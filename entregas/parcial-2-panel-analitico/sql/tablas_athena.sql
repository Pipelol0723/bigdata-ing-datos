-- Parcial 2 · las dos tablas del contrato (harness/contract/DATA.md) en el Glue Data Catalog.
-- Se crean con DDL de Athena: sin crawler que pagar y con los nombres y el orden exactos (R5).
-- __BUCKET__ lo reemplaza infra/03-tablas-athena.sh. Una sentencia por bloque (Athena corre de a una).

CREATE DATABASE IF NOT EXISTS airline_analytics;

-- Partition projection: Athena calcula las 24 carpetas month= a partir de este rango, sin
-- registrarlas en el catálogo ni correr MSCK REPAIR después de cada corrida del job (decisión D4).
CREATE EXTERNAL TABLE IF NOT EXISTS airline_analytics.reservations_curated (
    reservation_id string,
    flight_id      string,
    route          string,
    fare_class     string,
    price_cents    bigint,
    status         string
)
PARTITIONED BY (month string)
STORED AS PARQUET
LOCATION 's3://__BUCKET__/curated/reservations_curated/'
TBLPROPERTIES (
    'classification'                 = 'parquet',
    'projection.enabled'             = 'true',
    'projection.month.type'          = 'date',
    'projection.month.format'        = 'yyyy-MM',
    'projection.month.range'         = '2023-01,2024-12',
    'projection.month.interval'      = '1',
    'projection.month.interval.unit' = 'MONTHS',
    'storage.location.template'      = 's3://__BUCKET__/curated/reservations_curated/month=${month}/'
);

-- Sin particionar a propósito: si month fuera partición, saldría de la lista de columnas y el
-- orden del contrato (route, month, ...) dejaría de coincidir (R5). Son 240 filas.
CREATE EXTERNAL TABLE IF NOT EXISTS airline_analytics.route_month_metrics (
    route          string,
    month          string,
    seats_capacity bigint,
    seats_sold     bigint,
    occupancy      double,
    revenue_cents  bigint,
    bookings       bigint,
    cancellations  bigint
)
STORED AS PARQUET
LOCATION 's3://__BUCKET__/curated/route_month_metrics/'
TBLPROPERTIES ('classification' = 'parquet');
