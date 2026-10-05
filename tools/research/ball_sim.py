#!/usr/bin/env python3
"""Integer port of Tekken Ball's 3D drawing (volley.ovl, Japan Rev.1).

`background_draw` is FUN_800B5F0C: the stage's tile-map panorama (`stg_v` member 2) drawn as
32 x 32 sprites that scroll with the camera yaw and position, over a sky-coloured tile that
fills the screen above the map; the map's top edge follows the projected horizon.

`ball_draw` is FUN_800B3198: the ball as a 42-vertex sphere (16 Gouraud triangles and 32
Gouraud quads, back faces culled with NormalClip) lit by the stage's point light through the
PsyQ lighting pipeline (ColorMatCol with the ball type's colours and specular power), or in a
flat colour for the flash kinds; squashed along an axis on impact; kind 2 adds four
full-height streaks through the ball; and a four-quad shadow on the floor. `sparks` is
FUN_800B47B4 (16 effect particles around the ball). The GTE library it uses is ported in
projection_sim.py.

Verified by `tools/research/verify_ball_sim.py`.
"""

from __future__ import annotations

import draw_sim as ds
import projection_sim as pj
from fight_sim import Ram

M32 = 0xFFFFFFFF

CAMERA = 0x800A8A88              # +4 yaw, +0x14 x, y, z
MODE_KIND = 0x800AFF88           # 0x800AFF50 + 0x38: 1 skips the panorama
LAST_KIND = 0x800B6940
MAP_W, MAP_H = 0x800B6B28, 0x800B6B2C
MAP_TEX, MAP_CLUT = 0x800B6B30, 0x800B6B34   # u16 per cell: texture word (u, v, page), CLUT
SCROLL_DIV = 0x800B6B38          # 0x60
YAW_REF = 0x800B6B3C             # the camera yaw when the panorama was (re)started
VIEW_X = 0x800B6C5C              # the camera's view-space x (kept for the ball code)
SKY = 0x800B6B08                 # per display buffer: TILE (0x21, 0x3A, 0x94)
BG_PACKETS = 0x800AE220          # per buffer: 120 SPRTs (0x960), then at +0x12C0 120 draw modes (0x3C0)
ROUND_FLOW = 0x80097350
SCREEN = 0x800AE6F8              # s16 x, y, w, h
SCENE_OTS = 0x800A911C
TILE = 32
COLUMNS = 15
SCRATCH = 0x1F800300             # the game's stack locals


class BallHooks:
    """Calls outside the drawing: VRAM uploads and the floor set-up (default: nothing)."""

    def upload_textures(self, ram: Ram, archive: int) -> None:
        """FUN_8002988C(1), then OpenTIM/ReadTIM/LoadImage for each member of the TIM archive
        (count, then (offset, size) pairs) until OpenTIM fails, then FUN_8002988C(0)."""

    def floor_setup(self, ram: Ram, arg: int) -> None:
        """FUN_80048548."""


HOOKS = BallHooks()


def background_setup(ram: Ram, arg: int, tile_map: int, archive: int) -> None:
    """FUN_800B5CC4: stores the tile map (u16 w, u16 h, u16 texture[w·h], u16 clut[w·h]),
    uploads the stage textures, prepares 15 sprites per map row and the sky tile per buffer,
    and in True Ogre fights (0x800AFF68) sets up the floor."""
    w, h = ram.u16(tile_map), ram.u16(tile_map + 2)
    ram.put(MAP_TEX, "I", tile_map + 4 & M32)
    ram.put(MAP_W, "I", w)
    ram.put(MAP_H, "I", h)
    ram.put(SCROLL_DIV, "I", 0x60)
    ram.put(MAP_CLUT, "I", tile_map + 4 + 2 * (w * h) & M32)
    HOOKS.upload_textures(ram, archive)
    for buf in range(2):
        base = ram.u32(BG_PACKETS)
        p = base + 0x960 * buf & M32 if base else 0
        for _ in range(max(ram.s32(MAP_H), 0) * COLUMNS):
            for k in range(3):
                ram.put(p + 4 + k, "B", 0x80)
            ram.put(p + 0x10, "H", TILE)
            ram.put(p + 0x12, "H", TILE)
            ram.put(p + 7, "B", ram.u8(p + 7) | 1)      # SetShadeTex(p, 1), undone by SetSprt
            ram.put(p + 3, "B", 4)
            ram.put(p + 7, "B", 0x64)
            p += 0x14
        sky = SKY + 16 * buf
        for k, c in enumerate((0x21, 0x3A, 0x94)):
            ram.put(sky + 4 + k, "B", c)
        ram.put(sky + 8, "H", ram.u16(SCREEN))
        ram.put(sky + 0xA, "H", ram.u16(SCREEN + 2))
        ram.put(sky + 3, "B", 3)                         # SetTile
        ram.put(sky + 7, "B", 0x60)
    if ram.u8(0x800AFF68):
        HOOKS.floor_setup(ram, arg)


def _cdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def _cmod(a: int, b: int) -> int:
    return a - b * _cdiv(a, b)


def background_draw(ram: Ram, gte) -> None:
    """FUN_800B5F0C."""
    kind = ram.u32(MODE_KIND)
    if kind == 1:
        return
    if kind != ram.u32(LAST_KIND):
        ram.put(YAW_REF, "I", ram.u32(CAMERA + 4))
    yaw = ram.u32(CAMERA + 4) & 0xFFF
    cos = ram.s16(pj.SIN_TABLE + 0x800 + 2 * yaw)
    sin = ram.s16(pj.SIN_TABLE + 2 * yaw)
    ram.put(LAST_KIND, "I", kind)
    buf = ram.u32(ds.DISPLAY_BUFFER)
    v, out = SCRATCH, SCRATCH + 0x10
    for i in range(3):
        ram.put(v + 4 * i, "I", ram.u32(CAMERA + 0x14 + 4 * i))
    pj.apply_matrix_lv_gte(ram, gte, pj.VIEW, v, out)
    vx, vz = ram.s32(out), ram.s32(out + 8)
    width = ram.s32(MAP_W)
    scroll = (_cdiv(pj._s32(vx * cos + vz * sin), ram.s32(SCROLL_DIV)) >> 12) + \
        (pj._s32(ram.u32(YAW_REF) - ram.u32(CAMERA + 4)) >> 1)
    scroll = _cmod(pj._s32(scroll), width * TILE)
    ram.put(VIEW_X, "I", vx & M32)
    if scroll < 0:
        scroll += width * TILE
    col = _cdiv(scroll, TILE)
    first = col + 2
    flow = ram.s32(ROUND_FLOW)
    if flow == 2 and kind != 0:
        first = col + 16
    elif flow >= 3:
        first = col + 10
    zero, m = SCRATCH + 0x20, SCRATCH + 0x28
    for i in range(3):
        ram.put(zero + 2 * i, "H", 0)
    pj.rot_matrix_angles(ram, gte, zero, m)
    ram.put(m + 0x18, "I", 0x100)
    ram.put(m + 0x14, "I", pj._s32(ram.u32(CAMERA + 0x14) - sin * 0x1A00) >> 12 & M32)
    ram.put(m + 0x1C, "I", pj._s32(ram.u32(CAMERA + 0x1C) + cos * 0x1A00) >> 12 & M32)
    pj.local_matrix(ram, gte, pj.VIEW, m)
    sxy = SCRATCH + 0x50
    pj.rot_trans_pers_psyq(ram, gte, zero, sxy, sxy + 4, sxy + 8)
    top = ram.s16(sxy + 2) - ram.s32(MAP_H) * TILE
    sky = SKY + 16 * buf & M32
    if top < ram.s16(SCREEN + 6):
        ram.put(sky + 0xE, "H", top & 0xFFFF)
        ram.put(sky + 0xC, "H", ram.u16(SCREEN + 4))
    else:
        ram.put(sky + 0xC, "H", ram.u16(SCREEN + 4))
        ram.put(sky + 0xE, "H", ram.u16(SCREEN + 6))
    tex, clut = ram.u32(MAP_TEX), ram.u32(MAP_CLUT)
    base = ram.u32(BG_PACKETS)
    modes = base + 0x3C0 * buf + 0x12C0 & M32 if base else 0
    sprites = base + 0x960 * buf & M32 if base else 0
    x0 = (_cdiv(scroll, TILE) * TILE - scroll) << 12
    y = top << 12
    ot = ram.u32(ram.u32(SCENE_OTS) + 4) + 0xFC0 & M32
    for row in range(ram.s32(MAP_H)):
        x = x0
        off = y < -0x20000 or 0x1E0 << 12 < y
        for c in range(COLUMNS):
            if not off:
                cell = 2 * (_cmod(first + c, width) + row * width)
                word = ram.u16(tex + cell & M32)
                ram.put(sprites + 0xE, "H", ram.u16(clut + cell & M32))
                ram.put(sprites + 0xC, "B", (word & 7) << 5)
                ram.put(sprites + 0xD, "B", word << 2 & 0xE0)
                ram.put(sprites + 8, "H", _cdiv(x, 0x1000) & 0xFFFF)
                ram.put(sprites + 0xA, "H", _cdiv(y, 0x1000) & 0xFFFF)
                ds.link(ram, ot, sprites, ram.u8(sprites + 3))
                sprites += 0x14
                ram.put(modes + 3, "B", 1)
                ram.put(modes + 4, "I", 0xE1000200 | word >> 8 & 0x1F)
                ds.link(ram, ot, modes, 1)
                modes += 8
            x += 0x20000
        y += 0x20000
    ds.link(ram, ram.u32(ram.u32(SCENE_OTS) + 4) + 0xFF8 & M32, sky, ram.u8(sky + 3))


# ---- the ball (FUN_800B3198) ----
TEXT_OFF = 0x800AE16C
BALL_TYPE = 0x800AFF91           # 0 beach ball, 1 gum ball, 2 iron ball
STYLES = 0x800B6460              # per type (24 bytes): +0xC specular power, +0xD..F back colour
COLOURS = 0x800B6828             # per type (64 bytes): 8 triangle colours, 8 quad colours
NORMALS = 0x800B65F8             # per vertex: SVECTOR normal
TRIANGLES, QUADS = 0x800B6748, 0x800B6788   # vertex indices (4 bytes each), 16 and 32 faces
FRAME = 0x800AE6E0
FROZEN = 0x800958B8
XY, VERTS, COLOUR = 0x1F800000, 0x1F800100, 0x1F800200   # the game's scratchpad use
LOCALS = 0x1F800300              # the game's stack locals
FLAT_KINDS = (0, 1, 2, 5, 8)


def pulse(v: int) -> int:
    """FUN_8004E2C8: a 0-255-0 triangle wave over 512 steps."""
    v &= 0x1FF
    return v if v < 0x100 else 0x1FF - v


def sparks(ram: Ram, pos: int, source: int, low: int) -> None:
    """FUN_800B47B4: 16 particles (effect type 1) within +-255 of `pos`; above the floor they
    take a fixed size and a random flag, near the floor they copy two halfwords of `source`."""
    import ai_sim
    for _ in range(16):
        r1 = ai_sim.rand(ram)
        u = (r1 << 16) + ai_sim.rand(ram) & M32
        e = ds.effect_alloc(ram)
        if e == -1:
            return
        ram.put(e + 0xC, "B", 1)
        ram.put(e + 0x28, "I", ram.u32(pos) - 0xFF + (u >> 23) & M32)
        ram.put(e + 0x2C, "I", ram.u32(pos + 4) - 0xFF + (pj._s32(u) >> 14 & 0x1FF) & M32)
        ram.put(e + 0x30, "I", ram.u32(pos + 8) - 0xFF + (pj._s32(u) >> 5 & 0x1FF) & M32)
        if not low:
            ram.put(e + 0x10, "H", 0x400)
            ram.put(e + 0x12, "H", ai_sim.rand(ram) - 0x800 & 0x100)
        else:
            ram.put(e + 0x10, "H", ram.u16(source))
            ram.put(e + 0x12, "H", ram.u16(source + 4))


def _link(ram: Ram, ot: int, p: int) -> None:
    ds.link(ram, ot, p, ram.u8(p + 3))


def _diagonal(ram: Ram, m: int, q: int) -> None:
    """The squash matrix diag(0x1000 - q, 0x1000 + q, 0x1000 + q) (the pad and translation are
    left as they are)."""
    for i, v in enumerate((0x1000 - q, 0, 0, 0, q + 0x1000, 0, 0, 0, q + 0x1000)):
        ram.put(m + 2 * i, "H", v & 0xFFFF)


def _faces(ram: Ram, gte, table: int, count: int, polys: int, size: int, corners: int,
           flat: bool, colours: int, power: int, ot: int) -> None:
    for i in range(count - 1, -1, -1):
        p, idx = polys + size * i, table + 4 * i
        verts = [ram.u8(idx + k) for k in range(corners)]
        for k, v in enumerate(verts):
            ram.put(p + 8 + 8 * k, "I", ram.u32(XY + 4 * v))
        if pj.normal_clip(gte, ram.u32(p + 8), ram.u32(p + 0x10), ram.u32(p + 0x18)) < 0:
            continue
        if flat:
            for k in range(corners):
                ram.put(p + 4 + 8 * k, "I", ram.u32(COLOUR))
        else:
            ram.put(COLOUR, "I", ram.u32(colours + 4 * (i & 7) & M32))
            for k, v in enumerate(verts):
                pj.color_mat_col(ram, gte, NORMALS + 8 * v, COLOUR, p + 4 + 8 * k, power)
        _link(ram, ot, p)


def ball_draw(ram: Ram, gte, ball: int) -> None:
    """FUN_800B3198 for the ball record at `ball` (+0x48 matrix, +0x68 position, +0x98 angles,
    +0xB4 vertices, +0x146 kind, +0x147 strength, +0x148 squash axis, +0x150 squash)."""
    if ram.u32(TEXT_OFF):
        return
    m = ball + 0x48
    for i in range(3):
        ram.put(ball + 0x5C + 4 * i, "I", ram.u32(ball + 0x68 + 4 * i))
    style = STYLES + 24 * ram.u8(BALL_TYPE)
    power = ram.u8(style + 0xC)
    pj.rot_matrix_angles(ram, gte, ball + 0x98, m)
    pj.light_direction(ram, gte, ball + 0x68)
    squash, light, trans, axis = LOCALS, LOCALS + 0x20, LOCALS + 0x40, LOCALS + 0x60
    q = ram.s16(ball + 0x150)
    if q != 0:
        _diagonal(ram, squash, q)
        pj.rot_matrix_angles(ram, gte, ball + 0x148, axis)
        pj.transpose_matrix(ram, axis, trans)
        pj.mul_matrix(ram, gte, axis, squash)
        pj.mul_matrix(ram, gte, axis, trans)
        pj.mul_matrix2(ram, gte, axis, m)
    pj.light_local(ram, gte, m)
    pj.read_light_matrix(ram, gte, light)
    for off in (0, 4, 2):
        ram.put(light + off, "H", ram.u16(light + off) << 1 & 0xFFFF)
    pj.set_light_matrix(ram, gte, light)
    kind = ram.u8(ball + 0x146)
    if kind == 4 and ram.u32(FROZEN) == 0:
        a = pulse(ram.u32(FRAME) << 4)
        pj.set_back_color(gte, a, a, a)
    else:
        pj.set_back_color(gte, ram.u8(style + 0xD), ram.u8(style + 0xE), ram.u8(style + 0xF))
    pj.local_matrix(ram, gte, pj.VIEW, m)
    for i in range(3):
        ram.put(VERTS + 2 * i, "H", 0)
    centre = LOCALS + 0x80
    z = pj.rot_trans_pers(ram, gte, VERTS, centre)
    if z & 0xFFFF >= 0x4000:
        return
    if kind in (10, 0):
        ot = ram.u32(ds.OT_BASE)
    else:
        ot = ram.u32(ram.u32(SCENE_OTS) + 4) + (z >> 1 & 0x1FFC) & M32
    pj.rot_trans_pers_n(ram, gte, ram.u32(ball + 0xB4), XY, VERTS, 0x2A)
    k = ram.u8(ball + 0x147)
    colours = 0
    if kind == 0:
        for i in range(3):
            ram.put(COLOUR + i, "B", -8 * k & 0xFF)
    elif kind == 1:
        for i in range(3):
            ram.put(COLOUR + i, "B", 8 * k - 1 & 0xFF)
    elif kind in (2, 5, 8):
        ram.put(COLOUR, "I", M32)
    else:
        colours = COLOURS + 64 * ram.u8(BALL_TYPE)
    flat = kind in FLAT_KINDS
    buf = ram.u32(ds.DISPLAY_BUFFER)
    ram.put(COLOUR + 3, "B", 0x30)                                  # POLY_G3
    _faces(ram, gte, TRIANGLES, 16, ball + 0x1C0 * buf + 0x154 & M32, 0x1C, 3, flat, colours, power, ot)
    ram.put(COLOUR + 3, "B", 0x38)                                  # POLY_G4
    _faces(ram, gte, QUADS, 32, ball + 0x480 * buf + 0x4D4 & M32, 0x24, 4, flat, colours + 0x20, power, ot)
    if kind == 2:
        _streaks(ram, ball, buf, centre, k)
    _shadow(ram, gte, ball, buf, m)


def _streaks(ram: Ram, ball: int, buf: int, centre: int, k: int) -> None:
    """Kind 2: four streaks (0x1C-byte primitives) from the ball's centre to the top and bottom
    of the screen, jittered while the fight runs and held while it is frozen."""
    import ai_sim
    ot = ram.u32(ds.OT_BASE)
    sxy = ram.u32(centre)
    if ram.u32(FROZEN) == 0:
        if k == 5:
            sparks(ram, ball + 0x68, ball + 0x78, int(ram.s32(ball + 0x6C) < -0x180))
        for i in range(4):
            f = ball + 0x70 * buf + 0xEAC + 0x1C * i & M32
            ram.put(f + 8, "I", sxy)
            x = ram.u16(centre) + (ai_sim.rand(ram) >> 4) - 0x400 & 0xFFFF
            ram.put(f + 0x10, "H", x)
            ram.put(f + 0x18, "H", x + 8 * k & 0xFFFF)
            ram.put(f + 0x1A, "H", 0 if i & 2 else 0x1E0)
            ram.put(f + 0x12, "H", ram.u16(f + 0x1A))
            _link(ram, ot, f)
    else:
        for i in range(4):
            f = ball + 0x70 * buf + 0xEAC + 0x1C * i & M32
            other = ball + 0x70 * (1 - buf) + 0xEAC + 0x1C * i & M32
            ram.put(f + 8, "I", sxy)
            ram.put(f + 0x10, "I", ram.u32(other + 0x10))
            ram.put(f + 0x18, "I", ram.u32(other + 0x18))
            _link(ram, ot, f)
    _link(ram, ot, ball + 0xC * buf + 0xE94 & M32)


def _shadow(ram: Ram, gte, ball: int, buf: int, m: int) -> None:
    """Four flat quads from the ball's equator ring (vertices 18-25) flattened onto the floor."""
    saved = ram.u32(ball + 0x60)
    ram.put(ball + 0x60, "I", 0)
    squash, ang, ang2, axis, scale = LOCALS, LOCALS + 0xA0, LOCALS + 0xB0, LOCALS + 0xC0, LOCALS + 0xE0
    ram.put(ang, "H", 0)
    ram.put(ang + 2, "H", ram.u16(ball + 0x9A))
    ram.put(ang + 4, "H", 0)
    pj.rot_matrix_angles(ram, gte, ang, m)
    q = ram.s16(ball + 0x150)
    _diagonal(ram, squash, q)
    ram.put(ang2, "H", 0)
    ram.put(ang2 + 2, "H", ram.u16(ball + 0x14A))
    ram.put(ang2 + 4, "H", 0)
    pj.rot_matrix_angles(ram, gte, ang2, axis)
    pj.mul_matrix(ram, gte, axis, squash)
    pj.mul_matrix2(ram, gte, axis, m)
    stretch = (ram.s32(ball + 0x6C) >> 1) + 0x1000 & M32
    ram.put(scale, "I", stretch)
    ram.put(scale + 4, "I", 0x1000)
    ram.put(scale + 8, "I", stretch)
    pj.scale_matrix(ram, m, scale)
    pj.local_matrix(ram, gte, pj.VIEW, m)
    ot = ram.u32(ram.u32(SCENE_OTS) + 4) + 0xFBC & M32
    for i in range(4):
        ring = ram.u32(ball + 0xB4) + 0x90
        for slot, v in enumerate((i, i + 1, i + 5 & 7, i + 4 & 7)):
            ram.put(VERTS + 8 * slot, "I", ram.u32(ring + 8 * v & M32))
            ram.put(VERTS + 8 * slot + 4, "I", ram.u32(ring + 8 * v + 4 & M32))
        for slot in (3, 2, 1, 0):
            ram.put(VERTS + 8 * slot + 2, "H", 0)
        p = ball + 0x60 * buf + 0xDD4 + 0x18 * i & M32
        pj.rot_trans_pers_n(ram, gte, VERTS, p + 8, VERTS, 4)
        _link(ram, ot, p)
    ram.put(ball + 0x60, "I", saved)


# ---- the court (FUN_800B3DA4) ----
COURT = 0x800B6AB8               # the court's local MATRIX; its z translation follows the fighters
CENTRE_BAND = 0x800B6948         # 18 SVECTORs: 9 pairs (x = -100 / +100) from z = -8000 by 0x600
SIDE_LINES = 0x800B69D8          # 18 SVECTORs: 9 pairs at x = -/+ the court half-width


def court_draw(ram: Ram, gte, a: int, b: int, ball: int) -> None:
    """FUN_800B3DA4: the court markings, placed at z = (a + b) / 2 (the two fighters): the
    centre band as 8 semi-transparent Gouraud quads and the two side lines as 16 semi-transparent
    Gouraud lines (their colours fade with distance, set up with the ball), then a draw mode."""
    if ram.u32(TEXT_OFF):
        return
    ram.put(COURT + 0x1C, "I", pj._s32(a + b) >> 1 & M32)
    zero = LOCALS
    for i in range(3):
        ram.put(zero + 2 * i, "H", 0)
    pj.rot_matrix_angles(ram, gte, zero, COURT)
    pj.local_matrix(ram, gte, pj.VIEW, COURT)
    ot = ram.u32(ram.u32(SCENE_OTS) + 4) + 0xFD8 & M32
    buf = ram.u32(ds.DISPLAY_BUFFER)
    pj.rot_trans_pers_n(ram, gte, CENTRE_BAND, XY, VERTS, 18)
    band = ball + 0x120 * buf + 0x120C & M32
    for j in range(7, -1, -1):
        p = band + 0x24 * j
        for k in (3, 2, 1, 0):
            ram.put(p + 8 + 8 * k, "I", ram.u32(XY + 4 * (2 * j + k)))
        _link(ram, ot, p)
    pj.rot_trans_pers_n(ram, gte, SIDE_LINES, XY, VERTS, 18)
    lines = ball + 0x140 * buf + 0xF8C & M32
    for j in range(7, -1, -1):
        first, second = lines + 0x28 * j, lines + 0x28 * j + 0x14
        ram.put(first + 0x10, "I", ram.u32(XY + 4 * (2 * j + 3)))
        ram.put(second + 0x10, "I", ram.u32(XY + 4 * (2 * j + 2)))
        ram.put(first + 8, "I", ram.u32(XY + 4 * (2 * j + 1)))
        ram.put(second + 8, "I", ram.u32(XY + 4 * 2 * j))
        _link(ram, ot, second)
        _link(ram, ot, first)
    _link(ram, ot, ball + 0xC * buf + 0x144C & M32)


# ---- the ball's physics (FUN_800B16A4) ----
SPEED_UNIT, SPIKE_UNIT = 0x800B6AD8, 0x800B6ADA      # s16 per ball type
GRAVITY, NEUTRAL, GAIN = 0x800B6ADC, 0x800B6ADE, 0x800B6AE0
IDLE = 0x800B6AE4                # frames the ball has lain on the floor
TOUCH_SOUND_WAIT = 0x800B6AE8
POINT = 0x800B6B4C               # 1 + the index of the player who lost the point (0 = none)
CHARGED_HIT = 0x800B6B54
HIT_VOLUME = 0x800B6808          # 4 SVECTORs: the ball's hit points (0, ±0x80)
THIRD = 0x800AC808               # the third fighter record, the ball's stand-in attacker
LOB_BASE = 0x800AFF04
RESULT = 0x800AFF8C
NO_SCORE = 0x800958A0            # points are not scored (demonstration/replay)
NO_WINNER_MARK = 0x800958C4
ROUND_CLOCK = 0x80095884
EXCLAIM = 0x800B0A38             # "!"
TEXT_BUF = 0x1F800380            # the game's stack buffer for the damage text


class BallPhysicsHooks:
    """Calls into the resident engine (default: nothing)."""

    def sound(self, ram: Ram, sound_id: int) -> None:
        """SoundPlayFighter(0, id, 0)."""

    def vibrate(self, ram: Ram, player: int, kind: int) -> None:
        """FighterVibrate (0x800760D4)."""

    def camera_shake(self, ram: Ram, kind: int) -> None:
        """CameraShakeStart (0x8004AF94)."""

    def replay_event(self, ram: Ram, player: int, kind: int) -> None:
        """FUN_8004A840(player, kind, stack buffer, 1): a replay event; its three data words come
        from an uninitialised stack buffer."""


PHYSICS_HOOKS = BallPhysicsHooks()


def _div(a: int, b: int) -> int:
    """C division with the R3000 quotient for a zero divisor."""
    a, b = pj._s32(a), pj._s32(b)
    if b == 0:
        return -1 if a >= 0 else 1
    return _cdiv(a, b)


def _words(ram: Ram, a: int, n: int) -> list[int]:
    return [ram.s32(a + 4 * i) for i in range(n)]


def attack_touch(ram: Ram, f_a: int, f_b: int, cyl: int, out: int) -> int:
    """FUN_80048030: the fighters' attack segments against the cylinder at `cyl`; bit 2 for
    `f_a`, bit 1 for `f_b`, bit 8 when a fighter's move uses projectile segments. The first
    hitting segment's direction goes to `out`."""
    import fight_math
    mask, bit, f = 0, 2, f_a
    segs = count = 0
    for _ in range(2):
        move = ram.u32(f + 0x54)
        if ram.u8(ram.u32(move + 0x28)) < 0x18:
            count = min(ram.u8(f + 0xE3), 4)
            segs = f + 0x1AC
        else:
            mask |= 8
            idx = ram.u8(f + 0x1E)
            if idx <= 2:
                table = 0 if idx == 0 else 1
                count = ram.s32(0x800AE374 + 4 * table)
                base = ram.u32(0x800AE148)
                segs = base + table * 0x780 + 0x3200 & M32 if base else 0
        for _k in range(max(count, 0)):
            if fight_math.segment_hits_cylinder(_words(ram, segs, 6), _words(ram, cyl, 5)):
                s = _words(ram, segs, 6)
                for i in range(3):
                    ram.put(out + 4 * i, "I", s[3 + i] - s[i] & M32)
                mask |= bit
                break
            segs += 0x18
        bit, f = 1, f_b
    return mask


def body_touch(ram: Ram, f_a: int, f_b: int, segs: int) -> int:
    """FUN_800481AC: the ball's four swept hit points against each fighter's 14 hurt
    cylinders; the first contact is recorded in the fighter (+0x154 cylinder, +0x13C end point,
    +0x14C direction). Bit 2 for `f_a`, bit 1 for `f_b`."""
    import fight_math
    mask, bit, f = 0, 2, f_a
    for _ in range(2):
        done = False
        for k in range(14):
            c = f + 0x20C + 0x14 * k
            if ram.s16(c + 0xC) == 0:
                continue
            for j in range(4):
                s = segs + 0x18 * j
                if fight_math.segment_hits_cylinder(_words(ram, s, 6), _words(ram, c, 5)):
                    ram.put(f + 0x154, "H", k)
                    for i in range(3):
                        ram.put(f + 0x13C + 4 * i, "I", ram.u32(s + 0xC + 4 * i))
                        ram.put(f + 0x14C + 2 * i, "H", ram.u16(s + 0xC + 4 * i) - ram.u16(s + 4 * i) & 0xFFFF)
                    mask |= bit
                    done = True
                    break
            if done:
                break
        bit, f = 1, f_b
    return mask


def squash_axis(ram: Ram, out: int, d: int) -> None:
    """volley.ovl FUN_800B3118: the squash axis angles from the hit direction at `d`."""
    import ai_update
    exe = ai_update._exe_view(ram)
    import fight_math
    x, y, z = _words(ram, d, 3)
    ram.put(out, "H", 0)
    ram.put(out + 2, "H", fight_math.atan2_4096(x, z, exe) & 0xFFFF)
    a = fight_math.atan2_4096(x, y, exe)
    ram.put(out + 4, "H", (a if x > 0 else -a) & 0xFFFF)


def damage_text(ram: Ram, n: int, out: int) -> None:
    """FUN_800B42A4: the decimal digits of `n` (via the BCD of FUN_8004CE74)."""
    v = ds._bcd(ram, n)
    digits = ds.nibbles(v)
    k = max(digits - 1, 0)
    for s in range(4 * k, -1, -4):
        ram.put(out, "B", (v >> s & 0xF) + 0x30)
        out += 1
    ram.put(out, "B", 0)


def burn(ram: Ram, player: int) -> None:
    """FUN_8006F248: sets the player's fighter on fire (effect type 11): ten flames, or one
    marked flame for Gon (character 17) as the one whose opponent index `+0x22` points at."""
    PHYSICS_HOOKS.vibrate(ram, player, 0)
    who = ram.u8(0x800A9712 + player * 0x188C & M32)
    gon = ram.s16(0x800A9708 + who * 0x188C & M32) == 0x11
    n = 10
    if gon:
        n = 1
        ram.put(0x800AE39E, "B", ram.u8(0x800AE39E) | 0x10 >> (player & 0x1F) & 0xFF)
    for i in range(n):
        e = ds.effect_alloc(ram)
        if e == -1:
            return
        if ram.s16(0x800A9708 + ram.u8(0x800A9712 + player * 0x188C & M32) * 0x188C & M32) == 0x11:
            ram.put(e + 0xD, "B", ram.u8(e + 0xD) | 0x20)
        ram.put(e + 0xC, "B", 0xB)
        ram.put(e + 0x48, "I", i)
        ram.put(e + 0x4C, "I", ram.u32(0x800253DC + 4 * i))
        ram.put(e + 0xD, "B", ram.u8(e + 0xD) | 0x10 >> (player & 0x1F) & 0xFF)


def _hit_volume(ram: Ram, ball: int) -> None:
    """The four hit points sweep from their last position to the ball's position + offset."""
    for j in range(4):
        s = ball + 0xD0 + 0x18 * j
        for i in range(3):
            ram.put(s + 4 * i, "I", ram.u32(s + 0xC + 4 * i))
        for i in range(3):
            ram.put(s + 0xC + 4 * i, "I", ram.u32(ball + 0x68 + 4 * i) + ram.s16(HIT_VOLUME + 8 * j + 2 * i) & M32)


def _target(ram: Ram, positions: int, fighter: int) -> tuple[int, int]:
    p = ram.u32(positions + 4 * ram.u8(fighter + 0x1E))
    return ram.s32(p), ram.s32(p + 8)


def _charge_hit(ram: Ram, gte, ball: int, hitter: int, base_add: int, cap: int) -> int:
    """The shared part of a charging hit: re-hit bookkeeping, the hitter's power gain (damage ·
    gain / 100), the charge, the damage popup; returns the speed step count clamped to 20..cap."""
    if ram.s16(ball + 0x140):
        ram.put(ball + 0x145, "B", 1)
        ram.put(ball + 0x144, "B", ram.u8(ball + 0x144) + 1 & 0xFF)
    add = _cdiv(ram.s16(hitter + 0x5E) * ram.s16(GAIN), 100)
    slot = ball + 0x13C + 2 * ram.s16(hitter + 0x12)
    power = ram.u16(slot) + add & 0xFFFF
    ram.put(slot, "H", power)
    ram.put(ball + 0x140, "H", power)
    damage_text(ram, add, TEXT_BUF)
    ram.put(ball + 0xB2, "H", 1)
    colour = 2 if ram.u8(ram.u32(ball + 0x130) + 0x1E) == 0 else 5
    ds.ball_popup_add(ram, gte, TEXT_BUF, ball + 0x68, colour, 1, 0x1E)
    steps = ds._s16(ram.u16(hitter + 0x5E) + base_add)
    if steps >= cap + 1:
        steps = cap
    elif steps < 0x14:
        steps = 0x14
    return steps


def _speed_from_steps(ram: Ram, ball: int, steps: int) -> None:
    speed = (steps + ram.u8(ball + 0x144)) * ram.s16(SPIKE_UNIT)
    if ram.u8(ball + 0x145):
        speed += ram.s32(ball + 0xA8) >> 4
    ram.put(ball + 0xA8, "I", speed & M32)


def _attack_hit(ram: Ram, gte, ball: int, hitter: int, other: int, positions: int, mask: int, d: int) -> None:
    """A fighter's attack hits the ball (the branch after FUN_80048030)."""
    import ai_update
    import fight_math
    PHYSICS_HOOKS.vibrate(ram, ram.s16(hitter + 0x12), 5)
    ram.put(ball + 0xAC, "I", 0)
    ram.put(ball + 0x130, "I", hitter)
    ram.put(ball + 0x134, "I", other)
    ram.put(ball + 0xB2, "H", 0)
    for i in range(0, 0x188C, 4):
        ram.put(THIRD + i, "I", ram.u32(hitter + i))
    ram.put(THIRD + 0x1E, "B", 2)
    ram.put(THIRD + 0x122, "H", 1)
    ram.put(THIRD + 0x64, "H", 0xFFFF)
    ram.put(THIRD + 0xDF, "B", 1)
    for off, v in ((0x85, 1), (0x88, 1), (0xD1, 1), (0x23, 2)):
        ram.put(hitter + off, "B", v)
    ram.put(ball + 0xCC, "B", 5)
    tx, tz = _target(ram, positions, other)
    exe = ai_update._exe_view(ram)
    ram.put(ball + 0xB0, "H", fight_math.atan2_4096(tx - ram.s32(ball + 0x68), tz - ram.s32(ball + 0x70), exe) & 0xFFFF)
    squash_axis(ram, ball + 0x148, d)
    ram.put(ball + 0xCD, "B", 1)
    ram.put(ball + 0x150, "H", ram.u16(hitter + 0x5E) * 8 + 0x140 & 0xFFFF)
    g = ram.s16(GRAVITY)
    unit = ram.s16(SPEED_UNIT)
    x = ram.s32(ball + 0x68)
    level = ram.u16(hitter + 0x64)
    damage = ram.s16(hitter + 0x5E)
    lob_vy = lambda: pj._s32(tz_other() - 2 * ram.s32(ball + 0x6C) - ram.s32(LOB_BASE))
    tz_other = lambda: ram.s32(ram.u32(positions + 4 * ram.u8(other + 0x1E)) + 8)

    def flat(extra: int) -> None:
        ram.put(ball + 0x8C, "I", g & M32)
        ram.put(ball + 0x7C, "I", -0x25 * g & M32)
        quarter = ram.s32(ball + 0xA8) >> 2
        v = pj._s32((damage + extra) * unit)
        v = v - x if x < 0 else v + x
        v = pj._s32(v - quarter)
        ram.put(ball + 0xA8, "I", max(v, 0) & M32 if v >= 0 else 0)
        ram.put(ball + 0x140, "H", 0)
        ram.put(ball, "H", 2)

    if mask & 3 == 3:                                     # both players at once
        ram.put(ball + 0x140, "H", 0)
        ram.put(ball + 0xA8, "I", 0)
        ram.put(ball, "H", 2)
        ram.put(ball + 0x7C, "I", -0x25 * g & M32)
        ram.put(ball + 0x8C, "I", g & M32)
    elif (ram.s16(hitter + 0x16) == 4 and level in (0x607, 0x706) and not mask & 8
          and ram.s16(hitter + 0xA0) != 0x181):            # Yoshimitsu's unblockable
        hp = pj._s32(ram.u32(hitter + 0x3F4) - (ram.s16(ball + 0x13C + 2 * ram.u8(other + 0x1E)) << 16))
        ram.put(hitter + 0x3F4, "I", max(hp, 0) & M32)
        ram.put(ball + 0x13E, "H", 0)
        ram.put(ball + 0x13C, "H", 0)
        ram.put(ball, "H", 7)
        ram.put(ball + 0x147, "B", 5)
        ram.put(POINT, "I", ram.u8(hitter + 0x1E) + 1)
    elif damage == 0:                                     # a set
        if ram.s16(ball + 0x140) > 0:
            ram.put(ball, "H", 3)
            ram.put(ball + 0x7C, "I", -0x25 * g & M32)
            ram.put(ball + 0x8C, "I", g & M32)
            ram.put(ball + 0x142, "H", ram.u16(ball + 0xA8) + ram.u16(SPIKE_UNIT) * 5 & 0xFFFF)
            quarter = ram.s32(ball + 0xA8) >> 2
            v = pj._s32((damage + 8) * unit)
            v = pj._s32((v + x if x >= 0 else v - x) - quarter)
            ram.put(ball + 0xA8, "I", v & M32 if v >= 0 else 0)
            ram.put(ball + 0x140, "H", 0)
            ram.put(ball + 0xCC, "B", ram.u8(ball + 0xCC) + 2 & 0xFF)
            ds.ball_popup_add(ram, gte, EXCLAIM, ball + 0x68, 1, 1, 0x1E)
            PHYSICS_HOOKS.sound(ram, 0x7082)
        else:
            flat(10)
    elif level in (0x607, 0x706):                         # unblockable: homing with the charge
        ram.put(ball + 0xB2, "H", 1)
        ram.put(ball + 0xA8, "I", ram.s16(SPIKE_UNIT) * 60 & M32)
        ram.put(ball + 0x8C, "I", ram.s16(GRAVITY) >> 2 & M32)
        ram.put(ball + 0x140, "H", ram.u16(ball + 0x13C + 2 * ram.s16(hitter + 0x12)))
        ram.put(ball, "H", 2)
        ram.put(ball + 0x7C, "I", lob_vy() & M32)
        ds.ball_popup_add(ram, gte, EXCLAIM, ball + 0x68, 2, 1, 0x1E)
    elif ram.u8(hitter + 0xDB) == 0:
        if level in (0x31F, 0x217):                       # mids: a charged lob
            steps = _charge_hit(ram, gte, ball, hitter, 0x12, 0x2E)
            _speed_from_steps(ram, ball, steps)
            ram.put(ball + 0x8C, "I", ram.s16(GRAVITY) >> 2 & M32)
            ram.put(ball, "H", 2)
            ram.put(ball + 0x7C, "I", lob_vy() & M32)
        elif level in (0x10F, 0x51F):                     # lows
            ram.put(ball + 0x7C, "I", -0x32 * g & M32)
            ram.put(ball + 0x8C, "I", g & M32)
            ax = -x if x < 0 else x
            ram.put(ball + 0xA8, "I", pj._s32((ds._s16(ram.u16(hitter + 0x5E)) >> 2) * unit + ax) & M32)
            ram.put(ball + 0x140, "H", 0)
            ram.put(ball, "H", 2)
        elif level == 0x412:                              # highs
            if ram.s16(ball) != 3:
                flat(10)
            else:                                         # a spike
                ram.put(ball, "H", 4)
                ram.put(ball + 0x138, "I", other)
                ram.put(ball + 0x7C, "I", -0x48 * g & M32)
                ram.put(ball + 0x8C, "I", g & M32)
                ram.put(ball + 0xA8, "I", unit * 10 & M32)
                PHYSICS_HOOKS.sound(ram, 0x4DAF)
                _charge_hit(ram, gte, ball, hitter, 0, 0x7FFF)
    else:                                                 # the hitter is airborne
        steps = _charge_hit(ram, gte, ball, hitter, 0xF, 0x28)
        _speed_from_steps(ram, ball, steps)
        ram.put(ball, "H", 2)
        ram.put(ball + 0x8C, "I", ram.s16(GRAVITY) >> 1 & M32)
        ram.put(ball + 0x7C, "I", pj._s32(tz_other() - ram.s32(ball + 0x6C) - ram.s32(LOB_BASE)) & M32)


def _charged_touch(ram: Ram, ball: int, hitter: int, other: int) -> None:
    """The charged ball reaches the opponent: the resident hit system with the third fighter as
    the attacker, whose damage is the charge."""
    charge = ram.u16(ball + 0x140)
    ram.put(THIRD + 0x5E, "H", charge)
    ram.put(ball + 0x130, "I", hitter)
    ram.put(ball + 0x134, "I", other)
    ram.put(ball, "H", 2)
    ram.put(CHARGED_HIT, "B", 1)
    ram.put(ball + 0x140, "H", 0)
    ram.put(THIRD + 0x83 + ram.u8(other + 0x1E), "B", 1)
    ram.put(THIRD + 0x88, "B", 1)
    ram.put(THIRD + 0xD1, "B", 1)
    ram.put(THIRD + 0x23, "B", ram.u8(other + 0x1E))
    ram.put(hitter + 0x87, "B", 1)
    ram.put(hitter + 0xCE, "B", 1)
    ram.put(hitter + 0xEE, "H", ram.u8(ram.u32(THIRD + 0x54) + 0x2C))
    ram.put(hitter + 0x15D, "B", 1)
    ram.put(hitter + 0x15C, "B", 2)
    charge = ram.s16(THIRD + 0x5E)
    if charge != 0 or ram.u8(hitter + 0xDB):
        ram.put(hitter + 0x104, "H", 4)
    lethal = charge > 99 or ram.u8(ball + 0x146) == 9
    if ram.u16(hitter + 0x66) & ram.u16(THIRD + 0x64) == 0:          # not guarded
        if lethal:
            burn(ram, ram.u8(hitter + 0x1E))
            PHYSICS_HOOKS.replay_event(ram, ram.u8(hitter + 0x1E), 0x82)
            if ram.u8(0x800AFF91) == 2:
                ram.put(RESULT, "I", 6)
        g = ram.u16(GRAVITY)
        ram.put(ball + 0xA8, "I", 0)
        ram.put(ball + 0x144, "B", 0)
        ram.put(ball + 0x13C, "H", 0)
        ram.put(ball + 0x13E, "H", 0)
        ram.put(ball, "H", 5)
        ram.put(ball + 0x130, "I", hitter)
        ram.put(ball + 0x134, "I", hitter)
        ram.put(ball + 0xCC, "B", 5)
        ram.put(ball + 0x7C, "I", ds._s16(g) * -0x25 & M32)
        ram.put(ball + 0x8C, "I", ds._s16(g) >> 1 & M32)
        PHYSICS_HOOKS.sound(ram, 0x4E6D if charge < 0x32 else 0x4DAF)
    else:
        PHYSICS_HOOKS.sound(ram, 0x7043)
        if lethal and ram.s32(hitter + 0x3F4) <= pj._s32(charge << 13):
            burn(ram, ram.u8(hitter + 0x1E))
            PHYSICS_HOOKS.replay_event(ram, ram.u8(hitter + 0x1E), 0x82)


def _touches(ram: Ram, gte, ball: int, f_a: int, f_b: int, positions: int) -> int:
    """The attack and body tests of a flying ball; returns the hit mask (the game's $s7)."""
    import ai_update
    import fight_math
    for i in range(3):
        ram.put(ball + 0xB8 + 4 * i, "I", ram.u32(ball + 0x68 + 4 * i))
    d = LOCALS + 0x100
    mask = attack_touch(ram, f_a, f_b, ball + 0xB8, d)
    if mask & 7:
        hitter, other = (f_a, f_b) if mask & 2 else (f_b, f_a)
        if ram.u8(hitter + 0x85) == 0:
            _attack_hit(ram, gte, ball, hitter, other, positions, mask, d)
        return mask
    mask = 0
    if ram.u8(f_a + 0xC4) == 0 and ram.u8(f_b + 0xC4) == 0:
        mask = body_touch(ram, f_a, f_b, ball + 0xD0)
    if ram.s32(0x80097350) > 5:
        if ram.u8(f_b + 0xC3) == 0:
            mask &= 2
        elif ram.u8(f_a + 0xC3) == 0:
            mask &= 1
    if mask == 0:
        return 0
    hitter, other = (f_a, f_b) if mask & 2 else (f_b, f_a)
    owner, charge = ram.u32(ball + 0x130), ram.s16(ball + 0x140)
    if hitter == owner and charge != 0:
        return mask
    tx, tz = _target(ram, positions, other)
    ram.put(ball + 0xAC, "I", 0)
    ram.put(ball + 0xB2, "H", 0)
    if ram.s16(ball) != 3:
        ram.put(ball, "H", 2)
    exe = ai_update._exe_view(ram)
    ram.put(ball + 0xB0, "H", fight_math.atan2_4096(tx - ram.s32(ball + 0x68), tz - ram.s32(ball + 0x70), exe) & 0xFFFF)
    lob = ram.u32(LOB_BASE)
    g = ram.s16(GRAVITY)
    k = pj._s32((lob >> 7) + 12)
    ram.put(ball + 0x8C, "I", g & M32)
    ram.put(ball + 0x7C, "I", pj._s32((pj._s32(-g * k) >> 1) - pj._s32(ram.s32(ball + 0x6C) + 0x1000)) & M32)
    dist = pj._s32(lob - 0x800) if lob > 0x800 else 0x400
    ram.put(ball + 0xA8, "I", _div(pj._s32(dist << 8), k) & M32)
    if charge == 0 or owner == hitter:
        if ram.s32(TOUCH_SOUND_WAIT) == 0:
            PHYSICS_HOOKS.sound(ram, 0x704E)
            ram.put(TOUCH_SOUND_WAIT, "I", 10)
        ram.put(ball + 0x130, "I", hitter)
        ram.put(ball + 0x134, "I", other)
    else:
        _charged_touch(ram, ball, hitter, other)
    return mask


def ball_update(ram: Ram, gte, ball: int, f_a: int, f_b: int, positions: int, s7: int = 0) -> None:
    """FUN_800B16A4: one frame of the ball (see modes.md, Tekken Ball). `positions` points at the
    two fighters' position pointers (`+0xF68`). `s7` is the caller's $s7, which the game reuses as
    the hit mask on the frames that skip the hit tests (a register left over from start-up)."""
    import ai_update
    import fight_math
    keep = ram.u8(ball + 0x145) if ram.u8(ball + 0xCC) else 0
    ram.put(ball + 0x145, "B", keep)
    ram.put(CHARGED_HIT, "B", 0)
    ram.put(POINT, "I", 0)
    st = ram.s16(ball)
    if st == 0:
        t = ram.u8(ball + 0x147) - 1 & 0xFF
        ram.put(ball + 0x147, "B", t)
        if t == 0:
            ram.put(ball, "H", 8)
            ram.put(ball + 0x147, "B", 0x20)
            PHYSICS_HOOKS.sound(ram, 0x4CE8)
        return
    if st in (1, 8):
        t = ram.u8(ball + 0x147) - 1 & 0xFF
        ram.put(ball + 0x147, "B", t)
        if t:
            return
        ram.put(ball, "H", 9 if st == 8 else 2)
        ram.put(ball + 0xA8, "I", 0)
        ram.put(ball + 0xCC, "B", 0)
        ram.put(ball + 0xB0, "H", 0)
        ram.put(ball + 0xB2, "H", 0)
        p0, p1 = ram.u32(positions), ram.u32(positions + 4)
        x0, x1 = min(ram.s32(p0), 0), max(ram.s32(p1), 0)
        z0 = ram.s32(p0 + 8)
        dx, dz = pj._s32(x1 - x0), pj._s32(ram.s32(p1 + 8) - z0)
        if dx != 0:
            ram.put(ball + 0x70, "I", z0 + _div(pj._s32((ram.s32(ball + 0x68) - x0) * dz), dx) & M32)
        else:
            ram.put(ball + 0x68, "I", x0 + _div(0, dz) & M32)
        return
    if st == 6:
        ram.put(ball + 0x140, "H", 0)
        ram.put(ball + 0x144, "B", 0)
        t = ram.u8(ball + 0x147) - 1 & 0xFF
        ram.put(ball + 0x147, "B", t)
        if t:
            return
        ram.put(ball, "H", 1)
        ram.put(ball + 0x147, "B", 0x20)
        ram.put(ball + 0x68, "I", 0)
        ram.put(ball + 0x6C, "I", -0xE40 & M32)
        for off in (0x90, 0x88, 0x80, 0x7C, 0x78):
            ram.put(ball + off, "I", 0)
        for off in (0xA4, 0xA2, 0xA0):
            ram.put(ball + off, "H", 0)
        ram.put(ball + 0x8C, "I", ram.s16(GRAVITY) >> 1 & M32)
        z = pj._s32(ram.s32(ram.u32(positions) + 8) + ram.s32(ram.u32(positions + 4) + 8)) >> 1
        ram.put(ball + 0x70, "I", z & M32)
        _hit_volume(ram, ball)
        _hit_volume(ram, ball)
        if ram.u32(NO_SCORE) == 0:
            PHYSICS_HOOKS.sound(ram, 0x4CE9)
        return
    if st == 7:
        ram.put(ball + 0x140, "H", 0)
        ram.put(ball + 0x144, "B", 0)
        t = ram.u8(ball + 0x147) - 1 & 0xFF
        ram.put(ball + 0x147, "B", t)
        if t == 0:
            ram.put(ball, "H", 6)
            ram.put(ball + 0x147, "B", 0x10)
        return
    mask = s7 & M32
    g = ram.s16(GRAVITY)
    y = ram.s32(ball + 0x6C)
    if st == 4 and y < -0x1400:                            # a spike reaches the ceiling
        ram.put(ball + 0x6C, "I", -0x1400 & M32)
        ram.put(ball + 0x8C, "I", g & M32)
        ram.put(ball, "H", 2)
        ram.put(ball + 0x134, "I", ram.u32(ball + 0x138))
        ram.put(ball + 0xA8, "I", ram.s16(ball + 0x142) & M32)
        ram.put(ball + 0x7C, "I", _cdiv(ram.s16(ball + 0x142) * 2, 3) + 0x1000 & M32)
    elif st != 4 and y < -0x2000:                          # the ceiling
        ram.put(ball + 0x6C, "I", -0x2000 & M32)
        ram.put(ball + 0x7C, "I", 0)
        ram.put(ball + 0x8C, "I", g & M32)
    else:
        mask = _floor_and_touches(ram, gte, ball, f_a, f_b, positions, mask)
    _tail(ram, ball, positions, mask)


def _floor_and_touches(ram: Ram, gte, ball: int, f_a: int, f_b: int, positions: int, mask: int) -> int:
    g = ram.s16(GRAVITY)
    x = ram.s32(ball + 0x68)
    ax = -x if x < 0 else x
    if ram.s32(ball + 0x6C) >= -0x180 or ax > 0x2800:      # it comes down (or leaves the court)
        ram.put(ball + 0x6C, "I", -0x180 & M32)
        ram.put(ball + 0x8C, "I", g & M32)
        vy = ram.s32(ball + 0x7C)
        if vy > 0xD00:
            PHYSICS_HOOKS.sound(ram, 0x4E6E)
        if ram.u8(0x800AFF91) == 2:
            if vy > 0x3000:
                PHYSICS_HOOKS.camera_shake(ram, 1)
            elif vy > 0x1800:
                PHYSICS_HOOKS.camera_shake(ram, 0)
        x = ram.s32(ball + 0x68)
        if (-x if x < 0 else x) <= ram.s16(NEUTRAL):      # bounce in the neutral zone
            ram.put(ball, "H", 2)
            ram.put(ball + 0x7C, "I", pj._s32(-ram.s32(ball + 0x7C)) >> 1 & M32)
            for off in (0xA0, 0xA2, 0xA4):
                ram.put(ball + off, "H", ram.s16(ball + off) >> 1 & 0xFFFF)
        else:
            ram.put(ball + 0x7C, "I", 0)
            ram.put(ball + 0xA8, "I", 0)
            if ram.u32(NO_SCORE) != 0 or ram.s16(ball) == 5:
                ram.put(ball, "H", 6)
                ram.put(ball + 0x147, "B", 0x10)
                return mask
            ram.put(ball + (0x13C if x < 0 else 0x13E), "H", 0)
            loser = f_a if x < 0 else f_b
            hp = pj._s32(ram.u32(loser + 0x3F4) - 0x1E0000)
            ram.put(loser + 0x3F4, "I", hp & M32)
            ram.put(loser + 0x22, "B", ram.u8(loser + 0x1E) + 1 & 1)
            if hp < 0:
                ram.put(loser + 0x3F4, "I", 0)
            ram.put(ball, "H", 7)
            ram.put(ball + 0x147, "B", 5)
            ram.put(POINT, "I", 0 if ram.u32(NO_WINNER_MARK) else ram.u8(loser + 0x1E) + 1)
            ram.put(THIRD + 0xF68, "I", ram.u32(ball + 0x68))
            ram.put(THIRD + 0xF70, "I", ram.u32(ball + 0x70))
            return mask
    if ram.s32(ball + 0x6C) < -0x189:
        ram.put(IDLE, "I", 0)
    else:
        n = ram.s32(IDLE) + 1
        ram.put(IDLE, "I", n & M32)
        if n >= 600:
            ram.put(ball, "H", 6)
            ram.put(ball + 0x147, "B", 0x10)
            return mask
    if ram.s16(ball + 0xB2) == 0:
        v = pj._s32(ram.s32(ball + 0xA8) - 0x20)
        ram.put(ball + 0xA8, "I", v & M32 if v >= 0 else 0)
    if ram.u8(ball + 0xCC):
        ram.put(ball + 0xCC, "B", ram.u8(ball + 0xCC) - 1)
        return mask
    return _touches(ram, gte, ball, f_a, f_b, positions)


def _tail(ram: Ram, ball: int, positions: int, mask: int) -> None:
    import ai_update
    import fight_math
    angle = ram.u16(ball + 0xB0) & 0xFFF
    cos = ram.s16(pj.SIN_TABLE + 0x800 + 2 * angle)
    sin = ram.s16(pj.SIN_TABLE + 2 * angle)
    speed = ram.s32(ball + 0xA8)
    ram.put(ball + 0x78, "I", pj._s32(cos * speed) >> 12 & M32)
    ram.put(ball + 0x80, "I", pj._s32(sin * speed) >> 12 & M32)
    if ram.s16(ball) == 9:                                  # the serve: bob until touched
        t = ram.u8(ball + 0x147)
        v = ram.u16(pj.SIN_TABLE + (t << 6 & 0x1FC0))
        ram.put(ball + 0x147, "B", t + 1 & 0xFF)
        ram.put(ball + 0x6C, "I", (ds._s16(v) >> 4) - 0x500 & M32)
        if ram.s32(ROUND_CLOCK) >= 600:
            ram.put(ball, "H", 2)
            ram.put(ball + 0x7C, "I", 0)
    else:
        for i, off in enumerate((0x78, 0x7C, 0x80)):
            ram.put(ball + 0x68 + 4 * i, "I", ram.u32(ball + 0x68 + 4 * i) + (ram.s32(ball + off) >> 8) & M32)
    _hit_volume(ram, ball)
    ram.put(ball + 0x7C, "I", ram.u32(ball + 0x7C) + ram.u32(ball + 0x8C) & M32)
    if mask and ram.s16(ball) != 3:                         # spin from the new flight
        angle = ram.u16(ball + 0xB0) & 0xFFF
        cos = ram.s16(pj.SIN_TABLE + 0x800 + 2 * angle)
        sin = ram.s16(pj.SIN_TABLE + 2 * angle)
        speed = ram.s32(ball + 0xA8)
        spin = pj._s32(cos * speed) >> (0x11 if ram.s16(ball + 0xB2) else 0x13)
        ram.put(ball + 0xA4, "H", spin & 0xFFFF)
        ram.put(ball + 0xA0, "H", ds._s16(spin) >> 2 & 0xFFFF)
        ram.put(ball + 0xA2, "H", pj._s32(sin * speed) >> 0x13 & 0xFFFF)
    for i in range(3):
        ram.put(ball + 0x98 + 2 * i, "H", ram.u16(ball + 0x98 + 2 * i) + ram.u16(ball + 0xA0 + 2 * i) & 0xFFFF)
    z_old = ram.s32(ball + 0x70)
    mid = pj._s32(ram.s32(ram.u32(positions) + 8) + ram.s32(ram.u32(positions + 4) + 8)) >> 1
    if pj._s32(z_old - mid) > 0x80:
        ram.put(ball + 0x70, "I", mid + 0x80 & M32)
    if pj._s32(ram.s32(ball + 0x70) - mid) < -0x80:
        ram.put(ball + 0x70, "I", mid - 0x80 & M32)
    ram.put(ball + 0x98, "H", ram.u16(ball + 0x98) + ram.u16(ball + 0x70) - (z_old & 0xFFFF) & 0xFFFF)
    tx, tz = _target(ram, positions, ram.u32(ball + 0x134))
    a = ram.s16(ball + 0xB0)
    if a < -0x800:
        ram.put(ball + 0xB0, "H", a + 0x1000 & 0xFFFF)
    if ram.s16(ball + 0xB0) > 0x800:
        ram.put(ball + 0xB0, "H", ram.u16(ball + 0xB0) - 0x1000 & 0xFFFF)
    if ram.s16(ball + 0xB2) == 0:
        return
    exe = ai_update._exe_view(ram)
    ram.put(ball + 0xB0, "H", fight_math.atan2_4096(tx - ram.s32(ball + 0x68), tz - ram.s32(ball + 0x70), exe) & 0xFFFF)
    if ram.s32(ball + 0xA8) <= 0x1000:
        return
    dx, dz = pj._s32(ram.s32(ball + 0x68) - tx), pj._s32(ram.s32(ball + 0x70) - tz)
    dist = fight_math.isqrt(pj._s32(pj._s32(dx * dx) + pj._s32(dz * dz)) & M32)
    n = _div(dist, ram.s32(ball + 0xA8) >> 8)
    vy = ram.s32(ball + 0x7C)
    head = ram.s32(ram.u32(ball + 0x134) + 0x950)
    fall = pj._s32(vy + pj._s32(n * ram.s32(ball + 0x8C))) >> 8
    miss = pj._s32(pj._s32(ram.s32(ball + 0x6C) + fall - head) << 8)
    q = _div(pj._s32(vy - miss), n)
    ram.put(ball + 0x7C, "I", pj._s32(pj._s32(vy * 13 + q * 3) << 8) >> 12 & M32)


# ---- the ball's life cycle: set-up, per-frame hook, render kind ----
BALL_PTR = 0x800AE23C
BALL_TABLE = 0x800B6460          # per ball type (24 bytes): spike unit, speed unit, gravity, gain, neutral zone
GLOWS = 0x800B645C               # u8: effect-15 glows already started (bit player + 2·big)
BALL_VERTICES = 0x800B64A8
IDENTITY = 0x800AE3E0            # the 32-byte identity MATRIX that FUN_8003C454 copies
MODE_FLAGS = 0x800AFF90          # +0: the side that serves first
REPLAY_PLAYBACK = 0x800958C8
FROZEN_FIGHT = 0x8009588C


class BallFlowHooks:
    """Engine calls of the set-up and frame hooks (default: nothing)."""

    def face_opponent(self, ram: Ram, fighter: int, other: int) -> None:
        """FUN_8002BFCC(fighter, other, 0)."""

    def replay_ball(self, ram: Ram, ball: int) -> None:
        """FUN_800339F4: records the ball into, or plays it back from, the replay ring."""


FLOW_HOOKS = BallFlowHooks()


def _set_prim(ram: Ram, p: int, words: int, code: int) -> None:
    ram.put(p + 3, "B", words)
    ram.put(p + 7, "B", code)


def _semi(ram: Ram, p: int, on: int) -> None:
    """SetSemiTrans (0x8007BF4C)."""
    c = ram.u8(p + 7)
    ram.put(p + 7, "B", c | 2 if on else c & 0xFD)


def _draw_mode(ram: Ram, p: int) -> None:
    """SetDrawMode(p, 0, 1, 0x20, NULL): additive blending, dithered."""
    ram.put(p + 3, "B", 2)
    ram.put(p + 4, "I", ds.draw_mode_word(0, 1, 0x20))
    ram.put(p + 8, "I", 0)


def ball_init(ram: Ram) -> None:
    """FUN_800B0FDC: the ball and its packets at the start of a round."""
    ball = ram.u32(BALL_PTR)
    ram.put(ball, "H", 0)
    ram.put(ball + 2, "H", 0)
    ram.put(ball + 0x147, "B", 100 if ram.s32(0x800958A8) == 1 else 40)
    ram.put(ball + 0x44, "I", 0)                                  # FUN_8003C4A4(0, ball + 4)
    for i in range(0, 0x20, 4):                                    # FUN_8003C454
        ram.put(ball + 0x48 + i, "I", ram.u32(IDENTITY + i))
    side = ram.u8(MODE_FLAGS)
    ram.put(ball + 0x68, "I", (0xD00 if side else -0xD00) & M32)
    ram.put(ball + 0x130, "I", 0x800A96F0 + 0x188C * ram.u8(MODE_FLAGS) & M32)
    ram.put(ball + 0x6C, "I", -0x500 & M32)
    for off, v in ((0xA0, 0x20), (0xA2, 0x10), (0xA4, 4)):
        ram.put(ball + off, "H", v)
    for off in (0x70, 0xA8, 0xAC, 0x7C, 0x80, 0x78, 0x90, 0x8C, 0x88):
        ram.put(ball + off, "I", 0)
    for off in (0x13C, 0x13E, 0x140, 0x9C, 0x9A, 0x98, 0xB0, 0xB2, 0x14C, 0x14A, 0x148, 0x150):
        ram.put(ball + off, "H", 0)
    ram.put(ball + 0xCC, "B", 0)
    ram.put(ball + 0x134, "I", 0x800A96F0 + 0x188C * (1 - ram.u8(MODE_FLAGS)) & M32)
    ram.put(ball + 0x8C, "I", ram.s16(GRAVITY) & M32)
    ram.put(ball + 0x144, "B", 0)
    ram.put(ball + 0xC4, "H", 0x260)                               # hit radius 608
    ram.put(ball + 0xC8, "I", 0x5A400)
    ram.put(ball + 0xB4, "I", BALL_VERTICES)
    for i in range(3):
        ram.put(ball + 0xB8 + 4 * i, "I", ram.u32(ball + 0x68 + 4 * i))
    _hit_volume(ram, ball)
    _hit_volume(ram, ball)
    zone = ram.u16(NEUTRAL)
    z = -0x1F40
    for i in range(9):                                             # the court's vertices
        for base, x in ((CENTRE_BAND, 0x64), (SIDE_LINES, zone)):
            for k, sx in enumerate((-x, x)):
                v = base + 16 * i + 8 * k
                ram.put(v, "H", sx & 0xFFFF)
                ram.put(v + 2, "H", 0)
                ram.put(v + 4, "H", z & 0xFFFF)
        z += 0x600
    shades = [max(0xC0 - (0x30 * (4 - k) if k < 4 else 0x30 * (k - 4)), 0) & 0xFF for k in range(9)]
    colour = [0x3A000000 | v << 16 | v << 8 | v for v in shades]
    for b in range(2):
        for j in range(7, -1, -1):
            q = ball + 0x120C + 0x120 * b + 0x24 * j
            ram.put(q + 0x14, "I", colour[j + 1])
            ram.put(q + 0x1C, "I", colour[j + 1])
            ram.put(q + 4, "I", colour[j])
            ram.put(q + 0xC, "I", colour[j])
            _set_prim(ram, q, 8, 0x3A)
            second = ball + 0xFA0 + 0x140 * b + 0x28 * j
            ram.put(second + 0xC, "I", colour[j + 1])
            ram.put(second + 4, "I", colour[j])
            _set_prim(ram, second, 4, 0x52)
            first = ball + 0xF8C + 0x140 * b + 0x28 * j
            ram.put(first + 4, "I", colour[j])
            ram.put(first + 0xC, "I", colour[j + 1])
            _set_prim(ram, first, 4, 0x52)
        _draw_mode(ram, ball + 0x144C + 0xC * b)
    for b in range(2):
        for i in range(16):
            p = ball + 0x154 + 0x1C0 * b + 0x1C * i
            for k in range(3):
                ram.put(p + 4 + k, "B", 0x80)
            _set_prim(ram, p, 6, 0x30)
            _semi(ram, p, 0)
        for i in range(32):
            p = ball + 0x4D4 + 0x480 * b + 0x24 * i
            for k in range(3):
                ram.put(p + 4 + k, "B", 0x80)
            _set_prim(ram, p, 8, 0x38)
            _semi(ram, p, 0)
        for i in range(4):
            sh = ball + 0xDD4 + 0x60 * b + 0x18 * i
            _set_prim(ram, sh, 5, 0x28)
            _semi(ram, sh, 0)
            st = ball + 0xEAC + 0x70 * b + 0x1C * i
            for k in range(3):
                ram.put(st + 4 + k, "B", 0xFF)
                ram.put(st + 0xC + k, "B", 0x30)
                ram.put(st + 0x14 + k, "B", 0x30)
            _set_prim(ram, st, 6, 0x30)
            _semi(ram, st, 1)
        _draw_mode(ram, ball + 0xE94 + 0xC * b)
    shadow = ram.u32(0x80097090 + 0x1C * (ram.u16(0x800AE14C) + 1) & M32) | 0x29000000
    for b in range(2):
        for i in range(4):
            ram.put(ball + 0xDD8 + 0x60 * b + 0x18 * i, "I", shadow)


def glow(ram: Ram, player: int, big: int) -> None:
    """FUN_800B4720: once per player and size, effect type 15 (the charged ball's glow)."""
    u = player + 2 * big & M32
    bit = 1 << (u & 0x1F) & M32
    if ram.u8(GLOWS) & bit:
        return
    e = ds.effect_alloc(ram)
    if e == -1:
        return
    ram.put(e + 0xC, "B", 0xF)
    ram.put(e + 0x40, "I", u & 1)
    ram.put(e + 0x4C, "I", (u & 0xFF) >> 1)
    ram.put(GLOWS, "B", ram.u8(GLOWS) | bit & 0xFF)


def ball_after_update(ram: Ram, ball: int) -> None:
    """FUN_800B2F14: the squash relaxes (a homing ball keeps wobbling along its flight) and the
    render kind `+0x146` is chosen: 0 serve, 1 reset, 2 point, 3 flying, 4 set, 5 just touched,
    6/7 charged by player 1/2, 8 re-hit charge, 9 charge of 100 or more."""
    s = ram.s16(ball + 0x150)
    relax = True
    if ram.s16(ball + 0xB2):
        if s < 0x80:
            relax = False
            ram.put(ball + 0xCD, "B", 0)
            squash_axis(ram, ball + 0x148, ball + 0x78)
            ram.put(ball + 0x14C, "H", ram.u16(ball + 0x14C) + 0x400 & 0xFFFF)
            v = _cdiv(ds._s16(ram.u16(ball + 0x150)) * 2, 3) + _cdiv(ram.s32(ball + 0xA8) >> 6, 3)
            ram.put(ball + 0x150, "H", v & 0xFFFF)
        elif ram.u8(ball + 0xCD) == 0:
            relax = False
    if relax:
        s = ram.s16(ball + 0x150)
        ram.put(ball + 0x150, "H", ram.u16(ball + 0x150) - ((s + 0x10) >> 4) & 0xFFFF)
    st = ram.s16(ball)
    if st == 6:
        kind = 1
    elif st in (1, 8):
        ram.put(ball + 0x146, "B", 0)
        return
    elif st == 7:
        kind = 2
    else:
        charge = ram.s16(ball + 0x140)
        if charge == 0:
            if ram.u8(ball + 0xCC):
                kind = 5
            else:
                ram.put(ball + 0x146, "B", 4 if st == 3 else 3)
                return
        else:
            who = ram.u8(ram.u32(ball + 0x130) + 0x1E)
            ram.put(ball + 0x147, "B", who)
            if charge < 100:
                if ram.u8(ball + 0xCC) == 5:
                    glow(ram, who, 0)
                ram.put(ball + 0x146, "B", 7 if ram.u8(ball + 0x147) else 6)
            else:
                if ram.u8(ball + 0xCC) == 5:
                    glow(ram, who, 1)
                ram.put(ball + 0x146, "B", 9)
            if ram.u8(ball + 0xCC) == 0:
                return
            kind = 8 if ram.u8(ball + 0x145) else 5
    ram.put(ball + 0x146, "B", kind)


DRIFT = 0x800B6B40               # per player (6 bytes): s16 angle offset, u8 speed, u8 and two frame marks


def drift_clear(ram: Ram, player: int) -> None:
    """FUN_800B0B24."""
    r = DRIFT + 6 * player & M32
    ram.put(r, "H", 0)
    for k in range(2, 6):
        ram.put(r + k, "B", 0)


def move_tuning(ram: Ram, f: int) -> None:
    """FUN_800B0B54 (after MoveStartAll): the Tekken Ball tuning of the running move slot
    (`+0xA0` - 0x18): slots 0x18/0x1A drift (0x8000, 30, 3, 9); 0x1E/0x20 (0x8000, 150, 5, 12,
    look-ahead from frame 18); 0x1F/0x21 only the look-ahead frame 18."""
    r = DRIFT + 6 * ram.s16(f + 0x12) & M32
    ram.put(r, "H", 0)
    for k in range(2, 6):
        ram.put(r + k, "B", 0)
    k = ds._s16(ram.u16(f + 0xA0) - 0x18 & 0xFFFF)
    if not 0 <= k < 10:
        return
    kind = (0, None, 0, None, None, None, 1, 2, 1, 2)[k]
    if kind == 0:
        ram.put(r, "H", 0x8000)
        for i, v in enumerate((0x1E, 3, 9)):
            ram.put(r + 2 + i, "B", v)
    elif kind == 1:
        ram.put(r, "H", 0x8000)
        for i, v in enumerate((0x96, 5, 0xC, 0x12)):
            ram.put(r + 2 + i, "B", v)
    elif kind == 2:
        ram.put(r + 5, "B", 0x12)


def popups_clear(ram: Ram) -> None:
    """FUN_800B431C."""
    for i in range(8):
        ram.put(ds.POPUP_SLOTS + 0x20 * i + 0x1F, "B", 0)
    ram.put(ds.POPUP_NEXT, "I", 0)
    ram.put(ds.BALL_POPUPS, "I", 0)


def gauges_clear(ram: Ram) -> None:
    """FUN_800B4E30."""
    for g in range(2):
        r = ds.BALL_GAUGES + 0x10 * g
        ram.put(r, "I", 0)
        for off in (4, 6, 8):
            ram.put(r + off, "H", 0)


def fight_start(ram: Ram) -> None:
    """FUN_800B0C90 (mode 7 fight start): the ball type's constants, the ball, the players at
    x = -/+0x1400 facing each other, and two points per round."""
    t = BALL_TABLE + 24 * ram.u8(0x800AFF91)
    for dst, src in ((SPIKE_UNIT, 0), (SPEED_UNIT, 4), (GRAVITY, 8), (GAIN, 0x10), (NEUTRAL, 0x14)):
        ram.put(dst, "H", ram.u16(t + src))
    ball_init(ram)
    for i in range(2):
        f = 0x800A96F0 + 0x188C * i
        ram.put(f, "I", (-0x1400 if i == 0 else 0x1400) & M32)
        ram.put(f + 8, "I", 0)
        ram.put(f + 0xE, "H", 0x4000 if i == 0 else 0xC000)
        FLOW_HOOKS.face_opponent(ram, f, 0x800A96F0 + 0x188C * (1 - i))
    popups_clear(ram)
    gauges_clear(ram)
    ram.put(0x800AFF88, "I", 0)
    ram.put(RESULT, "I", 2)
    ram.put(GLOWS, "B", 0)
    ram.put(TOUCH_SOUND_WAIT, "I", 0)


def round_reset(ram: Ram) -> None:
    """FUN_800B0DD8."""
    ram.put(0x800B6A68 + 0x40, "I", 0)                           # FUN_8003C4A4(0, 0x800B6A68)
    for i in range(0, 0x20, 4):
        ram.put(COURT + i, "I", ram.u32(IDENTITY + i))
    ball_init(ram)


POSITION_PTRS = 0x1F800390       # the game's stack pair of position pointers


def ball_frame(ram: Ram, gte, f_a: int, f_b: int, s7: int = 0) -> None:
    """FUN_800B0E14 (after MoveBranchAll): the ball's physics unless the fight is frozen, the
    court, the ball, the power gauges and the popups."""
    ball = ram.u32(BALL_PTR)
    ram.put(POSITION_PTRS, "I", f_a + 0xF68 & M32)
    ram.put(POSITION_PTRS + 4, "I", f_b + 0xF68 & M32)
    if ram.s32(0x80097350) == 1:
        ram.put(RESULT, "I", 2)
    if ram.s32(TOUCH_SOUND_WAIT) > 0:
        ram.put(TOUCH_SOUND_WAIT, "I", ram.s32(TOUCH_SOUND_WAIT) - 1 & M32)
    if ram.u32(FROZEN_FIGHT) == 0 and ram.u32(FROZEN) == 0:
        FLOW_HOOKS.replay_ball(ram, ball)
        if ram.u32(REPLAY_PLAYBACK) == 0:
            ball_update(ram, gte, ball, f_a, f_b, POSITION_PTRS, s7)
            ball_after_update(ram, ball)
        elif ram.u32(ball + 0x144) & 0xFFFF0000 == 0x05020000:
            PHYSICS_HOOKS.sound(ram, 0x4E6E)
    court_draw(ram, gte, ram.u32(f_a + 0xF70), ram.u32(f_b + 0xF70), ball)
    if ram.s16(ball):
        ball_draw(ram, gte, ball)
    if ram.u8(0x80098DDD) != 2 or ram.u8(0x800AFF6C) == 1:
        charge = ram.s16(ball + 0x140)
        hl = 1 << (ram.u8(ram.u32(ball + 0x130) + 0x1E) & 0x1F) if charge else 0
        ds.ball_gauges(ram, ram.s16(ball + 0x13C), 100, ram.s16(ball + 0x13E), hl)
        ds.ball_popups(ram, int(bool(ram.u32(FROZEN) or ram.u32(FROZEN_FIGHT))))
