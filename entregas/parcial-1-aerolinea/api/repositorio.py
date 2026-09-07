"""Acceso a datos y reglas de inventario.

Acá vive la implementación de DEC-03 (bloqueo optimista con reintentos), que es
el requisito central del trabajo: FR-07 y NFR-CONC-01.
"""
from __future__ import annotations

import random
import string
import time
from datetime import date, timedelta

import psycopg
from psycopg.rows import dict_row
from psycopg_pool import ConnectionPool

from config import (
    MAX_REINTENTOS,
    MINUTOS_RETENCION_PASAJERO,
    MODO_INSEGURO,
    RETARDO_INSEGURO_SEG,
)

ALFABETO_PNR = string.ascii_uppercase + string.digits


class SinCupo(Exception):
    """No hay capacidad vendible suficiente. Es un rechazo legítimo, no un error."""


class ColisionPersistente(Exception):
    """Se agotaron los reintentos por contención. El cliente puede reintentar."""


class NoEncontrado(Exception):
    pass


def crear_pool(dsn: str, max_size: int = 25) -> ConnectionPool:
    """Devuelve un pool, no una conexión única.

    Con una sola conexión compartida las peticiones se serializarían y la
    prueba de concurrencia de 5.6 no probaría nada: el cuello de botella sería
    el cliente, no el mecanismo de inventario. Cada petición toma su propia
    conexión, que es lo que hace que la carrera sea real.
    """
    return ConnectionPool(
        dsn, min_size=2, max_size=max_size,
        kwargs={"row_factory": dict_row}, open=True,
    )


def _codigo_pnr() -> str:
    return "".join(random.choices(ALFABETO_PNR, k=6))


# ---------------------------------------------------------------------------
#  DEC-07 — expiración de holds, capa perezosa
# ---------------------------------------------------------------------------
def expirar_holds(conn: psycopg.Connection) -> int:
    """Libera el inventario de las retenciones vencidas.

    Se invoca de forma oportunista antes de cada búsqueda (capa perezosa de
    DEC-07) para que un hold vencido no siga contando aunque el barrido
    programado todavía no haya pasado. Cumple NFR-CONC-02.
    """
    with conn.cursor() as cur:
        cur.execute(
            """
            WITH vencidas AS (
                SELECT id_reserva FROM reservas.reserva
                 WHERE estado = 'retenida' AND expira_en < now()
                 FOR UPDATE SKIP LOCKED
            ),
            devolucion AS (
                SELECT t.id_instancia, t.clase, count(*) AS n
                  FROM reservas.tramo t
                  JOIN reservas.itinerario i ON i.id_itinerario = t.id_itinerario
                 WHERE i.id_reserva IN (SELECT id_reserva FROM vencidas)
                 GROUP BY t.id_instancia, t.clase
            ),
            liberado AS (
                UPDATE reservas.instancia_vuelo iv
                   SET asientos_comprometidos_eco = iv.asientos_comprometidos_eco
                         - CASE WHEN d.clase = 'economica' THEN d.n ELSE 0 END,
                       asientos_comprometidos_bus = iv.asientos_comprometidos_bus
                         - CASE WHEN d.clase = 'business'  THEN d.n ELSE 0 END,
                       version = iv.version + 1
                  FROM devolucion d
                 WHERE iv.id_instancia = d.id_instancia
                RETURNING 1
            )
            UPDATE reservas.reserva
               SET estado = 'expirada', expira_en = NULL
             WHERE id_reserva IN (SELECT id_reserva FROM vencidas)
            RETURNING id_reserva
            """
        )
        expiradas = cur.fetchall()
        for fila in expiradas:
            cur.execute(
                """INSERT INTO reservas.historial_reserva
                   (id_reserva, estado_anterior, estado_nuevo, actor_tipo, motivo)
                   VALUES (%s, 'retenida', 'expirada', 'sistema', 'vencimiento del hold')""",
                (fila["id_reserva"],),
            )
    conn.commit()
    return len(expiradas)


# ---------------------------------------------------------------------------
#  FR-01 / FR-02 / FR-03 — búsqueda de disponibilidad
# ---------------------------------------------------------------------------
def buscar_vuelos(conn, origen: str, destino: str, fecha: date, clase: str) -> list[dict]:
    columna_disp = "eco" if clase == "economica" else "bus"
    with conn.cursor() as cur:
        cur.execute(
            f"""
            SELECT iv.id_instancia,
                   vp.numero_vuelo,
                   r.origen, ao.zona_horaria AS tz_origen,
                   r.destino, ad.zona_horaria AS tz_destino,
                   iv.fecha_operacion,
                   vp.hora_salida_local, vp.hora_llegada_local,
                   iv.capacidad_vendible_{columna_disp}
                     - iv.asientos_comprometidos_{columna_disp} AS asientos_disponibles,
                   t.id_tarifa, t.precio_base, t.moneda
              FROM reservas.instancia_vuelo iv
              JOIN reservas.vuelo_programado vp ON vp.id_vuelo_prog = iv.id_vuelo_prog
              JOIN reservas.ruta r  ON r.id_ruta = vp.id_ruta
              JOIN reservas.aeropuerto ao ON ao.codigo_iata = r.origen
              JOIN reservas.aeropuerto ad ON ad.codigo_iata = r.destino
              JOIN LATERAL (
                    SELECT id_tarifa, precio_base, moneda
                      FROM reservas.tarifa
                     WHERE id_vuelo_prog = vp.id_vuelo_prog
                       AND clase = %s::reservas.clase_servicio
                       AND (iv.fecha_operacion - CURRENT_DATE)
                           BETWEEN antelacion_min_dias AND antelacion_max_dias
                     ORDER BY precio_base
                     LIMIT 1
              ) t ON TRUE
             WHERE r.origen = %s AND r.destino = %s
               AND iv.fecha_operacion = %s
               AND iv.estado = 'programado'
             ORDER BY vp.hora_salida_local
            """,
            (clase, origen, destino, fecha),
        )
        return cur.fetchall()


# ---------------------------------------------------------------------------
#  DEC-03 — el corazón: comprometer inventario sin sobrevender
# ---------------------------------------------------------------------------
def _comprometer_seguro(cur, id_instancia: int, clase: str) -> bool:
    """UPDATE condicional: la comprobación de capacidad viaja DENTRO de la
    sentencia, así que el motor la evalúa con la fila bloqueada durante la
    escritura. No existe ventana entre comprobar y escribir.

    Devuelve True si comprometió, False si no había capacidad.
    """
    col = "eco" if clase == "economica" else "bus"
    cur.execute(
        f"""
        UPDATE reservas.instancia_vuelo
           SET asientos_comprometidos_{col} = asientos_comprometidos_{col} + 1,
               version = version + 1
         WHERE id_instancia = %s
           AND asientos_comprometidos_{col} + 1 <= capacidad_vendible_{col}
        """,
        (id_instancia,),
    )
    return cur.rowcount == 1


def _comprometer_inseguro(cur, id_instancia: int, clase: str) -> bool:
    """Patrón ingenuo leer → decidir en Python → escribir.

    Existe SÓLO para generar la evidencia comparativa de la sección 5.6.
    Entre el SELECT y el UPDATE hay una ventana donde otra transacción puede
    colarse: es exactamente la condición de carrera que DEC-03 elimina.
    """
    col = "eco" if clase == "economica" else "bus"
    cur.execute(
        f"""SELECT asientos_comprometidos_{col} AS comprometidos,
                   capacidad_vendible_{col}     AS vendible
              FROM reservas.instancia_vuelo WHERE id_instancia = %s""",
        (id_instancia,),
    )
    fila = cur.fetchone()
    if fila["comprometidos"] + 1 > fila["vendible"]:
        return False

    time.sleep(RETARDO_INSEGURO_SEG)  # ensancha la ventana para hacerla visible

    cur.execute(
        f"""UPDATE reservas.instancia_vuelo
               SET asientos_comprometidos_{col} = %s, version = version + 1
             WHERE id_instancia = %s""",
        (fila["comprometidos"] + 1, id_instancia),
    )
    return True


# ---------------------------------------------------------------------------
#  FR-04 / FR-07 — crear reserva
# ---------------------------------------------------------------------------
def crear_reserva(conn, id_pasajero: int, tramos: list[dict], id_agencia: int | None = None) -> dict:
    """Crea una reserva en estado `retenida`, comprometiendo el inventario de
    todos sus tramos de forma atómica (todo o nada).

    Implementa DEC-03 con reintentos y DEC-02 (hold temporal).
    """
    comprometer = _comprometer_inseguro if MODO_INSEGURO else _comprometer_seguro

    # Prevención de deadlock: si dos reservas multi-tramo tocan las mismas
    # instancias en orden distinto, se abrazan. Ordenar siempre igual lo evita.
    tramos = sorted(tramos, key=lambda t: t["id_instancia"])

    minutos = MINUTOS_RETENCION_PASAJERO
    if id_agencia is not None:
        with conn.cursor() as cur:
            cur.execute(
                "SELECT minutos_retencion FROM reservas.agencia WHERE id_agencia = %s",
                (id_agencia,),
            )
            fila = cur.fetchone()
            if fila is None:
                raise NoEncontrado(f"agencia {id_agencia} inexistente")
            minutos = fila["minutos_retencion"]  # FR-15

    ultimo_error: Exception | None = None

    for intento in range(1, MAX_REINTENTOS + 1):
        try:
            with conn.transaction():
                with conn.cursor() as cur:
                    for t in tramos:
                        if not comprometer(cur, t["id_instancia"], t["clase"]):
                            raise SinCupo(
                                f"sin capacidad en la instancia {t['id_instancia']} "
                                f"({t['clase']})"
                            )

                    codigo = _codigo_pnr()
                    cur.execute(
                        """INSERT INTO reservas.reserva
                             (codigo_reserva, id_pasajero, id_agencia, estado,
                              expira_en, monto_total, moneda)
                           VALUES (%s, %s, %s, 'retenida',
                                   now() + make_interval(mins => %s), 0, 'COP')
                           RETURNING id_reserva, codigo_reserva, expira_en""",
                        (codigo, id_pasajero, id_agencia, minutos),
                    )
                    reserva = cur.fetchone()

                    cur.execute(
                        """INSERT INTO reservas.itinerario (id_reserva, sentido, orden)
                           VALUES (%s, 'ida', 1) RETURNING id_itinerario""",
                        (reserva["id_reserva"],),
                    )
                    id_itin = cur.fetchone()["id_itinerario"]

                    total = 0
                    for orden, t in enumerate(tramos, start=1):
                        cur.execute(
                            """SELECT id_tarifa, precio_base FROM reservas.tarifa
                                WHERE id_vuelo_prog = (
                                        SELECT id_vuelo_prog FROM reservas.instancia_vuelo
                                         WHERE id_instancia = %s)
                                  AND clase = %s::reservas.clase_servicio
                                ORDER BY precio_base LIMIT 1""",
                            (t["id_instancia"], t["clase"]),
                        )
                        tarifa = cur.fetchone()
                        if tarifa is None:
                            raise NoEncontrado("no hay tarifa para esa instancia y clase")

                        cur.execute(
                            """INSERT INTO reservas.tramo
                                 (id_itinerario, id_instancia, orden, clase,
                                  id_tarifa, precio_aplicado)
                               VALUES (%s, %s, %s, %s::reservas.clase_servicio, %s, %s)""",
                            (id_itin, t["id_instancia"], orden, t["clase"],
                             tarifa["id_tarifa"], tarifa["precio_base"]),
                        )
                        total += tarifa["precio_base"]

                    cur.execute(
                        "UPDATE reservas.reserva SET monto_total = %s WHERE id_reserva = %s",
                        (total, reserva["id_reserva"]),
                    )
                    cur.execute(
                        """INSERT INTO reservas.historial_reserva
                             (id_reserva, estado_anterior, estado_nuevo, actor_tipo, motivo)
                           VALUES (%s, NULL, 'retenida', %s, 'creación de reserva')""",
                        (reserva["id_reserva"],
                         "agencia" if id_agencia else "pasajero"),
                    )

                    return {
                        "codigo_reserva": reserva["codigo_reserva"],
                        "estado": "retenida",
                        "expira_en": reserva["expira_en"],
                        "monto_total": total,
                        "moneda": "COP",
                        "intentos": intento,
                    }

        except SinCupo:
            raise  # rechazo legítimo: no se reintenta
        except psycopg.errors.SerializationFailure as exc:
            ultimo_error = exc
            time.sleep(0.01 * (2 ** intento) + random.random() * 0.01)
        except psycopg.errors.CheckViolation as exc:
            # La red de seguridad de la base actuó: el mecanismo aplicativo
            # dejó pasar algo. En modo seguro esto no debería ocurrir nunca.
            raise SinCupo("la restricción de la base impidió la sobreventa") from exc

    raise ColisionPersistente(f"contención tras {MAX_REINTENTOS} intentos: {ultimo_error}")


# ---------------------------------------------------------------------------
#  FR-11 — consultar reserva
# ---------------------------------------------------------------------------
def obtener_reserva(conn, codigo: str) -> dict:
    with conn.cursor() as cur:
        cur.execute(
            """SELECT r.codigo_reserva, r.estado, r.creada_en, r.expira_en,
                      r.monto_total, r.moneda,
                      p.nombre, p.apellido, a.nombre AS agencia
                 FROM reservas.reserva r
                 JOIN reservas.pasajero p ON p.id_pasajero = r.id_pasajero
                 LEFT JOIN reservas.agencia a ON a.id_agencia = r.id_agencia
                WHERE r.codigo_reserva = %s""",
            (codigo,),
        )
        cab = cur.fetchone()
        if cab is None:
            raise NoEncontrado(f"reserva {codigo} inexistente")

        cur.execute(
            """SELECT t.orden, t.clase, t.precio_aplicado, t.operado_por,
                      vp.numero_vuelo, r.origen, r.destino,
                      iv.fecha_operacion, vp.hora_salida_local, vp.hora_llegada_local,
                      ao.zona_horaria AS tz_origen, ad.zona_horaria AS tz_destino
                 FROM reservas.tramo t
                 JOIN reservas.itinerario i ON i.id_itinerario = t.id_itinerario
                 JOIN reservas.reserva rr   ON rr.id_reserva = i.id_reserva
                 JOIN reservas.instancia_vuelo iv ON iv.id_instancia = t.id_instancia
                 JOIN reservas.vuelo_programado vp ON vp.id_vuelo_prog = iv.id_vuelo_prog
                 JOIN reservas.ruta r ON r.id_ruta = vp.id_ruta
                 JOIN reservas.aeropuerto ao ON ao.codigo_iata = r.origen
                 JOIN reservas.aeropuerto ad ON ad.codigo_iata = r.destino
                WHERE rr.codigo_reserva = %s
                ORDER BY i.orden, t.orden""",
            (codigo,),
        )
        cab["tramos"] = cur.fetchall()

        cur.execute(
            """SELECT h.estado_anterior, h.estado_nuevo, h.actor_tipo, h.motivo, h.ocurrido_en
                 FROM reservas.historial_reserva h
                 JOIN reservas.reserva r ON r.id_reserva = h.id_reserva
                WHERE r.codigo_reserva = %s ORDER BY h.ocurrido_en""",
            (codigo,),
        )
        cab["historial"] = cur.fetchall()  # NFR-AUD-01
    return cab


# ---------------------------------------------------------------------------
#  FR-06 / DEC-06 — confirmar el pago (simula el webhook de la pasarela)
# ---------------------------------------------------------------------------
def confirmar_pago(conn, codigo: str, id_transaccion: str) -> dict:
    """Idempotente: el mismo id_transaccion procesado dos veces no confirma dos
    veces. Las pasarelas reintentan los webhooks (DEC-06).
    """
    with conn.transaction():
        with conn.cursor() as cur:
            cur.execute(
                """SELECT id_reserva, estado, monto_total
                     FROM reservas.reserva WHERE codigo_reserva = %s FOR UPDATE""",
                (codigo,),
            )
            res = cur.fetchone()
            if res is None:
                raise NoEncontrado(f"reserva {codigo} inexistente")

            cur.execute(
                "SELECT 1 FROM reservas.pago WHERE id_transaccion_pasarela = %s",
                (id_transaccion,),
            )
            if cur.fetchone():
                return {"codigo_reserva": codigo, "estado": res["estado"],
                        "idempotente": True}

            if res["estado"] != "retenida":
                # El hold ya venció: el pago llegó tarde. No se confirma; se
                # marca para reembolso. Es preferible devolver el dinero antes
                # que incumplir FR-07.
                cur.execute(
                    """INSERT INTO reservas.pago
                         (id_reserva, id_transaccion_pasarela, estado, monto)
                       VALUES (%s, %s, 'reembolsado', %s)""",
                    (res["id_reserva"], id_transaccion, res["monto_total"]),
                )
                return {"codigo_reserva": codigo, "estado": res["estado"],
                        "reembolso_disparado": True}

            cur.execute(
                """INSERT INTO reservas.pago
                     (id_reserva, id_transaccion_pasarela, estado, monto)
                   VALUES (%s, %s, 'aprobado', %s)""",
                (res["id_reserva"], id_transaccion, res["monto_total"]),
            )
            cur.execute(
                """UPDATE reservas.reserva
                      SET estado = 'confirmada', expira_en = NULL
                    WHERE id_reserva = %s""",
                (res["id_reserva"],),
            )
            cur.execute(
                """INSERT INTO reservas.historial_reserva
                     (id_reserva, estado_anterior, estado_nuevo, actor_tipo, motivo)
                   VALUES (%s, 'retenida', 'confirmada', 'sistema', 'pago acreditado')""",
                (res["id_reserva"],),
            )

            # FR-14: comisión de agencia, si la venta vino por ese canal
            cur.execute(
                """INSERT INTO reservas.comision (id_reserva, id_agencia, monto)
                   SELECT r.id_reserva, r.id_agencia,
                          ROUND(r.monto_total * a.porcentaje_comision / 100, 2)
                     FROM reservas.reserva r
                     JOIN reservas.agencia a ON a.id_agencia = r.id_agencia
                    WHERE r.id_reserva = %s
                   ON CONFLICT (id_reserva) DO NOTHING""",
                (res["id_reserva"],),
            )
    return {"codigo_reserva": codigo, "estado": "confirmada"}
