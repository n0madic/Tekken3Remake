#!/usr/bin/env python3
"""Random cases of the arcade's sword glow (FUN_80192ecc) run in the CPU harness.

Each case sets up a fighter record of the arcade program (costume slot, the character word that
holds the PlayStation's bank type and character, player), the fighters' view (rotation,
translation, projection plane H, screen offsets 192 and 240 as the fight's display mode has them),
the world MATRIX of joint 10, the display buffer and the frame counter, runs the routine and records
the ten quads it built: their corners' screen positions, the ordering-table entry each was filed in
and the colour. The remake's ArcadeSwordGlow must reproduce every case
(tests/core/test_arcade_sword_glow.gd). Needs the MAME set (like arcade_attachment_cases.py), so
`export_traces.py` does not run it:

    python3 tools/research/arcade_sword_glow_cases.py [--count N] [--zip tekken3_mame.zip] [--out work/traces/arcade_sword_glow.bin]

Case file (`arcade_sword_glow.bin`): "T3AG", u32 version, u32 count, then per case:
    s16 costume slot, s16 character, s16 bank type, s16 frame counter parity, s16 view rot[9],
    s32 view t[3], s16 H, s16 pad, s16 block rot[9], s32 block t[3], u8 drawn, u8 pad[3];
    when drawn, per quad: s16 xy[8], u16 entry, u8 rgb
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
import sys
from pathlib import Path

from arcade_cpu import DEFAULT_ZIP, arcade, arcade_cpu  # puts tools/remake_import on the path

import arcade_sword_glow as asg
import sword_glow_cases as sgc

log = logging.getLogger("arcade_sword_glow_cases")

GLOW = 0x80192ECC
FIGHTER = 0x8031E154
OT_HEADER, OT_TABLE = 0x803C0000, 0x803C0100
ENTRIES = 1024
END_OF_LIST = 0x00FFFFFF
SCREEN_OFFSET = (192, 240)
SLOTS = (8, 9, 8, 9, 30, 31, 0, 7, 10, 40)
CHARACTER_WORDS = (0xF0004, 0xF0004, 0x40004, 0xF0007, 0x50004)   # character << 16 | bank type
VERSION = 1
DEFAULT_OUT = Path(__file__).resolve().parents[2] / "work" / "traces" / "arcade_sword_glow.bin"


def prepare(cpu, rng: random.Random, case: int, fixed_offset: bool = False) -> dict:
    """A random pre-state in the harness RAM and GTE: the same for the game and a port. Returns the
    case's inputs."""
    inputs = {
        "slot": rng.choice(SLOTS), "word": rng.choice(CHARACTER_WORDS),
        "player": rng.choice((0, 1)), "buffer": rng.choice((0, 1)),
        "parity": rng.randint(0, 1000),
    }
    near = case % 5 == 0         # a small depth makes the narrow ribbon
    inputs["view_rot"] = sgc.rotation(rng) if case % 3 == 0 else [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
    inputs["view_t"] = (rng.randint(-800, 800), rng.randint(-800, 800), rng.randint(0, 200) if near else rng.randint(1500, 6000))
    inputs["block_rot"] = sgc.rotation(rng)
    inputs["block_t"] = (rng.randint(-1200, 1200), rng.randint(-1500, 500), rng.randint(-1200, 1200))
    inputs["h"] = rng.randint(300, 1400)
    offset = SCREEN_OFFSET if fixed_offset else (rng.randint(100, 260), rng.randint(100, 260))
    cpu.write(FIGHTER + asg.PLAYER, struct.pack("<h", inputs["player"]))
    cpu.write(FIGHTER + asg.SLOT, struct.pack("<H", inputs["slot"]))
    cpu.write(FIGHTER + asg.CHARACTER, struct.pack("<I", inputs["word"]))
    cpu.write(asg.GS_OT, struct.pack("<I", OT_HEADER))
    cpu.write(OT_HEADER + 4, struct.pack("<I", OT_TABLE))
    cpu.write(OT_TABLE, struct.pack("<I", END_OF_LIST) * ENTRIES)
    cpu.write(asg.VIEW, sgc.matrix_bytes(inputs["view_rot"], inputs["view_t"]))
    cpu.write(FIGHTER + asg.SWORD_BLOCK, sgc.matrix_bytes(inputs["block_rot"], inputs["block_t"]))
    cpu.gte.write_ctrl(26, inputs["h"])
    cpu.gte.write_ctrl(24, offset[0] << 16)
    cpu.gte.write_ctrl(25, offset[1] << 16)
    cpu.write(asg.DISPLAY_BUFFER, struct.pack("<i", inputs["buffer"]))
    cpu.write(asg.PARITY, struct.pack("<i", inputs["parity"]))
    return inputs


def drawn(inputs: dict) -> bool:
    return inputs["slot"] in asg.SLOTS or inputs["word"] == asg.CHARACTER_MOKUJIN


def run_game(cpu, inputs: dict) -> list[tuple] | None:
    """The game's routine on the prepared state: the quads (xy[8], entry, rgb), or None when the
    fighter has no glow."""
    cpu.call(GLOW, FIGHTER)
    if not drawn(inputs):
        return None
    first = asg.PRIMITIVES + 800 * inputs["player"] + 400 * inputs["buffer"]
    entries = sgc.filed_entries(cpu, OT_TABLE, first, asg.PRIM_BYTES)
    quads = []
    for q in range(asg.QUADS):
        raw = cpu.read(first + asg.PRIM_BYTES * q, asg.PRIM_BYTES)
        xy = [struct.unpack_from("<h", raw, offset)[0] for v in range(4) for offset in (8 + 8 * v, 10 + 8 * v)]
        quads.append((xy, entries[q], tuple(raw[4:7])))
    return quads


def generate(cpu, count: int, seed: int = 26) -> bytes:
    rng = random.Random(seed)
    out = bytearray(b"T3AG" + struct.pack("<II", VERSION, count))
    for case in range(count):
        inputs = prepare(cpu, rng, case, fixed_offset=True)
        quads = run_game(cpu, inputs)
        out += struct.pack("<4h", inputs["slot"], inputs["word"] >> 16, inputs["word"] & 0xFFFF, inputs["parity"] & 1)
        out += struct.pack("<9h3ih", *inputs["view_rot"], *inputs["view_t"], inputs["h"]) + b"\0\0"
        out += struct.pack("<9h3i", *inputs["block_rot"], *inputs["block_t"])
        out += struct.pack("<B3x", quads is not None)
        for xy, entry, rgb in quads or ():
            out += struct.pack("<8hH3B", *xy, entry, *rgb)
    return bytes(out)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--count", type=int, default=2000)
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    args = parser.parse_args()
    cpu = arcade_cpu(arcade.open_set(args.zip))
    data = generate(cpu, args.count)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_bytes(data)
    log.info("%s: %d cases, %d bytes", args.out, args.count, len(data))
    return 0


if __name__ == "__main__":
    sys.exit(main())
