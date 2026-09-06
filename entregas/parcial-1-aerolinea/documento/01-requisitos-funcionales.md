# 5.1 Requisitos funcionales (FR)

> **Estado:** 🟡 borrador — 06/09
> **Peso en la rúbrica:** 10%

## Qué exige la rúbrica para "Sobresaliente"

> *"Resuelven explícitamente las preguntas guía, declaran los supuestos e integran la
> restricción específica del equipo."*

O sea: no alcanza con cubrir el escenario. Cada pregunta guía necesita respuesta explícita
y localizable.

## Preguntas guía — respondidas

- [x] **¿Quiénes son los actores? ¿Mismo sistema o interfaces distintas?**
      Cuatro actores. **Un solo backend, dos APIs.** El pasajero y el personal de aeropuerto
      usan la API pública; las agencias asociadas, una **API B2B separada** (`DEC-04`). La
      lógica de negocio no se duplica: cambia el contrato, no las reglas.
- [x] **¿Cómo se maneja una reserva con múltiples tramos?**
      Una sola reserva, con el **itinerario como entidad propia** entre Reserva y Vuelo
      (`DEC-01`). Un itinerario agrupa tramos ordenados; la reserva es una sola transacción
      comercial. Ver 5.3.
- [x] **¿Se permite reservar sin pagar de inmediato?**
      Sí. La reserva nace **retenida** con vencimiento y pasa a **confirmada** al acreditarse
      el pago (`DEC-02`). Si vence sin pago, el inventario se libera solo.
- [x] **¿Qué pasa si el pasajero quiere cancelar o cambiar la fecha?**
      Cancelación directa (`FR-09`). El **cambio de fecha se modela como cancelación +
      nueva emisión** con penalidad parametrizable (`SUP-06`, `FR-10`), en vez de una
      entidad "modificación" con reglas propias.
- [x] **¿Las agencias tienen flujo distinto?**
      Sí: API propia, autenticación por credenciales de agencia, tarifa negociada y comisión
      liquidable (`FR-13`, `FR-14`). El núcleo de búsqueda e inventario es el mismo.

## Actores del sistema

| Actor | Descripción | Interfaz que usa |
|---|---|---|
| **Pasajero** | Cliente final. Busca, reserva, paga, consulta y cancela sus propias reservas | Web pública (SPA) sobre la API pública |
| **Agente de agencia asociada** | Opera en nombre de un pasajero. Tarifas negociadas y comisión. Necesita retener asientos mientras confirma con su cliente | **API B2B** + portal propio (`DEC-04`) |
| **Personal de aeropuerto** | Consulta reservas y gestiona el embarque. **No vende** | API pública, con rol y permisos propios |
| **Administrador comercial** | Define rutas, vuelos programados, tarifas y **políticas de capacidad vendible** | Backoffice sobre la API pública |

> El personal de aeropuerto no vende porque el alcance de este parcial no incluye
> mostrador de ventas. Es un supuesto de acotación, no una limitación del diseño.

## Tabla de requisitos funcionales

Prioridad: `Alta` (sin esto el sistema no vende pasajes) / `Media` / `Baja`.

### Búsqueda y disponibilidad

| ID | Descripción | Actor | Prioridad | Sustento |
|---|---|---|---|---|
| `FR-01` | Buscar vuelos disponibles por origen, destino y fecha, devolviendo tarifa y asientos disponibles | Pasajero, Agente | Alta | Escenario §2 |
| `FR-02` | Devolver itinerarios con **escalas** cuando no hay vuelo directo, respetando un tiempo mínimo de conexión configurable | Pasajero, Agente | Alta | Escenario §2, `DEC-01` |
| `FR-03` | Mostrar la tarifa aplicable según **antelación de compra y clase** (económica / business) | Pasajero, Agente | Alta | Escenario §2 |

### Reserva y pago

| ID | Descripción | Actor | Prioridad | Sustento |
|---|---|---|---|---|
| `FR-04` | Crear una reserva sobre un itinerario completo, en estado **retenida**, descontando inventario de todos sus tramos | Pasajero, Agente | Alta | `DEC-02`, `NFR-CONC-01` |
| `FR-05` | La retención **vence automáticamente** tras un plazo configurable y **devuelve el inventario** | Sistema | Alta | `DEC-02` |
| `FR-06` | Confirmar la reserva al acreditarse el pago, pasándola a estado **confirmada** | Pasajero, Agente | Alta | `DEC-02`, `SUP-04` |
| `FR-07` | **Nunca confirmar más asientos que la capacidad vendible** de una instancia de vuelo, aun con solicitudes simultáneas | Sistema | **Alta** | `NFR-CONC-01`, `DEC-03` |
| `FR-08` | Delegar el cobro a una pasarela externa y registrar únicamente identificador y estado de la transacción | Sistema | Alta | `SUP-04`, `NFR-SEG-01` |

> `FR-07` es el requisito central del trabajo: es el que la rúbrica señala en tres criterios
> distintos (NFR, modelo ER y arquitectura). Todo lo demás se puede discutir; esto no.

### Posventa

| ID | Descripción | Actor | Prioridad | Sustento |
|---|---|---|---|---|
| `FR-09` | Cancelar una reserva confirmada, liberando el inventario y disparando el reembolso según política | Pasajero, Agente | Alta | `SUP-06` |
| `FR-10` | Cambiar la fecha, implementado como cancelación + nueva emisión con **penalidad parametrizable** | Pasajero, Agente | Media | `SUP-06` |
| `FR-11` | Consultar una reserva por su código, con el detalle de todos sus tramos | Pasajero, Agente, Aeropuerto | Alta | Escenario §2 |

### Canal de agencias

| ID | Descripción | Actor | Prioridad | Sustento |
|---|---|---|---|---|
| `FR-12` | Autenticar agencias con credenciales propias, distintas de las de un pasajero | Agente | Alta | `DEC-04`, `NFR-SEG-02` |
| `FR-13` | Aplicar **tarifa negociada** por agencia sobre la tarifa pública | Agente | Media | Escenario §2, `DEC-04` |
| `FR-14` | Registrar la **comisión** devengada por cada venta de agencia, para su liquidación posterior | Sistema | Media | Escenario §2 |
| `FR-15` | Permitir a la agencia un **plazo de retención mayor** que el del pasajero final | Agente | Media | `DEC-02`, `DEC-04` |

### Administración y analítica

| ID | Descripción | Actor | Prioridad | Sustento |
|---|---|---|---|---|
| `FR-16` | Administrar rutas, vuelos programados y sus instancias por fecha | Administrador | Alta | `DEC-01`, 5.3 |
| `FR-17` | Definir la **política de capacidad vendible** por vuelo, de forma independiente de la capacidad física de la aeronave | Administrador | Alta | Ver nota ⬇ |
| `FR-18` | Registrar todo cambio de estado de una reserva con marca de tiempo y actor responsable | Sistema | Media | `NFR-AUD-01` |
| `FR-19` | Exponer los datos históricos para analizar **ocupación por ruta, ingresos por tarifa y patrones de cancelación** | Administrador | Alta | Escenario §2, 5.7 |

> **`FR-17` es la decisión más importante de esta sección, y no es obvia.**
> El enunciado dice *"el sistema no debe vender más asientos de los que tiene el avión"*.
> Modelarlo literalmente daría el invariante `vendidos ≤ asientos_físicos`. En cambio se
> modela `capacidad_vendible = f(capacidad_física, política_comercial)`, y el invariante
> pasa a ser `vendidos ≤ capacidad_vendible`.
>
> Cuesta lo mismo implementarlo, pero convierte *"ahora permitimos overbooking del 5 %"* de
> un rediseño a un cambio de configuración. Es la aplicación concreta del criterio con el
> que se evalúa la defensa oral.

## Trazabilidad hacia adelante

| Requisito | Se materializa en |
|---|---|
| `FR-02` (escalas) | `DEC-01` — Itinerario como entidad (5.3) |
| `FR-04`, `FR-05`, `FR-15` (retención) | `DEC-02` — hold temporal (5.4) |
| `FR-07` (no sobrevender) | `DEC-03` — bloqueo optimista (5.4), prueba de concurrencia (5.6) |
| `FR-12`–`FR-15` (agencias) | `DEC-04` — API B2B separada (5.4) |
| `FR-19` (analítica) | ETL a la base OLAP (5.7) |

## Sobre la restricción específica de equipo (§3)

Según `SUP-09`, confirmado con el profesor el 06/09, **la restricción de este equipo se
recibe el día de la defensa**, no por escrito antes de entregar. Por eso no aparece
integrada en esta tabla.

La preparación para absorberla está en `FR-17` (políticas parametrizables) y en la tabla de
defensa de cada sección.

## Defensa: qué se rompe si esto cambia (§7)

| Si cambia… | Qué se toca | Costo | Alternativa ya considerada |
|---|---|---|---|
| **Overbooking del N %** | Sólo el valor de la política de `FR-17`. Ningún requisito ni entidad | **Bajo** | Invariante rígido contra capacidad física: descartado por esto mismo |
| **El personal de aeropuerto debe poder vender** | Nuevo actor con permisos de escritura sobre `FR-04`/`FR-06`. No toca inventario ni concurrencia | Bajo | Ya está el modelo de roles sobre la API pública |
| **Las agencias pueden emitir sin pagar (crédito)** | `FR-06` gana una vía de confirmación por línea de crédito. `FR-14` (comisión) ya existe | Medio | El hold diferenciado de `FR-15` es el primer escalón hacia esto |
| **Se exige devolver disponibilidad en tiempo real al frontend** | Es `NFR-PERF` y 5.5, no un FR nuevo. `FR-01` ya devuelve asientos disponibles | Bajo | Ver 5.5 (notificación de asiento tomado) |
| **Aparece equipaje como producto vendible** | Nueva entidad de servicios auxiliares colgando de la reserva. `SUP-07` lo excluyó explícitamente, no por olvido | Medio, aislado | Declarado fuera de alcance en `SUP-07` |
