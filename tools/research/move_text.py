#!/usr/bin/env python3
"""Decode the character command lists (ARC member 4) of the USA release to text.

The USA executable draws member-4 strings with `MoveTextDraw` (0x80077724 in
SLUS_004.02). Its byte encoding:

* 0x20-0x7F: ASCII, drawn from the 6 x 12 font in the member-0 atlas
  (glyph c = byte - 0x20 at u = 6 * (c & 15), v = 12 * (c >> 6), bit plane (c >> 4) & 3);
* 0x01-0x1F and 0xA1-0xC3: pre-rendered words from the same atlas; their width in
  characters comes from EXE tables. This tool reads them back by matching each 6-pixel
  cell against the ASCII glyphs, so no text is stored here;
* 0x80-0x90: direction arrows: index & 7 = db, d, df, b, f, ub, u, uf; +8 = held (upper
  case); 16 = neutral (printed as "N");
* 0x91-0xA0: button diagram, index = mask (1 LP, 2 RP, 4 LK, 8 RK), printed as "1+3" etc.;
* 0x20, 0xFB, 0xFD, 0xFE: spaces of 1, 10, 2 and 1 cells; 0xFC: new line; 0xFF: escape.

The output contains game text; print it locally only.
Usage: python3 tools/research/move_text.py [--arc-id 73]
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
USA_EXE_BASE = 0x80010000
EXE_HEADER = 0x800
WIDTH_LOW = 0x800989F7      # widths of word strips 0x01-0x1F (in cells)
WIDTH_HIGH = 0x80098976     # widths of word strips 0xA1-0xC3 (index = byte)
CELL_W, CELL_H = 6, 12
DIRECTIONS = ("db", "d", "df", "b", "f", "ub", "u", "uf")


def arrow(index: int) -> str:
    if index == 16:
        return "N"
    name = DIRECTIONS[index & 7]
    return name.upper() if index & 8 else name


def buttons(mask: int) -> str:
    return "+".join(str(i + 1) for i in range(4) if mask & (1 << i)) or "?"


def arc_members(data: bytes) -> list[bytes]:
    """Members of a Tekken 3 `.arc` archive: `u32 count`, then `(offset, size)` pairs."""
    count = struct.unpack_from("<I", data, 0)[0]
    return [data[o:o + s] for o, s in (struct.unpack_from("<II", data, 4 + 8 * i) for i in range(count))]


class Atlas:
    def __init__(self, tim: bytes) -> None:
        _, _, _, width_words, height = struct.unpack_from("<I4H", tim, 8)
        self.width, self.height = width_words * 4, height
        self.pixels = tim[20:20 + 2 * width_words * height]

    def nibble(self, x: int, y: int) -> int:
        if not (0 <= x < self.width and 0 <= y < self.height):
            return 0
        i = y * self.width + x
        return (self.pixels[i // 2] >> (4 * (i & 1))) & 15

    def cell(self, x: int, y: int, plane: int) -> tuple:
        return tuple((self.nibble(x + dx, y + dy) >> plane) & 1 for dy in range(CELL_H) for dx in range(CELL_W))


def ascii_font(atlas: Atlas) -> dict[tuple, str]:
    font = {}
    for code in range(0x21, 0x7F):
        c = code - 0x20
        bitmap = atlas.cell(CELL_W * (c & 15), CELL_H * (c >> 6), (c >> 4) & 3)
        if any(bitmap):
            font.setdefault(bitmap, chr(code))
    return font


def read_strip(atlas: Atlas, font: dict, x: int, y: int, plane: int, cells: int) -> str:
    out = []
    for i in range(cells):
        bitmap = atlas.cell(x + CELL_W * i, y, plane)
        out.append(font.get(bitmap, " " if not any(bitmap) else "?"))
    return "".join(out).strip()


def strip_origin(byte: int) -> tuple[int, int, int]:
    """Atlas (x, y, plane) of a word strip, following MoveTextDraw."""
    if byte < 0x20:
        return 0, CELL_H * ((byte + 5) >> 2), (byte + 1) & 3
    if byte - 0x82 <= 0x21:
        return 0, CELL_H * ((byte - 0x7C) >> 2), (byte - 0x80) & 3
    return 0x3C, CELL_H * ((byte - 0x9C) >> 2), (byte - 0xA4) & 3


def decode(text: bytes, atlas: Atlas, font: dict, exe: bytes) -> str:
    out = []
    for b in text:
        if b in (0x20, 0xFE):
            out.append(" ")
        elif b == 0xFD:
            out.append("  ")
        elif b == 0xFB:
            out.append(" " * 10)
        elif b == 0xFC:
            out.append(" / ")
        elif 0x80 <= b <= 0x90:
            out.append(arrow(b - 0x80) + ",")
        elif 0x91 <= b <= 0xA0:
            out.append(buttons(b - 0x91) + ",")
        elif 0x21 <= b <= 0x7F:
            out.append(chr(b))
        elif 1 <= b < 0x20 or 0xA1 <= b <= 0xC3:
            table = WIDTH_LOW if b < 0x20 else WIDTH_HIGH
            cells = exe[table + b - USA_EXE_BASE + EXE_HEADER]
            x, y, plane = strip_origin(b)
            out.append("{" + read_strip(atlas, font, x, y, plane, cells) + "}")
        else:
            out.append(f"<{b:02X}>")
    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--arc-id", type=int, action="append", help="character ARC BNS id (73 + 4n)")
    args = parser.parse_args()
    exe = (ROOT / "work" / "usa" / "exe.bin").read_bytes()
    for arc_id in args.arc_id or range(73, 278, 4):
        path = next((ROOT / "work" / "usa" / "bns").glob(f"{arc_id:03d}_*.arc"), None)
        if path is None:
            continue
        members = arc_members(path.read_bytes())
        if len(members) < 5 or not members[4] or not members[0].startswith(b"\x10\0\0\0"):
            continue
        atlas = Atlas(members[0])
        font = ascii_font(atlas)
        fields = members[4][1:].split(b"\0")[: 2 * members[4][0]]
        print(f"== {path.name}")
        for name, command in zip(fields[::2], fields[1::2]):
            command_text = decode(command, atlas, font, exe).rstrip(",").replace(",+", "+")
            print(f"{decode(name, atlas, font, exe):40s} {command_text}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
