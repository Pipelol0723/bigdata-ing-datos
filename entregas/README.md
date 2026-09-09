# Entregas — Big Data e Ingeniería de Datos (PCIA 5010)

Índice de todo lo que se entrega en el curso. **Canal de entrega: correo al profesor y
presentación en clase** — las tareas de Moodle de las semanas 1 a 4 tienen la fecha de cierre
vencida y el módulo ya no acepta envíos (verificado el 07/09; ver
[`../notas/plan-moodle-backlog.md`](../notas/plan-moodle-backlog.md)).

---

## Estado

| Semana | Actividad | Carpeta | Estado |
|---|---|---|---|
| 1 | Session 1 — Las 5 V, casos de uso y roles | [`semana-01/sesion-01-cinco-v-y-roles/`](semana-01/sesion-01-cinco-v-y-roles/) | ✅ escrita |
| 1 | Session 2 — Arquitecturas de datos | — | ✅ **ya entregada** en Moodle (06/08) |
| 1 | Module 1 — Welcome to AWS Academy DE | [`modulos-aws-academy/`](modulos-aws-academy/) | ⬜ pendiente |
| 2 | Session 3 — Diagramación y anatomía de un ADR | [`semana-02/sesion-03-diagramacion-y-adr/`](semana-02/sesion-03-diagramacion-y-adr/) | ✅ escrita |
| 2 | Session 4 — Setup y dos arquitecturas alternativas | [`semana-02/sesion-04-setup-y-alternativas/`](semana-02/sesion-04-setup-y-alternativas/) | ✅ escrita |
| 2 | Module 2 — Data-Driven Organizations | [`modulos-aws-academy/`](modulos-aws-academy/) | ⬜ pendiente |
| 3 | Session 5 — **ADR #1: esquema de particionado** | [`semana-03/sesion-05-adr-01-particionado/`](semana-03/sesion-05-adr-01-particionado/) | ✅ escrita |
| 3 | Session 6 — S3: clases, versionado y lifecycle | [`semana-03/sesion-06-s3-clases-versionado-lifecycle/`](semana-03/sesion-06-s3-clases-versionado-lifecycle/) | ✅ **aplicada en AWS (08/09)** |
| 3 | Module 3 — The Elements of Data | [`modulos-aws-academy/`](modulos-aws-academy/) | ⬜ pendiente |
| 4 | Session 7 — Glue Data Catalog y Crawlers | [`semana-04/sesion-07-glue-catalog-crawlers/`](semana-04/sesion-07-glue-catalog-crawlers/) | ✅ **evidencia capturada (08/09)** |
| 4 | **Checkpoint 1** (nota de proyecto) | [`semana-04/checkpoint-1/`](semana-04/checkpoint-1/) | ✅ **bucket y crawler ejecutados (08/09)** |
| 4 | Module 4 — Design Principles for Pipelines | [`modulos-aws-academy/`](modulos-aws-academy/) | ⬜ pendiente |
| 5 | **Parcial 1** — Sistema de reservas | [`parcial-1-aerolinea/`](parcial-1-aerolinea/) | ✅ **8 de 8 secciones** · falta ensayar la defensa |
| — | EC2 + Apache (práctica anterior) | [`ec2-apache/`](ec2-apache/) | ✅ entregada |

**La sesión de AWS se ejecutó el 08/09 y cerró todo lo que dependía de ella.** Lo único
pendiente son los **cuatro módulos de AWS Academy**, que viven en otra plataforma.

---

## Cómo está armado esto

### Un caso, todo el curso

Todos los entregables usan **el mismo caso**: el sistema de reservas de la aerolínea del Parcial 1.
No es comodidad — es que las cifras de cada documento son **mediciones reproducibles** de un
sistema que existe, no ejemplos de manual. Un ejemplo prestado no se puede defender en una
sustentación; uno propio, sí.

Eso además encadena los documentos: el umbral de volumen calculado en la Sesión 1 es el disparador
que la Sesión 4 usa para decidir batch sobre streaming, y el tamaño de archivo del ADR #1 es lo que
en la Sesión 6 explica por qué Standard-IA saldría más caro que Standard.

### Estructura de cada entregable

> **Qué pedía la sesión** · **Caso** · **Desarrollo** · **Evidencia** · **Decisiones y alternativa
> descartada** · **Qué generó la IA y qué corregí**

El último bloque no es decorativo: el syllabus condiciona el uso de IA a *"que el estudiante pueda
explicar, depurar y modificar manualmente cualquier línea de código generado"*, y el curso lo
evalúa sesión tras sesión — la política de lifecycle revisada línea por línea (S6), el
*find-the-AI-bug* (S12), manual vs generado (S14), código asistido + review (S17).

### Diagramas como código

[`_comun/diagramas/generar.py`](_comun/diagramas/generar.py) genera los cinco diagramas del curso
con iconografía oficial de AWS:

```bash
pip install diagrams        # requiere Graphviz en el PATH
python _comun/diagramas/generar.py
```

Quedan versionados junto al sistema que describen y se regeneran con un comando, así que no se
desincronizan en silencio.

---

## ✅ Sesión de AWS — ejecutada el 08/09

Evidencia completa en
[`parcial-1-aerolinea/evidencia/aws/sesion-2026-09-08.md`](parcial-1-aerolinea/evidencia/aws/sesion-2026-09-08.md).

| Recurso | Identificador |
|---|---|
| Bucket del data lake | `datalake-aerolinea-936980625651` |
| RDS OLTP / OLAP | `parcial-oltp` · `parcial-olap` (PostgreSQL 18.3) |
| SG de Glue (auto-referenciado) | `sg-0b3237efc5e6f8c1e` |
| SG de las bases | `sg-0a85ff98fa816dff8` |
| VPC Endpoint de S3 (gratis) | `vpce-09b60424dc9c1f1cf` |
| Databases del catálogo | `aerolinea_raw` (17) · `aerolinea_processed` (17) · `aerolinea_catalog` (8) |
| Crawlers | `crawler-datalake-aerolinea` · `crawler-raw` · `crawler-processed` |
| Job de Glue (dentro de la VPC) | `job-raw-processed` — SUCCEEDED en 149 s |
| Conexiones JDBC | `conn-parcial-oltp` · `conn-parcial-olap` |

Tres mediciones que el trabajo local no podía dar:

- **AWS respondió `TransitionDefaultMinimumObjectSize: all_storage_classes_128K`** al aplicar el
  lifecycle — confirma el análisis de costos de la Sesión 6 desde el propio servicio.
- **8.893 hechos cayeron en 2 particiones**, no en 60: el ADR #1 acertó el cálculo.
- **Athena escaneó 4.614 bytes** para consultar esas 8.893 filas. Eso es Parquet columnar.

**Y la medición que cierra el argumento del formato:** la misma consulta sobre `reserva`
escaneó **586.285 bytes en CSV** y **2.335 en Parquet** — 251 veces menos, misma respuesta.
El CSV escanea lo mismo sin importar qué se le pregunte.

Costo real de las dos sesiones: **~$0,64**.

💰 El bucket **no se borra**: cuesta centavos y lo necesitan el Checkpoint 2 y el resto del curso.
Las RDS quedan hasta la sustentación del 10/09 y **se borran ese día** — cobran almacenamiento
aunque estén detenidas, y AWS las reinicia solas a los 7 días.
