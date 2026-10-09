#!/usr/bin/env bash
# =============================================================================
#  Paso 13: la base "taxis", el crawler y la tabla "viajes"
# =============================================================================
#  El crawler recorre s3://<bucket>/viajes/ —la salida del paso 12— y registra la
#  tabla "viajes" con sus particiones year y month. No necesita el clúster: se
#  corre después de terminarlo.
#
#  Cobra ~$0,12 por corrida. Queda "on demand": nunca con schedule.
#
#  Uso:  bash 04-crawler.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="taxis-nyc-$CUENTA"
CRAWLER="crawler-taxis-viajes"

aws glue get-database --region "$R" --name taxis >/dev/null 2>&1 \
    || aws glue create-database --region "$R" \
           --database-input "Name=taxis,Description=Taller Taxis NYC: salida del paso 12"
aws glue get-crawler --region "$R" --name "$CRAWLER" >/dev/null 2>&1 \
    || aws glue create-crawler --region "$R" --name "$CRAWLER" --role LabRole \
           --database-name taxis --targets "S3Targets=[{Path=s3://$BUCKET/viajes/}]" \
           --tags Proyecto=bigdata,Unidad=8,Taller=taxis
echo "== base taxis y crawler $CRAWLER listos (rol LabRole, on demand) =="

aws glue start-crawler --region "$R" --name "$CRAWLER"
echo "== corriendo (1 a 2 min) =="
sleep 20
while [ "$(aws glue get-crawler --region "$R" --name "$CRAWLER" --query Crawler.State --output text)" != "READY" ]; do
    sleep 15
done
aws glue get-crawler --region "$R" --name "$CRAWLER" \
    --query "Crawler.LastCrawl.[Status, ErrorMessage]" --output text

echo "== tabla taxis.viajes =="
aws glue get-table --region "$R" --database-name taxis --name viajes \
    --query "Table.{ubicacion: StorageDescriptor.Location, columnas: StorageDescriptor.Columns[].[Name,Type], particiones: PartitionKeys[].[Name,Type]}"
echo "particiones registradas: $(aws glue get-partitions --region "$R" --database-name taxis \
    --table-name viajes --query 'length(Partitions)' --output text)   (esperado: 12)"

cat <<'ATHENA'

== Verificación en Athena (tiene que coincidir con el paso 11) ==
SELECT month, count(*) AS viajes FROM taxis.viajes GROUP BY month ORDER BY viajes DESC;

Si las particiones salieron como string y se las quiere enteras (pasos 9 y 10):
Glue → Tables → viajes → Edit schema → year y month: int → Save. No volver a correr el crawler
después, o las puede devolver a string.
ATHENA
