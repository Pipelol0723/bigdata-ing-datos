# Taller Taxis NYC — EMR + PySpark · Plan de solución

> **Estado (09/10):** decisiones tomadas · scripts y notebook listos para el ensayo · **todavía no
> se creó nada en AWS**.
> **Entrega: martes 13/10, en clase — el clúster corriendo, mostrado desde la consola de AWS.**
> **Enunciado:** [`enunciado.md`](enunciado.md), el archivo del profesor sin cambios.
> **Semana 8** del curso, *Arquitectura de clúster EMR*. Lo que se mida acá alimenta la *matriz de
> decisión Glue vs EMR* de la semana 9.

## Qué pide

| Pasos | Pide | Dónde |
|---|---|---|
| 1 | Viajes de taxis amarillos 2018 en `s3://…/taxis/viajes/` y zonas en `s3://…/taxis/zonas/` | CloudShell |
| 2–5 | Dos DataFrames, doble join con zonas (`PU_ZONE`, `DO_ZONE`) y `trip_duration` en minutos con `unix_timestamp` | Notebook en EMR |
| 6–8 | Viaje más largo · destino más frecuente sin datos erróneos · par origen-destino más frecuente con promedio y desviación estándar | Notebook en EMR |
| 9–11 | Columnas enteras `year` y `month` · meses ordenados por cantidad de viajes | Notebook en EMR |
| 12 | Parquet particionado en `s3://bucket/viajes/year=…/month=…` | Notebook en EMR |
| 13 | Crawler → tabla `viajes` en la base `taxis`, consultable en Athena | Glue + Athena |
| 14 | El notebook convertido en un programa que corre en el clúster | EMR Step |

---

## Decisiones tomadas

| # | Decisión | Elegido | Alternativa descartada | Por qué |
|---|---|---|---|---|
| 1 | **Respuestas de referencia** | **Athena sobre los datos crudos**, apenas se cargan (~$0,02) | DuckDB en la PC ($0) | Todo queda en AWS. Los números existen antes de pagar el clúster, y lo que dé EMR tiene que coincidir |
| 2 | **Cómo se ve el notebook** | **Desde la consola de AWS**: EMR Studio, o SageMaker si el lab no deja crear el Studio | Túnel SSH a JupyterHub | La demo es por la consola: sin túnel ni `.pem`, y sin depender de que el Wi-Fi del campus deje salir el puerto 22. *El camino A/B lo propuse yo: revisalo* |
| 3 | **Qué es un dato erróneo** | Recogida fuera de 2018 · duración ≤ 0 · duración mayor a un **tope elegido con los percentiles**, que queda como parámetro · destinos **264 y 265** | Tope fijo de 24 h · contar "Outside of NYC" como destino | Un tope fijo deja pasar taxímetros olvidados de varias horas. Las zonas 264 ("Unknown") y 265 ("Outside of NYC") no son lugares |
| 4 | **Qué se guarda en el paso 12** | **Sólo 2018, con todas sus duraciones** | Sólo los válidos · todo | 12 particiones limpias, no se pierde ningún viaje real de 2018 y Athena reproduce exacto el paso 11. Los crudos siguen en `taxis/viajes/` |
| 5 | **Tamaño del clúster** | **1 primario + 2 core `m5.large`** (~$0,36/h). *Lo decidí yo para no frenar: revisalo* | 1 + 4 (~$0,60/h) | La lectura no pasa de 12 tareas en paralelo: cada archivo es un solo *row group* |

---

## Lo que ya se midió (09/10), sin descargar el dataset

Sale de los pies (*footers*) de los 12 Parquet y de la tabla de zonas: unos KB de tráfico.
Reproducible con [`referencia/inspeccionar_dataset.py`](referencia/inspeccionar_dataset.py).

| Hallazgo | Dato | Qué cambia en la solución |
|---|---|---|
| Volumen | **12 archivos · 1.464.416.766 bytes · 102.871.387 viajes** | Cabe en una laptop. EMR se justifica por el ejercicio y el modelo distribuido, no por el tamaño |
| Formato | Parquet: el TLC dejó de publicar CSV en 2022 | Forzado, y mejor: viene tipado y es columnar |
| *Row groups* | **Uno por archivo** | La lectura se reparte en **12 tareas como máximo**: más de 12 núcleos no la aceleran |
| Columnas que usa el taller | 4 de 19: **907 MB de 1.464 (62 %)**; las dos fechas son el 78 % de eso | Spark lee sólo esas 4. Lo que pesa son las fechas, que casi no se repiten |
| ⚠️ **Tipos que cambian a mitad de año** | `passenger_count` y `RatecodeID`: INT64 de enero a junio, DOUBLE de julio a diciembre · `congestion_surcharge` y `airport_fee`: enteramente nulas en 8 y 11 meses | Leer la carpeta con su esquema completo puede fallar. **Las 4 que se usan tienen el mismo tipo en los 12 meses** → **esquema explícito** |
| ⚠️ **Fechas fuera de 2018, en los 12 meses** | Recogidas desde **2001** hasta **2084**; bajadas desde **1926** | Sin filtro, el paso 12 crea particiones `year=2001`, `year=2084`… y el viaje "más largo" sale absurdo |
| `LocationID` | Entre 1 y 265 en todos los meses, **sin nulos** | El join con zonas no pierde ninguna fila |
| Zonas | 265 filas, IDs 1 a 265 completos · **264 = "Unknown"** · **265 = "Outside of NYC"** | Los "datos erróneos" del paso 7 |
| ⚠️ **Nombres de zona repetidos** | "Corona" = 56 y 57 · "Governor's Island/…" = 103, 104 y 105 | Se agrupa por **ID**, no por nombre: por nombre se sumarían zonas distintas |
| Fechas sin zona horaria | `TIMESTAMP(isAdjustedToUTC=false)`: hora local de Nueva York | Sesión de Spark en UTC: `year`, `month` y la resta trabajan sobre la hora tal como está escrita |

---

## EMR en una página

**Qué es.** Un clúster de Hadoop y Spark administrado sobre EC2: AWS instala y configura Spark,
YARN y HDFS; vos elegís cuántas máquinas y cuánto tiempo viven.

**Por qué EMR y no la alternativa obvia.** El taller lo exige, pero conviene saber qué se resigna:

| Alternativa | Qué cambia |
|---|---|
| **Glue ETL** | El mismo Spark sin clúster que administrar; cobra por DPU-segundo. Sin un notebook interactivo barato en el lab |
| **Athena** | Los pasos 3 a 11 son SQL: los responde por centavos sin levantar nada — por eso es la referencia |
| **DuckDB local** | 102 millones de filas entran en una laptop: esto no es *big data* por volumen |
| **EMR** ✅ | Control del clúster (tamaño, versiones, notebook) y procesamiento distribuido de verdad. Se paga cada hora de máquina encendida, se use o no |

**Cuánto cuesta.** `m5.large` ≈ **$0,12/h por nodo** ($0,096 de EC2 + $0,024 de recargo EMR):
el clúster de 3 nodos ≈ **$0,36/h**, desde que arranca hasta que se termina.

**Trampas de este lab:**

- **Tamaños hasta `large`.** La consola propone `m5.xlarge`, que en el lab falla. El script ya
  pide `m5.large`.
- **El clúster no sobrevive al fin de la sesión** del lab (~4 h). Por eso el martes **se crea de
  nuevo**, una hora antes de la clase, con el mismo script del ensayo.
- **La auto-terminación por inactividad es la red, no el plan.** En el ensayo, 1 h; **el martes,
  3 h**: con 1 h podría apagarse solo antes de la demo.
- **Roles fijos:** `EMR_DefaultRole` y `EMR_EC2_DefaultRole` (no se pueden crear roles). Key pair
  `vockey`.
- **Modo `client` en el paso 14.** En modo `cluster`, lo que imprime el programa va a los logs de
  YARN y no a la salida del step.
- **Los logs del step llegan a S3 con hasta ~5 min de demora.** Por eso el programa además deja un
  resumen en `s3://…/resultados/` apenas termina: es lo que se muestra si el log todavía no llegó.
- **Los Security Groups que crea EMR** (`ElasticMapReduce-master` y `-slave`) se referencian entre
  sí: no se borran sin vaciar antes esas reglas. Son gratis; se pueden dejar.

---

## El notebook en la consola: EMR Studio, o SageMaker si el lab no deja

| | **A · EMR Studio** | **B · Notebook de SageMaker** |
|---|---|---|
| Qué es | El JupyterLab de EMR, dentro de la consola | Una notebook instance `ml.t3.medium` con el kernel *SparkMagic (PySpark)* |
| Cómo llega al clúster | Se "engancha" el Workspace al clúster que esté corriendo | Le manda el código a **Livy** (puerto 8998), **dentro de la VPC**: nada expuesto a internet |
| El martes | El notebook está guardado en S3: se engancha al clúster nuevo y listo | Se arranca la instancia y se apunta al clúster nuevo (cambia en cada clúster) |
| Costo | El Studio no cobra | ~$0,05/h encendida · detenida no se reinicia sola |
| Riesgo | **No está confirmado que el Learner Lab permita crearlo** | Más pasos de armado |

**Se prueba A en la sesión 1, sin clúster: son 10 minutos.** Si el lab no lo deja, B. En los dos
el kernel es PySpark y la sesión `spark` la crea el kernel: el notebook es el mismo.

---

## Hasta el martes: tres sesiones de AWS

| Sesión | Cuándo | Qué | Costo |
|---|---|---|---|
| **1** · preparación | hoy o mañana, ~45 min, **sin clúster** | Anotar el presupuesto · `01-cargar-datos.sh` · referencia en Athena → **se fija el tope** · probar si se puede crear el EMR Studio | ~$0,05 |
| **2** · ensayo general | sábado a lunes, ~2,5 h | `02-crear-cluster.sh` · notebook (pasos 2 a 12) · paso 14 · crawler y Athena · capturas · **terminar el clúster al cerrar** | ~$1 |
| **3** · demo | martes 13/10 | El guion de abajo · **terminar el clúster al salir de la clase** | ~$0,80 |

**Total ≈ $2 a $2,50**, de los **$31,20** que quedan. La bitácora ya anota la lección del 21/09:
la baja va en la misma sesión, nunca "después".

## El martes: guion de la demo

| Cuándo | Qué | Dónde |
|---|---|---|
| **1 h antes** | *Start Lab* · `bash 02-crear-cluster.sh 3` (auto-terminación a las 3 h, no a 1) | CloudShell |
| **45 min antes** | Clúster en `Waiting` · enganchar el notebook y **correrlo entero** (~10 min): llega a clase con las salidas frescas y los datos ya en memoria | EMR Studio / SageMaker |
| **En clase** (~10 min) | 1 · Consola de EMR: el clúster `Waiting`, 3 × `m5.large`, las aplicaciones · 2 · El notebook, paso por paso; **una celda re-ejecutada en vivo** (el paso 7 tarda segundos sobre los datos en memoria) · 3 · **El paso 14 en vivo**: agregar el step y verlo pasar a `Running` mientras se muestra lo demás · 4 · S3: `viajes/year=2018/month=1…12` · 5 · Glue: el crawler y la tabla `viajes` en `taxis` · 6 · Athena: los meses coinciden con el paso 11 · 7 · El step en `Completed` y su salida | Consola |
| **Al terminar la clase** | **Terminar el clúster ahí mismo** (y detener SageMaker si se usó) · `05-auditar-y-baja.sh` | Consola / CloudShell |

**Si algo falla:**
- **El clúster no arranca a tiempo** → la consola de EMR permite *Clone* sobre el clúster del
  ensayo (guarda su configuración) y, mientras tanto, se muestran las capturas del ensayo.
- **El notebook no se engancha** → el `.ipynb` del ensayo tiene las salidas guardadas, y el paso 14
  se corre en vivo igual: sólo necesita la consola.
- **La sesión del lab está por vencer** → *Start Lab* reinicia el contador: **verificarlo en el
  ensayo**, con el clúster corriendo.

---

## Cómo se resuelve cada paso

| # | Cómo | El detalle que importa |
|---|---|---|
| 1 | `curl … \| aws s3 cp - s3://…`, mes por mes | Streaming: no pasa por el disco de CloudShell (1 GB) ni por tu conexión. Control: 13 objetos, **1.464.429.097 bytes** |
| 2 | `spark.read.schema(esquema).parquet(…)` con las 4 columnas · `spark.read.csv(…, header=True, schema=…)` | El esquema explícito esquiva los tipos cambiantes. Control: **102.871.387** filas |
| 3 | Join con zonas por `PULocationID` → `Zone AS PU_ZONE`, `hora_recogida`, `hora_dejada`, `DOLocationID` | Zonas tiene 265 filas: Spark la copia a cada nodo (*broadcast join*) y los viajes no se mueven. Control: el conteo no cambia |
| 4 | Segundo join por `DOLocationID` → `PU_ZONE, DO_ZONE, PU_datetime, DO_datetime` | Los IDs quedan por dentro para agrupar en 7 y 8 |
| 5 | `withColumn("trip_duration", (unix_timestamp(DO_datetime) - unix_timestamp(PU_datetime)) / 60)` | Minutos, con decimales. El resultado se guarda en memoria para no releer S3 en cada consulta |
| 6 | `orderBy(desc("trip_duration"))`, el primero | Se muestran **dos**: el crudo (que deja ver el dato roto) y el más largo válido |
| 7 | Por zona de destino, `count()`, con el filtro de validez | Por ID y nombre · sin 264 ni 265 |
| 8 | Por origen y destino, `count`, `avg` y `stddev` | `stddev` es la muestral. Los valores absurdos inflan la desviación: va con el filtro |
| 9–10 | `year(PU_datetime)` y `month(PU_datetime)`, enteros | — |
| 11 | `groupBy("month").count()`, de mayor a menor | Sólo 2018: si no, enero suma también los viajes de enero de 2001 |
| 12 | `repartition("year", "month")` + `partitionBy("year", "month")` | Un archivo por mes, buen tamaño para Athena |
| 13 | Crawler con `LabRole` sobre `s3://…/viajes/` → base `taxis`, tabla `viajes` | El crawler tipa las particiones como `string` (pasó en el parcial) y los pasos 9–10 piden enteros: se ajustan a `int` en la tabla o se explica |
| 14 | `taller_taxis.py` como EMR Step en modo `client` | Tiene que dar **los mismos números** que el notebook y que la referencia de Athena |

---

## Archivos

```
taller-taxis-nyc-emr/
├── enunciado.md                  el del profesor, sin cambios
├── PLAN.md                       este archivo
├── referencia/
│   ├── inspeccionar_dataset.py   lo medido arriba (sólo metadatos)
│   └── respuestas_athena.sql     sesión 1: las respuestas, antes del clúster
├── infra/                        todo se corre en CloudShell
│   ├── 01-cargar-datos.sh        paso 1: bucket y carga por streaming
│   ├── 02-crear-cluster.sh       el clúster; el mismo comando para el ensayo y el martes
│   ├── 03-correr-paso-14.sh      el programa como EMR Step
│   ├── 04-crawler.sh             paso 13: base, crawler y tabla
│   └── 05-auditar-y-baja.sh      sólo lectura: qué quedó vivo y los comandos de baja
├── notebook/taller_taxis.ipynb   pasos 2 a 12
├── spark/taller_taxis.py         paso 14
└── evidencia/                    (en el ensayo) capturas y salidas
```

## Qué se crea en AWS y cómo se va

| Recurso | Cobra | Baja |
|---|---|---|
| Clúster EMR `taller-taxis-nyc` | ~$0,36/h | **Al cerrar el ensayo y al salir de la clase** · auto-terminación como red |
| EMR Studio *o* notebook de SageMaker | Studio nada · SageMaker ~$0,05/h | SageMaker se detiene con el clúster; los dos se borran después de la corrección |
| Bucket `taxis-nyc-<cuenta>`: datos, salida, scripts, logs, resultados de Athena | ~$0,06/mes | Después de la corrección |
| Bases `taxis` y `taxis_referencia`, crawler | por corrida / nada | Después de la corrección |
| SG `ElasticMapReduce-master` y `-slave` | nada | Opcional |
