# Plan de solución — actividades pendientes de Moodle

> **Fecha del plan:** 2026-09-07
> **Base:** el relevamiento del campus del 06/09 (`plan-del-curso.md`).
> ⚠️ **No pude re-verificar el campus hoy** — la extensión de Claude en Chrome no está
> instalada en el perfil actual y el campus necesita sesión iniciada. La semana 6 arrancó
> hoy: puede haber actividades nuevas que este plan no contempla. **Verificar antes de ejecutar.**

---

## 1. Lo primero no es trabajo: es una pregunta

Hay **tres preguntas al profesor** que hay que hacer antes de escribir una sola línea. No es
burocracia: la respuesta a la segunda decide si ~8 horas de trabajo valen algo o no valen nada.

| # | Pregunta | Qué cambia según la respuesta |
|---|---|---|
| 1 | En Moodle las tareas **no muestran botón de envío**, sólo "marcar como completado". ¿Cómo se entregan? | Define el **formato**: archivo por tarea, repositorio, correo, o presentación en clase. Escribir sin saberlo es apostar. |
| 2 | ¿**Se siguen recibiendo** las entregas de las semanas 1 a 4? ¿Con penalización? | **La pregunta cara.** Si la respuesta es no, los 7 assignments de sesión valen cero y no hay que escribirlos: quedan sólo el Checkpoint 1 y los módulos. Ahorra ~8 h. |
| 3 | Los módulos de AWS Academy (M1–M4), ¿se validan solos al completarlos allá o hay que reportarlos en Moodle? | Define si hay un paso extra de entrega o alcanza con hacerlos. |

**Opcional, pero útil:** cómo pesan el Parcial 1 y el Checkpoint 1 dentro del 15 % de
assignments y el 15 % de proyecto del período 1. Sirve para priorizar el resto del semestre.

### Borrador del mensaje

> Buenas, profesor. Estoy poniéndome al día con las actividades de las semanas 1 a 4 y quería
> confirmar tres cosas antes de ponerme a trabajar:
>
> 1. En Moodle las tareas no me muestran botón de envío, sólo la casilla de "marcar como
>    completado". ¿Cómo se entregan? ¿En clase, por Teams, por correo, o con un repositorio?
> 2. ¿Se siguen recibiendo las entregas atrasadas de esas semanas? ¿Hay alguna penalización?
> 3. Los módulos de AWS Academy (Module 1 a 4), ¿quedan validados al completarlos en esa
>    plataforma o hay que reportarlos también en Moodle?
>
> Gracias.

⏱️ **Cuesta 5 minutos y puede borrar una semana de trabajo innecesario.** Es lo único del
backlog que conviene hacer antes del jueves.

---

## 2. El inventario: 11 pendientes, 3 familias

| Familia | Cuántas | Cuáles | Dónde vive |
|---|---|---|---|
| Assignments de sesión | **7** | S1, S3, S4, S5, S6, S7, S8 | Moodle |
| Módulos AWS Academy | **4** | M1, M2, M3, M4 | Plataforma de AWS Academy |
| Checkpoint 1 | (es S8) | nota de **proyecto**, no de assignment | Moodle + defensa oral |

*(S2 ya está enviada. El Parcial 1 va aparte: vence el 10/09 y tiene prioridad absoluta.)*

💰 **Todo el backlog cuesta ~$0 de AWS.** La única pieza que toca la nube es un bucket S3, que
son centavos. Lo caro acá es el tiempo, no el presupuesto — que es una buena noticia, porque
del presupuesto quedan ~$45 y hay que estirarlos hasta noviembre.

---

## 3. La idea central: no son 11 trabajos, son 5 artefactos

Ésta es la parte que cambia el tamaño del problema. Los 7 assignments de sesión no son siete
trabajos independientes: son **cinco artefactos** que se escriben una vez y se citan varias.
Y cuatro de los cinco ya están hechos o casi.

| Artefacto | Qué es | Cubre | Insumo que ya existe |
|---|---|---|---|
| **A1 · Diagrama de arquitectura** | El pipeline propio con **iconos oficiales de AWS** (draw.io o la librería `diagrams` de Python — Graphviz ya está instalado) | S3 · S4 · **Checkpoint 1** | `parcial-1-aerolinea/diagramas/arquitectura.md` (Mermaid) — hay que reexpresarlo con iconografía oficial |
| **A2 · ADR #1 — data lake** | Contexto / decisión / alternativas / consecuencias sobre zonas, formatos y particionado | S5 · **Checkpoint 1** | Las decisiones **ya están tomadas y razonadas** en `CLAUDE.md`: por qué RDS y no MySQL en EC2, por qué Glue y no scripts, por qué Parquet, por qué SG grupo-a-grupo |
| **A3 · Bucket S3 del data lake** | `raw/` `processed/` `curated/` + versionado + una regla de lifecycle | S5 · S6 · **Checkpoint 1** | ❌ **Nunca se creó un bucket.** Es la única pieza de infraestructura que falta en todo el curso |
| **A4 · Evidencia de Glue** | Catálogo + crawler + conexión JDBC funcionando | S7 · **Checkpoint 1** | ✅ Hecho en clase, pero **la evidencia apunta a una RDS borrada** — hay que recapturarla |
| **A5 · Ensayo conceptual** | Las 5 V, roles (ingeniero / científico / arquitecto), DW vs data lake, batch vs streaming | S1 | Nada. **Es el único trabajo genuinamente nuevo del backlog** |

Los **módulos M1–M4** no se derivan de nada de esto: son lectura + quiz en otra plataforma.

> 💡 **A3 y A4 se resuelven solos si se aprovecha la sesión de AWS del parcial.** Ya se va a
> abrir el lab el martes para el 5.7, ya se van a crear crawlers y conexiones JDBC nuevas.
> Crear el bucket con sus zonas son 10 minutos más y unos centavos. Capturar las pantallas de
> Glue mientras ya están abiertas, cero. **Hacerlo en una sesión aparte después del 10/09
> significa abrir el lab una vez más para nada.**

---

## 4. Calendario propuesto

| Día | Qué | Por qué ahí |
|---|---|---|
| **07/09 (hoy)** | Mandar las 3 preguntas al profesor. **Nada más de Moodle.** | La respuesta tarda; que llegue mientras trabajás en el parcial |
| **08/09** | Sesión de AWS del parcial (~4 h de lab). **Al final, con el parcial ya capturado:** crear el bucket (**A3**) y capturar la evidencia de Glue (**A4**) | Aprovecha una sesión de lab que igual hay que abrir. Costo marginal: centavos |
| **09/09** | Ensayo de la defensa · revisión de trazabilidad. **Cero Moodle** | Día de margen. La defensa es eliminatoria por sección |
| **10/09** | 🎓 **Entrega y defensa del Parcial 1** | Fecha inamovible |
| **11–13/09** | **Módulos M1 a M4** de AWS Academy | Son puntos deterministas, no dependen de la respuesta del profesor y no consumen presupuesto. Empezar por M1 para medir cuánto lleva uno de verdad y recalibrar |
| **14–19/09** | 🎯 **Semana buffer, sin clase.** A1, A2, A5 + redacción de los 7 documentos + cierre del **Checkpoint 1** | Es **la única ventana grande del semestre** antes del Checkpoint 2 (semana 11). Si el backlog no se cierra acá, no se cierra |

**Después del 19/09 la agenda se pone dura:** semana 7 arranca Spark, semana 8 Glue ETL y EMR,
semana 10 el ADR #2, semana 11 el Checkpoint 2. El backlog no tiene otro hueco.

---

## 5. Los bloques, en detalle

### Bloque 0 — La pregunta (07/09, 5 min)
Ver §1. Bloquea todo lo demás, así que va primero aunque no produzca nada.

### Bloque 1 — Piggyback en la sesión de AWS del parcial (08/09, +25 min)

⚠️ **Regla: esto va AL FINAL, con la evidencia del parcial ya guardada.** El parcial vale más
que el backlog; si algo sale mal, sale mal en el pedazo barato.

1. Crear el bucket con las tres zonas del data lake (`raw/`, `processed/`, `curated/`).
2. Activar **versionado** y una regla de **lifecycle** (ej. a Glacier a los 90 días). Son
   exactamente los dos temas de la sesión 6 — se documentan con la captura de la consola.
3. Capturar el catálogo, el crawler y la conexión JDBC del parcial → **A4**, que de paso
   reemplaza la evidencia muerta que apunta a la RDS borrada.
4. Borrar los objetos de Glue huérfanos de Sakila (`crawler-sakila-rds`, `sakila_catalog`,
   la conexión JDBC vieja) — pendiente ya anotado en `CLAUDE.md`.

💰 El bucket queda: son centavos al mes y hace falta para el Checkpoint 1 y para casi todo lo
que viene (Athena, Glue ETL, Redshift COPY). **No borrarlo al cerrar la sesión.**

### Bloque 2 — Módulos AWS Academy (11–13/09)
M1 Welcome · M2 Data-Driven Organizations · M3 The Elements of Data · M4 Design Principles.
Lectura + quiz autoevaluado. Verificar primero si la plataforma todavía los acepta.

### Bloque 3 — Los artefactos (14–17/09)
En este orden, porque cada uno alimenta al siguiente:

1. **A3 documentado** (el bucket ya existe desde el 08/09) → redacción de S6.
2. **A2 · ADR #1** — casi se escribe solo: las decisiones ya están razonadas en `CLAUDE.md`,
   falta pasarlas al formato ADR.
3. **A1 · Diagrama** con iconos oficiales → S3, S4 y Checkpoint 1.
4. **A5 · Ensayo conceptual** → S1.

### Bloque 4 — Redacción y cierre (18–19/09)
Los 7 documentos de sesión, cada uno de 1–2 páginas citando los artefactos, más el
**Checkpoint 1** completo (diagrama + ADR + bucket/crawler + defensa oral preparada).

---

## 6. Estimación de esfuerzo

> Estimaciones, no promesas. La incógnita grande son los módulos.

| Bloque | Horas |
|---|---|
| Preguntas al profesor | 0,1 |
| Piggyback en AWS (08/09) | 0,5 |
| Módulos M1–M4 | **4–12** ← la gran incógnita, medir con M1 |
| Artefactos A1, A2, A5 | ~4 |
| Redacción de 7 documentos | ~3,5 |
| Cierre del Checkpoint 1 | ~2 |
| **Total** | **~14 a 22 h** |

Entra cómodo en la semana buffer **si los módulos no se desmadran**. Por eso M1 va primero y
solo: para saber contra qué se juega antes de comprometer el resto del calendario.

---

## 7. Riesgos

| Riesgo | Señal temprana | Qué hacer |
|---|---|---|
| **El profesor no acepta atrasadas** | Respuesta a la pregunta 2 | Se cae el Bloque 4 entero. Quedan Checkpoint 1 (nota de proyecto, otra bolsa) y los módulos. **Se ahorran ~8 h** |
| **Los módulos llevan mucho más de lo estimado** | Cuánto tardó M1 | Priorizar: los módulos son puntos seguros; los assignments atrasados quizá no |
| **La semana 6 trajo actividades nuevas** | Revisar el campus | Este plan no las contempla — **verificar antes de ejecutar** |
| Meter el bucket en la sesión del parcial y romper algo | — | Por eso va **al final**, con la evidencia del parcial ya guardada |
| El Checkpoint 1 también se defiende oralmente | El enunciado dice *"defended orally"* | Preparar la defensa como la del parcial: cada decisión con su alternativa descartada |

---

## 8. Decisiones que te tocan a vos

1. **¿El bucket y la evidencia de Glue entran en la sesión del martes 8, o van en una sesión aparte después del 10?**
   *Recomiendo meterlos*, al final y con el parcial ya capturado: son 25 minutos contra abrir
   el lab otra vez. El riesgo real es de atención, no técnico.
2. **¿Mandás las preguntas hoy por escrito, o las hacés el jueves en persona?**
   *Recomiendo hoy.* Si la respuesta a la 2 es "no se reciben", te enterás antes de invertir
   la semana buffer, no después.
3. **¿Un documento por sesión, o un solo cuaderno del curso con una sección por sesión?**
   Depende de la respuesta 1 del profesor. Si queda a criterio tuyo, *recomiendo uno por
   sesión* en `entregas/semana-N/` más un índice: si Moodle pide subir archivo por tarea calza
   directo, y si es un repositorio el índice lo resuelve igual.
4. **¿Módulos antes que assignments, o al revés?**
   *Recomiendo módulos primero.* No dependen de lo que conteste el profesor, así que el tiempo
   invertido no puede perderse.
