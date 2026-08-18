-- =============================================================
--  Las dos sintaxis de JOIN, y que pasa si falta la condicion
-- =============================================================

-- (1) SINTAXIS VIEJA: tablas separadas por coma, condicion en el WHERE
SELECT l.name AS idioma, f.title AS pelicula
FROM film f, language l
WHERE f.language_id = l.language_id
ORDER BY l.name, f.title;

-- (2) SINTAXIS EXPLICITA (SQL-92): condicion en el ON
--     Mismo resultado y mismo plan de ejecucion que (1).
SELECT l.name AS idioma, f.title AS pelicula
FROM film f
JOIN language l ON l.language_id = f.language_id
ORDER BY l.name, f.title;


-- =============================================================
--  (3) SIN LA CONDICION -> PRODUCTO CARTESIANO
--      Combina CADA pelicula con CADA idioma: 1000 x 6 = 6000.
--      No da error. Devuelve basura, en silencio.
-- =============================================================
SELECT l.name AS idioma, f.title AS pelicula
FROM film f, language l
ORDER BY f.title, l.name;

-- La demostracion numerica
SELECT (SELECT COUNT(*) FROM film)          AS peliculas,   -- 1000
       (SELECT COUNT(*) FROM language)      AS idiomas,     -- 6
       (SELECT COUNT(*) FROM film, language) AS cartesiano; -- 6000

-- Ver un solo titulo repetido 6 veces
SELECT f.title, l.name AS idioma
FROM film f, language l
WHERE f.title = 'ACADEMY DINOSAUR'
ORDER BY l.name;


-- =============================================================
--  POR QUE IMPORTA
--
--  Con la sintaxis vieja, olvidar la condicion NO da error:
--  la consulta corre y devuelve un resultado enorme y erroneo.
--  Con 3 tablas de 1.000.000 de filas eso es 10^18 filas.
--
--  Con la sintaxis explicita, JOIN sin ON es error de sintaxis:
--  no se puede olvidar por accidente.
--
--  Y si el cartesiano se quiere a proposito, se pide por su
--  nombre, dejando la intencion escrita:
-- =============================================================
SELECT l.name AS idioma, f.title AS pelicula
FROM film f
CROSS JOIN language l
ORDER BY f.title, l.name;
