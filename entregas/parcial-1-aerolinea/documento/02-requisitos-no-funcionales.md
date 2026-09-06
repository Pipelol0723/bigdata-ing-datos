# 5.2 Requisitos no funcionales (NFR)

> **Estado:** 🟡 borrador — 06/09
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
| `RSK-01` | **Sobreventa por concurrencia:** dos compras simultáneas del último asiento se confirman ambas | Reacomodación o compensación al pasajero, costo directo por evento y daño reputacional. Es el riesgo que el enunciado nombra explícitamente |
| `RSK-02` | **Abandono por lentitud en la búsqueda:** el usuario se va antes de ver resultados | Pérdida de venta directa. En venta aérea la búsqueda es el embudo: se buscan ~50 veces por cada compra (`SUP-02`) |
| `RSK-03` | **Caída en temporada alta:** el sistema no responde en el pico de demanda | Es cuando se concentra el ingreso. Una hora caída en pico cuesta lo que varias en temporada baja |
| `RSK-04` | **Fuga de datos personales o de pago** | Sanción regulatoria (Ley 1581 de 2012, habeas data) y pérdida de la licencia para operar con tarjetas |
| `RSK-05` | **Inventario retenido y nunca liberado:** holds que no vencen bloquean asientos vendibles | Se deja de vender inventario que estaba disponible. Es el costo oculto de haber elegido `DEC-02` |
| `RSK-06` | **Disputa sobre una reserva sin historial reconstruible** | Sin trazabilidad no se puede resolver un reclamo ni auditar una liquidación de comisión a una agencia (`FR-14`) |
| `RSK-07` | **Crecimiento que degrada la búsqueda:** sumar rutas multiplica las combinaciones con escala | La búsqueda de itinerarios crece más rápido que el número de rutas, no proporcionalmente |

## Tabla de requisitos no funcionales

| ID | Categoría | Requisito (con métrica) | Cómo se verifica | Riesgo que mitiga |
|---|---|---|---|---|
| `NFR-PERF-01` | Performance | Búsqueda de **vuelo directo**: p95 ≤ **800 ms**, p99 ≤ 1,5 s, con la carga de `SUP-02` (2.500 búsquedas/min) | Prueba de carga con k6/Locust sobre `FR-01`, midiendo percentiles no promedios | `RSK-02` |
| `NFR-PERF-02` | Performance | Búsqueda **con escalas**: p95 ≤ **2 s**. Se admite el triple porque exige combinar tramos y validar tiempos mínimos de conexión | Misma prueba sobre `FR-02`, con pares origen-destino sin vuelo directo | `RSK-02` |
| `NFR-CONC-01` | **Concurrencia** | **Cero sobreventas.** Con N solicitudes simultáneas sobre los últimos M asientos (N > M), se confirman **exactamente M** y las N−M restantes reciben un rechazo explícito. Nunca M+1 | **Prueba obligatoria de 5.6**: script con 50 solicitudes concurrentes sobre 1 asiento; se corre **sin** el mecanismo y **con** él, y se comparan. Evidencia en `evidencia/concurrencia/` | `RSK-01` |
| `NFR-CONC-02` | Concurrencia | Toda retención vence y **libera inventario** a más tardar **60 s** después de su plazo (30 min pasajero / 24 h agencia) | Crear un hold, esperar el vencimiento, verificar que el asiento vuelve a estar disponible | `RSK-05` |
| `NFR-DISP-01` | Disponibilidad | **99,9 %** mensual (≈ 43 min de caída al mes) en el flujo de búsqueda y reserva. **No** 99,99 % | Monitoreo de disponibilidad del endpoint. Ver justificación ⬇ | `RSK-03` |
| `NFR-SEG-01` | Seguridad | **Cero datos de tarjeta** en la base y en los logs. Sólo se persiste el identificador de transacción de la pasarela y su estado | Revisión de esquema + inspección de logs buscando patrones de PAN | `RSK-04` |
| `NFR-SEG-02` | Seguridad | Datos personales cifrados **en reposo** (KMS) y **en tránsito** (TLS 1.2+). Credenciales de agencia separadas de las de pasajero, con rotación | Verificar cifrado en RDS y política de TLS. Revisar el modelo de autenticación de `FR-12` | `RSK-04` |
| `NFR-ESC-01` | Escalabilidad | Absorber el **×5 de temporada alta** (`SUP-03`) sin degradar `NFR-PERF-01`, escalando sólo la capa de lectura | Prueba de carga a 12.500 búsquedas/min con réplicas de lectura activas | `RSK-03`, `RSK-07` |
| `NFR-ESC-02` | Escalabilidad | Pasar de 20 a 40 rutas **sin cambios de esquema**, sólo con datos nuevos | Cargar el doble de rutas y repetir la prueba de `NFR-PERF-02` | `RSK-07` |
| `NFR-AUD-01` | Auditabilidad | Historial **completo e inmutable** de cambios de estado de una reserva: qué cambió, cuándo, qué actor. Retención **5 años** | Consultar el historial de una reserva con cancelación y reemisión, y reconstruir la secuencia entera | `RSK-06` |

## Preguntas guía — respondidas

### Performance — ¿cambia con escalas?

**Sí, y el requisito lo refleja explícitamente.** Un vuelo directo es una consulta filtrada;
un itinerario con escalas exige combinar tramos y validar tiempos mínimos de conexión, y el
espacio de combinaciones crece más que linealmente con las rutas (`RSK-07`).

Escribir un solo número para ambos casos sería o inalcanzable para uno o irrelevante para el
otro. Por eso son dos: `NFR-PERF-01` y `NFR-PERF-02`.

### Concurrencia — ¿qué debe garantizar el sistema?

El requisito bisagra de todo el trabajo. La garantía es **exactitud, no orden**: no importa
cuál de los dos pasajeros gane, importa que gane **exactamente uno** y que el otro reciba un
rechazo claro y no un error genérico.

Esa formulación es deliberada: define el resultado observable en vez del mecanismo, así
`NFR-CONC-01` sigue siendo válido aunque en 5.4 se cambie de bloqueo optimista a otra cosa.
El requisito no debe encadenar la implementación.

### Disponibilidad — ¿99,9 % o 99,99 %?

**99,9 %, y la diferencia se justifica en costo:**

| Nivel | Caída mensual | Qué exige |
|---|---|---|
| 99 % | ~7 h | Instancia única |
| **99,9 %** ✅ | **~43 min** | Multi-AZ con failover automático |
| 99,99 % | ~4 min | Multi-región activo-activo, replicación entre regiones, equipo de guardia |

Saltar de 99,9 a 99,99 % multiplica el costo de infraestructura y agrega una clase entera de
problemas (consistencia entre regiones) para ahorrar unos 39 minutos al mes. Para una
aerolínea **regional** con la escala de `SUP-01`, no se paga solo.

⚠️ **Y hay un límite honesto que conviene declarar**: el Learner Lab tiene 50 USD de
presupuesto, así que **Multi-AZ no se implementa en el entregable**. `NFR-DISP-01` es el
requisito de diseño para producción; la implementación de 5.6/5.7 corre en Single-AZ, y esa
desviación se declara en 5.7 en vez de disimularse.

### Seguridad — ¿qué normativa aplica?

**Ley 1581 de 2012** (protección de datos personales, Colombia) por los datos de pasajeros, y
**PCI-DSS** por los de pago.

La decisión de `SUP-04` —delegar el cobro íntegramente a una pasarela— es lo que mantiene el
alcance PCI en el nivel más bajo posible: si los datos de tarjeta nunca tocan el sistema, la
mayor parte de los controles no aplican. **Es una decisión de arquitectura tomada por un
motivo regulatorio**, no una simplificación.

### Escalabilidad — ¿cuál es el primer cuello de botella?

**La lectura de disponibilidad, no la escritura.** Con la relación 50:1 de `SUP-02`, por cada
reserva hay cincuenta búsquedas.

Eso tiene una consecuencia de diseño concreta: el crecimiento se absorbe con **caché y
réplicas de lectura**, no escalando la base transaccional. Y explica por qué `DEC-03`
(bloqueo optimista) no se vuelve el problema al crecer — la contención depende de cuántos
compiten *por el mismo vuelo*, no del volumen total del sistema.

El segundo cuello, más lejano, es la búsqueda con escalas (`RSK-07`, `NFR-ESC-02`).

### Auditabilidad — ¿qué tan importante es el historial?

Alta, por dos motivos distintos: **reclamos de pasajeros** y **liquidación de comisiones a
agencias** (`FR-14`), que es dinero entre dos empresas.

Se resuelve con historial de estados **append-only**: no se actualiza el estado de una
reserva, se agrega un registro nuevo. Costo bajo, y encaja con la separación OLTP/OLAP de
5.7 — ese historial es la fuente natural de los *patrones de cancelación* que pide `FR-19`.

## Defensa: qué se rompe si esto cambia (§7)

| Si cambia… | Qué se toca | Costo | Alternativa ya considerada |
|---|---|---|---|
| **Ahora se exige 99,99 %** | No cambia ningún requisito funcional ni el modelo. Cambia la topología: multi-región activo-activo, y aparece consistencia entre regiones como problema nuevo | **Alto**, y es de infraestructura | Ya está la tabla de arriba con el costo de cada nivel |
| **Se permite overbooking** | `NFR-CONC-01` **no cambia**: dice "no más que la capacidad vendible", no "que la física". Es exactamente para esto que se formuló así (`FR-17`) | **Nulo** | Formular el NFR contra capacidad física: descartado |
| **El p95 de búsqueda baja a 300 ms** | No toca el modelo. Obliga a caché de disponibilidad, y ahí aparece el trade-off frescura vs latencia — que colisiona con `NFR-CONC-02` | Medio | Ver el análisis de cuello de botella de arriba |
| **La retención pasa de 30 min a 2 h** | Sólo el parámetro de `NFR-CONC-02`. Pero sube `RSK-05`: más inventario retenido sin vender | Bajo técnicamente, **decisión comercial** | El hold diferenciado por canal (`FR-15`) ya reconoce que el plazo es política, no constante |
| **Aparece una normativa de retención de datos más corta** | Choca de frente `NFR-AUD-01` (5 años) con el derecho al olvido. Se resuelve anonimizando en OLTP y conservando los hechos agregados en OLAP | Medio | La separación OLTP/OLAP de 5.7 ya deja el camino abierto |
| **Dos pasajeros compiten pero desde canales distintos** (web y agencia) | Nada. `NFR-CONC-01` está definido sobre el inventario, no sobre el canal. La API B2B (`DEC-04`) comparte el mismo núcleo | **Nulo** | Inventario por canal: se descartó, fragmenta la disponibilidad |
