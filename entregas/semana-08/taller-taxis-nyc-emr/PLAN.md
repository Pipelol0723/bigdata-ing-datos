# Taller Taxis NYC — EMR + PySpark · Plan de solución

> **Estado:** 📋 planificado el 09/10 — **todavía no se creó nada en AWS**.
> **Enunciado:** [`enunciado.md`](enunciado.md), el archivo del profesor sin cambios.
> **Semana del curso:** 8, *Arquitectura de clúster EMR* (con el PySpark de la semana 7). Lo que se
> mida acá alimenta la *matriz de decisión Glue vs EMR* de la semana 9.

## Qué pide

| Pasos | Pide | Dónde |
|---|---|---|
| 1 | Viajes de taxis amarillos 2018 en `s3://…/taxis/viajes/` y zonas en `s3://…/taxis/zonas/` | CloudShell |
| 2–5 | Dos DataFrames, doble join con zonas (`PU_ZONE`, `DO_ZONE`) y `trip_duration` en minutos con `unix_timestamp` | PySpark en EMR |
| 6–8 | Viaje más largo · destino más frecuente sin datos erróneos · par origen-destino más frecuente con promedio y desviación estándar | PySpark en EMR |
| 9–11 | Columnas enteras `year` y `month` · meses ordenados por cantidad de viajes | PySpark en EMR |
| 12 | Parquet particionado en `s3://bucket/viajes/year=…/month=…` | PySpark en EMR |
| 13 | Crawler → tabla `viajes` en la base `taxis`, consultable en Athena | Glue + Athena |
| 14 | El notebook convertido en un programa que corre en el clúster | `spark-submit` como EMR Step |

---

## Lo que ya se midió (09/10), sin descargar el dataset

Sale de los pies (*footers*) de los 12 Parquet y de la tabla de zonas: unos KB de tráfico.
Reproducible con [`referencia/inspeccionar_dataset.py`](referencia/inspeccionar_dataset.py).

| Hallazgo | Dato | Qué cambia en la solución |
|---|---|---|
| Volumen | **12 archivos · 1.464.416.766 bytes · 102.871.387 viajes** | Cabe en una laptop. EMR se justifica por el ejercicio y el modelo distribuido, no por el tamaño |
| Formato | Parquet: el TLC dejó de publicar CSV en 2022 | Forzado, y mejor: viene tipado y es columnar |
| *Row groups* | **Uno por archivo** | La lectura se reparte en **12 tareas como máximo**: más de 12 núcleos no aceleran el escaneo |
| Columnas que usa el taller | 4 de 19: **907 MB de 1.464 (62 %)**; las dos fechas son el 78 % de eso | Spark lee sólo esas 4. Lo que pesa no es la cantidad de columnas sino las fechas, que casi no se repiten |
| ⚠️ **Tipos que cambian a mitad de año** | `passenger_count` y `RatecodeID`: INT64 de enero a junio, DOUBLE de julio a diciembre · `congestion_surcharge` y `airport_fee`: columnas enteramente nulas en 8 y 11 meses | Leer la carpeta y tocar esas columnas puede fallar. **Las 4 que se usan tienen el mismo tipo en los 12 meses** → se leen con **esquema explícito** |
| ⚠️ **Fechas fuera de 2018, en los 12 meses** | Recogidas desde **2001** hasta **2084**; bajadas desde **1926** | Sin filtro, el paso 12 crea particiones `year=2001`, `year=2084`… y el viaje "más largo" sale absurdo |
| `LocationID` | Entre 1 y 265 en todos los meses, **sin nulos** | El join con zonas no pierde ninguna fila |
| Zonas | 265 filas, IDs 1 a 265 completos · **264 = "Unknown"** · **265 = "Outside of NYC"** | Son los candidatos a "dato erróneo" del paso 7 |
| ⚠️ **Nombres de zona repetidos** | "Corona" = 56 y 57 · "Governor's Island/…" = 103, 104 y 105 | Se agrupa por **ID**, no por nombre: por nombre se sumarían zonas distintas |
| Fechas sin zona horaria | `TIMESTAMP(isAdjustedToUTC=false)`: hora local de Nueva York | Se fija `spark.sql.session.timeZone=UTC` para que `year`, `month` y la resta no dependan de dónde corra Spark |

---

## EMR en una página

**Qué es.** Un clúster de Hadoop y Spark administrado sobre EC2: AWS instala Spark, YARN, HDFS y
JupyterHub; vos elegís cuántas máquinas y cuánto tiempo viven.

**Por qué EMR y no la alternativa obvia.** El taller lo exige, pero conviene saber qué se resigna:
es la materia prima de la matriz de la semana 9.

| Alternativa | Qué cambia |
|---|---|
| **Glue ETL** | El mismo Spark sin clúster que administrar; cobra por DPU-segundo. Sin un notebook interactivo barato en el lab |
| **Athena** | Los pasos 3 a 11 son SQL: los respondería por centavos sin levantar nada |
| **DuckDB local** | 102 millones de filas entran en una laptop: esto no es *big data* por volumen |
| **EMR** ✅ | Control total del clúster (tamaño, versiones, notebook) y procesamiento distribuido de verdad. Se paga cada hora de máquina encendida, se use o no |

**Cuánto cuesta.** `m5.large` ≈ **$0,12/h por nodo** ($0,096 de EC2 + $0,024 de recargo EMR). Un
clúster de 3 nodos ≈ **$0,36/h**, desde que arranca hasta que se termina, esté procesando o no.

**Trampas de este lab:**

- **Tamaños hasta `large`.** La consola propone `m5.xlarge` y en el lab falla: pasar los tres
  grupos a `m5.large` (o `m4.large` si no arranca) y sacar el grupo *task*.
- **El clúster no sobrevive al fin de la sesión** del lab (~4 h): los resultados van a S3 antes, y
  conviene arrancar con al menos 3 h de sesión por delante.
- **El notebook vive en el disco del nodo primario y muere con el clúster.** Al crearlo se activa
  la persistencia en S3 de JupyterHub (clasificación `jupyter-s3-conf`), y además se descarga el
  `.ipynb` antes de terminar.
- **Roles fijos:** `EMR_DefaultRole` y `EMR_EC2_DefaultRole` (verificar que existan: no se pueden
  crear roles). Key pair `vockey`.
- **La auto-terminación por inactividad (1 h) es la red, no el plan.** Es la lección del 21/09: una
  baja que se deja para después es una baja olvidada.
- **Modo `client` en el paso 14.** En modo `cluster`, los `print()` del script van a los logs de
  YARN y no a la salida del step. Igual se dejan los resultados en S3.
- **Los Security Groups que crea EMR** (`ElasticMapReduce-master` y `-slave`) se referencian entre
  sí: no se borran sin vaciar antes esas reglas. Son gratis; se pueden dejar.

---

## Cómo se resuelve cada paso

| # | Cómo | El detalle que importa |
|---|---|---|
| 1 | CloudShell: `curl … \| aws s3 cp - s3://…`, mes por mes | Streaming: no pasa por el disco de CloudShell (1 GB) ni por tu conexión. Control: 13 objetos, **1.464.429.097 bytes** |
| 2 | `spark.read.schema(esquema).parquet(…)` con las 4 columnas · `spark.read.csv(…, header=True, schema=…)` | El esquema explícito esquiva los tipos cambiantes. Control: `count()` = **102.871.387** |
| 3 | Join con zonas por `PULocationID` → `Zone AS PU_ZONE`, `hora_recogida`, `hora_dejada`, `DOLocationID` | Zonas tiene 265 filas: Spark la copia a cada nodo (*broadcast join*) y no mueve los viajes. Control: el conteo no cambia |
| 4 | Segundo join por `DOLocationID` → `PU_ZONE, DO_ZONE, PU_datetime, DO_datetime` | Los IDs se conservan por dentro para agrupar en 7 y 8 |
| 5 | `withColumn("trip_duration", (unix_timestamp(DO_datetime) - unix_timestamp(PU_datetime)) / 60)` | Minutos, con decimales |
| 6 | `orderBy(desc("trip_duration")).limit(1)` | Se muestran **dos**: el crudo (que deja ver el dato roto) y el más largo válido |
| 7 | `groupBy` por zona de destino y `count()`, con el filtro de validez | Por ID y nombre. Qué se excluye: decisión 3 |
| 8 | `groupBy(origen, destino).agg(count, avg, stddev)` | `stddev` es la muestral. Los valores absurdos inflan la desviación: va con el filtro |
| 9–10 | `year(PU_datetime)` y `month(PU_datetime)`, enteros | — |
| 11 | `groupBy("month").count().orderBy(desc("count"))` | Sólo 2018: si no, enero suma también los viajes de enero de 2001 |
| 12 | `repartition("year", "month")` y `write.partitionBy("year", "month").parquet("s3://…/viajes/")` | Queda un archivo por mes, buen tamaño para Athena. Qué filas se guardan: decisión 4 |
| 13 | Crawler con `LabRole`, *on demand*, sobre `s3://…/viajes/` → base `taxis`, tabla `viajes` | El crawler tipa las particiones como `string` (pasó en el parcial), y los pasos 9–10 piden enteros: se ajustan a `int` en la tabla o se explica |
| 14 | El notebook pasado a `taller_taxis.py` (`nbconvert` + limpieza), con el bucket como parámetro, corrido como **EMR Step** | Tiene que dar **los mismos números** que el notebook |

```python
# El núcleo del paso 2: sólo las 4 columnas, con el tipo que tienen en los 12 meses
esquema = ("tpep_pickup_datetime timestamp, tpep_dropoff_datetime timestamp, "
           "PULocationID long, DOLocationID long")
viajes = spark.read.schema(esquema).parquet(f"s3://{BUCKET}/taxis/viajes/")
```

---

## Plan de ejecución

El orden del enunciado no es el más barato: **el paso 14 va antes que el 13**, así el clúster se
termina antes de Glue y Athena, que no lo necesitan.

| Fase | Qué | Dónde | Tiempo | Costo | Cómo sé que salió bien |
|---|---|---|---|---|---|
| **0** | Respuestas de referencia: cuántas filas caen fuera de 2018, distribución de duraciones, y las respuestas de 6, 7, 8 y 11 | Decisión 1 | ~20 min | $0 | Los umbrales del filtro se eligen con números, antes de pagar el clúster |
| **1** | Anotar el presupuesto · bucket `taxis-nyc-<cuenta>` con tags · carga de los 13 archivos | CloudShell | ~10 min | ~$0 | 13 objetos, 1.464.429.097 bytes |
| **2** | Clúster (Hadoop, Spark, Livy, JupyterHub) · túnel SSH · notebook con los pasos 2 a 12 | EMR | ~2 h | ~$0,75 | Conteos de control y respuestas **iguales a la Fase 0** |
| **3** | Paso 14 como EMR Step · bajar el notebook · **terminar el clúster** | EMR | ~20 min | ~$0,10 | Step `Completed` con los mismos números · clúster `Terminated` |
| **4** | Paso 13: crawler y consultas en Athena | Glue + Athena | ~20 min | ~$0,15 | Los meses en Athena coinciden con el paso 11 |
| **5** | Auditoría, baja y bitácora | CloudShell | ~10 min | — | `auditar-recursos.sh` sin EMR vivo |

**Total estimado: ≈ $1 a $1,50.** Lo que queda en S3 (~2,7 GB) cuesta ~$0,06/mes hasta la corrección.

```bash
# Fase 1, el corazón: cada mes va de la web del TLC directo a S3, sin tocar disco
for m in $(seq -w 1 12); do
  curl -sfL "https://d37ci6vzurychx.cloudfront.net/trip-data/yellow_tripdata_2018-$m.parquet" \
    | aws s3 cp - "s3://$BUCKET/taxis/viajes/yellow_tripdata_2018-$m.parquet"
done
```

---

## Decisiones que tenés que tomar vos

Cada una con su alternativa, para poder defenderla.

| # | Decisión | Opciones | Recomiendo |
|---|---|---|---|
| 1 | **Respuestas de referencia (Fase 0)** | **(a)** DuckDB en tu PC: $0, baja ~907 MB · **(b)** Athena sobre los datos crudos, después de la Fase 1: todo en AWS, ~$0,02 · **(c)** sin referencia: el notebook responde solo | **(a)**. Si preferís que nada corra en tu máquina, **(b)** |
| 2 | **Dónde corre el notebook** | **(a)** JupyterHub en el nodo primario, por túnel SSH con `labsuser.pem` · **(b)** EMR Studio: más cómodo, pero no está confirmado en el lab y pide un rol de servicio | **(a)**: no depende de crear roles, y el túnel deja JupyterHub sin exponer a internet (la lección del túnel de DBeaver) |
| 3 | **Qué es un "dato erróneo"** (pasos 6 a 8) | Forzado: recogida fuera de 2018 y duración ≤ 0 · **Tope de duración:** 24 h (laxo) o el que marquen los percentiles · **Zonas:** excluir la 264 y la 265, o sólo la 264 | Tope como **parámetro** del script, elegido con los percentiles de la Fase 0 (24 h si no hay Fase 0) · excluir **264 y 265** |
| 4 | **Qué se guarda en el paso 12** | **(a)** todo: aparecen particiones de 2001 a 2084 · **(b)** sólo 2018, con todas sus duraciones · **(c)** sólo 2018 y sólo viajes válidos | **(b)**: 12 particiones limpias, no se pierde ningún viaje real de 2018, y Athena reproduce exacto el paso 11. El filtro de validez va en las consultas. Los crudos siguen en `taxis/viajes/` |
| 5 | **Tamaño del clúster** | 1 primario + 2 core `m5.large` (~$0,36/h) · 1 + 4 (~$0,60/h, lectura ~2 veces más rápida) | **1 + 2**: la lectura no pasa de 12 tareas en paralelo de todos modos |

---

## Cómo va a quedar la carpeta

```
taller-taxis-nyc-emr/
├── enunciado.md                  el del profesor, sin cambios
├── PLAN.md                       este archivo
├── README.md                     (al final) el documento a entregar: las 14 respuestas con su evidencia
├── referencia/
│   ├── inspeccionar_dataset.py   lo medido arriba, sólo metadatos
│   └── respuestas_duckdb.py      Fase 0
├── infra/
│   ├── 01-cargar-datos.sh        CloudShell: bucket y carga por streaming
│   └── 02-baja-recursos.sh       sólo lectura: qué quedó vivo y los comandos de baja
├── notebook/taller_taxis.ipynb   corrido en EMR, con sus salidas
├── spark/taller_taxis.py         paso 14
└── evidencia/                    capturas y salidas: clúster, step, S3, crawler, Athena
```

## Qué se crea en AWS y cómo se va

| Recurso | Cobra | Baja |
|---|---|---|
| Clúster EMR | ~$0,36/h | **Terminar al cerrar la Fase 3** · auto-terminación a 1 h como red |
| Bucket `taxis-nyc-<cuenta>`: datos, salida, logs, notebooks y resultados de Athena | ~$0,06/mes | Después de la corrección |
| Crawler, base `taxis` y tabla `viajes` | por corrida / nada | Después de la corrección |
| SG `ElasticMapReduce-master` y `-slave` | nada | Opcional |

## Pendiente de confirmar

- **Fecha de entrega** y canal: Moodle o correo.
- **Presupuesto actual** del lab: no se anota desde el 01/09, y las RDS del parcial quedaron
  vivas hasta el 21/09.
- **Versión de EMR.** Los links del enunciado son de Spark 3.1.3 (EMR 6.5); la propuesta es la
  última 7.x (Spark 3.5). El código es el mismo.
