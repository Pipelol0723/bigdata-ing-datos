#!/usr/bin/env bash
# =============================================================================
#  05-correr-harness.sh — corre el harness del profesor desde CloudShell
# =============================================================================
#  Por qué desde CloudShell: ya tiene las credenciales del lab (no hay que copiar
#  nada a la laptop) y la latencia de R1 se mide desde adentro de AWS.
#
#  Qué hace:
#    1. Busca la IP actual de la EC2 parcial2-app (cambia en cada sesión del lab)
#       y la escribe en harness/config.yaml.
#    2. Arma en /tmp lo que CloudShell borra entre sesiones: el venv con las
#       dependencias, el Chromium de Playwright y las bibliotecas que le faltan.
#       Va en /tmp porque el home de CloudShell tiene 1 GB y no alcanza.
#    3. Corre pytest: deja report.md y report.json en la carpeta del harness.
#
#  No crea ni borra recursos de AWS. Lo que sí hace el harness: consultas de
#  Athena (centavos de centavo) y vuelos y reservas de prueba en la app.
#
#  Uso (CloudShell, con harness/ y cost_projection.yaml en ~/p2h):
#    nohup bash ~/p2h/05-correr-harness.sh > ~/p2h/harness.log 2>&1 & tail -f --pid=$! ~/p2h/harness.log
#  (nohup: sigue aunque CloudShell se desconecte; --pid: el tail se cierra cuando termina)
#  Sólo una parte:  bash ~/p2h/05-correr-harness.sh tests/test_backend.py
# =============================================================================
set -euo pipefail
export AWS_PAGER=""
DIR="${HARNESS_DIR:-$HOME/p2h}"
cd "$DIR/harness"

IP=$(aws ec2 describe-instances --region us-east-1 \
    --filters Name=tag:Name,Values=parcial2-app Name=instance-state-name,Values=running \
    --query "Reservations[].Instances[].PublicIpAddress" --output text)
[ -n "$IP" ] && [ "$IP" != "None" ] || { echo "!! la EC2 parcial2-app no está running"; exit 1; }
sed -i -E "s#http://[0-9.]+:8000#http://$IP:8000#g" config.yaml
echo "== EC2 en $IP: $(curl -fs --max-time 5 "http://$IP:8000/health" || echo 'NO RESPONDE')"

if [ ! -x /tmp/gen/bin/python ]; then
    echo "== venv en /tmp/gen (~1 min)"
    python3 -m venv /tmp/gen
    /tmp/gen/bin/pip install -q -r requirements.txt
fi
export PLAYWRIGHT_BROWSERS_PATH=/tmp/pw
if [ ! -d /tmp/pw ]; then
    echo "== Chromium de Playwright y sus bibliotecas (~1 min)"
    /tmp/gen/bin/python -m playwright install chromium-headless-shell
    sudo dnf install -y -q nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon libXcomposite \
        libXdamage libXrandr libXfixes mesa-libgbm pango alsa-lib
fi

echo "== pytest $*"
/tmp/gen/bin/python -m pytest "$@"
