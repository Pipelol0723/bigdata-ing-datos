"""Ejercicio 6 (opcional): enhanced fan-out.

    python3 efo.py --stream ej-compite --consumidores 2 --segundos 60 [--resumen resumen.csv]

Cada consumidor registrado recibe 2 MB/s dedicados por shard, por push (SubscribeToShard, HTTP/2):
no hace GetRecords, así que no compite por las 5 llamadas/s del shard. Una suscripción dura ~5 min
y hay que renovarla desde el último número de secuencia (ContinuationSequenceNumber).
Los consumidores registrados no se borran acá: se van con el stream (--enforce-consumer-deletion).
"""
import argparse
import csv
import os
import threading
import time

from comun import kinesis, listar_shards

ap = argparse.ArgumentParser()
ap.add_argument("--stream", required=True)
ap.add_argument("--consumidores", type=int, default=2)
ap.add_argument("--segundos", type=int, default=60)
ap.add_argument("--resumen")
args = ap.parse_args()

arn = kinesis.describe_stream_summary(StreamName=args.stream)["StreamDescriptionSummary"]["StreamARN"]
shard_id = listar_shards(args.stream)[0]["ShardId"]

consumidores = []
for i in range(1, args.consumidores + 1):
    nombre = f"efo-{i}"
    try:
        c = kinesis.register_stream_consumer(StreamARN=arn, ConsumerName=nombre)["Consumer"]
    except kinesis.exceptions.ResourceInUseException:
        c = kinesis.describe_stream_consumer(StreamARN=arn, ConsumerName=nombre)["ConsumerDescription"]
    consumidores.append(c)
for c in consumidores:  # tarda unos segundos en pasar a ACTIVE
    while kinesis.describe_stream_consumer(ConsumerARN=c["ConsumerARN"])["ConsumerDescription"]["ConsumerStatus"] != "ACTIVE":
        time.sleep(3)
print(f"[ok] {len(consumidores)} consumidores ACTIVE", flush=True)

resultados = {}


def leer(c):
    nombre, registros, errores, eventos = c["ConsumerName"], 0, 0, 0
    fin, posicion = time.monotonic() + args.segundos, {"Type": "LATEST"}
    while time.monotonic() < fin:
        try:
            r = kinesis.subscribe_to_shard(ConsumerARN=c["ConsumerARN"], ShardId=shard_id,
                                           StartingPosition=posicion)
            for ev in r["EventStream"]:
                if "SubscribeToShardEvent" in ev:
                    e = ev["SubscribeToShardEvent"]
                    registros += len(e["Records"])
                    eventos += 1
                    posicion = {"Type": "AFTER_SEQUENCE_NUMBER",
                                "SequenceNumber": e["ContinuationSequenceNumber"]}
                if time.monotonic() >= fin:
                    break
        except Exception as ex:  # el límite es 1 suscripción cada 5 s por consumidor-shard
            errores += 1
            print(f"{nombre}: {type(ex).__name__}: {str(ex)[:120]}", flush=True)
            time.sleep(5)
    resultados[nombre] = (registros, errores, eventos)


hilos = [threading.Thread(target=leer, args=(c,)) for c in consumidores]
[h.start() for h in hilos]
[h.join() for h in hilos]
for nombre, (reg, err, ev) in sorted(resultados.items()):
    print(f"RESUMEN {nombre}: registros={reg} ({reg / args.segundos:.1f}/s) eventos push={ev} errores={err}")
    if args.resumen:
        nuevo = not os.path.exists(args.resumen)
        with open(args.resumen, "a", newline="") as f:
            w = csv.writer(f)
            if nuevo:
                w.writerow(["corrida", "consumidor", "shard", "pausa", "segundos", "registros",
                            "registros_por_s", "errores_limite", "llamadas_por_s"])
            w.writerow(["EFO", nombre, shard_id, "push", args.segundos, reg, round(reg / args.segundos, 1), err, ""])
