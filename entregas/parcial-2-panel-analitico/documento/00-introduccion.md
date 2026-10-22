# Introducción: el sistema y la trazabilidad

## Qué se construyó

El sistema de reservas del primer parcial, ahora completo y medido. Tiene tres caminos:

1. **Transaccional.** Los clientes buscan vuelos y reservan; la base no vende un asiento dos veces
   aunque 50 personas pidan el último a la vez. Una API FastAPI y PostgreSQL, en una EC2.
2. **Batch.** Dos años de historial (≈ 2,1 millones de reservas en CSV, sucias a propósito) se limpian
   con un job de **PySpark en EMR** que aplica las reglas C1–C5 y escribe Parquet particionado por
   mes en S3.
3. **Analítico.** Las dos tablas resultantes se registran en el **Glue Data Catalog** y se consultan
   con **Athena**; el panel de gerencia muestra la ocupación de una ruta en un mes leyendo de Athena.

El enunciado fija que lo más barato que cumpla es lo mejor. Por eso cada pieza es la versión mínima
que pasa su requisito, y cada una se midió en AWS contra el harness del profesor.

**Semilla asignada: 12345** (individual). Determina el dataset, el valor K de la prueba de
concurrencia (K = 3) y todas las respuestas esperadas.

## Resultado

| Aspecto | Valor |
|---|---|
| Harness del profesor contra lo desplegado (18/10/2026) | **70,0 / 70,0** · 23 tests en 34 s, una sola corrida |
| Datos | 2.087.701 reservas crudas → **2.017.079 curadas**, idénticas fila por fila a las del oráculo |
| Costo real del parcial en AWS | menos de US$1 (dos corridas de EMR, la EC2 y Athena) |
| Proyección mensual 24/7 | US$8,36 declarados (lo que mide el harness) + US$4,29 de EBS e IPv4 = **US$12,65 reales** |

## Matriz de trazabilidad

Cada requisito, la pieza que lo cumple, dónde está y la medición del harness que lo prueba
(`evidencia/harness-2026-10-18/report.md`).

| Req | Pts | Cómo se cumple | Dónde | Medición |
|---|---|---|---|---|
| R1 · búsqueda p95 ≤ 1 s | 4 | Índice `(route, flight_date)`; endpoint síncrono con pool de conexiones | `app/main.py`, `app/schema.sql` | p95 **0,080 s** con 20 clientes |
| R2 · sin sobreventa | 10 | `UPDATE … WHERE seats_available > 0` y la reserva en la misma transacción; `CHECK` como segunda red; pool que espera | `app/main.py` (`reservar`) | 1 de 50 y 3 de 50 (K = 3), 5 rondas cada uno, sin 5xx |
| R3 · consultar reserva | 3 | `reservation_id` como texto (un id inválido da 404, no 422) | `app/main.py` | 200 y 404 correctos |
| R4 · job EMR → Parquet | 8 | PySpark con C1–C5, corrido como **step** de un clúster transitorio | `spark/curar_reservas.py`, `infra/02-job-emr.sh` | 2.017.079 filas; **24/24** archivos escritos dentro del step |
| R5 · tablas en Glue | 6 | DDL de Athena; `reservations_curated` con partition projection; métricas sin particionar | `sql/tablas_athena.sql` | Columnas, orden y formato según contrato |
| R6 · Athena correcto y podado | 8 | Parquet + partición por mes; un archivo por mes | `spark/curar_reservas.py` | Top-10 = oráculo; un mes escanea **280.837 B** (tope 1.827.162) |
| R7 · endpoint desde Athena | 8 | Consulta parametrizada a Athena en cada pedido | `app/main.py` (`ocupacion`) | 5 rutas/mes correctas en ~0,93–1,06 s |
| R8 · flujo del cliente | 6 | HTML + JS servido por FastAPI con los `data-testid` del contrato | `app/static/index.html` | Reserva creada desde Chromium |
| R9 · panel = endpoint | 4 | El panel llama al endpoint y muestra 2 decimales | `app/static/manager.html` | 0,8359 = 0,8359 = 0,8359 |
| R10 · EMR acotado | 5 | `--auto-terminate`: el clúster muere al terminar el step | `infra/02-job-emr.sh` | 0 clústeres activos; 48 h normalizadas de 150 |
| R11 · simple y barato | 4 | `t3.micro`, `m4.large`, sin NAT ni balanceador, 5 servicios | `infra/04-ec2-app.sh` | 6 servicios contados (Lambda viene de la cuenta del lab) |
| R12 · proyección de costos | 4 | `cost_projection.yaml` coherente con lo desplegado | `cost_projection.yaml` | Dentro del tope y de la tolerancia (§5.7 y §6.3) |

## Dónde está cada cosa

El código, los scripts y la evidencia están en el repositorio, carpeta
`entregas/parcial-2-panel-analitico/`. Las rutas que cita el documento son relativas a esa carpeta.

| Carpeta | Contenido |
|---|---|
| `app/` | Backend FastAPI, esquema de PostgreSQL y las dos páginas del frontend |
| `spark/` | El job de PySpark (`curar_reservas.py`) |
| `sql/` | DDL de las dos tablas para Athena / Glue |
| `infra/` | Scripts de CloudShell: bucket, job de EMR, tablas, EC2 y auditoría de baja |
| `local/` | Pruebas en la laptop: el job contra el oráculo y el harness contra el backend local |
| `harness/` | El harness del profesor, **sin modificar**, más `config.yaml` |
| `evidencia/` | El `report.md` final del harness y cómo se obtuvo |
| `cost_projection.yaml` · `docker-compose.yml` | Proyección de costos y la composición que corre en la EC2 |
