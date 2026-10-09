#!/usr/bin/env bash
# =============================================================================
#  El clúster EMR del taller: el mismo comando para el ensayo y para la demo
# =============================================================================
#  1 primario + 2 core m5.large ("large" es el máximo que permite el lab), con
#  Spark, Livy y Jupyter Enterprise Gateway —lo que necesita un notebook de EMR
#  Studio o de SageMaker—, logs en S3 y AUTO-TERMINACIÓN por inactividad.
#
#  ⚠️ Cobra ~$0,36/h desde que arranca hasta que se termina, haga algo o no.
#     El clúster NO sobrevive al fin de la sesión del lab.
#
#  Uso:  bash 02-crear-cluster.sh [horas_inactivo]
#        horas_inactivo: a las cuántas horas sin trabajo se apaga solo (default 1).
#        El martes, 3: con 1 podría apagarse solo antes de la demo.
# =============================================================================
set -euo pipefail
export AWS_PAGER=""

R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="taxis-nyc-$CUENTA"
INACTIVO_S=$(( ${1:-1} * 3600 ))

# Ya hay uno vivo? Dos clústeres a la vez es pagar doble sin darse cuenta.
VIVO=$(aws emr list-clusters --region "$R" --active \
    --query "Clusters[?Name=='taller-taxis-nyc'].Id" --output text)
if [ -n "$VIVO" ]; then
    echo "!! Ya hay un clúster del taller vivo: $VIVO — no se crea otro."
    echo "$VIVO" > ~/cluster-taxis.id
    exit 1
fi

# Roles: en el lab no se pueden crear, tienen que existir
for rol in EMR_DefaultRole EMR_EC2_DefaultRole; do
    aws iam get-role --role-name "$rol" >/dev/null 2>&1 \
        || echo "   aviso: no pude verificar el rol $rol (si falta, create-cluster lo dirá)"
done

# La última versión 7.x disponible en la región (o la que se fije con EMR_RELEASE=emr-7.x.0)
RELEASE="${EMR_RELEASE:-$(aws emr list-release-labels --region "$R" --filters Prefix=emr-7 \
    --query "ReleaseLabels" --output text 2>/dev/null | tr '\t' '\n' | sort -V | tail -1 || true)}"
[ -n "$RELEASE" ] || { echo "!! no pude listar las versiones de EMR. Correr así:"
                       echo "   EMR_RELEASE=emr-7.x.0 bash 02-crear-cluster.sh"; exit 1; }
# Subred por defecto de us-east-1a: la misma en el ensayo y el martes
SUBNET=$(aws ec2 describe-subnets --region "$R" \
    --filters Name=default-for-az,Values=true Name=availability-zone,Values=us-east-1a \
    --query "Subnets[0].SubnetId" --output text)
[ "$SUBNET" != "None" ] || { echo "!! no hay subred por defecto en us-east-1a"; exit 1; }
echo "== release $RELEASE · subred $SUBNET (us-east-1a) · se apaga tras $(( INACTIVO_S / 3600 )) h sin trabajo =="

# Las fechas del TLC son hora local sin zona: en UTC, year(), month() y la resta trabajan
# sobre la hora tal como está escrita, sin corrimientos.
CONFIG='[{"Classification":"spark-defaults","Properties":{"spark.sql.session.timeZone":"UTC"}}]'

ID=$(aws emr create-cluster --region "$R" \
    --name "taller-taxis-nyc" \
    --release-label "$RELEASE" \
    --applications Name=Hadoop Name=Spark Name=Livy Name=JupyterEnterpriseGateway \
    --instance-groups \
        InstanceGroupType=MASTER,InstanceCount=1,InstanceType=m5.large \
        InstanceGroupType=CORE,InstanceCount=2,InstanceType=m5.large \
    --service-role EMR_DefaultRole \
    --ec2-attributes "KeyName=vockey,SubnetId=$SUBNET,InstanceProfile=EMR_EC2_DefaultRole" \
    --log-uri "s3://$BUCKET/logs/emr/" \
    --auto-termination-policy "IdleTimeout=$INACTIVO_S" \
    --configurations "$CONFIG" \
    --tags Proyecto=bigdata Unidad=8 Taller=taxis \
    --query ClusterId --output text)

echo "$ID" > ~/cluster-taxis.id
echo "== clúster $ID creado — arrancando (10 a 15 min) =="
echo "   consola: https://us-east-1.console.aws.amazon.com/emr/home?region=us-east-1#/clusterDetails/$ID"

if ! aws emr wait cluster-running --region "$R" --cluster-id "$ID"; then
    echo "!! el clúster no llegó a arrancar. Motivo según EMR:"
    aws emr describe-cluster --region "$R" --cluster-id "$ID" \
        --query "Cluster.Status.[State, StateChangeReason.Message]" --output text
    exit 1
fi
aws emr describe-cluster --region "$R" --cluster-id "$ID" \
    --query "Cluster.[Id, Status.State, ReleaseLabel, MasterPublicDnsName]" --output text
echo "== listo. Para terminarlo:  aws emr terminate-clusters --cluster-ids $ID --region $R =="
