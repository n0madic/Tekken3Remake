#!/usr/bin/env python3
"""Integer port of the world-to-screen projection used to place 2D elements over the 3D scene
(Japan Rev.1): the view-space transform FUN_8004B05C, the matrix helper FUN_80081C7C and the
one-point RotTransPers FUN_80036D28.

The projection runs on the Geometry Transformation Engine, whose registers are not in RAM: the
ports take a `psxcpu.GTE` (the harness's bit-exact model) holding the camera's projection plane H
(control register 26) and screen offsets OFX/OFY (24, 25), and update its rotation and
translation as the game does. Verified by `tools/research/verify_projection_sim.py`.
"""

from __future__ import annotations

from fight_sim import Ram
from psxcpu import GTE, s32

VIEW = 0x800AE438                # the camera's view MATRIX: 3 x 3 s16, pad, s32 translation at +0x14
M32 = 0xFFFFFFFF
RTPS = 0x180001                  # sf = 1


def _row(ram: Ram, m: int, r: int, v: tuple[int, int, int]) -> int:
    a = sum(ram.s16(m + 6 * r + 2 * k) * v[k] for k in range(3))
    return s32(a) >> 12


def apply_matrix_lv(ram: Ram, m: int, x: int, y: int, z: int) -> tuple[int, int, int]:
    """FUN_80081C7C: m · (x, y, z) >> 12 per row (32-bit products), keeping a coordinate
    unchanged when its row is the identity row."""
    v = (x, y, z)
    ox = x if ram.u32(m) == 0x1000 and ram.s16(m + 4) == 0 else _row(ram, m, 0, v)
    oy = y if ram.s16(m + 6) == 0 and ram.u32(m + 8) == 0x1000 else _row(ram, m, 1, v)
    oz = z if ram.u32(m + 0xC) == 0 and ram.s16(m + 0x10) == 0x1000 else _row(ram, m, 2, v)
    return ox, oy, oz


def set_rotation(gte: GTE, ram: Ram, m: int) -> None:
    """SetRotMatrix (0x80082A5C)."""
    for i in range(5):
        gte.write_ctrl(i, ram.u32(m + 4 * i))


def set_translation(gte: GTE, t: tuple[int, int, int]) -> None:
    """SetTransMatrix (0x80082AEC)."""
    for i in range(3):
        gte.write_ctrl(5 + i, t[i] & M32)


def view_point(ram: Ram, gte: GTE, x: int, y: int, z: int) -> None:
    """FUN_8004B05C: the GTE's rotation becomes the view matrix and its translation the point in
    view space (view · point >> 12 + view translation)."""
    ox, oy, oz = apply_matrix_lv(ram, VIEW, x, y, z)
    t = tuple(s32(o + ram.s32(VIEW + 0x14 + 4 * i)) for i, o in enumerate((ox, oy, oz)))
    set_rotation(gte, ram, VIEW)
    set_translation(gte, t)


def rot_trans_pers(ram: Ram, gte: GTE, v: int, out: int) -> int:
    """FUN_80036D28: projects the SVECTOR at `v`; writes the screen xy word to `out` and returns
    the depth SZ3 / 4 (the ordering-table index)."""
    gte.write_data(0, ram.u32(v))
    gte.write_data(1, ram.u32(v + 4))
    gte.command(RTPS)
    ram.put(out, "I", gte.read_data(14))
    return gte.read_data(19) >> 2


def screen_of(ram: Ram, gte: GTE, x: int, y: int, z: int, scratch: int) -> tuple[int, int, int]:
    """The pattern the game uses (FUN_8004B05C, then FUN_80036D28 on a zero vector): screen x, y
    and the depth index of a world point. `scratch` is 16 bytes for the zero vector and result
    (the game uses its stack)."""
    view_point(ram, gte, x, y, z)
    ram.put(scratch, "I", 0)
    ram.put(scratch + 4, "I", 0)
    z4 = rot_trans_pers(ram, gte, scratch, scratch + 8)
    return ram.s16(scratch + 8), ram.s16(scratch + 10), z4


MVMVA_IR_RAW = 0x1E012           # MVMVA sf=0, rotation · IR, no translation
MVMVA_IR = 0x9E012               # the same with sf=1


def _split(v: int) -> tuple[int, int]:
    """ApplyRotMatrixLV's split of a 32-bit component into high (>> 15) and low 15 bits,
    each keeping the sign."""
    v = s32(v)
    if v >= 0:
        return v >> 15, v & 0x7FFF
    a = -v & M32
    return -(a >> 15), -(a & 0x7FFF)


def apply_rot_matrix_lv(gte: GTE, v: tuple[int, int, int]) -> tuple[int, int, int]:
    """ApplyRotMatrixLV (0x8008247C): the GTE rotation times a 32-bit vector, as the high parts
    (unshifted, then << 3) plus the low parts (>> 12)."""
    parts = [_split(c) for c in v]
    for i in range(3):
        gte.write_data(9 + i, parts[i][0] & M32)
    gte.command(MVMVA_IR_RAW)
    hi = [s32(gte.read_data(25 + i)) for i in range(3)]
    for i in range(3):
        gte.write_data(9 + i, parts[i][1] & M32)
    gte.command(MVMVA_IR)
    lo = [s32(gte.read_data(25 + i)) for i in range(3)]
    return tuple(s32(lo[i] + (hi[i] << 3)) for i in range(3))


def local_screen(ram: Ram, gte: GTE, t: tuple[int, int, int], out: int) -> None:
    """FUN_80037AB0 with a local matrix whose translation is `t`, then FUN_80036D28 on a zero
    vector: writes the screen xy word of the view-space point view · t + view translation to
    `out`. (The game passes an uninitialised rotation to MulRotMatrix, which leaves the GTE
    rotation undefined afterwards, game-bugs.md #40; the port leaves it as the view rotation.)"""
    set_rotation(gte, ram, VIEW)
    r = apply_rot_matrix_lv(gte, t)
    set_translation(gte, tuple(s32(r[i] + ram.s32(VIEW + 0x14 + 4 * i)) for i in range(3)))
    gte.write_data(0, 0)
    gte.write_data(1, 0)
    gte.command(RTPS)
    ram.put(out, "I", gte.read_data(14))


GPF = 0x198003D                  # GPF sf=1: IR = IR0 · IR >> 12
MVMVA_ROT_V0 = 0x486012          # MVMVA sf=1, rotation · V0, no translation
SIN_TABLE = 0x8001E8C4           # 4,096 s16 sines; the cosines start 1,024 entries later


def apply_matrix_lv_gte(ram: Ram, gte: GTE, m: int, v: int, out: int) -> None:
    """ApplyMatrixLV (0x8008229C): the rotation `m` (set on the GTE) times the 32-bit VECTOR at
    `v`, written to `out`."""
    set_rotation(gte, ram, m)
    r = apply_rot_matrix_lv(gte, tuple(ram.s32(v + 4 * i) for i in range(3)))
    for i in range(3):
        ram.put(out + 4 * i, "I", r[i] & M32)


def _gpf(gte: GTE, ir0: int, ir: tuple[int, int, int]) -> tuple[int, int, int]:
    gte.write_data(8, ir0 & M32)
    for i in range(3):
        gte.write_data(9 + i, ir[i] & M32)
    gte.command(GPF)
    return tuple(s32(gte.read_data(9 + i)) for i in range(3))


def rot_matrix_angles(ram: Ram, gte: GTE, v: int, out: int) -> None:
    """FUN_8003A6E4: the rotation matrix of the SVECTOR angles at `v` (x, y, z; 4,096 = one
    turn), written to the 3 x 3 s16 matrix at `out`, using the GTE's GPF for three products."""
    w0, vz = ram.u32(v), ram.s16(v + 4)
    sin = lambda i: ram.s16(SIN_TABLE + 2 * i)
    cos = lambda i: ram.s16(SIN_TABLE + 0x800 + 2 * i)
    ix, iy, iz = w0 & 0xFFF, w0 >> 16 & 0xFFF, vz & 0xFFF
    cz, cx, cy, sx, sz = cos(iz), cos(ix), cos(iy), sin(ix), sin(iz)
    cxcz = s32(cx * cz) >> 12
    cxsz = s32(cx * sz) >> 12
    a1, a2, a3 = _gpf(gte, sx, (cz, sz, cy))           # sx·cz, sx·sz, sx·cy
    sy = sin(iy)
    b1, b2, b3 = _gpf(gte, sy, (a1, a2, cxcz))          # sy·sx·cz, sy·sx·sz, sy·cx·cz
    ram.put(out + 0xA, "h", -a3 & 0xFFFF)
    ram.put(out + 4, "H", sy & 0xFFFF)
    c1, c2, c3 = _gpf(gte, cy, (cz, -sz, cx))           # cy·cz, -cy·sz, cy·cx
    ram.put(out + 6, "H", b1 + cxsz & 0xFFFF)
    ram.put(out + 8, "H", cxcz - b2 & 0xFFFF)
    ram.put(out + 0xC, "H", a2 - b3 & 0xFFFF)
    ram.put(out + 0xE, "H", (s32(cxsz * sy) >> 12) + a1 & 0xFFFF)
    ram.put(out, "H", c1 & 0xFFFF)
    ram.put(out + 2, "H", c2 & 0xFFFF)
    ram.put(out + 0x10, "H", c3 & 0xFFFF)


def _columns(ram: Ram, gte: GTE, m: int) -> list[list[int]]:
    """The GTE rotation times each column of the matrix at `m` (MVMVA), as raw IR words."""
    cols = []
    for c in range(3):
        gte.write_data(0, ram.u16(m + 2 * c) | ram.u16(m + 6 + 2 * c) << 16)
        gte.write_data(1, ram.s16(m + 0xC + 2 * c) & M32)
        gte.command(MVMVA_ROT_V0)
        cols.append([gte.read_data(9 + i) for i in range(3)])
    return cols


def _packed(cols: list[list[int]]) -> tuple[int, int, int, int, int]:
    """The five matrix words of the product columns, as the library stores them."""
    lo = lambda c, r: cols[c][r] & 0xFFFF
    hi = lambda c, r: cols[c][r] << 16 & M32
    return (lo(0, 0) | hi(1, 0), lo(2, 0) | hi(0, 1), lo(1, 1) | hi(2, 1), lo(0, 2) | hi(1, 2),
            cols[2][2] & M32)


def set_mul_rot_matrix(ram: Ram, gte: GTE, m: int) -> None:
    """SetMulRotMatrix (0x800825BC): the GTE rotation becomes rotation · m."""
    for i, w in enumerate(_packed(_columns(ram, gte, m))):
        gte.write_ctrl(i, w)


def mul_matrix0(ram: Ram, gte: GTE, a: int, b: int, out: int) -> None:
    """MulMatrix0 (0x8008218C): out = a · b (the GTE rotation is left as a)."""
    set_rotation(gte, ram, a)
    for i, w in enumerate(_packed(_columns(ram, gte, b))):
        ram.put(out + 4 * i, "I", w)


def mul_matrix(ram: Ram, gte: GTE, a: int, b: int) -> None:
    """MulMatrix (0x800826AC): a = a · b."""
    mul_matrix0(ram, gte, a, b, a)


def mul_matrix2(ram: Ram, gte: GTE, a: int, b: int) -> None:
    """MulMatrix2 (0x800827BC): b = a · b."""
    mul_matrix0(ram, gte, a, b, b)


def transpose_matrix(ram: Ram, a: int, b: int) -> None:
    """TransposeMatrix (0x80082C8C), with the library's store order."""
    t1, t2 = ram.u32(a), ram.u32(a + 4)
    ram.put(b + 4, "I", t1)
    ram.put(b, "I", t2)
    ram.put(b, "H", t1 & 0xFFFF)
    t3, t1 = ram.u32(a + 8), ram.u32(a + 0xC)
    ram.put(b + 0xC, "I", t3)
    ram.put(b + 8, "I", t1)
    ram.put(b + 0xC, "H", t2 & 0xFFFF)
    ram.put(b + 8, "H", t3 & 0xFFFF)
    t2 = ram.u16(a + 0x10)
    ram.put(b + 4, "H", t1 & 0xFFFF)
    ram.put(b + 0x10, "H", t2)


def scale_matrix(ram: Ram, m: int, v: int) -> None:
    """ScaleMatrix (0x8008291C): column k times v[k] >> 12; the last element is stored as a
    full word (over the pad)."""
    s = [ram.s32(v + 4 * k) for k in range(3)]
    e = [ram.s16(m + 2 * i) for i in range(9)]
    p = [s32(e[i] * s[i % 3]) >> 12 for i in range(9)]
    for w in range(4):
        ram.put(m + 4 * w, "I", p[2 * w] & 0xFFFF | p[2 * w + 1] << 16 & M32)
    ram.put(m + 0x10, "I", p[8] & M32)


def read_light_matrix(ram: Ram, gte: GTE, out: int) -> None:
    """ReadLightMatrix (0x8008242C): the light matrix and the back colour."""
    for i in range(5):
        ram.put(out + 4 * i, "I", gte.read_ctrl(8 + i))
    for i in range(3):
        ram.put(out + 0x14 + 4 * i, "I", gte.read_ctrl(13 + i))


def set_light_matrix(ram: Ram, gte: GTE, m: int) -> None:
    """SetLightMatrix (0x80082A8C)."""
    for i in range(5):
        gte.write_ctrl(8 + i, ram.u32(m + 4 * i))


def set_back_color(gte: GTE, r: int, g: int, b: int) -> None:
    """SetBackColor (0x80082B0C)."""
    for i, c in enumerate((r, g, b)):
        gte.write_ctrl(13 + i, c << 4 & M32)


MODE = 0x800AFF50                # the game state (5 = practice)
STAGE_RECORDS = 0x80097080       # the light record of stage n is at +0x1C·(n + 1); +0 is the ambient u16
STAGE_RECORD_BYTES = 0x1C
SIGNAL = 0x800AE430              # practice's FREEZE SIGNAL per player: flag, R, G, B bytes
FLASH = 0x8009E998               # per player: the back colour flash's counter (Tekken Force's pick-ups)
FLASH_FRAMES = 0x20
GTE_ONE = 0x2000                 # the flash peaks at 2.0 in GTE units (4096 = 1.0)
PRACTICE = 5


def fighter_back_colour(ram: Ram, gte: GTE, player: int, stage: int) -> None:
    """FUN_8003A3B8 (called by FUN_8003AA6C unless the fighter's keepLight flag is set, which calls
    SetBackColor(0, 0, 0) instead): the back colour the fighter is lit with, for `player` (the
    fighter's +0x12) on `stage` (0x800AE14C).

    Practice's FREEZE SIGNAL (when its flag byte is set) replaces everything. Otherwise the stage's
    ambient A (a u16, in GTE units) is the colour (A >> 4 on each channel) except while the flash
    counter c runs (1 to 32, stepped here): red and green are the ramp
    (A + (0x2000 − A)·(33 − c)/32) >> 4, falling linearly from white towards A, and blue is the
    ramp on odd counts and A >> 4 on even ones."""
    ambient = ram.u16(STAGE_RECORDS + (stage + 1) * STAGE_RECORD_BYTES)
    signal = SIGNAL + 4 * player
    if ram.u32(MODE) == PRACTICE and ram.u8(signal) != 0:
        r, g, b = ram.u8(signal + 1), ram.u8(signal + 2), ram.u8(signal + 3)
    else:
        count = ram.u8(FLASH + player)
        if count != 0:
            t = s32((GTE_ONE - ambient) * (FLASH_FRAMES + 1 - count) * 0x80)
            if t < 0:
                t += 0xFFF
            ramp = ((t >> 12) + ambient) >> 4
            set_back_color(gte, ramp, ramp, ramp if count & 1 else ambient >> 4)
            count = count + 1 & 0xFF
            ram.put(FLASH + player, "B", count if count <= FLASH_FRAMES else 0)
            return
        r = g = b = ambient >> 4
    set_back_color(gte, r, g, b)


NCLIP = 0x1400006
LIGHT = 0x4A6412                 # MVMVA sf=1 lm=1, light matrix · V0
SQR = 0xA80428                   # sf=1 lm=1
CC = 0x138041C                   # sf=1 lm=1
RTPT = 0x280030


def normal_clip(gte: GTE, a: int, b: int, c: int) -> int:
    """NormalClip (0x80082BAC): the signed area of the screen triangle a, b, c."""
    gte.write_data(12, a & M32)
    gte.write_data(14, c & M32)
    gte.write_data(13, b & M32)
    gte.command(NCLIP)
    return s32(gte.read_data(24))


def color_mat_col(ram: Ram, gte: GTE, v: int, c: int, out: int, power: int) -> None:
    """ColorMatCol (0x80082BDC): light matrix · normal, squared `power` times (at least once),
    then the colour colour step with the colour word at `c`; the result goes to `out`."""
    gte.write_data(0, ram.u32(v))
    gte.write_data(1, ram.u32(v + 4))
    gte.command(LIGHT)
    n = power
    while True:
        gte.command(SQR)
        n = s32(n - 1)
        if n <= 0:
            break
    gte.write_data(6, ram.u32(c))
    gte.command(CC)
    ram.put(out, "I", gte.read_data(22))


SQRT_TABLE = 0x8004B1D8


def square_root0(ram: Ram, gte: GTE, n: int) -> int:
    """FUN_8004B174 (SquareRoot0): the GTE's leading-zero count and a 192-entry table."""
    gte.write_data(30, n & M32)
    lz = gte.read_data(31)
    if n & M32 == 0:
        return 0
    even = lz & 0xFFFE
    n = s32(n)
    shift = 0x18 - even
    v = n >> shift if shift >= 0 else s32(n << (even - 0x18 & 0x1F))
    t = ram.s16(SQRT_TABLE + 2 * (v - 0x40) & M32)
    return (t << (s32(0x1F - even) >> 1 & 0x1F) & M32) >> 12


LIGHT_SOURCE = 0x8009E988        # s32 x, y, z of the point light
LIGHT_POWER = 0x8009E994
LIGHT_MATRIX = 0x8009E948        # the light-direction matrix (row 1 at +6 is set per object)
LIGHT_SCRATCH = 0x1F800020


def light_direction(ram: Ram, gte: GTE, pos: int) -> None:
    """FUN_8003A210: points the light matrix's second row from the light source to `pos`,
    scaled by the light power / 48 over the distance (when the power is positive)."""
    power = ram.s32(LIGHT_POWER)
    if power <= 0:
        return
    d = [s32(ram.u32(pos + 4 * i) - ram.u32(LIGHT_SOURCE + 4 * i)) for i in range(3)]
    sq = [s32(c * c) for c in d]
    length = square_root0(ram, gte, sq[0] + sq[1] + sq[2] & M32)
    if length != 0:
        k = s32(_cdiv(0x4000000, length) * power)
        k = _cdiv(k, 48)
        d = [_cdiv(s32(c * k), 0x4000) for c in d]
    for i in range(3):
        ram.put(LIGHT_MATRIX + 6 + 2 * i, "H", -d[i] & 0xFFFF)


def light_local(ram: Ram, gte: GTE, m: int) -> None:
    """FUN_80037A68: the GTE light matrix becomes LIGHT_MATRIX · m."""
    mul_matrix0(ram, gte, LIGHT_MATRIX, m, LIGHT_SCRATCH)
    set_light_matrix(ram, gte, LIGHT_SCRATCH)


def _cdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def rot_trans_pers_n(ram: Ram, gte: GTE, v: int, sxy: int, z: int, n: int) -> None:
    """FUN_80036D4C: projects `n` SVECTORs three at a time (RTPT, then RTPS or a partial RTPT
    for the rest); writes the screen xy words and the depths SZ / 32 (halfwords). The vertices
    are read before the depths of their triple are written, so `z` may overlap `v`."""
    load = lambda r, a: gte.write_data(r, ram.u32(a))
    n = s32(n - 3)
    load(0, v)                                       # the branch delay slot loads VXY0 always
    if n >= 0:
        for r in range(1, 6):
            load(r, v + 4 * r)
        v += 0x18
        gte.command(RTPT)
        n -= 3
        while True:
            sxy += 0xC
            z += 6
            if n < 0:
                break
            words = [ram.u32(v + 4 * r) for r in range(6)]
            for k in range(3):
                ram.put(sxy - 0xC + 4 * k, "I", gte.read_data(12 + k))
            for r in range(6):
                gte.write_data(r, words[r])
            depths = [gte.read_data(17 + k) for k in range(3)]
            gte.command(RTPT)
            for k in range(3):
                ram.put(z - 6 + 2 * k, "H", depths[k] >> 5 & 0xFFFF)
            v += 0x18
            n -= 3
        for k in range(3):
            ram.put(sxy - 0xC + 4 * k, "I", gte.read_data(12 + k))
        for k in range(3):
            ram.put(z - 6 + 2 * k, "H", gte.read_data(17 + k) >> 5 & 0xFFFF)
    n += 2
    if n < 0:
        return
    load(0, v)
    load(1, v + 4)
    if n != 0:
        load(2, v + 8)
        load(3, v + 0xC)
        gte.command(RTPT)
        for k in range(2):
            ram.put(sxy + 4 * k, "I", gte.read_data(12 + k))
            ram.put(z + 2 * k, "H", gte.read_data(17 + k) >> 5 & 0xFFFF)
        return
    gte.command(RTPS)
    ram.put(sxy, "I", gte.read_data(14))
    ram.put(z, "H", gte.read_data(19) >> 5 & 0xFFFF)


LOCAL_SCRATCH = 0x1F800020       # FUN_80037AB0's translation (+0x14) in the scratchpad


def local_matrix(ram: Ram, gte: GTE, view: int, local: int) -> None:
    """FUN_80037AB0: GTE rotation = view · local, translation = view · local.t + view.t."""
    set_rotation(gte, ram, view)
    r = apply_rot_matrix_lv(gte, tuple(ram.s32(local + 0x14 + 4 * i) for i in range(3)))
    for i in range(3):
        ram.put(LOCAL_SCRATCH + 0x14 + 4 * i, "I", r[i] + ram.s32(view + 0x14 + 4 * i) & M32)
    set_translation(gte, tuple(ram.s32(LOCAL_SCRATCH + 0x14 + 4 * i) for i in range(3)))
    set_mul_rot_matrix(ram, gte, local)


def rot_trans_pers_psyq(ram: Ram, gte: GTE, v: int, sxy: int, p: int, flag: int) -> int:
    """RotTransPers (0x80082B7C): writes the screen xy, the depth cue IR0 and FLAG; returns SZ3 / 4."""
    gte.write_data(0, ram.u32(v))
    gte.write_data(1, ram.u32(v + 4))
    gte.command(RTPS)
    ram.put(sxy, "I", gte.read_data(14))
    ram.put(p, "I", gte.read_data(8))
    ram.put(flag, "I", gte.read_ctrl(31))
    return gte.read_data(19) >> 2
