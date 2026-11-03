"""
Convierte un informe en Markdown a PDF con el mismo estilo de las otras entregas del curso.

    python md_a_pdf.py informe.md [salida.pdf]

Marcadores que se reemplazan antes de convertir (rutas relativas al .md):
    {{codigo:ruta/archivo.py}}   el archivo como bloque de código (el lenguaje sale de la extensión)
    {{csv:ruta/archivo.csv}}     el CSV como tabla
Las imágenes (![](ruta.png)) se embeben en el HTML, así el PDF no depende de rutas.
Un título `## Anexo` empieza en página nueva.

Requiere:  pip install markdown   ·   Google Chrome instalado (imprime en modo headless)
"""
import base64
import csv
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import markdown

CHROME = [
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    Path(r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
]
LENGUAJES = {".py": "python", ".sh": "bash", ".sql": "sql", ".json": "json", ".md": "markdown"}

CSS = """
@page { size: A4; margin: 15mm 15mm 16mm 15mm;
        @bottom-center { content: counter(page); font: 8.5pt 'Segoe UI', sans-serif; color: #777; } }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { font: 10pt/1.45 'Segoe UI', system-ui, Arial, sans-serif; color: #1f2328; background: #fff;
       margin: 0 auto; max-width: 190mm; padding: 0 2mm; }
h1, h2, h3 { color: #0f3a66; line-height: 1.25; break-after: avoid; }
h1 { font-size: 19pt; border-bottom: 2px solid #0f3a66; padding-bottom: 4px; margin: 0 0 8px; }
h2 { font-size: 13.5pt; margin: 17px 0 7px; border-bottom: 1px solid #d0d7de; padding-bottom: 2px; }
h2.anexo { break-before: page; }
h3 { font-size: 11pt; margin: 13px 0 5px; }
p { margin: 6px 0; }
code { font-family: Consolas, 'Cascadia Mono', monospace; font-size: 0.88em; background: #f2f4f7;
       padding: 0 3px; border-radius: 3px; overflow-wrap: break-word; }
pre { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 4px; padding: 7px 9px;
      font-size: 7.4pt; line-height: 1.33; white-space: pre-wrap; overflow-wrap: anywhere; }
pre code { background: none; padding: 0; font-size: 1em; }
table { width: 100%; border-collapse: collapse; margin: 8px 0 10px; font-size: 8.6pt; line-height: 1.35; }
thead { display: table-header-group; }
tr { break-inside: avoid; }
th, td { border: 1px solid #c8d1dc; padding: 3px 5px; vertical-align: top; text-align: left; }
th { background: #e9eff6; color: #0f3a66; }
blockquote { margin: 8px 0; padding: 4px 11px; border-left: 3px solid #8fb0d8; background: #f4f8fc; }
img { max-width: 100%; display: block; margin: 8px auto; }
ul, ol { margin: 5px 0; padding-left: 22px; }
li { margin: 2px 0; }
hr { border: none; border-top: 1px solid #d0d7de; margin: 14px 0; }
"""


def tabla_csv(ruta: Path) -> str:
    filas = list(csv.reader(ruta.open(encoding="utf-8")))
    if not filas:
        return "_(sin filas)_"
    lineas = ["| " + " | ".join(filas[0]) + " |", "|" + "---|" * len(filas[0])]
    lineas += ["| " + " | ".join(f) + " |" for f in filas[1:]]
    return "\n".join(lineas)


def expandir(md: str, base: Path) -> str:
    def _codigo(m):
        ruta = (base / m.group(1)).resolve()
        lenguaje = LENGUAJES.get(ruta.suffix, "")
        return f"```{lenguaje}\n{ruta.read_text(encoding='utf-8').rstrip()}\n```"

    md = re.sub(r"\{\{codigo:([^}]+)\}\}", _codigo, md)
    return re.sub(r"\{\{csv:([^}]+)\}\}", lambda m: tabla_csv((base / m.group(1)).resolve()), md)


def embeber(html: str, base: Path) -> str:
    def _src(m):
        src = m.group(1)
        if src.startswith(("http", "data:")):
            return m.group(0)
        ruta = (base / src).resolve()
        tipo = "svg+xml" if ruta.suffix == ".svg" else ruta.suffix.lstrip(".").replace("jpg", "jpeg")
        return f'src="data:image/{tipo};base64,{base64.b64encode(ruta.read_bytes()).decode()}"'

    return re.sub(r'src="([^"]+)"', _src, html)


def convertir(fuente: Path, salida: Path) -> None:
    md = expandir(fuente.read_text(encoding="utf-8"), fuente.parent)
    cuerpo = markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"])
    cuerpo = re.sub(r"<h2>(Anexo)", r'<h2 class="anexo">\1', cuerpo)
    titulo = re.search(r"<h1>(.*?)</h1>", cuerpo)
    html = (f'<!doctype html><html lang="es"><head><meta charset="utf-8">'
            f'<title>{re.sub("<[^>]+>", "", titulo.group(1)) if titulo else fuente.stem}</title>'
            f'<style>{CSS}</style></head><body>{embeber(cuerpo, fuente.parent)}</body></html>')
    chrome = next((c for c in CHROME if c.exists()), None)
    if chrome is None:
        raise SystemExit("Chrome no encontrado")
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        ruta_html = Path(tmp) / "informe.html"
        ruta_html.write_text(html, encoding="utf-8")
        subprocess.run(
            [str(chrome), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
             f"--user-data-dir={Path(tmp) / 'perfil'}", f"--print-to-pdf={salida}", ruta_html.as_uri()],
            check=True, timeout=180, capture_output=True,
        )
    print(f"[ok] {salida.name} ({salida.stat().st_size:,} bytes)")


if __name__ == "__main__":
    fuente = Path(sys.argv[1]).resolve()
    convertir(fuente, Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else fuente.with_suffix(".pdf"))
