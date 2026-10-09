"""
Inspecciona el dataset del taller SIN descargarlo: sólo lee los pies (footers) de los 12 Parquet
del TLC —unos KB por archivo— y la tabla de zonas (12 KB).

Por qué antes de levantar el clúster: cada dato de acá cambia una decisión del plan (esquema
explícito, filtro de fechas, agrupar por ID), y averiguarlo con EMR encendido cuesta plata.

    python inspeccionar_dataset.py

Requiere: duckdb (instala solo su extensión httpfs la primera vez).
"""

import duckdb

BASE = "https://d37ci6vzurychx.cloudfront.net"
URLS = [f"{BASE}/trip-data/yellow_tripdata_2018-{m:02d}.parquet" for m in range(1, 13)]
ZONAS = f"{BASE}/misc/taxi_zone_lookup.csv"
COLS = ["tpep_pickup_datetime", "tpep_dropoff_datetime", "PULocationID", "DOLocationID"]

con = duckdb.connect()
con.execute("SET autoinstall_known_extensions = true; SET autoload_known_extensions = true;")
MES = "regexp_extract(file_name, '2018-(\\d\\d)', 1)"


def fecha(valor):
    """DuckDB devuelve los min/max de un timestamp ya formateados; algunas versiones, en microsegundos."""
    try:
        return con.execute("SELECT make_timestamp(?::BIGINT)::VARCHAR", [int(valor)]).fetchone()[0][:19]
    except ValueError:
        return str(valor)[:19]


# --- 1. Filas y row groups por mes -------------------------------------------------------------
filas = con.execute(f"SELECT {MES}, num_rows, num_row_groups FROM parquet_file_metadata(?) "
                    "ORDER BY 1", [URLS]).fetchall()
print("1) FILAS POR MES (row groups)")
for mes, n, rg in filas:
    print(f"   {mes}  {n:>11,}  ({rg})")
print(f"   TOTAL {sum(f[1] for f in filas):,}\n")

# --- 2. ¿Cada columna tiene el mismo tipo en los 12 meses? -------------------------------------
esquema = con.execute(f"SELECT {MES}, name, type, coalesce(logical_type, converted_type) "
                      "FROM parquet_schema(?) WHERE name <> 'schema'", [URLS]).fetchall()
tipos = {}
for mes, col, fisico, logico in esquema:
    clave = fisico + (" NULL" if logico and "Null" in logico else "")
    tipos.setdefault(col, {}).setdefault(clave, []).append(mes)
print("2) TIPOS POR COLUMNA  (!! = cambia entre meses)")
for col, t in tipos.items():
    detalle = " | ".join(f"{k} [{'todos' if len(v) == 12 else ','.join(v)}]" for k, v in t.items())
    print(f"   {'!!' if len(t) > 1 else '  '} {col:<22} {detalle}")

# --- 3. Rangos de las 4 columnas que usa el taller (estadísticas del pie) ----------------------
meta = con.execute(f"SELECT {MES}, path_in_schema, stats_min_value, stats_max_value, "
                   "stats_null_count, total_compressed_size FROM parquet_metadata(?)",
                   [URLS]).fetchall()
rango = {}
for mes, col, mn, mx, nulos, _ in meta:
    rango.setdefault(mes, {})[col] = (mn, mx, nulos or 0)
print("\n3) RANGOS  (recogida min/max · bajada min/max · LocationID · nulos)")
for mes in sorted(rango):
    r = rango[mes]
    pu, do = r["tpep_pickup_datetime"], r["tpep_dropoff_datetime"]
    print(f"   {mes}  {fecha(pu[0])} → {fecha(pu[1])}  ·  {fecha(do[0])} → {fecha(do[1])}  ·  "
          f"PU [{r['PULocationID'][0]},{r['PULocationID'][1]}] DO [{r['DOLocationID'][0]},"
          f"{r['DOLocationID'][1]}]  ·  {sum(r[c][2] for c in COLS)}")

total = sum(m[5] for m in meta)
usadas = sum(m[5] for m in meta if m[1] in COLS)
print(f"\n4) BYTES: las 4 columnas del taller pesan {usadas:,} de {total:,} ({usadas / total:.0%})")

# --- 5. Zonas -----------------------------------------------------------------------------------
print("\n5) ZONAS")
print("   ", con.execute(f"SELECT count(*) AS filas, min(LocationID), max(LocationID), "
                       f"count(DISTINCT LocationID) FROM read_csv('{ZONAS}')").fetchone())
for fila in con.execute(f"SELECT * FROM read_csv('{ZONAS}') WHERE LocationID IN (264, 265)").fetchall():
    print("    sin zona real:", fila)
for fila in con.execute(f"SELECT Zone, list(LocationID ORDER BY LocationID) FROM read_csv('{ZONAS}') "
                        "GROUP BY Zone HAVING count(*) > 1").fetchall():
    print("    nombre repetido:", fila)
