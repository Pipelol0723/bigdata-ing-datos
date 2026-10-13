# Taller Taxis NYC — EMR + PySpark

**Big Data e Ingeniería de Datos · CC-IA-02 · Taxis workshop** · 13 de octubre de 2026<br>
**Estudiante:** Andres Felipe Cespedes Rondon

Archivos de esta entrega: **este documento** (las 14 respuestas, cómo se verificaron y el programa del
paso 14 en el Anexo A) y **`taller_taxis.ipynb`**, el notebook ejecutado completo en el clúster de EMR el
13/10, con todas sus salidas.

---

## 1. Resumen

Se procesaron los **102.871.387 viajes** de los taxis amarillos de Nueva York de 2018 con PySpark en un
clúster de AWS EMR (Learner Lab, `us-east-1`). Los 14 pasos se ejecutaron en AWS, y cuatro caminos
independientes dan **los mismos números**: Athena sobre los datos crudos (calculado antes de levantar el
clúster), el notebook, el programa corrido como EMR Step y Athena sobre la tabla final.

## 2. Arquitectura

```
TLC (web) ──streaming──▶ S3 taxis/  ──▶ EMR: Spark (notebook en EMR Studio + programa como Step)
                                                     │
                                                     ▼
                         S3 viajes/year=2018/month=1…12 ──crawler──▶ Glue: taxis.viajes ──▶ Athena
```

| Pieza | Qué es |
|---|---|
| Datos | 12 Parquet del TLC (1,46 GB) en `s3://taxis-nyc-936980625651/taxis/viajes/` + `taxi_zone_lookup.csv` (265 zonas) en `…/taxis/zonas/` |
| Clúster | EMR 7.14 · Spark 3.5.6 · 1 primario + 2 core `m4.large` · se apaga solo tras 1 h sin trabajo |
| Notebook | **EMR Studio**: JupyterLab dentro de la consola de AWS, enganchado al clúster (kernel PySpark) |
| Programa | `taller_taxis.py` (Anexo A), corrido como **EMR Step** en modo `client` |
| Catálogo | Base `taxis`, tabla `viajes`, crawler `crawler-taxis-viajes` (rol `LabRole`, a demanda) |

## 3. Las 14 respuestas

| # | Pide | Resultado |
|---|---|---|
| 1 | Datos en `s3://…/taxis/viajes` y `…/taxis/zonas` | 13 objetos, **1.464.429.097 bytes**, idénticos al origen. Cargados en 34 s, de la web directo a S3 sin pasar por disco |
| 2 | Viajes y zonas en dos DataFrames | **102.871.387 viajes · 265 zonas**. Se leen sólo las 4 columnas que usa el taller, con esquema explícito |
| 3 | Join: `PU_ZONE`, hora de recogida, hora de dejada, `DOLocationID` | *Broadcast join* con las zonas: no se pierde ninguna fila |
| 4 | Segundo join: `PU_ZONE`, `DO_ZONE`, `PU_datetime`, `DO_datetime` | 102.871.387 filas después de los dos joins |
| 5 | `trip_duration` en minutos con `unix_timestamp` | `(unix_timestamp(DO_datetime) − unix_timestamp(PU_datetime)) / 60`, con `withColumn` |
| 6 | El viaje que más duró | **Tal como viene:** TriBeCa/Civic Center → Kips Bay, del 09/11 al 29/11/2018: **28.837 min (20 días)**, un dato roto. **Entre los válidos:** Murray Hill → Midtown East, **180 min** (el tope) |
| 7 | Destino más frecuente, sin datos erróneos | **Upper East Side North (zona 236): 3.973.487 viajes** · le siguen Midtown Center (3.895.672) y Upper East Side South (3.716.046) |
| 8 | Viaje más frecuente, con promedio y desviación estándar | **Upper East Side South → Upper East Side North: 609.664 viajes · 6,28 min de promedio · desviación estándar 3,3 min** |
| 9–10 | Año y mes del viaje, como enteros | `year: integer` · `month: integer` (de la hora de recogida) |
| 11 | Meses de mayor a menor | **marzo 9.430.359** · abril 9.305.987 · mayo 9.224.816 · octubre 8.834.553 · enero 8.760.903 · junio 8.714.545 · febrero 8.493.198 · diciembre 8.194.900 · noviembre 8.156.023 · septiembre 8.048.894 · agosto 7.854.947 · **julio 7.850.980** |
| 12 | Parquet particionado `s3://bucket/viajes/year=…/month=…` | **102.870.105 viajes** (todo 2018) en 12 carpetas `year=2018/month=1…12`, un archivo por mes de 126 a 147 MB |
| 13 | Crawler → tabla `viajes` en la base `taxis`, consultable en Athena | Tabla creada con 12 particiones. En Athena, el conteo y los meses dan igual que en Spark, **escaneando 0 bytes** (Anexo B) |
| 14 | El notebook como programa que corre en el clúster | `taller_taxis.py` (Anexo A) como EMR Step: **`COMPLETED` en 11 min**, con exactamente los mismos números |

## 4. Qué se considera "dato erróneo" (pasos 6 a 8)

| Regla | Cuántos | Por qué |
|---|---|---|
| Recogida fuera de 2018 | 1.282 | Hay viajes fechados entre 2001 y 2084 dentro de los 12 archivos de 2018 |
| Duración ≤ 0 | 90.375 | La bajada es anterior o igual a la recogida |
| Duración > 180 min | 241.065 | En el histograma, hasta 3 h la cantidad cae ~10× por tramo, como viajes reales; después deja de caer y aparece un **pico de 218.865 viajes entre las 22 y las 24 h** (taxímetros sin cortar) |
| Zonas 264 y 265 | — | "Unknown" y "Outside of NYC": no son lugares, así que no pueden ser "el destino más frecuente" |

Quedan **102.538.665 viajes válidos** (el 99,7 %). El tope es un **parámetro** del programa
(`--tope-min 180`): cambiar el criterio no exige tocar el código.

Los percentiles de duración (en minutos, sobre 2018 con duración positiva) que muestra el notebook:
p50 11,2 · p90 28,7 · p99 62,4 · p99,9 1.426 · p99,99 28.837.

## 5. Cómo se sabe que los números están bien

Antes de levantar el clúster se calcularon las mismas respuestas con **Athena sobre los datos crudos**
(costó $0,02). Esa referencia permitió comparar cada salida de Spark contra un valor conocido:

| Control | Athena (crudos) | Notebook (EMR) | Programa (Step) | Athena (`taxis.viajes`) |
|---|---|---|---|---|
| Viajes leídos | 102.871.387 | 102.871.387 | 102.871.387 | — |
| Fuera de 2018 · duración ≤ 0 | 1.282 · 90.375 | 1.282 · 90.375 | 1.282 · 90.375 | — |
| Sobre el tope de 180 min | 241.065 | 241.065 | 241.065 | — |
| Destino más frecuente | zona 236 · 3.973.487 | 236 · 3.973.487 | 236 · 3.973.487 | 3.973.487 |
| Guardados en el paso 12 | — | 102.870.105 | 102.870.105 | 102.870.105 |
| Meses (paso 11) | marzo → julio | idéntico | idéntico | idéntico |

El ensayo completo se hizo el 10/10. El 13/10 se levantó un clúster nuevo y el notebook se volvió a
ejecutar completo (las salidas del archivo entregado son de esa corrida, de unos 19 minutos): mismos
números en todos los pasos.

## 6. Decisiones y por qué

| Pregunta | Respuesta |
|---|---|
| **¿Por qué esquema explícito y no `spark.read.parquet` a secas?** | Porque `passenger_count` y `RatecodeID` cambian de tipo a mitad de año (INT64 de enero a junio, DOUBLE de julio a diciembre) y la lectura con el esquema completo puede fallar. Las 4 columnas que usa el taller tienen el mismo tipo en los 12 meses |
| **¿Por qué *broadcast join*?** | Zonas tiene 265 filas: se copia a cada nodo y los 102 millones de viajes no se mueven por la red |
| **¿Por qué `persist` después del paso 5?** | Todo lo que sigue sale de ese DataFrame. Sin guardarlo, cada consulta volvería a leer S3 y a repetir los dos joins |
| **¿Por qué agrupar por ID y no por nombre de zona?** | Hay nombres repetidos: "Corona" es la 56 y la 57. Agrupando por nombre se sumarían zonas distintas |
| **¿Por qué sólo 2018 en el paso 12?** | Sin ese filtro se crean particiones basura (`year=2001`, `year=2084`…) y el paso 11 sumaría en enero los viajes de enero de 2001 |
| **¿Por qué un archivo por mes?** | `repartition("year", "month")` antes de `partitionBy`: archivos de 126–147 MB, buen tamaño para Athena, en vez de cientos de archivos chicos |
| **¿Por qué en Athena `year` y `month` son texto?** | El crawler los toma del nombre de la carpeta (`year=2018`), que es texto. Se castean: `CAST(month AS integer)` |
| **¿Por qué Athena escanea 0 bytes?** | Parquet guarda la cantidad de filas en el pie de cada archivo, y el mes sale del nombre de la carpeta: no hace falta leer datos |
| **¿Por qué `m4.large`?** | El lab permite hasta `large`, y entre los `large` EMR sólo acepta `c4`, `m1` y `m4`: `m5.large` da *"not supported"* |
| **¿Por qué EMR y no Glue o Athena?** | Athena respondería los pasos 3 a 11 con SQL, por centavos, y Glue corre el mismo Spark sin clúster. EMR da control del clúster y notebook interactivo; a cambio, se paga cada hora encendido |

## 7. Ejecución y costo

El paso 14 se lanzó con:

```
aws emr add-steps --cluster-id <id-del-clúster> --steps "Type=Spark,Name=Paso 14 - taller_taxis.py,ActionOnFailure=CONTINUE,Args=[--deploy-mode,client,s3://taxis-nyc-936980625651/scripts/taller_taxis.py,--bucket,taxis-nyc-936980625651,--tope-min,180]"
```

Modo `client`: el programa corre en el nodo primario y lo que imprime queda en la salida del step.
Además deja un resumen en JSON en `s3://taxis-nyc-936980625651/resultados/`, disponible apenas termina.
Antes de lanzarlo se apaga el kernel del notebook: la sesión de Livy retiene los ejecutores y el step
quedaría esperando recursos.

| Concepto | Costo estimado |
|---|---|
| Carga a S3 y consultas de Athena (referencia y verificación) | ~$0,02 |
| Clúster 3 × `m4.large` en el ensayo (1 h 49 min, se apagó solo por inactividad) | ~$0,71 |
| Crawler (una corrida) | ~$0,12 |
| Presentación del 13/10 (clúster ~2 h) | ~$0,80 |
| S3 (3,1 GB) | ~$0,07/mes |

El clúster se termina al final de la sesión: EMR no sobrevive al cierre del lab, por eso todo resultado
se escribe en S3.

## 8. Uso de IA y qué se corrigió

Se trabajó con un asistente de IA (Claude Code). Las decisiones de criterio las tomó el alumno: verificar
con Athena sobre los crudos, mostrar todo desde la consola de AWS, excluir las zonas 264 y 265, guardar
2018 entero y elegir el tope mirando la distribución de duraciones. Lo que salió mal y se corrigió:

- **Propuso `m5.large` y EMR lo rechazó.** Consultando a la API qué tipos acepta el lab, se pasó a `m4.large`.
- **El separador de consultas SQL cortaba mal** por un `;` dentro de un comentario. Se reescribió para
  quitar los comentarios antes de separar.
- **Los percentiles extremos no coinciden** entre Spark (p99,99 = 28.837 min) y Athena (1.439 min): los
  dos son aproximados, y el error de Spark (±10.000 filas) es tan grande como la cola. Por eso el tope
  se eligió con el histograma exacto, no con un percentil.
- **Livy muestra las tildes de los `print()` como "?"** (se ve en algunas salidas del notebook, por
  ejemplo "despu?s"). Es la codificación de la sesión de Livy, no un error de datos; en el programa del
  paso 14 la salida se fuerza a UTF-8.

---

## Anexo A — Programa del paso 14: `taller_taxis.py`

Es el notebook convertido en programa. Cambia sólo lo que tiene que cambiar: la sesión de Spark se crea
en el programa (en el notebook la da el kernel), el bucket y el tope llegan como argumentos, y al final se
guarda un resumen en S3.

{{PROGRAMA}}

## Anexo B — Verificación en Athena (paso 13)

```sql
-- Conteo total: 102.870.105 = lo que guardó el paso 12 (0 bytes escaneados)
SELECT count(*) FROM taxis.viajes;

-- Meses de más a menos viajes: idéntico al paso 11 (0 bytes escaneados)
SELECT month, count(*) AS viajes FROM taxis.viajes GROUP BY month ORDER BY viajes DESC;
```

Columnas de la tabla que creó el crawler: `pu_zone string · do_zone string · pu_datetime timestamp ·
do_datetime timestamp · trip_duration double`, con las particiones `year string · month string`
(12 particiones registradas).
