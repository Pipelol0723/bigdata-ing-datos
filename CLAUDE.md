# Contexto del proyecto: Big Data e Ingeniería de Datos (AWS Learner Lab)

## Sobre este proyecto
Materia universitaria **"Big Data e Ingeniería de Datos"**. Todo el trabajo práctico se hace en un **AWS Academy Learner Lab**, un sandbox educativo con presupuesto de **50 USD**. Cualquier script o comando que se genere acá debe asumir que corre contra ese entorno, no contra una cuenta AWS normal.

---

## 🤝 Cómo trabajamos (rol del asistente)

**Rol:** agente para *trabajar, enseñar y explicar* AWS. No sólo resolver la entrega: que quede entendido.

**Idioma:** español (rioplatense, informal). El vocabulario técnico de AWS va en inglés (bucket, crawler, cluster, etc.).

**Estilo de explicación — el porqué antes del cómo.** Antes de tirar un comando o crear un recurso:
1. **Qué es** el servicio en una línea.
2. **Por qué ese** y no la alternativa obvia (Athena vs Redshift, Glue vs EMR, Lambda vs EC2...).
3. **Qué cuesta** y a partir de qué momento empieza a cobrar.
4. **Dónde está la trampa** en este lab específico.

Después sí, los pasos. Si un tema da para más, ofrecer profundizar en vez de escribir tres pantallas de una.

**Modo de ejecución: mixto.**
- **Consola web** para lo visual y para lo que se entrega con capturas (los labs de AWS Academy suelen pedir eso). Acá el asistente guía paso a paso: menú, botón, campo, valor.
- **CloudShell** para automatizar, verificar y sobre todo para el **checklist de apagado**. El asistente escribe el script, el usuario lo pega. CloudShell ya viene con AWS CLI + boto3 y las credenciales del lab cargadas. **Es la vía por defecto**: no depende de credenciales locales ni de que estén vigentes.
- **AWS CLI local** (instalado, v2) para iterar más rápido cuando hace falta. Requiere cargar antes las credenciales temporales del lab con `scripts/cargar-credenciales.ps1`.

**Regla de seguridad innegociable:** el asistente **nunca** apaga, termina ni borra un recurso AWS por su cuenta — ni con automatización de navegador, ni con CLI. Siempre propone el comando/paso y **espera confirmación explícita**. Los scripts que genere son de **sólo lectura** por defecto; los comandos destructivos se entregan aparte, para copiar a mano.

---

## ⚠️ Reglas críticas del entorno (leer antes de tocar nada)

- **Si se excede el presupuesto, la cuenta se desactiva y se pierde TODO** — recursos y progreso, sin aviso previo.
- El presupuesto que se ve en la consola viene de AWS Budgets y **se actualiza cada 8-12 horas**: siempre está atrasado respecto al gasto real. No tratarlo como un número exacto en tiempo real.
- El entorno es **persistente entre sesiones** (los recursos se mantienen), pero con comportamientos irregulares:
  - Las instancias **EC2 detenidas se REINICIAN solas** al abrir la siguiente sesión → principal fuente de gasto silencioso. **Para EC2, detener no alcanza: hay que terminar.**
  - Los notebooks de **SageMaker se detienen pero NO se reinician** solos.
  - Las apps de **SageMaker Canvas siguen corriendo** hasta que se borran a mano.
  - Un clúster de **EMR no sobrevive** al fin de sesión (no se puede "detener", queda inutilizable) → escribir siempre los resultados a S3 antes de cerrar la sesión.
  - Una instancia **RDS puede quedar corriendo** al cerrar sesión, y si se la deja detenida 7 días, AWS la reinicia sola.
- El link **Reset** borra todo lo creado, pero **no reinicia el presupuesto**.
- Regiones habilitadas: **solo us-east-1 y us-west-2**. Cualquier otra región da error de acceso.

## 🔑 Credenciales y acceso

- La sesión del lab dura unas **~4 horas** (mirar el contador arriba en el panel del lab). Al vencerse, las credenciales dejan de servir aunque los recursos sigan vivos y **cobrando**.
- El botón **AWS Details → AWS CLI** muestra las credenciales temporales (`aws_access_key_id`, `aws_secret_access_key`, **`aws_session_token`**). Son de corta duración: **nunca** hardcodearlas en un script ni guardarlas en un archivo del repo.
- **CloudShell** ya tiene esas credenciales inyectadas → es la vía por defecto para cualquier CLI. No hace falta `aws configure`.
- Para usar el **AWS CLI local**: copiar el bloque de `AWS Details → AWS CLI` y correr `.\scripts\cargar-credenciales.ps1`. Las carga como variables de entorno **sólo en esa terminal**; al cerrarla desaparecen. **No usar `aws configure`**: deja las claves en texto plano en `~/.aws/credentials`, dentro del perfil de usuario que además se sincroniza a OneDrive.
- En scripts para CloudShell conviene arrancar con `export AWS_PAGER=""` para que la salida no quede atrapada en el pager.

⚠️ **Trampa de PowerShell 5.1:** al invocar ejecutables nativos (`ssh.exe`, `aws.exe`) **se come las comillas dobles internas** de los argumentos. Un `ssh host 'cmd -H "Header: x"'` llega al destino con el header roto, y el error resultante no lo delata. Para comandos remotos con comillas anidadas, usar **Git Bash**, no PowerShell.

## 💻 Entorno local (ya instalado)

| Herramienta | Dónde / cómo |
|---|---|
| AWS CLI v2 | `C:\Program Files\Amazon\AWSCLIV2\aws.exe` (ya en el PATH) |
| Python 3.11 + venv | `C:\Users\pipel\venvs\bigdata` — **a propósito fuera de OneDrive**: un venv son miles de archivos chicos y sincronizarlos es lento e inútil |
| Paquetes | `duckdb`, `pyarrow`, `pandas`, `boto3`, `awswrangler`, `ipykernel` |
| VS Code | + AWS Toolkit, Python, Jupyter |
| Git + GitHub CLI | repo privado `Pipelol0723/bigdata-ing-datos` |

**Regla de oro para cuidar el presupuesto — desarrollar local, ejecutar en AWS:**
- Athena cobra **$5 por TB escaneado**. Depurar el SQL con **DuckDB** sobre los mismos Parquet cuesta **$0**; recién cuando la query funciona, correrla en Athena.
- Convertir CSV → **Parquet con `pyarrow` localmente** antes de subir a S3: baja el costo de Athena uno o dos órdenes de magnitud.
- Un error de sintaxis o un `SELECT *` de prueba no deberían costar plata.

Activar el venv: `C:\Users\pipel\venvs\bigdata\Scripts\Activate.ps1`

---

## 🔔 Recordatorio permanente

**Al final de cualquier actividad, tarea, proyecto o quiz: apagar/terminar los recursos AWS que hayan quedado corriendo** (EC2, RDS, EMR, Redshift, SageMaker, etc.) para cuidar el presupuesto. El asistente debe *ofrecerlo activamente* al cerrar cualquier trabajo, sin esperar a que se lo pidan. Si se usa automatización de navegador o CLI para apagar algo, **preguntar siempre antes de hacerlo** — nunca apagar recursos sin confirmación explícita del usuario.

### Checklist de INICIO de sesión
1. Abrir el lab y esperar el semáforo verde.
2. Anotar el presupuesto que muestra (recordando que está atrasado 8-12 h).
3. Correr `scripts/auditar-recursos.sh` en CloudShell → ver qué quedó vivo de la sesión anterior.
4. **Terminar los zombies antes de empezar** (sobre todo EC2, que se reinician solas).

### Checklist de CIERRE de sesión
1. **Escribir resultados a S3** — sobre todo si se usó EMR, que muere con la sesión.
2. Correr `scripts/auditar-recursos.sh` de nuevo.
3. Dar de baja en este orden (de más caro a menos): Redshift → EMR → RDS → EC2 → SageMaker (notebooks y apps de Canvas) → NAT Gateways → Elastic IPs sueltas → volúmenes EBS sin adjuntar.
4. Si se levantó todo con CloudFormation: `delete-stack` y listo, se va todo junto.
5. Verificar con **Resource Groups & Tag Editor** en las dos regiones.
6. S3 se puede dejar (centavos), pero borrar datasets grandes si ya no se usan.

---

## 💸 Costos de referencia

> Precios **aproximados** de us-east-1, on-demand, para tener orden de magnitud. Verificar en la [Pricing Calculator](https://calculator.aws) antes de comprometerse con algo caro.

| Recurso | Precio aprox. | Cobra cuando… |
|---|---|---|
| EC2 `t3.micro` | $0.0104 /h | está *running* |
| EC2 `t3.medium` | $0.0416 /h | está *running* |
| EC2 `m5.large` | $0.096 /h | está *running* |
| EBS `gp3` | $0.08 /GB-mes | el volumen existe (aunque la instancia esté detenida) |
| Elastic IP sin asociar | $0.005 /h | no está adjunta a nada |
| NAT Gateway | $0.045 /h + $0.045 /GB | existe |
| S3 Standard | $0.023 /GB-mes | hay objetos guardados |
| Athena | $5.00 /TB escaneado | corrés una query (particionar y usar Parquet baja esto muchísimo) |
| Glue ETL | $0.44 /DPU-hora | el job corre |
| Lambda | $0.20 /1M requests + $0.0000167 /GB-s | se invoca |
| DynamoDB on-demand | $1.25 /1M writes, $0.25 /1M reads | hay tráfico |
| Kinesis Data Streams | $0.015 /shard-hora | el stream existe |
| RDS `db.t3.micro` | ~$0.017 /h | la instancia existe (aun detenida cobra storage) |
| EMR | precio de las EC2 + recargo EMR (~25%) | el clúster está vivo |
| SageMaker notebook `ml.t3.medium` | ~$0.05 /h | está *InService* |
| Redshift `ra3.large` | ~$0.54 /h por nodo | el clúster existe, **aunque esté inactivo** |

### Por qué esto importa (con 50 USD)
- Un **Redshift de 2 nodos** (~$1.09/h) olvidado un fin de semana largo quema **el presupuesto entero en ~46 horas**.
- Un **EMR de 3 × m4.large** olvidado 24 h ≈ **$9**, casi el 20% del presupuesto.
- Una **t3.micro** olvidada un mes ≈ **$7.5** — poco por hora, letal por acumulación.
- El patrón peligroso no es el recurso caro, es el **recurso barato olvidado que se reinicia solo**.

---

## Límites técnicos por servicio

**IAM** — muy restringido. No se pueden crear usuarios ni roles nuevos. Usar siempre el rol preexistente **LabRole** (y el instance profile **LabInstanceProfile** para EC2).

**EC2**
- Tamaños permitidos: nano, micro, small, medium, large — solo On-Demand.
- Máximo 9 instancias concurrentes y 32 vCPU en total.
- ⚠️ 20+ instancias concurrentes = desactivación inmediata de la cuenta.
- Key pair: **vockey** (disponible en us-east-1).

**EBS** — máximo 100 GB, tipos gp2/gp3/sc1/standard (sin PIOPS).

**EMR**
- Tamaños hasta "large" (recomendado m4.large si hay problemas al lanzar el clúster).
- No sobrevive al fin de sesión → escribir resultados a S3 antes de cerrar.

**Redshift**
- Solo tipo de nodo **ra3.large**, máximo 2 nodos (~$0.54/hora por nodo, ~$1.09/hora el clúster completo).
- Cobra aunque esté inactivo — apagar o borrar el mismo día de uso.

**Glue**
- Worker type: G.1X o Standard.
- Máximo 10 workers, concurrencia máxima 1.

**Lambda** — máximo 10 ejecuciones concurrentes.

**RDS**
- Solo instancias burstable: nano, micro, small, medium.
- Storage gp2 hasta 100 GB.
- Sin enhanced monitoring (hay que desmarcarlo a mano al crear la instancia).

**CloudShell** — viene con AWS CLI y boto3 preconfigurados y con las credenciales del lab ya cargadas. Es la forma más rápida de correr scripts sin instalar nada localmente.

## Servicios disponibles para la materia
S3, Athena, Glue, Glue DataBrew, Kinesis, DynamoDB, EMR, Redshift, Step Functions, EventBridge, SageMaker, CloudFormation, Lambda, RDS, EC2.

---

## Buenas prácticas recomendadas
- Preferir **CloudFormation** para levantar entornos: al terminar, borrar el stack completo (elimina todo junto, sin dejar recursos sueltos cobrando) y recrearlo con el mismo template en la próxima sesión.
- Usar **Resource Groups & Tag Editor** (regiones us-east-1 y us-west-2, "All supported resource types") para encontrar recursos olvidados entre sesiones.
- **Taggear todo** con `Proyecto=bigdata` y `Unidad=<n>` desde el momento de crearlo: es la única forma barata de auditar después.
- Cualquier script debe asumir que corre en **CloudShell** o una terminal con las credenciales del Learner Lab ya configuradas — no asumir un IAM user propio.
- Priorizar servicios serverless / pago-por-uso (S3, Athena, Glue, Lambda) para las prácticas del día a día, y reservar EMR/Redshift/RDS para las sesiones puntuales donde son estrictamente necesarios.
- En S3: **Parquet + particionado** por defecto. Baja el costo de Athena en uno o dos órdenes de magnitud y es lo que se espera en la materia.
- Trabajar en **us-east-1** salvo que haya una razón concreta para no hacerlo: menos recursos dispersos = menos olvidos.

---

## 📁 Estructura del repo

```
bigdata e ing de datos/          ← repo git, sincronizado a OneDrive
├── CLAUDE.md                    ← este archivo (se carga solo en cada sesión)
├── .gitignore                   ← bloquea credenciales, .pem, .env y datasets
├── .gitattributes               ← fuerza LF en .sh (si no, fallan en CloudShell)
├── scripts/
│   ├── auditar-recursos.sh      ← sólo lectura: qué tengo prendido y cobrando
│   └── cargar-credenciales.ps1  ← credenciales del lab en memoria, no en disco
├── cloudformation/              ← templates .yaml (forma preferida de levantar entornos)
├── notas/                       ← apuntes y explicaciones de cada tema
└── entregas/                    ← trabajos prácticos por unidad
```

### Respaldo (3 capas)
1. **OneDrive** — sincroniza solo, pero *sync ≠ backup*: si borrás algo, se propaga. Cubre 30 días de papelera.
2. **Git local** — historial real, permite volver atrás.
3. **GitHub privado** — `Pipelol0723/bigdata-ing-datos`. Sobrevive a perder la PC.

⚠️ **Nunca commitear credenciales de AWS.** El `.gitignore` las bloquea, pero la regla es no escribirlas en ningún archivo del repo. GitHub escanea claves y las revoca automáticamente.

💡 Lo que de verdad hay que preservar no son los scripts (se regeneran) sino **este `CLAUDE.md` y la carpeta `notas/`**: son el contexto acumulado que permite retomar el trabajo en una sesión nueva sin volver a explicar todo. Commitear seguido.

---

## 📌 Bitácora del curso

### 💰 Control de presupuesto

| Fecha | Consumido | Nota |
|---|---|---|
| 2026-08-25 | **$3.20 / $50** | ~19 días de curso · ~$0.17/día promedio · no incluye la clase de ese día (~$1 más) |
| 2026-09-01 | **$4.90 / $50** | ~26 días de curso · ~$0.19/día promedio · $1.70 en la semana, de los cuales ~$0.77 fue storage de recursos que nadie usó |
| 2026-10-09 | **$18.80 / $50** | ~64 días de curso · **$13.90 desde el 01/09**: ~$2,70 fue el trabajo del parcial y **~$11 (estimado) las RDS y la EC2 olvidadas** del 10/09 al 21/09. Quedan **$31,20** |

Ritmo actual: **sano**. Con Cloud9 y `db-service` dados de baja el 01/09, el piso diario baja de ~$0.11 a **casi cero** entre clases.

🔴 **La lección del 01/09 → 09/10:** el olvido costó **unas 4 veces lo que costó todo el trabajo del
parcial**. La baja estaba escrita en esta bitácora, con fecha, y aun así se pasó 11 días. Desde
ahora: **la baja se hace en la misma sesión en que termina el uso**, nunca "después de".

💡 **La lección de la semana 25/08 → 01/09:** de $1.70 consumidos, ~$0.77 fue *storage idle*. Parece nada, pero proyectado a fin de semestre son ~$11 — el **22% del saldo restante** — por almacenar una base con Sakila que ya no se iba a tocar. **El gasto peligroso no es el pico, es el piso.**

⚠️ **El margen es para lo que viene, no para gastarlo ahora.** Con el saldo restante: EMR de 3 nodos dura ~5 días; Redshift de 2 nodos, **menos de 2**. Un Redshift olvidado un fin de semana (~$78) supera el presupuesto entero.

*(Mantener actualizado: es lo que le da contexto al asistente al abrir una sesión nueva.)*

- ✅ **(13/10): Taller Taxis NYC entregado.** Notebook corrido de nuevo en un clúster nuevo (`j-0504795HQHEQRH1YLXQ`, mismos números que el ensayo) y subido a Moodle (*CC-IA-02: Taxis workshop*, "Enviado para calificar" 10:12) junto con `entrega/Taller-Taxis-NYC-respuestas.pdf` (se regenera con `entrega/construir_pdf.py`). Clúster **terminado a pedido del alumno** tras 1 h 1 min (~$0,40). Falta: **End Lab** (lo hace el alumno) y, **después de la corrección**, la baja del bucket, el Studio y Glue.
- 📋 **(09/10): Taller Taxis NYC (EMR + PySpark), planificado.** Enunciado y plan en `entregas/semana-08/taller-taxis-nyc-emr/PLAN.md`. Dataset medido sin descargarlo: **102.871.387 viajes en 12 Parquet (1,46 GB)**, con tipos que cambian a mitad de año (`passenger_count`, `RatecodeID`) y fechas fuera de 2018 en los 12 meses. **Entrega: martes 13/10, mostrando el clúster corriendo, en persona, en clase y desde la consola de AWS** → se levanta de nuevo ese día (no sobrevive entre sesiones del lab). Decisiones tomadas el 09/10 (referencia con Athena sobre los crudos · tope de duración por percentiles · sin zonas 264/265 · se guarda 2018 entero · notebook en EMR Studio o, si el lab no lo deja, en SageMaker). **✅ Ensayo general completo el 10/10:** los 14 pasos en AWS, con el notebook en EMR Studio, y Athena, el notebook y el programa dan los mismos números (`evidencia/sesion-2026-10-10.md`). Costó ≈ $0,85. **Falta sólo la demo del martes**: guion con tiempos medidos en `PLAN.md` (empezar 1 h 30 antes de la clase).
- ✅ **(21/09): Parcial 1 cerrado — cuenta limpia para el nuevo corte.** Se entregó y defendió el 10/09; el 21/09 se dio de baja toda su infraestructura (ver *Cuenta limpia al 21/09* más abajo). Enunciado, documento final y evidencia quedan en `entregas/parcial-1-aerolinea/`.

### 📊 Avance del parcial al 06/09

| Sección | Peso | Estado |
|---|---|---|
| 0 · Contexto y supuestos | — | ✅ redactada (9 supuestos) |
| 5.1 · Requisitos funcionales | 10 % | ✅ redactada (19 `FR-`) |
| 5.2 · Requisitos no funcionales | 10 % | ✅ redactada (10 `NFR-`, 7 `RSK-`) |
| 5.3 · Modelo ER | 15 % | ✅ redactada (14 entidades + diagrama Crow's Foot) |
| 5.4 · Arquitectura backend | 15 % | ✅ decisiones cerradas (8 `DEC-`) |
| 5.5 · Arquitectura frontend | (en el 15 %) | ✅ redactada |
| 5.6 · Implementación backend | 10 % | ✅ **implementada y probada** |
| 5.7 · AWS ETL/catálogo/costos | **20 %** | ✅ **desplegado y verificado en AWS (08/09)** · 2 desviaciones declaradas |
| §4 · Prompt log | obligatorio | ✅ 23 entradas |

📄 **Documento final consolidado (10/09):** `entregas/parcial-1-aerolinea/entrega/Parcial1-Sistema-Reservas-Aerolinea.pdf`
(52 páginas), generado con `entrega/construir_documento.py --autor "..."` desde `documento/`.
**Regenerarlo después de tocar cualquier sección.** Falta poner el nombre del alumno en la portada.

⚠️ **Dos desviaciones declaradas en la 5.7 (reescrita el 10/09 para que diga lo que se hizo):**
1. El ETL OLTP → OLAP corre en la **EC2**, no en Glue (el diseño sigue apuntando a Glue Spark a escala).
2. Las dos bases están en el Glue Data Catalog **a través de sus copias en S3** (3 crawlers, uno por
   zona); **no se corrió un crawler JDBC directo** sobre las RDS. Cerrarlo costaría ~$0,25 y 5 min
   con las bases encendidas. Decisión del alumno: no gastar y declararlo.
Proyección de costos actualizada: **≈ $33,08/mes**, RDS = **93 %**; gasto real del parcial **≈ $2,70**.

### ✅ Sesión de AWS ejecutada — 08/09

**Las 8 secciones están completas.** Lo único que queda antes del jueves es **ensayar la defensa**.
Evidencia íntegra en `entregas/parcial-1-aerolinea/evidencia/aws/sesion-2026-09-08.md`.

Resultados medidos en AWS: los `.sql` escritos contra PostgreSQL 16 corrieron **sin un cambio**
contra **PostgreSQL 18.3** en RDS · invariante de sobreventa **0 violaciones** · ETL **141
dimensiones + 9.121 hechos en 1,64 s** (en local dio 8.821: el generador es aleatorio) ·
data lake con 13 objetos Parquet · **8 tablas** catalogadas con particiones `year`/`month`
detectadas solas · Athena consultó 8.893 filas escaneando **4.614 bytes**. Costo real: **~$0,25**.

Tres hallazgos que sólo aparecieron en AWS:
1. AWS devuelve `TransitionDefaultMinimumObjectSize: all_storage_classes_128K` — **no transiciona
   objetos < 128 KB**, confirmando el análisis de costos de la Sesión 6 desde el propio servicio.
2. Los 8.893 hechos cayeron en **2 particiones**, no 60: el ADR #1 acertó el cálculo.
3. **La ventana de bootstrap.** Las RDS son privadas, pero CloudShell corre fuera de la VPC y no
   podía cargar los `.sql`. Se abrió el 5432 a **una sola IP** (la de CloudShell), se cargó, y se
   **revocó en la misma sesión** dejando una única regla: 5432 desde el SG de Glue, sin CIDR.
   Decisión del alumno, documentada para la defensa.

### 🔁 Segunda pasada del 08/09 — las zonas `raw/` y `processed/`

Al releer lo entregado apareció un hueco: **el data lake tenía tres zonas y sólo `curated/` con
datos**, mientras el diagrama del Checkpoint 1 afirmaba el flujo completo. Se corrigió con un
**job de Glue dentro de la VPC** (`job-raw-processed`, SUCCEEDED en 149 s), que era además la
única forma de extraer del OLTP **sin reabrir la ventana**, ya cerrada.

Dos decisiones del job que conviene poder defender:
- `processed/` se construye **releyendo `raw/` desde S3**, no consultando la base. Es lo que
  vuelve real la promesa de reversibilidad de la zona cruda.
- **El tipado es la transformación** entre las dos zonas: al releer el CSV todo vuelve como texto
  y el job le devuelve el esquema de PostgreSQL. Responde solo *"¿qué aporta `processed/`?"*.

**Mediciones nuevas:** las 17 tablas ocupan **2.915.371 bytes en CSV** y **941.399 en Parquet**
(3,1× menos). Y la misma consulta con Athena escaneó **586.285 bytes contra `raw/`** y **2.335
contra `processed/`** — **251× menos, misma respuesta**. El CSV escanea lo mismo sin importar qué
se le pregunte: siempre lee todo.

Total de las dos pasadas: **~$0,64**.

**Todo el pipeline está funcionando en local** con dos PostgreSQL 16 en Docker (`docker-compose.yml`, puertos **15432/15433** — el 5432 y el 5433 están ocupados por los PostgreSQL nativos 13/17/18 que ya tenía la máquina). Reconstrucción completa desde cero verificada reproducible.

**Resultados verificados que sostienen el documento:**
- Prueba de concurrencia: **sin lock → 4 reservas sobre 1 asiento** (con el contador diciendo "1"); **con lock → exactamente 1 de 30**, 29 rechazos `409` explícitos. Evidencia en `evidencia/concurrencia/`.
- ETL: 141 filas de dimensiones + 8.821 de hechos en ~3,3 s.
- Las tres vistas de negocio de `FR-19` responden con datos interpretables (`evidencia/olap/`).

✅ ~~Plan de AWS de una sola sesión~~ — **ejecutado el 08/09 y reprobado el 10/09**; la evidencia quedó en `evidencia/aws/` (no en `evidencia/glue/`, que está vacía).

✅ ~~Objetos de Glue huérfanos de la práctica de Sakila~~ — borrados el 21/09, junto con el SG `glue-sakila`.

- **Cuenta AWS vacía (01/09):** se dieron de baja Cloud9 y la RDS `db-service`. **No queda ningún recurso cobrando cómputo.** El parcial arranca con infraestructura nueva.
- **Trabajo anterior, ya entregado:** EC2 + Apache (`entregas/ec2-apache/`) con FastAPI como reverse proxy (`scripts/instalar-fastapi.sh`), Sakila en RDS, MySQL local en Cloud9 y Glue conectado a la RDS.
- 🎤 **Cómo se evalúa la defensa (dato del 01/09):** el día de la sustentación el profesor plantea un cambio, mejora o problema y hay que proponer la solución **en el momento**, según cómo esté construido el sistema. No hay nada extra que implementar, pero cambia el criterio: lo que se mide es **si el diseño absorbe un cambio no previsto**. Por eso cada decisión se documenta junto a su alternativa descartada, y las reglas de negocio se modelan como **políticas parametrizables** (`capacidad_vendible = f(capacidad_física, política_comercial)`) en vez de invariantes rígidos.
- ⚠️ **Pendiente de confirmar con el profesor:** lo anterior describe la **§7** del enunciado (defensa oral, igual para todos los equipos). La **§3** es otra cosa: una restricción confidencial por equipo que debe integrarse **por escrito** en el documento. Puede que en este caso sean lo mismo, o puede que la §3 siga faltando — y la rúbrica de requisitos funcionales la premia explícitamente.

### 🔒 CERRADO — el túnel SSH de DBeaver

**Por qué se cierra:** el 01/09 se dieron de baja Cloud9 y la RDS `db-service`. El instructivo paso a paso (abrir el 22, `authorized_keys`, reconfigurar DBeaver) ya no aplica a ningún recurso existente, y los IDs que mencionaba están muertos. Se borra el procedimiento y se conserva **la lección**, que es lo único que sobrevive al recurso.

**El caso:** la conexión quedó funcionando por el camino rápido — `bind-address = 0.0.0.0`, usuario `'pipe'@'%'`, y el 3306 abierto en el Security Group a la IP del alumno. Comprobado en clase: se podía leer el banner de versión de MySQL **desde afuera, sin autenticarse**. El profesor lo dio por válido, pero había pedido SSH.

**La lección:** con un túnel SSH la base es segura **por diseño** — no escucha en una interfaz pública. Con el puerto abierto en el SG es segura **por configuración** — depende de que una regla siga siendo correcta. La primera falla cerrada, la segunda falla abierta.

⚠️ Y el motivo práctico por el que el camino rápido además es incómodo: **la IP del alumno rota** (`192.144.114.66` → `.77` en una semana) y **la IP pública de una instancia cambia en cada reinicio**. Cualquier método basado en IP exige reescribir la regla del SG cada clase.

> 📌 **Aplica directo al parcial:** si las RDS nuevas se hacen públicamente accesibles, es exactamente la misma deuda. Es una decisión a tomar y justificar en `NFR-SEG-` (sección 5.2).

### Recursos AWS

### 🟡 VIVOS al 13/10 — Taller Taxis (entregado, nada cobrando por hora)

| Recurso | Identificador | Cobra | Baja |
|---|---|---|---|
| ~~Clúster EMR (ensayo)~~ | `j-051241333LOTQJZJ6C3Y` | — | ✅ **se apagó solo** por inactividad tras 1 h 49 min (~$0,71) |
| ~~Clúster EMR (entrega)~~ | `j-0504795HQHEQRH1YLXQ` | — | ✅ **terminado** el 13/10 a pedido del alumno, tras 1 h 1 min (~$0,40) |
| Bucket | `taxis-nyc-936980625651` (3,1 GB: crudos, `viajes/`, scripts, logs, resultados, Studio) | ~$0,07/mes | después de la corrección |
| EMR Studio + Workspace | `taller-taxis` · `taller-taxis-nyc` (notebook con salidas guardado) | nada | después de la corrección |
| Glue | bases `taxis` (tabla `viajes`) y `taxis_referencia` · crawler `crawler-taxis-viajes` | por corrida | después de la corrección |
| SG de EMR | `sg-0f253f4cb96e04bca` · `sg-0bd7e2f60a8b3af61` | nada | opcional |

**Después de la corrección:** bucket, Studio, Glue y SGs. Los comandos de baja salen de
`entregas/semana-08/taller-taxis-nyc-emr/infra/05-auditar-y-baja.sh` (el bucket se borra a mano).

💡 **Lecciones del 13/10:** el *Quick launch* del Workspace falla si Chrome bloquea el pop-up (el
`window.open` llega después de una llamada asíncrona); se abre capturando la URL de lanzamiento y
abriéndola con un enlace normal · la consola de **EC2 y la de Athena dieron "Unable to load content"**
ese día: el Query editor de EMR Studio reemplaza a Athena, y el estado de los nodos se ve en EMR.

💡 **Lecciones de EMR en el lab (10/10):** entre los `large`, EMR sólo acepta `c4.large`, `m1.large`
y `m4.large` (`m5.large` → *not supported*) · EMR Studio **sí** se puede crear (Custom, IAM, `LabRole`)
· la auto-terminación por inactividad funcionó aun con un Workspace enganchado · Livy muestra las
tildes de los `print()` como "?".

### ✅ Cuenta limpia al 21/09 — fin del parcial, arranca el nuevo corte

Toda la infraestructura del parcial se dio de baja el 21/09 con
`entregas/parcial-1-aerolinea/infra/02-baja-recursos.sh`. El script sólo lee: audita e imprime
los comandos con los IDs reales, y el alumno los pegó a mano en CloudShell. Verificado: **LIMPIO**.

| Se borró | Detalle |
|---|---|
| RDS | `parcial-oltp` y `parcial-olap`, sin snapshot final |
| EC2 | `i-0154fecb40194d171` (`api-parcial`) |
| S3 | `datalake-aerolinea-936980625651`, con todas sus versiones |
| Glue | `job-raw-processed`, 4 crawlers, 3 conexiones, 4 databases (incluye los restos de Sakila) y los log groups `/aws-glue/*` |
| SSM | `/parcial/*` |
| Security Groups | `rds-parcial`, `glue-parcial`, `api-parcial`, `glue-sakila`, `launch-wizard-1` |

**Queda a propósito:** el VPC Endpoint de S3 `vpce-09b60424dc9c1f1cf` (tipo Gateway, **gratis**;
lo necesita cualquier job de Glue que corra dentro de la VPC), la VPC default y su SG `default`.

⚠️ **Las RDS quedaron vivas 11 días después de la defensa** (10/09 → 21/09). Si estuvieron
encendidas todo ese tiempo, son hasta ~$11 de más. **Anotar el presupuesto real en la próxima
sesión.** Es el patrón de siempre, el recurso barato olvidado: la baja estaba escrita acá mismo,
con fecha, y aun así se pasó. **Una baja diferida ("después de la defensa") es una baja olvidada.**

💡 **Trampa nueva: el SG `default` retiene referencias.** `glue-sakila` no se dejaba borrar
(`DependencyViolation`) porque el SG `default` tenía una regla de entrada 3306 que lo
referenciaba, de cuando la RDS de Sakila usaba el default. Hubo que revocar esa regla primero. El
script ahora imprime ese `revoke` solo.

📌 **Si el Checkpoint 2 necesita el data lake**, hay que recrearlo porque el bucket ya no existe:
`entregas/semana-04/checkpoint-1/crear-data-lake.sh`.

### ✅ Guía de ejecución en AWS probada de punta a punta — 10/09

`entregas/parcial-1-aerolinea/GUIA-EJECUCION-AWS.md` se ejecutó completa en AWS, **sin nada en la
máquina local**: EC2 por EC2 Instance Connect (22 abierto sólo al prefix list de AWS), API como
servicio systemd, ciclo reserva → pago → **pago repetido idempotente**, prueba de concurrencia
**con lock 1 de 30** y **sin lock 2 reservas vivas con el contador en 1** (actualización perdida),
ETL desde la EC2, job de Glue y Athena (**586.285 bytes en CSV vs 2.339 en Parquet**).
Evidencia en `evidencia/aws/sesion-2026-09-10.md`.

**Tres bugs que sólo aparecieron en AWS, corregidos y reprobados:** la prueba de concurrencia
apuntaba al Docker local; la prueba intentaba borrar reservas pagadas (la FK de `pago` las
protege a propósito: los registros financieros no se borran en cascada); y el job de Glue
duplicaba `processed/` en la segunda corrida.

⚠️ **Trampa de CloudShell:** subir un archivo con el mismo nombre **no lo reemplaza** (*"ya existe
en el entorno y no se sobrescribirá"*). Hacer `rm` antes, y verificar la línea que cambió — no un
texto que aparece en las dos versiones.

---

**Estado al 01/09: la cuenta no tiene ningún recurso cobrando cómputo.** Todo lo de las prácticas anteriores fue dado de baja para arrancar el parcial con infraestructura nueva — decisión del alumno: reutilizar obligaba a explicar en la defensa por qué un componente venía prestado de otra práctica, y la coherencia del trabajo pesa más que ~$2 de ahorro.

| Recurso | Detalle | Estado |
|---|---|---|
| ~~EC2 `i-082829eaed67d7086`~~ | t3.micro Ubuntu 26.04 | ✅ **TERMINADA** |
| ~~Cloud9 `i-0490df2bd01dfaafe`~~ | `t3.small` · entorno `aws-cloud9-my-env-5521f907b4ed4cfba8188eaba6c1ff1a` | ✅ **BORRADO 01/09** |
| ~~RDS `db-service`~~ | `db.t4g.micro` · MySQL 8.4.9 · Sakila cargada | ✅ **BORRADA 01/09** |

✅ ~~Objetos de Glue huérfanos de Sakila~~ — borrados el 21/09.

📌 **Recursos del parcial:** dados de baja el 21/09 (ver *Cuenta limpia al 21/09*).

⚠️ **Una RDS se reinicia sola a los 7 días de detenida** — regla de AWS, no del lab — y cobra storage aunque esté detenida (~$2.30/mes por 20 GB). Para las dos del parcial la consigna es **borrarlas** después de la defensa, no detenerlas: el esquema y el script de bootstrap quedan en el repo.

**Cloud9 = una EC2 con IDE en el navegador.** Cobra como cualquier EC2. Su ventaja: **hibernación automática por inactividad** (verificar que esté en 30 min, no en "Never"). Su límite: en el Learner Lab las instancias detenidas **se reinician solas** en la sesión siguiente, así que la hibernación protege dentro de una sesión, no entre sesiones.
⚠️ AWS cerró Cloud9 a clientes nuevos en 2024. Sirve para el curso, pero no basar nada a largo plazo en él.
⚠️ El *Preview* de Cloud9 **no es una URL pública**: para que el profesor vea la app hay que abrir el puerto en el Security Group.

**Conexión a la base ya resuelta:** DBeaver instalado y conectando. MySQL Shell 26.7 instalado local (`mysqlsh`). El cliente clásico `mysql.exe` **no** está en Windows — MySQL Shell no lo incluye, viene con el paquete de MySQL Server. En Cloud9 sí está (`mysql`).

**Base cargada:** esquema **Sakila** (dataset público de MySQL) en la RDS, usuario `pipe`, motor MySQL 8.4.9. Cargado desde Cloud9 con `wget` + `unzip` + `source`.

### MySQL Server local en Cloud9 (tarea, hecha)

`scripts/instalar-mysql-server.sh` · **MySQL 8.0.46 sobre Ubuntu 22.04**, activo como servicio systemd. Sakila cargada **sin un solo error**.

**El contraste que demuestra el ejercicio:**

| | RDS `db-service` | MySQL local en Cloud9 |
|---|---|---|
| Funciones de Sakila | **0** | **3** |
| Triggers de Sakila | **0** | **6** |
| Privilegio `SUPER` | nunca | sí (sos admin) |
| Backups y parches | AWS | tu problema |

Es IaaS vs servicio gestionado en una sola captura.

💡 Cloud9 corre **Ubuntu 22.04**, no 26.04 como la EC2 vieja → **no tiene PEP 668**, así que `pip install` funciona sin `--break-system-packages`.

### Sobre los errores de Sakila (cerrado)

Al correr `sakila-schema.sql` aparecieron ~8 veces:

```
ERROR 1419: You do not have the SUPER privilege and binary logging is enabled
```

Consecuencia: **las 3 funciones y los 6 triggers de Sakila no se crearon.** Las tablas, las vistas y los datos sí entraron completos.

Causa: RDS tiene binlog siempre activo y **nunca otorga `SUPER`**, ni al usuario maestro. Sin `SUPER`, MySQL no deja crear funciones ni triggers. Es el precio concreto de usar una base gestionada.

✅ **El profesor dijo que no importa, que se deje así.** Ya no es un pendiente.

Si alguna vez hicieran falta: parameter group propio (familia `mysql8.4`) con `log_bin_trust_function_creators=1`, asociarlo a `db-service`, reiniciar la instancia y volver a correr `sakila-schema.sql`. Verificar con `SHOW FUNCTION STATUS WHERE Db='sakila';` y `SHOW TRIGGERS FROM sakila;`.

### ⚠️ Trampas de Cloud9 (aprendidas a los golpes)

- **No terminar la instancia EC2 directamente** — rompe el entorno y no se recupera. Detenerla, o borrar el entorno completo desde la consola de Cloud9.
- **Con la pestaña del IDE abierta, la instancia NO se puede detener:** Cloud9 detecta que su entorno se apaga y **la vuelve a encender sola**. Pasó: `stop-instances` devolvió `stopping` y minutos después estaba en `running` otra vez. **Hay que cerrar todas las pestañas de Cloud9 antes de detenerla.**
- Por eso el **timeout de hibernación por inactividad** no es un detalle de comodidad sino el mecanismo principal de control de costo. La API `describe-environments` **no** devuelve ese campo (comprobado): sólo se ve en la consola de Cloud9.
- ✅ **La hibernación está ACTIVA y funcionando** (confirmado 2026-08-18): al estar inactiva apareció en la terminal `Broadcast message ... The system shutdown has been cancelled`, o sea que el timer había programado el apagado y la actividad lo canceló. Es la forma empírica de verificarlo.
- ⚠️ Durante instalaciones largas (`apt-get install`), mantener la pestaña del IDE activa: si hiberna a mitad, el gestor de paquetes queda inconsistente. Se arregla con `sudo dpkg --configure -a && sudo apt-get install -f -y`.
- `managedCredentialsStatus: ENABLED_BY_OWNER` es lo que hace que el `aws` CLI funcione en Cloud9 sin configurar credenciales.

⚠️ **La RDS se reinicia sola a los 7 días de detenida** (regla de AWS, no del lab). Si no se va a usar en ese plazo: borrarla con `--final-db-snapshot-identifier`, o guardar el esquema en un `.sql` y borrarla sin snapshot.

**Pendiente cuando se retome:** la EC2 nunca llegó a conectarse a la RDS — falta la regla de entrada al **3306 en el SG de la base, con origen el SG de la EC2** (no una IP). En la consola de RDS, *Acciones → Configurar la conexión de EC2* lo hace automático.

### Notas de la instancia que se terminó (para recrearla)
- Apache en el `:80` sirviendo `/` y proxeando `/api/` a FastAPI en `127.0.0.1:8000`, como servicio systemd. Así **no hace falta abrir ningún puerto extra**.
- Ubuntu 26.04 trae **Python 3.14 con PEP 668**: `pip install` a secas falla. Va con venv o `pip install --user --break-system-packages`.
- Drivers que hicieron falta para MySQL: `pymysql`, `sqlalchemy`.
- ⚠️ **La IP pública cambia en cada stop/start** (pasó dos veces: `54.90.158.108` → `50.17.68.3`). Regenerar el alias SSH con `scripts/conectar-ec2.ps1 -ConfigurarVSCode`.
- El alias `ec2-bigdata` en `~/.ssh/config` quedó apuntando a una instancia que ya no existe.

**IDs para el checklist de baja:**
`instancia i-082829eaed67d7086` · `SG sg-06269c038daa2d634 (launch-wizard-1)` · `VPC vpc-099e92d8e5feb8b90` · `subnet subnet-0e44e937b437991a7`

**Acceso:** alias `ec2-bigdata` en `~/.ssh/config` → `ssh ec2-bigdata`, o VS Code Remote-SSH.
⚠️ El DNS/IP **cambia cada vez que la instancia se reinicia** → hay que reescribir el alias con `scripts/conectar-ec2.ps1 -ConfigurarVSCode`.
⚠️ Con 908 MB de RAM **no entra Spark ni un dataset mediano en pandas**. Para procesamiento real: EMR, o DuckDB local.
### 🔵 Glue conectado a la RDS (histórico — esa RDS ya no existe)

⚠️ **Los IDs de esta sección son de la práctica de Sakila y apuntan a recursos borrados el 01/09.** Se conserva por **las cuatro trampas de más abajo**, que aplican igual a las conexiones PostgreSQL del parcial y son horas de trabajo ya pagadas. Los objetos de Glue y el SG `glue-sakila` se borraron el 21/09; de esta tabla sólo sigue vivo el VPC Endpoint.

| Recurso | ID / nombre |
|---|---|
| Conexión JDBC | `Jdbc connection` → `jdbc:mysql://db-service.cvbllouimnrr.us-east-1.rds.amazonaws.com:3306/sakila` |
| SG de Glue | `sg-0a705241afac09be5` (con **regla auto-referenciada**, obligatoria) |
| VPC Endpoint S3 | `vpce-09b60424dc9c1f1cf` — tipo **Gateway, gratis** |
| Database del catálogo | `sakila_catalog` |
| Crawler | `crawler-sakila-rds`, `Include path = sakila/%` |
| VPC / Subnet | `vpc-099e92d8e5feb8b90` / `subnet-0e44e937b437991a7` (us-east-1a) |
| Cuenta | `936980625651` → rol `arn:aws:iam::936980625651:role/LabRole` |

**Las cuatro trampas que costaron tiempo, para no repetirlas:**

1. **La URL JDBC va con dos puntos**, no punto: `jdbc:mysql://…`, y **con el puerto** `:3306`.
2. **El SG de Glue necesita una regla auto-referenciada** (todo el tráfico con origen el propio grupo). Sin eso la conexión falla sin explicar por qué.
3. **Sin VPC Endpoint de S3, el crawler da timeout**: los workers corren dentro de la VPC sin IP pública. El endpoint Gateway es **gratis**; el NAT Gateway resuelve lo mismo a **$0.045/h** — no usarlo.
4. **`Service is unable to assume provided role`** = se eligió un rol que no es `LabRole`. Hay ~25 roles en la cuenta y es fácil errarle; `LabRole` sí tiene `glue.amazonaws.com` en su trust policy (verificado).

⚠️ **El crawler cobra por ejecución** (~$0.10-0.15). Dejarlo **On demand**, nunca con schedule: programado cada hora son ~$3.50/día catalogando una base que no cambia.

⚠️ **Athena todavía no puede consultar estas tablas.** El catálogo apunta a una conexión JDBC, y Athena lee de S3. Falta el paso siguiente: un **ETL job** que escriba Parquet a S3.

```
RDS ──crawler──▶ Catálogo ──ETL job──▶ S3 (Parquet) ──▶ Athena
                  (acá estamos)
```

