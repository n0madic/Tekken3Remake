#!/usr/bin/env python3
"""Integer ports of the fight camera (Japan Rev.1), working on guest memory like fight_sim.

* `camera_frame_fighters` — CameraFrameFighters (0x800650F8): places camera source `src`
  so that both fighters' target points fit the screen, with the game's smoothing state.
* `camera_track_fighters` — CameraTrackFighters (0x80064944): the two target points.
* `camera_blend` — CameraBlend (0x80062E5C): mixes the weighted sources into source 3 and the
  view (`g_camera`, GTE H); pairs orbit a shared look point (`camera_blend_pair`, 0x80064458).
* `camera_yaw_spring` — CameraYawSpring (0x80064AF8): the yaw that keeps the fighters' axis
  across the screen, with the delayed swing of source 0 and its roll target.

In mode 7 (Tekken Ball) the ball position from `volley.ovl` `FUN_800B4948` is a third target.
`tools/research/verify_camera_sim.py` compares them with the game in the CPU harness.
"""

from __future__ import annotations

import fight_math
from fight_math import div_trunc, isqrt, s16, trunc12, w32
from fight_sim import GAME_MODE, Fighter, Ram, exe

SOURCES = 0x800A0650               # 6 ints per camera source: x, y, z, pitch, yaw (18-bit angles), H
OUTPUT_SOURCE = 3                  # CameraBlend result
WEIGHTS = 0x800A9140               # s16 weight per source 0..4 (4096 = 1), previous frame at +0xA
H_MIN, H_MAX = 0x800A919E, 0x800A91A0   # s16 clamp for the projection distance
VIEW = 0x800A8A88                  # g_camera: +0 pitch >> 6, +4 yaw >> 6, +0x14 x, y, z
TARGETS = 0x800AE170               # 2 x (x, y, z, screenX) ints, previous copy at +0x30
PROJECTION = 0x800A919C            # s16 GTE projection distance H
STATE = 0x800A06D0                 # per source 0x30 bytes (layout below); only source 0 swings
SMOOTH = STATE + 0x24              # +0 depth step, +4 depth, +8 lateral
# STATE offsets: +0 s16 swing phase, +2 s16 moved flag (MOVED), +4/+6 s16 cleared, +8 s16 swing
# frames, +0xC swing angle, +0x10 swing speed, +0x14 roll, +0x18 roll target, +0x1C roll step,
# +0x20 last axis error.
HEIGHT_TERM = 0x80098754           # smoothed height term of source 1
MOVED = STATE + 2                 # s16: source 0 moved more than ~31 units this frame
MARGIN = 0x96                      # 150-unit screen margins
MIN_DISTANCE = 800
SPREAD_LIMIT = 0x119
FIGHTER_DISTANCE = 0x800AFF04      # g_fighterDistance
SWING_CAP = 0xDDD0                 # swing angle limit (18-bit units x 64)
SWING_KICK = 0x600
# Move flag byte +0x24 values (' ( ) *) that narrow the swing limit to cap * n / 256.
SWING_LIMITS = ((0x27, 0x200), (0x28, 0x180), (0x29, 0x80), (0x2A, 0x40))


def _trig(index: int) -> tuple[int, int]:
    return (fight_math.trig_raw(index, exe(), fight_math.SIN_TABLE),
            fight_math.trig_raw(index, exe(), fight_math.COS_TABLE))


def _idx18(angle: int) -> int:
    """(angle [+0x3F if negative]) >> 5 & 0x1FFE, as a 4096-entry index."""
    angle = w32(angle)
    if angle < 0:
        angle += 0x3F
    return ((angle >> 5) & 0x1FFE) >> 1


def _s18(v: int) -> int:
    v &= 0x3FFFF
    return v - 0x40000 if v & 0x20000 else v


def _div(a: int, b: int) -> int:
    """C division; a zero divisor gives the R3000 quotient (-1 or 1) since the game does not trap."""
    if b == 0:
        return -1 if w32(a) >= 0 else 1
    return div_trunc(a, b)


def _div8(v: int) -> int:
    return (v + 7 if v < 0 else v) >> 3


def camera_frame_fighters(ram: Ram, pitch: int, yaw: int, reset: int, distance: int, src: int,
                          ball: tuple[int, int, int] | None = None) -> None:
    """`ball` is the (x, y, z) that FUN_800B4948 returns; used only in mode 7."""
    pitch, yaw, distance = w32(pitch), w32(yaw), w32(distance)
    h = ram.s16(PROJECTION)
    if distance < 0x321:
        distance = MIN_DISTANCE
    rec = SOURCES + 24 * src
    cam_x, cam_y, cam_z, cam_p, cam_yw, cam_r = (ram.s32(rec + 4 * i) for i in range(6))
    sp, cp = _trig(_idx18(-pitch))
    sy, cy = _trig(_idx18(-yaw))
    t = [[ram.s32(TARGETS + 16 * k + 4 * i) for i in range(4)] for k in range(2)]
    mx = _div(t[0][0] + t[1][0], 2)
    mz = _div(t[0][2] + t[1][2], 2)
    if reset == 0:
        s_, c_ = _trig(_idx18(_s18(yaw - cam_yw)))
        dx, dz = w32(cam_x - mx), w32(cam_z - mz)
        ox, oz = trunc12(c_ * dx - s_ * dz), trunc12(s_ * dx + c_ * dz)
    else:
        s_, c_ = _trig(_idx18(yaw + 0x30000))
        ox, oz = trunc12(distance * c_), trunc12(distance * s_)
    mx, mz = w32(mx + ox), w32(mz + oz)
    u, v1, z, depth = [0, 0], [0, 0], [0, 0], [0, 0, 0]
    for k in range(2):
        tx, tz, ty = w32(t[k][0] - mx), w32(t[k][2] - mz), w32(t[k][1] - cam_y)
        a1 = trunc12(sy * tx + cy * tz)
        u[k] = trunc12(cy * tx - sy * tz)
        z[k] = trunc12(cp * a1 - sp * ty)
        v1[k] = trunc12(sp * a1 + cp * ty)
        depth[k] = a1
    ball_view = None
    if ram.s32(GAME_MODE) == 7:
        bx, by, bz = ball
        tx, tz, ty = w32(bx - mx), w32(bz - mz), w32(by - cam_y)
        a1 = trunc12(sy * tx + cy * tz)
        # The ball keeps its raw depth: it is not moved by the distance correction below.
        ball_view = (trunc12(cy * tx - sy * tz), trunc12(cp * a1 - sp * ty), trunc12(sp * a1 + cp * ty), by)
    m = _div(depth[0] + depth[1], 2)
    up = w32(-0x1C2 - cam_y)
    e10 = trunc12(cp * m - sp * up)
    e2 = w32(sp * m + cp * up)
    e2 = trunc12(e2)
    d = distance - e10
    depth[2] = e10 + d
    back = -d
    z[0], z[1] = z[0] + d, z[1] + d
    lateral = 0
    smooth = SMOOTH + 0x30 * src
    if ball_view:
        bu, bzz = ball_view[0], ball_view[1]
        # A ball beyond the outer fighter replaces it, with a further 150-unit margin.
        lo_k, hi_k = (0, 1) if u[0] < u[1] else (1, 0)
        if bu < u[lo_k]:
            u[lo_k], z[lo_k] = bu - MARGIN, bzz
        elif u[hi_k] < bu:
            u[hi_k], z[hi_k] = bu + MARGIN, bzz
    right_first = u[1] <= u[0]
    if right_first:
        left_px = _div(w32((u[1] - MARGIN) * h), z[1])
        edge = u[0] + MARGIN
        u[1] -= MARGIN
        u[0] = edge
        zr = z[0]
        lo, hi = 1, 0
    else:
        left_px = _div(w32((u[0] - MARGIN) * h), z[0])
        edge = u[1] + MARGIN
        u[0] -= MARGIN
        u[1] = edge
        zr = z[1]
        lo, hi = 0, 1
    right_px = _div(w32(edge * h), zr)

    def settle(s: int) -> int:
        if s < 0:
            return s - ((s + 0x1F) >> 5)
        return s - (s >> 3) if s > 0 else 0

    if right_px - left_px < SPREAD_LIMIT:
        centred = False
        if reset == 0:
            a7 = _div(z[hi] * 0x30, h)
            a13 = _div(z[lo] * -0x30, h)
            if a7 - (u[hi] - u[lo]) < a13:
                centred = True
            else:
                a13 = u[lo] - a13
                if left_px > -0x31:
                    if right_px >= 0x31:
                        lateral += _div8(u[hi] - a7)
                else:
                    lateral += _div8(a13)
        else:
            centred = True
        if centred:
            lateral = u[lo] + _div(w32((u[hi] - u[lo]) * z[lo]), z[lo] + z[hi])
            lateral = _div8(lateral)
        if reset != 0 and centred:
            ram.put(smooth + 8, "i", 0)
        else:
            s = settle(ram.s32(smooth + 8))
            ram.put(smooth + 8, "i", s)
            back += s
            depth[2] -= s
            z[0] -= s
            z[1] -= s
    else:
        e10b = _div(w32(h * (u[hi] - u[lo]) + (z[hi] - z[lo]) * -0x8C), 0x118)
        a13 = z[lo] - e10b
        if reset == 0:
            s = ram.s32(smooth + 8)
            if s < a13:
                a13 = s + ((a13 - s) >> 5)
            else:
                a13 = s - _div8(s - a13)
        ram.put(smooth + 8, "i", a13)
        back += a13
        lateral = _div8(u[lo] - _div(w32(e10b * -0x8C), h))
        z[0] -= a13
        depth[2] -= a13
        z[1] -= a13
    top = 100
    ty_world = ram.s32(TARGETS + 16 + 4)
    top_v, top_z = v1[1], z[1]
    if _div(w32(v1[0] * h), z[0]) < _div(w32(v1[1] * h), z[1]):
        top_v, top_z = v1[0], z[0]
        ty_world = ram.s32(TARGETS + 4)
    height = trunc12(ty_world * cp)
    if ball_view and ball_view[2] < top_v:
        top_v, top_z, height = ball_view[2], ball_view[1], trunc12(w32(ball_view[3] * cp))
    if src == 1 and pitch < 0:
        top = 0x80
    lift = 0
    g = ram.s32(HEIGHT_TERM)
    new_g = g
    if src == 1 and pitch > 0:
        if height > -1001:
            lift = _div(w32((height + 1000) * 0x170), 0x280)
        new_g = lift
        if reset == 0:
            if g < lift and lift - g > 0x1C:
                lift = g + 0x1C
            elif lift < g and g - lift > 0x1C:
                lift = g - 0x1C
            new_g = lift
    ram.put(HEIGHT_TERM, "i", new_g)
    scale = trunc12(cp * (top - _div(w32(h * 0x1C2), distance)))
    want = _div(w32(w32((top_z - depth[2]) * -0x70) - w32(h * (top_v - e2))), scale + 0x70) - depth[2]
    if want < 0:
        want = 0
    if reset == 0:
        cur = ram.s32(smooth + 4)
        if want < cur:
            step = cur - want
            big = step * 16
            if step > 0x4B0:
                step, big = 0x4B0, 0x4B00
            q = w32((big - step) * 8)
            q = (q + 0x7F if q < 0 else q) >> 7
            ram.put(smooth, "i", q - step)
            want = cur + (q - step)
        elif want > cur:
            step = min(want - cur, 800)
            ram.put(smooth, "i", _div8(step))
            want = cur + _div8(step)
    else:
        want = 0
        ram.put(smooth, "i", 0)
    ram.put(smooth + 4, "i", want)
    if want > 0:
        back -= want
        depth[2] += want
    raw = w32(want * cp)
    vertical_scale = scale
    if src == 0:
        q = _div(w32(trunc12(raw) * h), distance)
        vertical_scale += (q + 0xF if q < 0 else q) >> 4
    vertical = e2 - _div(w32(vertical_scale * depth[2]), h) + lift
    sp2, cp2 = _trig(_idx18(pitch))
    sy2, cy2 = _trig(_idx18(yaw))
    r2 = trunc12(back * cp2 - vertical * sp2)
    r12 = trunc12(back * sp2 + vertical * cp2)
    xa = w32(lateral * cy2 + r2 * -sy2)
    za = w32(lateral * sy2 + r2 * cy2)
    new_x, new_z = w32(mx + trunc12(xa)), w32(mz + trunc12(za))
    if reset == 0:
        dx, dz = w32(new_x - cam_x), w32(new_z - cam_z)
        if src == 0:
            ram.put(MOVED, "h", 0 if w32(dx * dx + dz * dz) < 0x3E9 else 1)
        cam_x, cam_z = new_x, new_z
        cam_p = w32(cam_p + _s18(pitch - cam_p))
        cam_yw = w32(cam_yw + _s18(yaw - cam_yw))
    else:
        cam_x, cam_z, cam_p, cam_yw = new_x, new_z, pitch, yaw
    cam_y = w32(cam_y + r12)
    for i, v in enumerate((cam_x, cam_y, cam_z, cam_p, cam_yw, cam_r)):
        ram.put(rec + 4 * i, "I", v)


def camera_track_fighters(ram: Ram, f0: Fighter, f1: Fighter, force_root: int) -> None:
    if f0.throwState or f1.throwState:
        force_root = 1
    skip_side = ram.s16(0x800A91A8)
    for k, f in enumerate((f0, f1)):
        base = TARGETS + 16 * k
        for i in range(4):
            ram.put(base + 0x30 + 4 * i, "I", ram.u32(base + 4 * i))
        if skip_side != k or f.poseFrame & 1:
            if not (ram.u32(f.poseMove + 0x24) >> 29) & 1 and f.throwState == 0 and force_root == 0:
                ram.put(base, "i", f.posX)
                ram.put(base + 8, "i", f.posZ)
            else:
                ram.put(base, "i", f.rootX)
                ram.put(base + 8, "i", f.rootZ)
            ram.put(base + 12, "i", f.at(0x1278, "h"))
            y = w32(f.at(0x994, "i") - 0x122)
            if f.curSlot == 2 and f.bankType == 4:
                y = -0x6B8
            ram.put(base + 4, "i", y)
    t0x, t0z, t1x, t1z = (ram.s32(TARGETS + o) for o in (0, 8, 16, 24))
    if t0x == t1x and t0z == t1z:
        ram.put(TARGETS + 16, "i", t0x + 1)
        ram.put(TARGETS + 24, "i", t0z + 1)
        ram.put(TARGETS, "i", t0x - 1)
        ram.put(TARGETS + 8, "i", t0z - 1)


def _half(v: int) -> int:
    """C `v / 2` rounding toward zero."""
    return (v + (1 if v < 0 else 0)) >> 1


def _sar(v: int, n: int) -> int:
    """Arithmetic shift rounding toward zero."""
    return (v + (1 << n) - 1 if v < 0 else v) >> n


def camera_yaw_spring(ram: Ram, f0: Fighter, f1: Fighter, reset: int, src: int) -> tuple[int, int]:
    """Returns (return value, yaw written through the out pointer)."""
    st = STATE + 0x30 * src
    rec = SOURCES + 24 * src
    cam_yaw = ram.s32(rec + 16)
    t = [ram.s32(TARGETS + o) for o in (0, 8, 16, 24)]
    axis = s16(fight_math.atan2_4096(t[2] - t[0], t[3] - t[1], exe()))
    axis &= 0xFFFFFFFF
    if f1.at(0x1278, "h") <= f0.at(0x1278, "h"):
        axis = (axis + 0x800) & 0xFFF
    err = _s18(w32(axis * 0x40 - cam_yaw))
    sign = (err > 0) - (err < 0)
    err = abs(err)
    if reset:
        for off in (0xC, 0x10, 0x18, 0x14, 0x1C):
            ram.put(st + off, "i", 0)
        ram.put(st + 4, "h", 0)
        ram.put(st + 6, "h", 0)
        return reset, w32(axis * 0x40)
    if src != 0 or err > 0x1AAAA or ram.s32(FIGHTER_DISTANCE) < 200:
        ram.put(st + 4, "h", 0)
        ram.put(st + 6, "h", 0)
        return 0, cam_yaw
    phase, frames = ram.s16(st), ram.s16(st + 8)
    angle, speed = ram.s32(st + 0xC), ram.s32(st + 0x10)
    offset = 0
    if phase == 0:
        frames = 0 if err < 0xE38 else s16(frames + 1)
        if frames > 0:
            phase, frames = 1, 0
            speed = w32(speed + sign * SWING_KICK)
    elif phase == 1:
        if err < 0x38E4:
            angle = w32(angle - _sar(w32(angle * 0xE), 7))
            speed = w32(speed - _half(speed) + sign * 0x300)
            if err < 0xE39:
                speed = w32(speed - _half(speed))
                frames = s16(frames + 1)
                if frames >= 0x20:
                    angle, phase, frames = 0, 0, 0
            else:
                frames = 0
        else:
            speed = w32(speed + sign * SWING_KICK)
        angle = w32(angle + speed)
        flags = (ram.u8(f0.poseMove + 0x24), ram.u8(f1.poseMove + 0x24))
        limit = next((n for code, n in SWING_LIMITS if code in flags), -1)
        if limit < 1:
            if angle > SWING_CAP:
                angle, speed = SWING_CAP, w32(speed - SWING_KICK)
            elif angle < -SWING_CAP:
                angle, speed = -SWING_CAP, w32(speed + SWING_KICK)
        else:
            hi, lo = _sar(limit * SWING_CAP, 8), _sar(-limit * SWING_CAP, 8)
            if hi < angle:
                angle, speed = hi, w32(speed - SWING_KICK)
            elif angle < lo:
                angle, speed = lo, w32(speed + SWING_KICK)
        offset = _sar(angle, 6)
    ram.put(st, "h", phase)
    ram.put(st + 8, "h", frames)
    ram.put(st + 0xC, "i", angle)
    ram.put(st + 0x10, "i", speed)
    if err < 0x38E3:
        ram.put(st + 0x18, "i", 0)
    else:
        q = _sar(div_trunc(w32((err - 0x38E3) * 0x1000), 0xC71D), 8)
        ram.put(st + 0x18, "i", trunc12(w32(_trig(q)[0] * 0x44440)))
    if ram.s16(STATE + 2) == 0:
        ram.put(STATE + 0x1C, "i", 0)
    else:
        diff = w32(ram.s32(STATE + 0x18) - ram.s32(STATE + 0x14))
        step = max(-0x100, min(0x100, _sar(diff, 4)))
        ram.put(STATE + 0x1C, "i", step)
        ram.put(STATE + 0x14, "i", w32(ram.s32(STATE + 0x14) + step))
    ram.put(STATE + 0x20, "i", err)
    return 0, w32(cam_yaw + offset)


def _sar6(v: int) -> int:
    return (v + 0x3F if v < 0 else v) >> 6


def _source(ram: Ram, i: int) -> list[int]:
    return [ram.s32(SOURCES + 24 * i + 4 * k) for k in range(6)]


def _projection(ram: Ram, h: int) -> int:
    """FUN_80063F4C: GsSetProjection(h) clamped to [H_MIN, H_MAX]; returns the GTE H value."""
    lo, hi = ram.s16(H_MIN), ram.s16(H_MAX)
    return lo if h < lo else hi if hi < h else h


def camera_use_source(ram: Ram, i: int) -> int:
    """FUN_80064368: copies source i to source 3 and the view; returns the GTE H value."""
    rec = _source(ram, i)
    for k, v in enumerate(rec):
        ram.put(SOURCES + 24 * OUTPUT_SOURCE + 4 * k, "I", v)
    for k in range(3):
        ram.put(VIEW + 0x14 + 4 * k, "I", rec[k])
    ram.put(VIEW, "i", _sar6(rec[3]))
    ram.put(VIEW + 4, "i", _sar6(rec[4]))
    return _projection(ram, rec[5])


def camera_look_point(ram: Ram, rec: list[int]) -> tuple[int, list[int]]:
    """FUN_80063FE8: mean distance to the two targets and the point that far along the view."""
    x, y, z, pitch, yaw = rec[:5]
    sp, cp = _trig(_idx18(pitch))
    sy, cy = _trig(_idx18(w32(yaw + 0x10000)))
    t = [ram.s32(TARGETS + o) for o in (0, 4, 8, 16, 20)]
    zz = w32((t[2] - z) * (t[2] - z))   # both distances use target 0's z (as in the game)
    d0 = isqrt(w32(w32((t[0] - x) * (t[0] - x)) + w32((t[1] - y) * (t[1] - y)) + zz) & 0xFFFFFFFF)
    d1 = isqrt(w32(w32((t[3] - x) * (t[3] - x)) + w32((t[4] - y) * (t[4] - y)) + zz) & 0xFFFFFFFF)
    r = ((d0 + d1) & 0xFFFFFFFF) >> 1
    look = [w32(x + trunc12(w32(trunc12(w32(r * cy)) * cp))),
            w32(y + trunc12(w32(r * sp))),
            w32(z + trunc12(w32(trunc12(w32(r * sy)) * cp)))]
    return r, look


def camera_blend_pair(ram: Ram, a: list[int], b: list[int], w: int) -> int:
    """FUN_80064458: blends two sources (weight w of `a`) around their look points into
    source 3 and the view; returns the GTE H value. A non-positive blended H leaves source 3's H
    as uninitialised stack in the game; the port keeps the old value."""
    iw = 0x1000 - w
    ra, la = camera_look_point(ram, a)
    rb, lb = camera_look_point(ram, b)
    r = trunc12(w32(ra * w + rb * iw))
    look = [trunc12(w32(la[k] * w + lb[k] * iw)) for k in range(3)]
    pitch = w32(a[3] + trunc12(w32(_s18(b[3] - a[3]) * iw)))
    yaw = w32(a[4] + trunc12(w32(_s18(b[4] - a[4]) * iw)))
    sp, cp = _trig(_idx18(pitch))
    ys, yc = _trig(_sar6(yaw) + 0x400)
    pos = [w32(look[0] - trunc12(w32(trunc12(w32(r * yc)) * cp))),
           w32(look[1] - trunc12(w32(r * sp))),
           w32(look[2] - trunc12(w32(trunc12(w32(r * ys)) * cp)))]
    h = trunc12(w32(a[5] * w + b[5] * iw))
    dx, dy, dz = w32(look[0] - pos[0]), w32(look[1] - pos[1]), w32(look[2] - pos[2])
    flat = isqrt(w32(w32(dx * dx) + w32(dz * dz)) & 0xFFFFFFFF)
    out = SOURCES + 24 * OUTPUT_SOURCE
    new = pos + [s16(fight_math.atan2_4096(flat, dy, exe())) << 6,
                 s16(fight_math.atan2_4096(dz, -dx, exe())) << 6]
    if h > 0:
        new.append(h)
    for k, v in enumerate(new):
        ram.put(out + 4 * k, "I", w32(v))
    camera_use_source(ram, OUTPUT_SOURCE)
    return _projection(ram, h)


def camera_blend(ram: Ram) -> int | None:
    """CameraBlend; returns the GTE H value (None for the CameraReset fallback, not ported)."""
    weights = [ram.s16(WEIGHTS + 2 * i) for i in range(5)]
    mask = sum(1 << i for i, v in enumerate(weights) if v > 0)
    w0 = weights[0]
    if mask in (1, 2, 4, 0x10):
        h = camera_use_source(ram, mask.bit_length() - 1)
    elif mask in (3, 5):
        h = camera_blend_pair(ram, _source(ram, 0), _source(ram, 1 if mask == 3 else 2), w0)
    elif mask == 0x11:
        e = _trig(((w0 - (w0 >> 31)) >> 1) - 0x400)[0]   # eased: (sin(w0/2 - 90deg) / 2) + 0x800
        h = camera_blend_pair(ram, _source(ram, 0), _source(ram, 4), _half(e) + 0x800)
    else:
        h = None
    for i in range(5):
        ram.put(WEIGHTS + 0xA + 2 * i, "h", weights[i])
    return h
