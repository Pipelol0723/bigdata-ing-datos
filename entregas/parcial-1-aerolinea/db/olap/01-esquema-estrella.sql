-- =============================================================================
--  OLAP — Modelo dimensional (estrella)
--  PostgreSQL 16 · destino del ETL de la sección 5.7
-- =============================================================================
--  POR QUÉ ESTE ESQUEMA NO ES EL DEL OLTP
--
--  El OLTP está en 3NF: cada dato en un solo lugar, ideal para escrituras
--  concurrentes e integridad (DEC-03 toca una fila). Pero responder
--  "ocupación por ruta" en 3NF cruza cinco tablas por consulta.
--
--  Acá los joins se resuelven UNA VEZ, en el ETL, no en cada reporte.
--  Es la materialización de la discusión de normalización de 5.3.
--
--  DOS TABLAS DE HECHOS con dimensiones compartidas (constelación), porque las
--  preguntas de FR-19 tienen granos distintos:
--    · ingresos y cancelaciones  → grano TRAMO VENDIDO
--    · ocupación por ruta        → grano INSTANCIA DE VUELO
--  Un solo hecho a grano de tramo no podría dar ocupación: no sabría la
--  capacidad de los vuelos que no vendieron nada.
-- =============================================================================

BEGIN;

DROP SCHEMA IF EXISTS dw CASCADE;
CREATE SCHEMA dw;
SET search_path TO dw;

-- =============================================================================
--  DIMENSIONES
-- =============================================================================

CREATE TABLE dim_fecha (
    id_fecha       INT     PRIMARY KEY,          -- AAAAMMDD
    fecha          DATE    NOT NULL UNIQUE,
    anio           SMALLINT NOT NULL,
    trimestre      SMALLINT NOT NULL,
    mes            SMALLINT NOT NULL,
    nombre_mes     VARCHAR(12) NOT NULL,
    dia            SMALLINT NOT NULL,
    dia_semana     SMALLINT NOT NULL,            -- 1=lunes
    nombre_dia     VARCHAR(12) NOT NULL,
    es_fin_semana  BOOLEAN NOT NULL,
    -- Temporada: permite responder "ocupación en temporada alta" sin recalcular
    temporada      VARCHAR(10) NOT NULL          -- alta | media | baja
);

CREATE TABLE dim_ruta (
    id_ruta_dw       BIGINT PRIMARY KEY,         -- conserva el id del OLTP
    origen_iata      CHAR(3)     NOT NULL,
    origen_ciudad    VARCHAR(80) NOT NULL,
    origen_pais      VARCHAR(80) NOT NULL,
    destino_iata     CHAR(3)     NOT NULL,
    destino_ciudad   VARCHAR(80) NOT NULL,
    destino_pais     VARCHAR(80) NOT NULL,
    -- Desnormalizado a propósito: el reporte por ruta no necesita joins
    ruta_descripcion VARCHAR(20) NOT NULL,       -- 'BOG-MDE'
    duracion_min     INT NOT NULL,
    es_internacional BOOLEAN NOT NULL
);

CREATE TABLE dim_tarifa (
    id_tarifa_dw        BIGINT PRIMARY KEY,
    clase               VARCHAR(12) NOT NULL,
    antelacion_min_dias INT NOT NULL,
    antelacion_max_dias INT NOT NULL,
    -- Etiqueta legible de la ventana: agrupa sin tener que interpretar números
    ventana_compra      VARCHAR(20) NOT NULL,    -- anticipada | intermedia | ultima_hora
    precio_base         NUMERIC(12,2) NOT NULL,
    moneda              CHAR(3) NOT NULL
);

CREATE TABLE dim_canal (
    id_canal            BIGINT PRIMARY KEY,      -- 0 = venta directa
    tipo_canal          VARCHAR(12) NOT NULL,    -- directo | agencia
    nombre_agencia      VARCHAR(120),
    porcentaje_comision NUMERIC(5,2)
);

CREATE TABLE dim_estado_reserva (
    id_estado SMALLINT PRIMARY KEY,
    estado    VARCHAR(12) NOT NULL UNIQUE,
    -- Banderas pre-calculadas: los patrones de cancelación de FR-19 se
    -- responden con SUM(), sin CASE WHEN en cada consulta
    es_vendida    BOOLEAN NOT NULL,
    es_cancelada  BOOLEAN NOT NULL,
    es_expirada   BOOLEAN NOT NULL
);

CREATE TABLE dim_vuelo (
    id_vuelo_dw   BIGINT PRIMARY KEY,
    numero_vuelo  VARCHAR(8) NOT NULL,
    id_ruta_dw    BIGINT NOT NULL REFERENCES dim_ruta(id_ruta_dw),
    hora_salida   TIME NOT NULL,
    franja_horaria VARCHAR(12) NOT NULL          -- madrugada | mañana | tarde | noche
);

-- =============================================================================
--  HECHOS
-- =============================================================================

-- Grano: UN TRAMO VENDIDO.
-- Responde: ingresos por tarifa, patrones de cancelación, mix de canal.
CREATE TABLE fact_tramo_vendido (
    id_tramo_dw     BIGINT PRIMARY KEY,          -- conserva el id del OLTP
    id_fecha_vuelo  INT    NOT NULL REFERENCES dim_fecha(id_fecha),
    id_fecha_reserva INT   NOT NULL REFERENCES dim_fecha(id_fecha),
    id_ruta_dw      BIGINT NOT NULL REFERENCES dim_ruta(id_ruta_dw),
    id_vuelo_dw     BIGINT NOT NULL REFERENCES dim_vuelo(id_vuelo_dw),
    id_tarifa_dw    BIGINT NOT NULL REFERENCES dim_tarifa(id_tarifa_dw),
    id_canal        BIGINT NOT NULL REFERENCES dim_canal(id_canal),
    id_estado       SMALLINT NOT NULL REFERENCES dim_estado_reserva(id_estado),

    -- Métricas aditivas
    asientos          INT NOT NULL DEFAULT 1,
    ingreso           NUMERIC(12,2) NOT NULL,
    comision          NUMERIC(12,2) NOT NULL DEFAULT 0,
    -- Días entre la reserva y el vuelo: alimenta el análisis de antelación
    dias_antelacion   INT NOT NULL,
    -- Sólo cuenta si terminó vendido; permite SUM() sin filtrar
    ingreso_realizado NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE INDEX ix_ftv_fecha ON fact_tramo_vendido (id_fecha_vuelo);
CREATE INDEX ix_ftv_ruta  ON fact_tramo_vendido (id_ruta_dw);

-- Grano: UNA INSTANCIA DE VUELO.
-- Responde: ocupación por ruta. Incluye los vuelos que NO vendieron nada,
-- que son justamente los que un hecho a grano de tramo perdería.
CREATE TABLE fact_ocupacion_vuelo (
    id_instancia_dw    BIGINT PRIMARY KEY,
    id_fecha           INT    NOT NULL REFERENCES dim_fecha(id_fecha),
    id_ruta_dw         BIGINT NOT NULL REFERENCES dim_ruta(id_ruta_dw),
    id_vuelo_dw        BIGINT NOT NULL REFERENCES dim_vuelo(id_vuelo_dw),

    capacidad_vendible INT NOT NULL,
    asientos_vendidos  INT NOT NULL,
    -- Precalculado: evita divisiones por cero repartidas por todos los reportes
    factor_ocupacion   NUMERIC(5,4) NOT NULL,
    ingreso_vuelo      NUMERIC(12,2) NOT NULL DEFAULT 0
);

CREATE INDEX ix_fov_fecha ON fact_ocupacion_vuelo (id_fecha);
CREATE INDEX ix_fov_ruta  ON fact_ocupacion_vuelo (id_ruta_dw);

-- =============================================================================
--  Control de cargas — trazabilidad del ETL
-- =============================================================================
CREATE TABLE etl_ejecucion (
    id_ejecucion   BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    iniciada_en    TIMESTAMPTZ NOT NULL DEFAULT now(),
    finalizada_en  TIMESTAMPTZ,
    filas_hechos   INT,
    filas_dims     INT,
    estado         VARCHAR(12) NOT NULL DEFAULT 'en_curso',
    detalle        TEXT
);

COMMIT;

-- =============================================================================
--  VISTAS DE NEGOCIO — las tres preguntas del enunciado, ya resueltas
-- =============================================================================
SET search_path TO dw;

-- 1) Ocupación por ruta
CREATE OR REPLACE VIEW v_ocupacion_por_ruta AS
SELECT r.ruta_descripcion,
       r.origen_ciudad, r.destino_ciudad,
       count(*)                             AS vuelos,
       sum(f.capacidad_vendible)            AS asientos_ofrecidos,
       sum(f.asientos_vendidos)             AS asientos_vendidos,
       ROUND(AVG(f.factor_ocupacion) * 100, 2) AS ocupacion_promedio_pct,
       sum(f.ingreso_vuelo)                 AS ingreso_total
  FROM fact_ocupacion_vuelo f
  JOIN dim_ruta r ON r.id_ruta_dw = f.id_ruta_dw
 GROUP BY r.ruta_descripcion, r.origen_ciudad, r.destino_ciudad
 ORDER BY ocupacion_promedio_pct DESC;

-- 2) Ingresos por tarifa
CREATE OR REPLACE VIEW v_ingresos_por_tarifa AS
SELECT t.clase, t.ventana_compra,
       count(*)                    AS tramos,
       sum(f.ingreso_realizado)    AS ingreso,
       ROUND(AVG(f.ingreso), 2)    AS ticket_promedio,
       ROUND(AVG(f.dias_antelacion), 1) AS antelacion_promedio_dias
  FROM fact_tramo_vendido f
  JOIN dim_tarifa t ON t.id_tarifa_dw = f.id_tarifa_dw
 GROUP BY t.clase, t.ventana_compra
 ORDER BY ingreso DESC;

-- 3) Patrones de cancelación
CREATE OR REPLACE VIEW v_patrones_cancelacion AS
SELECT r.ruta_descripcion,
       c.tipo_canal,
       count(*) FILTER (WHERE e.es_vendida)   AS vendidos,
       count(*) FILTER (WHERE e.es_cancelada) AS cancelados,
       count(*) FILTER (WHERE e.es_expirada)  AS expirados,
       ROUND(100.0 * count(*) FILTER (WHERE e.es_cancelada) / NULLIF(count(*), 0), 2)
         AS tasa_cancelacion_pct,
       ROUND(AVG(f.dias_antelacion) FILTER (WHERE e.es_cancelada), 1)
         AS antelacion_promedio_cancelados
  FROM fact_tramo_vendido f
  JOIN dim_ruta r           ON r.id_ruta_dw = f.id_ruta_dw
  JOIN dim_canal c          ON c.id_canal = f.id_canal
  JOIN dim_estado_reserva e ON e.id_estado = f.id_estado
 GROUP BY r.ruta_descripcion, c.tipo_canal
 ORDER BY tasa_cancelacion_pct DESC;
