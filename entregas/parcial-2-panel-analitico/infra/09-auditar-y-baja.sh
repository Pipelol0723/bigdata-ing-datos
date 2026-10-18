#!/usr/bin/env bash
# =============================================================================
#  Parcial 2 · qué quedó vivo y cómo se va  —  SÓLO LECTURA
# =============================================================================
#  No borra nada: audita e IMPRIME los comandos de baja con los IDs reales, para
#  copiarlos a mano (regla del proyecto, CLAUDE.md).
#
#  Uso:  bash 09-auditar-y-baja.sh
# =============================================================================
export AWS_PAGER=""
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aerolinea-p2-$CUENTA"
lista () { "$@" --output text 2>/dev/null | tr '\t' '\n' | sed '/^None$/d;/^$/d'; }

EMR=$(lista aws emr list-clusters --region $R --active --query "Clusters[].Id")
EC2=$(lista aws ec2 describe-instances --region $R \
    --filters Name=tag:Name,Values=parcial2-app Name=instance-state-name,Values=pending,running,stopping,stopped \
    --query "Reservations[].Instances[].InstanceId")
EC2_TODAS=$(aws ec2 describe-instances --region $R --filters Name=instance-state-name,Values=pending,running \
    --query "Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key=='Name']|[0].Value]" --output text 2>/dev/null)
SG=$(lista aws ec2 describe-security-groups --region $R --filters Name=group-name,Values=parcial2-app --query "SecurityGroups[].GroupId")
HORAS=$(aws emr list-clusters --region $R --created-after "$(date -u -d '45 days ago' +%Y-%m-%dT%H:%M:%SZ)" \
    --query "Clusters[].Id" --output text 2>/dev/null | tr '\t' '\n' | while read -r c; do
        [ -n "$c" ] && aws emr describe-cluster --region $R --cluster-id "$c" --query "Cluster.NormalizedInstanceHours" --output text; done \
    | awk '{s+=$1} END {print s+0}')
TAMANO=$(aws s3api list-objects-v2 --bucket "$BUCKET" --query "sum(Contents[].Size)" --output text 2>/dev/null)

echo "=============================================================="
echo " PARCIAL 2 — QUÉ SIGUE VIVO   —   $(date '+%Y-%m-%d %H:%M')"
echo "=============================================================="
echo " EMR activos (R10 exige ninguno):  ${EMR:-ninguno}"
echo " Horas normalizadas de EMR, 45 días (R10: tope 150):  $HORAS"
echo " EC2 de la app:  ${EC2:-ninguna}"
echo " Todas las EC2 prendidas de la cuenta:"; echo "${EC2_TODAS:-   ninguna}" | sed 's/^/   /'
echo " Bucket s3://$BUCKET:  ${TAMANO:-no existe} bytes"
echo ""
echo "=============================================================="
echo " COMANDOS DE BAJA — copiar a mano, sólo lo que corresponda"
echo "=============================================================="
for c in $EMR; do echo "aws emr terminate-clusters --cluster-ids $c --region $R"; done
for i in $EC2; do
    echo "# La app (al terminar el parcial; mientras se corrige tiene que estar arriba):"
    echo "aws ec2 terminate-instances --instance-ids $i --region $R"
    echo "aws ec2 wait instance-terminated --instance-ids $i --region $R"
done
for s in $SG; do echo "aws ec2 delete-security-group --group-id $s --region $R   # después de terminar la EC2"; done
echo "# Datos y catálogo (después de la corrección):"
echo "aws athena start-query-execution --region $R --query-string 'DROP TABLE IF EXISTS airline_analytics.reservations_curated' --result-configuration OutputLocation=s3://$BUCKET/athena-results/"
echo "aws athena start-query-execution --region $R --query-string 'DROP TABLE IF EXISTS airline_analytics.route_month_metrics' --result-configuration OutputLocation=s3://$BUCKET/athena-results/"
echo "aws glue delete-database --name airline_analytics --region $R"
echo "aws s3 rb s3://$BUCKET --force"
