"""Utilidades compartidas por los scripts del taller y de los ejercicios adicionales de Kinesis.

Todo corre en CloudShell (us-east-1) con las credenciales del Learner Lab: no hay claves en el código.
"""
import time

import boto3

REGION = "us-east-1"
kinesis = boto3.client("kinesis", region_name=REGION)

# Límite de lectura por shard en modo provisionado: 5 GetRecords/s entre TODOS los consumidores
PAUSA_LECTURA_SEGURA = 0.25


def esperar_activo(stream):
    """Espera a que el stream esté ACTIVE (al crearlo o después de un reshard)."""
    while True:
        estado = kinesis.describe_stream_summary(StreamName=stream)["StreamDescriptionSummary"]["StreamStatus"]
        if estado == "ACTIVE":
            return
        time.sleep(5)


def crear_stream(stream, shards):
    """Crea un stream provisionado; si ya existe, lo reutiliza."""
    try:
        kinesis.create_stream(StreamName=stream, ShardCount=shards,
                              StreamModeDetails={"StreamMode": "PROVISIONED"})
        print(f"[ok] stream {stream} creado con {shards} shard(s)")
    except kinesis.exceptions.ResourceInUseException:
        print(f"[=] stream {stream} ya existía")
    esperar_activo(stream)


def listar_shards(stream):
    """Todos los shards, abiertos y cerrados, en el orden de la API."""
    shards, token = [], None
    while True:
        r = kinesis.list_shards(NextToken=token) if token else kinesis.list_shards(StreamName=stream)
        shards += r["Shards"]
        token = r.get("NextToken")
        if not token:
            return shards


def esta_cerrado(shard):
    """Un shard cerrado (padre de un reshard) ya tiene número de secuencia final."""
    return "EndingSequenceNumber" in shard["SequenceNumberRange"]


def shards_abiertos(stream):
    return [s for s in listar_shards(stream) if not esta_cerrado(s)]


def iterador(stream, shard_id, desde="TRIM_HORIZON", ts=None, despues_de=None):
    """Iterador de un shard: TRIM_HORIZON, LATEST, AT_TIMESTAMP (ts) o AFTER_SEQUENCE_NUMBER."""
    args = {"StreamName": stream, "ShardId": shard_id, "ShardIteratorType": desde}
    if desde == "AT_TIMESTAMP":
        args["Timestamp"] = ts
    if despues_de:
        args["ShardIteratorType"] = "AFTER_SEQUENCE_NUMBER"
        args["StartingSequenceNumber"] = despues_de
    return kinesis.get_shard_iterator(**args)["ShardIterator"]
