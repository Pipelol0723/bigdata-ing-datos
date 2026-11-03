"""Ejercicio 5: consumidor que sobrevive a un reshard.

    python3 consumidor_reshard.py --stream ej-reshard --esperados totales.json [--csv shards.csv]

Después de `update_shard_count`, los shards viejos quedan CERRADOS (tienen EndingSequenceNumber) y
los nuevos apuntan a su padre (ParentShardId). Para no perder ni desordenar registros:
1. un shard se lee recién cuando su padre (y su padre adyacente, si hubo merge) se leyó entero;
2. un shard cerrado se lee hasta que NextShardIterator llega vacío; ahí se pasa a los hijos.

Cada evento trae `n`, un contador por clave puesto por el productor: si el orden por clave se
respeta, `n` sólo crece. Al final se compara contra lo que el productor dice haber enviado.
"""
import argparse
import csv
import json
import time

from comun import PAUSA_LECTURA_SEGURA, esta_cerrado, iterador, kinesis, listar_shards

ap = argparse.ArgumentParser()
ap.add_argument("--stream", required=True)
ap.add_argument("--esperados", help="JSON del productor (--resumen) con los totales por clave")
ap.add_argument("--csv", help="detalle por shard")
args = ap.parse_args()

shards = listar_shards(args.stream)
ids = {s["ShardId"] for s in shards}
print(f"{'shard':22} {'estado':8} {'padre':22} {'padre adyacente':22}")
for s in shards:
    print(f"{s['ShardId']:22} {'cerrado' if esta_cerrado(s) else 'abierto':8} "
          f"{s.get('ParentShardId', '-'):22} {s.get('AdjacentParentShardId', '-'):22}")

leidos, pendientes = set(), list(shards)
ultimo_n, vistos = {}, set()
total = desordenes = 0
detalle = []
while pendientes:
    # un shard está listo cuando sus padres (si siguen en el stream) ya se leyeron enteros
    listos = [s for s in pendientes
              if all(p not in ids or p in leidos for p in (s.get("ParentShardId"), s.get("AdjacentParentShardId")) if p)]
    for s in listos:
        pendientes.remove(s)
        it, n_shard, vacias = iterador(args.stream, s["ShardId"], "TRIM_HORIZON"), 0, 0
        while it:
            r = kinesis.get_records(ShardIterator=it, Limit=10000)
            al_dia = not r["Records"] and r.get("MillisBehindLatest", 0) == 0
            vacias = vacias + 1 if al_dia else 0
            if esta_cerrado(s) and vacias >= 3:
                break  # resguardo: algunos emuladores nunca devuelven el iterador vacío al final
            for rec in r["Records"]:
                e = json.loads(rec["Data"])
                clave, n = e["contenedor_id"], e["n"]
                if n <= ultimo_n.get(clave, 0):
                    desordenes += 1
                ultimo_n[clave] = max(n, ultimo_n.get(clave, 0))
                vistos.add((clave, n))
                total += 1
                n_shard += 1
            it = r.get("NextShardIterator")  # None cuando un shard cerrado se agotó
            if not esta_cerrado(s) and not r["Records"] and r.get("MillisBehindLatest", 0) == 0:
                break  # shard abierto: se para al llegar a la punta
            time.sleep(PAUSA_LECTURA_SEGURA)
        leidos.add(s["ShardId"])
        detalle.append([s["ShardId"], "cerrado" if esta_cerrado(s) else "abierto",
                        s.get("ParentShardId", ""), n_shard])
        print(f"leído {s['ShardId']} ({'cerrado' if esta_cerrado(s) else 'abierto'}): {n_shard} registros", flush=True)

print(f"\nLeídos: {total} · únicos: {len(vistos)} · duplicados: {total - len(vistos)} · "
      f"registros fuera de orden por clave: {desordenes}")
if args.esperados:
    esperados = json.load(open(args.esperados))
    faltan = sum(1 for k, cant in esperados["por_clave"].items() for n in range(1, cant + 1)
                 if (k, n) not in vistos)
    print(f"Enviados según el productor: {esperados['enviados']} · faltantes: {faltan}")
if args.csv:
    with open(args.csv, "w", newline="") as fh:
        w = csv.writer(fh)
        w.writerow(["shard", "estado", "padre", "registros"])
        w.writerows(detalle)
