"""Extract text from requirement DOCX files -> UTF-8 file (no console encoding issues)."""
import sys
import io
from docx import Document
from docx.table import Table
from docx.text.paragraph import Paragraph
from docx.oxml.ns import qn


def iter_block_items(parent):
    body = parent.element.body
    for child in body.iterchildren():
        if child.tag == qn('w:p'):
            yield Paragraph(child, parent)
        elif child.tag == qn('w:tbl'):
            yield Table(child, parent)


def dump(path, out):
    out.write("=" * 70 + "\n")
    out.write(f"### FILE: {path}\n")
    out.write("=" * 70 + "\n")
    doc = Document(path)
    ti = 0
    for block in iter_block_items(doc):
        if isinstance(block, Paragraph):
            txt = block.text.strip()
            if txt:
                style = block.style.name if block.style else ""
                prefix = f"[{style}] " if style and style != "Normal" else ""
                out.write(f"{prefix}{txt}\n")
        else:
            ti += 1
            out.write(f"\n--- TABLE {ti} ({len(block.rows)}r x {len(block.columns)}c) ---\n")
            for ri, row in enumerate(block.rows):
                cells = [c.text.strip().replace("\n", " / ") for c in row.cells]
                out.write(f"  R{ri}: " + " | ".join(cells) + "\n")
            out.write("--- END TABLE ---\n\n")


src, dst = sys.argv[1], sys.argv[2]
with io.open(dst, "w", encoding="utf-8") as out:
    dump(src, out)
print(f"wrote {dst}")
