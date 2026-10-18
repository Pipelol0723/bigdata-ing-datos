#!/usr/bin/env bash
# =============================================================================
#  Parcial 2 · F3 paso 1: el bucket del proyecto
# =============================================================================
#  Crea s3://aerolinea-p2-<cuenta> (privado, con tags) y sube el job de PySpark.
#  El nombre sale del ID de la cuenta: en otra cuenta del lab, el mismo script.
#
#  Los CSV crudos NO se generan acá (CloudShell tiene 1 GB de RAM y el generador usa
#  más). Se suben desde la laptop, ya validados contra el oráculo. Este script imprime
#  el comando exacto al final.
#
#  ⚠️ Cobra: S3 ~US$0,023/GB-mes. Con ~115 MB son centavos.
#
#  Uso (CloudShell, con curar_reservas.py subido a la misma carpeta):  bash 01-bucket.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aerolinea-p2-$CUENTA"

if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "== el bucket $BUCKET ya existe =="
else
    aws s3api create-bucket --bucket "$BUCKET" --region "$R" >/dev/null
    aws s3api put-public-access-block --bucket "$BUCKET" --public-access-block-configuration \
        BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true
    aws s3api put-bucket-tagging --bucket "$BUCKET" \
        --tagging 'TagSet=[{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=parcial2}]'
    echo "== bucket $BUCKET creado (privado) =="
fi

[ -f curar_reservas.py ] || { echo "!! falta curar_reservas.py en esta carpeta (subirlo a CloudShell)"; exit 1; }
aws s3 cp curar_reservas.py "s3://$BUCKET/scripts/curar_reservas.py" --only-show-errors
echo "== job en s3://$BUCKET/scripts/curar_reservas.py =="

echo ""
echo "Crudos en S3:"
aws s3 ls "s3://$BUCKET/raw/" || true
cat <<EOF

Si faltan, subirlos DESDE LA LAPTOP (PowerShell, con las credenciales del lab cargadas
con scripts\\cargar-credenciales.ps1):

    aws s3 cp C:\\Users\\pipel\\datos-parcial2\\raw s3://$BUCKET/raw/ --recursive

Tienen que quedar flights.csv (~0,4 MB) y reservations.csv (~85 MB).
EOF
