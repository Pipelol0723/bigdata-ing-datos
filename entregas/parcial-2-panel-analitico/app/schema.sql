-- Base transaccional del parcial 2 (PostgreSQL). Sólo atiende reservas: el historial de 2 millones
-- de filas NO vive acá, vive en S3 y lo consultan EMR y Athena (separación de cargas, R1/R2).

CREATE TABLE IF NOT EXISTS flights (
    flight_id       text    PRIMARY KEY,
    route           text    NOT NULL,                       -- 'BOG-MDE'
    flight_date     date    NOT NULL,
    capacity        integer NOT NULL CHECK (capacity > 0),
    -- Contador de asientos libres. El CHECK es la segunda red: aunque el código fallara,
    -- la base rechaza quedar en negativo (nunca más reservas que asientos).
    seats_available integer NOT NULL CHECK (seats_available >= 0 AND seats_available <= capacity),
    price_cents     bigint  NOT NULL CHECK (price_cents > 0)
);
CREATE INDEX IF NOT EXISTS flights_busqueda ON flights (route, flight_date);

CREATE TABLE IF NOT EXISTS reservations (
    reservation_id text        PRIMARY KEY,
    flight_id      text        NOT NULL REFERENCES flights (flight_id),
    passenger_name text        NOT NULL,
    fare_class     text        NOT NULL CHECK (fare_class IN ('ECONOMY', 'BUSINESS')),
    status         text        NOT NULL DEFAULT 'CONFIRMED' CHECK (status IN ('CONFIRMED', 'CANCELLED')),
    created_at     timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS reservations_por_vuelo ON reservations (flight_id);
