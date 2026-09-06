# Parcial 1 — Sistema de Reservas de una Aerolínea

**Materia:** Big Data e Ingeniería de Datos
**Entrega final:** jueves 10 de septiembre de 2026
**Modalidad:** individual
**Defensa oral:** eliminatoria por sección
**Enunciado:** [`enunciado.md`](enunciado.md) — copia íntegra, en el repo

⚠️ **El enunciado (§6) define DOS entregas, no una:**

| Entrega | Contenido |
|---|---|
| **Parcial** | Sólo requisitos funcionales y no funcionales (5.1 y 5.2) |
| **Final** | Documento completo: contexto, FR, NFR, modelo ER, arquitectura backend y frontend, implementación backend (5.6), implementación AWS (5.7) y anexo de prompt log |

En Moodle sólo figura una tarea **"Parcial 1"**, sin fechas de apertura ni cierre.
**Preguntar si la entrega parcial ya pasó o si las dos se juntan el 10/09.**

---

## Cómo leer este trabajo

Los archivos de `documento/` se leen en orden numérico. Cada uno resuelve una sección
del enunciado y declara explícitamente qué requisito origina cada decisión.

| # | Sección | Peso | Archivo | Estado |
|---|---|---|---|---|
| — | Contexto y supuestos | — | `documento/00-contexto-y-supuestos.md` | 🟡 borrador 06/09 |
| 5.1 | Requisitos funcionales | 10% | `documento/01-requisitos-funcionales.md` | 🟡 borrador 06/09 |
| 5.2 | Requisitos no funcionales | 10% | `documento/02-requisitos-no-funcionales.md` | 🟡 borrador 06/09 |
| 5.3 | Modelo entidad-relación | 15% | `documento/03-modelo-er.md` | 🟡 borrador 06/09 |
| 5.4 | Arquitectura backend | 15% | `documento/04-arquitectura-backend.md` | ⬜ |
| 5.5 | Arquitectura frontend | (dentro del 15%) | `documento/05-arquitectura-frontend.md` | ⬜ |
| 5.6 | Primera implementación backend | 10% | `documento/06-implementacion-backend.md` | ⬜ |
| 5.7 | AWS: ETL, catálogo y costos | 20% | `documento/07-aws-etl-glue-costos.md` | ⬜ |
| §4 | Prompt log (anexo) | obligatorio | `documento/99-prompt-log.md` | 🟡 en curso |

Claridad y trazabilidad del documento: 10% adicional, transversal a todas las secciones.

## Estructura del repositorio

```
parcial-1-aerolinea/
├── documento/     Secciones del informe, en Markdown
├── diagramas/     Diagrama ER (Crow's Foot) y diagrama de arquitectura
├── api/           Implementación FastAPI (sección 5.6)
├── db/oltp/       Esquema y datos de la base transaccional
├── db/olap/       Esquema de la base analítica
├── etl/           Script del proceso ETL (sección 5.7)
├── infra/         Scripts de creación y baja de recursos AWS
└── evidencia/     Capturas y salidas que respaldan lo que afirma el documento
    ├── concurrencia/   Prueba de sobreventa: sin lock y con lock
    └── glue/           Ambas bases registradas en el Data Catalog
```

---

## Convenciones de identificadores

La trazabilidad vale el 10% de la nota: toda decisión debe poder rastrearse hasta el
requisito que la origina. Para eso, todo lleva ID y toda decisión cita los IDs que la sustentan.

| Prefijo | Significado | Ejemplo |
|---|---|---|
| `SUP-nn` | Supuesto declarado | `SUP-03` |
| `FR-nn` | Requisito funcional | `FR-07` |
| `NFR-<CAT>-nn` | Requisito no funcional | `NFR-CONC-01` |
| `DEC-nn` | Decisión de arquitectura | `DEC-04` |
| `RSK-nn` | Riesgo de negocio identificado | `RSK-02` |

Categorías de NFR: `PERF` (performance), `CONC` (consistencia y concurrencia),
`DISP` (disponibilidad), `SEG` (seguridad), `ESC` (escalabilidad), `AUD` (auditabilidad).

**Regla:** ninguna decisión de arquitectura entra al documento sin citar al menos un
`FR-` o `NFR-`. Si no se puede citar ninguno, o falta el requisito o sobra la decisión.

---

## La restricción del equipo y la defensa oral

**Lo que se comunicó (01/09):** el día de la sustentación el profesor plantea un cambio,
mejora o problema, y hay que proponer una solución **en el momento**, basada en cómo está
construido el sistema. No hay nada extra que implementar.

✅ **Confirmado con el profesor (06/09): la §3 de este equipo se recibe en la defensa.**
No hay una restricción escrita que integrar antes de entregar.

⚠️ Vale dejar constancia de la tensión con el texto del enunciado, por si el que corrige
no es quien lo confirmó. El enunciado separa las dos cosas: la §3 dice que la restricción
se entrega *"independently and confidentially"* y que debe quedar *"coherently integrated
into all of the exercise's deliverables: requirements, data model, and architecture"*; la §7
la menciona aparte, como algo que hay que poder defender. Y la rúbrica de requisitos
funcionales reserva el nivel Sobresaliente para quien *"integra la restricción específica
del equipo"*.

**Mitigación (barata):** dejar esta confirmación anotada por escrito en
`documento/00-contexto-y-supuestos.md` como supuesto declarado, con fecha. Si un corrector
busca la §3 y no la encuentra, el documento explica por qué no está en vez de parecer un
olvido. Un supuesto declarado es una decisión; uno no declarado es un agujero.

### Qué implica para el diseño

No cambia **qué** se construye, cambia **qué se evalúa**: la capacidad del diseño de absorber
un cambio no previsto. Si ante *"ahora se permite overbooking del 5%"* la respuesta es
*"cambio un parámetro de política y se propaga solo"*, el diseño aprobó. Si es *"habría que
rehacer el modelo"*, no.

Y esa diferencia se decide **al diseñar, no al defender**. Tres decisiones ya tomadas apuntan ahí:

| Decisión | Para qué sirve el día de la defensa |
|---|---|
| Columna **"alternativa descartada"** en cada tabla `DEC-` | Banco de respuestas precalculado: *"lo consideramos; acá está la alternativa y esto es lo que habría que tocar"* |
| **Trazabilidad** `FR-`/`NFR-` en cada decisión | *"¿Qué parte del diseño se ve afectada?"* se contesta siguiendo los enlaces hacia atrás, no improvisando |
| **Políticas parametrizables** en vez de invariantes rígidos | `capacidad_vendible = f(capacidad_física, política_comercial)`: una regla nueva entra como configuración, no como rediseño |

### Mapa de impacto

Cada sección del documento cierra con un bloque **"Defensa: qué se rompe si esto cambia"**.
Completarlos es lo que convierte la sustentación en una lectura y no en una improvisación.

Banco de variaciones a ensayar el 09/09: overbooking · programa de viajero frecuente ·
cambio de fecha con penalidad · codeshare con otra aerolínea · volumen ×100 · caída del
proveedor de pagos · derecho al olvido sobre los datos de un pasajero.

---

## Entorno

Todo el trabajo práctico corre en un **AWS Academy Learner Lab** con presupuesto de 50 USD.
Ver `../../CLAUDE.md` para límites del entorno, credenciales y checklist de apagado.
