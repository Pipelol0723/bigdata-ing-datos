# 5.5 Arquitectura frontend

> **Estado:** 🟡 borrador — 06/09
> **Peso en la rúbrica:** 15% (compartido con 5.4)
> **Alcance:** sólo diseño. El enunciado no pide implementar el frontend.

## Tabla de decisiones

| ID | Decisión | Alternativa descartada | Requisito que la sustenta | Justificación |
|---|---|---|---|---|
| `DEC-09` | **SPA para el embudo de reserva** (búsqueda → selección → checkout) | Renderizado del lado del servidor (SSR) | `NFR-PERF-01`, `NFR-PERF-02` | El embudo es un flujo con estado donde el usuario va y vuelve. Con SSR, cada cambio de filtro es una recarga completa: el presupuesto de latencia se gasta en re-renderizar lo que no cambió |
| `DEC-10` | **Server-Sent Events** para avisar cambios de disponibilidad del vuelo que se está mirando | *Polling* periódico · WebSocket | `NFR-CONC-01`, `NFR-ESC-01` | El tráfico es de una sola dirección (servidor → cliente). SSE reconecta solo y va sobre HTTP común; WebSocket es bidireccional y no aporta nada acá |
| `DEC-11` | **Portal separado para agencias**, sobre el mismo sistema de diseño | Un rol distinto en la misma interfaz | `FR-12`–`FR-15`, `DEC-04` | Coherente con la API B2B: el agente opera para terceros, en lote y viendo comisiones. Es otro producto, no otro permiso |
| `DEC-12` | **Montos y horarios se muestran tal como los da el backend**: nunca se convierten en el cliente | Convertir moneda y zona horaria en el navegador | `SUP-08`, `NFR-AUD-01` | Ver el análisis ⬇: convertir en el cliente introduce discrepancias de redondeo y errores de hora que en una aerolínea son graves |

---

## Preguntas guía — respondidas

### ¿SPA o renderizado del lado del servidor? → `DEC-09`

**SPA para el embudo de reserva.** El NFR que pesa es **`NFR-PERF-01`/`NFR-PERF-02`**, pero no
por el motivo que suele darse.

La reserva no es una página: es un **flujo con estado** de cuatro pasos donde el usuario
retrocede constantemente —cambia la fecha, compara escalas, vuelve al resultado anterior—. Con
SSR, cada una de esas interacciones es una recarga completa: el servidor vuelve a armar el
encabezado, el pie y el formulario que no cambiaron.

El presupuesto de `NFR-PERF-01` es **800 ms p95 para la búsqueda**. En una SPA ese
presupuesto se gasta casi entero en lo que importa: la llamada a la API y el repintado de la
lista de resultados. Con SSR hay que descontar de esos 800 ms el render del documento
completo y su descarga.

**Alternativa descartada: SSR.** Es más simple, mejor para SEO y da un primer pintado más
rápido. El primer pintado importa —pero **una sola vez**, mientras que la interacción con
resultados ocurre decenas de veces por sesión (`SUP-02`: 50 búsquedas por cada compra).

> **Matiz honesto:** en una aerolínea real convendría un híbrido — SSR para las páginas de
> destino y de ruta, que son las que traen tráfico orgánico, y SPA para el embudo. Queda fuera
> del alcance de este parcial, que cubre el sistema de reservas y no el sitio comercial.

### ¿Cómo se avisa que el asiento ya no está disponible? → `DEC-10`

Ésta es la pregunta que engancha con `NFR-CONC-01`, y **la respuesta empieza por reconocer un
límite: no se puede evitar que ocurra, sólo achicar la ventana y fallar bien.**

**Lo que de verdad protege al usuario no es la notificación: es el hold** (`DEC-02`). Apenas
el usuario confirma la selección, el inventario queda comprometido a su nombre por 30 minutos.
A partir de ahí nadie se lo puede quitar. La ventana de riesgo existe **sólo mientras mira,
antes de reservar** — y ése es el problema que resuelve `DEC-10`.

**Tres capas, de menor a mayor costo:**

| Capa | Qué hace | Cuándo actúa |
|---|---|---|
| **1. SSE** | El servidor empuja los asientos restantes del vuelo que el usuario tiene abierto. La UI actualiza el contador y, si llega a cero, deshabilita el botón | Mientras mira |
| **2. Hold** (`DEC-02`) | Al confirmar, el asiento queda comprometido con vencimiento. El usuario tiene 30 min para pagar sin competir con nadie | Al reservar |
| **3. Manejo del `409`** | Si aun así perdió la carrera, el rechazo de `DEC-03` se muestra como un mensaje específico —*"quedan 0 asientos en económica; hay 2 en business a $X"*— con alternativas cargadas | Al fallar |

La tercera capa es la que más se descuida y la que más se nota. `NFR-CONC-01` no pide sólo que
no se sobrevenda: pide que **las solicitudes perdedoras reciban un rechazo explícito**. Un
"error inesperado" genérico cumpliría la letra del requisito e incumpliría su intención.

**Por qué SSE y no las alternativas:**

| Alternativa | Por qué se descartó |
|---|---|
| ***Polling*** cada N segundos | A la escala de `SUP-02` (2.500 búsquedas/min), cada sesión abierta preguntando cada 5 s multiplica la carga de lectura — que es justamente el cuello de botella identificado en `NFR-ESC-01`. Se paga tráfico constante para un evento raro |
| **WebSocket** | Canal bidireccional persistente. Acá el cliente **no envía nada** por ese canal: sólo escucha. Es infraestructura de más para el mismo resultado |

SSE además reconecta solo cuando se corta la red, sin código adicional.

### ¿Hace falta una interfaz separada para agencias? → `DEC-11`

**Sí, un portal separado**, coherente con la API B2B de `DEC-04`.

No es una cuestión de permisos, sino de que **el trabajo es distinto**:

| | Pasajero | Agente de agencia |
|---|---|---|
| Para quién compra | Para sí mismo | **Para terceros**: carga datos de otro |
| Volumen | Una reserva | Muchas por turno; necesita operar en lote |
| Qué necesita ver | Su itinerario | **Comisión devengada** (`FR-14`), reservas retenidas por vencer |
| Retención | 30 min | Configurable, más larga (`FR-15`) |
| Aprendizaje | Cero: se usa una vez | Es su herramienta de trabajo diaria |

Meter ambos en una interfaz con roles daría un producto peor para los dos: el pasajero vería
opciones que no le sirven, y el agente pelearía con un flujo pensado para comprar un pasaje.

**Lo que sí se comparte:** el sistema de diseño y la librería de componentes. Selector de
fechas, tarjeta de vuelo, mapa de asientos son los mismos. Se comparte la implementación, no
el flujo.

### ¿Qué implica manejar múltiples monedas e idiomas? → `DEC-12`

`SUP-08` acota el alcance a una moneda (COP) y dos idiomas (es/en). Pero hay decisiones que
**cuestan poco ahora y muchísimo después**, y conviene tomarlas desde el inicio:

**Textos externalizados desde el día uno.** Sacar cadenas de la interfaz cuando ya hay 80
pantallas es un trabajo mecánico y enorme; hacerlo desde el principio no cuesta nada.

**La moneda viaja con el monto, y no se convierte en el cliente.** El backend devuelve
`{ monto: 450000, moneda: "COP" }` y el frontend **sólo formatea**. Convertir en el navegador
significaría tasas de cambio en el cliente, y dos usuarios podrían ver precios distintos para
el mismo vuelo según cuándo cargó su página. Para algo que termina en un cobro, es
inaceptable: el monto que se muestra tiene que ser exactamente el que se cobra
(`NFR-AUD-01`).

**Y el error clásico de las aerolíneas: la zona horaria.**

Un vuelo sale a las **07:30 hora de Bogotá** y llega a las **11:45 hora de Miami**. Si el
frontend renderizara esas horas en la zona del navegador, un usuario en México vería horas que
**no coinciden con su tarjeta de embarque**.

> **Regla:** las horas de vuelo se muestran siempre en la **hora local del aeropuerto
> correspondiente**, con el código IATA al lado. Nunca en la zona del navegador.

Por eso `AEROPUERTO` tiene el atributo `zona_horaria` en el modelo de 5.3: **no está de
adorno, sostiene este requisito de presentación**. La única hora que se muestra en la zona del
usuario es el **vencimiento del hold** (`expira_en`), porque ésa sí es un plazo que corre
para él, no un evento en un aeropuerto.

---

## Trazabilidad hacia atrás

| Decisión de frontend | Se apoya en |
|---|---|
| `DEC-09` (SPA) | `NFR-PERF-01`, `NFR-PERF-02`, `SUP-02` (relación 50:1) |
| `DEC-10` (SSE) | `NFR-CONC-01` (rechazo explícito), `NFR-ESC-01`, y descansa sobre `DEC-02` |
| `DEC-11` (portal separado) | `DEC-04`, `FR-12`–`FR-15` |
| `DEC-12` (no convertir en cliente) | `SUP-08`, `NFR-AUD-01`, `AEROPUERTO.zona_horaria` de 5.3 |

## Defensa: qué se rompe si esto cambia (§7)

| Si cambia… | Qué se toca | Costo | Alternativa ya considerada |
|---|---|---|---|
| **Se exige buen posicionamiento SEO** | Las páginas de destino pasan a SSR; el embudo sigue SPA. Es el híbrido ya analizado. **No toca el backend** | Medio, aislado en el frontend | Documentado como matiz en `DEC-09` |
| **Hay que operar en 3 monedas** | El frontend **no cambia**: ya recibe monto + moneda y sólo formatea (`DEC-12`). El trabajo está en el backend: tasas con vigencia temporal | **Bajo en el frontend** | Convertir en el cliente: descartado por consistencia de precio |
| **Se pide notificación instantánea de asiento tomado** | Ya está: es exactamente `DEC-10`. Si se quisiera menor latencia, se baja el intervalo de emisión del SSE | **Nulo** | Polling y WebSocket, ambos descartados con motivo |
| **Muchos usuarios simultáneos abren el mismo vuelo** | El SSE se convierte en el costo dominante. Se mitiga emitiendo por vuelo y no por sesión: una fuente, N suscriptores | Medio | *Polling*: habría escalado peor, es N peticiones independientes |
| **El agente de agencia necesita una app móvil** | El portal ya está separado (`DEC-11`) y consume la API B2B: se agrega un cliente más, sin tocar el resto | Bajo | Interfaz única con roles: habría obligado a rediseñar para dos públicos a la vez |
| **Hay que soportar idiomas de escritura derecha-izquierda** | Textos ya externalizados (`DEC-12`); falta el trabajo de estilos. Costoso, pero no estructural | Medio | Externalizar después: habría sido mucho peor |
