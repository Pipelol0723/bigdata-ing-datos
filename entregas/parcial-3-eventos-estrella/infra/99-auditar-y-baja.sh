#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 99: qué quedó vivo (P3 y restos del P2) y cómo se va  —  SÓLO LECTURA
# =============================================================================
#  No borra nada: audita e IMPRIME los comandos de baja con los nombres reales, para copiarlos a
#  mano (regla del proyecto, CLAUDE.md). La baja completa del P3 va DESPUÉS de la defensa.
#  Uso (CloudShell):  bash ~/p3/infra/99-auditar-y-baja.sh
# =============================================================================
source "$(dirname "$0")/00-comun.sh"
tam () { aws s3api list-objects-v2 --bucket "$1" --query "[sum(Contents[].Size), length(Contents[])]" --output text 2>/dev/null || echo "no existe"; }

echo "=============================================================="
echo " PARCIAL 3 — QUÉ SIGUE VIVO   —   $(date '+%Y-%m-%d %H:%M')"
echo "=============================================================="
echo " Stream $STREAM:      $(aws kinesis describe-stream-summary --stream-name "$STREAM" --query 'StreamDescriptionSummary.[StreamStatus,OpenShardCount]' --output text 2>/dev/null || echo 'no existe')   <- US\$0,015/h"
echo " Firehose $FIREHOSE: $(aws firehose describe-delivery-stream --delivery-stream-name "$FIREHOSE" --query DeliveryStreamDescription.DeliveryStreamStatus --output text 2>/dev/null || echo 'no existe')"
echo " EC2 $EC2_NOMBRE:     $(aws ec2 describe-instances --filters "Name=tag:Name,Values=$EC2_NOMBRE" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].[InstanceId,State.Name,PublicIpAddress]' --output text)"
echo " Bucket P3 $BUCKET:  $(tam "$BUCKET") (bytes, objetos)"
echo " Bucket P2 aerolinea-p2-$CUENTA:  $(tam "aerolinea-p2-$CUENTA")"
echo " Glue: $(aws glue get-databases --query 'DatabaseList[].Name' --output text)"
echo " Workgroups: $(aws athena list-work-groups --query 'WorkGroups[].Name' --output text)"
echo " Todas las EC2 prendidas:"; aws ec2 describe-instances --filters Name=instance-state-name,Values=pending,running \
    --query "Reservations[].Instances[].[InstanceId,InstanceType,Tags[?Key=='Name']|[0].Value]" --output text | sed 's/^/   /'
echo " Todos los streams: $(aws kinesis list-streams --query StreamNames --output text)"

cat <<EOF

==============================================================
 COMANDOS DE BAJA — copiar a mano, sólo lo que corresponda
==============================================================
 # Al terminar CADA sesión (lo único que cobra por hora del P3):
 bash ~/p3/infra/90-bajar-stream.sh --confirmo

 # Restos del PARCIAL 2 (ya calificado; el P3 no los usa):
 aws s3 rb s3://aerolinea-p2-$CUENTA --force
 aws glue delete-database --name airline_analytics

 # Baja completa del PARCIAL 3 (DESPUÉS de la defensa y de la nota):
 bash ~/p3/infra/90-bajar-stream.sh --confirmo
 aws glue delete-database --name $DB
 aws athena delete-work-group --work-group $WG --recursive-delete-option
 aws s3 rb s3://$BUCKET --force
 # La EC2 (P2 y P3) y su security group: terminar, no detener (en el lab se reinicia sola)
 aws ec2 terminate-instances --instance-ids $(aws ec2 describe-instances --filters "Name=tag:Name,Values=$EC2_NOMBRE" Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)
 aws ec2 wait instance-terminated --instance-ids <id de arriba>
 aws ec2 delete-security-group --group-id $(aws ec2 describe-security-groups --filters Name=group-name,Values=$EC2_NOMBRE --query 'SecurityGroups[0].GroupId' --output text)
EOF
