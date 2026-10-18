# Corrida del harness en AWS — 18/10/2026 · **70,0 / 70,0**

`report.md` y `report.json` son la salida **sin editar** del harness del profesor, en una sola corrida
(23 tests en 34 s) contra el sistema desplegado en la cuenta `936980625651` (us-east-1).

| Pieza | Identificador |
|---|---|
| App (API + frontend + PostgreSQL en Docker) | EC2 `i-02fec020612e00ad5` · `t3.micro` · `http://100.55.17.95:8000` (la IP cambia en cada sesión del lab) |
| Security group | `sg-0aed72ab437513545` (8000 abierto; 22 sólo EC2 Instance Connect) |
| Job de EMR | clúster transitorio `j-0521467TOB8AKZBIIM2` · 1 primario + 1 core `m4.large` · step `COMPLETED` en ~2 min, se apagó solo |
| Datos | `s3://aerolinea-p2-936980625651/` (`raw/`, `curated/`, `scripts/`, `athena-results/`) |
| Catálogo | base `airline_analytics`: `reservations_curated` (partition projection) y `route_month_metrics` |

## Mediciones que respaldan el documento

| Req | Medición |
|---|---|
| R1 | p95 **80 ms** desde CloudShell (183 ms desde la laptop, por internet); tope 1 s |
| R2 | 1 de 50 en el último asiento y 3 de 50 con K = 3, en las 5 rondas; nunca un 5xx |
| R4 | **2.017.079** filas curadas = oráculo · 24/24 Parquet escritos dentro de la ventana del step |
| R6 | consulta de un mes: **280.837 bytes** escaneados (tope 1.827.162) · top-10 = oráculo |
| R7 | 5 consultas en ~1 s cada una, todas desde Athena |
| R10 | ningún clúster activo · **48** horas normalizadas en 45 días (tope 150) |
| R11 | 6 servicios: Athena, EC2, EMR, Glue, **Lambda** (de la cuenta del lab, no del proyecto), S3 |
| R12 | declarado **US$12,65**/mes · estimado sobre lo vivo **US$9,03** (EC2 7,59 + EMR 1,44) |

## Cómo se reproduce

1. CloudShell: subir `harness/` + `cost_projection.yaml`, venv en `/tmp` con `pytest httpx pyyaml boto3
   pandas pyarrow numpy playwright`, y `playwright install chromium-headless-shell`.
2. Chromium necesita bibliotecas que CloudShell no trae:
   `sudo dnf install -y nss nspr atk at-spi2-atk cups-libs libdrm libxkbcommon libXcomposite libXdamage libXrandr libXfixes mesa-libgbm pango alsa-lib`.
3. `config.yaml` con la IP actual de la EC2 y `PLAYWRIGHT_BROWSERS_PATH=/tmp/pw python -m pytest`.

Los reportes se trajeron a la laptop en base64 (la terminal corta las líneas largas) y se
reconstruyeron byte a byte.
