"""Exporta el modelo estrella del OLAP a la zona curated/ del data lake.

    RDS OLAP (dw.*)  -->  ~/curated/<tabla>/...parquet  -->  s3://<bucket>/curated/

Particionado según el ADR #1:
    · hechos por FECHA DE VUELO, granularidad MENSUAL  (year=AAAA/month=MM)
    · dimensiones sin particionar (141 filas en total, se leen enteras)

Se ejecutó por primera vez el 08/09 desde CloudShell. Desde que existe la EC2
de la aplicación corre ahí, porque las RDS son privadas y sólo se alcanzan
desde dentro de la VPC.

Uso (en la EC2, con el entorno cargado):
    python etl/exportar_curated.py
    aws s3 cp ~/curated s3://$BUCKET/curated/ --recursive
"""
import os
import pathlib
from decimal import Decimal

import pandas as pd
import psycopg

BASE = pathlib.Path.home() / "curated"
DIMS = ["dim_fecha", "dim_ruta", "dim_tarifa", "dim_canal", "dim_estado_reserva", "dim_vuelo"]
# (tabla, columna con la fecha AAAAMMDD por la que se particiona)
FACTS = [("fact_tramo_vendido", "id_fecha_vuelo"), ("fact_ocupacion_vuelo", "id_fecha")]


def leer(cx, tabla):
    with cx.cursor() as cur:
        cur.execute("select * from dw." + tabla)
        cols = [d.name for d in cur.description]
        df = pd.DataFrame(cur.fetchall(), columns=cols)
    # NUMERIC llega como Decimal; Parquet lo guarda mejor como double.
    for c in df.columns:
        if len(df) and isinstance(df[c].iloc[0], Decimal):
            df[c] = df[c].astype(float)
    return df


with psycopg.connect(os.environ["DSN_OLAP"]) as cx:
    for t in DIMS:
        df = leer(cx, t)
        d = BASE / t
        d.mkdir(parents=True, exist_ok=True)
        df.to_parquet(d / (t + ".parquet"), index=False, compression="snappy")
        print("%-24s %6d filas  (sin particionar)" % (t, len(df)))

    for t, col in FACTS:
        df = leer(cx, t)
        df["_y"] = df[col] // 10000
        df["_m"] = (df[col] // 100) % 100
        n = 0
        for (y, m), g in df.groupby(["_y", "_m"]):
            d = BASE / t / ("year=%d" % y) / ("month=%02d" % m)
            d.mkdir(parents=True, exist_ok=True)
            g.drop(columns=["_y", "_m"]).to_parquet(
                d / "parte-0000.parquet", index=False, compression="snappy")
            n += 1
        print("%-24s %6d filas  en %d particiones year/month" % (t, len(df), n))
