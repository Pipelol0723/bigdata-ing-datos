# Plan de solución — todas las actividades pendientes de Moodle

> **Verificado en el campus el 2026-09-07** (no es un plan sobre recuerdos: entré a cada tarea).
> Curso `CC-IA-02` · [campus](https://campusvirtual.usergioarboleda.edu.co/course/view.php?id=3167)

---

## 1. ⛔ El hallazgo que cambia todo: Moodle no te deja entregar

Abrí las tareas vencidas una por una. **Ninguna tiene el botón "Agregar entrega".** Sólo
muestran el estado y un contador de atraso:

> *Estado de la entrega: Todavía no se han realizado envíos*
> *Tiempo restante: La Tarea está retrasada por: 34 días 15 horas*

Y la prueba de que no es un problema de permisos generales: **el Parcial 1 sí tiene el botón**.
Lo verifiqué. La diferencia está en las fechas:

| Tarea | Apertura | Cierre | ¿Se puede entregar? |
|---|---|---|---|
| Session 1 — Assignment | lun 3 ago 00:00 | **lun 3 ago 23:59** | ❌ no |
| Module 1 | lun 3 ago 00:00 | **vie 7 ago 23:59** | ❌ no |
| Session 8 — Checkpoint | jue 27 ago 00:00 | **jue 27 ago 23:59** | ❌ no |
| **Parcial 1** | *(sin fecha)* | *(sin fecha)* | ✅ **sí** |

En Moodle, la fecha de **Cierre** es un portón, no una advertencia: pasada esa hora el módulo
deja de aceptar archivos, y ni el atraso ni la buena voluntad del profesor lo abren solo.

⚠️ **Ojo con el detalle:** las tareas de sesión abren y cierran **el mismo día** (00:00 a 23:59).
No eran trabajos para hacer en casa durante la semana: eran evidencia del ejercicio de esa
clase, entregada ese día. Eso importa para calibrar qué tan grande tiene que ser cada entrega
(ver §3).

### ✅ Resuelto: se entregan por correo y en clase

**Decisión del 07/09:** el canal es **correo al profesor + presentación en clase**. No hace falta
que reabra Moodle. El hallazgo sigue siendo relevante por dos motivos:

- Explica **por qué** no aparecía el botón, en vez de dejarlo como un misterio.
- Conviene **pedir acuse de recibo** del correo: si la entrega no consta en Moodle, el único
  registro de que existió es ese mensaje.

### Borrador del mensaje

> Buenas, profesor. Estoy poniéndome al día con las actividades de las semanas 1 a 4 y quería
> avisarle de un detalle técnico: en Moodle esas tareas ya no muestran el botón de "Agregar
> entrega", porque la fecha de cierre era el mismo día de la sesión. El Parcial 1 sí me deja
> subir, así que no es un problema de mi usuario.
>
> ¿Podría reabrirlas o darme una prórroga individual para poder subir el trabajo? Si le resulta
> más cómodo se las hago llegar por Teams o por correo, como prefiera.
>
> Le confirmo que el Parcial 1 lo entrego el jueves como está previsto.

⏱️ **Cinco minutos, hoy.** Todo el resto del plan depende de que esto se destrabe, y él necesita
tiempo para hacerlo. **Reforzalo en persona el jueves**, cuando lo veas para la defensa del
parcial: por escrito queda constancia, en persona se resuelve.

---

## 2. El inventario verificado

**11 pendientes.** Ni una más: la semana 5 no tiene tareas de sesión (sólo el Parcial 1) y la
**semana 6 —la actual— tampoco tiene ninguna cargada**. No se está acumulando deuda nueva
mientras trabajás en el parcial.

| # | Tarea | Venció | Tema de la sesión |
|---|---|---|---|
| 1 | Session 1 — Assignment | 3 ago | Intro a Big Data: las 5 V, casos de uso, ingeniero vs científico vs arquitecto |
| 2 | Module 1 | 7 ago | Welcome to AWS Academy DE |
| 3 | Session 3 — Assignment | 10 ago | Diagramar arquitecturas AWS: iconos oficiales, **niveles de abstracción**, anatomía de un ADR |
| 4 | Session 4 — Assignment | 13 ago | Taller: setup (CLI, LabRole) + **bosquejar 2 arquitecturas alternativas** para un caso simple |
| 5 | Module 2 | 14 ago | Data-Driven Organizations |
| 6 | Session 5 — Assignment | 17 ago | Data lake: zonas, particionado, formatos. **ADR #1** |
| 7 | Session 6 — Assignment | 20 ago | S3 a fondo: clases, versionado, lifecycle. **Política de lifecycle asistida por IA, revisada línea por línea** |
| 8 | Module 3 | 21 ago | The Elements of Data |
| 9 | Session 7 — Assignment | 24 ago | Glue Catalog y Crawlers: desacoplar cómputo de metadatos; **gobernanza sin Lake Formation** |
| 10 | **Session 8 — Checkpoint 1** | 27 ago | Diagrama + ADR + bucket/crawler implementados, **defendido oralmente** |
| 11 | Module 4 | 28 ago | Design Principles and Patterns for Data Pipelines |

*(Session 2 ya está entregada y marcada como hecha.)*

💰 **Todo el backlog cuesta ~$0 de AWS.** Lo único que toca la nube es un bucket S3: centavos.

---

## 3. Cuánto hay que escribir — resuelto por el Syllabus

La entrega de la Session 2 —la única hecha— fue **un solo archivo PNG**, lo que sugería que
alcanzaba con una captura. **El Syllabus dice otra cosa**, y manda.

El sistema de evaluación reparte cada corte entre **tres unidades de competencia**, y una de las
tres es:

> **UC 3.1 — Comunicación Técnica Escrita para Audiencias Especializadas**

En el corte 1 los talleres valen 3 % + 6 % + 6 % (15 % del total), y la porción más grande está en
las UC 2.2 y **3.1**. O sea: **la escritura técnica se califica explícitamente.** Una captura sin
documento deja sin evidencia la unidad de competencia mejor ponderada.

**Conclusión: documentos reales, con las capturas adentro como evidencia.** No al revés.

### Lo otro que aporta el Syllabus

| Hallazgo | Consecuencia |
|---|---|
| **ADR #1 es "de esquema de particionado"** | Moodle decía sólo "ADR #1". El tema es específico: particionado, no diseño general del data lake |
| *"el cuello de botella ya no es escribir el ETL sino decidir qué arquitectura construir, justificarla y validar que el código generado la implemente correctamente"* | Es la tesis del curso. Cada entregable debe mostrar la **decisión**, no sólo el resultado |
| *"con la condición no negociable de que el estudiante pueda explicar, depurar y modificar manualmente cualquier línea de código generado"* | El bloque *"qué generó la IA y qué corregí"* pasa de buena idea a **requisito** |
| Resultados de aprendizaje declarados | Cada documento puede citar cuál cubre — trazabilidad barata |

---

## 4. El hilo conductor del curso: IA con revisión humana

Mirando el calendario completo aparece un patrón que no es casual:

| Sesión | Consigna |
|---|---|
| **S6** (pendiente) | *"AI-assisted lifecycle policy, **reviewed line by line**"* |
| S12 (10 sep) | *"**find-the-AI-bug** exercise"* |
| S14 (24 sep) | *"**hand-written vs. AI-generated** comparison"* |
| S17 (13 oct) | *"AI-assisted code **+ review**"* |
| Parcial 1 | anexo obligatorio de **prompt log** |

**Este profesor no evalúa si usaste IA: evalúa si la revisaste.** Así que cada entregable del
backlog debería cerrar con un bloque corto de *"qué generó la IA / qué corregí y por qué"* —
igual que el anexo del parcial. En la S6 eso no es un extra: **es literalmente la consigna**.

Ventaja tuya: el `99-prompt-log.md` del parcial ya tiene diez entradas de ese tipo, incluidas
dos correcciones de fondo (la conexión única, la sobreventa en business). Es material real.

---

## 5. Qué producir, tarea por tarea

Formato de cada carpeta: `entregas/semana-N/sesionM-<tema>/` con el PDF, las capturas y un
`README.md`. Estructura interna de cada documento:

> **Qué pedía la sesión** · **Caso** · **Desarrollo** · **Evidencia** · **Decisiones y
> alternativa descartada** · **Qué generó la IA y qué corregí**

### 1 · Session 1 — Las 5 V y los roles · ~45 min
El único entregable **sin insumo previo**. La jugada: en vez de un ensayo genérico, aplicar las
5 V **al sistema de reservas que construiste en el parcial**.

| V | Cómo se ve en tu sistema |
|---|---|
| Volumen | 8.821 hechos en 30 días de operación simulada → proyección anual |
| Velocidad | reservas concurrentes; la prueba de 30 peticiones simultáneas |
| Variedad | OLTP relacional + eventos de pago + logs de aplicación |
| **Veracidad** | el invariante de no-sobreventa **encontró un bug en el generador que lo alimentaba** |
| Valor | las tres vistas de negocio (`v_ocupacion_por_ruta`, `v_ingresos_por_tarifa`, `v_patrones_cancelacion`) |

Más una tabla de los tres roles (ingeniero / científico / arquitecto) mapeada a qué hiciste vos
en cada uno. **Un ensayo genérico sobre las 5 V es intercambiable con el de cualquier compañero;
uno que usa tu propio sistema no.**

### 2 · Session 3 — Diagramar arquitecturas · ~1,5 h
⚠️ La consigna dice **"levels of abstraction"**. Un solo diagrama no cumple: hay que entregar
**el mismo sistema en dos niveles** — vista de contexto (quién habla con qué) y vista de
componentes (servicios, formatos, flujos). Más media página sobre la anatomía de un ADR.

Insumo: `parcial-1-aerolinea/diagramas/arquitectura.md` (Mermaid) → reexpresar con el **kit
oficial de iconos AWS**, que el propio curso enlaza como material de la sesión.

### 3 · Session 4 — Setup + dos arquitecturas alternativas · ~1,5 h
Dos partes:
- **Setup:** capturas del entorno (AWS CLI v2, LabRole, CloudShell). El inventario ya está en
  el `CLAUDE.md`.
- **Dos arquitecturas alternativas** para el mismo caso de negocio, comparadas con criterios y
  costo. Opciones fuertes, las dos con material propio detrás:
  - *ingesta batch con Glue* vs *ingesta streaming con Kinesis Firehose*
  - *RDS → Glue → S3(Parquet) → Athena* vs *RDS → DMS → Redshift*

### 4 · Session 5 — ADR #1 · ~1,5 h
Usar **la plantilla de ADR que el curso enlaza** en el material de la Session 4, no una
inventada. Decisión a documentar: el diseño del data lake — tres zonas, Parquet en
`processed/` y `curated/`, particionado por fecha de vuelo, catálogo con Glue.

Insumo: las decisiones **ya están razonadas** en el `CLAUDE.md` (por qué RDS y no MySQL en EC2,
por qué Glue y no scripts, por qué Parquet, por qué SG grupo-a-grupo). Es traducción de formato,
no investigación.

### 5 · Session 6 — S3 a fondo · ~1,5 h + AWS
El de consigna más específica de los siete. Tres piezas:
1. El bucket con las tres zonas, **versionado activado** y capturas.
2. **La política de lifecycle en JSON, generada con IA y revisada línea por línea** — con la
   tabla *qué propuso / qué corregí / por qué*. La revisión **es** el entregable.
3. Tabla de clases de almacenamiento (Standard / IA / Glacier) con el cálculo de costo para tu
   propio dataset, no para uno de ejemplo.

### 6 · Session 7 — Glue Catalog y Crawlers · ~1 h
Evidencia del crawler y el catálogo corriendo sobre las bases del parcial, más las **cuatro
trampas** ya documentadas en el `CLAUDE.md` (URL JDBC con `://` y puerto, SG auto-referenciado,
VPC Endpoint de S3 vs NAT, `LabRole`). Y una sección sobre la consigna: **qué gobernanza se
alcanza sin Lake Formation** (IAM sobre el catálogo, tags, separación por database) y qué no
(permisos por fila y por columna).

### 7 · Session 8 — Checkpoint 1 · ~2 h + defensa
**Es nota de proyecto, no de assignment.** No es trabajo nuevo: es el ensamblado de los cuatro
anteriores — diagrama (S3) + ADR (S5) + bucket (S6) + crawler (S7) — más preparar la defensa
oral con el mismo método del parcial: cada decisión con su alternativa descartada.

### 8-11 · Módulos M1 a M4
Viven en la plataforma de **AWS Academy**, no en Moodle: lectura + quiz. Entregable en Moodle:
la captura del progreso. **Duración desconocida** — por eso M1 va primero y solo, para medir.

---

## 6. Calendario

| Cuándo | Qué |
|---|---|
| **07/09 hoy** | Pedir la reapertura de las 11 tareas. Nada más de Moodle |
| **08/09** | Sesión de AWS del parcial. **Al final**, con el parcial ya capturado: crear el bucket, versionado, la política de lifecycle y capturar Glue → cubre **S6**, **S7** y el bucket del **Checkpoint 1** |
| **09/09** | Ensayo de la defensa del parcial |
| **10/09** | 🎓 Subir el parcial a Moodle (tarea `273082`, tiene botón) + reforzar el pedido en persona |
| **11–13/09** | Módulos **M1 → M4**. Empezar por M1 solo, cronometrado |
| **14–19/09** | 🎯 Semana buffer: S1, S3, S4, S5, S6, S7 y el **Checkpoint 1** |

El campus dice explícitamente de la semana buffer: *"No AWS Academy module assignment is due
this week either; **continue with the previous week's module if not yet finished**"*. Está
previsto que se use para ponerse al día.

⚠️ **Y después se acaba el aire:** el 21/09 arranca la semana 7 con dos assignments nuevos
(S13, S14) y el Module 7. Si el backlog no cierra el 19, se superpone.

| Bloque | Horas |
|---|---|
| Pedido de reapertura | 0,1 |
| Piggyback en la sesión de AWS del 08/09 | 0,5 |
| Módulos M1–M4 | **4–12** ← la incógnita |
| Los 6 documentos de sesión | ~7,5 |
| Checkpoint 1 (ensamblado + defensa) | ~2 |
| **Total** | **~14 a 22 h** |

---

## 7. Riesgos

| Riesgo | Qué hacer |
|---|---|
| **El profesor no reabre las tareas** | Negociar canal alterno y **que quede por escrito** que se entregó. Sin eso, el trabajo existe pero no consta |
| **Reabre por una ventana corta** | Tener el material listo **antes** de que reabra. Otro motivo para no dejar la escritura para el final |
| Los módulos llevan mucho más de lo estimado | Medir con M1. Son puntos deterministas: si hay que recortar, se recorta en otro lado |
| Que lo pedido fuera una captura y entregues informes (o al revés) | El formato mixto de §3 cubre las dos lecturas |
| El Checkpoint 1 también se defiende oralmente | Prepararlo como el parcial: cada decisión con su alternativa |

---

## 8. Decisiones que te tocan a vos

1. **¿Un caso de estudio único —el sistema de la aerolínea— para todos los documentos, o cada
   sesión con su propio caso?**
   *Recomiendo el único.* Da coherencia, reusa trabajo verificado y podés defenderlo, que es
   como evalúa este profesor. El riesgo: si esperaba el ejercicio hecho en clase, queda
   desalineado — se mitiga con una línea al inicio de cada documento diciendo por qué se eligió
   ese caso.
2. **¿Herramienta para los diagramas: draw.io o la librería `diagrams` de Python?**
   `diagrams` es código: versionable en git, reproducible, y cuenta mejor en un curso de
   ingeniería de datos (Graphviz ya está instalado). draw.io es más rápido y va directo con el
   kit oficial de iconos. *Me inclino por `diagrams`*, pero es tu llamado.
3. **¿Pedís la reapertura hoy por escrito, o esperás al jueves en persona?**
   *Recomiendo las dos:* hoy por escrito para que quede constancia y él tenga tiempo, el jueves
   en persona para que se resuelva.
4. **¿Abro el Syllabus para ver si define qué se espera de cada assignment?**
   Es un archivo para descargar del campus; decime y lo reviso antes de que escribas nada.
