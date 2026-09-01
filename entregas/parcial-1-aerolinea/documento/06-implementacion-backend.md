# 5.6 Primera implementación del backend

> **Estado:** ⬜ pendiente — planificado para el sábado 5/09
> **Peso en la rúbrica:** 10%
> **Entorno de desarrollo:** PostgreSQL local en Docker · FastAPI en venv local

## Alcance mínimo exigido

- [ ] Una base de datos funcional, con el motor y el nivel de normalización definidos en 5.3
- [ ] Una API FastAPI que exponga, como mínimo:
  - [ ] Buscar vuelos disponibles
  - [ ] Crear una reserva
  - [ ] Consultar una reserva existente
- [ ] La creación de reserva debe reflejar la decisión de concurrencia de 5.4.
      **No alcanza con que la API funcione con un solo usuario a la vez.**

## Qué exige la rúbrica para "Sobresaliente"

> *"Implementación funcional, fiel al diseño (o con desviaciones justificadas), con
> evidencia concreta de la prueba de concurrencia."*

## La prueba de concurrencia

Plan: **mostrar primero el bug y después la cura.** Se corre el mismo test dos veces contra
el último asiento disponible:

| Corrida | Mecanismo | Resultado esperado | Evidencia |
|---|---|---|---|
| A | Sin control de concurrencia | Sobreventa reproducida | `evidencia/concurrencia/a-sin-lock/` |
| B | Con el mecanismo de `DEC-` | 1 sola venta, el resto rechazado | `evidencia/concurrencia/b-con-lock/` |

Reproducir la falla vale más que sólo demostrar que funciona: prueba que el mecanismo
elegido es necesario, no decorativo. Y es exactamente lo que se defiende bien oralmente.

## Preguntas guía a resolver

- [ ] ¿El código refleja exactamente lo documentado en 5.4, o aparecieron ajustes durante
      la implementación? ¿Qué los motivó y qué documento se actualiza?
- [ ] ¿Cómo se probó específicamente el escenario de `NFR-CONC-01`? ¿Qué evidencia lo
      respalda?
- [ ] ¿Qué parte del modelo de 5.3 hubo que ajustar al enfrentar la implementación real?

## Guía de ejecución

*(cómo levantar la base, correr la API y ejecutar el test — se completa al implementar)*

## Impacto de la restricción específica (§3)

⏳ Pendiente de asignación.
