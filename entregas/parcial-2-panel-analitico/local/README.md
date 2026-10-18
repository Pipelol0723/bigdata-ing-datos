# Pruebas locales del parcial 2 ($0)

Todo lo que se puede verificar sin AWS. Los datos viven fuera de OneDrive, en
`C:\Users\pipel\datos-parcial2\` (`raw/` los CSV de la semilla 12345, `curated-local/` la salida).

> **Sin Docker en la laptop (desde el 18/10):** WSL2 no arranca porque la virtualización está
> desactivada (`HCS_E_HYPERV_NOT_INSTALLED`), y Docker Desktop corre sobre WSL2. Por eso acá se usa
> un PostgreSQL nativo descartable. En la EC2 (Linux) se usa el `docker-compose.yml`, sin cambios.

## 1 · El job de EMR contra el oráculo

```bash
cd /c/Users/pipel/datos-parcial2
export PYSPARK_PYTHON=/c/Users/pipel/venvs/bigdata/Scripts/python.exe SPARK_LOCAL_HOSTNAME=localhost
python ".../local/probar_job_local.py" raw curated-local
python -I ".../local/validar_contra_oraculo.py" ".../harness" 12345 curated-local
```

Resultado del 18/10: **TODO COINCIDE** — 2.017.079 filas curadas idénticas fila por fila, las 240
filas de métricas, la facturación de los 24 meses y el top-10.

Dos trampas de Spark en esta laptop (ninguna existe en EMR):
- El hostname `portatil_pipe` tiene un guion bajo y Spark lo rechaza en sus URLs internas
  (`Invalid Spark URL`): por eso `SPARK_LOCAL_HOSTNAME=localhost`.
- Para **escribir** archivos, Spark en Windows necesita `winutils.exe`. `probar_job_local.py` usa
  `procesar()` del job tal cual y escribe con pyarrow; la escritura de Spark se prueba en EMR.

## 2 · Backend + frontend con el harness del profesor

```powershell
$bin = "C:\Program Files\PostgreSQL\17\bin"; $dir = "C:\Users\pipel\pg-parcial2"
& "$bin\initdb.exe" -D $dir -U app -A trust -E UTF8 --no-locale      # sólo la primera vez
& "$bin\pg_ctl.exe" -D $dir -o "-p 15499 -c listen_addresses=localhost" -l "$dir\servidor.log" start
& "$bin\createdb.exe" -h localhost -p 15499 -U app aerolinea          # sólo la primera vez
```
```bash
cd app && DATABASE_URL=postgresql://app@localhost:15499/aerolinea python -m uvicorn main:app --port 8000
cd harness && HARNESS_REPORT=../local/reporte-local python -m pytest tests/test_backend.py "tests/test_frontend.py::test_search_reserve_confirm"
```

Resultado del 18/10: **R1 (p95 18 ms), R2 (1 de 50 y 3 de 50, cinco rondas), R3 y R8 en verde.**

⚠️ En `config.yaml` la URL local tiene que ser `http://127.0.0.1:8000`, no `localhost`: en Windows
`localhost` resuelve primero a IPv6, uvicorn escucha en IPv4, y cada conexión nueva pierde ~2 s
reintentando. Con `localhost`, R1 daba p95 = 2,05 s (con p50 = 7 ms).

Apagar: `pg_ctl -D C:\Users\pipel\pg-parcial2 stop` y Ctrl+C en uvicorn.
