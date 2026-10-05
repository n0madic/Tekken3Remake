#!/usr/bin/env python3
"""Check Gon's eyes' texture shifts (GonEyesSetOffset, 0x80034120) against the converter's model
(`gaze.shifted`), in the CPU harness.

The routine runs on a synthetic fighter record (Gon, costume slot 42 or 43, player 1 or 2, the two
eyes' cache bytes +0x1292, +0x1293 cleared) for random sequences of look directions −17..17, as
FighterAnimate calls it every frame. The VRAM copies it queues (FUN_80029610's command list,
flushed in order by FUN_8002971C) must be, for each eye whose wanted shift differs from the one
it last copied (eye 0 wants the direction when it is not negative, eye 1 when it is, the other 0):
the 34-row window of the saved strip, from the row `gaze.SOURCE_ROWS[eye] + shift` of the saved
copy, onto the strip's row `gaze.DEST_ROWS[eye]` (both 0x100 rows lower for player 2).

The face's branch for the overhead KO camera (0x800B08D4 set) is checked on its own: FUN_80034354
on a Gon whose move has flag 0x40000 must set his jaw channel to the shape 3 value (HandFaceCommand
1, 3, 1) and queue the swapped palette's copy once (the palette cache +0x1291 holds 4 from then on),
and with the flag clear (any other camera) do neither.

The set-up's copies (FUN_8003401C saves the eyes' strips beside the texture page, FUN_800342A0 the
head palette) run with libgpu's MoveImage stubbed to record its rectangles; they must be what
`gaze.with_saves` and the palette's saved place (`character.PALETTE_TABLE`) say, for both players.

Usage: python3 tools/research/verify_gon_eyes.py [--image <Rev.1 cue>] [--steps N] [--seed S]
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

import character  # noqa: E402
import convert  # noqa: E402
import gaze  # noqa: E402
from harness_common import (CHAR_ID, COSTUME_SLOT, MOVE_COMMAND, PLAYER, read_commands,  # noqa: E402
                            reset_commands)
from common import RELEASES, open_discs  # noqa: E402
from psxcpu import load_release  # noqa: E402

log = logging.getLogger("verify_gon_eyes")

DEFAULT_IMAGE = ROOT / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1).cue"
SET_OFFSET = 0x80034120         # GonEyesSetOffset(fighter, shift)
FIGHTER = 0x801A0000
FIGHTER_BYTES = 0x1AE4
CACHE = 0x1292
PLAYER_ROWS = 0x100             # player 2's texture page lies this many rows lower


def expected(where: gaze.Layout, shift: int, cache: list[int], player: int) -> list[tuple]:
    """The copies GonEyesSetOffset(shift) queues, updating the eyes' `cache`."""
    wanted = (shift if shift >= 0 else 0, shift if shift < 0 else 0)
    rows = PLAYER_ROWS * player
    out = []
    for eye in range(gaze.EYES):
        if wanted[eye] != cache[eye]:
            cache[eye] = wanted[eye]
            e = where.eyes[eye]
            out.append((e.saved[0], e.saved[1] + gaze.SOURCE_ROWS[eye] + wanted[eye] + rows, *where.window_size,
                        e.strip[0], e.strip[1] + gaze.DEST_ROWS[eye] + rows))
    return out


FACE = 0x80034354               # FUN_80034354(fighter): the blink and Gon's face
MOVE = 0x54                     # pointer to the running move row; +0x24 its flags, +4 its state bits
MOVE_ROW = 0x801C0000
OVERHEAD = 0x800B08D4
CHANNEL = 0x127C                # s16 current, +4 target, +8 rate of hand channel 0
PALETTE_SEEN = 0x1291
FLAG_REACT_CHAIN = 0x40000
SHAPE_3_VALUE = 0x202


def check_overhead(cpu, disc, slot: int, problems: list[str]) -> None:
    """FUN_80034354's Gon branch under the overhead KO camera."""
    rects = lambda i: tuple(disc.exe_s16(character.EYE_RECTS + 4 * i, 2))
    size, palette, _, swapped = (b - 256 if b > 127 else b for b in disc.exe_u8(character.PALETTE_TABLE + 4 * slot, 4))
    w, h = disc.exe_s16(character.EYE_SIZES + 4 * size, 2)
    copy = (*rects(swapped), w, h, *rects(palette))
    for overhead in (1, 0):
        cpu.write(FIGHTER, bytes(FIGHTER_BYTES))
        cpu.write(FIGHTER + CHAR_ID, struct.pack("<h", gaze.GON))
        cpu.write(FIGHTER + COSTUME_SLOT, struct.pack("<h", slot))
        cpu.write(MOVE_ROW, bytes(0x40))
        cpu.write(MOVE_ROW + 0x24, struct.pack("<I", FLAG_REACT_CHAIN))
        cpu.write(FIGHTER + MOVE, struct.pack("<I", MOVE_ROW))
        cpu.write(OVERHEAD, bytes([overhead]))
        counts = []
        for call in range(2):
            reset_commands(cpu)
            cpu.call(FACE, FIGHTER)
            counts.append(read_commands(cpu))
        current = struct.unpack("<h", cpu.read(FIGHTER + CHANNEL, 2))[0]
        seen = cpu.read(FIGHTER + PALETTE_SEEN, 1)[0]
        want_copies = [[(MOVE_COMMAND, *copy)], []] if overhead else [[], []]
        want = (SHAPE_3_VALUE, 4) if overhead else (0, 0)
        if counts != want_copies or (current, seen) != want:
            problems.append(f"slot {slot} overhead {overhead}: copies {counts}, jaw value {current:#x}, palette cache {seen}")


MOVE_IMAGE = 0x8007CB34         # libgpu MoveImage(rect, x, y)
SAVE_STRIPS = 0x8003401C        # FUN_8003401C(fighter)
SAVE_PALETTE = 0x800342A0       # FUN_800342A0(fighter)
PALETTE_ROWS = 4                # player 2's CLUT rows lie this far below player 1's


def check_saves(cpu, disc, slot: int, where: gaze.Layout, problems: list[str]) -> None:
    """The copies the fight's set-up makes of Gon's strips and head palette."""
    moves: list[tuple[int, ...]] = []

    def record(c, rect, x, y, _):
        moves.append((*struct.unpack("<4h", c.read(rect, 8)), x & 0xFFFF, y & 0xFFFF))

    cpu.stub(MOVE_IMAGE, record)
    size, palette, backup, _ = (b - 256 if b > 127 else b for b in disc.exe_u8(character.PALETTE_TABLE + 4 * slot, 4))
    rect = lambda i: tuple(disc.exe_s16(character.EYE_RECTS + 4 * i, 2))
    w, h = disc.exe_s16(character.EYE_SIZES + 4 * size, 2)
    for player in range(2):
        cpu.write(FIGHTER, bytes(FIGHTER_BYTES))
        cpu.write(FIGHTER + CHAR_ID, struct.pack("<h", gaze.GON))
        cpu.write(FIGHTER + PLAYER, struct.pack("<h", player))
        cpu.write(FIGHTER + COSTUME_SLOT, struct.pack("<h", slot))
        rows = PLAYER_ROWS * player
        moves.clear()
        cpu.call(SAVE_STRIPS, FIGHTER)
        want = [(*e.strip[:1], e.strip[1] + rows, *where.strip_size, *e.saved[:1], e.saved[1] + rows)
                for e in where.eyes]
        if moves != want:
            problems.append(f"slot {slot} player {player + 1}: the strips' saves {moves}, expected {want}")
        moves.clear()
        cpu.call(SAVE_PALETTE, FIGHTER)
        rows = PALETTE_ROWS * player
        want = [(rect(palette)[0], rect(palette)[1] + rows, w, h, rect(backup)[0], rect(backup)[1] + rows)]
        if moves != want:
            problems.append(f"slot {slot} player {player + 1}: the palette's save {moves}, expected {want}")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--image", default=str(DEFAULT_IMAGE), help="the Japan Rev.1 disc image")
    parser.add_argument("--steps", type=int, default=600)
    parser.add_argument("--seed", type=int, default=5)
    args = parser.parse_args()
    discs = open_discs([Path(args.image)])
    disc = next(discs[r.key] for r in RELEASES if r.key in discs).canonical()
    rng = random.Random(args.seed)
    cpu = load_release()
    problems: list[str] = []
    steps = 0
    for _, slot, _, _ in convert.CHARACTERS:
        where = gaze.layout(disc, character.costume_characters(disc, slot), slot)
        if where is None:
            continue
        for player in range(2):
            cpu.write(FIGHTER, bytes(FIGHTER_BYTES))
            cpu.write(FIGHTER + CHAR_ID, struct.pack("<h", gaze.GON))
            cpu.write(FIGHTER + PLAYER, struct.pack("<h", player))
            cpu.write(FIGHTER + COSTUME_SLOT, struct.pack("<h", slot))
            cache = [0, 0]
            shift = 0
            for step in range(args.steps):
                # Mostly small moves, as the opponent's direction changes, with jumps and repeats.
                shift = max(-17, min(17, shift + rng.choice((-3, -1, 0, 0, 0, 1, 2)))) if rng.random() < 0.8 \
                    else rng.randrange(-17, 18)
                reset_commands(cpu)
                cpu.call(SET_OFFSET, FIGHTER, shift)
                got = read_commands(cpu)
                want = expected(where, shift, cache, player)
                steps += 1
                if got != [(MOVE_COMMAND, *w) for w in want]:
                    problems.append(f"slot {slot} player {player + 1} step {step} shift {shift}: copies {got}, expected {want}")
    for _, slot, _, _ in convert.CHARACTERS:
        if gaze.layout(disc, character.costume_characters(disc, slot), slot) is not None:
            check_overhead(cpu, disc, slot, problems)
            check_saves(cpu, disc, slot, gaze.layout(disc, character.costume_characters(disc, slot), slot), problems)
    for p in problems[:20]:
        log.error(p)
    log.info("%d GonEyesSetOffset calls on 2 slots and both players compared with the converter's model; %d differences",
             steps, len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
