# Repaso del tercer corte — para el examen teórico del 26/11

Cubre las semanas 10 a 14 (19/10 – 28/11) y lo que se practicó en ese período. Cada tema tiene lo
esencial, las comparaciones que suelen preguntarse y un ejemplo **medido por nosotros**. Al final hay
un banco de preguntas con respuesta corta.

| Semana | Tema de clase | Lo que hicimos | Módulo AWS Academy |
|---|---|---|---|
| 10 | Athena (escaneo, formatos columnares) · Redshift MPP · **ADR #2** | Athena German Credit; Parcial 2 (Athena + EMR) | M10: Processing Data for ML |
| 11 | Modelado dimensional (estrella y copo de nieve) · **Checkpoint 2** (carga a Redshift con COPY) | Ejercicio de la librería en el pizarrón; **taller de Kinesis** y ejercicios adicionales | M11: Analyzing and Visualizing |
| 12 | Step Functions · EventBridge + Lambda, SNS/SQS | Lambdas con trigger de Kinesis; Firehose | M12: Automating the Pipeline |
| 13 | SageMaker contra Athena/Redshift · **Well-Architected Tool** | Módulo 13 (certificaciones) | M13: Bridging to Certification |
| 14 | Consolidación · **defensa final** | **Parcial 3**: Kinesis + Firehose + estrella SCD 2 en Athena | Capstone |

---

## 1. Athena

**Qué es.** Un motor SQL *serverless*, basado en Trino/Presto, que consulta datos **en S3** usando el
esquema del Glue Data Catalog (*schema-on-read*). No hay nada que prender.

**Costo.**

- **US$5 por TB escaneado**, con un **mínimo de 10 MB por consulta**.
- Las DDL (`CREATE`, `DROP`, `ALTER`) y las consultas fallidas no cobran.
- Los resultados se guardan en S3.

**Cómo se paga menos** (todo apunta a leer menos bytes):

| Técnica | Por qué funciona | Medido por nosotros |
|---|---|---|
| **Formato columnar** (Parquet/ORC) | Lee sólo las columnas pedidas, con compresión y estadísticas min/max por bloque (*predicate pushdown*) | German Credit: **562 B vs 79.793 B** (142×). P1: **2.335 B vs 586.285 B** (251×) |
| **Particionar** (carpetas `clave=valor`) | Un `WHERE` sobre la partición abre sólo esas carpetas (*partition pruning*) | P3: un mes **3.798 B vs 11.177 B** (0,34) |
| **Comprimir** (gzip, snappy) | Menos bytes en S3 | — |
| **Archivos de buen tamaño** (128 MB–1 GB) | Muchos archivos chicos = mucho *overhead* (*small files problem*) | — |

**Particiones: tres formas de registrarlas.**

- `MSCK REPAIR TABLE` recorre S3 y es lento con muchas.
- `ALTER TABLE ADD PARTITION` las agrega a mano.
- **Partition projection** las calcula de una regla, sin guardarlas en el catálogo. Es ideal para
  fechas: lo usamos en el P2.
- Un **CTAS** con `partitioned_by` las registra solo: lo usamos en el P3. Límite: 100 particiones
  por CTAS o `INSERT`.

**Workgroups.** Separan usuarios o aplicaciones, cada uno con su carpeta de resultados, y permiten:

- un **límite de datos por consulta** (`BytesScannedCutoffPerQuery`, mínimo 10 MB): R10 del P3;
- alertas por workgroup.

Con *enforce* activado, la configuración del workgroup pisa la del cliente. Trampa que encontramos:
así se rechaza un CTAS con `external_location`.

**CTAS e INSERT INTO.** CTAS crea una tabla nueva desde un `SELECT` y es la forma de convertir CSV o
JSON a Parquet sin otro servicio. No escribe sobre una ubicación con datos. **Iceberg** suma ACID,
`MERGE`, `UPDATE` y *time travel*: lo natural para cargas incrementales.

## 2. Redshift

**Qué es.** Un *data warehouse* columnar **MPP** (procesamiento masivamente paralelo):

- un **leader node** recibe la consulta y arma el plan;
- los **compute nodes**, divididos en *slices*, ejecutan en paralelo.

**RA3** separa el cómputo del almacenamiento (*managed storage* en S3). En el lab: `ra3.large`,
máximo 2 nodos, ~US$0,54/h por nodo. **Cobra mientras exista, aunque esté inactivo.**

**Distribución** (cómo se reparten las filas entre slices):

| Estilo | Cuándo |
|---|---|
| `KEY` | Tablas grandes que se unen por esa columna: el join queda local, sin mover datos |
| `ALL` | Dimensiones chicas: copia completa en cada nodo |
| `EVEN` | Sin un join dominante |
| `AUTO` | Redshift elige (por defecto) |

**Sort keys.** Ordenan los bloques en disco y permiten saltear los que no cumplen el filtro (*zone
maps*). Pueden ser compuestas o intercaladas.

**COPY.** Carga en paralelo desde S3, con un rol IAM. Conviene dividir el archivo en un **múltiplo de
la cantidad de slices**, comprimido; el `manifest` lista archivos exactos. `INSERT` fila por fila es
lentísimo. Mantenimiento: `VACUUM` y `ANALYZE`.

**Redshift Spectrum** consulta tablas externas en S3 desde Redshift. **Serverless** cobra por RPU-hora
y no por nodo.

**Athena o Redshift** (el ADR típico):

| | Athena | Redshift |
|---|---|---|
| Modelo | serverless, pago por TB escaneado | cluster (o serverless) pago por hora |
| Ideal para | consultas *ad hoc*, exploración del data lake, poca frecuencia | dashboards con muchos usuarios concurrentes, joins complejos repetidos, rendimiento predecible |
| Datos | en S3, abiertos (Parquet/ORC) | cargados en el DW (más Spectrum para S3) |
| Costo con uso bajo | casi cero | lo que cuesta el cluster por hora, aunque esté quieto |

## 3. Modelado dimensional (Kimball)

**Los 4 pasos:**

1. Elegir el **proceso de negocio**: ventas, reservas.
2. **Declarar el grano**: qué es UNA fila del hecho. Es la decisión más importante.
3. Identificar las **dimensiones**: el contexto (quién, qué, cuándo, dónde).
4. Identificar los **hechos**: las medidas numéricas.

**Tipos de tabla de hechos:**

| Tipo | Una fila es… | Ejemplo |
|---|---|---|
| De transacción | un evento | una venta, una reserva (`fact_booking_event`) |
| *Periodic snapshot* | el estado en un período | el saldo de cada cuenta a fin de mes |
| *Accumulating snapshot* | un proceso con hitos que se actualiza | un pedido: creado → pagado → enviado → entregado |
| *Factless* | un evento sin medidas | una asistencia, una búsqueda (si sólo se cuenta) |

**Medidas:**

- **Aditivas:** se suman por cualquier dimensión (cantidad, ingreso).
- **Semiaditivas:** no se suman en el tiempo (saldo, inventario: se promedian o se toma el último).
- **No aditivas:** cocientes como margen % o conversión. Se guardan sus **componentes** y se
  calculan al final.

**Vocabulario:**

- **Clave subrogada:** entero sin significado, propio del DW. Permite la SCD 2 y aísla del sistema origen.
- **Clave natural:** la del negocio (`BOG-MDE`).
- **Dimensión conformada:** la misma dimensión, con las mismas claves, en varios hechos. Permite
  comparar procesos (*drill-across*) y se planifica con la **matriz bus** (procesos contra dimensiones).
- **Dimensión degenerada:** un identificador sin dimensión propia que queda en el hecho (número de
  pedido, `flight_id`).
- **Role-playing:** la misma dimensión con varios roles (fecha de pedido, fecha de envío).
- **Junk dimension:** agrupa flags sueltos.
- **Miembro desconocido** (−1): evita huérfanos cuando falta la referencia.

**Estrella o copo de nieve.**

- **Estrella:** las dimensiones van desnormalizadas, en una tabla cada una (`dim_book` con autor,
  categoría y editorial adentro). Menos joins y más simple para el usuario y para el motor.
- **Copo de nieve:** las dimensiones se normalizan en subtablas (`dim_book → dim_author`). Ahorra un
  poco de espacio, a cambio de más joins. En analítica casi siempre conviene la estrella.

**SCD (dimensiones lentamente cambiantes):**

| Tipo | Qué hace | Cuándo |
|---|---|---|
| 0 | No cambia nunca (el valor original) | Fecha de alta |
| 1 | **Sobrescribe**: se pierde la historia | Correcciones de errores (un nombre mal escrito) |
| 2 | **Fila nueva por versión**, con `valid_from`, `valid_to`, `is_current` y clave subrogada nueva | Cuando la historia importa (categoría de la ruta, región del cliente) |
| 3 | Columna "valor anterior" | Sólo interesa el cambio inmediato |
| 6 | Híbrido 1+2+3 | Ver la versión histórica y la actual a la vez |

Con SCD 2, el hecho se une a la versión vigente **en la fecha del hecho** (*as-of join*), no a la actual.

Ejemplo del P3: con una tipo 1, enero de 2025 queda +38,8 % REGIONAL y −42,5 % TRUNK.

**El ejercicio del pizarrón (librería):**

- **OLTP:** `author`, `publisher` y `category` → `book` (FK de cada una); `book` → `order_item`
  (FK `book_id`, `order_id`) → `order` (FK `customer_id`) → `customer`. Faltaba `order_date`, sin la
  cual no hay mes ni trimestre.
- **Estrella:** `fact_sales`, con grano de **una línea de pedido**, y las dimensiones `dim_date`,
  `dim_book` (con autor, categoría y editorial desnormalizados) y `dim_customer`. Tiene `order_id`
  como dimensión degenerada.
- **Medidas:** `quantity`, `sales_amount`, `cost_amount` y `margin`.
- **Preguntas:** margen por categoría y mes; autores top por trimestre; pedidos y precio promedio por
  cliente (`COUNT(DISTINCT order_id)`).

## 4. Streaming: Kinesis, Firehose y compañía

**Kinesis Data Streams (KDS):** un log ordenado y durable, en **shards**.

| Límite por shard | Valor |
|---|---|
| Escritura | **1 MB/s o 1.000 registros/s** |
| Lectura compartida | **2 MB/s y 5 `GetRecords`/s**, repartidos entre todos los consumidores |
| Lectura con **enhanced fan-out** (EFO) | 2 MB/s **por consumidor** y por shard, por *push* (HTTP/2): cuesta aparte |
| Registro | hasta 1 MB |
| Retención | 24 h por defecto (hasta 365 días) |

- **Partition key → hash MD5 → shard.** El orden se garantiza **dentro de un shard**, por número de
  secuencia. Una clave muy repetida genera un ***hot shard***.
- **Resharding.** *Split* (un shard en dos) y *merge*, o `UpdateShardCount`. Los shards padres se
  leen antes que los hijos para no perder el orden.
- **Modos.** *Provisioned* paga US$0,015 por shard-hora más US$0,014 por millón de PUT units de
  25 KB. *On-demand* escala solo y cobra por hora de stream más GB: conviene con tráfico impredecible.
- **Productores.** `PutRecords` acepta hasta 500 registros o 5 MB; si falla en parte, se reintentan
  sólo los fallidos. La KPL agrega registros.
- **Consumidores.** El iterador puede arrancar en `TRIM_HORIZON` (lo más viejo), `LATEST`,
  `AT_TIMESTAMP` o `AT_SEQUENCE_NUMBER`.
  - La **KCL** reparte los shards entre workers con *leases* en DynamoDB y guarda *checkpoints*.
  - **Lambda** se engancha con un *event source mapping* (batch size, ventana, `bisect on error`).
- **Semántica: al menos una vez.** Puede haber duplicados, así que el consumidor es **idempotente**
  (deduplica por id).
- **Error típico:** `ProvisionedThroughputExceededException` (shard saturado). Se resuelve con
  *backoff*, mejores claves o más shards.

**Amazon Data Firehose:** entrega **gestionada** a destinos.

- **Destinos:** S3, Redshift (vía S3 + COPY), OpenSearch, Splunk, HTTP, Iceberg.
- **Buffer:** tamaño (1–128 MB) o tiempo (0–900 s); es *near real-time*.
- **Transformaciones:** con Lambda, conversión a Parquet/ORC (usa un esquema de Glue), *dynamic
  partitioning*, compresión y un **delimitador de línea** (nuestra trampa del P3).
- **No guarda ni permite releer:** si hace falta *replay*, va KDS adelante.
- **Precio:** por GB ingerido, **redondeando cada registro a 5 KB**.

**¿Cuál uso?**

| Servicio | Modelo | Úsalo cuando… |
|---|---|---|
| **KDS** | log ordenado con retención; varios consumidores lo releen | analítica en tiempo real, orden por clave, *replay* |
| **Firehose** | tubo gestionado sin retención | sólo hay que **dejar los datos en S3 o Redshift** |
| **SQS** | cola: el mensaje se borra al procesarlo | desacoplar trabajos; *visibility timeout*, DLQ; FIFO para orden y dedup |
| **SNS** | pub/sub por *push* | *fan-out* a varios suscriptores (SQS, Lambda, email) |
| **EventBridge** | bus de eventos con reglas por patrón | reaccionar a eventos de AWS o de SaaS; programar tareas |
| **MSK** | Kafka gestionado | ya usás Kafka o necesitás su ecosistema |

**Conceptos de streaming:**

- **Tiempo del evento o de procesamiento.** Contar por *event time* hace que los eventos tardíos
  caigan en su ventana.
- **Ventanas:** *tumbling*, *sliding* y de sesión. Una **marca de agua** (*watermark*) dice hasta
  cuándo esperar eventos tardíos.
- **Arquitectura Lambda:** una capa batch y una de velocidad, combinadas.
- **Arquitectura Kappa:** todo es stream y se reprocesa releyendo el log.
- **Nuestro P3** es "dos caminos" con un mismo stream: un camino rápido con contadores y uno
  analítico en micro-lotes.

## 5. Orquestación: Step Functions, EventBridge, Lambda

**Step Functions.** Máquinas de estado en JSON (Amazon States Language).

| Estado | Para qué |
|---|---|
| `Task` | Hace algo: Lambda, Glue, Athena, EMR, SNS… (`.sync` espera a que termine) |
| `Choice` | Bifurca según los datos |
| `Parallel` / `Map` | Ramas en paralelo / una por elemento de una lista |
| `Wait`, `Pass`, `Succeed`, `Fail` | Control |

- **Manejo de errores:** `Retry`, con `IntervalSeconds`, `MaxAttempts` y `BackoffRate` para el
  *backoff* exponencial, y `Catch` para derivar a un estado de error (por ejemplo, avisar por SNS).
- **Standard o Express.**
  - *Standard*: hasta 1 año, *exactly-once*, US$0,025 por 1.000 transiciones. Pipelines largos y auditables.
  - *Express*: hasta 5 min, *at-least-once*, se cobra por pedido y duración. Mucho volumen y corto.
- **Patrón callback** (`.waitForTaskToken`): espera una aprobación o un sistema externo.

**EventBridge.**

- Un **bus de eventos** con **reglas**: patrón de evento → destinos (Lambda, Step Functions, SQS…).
- **Scheduler** para programar tareas (cron o rate).
- Archivo y *replay* de eventos; registro de esquemas.

**Un pipeline automatizado típico** (M12):

1. **EventBridge** se dispara cuando llega un objeto a S3, o por horario.
2. Arranca **Step Functions**, que corre el crawler o job de Glue (`.sync`), después la consulta de
   Athena (CTAS), y **SNS** avisa si falla.
3. Todo se define en **CloudFormation** (infraestructura como código).
4. Alternativas: **Glue Workflows** (sólo Glue) y **MWAA** (Airflow gestionado: DAGs en Python, más
   costoso).

**Lambda.** Hasta 15 min y hasta 10 GB de RAM. Se cobra por invocación y por GB-s. En el lab, máximo
10 ejecuciones concurrentes. Va bien para transformaciones cortas y triggers. Un trigger de Kinesis
con `LATEST` tardó **más de 1 minuto** en empezar a leer: lo medimos en el taller.

## 6. Datos para ML (M10) y SageMaker

**Ciclo de ML:** problema de negocio → recolección → **preparación** → *feature engineering* →
entrenamiento → evaluación → despliegue → monitoreo (*drift*). La mayor parte del tiempo se va en
preparar los datos.

**Preparación:**

- **Faltantes:** imputar o descartar.
- **Atípicos.**
- **Duplicados.**
- **Categóricas:** *one-hot* o *label encoding*.
- **Escalado o normalización.**
- **Desbalance de clases:** sobre o submuestreo, o pesos.
- **División train / validación / test**, sin fuga de información (*data leakage*).

**Herramientas:**

- **Glue DataBrew:** preparación visual, sin código.
- **SageMaker Data Wrangler.**
- **SageMaker Processing:** jobs de preparación.
- **Feature Store.**
- **Notebooks.**
- **Canvas:** sin código. En el lab sigue corriendo y cobrando hasta borrarlo.

Desde un notebook se consulta Athena o Redshift con **boto3** o **awswrangler** (`wr.athena.read_sql_query`).

**Clasificación sensible al costo** (German Credit): si clasificar mal a un "malo" cuesta 5 veces más
que rechazar a un "bueno", se predice "malo" cuando **p(malo) > 1/(1+5) = 1/6**, no cuando supera 0,5.
El umbral óptimo es c_FP / (c_FP + c_FN).

## 7. Análisis y visualización (M11)

| Herramienta | Para |
|---|---|
| **Athena** | SQL *ad hoc* sobre el data lake |
| **Redshift** | DW con alta concurrencia de BI |
| **QuickSight** | dashboards (motor en memoria **SPICE**); se paga por usuario o sesión |
| **OpenSearch** | búsqueda de texto y logs, *observability*, dashboards (Kibana) |

**El gráfico según la pregunta:**

- comparación: barras;
- tendencia: líneas;
- composición: barras apiladas (no torta con muchas categorías);
- distribución: histograma o boxplot;
- relación: dispersión.

Siempre en función de **quién mira** y **qué decisión toma**.

## 8. Well-Architected (y la Well-Architected Tool)

| Pilar | Idea central | Ejemplo nuestro |
|---|---|---|
| Excelencia operacional | Operar como código; cambios chicos y reversibles; aprender de las fallas | Scripts idempotentes; harness local antes que AWS |
| Seguridad | Mínimo privilegio, cifrado, trazabilidad, proteger los datos | `LabRole`; sin datos personales en los eventos; bucket privado |
| Fiabilidad | Recuperarse solo, escalar, probar la recuperación | Reintento de los registros fallidos, dedup, rebuild idempotente |
| Eficiencia de rendimiento | El recurso justo; experimentar; serverless | Cola y lotes; particiones; Parquet |
| Optimización de costos | Pagar por uso; medir; apagar lo ocioso | Shard sólo en pruebas; Athena por consulta |
| Sostenibilidad | Minimizar el impacto: usar sólo lo necesario | Nada prendido sin uso; compresión; retención mínima |

La **Well-Architected Tool** es un cuestionario por pilar que marca los **riesgos altos y medios**
(HRI/MRI), arma un plan de mejora con hitos y tiene "lentes" especializados, como el **Data Analytics
Lens**.

## 9. Ideas que atraviesan todo el corte

- **Idempotencia:** repetir una operación da el mismo resultado. Es la base para reintentar sin
  miedo: dedup por id, rebuild completo, `MERGE`.
- **"Exactamente una vez"** no lo da el transporte (Kinesis y SQS standard son *at-least-once*): se
  logra con **dedup** al consumir.
- **Transactional outbox:** guardar el evento en la misma transacción que el dato y publicarlo
  después. **CDC** (captura de cambios, por ejemplo con DMS) es la alternativa de leer el log de la base.
- **Schema-on-read** (Athena, data lake) frente a **schema-on-write** (Redshift, OLTP).
- **Zonas del data lake:** `raw` (tal cual, *append-only*) → `processed`/`curated` (tipado,
  limpio, Parquet) → modelos de consumo.
- **El gasto peligroso es el recurso barato olvidado**, no el caro: en el lab, las EC2 detenidas se
  reinician solas y el shard cobra por hora.

---

## 10. Banco de preguntas (con respuesta corta)

1. **¿Qué es el grano de una tabla de hechos y por qué se declara primero?** Qué representa una fila.
   Define qué dimensiones y medidas son posibles; mezclar granos rompe las sumas.
2. **Hecho de transacción vs. *periodic snapshot*.** Uno es una fila por evento; el otro, una fila por
   entidad y período con el estado (por ejemplo, el saldo a fin de mes).
3. **¿Por qué el margen % no se guarda como medida?** No es aditivo. Se guardan ventas y costo, y se
   calcula al final.
4. **Estrella vs. copo de nieve.** Desnormalizada (menos joins) vs. normalizada (menos redundancia,
   más joins).
5. **SCD 1 vs. 2.** Sobrescribir (se pierde la historia) vs. versionar con validez y clave subrogada.
6. **¿Para qué sirve la clave subrogada?** Identifica versiones (SCD 2), aísla de cambios del origen y
   hace los joins más rápidos (enteros).
7. **¿Qué es una dimensión conformada y qué permite?** La misma dimensión compartida por varios
   hechos. Permite comparar procesos (*drill-across*), como búsquedas contra reservas por ruta.
8. **¿Qué es una dimensión degenerada?** Un identificador transaccional sin dimensión propia, guardado
   en el hecho (número de pedido).
9. **Athena cobra por… y ¿cómo se reduce?** Por TB escaneado (US$5, mínimo 10 MB). Con Parquet,
   particiones, compresión y seleccionando sólo las columnas necesarias.
10. **Una consulta escanea 400 GB de CSV por día. ¿Cuánto cuesta al mes y qué harías?**
    0,4 TB × US$5 × 30 = **US$60/mes**. Con Parquet y particiones suele bajar 10–100×.
11. **¿Qué es *partition projection*?** Calcular las particiones con una regla (por ejemplo, un rango
    de fechas) en lugar de registrarlas en el catálogo: no hace falta `MSCK REPAIR` ni crawler.
12. **Athena vs. Redshift: ¿cuándo cada uno?** Athena: *ad hoc*, poco uso, datos en S3. Redshift:
    BI concurrente, joins pesados, rendimiento estable.
13. **¿Qué es MPP?** Procesamiento masivamente paralelo: un nodo líder planifica y los nodos de
    cómputo ejecutan sobre su porción de datos.
14. **Distribución `KEY` vs. `ALL` en Redshift.** `KEY` deja juntas las filas que se unen (tablas
    grandes); `ALL` replica las dimensiones chicas en cada nodo.
15. **¿Por qué COPY y no INSERT?** COPY carga en paralelo desde S3 aprovechando todos los slices;
    `INSERT` va fila por fila.
16. **Capacidad de un shard.** Escritura 1 MB/s o 1.000 registros/s; lectura 2 MB/s y 5 llamadas/s
    compartidas.
17. **3.000 registros/s de 2 KB: ¿cuántos shards?** Por registros, 3. Por bytes, 6 MB/s → **6**.
    Manda el mayor.
18. **¿Cuánto cuesta ese stream al mes (provisionado)?** 6 × US$0,015 × 730 h ≈ **US$65,70**, más
    las PUT units.
19. **¿Qué es un *hot shard* y cómo se evita?** Un shard que recibe demasiado por una clave
    repetida. Se evita con claves de alta cardinalidad (o agregándoles un sufijo), o haciendo *split*.
20. **¿Qué garantiza Kinesis sobre el orden?** El orden por shard (dentro de la misma partition key);
    no hay orden global.
21. **¿Qué pasa si se cae un consumidor?** Los datos siguen en el stream durante la retención. Con
    KCL, otro worker toma el *lease* y sigue desde el último *checkpoint*. Puede reprocesar algo, así
    que hay que ser idempotente.
22. **EFO: qué es y cuándo.** Cada consumidor recibe 2 MB/s por shard propios, por *push*. Sirve con
    varios consumidores o cuando importa la latencia. Cuesta aparte.
23. **Firehose vs. Data Streams.** Firehose entrega a destinos gestionados, sin retención ni *replay*,
    con un buffer de segundos a minutos. KDS es un log que se relee, con consumidores propios.
24. **¿Por qué Firehose cobra más de lo que pesan los datos?** Redondea cada registro a 5 KB:
    1 millón de registros de 1 KB se cobran como 5 GB.
25. **SQS vs. SNS vs. Kinesis.** Cola con borrado al procesar / *pub-sub* por *push* a muchos / log
    ordenado que se relee.
26. **Step Functions Standard vs. Express.** Larga duración, *exactly-once*, auditables vs. corta
    (≤ 5 min), mucho volumen, *at-least-once*.
27. **¿Cómo reintenta Step Functions?** `Retry` con intervalo, intentos y *backoff*, y `Catch` para
    derivar el error.
28. **Pipeline programado sin servidores: ¿con qué?** EventBridge Scheduler → Step Functions → Glue
    o Athena → SNS si falla.
29. **¿Qué es la idempotencia y por qué importa en streaming?** Que repetir dé el mismo resultado.
    Con entrega "al menos una vez" llegan duplicados y reintentos.
30. **¿Cómo no perder un evento entre la base y el stream?** Con *transactional outbox*, o con CDC
    leyendo el log de la base.
31. ***Event time* vs. *processing time*.** Cuándo ocurrió vs. cuándo se procesó. Para contar bien
    los tardíos se agrupa por *event time*.
32. **Arquitectura Lambda vs. Kappa.** Batch + velocidad en paralelo vs. todo como stream, con
    reproceso releyendo el log.
33. **¿Por qué no actualizar un modelo estrella por cada evento?** Archivos chicos, costo por consulta
    y la deduplicación y los tardíos necesitan el conjunto. Se carga en micro-lotes.
34. **Umbral de decisión con costos asimétricos** (FN 5×FP). p > 1/6 ≈ 0,17.
35. **Los 6 pilares de Well-Architected.** Excelencia operacional, seguridad, fiabilidad, eficiencia
    de rendimiento, optimización de costos y sostenibilidad.
36. **¿Para qué sirve la Well-Architected Tool?** Revisar una carga pilar por pilar, detectar riesgos
    altos y medios y armar un plan de mejora.
37. **QuickSight SPICE.** El motor en memoria de QuickSight: los dashboards no consultan la fuente en
    cada vista.
38. **Pasos de preparación de datos para ML.** Limpiar (faltantes, atípicos, duplicados), codificar
    categóricas, escalar, balancear y dividir sin fuga.
