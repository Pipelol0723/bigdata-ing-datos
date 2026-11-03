# Taller: streaming de datos con Amazon Kinesis — informe

**Big Data e Ingeniería de Datos (CC-IA-02)** · Universidad Sergio Arboleda · **Andres Felipe Cespedes Rondon** · 3 de noviembre de 2026

> **Cómo se hizo.** Todo se corrió en el AWS Academy Learner Lab (us-east-1, rol `LabRole`) desde
> **CloudShell**, con los scripts de la guía y un orquestador que guarda la salida de cada paso
> (`infra/10-taller.sh`, Anexo B). Los números de este informe salen de esa salida. Los recursos
> **quedaron creados a propósito para mostrarlos en clase**; la limpieza (laboratorio 6) está escrita
> y se ejecuta después de la demostración (§2.7).

## 1. Arquitectura

```
                               ┌──▶ Lambda procesar-sensores ──▶ CloudWatch Logs (ALERTA / OK)
productor.py ──PutRecords──▶ Kinesis Data Stream ──┼──▶ Lambda contar-alertas ──▶ S3 resumen-alertas/ (reto)
 (boto3, CloudShell)        taller-kinesis-sensores  └──▶ Firehose taller-kinesis-a-s3 ──▶ S3 sensores/anio=/mes=/dia=/
                               (1 shard, provisionado)                                          │
                                                                                     Athena (tabla JSON) ◀┘
```

| Recurso | Nombre | Para qué |
|---|---|---|
| Kinesis Data Stream | `taller-kinesis-sensores` (1 shard) | El flujo de eventos de los sensores |
| Kinesis Data Stream | `taller-kinesis-3shards` (3 shards) | Reto: reparto por partition key |
| Lambda | `procesar-sensores` | Alertas por temperatura > 8 °C |
| Lambda | `contar-alertas` | Reto: resumen de alertas por contenedor en S3 |
| Amazon Data Firehose | `taller-kinesis-a-s3` | Entrega del stream a S3, particionado por fecha |
| S3 | `taller-kinesis-ac-936980625651` | Data lake: `sensores/`, `resumen-alertas/`, resultados de Athena |
| Glue / Athena | base `taller_kinesis`, tabla `sensores` | Consultar lo que llegó a S3 |

Todos usan **`LabRole`**: el Learner Lab no deja crear roles.

## 2. Laboratorios

### 2.1 Laboratorio 1 — Crear el stream

Se creó `taller-kinesis-sensores` en modo **provisionado con 1 shard** (estado ACTIVE, retención de
24 horas).

**Pregunta: ¿cuál es la capacidad máxima de escritura de este stream?** La de un shard:
**1 MB/s o 1.000 registros/s**, lo que se alcance primero. La lectura es de 2 MB/s y 5 llamadas
`GetRecords` por segundo, compartidas entre todos los consumidores.

### 2.2 Laboratorio 2 — Productor con boto3

El productor de la guía manda lotes de 10 eventos por segundo con `put_records`, usando
`contenedor_id` como partition key. Se mandaron dos tandas de 200 eventos, sin ningún fallo.

En la pestaña *Monitoring* (métrica `IncomingRecords` de CloudWatch, suma por minuto) se ven las dos
tandas en el mismo minuto, y después las de los laboratorios siguientes:

| Minuto (UTC) | `IncomingRecords` | Qué fue |
|---|---|---|
| 15:11 | **400** | Las dos tandas de 200 del laboratorio 2 |
| 15:13 | 100 | La tanda del iterador `LATEST` (laboratorio 3) |
| 15:14 – 15:18 | 120 · 80 · 200 · 340 · 60 | Las tandas del laboratorio 4 (Lambda) y del 5 (Firehose) |
| 15:22 · 15:25 | 200 · 200 | Las del reto 2 (segunda Lambda) |

**Actividad: ¿qué implica usar una partition key constante con varios shards?** Kinesis aplica un
hash MD5 a la clave para elegir el shard. Con una clave constante, **todos los registros van al mismo
shard**: los otros quedan ociosos y la capacidad efectiva del stream es la de un solo shard
(1.000 registros/s), aunque se paguen todos. A cambio, el orden es total, porque todo pasa por un
único shard. Se midió en el reto (§3.1): con clave constante, el 100 % fue a un solo shard.

### 2.3 Laboratorio 3 — Consumidor manual

Con 400 registros en el stream (dos tandas de 200; la segunda empezó a las 15:11:22 UTC), se leyó con
los tres tipos de iterador:

| Iterador | Desde dónde lee | Registros leídos |
|---|---|---|
| `TRIM_HORIZON` | El registro más antiguo que el stream todavía retiene | **400** (las dos tandas) |
| `AT_TIMESTAMP` (15:11:22) | El primer registro con marca de llegada igual o posterior a ese instante | **200** (sólo la segunda tanda) |
| `LATEST` | Sólo lo que llegue **después** de abrir el iterador | **100** (se abrió y después se produjeron 100) |

**Dos consumidores a la vez** (`TRIM_HORIZON`, mismo shard): **ambos recibieron los 500 registros**.
Con `GetRecords`, los consumidores no se reparten los datos: cada uno lee todo el shard. Lo que sí
comparten es la capacidad de lectura del shard: **2 MB/s y 5 llamadas por segundo entre todos**. Con
muchos consumidores aparece `ProvisionedThroughputExceededException`. La salida es *enhanced fan-out*
(2 MB/s dedicados por consumidor) o tener más shards.

### 2.4 Laboratorio 4 — Lambda como consumidor

`procesar-sensores` (Python 3.12, `LabRole`) con un trigger del stream. Para 200 registros:

| Configuración del trigger | Invocaciones | Registros | Alertas (> 8 °C) | OK |
|---|---|---|---|---|
| Batch size **100**, ventana **5 s** | **6** | 200 | 36 | 164 |
| Batch size **5**, ventana **0 s** | **40** | 200 | 26 | 174 |

Con ventana de 5 s, Lambda espera a juntar registros (hasta 100) antes de invocar: **6 invocaciones**
procesan lo mismo que 40 de a 5. Menos invocaciones significa menos costo y menos sobrecarga; a cambio,
hasta 5 s más de latencia. Las alertas difieren entre filas porque son tandas distintas de eventos
aleatorios.

> **Hallazgo:** con *Starting position* `LATEST`, el trigger tardó más de un minuto en empezar a leer
> después de quedar *Enabled*: la primera tanda no llegó a la Lambda. Es la situación que la guía anota
> en "Solución de problemas" ("enviar más datos tras crear el trigger"). Por eso la medición con batch
> 100 se tomó de nuevo, con el trigger ya activo.

**Discusión: ¿por qué la Lambda debe ser idempotente?** Kinesis y Lambda entregan **al menos una
vez**. Si una invocación falla o se corta por *timeout*, Lambda reintenta **el lote entero**, y los
registros que sí se habían procesado vuelven a llegar. Si la función tiene efectos (mandar una
alerta, sumar un contador, escribir una fila), procesar dos veces el mismo registro no debe cambiar el
resultado. Técnicas: usar el `sequenceNumber` (o un id del evento) como clave de escritura, escribir
con `PutItem` condicional, o sobrescribir en lugar de sumar. La segunda Lambda del reto lo aplica: nombra
el objeto de S3 con el id de la invocación, así un reintento sobrescribe el mismo archivo en vez de
duplicar el conteo.

### 2.5 Laboratorio 5 — Firehose a S3

Firehose **sí aceptó `LabRole`** en este Learner Lab, así que no hizo falta el plan B (que quedó
escrito igual: `codigo/lambda_plan_b_s3.py`). Configuración: fuente el stream, destino el bucket, prefijo
`sensores/anio=!{timestamp:yyyy}/mes=!{timestamp:MM}/dia=!{timestamp:dd}/` y buffer de **1 MB / 60 s**.

Se mandaron dos tandas de 200 eventos y, pasado el buffer de 60 s, Firehose había escrito un objeto con
**las 400 líneas**. Después, con las tandas del reto, siguió escribiendo un objeto por minuto con datos:

| Hora de escritura | Tamaño | Objeto en S3 |
|---|---|---|
| 15:19:03 | 45.994 B | `sensores/anio=2026/mes=11/dia=03/taller-kinesis-a-s3-1-2026-11-03-15-17-25-…` |
| 15:23:29 | 22.995 B | `sensores/anio=2026/mes=11/dia=03/taller-kinesis-a-s3-1-2026-11-03-15-22-21-…` |
| 15:26:39 | 23.000 B | `sensores/anio=2026/mes=11/dia=03/taller-kinesis-a-s3-1-2026-11-03-15-25-32-…` |

El prefijo con `!{timestamp:…}` dejó los datos **particionados por fecha** al estilo Hive
(`anio=/mes=/dia=`), que es lo que Athena o Glue reconocen como particiones.

**Extensión opcional (Athena).** Tabla externa con el SerDe de JSON sobre `s3://…/sensores/` y la
consulta de la guía, con la cantidad de alertas agregada:

{{csv:resultados/taller/02.csv}}

Suman **400 eventos**, exactamente los que entregó Firehose en la primera escritura, y 63 alertas. El
promedio ronda los 5 °C en todos los contenedores, como era de esperar: el productor genera
temperaturas con una normal de media 5 y desvío 3.

### 2.6 Laboratorio 6 — Limpieza

La limpieza está automatizada en `infra/90-limpieza.sh`. **Por defecto sólo audita**: lista lo que
queda vivo e imprime los comandos de baja (borrar los streams con `--enforce-consumer-deletion`, el
Firehose, los triggers y las Lambdas, la base de Glue, la tabla de DynamoDB de los ejercicios y el
bucket). Con `--confirmo` los ejecuta. Se corre **después de la demostración en clase**: un stream
cobra por shard-hora mientras exista, aunque el lab esté cerrado, así que no se deja de un día para otro.

## 3. Reto final

### 3.1 Tres shards y distintas partition keys

Stream `taller-kinesis-3shards` (3 shards). Se mandaron 300 eventos con cada estrategia de clave y se
contó cuántos cayeron en cada shard (`codigo/contador_por_shard.py`, leyendo sólo esa corrida con
`AT_TIMESTAMP`):

{{csv:resultados/taller/reto_shards.csv}}

| Clave | Reparto entre los 3 shards | Lectura |
|---|---|---|
| `contenedor_id` (8 valores) | 33 % · 10 % · 57 % | **Desparejo**: con sólo 8 claves, el hash dejó 3, 1 y 4 contenedores en cada shard. El shard 1 recibe un solo contenedor |
| Constante | 0 % · **100 %** · 0 % | **Todo a un shard**: los otros dos no trabajan. Es el *hot shard* llevado al extremo |
| Aleatoria (UUID por evento) | 30 % · 34 % · 36 % | **Parejo**, pero sin orden por contenedor: cada evento cae en cualquier shard |

La elección de la partition key es un **compromiso entre orden y reparto**. Con pocas claves, o con una
sola, el reparto queda desparejo; una clave aleatoria reparte bien pero pierde el orden. Para este caso,
`contenedor_id` es la correcta, porque el orden por contenedor importa. Con cientos de contenedores
reales, el reparto se empareja solo.

### 3.2 Segunda Lambda: alertas por contenedor en S3

`contar-alertas` lee el mismo stream, con su propio trigger, y por cada lote escribe en
`s3://…/resumen-alertas/fecha=AAAA-MM-DD/<id de la invocación>.json` un resumen como éste:

```json
{"lote": "1d77c339-0a55-4c76-afe7-f54f4534d972",
 "primer_numero_secuencia": "49679877509209292691846071227362295661329668367162802178",
 "registros": 40, "alertas_por_contenedor": {"CT-005": 3, "CT-008": 1}, "total_alertas": 4,
 "generado": "2026-11-03T15:25:52.865352+00:00"}
```

Con una tanda de 200 eventos, las dos Lambdas coincidieron:

| Lambda | Lotes / invocaciones | Registros | Alertas |
|---|---|---|---|
| `procesar-sensores` (logs) | 6 | 200 | **36** |
| `contar-alertas` (resúmenes en S3) | 6 | 200 | **36** |

Alertas por contenedor según los resúmenes: CT-001: 8 · CT-002: 4 · CT-003: 3 · CT-004: 3 · CT-005: 8 ·
CT-006: 3 · CT-007: 1 · CT-008: 6.

Las dos Lambdas leen el mismo stream de forma independiente: un Data Stream admite varios
consumidores, y cada uno lleva su propia posición.

### 3.3 Informe de una página: diagrama, decisiones y costo

**Diagrama:** §1.

**Decisiones de diseño.**

| Decisión | Elegido | Por qué | Cuándo cambiaría |
|---|---|---|---|
| Modo de capacidad | **Provisionado, 1 shard** | Carga chica y previsible (~10 registros/s de 8 sensores, muy lejos de 1.000/s). Es lo más barato para un flujo estable: se paga el shard-hora (~US$0,015) | **On-demand** si el tráfico tiene picos impredecibles o no se conoce: escala solo, pero cobra más por GB en volumen sostenido |
| Partition key | `contenedor_id` | Orden garantizado **por contenedor**, que es lo que importa para detectar una tendencia de temperatura; con 3 shards reparte razonablemente (§3.1) | Una clave más fina (contenedor + sufijo) si un contenedor se vuelve un *hot shard* |
| Buffer de Firehose | **1 MB / 60 s** | Con este volumen siempre gana el tiempo: un archivo por minuto con datos "casi" en tiempo real. Para alertas inmediatas ya está la Lambda; S3 es el histórico | Buffer más grande (p. ej. 64 MB / 900 s) en producción, para escribir menos archivos y más grandes: menos *requests* a S3 y mejores consultas en Athena |
| Consumidores | Lambda (alertas) + Firehose (data lake) | Separa lo urgente de lo histórico, sin servidores | KCL o Flink si hiciera falta estado (ventanas, agregaciones por minuto) |
| Formato en S3 | JSON por línea | Es lo que produce el productor y Athena lo lee con el SerDe de JSON | Firehose puede convertir a **Parquet** con un esquema del Glue Data Catalog: mucho menos escaneo en Athena |

**Estimación de costo** (us-east-1, precios de lista, 24/7 con el volumen del taller):

| Componente | Cálculo | US$/mes |
|---|---|---|
| Kinesis: 1 shard provisionado | 730 h × US$0,015 | 10,95 |
| Kinesis: PUT payload units | ~26 M registros/mes × US$0,014 por millón | 0,36 |
| Lambda (2 funciones) | ~0,5 M invocaciones por función (lotes de ~50 con ventana de 5 s), ~50 ms cada una; queda casi toda dentro de la capa gratuita | ~0,01 |
| Firehose | Cobra cada registro **redondeado a 5 KB**: 26 M registros ≈ 130 GB facturados × US$0,029/GB | 3,77 |
| S3 + Athena | ~3 GB de JSON por mes + consultas ocasionales | < 0,50 |
| **Total** | | **≈ US$15,60/mes** |

El costo dominante es **el shard por existir**, no el volumen. El segundo es Firehose, y por un detalle
fácil de pasar por alto: el productor manda **un evento de ~110 bytes por registro**, y Firehose lo
cobra como si pesara 5 KB. Agrupar ~40 eventos por registro (el `Data` admite hasta 1 MB) bajaría ese
ítem a centavos. Para el taller, en el lab, el costo real fue de centavos: ~1 hora de 1 + 3 shards.

## 4. Preguntas de repaso

1. **¿Qué garantiza el orden y hasta qué nivel?** La partition key: registros con la misma clave van
   al mismo shard, y **dentro de un shard** el orden es el de llegada (número de secuencia creciente).
   No hay orden global entre shards ni entre claves distintas.
2. **¿Por qué Firehose no es tiempo real?** Porque entrega **por buffer**: espera a juntar un tamaño
   (MB) o a que pase un intervalo (segundos), lo que ocurra primero. Con 60 s de buffer, el dato llega
   a S3 hasta un minuto después. Es *near real-time*.
3. **¿Qué pasa tras 24 horas de retención?** Los registros más viejos que el período de retención se
   **eliminan del stream** y ya no se pueden leer ni reprocesar. La retención se puede extender hasta
   365 días, con costo adicional.
4. **`TRIM_HORIZON` vs `LATEST`.** `TRIM_HORIZON` empieza en el registro más antiguo que todavía está
   retenido (lee todo lo disponible); `LATEST` empieza después del último registro, o sea, sólo ve lo
   que llegue después de pedir el iterador. Medido: 400 contra 100 (§2.3).
5. **¿Cuándo on-demand sobre provisionado?** Con tráfico impredecible o con picos, en cargas nuevas sin
   historia, o cuando no se quiere administrar shards. Para cargas estables y conocidas, provisionado
   es más barato.
6. **¿Qué significa "al menos una vez" y cómo lo mitiga el consumidor?** Que un registro puede
   entregarse **más de una vez** (reintentos de lotes, reinicios del consumidor desde el último
   checkpoint), pero nunca se pierde mientras esté retenido. Se mitiga con **consumidores idempotentes**
   (§2.4): deduplicar por número de secuencia o id del evento, escrituras condicionales, sobrescribir
   en vez de acumular.
7. **¿Cuántos shards para 3 MB/s y 2.500 registros/s?** Por volumen: 3 MB/s ÷ 1 MB/s = 3. Por registros:
   2.500 ÷ 1.000 = 2,5 → 3. **Mínimo 3 shards**, y conviene dejar margen (4).

## Anexo A — Código de la guía y del reto

{{codigo:codigo/productor.py}}

{{codigo:codigo/consumidor.py}}

{{codigo:codigo/lambda_procesar.py}}

{{codigo:codigo/lambda_contar_alertas.py}}

## Anexo B — Orquestador del taller (CloudShell)

{{codigo:infra/10-taller.sh}}
