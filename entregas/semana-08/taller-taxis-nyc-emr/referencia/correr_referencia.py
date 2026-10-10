"""
Corre respuestas_athena.sql por la API de Athena y muestra cada resultado con lo que escaneó.

    python3 correr_referencia.py              consultas 0 a 3: tablas sobre los crudos y calidad
    python3 correr_referencia.py --tope 120   consultas 4 a 7: las respuestas, con el tope elegido

Corre en CloudShell (boto3 y las credenciales del lab ya están). Los resultados de Athena quedan en
s3://taxis-nyc-<cuenta>/athena-resultados/.
"""

import argparse
import re
import time
from pathlib import Path

import boto3

SQL = Path(__file__).with_name("respuestas_athena.sql")


def consultas(texto):
    """Separa el archivo en sentencias, con el número del comentario que las encabeza.

    Los comentarios se quitan antes de buscar el ';' final: un ';' dentro de un comentario
    no corta nada. (El archivo no tiene '--' dentro de cadenas de texto.)
    """
    salida, numero, codigo = [], "?", []
    for linea in texto.splitlines():
        encabezado = re.match(r"\s*--\s*(\d+[ab]?)\s*·", linea)
        if encabezado:
            numero = encabezado.group(1)
        sin_comentario = linea.split("--", 1)[0].rstrip()
        if sin_comentario.strip():
            codigo.append(sin_comentario)
        if sin_comentario.endswith(";"):
            salida.append((numero, "\n".join(codigo).rstrip(";")))
            codigo = []
    return salida


def correr(athena, sql, salida_s3):
    qid = athena.start_query_execution(
        QueryString=sql, ResultConfiguration={"OutputLocation": salida_s3})["QueryExecutionId"]
    while True:
        e = athena.get_query_execution(QueryExecutionId=qid)["QueryExecution"]
        estado = e["Status"]["State"]
        if estado in ("SUCCEEDED", "FAILED", "CANCELLED"):
            break
        time.sleep(1)
    if estado != "SUCCEEDED":
        raise SystemExit(f"   !! {estado}: {e['Status'].get('StateChangeReason')}")
    filas = athena.get_query_results(QueryExecutionId=qid)["ResultSet"]["Rows"]
    tabla = [[c.get("VarCharValue", "") for c in f["Data"]] for f in filas]
    stats = e["Statistics"]
    return tabla, stats.get("DataScannedInBytes", 0), stats.get("EngineExecutionTimeInMillis", 0)


def imprimir(tabla):
    if not tabla:
        return
    anchos = [max(len(f[i]) for f in tabla) for i in range(len(tabla[0]))]
    for n, f in enumerate(tabla):
        print("   " + "  ".join(v.ljust(a) for v, a in zip(f, anchos)))
        if n == 0:
            print("   " + "  ".join("-" * a for a in anchos))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tope", type=float, help="tope de duración válida en minutos (consultas 4 a 7)")
    args = ap.parse_args()

    cuenta = boto3.client("sts").get_caller_identity()["Account"]
    bucket = f"taxis-nyc-{cuenta}"
    athena = boto3.client("athena", region_name="us-east-1")
    salida_s3 = f"s3://{bucket}/athena-resultados/"

    texto = SQL.read_text(encoding="utf-8").replace("BUCKET", bucket)
    elegidas = []
    for numero, sql in consultas(texto):
        es_respuesta = numero[0] in "4567"
        if args.tope is None and not es_respuesta:
            elegidas.append((numero, sql))
        elif args.tope is not None and es_respuesta:
            elegidas.append((numero, sql.replace("TOPE_MIN", f"{args.tope:g}")))

    total = 0
    for numero, sql in elegidas:
        primera = next(l for l in sql.splitlines() if l.strip())
        print(f"\n== {numero} · {primera[:90]}")
        tabla, escaneado, ms = correr(athena, sql, salida_s3)
        total += escaneado
        imprimir(tabla)
        print(f"   [{escaneado:,} bytes escaneados · {ms / 1000:.1f} s]")
    print(f"\nTotal escaneado: {total:,} bytes → ${total / 1e12 * 5:.4f} a $5/TB")


if __name__ == "__main__":
    main()
