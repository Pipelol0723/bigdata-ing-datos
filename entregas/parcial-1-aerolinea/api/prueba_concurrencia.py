"""Prueba de concurrencia sobre el último asiento — evidencia para 5.6.

Reproduce el escenario textual del enunciado:

    "Si dos pasajeros intentan reservar el último asiento disponible al mismo
     tiempo, ¿qué debe garantizar el sistema?"

Verifica NFR-CONC-01: con N solicitudes simultáneas sobre M asientos (N > M),
se confirman EXACTAMENTE M. Nunca M+1.

Uso:
    python prueba_concurrencia.py --peticiones 30
    python prueba_concurrencia.py --peticiones 30 --etiqueta sin-lock

El script no decide el modo: eso lo fija la variable MODO_INSEGURO con la que
se levantó la API. Acá sólo se mide y se registra qué pasó.
"""
from __future__ import annotations

import argparse
import json
import os
import threading
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import httpx
import psycopg
from psycopg.rows import dict_row

# La MISMA variable que usa la API (config.py). Antes estaba fija al Docker
# local: con la API apuntando a RDS, la prueba preparaba y verificaba la
# instancia en otra base, y el resultado no tenía sentido. La prueba tiene que
# mirar exactamente la base contra la que corre la API.
DSN = os.environ.get(
    "DSN_OLTP", "postgresql://parcial:parcial_local_dev@127.0.0.1:15432/aerolinea"
)
DIR_EVIDENCIA = Path(__file__).resolve().parents[1] / "evidencia" / "concurrencia"


def preparar_instancia(capacidad: int = 1) -> dict:
    """Deja una instancia de vuelo con exactamente `capacidad` asientos libres."""
    with psycopg.connect(DSN, row_factory=dict_row) as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT iv.id_instancia
                 FROM reservas.instancia_vuelo iv
                 JOIN reservas.vuelo_programado vp USING (id_vuelo_prog)
                WHERE vp.numero_vuelo = 'AV8020'
                  AND iv.fecha_operacion > CURRENT_DATE + 5
                ORDER BY iv.fecha_operacion LIMIT 1"""
        )
        id_inst = cur.fetchone()["id_instancia"]

        # Borra reservas previas de esa instancia para partir de cero
        cur.execute(
            """DELETE FROM reservas.reserva r
                WHERE r.id_reserva IN (
                    SELECT i.id_reserva FROM reservas.itinerario i
                    JOIN reservas.tramo t ON t.id_itinerario = i.id_itinerario
                    WHERE t.id_instancia = %s)""",
            (id_inst,),
        )
        cur.execute(
            """UPDATE reservas.instancia_vuelo
                  SET capacidad_vendible_eco = %s,
                      asientos_comprometidos_eco = 0,
                      version = 0
                WHERE id_instancia = %s""",
            (capacidad, id_inst),
        )
        conn.commit()
    return {"id_instancia": id_inst, "capacidad": capacidad}


def estado_instancia(id_inst: int) -> dict:
    with psycopg.connect(DSN, row_factory=dict_row) as conn, conn.cursor() as cur:
        cur.execute(
            """SELECT capacidad_vendible_eco AS vendible,
                      asientos_comprometidos_eco AS comprometidos,
                      version
                 FROM reservas.instancia_vuelo WHERE id_instancia = %s""",
            (id_inst,),
        )
        inst = cur.fetchone()
        cur.execute(
            """SELECT count(*) AS reservas_vivas
                 FROM reservas.tramo t
                 JOIN reservas.itinerario i ON i.id_itinerario = t.id_itinerario
                 JOIN reservas.reserva r    ON r.id_reserva = i.id_reserva
                WHERE t.id_instancia = %s
                  AND r.estado IN ('retenida','confirmada')""",
            (id_inst,),
        )
        inst["reservas_vivas"] = cur.fetchone()["reservas_vivas"]
    return inst


def disparar(url: str, id_inst: int, n: int) -> list[dict]:
    """Lanza n peticiones que arrancan TODAS a la vez.

    La barrera es lo que hace real la carrera: sin ella las peticiones salen
    escalonadas y el conflicto nunca se manifiesta.
    """
    barrera = threading.Barrier(n)
    resultados: list[dict] = []
    lock = threading.Lock()

    def una(i: int) -> None:
        cuerpo = {
            "id_pasajero": (i % 5) + 1,
            "tramos": [{"id_instancia": id_inst, "clase": "economica"}],
        }
        barrera.wait()
        try:
            with httpx.Client(timeout=30.0) as cli:
                r = cli.post(f"{url}/reservas", json=cuerpo)
            item = {"i": i, "status": r.status_code}
            if r.status_code == 201:
                item["codigo"] = r.json().get("codigo_reserva")
                item["intentos"] = r.json().get("intentos")
            else:
                item["detalle"] = str(r.json().get("detail"))[:120]
        except Exception as exc:  # noqa: BLE001
            item = {"i": i, "status": "excepcion", "detalle": str(exc)[:120]}
        with lock:
            resultados.append(item)

    hilos = [threading.Thread(target=una, args=(i,)) for i in range(n)]
    for h in hilos:
        h.start()
    for h in hilos:
        h.join()
    return sorted(resultados, key=lambda x: x["i"])


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--url", default="http://127.0.0.1:8010")
    ap.add_argument("--peticiones", type=int, default=30)
    ap.add_argument("--capacidad", type=int, default=1)
    ap.add_argument("--etiqueta", default="con-lock")
    args = ap.parse_args()

    modo_api = httpx.get(f"{args.url}/salud", timeout=10).json()["modo_inventario"]

    print("=" * 66)
    print(f" PRUEBA DE CONCURRENCIA — NFR-CONC-01")
    print(f" modo de la API: {modo_api.upper()}   etiqueta: {args.etiqueta}")
    print("=" * 66)

    inicial = preparar_instancia(args.capacidad)
    id_inst = inicial["id_instancia"]
    print(f"\nInstancia {id_inst}: {args.capacidad} asiento(s) vendible(s), 0 comprometidos")
    print(f"Lanzando {args.peticiones} peticiones SIMULTÁNEAS...\n")

    resultados = disparar(args.url, id_inst, args.peticiones)
    final = estado_instancia(id_inst)

    conteo = Counter(str(r["status"]) for r in resultados)
    exitosas = conteo.get("201", 0)
    rechazos = conteo.get("409", 0)

    print("Respuestas HTTP:")
    for cod, n in sorted(conteo.items()):
        etiqueta = {"201": "reserva creada", "409": "rechazo explícito (sin cupo)",
                    "503": "contención tras reintentos", "500": "ERROR interno"}.get(cod, "")
        print(f"  {cod:>10} : {n:>3}   {etiqueta}")

    print(f"\nEstado final de la instancia:")
    print(f"  capacidad vendible ...... {final['vendible']}")
    print(f"  asientos comprometidos .. {final['comprometidos']}")
    print(f"  reservas vivas .......... {final['reservas_vivas']}")
    print(f"  version ................. {final['version']}")

    sobreventa = final["comprometidos"] > final["vendible"]
    coherente = exitosas == final["comprometidos"] == final["reservas_vivas"]

    print("\n" + "-" * 66)
    if sobreventa:
        print(f"  [FALLA] SOBREVENTA: {final['comprometidos']} comprometidos sobre "
              f"{final['vendible']} vendibles")
        veredicto = "SOBREVENTA"
    elif exitosas == args.capacidad and coherente:
        print(f"  [OK] CORRECTO: exactamente {exitosas} de {args.peticiones} "
              f"solicitudes prosperaron")
        print(f"     Las otras {rechazos} recibieron rechazo explícito (409), "
              f"no un error genérico")
        veredicto = "CORRECTO"
    else:
        print(f"  [!] INCONSISTENTE: {exitosas} respuestas 201 pero "
              f"{final['comprometidos']} comprometidos")
        veredicto = "INCONSISTENTE"
    print("-" * 66)

    DIR_EVIDENCIA.mkdir(parents=True, exist_ok=True)
    salida = {
        "momento": datetime.now(timezone.utc).isoformat(),
        "etiqueta": args.etiqueta,
        "modo_api": modo_api,
        "peticiones": args.peticiones,
        "capacidad_inicial": args.capacidad,
        "respuestas": dict(conteo),
        "estado_final": {k: int(v) for k, v in final.items()},
        "veredicto": veredicto,
        "detalle": resultados,
    }
    destino = DIR_EVIDENCIA / f"resultado-{args.etiqueta}.json"
    destino.write_text(json.dumps(salida, indent=2, ensure_ascii=False), encoding="utf-8")
    print(f"\nEvidencia escrita en: {destino.relative_to(DIR_EVIDENCIA.parents[1])}")


if __name__ == "__main__":
    main()
