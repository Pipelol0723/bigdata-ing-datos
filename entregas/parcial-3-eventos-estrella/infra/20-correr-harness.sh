#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 20: corre el harness del profesor desde CloudShell
# =============================================================================
#  Por qué desde CloudShell: ya tiene las credenciales del lab y mide la latencia (R2) desde
#  adentro de AWS, como el P2.
#    1. Escribe harness/config.yaml con la IP actual de la EC2 y los nombres reales (cuenta).
#    2. Arma en /tmp el venv con las dependencias del harness (CloudShell lo borra entre sesiones).
#    3. Corre pytest: deja report.md y report.json en harness/ y una copia fechada en evidencia/.
#  ⚠️ El harness INYECTA ~20.500 eventos en el stream y tarda hasta ~25 min (replay, espera de
#     la entrega a S3 y refresh). Correrlo con nohup: CloudShell se desconecta si Chrome no está
#     al frente.
#
#  Uso (CloudShell):
#    nohup bash ~/p3/infra/20-correr-harness.sh > ~/p3/harness.log 2>&1 & tail -f --pid=$! ~/p3/harness.log
#    Sólo una parte:  bash ~/p3/infra/20-correr-harness.sh tests/test_1_stream.py -k live
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-comun.sh"
cd "$P3/harness"

IP=$(ip_ec2)
[ -n "$IP" ] && [ "$IP" != "None" ] || { echo "!! la EC2 $EC2_NOMBRE no está running"; exit 1; }
cat > config.yaml <<EOF
# Parcial 3 · config del harness (SIN credenciales: usa las del entorno, como la AWS CLI).
# La IP de la EC2 cambia en cada sesión del lab: la reescribe infra/20-correr-harness.sh.
team_id: "andres-cespedes"
seed: 12345              # semilla del parcial (individual)

backend:
  base_url: "http://$IP:8000"

aws:
  region: us-east-1
  kinesis_stream: $STREAM
  raw_events_uri: "$RAW_URI"
  athena_workgroup: $WG
  athena_database: $DB
  athena_output: "s3://$BUCKET/athena-results/"

cost_projection_file: ../cost_projection.yaml
EOF
echo "== EC2 en $IP: $(curl -fs --max-time 5 "http://$IP:8000/health" || echo 'NO RESPONDE')"
echo "== stream: $(aws kinesis describe-stream-summary --stream-name "$STREAM" --query StreamDescriptionSummary.StreamStatus --output text 2>/dev/null || echo 'NO EXISTE: correr 10-levantar-sesion.sh')"

if [ ! -x /tmp/h3/bin/python ]; then
    echo "== venv en /tmp/h3 (~1 min)"
    python3 -m venv /tmp/h3
    /tmp/h3/bin/pip install -q -r requirements.txt
fi

echo "== pytest $* ($(date -u '+%H:%M:%S') UTC)"
set +e
/tmp/h3/bin/python -m pytest "$@"
RC=$?
set -e
SELLO=$(date -u '+%Y-%m-%d_%H%M')
mkdir -p "$P3/evidencia/harness-$SELLO"
cp report.md report.json config.yaml "$P3/evidencia/harness-$SELLO/" 2>/dev/null || true
echo "== copia en evidencia/harness-$SELLO/ ; pytest terminó con código $RC"
grep -E "Automated score|^\| R" report.md || true
