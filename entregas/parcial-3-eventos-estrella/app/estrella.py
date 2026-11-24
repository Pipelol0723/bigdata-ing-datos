"""
Parcial 3 · construcción del modelo estrella con Athena (decisiones D5, D6, D8, D11).

El ETL es SQL (app/sql/*.sql) que corre en Athena: CTAS escribe Parquet en S3 y registra la tabla
y sus particiones en el Glue Data Catalog, todo en un paso. Este módulo sólo:
  1. lee las sentencias y les completa {bucket}, {db} y {raw_uri};
  2. antes de cada CTAS borra su external_location (Athena no escribe sobre datos existentes:
     es lo que hace idempotente el rebuild completo);
  3. corre las sentencias en orden y lleva el estado RUNNING / SUCCEEDED / FAILED del refresh.

Lo usan tres clientes con el MISMO código:
  - la API (main.py): POST /admin/refresh-star, GET /admin/refresh-status y el bucle automático;
  - los scripts de infraestructura, por línea de comandos (dimensiones una sola vez, D11):
        python estrella.py dimensiones --bucket B --db airline_star --workgroup parcial3
  - la simulación local (local/sim_local.py), que cambia Athena por DuckDB para probar a US$0.

Sin credenciales en el código: boto3 toma las del instance profile (LabRole) en la EC2, o las del
entorno en CloudShell.
"""
import argparse
import datetime as dt
import re
import threading
import time
import uuid
from pathlib import Path

SQL = Path(__file__).resolve().parent / "sql"
DIMENSIONES = ("dim_date", "dim_route", "dim_fare_class")
HECHOS = ("fact_search", "fact_booking_event")
UBICACION = re.compile(r"external_location\s*=\s*'([^']+)'", re.I)


def sentencias(archivo: str, **valores) -> list[str]:
    """Sentencias de un .sql, sin las líneas de comentario y con los valores completados."""
    texto = (SQL / archivo).read_text(encoding="utf-8")
    texto = "\n".join(l for l in texto.splitlines() if not l.lstrip().startswith("--"))
    return [s.strip().format(**valores) for s in re.split(r";[ \t]*(?:\r?\n|$)", texto) if s.strip()]


# ------------------------------------------------------------------------------- motor Athena
class Athena:
    """Corre SQL en Athena (workgroup con límite por consulta, R10) y maneja S3/Glue."""

    def __init__(self, database: str, workgroup: str, region: str = "us-east-1", output: str | None = None):
        import boto3
        self.database, self.workgroup, self.output = database, workgroup, output
        self.athena = boto3.client("athena", region_name=region)
        self.s3 = boto3.client("s3", region_name=region)
        self.glue = boto3.client("glue", region_name=region)

    def ejecutar(self, sql: str, base: str | None = None, timeout: float = 600) -> dict:
        kw = {"QueryString": sql, "WorkGroup": self.workgroup,
              "QueryExecutionContext": {"Database": base or self.database}}
        if self.output:
            kw["ResultConfiguration"] = {"OutputLocation": self.output}
        qid = self.athena.start_query_execution(**kw)["QueryExecutionId"]
        limite, espera = time.monotonic() + timeout, 0.3
        while True:
            qe = self.athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
            estado = qe["Status"]["State"]
            if estado == "SUCCEEDED":
                return {"id": qid, "bytes": int(qe.get("Statistics", {}).get("DataScannedInBytes", 0))}
            if estado in ("FAILED", "CANCELLED"):
                raise RuntimeError(f"Athena {estado} ({qid}): {qe['Status'].get('StateChangeReason', '')}"
                                   f" -- {sql.splitlines()[0][:80]}")
            if time.monotonic() > limite:
                raise TimeoutError(f"Athena {qid} sigue {estado} después de {timeout:.0f} s")
            time.sleep(espera)
            espera = min(espera * 1.5, 2.0)

    def borrar_prefijo(self, uri: str) -> int:
        bucket, _, prefijo = uri.removeprefix("s3://").partition("/")
        n = 0
        for pagina in self.s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefijo):
            claves = [{"Key": o["Key"]} for o in pagina.get("Contents", [])]
            for i in range(0, len(claves), 1000):
                self.s3.delete_objects(Bucket=bucket, Delete={"Objects": claves[i:i + 1000], "Quiet": True})
            n += len(claves)
        return n

    def existe_tabla(self, nombre: str) -> bool:
        try:
            self.glue.get_table(DatabaseName=self.database, Name=nombre)
            return True
        except self.glue.exceptions.EntityNotFoundException:
            return False

    def hay_objetos_desde(self, uri: str, desde: dt.datetime | None) -> bool:
        """¿Llegó algo a la landing después de `desde`? Un LIST de S3: ~US$0,000005."""
        bucket, _, prefijo = uri.removeprefix("s3://").partition("/")
        for pagina in self.s3.get_paginator("list_objects_v2").paginate(Bucket=bucket, Prefix=prefijo):
            for o in pagina.get("Contents", []):
                if desde is None or o["LastModified"] > desde:
                    return True
        return False


# --------------------------------------------------------------------------------- el pipeline
def _correr(motor, archivo: str, cfg: dict) -> list[dict]:
    hechos = []
    for s in sentencias(archivo, **cfg):
        m = UBICACION.search(s)
        if m:                                   # CTAS: primero vaciar su carpeta (idempotencia)
            motor.borrar_prefijo(m.group(1))
        base = "default" if s.upper().startswith("CREATE DATABASE") else None
        t0 = time.monotonic()
        r = motor.ejecutar(s, base=base)
        hechos.append({"sql": s.splitlines()[0][:70], "segundos": round(time.monotonic() - t0, 2),
                       "bytes": r.get("bytes", 0)})
    return hechos


def construir_base(motor, cfg):
    return _correr(motor, "00_base.sql", cfg)


def construir_dimensiones(motor, cfg):
    return _correr(motor, "10_dimensiones.sql", cfg)


def construir_hechos(motor, cfg):
    return _correr(motor, "20_hechos.sql", cfg)


def refrescar(motor, cfg) -> list[dict]:
    """Un refresh completo: tablas de entrada, dimensiones si falta alguna, y los dos hechos."""
    pasos = construir_base(motor, cfg)
    if not all(motor.existe_tabla(t) for t in DIMENSIONES):
        pasos += construir_dimensiones(motor, cfg)
    return pasos + construir_hechos(motor, cfg)


# ------------------------------------------------------------------ estado del refresh (la API)
class Refresco:
    """Un solo refresh a la vez. POST /admin/refresh-star llama a iniciar(); GET /refresh-status lee
    estado(). El estado pasa a RUNNING ANTES de responder el POST: así quien sondea nunca ve el
    SUCCEEDED de la corrida anterior.

    Bucle automático (D8): cada `cada_min` minutos, y sólo si llegó algo nuevo a la landing desde el
    último refresh. Además espera `cada_min` desde que TERMINÓ el último (manual o automático): así
    no reconstruye las tablas mientras alguien (el harness) las está consultando."""

    def __init__(self, motor, cfg: dict, cada_min: float = 10):
        self.motor, self.cfg, self.cada_min = motor, cfg, cada_min
        self._lock = threading.Lock()
        self._estado = {"state": "SUCCEEDED", "job_id": None, "detail": "todavía no corrió ningún refresh"}
        self._inicio_ok: dt.datetime | None = None    # inicio del último refresh exitoso
        self._fin = 0.0                               # time.monotonic() del último fin

    def estado(self) -> dict:
        with self._lock:
            return dict(self._estado)

    def iniciar(self, origen: str = "manual") -> dict:
        with self._lock:
            if self._estado["state"] == "RUNNING":
                return dict(self._estado)
            job = uuid.uuid4().hex[:12]
            self._estado = {"state": "RUNNING", "job_id": job, "origin": origen,
                            "started_at": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")}
        threading.Thread(target=self._trabajar, args=(job,), daemon=True, name=f"refresh-{job}").start()
        return {"job_id": job, "state": "RUNNING"}

    def _trabajar(self, job: str):
        inicio, t0 = dt.datetime.now(dt.timezone.utc), time.monotonic()
        try:
            pasos = refrescar(self.motor, self.cfg)
            final = {"state": "SUCCEEDED", "steps": len(pasos),
                     "bytes_scanned": sum(p["bytes"] for p in pasos)}
            self._inicio_ok = inicio
        except Exception as ex:                           # el estado tiene que decir por qué falló
            final = {"state": "FAILED", "error": f"{type(ex).__name__}: {ex}"[:500]}
        with self._lock:
            self._estado.update(final, seconds=round(time.monotonic() - t0, 1))
            self._fin = time.monotonic()

    def bucle(self, landing_uri: str, revisar_cada_s: float = 30):
        """Hilo del refresh periódico (D8). cada_min = 0 lo apaga."""
        while True:
            time.sleep(revisar_cada_s)
            if self.cada_min <= 0 or self.estado()["state"] == "RUNNING":
                continue
            if time.monotonic() - self._fin < self.cada_min * 60:
                continue
            try:
                if self.motor.hay_objetos_desde(landing_uri, self._inicio_ok):
                    self.iniciar("automatico")
                else:
                    self._fin = time.monotonic()          # nada nuevo: volver a mirar en cada_min
            except Exception:
                self._fin = time.monotonic()


# ------------------------------------------------------------------------- línea de comandos
def main():
    ap = argparse.ArgumentParser(description="Construye el modelo estrella del parcial 3 en Athena.")
    ap.add_argument("que", choices=["base", "dimensiones", "hechos", "todo"])
    ap.add_argument("--bucket", required=True)
    ap.add_argument("--db", default="airline_star")
    ap.add_argument("--workgroup", default="parcial3")
    ap.add_argument("--raw-uri", help="landing zone (por defecto s3://BUCKET/raw/events/)")
    ap.add_argument("--region", default="us-east-1")
    a = ap.parse_args()
    cfg = {"bucket": a.bucket, "db": a.db, "raw_uri": a.raw_uri or f"s3://{a.bucket}/raw/events/"}
    motor = Athena(a.db, a.workgroup, a.region)
    pasos = construir_base(motor, cfg)
    if a.que in ("dimensiones", "todo"):
        pasos += construir_dimensiones(motor, cfg)
    if a.que in ("hechos", "todo"):
        pasos += construir_hechos(motor, cfg)
    for p in pasos:
        print(f"{p['segundos']:6.2f} s  {p['bytes']:>10,} B  {p['sql']}")
    print(f"total: {sum(p['segundos'] for p in pasos):.1f} s, {sum(p['bytes'] for p in pasos):,} B escaneados")


if __name__ == "__main__":
    main()
