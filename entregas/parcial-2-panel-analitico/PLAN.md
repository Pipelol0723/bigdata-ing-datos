# Parcial 2 — Panel analítico de la aerolínea · Plan

> Fuentes: [`enunciado.md`](enunciado.md) (convertido de `enunciado/parcial22026-2-EN.docx`) y el
> harness del profesor en [`harness/`](harness/), **copiado intacto: no se edita** (el profesor corre
> su propia copia). Plan armado el 17/10/2026.

**Qué pide, en una línea:** el sistema de reservas del parcial 1 tiene que funcionar de punta a punta
—backend, frontend, un job de PySpark en EMR que limpia 2 millones de reservas, tablas en Glue y un
panel que lee de Athena— y **un test automático lo mide contra lo que esté desplegado**. Lo más barato
que cumpla es lo mejor: lo caro o complejo no suma y puede restar (R10–R12).

| Componente | Peso | Quién lo evalúa |
|---|---|---|
| R1–R12 (harness) | **70 %** | `pytest` contra el sistema desplegado, con *probes* que el profesor cambia |
| Documento: justificaciones, Well-Architected, costos, trazabilidad | 15 % | Profesor |
| Defensa oral | 15 % | Profesor — **eliminatoria por sección: anula también los puntos del harness** |

**Dos entregas:** la *parcial* es la sección 5 en borrador (diagrama, tabla de servicios y primera
proyección de costos) **antes de construir**; la *final* es todo: documento, repo, `config.yaml`,
`cost_projection.yaml`, `report.md` y el registro de prompts.

---

## 1. Lo que el harness revela y el enunciado no dice

Leído el código de los tests (`harness/tests/`), estas son las trampas que cuestan puntos:

| # | Trampa | Requisito | Qué hacer |
|---|---|---|---|
| 1 | **Las horas de EMR de los últimos 45 días se suman todas**, incluidas las del Taller Taxis: ya hay **36 de 150** normalizadas (24 del 10/10 + 12 del 13/10). Salen de la ventana el 24/11 y el 27/11 | R10 | Cada clúster de 3 × `m4.large` gasta **12 por arranque** aunque dure 10 min (se redondea a la hora por instancia). Con 1 solo nodo, **4** |
| 2 | **El Parquet tiene que escribirse dentro de la ventana de un *step* de EMR `COMPLETED`.** Un notebook de EMR Studio (Livy) no cuenta, y subir Parquet desde la laptop tampoco | R4 | El job corre siempre como **step** (o job de EMR Serverless) |
| 3 | Bajo la ubicación de `reservations_curated` tiene que haber **exactamente 24** prefijos `month=` | R4 | Las pruebas con muestras van a **otro prefijo**, nunca debajo de la tabla real |
| 4 | **`route_month_metrics` no puede estar particionada por `month`**: si lo está, `month` sale de la lista de columnas y el orden contra el contrato falla | R5 | Tabla sin particionar (son 240 filas) |
| 5 | `GET /reservations/does-not-exist-…` tiene que dar **404**, no 422 | R3 | El `reservation_id` del path es **texto**, no `int` |
| 6 | El endpoint de ocupación arma SQL con `route` y `month` que manda el usuario | R7 | Validar con regex (`^[A-Z]{3}-[A-Z]{3}$`, `^\d{4}-\d{2}$`) o usar parámetros de Athena: **inyección SQL**, va a la defensa |
| 7 | El harness revisa el historial de Athena: tiene que haber consultas **durante** las llamadas | R7 | Caché permitida sólo si la primera llamada por (ruta, mes) va a Athena |
| 8 | R12 compara lo que **declarás** con lo que **está prendido** al momento de corregir (EC2/RDS × 730 h + todas las horas de EMR de 45 días) | R12 | Tolerancia: 25 % + US$2. El EC2 tiene que estar arriba en la ventana de corrección y la proyección tiene que describir *eso* |
| 9 | El tope de R12 es `min(1,5 × referencia del profesor, 50)`. **La referencia todavía no la publicó** (vale 60 en el archivo, a completar) | R12 | Lo más barato que cumpla. Si la referencia del profesor es chica, una arquitectura con RDS puede pasarse |
| 10 | Cuenta servicios facturables (Lambda, DynamoDB, Kinesis…) **de toda la cuenta**, no sólo del parcial | R11 | Auditar la cuenta antes de la corrección: ≤ 8 servicios |
| 11 | El panel muestra un porcentaje y se compara con tolerancia 0,001 | R9 | Mostrar **2 decimales** (`78.41%`), no 1 |
| 12 | El ejemplo de `cost_projection.yaml` dice `3 x m5.xlarge`, pero R11 sólo admite `m4.large` | R11/R12 | No copiar el ejemplo |
| 13 | La IP pública cambia en cada sesión del lab, y el profesor corre el harness desde **su** máquina | R1–R9 | Actualizar `config.yaml` antes de entregar, o Elastic IP. El puerto de la app abierto al mundo en la ventana de corrección; **la base nunca** |

**Una inconsistencia para preguntar al profesor:** el enunciado y `contract/DATA.md` dicen que
`bookings` cuenta sólo las `CONFIRMED`, pero el oráculo (`airline_data/oracle.py`) la calcula como
**confirmadas + canceladas** (verificado: `bookings == seats_sold + cancellations` en las 240 filas).
El harness no la chequea, pero la defensa puede preguntarla.

## 2. El dataset (medido con la semilla de ejemplo 12345)

Generado y medido localmente el 17/10, sin gastar nada en AWS:

| | |
|---|---|
| Archivos crudos | `reservations.csv` **84,6 MB** · `flights.csv` 0,4 MB |
| Reservas | 2.087.701 crudas → **2.017.079 curadas** (C1–C5) |
| Vuelos | 12.480, en 10 rutas × 24 meses (2023-01 a 2024-12), capacidad 180 |
| Por mes | entre 78.024 y 89.974 reservas |
| `route_month_metrics` | 240 filas |
| Verificado | aplicar C1–C5 al crudo **reproduce exactamente la verdad** del oráculo |
| Detalles | `reservations.csv` **no trae la ruta**: sale del *join* con `flights`, y C1 se aplica sobre los vuelos · `fare_class` viene en minúsculas y ninguna regla la toca · los IDs son enteros pero el contrato los quiere `string` |

Con tu semilla cambian las rutas, la capacidad, K y todas las respuestas, pero no el tamaño: es un
dataset chico. **Un solo `m4.large` lo procesa en minutos**; tres nodos sobran.

## 3. Decisiones que tomás vos

Cada una va a la sección 5 del documento con el requisito y el pilar de Well-Architected que la
justifican. La recomendación es la opción más barata que cumple; la elección es tuya.

✅ **Decididas por el alumno el 17/10:** D1 (a) una EC2 con Docker · D3 (a) EMR transitorio de 1 nodo
· D4 (a) DDL + *partition projection* · D5 (a) HTML + JS en el mismo FastAPI. **D2** se decide
midiendo R1 en F4, y **D6** al construir el endpoint en F2.

| # | Decisión | Opciones | Recomendación | Por qué (requisito · pilar) |
|---|---|---|---|---|
| D1 | **Dónde corren el backend, el frontend y la base transaccional** | (a) una EC2 con Docker: FastAPI + PostgreSQL · (b) EC2 + RDS `db.t3.micro` · (c) EC2 + SQLite | **(a)** | R1/R2 los cumple PostgreSQL en cualquier lado; RDS suma ~US$14,70/mes (instancia + 20 GB) y un servicio más. A cambio, (a) pierde los backups gestionados: se compensa con `pg_dump` a S3 · Cost Optimization vs Reliability |
| D2 | **Tamaño de la EC2** | `t3.micro` (US$7,59/mes) · `t3.small` (US$15,18/mes) | Medir R1 en `t3.micro`; subir sólo si el p95 no da | "Lo más barato que cumple", medido, no supuesto · Cost Optimization + Performance |
| D3 | **Cómo corre EMR** | (a) clúster transitorio de **1 nodo** `m4.large` con el step y `--auto-terminate` · (b) transitorio de 3 nodos, como el taller · (c) EMR Serverless, si el lab lo permite | **(a)** | Se apaga solo cuando termina el step: R10 garantizado por diseño, no por memoria. 4 horas normalizadas por corrida contra 12 · Cost Optimization + Operational Excellence |
| D4 | **Cómo se registran las tablas** | (a) DDL en Athena + *partition projection* · (b) DDL + `MSCK REPAIR` · (c) crawler de Glue | **(a)** | Sin crawler que pagar por corrida; los meses nuevos aparecen sin catalogar nada. R5 acepta *projection* explícitamente · Cost Optimization |
| D5 | **El frontend** | (a) HTML + JS servido por el mismo FastAPI · (b) SPA aparte (React/Vite) en otro puerto | **(a)** | Mismo origen: sin CORS, sin build y sin otro proceso. R8/R9 sólo piden los `data-testid` · Operational Excellence |
| D6 | **De dónde saca el panel sus números** | Athena en cada pedido · Athena + caché en memoria | Athena + caché opcional | R7 obliga a Athena; una consulta sobre 240 filas cuesta el mínimo facturable (10 MB ≈ US$0,00005). La caché sólo se justifica con ×10 consultas · Performance + Cost |

**Separación de cargas (R1/R2):** el historial **nunca entra a la base transaccional**. Vive en S3 y
sólo lo tocan EMR y Athena; la base sólo atiende reservas. Por eso un análisis pesado no puede
frenar una reserva: no comparten ni disco ni conexiones.

**Para R2** se reusa la idea del parcial 1 (exactamente 1 de 30 con lock), simplificada: un
`UPDATE flights SET seats_available = seats_available - 1 WHERE flight_id = %s AND seats_available > 0
RETURNING …` en la misma transacción que el `INSERT` de la reserva. Si no actualiza ninguna fila, es
**409**. El pool de conexiones tiene que *esperar*, no fallar, con 50 pedidos simultáneos: un 500 por
pool agotado cuesta R2 entero.

## 4. Arquitectura propuesta (con las recomendaciones)

```
                       ┌──────────────── EC2 t3.micro (LabInstanceProfile) ────────────────┐
 navegador ──HTTP:8000─┤ FastAPI: API + páginas / y /manager ──► PostgreSQL (Docker, local) │
 (cliente, gerente)    │        │ /analytics/occupancy                                       │
                       └────────┼───────────────────────────────────────────────────────────┘
                                ▼
 laptop ── generate.py ──► S3 raw/ ──► EMR transitorio (1 × m4.large, step PySpark, auto-terminate)
                                              │ C1–C5, join con vuelos, agregación
                                              ▼
                     S3 curated/reservations_curated/month=…/   S3 curated/route_month_metrics/
                                              │
                               Glue Data Catalog (DDL + partition projection) ──► Athena
```

**Servicios facturables: 5** (EC2, S3, EMR, Glue, Athena). R11 permite hasta 8.

## 5. Fases

Regla de la casa: **todo lo que se puede probar local se prueba local**. AWS es para el final de cada
fase, no para depurar.

| Fase | Qué | Dónde | Costo | Terminada cuando |
|---|---|---|---|---|
| **F0** | Decisiones D1–D6 y **entrega parcial**: diagrama, tabla de servicios y primera proyección de costos | Local | $0 | Sección 5 en borrador entregada |
| **F1** | Datos con **tu semilla** y job de PySpark: C1–C5, *join*, `month`, las dos tablas. Validar contra el oráculo (filas curadas, ingreso confirmado por mes, top-10) | Local: PySpark en modo local (Java 8 ya instalado) o DuckDB | $0 | Los números locales = los del oráculo |
| **F2** | Backend (los 6 endpoints del contrato) y frontend con los `data-testid`. Docker Compose local. Harness local para R1, R2, R3 y R8 | Local | $0 | R1–R3 y R8 en verde contra `localhost` |
| **F3** | Camino de datos en AWS, **una sesión**: bucket, subir crudos y job, EMR transitorio (1 step), DDL en Athena. Harness sólo de R4–R6 | AWS | ~US$0,20 | R4, R5 y R6 en verde |
| **F4** | Despliegue: EC2 con Docker, arranque automático al bootear (el lab la reinicia en cada sesión), `config.yaml` con la IP. Harness completo | AWS | ~US$0,10/sesión | `report.md` con R1–R12 |
| **F5** | `cost_projection.yaml` coherente con lo desplegado, documento (secciones 5 y 6), registro de prompts, `report.md` final | Local | $0 | Entrega final |
| **F6** | Defensa: ensayar cambios en vivo (otra regla de limpieza, otra agregación) y saber qué partes tocan: job, tablas, endpoint, tests | Local | $0 | Cada integrante explica cualquier parte |

**Diseño para la defensa** (el profesor puede pedir cambiar una regla o una agregación en vivo): las
reglas C1–C5 como funciones separadas y nombradas en el job, y las métricas calculadas en un solo
lugar. Cambiar una regla tiene que ser cambiar una función y volver a correr el step.

## 6. Plata

**Gasto real estimado del parcial: US$2–4** (EMR ~US$0,13 por corrida de 1 nodo; EC2 `t3.micro`
~US$0,04 por hora de sesión; Athena y S3, centavos). Saldo al 13/10: unos US$29 de US$50.

**Proyección mensual 24/7** (borrador de `cost_projection.yaml`, con D1–D6 recomendadas):

| Servicio | Detalle | US$/mes |
|---|---|---|
| EC2 | `t3.micro` 24/7 + 8 GB gp3 + IPv4 pública | ~11,90 |
| S3 | ~0,15 GB (crudos + Parquet + resultados de Athena) | ~0,01 |
| Athena | ~10.000 consultas al panel × 10 MB mínimo | ~0,50 |
| EMR | 1 corrida al mes, 1 × `m4.large`, < 1 h | ~0,13 |
| Glue | Catálogo: 2 tablas, sin crawler | 0,00 |

Total ≈ **US$12,50/mes**. Con RDS (D1-b) serían ≈ US$27. El ×10 que pide el enunciado: datos ×10 no
cambia el costo por consulta del panel (lee una tabla agregada), y consultas ×10 es donde la caché
empieza a justificarse.

⚠️ **R12 con totales chicos:** el harness estima lo vivo como EC2 × 730 h + horas de EMR × US$0,03, y
**no cuenta el EBS ni la IPv4 pública**. Con `t3.micro` estima ~US$7,60 (más ~US$1,10–1,60 de EMR
mientras las horas del taller sigan en la ventana), y la tolerancia es 25 % + US$2: declarar
US$12,50 queda **al límite** y puede fallar después del 27/11. Se resuelve en F5 con el número real
de `estimate_monthly_cost`: declarar lo honesto y, si no entra, explicarlo en el documento como pide
la sección 6 del enunciado.

## 7. Pendientes

**Datos que faltan (los tenés que conseguir vos):**
- [ ] **La semilla** asignada (cambia el dataset, K y todas las respuestas).
- [ ] ¿Individual o en equipo? El enunciado habla de equipos; el parcial 1 fue individual.
- [ ] Fechas: entrega parcial, entrega final y **ventana de corrección** (el sistema tiene que estar arriba).

**Preguntas para el profesor:**
- [ ] `bookings`: ¿sólo confirmadas, como dice el contrato, o confirmadas + canceladas, como calcula el oráculo?
- [ ] ¿Cuál es el costo de referencia de R12? Define si una arquitectura con RDS entra.
- [ ] ¿En qué idioma va el documento? El enunciado está en inglés.
