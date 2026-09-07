"""API de reservas — implementación parcial del backend diseñado en 5.4.

Alcance mínimo exigido por el enunciado (5.6):
  · buscar vuelos disponibles           FR-01
  · crear una reserva                   FR-04, FR-07
  · consultar una reserva existente     FR-11

La creación de reserva refleja la decisión de concurrencia de 5.4 (DEC-03):
no alcanza con que funcione para un usuario a la vez.
"""
from __future__ import annotations

from contextlib import asynccontextmanager
from datetime import date, datetime
from typing import Literal

import psycopg
from fastapi import FastAPI, HTTPException, Query
from pydantic import BaseModel, Field

import config
import repositorio as repo

# ---------------------------------------------------------------------------
#  Modelos de entrada y salida
# ---------------------------------------------------------------------------
Clase = Literal["economica", "business"]


class TramoSolicitado(BaseModel):
    id_instancia: int = Field(..., description="Instancia de vuelo concreta (fecha incluida)")
    clase: Clase = "economica"


class SolicitudReserva(BaseModel):
    id_pasajero: int
    tramos: list[TramoSolicitado] = Field(..., min_length=1)
    id_agencia: int | None = Field(
        None, description="Si viene, la venta es por canal de agencia (FR-13/14/15)"
    )


class ConfirmacionPago(BaseModel):
    id_transaccion_pasarela: str = Field(
        ..., description="Referencia externa. El sistema nunca ve datos de tarjeta (SUP-04)"
    )


# ---------------------------------------------------------------------------
#  Ciclo de vida
# ---------------------------------------------------------------------------
@asynccontextmanager
async def ciclo_vida(app: FastAPI):
    app.state.pool = repo.crear_pool(config.DSN_OLTP)
    yield
    app.state.pool.close()


app = FastAPI(
    title="Reservas de aerolínea — Parcial 1",
    description=(
        "Implementación parcial del backend de 5.4. "
        f"Modo de inventario: **{'INSEGURO (demo)' if config.MODO_INSEGURO else 'seguro (DEC-03)'}**"
    ),
    version="1.0.0",
    lifespan=ciclo_vida,
)


def _pool():
    return app.state.pool


# ---------------------------------------------------------------------------
#  Endpoints
# ---------------------------------------------------------------------------
@app.get("/salud", tags=["operación"])
def salud():
    with _pool().connection() as conn, conn.cursor() as cur:
        cur.execute("SELECT 1 AS ok")
        cur.fetchone()
    return {
        "estado": "ok",
        "modo_inventario": "inseguro" if config.MODO_INSEGURO else "seguro",
        "max_reintentos": config.MAX_REINTENTOS,
    }


@app.get("/vuelos", tags=["búsqueda"], summary="FR-01 · buscar vuelos disponibles")
def buscar_vuelos(
    origen: str = Query(..., min_length=3, max_length=3, examples=["BOG"]),
    destino: str = Query(..., min_length=3, max_length=3, examples=["MDE"]),
    fecha: date = Query(..., description="Fecha de operación"),
    clase: Clase = "economica",
):
    with _pool().connection() as conn:
        # Capa perezosa de DEC-07: un hold vencido no debe contar como ocupado
        repo.expirar_holds(conn)
        filas = repo.buscar_vuelos(conn, origen.upper(), destino.upper(), fecha, clase)
    return {"cantidad": len(filas), "vuelos": filas}


@app.post("/reservas", status_code=201, tags=["reserva"],
          summary="FR-04 · crear reserva (aplica DEC-03)")
def crear_reserva(solicitud: SolicitudReserva):
    try:
        with _pool().connection() as conn:
            return repo.crear_reserva(
                conn,
                id_pasajero=solicitud.id_pasajero,
                tramos=[t.model_dump() for t in solicitud.tramos],
                id_agencia=solicitud.id_agencia,
            )
    except repo.SinCupo as exc:
        # NFR-CONC-01 exige un rechazo EXPLÍCITO, no un error genérico
        raise HTTPException(
            status_code=409,
            detail={"motivo": "sin_capacidad", "mensaje": str(exc)},
        ) from exc
    except repo.ColisionPersistente as exc:
        raise HTTPException(
            status_code=503,
            detail={"motivo": "contencion", "mensaje": str(exc), "reintentable": True},
        ) from exc
    except repo.NoEncontrado as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except psycopg.Error as exc:
        raise HTTPException(status_code=500, detail=f"error de base: {exc}") from exc


@app.get("/reservas/{codigo}", tags=["reserva"], summary="FR-11 · consultar reserva")
def consultar_reserva(codigo: str):
    try:
        with _pool().connection() as conn:
            return repo.obtener_reserva(conn, codigo.upper())
    except repo.NoEncontrado as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.post("/reservas/{codigo}/pago", tags=["reserva"],
          summary="FR-06 · confirmar pago (webhook idempotente, DEC-06)")
def confirmar_pago(codigo: str, cuerpo: ConfirmacionPago):
    try:
        with _pool().connection() as conn:
            return repo.confirmar_pago(conn, codigo.upper(), cuerpo.id_transaccion_pasarela)
    except repo.NoEncontrado as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc


@app.post("/operacion/expirar-holds", tags=["operación"],
          summary="DEC-07 · barrido de retenciones vencidas (NFR-CONC-02)")
def barrer_holds():
    with _pool().connection() as conn:
        return {"reservas_expiradas": repo.expirar_holds(conn)}
