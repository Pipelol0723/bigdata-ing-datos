# 5.2 Requisitos no funcionales (NFR)

> **Estado:** ⬜ pendiente — planificado para el jueves 3/09
> **Peso en la rúbrica:** 10%

## Qué exige la rúbrica para "Sobresaliente"

> *"Métricas concretas rastreables hasta un riesgo de negocio explícito, particularmente
> concurrencia."*

Y el enunciado avisa: **no alcanza con escribir "debe ser rápido" o "debe ser seguro"**.
Un NFR sin número no se puede verificar, y sin verificar no se puede evaluar.

**Regla propia:** todo NFR de esta sección tiene (1) un número, (2) cómo se mide, y
(3) el riesgo de negocio `RSK-` que lo justifica.

## Riesgos de negocio identificados

| ID | Riesgo | Consecuencia si se materializa |
|---|---|---|
| `RSK-01` | | |

## Tabla de requisitos no funcionales

| ID | Categoría | Requisito (con métrica) | Cómo se verifica | Riesgo que mitiga |
|---|---|---|---|---|
| `NFR-PERF-01` | Performance | | | |
| `NFR-CONC-01` | Concurrencia | | | |
| `NFR-DISP-01` | Disponibilidad | | | |
| `NFR-SEG-01` | Seguridad | | | |
| `NFR-ESC-01` | Escalabilidad | | | |
| `NFR-AUD-01` | Auditabilidad | | | |

## Preguntas guía a resolver (una por categoría)

- [ ] **Performance** — ¿Qué tiempo de respuesta es aceptable para una búsqueda de
      disponibilidad? ¿Cambia si hay escalas?
- [ ] **Consistencia / Concurrencia** — Si dos pasajeros intentan reservar el último asiento
      al mismo tiempo, ¿qué debe garantizar el sistema?
- [ ] **Disponibilidad** — ¿Qué número (99%, 99.9%, 99.99%) traduce "no puede caerse en
      temporada alta", y qué implica eso en costo y complejidad?
- [ ] **Seguridad** — ¿Cómo se protegen los datos de pago y los datos personales?
      ¿Aplica alguna normativa?
- [ ] **Escalabilidad** — Si la aerolínea suma 20 rutas en un año, ¿qué parte de la
      arquitectura es el primer cuello de botella?
- [ ] **Auditabilidad** — ¿Qué tan importante es reconstruir el historial completo de
      cambios de una reserva?

> ⚠️ `NFR-CONC-01` es el requisito bisagra de todo el trabajo: se diseña acá, se resuelve
> arquitectónicamente en 5.4, se implementa en 5.6 y se prueba con evidencia en
> `evidencia/concurrencia/`. Los cuatro tienen que decir lo mismo.

## Impacto de la restricción específica (§3)

⏳ Pendiente de asignación.
