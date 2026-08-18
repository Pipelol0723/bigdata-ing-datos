#!/usr/bin/env bash
# =============================================================================
#  instalar-mysql-server.sh -- MySQL Server local en la EC2 / Cloud9 (Ubuntu)
# =============================================================================
#  USO (pegar en la terminal de Cloud9):
#      bash instalar-mysql-server.sh
#
#  QUE ES ESTO Y EN QUE SE DIFERENCIA DE RDS
#    Aca MySQL corre DENTRO de tu instancia: vos sos el administrador.
#    Eso significa que tenes privilegio SUPER -- el que RDS nunca da.
#    Consecuencia practica: aca SI se pueden crear las funciones y
#    triggers de Sakila que en la RDS fallaron con el ERROR 1419.
#
#    A cambio, todo lo que RDS hacia por vos pasa a ser tu problema:
#    backups, parches de seguridad, y si la instancia muere, la base
#    muere con ella. Ese es el trade-off, y es el punto del ejercicio.
# =============================================================================

set -e

echo "=============================================="
echo " 1/4  Instalando MySQL Server"
echo "=============================================="
sudo apt-get update -qq
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq mysql-server

echo ""
echo "=============================================="
echo " 2/4  Arrancando el servicio"
echo "=============================================="
sudo systemctl enable --now mysql
sudo systemctl is-active mysql && echo "servicio activo"

echo ""
echo "=============================================="
echo " 3/4  Version y estado"
echo "=============================================="
mysql --version
sudo mysql -e "SELECT VERSION() AS version, @@hostname AS servidor;"

echo ""
echo "=============================================="
echo " 4/4  Comprobacion de privilegios"
echo "=============================================="
# En RDS esto devuelve 0 filas. Aca, root local tiene SUPER.
sudo mysql -e "SHOW GRANTS FOR CURRENT_USER();"

cat <<'FIN'

==============================================================
 LISTO. MySQL Server corriendo en esta instancia.

 COMO ENTRAR
   sudo mysql
 En Ubuntu el root de MySQL usa auth_socket: entra sin password
 siempre que uses sudo. No hace falta configurar nada mas.

 CREAR UN USUARIO NORMAL (opcional, elegi vos la password)
   sudo mysql -e "CREATE USER 'pipe'@'localhost' IDENTIFIED BY 'TU_PASSWORD';"
   sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO 'pipe'@'localhost' WITH GRANT OPTION;"
   sudo mysql -e "FLUSH PRIVILEGES;"

 CARGAR SAKILA ACA (y ver la diferencia con RDS)
   wget -q https://downloads.mysql.com/docs/sakila-db.zip
   unzip -o -q sakila-db.zip
   sudo mysql < sakila-db/sakila-schema.sql
   sudo mysql < sakila-db/sakila-data.sql

 >> Fijate que NO aparece el ERROR 1419. Comprobalo:
   sudo mysql -e "SHOW FUNCTION STATUS WHERE Db='sakila';"
   sudo mysql -e "SHOW TRIGGERS FROM sakila;"
 En la RDS esas dos consultas vuelven vacias. Aca traen
 3 funciones y 6 triggers. Esa es la diferencia entre ser
 administrador de tu base y alquilar una gestionada.

 COMANDOS UTILES
   sudo systemctl status mysql
   sudo systemctl stop mysql      # liberar RAM si hace falta
   sudo journalctl -u mysql -n 30
==============================================================
FIN
