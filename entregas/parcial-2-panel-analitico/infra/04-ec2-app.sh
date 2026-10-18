#!/usr/bin/env bash
# =============================================================================
#  Parcial 2 · F4: la app (FastAPI + frontend + PostgreSQL) en UNA EC2 con Docker (D1)
# =============================================================================
#  Empaqueta app/ y docker-compose.yml, los sube a S3 y lanza una EC2 Ubuntu 24.04 que,
#  al arrancar, instala Docker y levanta el compose. La base no publica ningún puerto.
#
#  · Tipo: t3.micro por defecto (D2: se mide R1 y se sube a t3.small sólo si no da).
#  · Rol: LabInstanceProfile (LabRole) -> el backend consulta Athena sin credenciales.
#  · IMDSv2 con hop limit 2: si no, boto3 DENTRO del contenedor no llega a las credenciales.
#  · Puerto 8000 abierto a todo internet: el profesor corre el harness desde su máquina y su
#    IP no se conoce. Es lo único expuesto; el 22 sólo para EC2 Instance Connect de AWS.
#  · restart: unless-stopped + docker al arranque: cuando el lab reinicia la instancia en
#    la sesión siguiente, la app vuelve sola (la IP pública cambia: actualizar config.yaml).
#
#  ⚠️ Cobra: t3.micro US$0,0104/h + IPv4 pública US$0,005/h + EBS 8 GB, mientras exista.
#     Una EC2 detenida se REINICIA sola en la próxima sesión del lab.
#
#  Uso (CloudShell, desde la carpeta con app/ y docker-compose.yml):
#        bash 04-ec2-app.sh [t3.micro|t3.small]
# =============================================================================
set -euo pipefail
export AWS_PAGER=""
R="us-east-1"
TIPO="${1:-t3.micro}"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aerolinea-p2-$CUENTA"
NOMBRE="parcial2-app"

[ -d app ] && [ -f docker-compose.yml ] || { echo "!! correr desde la carpeta que tiene app/ y docker-compose.yml"; exit 1; }
VIVA=$(aws ec2 describe-instances --region "$R" \
    --filters "Name=tag:Name,Values=$NOMBRE" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query "Reservations[].Instances[].InstanceId" --output text)
[ -z "$VIVA" ] || { echo "!! ya existe $NOMBRE: $VIVA (terminarla antes de crear otra)"; exit 1; }

# 1 · El paquete de la app, en S3, con una URL prefirmada que la instancia descarga al arrancar
tar czf /tmp/app.tgz app docker-compose.yml
aws s3 cp /tmp/app.tgz "s3://$BUCKET/deploy/app.tgz" --only-show-errors
URL=$(aws s3 presign "s3://$BUCKET/deploy/app.tgz" --expires-in 3600)
echo "== paquete en s3://$BUCKET/deploy/app.tgz =="

# 2 · Security group: 8000 al mundo (el harness), 22 sólo desde EC2 Instance Connect
VPC=$(aws ec2 describe-vpcs --region "$R" --filters Name=isDefault,Values=true --query "Vpcs[0].VpcId" --output text)
SG=$(aws ec2 describe-security-groups --region "$R" \
    --filters Name=group-name,Values=$NOMBRE Name=vpc-id,Values=$VPC --query "SecurityGroups[0].GroupId" --output text)
if [ "$SG" = "None" ]; then
    SG=$(aws ec2 create-security-group --region "$R" --group-name "$NOMBRE" --vpc-id "$VPC" \
        --description "Parcial 2: API+frontend en 8000; SSH solo por EC2 Instance Connect" \
        --tag-specifications "ResourceType=security-group,Tags=[{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=parcial2}]" \
        --query GroupId --output text)
    aws ec2 authorize-security-group-ingress --region "$R" --group-id "$SG" \
        --ip-permissions 'IpProtocol=tcp,FromPort=8000,ToPort=8000,IpRanges=[{CidrIp=0.0.0.0/0,Description=harness y profesor}]' >/dev/null
    PL=$(aws ec2 describe-managed-prefix-lists --region "$R" \
        --filters Name=prefix-list-name,Values=com.amazonaws.$R.ec2-instance-connect --query "PrefixLists[0].PrefixListId" --output text)
    [ "$PL" != "None" ] && aws ec2 authorize-security-group-ingress --region "$R" --group-id "$SG" \
        --ip-permissions "IpProtocol=tcp,FromPort=22,ToPort=22,PrefixListIds=[{PrefixListId=$PL,Description=EC2 Instance Connect}]" >/dev/null
    echo "== security group $SG creado =="
fi

# 3 · La instancia
AMI=$(aws ssm get-parameter --region "$R" \
    --name /aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id \
    --query Parameter.Value --output text)
cat > /tmp/user-data.sh <<EOF
#!/bin/bash
set -eux
apt-get update -y
apt-get install -y docker.io docker-compose-v2 curl
systemctl enable --now docker
mkdir -p /opt/parcial2 && cd /opt/parcial2
curl -fsSL "$URL" -o app.tgz && tar xzf app.tgz
cat > .env <<ENV
DB_PASSWORD=\$(openssl rand -hex 16)
ATHENA_DATABASE=airline_analytics
ATHENA_OUTPUT=s3://$BUCKET/athena-results/
ENV
docker compose up -d --build
EOF
ID=$(aws ec2 run-instances --region "$R" --image-id "$AMI" --instance-type "$TIPO" \
    --key-name vockey --security-group-ids "$SG" \
    --iam-instance-profile Name=LabInstanceProfile \
    --metadata-options "HttpTokens=required,HttpPutResponseHopLimit=2,HttpEndpoint=enabled" \
    --block-device-mappings 'DeviceName=/dev/sda1,Ebs={VolumeSize=8,VolumeType=gp3,DeleteOnTermination=true}' \
    --user-data file:///tmp/user-data.sh \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=$NOMBRE},{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=parcial2}]" \
                         "ResourceType=volume,Tags=[{Key=Proyecto,Value=bigdata},{Key=Unidad,Value=parcial2}]" \
    --query "Instances[0].InstanceId" --output text)
echo "== instancia $ID ($TIPO) lanzada; esperando que arranque =="
aws ec2 wait instance-running --region "$R" --instance-ids "$ID"
IP=$(aws ec2 describe-instances --region "$R" --instance-ids "$ID" \
    --query "Reservations[0].Instances[0].PublicIpAddress" --output text)
echo "== IP pública: $IP — instalando Docker y construyendo la app (3-6 min) =="

for i in $(seq 1 60); do
    if curl -fs --max-time 3 "http://$IP:8000/health" >/dev/null; then
        echo "== APP ARRIBA tras ~$((i * 10)) s =="
        curl -s "http://$IP:8000/health"; echo
        break
    fi
    sleep 10
done
curl -fs --max-time 3 "http://$IP:8000/health" >/dev/null || {
    echo "!! la app no respondió en 10 min. Log de arranque:"
    echo "   aws ec2 get-console-output --instance-id $ID --region $R --latest --output text | tail -40"; exit 1; }
cat <<EOF

Para harness/config.yaml:
  backend:  base_url: "http://$IP:8000"
  frontend: base_url: "http://$IP:8000"
Páginas:  http://$IP:8000/   y   http://$IP:8000/manager
EOF
