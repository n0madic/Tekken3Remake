#!/usr/bin/env python3
"""Integer ports of the 2D drawing code of Tekken 3 (Japan Rev.1): GPU packet builders,
the text engine, and the screen drawing routines of the result, ranking and staff roll screens.

The routines write GPU packets into a packet buffer and link them into an ordering table
(OT), exactly as the game does, so `tools/research/verify_draw_sim.py` can compare the packet
bytes and the OT with the harness. The packets are the complete description of what is
drawn (primitive type, coordinates, texture page, CLUT, UVs, colours, semi-transparency),
and the PlayStation GPU rasterises them in a fixed way.

Packet builders take (ot, packet, ...) and return the next free packet address, like the
game's functions. `ot` is the address of the OT entry the packet is linked into.
"""

from __future__ import annotations

from fight_sim import Ram

GLYPH_CODE = 0x65000000          # SPRT, textured, raw texture
FONT_TABLE = 0x80021FD0          # 4 x 16 bytes: glyph UV table, advance, line height, w, h, draw mode, CLUT offset
POWERS = 0x80021E24              # 10^7 .. 10, 0
HEX_DIGITS = 0x80022010          # "0123456789ABCDEF"
TEXT_STATE = 0x8009F658          # u16 margin x, margin y, pen x, pen y; u32 colour
OT_BASE = 0x800A96E0             # pointer to the current OT
PACKET_PTR = 0x800AE42C          # next free packet
TEXT_OFF = 0x800AE16C            # text is not drawn while non-zero


def link(ram: Ram, ot: int, p: int, words: int) -> None:
    """addPrim: tag = (OT link) | length << 24; OT entry -> this packet."""
    ram.put(p, "I", ram.u32(ot) & 0xFFFFFF | words << 24)
    ram.put(ot, "I", p & 0xFFFFFF | ram.u32(ot) & 0xFF000000)


def draw_mode_word(dfe: int, dtd: int, tpage: int) -> int:
    """GetDrawMode (0x8007DA94)."""
    return 0xE1000000 | (0x200 if dtd else 0) | (0x400 if dfe else 0) | tpage & 0x9FF


def dr_mode(ram: Ram, ot: int, p: int, tpage: int) -> int:
    """FUN_8004DD90: SetDrawMode(p, 0, 1, tpage, NULL) and link."""
    ram.put(p + 3, "B", 2)
    ram.put(p + 4, "I", draw_mode_word(0, 1, tpage & 0xFFFF))
    ram.put(p + 8, "I", 0)
    link(ram, ot, p, 2)
    return p + 12


def _words(ram: Ram, p: int, pairs) -> None:
    for i, v in pairs:
        ram.put(p + 4 * i, "I", v & 0xFFFFFFFF)


def poly_ft4(ram: Ram, ot: int, p: int, a3, a4, a5, a6, a7, a8, a9, a10) -> int:
    """FUN_8004DB18: textured quad (9 words)."""
    _words(ram, p, ((1, a3), (2, a4), (4, a5), (6, a6), (8, a7), (3, a8), (5, a9), (7, a10 & 0xFFFF), (9, a10 >> 16)))
    link(ram, ot, p, 9)
    return p + 40


def poly_g4(ram: Ram, ot: int, p: int, c0, c1, c2, c3, v0, v1, v2, v3) -> int:
    """FUN_8004DB98: Gouraud quad."""
    _words(ram, p, ((1, c0), (3, c1), (5, c2), (7, c3), (2, v0), (4, v1), (6, v2), (8, v3)))
    link(ram, ot, p, 8)
    return p + 36


def poly_f4(ram: Ram, ot: int, p: int, c, v0, v1, v2, v3) -> int:
    """FUN_8004DABC: flat quad."""
    _words(ram, p, ((1, c), (2, v0), (3, v1), (4, v2), (5, v3)))
    link(ram, ot, p, 5)
    return p + 24


def tile(ram: Ram, ot: int, p: int, c, xy, wh) -> int:
    """FUN_8004DCF8 / FUN_8004DD44: TILE (3 words)."""
    _words(ram, p, ((1, c), (2, xy), (3, wh)))
    link(ram, ot, p, 3)
    return p + 16


def sprt(ram: Ram, ot: int, p: int, code, xy, wh, uv_clut) -> int:
    """FUN_8004DCA4: SPRT (4 words: code, xy, uv|clut, wh)."""
    _words(ram, p, ((1, code), (2, xy), (4, wh), (3, uv_clut)))
    link(ram, ot, p, 4)
    return p + 20


def fade(ram: Ram, ot: int, p: int, level: int) -> int:
    """FUN_8004E2E8: screen fade; 0x100 = none, below darkens, above brightens."""
    if level > 0x1FF:
        level = 0x1FF
    if level == 0x100:
        return p
    if level < 0x100:
        v, mode = 0xFF - level, 2
    else:
        v, mode = level - 0x100, 1
    v &= 0xFFFFFFFF
    _words(ram, p, ((1, v | v << 8 | v << 16 | 0x62000000), (2, 0), (3, 0x1E00170)))
    link(ram, ot, p, 3)
    return dr_mode(ram, ot, p + 16, (mode & 3) << 5)


def scale_colour(c: int, k: int) -> int:
    """FUN_8004E254."""
    out = 0
    for sh in (0, 8, 16):
        v = ((c >> sh & 0xFF) * k & 0xFFFFFFFF) >> 8
        out |= min(v, 0xFF) << sh
    return out


def triangle_wave(v: int) -> int:
    """FUN_8004E2C8."""
    v &= 0x1FF
    return 0x1FF - v if v >= 0x100 else v


# ---- text engine (FUN_8004D15C) ----
def nibbles(v: int) -> int:
    """FUN_8004CFC0."""
    v &= 0xFFFFFFFF
    n = 0
    while v:
        v >>= 4
        n += 1
    return n


def print_text(ram: Ram, fmt: int, args: list[int], powers: list[int] | None = None) -> None:
    """FUN_8004D15C(format, args...): printf-like text into SPRT glyph packets.

    `args` are the 32-bit argument words in order (a1..a3, then the stack)."""
    if ram.u32(TEXT_OFF):
        return
    if powers is None:
        powers = []
        a = POWERS
        while ram.u32(a):
            powers.append(ram.u32(a))
            a += 4

    def bcd(n: int) -> int:
        n &= 0xFFFFFFFF
        if n > 100_000_000:                  # FUN_8004CE74; exactly 10^8 gives 0xA0000000
            return 0x99999999
        out, shift = 0, 0x1C
        for pw in powers:
            if n >= pw:
                out |= (n // pw) << shift & 0xFFFFFFFF
                n %= pw
            shift -= 4
        return (out + n) & 0xFFFFFFFF

    font = FONT_TABLE
    table = ram.u32(font)
    adv, line = ram.u16(font + 4), ram.u16(font + 6)
    size = ram.u16(font + 8) | ram.u16(font + 0xA) << 16
    mode = ram.u16(font + 0xC)
    clut_off = ram.u8(font + 0xE)
    colour = ram.u8(TEXT_STATE + 8)
    mx, my = ram.u16(TEXT_STATE), ram.u16(TEXT_STATE + 2)
    px, py = ram.u16(TEXT_STATE + 4), ram.u16(TEXT_STATE + 6)

    def clut_word(extra_mask: bool) -> int:
        v = colour + clut_off
        hi = ((v >> 4) + 0x18 & 0x1F) + 0x1E0 if extra_mask else ((v >> 4) + 0x18) | 0x1E0
        return (hi << 6 | v & 0xF | 0x10) << 16 & 0xFFFFFFFF

    clut = clut_word(False)
    ot = ram.u32(OT_BASE) + 0x1C
    p = ram.u32(PACKET_PTR)
    arg = iter(args)

    def glyph(code: int) -> None:
        nonlocal p, px
        ram.put(p + 4, "I", GLYPH_CODE)
        ram.put(p + 8, "I", px | py << 16)
        px = (px + adv) & 0xFFFF
        ram.put(p + 0x10, "I", size)
        ram.put(p + 0xC, "I", ram.u16(table + 2 * code) | clut)
        link(ram, ot, p, 4)
        p += 0x14

    escape = zero_pad = 0
    width = 0
    i = fmt
    while True:
        c = ram.u8(i)
        i += 1
        if c == 0:
            break
        if c == 0x20:
            px = (px + adv) & 0xFFFF
            continue
        if c == 0x0A:
            my = (my + line) & 0xFFFF
            px, py = mx, my
            continue
        if c == 0x25:
            if escape != 1:
                width = 0
                escape = 1
                zero_pad = 0
                continue
            escape = 0
        if escape == 0:
            glyph(c)
            continue
        if escape != 1:
            continue
        escape = 0
        code = chr(c)
        if code == "0":
            zero_pad = escape = 1
        elif "1" <= code <= "8":
            width = c - 0x30
            escape = 1
        elif code in "DdbxC":
            if code == "C":
                ch = next(arg) & 0xFF
                if ch == 0x20:
                    px = (px + adv) & 0xFFFF
                else:
                    glyph(ch)
                continue
            v = next(arg) & 0xFFFFFFFF
            neg = 0
            if code == "d" and v & 0x80000000:
                v = -v & 0xFFFFFFFF
                neg = 1
            if code in "dD":
                v = bcd(v)
            digits = nibbles(v) or 1
            if width == 0:
                width = digits
            else:
                if neg:
                    width -= 1
                if width < digits or zero_pad:
                    digits = width
            if digits < width:
                gap = width - digits
                if code == "b":
                    gap *= 4
                px = (px + gap * _s16(adv)) & 0xFFFF
            if neg:
                glyph(0x2D)
            sv = v - (1 << 32) if v & 0x80000000 else v
            if code == "b":
                for bit in range(digits * 4 - 1, -1, -1):
                    glyph(ram.u8(HEX_DIGITS + (sv >> bit & 1)))
            else:
                for sh in range((digits - 1) * 4, -1, -4):
                    glyph(ram.u8(HEX_DIGITS + (sv >> sh & 0xF)))
        elif code == "H":
            mx = px = next(arg) & 0xFFFF
        elif code == "V":
            my = py = next(arg) & 0xFFFF
        elif code == "h":
            mx = px = next(arg) * _s16(adv) & 0xFFFF
        elif code == "v":
            my = py = next(arg) * _s16(line) & 0xFFFF
        elif code == "c":
            v = (next(arg) + clut_off) & 0xFFFFFFFF
            clut = ((_asr(v, 4) + 0x18 & 0x1F) + 0x1E0) << 6 | v & 0xF | 0x10
            clut = clut << 16 & 0xFFFFFFFF
            colour = (v - clut_off) & 0xFF
        elif code == "p":
            p = dr_mode(ram, ot, p, mode)
            ot = (ram.u32(OT_BASE) + 4 * next(arg)) & 0xFFFFFFFF
        elif code == "f":
            n = next(arg)
            p = dr_mode(ram, ot, p, mode)
            font = (FONT_TABLE + 16 * n) & 0xFFFFFFFF
            table = ram.u32(font)
            adv, line = ram.u16(font + 4), ram.u16(font + 6)
            size = ram.u16(font + 8) | ram.u16(font + 0xA) << 16
            mode = ram.u16(font + 0xC)
            clut_off = ram.u8(font + 0xE)
            clut = clut_word(False)
        elif code == "s":
            s = next(arg)
            while True:
                ch = ram.u8(s)
                s += 1
                if ch == 0:
                    break
                if ch == 0x20:
                    px = (px + adv) & 0xFFFF
                else:
                    glyph(ch)
        else:
            raise ValueError(f"unknown text code %{code}: the game calls exit()")
    p = dr_mode(ram, ot, p, mode)
    ram.put(PACKET_PTR, "I", p)
    ram.put(TEXT_STATE, "H", mx)
    ram.put(TEXT_STATE + 2, "H", my)
    ram.put(TEXT_STATE + 4, "H", px)
    ram.put(TEXT_STATE + 6, "H", py)
    ram.put(TEXT_STATE + 8, "I", colour & 0xFF)


def _s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def _s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def _asr(v: int, n: int) -> int:
    v &= 0xFFFFFFFF
    if v & 0x80000000:
        v -= 1 << 32
    return v >> n


# ---- larger resident builders ----
FRAME_COUNT = 0x800AE6E0
PORTRAIT_FRAME_COLOURS = 0x80021664   # 4 x 10 words; the first three are the frame colours
PORTRAIT_FRAME_LINES = 0x800215EC     # 10 x (colour index, xy0 offset, xy1 offset)
PORTRAIT_UV = 0x8002152C              # per character: u32 uv|clut, u16 tpage
IMAGE_DEPTHS = 0x80022148             # per depth: u16 max sprite width, u16 max rows
BACKDROPS = (0x80022CF8, 0x80022D78)  # gradient quads: 8 words each


def line_f2(ram: Ram, ot: int, p: int, c, xy0, xy1) -> int:
    """FUN_8004DD44 (3 words: colour|code, xy0, xy1)."""
    return tile(ram, ot, p, c, xy0, xy1)


def poly_f3(ram: Ram, ot: int, p: int, c, xy0, xy1, xy2) -> int:
    """FUN_8004DA04 (4 words: colour|code, three vertices)."""
    _words(ram, p, ((1, c), (2, xy0), (3, xy1), (4, xy2)))
    link(ram, ot, p, 4)
    return p + 20


def portrait_frame(ram: Ram, ot: int, p: int, x: int, y: int, flags: int) -> int:
    """FUN_8004BA68: a portrait's frame (10 lines in 3 colours of set flags & 3; pulsing with 0x10)."""
    k = triangle_wave(ram.u32(FRAME_COUNT) << 4) if flags & 0x10 else 0x80
    cols = [scale_colour(ram.u32(PORTRAIT_FRAME_COLOURS + (flags & 3) * 0x28 + 4 * i), k * 2) | 0x40000000
            for i in range(3)]
    base = (x & 0xFFFF | y << 16) & 0xFFFFFFFF
    for i in range(10):
        e = PORTRAIT_FRAME_LINES + 12 * i
        p = line_f2(ram, ot, p, cols[ram.s32(e)], base + ram.u32(e + 4), base + ram.u32(e + 8))
    return p


def portrait(ram: Ram, ot: int, p: int, x: int, y: int, key: int, flags: int) -> int:
    """FUN_8004BBC0: a character portrait with an optional frame (the HUD face sprites)."""
    x &= 0xFFFFFFFF
    y = y - (1 << 32) if y & 0x80000000 else y
    key = key - (1 << 32) if key & 0x80000000 else key
    if not flags & 8:
        p = portrait_frame(ram, ot, p, x, y, flags)
        x = (x + 2) & 0xFFFFFFFF
        y += 3
    if flags & 0x40:
        p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | (y - 5) << 16, 0x200020, 0x7F1DE000)
        p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | (y + 0x1B) << 16, 0x200020, 0x7F1DE020)
        p = dr_mode(ram, ot, p, 0x1F)
    if not flags & 0x80:
        i = 0x17 if key == 0x59 else key >> 2
        uvc = ram.u32(PORTRAIT_UV + 8 * i)
        tp = ram.u16(PORTRAIT_UV + 8 * i + 4)
        if flags & 0x20:
            uvc = uvc & 0xFFFF | 0x7D500000
        x16 = x & 0xFFFF
        if i == 0x14:
            p = sprt(ram, ot, p, 0x65000000, x16 | y << 16, 0x180020, uvc)
            p = sprt(ram, ot, p, 0x65000000, x16 | (y + 0x18) << 16, 0x180020, uvc + 0x20)
            uvc += 0x40
            wh, xy = 0xA0020, x16 | (y + 0x30) << 16
        elif i < 0x16:
            wh, xy = 0x3A0020, x16 | y << 16
        else:
            p = sprt(ram, ot, p, 0x65000000, x16 | y << 16, 0xA0020, uvc)
            p = sprt(ram, ot, p, 0x65000000, x16 | (y + 10) << 16, 0x180020, (uvc & 0xFFFF00FF) + 0x20)
            uvc = (uvc & 0xFFFF00FF) + 0x40
            wh, xy = 0x180020, x16 | (y + 0x22) << 16
        p = sprt(ram, ot, p, 0x65000000, xy, wh, uvc)
        p = dr_mode(ram, ot, p, tp)
    return p


def backdrop(ram: Ram, ot: int, p: int, kind: int, colour: int) -> int:
    """FUN_800551FC: the gradient backdrop behind menus and result screens."""
    table, count, code = (BACKDROPS[0], 4, 0x38000000) if kind == 0 else (BACKDROPS[1], 2, 0x3A000000)
    for q in range(count):
        e = table + 32 * q
        cols = [ram.u32(e + 16 + 4 * i) for i in range(4)]
        cols = [colour if c == 0xFFFFFFFF else c for c in cols]
        cols[0] |= code
        p = poly_g4(ram, ot, p, *cols, ram.u32(e), ram.u32(e + 4), ram.u32(e + 8), ram.u32(e + 12))
    return p


def image(ram: Ram, ot: int, p: int, sx: int, sy: int, w: int, h: int, vx: int, vy: int,
          clut: int, mode: int) -> int:
    """FUN_8004DE84: draw a VRAM image of any size as SPRTs, split at texture-page borders.

    sx, sy: screen position; w, h: size in pixels; vx: VRAM x in 16-bit words; vy: VRAM y;
    clut: CLUT word; mode: texture page bits (depth in bits 7-8)."""
    M = 0xFFFF
    sx, sy, w, h, vy = sx & M, sy & M, w & M, h & M, vy & M
    depth = (mode & 0x180) >> 7
    max_w = ram.u16(IMAGE_DEPTHS + 4 * depth)
    rows = ram.u16(IMAGE_DEPTHS + 4 * depth + 2)
    shift = (2 - depth) & M
    tp_base = mode & 0xFFE0
    w_mask = (max_w - 1) & M
    h_lim = rows << 8 & M
    h_mask = (rows - 1) * 0x100 & M
    clutw = clut << 16 & 0xFFFFFFFF
    cur_vy, left_h = vy, h
    chunk_h = 0x100 - (vy & 0xFF) if vy & 0xFF else 0x100
    cur_sy = sy
    if h == 0:
        return p
    while True:
        if left_h < chunk_h:
            chunk_h = left_h
        cur_vx = (vx << shift) & M
        u0 = cur_vx & 0xFF
        chunk_w = 0x100 - u0 if u0 else 0x100
        left_w, cur_sx = w, sx
        ch = chunk_h
        while left_w != 0:
            if left_w < chunk_w:
                chunk_w = left_w
            rows_left = ch
            lim = h_lim
            ys = (cur_sy << 16) & 0xFFFFFFFF
            vv = (cur_vy & 0xFF) << 8
            if vv & h_mask:
                lim -= vv & h_mask
            while rows_left & M:
                hh = min(lim, (rows_left & M) << 8)
                x = cur_sx
                cw = chunk_w
                sw = max_w
                uu = cur_vx & 0xFF
                if uu & w_mask:
                    sw -= uu & w_mask
                if cw:
                    while True:
                        uv = uu | vv
                        if (cw & M) < sw:
                            sw = cw & M
                        uu += sw
                        xy = x | ys
                        x = (x + sw) & M
                        cw -= sw
                        ram.put(p + 4, "I", 0x65000000)
                        ram.put(p + 8, "I", xy & 0xFFFFFFFF)
                        ram.put(p + 12, "I", (uv | clutw) & 0xFFFFFFFF)
                        ram.put(p + 16, "I", (sw | hh << 8) & 0xFFFFFFFF)
                        link(ram, ot, p, 4)
                        p += 20
                        sw = max_w
                        if not cw & M:
                            break
                vv += hh
                ys = (ys + hh * 0x100) & 0xFFFFFFFF
                lim = h_lim
                rows_left = ((rows_left & M) * 0x100 - hh) >> 8
            tp = tp_base | (cur_vy & 0x100) >> 4 | ((cur_vx & 0xFF00) >> shift & 0x3FF) >> 6
            p = dr_mode(ram, ot, p, tp)
            left_w = (left_w - chunk_w) & M
            cur_vx = (cur_vx + chunk_w) & M
            cur_sx = (cur_sx + chunk_w) & M
            chunk_w = 0x100
        cur_vy = (cur_vy + chunk_h) & M
        rest = left_h - chunk_h
        left_h = rest & M
        cur_sy = (cur_sy + chunk_h) & M
        if rest == 0:
            break
        chunk_h = 0x100
    return p


# ---- memory with the scratchpad (strings are built there before printing) ----
SCRATCH = 0x1F800000
RAM_SIZE = 0x200000
FMT_PREFIX = 0x800980E8          # "%c%f%H%V"


class GpuRam(Ram):
    """Main RAM plus the 4 KB scratchpad at 0x1F800000."""

    def __init__(self, data: bytes | bytearray, scratch: bytes | bytearray = bytes(0x1000)) -> None:
        super().__init__(bytes(data) + bytes(scratch))

    def _off(self, addr: int) -> int:
        if addr & 0xFFFFF000 == SCRATCH:
            return RAM_SIZE + (addr & 0xFFF)
        return super()._off(addr)


def strcpy(ram: Ram, dst: int, src: int) -> int:
    while True:
        c = ram.u8(src)
        src += 1
        if c == 0:
            break
        ram.put(dst, "B", c)
        dst += 1
    ram.put(dst, "B", 0)
    return dst


def strlen(ram: Ram, s: int) -> int:
    n = 0
    while ram.u8(s + n):
        n += 1
    return n


def text(ram: Ram, fmt: int, *args: int) -> None:
    print_text(ram, fmt, [a & 0xFFFFFFFF for a in args])


def ot0(ram: Ram) -> int:
    return ram.u32(OT_BASE)


def ot_text(ram: Ram) -> int:
    return ram.u32(OT_BASE) + 0x1C


def _pkt(ram: Ram) -> int:
    return ram.u32(PACKET_PTR)


def _set_pkt(ram: Ram, p: int) -> None:
    ram.put(PACKET_PTR, "I", p)


def _sdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def _smod(a: int, b: int) -> int:
    return a - _sdiv(a, b) * b


# ---- result.ovl drawing ----
MODE = 0x800AFF50
T_FIGHT, T_LOST1, T_LOST2, T_LEFT1, T_LEFT2 = 0x800FAC48, 0x800FAC50, 0x800FAC54, 0x800FAC58, 0x800FAC5C
T_MSG, T_SLIDE, T_LINE = 0x800FAC60, 0x800FAC64, 0x800FAC68
T_MEMBER1, T_MEMBER2 = 0x800FAC78, 0x800FAD28
TEAM_LABELS = 0x800B9378         # 2 players x 2 layouts, 0x24 bytes each
TEAM_MESSAGES = 0x800B9428       # 5 x (string, colour)


def _rows_shift(ram: Ram) -> int:
    """(5 - (members1 + members2 + 1) / 3): pushes the second team down for small teams."""
    return 5 - (ram.u8(MODE + 0x65) + ram.u8(MODE + 0x72) + 1) // 3


def team_labels(ram: Ram, ctx: int) -> None:
    """FUN_800EE100: the two team labels and their colour bars."""
    tail = strcpy(ram, SCRATCH, FMT_PREFIX)
    for k in range(2):
        j = k + 2 if ram.u8(ctx + 0x1C) == 1 and k == ram.u8(ctx + 0x1F) else k
        e = TEAM_LABELS + 0x24 * j
        shift = (5 - (ram.u8(ctx + 0x65) + ram.u8(ctx + 0x72) + 1) // 3) * 0x1E if k == 1 else 0
        y = ram.u16(e + 6) + shift
        strcpy(ram, tail, ram.u32(e))
        text(ram, SCRATCH, ram.u32(e + 8), 1, ram.u16(e + 4), y, 1)
        top = (ram.u16(e + 0xE) + shift) << 16 & 0xFFFFFFFF
        bottom = (ram.u16(e + 0x14) + shift) << 16 & 0xFFFFFFFF
        mid_x = ram.u16(e + 0x10)
        c_edge, c_mid, c_end = ram.u32(e + 0x18), ram.u32(e + 0x1C), ram.u32(e + 0x20)
        v1, v3 = mid_x | top, mid_x | bottom
        p = poly_g4(ram, ot0(ram), _pkt(ram), c_edge | 0x3A000000, c_mid | 0x38000000, c_edge | 0x38000000,
                    c_mid | 0x38000000, ram.u16(e + 0xC) | top, v1, ram.u16(e + 0xC) | bottom, v3)
        p = poly_g4(ram, ot0(ram), p, c_mid | 0x3A000000, c_end | 0x38000000, c_mid | 0x38000000,
                    c_end | 0x38000000, v1, ram.u16(e + 0x12) | top, v3, ram.u16(e + 0x12) | bottom)
        _set_pkt(ram, dr_mode(ram, ot0(ram), p, 0x20))


def _asr8(v: int) -> int:
    return _asr(v, 8)


FACE_UV = 0x800B9778             # result.ovl: per character u32 uv|clut, u16 extra


def _uv_rect(uvc: int, v_shift: int, w: int, h: int, hi: int) -> tuple[int, int, int]:
    """(uv0|clut, uv1|tpage, uv2|uv3) words of a POLY_FT4 covering w+1 x h+1 texels."""
    u = uvc & 0xFF
    v = v_shift & 0xFF
    u1 = u + w & 0xFF
    v1 = v + h & 0xFF
    return (u | v << 8 | uvc & 0xFFFF0000, u1 | v << 8 | hi << 16, u | v1 << 8 | (u1 | v1 << 8) << 16)


def small_face(ram: Ram, ot: int, p: int, x: int, y: int, key: int, flags: int) -> int:
    """FUN_800F131C (result.ovl): a 16 x 29 character face, optionally over a frame."""
    x &= 0xFFFFFFFF
    y = y - (1 << 32) if y & 0x80000000 else y
    key = key - (1 << 32) if key & 0x80000000 else key
    x0, x1 = x & 0xFFFF, x + 0xF & 0xFFFF

    def quad(p, ya, yb, a8, a9, a10):
        return poly_ft4(ram, ot, p, 0x2D000000, x0 | ya << 16, x1 | ya << 16, x0 | yb << 16, x1 | yb << 16,
                        a8, a9, a10)
    if flags & 0x40:
        p = quad(p, y, y + 0xF, 0x7F1DE000, 0x1FE01F, 0xFF1FFF00)
        p = quad(p, y + 0x10, y + 0x1F, 0x7F1DE020, 0x1FE03F, 0xFF3FFF20)
    if not flags & 0x80:
        i = 0x17 if key == 0x59 else key >> 2
        uvc = ram.u32(FACE_UV + 8 * i)
        hi = ram.u16(FACE_UV + 8 * i + 4)
        if flags & 0x20:
            uvc = uvc & 0xFFFF | 0x7D500000
        v = _asr8(uvc)
        if i == 0x14:
            p = quad(p, y, y + 0xB, *_uv_rect(uvc, v, 0x1F, 0x17, hi))
            u2 = (uvc + 0x20) & 0xFFFFFFFF
            p = quad(p, y + 0xC, y + 0x17, *_uv_rect(u2, _asr8(u2), 0x1F, 0x17, hi))
            u3 = (uvc + 0x40) & 0xFFFFFFFF
            p = quad(p, y + 0x18, y + 0x1C, *_uv_rect(u3, _asr8(u3), 0x1F, 9, hi))
        elif i < 0x16:
            p = quad(p, y, y + 0x1C, *_uv_rect(uvc, v, 0x1F, 0x39, hi))
        else:
            p = quad(p, y, y + 4, *_uv_rect(uvc, v, 0x1F, 9, hi))
            u2 = ((uvc & 0xFFFF00FF) + 0x20) & 0xFFFFFFFF
            p = quad(p, y + 5, y + 0x10, *_uv_rect(u2, _asr8(u2), 0x1F, 0x17, hi))
            u3 = ((uvc & 0xFFFF00FF) + 0x40) & 0xFFFFFFFF
            p = quad(p, y + 0x11, y + 0x1C, *_uv_rect(u3, _asr8(u3), 0x1F, 0x17, hi))
    return p


STR_VS_ROW = 0x800B9494          # "%c%f%H%V%2d.  VS"
STR_STAGE_1X, STR_STAGE_2D = 0x800B951C, 0x800B9530
STR_TICKS = 0x800B9544           # the ' and " of a stage time
STR_TIME = 0x800B9554
STR_YOUR_TIME, STR_TOTAL_TICKS, STR_TOTAL_TIME, STR_NEW_RECORD = 0x800B959C, 0x800B9570, 0x800B9580, 0x800B95B0
DIGIT_FORMATS = 0x800F2994       # "%1d".."%8d" pointers (index 1-8)
STR_BLANK8 = 0x800B9680
STR_WIN, STR_WINS = 0x800B968C, 0x800B9698
STR_YOU_ARE, STR_GREATEST, STR_PRACTICE = 0x800B96C0, 0x800B96D0, 0x800B96E4
ORDINALS = 0x800F29B8            # "ST", "ND", "RD", "TH" at index 1-4
SURVIVOR_COLOURS = 0x800B96FC
BANNER_TILES = 0x800B9838
STR_BANNER_FMT, STR_BANNER = 0x800B9854, 0x800FAC0C
FORCE_FRAME = 0x800B9864
F_TEX, F_COLOUR, F_FLIP = 0x800FAE50, 0x800FAE58, 0x800FAE5C
BANNER_X, BANNER_Y = 0x80102690, 0x80102694
SCREEN_X, SCREEN_W = 0x800AE6F8, 0x800AE6FC
A_SHOW, A_WAIT, A_TOTAL, A_RECORD = 0x800FADF0, 0x800FADF4, 0x800FADEC, 0x800FADE0
A_KEY = 0x800FADE8
FRAME_COUNT2 = 0x800AE6E0
S_SHOW = 0x800FAE38


def team_message(ram: Ram, ctx: int) -> None:
    """FUN_800EE3C0: YOU WIN! / YOU LOSE! / DRAW GAME / PLAYER-n WINS!, sliding in."""
    if ram.u32(T_MSG) == 0:
        return
    left1, left2 = ram.s32(T_LEFT1), ram.s32(T_LEFT2)          # signed compares (slt)
    if ram.u8(ctx + 0x1C) == 1:
        if left1 == left2:
            msg = 2
        else:
            msg = int(ram.s32(T_LEFT1 + 4 * ram.u8(ctx + 0x1F)) < ram.s32(T_LEFT1 + 4 * ram.u8(ctx + 0x1E))) ^ 1
        way = -1 if ram.u8(ctx + 0x1E) == 0 else 1
    elif left1 == left2:
        msg, way = 2, -1
    elif left2 < left1:
        msg, way = 3, -1
    else:
        msg, way = 4, 1
    tail = strcpy(ram, SCRATCH, FMT_PREFIX)
    strcpy(ram, tail, ram.u32(TEAM_MESSAGES + 8 * msg))
    n = strlen(ram, tail)
    slide = ram.s32(T_SLIDE)
    x = 0xB8 if slide == 0 else _sdiv(slide * 0x170, 0x1E) * way + 0xB8
    x -= n * 0x16 >> 1
    yo = _rows_shift(ram) * 0xF
    text(ram, SCRATCH, ram.u32(TEAM_MESSAGES + 8 * msg + 4), 2, x, yo + 0x9E)
    col = 0xC0C0C0 if left1 == left2 else (0xFF if left2 < left1 else 0xC0FF)
    if slide == 0:
        p = tile(ram, ot_text(ram), _pkt(ram), col | 0x62000000,
                 (x - 8) & 0xFFFF | (yo + 0x9C) << 16, (n * 0x16 + 0x10) & 0xFFFF | 0x2E0000)
        _set_pkt(ram, dr_mode(ram, ot_text(ram), p, 0))


def team_members(ram: Ram, names: int, lost: int, x: int, y: int, second: int) -> None:
    """FUN_800EE694: a team's eight member slots (portrait, greyed when defeated, or an empty box)."""
    count = ram.u8(names + 0xC)
    n = min(count, 8)
    ot, p = ot0(ram), _pkt(ram)
    lost = lost - (1 << 32) if lost & 0x80000000 else lost
    for i in range(8):
        ch = min(ram.u8(names + i), 0x58)
        flags = 0
        if i < lost:
            flags = 0x60
        elif i == lost and i < n:
            flags = 1 if second else 2
        if i < count:
            p = portrait(ram, ot, p, x, y, ch, flags)
        else:
            x1, x35 = x + 1 & 0xFFFF, x + 0x23 & 0xFFFF
            y2, y3e = (y + 2) << 16, (y + 0x3E) << 16
            p = poly_g4(ram, ot, p, 0x38000000, 0, 0xC0C0C, 0xC0C0C, x1 | y2, x35 | y2, x1 | y3e, x35 | y3e)
            x36, y40 = x + 0x24 & 0xFFFF, (y + 0x40) << 16
            p = poly_f4(ram, ot, p, 0x28303030, x & 0xFFFF | y << 16, x36 | y << 16, x & 0xFFFF | y40, x36 | y40)
        x += 0x24
    _set_pkt(ram, p)


def team_grid(ram: Ram, ctx: int, fights: int, names: int) -> None:
    """FUN_800EE870: one box per fight (number, both faces, result colour), empty boxes after."""
    ot = ot0(ram)
    limit = fights - (1 << 32) if fights & 0x80000000 else fights
    if ram.u8(ctx + 0x58) < limit:
        limit = ram.u8(ctx + 0x58)
    a = b = 0
    col = f1 = f2 = 0
    shift = _rows_shift(ram) * 0x1E
    for i in range(max(limit, 0)):
        code = ram.u16(ctx + 0x38 + 2 * i)
        if code == 1:
            col, f1, f2 = 0xFF, 2, 0x60
        elif code == 2:
            col, f1, f2 = 0xC0FF, 0x60, 1
        elif code == 3:
            col, f1, f2 = 0xC0C0C0, 0, 0
        ch1 = min(ram.u8(names + a), 0x58)
        ch2 = min(ram.u8(names + b + 0xD), 0x58)
        if code in (2, 3):
            a += 1
        if code in (1, 3):
            b += 1
        xo, yo = _smod(i, 3) * 0x60, _sdiv(i, 3) * 0x1E
        _set_pkt(ram, small_face(ram, ot, _pkt(ram), xo + 0x47, yo + shift + 0x126, ch1, f1))
        _set_pkt(ram, small_face(ram, ot, _pkt(ram), xo + 0x6F, yo + shift + 0x126, ch2, f2))
        text(ram, STR_VS_ROW, 6, 0, xo + 0x2C, shift + yo + 0x132, i + 1)
        _grid_box(ram, ot, xo, yo + shift, col)
    j = limit
    while j < ram.u8(ctx + 0x65) + ram.u8(ctx + 0x72) - 1:
        xo, yo = _smod(j, 3) * 0x60, _sdiv(j, 3) * 0x1E
        p = tile(ram, ot, _pkt(ram), 0x60201010, xo + 0x47 & 0xFFFF | (yo + shift + 0x126) << 16, 0x1D0010)
        _set_pkt(ram, tile(ram, ot, p, 0x60201010, xo + 0x6F & 0xFFFF | (yo + shift + 0x126) << 16, 0x1D0010))
        j += 1
        text(ram, STR_VS_ROW, 0x1A, 0, xo + 0x2C, shift + yo + 0x132, j)
        _grid_box(ram, ot, xo, yo + shift, 0x404040)


def _grid_box(ram: Ram, ot: int, xo: int, y: int, col: int) -> None:
    x28, x87 = xo + 0x28 & 0xFFFF, xo + 0x87 & 0xFFFF
    p = poly_g4(ram, ot, _pkt(ram), 0x38000000, 0, col, col, x28 | (y + 0x135) << 16, x87 | (y + 0x135) << 16,
                x28 | (y + 0x143) << 16, x87 | (y + 0x143) << 16)
    _set_pkt(ram, tile(ram, ot, p, 0x60000000, x28 | (y + 0x126) << 16, 0x1D005F))


def team_lines(ram: Ram, ctx: int, fight: int, anim: int, colour: int) -> None:
    """FUN_800EF0D8: the lines joining the members of each fight (the current one grows)."""
    ot = ot_text(ram)
    fight = fight - (1 << 32) if fight & 0x80000000 else fight
    if ram.u8(ctx + 0x58) < fight:
        fight = ram.u8(ctx + 0x58)
    shift = _rows_shift(ram) * 0x1E
    if anim:
        y1 = 0xA4
        x1 = ram.s32(T_MEMBER1 + 4 * fight) * 0x24 + 0x39
        x2 = ram.s32(T_MEMBER2 + 4 * fight) * 0x24 + 0x39
        code = ram.u16(ctx + 0x38 + 2 * fight)
        y2 = shift + 0xC0
        t = min(anim, 8)
        if code == 1:
            x2 = x1 + ((x2 - x1) * t >> 3)
            colour = 0xF8
            y2 = ((shift + 0x1C) * t >> 3) + 0xA4
        elif code == 2:
            x1 = x2 + ((x1 - x2) * t >> 3)
            colour = 0xE0F8
            y1 = y2 + ((0xA4 - y2) * t >> 3)
        elif code == 3:
            mid = ((x2 - x1) >> 1) + x1
            x1 = mid + ((x1 - mid) * t >> 3)
            x2 = mid + ((x2 - mid) * t >> 3)
            ym = ((shift + 0x1C) >> 1) + 0xA4
            y1 = ym + ((0xA4 - ym) * t >> 3)
            colour = 0xE0E0E0
            y2 = ym + ((y2 - ym) * t >> 3)
        _set_pkt(ram, poly_f4(ram, ot, _pkt(ram), colour | 0x28000000, x1 & 0xFFFF | y1 << 16,
                              x1 + 3 & 0xFFFF | y1 << 16, x2 & 0xFFFF | y2 << 16, x2 + 3 & 0xFFFF | y2 << 16))
    for k in range(fight - 1, -1, -1):
        a, b = ram.s32(T_MEMBER1 + 4 * k), ram.s32(T_MEMBER2 + 4 * k)
        code = ram.s16(ctx + 0x38 + 2 * k)
        col = 0xF8 if code == 1 else 0xE0F8 if code == 2 else 0xE0E0E0
        yb = (shift + 0xC0) << 16
        _set_pkt(ram, poly_f4(ram, ot, _pkt(ram), col | 0x28000000, a * 0x24 + 0x39 & 0xFFFF | 0xA40000,
                              a * 0x24 + 0x3C & 0xFFFF | 0xA40000, b * 0x24 + 0x39 & 0xFFFF | yb,
                              b * 0x24 + 0x3C & 0xFFFF | yb))


def stage_row(ram: Ram, stage: int, frames: int, key: int, flags: int, x: int, y: int) -> None:
    """FUN_800EFA9C: STAGE n, the stage time and the opponent's face."""
    ot = ot_text(ram)
    text(ram, STR_STAGE_1X if stage + 1 < 10 else STR_STAGE_2D, 6, 0, x + 0x22, y + 0x10, stage + 1)
    frames = frames - (1 << 32) if frames & 0x80000000 else frames
    frames = min(frames, TIME_CAP)
    text(ram, STR_TICKS, 6, 1, y + 0x20, x + 0x39, x + 0x5C)
    text(ram, STR_TIME, 6, 1, y + 0x24, x + 0x22, _sdiv(_sdiv(frames, 60), 60), x + 0x42,
         _smod(_sdiv(frames, 60), 60), x + 0x66, _sdiv(_smod(frames, 60) * 100, 60))
    _set_pkt(ram, small_face(ram, ot, _pkt(ram), x + 0xF, y + 0x1E, key, flags))
    x0, x1 = x + 0xD & 0xFFFF, x + 0x8D & 0xFFFF
    ya, yb = (y + 0x18) << 16, (y + 0x40) << 16
    p = poly_g4(ram, ot, _pkt(ram), 0x3ADEDEDE, 0, 0xDEDEDE, 0, x0 | ya, x1 | ya, x0 | yb, x1 | yb)
    _set_pkt(ram, dr_mode(ram, ot, p, 0x40))


TIME_CAP = 359_999


def your_time(ram: Ram) -> None:
    """FUN_800EFD14: YOUR TIME, the total and the player's face; NEW RECORD blinks."""
    if ram.u32(A_SHOW) == 0:
        return
    text(ram, STR_YOUR_TIME, 2, 1, 0x25, 0x160)
    t = ram.s32(A_TOTAL)
    t = min(t, TIME_CAP)
    text(ram, STR_TOTAL_TICKS, 7, 2, 0x80, 0x17C, 0xBD, 200)
    text(ram, STR_TOTAL_TIME, 7, 2, 0x5E, 0x17C, _sdiv(_sdiv(t, 60), 60), 0x97, _smod(_sdiv(t, 60), 60), 0xD7,
         _sdiv(_smod(t, 60) * 100, 60))
    _set_pkt(ram, portrait(ram, ot_text(ram), _pkt(ram), 0x121, 0x170, ram.u32(A_KEY), 0))
    if ram.u32(A_WAIT) == 0 and ram.u32(A_RECORD) != 0:
        text(ram, STR_NEW_RECORD, 5 if ram.u32(FRAME_COUNT2) & 3 else 6, 1, 0x62, 0x1A8)


def _digits_format(ram: Ram, value: int, cap_digits: int) -> tuple[int, int]:
    n = value
    if n < 10:
        k = 1
    elif n < 100:
        k = 2
    elif n < 1000:
        k = 3
    elif n < 10000:
        k = 4
    elif n < 100000:
        k = 5
    elif n < 1000000:
        k = 6
    elif n < 10000000:
        k = 7
    else:
        k = 8
        if n > 99_999_999:
            value = 99_999_999
    return min(k, cap_digits), value


def survival_wins(ram: Ram, wins: int, x: int, y: int) -> None:
    """FUN_800F04C4: the total and WIN/WINS."""
    wins = wins - (1 << 32) if wins & 0x80000000 else wins
    k, value = _digits_format(ram, wins, 3)
    tail = strcpy(ram, SCRATCH, FMT_PREFIX)
    strcpy(ram, tail, STR_BLANK8)
    strcpy(ram, tail + (3 - k), ram.u32(DIGIT_FORMATS + 4 * k))
    text(ram, SCRATCH, 0, 2, x + 0x1A, y, value)
    text(ram, STR_WIN if wins < 2 else STR_WINS, 6, 1, x + 0x60, y + 0xE, value)


def survival_rank(ram: Ram, rank: int, x: int, y: int) -> None:
    """FUN_800F068C: YOU ARE THE nth / GREATEST SURVIVOR!, or YOU NEED MORE PRACTICE!"""
    rank = rank - (1 << 32) if rank & 0x80000000 else rank
    tail = strcpy(ram, SCRATCH, FMT_PREFIX)
    suffix = min(rank, 4)
    if rank == 0:
        colour = 5 if ram.u32(FRAME_COUNT2) & 0x10 else 2
        tail = strcpy(ram, SCRATCH, FMT_PREFIX)
        strcpy(ram, tail, STR_PRACTICE)
        y += 0x1A
        x2 = 0x22
    else:
        end = strcpy(ram, tail, STR_YOU_ARE)
        if rank > 100:
            rank = 99
        tens = rank // 10
        ram.put(end, "B", 0x20 if tens == 0 else tens + 0x30)
        ram.put(end + 1, "B", rank - tens * 10 + 0x30)
        strcpy(ram, end + 2, ram.u32(ORDINALS + 4 * suffix))
        text(ram, SCRATCH, 5, 1, 0x56, y, 6 if ram.u32(FRAME_COUNT2) & 2 else 2)
        tail = strcpy(ram, SCRATCH, FMT_PREFIX)
        strcpy(ram, tail, STR_GREATEST)
        colour, x2 = 5, 0x43
        y += 0x1C
    text(ram, SCRATCH, colour, 1, x2, y)


def survivor_cell(ram: Ram, wins: int, key: int, flags: int, x: int, y: int) -> None:
    """FUN_800F0858: one defeated character's portrait and win count (mod 100, coloured by hundreds)."""
    ot = ot_text(ram)
    if ram.u32(S_SHOW) != 0:
        wins = wins - (1 << 32) if wins & 0x80000000 else wins
        rest = _smod(wins, 100)
        colour = ram.u8(SURVIVOR_COLOURS + (_sdiv(wins, 100) & 3))
        k, rest = _digits_format(ram, rest, 2)
        tail = strcpy(ram, SCRATCH, FMT_PREFIX)
        strcpy(ram, tail, STR_BLANK8)
        strcpy(ram, tail + (2 - k), ram.u32(DIGIT_FORMATS + 4 * k))
        text(ram, SCRATCH, colour, 0, x + 0x14, y + 0x44, rest)
    _set_pkt(ram, portrait(ram, ot, _pkt(ram), x + 2, y + 2, key, flags))


def result_picture(ram: Ram, ot: int, p: int) -> int:
    """FUN_800F1150: the 368 x 480 picture uploaded to VRAM 512-703 (time attack, Tekken Force)."""
    p = image(ram, ot, p, 0, 0, 0x80, 0x100, 0x200, 0, 0x7FE0, 0x80)
    p = image(ram, ot, p, 0x80, 0, 0x80, 0x100, 0x240, 0, 0x7FE0, 0x80)
    p = image(ram, ot, p, 0x100, 0, 0x70, 0x100, 0x280, 0, 0x7FE0, 0x80)
    p = image(ram, ot, p, 0, 0x100, 0x80, 0xE0, 0x200, 0x100, 0x7FE0, 0x80)
    p = image(ram, ot, p, 0x80, 0x100, 0x80, 0xE0, 0x240, 0x100, 0x7FE0, 0x80)
    return image(ram, ot, p, 0x100, 0x100, 0x70, 0xE0, 0x280, 0x100, 0x7FE0, 0x80)


def result_banner(ram: Ram, colour: int) -> None:
    """FUN_800F18FC: the scrolling tile strip and banner over the gradient backdrop."""
    ot = ot0(ram)
    p = _pkt(ram)
    bx = _smod(ram.s32(BANNER_X) + 0x17F, 0x180)
    ram.put(BANNER_X, "i", bx)
    x = bx - 0x180
    for k in range(7):
        w = ram.u32(BANNER_TILES + 4 * k)
        vb = ram.u8(BANNER_TILES + 4 * k + 1)
        if x < 0x170:
            u = w & 0xFF
            v8 = vb << 8
            u2 = u + 0x18 & 0xFF
            xx = x
            while True:
                if xx > -0x30:
                    x30 = xx + 0x30 & 0xFFFF
                    v28 = (vb + 0x28 & 0xFF) << 8
                    p = poly_ft4(ram, ot, p, 0x2C606060, xx & 0xFFFF | 0x5F0000, x30 | 0x5F0000,
                                 xx & 0xFFFF | 0xAF0000, x30 | 0xAF0000, u | v8 | w & 0xFFFF0000,
                                 u2 | v8 | 0x6E0000, u | v28 | (u2 | v28) << 16)
                xx += 0x180
                if xx >= 0x170:
                    break
        x += 0x30
    by = (ram.u32(BANNER_Y) + 0x342) % 0x344
    ram.put(BANNER_Y, "I", by)
    sx, sw = ram.s16(SCREEN_X), ram.s16(SCREEN_W)
    p = poly_f4(ram, ot, p, 0x2A606060, sx & 0xFFFF | 0xCB0000, sx + sw & 0xFFFF | 0xCB0000,
                ram.u16(SCREEN_X) | 0xF50000, sx + sw & 0xFFFF | 0xF50000)
    _set_pkt(ram, dr_mode(ram, ot, p, 0x40))
    y = by - 0x344
    while y < 0x170:
        text(ram, STR_BANNER_FMT, 0, 6, 2, y, 0xCB, STR_BANNER)
        y += 0x344
    p = backdrop(ram, ot, _pkt(ram), 0, colour)
    _set_pkt(ram, tile(ram, ot, p, 0x60000000, 0, 0x1E00170))


def force_portrait(ram: Ram, x: int, y: int) -> None:
    """FUN_800F1C00: the player's 126 x 212 portrait in a coloured frame (Tekken Force result)."""
    ot = ram.u32(OT_BASE) + 4
    xl = x + 2
    yy = y + 6
    v = ram.u16(F_TEX + 2) + 0x14 & 0xFF
    u = (ram.u16(F_TEX) & 0x3F) * 2
    if ram.u8(F_FLIP) == 0:
        dx = 0x7E
    else:
        dx = -0x7E
        xl = x + 0x80
    xr = xl + dx & 0xFFFF
    rem, ty, lim = 0xD4, 0x14, 0x40
    clut_hi = ram.u16(F_TEX + 6)
    tp = ram.u16(F_TEX + 4)
    p = _pkt(ram)
    while True:
        seg = rem
        if lim < ty + rem:
            seg = lim - ty
            lim += 0x40
        ya = yy << 16
        yy += seg
        va = (v & 0xFF) << 8
        v += seg
        vb = (v & 0xFF) << 8
        p = poly_ft4(ram, ot, p, 0x2D000000, xl & 0xFFFF | ya, xr | ya, xl & 0xFFFF | yy << 16, xr | yy << 16,
                     u | va | tp << 16, u + 0x7D | va | clut_hi << 16, u | vb | (u + 0x7D | vb) << 16)
        tp += 4
        rem -= seg
        ty += seg
        if rem == 0:
            break
    for i in range(4):
        e = FORCE_FRAME + 8 * i
        p = tile(ram, ot, p, 0x60F0F0F0, ram.s16(e) + x & 0xFFFF | (ram.s16(e + 2) + y) << 16, ram.u32(e + 4))
    colour = ram.u32(F_COLOUR)
    x0, x80 = x + 2 & 0xFFFF, x + 0x80 & 0xFFFF
    y6, y70, yda = (y + 6) << 16, (y + 0x70) << 16, (y + 0xDA) << 16
    p = poly_g4(ram, ot, p, 0x3A000000, 0, colour, colour, x0 | y6, x80 | y6, x0 | y70, x80 | y70)
    p = poly_g4(ram, ot, p, colour | 0x3A000000, colour, 0xC0C0C0, 0xC0C0C0, x0 | y70, x80 | y70, x0 | yda, x80 | yda)
    _set_pkt(ram, dr_mode(ram, ot, p, 0x20))


# ---- whole result screens (logic from screens_sim, drawing here) ----
RESULT_PACKETS = 0x800FAE80      # + buffer * 0x3C00
BRIGHT = 0x800FAE78
DISPLAY_BUFFER = 0x800AE3C4
STR_TEAM_TITLE, STR_TA_TITLE, STR_SURV_TITLE, STR_TOTAL = 0x800B94A8, 0x800B95C4, 0x800B9710, 0x800B9700
TA_ROW_POS = 0x800B94F4          # 11 x (s16 x, s16 y)
SURVIVOR_POS = 0x800B960C        # 22 x (s16 x, s16 y)
HISCORE = 0x800982F4             # what force.ovl FUN_800B6404 returns
F_SHOWN, F_BOSS, F_PHASE, F_FORCE = 0x800FAE64, 0x800FAE68, 0x800FAE6C, 0x800FAE70
F_FRAME = 0x800FAE60
S_TOTAL, S_RANK, S_WAIT, S_ROW, S_ANIM, S_CHARS = 0x800FAE40, 0x800FAE30, 0x800FAE3C, 0x800FAE28, 0x800FAE48, 0x800FAE10
A_ROWS, A_ROW_ANIM = 0x800FADD8, 0x800FADDC
LADDER = MODE + 0x90


def _begin_screen(ram: Ram) -> int:
    saved = _pkt(ram)
    _set_pkt(ram, RESULT_PACKETS + ram.u32(DISPLAY_BUFFER) * 0x3C00)
    _set_pkt(ram, fade(ram, ot_text(ram), _pkt(ram), ram.s32(BRIGHT)))
    return saved


def team_screen_draw(ram: Ram) -> None:
    saved = _begin_screen(ram)
    text(ram, STR_TEAM_TITLE, 6, 1, 0x43, 0x1C)
    team_message(ram, MODE)
    team_labels(ram, MODE)
    team_lines(ram, MODE, ram.u32(T_FIGHT), ram.u32(T_LINE), 0)
    team_members(ram, MODE + 0x59, ram.u32(T_LOST1), 0x28, 100, 0)
    team_members(ram, MODE + 0x66, ram.u32(T_LOST2), 0x28, _rows_shift(ram) * 0x1E + 0xC0, 1)
    team_grid(ram, MODE, ram.u32(T_FIGHT), MODE + 0x59)
    result_banner(ram, 0x1830F0)
    _set_pkt(ram, saved)


def _stage_record_time(ram: Ram, k: int, last: int) -> int:
    return ram.u32(MODE + 0x40 + 8 * k) if k < 10 else last


def time_attack_screen_draw(ram: Ram) -> None:
    saved = _begin_screen(ram)
    text(ram, STR_TA_TITLE, 6, 1, 0x43, 0x20)
    your_time(ram)
    anim, rows = ram.s32(A_ROW_ANIM), ram.s32(A_ROWS)
    last = 0
    k = 0
    for k in range(max(rows, 0)):
        last = _stage_record_time(ram, k, last)
        key = ram.u8(LADDER + 4 * k) << 2 | ram.u8(LADDER + 4 * k + 1)
        stage_row(ram, k, last, key, 0x40, ram.s16(TA_ROW_POS + 4 * k), ram.s16(TA_ROW_POS + 4 * k + 2))
    k = max(rows, 0)
    if anim:
        last = _stage_record_time(ram, k, last)
        t = (last * anim) & 0xFFFFFFFF
        t = t - (1 << 32) if t & 0x80000000 else t
        if t < 0:
            t += 0xF
        key = ram.u8(LADDER + 4 * k) << 2 | ram.u8(LADDER + 4 * k + 1)
        stage_row(ram, k, (t >> 4) & 0xFFFFFFFF, key, 0, ram.s16(TA_ROW_POS + 4 * k), ram.s16(TA_ROW_POS + 4 * k + 2))
    p = result_picture(ram, ot0(ram), _pkt(ram))
    tile(ram, ot0(ram), p, 0x602030A0, 0, 0x1E00170)
    _set_pkt(ram, saved)


def survival_screen_draw(ram: Ram) -> None:
    saved = _begin_screen(ram)
    text(ram, STR_SURV_TITLE, 6, 1, 0x56, 0x1C)
    if ram.s32(S_SHOW) > 1:
        survival_wins(ram, ram.u32(S_TOTAL), 0x78, 0x160)
        text(ram, STR_TOTAL, 6, 1, 0x54, 0x148)
        if ram.u32(S_WAIT) == 0:
            survival_rank(ram, ram.u32(S_RANK), 99, 400)
    rows = ram.s32(S_ROW)
    for i in range(max(rows, 0)):
        char = ram.u8(S_CHARS + i)
        wins = ram.u32(S_ANIM) if i >= rows - 1 else ram.u16(MODE + 0x60 + 2 * char)
        survivor_cell(ram, wins, char << 2, 0x40, ram.s16(SURVIVOR_POS + 4 * i) & 0xFFFFFFFF,
                      ram.s16(SURVIVOR_POS + 4 * i + 2) & 0xFFFFFFFF)
    result_banner(ram, 0xA0C000)
    _set_pkt(ram, saved)


STR_TF_TITLE, STR_SCORE, STR_8D, STR_HIGH = 0x800B9884, 0x800B989C, 0x800B98B0, 0x800B98BC
STR_NEW_RECORD2, STR_SAVED, STR_KEYS = 0x800B98D0, 0x800B98E8, 0x800B9910
STR_COPPER, STR_SILVER, STR_GOLD, STR_CONTINUED = 0x800B9920, 0x800B9930, 0x800B9940, 0x800B9950
STR_BOSS, STR_FORCE, STR_4D = 0x800B996C, 0x800B997C, 0x800B998C


def force_screen_draw(ram: Ram) -> None:
    """The drawing of FUN_800F1F08, with the display counters it advances."""
    saved = _begin_screen(ram)
    text(ram, STR_TF_TITLE, 0, 2, 0x34, 0x1C)
    y = 0x78
    shown = ram.s32(F_SHOWN)
    blink = 6 if ram.u32(F_FRAME) & 2 else 2
    if shown > 0x1D:
        text(ram, STR_SCORE, 1, 5, 0x9E, 0x78)
        y = 0xC6
        text(ram, STR_8D, 1, 6, 0xF9, 0x92, ram.u32(MODE + 0x38))
    if shown > 0x3B:
        text(ram, STR_HIGH, 1, 5, 0x9E, y)
        hs = ram.u32(HISCORE)
        text(ram, STR_8D, 1, 6, 0xF9, y + 0x1A, hs)
        y += 0x34
        if ram.u8(MODE + 0x3F):
            text(ram, STR_NEW_RECORD2, 1, blink, 0xC5, y, hs)
    flags = ram.u32(MODE + 0x40)
    if not flags & 0x10:
        if flags & 8:
            if shown > 0x59:
                text(ram, STR_SAVED, 1, 8, 0xF, y + 0xB6, blink)
        else:
            if shown > 0x59:
                text(ram, STR_KEYS, 1, 5, 0x9E, y + 0x4E)
            if flags & 1 and shown > 0x59:
                text(ram, STR_COPPER, 1, 2, 0xDF, y + 0x4E)
            if flags & 2 and shown > 0x77:
                text(ram, STR_SILVER, 1, 6, 0xDF, y + 0x68)
            if flags & 4 and shown > 0x95:
                text(ram, STR_GOLD, 1, 5, 0xDF, y + 0x82)
            if shown >= 0xB4 and shown & 0x30:
                text(ram, STR_CONTINUED, 1, 8, 0x43, y + 0xB6)
    else:
        if shown > 0x59:
            ram.put(F_BOSS, "i", ram.s32(F_BOSS) + 1)
            text(ram, STR_BOSS, 1, 5, 0x27, y + 0x68)
            _set_pkt(ram, portrait(ram, ot0(ram), _pkt(ram), 0x34, y + 0x82, ram.u8(MODE + 0x41), 0))
        boss = ram.s32(F_BOSS)
        for limit, bx, off in ((0x13, 0x58, 0x42), (0x27, 0x7C, 0x43), (0x3B, 0xA0, 0x44)):
            if boss > limit:
                _set_pkt(ram, portrait(ram, ot0(ram), _pkt(ram), bx, y + 0x82, ram.u8(MODE + off), 0))
        phase = ram.s32(F_PHASE)
        if phase == 1:
            text(ram, STR_FORCE, 1, 5, 0xDF, y + 0x68)
            text(ram, STR_4D, 1, 6, 0x12D, y + 0x82, ram.u32(F_FORCE))
            if shown & 1 == 0:
                ram.put(F_FORCE, "i", ram.s32(F_FORCE) + 1)
            if ram.u16(MODE + 0x3C) < ram.s32(F_FORCE) or ram.s16(0x800AE6EC) > 2:
                ram.put(F_PHASE, "i", 2)
        elif phase < 2:
            if phase == 0 and boss > 0x4F:
                ram.put(F_PHASE, "i", 1)
                ram.put(F_FORCE, "i", 0)
        elif phase == 2:
            text(ram, STR_FORCE, 1, 5, 0xDF, y + 0x68)
            text(ram, STR_4D, 1, 6, 0x12D, y + 0x82, ram.u16(MODE + 0x3C))
    _set_pkt(ram, result_picture(ram, ot0(ram), _pkt(ram)))
    force_portrait(ram, 0x10, 100)
    _set_pkt(ram, saved)


# ---- ranking.ovl drawing ----
VRAM_SIZE = 0x80098F60           # s16 width, height (set by ResetGraph)
R_STR_RANK, R_STR_S, R_STR_TICKS, R_STR_TIME = 0x800B9540, 0x800B9550, 0x800B9560, 0x800B9570
R_STR_100, R_STR_0, R_STR_PCT, R_STR_3D = 0x800B958C, 0x800B95A4, 0x800B95BC, 0x800B95DC
R_STR_WIN, R_STR_WINS, R_STR_2D = 0x800B95EC, 0x800B95FC, 0x800B960C
R_ORDINALS = 0x800CBE18
R_STYLE_TIME, R_STYLE_SURV, R_STYLE_USE = 0x800CBE28, 0x800CBE34, 0x800CBE3C
R_BAR_COLOURS = 0x800B9378       # 22 x 20 bytes: bar edge, face, top colours
R_TABLE = 0x800CBE68
R_RECORDS, R_SURVIVORS = 0x8009832C, 0x800983DC
R_NAME = 0x800D36F8
R_PACKETS = 0x800CBEF8


CHAR_RECORDS = 0x80098120


def char_name(ram: Ram, key: int) -> int:
    """FUN_8004F2D8(char, 0) -> *record: the character's name string."""
    if key > 0x5C:
        key = 0x58
    return ram.u32(ram.u32(CHAR_RECORDS + 4 * key))


def poly_gt4(ram: Ram, ot: int, p: int, c0, c1, c2, c3, v0, v1, v2, v3, uv0, uv1, uv23) -> int:
    """FUN_8004DC0C: Gouraud textured quad (12 words)."""
    _words(ram, p, ((1, c0), (4, c1), (7, c2), (10, c3), (2, v0), (5, v1), (8, v2), (11, v3), (3, uv0),
                    (6, uv1), (9, uv23 & 0xFFFF), (12, uv23 >> 16)))
    link(ram, ot, p, 12)
    return p + 52


def _area_word(ram: Ram, x: int, y: int, code: int) -> int:
    x, y = _s16(x), _s16(y)
    w, h = ram.s16(VRAM_SIZE), ram.s16(VRAM_SIZE + 2)
    x = 0 if x < 0 else (ram.u16(VRAM_SIZE) - 1 if w - 1 < x else x)
    y = 0 if y < 0 else (ram.u16(VRAM_SIZE + 2) - 1 if h - 1 < y else y)
    return code | (y & 0x3FF) << 10 | x & 0x3FF


def draw_area(ram: Ram, ot: int, p: int, rect: int) -> int:
    """FUN_8004DE10: SetDrawArea(p, rect) and link (clips drawing to the rectangle)."""
    return draw_area_xywh(ram, ot, p, *(ram.u16(rect + 2 * i) for i in range(4)))


def draw_area_xywh(ram: Ram, ot: int, p: int, x: int, y: int, w: int, h: int) -> int:
    ram.put(p + 3, "B", 2)
    ram.put(p + 4, "I", _area_word(ram, x, y, 0xE3000000))
    ram.put(p + 8, "I", _area_word(ram, x + w - 1, y + h - 1, 0xE4000000))
    link(ram, ot, p, 2)
    return p + 12


def _rank_text(ram: Ram, rank: int, colour: int, x: int, y: int) -> int:
    suffix = min(_smod(rank, 10), 3) if rank <= 3 else 3
    n = rank + 1
    if n > 100:
        n = 99
    sfx = ram.u32(R_ORDINALS + 4 * suffix)
    text(ram, R_STR_RANK, 1, colour, 1, x + 0xC, y - 0x22, n, sfx)
    return sfx


def _row_lines(ram: Ram, x: int, y: int) -> None:
    ot = ot0(ram) + 4
    p = tile(ram, ot, _pkt(ram), 0x60909090, x + 8 & 0xFFFF | (y - 0xE) << 16, 0x8003E)
    _set_pkt(ram, tile(ram, ot, p, 0x60909090, x + 0x46 & 0xFFFF | (y - 8) << 16, 0x132 - (x + 8) & 0xFFFF | 0x20000))


def time_row(ram: Ram, rank: int, char: int, rec: int, x: int, y: int, style: int) -> None:
    """FUN_800C133C: 1ST  <face> NAME  mm'ss"hh  entered name."""
    if y & 0xFFFFFFFF >= 0x228:
        return
    s = R_STYLE_TIME + 5 * style
    sfx = _rank_text(ram, rank, ram.u8(s), x, y)
    _set_pkt(ram, portrait(ram, ot0(ram) + 4, _pkt(ram), x + 0x4C, y - 0x3A, char << 2, 8))
    text(ram, R_STR_S, 1, ram.u8(s + 1), 0, x + 0x6F, y - 0x38, char_name(ram, char * 4))
    c = ram.u8(s + 2)
    t = min(ram.s32(rec), TIME_CAP)
    text(ram, R_STR_TICKS, 1, c, 1, y - 0x26, x + 0xB6, x + 0xD9, sfx)
    text(ram, R_STR_TIME, 1, c, 1, y - 0x22, x + 0x9E, _sdiv(_sdiv(t, 60), 60), x + 0xBF,
         _smod(_sdiv(t, 60), 60), x + 0xE3, _sdiv(_smod(t, 60) * 100, 60))
    text(ram, R_STR_S, 1, ram.u8(s + 3), 1, x + 299, y - 0x22, rec + 4)
    _row_lines(ram, x, y)


def survivor_row(ram: Ram, rank: int, entry: int, x: int, y: int, style: int) -> None:
    """FUN_800C16C0: 1ST  <face> NAME  n WIN(S)  entered name."""
    if y & 0xFFFFFFFF >= 0x228:
        return
    wins = min(ram.u16(entry + 2), 999)
    s = R_STYLE_SURV + 4 * style
    sfx = _rank_text(ram, rank, ram.u8(s), x, y)
    char = ram.u16(entry)
    _set_pkt(ram, portrait(ram, ot0(ram) + 4, _pkt(ram), x + 0x4C, y - 0x3A, char << 2, 8))
    text(ram, R_STR_S, 1, ram.u8(s + 1), 0, x + 0x6F, y - 0x38, char_name(ram, char * 4))
    c = ram.u8(s + 2)
    if wins < 2:
        text(ram, R_STR_3D, 1, c, 1, x + 0xAB, y - 0x22, wins, sfx)
        fmt, xx = R_STR_WIN, x + 0xD9
    else:
        text(ram, R_STR_3D, 1, c, 1, x + 0x9E, y - 0x22, wins, sfx)
        fmt, xx = R_STR_WINS, x + 0xCC
    text(ram, fmt, 1, c, 1, xx, y - 0x22, wins)
    text(ram, R_STR_S, 1, ram.u8(s + 3), 1, x + 299, y - 0x22, entry + 4)
    _row_lines(ram, x, y)


def usage_bar(ram: Ram, char: int, share: int, x: int, y: int) -> None:
    """FUN_800C1154: the bar of a usage row, length 129 x share / 1000, in the character's colours."""
    ot = ot0(ram) + 4
    share = _s32(share)
    share = min(share, 1000)
    w = _s16(_sdiv(_s32(share * 0x81), 1000)) if share else 0
    if w == 0:
        return
    e = R_BAR_COLOURS + 0x14 * char
    y18 = (y + 0x18) << 16
    left = x - w
    l16 = left & 0xFFFF
    tl, tr = l16 | y << 16, x & 0xFFFF | y << 16
    bl = l16 | y18
    p = poly_g4(ram, ot, _pkt(ram), ram.u32(e + 4) | 0x38000000, ram.u32(e + 8), ram.u32(e + 4), ram.u32(e + 8),
                tl, tr, bl, x & 0xFFFF | y18)
    e6 = left - 6 & 0xFFFF
    y8 = (y - 8) << 16
    p = poly_f4(ram, ot, p, ram.u32(e) | 0x28000000, e6 | y8, tl, e6 | (y + 0x10) << 16, bl)
    p = poly_g4(ram, ot, p, ram.u32(e + 0xC) | 0x38000000, ram.u32(e + 0x10), ram.u32(e + 0xC), ram.u32(e + 0x10),
                e6 | y8, x - 8 & 0xFFFF | y8, tl, tr)
    _set_pkt(ram, dr_mode(ram, ot, p, 0))


def usage_row(ram: Ram, rank: int, char: int, share: int, top: int, anim: int, x: int, y: int, style: int) -> None:
    """FUN_800C19C4: 1ST  <face> NAME  share %  and a bar relative to the most used character."""
    if y & 0xFFFFFFFF > 0x227:
        return
    shown, bar = 0, 0
    if top:
        shown = _s32(share * anim) >> 6
        bar = _sdiv(_s32(_s32(share * anim) * 1000), top) >> 6
    s = R_STYLE_USE + 3 * style
    _rank_text(ram, rank, ram.u8(s), x, y)
    _set_pkt(ram, portrait(ram, ot0(ram) + 4, _pkt(ram), x + 0x4C, y - 0x3A, char << 2, 8))
    text(ram, R_STR_S, 1, ram.u8(s + 1), 0, x + 0x6F, y - 0x38, char_name(ram, char * 4))
    shown = min(shown, 1000)
    if shown == 1000 or shown == 0:
        text(ram, R_STR_100 if shown == 1000 else R_STR_0, 1, ram.u8(s + 2), 1, x + 0x11B, y - 0x22, 0,
             x + 0x145, y - 0x1E)
    else:
        text(ram, R_STR_PCT, 1, ram.u8(s + 2), 1, x + 0x119, y - 0x22, _sdiv(shown, 10), 0, x + 0x134,
             y - 0x1E, x + 0x13B, _smod(shown, 10))
    usage_bar(ram, char, bar & 0xFFFFFFFF, x + 0x111, y - 0x22)
    _row_lines(ram, x, y)


SCREEN_RECT = 0x800AE6F8         # s16 x, y, w, h of the display
R_HEADER_VRAM = (0x180, 0)


def ranking_header(ram: Ram) -> None:
    """FUN_800C2108: the page header picture and its two shaded bars."""
    ot = ot0(ram) + 4
    p = image(ram, ot, _pkt(ram), 0, 0x24, 0x80, 0x30, 0x180, 0, 0x7F50, 0x80)
    p = image(ram, ot, p, 0x80, 0x24, 0x70, 0x30, 0x180, 0x30, 0x7F50, 0x80)
    p = poly_gt4(ram, ot, p, 0x3E808080, 0x606060, 0x808080, 0x606060, 0x2400F0, 0x240100, 0x5400F0, 0x540100,
                 0x7F503070, 0xA63080, 0x60806070)
    p = poly_gt4(ram, ot, p, 0x3E808080, 0x606060, 0x808080, 0x606060, 0x2400F0, 0x240100, 0x5400F0, 0x540100,
                 0x7FD03070, 0xC63080, 0x60806070)
    p = poly_gt4(ram, ot, p, 0x3E606060, 0x101010, 0x606060, 0x101010, 0x240100, 0x240170, 0x540100, 0x540170,
                 0x7F506000, 0xA66070, 0x90709000)
    _set_pkt(ram, poly_gt4(ram, ot, p, 0x3E606060, 0x101010, 0x606060, 0x101010, 0x240100, 0x240170, 0x540100,
                           0x540170, 0x7FD06000, 0xC66070, 0x90709000))


def _usage_rows(ram: Ram, t: int) -> None:
    for i in range(ram.u16(t + 0xC)):
        c = ram.u16(t + 0xE + 2 * i)
        anim = 0 if i < ram.s32(t + 0x54) else ram.u16(t + 0xA)
        usage_row(ram, i, c, ram.u16(t + 0x58 + 2 * c), ram.u16(t + 0x84), anim, 0, ram.s16(t + 2) + 0x48 * i, 0)


def ranking_page(ram: Ram, page: int) -> None:
    """FUN_800C23D8: the rows of a page, clipped below the header."""
    ot, t = ot0(ram) + 4, R_TABLE
    _set_pkt(ram, draw_area(ram, ot, _pkt(ram), SCREEN_RECT))
    if page == 1:
        for i in range(ram.u16(t + 0xC)):
            survivor_row(ram, i, R_SURVIVORS + 8 * ram.u16(t + 0xE + 2 * i), 0, ram.s16(t + 2) + 0x48 * i, 0)
    elif page == 0:
        for i in range(ram.u16(t + 0xC)):
            c = ram.u16(t + 0xE + 2 * i)
            time_row(ram, i, c, R_RECORDS + 8 * c, 0, ram.s16(t + 2) + 0x48 * i, 0)
    elif page == 2:
        _usage_rows(ram, t)
    _set_pkt(ram, draw_area_xywh(ram, ot, _pkt(ram), 0, 0x60, 0x170, 0x168))


def _entry_cursor(ram: Ram, t: int) -> None:
    pos = ram.u16(R_NAME + 4)
    if pos < 3:
        _set_pkt(ram, tile(ram, ot0(ram) + 8, _pkt(ram), 0x600000FF,
                           pos * 0xD + 0x129 & 0xFFFF | (ram.u16(t + 0x86) * 0x48 + 0xA0) << 16, 0x40012))


def ranking_entry_page(ram: Ram, page: int) -> None:
    """FUN_800C2898 (with FUN_800C2624 / FUN_800C2760): the page during name entry, the new row blinking."""
    ot, t = ot0(ram) + 4, R_TABLE
    _set_pkt(ram, draw_area(ram, ot, _pkt(ram), SCREEN_RECT))
    blink = ram.u32(FRAME_COUNT2) & 3 != 0
    if page in (0, 1):
        if ram.s16(t + 0xC):
            for i in range(ram.u16(t + 0xC)):
                c = ram.u16(t + 0xE + 2 * i)
                hi = int(ram.u16(t + 0x88) == i and blink)
                y = ram.s16(t + 2) + 0x48 * i
                if page == 0:
                    time_row(ram, i, c, 0x80098324 + 8 * c + 8, 0, y, hi)
                else:
                    survivor_row(ram, i, 0x80098324 + 8 * c + 0xB8, 0, y, hi)
        _entry_cursor(ram, t)
    elif page == 2:
        _usage_rows(ram, t)
    _set_pkt(ram, draw_area_xywh(ram, ot, _pkt(ram), 0, 0x60, 0x170, 0x170))


def ranking_screen_draw(ram: Ram) -> None:
    """The drawing section of FUN_800C2A24 (game state 17), with the backdrop update it runs."""
    import screens_sim as ss
    saved = _pkt(ram)
    _set_pkt(ram, R_PACKETS + ram.u32(DISPLAY_BUFFER) * 0x3C00)
    mode = ram.u16(R_TABLE)
    page = ram.u8(0x800984DC)
    if mode == 0:
        tile(ram, ot0(ram), _pkt(ram), 0x60000000, 0, 0x1E00170)
        _set_pkt(ram, saved)
        return
    if mode not in (1, 2, 3, 4):
        _set_pkt(ram, saved)
        return
    if mode == 1:
        ranking_header(ram)
    elif mode == 2:
        ranking_header(ram)
        ranking_page(ram, page)
    else:
        if mode == 3:
            p = tile(ram, ot0(ram), _pkt(ram), 0x62100000, (ram.u16(R_TABLE + 0x86) * 0x48 + 0x68) << 16, 0x480170)
            _set_pkt(ram, dr_mode(ram, ot0(ram), p, 0))
        left = ram.u16(R_TABLE + 6)
        text(ram, R_STR_2D, 1, 6, 1, 0x13C, 0x30, 0 if left == 0 else (left + 0x3B) // 0x3C)
        ranking_header(ram)
        ranking_entry_page(ram, page)
    if ram.u8(0x800AFF68) == 0:
        ram.put(0x8009EB20, "I", 2)
    ss.backdrop_camera(ram)
    _set_pkt(ram, saved)


class RankingDraw:
    """Drawing for screens_sim.ranking_frame: the section at the end, and the fades of sub-states 3 and 9."""

    def __call__(self, ram: Ram) -> None:
        ranking_screen_draw(ram)

    @staticmethod
    def fade(ram: Ram, level: int) -> None:
        _set_pkt(ram, fade(ram, ot_text(ram), _pkt(ram), level))


RANKING_DRAW = RankingDraw()


# ---- ending.ovl: staff roll drawing ----
R_PACKETS_G, R_PACKETS_T, R_OT = 0x80194664, 0x80194668, 0x8019466C
R_LEFT, R_Y, R_X0, R_X1, R_WIDTH = 0x8019462C, 0x80194630, 0x80194634, 0x80194638, 0x80194640
R_RGB, R_BRIGHT = 0x80194626, 0x80194648
ROLL_FONTS = {0: (0xE, 0x24, 0x12, 0xC, 0x800BC054), 1: (0x15, 0, 0xC, 8, 0x800BC014)}


def roll_glow(ram: Ram, left: int, y: int, x0: int, x1: int, width: int, r: int, g: int, b: int) -> None:
    """FUN_80113A3C: the glow behind a credit line (25 Gouraud quads, additive)."""
    ot = ram.u32(R_OT)
    full = (r & 0xFF) | (g & 0xFF) << 8 | (b & 0xFF) << 16
    half = (r & 0xFF) >> 1 | ((g & 0xFF) >> 1) << 8 | ((b & 0xFF) >> 1) << 16
    p = dr_mode(ram, ot, ram.u32(R_PACKETS_G), 0x20)
    q = lambda *a: poly_g4(ram, ot, p, *a)                         # noqa: E731
    Y = lambda d: ((y + d) << 16) & 0xFFFFFFFF                     # noqa: E731
    X = lambda v: v & 0xFFFF                                       # noqa: E731
    a1, a17, a2 = X(left - 0x10), X(left + 0x18), X(left + 0x30)
    a13, a3 = X(x0 + 0x10), X(x0 + 0x10 + width - 0x28)
    a4, a10, a5 = X(x1), X(x1 - 0x18), X(x1 + 0x28)
    a11, a12 = X(left - 0x20), X(left + 0x24)
    a6, a7 = X(x1 - 0xC), X(x1 + 0x38)
    ym2, yp1, yp4, yp7, yp10, yp13 = Y(-2), Y(1), Y(4), Y(7), Y(10), Y(13)
    h9, f15 = half | 0x3A000000, full | 0x3A000000
    for args in (
        (0x3A000000, half, 0, half, a1 | ym2, a17 | ym2, a1 | yp1, a17 | yp1),
        (h9, half, half, full, a17 | ym2, a2 | ym2, a17 | yp1, a2 | yp1),
        (h9, half, full, full, a13 | ym2, a3 | ym2, a13 | yp1, a3 | yp1),
        (h9, half, half, full, a4 | ym2, a10 | ym2, a4 | yp1, a10 | yp1),
        (0x3A000000, half, 0, half, a5 | ym2, a4 | ym2, a5 | yp1, a4 | yp1),
        (0x3A000000, full, 0, full, a11 | yp1, a12 | yp1, a11 | yp4, a12 | yp4),
        (f15, full, full, full, a12 | yp1, a2 | yp1, a12 | yp4, a2 | yp4),
        (f15, full, full, full, a13 | yp1, a3 | yp1, a13 | yp4, a3 | yp4),
        (f15, full, full, full, a10 | yp1, a6 | yp1, a10 | yp4, a6 | yp4),
        (f15, 0, full, 0, a6 | yp1, a7 | yp1, a6 | yp4, a7 | yp4),
    ):
        p = poly_g4(ram, ot, p, *args)
    b22 = X(left + 0x16)
    p = poly_g4(ram, ot, p, 0x3A000000, half, 0, full, a11 | yp4, b22 | yp4, a11 | yp7, b22 | yp7)
    p = poly_g4(ram, ot, p, h9, full, full, full, b22 | yp4, a2 | yp4, b22 | yp7, a2 | yp7)
    p = poly_g4(ram, ot, p, f15, full, full, full, a13 | yp4, a3 | yp4, a13 | yp7, a3 | yp7)
    c2 = X(x1 + 2)
    p = poly_g4(ram, ot, p, h9, full, full, full, c2 | yp4, a10 | yp4, c2 | yp7, a10 | yp7)
    p = poly_g4(ram, ot, p, 0x3A000000, half, 0, full, a7 | yp4, c2 | yp4, a7 | yp7, c2 | yp7)
    for args in (
        (0x3A000000, full, 0, full, a11 | yp7, a12 | yp7, a11 | yp10, a12 | yp10),
        (f15, full, full, full, a12 | yp7, a2 | yp7, a12 | yp10, a2 | yp10),
        (f15, full, full, full, a13 | yp7, a3 | yp7, a13 | yp10, a3 | yp10),
        (f15, full, full, full, a10 | yp7, a6 | yp7, a10 | yp10, a6 | yp10),
        (f15, 0, full, 0, a6 | yp7, a7 | yp7, a6 | yp10, a7 | yp10),
        (h9, 0, half, 0, a17 | yp10, a1 | yp10, a17 | yp13, a1 | yp13),
        (f15, half, half, half, a2 | yp10, a17 | yp10, a2 | yp13, a17 | yp13),
        (f15, full, half, half, a13 | yp10, a3 | yp10, a13 | yp13, a3 | yp13),
        (f15, half, half, half, a10 | yp10, a4 | yp10, a10 | yp13, a4 | yp13),
        (h9, 0, half, 0, a4 | yp10, a5 | yp10, a4 | yp13, a5 | yp13),
    ):
        p = poly_g4(ram, ot, p, *args)
    ram.put(R_PACKETS_G, "I", p)


def roll_text(ram: Ram, x: int, y: int, font: int, bright: int, s: int) -> None:
    """FUN_8011484C: a credit line as additive POLY_FT4 glyphs (12 pixels high) from the font sheets."""
    cols, v0, cell, space, table = ROLL_FONTS[0 if font == 0 else 1]
    ot = ram.u32(OT_BASE) + 0x18
    x &= 0xFFFF
    while True:
        c = ram.u8(s)
        s += 1
        if c == 0:
            return
        if c == 0x20:
            x = (x + space) & 0xFFFF
            continue
        i = c - 0x21 if c < 0x31 else c - 0x22
        w = ram.u8(table + i)
        u = _smod(i, cols) * cell & 0xFF
        v = _sdiv(i, cols) * 0xC + v0 & 0xFF
        p = ram.u32(R_PACKETS_T)
        ram.put(p + 3, "B", 9)
        ram.put(p + 7, "B", 0x2E)
        for k in (4, 5, 6):
            ram.put(p + k, "B", bright)
        ram.put(p + 0xC, "B", u)
        ram.put(p + 0x16, "H", 0x2A)
        ram.put(p + 0xE, "H", 0x1828)
        ram.put(p + 0xD, "B", v)
        ram.put(p + 0x14, "B", u + w)
        ram.put(p + 0x15, "B", v)
        ram.put(p + 0x1C, "B", u)
        ram.put(p + 0x1D, "B", v + 0xC)
        ram.put(p + 0x24, "B", u + w)
        ram.put(p + 0x25, "B", v + 0xC)
        ram.put(p + 0x10, "H", x + w)
        ram.put(p + 0x20, "H", x + w)
        ram.put(p + 0x8, "H", x)
        ram.put(p + 0xA, "H", y)
        ram.put(p + 0x12, "H", y)
        ram.put(p + 0x18, "H", x)
        ram.put(p + 0x1A, "H", y + 0xC)
        ram.put(p + 0x22, "H", y + 0xC)
        ram.put(p, "I", ram.u32(p) & 0xFF000000 | ram.u32(ot) & 0xFFFFFF)
        ram.put(ot, "I", ram.u32(ot) & 0xFF000000 | p & 0xFFFFFF)
        ram.put(R_PACKETS_T, "I", p + 0x28)
        x = (x + w) & 0xFFFF


def roll_logo(ram: Ram, bright: int) -> None:
    """FUN_80114550: the Namco logo (two additive POLY_FT4, 261 x 45 at (54, 220))."""
    ot = ram.u32(R_OT)
    for tpage, u1, xa, xb in ((0xA, 0xFF, 0x36, 0x136), (0xB, 4, 0x136, 0x13B)):
        p = ram.u32(R_PACKETS_T)
        ram.put(p + 3, "B", 9)
        ram.put(p + 7, "B", 0x2E)
        for k in (4, 5, 6):
            ram.put(p + k, "B", bright)
        ram.put(p + 0x16, "H", tpage)
        ram.put(p + 0xE, "H", 0x2C28)
        for off, val in ((0xC, 0), (0xD, 0x80), (0x14, u1), (0x15, 0x80), (0x1C, 0), (0x1D, 0xAC),
                         (0x24, u1), (0x25, 0xAC)):
            ram.put(p + off, "B", val)
        for off, val in ((8, xa), (0xA, 0xDC), (0x10, xb), (0x12, 0xDC), (0x18, xa), (0x1A, 0x109),
                         (0x20, xb), (0x22, 0x109)):
            ram.put(p + off, "H", val)
        ram.put(p, "I", ram.u32(p) & 0xFF000000 | ram.u32(ot) & 0xFFFFFF)
        ram.put(R_PACKETS_T, "I", p + 0x28)
        ram.put(ot, "I", ram.u32(ot) & 0xFF000000 | p & 0xFFFFFF)


class RollDraw:
    """Drawing for screens_sim.staff_roll."""

    @staticmethod
    def glow(ram: Ram, rgb=None) -> None:
        r, g, b = rgb if rgb else (ram.u8(R_RGB), ram.u8(R_RGB + 1), ram.u8(R_RGB + 2))
        roll_glow(ram, ram.s32(R_LEFT), ram.s32(R_Y), ram.s32(R_X0), ram.s32(R_X1), ram.s32(R_WIDTH), r, g, b)

    @staticmethod
    def text(ram: Ram, y: int, font: int, s: int) -> None:
        roll_text(ram, ram.s32(R_X0), y, font, ram.u8(R_BRIGHT), s)

    @staticmethod
    def logo(ram: Ram) -> None:
        roll_logo(ram, ram.u8(R_BRIGHT))


ROLL_DRAW = RollDraw()


# ---- fight HUD (HudRoundUpdate 0x8003D904 and its parts) ----
FIGHTERS = (0x800A96F0, 0x800AAF7C)
HUD_OT = 0x800AE21C
TIMER_UV = 0x80022154
HEALTH = 0x800980F4              # per player 16 bytes: s32 last health, s16 target, drawn, recent, side, x, y
MARK_UV = 0x80022190
PREV_WINS = 0x80098114
NAME_POS = 0x800221A0            # per player 8 bytes: u16 x, y
NAME_W, NAME_UV, NAME_TP, NAME_COL = 0x8009F668, 0x8009F670, 0x8009F678, 0x8009F67C
PLATE_COLOURS = 0x80022198
MODE_LINE_X = 0x80022228
COIN_X = 0x8002222C
PADS = 0x800A964C                # connected controllers, bit per port
COIN_TEXTS, FREE_TEXTS = 0x800223A0, 0x800223D8
STR_COIN = 0x80022400
STR_GAME_OVER_LINE, STR_TEAM_LINE, STR_TA_LINE, STR_SURV_LINE, STR_BALL_LINE = 0x80022234, 0x80022248, 0x80022260, 0x80022278, 0x80022290
HUD_SCORE, HUD_HISCORE = 0x800222A8, 0x800222BC
FORCE_SCORE, FORCE_HISCORE = 0x800B70EC, 0x800B7100
A_STAGE, A_FINAL, A_TICKS, A_TIME = 0x800B0A18, 0x800B0A2C, 0x800B0A3C, 0x800B0A4C
A_COUNT_TEXTS, A_WINS_TEXTS = 0x800B4E78, 0x800B4E64
PRACTICE_WINS = (0x800221B8, 0x800221C0, 0x800221C8, 0x800221D0)
R_ROUND, R_FINAL_ROUND, R_TEAM, R_SURVIVAL, R_PRACTICE = 0x8001A3F8, 0x8001A40C, 0x8001A420, 0x8001A434, 0x8001A44C
R_STAGE, R_FINAL_STAGE, R_READY = 0x8001A464, 0x8001A478, 0x8001A48C
R_TIME_UP, R_PERFECT, R_DOUBLE_KO, R_KO, R_DRAW = 0x8001A4C0, 0x8001A4D0, 0x8001A4E4, 0x8001A4F8, 0x8001A508
R_WINS, R_WINNER, R_LOSER, R_YOU_WIN, R_YOU_LOSE, R_GAME_OVER = 0x8001A518, 0x8001A52C, 0x8001A53C, 0x8001A54C, 0x8001A560, 0x8001A37C
ROUND_STATE, ROUND_CLOCK, ROUND_NO, MAX_ROUNDS = 0x80097350, 0x80095884, 0x800958A8, 0x800AE404
RESULT_FLAGS = 0x800AE340
EFFECT_FREE, EFFECT_FREE_END, EFFECT_USED = 0x800A0D2C, 0x800A0D28, 0x800A0D30


def _bcd(ram: Ram, n: int) -> int:
    n &= 0xFFFFFFFF
    if n > 100_000_000:
        return 0x99999999
    out, shift, a = 0, 0x1C, POWERS
    while ram.u32(a):
        pw = ram.u32(a)
        if n >= pw:
            out |= (n // pw) << shift & 0xFFFFFFFF
            n %= pw
        shift -= 4
        a += 4
    return (out + n) & 0xFFFFFFFF


def hud_timer(ram: Ram, value: int, x: int, y: int, clut: int) -> None:
    """FUN_8004E410: two 16 x 46 digits (value -1 shows the infinity sign)."""
    digits = 0xAB if value == -1 else _bcd(ram, value)
    ot, p = ot0(ram), _pkt(ram)
    for _ in range(2):
        d = digits & 0xF
        digits >>= 4
        p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | y << 16, 0x2E0010, ram.u32(TIMER_UV + 4 * d) | clut << 16)
        x -= 0xF
    _set_pkt(ram, dr_mode(ram, ot, p, 0xE))


def hud_health(ram: Ram, h0: int, m0: int, h1: int, m1: int) -> None:
    """FUN_8004E55C: both health bars (caps, then drawn health, recent damage and empty parts)."""
    ot, p = ot0(ram), _pkt(ram)
    for i, (h, m) in enumerate(((h0, m0), (h1, m1))):
        h, m = _s32(h), _s32(m)
        e = HEALTH + 0x10 * i
        target, drawn, recent = ram.s16(e + 4), ram.s16(e + 6), ram.s16(e + 8)
        if ram.s32(e) != h:
            ram.put(e, "i", h)
            unit = _sdiv(m, 0x98)
            target = _sdiv(h - 1 + unit, unit)
        target = min(target, 0x98)
        rec = recent - ((recent - drawn) + 0xF >> 4) if drawn < recent else drawn
        new = target if target <= drawn or target < drawn + 3 else drawn + 3
        rec = max(rec, new)
        lens = (new, rec - new, 0x98 - rec)
        ram.put(e + 4, "h", target)
        ram.put(e + 6, "h", new)
        ram.put(e + 8, "h", rec)
        side, x, y = ram.s16(e + 0xA), ram.u16(e + 0xC), ram.u16(e + 0xE)
        p = sprt(ram, ot, p, 0x65000000, ram.u32(e + 0xC), 0x180006, 0x7EDEA8E0)
        p = sprt(ram, ot, p, 0x65000000, x + 0x96 & 0xFFFF | y << 16, 0x180006, 0x7EDEA8EA)
        pos = x + 2 if side == 1 else x + 0x9A
        top, bot = y << 16, (y + 0x18) << 16 & 0xFFFFFFFF
        for k, n in enumerate(lens):
            if n == 0:
                continue
            if side == 1:
                a = pos
                pos += n
            else:
                pos -= n
                a = pos
            clut = (0x7EDC, 0x7EDD, 0x7EDE)[k]
            b = a + n & 0xFFFF
            p = poly_ft4(ram, ot, p, 0x2D000000, a & 0xFFFF | top, b | top, a & 0xFFFF | bot, b | bot,
                         clut << 16 | 0xA8E8, 0xDA8E9, 0xC0E9C0E8)
    _set_pkt(ram, p)


def hud_marks(ram: Ram, w0: int, w1: int) -> None:
    """FUN_8004E87C: round marks (the mark just won blinks)."""
    ot, p = ot0(ram), _pkt(ram)
    need = ram.u16(0x800AE2C4)
    for i, wins in enumerate((_s32(w0), _s32(w1))):
        x, dx = (0x97, -0xE) if i == 0 else (0xCA, 0xE)
        for k in range(need):
            if k < wins:
                m = int(ram.u32(FRAME_COUNT2) & 0x10 != 0) if k == wins - 1 and ram.u8(PREV_WINS + i) != wins & 0xFFFFFFFF else 0
            else:
                m = 1
            p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | 0x460000, 0x12000F, ram.u32(MARK_UV + 4 * m))
            x += dx
    _set_pkt(ram, dr_mode(ram, ot, p, 0xD))


def hud_names(ram: Ram) -> None:
    """FUN_8004EB9C: the name sprites on their coloured plates."""
    ot, p = ot0(ram), _pkt(ram)
    for i in range(2):
        x, y = ram.u16(NAME_POS + 8 * i), ram.u16(NAME_POS + 8 * i + 2)
        w = ram.u16(NAME_W + 2 * i)
        if i:
            x -= _s16(w)
        p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | y << 16, w | 0x100000, ram.u32(NAME_UV + 4 * i))
        p = dr_mode(ram, ot, p, ram.u16(NAME_TP + 2 * i))
        x0, x1 = x - 4 & 0xFFFF, (x - 4) + _s16(w) + 8 & 0xFFFF
        y9, y19 = (y + 9) << 16, (y + 0x13) << 16
        col = ram.u16(PLATE_COLOURS + 2 * ram.u16(NAME_COL + 2 * i))
        p = poly_ft4(ram, ot, p, 0x2D000000, x0 | y9, x1 | y9, x0 | y19, x1 | y19, col << 16 | 0xA8DC, 0xDA8DE,
                     0xB2DEB2DC)
    _set_pkt(ram, p)


def hud_coin(ram: Ram, player: int, x: int, y: int, colour: int) -> None:
    """FUN_8004F1D0: the demonstration's blinking INSERT COIN / FREE PLAY style prompt."""
    f = ram.u32(FRAME_COUNT2)
    if not f & 0x30:
        return
    n = ram.u16(PADS) >> (player & 31) & 1      # FUN_8002A338: is a controller plugged into this port
    if not f & 0x40:
        k = (1 if player == 0 else 2) if n > 0 else 0
        table = COIN_TEXTS
    else:
        k = int(n == 0)
        table = FREE_TEXTS
    text(ram, STR_COIN, x - ram.u32(table + 8 * k + 4), y, colour, ram.u32(table + 8 * k))


def _arcade_code(ram: Ram, ctx: int, p: int) -> int:
    """FUN_800B2170 (arcade.ovl)."""
    h = ram.u8(ctx + 0x1C)
    if h == 1:
        if p == ram.u8(ctx + 0x1E):
            return 3 if ram.u16(0x800AE6C0 + 2 * p) else 1
        if ram.u8(ctx + 0x12):
            return 2
        if ram.u16(0x800AE6DA):
            return 2
        return int(ram.u8(ctx + 0x13) == 0)
    if h == 2:
        r = ram.u8(ctx + 0x21)
        if r in (0, 3) or ram.u8(ctx + 0x23) != p or not ram.u32(FRAME_COUNT2) & 0x18:
            return 0
        return 2
    return 0


def _team_code(ram: Ram, ctx: int, p: int) -> int:
    """FUN_800B2254."""
    h = ram.u8(ctx + 0x1C)
    if h == 1:
        if p != ram.u8(ctx + 0x1E):
            return 1
        return 4 if ram.u16(0x800AE6C0 + 2 * p) else 1
    if h == 2:
        return 4 if p == 0 else 0
    return 0


def _ta_code(ram: Ram, ctx: int, p: int) -> int:
    if p != ram.u8(ctx + 0x1E):
        return 5
    return 3 if ram.u16(0x800AE6C0 + 2 * p) else 1


def _surv_code(ram: Ram, ctx: int, p: int) -> int:
    if p != ram.u8(ctx + 0x1E):
        return 6
    return 8 if ram.u16(0x800AE6C0 + 2 * p) else 2


def _ball_code(ram: Ram, ctx: int, p: int) -> int:
    """FUN_800B5210 (volley.ovl)."""
    h = ram.u8(ctx + 0x1C)
    if h == 1:
        if p != ram.u8(ctx + 0x1E):
            return 1
        return 9 if ram.u16(0x800AE6C0 + 2 * p) else 1
    if h == 2:
        return 9 if p == 0 else 0
    return 0


def _stage_time(ram: Ram, stage: int, t: int, x: int, y: int) -> None:
    """FUN_800B1E78 (arcade.ovl): STAGE n (or FINAL, blinking) and the running time."""
    t &= 0xFFFFFFFF
    t = min(t, TIME_CAP)
    fmt = A_STAGE if _s32(stage) < 10 or ram.u32(FRAME_COUNT2) & 0x20 else A_FINAL
    text(ram, fmt, 7, 0, x, y, stage)
    text(ram, A_TICKS, 5, 0, x + 0x5C, y - 2, x + 0x75)
    text(ram, A_TIME, 5, 0, x + 0x4B, y, t // 60 // 60, x + 99, t // 60 % 60, x + 0x7D, t % 60 * 100 // 60)


def _survival_count(ram: Ram, n: int, x: int, y: int) -> None:
    """FUN_800B20DC (arcade.ovl)."""
    n = _s32(n)
    if n == 0:
        return
    n = min(n, 10)
    tail = strcpy(ram, SCRATCH, FMT_PREFIX)
    strcpy(ram, tail, ram.u32(A_COUNT_TEXTS + 4 * n))
    text(ram, SCRATCH, 5, 0, x, y)


def _survival_wins(ram: Ram, n: int, x: int, y: int) -> None:
    """FUN_800B2004 (arcade.ovl)."""
    n = min(_s32(n), 9999)
    k = 0 if n <= 1 else 1 if n <= 9 else 2 if n <= 99 else 3 if n < 1000 else 4
    tail = strcpy(ram, SCRATCH, FMT_PREFIX)
    strcpy(ram, tail, ram.u32(A_WINS_TEXTS + 4 * k))
    text(ram, SCRATCH, 1, 0, x, y, n)


def hud_mode_line(ram: Ram) -> None:
    """FUN_8004EFF8 / FUN_8004EE3C: the per-player line under the health bars."""
    ctx = MODE
    mode = ram.u32(ctx)
    for p in range(2):
        code = {0: lambda: _arcade_code(ram, ctx, p), 2: lambda: _team_code(ram, ctx, p),
                3: lambda: _ta_code(ram, ctx, p), 4: lambda: _surv_code(ram, ctx, p),
                6: lambda: 1, 7: lambda: _ball_code(ram, ctx, p), 8: lambda: 10}.get(mode, lambda: 0)()
        x = ram.s16(MODE_LINE_X + 2 * p)
        if code == 1:
            hud_coin(ram, p, ram.s16(COIN_X + 2 * p), 0x18, 5)
        elif code == 2:
            text(ram, STR_GAME_OVER_LINE, 2, 0, x + 0x20, 0x18)
        elif code == 3:
            _stage_time(ram, ram.u32(ctx + 0x24) + 1, ram.u32(ctx + 0x2C) + ram.u32(ctx + 0x34), x, 0x18)
        elif code in (4, 5, 6, 9):
            text(ram, {4: STR_TEAM_LINE, 5: STR_TA_LINE, 6: STR_SURV_LINE, 9: STR_BALL_LINE}[code], 6, 0, x, 0x18)
        elif code == 8:
            _survival_count(ram, ram.u32(ctx + 0x40), x, 0x18)
            _survival_wins(ram, ram.u32(ctx + 0x44), x + 0x30, 0x18)
        elif code == 10:
            if p == 0:
                text(ram, HUD_SCORE, 5, 0, x, 0x18, 6, ram.u32(FORCE_SCORE))
            else:
                text(ram, HUD_HISCORE, 2, 0, x, 0x18, 6, ram.u32(FORCE_HISCORE))


def hud_team(ram: Ram) -> None:
    """FUN_800B1C2C (arcade.ovl): the team members left, as small icons under the bars."""
    ot, p = ot0(ram), _pkt(ram)
    over = ram.u8(MODE + 0x21)
    for i in range(2):
        e = MODE + 0x65 + 0xD * i
        if i == 0:
            x, step, u, du = 0x9C, -9, 0x40, 10
            blink_side = (over - 2) & 0xFFFFFFFF < 2
        else:
            x, step, u, du = 0xCA, 9, 0x49, -10
            blink_side = over in (1, 3)
        u2 = u + du & 0xFF
        lost = ram.u8(e - 3)
        for k in range(ram.u8(e)):
            gone = k < lost
            if gone or (k == lost and blink_side):
                p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | 0x430000, 0x15000A, 0x7ED1E04A)
                lost = ram.u8(e - 3)
                gone = k < lost
            clut = 0x7ED1
            if not gone:
                clut = 0x7ED0
                if k == lost and blink_side and not ram.u32(FRAME_COUNT2) & 0x10:
                    clut = 0x7ED1
            x1 = x + 10 & 0xFFFF
            p = poly_ft4(ram, ot, p, 0x2D000000, x & 0xFFFF | 0x400000, x1 | 0x400000, x & 0xFFFF | 0x580000,
                         x1 | 0x580000, u | clut << 16 | 0xE000, u2 | 0x1FE000, u | (u2 | 0xF800) << 16 | 0xF800)
            x += step
    _set_pkt(ram, dr_mode(ram, ot, p, 0x1F))


def hud_practice_wins(ram: Ram) -> None:
    """FUN_8004ED9C."""
    n = ram.u32(0x8009811C)
    if n == 0:
        return
    t = PRACTICE_WINS[0 if n < 2 else 1 if n < 10 else 2 if n < 100 else 3]
    text(ram, ram.u32(t), 1, 8, ram.u16(t + 4 + 2 * int(ram.u32(0x80098118) != 0)), 0x1B0, n)


def effect_alloc(ram: Ram) -> int:
    """FUN_8006F7DC: take a node from the free effect list and put it on the active list."""
    node = ram.u32(EFFECT_FREE)
    if node == EFFECT_FREE_END:
        return -1
    nxt = ram.u32(node + 4)
    ram.put(EFFECT_FREE, "I", nxt)
    ram.put(nxt, "I", EFFECT_FREE_END)
    ram.put(node + 4, "I", EFFECT_USED)
    ram.put(node, "I", ram.u32(EFFECT_USED))
    ram.put(EFFECT_USED, "I", node)
    ram.put(ram.u32(node) + 4, "I", node)
    ram.put(node + 0xD, "B", 0x80)
    ram.put(node + 0xE, "B", 0)
    return node


def _round_intro(ram: Ram) -> None:
    """FUN_8003DF60: ROUND n / FINAL ROUND / mode caption, then READY?"""
    mode, rn, clock = ram.u32(MODE), ram.s32(ROUND_NO), ram.s32(ROUND_CLOCK)
    fmt = None
    if mode == 2:
        fmt, x, args = R_TEAM, 0x3F, ()
    elif mode == 4:
        fmt, x, args = R_SURVIVAL, 0x13, ()
    elif mode == 5:
        fmt, x, args = R_PRACTICE, 0x29, ()
    elif mode == 8:
        if ram.u32(MODE + 0x24) > 3:
            fmt, x, args = R_FINAL_STAGE, 0x3F, ()
        else:
            fmt, x, args = R_STAGE, 0x6B, (ram.u32(MODE + 0x24) + 1,)
    elif ram.u16(MAX_ROUNDS) <= rn:
        fmt, x, args = R_FINAL_ROUND, 0x3F, ()
    elif (clock >= 0x3D) if rn == 1 else (clock >= 1):
        fmt, x, args = R_ROUND, 0x6B, (rn,)
    if fmt:
        text(ram, fmt, 8, 2, x, 0x70, *args)
    if (clock < 0x6A) if rn == 1 else (clock < 0x2E):
        return
    text(ram, R_READY, 9, 2, 0x76, 0xE4)


def _result_text(ram: Ram) -> None:
    """FUN_8003E200: TIME UP / PERFECT! / DOUBLE K.O. / K.O."""
    if ram.u32(MODE) == 7 and not _s32(ram.u32(MODE + 0x3C) - 1) <= ram.s32(MODE + 0x38):
        return
    if ram.u32(0x80097358):
        return
    f = ram.u32(RESULT_FLAGS)
    if f & 1:
        a = (R_TIME_UP, 3, 0x6B)
    elif f & 8:
        a = (R_PERFECT, 2, 0x60)
    elif f & 4:
        a = (R_DOUBLE_KO, 1, 0x3F)
    else:
        a = (R_KO, 1, 0x8C)
    text(ram, a[0], a[1], 2, a[2], 0xE4)


def _winner_text(ram: Ram) -> None:
    """FUN_8003E408: DRAW, YOU WIN!/YOU LOSE, or <NAME> WINS! with WINNER/LOSER in 2-player arcade."""
    r0, r1 = ram.s16(FIGHTERS[0] + 0x46), ram.s16(FIGHTERS[1] + 0x46)
    if r0 == r1:
        text(ram, R_DRAW, 6, 2, 0x8C, 0x170)
        return
    w = int(r0 <= r1)
    humans = ram.u16(0x800AE3D8)
    if humans == 3 or ram.u32(MODE) == 2:
        key = ram.s16(FIGHTERS[w] + 0x14)
        name = ram.u32(ram.u32(CHAR_RECORDS + 4 * (0x58 if key > 0x5C else key)))
        n = strlen(ram, name)
        text(ram, R_WINS, 4, 2, _s16(0xB8 - (n * 0xB + 0x42)), 0x170, name)
        if ram.u8(MODE + 0x21) == 0 or ram.u32(MODE) != 0:
            return
        text(ram, R_WINNER, 9, 1, w * 0xC4 + 0x2F, 0x68, name)
        text(ram, R_LOSER, 9, 1, (1 - w) * 0xC3 + 0x36, 0x68)
        return
    if humans >> w & 1:
        text(ram, R_YOU_WIN, 4, 2, 0x60, 0x170)
    else:
        text(ram, R_YOU_LOSE, 5, 2, 0x60, 0x170)


def _winner_sounds(ram: Ram) -> None:
    """FUN_8003E2F8: only its effect allocation touches memory (the sounds and music fade are not ported)."""
    if ram.s32(0x80097354) != 1:
        return
    r0, r1 = ram.s16(FIGHTERS[0] + 0x46), ram.s16(FIGHTERS[1] + 0x46)
    if r0 == r1:
        return
    w = int(not r1 < r0)
    if ram.u16(0x800AE3D8) == 3 or ram.u32(MODE) == 2:
        if ram.s16(FIGHTERS[w] + 0x14) != 0x22:
            node = effect_alloc(ram)
            if node != -1:
                ram.put(node + 0xC, "B", 0x10)


def hud_frame(ram: Ram, f0: int = FIGHTERS[0], f1: int = FIGHTERS[1]) -> None:
    """HudRoundUpdate (0x8003D904): round texts and the HUD, in every mode (the overlay parts of
    Tekken Ball and Tekken Force included)."""
    if ram.u32(TEXT_OFF):
        return
    mode = ram.u32(MODE)
    if ram.u16(0x800AE39C) == 0 and ram.u8(0x800AFF63) == 0:
        rs = ram.s16(ROUND_STATE)
        if rs == 0:
            if ram.u32(ROUND_CLOCK):
                _round_intro(ram)
        elif rs == 2:
            if mode != 8 or ram.u32(RESULT_FLAGS) & 1:
                _result_text(ram)
        elif rs in (6, 9) and mode != 8 and mode != 5:
            _winner_text(ram)
            if not (ram.u8(MODE + 0x21) == 0 and ram.u32(0x800958A4) and ram.u32(0x800958B0) == 0):
                _winner_sounds(ram)
    saved = ram.u32(OT_BASE)
    if ram.u16(0x800AE6C8) == 0:
        return
    if ram.u8(MODE + 7):
        hud_practice_wins(ram)
    if mode != 6:
        ram.put(OT_BASE, "I", ram.u32(HUD_OT))
    if mode == 6:
        text(ram, R_GAME_OVER, 2, 1, 0x7E, 0x104)
    if mode == 8:
        force_names(ram)
        hud_mode_line(ram)
        hud_timer(ram, -1 if ram.u32(0x800958D4) else _sdiv(ram.s32(0x800AE094) + 0x3B, 0x3C), 0xB8, 0x16, 0x7F1C)
        force_health(ram, ram.u32(F_PLAYER), F_SLOTS, F_SLOTS + 24)
        ram.put(OT_BASE, "I", saved)
        return
    if mode == 2:
        hud_names(ram)
        if ram.u8(0x80098DDD) != 2 or ram.u8(0x800A8B3A) != 0:
            hud_team(ram)
    else:
        hud_names(ram)
        hud_marks(ram, ram.s16(f0 + 0x44), ram.s16(f1 + 0x44))
    hud_mode_line(ram)
    hud_timer(ram, -1 if ram.u32(0x800958D4) else _sdiv(ram.s32(0x800AE094) + 0x3B, 0x3C), 0xB8, 0x16, 0x7F1C)
    hud_health(ram, ram.u32(f0 + 0x3F4), ram.u32(f0 + 0x3F8), ram.u32(f1 + 0x3F4), ram.u32(f1 + 0x3F8))
    ram.put(OT_BASE, "I", saved)


# Tekken Force HUD (force.ovl): three name plates and health bars
F_PLAYER, F_ENEMIES, F_SLOTS = 0x800B6AAC, 0x800B6AB4, 0x800B6A7C
F_NAME_POS, F_NAME_W, F_NAME_UV, F_NAME_TP, F_NAME_COL = 0x800B0EC8, 0x800B6B00, 0x800B6B10, 0x800B6B20, 0x800B6B28
F_HEALTH_LAST, F_HEALTH = 0x800B69CC, 0x800B69D0
F_BAR_LEN = 0x800B0B38


def _force_visible(ram: Ram, i: int, fighter: int) -> bool:
    return i < 1 or (ram.u8(fighter + 0xC2) == 0 and ram.s16(ROUND_STATE) != 0)


def force_names(ram: Ram) -> None:
    """FUN_800B3790 (force.ovl)."""
    ot, p = ot0(ram), _pkt(ram)
    for i in range(3):
        if i >= 1 and not _force_visible(ram, i, ram.u32(F_ENEMIES + 4 * (i - 1 & 1))):
            continue
        x, y = ram.u16(F_NAME_POS + 8 * i), ram.u16(F_NAME_POS + 8 * i + 2)
        w = ram.u16(F_NAME_W + 2 * i)
        if i:
            x -= _s16(w)
        p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | y << 16, w | 0x100000, ram.u32(F_NAME_UV + 4 * i))
        p = dr_mode(ram, ot, p, ram.u16(F_NAME_TP + 2 * i))
        x0, x1 = x - 4 & 0xFFFF, x + _s16(w) + 4 & 0xFFFF
        y9, y19 = (y + 9) << 16, (y + 0x13) << 16
        p = poly_ft4(ram, ot, p, 0x2D000000, x0 | y9, x1 | y9, x0 | y19, x1 | y19,
                     ram.u16(F_NAME_COL + 2 * i) << 16 | 0xA8DC, 0xDA8DE, 0xB2DEB2DC)
    _set_pkt(ram, p)


def force_health(ram: Ram, player: int, slot1: int, slot2: int) -> None:
    """FUN_800B3118 (force.ovl): the player's bar and one per enemy, sized by enemy type."""
    ot, p = ot0(ram), _pkt(ram)
    for i in range(3):
        if i == 0:
            length, fighter = 0x9C, player
        else:
            slot = slot1 if i == 1 else slot2
            fighter = ram.u32(slot)
            length = ram.u16(F_BAR_LEN + 4 * ram.s16(slot + 0xE))
        if not _force_visible(ram, i, fighter):
            continue
        e = F_HEALTH + 0x10 * i
        target, drawn, recent = ram.s16(e), ram.s16(e + 2), ram.s16(e + 4)
        h = ram.s32(fighter + 0x3F4)
        full = length - 4
        if ram.s32(F_HEALTH_LAST + 0x10 * i) != h:
            unit = _sdiv(ram.s32(fighter + 0x3F8), full)
            ram.put(F_HEALTH_LAST + 0x10 * i, "i", h)
            target = _sdiv(h - 1 + unit, unit)
        target = min(target, full)
        rec = recent - ((recent - drawn) + 0xF >> 4) if drawn < recent else drawn
        new = target if target <= drawn or target < drawn + 3 else drawn + 3
        dmg = rec - new
        if rec < new:
            dmg, rec = 0, new
        ram.put(e, "h", target)
        ram.put(e + 2, "h", new)
        ram.put(e + 4, "h", rec)
        lens = (new, dmg, full - rec)
        side, bx, y = ram.s16(e + 6), ram.u16(e + 8), ram.u16(e + 0xA)
        x = bx if i < 1 else bx - (length - 0x9C)
        p = sprt(ram, ot, p, 0x65000000, x & 0xFFFF | y << 16, 0x180006, 0x7EDEA8E0)
        p = sprt(ram, ot, p, 0x65000000, x + length - 6 & 0xFFFF | y << 16, 0x180006, 0x7EDEA8EA)
        pos = bx + 0x9A
        top, bot = y << 16, (y + 0x18) << 16 & 0xFFFFFFFF
        for k, n in enumerate(lens):
            if n == 0:
                continue
            if side == 1:
                a = pos
                pos += n
            else:
                pos -= n
                a = pos
            b = a + n & 0xFFFF
            p = poly_ft4(ram, ot, p, 0x2D000000, a & 0xFFFF | top, b | top, a & 0xFFFF | bot, b | bot,
                         (0x7EDC, 0x7EDD, 0x7EDE)[k] << 16 | 0xA8E8, 0xDA8E9, 0xC0E9C0E8)
    _set_pkt(ram, p)


# ---- pre-fight VS screen (game state 11, FUN_80052808) ----
VS_TABLE = 0x800B9378            # u16 background id, ..., s32 slide counter at +4, objects from +8
VS_SLIDE = 0x800B937C
VS_OBJECTS = 0x800B9380          # 64 x 0x28 bytes
VS_PACKETS = 0x800B9D80
VS_COL_EDGES, VS_ROW_EDGES = 0x800228C6, 0x800228D8
VS_BAR_MODES = 0x800228F4
VS_FRAME_RECTS = 0x8002292C


def vs_background(ram: Ram) -> None:
    """FUN_80051C9C: the 7 x 6 grid of makuma*.tia cells (a black tile while sliding)."""
    ot, p = ot0(ram), _pkt(ram)
    if ram.s32(VS_SLIDE) != 0:
        _set_pkt(ram, tile(ram, ot, p, 0x60000000, 0, 0x1E00170))
        return
    cell = 0
    v_last = 0xFFFFFFFF
    y_top = 0x140000
    for row in range(7):
        va = (v_last + 1 & 0xFF) << 8
        v_last += 0x20
        vb = (v_last & 0xFF) << 8
        y_bot = ram.u32(VS_ROW_EDGES + 4 * row)
        x_left, u_left, u_last = 0, 0, 0xFFFFFFFF
        for col in range(6):
            hi, lo = cell & 0x30, cell & 0xF
            cell += 1
            x_right = ram.u16(VS_COL_EDGES + 2 * col)
            u_right = u_last + 0x20 & 0xFF
            p = poly_ft4(ram, ot, p, 0x2D000000, x_left | y_top, x_right | y_top, x_left | y_bot, x_right | y_bot,
                         u_left & 0xFF | va | (hi << 2 | 32000 | lo) << 16, u_right | va | 0xD0000,
                         u_left & 0xFF | vb | (u_right | vb) << 16)
            u_left = u_last + 0x21
            x_left = x_right
            u_last += 0x20
        y_top = y_bot
    _set_pkt(ram, p)


def vs_caption_bar(ram: Ram, obj: int) -> None:
    """FUN_80051E74: the mode-coloured bar with a gradient tail (drawn at rest)."""
    if ram.s32(VS_SLIDE) != 0:
        return
    ot, p = ot0(ram), _pkt(ram)
    x, y = ram.s16(obj + 4), ram.s16(obj + 6)
    col = ram.u32(obj + 0x14)
    ys = y << 16 & 0xFFFFFFFF
    w = ram.s16(obj + 8) - 0x6E
    p = tile(ram, ot, p, col | 0x60000000, ram.u32(obj + 4), w & 0xFFFF | 0x240000)
    x2 = x + w
    xa, xb = x2 & 0xFFFF, x2 + 0x6E & 0xFFFF
    y24 = (y + 0x24) << 16 & 0xFFFFFFFF
    for i in range(2):
        p = poly_g4(ram, ot, p, col | 0x3A000000, 0, col, 0, xa | ys, xb | ys, xa | y24, xb | y24)
        p = dr_mode(ram, ot, p, ram.u32(VS_BAR_MODES + 4 * i))
    _set_pkt(ram, p)


def vs_portrait_at(ram: Ram, obj: int, x: int, y: int) -> None:
    """FUN_800520A0: a 126 x 212 portrait from the face_b*.tiz picture, its frame and tint."""
    ot = ot0(ram)
    xl = x + 2
    yy = y + 6
    v = ram.u16(obj + 0xE) + 0x14 & 0xFF
    u = (ram.u16(obj + 0xC) & 0x3F) * 2
    if ram.s16(obj + 0x24) == 0:
        dx = 0x7E
    else:
        dx = -0x7E
        xl = x + 0x80
    xr = xl + dx & 0xFFFF
    rem, ty, lim = 0xD4, 0x14, 0x40
    hi = ram.u16(obj + 0x12)
    tp = ram.u16(obj + 0x10)
    p = _pkt(ram)
    while True:
        seg = rem
        if lim < ty + rem:
            seg = lim - ty
            lim += 0x40
        ya = yy << 16 & 0xFFFFFFFF
        yy += seg
        va = (v & 0xFF) << 8
        v += seg
        vb = (v & 0xFF) << 8
        p = poly_ft4(ram, ot, p, 0x2D000000, xl & 0xFFFF | ya, xr | ya, xl & 0xFFFF | yy << 16, xr | yy << 16,
                     u | va | tp << 16, u + 0x7D | va | hi << 16, u | vb | (u + 0x7D | vb) << 16)
        tp += 4
        rem -= seg
        ty += seg
        if rem == 0:
            break
    for i in range(4):
        e = VS_FRAME_RECTS + 8 * i
        p = tile(ram, ot, p, 0x60E8E8E8, ram.s16(e) + x & 0xFFFF | (ram.s16(e + 2) + y) << 16, ram.u32(e + 4))
    col = ram.u32(obj + 0x14)
    x0, x80 = x + 2 & 0xFFFF, x + 0x80 & 0xFFFF
    y6, y70, yda = (y + 6) << 16, (y + 0x70) << 16, (y + 0xDA) << 16
    p = poly_g4(ram, ot, p, 0x3A000000, 0, col, col, x0 | y6, x80 | y6, x0 | y70, x80 | y70)
    p = poly_g4(ram, ot, p, col | 0x3A000000, col, 0xC0C0C0, 0xC0C0C0, x0 | y70, x80 | y70, x0 | yda, x80 | yda)
    _set_pkt(ram, dr_mode(ram, ot, p, 0x20))


def _slid(ram: Ram, obj: int) -> tuple[int, int]:
    x, y = ram.s16(obj + 4), ram.s16(obj + 6)
    n = ram.s32(VS_SLIDE)
    if n:
        x += n * ram.s16(obj + 8) >> 3
        y += n * ram.s16(obj + 10) >> 3
    return x, y


def vs_text(ram: Ram, obj: int) -> None:
    """FUN_80052538: type 7 texts appear at rest, type 8 (names) also slide."""
    x, y = _slid(ram, obj)
    kind = ram.u16(obj)
    if kind == 8 or ram.s32(VS_SLIDE) == 0:
        text(ram, ram.u32(obj + 0x18), ram.s16(obj + 0x10), ram.s16(obj + 0x12), x, y, ram.u32(obj + 0x1C),
             ram.u32(obj + 0x20))


def vs_team_bars(ram: Ram) -> None:
    """FUN_800B3708 (arcade.ovl)."""
    if ram.s32(VS_SLIDE) != 0:
        return
    ot, p = ot0(ram), _pkt(ram)
    p = poly_g4(ram, ot, p, 0x3AE0E0E0, 0, 0x707070, 0, 0x60008E, 0x600170, 0xB8008E, 0xB80170)
    p = poly_g4(ram, ot, p, 0x3A000000, 0x707070, 0, 0xE0E0E0, 0x15E0000, 0x15E00E2, 0x1B60000, 0x1B600E2)
    _set_pkt(ram, dr_mode(ram, ot, p, 0x20))


def vs_draw(ram: Ram) -> None:
    """The drawing loop of FUN_80052808 over the 64 screen objects."""
    saved = _pkt(ram)
    _set_pkt(ram, VS_PACKETS + ram.u32(DISPLAY_BUFFER) * 0x3C00)
    for i in range(64):
        obj = VS_OBJECTS + 0x28 * i
        kind = ram.u16(obj)
        if kind == 1:
            vs_background(ram)
        elif kind == 2:
            vs_team_bars(ram)
        elif kind == 3:
            vs_caption_bar(ram, obj)
        elif kind == 4:
            vs_portrait_at(ram, obj, *_slid(ram, obj))
        elif kind == 5:
            x, y = _slid(ram, obj)
            _set_pkt(ram, portrait(ram, ot0(ram), _pkt(ram), x, y, ram.u32(obj + 0x1C), ram.u32(obj + 0x20)))
        elif kind == 6:
            if ram.s32(VS_SLIDE) == 0:
                _set_pkt(ram, tile(ram, ot0(ram), _pkt(ram), 0x60E0E0E0, ram.u32(obj + 4), ram.u32(obj + 8)))
        elif kind in (7, 8):
            vs_text(ram, obj)
    _set_pkt(ram, saved)


VS_PLAYER_POS = (0x800B4ED0, 0x800B4EE0)   # arcade.ovl: per side 4 x s16 (portrait, name)
VS_TEAM_POS = (0x800B4EF0, 0x800B4F00)
VS_TEAM_ICONS = 0x800B0B9C       # per side: u16 x, y, step, x when 8 members
VS_FMT_VS, VS_FMT_STAGE, VS_FMT_ROUND, VS_FMT_DEMO = 0x800B0BAC, 0x800B0BB8, 0x800B0BCC, 0x800B0BE0
VS_NAME_FMT = 0x8002294C
VS_BACKGROUNDS = 0x800228FC      # u16 per background kind
VS_CAPTION_COLOURS, VS_CAPTION_WIDTHS = 0x80022900, 0x8002291C
VS_PICTURE_SLOTS = 0x800984E8    # per side 4 x s16: VRAM x, y, CLUT, tpage of the big picture


def _vs_alloc(ram: Ram) -> int:
    """FUN_80051C64: the first free screen object (0 when all 64 are used)."""
    for i in range(64):
        obj = VS_OBJECTS + 0x28 * i
        if ram.u16(obj) == 0:
            return obj
    return 0


def _vs_pos(ram: Ram, obj: int, pos: int) -> None:
    for k in range(4):
        ram.put(obj + 4 + 2 * k, "H", ram.u16(pos + 2 * k))


def vs_add_portrait(ram: Ram, side: int, key: int, pos: int) -> None:
    """FUN_800523FC: a side's big picture (type 4), facing the other side."""
    obj = _vs_alloc(ram)
    if not obj:
        return
    ram.put(obj, "H", 4)
    k, c = key >> 2, key & 3
    if k > 0x15 or c > 3:
        k, c = 0x16, 0
    word = ram.u32(ram.u32(0x80097EDC + 4 * (k * 4 + c)))
    ram.put(obj + 0x14, "I", word >> 8)
    ram.put(obj + 0x24, "H", ((word & 0xFF) >> 5 ^ (side != 0)) & 1)
    ram.put(VS_TABLE + 2 + side, "B", word & 0x1F)
    for k2 in range(4):
        ram.put(obj + 0xC + 2 * k2, "H", ram.u16(VS_PICTURE_SLOTS + 8 * side + 2 * k2))
    _vs_pos(ram, obj, pos)


def vs_add_name(ram: Ram, key: int, pos: int) -> None:
    """FUN_80052650: a side's name (type 8, colour 8 font 3), kept on screen."""
    obj = _vs_alloc(ram)
    if not obj:
        return
    ram.put(obj, "H", 8)
    k = 0x58 if key > 0x5C else key
    name = ram.u32(ram.u32(CHAR_RECORDS + 4 * k))
    ram.put(obj + 0x1C, "I", name)
    _vs_pos(ram, obj, pos)
    ram.put(obj + 0x18, "I", VS_NAME_FMT)
    ram.put(obj + 0x10, "H", 8)
    ram.put(obj + 0x12, "H", 3)
    w = strlen(ram, name) * 0x15
    x = ram.s16(obj + 4)
    if x < 0:
        right, left = -x, -x - w
    else:
        right, left = x + w, x
    if left < 0xC:
        left = 0xC
    v = left
    if right > 0x164:
        v = v + 0x164 - right
    ram.put(obj + 4, "H", v & 0xFFFF)
    d = ram.s16(obj + 8)
    if d:
        v = _s16(v)
        ram.put(obj + 8, "H", (-(v + w) if d < 1 else 0x170 - v) & 0xFFFF)


def vs_add_text(ram: Ram, fmt: int, colour: int, font: int, x: int, y: int, arg: int) -> None:
    """FUN_800525DC: a text object (type 7)."""
    obj = _vs_alloc(ram)
    if not obj:
        return
    ram.put(obj + 0x18, "I", fmt)
    ram.put(obj + 0x10, "H", colour & 0xFFFF)
    ram.put(obj + 0x12, "H", font & 0xFFFF)
    ram.put(obj + 4, "H", x & 0xFFFF)
    ram.put(obj + 8, "H", 0)
    ram.put(obj + 0xA, "H", 0)
    ram.put(obj + 6, "H", y & 0xFFFF)
    ram.put(obj, "H", 7)
    ram.put(obj + 0x1C, "I", arg & 0xFFFFFFFF)


def vs_add_background(ram: Ram, background: int, caption: int) -> None:
    """FUN_80051FC4: the caption bar (type 3) and the tiled background (type 1)."""
    obj = _vs_alloc(ram)
    if not obj:
        return
    ram.put(obj, "H", 3)
    ram.put(obj + 6, "H", 0x24)
    ram.put(obj + 4, "H", 0)
    ram.put(obj + 0x14, "I", ram.u32(VS_CAPTION_COLOURS + 4 * caption))
    ram.put(obj + 8, "H", ram.u16(VS_CAPTION_WIDTHS + 2 * caption))
    obj = _vs_alloc(ram)
    if obj:
        ram.put(obj, "H", 1)
        ram.put(VS_TABLE, "H", ram.u16(VS_BACKGROUNDS + 2 * background))


def vs_team_icons(ram: Ram, side: int, team: int) -> None:
    """arcade.ovl FUN_800B3928: a team's member portraits (type 5; beaten ones dimmed) and their frame."""
    n = min(ram.u8(team + 0xC), 8)
    e = VS_TEAM_ICONS + 8 * side
    x, y, step = ram.u16(e), ram.u16(e + 2), ram.u16(e + 4)
    if n == 8:
        x = ram.u16(e + 6)
    w = step << 3 & 0xFFFF
    fx, fy = x - 1 & 0xFFFF, y - 2 & 0xFFFF
    fw = (n - 1) * 0x21 + 1 & 0xFFFF
    if side:
        fx = fx + (n - 2) * step & 0xFFFF
    cur = ram.u8(team + 9)
    last = ram.u8(team + 10)
    if not cur < last:
        last = cur + 1

    def icon(i: int) -> None:
        nonlocal x
        key = ram.u8(team + i)
        flags = 8
        if key >= 0x58:
            key = 0x58
        if i >= last:
            key = 0x58
        elif i < cur:
            flags = 0x68
        elif i == cur:
            return
        obj = _vs_alloc(ram)
        if obj:
            ram.put(obj, "H", 5)
            ram.put(obj + 0x1C, "I", key)
            ram.put(obj + 0x20, "I", flags)
            ram.put(obj + 4, "H", x)
            ram.put(obj + 6, "H", y)
            ram.put(obj + 8, "H", w)
            ram.put(obj + 0xA, "H", 0)
        x = x + step & 0xFFFF

    for i in range(cur, n):
        icon(i)
    for i in range(ram.u8(team + 9)):
        icon(i)
    if n >= 2:
        obj = _vs_alloc(ram)
        if obj:
            ram.put(obj, "H", 6)
            for k, v in enumerate((fx, fy, fw, 0x3E)):
                ram.put(obj + 4 + 2 * k, "H", v)


def force_vs_setup(ram: Ram, keys: list[int]) -> None:
    """force.ovl FUN_800B6648: the player's portrait and name, TEKKEN FORCE, STAGE n / FINAL STAGE,
    and the level's two enemy names sliding in on the right."""
    stage = ram.s32(MODE + 0x24)
    side = int(ram.u8(MODE + 0x3E) != 0)
    vs_add_portrait(ram, side, keys[side], 0x800B6A24)
    ram.put(0x800984E6 + (side ^ 1), "B", 0x26)          # FUN_80052794: the other side has no picture
    ram.put(VS_TABLE + 2 + (side ^ 1), "B", 0x26)
    vs_add_name(ram, keys[side + 2], 0x800B6A2C)
    vs_add_text(ram, 0x800B0FA0, 6, 1, 0x1C, 0x2A, 0)
    if stage < 4:
        vs_add_text(ram, 0x800B0FB8, 6, 1, 0x20, 0x54, stage + 1)
    else:
        vs_add_text(ram, 0x800B0FCC, 6, 1, 0x20, 0x54, 0)
    x, y, dx, dy = (ram.u16(0x800B6A34 + 2 * k) for k in range(4))
    for i in range(2):
        obj = _vs_alloc(ram)
        if not obj:
            break
        ram.put(obj, "H", 8)
        ram.put(obj + 0x18, "I", 0x800B0F94)
        ram.put(obj + 0x12, "H", 3)
        ram.put(obj + 0x10, "H", ram.u8(0x800B6A64 + stage & 0xFFFFFFFF))
        for k, v in enumerate((x, y, dx, dy)):
            ram.put(obj + 4 + 2 * k, "H", v)
        name = ram.u32(0x800B6A3C + 8 * stage + 4 * i & 0xFFFFFFFF)
        ram.put(obj + 0x1C, "I", name)
        ram.put(obj + 4, "H", x - strlen(ram, name) * 0x15 & 0xFFFF)
        y = y + 0x2E & 0xFFFF
    vs_add_background(ram, 0, 6)


class VsModeSetups:
    """FUN_80052808 sub-state 1's per-mode object set-up (mode overlay functions): arcade.ovl
    0x800B3C70 (arcade, time attack), 0x800B3D70 (VS), 0x800B3E64 (team), 0x800B3F98 (survival),
    0x800B408C (demonstration); practice.ovl 0x800B713C; volley.ovl 0x800B55B4; force.ovl 0x800B6648."""

    def setup(self, ram: Ram, keys: list[int]) -> None:
        mode = ram.u32(MODE)
        if mode == 8:
            force_vs_setup(ram, keys)
            return
        if mode in (5, 7):                              # practice.ovl FUN_800B713C, volley.ovl FUN_800B55B4
            if mode == 5:
                pos, fmt_vs, fmt_caption, bg, caption = (0x800B9134, 0x800B9144), 0x800B0EB8, 0x800B0EC4, 0, 4
            else:
                pos, fmt_vs, fmt_caption, bg, caption = (0x800B6908, 0x800B6918), 0x800B0AA4, 0x800B0AB0, keys[4], 5
            for side in range(2):
                vs_add_portrait(ram, side, keys[side], pos[0] + 8 * side)
                vs_add_name(ram, keys[side + 2], pos[1] + 8 * side)
            vs_add_text(ram, fmt_vs, 0, 2, 0xA2, 0xFA, 0)
            vs_add_text(ram, fmt_caption, 6, 1, 0x1C, 0x2A, 0)
            vs_add_background(ram, bg, caption)
            return
        pos = VS_TEAM_POS if mode == 2 else VS_PLAYER_POS
        for side in range(2):
            if mode == 2:
                vs_team_icons(ram, side, MODE + 0x59 + 0xD * side)
            vs_add_portrait(ram, side, keys[side], pos[0] + 8 * side)
            vs_add_name(ram, keys[side + 2], pos[1] + 8 * side)
        vs_add_text(ram, VS_FMT_VS, 0, 2, 0xA2, 0xFA, 0)
        if mode == 6:
            vs_add_text(ram, VS_FMT_DEMO, 6, 1, 0x1C, 0x2A, 0)
            vs_add_background(ram, 1, 1)
        elif mode == 1:
            vs_add_text(ram, VS_FMT_ROUND, 6, 1, 0x1C, 0x2A, ram.u32(MODE + 0x28) + 1)
            vs_add_background(ram, 1, 1)
        elif mode == 2:
            vs_add_text(ram, VS_FMT_ROUND, 6, 1, 0x1C, 0x2A, ram.u8(MODE + 0x58) + 1)
            obj = _vs_alloc(ram)
            if obj:
                ram.put(obj, "H", 2)
            vs_add_background(ram, keys[4], 2)
        elif mode == 4:
            vs_add_text(ram, VS_FMT_ROUND, 6, 1, 0x1C, 0x2A, ram.u32(MODE + 0x44) + 1)
            vs_add_background(ram, 0, 3)
        else:
            vs_add_text(ram, VS_FMT_STAGE, 6, 1, 0x1C, 0x2A, ram.u32(MODE + 0x24) + 1)
            vs_add_background(ram, keys[4], keys[4])


VS_SETUPS = VsModeSetups()


def vs_setup(ram: Ram) -> None:
    """FUN_80052808 sub-state 1: the screen objects of the pre-fight VS screen (picture uploads not ported)."""
    for i in range(64):
        ram.put(VS_OBJECTS + 0x28 * i, "H", 0)
    k0 = ram.u16(0x800AE224) << 2 | ram.u16(0x800AE260)
    k1 = ram.u16(0x800AE226) << 2 | ram.u16(0x800AE262)
    VS_SETUPS.setup(ram, [k0, k1, k0, k1, int(ram.u8(0x800AFF6C) != 1)])
    hold = ram.u32(0x8009584C) + 1 & 0xFFFFFFFF          # FUN_8002988C(1) ... (0) around the uploads
    ram.put(0x8009584C, "I", hold)
    if ram.s16(0x800984E4) != ram.s16(VS_TABLE):
        ram.put(0x800984E4, "H", ram.u16(VS_TABLE))            # (loads the background's pictures)
    for side in range(2):
        b = ram.u8(VS_TABLE + 2 + side)
        if ram.u8(0x800984E6 + side) != b:
            ram.put(0x800984E6 + side, "B", b)                # (loads this side's big picture)
    if hold:
        ram.put(0x8009584C, "I", hold - 1)
    ram.put(VS_SLIDE, "I", 8)
    ram.put(0x800AE6EC, "H", 2)


def vs_frame(ram: Ram) -> None:
    """FUN_80052808 (game state 11): display on, the objects, the slide-in, the resting frame, the hand-over."""
    sub = ram.u16(0x800AE6EC)
    draw = False
    if sub == 0:
        ram.put(0x80095850, "I", 1)                        # FUN_80029860(0)
        ram.put(0x800AE6EC, "H", 1)
    elif sub == 1:
        vs_setup(ram)
    elif sub == 2:
        draw = True
        n = ram.s32(VS_SLIDE) - 1
        ram.put(VS_SLIDE, "i", n)
        if n < 1:
            ram.put(0x800AE6EC, "H", 3)
    elif sub == 3:
        draw = True
        ram.put(0x800AE6EC, "H", 4)
    elif sub == 4:
        ram.put(0x800AE6CC, "H", ram.u8(0x800AFF64))
        ram.put(0x800AE6EC, "H", ram.u8(0x800AFF65))
    if draw:
        vs_draw(ram)


# ---- Tekken Ball HUD (volley.ovl) ----
BALL_GAUGES = 0x800B68E8         # 2 x 0x10: u32 last power, s16 target, fill, trail, u16 direction (1 = grows right), x, y
BALL_POPUPS = 0x800B6C58         # head of the popup text list (8 slots of 0x20 at 0x800B6B58)
PAUSED = 0x800958B0


def ball_gauges(ram: Ram, p1: int, maximum: int, p2: int, highlight: int) -> None:
    """volley.ovl FUN_800B4E6C: the two 76-pixel power gauges. The fill moves 3 pixels per frame
    towards `power · 76 / maximum`; a lighter trail follows a drop by 1/16 per frame. The gauge in
    `highlight` (1 << player) pulses while the game is not paused."""
    ot = ot0(ram)
    p = _pkt(ram)
    for g in range(2):
        r = BALL_GAUGES + 0x10 * g
        ch = 0x3E if g == 0 else 0x3D
        power = (p1 if g == 0 else p2) & 0xFFFFFFFF
        target, fill, trail = ram.s16(r + 4), ram.s16(r + 6), ram.s16(r + 8)
        if ram.u32(r) != power:
            ram.put(r, "I", power)
            target = _sdiv(_s32(_s32(power) * 76), maximum)
        target = min(target, 0x4C)
        trail = trail - (trail - fill + 15 >> 4) if fill < trail else fill
        if fill < target:
            fill = min(fill + 3, target)
        else:
            fill = target
        if trail < fill:
            trail = fill
        for off, v in ((4, target), (6, fill), (8, trail)):
            ram.put(r + off, "H", v & 0xFFFF)
        segments = (fill, trail - fill, 0x4C - trail)
        if highlight == 1 << g and ram.u32(PAUSED) == 0:
            colour = scale_colour(0xFFFFFF, triangle_wave(ram.u32(FRAME_COUNT) << 4))
        else:
            colour = 0x808080
        x, y = ram.u16(r + 0xC), ram.u16(r + 0xE)
        top, bottom = y << 16, (y + 0x18 << 16) & 0xFFFFFFFF
        p = sprt(ram, ot, p, colour | 0x64000000, x | top, 0x180006, 0x7EDEA8E0)
        p = sprt(ram, ot, p, colour | 0x64000000, x + 0x4A & 0xFFFF | top, 0x180006, 0x7EDEA8EA)
        right = ram.u16(r + 0xA) == 1
        sx = x + 2 if right else x + 0x4E
        for k, n in enumerate(segments):
            if n == 0:
                continue
            if right:
                a, sx = sx, sx + n
            else:
                a = sx = sx - n
            clut = ((ch >> 4 | 0x1F8) << 6 | ch & 0xF | 0x10) if k == 0 else 0x7EDC if k == 1 else 0x7EDF
            p = poly_ft4(ram, ot, p, colour | 0x2C000000, a & 0xFFFF | top, a + n & 0xFFFF | top,
                         a & 0xFFFF | bottom, a + n & 0xFFFF | bottom, clut << 16 | 0xA8E8, 0xDA8E9, 0xC0E9C0E8)
    _set_pkt(ram, p)


def _popup_remove(ram: Ram, node: int) -> None:
    """volley.ovl FUN_800B4638."""
    ram.put(node + 0x1F, "B", 0)
    nxt, prev = ram.u32(node), ram.u32(node + 4)
    if prev == 0:
        ram.put(BALL_POPUPS, "I", nxt)
        if nxt:
            ram.put(nxt + 4, "I", 0)
    else:
        ram.put(prev, "I", nxt)
        if nxt:
            ram.put(nxt + 4, "I", prev)


def ball_popups(ram: Ram, frozen: int) -> None:
    """volley.ovl FUN_800B4350: the popup texts (`!` and damage numbers, placed over the ball by
    FUN_800B445C). Each rises one pixel per frame and is removed when its frames run out; while
    the fight is frozen they are only drawn."""
    node = ram.u32(BALL_POPUPS)
    while node:
        if not frozen and ram.u8(node + 0x1E) == 0:
            _popup_remove(ram, node)
        else:
            text(ram, node + 8, 0, ram.u8(node + 0x1C), ram.u8(node + 0x1D), ram.s16(node + 0x18), ram.s16(node + 0x1A))
            if not frozen:
                ram.put(node + 0x1A, "H", ram.u16(node + 0x1A) - 1 & 0xFFFF)
                ram.put(node + 0x1E, "B", ram.u8(node + 0x1E) - 1)
        node = ram.u32(node)


POPUP_SLOTS, POPUP_NEXT = 0x800B6B58, 0x800B6B50
POPUP_PREFIX = 0x800B0A8C        # "%p%c%f%H%V"


def ball_popup_add(ram: Ram, gte, s: int, pos: int, colour: int, font: int, frames: int) -> None:
    """volley.ovl FUN_800B445C: a popup text over the world point at `pos` (three s32) in the next
    of eight slots (skipped while that slot is still showing), centred for its font (0, 1, 2:
    5, 7, 12 pixels per character, 8, 12, 20 pixels up) and put at the head of the list."""
    import projection_sim as pj
    i = ram.s32(POPUP_NEXT) + 1
    i = i - (ds_floor8(i))
    ram.put(POPUP_NEXT, "i", i)
    node = POPUP_SLOTS + 0x20 * i & 0xFFFFFFFF
    if ram.u8(node + 0x1F):
        return
    end = strcpy(ram, node + 8, POPUP_PREFIX)
    n = 0
    while True:
        c = ram.u8(s + n)
        ram.put(end + n, "B", c)
        if c == 0:
            break
        n += 1
    pj.local_screen(ram, gte, tuple(ram.s32(pos + 4 * k) for k in range(3)), node + 0x18)
    shift = {0: (5, 8), 1: (7, 12), 2: (12, 20)}.get(font & 0xFF)
    if shift:
        ram.put(node + 0x18, "H", ram.u16(node + 0x18) - shift[0] * n & 0xFFFF)
        ram.put(node + 0x1A, "H", ram.u16(node + 0x1A) - shift[1] & 0xFFFF)
    ram.put(node + 0x1D, "B", font & 0xFF)
    ram.put(node + 0x1C, "B", colour & 0xFF)
    ram.put(node + 0x1E, "B", frames & 0xFF)
    ram.put(node + 0x1F, "B", 1)
    head = ram.u32(BALL_POPUPS)
    ram.put(node + 4, "I", 0)
    ram.put(node, "I", head)
    if head:
        ram.put(head + 4, "I", node)
    ram.put(BALL_POPUPS, "I", node)


def ds_floor8(i: int) -> int:
    """(i / 8) * 8 with the game's rounding towards zero."""
    return (i + 7 if i < 0 else i) >> 3 << 3
