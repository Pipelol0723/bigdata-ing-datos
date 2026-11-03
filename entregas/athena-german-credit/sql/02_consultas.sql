-- German Credit: preguntas de negocio sobre la vista german_credit.solicitudes.
-- SQL compatible con Athena (Trino) y con DuckDB, para probarlo gratis en la laptop antes de correrlo.
-- "Tasa de malos" = % de solicitantes clasificados como malos pagadores (clase 2).

-- Q01 Tamaño del dataset y balance de clases
SELECT riesgo, count(*) AS solicitudes,
       round(100.0 * count(*) / sum(count(*)) OVER (), 1) AS pct
FROM solicitudes GROUP BY riesgo ORDER BY riesgo;

-- Q02 Tasa de malos según el estado de la cuenta corriente
SELECT cuenta, count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY cuenta ORDER BY cuenta;

-- Q03 Tasa de malos según el historial de crédito
SELECT historial, count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY historial ORDER BY pct_malos DESC;

-- Q04 Propósito del crédito: volumen, monto promedio y tasa de malos
SELECT proposito, count(*) AS solicitudes, round(avg(monto_dm)) AS monto_promedio_dm,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY proposito ORDER BY solicitudes DESC;

-- Q05 Plazo del crédito en tramos
SELECT CASE WHEN duracion_meses <= 12 THEN '1. hasta 12 meses'
            WHEN duracion_meses <= 24 THEN '2. 13 a 24 meses'
            WHEN duracion_meses <= 36 THEN '3. 25 a 36 meses'
            ELSE '4. más de 36 meses' END AS plazo,
       count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY 1 ORDER BY 1;

-- Q06 Monto del crédito por cuartiles
WITH q AS (SELECT *, ntile(4) OVER (ORDER BY monto_dm) AS cuartil FROM solicitudes)
SELECT cuartil, min(monto_dm) AS desde_dm, max(monto_dm) AS hasta_dm, count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM q GROUP BY cuartil ORDER BY cuartil;

-- Q07 Edad en tramos
SELECT CASE WHEN edad <= 25 THEN '1. 19 a 25' WHEN edad <= 35 THEN '2. 26 a 35'
            WHEN edad <= 50 THEN '3. 36 a 50' ELSE '4. más de 50' END AS edad_tramo,
       count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY 1 ORDER BY 1;

-- Q08 Ahorros
SELECT ahorros, count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY ahorros ORDER BY ahorros;

-- Q09 Antigüedad en el empleo
SELECT antiguedad_empleo, count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY antiguedad_empleo ORDER BY antiguedad_empleo;

-- Q10 Vivienda y propiedad
SELECT vivienda, propiedad, count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY vivienda, propiedad HAVING count(*) >= 20 ORDER BY pct_malos DESC;

-- Q11 Perfil numérico promedio de buenos y malos pagadores
SELECT riesgo, round(avg(duracion_meses), 1) AS plazo_meses, round(avg(monto_dm)) AS monto_dm,
       round(avg(edad), 1) AS edad, round(avg(tasa_cuota_pct), 2) AS cuota_pct_ingreso,
       round(avg(creditos_banco), 2) AS creditos_en_el_banco
FROM solicitudes GROUP BY riesgo ORDER BY riesgo;

-- Q12 Perfil de mayor riesgo: saldo negativo o bajo en la cuenta corriente y plazo mayor a 24 meses
SELECT CASE WHEN cuenta IN ('1. < 0 DM', '2. 0 a 200 DM') AND duracion_meses > 24
            THEN 'saldo bajo y plazo > 24 meses' ELSE 'resto' END AS perfil,
       count(*) AS solicitudes,
       round(100 * avg(CASE WHEN riesgo = 'malo' THEN 1.0 ELSE 0 END), 1) AS pct_malos
FROM solicitudes GROUP BY 1 ORDER BY pct_malos DESC;

-- Q13 Matriz de costos de la UCI (aprobar a un malo cuesta 5, rechazar a un bueno cuesta 1): cuatro políticas
-- Aprobar a un segmento con tasa de malos p cuesta 5p y rechazarlo, 1-p: conviene aprobar sólo si p < 1/6.
-- Por Q02, el único segmento de la cuenta corriente por debajo de 16,7 % es "sin cuenta" (política D).
WITH politicas AS (
  SELECT riesgo, 'A. aprobar a todos' AS politica, false AS rechaza FROM solicitudes
  UNION ALL
  SELECT riesgo, 'B. rechazar a todos', true FROM solicitudes
  UNION ALL
  SELECT riesgo, 'C. rechazar si la cuenta tiene < 200 DM', cuenta IN ('1. < 0 DM', '2. 0 a 200 DM')
  FROM solicitudes
  UNION ALL
  SELECT riesgo, 'D. aprobar sólo sin cuenta corriente (p < 1/6)', cuenta <> '4. sin cuenta'
  FROM solicitudes)
SELECT politica,
       sum(CASE WHEN riesgo = 'malo' AND NOT rechaza THEN 1 ELSE 0 END) AS malos_aprobados,
       sum(CASE WHEN riesgo = 'bueno' AND rechaza THEN 1 ELSE 0 END) AS buenos_rechazados,
       5 * sum(CASE WHEN riesgo = 'malo' AND NOT rechaza THEN 1 ELSE 0 END)
         + sum(CASE WHEN riesgo = 'bueno' AND rechaza THEN 1 ELSE 0 END) AS costo_total
FROM politicas GROUP BY politica ORDER BY politica;
