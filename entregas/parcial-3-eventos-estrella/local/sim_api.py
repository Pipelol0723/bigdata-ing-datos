"""
Prueba local de la API (R1, R2, R3) con los tests ORIGINALES del harness, contra:
  - la API real (app/main.py) corriendo con uvicorn en 127.0.0.1:8000,
  - PostgreSQL local (el descartable del P2, puerto 15499, base aerolinea3),
  - Kinesis simulado con moto (servidor en 127.0.0.1:5005).
La API y el harness hablan con moto por la variable AWS_ENDPOINT_URL (boto3 la respeta sola).

Uso (desde harness/):
    AWS_ENDPOINT_URL=http://127.0.0.1:5005 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
    PYTHONPATH=../local python -m pytest -p sim_api tests/test_1_stream.py -k "not landing"

Lo que NO prueba: R4 (moto no entrega de Kinesis a S3 como Firehose) ni la latencia real de AWS.
"""
import os
from pathlib import Path

AQUI = Path(__file__).resolve().parent


def pytest_configure(config):
    from harness import registry
    registry.CONFIG_OVERRIDE = {
        "team_id": "andres-cespedes (API local + Kinesis simulado)", "seed": 12345,
        "backend": {"base_url": os.environ.get("SIM_API_URL", "http://127.0.0.1:8000")},
        "aws": {"region": "us-east-1", "kinesis_stream": "airline-events",
                "raw_events_uri": "s3://sim/raw/events/", "athena_workgroup": "parcial3",
                "athena_database": "airline_star"},
        "cost_projection_file": str(AQUI.parent / "cost_projection.yaml")}
    os.environ.setdefault("HARNESS_REPORT", str(AQUI / "reportes" / "reporte-api-local"))
    (AQUI / "reportes").mkdir(exist_ok=True)
