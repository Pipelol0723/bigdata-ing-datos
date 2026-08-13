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

*(Mantener actualizado: es lo que le da contexto al asistente al abrir una sesión nueva.)*

- **Estado actual:** EC2 + Apache **entregado** (`entregas/ec2-apache/`). Se montó FastAPI detrás de Apache como reverse proxy — receta en `scripts/instalar-fastapi.sh`. **La EC2 ya fue terminada.** Próximo tema: app web + versión móvil (responsive/PWA), con RDS MySQL como base.
- **Última auditoría:** cierre de sesión hecho a mano; falta correr `auditar-recursos.sh` al abrir la próxima.

### Recursos AWS

| Recurso | Detalle | Costo | Estado |
|---|---|---|---|
| ~~EC2 `i-082829eaed67d7086`~~ | t3.micro Ubuntu 26.04 | — | ✅ **TERMINADA** |
| **Cloud9 `i-0490df2bd01dfaafe`** | `t3.small` (2 vCPU / 2 GB) · entorno `aws-cloud9-my-env-5521f907b4ed4cfba8188eaba6c1ff1a` | **~$0.0208/h** (el doble que una micro) | ▶️ **RUNNING** |
| RDS `db-service` | `db.t4g.micro` · MySQL · 1 AZ · `db-service.cvbllouimnrr.us-east-1.rds.amazonaws.com:3306` · **públicamente accesible**, 3306 abierto a la IP del alumno | ~$0.016/h encendida · **~$2.30/mes de storage aunque esté detenida** | ▶️ **RUNNING** |

**Quema combinada con todo prendido: ~$0.90–1.00 por día.**

**Cloud9 = una EC2 con IDE en el navegador.** Cobra como cualquier EC2. Su ventaja: **hibernación automática por inactividad** (verificar que esté en 30 min, no en "Never"). Su límite: en el Learner Lab las instancias detenidas **se reinician solas** en la sesión siguiente, así que la hibernación protege dentro de una sesión, no entre sesiones.
⚠️ AWS cerró Cloud9 a clientes nuevos en 2024. Sirve para el curso, pero no basar nada a largo plazo en él.
⚠️ El *Preview* de Cloud9 **no es una URL pública**: para que el profesor vea la app hay que abrir el puerto en el Security Group.

**Conexión a la base ya resuelta:** DBeaver instalado y conectando. MySQL Shell 26.7 instalado local (`mysqlsh`). El cliente clásico `mysql.exe` **no** está — MySQL Shell no lo incluye, viene con el paquete de MySQL Server.

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
