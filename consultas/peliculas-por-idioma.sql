-- Peliculas listadas por idioma.
-- En Sakila las 1000 tienen language_id = 1, asi que salen todas en ingles.

SELECT l.name  AS idioma,
       f.title AS pelicula
FROM film f
JOIN language l ON l.language_id = f.language_id
ORDER BY l.name, f.title;
