#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 80: "reinicio del entorno de prueba" antes de la defensa (decisión D12)
# =============================================================================
#  Por qué (trampa 1, medida en local: local/reportes/reporte-sim-trampa1-*.md): el replay del
#  profesor usa LOS MISMOS event_id que nuestras corridas de prueba, con otro contenido. Si en la
#  landing quedan las nuestras, deduplicar por event_id mezcla las dos versiones y R7-R10 fallan
#  (en la simulación el bloque de la estrella bajó de 41 a 20 puntos).
#
#  Qué hace: MUEVE todo raw/events/ a archive/<fecha>/ (no borra nada: la evidencia de las
#  pruebas queda) y pide un refresh para que la estrella se reconstruya con la landing vacía.
#  archive/ está FUERA de raw_events_uri: Athena y el harness ya no lo ven.
#
#  Sin --confirmo sólo muestra lo que haría.
#  Uso (CloudShell):  bash ~/p3/infra/80-archivar-landing.sh [--confirmo]
# =============================================================================
set -euo pipefail
source "$(dirname "$0")/00-comun.sh"
DESTINO="s3://$BUCKET/archive/$(date -u '+%Y%m%dT%H%M')/"
N=$(aws s3 ls "$RAW_URI" --recursive | wc -l)
echo "landing $RAW_URI: $N objetos -> $DESTINO"
if [ "${1:-}" != "--confirmo" ]; then
    echo "(simulación: no se movió nada; para hacerlo: bash $0 --confirmo)"
    exit 0
fi
aws s3 mv "$RAW_URI" "$DESTINO" --recursive --only-show-errors
echo "movidos. Quedan en la landing: $(aws s3 ls "$RAW_URI" --recursive | wc -l) objetos"
IP=$(ip_ec2)
if [ -n "$IP" ] && [ "$IP" != "None" ]; then
    curl -fs -X POST "http://$IP:8000/admin/refresh-star"; echo
    for _ in $(seq 1 60); do
        S=$(curl -fs "http://$IP:8000/admin/refresh-status" || echo '{}')
        echo "$S" | grep -q '"RUNNING"' || break
        sleep 5
    done
    echo "refresh: $S"
fi
