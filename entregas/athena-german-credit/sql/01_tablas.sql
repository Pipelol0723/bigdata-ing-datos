-- German Credit en Athena: tabla sobre el archivo original, vista legible y copia en Parquet.
-- __BUCKET__ lo reemplaza infra/correr.sh. Una sentencia por bloque (Athena corre de a una).

-- base de datos del ejercicio
CREATE DATABASE IF NOT EXISTS german_credit;

-- tabla externa sobre german.data tal como lo publica la UCI: separado por espacios y codificado
CREATE EXTERNAL TABLE IF NOT EXISTS german_credit.solicitudes_raw (
  cod_cuenta        string,  -- A11..A14  estado de la cuenta corriente
  duracion_meses    int,
  cod_historial     string,  -- A30..A34
  cod_proposito     string,  -- A40..A410
  monto_dm          int,     -- marcos alemanes
  cod_ahorros       string,  -- A61..A65
  cod_empleo        string,  -- A71..A75  antigüedad en el empleo
  tasa_cuota_pct    int,     -- cuota como % del ingreso disponible (1 a 4)
  cod_estado_sexo   string,  -- A91..A95
  cod_otros_deudores string, -- A101..A103
  residencia_anios  int,
  cod_propiedad     string,  -- A121..A124
  edad              int,
  cod_otros_planes  string,  -- A141..A143
  cod_vivienda      string,  -- A151..A153
  creditos_banco    int,
  cod_trabajo       string,  -- A171..A174
  personas_a_cargo  int,
  cod_telefono      string,  -- A191, A192
  cod_extranjero    string,  -- A201 sí, A202 no
  clase             int      -- 1 = buen pagador, 2 = mal pagador
)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ' '
STORED AS TEXTFILE
LOCATION 's3://__BUCKET__/raw/';

-- vista con los códigos traducidos (no ocupa espacio ni cuesta: se resuelve en cada consulta)
CREATE OR REPLACE VIEW german_credit.solicitudes AS
SELECT
  CASE cod_cuenta WHEN 'A11' THEN '1. < 0 DM' WHEN 'A12' THEN '2. 0 a 200 DM'
                  WHEN 'A13' THEN '3. >= 200 DM' ELSE '4. sin cuenta' END AS cuenta,
  duracion_meses,
  CASE cod_historial WHEN 'A30' THEN 'sin créditos o todos pagados'
                     WHEN 'A31' THEN 'todo pagado en este banco'
                     WHEN 'A32' THEN 'créditos al día'
                     WHEN 'A33' THEN 'atrasos en el pasado'
                     ELSE 'cuenta crítica / créditos en otros bancos' END AS historial,
  CASE cod_proposito WHEN 'A40' THEN 'auto nuevo' WHEN 'A41' THEN 'auto usado'
                     WHEN 'A42' THEN 'muebles/equipamiento' WHEN 'A43' THEN 'radio/TV'
                     WHEN 'A44' THEN 'electrodomésticos' WHEN 'A45' THEN 'reparaciones'
                     WHEN 'A46' THEN 'educación' WHEN 'A47' THEN 'vacaciones'
                     WHEN 'A48' THEN 'capacitación' WHEN 'A49' THEN 'negocio' ELSE 'otros' END AS proposito,
  monto_dm,
  CASE cod_ahorros WHEN 'A61' THEN '1. < 100 DM' WHEN 'A62' THEN '2. 100 a 500 DM'
                   WHEN 'A63' THEN '3. 500 a 1000 DM' WHEN 'A64' THEN '4. >= 1000 DM'
                   ELSE '5. sin ahorros / desconocido' END AS ahorros,
  CASE cod_empleo WHEN 'A71' THEN '1. desempleado' WHEN 'A72' THEN '2. < 1 año'
                  WHEN 'A73' THEN '3. 1 a 4 años' WHEN 'A74' THEN '4. 4 a 7 años'
                  ELSE '5. >= 7 años' END AS antiguedad_empleo,
  tasa_cuota_pct,
  CASE WHEN cod_estado_sexo IN ('A92', 'A95') THEN 'mujer' ELSE 'hombre' END AS sexo,
  CASE cod_otros_deudores WHEN 'A101' THEN 'ninguno' WHEN 'A102' THEN 'codeudor' ELSE 'garante' END AS otros_deudores,
  residencia_anios,
  CASE cod_propiedad WHEN 'A121' THEN 'inmueble' WHEN 'A122' THEN 'ahorro/seguro de vida'
                     WHEN 'A123' THEN 'auto u otro' ELSE 'sin propiedad conocida' END AS propiedad,
  edad,
  CASE cod_otros_planes WHEN 'A141' THEN 'banco' WHEN 'A142' THEN 'comercios' ELSE 'ninguno' END AS otros_planes,
  CASE cod_vivienda WHEN 'A151' THEN 'alquila' WHEN 'A152' THEN 'propia' ELSE 'gratuita' END AS vivienda,
  creditos_banco,
  CASE cod_trabajo WHEN 'A171' THEN 'no calificado no residente' WHEN 'A172' THEN 'no calificado'
                   WHEN 'A173' THEN 'calificado' ELSE 'gerencial/independiente' END AS trabajo,
  personas_a_cargo,
  cod_telefono = 'A192' AS tiene_telefono,
  cod_extranjero = 'A201' AS extranjero,
  CASE clase WHEN 1 THEN 'bueno' ELSE 'malo' END AS riesgo
FROM german_credit.solicitudes_raw;

-- copia columnar: misma información, en Parquet comprimido (para comparar lo que escanea Athena)
CREATE TABLE IF NOT EXISTS german_credit.solicitudes_parquet
WITH (format = 'PARQUET', write_compression = 'SNAPPY', external_location = 's3://__BUCKET__/parquet/')
AS SELECT * FROM german_credit.solicitudes;
