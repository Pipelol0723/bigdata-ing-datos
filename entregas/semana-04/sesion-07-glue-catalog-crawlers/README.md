# Session 7 — AWS Glue Data Catalog y Crawlers

**Curso:** Big Data e Ingeniería de Datos (PCIA 5010) · Semana 4 · Sesión 7
**Tema:** el catálogo como desacople de cómputo y metadatos · **gobernanza alcanzable sin Lake Formation**
**Caso:** data lake del sistema de reservas (`entregas/parcial-1-aerolinea/`)

---

## 1. El catálogo como desacople de cómputo y metadatos

Sin catálogo, cada motor de consulta necesita que le declaren el esquema. La misma tabla se
define una vez para Athena, otra para Spark en EMR, otra para el job de Glue — y las tres
definiciones se desincronizan apenas alguien agrega una columna.

El **Glue Data Catalog** guarda una sola vez, por tabla: dónde están los archivos, en qué formato,
con qué columnas y tipos, y cómo está particionada.

```
                       ┌──────────────┐
        S3 (Parquet) ──│ Data Catalog │──┬── Athena
                       │  esquema,    │  ├── Glue ETL Job
                       │  ubicación,  │  ├── EMR / Spark
                       │  particiones │  └── Redshift Spectrum
                       └──────────────┘
```

**Qué habilita concretamente el desacople:**

| | Sin catálogo | Con catálogo |
|---|---|---|
| Cambiar de motor | redefinir esquemas en el motor nuevo | apunta al mismo catálogo y funciona |
| Dos motores a la vez | dos definiciones que divergen | una definición, dos lectores |
| Agregar una columna | actualizar cada motor | se actualiza una vez |
| Saber qué datos hay | mirar S3 y adivinar | consultar el catálogo |

Es el mismo principio que separar esquema de aplicación en una base relacional, aplicado a
archivos: **los datos dejan de ser archivos y pasan a ser tablas**, sin moverlos.

---

## 2. Crawlers

Un crawler recorre una ruta —de S3 o por JDBC—, infiere el esquema y crea o actualiza las tablas
del catálogo. Detecta columnas, tipos y particiones.

### Cuándo usarlo y cuándo no

| Situación | Crawler | Por qué |
|---|---|---|
| Descubrimiento inicial de una fuente desconocida | ✅ | es exactamente su trabajo |
| Fuente que cambia de esquema sin aviso | ✅ | detecta la deriva |
| Tablas propias con esquema estable y conocido | ❌ | conviene declararlas o dejar que el job actualice el catálogo |
| Particiones nuevas cada día | ❌ | **partition projection** de Athena las deduce sin ejecutar nada |

⚠️ **El crawler cobra por ejecución** (~$0,10–0,15). Dejarlo **On demand**, nunca con schedule:
programado cada hora son **~$3,50 por día** catalogando una base que no cambia. Sobre un
presupuesto de 50 USD, eso es el 7 % diario por no cambiar un desplegable.

---

## 3. Las cuatro trampas, verificadas en clase

Cuatro errores que costaron tiempo real conectando Glue a RDS. Los tres primeros fallan **sin
decir por qué**.

| # | Síntoma | Causa | Solución |
|---|---|---|---|
| 1 | La conexión no valida | URL JDBC mal formada | Va con **dos puntos** y **puerto explícito**: `jdbc:postgresql://host:5432/base` — no `jdbc.postgresql` ni sin `:5432` |
| 2 | La conexión falla sin explicación | El SG de Glue no se referencia a sí mismo | Glue levanta **varios workers que hablan entre ellos**. Hace falta una **regla auto-referenciada**: todo el tráfico con origen el propio grupo |
| 3 | El crawler queda colgado y da **timeout** | Los workers corren dentro de la VPC **sin IP pública** y no llegan a S3 | **VPC Endpoint de S3 tipo Gateway** — es **gratis**. Un NAT Gateway resuelve lo mismo a **$0,045/h**: ~$32/mes por no saber que existía el endpoint |
| 4 | `Service is unable to assume provided role. Please verify role's TrustPolicy` | Se eligió un rol que no es `LabRole` | La cuenta tiene ~25 roles. Sólo **`LabRole`** tiene `glue.amazonaws.com` en su trust policy (verificado con `aws iam get-role`) |

> La #3 es la más cara de las cuatro: las dos soluciones funcionan y una cuesta $32/mes más que
> la otra. **El diagrama de la Sesión 3 dibuja S3 fuera de la VPC justamente para que este
> problema se vea antes de chocarse con él.**

---

## 4. Gobernanza alcanzable sin Lake Formation

Lake Formation agrega permisos finos sobre el catálogo. Sin él —que es el caso del Learner Lab—
la gobernanza se arma con IAM, la organización del bucket y el catálogo. **No es nada, pero
tiene un techo claro.**

### Lo que **sí** se puede

| Mecanismo | Qué logra |
|---|---|
| **Políticas IAM por recurso** sobre el catálogo | permitir `glue:GetTable` sobre una database y negarla sobre otra |
| **Separar databases** (`aerolinea_raw`, `aerolinea_curated`) | frontera de permisos: analistas al catálogo curado, ingeniería a todo |
| **Permisos por prefijo de S3** | quien consulta `curated/` no lee `raw/` |
| **Tags + ABAC** (`aws:ResourceTag`) | políticas por etiqueta en vez de por nombre; escala mejor |
| **Cifrado de los metadatos** del catálogo | protege el esquema, no sólo los datos |
| **CloudTrail** | auditoría de quién consultó qué y cuándo |

### Lo que **no** se puede

| Falta | Consecuencia práctica |
|---|---|
| **Permisos por columna** | no se puede dar acceso a `fact_tramo_vendido` ocultando el precio pagado. Es todo o nada por tabla |
| **Permisos por fila** | no se puede limitar a un analista a una sola ruta |
| **Filtros de datos** | ninguna forma declarativa de decir "sólo los vuelos de este año" |
| **Grants centralizados entre cuentas** | hay que administrar políticas IAM a mano en cada cuenta |

### El *workaround* y su costo

Sin permisos por columna, la única salida es **materializar vistas restringidas**: generar en
`curated/` una tabla sin las columnas sensibles y dar permiso sólo sobre ésa.

Funciona, y hay que ser honesto sobre lo que cuesta: **duplica datos**, agrega un paso al ETL, y
crea la posibilidad de que las dos copias se desincronicen. Es gobernanza por duplicación en
lugar de por política. **A partir de unas pocas reglas de acceso distintas, Lake Formation deja
de ser un lujo.**

⚠️ **Límite del entorno:** en el Learner Lab **no se pueden crear roles ni usuarios de IAM** —
todo corre con `LabRole`. O sea que esta sección es diseño, no implementación: la separación de
permisos se puede *diseñar* y justificar, pero no demostrar en este entorno.

---

## 5. Evidencia

| Elemento | Estado |
|---|---|
| Conexión JDBC a la base OLTP | ⏳ sesión de AWS |
| Conexión JDBC a la base OLAP | ⏳ sesión de AWS |
| Crawler ejecutado y tablas en el catálogo | ⏳ sesión de AWS |
| Consulta de Athena sobre las tablas catalogadas | ⏳ sesión de AWS |

> Los objetos de Glue de la práctica anterior con Sakila (`crawler-sakila-rds`, `sakila_catalog`
> y su conexión JDBC) apuntan a una RDS ya borrada. **Se eliminan en la misma sesión**, para que
> el catálogo del proyecto quede limpio.

---

## 6. Decisiones

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Crawler **On demand** | schedule diario u horario | Cobra por ejecución y el esquema no cambia solo. Programarlo es pagar por descubrir lo mismo |
| **VPC Endpoint Gateway** para S3 | NAT Gateway | Idéntico resultado; el endpoint es gratis y el NAT cuesta ~$32/mes |
| Databases separadas por zona | una sola database | Es la única frontera de permisos disponible sin Lake Formation. Gratis de implementar ahora, cara de agregar después |
| Documentar el techo de la gobernanza sin Lake Formation | presentarla como suficiente | La sustentación puede preguntar por permisos a nivel de columna: conviene saber de antemano que la respuesta es "no se puede, y esto es lo que costaría" |

---

## 7. Qué generó la IA y qué corregí

| # | Qué propuso el asistente | Qué corregí | Por qué |
|---|---|---|---|
| 1 | Describir el catálogo como "un inventario de metadatos" | Explicar **qué habilita el desacople**, con la tabla comparativa | La definición es correcta y no dice para qué sirve. Lo que se defiende es la consecuencia |
| 2 | Recomendar crawler programado a diario | On demand | Cobra por ejecución; a diario son ~$3,50/día por catalogar algo que no cambió |
| 3 | Presentar la gobernanza sin Lake Formation como equivalente | Agregar la tabla de **lo que no se puede** y el costo del *workaround* | Es lo que decide cuándo hace falta Lake Formation, y es la pregunta probable en la sustentación |
| 4 | Omitir que en el Learner Lab no se pueden crear roles | Marcarlo explícitamente | Sin esa aclaración, el documento promete una implementación que el entorno no permite |
