-- =============================================================
--  Clientes con su ciudad y pais
--  Cadena: customer -> address -> city -> country
--  (customer NO tiene city_id: hay que pasar por address)
-- =============================================================

-- 1. Listado completo
SELECT co.country   AS pais,
       ci.city      AS ciudad,
       c.first_name AS nombre,
       c.last_name  AS apellido
FROM customer c
JOIN address a  ON a.address_id  = c.address_id
JOIN city    ci ON ci.city_id    = a.city_id
JOIN country co ON co.country_id = ci.country_id
ORDER BY co.country, ci.city, c.last_name;


-- 2. Filtrado por pais
SELECT co.country AS pais, ci.city AS ciudad,
       c.first_name, c.last_name
FROM customer c
JOIN address a  ON a.address_id  = c.address_id
JOIN city    ci ON ci.city_id    = a.city_id
JOIN country co ON co.country_id = ci.country_id
WHERE co.country = 'Argentina'
ORDER BY ci.city, c.last_name;


-- 3. Filtrado por pais Y ciudad
SELECT c.first_name, c.last_name, c.email
FROM customer c
JOIN address a  ON a.address_id  = c.address_id
JOIN city    ci ON ci.city_id    = a.city_id
JOIN country co ON co.country_id = ci.country_id
WHERE co.country = 'Argentina'
  AND ci.city    = 'Almirante Brown';


-- 4. Cuantos clientes por pais (agregacion sobre la misma cadena)
SELECT co.country AS pais, COUNT(*) AS clientes
FROM customer c
JOIN address a  ON a.address_id  = c.address_id
JOIN city    ci ON ci.city_id    = a.city_id
JOIN country co ON co.country_id = ci.country_id
GROUP BY co.country
ORDER BY clientes DESC;


-- 5. Ver que valores existen antes de filtrar
SELECT country FROM country ORDER BY country;     -- 109 paises
SELECT city    FROM city    ORDER BY city;        -- 600 ciudades


-- NOTA: staff y store llegan a la ciudad por la MISMA cadena,
-- porque los tres (customer, staff, store) tienen address_id.
-- Ejemplo con las tiendas:
SELECT s.store_id, ci.city, co.country
FROM store   s
JOIN address a  ON a.address_id  = s.address_id
JOIN city    ci ON ci.city_id    = a.city_id
JOIN country co ON co.country_id = ci.country_id;
