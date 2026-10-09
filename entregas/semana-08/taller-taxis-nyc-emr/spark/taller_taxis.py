"""
Taller Taxis NYC: el notebook convertido en un programa que corre en el clúster (paso 14).

    spark-submit --deploy-mode client taller_taxis.py --bucket taxis-nyc-<cuenta> --tope-min <minutos>

Hace los pasos 2 a 12 sobre s3://<bucket>/taxis/: imprime cada respuesta (queda en la salida del
step de EMR), escribe el Parquet particionado en s3://<bucket>/viajes/ y deja un resumen en
s3://<bucket>/resultados/, que está disponible apenas termina (el log del step tarda unos minutos).

Qué cambia respecto del notebook, y nada más:
  - la sesión de Spark se crea acá (en el notebook la da el kernel);
  - el bucket y el tope de duración llegan como argumentos, no escritos en el código;
  - al final se guarda el resumen en S3.
"""

import argparse
import json
from datetime import datetime, timezone

from pyspark import StorageLevel
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

# Sólo las 4 columnas que usa el taller, con el tipo que tienen en los 12 meses.
# Leer la carpeta con su esquema completo puede fallar: passenger_count y RatecodeID
# pasan de INT64 a DOUBLE en julio.
ESQUEMA_VIAJES = ("tpep_pickup_datetime timestamp, tpep_dropoff_datetime timestamp, "
                  "PULocationID long, DOLocationID long")
ESQUEMA_ZONAS = "LocationID int, Borough string, Zone string, service_zone string"
SIN_ZONA = [264, 265]  # 264 = Unknown · 265 = Outside of NYC: ninguna es un lugar


def titulo(texto):
    print(f"\n{'=' * 78}\n {texto}\n{'=' * 78}", flush=True)


def filas(df, n):
    """Las primeras n filas como diccionarios, para el resumen en JSON."""
    return [r.asDict() for r in df.limit(n).collect()]


def main():
    ap = argparse.ArgumentParser(description="Taller Taxis NYC, pasos 2 a 12")
    ap.add_argument("--bucket", required=True, help="bucket con taxis/viajes/ y taxis/zonas/")
    ap.add_argument("--tope-min", type=float, required=True,
                    help="duración máxima válida, en minutos (elegida con los percentiles)")
    args = ap.parse_args()
    base = f"s3://{args.bucket}"
    tope = args.tope_min

    spark = (SparkSession.builder
             .appName("taller-taxis-nyc")
             # Fechas del TLC: hora local sin zona. En UTC se usan tal como están escritas.
             .config("spark.sql.session.timeZone", "UTC")
             .getOrCreate())
    resumen = {"bucket": args.bucket, "tope_min": tope, "inicio": datetime.now(timezone.utc).isoformat()}

    # ---- 2 · Dos DataFrames ----------------------------------------------------------------
    titulo("Paso 2 · Viajes y zonas")
    viajes = spark.read.schema(ESQUEMA_VIAJES).parquet(f"{base}/taxis/viajes/")
    zonas = spark.read.csv(f"{base}/taxis/zonas/", header=True, schema=ESQUEMA_ZONAS)
    resumen["filas_viajes"] = viajes.count()   # control: 102.871.387
    resumen["filas_zonas"] = zonas.count()     # control: 265
    print(f"viajes: {resumen['filas_viajes']:,} · zonas: {resumen['filas_zonas']:,}")

    # ---- 3 · Lugar de recogida (alias PU_ZONE), horas y DOLocationID ------------------------
    # Zonas tiene 265 filas: broadcast la copia a cada nodo y los viajes no se mueven por la red.
    titulo("Paso 3 · PU_ZONE, hora_recogida, hora_dejada, DOLocationID")
    zonas_pu = zonas.select(F.col("LocationID").alias("PULocationID"),
                            F.col("Zone").alias("PU_ZONE"))
    paso3 = (viajes.join(F.broadcast(zonas_pu), on="PULocationID")
                   .select("PULocationID", "PU_ZONE",
                           F.col("tpep_pickup_datetime").alias("hora_recogida"),
                           F.col("tpep_dropoff_datetime").alias("hora_dejada"),
                           "DOLocationID"))
    paso3.select("PU_ZONE", "hora_recogida", "hora_dejada", "DOLocationID").show(10, truncate=False)

    # ---- 4 · Segundo cruce: la zona de destino ---------------------------------------------
    # Los IDs se conservan para agrupar en 7 y 8: hay nombres repetidos ("Corona" es la 56 y la 57).
    titulo("Paso 4 · PU_ZONE, DO_ZONE, PU_datetime, DO_datetime")
    zonas_do = zonas.select(F.col("LocationID").alias("DOLocationID"),
                            F.col("Zone").alias("DO_ZONE"))
    paso4 = (paso3.join(F.broadcast(zonas_do), on="DOLocationID")
                  .select("PULocationID", "DOLocationID", "PU_ZONE", "DO_ZONE",
                          F.col("hora_recogida").alias("PU_datetime"),
                          F.col("hora_dejada").alias("DO_datetime")))
    paso4.select("PU_ZONE", "DO_ZONE", "PU_datetime", "DO_datetime").show(10, truncate=False)

    # ---- 5 · trip_duration en minutos -------------------------------------------------------
    titulo("Paso 5 · trip_duration (minutos)")
    viajes_dur = paso4.withColumn(
        "trip_duration",
        (F.unix_timestamp("DO_datetime") - F.unix_timestamp("PU_datetime")) / 60)
    # Todo lo que sigue sale de acá: se guarda en memoria (y en disco lo que no entre) para no
    # releer S3 y repetir los dos joins en cada consulta.
    viajes_dur.persist(StorageLevel.MEMORY_AND_DISK)
    resumen["filas_tras_los_joins"] = viajes_dur.count()   # control: igual a filas_viajes
    print(f"después de los dos joins: {resumen['filas_tras_los_joins']:,}")
    viajes_dur.select("PU_ZONE", "DO_ZONE", "PU_datetime", "DO_datetime",
                      F.round("trip_duration", 2).alias("trip_duration")).show(10, truncate=False)

    # ---- Calidad: qué se considera erróneo ---------------------------------------------------
    titulo(f"Calidad · válido = recogida en 2018 y duración entre 0 y {tope:g} min")
    es_2018 = F.year("PU_datetime") == 2018
    dur = F.col("trip_duration")
    valido = es_2018 & (dur > 0) & (dur <= tope)
    calidad = viajes_dur.select(
        F.count("*").alias("total"),
        F.sum((~es_2018).cast("int")).alias("fuera_de_2018"),
        F.sum((es_2018 & (dur <= 0)).cast("int")).alias("duracion_no_positiva"),
        F.sum((es_2018 & (dur > tope)).cast("int")).alias("sobre_el_tope"),
        F.sum(valido.cast("int")).alias("validos"))
    calidad.show(truncate=False)
    resumen["calidad"] = filas(calidad, 1)[0]
    percentiles = viajes_dur.filter(es_2018 & (dur > 0)).approxQuantile(
        "trip_duration", [0.5, 0.9, 0.99, 0.999, 0.9999], 0.0001)
    resumen["percentiles_min"] = dict(zip(["p50", "p90", "p99", "p99.9", "p99.99"],
                                          [round(p, 1) for p in percentiles]))
    print("percentiles de duración (min):", resumen["percentiles_min"])

    # ---- 6 · El viaje que más duró ----------------------------------------------------------
    titulo("Paso 6 · El viaje que más duró: tal como viene, y entre los válidos")
    columnas = ["PU_ZONE", "DO_ZONE", "PU_datetime", "DO_datetime",
                F.round("trip_duration", 1).alias("trip_duration"),
                F.round(F.col("trip_duration") / 60 / 24, 1).alias("dias")]
    largo_crudo = viajes_dur.orderBy(F.desc("trip_duration")).select(*columnas)
    largo_valido = viajes_dur.filter(valido).orderBy(F.desc("trip_duration")).select(*columnas)
    largo_crudo.show(1, truncate=False)
    largo_valido.show(1, truncate=False)
    resumen["mas_largo_crudo"] = filas(largo_crudo, 1)[0]
    resumen["mas_largo_valido"] = filas(largo_valido, 1)[0]

    # ---- 7 · Destino más frecuente ----------------------------------------------------------
    titulo("Paso 7 · Destino más frecuente (válidos, sin las zonas 264 y 265)")
    destinos = (viajes_dur
                .filter(valido & ~F.col("DOLocationID").isin(SIN_ZONA))
                .groupBy("DOLocationID", "DO_ZONE")
                .count()
                .orderBy(F.desc("count")))
    destinos.show(5, truncate=False)
    resumen["destinos_top5"] = filas(destinos, 5)

    # ---- 8 · Par origen-destino más frecuente -----------------------------------------------
    titulo("Paso 8 · Viaje más frecuente: promedio y desviación estándar (muestral)")
    pares = (viajes_dur
             .filter(valido
                     & ~F.col("PULocationID").isin(SIN_ZONA)
                     & ~F.col("DOLocationID").isin(SIN_ZONA))
             .groupBy("PULocationID", "PU_ZONE", "DOLocationID", "DO_ZONE")
             .agg(F.count("*").alias("viajes"),
                  F.round(F.avg("trip_duration"), 2).alias("promedio_min"),
                  F.round(F.stddev("trip_duration"), 2).alias("desviacion_estandar_min"))
             .orderBy(F.desc("viajes")))
    pares.show(5, truncate=False)
    resumen["pares_top5"] = filas(pares, 5)

    # ---- 9 y 10 · Año y mes, enteros --------------------------------------------------------
    titulo("Pasos 9 y 10 · year y month (enteros)")
    viajes_ym = (viajes_dur
                 .withColumn("year", F.year("PU_datetime").cast("int"))
                 .withColumn("month", F.month("PU_datetime").cast("int")))
    viajes_ym.printSchema()

    # ---- 11 · Meses por cantidad de viajes --------------------------------------------------
    titulo("Paso 11 · Meses de 2018, de más a menos viajes")
    del_2018 = viajes_ym.filter(F.col("year") == 2018)
    meses = del_2018.groupBy("month").count().orderBy(F.desc("count"))
    meses.show(12)
    resumen["meses"] = filas(meses, 12)

    # ---- 12 · Parquet particionado por año y mes --------------------------------------------
    titulo(f"Paso 12 · Guardado en {base}/viajes/ (sólo 2018, todas las duraciones)")
    (del_2018
     .select("PU_ZONE", "DO_ZONE", "PU_datetime", "DO_datetime", "trip_duration", "year", "month")
     .repartition("year", "month")   # un archivo por mes: buen tamaño para Athena
     .write.mode("overwrite")
     .partitionBy("year", "month")
     .parquet(f"{base}/viajes/"))
    resumen["filas_guardadas"] = spark.read.parquet(f"{base}/viajes/").count()
    print(f"filas guardadas: {resumen['filas_guardadas']:,}")

    # ---- Resumen en S3: disponible apenas termina, antes que el log del step ---------------
    resumen["fin"] = datetime.now(timezone.utc).isoformat()
    texto = json.dumps(resumen, ensure_ascii=False, indent=2, default=str)
    destino = f"{base}/resultados/corrida-{datetime.now(timezone.utc):%Y%m%d-%H%M%S}"
    spark.sparkContext.parallelize([texto], 1).saveAsTextFile(destino)
    titulo(f"Resumen guardado en {destino}/part-00000")
    print(texto)

    spark.stop()


if __name__ == "__main__":
    main()
