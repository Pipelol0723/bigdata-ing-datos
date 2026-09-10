"""Job de Glue: RDS OLTP -> raw/ -> processed/

Puebla las dos primeras zonas del data lake. Corre DENTRO de la VPC usando la
conexión JDBC del catálogo, así que alcanza una RDS privada sin abrir ningún
puerto hacia internet.

    RDS OLTP  --JDBC-->  raw/ (CSV, fiel)  -->  processed/ (Parquet, tipado)

Dos decisiones que hacen que las zonas signifiquen algo:

1. `raw/` se escribe en **CSV sin transformar**, particionado por fecha de
   extracción. Es la copia fiel: si mañana la lógica de limpieza tiene un bug,
   se corrige el código y se reprocesa desde acá, sin volver a tocar la base
   transaccional —que para entonces ya cambió—.

2. `processed/` se construye **leyendo `raw/` desde S3**, no consultando la base
   otra vez. Es lo que vuelve real la promesa de la zona cruda: si el ETL sólo
   pudiera regenerarse volviendo a la fuente, `raw/` sería decorativa.

El tipado es la transformación concreta entre ambas: al releer el CSV todo
vuelve como texto, y acá se le devuelve el esquema que traía de PostgreSQL.
Eso es exactamente lo que `processed/` aporta sobre `raw/`.

Ejecutado el 2026-09-08 · run SUCCEEDED en 149 s · Glue 4.0 · G.1X × 2.
La copia desplegada en S3 es este mismo archivo sin los comentarios.

Parámetros:  --BUCKET  --CONEXION
"""
import sys
from datetime import date

from awsglue.context import GlueContext
from awsglue.job import Job
from awsglue.utils import getResolvedOptions
from pyspark.context import SparkContext

ARGS = getResolvedOptions(sys.argv, ["JOB_NAME", "BUCKET", "CONEXION"])
BUCKET = ARGS["BUCKET"]
CONEXION = ARGS["CONEXION"]
ESQUEMA = "reservas"
HOY = date.today().isoformat()

sc = SparkContext()
gc = GlueContext(sc)
spark = gc.spark_session
job = Job(gc)
job.init(ARGS["JOB_NAME"], ARGS)

# Las 17 tablas del OLTP. Se listan explícitamente y no se descubren en tiempo
# de ejecución: si mañana aparece una tabla nueva, quiero que el job la ignore
# hasta que alguien decida conscientemente incorporarla al lago.
TABLAS = [
    "aeronave", "aeropuerto", "agencia", "asiento", "asignacion_asiento",
    "comision", "historial_reserva", "instancia_vuelo", "itinerario", "pago",
    "pasajero", "politica_capacidad", "reserva", "ruta", "tarifa", "tramo",
    "vuelo_programado",
]


def leer_oltp(tabla):
    # useConnectionProperties + connectionName: Glue toma host, usuario y clave
    # de la conexión del catálogo. Ninguna credencial viaja en el script.
    return gc.create_dynamic_frame.from_options(
        connection_type="postgresql",
        connection_options={
            "useConnectionProperties": "true",
            "connectionName": CONEXION,
            "dbtable": ESQUEMA + "." + tabla,
        },
        transformation_ctx="src_" + tabla,
    )


resumen = []

for tabla in TABLAS:
    # --- 1. Extracción fiel a raw/ -------------------------------------------
    origen = leer_oltp(tabla)
    df_origen = origen.toDF()
    esquema_original = df_origen.schema          # se conserva para el tipado
    filas = df_origen.count()

    ruta_raw = "s3://" + BUCKET + "/raw/oltp/" + tabla + "/fecha_extraccion=" + HOY + "/"
    df_origen.coalesce(1).write.mode("overwrite").option("header", "true").csv(ruta_raw)

    # --- 2. raw/ -> processed/, releyendo desde S3 ---------------------------
    # Se relee SÓLO la extracción recién escrita, no toda la carpeta de la
    # tabla. raw/ acumula una partición por corrida (es el historial); si
    # processed/ leyera todas, cada corrida nueva duplicaría las filas.
    # Corregido el 10/09, antes de la segunda ejecución: con una sola
    # extracción el error no se veía.
    # Todo vuelve como string: es el CSV haciendo lo que hace el CSV.
    df_raw = spark.read.option("header", "true").csv(ruta_raw)

    # Se le devuelve el esquema que traía de PostgreSQL. Ésta es la
    # transformación que justifica que processed/ exista.
    df_tipado = df_raw.select(*[
        df_raw[c.name].cast(c.dataType).alias(c.name)
        for c in esquema_original.fields
    ])

    ruta_proc = "s3://" + BUCKET + "/processed/oltp/" + tabla + "/"
    df_tipado.coalesce(1).write.mode("overwrite").option("compression", "snappy").parquet(ruta_proc)

    resumen.append((tabla, filas))
    print("[ok] %-22s %7d filas  -> raw/ y processed/" % (tabla, filas))

print("=" * 62)
print(" %d tablas . %d filas totales" % (len(resumen), sum(f for _, f in resumen)))
print("=" * 62)

job.commit()
