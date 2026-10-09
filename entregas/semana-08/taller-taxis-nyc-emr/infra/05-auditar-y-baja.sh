#!/usr/bin/env bash
# =============================================================================
#  Qué quedó vivo del taller, y cómo se va  —  SÓLO LECTURA
# =============================================================================
#  No borra nada. Busca los recursos del taller y al final IMPRIME los comandos de
#  baja con los IDs reales, para copiarlos a mano (regla del proyecto: CLAUDE.md).
#
#  Dos momentos de baja distintos:
#    A · al cerrar CADA sesión (ensayo y demo): el clúster y SageMaker, que cobran por hora
#    B · después de la corrección: todo lo demás
#
#  Uso:  bash 05-auditar-y-baja.sh
# =============================================================================
export AWS_PAGER=""
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="taxis-nyc-$CUENTA"

lista () { "$@" --output text 2>/dev/null | tr '\t' '\n' | sed '/^None$/d;/^$/d'; }

CLUSTERS=$(lista aws emr list-clusters --region $R --active --query "Clusters[].Id")
NOTEBOOKS=$(lista aws sagemaker list-notebook-instances --region $R \
    --query "NotebookInstances[?NotebookInstanceStatus!='Deleting'].NotebookInstanceName")
STUDIOS=$(lista aws emr list-studios --region $R --query "Studios[].StudioId")
CRAWLER=$(lista aws glue get-crawler --region $R --name crawler-taxis-viajes --query "Crawler.Name")
BASES=$(lista aws glue get-databases --region $R \
    --query "DatabaseList[?Name=='taxis' || Name=='taxis_referencia'].Name")
TAMANO=$(aws s3api list-objects-v2 --bucket "$BUCKET" --query "sum(Contents[].Size)" --output text 2>/dev/null)
SG_EMR=$(lista aws ec2 describe-security-groups --region $R \
    --filters Name=group-name,Values=ElasticMapReduce-master,ElasticMapReduce-slave --query "SecurityGroups[].GroupId")

mostrar () {
    if [ -z "$2" ]; then printf '  %-28s [ok] nada\n' "$1"
    else printf '  %-28s [!]\n' "$1"; printf '%s\n' "$2" | sed 's/^/        /'; fi
}
echo "=============================================================="
echo " TALLER TAXIS — QUÉ SIGUE VIVO   —   $(date '+%Y-%m-%d %H:%M')"
echo "=============================================================="
echo " --- cobran por hora: bajar al cerrar CADA sesión ---"
mostrar "Clústeres EMR activos" "$CLUSTERS"
mostrar "Notebooks de SageMaker" "$NOTEBOOKS"
echo " --- bajar después de la corrección ---"
[ "$TAMANO" != "None" ] && [ -n "$TAMANO" ] && B="s3://$BUCKET ($TAMANO bytes)" || B=""
mostrar "Bucket del taller" "$B"
mostrar "Bases de Glue" "$BASES"
mostrar "Crawler" "$CRAWLER"
mostrar "EMR Studios" "$STUDIOS"
mostrar "SG que creó EMR" "$SG_EMR"

echo ""
echo "=============================================================="
echo " COMANDOS DE BAJA — copiar a mano"
echo "=============================================================="
if [ -n "$CLUSTERS$NOTEBOOKS" ]; then
    echo ""
    echo "# A · AL CERRAR LA SESIÓN — lo que cobra por hora"
    for c in $CLUSTERS; do
        echo "aws emr terminate-clusters --cluster-ids $c --region $R"
        echo "aws emr wait cluster-terminated --cluster-id $c --region $R && echo 'clúster $c terminado'"
    done
    for n in $NOTEBOOKS; do
        echo "aws sagemaker stop-notebook-instance --notebook-instance-name $n --region $R"
    done
else
    echo ""
    echo "# A · nada cobrando por hora ✓"
fi

echo ""
echo "# B · DESPUÉS DE LA CORRECCIÓN — no correr antes: la demo los necesita"
for n in $NOTEBOOKS; do
    echo "aws sagemaker delete-notebook-instance --notebook-instance-name $n --region $R   # ya detenida"
done
for s in $STUDIOS; do echo "aws emr delete-studio --studio-id $s --region $R"; done
[ -n "$CRAWLER" ] && echo "aws glue delete-crawler --name $CRAWLER --region $R"
for b in $BASES; do echo "aws glue delete-database --name $b --region $R   # borra también sus tablas"; done
[ -n "$B" ] && echo "aws s3 rb s3://$BUCKET --force   # IRREVERSIBLE: datos, salida, logs y notebooks"
if [ -n "$SG_EMR" ]; then
    echo "# SG de EMR (gratis, opcional): se referencian entre sí, hay que vaciarlos antes de borrarlos"
    for sg in $SG_EMR; do
        echo "aws ec2 revoke-security-group-ingress --group-id $sg --region $R --ip-permissions \"\$(aws ec2 describe-security-groups --group-ids $sg --region $R --query 'SecurityGroups[0].IpPermissions' --output json)\""
    done
    for sg in $SG_EMR; do echo "aws ec2 delete-security-group --group-id $sg --region $R"; done
fi
echo ""
echo "# Verificación: bash 05-auditar-y-baja.sh   ·   y la general: bash auditar-recursos.sh"
