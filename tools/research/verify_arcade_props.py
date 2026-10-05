#!/usr/bin/env python3
"""Check arcade_props_sim.py against the arcade's own prop routines, frame by frame.

Stage 3's carousel and stage 11's helicopter in its four modes (chosen by buttons and by the
counter, two rounds in a row so that the variables the round start leaves alone carry over) are
run for a few thousand frames under random camera turns, in the game (FUN_801E3D94 at the round's
start, FUN_801E3D0C every frame, the helicopter shown) and in the port; every prop angle and
position and every helicopter variable must agree after every frame. The game is patched for
arcade bug #63 (the manoeuvre's mode test, 0x801E4100: 2 → 0) as the port fixes it.

`--export` writes the cases for the remake's test (tests/presentation/test_arcade_props.gd):
work/traces/arcade_props.json lists them (stage, and per round the buttons, counter and camera
yaws; with the sine table), work/traces/arcade_props.bin holds every frame's state after it as FRAME_WORDS
little-endian s16 (`frame_words`), the cases one after the other.

Usage: python3 tools/research/verify_arcade_props.py [--zip tekken3_mame.zip] [--frames N] [--seed S] [--export]
"""

from __future__ import annotations

import argparse
import json
import logging
import random
import struct
import sys
from pathlib import Path

import arcade_props_sim as sim
from arcade_cpu import DEFAULT_ZIP, ROOT, arcade, arcade_cpu, sine_table

log = logging.getLogger("verify_arcade_props")

ROUND_START = 0x801E3D94
FRAME = 0x801E3D0C
STAGE = 0x8021FBB8
ROUND_PHASE = 0x8021F0C0       # ≥ 6: the round has ended (FUN_801E2A2C shows the helicopter)
REPLAY = 0x8021F03C
BUTTONS = 0x8021FBF4
COUNTER = 0x8021FD58
CAMERA_YAW = 0x802C6BD8
ANGLES = 0x802FECE4            # 4 SVECTORs
POSITIONS = 0x8031E134         # 4 SVECTORs
PROFILE = 0x8021F9F8           # pointer to 4 s16
VARIABLES = 0x8021F9FC         # accelerate … carousel_timer, one s16 each (fa14 and the gaps too)
MANOEUVRE_TEST = 0x801E4100    # ori $v0, $zero, 2
MANOEUVRE_FIX = 0x34020000     # ori $v0, $zero, 0
FIELD_ADDRESSES = {name: 0x8021F9FC + 2 * k if k < 2 else 0x8021FA00 + 4 * (k - 2)
                   for k, name in enumerate(sim.Props.FIELDS)}
TRACE = ROOT / "work" / "traces" / "arcade_props.json"
TRACE_FRAMES = TRACE.with_suffix(".bin")
FRAME_WORDS = 12 + 12 + len(sim.Props.FIELDS) + 4


def frame_words(state: dict) -> list[int]:
    """angles (4 × xyz), positions (4 × xyz), the variables in Props.FIELDS order, profile."""
    words = [v for a in state["angles"] for v in a] + [v for a in state["positions"] for v in a]
    return words + [state[name] for name in sim.Props.FIELDS] + state["profile"]


def game_state(cpu) -> dict:
    def s16(a: int) -> int:
        return struct.unpack("<h", cpu.read(a, 2))[0]
    out = {
        "angles": [[s16(ANGLES + 8 * p + 2 * k) for k in range(3)] for p in range(4)],
        "positions": [[s16(POSITIONS + 8 * p + 2 * k) for k in range(3)] for p in range(4)],
    }
    for name, address in FIELD_ADDRESSES.items():
        out[name] = s16(address)
    pointer = cpu.u32(PROFILE)
    out["profile"] = list(struct.unpack("<4h", cpu.read(pointer, 8))) if pointer else [0, 0, 0, 0]
    return out


def port_state(p: sim.Props) -> dict:
    out = {"angles": [list(a) for a in p.angles], "positions": [list(v) for v in p.positions]}
    for name in sim.Props.FIELDS:
        out[name] = sim.s16(getattr(p, name))
    out["profile"] = list(p.profile)
    return out


def yaw_walk(rng: random.Random, frames: int) -> list[int]:
    """Camera yaws: slow drift with occasional swings past the manoeuvres' thresholds."""
    yaw, out = rng.randrange(-0x400, 0xC00), []
    for _ in range(frames):
        if rng.random() < 0.004:
            yaw += rng.choice((-1, 1)) * rng.randrange(0x150, 0x600)
        yaw += rng.randrange(-12, 13)
        out.append(yaw)
    return out


def run_case(cpu, sine: list[int], stage: int, rounds: list[tuple[int, int, list[int]]],
             port: sim.Props) -> tuple[int, list]:
    """Rounds of (buttons, counter, camera yaws); returns (first differing frame or −1, frames)."""
    cpu.write(STAGE, struct.pack("<H", stage))
    cpu.write(ROUND_PHASE, struct.pack("<i", 6))
    cpu.write(REPLAY, struct.pack("<i", 0))
    frames = []
    n = 0
    for buttons, counter, yaws in rounds:
        cpu.write(BUTTONS, struct.pack("<I", buttons))
        cpu.write(COUNTER, struct.pack("<H", counter))
        cpu.call(ROUND_START)
        if stage == 3:
            sim.carousel_start(port)
        else:
            sim.helicopter_start(port, buttons, counter)
        for yaw in yaws:
            cpu.write(CAMERA_YAW, struct.pack("<i", yaw))
            cpu.call(FRAME)
            if stage == 3:
                sim.carousel_step(port)
            else:
                sim.helicopter_step(port, yaw, sine)
            game, ours = game_state(cpu), port_state(port)
            frames.append(game)
            if game != ours:
                diff = {k: (game[k], ours[k]) for k in game if game[k] != ours[k]}
                log.info("  frame %d differs: %s", n, diff)
                return n, frames
            n += 1
    return -1, frames


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--frames", type=int, default=3000, help="frames per round")
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--export", action="store_true", help=f"write {TRACE.relative_to(ROOT)}")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    arc = arcade.open_set(args.zip)
    sine = sine_table(arc)
    rng = random.Random(args.seed)
    cases = [("carousel", 3, [(0, 0), (0, 0)])]
    for buttons, counter in ((0x200, 0), (0x100, 0), (0x40, 0), (0x20, 0), (0, 0), (0, 1), (0, 2), (0, 7)):
        cases.append((f"helicopter buttons {buttons:#x} counter {counter}", 11, [(buttons, counter), (buttons, counter)]))
    failures = 0
    export = []
    for name, stage, starts in cases:
        cpu = arcade_cpu(arc)
        if cpu.u32(MANOEUVRE_TEST) != 0x34020002:
            raise SystemExit("unexpected code at the manoeuvre's mode test")
        cpu.write(MANOEUVRE_TEST, struct.pack("<I", MANOEUVRE_FIX))
        rounds = [(b, c, yaw_walk(rng, args.frames)) for b, c in starts]
        first, frames = run_case(cpu, sine, stage, rounds, sim.Props())
        ok = first < 0
        failures += not ok
        log.info("%-40s %s", name, "ok" if ok else f"DIFFERENT from frame {first}")
        export.append({"name": name, "stage": stage,
                       "rounds": [{"buttons": b, "counter": c, "yaws": y} for b, c, y in rounds],
                       "frames": frames})
    if args.export and not failures:
        TRACE.parent.mkdir(parents=True, exist_ok=True)
        words = [w for case in export for frame in case.pop("frames") for w in frame_words(frame)]
        TRACE_FRAMES.write_bytes(struct.pack(f"<{len(words)}h", *words))
        TRACE.write_text(json.dumps({"frame_words": FRAME_WORDS, "fields": list(sim.Props.FIELDS),
                                     "sine": sine, "cases": export}))
        log.info("wrote %s and %s", TRACE, TRACE_FRAMES.name)
    log.info("%s", "all cases match" if not failures else f"{failures} cases differ")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
