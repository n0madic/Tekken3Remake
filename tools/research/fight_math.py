#!/usr/bin/env python3
"""Integer ports of small Tekken 3 fight routines (Japan Rev.1).

* `atan2_angle` - `Atan2Angle` (0x8002A478): 16-bit binary angle from (dz, dx).
* `relative_angles` - `FighterRelativeAngles` (0x80043D2C).
* `hit_damage` - `HitDamage` (0x80044E70) with `HitZoneScale` (0x800452D0).

Fighters are passed as dicts of named fields (see docs/research/code/fighter.md);
`tools/research/verify_fight_math.py` compares every port with the game routine in the harness.
"""

from __future__ import annotations

from dataclasses import dataclass

EXE_BASE = 0x80010000
EXE_HEADER = 0x800
ATAN_TABLE = 0x800210C8          # u8[1025]
ZONE_PERCENT = (90, 90, 90, 90, 100, 100, 120, 120, 130, 100, 100, 140, 125, 125)


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def w32(v: int) -> int:
    """Wrap to a signed 32-bit C int."""
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def div_trunc(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


@dataclass
class Exe:
    data: bytes

    def u8(self, addr: int) -> int:
        return self.data[addr - EXE_BASE + EXE_HEADER]


def atan_table(x: int, exe: Exe) -> int:
    """FUN_8004B5E0: arctangent of x/4096 in 1/1024 of a quarter turn."""
    idx = abs(div_trunc(x, 4))
    v = exe.u8(ATAN_TABLE + idx) + (idx >> 1)
    return s16(-v if x < 0 else v)


def atan2_angle(dz: int, dx: int, exe: Exe) -> int:
    """Atan2Angle (0x8002A478); only the low 16 bits of each argument are used."""
    z, x = s16(dz), s16(dx)
    a, b = abs(z) & 0xFFFF, abs(x) & 0xFFFF
    if a == b:
        s = 0x200
    elif b < a:
        s = atan_table((b << 12) // a, exe)
    else:
        s = s16(0x400 - atan_table((a << 12) // b, exe))
    u = (s * 16) & 0xFFFF
    if z < 0:
        r = u + 0x8000 if x < 0 else -s * 16 + 0x7FFF
    else:
        r = ~u if x < 0 else u
    return r & 0xFFFF


def quadrant(delta: int) -> int:
    q = (delta + 0x2000) & 0xFFFF
    if q < 0x4000:
        return 0
    if q < 0x8000:
        return 1
    return 2 if q < 0xC000 else 3


def fold(delta: int) -> int:
    delta &= 0xFFFF
    return (~delta & 0xFFFF) if delta & 0x8000 else delta


def relative_angles(f: dict, opp: dict, exe: Exe) -> None:
    """FighterRelativeAngles: update the angle fields of `f` in place (16-bit values)."""
    if f["fixedFacing"] == 0:
        target = atan2_angle(opp["rootZ"] - f["rootZ"], opp["rootX"] - f["rootX"], exe)
        f["targetDir"] = target
        f["oppToSelfDir"] = (target - 0x8000) & 0xFFFF
        f["oppHeading"] = opp["heading"] & 0xFFFF
    else:
        side = 0x4000 if f["fixedFacingSide"] == 0 else -0x4000
        f["oppToSelfDir"] = (side - 0x8000) & 0xFFFF
        f["oppHeading"] = (side - 0x8000) & 0xFFFF
        f["targetDir"] = side & 0xFFFF
    f["headingDelta"] = (f["heading"] - f["targetDir"]) & 0xFFFF
    f["facingQuadrant"] = quadrant(f["headingDelta"])
    f["oppHeadingDelta"] = (f["oppHeading"] - f["oppToSelfDir"]) & 0xFFFF
    f["oppQuadrant"] = quadrant(f["oppHeadingDelta"])
    f["relAngle"] = fold(f["headingDelta"])
    f["oppRelAngle"] = fold(f["oppHeadingDelta"])
    if f["dist"] > 0x200:
        f["aimDir"] = f["targetDir"] if f["relAngle"] < 0x4000 else (f["targetDir"] - 0x8000) & 0xFFFF
        f["oppAimDir"] = (f["oppToSelfDir"] if f["oppRelAngle"] < 0x4000
                          else (f["oppToSelfDir"] - 0x8000) & 0xFFFF)


def hit_damage(defender: dict, attacker: dict, slot: dict) -> int:
    """HitDamage: returns the value added to the slot's damage (`slot + 0x1E`)."""
    base = s16(attacker["damage"])
    if slot["guarded"]:
        return s16(div_trunc(base, 10) + 2) if slot["chip"] else 0
    if slot["close"]:
        d = base + div_trunc(base, 2)
    else:
        d = s16(div_trunc(base * ZONE_PERCENT[slot["zone"]], 100))
    if slot["counter"]:
        e = div_trunc(abs(s16(defender["damage"])) * 3, 10)
        if defender["powerTimer"] == 0 and attacker["powerTimer"] == 0:
            w = defender["moveActiveStart"]
            if w == 0 or w < defender["poseFrame"]:
                w = defender["poseFrame"] & 0xFFFF
            e = div_trunc(div_trunc(s16(e) * 3, 10) * defender["poseFrame"], s16(w))
        d = e + div_trunc(s16(d) * 12, 10)
    d = s16(d)
    if slot["airborne"]:
        d = s16(div_trunc(d * 80, 100)) if defender["juggleCount"] == 0 else s16(div_trunc(d, 2))
    return d


LAUNCH_PUSH_TABLE = 0x80019D2C


def isqrt(n: int) -> int:
    """ISqrt (0x8002A578): Newton iteration from a power-of-two estimate."""
    if n == 0:
        return 0
    guess, rest = 1, n
    while guess < rest:
        guess <<= 1
        rest >>= 1
    while True:
        prev = guess
        guess = (n // prev + prev) >> 1
        if guess >= prev:
            return prev


def launch_trajectory(f: dict, move_hold: int, pose_len: int, move_len: int, same_anim: bool) -> dict:
    """LaunchTrajectory (0x8002F2C8). Returns the fields it writes.

    `move_hold` is byte +0x1B of the new move, `pose_len` byte +0x18 of the running
    move, `move_len` byte +0x18 of the new move, `same_anim` whether both use one stream.
    """
    out: dict = {}
    hold = move_hold or pose_len
    y, ground = f["rootY"], s16(f["groundOffset"])
    dmg, jug = s16(f["lastDamage"]), s16(f["juggleCount"])
    speed = dmg + (jug + 1) * 7 + 10 + (10 if f["airKind"] == 5 else 0)
    out["airSpeed"] = s16(min(max(speed, 0), 100))
    v = w32(dmg * 4 - (w32(f["velY"] + f["hitDirY"]) >> 3) - (jug * 7 - 40))
    vc = min(v, 100)
    sq = vc * vc
    if v < -100:
        vc, sq = -100, 10000
    out["airVelY"] = s16(-vc)
    # The game divides the (possibly negative) sum as an unsigned int and keeps
    # computing with 32-bit wrap-around; high bounces rely on it.
    t = ((vc + isqrt(abs(w32(sq + w32(ground + y) * 12)))) & 0xFFFFFFFF) // 6
    e = w32(-t)
    if t == 0:
        t, e = 1, -1
    e = w32(hold + e + 1)
    if e < 1:
        e = 1
    if (f["state"] & 4) == 0 and e != 1:
        t = (t - 1 + e) & 0xFFFFFFFF
        entry = 1
    elif jug == 0:
        t = (t + 10) & 0xFFFFFFFF
        entry = w32(hold - t + 1)
        if entry < 1:
            entry = 1
    else:
        entry = e
        if same_anim and abs(s16(f["poseFrame"]) - e) < 10:
            entry = s16(f["poseFrame"]) - 10
            back = -entry
            if entry < 1:
                entry, back = 1, -1
            t = (t + e + back) & 0xFFFFFFFF
    n = w32(t + 1)
    fall = w32(n * n * 6) >> 1
    if w32(w32(vc * n - fall) - y) < ground:
        out["airVelY"] = s16(div_trunc(-w32(ground + y + fall), n))
    out["pushTable"] = LAUNCH_PUSH_TABLE
    out["pushTableFrames"] = 8
    out["entryFrame"] = s16(entry)
    out["pushDir"] = (f["targetDir"] - 0x8000) & 0xFFFF
    if f["airKind"] == 1:
        out["airVelY"] = 400
        out["entryFrame"] = 6
        out["pushFrames"] = max(move_len - 6, 0)
        out["pushSpeed"] = 0x28
    out["airFrames"] = w32(n)
    return out


def enters_before_active_end(move: dict, entry_frame: int) -> bool:
    """BranchEntersBeforeActiveEnd (0x8003127C) for the pending move `move`."""
    return move["activeStart"] != 0 and entry_frame + 1 < move["activeEnd"] <= move["length"]


def transition_remap(code: int, move: dict, entry_frame: int) -> int:
    """TransitionRemap (0x800311BC)."""
    if code == 2:
        return 0x14 if enters_before_active_end(move, entry_frame) else 2
    if 12 <= code <= 15:
        return code if move["activeStart"] else 0x0B
    if code in (20, 21):
        return code if enters_before_active_end(move, entry_frame) else 0x0B
    if code == 25:
        return 0x16 if enters_before_active_end(move, entry_frame) else 25
    return code


def move_keeps_frame(move: dict, branch_kind: int, pose_frame: int) -> bool:
    """MoveKeepsFrame (0x800312C4) for the pending move `move`."""
    if branch_kind == 3:
        return False
    if move["activeStart"] == 0:
        return True
    return move["activeStart"] <= move["length"] and pose_frame <= move["activeEnd"]


def trunc_shift12(v: int) -> int:
    """C `v / 4096` for the compiler's shift idiom (rounds toward zero)."""
    return (v + 0xFFF) >> 12 if v < 0 else v >> 12


def segment_hits_cylinder(seg: list[int], cyl: list[int], exact: bool = False) -> bool:
    """SegmentHitsCylinder (0x800479A4); `exact` computes the foot of the perpendicular without
    the game's 32-bit wrap (Gameplay fix #9).

    seg = [x0, y0, z0, x1, y1, z1]; cyl = [cx, cy, cz, radius, radius_squared].
    Bounding-box rejection, clip to the slab cy +- r, then horizontal (x, z) distance.
    """
    x0, y0, z0, x1, y1, z1 = seg
    cx, cy, cz, r, r2 = cyl
    r = s16(r)
    for a, b, c in ((x0, x1, cx), (z0, z1, cz), (y0, y1, cy)):
        if (abs(b - a) >> 1) + r < abs(c - div_trunc(a + b, 2)):
            return False
    sx, sz, ex, ez = x0, z0, x1, z1
    dx, dy, dz = x1 - x0, y1 - y0, z1 - z0
    if y0 != y1:
        lo, hi = cy - r, cy + r
        if y1 < y0:
            if hi < y0:
                t = div_trunc(w32((hi - y0) * 0x1000), dy)
                sx, sz = x0 + trunc_shift12(w32(t * dx)), z0 + trunc_shift12(w32(t * dz))
            if y1 < lo:
                t = div_trunc(w32((lo - y0) * 0x1000), dy)
                ex, ez = x0 + trunc_shift12(w32(t * dx)), z0 + trunc_shift12(w32(t * dz))
        else:
            if hi < y1:
                t = div_trunc(w32((hi - y0) * 0x1000), dy)
                ex, ez = x0 + trunc_shift12(w32(t * dx)), z0 + trunc_shift12(w32(t * dz))
            if y0 < lo:
                t = div_trunc(w32((lo - y0) * 0x1000), dy)
                sx, sz = x0 + trunc_shift12(w32(t * dx)), z0 + trunc_shift12(w32(t * dz))
    vx, vz = ex - sx, ez - sz
    px, pz = sx - cx, sz - cz
    length2 = w32(vx * vx + vz * vz)
    proj = w32(-(vx * px + vz * pz))
    if length2 == 0 or proj < 0:
        d2 = w32(px * px + pz * pz)
    elif length2 < proj:
        qx, qz = ex - cx, ez - cz
        d2 = w32(qx * qx + qz * qz)
    elif exact:
        px += div_trunc(vx * proj, length2)
        pz += div_trunc(vz * proj, length2)
        d2 = px * px + pz * pz
    else:
        # the products wrap to 32 bits in the game (long segments far from the axis)
        px += div_trunc(w32(vx * proj), length2)
        pz += div_trunc(w32(vz * proj), length2)
        d2 = w32(w32(px * px) + w32(pz * pz))
    return d2 <= r2


SIN_TABLE = 0x8001E8C4


def _trig(angle: int, base: int, exe: Exe) -> int:
    off = base + ((angle & 0xFFFFFFFF) >> 3 & 0x1FFE) - EXE_BASE + EXE_HEADER
    v = int.from_bytes(exe.data[off:off + 2], "little", signed=True)
    v = max(-0xFFF, min(0xFFF, v))
    return s16((v << 19) >> 16)


def sin_q15(angle: int, exe: Exe) -> int:
    """SinQ15 (0x8002A3E8): sin * 0x7FF8 from the 4096-entry table."""
    return _trig(angle, SIN_TABLE, exe)


def cos_q15(angle: int, exe: Exe) -> int:
    """CosQ15 (0x8002A430)."""
    return _trig(angle, SIN_TABLE + 0x800, exe)


SQRT_TABLE = 0x8004B1D8            # s16[192], PsyQ SquareRoot0 table


def sqrt_table(n: int, exe: Exe) -> int:
    """FUN_8004B174 (PsyQ SquareRoot0): GTE leading-zero count plus a 192-entry table."""
    n = w32(n)
    if n == 0:
        return 0
    lz = 32 - (n if n > 0 else ~n & 0xFFFFFFFF).bit_length()
    lz &= 0xFFFE
    shift = 0x18 - lz
    v = n >> shift if shift >= 0 else w32(n << -shift)
    off = SQRT_TABLE + (v - 0x40) * 2 - EXE_BASE + EXE_HEADER
    t = int.from_bytes(exe.data[off:off + 2], "little", signed=True)
    return ((t << (((0x1F - lz) >> 1) & 0x1F)) & 0xFFFFFFFF) >> 12


COS_TABLE = 0x8001F0C4             # s16[4096] raw 4.12 cosine (sin table precedes it)


def trig_raw(index: int, exe: Exe, table: int = SIN_TABLE) -> int:
    """Raw 4.12 entry of g_sinTable / g_cosTable (index masked to 12 bits)."""
    off = table + 2 * (index & 0xFFF) - EXE_BASE + EXE_HEADER
    return int.from_bytes(exe.data[off:off + 2], "little", signed=True)


def trunc12(v: int) -> int:
    """(v < 0 ? v + 0xFFF : v) >> 12, i.e. division by 4096 towards zero."""
    v = w32(v)
    return (v + 0xFFF if v < 0 else v) >> 12


def atan2_4096(x: int, z: int, exe: Exe) -> int:
    """FUN_8004B634: angle of (x, z) in 4096 units from the u8 atan table plus t/2."""
    def a(t: int) -> int:
        return exe.u8(ATAN_TABLE + t) + (t >> 1)
    x, z = w32(x), w32(z)
    if x == 0 and z == 0:
        return 0
    if x < 0:
        if z < 0:
            if -x < -z:
                t = div_trunc(w32(x << 10), z)
                r = 0xC00 - a(t)
            else:
                t = div_trunc(w32(z << 10), x)
                r = a(t) + 0x800
        elif -x < z:
            t = div_trunc(w32(x * -0x400), z)
            r = a(t) + 0x400
        else:
            t = div_trunc(w32(z << 10), -x)
            r = 0x800 - a(t)
    elif z < 0:
        if x < -z:
            t = div_trunc(w32(x << 10), -z)
            r = a(t) + 0xC00
        else:
            t = div_trunc(w32(z * -0x400), x)
            r = 0x1000 - a(t)
    elif x < z:
        t = div_trunc(w32(x << 10), z)
        r = 0x400 - a(t)
    else:
        t = div_trunc(w32(z << 10), x)
        r = a(t)
    return s16(r)
