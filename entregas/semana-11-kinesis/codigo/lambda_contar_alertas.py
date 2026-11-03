"""Reto final del taller, punto 2: segunda Lambda que cuenta alertas por contenedor.

Por cada lote que le entrega el stream escribe un resumen en S3:
    s3://<BUCKET>/resumen-alertas/fecha=YYYY-MM-DD/<request-id>.json
El nombre del objeto es el id de la invocación: si Lambda reintenta el mismo lote, sobrescribe el
mismo archivo en vez de duplicar el conteo (idempotencia, por la entrega "al menos una vez").
"""
import base64
import json
import os
from collections import Counter
from datetime import datetime, timezone

import boto3

UMBRAL = 8.0  # °C
s3 = boto3.client("s3")


def lambda_handler(event, context):
    alertas, registros = Counter(), 0
    for registro in event["Records"]:
        payload = base64.b64decode(registro["kinesis"]["data"]).decode("utf-8")
        for linea in payload.strip().splitlines():
            e = json.loads(linea)
            registros += 1
            if e["temperatura"] > UMBRAL:
                alertas[e["contenedor_id"]] += 1
    ahora = datetime.now(timezone.utc)
    resumen = {
        "lote": context.aws_request_id,
        "primer_numero_secuencia": event["Records"][0]["kinesis"]["sequenceNumber"],
        "registros": registros,
        "alertas_por_contenedor": dict(sorted(alertas.items())),
        "total_alertas": sum(alertas.values()),
        "generado": ahora.isoformat(),
    }
    s3.put_object(
        Bucket=os.environ["BUCKET"],
        Key=f"resumen-alertas/fecha={ahora:%Y-%m-%d}/{context.aws_request_id}.json",
        Body=json.dumps(resumen).encode("utf-8"),
        ContentType="application/json",
    )
    return {"batchItemFailures": []}
