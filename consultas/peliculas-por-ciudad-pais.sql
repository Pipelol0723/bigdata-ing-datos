-- =============================================================
--  Peliculas con ciudad y pais
--
--  Una pelicula NO tiene ciudad. Hay dos caminos para llegar,
--  y responden preguntas distintas:
--
--    A) film -> inventory -> store    -> address -> city -> country
--       "donde esta disponible la pelicula"
--
--    B) film -> inventory -> rental -> customer -> address -> city -> country
--       "donde se alquilo / de donde son los que la alquilan"
--
--  Los dos arrancan por inventory porque lo que se alquila es una
--  COPIA FISICA, no el titulo. Se bifurcan despues: la copia
--  pertenece a una tienda, pero la alquilo un cliente.
-- =============================================================

-- -------------------------------------------------------------
-- A) Donde esta disponible cada pelicula
--    DISTINCT: cada tienda tiene varias copias en inventory,
--    sin el cada titulo se repite una vez por copia.
--    OJO: Sakila tiene solo 2 tiendas -> solo 2 ciudades.
-- -------------------------------------------------------------
SELECT DISTINCT
       f.title    AS pelicula,
       co.country AS pais,
       ci.city    AS ciudad
FROM film      f
JOIN inventory i  ON i.film_id     = f.film_id
JOIN store     s  ON s.store_id    = i.store_id
JOIN address   a  ON a.address_id  = s.address_id
JOIN city      ci ON ci.city_id    = a.city_id
JOIN country   co ON co.country_id = ci.country_id
ORDER BY f.title;


-- -------------------------------------------------------------
-- B) Donde se alquilo cada pelicula  (109 paises, 600 ciudades)
-- -------------------------------------------------------------
SELECT f.title    AS pelicula,
       co.country AS pais,
       ci.city    AS ciudad,
       COUNT(*)   AS alquileres
FROM film      f
JOIN inventory i  ON i.film_id      = f.film_id
JOIN rental    r  ON r.inventory_id = i.inventory_id
JOIN customer  c  ON c.customer_id  = r.customer_id
JOIN address   a  ON a.address_id   = c.address_id
JOIN city      ci ON ci.city_id     = a.city_id
JOIN country   co ON co.country_id  = ci.country_id
GROUP BY f.title, co.country, ci.city
ORDER BY f.title, alquileres DESC;


-- -------------------------------------------------------------
-- B2) Filtrado: peliculas alquiladas en un pais concreto
-- -------------------------------------------------------------
SELECT f.title AS pelicula, ci.city AS ciudad, COUNT(*) AS alquileres
FROM film      f
JOIN inventory i  ON i.film_id      = f.film_id
JOIN rental    r  ON r.inventory_id = i.inventory_id
JOIN customer  c  ON c.customer_id  = r.customer_id
JOIN address   a  ON a.address_id   = c.address_id
JOIN city      ci ON ci.city_id     = a.city_id
JOIN country   co ON co.country_id  = ci.country_id
WHERE co.country = 'Argentina'
GROUP BY f.title, ci.city
ORDER BY alquileres DESC, f.title;


-- -------------------------------------------------------------
-- Verificacion: cuantas tiendas hay y donde estan
-- -------------------------------------------------------------
SELECT s.store_id, ci.city AS ciudad, co.country AS pais
FROM store   s
JOIN address a  ON a.address_id  = s.address_id
JOIN city    ci ON ci.city_id    = a.city_id
JOIN country co ON co.country_id = ci.country_id;
