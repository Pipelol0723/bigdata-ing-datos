"""
Arma el PDF de respuestas del Taller Taxis a partir de `Taller-Taxis-NYC-respuestas.md`.

    python construir_pdf.py

El Anexo A no se copia a mano: el marcador {{PROGRAMA}} se reemplaza por el contenido actual de
`../spark/taller_taxis.py`, así el documento no puede quedar desfasado del programa que corre en EMR.

Requiere:  pip install markdown   ·   Google Chrome instalado (imprime el PDF en modo headless)
"""

import subprocess
import tempfile
from pathlib import Path

import markdown

AQUI = Path(__file__).resolve().parent
FUENTE = AQUI / "Taller-Taxis-NYC-respuestas.md"
PROGRAMA = AQUI.parent / "spark" / "taller_taxis.py"
SALIDA = AQUI / "Taller-Taxis-NYC-respuestas.pdf"
CHROME = [
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    Path(r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
]

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
p { margin: 6px 0; }
code { font-family: Consolas, 'Cascadia Mono', monospace; font-size: 0.88em; background: #f2f4f7;
       padding: 0 3px; border-radius: 3px; overflow-wrap: break-word; }
pre { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 4px; padding: 7px 9px;
      font-size: 7.6pt; line-height: 1.35; white-space: pre-wrap; overflow-wrap: anywhere; }
pre code { background: none; padding: 0; font-size: 1em; }
table { width: 100%; border-collapse: collapse; margin: 8px 0 10px; font-size: 8.6pt; line-height: 1.35; }
thead { display: table-header-group; }
tr { break-inside: avoid; }
th, td { border: 1px solid #c8d1dc; padding: 3px 5px; vertical-align: top; text-align: left; }
th { background: #e9eff6; color: #0f3a66; }
ul { margin: 5px 0; padding-left: 22px; }
li { margin: 2px 0; }
hr { border: none; border-top: 1px solid #d0d7de; margin: 14px 0; }
"""


def main() -> None:
    md = FUENTE.read_text(encoding="utf-8")
    codigo = PROGRAMA.read_text(encoding="utf-8").rstrip()
    md = md.replace("{{PROGRAMA}}", f"```python\n{codigo}\n```")
    cuerpo = markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"])
    cuerpo = cuerpo.replace("<h2>Anexo A", '<h2 class="anexo">Anexo A')
    html = f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<title>Taller Taxis NYC — respuestas</title>
<style>{CSS}</style>
</head><body>
{cuerpo}
</body></html>
"""
    chrome = next((c for c in CHROME if c.exists()), None)
    if chrome is None:
        raise SystemExit("Chrome no encontrado")
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as tmp:
        ruta_html = Path(tmp) / "respuestas.html"
        ruta_html.write_text(html, encoding="utf-8")
        subprocess.run(
            [str(chrome), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
             f"--user-data-dir={Path(tmp) / 'perfil'}", f"--print-to-pdf={SALIDA}", ruta_html.as_uri()],
            check=True, timeout=120, capture_output=True,
        )
    print(f"[ok] {SALIDA.name} ({SALIDA.stat().st_size:,} bytes)")


if __name__ == "__main__":
    main()
