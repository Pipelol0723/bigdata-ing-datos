# 6. Ejecución del harness

## 6.1 Cómo se corrió

El harness es la copia entregada por el profesor, **sin modificar** (`harness/`); sólo se completó
`config.yaml` (semilla 12345, URLs de la EC2, base de Athena) y se escribió `cost_projection.yaml`.

| Aspecto | Detalle |
|---|---|
| Fecha | 18/10/2026, 22:29 UTC |
| Dónde | **AWS CloudShell** de la cuenta del lab: el harness consulta Glue, Athena, EMR, EC2 y S3 con boto3, y CloudShell ya tiene las credenciales temporales del Learner Lab. Así no tocan el disco de la laptop |
| Contra qué | La app en la EC2 `t3.micro` (`http://100.55.17.95:8000` ese día) y las tablas de `airline_analytics` |
| Navegador (R8, R9) | Chromium de Playwright dentro de CloudShell. Le faltaban bibliotecas del sistema (`libnspr4` y otras), que se instalaron con `dnf` para esa sesión |
| Corrida | **Una sola**, con los 23 tests, en 34 s |
| Resultado | **70,0 / 70,0** · `evidencia/harness-2026-10-18/report.md` (Anexo C, sin editar) |

**Segunda corrida, 22/10/2026**, también en CloudShell y ya con la proyección entregada (US$8,36):
**70,0 / 70,0**, 23 tests en 40 s, con la EC2 en otra IP después del reinicio del lab. R1 dio p95 =
0,069 s; R6, 280.837 B escaneados (igual que el 18/10); R10, 48 h normalizadas; R12, 8,36 declarado
contra 9,03 estimado. Desde entonces la corrida es un solo comando: `infra/05-correr-harness.sh` busca la
IP actual de la EC2, reinstala en `/tmp` lo que CloudShell borra entre sesiones y corre `pytest`.

Antes de esa corrida, cada parte se probó por separado y gratis: el job de PySpark contra el oráculo
en la laptop, con resultados idénticos fila por fila, y R1–R3 y R8 contra un backend local
(`local/README.md`).

## 6.2 Resultado por requisito

| Req | Estado | Puntos | Evidencia del reporte |
|---|---|---|---|
| R1 | passed | 4 / 4 | 100 pedidos, 20 concurrentes: p50 = 0,014 s, **p95 = 0,080 s** |
| R2 | passed | 10 / 10 | 5 rondas de 50 por el último asiento: **201 = 1, 409 = 49**; 5 rondas con K = 3: **201 = 3** |
| R3 | passed | 3 / 3 | lectura de la reserva creada y 404 para una inexistente |
| R4 | passed | 8 / 8 | **2.017.079** filas curadas (esperadas 2.017.079); **24/24** Parquet escritos dentro de un step `COMPLETED` |
| R5 | passed | 6 / 6 | columnas y formato según contrato; partition projection habilitada |
| R6 | passed | 8 / 8 | top-10 igual al oráculo; un mes escaneó **280.837 B** (tope 1.827.162 B) |
| R7 | passed | 8 / 8 | 5 pares ruta-mes correctos en 0,93–1,06 s; 8 consultas de Athena durante la prueba |
| R8 | passed | 6 / 6 | reserva `R1D8F8FACA31A492` creada desde el navegador y leída del backend |
| R9 | passed | 4 / 4 | PEI-CLO 2023-03: panel = endpoint = oráculo = **0,8359** |
| R10 | passed | 5 / 5 | 0 clústeres activos; **48** horas normalizadas en 45 días (tope 150) |
| R11 | passed | 4 / 4 | servicios: Athena, EC2, EMR, Glue, Lambda, S3 (6 de 8) |
| R12 | passed | 4 / 4 | declarado 12,65; estimado sobre lo vivo 9,03 (ver 6.3) |

## 6.3 Lo que hay detrás de algunos números

- **R10 — las 48 horas normalizadas.** El harness suma todos los clústeres de la cuenta de los últimos
  45 días: 36 son del Taller Taxis del 10 y 13/10 (otra entrega del curso), 4 de la corrida de un
  nodo que se trabó y 8 de la corrida buena. El propio job del parcial consume 8 por corrida.
- **R11 — Lambda y CloudFront.** Lambda aparece porque la cuenta del Learner Lab trae funciones
  propias; este proyecto no usa Lambda. CloudFront figura como **"could not inspect"**: el rol del lab
  no puede listarlo, así que el harness no lo cuenta. Este proyecto no usa CloudFront; se declara como
  pide la sección 6 del enunciado.
- **R12 — la proyección cambió después de la corrida.** Ese día el yaml declaraba US$12,65 (incluía
  EBS e IPv4). El 22/10 se dejó en **US$8,36** por lo explicado en §5.7. Las dos comprobaciones de
  R12 con el yaml nuevo:

  | Momento | Estimado del harness | Diferencia | Tolerancia (25 % + 2) | |
  |---|---|---|---|---|
  | Hoy (48 h de EMR en la ventana) | 9,03 | 0,67 | 4,26 | pasa |
  | Desde el 24/11 (24 h) | 8,31 | 0,05 | 4,08 | pasa |
  | Desde el 02/12 (0 h) | 7,59 | 0,77 | 3,90 | pasa |

  Con el yaml anterior (12,65) la segunda y la tercera fila fallaban. El tope por referencia
  (`mín(1,5 × referencia, 50)`) se cumple mientras la referencia del profesor sea de al menos
  US$5,57. El 22/10 se corrió el harness completo con el yaml nuevo (§6.1) y R12 pasa en sus dos
  comprobaciones.

## 6.4 Preguntas abiertas al profesor

1. **`bookings`.** El contrato dice "sólo CONFIRMED" y el oráculo calcula "confirmadas + canceladas".
   Se implementó el contrato, con la otra lectura a un parámetro (§5.8). ¿Cuál es la correcta?
2. **Referencia de R12.** `thresholds.yaml` trae `reference_monthly_usd: 60` como valor provisorio.
   ¿Cuál es el definitivo? ¿Y la proyección debe incluir costos que el harness no estima, como el EBS
   y la IPv4 pública, o sólo los que modela `pricing.yaml`?

## 6.5 Antes de la corrección

El Learner Lab detiene la EC2 al cerrar cada sesión y la vuelve a prender en la siguiente, **con otra
IP pública**. Docker está habilitado al arranque y los contenedores tienen `restart: unless-stopped`,
así que la app vuelve sola: **se comprobó el 22/10**, tras el reinicio que hizo el lab, sin tocar
nada. Lo único que cambia es la dirección:

1. Abrir el lab y esperar a que la EC2 `parcial2-app` esté `running` (2–3 min).
2. Tomar la IP nueva (`aws ec2 describe-instances --filters Name=tag:Name,Values=parcial2-app`) y
   ponerla en las dos URLs de `harness/config.yaml`.
3. Verificar `http://<IP>:8000/health` y, si se quiere, volver a correr el harness con
   `infra/05-correr-harness.sh`, que hace el paso 2 solo.

## 6.6 Lo que falló en el camino y cómo se resolvió

Ningún requisito quedó fallando, pero cuatro habrían fallado sin estos cambios:

| Req | Qué pasó | Cambio |
|---|---|---|
| R4 / R10 | El job en un clúster de **un solo nodo** quedó trabado: *"waiting for resources to be assigned for AM"*. YARN no ubica el application master de Spark en el nodo primario, y como el step no terminaba, el clúster tampoco se apagaba solo | Clúster de 1 primario + 1 core; el step terminó en ~2 min |
| R1 | En las pruebas locales, p95 = 2,05 s con p50 = 7 ms: la URL `localhost` resolvía primero a IPv6 y cada conexión nueva esperaba ~2 s antes de reintentar por IPv4 | Usar la IP (`127.0.0.1` en local, la de la EC2 en AWS); p95 bajó a 18 ms |
| R3 | Si el `reservation_id` del path fuera numérico, un id inválido daría 422 y no 404 | Se declaró `str` desde el diseño |
| R5 | Si `route_month_metrics` se particionara por mes, el catálogo sacaría `month` de las columnas y el orden dejaría de coincidir con el contrato | Tabla sin particionar desde el diseño |
