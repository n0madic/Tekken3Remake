"""The arcade stages' animated props (World ver. E1; docs/research/arcade/stages.md#props).

Stage 3 turns its carousel (FUN_801E59FC at the round's start, FUN_801E5AD0 every frame). Stage 11
flies a helicopter around the arena (FUN_801E3DE0, then FUN_801E3D0C every frame it is shown) in
one of four modes chosen at the round's start: 0 hovers and, when the camera has turned far,
circles to stay in view; 1–3 fly scripted figures.

The state is the game's: SVECTOR angles (`angles[prop]`, 4096 units) and positions
(`positions[prop]`, scene units, y down) of the props, and the helicopter's variables at
0x8021F9F8–0x8021FA70. Every variable is a 16-bit word; `step` reads them as the code does.

Arcade bug #63 (game-bugs.md): FUN_801E40C0 runs the camera-following manoeuvre
(FUN_801E42DC, FUN_801E4674) for mode 2, but only mode 0 arms it, so it never runs. The port
runs it for mode 0, as meant (`MANOEUVRE_MODE`); verify_arcade_props.py patches the game the
same way.
"""

from __future__ import annotations

from dataclasses import dataclass, field

CAROUSEL_TURN = -5            # FUN_801E5AD0: per frame, 0x88 frames, then back
CAROUSEL_FRAMES = 0x88
CAROUSEL_START = 0x955
WARMUP = 0x78                 # frames before the helicopter watches the camera
ROTOR = 0x29F                 # rotor turn per frame (main −, tail +)
RADIUS = 0x1068               # orbit radius (scene units)
NEAR_TURN = 0x17C             # camera turns that start the manoeuvres
FAR_TURN = 0x352
NEAR_PROFILE = (7, 507, 460, 11)    # 0x802045EC: top step, orbit, brake distance, turn rate
FAR_PROFILE = (15, 1016, 793, 16)   # 0x802045F4
MANOEUVRE_MODE = 0            # the game tests 2 (bug #63)

# Mode-selecting button bits of the first player's held buttons at the round's start
# (FUN_801E3DE0, the arcade's input word); none: the low bits of a counter.
MODE_BUTTONS = ((0x200, 0), (0x100, 1), (0x40, 2), (0x20, 3))


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def u16(v: int) -> int:
    return v & 0xFFFF


@dataclass
class Props:
    angles: list[list[int]] = field(default_factory=lambda: [[0, 0, 0] for _ in range(4)])
    positions: list[list[int]] = field(default_factory=lambda: [[0, 0, 0] for _ in range(4)])
    profile: tuple[int, int, int, int] = (0, 0, 0, 0)   # f9f8 (a pointer in the game)
    accelerate: int = 0       # f9fc
    reverse: int = 0          # f9fe
    bob_dir: int = 0          # fa00
    yaw_timer: int = 0        # fa04
    yaw_dir: int = 0          # fa08
    tilt_timer: int = 0       # fa0c
    tilt_dir: int = 0         # fa10
    fa14: int = 0
    phase_timer: int = 0      # fa18
    flags: int = 0            # fa1c
    start_yaw: int = 0        # fa20
    orbit: int = 0            # fa24
    orbit_target: int = 0     # fa28
    turn_left: int = 0        # fa2c
    bank: int = 0             # fa30
    speed: int = 0            # fa34
    step_size: int = 0        # fa38
    turn_step: int = 0        # fa3c
    turn_rate: int = 0        # fa40
    mode: int = 0             # fa44
    warmup: int = 0           # fa48
    state: int = 0            # fa4c
    timer: int = 0            # fa50
    camera_ref: int = 0       # fa54
    camera_last: int = 0      # fa58
    slide_x: int = 0          # fa5c
    slide_z: int = 0          # fa60
    axis: int = 0             # fa64
    slide: int = 0            # fa68
    bob_timer: int = 0        # fa6c
    radius: int = 0           # fa70
    carousel_timer: int = 0   # fa74

    FIELDS = ("accelerate", "reverse", "bob_dir", "yaw_timer", "yaw_dir", "tilt_timer", "tilt_dir",
              "fa14", "phase_timer", "flags", "start_yaw", "orbit", "orbit_target", "turn_left",
              "bank", "speed", "step_size", "turn_step", "turn_rate", "mode", "warmup", "state",
              "timer", "camera_ref", "camera_last", "slide_x", "slide_z", "axis", "slide",
              "bob_timer", "radius", "carousel_timer")


# ---- stage 3 ----

def carousel_start(p: Props) -> None:
    """FUN_801E59FC."""
    for k in range(3):
        p.positions[k] = [0, -300, 0xC1C]
    p.angles[0] = [0, CAROUSEL_START, 0]
    p.angles[1] = [0, 0, 0]
    p.angles[2] = [0, 0x800, 0]
    p.angles[3] = [0, 0x800, 0]
    p.positions[3] = [0, 0, 0]
    p.carousel_timer = 0


def carousel_step(p: Props) -> None:
    """FUN_801E5AD0."""
    p.angles[0][1] = s16(p.angles[0][1] + CAROUSEL_TURN)
    p.carousel_timer = s16(p.carousel_timer + 1)
    if p.carousel_timer == CAROUSEL_FRAMES:
        p.angles[0][1] = CAROUSEL_START
        p.carousel_timer = 0


# ---- stage 11 ----

def helicopter_start(p: Props, buttons: int, counter: int) -> None:
    """FUN_801E3DE0 at the round's start: `buttons` the first player's held buttons, `counter`
    0x8021FD58. The variables it does not set keep the previous round's values."""
    p.angles[0] = [s16(0xFF61), 0x71C, 0]
    p.angles[1] = [0, 0, 0]
    p.angles[2] = [0, 0, 0]
    p.positions[0] = [0, s16(0xFE70), RADIUS]
    p.positions[1] = [0, s16(0xFED4), 0]
    p.positions[2] = [0, 0x118, s16(0xFB32)]
    p.yaw_timer = 0x80
    p.fa14 = s16(0xFFFE)
    p.flags = 0
    p.state = 0
    p.bob_dir = -1
    p.bob_timer = 0x20
    p.yaw_dir = -1
    p.tilt_timer = 0x20
    p.tilt_dir = -1
    p.phase_timer = 0
    p.start_yaw = 0
    p.orbit = 0
    p.orbit_target = 0
    p.camera_ref = 0
    p.speed = 0
    p.warmup = 0
    p.slide_x = -70
    p.slide_z = 70
    p.timer = 0
    p.axis = 1
    p.bank = 1
    p.radius = RADIUS
    p.reverse = 1
    for bit, mode in MODE_BUTTONS:
        if buttons & bit:
            p.mode = mode
            break
    else:
        p.mode = counter & 3


def helicopter_step(p: Props, camera_yaw: int, sine: list[int]) -> None:
    """FUN_801E3D0C for a frame the helicopter is shown: `camera_yaw` the camera's yaw word
    (0x802C6BD8), `sine` the 4096-entry table at 0x80175944."""
    if p.warmup > WARMUP:
        _watch_camera(p, s16(camera_yaw))
    else:
        p.warmup = s16(p.warmup + 1)
    _fly(p, sine)


def _watch_camera(p: Props, yaw: int) -> None:
    """FUN_801E3F68."""
    a = p.angles[0]
    a[1] = s16(a[1] & 0xFFF)
    p.start_yaw = s16(p.start_yaw & 0xFFF)
    if p.mode == 0:
        if p.flags & 2:
            p.camera_last = s16(yaw)
            return
        ref = p.camera_ref
        if ref < yaw:
            turned, bits = yaw - ref, 7
        else:
            turned, bits = ref - yaw, 0x23
        if turned > NEAR_TURN:
            p.profile = FAR_PROFILE if turned > FAR_TURN else NEAR_PROFILE
            p.phase_timer = 0
            p.flags = u16(p.flags | bits)
            p.start_yaw = a[1]
            p.camera_ref = s16(yaw)
            p.camera_last = s16(yaw)
            return
        p.timer = s16(p.timer + 1)
        p.camera_last = s16(yaw)
    elif p.mode in (1, 2, 3):
        p.timer = s16(p.timer + 1)
        p.flags = u16(p.flags | 0x1000)


def _orbit_position(p: Props, angle: int, sine: list[int], radius: int = RADIUS) -> None:
    """x, z on the orbit at `angle` (sin, cos of −angle), the game's rounding toward zero."""
    def scaled(v: int) -> int:
        v = v * radius
        return (v + 0xFFF if v < 0 else v) >> 12
    p.positions[0][0] = s16(scaled(sine[-angle & 0xFFF]))
    p.positions[0][2] = s16(scaled(sine[(-angle + 0x400) & 0xFFF]))


def _fly(p: Props, sine: list[int]) -> None:
    """FUN_801E40C0."""
    p.angles[1][1] = s16(p.angles[1][1] - ROTOR)
    p.angles[2][0] = s16(p.angles[2][0] + ROTOR)
    if p.flags & 1 and p.mode == MANOEUVRE_MODE:
        _manoeuvre(p, sine, 1)
        _manoeuvre(p, sine, -1)
    else:
        t = p.yaw_timer
        if t & 2:
            p.angles[0][1] = s16(p.angles[0][1] + p.yaw_dir)
        p.yaw_timer = s16(t + 1)
        if p.yaw_timer == 0x100:
            p.yaw_timer = 0
            p.yaw_dir = s16(-p.yaw_dir)
    if not (p.flags & 1) or not (p.flags & 0x1000):
        p.positions[0][1] = s16(p.positions[0][1] + (1 if p.bob_dir > 0 else -1))
        p.bob_timer = s16(p.bob_timer + 1)
        if p.bob_timer == 0x40:
            p.bob_timer = 0
            p.bob_dir = s16(-p.bob_dir)
        p.angles[0][2] = s16(p.angles[0][2] + p.tilt_dir)
        p.tilt_timer = s16(p.tilt_timer + 1)
        if p.tilt_timer == 0x40:
            p.tilt_timer = 0
            p.tilt_dir = s16(-p.tilt_dir)
        if not (p.flags & 0x1000):
            return
    if p.mode == 1:
        _figure_1(p, sine)
    elif p.mode == 2:
        _figure_2(p, sine)
    elif p.mode == 3:
        _figure_3(p, sine)


def _manoeuvre(p: Props, sine: list[int], side: int) -> None:
    """FUN_801E42DC (side 1: flags 4, 8, 0x10, the orbit growing) and its mirror FUN_801E4674
    (side −1: flags 0x20, 0x40, 0x80)."""
    rise, orbit_bit, brake_bit = (4, 8, 0x10) if side > 0 else (0x20, 0x40, 0x80)
    a, pos = p.angles[0], p.positions[0]
    if p.flags & rise:
        early = p.phase_timer < 0x20
        p.phase_timer = s16(p.phase_timer + 1)
        if early:
            a[1] = s16(a[1] + 0x10 * side)
            pos[1] = s16(pos[1] + 8)
        else:
            p.flags = u16(p.flags & ~rise | orbit_bit)
            p.phase_timer = 0
            p.bank = 0
            p.speed = 0
    if p.flags & orbit_bit:
        top, delta, brake, rate = p.profile
        step = s16((p.speed >> 1) + 2)
        p.step_size = step
        gap = p.orbit - p.orbit_target
        if (gap < 0 and -gap < brake) or (gap >= 0 and gap < brake):
            p.step_size = top
            if step < top:
                p.speed = s16(p.speed + 1)
                p.step_size = step
        else:
            if not (p.flags & brake_bit):
                p.turn_rate = rate
                turn = a[1] - p.start_yaw
                p.turn_left = u16(abs(turn) + delta) & 0xFFF
                p.flags = u16(p.flags | brake_bit)
            p.speed = s16(p.speed - 1)
            if p.speed < 0:
                p.speed = 0
                p.flags = u16(p.flags & ~orbit_bit)
                p.orbit_target = s16(p.orbit_target + delta * side)
        p.orbit = s16(p.orbit + p.step_size * side)
        _orbit_position(p, p.orbit, sine)
        if p.bank < 0x1E:
            p.angles[0][2] = s16(p.angles[0][2] - 10 * side)
            p.bank = s16(p.bank + 1)
    if p.flags & brake_bit:
        if p.phase_timer < 0x20:
            pos[1] = s16(pos[1] - 8)
        p.phase_timer = s16(p.phase_timer + 1)
        if p.phase_timer > 0x24:
            p.turn_rate = s16(p.turn_rate - 1)
        if p.turn_rate < 0:
            p.turn_rate = 0
        p.turn_step = s16(p.turn_rate * 2 + 2)
        a[1] = s16(a[1] - p.turn_step * side)
        left = s16(p.turn_left - p.turn_step)
        p.turn_left = u16(left)
        if left < 0:
            if side > 0:             # the mirror keeps its phase timer
                p.phase_timer = 0
            p.flags = u16(p.flags & (0xFFEC if side > 0 else 0xFF7C))
        if p.bank > 0:
            p.bank = s16(p.bank - 1)
            p.angles[0][2] = s16(p.angles[0][2] + 10 * side)


def _figure_1(p: Props, sine: list[int]) -> None:
    """FUN_801E4A0C (mode 1)."""
    a = p.angles[0]
    t = p.timer
    if p.state == 0:
        if t < 200:
            a[1] = s16(a[1] + 4)
            return
    elif p.state == 1:
        if t < 0x118:
            a[1] = s16(a[1] + 4)
            return
    elif p.state == 2:
        p.step_size = s16(p.speed >> 3 | 1)
        if t == 500:
            p.accelerate = 0
        if p.accelerate == 0:
            if t < 0x212:
                a[2] = s16(a[2] + p.bank * 6)
            if t < 0x230:
                a[0] = s16(a[0] + 4)
            p.speed = s16(p.speed + (1 if p.reverse == 0 else -1))
            if p.speed == 0:
                p.state = 5
                p.timer = 0
        else:
            if t < 0x1F:
                a[2] = s16(a[2] - p.bank * 6)
            if t < 0x3D:
                a[0] = s16(a[0] - 1)
            if abs(p.step_size) < 8:
                p.speed = s16(p.speed + (-1 if p.reverse == 0 else 1))
            else:
                p.step_size = -8 if p.reverse == 0 else 8
        angle = -(p.orbit + p.step_size)
        p.orbit = s16(p.orbit + p.step_size)
        a[1] = s16(a[1] - p.step_size)
        _orbit_position(p, -angle, sine)
        return
    elif p.state == 4:
        if t < 0x118:
            a[1] = s16(a[1] - 4)
            return
    elif p.state == 5:
        if t < 0x1E:
            return
        if t < 0xD2:
            a[0] = s16(a[0] - 1)
        if t > 0x137:
            if p.speed == 0:
                p.reverse = 1 - p.reverse
            p.accelerate = 1
            p.bank = s16(-p.bank)
            p.state = 2
            p.timer = 0
            return
        a[1] = s16(a[1] + (-4 if p.reverse else 4))
        return
    else:
        return
    p.state = 2
    p.timer = 0
    p.accelerate = 1


def _figure_2(p: Props, sine: list[int]) -> None:
    """FUN_801E4E04 (mode 2)."""
    a = p.angles[0]
    t = p.timer
    if p.state == 0:
        if t < 0x1E:
            a[2] = s16(a[2] - 8)
        if 0x82 <= t < 0xA0:
            a[2] = s16(a[2] + 8)
        if t < 0xA0:
            a[1] = s16(a[1] - 0xB)
        if t == 0x8C:
            p.accelerate = 1
        if t < 0x8D:
            return
        p.step_size = 0x19 if p.speed > 1 else 5
        if t == 0x15E:
            p.accelerate = 0
        if p.accelerate == 0:
            p.speed = s16(p.speed - 1)
            if p.speed == 0:
                p.state = 2
                p.timer = 0
        else:
            if p.step_size > 200:
                p.step_size = 200
            p.speed = s16(p.speed + 1)
        p.radius = s16(p.radius + p.step_size)
        _orbit_position(p, p.orbit, sine, p.radius)
    elif p.state == 2:
        if t < 0x50:
            a[1] = s16(a[1] - 0xB)
            a[2] = s16(a[2] - 3)
        else:
            p.accelerate = 1
            p.state = 3
            p.timer = 0
            p.orbit = 0
            p.speed = 0
            a[1] = s16(a[1] - 0xB)
            a[2] = s16(a[2] - 5)
    elif p.state == 3:
        if t < 0x14:
            a[1] = s16(a[1] - 0x16)
            a[2] = s16(a[2] - 5)
        else:
            a[1] = s16(a[1] - p.step_size)
        step = (s16(p.speed) >> 3) | 1
        p.step_size = s16(step)
        if t == 0x578:
            p.accelerate = 0
        if p.accelerate == 0:
            speed = p.speed - 1
            if p.speed == 1:
                p.state = 4
                p.timer = 0
        else:
            speed = p.speed + 1
            if step > 8:
                p.step_size = 8
                speed = p.speed
        p.speed = s16(speed)
        orbit = p.orbit
        p.radius = s16(p.radius - 10)
        p.orbit = s16(orbit + p.step_size)
        if p.radius < RADIUS:
            p.radius = RADIUS
        _orbit_position(p, orbit + p.step_size, sine, p.radius)
    elif p.state == 4:
        if t < 100:
            a[2] = s16(a[2] + 3)
        if t > 0xA0:
            p.timer = 0
            p.state = 5
    elif p.state == 5:
        if t < 0x15E:
            a[1] = s16(a[1] - 5)
        elif t < 0x1D6:
            a[2] = s16(a[2] + 2)
        if t < 0x3C:
            a[0] = s16(a[0] + 1)
        if t < 0x78:
            a[2] = s16(a[2] - 2)
        if t > 0x208:
            p.state = 6
            p.timer = 0
            p.accelerate = 1
    elif p.state == 6:
        if t < 0x1E:
            a[0] = s16(a[0] - 1)
        if t < 0x50:
            a[2] = s16(a[2] + 4)
        step = (s16(p.speed) >> 3) | 1
        p.step_size = s16(step)
        if p.accelerate == 0:
            speed = p.speed - 1
            if p.speed == 1:
                p.state = 7
                p.timer = 0
        else:
            speed = p.speed + 1
            if step > 8:
                p.step_size = 8
                speed = p.speed
        p.speed = s16(speed)
        p.orbit = s16(p.orbit - p.step_size)
        _orbit_position(p, p.orbit, sine)
        a[1] = s16(a[1] + p.step_size)


def _figure_3(p: Props, sine: list[int]) -> None:
    """FUN_801E54B4 (mode 3)."""
    a, pos = p.angles[0], p.positions[0]
    t = p.timer
    if p.state == 0:
        if t < 0x1E:
            a[0] = s16(a[0] - 1)
        if t < 0x10E:
            pos[1] = s16(pos[1] + 10)
        else:
            p.state = 1
            p.timer = 0
            p.slide = p.slide_z if p.axis == 0 else p.slide_x
    elif p.state == 1:
        if t < 0x79:
            k = 0 if p.axis == 0 else 2
            pos[k] = s16(pos[k] + p.slide)
        else:
            p.timer = 0
            if p.axis == 0:
                p.slide_z = s16(-p.slide_z)
            else:
                p.slide_x = s16(-p.slide_x)
            p.state = 2
            p.axis = 1 - p.axis
    elif p.state == 2:
        if t < 0x41:
            a[1] = s16(a[1] + 0x20)
        else:
            p.state = 3
            p.timer = 0
            p.orbit = s16(p.orbit + 0x800)
    elif p.state == 3:
        if 0xF1 <= t < 0x10E:
            a[0] = s16(a[0] + 1)
        if t < 0x10E:
            pos[1] = s16(pos[1] - 10)
        else:
            p.state = 4
            p.timer = 0
            p.flags = u16(p.flags & 0xFFFD)
    elif p.state == 4:
        if t < 0x79:
            return
        p.state = 5
        p.flags = u16(p.flags | 2)
        p.timer = 0
    elif p.state == 5:
        if t < 0x32:
            a[0] = s16(a[0] + 3)
            a[1] = s16(a[1] - 1)
            pos[1] = s16(pos[1] - 1)
            return
        if t < 0x118:
            a[1] = s16(a[1] - 5)
            pos[1] = s16(pos[1] - 6)
            return
        p.state = 6
        p.accelerate = 1
        p.flags = u16(p.flags & 0xFFFD)
        p.timer = 0
    elif p.state == 6:
        step = (s16(p.speed) >> 4) * 2 + 1
        p.step_size = s16(step)
        if t == 0x66:
            p.accelerate = 0
        if p.accelerate == 0:
            speed = p.speed - 1
            if p.speed == 1:
                p.state = 7
                p.timer = 0
                p.flags = u16(p.flags & 0xFFFD)
                p.step_size = 5
        else:
            speed = p.speed + 1
            if step > 10:
                p.step_size = 10
                speed = p.speed
        p.speed = s16(speed)
        p.orbit = s16(p.orbit - p.step_size)
        _orbit_position(p, p.orbit, sine)
        a[1] = s16(a[1] + p.step_size)
    elif p.state == 7:
        if t < 300:
            a[1] = s16(a[1] + 4)
            if t < 0x11E:
                pos[1] = s16(pos[1] + 5)
        if 0xC9 <= t < 0x15E:
            a[0] = s16(a[0] - 1)
        if t < 0x15F:
            return
        p.state = 8
        p.flags = u16(p.flags & 0xFFFD)
        p.timer = 0
    elif p.state == 8:
        if t < 0x79:
            return
        p.state = 0
        p.flags = u16(p.flags | 2)
        p.timer = 0
