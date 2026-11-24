"""
Parcial 3 · la API del parcial 2 + eventos a Kinesis, vista en vivo y refresh del modelo estrella.

Contratos: harness/contract/API.md y EVENTS.md. Todo lo del parcial 2 sigue igual (crear vuelos,
buscar, reservar, consultar, health y el frontend). Se agregan:
  - un evento por búsqueda, reserva y cancelación (eventos.py, decisión D2);
  - POST /reservations/{id}/cancel;
  - GET /analytics/live, alimentado por un consumidor del stream (en_vivo.py, decisión D3);
  - POST /admin/refresh-star y GET /admin/refresh-status, que reconstruyen la estrella con Athena
    (estrella.py, decisiones D5, D6 y D8).
Un solo proceso uvicorn (Dockerfile): la vista en vivo y el estado del refresh viven en su memoria.
Configuración por variables de entorno (docker-compose.yml); sin credenciales en el código: en la
EC2, boto3 toma las del instance profile (LabRole).
"""
import logging
import os
import threading
import time
import uuid
from contextlib import asynccontextmanager
from datetime import date
from pathlib import Path
from typing import Literal

import boto3
from fastapi import FastAPI, Header, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

import estrella
from en_vivo import HORIZONTE_MIN, VistaEnVivo
from eventos import Publicador, evento

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(name)s %(levelname)s %(message)s")
AQUI = Path(__file__).resolve().parent
RUTA = r"^[A-Z]{3}-[A-Z]{3}$"
MES = r"^\d{4}-(0[1-9]|1[0-2])$"

DATABASE_URL = os.environ["DATABASE_URL"]
REGION = os.environ.get("AWS_REGION", "us-east-1")
# Parcial 2 (sigue andando mientras existan su bucket y su base de Glue)
ATHENA_DATABASE = os.environ.get("ATHENA_DATABASE", "airline_analytics")
ATHENA_WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "primary")
ATHENA_OUTPUT = os.environ.get("ATHENA_OUTPUT")
METRICS_TABLE = os.environ.get("METRICS_TABLE", "route_month_metrics")
ATHENA_TIMEOUT_S = float(os.environ.get("ATHENA_TIMEOUT_S", "9"))
# Parcial 3
KINESIS_STREAM = os.environ.get("KINESIS_STREAM", "airline-events")
STAR_BUCKET = os.environ.get("STAR_BUCKET", "")
STAR_DB = os.environ.get("STAR_DB", "airline_star")
STAR_WORKGROUP = os.environ.get("STAR_WORKGROUP", "parcial3")
RAW_URI = os.environ.get("RAW_URI") or f"s3://{STAR_BUCKET}/raw/events/"
REFRESH_CADA_MIN = float(os.environ.get("REFRESH_CADA_MIN", "10"))     # 0 apaga el refresh automático

pool = ConnectionPool(DATABASE_URL, min_size=2, max_size=20, timeout=30, open=False,
                      kwargs={"autocommit": True, "row_factory": dict_row})
publicador = Publicador(KINESIS_STREAM, REGION)
vista = VistaEnVivo(KINESIS_STREAM, REGION)
refresco = estrella.Refresco(estrella.Athena(STAR_DB, STAR_WORKGROUP, REGION),
                             {"bucket": STAR_BUCKET, "db": STAR_DB, "raw_uri": RAW_URI},
                             cada_min=REFRESH_CADA_MIN)


@asynccontextmanager
async def ciclo_de_vida(_app):
    pool.open(wait=True)
    with pool.connection() as conn:
        conn.execute((AQUI / "schema.sql").read_text(encoding="utf-8"))
    publicador.iniciar()
    vista.iniciar()
    threading.Thread(target=refresco.bucle, args=(RAW_URI,), daemon=True, name="refresh-automatico").start()
    yield
    pool.close()


app = FastAPI(title="Aerolínea · parcial 3", lifespan=ciclo_de_vida)


# ---- Modelos ------------------------------------------------------------------------------------

class Vuelo(BaseModel):
    flight_id: str = Field(min_length=1, max_length=64)
    route: str = Field(pattern=RUTA)
    flight_date: date
    capacity: int = Field(gt=0)
    price_cents: int = Field(gt=0)


class PedidoReserva(BaseModel):
    flight_id: str = Field(min_length=1, max_length=64)
    passenger_name: str = Field(min_length=1, max_length=200)
    fare_class: Literal["ECONOMY", "BUSINESS"]


def _reserva(fila):
    return {"reservation_id": fila["reservation_id"], "flight_id": fila["flight_id"],
            "status": fila["status"], "passenger_name": fila["passenger_name"],
            "fare_class": fila["fare_class"]}


def _evento_reserva(tipo: str, reserva: dict, vuelo: dict) -> dict:
    """reservation_created / reservation_cancelled: mismos campos (EVENTS.md). SIN passenger_name:
    los eventos van a S3 y a la analítica, y no necesitan datos personales (R1)."""
    return evento(tipo, reservation_id=reserva["reservation_id"], flight_id=reserva["flight_id"],
                  route=vuelo["route"], flight_date=vuelo["flight_date"].isoformat(),
                  fare_class=reserva["fare_class"],
                  price_cents=int(reserva.get("price_cents") or vuelo["price_cents"]))


# ---- Transaccional ------------------------------------------------------------------------------

@app.post("/admin/flights", status_code=201)
def crear_vuelo(v: Vuelo):
    try:
        with pool.connection() as conn:
            conn.execute(
                "INSERT INTO flights (flight_id, route, flight_date, capacity, seats_available, price_cents) "
                "VALUES (%s, %s, %s, %s, %s, %s)",
                (v.flight_id, v.route, v.flight_date, v.capacity, v.capacity, v.price_cents))
    except UniqueViolation:
        raise HTTPException(409, f"el vuelo {v.flight_id} ya existe")
    return v.model_dump(mode="json")


@app.get("/flights/search")
def buscar_vuelos(origin: str = Query(pattern=r"^[A-Za-z]{3}$"),
                  destination: str = Query(pattern=r"^[A-Za-z]{3}$"),
                  fecha: date = Query(alias="date"),
                  x_session_id: str | None = Header(default=None)):
    o, d = origin.upper(), destination.upper()
    with pool.connection() as conn:
        filas = conn.execute(
            "SELECT flight_id, route, flight_date, seats_available, price_cents FROM flights "
            "WHERE route = %s AND flight_date = %s AND seats_available > 0 ORDER BY flight_id",
            (f"{o}-{d}", fecha)).fetchall()
    # R1: un evento por llamada; partition key = session_id (header opcional; si no viene, se genera).
    sesion = x_session_id or f"anon-{uuid.uuid4().hex}"
    publicador.publicar(evento("search_performed", session_id=sesion, origin=o, destination=d,
                               travel_date=fecha.isoformat(), results_count=len(filas)), sesion)
    return [{**f, "flight_date": f["flight_date"].isoformat()} for f in filas]


@app.post("/reservations", status_code=201)
def reservar(p: PedidoReserva):
    """Sin sobreventa (P2): descontar el asiento y crear la reserva van en UNA transacción. El evento
    se publica DESPUÉS del commit: nunca se anuncia una reserva que la base no guardó."""
    with pool.connection() as conn, conn.transaction():
        vuelo = conn.execute("UPDATE flights SET seats_available = seats_available - 1 "
                             "WHERE flight_id = %s AND seats_available > 0 "
                             "RETURNING flight_id, route, flight_date, price_cents",
                             (p.flight_id,)).fetchone()
        if vuelo is None:
            existe = conn.execute("SELECT 1 FROM flights WHERE flight_id = %s", (p.flight_id,)).fetchone()
            raise HTTPException(409 if existe else 404,
                                "no quedan asientos" if existe else f"vuelo {p.flight_id} desconocido")
        fila = conn.execute(
            "INSERT INTO reservations (reservation_id, flight_id, passenger_name, fare_class, price_cents) "
            "VALUES (%s, %s, %s, %s, %s) RETURNING *",
            ("R" + uuid.uuid4().hex[:15].upper(), p.flight_id, p.passenger_name, p.fare_class,
             vuelo["price_cents"])).fetchone()
    publicador.publicar(_evento_reserva("reservation_created", fila, vuelo), vuelo["flight_id"], critico=True)
    return _reserva(fila)


@app.post("/reservations/{reservation_id}/cancel")
def cancelar(reservation_id: str):
    """200 con la reserva CANCELLED, libera el asiento y publica reservation_cancelled.
    404 si no existe, 409 si ya estaba cancelada. El UPDATE condicionado a status = 'CONFIRMED'
    resuelve la carrera de dos cancelaciones simultáneas: sólo una lo encuentra confirmado."""
    with pool.connection() as conn, conn.transaction():
        fila = conn.execute("UPDATE reservations SET status = 'CANCELLED' "
                            "WHERE reservation_id = %s AND status = 'CONFIRMED' RETURNING *",
                            (reservation_id,)).fetchone()
        if fila is None:
            existe = conn.execute("SELECT 1 FROM reservations WHERE reservation_id = %s",
                                  (reservation_id,)).fetchone()
            raise HTTPException(409 if existe else 404,
                                "la reserva ya estaba cancelada" if existe else "reserva desconocida")
        vuelo = conn.execute("UPDATE flights SET seats_available = seats_available + 1 WHERE flight_id = %s "
                             "RETURNING flight_id, route, flight_date, price_cents",
                             (fila["flight_id"],)).fetchone()
    publicador.publicar(_evento_reserva("reservation_cancelled", fila, vuelo), vuelo["flight_id"], critico=True)
    return _reserva(fila)


@app.get("/reservations/{reservation_id}")
def ver_reserva(reservation_id: str):
    with pool.connection() as conn:
        fila = conn.execute("SELECT * FROM reservations WHERE reservation_id = %s", (reservation_id,)).fetchone()
    if fila is None:
        raise HTTPException(404, "reserva desconocida")
    return _reserva(fila)


# ---- Camino rápido: vista en vivo desde el stream (R3) ------------------------------------------

@app.get("/analytics/live")
def en_vivo(window: int = Query(5, ge=1, le=HORIZONTE_MIN)):
    return vista.resumen(window)


# ---- Camino analítico: refresh del modelo estrella (R8) ------------------------------------------

@app.post("/admin/refresh-star", status_code=202)
def refrescar_estrella():
    return refresco.iniciar("manual")


@app.get("/admin/refresh-status")
def estado_refresh():
    return refresco.estado()


@app.get("/admin/pipeline")
def estado_pipeline():
    """Diagnóstico (no es del contrato): cómo vienen la publicación y el consumidor."""
    return {"publicador": dict(publicador.metricas, en_cola=publicador.cola.qsize()),
            "en_vivo": vista.estado, "refresh": refresco.estado()}


# ---- Analítico del parcial 2: Athena sobre la historia (sigue igual) -----------------------------

athena = boto3.client("athena", region_name=REGION)


def consultar_athena(sql: str, parametros: list[str]):
    kw = {"QueryString": sql, "QueryExecutionContext": {"Database": ATHENA_DATABASE},
          "WorkGroup": ATHENA_WORKGROUP, "ExecutionParameters": parametros}
    if ATHENA_OUTPUT:
        kw["ResultConfiguration"] = {"OutputLocation": ATHENA_OUTPUT}
    qid = athena.start_query_execution(**kw)["QueryExecutionId"]
    limite = time.monotonic() + ATHENA_TIMEOUT_S
    while True:
        estado = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]["Status"]
        if estado["State"] == "SUCCEEDED":
            break
        if estado["State"] in ("FAILED", "CANCELLED"):
            raise HTTPException(502, f"Athena {estado['State']}: {estado.get('StateChangeReason', '')}")
        if time.monotonic() > limite:
            raise HTTPException(504, f"Athena no respondió en {ATHENA_TIMEOUT_S:g} s (consulta {qid})")
        time.sleep(0.2)
    filas = athena.get_query_results(QueryExecutionId=qid)["ResultSet"]["Rows"]
    return qid, [[c.get("VarCharValue") for c in f["Data"]] for f in filas[1:]]


@app.get("/analytics/occupancy")
def ocupacion(route: str = Query(pattern=RUTA), month: str = Query(pattern=MES)):
    qid, filas = consultar_athena(
        f"SELECT occupancy, seats_sold, seats_capacity FROM {METRICS_TABLE} WHERE route = ? AND month = ?",
        [f"'{route}'", f"'{month}'"])
    if not filas:
        raise HTTPException(404, f"no hay datos para {route} en {month}")
    occ, vendidos, capacidad = filas[0]
    return JSONResponse({"route": route, "month": month, "occupancy": float(occ),
                         "seats_sold": int(vendidos), "seats_capacity": int(capacidad)},
                        headers={"X-Athena-Query-Id": qid})


@app.get("/health")
def salud():
    with pool.connection() as conn:
        conn.execute("SELECT 1")
    return {"status": "ok"}


# ---- Frontend (del parcial 2) ---------------------------------------------------------------------

@app.get("/", response_class=HTMLResponse, include_in_schema=False)
def pagina_cliente():
    return (AQUI / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/manager", response_class=HTMLResponse, include_in_schema=False)
def pagina_gerente():
    return (AQUI / "static" / "manager.html").read_text(encoding="utf-8")
