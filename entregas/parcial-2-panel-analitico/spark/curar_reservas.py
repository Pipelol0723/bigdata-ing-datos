"""
Parcial 2 · job de EMR: limpia el historial crudo (C1–C5) y escribe las dos tablas del contrato.

    spark-submit curar_reservas.py --raw s3://<bucket>/raw/ --out s3://<bucket>/curated/

Lee   <raw>/flights.csv y <raw>/reservations.csv (los genera airline_data.generate).
Escribe
  <out>/reservations_curated/month=YYYY-MM/   Parquet, una partición por mes del vuelo
  <out>/route_month_metrics/                  Parquet sin particionar (240 filas con la semilla 12345)
  <out>/_resumen/                             cuántas filas sacó cada regla, en JSON

route_month_metrics NO se particiona a propósito: si `month` fuera columna de partición, Glue la
saca de la lista de columnas y el orden del contrato (R5) deja de coincidir.
"""

import argparse
import json
from datetime import datetime, timezone

from pyspark.sql import SparkSession, Window
from pyspark.sql import functions as F

ESQUEMA_VUELOS = "flight_id long, route string, flight_date string, capacity long"
ESQUEMA_RESERVAS = ("reservation_id long, flight_id long, fare_class string, price_cents long, "
                    "status string, days_before_departure int")
ESTADOS_VALIDOS = ["CONFIRMED", "CANCELLED"]


# ---- Reglas de limpieza: una función por regla, para poder cambiar una sin tocar las demás --------

def c1_normalizar_ruta(vuelos):
    """C1 · route sin ningún espacio y en mayúsculas: ' bog - mde ' -> 'BOG-MDE'."""
    return vuelos.withColumn("route", F.upper(F.regexp_replace("route", r"\s+", "")))


def c2_normalizar_estado(reservas):
    """C2 · status sin espacios en los extremos y en mayúsculas. Se usa una regex y no trim():
    trim() de Spark sólo quita espacios, y la regla dice 'whitespace' (como str.strip de Python)."""
    return reservas.withColumn("status", F.upper(F.regexp_replace("status", r"^\s+|\s+$", "")))


def c3_estados_validos(reservas):
    """C3 · sólo CONFIRMED o CANCELLED (descarta PENDING y cualquier otro)."""
    return reservas.filter(F.col("status").isin(ESTADOS_VALIDOS))


def c4_precio_valido(reservas):
    """C4 · price_cents presente y mayor que 0."""
    return reservas.filter(F.col("price_cents").isNotNull() & (F.col("price_cents") > 0))


def c5_sin_duplicados(reservas):
    """C5 · un reservation_id una sola vez, quedándose con la PRIMERA aparición en el archivo.
    dropDuplicates() no garantiza cuál conserva; por eso se numera cada fila al leer (_orden)
    y se elige la menor."""
    primero = Window.partitionBy("reservation_id").orderBy("_orden")
    return (reservas.withColumn("_n", F.row_number().over(primero))
                    .filter(F.col("_n") == 1)
                    .drop("_n"))


# ---- Tablas del contrato -------------------------------------------------------------------------

def tabla_detalle(reservas, vuelos):
    """reservations_curated: la ruta y el mes salen del vuelo (reservations.csv no trae ruta)."""
    v = vuelos.select("flight_id", "route", F.substring("flight_date", 1, 7).alias("month"))
    return (reservas.join(v, on="flight_id", how="inner")
                    .select(F.col("reservation_id").cast("string").alias("reservation_id"),
                            F.col("flight_id").cast("string").alias("flight_id"),
                            "route", "fare_class", "price_cents", "status", "month"))


def tabla_metricas(detalle, vuelos, bookings_incluye_canceladas=False):
    """route_month_metrics. La capacidad sale de los VUELOS (todos los del mes, tengan o no
    reservas); lo vendido, de las reservas CONFIRMED. Las canceladas no ocupan asiento."""
    capacidad = (vuelos.groupBy("route", F.substring("flight_date", 1, 7).alias("month"))
                       .agg(F.sum("capacity").alias("seats_capacity")))
    confirmada = F.col("status") == "CONFIRMED"
    reservas = (detalle.groupBy("route", "month")
                       .agg(F.sum(confirmada.cast("long")).alias("seats_sold"),
                            F.sum(F.when(confirmada, F.col("price_cents"))).alias("revenue_cents"),
                            F.count("*").alias("todas"),
                            F.sum((F.col("status") == "CANCELLED").cast("long")).alias("cancellations")))
    # El contrato dice que bookings cuenta sólo las CONFIRMED; el oráculo del harness cuenta todas.
    # El harness no la verifica: queda como parámetro hasta que el profesor confirme.
    bookings = F.col("todas") if bookings_incluye_canceladas else F.col("seats_sold")
    m = capacidad.join(reservas, on=["route", "month"], how="left").fillna(0)
    return m.select("route", "month",
                    F.col("seats_capacity").cast("long"),
                    F.col("seats_sold").cast("long"),
                    (F.col("seats_sold") / F.col("seats_capacity")).cast("double").alias("occupancy"),
                    F.col("revenue_cents").cast("long"),
                    bookings.cast("long").alias("bookings"),
                    F.col("cancellations").cast("long"))


def procesar(spark, raw, bookings_incluye_canceladas=False):
    """Lee los crudos, aplica C1–C5 y arma las dos tablas. No escribe nada: así la misma función
    se prueba en la laptop contra el oráculo y corre en EMR."""
    raw = raw.rstrip("/")
    vuelos_crudos = spark.read.csv(f"{raw}/flights.csv", header=True, schema=ESQUEMA_VUELOS)
    # _orden numera las filas en el orden del archivo (crece con la partición y la posición)
    reservas_crudas = (spark.read.csv(f"{raw}/reservations.csv", header=True, schema=ESQUEMA_RESERVAS)
                            .withColumn("_orden", F.monotonically_increasing_id()))

    vuelos = c1_normalizar_ruta(vuelos_crudos).cache()
    filas = {"crudas": reservas_crudas.count()}
    r = c2_normalizar_estado(reservas_crudas)
    r = c3_estados_validos(r)
    filas["tras_C3"] = r.count()
    r = c4_precio_valido(r)
    filas["tras_C4"] = r.count()
    r = c5_sin_duplicados(r).drop("_orden")

    detalle = tabla_detalle(r, vuelos).cache()
    filas["curadas"] = detalle.count()
    metricas = tabla_metricas(detalle, vuelos, bookings_incluye_canceladas).cache()
    resumen = {"vuelos": vuelos.count(), "filas": filas,
               "meses": detalle.select("month").distinct().count(), "filas_metricas": metricas.count(),
               "bookings": "confirmadas+canceladas" if bookings_incluye_canceladas else "confirmadas"}
    return detalle, metricas, resumen


def escribir(spark, detalle, metricas, resumen, out):
    out = out.rstrip("/")
    # Una partición = un archivo: 24 archivos de ~1 MB, que Athena poda por mes (R6)
    (detalle.repartition("month")
            .write.mode("overwrite").partitionBy("month")
            .parquet(f"{out}/reservations_curated"))
    metricas.coalesce(1).write.mode("overwrite").parquet(f"{out}/route_month_metrics")
    spark.createDataFrame([(json.dumps(resumen),)], "json string").coalesce(1) \
         .write.mode("overwrite").text(f"{out}/_resumen")


def main():
    ap = argparse.ArgumentParser(description="Parcial 2: limpieza C1-C5 y tablas del contrato")
    ap.add_argument("--raw", required=True, help="carpeta con flights.csv y reservations.csv")
    ap.add_argument("--out", required=True, help="carpeta donde se escriben las dos tablas")
    ap.add_argument("--bookings-incluye-canceladas", action="store_true",
                    help="bookings = confirmadas + canceladas (como el oráculo) en vez de sólo confirmadas")
    args = ap.parse_args()

    spark = SparkSession.builder.appName("parcial2-curar-reservas").getOrCreate()
    inicio = datetime.now(timezone.utc)
    detalle, metricas, resumen = procesar(spark, args.raw, args.bookings_incluye_canceladas)
    resumen = {"inicio": inicio.isoformat(), **resumen, "fin": datetime.now(timezone.utc).isoformat()}
    escribir(spark, detalle, metricas, resumen, args.out)
    print(json.dumps(resumen, ensure_ascii=False), flush=True)
    spark.stop()


if __name__ == "__main__":
    main()
