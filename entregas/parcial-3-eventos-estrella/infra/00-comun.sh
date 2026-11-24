#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · nombres comunes de todos los scripts (se incluye con `source`).
#  Todo deriva del ID de la cuenta: sirve igual en otra cuenta del lab.
# =============================================================================
export AWS_PAGER=""
export AWS_DEFAULT_REGION="us-east-1"
R="us-east-1"
CUENTA=$(aws sts get-caller-identity --query Account --output text)
BUCKET="aerolinea-p3-$CUENTA"              # landing (raw/), estrella (star/), ref/, deploy/, athena-results/
STREAM="airline-events"                    # Kinesis: 1 shard provisionado (R11)
FIREHOSE="airline-events-a-s3"             # entrega gestionada Kinesis -> S3 (D4)
DB="airline_star"                          # base del Glue Data Catalog
WG="parcial3"                              # workgroup de Athena con límite de 1 GB por consulta (R10, D10)
RAW_URI="s3://$BUCKET/raw/events/"         # landing zone (config.yaml: raw_events_uri)
ROL="arn:aws:iam::$CUENTA:role/LabRole"    # el único rol que deja usar el Learner Lab
EC2_NOMBRE="parcial2-app"                  # la EC2 del P2, reutilizada (D1)
P3="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"   # carpeta del parcial (app/, harness/, ref/...)

ip_ec2 () {
    aws ec2 describe-instances --region "$R" \
        --filters "Name=tag:Name,Values=$EC2_NOMBRE" Name=instance-state-name,Values=running \
        --query "Reservations[].Instances[].PublicIpAddress" --output text
}
id_ec2 () {
    aws ec2 describe-instances --region "$R" \
        --filters "Name=tag:Name,Values=$EC2_NOMBRE" Name=instance-state-name,Values=running \
        --query "Reservations[].Instances[].InstanceId" --output text
}
paso () { echo; echo "=== $* ==="; }
