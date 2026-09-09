# Session 6 — Amazon S3 a fondo: clases, versionado y ciclo de vida

**Curso:** Big Data e Ingeniería de Datos (PCIA 5010) · Semana 3 · Sesión 6
**Tema:** clases de almacenamiento, versionado y ciclo de vida — **política implementada con
asistencia de IA y revisada línea por línea**
**Caso:** data lake del sistema de reservas (`entregas/parcial-1-aerolinea/`)

**Artefactos de esta carpeta**

| Archivo | Qué es |
|---|---|
| `lifecycle-borrador-ia.json` | lo que generó el asistente. **No aplicar** |
| `lifecycle-revisada.json` | la versión corregida, lista para `put-bucket-lifecycle-configuration` |

---

## 1. Clases de almacenamiento

> Precios aproximados de us-east-1. Sirven para decidir órdenes de magnitud, no como cotización.

| Clase | USD/GB-mes | Recuperación | Mínimo de permanencia | ¿La lee Athena? |
|---|---|---|---|---|
| **Standard** | $0,023 | gratis | — | ✅ |
| **Standard-IA** | $0,0125 | $0,01/GB | 30 días | ✅ |
| **One Zone-IA** | $0,010 | $0,01/GB | 30 días | ✅ (una sola AZ) |
| **Glacier Instant Retrieval** | $0,004 | $0,03/GB | 90 días | ✅ (milisegundos) |
| **Glacier Flexible** | $0,0036 | por restauración | 90 días | ❌ **hay que restaurar antes** |
| **Glacier Deep Archive** | $0,00099 | horas | 180 días | ❌ |

Tres cosas que la tabla de precios no dice y deciden el diseño:

1. **El mínimo de permanencia se cobra igual.** Un objeto movido a Standard-IA y borrado a los
   10 días paga 30. Mover datos que van a cambiar pronto **aumenta** la factura.
2. **Existe un tamaño mínimo facturable de 128 KB** en IA y en Glacier IR. Un objeto de 40 KB se
   cobra como 40 KB en Standard y como **128 KB** en IA.
3. **Las clases Glacier Flexible y Deep Archive rompen Athena.** La consulta no se pone lenta:
   falla, hasta que alguien restaure los objetos.

### El cálculo para nuestro data lake, y el resultado incómodo

Volumen real: **< 1 GB** — 8.821 filas de hechos y 141 de dimensiones en Parquet.

| Escenario | Costo mensual |
|---|---|
| Todo en Standard (~300 MB) | **$0,007** |
| Todo en Glacier IR | **$0,001** |
| **Ahorro** | **~medio centavo por mes** |

**A esta escala, el ciclo de vida no ahorra dinero.** Decirlo es parte del ejercicio: una
política de lifecycle justificada por "ahorro" sobre 300 MB es teatro de optimización.

Y hay un caso donde **enfriar sale más caro**. Nuestros archivos son chicos por el particionado
mensual del ADR #1. Si fueran de 50 KB:

| | Cálculo | USD/mes |
|---|---|---|
| 50 objetos × 50 KB en **Standard** | 0,00238 GB × $0,023 | $0,0000548 |
| Los mismos en **Standard-IA** | 50 × **128 KB** mínimo = 0,0061 GB × $0,0125 | **$0,0000763** |

**Standard-IA sale ~39 % más caro** que Standard para esos objetos. La clase "barata" cuesta más
porque el mínimo facturable multiplica el volumen por más de lo que la tarifa lo divide.

> ### ✅ Confirmado por AWS al aplicar la política (08/09)
>
> Al ejecutar `put-bucket-lifecycle-configuration`, la API respondió:
>
> ```json
> { "TransitionDefaultMinimumObjectSize": "all_storage_classes_128K" }
> ```
>
> **AWS no transiciona objetos de menos de 128 KB, por defecto y para todas las clases.** O sea
> que el problema que calculamos arriba está reconocido por el propio servicio, que trae una
> protección de fábrica contra él.
>
> Dos consecuencias concretas:
>
> 1. La regla de `processed/` **no va a mover nada** mientras los archivos sigan por debajo de
>    128 KB. No es un error: es el comportamiento correcto, y significa que la política está
>    escrita para el volumen que vendrá, no para el actual.
> 2. Quien quiera forzar el comportamiento viejo puede pasar
>    `TransitionDefaultMinimumObjectSize=varies_by_storage_class`. **No lo hacemos**: sería pedir
>    explícitamente que se apliquen las transiciones que acabamos de demostrar que encarecen.

### Entonces, ¿para qué la política?

Por dos reglas que **sí** importan a cualquier escala, incluso a 300 MB — y no son las
transiciones:

- `NoncurrentVersionExpiration` — evita que las versiones viejas crezcan sin techo.
- `AbortIncompleteMultipartUpload` — borra restos de subidas fallidas que se facturan y **no se
  ven en la consola**.

Las transiciones empiezan a pagar alrededor del **terabyte**: 1 TB en Standard son $23/mes y en
Glacier IR $4/mes. Ahí la política deja de ser higiene y pasa a ser ahorro.

---

## 2. Versionado

Versionar conserva cada sobrescritura como una versión anterior. Protege contra el borrado
accidental y contra un ETL que escribe mal.

⚠️ **La trampa aplicada a nuestro pipeline:** el ETL es una **recarga completa**
(`TRUNCATE` + `INSERT`), así que **cada ejecución reescribe todos los archivos y crea una versión
nueva de todo**. Con versionado activado y sin expiración de versiones no vigentes, el costo de
almacenamiento crece linealmente con la cantidad de veces que se corrió el ETL — y en la consola
el bucket sigue mostrando un solo archivo por tabla.

Es exactamente el patrón que ya nos costó plata en este curso: de $1,70 gastados en una semana,
$0,77 fueron almacenamiento de recursos que nadie usaba. **El gasto peligroso no es el pico, es
el piso.**

**Decisión:** versionado **activado**, con expiración de versiones no vigentes a 30 días en
`raw/` y 15 en `processed/` y `curated/`. Más corto donde el dato es regenerable.

---

## 3. La política: borrador de IA y revisión línea por línea

### 3.1 Lo que generó el asistente

```json
{
  "Rules": [
    {
      "ID": "archivar-datos-antiguos",
      "Status": "Enabled",
      "Transitions": [
        { "Days": 30, "StorageClass": "STANDARD_IA" },
        { "Days": 90, "StorageClass": "GLACIER" }
      ],
      "Expiration": { "Days": 365 }
    }
  ]
}
```

Es sintácticamente válido, se aplica sin error y **destruye el data lake en un año**.

### 3.2 Revisión línea por línea

| # | Línea | Defecto | Consecuencia | Corrección |
|---|---|---|---|---|
| 1 | *(ausente)* `Filter` | Sin filtro, la regla aplica a **todo el bucket** | `curated/` —lo que Athena consulta a diario— también se archiva | Tres reglas, una por zona, con `Filter.Prefix` |
| 2 | `"Expiration": {"Days": 365}` | **Borra los datos crudos al año** | `raw/` es la única copia fiel de la fuente. Sin ella no se puede reprocesar: el borrado es irreversible | ❌ **Eliminada.** `raw/` no expira |
| 3 | `"StorageClass": "GLACIER"` | Glacier Flexible **no es consultable directamente** | Toda query de Athena sobre datos de más de 90 días **falla** hasta restaurarlos | `GLACIER_IR` (recuperación en milisegundos) y **sólo en `raw/`**, que Athena no consulta |
| 4 | `"Days": 30` → Standard-IA | Ignora el **mínimo de 128 KB** y el de permanencia | Con archivos chicos, IA sale **más caro** que Standard (§1) | Sólo en `processed/`, a 60 días, cuando ya no se reescribe |
| 5 | *(ausente)* `NoncurrentVersionExpiration` | Con versionado activo, las versiones viejas **no expiran nunca** | Nuestro ETL de recarga completa crea una versión de todo en cada corrida: crecimiento silencioso sin techo | Agregada en las tres reglas: 30 días en `raw/`, 15 en el resto |
| 6 | *(ausente)* `AbortIncompleteMultipartUpload` | Las subidas fallidas dejan partes facturables **invisibles en la consola** | Se paga por datos que nadie puede ver ni listar sin la API | Agregada: 7 días en las tres reglas |

**Cuatro de los seis defectos son omisiones, no errores.** El JSON generado es correcto en lo que
dice; el problema es lo que no dice. Es el modo de falla característico de la generación asistida:
produce lo que se pidió y calla lo que había que saber para pedirlo bien. Revisar sólo lo escrito
habría dejado pasar los cuatro.

### 3.3 La política corregida

Archivo completo en [`lifecycle-revisada.json`](lifecycle-revisada.json). La lógica por zona:

| Zona | Transición | Versiones viejas | Expiración |
|---|---|---|---|
| `raw/` | → Glacier IR a los **90 días** | 30 días | ❌ **nunca** — es la copia irremplazable |
| `processed/` | → Standard-IA a los **60 días** | 15 días | ❌ no (regenerable, pero barato de conservar) |
| `curated/` | **ninguna** — se consulta siempre | 15 días | ❌ no |

Las tres reglas incluyen `AbortIncompleteMultipartUpload` a 7 días.

**El criterio detrás:** enfriar en proporción inversa a la frecuencia de consulta, y **no borrar
nunca lo que no se puede regenerar**. `processed/` y `curated/` se reconstruyen desde `raw/` con
el ETL; `raw/` no se reconstruye desde ningún lado.

### 3.4 Aplicación

```bash
aws s3api put-bucket-versioning \
    --bucket <bucket> --versioning-configuration Status=Enabled

aws s3api put-bucket-lifecycle-configuration \
    --bucket <bucket> --lifecycle-configuration file://lifecycle-revisada.json

# verificación
aws s3api get-bucket-lifecycle-configuration --bucket <bucket>
```

> ✅ **Aplicado el 08/09** sobre `datalake-aerolinea-936980625651`, junto con el versionado y el
> bloqueo de acceso público 4/4. La respuesta de AWS está en la §1; evidencia completa en
> el anexo *Evidencia — Sesión de AWS del 08/09* (adjunto).
>
> **Y la política resultó aún mejor calibrada de lo previsto:** los objetos reales del data lake
> pesan entre 3,0 y 81,4 KiB — **ninguno llega a 128 KB**. Con el default de AWS, la regla de
> transición de `processed/` no moverá nada hasta que el volumen crezca, que es exactamente lo
> que corresponde.

---

## 4. Decisiones

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Una regla por zona | una regla global | Las tres zonas tienen valor y frecuencia de acceso distintos; tratarlas igual es lo que rompía el borrador |
| `raw/` no expira nunca | expirar al año, como propuso la IA | Es la única copia que permite corregir un error de procesamiento. Borrarla convierte un bug en pérdida definitiva |
| Glacier **IR** y no Flexible | Flexible, más barato | $0,0004/GB-mes de diferencia no compensa perder la lectura directa |
| Documentar que **el ahorro es medio centavo** | justificar la política por ahorro | Es falso a esta escala. Lo que la justifica son la higiene de versiones y la disciplina que sí escala |

---

## 5. Qué generó la IA y qué corregí

Toda la sección 3 **es** esa revisión. En síntesis:

| # | Qué propuso | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Política de una sola regla para todo el bucket | Tres reglas con `Filter.Prefix` | Sin filtro, archivaba los datos que Athena consulta |
| 2 | `Expiration: 365` | Eliminada de `raw/` | Borrado irreversible de la única copia fiel |
| 3 | `GLACIER` | `GLACIER_IR`, y sólo donde Athena no lee | Glacier Flexible rompe las consultas sin restauración previa |
| 4 | Nada sobre versiones no vigentes ni multipart | Ambas reglas agregadas | Son las dos que **sí** ahorran a nuestra escala |
| 5 | Justificar la política por ahorro de costo | Rehacer el cálculo y **mostrar que no ahorra** | El número real es medio centavo al mes; sostener lo contrario sería no haber hecho la cuenta |
