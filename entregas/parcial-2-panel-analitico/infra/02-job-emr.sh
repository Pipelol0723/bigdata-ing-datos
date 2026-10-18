#!/usr/bin/env bash
# =============================================================================
#  Parcial 2 · F3 paso 2: el job de PySpark en un EMR TRANSITORIO (decisión D3)
# =============================================================================
#  Crea un clúster de 1 solo nodo m4.large que corre el step y SE TERMINA SOLO
#  (--auto-terminate): R10 queda garantizado por diseño, no por acordarse.
#  Si el step falla, el clúster también se termina (ActionOnFailure=TERMINATE_CLUSTER).
#
#  ¿Por qué 1 nodo? El dataset son 85 MB: entra en la memoria de un m4.large. Un clúster
#  de 3 nodos gasta 12 horas normalizadas por arranque (R10 tiene tope 150 en 45 días);
#  éste, 4. ¿Por qué m4.large? Es el único tipo que acepta R11 (y el lab no da m5.large).
#
#  ⚠️ Cobra ~US$0,13/h (EC2 + recargo EMR) desde que arranca hasta que termina, y se
#     factura la hora entera. Una corrida: ~10-15 min de reloj, 4 horas normalizadas.
#
#  Uso (CloudShell):  bash 02-job-emr.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aerolinea-p2-$CUENTA"

aws s3api head-object --bucket "$BUCKET" --key raw/reservations.csv >/dev/null 2>&1 \
    || { echo "!! no está s3://$BUCKET/raw/reservations.csv (correr 01-bucket.sh y subir los crudos)"; exit 1; }
aws s3api head-object --bucket "$BUCKET" --key scripts/curar_reservas.py >/dev/null 2>&1 \
    || { echo "!! no está el job en s3://$BUCKET/scripts/ (correr 01-bucket.sh)"; exit 1; }

VIVO=$(aws emr list-clusters --region "$R" --active --query "Clusters[?Name=='parcial2-curar'].Id" --output text)
[ -z "$VIVO" ] || { echo "!! ya hay un clúster del job vivo: $VIVO — no se crea otro"; exit 1; }

RELEASE="${EMR_RELEASE:-$(aws emr list-release-labels --region "$R" --filters Prefix=emr-7 \
    --query "ReleaseLabels" --output text | tr '\t' '\n' | sort -V | tail -1)}"
SUBNET=$(aws ec2 describe-subnets --region "$R" \
    --filters Name=default-for-az,Values=true Name=availability-zone,Values=us-east-1a \
    --query "Subnets[0].SubnetId" --output text)
echo "== release $RELEASE · subred $SUBNET · 1 × m4.large · se termina solo al acabar el step =="

STEP="Type=Spark,Name=curar-reservas,ActionOnFailure=TERMINATE_CLUSTER,Args=[--deploy-mode,client,s3://$BUCKET/scripts/curar_reservas.py,--raw,s3://$BUCKET/raw/,--out,s3://$BUCKET/curated/]"
ID=$(aws emr create-cluster --region "$R" \
    --name "parcial2-curar" \
    --release-label "$RELEASE" \
    --applications Name=Spark \
    --instance-groups InstanceGroupType=MASTER,InstanceCount=1,InstanceType=m4.large \
    --service-role EMR_DefaultRole \
    --ec2-attributes "KeyName=vockey,SubnetId=$SUBNET,InstanceProfile=EMR_EC2_DefaultRole" \
    --log-uri "s3://$BUCKET/logs/emr/" \
    --steps "$STEP" \
    --auto-terminate \
    --tags Proyecto=bigdata Unidad=parcial2 \
    --query ClusterId --output text)
echo "== clúster $ID creado. Espera ~10-15 min (arranque + step + apagado) =="
echo "   consola: https://us-east-1.console.aws.amazon.com/emr/home?region=us-east-1#/clusterDetails/$ID"

aws emr wait cluster-terminated --region "$R" --cluster-id "$ID" || true
aws emr describe-cluster --region "$R" --cluster-id "$ID" \
    --query "Cluster.[Status.State, Status.StateChangeReason.Message, NormalizedInstanceHours]" --output text
aws emr list-steps --region "$R" --cluster-id "$ID" \
    --query "Steps[].[Name, Status.State, Status.Timeline.StartDateTime, Status.Timeline.EndDateTime]" --output text

echo ""
echo "== salida en S3 =="
echo "meses (tiene que dar 24): $(aws s3 ls "s3://$BUCKET/curated/reservations_curated/" | grep -c 'month=')"
aws s3 ls "s3://$BUCKET/curated/route_month_metrics/"
RES=$(aws s3 ls "s3://$BUCKET/curated/_resumen/" | awk '/part-/{print $4}' | head -1)
[ -n "$RES" ] && { echo "resumen del job:"; aws s3 cp "s3://$BUCKET/curated/_resumen/$RES" -; }
echo ""
echo "Activos de EMR (tiene que estar vacío, R10):"
aws emr list-clusters --region "$R" --active --query "Clusters[].[Id,Name,Status.State]" --output text
