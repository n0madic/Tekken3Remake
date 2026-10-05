#!/usr/bin/env python3
"""Random cases of the arcade's attachment dynamics (FUN_8019b6d8) run in the CPU harness.

Each case sets up one fighter record of the arcade program (costume slot, an attachment's rest
angles plus record offsets, started flag, smoothed tip, mode-1 target angles, the world joints
of all 24 rows with the attachment's parent link and offset, the helicopter stage's wind) and
calls the routine; it records those inputs and the results: the attachment's local rotation,
smoothed tip and target angles. The remake's ArcadeAttachments must reproduce every case
(tests/presentation/test_arcade_attachments.gd).

    python3 tools/research/arcade_attachment_cases.py [--count N] [--out work/traces/arcade_attachments.bin]
        [--steps-count N] [--steps-out work/traces/arcade_attachment_steps.bin]

Case file: "T3AA", u32 version, u32 count, then per case:
    u8 slot, u8 attachment, u8 started, u8 parent row, s16 angles[3], s16 record[RECORD],
    s16 wind[3], s32 tip[3], s32 target[2], s32 offset[3], 24 × (s16 rot[9], s32 t[3]),
    then the results: s16 local[9], s32 tip[3], s32 target[2]

It also writes whole runs (`arcade_attachment_steps.bin`): a costume's swinging and static
attachments set up as the model loads them (FUN_8019b634), then STEPS steps of a skeleton turning
slowly about a random start, each running every drawn attachment in row order through the
routine and CompMatrix as FUN_80198754 does. The remake's ArcadeAttachments.update must give the
same attachment joints, from the converted model (tests/presentation/test_arcade_attachments.gd).

Run file: "T3AT", u32 version, u32 count, u32 steps, then per run: u8 slot, u8 pad, s16 wind[3],
then per step 18 skeleton joints and the 6 attachment joints (rows 18–23, zero when not drawn),
each s16 rot[9], s32 t[3].
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "remake_import"))

import arcade  # noqa: E402
import arcade_cpu  # noqa: E402
import arcade_kmd  # noqa: E402
import arcade_character  # noqa: E402
import motion  # noqa: E402
import pose  # noqa: E402

log = logging.getLogger("arcade_attachment_cases")

DYNAMICS = 0x8019B6D8
FIGHTER = 0x8031E154
FIGHTER_BYTES = 0x1AE4
SLOT = 0x1E
ANGLES = 0x1180                 # s16[3] per attachment, 8 bytes apart (FUN_8019b634)
TIP = 0x11E0                    # s32[3] per attachment, 16 bytes apart: the smoothed tip
STARTED = 0x1240                # s16 per attachment
RECORDS = 0x124C                # u32 per attachment: its dynamics record
TARGET = 0x1268                 # s32 yaw, pitch (mode 1)
JOINTS = 0x724                  # per row, 0x50 bytes: +4 local MATRIX, +0x24 world MATRIX, +0x48 parent
JOINT_BYTES = 0x50
LOCAL, WORLD, PARENT = 4, 0x24, 0x48
WIND = 0x8021F690               # s16[3] (FUN_8019c738)
PAUSES = (0x8021FBD0, 0x8021FAD0)   # FUN_8019b6d8 returns at once while either is set
COMPOSE = 0x801EF684             # CompMatrix (libgte)
RECORD = arcade_character.RECORD_WORDS
ROWS = arcade_kmd.ROWS
VERSION = 1
DEFAULT_OUT = ROOT / "work" / "traces" / "arcade_attachments.bin"
STEPS_OUT = ROOT / "work" / "traces" / "arcade_attachment_steps.bin"
STEPS = 40
TURN_PER_STEP = 0x200            # the skeleton's joints turn up to this much per step (16-bit angles)


def matrix(rot: list[int], t: list[int]) -> bytes:
    return struct.pack("<9h", *rot) + b"\0\0" + struct.pack("<3i", *t)


def dynamic_attachments(arc: arcade.ArcadeSet) -> list[tuple[int, int, int, int, list[int]]]:
    """(slot, attachment, parent row, record address, record) of every swinging attachment."""
    out = []
    for slot in range(arcade_character.SLOTS):
        model = arcade_kmd.parse(arcade_character.costume(arc, slot)[0])
        for i in range(arcade_kmd.ATTACHMENTS):
            row = model.rows[arcade_kmd.FIRST_ATTACHMENT + i]
            pointer = arc.prog_values("<I", arcade_kmd.ATTACHMENT_RECORDS + 4 * (arcade_kmd.ATTACHMENTS * slot + i))[0]
            if row.verts is None or pointer == arcade_kmd.STATIC_RECORD:
                continue
            out.append((slot, i, row.parent, pointer, list(arc.prog_values(f"<{RECORD}h", pointer))))
    return out


def generate(count: int, seed: int = 7) -> bytes:
    rng = random.Random(seed)
    arc = arcade.open_set(arcade_cpu.DEFAULT_ZIP)
    cpu = arcade_cpu.arcade_cpu(arc)
    tab = pose.ExeTables(motion.load_exe())
    choices = dynamic_attachments(arc)
    log.info("%d swinging attachments", len(choices))
    out = bytearray(b"T3AA" + struct.pack("<II", VERSION, count))

    def rotation() -> list[int]:
        m = pose.euler_to_matrix(rng.getrandbits(16), rng.getrandbits(16), rng.getrandbits(16), tab)
        return [m[r][k] for r in range(3) for k in range(3)]

    for address in PAUSES:
        cpu.write(address, bytes(4))
    for _ in range(count):
        slot, i, parent, pointer, record = rng.choice(choices)
        row = arcade_kmd.FIRST_ATTACHMENT + i
        cpu.write(FIGHTER, bytes(FIGHTER_BYTES))
        cpu.write(FIGHTER + SLOT, struct.pack("<h", slot))
        cpu.write(FIGHTER + RECORDS + 4 * i, struct.pack("<I", pointer))
        angles = [rng.getrandbits(16) - 0x8000 for _ in range(3)]
        started = int(rng.random() < 0.9)
        tip = [rng.randrange(-4096, 4096) for _ in range(3)]
        target = [rng.randrange(-0x800, 0x800), rng.randrange(-0x800, 0x800)]
        wind = [rng.randrange(-200, 200), rng.randrange(0, 300), rng.randrange(-200, 200)] if rng.random() < 0.3 else [0, 0, 0]
        offset = [rng.randrange(-300, 300) for _ in range(3)]
        cpu.write(FIGHTER + ANGLES + 8 * i, struct.pack("<3h", *angles))
        cpu.write(FIGHTER + STARTED + 2 * i, struct.pack("<h", started))
        cpu.write(FIGHTER + TIP + 16 * i, struct.pack("<3i", *tip))
        cpu.write(FIGHTER + TARGET, struct.pack("<2i", *target))
        cpu.write(WIND, struct.pack("<3h", *wind))
        joints = []
        for k in range(ROWS):
            rot = rotation()
            t = [rng.randrange(-2500, 2500), rng.randrange(-2200, 150), rng.randrange(-2500, 2500)]
            joints.append((rot, t))
        # The attachment's own joint (its previous frame) near its parent, so its tip is realistic.
        pt = joints[parent][1]
        joints[row] = (joints[row][0], [pt[k] + rng.randrange(-400, 400) for k in range(3)])
        for k, (rot, t) in enumerate(joints):
            cpu.write(FIGHTER + JOINTS + JOINT_BYTES * k + WORLD, matrix(rot, t))
        base = FIGHTER + JOINTS + JOINT_BYTES * row
        cpu.write(base + PARENT, struct.pack("<I", FIGHTER + JOINTS + JOINT_BYTES * parent))
        cpu.write(base + LOCAL, matrix([0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000], offset))
        cpu.call(DYNAMICS, FIGHTER, row)
        local = list(struct.unpack("<9h", cpu.read(base + LOCAL, 18)))
        tip_after = list(struct.unpack("<3i", cpu.read(FIGHTER + TIP + 16 * i, 12)))
        target_after = list(struct.unpack("<2i", cpu.read(FIGHTER + TARGET, 8)))
        out += struct.pack("<4B", slot, i, started, parent) + struct.pack("<3h", *angles)
        out += struct.pack(f"<{RECORD}h", *record) + struct.pack("<3h", *wind)
        out += struct.pack("<3i", *tip) + struct.pack("<2i", *target) + struct.pack("<3i", *offset)
        for rot, t in joints:
            out += struct.pack("<9h3i", *rot, *t)
        out += struct.pack("<9h", *local) + struct.pack("<3i", *tip_after) + struct.pack("<2i", *target_after)
    return bytes(out)


def compose(parent: tuple[list[int], list[int]], local: list[int], offset: list[int]) -> tuple[list[int], list[int]]:
    """CompMatrix in integers (columns through MVMVA, the offset as 16-bit; the skeleton only)."""
    p, pt = parent
    rot = [max(-0x8000, min(0x7FFF, (p[3 * r] * local[c] + p[3 * r + 1] * local[3 + c] + p[3 * r + 2] * local[6 + c]) >> 12))
           for r in range(3) for c in range(3)]
    t = [((p[3 * r] * offset[0] + p[3 * r + 1] * offset[1] + p[3 * r + 2] * offset[2]) >> 12) + pt[r] for r in range(3)]
    return rot, t


def generate_steps(count: int, seed: int = 11) -> bytes:
    rng = random.Random(seed)
    arc = arcade.open_set(arcade_cpu.DEFAULT_ZIP)
    cpu = arcade_cpu.arcade_cpu(arc)
    tab = pose.ExeTables(motion.load_exe())
    slots = sorted({c[0] for c in dynamic_attachments(arc)})
    out = bytearray(b"T3AT" + struct.pack("<III", VERSION, count, STEPS))
    for address in PAUSES:
        cpu.write(address, bytes(4))
    for _ in range(count):
        slot = rng.choice(slots)
        model = arcade_kmd.parse(arcade_character.costume(arc, slot)[0])
        enable = arc.prog(arcade_kmd.ATTACHMENT_ENABLE + arcade_kmd.ATTACHMENTS * slot, ROWS)
        rows = [r.index for r in model.rows[arcade_kmd.FIRST_ATTACHMENT:]
                if r.verts is not None and r.verts.coords and enable[r.index] and r.parent >= 0]
        wind = [rng.randrange(-4096, 4096), rng.randrange(0, 4096), rng.randrange(-4096, 4096)] if rng.random() < 0.3 \
            else [0, 0, 0]
        cpu.write(FIGHTER, bytes(FIGHTER_BYTES))
        cpu.write(FIGHTER + SLOT, struct.pack("<h", slot))
        cpu.write(WIND, struct.pack("<3h", *wind))
        for k in rows:
            i = k - arcade_kmd.FIRST_ATTACHMENT
            row = model.rows[k]
            pointer = arc.prog_values("<I", arcade_kmd.ATTACHMENT_RECORDS + 4 * (arcade_kmd.ATTACHMENTS * slot + i))[0]
            offsets = arc.prog_values("<3h", pointer)
            angles = [((r + o + 0x8000) & 0xFFFF) - 0x8000 for r, o in zip(row.rest, offsets)]
            x, y, z = row.offset
            block = FIGHTER + JOINTS + JOINT_BYTES * k
            cpu.write(FIGHTER + RECORDS + 4 * i, struct.pack("<I", pointer))
            cpu.write(FIGHTER + ANGLES + 8 * i, struct.pack("<3h", *angles))
            cpu.write(block + LOCAL, matrix([0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000], [x, y, -z]))
            cpu.write(block + PARENT, struct.pack("<I", FIGHTER + JOINTS + JOINT_BYTES * row.parent))
        out += struct.pack("<2B3h", slot, 0, *wind)
        angles = [[rng.getrandbits(16) for _ in range(3)] for _ in range(arcade_kmd.JOINTS)]
        drift = [[rng.randrange(-TURN_PER_STEP, TURN_PER_STEP) for _ in range(3)] for _ in range(arcade_kmd.JOINTS)]
        root = [rng.randrange(-2000, 2000), rng.randrange(-1100, -900), rng.randrange(-2000, 2000)]
        for _ in range(STEPS):
            body = []
            for k in range(arcade_kmd.JOINTS):
                angles[k] = [(a + d) & 0xFFFF for a, d in zip(angles[k], drift[k])]
                m = pose.euler_to_matrix(*angles[k], tab)
                local = [m[r][c] for r in range(3) for c in range(3)]
                row = model.rows[k]
                x, y, z = row.offset
                body.append((local, root) if row.parent < 0 else compose(body[row.parent], local, [x, y, -z]))
            for k, (rot, t) in enumerate(body):
                cpu.write(FIGHTER + JOINTS + JOINT_BYTES * k + WORLD, matrix(rot, t))
            for k in rows:
                block = FIGHTER + JOINTS + JOINT_BYTES * k
                cpu.call(DYNAMICS, FIGHTER, k)
                parent = FIGHTER + JOINTS + JOINT_BYTES * model.rows[k].parent
                cpu.call(COMPOSE, parent + WORLD, block + LOCAL, block + WORLD)
            for rot, t in body:
                out += struct.pack("<9h3i", *rot, *t)
            for k in range(arcade_kmd.FIRST_ATTACHMENT, ROWS):
                if k in rows:
                    data = cpu.read(FIGHTER + JOINTS + JOINT_BYTES * k + WORLD, 32)
                    out += data[:18] + data[20:32]
                else:
                    out += bytes(30)
    return bytes(out)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--count", type=int, default=3000)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--steps-count", type=int, default=24)
    parser.add_argument("--steps-out", type=Path, default=STEPS_OUT)
    args = parser.parse_args()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(generate(args.count))
    log.info("wrote %d cases to %s", args.count, args.out)
    args.steps_out.write_bytes(generate_steps(args.steps_count))
    log.info("wrote %d runs of %d steps to %s", args.steps_count, STEPS, args.steps_out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
