#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · 10: levanta TODO lo de una sesión de pruebas, en orden (idempotente)
# =============================================================================
#    01  bucket + stream (1 shard) + Firehose     <- el stream cobra por hora desde acá
#    02  workgroup + ref/ + base + dimensiones
#    03  despliegue de la API en la EC2
#  Al terminar la sesión: bash ~/p3/infra/90-bajar-stream.sh --confirmo
#
#  Uso (CloudShell):  bash ~/p3/infra/10-levantar-sesion.sh
# =============================================================================
set -euo pipefail
D="$(dirname "$0")"
bash "$D/01-bucket-stream-firehose.sh"
bash "$D/02-athena-y-dimensiones.sh"
bash "$D/03-desplegar-app.sh"
echo
echo "LISTO. Siguiente: nohup bash ~/p3/infra/20-correr-harness.sh > ~/p3/harness.log 2>&1 & tail -f --pid=\$! ~/p3/harness.log"
echo "Al terminar:     bash ~/p3/infra/90-bajar-stream.sh --confirmo   (el stream cobra US\$0,015/h)"
