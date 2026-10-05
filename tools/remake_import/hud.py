"""The fight HUD's sprites (hud.md#elements) → PNGs through their CLUTs.

The HUD draws 4-bit sprites and stretched quads from two system texture pages (tpage 0x0D at
VRAM (832, 0) and 0x0E at (896, 0)) and each fighter's name from its own texture page:

- health bar: the end caps (6 × 24 at UV (0xE0, 0xA8) and (0xEA, 0xA8), CLUT 0x7EDE) and the
  fill column (UV 0xE8, rows 0xA8–0xBF) stretched for the health (0x7EDC), recent damage
  (0x7EDD) and empty (0x7EDE) parts (FUN_8004E55C);
- round marks: 15 × 18 at UV (0xF0, 0xA8), won CLUT 0x7F18, empty 0x7F19 (FUN_8004E87C);
- timer digits: 16 × 46 at UV (16·d, 0xD0) on page 0x0E, CLUT 0x7F1C; 10 and 11 are the halves
  of ∞ (FUN_8004E410, table 0x80022154);
- name plates: the name at UV (0x40, 0) of the fighter's page (tpage 7, VRAM (448, 0) for
  player 1), 16 lines high and as wide as the character record's byte +5, through the
  system CLUT 0x7F10 + 2 · costume; the backing quad's texels (UV 0xDC–0xDD, 0xA8–0xB1)
  through 0x7F11 + 2 · costume (FUN_8004EA84, FUN_8004EB9C). Tekken Force's enemies (keys
  0x54–0x57, slots 47–50) keep their names stacked on that page, costume c at V = 16 · c,
  through 0x7F10 on the first plate (force.ovl FUN_800B362C).

The text engine's fonts 0–3 (hud.md#text-engine, FUN_8004D15C) become glyph sheets, one per
font and colour (`hud/font_<f>_<colour>.png`: characters 0x20–0x5F in rows of 16 cells), each
glyph through the colour's CLUT at x = 256 + 16·((n + k) & 15), y = ((n + k) >> 4) + 24 | 480.

Output: `hud/*.png` and `hud/hud.json` (the names' widths by costume slot, the fonts' metrics).
"""

from __future__ import annotations

import numpy as np

from common import Disc, Output
from vram import Vram, clut_xy, png_bytes, rgba, tpage_xy
import character
import sources

PAGE_BARS = (832, 0)            # tpage 0x0D
PAGE_DIGITS = (896, 0)          # tpage 0x0E
NAME_PAGE = (448, 0)            # tpage 7: the second page of player 1's texture area
NAME_UV = (0x40, 0)
NAME_HEIGHT = 16
NAME_CLUTS = 0x7F10             # + 2 · costume
PLATE_CLUTS = 0x7F11            # + 2 · costume
PLATE_UV = (0xDC, 0xA8, 2, 10)
CAP_UV = ((0xE0, 0xA8), (0xEA, 0xA8))
CAP_SIZE = (6, 24)
FILL_UV = (0xE8, 0xA8, 2, 24)
BAR_CLUTS = {"health": 0x7EDC, "damage": 0x7EDD, "empty": 0x7EDE}
MARK_UV = (0xF0, 0xA8, 15, 18)
MARK_CLUTS = {"won": 0x7F18, "empty": 0x7F19}
DIGIT_SIZE = (16, 46)
DIGIT_V = 0xD0
DIGITS = 12                     # 0–9 and the two halves of ∞
DIGIT_CLUT = 0x7F1C
CHAR_RECORDS = 0x80098120       # record pointer per costume key; byte +5: the name's width
COSTUME_KEYS = 0x80095CE8
COSTUME_KEY_COUNT = 0x5C
COSTUME_ARC_FIRST = 73
FORCE_ENEMY_KEYS = range(0x54, 0x58)   # Tekken Force's enemies: names stacked by costume
FONT_TABLE = 0x80021FD0         # 16 bytes per font: glyph UV table, advance, line, w, h, tpage, CLUT offset
FONTS = 4                        # font 3: font 2 at a 21-pixel advance (the VS names)
FONT_COLOURS = 32                 # CLUT rows 504 and 505: colours 0–31 (the team grid's 0x1A)
FIRST_CHAR, LAST_CHAR = 0x20, 0x5F
SHEET_COLUMNS = 16


def _sprite(out: Output, rel: str, indices: Vram, page: tuple[int, int], u: int, v: int, w: int, h: int,
            palette: Vram, clut: int) -> None:
    """Writes a 4-bit sprite of the page in `indices` through a CLUT of `palette` (and records it)."""
    idx = indices.page_indices(page[0], page[1], 4)[v:v + h, u:u + w]
    cx, cy = clut_xy(clut)
    colours = palette.clut(cx, cy, 16)
    out.write(rel, png_bytes(rgba(colours[idx])))
    sources.piece(out, rel, 0, 0, indices.words, 4 * page[0] + u, page[1] + v, idx.shape[1], idx.shape[0], 4, colours)


def convert(disc: Disc, out: Output) -> None:
    system = disc.system_vram()
    for side, (u, v) in zip(("left", "right"), CAP_UV):
        _sprite(out, f"hud/bar_cap_{side}.png", system, PAGE_BARS, u, v, *CAP_SIZE, system, BAR_CLUTS["empty"])
    for name, clut in BAR_CLUTS.items():
        _sprite(out, f"hud/bar_{name}.png", system, PAGE_BARS, *FILL_UV, system, clut)
    for name, clut in MARK_CLUTS.items():
        _sprite(out, f"hud/mark_{name}.png", system, PAGE_BARS, *MARK_UV, system, clut)
    for d in range(DIGITS):
        _sprite(out, f"hud/digit_{d}.png", system, PAGE_DIGITS, 16 * d, DIGIT_V, *DIGIT_SIZE, system, DIGIT_CLUT)
    for costume in range(4):
        _sprite(out, f"hud/plate_{costume}.png", system, PAGE_BARS, *PLATE_UV, system, PLATE_CLUTS + 2 * costume)
    names = {}
    pointers = disc.exe_u32(CHAR_RECORDS, COSTUME_KEY_COUNT)
    for key, byte in enumerate(disc.exe_u8(COSTUME_KEYS, COSTUME_KEY_COUNT)):
        slot = byte - 256 if byte > 127 else byte
        if slot < 0 or str(slot) in names:
            continue
        width = disc.exe_u8(pointers[key] + 5, 1)[0]
        textures = character.costume_textures(disc, COSTUME_ARC_FIRST + 4 * slot)
        costume = 0 if key in FORCE_ENEMY_KEYS else key & 3
        v = 16 * (key & 3) if key in FORCE_ENEMY_KEYS else NAME_UV[1]
        _sprite(out, f"hud/name_{slot:02d}.png", textures, NAME_PAGE, NAME_UV[0], v, width, NAME_HEIGHT, system,
                NAME_CLUTS + 2 * costume)
        names[str(slot)] = {"file": f"name_{slot:02d}.png", "width": width, "plate": f"plate_{costume}.png"}
    fonts = {}
    for f in range(FONTS):
        at = FONT_TABLE + 16 * f
        table = disc.exe_u32(at, 1)[0]
        advance, line, w, h, tpage = disc.exe_u16(at + 4, 5)
        offset = disc.exe_u8(at + 14, 1)[0]
        page = tpage_xy(tpage)
        codes = range(FIRST_CHAR, LAST_CHAR + 1)
        rows = (len(codes) + SHEET_COLUMNS - 1) // SHEET_COLUMNS
        indices = system.page_indices(page[0], page[1], 4)
        for colour in range(FONT_COLOURS):
            k = colour + offset
            palette = system.clut(256 + 16 * (k & 15), ((k >> 4) + 24) | 480, 16)
            sheet = np.zeros((rows * h, SHEET_COLUMNS * w, 4), dtype=np.uint8)
            for n, code in enumerate(codes):
                if code == 0x20:
                    continue
                uv = disc.exe_u16(table + 2 * code, 1)[0]
                u, v = uv & 0xFF, uv >> 8
                glyph = rgba(palette[indices[v:v + h, u:u + w]])
                gh, gw = glyph.shape[:2]
                r, c = divmod(n, SHEET_COLUMNS)
                sheet[r * h:r * h + gh, c * w:c * w + gw] = glyph
                sources.piece(out, f"hud/font_{f}_{colour}.png", c * w, r * h, system.words, 4 * page[0] + u,
                              page[1] + v, gw, gh, 4, palette)
            out.write(f"hud/font_{f}_{colour}.png", png_bytes(sheet))
        fonts[str(f)] = {"advance": advance, "line": line, "width": w, "height": h,
                         "first": FIRST_CHAR, "columns": SHEET_COLUMNS}
    out.write_json("hud/hud.json", {"names": names, "digits": DIGITS, "fonts": fonts})
