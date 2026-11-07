#!/usr/bin/env python3
"""Compare sword_glow.py with the game's code in the CPU harness (Japan Rev.1).

`FUN_8003161C` (the two buffers of ten quads) and `FUN_80031980` (the ribbon of one frame) run on
random fighter records: Yoshimitsu, Mokujin with and without Yoshimitsu's moves and another
character, in each costume colour, with a random view (rotation, translation, projection plane),
a random sword joint block and either display buffer. The whole RAM is compared byte for byte
afterwards (only the harness stack is excluded), so the quads' colours, positions, the ordering
table and the allocator all have to match.

It also checks the claim the remake relies on, that the ribbon's texture is white: the system
texture archive's 8-bit CLUT row 511 holds colour 0x0000 at index 0 and 0xFFFF after it, which
covers the ribbon's CLUT (272, 511) for any index of the texel at (512, 0).

Usage: python3 tools/research/verify_sword_glow.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
import sys

import sword_glow as sg
import sword_glow_cases
import system_textures
from fight_sim import Ram
from psxcpu import load_release
from sword_glow_cases import port_gte
from verify_draw_sim import Checker, snapshot

log = logging.getLogger("verify_sword_glow")

FIGHTER = sword_glow_cases.FIGHTER


def check_white_texture() -> bool:
    """The ribbon's CLUT is white: row 511 of the system textures is 0x0000, then 0xFFFF."""
    exe = (system_textures.ROOT / "work" / "jp_rev1" / "exe.bin").read_bytes()
    tims = system_textures.members(exe, "jp_rev1")
    vram = system_textures.build_vram(tims)
    row = [struct.unpack_from("<H", vram, (511 * system_textures.VRAM_W + x) * 2)[0] for x in range(256, 512)]
    ok = row[0] == 0 and all(c == 0xFFFF for c in row[1:])
    log.info("system CLUT row 511: %s", "colour 0 then white, so the ribbon is its vertex colours" if ok else "NOT white")
    clut_x = 272 - 256
    return ok and all(c == 0xFFFF for c in row[clut_x:clut_x + 16])


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=300)
    parser.add_argument("--seed", type=int, default=26)
    args = parser.parse_args()
    cpu = load_release()
    rng = random.Random(args.seed)
    init = Checker("FUN_8003161C")
    draw = Checker("FUN_80031980")
    drawn = 0
    for case in range(args.cases):
        sword_glow_cases.prepare(cpu, rng, case)
        init.run(cpu, lambda c: c.call(0x8003161C, FIGHTER), lambda r: sg.init_prims(r, FIGHTER))
        gte = port_gte(cpu)
        # The game's GTE state after the init is the same as before; the port starts from a copy.
        ram_has_glow = sg.has_glow(Ram(snapshot(cpu)), FIGHTER)
        drawn += ram_has_glow
        draw.run(cpu, lambda c: c.call(0x80031980, FIGHTER), lambda r: sg.draw(r, gte, FIGHTER))
    log.info("%d of %d cases drew the ribbon", drawn, args.cases)
    ok = init.report()
    ok = draw.report() and ok
    ok = check_white_texture() and ok
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
