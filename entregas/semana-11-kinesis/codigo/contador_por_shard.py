"""Ejercicio 4 (y reto del taller): cuántos registros hay en cada shard.

    python3 contador_por_shard.py --stream S [--desde-ts ISO] [--etiqueta A] [--csv salida.csv]

Lee todos los shards desde TRIM_HORIZON, o desde un instante con AT_TIMESTAMP para contar sólo una
corrida, hasta alcanzar la punta del stream (MillisBehindLatest = 0). Una respuesta vacía no alcanza
para saber que se terminó: GetRecords puede volver vacío aunque falten datos más adelante.
"""
import argparse
import csv
import os
import time
from collections import Counter
from datetime import datetime

from comun import PAUSA_LECTURA_SEGURA, iterador, kinesis, listar_shards

ap = argparse.ArgumentParser()
ap.add_argument("--stream", required=True)
ap.add_argument("--desde-ts", help="ISO 8601: contar sólo desde ese instante")
ap.add_argument("--etiqueta", default="")
ap.add_argument("--csv", help="CSV acumulativo: una fila por shard")
args = ap.parse_args()

ts = datetime.fromisoformat(args.desde_ts) if args.desde_ts else None
filas, total = [], 0
for shard in listar_shards(args.stream):
    it = iterador(args.stream, shard["ShardId"], "AT_TIMESTAMP" if ts else "TRIM_HORIZON", ts)
    claves = Counter()
    while it:
        r = kinesis.get_records(ShardIterator=it, Limit=10000)
        for rec in r["Records"]:
            claves[rec["PartitionKey"]] += 1
        it = r.get("NextShardIterator")
        if not r["Records"] and r.get("MillisBehindLatest", 0) == 0:
            break
        time.sleep(PAUSA_LECTURA_SEGURA)
    n = sum(claves.values())
    total += n
    top = claves.most_common(1)[0] if claves else ("-", 0)
    filas.append([args.etiqueta, shard["ShardId"], n, len(claves), top[0], top[1]])

print(f"{'corrida':8} {'shard':22} {'registros':>9} {'%':>6} {'claves':>6}  clave más frecuente")
for f in filas:
    pct = 100 * f[2] / total if total else 0
    f.insert(3, round(pct, 1))
    print(f"{f[0]:8} {f[1]:22} {f[2]:9d} {pct:6.1f} {f[4]:6d}  {f[5]} ({f[6]})")
print(f"TOTAL {total}")

if args.csv:
    nuevo = not os.path.exists(args.csv)
    with open(args.csv, "a", newline="") as fh:
        w = csv.writer(fh)
        if nuevo:
            w.writerow(["corrida", "shard", "registros", "porcentaje", "claves_distintas", "clave_top",
                        "registros_clave_top"])
        w.writerows(filas)
