"""Corre el mismo SQL de Athena con DuckDB sobre el archivo local: depurar acá cuesta $0.

    python probar_duckdb.py [ruta/a/german.data]

Usa la vista de sql/01_tablas.sql tal cual (sólo cambia de dónde salen los datos crudos) y las
consultas de sql/02_consultas.sql sin tocar. Imprime cada resultado.
"""
import re
import sys
from pathlib import Path

import duckdb

AQUI = Path(__file__).resolve().parent
SQL = AQUI.parent / "sql"
DATOS = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(r"C:\Users\pipel\datos-german\uci\german.data")


def sentencias(texto):
    return [s.strip() for s in texto.split(";")
            if any(l.strip() and not l.strip().startswith("--") for l in s.splitlines())]


con = duckdb.connect()
con.execute("CREATE SCHEMA german_credit")
ddl = sentencias((SQL / "01_tablas.sql").read_text(encoding="utf-8"))
columnas = re.findall(r"^\s+(\w+)\s+(string|int)", ddl[1], flags=re.M)
tipos = {c: ("VARCHAR" if t == "string" else "INTEGER") for c, t in columnas}
con.execute(f"""CREATE TABLE german_credit.solicitudes_raw AS
                SELECT * FROM read_csv('{DATOS.as_posix()}', delim=' ', header=false, columns={tipos})""")
con.execute(ddl[2])                       # la vista, idéntica a la de Athena
con.execute("SET search_path = 'german_credit'")
print(f"filas crudas: {con.execute('SELECT count(*) FROM solicitudes_raw').fetchone()[0]}")

for sql in sentencias((SQL / "02_consultas.sql").read_text(encoding="utf-8")):
    titulo = next(l for l in sql.splitlines() if l.strip().startswith("-- Q"))
    print(f"\n{titulo}")
    print(con.sql("\n".join(l for l in sql.splitlines() if not l.strip().startswith("--"))))
