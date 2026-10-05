#!/usr/bin/env python3
"""Check how the arcade chooses its characters' vertex variants (FUN_80194458, the PlayStation's
FighterHandPoses) against a model written from its decompilation, in the CPU harness.

The routine runs on a synthetic fighter record of the arcade program: a costume slot, the airborne
flag (+0x1158), the wing counter and phase (+0x115C, +0x1160), the two hand channels (+0x1164
current, +0x1168 target, +0x116C rate) and True Ogre's level (+0x1178). Each of the 24 part rows
(fighter + 0x48C + 0x1C·row) points to a (block, table) pair whose 41 table entries are markers,
so the block each row ends up with names the variant the game selected.

For True Ogre (costume slots 0x20 and 0x21) a random airborne script of 600 steps is run row by
row: row 1 (the wings) must take the variant the wing sequence gives (the tables at 0x801FCF30 and
0x801FCF44, the counter stepping by one), rows 18 and 19 the level >> 4 of channel 0. For the other
costumes rows 10 and 6 (rows 2 for slots 0x16 and 0x17 on channel 0) take
`value >> 4` up to 0x200 and `value − 0x1E0` above. Then the converter's data are checked against
the routine on the real models: each costume slot's file is relocated in RAM as the loader does and
the routine runs on a fighter whose hand rows (arcade_character.hand_rows: 10 and 6, row 2 for the
jaws of slots 0x16 and 0x17) point at the file's own block tables, with random channel values; the
vertex block each row ends up with must be the one of the variant the remake shows
(`ArcadePoses.hand_variant` and the group's `select`, here `remake_variant`), and rows the converter
has no group for must keep their base block. It also reports how the PlayStation's wing
sequence (FighterHands._update_wings, the remake's simulation) differs: the same tables, but its
opening steps the counter by two.

FUN_80197578 (the load turn of a swinging attachment, which turns its first 17 variant blocks too)
is run on True Ogre's models as the loader leaves them (FUN_80196e30 relocates the file in RAM):
the turned base and variant blocks of rows 18 and 19 must be the ones `arcade_kmd.variant` gives.

Usage: python3 tools/research/verify_arcade_wings.py [--zip tekken3_mame.zip] [--steps N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
import sys
from pathlib import Path

from arcade_cpu import DEFAULT_ZIP, arcade, arcade_cpu  # puts tools/remake_import on the path

import arcade_character  # noqa: E402
import arcade_kmd  # noqa: E402
import character  # noqa: E402

log = logging.getLogger("verify_arcade_wings")

POSES = 0x80194458             # FUN_80194458(fighter)
FIGHTER = 0x8031E154
SLOT = 0x1E
AIRBORNE = 0x1158              # s32: the PlayStation's +0x128A
WING_FRAME, WING_PHASE = 0x115C, 0x1160
CURRENT, TARGET, RATE = 0x1164, 0x1168, 0x116C   # s16 per hand channel, 2 bytes apart
OGRE_LEVEL = 0x1178            # s16 current, +2 target, +4 rate
ROW_POINTERS = 0x48C           # per row, 0x1C bytes apart: the pointer to its (block, table) pair
ROW_STRIDE = 0x1C
PAUSES = (0x8021FBD0, 0x8021FAD0)
REPLAY_MODE = 0x8021F640       # 0: the recorder hooks return their argument
WING_TABLES = (0x801FCF30, 0x801FCF44)
TABLE_BYTES = 0x40
SCRATCH = 0x803A0000
MODEL = 0x803B0000
RELOCATE = 0x80196E30          # FUN_80196E30(model, rows): the loader's pointer relocation
LOAD_TURN = 0x80197578         # FUN_80197578(model, row, s16 angles[3])
ANGLES = 0x803AF000
ROW_BYTES = 0x38
ROWS = 24
VARIANTS = 41
OGRE_SLOTS = (0x20, 0x21)
WING_ROW, TAIL_ROWS = 1, (18, 19)
HAND_ROWS = (10, 6)
JAW_SLOTS = (0x16, 0x17)
JAW_ROW = 2
FIST = 0x200
SHAPE_BASE = 0x1E0
PLAYSTATION_STEP = 2            # the PlayStation's opening and first beat step


def marker(row: int, k: int) -> int:
    return 0x10000 * (row + 1) + k + 1


def sequence_tables(arc) -> tuple[list[int], list[int]]:
    """The wing tables (s8, −1 ends) as read from the program."""
    out = []
    for address in WING_TABLES:
        raw = arc.prog(address, TABLE_BYTES)
        values = [b - 256 if b > 127 else b for b in raw]
        out.append(values[:values.index(-1) + 1])
    return out[0], out[1]


class Wings:
    """True Ogre's wing sequence: FUN_80194458's branch steps the counter by one in both phases
    (the defaults); the PlayStation's steps by two while opening and by two on the first beat."""

    def __init__(self, opening: list[int], beat: list[int], open_step: int = 1, first_beat_step: int = 1) -> None:
        self.opening, self.beat, self.open_step, self.first_beat_step = opening, beat, open_step, first_beat_step
        self.phase = self.frame = self.first = 0

    def update(self, airborne: bool) -> int:
        if self.phase == 0:
            if not airborne:
                if self.frame:
                    self.frame -= 1
            else:
                self.frame += self.open_step
                if self.opening[self.frame] == -1:
                    self.phase, self.frame, self.first = 1, 0, 1
        else:
            self.frame += self.first_beat_step if self.first else 1
            self.first = 0
            if self.beat[self.frame] == -1:
                if airborne:
                    self.frame = 0
                else:
                    self.frame, self.phase = 0x10, 0
        return (self.opening if self.phase == 0 else self.beat)[self.frame]


class Fighter:
    def __init__(self, cpu) -> None:
        self.cpu = cpu
        self.markers()
        cpu.write(REPLAY_MODE, bytes(4))
        for address in PAUSES:
            cpu.write(address, bytes(4))

    def markers(self) -> None:
        """Every row's table holds markers: the block a row ends up with names its variant."""
        for k in range(ROWS):
            pair = SCRATCH + 0x400 * k
            table = pair + 0x10
            self.cpu.write(pair + 4, struct.pack("<I", table))
            self.cpu.write(table, struct.pack(f"<{VARIANTS}I", *(marker(k, i) for i in range(VARIANTS))))

    def reset(self, slot: int) -> None:
        self.cpu.write(FIGHTER, bytes(0x1AE4))
        self.cpu.write(FIGHTER + SLOT, struct.pack("<h", slot))
        for k in range(ROWS):
            pair = SCRATCH + 0x400 * k
            self.cpu.write(pair, bytes(4))
            self.cpu.write(FIGHTER + ROW_POINTERS + ROW_STRIDE * k, struct.pack("<I", pair))

    def put(self, offset: int, fmt: str, *values: int) -> None:
        self.cpu.write(FIGHTER + offset, struct.pack(fmt, *values))

    def get(self, offset: int, fmt: str) -> tuple:
        return struct.unpack(fmt, self.cpu.read(FIGHTER + offset, struct.calcsize(fmt)))

    def variant(self, row: int) -> int:
        """The variant the row shows, −1 while it still has its base block."""
        (block,) = struct.unpack("<I", self.cpu.read(SCRATCH + 0x400 * row, 4))
        return -1 if block == 0 else (block & 0xFFFF) - 1

    def poses(self) -> None:
        self.cpu.call(POSES, FIGHTER)


def check_ogre(fighter: Fighter, arc, rng: random.Random, steps: int) -> list[str]:
    opening, beat = sequence_tables(arc)
    log.info("opening %s", opening)
    log.info("beat %s", beat)
    problems = []
    for slot in OGRE_SLOTS:
        fighter.reset(slot)
        model = Wings(opening, beat)
        airborne = False
        seen_rows: set[int] = set()
        for step in range(steps):
            if rng.random() < 0.08:
                airborne = not airborne
            fighter.put(AIRBORNE, "<i", int(airborne))
            if step % 50 == 0:
                target = rng.choice((0, FIST // 2))
                fighter.put(TARGET, "<h", target)
                fighter.put(RATE, "<h", rng.randrange(1, 40))
                fighter.put(OGRE_LEVEL + 2, "<h", rng.choice((0, 0x100)))
                fighter.put(OGRE_LEVEL + 4, "<h", rng.randrange(0, 60))
            fighter.poses()
            wing = model.update(airborne)
            if (fighter.get(WING_FRAME, "<i")[0], fighter.get(WING_PHASE, "<i")[0]) != (model.frame, model.phase):
                problems.append(f"slot {slot:#x} step {step}: counter {fighter.get(WING_FRAME, '<i')[0]}/"
                                f"{fighter.get(WING_PHASE, '<i')[0]} against {model.frame}/{model.phase}")
            if fighter.variant(WING_ROW) != wing:
                problems.append(f"slot {slot:#x} step {step}: wing variant {fighter.variant(WING_ROW)} against {wing}")
            level = fighter.get(CURRENT, "<h")[0]
            for row in TAIL_ROWS:
                if fighter.variant(row) != level >> 4:
                    problems.append(f"slot {slot:#x} step {step}: row {row} variant {fighter.variant(row)} "
                                    f"against {level >> 4}")
            seen_rows.add(fighter.variant(WING_ROW))
        log.info("slot %#x: wing variants seen %s", slot, sorted(seen_rows))
    return problems


def check_hands(fighter: Fighter, rng: random.Random, steps: int) -> list[str]:
    problems = []
    for slot in (0, 5, 17, 40, *JAW_SLOTS):
        fighter.reset(slot)
        for step in range(steps):
            if step % 20 == 0:
                for c in range(2):
                    fighter.put(TARGET + 2 * c, "<h", rng.choice((0, FIST, FIST + rng.randrange(1, 8), rng.randrange(0, FIST))))
                    fighter.put(RATE + 2 * c, "<h", rng.randrange(1, 60))
            fighter.poses()
            for c in range(2):
                value = fighter.get(CURRENT + 2 * c, "<h")[0]
                want = value >> 4 if value < FIST + 1 else value - SHAPE_BASE
                row = JAW_ROW if c == 0 and slot in JAW_SLOTS else HAND_ROWS[c]
                if fighter.variant(row) != want:
                    problems.append(f"slot {slot} step {step}: channel {c} row {row} variant "
                                    f"{fighter.variant(row)} against {want} (value {value:#x})")
    return problems


def read_block(cpu, pointer: int) -> list[tuple[int, int, int]]:
    """The vertices of the block at `pointer` in RAM (a u32 count, then 8 bytes each)."""
    (n,) = struct.unpack("<I", cpu.read(pointer, 4))
    return [struct.unpack("<3h", cpu.read(pointer + 4 + 8 * i, 6)) for i in range(n)]


def remake_variant(value: int) -> int:
    """The variant the remake shows for a hand channel's value (ArcadePoses.hand_variant)."""
    return value >> 4 if value <= FIST else value - SHAPE_BASE


def check_converted_hands(fighter: Fighter, arc, rng: random.Random, steps: int) -> list[str]:
    """The routine run on every costume's relocated file: the block each hand (or jaw) row shows
    is the converter's coordinates of the variant the remake selects from the channel's value."""
    problems = []
    cpu = fighter.cpu
    sine = list(arc.prog_table(f"<{arcade_kmd.SINE_ENTRIES}h", arcade_kmd.SINE))
    checked = 0
    for slot in range(arcade_character.SLOTS):
        if not arcade_character.replaces(slot) or slot in OGRE_SLOTS:
            continue
        data, _ = arcade_character.costume(arc, slot)
        enable = arc.prog(arcade_kmd.ATTACHMENT_ENABLE + arcade_kmd.ATTACHMENTS * slot, arcade_kmd.ROWS)
        model = arcade_kmd.parse(data)
        arcade_kmd.turn_attachments(model, arcade_kmd.load_turns(arc.prog_values, slot, enable), sine)
        groups = {g.channel: g for g in arcade_character.pose_groups(data, model, slot) if g.key == character.HANDS}
        cpu.write(MODEL, data)
        cpu.call(RELOCATE, MODEL, arcade_kmd.ROWS)
        fighter.markers()
        fighter.reset(slot)
        base = {}
        rows = arcade_character.hand_rows(slot)
        for row in {10, 6, JAW_ROW}:
            words = struct.unpack("<2I", cpu.read(MODEL + arcade_kmd.HEADER_BYTES + ROW_BYTES * row, 8))
            cpu.write(SCRATCH + 0x400 * row + 4, struct.pack("<I", words[1]))     # the file's variant table (0: none)
            base[row] = words[0]
        for step in range(steps):
            if step % 20 == 0:
                for c in range(2):
                    fighter.put(TARGET + 2 * c, "<h", rng.choice((0, FIST, FIST + rng.randrange(1, 9), rng.randrange(0, FIST))))
                    fighter.put(RATE + 2 * c, "<h", rng.randrange(1, 60))
            fighter.poses()
            for c, (row, _) in enumerate(rows):
                value = fighter.get(CURRENT + 2 * c, "<h")[0]
                (pointer,) = struct.unpack("<I", cpu.read(SCRATCH + 0x400 * row, 4))
                shown = read_block(cpu, pointer or base[row])
                group = groups.get(c)
                if group is None:
                    if pointer not in (0, base[row]):
                        problems.append(f"slot {slot} step {step}: row {row} changed without a group")
                    continue
                want = group.coords[row][group.select[remake_variant(value)]]
                checked += 1
                if shown != want:
                    problems.append(f"slot {slot} step {step}: channel {c} row {row} value {value:#x}: the block differs "
                                    f"from the converter's variant {remake_variant(value)}")
    log.info("%d hand and jaw blocks compared with the converter's groups", checked)
    fighter.markers()
    return problems


def check_load_turns(arc, cpu) -> list[str]:
    """The base and variant blocks of True Ogre's attachment rows after FUN_80197578, in RAM,
    against arcade_kmd's turned blocks."""
    problems = []
    sine = list(arc.prog_table(f"<{arcade_kmd.SINE_ENTRIES}h", arcade_kmd.SINE))
    for slot in OGRE_SLOTS:
        data, _ = arcade_character.costume(arc, slot)
        enable = arc.prog(arcade_kmd.ATTACHMENT_ENABLE + arcade_kmd.ATTACHMENTS * slot, arcade_kmd.ROWS)
        turns = arcade_kmd.load_turns(arc.prog_values, slot, enable)
        model = arcade_kmd.parse(data)
        arcade_kmd.turn_attachments(model, turns, sine)
        cpu.write(MODEL, data)
        cpu.call(RELOCATE, MODEL, arcade_kmd.ROWS)
        for row in sorted(turns):
            cpu.write(ANGLES, struct.pack("<3h", *turns[row]))
            cpu.call(LOAD_TURN, MODEL, row, ANGLES)

        for row in sorted(turns):
            words = struct.unpack("<5I", cpu.read(MODEL + arcade_kmd.HEADER_BYTES + ROW_BYTES * row, 20))
            if read_block(cpu, words[0]) != model.rows[row].verts.coords:
                problems.append(f"slot {slot:#x} row {row}: turned base block differs")
            if not words[1]:
                continue
            for k, pointer in enumerate(struct.unpack(f"<{arcade_kmd.VARIANTS}I", cpu.read(words[1], 4 * arcade_kmd.VARIANTS))):
                if read_block(cpu, pointer) != arcade_kmd.variant(data, model, row, k).coords:
                    problems.append(f"slot {slot:#x} row {row}: variant {k} differs after the load turn")
        log.info("slot %#x: rows %s turned and compared", slot, sorted(turns))
    return problems


def playstation_difference(arc, rng: random.Random, steps: int) -> int:
    """Steps where the PlayStation's sequence shows another variant than the arcade's."""
    opening, beat = sequence_tables(arc)
    ps_opening = opening + [-1]            # the PlayStation reads two steps at a time: 0x80095CAC has 20 bytes
    arcade_wings, ps = Wings(opening, beat), Wings(ps_opening, beat, PLAYSTATION_STEP, PLAYSTATION_STEP)
    airborne, different = False, 0
    for _ in range(steps):
        if rng.random() < 0.05:
            airborne = not airborne
        different += arcade_wings.update(airborne) != ps.update(airborne)
    return different


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", default=str(DEFAULT_ZIP))
    parser.add_argument("--steps", type=int, default=600)
    parser.add_argument("--seed", type=int, default=3)
    args = parser.parse_args()
    arc = arcade.open_set(Path(args.zip))
    fighter = Fighter(arcade_cpu(arc))
    rng = random.Random(args.seed)
    cpu = fighter.cpu
    problems = (check_ogre(fighter, arc, rng, args.steps) + check_hands(fighter, rng, args.steps)
                + check_load_turns(arc, cpu) + check_converted_hands(fighter, arc, rng, args.steps))
    for p in problems[:20]:
        log.error(p)
    log.info("%d differences from the model (%d shown)", len(problems), min(len(problems), 20))
    log.info("PlayStation's wing sequence shows another variant in %d of %d steps",
             playstation_difference(arc, rng, args.steps), args.steps)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
