#!/usr/bin/env python3
"""Integer port of the Tekken 3 pose pipeline (pose vector -> 18 local joint rotations).

A literal port of `PoseBuildMatrices` (0x8003AF64, Japan Rev.1) and its helpers:
`EulerToMatrix`, `ComposeJointOffset`, `IkLimbTarget`, `IkSolveLimb`, `IkBendMatrix`,
the libgte routines `MulMatrix` and `SquareRoot0`, and the GTE operations they use
(MVMVA with sf=1/lm=0, GPF with sf=1). Constants and tables are read from the
user's executable. `tools/research/verify_pose.py` compares it with the game's routine.

Matrices are 3x3 lists of ints in 4.12 fixed point; vectors are lists of ints.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

EXE_BASE = 0x80010000
EXE_HEADER = 0x800
SIN_TABLE = 0x8001E8C4          # g_sinTable; g_cosTable = SIN_TABLE + 0x800 bytes
SQRT_TABLE = 0x800990AC         # SquareRoot0 mantissa table
EULER_SLOTS = 0x8001A330        # matrix slot of each of the ten Euler joints
LIMB_BASIS = 0x800972D0         # constant basis for slots 2, 3 and 7
SKELETON_OFFSETS = 0x800972F0   # 4 x int[3]: chest, right/left shoulder, hips
LIMB_OFFSETS = 0x80097320       # 4 x int[3]: IK root offsets (arms, legs)
SLOT_COUNT = 18
ONE = 0x1000


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def sat16(v: int) -> int:
    """GTE IR saturation with lm=0."""
    return max(-0x8000, min(0x7FFF, v))


def asr(v: int, n: int) -> int:
    """Arithmetic shift right (Python >> already floors like MIPS sra)."""
    return v >> n


def w32(v: int) -> int:
    """Wrap to a signed 32-bit value, as C int arithmetic on the R3000 does."""
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def div_trunc(a: int, b: int) -> int:
    """C integer division (truncates toward zero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


@dataclass
class ExeTables:
    exe: bytes

    def _off(self, addr: int) -> int:
        return addr - EXE_BASE + EXE_HEADER

    def s16(self, addr: int) -> int:
        return struct.unpack_from("<h", self.exe, self._off(addr))[0]

    def s32(self, addr: int) -> int:
        return struct.unpack_from("<i", self.exe, self._off(addr))[0]

    def u8(self, addr: int) -> int:
        return self.exe[self._off(addr)]

    def sin(self, angle: int) -> int:
        return self.s16(SIN_TABLE + ((angle >> 3) & 0x1FFE))

    def cos(self, angle: int) -> int:
        return self.s16(SIN_TABLE + 0x800 + ((angle >> 3) & 0x1FFE))

    def vec3(self, addr: int) -> list[int]:
        return [self.s32(addr + 4 * i) for i in range(3)]


def mvmva(m: list[list[int]], v: list[int]) -> list[int]:
    """GTE MVMVA rt*v, sf=1, lm=0 (IR results)."""
    return [sat16(asr(m[r][0] * v[0] + m[r][1] * v[1] + m[r][2] * v[2], 12)) for r in range(3)]


def mul_matrix(m0: list[list[int]], m1: list[list[int]]) -> list[list[int]]:
    """libgte MulMatrix: m0 * m1, one column at a time through MVMVA."""
    cols = [mvmva(m0, [m1[0][c], m1[1][c], m1[2][c]]) for c in range(3)]
    return [[s16(cols[c][r]) for c in range(3)] for r in range(3)]


def square_root0(a: int, tab: ExeTables) -> int:
    if a == 0:
        return 0
    lz = 32 - a.bit_length()          # LZCS of a positive value
    lz &= ~1
    x = a >> (24 - lz) if lz < 24 else a << (lz - 24)
    mant = tab.s16(SQRT_TABLE + (x - 0x40) * 2) & 0xFFFFFFFF
    return ((mant << ((31 - lz) >> 1)) & 0xFFFFFFFF) >> 12


def gpf12(ir0: int, v: list[int]) -> list[int]:
    return [sat16(asr(ir0 * x, 12)) for x in v]


def euler_to_matrix(x: int, y: int, z: int, tab: ExeTables) -> list[list[int]]:
    """EulerToMatrix (0x8003A58C): Rz(z)*Ry(y)*Rx(x) with the game's rounding."""
    sx, cx = tab.sin(x), tab.cos(x)
    sy, cy = tab.sin(y), tab.cos(y)
    sz, cz = tab.sin(z), tab.cos(z)
    a1, a2, a3 = gpf12(sx, [cz, sz, cy])               # sx*cz, sx*sz, sx*cy
    cxcz = asr(cx * cz, 12)
    b1, b2, b3 = gpf12(sy, [a1, a2, cxcz])             # sy*sx*cz, sy*sx*sz, sy*cx*cz
    cxsz = asr(cx * sz, 12)
    c1, c2, c3 = gpf12(cy, [cz, sz, cx])               # cy*cz, cy*sz, cy*cx
    m = [[0] * 3 for _ in range(3)]
    m[2][1] = s16(a3)
    m[2][0] = s16(-sy)
    m[0][1] = s16(b1 - cxsz)
    m[1][1] = s16(cxcz + b2)
    m[0][2] = s16(a2 + b3)
    m[1][2] = s16(asr(cxsz * sy, 12) - a1)
    m[0][0] = s16(c1)
    m[1][0] = s16(c2)
    m[2][2] = s16(c3)
    return m


@dataclass
class Frame:
    rot: list[list[int]]
    t: list[int]


def compose_joint_offset(parent: Frame, local: list[list[int]], offset: list[int]) -> Frame:
    """ComposeJointOffset (0x8003B80C): R = P.R*L (MVMVA per column), t = P.t + P.R*offset."""
    rot = mul_matrix(parent.rot, local)
    d = mvmva(parent.rot, offset)
    return Frame(rot, [parent.t[i] + d[i] for i in range(3)])


def transpose(m: list[list[int]]) -> list[list[int]]:
    return [[m[c][r] for c in range(3)] for r in range(3)]


def split15(v: int) -> tuple[int, int]:
    """Split a value into (high, low) parts of 15 bits keeping the sign on both."""
    if v < 0:
        return -((-v) >> 15), -((-v) & 0x7FFF)
    return v >> 15, v & 0x7FFF


def ik_limb_target(target: list[int], root: Frame, offset: list[int]) -> list[int]:
    """IkLimbTarget (0x8003BC7C): target in the limb root frame (transposed rotation)."""
    rt = transpose(root.rot)
    parts = [split15(target[i] - root.t[i]) for i in range(3)]
    hi = [p[0] for p in parts]
    lo = [p[1] for p in parts]
    high = [sat16(rt[r][0] * hi[0] + rt[r][1] * hi[1] + rt[r][2] * hi[2]) for r in range(3)]
    low = mvmva(rt, lo)
    return [low[i] + high[i] * 8 + offset[i] for i in range(3)]


def ik_bend(m: list[int], s: int, c: int) -> None:
    """IkBendMatrix (0x8003BDDC) on a flat 9-element rotation."""
    a0, a3, a6 = m[0], m[3], m[6]
    m[0] = s16(asr(a0 * c + m[1] * s, 12))
    m[3] = s16(asr(a3 * c + m[4] * s, 12))
    m[1] = s16(asr(-a0 * s + m[1] * c, 12))
    m[4] = s16(asr(-a3 * s + m[4] * c, 12))
    m[6] = s16(asr(a6 * c + m[7] * s, 12))
    m[7] = s16(asr(-a6 * s + m[7] * c, 12))


def trunc12(v: int) -> int:
    return (v + 0xFFF) >> 12 if v < 0 else v >> 12


def ik_solve_limb(target: list[int], swivel: int, is_arm: bool, tab: ExeTables,
                  upper: list[int], lower: list[int]) -> int:
    """IkSolveLimb (0x8003BEFC): aim rotation (upper) and bend (lower), flat 9-element lists.

    All products wrap to 32 bits like the original C code; for arm targets just above
    the minimum reach `inv * 0x9204` overflows, and the game relies on that result.
    """
    x, y, z = target
    sq = w32(x * x + y * y + z * z)
    if sq == 0:
        return -1
    length = square_root0(sq, tab)
    inv = div_trunc(0x400000, length)
    ux = asr(w32(x * inv), 10)
    uy = asr(w32(y * inv), 10)
    uz = asr(w32(z * inv), 10)
    k = ux + ONE
    if k == 0:
        k = -0x800
        a = asr(w32(y * inv), 11)
        e = -ONE
    else:
        if k < 0x2000:
            k = div_trunc(-0x1000000, k)
            a = asr(w32(k * uy), 12)
        else:
            k = -0x800
            a = asr(-uy, 1)
        e = ONE
    b = asr(w32(a * uy), 12) + e
    k = asr(w32(k * uz), 12)
    upper[0], upper[3], upper[6] = s16(ux), s16(uy), s16(uz)
    c, s = tab.cos(swivel), tab.sin(swivel)
    p = asr(w32(a * (e + ux)), 12)
    q = asr(w32(k * (e + ux)), 12)
    r = asr(w32(k * uy), 12)
    w = asr(w32(a * uz), 12)
    v = asr(w32(k * uz), 12) + ONE
    upper[1] = s16(asr(w32(c * p + s * q), 12))
    upper[4] = s16(asr(w32(c * b + s * r), 12))
    upper[7] = s16(asr(w32(c * w + s * v), 12))
    upper[2] = s16(asr(w32(-s * p + c * q), 12))
    upper[5] = s16(asr(w32(-s * b + c * r), 12))
    upper[8] = s16(asr(w32(-s * w + c * v), 12))
    if is_arm:
        if length > 0x215:
            lower[:] = [ONE, 0, 0, 0, ONE, 0, 0, 0, ONE]
            return 0
        if length < 0x47:
            return 1
        d = asr(w32(inv * 0x9204), 11)
        cos_a = asr(w32((length * 0x800 + d) * 0xD9), 16)
        cos_b = asr(w32((length * 0x800 - d) * 0x11A), 16)
    else:
        if length > 0x37B:
            lower[:] = [ONE, 0, 0, 0, ONE, 0, 0, 0, ONE]
            return 0
        if length < 3:
            return 1
        d = asr(w32(inv * 0x6F8), 11)
        cos_a = asr(w32((length * 0x800 + d) * 0x92), 16)
        cos_b = asr(w32((length * 0x800 - d) * 0x93), 16)
    if cos_a > ONE:
        cos_a, sin_a = ONE, 0
    elif cos_a < -ONE:
        cos_a, sin_a = -ONE, 0
    else:
        sin_a = square_root0(0x1000000 - cos_a * cos_a, tab)
        if not is_arm:
            sin_a = -sin_a
    ik_bend(upper, s16(sin_a), cos_a)
    if cos_b > ONE:
        cos_b, sin_b = ONE, 0
    elif cos_b < -ONE:
        cos_b, sin_b = -ONE, 0
    else:
        sin_b = asr(w32(sin_a * (-0x14D4 if is_arm else -0x1012)), 12)
    diag = s16(trunc12(w32(cos_a * cos_b + sin_a * sin_b)))
    off = s16(trunc12(w32(-sin_a * cos_b + cos_a * sin_b)))
    lower[:] = [diag, s16(-off), 0, off, diag, 0, 0, 0, ONE]
    return 0


def flat(m: list[list[int]]) -> list[int]:
    return [m[r][c] for r in range(3) for c in range(3)]


def unflat(v: list[int]) -> list[list[int]]:
    return [v[0:3], v[3:6], v[6:9]]


def pose_build_matrices(pose: list[int], slots: list[list[int]], tab: ExeTables) -> None:
    """PoseBuildMatrices: fill the rotation (9 values) of each of the 18 slots.

    `slots` holds 18 flat rotations; entries not written by the game keep their values.
    """
    for j in range(10):
        m = euler_to_matrix(pose[19 + 3 * j], pose[20 + 3 * j], pose[21 + 3 * j], tab)
        slots[tab.u8(EULER_SLOTS + j)] = flat(m)
    basis = [[tab.s16(LIMB_BASIS + 2 * (3 * r + c)) for c in range(3)] for r in range(3)]
    for s in (2, 3, 7):
        slots[s] = flat(mul_matrix(unflat(slots[s]), basis))
    root = Frame(unflat(slots[0]), [pose[0], pose[1], pose[2]])
    chest = compose_joint_offset(root, unflat(slots[1]), tab.vec3(SKELETON_OFFSETS))
    right = compose_joint_offset(chest, unflat(slots[3]), tab.vec3(SKELETON_OFFSETS + 12))
    left = compose_joint_offset(chest, unflat(slots[7]), tab.vec3(SKELETON_OFFSETS + 24))
    hips = compose_joint_offset(root, unflat(slots[11]), tab.vec3(SKELETON_OFFSETS + 36))
    limbs = [
        (right, 3, LIMB_OFFSETS, 15, 4, 5, True),
        (left, 6, LIMB_OFFSETS + 12, 16, 8, 9, True),
        (hips, 9, LIMB_OFFSETS + 24, 17, 12, 13, False),
        (hips, 12, LIMB_OFFSETS + 36, 18, 15, 16, False),
    ]
    targets = [ik_limb_target(pose[c:c + 3], fr, tab.vec3(off)) for fr, c, off, *_ in limbs]
    for (fr, c, off, sw, up, lo, arm), tgt in zip(limbs, targets):
        ik_solve_limb(tgt, pose[sw], arm, tab, slots[up], slots[lo])
