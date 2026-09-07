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

### 2026-09-06 — Redacción del documento e implementación

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección / refinamiento aplicado |
|---|---|---|---|---|
| 5 | Situar el parcial en el curso | *"revisa todas las actividades del campus desde la semana 1, planea cómo hacerlas y documenta"* | Relevamiento completo del campus: 13 entregas vencidas, sólo 1 enviada | **Reordenó la prioridad.** El plan inicial trataba el parcial como una tarea más; al ver que vencía en 4 días y pesaba más que todo el backlog junto, se reescribió el plan poniéndolo como prioridad 0. |
| 6 | Evitar que la IA decida por mí | *"planea y dime cómo piensas implementar el 5.7 **antes de hacer cualquier cosa**"* | Plan por fases, 5 decisiones con alternativas y proyección de costos | **La restricción explícita fue clave otra vez.** Sin ella habría empezado a crear recursos en AWS. El plan mostró que convenía validar todo en local primero: depurar el ETL contra AWS habría costado varios dólares en instancias encendidas. |
| 7 | Decisiones estructurales del diseño | El asistente presentó 4 bifurcaciones (itinerario multi-tramo, momento del pago, control de sobreventa, canal de agencias) con trade-offs y recomendación | Cuatro pares decisión/alternativa | **Las decisiones las tomé yo, con la alternativa a la vista.** Es lo que después permite defender cada una: la columna "alternativa descartada" del documento no es decorativa, es el registro de esa elección. |
| 8 | Concurrencia — corrección de fondo | Al revisar el código de la API antes de probarlo, apareció que usaba **una sola conexión compartida** | El asistente lo detectó y lo corrigió por pool antes de ejecutar | **Es el error más peligroso del trabajo**: la prueba de concurrencia habría pasado igual, pero por el motivo equivocado — sin paralelismo real no hay carrera que ganar. Un test que pasa por la razón incorrecta es peor que uno que falla. |
| 9 | Demostrar la falla, no sólo la cura | *"que la evidencia muestre el antes y el después"* | Modo `MODO_INSEGURO` que reproduce el patrón ingenuo leer→decidir→escribir | Al ejecutarlo, **el `CHECK` de la tabla impedía ver la sobreventa**. Hubo que retirarlo temporalmente para reproducir la falla — lo que terminó demostrando algo mejor: la restricción declarativa protegía incluso con el mecanismo aplicativo roto. |
| 10 | Datos de prueba | Generador SQL de actividad transaccional | Falló dos veces | **Las dos fallas fueron informativas y quedaron documentadas:** (a) colisión de PNR por la paradoja del cumpleaños con 6 caracteres → se resolvió con reintento, que es lo que hacen los sistemas reales; (b) sobreventa en business porque el generador repartía 10 % a esa clase sin mirar que sólo hay 12 asientos. **El invariante encontró un bug en el código que lo alimentaba.** |

---

## Observaciones sobre el uso de la herramienta

### Dónde ayudó de verdad

- **Redactar con trazabilidad.** Mantener coherentes ~50 identificadores (`FR-`, `NFR-`,
  `DEC-`, `SUP-`, `RSK-`) referenciados entre siete documentos es trabajo mecánico y propenso
  al error humano. Acá la herramienta es claramente mejor que yo.
- **Verificar en vez de afirmar.** Cada afirmación técnica del documento se ejecutó antes de
  escribirla: el invariante se probó con SQL, la concurrencia con 30 peticiones simultáneas,
  el ETL con 8.794 filas reales. Ninguna cifra del documento es una estimación.
- **Anticipar el costo antes de gastarlo.** El plan de trabajar en local y subir a AWS una
  sola vez salió de pedir el plan antes de la ejecución.

### Dónde se equivocó

- **La conexión única** (entrada 8). Habría invalidado la prueba más importante del trabajo.
- **Tiende a producir antes de entender.** Las dos veces que el resultado fue mejor, fue
  porque el prompt incluía una prohibición explícita: *"sin hacer nada"*, *"antes de hacer
  cualquier cosa"*. Sin esa restricción arranca a escribir código o crear recursos.
- **Recomendó reutilizar infraestructura** de prácticas anteriores para ahorrar presupuesto,
  sin considerar el costo de tener que explicarlo en la defensa (entrada 3).

### Qué mantuve bajo control propio

Las **decisiones de diseño**, sin excepción. La herramienta presentó alternativas con sus
trade-offs; la elección fue mía en los cuatro casos estructurales, y en uno fue **en contra**
de su recomendación.

Es una distinción que importa por cómo se evalúa este trabajo: la defensa oral es
eliminatoria por sección. Una decisión que no tomé yo es una sección que no puedo sostener.
