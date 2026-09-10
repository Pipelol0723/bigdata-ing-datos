#!/usr/bin/env bash
# =============================================================================
#  Crea la EC2 de la aplicación (backend) dentro de la VPC    — correr en CloudShell
# =============================================================================
#  CREA (no borra nada):
#    · SG `api-parcial`: SSH SÓLO desde el servicio EC2 Instance Connect
#      (prefix list administrada por AWS), nunca desde 0.0.0.0/0
#    · regla en el SG de las bases: 5432 desde `api-parcial` (grupo a grupo)
#    · 3 parámetros en SSM Parameter Store: contraseña (cifrada) y endpoints
#    · la instancia: t3.micro, Amazon Linux 2023, LabInstanceProfile
#
#  POR QUÉ UNA EC2: las RDS son privadas y CloudShell corre FUERA de la VPC.
#  Todo lo que tenga que hablar con la base —la API, el ETL, la carga de los
#  .sql— tiene que correr adentro. La EC2 es ese "adentro".
#
#  Requiere ~/env.sh (lo crea la sesión del 08/09) y ~/.pg_parcial (contraseña).
#  💰 t3.micro ≈ $0,0104/h. Terminarla al cerrar: ver 02-baja-recursos.sh
# =============================================================================
set -euo pipefail
export AWS_PAGER=""
source ~/env.sh

for v in VPC SUBNET SG_DB EP_OLTP EP_OLAP BUCKET; do
    [ -n "${!v:-}" ] || { echo "ERROR: falta $v en ~/env.sh"; exit 1; }
done
[ -s ~/.pg_parcial ] || { echo "ERROR: falta ~/.pg_parcial"; exit 1; }

# --- 1. Security Group de la aplicación --------------------------------------
if SG_APP=$(aws ec2 describe-security-groups \
        --filters Name=group-name,Values=api-parcial Name=vpc-id,Values=$VPC \
        --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null) \
   && [ "$SG_APP" != "None" ]; then
    echo "[=] SG api-parcial ya existe: $SG_APP"
else
    SG_APP=$(aws ec2 create-security-group --group-name api-parcial \
        --description "EC2 de la API del parcial 1" --vpc-id $VPC \
        --query GroupId --output text)
    aws ec2 create-tags --resources $SG_APP \
        --tags Key=Proyecto,Value=bigdata Key=Unidad,Value=parcial-1
    echo "[+] SG api-parcial: $SG_APP"
fi

# SSH sólo desde EC2 Instance Connect. La consola abre la terminal en el
# navegador pasando por este servicio: no hace falta abrir el 22 a internet
# ni tener una clave en la máquina local.
PL=$(aws ec2 describe-managed-prefix-lists \
    --filters Name=prefix-list-name,Values=com.amazonaws.us-east-1.ec2-instance-connect \
    --query 'PrefixLists[0].PrefixListId' --output text)
aws ec2 authorize-security-group-ingress --group-id $SG_APP \
    --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,PrefixListIds=[{PrefixListId=$PL}]" \
    >/dev/null 2>&1 && echo "[+] 22 desde EC2 Instance Connect ($PL)" \
    || echo "[=] regla 22 ya existía"

# La base acepta a la API por PERTENENCIA AL GRUPO, no por IP.
aws ec2 authorize-security-group-ingress --group-id $SG_DB \
    --protocol tcp --port 5432 --source-group $SG_APP \
    >/dev/null 2>&1 && echo "[+] 5432 en las bases desde api-parcial" \
    || echo "[=] regla 5432 ya existía"

# --- 2. Secretos y configuración en SSM Parameter Store ----------------------
# La contraseña NO viaja en el user-data, ni en el repo, ni en la línea de
# comando de la EC2: se guarda cifrada y la instancia la lee con su rol.
aws ssm put-parameter --name /parcial/pg_password --type SecureString \
    --value "$(cat ~/.pg_parcial)" --overwrite >/dev/null
aws ssm put-parameter --name /parcial/ep_oltp --type String --value "$EP_OLTP" --overwrite >/dev/null
aws ssm put-parameter --name /parcial/ep_olap --type String --value "$EP_OLAP" --overwrite >/dev/null
aws ssm put-parameter --name /parcial/bucket  --type String --value "$BUCKET"  --overwrite >/dev/null
echo "[+] parámetros /parcial/* en SSM (contraseña como SecureString)"

# --- 3. La instancia ---------------------------------------------------------
INST=$(aws ec2 describe-instances \
    --filters Name=tag:Name,Values=api-parcial Name=instance-state-name,Values=pending,running,stopped \
    --query 'Reservations[0].Instances[0].InstanceId' --output text)
if [ "$INST" != "None" ]; then
    echo "[=] la instancia ya existe: $INST"
else
    INST=$(aws ec2 run-instances \
        --image-id resolve:ssm:/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
        --instance-type t3.micro \
        --key-name vockey \
        --iam-instance-profile Name=LabInstanceProfile \
        --security-group-ids $SG_APP \
        --subnet-id $SUBNET \
        --associate-public-ip-address \
        --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=api-parcial},{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=parcial-1}]' \
        --query 'Instances[0].InstanceId' --output text)
    echo "[+] instancia lanzada: $INST — esperando que arranque..."
    aws ec2 wait instance-running --instance-ids $INST
fi

grep -q '^export SG_APP=' ~/env.sh || echo "export SG_APP=$SG_APP" >> ~/env.sh
grep -q '^export INST='   ~/env.sh || echo "export INST=$INST"     >> ~/env.sh

# --- 4. Subir el código de la aplicación a S3 --------------------------------
# La EC2 lo baja de ahí con su rol. S3 es el artefacto; la instancia es
# descartable y se puede recrear sin perder nada.
ORIGEN="${1:-$HOME/repo/entregas/parcial-1-aerolinea}"
if [ -d "$ORIGEN/api" ]; then
    aws s3 cp "$ORIGEN" s3://$BUCKET/app/ --recursive --only-show-errors \
        --exclude "evidencia/*" --exclude "*.pyc" --exclude "*/__pycache__/*"
    echo "[+] código subido a s3://$BUCKET/app/"
else
    echo "[!] no encuentro el código en $ORIGEN — subilo a mano (ver la guía, paso 2)"
fi

echo ""
echo "=============================================================="
echo " LISTO  —  instancia $INST"
echo "=============================================================="
echo " Abrí la terminal de la EC2:"
echo "   Consola EC2 → Instancias → api-parcial → Conectar →"
echo "   pestaña 'EC2 Instance Connect' → Conectar"
echo ""
echo " Y ahí adentro:"
echo "   aws s3 cp s3://$BUCKET/app/infra/04-instalar-en-ec2.sh . && bash 04-instalar-en-ec2.sh"
