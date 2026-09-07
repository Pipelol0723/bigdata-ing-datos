#!/usr/bin/env bash
# =============================================================================
#  Crea la infraestructura del parcial en AWS  (sección 5.7)
#  Pegar en CloudShell, que ya trae las credenciales del Learner Lab.
# =============================================================================
#  CREA (no borra nada):
#    · 1 Security Group para Glue, con regla auto-referenciada
#    · 2 instancias RDS PostgreSQL db.t3.micro (OLTP y OLAP)
#    · reglas de entrada al 5432 desde el SG de Glue
#    · VPC Endpoint de S3 (gratis) si no existe
#
#  ⚠️ LA CONTRASEÑA NO VA EN EL SCRIPT. Exportala antes de correrlo:
#        export PG_PASSWORD='...'
#     Se pasa a AWS por parámetro y no queda en el repo (NFR-SEG-01).
#
#  ⚠️ Estas instancias CUESTAN ~$0.86/día entre las dos. Al terminar, correr
#     02-baja-recursos.sh y ejecutar los comandos de baja que imprime.
# =============================================================================

set -euo pipefail
export AWS_PAGER=""

REGION="${AWS_REGION:-us-east-1}"
CLASE="db.t3.micro"
ALMACENAMIENTO=20
USUARIO="parcial"
ID_OLTP="parcial-oltp"
ID_OLAP="parcial-olap"
TAGS="Key=Proyecto,Value=bigdata Key=Unidad,Value=parcial-1"

if [ -z "${PG_PASSWORD:-}" ]; then
    echo "ERROR: falta la variable PG_PASSWORD."
    echo "       export PG_PASSWORD='una-clave-segura'   y volvé a correr."
    exit 1
fi
if [ ${#PG_PASSWORD} -lt 8 ]; then
    echo "ERROR: RDS exige al menos 8 caracteres."
    exit 1
fi

echo "=============================================================="
echo " Creando infraestructura del parcial en $REGION"
echo "=============================================================="

# --- 1. VPC y subredes -------------------------------------------------------
VPC=$(aws ec2 describe-vpcs --region "$REGION" \
        --filters "Name=isDefault,Values=true" \
        --query "Vpcs[0].VpcId" --output text)
echo "VPC por defecto: $VPC"

# --- 2. Security Group de Glue ----------------------------------------------
# La regla auto-referenciada es OBLIGATORIA: Glue levanta varios workers que
# necesitan hablar entre ellos. Sin esto la conexión falla sin explicar por qué.
echo ""
echo "--- Security Group de Glue ---"
if SG_GLUE=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=group-name,Values=glue-parcial" "Name=vpc-id,Values=$VPC" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null) \
   && [ "$SG_GLUE" != "None" ]; then
    echo "ya existe: $SG_GLUE"
else
    SG_GLUE=$(aws ec2 create-security-group --region "$REGION" \
        --group-name glue-parcial \
        --description "Conexiones Glue del parcial 1" \
        --vpc-id "$VPC" --query GroupId --output text)
    aws ec2 authorize-security-group-ingress --region "$REGION" \
        --group-id "$SG_GLUE" --protocol -1 --source-group "$SG_GLUE" >/dev/null
    aws ec2 create-tags --region "$REGION" --resources "$SG_GLUE" --tags $TAGS
    echo "creado con regla auto-referenciada: $SG_GLUE"
fi

# --- 3. Security Group de las bases -----------------------------------------
echo ""
echo "--- Security Group de las bases ---"
if SG_DB=$(aws ec2 describe-security-groups --region "$REGION" \
        --filters "Name=group-name,Values=rds-parcial" "Name=vpc-id,Values=$VPC" \
        --query "SecurityGroups[0].GroupId" --output text 2>/dev/null) \
   && [ "$SG_DB" != "None" ]; then
    echo "ya existe: $SG_DB"
else
    SG_DB=$(aws ec2 create-security-group --region "$REGION" \
        --group-name rds-parcial \
        --description "RDS del parcial 1" \
        --vpc-id "$VPC" --query GroupId --output text)
    aws ec2 create-tags --region "$REGION" --resources "$SG_DB" --tags $TAGS
    echo "creado: $SG_DB"
fi

# Grupo a grupo: la base acepta a Glue por su SG, no por IP.
# Las IPs cambian; la pertenencia al grupo no.
aws ec2 authorize-security-group-ingress --region "$REGION" \
    --group-id "$SG_DB" --protocol tcp --port 5432 --source-group "$SG_GLUE" \
    2>/dev/null && echo "regla 5432 desde Glue: creada" \
    || echo "regla 5432 desde Glue: ya existia"

# --- 4. VPC Endpoint de S3 (gratis) -----------------------------------------
# Sin esto el crawler da timeout: los workers corren dentro de la VPC sin IP
# pública y no llegan a S3. El NAT Gateway resuelve lo mismo a $0.045/h.
echo ""
echo "--- VPC Endpoint de S3 ---"
EXISTE=$(aws ec2 describe-vpc-endpoints --region "$REGION" \
    --filters "Name=vpc-id,Values=$VPC" "Name=service-name,Values=com.amazonaws.$REGION.s3" \
    --query "length(VpcEndpoints)" --output text)
if [ "$EXISTE" = "0" ]; then
    RTBS=$(aws ec2 describe-route-tables --region "$REGION" \
        --filters "Name=vpc-id,Values=$VPC" \
        --query "RouteTables[].RouteTableId" --output text)
    aws ec2 create-vpc-endpoint --region "$REGION" --vpc-id "$VPC" \
        --service-name "com.amazonaws.$REGION.s3" \
        --vpc-endpoint-type Gateway --route-table-ids $RTBS \
        --query "VpcEndpoint.VpcEndpointId" --output text
    echo "creado (Gateway, sin costo)"
else
    echo "ya existe"
fi

# --- 5. Instancias RDS -------------------------------------------------------
crear_rds () {
    local id="$1" base="$2"
    echo ""
    echo "--- RDS $id ---"
    if aws rds describe-db-instances --region "$REGION" \
         --db-instance-identifier "$id" >/dev/null 2>&1; then
        echo "ya existe"
        return
    fi
    aws rds create-db-instance --region "$REGION" \
        --db-instance-identifier "$id" \
        --db-instance-class "$CLASE" \
        --engine postgres \
        --master-username "$USUARIO" \
        --master-user-password "$PG_PASSWORD" \
        --allocated-storage "$ALMACENAMIENTO" \
        --storage-type gp2 \
        --db-name "$base" \
        --vpc-security-group-ids "$SG_DB" \
        --backup-retention-period 1 \
        --no-multi-az \
        --no-publicly-accessible \
        --monitoring-interval 0 \
        --tags $TAGS \
        --query "DBInstance.DBInstanceIdentifier" --output text
    echo "creación iniciada"
}
# --monitoring-interval 0  → el Learner Lab NO permite enhanced monitoring
# --no-publicly-accessible → las bases no escuchan hacia internet (NFR-SEG-02).
#                            Glue llega por estar dentro de la VPC.

crear_rds "$ID_OLTP" "aerolinea"
crear_rds "$ID_OLAP" "aerolinea_dw"

# --- 6. Esperar y mostrar los endpoints -------------------------------------
echo ""
echo "Esperando a que ambas estén disponibles (5-10 min)..."
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$ID_OLTP"
aws rds wait db-instance-available --region "$REGION" --db-instance-identifier "$ID_OLAP"

echo ""
echo "=============================================================="
echo " LISTO"
echo "=============================================================="
for id in "$ID_OLTP" "$ID_OLAP"; do
    ep=$(aws rds describe-db-instances --region "$REGION" \
         --db-instance-identifier "$id" \
         --query "DBInstances[0].Endpoint.Address" --output text)
    echo "  $id : $ep"
done
echo ""
echo "  SG de Glue  : $SG_GLUE   (usarlo en las conexiones JDBC)"
echo "  SG de bases : $SG_DB"
echo ""
echo "  URL JDBC — ojo: DOS PUNTOS y puerto explícito"
echo "    jdbc:postgresql://<endpoint>:5432/aerolinea"
echo "    jdbc:postgresql://<endpoint>:5432/aerolinea_dw"
echo ""
echo "  Rol para Glue: LabRole  (cualquier otro da 'unable to assume provided role')"
echo ""
echo "  ⚠️  ~\$0.86/día entre las dos. Al terminar: bash 02-baja-recursos.sh"
