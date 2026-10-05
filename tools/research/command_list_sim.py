#!/usr/bin/env python3
"""Integer port of the in-fight command list's text engine (Japan Rev.1): `MoveTextDraw`
(0x80077A0C) and its direction arrows (0x800778A8).

The engine works like the main text engine (draw_sim.print_text) but with 0xFF as the escape
byte and the per-character glyph atlas of formats/arc-archives.md ("Move-text rendering").
Its pen and style live in the scratchpad at 0x1F800380 while it runs and are saved to
0x800A39B0 afterwards. Verified by `tools/research/verify_command_list_sim.py`.
"""

from __future__ import annotations

import draw_sim as ds
from fight_sim import Ram

M = 0x1F800380                   # s16 x, y; u32 glyph w|h; u16 tpage; u32 colour at +0xC;
                                 # s16 advance x, y at +0x10; s16 margin x, line y at +0x14
SAVED = 0x800A39B0               # u16 margin x, line y, x, y; u32 colour
FONT_INDEX = 0x80098DD8
FONTS = 0x80027D1C               # 4 x (s16 advance x, advance y, u16 w, h, tpage)
ARROWS = 0x80027D44              # 9 x (u16 uv, u16 flip flags: 1 horizontal, 2 vertical)
BUTTON_TPAGE = 0x80027D38
M32 = 0xFFFFFFFF


def _link(ram: Ram, ot: int, p: int, words: int) -> None:
    ram.put(p, "I", ram.u32(ot) & 0xFFFFFF | words << 24)
    ram.put(ot, "I", p & 0xFFFFFF | ram.u32(ot) & 0xFF000000)


def _xy(ram: Ram) -> int:
    return ram.u32(M)


def _adv(ram: Ram, n: int) -> int:
    """The x advance divided by n (2 or 4), truncated towards zero like the game's shifts."""
    return ds._sdiv(ram.s16(M + 0x10), n)


def _glyph_uv(g: int) -> int:
    """Glyph g of the character's atlas: 12 x 11 cells, ten per row, four bit planes by CLUT."""
    g &= M32
    return ((g // 10 & 3 | 0x7ED8) << 16) + ((g // 40 * 11 + 0x10 & 0xFF) << 8) + (g % 10 * 12 + 0x40 & 0xFF)


def _sprite(ram: Ram, ot: int, p: int, uv: int) -> int:
    """A glyph SPRT at the pen; the pen moves on by the advance."""
    ram.put(p + 4, "I", ram.u32(M + 0xC) | 0x64000000)
    xy = _xy(ram)
    ram.put(p + 8, "I", xy)
    ram.put(M, "H", (xy & 0xFFFF) + ram.u16(M + 0x10) & 0xFFFF)
    ram.put(p + 0x10, "I", ram.u32(M + 4))
    ram.put(p + 0xC, "I", uv & M32)
    _link(ram, ot, p, 4)
    return p + 0x14


def arrow(ram: Ram, ot: int, p: int, idx: int) -> int:
    """FUN_800778A8: a 20 x 32 direction arrow (a POLY_FT4 flipped from one of three pictures);
    bit 3 picks the held-direction CLUT; 0x10 is the neutral star."""
    t = 8 if idx & 0xFF == 0x10 else idx & 7
    uv, flags = ram.u16(ARROWS + 4 * t), ram.u16(ARROWS + 4 * t + 2)
    uvs = [uv, uv + 0x13, uv + 0x1F00, uv + 0x1F13]
    if flags & 1:
        uvs = [uvs[1], uvs[0], uvs[3], uvs[2]]
    if flags & 2:
        uvs = [uvs[2], uvs[3], uvs[0], uvs[1]]
    uvs[1] |= 0x60000
    uvs[0] |= (0x7FB3 if idx & 8 else 0x7FB4) << 16
    xy = (ram.s16(M + 2) - 12 << 16 | ram.s16(M)) & M32
    ram.put(p + 4, "I", ram.u32(M + 0xC) | 0x2C000000)
    for i, (off, v) in enumerate(((0x10, 0x13), (0x18, 0x1F0000), (0x20, 0x1F0013))):
        ram.put(p + off, "I", xy + v & M32)
    ram.put(p + 8, "I", xy)
    for i, off in enumerate((0xC, 0x14, 0x1C, 0x24)):
        ram.put(p + off, "I", uvs[i] & M32)
    ram.put(M, "H", xy + 0x14 & 0xFFFF)
    _link(ram, ot, p, 9)
    return p + 0x28


def _font(ram: Ram, idx: int) -> None:
    f = FONTS + 10 * idx & M32
    for dst, src in ((0x10, 0), (0x12, 2), (4, 4), (6, 6), (8, 8)):
        ram.put(M + dst, "H", ram.u16(f + src))


def move_text_draw(ram: Ram, s: int, args: list[int]) -> int:
    """MoveTextDraw (0x80077A0C): draws string `s` at the saved pen; returns the address after
    its terminating zero. Escapes (0xFF + letter): n newline, s a nested string drawn glyph by
    glyph, H/V pen x/y, h/v pen x/y in advances, i colour, p ordering-table entry, t font."""
    for dst, src in ((0x14, 0), (0x16, 2), (0, 4), (2, 6)):
        ram.put(M + dst, "H", ram.u16(SAVED + src))
    ram.put(M + 0xC, "I", ram.u32(SAVED + 8))
    _font(ram, ram.u32(FONT_INDEX))
    ot = ds.ot0(ram) + 4
    p = ds._pkt(ram)
    args = list(args)
    escape = False
    button_run = False
    while True:
        c = ram.u8(s)
        s += 1
        if c == 0:
            break
        if c == 0xFF and not escape:
            escape = True
            continue
        if escape and c != 0xFF:
            escape = False
            cmd = chr(c)
            if cmd == "n":
                y = ram.u16(M + 0x16) + ram.u16(M + 0x12) & 0xFFFF
                ram.put(M, "H", ram.u16(M + 0x14))
                ram.put(M + 0x16, "H", y)
                ram.put(M + 2, "H", y)
            elif cmd == "s":
                t = args.pop(0)
                while b := ram.u8(t):
                    t += 1
                    p = _sprite(ram, ot, p, _glyph_uv(b - 1))
            elif cmd in "HVhv":
                v = args.pop(0)
                if cmd in "hv":
                    v *= ram.s16(M + (0x10 if cmd == "h" else 0x12))
                off = 0 if cmd in "Hh" else 2
                ram.put(M + off, "H", v & 0xFFFF)
                ram.put(M + 0x14 + off, "H", v & 0xFFFF)
            elif cmd == "i":
                ram.put(M + 0xC, "I", args.pop(0) & M32)
            elif cmd == "p":
                p = ds.dr_mode(ram, ot, p, ram.u16(M + 8))
                ot = ds.ot0(ram) + 4 * args.pop(0) & M32
            elif cmd == "t":
                idx = args.pop(0)
                p = ds.dr_mode(ram, ot, p, ram.u16(M + 8))
                _font(ram, idx)
                ram.put(FONT_INDEX, "I", idx & M32)
            else:
                raise NotImplementedError(f"move text escape {c:#x}")
            continue
        escape = False
        if 0xD1 <= c <= 0xE0:                       # button diagram: two 20 x 32 sprites
            mask = c - 0xD1
            if not button_run:
                p = ds.dr_mode(ram, ot, p, ram.u16(M + 8))
            clut = (0x1FC + int(mask & 8 != 0)) << 6 | 0x30 | mask & 7
            xy = (ram.u16(M + 2) << 16) + 0xFFF40000 | ram.s16(M) & M32
            xy &= M32
            for q, uv in ((p, clut << 16 | 0xE000), (p + 0x14, 0x7FB1E014)):
                ram.put(q + 0xC, "I", uv)
                ram.put(q + 0x10, "I", 0x200014)
                ram.put(q + 4, "I", ram.u32(M + 0xC) | 0x64000000)
                ram.put(q + 8, "I", xy)
                _link(ram, ot, q, 4)
            ram.put(M, "H", xy + 0x14 & 0xFFFF)
            p += 0x28
            if not 0xD1 <= ram.u8(s) <= 0xE0:
                p = ds.dr_mode(ram, ot, p, ram.u16(BUTTON_TPAGE))
            button_run = True
            continue
        button_run = False
        if 0xBD <= c <= 0xCC:                       # direction arrow
            p = ds.dr_mode(ram, ot, p, ram.u16(M + 8))
            p = arrow(ram, ot, p, c - 0xBD)
        elif c == 6:                                # neutral star
            p = ds.dr_mode(ram, ot, p, ram.u16(M + 8))
            p = arrow(ram, ot, p, 0x10)
        elif c == 0xFD:
            ram.put(M, "H", ram.u16(M) + ram.u16(M + 0x10) & 0xFFFF)
        elif c == 0xFE:
            ram.put(M, "H", ram.u16(M) + _adv(ram, 2) & 0xFFFF)
        elif c == 1:                                # joiners: drawn with back-spacing
            ram.put(M, "H", ram.u16(M) - _adv(ram, 2) & 0xFFFF)
            p = _sprite(ram, ot, p, 0x7ED81040)
        elif c == 2:
            p = _sprite(ram, ot, p, 0x7ED8104C)
            ram.put(M, "H", ram.u16(M) - _adv(ram, 2) & 0xFFFF)
        elif c == 3:
            ram.put(M, "H", ram.u16(M) - _adv(ram, 4) & 0xFFFF)
            p = _sprite(ram, ot, p, _glyph_uv(2))
            ram.put(M, "H", ram.u16(M) - _adv(ram, 4) & 0xFFFF)
        elif c in (4, 5):
            ram.put(M, "H", ram.u16(M) + 2 - _adv(ram, 4) & 0xFFFF)
            p = _sprite(ram, ot, p, _glyph_uv(c - 1))
            ram.put(M, "H", ram.u16(M) - 2 - _adv(ram, 4) & 0xFFFF)
        else:
            p = _sprite(ram, ot, p, _glyph_uv(c - 1))
    ds._set_pkt(ram, ds.dr_mode(ram, ot, p, ram.u16(M + 8)))
    for dst, src in ((0, 0x14), (2, 0x16), (4, 0), (6, 2)):
        ram.put(SAVED + dst, "H", ram.u16(M + src))
    ram.put(SAVED + 8, "I", ram.u32(M + 0xC))
    return s


# ---- the command list screens ----
LISTS = 0x800A39D0               # per player (0x232 bytes): u8 count, then count x (name, command)
SCROLL = 0x800A39C0              # per player: s32 cursor, s32 scroll offset (pixels, eases to 0)
STR_STYLE = 0x80027E60           # "\xFFi\xFFt": colour, font
STR_POS = 0x80027E68             # "\xFFH\xFFV"
STR_TITLE = 0x80098DF0           # "\xFFp" + glyphs 6-10 (the title)
STR_EXIT = 0x80027E70            # "%p%f%H%V%cPUSH %cBUTTON %cTO %cEXIT"
FIGHTERS = (0x800A96F0, 0x800AAF7C)
NAME_BUF = 0x1F800340            # the first line of a long name (the game uses its stack)
PAUSE_DELAY, PAUSE_CURSOR, PAUSE_CHOICE = 0x800A8B3A, 0x80098DDC, 0x80098DDD
PAD_PRESSED, PAD_HELD = 0x800AE3D0, 0x800AE230
MODE = 0x800AFF50
SCREEN_RECT = 0x800AE6F8


class ListHooks:
    """SoundPlayFighter(0, id, 0); the default does nothing, the verifier logs it."""

    def sound(self, ram: Ram, sound_id: int) -> None:
        pass


HOOKS = ListHooks()


def skip_strings(ram: Ram, p: int, n: int) -> int:
    """FUN_800795E4."""
    while n > 0:
        while ram.u8(p):
            p += 1
        p += 1
        n -= 1
    return p


def _weight(c: int) -> int:
    return 1 if c == 0xFE or 1 <= c <= 5 else 2


def text_width(ram: Ram, s: int) -> int:
    """FUN_80079664: joiners (1-5) and half spaces count 1, everything else 2."""
    n = 0
    while c := ram.u8(s):
        n += _weight(c)
        s += 1
    return n


def width_copy(ram: Ram, dst: int, src: int, width: int) -> int:
    """FUN_80079610: copies bytes until `width` is used up; returns where it stopped."""
    while width > 0:
        c = ram.u8(src)
        width -= _weight(c)
        ram.put(dst, "B", c)
        src += 1
        dst += 1
    ram.put(dst, "B", 0)
    return src


def horizon_band(ram: Ram) -> None:
    """FUN_80048760: shows the stage's horizon band (stages.md, "Clear colour") for the next two
    frames, unless a True Ogre fight is on."""
    if ram.u8(0x800AFF68) == 0:
        ram.put(0x8009EB20, "I", 2)


def _tile(ram: Ram, ot: int, c: int, xy: int, wh: int) -> None:
    ds._set_pkt(ram, ds.tile(ram, ot, ds._pkt(ram), c, xy & M32, wh))


def list_screen(ram: Ram, player: int, pad_player: int) -> None:
    """FUN_800789E4: one player's move list, six moves 64 pixels apart in a 182-pixel column
    (right half for player 2), scrolled by up/down (1) and left/right (5) with easing."""
    p8 = player & 0xFF
    lst = LISTS + 0x232 * p8
    pressed = ram.u16(PAD_PRESSED + (2 if pad_player else 0))
    held = ram.u16(PAD_HELD + (2 if pad_player else 0))
    x0 = 0xB8 if p8 else 0
    sc = SCROLL + 8 * p8
    count = ram.u8(lst)
    if not ram.u32(ds.TEXT_OFF):
        d = 1 if pressed == 0x4000 else 0
        if pressed == 0x1000:
            d = -1
        if not held & 0x5000:
            if pressed == 0x2000:
                d = 5
            elif pressed == 0x8000:
                d = -5
        if d:
            HOOKS.sound(ram, 0x546C)
        cur = ram.s32(sc)
        v = (cur if cur < count else 0) + d
        if v < 0:
            v += count
        if not v < count:
            v -= count
        ram.put(sc, "i", v)
        ram.put(sc + 4, "I", ram.s32(sc + 4) + 64 * d & M32)
    off = ram.s32(sc + 4)
    if off:
        neg = off < 0
        off = abs(off)
        off -= ds._sdiv(off + 3, 3)
        off = max(off, 0)
        off = -off if neg else off
    ram.put(sc + 4, "I", off & M32)
    if ram.u32(ds.TEXT_OFF):
        return
    shift = ds._sdiv(off, 64) + int(off > 0)
    y = off + 0x76 - 64 * shift
    idx = ram.s32(sc) - shift
    while idx < 0:
        idx += count
    while idx >= count:
        idx -= count
    s = skip_strings(ram, lst + 1, 2 * idx)
    kind = ram.s16(FIGHTERS[0] + 0x188C * p8 + 0x18 & M32)
    rows = 6
    if kind == 0xF:
        y, rows = 0xF6, 1
    move_text_draw(ram, STR_STYLE, [0x707070, p8])
    band = (y << 16) + 0xFFFE0000 & M32
    ot = ds.ot0(ram) + 4
    for _ in range(rows):
        if text_width(ram, s) >= 0x1D:
            move_text_draw(ram, STR_POS, [x0 + 6, y])
            s = width_copy(ram, NAME_BUF, s, 0x1C)
            move_text_draw(ram, NAME_BUF, [])
            move_text_draw(ram, STR_POS, [x0 + 6, y + 0xC])
        else:
            move_text_draw(ram, STR_POS, [x0 + 6, y + 6])
        s = move_text_draw(ram, s, [])
        move_text_draw(ram, STR_POS, [x0 + 6, y + 0x27])
        s = move_text_draw(ram, s, [])
        boxed, edge, fill = True, 0x602010, 0xB89246
        if kind == 6:
            if 6 <= idx <= 13:
                edge, fill, first = 0x204000, 0x5FA255, idx < 7
            elif idx >= 14:
                edge, fill, first = 0x103040, 0x2090A0, idx < 15
            else:
                first = False
            if first:
                fill, boxed = 0x602010, False
        low = (y + 0x18 << 16) & M32
        if boxed:
            ds._set_pkt(ram, ds.poly_g4(ram, ot, ds._pkt(ram), edge | 0x38000000, edge, fill, fill,
                                        (x0 | 3) | band, (x0 + 0xB5) | band, (x0 | 3) | low, (x0 + 0xB5) | low))
            _tile(ram, ot, edge | 0x60000000, (x0 | 3) | band, 0x3F00B2)
            _tile(ram, ot, 0x60D0D0D0, (x0 | 2) | (y - 3 << 16), 0x4200B4)
        else:
            _tile(ram, ot, fill | 0x60000000, (x0 | 3) | band, 0x1A00B2)
            _tile(ram, ot, edge | 0x60000000, (x0 | 2) | band, 0x3F00B4)
        idx += 1
        if idx >= count:
            s, idx = lst + 1, 0
        band = band + 0x400000 & M32
        y += 0x40
    move_text_draw(ram, STR_POS, [x0 + 0x3C, 0x61])
    move_text_draw(ram, STR_TITLE, [0])
    ot0 = ds.ot0(ram)
    _tile(ram, ot0, 0x60E0E0E0, (x0 | 2) | 0x720000, 0x200B4)
    _tile(ram, ot0, 0x60E0E0E0, (x0 | 2) | 0x1B30000, 0x200B4)
    _tile(ram, ot0, 0x60602010, x0 | 0x5C0001, 0x17000B6)


def _rect(ram: Ram) -> tuple[int, int, int, int]:
    return tuple(ram.u16(SCREEN_RECT + 2 * i) for i in range(4))


def _area(ram: Ram, ot: int, x: int, y: int, w: int, h: int) -> None:
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ot, ds._pkt(ram), x, y, w, h & 0xFFFF))


def _lists(ram: Ram, mask: int) -> None:
    for p in range(2):
        if mask >> p & 1:
            list_screen(ram, p, p)


def practice_command_list(ram: Ram, mask: int, player: int) -> None:
    """FUN_8007906C: practice's COMMAND LIST: the lists in `mask` and PUSH BUTTON TO EXIT."""
    if ram.u32(ds.TEXT_OFF):
        _lists(ram, mask)
        return
    delay = ram.u8(PAUSE_DELAY)
    if delay:
        ram.put(PAUSE_DELAY, "B", delay - 1)
        return
    x, y, w, h = _rect(ram)
    _area(ram, ds.ot0(ram), x, y, 0, 0)
    _area(ram, ds.ot0(ram) + 4, x, y, 0, 0)
    ds.text(ram, STR_EXIT, 0, 0, player * 0xB8 | 6, 0x1B8, 6, 5, 6, 5)
    _lists(ram, mask)
    _area(ram, ds.ot0(ram), x, 0x5C, w, y + h - 0x5C)
    _area(ram, ds.ot0(ram) + 4, x, 0x74, w, 0x13F)
    _area(ram, ram.u32(ram.u32(0x800A911C) + 0x10), x, y, 0, 0)


def pause_command_page(ram: Ram, player: int) -> None:
    """FUN_80079298: the pause menu's COMMAND page; a button returns to the menu. Tekken Force
    shows only the player's list. (With text off it updates the scrolling with the Tekken Ball
    test instead of the Tekken Force one: game-bugs.md #39.)"""
    if ram.u32(ds.TEXT_OFF):
        if ram.u32(MODE) == 7:
            list_screen(ram, 0, ram.u32(0x800B70D8))
        else:
            _lists(ram, ram.u8(MODE + 0x1D))
        return
    delay = ram.u8(PAUSE_DELAY)
    if delay:
        ram.put(PAUSE_DELAY, "B", delay - 1)
        return
    x, y, w, h = _rect(ram)
    _area(ram, ds.ot0(ram), x, y, 0, 0)
    _area(ram, ds.ot0(ram) + 4, x, y, 0, 0)
    if ram.u16(PAD_PRESSED + (0 if player == 1 else 2)) & 0x8F0:
        ram.put(PAUSE_CHOICE, "B", 0)
        ram.put(PAUSE_CURSOR, "B", 0)
        ram.put(PAUSE_DELAY, "B", 2)
        horizon_band(ram)
        HOOKS.sound(ram, 0x50F4)
    if ram.u32(MODE) == 8:
        ds.text(ram, STR_EXIT, 0, 0, 6, 0x1B8, 6, 5, 6, 5)
        list_screen(ram, 0, ram.u32(0x800B70D8))
    else:
        ds.text(ram, STR_EXIT, 0, 0, (player - 1) * 0xB8 | 6, 0x1B8, 6, 5, 6, 5)
        _lists(ram, ram.u8(MODE + 0x1D))
    _area(ram, ds.ot0(ram), x, 0x5C, w, y + h - 0x5C)
    _area(ram, ds.ot0(ram) + 4, x, 0x74, w, 0x13F)
    _area(ram, ram.u32(ram.u32(0x800A911C) + 0x10), x, y, w, 0x20)
