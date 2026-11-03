#!/usr/bin/env bash
# =============================================================================
#  correr.sh — German Credit en Athena, de punta a punta, en CloudShell (us-east-1)
# =============================================================================
#  1. Bucket german-credit-<cuenta> y el archivo original de la UCI en raw/ (se baja directo a
#     CloudShell: no pasa por la laptop).
#  2. Tabla externa sobre el texto, vista legible y copia en Parquet (sql/01_tablas.sql).
#  3. Las 13 consultas (sql/02_consultas.sql), con los bytes escaneados de cada una.
#  4. La misma consulta sobre el texto y sobre el Parquet, para comparar lo que cobra Athena.
#  Costo: centavos (S3 de ~100 KB; Athena factura un mínimo de 10 MB por consulta).
#
#  Uso:  bash ~/k/german/infra/correr.sh > ~/k/resultados/german.log 2>&1
# =============================================================================
set -uo pipefail
export AWS_PAGER=""
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET=german-credit-$CUENTA
OUT=~/k/resultados/german
SALIDA="s3://$BUCKET/athena-results/"
ATHENA="python3 $HOME/k/codigo/athena.py"
mkdir -p "$OUT" /tmp/german
cd ~/k/german
paso() { echo; echo "=================== $* ($(date -u +%H:%M:%S) UTC)"; }

paso "datos: bucket y archivo original de la UCI"
aws s3 mb "s3://$BUCKET" 2>&1 | tail -1
curl -sSL -o /tmp/german/german.zip "https://archive.ics.uci.edu/static/public/144/statlog+german+credit+data.zip"
python3 -m zipfile -e /tmp/german/german.zip /tmp/german/uci
wc -l /tmp/german/uci/german.data
aws s3 cp /tmp/german/uci/german.data "s3://$BUCKET/raw/german.data" --only-show-errors
aws s3 ls "s3://$BUCKET/raw/"

paso "tablas: externa sobre el texto, vista legible y CTAS a Parquet"
sed "s#__BUCKET__#$BUCKET#g" sql/01_tablas.sql > /tmp/german/01_tablas.sql
$ATHENA --salida "$SALIDA" --archivo /tmp/german/01_tablas.sql
aws s3 ls "s3://$BUCKET/parquet/" --summarize | tail -2

paso "las 13 consultas"
$ATHENA --db german_credit --salida "$SALIDA" --archivo sql/02_consultas.sql --csv-dir "$OUT"

paso "costo por formato: la misma consulta sobre texto y sobre Parquet"
for TABLA in solicitudes solicitudes_parquet; do
    $ATHENA --db german_credit --salida "$SALIDA" --sql "
-- tasa de malos por cuenta corriente, leyendo $TABLA
SELECT cuenta, round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM $TABLA GROUP BY cuenta ORDER BY cuenta"
done
echo "FIN-GERMAN"
