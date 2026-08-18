#!/usr/bin/env bash
# =============================================================================
#  consultar-sakila.sh -- correr consultas contra la RDS sin repetir el host
# =============================================================================
#  INSTALACION (en Cloud9, una sola vez):
#      nano ~/consultar.sh     <- pegar este contenido
#      chmod +x ~/consultar.sh
#
#  USO:
#      ./consultar.sh "SELECT * FROM film LIMIT 5;"
#      ./consultar.sh --archivo mis_consultas.sql
#      ./consultar.sh                      <- sin argumentos: abre el cliente
# =============================================================================

HOST=db-service.cvbllouimnrr.us-east-1.rds.amazonaws.com
USUARIO=pipe
BASE=sakila

# --table fuerza el formato de cajitas aunque la salida se redirija a un archivo
MYSQL="mysql -h $HOST -u $USUARIO -p $BASE --table"

if [ -z "$1" ]; then
    # sin argumentos: sesion interactiva
    $MYSQL
elif [ "$1" = "--archivo" ]; then
    if [ ! -f "$2" ]; then echo "No existe el archivo: $2"; exit 1; fi
    $MYSQL < "$2"
else
    $MYSQL -e "$1"
fi
