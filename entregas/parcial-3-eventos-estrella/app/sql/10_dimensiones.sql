-- Parcial 3 · DIMENSIONES del modelo estrella (decisión D11: se construyen una vez, por script).
-- Cada tabla se reconstruye con DROP + CTAS. Antes de cada CTAS, estrella.py borra la carpeta de
-- external_location, porque Athena no escribe sobre una ubicación que ya tiene datos.
-- Valores que completa estrella.py: {bucket}
--
-- Los CSV de ref/ pueden venir de Windows con fin de línea \r\n: la última columna de cada uno
-- (holiday_name, region, effective_date) arrastraría un '\r'. Por eso el regexp_replace.

-- ---------------------------------------------------------------------------------- dim_date
-- Un día por fila, del 2023-01-01 al 2027-12-31 (1.826 filas). Responde Q3 (weekday_name),
-- Q7 (is_holiday) y Q8 (is_long_weekend).
-- Día de puente (regla del enunciado §4.3 y de calendar_dates() del harness): el festivo mismo si
-- cae viernes o lunes, más el sábado y el domingo de ese fin de semana. Como la serie de días es
-- continua, "el festivo de ayer / anteayer / mañana / pasado" sale con lag/lead sobre la fecha.
DROP TABLE IF EXISTS dim_date;
CREATE TABLE dim_date
WITH (format = 'PARQUET', external_location = 's3://{bucket}/star/dim_date/') AS
WITH dias AS (
  SELECT CAST(d AS DATE) AS d
  FROM UNNEST(sequence(DATE '2023-01-01', DATE '2027-12-31', INTERVAL '1' DAY)) AS t (d)
),
feriados AS (
  SELECT CAST(holiday_date AS DATE) AS f,
         max(regexp_replace(holiday_name, '[\r\n]', '')) AS nombre
  FROM ref_holidays
  GROUP BY 1
),
base AS (
  SELECT dias.d,
         day_of_week(dias.d) AS dow,                 -- ISO: 1 = lunes ... 7 = domingo
         feriados.nombre,
         feriados.f IS NOT NULL AS feriado
  FROM dias LEFT JOIN feriados ON feriados.f = dias.d
),
vecinos AS (
  SELECT base.*,
         COALESCE(lag(feriado, 1)  OVER (ORDER BY d), false) AS feriado_ayer,
         COALESCE(lag(feriado, 2)  OVER (ORDER BY d), false) AS feriado_anteayer,
         COALESCE(lead(feriado, 1) OVER (ORDER BY d), false) AS feriado_manana,
         COALESCE(lead(feriado, 2) OVER (ORDER BY d), false) AS feriado_pasado
  FROM base
)
SELECT
  CAST(year(d) * 10000 + month(d) * 100 + day(d) AS INTEGER) AS date_key,
  d                                                          AS full_date,
  CAST(year(d) AS INTEGER)                                   AS year,
  CAST(month(d) AS INTEGER)                                  AS month,
  CAST(quarter(d) AS INTEGER)                                AS quarter,
  CAST(dow AS INTEGER)                                       AS weekday,
  CASE dow WHEN 1 THEN 'Monday'   WHEN 2 THEN 'Tuesday' WHEN 3 THEN 'Wednesday'
           WHEN 4 THEN 'Thursday' WHEN 5 THEN 'Friday'  WHEN 6 THEN 'Saturday'
           ELSE 'Sunday' END                                 AS weekday_name,
  dow >= 6                                                   AS is_weekend,
  feriado                                                    AS is_holiday,
  COALESCE(nombre, '')                                       AS holiday_name,
  CASE WHEN dow IN (1, 5) THEN feriado                               -- lunes o viernes festivo
       WHEN dow = 6 THEN feriado_ayer OR feriado_pasado              -- sábado: viernes o lunes
       WHEN dow = 7 THEN feriado_anteayer OR feriado_manana          -- domingo: viernes o lunes
       ELSE false END                                        AS is_long_weekend,
  -- Atributos extra (fuera del contrato): jerarquía de fechas para reportes legibles.
  CAST(day(d) AS INTEGER)                                    AS day_of_month,
  CASE month(d) WHEN 1 THEN 'January' WHEN 2 THEN 'February' WHEN 3 THEN 'March'
                WHEN 4 THEN 'April'   WHEN 5 THEN 'May'      WHEN 6 THEN 'June'
                WHEN 7 THEN 'July'    WHEN 8 THEN 'August'   WHEN 9 THEN 'September'
                WHEN 10 THEN 'October' WHEN 11 THEN 'November' ELSE 'December' END AS month_name,
  concat(CAST(year(d) AS VARCHAR), '-', lpad(CAST(month(d) AS VARCHAR), 2, '0')) AS year_month
FROM vecinos;

-- ---------------------------------------------------------------------------------- dim_route
-- SCD tipo 2 (Q5 y R9): una fila por VERSIÓN de la ruta. valid_from inclusivo, valid_to exclusivo
-- (= inicio de la versión siguiente) y la vigente cierra en 9999-12-31 con is_current = true.
-- route_key es una clave subrogada: identifica la versión, no la ruta.
-- Fila -1 'UNKNOWN' (decisión D7): destino de los eventos con una ruta que no está en el catálogo,
-- para no perderlos y no dejar huérfanos (R6).
DROP TABLE IF EXISTS dim_route;
CREATE TABLE dim_route
WITH (format = 'PARQUET', external_location = 's3://{bucket}/star/dim_route/') AS
WITH historia AS (
  SELECT route, route_category,
         CAST(regexp_replace(effective_date, '[\r\n]', '') AS DATE) AS valid_from
  FROM ref_route_history
),
versiones AS (
  SELECT historia.*,
         lead(valid_from) OVER (PARTITION BY route ORDER BY valid_from) AS siguiente,
         row_number()     OVER (PARTITION BY route ORDER BY valid_from) AS version
  FROM historia
)
SELECT CAST(row_number() OVER (ORDER BY v.route, v.valid_from) AS INTEGER) AS route_key,
       v.route,
       r.origin,
       r.destination,
       regexp_replace(r.region, '[\r\n]', '')                AS region,
       v.route_category,
       v.valid_from,
       COALESCE(v.siguiente, DATE '9999-12-31')              AS valid_to,
       v.siguiente IS NULL                                   AS is_current,
       CAST(v.version AS INTEGER)                            AS version      -- extra
FROM versiones v
JOIN ref_routes r ON r.route = v.route
UNION ALL
SELECT -1, 'UNKNOWN', 'UNK', 'UNK', 'UNKNOWN', 'UNKNOWN',
       DATE '1900-01-01', DATE '9999-12-31', true, 1;

-- ----------------------------------------------------------------------------- dim_fare_class
-- Q1 (ingreso por clase). is_premium es un atributo extra para agrupar cabinas.
DROP TABLE IF EXISTS dim_fare_class;
CREATE TABLE dim_fare_class
WITH (format = 'PARQUET', external_location = 's3://{bucket}/star/dim_fare_class/') AS
SELECT CAST(k AS INTEGER) AS fare_class_key,
       clase              AS fare_class,
       premium            AS is_premium
FROM (VALUES (1, 'ECONOMY', false), (2, 'BUSINESS', true), (-1, 'UNKNOWN', false))
     AS t (k, clase, premium);
