# Parcial 1 — Sistema de Reservas de una Aerolínea

**Materia:** Big Data e Ingeniería de Datos
**Entrega final:** jueves 10 de septiembre de 2026
**Modalidad:** individual
**Defensa oral:** eliminatoria por sección

---

## Cómo leer este trabajo

Los archivos de `documento/` se leen en orden numérico. Cada uno resuelve una sección
del enunciado y declara explícitamente qué requisito origina cada decisión.

| # | Sección | Peso | Archivo | Estado |
|---|---|---|---|---|
| — | Contexto y supuestos | — | `documento/00-contexto-y-supuestos.md` | ⬜ |
| 5.1 | Requisitos funcionales | 10% | `documento/01-requisitos-funcionales.md` | ⬜ |
| 5.2 | Requisitos no funcionales | 10% | `documento/02-requisitos-no-funcionales.md` | ⬜ |
| 5.3 | Modelo entidad-relación | 15% | `documento/03-modelo-er.md` | ⬜ |
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

## Restricción específica del equipo (§3)

⏳ **Pendiente de asignación.**

Cuando llegue, se integra en las secciones marcadas con el bloque
`## Impacto de la restricción específica (§3)` que ya existe en cada archivo.

Mitigación adoptada mientras tanto: las reglas de negocio sensibles se modelan como
**políticas parametrizables**, no como invariantes rígidos. Ejemplo concreto: la capacidad
vendible se define como `f(capacidad_física, política_comercial)` en vez de fijarla igual a
la capacidad del avión. Así, una restricción del tipo "se permite overbooking del 5%" entra
como configuración y justificación nueva, no como rediseño.

---

## Entorno

Todo el trabajo práctico corre en un **AWS Academy Learner Lab** con presupuesto de 50 USD.
Ver `../../CLAUDE.md` para límites del entorno, credenciales y checklist de apagado.
