-- =============================================================================
--  Respuestas de referencia: Athena sobre los datos CRUDOS, antes de levantar EMR
-- =============================================================================
--  Para qué: tener los números ANTES de pagar el clúster. Lo que dé EMR tiene que
--  coincidir con esto; si no coincide, hay un error en uno de los dos lados.
--
--  Cómo:  python3 correr_referencia.py              → consultas 0 a 3 (tablas y calidad)
--         python3 correr_referencia.py --tope 120   → consultas 4 a 7, con el tope elegido
--         (o a mano en la consola de Athena, reemplazando BUCKET y TOPE_MIN)
--
--  Costo: cada consulta lee como mucho las 4 columnas (~907 MB) → ~$0,005.
-- =============================================================================


-- 0 · Una base aparte, para no mezclar con la base "taxis" que pide el enunciado
CREATE DATABASE IF NOT EXISTS taxis_referencia;


-- 1 · Tabla sobre los 12 Parquet, con SÓLO las 4 columnas del taller.
--     Las otras 15 se ignoran: dos cambian de tipo en julio y romperían la lectura.
CREATE EXTERNAL TABLE IF NOT EXISTS taxis_referencia.viajes_crudos (
    tpep_pickup_datetime  timestamp,
    tpep_dropoff_datetime timestamp,
    pulocationid          bigint,
    dolocationid          bigint
)
STORED AS PARQUET
LOCATION 's3://BUCKET/taxis/viajes/';


-- 2 · Zonas. El CSV trae comillas: OpenCSVSerde las entiende, pero lee todo como texto
CREATE EXTERNAL TABLE IF NOT EXISTS taxis_referencia.zonas (
    locationid   string,
    borough      string,
    zone         string,
    service_zone string
)
ROW FORMAT SERDE 'org.apache.hadoop.hive.serde2.OpenCSVSerde'
LOCATION 's3://BUCKET/taxis/zonas/'
TBLPROPERTIES ('skip.header.line.count' = '1');


-- 3 · Control y calidad: cuántas filas, cuántas sobran, y la distribución de duraciones.
--     Los percentiles son los que deciden el tope de duración válida.
WITH v AS (
    SELECT year(tpep_pickup_datetime) AS anio,
           date_diff('second', tpep_pickup_datetime, tpep_dropoff_datetime) / 60.0 AS dur
    FROM taxis_referencia.viajes_crudos
)
SELECT count(*)                                      AS total,          -- esperado: 102.871.387
       count_if(anio <> 2018)                        AS fuera_de_2018,
       count_if(anio = 2018 AND dur <= 0)            AS duracion_no_positiva,
       count_if(anio = 2018 AND dur > 24 * 60)       AS mas_de_24_h,
       approx_percentile(dur, ARRAY[0.5, 0.9, 0.99, 0.999, 0.9999])
           FILTER (WHERE anio = 2018 AND dur > 0)    AS p50_p90_p99_p999_p9999_min
FROM v;


-- 4a · Paso 6 — el viaje más largo, tal como viene
SELECT pu.zone AS pu_zone,
       d.zone  AS do_zone,
       v.tpep_pickup_datetime  AS pu_datetime,
       v.tpep_dropoff_datetime AS do_datetime,
       date_diff('second', v.tpep_pickup_datetime, v.tpep_dropoff_datetime) / 60.0 AS trip_duration
FROM taxis_referencia.viajes_crudos v
JOIN taxis_referencia.zonas pu ON v.pulocationid = CAST(pu.locationid AS bigint)
JOIN taxis_referencia.zonas d  ON v.dolocationid = CAST(d.locationid  AS bigint)
ORDER BY trip_duration DESC
LIMIT 3;


-- 4b · Paso 6 — el viaje más largo entre los válidos
SELECT pu.zone AS pu_zone,
       d.zone  AS do_zone,
       v.tpep_pickup_datetime  AS pu_datetime,
       v.tpep_dropoff_datetime AS do_datetime,
       date_diff('second', v.tpep_pickup_datetime, v.tpep_dropoff_datetime) / 60.0 AS trip_duration
FROM taxis_referencia.viajes_crudos v
JOIN taxis_referencia.zonas pu ON v.pulocationid = CAST(pu.locationid AS bigint)
JOIN taxis_referencia.zonas d  ON v.dolocationid = CAST(d.locationid  AS bigint)
WHERE year(v.tpep_pickup_datetime) = 2018
  AND date_diff('second', v.tpep_pickup_datetime, v.tpep_dropoff_datetime) BETWEEN 1 AND TOPE_MIN * 60
ORDER BY trip_duration DESC
LIMIT 3;


-- 5 · Paso 7 — destino más frecuente, sin datos erróneos y sin las zonas 264 y 265
SELECT v.dolocationid, d.zone AS do_zone, count(*) AS viajes
FROM taxis_referencia.viajes_crudos v
JOIN taxis_referencia.zonas d ON v.dolocationid = CAST(d.locationid AS bigint)
WHERE year(v.tpep_pickup_datetime) = 2018
  AND date_diff('second', v.tpep_pickup_datetime, v.tpep_dropoff_datetime) BETWEEN 1 AND TOPE_MIN * 60
  AND v.dolocationid NOT IN (264, 265)
GROUP BY v.dolocationid, d.zone
ORDER BY viajes DESC
LIMIT 5;


-- 6 · Paso 8 — par origen-destino más frecuente, con promedio y desviación estándar (muestral)
WITH v AS (
    SELECT pulocationid, dolocationid,
           date_diff('second', tpep_pickup_datetime, tpep_dropoff_datetime) / 60.0 AS dur
    FROM taxis_referencia.viajes_crudos
    WHERE year(tpep_pickup_datetime) = 2018
)
SELECT v.pulocationid, pu.zone AS pu_zone, v.dolocationid, d.zone AS do_zone,
       count(*)                       AS viajes,
       round(avg(v.dur), 2)           AS promedio_min,
       round(stddev_samp(v.dur), 2)   AS desviacion_estandar_min
FROM v
JOIN taxis_referencia.zonas pu ON v.pulocationid = CAST(pu.locationid AS bigint)
JOIN taxis_referencia.zonas d  ON v.dolocationid = CAST(d.locationid  AS bigint)
WHERE v.dur > 0 AND v.dur <= TOPE_MIN
  AND v.pulocationid NOT IN (264, 265)
  AND v.dolocationid NOT IN (264, 265)
GROUP BY v.pulocationid, pu.zone, v.dolocationid, d.zone
ORDER BY viajes DESC
LIMIT 5;


-- 7 · Paso 11 — meses de 2018 por cantidad de viajes (todas las duraciones, como el paso 12)
SELECT month(tpep_pickup_datetime) AS month, count(*) AS viajes
FROM taxis_referencia.viajes_crudos
WHERE year(tpep_pickup_datetime) = 2018
GROUP BY month(tpep_pickup_datetime)
ORDER BY viajes DESC;
