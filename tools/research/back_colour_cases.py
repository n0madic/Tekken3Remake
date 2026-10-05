#!/usr/bin/env python3
"""Cases of a fighter's back colour (FUN_8003A3B8, the pick-up flash's ramp and practice's FREEZE
SIGNAL) run in the CPU harness.

Every real stage's light record with each flash count 0 to 34, then random light words (above the
flash's peak too), counts and signals. The harness calls the game's routine on a fighter record and
reads the colour SetBackColor leaves in the GTE (in bytes: the control registers >> 4). The remake's
`StageLighting.fighter_back_colour` must give the same colour (tests/presentation/test_stage_lighting.gd).
Used by `export_traces.py --back-colour`.

Case file (`back_colour.bin`): "T3BC", u32 version, u32 count, then per case:
    u16 light word, u8 flash count, u8 practice (the game mode is practice), u8 signal flag,
    u8 signal r, g, b, u16 expected red, green, blue
"""

from __future__ import annotations

import random
import struct

import projection_sim as pj
import psxcpu

FIGHTER = 0x801C0000
BACK_COLOUR_REGISTERS = (13, 14, 15)
STAGES = 19
FLASH_COUNTS = 35
RANDOM_CASES = 600
CASE = "<H6B3H"


def generate(seed: int = 5) -> bytes:
    rng = random.Random(seed)
    cpu = psxcpu.load_release()
    cases = []
    for stage in range(STAGES):
        for count in range(FLASH_COUNTS):
            cases.append((stage, None, count, False, 0, (0, 0, 0)))
    for _ in range(RANDOM_CASES):
        word = rng.choice([rng.randrange(0x2000), rng.getrandbits(16), 1500, 2800])
        practice = rng.random() < 0.5
        cases.append((rng.randrange(STAGES), word, rng.choice([0, 0, 1, 2, 31, 32, 33, rng.randrange(1, 35)]),
                      practice, rng.choice([0, 1, rng.getrandbits(8)]), tuple(rng.randbytes(3))))
    out = bytearray(b"T3BC" + struct.pack("<II", 1, len(cases)))
    for stage, word, count, practice, flag, signal in cases:
        record = pj.STAGE_RECORDS + (stage + 1) * pj.STAGE_RECORD_BYTES
        if word is not None:
            cpu.write(record, struct.pack("<H", word))
        word = struct.unpack("<H", cpu.read(record, 2))[0]
        cpu.write(FIGHTER, bytes(0x40))          # player 1's record: +0x12 = 0
        cpu.write(pj.FLASH, bytes([count]))
        cpu.write(pj.SIGNAL, bytes([flag, *signal]))
        cpu.write(pj.MODE, struct.pack("<I", pj.PRACTICE if practice else 8))
        cpu.call(0x8003A3B8, FIGHTER, stage)
        colour = [cpu.gte.read_ctrl(r) >> 4 for r in BACK_COLOUR_REGISTERS]
        out += struct.pack(CASE, word, count, int(practice), flag, *signal, *colour)
    return bytes(out)
