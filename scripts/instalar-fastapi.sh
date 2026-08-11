#!/usr/bin/env bash
# =============================================================================
#  instalar-fastapi.sh -- FastAPI en la EC2 Ubuntu, servido por el puerto 80
# =============================================================================
#  COMO SE USA (desde tu Windows, con la instancia viva):
#      scp scripts/instalar-fastapi.sh ec2-bigdata:/tmp/
#      ssh ec2-bigdata "bash /tmp/instalar-fastapi.sh"
#
#  QUE HACE
#    1. Instala python3-venv y crea un entorno virtual en ~/api/.venv
#    2. Instala fastapi + uvicorn ahi adentro
#    3. Deja una app de ejemplo en ~/api/main.py
#    4. La registra como servicio systemd (sobrevive a cerrar el SSH)
#    5. Configura Apache como reverse proxy: la API queda en /api
#
#  POR QUE UN VENV Y NO 'pip install' A SECAS
#    Ubuntu 24.04+ implementa PEP 668: el Python del sistema esta marcado como
#    "externally managed" y pip se niega a instalar ahi. Si lo intentas ves:
#        error: externally-managed-environment
#    Existe --break-system-packages, pero el nombre no es casualidad: podes
#    romper herramientas del sistema que dependen de ese Python. El venv es
#    la respuesta correcta, no un rodeo.
#
#  POR QUE REVERSE PROXY Y NO ABRIR EL PUERTO 8000
#    El security group ya tiene el 80 abierto. Con Apache haciendo de proxy,
#    uvicorn escucha en 127.0.0.1 (inalcanzable desde internet) y Apache le
#    pasa el trafico. Resultado: no hay que tocar el security group y no se
#    expone un puerto mas. Es ademas como se hace en produccion.
#    Si preferis el camino directo, esta explicado al final del script.
# =============================================================================

set -e

APP_DIR="$HOME/api"

echo "=============================================="
echo " 1/5  Paquetes del sistema"
echo "=============================================="
sudo apt-get update -qq
sudo apt-get install -y -qq python3-venv python3-pip

echo ""
echo "=============================================="
echo " 2/5  Entorno virtual en $APP_DIR/.venv"
echo "=============================================="
mkdir -p "$APP_DIR"
python3 -m venv "$APP_DIR/.venv"
"$APP_DIR/.venv/bin/pip" install --quiet --upgrade pip
"$APP_DIR/.venv/bin/pip" install --quiet "fastapi[standard]" uvicorn
echo "Instalado:"
"$APP_DIR/.venv/bin/pip" list --format=freeze | grep -Ei '^(fastapi|uvicorn|pydantic|starlette)='

echo ""
echo "=============================================="
echo " 3/5  App de ejemplo"
echo "=============================================="
if [ -f "$APP_DIR/main.py" ]; then
    echo "Ya existe $APP_DIR/main.py -- no lo piso."
else
    cat > "$APP_DIR/main.py" <<'PYEOF'
from fastapi import FastAPI

# root_path="/api" le avisa a FastAPI que Apache lo publica bajo ese prefijo,
# para que la documentacion automatica genere las URLs correctas.
app = FastAPI(title="API de la clase", root_path="/api")


@app.get("/")
def raiz():
    return {"mensaje": "FastAPI andando en la EC2"}


@app.get("/saludo/{nombre}")
def saludo(nombre: str):
    return {"saludo": f"hola {nombre}"}
PYEOF
    echo "Creado $APP_DIR/main.py"
fi

echo ""
echo "=============================================="
echo " 4/5  Servicio systemd"
echo "=============================================="
# Sin esto, uvicorn muere al cerrar la sesion SSH: systemd lo mantiene vivo
# y lo levanta solo si la instancia se reinicia.
sudo tee /etc/systemd/system/fastapi.service > /dev/null <<EOF
[Unit]
Description=FastAPI (uvicorn)
After=network.target

[Service]
User=$USER
WorkingDirectory=$APP_DIR
ExecStart=$APP_DIR/.venv/bin/uvicorn main:app --host 127.0.0.1 --port 8000
Restart=always

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now fastapi
sleep 2
sudo systemctl is-active fastapi && echo "servicio activo"

echo ""
echo "=============================================="
echo " 5/5  Apache como reverse proxy"
echo "=============================================="
sudo a2enmod proxy proxy_http > /dev/null 2>&1 || true
sudo tee /etc/apache2/conf-available/fastapi.conf > /dev/null <<'EOF'
# La barra final en ambos lados importa: mapea /api/foo -> /foo en el backend.
ProxyPreserveHost On
ProxyPass        /api/ http://127.0.0.1:8000/
ProxyPassReverse /api/ http://127.0.0.1:8000/
EOF
sudo a2enconf fastapi > /dev/null 2>&1 || true
sudo systemctl reload apache2

echo ""
echo "=============================================="
echo " Verificacion local"
echo "=============================================="
curl -s http://127.0.0.1/api/ ; echo
curl -s http://127.0.0.1/api/saludo/pipe ; echo

IP=$(curl -s -m 5 https://checkip.amazonaws.com || echo "<IP-PUBLICA>")
cat <<EOF

==============================================================
 LISTO. Desde tu navegador:

   http://$IP/api/          -> la API
   http://$IP/api/docs      -> documentacion interactiva (Swagger)
   http://$IP/              -> tu pagina de Apache, intacta

 Comandos utiles:
   sudo systemctl status fastapi     # como esta
   sudo systemctl restart fastapi    # despues de editar main.py
   sudo journalctl -u fastapi -f     # ver los logs en vivo

 ALTERNATIVA sin proxy (mas simple, pero expone un puerto mas):
   1. Abrir el 8000 en el security group:
      aws ec2 authorize-security-group-ingress --group-id sg-06269c038daa2d634 \\
          --protocol tcp --port 8000 --cidr <TU_IP>/32
   2. Cambiar --host 127.0.0.1 por --host 0.0.0.0 en el servicio.
   3. Acceder a http://$IP:8000/
==============================================================
EOF
