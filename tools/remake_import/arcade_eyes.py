"""The arcade's eye shapes (docs/research/arcade/README.md#eye-shapes).

A costume slot's face texture has up to six eye shapes, rectangles of the texture pages that the
game copies over the eyes' own rectangle as the fighter's face changes (`FUN_80193ea4`; shape 0 is
the eyes as loaded). The converter writes one atlas per shape the game selects (character.py
`write_model`, `eyes`), and the model's record says when each is shown (`record`; the remake:
ArcadeFace).
"""

from __future__ import annotations

import struct

import arcade
import character
from vram import Vram

LAYOUT = 0x801FE370              # per costume slot, 8 s8: eyes' rectangle, size, shapes 0–5 (-1: none)
LAYOUT_BYTES = 8
RECTS = 0x801FCE98               # (x, y) s16 VRAM positions
SIZES = 0x801FCF1C               # (w, h) s16 in VRAM words
SHAPES = 6
FIRST_SHAPE_BYTE = 2
# s8 per costume slot (0x29): the shape of the blink (shape 0: the costume does not blink), of a
# move with the closed-eyes flag and of a lying fighter (FUN_8019cc68, FUN_8019cc94, FUN_8019ccc0).
SLOTS = 0x29
BLINK, HELD, DOWN = 0x801FE4B8, 0x801FE4E4, 0x801FE510
# FUN_8019cac0: the character of costume slot k is the id whose four colours (s8, -1: none) list
# it; ids 16–21 repeat other characters' costumes.
CHARACTER_SLOTS = 0x801FE060
CHARACTER_COLOURS = 4
CHARACTER_IDS = 22
# FUN_801A1C74(fighter, voice id): while a character shouts an attack voice (voice codes 0x2000 on,
# played by FUN_801A104C) the face takes a shape for as many frames as the voice sample lasts, by
# character id (the fighter's +0x1A); it ends with FUN_80194080(fighter, 0, 10 + shape, frames).
# `shouts` runs the routine's own instructions on the program to read them.
SHOUT = 0x801A1C74
SHOUT_FACE = 0x80194080
SHOUT_CHARACTER = 0x1A
SHOUT_FIRST = 0x2000
SHOUT_CODES = 9
SHOUT_SHAPE_BASE = 10                    # the shape is the face command's value − 10
SHOUT_STEPS = 400                        # the longest run is about 70 instructions
NO_SHAPE = -1


class ShoutError(ValueError):
    """The shout routine does something the small interpreter does not know."""


def _signed(value: int, bits: int) -> int:
    return value - (1 << bits) if value >> (bits - 1) else value


def run_shout(arc: arcade.ArcadeSet, character: int, code: int) -> tuple[int, int] | None:
    """The (value, frames) FUN_801A1C74 passes to FUN_80194080 for character id `character` and voice
    code `code`, or None when it returns without calling it. Its instructions are interpreted from
    the program: the integer, shift, load and branch instructions it is made of, with the delay
    slots, and nothing else (the fighter record is just the character id at +0x1A)."""
    regs = [0] * 32
    regs[4], regs[5] = 0x1000, code
    pc = SHOUT

    def execute(word: int) -> None:
        op, rs, rt, rd = word >> 26, word >> 21 & 31, word >> 16 & 31, word >> 11 & 31
        imm = word & 0xFFFF
        value = None
        if op == 0:
            funct = word & 63
            if funct == 0:                                       # sll (nop: all zero)
                value = regs[rt] << (word >> 6 & 31)
            elif funct == 3:                                     # sra
                value = _signed(regs[rt], 32) >> (word >> 6 & 31)
            elif funct in (0x21, 0x25):                          # addu, or (move)
                value = regs[rs] + regs[rt] if funct == 0x21 else regs[rs] | regs[rt]
            else:
                raise ShoutError(f"special {funct:#x} at {pc:#x}")
            target = rd
        elif op == 0x09:                                         # addiu
            value, target = regs[rs] + _signed(imm, 16), rt
        elif op == 0x0D:                                         # ori
            value, target = regs[rs] | imm, rt
        elif op == 0x0A:                                         # slti
            value, target = int(_signed(regs[rs], 32) < _signed(imm, 16)), rt
        elif op == 0x0F:                                         # lui
            value, target = imm << 16, rt
        elif op == 0x21 and regs[rs] + _signed(imm, 16) == regs[4] + SHOUT_CHARACTER:   # lh of the character id
            value, target = character & 0xFFFF, rt
            value = _signed(value, 16)
        elif op in (0x23, 0x2B):                                 # lw of the saved ra, sw of it
            value, target = 0, rt
            if op == 0x2B:
                return
        else:
            raise ShoutError(f"opcode {op:#x} at {pc:#x}")
        if target:
            regs[target] = value & 0xFFFFFFFF

    for _ in range(SHOUT_STEPS):
        word = struct.unpack("<I", arc.prog(pc, 4))[0]
        op = word >> 26
        branch = op in (0x02, 0x03, 0x04, 0x05) or (op == 0 and word & 63 == 8)
        if not branch:
            execute(word)
            pc += 4
            continue
        slot = struct.unpack("<I", arc.prog(pc + 4, 4))[0]
        rs, rt = word >> 21 & 31, word >> 16 & 31
        target = pc + 8
        if op in (0x04, 0x05):
            if (regs[rs] == regs[rt]) == (op == 0x04):
                target = pc + 4 + (_signed(word & 0xFFFF, 16) << 2)
        elif op in (0x02, 0x03):
            target = (pc + 4 & 0xF0000000) | (word & 0x3FFFFFF) << 2
        else:                                                    # jr
            return None
        execute(slot)
        if op == 0x03:
            if target != SHOUT_FACE:
                raise ShoutError(f"call of {target:#x} at {pc:#x}")
            return regs[6], regs[7]
        pc = target
    raise ShoutError("the routine does not return")


def shouts(arc: arcade.ArcadeSet) -> dict[int, tuple[int, tuple[int, ...]]]:
    """Per character id that shouts: its face shape and the frames of each of its SHOUT_CODES voices.
    Read once per program."""
    found = getattr(arc, "_shouts", None)
    if found is None:
        found = {}
        for char in range(CHARACTER_IDS):
            calls = [run_shout(arc, char, SHOUT_FIRST + k) for k in range(SHOUT_CODES)]
            if not any(calls):
                continue
            values = {c[0] for c in calls if c}
            if len(values) != 1:
                raise ShoutError(f"character {char} shows more than one shape: {sorted(values)}")
            found[char] = (values.pop() - SHOUT_SHAPE_BASE, tuple(c[1] if c else 0 for c in calls))
        arc._shouts = found
    return found


def layout(arc: arcade.ArcadeSet, slot: int) -> tuple[int, ...]:
    return struct.unpack(f"<{LAYOUT_BYTES}b", arc.prog(LAYOUT + LAYOUT_BYTES * slot, LAYOUT_BYTES))


def slot_table(arc: arcade.ArcadeSet, base: int, slot: int) -> int:
    return struct.unpack("<b", arc.prog(base + slot, 1))[0] if slot < SLOTS else 0


def character_id(arc: arcade.ArcadeSet, slot: int) -> int | None:
    """The first character id with costume `slot`, or None."""
    table = arc.prog_table(f"<{CHARACTER_IDS * CHARACTER_COLOURS}b", CHARACTER_SLOTS)
    return next((k // CHARACTER_COLOURS for k, s in enumerate(table) if s == slot), None)


def shapes_of(arc: arcade.ArcadeSet, slot: int) -> list[bool]:
    """Which shapes 0–5 the slot has, as rectangles it can copy over its eyes."""
    lay = layout(arc, slot)
    if min(lay[0], lay[1]) < 0:
        return [False] * SHAPES
    return [lay[FIRST_SHAPE_BYTE + k] >= 0 for k in range(SHAPES)]


def roles(arc: arcade.ArcadeSet, slot: int) -> dict[str, int]:
    """The shapes the game shows for the blink, a closed-eyes move, a lying fighter and a shout
    (0: the eyes as loaded, NO_SHAPE: the slot lacks that shape: the face stays as it is)."""
    have = shapes_of(arc, slot)
    char = character_id(arc, slot)

    def available(shape: int) -> int:
        return shape if 0 <= shape < SHAPES and have[shape] else NO_SHAPE

    return {
        "blink": available(slot_table(arc, BLINK, slot)),
        "held": available(slot_table(arc, HELD, slot)),
        "down": available(slot_table(arc, DOWN, slot)),
        "shout": available(shouts(arc)[char][0]) if char in shouts(arc) else 0,
    }


def record(arc: arcade.ArcadeSet, slot: int) -> dict | None:
    """The model.json record of the slot's eyes: `roles`, and for a shouting character the
    frames of each of its nine voices. None when the slot's eyes never change."""
    if not any(shapes_of(arc, slot)):
        return None
    char = character_id(arc, slot)
    shape = roles(arc, slot)
    return {**shape, "shout_frames": list(shouts(arc)[char][1]) if char in shouts(arc) else []}


def copies(arc: arcade.ArcadeSet, slot: int) -> dict[int, tuple[tuple, tuple]]:
    """The copy that shows each shape 1–5 the slot's roles use, ((x, y, w, h), (dx, dy)): the
    shape's rectangle over the eyes'."""
    eyes = record(arc, slot)
    if eyes is None:
        return {}
    lay = layout(arc, slot)
    w, h = arc.prog_values("<2h", SIZES + 4 * lay[1])
    dest = arc.prog_values("<2h", RECTS + 4 * lay[0])
    used = {eyes[role] for role in ("blink", "held", "down", "shout")} - {0, NO_SHAPE}
    return {shape: ((*arc.prog_values("<2h", RECTS + 4 * lay[FIRST_SHAPE_BYTE + shape]), w, h), dest)
            for shape in sorted(used)}


def images(arc: arcade.ArcadeSet, slot: int, vram: Vram) -> dict[int, Vram]:
    """The costume's VRAM with each of `copies` made."""
    return {shape: character.eye_image(vram, copy) for shape, copy in copies(arc, slot).items()}
