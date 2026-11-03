"""Laboratorio 2 del taller: productor de eventos de sensores.

Es el código de la guía con tres argumentos opcionales, para reutilizarlo en el reto final:
    python3 productor.py [stream] [total] [clave]
    clave = contenedor (la de la guía) | constante | aleatoria
"""
import boto3, json, random, sys, time, uuid
from datetime import datetime, timezone

STREAM = sys.argv[1] if len(sys.argv) > 1 else "taller-kinesis-sensores"
TOTAL = int(sys.argv[2]) if len(sys.argv) > 2 else 200
CLAVE = sys.argv[3] if len(sys.argv) > 3 else "contenedor"

kinesis = boto3.client("kinesis", region_name="us-east-1")

CONTENEDORES = [f"CT-{i:03d}" for i in range(1, 9)]


def generar_evento():
    return {
        "contenedor_id": random.choice(CONTENEDORES),
        "temperatura": round(random.gauss(5, 3), 2),  # °C
        "humedad": round(random.uniform(40, 90), 1),  # %
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


def clave_de(evento):
    if CLAVE == "constante":
        return "SIEMPRE-LA-MISMA"
    if CLAVE == "aleatoria":
        return uuid.uuid4().hex
    return evento["contenedor_id"]


if __name__ == "__main__":
    enviados = 0
    while enviados < TOTAL:
        lote = [generar_evento() for _ in range(10)]
        respuesta = kinesis.put_records(
            StreamName=STREAM,
            Records=[
                {
                    "Data": (json.dumps(e) + "\n").encode("utf-8"),
                    "PartitionKey": clave_de(e),
                }
                for e in lote
            ],
        )
        fallidos = respuesta["FailedRecordCount"]
        enviados += len(lote) - fallidos
        print(f"Enviados: {enviados} | Fallidos en este lote: {fallidos}")
        time.sleep(1)
