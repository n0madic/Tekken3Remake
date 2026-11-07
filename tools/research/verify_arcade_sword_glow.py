#!/usr/bin/env python3
"""Compare arcade_sword_glow.py with the arcade's code in the CPU harness (World ver. E1).

`FUN_80192ecc` (the ribbon of one fighter and frame) runs on random fighter records: costume slots
8 and 9, Mokujin's with and without Yoshimitsu's moves and others, either player and display
buffer, either frame parity, a random view (rotation, translation, projection plane) and a random
sword joint matrix. The whole RAM is compared byte for byte afterwards (only the harness stack is
excluded), so the quads' colours, positions, texture coordinates, pages, the ordering table and the
GTE rotation all have to match.

It also checks what the remake relies on: the sine and octant tables the arcade's ribbon uses are
the PlayStation's, and the ribbon's 16 × 16 texture (VRAM (960, 256) and its CLUT (768, 375), the
second player's 128 rows lower) is the same grey ramp in every costume that has the glow.

Usage: python3 tools/research/verify_arcade_sword_glow.py [--cases N] [--seed S] [--zip tekken3_mame.zip]
"""

from __future__ import annotations

import argparse
import logging
import random
import sys
from itertools import islice
from pathlib import Path

from arcade_cpu import DEFAULT_ZIP, STACK, arcade, arcade_cpu  # puts tools/remake_import on the path

import arcade_character
import arcade_sword_glow as asg
import arcade_sword_glow_cases as cases
import sword_glow
from sword_glow_cases import port_gte

log = logging.getLogger("verify_arcade_sword_glow")

ROOT = Path(__file__).resolve().parents[2]
RAM_START = 0x80000000
PS_BASE, PS_HEADER = 0x80010000, 0x800   # the PlayStation executable: load address, header bytes


def differences(game: bytes, port: bytes, stack: tuple[int, int]) -> list[int]:
    """The first addresses at which the RAM images differ, without the harness stack."""
    g, p = bytearray(game), bytearray(port)
    lo, hi = stack[0] - RAM_START, stack[1] - RAM_START
    g[lo:hi] = p[lo:hi] = bytes(hi - lo)
    if g == p:
        return []
    return list(islice((RAM_START + i for i in range(len(g)) if g[i] != p[i]), 9))


def check_tables(arc: arcade.ArcadeSet) -> bool:
    """The arcade's sine and octant tables are the PlayStation's (so the remake's are the same)."""
    exe = (ROOT / "work" / "jp_rev1" / "exe.bin").read_bytes()

    def ps(address: int, size: int) -> bytes:
        return exe[address - PS_BASE + PS_HEADER:address - PS_BASE + PS_HEADER + size]

    sine = arc.prog(asg.SIN_TABLE, 2 * 4096) == ps(sword_glow.SIN_TABLE, 2 * 4096)
    octant = arc.prog(asg.RATAN_TABLE, 2 * 1025) == ps(sword_glow.RATAN_TABLE, 2 * 1025)
    blade = arc.prog(asg.BLADE_POINTS, 32) == ps(sword_glow.BLADE_POINTS, 32)
    log.info("sine table %s, ratan2 table %s, blade points %s the PlayStation's",
             *("equal to" if ok else "DIFFERENT from" for ok in (sine, octant, blade)))
    return sine and octant and blade


def check_texture(arc: arcade.ArcadeSet) -> bool:
    """The glow's picture (arcade_character.glow_levels: the texels through a grey CLUT) is the same
    in every costume that has the glow."""
    found = {slot: arcade_character.glow_levels(arcade_character.load_textures(arcade_character.costume(arc, slot)[1]).words)
             for slot in (8, 9, 30, 31)}
    same = all(levels == found[8] for levels in found.values())
    ramp = found[8]
    # Black at the top left (the quads' dark corners), white at the bottom right, never brighter going left or up.
    shaded = ramp[0] == 0 and ramp[-1] == 31 and all(
        ramp[16 * v + u] <= ramp[16 * v + u + 1] and ramp[16 * v + u] <= ramp[16 * (v + 1) + u]
        for v in range(15) for u in range(15))
    log.info("glow picture: %s in slots 8, 9, 30 and 31, a grey ramp %s", "the same" if same else "NOT the same",
             "from black to white" if shaded else "NOT from black to white")
    return same and shaded


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=300)
    parser.add_argument("--seed", type=int, default=26)
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    args = parser.parse_args()
    arc = arcade.open_set(args.zip)
    cpu = arcade_cpu(arc)
    rng = random.Random(args.seed)
    stack = (STACK - 0x4000, STACK)
    bad = drawn = 0
    for case in range(args.cases):
        inputs = cases.prepare(cpu, rng, case)
        drawn += cases.drawn(inputs)
        ram = asg.ArcadeRam(cpu.read(RAM_START, asg.ARCADE_RAM))
        gte = port_gte(cpu)
        cpu.call(cases.GLOW, cases.FIGHTER)
        asg.draw(ram, gte, cases.FIGHTER)
        d = differences(cpu.read(RAM_START, asg.ARCADE_RAM), bytes(ram.data), stack)
        rotation = [cpu.gte.read_ctrl(r) for r in range(8)] != [gte.read_ctrl(r) for r in range(8)]
        if d or rotation:
            bad += 1
            if bad <= 5:
                log.info("  mismatch in case %d (%s): bytes %s, GTE rotation %s", case,
                         {k: v for k, v in inputs.items() if k in ("slot", "word", "player", "buffer", "parity")},
                         [hex(a) for a in d], "differs" if rotation else "equal")
    log.info("FUN_80192ecc: %d cases (%d with the glow), %d mismatches", args.cases, drawn, bad)
    ok = bad == 0
    ok = check_tables(arc) and ok
    ok = check_texture(arc) and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
