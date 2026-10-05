#!/usr/bin/env python3
"""Compare camera_sim.py with CameraFrameFighters / CameraTrackFighters in the CPU harness.

Usage: python3 tools/research/verify_camera_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
from collections import Counter

import camera_sim as cam
import fight_sim as sim
from psxcpu import load_release

CAMERA_CODE = (0x80062CF8, 0x80069A00)   # camera module (CameraReset .. the director helpers)
from verify_fight_sim import F0, F1, compare, prepare, snapshot

log = logging.getLogger("verify_camera_sim")
STATS: Counter[str] = Counter()


def case_frame(cpu, rng) -> bool:
    prepare(cpu, rng)
    mode = rng.choice([0, 0, 5, 7, 7])
    cpu.write(sim.GAME_MODE, struct.pack("<i", mode))
    cpu.write(cam.PROJECTION, struct.pack("<h", rng.choice([0x200, 0x226, 0x1C2, rng.randint(0x180, 0x300)])))
    src = rng.choice([0, 0, 1, 2])
    cx, cz = rng.randint(-20000, 20000), rng.randint(-20000, 20000)
    targets = []
    for k in range(2):
        targets += [cx + rng.randint(-3000, 3000), rng.randint(-1800, -200), cz + rng.randint(-3000, 3000), rng.randint(0, 368)]
    cpu.write(cam.TARGETS, struct.pack("<8i", *targets))
    rec = [cx + rng.randint(-6000, 6000), rng.randint(-3000, -500), cz + rng.randint(-6000, 6000),
           rng.randint(-0x8000, 0x8000), rng.randint(0, 0x3FFFF), rng.randint(-100, 100)]
    cpu.write(cam.SOURCES + 24 * src, struct.pack("<6i", *rec))
    cpu.write(cam.SMOOTH + 0x30 * src, struct.pack("<3i", rng.randint(-50, 50), rng.randint(0, 3000), rng.randint(-2000, 2000)))
    cpu.write(cam.HEIGHT_TERM, struct.pack("<i", rng.randint(-200, 400)))
    pitch = rng.choice([0, rng.randint(-0x4000, 0x4000)])
    yaw = rng.randint(-0x40000, 0x40000)
    reset = rng.choice([0, 0, 1])
    distance = rng.choice([0x158D, 0x158D * 0x72 >> 7, rng.randint(500, 9000)])
    ball = (cx + rng.randint(-5000, 5000), rng.randint(-4000, 0), cz + rng.randint(-5000, 5000))
    cpu.write(BALL_POINT, struct.pack("<3i", *ball))
    ram = snapshot(cpu)
    label = f"CameraFrameFighters (mode {mode}, src {src}, reset {reset})"
    try:
        cpu.call(0x800650F8, 0, 0, pitch, yaw, reset, distance, src)
    except RuntimeError as e:  # guest CPU exception (none seen so far)
        log.debug("skip %s", e)
        return True
    zero = []
    div = cam._div
    cam._div = lambda a, b: zero.append(b) or div(a, b) if b == 0 else div(a, b)
    try:
        cam.camera_frame_fighters(ram, pitch, yaw, reset, distance, src, ball)
    finally:
        cam._div = div
    if zero:
        STATS["zero divisor (R3000 result, compared)"] += 1
    return compare(cpu, ram, [(cam.SOURCES, 24 * 5), (cam.SMOOTH, 0x30 * 3), (cam.HEIGHT_TERM, 4), (cam.MOVED, 2)], label)


def case_track(cpu, rng) -> bool:
    prepare(cpu, rng)
    cpu.write(0x800A91A8, struct.pack("<h", rng.choice([-1, -1, 0, 1])))
    ram = snapshot(cpu)
    f0, f1 = sim.Fighter(ram, F0), sim.Fighter(ram, F1)
    for f in (f0, f1):
        f.throwState = rng.choice([0, 0, 0, 1, -1])
        f.bankType = rng.choice([0, 4])
        f.curSlot = rng.choice([0, 2, 5])
        f.set_at(0x994, "i", rng.randint(-2000, 0))
        f.set_at(0x1278, "h", rng.randint(0, 368))
    if rng.random() < 0.1:
        f1.posX, f1.posZ, f1.rootX, f1.rootZ = f0.posX, f0.posZ, f0.rootX, f0.rootZ
    force = rng.choice([0, 0, 1])
    cpu.write(0x80000000, bytes(ram.data))
    cpu.call(0x80064944, F0, F1, force)
    cam.camera_track_fighters(ram, f0, f1, force)
    return compare(cpu, ram, [(cam.TARGETS, 0x60)], "CameraTrackFighters")


YAW_OUT = 0x801E4000
BALL_POINT = 0x801E6000            # stand-in for the ball position returned by volley.ovl FUN_800B4948
POSE_ROWS = 0x801E5000


def case_yaw(cpu, rng) -> bool:
    prepare(cpu, rng)
    cx, cz = rng.randint(-20000, 20000), rng.randint(-20000, 20000)
    for k in range(2):
        cpu.write(cam.TARGETS + 16 * k, struct.pack("<3i", cx + rng.randint(-3000, 3000), rng.randint(-1800, -200),
                                                    cz + rng.randint(-3000, 3000)))
    src = rng.choice([0, 0, 0, 1, 2])
    cpu.write(cam.SOURCES + 24 * src + 16, struct.pack("<i", rng.randint(-0x40000, 0x40000)))
    state = bytearray(rng.randrange(256) for _ in range(0x30))
    state[0:2] = struct.pack("<h", rng.choice([0, 0, 1, 1, 1]))
    state[2:4] = struct.pack("<h", rng.choice([0, 1]))
    state[8:10] = struct.pack("<h", rng.choice([0, 0x1E, 0x1F, rng.randint(-5, 40)]))
    state[0xC:0x14] = struct.pack("<2i", rng.randint(-0x10000, 0x10000), rng.randint(-0x3000, 0x3000))
    state[0x14:0x1C] = struct.pack("<2i", rng.randint(-0x20000, 0x20000), rng.randint(-0x20000, 0x20000))
    cpu.write(cam.STATE + 0x30 * src, bytes(state))
    cpu.write(cam.FIGHTER_DISTANCE, struct.pack("<i", rng.choice([150, 199, 200, rng.randint(0, 5000)])))
    for k, base in enumerate((F0, F1)):
        row = POSE_ROWS + 0x40 * k
        cpu.write(row + 0x24, bytes([rng.choice([0, 0, 0x27, 0x28, 0x29, 0x2A, 0x53])]))
        cpu.write(base + 0x54, struct.pack("<I", row))
        cpu.write(base + 0x1278, struct.pack("<h", rng.randint(0, 368)))
    reset = rng.choice([0, 0, 0, 1])
    ram = snapshot(cpu)
    ret = cpu.call(0x80064AF8, F0, F1, YAW_OUT, reset, src) & 0xFFFFFFFF
    mine_ret, yaw = cam.camera_yaw_spring(ram, sim.Fighter(ram, F0), sim.Fighter(ram, F1), reset, src)
    ram.put(YAW_OUT, "i", yaw)
    ok = compare(cpu, ram, [(cam.STATE, 0x90), (YAW_OUT, 4)], f"CameraYawSpring (src {src}, reset {reset})")
    if ret != mine_ret & 0xFFFFFFFF:
        log.info("CameraYawSpring: return %#x, port %#x", ret, mine_ret)
        ok = False
    return ok


def case_blend(cpu, rng) -> bool:
    prepare(cpu, rng)
    cx, cz = rng.randint(-20000, 20000), rng.randint(-20000, 20000)
    for k in range(2):
        cpu.write(cam.TARGETS + 16 * k, struct.pack("<3i", cx + rng.randint(-3000, 3000), rng.randint(-1800, -200),
                                                    cz + rng.randint(-3000, 3000)))
    for i in range(5):
        cpu.write(cam.SOURCES + 24 * i, struct.pack(
            "<6i", cx + rng.randint(-8000, 8000), rng.randint(-3000, 0), cz + rng.randint(-8000, 8000),
            rng.randint(-0x8000, 0x8000), rng.randint(-0x40000, 0x40000), rng.randint(0x100, 0x400)))
    mask = rng.choice([1, 2, 4, 0x10, 3, 3, 5, 5, 0x11, 0x11])
    weights = [rng.randint(1, 0x1000) if mask >> i & 1 else rng.choice([0, 0, -5]) for i in range(5)]
    cpu.write(cam.WEIGHTS, struct.pack("<5h", *weights))
    cpu.write(cam.H_MIN, struct.pack("<2h", rng.choice([0x100, 0x180]), rng.choice([0x300, 0x400])))
    ram = snapshot(cpu)
    cpu.call(0x80062E5C)
    h = cam.camera_blend(ram)
    ok = compare(cpu, ram, [(cam.SOURCES, 24 * 5), (cam.VIEW, 0x20), (cam.WEIGHTS, 0x14)], f"CameraBlend (mask {mask:#x})")
    gte_h = cpu.gte.read_ctrl(26) & 0xFFFF
    if gte_h != h & 0xFFFF:
        log.info("CameraBlend (mask %#x): GTE H %#x, port %#x", mask, gte_h, h)
        ok = False
    return ok


CASES = {"CameraBlend": case_blend, "CameraYawSpring": case_yaw, "CameraTrackFighters": case_track, "CameraFrameFighters": case_frame}


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--only")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    cpu = load_release()
    cpu.r3000_divide_range(CAMERA_CODE[0], CAMERA_CODE[1])   # R3000 quotients for zero divisors
    cpu.stub(0x800B4948, lambda _cpu, *args: BALL_POINT)
    failed = False
    for name, case in CASES.items():
        if args.only and name != args.only:
            continue
        bad = sum(not case(cpu, rng) for _ in range(args.cases))
        log.info("%s: %d cases, %d mismatches", name, args.cases, bad)
        failed |= bad > 0
    for what, n in STATS.items():
        log.info("  %s: %d", what, n)
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
