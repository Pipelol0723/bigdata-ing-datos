# Taller Taxis NYC — EMR + PySpark

**Big Data e Ingeniería de Datos · semana 8** · Presentación: **martes 13/10, en clase, con el
clúster corriendo**. Todo se ejecutó en AWS (Learner Lab, us-east-1) el 10/10, y los números de abajo
son los medidos ese día.

**Qué pedía:** los viajes de los taxis amarillos de Nueva York de 2018, procesados con PySpark en un
clúster de EMR: joins con las zonas, duración de cada viaje, el viaje más largo, el destino y el
trayecto más frecuentes, los meses con más viajes, el resultado en Parquet particionado, una tabla en
el catálogo de Glue consultada con Athena, y el notebook convertido en un programa.

---

## La arquitectura en una línea

```
TLC (web) ──streaming──▶ S3 taxis/  ──▶ EMR: Spark (notebook en EMR Studio + programa como Step)
                                                     │
                                                     ▼
                         S3 viajes/year=2018/month=1…12 ──crawler──▶ Glue: taxis.viajes ──▶ Athena
```

| Pieza | Qué es |
|---|---|
| Datos | **102.871.387 viajes** en 12 Parquet (1,46 GB) + 265 zonas |
| Clúster | EMR 7.14 · Spark 3.5.6 · 1 primario + 2 core `m4.large` · se apaga solo tras 1 h sin trabajo |
| Notebook | **EMR Studio**: JupyterLab dentro de la consola de AWS, enganchado al clúster |
| Programa | `spark/taller_taxis.py`, corrido como **EMR Step** |
| Catálogo | base `taxis`, tabla `viajes`, crawler `crawler-taxis-viajes` |

---

## Las 14 respuestas

| # | Pide | Resultado |
|---|---|---|
| 1 | Datos en `s3://…/taxis/viajes` y `…/taxis/zonas` | 13 objetos, **1.464.429.097 bytes**, idéntico al origen. Cargados en 34 s, de la web directo a S3 |
| 2 | Viajes y zonas en dos DataFrames | 102.871.387 viajes · 265 zonas. Se leen **sólo 4 columnas, con esquema explícito** |
| 3 | Join: `PU_ZONE`, hora de recogida, hora de dejada, `DOLocationID` | Hecho con *broadcast join*: no se pierde ninguna fila |
| 4 | Segundo join: `PU_ZONE`, `DO_ZONE`, `PU_datetime`, `DO_datetime` | 102.871.387 filas después de los dos joins |
| 5 | `trip_duration` en minutos con `unix_timestamp` | `(unix_timestamp(DO) − unix_timestamp(PU)) / 60` |
| 6 | El viaje que más duró | **Tal como viene:** TriBeCa/Civic Center → Kips Bay, del 09/11 al 29/11/2018: **28.837 min (20 días)**, un dato roto. **Entre los válidos:** 180 min, el tope |
| 7 | Destino más frecuente, sin datos erróneos | **Upper East Side North (zona 236): 3.973.487 viajes** · le siguen Midtown Center (3.895.672) y Upper East Side South (3.716.046) |
| 8 | Viaje más frecuente, con promedio y desviación estándar | **Upper East Side South → Upper East Side North: 609.664 viajes · 6,28 min de promedio · desviación 3,3 min** |
| 9–10 | Año y mes del viaje, como enteros | `year: integer` · `month: integer` |
| 11 | Meses de mayor a menor | **marzo 9.430.359** · abril 9.305.987 · mayo 9.224.816 · octubre 8.834.553 · enero 8.760.903 · junio 8.714.545 · febrero 8.493.198 · diciembre 8.194.900 · noviembre 8.156.023 · septiembre 8.048.894 · agosto 7.854.947 · **julio 7.850.980** |
| 12 | Parquet particionado `s3://bucket/viajes/year=…/month=…` | **102.870.105 viajes** (todo 2018) en 12 carpetas, un archivo por mes de 126 a 147 MB |
| 13 | Crawler → tabla `viajes` en la base `taxis`, consultable en Athena | Tabla creada con 12 particiones. En Athena, el conteo y los meses dan igual que en Spark, **escaneando 0 bytes** |
| 14 | El notebook como programa que corre en el clúster | EMR Step **`COMPLETED` en 11 min**, con exactamente los mismos números |

**Cómo se sabe que están bien:** antes de levantar el clúster se calcularon las mismas respuestas con
**Athena sobre los datos crudos** (costó $0,02). Athena crudo, el notebook, el programa y Athena sobre
la tabla final dan **los mismos números**.

---

## Qué se considera "dato erróneo" (pasos 6 a 8)

| Regla | Cuántos | Por qué |
|---|---|---|
| Recogida fuera de 2018 | 1.282 | Hay viajes fechados entre 2001 y 2084 en los 12 archivos |
| Duración ≤ 0 | 90.375 | La bajada es antes o a la misma hora que la recogida |
| Duración > 180 min | 241.065 | El histograma: hasta 3 h la cantidad cae ~10× por tramo, como viajes reales; después deja de caer y aparece un **pico de 218.865 viajes entre las 22 y las 24 h** (taxímetros sin cortar) |
| Zonas 264 y 265 | — | "Unknown" y "Outside of NYC": no son lugares |

Quedan **102.538.665 viajes válidos** (el 99,7 %). El tope es un **parámetro** del programa
(`--tope-min 180`): cambiar el criterio no exige tocar el código.

---

## Las preguntas que conviene tener respondidas

| Pregunta | Respuesta |
|---|---|
| **¿Por qué esquema explícito y no `spark.read.parquet` a secas?** | Porque `passenger_count` y `RatecodeID` cambian de tipo a mitad de año (INT64 de enero a junio, DOUBLE de julio a diciembre). Las 4 columnas que se usan tienen el mismo tipo en los 12 meses |
| **¿Por qué `m4.large` y no algo más moderno?** | El lab permite hasta `large`, y entre los `large` EMR sólo acepta `c4`, `m1` y `m4`. `m5.large` da *"not supported"*: lo comprobamos |
| **¿Por qué agrupar por ID y no por nombre de zona?** | Hay nombres repetidos: "Corona" es la 56 y la 57. Por nombre se sumarían zonas distintas |
| **¿Por qué sólo 2018 en el paso 12?** | Sin ese filtro se crean particiones basura (`year=2001`, `year=2084`…) y el paso 11 sumaría en enero los viajes de enero de 2001 |
| **¿Por qué Athena escanea 0 bytes?** | Parquet guarda la cantidad de filas en el pie de cada archivo, y el mes sale del nombre de la carpeta: no hace falta leer datos |
| **¿Por qué en Athena `year` y `month` son texto?** | El crawler los toma del nombre de la carpeta (`year=2018`), que es texto. Se castean: `CAST(month AS integer)` |
| **¿Esto es *big data*?** | Por volumen, no: 102 millones de filas entran en una laptop. El valor está en el modelo distribuido, que escala sin cambiar el código |
| **¿Por qué EMR y no Glue o Athena?** | Athena respondería los pasos 3 a 11 con SQL, por centavos. Glue corre el mismo Spark sin clúster. EMR da control del clúster y notebook interactivo; a cambio, se paga cada hora encendido |

---

## La demo de mañana

El guion con horarios está en [`PLAN.md`](PLAN.md#el-martes-guion-de-la-demo). Lo esencial:

1. **1 h 30 antes:** *Start Lab* → CloudShell → `cd ~/taller && bash 02-crear-cluster.sh 3`.
2. **Con el clúster en `Waiting`:** EMR Studio → Workspace `taller-taxis-nyc` → *Compute* → el
   clúster → *Attach* → *Run All Cells* (~18 min).
3. **Guardar, apagar el kernel**, y `bash 03-correr-paso-14.sh 180` (~11 min).
4. **En clase:** el clúster en la consola de EMR → el notebook con sus salidas → el step en
   `Completed` → S3 → Glue → Athena.
5. **Al terminar:** terminar el clúster en la misma sesión.

---

## Costo

| | |
|---|---|
| Ensayo del 10/10 (carga, Athena, clúster 1 h 49 min, crawler) | ≈ $0,85 |
| Demo (clúster ~2 h) | ≈ $0,80 |
| S3 (3,1 GB) hasta la corrección | ≈ $0,07/mes |

---

## Qué hizo la IA y qué se corrigió

Se trabajó con Claude (Claude Code). Las decisiones de criterio las tomó el alumno: verificar con
Athena sobre los crudos, mostrar todo desde la consola de AWS, excluir las zonas 264 y 265, guardar
2018 entero, y elegir el tope mirando la distribución de duraciones. Lo que salió mal y se corrigió:

- **Propuso `m5.large` y EMR lo rechazó.** Consultando a la API qué tipos acepta, se pasó a `m4.large`.
- **El separador de consultas SQL cortaba mal** por un `;` dentro de un comentario. Se reescribió para
  quitar los comentarios antes de separar.
- **Los percentiles extremos no coinciden** entre Spark (p99,99 = 28.837 min) y Athena (1.439 min): los
  dos son aproximados, y el error de Spark (±10.000 filas) es tan grande como la cola. Por eso el tope
  se eligió con el histograma exacto.
- **Livy mostraba las tildes de los `print()` como "?"**. Se reescribieron esos textos sin tildes.

Evidencia completa: [`evidencia/sesion-2026-10-10.md`](evidencia/sesion-2026-10-10.md).
