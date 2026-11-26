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

## 3b. Ejecución en un script (25/11, guía releída completa)

`capstone.sh` hace los pasos 5 a 23 en el orden de la guía, imprime cada consulta con su resultado y
termina con un resumen de lo que revisa el corrector. Es idempotente y no borra nada.

- **Dónde:** CloudShell de la cuenta del Capstone (no pide contraseña) o la terminal del IDE (la contraseña
  la escribe el alumno). Se sube con *Actions → Upload file* y se corre con
  `nohup bash capstone.sh > capstone-salida.log 2>&1 &`, porque CloudShell se desconecta si Chrome no
  está al frente.
- **Una diferencia con la guía, a propósito:** al convertir a Parquet se fijan los tipos (`year` int64,
  `tonnes` y `landed_value` double, el resto string). Una columna vacía en un archivo pandas la infiere
  como double, y en otro es texto: el crawler daría un esquema mezclado y Athena un `HIVE_BAD_DATA`.
  Probado en local con muestras: los tres Parquet salen con el mismo tipo por columna.
- **Chequeos que frenan el script:** que el crawler deje **una sola tabla** `data_source_#####` (las
  vistas no cuentan) y que tras el EEZ no aparezcan `fish_name` ni `country`.
- **Comprobación del *Analysis* del paso 20:** una consulta extra calcula alta mar + EEZ − total por año;
  la diferencia tiene que dar 0.00.
- **Athena:** la salida del workgroup `primary` se fija en `s3://query-results-#####/` con
  `update-work-group` y además cada consulta la pasa explícita.

## 3c. ✅ Ejecutado el 25/11: **25/25** en el corrector (Submit 20:37 PST)

Evidencia en `evidencia/` (nota + Submission Report, y `Capstone-evidencia-25-de-25.pdf` para Moodle).
End Lab hecho: **US$0 de 35** usados en la cuenta del Capstone.
**Moodle:** "Enviado para calificar" el 25/11 a las 23:43, con el PDF y una línea de texto en línea.

**Lo que el lab no deja hacer, y cómo se resolvió:**

| Intento | Resultado |
|---|---|
| CloudShell en la cuenta del Capstone | ❌ `cloudshell:CreateEnvironment` denegado |
| CLI del IDE con su rol (`VSCodeInstanceRole`) | Sólo `s3:ListBuckets`: ❌ `CreateBucket`, ❌ `PutObject`, ❌ Glue, ❌ Athena, ❌ IAM |
| CLI del IDE con las credenciales del lab | No se usó: el asistente no maneja credenciales |
| **Lo que se hizo** | Buckets, `fishdb`, `fishcrawler`, salida de Athena, consultas y vistas **por consola**. Los Parquet se generaron en la laptop con el mismo `convertir.py` (de `capstone-ide.sh`) y se subieron con el botón *Cargar* de S3 |

- Nombres: `data-source-23719`, `query-results-12481` y la tabla `data_source_23719`.
- Crawler:
  - 1.ª corrida: 38 s, con 588.395 registros y 15 columnas.
  - 2.ª corrida, con el EEZ: 615.444 registros y 17 columnas, ya sin `fish_name` ni `country`.
  - En las dos dejó **una sola tabla**.
- Las consultas de Athena dieron **exactamente** lo que había calculado DuckDB en local. Por ejemplo, el *challenge* de 2001 da 65.491.257,47.
- La comprobación alta mar + EEZ − total da 0,0 en los 18 años.
- `consultas-athena.sql` tiene todas las consultas tal como se corrieron.
- **Diferencia con la guía:** su ejemplo de `MackerelsCatch` sólo muestra filas de la EEZ de Fiji, pero en nuestros datos también entran capturas en alta mar (por ejemplo, USA 2015 en Pacific WC, 859,5 t). Las 8 filas de China en la EEZ coinciden con la guía, y el corrector dio 5/5 a esa vista. Lo más probable es que la captura de la guía se haya hecho con otra versión del archivo HighSeas.
- `capstone-ide.sh` queda como referencia del camino de la guía (IDE + CLI). Sólo funciona si la CLI del IDE tiene las credenciales del lab.

**Queda en la cuenta del Capstone** (otra cuenta, otro presupuesto; nada cobra por hora):
- los 2 buckets (~11 MB);
- `fishdb`, con la tabla y las vistas `challenge` y `mackerelscatch`;
- el crawler On demand.

El EC2 del IDE se detiene con End Lab.

## 4. Calendario

| Cuándo | Qué |
|---|---|
| esta semana (gratis) | Preparar y probar en local los scripts y las consultas |
| desde el lun 16/11 | Una sesión del lab de Capstone: ejecutar, Submit, revisar el Submission Report |
| antes del sáb 28/11 | Subir a Moodle la evidencia: nota del corrector + Submission Report |
