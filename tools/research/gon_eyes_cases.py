#!/usr/bin/env python3
"""Random cases of Gon's eyes' look direction (GonEyesFollow, 0x80039A50) run in the CPU harness.

Each case sets up two fighter records (Gon's costume slot 42, head joint block of the last frame
with a random rotation and position, the opponent's head position) and calls the game's routine,
which turns the direction of the opponent's head in Gon's head frame into a shift of the pupils
(GonEyesSetOffset, 0 to 17 for one eye or 0 to −17 for the other); the shift is read back from the
two eyes' cache bytes (fighter +0x1292, +0x1293), which hold it after the call. The remake's
simulation (FighterAnimation._gon_eyes_follow) must reproduce every case
(tests/core/test_gon_eyes.gd). Used by `export_traces.py --gon-eyes`.

Case file (`gon_eyes.bin`): "T3GE", u32 version, u32 count, then per case: s16 rot[9] (Gon's head),
s32 own head t[3], s32 opponent's head t[3], s32 shift
"""

from __future__ import annotations

import random
import struct

import motion
from harness_common import CHAR_ID, COSTUME_SLOT, reset_commands
import pose
import psxcpu

F0 = 0x800A96F0
FIGHTER_BYTES = 0x188C
GON_FOLLOW = 0x80039A50          # GonEyesFollow(fighter, opponent)
GON_SLOT = 42                    # costume slot of Gon (the table rows are read by the slot)
GON = 0x11
CACHE = 0x1292                   # u8 per eye: the shift last copied
HEAD_JOINT = 2


def block(base: int, joint: int) -> int:
    return base + 0x8F4 + 0x44 * joint


def generate(count: int, seed: int = 5) -> bytes:
    rng = random.Random(seed)
    cpu = psxcpu.load_release()
    tab = pose.ExeTables(motion.load_exe())
    out = bytearray(b"T3GE" + struct.pack("<II", 1, count))
    blank = bytes(FIGHTER_BYTES)
    opponent = F0 + FIGHTER_BYTES
    for _ in range(count):
        for base in (F0, opponent):
            cpu.write(base, blank)
        cpu.write(F0 + COSTUME_SLOT, struct.pack("<h", GON_SLOT))
        cpu.write(F0 + CHAR_ID, struct.pack("<h", GON))
        m = pose.euler_to_matrix(rng.getrandbits(16), rng.getrandbits(16), rng.getrandbits(16), tab)
        rot = [m[r][c] for r in range(3) for c in range(3)]
        own = [rng.randrange(-2500, 2500), rng.randrange(-2200, 150), rng.randrange(-2500, 2500)]
        reach = rng.choice((300, 1500, 6000, 40000))
        other = [own[0] + rng.randrange(-reach, reach), own[1] + rng.randrange(-reach // 4, reach // 4),
                 own[2] + rng.randrange(-reach, reach)]
        cpu.write(block(F0, HEAD_JOINT), struct.pack("<9h", *rot) + b"\0\0" + struct.pack("<3i", *own))
        cpu.write(block(opponent, HEAD_JOINT), bytes(20) + struct.pack("<3i", *other))
        reset_commands(cpu)
        cpu.call(GON_FOLLOW, F0, opponent)
        first, second = cpu.read(F0 + CACHE, 2)
        shift = struct.unpack("b", bytes([first if first else second]))[0]
        out += struct.pack("<9h3i3ii", *rot, *own, *other, shift)
    return bytes(out)
