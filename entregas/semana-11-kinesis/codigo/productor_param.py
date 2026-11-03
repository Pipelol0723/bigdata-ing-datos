"""Ejercicio 1: productor parametrizable.

    python3 productor_param.py --stream S --tasa 200 --duracion 60 --claves 8 --sesgo 0
                               [--csv log.csv] [--resumen totales.json]

- Envía `tasa` registros por segundo durante `duracion` segundos, en lotes de máximo 500.
- `put_records` puede fallar PARCIALMENTE sin lanzar excepción: la respuesta trae
  FailedRecordCount y un ErrorCode por registro. Se reenvían sólo los fallidos, con backoff
  exponencial con jitter, hasta `--max-reintentos`.
- Cada evento lleva `n`, un contador por clave, que el Ejercicio 5 usa para verificar el orden.
- Imprime cada segundo: enviados, reintentados y fallidos.
"""
import argparse
import csv
import json
import random
import time
from datetime import datetime, timezone

from botocore.exceptions import ClientError

from comun import kinesis

LOTE_MAXIMO = 500  # límite de la API PutRecords


def parsear():
    ap = argparse.ArgumentParser()
    ap.add_argument("--stream", required=True)
    ap.add_argument("--tasa", type=int, default=100, help="registros por segundo")
    ap.add_argument("--duracion", type=int, default=60, help="segundos")
    ap.add_argument("--claves", type=int, default=8, help="partition keys distintas")
    ap.add_argument("--sesgo", type=float, default=0.0, help="probabilidad de usar siempre CT-001")
    ap.add_argument("--max-reintentos", type=int, default=8)
    ap.add_argument("--csv", help="log por segundo")
    ap.add_argument("--resumen", help="JSON con los totales y los registros enviados por clave")
    return ap.parse_args()


class Productor:
    def __init__(self, a):
        self.a = a
        self.claves = [f"CT-{i:03d}" for i in range(1, a.claves + 1)]
        self.n_por_clave = {k: 0 for k in self.claves}
        self.total = {"enviados": 0, "reintentados": 0, "fallidos": 0}

    def evento(self):
        clave = "CT-001" if random.random() < self.a.sesgo else random.choice(self.claves)
        self.n_por_clave[clave] += 1
        return {
            "contenedor_id": clave,
            "n": self.n_por_clave[clave],
            "temperatura": round(random.gauss(5, 3), 2),
            "humedad": round(random.uniform(40, 90), 1),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }

    def enviar_lote(self, eventos):
        """Envía hasta 500 registros; reintenta sólo los que fallaron. Devuelve (ok, reint, fallidos)."""
        pendientes = [{"Data": (json.dumps(e) + "\n").encode("utf-8"), "PartitionKey": e["contenedor_id"]}
                      for e in eventos]
        ok = reintentados = 0
        for intento in range(self.a.max_reintentos + 1):
            try:
                r = kinesis.put_records(StreamName=self.a.stream, Records=pendientes)
                fallidos_idx = [i for i, rec in enumerate(r["Records"]) if "ErrorCode" in rec]
            except ClientError as e:  # el lote entero rechazado (p. ej., throttling de la cuenta)
                if e.response["Error"]["Code"] not in ("ProvisionedThroughputExceededException",
                                                       "LimitExceededException"):
                    raise
                fallidos_idx = list(range(len(pendientes)))
            ok += len(pendientes) - len(fallidos_idx)
            if not fallidos_idx:
                return ok, reintentados, 0
            pendientes = [pendientes[i] for i in fallidos_idx]
            if intento == self.a.max_reintentos:
                break
            reintentados += len(pendientes)
            time.sleep(min(0.05 * 2 ** intento, 3.2) * random.uniform(0.5, 1.0))  # backoff con jitter
        return ok, reintentados, len(pendientes)

    def correr(self):
        log = csv.writer(open(self.a.csv, "w", newline="")) if self.a.csv else None
        if log:
            log.writerow(["segundo", "enviados", "reintentados", "fallidos"])
        inicio = time.monotonic()
        for segundo in range(1, self.a.duracion + 1):
            t0 = time.monotonic()
            eventos = [self.evento() for _ in range(self.a.tasa)]
            s = {"enviados": 0, "reintentados": 0, "fallidos": 0}
            for i in range(0, len(eventos), LOTE_MAXIMO):
                ok, rein, fall = self.enviar_lote(eventos[i:i + LOTE_MAXIMO])
                s["enviados"] += ok
                s["reintentados"] += rein
                s["fallidos"] += fall
            for k in s:
                self.total[k] += s[k]
            print(f"[{segundo:4d}s] enviados={s['enviados']} reintentados={s['reintentados']} "
                  f"fallidos={s['fallidos']}", flush=True)
            if log:
                log.writerow([segundo, s["enviados"], s["reintentados"], s["fallidos"]])
            time.sleep(max(0.0, 1.0 - (time.monotonic() - t0)))
        # si enviar un "segundo" de registros tarda más de un segundo, la tasa real queda por debajo
        real = time.monotonic() - inicio
        print(f"TOTAL enviados={self.total['enviados']} reintentados={self.total['reintentados']} "
              f"fallidos={self.total['fallidos']} en {real:.1f} s reales "
              f"(tasa real {self.total['enviados'] / real:.0f}/s)", flush=True)
        if self.a.resumen:
            json.dump({**self.total, "por_clave": self.n_por_clave}, open(self.a.resumen, "w"), indent=1)


if __name__ == "__main__":
    Productor(parsear()).correr()
