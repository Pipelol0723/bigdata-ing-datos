#!/usr/bin/env bash
# =============================================================================
#  Baja TOTAL de la infraestructura del parcial  —  SÓLO LECTURA
# =============================================================================
#  Este script NO borra nada. Busca todo lo que dejó el parcial (y los restos de
#  la práctica de Sakila) y al final IMPRIME los comandos de baja con los IDs
#  reales y en el orden en que hay que correrlos, para copiarlos a mano.
#
#  Es una regla del proyecto (ver ../../../CLAUDE.md): los comandos destructivos
#  se entregan aparte, nunca automatizados. Un `terminate` disparado por un
#  script que se corrió sin leer es irreversible.
#
#  Uso (CloudShell):   bash 02-baja-recursos.sh
#  Correrlo de nuevo al terminar: tiene que dar [ok] en todo.
# =============================================================================

export AWS_PAGER=""
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)

# --output text separa con tabuladores: así los nombres con espacios
# ("Jdbc connection") no se parten en dos.
lista () { "$@" --output text 2>/dev/null | tr '\t' '\n' | sed '/^None$/d;/^$/d'; }

RDS=$(lista aws rds describe-db-instances --region $R \
        --query "DBInstances[].DBInstanceIdentifier")
SNAPS=$(lista aws rds describe-db-snapshots --region $R --snapshot-type manual \
        --query "DBSnapshots[].DBSnapshotIdentifier")
BACKUPS=$(lista aws rds describe-db-instance-automated-backups --region $R \
        --query "DBInstanceAutomatedBackups[].DBInstanceAutomatedBackupsArn")
EC2=$(lista aws ec2 describe-instances --region $R \
        --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
        --query "Reservations[].Instances[].InstanceId")
SSM=$(lista aws ssm get-parameters-by-path --region $R --path /parcial --query "Parameters[].Name")
JOBS=$(lista aws glue list-jobs --region $R --query "JobNames")
CRAWLERS=$(lista aws glue list-crawlers --region $R --query "CrawlerNames")
CONEXIONES=$(lista aws glue get-connections --region $R --query "ConnectionList[].Name")
DATABASES=$(lista aws glue get-databases --region $R --query "DatabaseList[?Name!='default'].Name")
LOGS=$(lista aws logs describe-log-groups --region $R --log-group-name-prefix /aws-glue \
        --query "logGroups[].logGroupName")
SGS=$(lista aws ec2 describe-security-groups --region $R \
        --query "SecurityGroups[?GroupName!='default'].GroupId")
ENDPOINTS=$(lista aws ec2 describe-vpc-endpoints --region $R --query "VpcEndpoints[].VpcEndpointId")
BUCKETS=$(lista aws s3api list-buckets --query "Buckets[].Name")
# Buckets que son del parcial: el data lake, los scripts del job (Glue los guarda en
# aws-glue-assets-*) y los resultados de Athena si se guardaron aparte.
BUCKETS_PARCIAL=$(printf '%s\n' "$BUCKETS" | grep -E "^(datalake-aerolinea-|aws-glue-assets-|aws-athena-query-results-)")
BUCKETS_OTROS=$(printf '%s\n' "$BUCKETS" | grep -vE "^(datalake-aerolinea-|aws-glue-assets-|aws-athena-query-results-)")

echo "=============================================================="
echo " QUÉ SIGUE VIVO   —   cuenta $CUENTA   —   $(date '+%Y-%m-%d %H:%M')"
echo "=============================================================="
mostrar () {
    if [ -z "$2" ]; then printf '  %-30s [ok] nada\n' "$1"
    else printf '  %-30s [!]\n' "$1"; printf '%s\n' "$2" | sed 's/^/        /'; fi
}
echo " --- cobran ---"
mostrar "RDS"                          "$RDS"
mostrar "EC2 (cualquiera)"             "$EC2"
mostrar "Buckets del parcial"          "$BUCKETS_PARCIAL"
mostrar "Snapshots manuales de RDS"    "$SNAPS"
mostrar "Backups automáticos retenidos" "$BACKUPS"
mostrar "Log groups de Glue"           "$LOGS"
echo " --- no cobran ---"
mostrar "Parámetros SSM /parcial"      "$SSM"
mostrar "Jobs de Glue"                 "$JOBS"
mostrar "Crawlers"                     "$CRAWLERS"
mostrar "Conexiones de Glue"           "$CONEXIONES"
mostrar "Databases del catálogo"       "$DATABASES"
mostrar "Security Groups (no default)" "$SGS"
mostrar "VPC Endpoints"                "$ENDPOINTS"
echo " --- para revisar a mano (no son del parcial) ---"
mostrar "Otros buckets"                "$BUCKETS_OTROS"

TODO="$RDS$EC2$BUCKETS_PARCIAL$SNAPS$BACKUPS$LOGS$SSM$JOBS$CRAWLERS$CONEXIONES$DATABASES$SGS"
if [ -z "$TODO" ]; then
    echo ""
    echo " LIMPIO: no queda nada del parcial."
    [ -n "$ENDPOINTS" ] && echo " (El VPC Endpoint de S3 es gratis y conviene dejarlo.)"
    exit 0
fi

# ---------------------------------------------------------------------------
#  Comandos de baja con los IDs de arriba. El orden importa:
#  los Security Groups no se pueden borrar mientras una RDS o una EC2 los use.
# ---------------------------------------------------------------------------
echo ""
echo "=============================================================="
echo " COMANDOS DE BAJA — copiar a mano, bloque por bloque"
echo "=============================================================="

if [ -n "$RDS$EC2" ]; then
    echo ""
    echo "# 1) Lo que cobra por hora. RDS sin snapshot final: los datos son sintéticos"
    echo "#    y se regeneran con los .sql del repo."
    for x in $RDS; do
        echo "aws rds delete-db-instance --db-instance-identifier $x --skip-final-snapshot --delete-automated-backups --region $R"
    done
    [ -n "$EC2" ] && echo "aws ec2 terminate-instances --instance-ids $(echo $EC2) --region $R"
    echo ""
    echo "# 2) Esperar a que terminen (5-10 min, el prompt vuelve solo)."
    for x in $RDS; do echo "aws rds wait db-instance-deleted --db-instance-identifier $x --region $R"; done
    [ -n "$EC2" ] && echo "aws ec2 wait instance-terminated --instance-ids $(echo $EC2) --region $R"
fi

if [ -n "$SNAPS$BACKUPS" ]; then
    echo ""
    echo "# 3) Copias de RDS que siguen cobrando storage"
    for x in $SNAPS;   do echo "aws rds delete-db-snapshot --db-snapshot-identifier $x --region $R"; done
    for x in $BACKUPS; do echo "aws rds delete-db-instance-automated-backup --db-instance-automated-backups-arn $x --region $R"; done
fi

echo ""
echo "# 4) Lo que no cobra, para dejar la cuenta limpia"
[ -n "$SSM" ] && echo "aws ssm delete-parameters --names $(echo $SSM) --region $R"
while IFS= read -r x; do [ -n "$x" ] && echo "aws glue delete-job --job-name \"$x\" --region $R"; done <<< "$JOBS"
while IFS= read -r x; do [ -n "$x" ] && echo "aws glue delete-crawler --name \"$x\" --region $R"; done <<< "$CRAWLERS"
while IFS= read -r x; do [ -n "$x" ] && echo "aws glue delete-connection --connection-name \"$x\" --region $R"; done <<< "$CONEXIONES"
while IFS= read -r x; do [ -n "$x" ] && echo "aws glue delete-database --name \"$x\" --region $R"; done <<< "$DATABASES"
while IFS= read -r x; do [ -n "$x" ] && echo "aws logs delete-log-group --log-group-name \"$x\" --region $R"; done <<< "$LOGS"
if [ -n "$SGS" ]; then
    # Reglas de un SG que NO se va a borrar (típicamente el default) que apuntan a uno
    # que sí: bloquean el borrado con DependencyViolation. Pasó con glue-sakila, que
    # seguía referenciado desde el default por la práctica de Sakila.
    aws ec2 describe-security-group-rules --region $R \
        --query "SecurityGroupRules[?ReferencedGroupInfo.GroupId!=null].[GroupId,SecurityGroupRuleId,IsEgress,ReferencedGroupInfo.GroupId]" \
        --output text 2>/dev/null |
    while read -r grupo regla egreso apunta; do
        printf '%s\n' $SGS | grep -qx "$apunta" || continue      # no apunta a uno que se borra
        printf '%s\n' $SGS | grep -qx "$grupo" && continue       # el que la tiene también se borra
        [ "$egreso" = "True" ] && tipo=egress || tipo=ingress
        echo "# $grupo tiene una regla hacia $apunta: hay que quitarla antes de borrarlo"
        echo "aws ec2 revoke-security-group-$tipo --group-id $grupo --security-group-rule-ids $regla --region $R"
    done
    echo "# Los SG se referencian entre sí (el de las bases apunta al de la API y al de"
    echo "# Glue): se reintenta hasta 3 vueltas para que caigan en el orden que se pueda."
    echo "for i in 1 2 3; do for sg in $(echo $SGS); do aws ec2 delete-security-group --group-id \$sg --region $R 2>/dev/null && echo \"borrado \$sg\"; done; done"
    echo "# Si alguno sobrevivió, esto muestra por qué (DependencyViolation = una EC2, una"
    echo "# interfaz de red u otro SG todavía lo usa o lo referencia):"
    echo "for sg in $(echo $SGS); do aws ec2 describe-security-groups --group-ids \$sg --region $R >/dev/null 2>&1 && aws ec2 delete-security-group --group-id \$sg --region $R; done"
fi

if [ -n "$BUCKETS_PARCIAL" ]; then
    echo ""
    echo "# 5) Buckets — IRREVERSIBLE. El data lake tiene versionado: 'aws s3 rb --force'"
    echo "#    no borra las versiones viejas y el bucket no se deja eliminar. Esto sí."
    echo "#    (Opcional, antes: respaldo de ~4 MB para bajar con Acciones → Descargar archivo)"
    for b in $BUCKETS_PARCIAL; do
        case "$b" in datalake-aerolinea-*)
            echo "#    aws s3 sync s3://$b ~/respaldo-datalake && tar czf ~/respaldo-datalake.tgz -C ~ respaldo-datalake" ;;
        esac
    done
    for b in $BUCKETS_PARCIAL; do
        echo "python3 -c \"import boto3; b=boto3.resource('s3').Bucket('$b'); b.object_versions.delete(); b.delete(); print('borrado $b')\""
    done
fi

cat <<'FIN'

# El VPC Endpoint de S3 (Gateway) es GRATIS y existía desde antes del parcial:
# conviene dejarlo para cualquier job de Glue que corra dentro de la VPC.

# Verificación final:
bash 02-baja-recursos.sh      # tiene que decir LIMPIO
==============================================================
FIN
