# Parcial 3 · pruebas locales (US$0) con el harness ORIGINAL

Las dos pruebas usan los tests del profesor **sin modificarlos**. Les cambian el "AWS" por medio de
la costura que trae el propio harness (`harness/harness/registry.py`) o de la variable
`AWS_ENDPOINT_URL`.

## 1 · Camino analítico (R5–R10, R12): `sim_local.py`

| En AWS | En la simulación |
|---|---|
| Firehose → `s3://…/raw/events/` | `.gz` con un JSON por línea en `C:\Users\pipel\datos-parcial3\landing` |
| Athena | DuckDB, ejecutando **el mismo SQL** de `app/sql` (3 traducciones de dialecto: `CREATE TABLE … WITH (…) AS`, `sequence` y `day_of_week`) |
| Glue (esquema) | `DESCRIBE` de DuckDB con los nombres de tipo de Athena |
| `POST /admin/refresh-star` | servidor HTTP mínimo con **la misma clase `Refresco`** de `app/estrella.py` |

```bash
cd harness
PYTHONPATH=../local python -m pytest -p sim_local tests/test_2_star.py tests/test_3_cost.py -k "not stream_is_minimal"
```

**Resultado del 23/11:** 23 de 23 tests, con R5, R6, R7, R8, R9, R10 y R12 en verde
(`reportes/reporte-sim.md`). R10 es parcial: los bytes escaneados se estiman, porque sólo se miden
en Athena.

**Trampa 1, medida** (el replay del profesor usa los mismos `event_id` con otro contenido):

```bash
SIM_LIMPIAR=0 SIM_SALT=7 HARNESS_REPORT=../local/reportes/reporte-sim-trampa1-sin-archivar PYTHONPATH=../local python -m pytest -p sim_local tests/test_2_star.py
SIM_LIMPIAR=1 SIM_SALT=7 HARNESS_REPORT=../local/reportes/reporte-sim-trampa1-archivada  PYTHONPATH=../local python -m pytest -p sim_local tests/test_2_star.py
```

| | Bloque de la estrella (R5–R10) |
|---|---|
| Sin archivar la landing | **20 / 41**: R7 = 0, R8 = 2/6, R9 = 4/8, R10 = 2/4 |
| Con la landing archivada (D12) | **41 / 41** |

## 2 · API (R1–R3): `sim_api.py`

Usa la API real (`app/main.py`), PostgreSQL local y Kinesis simulado con moto.

```powershell
$bin = "C:\Program Files\PostgreSQL\17\bin"; $dir = "C:\Users\pipel\pg-parcial2"
& "$bin\pg_ctl.exe" -D $dir -o "-p 15499 -c listen_addresses=localhost" -l "$dir\servidor.log" start
& "$bin\createdb.exe" -h localhost -p 15499 -U app aerolinea3        # sólo la primera vez
```

```bash
python -m moto.server -H 127.0.0.1 -p 5005 &
export AWS_ENDPOINT_URL=http://127.0.0.1:5005 AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test AWS_DEFAULT_REGION=us-east-1
python -c "import boto3; boto3.client('kinesis').create_stream(StreamName='airline-events', ShardCount=1)"
cd app && DATABASE_URL=postgresql://app@localhost:15499/aerolinea3 STAR_BUCKET=sim REFRESH_CADA_MIN=0 \
    python -m uvicorn main:app --host 127.0.0.1 --port 8000 &
cd harness && PYTHONPATH=../local python -m pytest -p sim_api tests/test_1_stream.py -k "not landing"
```

**Resultado del 23/11:** R1, R2 y R3 en verde (`reportes/reporte-api-local.md`):
- 30 eventos para 30 búsquedas y 4 para 3 reservas + 1 cancelación;
- ráfaga de 200 con p95 de 8 ms y 200 eventos (en local: la latencia real se mide en AWS);
- vista en vivo actualizada en 1,4 s; tras el replay de 17.000 búsquedas viejas, cuenta sólo las nuevas.

A mano: cancelar da 200 la primera vez, 409 la segunda y 404 si la reserva no existe. El asiento
vuelve a quedar libre.

**Sólo se puede verificar en AWS:** R4 (que Firehose entregue a S3, con el `\n`) y R11 (la
configuración del stream).

Apagar: `pg_ctl -D C:\Users\pipel\pg-parcial2 stop`, cortar uvicorn y moto.
