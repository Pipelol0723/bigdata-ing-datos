# 5.1 Requisitos funcionales (FR)

> **Estado:** ⬜ pendiente — planificado para el miércoles 2/09
> **Peso en la rúbrica:** 10%

## Qué exige la rúbrica para "Sobresaliente"

> *"Resuelven explícitamente las preguntas guía, declaran los supuestos e integran la
> restricción específica del equipo."*

O sea: no alcanza con cubrir el escenario. Cada pregunta guía necesita respuesta explícita
y localizable.

## Preguntas guía a resolver (checklist de la rúbrica)

- [ ] ¿Quiénes son los actores? (pasajero, agente de agencia asociada, personal de
      aeropuerto, administrador) ¿Interactúan todos con el mismo sistema, o con
      interfaces distintas sobre el mismo backend?
- [ ] ¿Cómo se maneja una reserva con múltiples tramos o conexiones? ¿Una sola reserva con
      varios vuelos asociados, o varias reservas encadenadas?
- [ ] ¿Se permite reservar sin pagar de inmediato (bloqueo temporal del asiento), o el pago
      es parte atómica de la reserva?
- [ ] ¿Qué pasa si el pasajero quiere cancelar o cambiar la fecha?
- [ ] ¿Las agencias asociadas tienen un flujo distinto (descuento, comisión), o usan el
      mismo proceso que un pasajero final?

## Actores del sistema

| Actor | Descripción | Interfaz que usa |
|---|---|---|

## Tabla de requisitos funcionales

| ID | Descripción | Actor | Prioridad | Supuestos que lo sostienen |
|---|---|---|---|---|
| `FR-01` | | | | |

Prioridad: `Alta` (sin esto el sistema no vende pasajes) / `Media` / `Baja`.

## Defensa: qué se rompe si esto cambia (§7)

El día de la sustentación el profesor plantea un cambio, mejora o problema no cubierto en el
documento, y hay que responder **en el momento** qué parte del diseño se ve afectada. Esta
tabla es la respuesta preparada para esta sección.

| Si cambia… | Qué decisiones o entidades se tocan | Costo del cambio | Alternativa ya considerada |
|---|---|---|---|

> Sobre la restricción específica de equipo (§3), pendiente de confirmar: ver el README.
