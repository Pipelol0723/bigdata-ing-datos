# Module 2 — Data-Driven Organizations

**Actividad de Moodle:** *AWS Academy Data Engineering — Module 2: Data-Driven Organizations*
**Semana 2** · cerró el 14 de agosto de 2026
**Caso de estudio:** sistema de reservas de una aerolínea (Parcial 1)

> ⚠️ El módulo se completa en la plataforma de **AWS Academy**; el entregable formal es la
> evidencia de haberlo terminado. Este documento es la **síntesis aplicada al proyecto**.
> **Estado del módulo:** ⬜ pendiente.

---

## 1. De qué trata el módulo

Qué significa que una organización sea *data-driven*: cómo el dato pasa de subproducto operativo a
insumo de decisión, quiénes son los consumidores dentro de la empresa, y por qué la mayor parte
del valor no está en recolectar sino en **poder responder preguntas**.

## 2. La prueba de que un dato sirve: que alguien decida distinto

Lo más fácil de este tema es repetir que "los datos son el nuevo petróleo". Lo útil es preguntar,
por cada tabla: **¿qué decisión cambia si este dato dice otra cosa?** Si no hay respuesta, la tabla
es costo de almacenamiento.

En el proyecto sobreviven tres, y cada una tiene un dueño y una decisión atada:

| Vista | Quién la usa | Qué decide |
|---|---|---|
| `v_ocupacion_por_ruta` | planificación de red | qué rutas justifican más frecuencias y cuáles sobran |
| `v_ingresos_por_tarifa` | *revenue management* | si la estructura tarifaria captura la disposición a pagar |
| `v_patrones_cancelacion` | operaciones | cuánta sobreventa tolera cada ruta sin dejar pasajeros en tierra |

## 3. Un dato que cambió una lectura del negocio

De la corrida real sobre AWS:

| clase | ventana de compra | tramos | ticket promedio |
|---|---|---|---|
| económica | anticipada | 2.821 | **291.010** |
| económica | intermedia | 2.768 | 420.923 |
| económica | última hora | 2.822 | 680.231 |
| **business** | última hora | 482 | **1.433.431** |

El ticket de business a última hora es **4,9 veces** el de económica anticipada, con apenas 482
tramos. Un tablero de "ingresos totales" mostraría a económica dominando y escondería que el
margen por asiento está en el otro extremo.

**Ésa es la diferencia entre tener datos y ser data-driven:** el número existía en las dos
lecturas; sólo una permite decidir cuántos asientos de business poner en el próximo avión.

## 4. Por qué separar OLTP de OLAP es una decisión organizacional

No es sólo performance. Son dos consumidores con necesidades opuestas:

| | OLTP (`aerolinea`) | OLAP (`aerolinea_dw`) |
|---|---|---|
| Pregunta típica | *"¿queda un asiento en este vuelo?"* | *"¿cómo evolucionó la ocupación por ruta?"* |
| Quién pregunta | el sistema, miles de veces por minuto | una persona, unas veces por día |
| Costo de equivocarse | se vende dos veces el mismo asiento | un gráfico desactualizado un día |
| Modelo | 3NF, 17 tablas | estrella, 2 hechos + 6 dimensiones |

Ponerlos en la misma base significa que **un reporte pesado puede degradar la venta de pasajes**.
La separación existe para que el analista no pueda romperle el día al pasajero.

## 5. El techo de la gobernanza en este entorno

Ser data-driven exige que la gente acceda a los datos — y eso choca con quién puede ver qué. En el
catálogo del proyecto la frontera está implementada como **tres databases separadas**
(`aerolinea_raw`, `aerolinea_processed`, `aerolinea_catalog`), que es la única división de permisos
disponible sin Lake Formation.

Su límite, que conviene saber antes de que lo pregunten: **los permisos son por tabla, no por
columna.** No se puede dar acceso a los hechos ocultando el precio pagado. La salida sería
materializar una vista sin esa columna —duplicando datos— o incorporar Lake Formation.

## 6. Evidencia a adjuntar

Captura del módulo al 100 % con el resultado del quiz, como `modulo-2-evidencia.png`.

## 7. Qué generó la IA y qué corregí

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Explicar la cultura *data-driven* con las etapas de un modelo de madurez genérico | Reemplazar por el criterio *"¿qué decisión cambia si este dato dice otra cosa?"* | Un modelo de madurez no se puede aplicar a un proyecto de una persona. La pregunta sí, y descarta tablas |
| 2 | Presentar los ingresos totales por clase | Usar el **ticket promedio** | Los totales muestran a económica dominando; el promedio revela que el margen por asiento está en business. Era el ejemplo del módulo dentro de mis propios datos |
