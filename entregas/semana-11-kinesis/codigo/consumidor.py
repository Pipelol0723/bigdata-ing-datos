"""Laboratorio 3 del taller: consumidor manual con GetRecords.

El código de la guía lee para siempre; esta versión agrega lo necesario para comparar los tipos de
iterador y correr dos consumidores a la vez: el tipo de iterador, un tope de tiempo y un nombre.

    python3 consumidor.py --tipo TRIM_HORIZON|LATEST|AT_TIMESTAMP [--ts ISO] [--segundos 20] [--nombre c1]
"""
import argparse
import json
import time
from datetime import datetime

from comun import iterador, kinesis, listar_shards

ap = argparse.ArgumentParser()
ap.add_argument("--stream", default="taller-kinesis-sensores")
ap.add_argument("--tipo", default="TRIM_HORIZON", choices=["TRIM_HORIZON", "LATEST", "AT_TIMESTAMP"])
ap.add_argument("--ts", help="para AT_TIMESTAMP, en ISO 8601")
ap.add_argument("--segundos", type=float, default=20)
ap.add_argument("--nombre", default="consumidor")
args = ap.parse_args()

shard_id = listar_shards(args.stream)[0]["ShardId"]
ts = datetime.fromisoformat(args.ts) if args.ts else None
it = iterador(args.stream, shard_id, args.tipo, ts)

recibidos, primero, ultimo = 0, None, None
fin = time.monotonic() + args.segundos
while it and time.monotonic() < fin:
    salida = kinesis.get_records(ShardIterator=it, Limit=50)
    for r in salida["Records"]:
        evento = json.loads(r["Data"].decode("utf-8"))
        recibidos += 1
        primero = primero or evento["timestamp"]
        ultimo = evento["timestamp"]
    it = salida["NextShardIterator"]
    if not salida["Records"]:
        time.sleep(2)
    else:
        time.sleep(0.25)  # 5 GetRecords/s por shard, compartidas

print(f"RESUMEN,{args.nombre},{args.tipo},{recibidos},{primero},{ultimo}")
