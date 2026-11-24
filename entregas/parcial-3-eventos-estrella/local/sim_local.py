"""
Simulación local del camino analítico (US$0): corre los tests ORIGINALES del harness (R5-R10 y R12)
sin AWS, usando la "costura" que el propio harness trae para eso (harness/registry.py).

    Firehose  -> carpeta local con .gz de JSON, UN evento por línea (como con AppendDelimiterToRecord)
    Athena    -> DuckDB, ejecutando EL MISMO SQL de app/sql (con 3 traducciones de dialecto, abajo)
    Glue      -> el esquema de las tablas de DuckDB, con los nombres de tipo de Athena
    refresh   -> servidor HTTP mínimo que usa la MISMA clase Refresco de app/estrella.py

Uso (desde harness/, para no tocar nada del harness):
    set PYTHONPATH=..\\local & python -m pytest -p sim_local tests/test_2_star.py tests/test_3_cost.py

Lo que NO prueba (sólo se ve en AWS): la entrega real de Firehose, el SerDe JSON de Athena, el
escaneo de bytes de R10 (acá se estima) y R11 (configuración del stream).
"""
import datetime as dt
import gzip
import json
import os
import re
import shutil
import sys
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import duckdb

AQUI = Path(__file__).resolve().parent
P3 = AQUI.parent
sys.path.insert(0, str(P3 / "app"))
import estrella  # noqa: E402  (el mismo módulo que usa la API)

DATOS = Path(os.environ.get("P3_DATOS", r"C:\Users\pipel\datos-parcial3"))
LANDING = DATOS / "landing"
REF = P3 / "ref"
SALT = int(os.environ.get("SIM_SALT", "0"))        # para simular el replay del profesor (trampa 1)
CFG = {"bucket": "sim", "db": "airline_star", "raw_uri": "s3://sim/raw/events/"}

COLUMNAS_RAW = {"event_id": "VARCHAR", "event_type": "VARCHAR", "event_ts": "VARCHAR",
                "schema_version": "INTEGER", "session_id": "VARCHAR", "origin": "VARCHAR",
                "destination": "VARCHAR", "travel_date": "VARCHAR", "results_count": "INTEGER",
                "reservation_id": "VARCHAR", "flight_id": "VARCHAR", "route": "VARCHAR",
                "flight_date": "VARCHAR", "fare_class": "VARCHAR", "price_cents": "BIGINT"}
TIPOS_ATHENA = {"INTEGER": "int", "BIGINT": "bigint", "VARCHAR": "string", "DATE": "date",
                "BOOLEAN": "boolean", "DOUBLE": "double", "SMALLINT": "smallint", "TINYINT": "tinyint"}
PARTICIONES = {"fact_search": "month"}


# ------------------------------------------------------------------------- Athena -> DuckDB
def a_duckdb(sql: str) -> str:
    """Las tres diferencias de dialecto Athena (Trino) -> DuckDB que usa nuestro SQL."""
    sql = re.sub(r"CREATE TABLE (\w+)\s+WITH\s*\((?:[^()]|\([^()]*\))*\)\s*AS",
                 r"CREATE OR REPLACE TABLE \1 AS", sql, flags=re.S | re.I)
    return sql.replace("sequence(", "generate_series(").replace("day_of_week(", "isodow(")


class MotorDuckDB:
    """Mismo contrato que estrella.Athena: ejecutar, borrar_prefijo, existe_tabla, hay_objetos_desde."""

    def __init__(self):
        self.con = duckdb.connect()
        self.lock = threading.RLock()

    def _raw(self):
        archivos = list(LANDING.rglob("*.gz"))
        if not archivos:
            cols = ", ".join(f"{c} {t}" for c, t in COLUMNAS_RAW.items())
            return f"CREATE OR REPLACE TABLE raw_events ({cols})"
        cols = ", ".join(f"'{c}': '{t}'" for c, t in COLUMNAS_RAW.items())
        patron = (LANDING / "**" / "*.gz").as_posix()
        return (f"CREATE OR REPLACE VIEW raw_events AS SELECT * FROM read_json('{patron}', "
                f"format = 'newline_delimited', columns = {{{cols}}}, ignore_errors = true)")

    def ejecutar(self, sql: str, base=None) -> dict:
        s = sql.lstrip().upper()
        with self.lock:
            if s.startswith("CREATE DATABASE"):
                return {"bytes": 0}
            if s.startswith("CREATE EXTERNAL TABLE"):
                nombre = re.search(r"EXISTS\s+(\w+)", sql, re.I).group(1)
                if nombre == "raw_events":
                    self.con.execute(self._raw())
                else:
                    archivo = {"ref_routes": "routes_ref.csv", "ref_route_history": "route_category_history.csv",
                               "ref_holidays": "holidays_ref.csv"}[nombre]
                    cols = re.search(r"\((.*?)\)\s*ROW FORMAT", sql, re.S).group(1)
                    nombres = [c.split()[0] for c in cols.split(",")]
                    self.con.execute(
                        f"CREATE OR REPLACE VIEW {nombre} AS SELECT * FROM read_csv('{(REF / archivo).as_posix()}', "
                        f"header = true, all_varchar = true, names = {nombres})")
                return {"bytes": 0}
            self.con.execute(a_duckdb(sql))
            return {"bytes": 0}

    def borrar_prefijo(self, uri):          # las tablas de DuckDB se reemplazan solas
        return 0

    def existe_tabla(self, nombre):
        with self.lock:
            return bool(self.con.execute("SELECT count(*) FROM information_schema.tables WHERE table_name = ?",
                                         [nombre]).fetchone()[0])

    def hay_objetos_desde(self, uri, desde):
        return any(desde is None or dt.datetime.fromtimestamp(p.stat().st_mtime, dt.timezone.utc) > desde
                   for p in LANDING.rglob("*.gz"))

    def consultar(self, sql):
        with self.lock:
            cur = self.con.execute(sql)
            return cur.fetchall(), cur.description


def texto_athena(v):
    """Como devuelve Athena cada celda (VarCharValue)."""
    if v is None:
        return None
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()
    return str(v)


# ------------------------------------------------------------------------- AWS simulado
class AWSSimulado:
    """Los métodos de harness/harness/aws.py que usan los tests de la estrella y del costo."""

    def __init__(self, motor: MotorDuckDB):
        self.m = motor

    # Kinesis -> Firehose -> S3: el replay del harness termina en la landing local
    def kinesis_put(self, stream, records):
        ahora = dt.datetime.now(dt.timezone.utc)
        carpeta = LANDING / ahora.strftime("%Y/%m/%d/%H")
        carpeta.mkdir(parents=True, exist_ok=True)
        for i in range(0, len(records), 5000):             # un objeto por "buffer" de Firehose
            lineas = b"".join(data + b"\n" for _, data in records[i:i + 5000])
            (carpeta / f"sim-{ahora:%Y-%m-%d-%H-%M-%S}-{i // 5000}.gz").write_bytes(gzip.compress(lineas))

    def s3_read_text_since(self, uri, since):
        out = []
        for p in LANDING.rglob("*.gz"):
            if dt.datetime.fromtimestamp(p.stat().st_mtime, dt.timezone.utc) >= since:
                out.append((p.name, gzip.decompress(p.read_bytes()).decode("utf-8")))
        return out

    # Athena
    def athena_run(self, sql, database, workgroup, timeout=180):
        filas, desc = self.m.consultar(sql)
        # R10: estimación de bytes "escaneados" (no medible en local): filas leídas x ancho fijo
        mes = re.search(r"month\s*=\s*'(\d{4}-\d{2})'", sql)
        if "fact_search" in sql:
            n = self.m.consultar("SELECT count(*) FROM fact_search" + (f" WHERE month = '{mes.group(1)}'" if mes else ""))[0][0][0]
        else:
            n = 0
        return {"execution_id": "sim", "rows": [[texto_athena(v) for v in f] for f in filas],
                "data_scanned_bytes": int(n) * 8}

    def athena_workgroup(self, workgroup):
        return {"bytes_cutoff": 1_000_000_000}       # lo crea infra/03 (no verificable en local)

    # Glue: el esquema de la tabla de DuckDB con nombres de tipo de Athena
    def glue_get_table(self, database, name):
        if not self.m.existe_tabla(name):
            return None
        filas, _ = self.m.consultar(f"DESCRIBE {name}")
        part = PARTICIONES.get(name)
        cols = [{"name": c, "type": TIPOS_ATHENA.get(t.upper(), t.lower())} for c, t, *_ in filas]
        return {"name": name, "columns": [c for c in cols if c["name"] != part],
                "partition_keys": [c for c in cols if c["name"] == part],
                "input_format": "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat",
                "serde": "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe",
                "location": f"s3://sim/star/{name}/", "classification": "parquet", "projection_enabled": False}

    def glue_partition_count(self, database, name):
        return self.m.consultar(f"SELECT count(DISTINCT {PARTICIONES[name]}) FROM {name}")[0][0][0]

    def kinesis_summary(self, stream):
        return None                                  # R11 sólo se verifica en AWS


# --------------------------------------------------------- API de refresh (misma clase Refresco)
def servidor(refresco: estrella.Refresco) -> int:
    class H(BaseHTTPRequestHandler):
        def _json(self, codigo, cuerpo):
            b = json.dumps(cuerpo).encode()
            self.send_response(codigo)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(b)))
            self.end_headers()
            self.wfile.write(b)

        def do_POST(self):
            if self.path.startswith("/admin/refresh-star"):
                return self._json(202, refresco.iniciar("manual"))
            self._json(404, {})

        def do_GET(self):
            if self.path.startswith("/admin/refresh-status"):
                return self._json(200, refresco.estado())
            self._json(404, {})

        def log_message(self, *a):
            pass

    srv = ThreadingHTTPServer(("127.0.0.1", 0), H)
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv.server_address[1]


# --------------------------------------------------------------------------- plugin de pytest
def pytest_configure(config):
    from harness import registry
    if os.environ.get("SIM_LIMPIAR", "1") == "1":       # SIM_LIMPIAR=0 simula una landing con corridas viejas
        shutil.rmtree(LANDING, ignore_errors=True)
    LANDING.mkdir(parents=True, exist_ok=True)
    motor = MotorDuckDB()
    puerto = servidor(estrella.Refresco(motor, CFG, cada_min=0))
    registry.AWS_OVERRIDE = AWSSimulado(motor)
    registry.CONFIG_OVERRIDE = {
        "team_id": "andres-cespedes (simulacion local)", "seed": 12345,
        "backend": {"base_url": f"http://127.0.0.1:{puerto}"},
        "aws": {"region": "us-east-1", "kinesis_stream": "airline-events", "raw_events_uri": CFG["raw_uri"],
                "athena_workgroup": "parcial3", "athena_database": CFG["db"]},
        "cost_projection_file": str(P3 / "cost_projection.yaml")}
    if SALT:
        from harness.config import load_thresholds
        thr = load_thresholds()
        thr["probe_salt"] = SALT
        registry.THRESHOLDS_OVERRIDE = thr
    os.environ.setdefault("HARNESS_REPORT", str(AQUI / "reportes" / "reporte-sim"))
    (AQUI / "reportes").mkdir(exist_ok=True)
