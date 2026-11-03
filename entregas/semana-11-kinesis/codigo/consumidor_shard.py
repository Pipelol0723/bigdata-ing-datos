"""Ejercicios 2 y 3: consumidor de UN shard con GetRecords.

    python3 consumidor_shard.py --stream S --indice-shard 0 --pausa 1.0 --nombre c1 --desde LATEST
                                [--segundos 60] [--csv log.csv] [--resumen resumen.csv]

Cuenta los registros recibidos por segundo y las ProvisionedThroughputExceededException (el límite
de 5 GetRecords/s y 2 MB/s es por shard, compartido entre todos los consumidores). Ante el límite
espera y reintenta con el mismo iterador: no se cae ni pierde la posición.
"""
import argparse
import csv
import os
import time

from comun import iterador, kinesis, shards_abiertos

ap = argparse.ArgumentParser()
ap.add_argument("--stream", required=True)
ap.add_argument("--indice-shard", type=int, default=0)
ap.add_argument("--pausa", type=float, default=1.0, help="segundos entre lecturas")
ap.add_argument("--nombre", default="consumidor")
ap.add_argument("--desde", default="LATEST", choices=["LATEST", "TRIM_HORIZON"])
ap.add_argument("--segundos", type=int, default=60)
ap.add_argument("--csv", help="log por segundo")
ap.add_argument("--resumen", help="CSV compartido: una fila por consumidor")
ap.add_argument("--etiqueta", default="", help="nombre de la corrida, para el resumen")
args = ap.parse_args()

shards = sorted(shards_abiertos(args.stream), key=lambda s: int(s["HashKeyRange"]["StartingHashKey"]))
shard_id = shards[args.indice_shard]["ShardId"]
it = iterador(args.stream, shard_id, args.desde)

log = csv.writer(open(args.csv, "w", newline="")) if args.csv else None
if log:
    log.writerow(["segundo", "registros", "errores_limite", "llamadas"])

inicio = time.monotonic()
seg_actual, reg_seg, err_seg, llam_seg = 1, 0, 0, 0
total_reg = total_err = total_llam = 0
while True:
    ahora = time.monotonic() - inicio
    while ahora >= seg_actual:  # cerrar el segundo (o los segundos) que pasaron
        print(f"{args.nombre} t={seg_actual:3d}s registros={reg_seg} errores={err_seg}", flush=True)
        if log:
            log.writerow([seg_actual, reg_seg, err_seg, llam_seg])
        seg_actual, reg_seg, err_seg, llam_seg = seg_actual + 1, 0, 0, 0
    if ahora >= args.segundos:
        break
    try:
        llam_seg += 1
        total_llam += 1
        r = kinesis.get_records(ShardIterator=it, Limit=10000)
        reg_seg += len(r["Records"])
        total_reg += len(r["Records"])
        it = r["NextShardIterator"]
    except kinesis.exceptions.ProvisionedThroughputExceededException:
        err_seg += 1
        total_err += 1
    time.sleep(args.pausa)

dur = args.segundos
print(f"RESUMEN {args.nombre}: shard={shard_id} registros={total_reg} ({total_reg / dur:.1f}/s) "
      f"errores={total_err} llamadas={total_llam} ({total_llam / dur:.2f}/s)", flush=True)
if args.resumen:
    nuevo = not os.path.exists(args.resumen)
    with open(args.resumen, "a", newline="") as f:
        w = csv.writer(f)
        if nuevo:
            w.writerow(["corrida", "consumidor", "shard", "pausa", "segundos", "registros", "registros_por_s",
                        "errores_limite", "llamadas_por_s"])
        w.writerow([args.etiqueta, args.nombre, shard_id, args.pausa, dur, total_reg, round(total_reg / dur, 1),
                    total_err, round(total_llam / dur, 2)])
