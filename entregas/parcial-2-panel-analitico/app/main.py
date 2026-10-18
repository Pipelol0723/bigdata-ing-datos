"""
Parcial 2 · backend de reservas + endpoint analítico + las dos páginas del frontend.

Contrato: harness/contract/API.md. Un solo proceso sirve la API y el HTML (mismo origen: sin CORS).
Configuración por variables de entorno (ver docker-compose.yml); nada de credenciales en el código:
en la EC2, boto3 toma las del instance profile (LabRole).
"""
import os
import time
import uuid
from contextlib import asynccontextmanager
from datetime import date
from pathlib import Path
from typing import Literal

import boto3
from fastapi import FastAPI, HTTPException, Query
from fastapi.responses import HTMLResponse, JSONResponse
from psycopg.errors import UniqueViolation
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool
from pydantic import BaseModel, Field

AQUI = Path(__file__).resolve().parent
RUTA = r"^[A-Z]{3}-[A-Z]{3}$"
MES = r"^\d{4}-(0[1-9]|1[0-2])$"

DATABASE_URL = os.environ["DATABASE_URL"]
ATHENA_DATABASE = os.environ.get("ATHENA_DATABASE", "airline_analytics")
ATHENA_WORKGROUP = os.environ.get("ATHENA_WORKGROUP", "primary")
ATHENA_OUTPUT = os.environ.get("ATHENA_OUTPUT")            # s3://bucket/athena-results/
METRICS_TABLE = os.environ.get("METRICS_TABLE", "route_month_metrics")
ATHENA_TIMEOUT_S = float(os.environ.get("ATHENA_TIMEOUT_S", "9"))   # R7 exige < 10 s

# El pool ESPERA una conexión libre (hasta 30 s) en vez de fallar: con 50 reservas simultáneas
# (R2) un pool agotado que devolviera error sería un 500, y R2 prohíbe cualquier 5xx.
pool = ConnectionPool(DATABASE_URL, min_size=2, max_size=20, timeout=30, open=False,
                      kwargs={"autocommit": True, "row_factory": dict_row})


@asynccontextmanager
async def ciclo_de_vida(_app):
    pool.open(wait=True)
    with pool.connection() as conn:
        conn.execute((AQUI / "schema.sql").read_text(encoding="utf-8"))
    yield
    pool.close()


app = FastAPI(title="Aerolínea · parcial 2", lifespan=ciclo_de_vida)


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
                  fecha: date = Query(alias="date")):
    with pool.connection() as conn:
        filas = conn.execute(
            "SELECT flight_id, route, flight_date, seats_available, price_cents FROM flights "
            "WHERE route = %s AND flight_date = %s AND seats_available > 0 ORDER BY flight_id",
            (f"{origin.upper()}-{destination.upper()}", fecha)).fetchall()
    return [{**f, "flight_date": f["flight_date"].isoformat()} for f in filas]


@app.post("/reservations", status_code=201)
def reservar(p: PedidoReserva):
    """Sin sobreventa (R2): el descuento del asiento y la reserva van en UNA transacción, y el
    UPDATE sólo afecta la fila si todavía queda un asiento. PostgreSQL bloquea la fila del vuelo
    mientras dura la transacción: 50 pedidos simultáneos por el último asiento se ordenan solos,
    el primero descuenta y los otros 49 ven seats_available = 0 y no actualizan nada -> 409."""
    with pool.connection() as conn, conn.transaction():
        if conn.execute("UPDATE flights SET seats_available = seats_available - 1 "
                        "WHERE flight_id = %s AND seats_available > 0 RETURNING flight_id",
                        (p.flight_id,)).fetchone() is None:
            existe = conn.execute("SELECT 1 FROM flights WHERE flight_id = %s", (p.flight_id,)).fetchone()
            raise HTTPException(409 if existe else 404,
                                "no quedan asientos" if existe else f"vuelo {p.flight_id} desconocido")
        fila = conn.execute(
            "INSERT INTO reservations (reservation_id, flight_id, passenger_name, fare_class) "
            "VALUES (%s, %s, %s, %s) RETURNING *",
            ("R" + uuid.uuid4().hex[:15].upper(), p.flight_id, p.passenger_name, p.fare_class)).fetchone()
    return _reserva(fila)


@app.get("/reservations/{reservation_id}")
def ver_reserva(reservation_id: str):
    # Texto, no int: un id que no existe ('does-not-exist-...') tiene que dar 404, no 422 (R3)
    with pool.connection() as conn:
        fila = conn.execute("SELECT * FROM reservations WHERE reservation_id = %s", (reservation_id,)).fetchone()
    if fila is None:
        raise HTTPException(404, "reserva desconocida")
    return _reserva(fila)


# ---- Analítico: siempre desde Athena (R7) -------------------------------------------------------

athena = boto3.client("athena", region_name=os.environ.get("AWS_REGION", "us-east-1"))


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
    return qid, [[c.get("VarCharValue") for c in f["Data"]] for f in filas[1:]]   # [0] = encabezado


@app.get("/analytics/occupancy")
def ocupacion(route: str = Query(pattern=RUTA), month: str = Query(pattern=MES)):
    # Doble defensa contra inyección SQL: el formato se valida arriba (si no, 422) y los valores
    # viajan como parámetros de Athena, nunca pegados al texto de la consulta.
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


# ---- Frontend (R8, R9): dos páginas estáticas servidas por el mismo proceso ------------------------

@app.get("/", response_class=HTMLResponse, include_in_schema=False)
def pagina_cliente():
    return (AQUI / "static" / "index.html").read_text(encoding="utf-8")


@app.get("/manager", response_class=HTMLResponse, include_in_schema=False)
def pagina_gerente():
    return (AQUI / "static" / "manager.html").read_text(encoding="utf-8")
