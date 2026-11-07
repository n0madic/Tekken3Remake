#!/usr/bin/env python3
"""Integer port of the arcade's glow along Yoshimitsu's sword (MAME `tekken3`, World ver. E1):
`FUN_80192ecc`, called for every fighter each frame after its parts are drawn.

It is the PlayStation's ribbon (sword_glow.py) built the same way from the four blade points of the
sword hand's joint (row 10, world MATRIX at fighter + 0xA68: the blade table at 0x801FCD00 is the
PlayStation's) with the same ten quads (0x8015F0C4), but differs in what it draws:

- the half width is 2,000 / (SZ >> 5) of the first point, 2,000 when that is 0, and the ribbon's
  ends are as wide as the rest: no narrower sides, no further reach of the last point;
- the quads are POLY_FT4, textured and semi-transparent (additive: tpage (0x3C0, 0x100) 4-bit,
  mode B + F; the second player's texture is the same 128 rows lower), flat coloured; the table
  gives each corner's texel (u, v) of a 16 × 16 picture, a grey ramp from black at the edge to white
  on the centre line, darkening towards the ends. The picture and its CLUT (768, 375 or 503) are part
  of Yoshimitsu's costume textures (slots 8 and 9, the Mokujin's too);
- the colour is chosen by the costume slot (+0x1E: 8 green, 9 red, others orange) and by the
  parity of the frame counter DAT_8021FD58, whose odd frames are the brighter, so the ribbon pulses;
- it draws for the costume slots 8 and 9 and for the character word (+0x18, the PlayStation's
  bank type + character << 16) 0xF0004, Mokujin with Yoshimitsu's moves;
- the quads are rebuilt every frame (no set-up), in the ten primitives of the player's buffer
  at 0x8021FE60 + 800 · player + 400 · display buffer, filed in the ordering table at
  (SZ >> 5 of the quad's blade point − 8) & 0x3FF like the PlayStation's.

The ports take an `ArcadeRam` and a `psxcpu.GTE`. Verified by `tools/research/verify_arcade_sword_glow.py`.
"""

from __future__ import annotations

import sword_glow as sg
from arcade_cpu import ARCADE_RAM, SINE as SIN_TABLE   # 4,096 s16 sines; the cosines start 1,024 entries later
from fight_sim import Ram
from psxcpu import GTE

PLAYER, SLOT, CHARACTER = 0x14, 0x1E, 0x18   # fighter record: s16 player, u16 costume slot, s32 bank | character << 16
SWORD_BLOCK = 0xA68              # row 10's world MATRIX (+0x724 + 10 · 0x50 + 0x24)
VIEW = 0x8036EBFC                # the fighters' view MATRIX
BLADE_POINTS = 0x801FCD00        # 4 SVECTORs, in the sword joint's axes (the PlayStation's)
QUAD_TABLE = 0x8015F0C4          # per quad (13 bytes): 4 point numbers, 4 × (u, v), the depth point
QUAD_BYTES = 13
RATAN_TABLE = 0x80216088         # libgte ratan2's octant table (1,025 s16)
DISPLAY_BUFFER = 0x8021FC80      # GsGetActiveBuff(): 0 or 1
PARITY = 0x8021FD58              # the frame counter whose low bit picks the brightness
GS_OT = 0x8021FB34               # the current GsOT; its table pointer is at +4
PRIMITIVES = 0x8021FE60          # per player 800 bytes, per display buffer 400
POLY_FT4 = 0x2C | 2              # code of a semi-transparent POLY_FT4
FT4_WORDS = 9
PRIM_BYTES = 0x28
QUADS = 10
CHARACTER_MOKUJIN = 0xF0004
SLOTS = (8, 9)
WIDTH = 2000
TEXTURE_PAGE = (0x3C0, 0x100, 0x180)       # x, then y of players 0 and 1
CLUT = ((0x300, 0x177), (0x300, 0x1F7))
SECOND_PLAYER_V = 0x80
# The colour by costume slot for the even and odd frames; slots 8 and 9, then the others.
COLOURS = {
    8: ((0x10, 0x28, 0), (0x20, 0x40, 0)),
    9: ((0x40, 0x20, 0), (0x60, 0x28, 0)),
}
OTHER_COLOURS = ((0x28, 0x18, 0), (0x50, 0x28, 0))


class ArcadeRam(Ram):
    """Little-endian guest memory of the System 12's 4 MB."""

    def _off(self, addr: int) -> int:
        off = addr & 0x1FFFFFFF
        if off >= ARCADE_RAM:
            raise ValueError(f"address {addr:#x} outside RAM")
        return off


def has_glow(ram: Ram, f: int) -> bool:
    """FUN_80192ecc's test: costume slot 8 or 9, or Mokujin with Yoshimitsu's moves."""
    return ram.u16(f + SLOT) in SLOTS or ram.s32(f + CHARACTER) == CHARACTER_MOKUJIN


def colour_of(slot: int, parity: int) -> tuple[int, int, int]:
    return COLOURS.get(slot, OTHER_COLOURS)[parity & 1]


def get_tpage(x: int, y: int) -> int:
    """GetTPage(0, 1, x, y): 4-bit texels, mode B + F."""
    return (1 << 5) | (x >> 6) & 0xF | (y >> 4) & 0x10


def get_clut(x: int, y: int) -> int:
    return y << 6 | x >> 4


def ribbon(ram: Ram, xy: list[tuple[int, int]], depth: list[int]) -> list[tuple[int, int]]:
    """The 18 points of FUN_80192ecc: six centre points (P0 to P5), then the six on one edge and
    the six on the other, from the four projected points."""
    width = WIDTH if depth[0] == 0 else WIDTH // depth[0]
    dy_a, dx_a, dy_b, dx_b = sg.offsets(ram, xy, width, RATAN_TABLE, SIN_TABLE)
    p = [(0, 0)] * 6
    p[1], p[2], p[3], p[4] = xy
    p[0] = (sg.s16(xy[0][0] - dx_a), sg.s16(xy[0][1] - dy_a))
    p[5] = (sg.s16(xy[3][0] + dx_b), sg.s16(xy[3][1] + dy_b))
    one: list[tuple[int, int]] = []
    other: list[tuple[int, int]] = []
    for k in range(6):
        dy, dx = (dy_a, dx_a) if k <= 2 else (dy_b, dx_b)
        one.append((sg.s16(p[k][0] + dy), sg.s16(p[k][1] - dx)))
        other.append((sg.s16(p[k][0] - dy), sg.s16(p[k][1] + dx)))
    return p + one + other


def draw(ram: Ram, gte: GTE, f: int) -> None:
    """FUN_80192ecc: builds this frame's ten quads of the fighter and files them in the table."""
    if not has_glow(ram, f):
        return
    xy, depth = sg.project(ram, gte, f + SWORD_BLOCK, VIEW, BLADE_POINTS)
    points = ribbon(ram, xy, depth)
    player = ram.s16(f + PLAYER)
    slot = ram.u16(f + SLOT)
    prim = PRIMITIVES + 800 * player + 400 * ram.s32(DISPLAY_BUFFER)
    table = ram.u32(ram.u32(GS_OT) + 4)
    second = player != 0
    tpage = get_tpage(TEXTURE_PAGE[0], TEXTURE_PAGE[2 if second else 1])
    clut = get_clut(*CLUT[1 if second else 0])
    v_shift = SECOND_PLAYER_V if second else 0
    r, g, b = colour_of(slot, ram.s32(PARITY))
    for q in range(QUADS):
        entry = QUAD_TABLE + QUAD_BYTES * q
        ram.put(prim + 4, "B", r)
        ram.put(prim + 5, "B", g)
        ram.put(prim + 6, "B", b)
        ram.put(prim + 7, "B", POLY_FT4)
        for v in range(4):
            x, y = points[ram.u8(entry + v)]
            ram.put(prim + (8, 16, 24, 32)[v], "h", x)
            ram.put(prim + (10, 18, 26, 34)[v], "h", y)
            ram.put(prim + (12, 20, 28, 36)[v], "B", ram.u8(entry + 4 + 2 * v))
            ram.put(prim + (13, 21, 29, 37)[v], "B", ram.u8(entry + 5 + 2 * v) + v_shift)
        ram.put(prim + 14, "H", clut)
        ram.put(prim + 22, "H", tpage)
        head = table + 4 * ((depth[ram.u8(entry + 12)] - sg.DEPTH_BIAS) & 0x3FF)
        ram.put(prim, "I", ram.u32(head) & 0xFFFFFF | FT4_WORDS << 24)
        ram.put(head, "I", ram.u32(head) & 0xFF000000 | prim & 0xFFFFFF)
        prim += PRIM_BYTES
