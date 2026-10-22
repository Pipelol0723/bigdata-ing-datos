# Anexo B — Qué se toca si cambia algo

El enunciado (§8) anticipa que en la defensa se puede pedir un cambio en vivo —otra regla de
limpieza, otra agregación— y preguntar qué partes del sistema, de los datos y de los tests se ven
afectadas. El diseño apunta a que cada cambio toque **un solo lugar**: las reglas C1–C5 son funciones
separadas (`c1_normalizar_ruta` … `c5_sin_duplicados`), las métricas se calculan en una sola función
(`tabla_metricas`) y el endpoint sólo lee la tabla agregada.

| Cambio pedido | Código | Datos | Tests del harness | Costo / tiempo |
|---|---|---|---|---|
| **Otra regla de limpieza** (p. ej. aceptar `PENDING`, o quedarse con la *última* aparición en C5) | Una función en `spark/curar_reservas.py` (`c3_estados_validos` o el orden de `c5_sin_duplicados`) | Volver a correr el job: reescribe `curated/` completo | R4, R6, R7, R9 dejan de coincidir con el oráculo, que tiene las reglas fijas; R5 no cambia | 1 corrida de EMR: ~10 min, ~US$0,26 |
| **Las canceladas también ocupan asiento** | Una línea de `tabla_metricas` (`seats_sold`) | Re-correr el job | R6, R7, R9 (cambia la ocupación) | 1 corrida de EMR |
| **`bookings` = confirmadas + canceladas** | Ya existe: `--bookings-incluye-canceladas` | Re-correr el job | Ninguno: el harness no la mira | 1 corrida de EMR |
| **Otra agregación** (por semana, o por clase tarifaria) | `tabla_metricas` (nueva clave), `sql/tablas_athena.sql` (columna nueva), la consulta del endpoint y los campos del panel | Re-correr el job y recrear la tabla de métricas (DDL, gratis) | R5 (columnas del contrato), R6, R7, R9 | 1 corrida de EMR + 3 archivos |
| **Más meses de historia** (2025) | Ampliar `projection.month.range` en el DDL | Generar y subir los crudos; re-correr el job | R4/R5 esperan exactamente 24 particiones | DDL + 1 corrida |
| **Datos ×10** | Ninguno; quizá un core más (`infra/02-job-emr.sh`) | Re-correr el job | Ninguno | Corrida ~2× más larga; el panel cuesta lo mismo (lee la tabla agregada) |
| **Permitir sobreventa controlada** (vender 105 % de la capacidad) | `crear_vuelo`: `seats_available = floor(capacity × factor)`; ajustar el `CHECK` | Ninguno (los vuelos nuevos) | R2 espera exactamente K: con factor > 1 falla, que es lo correcto si la regla cambió | Cambio en la API + rebuild de la imagen |
| **Base gestionada** (pasar a RDS) | Sólo `DATABASE_URL`; sacar el servicio `db` del compose | Migrar con `pg_dump` / `pg_restore` | R11: RDS sólo `db.t3/t4g micro/small`, sin Multi-AZ; R12 suma ~US$12,41/mes | ~US$14,70/mes más |
| **Que el panel no espere a Athena** | Caché por (ruta, mes) en `ocupacion`, vencida al correr el job | Ninguno | R7 la permite si el primer pedido va a Athena | Código del endpoint |

**Regla general para responder en vivo:** primero ubicar en qué capa vive el cambio (transaccional,
batch o analítica), después qué tabla del contrato cambia, y recién ahí qué tests del harness lo van a
notar. Un cambio de reglas de negocio en el batch nunca toca la base transaccional ni el frontend del
cliente.
