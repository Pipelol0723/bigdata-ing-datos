"""Configuración de la API.

Todo por variables de entorno: la misma imagen corre contra el PostgreSQL
local en Docker y contra la RDS de AWS sin tocar una línea de código.

⚠️ Las credenciales NUNCA se escriben acá (NFR-SEG-01). El valor por defecto
   apunta al contenedor local de desarrollo, que sólo escucha en 127.0.0.1.
"""
import os

# --- conexión ---------------------------------------------------------------
DSN_OLTP = os.environ.get(
    "DSN_OLTP",
    "postgresql://parcial:parcial_local_dev@127.0.0.1:15432/aerolinea",
)

# --- políticas de negocio (parametrizables, no constantes) -------------------
# DEC-02 / NFR-CONC-02: cuánto dura una retención antes de liberarse sola.
MINUTOS_RETENCION_PASAJERO = int(os.environ.get("MINUTOS_RETENCION", "30"))

# DEC-03: cuántas veces se reintenta ante colisión optimista antes de rendirse.
MAX_REINTENTOS = int(os.environ.get("MAX_REINTENTOS", "3"))

# --- modo de demostración ---------------------------------------------------
# Con MODO_INSEGURO=1 la reserva usa el patrón ingenuo leer→decidir→escribir,
# que es exactamente lo que DEC-03 evita. Existe SÓLO para producir la
# evidencia comparativa que pide la sección 5.6 del enunciado.
MODO_INSEGURO = os.environ.get("MODO_INSEGURO", "0") == "1"

# Retardo artificial en el modo inseguro: ensancha la ventana de la condición
# de carrera para que sea observable con pocas peticiones. Sin esto habría que
# lanzar miles para que la colisión se manifieste.
RETARDO_INSEGURO_SEG = float(os.environ.get("RETARDO_INSEGURO", "0.05"))
