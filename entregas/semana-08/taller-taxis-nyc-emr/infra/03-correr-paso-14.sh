#!/usr/bin/env bash
# =============================================================================
#  Paso 14: el programa como EMR Step, en modo client
# =============================================================================
#  Sube taller_taxis.py a S3 y lo agrega como step al clúster que está corriendo.
#  Modo client: el programa corre en el nodo primario, y lo que imprime queda en la
#  salida del step (en modo cluster iría a los logs de YARN).
#
#  En la demo conviene hacerlo desde la consola, para que se vea: Steps → Add step →
#  Spark application → Deploy mode: Client → Application location y Arguments como abajo.
#
#  Uso:  bash 03-correr-paso-14.sh <tope_min>
#        (con taller_taxis.py en la misma carpeta; el clúster sale de ~/cluster-taxis.id)
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="taxis-nyc-$CUENTA"
TOPE="${1:?Uso: bash 03-correr-paso-14.sh <tope_min>  (el tope elegido en la referencia de Athena)}"
ID="${CLUSTER_ID:-$(cat ~/cluster-taxis.id 2>/dev/null || true)}"
[ -n "$ID" ] || { echo "!! no encuentro el ID del clúster: CLUSTER_ID=j-... bash 03-correr-paso-14.sh $TOPE"; exit 1; }
[ -f taller_taxis.py ] || { echo "!! falta taller_taxis.py en esta carpeta (subirlo a CloudShell)"; exit 1; }

aws s3 cp taller_taxis.py "s3://$BUCKET/scripts/taller_taxis.py" --only-show-errors
echo "== programa en s3://$BUCKET/scripts/taller_taxis.py =="
echo "   argumentos para la consola:  --bucket $BUCKET --tope-min $TOPE"

STEP=$(aws emr add-steps --region "$R" --cluster-id "$ID" --steps \
    "Type=Spark,Name=Paso 14 - taller_taxis.py,ActionOnFailure=CONTINUE,Args=[--deploy-mode,client,s3://$BUCKET/scripts/taller_taxis.py,--bucket,$BUCKET,--tope-min,$TOPE]" \
    --query "StepIds[0]" --output text)
echo "== step $STEP en el clúster $ID — esperando (5 a 10 min) =="

if aws emr wait step-complete --region "$R" --cluster-id "$ID" --step-id "$STEP"; then
    echo "   COMPLETED"
    echo "   resumen (ya disponible):  aws s3 ls s3://$BUCKET/resultados/"
else
    echo "   !! el step no terminó bien:"
    aws emr describe-step --region "$R" --cluster-id "$ID" --step-id "$STEP" \
        --query "Step.Status.[State, FailureDetails.Reason, FailureDetails.LogFile]" --output text
fi
echo "   log del step (llega a S3 con hasta ~5 min de demora):"
echo "   s3://$BUCKET/logs/emr/$ID/steps/$STEP/stdout.gz"
