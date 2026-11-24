# Capstone Project — AWS Academy Data Engineering · plan

> Leído en Canvas (curso 180877, ítem *Capstone project*) el **09/11/2026**, sin arrancar el lab.
> Moodle: tarea *AWS Academy Data Engineering — Capstone Project*, abre **lun 16/11** y cierra
> **sáb 28/11 23:59**. Vale 5 puntos, como cada módulo.

## 1. Qué pide

Armar la infraestructura para que analistas consulten datos de pesca de **Sea Around Us** (capturas por
año, país y especie, 1950–2018) usando tres archivos CSV:

| Archivo | Qué contiene |
|---|---|
| `SAU-GLOBAL-1-v48-0.csv` | Todas las aguas internacionales (*high seas*). 561.675 líneas. **No tiene** `area_name` |
| `SAU-HighSeas-71-v48-0.csv` | Una sola zona de alta mar: *Pacific, Western Central* |
| `SAU-EEZ-242-v48-0.csv` | La zona económica exclusiva (EEZ) de **Fiji**. Dos columnas con otro nombre: `fish_name` (= `common_name`) y `country` (= `fishing_entity`) |

**Arquitectura final:** IDE (Cloud9) → S3 `data-source-#####` (Parquet) → crawler de Glue → Glue Data
Catalog (`fishdb`) → Athena, que guarda sus resultados en S3 `query-results-#####`. El rol
`CapstoneGlueRole` ya viene creado.

### Tareas (26 pasos, ~4 h según la guía)

1. **Entorno:** abrir el IDE (URL y contraseña del panel del lab), crear los dos buckets en us-east-1,
   bajar los 3 CSV con `wget`, convertir GLOBAL a Parquet con pandas y subirlo a `data-source` con la CLI.
2. **Glue + Athena:**
   - convertir y subir HighSeas;
   - crear la base `fishdb` y el crawler `fishcrawler` (rol `CapstoneGlueRole`, origen el bucket
     `data-source`, frecuencia *On demand*) y correrlo;
   - configurar la salida de Athena en `query-results`;
   - consultas de verificación;
   - **desafío:** el valor de lo pescado por Fiji en toda la alta mar desde 2001, guardado como vista
     `challenge`.
3. **Archivo nuevo:**
   - renombrar las dos columnas del EEZ con pandas, convertirlo a Parquet, subirlo y volver a correr el
     crawler;
   - consultas que tienen que cerrar entre sí: valor en alta mar + valor en la EEZ = valor total;
   - vista `MackerelsCatch` y consultas sobre ella.
4. **Submit:** un **corrector automático** de Vocareum da los puntos por tarea. Se puede enviar varias
   veces; vale la última entrega. *Submission Report* trae el detalle.

## 2. Diferencias con lo que veníamos haciendo

- **Es otro lab de Vocareum**, no el Learner Lab: otra cuenta, con su propio presupuesto y su propio
  panel. Los recursos y el saldo del Learner Lab (US$20,6 de 50) no se tocan. El entorno es de larga
  duración: lo creado queda entre sesiones.
- **El IDE pide una contraseña** (`LabIDEPassword`, en el panel del lab). La escribe el alumno. Una vez
  adentro, Claude puede operar la terminal del IDE.
- El lab puede restringir servicios que no estén en la guía: conviene seguir los pasos tal cual (IDE + CLI
  + consola) y no improvisar con otros servicios.
- **El corrector revisa lo que existe en la cuenta:** buckets, objetos, base, crawler, tabla y las
  vistas `challenge` y `mackerelscatch`. Los nombres tienen que ser exactamente los de la guía.

## 3. Cómo hacerlo rápido y sin errores

**Antes del lab, en la laptop y gratis:** los 3 CSV son públicos (`aws-tc-largeobjects`, us-west-2).
Se bajan y se prueba todo con pandas y DuckDB:
- el script de conversión a Parquet y el de renombrado;
- las consultas con los placeholders resueltos;
- la comprobación de que las sumas cierran.

Así el lab es sólo ejecutar, ~1 hora en vez de 4.

**Placeholders ya resueltos al leer la guía:**

| Paso | Placeholder | Valor |
|---|---|---|
| 15 | `<FMI_1>` | `fishdb.data_source_#####` (la tabla que crea el crawler; se llama como el bucket) |
| 15 | `<FMI_2>` | `2000` (*"since 2001"*, con `year > <FMI_2>`) |
| 15 (desafío) | consulta | `WHERE area_name IS NULL AND fishing_entity = 'Fiji' AND year > 2000`, columna `ValueAllHighSeasCatch`. Las filas de GLOBAL no tienen `area_name`: ésas son "toda la alta mar" |
| 17 | `df.rename` | `{"fish_name": "common_name", "country": "fishing_entity"}` |

**Trampas a cuidar:**
- El crawler tiene que generar **una sola tabla** con los tres Parquet. Hay que dejarlos en la raíz del
  bucket, como dice la guía, y con nombres de columna que coincidan: por eso el renombrado del EEZ va
  antes de subirlo.
- **Configurar la salida de Athena** (*query-results*) antes de la primera consulta, porque si no, falla.
- `pip install` en el IDE va con `sudo`, como indica la guía.
- **Al terminar, dejar todo**: el corrector revisa lo que existe. Recién después del Submit y de la nota
  se decide la baja (en esta cuenta el costo es mínimo: S3, un crawler On demand y Athena por consulta).

## 4. Calendario

| Cuándo | Qué |
|---|---|
| esta semana (gratis) | Preparar y probar en local los scripts y las consultas |
| desde el lun 16/11 | Una sesión del lab de Capstone: ejecutar, Submit, revisar el Submission Report |
| antes del sáb 28/11 | Subir a Moodle la evidencia: nota del corrector + Submission Report |
