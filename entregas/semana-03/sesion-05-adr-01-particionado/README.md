# Session 5 — Diseño del data lake y **ADR #1: esquema de particionado**

**Curso:** Big Data e Ingeniería de Datos (PCIA 5010) · Semana 3 · Sesión 5
**Tema:** zonas (raw/processed/curated), particionado y formatos — **ADR #1 de esquema de particionado**
**Caso:** sistema de reservas de la aerolínea (`entregas/parcial-1-aerolinea/`)

---

# Parte 1 — Diseño del data lake

## 1.1 Las tres zonas

| Zona | Contenido | Formato | Regla |
|---|---|---|---|
| `raw/` | copia fiel de la fuente, sin tocar | CSV, tal como sale | **inmutable**: nunca se corrige acá |
| `processed/` | limpio, tipado, deduplicado | Parquet + Snappy | regenerable desde `raw/` |
| `curated/` | modelo estrella listo para consultar | Parquet + Snappy | regenerable desde `processed/` |

**Por qué la separación no es burocracia:** si la lógica de limpieza tiene un error, se corrige
el código y se reprocesa desde `raw/`. Sin zona cruda hay que volver a extraer de la base
transaccional, que para entonces ya cambió. **`raw/` es lo que hace reversible una equivocación.**

## 1.2 Formatos

| | CSV | Parquet |
|---|---|---|
| Orientación | fila | **columna** |
| Esquema | ninguno | embebido, con tipos |
| Compresión típica | — | 5-10× |
| Athena escanea… | **todo el archivo** | sólo las columnas de la query |

Athena cobra **$5 por TB escaneado**. Una consulta que lee 3 de 20 columnas sobre Parquet escanea
una fracción de lo que escanearía sobre CSV: es la misma pregunta a una fracción del precio. Por
eso `raw/` es CSV (fidelidad a la fuente) y todo lo demás es Parquet (costo de consulta).

---

# Parte 2 — ADR #1: esquema de particionado del data lake

> Formato según la guía de AWS Prescriptive Guidance sobre *Architectural Decision Records*.

| | |
|---|---|
| **ADR** | 01 |
| **Título** | Particionar el data lake por **fecha de vuelo**, con granularidad **mensual** |
| **Estado** | ✅ Aceptada — 2026-09-07 |
| **Decide** | esquema de particionado de `processed/` y `curated/` |
| **Relacionada con** | `FR-19` (preguntas de negocio), `NFR-PERF-01`, ADR #2 (Athena vs Redshift, semana 10) |

## Contexto

El data lake alimenta tres preguntas de negocio, todas con filtro temporal:

| Vista | Filtra por |
|---|---|
| `v_ocupacion_por_ruta` | rango de fechas + ruta |
| `v_ingresos_por_tarifa` | rango de fechas |
| `v_patrones_cancelacion` | rango de fechas + ruta |

Volumen medido hoy: **8.821 filas de hechos** producidas por 227 instancias de vuelo en 30 días,
o sea **~294 filas por día**. Dos tablas de hechos a granos distintos: `fact_tramo_vendido`
(tramo vendido) y `fact_ocupacion_vuelo` (instancia de vuelo).

Fuerzas en juego:

1. **Athena cobra por byte escaneado.** El particionado es el mecanismo principal para no leer lo
   que no se necesita.
2. **Los archivos chicos degradan y encarecen.** Cada archivo tiene costo fijo de apertura y de
   metadatos en el catálogo. Parquet rinde con archivos de cientos de MB.
3. **Hay dos fechas candidatas y no son la misma.** Una reserva creada en enero para un vuelo de
   marzo tiene `fecha_reserva` ≠ `fecha_vuelo`.
4. **Presupuesto de 50 USD** para todo el semestre: el crawler cobra por ejecución.

## Opciones consideradas

### Opción A — Sin particionar
Un único conjunto de archivos por tabla.

- ✅ Máxima simplicidad; a 8.821 filas, Athena escanea todo en milisegundos y cuesta ~$0.
- ❌ No escala: cuando el volumen crezca hay que reescribir el layout y todas las queries.
- ❌ No demuestra el resultado de aprendizaje de la asignatura.

### Opción B — Particionar por `fecha_reserva`
`year=2026/month=09/day=07/`

- ✅ **Las particiones quedan inmutables:** una reserva creada hoy nunca cambia de partición, así
  que la carga incremental sólo escribe la partición del día.
- ❌ **Las tres consultas del negocio preguntan por fecha de vuelo, no de reserva.** Ninguna
  podaría particiones: se escanearía todo igual. El particionado sería decorativo.

### Opción C — Particionar por `fecha_vuelo`, granularidad diaria
`year=2026/month=09/day=07/`

- ✅ Poda perfecta para las tres consultas.
- ❌ **~294 filas por partición ≈ archivos de ~15 KB.** Es el *small files problem*: cientos de
  archivos diminutos, catálogo inflado y consultas más lentas que sin particionar.
- ❌ Más particiones = crawler más caro.

### Opción D — Particionar por `fecha_vuelo` + `ruta`
- ✅ Dos de las tres consultas filtran también por ruta.
- ❌ 14 rutas × días = explosión combinatoria de particiones minúsculas. Empeora la Opción C.

### Opción E — Particionar por `fecha_vuelo`, granularidad **mensual** ← elegida
`year=2026/month=09/`

- ✅ Poda por el filtro que las tres consultas usan de verdad.
- ✅ ~8.800 filas por partición ≈ **archivos de unos cientos de KB**: chicos todavía, pero dos
  órdenes de magnitud mejor que la opción diaria.
- ✅ Pocas particiones → catálogo liviano y crawler barato.
- ⚠️ Las particiones **no son inmutables**: una reserva creada hoy para un vuelo de diciembre
  escribe en una partición futura.

## Decisión

**Particionar `processed/` y `curated/` por fecha de vuelo con granularidad mensual**, en
notación Hive para que Glue y Athena la detecten solas:

```
s3://<bucket>/curated/fact_tramo_vendido/year=2026/month=09/parte-0000.parquet
s3://<bucket>/curated/fact_ocupacion_vuelo/year=2026/month=09/parte-0000.parquet
```

Las dimensiones (141 filas en total) **no se particionan**: son demasiado chicas y se leen
enteras en cada join.

### El criterio de revisión, explícito

> **Cuando una partición mensual supere ~128 MB, bajar la granularidad a diaria.**

128 MB es el orden de tamaño en que Parquet rinde bien. A ~300 KB por mes hoy, ese umbral está a
unas 400 veces el volumen actual. **La decisión no es "mensual para siempre": es "mensual hasta
este número".** Escrito así, la revisión es una medición y no una discusión.

## Consecuencias

### Positivas
- Las tres consultas podan particiones por su filtro real.
- Costo de Athena ≈ $0 al volumen actual y creciente sólo con el rango consultado, no con el
  histórico total.
- Pocas particiones: el crawler corre rápido y barato.

### Negativas — que se aceptan
- **Particiones mutables.** Una reserva para un vuelo lejano modifica una partición futura. Hoy
  no duele porque el ETL es **recarga completa** (`TRUNCATE` + `INSERT`); cuando pase a
  incremental habrá que reescribir la partición del mes afectado, no sólo la del día.
- **Granularidad mensual poda menos que la diaria.** Una consulta de un solo día lee el mes
  entero. Aceptable: leer 300 KB de más cuesta menos que administrar 30 archivos de 15 KB.
- **Quedan preguntas por fecha de reserva sin optimizar** (p. ej. *"¿cuánto se vendió en agosto?"*).
  Escanean todo. Si se vuelven frecuentes, la salida no es reparticionar sino agregar una tabla
  derivada — y eso sería un ADR nuevo, no una edición de éste.

### Neutras
- Habilita más adelante **partition projection** de Athena: declarar el patrón de particiones en
  el catálogo y dejar de correr el crawler para descubrirlas. Ahorra el costo por ejecución. No
  se implementa ahora para no introducir dos cambios a la vez.

---

## 3. Qué generó la IA y qué corregí

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Particionar por `year/month/day` — "el estándar" | Bajar a granularidad **mensual** | A 294 filas por día, el estándar produce archivos de 15 KB. Copiar un patrón sin mirar el volumen propio es el error que el particionado debía evitar |
| 2 | Dar por obvio que la fecha era `fecha_reserva` | Separar las dos fechas como **opciones distintas** | Son fechas diferentes y eligen mal quien no lo nota: las consultas del negocio usan la de vuelo |
| 3 | Cerrar el ADR sin criterio de revisión | Agregar el umbral de **128 MB** | Sin umbral, "revisar cuando crezca" no se revisa nunca. Con número, es una medición |
| 4 | Omitir que las particiones quedan mutables | Documentarlo en consecuencias negativas | Es el costo real de la opción elegida. Un ADR que sólo lista ventajas no sirve para decidir |

> 📌 **Decisión que tomé yo y conviene que revises antes de entregar:** elegí `fecha_vuelo` sobre
> `fecha_reserva` porque es lo que filtran las tres vistas del proyecto. Si en la sustentación
> aparece una pregunta de negocio orientada a la venta (*"¿cuánto vendimos en agosto?"*), la
> respuesta correcta es la tabla derivada de la sección de consecuencias, no reparticionar.
