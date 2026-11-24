#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 90: baja del stream y de Firehose AL TERMINAR CADA SESIÓN (enunciado §4.2, D9)
# =============================================================================
#  El shard provisionado cobra US$0,015 por CADA HORA que existe, se use o no. Olvidarlo un mes
#  son ~US$11 (más que todo lo demás del parcial junto). Firehose se borra con él porque su
#  fuente es el stream. Se recrean con 01-bucket-stream-firehose.sh (o 10-levantar-sesion.sh).
#  NO toca: el bucket (landing, estrella, evidencia), Glue, el workgroup ni la EC2.
#  Lo que estaba en el stream y no llegó a S3 se pierde: esperar ~2 min después de la última
#  prueba (buffer de Firehose de 60 s) antes de correrlo.
#
#  Sin --confirmo sólo muestra lo que borraría.
#  Uso (CloudShell):  bash ~/p3/infra/90-bajar-stream.sh [--confirmo]
# =============================================================================
set -uo pipefail
source "$(dirname "$0")/00-comun.sh"
echo "Firehose: $(aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE" --query DeliveryStreamDescription.DeliveryStreamStatus --output text 2>/dev/null || echo 'no existe')"
echo "Stream:   $(aws kinesis describe-stream-summary --stream-name "$STREAM" --query StreamDescriptionSummary.StreamStatus --output text 2>/dev/null || echo 'no existe')"
if [ "${1:-}" != "--confirmo" ]; then
    echo "(simulación: no se borró nada; para hacerlo: bash $0 --confirmo)"
    exit 0
fi
aws firehose delete-delivery-stream --delivery-stream-name "$FIREHOSE" 2>/dev/null && echo "Firehose: borrándose"
aws kinesis delete-stream --stream-name "$STREAM" --enforce-consumer-deletion 2>/dev/null && echo "Stream: borrándose"
aws kinesis wait stream-not-exists --stream-name "$STREAM" 2>/dev/null && echo "Stream: borrado (deja de cobrar)"
aws kinesis list-streams --query StreamNames --output text
