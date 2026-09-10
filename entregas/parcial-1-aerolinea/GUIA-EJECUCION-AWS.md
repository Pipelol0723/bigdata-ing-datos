# Guía de ejecución en AWS — Sistema de reservas de la aerolínea

**Parcial 1 · Big Data e Ingeniería de Datos (PCIA 5010)**
**Cuenta:** `936980625651` · **Región:** us-east-1 · **Todo corre en AWS: nada en la máquina local.**

---

## 0. Cómo leer esta guía

Tres partes, según para qué la abras:

| Si necesitás… | Andá a |
|---|---|
| **Levantar la aplicación** | §4 — paso a paso |
| **Abrir una pieza puntual** (la base, la API, el ETL…) | §5 — cada componente por separado |
| **Entender por qué es así** | §2 — qué se hizo y por qué |
| **Mostrarlo en la defensa** | §6 — guion con tiempos |

### Qué está verificado y qué no

Cada paso lleva la marca de si **ya se ejecutó en AWS**:

| Marca | Significa |
|---|---|
| ✅ | Ejecutado y verificado en AWS. Evidencia en `evidencia/aws/sesion-2026-09-08.md` y `sesion-2026-09-10.md` |

> ✅ **La guía completa se ejecutó en AWS el 10/09**, de punta a punta y sin nada en la máquina
> local. Probarla encontró **tres bugs que en local nunca se habían manifestado** — los tres están
> corregidos y vueltos a probar (§7, filas 9, 12 y 13).
>
> **Lo único no ejecutado, a propósito:** exponer `/docs` a internet (§5.3, opcional), la baja de
> recursos (§8) y la carga desde cero (Anexo A), que **borraría los datos**.

---

## 1. Mapa del sistema

```
                        ┌──────────────────── VPC (us-east-1) ─────────────────────┐
                        │                                                           │
  Consola / CloudShell  │   EC2 api-parcial ──5432──▶ RDS parcial-oltp (OLTP)       │
  (tu navegador)        │   · API FastAPI              17 tablas, esquema reservas  │
        │               │   · ETL OLTP→OLAP     ──5432──▶ RDS parcial-olap (OLAP)   │
        │ EC2 Instance  │   · prueba concurrencia        estrella, esquema dw       │
        └─ Connect ────▶│                                                           │
                        │   Glue job-raw-processed ──JDBC──▶ parcial-oltp           │
                        │          │                                                │
                        └──────────┼── VPC Endpoint S3 (gratis) ───────────────────┘
                                   ▼
                  S3 datalake-aerolinea-936980625651
                     raw/ (CSV) → processed/ (Parquet) → curated/ (estrella)
                                   │
                          Glue Data Catalog (3 databases, 42 tablas)
                                   │
                                Athena
```

| # | Componente | Qué hace | Dónde vive | Código |
|---|---|---|---|---|
| 1 | **Base transaccional** | registra reservas, garantiza que no se venda de más | RDS `parcial-oltp` | `db/oltp/*.sql` |
| 2 | **Base analítica** | responde las 3 preguntas de negocio | RDS `parcial-olap` | `db/olap/01-esquema-estrella.sql` |
| 3 | **Backend** | API REST: buscar, reservar, pagar | EC2 `api-parcial` | `api/main.py` |
| 4 | **Lógica de negocio** | el bloqueo optimista, las políticas | EC2 `api-parcial` | `api/repositorio.py`, `api/config.py` |
| 5 | **ETL OLTP→OLAP** | transforma a esquema estrella | EC2 `api-parcial` | `etl/etl_oltp_a_olap.py` |
| 6 | **Extracción al lago** | OLTP → `raw/` → `processed/` | job de Glue | `etl/job_glue_raw_processed.py` |
| 7 | **Exportación curated** | OLAP → `curated/` | EC2 `api-parcial` | `etl/exportar_curated.py` |
| 8 | **Data lake** | tres zonas en S3 | bucket `datalake-aerolinea-936980625651` | — |
| 9 | **Catálogo** | convierte archivos en tablas | Glue Data Catalog | — |
| 10 | **Consulta** | SQL sobre el lago | Athena | — |

---

## 2. Qué se hizo y por qué

Cada decisión con su alternativa descartada. Es lo que hay que poder sostener en la defensa.

### Dos bases, no una

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| RDS OLTP **y** RDS OLAP separadas | una sola base para todo | Son dos consumidores opuestos. El OLTP responde *"¿queda un asiento?"* miles de veces por minuto; el OLAP responde *"¿cómo evolucionó la ocupación?"* unas veces por día. Juntos, **un reporte pesado puede frenar la venta de pasajes** |
| OLTP en **3NF** (17 tablas) | desnormalizado | Cada hecho vive en un solo lugar, así que no puede quedar contradicho |
| OLAP en **estrella** con **dos tablas de hechos** | una sola tabla de hechos | Hay dos granos legítimos —el tramo vendido y la ocupación del vuelo— y forzarlos a uno destruye información |

### Las bases son privadas

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| RDS con `--no-publicly-accessible` | base accesible desde internet | Con la base privada, la seguridad es **por diseño**: no escucha en una interfaz pública. Abierta y protegida por una regla, es segura **por configuración** — depende de que la regla siga siendo correcta. La primera falla cerrada; la segunda, abierta |
| El SG de la base acepta **por grupo** (`sg-…` de Glue y de la EC2) | reglas por IP | Las IPs cambian: la del alumno rotó en una semana y la de una instancia cambia en cada reinicio. **La pertenencia a un grupo no cambia** |

**Consecuencia directa:** todo lo que habla con la base tiene que correr **dentro de la VPC**.
CloudShell corre afuera. Por eso:

| Qué | Dónde corre | Por qué ahí |
|---|---|---|
| API, ETL, prueba de concurrencia, `psql` | **EC2 `api-parcial`** | es el "adentro" de la VPC para lo que no es Glue |
| Extracción al data lake | **job de Glue** | Glue corre en la VPC usando la conexión JDBC |
| Crear recursos, S3, Athena, Glue | **CloudShell** | no tocan la base directamente |

> **El 08/09 todavía no existía la EC2.** Para cargar los `.sql` se abrió una **ventana
> temporal**: el 5432 a **una sola IP** (la de CloudShell), se cargó y se **revocó en la misma
> sesión**. Con la EC2, esa ventana deja de hacer falta: la carga se hace desde adentro.

### Credenciales

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Contraseña generada **dentro de CloudShell** con `openssl rand` | elegirla a mano | Nunca se imprimió ni se escribió en el repo |
| Guardada en **SSM Parameter Store** como `SecureString` | pasarla en el user-data o en el código | La EC2 la lee con su rol. No viaja por ningún lado donde quede a la vista |
| El código lee la conexión de **variables de entorno** | conexión escrita en el código | El mismo archivo corre contra cualquier base sin editarse. Así el ETL apuntó a RDS el 08/09 sin tocar una línea |

### El data lake

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| Tres zonas: `raw/`, `processed/`, `curated/` | escribir directo el modelo final | `raw/` es la copia fiel. Si la limpieza tiene un bug, **se reprocesa desde ahí** sin volver a la base, que ya cambió |
| `processed/` se construye **releyendo `raw/`** desde S3 | volver a consultar la base | Si no, `raw/` sería decorativa y el argumento de reversibilidad se caería |
| **Parquet** en `processed/` y `curated/` | CSV | Medido: la misma consulta escaneó **586.285 bytes en CSV y 2.335 en Parquet** — 251× menos |
| Particionado por **fecha de vuelo, mensual** (ADR #1) | diario, o por fecha de reserva | Las tres consultas filtran por fecha de vuelo. A 294 filas/día, la partición diaria da archivos de 15 KB. **Umbral de revisión: 128 MB por partición** |
| Catálogo en **3 databases**, una por zona | una sola database | Sin Lake Formation, separar databases es **la única frontera de permisos** disponible |

### La lógica de negocio

| Decisión | Alternativa descartada | Por qué |
|---|---|---|
| **Bloqueo optimista** con columna `version` y `UPDATE` condicional | bloqueo pesimista (`SELECT … FOR UPDATE`) | No retiene filas mientras el usuario piensa. La condición `comprometidos + 1 <= vendible` va **en el mismo `UPDATE`**: leer, decidir y escribir es una sola operación atómica |
| Además, un `CHECK` en la tabla | confiar sólo en el código | Dos capas: si el código falla, la base rechaza. **El `CHECK` encontró un bug en el generador de datos demo** |
| La sobreventa como **política** (`politica_capacidad.factor_sobreventa`) | un invariante fijo | Un cambio comercial —*"ahora se permite overbooking del 5 %"*— entra como configuración, no como rediseño |

### El costo

| Recurso | Cobra | Estado |
|---|---|---|
| 2 × RDS db.t3.micro | ~$0,86/día entre ambas, **aunque estén detenidas** | ⚠️ borrar hoy, después de la defensa |
| EC2 t3.micro | ~$0,25/día | ⚠️ terminar hoy |
| S3 (3,8 MB) | centavos al mes | queda: lo usa el resto del curso |
| Glue / Athena | sólo cuando corren | — |

**Costo real de las sesiones del 08/09: ~$0,64.** Se desarrolló todo primero en local, a costo
cero, y se subió a AWS una vez funcionando.

---

## 3. Antes de empezar (cada sesión)

1. **AWS Academy → Learner Lab → Start Lab.** Esperar el semáforo **verde**.
2. Botón **AWS** → abre la consola en **us-east-1**.
3. Abrir **CloudShell** (ícono `>_` arriba a la derecha).
4. Cargar las variables que dejó la sesión anterior:

```bash
source ~/env.sh && echo "BUCKET=$BUCKET  VPC=$VPC  SG_DB=$SG_DB"
```

> ⚠️ **La sesión del lab dura ~4 horas.** Al vencerse, la consola sigue abierta pero **sin
> permisos**: aparece *"No tiene permisos para obtener una lista de los buckets"* y CloudShell no
> puede crear el entorno. No es un error de configuración — hay que volver a **Start Lab**.
> Los recursos siguen existiendo y **siguen cobrando**.

---

## 4. Paso a paso: levantar la aplicación

### Estado actual (10/09)

**Existe y está cargado todo**, incluida la EC2 de la aplicación (`i-0154fecb40194d171`, creada el
10/09). Si la EC2 ya está corriendo, saltar al paso 5. Si se borró, los pasos 3 a 5 la recrean
en unos 5 minutos.

Para una instalación **desde cero** (cuenta vacía), ver el Anexo A al final.

---

### Paso 1 — Verificar el estado ✅

En **CloudShell**:

```bash
source ~/env.sh
aws rds describe-db-instances --query 'DBInstances[].[DBInstanceIdentifier,DBInstanceStatus,PubliclyAccessible]' --output text
aws s3 ls s3://$BUCKET/
```

Esperado: `parcial-oltp` y `parcial-olap` en `available` y `False`; en el bucket, `raw/`,
`processed/`, `curated/` y `athena-results/`.

---

### Paso 2 — Subir el código a CloudShell ✅

1. En **GitHub** → repositorio `Pipelol0723/bigdata-ing-datos` → botón **Code → Download ZIP**.
2. En **CloudShell** → **Acciones → Cargar archivo** → elegir el ZIP.
3. Descomprimir:

```bash
cd ~ && unzip -q -o bigdata-ing-datos-main.zip && mv -f bigdata-ing-datos-main repo
ls ~/repo/entregas/parcial-1-aerolinea
```

> Por qué desde GitHub: es la fuente de verdad. Lo que se ejecuta en AWS es exactamente lo que
> está versionado, y cualquiera puede repetir el procedimiento sin depender de una máquina.

---

### Paso 3 — Crear la EC2 de la aplicación ✅

En **CloudShell**:

```bash
bash ~/repo/entregas/parcial-1-aerolinea/infra/03-crear-ec2-api.sh
```

El script ([`infra/03-crear-ec2-api.sh`](infra/03-crear-ec2-api.sh)) crea:

| Qué | Por qué así |
|---|---|
| SG `api-parcial` con el **22 abierto sólo al servicio EC2 Instance Connect** (prefix list de AWS) | se entra por el navegador sin abrir el 22 a internet ni tener claves en la máquina |
| Regla en el SG de las bases: **5432 desde `api-parcial`** | la base acepta a la API por grupo, no por IP |
| Parámetros `/parcial/*` en **SSM Parameter Store** — la contraseña como `SecureString` | la EC2 los lee con su rol; la contraseña no viaja en ningún archivo |
| Instancia **t3.micro · Amazon Linux 2023 · `LabInstanceProfile`** | el perfil es el único disponible en el lab y le da acceso a S3 y SSM |
| Sube el código a `s3://…/app/` | la instancia lo baja de ahí: S3 es el artefacto, la instancia es descartable |

Termina con `LISTO — instancia i-…` y las instrucciones para entrar.

---

### Paso 4 — Instalar y levantar la API en la EC2 ✅

1. **Consola EC2 → Instancias → `api-parcial` → Conectar** → pestaña **EC2 Instance Connect**
   → **Conectar**. Se abre una terminal **dentro de la instancia**, en el navegador.
2. Ahí adentro:

```bash
export AWS_DEFAULT_REGION=us-east-1
B=$(aws ssm get-parameter --name /parcial/bucket --query Parameter.Value --output text)
aws s3 cp s3://$B/app/infra/04-instalar-en-ec2.sh . && bash 04-instalar-en-ec2.sh
```

El script ([`infra/04-instalar-en-ec2.sh`](infra/04-instalar-en-ec2.sh)) instala Python 3.11 y
el cliente de PostgreSQL, baja el código de S3, arma el entorno virtual, arma `~/aerolinea.env`
con las conexiones leídas de SSM (`chmod 600`), **prueba que las dos bases respondan antes de
levantar nada**, y deja la API como servicio `systemd`.

> ⚠️ La API escucha **sólo en `127.0.0.1:8010`**. No queda expuesta a internet; se prueba desde
> la misma terminal. Para abrirla en el navegador ver §5.3, *"Si piden ver /docs"*.

---

### Paso 5 — Verificar que la aplicación responde ✅

En la terminal de la **EC2**:

```bash
cd /opt/aerolinea && . .venv/bin/activate && set -a && . ~/aerolinea.env && set +a
curl -s http://127.0.0.1:8010/salud
```

Esperado:

```json
{"estado":"ok","modo_inventario":"seguro","max_reintentos":3}
```

`modo_inventario: seguro` significa que el **bloqueo optimista está activo**. Si dijera
`inseguro`, la API está en el modo de demostración que reproduce la sobreventa.

**La aplicación está corriendo en AWS.** Todo lo que sigue abre cada pieza por separado.

---

## 5. Cómo abrir cada componente por separado

> **Convención:** los bloques marcados **[EC2]** van en la terminal de la EC2 (Consola EC2 →
> `api-parcial` → Conectar → EC2 Instance Connect), con el entorno cargado:
>
> ```bash
> cd /opt/aerolinea && . .venv/bin/activate && set -a && . ~/aerolinea.env && set +a
> ```
>
> Los marcados **[CloudShell]** van en CloudShell, con `source ~/env.sh`.

---

### 5.1 Base transaccional (OLTP) — RDS `parcial-oltp`

**Qué es:** la base donde se registran las reservas. PostgreSQL 18.3, 17 tablas en el esquema
`reservas`, normalizada.

**Verla en la consola:** **RDS → Bases de datos → `parcial-oltp`**
- *Conectividad y seguridad:* endpoint, puerto 5432, **"Accesible públicamente: No"**, y el SG
  `rds-parcial`.
- *Supervisión:* CPU, conexiones, IOPS.

**Abrirla con SQL — [EC2]:**

```bash
psql "$DSN_OLTP"
```

Consultas útiles adentro de `psql`:

```sql
\dt reservas.*                                   -- las 17 tablas
\d reservas.instancia_vuelo                      -- columna version y los CHECK de sobreventa
SELECT estado, count(*) FROM reservas.reserva GROUP BY estado ORDER BY 2 DESC;
SELECT * FROM reservas.politica_capacidad;       -- la sobreventa como política
-- el invariante: debe dar 0
SELECT count(*) AS violaciones FROM reservas.instancia_vuelo
 WHERE asientos_comprometidos_eco > capacidad_vendible_eco
    OR asientos_comprometidos_bus > capacidad_vendible_bus;
\q
```

> ⚠️ **Por qué no desde CloudShell:** la base es privada y CloudShell corre fuera de la VPC. La
> conexión da *timeout*, no *"acceso denegado"* — el paquete ni siquiera llega.

---

### 5.2 Base analítica (OLAP) — RDS `parcial-olap`

**Qué es:** el destino del ETL. Esquema estrella en `dw`: 6 dimensiones, 2 tablas de hechos, 3
vistas de negocio.

**Abrirla — [EC2]:**

```bash
psql "$DSN_OLAP"
```

```sql
\dt dw.*
SELECT * FROM dw.v_ocupacion_por_ruta   LIMIT 5;   -- ¿qué rutas se llenan?
SELECT * FROM dw.v_ingresos_por_tarifa  LIMIT 5;   -- ¿la tarifa captura disposición a pagar?
SELECT * FROM dw.v_patrones_cancelacion LIMIT 5;   -- ¿cuánta sobreventa tolera cada ruta?
SELECT * FROM dw.etl_ejecucion ORDER BY 1 DESC LIMIT 3;   -- historial de corridas del ETL
\q
```

---

### 5.3 Backend — la API FastAPI

**Qué es:** la API REST del sistema. Corre en la EC2 como servicio `aerolinea`.

| Archivo en la EC2 | Qué tiene |
|---|---|
| `/opt/aerolinea/api/main.py` | los endpoints y el manejo de errores HTTP |
| `/opt/aerolinea/api/repositorio.py` | la lógica de negocio (§5.4) |
| `/opt/aerolinea/api/config.py` | las políticas parametrizables |

**Controlar el servicio — [EC2]:**

```bash
sudo systemctl status aerolinea          # ¿está corriendo?
journalctl -u aerolinea -n 30            # últimas 30 líneas del log
journalctl -u aerolinea -f               # log en vivo (Ctrl+C para salir)
sudo systemctl restart aerolinea         # reiniciar
```

**Probar los endpoints — [EC2]:**

```bash
# salud
curl -s localhost:8010/salud; echo

# qué fechas tienen vuelos (la demo cubre 30 días desde la carga)
psql "$DSN_OLTP" -tAc "SELECT min(fecha_operacion), max(fecha_operacion)
                       FROM reservas.instancia_vuelo WHERE fecha_operacion >= current_date"

# buscar vuelos — cambiar la fecha por una del rango anterior.
# Algunos días dan 0: la ruta no opera todos los días (dias_operacion). No es un error.
curl -s "localhost:8010/vuelos?origen=BOG&destino=MDE&fecha=2026-09-20" | python -m json.tool

# reservar: tomar un pasajero y una instancia reales
P=$(psql "$DSN_OLTP" -tAc "SELECT id_pasajero FROM reservas.pasajero LIMIT 1")
I=$(psql "$DSN_OLTP" -tAc "SELECT id_instancia FROM reservas.instancia_vuelo
                           WHERE fecha_operacion > current_date + 5 LIMIT 1")
curl -s -X POST localhost:8010/reservas -H 'Content-Type: application/json' \
     -d "{\"id_pasajero\": $P, \"tramos\": [{\"id_instancia\": $I, \"clase\": \"economica\"}]}" \
     | python -m json.tool
```

La respuesta trae un `codigo_reserva` de 6 caracteres. Con él:

```bash
curl -s localhost:8010/reservas/ABC123 | python -m json.tool          # consultar (FR-11)
curl -s -X POST localhost:8010/reservas/ABC123/pago \
     -H 'Content-Type: application/json' -d '{"id_transaccion_pasarela": "TX-001"}'   # pagar
```

| Código HTTP | Qué significa |
|---|---|
| `201` | reserva creada |
| `409` | **sin capacidad**: rechazo explícito, no un error genérico (`NFR-CONC-01`) |
| `503` | contención tras 3 reintentos: reintentable |
| `404` | la instancia o el pasajero no existen |

**Si piden ver `/docs` en el navegador** (opcional — expone la API mientras dure):

```bash
# [CloudShell] abrir el 8010 SÓLO a tu IP actual (buscala en https://checkip.amazonaws.com)
aws ec2 authorize-security-group-ingress --group-id $SG_APP --protocol tcp --port 8010 --cidr <TU_IP>/32
# [EC2] escuchar en todas las interfaces
sudo sed -i 's/--host 127.0.0.1/--host 0.0.0.0/' /etc/systemd/system/aerolinea.service
sudo systemctl daemon-reload && sudo systemctl restart aerolinea
```

Abrir `http://<IP pública de la EC2>:8010/docs`. **Al terminar, revertir las dos cosas** —
es el mismo patrón de ventana temporal del 08/09, y hay que cerrarla igual.

---

### 5.4 Lógica de negocio — el bloqueo optimista

**Dónde está:** `/opt/aerolinea/api/repositorio.py`, función `_comprometer_seguro` (línea 156).

**Verla — [EC2]:**

```bash
sed -n '/def _comprometer_seguro/,/return cur.rowcount/p' /opt/aerolinea/api/repositorio.py
```

**Qué hace, en tres líneas.** El `UPDATE` suma un asiento **sólo si todavía entra**: la condición
`asientos_comprometidos + 1 <= capacidad_vendible` va dentro del mismo `UPDATE`. Si dos pedidos
llegan juntos, el segundo encuentra la condición falsa y no modifica nada; `rowcount == 0` y la
API responde `409`. **Leer, decidir y escribir es una sola operación atómica** — no hay hueco
entre la lectura y la escritura donde colarse.

**Las otras piezas de la lógica:**

| Qué | Dónde | Para qué |
|---|---|---|
| Orden fijo de bloqueo | `crear_reserva`: `sorted(tramos, key=…id_instancia)` | dos reservas multi-tramo no se bloquean mutuamente (*deadlock*) |
| Expiración de retenciones | `expirar_holds` (línea 60) | un asiento retenido y no pagado se libera solo a los 30 min |
| Pago idempotente | `confirmar_pago` (línea 376) | el webhook del proveedor llega repetido: confirmar dos veces no cobra dos veces |
| Políticas | `config.py` · tabla `politica_capacidad` | minutos de retención, reintentos y sobreventa son **configuración**, no código |

---

### 5.5 La prueba de concurrencia — con lock y sin lock

**Qué demuestra:** 30 pedidos **simultáneos** sobre **1** asiento. Con el mecanismo, se confirma
exactamente 1. Sin él, se vende varias veces el mismo asiento **y el sistema no se entera**.

**Corrida B, con el mecanismo — [EC2]:**

```bash
python api/prueba_concurrencia.py --url http://127.0.0.1:8010 --peticiones 30 --etiqueta con-lock
```

Resultado verificado en AWS (10/09):

```
Instancia 229: 1 asiento(s) vendible(s), 0 comprometidos
      201 :   1   reserva creada
      409 :  29   rechazo explícito (sin cupo)
[OK] CORRECTO: exactamente 1 de 30 solicitudes prosperaron
Instancia de prueba 229 y sus reservas eliminadas.
```

> **La prueba usa una instancia de vuelo propia** (fecha 2099-12-31), no una de la demo, y **la
> borra al terminar**. No es comodidad: las instancias de la demo tienen reservas **pagadas**, y el
> esquema **no borra en cascada los registros financieros** (`pago`, `comision`) — un pago es
> auditoría. Intentar limpiarlas choca con esa regla. Para inspeccionar el estado final antes de
> que se borre: agregar `--conservar`.

**Corrida A, sin el mecanismo — [EC2].** Hay que desactivar las **dos** capas: el `CHECK` de la
base (si no, la base ataja la sobreventa y no se ve) y el lock de la API.

```bash
# 1. quitar el CHECK
psql "$DSN_OLTP" -c "ALTER TABLE reservas.instancia_vuelo DROP CONSTRAINT no_sobreventa_eco;"
# 2. poner la API en modo inseguro
sudo systemctl set-environment MODO_INSEGURO=1 && sudo systemctl restart aerolinea
curl -s localhost:8010/salud; echo                    # debe decir "inseguro"
# 3. disparar
python api/prueba_concurrencia.py --url http://127.0.0.1:8010 --peticiones 30 --etiqueta sin-lock
```

Resultado verificado en AWS (10/09):

```
      201 :   2   reserva creada
  asientos comprometidos .. 1
  reservas vivas .......... 2
  version ................. 2
[!] INCONSISTENTE: 2 respuestas 201 pero 1 comprometidos
```

**Esto es una actualización perdida, y es peor que una sobreventa visible:** dos pasajeros tienen
el mismo asiento (`reservas vivas = 2`), pero **el contador dice 1**. `version = 2` prueba que hubo
dos escrituras y que la segunda pisó a la primera. **El sistema no sabe que vendió de más.**

> El veredicto dice *INCONSISTENTE* y no *SOBREVENTA* porque compara el contador contra la
> capacidad (1 ≤ 1). La sobreventa real está en `reservas vivas`. Por eso el contador no alcanza:
> miente de forma coherente. Cuántas reservas colisionan varía entre corridas (en local fueron 4;
> en AWS, con la latencia de red de por medio, 2) — el efecto es el mismo.

**Restaurar — ⚠️ en este orden, o falla:**

```bash
# 1. API de vuelta a modo seguro
sudo systemctl unset-environment MODO_INSEGURO && sudo systemctl restart aerolinea
curl -s localhost:8010/salud; echo                    # debe decir "seguro"
# 2. la corrida B resetea la instancia (queda 1 de 1): recién ahí el CHECK entra
python api/prueba_concurrencia.py --url http://127.0.0.1:8010 --peticiones 30 --etiqueta con-lock
# 3. devolver el CHECK
psql "$DSN_OLTP" -c "ALTER TABLE reservas.instancia_vuelo ADD CONSTRAINT no_sobreventa_eco
                     CHECK (asientos_comprometidos_eco <= capacidad_vendible_eco);"
```

> **Por qué el orden:** `ADD CONSTRAINT` valida las filas existentes, y si encuentra una que lo
> viola, **se niega**. Hoy la prueba borra su instancia al terminar, así que ya no deja la fila
> inválida; igual conviene la corrida B antes del `CHECK`: confirma que la API volvió al modo
> seguro *antes* de volver a encender la segunda capa. Verificado en AWS el 10/09: después de este
> bloque, `no_sobreventa_eco` y `no_sobreventa_bus` quedan presentes.

La prueba guarda el resultado en `evidencia/concurrencia/resultado-<etiqueta>.json`. Para
conservarlo:

```bash
aws s3 cp evidencia/concurrencia/ s3://$BUCKET/evidencia/concurrencia/ --recursive
```

---

### 5.6 ETL OLTP → OLAP

**Qué es:** lee el OLTP, transforma a esquema estrella y carga el OLAP. **Recarga completa**
(`TRUNCATE` + `INSERT`): idempotente, no arrastra estado, no puede quedar a medias.

**Correrlo — [EC2]:**

```bash
python etl/etl_oltp_a_olap.py
```

Esperado (el 08/09): `OK  141 filas de dimensiones, 9121 de hechos en 1.64s`.

> Las dimensiones siempre dan 141. Los hechos pueden variar entre instalaciones: el generador
> de actividad demo es aleatorio.

**Si se corre, actualizar `curated/` y el catálogo:**

```bash
# [EC2]
python etl/exportar_curated.py
aws s3 cp ~/curated s3://$BUCKET/curated/ --recursive
# [CloudShell]
aws glue start-crawler --name crawler-datalake-aerolinea
```

---

### 5.7 Job de Glue — extracción al data lake ✅

**Qué es:** extrae las 17 tablas del OLTP **por JDBC, dentro de la VPC**, las escribe en `raw/`
como CSV, relee `raw/` desde S3 y escribe `processed/` en Parquet con los tipos restaurados.

**Verlo en la consola:** **AWS Glue → ETL jobs → `job-raw-processed`**
- pestaña *Script:* el código.
- pestaña *Runs:* cada ejecución, su duración y estado. *Output logs* abre CloudWatch.
- *Job details:* la conexión `conn-parcial-oltp`, el rol `LabRole`, Glue 4.0, G.1X × 2.

**Correrlo — [CloudShell]:**

```bash
RUN=$(aws glue start-job-run --job-name job-raw-processed --query JobRunId --output text)
aws glue get-job-run --job-name job-raw-processed --run-id $RUN --query 'JobRun.[JobRunState,ExecutionTime]' --output text
```

Esperado: `SUCCEEDED` en ~170 s. **Cuesta ~$0,15 por corrida.**

> **Se puede correr cuantas veces se quiera.** Cada corrida agrega a `raw/` una partición
> `fecha_extraccion=` —es el historial— y reescribe `processed/` sólo con la extracción nueva.
> Hasta el 10/09 no era así: `processed/` leía todas las extracciones y **duplicaba las filas** en
> la segunda corrida (medido: 17.787 filas para 8.894 reservas). Corregido y verificado.

---

### 5.8 Data lake — S3 ✅

**Verlo en la consola:** **S3 → `datalake-aerolinea-936980625651`**
- las carpetas `raw/`, `processed/`, `curated/`.
- *Propiedades:* **versionado activado**.
- *Administración:* las **3 reglas de ciclo de vida**.
- *Permisos:* **bloqueo de acceso público 4/4**.

**Desde [CloudShell]:**

```bash
for z in raw processed curated; do
  printf "%-10s " "$z/"; aws s3 ls s3://$BUCKET/$z/ --recursive --summarize | grep 'Total Size'
done
aws s3api get-bucket-lifecycle-configuration --bucket $BUCKET --query 'Rules[].ID' --output text
```

Esperado: `raw/` ~2,9 MB, `processed/` ~0,9 MB, `curated/` ~0,15 MB — lo mismo ocupa 3,1 veces
menos en Parquet que en CSV.

---

### 5.9 Catálogo — Glue Data Catalog ✅

**Verlo en la consola:** **AWS Glue → Data Catalog → Databases**

| Database | Zona | Tablas |
|---|---|---|
| `aerolinea_raw` | `raw/` | 17 |
| `aerolinea_processed` | `processed/` | 17 |
| `aerolinea_catalog` | `curated/` | 8 |

Entrar a una tabla muestra el esquema, la ubicación en S3 y —en los hechos— las **particiones
`year`/`month`, que el crawler dedujo solo** de la forma de las rutas.

**Crawlers:** **AWS Glue → Crawlers** → `crawler-raw`, `crawler-processed`,
`crawler-datalake-aerolinea`. Todos **On demand**: cobran por corrida (~$0,12) y el esquema no
cambia solo.

---

### 5.10 Athena ✅

**Abrirlo:** **Athena → Editor de consultas**.

> ⚠️ **La primera vez:** *Configuración → Administrar* → ubicación de resultados
> `s3://datalake-aerolinea-936980625651/athena-results/`. Sin esto Athena no deja ejecutar.

Elegir la database en el desplegable de la izquierda y probar:

```sql
-- en aerolinea_raw  (CSV)
SELECT estado, count(*) FROM reserva GROUP BY estado ORDER BY 2 DESC;
-- en aerolinea_processed  (Parquet): la misma consulta
SELECT estado, count(*) FROM reserva GROUP BY estado ORDER BY 2 DESC;
```

Debajo del resultado, **"Datos analizados"**: ~586 KB contra ~2,3 KB. **Ésa es la demostración
del formato**, y se ve en la pantalla sin explicar nada.

```sql
-- en aerolinea_catalog: la poda por partición
SELECT count(*), round(sum(ingreso)) FROM fact_tramo_vendido WHERE year = '2026' AND month = '09';
```

---

## 6. Guion para la defensa

Orden pensado para que **ninguna demostración dependa de la anterior**: si una falla, se sigue
con la próxima.

| # | Qué mostrar | Dónde | Tiempo | Qué decir |
|---|---|---|---|---|
| 1 | Diagrama de componentes | documento | 1 min | dos bases, privadas, todo en la VPC |
| 2 | RDS → *Accesible públicamente: No* | consola RDS | 30 s | seguridad por diseño, no por configuración |
| 3 | `curl /salud` → `"seguro"` | EC2 | 30 s | la API corre en AWS, dentro de la VPC |
| 4 | **Prueba de concurrencia con lock** | EC2 | 1 min | 30 pedidos, 1 asiento, **1 confirmada y 29 rechazos 409** |
| 5 | La función `_comprometer_seguro` | EC2 | 1 min | la condición va dentro del `UPDATE` |
| 6 | Las tres zonas del lago | consola S3 | 30 s | `raw/` hace reversible un error |
| 7 | **Athena: CSV vs Parquet** | consola Athena | 1 min | **251× menos**, misma respuesta |
| 8 | Particiones en el catálogo | consola Glue | 30 s | el ADR #1 se cumplió: 2 particiones, no 60 |

**La demostración 4 sin lock** vale la pena sólo si sobra tiempo: tiene 3 pasos de ida y 3 de
vuelta, y el orden de restauración importa (§5.5). Si se muestra, **la evidencia de la corrida
anterior ya está en el repo** (`evidencia/concurrencia/resultado-sin-lock.json`: 4 reservas sobre
1 asiento).

**Si algo se cae en vivo:**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La consola no lista nada | la sesión del lab venció | Start Lab otra vez, 2 min |
| `curl` no responde | la API se cayó | `sudo systemctl restart aerolinea` y `journalctl -u aerolinea -n 30` |
| `psql` da *timeout* | lo estás corriendo desde CloudShell | tiene que ser desde la EC2 |
| Athena no deja ejecutar | falta la ubicación de resultados | §5.10 |

---

## 7. Problemas que aparecieron y cómo se resolvieron

| # | Problema | Causa | Solución |
|---|---|---|---|
| 1 | La conexión JDBC de Glue no valida | URL mal formada | `jdbc:postgresql://host:5432/base` — con `://` y con puerto |
| 2 | La conexión falla sin explicación | el SG de Glue no se referencia a sí mismo | regla auto-referenciada: Glue levanta varios workers que hablan entre ellos |
| 3 | El crawler da *timeout* | los workers no tienen IP pública y no llegan a S3 | **VPC Endpoint de S3 tipo Gateway** — gratis. El NAT Gateway resuelve lo mismo a ~$32/mes |
| 4 | `Service is unable to assume provided role` | se eligió un rol que no es `LabRole` | usar `LabRole`: es el único con `glue.amazonaws.com` en su trust policy |
| 5 | CloudShell no alcanza las RDS | CloudShell corre fuera de la VPC | todo lo que habla con la base va en la EC2 o en Glue |
| 6 | `pip install --user` falla en CloudShell | CloudShell usa un virtualenv | `pip install` sin `--user` |
| 7 | La consola sin permisos, CloudShell no arranca | venció la sesión de 4 h del lab | Start Lab |
| 8 | La CLI de la EC2 pide región | la CLI no adivina la región desde la instancia | `export AWS_DEFAULT_REGION=us-east-1` (el script de instalación lo deja en `~/.bashrc`) |
| 9 | La prueba de concurrencia miraba otra base | la conexión estaba fija al Docker local | **corregido el 10/09**: lee `DSN_OLTP` como la API |
| 10 | Restaurar el `CHECK` después de la corrida A falla | quedan filas que lo violan | resetear la instancia primero (§5.5). **Corregido el 10/09** en la sección 5.6 |
| 11 | El data lake tenía 3 zonas y datos en 1 | la primera pasada sólo exportó `curated/` | job de Glue para `raw/` y `processed/` |
| 12 | La prueba de concurrencia falla con `ForeignKeyViolation` sobre `pago_id_reserva_fkey` | borraba reservas **pagadas** de una instancia de la demo, y el esquema protege los pagos | **corregido el 10/09**: usa una instancia dedicada y la borra al terminar |
| 13 | `processed/` con todas las filas duplicadas | el job leía todas las extracciones de `raw/` | **corregido el 10/09**: lee sólo la extracción recién escrita |
| 14 | Al subir un archivo a CloudShell con el mismo nombre, no se reemplaza | CloudShell no sobrescribe: *"ya existe en el entorno y no se sobrescribirá"* | `rm` del archivo viejo antes de subir el nuevo, y **verificar la línea que cambió**, no una que aparece en las dos versiones |

---

## 8. Baja de recursos — hoy, después de la defensa

> **Regla del proyecto:** los comandos destructivos no se automatizan. Se ejecutan a mano,
> leyéndolos.

**Primero, ver qué hay — [CloudShell]** (sólo lectura):

```bash
bash ~/repo/entregas/parcial-1-aerolinea/infra/02-baja-recursos.sh
```

**Después, en este orden — de más caro a menos:**

```bash
# 1. las bases — cobran aunque estén detenidas, y AWS las reinicia solas a los 7 días
aws rds delete-db-instance --db-instance-identifier parcial-oltp --skip-final-snapshot --delete-automated-backups
aws rds delete-db-instance --db-instance-identifier parcial-olap --skip-final-snapshot --delete-automated-backups

# 2. la EC2 — TERMINAR, no detener: detenida se reinicia sola en la próxima sesión del lab
aws ec2 terminate-instances --instance-ids $INST

# 3. los parámetros de SSM (la contraseña cifrada)
aws ssm delete-parameters --names /parcial/pg_password /parcial/ep_oltp /parcial/ep_olap /parcial/bucket
```

**No borrar:** el bucket, el catálogo, los crawlers, el job ni el VPC Endpoint. Cuestan
centavos o nada, y los necesitan el Checkpoint 2 y el resto del curso.

Los SG `rds-parcial` y `api-parcial` se pueden borrar **después** de que terminen de borrarse las
RDS y la EC2 — antes, AWS se niega porque siguen en uso.

---

## Anexo A — Instalación desde cero (cuenta vacía) ✅

Es lo que se hizo el 08/09, con una diferencia: ahora la carga de los `.sql` va desde la EC2 y
**no hace falta la ventana temporal**.

| Paso | Dónde | Comando |
|---|---|---|
| 1. SG de Glue, SG de las bases, VPC Endpoint, 2 RDS | CloudShell | `bash infra/01-crear-recursos.sh` (requiere `export PG_PASSWORD=…`) |
| 2. Guardar las variables | CloudShell | endpoints, SG, bucket en `~/env.sh` |
| 3. Bucket del data lake + lifecycle | CloudShell | `bash entregas/semana-04/checkpoint-1/crear-data-lake.sh` |
| 4. EC2 de la aplicación | CloudShell | `bash infra/03-crear-ec2-api.sh` |
| 5. Instalar en la EC2 | EC2 | `bash 04-instalar-en-ec2.sh` |
| 6. **Cargar los esquemas** | EC2 | ver abajo |
| 7. ETL + exportación curated | EC2 | §5.6 |
| 8. Conexiones JDBC + job de Glue | CloudShell | ver `evidencia/aws/sesion-2026-09-08.md` §2 y §14 |
| 9. Crawlers | CloudShell | uno por zona, **On demand** |

**Paso 6 — cargar los esquemas — [EC2]:**

> 🔴 **CUIDADO: `01-esquema.sql` empieza con `DROP SCHEMA IF EXISTS reservas CASCADE`.**
> Sobre una base con datos **los borra todos, sin preguntar.** Sólo en una base recién creada.
> **Hoy las bases ya están cargadas: NO correr esto.**

```bash
psql "$DSN_OLTP" -v ON_ERROR_STOP=1 -q -f db/oltp/01-esquema.sql
psql "$DSN_OLTP" -v ON_ERROR_STOP=1 -q -f db/oltp/02-datos-demo.sql
psql "$DSN_OLTP" -v ON_ERROR_STOP=1 -q -f db/oltp/03-actividad-demo.sql
psql "$DSN_OLAP" -v ON_ERROR_STOP=1 -q -f db/olap/01-esquema-estrella.sql
```

`-v ON_ERROR_STOP=1` hace que el primer error detenga todo, en vez de seguir y dejar la base a
medio cargar.
