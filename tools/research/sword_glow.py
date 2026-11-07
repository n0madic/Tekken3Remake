#!/usr/bin/env python3
"""Integer port of the glow along Yoshimitsu's sword (Japan Rev.1): the primitive set-up
`FUN_8003161C` (run when the fighter's parts are set up) and the per-frame ribbon `FUN_80031980`
(called by `FUN_8003B74C` after the fighter's parts are drawn).

The fighter record's character (+0x18) is Yoshimitsu (4) or Mokujin (15) with Yoshimitsu's moves
(bank type +0x16 = 4, checked each frame). Each player owns two buffers of ten Gouraud-textured
quads (POLY_GT4, semi-transparent, additive: tpage 0x28 = 4-bit, mode B + F, page x 512), one
per display buffer, so the ribbon is drawn from the buffer of the frame that is being built. Every
vertex has the texture coordinate (0, 0) and the CLUT at (272, 511), whose 16 colours are all
white in the system textures (the 8-bit row at (256, 511) holds 0x0000 and then 255 × 0xFFFF): the
ribbon is the vertex colours, added to the picture. Each quad's vertices 0 and 1 are on the
ribbon's centre line, 2 and 3 on its edges; the edge vertices and the first and last points of the
centre line are black, so the glow fades towards the sides and the ends. The colour belongs to
the costume slot (+0x1C): slot 8 green, slot 9 red, the others (Mokujin) orange, and the second
display buffer's is dimmer, which makes the ribbon pulse from frame to frame.

The routine projects four points of joint block 10 (+0xB9C; the table at 0x80095BA0, in the
sword joint's own axes) with the fighter's view (0x800AE2E8) and builds the ribbon in the screen's
plane: P1 to P4 are the projected points, P0 and P5 the line's ends, one width beyond them along
the first and last segment. The half-width is 2,000 / (SZ >> 5) of the first point (200 when that
is 9 or less), in the GTE's screen units, the rows of which are the 480-line display's. The edge
points of P0 and P5 are narrower by a quarter, P5 reaches a quarter of the width further and the
quads are filed in the ordering table at SZ >> 5 − 8 of their first point (or, for the last of
each half, the fourth).

The ports take a `fight_sim.Ram` and a `psxcpu.GTE`. Verified by `tools/research/verify_sword_glow.py`.
"""

from __future__ import annotations

from fight_sim import Ram
from projection_sim import M32, RTPS, apply_rot_matrix_lv, set_mul_rot_matrix, set_rotation, set_translation
from psxcpu import GTE, s32

PLAYER, BANK_TYPE, CHAR_ID, COSTUME_SLOT = 0x12, 0x16, 0x18, 0x1C   # s16 fields of a fighter record
SWORD_BLOCK = 0xB9C              # the joint block of joint 10 (+0x8F4 + 10 · 0x44): rotation, translation at +0x14
VIEW = 0x800AE2E8                # the fighters' view MATRIX (FUN_80036254)
BLADE_POINTS = 0x80095BA0        # 4 SVECTORs, in the sword joint's axes
QUAD_TABLE = 0x80019F24          # per quad: 4 point numbers and the depth point (50 bytes)
DISPLAY_BUFFER = 0x800AE3C4      # the frame's display buffer, 0 or 1
GS_OT = 0x800A911C               # the current GsOT; its table pointer is at +4
PRIM_BUFFERS = 0x8009C030        # per player (8 bytes): the two buffers' addresses
ALLOCATION = 0x8009C0A0          # per player (8 bytes): where the fight's buffer allocator stands
SIN_TABLE = 0x8001E8C4           # 4,096 s16 sines; the cosines start 1,024 entries later
RATAN_TABLE = 0x8009922C         # libgte ratan2's octant table (1,025 s16)

YOSHIMITSU, MOKUJIN = 4, 15
BANK_YOSHIMITSU = 4
QUADS = 10
PRIM_BYTES = 0x34
RTPT = 0x280030                  # sf = 1
TPAGE = 0x28                     # GetTPage(0, 1, 0x200, 0)
CLUT = 0x7FD1                    # (272, 511)
POLY_GT4 = 0x3C | 2              # code of a semi-transparent POLY_GT4
GT4_WORDS = 12
DEPTH_BIAS = 8                   # entries in front of the point's own
WIDTH = 2000                     # the half width is WIDTH / depth of the first point, in screen units
NEAR_WIDTH = 200                 # ... when that depth is NEAR_DEPTH or less
NEAR_DEPTH = 9
# The colour of display buffer 0 and 1 by costume slot: Yoshimitsu's two costumes, then the others.
COLOURS = {
    8: ((0x18, 0x30, 0x18), (0x0C, 0x1E, 0x0C)),
    9: ((0x48, 0x1E, 0x1E), (0x30, 0x18, 0x18)),
}
OTHER_COLOURS = ((0x3C, 0x1E, 0x0C), (0x1E, 0x12, 0x0C))
# Per quad which of vertices 0 and 1 carry the colour (bit 0, bit 1): the ends of each half fade.
FADE = (2, 3, 3, 3, 2, 2, 3, 3, 3, 2)


def has_glow(ram: Ram, f: int) -> bool:
    """FUN_80031980's test: Yoshimitsu, or Mokujin fighting with Yoshimitsu's moves."""
    char = ram.s16(f + CHAR_ID)
    return char == YOSHIMITSU or (char == MOKUJIN and ram.s16(f + BANK_TYPE) == BANK_YOSHIMITSU)


def colours_of(slot: int) -> tuple[tuple[int, int, int], tuple[int, int, int]]:
    return COLOURS.get(slot, OTHER_COLOURS)


def init_prims(ram: Ram, f: int) -> None:
    """FUN_8003161C: the two buffers' ten quads (their positions are written by each frame)."""
    char = ram.s16(f + CHAR_ID)
    if char not in (YOSHIMITSU, MOKUJIN):
        return
    player = ram.s16(f + PLAYER)
    slot = ram.s16(f + COSTUME_SLOT)
    for k in range(2):
        ram.put(PRIM_BUFFERS + 8 * player + 4 * k, "I", ram.u32(ALLOCATION + 8 * player + 4 * k))
    ends = []
    for k in range(2):
        colour = colours_of(slot)[k]
        p = ram.u32(PRIM_BUFFERS + 8 * player + 4 * k)
        for q in range(QUADS):
            ram.put(p, "I", ram.u32(p) & 0xFFFFFF | GT4_WORDS << 24)
            ram.put(p + 7, "B", POLY_GT4)
            lit = FADE[q]
            for v in range(4):
                shown = (lit >> v) & 1 if v < 2 else 0
                for c, byte in enumerate(colour if shown else (0, 0, 0)):
                    ram.put(p + (4, 16, 28, 40)[v] + c, "B", byte)
                ram.put(p + (12, 24, 36, 48)[v], "B", 0)         # u
                ram.put(p + (13, 25, 37, 49)[v], "B", 0)         # v
            ram.put(p + 14, "H", CLUT)
            ram.put(p + 26, "H", TPAGE)
            p += PRIM_BYTES
        ends.append(p)
    for k in range(2):
        ram.put(ALLOCATION + 8 * player + 4 * k, "I", ends[k])


def ratan2(ram: Ram, y: int, x: int, table: int = RATAN_TABLE) -> int:
    """libgte ratan2(y, x): the angle of (x, y) in 4,096 units from the octant table."""
    x, y = s32(x), s32(y)
    negative_x, negative_y = x < 0, y < 0
    x, y = abs(x), abs(y)
    if x == 0 and y == 0:
        return 0
    if y < x:
        t = s32(y << 10) // x if y & 0x7FE00000 == 0 else y // (x >> 10)
        v = ram.s16(table + 2 * t)
    else:
        t = s32(x << 10) // y if x & 0x7FE00000 == 0 else x // (y >> 10)
        v = 0x400 - ram.s16(table + 2 * t)
    if negative_x:
        v = 0x800 - v
    if negative_y:
        v = -v
    return v


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def toward_zero(v: int) -> int:
    """(v < 0 ? v + 0xFFF : v) >> 12: the compiler's division by 4,096 (towards zero)."""
    return (v + 0xFFF if v < 0 else v) >> 12


def project(ram: Ram, gte: GTE, block: int, view: int = VIEW, blade: int = BLADE_POINTS) -> tuple[list[tuple[int, int]], list[int]]:
    """FUN_80037AB0 on the view MATRIX at `view` and the sword's joint block at `block`, then
    FUN_80036D4C on the four blade points at `blade`: their screen positions and SZ >> 5."""
    set_rotation(gte, ram, view)
    r = apply_rot_matrix_lv(gte, tuple(ram.s32(block + 0x14 + 4 * i) for i in range(3)))
    set_translation(gte, tuple(s32(r[i] + ram.s32(view + 0x14 + 4 * i)) for i in range(3)))
    set_mul_rot_matrix(ram, gte, block)

    def load(slot: int, point: int) -> None:
        a = blade + 8 * point
        gte.write_data(2 * slot, ram.u32(a))
        gte.write_data(2 * slot + 1, ram.u32(a + 4))

    def sxy(register: int) -> tuple[int, int]:
        w = gte.read_data(register)
        return s16(w), s16(w >> 16)

    for i in range(3):
        load(i, i)
    gte.command(RTPT)
    xy = [sxy(12), sxy(13), sxy(14)]
    depth = [gte.read_data(17) >> 5, gte.read_data(18) >> 5, gte.read_data(19) >> 5]
    load(0, 3)
    gte.command(RTPS)
    xy.append(sxy(14))
    depth.append(gte.read_data(19) >> 5)
    return xy, [s16(d) for d in depth]


def offsets(ram: Ram, xy: list[tuple[int, int]], width: int, ratan_table: int = RATAN_TABLE,
            sin_table: int = SIN_TABLE) -> tuple[int, int, int, int]:
    """The half width `width` as (dy, dx) at right angles to the first segment of the projected
    points (P1 to P2) and to the last (P3 to P4): the angle of each from ratan2, then the cosine
    and the sine times the width in 4.12, towards zero. FUN_80031980 and the arcade's FUN_80192ecc
    both build their edges from these."""
    out = []
    for a, b in ((0, 1), (2, 3)):
        angle = ratan2(ram, xy[b][0] - xy[a][0], xy[b][1] - xy[a][1], ratan_table) & 0xFFF
        sin = ram.s16(sin_table + 2 * angle)
        cos = ram.s16(sin_table + 0x800 + 2 * angle)
        out += [toward_zero(cos * width), toward_zero(sin * width)]
    return out[0], out[1], out[2], out[3]


def ribbon(ram: Ram, xy: list[tuple[int, int]], depth: list[int]) -> list[tuple[int, int]]:
    """The 18 points of FUN_80031980: six centre points (P0 to P5), then the six on one edge and
    the six on the other, from the four projected points."""
    width = WIDTH // depth[0] if depth[0] > NEAR_DEPTH else NEAR_WIDTH
    dy_a, dx_a, dy_b, dx_b = offsets(ram, xy, width)
    p = [(0, 0)] * 6
    p[1], p[2], p[3], p[4] = xy
    p[0] = (s16(xy[0][0] - dx_a), s16(xy[0][1] - dy_a))
    p[5] = (s16(xy[3][0] + dx_b), s16(xy[3][1] + dy_b))
    one: list[tuple[int, int]] = []
    other: list[tuple[int, int]] = []
    dy, dx = dy_a, dx_a
    for k in range(6):
        if k == 3:
            dy, dx = dy_b, dx_b
        ax, ay = s16(p[k][0] + dy), s16(p[k][1] - dx)
        bx, by = s16(p[k][0] - dy), s16(p[k][1] + dx)
        quarter_y, quarter_x = dx >> 2, dy >> 2
        if k in (0, 5):
            ax, ay = s16(ax - quarter_x), s16(ay + quarter_y)
            bx, by = s16(bx + quarter_x), s16(by - quarter_y)
        one.append((ax, ay))
        other.append((bx, by))
    p[5] = (s16(p[5][0] + quarter_y), s16(p[5][1] + quarter_x))
    return p + one + other


def draw(ram: Ram, gte: GTE, f: int) -> None:
    """FUN_80031980: places the ten quads of this frame's buffer and files them in the table."""
    if not has_glow(ram, f):
        return
    xy, depth = project(ram, gte, f + SWORD_BLOCK)
    points = ribbon(ram, xy, depth)
    player = ram.s16(f + PLAYER)
    prim = ram.u32(PRIM_BUFFERS + 4 * ram.u32(DISPLAY_BUFFER) + 8 * player)
    table = ram.u32(ram.u32(GS_OT) + 4)
    for q in range(QUADS):
        entry = QUAD_TABLE + 5 * q
        for v in range(4):
            x, y = points[ram.u8(entry + v)]
            ram.put(prim + (8, 20, 32, 44)[v], "h", x)
            ram.put(prim + (10, 22, 34, 46)[v], "h", y)
        slot = (depth[ram.u8(entry + 4)] - DEPTH_BIAS) & 0x3FF
        head = table + 4 * slot
        ram.put(prim, "I", ram.u32(head) & 0xFFFFFF | GT4_WORDS << 24)
        ram.put(head, "I", ram.u32(head) & 0xFF000000 | prim & 0xFFFFFF)
        prim += PRIM_BYTES
