#!/usr/bin/env bash
# =============================================================================
#  Paso 1 del taller: el bucket, los 12 Parquet de 2018 y la tabla de zonas
# =============================================================================
#  Corre en CloudShell. Cada archivo va de la web del TLC DIRECTO a S3, en
#  streaming: no pasa por el disco de CloudShell (1 GB) ni por tu conexión.
#
#  Crea un recurso (el bucket) y no borra nada. Se puede correr dos veces: si el
#  bucket ya existe lo reusa, y los archivos se vuelven a subir encima.
#
#  Uso:  bash 01-cargar-datos.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="taxis-nyc-$CUENTA"
TLC="https://d37ci6vzurychx.cloudfront.net"
# Medido el 09/10 con referencia/inspeccionar_dataset.py: 12 Parquet + el CSV de zonas
ESPERADO_OBJETOS=13
ESPERADO_BYTES=1464429097

echo "== Bucket s3://$BUCKET =="
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "   ya existe: se reusa"
else
    aws s3api create-bucket --bucket "$BUCKET" --region "$R" >/dev/null
    aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging \
        'TagSet=[{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=8},{Key=Taller,Value=taxis}]'
    echo "   creado, con el acceso público bloqueado y los tags del proyecto"
fi

echo "== Viajes 2018 → s3://$BUCKET/taxis/viajes/ =="
for m in $(seq -w 1 12); do
    archivo="yellow_tripdata_2018-$m.parquet"
    # pipefail: si curl falla a mitad, el script se corta en vez de seguir como si nada
    curl -sfL "$TLC/trip-data/$archivo" \
        | aws s3 cp - "s3://$BUCKET/taxis/viajes/$archivo" --only-show-errors
    echo "   $archivo ✓"
done

echo "== Zonas → s3://$BUCKET/taxis/zonas/zones.csv =="
curl -sfL "$TLC/misc/taxi_zone_lookup.csv" \
    | aws s3 cp - "s3://$BUCKET/taxis/zonas/zones.csv" --only-show-errors
echo "   zones.csv ✓"

echo "== Verificación =="
read -r objetos bytes < <(aws s3api list-objects-v2 --bucket "$BUCKET" --prefix taxis/ \
    --query "[length(Contents), sum(Contents[].Size)]" --output text)
if [ "$objetos" = "$ESPERADO_OBJETOS" ] && [ "$bytes" = "$ESPERADO_BYTES" ]; then
    echo "   OK: $objetos objetos, $bytes bytes — idéntico a lo medido en el origen"
else
    echo "   !! se esperaban $ESPERADO_OBJETOS objetos y $ESPERADO_BYTES bytes; hay $objetos y $bytes"
    echo "   (si el TLC republicó algún archivo, el tamaño puede cambiar: comparar mes por mes)"
    exit 1
fi
