"""
Arma el documento final del Parcial 2 a partir de las secciones de `documento/`.

    python construir_documento.py

Genera, en esta carpeta:
    Parcial2-Panel-Analitico-Aerolinea.md     fuente consolidada (se lee en GitHub)
    Parcial2-Panel-Analitico-Aerolinea.html   diagramas Mermaid por CDN
    Parcial2-Panel-Analitico-Aerolinea.pdf    impreso con Chrome headless

Las secciones de `documento/` son la fuente de verdad: si se corrige una, se vuelve a correr esto.
El Anexo C es el `report.md` del harness tal cual, sin editar.

Requiere:  pip install markdown   ·   Google Chrome instalado (sólo para el PDF)
"""

import argparse
import base64
import os
import re
import subprocess
import tempfile
from pathlib import Path

import markdown

AQUI = Path(__file__).resolve().parent
RAIZ = AQUI.parent                                  # entregas/parcial-2-panel-analitico
DOC = RAIZ / "documento"
NOMBRE = "Parcial2-Panel-Analitico-Aerolinea"
REPO = "https://github.com/Pipelol0723/bigdata-ing-datos"
FECHA = "22 de octubre de 2026"
AUTOR = "Andres Felipe Cespedes Rondon"

SECCIONES = [
    "00-introduccion.md",
    "05-decisiones.md",
    "06-harness.md",
]
ANEXO_PROMPTS = DOC / "99-prompt-log.md"
ANEXO_CAMBIOS = DOC / "97-impacto-de-cambios.md"
ANEXO_REPORTE = RAIZ / "evidencia" / "harness-2026-10-18" / "report.md"

CHROME = [
    Path(r"C:\Program Files\Google\Chrome\Application\chrome.exe"),
    Path(r"C:\Program Files (x86)\Google\Chrome\Application\chrome.exe"),
]
MERMAID_JS = "https://cdn.jsdelivr.net/npm/mermaid@10.9.1/dist/mermaid.min.js"

# Lo que sirve para trabajar pero no va en la entrega: el estado de avance de cada archivo,
# el peso en la rúbrica y las secciones que citan la rúbrica como guía de redacción.
RE_ESTADO = re.compile(r"^> \*\*(Estado|Peso en la rúbrica):\*\*")
RE_RUBRICA = re.compile(r"^## Qué exige la rúbrica")
RE_OMITIR = re.compile(r"^> Versión exportable del diagrama")
RE_TITULO = re.compile(r"^(#{1,6}) ")
RE_LISTA = re.compile(r"^([-*+]|\d+\.) ")
RE_LINK = re.compile(r"(?<!!)\[([^\]]+)\]\(([^)\s]+)\)")
RE_IMAGEN = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)\)")


def es_fence(linea: str) -> bool:
    return linea.startswith("```") or linea.startswith("~~~")


def limpiar(texto: str, origen: Path, bajar_titulos: int = 0) -> str:
    """Adapta una sección del repo al documento consolidado."""
    salida: list[str] = []
    en_codigo = False
    saltando_rubrica = False

    for linea in texto.splitlines():
        if es_fence(linea):
            # python-markdown sólo reconoce el bloque si arranca después de una línea en blanco
            if not en_codigo and salida and salida[-1].strip():
                salida.append("")
            en_codigo = not en_codigo
            salida.append(linea)
            continue
        if en_codigo:
            salida.append(linea)
            continue

        if saltando_rubrica:
            if re.match(r"^#{1,2} ", linea):
                saltando_rubrica = False
            else:
                continue
        if RE_RUBRICA.match(linea):
            saltando_rubrica = True
            continue
        if RE_ESTADO.match(linea) or RE_OMITIR.match(linea):
            continue

        # Casillas de verificación → marca visible (en PDF una casilla no significa nada)
        linea = re.sub(r"^(\s*)- \[x\] ", r"\1- ✅ ", linea)
        # Listas anidadas con 2 espacios → 4, que es lo que exige python-markdown
        linea = re.sub(r"^ {2,3}(?=([-*+]|\d+\.) )", "    ", linea)

        # Links a archivos del repo → texto: en un PDF no llevan a ningún lado
        def _link(m: re.Match) -> str:
            texto_link, destino = m.group(1), m.group(2)
            if destino.startswith(("http://", "https://")):
                return m.group(0)
            return re.sub(r"`(\.\./)+", "`", texto_link)

        linea = RE_LINK.sub(_link, linea)

        # Imágenes → ruta relativa a esta carpeta (el HTML las embebe después)
        def _imagen(m: re.Match) -> str:
            absoluta = (origen.parent / m.group(2)).resolve()
            relativa = os.path.relpath(absoluta, AQUI).replace("\\", "/")
            return f"![{m.group(1)}]({relativa})"

        linea = RE_IMAGEN.sub(_imagen, linea)

        titulo = RE_TITULO.match(linea)
        if titulo and bajar_titulos:
            linea = "#" * bajar_titulos + linea

        # Tablas, listas y citas necesitan una línea en blanco antes para ser bloque
        previa = salida[-1] if salida else ""
        if previa.strip():
            empieza_tabla = linea.startswith("|") and not previa.startswith("|")
            empieza_lista = (RE_LISTA.match(linea) and not RE_LISTA.match(previa)
                             and not previa.startswith(" "))
            empieza_cita = linea.startswith(">") and not previa.startswith(">")
            if empieza_tabla or empieza_lista or empieza_cita:
                salida.append("")

        salida.append(linea)

    return "\n".join(salida).strip() + "\n"


def presentacion() -> str:
    return """# Cómo leer este documento

Responde la entrega final del segundo parcial (§7 del enunciado): las **secciones 5 y 6**, con la
misma numeración del enunciado, y el registro de prompts como anexo obligatorio. Antes va una
introducción con la **matriz de trazabilidad** de R1 a R12, y al final dos anexos más: qué partes se
tocan ante un cambio en vivo (para la defensa) y el reporte del harness sin editar.

| Parte | Qué contiene |
|---|---|
| Introducción | El sistema, el resultado (70/70) y cada requisito con su pieza y su medición |
| 5 · Decisiones | Hosting, por qué EMR, organización de los datos, el panel, la separación de cargas, los servicios y los costos, cada uno con su requisito y su pilar de Well-Architected |
| 6 · Harness | Cómo se corrió, qué dio, lo que no se pudo verificar y lo que falló en el camino |
| Anexo A | Registro de prompts |
| Anexo B | Impacto de cambios: qué se toca si el profesor pide otra regla u otra agregación |
| Anexo C | `report.md` del harness, tal cual |

El código, los scripts y la evidencia están en <REPO>, carpeta `entregas/parcial-2-panel-analitico/`.
""".replace("REPO", REPO)


def anexo_reporte() -> str:
    texto = ANEXO_REPORTE.read_text(encoding="utf-8")
    return ("# Anexo C — Reporte del harness (sin editar)\n\n"
            "Salida de `pytest` del 18/10/2026 contra lo desplegado, copiada sin cambios de "
            "`evidencia/harness-2026-10-18/report.md`. La proyección de costos que evaluó R12 ese día "
            "declaraba US$12,65; la versión entregada declara US$8,36 (ver §5.7 y §6.3).\n\n"
            + limpiar(texto, ANEXO_REPORTE, bajar_titulos=1))


def consolidar(autor: str) -> tuple[str, str]:
    """Devuelve (portada en Markdown, cuerpo en Markdown)."""
    cuerpo = [presentacion()]
    for nombre in SECCIONES:
        ruta = DOC / nombre
        cuerpo.append(limpiar(ruta.read_text(encoding="utf-8"), ruta))
    cuerpo.append(limpiar(ANEXO_PROMPTS.read_text(encoding="utf-8"), ANEXO_PROMPTS))
    cuerpo.append(limpiar(ANEXO_CAMBIOS.read_text(encoding="utf-8"), ANEXO_CAMBIOS))
    cuerpo.append(anexo_reporte())

    portada = f"""# Parcial 2 — Panel analítico de la aerolínea

**Big Data e Ingeniería de Datos (PCIA 5010)** · Universidad Sergio Arboleda

**Estudiante:** {autor} · **Modalidad:** individual · **Semilla:** 12345 · **Fecha:** {FECHA}

**Repositorio:** <{REPO}> — carpeta `entregas/parcial-2-panel-analitico/`

> Archivo generado por `entrega/construir_documento.py` a partir de `documento/`.
"""
    return portada, "\n\n".join(cuerpo)


# ─── HTML ──────────────────────────────────────────────────────────────────────

CSS = """
@page { size: A4; margin: 15mm 15mm 16mm 15mm;
        @bottom-center { content: counter(page); font: 8.5pt 'Segoe UI', sans-serif; color: #777; } }
@page :first { @bottom-center { content: none; } }
* { box-sizing: border-box; }
html { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
body { font: 10pt/1.45 'Segoe UI', system-ui, -apple-system, Arial, sans-serif; color: #1f2328;
       background: #fff; margin: 0 auto; max-width: 190mm; padding: 0 2mm; }
h1, h2, h3, h4 { color: #0f3a66; line-height: 1.25; page-break-after: avoid; break-after: avoid; }
h1 { font-size: 19pt; border-bottom: 2px solid #0f3a66; padding-bottom: 4px; margin: 0 0 12px;
     page-break-before: always; break-before: page; }
h2 { font-size: 13.5pt; margin: 17px 0 7px; border-bottom: 1px solid #d0d7de; padding-bottom: 2px; }
h3 { font-size: 11.5pt; margin: 16px 0 6px; }
h4 { font-size: 10.5pt; margin: 14px 0 6px; }
p { margin: 6px 0; }
a { color: #0b5cad; text-decoration: none; }
code { font-family: Consolas, 'Cascadia Mono', monospace; font-size: 0.88em; background: #f2f4f7;
       padding: 0 3px; border-radius: 3px; overflow-wrap: break-word; }
pre { background: #f6f8fa; border: 1px solid #e1e4e8; border-radius: 4px; padding: 7px 9px;
      font-size: 7.8pt; line-height: 1.35; white-space: pre-wrap; overflow-wrap: break-word;
      page-break-inside: avoid; break-inside: avoid; }
pre code { background: none; padding: 0; font-size: 1em; }
pre.mermaid { background: none; border: none; text-align: center; font-size: 10pt; white-space: pre; }
pre.mermaid svg { width: 100%; max-width: 100% !important; max-height: 225mm; height: auto; }
blockquote { margin: 8px 0; padding: 4px 11px; border-left: 3px solid #8fb0d8; background: #f4f8fc;
             color: #2d333b; page-break-inside: avoid; break-inside: avoid; }
blockquote p { margin: 4px 0; }
table { width: 100%; border-collapse: collapse; margin: 8px 0 10px; font-size: 8.6pt; line-height: 1.35; }
thead { display: table-header-group; }
tr { page-break-inside: avoid; break-inside: avoid; }
th, td { border: 1px solid #c8d1dc; padding: 3px 5px; vertical-align: top; text-align: left; }
th { background: #e9eff6; color: #0f3a66; }
td code, th code { font-size: 0.92em; }
img { width: 100%; max-width: 100%; display: block; margin: 8px auto; }   /* sólo hay diagramas */
ul, ol { margin: 5px 0; padding-left: 22px; }
li { margin: 2px 0; }
hr { border: none; border-top: 1px solid #d0d7de; margin: 14px 0; }

.portada { height: 255mm; display: flex; flex-direction: column; justify-content: center;
           text-align: center; page-break-after: always; break-after: page; }
.portada .institucion { font-size: 12pt; letter-spacing: .5px; color: #555; margin-bottom: 36mm; }
.portada .materia { font-size: 12pt; color: #0f3a66; font-weight: 600; }
.portada .titulo { font-size: 26pt; color: #0f3a66; font-weight: 700; margin: 8mm 0 3mm; line-height: 1.2; }
.portada .subtitulo { font-size: 12pt; color: #444; max-width: 140mm; margin: 0 auto; }
.portada .datos { margin-top: 40mm; font-size: 11pt; line-height: 1.8; }
.portada .datos code { font-size: 0.85em; }
.indice h2 { border: none; font-size: 16pt; margin-top: 0; }
.indice ol { column-count: 2; column-gap: 9mm; padding-left: 0; list-style: none; margin: 0; font-size: 9.5pt; }
.indice > ol > li { break-inside: avoid; margin-bottom: 7px; }
.indice > ol > li > a { font-weight: 600; color: #0f3a66; }
.indice ol ol { column-count: 1; padding-left: 12px; margin: 2px 0 0; font-size: 8.8pt; }
.indice ol ol li { margin: 1px 0; }
.indice ol ol a { color: #333; }
"""

# Secciones que se repiten en todos los capítulos: en el índice sólo agregarían ruido
TOC_OMITIR = re.compile(r"^(Defensa: qué se rompe|Preguntas guía)")


def a_html(md: str) -> str:
    return markdown.markdown(md, extensions=["tables", "fenced_code", "sane_lists"],
                             output_format="html")


def indice_y_anclas(cuerpo_html: str) -> tuple[str, str]:
    """Numera h1/h2 con anclas propias y arma el índice (h1 + h2 relevantes)."""
    entradas: list[tuple[int, str, str]] = []
    contador = {"n": 0}

    def _ancla(m: re.Match) -> str:
        nivel, contenido = int(m.group(1)), m.group(2)
        contador["n"] += 1
        ancla = f"s{contador['n']}"
        texto_plano = re.sub(r"<[^>]+>", "", contenido)
        if nivel == 1 or not TOC_OMITIR.match(texto_plano):
            entradas.append((nivel, ancla, contenido))
        return f'<h{nivel} id="{ancla}">{contenido}</h{nivel}>'

    cuerpo = re.sub(r"<h([12])>(.*?)</h\1>", _ancla, cuerpo_html)

    html_indice = ['<nav class="indice"><h2>Contenido</h2><ol>']
    abierta = False
    for nivel, ancla, contenido in entradas:
        if nivel == 1:
            if abierta:
                html_indice.append("</ol></li>")
            html_indice.append(f'<li><a href="#{ancla}">{contenido}</a><ol>')
            abierta = True
        else:
            html_indice.append(f'<li><a href="#{ancla}">{contenido}</a></li>')
    if abierta:
        html_indice.append("</ol></li>")
    html_indice.append("</ol></nav>")
    return "".join(html_indice), cuerpo


def embeber_imagenes(html: str) -> str:
    def _src(m: re.Match) -> str:
        src = m.group(1)
        if src.startswith(("http", "data:")):
            return m.group(0)
        ruta = (AQUI / src).resolve()
        datos = base64.b64encode(ruta.read_bytes()).decode("ascii")
        return f'src="data:image/{ruta.suffix.lstrip(".").lower()};base64,{datos}"'

    return re.sub(r'src="([^"]+)"', _src, html)


def construir_html(autor: str, cuerpo_md: str) -> str:
    cuerpo = a_html(cuerpo_md)
    # Mermaid lee el texto del bloque y lo reemplaza por un SVG al cargar la página
    cuerpo = re.sub(r'<pre><code class="language-mermaid">(.*?)</code></pre>',
                    r'<pre class="mermaid">\1</pre>', cuerpo, flags=re.S)
    indice, cuerpo = indice_y_anclas(cuerpo)
    cuerpo = embeber_imagenes(cuerpo)
    # El primer h1 del cuerpo va después del índice, que ya abre página propia
    portada = f"""
<section class="portada">
  <div class="institucion">UNIVERSIDAD SERGIO ARBOLEDA</div>
  <div class="materia">Big Data e Ingeniería de Datos · PCIA 5010</div>
  <div class="titulo">Parcial 2<br>Panel analítico de la aerolínea</div>
  <div class="subtitulo">Documento final: decisiones y su justificación (§5), ejecución del harness
    (§6), registro de prompts, impacto de cambios y reporte del harness</div>
  <div class="datos">
    <div><strong>Estudiante:</strong> {autor}</div>
    <div><strong>Modalidad:</strong> individual · <strong>Semilla:</strong> 12345 · <strong>Fecha:</strong> {FECHA}</div>
    <div><strong>Harness sobre lo desplegado:</strong> 70,0 / 70,0</div>
    <div><strong>Repositorio:</strong> {REPO.replace("https://", "")}<br>
      carpeta <code>entregas/parcial-2-panel-analitico/</code></div>
  </div>
</section>"""
    return f"""<!doctype html>
<html lang="es"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Parcial 2 — Panel analítico de la aerolínea</title>
<style>{CSS}</style>
</head><body>
{portada}
{indice}
{cuerpo}
<script src="{MERMAID_JS}"></script>
<script>
  // Letra del ER más grande que la de fábrica: el diagrama se imprime a ancho de página y, con
  // 14 entidades, a 12 px los nombres quedaban ilegibles en papel.
  mermaid.initialize({{ startOnLoad: true, theme: "neutral", securityLevel: "strict",
    er: {{ useMaxWidth: true, fontSize: 20, entityPadding: 10 }},
    sequence: {{ useMaxWidth: true }} }});
</script>
</body></html>
"""


def imprimir_pdf(html_path: Path, pdf_path: Path) -> bool:
    chrome = next((c for c in CHROME if c.exists()), None)
    if chrome is None:
        print("[!] Chrome no encontrado: se omite el PDF")
        return False
    with tempfile.TemporaryDirectory(ignore_cleanup_errors=True) as perfil:
        subprocess.run(
            [str(chrome), "--headless=new", "--disable-gpu", "--no-pdf-header-footer",
             "--run-all-compositor-stages-before-draw", "--virtual-time-budget=30000",
             f"--user-data-dir={perfil}", f"--print-to-pdf={pdf_path}", html_path.as_uri()],
            check=True, timeout=240, capture_output=True,
        )
    return pdf_path.exists()


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--autor", default=AUTOR)
    ap.add_argument("--sin-pdf", action="store_true", help="genera sólo .md y .html")
    args = ap.parse_args()

    portada_md, cuerpo_md = consolidar(args.autor)

    ruta_md = AQUI / f"{NOMBRE}.md"
    ruta_md.write_text(portada_md + "\n" + cuerpo_md, encoding="utf-8")
    print(f"[ok] {ruta_md.name}")

    ruta_html = AQUI / f"{NOMBRE}.html"
    ruta_html.write_text(construir_html(args.autor, cuerpo_md), encoding="utf-8")
    print(f"[ok] {ruta_html.name}")

    if not args.sin_pdf:
        ruta_pdf = AQUI / f"{NOMBRE}.pdf"
        if imprimir_pdf(ruta_html, ruta_pdf):
            print(f"[ok] {ruta_pdf.name}  ({ruta_pdf.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()
