-- =============================================================
--  Comprobar que Cloud9 y DBeaver pegan al MISMO servidor MySQL
--  Correr en AMBAS conexiones y comparar.
-- =============================================================

-- Que campos comparar y cuales NO
--
--   @@hostname     -> IGUAL en las dos   (identifica al servidor)
--   @@server_uuid  -> IGUAL en las dos   (id unico del servidor: la prueba)
--   @@port         -> IGUAL en las dos
--   USER()         -> DISTINTO, y esta bien: identifica al CLIENTE
--
-- Comparar USER() es el error tipico: no dice quien es el servidor,
-- dice desde donde entraste.
SELECT @@hostname    AS servidor,
       @@port        AS puerto,
       @@server_uuid AS id_unico,
       USER()        AS quien_soy,
       @@bind_address AS escuchando;


-- =============================================================
--  LA DEMOSTRACION EN UNA SOLA CAPTURA
--  Con DBeaver conectado, correr esto desde la terminal de Cloud9.
--  El servidor lista las dos conexiones a la vez:
--    - una desde localhost (el socket, la terminal)
--    - otra desde tu IP de casa (DBeaver, por el 3306)
-- =============================================================
SELECT id, user, host, db, command, time
FROM information_schema.PROCESSLIST
ORDER BY id;


-- Las tres IPs en juego, para no confundirlas:
--   172.31.76.95    IP privada de la instancia
--   3.236.77.57     IP publica de la instancia (la de DBeaver)
--   192.144.114.77  la IP del alumno, en su casa
