# Plan del curso — Big Data e Ingeniería de Datos

> Relevado del campus virtual el **2026-09-06**.
> Curso `CC-IA-02`, id 3167 · [campus](https://campusvirtual.usergioarboleda.edu.co/course/view.php?id=3167)

---

## 🔴 Resumen ejecutivo

**De 13 entregas ya vencidas, sólo 1 está enviada.** La única con envío registrado es *Session 2 — Assignment* (venció el 6 de agosto).

Pero el panorama es mejor de lo que ese número sugiere: **buena parte del trabajo técnico de las semanas 4 y 5 ya está hecho** en las sesiones de laboratorio — falta documentarlo y entregarlo, no construirlo.

### ⚠️ Dato clave a verificar con el profesor

Al abrir las tareas en Moodle **no aparece ningún botón de "Agregar entrega"**. Sólo está la casilla manual de "Marcar como completado".

Eso admite dos lecturas muy distintas:

- **(a)** Las tareas son *offline*: se entregan en clase o por otro canal (Teams, correo, repositorio) y Moodle sólo registra la nota.
- **(b)** La fecha límite de corte ya pasó y Moodle cerró los envíos.

En el listado, las semanas 1-2 figuran como **"No entregado"** y las 3-5 como **"Sin entrega"**. Esa diferencia sugiere la lectura (a) — que están configuradas como actividades sin envío en línea. **Confirmarlo es lo primero**, porque cambia todo el plan.

---

## 📊 Estado de entregas (semanas vencidas)

| Semana | Actividad | Vencía | Estado |
|---|---|---|---|
| 1 | Session 1 — Assignment | 3 ago | ❌ No entregado |
| 1 | **Session 2 — Assignment** | 6 ago | ✅ **Enviado para calificar** |
| 1 | Module 1 — Welcome to AWS Academy DE | 7 ago | ❌ No entregado |
| 2 | Session 3 — Assignment | 10 ago | ❌ No entregado |
| 2 | Session 4 — Assignment | 13 ago | ❌ No entregado |
| 2 | Module 2 — Data-Driven Organizations | 14 ago | ❌ No entregado |
| 3 | Session 5 — Assignment (+ **ADR #1**) | 17 ago | ❌ Sin entrega |
| 3 | Session 6 — Assignment | 20 ago | ❌ Sin entrega |
| 3 | Module 3 — The Elements of Data | 21 ago | ❌ Sin entrega |
| 4 | Session 7 — Assignment | 24 ago | ❌ Sin entrega |
| 4 | **Session 8 — CHECKPOINT 1** | 27 ago | ❌ Sin entrega |
| 4 | Module 4 — Design Principles for Pipelines | 28 ago | ❌ Sin entrega |
| 5 | **Parcial 1** | sin fecha | ❌ No entregado |

Ninguna tiene calificación asignada todavía (columna vacía en todas, incluida la enviada).

**La semana 6 (7-12 sep, la que arranca mañana) no tiene tareas cargadas en Moodle.**

---

## 🎯 Evaluación

| Período | Assignments + quizzes | Proyecto |
|---|---|---|
| 1 | 15 % | 15 % |
| 2 | 15 % | 15 % |
| 3 | 20 % | 20 % |

Los **checkpoints** son las notas de proyecto: Checkpoint 1 (sem. 4), Checkpoint 2 (sem. 11), Defensa final (sem. 14).

---

## ✅ Lo que YA está hecho (aunque no entregado)

Trabajo técnico completado en las sesiones de laboratorio, con evidencia en este repo:

| Requisito del curso | Estado | Dónde está |
|---|---|---|
| EC2 + servidor web | ✅ hecho | `entregas/ec2-apache/` |
| RDS MySQL + dataset (Sakila) | ✅ hecho | bitácora del `CLAUDE.md` |
| **Glue Data Catalog + Crawler** (sem. 4, sesión 7) | ✅ hecho | sección Glue del `CLAUDE.md` |
| **Conexión JDBC Glue → RDS** (sem. 5, sesión 9) | ✅ hecho | `Jdbc connection` |
| Consultas SQL sobre el dataset | ✅ hecho | `consultas/` (7 archivos) |

### Lo que falta para cerrar el Checkpoint 1

El enunciado pide: *architecture diagram + ADR + bucket/crawler implementation, defended orally*.

| Pieza | Estado |
|---|---|
| Crawler implementado | ✅ ya está |
| **Bucket S3** | ❌ **nunca se creó uno** |
| **Diagrama de arquitectura** | ❌ falta |
| **ADR** (Architecture Decision Record) | ❌ falta |

Son tres piezas, y dos son documentación pura — no requieren gastar presupuesto de AWS.

---

## 📅 Calendario completo

### Período vencido

| Sem | Fechas | Sesiones | Módulo AWS Academy |
|---|---|---|---|
| 1 | 3–7 ago | Introducción a Big Data (las 5 V, roles del ingeniero vs científico vs arquitecto) · Arquitecturas de datos (DW vs data lake, batch vs streaming) + Well-Architected | M1: Welcome |
| 2 | 10–14 ago | Cómo diagramar arquitecturas AWS (iconos oficiales, anatomía de un ADR) · Taller: setup del entorno + 2 arquitecturas alternativas | M2: Data-Driven Organizations |
| 3 | 17–21 ago | Diseño de data lake (zonas raw/processed/curated, particionado, CSV/JSON/Parquet) — **ADR #1** · S3 a fondo (clases, versionado, lifecycle) | M3: The Elements of Data |
| 4 | 24–28 ago | **Glue Data Catalog y Crawlers** · Taller + **CHECKPOINT 1** | M4: Design Principles for Pipelines |
| 5 | 31 ago–4 sep | Ingesta batch — Glue Jobs leyendo S3 y RDS/Aurora por JDBC · Ingesta streaming — Kinesis Streams vs Firehose | M5: Securing and Scaling |

### Lo que viene

| Sem | Fechas | Sesiones | Módulo |
|---|---|---|---|
| 6 | 7–12 sep | DynamoDB como sink NoSQL (partition/sort key) · Taller: pipeline de streaming con datos sintéticos | M6: Ingesting and Preparing |
| — | 14–19 sep | **sin clase** (semana buffer institucional) | — |
| 7 | 21–25 sep | Fundamentos de Spark · PySpark aplicado (transformaciones, joins, window functions) | M7: Batch or Stream |
| 8 | 28 sep–2 oct | Glue ETL serverless (límites del lab: G.1X, 10 workers) · Arquitectura de clúster EMR | M8: Storing and Organizing |
| — | 5–12 oct | **sin clase** (semana de receso) | — |
| 9 | 13–17 oct | Taller: job de transformación completo en Glue · Matriz de decisión Glue vs EMR | M9: Processing Big Data |
| 10 | 19–24 oct | Athena (optimización por escaneo, formatos columnares) · Redshift MPP — **ADR #2** | M10: Processing Data for ML |
| 11 | 26–30 oct | Modelado dimensional (estrella/copo) · **CHECKPOINT 2**: carga a Redshift (COPY desde S3) | M11: Analyzing and Visualizing |
| 12 | 2–6 nov | Step Functions (máquinas de estado, reintentos) · EventBridge + Lambda, SNS/SQS | M12: Automating the Pipeline |
| 13 | 9–13 nov | SageMaker notebooks contra Athena/Redshift vía boto3 · Auditoría con Well-Architected Tool | M13: Bridging to Certification |
| 14 | 16–28 nov | Consolidación · **DEFENSA FINAL** | Capstone Project |

---

## 🗺️ Plan propuesto

### Prioridad 1 — Checkpoint 1 (nota de proyecto, 15 %)

Es lo más valioso y lo más cerca de estar listo. Faltan tres piezas:

1. **Crear el bucket S3** con las zonas del data lake (`raw/`, `processed/`, `curated/`). Costo: centavos.
2. **Diagrama de arquitectura** con iconos oficiales de AWS. Herramienta: draw.io o la librería `diagrams` de Python (Graphviz ya está instalado localmente).
3. **ADR #1** documentando las decisiones ya tomadas: por qué RDS y no MySQL en EC2, por qué Glue y no scripts propios, por qué Parquet, por qué la conexión JDBC con Security Group grupo-a-grupo.

El ADR casi se escribe solo: **las decisiones ya están tomadas y razonadas en el `CLAUDE.md`**. Es cuestión de pasarlas al formato ADR (contexto / decisión / alternativas / consecuencias).

### Prioridad 2 — Módulos de AWS Academy

Son 4 vencidos (M1 a M4) y viven en la plataforma de AWS Academy, no en Moodle. Suelen ser lectura + quiz autoevaluado. **Verificar cuánto tiempo llevan.**

### Prioridad 3 — Assignments de sesión

11 vencidos. Falta saber qué piden exactamente: **en Moodle no tienen enunciado**, sólo el título y las fechas. El contenido real está en la descripción de cada sesión (recogida arriba) o se dio en clase.

### Prioridad 4 — Parcial 1

Aparece sin fecha de apertura ni cierre. **Preguntar si es presencial, si ya pasó, o si está por venir.**

---

## ❓ Preguntas abiertas (para el profesor o para verificar)

1. **¿Cómo se entregan las tareas?** Moodle no muestra botón de envío. ¿Es en clase, por Teams, por correo?
2. **¿Siguen aceptándose entregas atrasadas?** Y si sí, ¿con penalización?
3. **¿Qué pedía cada assignment de sesión?** Los enunciados no están en Moodle.
4. **Parcial 1** — ¿pendiente, ya pasado, presencial?
5. **¿Los módulos de AWS Academy se validan solos** al completarlos en esa plataforma, o hay que reportarlos en Moodle?

---

## 📎 Enlaces directos a las tareas

| Actividad | Enlace |
|---|---|
| Session 1 | [273063](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273063) |
| Session 2 ✅ | [273065](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273065) |
| Module 1 | [273066](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273066) |
| Session 3 | [273068](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273068) |
| Session 4 | [273070](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273070) |
| Module 2 | [273071](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273071) |
| Session 5 | [273073](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273073) |
| Session 6 | [273075](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273075) |
| Module 3 | [273076](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273076) |
| Session 7 | [273078](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273078) |
| **Session 8 — Checkpoint 1** | [273079](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273079) |
| Module 4 | [273080](https://campusvirtual.usergioarboleda.edu.co/mod/assign/view.php?id=273080) |
