#!/usr/bin/env bash
# =============================================================================
#  90-limpieza.sh — audita lo que crearon el taller y los ejercicios de Kinesis
# =============================================================================
#  Por defecto SÓLO LEE: lista lo que queda vivo e imprime los comandos de baja.
#  Con --confirmo, además los ejecuta. Se corre con --confirmo sólo después de que el alumno
#  lo autorice (regla del repo: nadie borra recursos de AWS sin confirmación explícita).
#
#  Lo que cobra mientras exista: cada shard (~US$0,015/h), cada consumidor enhanced fan-out
#  (~US$0,015/h por shard) y, mucho menos, S3 y DynamoDB on-demand.
#
#  Uso:  bash ~/k/infra/90-limpieza.sh              (auditoría)
#        bash ~/k/infra/90-limpieza.sh --confirmo   (baja)
# =============================================================================
set -uo pipefail
export AWS_PAGER=""
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET=taller-kinesis-ac-$CUENTA
CMDS=()

echo "== streams";       for s in $(aws kinesis list-streams --query 'StreamNames[]' --output text); do
    case $s in taller-kinesis-*|ej-*)
        n=$(aws kinesis describe-stream-summary --stream-name "$s" --query StreamDescriptionSummary.OpenShardCount --output text)
        echo "  $s ($n shards abiertos)"
        CMDS+=("aws kinesis delete-stream --stream-name $s --enforce-consumer-deletion");; esac; done
echo "== Firehose";      for f in $(aws firehose list-delivery-streams --query 'DeliveryStreamNames[]' --output text); do
    case $f in taller-kinesis-*) echo "  $f"; CMDS+=("aws firehose delete-delivery-stream --delivery-stream-name $f");; esac; done
echo "== Lambda";        for fn in procesar-sensores contar-alertas taller-kinesis-plan-b; do
    if aws lambda get-function --function-name $fn > /dev/null 2>&1; then
        echo "  $fn"
        for u in $(aws lambda list-event-source-mappings --function-name $fn --query 'EventSourceMappings[].UUID' --output text); do
            CMDS+=("aws lambda delete-event-source-mapping --uuid $u")
        done
        CMDS+=("aws lambda delete-function --function-name $fn")
    fi; done
echo "== DynamoDB";      if aws dynamodb describe-table --table-name kinesis-leases > /dev/null 2>&1; then
    echo "  kinesis-leases"; CMDS+=("aws dynamodb delete-table --table-name kinesis-leases"); fi
echo "== Glue/Athena";   if aws glue get-database --name taller_kinesis > /dev/null 2>&1; then
    echo "  base taller_kinesis"; CMDS+=("aws glue delete-database --name taller_kinesis"); fi
echo "== S3";            if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "  $BUCKET ($(aws s3 ls "s3://$BUCKET" --recursive --summarize | awk '/Total Size/{print $3}') bytes)"
    CMDS+=("aws s3 rb s3://$BUCKET --force"); fi

echo; echo "== comandos de baja (${#CMDS[@]})"
printf '  %s\n' "${CMDS[@]}"
if [ "${1:-}" = "--confirmo" ]; then
    echo; echo "== ejecutando"
    for c in "${CMDS[@]}"; do echo "+ $c"; eval "$c" > /dev/null && echo "  ok"; done
    sleep 20
    echo "== streams que quedan: $(aws kinesis list-streams --query 'StreamNames' --output text)"
fi
