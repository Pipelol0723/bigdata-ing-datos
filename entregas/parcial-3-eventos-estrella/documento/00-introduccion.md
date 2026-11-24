# Introducción: el sistema y la trazabilidad

## Qué se construyó

El sistema de reservas de los parciales anteriores ahora **reacciona a los eventos a medida que
ocurren**:

1. **Eventos.** Cada búsqueda, reserva y cancelación de la API publica un evento en un stream de
   **Amazon Kinesis** de un shard. Se publica desde una cola en memoria, así que publicar no frena a
   quien busca.
2. **Camino rápido (segundos).** Un consumidor del stream dentro de la API cuenta los eventos de los
   últimos minutos por **cuándo ocurrieron**, y responde `GET /analytics/live`.
3. **Camino analítico (minutos).** **Amazon Data Firehose** lleva los mismos eventos a una landing
   zone en S3. Cada pocos minutos, **Athena** reconstruye con SQL un **modelo estrella** en Parquet:
   deduplica, ubica los eventos tardíos en su fecha y elige la versión de la ruta vigente ese día.
   Las tablas quedan registradas en el **Glue Data Catalog** y se consultan con Athena.

La API, la base y el frontend son los del parcial 2, en la misma EC2. El enunciado fija que lo más
barato que cumpla es lo mejor: cada pieza es la versión mínima que pasa su requisito, y todas se
midieron contra el harness del profesor, primero en local y después en AWS.

**Semilla asignada: 12345** (individual). Son las mismas 10 rutas del parcial 2; tres cambian de
categoría el 2025-02-01.

## Resultado

| Aspecto | Valor |
|---|---|
| Harness del profesor contra lo desplegado (24/11/2026) | **70,0 / 70,0**: 29 tests en 2 min 46 s, en la primera corrida completa |
| Antes de AWS, en local y gratis | 63 de 70 con los mismos tests (DuckDB en lugar de Athena, moto en lugar de Kinesis); R4 y R11 sólo se pueden medir en AWS |
| Replay sucio del harness | 20.509 registros → **19.912 eventos distintos**, todos en S3 a los 61 s; estrella reconstruida en 20 s |
| Costo de la sesión de AWS del parcial | ~US$0,10 (stream ~1 h, Firehose, Athena y la EC2 que ya existía) |
| Proyección mensual declarada | **US$10,76** (perfil de prueba); ~US$15 con EBS e IPv4; ~US$23 en producción 24×7 |

## Matriz de trazabilidad

Cada requisito, la pieza que lo cumple, dónde está y la medición del harness en AWS
(`evidencia/harness-2026-11-24_0632/report.md`).

| Req | Pts | Cómo se cumple | Dónde | Medición en AWS |
|---|---|---|---|---|
| R1 · un evento válido por acción | 7 | Sobre del contrato; `event_ts` del momento de la acción; partition key `session_id` (búsquedas) o `flight_id` (reservas); sin datos personales; la reserva publica después del commit | `app/main.py`, `app/eventos.py` | 30 eventos para 30 búsquedas; 4 para 3 reservas + 1 cancelación |
| R2 · sin pérdida, API rápida | 6 | Cola en memoria + hilo con `PutRecords` en lotes; se reintentan sólo los registros fallidos | `app/eventos.py` | 200 de 200 eventos; p95 **0,094 s** con 50 en paralelo |
| R3 · vista en vivo por tiempo del evento | 7 | Consumidor del stream en la API; baldes por segundo de `event_ts`; ignora lo viejo y lo duplicado | `app/en_vivo.py` | deltas exactos en **1,5 s**; el replay de 17.000 búsquedas viejas no se contó |
| R4 · todo llega a S3 en ≤ 5 min | 4 | Firehose: buffer de 60 s, gzip, un JSON por línea | `infra/01-bucket-stream-firehose.sh` | **19.912 / 19.912** en 61 s |
| R5 · tablas del contrato | 7 | CTAS de Athena a Parquet, registradas en Glue; `fact_search` particionada por `month`; `dim_date` 2023–2027 con festivos y puentes | `app/sql/10_dimensiones.sql`, `20_hechos.sql` | columnas, tipos, Parquet, particiones y las 1.826 filas de `dim_date` correctas |
| R6 · integridad | 5 | Claves subrogadas únicas; miembro `UNKNOWN` (-1) contra huérfanos; dedup por `event_id` | `app/sql/*.sql` | sin duplicados ni huérfanos |
| R7 · Q1, Q2, Q3, Q4, Q6, Q7, Q8 | 11 | Medidas aditivas (`bookings`, `cancellations`, `revenue_cents` con signo); dimensiones conformadas | `app/sql/20_hechos.sql` | las 7 preguntas iguales al oráculo |
| R8 · sucios y refresh ≤ 15 min | 6 | Rebuild completo idempotente; dedup; fecha por `event_ts`; `POST /admin/refresh-star` y su estado | `app/estrella.py` | refresh en **20 s**; conteos por evento y por fecha exactos |
| R9 · SCD tipo 2 | 8 | Versiones con `valid_from` / `valid_to` / `is_current`; *as-of join* por la fecha del evento | `app/sql/10_dimensiones.sql`, `20_hechos.sql` | versiones y Q5 correctas |
| R10 · poda y límite | 4 | Partición por mes en Parquet; workgroup `parcial3` con 1 GB por consulta | `infra/02-athena-y-dimensiones.sh` | un mes escaneó **3.798 B** contra 11.177 B (0,34) |
| R11 · stream mínimo | 3 | Provisionado, 1 shard, 24 h, sin EFO; se crea y se borra por script | `infra/01`, `infra/90` | `PROVISIONED`, 1 shard, 24 h, 0 consumidores |
| R12 · proyección | 2 | `cost_projection.yaml` con Kinesis, EC2, Firehose, S3, Athena y Glue | `cost_projection.yaml` | US$10,76 ≤ US$50 |

## Cómo está organizado el repositorio

| Carpeta | Contenido |
|---|---|
| `app/` | API (FastAPI): `main.py`, `eventos.py` (publicador), `en_vivo.py` (consumidor), `estrella.py` (refresh) y `sql/` (el ETL en SQL de Athena) |
| `infra/` | Scripts de CloudShell: `01`–`03` levantan la sesión (`10` los corre en orden), `20` corre el harness, `80` archiva la landing antes de la defensa, `90` baja el stream al terminar y `99` audita. Sólo leen salvo con `--confirmo` |
| `local/` | Pruebas a US$0 con el harness original: `sim_local.py` (estrella con DuckDB) y `sim_api.py` (API con moto) |
| `harness/` | El harness del profesor, intacto, más `config.yaml` (sin credenciales) |
| `evidencia/` | `report.md` de cada corrida en AWS |
| `cost_projection.yaml` | La proyección mensual (R12) |
