# Parcial 3 — Guía de sustentación

**Jueves 26/11 · g01 · examen teórico y defensa.** La defensa es **eliminatoria por bloque**:
R1–R4 (eventos y vista en vivo), R5–R10 (estrella) y R11–R12 (costo y arquitectura). Si un bloque no
se sostiene, se pierden también sus puntos del harness.

## 1. Antes de entrar (~15 min)

| # | Paso | Dónde | Tiempo |
|---|---|---|---|
| 1 | Abrir el Learner Lab → **Start Lab** → esperar el verde. Anotar el presupuesto (el 25/11 marcaba US$21,3) | Canvas, curso 179973 | 1-2 min |
| 2 | Botón **AWS** → abrir CloudShell (`us-east-1`) | consola | 1 min |
| 3 | Subir el `p3.tgz` **nuevo**: lo arma `bash infra/empaquetar.sh` y queda en `C:\Users\pipel\datos-parcial3\p3.tgz`. Antes, `rm -f ~/p3.tgz` (CloudShell no pisa un archivo con el mismo nombre). Después: `rm -rf ~/p3 && mkdir ~/p3 && tar xzf ~/p3.tgz -C ~/p3 && cd ~/p3` | CloudShell, Acciones → Cargar archivo | 1 min |
| 4 | `bash infra/10-levantar-sesion.sh && bash infra/31-consultas-guardadas.sh`: recrea el stream y Firehose, redespliega la API en la EC2 (vuelve sola con IP nueva) y guarda en Athena las consultas de la demo (P3-1 a P3-8; si ya existen, no las duplica) | CloudShell | 3-4 min |
| 5 | **`bash infra/80-archivar-landing.sh --confirmo`**: mueve `raw/events/` a `archive/` y reconstruye la estrella vacía. **Imprescindible** (trampa 1, §4) | CloudShell | 30 s |
| 6 | Opcional: `bash infra/30-demo.sh` para probar todo de punta a punta con tráfico real. No afecta al harness del profesor | CloudShell | 3 min |
| 7 | Anotar la **IP** que imprimió el paso 4. El profesor la pone en su `config.yaml`; el resto de los valores no cambia | — | — |

⚠️ **No correr nuestro harness después del paso 5.** Volvería a meter nuestros `rp-` en la landing.

**Valores para el `config.yaml` del profesor:**

```yaml
seed: 12345
backend: {base_url: "http://<IP>:8000"}
aws:
  region: us-east-1
  kinesis_stream: airline-events
  raw_events_uri: "s3://aerolinea-p3-936980625651/raw/events/"
  athena_workgroup: parcial3
  athena_database: airline_star
  athena_output: "s3://aerolinea-p3-936980625651/athena-results/"
```

**Al terminar:** `bash ~/p3/infra/90-bajar-stream.sh --confirmo` y **End Lab**.

## 2. El sistema en un minuto (para arrancar)

> La API del parcial 2 ahora **publica un evento por cada búsqueda, reserva y cancelación** en un
> stream de **Kinesis** de un shard. Publica desde una **cola en memoria** con un hilo que manda
> lotes, así que publicar no frena al usuario: p95 de 0,094 s con 50 búsquedas en paralelo.
>
> Del stream salen **dos caminos**:
>
> - **Rápido:** un consumidor dentro de la API cuenta los eventos por **cuándo ocurrieron** y responde
>   `/analytics/live` en 1,5 s.
>
> - **Analítico:** **Firehose** deja los eventos en S3 como JSON, uno por línea. Cada 10 minutos, y
>   sólo si llegó algo, **Athena reconstruye con SQL un modelo estrella en Parquet**. Deduplica,
>   pone cada evento en su fecha y elige la versión de la ruta vigente ese día (**SCD tipo 2**).
>
> El harness dio **70 / 70 en AWS**. Antes lo validé en local, gratis, con el mismo SQL en DuckDB.

## 3. Guion de la demo (5-8 min)

1. **Arquitectura:** el diagrama de la §5.0 del documento.
2. **Camino rápido:** `bash infra/30-demo.sh`. Muestra la vista en vivo subiendo en segundos y el
   `409` al cancelar dos veces.
3. **Camino analítico:** el mismo script espera a Firehose, pide el refresh y consulta la estrella:
   2 bookings, 1 cancellation y neto de +350.000.
4. **La estrella en Athena** (workgroup `parcial3`, base `airline_star`), después del harness del profesor.
   Están en la pestaña **Consultas guardadas**: P3-1 (SCD 2), P3-2 (Q5), P3-3 (conversión), P3-4 (Q1),
   P3-5 (festivos y puentes), P3-6 (`dim_date`), P3-7 (R10: mirar "Datos escaneados") y P3-8 (grano).
   Las principales:

```sql
-- SCD 2: tres rutas con dos versiones
SELECT route, route_category, valid_from, valid_to, is_current
FROM dim_route ORDER BY route, valid_from;

-- Q5: ingreso por la categoría vigente el día del evento
SELECT r.route_category, d.year, d.month, SUM(f.revenue_cents) / 100 AS ingreso
FROM fact_booking_event f
JOIN dim_route r ON f.route_key = r.route_key
JOIN dim_date d ON f.date_key = d.date_key
GROUP BY 1, 2, 3 ORDER BY 2, 3, 1;

-- R10: un mes escanea ~1/3 (mirar "Datos escaneados")
SELECT COUNT(*) FROM fact_search WHERE month = '2025-01';

-- dim_date: festivos y puentes de enero de 2025
SELECT full_date, weekday_name, holiday_name, is_long_weekend
FROM dim_date WHERE year = 2025 AND month = 1 AND (is_holiday OR is_long_weekend);
```

5. **El código:** `app/sql/20_hechos.sql` (dedup + *as-of join*), `app/eventos.py` (lotes y
   reintento de los fallidos) y `app/en_vivo.py` (baldes por `event_ts`).

## 4. Defensa por bloque

### Bloque R1–R4: eventos y vista en vivo

| Pregunta probable | Respuesta corta |
|---|---|
| ¿Por qué las búsquedas encajan en Kinesis y las reservas son delicadas? | Las búsquedas son muchas y baratas: perder una no importa; frenar al usuario, sí. Las reservas son transacciones: un evento perdido es ingreso que falta en la analítica, y uno de más es ingreso inventado. Por eso se publican **después del commit** y se reintentan más |
| ¿Cómo no perder una reserva entre la base y el stream? | **Transactional outbox**: el evento se guarda en una tabla `outbox` en la **misma transacción** que la reserva; un publicador la lee, publica y marca. Puede duplicar, nunca perder, y los consumidores deduplican por `event_id`. Se describe, no se implementó (lo pide así el enunciado) |
| ¿Qué pasa si la API muere con eventos en la cola? | Se pierden: es el límite de la cola en memoria. El outbox es la solución |
| ¿Por qué `PutRecords` en lotes y no `PutRecord`? | Una llamada por cada 500 eventos o 200 ms: menos latencia y menos llamadas. Si falla una parte, se reintentan **sólo los fallidos**; reintentar todo duplicaría (R2 exige exactamente 200) |
| ¿Por qué esas partition keys? | `session_id` reparte las búsquedas. `flight_id` mantiene **en orden** los eventos de un mismo vuelo, porque caen en el mismo shard |
| ¿Por qué la vista en vivo no usa Athena? | Athena tarda segundos, cobra un mínimo de 10 MB por consulta y la estrella se refresca cada 10 min. La vista necesita lo de hace 3 s |
| ¿Por qué cuenta por `event_ts`? | Para que un evento viejo que llega ahora (el replay de 2025) no infle "lo de los últimos 5 minutos". Medido: el replay de 17.000 búsquedas viejas no se contó |
| ¿Y si la API se reinicia? | Pierde los contadores, pero relee el stream de los últimos 60 min (la retención es de 24 h) |
| ¿Por qué Firehose y no un consumidor propio? | Entrega gestionada, sin checkpoints ni reintentos propios; ~US$0,003 por replay. Medido: 19.912 de 19.912 eventos en S3 en 61 s |
| ¿Por qué el salto de línea? | Firehose pega los JSON (`{…}{…}`) y el SerDe JSON de Athena lee uno por línea: perdería eventos en silencio. Se usa el procesador `AppendDelimiterToRecord` |
| ¿Cuántos lectores tiene el shard? | Dos: el consumidor de la API y Firehose. Comparten 5 `GetRecords`/s y 2 MB/s. Sin enhanced fan-out (R11) |

### Bloque R5–R10: el modelo estrella

| Pregunta probable | Respuesta corta |
|---|---|
| ¿Cuál es el grano de cada hecho? | `fact_search`: un evento de búsqueda. `fact_booking_event`: un evento de reserva (creación **o** cancelación) |
| ¿Por qué la cancelación es una fila con ingreso negativo? | Es un **hecho de transacción** con medidas **aditivas**: el ingreso neto es `SUM(revenue_cents)` en cualquier corte, sin cruzar la cancelación con su reserva |
| ¿Qué es una dimensión conformada? | La misma dimensión, con las mismas claves, compartida por varios hechos. `dim_date` y `dim_route` sirven a los dos: eso permite Q6 (conversión) y Q7 (festivos) |
| ¿Por qué SCD tipo 2 y no tipo 1? | Q5 pide la categoría **vigente el día del evento**. Una tipo 1 reescribe la historia: enero de 2025 quedaría **+38,8 %** REGIONAL y **−42,5 %** TRUNK (calculado con el oráculo) |
| ¿Cómo se elige la versión? | *As-of join* por la **fecha del evento**: `valid_from <= fecha < valid_to`. Un evento tardío usa la versión de su fecha, no la actual |
| ¿Cómo se deduplica? | `row_number() OVER (PARTITION BY event_id)` y se queda la copia 1. La landing es *append-only* y Kinesis entrega "al menos una vez" |
| ¿Tardíos y desordenados? | `date_key` y `month` salen de `event_ts`, y el refresh es un **rebuild completo**: el orden de llegada no importa |
| ¿Por qué Athena CTAS y no Glue o Lambda? | Para 5 MB: ~US$0,0001 por refresh contra ~US$0,015–0,03 de Glue. Arranca en segundos y CTAS escribe Parquet y registra las particiones solo. Glue convendría con GB, o con lógica que no se pueda expresar en SQL |
| ¿Por qué rebuild y no incremental? | Es idempotente por construcción y resuelve solo los tardíos. Se pasaría a incremental (Iceberg + `MERGE`) con más de ~10 GB |
| ¿Por qué no refrescar por evento? | Miles de archivos chicos (*small files*), el mínimo de 10 MB por consulta en cada uno, y la deduplicación necesita ver el conjunto |
| ¿Qué es `UNKNOWN` (-1)? | El **miembro desconocido**: un evento con una ruta fuera del catálogo se conserva sin quedar huérfano (R6) |
| ¿Cómo se marca un día de puente? | El festivo que cae viernes o lunes, más el sábado y el domingo: `lag`/`lead` sobre la serie de días. `STAR.md` dice otra cosa; se siguió el código del oráculo |
| ¿Por qué particionar por `month` y no por día? | Las consultas filtran por mes, y por día habría ~90 particiones de pocos KB cada una. Medido: un mes escanea 0,34 del total |
| La trampa del replay | Los `event_id` del profesor coinciden con los nuestros, con otro contenido. Por eso se archiva la landing antes: sin archivar, la estrella pasa de 41 a **20** puntos (medido) |

### Bloque R11–R12: costo y arquitectura

| Pregunta probable | Respuesta corta |
|---|---|
| ¿Por qué un shard provisionado? | Un shard da 1.000 registros/s y 1 MB/s de escritura; sobra. On-demand cobra por hora de stream y por GB, y a este volumen sale más caro |
| ¿Qué existe siempre y qué no? | Siempre: la EC2, S3 y el catálogo. **Sólo en pruebas: el stream** (US$0,015/h exista o no tráfico), que se crea y se borra por script |
| ¿Cuánto cuesta? | Declarado: **US$10,76/mes** (Kinesis 3,01 + EC2 7,59 + el resto centavos). Con EBS e IPv4, ~US$15. En producción 24×7, ~US$23 |
| ¿Por qué el workgroup tiene enforce = false? | Con enforce, Athena rechaza el CTAS con `external_location` (lo encontramos en AWS). El límite de 1 GB por consulta se aplica igual |
| Pilares de Well-Architected | REL: outbox, dedup, rebuild idempotente. PERF: cola y lotes, particiones. COST: shard sólo en pruebas, Athena por consulta. SUS: nada prendido sin uso, Parquet + gzip. SEC: sin datos personales en los eventos, `LabRole`, bucket privado. OE: scripts idempotentes, harness local |

## 5. Cambios en vivo (el profesor puede pedirlos)

Regla para responder: primero **el camino** (rápido o analítico), después **el grano**, después **la
tabla** y recién al final **los tests**.

**Agregar una medida al hecho**, por ejemplo la anticipación de la compra:

- En CloudShell, editar `~/p3/app/sql/20_hechos.sql` y agregar en el `SELECT` de `fact_booking_event`:
  `date_diff('day', CAST(substr(u.event_ts,1,10) AS DATE), CAST(u.flight_date AS DATE)) AS lead_days,`
- Aplicarlo: `python3 ~/p3/app/estrella.py hechos --bucket aerolinea-p3-936980625651`
- Para que el refresh automático lo mantenga, redesplegar con `infra/03`.
- No rompe ningún test: el contrato permite columnas extra.

**Agregar un atributo a una dimensión**, por ejemplo si la ruta toca Bogotá:

- Agregar en el `SELECT` de `dim_route`, en `10_dimensiones.sql`:
  `(r.origin = 'BOG' OR r.destination = 'BOG') AS touches_bogota,`
- Agregarlo también a la fila `UNKNOWN` (un `false` más).
- Aplicarlo: `python3 ~/p3/app/estrella.py dimensiones --bucket …`
- Las `route_key` no cambian (el orden es determinístico), así que los hechos siguen apuntando bien.

**Otros cambios:**

| Cambio | Qué se toca |
|---|---|
| Un tipo de evento nuevo | Contrato, la API, `raw_events` y un hecho nuevo o una fila más; la vista en vivo suma un contador |
| Refresh más seguido | `REFRESH_CADA_MIN` en el `.env` (cada refresh cuesta ~US$0,0001) |
| Diez veces más tráfico | Medir si 1 shard alcanza; si no, `update_shard_count`. El consumidor ya relista los shards |
| No perder reservas nunca | Outbox |

## 6. Si algo falla en vivo

| Síntoma | Qué hacer |
|---|---|
| La API no responde | `bash infra/03-desplegar-app.sh` (redespliega por SSM). La IP cambia con cada sesión del lab |
| `/admin/pipeline` muestra un error del consumidor | ¿Existe el stream? `aws kinesis describe-stream-summary --stream-name airline-events`. Si no, `infra/01` |
| El refresh da `FAILED` | Leer `error` en `/admin/refresh-status`; mirar el historial del workgroup `parcial3` en la consola de Athena |
| No llega nada a S3 | `aws firehose describe-delivery-stream --delivery-stream-name airline-events-a-s3`; Firehose tarda ~60-120 s |
| R12 falla con la referencia del profesor | La proyección es de US$10,76: pasa con cualquier referencia mayor que US$7,17. El costo real está en §5.8 |

## 7. Números para tener en la cabeza

| Dato | Valor |
|---|---|
| Harness | **70 / 70** en AWS (29 tests, 2 min 46 s); 63/70 antes, en local, a US$0 |
| R2 | p95 0,094 s con 50 en paralelo; 200 de 200 eventos |
| R3 | vista en vivo en 1,5 s |
| R4 | 19.912 / 19.912 eventos en S3 en 61 s |
| R8 | refresh en 20 s (límite 900 s) |
| R10 | un mes 3.798 B contra 11.177 B todos (0,34) |
| Replay | 20.509 registros → 19.912 distintos (17.000 búsquedas, 2.600 reservas y 312 cancelaciones) |
| Modelo | 10 rutas, 3 con dos versiones; `dim_date` de 1.826 días, 91 festivos y 201 días de puente |
| Trampa 1 | sin archivar, la estrella baja de 41 a 20 puntos |
| SCD tipo 1 | enero +38,8 % REGIONAL y −42,5 % TRUNK |
| Costo | US$10,76/mes declarados; el shard cuesta US$0,015/h; el parcial costó ~US$0,10 en AWS |
