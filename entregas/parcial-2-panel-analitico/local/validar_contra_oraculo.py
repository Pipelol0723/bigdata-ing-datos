"""
Compara la salida del job (las dos tablas en Parquet, locales) contra el oráculo del harness.
Es la misma verdad contra la que corrige el profesor, calculada sin gastar nada en AWS.

    python -I validar_contra_oraculo.py <raiz_del_harness> <seed> <carpeta_curated>

Revisa lo que miran R4, R5 y R6: filas curadas, filas y facturación confirmada de los 24 meses,
las 240 filas de métricas, el top-10 por ocupación y el orden y tipo de las columnas.
"""
import sys
from pathlib import Path

import pyarrow.dataset as ds

sys.path.insert(0, sys.argv[1])
from airline_data.oracle import CURATED_COLUMNS, METRIC_COLUMNS, load_truth  # noqa: E402

seed, curated = int(sys.argv[2]), Path(sys.argv[3])
T = load_truth(seed, 2_000_000)
fallas = []


def chequeo(nombre, ok, detalle=""):
    print(f"[{'ok' if ok else 'FALLA'}] {nombre} {detalle}")
    if not ok:
        fallas.append(nombre)


# ---- reservations_curated ------------------------------------------------------------------------
dir_det = curated / "reservations_curated"
d_ds = ds.dataset(dir_det, format="parquet", partitioning="hive")
archivos = sorted(p for p in dir_det.rglob("*.parquet"))
meses = sorted({p.parent.name for p in archivos})
chequeo("24 carpetas month=", len(meses) == 24 and all(m.startswith("month=") for m in meses), f"({len(meses)})")
chequeo("un archivo por mes", len(archivos) == 24, f"({len(archivos)} archivos)")
esquema = [f.name for f in ds.dataset(archivos[0], format="parquet").schema]
chequeo("columnas del detalle en orden", esquema == CURATED_COLUMNS, str(esquema))
tipos = {f.name: str(f.type) for f in ds.dataset(archivos[0], format="parquet").schema}
chequeo("tipos del detalle", tipos.get("price_cents") == "int64" and tipos.get("reservation_id") == "string"
        and tipos.get("flight_id") == "string", str(tipos))

det = d_ds.to_table().to_pandas()
det["month"] = det["month"].astype(str)
chequeo("filas curadas (C1-C5)", len(det) == T.row_count, f"{len(det):,} vs {T.row_count:,}")
por_mes = det.groupby("month").size().to_dict()
chequeo("filas por mes", por_mes == T.partition_counts)
conf = det[det.status == "CONFIRMED"].groupby("month")["price_cents"].sum()
malos = [m for m in T.partition_counts if int(conf.get(m, 0)) != T.confirmed_revenue(m)]
chequeo("facturación confirmada de los 24 meses", not malos, f"meses distintos: {malos[:5]}")

# Fila por fila contra la verdad del oráculo (mismo reservation_id, mismos valores)
verdad = T.detail.copy()
verdad["reservation_id"] = verdad["reservation_id"].astype(str)
verdad["flight_id"] = verdad["flight_id"].astype(str)
cmp = det.merge(verdad, on="reservation_id", how="outer", suffixes=("", "_v"), indicator=True)
solo = cmp["_merge"].value_counts().to_dict()
chequeo("mismos reservation_id", solo.get("left_only", 0) == 0 and solo.get("right_only", 0) == 0, str(solo))
iguales = all((cmp[c] == cmp[c + "_v"]).all() for c in ["flight_id", "route", "fare_class", "price_cents", "status", "month"])
chequeo("mismos valores fila por fila", iguales)

# ---- route_month_metrics -------------------------------------------------------------------------
dir_met = curated / "route_month_metrics"
met = ds.dataset(dir_met, format="parquet").to_table().to_pandas()
chequeo("columnas de métricas en orden", list(met.columns) == METRIC_COLUMNS, str(list(met.columns)))
chequeo("métricas sin particionar", not any(p.is_dir() for p in dir_met.iterdir()))
om = T.metrics
j = met.merge(om, on=["route", "month"], how="outer", suffixes=("", "_v"), indicator=True)
chequeo("mismos (ruta, mes)", (j["_merge"] == "both").all(), f"{len(met)} vs {len(om)}")
for c in ["seats_capacity", "seats_sold", "revenue_cents", "cancellations"]:
    chequeo(f"métricas: {c}", (j[c] == j[c + "_v"]).all())
chequeo("métricas: occupancy", ((j["occupancy"] - j["occupancy_v"]).abs() < 1e-12).all())
b_conf = (met["bookings"] == met["seats_sold"]).all()
b_todas = (met["bookings"] == met["seats_sold"] + met["cancellations"]).all()
print(f"[info] bookings = {'confirmadas' if b_conf else 'confirmadas+canceladas' if b_todas else '¿otra cosa?'}"
      f" (el oráculo usa confirmadas+canceladas; el harness no lo verifica)")

# ---- R6: el top-10 tal como lo calcula el harness en Athena ---------------------------------------
g = met.groupby("route")[["seats_sold", "seats_capacity"]].sum()
g["occ"] = g["seats_sold"] / g["seats_capacity"]
top = g.sort_values("occ", ascending=False).head(10)
exp = T.top_routes(10)
chequeo("top-10 rutas por ocupación", list(top.index) == list(exp["route"]), str(list(top.index)))

# ---- tamaños: lo que usa R6 para el tope de bytes escaneados ------------------------------------
tam = sum(p.stat().st_size for p in archivos)
print(f"[info] detalle: {tam/1e6:.1f} MB en {len(archivos)} archivos · partición promedio {tam/24/1e6:.2f} MB"
      f" · tope de R6 para una consulta de un mes: {2*tam/24/1e6:.2f} MB")
print("\nRESULTADO:", "TODO COINCIDE con el oráculo" if not fallas else f"{len(fallas)} FALLAS: {fallas}")
sys.exit(1 if fallas else 0)
