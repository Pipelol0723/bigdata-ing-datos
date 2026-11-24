-- Parcial 3 · HECHOS del modelo estrella (decisiones D5 y D6): rebuild completo en cada refresh,
-- leyendo TODA la landing zone. Correrlo dos veces da lo mismo (idempotente), y un evento tardío o
-- desordenado cae en la fecha en que ocurrió, igual que si hubiera llegado a tiempo (R8).
-- Valores que completa estrella.py: {bucket}
--
-- Las tres reglas que se repiten en los dos hechos:
--   1. Deduplicar por event_id (la landing es append-only y trae duplicados: Kinesis entrega
--      "al menos una vez" y el replay del harness repite un 3 %). row_number() se queda con una copia.
--   2. date_key sale de event_ts (cuándo OCURRIÓ), nunca de la hora de llegada.
--   3. route_key es la versión de la ruta vigente ESE día (as-of join contra la SCD 2):
--      valid_from <= fecha < valid_to. Si la ruta no está en el catálogo, -1 (UNKNOWN).

-- -------------------------------------------------------------------------------- fact_search
-- Grano: UNA fila por evento de búsqueda distinto. Particionada por mes (R5, R10): una consulta
-- de un mes sólo lee esa carpeta.
DROP TABLE IF EXISTS fact_search;
CREATE TABLE fact_search
WITH (format = 'PARQUET',
      external_location = 's3://{bucket}/star/fact_search/',
      partitioned_by = ARRAY['month']) AS
WITH unicos AS (
  SELECT * FROM (
    SELECT e.*, row_number() OVER (PARTITION BY event_id ORDER BY event_ts) AS copia
    FROM raw_events e
    WHERE event_type = 'search_performed' AND event_id IS NOT NULL AND event_ts IS NOT NULL
  ) x
  WHERE copia = 1
)
SELECT u.event_id,
       CAST(replace(substr(u.event_ts, 1, 10), '-', '') AS INTEGER) AS date_key,
       COALESCE(r.route_key, -1)                                    AS route_key,
       CAST(COALESCE(u.results_count, 0) AS INTEGER)                AS results_count,
       1                                                            AS searches,
       substr(u.event_ts, 1, 7)                                     AS month    -- la partición va última
FROM unicos u
LEFT JOIN dim_route r
       ON r.route = concat(upper(u.origin), '-', upper(u.destination))
      AND CAST(substr(u.event_ts, 1, 10) AS DATE) >= r.valid_from
      AND CAST(substr(u.event_ts, 1, 10) AS DATE) <  r.valid_to;

-- ------------------------------------------------------------------------- fact_booking_event
-- Grano: UNA fila por evento de reserva distinto (creación o cancelación). Es un hecho de
-- transacción con medidas aditivas: una creación suma bookings = 1 y +precio; una cancelación suma
-- cancellations = 1 y -precio. El ingreso neto (Q1, Q4, Q5) es un simple SUM(revenue_cents).
DROP TABLE IF EXISTS fact_booking_event;
CREATE TABLE fact_booking_event
WITH (format = 'PARQUET',
      external_location = 's3://{bucket}/star/fact_booking_event/') AS
WITH unicos AS (
  SELECT * FROM (
    SELECT e.*, row_number() OVER (PARTITION BY event_id ORDER BY event_ts) AS copia
    FROM raw_events e
    WHERE event_type IN ('reservation_created', 'reservation_cancelled')
      AND event_id IS NOT NULL AND event_ts IS NOT NULL
  ) x
  WHERE copia = 1
)
SELECT u.event_id,
       CAST(replace(substr(u.event_ts, 1, 10), '-', '') AS INTEGER) AS date_key,
       COALESCE(r.route_key, -1)                                    AS route_key,
       COALESCE(f.fare_class_key, -1)                               AS fare_class_key,
       u.reservation_id,
       u.event_type,
       CASE WHEN u.event_type = 'reservation_created'   THEN 1 ELSE 0 END AS bookings,
       CASE WHEN u.event_type = 'reservation_cancelled' THEN 1 ELSE 0 END AS cancellations,
       CAST(CASE WHEN u.event_type = 'reservation_created' THEN u.price_cents
                 ELSE -u.price_cents END AS BIGINT)                AS revenue_cents,
       u.flight_id                                                  -- extra: dimensión degenerada
FROM unicos u
LEFT JOIN dim_route r
       ON r.route = u.route
      AND CAST(substr(u.event_ts, 1, 10) AS DATE) >= r.valid_from
      AND CAST(substr(u.event_ts, 1, 10) AS DATE) <  r.valid_to
LEFT JOIN dim_fare_class f
       ON f.fare_class = u.fare_class;
