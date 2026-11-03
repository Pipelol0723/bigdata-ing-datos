"""Laboratorio 4 del taller: Lambda `procesar-sensores`, disparada por el stream (código de la guía)."""
import base64, json

UMBRAL = 8.0  # °C


def lambda_handler(event, context):
    for registro in event["Records"]:
        payload = base64.b64decode(registro["kinesis"]["data"]).decode("utf-8")
        for linea in payload.strip().splitlines():
            e = json.loads(linea)
            if e["temperatura"] > UMBRAL:
                print(f"ALERTA {e['contenedor_id']}: {e['temperatura']} °C")
            else:
                print(f"OK {e['contenedor_id']}: {e['temperatura']} °C")
    return {"batchItemFailures": []}
