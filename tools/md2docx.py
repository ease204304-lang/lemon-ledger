#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
md2docx.py —— 把 docs/*.md 渲染为正式 Word 文档。

用法：
    python tools/md2docx.py docs/01-软件需求说明书-SRS.md deliverables/01-软件需求说明书-SRS.docx

支持语法：ATX 标题、段落、无序/有序列表、GFM 表格（含代码跨度内的竖线）、
围栏代码块、引用块、水平线，以及行内 **粗体**、`代码`、[文本](链接)。
中文字体通过 w:eastAsia 显式指定，避免 Word 中文字形回退。
"""
import re
import sys
from pathlib import Path

from docx import Document
from docx.enum.section import WD_ORIENT, WD_SECTION
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml import OxmlElement
from docx.oxml.ns import qn
from docx.shared import Cm, Pt, RGBColor

LANDSCAPE_MIN_COLS = 8          # 列数 ≥ 8 的表格放到横向分节，避免纵向 A4 挤压

CJK = "微软雅黑"
MONO = "Courier New"
BODY_PT = 10.5
TABLE_PT = 9.0
CODE_PT = 8.5

INK = RGBColor(0x1A, 0x1A, 0x1A)
GREY = RGBColor(0x60, 0x60, 0x60)
BRAND = RGBColor(0xB3, 0x8A, 0x00)


# --------------------------------------------------------------------------
# 基础工具
# --------------------------------------------------------------------------
def set_font(run, name=CJK, size=None, bold=None, italic=None, color=None, mono=False):
    """同时设置 ascii / hAnsi / eastAsia 字体，保证中文不回退。"""
    fam = MONO if mono else name
    run.font.name = fam
    rpr = run._element.get_or_add_rPr()
    rf = rpr.find(qn("w:rFonts"))
    if rf is None:
        rf = OxmlElement("w:rFonts")
        rpr.append(rf)
    for attr in ("w:ascii", "w:hAnsi", "w:eastAsia", "w:cs"):
        rf.set(qn(attr), fam)
    if size is not None:
        run.font.size = Pt(size)
    if bold is not None:
        run.bold = bold
    if italic is not None:
        run.font.italic = italic
    if color is not None:
        run.font.color.rgb = color
    return run


def shade(cell_or_paragraph, hex_fill):
    """给单元格或段落加底纹。"""
    el = cell_or_paragraph._element
    pr = el.find(qn("w:tcPr")) if el.tag.endswith("}tc") else el.get_or_add_pPr()
    if pr is None:
        pr = OxmlElement("w:tcPr")
        el.insert(0, pr)
    sh = OxmlElement("w:shd")
    sh.set(qn("w:val"), "clear")
    sh.set(qn("w:color"), "auto")
    sh.set(qn("w:fill"), hex_fill)
    pr.append(sh)


def add_field(paragraph, instr):
    run = paragraph.add_run()
    f1 = OxmlElement("w:fldChar"); f1.set(qn("w:fldCharType"), "begin")
    it = OxmlElement("w:instrText"); it.set(qn("xml:space"), "preserve"); it.text = instr
    f2 = OxmlElement("w:fldChar"); f2.set(qn("w:fldCharType"), "end")
    run._element.append(f1); run._element.append(it); run._element.append(f2)
    set_font(run, size=8.5, color=GREY)


def split_row(line):
    """按 | 切分表格行，但忽略 `代码跨度` 内的竖线（如 `|` 分隔）。"""
    line = line.strip()
    if line.startswith("|"):
        line = line[1:]
    if line.endswith("|"):
        line = line[:-1]
    out, buf, tick = [], [], False
    for ch in line:
        if ch == "`":
            tick = not tick
            buf.append(ch)
        elif ch == "|" and not tick:
            out.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    out.append("".join(buf).strip())
    return out


def is_sep_row(cells):
    return all(re.fullmatch(r":?-{2,}:?", c.replace(" ", "")) for c in cells if c != "") and len(cells) > 0


INLINE = re.compile(r"(\*\*.+?\*\*|`[^`]+`|\[[^\]]+\]\([^)]*\))")


def add_inline(paragraph, text, size=BODY_PT, base_bold=False, color=INK):
    """解析行内语法并写入段落。"""
    text = re.sub(r"\[([^\]]+)\]\([^)]*\)", r"\1", text)
    for part in INLINE.split(text):
        if not part:
            continue
        if part.startswith("**") and part.endswith("**") and len(part) > 4:
            set_font(paragraph.add_run(part[2:-2]), size=size, bold=True, color=color)
        elif part.startswith("`") and part.endswith("`") and len(part) > 2:
            r = paragraph.add_run(part[1:-1])
            set_font(r, size=size - 1, mono=True, color=BRAND, bold=base_bold)
        else:
            set_font(paragraph.add_run(part), size=size, bold=base_bold, color=color)


# --------------------------------------------------------------------------
# 块级渲染
# --------------------------------------------------------------------------
def heading(doc, level, text):
    sizes = {1: 20, 2: 15, 3: 12.5, 4: 11}
    p = doc.add_paragraph()
    p.paragraph_format.space_before = Pt(14 if level <= 2 else 10)
    p.paragraph_format.space_after = Pt(6 if level <= 2 else 4)
    p.paragraph_format.keep_with_next = True
    if level == 1:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    add_inline(p, text, size=sizes.get(level, 11), base_bold=True)
    for r in p.runs:
        set_font(r, size=sizes.get(level, 11), bold=True, color=INK if level > 1 else RGBColor(0, 0, 0))
        r.font.name = CJK
    if level <= 2:
        pPr = p._element.get_or_add_pPr()
        bdr = OxmlElement("w:pBdr")
        bot = OxmlElement("w:bottom")
        bot.set(qn("w:val"), "single"); bot.set(qn("w:sz"), "6")
        bot.set(qn("w:space"), "4"); bot.set(qn("w:color"), "FFD946")
        bdr.append(bot); pPr.append(bdr)
    return p


def paragraph(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.25
    add_inline(p, text)
    return p


def bullet(doc, text, ordered=False, level=0):
    p = doc.add_paragraph(style="List Number" if ordered else "List Bullet")
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.left_indent = Cm(0.75 + 0.6 * level)
    p.paragraph_format.line_spacing = 1.2
    add_inline(p, text)
    return p


def quote(doc, text):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Cm(0.6)
    p.paragraph_format.space_after = Pt(4)
    add_inline(p, text, size=BODY_PT - 0.5, color=GREY)
    return p


def code_block(doc, lines):
    p = doc.add_paragraph()
    p.paragraph_format.left_indent = Cm(0.4)
    p.paragraph_format.space_before = Pt(4)
    p.paragraph_format.space_after = Pt(6)
    p.paragraph_format.line_spacing = 1.0
    shade(p, "F7F7F7")
    for i, ln in enumerate(lines):
        r = p.add_run(ln)
        set_font(r, size=CODE_PT, mono=True, color=RGBColor(0x2A, 0x2A, 0x2A))
        if i < len(lines) - 1:
            r.add_break()
    return p


def setup_section(sec, landscape, footer_text):
    """统一页面设置与页脚（每新增分节都要重设，否则页脚不继承）。"""
    if landscape:
        sec.orientation = WD_ORIENT.LANDSCAPE
        sec.page_width, sec.page_height = Cm(29.7), Cm(21.0)
        sec.left_margin = sec.right_margin = Cm(1.6)
        sec.top_margin = Cm(1.6)
        sec.bottom_margin = Cm(1.5)
    else:
        sec.orientation = WD_ORIENT.PORTRAIT
        sec.page_width, sec.page_height = Cm(21.0), Cm(29.7)
        sec.left_margin = sec.right_margin = Cm(2.2)
        sec.top_margin = Cm(2.2)
        sec.bottom_margin = Cm(2.0)
    sec.header_distance = Cm(1.1)
    sec.footer_distance = Cm(1.1)
    fp = sec.footer.paragraphs[0]
    fp.alignment = WD_ALIGN_PARAGRAPH.CENTER
    for r in list(fp.runs):
        r._element.getparent().remove(r._element)
    set_font(fp.add_run(footer_text + "    第 "), size=8.5, color=GREY)
    add_field(fp, " PAGE ")
    set_font(fp.add_run(" 页 / 共 "), size=8.5, color=GREY)
    add_field(fp, " NUMPAGES ")
    set_font(fp.add_run(" 页"), size=8.5, color=GREY)


def set_table_widths(t, col_cm):
    """固定布局 + 显式列宽。必须同时改写 tblW / tblLayout / tblGrid，
    否则 LibreOffice 与 Word 会按模板默认（Letter 纵向）宽度渲染并横向溢出。

    注意：w:tblLayout 必须由 python-docx 的 autofit API 写入，保证其落在
    OOXML 规定的 w:jc 之后；手工 append 会破坏元素顺序，LibreOffice 将忽略
    固定布局并退化为按内容自适应，导致列宽失效、表格溢出页面。
    """
    tbl = t._tbl
    tblPr = tbl.tblPr
    total = sum(col_cm)

    for el in tblPr.findall(qn("w:tblW")):
        tblPr.remove(el)
    tw = OxmlElement("w:tblW")
    tw.set(qn("w:w"), str(int(total * 567)))
    tw.set(qn("w:type"), "dxa")
    anchor = tblPr.find(qn("w:tblStyle"))
    if anchor is not None:
        anchor.addnext(tw)          # schema 要求 tblW 在 jc / tblLayout 之前
    else:
        tblPr.insert(0, tw)

    t.autofit = False               # 由 python-docx 按 schema 顺序写入 tblLayout=fixed

    grid = tbl.find(qn("w:tblGrid"))
    if grid is not None:
        for gc, w in zip(grid.findall(qn("w:gridCol")), col_cm):
            gc.set(qn("w:w"), str(int(w * 567)))


def picture(doc, path, width_cm=7.0):
    """插入图片并居中；路径相对于 Markdown 文件所在目录。"""
    if not path.exists():
        p = doc.add_paragraph()
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
        set_font(p.add_run(f"[缺图] {path.name}"), size=9, color=GREY)
        return
    p = doc.add_paragraph()
    p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    p.paragraph_format.space_before = Pt(6)
    p.paragraph_format.space_after = Pt(2)
    p.add_run().add_picture(str(path), width=Cm(width_cm))


def table(doc, rows, state, footer_text):
    ncol = max(len(r) for r in rows)
    rows = [r + [""] * (ncol - len(r)) for r in rows]

    # 宽表自动进入横向分节；连续宽表共用同一分节，避免插入空白页
    want_land = ncol >= LANDSCAPE_MIN_COLS
    if want_land and not state["land"]:
        setup_section(doc.add_section(WD_SECTION.NEW_PAGE), True, footer_text)
        state["land"] = True
    elif not want_land and state["land"]:
        setup_section(doc.add_section(WD_SECTION.NEW_PAGE), False, footer_text)
        state["land"] = False

    t = doc.add_table(rows=len(rows), cols=ncol)
    t.style = "Table Grid"
    t.alignment = WD_TABLE_ALIGNMENT.LEFT   # 左对齐 + 固定列宽，保证不越过右页边距
    t.autofit = False

    # 固定布局 + 显式列宽：避免宽表溢出页面（LibreOffice/Word 都按此渲染）
    usable_cm = 26.5 if want_land else 16.6
    weights = [max(4.0, min(float(max(len(r[j]) for r in rows)), 42.0)) for j in range(ncol)]
    total_w = sum(weights)
    col_cm = [usable_cm * w / total_w for w in weights]
    set_table_widths(t, col_cm)

    size = TABLE_PT if ncol <= 5 else (TABLE_PT - 0.5 if ncol <= 7 else TABLE_PT - 1.5)
    for i, row in enumerate(rows):
        for j, val in enumerate(row):
            cell = t.cell(i, j)
            cell.text = ""
            cell.width = Cm(col_cm[j])
            p = cell.paragraphs[0]
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.space_before = Pt(0)
            p.paragraph_format.line_spacing = 1.05
            add_inline(p, val, size=size, base_bold=(i == 0),
                       color=INK if i == 0 else RGBColor(0x33, 0x33, 0x33))
            if i == 0:
                shade(cell, "FFF3C4")
    # 表后留白
    doc.add_paragraph().paragraph_format.space_after = Pt(2)
    return t


def hr(doc):
    p = doc.add_paragraph()
    pPr = p._element.get_or_add_pPr()
    bdr = OxmlElement("w:pBdr")
    bot = OxmlElement("w:bottom")
    bot.set(qn("w:val"), "single"); bot.set(qn("w:sz"), "6")
    bot.set(qn("w:space"), "1"); bot.set(qn("w:color"), "DDDDDD")
    bdr.append(bot); pPr.append(bdr)
    p.paragraph_format.space_after = Pt(2)


# --------------------------------------------------------------------------
# 主流程
# --------------------------------------------------------------------------
def build(md_path: Path, docx_path: Path, footer_text: str):
    lines = md_path.read_text(encoding="utf-8").splitlines()
    doc = Document()
    state = {"land": False}

    setup_section(doc.sections[0], False, footer_text)

    normal = doc.styles["Normal"]
    normal.font.name = CJK
    normal.font.size = Pt(BODY_PT)
    normal.element.rPr.rFonts.set(qn("w:eastAsia"), CJK)

    i, n = 0, len(lines)
    first_h1_done = False
    while i < n:
        raw = lines[i]
        line = raw.rstrip()
        stripped = line.strip()

        # 围栏代码块
        if stripped.startswith("```"):
            i += 1
            buf = []
            while i < n and not lines[i].strip().startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            code_block(doc, buf)
            continue

        # 表格
        if stripped.startswith("|") and i + 1 < n and set(lines[i + 1].strip()) <= set("|-: "):
            block = []
            while i < n and lines[i].strip().startswith("|"):
                block.append(split_row(lines[i]))
                i += 1
            header = block[0]
            body = [r for r in block[1:] if not is_sep_row(r)]
            table(doc, [header] + body, state, footer_text)
            continue

        if not stripped:
            i += 1
            continue

        # 水平线
        if re.fullmatch(r"-{3,}|\*{3,}|_{3,}", stripped):
            hr(doc)
            i += 1
            continue

        # 图片：![alt](相对路径) 或 ![alt](相对路径 =8cm)
        m = re.match(r"^!\[[^\]]*\]\(([^)]+)\)\s*$", stripped)
        if m:
            raw = m.group(1).strip()
            w = 7.0
            if "=" in raw:
                raw, _, wv = raw.rpartition("=")
                try:
                    w = float(wv.strip().rstrip("cm"))
                except ValueError:
                    w = 7.0
            target = (md_path.parent / raw.strip()).resolve()
            picture(doc, target, w)
            i += 1
            continue

        # 标题
        m = re.match(r"^(#{1,6})\s+(.*)$", stripped)
        if m:
            lvl, text = len(m.group(1)), m.group(2).strip()
            if lvl == 1 and not first_h1_done:
                first_h1_done = True
                doc.add_paragraph().paragraph_format.space_after = Pt(0)
            heading(doc, lvl, text)
            i += 1
            continue

        # 引用
        if stripped.startswith(">"):
            quote(doc, stripped.lstrip("> ").strip())
            i += 1
            continue

        # 列表
        m = re.match(r"^(\s*)[-*+]\s+(.*)$", raw)
        if m:
            bullet(doc, m.group(2).strip(), ordered=False, level=len(m.group(1)) // 2)
            i += 1
            continue
        m = re.match(r"^(\s*)(\d+)\.\s+(.*)$", raw)
        if m:
            bullet(doc, m.group(3).strip(), ordered=True, level=len(m.group(1)) // 2)
            i += 1
            continue

        paragraph(doc, stripped)
        i += 1

    docx_path.parent.mkdir(parents=True, exist_ok=True)
    doc.save(str(docx_path))
    return docx_path


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        return 2
    src, dst = Path(sys.argv[1]), Path(sys.argv[2])
    name = sys.argv[3] if len(sys.argv) > 3 else src.stem
    out = build(src, dst, name)
    print(f"OK  {out}  ({out.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
