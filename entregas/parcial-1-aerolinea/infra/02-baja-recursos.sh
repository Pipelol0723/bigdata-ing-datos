#!/usr/bin/env bash
# =============================================================================
#  Baja de la infraestructura del parcial  —  SÓLO LECTURA
# =============================================================================
#  Este script NO borra nada. Inspecciona qué quedó vivo y al final IMPRIME los
#  comandos de baja para copiar a mano los que se quieran ejecutar.
#
#  Es una regla del proyecto (ver ../../CLAUDE.md): los comandos destructivos se
#  entregan aparte, nunca automatizados. Un `terminate` disparado por un script
#  que se corrió sin leer es irreversible.
#
#  Uso:  bash 02-baja-recursos.sh
# =============================================================================

export AWS_PAGER=""
REGION="${AWS_REGION:-us-east-1}"

echo "=============================================================="
echo " QUÉ SIGUE VIVO   —   $(date '+%Y-%m-%d %H:%M')"
echo "=============================================================="

mostrar () {
    local titulo="$1"; shift
    local salida
    salida=$("$@" 2>/dev/null)
    if [ -z "$salida" ] || [ "$salida" = "None" ]; then
        printf '  %-26s [ok] nada\n' "$titulo"
    else
        printf '  %-26s [!] revisar\n' "$titulo"
        printf '%s\n' "$salida" | sed 's/^/        /'
    fi
}

mostrar "EC2 de la API" \
    aws ec2 describe-instances --region "$REGION" \
      --filters "Name=tag:Name,Values=api-parcial" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
      --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name]" \
      --output text

mostrar "Parámetros SSM /parcial" \
    aws ssm get-parameters-by-path --region "$REGION" --path /parcial \
      --query "Parameters[].Name" --output text

mostrar "RDS del parcial" \
    aws rds describe-db-instances --region "$REGION" \
      --query "DBInstances[?starts_with(DBInstanceIdentifier,'parcial-')].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus,AllocatedStorage]" \
      --output text

mostrar "Conexiones de Glue" \
    aws glue get-connections --region "$REGION" \
      --query "ConnectionList[].[Name,ConnectionType]" --output text

mostrar "Crawlers" \
    aws glue list-crawlers --region "$REGION" --query "CrawlerNames" --output text

mostrar "Databases del catálogo" \
    aws glue get-databases --region "$REGION" --query "DatabaseList[].Name" --output text

mostrar "Jobs de Glue" \
    aws glue list-jobs --region "$REGION" --query "JobNames" --output text

mostrar "Security Groups del parcial" \
    aws ec2 describe-security-groups --region "$REGION" \
      --filters "Name=tag:Proyecto,Values=bigdata" \
      --query "SecurityGroups[].[GroupId,GroupName]" --output text

mostrar "Snapshots manuales" \
    aws rds describe-db-snapshots --region "$REGION" --snapshot-type manual \
      --query "DBSnapshots[?starts_with(DBInstanceIdentifier,'parcial-')].[DBSnapshotIdentifier,AllocatedStorage]" \
      --output text

cat <<'REFERENCIA'

==============================================================
 COMANDOS DE BAJA — copiar a mano los que correspondan
==============================================================

 ⚠️ Las dos RDS cobran storage (~$4.60/mes entre ambas) AUNQUE ESTÉN
    DETENIDAS, y AWS las reinicia solas a los 7 días de detenidas.
    Después de la defensa la consigna es BORRARLAS, no detenerlas:
    el esquema y los scripts quedan en el repo y recrear todo son 5 minutos.

 --- EC2 de la API (terminar, NO detener: detenida se reinicia sola) ---
 aws ec2 terminate-instances --instance-ids <i-...> --region us-east-1

 --- Parámetros de SSM (la contraseña cifrada y los endpoints) ---
 aws ssm delete-parameters --names /parcial/pg_password /parcial/ep_oltp \
     /parcial/ep_olap /parcial/bucket --region us-east-1

 --- Borrar las bases (sin snapshot: los datos son sintéticos) ---
 aws rds delete-db-instance --db-instance-identifier parcial-oltp \
     --skip-final-snapshot --delete-automated-backups --region us-east-1

 aws rds delete-db-instance --db-instance-identifier parcial-olap \
     --skip-final-snapshot --delete-automated-backups --region us-east-1

 --- Si se prefiere conservar los datos, con snapshot final ---
 aws rds delete-db-instance --db-instance-identifier parcial-oltp \
     --final-db-snapshot-identifier parcial-oltp-final --region us-east-1

 --- Objetos de Glue (no cobran en reposo; borrar sólo para dejar limpio) ---
 aws glue delete-crawler    --name <nombre-del-crawler> --region us-east-1
 aws glue delete-connection --connection-name <nombre>  --region us-east-1
 aws glue delete-database   --name <nombre-database>    --region us-east-1
 aws glue delete-job        --job-name <nombre-del-job> --region us-east-1

 --- Security Groups (gratis; borrar DESPUÉS de las RDS que los usan) ---
 aws ec2 delete-security-group --group-id <sg-...> --region us-east-1

 --- El VPC Endpoint de S3 es GRATIS: conviene dejarlo ---

 --- Verificación final ---
 bash 02-baja-recursos.sh     # debe dar [ok] en todo

==============================================================
REFERENCIA
