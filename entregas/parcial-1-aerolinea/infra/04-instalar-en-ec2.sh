#!/usr/bin/env bash
# =============================================================================
#  Instala y levanta la API DENTRO de la EC2          — correr EN la EC2
# =============================================================================
#  Se abre la terminal con: Consola EC2 → api-parcial → Conectar →
#  EC2 Instance Connect. Después:
#
#     aws s3 cp s3://<bucket>/app/infra/04-instalar-en-ec2.sh . && bash 04-instalar-en-ec2.sh
#
#  Deja:
#    /opt/aerolinea/            el código (bajado de S3)
#    /opt/aerolinea/.venv/      Python 3.11 con las dependencias
#    ~/aerolinea.env            conexiones, leídas de SSM (chmod 600)
#    servicio systemd `aerolinea`: la API en 127.0.0.1:8010
#
#  La API escucha SÓLO en 127.0.0.1: no queda expuesta a internet. Se prueba
#  con curl desde esta misma terminal.
# =============================================================================
set -euo pipefail

# La CLI dentro de la EC2 NO adivina la región: sin esto, cada llamada falla
# con "You must specify a region".
export AWS_DEFAULT_REGION=us-east-1
grep -q AWS_DEFAULT_REGION ~/.bashrc || echo 'export AWS_DEFAULT_REGION=us-east-1' >> ~/.bashrc

echo "=== 1/5  paquetes del sistema ==="
sudo dnf install -y -q python3.11 python3.11-pip
sudo dnf install -y -q postgresql16 2>/dev/null || sudo dnf install -y -q postgresql15
python3.11 --version
psql --version

echo "=== 2/5  código desde S3 ==="
BUCKET=$(aws ssm get-parameter --name /parcial/bucket --query Parameter.Value --output text)
sudo mkdir -p /opt/aerolinea
sudo chown ec2-user:ec2-user /opt/aerolinea
aws s3 cp s3://$BUCKET/app/ /opt/aerolinea/ --recursive --only-show-errors
ls /opt/aerolinea

echo "=== 3/5  entorno de Python ==="
cd /opt/aerolinea
python3.11 -m venv .venv
.venv/bin/pip install -q --upgrade pip
.venv/bin/pip install -q -r api/requirements.txt pandas pyarrow
.venv/bin/python -c "import fastapi, psycopg, pandas; print('dependencias OK')"

echo "=== 4/5  conexiones (desde SSM, nunca en el código) ==="
PW=$(aws ssm get-parameter --name /parcial/pg_password --with-decryption --query Parameter.Value --output text)
EP_OLTP=$(aws ssm get-parameter --name /parcial/ep_oltp --query Parameter.Value --output text)
EP_OLAP=$(aws ssm get-parameter --name /parcial/ep_olap --query Parameter.Value --output text)
umask 077
cat > ~/aerolinea.env <<EOF
DSN_OLTP=postgresql://parcial:$PW@$EP_OLTP:5432/aerolinea
DSN_OLAP=postgresql://parcial:$PW@$EP_OLAP:5432/aerolinea_dw
BUCKET=$BUCKET
EOF
umask 022
unset PW
ls -l ~/aerolinea.env
# Probar que la base es alcanzable ANTES de levantar nada
set -a; . ~/aerolinea.env; set +a
psql "$DSN_OLTP" -tAc "select 'OLTP OK - ' || count(*) || ' tablas' from information_schema.tables where table_schema='reservas'"
psql "$DSN_OLAP" -tAc "select 'OLAP OK - ' || count(*) || ' tablas' from information_schema.tables where table_schema='dw'"

echo "=== 5/5  servicio de la API ==="
sudo tee /etc/systemd/system/aerolinea.service >/dev/null <<'EOF'
[Unit]
Description=API del sistema de reservas (Parcial 1)
After=network-online.target
Wants=network-online.target

[Service]
User=ec2-user
WorkingDirectory=/opt/aerolinea/api
EnvironmentFile=/home/ec2-user/aerolinea.env
ExecStart=/opt/aerolinea/.venv/bin/uvicorn main:app --host 127.0.0.1 --port 8010
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now aerolinea
sleep 3
curl -s http://127.0.0.1:8010/salud; echo

cat <<'FIN'

==============================================================
 LISTO
==============================================================
 Cargar el entorno en cada terminal nueva:
   cd /opt/aerolinea && . .venv/bin/activate && set -a && . ~/aerolinea.env && set +a

 Probar la API:        curl -s http://127.0.0.1:8010/salud
 Logs de la API:       journalctl -u aerolinea -f
 Reiniciar la API:     sudo systemctl restart aerolinea
==============================================================
FIN
