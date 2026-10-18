"""
Corre el job de EMR en la laptop (Spark local) y deja las dos tablas en Parquet para validarlas
contra el oráculo, sin gastar nada en AWS.

    python probar_job_local.py <carpeta_raw> <carpeta_salida>

Usa procesar() de spark/curar_reservas.py tal cual: las reglas C1–C5, el join y las métricas son el
mismo código que corre en EMR. Lo único distinto es la escritura: Spark en Windows necesita
winutils.exe (un binario de Hadoop que no viene en ningún instalador oficial), así que acá las
tablas se pasan a pandas y se escriben con pyarrow, con el mismo particionado (month=YYYY-MM).
La escritura de Spark se prueba en EMR, que es Linux.

Antes de correrlo en Windows:  SPARK_LOCAL_HOSTNAME=localhost  (el hostname de esta laptop tiene
un guion bajo y Spark lo rechaza en sus URLs internas).
"""
import json
import shutil
import sys
import time
from pathlib import Path

import pyarrow as pa
import pyarrow.parquet as pq
from pyspark.sql import SparkSession

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "spark"))
from curar_reservas import procesar  # noqa: E402

raw, salida = Path(sys.argv[1]), Path(sys.argv[2])
spark = (SparkSession.builder.master("local[*]").appName("parcial2-local")
         .config("spark.driver.memory", "4g")
         .config("spark.sql.shuffle.partitions", "8")
         .config("spark.sql.execution.arrow.pyspark.enabled", "true")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

t0 = time.time()
detalle, metricas, resumen = procesar(spark, raw.resolve().as_uri())
det, met = detalle.toPandas(), metricas.toPandas()
spark.stop()
print(json.dumps(resumen, ensure_ascii=False))
print(f"Spark local: {time.time() - t0:.1f} s")

shutil.rmtree(salida, ignore_errors=True)
esquema_det = pa.schema([("reservation_id", pa.string()), ("flight_id", pa.string()), ("route", pa.string()),
                         ("fare_class", pa.string()), ("price_cents", pa.int64()), ("status", pa.string()),
                         ("month", pa.string())])
pq.write_to_dataset(pa.Table.from_pandas(det, schema=esquema_det, preserve_index=False),
                    root_path=salida / "reservations_curated", partition_cols=["month"])
(salida / "route_month_metrics").mkdir(parents=True)
pq.write_table(pa.Table.from_pandas(met, preserve_index=False), salida / "route_month_metrics" / "part-0.parquet")
print(f"escrito en {salida}")
