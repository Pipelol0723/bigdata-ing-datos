# Anexo A — Registro de prompts

El enunciado (§3) permite asistentes de IA con la misma regla de los parciales anteriores: cada
decisión tiene que poder explicarse y defenderse, y el registro de prompts es obligatorio. Lo que se
registra no es el prompt perfecto sino **la iteración**: qué se pidió, qué devolvió la herramienta y
qué hubo que corregir o decidir.

**Asistente utilizado:** Claude (Claude Code, modelo Opus). Tuvo acceso al repositorio, a una
terminal local y al navegador (Claude in Chrome) para operar Moodle, la consola de AWS y CloudShell.
Regla del proyecto: el asistente nunca borra ni apaga recursos de AWS; propone el comando y espera
confirmación.

---

### 12/11 — Lectura del enunciado y del harness

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección o decisión |
|---|---|---|---|---|
| 1 | Entender qué se evalúa | Se adjuntaron el `.docx` y el `.zip`: *"revisa la información del parcial y organízala en la carpeta de la materia; revisa el Moodle si hace falta y pregúntame lo que necesites"* | Leyó los 35 archivos del harness, no sólo el enunciado, y armó `PLAN.md` con lo que cada test verifica de verdad y **15 trampas**. Entre ellas: el replay del profesor reutiliza los mismos `event_id` con otro contenido (lo midió: 19.634 de 19.912), Firehose deja los JSON sin salto de línea, el texto de `STAR.md` sobre los días de puente contradice al código del oráculo y R6 cuenta huérfanos en todas las filas | Leer el código de los tests volvió a ser lo que más valió. Respondí lo que sólo yo sabía: semilla 12345, individual, el P2 ya calificado |
| 2 | Fechas | *"revisa el moodle"* (19/11) | La tarea ya mostraba las fechas: examen teórico y defensa el 26/11 para el g01. Comprobó que los adjuntos de Moodle eran idénticos (mismo SHA-256) a los recibidos | Confirmé que soy del g01 |

### 19/11 — Decisiones (antes de construir)

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección o decisión |
|---|---|---|---|---|
| 3 | Elegir la arquitectura | *"iniciemos las decisiones"* | 12 decisiones (D1–D12) en tres bloques, como los de la defensa. Cada una con sus alternativas, su costo, el requisito que toca y una recomendación | **Las elegí yo** con las alternativas a la vista. Tomé las recomendadas: reutilizar la EC2 del P2, cola en memoria para publicar, consumidor dentro de la API, Firehose, Athena CTAS con rebuild completo, miembro `UNKNOWN`, refresh cada 10 min sólo si hay datos, workgroup propio, dimensiones por SQL y archivar la landing antes de la defensa |
| 4 | Verificar una suposición | (el asistente, antes de recomendar Athena) | Buscó en la documentación de AWS si Firehose agrega el salto de línea sin *dynamic partitioning*: sí, con `AppendDelimiterToRecord` | Quedó como "a verificar en el lab". Se verificó el 24/11 (#9) |
| 5 | Costos | (D9) | Tres perfiles: stream sólo en pruebas (~US$11), producción 24×7 (~US$23) y todo sólo en pruebas (~US$5). Recordó que en el P2 R12 falló con US$12,65 | Elegí el que sigue el ejemplo del enunciado (*"only while testing"*), con la narrativa completa en la §5.8 |

### 23/11 — Desarrollo en la laptop (US$0)

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección o decisión |
|---|---|---|---|---|
| 6 | Construir el camino analítico sin gastar | *"inicia el desarrollo del parcial"* | El ETL en SQL de Athena (`app/sql`), `estrella.py` y una simulación que corre **los tests originales del harness** con DuckDB en lugar de Athena. Usa la costura `registry.py` del propio harness, sin editarlo | 23 de 23 tests en la primera corrida. Antes de darlo por bueno, el asistente revisó en el reporte que cada test comparara contra el oráculo y no pasara en vacío |
| 7 | Medir la trampa 1 | (el asistente) | Simuló el replay del profesor (`probe_salt = 7`) sobre una landing con nuestras corridas: el bloque de la estrella bajó de 41 a **20** puntos. Archivando la landing, 41/41 | Confirmó la decisión D12 con un número, no con una sospecha |
| 8 | La API | (mismo pedido) | Publicador con cola y lotes, consumidor de la vista en vivo, cancelación, endpoints de refresh. Probado con la API real, PostgreSQL local y Kinesis simulado con moto: R1–R3 en verde. Cancelación: 200, 409 y 404 probados a mano | Se agregó `price_cents` a la reserva, para que la cancelación lleve el mismo precio que la creación aunque el vuelo cambie de precio |

### 24/11 — AWS y documento

| # | Objetivo | Prompt (resumen) | Qué devolvió | Corrección o decisión |
|---|---|---|---|---|
| 9 | Desplegar y medir | *"realiza todo lo que falta ahora"* | Arrancó el lab, subió el paquete a CloudShell y corrió `10-levantar-sesion.sh` | **Falló el primer CTAS:** un workgroup con *enforce* rechaza `external_location`. Se pasó a `EnforceWorkGroupConfiguration = false` (el límite de 1 GB sigue). Antes del harness hizo una prueba de humo: 5 búsquedas, que la vista en vivo contó, y un objeto de Firehose con 5 JSON en 5 líneas |
| 10 | El harness en AWS | (mismo pedido) | **70,0 / 70,0** en la primera corrida completa: 29 tests en 2 min 46 s, con R4 (61 s) y R11, que no se podían simular | El reporte se copió a `evidencia/` y al bucket |
| 11 | Documento | (mismo pedido) | Las secciones 5 y 6, la trazabilidad, este registro y el anexo de cambios. Para la §5.6 calculó con el oráculo cuánto se equivocaría una SCD tipo 1: enero de 2025, +38,8 % REGIONAL y −42,5 % TRUNK | Pendiente de mi revisión antes de entregarlo: lo defiendo yo |

---

**Lo que la herramienta no decidió:**
- La semilla, la modalidad y las 12 decisiones de diseño.
- Cuándo gastar en AWS.
- Bajar el stream y los restos del P2: se pidieron con confirmación explícita.
- Entregar en Moodle.
