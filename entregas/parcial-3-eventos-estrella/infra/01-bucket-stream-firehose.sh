#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 01: bucket, stream de Kinesis y Firehose hacia la landing zone
# =============================================================================
#  Idempotente: lo que ya existe se deja como está. Se corre al ABRIR cada sesión de pruebas.
#
#  · Bucket aerolinea-p3-<cuenta>: landing (raw/), estrella (star/), ref/, deploy/, resultados.
#  · Stream airline-events: PROVISIONED, 1 shard, retención por defecto (24 h), sin enhanced
#    fan-out (R11). Es lo único que cobra por hora: US$0,015/h MIENTRAS EXISTA -> se borra al
#    terminar cada sesión con 90-bajar-stream.sh (enunciado §4.2 y decisión D9).
#  · Firehose airline-events-a-s3 (D4): lee el stream y escribe en s3://BUCKET/raw/events/
#    AAAA/MM/DD/HH/, en gzip, cada 60 s o 1 MB, con un salto de línea después de cada registro
#    (AppendDelimiterToRecord: sin eso los JSON quedan pegados y Athena lee uno por línea, trampa 2).
#    Cobra US$0,029/GB ingerido (cada registro se redondea a 5 KB); no cobra por hora.
#
#  Uso (CloudShell):  bash ~/p3/infra/01-bucket-stream-firehose.sh
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-comun.sh"

paso "bucket s3://$BUCKET"
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "ya existe"
else
    aws s3api create-bucket --bucket "$BUCKET" --region "$R" >/dev/null
    aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    aws s3api put-bucket-tagging --bucket "$BUCKET" \
        --tagging 'TagSet=[{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=parcial3}]'
    echo "creado (privado, con tags)"
fi

paso "stream $STREAM (1 shard provisionado)"
if aws kinesis describe-stream-summary --stream-name "$STREAM" >/dev/null 2>&1; then
    echo "ya existe"
else
    aws kinesis create-stream --stream-name "$STREAM" --shard-count 1 \
        --stream-mode-details StreamMode=PROVISIONED
    aws kinesis wait stream-exists --stream-name "$STREAM"
    aws kinesis add-tags-to-stream --stream-name "$STREAM" --tags Proyecto=bigdata,Unidad=parcial3
    echo "creado: empieza a cobrar US\$0,015/h"
fi
ARN_STREAM=$(aws kinesis describe-stream-summary --stream-name "$STREAM" \
    --query StreamDescriptionSummary.StreamARN --output text)
aws kinesis describe-stream-summary --stream-name "$STREAM" --query \
    'StreamDescriptionSummary.{estado:StreamStatus,modo:StreamModeDetails.StreamMode,shards:OpenShardCount,retencion_h:RetentionPeriodHours,consumidores_efo:ConsumerCount}' \
    --output table

paso "Firehose $FIREHOSE -> s3://$BUCKET/raw/events/"
if aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE" >/dev/null 2>&1; then
    echo "ya existe"
else
    crear () {   # $1 = con parámetro Delimiter explícito (1) o sin parámetros (0)
        python3 - "$1" "$ROL" "$BUCKET" > /tmp/firehose-s3.json <<'PY'
import json, sys
explicito, rol, bucket = sys.argv[1] == "1", sys.argv[2], sys.argv[3]
proc = {"Type": "AppendDelimiterToRecord"}
if explicito:
    proc["Parameters"] = [{"ParameterName": "Delimiter", "ParameterValue": "\\n"}]
print(json.dumps({
    "RoleARN": rol, "BucketARN": f"arn:aws:s3:::{bucket}",
    "Prefix": "raw/events/!{timestamp:yyyy/MM/dd/HH}/",
    "ErrorOutputPrefix": "errores-firehose/!{firehose:error-output-type}/!{timestamp:yyyy/MM/dd}/",
    "BufferingHints": {"SizeInMBs": 1, "IntervalInSeconds": 60},
    "CompressionFormat": "GZIP",
    "ProcessingConfiguration": {"Enabled": True, "Processors": [proc]}}))
PY
        aws firehose create-delivery-stream --delivery-stream-name "$FIREHOSE" \
            --delivery-stream-type KinesisStreamAsSource \
            --kinesis-stream-source-configuration "KinesisStreamARN=$ARN_STREAM,RoleARN=$ROL" \
            --extended-s3-destination-configuration file:///tmp/firehose-s3.json \
            --tags Key=Proyecto,Value=bigdata Key=Unidad,Value=parcial3 >/dev/null
    }
    crear 0 2>/tmp/firehose-err.txt || { echo "(sin parámetros falló: $(head -c 200 /tmp/firehose-err.txt)) -> con Delimiter explícito"; crear 1; }
    for _ in $(seq 1 40); do
        e=$(aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE" \
            --query DeliveryStreamDescription.DeliveryStreamStatus --output text)
        [ "$e" = "ACTIVE" ] || [ "$e" = "CREATING_FAILED" ] && break
        sleep 10
    done
    echo "estado: $e"
    [ "$e" = "ACTIVE" ] || { echo "!! Firehose no quedó ACTIVE"; exit 1; }
fi
aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE" --query \
    'DeliveryStreamDescription.Destinations[0].ExtendedS3DestinationDescription.{prefijo:Prefix,buffer:BufferingHints,compresion:CompressionFormat,procesadores:ProcessingConfiguration.Processors[].Type}' \
    --output json
