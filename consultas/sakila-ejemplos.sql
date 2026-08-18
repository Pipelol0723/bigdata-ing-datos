-- =============================================================
--  Sakila: consultas de ejemplo, de menor a mayor dificultad
--  Base: db-service.cvbllouimnrr.us-east-1.rds.amazonaws.com
-- =============================================================

USE sakila;

-- -------------------------------------------------------------
-- 0. RECONOCIMIENTO DEL TERRENO
-- -------------------------------------------------------------
SHOW TABLES;                    -- 16 tablas + 7 vistas
DESCRIBE film;                  -- columnas y tipos de una tabla
SELECT COUNT(*) FROM film;      -- 1000 peliculas
SELECT COUNT(*) FROM rental;    -- 16044 alquileres
SELECT COUNT(*) FROM payment;   -- 16049 pagos


-- -------------------------------------------------------------
-- 1. SELECT basico: filtrar y ordenar
-- -------------------------------------------------------------
-- Peliculas mas largas que 2 horas, las 10 primeras
SELECT title, length, rating
FROM film
WHERE length > 120
ORDER BY length DESC
LIMIT 10;

-- Clientes activos de una ciudad (LIKE para busqueda parcial)
SELECT first_name, last_name, email
FROM customer
WHERE active = 1 AND last_name LIKE 'S%'
ORDER BY last_name;


-- -------------------------------------------------------------
-- 2. AGREGACION: GROUP BY + HAVING
-- -------------------------------------------------------------
-- Cuantas peliculas hay por clasificacion
SELECT rating, COUNT(*) AS cantidad, ROUND(AVG(length), 1) AS duracion_promedio
FROM film
GROUP BY rating
ORDER BY cantidad DESC;

-- Diferencia clave: WHERE filtra FILAS antes de agrupar,
-- HAVING filtra GRUPOS despues de agregar.
SELECT rating, AVG(rental_rate) AS precio_promedio
FROM film
WHERE length > 90              -- descarta peliculas cortas
GROUP BY rating
HAVING AVG(rental_rate) > 2.5; -- descarta grupos baratos


-- -------------------------------------------------------------
-- 3. JOIN de dos tablas
-- -------------------------------------------------------------
-- Pagos con el nombre del cliente
SELECT c.first_name, c.last_name, p.amount, p.payment_date
FROM payment p
JOIN customer c ON c.customer_id = p.customer_id
ORDER BY p.payment_date DESC
LIMIT 20;


-- -------------------------------------------------------------
-- 4. JOIN encadenado: relacion muchos-a-muchos
-- -------------------------------------------------------------
-- film y category se relacionan a traves de film_category.
-- Esa tabla del medio existe justamente porque una pelicula
-- puede tener varias categorias y una categoria varias peliculas.
SELECT cat.name AS categoria, COUNT(*) AS peliculas
FROM film f
JOIN film_category fc ON fc.film_id  = f.film_id
JOIN category      cat ON cat.category_id = fc.category_id
GROUP BY cat.name
ORDER BY peliculas DESC;

-- Los 10 actores con mas peliculas
SELECT a.first_name, a.last_name, COUNT(*) AS peliculas
FROM actor a
JOIN film_actor fa ON fa.actor_id = a.actor_id
GROUP BY a.actor_id, a.first_name, a.last_name
ORDER BY peliculas DESC
LIMIT 10;


-- -------------------------------------------------------------
-- 5. LA CADENA COMPLETA (la consulta "de parcial")
-- -------------------------------------------------------------
-- Recorrido: pais -> ciudad -> direccion -> cliente -> pago
-- Cinco JOIN para responder "cuanto factura cada pais".
SELECT co.country                AS pais,
       COUNT(DISTINCT c.customer_id) AS clientes,
       ROUND(SUM(p.amount), 2)   AS facturacion
FROM payment  p
JOIN customer c  ON c.customer_id = p.customer_id
JOIN address  a  ON a.address_id  = c.address_id
JOIN city     ci ON ci.city_id    = a.city_id
JOIN country  co ON co.country_id = ci.country_id
GROUP BY co.country
ORDER BY facturacion DESC
LIMIT 15;


-- -------------------------------------------------------------
-- 6. SUBCONSULTAS
-- -------------------------------------------------------------
-- Peliculas mas caras que el promedio general
SELECT title, rental_rate
FROM film
WHERE rental_rate > (SELECT AVG(rental_rate) FROM film)
ORDER BY rental_rate DESC
LIMIT 10;

-- Clientes que nunca alquilaron (LEFT JOIN + IS NULL)
SELECT c.customer_id, c.first_name, c.last_name
FROM customer c
LEFT JOIN rental r ON r.customer_id = c.customer_id
WHERE r.rental_id IS NULL;


-- -------------------------------------------------------------
-- 7. FECHAS
-- -------------------------------------------------------------
-- Facturacion mes a mes
SELECT DATE_FORMAT(payment_date, '%Y-%m') AS mes,
       COUNT(*)                AS operaciones,
       ROUND(SUM(amount), 2)   AS total
FROM payment
GROUP BY mes
ORDER BY mes;

-- Alquileres que se devolvieron tarde
SELECT r.rental_id, f.title,
       DATEDIFF(r.return_date, r.rental_date) AS dias_afuera,
       f.rental_duration                      AS dias_permitidos
FROM rental    r
JOIN inventory i ON i.inventory_id = r.inventory_id
JOIN film      f ON f.film_id      = i.film_id
WHERE r.return_date IS NOT NULL
  AND DATEDIFF(r.return_date, r.rental_date) > f.rental_duration
ORDER BY dias_afuera DESC
LIMIT 20;


-- -------------------------------------------------------------
-- 8. VISTAS (ya vienen creadas con Sakila)
-- -------------------------------------------------------------
SELECT * FROM sales_by_film_category;
SELECT * FROM film_list LIMIT 10;


-- =============================================================
--  ⚠️  NO FUNCIONAN EN ESTA BASE
--  Las funciones de Sakila no se crearon (ERROR 1419: RDS no
--  otorga SUPER y el binlog esta activo). El profesor dijo que
--  se dejara asi, pero estas llamadas van a fallar:
--      inventory_in_stock(...)
--      get_customer_balance(...)
--      inventory_held_by_customer(...)
--  Todo lo de arriba usa SQL puro y anda sin problema.
-- =============================================================


-- =============================================================
--  CONSIGNA: listar el nombre de las peliculas por su idioma
-- =============================================================

-- Version pedida: una fila por pelicula, con su idioma
SELECT l.name  AS idioma,
       f.title AS pelicula
FROM film f
JOIN language l ON l.language_id = f.language_id
ORDER BY l.name, f.title;

-- ⚠️ OJO: en Sakila las 1000 peliculas tienen language_id = 1,
-- o sea que TODAS figuran en ingles. El resultado no esta mal:
-- el dataset de ejemplo se cargo asi. Esta consulta lo demuestra.
SELECT l.language_id, l.name AS idioma, COUNT(f.film_id) AS peliculas
FROM language l
LEFT JOIN film f ON f.language_id = l.language_id   -- LEFT: muestra
GROUP BY l.language_id, l.name                      -- los idiomas
ORDER BY peliculas DESC;                            -- con 0 peliculas

-- Variante compacta: un renglon por idioma con los titulos juntos.
-- Requiere subir group_concat_max_len o trunca en 1024 caracteres.
SET SESSION group_concat_max_len = 1000000;
SELECT l.name AS idioma,
       COUNT(*) AS cantidad,
       GROUP_CONCAT(f.title ORDER BY f.title SEPARATOR ', ') AS peliculas
FROM film f
JOIN language l ON l.language_id = f.language_id
GROUP BY l.name;
