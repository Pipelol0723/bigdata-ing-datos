#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 03: despliega la API nueva en la EC2 del parcial 2 (decisión D1), por SSM
# =============================================================================
#  · Empaqueta app/ y docker-compose.yml, los sube a s3://BUCKET/deploy/ y la EC2 los baja con
#    una URL prefirmada (1 h). Sin SSH: SSM Run Command, como el 22/10 (la EC2 ya está registrada).
#  · En la EC2 usa LA MISMA carpeta del P2 (/opt/parcial2): el proyecto de docker compose y el
#    volumen de PostgreSQL son los mismos -> los vuelos y reservas existentes se conservan.
#  · Agrega/actualiza en .env las variables del P3 (bucket, stream, base, workgroup, refresh).
#  · Reconstruye la imagen y reinicia sólo la app (~2-4 min en una t3.micro).
#
#  No crea ni borra recursos de AWS (salvo el objeto deploy/app.tgz en el bucket).
#  Uso (CloudShell):  bash ~/p3/infra/03-desplegar-app.sh
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-comun.sh"

ID=$(id_ec2); IP=$(ip_ec2)
[ -n "$ID" ] && [ "$ID" != "None" ] || { echo "!! la EC2 $EC2_NOMBRE no está running (¿arrancó la sesión del lab?)"; exit 1; }
paso "EC2 $ID en $IP"

cd "$P3"
tar czf /tmp/app-p3.tgz app docker-compose.yml
aws s3 cp /tmp/app-p3.tgz "s3://$BUCKET/deploy/app-p3.tgz" --only-show-errors
URL=$(aws s3 presign "s3://$BUCKET/deploy/app-p3.tgz" --expires-in 3600)

python3 - "$URL" "$BUCKET" "$STREAM" "$DB" "$WG" > /tmp/ssm-desplegar.json <<'PY'
import json, sys
url, bucket, stream, db, wg = sys.argv[1:6]
variables = {"STAR_BUCKET": bucket, "KINESIS_STREAM": stream, "STAR_DB": db,
             "STAR_WORKGROUP": wg, "REFRESH_CADA_MIN": "10"}
cmds = ["set -e", "cd /opt/parcial2", f"curl -fsSL '{url}' -o app-p3.tgz",
        "rm -rf app && tar xzf app-p3.tgz"]
for k, v in variables.items():      # agregar o reemplazar cada variable en .env
    cmds.append(f"grep -q '^{k}=' .env && sed -i 's|^{k}=.*|{k}={v}|' .env || echo '{k}={v}' >> .env")
cmds += ["docker compose up -d --build 2>&1 | tail -5", "docker compose ps",
         "grep -E '^(STAR_|KINESIS_|REFRESH_)' .env"]
print(json.dumps({"commands": cmds}))
PY

paso "SSM: bajar el paquete, actualizar .env y reconstruir la app"
CMD=$(aws ssm send-command --instance-ids "$ID" --document-name AWS-RunShellScript \
    --comment "parcial3: desplegar API" --timeout-seconds 900 \
    --parameters file:///tmp/ssm-desplegar.json --query Command.CommandId --output text)
for _ in $(seq 1 90); do
    E=$(aws ssm get-command-invocation --command-id "$CMD" --instance-id "$ID" --query Status --output text 2>/dev/null || echo Pending)
    case "$E" in Success|Failed|Cancelled|TimedOut) break;; esac
    sleep 10
done
aws ssm get-command-invocation --command-id "$CMD" --instance-id "$ID" \
    --query "[Status, StandardOutputContent, StandardErrorContent]" --output text | tail -25
[ "$E" = "Success" ] || { echo "!! el despliegue terminó en $E"; exit 1; }

paso "esperando /health"
for i in $(seq 1 30); do
    curl -fs --max-time 3 "http://$IP:8000/health" >/dev/null && break
    sleep 5
done
echo "health:   $(curl -fs --max-time 5 "http://$IP:8000/health" || echo 'NO RESPONDE')"
echo "pipeline: $(curl -fs --max-time 5 "http://$IP:8000/admin/pipeline" || echo 'NO RESPONDE')"
echo
echo "API:  http://$IP:8000      (config.yaml -> backend.base_url; lo actualiza 20-correr-harness.sh)"
