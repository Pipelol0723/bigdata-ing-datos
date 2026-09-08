# 5.7 Implementación en AWS: ETL, catálogo de datos y costos

> **Estado:** ✅ **DESPLEGADO Y VERIFICADO EN AWS — 08/09.**
> Evidencia completa en [`../evidencia/aws/sesion-2026-09-08.md`](../evidencia/aws/sesion-2026-09-08.md).
> **Peso en la rúbrica:** 20% — **la sección que más pesa**

## Resultado de la ejecución en AWS (08/09)

| Qué | Resultado medido |
|---|---|
| 2 × RDS PostgreSQL **18.3** | `parcial-oltp`, `parcial-olap` — los `.sql` escritos contra PG 16 corrieron **sin un solo cambio** |
| Carga de los 4 `.sql` | OK · el generador de actividad tardó **2,4 s** |
| Invariante de no-sobreventa sobre RDS | **0 violaciones** |
| ETL OLTP → OLAP contra las RDS | **141 dimensiones + 9.121 hechos en 1,64 s** |
| Data lake en S3 | 13 objetos, 147 KiB, Parquet particionado `year=/month=` |
| Catálogo de Glue | **8 tablas**, particiones `year`/`month` detectadas solas |
| Athena | 8.893 filas consultadas escaneando **4.614 bytes** |
| Costo real de la sesión | **~$0,25** |

**El ETL se ejecutó desde CloudShell contra las RDS**, no como job de Glue. Fue una decisión de
alcance: el job de Glue es la evolución prevista —tiene sentido cuando la recarga completa deje
de entrar en la ventana de proceso— y agregarlo hoy no cambia ningún resultado del documento.
El mismo script apuntó a AWS sin editar una línea, sólo cambiando `DSN_OLTP` y `DSN_OLAP`.

## Por qué se validó primero en local

Todo el pipeline —esquema OLTP, esquema estrella, ETL y las tres vistas de negocio— está
**funcionando y probado** contra dos PostgreSQL 16 en Docker que espejan la topología de
destino (`docker-compose.yml`).

No es una preferencia de comodidad: el Learner Lab tiene **50 USD de presupuesto total** y
dos instancias RDS encendidas cuestan ~$0.86/día. Depurar un ETL contra AWS habría costado
varios dólares en instancias corriendo mientras se corregían errores de SQL. Depurarlo local
cuesta **cero**, y a AWS se sube una sola vez, ya funcionando.

Es la aplicación directa del pilar de **Optimización de Costos** al propio proceso de
desarrollo, no sólo al producto.

---

## Qué se copia al OLAP, y por qué transformado

### La respuesta corta: transformado, en esquema estrella, con dos tablas de hechos

```
OLTP (3NF, 17 tablas)                    OLAP (estrella, 6 dim + 2 hechos)
──────────────────────                   ─────────────────────────────────
tramo ──┐                                fact_tramo_vendido   (grano: tramo)
itinerario ──┤                             → ingresos por tarifa
reserva ──┼── ETL ──▶                      → patrones de cancelación
instancia_vuelo ──┤
vuelo_programado ──┤                     fact_ocupacion_vuelo (grano: vuelo)
ruta ──┤                                   → ocupación por ruta
aeropuerto ──┘
                                         dim_fecha · dim_ruta · dim_vuelo
                                         dim_tarifa · dim_canal · dim_estado
```

### ¿Por qué no copiar tal cual?

Responder *"ocupación por ruta"* contra el OLTP cruza **cinco tablas**:
`tramo → instancia_vuelo → vuelo_programado → ruta → aeropuerto`. Cada reporte paga ese costo
otra vez. El ETL **resuelve esos joins una sola vez** y los materializa.

### ¿Por qué DOS tablas de hechos?

Porque las preguntas de `FR-19` tienen **granos distintos**, y ése es el error de modelado
dimensional más común:

- *Ingresos y cancelaciones* → grano **tramo vendido**
- *Ocupación por ruta* → grano **instancia de vuelo**

Un único hecho a grano de tramo **no puede** dar ocupación: no conoce los vuelos que
no vendieron nada, y ésos son justamente los que hacen bajar el promedio. Calcularla sólo
sobre los vuelos con ventas daría una ocupación sistemáticamente inflada.

Las dos tablas comparten dimensiones (`dim_fecha`, `dim_ruta`, `dim_vuelo`): es una
**constelación**, no dos estrellas sueltas.

### ¿Debe el esquema analítico ser idéntico al transaccional?

**No, y ésa es la razón de ser de esta sección.** Conecta directo con la discusión de
normalización de 5.3:

| | OLTP | OLAP |
|---|---|---|
| Normalización | **3NF** | **Desnormalizado** (estrella) |
| Optimizado para | Escrituras concurrentes, integridad | Lecturas agregadas sobre históricos |
| Por qué | Cada dato en un lugar → sin anomalías, y `DEC-03` bloquea una fila | Los joins de `FR-19` ya vienen resueltos |

Forzar un solo modelo penaliza a alguno de los dos. **La copia por ETL no es un requisito
arbitrario del enunciado: es la consecuencia lógica de haber elegido 3NF en 5.3.**

### Transformaciones concretas que aplica el ETL

| Transformación | Por qué |
|---|---|
| Aplana `ruta → aeropuerto` en `dim_ruta` con ciudades y `ruta_descripcion` | Elimina dos joins de cada reporte |
| `dim_fecha` con trimestre, día de semana y **temporada** | Permite *"ocupación en temporada alta"* sin recalcular |
| `ventana_compra` (anticipada/intermedia/última hora) derivada de `antelacion_min_dias` | Agrupa por concepto de negocio, no por número crudo |
| **`id_canal = 0`** para la venta directa | En el OLTP `id_agencia` es `NULL` (correcto en 3NF), pero un `NULL` en la FK de un hecho obliga a `LEFT JOIN` en todos los reportes |
| Banderas `es_vendida` / `es_cancelada` / `es_expirada` precalculadas | Los patrones de cancelación salen con `SUM()`, sin `CASE WHEN` repetido |
| `factor_ocupacion` precalculado | Evita divisiones por cero repartidas por todas las consultas |
| `dias_antelacion` = fecha de vuelo − fecha de reserva | Métrica de negocio que en el OLTP habría que calcular en cada consulta |

### Resultado verificado (local)

| Objeto | Filas |
|---|---|
| Dimensiones (6) | 141 |
| `fact_tramo_vendido` | 8.794 |
| `fact_ocupacion_vuelo` | 227 |
| **Tiempo de ejecución** | **3,22 s** |

Salida de las tres vistas de negocio en `evidencia/olap/vistas-de-negocio.txt`.

---

## Qué servicio implementa el ETL

**AWS Glue ETL (Spark), 2 workers G.1X.** Y la justificación honesta empieza reconociendo
que **hoy es la opción más cara de las tres disponibles**:

| Opción en el Learner Lab | Costo por corrida | Límite que impone |
|---|---|---|
| **Glue ETL (Spark)** ✅ | ~$0.044 | Ninguno relevante |
| Glue Python Shell | ~$0.005 | Un solo núcleo, sin paralelismo |
| Lambda | ~$0.000 | **Tope duro de 15 minutos** y memoria acotada |

A 8.794 filas, las tres funcionan y Lambda sería gratis. **Se elige Spark por el escenario
que la propia rúbrica manda proyectar:**

> Con volumen ×10 o ×100, Lambda choca contra su tope de 15 minutos y Python Shell contra su
> único núcleo. Spark **paraleliza**: el tiempo no crece linealmente con el volumen. Se elige
> la opción que **no obliga a rediseñar** cuando el negocio crece.

Declarar que hoy es más cara es lo que vuelve creíble la elección: no se está justificando
una preferencia, se está pagando una opción sobre el futuro.

**Descartado también: script en una EC2.** Sería lo más barato, pero reintroduce un servidor
que administrar, parchear y monitorear — exactamente lo que `DEC-05` y el pilar de Excelencia
Operativa buscan evitar.

---

## Frecuencia de ejecución

**Diaria, no por evento.**

| Frecuencia | Costo mensual del ETL | ¿Lo justifica el negocio? |
|---|---|---|
| Por evento (CDC) | alto + complejidad | ❌ Ninguna pregunta de `FR-19` necesita tiempo real |
| **Diaria** ✅ | **~$1.30** | ✅ Son preguntas estratégicas: *ocupación por ruta*, *patrones de cancelación* |
| Horaria | ~$32 | ❌ 24× el costo para datos que se miran una vez por semana |

**El criterio es la frescura que el negocio consume, no la que es técnicamente posible.**
Nadie decide abrir una ruta nueva con datos de hace una hora en vez de un día.

⚠️ **Los crawlers van *on demand*, nunca programados.** El esquema no cambia todos los días,
sólo los datos. Un crawler diario catalogaría 30 veces el mismo esquema: ~$9/mes tirados.

**Estrategia de carga: recarga completa** (`TRUNCATE` + `INSERT`). A este volumen es lo
correcto — es idempotente, no arrastra estado y no puede quedar a medias. La carga incremental
por marca de agua sobre `historial_reserva.ocurrido_en` es la evolución prevista para cuando
la recarga deje de entrar en la ventana de proceso, no un pendiente.

---

## Conexión al Glue Data Catalog

```
              ┌──────────────────── VPC ────────────────────┐
              │                                             │
  Glue Job ───┼─▶ [SG auto-referenciado] ─┬─▶ RDS OLTP :5432│
  Crawler  ───┤                           └─▶ RDS OLAP :5432│
              │                                             │
              │   VPC Endpoint S3 (Gateway, GRATIS) ──▶ S3  │
              └─────────────────────────────────────────────┘
                              │
                    Glue Data Catalog
                  (ambas bases registradas)
```

| Pieza | Configuración |
|---|---|
| Conexión JDBC ×2 | `jdbc:postgresql://<endpoint>:5432/<base>` — **dos puntos y puerto explícito** |
| Rol IAM | **`LabRole`** (el lab no permite crear roles) |
| Red | VPC por defecto, subred en `us-east-1a`, **SG con regla auto-referenciada** |
| Salida a S3 | **VPC Endpoint tipo Gateway** — gratis |
| Crawlers ×2 | Uno por base, *on demand*, `Include path = <base>/%` |

### Las cinco trampas, ya pagadas en prácticas anteriores

Documentadas en el `CLAUDE.md` del curso. Aplican igual a PostgreSQL:

1. La URL JDBC va con **dos puntos** (`jdbc:postgresql://`), no punto, y **con el puerto**.
2. El SG de Glue necesita **regla auto-referenciada** (todo el tráfico con origen el propio
   grupo). Sin eso la conexión falla sin explicar por qué.
3. **Sin VPC Endpoint de S3 el crawler da timeout**: los workers corren dentro de la VPC sin
   IP pública. El endpoint Gateway es **gratis**; el NAT Gateway resuelve lo mismo a
   **$0.045/h** — más de un dólar por día. No usarlo.
4. `Service is unable to assume provided role` = se eligió un rol que no es `LabRole`.
5. El crawler **cobra por ejecución**: dejarlo *on demand*.

---

## Tabla de justificación de servicios

| Servicio AWS | Alternativa considerada | Requisito que lo sustenta | Pilar(es) Well-Architected |
|---|---|---|---|
| **RDS PostgreSQL** `db.t3.micro` (OLTP) | PostgreSQL autoadministrado en EC2 | `NFR-DISP-01` (99,9 %), `NFR-SEG-02` (cifrado en reposo) | **Fiabilidad** (backups y failover gestionados), **Seguridad** (parcheo y cifrado sin intervención) |
| **RDS PostgreSQL** `db.t3.micro` (OLAP) | Redshift · Athena sobre S3 | `FR-19`, `NFR-PERF-01` (la analítica no debe tocar el OLTP) | **Optimización de Costos** — Redshift `ra3.large` cuesta ~$780/mes contra ~$15: absurdo a esta escala. **Eficiencia del Rendimiento** — aísla la carga analítica |
| **AWS Glue ETL** (Spark, 2×G.1X) | Glue Python Shell · Lambda · script en EC2 | `FR-19`, `NFR-ESC-01` (absorber ×5 en temporada alta) | **Eficiencia del Rendimiento** (paraleliza, no choca contra topes), **Excelencia Operativa** (serverless, sin servidor que mantener) |
| **Glue Data Catalog** | Documentar el esquema a mano | Exigido explícitamente por el enunciado; habilita `FR-19` | **Excelencia Operativa** (metadatos vivos, no un documento que se desactualiza), **Sostenibilidad** (un catálogo compartido evita copias redundantes) |
| **Glue Crawler** ×2 | Definir las tablas a mano en el catálogo | Mantiene el catálogo sincronizado con `DEC-08` | **Excelencia Operativa** |
| **Conexión JDBC de Glue** (en VPC) | Hacer las bases públicamente accesibles | `NFR-SEG-01`, `NFR-SEG-02` | **Seguridad** — las bases nunca escuchan en una interfaz pública |
| **VPC Endpoint S3** (Gateway) | NAT Gateway | `NFR-SEG-02`; restricción de presupuesto | **Seguridad** (el tráfico no sale a internet), **Optimización de Costos** (gratis vs $0.045/h) |
| **Security Group auto-referenciado** | Abrir el 5432 a `0.0.0.0/0` | `NFR-SEG-02` | **Seguridad** — es la lección ya pagada en la práctica de Sakila |
| **LabRole** (IAM) | Rol dedicado con permisos mínimos | Restricción del Learner Lab | **Seguridad** — se declara la desviación: en producción correspondería un rol con privilegio mínimo por servicio |

---

## Proyección de costos

> Precios de **us-east-1**, On-Demand, a septiembre de 2026. Verificados contra la
> [AWS Pricing Calculator](https://calculator.aws). Mes = 730 horas.

| Concepto | Supuesto | Costo mensual |
|---|---|---|
| RDS OLTP | `db.t3.micro` PostgreSQL, 1 AZ, 20 GB gp2 · $0.018/h + $0.115/GB-mes | **$15.44** |
| RDS OLAP | idéntica | **$15.44** |
| Glue ETL | 2 DPU (G.1X) × ~3 min × 30 corridas/mes · $0.44/DPU-hora | **$1.32** |
| Crawlers | 2 crawlers × ~4 corridas/mes (on demand) · mínimo facturable 10 min | **$0.59** |
| Glue Data Catalog | ~30 tablas · el primer millón de objetos y de peticiones no se cobra | **$0.00** |
| VPC Endpoint S3 | tipo Gateway | **$0.00** |
| | **TOTAL** | **≈ $32.79 / mes** |

**Las dos instancias RDS son el 94 % del costo.** Cualquier optimización que no las toque es
irrelevante — dato que conviene tener a mano en la defensa.

### Costo real de este parcial

La proyección mensual es lo que pide el enunciado, pero **no es lo que se va a gastar**: las
instancias se crean el día de la ejecución, se captura la evidencia y se borran.

```
2 RDS × $0.018/h × ~6 h  +  1 corrida de ETL  +  2 crawlers   ≈  $0.40
```

### Escenario de crecimiento ×10

Hay dos formas de multiplicar por diez, y **no cuestan lo mismo**:

#### A) Volumen de datos ×10 (87.940 tramos)

| Concepto | Actual | ×10 | ¿Escala lineal? |
|---|---|---|---|
| RDS OLTP | $15.44 | **$28.28** (`db.t3.small`) | ❌ Sube un escalón de clase, no ×10 |
| RDS OLAP | $15.44 | **$28.28** | ❌ Íd. |
| Storage | (incluido) | incluido | ❌ 20 GB es el **mínimo** de RDS: no cambia hasta superarlo |
| Glue ETL | $1.32 | **$3.50** | ❌ Spark paraleliza: ~2,7× el tiempo, no 10× |
| Crawlers | $0.59 | $0.59 | ❌ El esquema no cambia con el volumen |
| Catálogo | $0 | $0 | ❌ Plano |
| **Total** | **$32.79** | **≈ $60.65** | **×1,85 — no ×10** |

#### B) Frecuencia ×10 (ETL cada 2,4 h en vez de diario)

| Concepto | Actual | ×10 | |
|---|---|---|---|
| Glue ETL | $1.32 | **$13.20** | ✅ Sí escala lineal: son 10× más corridas |
| Todo lo demás | $31.47 | $31.47 | Sin cambios |
| **Total** | **$32.79** | **≈ $44.67** | ×1,36 |

### Lectura para los pilares de Optimización de Costos y Sostenibilidad

**El costo está dominado por capacidad reservada (las RDS, encendidas 24×7), no por trabajo
realizado.** Tres consecuencias:

1. **Diez veces más datos cuestan menos del doble.** El cómputo del ETL, que es lo que
   escala con el volumen, es sólo el 4 % del total. Es un sistema con buena eficiencia
   marginal: crecer sale barato.
2. **Multiplicar la frecuencia sale más caro que multiplicar el volumen** ($13.20 contra
   $3.50 de incremento). Confirma la decisión de frecuencia diaria: la frescura innecesaria
   es el gasto evitable, no el tamaño de los datos.
3. **La palanca real de ahorro es apagar lo que no se usa.** En **Sostenibilidad**, la
   pregunta correcta no es "cómo proceso más barato" sino "por qué hay dos bases encendidas
   de noche cuando el ETL corre a las 03:00 y nadie consulta hasta las 08:00". Apagar la OLAP
   fuera de horario laboral recorta ~40 % de su costo sin afectar a ningún usuario.

⚠️ **Desviación declarada:** `NFR-DISP-01` pide 99,9 %, que exige Multi-AZ (~2× el costo de
cómputo). Con 50 USD de presupuesto **no se implementa**: el entregable corre en Single-AZ.
El requisito es de diseño para producción; la implementación lo declara en vez de disimularlo.

---

## Plan de ejecución en AWS (sesión única)

| # | Paso | Comprobación |
|---|---|---|
| 1 | Borrar los objetos de Glue huérfanos de la práctica de Sakila | El catálogo del parcial queda limpio |
| 2 | Crear 2 RDS PostgreSQL `db.t3.micro`, sin *enhanced monitoring* | Estado `available` |
| 3 | Cargar `01-esquema.sql`, `02-datos-demo.sql`, `03-actividad-demo.sql` en la OLTP y `01-esquema-estrella.sql` en la OLAP | 17 tablas + 9 objetos DW |
| 4 | Crear SG de Glue con **regla auto-referenciada** y permitir 5432 desde él en ambas bases | Trampa 2 |
| 5 | Verificar/crear el **VPC Endpoint de S3** | Trampa 3 |
| 6 | Crear 2 conexiones JDBC y probarlas con `LabRole` | Trampas 1 y 4 |
| 7 | Correr los 2 crawlers → **ambas bases en el Data Catalog** | Requisito explícito del enunciado |
| 8 | Ejecutar el job de ETL | Filas en el OLAP |
| 9 | **Capturar evidencia** → `evidencia/glue/` | Capturas del catálogo con ambas bases |
| 10 | **Borrar las dos RDS** | Presupuesto |

El código del ETL no cambia entre local y AWS: las conexiones vienen de `DSN_OLTP` y
`DSN_OLAP` como variables de entorno.

## Baja de recursos

⚠️ Las dos RDS suman ~$4.60/mes de storage **aunque estén detenidas**, y AWS las reinicia
solas a los 7 días. Después de la defensa **se borran**, no se detienen: el esquema, los datos
semilla y los scripts quedan en el repo y recrear todo son 5 minutos.

## Defensa: qué se rompe si esto cambia (§7)

| Si cambia… | Qué se toca | Costo | Alternativa ya considerada |
|---|---|---|---|
| **La analítica debe ser en tiempo real** | Cambia la frecuencia del ETL, o se pasa a CDC. **No cambia el backend ni el modelo**: la frontera de `DEC-08` sigue valiendo. El costo del ETL ×10, no el total | Medio, aislado | La tabla de frecuencias ya tiene el número |
| **Volumen ×100** | Las RDS suben de clase; el ETL en Spark absorbe sin rediseño — **que es exactamente por lo que se eligió Spark** y no Lambda | Medio | Lambda: habría chocado contra los 15 min |
| **Piden agregar una métrica nueva** (ej. ingreso por aeronave) | `dim_vuelo` ya tiene la ruta; se agrega `dim_aeronave` y una FK al hecho. El grano no cambia | Bajo | El grano a nivel tramo se eligió sin pre-agregar justamente para esto |
| **Hay que reducir el costo a la mitad** | Apagar la OLAP fuera de horario laboral y bajar la frecuencia del ETL. Las RDS son el 94 % del costo: cualquier otra optimización es ruido | Bajo | Está en la lectura de Sostenibilidad |
| **El profesor pide Athena en vez de la RDS OLAP** | El ETL escribiría Parquet a S3 en vez de a PostgreSQL. El esquema estrella **no cambia**; cambia el destino | Medio | Descartado acá porque el enunciado exige PostgreSQL para el OLAP |
| **Se exige Multi-AZ** | Duplica el costo de cómputo de las RDS ($30.88 → ~$61.76/mes). No toca ni el modelo ni el ETL | Alto, sólo dinero | Declarado como desviación consciente |
