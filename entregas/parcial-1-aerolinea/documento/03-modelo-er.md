# 5.3 Modelo entidad-relación

> **Estado:** ⬜ pendiente — planificado para el viernes 4/09
> **Peso en la rúbrica:** 15%
> **Notación:** Crow's Foot (consistente en todo el diagrama)

## Qué exige la rúbrica

| Nivel | Criterio |
|---|---|
| Insuficiente | No resuelve escalas ni control de sobreventa |
| Aceptable | Modelo funcional pero con decisiones injustificadas |
| **Sobresaliente** | **Modelo coherente que resuelve explícitamente escalas, vuelos recurrentes e inventario de asientos, con justificación** |

Los tres nudos del nivel Sobresaliente son innegociables.

## Los tres nudos a desatar

- [ ] **Multi-tramo / escalas** — ¿La reserva tiene N vuelos asociados, o existe una
      entidad Itinerario entre Reserva y Vuelo? *(La industria real usa PNR → Ticket →
      Cupón, uno por tramo.)*
- [ ] **Vuelos recurrentes** — ¿Hay una entidad "vuelo programado" distinta de "instancia
      de vuelo en una fecha concreta"?
- [ ] **Inventario de asientos** — ¿Dónde vive el control para evitar sobreventa? Este es
      el punto donde se pone el lock, y tiene que coincidir con `DEC-` de la sección 5.4.

## Otras decisiones a justificar

- [ ] ¿La asignación de asiento es parte de la reserva desde la compra, o es un proceso
      separado (check-in) que ocurre después?
- [ ] ¿Qué nivel de normalización se justifica, dado que este modelo alimenta tanto el
      sistema transaccional como el pipeline de Big Data? *(engancha directo con 5.7)*

## Entidades

Punto de partida del enunciado, sin asumir que la lista esté completa ni que sean las
correctas: Vuelo, Avión, Ruta, Aeropuerto, Pasajero, Reserva, Tarifa, Asiento, Pago.

## Diccionario de datos

*(una tabla por entidad: atributo, tipo, nulabilidad, descripción, restricciones)*

## Diagrama

Archivo: `../diagramas/modelo-er.*`

## Impacto de la restricción específica (§3)

⏳ Pendiente de asignación.
