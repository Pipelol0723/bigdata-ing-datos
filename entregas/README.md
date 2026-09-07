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
| 3 | Session 6 — S3: clases, versionado y lifecycle | [`semana-03/sesion-06-s3-clases-versionado-lifecycle/`](semana-03/sesion-06-s3-clases-versionado-lifecycle/) | 🟡 escrita · falta aplicar en AWS |
| 3 | Module 3 — The Elements of Data | [`modulos-aws-academy/`](modulos-aws-academy/) | ⬜ pendiente |
| 4 | Session 7 — Glue Data Catalog y Crawlers | [`semana-04/sesion-07-glue-catalog-crawlers/`](semana-04/sesion-07-glue-catalog-crawlers/) | 🟡 escrita · falta evidencia de AWS |
| 4 | **Checkpoint 1** (nota de proyecto) | [`semana-04/checkpoint-1/`](semana-04/checkpoint-1/) | 🟡 armado · falta ejecutar el bucket y el crawler |
| 4 | Module 4 — Design Principles for Pipelines | [`modulos-aws-academy/`](modulos-aws-academy/) | ⬜ pendiente |
| 5 | **Parcial 1** — Sistema de reservas | [`parcial-1-aerolinea/`](parcial-1-aerolinea/) | 🟡 7 de 8 secciones · falta la sesión de AWS |
| — | EC2 + Apache (práctica anterior) | [`ec2-apache/`](ec2-apache/) | ✅ entregada |

**Lo único que bloquea a los cinco 🟡 es una sola sesión de AWS.** Todo lo demás está escrito.

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

## Pendiente de AWS — una sola sesión

Todo lo que sigue se hace en la misma sesión del lab, después de la del Parcial 1:

1. `bash semana-04/checkpoint-1/crear-data-lake.sh` — bucket, zonas, versionado, lifecycle.
2. Capturar `get-bucket-lifecycle-configuration` → evidencia de la **Sesión 6**.
3. Conexiones JDBC + crawler sobre las bases del parcial → evidencia de la **Sesión 7**.
4. Una consulta de Athena sobre las tablas catalogadas.
5. Borrar los objetos de Glue huérfanos de la práctica de Sakila.

💰 El bucket cuesta centavos y **no se borra**: lo necesitan el Checkpoint 2 y el resto del curso.
Las RDS sí se borran — cobran storage aunque estén detenidas.
