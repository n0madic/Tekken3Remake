#!/usr/bin/env python3
"""Check the Tekken Force boss table in modes.md against the game's own boss loader (Japan Rev.1).

For every player character (costume key = character · 4 + costume) and level 1-4 the original
`FUN_800B2B3C` runs in the CPU harness until it calls `FUN_8004F55C(fighter, character, costume)`,
which loads the boss; the arguments are compared with the table the port documents
(`force_sim.boss_for`).

Usage: python3 tools/research/check_force_bosses.py
"""

from __future__ import annotations

import struct
import sys

import force_sim as fs
import verify_ai_sim as va
import verify_menu_sim as vm
from unicorn.mips_const import UC_MIPS_REG_A1, UC_MIPS_REG_A2


def main() -> int:
    cpu = vm.menu_cpu("force")
    bad = total = 0
    for key in range(0x5C):
        char = key >> 2
        if char in (22,):
            continue
        for level in range(4):
            player, slot_fighter = fs.F0, fs.F1
            cpu.write(fs.PLAYER, struct.pack("<I", player))
            cpu.write(fs.SLOTS, struct.pack("<I", slot_fighter))
            cpu.write(player + 0x14, struct.pack("<h", key))           # costume key
            cpu.write(player + 0x18, struct.pack("<h", char))          # character id
            cpu.write(fs.LEVEL, struct.pack("<I", level))
            if not va.run_until(cpu, 0x800B2B3C, 0x8004F55C):
                print("no boss load for key", hex(key))
                bad += 1
                continue
            got = (cpu.uc.reg_read(UC_MIPS_REG_A1), cpu.uc.reg_read(UC_MIPS_REG_A2))
            want = fs.boss_for(cpu, key, level)
            total += 1
            if got != want:
                bad += 1
                print(f"key {key:#x} level {level + 1}: game {got} table {want}")
    print(f"{total} player/level pairs, {bad} differences")
    return 0 if bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
