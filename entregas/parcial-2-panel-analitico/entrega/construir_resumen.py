"""
Arma el resumen para la sustentación: la versión corta del documento final.

    python construir_resumen.py

Fuente: `documento/resumen-sustentacion.md`. Genera, en esta carpeta:
    Parcial2-Resumen-Sustentacion.html
    Parcial2-Resumen-Sustentacion.pdf    impreso con Chrome headless

Usa el mismo estilo y la misma impresión que `construir_documento.py`, sin portada ni índice: es
para leer de corrido en la defensa.
"""

import argparse
import re

from construir_documento import (AQUI, AUTOR, CSS, DOC, FECHA, MERMAID_JS, REPO, a_html,
                                 imprimir_pdf, limpiar)

NOMBRE = "Parcial2-Resumen-Sustentacion"
FUENTE = DOC / "resumen-sustentacion.md"

# Los capítulos siguen de corrido (en el documento final cada h1 abre página) y el diagrama
# se achica: acá acompaña, no es el protagonista.
CSS_RESUMEN = CSS + """
h1 { page-break-before: auto; break-before: auto; font-size: 15pt; margin: 18px 0 8px; }
pre.mermaid svg { max-height: 85mm; }
.cabecera { border-bottom: 3px solid #0f3a66; padding-bottom: 8px; margin-bottom: 6px; }
.cabecera .materia { font-size: 9pt; color: #555; letter-spacing: .3px; }
.cabecera .titulo { font-size: 21pt; font-weight: 700; color: #0f3a66; margin: 2px 0; }
.cabecera .datos { font-size: 9pt; color: #333; }
"""


def construir_html(autor: str) -> str:
    cuerpo = a_html(limpiar(FUENTE.read_text(encoding="utf-8"), FUENTE))
    cuerpo = re.sub(r'<pre><code class="language-mermaid">(.*?)</code></pre>',
                    r'<pre class="mermaid">\1</pre>', cuerpo, flags=re.S)
    cabecera = f"""
<header class="cabecera">
  <div class="materia">UNIVERSIDAD SERGIO ARBOLEDA · Big Data e Ingeniería de Datos (PCIA 5010)</div>
  <div class="titulo">Parcial 2 — Panel analítico de la aerolínea · Resumen</div>
  <div class="datos"><strong>{autor}</strong> · individual · semilla 12345 · {FECHA} ·
    harness <strong>70,0 / 70,0</strong> · {REPO.replace("https://", "")}</div>
</header>"""
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Parcial 2 — Resumen para la sustentación</title>
<style>{CSS_RESUMEN}</style>
</head><body>
{cabecera}
{cuerpo}
<script src="{MERMAID_JS}"></script>
<script>
  mermaid.initialize({{ startOnLoad: true, theme: "neutral", securityLevel: "strict",
    flowchart: {{ useMaxWidth: true }} }});
</script>
</body></html>
"""


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--autor", default=AUTOR)
    ap.add_argument("--sin-pdf", action="store_true", help="genera sólo el .html")
    args = ap.parse_args()

    ruta_html = AQUI / f"{NOMBRE}.html"
    ruta_html.write_text(construir_html(args.autor), encoding="utf-8")
    print(f"[ok] {ruta_html.name}")

    if not args.sin_pdf:
        ruta_pdf = AQUI / f"{NOMBRE}.pdf"
        if imprimir_pdf(ruta_html, ruta_pdf):
            print(f"[ok] {ruta_pdf.name}  ({ruta_pdf.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
