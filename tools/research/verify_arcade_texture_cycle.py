#!/usr/bin/env python3
"""Check the arcade's fire-bowl texture animation (stages 6 and 12) against the arcade's code.

FUN_801E2090 sets the cycle up (its upload of category 39 is stubbed) and FUN_801E2114 runs every
frame of the stage's display; the copies it queues (FUN_801BBF14: a MoveImage of a rectangle to a
point) are recorded and compared with the model the converter and the remake use
(arcade.py TEXTURE_CYCLE*, StageView.step): every TEXTURE_CYCLE_PERIOD frames the next of the
TEXTURE_CYCLE_FRAMES source rectangles of the table, 16 × 64 VRAM words, to the stage's target.

Usage: python3 tools/research/verify_arcade_texture_cycle.py [--zip tekken3_mame.zip] [--frames N]
"""

from __future__ import annotations

import argparse
import logging
import struct
import sys
from pathlib import Path

from arcade_cpu import DEFAULT_ZIP, arcade, arcade_cpu

log = logging.getLogger("verify_arcade_texture_cycle")

CYCLE_START = 0x801E2090
CYCLE_FRAME = 0x801E2114
LOAD_CATEGORY = 0x801E2218     # loads and uploads a category's TIM block: no files or GPU here
MOVE_IMAGE = 0x801BBF14        # queues a VRAM copy: (rect*, x, y)
STAGE = 0x8021FBB8


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--frames", type=int, default=200)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    arc = arcade.open_set(args.zip)
    sources = [arc.prog_values("<4H", arcade.TEXTURE_CYCLE + 8 * k) for k in range(arcade.TEXTURE_CYCLE_FRAMES)]
    failures = 0
    for stage, (tx, ty) in arcade.TEXTURE_CYCLE_TARGET.items():
        cpu = arcade_cpu(arc)
        copies: list[tuple[int, tuple[int, ...], int, int]] = []
        frame = [0]

        def move(cpu, rect, x, y, *_):
            copies.append((frame[0], struct.unpack("<4h", cpu.read(rect, 8)), x & 0xFFFF, y & 0xFFFF))
            return 0
        cpu.stub(LOAD_CATEGORY, lambda cpu, *_: 0)
        cpu.stub(MOVE_IMAGE, move)
        cpu.write(STAGE, struct.pack("<H", stage))
        cpu.call(CYCLE_START)
        for n in range(1, args.frames + 1):
            frame[0] = n
            cpu.call(CYCLE_FRAME)
        w, h = arcade.TEXTURE_CYCLE_SIZE
        expected = []
        for n in range(1, args.frames + 1):
            if n % arcade.TEXTURE_CYCLE_PERIOD == 0:
                sx, _, sy, _ = sources[(n // arcade.TEXTURE_CYCLE_PERIOD - 1) % arcade.TEXTURE_CYCLE_FRAMES]
                expected.append((n, (sx, sy, w, h), tx, ty))
        ok = copies == expected
        failures += not ok
        log.info("stage %2d: %d copies, %s", stage, len(copies), "ok" if ok else f"DIFFERENT: {copies[:4]} vs {expected[:4]}")
    log.info("%s", "all stages match" if not failures else f"{failures} stages differ")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
