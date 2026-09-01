# Anexo — Registro de prompts (§4)

> **Estado:** 🟡 en curso — se completa a medida que se avanza, no al final.

## Por qué este anexo existe

El enunciado permite el uso de asistentes de IA con una condición explícita:

> *"el documento final debe incluir, como anexo, un breve registro de los principales
> prompts utilizados durante el ejercicio y cómo fueron refinados o corregidos por el equipo"*

Lo que se evalúa no es el prompt perfecto, sino **la iteración**: qué se pidió, qué devolvió
la herramienta, y qué hubo que corregirle. Por eso este archivo se escribe en el momento, no
se reconstruye al final.

**Asistente utilizado:** Claude (Claude Code, modelo Opus).

---

## Registro

### 2026-09-01 — Análisis del enunciado y planificación

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 1 | Entender qué pesa en la nota | Se adjuntó el enunciado con la instrucción explícita: *"léela, dime lo importante y **planea sin hacer nada**, pregúntame todo lo que necesites"* | Análisis de la rúbrica, plan por fases y 4 preguntas de decisión | **La restricción "sin hacer nada" fue deliberada.** Sin ella el asistente arranca produciendo documento antes de entender el enunciado. Forzarlo a planificar y preguntar primero fue lo que hizo aparecer el análisis de pesos de la rúbrica. |
| 2 | Corregir jerga sin definir | *"¿qué es FR+NFR? explícame todo sin entrar en mucho detalle a menos que te lo pida"* | Explicación general del proyecto y de OLTP vs OLAP | El asistente había usado siglas sin traducir. Se le corrigió el registro: explicación de alto nivel primero, profundidad sólo bajo pedido. |
| 3 | Decisión de infraestructura | Ante la opción de reutilizar la RDS MySQL y las conexiones Glue de prácticas anteriores, se decidió **crear todo nuevo** | El asistente había recomendado reutilizar para ahorrar presupuesto | **Decisión propia, en contra de la sugerencia del asistente.** Reutilizar obligaba a explicar en la defensa por qué un componente venía prestado de otra práctica. La coherencia del trabajo pesa más que ~$2 de ahorro. |
| 4 | Manejar la restricción faltante (§3) | Se le planteó que la restricción específica todavía no fue asignada | Propuso modelar las reglas de negocio sensibles como **políticas parametrizables** en vez de invariantes rígidos | Se adoptó. El ejemplo concreto: `capacidad_vendible = f(capacidad_física, política_comercial)`, para que una restricción del tipo "se permite overbooking" entre como configuración y no como rediseño. |

---

## Observaciones sobre el uso de la herramienta

*(se completa al cierre: dónde ayudó de verdad, dónde se equivocó, qué hubo que rehacer a mano)*
