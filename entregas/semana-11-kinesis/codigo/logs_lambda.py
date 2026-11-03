"""Cuenta invocaciones, alertas y OK de una Lambda leyendo su log group de CloudWatch Logs.

    python3 logs_lambda.py --funcion procesar-sensores --desde-ms 1730000000000 [--etiqueta batch100]
"""
import argparse
import time

import boto3

ap = argparse.ArgumentParser()
ap.add_argument("--funcion", required=True)
ap.add_argument("--desde-ms", type=int, required=True)
ap.add_argument("--etiqueta", default="")
args = ap.parse_args()

logs = boto3.client("logs", region_name="us-east-1")
grupo = f"/aws/lambda/{args.funcion}"
invocaciones = alertas = ok = 0
ejemplos, token = [], None
while True:
    kw = {"logGroupName": grupo, "startTime": args.desde_ms, "endTime": int(time.time() * 1000)}
    if token:
        kw["nextToken"] = token
    r = logs.filter_log_events(**kw)
    for e in r["events"]:
        m = e["message"]
        if m.startswith("START RequestId"):
            invocaciones += 1
        elif m.startswith("ALERTA"):
            alertas += 1
            if len(ejemplos) < 5:
                ejemplos.append(m.strip())
        elif m.startswith("OK "):
            ok += 1
    token = r.get("nextToken")
    if not token:
        break

print(f"RESUMEN {args.etiqueta}: invocaciones={invocaciones} registros={alertas + ok} alertas={alertas} ok={ok}")
for m in ejemplos:
    print("  ", m)
