"""Corre una sentencia en Athena, espera el resultado y lo imprime como tabla (y opcionalmente CSV).

    python3 athena.py --db taller_kinesis --salida s3://bucket/athena-results/ --sql "SELECT 1" [--csv r.csv]
    python3 athena.py ... --archivo consultas.sql      (varias sentencias separadas por ';')

Imprime además los bytes escaneados: es lo que cobra Athena (US$5 por TB, mínimo 10 MB por consulta).
"""
import argparse
import csv
import time

import boto3

ap = argparse.ArgumentParser()
ap.add_argument("--db", default="default")
ap.add_argument("--salida", required=True, help="s3://.../ para los resultados de Athena")
ap.add_argument("--sql")
ap.add_argument("--archivo")
ap.add_argument("--csv-dir", help="guarda el resultado de cada sentencia como NN.csv")
args = ap.parse_args()

athena = boto3.client("athena", region_name="us-east-1")


def correr(sql):
    qid = athena.start_query_execution(QueryString=sql, QueryExecutionContext={"Database": args.db},
                                       ResultConfiguration={"OutputLocation": args.salida})["QueryExecutionId"]
    while True:
        e = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        estado = e["Status"]["State"]
        if estado in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    if estado != "SUCCEEDED":
        raise SystemExit(f"[!] {estado}: {e['Status'].get('StateChangeReason')}\n{sql}")
    filas, token = [], None
    while True:
        kw = {"QueryExecutionId": qid, "MaxResults": 1000}
        if token:
            kw["NextToken"] = token
        r = athena.get_query_results(**kw)
        filas += [[c.get("VarCharValue", "") for c in f["Data"]] for f in r["ResultSet"]["Rows"]]
        token = r.get("NextToken")
        if not token:
            break
    escaneado = e["Statistics"].get("DataScannedInBytes", 0)
    return filas, escaneado


def es_codigo(sentencia):
    return any(l.strip() and not l.strip().startswith("--") for l in sentencia.splitlines())


texto = args.sql if args.sql else open(args.archivo, encoding="utf-8").read()
for i, sql in enumerate([s.strip() for s in texto.split(";") if es_codigo(s)], 1):
    filas, escaneado = correr(sql)
    comentarios = [l for l in sql.splitlines() if l.strip().startswith("--")]
    titulo = next((l for l in comentarios if l.strip().startswith("-- Q")),
                  comentarios[-1] if comentarios else sql.splitlines()[0])
    print(f"\n### {i:02d} {titulo.strip()}   [{escaneado:,} bytes escaneados]", flush=True)
    codigo = "\n".join(l for l in sql.splitlines() if not l.strip().startswith("--")).lstrip().upper()
    if filas and codigo.startswith(("SELECT", "WITH", "SHOW", "DESCRIBE")):
        anchos = [max(len(str(f[j])) for f in filas) for j in range(len(filas[0]))]
        for f in filas[:60]:
            print("  " + "  ".join(str(v).ljust(a) for v, a in zip(f, anchos)))
        if args.csv_dir:
            with open(f"{args.csv_dir}/{i:02d}.csv", "w", newline="") as fh:
                csv.writer(fh).writerows(filas)
