-- =============================================================================
--  Actividad transaccional de demostración
--  Genera un histórico de reservas con estados variados para que el OLAP
--  tenga qué analizar: ocupación, ingresos por tarifa y cancelaciones.
-- =============================================================================
--  Se genera por SQL y no por la API a propósito: acá hace falta CONTROLAR la
--  distribución de estados y fechas para que los reportes de FR-19 muestren
--  algo interpretable. La API ya quedó probada aparte (prueba_concurrencia.py).
-- =============================================================================

SET search_path TO reservas;

DO $$
DECLARE
    v_instancia   RECORD;
    v_id_reserva  BIGINT;
    v_id_itin     BIGINT;
    v_id_tarifa   BIGINT;
    v_precio      NUMERIC(12,2);
    v_estado      estado_reserva;
    v_agencia     BIGINT;
    v_pasajero    BIGINT;
    v_creada      TIMESTAMPTZ;
    v_clase       clase_servicio;
    v_n           INT;
    v_i           INT;
    v_pnr         TEXT;
    v_clase_txt   TEXT;
BEGIN
    -- Recorre una muestra de instancias y les genera demanda
    FOR v_instancia IN
        SELECT iv.id_instancia, iv.id_vuelo_prog, iv.fecha_operacion,
               iv.capacidad_vendible_eco, iv.capacidad_vendible_bus
          FROM instancia_vuelo iv
         WHERE iv.capacidad_vendible_eco > 10          -- excluye la de la prueba
         ORDER BY iv.id_instancia
         LIMIT 120
    LOOP
        -- La demanda se genera POR CLASE y acotada a la capacidad de esa clase.
        -- Generar sin ese tope produce sobreventa en business (12 asientos)
        -- aunque en económica sobre lugar: el invariante es por clase, no global.
        FOREACH v_clase_txt IN ARRAY ARRAY['economica','business'] LOOP
        v_clase := v_clase_txt::clase_servicio;

        v_n := CASE v_clase_txt
                 WHEN 'economica' THEN
                   GREATEST(1, FLOOR(v_instancia.capacidad_vendible_eco
                                     * (0.10 + random() * 0.75))::INT)
                 ELSE
                   FLOOR(v_instancia.capacidad_vendible_bus
                         * (0.05 + random() * 0.60))::INT
               END;

        FOR v_i IN 1..v_n LOOP
            -- Mezcla de estados: mayoría confirmadas, algunas canceladas/expiradas
            v_estado := CASE
                WHEN random() < 0.78 THEN 'confirmada'::estado_reserva
                WHEN random() < 0.60 THEN 'cancelada'::estado_reserva
                ELSE 'expirada'::estado_reserva END;

            -- 30% de las ventas vienen por agencia (FR-13/14)
            v_agencia  := CASE WHEN random() < 0.30
                               THEN (SELECT id_agencia FROM agencia
                                      ORDER BY random() LIMIT 1) END;
            v_pasajero := (SELECT id_pasajero FROM pasajero ORDER BY random() LIMIT 1);

            -- Fecha de compra: entre 1 y 45 días antes del vuelo
            v_creada := (v_instancia.fecha_operacion
                         - (1 + floor(random() * 45))::INT)::TIMESTAMPTZ
                        + (random() * INTERVAL '18 hours');

            SELECT id_tarifa, precio_base INTO v_id_tarifa, v_precio
              FROM tarifa
             WHERE id_vuelo_prog = v_instancia.id_vuelo_prog AND clase = v_clase
             ORDER BY random() LIMIT 1;
            CONTINUE WHEN v_id_tarifa IS NULL;

            -- El PNR son 6 caracteres: con miles de reservas la colisión es
            -- probable (paradoja del cumpleaños). Se reintenta hasta encontrar
            -- uno libre, que es lo que hacen los sistemas de reservas reales.
            LOOP
                BEGIN
                    v_pnr := upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6));
                    INSERT INTO reserva (codigo_reserva, id_pasajero, id_agencia, estado,
                                         creada_en, expira_en, monto_total, moneda)
                    VALUES (v_pnr, v_pasajero, v_agencia, v_estado, v_creada,
                            CASE WHEN v_estado = 'retenida'
                                 THEN v_creada + INTERVAL '30 minutes' END,
                            v_precio, 'COP')
                    RETURNING id_reserva INTO v_id_reserva;
                    EXIT;
                EXCEPTION WHEN unique_violation THEN
                    NULL;  -- PNR ya usado: se prueba con otro
                END;
            END LOOP;

            INSERT INTO itinerario (id_reserva, sentido, orden)
            VALUES (v_id_reserva, 'ida', 1) RETURNING id_itinerario INTO v_id_itin;

            INSERT INTO tramo (id_itinerario, id_instancia, orden, clase,
                               id_tarifa, precio_aplicado)
            VALUES (v_id_itin, v_instancia.id_instancia, 1, v_clase,
                    v_id_tarifa, v_precio);

            -- NFR-AUD-01: historial append-only
            INSERT INTO historial_reserva (id_reserva, estado_anterior, estado_nuevo,
                                           actor_tipo, motivo, ocurrido_en)
            VALUES (v_id_reserva, NULL, 'retenida',
                    CASE WHEN v_agencia IS NULL THEN 'pasajero' ELSE 'agencia' END,
                    'creación', v_creada);

            IF v_estado <> 'retenida' THEN
                INSERT INTO historial_reserva (id_reserva, estado_anterior, estado_nuevo,
                                               actor_tipo, motivo, ocurrido_en)
                VALUES (v_id_reserva, 'retenida', v_estado, 'sistema',
                        CASE v_estado WHEN 'confirmada' THEN 'pago acreditado'
                                      WHEN 'cancelada'  THEN 'cancelación del pasajero'
                                      ELSE 'vencimiento del hold' END,
                        v_creada + INTERVAL '15 minutes');
            END IF;

            -- Pago y comisión sólo para las confirmadas
            IF v_estado = 'confirmada' THEN
                INSERT INTO pago (id_reserva, id_transaccion_pasarela, estado, monto, registrado_en)
                VALUES (v_id_reserva, 'txn_' || v_id_reserva::text, 'aprobado', v_precio,
                        v_creada + INTERVAL '10 minutes');

                IF v_agencia IS NOT NULL THEN
                    INSERT INTO comision (id_reserva, id_agencia, monto)
                    SELECT v_id_reserva, v_agencia,
                           ROUND(v_precio * a.porcentaje_comision / 100, 2)
                      FROM agencia a WHERE a.id_agencia = v_agencia;
                END IF;
            END IF;
        END LOOP;
        END LOOP;   -- cierra el FOREACH por clase
    END LOOP;
END $$;

-- -----------------------------------------------------------------------------
--  Recalcular el inventario desde los tramos vivos.
--  Sólo las reservas retenidas o confirmadas ocupan asiento: las canceladas y
--  expiradas ya lo devolvieron.
-- -----------------------------------------------------------------------------
UPDATE instancia_vuelo iv
   SET asientos_comprometidos_eco = COALESCE(v.eco, 0),
       asientos_comprometidos_bus = COALESCE(v.bus, 0)
  FROM (
    SELECT t.id_instancia,
           count(*) FILTER (WHERE t.clase = 'economica') AS eco,
           count(*) FILTER (WHERE t.clase = 'business')  AS bus
      FROM tramo t
      JOIN itinerario i ON i.id_itinerario = t.id_itinerario
      JOIN reserva r    ON r.id_reserva = i.id_reserva
     WHERE r.estado IN ('retenida','confirmada')
     GROUP BY t.id_instancia
  ) v
 WHERE iv.id_instancia = v.id_instancia;

-- Verificación: el invariante FR-07 debe seguir cumpliéndose en todas las filas
SELECT count(*) AS filas_que_violan_el_invariante
  FROM instancia_vuelo
 WHERE asientos_comprometidos_eco > capacidad_vendible_eco
    OR asientos_comprometidos_bus > capacidad_vendible_bus;
