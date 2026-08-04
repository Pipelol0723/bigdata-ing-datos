#!/usr/bin/env bash
# =============================================================================
#  auditar-recursos.sh -- Learner Lab: ¿qué tengo prendido y cobrando?
# =============================================================================
#  Este script SOLO LEE. No apaga, no termina y no borra absolutamente nada.
#  Al final imprime, como referencia, los comandos para dar de baja cada tipo
#  de recurso -- para que los copies vos, a mano, sólo los que quieras.
#
#  Uso en CloudShell:
#      bash auditar-recursos.sh
#
#  Correlo al ABRIR la sesión (para cazar zombies de la sesión anterior)
#  y al CERRARLA (para no dejar nada cobrando).
# =============================================================================

export AWS_PAGER=""
REGIONES="us-east-1 us-west-2"
HALLAZGOS=0

# chk "titulo" comando...
#   [ok]     -> no hay nada de eso
#   [!]      -> hay recursos, los lista
#   [?]      -> la llamada falló (típico: permiso denegado en el lab)
chk() {
  local titulo="$1"; shift
  local salida err rc
  err=$(mktemp)
  salida=$("$@" 2>"$err"); rc=$?
  if [ $rc -ne 0 ]; then
    printf '  %-30s [?] %s\n' "$titulo" "$(head -c 90 "$err" | tr '\n' ' ')"
  elif [ -z "$salida" ] || [ "$salida" = "None" ]; then
    printf '  %-30s [ok] nada\n' "$titulo"
  else
    printf '  %-30s [!] REVISAR\n' "$titulo"
    printf '%s\n' "$salida" | sed 's/^/         /'
    HALLAZGOS=$((HALLAZGOS + 1))
  fi
  rm -f "$err"
}

echo "============================================================"
echo " AUDITORIA LEARNER LAB   --   $(date '+%Y-%m-%d %H:%M:%S')"
echo " Cuenta: $(aws sts get-caller-identity --query Account --output text 2>/dev/null)"
echo "============================================================"

# ---------------------------------------------------------------- global -----
echo ""
echo "### GLOBAL"
chk "S3 buckets" \
    aws s3api list-buckets --query "Buckets[].Name" --output text

# ------------------------------------------------------------- por region ----
for R in $REGIONES; do
  echo ""
  echo "### REGION $R"

  # --- computo -----------------------------------------------------------
  chk "EC2 running/stopped" \
      aws ec2 describe-instances --region "$R" \
        --filters "Name=instance-state-name,Values=running,stopped" \
        --query "Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key=='Name']|[0].Value]" \
        --output text

  chk "EBS sin adjuntar" \
      aws ec2 describe-volumes --region "$R" \
        --filters "Name=status,Values=available" \
        --query "Volumes[].[VolumeId,Size,VolumeType]" --output text

  chk "Elastic IP sin asociar" \
      aws ec2 describe-addresses --region "$R" \
        --query 'Addresses[?AssociationId==`null`].[PublicIp,AllocationId]' --output text

  chk "NAT Gateways activos" \
      aws ec2 describe-nat-gateways --region "$R" \
        --filter "Name=state,Values=available" \
        --query "NatGateways[].[NatGatewayId,VpcId]" --output text

  chk "Load balancers" \
      aws elbv2 describe-load-balancers --region "$R" \
        --query "LoadBalancers[].[LoadBalancerName,Type,State.Code]" --output text

  # --- lo caro -----------------------------------------------------------
  chk "Redshift clusters" \
      aws redshift describe-clusters --region "$R" \
        --query "Clusters[].[ClusterIdentifier,NodeType,NumberOfNodes,ClusterStatus]" --output text

  chk "EMR clusters activos" \
      aws emr list-clusters --region "$R" --active \
        --query "Clusters[].[Id,Name,Status.State]" --output text

  chk "RDS instancias" \
      aws rds describe-db-instances --region "$R" \
        --query "DBInstances[].[DBInstanceIdentifier,DBInstanceClass,DBInstanceStatus]" --output text

  chk "SageMaker notebooks" \
      aws sagemaker list-notebook-instances --region "$R" \
        --query "NotebookInstances[].[NotebookInstanceName,InstanceType,NotebookInstanceStatus]" \
        --output text

  chk "SageMaker apps (Canvas)" \
      aws sagemaker list-apps --region "$R" \
        --query "Apps[?Status!='Deleted'].[AppType,AppName,UserProfileName,Status]" --output text

  # --- datos / streaming -------------------------------------------------
  chk "Glue interactive sessions" \
      aws glue list-sessions --region "$R" \
        --query "Sessions[?Status!='STOPPED'&&Status!='FAILED'].[Id,Status]" --output text

  chk "Kinesis streams" \
      aws kinesis list-streams --region "$R" --query "StreamNames" --output text

  chk "DynamoDB tablas" \
      aws dynamodb list-tables --region "$R" --query "TableNames" --output text

  # --- infra como codigo -------------------------------------------------
  chk "CloudFormation stacks" \
      aws cloudformation list-stacks --region "$R" \
        --stack-status-filter CREATE_COMPLETE UPDATE_COMPLETE UPDATE_ROLLBACK_COMPLETE \
                              ROLLBACK_COMPLETE CREATE_IN_PROGRESS \
        --query "StackSummaries[].[StackName,StackStatus]" --output text
done

# ------------------------------------------------------------- resumen -------
echo ""
echo "============================================================"
if [ "$HALLAZGOS" -eq 0 ]; then
  echo " LIMPIO: no se encontraron recursos cobrando."
else
  echo " ATENCION: $HALLAZGOS tipo(s) de recurso con cosas vivas."
  echo " Revisá las lineas marcadas con [!] antes de cerrar la sesión."
fi
echo "============================================================"

cat <<'REFERENCIA'

------------------------------------------------------------------
 COMANDOS DE BAJA (referencia -- copiá sólo lo que quieras ejecutar)
 Reemplazá <...> por el ID que apareció arriba. Agregá --region si
 el recurso está en us-west-2.
------------------------------------------------------------------

 # Si lo levantaste con CloudFormation, esto se lleva TODO junto:
 aws cloudformation delete-stack --stack-name <NOMBRE>

 # EC2 -- OJO: en el Learner Lab "stop" NO alcanza, se reinician solas.
 aws ec2 terminate-instances --instance-ids <i-xxxx>

 # Volúmenes EBS huérfanos y Elastic IPs sueltas (cobran sin hacer nada)
 aws ec2 delete-volume  --volume-id <vol-xxxx>
 aws ec2 release-address --allocation-id <eipalloc-xxxx>

 # Redshift -- lo más caro del lab. Sin snapshot final:
 aws redshift delete-cluster --cluster-identifier <ID> --skip-final-cluster-snapshot

 # EMR -- guardá los resultados en S3 ANTES de matarlo
 aws emr terminate-clusters --cluster-ids <j-xxxx>

 # RDS
 aws rds delete-db-instance --db-instance-identifier <ID> \
     --skip-final-snapshot --delete-automated-backups

 # SageMaker
 aws sagemaker stop-notebook-instance   --notebook-instance-name <NOMBRE>
 aws sagemaker delete-notebook-instance --notebook-instance-name <NOMBRE>
 aws sagemaker delete-app --domain-id <d-xxxx> --user-profile-name <USER> \
     --app-type Canvas --app-name <NOMBRE>

 # Kinesis
 aws kinesis delete-stream --stream-name <NOMBRE> --enforce-consumer-deletion

 # NAT Gateway
 aws ec2 delete-nat-gateway --nat-gateway-id <nat-xxxx>

------------------------------------------------------------------
REFERENCIA
