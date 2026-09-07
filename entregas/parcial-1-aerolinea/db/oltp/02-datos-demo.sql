-- =============================================================================
--  Datos de demostración — OLTP
--  Aerolínea regional colombiana. Escala reducida respecto de SUP-01 para que
--  el conjunto sea manejable, pero con la misma forma.
-- =============================================================================

SET search_path TO reservas;

BEGIN;

-- -----------------------------------------------------------------------------
--  Red
-- -----------------------------------------------------------------------------
INSERT INTO aeropuerto (codigo_iata, nombre, ciudad, pais, zona_horaria) VALUES
  ('BOG', 'El Dorado',                'Bogotá',       'Colombia', 'America/Bogota'),
  ('MDE', 'José María Córdova',       'Medellín',     'Colombia', 'America/Bogota'),
  ('CTG', 'Rafael Núñez',             'Cartagena',    'Colombia', 'America/Bogota'),
  ('CLO', 'Alfonso Bonilla Aragón',   'Cali',         'Colombia', 'America/Bogota'),
  ('SMR', 'Simón Bolívar',            'Santa Marta',  'Colombia', 'America/Bogota'),
  ('BAQ', 'Ernesto Cortissoz',        'Barranquilla', 'Colombia', 'America/Bogota'),
  ('MIA', 'Miami International',      'Miami',        'Estados Unidos', 'America/New_York');
-- MIA con zona horaria distinta a propósito: hace visible por qué DEC-12 exige
-- mostrar cada hora en la local de su aeropuerto.

INSERT INTO ruta (origen, destino, duracion_estimada_min) VALUES
  ('BOG','MDE', 55), ('MDE','BOG', 55),
  ('BOG','CTG', 90), ('CTG','BOG', 90),
  ('BOG','CLO', 65), ('CLO','BOG', 65),
  ('BOG','SMR',100), ('SMR','BOG',100),
  ('BOG','BAQ', 95), ('BAQ','BOG', 95),
  ('MDE','CTG', 70), ('CTG','MDE', 70),
  ('BOG','MIA',210), ('MIA','BOG',210);

-- -----------------------------------------------------------------------------
--  Flota
-- -----------------------------------------------------------------------------
INSERT INTO aeronave (matricula, modelo, capacidad_fisica_eco, capacidad_fisica_bus) VALUES
  ('HK-4801', 'Airbus A320',   150, 12),
  ('HK-4802', 'Airbus A320',   150, 12),
  ('HK-4803', 'ATR 72-600',     68,  0),
  ('HK-4804', 'Boeing 737-800',162, 16);

-- Asientos físicos (para la asignación en check-in, DEC de la sección 5.3 nudo 4)
INSERT INTO asiento (matricula, fila, columna, clase)
SELECT a.matricula, f.fila, c.col::CHAR(1),
       CASE WHEN f.fila <= 3 AND a.capacidad_fisica_bus > 0
            THEN 'business'::clase_servicio ELSE 'economica'::clase_servicio END
FROM aeronave a
CROSS JOIN generate_series(1, 12) AS f(fila)
CROSS JOIN (VALUES ('A'),('B'),('C'),('D')) AS c(col);

-- -----------------------------------------------------------------------------
--  Política de capacidad (FR-17)
--  factor 1.000 = sin sobreventa. Cambiar este valor es TODO lo que hace falta
--  para habilitar overbooking: ninguna tabla se modifica.
-- -----------------------------------------------------------------------------
INSERT INTO politica_capacidad (ambito, id_referencia, factor_sobreventa, vigencia_desde, vigencia_hasta)
VALUES ('global', NULL, 1.000, DATE '2026-01-01', DATE '2026-12-31');

-- -----------------------------------------------------------------------------
--  Vuelos programados (la regla)
-- -----------------------------------------------------------------------------
INSERT INTO vuelo_programado (numero_vuelo, id_ruta, hora_salida_local, hora_llegada_local,
                              dias_operacion, vigencia_desde, vigencia_hasta)
SELECT v.num, r.id_ruta, v.sale::TIME, v.llega::TIME, v.dias, DATE '2026-01-01', DATE '2026-12-31'
FROM (VALUES
    ('AV8020','BOG','MDE','07:30','08:25','LMXJV--'),
    ('AV8021','MDE','BOG','09:15','10:10','LMXJV--'),
    ('AV8030','BOG','CTG','06:00','07:30','LMXJVSD'),
    ('AV8031','CTG','BOG','08:15','09:45','LMXJVSD'),
    ('AV8040','BOG','CLO','11:00','12:05','LMXJVSD'),
    ('AV8041','CLO','BOG','13:00','14:05','LMXJVSD'),
    ('AV8050','BOG','SMR','14:20','16:00','--XJVSD'),
    ('AV8060','MDE','CTG','10:30','11:40','L-X-V--'),
    ('AV9000','BOG','MIA','23:10','03:40','LMXJVSD')
) AS v(num, ori, des, sale, llega, dias)
JOIN ruta r ON r.origen = v.ori AND r.destino = v.des;

-- -----------------------------------------------------------------------------
--  Tarifas — ventanas por antelación de compra (FR-03)
-- -----------------------------------------------------------------------------
INSERT INTO tarifa (id_vuelo_prog, clase, antelacion_min_dias, antelacion_max_dias,
                    precio_base, moneda, penalidad_cambio)
SELECT vp.id_vuelo_prog, t.clase::clase_servicio, t.amin, t.amax,
       ROUND(t.base * (1 + r.duracion_estimada_min / 120.0), -3), 'COP', t.penal
FROM vuelo_programado vp
JOIN ruta r ON r.id_ruta = vp.id_ruta
CROSS JOIN (VALUES
    ('economica', 21, 365, 180000,  60000),  -- compra anticipada
    ('economica',  7,  20, 260000,  90000),
    ('economica',  0,   6, 420000, 150000),  -- last minute
    ('business',   0, 365, 890000, 200000)
) AS t(clase, amin, amax, base, penal);

-- -----------------------------------------------------------------------------
--  Instancias de vuelo (el hecho): próximos 30 días
--  capacidad_vendible = f(capacidad_física, política)   ← FR-17
-- -----------------------------------------------------------------------------
INSERT INTO instancia_vuelo (id_vuelo_prog, fecha_operacion, matricula,
                             capacidad_vendible_eco, capacidad_vendible_bus)
SELECT vp.id_vuelo_prog,
       d.fecha,
       av.matricula,
       FLOOR(av.capacidad_fisica_eco * pc.factor_sobreventa)::INT,
       FLOOR(av.capacidad_fisica_bus * pc.factor_sobreventa)::INT
FROM vuelo_programado vp
CROSS JOIN generate_series(CURRENT_DATE, CURRENT_DATE + 29, INTERVAL '1 day') AS d(fecha)
CROSS JOIN LATERAL (
    SELECT matricula, capacidad_fisica_eco, capacidad_fisica_bus
    FROM aeronave
    ORDER BY (vp.id_vuelo_prog + EXTRACT(DAY FROM d.fecha)::INT) % 4, matricula
    LIMIT 1
) av
CROSS JOIN (SELECT factor_sobreventa FROM politica_capacidad WHERE ambito='global' LIMIT 1) pc
-- sólo los días en que el vuelo opera, según la máscara LMXJVSD
WHERE SUBSTRING(vp.dias_operacion FROM
        CASE EXTRACT(ISODOW FROM d.fecha)::INT
             WHEN 1 THEN 1 WHEN 2 THEN 2 WHEN 3 THEN 3 WHEN 4 THEN 4
             WHEN 5 THEN 5 WHEN 6 THEN 6 ELSE 7 END FOR 1) <> '-';

-- -----------------------------------------------------------------------------
--  Clientes y canales
-- -----------------------------------------------------------------------------
INSERT INTO pasajero (tipo_documento, numero_documento, nombre, apellido, email, telefono) VALUES
  ('CC','1020304050','Andrea','Restrepo','andrea.restrepo@example.com','+57 300 1112233'),
  ('CC','1020304051','Camilo','Ospina',  'camilo.ospina@example.com',  '+57 300 2223344'),
  ('CC','1020304052','Valeria','Cárdenas','valeria.cardenas@example.com','+57 300 3334455'),
  ('CC','1020304053','Julián','Mesa',    'julian.mesa@example.com',    '+57 300 4445566'),
  ('PA','X9988776',  'Sofía', 'Navarro', 'sofia.navarro@example.com',  '+1 305 5556677');

INSERT INTO agencia (nombre, nit, porcentaje_comision, descuento_negociado, minutos_retencion) VALUES
  ('Viajes Andinos S.A.S.', '900123456-1', 7.00, 4.00, 1440),   -- FR-15: 24 h
  ('Turismo Caribe Ltda.',  '900654321-7', 5.50, 2.50,  720);   -- 12 h

COMMIT;

-- =============================================================================
--  Instancia de prueba para la demostración de concurrencia (NFR-CONC-01)
--  Se deja UN solo asiento vendible en económica: es el escenario del enunciado
--  ("dos pasajeros intentan reservar el último asiento al mismo tiempo").
-- =============================================================================
UPDATE instancia_vuelo
   SET capacidad_vendible_eco     = 1,
       asientos_comprometidos_eco = 0
 WHERE id_instancia = (
       SELECT iv.id_instancia
         FROM instancia_vuelo iv
         JOIN vuelo_programado vp ON vp.id_vuelo_prog = iv.id_vuelo_prog
        WHERE vp.numero_vuelo = 'AV8020'
          AND iv.fecha_operacion >= CURRENT_DATE + 7
        ORDER BY iv.fecha_operacion
        LIMIT 1);
