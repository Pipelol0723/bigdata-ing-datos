#!/usr/bin/env bash
# =============================================================================
#  Parcial 3 · arma p3.tgz para subir a CloudShell (Acciones -> Cargar archivo)
# =============================================================================
#  Se corre en la LAPTOP (Git Bash). Mete lo que la sesión de AWS necesita: app/, infra/,
#  harness/, ref/, docker-compose.yml y cost_projection.yaml. Sin cachés ni reportes locales.
#  En CloudShell:   rm -rf ~/p3 && mkdir ~/p3 && tar xzf ~/p3.tgz -C ~/p3
#  (⚠️ CloudShell NO reemplaza un archivo subido con el mismo nombre: borrar ~/p3.tgz antes.)
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/.."
SALIDA="${1:-/c/Users/pipel/datos-parcial3/p3.tgz}"
tar czf "$SALIDA" --exclude='__pycache__' --exclude='*.pyc' --exclude='harness/config.yaml' \
    app infra harness ref docker-compose.yml cost_projection.yaml
echo "$SALIDA: $(du -h "$SALIDA" | cut -f1), $(tar tzf "$SALIDA" | wc -l) archivos"
