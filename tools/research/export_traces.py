#!/usr/bin/env python3
"""Export golden traces for the remake's tests.

Each trace replays one subsystem of the original game, with the ports that match the
game's own code in the CPU harness or with the game's code itself running in the harness,
and records inputs and outputs per frame. The remake's test suites feed the same inputs to
its GDScript core and compare. Traces contain game-derived data and are written to
`work/traces/` (git-ignored).

Pose trace (`pose_<bank>.bin`, little-endian):

    char[4] "T3PT", u32 version, u32 anim count
    per animation: u32 stream offset (section 6), u32 frame count,
        per frame: s16 pose[49] (motion.sample_pose), s16 slots[18][9] after pose_build_matrices

Slots carry over from frame to frame within an animation and start as identity
matrices, as a fighter's local matrices do while one move plays.

Demonstration trace (`enbu_<n>.bin`, little-endian), from `enbu_harness.py` (the game's
FUN_800D3D64 in the harness):

    char[4] "T3EB", u32 version, u32 demonstration, u32 frame count
    per frame: u8 phase, u8 flags (1 end event ran, 2/4 fighter 0/1 animated),
        s16 script frame (before the step),
        per fighter: s16 runner state, costume, move slot, end frame, frame,
                     s16 poseFrame, rootFrame, prevPoseFrame, costumeSlot, costumeKey, charId,
        s32 camera pitch, yaw, x, y, z, s16 H, s16 fade level (−1: no fade drawn),
        u8 call count, per call: u8 kind, s8 fighter, s16 a, b, c, d

Call kinds follow the remake's SimEvents (0 effect: set, joint; 1 spark: index, joint;
2 dust; 3 shake: script; 4 vibrate: player, pattern) plus 5 for HandFaceCommand (hands,
shape, speed). Game bug #49 is removed: the events of a fighter's MoveEvents that the game
runs again while the other fighter is processed are dropped (the exporter checks that they
repeat events of the same frame).


Pad vibration (`vibration.bin`): `vibration_trace.py` — the game's vibration scripts for every
pattern and some pairs.

Attachment cases (`attachments.bin`): `attachment_cases.py` — random inputs of the costume
attachments' dynamics (FUN_80037F10) with the game's results.

Gon's eyes' look direction (`gon_eyes.bin`): `gon_eyes_cases.py` — random head positions and
rotations with the shift of the pupils GonEyesFollow gives.

Back colours (`back_colour.bin`): `back_colour_cases.py` — the fighter's back colour for every
stage's light record and flash count, and random ones, with the game's result.

The Tekken Force pick-up's golden colours (`force_back_colour.json`) come from
`trace_back_colour.py force --out` (the whole scenario runs: about ten minutes).

    python3 tools/research/export_traces.py [--banks divmot00 divmot99] [--enbu 0 1 2]
        [--attachments N] [--gon-eyes N] [--no-back-colour]
"""

from __future__ import annotations

import argparse
import logging
import struct
from pathlib import Path

import motion
import pose

ROOT = Path(__file__).resolve().parents[2]
BNS_DIR = ROOT / "work" / "jp_rev1" / "bns"
OUT_DIR = ROOT / "work" / "traces"
POSE_MAGIC = b"T3PT"
POSE_VERSION = 1
ENBU_MAGIC = b"T3EB"
ENBU_VERSION = 2
CALL_KINDS = {"effect": 0, "spark": 1, "dust": 2, "shake": 3, "vibrate": 4, "hand_face": 5}
BANK_IDS = {"divmot00": 74, "divmot99": 279}
IDENTITY = [0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000]

log = logging.getLogger("export_traces")


def own_anims(bank: motion.MotionBank) -> list[int]:
    return sorted({bank.move_row(r)[0] for r in range(bank.move_count) if bank.move_row(r)[0] < motion.COMMON_FLAG})


def pose_trace(name: str, exe: bytes) -> bytes:
    data = (BNS_DIR / f"{BANK_IDS[name]:03d}_{name}.bin").read_bytes()
    bank = motion.parse_bank(data)
    spline = motion.SplineTables(exe)
    tab = pose.ExeTables(exe)
    anims = own_anims(bank)
    out = bytearray(POSE_MAGIC + struct.pack("<II", POSE_VERSION, len(anims)))
    frames_total = 0
    for offset in anims:
        stream = motion.parse_anim(data, bank.anim_offset(offset))
        out += struct.pack("<II", offset, stream.frames)
        slots = [IDENTITY[:] for _ in range(pose.SLOT_COUNT)]
        for frame in range(stream.frames):
            vec = motion.sample_pose(stream, frame, spline)
            pose.pose_build_matrices(vec, slots, tab)
            out += struct.pack("<49h", *vec)
            for slot in slots:
                out += struct.pack("<9h", *slot)
        frames_total += stream.frames
    log.info("%s: %d animations, %d frames", name, len(anims), frames_total)
    return bytes(out)


def intended_calls(calls: list[tuple]) -> tuple[list[tuple], int]:
    """The calls of one frame without bug #49's repeated MoveEvents; returns them and the
    number dropped. Each fighter's processing ends with its 'animate' call; inside it only the
    MoveEvents of that fighter belong to it."""
    kept, block = [], []
    dropped = 0
    for call in calls:
        if call[0] != "animate":
            block.append(call)
            continue
        owner = call[2]
        for c in block:
            if c[1] in (-1, owner):
                kept.append(c)
            elif c in kept:
                dropped += 1
            else:
                raise ValueError(f"call {c} of another fighter is not a repeat")
        block = []
    kept.extend(block)
    return kept, dropped


def enbu_trace(demo: int) -> bytes:
    import enbu_harness
    frames = enbu_harness.EnbuHarness().record(demo)
    out = bytearray(ENBU_MAGIC + struct.pack("<IIIi", ENBU_VERSION, demo, len(frames), enbu_harness.ROUND_STATE_AFTER_FIGHT))
    dropped = 0
    for f in frames:
        animated = {c[2] for c in f.calls if c[0] == "animate"}
        flags = int(f.done) | (2 if 0 in animated else 0) | (4 if 1 in animated else 0)
        out += struct.pack("<BBh", f.phase, flags, f.script_frame)
        for i in range(2):
            out += struct.pack("<11h", *f.runner[i], *f.fighter[i])
        out += struct.pack("<5ihh", *f.camera, f.fade)
        out += struct.pack("<5i", *f.backdrop)
        calls, n = intended_calls(f.calls)
        dropped += n
        out += struct.pack("<B", len(calls))
        for c in calls:
            args = list(c[2:]) + [0] * (4 - len(c[2:]))
            out += struct.pack("<Bb4h", CALL_KINDS[c[0]], c[1], *args)
    log.info("demonstration %d: %d frames, %d repeated event calls dropped (bug #49)", demo, len(frames), dropped)
    return bytes(out)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--banks", nargs="*", default=list(BANK_IDS))
    parser.add_argument("--enbu", nargs="*", type=int, default=[0, 1, 2])
    parser.add_argument("--gon-eyes", type=int, default=2000, help="Gon's eye direction cases (0: none)")
    parser.add_argument("--no-back-colour", action="store_true")
    parser.add_argument("--no-vibration", action="store_true")
    parser.add_argument("--attachments", type=int, default=3000, help="attachment cases (0: none)")
    parser.add_argument("--fight", nargs="*", default=None,
                        help="fight scenarios of fight_harness.SCENARIOS (no names: all)")
    parser.add_argument("--jobs", type=int, default=8, help="fight scenarios run in parallel")
    args = parser.parse_args()
    exe = motion.load_exe()
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name in args.banks:
        (OUT_DIR / f"pose_{name}.bin").write_bytes(pose_trace(name, exe))
    for demo in args.enbu:
        (OUT_DIR / f"enbu_{demo}.bin").write_bytes(enbu_trace(demo))
    if args.attachments:
        import attachment_cases
        (OUT_DIR / "attachments.bin").write_bytes(attachment_cases.generate(args.attachments))
        log.info("attachments: %d cases", args.attachments)
    if args.gon_eyes:
        import gon_eyes_cases
        (OUT_DIR / "gon_eyes.bin").write_bytes(gon_eyes_cases.generate(args.gon_eyes))
        log.info("Gon's eyes: %d cases", args.gon_eyes)
    if not args.no_back_colour:
        import back_colour_cases
        (OUT_DIR / "back_colour.bin").write_bytes(back_colour_cases.generate())
        log.info("back colour: cases")
    if not args.no_vibration:
        import vibration_trace
        (OUT_DIR / "vibration.bin").write_bytes(vibration_trace.record())
        log.info("vibration: pad scripts")
    if args.fight is not None:
        import fight_harness
        fight_harness.export(args.fight, OUT_DIR, args.jobs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
