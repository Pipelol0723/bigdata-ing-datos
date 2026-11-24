#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 02: workgroup de Athena, datos de referencia y DIMENSIONES (D10, D11)
# =============================================================================
#  · Workgroup "parcial3" (R10): límite de 1 GB por consulta (BytesScannedCutoffPerQuery) y su
#    propia carpeta de resultados. No se toca "primary", que usan las otras prácticas.
#    EnforceWorkGroupConfiguration = false A PROPÓSITO (hallazgo del 24/11 en AWS): con true,
#    Athena rechaza todo CTAS con external_location ("...enforces a centralized output
#    location..."), y el rebuild necesita ubicaciones fijas para poder vaciarlas. El límite de
#    datos por consulta es un control del workgroup y se aplica igual con enforce = false.
#  · ref/ (generado con --seed 12345) sube SIN el \r\n de Windows (si no, la última columna de
#    cada CSV arrastra un '\r'; el SQL igual lo limpia, doble defensa).
#  · Las dimensiones se construyen UNA VEZ con el mismo SQL que usa la app (app/sql), vía
#    app/estrella.py. Sólo hay que repetirlo si cambia ref/ (o con --forzar).
#  Costo: CTAS de dimensiones ~10 MB mínimos por consulta -> fracciones de centavo.
#
#  Uso (CloudShell):  bash ~/p3/infra/02-athena-y-dimensiones.sh [--forzar]
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-comun.sh"

paso "workgroup $WG (límite 1 GB por consulta)"
CONF="ResultConfigurationUpdates={OutputLocation=s3://$BUCKET/athena-results/},EnforceWorkGroupConfiguration=false,PublishCloudWatchMetricsEnabled=false,BytesScannedCutoffPerQuery=1000000000"
if aws athena get-work-group --work-group "$WG" >/dev/null 2>&1; then
    aws athena update-work-group --work-group "$WG" --configuration-updates "$CONF"
    echo "ya existía: configuración actualizada"
else
    aws athena create-work-group --name "$WG" \
        --description "Parcial 3: limite de 1 GB por consulta (R10)" \
        --configuration "ResultConfiguration={OutputLocation=s3://$BUCKET/athena-results/},EnforceWorkGroupConfiguration=false,PublishCloudWatchMetricsEnabled=false,BytesScannedCutoffPerQuery=1000000000" \
        --tags Key=Proyecto,Value=bigdata Key=Unidad,Value=parcial3
    echo "creado"
fi
aws athena get-work-group --work-group "$WG" --query \
    'WorkGroup.Configuration.{limite_bytes:BytesScannedCutoffPerQuery,salida:ResultConfiguration.OutputLocation,forzado:EnforceWorkGroupConfiguration}' --output table

paso "datos de referencia -> s3://$BUCKET/ref/ (sin \\r)"
subir () { sed 's/\r$//' "$P3/ref/$1" > "/tmp/$1"; aws s3 cp "/tmp/$1" "s3://$BUCKET/ref/$2/$1" --only-show-errors; echo "  $1 -> ref/$2/ ($(wc -l < "/tmp/$1") líneas)"; }
subir routes_ref.csv routes
subir route_category_history.csv route_history
subir holidays_ref.csv holidays

paso "base $DB, tablas de entrada y dimensiones (app/estrella.py)"
cd "$P3/app"
if [ "${1:-}" = "--forzar" ] || ! aws glue get-table --database-name "$DB" --name dim_date >/dev/null 2>&1; then
    python3 estrella.py dimensiones --bucket "$BUCKET" --db "$DB" --workgroup "$WG"
else
    python3 estrella.py base --bucket "$BUCKET" --db "$DB" --workgroup "$WG"
    echo "(las dimensiones ya existían; para reconstruirlas: --forzar)"
fi
aws glue get-tables --database-name "$DB" --query "TableList[].[Name,StorageDescriptor.SerdeInfo.SerializationLibrary]" --output table
