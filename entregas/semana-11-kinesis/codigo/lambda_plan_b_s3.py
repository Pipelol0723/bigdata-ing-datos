"""Plan B del Laboratorio 5 (sólo si Firehose no acepta LabRole en el Learner Lab).

Lambda que lee del stream y escribe cada lote como JSON Lines en S3, con el mismo particionado
que el Firehose de la guía: s3://<BUCKET>/sensores/anio=YYYY/mes=MM/dia=DD/<request-id>.json
"""
import base64
import os
from datetime import datetime, timezone

import boto3

s3 = boto3.client("s3")


def lambda_handler(event, context):
    lineas = []
    for registro in event["Records"]:
        payload = base64.b64decode(registro["kinesis"]["data"]).decode("utf-8")
        lineas += [l for l in payload.strip().splitlines() if l]
    ahora = datetime.now(timezone.utc)
    clave = f"sensores/anio={ahora:%Y}/mes={ahora:%m}/dia={ahora:%d}/{context.aws_request_id}.json"
    s3.put_object(Bucket=os.environ["BUCKET"], Key=clave, Body=("\n".join(lineas) + "\n").encode("utf-8"))
    return {"batchItemFailures": []}
