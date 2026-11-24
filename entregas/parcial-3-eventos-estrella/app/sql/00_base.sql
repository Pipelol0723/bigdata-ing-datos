-- Parcial 3 · tablas de ENTRADA del modelo estrella (Athena / Glue Data Catalog).
-- Son tablas externas: Athena sólo guarda el esquema; los datos son los objetos de S3.
-- Idempotente (IF NOT EXISTS): el refresh lo corre siempre antes de construir.
--
-- Valores que completa estrella.py: {db}, {bucket}, {raw_uri}

CREATE DATABASE IF NOT EXISTS {db};

-- Landing zone: lo que escribe Firehose (JSON, un evento por línea, gzip). Athena lee también las
-- subcarpetas por fecha que agrega Firehose (AAAA/MM/DD/HH). Columnas = unión de los tres tipos de
-- evento del contrato (EVENTS.md); los campos que un tipo no tiene quedan en NULL.
-- 'ignore.malformed.json': una línea rota no frena la consulta; queda con event_id NULL y se filtra.
CREATE EXTERNAL TABLE IF NOT EXISTS raw_events (
  event_id       string,
  event_type     string,
  event_ts       string,
  schema_version int,
  session_id     string,
  origin         string,
  destination    string,
  travel_date    string,
  results_count  int,
  reservation_id string,
  flight_id      string,
  route          string,
  flight_date    string,
  fare_class     string,
  price_cents    bigint
)
ROW FORMAT SERDE 'org.openx.data.jsonserde.JsonSerDe'
WITH SERDEPROPERTIES ('ignore.malformed.json' = 'true')
LOCATION '{raw_uri}';

-- Datos de referencia del parcial (generate_p3 --seed 12345), subidos tal cual a s3://{bucket}/ref/.
CREATE EXTERNAL TABLE IF NOT EXISTS ref_routes (
  route string, origin string, destination string, region string
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://{bucket}/ref/routes/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE EXTERNAL TABLE IF NOT EXISTS ref_route_history (
  route string, route_category string, effective_date string
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://{bucket}/ref/route_history/'
TBLPROPERTIES ('skip.header.line.count' = '1');

CREATE EXTERNAL TABLE IF NOT EXISTS ref_holidays (
  holiday_date string, holiday_name string
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION 's3://{bucket}/ref/holidays/'
TBLPROPERTIES ('skip.header.line.count' = '1');
