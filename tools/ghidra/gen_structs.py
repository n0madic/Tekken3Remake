#!/usr/bin/env python3
"""Generate the Fighter struct from fighter_fields.tsv.

Fields are placed at their verified offsets; gaps become unkXXX byte arrays.
The C struct replaces the block between the BEGIN/END markers in tekken3.h;
the same fields are written as a Markdown table into the fighter field
reference (docs/research/code/fighter.md).
"""

from __future__ import annotations

import re
from pathlib import Path

HERE = Path(__file__).resolve().parent
FIGHTER_SIZE = 0x188C
SIZES = {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4, "void*": 4}
KNOWN_STRUCTS = {"FighterPart": 0x28}
BEGIN = "/* BEGIN generated Fighter */"
END = "/* END generated Fighter */"
DOC = HERE.parents[1] / "docs" / "research" / "code" / "fighter.md"
DOC_BEGIN = "<!-- BEGIN generated fields -->"
DOC_END = "<!-- END generated fields -->"


def field_size(ctype: str) -> tuple[str, int, int]:
    """Return (base type, element size, count)."""
    m = re.fullmatch(r"(\w+\*?)\[(\d+)\]", ctype)
    base, count = (m.group(1), int(m.group(2))) if m else (ctype, 1)
    size = SIZES.get(base) or KNOWN_STRUCTS[base]
    return base, size, count


def read_fields() -> list[tuple[int, str, str, str]]:
    rows = []
    for line in (HERE / "fighter_fields.tsv").read_text().splitlines():
        if not line.strip() or line.startswith("#"):
            continue
        parts = line.split("\t")
        rows.append((int(parts[0], 16), parts[1], parts[2], parts[3] if len(parts) > 3 else ""))
    return sorted(rows)


def generate_markdown(rows: list[tuple[int, str, str, str]]) -> str:
    out = [DOC_BEGIN, "| Offset | Type | Name | Meaning |", "|---:|---|---|---|"]
    for off, ctype, name, comment in rows:
        out.append(f"| `+0x{off:04X}` | `{ctype}` | `{name}` | {comment.replace('|', '/')} |")
    out.append(DOC_END)
    return "\n".join(out)


def replace_block(text: str, begin: str, end: str, block: str) -> str:
    if begin in text:
        return text[: text.index(begin)] + block + text[text.index(end) + len(end):]
    return text.rstrip() + "\n\n" + block + "\n"


def generate(rows: list[tuple[int, str, str, str]]) -> str:
    out = [BEGIN, "typedef struct Fighter {"]
    pos = 0
    for off, ctype, name, comment in rows:
        if off < pos:
            raise ValueError(f"field {name} at {off:#x} overlaps previous field (ends {pos:#x})")
        if off > pos:
            out.append(f"    u8 unk{pos:04X}[{off - pos}];")
        base, size, count = field_size(ctype)
        decl = f"{base} {name}" + (f"[{count}]" if count > 1 else "") + ";"
        out.append(f"    {decl:<34} /* +0x{off:04X}{' ' + comment if comment else ''} */")
        pos = off + size * count
    if pos < FIGHTER_SIZE:
        out.append(f"    u8 unk{pos:04X}[{FIGHTER_SIZE - pos}];")
    out += ["} Fighter;", END]
    return "\n".join(out)


def main() -> int:
    rows = read_fields()
    header = HERE / "tekken3.h"
    header.write_text(replace_block(header.read_text(), BEGIN, END, generate(rows)))
    if DOC.exists():
        DOC.write_text(replace_block(DOC.read_text(), DOC_BEGIN, DOC_END, generate_markdown(rows)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
