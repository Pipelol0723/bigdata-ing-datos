# Anexo B — Qué se toca si cambia algo

El enunciado (§8) anticipa que en la defensa se puede pedir un cambio en vivo y preguntar qué parte
del pipeline, de las tablas y de los tests se ve afectada; por ejemplo, agregar una medida a un hecho
o un atributo a una dimensión.

El diseño apunta a que cada cambio toque **un solo lugar**:
- El ETL entero es SQL en tres archivos: entradas, dimensiones y hechos.
- Cada refresh reconstruye los hechos desde la landing: un cambio en el SQL se aplica a toda la
  historia sin migraciones.
- La landing guarda el evento **completo**: una medida nueva puede salir de un campo que ya viajaba,
  sin tocar la API.

| Cambio pedido | Pipeline / código | Tablas | Tests del harness | Costo / tiempo |
|---|---|---|---|---|
| **Medida nueva en un hecho**: anticipación de la compra, `lead_days` = `flight_date − fecha del evento` | Una columna en `app/sql/20_hechos.sql` (`date_diff('day', …)`). El evento ya trae `flight_date`: la API no cambia | `fact_booking_event` gana una columna en el próximo refresh, con toda la historia | Ninguno: el contrato permite columnas extra | Un refresh (~20 s, ~US$0,0001) |
| **Atributo nuevo en una dimensión**: `distance_km` o `is_international` en `dim_route` | Columna en `ref/routes_ref.csv` y en `ref_routes` (`00_base.sql`), y en el `SELECT` de `dim_route` (`10_dimensiones.sql`). Si el atributo **cambia en el tiempo**, decidir tipo 1 o 2 (§5.6) | `dim_route` se reconstruye con `infra/02 --forzar`; los hechos no cambian (apuntan por `route_key`) | Ninguno si las versiones siguen siendo las de `route_category_history` (R9) | DDL + 1 CTAS |
| **Pregunta nueva sobre lo que ya hay**: ingreso por región y trimestre | Ninguno: es una consulta (`dim_route.region`, `dim_date.quarter`) | — | — | Una consulta de Athena |
| **Tipo de evento nuevo**: `payment_completed` | Contrato, la API publica el evento (`eventos.evento(...)`), columnas nuevas en `raw_events` y, según el grano, un hecho nuevo `fact_payment` o una fila más en `fact_booking_event`. La vista en vivo suma un contador | Tabla nueva o columnas | R1 cuenta los eventos de cada `reservation_id`: un evento extra por reserva lo rompería. Habría que filtrarlo por tipo o acordar el contrato | Código + DDL |
| **Refresh más seguido** (cada 2 min) | Variable `REFRESH_CADA_MIN` del `.env` | — | — | Más consultas de Athena: ~US$0,0001 por refresh |
| **Refresh por evento** | No conviene: archivos chicos, costo y deduplicación imposible por evento (§5.2) | — | — | — |
| **Diez veces más tráfico** | Ver si 1 shard alcanza (1.000 registros/s, 1 MB/s de escritura). Si no, más shards con `update_shard_count`; el consumidor ya relista shards tras un *reshard* | — | R11 exige 1 shard: sería un cambio de requisito | US$0,015/h por shard |
| **Landing de 10 GB o más** | ETL incremental en vez de rebuild: Iceberg + `MERGE`, o Glue (§5.5) | Particiones por fecha de evento reescritas a pedido | R8 sigue igual si el resultado no cambia | Glue ~US$0,015-0,03 por corrida |
| **No perder reservas aunque se caiga la API** | *Transactional outbox*: tabla `outbox` en la misma transacción + publicador (§5.1) | Tabla nueva en PostgreSQL | Ninguno | Una escritura más por reserva |
| **`region` como tipo 2** | Archivo de historia por región; las versiones de `dim_route` pasan a ser la combinación de las dos historias | `dim_route` con más versiones | R9 compara las versiones con `route_category_history`: fallaría si cambian las fechas de versión | Rehacer `dim_route` |

**Regla general para responder en vivo.** Seguir este orden:
1. **El camino.** ¿Es el rápido (memoria de la API, segundos) o el analítico (S3 → Athena, minutos)?
2. **El grano.** ¿Una fila por evento sigue siendo correcta?
3. **La tabla.** ¿Es una medida en un hecho, un atributo en una dimensión o una tabla nueva?
4. **Los tests.** Recién ahí, qué tests del harness lo notarían. El contrato permite columnas
   extra; lo que no se puede cambiar es el grano ni los valores de las medidas del contrato.
