#!/usr/bin/env python3
"""Check the arcade's face changes against the arcade's code (arcade/README.md#eye-shapes).

Two routines run in the CPU harness:

- `FUN_80193F90`, the per-frame face update (with `FUN_80193EA4`, which changes the shape), on a
  fighter struct of costume slot `s` whose move is plain, has the closed-eyes field (`+0x18`
  negative: ArcadeFace's `held`) or lies down (state bit 2 and `+0x17` zero: `down`). The copies it
  queues (`FUN_801BBF14`, a MoveImage of a rectangle to a point) are recorded per frame and
  compared with the model below, the one the remake's ArcadeFace ports (tests/presentation/test_arcade_face.gd
holds its shapes for three costume slots).
- `FUN_801A1C74`, the shout's face, for every character id and voice code against the converter's
  tables (arcade_eyes.shouts, which interprets the routine's instructions: this is its check against
  the CPU), and called mid-sequence by the model's run.

The random open time comes from `rand`, stubbed to a fixed sequence here.

Usage: python3 tools/research/verify_arcade_eyes.py [--zip tekken3_mame.zip] [--frames N] [--sequence SLOT]
"""

from __future__ import annotations

import argparse
import logging
import struct
import sys
from pathlib import Path

from arcade_cpu import DEFAULT_ZIP, arcade, arcade_cpu

import arcade_eyes  # noqa: E402  (arcade_cpu puts tools/remake_import on the import path)

log = logging.getLogger("verify_arcade_eyes")

FACE_FRAME = 0x80193F90
SHOUT = 0x801A1C74
MOVE_IMAGE = 0x801BBF14          # queues a VRAM copy: (rect*, x, y)
RAND = 0x801E7B24
GAME_STATE = 0x8021FD20          # the copies are skipped while this is 2
FIGHTER = 0x80330000
MOVE = 0x80340000
OPEN_SHAPE = 0
BLINK_FRAMES = 3
HELD_FRAMES = DOWN_FRAMES = 2
SLOTS = (0, 12, 10, 16, 4, 14, 40)
SHOUT_AT = {20: 0x2005, 150: 0x2000, 300: 0x2008, 400: 0x2002, 520: 0x2006}
HELD_SPANS = ((100, 110), (200, 215))
DOWN_SPANS = ((140, 170), (205, 220), (450, 470))
CHARACTER_CODES = arcade_eyes.SHOUT_FIRST


def rand_sequence() -> list[int]:
    """A fixed pseudo random sequence (the harness's `rand` and the model's)."""
    out, x = [], 12345
    for _ in range(4096):
        x = (x * 1103515245 + 12345) & 0x7FFFFFFF
        out.append(x >> 8 & 0x7FFF)
    return out


class FaceModel:
    """FUN_80193F90 and FUN_80193EA4 for one fighter: `copies` collects the rectangles copied over
    the eyes, as (source rectangle, destination)."""

    def __init__(self, arc: arcade.ArcadeSet, slot: int) -> None:
        self.arc = arc
        self.slot = slot
        self.rolled = {role: arcade_eyes.slot_table(arc, base, slot)
                       for role, base in (("blink", arcade_eyes.BLINK), ("held", arcade_eyes.HELD), ("down", arcade_eyes.DOWN))}
        self.layout = arcade_eyes.layout(arc, slot)
        self.shape = OPEN_SHAPE
        self.timer = 0
        self.rands = iter(rand_sequence())
        self.copies: list[tuple] = []

    def rectangle(self, shape: int) -> tuple:
        lay = self.layout
        w, h = self.arc.prog_values("<2h", arcade_eyes.SIZES + 4 * lay[1])
        return ((*self.arc.prog_values("<2h", arcade_eyes.RECTS + 4 * lay[2 + shape]), w, h),
                self.arc.prog_values("<2h", arcade_eyes.RECTS + 4 * lay[0]))

    def set(self, shape: int, frames: int) -> None:
        """FUN_80193EA4."""
        if shape >= arcade_eyes.SHAPES:
            return
        self.timer = frames
        if self.shape != shape and self.layout[2 + shape] != -1:
            self.shape = shape
            self.copies.append(self.rectangle(shape))

    def step(self, held: bool, down: bool) -> None:
        """FUN_80193F90."""
        if held:
            self.set(self.rolled["held"], HELD_FRAMES)
        elif down:
            self.set(self.rolled["down"], DOWN_FRAMES)
        if self.timer == 0:
            if self.shape == OPEN_SHAPE:
                self.set(self.rolled["blink"], BLINK_FRAMES)
            else:
                self.set(OPEN_SHAPE, next(self.rands) & 0xFE | 1)
        self.timer -= 1

    def shout(self, code: int) -> None:
        """FUN_801A1C74 (through FUN_80194080, shapes of value − 10)."""
        char = arcade_eyes.character_id(self.arc, self.slot)
        shouts = arcade_eyes.shouts(self.arc)
        if char in shouts:
            shape, frames = shouts[char]
            self.set(shape, frames[code - CHARACTER_CODES])


def schedule(frames: int) -> list[tuple[bool, bool, int | None]]:
    """(held, down, voice code) per frame."""
    return [(any(a <= n < b for a, b in HELD_SPANS), any(a <= n < b for a, b in DOWN_SPANS), SHOUT_AT.get(n))
            for n in range(frames)]


def run_model(arc: arcade.ArcadeSet, slot: int, frames: int) -> tuple[list[list[tuple]], list[int]]:
    """The copies of every frame and the shape shown at its end."""
    model = FaceModel(arc, slot)
    copies, shapes = [], []
    for held, down, code in schedule(frames):
        model.copies = []
        if code is not None:
            model.shout(code)
        model.step(held, down)
        copies.append(model.copies)
        shapes.append(model.shape)
    return copies, shapes


def run_original(arc: arcade.ArcadeSet, slot: int, frames: int) -> list[list[tuple]]:
    cpu = arcade_cpu(arc)
    current: list[tuple] = []
    rands = iter(rand_sequence())

    def move_image(cpu, rect, x, y, *_):
        current.append((struct.unpack("<4h", cpu.read(rect, 8)), (x & 0xFFFF, y & 0xFFFF)))
        return 0
    cpu.stub(MOVE_IMAGE, move_image)
    cpu.stub(RAND, lambda cpu, *_: next(rands))
    cpu.write(GAME_STATE, struct.pack("<I", 0))
    cpu.write(FIGHTER, bytes(0x1200))
    char = arcade_eyes.character_id(arc, slot)
    cpu.write(FIGHTER + 0x14, struct.pack("<h", 0))
    cpu.write(FIGHTER + 0x1A, struct.pack("<h", -1 if char is None else char))
    cpu.write(FIGHTER + 0x1E, struct.pack("<h", slot))
    cpu.write(FIGHTER + 0x44, struct.pack("<I", MOVE))
    out = []
    for held, down, code in schedule(frames):
        current.clear()
        # A plain move, one that closes the eyes (+0x18 negative), or a lying one.
        cpu.write(MOVE, bytes(0x40))
        if held:
            cpu.write(MOVE + 0x18, struct.pack("<i", -1))
        if down:
            cpu.write(MOVE + 4, struct.pack("<I", 4))
        if code is not None:
            cpu.call(SHOUT, FIGHTER, code)
        cpu.call(FACE_FRAME, FIGHTER)
        out.append([((r[0], r[1], r[2], r[3]), (d[0], d[1])) for r, d in current])
    return out


def check_shouts(arc: arcade.ArcadeSet) -> int:
    """FUN_801A1C74's shape and frames for each character id and voice code."""
    cpu = arcade_cpu(arc)
    calls: list[tuple] = []
    cpu.stub(0x80194080, lambda cpu, p, mask, value, frames: calls.append((value, frames)) or 0)
    failures = 0
    shouts = arcade_eyes.shouts(arc)
    for char in range(arcade_eyes.CHARACTER_IDS):
        for k in range(arcade_eyes.SHOUT_CODES):
            calls.clear()
            cpu.write(FIGHTER, bytes(0x40))
            cpu.write(FIGHTER + 0x1A, struct.pack("<h", char))
            cpu.call(SHOUT, FIGHTER, CHARACTER_CODES + k)
            expected = ([(shouts[char][0] + arcade_eyes.SHOUT_SHAPE_BASE, shouts[char][1][k])]
                        if char in shouts else [])
            if calls != expected:
                failures += 1
                log.info("shout: character %d code %#x: %s, expected %s", char, CHARACTER_CODES + k, calls, expected)
    log.info("shouts: %s", "all match" if not failures else f"{failures} differ")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--frames", type=int, default=600)
    parser.add_argument("--sequence", type=int, help="print the model's shape changes of this costume slot")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    arc = arcade.open_set(args.zip)
    failures = check_shouts(arc)
    for slot in SLOTS:
        original = run_original(arc, slot, args.frames)
        model, shapes = run_model(arc, slot, args.frames)
        ok = original == model
        failures += not ok
        changes = sum(len(c) for c in original)
        log.info("slot %2d: %d copies, %s", slot, changes, "ok" if ok else "DIFFERENT")
        if not ok:
            first = next(n for n, (a, b) in enumerate(zip(original, model)) if a != b)
            log.info("  first difference at frame %d: %s vs %s", first, original[first], model[first])
        if args.sequence == slot:
            log.info("shapes: %s", [(n, shape) for n, shape in enumerate(shapes) if n == 0 or shape != shapes[n - 1]])
    log.info("%s", "all match" if not failures else f"{failures} differ")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
