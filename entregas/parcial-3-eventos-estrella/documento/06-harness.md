# 6. El harness: cómo se corrió y qué dio

## 6.1 Resultado final

**70,0 / 70,0 contra lo desplegado en AWS, el 24/11/2026**, en la primera corrida completa: 29 tests
en 2 min 46 s. El `report.md` va íntegro en el Anexo C. Ningún requisito falló, así que no hay fallas
que explicar; sí hubo un hallazgo del Learner Lab que obligó a corregir la configuración (§6.4).

| Medición | Valor | Umbral |
|---|---|---|
| p95 de la búsqueda con 50 en paralelo (R2) | 0,094 s | ≤ 1,0 s |
| Eventos de la ráfaga en el stream (R2) | 200 de 200 | exactos |
| Vista en vivo: tiempo hasta reflejar 10 + 3 + 1 eventos (R3) | 1,5 s | ≤ 10 s |
| Vista en vivo tras el replay de 17.000 búsquedas viejas (R3) | 245 (las del momento) | < 1.700 |
| Eventos del replay en S3 (R4) | 19.912 de 19.912, a los 61 s | ≤ 300 s |
| Refresh de la estrella (R8) | 20 s | ≤ 900 s |
| Bytes de un mes vs. todos (R10) | 3.798 B vs. 11.177 B (0,34) | ≤ 0,6 |
| Stream (R11) | PROVISIONED, 1 shard, 24 h, 0 consumidores EFO | — |
| Proyección (R12) | US$10,76/mes | ≤ US$50 en la copia del alumno |

## 6.2 Cómo se corrió

Desde **CloudShell**, que ya tiene las credenciales del lab, con los scripts de `infra/`:

1. Se arma el paquete en la laptop con `bash infra/empaquetar.sh`.
2. Se sube a CloudShell (Acciones → Cargar archivo) y se descomprime en `~/p3`.
3. Se levanta la sesión: `bash ~/p3/infra/10-levantar-sesion.sh` crea, si falta, lo siguiente:
   - el bucket, el stream y Firehose;
   - el workgroup, `ref/` y las dimensiones;
   - el despliegue de la API en la EC2 por SSM.
4. Se corre el harness: `nohup bash ~/p3/infra/20-correr-harness.sh > harness.log 2>&1 &`.
   - El script escribe `harness/config.yaml` con la IP del día, porque cambia en cada sesión del lab.
   - Crea el venv en `/tmp`.
   - Guarda el reporte en `evidencia/` y una copia en el bucket.
5. Al terminar, `bash ~/p3/infra/90-bajar-stream.sh --confirmo`: el stream cobra por hora.

`nohup` hace falta porque CloudShell se desconecta cuando Chrome no está al frente (lección del P2).

## 6.3 Antes de AWS: el mismo harness en local, a US$0

El harness trae una "costura" para inyectar un AWS simulado (`harness/registry.py`). Se usó sin tocar
ni un test (`local/README.md`):

| Prueba | Qué simula | Resultado |
|---|---|---|
| `local/sim_local.py` | Firehose → carpeta local; Athena → **DuckDB con el mismo SQL** de `app/sql`; refresh → la misma clase `Refresco` de la app | R5–R10 y R12: 23 de 23 tests |
| `local/sim_api.py` | Kinesis → moto; la API real con PostgreSQL local | R1–R3: 4 de 4 tests |
| Trampa 1 (replay del profesor sobre una landing con corridas viejas) | `SIM_SALT=7`, `SIM_LIMPIAR=0` | Estrella **20 / 41** sin archivar; **41 / 41** archivando |

En AWS se agregaron R4 y R11, que no se pueden simular, y no hubo que tocar el SQL ni la API: los
números de AWS coincidieron con los locales.

## 6.4 Lo que el Learner Lab enseñó

- **Workgroup con *enforce* y CTAS no conviven.** El primer intento de construir las dimensiones falló
  con *"…submitted with an 'external_location' property to an Athena Workgroup that enforces a
  centralized output location…"*. Se pasó a `EnforceWorkGroupConfiguration = false`: el límite de
  1 GB por consulta igual se aplica (R10 lo verificó). Está explicado en el script y en la §5.9.
- **Firehose aceptó `LabRole`** y el procesador `AppendDelimiterToRecord` sin parámetros. Se verificó
  que un objeto con 5 búsquedas trae 5 JSON en líneas separadas: el salto va *entre* registros.
- **La EC2 del P2 volvió sola** con la sesión, con IP nueva (34.228.161.170). El despliegue por SSM
  reconstruyó la imagen y conservó la base, porque usa el mismo proyecto de Docker Compose.

## 6.5 Para la defensa (el profesor corre su propia copia)

- El profesor usa un `probe_salt` distinto: sus `event_id` coinciden con los nuestros pero con otro
  contenido (§5.7). Por eso, **antes de la defensa**:
  1. se levanta la sesión con `10-levantar-sesion.sh`;
  2. se archiva la landing y se reconstruye la estrella con `80-archivar-landing.sh --confirmo`;
  3. se actualiza la IP en `config.yaml`.
- **R12 depende de la referencia del profesor**, que la copia del alumno no trae (`reference_monthly_usd`
  es 60). La proyección es de US$10,76: queda dentro de 1,5× cualquier referencia mayor que US$7,17.
