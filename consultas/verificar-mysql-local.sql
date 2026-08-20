-- =============================================================
--  Verificacion del MySQL local en Cloud9  (vs la RDS)
--  Correr las mismas consultas en las DOS conexiones y comparar.
-- =============================================================

-- 1) Donde estoy conectado
--    USER() muestra la IP desde la que entraste: prueba que la
--    conexion vino de afuera y no de la propia maquina.
SELECT @@hostname     AS servidor,
       VERSION()      AS version,
       USER()         AS conectado_como,
       @@bind_address AS escuchando;

-- 2) Sakila completa
SELECT (SELECT COUNT(*) FROM film)   AS peliculas,    -- 1000
       (SELECT COUNT(*) FROM rental) AS alquileres,   -- 16044
       (SELECT COUNT(*) FROM actor)  AS actores;      -- 200

-- 3) EL DIFERENCIAL
--    Cloud9 (sos admin, tenes SUPER):  3 funciones, 6 triggers
--    RDS    (base gestionada):         0 funciones, 0 triggers
SELECT (SELECT COUNT(*) FROM information_schema.ROUTINES
        WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_TYPE='FUNCTION') AS funciones,
       (SELECT COUNT(*) FROM information_schema.TRIGGERS
        WHERE TRIGGER_SCHEMA='sakila')                             AS triggers;

-- Detalle de que hay exactamente
SELECT ROUTINE_NAME AS funcion FROM information_schema.ROUTINES
WHERE ROUTINE_SCHEMA='sakila' AND ROUTINE_TYPE='FUNCTION';

SELECT TRIGGER_NAME AS disparador, EVENT_OBJECT_TABLE AS tabla,
       ACTION_TIMING AS momento, EVENT_MANIPULATION AS evento
FROM information_schema.TRIGGERS WHERE TRIGGER_SCHEMA='sakila';

-- 4) LA PRUEBA DEFINITIVA
--    En la RDS esto NO se puede ejecutar: las funciones no existen.
--    Devuelve: FUNCTION sakila.inventory_in_stock does not exist
SELECT inventory_in_stock(1)          AS hay_stock,
       get_customer_balance(1, NOW()) AS saldo_cliente_1;

-- 5) Y el privilegio que lo explica todo.
--    Aca aparece SUPER (o ALL PRIVILEGES). En RDS, nunca.
SHOW GRANTS FOR CURRENT_USER();
