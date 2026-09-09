# Module 4 — Design Principles and Patterns for Data Pipelines

**Actividad de Moodle:** *AWS Academy Data Engineering — Module 4: Design Principles and Patterns for Data Pipelines*
**Semana 4** · cerró el 28 de agosto de 2026
**Caso de estudio:** sistema de reservas de una aerolínea (Parcial 1)

> ⚠️ El módulo se completa en la plataforma de **AWS Academy**; el entregable formal es la
> evidencia de haberlo terminado. Este documento es la **síntesis aplicada al proyecto**.
> **Estado del módulo:** ⬜ pendiente.

---

## 1. De qué trata el módulo

Los principios que separan un pipeline que funciona de uno que se puede operar: idempotencia,
tolerancia a fallos, desacople entre almacenamiento y cómputo, escalabilidad, y los patrones
batch / streaming / lambda. Cierra la semana del Checkpoint 1.

## 2. Idempotencia — la decisión más barata del proyecto

El ETL usa **recarga completa** (`TRUNCATE` + `INSERT`), no carga incremental.

A 9.121 filas en 1,64 s es lo correcto, y no por simplicidad: **es idempotente, no arrastra estado
y no puede quedar a medias.** Si falla en el medio, se vuelve a correr y punto. La alternativa
—incremental por marca de agua sobre `historial_reserva.ocurrido_en`— sólo se justifica cuando la
recarga deja de entrar en la ventana de proceso.

Está documentada como la evolución prevista, con su disparador. No como deuda.

## 3. Tolerancia a fallos: el criterio que decidió batch sobre streaming

Al comparar las dos arquitecturas de ingesta para el mismo caso, el modo de falla resultó más
decisivo que la latencia o el costo:

| | Batch (Glue) | Streaming (Kinesis) |
|---|---|---|
| Latencia | hasta 24 h | segundos |
| Costo mensual | ~$5 | ~$11 |
| **Costo con tráfico cero** | **~$0** | **~$11** — el shard cobra por existir |
| **Modo de falla** | el job falla → se reintenta, **la fuente sigue intacta** | evento perdido → **hueco permanente** |
| Reproceso histórico | trivial: se relee la fuente | difícil: los eventos expiraron |

**El batch tolera errores y el streaming no.** Ninguna de las tres preguntas del negocio se decide
minuto a minuto, así que pagar el doble y aceptar pérdida permanente de datos para adelantar un
dato que nadie mira hasta la mañana no se sostiene.

Con disparador declarado para revisarlo: **precios dinámicos según búsquedas**. Ahí sí haría falta
reaccionar a eventos que no se guardan en la base transaccional.

## 4. Desacople entre almacenamiento y cómputo

Es el principio que el Glue Data Catalog implementa. Sin catálogo, cada motor necesita que le
declaren el esquema, y las definiciones se desincronizan apenas alguien agrega una columna.

| | Sin catálogo | Con catálogo |
|---|---|---|
| Cambiar de motor | redefinir esquemas en el motor nuevo | apunta al mismo catálogo y funciona |
| Dos motores a la vez | dos definiciones que divergen | una definición, dos lectores |
| Saber qué datos hay | mirar S3 y adivinar | consultar el catálogo |

En el proyecto: **42 tablas en tres databases**, y el crawler dedujo solo las claves de partición
`year`/`month` de la convención de rutas Hive. Nadie se las declaró.

## 5. Reversibilidad — el principio que casi se me escapa

El data lake tiene tres zonas, y la de arriba existe por un solo motivo: **que un error de
procesamiento sea reversible.** Si la lógica de limpieza tiene un bug, se corrige el código y se
reprocesa desde `raw/`, sin volver a tocar una fuente transaccional que para entonces ya cambió.

Eso obligó a una decisión concreta en el job de Glue: **`processed/` se construye leyendo `raw/`
desde S3, no consultando la base otra vez.** Si el pipeline sólo pudiera regenerarse volviendo a la
fuente, la zona cruda sería decorativa y el principio, una frase.

> Y es exactamente el error que cometí en la primera pasada: dejé las tres zonas creadas y sólo
> `curated/` con datos. El diagrama afirmaba un flujo que la evidencia no respaldaba. **Un
> principio de diseño no está aplicado hasta que se puede medir.**

## 6. Escalabilidad: dónde se rompe esto

| Componente | Aguanta | Se rompe cuando |
|---|---|---|
| Particionado mensual | ~400× el volumen actual | una partición supera ~128 MB → bajar a diaria |
| Recarga completa del ETL | mientras entre en la ventana | pasa de minutos a horas → incremental |
| PostgreSQL como OLAP | ~10 M filas/año | se empiezan a guardar eventos de búsqueda |
| Batch nocturno | siempre que la decisión sea diaria | precios dinámicos |

Los cuatro umbrales están escritos con número. **Un límite sin cifra no se revisa nunca.**

## 7. Evidencia a adjuntar

Captura del módulo al 100 % con el resultado del quiz, como `modulo-4-evidencia.png`.

## 8. Qué generó la IA y qué corregí

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Listar los principios de diseño en abstracto | Atar cada uno a una decisión del proyecto con su medición | Un principio recitado no se puede defender; uno aplicado tiene un número al lado |
| 2 | Presentar la recarga completa como una limitación a superar | Sostenerla como **decisión**, con su disparador de revisión | Es idempotente y no puede quedar a medias. Lo simple acá es lo correcto, no lo provisorio |
| 3 | Omitir que la primera pasada dejó las zonas vacías | Documentarlo en la §5 | Es el mejor ejemplo del módulo que tengo: un principio que estaba escrito y no aplicado, detectado releyendo la evidencia contra el diagrama |
