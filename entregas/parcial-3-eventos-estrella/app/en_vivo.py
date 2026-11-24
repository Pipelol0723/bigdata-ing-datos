"""
Parcial 3 · vista en vivo (decisión D3): un consumidor del stream dentro de la API.

Camino rápido (R3): un hilo lee el shard con GetRecords cada ~1 s y lleva contadores en memoria por
SEGUNDO de event_ts (cuándo ocurrió el evento, no cuándo llegó). GET /analytics/live suma los baldes
de los últimos `window` minutos. Por qué no Athena: consultar la estrella tarda segundos, cuesta por
consulta y la estrella se refresca cada ~10 min; la vista en vivo necesita lo de hace 3 segundos.

Detalles que importan:
  - Eventos viejos (el replay del harness trae fechas de 2025): su event_ts queda fuera de la
    ventana y no se cuentan, aunque hayan llegado recién.
  - Kinesis entrega "al menos una vez": se recuerdan los event_id del horizonte para no contar dos
    veces un reintento.
  - Sin enhanced fan-out (R11): comparte con Firehose el límite de 5 GetRecords/s y 2 MB/s del
    shard. Si Kinesis lo frena (ProvisionedThroughputExceeded), espera y sigue.
  - Si la API se reinicia, la memoria se pierde, pero al arrancar relee el stream desde hace
    HORIZONTE_MIN minutos (la retención es de 24 h): la vista se reconstruye sola.
  - Un solo proceso uvicorn (Dockerfile): con varios workers cada uno tendría sus propios contadores.
"""
import datetime as dt
import json
import logging
import threading
import time

log = logging.getLogger("en_vivo")
HORIZONTE_MIN = 60             # ventana máxima que acepta /analytics/live
TIPOS = {"search_performed": 0, "reservation_created": 1, "reservation_cancelled": 2}


class VistaEnVivo:
    def __init__(self, stream: str, region: str = "us-east-1", cliente=None):
        import boto3
        self.stream = stream
        self.k = cliente or boto3.client("kinesis", region_name=region)
        self._baldes: dict[int, list[int]] = {}     # segundo epoch -> [búsquedas, reservas, cancelaciones]
        self._vistos: dict[str, int] = {}           # event_id -> segundo (para no contar duplicados)
        self._lock = threading.Lock()
        self.estado = {"leyendo": False, "registros": 0, "ultimo_error": None}

    # ---------------------------------------------------------------------------- lectura
    def iniciar(self):
        threading.Thread(target=self._bucle, daemon=True, name="consumidor-en-vivo").start()
        return self

    def _iteradores(self) -> dict[str, str]:
        desde = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=HORIZONTE_MIN)
        its = {}
        for sh in self.k.list_shards(StreamName=self.stream)["Shards"]:
            if "EndingSequenceNumber" in sh.get("SequenceNumberRange", {}):
                continue                             # shard cerrado (después de un reshard)
            its[sh["ShardId"]] = self.k.get_shard_iterator(
                StreamName=self.stream, ShardId=sh["ShardId"],
                ShardIteratorType="AT_TIMESTAMP", Timestamp=desde)["ShardIterator"]
        return its

    def _bucle(self):
        its: dict[str, str] = {}
        espera_error = 2.0
        while True:
            try:
                if not its:
                    its = self._iteradores()
                    self.estado["leyendo"] = True
                atrasado = False
                for shard, it in list(its.items()):
                    r = self.k.get_records(ShardIterator=it, Limit=10000)
                    for rec in r["Records"]:
                        self._contar(rec["Data"])
                    self.estado["registros"] += len(r["Records"])
                    atrasado |= r.get("MillisBehindLatest", 0) > 0
                    if r.get("NextShardIterator"):
                        its[shard] = r["NextShardIterator"]
                    else:                            # shard cerrado: volver a listar
                        its = {}
                        break
                self._purgar()
                espera_error = 2.0
                time.sleep(0.2 if atrasado else 1.0)
            except Exception as ex:
                nombre = type(ex).__name__
                self.estado["ultimo_error"] = f"{nombre}: {ex}"[:300]
                if "ProvisionedThroughputExceeded" in nombre or "Throttl" in str(ex):
                    time.sleep(1.0)                 # el shard está saturado: esperar y seguir
                    continue
                its = {}                            # iterador vencido, stream borrado, red...
                self.estado["leyendo"] = False
                time.sleep(espera_error)
                espera_error = min(espera_error * 2, 30)

    def _contar(self, data: bytes):
        try:
            e = json.loads(data)
            tipo = TIPOS[e["event_type"]]
            seg = int(dt.datetime.strptime(e["event_ts"], "%Y-%m-%dT%H:%M:%SZ")
                      .replace(tzinfo=dt.timezone.utc).timestamp())
        except Exception:
            return                                   # evento mal formado: no es de la vista en vivo
        ahora = time.time()
        if seg < ahora - HORIZONTE_MIN * 60 or seg > ahora + 300:
            return                                   # fuera del horizonte (p. ej., el replay de 2025)
        with self._lock:
            if e.get("event_id") in self._vistos:
                return
            self._vistos[e.get("event_id")] = seg
            self._baldes.setdefault(seg, [0, 0, 0])[tipo] += 1

    def _purgar(self):
        corte = time.time() - HORIZONTE_MIN * 60 - 60
        with self._lock:
            for s in [s for s in self._baldes if s < corte]:
                del self._baldes[s]
            for eid in [k for k, s in self._vistos.items() if s < corte]:
                del self._vistos[eid]

    # ---------------------------------------------------------------------------- consulta
    def resumen(self, ventana_min: int) -> dict:
        ahora = time.time()
        desde = ahora - ventana_min * 60
        b = r = c = 0
        with self._lock:
            for seg, (nb, nr, nc) in self._baldes.items():
                if desde <= seg <= ahora + 300:
                    b, r, c = b + nb, r + nr, c + nc
        return {"window_minutes": ventana_min, "searches": b, "reservations": r, "cancellations": c,
                "conversion": round(r / b, 6) if b else 0.0}
