#!/usr/bin/env bash
# =============================================================================
#  Parcial 2 · F3 paso 3: las tablas en el Glue Data Catalog y la verificación en Athena
# =============================================================================
#  Corre sql/tablas_athena.sql (DDL con partition projection) y después las mismas
#  consultas que hace el harness en R4 y R6, mostrando los bytes escaneados.
#
#  ⚠️ Cobra: Athena US$5/TB escaneado, con un mínimo de 10 MB por consulta. Las DDL no
#     escanean nada; las 4 verificaciones, unos 40 MB facturables: ~US$0,0002.
#
#  Uso (CloudShell, con tablas_athena.sql subido a la misma carpeta):  bash 03-tablas-athena.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aerolinea-p2-$CUENTA"
SALIDA="s3://$BUCKET/athena-results/"
[ -f tablas_athena.sql ] || { echo "!! falta tablas_athena.sql en esta carpeta"; exit 1; }

consulta () {   # $1 = SQL. Imprime las filas y los bytes escaneados.
    local qid estado
    qid=$(aws athena start-query-execution --region "$R" --work-group primary \
        --query-string "$1" --result-configuration "OutputLocation=$SALIDA" \
        --query QueryExecutionId --output text)
    while :; do
        estado=$(aws athena get-query-execution --region "$R" --query-execution-id "$qid" \
            --query "QueryExecution.Status.State" --output text)
        case "$estado" in SUCCEEDED|FAILED|CANCELLED) break ;; esac
        sleep 1
    done
    if [ "$estado" != "SUCCEEDED" ]; then
        aws athena get-query-execution --region "$R" --query-execution-id "$qid" \
            --query "QueryExecution.Status.StateChangeReason" --output text
        return 1
    fi
    aws athena get-query-results --region "$R" --query-execution-id "$qid" \
        --query "ResultSet.Rows[1:][].Data[].VarCharValue" --output text 2>/dev/null | head -12 || true
    echo "   (escaneado: $(aws athena get-query-execution --region "$R" --query-execution-id "$qid" \
        --query "QueryExecution.Statistics.DataScannedInBytes" --output text) bytes)"
}

echo "== DDL =="
# Separa el archivo en sentencias por ';' al final de línea, sin los comentarios
sed "s/__BUCKET__/$BUCKET/g" tablas_athena.sql | sed 's/--.*$//' \
    | awk 'BEGIN{RS=";[ \t]*\n"} {gsub(/^[ \t\n]+|[ \t\n]+$/, ""); if (length($0)) printf "%s%c", $0, 0}' \
    | while IFS= read -r -d '' sentencia; do
        echo "-- $(echo "$sentencia" | head -1)"
        consulta "$sentencia"
    done

DB="airline_analytics"
echo ""
echo "== Verificación (las consultas del harness) =="
echo "R4 · filas curadas (con la semilla 12345 tienen que ser 2017079):"
consulta "SELECT count(*) FROM $DB.reservations_curated"
echo "R6 · una sola partición (el harness exige escanear <= 2 × la partición promedio):"
consulta "SELECT count(*), sum(price_cents) FROM $DB.reservations_curated WHERE month='2024-01'"
echo "R6 · top-10 rutas por ocupación:"
consulta "SELECT route, CAST(sum(seats_sold) AS DOUBLE)/sum(seats_capacity) AS occ FROM $DB.route_month_metrics GROUP BY route ORDER BY occ DESC LIMIT 10"
echo "R7 · lo que consulta el endpoint (una ruta y un mes):"
consulta "SELECT * FROM $DB.route_month_metrics ORDER BY route, month LIMIT 1"
