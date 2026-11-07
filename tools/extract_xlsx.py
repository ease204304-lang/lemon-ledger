"""Dump XLSX (test checklist + traceability) to UTF-8 text."""
import sys
import io
import openpyxl

src, dst = sys.argv[1], sys.argv[2]
wb = openpyxl.load_workbook(src, data_only=True)
with io.open(dst, "w", encoding="utf-8") as out:
    for ws in wb.worksheets:
        out.write("=" * 70 + "\n")
        out.write(f"### SHEET: {ws.title}  ({ws.max_row}r x {ws.max_column}c)\n")
        out.write("=" * 70 + "\n")
        for ri, row in enumerate(ws.iter_rows(values_only=True), 1):
            cells = ["" if c is None else str(c).strip().replace("\n", " / ") for c in row]
            while cells and cells[-1] == "":
                cells.pop()
            if not cells:
                continue
            out.write(f"R{ri}: " + " | ".join(cells) + "\n")
        out.write("\n")
print(f"wrote {dst}")
