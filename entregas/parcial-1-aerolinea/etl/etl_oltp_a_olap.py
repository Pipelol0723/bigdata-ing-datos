"""ETL: OLTP transaccional → OLAP dimensional.

Sección 5.7 del enunciado. Copia y TRANSFORMA (no copia tal cual) los datos
que responden las tres preguntas de negocio de FR-19:

    · ocupación por ruta
    · ingresos por tarifa
    · patrones de cancelación

ESTRATEGIA DE CARGA: recarga completa (TRUNCATE + INSERT).
    A este volumen es lo correcto: es idempotente, no arrastra estado y no
    puede quedar a medias. La alternativa —carga incremental por marca de
    agua sobre `historial_reserva.ocurrido_en`— sólo se justifica cuando la
    recarga deja de entrar en la ventana de proceso. Se documenta en 5.7
    como la evolución prevista, no como algo pendiente.

Uso:
    python etl_oltp_a_olap.py
    python etl_oltp_a_olap.py --dsn-oltp ... --dsn-olap ...

Las mismas variables de entorno sirven para apuntar a las RDS de AWS sin
tocar el código.
"""
from __future__ import annotations

import argparse
import os
import sys
import time
from datetime import date

import psycopg
from psycopg.rows import dict_row

DSN_OLTP = os.environ.get(
    "DSN_OLTP", "postgresql://parcial:parcial_local_dev@127.0.0.1:15432/aerolinea"
)
DSN_OLAP = os.environ.get(
    "DSN_OLAP", "postgresql://parcial:parcial_local_dev@127.0.0.1:15433/aerolinea_dw"
)

MESES = ["", "enero", "febrero", "marzo", "abril", "mayo", "junio", "julio",
         "agosto", "septiembre", "octubre", "noviembre", "diciembre"]
DIAS = ["lunes", "martes", "miércoles", "jueves", "viernes", "sábado", "domingo"]
# Temporada alta en Colombia: vacaciones escolares y fin de año
MESES_TEMPORADA_ALTA = {1, 6, 7, 12}
MESES_TEMPORADA_MEDIA = {4, 10}


def ventana_compra(dias_min: int) -> str:
    if dias_min >= 21:
        return "anticipada"
    if dias_min >= 7:
        return "intermedia"
    return "ultima_hora"


def franja_horaria(hora) -> str:
    h = hora.hour
    if h < 6:
        return "madrugada"
    if h < 12:
        return "mañana"
    if h < 18:
        return "tarde"
    return "noche"


def temporada(mes: int) -> str:
    if mes in MESES_TEMPORADA_ALTA:
        return "alta"
    if mes in MESES_TEMPORADA_MEDIA:
        return "media"
    return "baja"


def id_fecha(d: date) -> int:
    return d.year * 10000 + d.month * 100 + d.day


# ---------------------------------------------------------------------------
def cargar_dim_fecha(cur_olap, desde: date, hasta: date) -> int:
    filas = []
    dia = desde
    while dia <= hasta:
        filas.append((
            id_fecha(dia), dia, dia.year, (dia.month - 1) // 3 + 1, dia.month,
            MESES[dia.month], dia.day, dia.isoweekday(), DIAS[dia.isoweekday() - 1],
            dia.isoweekday() >= 6, temporada(dia.month),
        ))
        dia = date.fromordinal(dia.toordinal() + 1)
    cur_olap.executemany(
        """INSERT INTO dw.dim_fecha
             (id_fecha, fecha, anio, trimestre, mes, nombre_mes, dia,
              dia_semana, nombre_dia, es_fin_semana, temporada)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
        filas,
    )
    return len(filas)


def cargar_dim_ruta(cur_oltp, cur_olap) -> int:
    cur_oltp.execute(
        """SELECT r.id_ruta, r.origen, ao.ciudad AS origen_ciudad, ao.pais AS origen_pais,
                  r.destino, ad.ciudad AS destino_ciudad, ad.pais AS destino_pais,
                  r.duracion_estimada_min
             FROM reservas.ruta r
             JOIN reservas.aeropuerto ao ON ao.codigo_iata = r.origen
             JOIN reservas.aeropuerto ad ON ad.codigo_iata = r.destino"""
    )
    filas = [
        (f["id_ruta"], f["origen"], f["origen_ciudad"], f["origen_pais"],
         f["destino"], f["destino_ciudad"], f["destino_pais"],
         f"{f['origen']}-{f['destino']}", f["duracion_estimada_min"],
         f["origen_pais"] != f["destino_pais"])
        for f in cur_oltp.fetchall()
    ]
    cur_olap.executemany(
        """INSERT INTO dw.dim_ruta
             (id_ruta_dw, origen_iata, origen_ciudad, origen_pais,
              destino_iata, destino_ciudad, destino_pais,
              ruta_descripcion, duracion_min, es_internacional)
           VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
        filas,
    )
    return len(filas)


def cargar_dim_vuelo(cur_oltp, cur_olap) -> int:
    cur_oltp.execute(
        """SELECT id_vuelo_prog, numero_vuelo, id_ruta, hora_salida_local
             FROM reservas.vuelo_programado"""
    )
    filas = [
        (f["id_vuelo_prog"], f["numero_vuelo"], f["id_ruta"],
         f["hora_salida_local"], franja_horaria(f["hora_salida_local"]))
        for f in cur_oltp.fetchall()
    ]
    cur_olap.executemany(
        """INSERT INTO dw.dim_vuelo
             (id_vuelo_dw, numero_vuelo, id_ruta_dw, hora_salida, franja_horaria)
           VALUES (%s,%s,%s,%s,%s)""",
        filas,
    )
    return len(filas)


def cargar_dim_tarifa(cur_oltp, cur_olap) -> int:
    cur_oltp.execute(
        """SELECT id_tarifa, clase::text, antelacion_min_dias, antelacion_max_dias,
                  precio_base, moneda FROM reservas.tarifa"""
    )
    filas = [
        (f["id_tarifa"], f["clase"], f["antelacion_min_dias"], f["antelacion_max_dias"],
         ventana_compra(f["antelacion_min_dias"]), f["precio_base"], f["moneda"])
        for f in cur_oltp.fetchall()
    ]
    cur_olap.executemany(
        """INSERT INTO dw.dim_tarifa
             (id_tarifa_dw, clase, antelacion_min_dias, antelacion_max_dias,
              ventana_compra, precio_base, moneda)
           VALUES (%s,%s,%s,%s,%s,%s,%s)""",
        filas,
    )
    return len(filas)


def cargar_dim_canal(cur_oltp, cur_olap) -> int:
    # id_canal = 0 representa la venta directa: evita NULLs en la clave foránea
    # del hecho, que complicarían todos los joins de los reportes.
    filas = [(0, "directo", None, None)]
    cur_oltp.execute("SELECT id_agencia, nombre, porcentaje_comision FROM reservas.agencia")
    filas += [(f["id_agencia"], "agencia", f["nombre"], f["porcentaje_comision"])
              for f in cur_oltp.fetchall()]
    cur_olap.executemany(
        """INSERT INTO dw.dim_canal (id_canal, tipo_canal, nombre_agencia, porcentaje_comision)
           VALUES (%s,%s,%s,%s)""",
        filas,
    )
    return len(filas)


def cargar_dim_estado(cur_olap) -> int:
    filas = [
        (1, "retenida",   False, False, False),
        (2, "confirmada", True,  False, False),
        (3, "cancelada",  False, True,  False),
        (4, "expirada",   False, False, True),
    ]
    cur_olap.executemany(
        """INSERT INTO dw.dim_estado_reserva
             (id_estado, estado, es_vendida, es_cancelada, es_expirada)
           VALUES (%s,%s,%s,%s,%s)""",
        filas,
    )
    return len(filas)


# ---------------------------------------------------------------------------
def cargar_fact_tramo(cur_oltp, cur_olap) -> int:
    """Grano: un tramo vendido. La transformación resuelve acá los cinco joins
    que cada reporte tendría que hacer contra el OLTP."""
    cur_oltp.execute(
        """
        SELECT t.id_tramo,
               iv.fecha_operacion,
               r.creada_en::date              AS fecha_reserva,
               vp.id_ruta,
               vp.id_vuelo_prog,
               t.id_tarifa,
               COALESCE(r.id_agencia, 0)      AS id_canal,
               CASE r.estado WHEN 'retenida' THEN 1 WHEN 'confirmada' THEN 2
                             WHEN 'cancelada' THEN 3 ELSE 4 END AS id_estado,
               t.precio_aplicado,
               COALESCE(cm.monto, 0)          AS comision,
               (iv.fecha_operacion - r.creada_en::date) AS dias_antelacion,
               CASE WHEN r.estado = 'confirmada' THEN t.precio_aplicado ELSE 0 END
                                              AS ingreso_realizado
          FROM reservas.tramo t
          JOIN reservas.itinerario i       ON i.id_itinerario = t.id_itinerario
          JOIN reservas.reserva r          ON r.id_reserva = i.id_reserva
          JOIN reservas.instancia_vuelo iv ON iv.id_instancia = t.id_instancia
          JOIN reservas.vuelo_programado vp ON vp.id_vuelo_prog = iv.id_vuelo_prog
          LEFT JOIN reservas.comision cm   ON cm.id_reserva = r.id_reserva
        """
    )
    filas = [
        (f["id_tramo"], id_fecha(f["fecha_operacion"]), id_fecha(f["fecha_reserva"]),
         f["id_ruta"], f["id_vuelo_prog"], f["id_tarifa"], f["id_canal"], f["id_estado"],
         1, f["precio_aplicado"], f["comision"],
         max(f["dias_antelacion"], 0), f["ingreso_realizado"])
        for f in cur_oltp.fetchall()
    ]
    if filas:
        cur_olap.executemany(
            """INSERT INTO dw.fact_tramo_vendido
                 (id_tramo_dw, id_fecha_vuelo, id_fecha_reserva, id_ruta_dw,
                  id_vuelo_dw, id_tarifa_dw, id_canal, id_estado,
                  asientos, ingreso, comision, dias_antelacion, ingreso_realizado)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s)""",
            filas,
        )
    return len(filas)


def cargar_fact_ocupacion(cur_oltp, cur_olap) -> int:
    """Grano: una instancia de vuelo.

    Incluye los vuelos que NO vendieron nada — que son exactamente los que un
    hecho a grano de tramo perdería, y sin los cuales la ocupación promedio
    saldría inflada.
    """
    cur_oltp.execute(
        """
        SELECT iv.id_instancia, iv.fecha_operacion, vp.id_ruta, vp.id_vuelo_prog,
               iv.capacidad_vendible_eco + iv.capacidad_vendible_bus AS capacidad,
               iv.asientos_comprometidos_eco + iv.asientos_comprometidos_bus AS vendidos,
               COALESCE((SELECT sum(t.precio_aplicado)
                           FROM reservas.tramo t
                           JOIN reservas.itinerario i ON i.id_itinerario = t.id_itinerario
                           JOIN reservas.reserva r    ON r.id_reserva = i.id_reserva
                          WHERE t.id_instancia = iv.id_instancia
                            AND r.estado = 'confirmada'), 0) AS ingreso
          FROM reservas.instancia_vuelo iv
          JOIN reservas.vuelo_programado vp ON vp.id_vuelo_prog = iv.id_vuelo_prog
        """
    )
    filas = []
    for f in cur_oltp.fetchall():
        cap = f["capacidad"] or 0
        filas.append((
            f["id_instancia"], id_fecha(f["fecha_operacion"]), f["id_ruta"],
            f["id_vuelo_prog"], cap, f["vendidos"],
            round(f["vendidos"] / cap, 4) if cap else 0,  # sin división por cero
            f["ingreso"],
        ))
    if filas:
        cur_olap.executemany(
            """INSERT INTO dw.fact_ocupacion_vuelo
                 (id_instancia_dw, id_fecha, id_ruta_dw, id_vuelo_dw,
                  capacidad_vendible, asientos_vendidos, factor_ocupacion, ingreso_vuelo)
               VALUES (%s,%s,%s,%s,%s,%s,%s,%s)""",
            filas,
        )
    return len(filas)


# ---------------------------------------------------------------------------
def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn-oltp", default=DSN_OLTP)
    ap.add_argument("--dsn-olap", default=DSN_OLAP)
    args = ap.parse_args()

    t0 = time.time()
    print("=" * 62)
    print(" ETL  OLTP -> OLAP   (seccion 5.7)")
    print("=" * 62)

    with psycopg.connect(args.dsn_oltp, row_factory=dict_row) as c_oltp, \
         psycopg.connect(args.dsn_olap, row_factory=dict_row) as c_olap:

        cur_oltp = c_oltp.cursor()
        cur_olap = c_olap.cursor()

        cur_olap.execute(
            "INSERT INTO dw.etl_ejecucion (estado) VALUES ('en_curso') RETURNING id_ejecucion"
        )
        id_ejec = cur_olap.fetchone()["id_ejecucion"]
        c_olap.commit()

        try:
            # Rango de fechas a cubrir: vuelos y reservas
            cur_oltp.execute(
                """SELECT LEAST(min(iv.fecha_operacion), min(r.creada_en::date)) AS d0,
                          GREATEST(max(iv.fecha_operacion), max(r.creada_en::date)) AS d1
                     FROM reservas.instancia_vuelo iv
                     LEFT JOIN reservas.reserva r ON TRUE"""
            )
            rango = cur_oltp.fetchone()
            d0 = rango["d0"] or date.today()
            d1 = rango["d1"] or date.today()

            # Recarga completa: primero hechos (por las FK), después dimensiones
            cur_olap.execute(
                "TRUNCATE dw.fact_tramo_vendido, dw.fact_ocupacion_vuelo, "
                "dw.dim_vuelo, dw.dim_ruta, dw.dim_tarifa, dw.dim_canal, "
                "dw.dim_estado_reserva, dw.dim_fecha RESTART IDENTITY CASCADE"
            )

            dims = 0
            dims += cargar_dim_fecha(cur_olap, d0, d1);      print(f"  dim_fecha ............ {dims}")
            n = cargar_dim_ruta(cur_oltp, cur_olap);    dims += n; print(f"  dim_ruta ............. {n}")
            n = cargar_dim_vuelo(cur_oltp, cur_olap);   dims += n; print(f"  dim_vuelo ............ {n}")
            n = cargar_dim_tarifa(cur_oltp, cur_olap);  dims += n; print(f"  dim_tarifa ........... {n}")
            n = cargar_dim_canal(cur_oltp, cur_olap);   dims += n; print(f"  dim_canal ............ {n}")
            n = cargar_dim_estado(cur_olap);            dims += n; print(f"  dim_estado_reserva ... {n}")

            f1 = cargar_fact_tramo(cur_oltp, cur_olap)
            print(f"  fact_tramo_vendido ... {f1}")
            f2 = cargar_fact_ocupacion(cur_oltp, cur_olap)
            print(f"  fact_ocupacion_vuelo . {f2}")

            cur_olap.execute(
                """UPDATE dw.etl_ejecucion
                      SET finalizada_en = now(), estado = 'ok',
                          filas_hechos = %s, filas_dims = %s
                    WHERE id_ejecucion = %s""",
                (f1 + f2, dims, id_ejec),
            )
            c_olap.commit()

            print("-" * 62)
            print(f"  OK  {dims} filas de dimensiones, {f1 + f2} de hechos "
                  f"en {time.time() - t0:.2f}s")
            print("-" * 62)
            return 0

        except Exception as exc:  # noqa: BLE001
            c_olap.rollback()
            cur_olap.execute(
                """UPDATE dw.etl_ejecucion
                      SET finalizada_en = now(), estado = 'error', detalle = %s
                    WHERE id_ejecucion = %s""",
                (str(exc)[:500], id_ejec),
            )
            c_olap.commit()
            print(f"  ERROR: {exc}", file=sys.stderr)
            return 1


if __name__ == "__main__":
    raise SystemExit(main())
