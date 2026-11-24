"""
Parcial 3 · publicación de eventos a Kinesis (decisión D2: cola en memoria + hilo con lotes).

Por qué así (R1, R2):
  - La request NO habla con Kinesis: sólo encola (microsegundos). Publicar nunca frena la API.
  - Un único hilo junta hasta 500 eventos o 200 ms y hace UN PutRecords (500 es el máximo por
    llamada). Bajo una ráfaga de 50 búsquedas simultáneas salen 1-2 llamadas en vez de 50.
  - PutRecords puede fallar a medias (p. ej. ProvisionedThroughputExceeded en un shard): se
    reintentan SÓLO los registros fallidos, con espera exponencial. Reintentar el lote entero
    duplicaría los que sí entraron (R2 exige exactamente 200 eventos para 200 búsquedas).
  - Búsquedas: perder una es aceptable, frenar al usuario no. Si la cola se llena, se descartan
    (y se cuentan). Reservas y cancelaciones: son transacciones de negocio; se encolan DESPUÉS del
    commit, esperando lugar en la cola, y se reintentan muchas más veces.

Límite conocido (se discute en la §5): si el proceso muere con eventos en la cola, esos eventos se
pierden. En producción se resuelve con un "transactional outbox": el evento se guarda en la misma
transacción que la reserva y un publicador lo lee de la base y lo marca como enviado.
"""
import datetime as dt
import json
import logging
import queue
import threading
import time
import uuid

log = logging.getLogger("eventos")
MAX_LOTE = 500                 # máximo de registros por PutRecords
ESPERA_LOTE_S = 0.2            # cuánto junta el hilo antes de mandar un lote incompleto
REINTENTOS = {False: 5, True: 50}   # búsqueda / evento crítico (reserva, cancelación)


def ahora_iso() -> str:
    """event_ts del contrato: UTC, YYYY-MM-DDTHH:MM:SSZ, el momento en que OCURRIÓ."""
    return dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def evento(tipo: str, **campos) -> dict:
    """Sobre común del contrato (EVENTS.md) + los campos propios del tipo."""
    return {"event_id": str(uuid.uuid4()), "event_type": tipo, "event_ts": ahora_iso(),
            "schema_version": 1, **campos}


class Publicador:
    def __init__(self, stream: str, region: str = "us-east-1", cliente=None, max_cola: int = 20000):
        import boto3
        self.stream = stream
        self.k = cliente or boto3.client("kinesis", region_name=region)
        self.cola: queue.Queue = queue.Queue(maxsize=max_cola)
        self.metricas = {"encolados": 0, "publicados": 0, "descartados": 0, "reintentos": 0, "lotes": 0}
        self._m = threading.Lock()

    def _sumar(self, clave, n=1):
        with self._m:
            self.metricas[clave] += n

    def publicar(self, ev: dict, clave_particion: str, critico: bool = False) -> bool:
        """Encola un evento. Nunca lanza excepción hacia el endpoint."""
        item = [clave_particion, json.dumps(ev, separators=(",", ":")).encode("utf-8"), critico, 0]
        try:
            if critico:
                self.cola.put(item, timeout=2)       # una reserva espera lugar (acotado)
            else:
                self.cola.put_nowait(item)           # una búsqueda no espera nunca
            self._sumar("encolados")
            return True
        except queue.Full:
            self._sumar("descartados")
            log.warning("cola llena: descarto %s %s", ev.get("event_type"), ev.get("event_id"))
            return False

    def iniciar(self):
        threading.Thread(target=self._bucle, daemon=True, name="publicador-kinesis").start()
        return self

    def _tomar_lote(self, pendientes: list) -> list:
        lote, pendientes[:] = pendientes[:MAX_LOTE], pendientes[MAX_LOTE:]
        limite = time.monotonic() + ESPERA_LOTE_S
        while len(lote) < MAX_LOTE:
            restante = limite - time.monotonic()
            try:
                if not lote:
                    lote.append(self.cola.get(timeout=1.0))     # sin nada pendiente: esperar
                    limite = time.monotonic() + ESPERA_LOTE_S
                elif restante > 0:
                    lote.append(self.cola.get(timeout=restante))
                else:
                    break
            except queue.Empty:
                if lote:
                    break
        return lote

    def _bucle(self):
        pendientes: list = []
        espera = 0.1
        while True:
            lote = self._tomar_lote(pendientes)
            if not lote:
                continue
            try:
                r = self.k.put_records(StreamName=self.stream,
                                       Records=[{"Data": d, "PartitionKey": pk} for pk, d, _, _ in lote])
                fallidos = [lote[i] for i, x in enumerate(r["Records"]) if "ErrorCode" in x]
            except Exception as ex:                  # stream inexistente, red, credenciales...
                log.warning("PutRecords falló entero (%s): reintento %d registros", ex, len(lote))
                fallidos = lote
            self._sumar("lotes")
            self._sumar("publicados", len(lote) - len(fallidos))
            for item in fallidos:
                item[3] += 1
                if item[3] > REINTENTOS[item[2]]:
                    self._sumar("descartados")
                    log.error("descarto un evento tras %d intentos", item[3])
                else:
                    pendientes.append(item)
                    self._sumar("reintentos")
            if fallidos:
                time.sleep(espera)
                espera = min(espera * 2, 5.0)
            else:
                espera = 0.1
