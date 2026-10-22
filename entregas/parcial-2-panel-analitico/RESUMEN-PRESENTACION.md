# Parcial 2: resumen para la presentación

> Sesión del 22/10/2026. Lab iniciado a las ~09:28 (hora de Colombia); **la sesión vence ~13:25**.
> Presupuesto según el panel del lab: **US$20,3 de 50**.

## 1. Dónde entrar (hoy)

| Qué | URL |
|---|---|
| **Página del cliente** (buscar y reservar) | **http://54.147.173.30:8000/** |
| **Panel de gerencia** (ocupación desde Athena) | **http://54.147.173.30:8000/manager** |
| **API documentada** (Swagger, se puede probar cada endpoint) | **http://54.147.173.30:8000/docs** |
| Chequeo de salud | http://54.147.173.30:8000/health → `{"status":"ok"}` |

⚠️ **La IP cambia cada vez que se abre el lab.** La EC2 (`parcial2-app`, `i-02fec020612e00ad5`) se
apaga al terminar la sesión y vuelve a prender sola en la siguiente, con otra IP. Para sacar la nueva,
en CloudShell:

```bash
aws ec2 describe-instances --filters Name=tag:Name,Values=parcial2-app --query "Reservations[].Instances[].PublicIpAddress" --output text
```

Después hay que poner esa IP en las dos `base_url` de `harness/config.yaml`. Hoy ya está hecho.

✅ **Probado hoy:** después del reinicio que hace el lab, la app volvió sola, sin tocar nada (Docker
arranca con la máquina y los contenedores tienen `restart: unless-stopped`). Era lo único que no se
había probado antes.

## 2. Qué es el sistema, en un minuto

```
                 ┌──────────── EC2 t3.micro (Docker) ─────────────┐
 Cliente  ──────►│ FastAPI ──► PostgreSQL  (vuelos y reservas)     │   camino transaccional
 Gerente  ──────►│ FastAPI ──► Athena ─┐                           │   camino analítico
                 └─────────────────────┼───────────────────────────┘
                                       ▼
 CSV sucios (2,1 M reservas) ─► EMR (PySpark, C1–C5) ─► S3 Parquet por mes ─► Glue Data Catalog
                                                                               camino batch
```

1. **Transaccional.** El cliente busca vuelos y reserva. La base no vende un asiento dos veces aunque
   50 personas pidan el último a la vez.
2. **Batch.** Un job de PySpark en un EMR que **se apaga solo** limpia dos años de reservas (reglas
   C1–C5) y escribe Parquet particionado por mes en S3.
3. **Analítico.** Las tablas están en el Glue Data Catalog; el panel de gerencia consulta Athena en
   cada pedido.

**Resultado:** harness del profesor **70,0 / 70,0** en una sola corrida (18/10), con 23 tests en 34 s.

## 3. Datos para usar en la demo

### Página del cliente: vuelos que existen (PostgreSQL)

La API no tiene un endpoint para listar todos los vuelos: busca por **origen + destino + fecha**. Estos
son todos los que hay hoy (70 vuelos, 68 reservas):

| Origen → Destino | Fecha | Vuelos | Asientos libres | Para qué |
|---|---|---|---|---|
| **PEI → CLO** (Pereira → Cali) | **15/12/2026** | 2 | 181 | **Vuelos de demo** (cargados hoy) |
| PEI → CLO | 16/12/2026 | 1 | 0 | La prueba de sobreventa de hoy (ya no aparece al buscar) |
| BGA → BOG (Bucaramanga → Bogotá) | 01/03/2030 a 10/03/2030 | 3 por día | 450 por día | Los creó la prueba R1 del harness (búsqueda) |
| BGA → BOG | 15/01/2030 | 33 | 12 | Prueba R2 (sobreventa): casi todos llenos |
| BGA → BOG | 20/05/2031 | 4 | 8 | Prueba R8 (navegador) |

Los dos vuelos de demo del 15/12/2026:

- `DEMO-PEI-CLO-1`: 180 asientos, US$ 320. Para mostrar una reserva normal.
- `DEMO-PEI-CLO-ULTIMO`: **1 asiento**, US$ 450. Para mostrar que no se sobrevende: el primero que
  reserva se lo lleva; después el vuelo deja de aparecer en la búsqueda (sólo se listan vuelos con
  asientos). Para ver el rechazo en pantalla: abrir la búsqueda en dos pestañas y reservar en las dos;
  la segunda dice "no quedan asientos" (HTTP 409).

### Panel de gerencia: rutas y meses (Athena)

Son **10 rutas** y **24 meses, de 2023-01 a 2024-12** (240 filas):

| Ruta | Ocupación promedio de los 2 años |
|---|---|
| ADZ-SMR | 73,6 % |
| BAQ-CUC | 92,1 % |
| BAQ-PSO | 84,2 % |
| BGA-BOG | 70,7 % |
| BGA-CLO | 94,2 % |
| BOG-SMR | 81,6 % |
| CLO-BAQ | 76,1 % |
| CLO-CTG | 89,6 % |
| PEI-CLO | 78,9 % |
| SMR-ADZ | 86,9 % |

**Ejemplo para la demo:** `PEI-CLO` + `2023-03` → **83,59 %** (7.824 de 9.360 asientos). Es el mismo
caso que usó el harness: panel = endpoint = oráculo. Tarda ~2 s porque Athena corre la consulta en ese
momento, sin caché (decisión D6).

⚠️ El ejemplo gris del formulario (`BOG-MDE`) **no existe en los datos**: devuelve "no hay datos"
(404). Usar una de las 10 rutas de arriba.

### Demo de sobreventa en vivo (probado hoy)

Crea un vuelo con 1 asiento y le tira 30 reservas al mismo tiempo. Se puede pegar en CloudShell o en
Git Bash, y se puede repetir porque cada vez crea un vuelo nuevo:

```bash
IP=54.147.173.30; FID=DEMO-CARRERA-$RANDOM
curl -s -o /dev/null -w "vuelo $FID: %{http_code}\n" -X POST http://$IP:8000/admin/flights -H 'Content-Type: application/json' -d "{\"flight_id\":\"$FID\",\"route\":\"PEI-CLO\",\"flight_date\":\"2026-12-16\",\"capacity\":1,\"price_cents\":30000}"
( for i in $(seq 1 30); do curl -s -o /dev/null -w '%{http_code}\n' -X POST http://$IP:8000/reservations -H 'Content-Type: application/json' -d "{\"flight_id\":\"$FID\",\"passenger_name\":\"Pasajero $i\",\"fare_class\":\"ECONOMY\"}" & done; wait ) | sort | uniq -c
```

Resultado esperado (el de hoy): `1 201` y `29 409`. Una sola reserva entra y 29 se rechazan.

### Correr el harness del profesor (los tests)

**Desde CloudShell** (recomendado: ya tiene las credenciales). Ya está todo en `~/p2h`; el script
busca solo la IP de la EC2 y reinstala lo que CloudShell borra entre sesiones:

```bash
nohup bash ~/p2h/05-correr-harness.sh > ~/p2h/harness.log 2>&1 & tail -f --pid=$! ~/p2h/harness.log
```

Muestra el avance y se cierra solo al terminar. (Con un `tail -f` sin `--pid` la terminal queda
mirando el archivo para siempre aunque el harness ya haya terminado: se sale con Ctrl + C.)
Tarda ~2 min la primera vez de la sesión (instalación) y ~40 s las siguientes. Sólo una parte:
`bash ~/p2h/05-correr-harness.sh tests/test_backend.py`. **Corrida del 22/10: 70,0 / 70,0**, 23 tests
en 40 s, p95 de R1 = 0,069 s, R12 declarado 8,36 contra 9,03 estimado.

**Desde la laptop:** cargar las credenciales del lab con `scripts\cargar-credenciales.ps1` y, en la
carpeta `harness/`, `C:\Users\pipel\venvs\bigdata\Scripts\python.exe -m pytest` (~5 min).

## 4. Pestañas abiertas en Chrome, en orden de demo

1. **Cliente:** PEI → CLO, 15/12/2026, Buscar, Reservar, nombre, Confirmar. Muestra el número de reserva.
2. **Swagger (`/docs`):** los endpoints. `GET /reservations/{id}` con el número de la reserva recién
   hecha; `GET /analytics/occupancy` con `PEI-CLO` y `2023-03`.
3. **Panel de gerencia:** PEI-CLO, 2023-03 → 83,59 %.
4. **EMR → Clústeres:** los 4 terminados. Los del parcial se llaman `parcial2-curar`:
   - `j-0521467TOB8AKZBIIM2`: el bueno. 1 primario + 1 core `m4.large`, "Todos los pasos
     completados", 11 min, **se apagó solo** (`--auto-terminate`).
   - `j-00349162LQTSD9WGFEE5`: el intento con un solo nodo, que se trabó (YARN no ubicaba el AM de
     Spark en el primario). Se terminó a mano. Es la razón del cambio a 1 + 1.
   - Los otros dos (`taller taxis nyc`) son del Taller, otra entrega.
5. **S3 → `aerolinea-p2-936980625651`:** `raw/` (CSV de entrada), `scripts/` (el job),
   `curated/reservations_curated/month=2023-01 … 2024-12/` (24 carpetas, un Parquet cada una),
   `curated/route_month_metrics/`, `athena-results/`, `logs/` (EMR) y `deploy/` (el paquete de la app).
6. **Glue → `airline_analytics`:** las 2 tablas, `reservations_curated` y `route_month_metrics`,
   creadas con DDL (sin crawler).
7. **Athena → Editor de consultas:** base `airline_analytics` ya elegida. **Antes de la primera
   consulta**, la consola pide la ubicación de resultados: *Editar ajustes* →
   `s3://aerolinea-p2-936980625651/athena-results/` → Guardar. Consultas para mostrar (cuestan
   centavos de centavo):

   ```sql
   -- La misma consulta que hace el panel
   SELECT occupancy, seats_sold, seats_capacity
   FROM route_month_metrics WHERE route = 'PEI-CLO' AND month = '2023-03';

   -- Poda de particiones: lee una sola carpeta month=. Mirar "Datos escaneados" (~280 KB)
   SELECT route, count(*) AS reservas, sum(price_cents) / 100.0 AS ingresos_usd
   FROM reservations_curated
   WHERE month = '2023-03' AND status = 'CONFIRMED'
   GROUP BY route ORDER BY ingresos_usd DESC;

   -- Top de rutas por ingresos en los dos años
   SELECT route, sum(revenue_cents) / 100.0 AS ingresos_usd
   FROM route_month_metrics GROUP BY route ORDER BY 2 DESC LIMIT 10;
   ```
8. **EC2 → Instancias:** `parcial2-app`, `t3.micro`, en ejecución, con la IP de hoy.
9. **CloudShell:** para cualquier comando.

## 5. Números para defender

| Requisito | Medición del harness (18/10) |
|---|---|
| R1 búsqueda (p95 ≤ 1 s) | p95 **0,080 s** con 20 clientes simultáneos |
| R2 sin sobreventa | 50 pedidos por el último asiento: **1 aceptado, 49 rechazados**; con K = 3: **3** |
| R4 job de EMR | **2.017.079** filas curadas (de 2.087.701 crudas), idénticas al oráculo; 24/24 Parquet |
| R6 Athena podado | un mes escaneó **280.837 B** (tope 1.827.162) |
| R7 endpoint desde Athena | 5 rutas/mes correctas en ~1 s |
| R10 EMR acotado | 0 clústeres vivos; 48 h normalizadas en 45 días (tope 150) |
| R12 costos | declarado **US$8,36/mes**; lo que el harness estima sobre lo vivo: 9,03 |

**Costo real:** todo el parcial costó menos de US$1 en AWS. La proyección 24/7 es de US$8,36 que
mide el harness (EC2 7,59 · Athena 0,50 · EMR 0,26 · S3 0,01) **+ US$4,29** de disco EBS e IPv4
pública, que el harness no estima y están explicados en el documento (§5.7). Total real: US$12,65.

## 6. Preguntas probables, respuesta corta

- **¿Cómo evitás la sobreventa?** El descuento del asiento es un `UPDATE … SET seats_available =
  seats_available - 1 WHERE flight_id = … AND seats_available > 0`, en la misma transacción que el
  `INSERT` de la reserva. PostgreSQL bloquea la fila del vuelo: los pedidos se ordenan solos y, cuando
  llega a 0, el `UPDATE` no toca ninguna fila → 409. El `CHECK (seats_available >= 0 AND
  seats_available <= capacity)` de la tabla es una segunda red.
- **¿Por qué EMR transitorio y no un clúster fijo?** El job tarda ~2 min; un clúster prendido cobra
  todo el día. Con `--auto-terminate` se paga sólo lo que dura el step, y R10 lo exige.
- **¿Por qué 1 primario + 1 core y no 1 solo nodo?** Con un nodo el step quedó esperando recursos para
  el AM de Spark y el clúster no terminaba nunca. Con un core, terminó en ~2 min.
- **¿Por qué partition projection?** Athena calcula las 24 particiones a partir del rango
  `2023-01,2024-12`. No hace falta correr un crawler ni `MSCK REPAIR` después de cada corrida.
- **¿Por qué la tabla de métricas no está particionada?** Si `month` fuera partición, saldría de la
  lista de columnas y el orden dejaría de coincidir con el contrato (R5). Además son 240 filas.
- **¿Por qué una sola EC2 con Docker?** Es lo más barato que cumple: una `t3.micro` aguanta R1 con p95
  de 80 ms. Sin balanceador, sin NAT y sin RDS (R11 premia lo simple).
- **¿Y la inyección SQL en Athena?** Doble defensa: el formato de la ruta y del mes se valida con regex
  (si no coincide, 422) y los valores viajan como parámetros de Athena (`ExecutionParameters`), nunca
  pegados al texto de la consulta.
- **¿`bookings` cuenta las canceladas?** El contrato dice sólo confirmadas, y así está. El oráculo del
  harness cuenta confirmadas + canceladas; está consultado con el profesor y es un parámetro del job
  (`--bookings-incluye-canceladas`).

## 7. Cambios de hoy (22/10)

- **IP nueva** en `harness/config.yaml`: `54.147.173.30`.
- **Arreglo visual en la página del cliente:** el recuadro "Reserva confirmada" y el campo "Pasajero"
  se veían antes de buscar, porque el `display: flex` de `section` le ganaba al atributo `hidden`. Se
  agregó `[hidden] { display: none !important; }` en `app/static/index.html` y se aplicó en la EC2 por
  SSM, sin reiniciar nada (la app lee el HTML en cada pedido). El recorrido del test R8 sigue igual y se
  probó en el navegador.
- **Vuelos de demo:** `DEMO-PEI-CLO-1` y `DEMO-PEI-CLO-ULTIMO` (15/12/2026) y uno `DEMO-CARRERA-…`
  (16/12/2026, ya lleno) de la prueba de sobreventa. No afectan lo que mide el harness.

## 8. Al terminar la clase

- **End Lab** en el panel del lab. La EC2 queda (se decidió dejarla para la corrección): el lab la
  apaga sola y la vuelve a prender en la próxima sesión, con otra IP.
- No queda ningún EMR vivo. No hay nada más que apagar hoy.
- **Después de la corrección:** dar de baja la EC2, el SG, el bucket y la base de Glue. Los comandos
  los imprime `infra/09-auditar-y-baja.sh` (sólo lee; los comandos de baja se pegan a mano).
