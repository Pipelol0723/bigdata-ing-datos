# 0. Contexto y supuestos

> **Estado:** 🟡 borrador — 06/09. Los supuestos de calibración (`SUP-01`, `SUP-06`) fijan el orden de magnitud de los NFR; conviene revisarlos antes de entregar.

## Por qué esta sección existe

El enunciado deja detalles sin especificar a propósito (cantidad de rutas, si hay programa
de viajero frecuente, si se permiten cambios de itinerario, qué pasa con el equipaje) y
advierte:

> *"un supuesto no declarado es una decisión de arquitectura escondida"*

Todo lo que no esté acá y aun así condicione el diseño, es una decisión invisible que no se
puede defender.

## Supuestos declarados

| ID | Supuesto | Por qué se asume esto | Qué secciones condiciona |
|---|---|---|---|
| `SUP-01` | **Escala:** 20 rutas, 60 vuelos diarios, 180 asientos promedio por aeronave (~10.800 asientos/día) | El enunciado dice "aerolínea regional" y no da números. Sin un orden de magnitud declarado, ningún NFR es verificable — y la rúbrica exige métricas concretas | 5.2 (todos los NFR), 5.4 (dimensionamiento), 5.7 (proyección de costos) |
| `SUP-02` | **Carga base:** 50 reservas/minuto en hora pico ordinaria; relación búsqueda:reserva de 50:1 (~2.500 búsquedas/min) | Ratio *look-to-book* habitual en venta aérea directa. Fija la carga de lectura, que domina el dimensionamiento | `NFR-PERF-01`, 5.4, 5.5 |
| `SUP-03` | **Temporada alta = ×5 la carga base** (250 reservas/min, 12.500 búsquedas/min) | Traduce a número el *"traffic spikes during peak season"* del enunciado, que no da cifras | `NFR-ESC-01`, `NFR-DISP-01`, 5.7 (escenario de crecimiento) |
| `SUP-04` | **El pago se delega íntegramente a una pasarela externa.** El sistema nunca almacena ni transporta datos de tarjeta; guarda sólo el identificador de transacción y su estado | Reduce drásticamente el alcance de cumplimiento PCI-DSS. Es la práctica estándar y es defendible como decisión, no como omisión | `NFR-SEG-01`, 5.4 (flujo de pago), 5.6 |
| `SUP-05` | **Sin programa de viajero frecuente** en el alcance de este parcial | El enunciado lo lista explícitamente como no especificado. Se excluye para acotar, no por olvido | 5.1, 5.3 |
| `SUP-06` | **Se permite cancelación. El cambio de fecha se modela como cancelación + nueva emisión**, con una penalidad parametrizable | Evita una entidad "modificación" con reglas propias sin perder el caso de uso. La penalidad como parámetro, no como constante, para que un cambio de política comercial no toque el modelo | 5.1, 5.3, 5.4 |
| `SUP-07` | **El equipaje queda fuera del alcance** | Listado como no especificado en el enunciado. No afecta al núcleo de inventario y concurrencia, que es lo que la rúbrica evalúa | 5.1, 5.3 |
| `SUP-08` | **Una sola moneda (COP) y dos idiomas (es/en)** en el alcance, pero el modelo de tarifas guarda la moneda como atributo | Multi-moneda real exigiría tasas de cambio con vigencia temporal. Guardar la moneda desde el inicio deja la puerta abierta sin pagar el costo ahora | 5.3, 5.5 |
| `SUP-09` | **La restricción específica de equipo (§3) se recibe el día de la defensa**, no por escrito antes de entregar | Confirmado con el profesor el 06/09. Se declara acá para que la ausencia de §3 en el documento sea una decisión trazable y no parezca un olvido | 5.1 (rúbrica), 7 |

## Decisiones estructurales tomadas (06/09)

Cuatro decisiones se tomaron antes de escribir los requisitos, porque condicionan todo lo demás. Se documentan en detalle en sus secciones; acá quedan enunciadas para dar contexto de lectura:

| Decisión | Qué se eligió | Dónde se justifica |
|---|---|---|
| Itinerario multi-tramo | **Itinerario como entidad propia** entre Reserva y Vuelo | 5.3 (`DEC-01`) |
| Momento del pago | **Hold temporal del asiento** con vencimiento, y confirmación al pagar | 5.1, 5.4 (`DEC-02`) |
| Control de sobreventa | **Bloqueo optimista con reintentos** sobre la instancia de vuelo | 5.4 (`DEC-03`) |
| Canal de agencias | **API B2B separada sobre el mismo backend** | 5.4 (`DEC-04`) |

## Preguntas abiertas del enunciado — resueltas acá

- [x] ¿Cuántas rutas y vuelos diarios? → `SUP-01`
- [x] ¿Programa de viajero frecuente? → `SUP-05`: fuera de alcance
- [x] ¿Cambios de itinerario o sólo cancelación? → `SUP-06`: cancelación + reemisión
- [x] ¿Gestión de equipaje? → `SUP-07`: fuera de alcance
- [x] ¿Monedas e idiomas? → `SUP-08`
- [x] ¿Qué son los "picos de temporada alta" en números? → `SUP-03`: ×5

## Defensa: qué se rompe si esto cambia (§7)

El día de la sustentación el profesor plantea un cambio, mejora o problema no cubierto en el
documento, y hay que responder **en el momento** qué parte del diseño se ve afectada. Esta
tabla es la respuesta preparada para esta sección.

| Si cambia… | Qué decisiones o entidades se tocan | Costo del cambio | Alternativa ya considerada |
|---|---|---|---|
| **Se habilita overbooking del N %** | Ninguna entidad. `capacidad_vendible = f(capacidad_física, política)` ya está parametrizado; el bloqueo optimista compara contra ese valor, no contra el físico | **Bajo** — un parámetro de política comercial | Invariante rígido `vendidos ≤ asientos`: se descartó justamente por esto |
| **Aparece programa de viajero frecuente** | Nueva entidad `Pasajero_Programa` + `Tarifa` gana una dimensión. No toca inventario ni concurrencia | Medio, aislado | Excluido en `SUP-05` para acotar |
| **Volumen ×100** | El cuello de botella es la lectura de disponibilidad, no la escritura: se resuelve con caché y réplicas de lectura. El bloqueo optimista degrada sólo si sube la *contención por vuelo*, que no escala con el volumen total | Medio | Bloqueo pesimista: se descartó por serializar el mismo vuelo |
| **Cae la pasarela de pagos** | El hold temporal (`SUP-04` + `DEC-02`) ya desacopla reserva de pago: la reserva sobrevive retenida y vence sola. Sin hold, la caída de la pasarela tiraría la reserva completa | **Bajo** — es un beneficio ya comprado con `DEC-02` | Pago atómico: más simple, pero acopla disponibilidad del sistema a la del proveedor |
| **Derecho al olvido sobre un pasajero** | `SUP-04` ya evita el problema más grave (no hay datos de tarjeta). Queda anonimizar datos personales conservando los hechos analíticos, que es justamente lo que permite la separación OLTP/OLAP de la 5.7 | Medio | Borrado físico en cascada: rompería la trazabilidad contable |
| **Codeshare con otra aerolínea** | El `Itinerario` como entidad propia (`DEC-01`) ya admite tramos operados por distinto transportista: se agrega el atributo, no se rehace el modelo | **Bajo** — es la ventaja que se compró con `DEC-01` | Reserva → muchos vuelos: no tendría dónde alojar el operador por tramo |
