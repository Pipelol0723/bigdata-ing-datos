#!/usr/bin/env bash
# =============================================================================
#  Capstone · la parte del IDE: bajar los CSV, pasarlos a Parquet y subirlos a data-source
# =============================================================================
#  El rol de la instancia del IDE (VSCodeInstanceRole) sólo tiene S3: crear buckets, Glue y Athena
#  van por la consola (ver PLAN.md §3b y consultas-athena.sql).
#  Uso, en la terminal del IDE:
#     bash capstone-ide.sh 1    pasos 6 a 11: GLOBAL y HighSeas -> Parquet -> s3://data-source-#####/
#     bash capstone-ide.sh 2    pasos 16 a 18: EEZ con las 2 columnas renombradas -> Parquet -> bucket
#  Es idempotente y no borra nada en AWS.
# =============================================================================
set -uo pipefail
export AWS_PAGER="" AWS_DEFAULT_REGION=us-east-1
FASE="${1:-}"; [ "$FASE" = 1 ] || [ "$FASE" = 2 ] || { echo "uso: bash capstone-ide.sh 1|2"; exit 1; }
FUENTE="https://aws-tc-largeobjects.s3.us-west-2.amazonaws.com/CUR-TF-200-ACDENG-1-91570/lab-capstone/s3"
GLOBAL=SAU-GLOBAL-1-v48-0; HIGHSEAS=SAU-HighSeas-71-v48-0; EEZ=SAU-EEZ-242-v48-0
paso () { printf '\n==== %s ====\n' "$*"; }
falla () { echo "!! $*"; exit 1; }

DS=$(aws s3api list-buckets --query "Buckets[?starts_with(Name, 'data-source-')].Name | [0]" --output text)
[ -n "$DS" ] && [ "$DS" != "None" ] || falla "no encuentro el bucket data-source-#####: crearlo primero en la consola"
echo "bucket data-source: $DS"

# Conversión (pasos 8, 11 y 17). Además de lo que pide la guía, fija los tipos para que los tres Parquet
# tengan el mismo esquema: el crawler arma UNA tabla y Athena no da HIVE_BAD_DATA.
cat > convertir.py <<'PY'
import sys
import pandas as pd
nombre = sys.argv[1]
if "EEZ" in nombre:                                   # paso 17: se lee la copia de respaldo
    df = pd.read_csv(f"{nombre}-old.csv", low_memory=False)
    print(df.head(1).to_string())
    df.rename(columns={"fish_name": "common_name", "country": "fishing_entity"}, inplace=True)
    print(df.head(1).to_string())
    df.to_csv(f"{nombre}.csv", header=True, index=False)
else:
    df = pd.read_csv(f"{nombre}.csv", low_memory=False)
df["year"] = df["year"].astype("int64")
for c in ("tonnes", "landed_value"):
    df[c] = df[c].astype("float64")
for c in df.columns:
    if c not in ("year", "tonnes", "landed_value", "uncertainty_score"):
        df[c] = df[c].astype("string")
df.to_parquet(f"{nombre}.parquet", index=False)
print(f"{nombre}.parquet: {len(df):,} filas, {len(df.columns)} columnas: {', '.join(df.columns)}")
PY

if ! python3 -c 'import pandas, pyarrow' 2>/dev/null; then
    paso "paso 8: sudo pip3 install pandas pyarrow fastparquet (como dice la guía)"
    sudo pip3 install -q pandas pyarrow fastparquet || falla "no pude instalar pandas y pyarrow"
fi

if [ "$FASE" = 1 ]; then
    paso "paso 6: los 3 CSV de Sea Around Us"
    for f in $GLOBAL $HIGHSEAS $EEZ; do
        [ -s "$f.csv" ] || [ -s "$f-old.csv" ] || wget -q "$FUENTE/$f.csv" || falla "no pude bajar $f.csv"
    done
    ls -l ./*.csv

    paso "paso 7: head -6 $GLOBAL.csv"
    head -6 "$GLOBAL.csv"
    echo "líneas: $(wc -l < "$GLOBAL.csv")   (la guía dice 561,675)"

    paso "pasos 8 y 9: $GLOBAL a Parquet y al bucket"
    python3 convertir.py "$GLOBAL" || falla "falló la conversión de $GLOBAL"
    aws s3 cp "$GLOBAL.parquet" "s3://$DS/" || falla "no pude subir $GLOBAL.parquet"

    paso "paso 10: head de $HIGHSEAS.csv (columnas extra: area_name, common_name...)"
    head -3 "$HIGHSEAS.csv"

    paso "paso 11: $HIGHSEAS a Parquet y al bucket"
    python3 convertir.py "$HIGHSEAS" || falla "falló la conversión de $HIGHSEAS"
    aws s3 cp "$HIGHSEAS.parquet" "s3://$DS/" || falla "no pude subir $HIGHSEAS.parquet"
else
    paso "paso 16: encabezado del EEZ (fish_name y country tienen otro nombre)"
    [ -s "$EEZ-old.csv" ] || cp "$EEZ.csv" "$EEZ-old.csv"          # paso 17: respaldo antes de tocarlo
    head -2 "$EEZ-old.csv"

    paso "paso 17: fish_name -> common_name, country -> fishing_entity, y Parquet"
    python3 convertir.py "$EEZ" || falla "falló la conversión de $EEZ"
    head -1 "$EEZ.csv"

    paso "paso 18: $EEZ.parquet al bucket"
    aws s3 cp "$EEZ.parquet" "s3://$DS/" || falla "no pude subir $EEZ.parquet"
fi

paso "contenido de s3://$DS/"
aws s3 ls "s3://$DS/"
echo "LISTO (fase $FASE)"
