#!/usr/bin/env bash
# =============================================================================
#  Checkpoint 1 — Crea el bucket del data lake con sus zonas
#  Pegar en CloudShell, que ya trae las credenciales del Learner Lab.
# =============================================================================
#  CREA (no borra nada):
#    · 1 bucket S3 con nombre único por cuenta
#    · bloqueo de acceso público (los 4 flags)
#    · versionado activado
#    · política de ciclo de vida (../../semana-03/sesion-06-.../lifecycle-revisada.json)
#    · los prefijos raw/ processed/ curated/
#
#  💰 Costo: centavos al mes con < 1 GB. El bucket NO se borra al cerrar la
#     sesión: lo necesitan el Checkpoint 2, Athena y el resto del curso.
#
#  Uso:  bash crear-data-lake.sh
# =============================================================================

set -euo pipefail
export AWS_PAGER=""

REGION="${AWS_REGION:-us-east-1}"
LIFECYCLE="../../semana-03/sesion-06-s3-clases-versionado-lifecycle/lifecycle-revisada.json"

if [ ! -f "$LIFECYCLE" ]; then
    echo "ERROR: no encuentro $LIFECYCLE"
    echo "       Corré el script desde la carpeta entregas/semana-04/checkpoint-1/"
    exit 1
fi

CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="datalake-aerolinea-${CUENTA}"

echo "=============================================================="
echo " Data lake del proyecto — $BUCKET  ($REGION)"
echo "=============================================================="

# --- 1. Bucket ---------------------------------------------------------------
# us-east-1 es la única región que NO acepta --create-bucket-configuration.
if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    echo "[=] el bucket ya existe"
else
    if [ "$REGION" = "us-east-1" ]; then
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
    else
        aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" \
            --create-bucket-configuration "LocationConstraint=$REGION" >/dev/null
    fi
    echo "[+] bucket creado"
fi

# --- 2. Acceso público bloqueado --------------------------------------------
# Por defecto AWS ya los bloquea, pero se declara explícitamente: el data lake
# contiene datos de pasajeros y la configuración por defecto puede cambiar.
aws s3api put-public-access-block --bucket "$BUCKET" \
    --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
echo "[+] acceso público bloqueado (4/4)"

# --- 3. Versionado -----------------------------------------------------------
aws s3api put-bucket-versioning --bucket "$BUCKET" \
    --versioning-configuration Status=Enabled
echo "[+] versionado activado"

# --- 4. Ciclo de vida --------------------------------------------------------
# Ver la revisión línea por línea del borrador generado por IA en
# ../../semana-03/sesion-06-s3-clases-versionado-lifecycle/README.md
aws s3api put-bucket-lifecycle-configuration --bucket "$BUCKET" \
    --lifecycle-configuration "file://$LIFECYCLE"
echo "[+] política de ciclo de vida aplicada (3 reglas)"

# --- 5. Zonas ----------------------------------------------------------------
# S3 no tiene carpetas: son prefijos. Se crean objetos marcador de 0 bytes para
# que las tres zonas se vean en la consola desde el principio.
for zona in raw processed curated; do
    aws s3api put-object --bucket "$BUCKET" --key "${zona}/" --content-length 0 >/dev/null
    echo "[+] zona ${zona}/"
done

# --- 6. Etiquetas ------------------------------------------------------------
aws s3api put-bucket-tagging --bucket "$BUCKET" --tagging \
    'TagSet=[{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=checkpoint-1}]'
echo "[+] etiquetado"

# --- 7. Verificación ---------------------------------------------------------
echo ""
echo "=============================================================="
echo " VERIFICACIÓN  —  capturar esta salida como evidencia"
echo "=============================================================="
echo ""
echo "--- versionado ---"
aws s3api get-bucket-versioning --bucket "$BUCKET"
echo ""
echo "--- ciclo de vida ---"
aws s3api get-bucket-lifecycle-configuration --bucket "$BUCKET"
echo ""
echo "--- acceso público ---"
aws s3api get-public-access-block --bucket "$BUCKET" \
    --query "PublicAccessBlockConfiguration"
echo ""
echo "--- zonas ---"
aws s3 ls "s3://$BUCKET/"
echo ""
echo "Bucket: s3://$BUCKET"
