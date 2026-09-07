-- =============================================================================
--  OLTP — Sistema de reservas de aerolínea
--  PostgreSQL 16 · 3NF · implementa el modelo de documento/03-modelo-er.md
-- =============================================================================
--  Trazabilidad: cada bloque cita el FR/NFR/DEC que lo origina.
-- =============================================================================

BEGIN;

DROP SCHEMA IF EXISTS reservas CASCADE;
CREATE SCHEMA reservas;
SET search_path TO reservas;

-- -----------------------------------------------------------------------------
--  Tipos enumerados
-- -----------------------------------------------------------------------------
CREATE TYPE clase_servicio    AS ENUM ('economica', 'business');
CREATE TYPE estado_instancia  AS ENUM ('programado', 'en_vuelo', 'aterrizado', 'cancelado');
CREATE TYPE estado_reserva    AS ENUM ('retenida', 'confirmada', 'cancelada', 'expirada');
CREATE TYPE estado_pago       AS ENUM ('pendiente', 'aprobado', 'rechazado', 'reembolsado');
CREATE TYPE sentido_itin      AS ENUM ('ida', 'vuelta');
CREATE TYPE ambito_politica   AS ENUM ('global', 'ruta', 'vuelo_programado');
CREATE TYPE estado_comision   AS ENUM ('devengada', 'liquidada');

-- =============================================================================
--  RED Y FLOTA
-- =============================================================================

CREATE TABLE aeropuerto (
    codigo_iata   CHAR(3)      PRIMARY KEY,
    nombre        VARCHAR(120) NOT NULL,
    ciudad        VARCHAR(80)  NOT NULL,
    pais          VARCHAR(80)  NOT NULL,
    -- zona_horaria NO es decorativa: sostiene la regla de presentación de DEC-12
    -- (las horas de vuelo se muestran en hora local del aeropuerto, nunca del navegador)
    zona_horaria  VARCHAR(40)  NOT NULL
);

CREATE TABLE ruta (
    id_ruta               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    origen                CHAR(3) NOT NULL REFERENCES aeropuerto(codigo_iata),
    destino               CHAR(3) NOT NULL REFERENCES aeropuerto(codigo_iata),
    duracion_estimada_min INT     NOT NULL CHECK (duracion_estimada_min > 0),
    CONSTRAINT ruta_origen_distinto_destino CHECK (origen <> destino),
    CONSTRAINT ruta_unica UNIQUE (origen, destino)
);

CREATE TABLE aeronave (
    matricula            VARCHAR(10) PRIMARY KEY,
    modelo               VARCHAR(60) NOT NULL,
    -- Capacidad FÍSICA. No es la vendible: ver politica_capacidad (FR-17)
    capacidad_fisica_eco INT NOT NULL CHECK (capacidad_fisica_eco >= 0),
    capacidad_fisica_bus INT NOT NULL CHECK (capacidad_fisica_bus >= 0)
);

CREATE TABLE asiento (
    id_asiento BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    matricula  VARCHAR(10) NOT NULL REFERENCES aeronave(matricula) ON DELETE CASCADE,
    fila       SMALLINT    NOT NULL CHECK (fila > 0),
    columna    CHAR(1)     NOT NULL,
    clase      clase_servicio NOT NULL,
    CONSTRAINT asiento_unico UNIQUE (matricula, fila, columna)
);

-- =============================================================================
--  PROGRAMACIÓN — la separación regla / hecho
-- =============================================================================

-- LA REGLA: un vuelo que se repite. Sin fecha, sin inventario.
CREATE TABLE vuelo_programado (
    id_vuelo_prog     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    numero_vuelo      VARCHAR(8) NOT NULL,
    id_ruta           BIGINT     NOT NULL REFERENCES ruta(id_ruta),
    hora_salida_local TIME       NOT NULL,
    hora_llegada_local TIME      NOT NULL,
    dias_operacion    VARCHAR(7) NOT NULL,   -- máscara LMXJVSD, '-' = no opera
    vigencia_desde    DATE       NOT NULL,
    vigencia_hasta    DATE       NOT NULL,
    CONSTRAINT vigencia_coherente CHECK (vigencia_hasta >= vigencia_desde),
    CONSTRAINT dias_operacion_formato CHECK (dias_operacion ~ '^[LMXJVSD-]{7}$')
);

-- Política de capacidad vendible (FR-17).
-- Es la entidad que convierte "ahora hay overbooking del 5%" en una fila nueva
-- en vez de un rediseño. factor 1.000 = sin sobreventa.
CREATE TABLE politica_capacidad (
    id_politica      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    ambito           ambito_politica NOT NULL,
    id_referencia    BIGINT,                 -- NULL si ambito='global'
    factor_sobreventa NUMERIC(4,3) NOT NULL DEFAULT 1.000
                      CHECK (factor_sobreventa >= 1.000 AND factor_sobreventa <= 1.500),
    vigencia_desde   DATE NOT NULL,
    vigencia_hasta   DATE NOT NULL,
    CONSTRAINT politica_vigencia CHECK (vigencia_hasta >= vigencia_desde),
    CONSTRAINT politica_referencia CHECK (
        (ambito = 'global' AND id_referencia IS NULL) OR
        (ambito <> 'global' AND id_referencia IS NOT NULL)
    )
);

-- EL HECHO: ese vuelo en una fecha concreta.
-- Acá vive el inventario y acá se toma el lock optimista (DEC-03).
CREATE TABLE instancia_vuelo (
    id_instancia               BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vuelo_prog              BIGINT NOT NULL REFERENCES vuelo_programado(id_vuelo_prog),
    fecha_operacion            DATE   NOT NULL,
    matricula                  VARCHAR(10) REFERENCES aeronave(matricula),

    -- capacidad_vendible = f(capacidad_física, política).  FR-17
    capacidad_vendible_eco     INT NOT NULL CHECK (capacidad_vendible_eco >= 0),
    capacidad_vendible_bus     INT NOT NULL CHECK (capacidad_vendible_bus >= 0),

    -- confirmados + retenidos vigentes
    asientos_comprometidos_eco INT NOT NULL DEFAULT 0 CHECK (asientos_comprometidos_eco >= 0),
    asientos_comprometidos_bus INT NOT NULL DEFAULT 0 CHECK (asientos_comprometidos_bus >= 0),

    -- columna del bloqueo optimista (DEC-03)
    version                    BIGINT NOT NULL DEFAULT 0,

    estado                     estado_instancia NOT NULL DEFAULT 'programado',

    CONSTRAINT instancia_unica UNIQUE (id_vuelo_prog, fecha_operacion),

    -- EL INVARIANTE DEL TRABAJO (FR-07, NFR-CONC-01).
    -- Se compara contra la capacidad VENDIBLE, no contra la física.
    CONSTRAINT no_sobreventa_eco CHECK (asientos_comprometidos_eco <= capacidad_vendible_eco),
    CONSTRAINT no_sobreventa_bus CHECK (asientos_comprometidos_bus <= capacidad_vendible_bus)
);

-- Índice para la búsqueda de disponibilidad (NFR-PERF-01)
CREATE INDEX ix_instancia_fecha ON instancia_vuelo (fecha_operacion, id_vuelo_prog);

CREATE TABLE tarifa (
    id_tarifa           BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_vuelo_prog       BIGINT NOT NULL REFERENCES vuelo_programado(id_vuelo_prog),
    clase               clase_servicio NOT NULL,
    antelacion_min_dias INT NOT NULL CHECK (antelacion_min_dias >= 0),
    antelacion_max_dias INT NOT NULL,
    precio_base         NUMERIC(12,2) NOT NULL CHECK (precio_base >= 0),
    moneda              CHAR(3) NOT NULL DEFAULT 'COP',   -- SUP-08
    penalidad_cambio    NUMERIC(12,2) NOT NULL DEFAULT 0, -- SUP-06: parámetro, no constante
    CONSTRAINT ventana_antelacion CHECK (antelacion_max_dias >= antelacion_min_dias)
);

-- =============================================================================
--  CLIENTES Y CANALES
-- =============================================================================

CREATE TABLE pasajero (
    id_pasajero      BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    tipo_documento   VARCHAR(10)  NOT NULL,
    numero_documento VARCHAR(30)  NOT NULL,
    nombre           VARCHAR(80)  NOT NULL,
    apellido         VARCHAR(80)  NOT NULL,
    email            VARCHAR(120) NOT NULL,
    telefono         VARCHAR(30),
    -- Soporta derecho al olvido sin borrar hechos contables (NFR-SEG-02)
    anonimizado_en   TIMESTAMPTZ,
    CONSTRAINT documento_unico UNIQUE (tipo_documento, numero_documento)
);

CREATE TABLE agencia (
    id_agencia          BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    nombre              VARCHAR(120) NOT NULL,
    nit                 VARCHAR(30)  NOT NULL UNIQUE,
    porcentaje_comision NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (porcentaje_comision >= 0), -- FR-14
    descuento_negociado NUMERIC(5,2) NOT NULL DEFAULT 0 CHECK (descuento_negociado >= 0), -- FR-13
    minutos_retencion   INT NOT NULL DEFAULT 1440  -- FR-15: plazo mayor que el del pasajero
);

-- =============================================================================
--  RESERVA — DEC-01 (Reserva → Itinerario → Tramo)
-- =============================================================================

CREATE TABLE reserva (
    id_reserva     BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    codigo_reserva CHAR(6) NOT NULL UNIQUE,      -- PNR, lo que usa el pasajero (FR-11)
    id_pasajero    BIGINT  NOT NULL REFERENCES pasajero(id_pasajero),
    id_agencia     BIGINT  REFERENCES agencia(id_agencia),  -- NULL = venta directa
    estado         estado_reserva NOT NULL DEFAULT 'retenida',
    creada_en      TIMESTAMPTZ NOT NULL DEFAULT now(),
    expira_en      TIMESTAMPTZ,                  -- sólo si estado='retenida' (DEC-02)
    monto_total    NUMERIC(12,2) NOT NULL DEFAULT 0,
    moneda         CHAR(3) NOT NULL DEFAULT 'COP',
    CONSTRAINT expira_solo_si_retenida CHECK (
        (estado = 'retenida' AND expira_en IS NOT NULL) OR
        (estado <> 'retenida')
    )
);

-- El barrido de holds vencidos (DEC-07) recorre por acá
CREATE INDEX ix_reserva_expiracion ON reserva (estado, expira_en)
    WHERE estado = 'retenida';

CREATE TABLE itinerario (
    id_itinerario BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva    BIGINT NOT NULL REFERENCES reserva(id_reserva) ON DELETE CASCADE,
    sentido       sentido_itin NOT NULL,
    orden         SMALLINT NOT NULL DEFAULT 1,
    CONSTRAINT itinerario_orden_unico UNIQUE (id_reserva, sentido, orden)
);

CREATE TABLE tramo (
    id_tramo        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_itinerario   BIGINT NOT NULL REFERENCES itinerario(id_itinerario) ON DELETE CASCADE,
    id_instancia    BIGINT NOT NULL REFERENCES instancia_vuelo(id_instancia),
    orden           SMALLINT NOT NULL,          -- secuencia: resuelve las escalas (FR-02)
    clase           clase_servicio NOT NULL,
    id_tarifa       BIGINT NOT NULL REFERENCES tarifa(id_tarifa),
    -- Congelado al reservar: la tarifa puede cambiar después
    precio_aplicado NUMERIC(12,2) NOT NULL CHECK (precio_aplicado >= 0),
    -- NULL = operado por la propia aerolínea. Prepara codeshare sin rediseño
    operado_por     VARCHAR(60),
    CONSTRAINT tramo_orden_unico UNIQUE (id_itinerario, orden)
);

CREATE INDEX ix_tramo_instancia ON tramo (id_instancia);

CREATE TABLE asignacion_asiento (
    id_asignacion BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_tramo      BIGINT NOT NULL UNIQUE REFERENCES tramo(id_tramo) ON DELETE CASCADE,
    id_asiento    BIGINT NOT NULL REFERENCES asiento(id_asiento),
    asignado_en   TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- =============================================================================
--  PAGO Y AUDITORÍA
-- =============================================================================

CREATE TABLE pago (
    id_pago                BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva             BIGINT NOT NULL REFERENCES reserva(id_reserva),
    -- Idempotencia del webhook (DEC-06): las pasarelas reintentan
    id_transaccion_pasarela VARCHAR(80) NOT NULL UNIQUE,
    estado                 estado_pago NOT NULL DEFAULT 'pendiente',
    monto                  NUMERIC(12,2) NOT NULL CHECK (monto >= 0),
    moneda                 CHAR(3) NOT NULL DEFAULT 'COP',
    registrado_en          TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- SIN columnas de datos de tarjeta. Su ausencia es deliberada: SUP-04, NFR-SEG-01.

CREATE TABLE historial_reserva (
    id_historial    BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva      BIGINT NOT NULL REFERENCES reserva(id_reserva) ON DELETE CASCADE,
    estado_anterior estado_reserva,
    estado_nuevo    estado_reserva NOT NULL,
    actor_tipo      VARCHAR(20) NOT NULL,   -- pasajero | agencia | sistema | admin
    actor_id        VARCHAR(40),
    motivo          VARCHAR(200),
    ocurrido_en     TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Append-only (NFR-AUD-01): sin UPDATE ni DELETE. Fuente de los patrones
-- de cancelación que pide FR-19 y consume el ETL de 5.7.

CREATE INDEX ix_historial_reserva ON historial_reserva (id_reserva, ocurrido_en);

CREATE TABLE comision (
    id_comision        BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    id_reserva         BIGINT NOT NULL REFERENCES reserva(id_reserva),
    id_agencia         BIGINT NOT NULL REFERENCES agencia(id_agencia),
    monto              NUMERIC(12,2) NOT NULL CHECK (monto >= 0),
    estado_liquidacion estado_comision NOT NULL DEFAULT 'devengada',
    CONSTRAINT comision_por_reserva UNIQUE (id_reserva)
);

COMMIT;
