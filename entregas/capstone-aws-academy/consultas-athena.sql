-- =============================================================================
--  Capstone · consultas de Athena, en el orden de la guía (pasos 14, 15, 20 a 23)
-- =============================================================================
--  Tabla que crea el crawler: data_source_23719 (el bucket data-source-23719 con "_" en vez de "-").
--  Antes de la primera: Athena > Settings > Manage > s3://query-results-12481/
-- =============================================================================

-- ---- paso 14 (con GLOBAL + HighSeas): 2 filas, 'Pacific, Western Central' y NULL
SELECT DISTINCT area_name FROM fishdb.data_source_23719;

-- ---- paso 15: <FMI_1> = fishdb.data_source_23719, <FMI_2> = 2000 ("since 2001")
SELECT year, fishing_entity AS Country, CAST(CAST(SUM(landed_value) AS DOUBLE) AS DECIMAL(38,2)) AS ValuePacificWCSeasCatch
FROM fishdb.data_source_23719
WHERE area_name LIKE '%Pacific%' and fishing_entity='Fiji' AND year > 2000
GROUP BY year, fishing_entity
ORDER By year;

-- ---- paso 15, Challenge: Fiji en TODA la alta mar desde 2001. Las filas de GLOBAL no tienen area_name.
--      Se guarda como vista "challenge" (equivale a Create > View from query).
CREATE OR REPLACE VIEW challenge AS
SELECT year, fishing_entity AS Country, CAST(CAST(SUM(landed_value) AS DOUBLE) AS DECIMAL(38,2)) AS ValueAllHighSeasCatch
FROM fishdb.data_source_23719
WHERE area_name IS NULL AND fishing_entity='Fiji' AND year > 2000
GROUP BY year, fishing_entity
ORDER BY year;

-- ---- paso 20 (después de subir el EEZ y volver a correr el crawler): ahora 3 filas
SELECT DISTINCT area_name FROM fishdb.data_source_23719;

SELECT year, fishing_entity AS Country, CAST(CAST(SUM(landed_value) AS DOUBLE) AS DECIMAL(38,2)) AS ValueOpenSeasCatch
FROM fishdb.data_source_23719
WHERE area_name IS NULL AND fishing_entity='Fiji' AND year > 2000
GROUP BY year, fishing_entity
ORDER By year;

SELECT year, fishing_entity AS Country, CAST(CAST(SUM(landed_value) AS DOUBLE) AS DECIMAL(38,2)) AS ValueEEZCatch
FROM fishdb.data_source_23719
WHERE area_name LIKE '%Fiji%' AND fishing_entity='Fiji' AND year > 2000
GROUP BY year, fishing_entity
ORDER By year;

SELECT year, fishing_entity AS Country, CAST(CAST(SUM(landed_value) AS DOUBLE) AS DECIMAL(38,2)) AS ValueEEZAndOpenSeasCatch
FROM fishdb.data_source_23719
WHERE (area_name LIKE '%Fiji%' OR area_name IS NULL) AND fishing_entity='Fiji' AND year > 2000
GROUP BY year, fishing_entity
ORDER By year;

-- ---- paso 20, Analysis: alta mar + EEZ = total, año por año (la diferencia tiene que dar 0.00)
WITH a AS (SELECT year,
             CAST(SUM(CASE WHEN area_name IS NULL THEN landed_value ELSE 0 END) AS DECIMAL(38,2)) AS open_seas,
             CAST(SUM(CASE WHEN area_name LIKE '%Fiji%' THEN landed_value ELSE 0 END) AS DECIMAL(38,2)) AS eez,
             CAST(SUM(landed_value) AS DECIMAL(38,2)) AS total
           FROM fishdb.data_source_23719
           WHERE (area_name LIKE '%Fiji%' OR area_name IS NULL) AND fishing_entity='Fiji' AND year > 2000
           GROUP BY year)
SELECT year, open_seas, eez, total, open_seas + eez - total AS diferencia FROM a ORDER BY year;

-- ---- paso 21: vista MackerelsCatch (Athena la guarda en minúsculas: mackerelscatch)
CREATE OR REPLACE VIEW MackerelsCatch AS
SELECT year, area_name AS WhereCaught, fishing_entity as Country, SUM(tonnes) AS TotalWeight
FROM fishdb.data_source_23719
WHERE common_name LIKE '%Mackerels%' AND year > 2014
GROUP BY year, area_name, fishing_entity, tonnes
ORDER BY tonnes DESC;

-- ---- paso 22: toneladas de caballa por año y país
SELECT year, Country, MAX(TotalWeight) AS Weight
FROM fishdb.mackerelscatch
GROUP BY year, Country
ORDER BY year, Weight DESC;

-- ---- paso 23: MackerelsCatch de China
SELECT * FROM "fishdb"."mackerelscatch"
where country in ('China');
