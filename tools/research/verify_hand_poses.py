#!/usr/bin/env python3
"""Check the PlayStation's vertex variants of the hands and the jaw (FighterHandPoses, 0x80034BC4)
against the converter's variant groups (character.pose_groups), in the CPU harness.

For every costume slot the model file is placed in RAM and relocated by KmdRelocate (0x80035138),
and a synthetic fighter record gets what FighterBuildPartPrims leaves in each draw part (+0x4F8 +
0x28 · part: the pointer to its row's (block, variant table) pair, +0x4FC the second mesh's):
the KMD row addresses. The two hand channels (+0x127C current, +0x1280 target, +0x1284 rate) are
driven by random scripts and FighterHandPoses runs on every step (the replay recorder passes the
values through: mode 0). The vertex block each row ends up with must be

- for the rows of the part the channel selects (character.hand_parts: part 16 and part 12, but part
  17 for channel 0 of Kuma and Panda, character 11, and Gon, 0x11, whose head rows 19 and 20 are
  the jaw) that have variants, the converter's coordinates of the variant the remake shows for the
  channel's value (`FighterHands.variant_of`, and the group's `select`),
- the base block everywhere else (rows without a table are left as they are, and so are the rows
  of other parts).

Gon's head palette (the part of PartSelectVertexVariant that copies a VRAM rectangle) is switched
off (+0x800B08D4 set) there and checked on its own (`check_palette`): the copies the routine queues
(FUN_80029610's command list) must be the ones the remake derives from the channels' variants (swap
from the converter's `character.palette_copy` for the variants 4 and 5, else back from the saved
palette (220, 506), whenever the variant differs from the last one seen, channel 0's then channel 1's).

Usage: python3 tools/research/verify_hand_poses.py [--image <Rev.1 cue>] [--steps N] [--seed S]
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
import kmd as kmdlib  # noqa: E402
import tables  # noqa: E402
from common import RELEASES, open_discs  # noqa: E402
from harness_common import (CHAR_ID, COSTUME_SLOT, MOVE_COMMAND, PLAYER, read_commands,  # noqa: E402
                            reset_commands)
from psxcpu import load_release  # noqa: E402

log = logging.getLogger("verify_hand_poses")

DEFAULT_IMAGE = ROOT / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1).cue"
HAND_POSES = 0x80034BC4         # FighterHandPoses(fighter)
KMD_RELOCATE = 0x80035138       # KmdRelocate(kmd, rows, fighter)
MODEL = 0x80150000
FIGHTER = 0x801A0000
FIGHTER_BYTES = 0x1AE4
PLAYER_ROWS = 4                 # player 2's CLUT rows lie this far below player 1's
PALETTE_SEEN = 0x1291           # u8: the variant the palette was last swapped for
CURRENT, TARGET, RATE = 0x127C, 0x1280, 0x1284   # s16 per hand channel, 2 bytes apart
PART_ROWS = 0x4F8               # per part, 0x28 bytes apart: pointer to the row, +4 the second mesh's
PART_STRIDE = 0x28
REPLAY_MODE = 0x8009C050        # 0: ReplayHandPose returns its argument
SKIP_FLAGS = (0x800958B8, 0x8009588C)       # FighterHandPoses returns while either is set
GON_MOUTH_OFF = 0x800B08D4      # non-zero: PartSelectVertexVariant leaves Gon's mouth texture alone
TRUE_OGRE = 0x14                # animates wings instead: not a hand
FIST = 0x200


def variant_of(value: int) -> int:
    """The variant a channel value selects (FighterHands.variant_of)."""
    return value - (FIST - 3) if value > FIST else max((value >> 7) - 1, 0)


def character_of(disc, slot: int) -> int | None:
    """The character id whose costume key maps to the slot (the first one), None if none does."""
    keys = disc.exe_u8(tables.COSTUME_KEYS, tables.COSTUME_KEY_COUNT)
    return next((key // 4 for key, key_slot in enumerate(keys) if key_slot == slot), None)


def prepare(cpu, data: bytes, char_id: int, slot: int):
    """Places the model in RAM, relocates it and gives a zeroed fighter record the row pointers
    FighterBuildPartPrims leaves; returns (the row's address function, each row's base block pointer)."""
    cpu.write(MODEL, data)
    cpu.write(FIGHTER, bytes(FIGHTER_BYTES))
    cpu.write(FIGHTER + CHAR_ID, struct.pack("<h", char_id))
    cpu.write(FIGHTER + COSTUME_SLOT, struct.pack("<h", slot))
    cpu.call(KMD_RELOCATE, MODEL, kmdlib.ROW_COUNT, FIGHTER)
    row_address = lambda row: MODEL + kmdlib.HEADER_BYTES + kmdlib.ROW_BYTES * row
    base = {row: struct.unpack("<I", cpu.read(row_address(row), 4))[0] for row in range(kmdlib.ROW_COUNT)}
    for part, row in enumerate(kmdlib.PART_ROW):
        rows = [row] + ([row + 1] if part in character.SECOND_MESH_PARTS else [])
        pointers = [row_address(r) if base[r] else 0 for r in rows] + [0]
        cpu.write(FIGHTER + PART_ROWS + PART_STRIDE * part, struct.pack("<2I", *pointers[:2]))
    cpu.write(REPLAY_MODE, bytes(4))
    for flag in SKIP_FLAGS:
        cpu.write(flag, bytes(4))
    return row_address, base


def check_slot(cpu, disc, slot: int, kmd_id: int, rng: random.Random, steps: int) -> tuple[list[str], int]:
    data = disc.bns(kmd_id)
    char_id = character_of(disc, slot)
    if char_id is None or char_id == TRUE_OGRE:
        return [], 0
    model = kmdlib.parse(data)
    jaw = character.has_jaw(character.costume_characters(disc, slot))
    groups = {g.channel: g for g in character.pose_groups(data, model, jaw)}
    row_address, base = prepare(cpu, data, char_id, slot)
    cpu.write(GON_MOUTH_OFF, b"\x01")
    problems = []
    compared = 0
    for step in range(steps):
        if step % 20 == 0:
            for c in range(2):
                cpu.write(FIGHTER + TARGET + 2 * c, struct.pack("<h", rng.choice(
                    (0, FIST, FIST + rng.randrange(1, 7), rng.randrange(0, FIST)))))
                cpu.write(FIGHTER + RATE + 2 * c, struct.pack("<h", rng.randrange(1, 60)))
        cpu.call(HAND_POSES, FIGHTER)
        ram = cpu.read(MODEL, len(data))
        channel_rows = {}
        for c, part in enumerate(character.hand_parts(jaw)):
            for row in character.part_rows(part):
                channel_rows[row] = c
        for row in range(kmdlib.ROW_COUNT):
            (pointer,) = struct.unpack("<I", cpu.read(row_address(row), 4))
            c = channel_rows.get(row)
            group = groups.get(c) if c is not None else None
            if group is None or row not in group.coords:
                if pointer != base[row]:
                    problems.append(f"slot {slot} step {step}: row {row} changed without a group")
                continue
            value = struct.unpack("<h", cpu.read(FIGHTER + CURRENT + 2 * c, 2))[0]
            shown = kmdlib.parse_vertex_block(ram, pointer - MODEL, len(ram), normals=False).coords
            want = group.coords[row][group.select[variant_of(value)]]
            compared += 1
            if shown != want:
                problems.append(f"slot {slot} step {step}: channel {c} row {row} value {value:#x}: the block differs "
                                f"from the converter's variant {variant_of(value)}")
    return problems, compared


def check_palette(cpu, disc, slot: int, kmd_id: int, rng: random.Random, steps: int) -> tuple[list[str], int]:
    """Gon's head palette: the copies FighterHandPoses queues (PartSelectVertexVariant) for random
    channel scripts, for both players, against what the remake shows (`character.palette_copy`)."""
    char_id = character_of(disc, slot)
    copy = character.palette_copy(disc, character.costume_characters(disc, slot), slot)
    if copy is None:
        return [], 0
    (sx, sy, w, h), (dx, dy) = copy
    _, _, backup, _ = (b - 256 if b > 127 else b for b in disc.exe_u8(character.PALETTE_TABLE + 4 * slot, 4))
    bx, by = disc.exe_s16(character.EYE_RECTS + 4 * backup, 2)
    problems = []
    compared = 0
    for player in range(2):
        prepare(cpu, disc.bns(kmd_id), char_id, slot)
        cpu.write(GON_MOUTH_OFF, b"\x00")
        cpu.write(FIGHTER + PLAYER, struct.pack("<h", player))
        rows = PLAYER_ROWS * player
        seen = 0
        for step in range(steps):
            if step % 20 == 0:
                for c in range(2):
                    cpu.write(FIGHTER + TARGET + 2 * c, struct.pack("<h", rng.choice(
                        (0, FIST, FIST + rng.randrange(1, 7), rng.randrange(0, FIST)))))
                    cpu.write(FIGHTER + RATE + 2 * c, struct.pack("<h", rng.randrange(1, 60)))
            reset_commands(cpu)
            cpu.call(HAND_POSES, FIGHTER)
            got = read_commands(cpu)
            want = []
            for c in range(2):
                v = variant_of(struct.unpack("<h", cpu.read(FIGHTER + CURRENT + 2 * c, 2))[0])
                if v != seen:
                    seen = v
                    x, y = (sx, sy) if v in character.PALETTE_SWAP_VARIANTS else (bx, by)
                    want.append((x, y + rows, w, h, dx, dy + rows))
            compared += 1
            if got != [(MOVE_COMMAND, *x) for x in want]:
                problems.append(f"slot {slot} player {player} step {step}: palette copies {got}, expected {want}")
            if (v := cpu.read(FIGHTER + PALETTE_SEEN, 1)[0]) != seen:
                problems.append(f"slot {slot} step {step}: last variant seen {v}, expected {seen}")
    return problems, compared


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--image", default=str(DEFAULT_IMAGE), help="the Japan Rev.1 disc image")
    parser.add_argument("--steps", type=int, default=400)
    parser.add_argument("--seed", type=int, default=5)
    args = parser.parse_args()
    discs = open_discs([Path(args.image)])
    disc = next(discs[r.key] for r in RELEASES if r.key in discs).canonical()
    rng = random.Random(args.seed)
    cpu = load_release()
    problems: list[str] = []
    compared = 0
    slots = 0
    for _, slot, kmd_id, _ in convert.CHARACTERS:
        found, count = check_slot(cpu, disc, slot, kmd_id, rng, args.steps)
        problems += found
        compared += count
        slots += 1 if count else 0
        if count and character.has_jaw(character.costume_characters(disc, slot)):
            log.info("slot %d (character %d): jaw checked, %d blocks", slot, character_of(disc, slot), count)
    swaps = 0
    for _, slot, kmd_id, _ in convert.CHARACTERS:
        found, count = check_palette(cpu, disc, slot, kmd_id, rng, 2 * args.steps)
        problems += found
        swaps += count
        if count:
            log.info("slot %d: Gon's palette copies checked over %d steps", slot, count)
    for p in problems[:20]:
        log.error(p)
    log.info("%d blocks of %d costume slots with variants compared with the converter's groups, %d palette steps; "
             "%d differences", compared, slots, swaps, len(problems))
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
