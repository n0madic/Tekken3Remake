#!/usr/bin/env python3
"""Random cases of Yoshimitsu's sword glow (FUN_8003161C and FUN_80031980) run in the CPU harness.

Each case sets up a fighter record (character, bank type, costume slot, player), the fighters'
view (rotation, translation, projection plane H, screen offsets 192 and 240 as the fight's display
mode has them), joint block 10 and the frame's display buffer, runs the game's two routines and
records the ten quads it built: their corners' screen positions, the ordering-table entry each
was filed in and the colours of their first two corners. The remake's SwordGlow must reproduce
every case (tests/core/test_sword_glow.gd). Used by `export_traces.py --sword-glow`.

Case file (`sword_glow.bin`): "T3SG", u32 version, u32 count, then per case:
    s16 char id, bank type, costume slot, display buffer, s16 view rot[9], s32 view t[3], s16 H,
    s16 pad, s16 block rot[9], s32 block t[3], u8 drawn, u8 pad[3];
    when drawn, per quad: s16 xy[8], u16 entry, u8 rgb of corner 0, u8 rgb of corner 1
"""

from __future__ import annotations

import math
import random
import struct

import sword_glow as sg
from psxcpu import GTE, PsxCpu, load_release

FIGHTER = 0x800A96F0
OT_HEADER, OT_TABLE = 0x801C0000, 0x801C0100
BUFFERS = (0x801D0000, 0x801D0400)
ENTRIES = 1024
END_OF_LIST = 0x00FFFFFF
SCREEN_OFFSET = (192, 240)
CHARACTERS = (4, 4, 15, 15, 5)           # Yoshimitsu, Mokujin, another fighter
BANKS = (4, 4, 7)
SLOTS = (8, 9, 10, 11, 20)


def rotation(rng: random.Random) -> list[int]:
    """A random rotation matrix, 4.12 (the product of three turns)."""
    def turn(axis: int, a: float) -> list[list[float]]:
        c, s = math.cos(a), math.sin(a)
        m = [[1.0, 0, 0], [0, 1.0, 0], [0, 0, 1.0]]
        i, j = [(1, 2), (0, 2), (0, 1)][axis]
        m[i][i], m[i][j], m[j][i], m[j][j] = c, -s, s, c
        return m

    def mul(a, b):
        return [[sum(a[r][k] * b[k][c] for k in range(3)) for c in range(3)] for r in range(3)]

    angles = [rng.uniform(-math.pi, math.pi) for _ in range(3)]
    m = mul(turn(0, angles[0]), mul(turn(1, angles[1]), turn(2, angles[2])))
    return [round(m[r][c] * 4096) for r in range(3) for c in range(3)]


def matrix_bytes(rot: list[int], t: tuple[int, int, int]) -> bytes:
    return struct.pack("<9h", *rot) + b"\0\0" + struct.pack("<3i", *t)


def prepare(cpu: PsxCpu, rng: random.Random, case: int, fixed_offset: bool = False) -> dict:
    """A random pre-state in the harness RAM and GTE: the same for the game and a port. Returns the
    case's inputs."""
    inputs = {
        "char": rng.choice(CHARACTERS), "bank": rng.choice(BANKS), "slot": rng.choice(SLOTS),
        "player": rng.choice((0, 1)), "buffer": rng.choice((0, 1)),
    }
    near = case % 5 == 0         # a small depth makes the narrow ribbon
    inputs["view_rot"] = rotation(rng) if case % 3 == 0 else [4096, 0, 0, 0, 4096, 0, 0, 0, 4096]
    inputs["view_t"] = (rng.randint(-800, 800), rng.randint(-800, 800), rng.randint(0, 200) if near else rng.randint(1500, 6000))
    inputs["block_rot"] = rotation(rng)
    inputs["block_t"] = (rng.randint(-1200, 1200), rng.randint(-1500, 500), rng.randint(-1200, 1200))
    inputs["h"] = rng.randint(300, 1400)
    offset = SCREEN_OFFSET if fixed_offset else (rng.randint(100, 260), rng.randint(100, 260))
    for field, value in ((sg.PLAYER, inputs["player"]), (sg.BANK_TYPE, inputs["bank"]),
                         (sg.CHAR_ID, inputs["char"]), (sg.COSTUME_SLOT, inputs["slot"])):
        cpu.write(FIGHTER + field, struct.pack("<h", value))
    cpu.write(sg.GS_OT, struct.pack("<I", OT_HEADER))
    cpu.write(OT_HEADER + 4, struct.pack("<I", OT_TABLE))
    cpu.write(OT_TABLE, struct.pack("<I", END_OF_LIST) * ENTRIES)
    cpu.write(sg.ALLOCATION + 8 * inputs["player"], struct.pack("<II", *BUFFERS))
    cpu.write(sg.PRIM_BUFFERS + 8 * inputs["player"], bytes(8))
    cpu.write(sg.VIEW, matrix_bytes(inputs["view_rot"], inputs["view_t"]))
    cpu.write(FIGHTER + sg.SWORD_BLOCK, matrix_bytes(inputs["block_rot"], inputs["block_t"]))
    cpu.gte.write_ctrl(26, inputs["h"])
    cpu.gte.write_ctrl(24, offset[0] << 16)
    cpu.gte.write_ctrl(25, offset[1] << 16)
    cpu.write(sg.DISPLAY_BUFFER, struct.pack("<i", inputs["buffer"]))
    return inputs


def port_gte(cpu: PsxCpu) -> GTE:
    """A port's GTE: the control registers the game has before the call."""
    gte = GTE()
    for r in range(32):
        gte.write_ctrl(r, cpu.gte.read_ctrl(r))
    return gte


def filed_entries(cpu: PsxCpu, table: int, first: int, size: int) -> dict[int, int]:
    """The ordering-table entry each primitive (`size` bytes) of the buffer at `first` was filed in,
    in the ordering table whose entries start at `table`."""
    found: dict[int, int] = {}
    for entry in range(ENTRIES):
        link = struct.unpack("<I", cpu.read(table + 4 * entry, 4))[0] & 0xFFFFFF
        while link != END_OF_LIST:
            address = 0x80000000 | link
            found[(address - first) // size] = entry
            link = struct.unpack("<I", cpu.read(address, 4))[0] & 0xFFFFFF
    return found


def run_game(cpu: PsxCpu, inputs: dict) -> list[tuple] | None:
    """The game's two routines on the prepared state: the quads (xy[8], entry, rgb0, rgb1), or None
    when the fighter has no glow."""
    cpu.call(0x8003161C, FIGHTER)
    cpu.call(0x80031980, FIGHTER)
    if inputs["char"] != sg.YOSHIMITSU and not (inputs["char"] == sg.MOKUJIN and inputs["bank"] == sg.BANK_YOSHIMITSU):
        return None
    first = BUFFERS[inputs["buffer"]]
    entries = filed_entries(cpu, OT_TABLE, first, sg.PRIM_BYTES)
    quads = []
    for q in range(sg.QUADS):
        raw = cpu.read(first + sg.PRIM_BYTES * q, sg.PRIM_BYTES)
        xy = [struct.unpack_from("<h", raw, offset)[0] for v in range(4) for offset in (8 + 12 * v, 10 + 12 * v)]
        quads.append((xy, entries[q], tuple(raw[4:7]), tuple(raw[16:19])))
    return quads


def generate(count: int, seed: int = 26) -> bytes:
    rng = random.Random(seed)
    cpu = load_release()
    out = bytearray(b"T3SG" + struct.pack("<II", 1, count))
    for case in range(count):
        inputs = prepare(cpu, rng, case, fixed_offset=True)
        quads = run_game(cpu, inputs)
        out += struct.pack("<4h", inputs["char"], inputs["bank"], inputs["slot"], inputs["buffer"])
        out += struct.pack("<9h3ih", *inputs["view_rot"], *inputs["view_t"], inputs["h"]) + b"\0\0"
        out += struct.pack("<9h3i", *inputs["block_rot"], *inputs["block_t"])
        out += struct.pack("<B3x", quads is not None)
        for xy, entry, rgb0, rgb1 in quads or ():
            out += struct.pack("<8hH3B3B", *xy, entry, *rgb0, *rgb1)
    return bytes(out)
