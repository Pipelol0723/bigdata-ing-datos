# Parcial 3 — Eventos, vista en vivo y modelo estrella · plan

> Recibido el **12/11/2026**: `enunciado/parcial32026-2-EN.docx` y `enunciado/parcial3-harness-estudiantes.zip`.
> Desde el **19/11** también están en la tarea **"Parcial 3"** de Moodle (id 283333), subidos el 12/11 a las 09:20.
> **Son idénticos**: mismo tamaño y mismo SHA-256. La tarea cierra el **jue 26/11 a las 00:00**. Transcripción
> completa en [`enunciado.md`](enunciado.md); harness **intacto** en [`harness/`](harness/) (no editarlo:
> `thresholds.yaml`, `harness/` y `tests/` son del profesor).
>
> 🗓️ **Fechas (publicadas en Moodle el 19/11):** *"Theoretical Exam (November 26th Group 1 - November 27th
> Group 2) · Defense November 26th Group 1 - November 27th Group 2"*.
> - El alumno es del **g01** (confirmado el 19/11).
> - Con g01, el **examen teórico y la defensa son el jue 26/11**, y la entrega cierra el miércoles 25/11 a la medianoche.
> - Hay un **examen teórico** además de la defensa. El enunciado no lo mencionaba.
> **Estado:** leído y medido en local. Nada construido, **US$0** gastados.
> **Confirmado por el alumno el 12/11:** semilla **12345** (la del P2), parcial **individual** y el **P2 ya está
> calificado**. En el libro de Moodle la nota del P2 todavía no figura (19/11).

## 1. Qué pide, en una página

El sistema del Parcial 2 (API + PostgreSQL en la EC2) ahora **emite un evento por cada búsqueda, reserva y
cancelación** a Kinesis, y ese mismo flujo alimenta dos caminos con latencias distintas:

```
                          ┌─► consumidor ─► GET /analytics/live          camino rápido (segundos)
API (EC2) ─► Kinesis ─────┤
  1 shard                 └─► landing zone S3 (JSON) ─► ETL (refresh) ─► estrella Parquet  camino analítico (minutos)
                                                                          Glue Catalog + Athena
```

**Qué hay que construir:**

| Pieza | Detalle |
|---|---|
| **API** | La API del P2 sigue funcionando y suma cuatro endpoints: `POST /reservations/{id}/cancel`, `GET /analytics/live`, `POST /admin/refresh-star` y `GET /admin/refresh-status` |
| **Eventos** | `search_performed` (partition key `session_id`), `reservation_created` y `reservation_cancelled` (partition key `flight_id`). Sin datos personales |
| **Stream** | Provisioned, **1 shard**, retención ≤ 24 h, sin enhanced fan-out. Se crea y se borra con un script en cada sesión |
| **Landing zone** | Todos los eventos llegan a S3 **como JSON** (gzip permitido) en menos de 5 min |
| **Estrella** | `dim_date` enriquecida 2023–2027, `dim_route` **SCD tipo 2**, `dim_fare_class`, `fact_search` particionada por `month` y `fact_booking_event`. Todo Parquet, en el Glue Catalog |
| **ETL** | Deduplica por `event_id`, asigna la fecha por `event_ts`, hace el *as-of join* con la versión de la ruta, escribe Parquet y registra las particiones. **Terminar en ≤ 15 min** |
| **Athena** | Un workgroup con límite por consulta de **≤ 1 GB** |
| **Documento** | Sección 5: decisiones con requisito y pilar Well-Architected, bus matrix y costos. Sección 6: `report.md` final. Más el prompt log |

**Nota:** harness **70 %**, documento **15 %**, defensa **15 %**. La defensa es **eliminatoria por bloque**
(R1–R4, R5–R10, R11–R12): si un bloque no se defiende, se pierden también sus puntos del harness.
Hay una **entrega parcial** antes de construir: borrador de la sección 5, diagrama de la estrella con grano y
bus matrix, diagrama de arquitectura y primera proyección de costos.

## 2. Qué chequea el harness de verdad (leído en el código)

| Req | Pts | Lo que hace el test |
|---|---|---|
| R1 | 7 | Crea un vuelo (fecha 2031-03-10). Hace 30 búsquedas con `X-Session-Id`, 3 reservas y 1 cancelación, y lee el stream durante ≤ 15 s. Exige **exactamente** 30 + 4 eventos con ids únicos y `schema_version` 1. `event_ts` tiene que estar a < 300 s de ahora. Partition key: `session_id` en búsquedas y `flight_id` en reservas. `origin`, `destination` y `travel_date` iguales a la búsqueda. `fare_class` ECONOMY y `price_cents` int. Sin `passenger_name` |
| R2 | 6 | 200 búsquedas con 50 hilos: **p95 ≤ 1,0 s**, todas 200, y **exactamente 200 eventos** en el stream. Un reintento que duplique, falla |
| R3 | 7 | (a) Toma la línea base de `/analytics/live`, suma 10 búsquedas, 3 reservas y 1 cancelación, y espera ver esos deltas exactos en ≤ 10 s; `conversion` = reservas / búsquedas. (b) Inyecta el replay (eventos de 2025), espera 15 s y exige que la vista **no** los cuente (< 10 % de 17.000) |
| R4 | 4 | Busca en S3, bajo `raw_events_uri`, los objetos modificados desde el replay y extrae con una regex los `"event_id":"rp-..."`. Tienen que estar los 19.912 distintos en ≤ 300 s. Lee texto, y gzip lo descomprime solo |
| R5 | 7 | Columnas y tipos en Glue: `full_date`, `valid_from` y `valid_to` son **date**; los flags son **boolean**; cualquier entero vale. Todo Parquet. `fact_search` con partition keys **exactamente** `['month']` y ≥ 3 particiones registradas (o *partition projection*). `dim_date` comparada **fila por fila** contra el calendario esperado (1.826 días) |
| R6 | 5 | Claves únicas en las tres dims. **Ninguna fila de hecho huérfana**, contando **todas** las filas y no sólo las `rp-`. Una fila por `event_id` en cada hecho |
| R7 | 11 | Q1, Q2, Q3, Q4, Q6, Q7 y Q8 con su propio SQL, sólo sobre `event_id LIKE 'rp-%'`. Q2, Q3, Q6, Q7 y Q8 exigen igualdad **exacta**; Q1 y Q4 toleran 0,1 % |
| R8 | 6 | `POST /admin/refresh-star` y sondea `/admin/refresh-status` hasta SUCCEEDED (≤ 900 s). Luego conteos exactos de `rp-` en cada hecho y por `date_key` |
| R9 | 8 | `dim_route` igual a `route_category_history.csv`: mismas versiones, `valid_from`, `valid_to` exclusivo (la vigente con `9999-12-31`) e `is_current`. Q5 por categoría vigente en la fecha del evento |
| R10 | 4 | `COUNT(*)` del mes `2025-01` = búsquedas de enero del replay, **sin filtro `rp-`**. Escanear un mes ≤ 60 % de lo que escanean todos. El workgroup tiene `BytesScannedCutoffPerQuery` ≤ 1 GB |
| R11 | 3 | `describe_stream_summary`: PROVISIONED, ≤ 1 shard abierto, retención ≤ 24 h, 0 consumidores EFO |
| R12 | 2 | Suma los `line_items` del `cost_projection.yaml` y la compara con `min(1,5 × referencia, 50)`. Tiene que haber líneas de Kinesis, S3 y Athena |

**Orden y duración de una corrida:**
1. R1, R2 y R3 (en R3 se inyecta el replay: ~20.500 registros contra 1 shard, ≥ 21 s con reintentos).
2. Espera de hasta 5 min a que los eventos lleguen a S3.
3. Refresh de hasta 15 min.
4. R5 a R12.

Son **~25 min** como máximo.

## 3. Trampas encontradas leyendo el harness

1. **🔴 El replay de la defensa reutiliza los mismos `event_id` con otro contenido.**
   - El profesor corre con un `probe_salt` secreto, distinto de 0. Lo medí: 19.634 de 19.912 ids coinciden con los de nuestras corridas, pero cambian la fecha, la ruta y el precio. Además 278 cancelaciones son distintas.
   - Si en la landing zone o en la estrella quedan nuestras corridas de prueba, deduplicar por `event_id` mezcla las dos versiones. Fallan R6–R10 justo en la defensa.
   - **Hay que llegar a la defensa con la landing zone y la estrella vacías de `rp-`** (o con un procedimiento que lo garantice) y conviene que el refresh reconstruya todo desde cero.
   - Pasa lo mismo con R10, que cuenta enero **sin filtro `rp-`**.
2. **🔴 Firehose concatena los JSON sin salto de línea**, y los registros del replay no traen `\n` (los mete el harness, no nuestra API).
   - La regex de R4 los encuentra igual. Pero una tabla de Athena con JSON SerDe lee un solo registro por línea y **pierde eventos en silencio**.
   - Dos salidas: activar el delimitador de línea de Firehose (`AppendDelimiterToRecord`, **a verificar en el lab**) o que el ETL parsee JSON concatenado.
3. **Días de puente: el código manda.** `contract/STAR.md` dice *"plus the Monday/Friday that completes the three days"*. Pero el oráculo (`calendar_dates()`) y el enunciado (§4.3) marcan sólo:
   - el festivo, si cae viernes o lunes;
   - el sábado y el domingo de ese fin de semana.

   Hay que seguir el código, que es contra lo que se compara: 201 días en 2023–2027.
4. **Huérfanos de toda la tabla.** R6 cuenta todas las filas. Una búsqueda en la API de una ruta que no está en `routes_ref.csv` deja un `route_key` huérfano. Hace falta un **miembro "desconocido"** en `dim_route` o descartar esas búsquedas. R9 sólo revisa las rutas del histórico, así que el miembro extra no lo rompe.
5. **R2 en una t3.micro.** La publicación tiene que ser asíncrona (cola y lotes con `PutRecords`), reintentar **sólo** los registros que fallan y no duplicar. Hay que medir el p95 con 50 hilos: el P2 usa un solo proceso uvicorn con 40 hilos y un pool de 20 conexiones.
6. **Cinco lecturas por segundo por shard, compartidas.** Leen el mismo shard:
   - el consumidor de la vista en vivo (~1/s);
   - Firehose (~1/s);
   - el harness, que en R1/R2 llama a `get_records` **cada 0,25 s**.

   Va a haber `ProvisionedThroughputExceeded`: el consumidor necesita *backoff*. No se puede usar EFO (R11).
7. **Vista en vivo con un solo proceso.** Si la API corriera con varios workers, cada uno tendría sus propios contadores. Cuenta por `event_ts` e ignora el replay de 2025.
8. **R12 con la referencia del profesor.** En nuestra copia `reference_monthly_usd` es 60, así que el límite es US$50. La copia del profesor tendrá el valor real de su solución, que no conocemos. Es la misma trampa del P2: proyección austera y bien justificada.
9. **Workgroup.** Puede que el lab no deje modificar `primary`. Un workgroup propio con `BytesScannedCutoffPerQuery` (mínimo 10 MB) y su nombre en `config.yaml` lo resuelve.
10. **Tipos exactos.** `DATE` de verdad en `full_date` y `valid_*` (no string ni timestamp). `month` como string `YYYY-MM`. Un `CAST(... AS VARCHAR)` de las fechas tiene que empezar con `YYYY-MM-DD`.
11. **La landing zone es JSON.** Nada de conversión a Parquet en Firehose: R4 lee texto.
12. **Git ignora un archivo del harness.** `harness/airline_data/holidays_co.csv` cae en el `*.csv` del `.gitignore`. Hay que hacer `git add -f`, o un clon del repo rompe el harness. `ref/` se regenera.
13. **`report.md` y `report.json` del zip están viejos**: tienen otros pesos (R1 8, R7 8, R11 4…). Valen los de `thresholds.yaml`, que coinciden con el enunciado. Se sobrescriben en la primera corrida.
14. **El shard cobra cada hora que existe** (~US$0,015/h). Script de crear y borrar en cada sesión. La EC2 se reinicia sola con cada sesión del lab.
15. **Corridas largas en CloudShell.** Se desconecta si Chrome no está al frente (lección del P2): correr con `nohup` y leer el log.

## 4. Números del replay (medidos en local, US$0)

Con dos semillas de prueba (417, la del ejemplo, y 12345, la del P2). El tamaño no depende de la semilla.

| | Valor |
|---|---|
| Registros que el harness mete al stream | **20.509** (~4,8 MB, ~235 B cada uno) |
| Eventos distintos (lo que tiene que quedar en la estrella) | **19.912**: 17.000 búsquedas, 2.600 reservas y 312 cancelaciones |
| Duplicados en el replay | 597 |
| Búsquedas por mes | ~5.300 a 5.900 (2025-01, 02 y 03) |
| Rutas | 10 u 11, de las cuales **3 cambian de categoría** el 2025-02-01 |
| `dim_date` | 1.826 días, 91 festivos, 201 días de puente |

Es un volumen chico: cualquier ETL lo procesa en segundos. Lo que se evalúa es **la decisión y su justificación**, no la potencia.

**Con la semilla 12345** (archivos en `ref/`, generados el 12/11):
- Son las **mismas 10 rutas del P2**, así que los vuelos que ya tiene la base de la app sirven tal cual.
- Cambian de categoría el 2025-02-01 (y por eso tienen 2 versiones en `dim_route`):

| Ruta | Antes | Desde 2025-02-01 |
|---|---|---|
| CLO-CTG | TRUNK | REGIONAL |
| BOG-SMR | REGIONAL | TRUNK |
| BAQ-CUC | TRUNK | REGIONAL |

## 5. Decisiones que tenés que tomar (y defender)

Están las opciones y lo que pesa en cada una. **Todas tomadas por el alumno el 19/11**: ver la tabla
*Decididas*, más abajo.

| # | Decisión | Opciones |
|---|---|---|
| D1 | **Base** | El P2 ya está calificado: se puede **reutilizar** la EC2 `i-02fec020612e00ad5` (ya tiene Docker, la app y las rutas de la semilla 12345) o darla de baja y crear una nueva por script. El bucket `aerolinea-p2-…` y la base `airline_analytics` no los necesita el P3 (no hay que recargar la historia): **baja pendiente**, a confirmar |
| D2 | **Cómo publica la API** | Cola en memoria + hilo que manda lotes con `PutRecords`: no frena la API y las búsquedas son *fire and forget*. Las reservas, **después del commit** y con reintento. En producción, *transactional outbox* (se describe, no se implementa). La alternativa síncrona con boto3 en cada request es más simple pero arriesga R2 |
| D3 | **Vista en vivo** | Hilo consumidor dentro de la API con contadores en memoria por minuto de `event_ts` (barato, una pieza menos). O Lambda + DynamoDB (más piezas y costo, sobrevive a reinicios) |
| D4 | **Landing zone** | **Firehose**: gestionado, con `LabRole`, buffer de ~60 s, gzip y delimitador de línea. Cobra por registro redondeado a 5 KB: ~US$0,003 por replay. O un consumidor propio que escribe a S3 cada minuto: más código, checkpoints, otro lector del shard |
| D5 | **ETL de la estrella** | (a) **Athena CTAS / INSERT** orquestado desde la API: pago por byte escaneado y nada que desplegar, pero ojo, CTAS no pisa una ubicación con datos. (b) **Lambda + DuckDB/pandas**: segundos, pero hay que empaquetar y el lab tiene tope de 10 concurrentes. (c) **Glue job**: arranca en ~1 min, US$0,44/DPU-h con mínimo de 1 min; Python shell con 1/16 DPU, si el lab lo permite. El enunciado pide compararlas en costo por corrida y por mes, arranque contra los 15 min, crecimiento, operación e **idempotencia** |
| D6 | **Rebuild completo o incremental** | Completo: idempotente por construcción, resuelve tarde/desordenado solo y con 20 k eventos tarda segundos. Incremental: escala mejor, pero hay que manejar eventos tardíos en particiones viejas. Se relaciona con la trampa 1 |
| D7 | **Dimensiones** | Cargar `dim_date`, `dim_route` y `dim_fare_class` una vez, desde `ref/` y por script. Atributos extra que se puedan justificar: `month_name`, `year_month`, `is_current`… Miembro desconocido para las rutas fuera del catálogo |
| D8 | **Refresh periódico** | El enunciado habla de micro-lotes "cada pocos minutos". EventBridge Scheduler, un bucle en la API, o sólo a pedido más la justificación |
| D9 | **Perfil de costos** | Cuántas horas al mes existe el stream, si la EC2 está siempre prendida o sólo en pruebas, y qué va a `cost_projection.yaml` |

### Decididas por el alumno (19/11)

| # | Elección | Por qué (para la defensa) |
|---|---|---|
| D1 | **Reutilizar la EC2 del P2** (`i-02fec020612e00ad5`) y desplegar por SSM | El P3 es la continuación del mismo sistema y la API del P2 tiene que seguir andando. No se instala nada y el costo ya se conoce |
| D2 | **Cola en memoria + hilo que publica con `PutRecords` por lotes** (hasta 500 eventos o 200 ms) | La request sólo encola, así que publicar no frena la API (R2). Se reintentan sólo los registros fallidos: ni pérdida ni duplicado. Las búsquedas se pueden descartar si la cola se llena; las reservas se encolan **después del commit**. En producción, *transactional outbox* (se describe en la §5, no se implementa) |
| D3 | **Hilo consumidor dentro de la API**: `GetRecords` cada ~1 s y contadores en memoria por minuto de `event_ts` | Ninguna pieza nueva, US$0 y < 10 s (R3). Cuenta por tiempo del evento, no de llegada. Al arrancar relee los últimos 5 min con `AT_TIMESTAMP`. Un solo proceso uvicorn, para que no haya contadores divididos |
| D4 | **Amazon Data Firehose** → S3 (buffer 60 s, gzip, delimitador de línea) | Entrega gestionada, sin checkpoints propios (R4). Cuesta ~US$0,003 por replay. El `\n` se agrega con el procesador `AppendDelimiterToRecord`, que según la documentación no requiere dynamic partitioning. **Verificar en el lab** que los objetos salgan con un registro por línea (trampa 2) |
| D5 | **Athena SQL (CTAS)** orquestado por la API: un hilo corre ~8 consultas y `refresh-status` expone el estado | CTAS ya escribe Parquet y registra tablas y particiones en Glue (R5), sin nada nuevo que desplegar. Cuesta ~US$0,0004 por refresh, arranca en segundos (≪ 15 min, R8) y escala sola. Alternativas descartadas: Glue (~US$0,015–0,04 por corrida, ~1 min de arranque, desproporcionado para 5 MB), Lambda + DuckDB (empaquetar y registrar el catálogo a mano) y DuckDB en la EC2 (acopla el ETL a la web, 1 GB de RAM) |
| D6 | **Rebuild completo** de los hechos en cada refresh: borrar la ubicación en S3 y volver a hacer el CTAS | Idempotente por construcción: correrlo dos veces da lo mismo, y los tardíos y desordenados caen solos en su fecha (R8). Se pasaría a incremental si la landing supera ~10 GB o el refresh se acerca a los 15 min |
| D7 | **Miembro desconocido** en `dim_route` (`route_key = -1`, `UNKNOWN`, vigente siempre) | No se pierde ningún evento y no hay huérfanos (R6). Es la práctica estándar de Kimball, y R9 no la ve porque sólo revisa las rutas del histórico |
| D8 | **Bucle en la API cada 10 min que refresca sólo si llegaron objetos nuevos**, más el endpoint manual | Cumple el "cada pocos minutos" del enunciado. Cuesta ~US$0 sin tráfico (un LIST de S3); sin el control serían ~US$4,30/mes, por el mínimo de 10 MB por consulta de Athena. Sin piezas nuevas |
| D9 | **Costos: stream sólo durante las pruebas, EC2 24×7.** Kinesis ~200 h ≈ US$3, EC2 ≈ US$7,6, y Firehose, S3 y Athena centavos: **~US$11** | Sigue el ejemplo del enunciado (*"only while testing"*) y la lección del P2 (R12 falló con US$12,65 y pasó con US$8,36). IPv4 y EBS (~US$4,3) se explican en la narrativa, junto al escenario de producción 24×7 (~US$23) |
| D10 | **Workgroup propio `parcial3`** con límite de **1 GB** por consulta y su propia salida en S3 | No toca `primary` (otras prácticas, y puede que el lab no deje modificarlo). Tope de ~US$0,005 por consulta (R10) |
| D11 | **Dimensiones una sola vez, por script, en Athena SQL.** `ref/` sube a S3 y un CTAS lo pasa a Parquet. `dim_date` se genera con una secuencia de fechas más los festivos, y los puentes se calculan en SQL | Mismo lenguaje que D5. Se valida antes en local con DuckDB contra el oráculo (US$0). Son estáticas: se rehacen sólo si cambia `ref/` |
| D12 | **Antes de la defensa: archivar la landing** (`raw/` → `archive/<fecha>/`, fuera de `raw_events_uri`) **y reconstruir**. Script de sólo lectura salvo `--confirmo`; lo corre el alumno | Resuelve la trampa 1 sin borrar la evidencia de las pruebas. En la §5 se explica como "reinicio del entorno de prueba" |

**Arquitectura que resulta:**

```
API FastAPI (EC2 del P2, Docker)
 ├─ cola en memoria ─► PutRecords en lotes ─► Kinesis "airline-events" (1 shard, 24 h, sin EFO)
 │                                              ├─► hilo consumidor (en la API) ─► GET /analytics/live
 │                                              └─► Firehose (60 s, gzip, \n) ─► s3://…/raw/events/
 └─ refresh (endpoint + bucle cada 10 min si hay datos nuevos)
       └─► Athena (workgroup parcial3, ≤ 1 GB): raw JSON ─► dedup + as-of join ─► CTAS Parquet
                                                 ─► fact_search (por month), fact_booking_event
            dims una sola vez: dim_date, dim_route (SCD 2 + UNKNOWN), dim_fare_class
```

## Avance

**23/11 — F1 y F2 hechas en local, US$0** (detalle en [`local/README.md`](local/README.md)):

| Pieza | Dónde | Estado |
|---|---|---|
| SQL del ETL: tablas de entrada, dimensiones y hechos | `app/sql/00_base.sql`, `10_dimensiones.sql`, `20_hechos.sql` | ✅ R5–R10 en la simulación con DuckDB y los tests originales |
| Orquestación del refresh y bucle automático | `app/estrella.py` | ✅ (la usan la API, los scripts y la simulación) |
| Publicador de eventos | `app/eventos.py` | ✅ R1 y R2 con Kinesis simulado (moto) |
| Vista en vivo | `app/en_vivo.py` | ✅ R3 |
| API: cancelación, `/analytics/live`, refresh | `app/main.py`, `schema.sql` | ✅ (200, 409 y 404 de la cancelación probados a mano) |
| Proyección de costos | `cost_projection.yaml` | ✅ R12 (US$10,76) |
| Scripts de AWS | `infra/01` a `03` (levantar), `20` (harness), `80` (archivar), `90` (bajar el stream), `99` (auditar) | ✍️ escritos, falta correrlos en AWS |
| **Trampa 1, medida** | `local/reportes/reporte-sim-trampa1-*.md` | Sin archivar, el bloque de la estrella baja de 41 a **20** puntos |

**24/11 — F3 y F4 hechas: harness 70,0 / 70,0 en AWS, documento entregado en Moodle.**
- **AWS (sesión de ~1 h):**
  - Primera corrida completa del harness: 29 tests en 2 min 46 s (`evidencia/harness-2026-11-24_0632/`, también copiada en el bucket).
  - Hallazgo: un workgroup con *enforce* rechaza el CTAS con `external_location`; se pasó a `false`.
  - Stream y Firehose **dados de baja** al terminar, a pedido del alumno, y auditoría limpia.
- **Moodle:** "Enviado para calificar" el 24/11 a la 01:44, con 3 archivos: el PDF de 21 páginas, `Parcial3-repositorio.zip` y `report.md`.
- **GitHub:** commits `b3b5ef9` y `3e08319`.

### ✅ Checklist del jueves 26/11 (examen teórico y defensa, g01)

1. Abrir el Learner Lab y esperar el verde. Anotar el presupuesto (el 24/11 marcaba US$21,2).
2. En CloudShell: si `~/p3` no está, subir `p3.tgz` con `bash infra/empaquetar.sh`. Después correr `bash ~/p3/infra/10-levantar-sesion.sh`, que recrea el stream y Firehose y redespliega la API (~3 min).
3. **`bash ~/p3/infra/80-archivar-landing.sh --confirmo`** (trampa 1): mueve `raw/events/` a `archive/` y reconstruye la estrella con la landing vacía.
4. **NO volver a correr nuestro harness después del paso 3**: metería otra vez nuestros `rp-` en la landing. Para mostrar que todo anda alcanza con la API, `/analytics/live` y una consulta en Athena.
5. Pasarle al profesor la IP del día (`ip_ec2` en `00-comun.sh`) para su `config.yaml`: el stream, la landing, la base y el workgroup no cambian.
6. Al terminar: `bash ~/p3/infra/90-bajar-stream.sh --confirmo` y End Lab.

**Ejecutado el 26/11 a la mañana (09:15–09:30 hora local):**
- Lab arrancado (US$21,4 al abrir). `10-levantar-sesion.sh` y `31` OK. IP del día: **54.227.170.70**.
- **Harness 70,0/70,0** a las 14:21 UTC: 29 passed en 2 min 40 s. Evidencia en `evidencia/harness-2026-11-26_1424/`.
- Después, **`80-archivar-landing.sh --confirmo`**: la landing quedó en 0 objetos (movida a `archive/20261126T1424/`). La estrella se reconstruyó vacía (refresh SUCCEEDED a las 14:24:47 UTC, 1.296 bytes escaneados).
- **Si se vuelve a correr nuestro harness delante del profe, hay que repetir el 80 antes de que él corra el suyo.**
- Se agregaron P3-9 (Q2), P3-10 (Q3) y P3-11 (Q4) a las consultas guardadas (`31`).
- Se corrió `30-demo.sh`:
  - vista en vivo en 2 s;
  - estrella con 3 filas de hoy (BGA-BOG, neto 3.500,00).
  - Son eventos que no empiezan con `rp-`, así que el replay del profe no choca con ellos.

## 6. Fases

| Fase | Qué | Dónde | Costo |
|---|---|---|---|
| **F0** | Decisiones D1–D9 y **entrega parcial**: borrador de la §5, estrella con grano, bus matrix, arquitectura y primera proyección | Local | US$0 |
| **F1** | `dim_*` desde `ref/` y ETL contra una landing simulada: el replay se genera en local con `make_events()` y se escribe como lo dejaría Firehose. Validar contra `StarTruth` (el oráculo del harness) con DuckDB | Local | US$0 |
| **F2** | API: cancelación, publicación, consumidor en vivo y refresh. Kinesis simulado con moto, como en el taller | Local | US$0 |
| **F3** | Sesión de AWS: stream, landing, workgroup, tablas, despliegue, harness completo | AWS | ~US$1 |
| **F4** | Documento final, `report.md` y prompt log. **Borrar el stream** al cerrar cada sesión | Local | US$0 |
| **F5** | Defensa: vaciar `rp-` de la landing y la estrella (trampa 1), crear el stream y verificar | AWS | centavos |

**Calendario propuesto (6 días, a confirmar con el alumno):**

| Día | Fase |
|---|---|
| jue 19 – vie 20 | F0 (decisiones D1–D9) y F1 (dimensiones y ETL en local contra el oráculo) |
| sáb 21 – dom 22 | F2 (API en local: cancelación, publicación, vista en vivo, refresh) |
| lun 23 | F3: primera sesión de AWS, despliegue y harness completo |
| mar 24 | Correcciones, segunda corrida del harness, documento |
| **mié 25** | Documento final, `report.md` y prompt log. **Subir a Moodle antes de las 23:59** |
| **jue 26** | **Examen teórico y defensa (g01).** Antes de la defensa: vaciar `rp-` (trampa 1), crear el stream y verificar |

Moodle no muestra una fecha para la "entrega parcial" (borrador de la §5): hay que preguntarla en clase.
El **Capstone** (cierra sáb 28/11) corre en paralelo. Es ~1 h de lab con los scripts preparados y va
mejor el 27 o el 28, después de la defensa.

**Costo estimado del parcial en el Learner Lab: menos de US$2.**
- Shard: US$0,015/h; 20 h de pruebas ≈ US$0,30.
- Firehose, S3 y Athena: centavos.
- La EC2 ya cobra igual por el P2.

## 7. Estructura de esta carpeta

```
parcial-3-eventos-estrella/
├── PLAN.md          ← este archivo
├── enunciado.md     ← transcripción del .docx (en inglés, sin cambios)
├── enunciado/       ← originales recibidos (.docx y .zip; el zip no va a git)
├── ref/             ← generado con --seed 12345 (CSV: no va a git, se regenera con el comando de abajo)
└── harness/         ← harness del profesor, intacto (config.yaml se crea cuando exista la infraestructura)
```

```
cd harness && python -m airline_data.generate_p3 --seed 12345 --out ../ref
```
Lo que se construya va a ir en `app/`, `infra/`, `etl/`, `local/`, `documento/` y `entrega/`, como en el P2.

## 8. Preguntas abiertas

- [x] Semilla: **12345** · individual · P2 calificado (respondido el 12/11).
- [x] Fechas (Moodle, 19/11): examen teórico y defensa el **26/11 para el g01** y el 27/11 para el g02.
- [x] El alumno es del **g01**: examen teórico y defensa el **jue 26/11**.
- [ ] Fecha de la entrega parcial (borrador de la §5): no figura en Moodle. Preguntar en clase.
- [ ] ¿Qué cubre el **examen teórico**? El enunciado no lo menciona.
- [ ] Idioma del documento: el P2 fue en español.
- [x] D1–D12 (§5): decididas el 19/11.
- [ ] Atributos extra de las dimensiones, más allá del contrato. Se proponen en el borrador de la §5.
