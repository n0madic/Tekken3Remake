#!/usr/bin/env python3
"""Compare command_list_sim.py with the command list (Japan Rev.1) in the CPU harness.

Each case builds a random move-text string (glyphs, joiners, arrows, button diagrams, spaces and
every 0xFF escape with its arguments), runs MoveTextDraw (0x80077A0C) and the port on the same
RAM, and compares all of RAM (packets and ordering table included) and the returned pointer.

Usage: python3 tools/research/verify_command_list_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import command_list_sim as cl
import verify_draw_sim as vd
import verify_menu_sim as vm

log = logging.getLogger("verify_command_list_sim")
NESTED = vd.STRINGS + 0x200


def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


def random_text(cpu, rng) -> tuple[bytes, list[int]]:
    """A random move-text string and its arguments; nested strings are written after NESTED."""
    out, args, nested = bytearray(), [], NESTED
    for _ in range(rng.randrange(1, 14)):
        k = rng.randrange(12)
        if k < 3:
            out += bytes(rng.randrange(7, 0xBD) for _ in range(rng.randrange(1, 5)))
        elif k == 3:
            out.append(rng.randrange(1, 7))
        elif k == 4:
            out.append(rng.randrange(0xBD, 0xCD))
        elif k == 5:
            out += bytes(rng.randrange(0xD1, 0xE1) for _ in range(rng.randrange(1, 4)))
        elif k == 6:
            out.append(rng.choice([0xFD, 0xFE, 0xCD, 0xD0, 0xE1, 0xFC]))
        elif k == 7:
            out += b"\xFF\xFF"
        else:
            cmd = rng.choice("nsHVhvipt")
            out += b"\xFF" + cmd.encode()
            if cmd == "s":
                text = bytes(rng.randrange(1, 0x100) for _ in range(rng.randrange(0, 5))) + b"\0"
                cpu.write(nested, text)
                args.append(nested)
                nested += len(text)
            elif cmd in "HV":
                args.append(rng.randrange(-20, 400))
            elif cmd in "hv":
                args.append(rng.randrange(-3, 30))
            elif cmd == "i":
                args.append(rng.getrandbits(24))
            elif cmd == "p":
                args.append(rng.randrange(16))
            elif cmd == "t":
                args.append(rng.randrange(4))
    return bytes(out) + b"\0", args


def case_text(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    for i in range(4):
        w16(cpu, cl.SAVED + 2 * i, rng.choice([0, 16, 100, rng.randrange(-20, 400)]))
    w32(cpu, cl.SAVED + 8, rng.getrandbits(24))
    w32(cpu, cl.FONT_INDEX, rng.randrange(4))
    text, args = random_text(cpu, rng)
    cpu.write(vd.STRINGS, text)
    vd.run_gpu(chk, "MoveTextDraw", cpu, lambda c: c.call(0x80077A0C, vd.STRINGS, *args) & 0xFFFFFFFF,
               lambda r: cl.move_text_draw(r, vd.STRINGS, args), show=text.hex())


SOUND_LOG = 0x801F8040
SCENE_OTS = 0x801F8280


class LogHooks(cl.ListHooks):
    def sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, SOUND_LOG, sound_id)


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))


def random_entry_text(rng, width: int) -> bytes:
    out = bytearray()
    while width > 0:
        c = rng.choice([rng.randrange(7, 0xBD), rng.randrange(7, 0xBD), rng.randrange(1, 6), 0xFD, 0xFE,
                        rng.randrange(0xBD, 0xCD), rng.randrange(0xD1, 0xE1), 6])
        out.append(c)
        width -= cl._weight(c)
    return bytes(out) + b"\0"


def random_lists(cpu, rng) -> None:
    for p in range(2):
        body = bytearray()
        n = rng.choice([1, 2, 7, rng.randrange(1, 12), 16, 22])
        for _ in range(n):
            if n > 12:                              # long lists (the grouped colours need 15+ moves)
                body += random_entry_text(rng, rng.choice([2, 6, 29, rng.randrange(1, 10)]))
                body += random_entry_text(rng, rng.randrange(1, 6))
            else:
                body += random_entry_text(rng, rng.choice([4, 12, 26, 28, 29, 34, rng.randrange(1, 40)]))
                body += random_entry_text(rng, rng.randrange(1, 16))
        body = bytes([n]) + body
        assert len(body) <= 0x232
        cpu.write(cl.LISTS + 0x232 * p, body)
        cpu.write(cl.SCROLL + 8 * p, struct.pack("<ii", rng.choice([0, n - 1, n, rng.randrange(n)]),
                                                  rng.choice([0, 0, 1, -1, 64, -64, 320, -320, rng.randrange(-400, 400)])))
        w16(cpu, cl.FIGHTERS[p] + 0x18, rng.choice([0, 6, 6, 0xF, rng.randrange(22)]))


def random_list_state(cpu, rng) -> None:
    vm.common(cpu, rng)
    w32(cpu, SOUND_LOG, 0)
    random_lists(cpu, rng)
    for i in range(4):
        w16(cpu, cl.SAVED + 2 * i, rng.randrange(0, 300))
    w32(cpu, cl.FONT_INDEX, rng.randrange(2))
    w32(cpu, vd.ds.TEXT_OFF, rng.choice([0, 0, 0, 1]))
    for p in range(2):
        w16(cpu, cl.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0x1000, 0x4000, 0x2000, 0x8000, 0x20, 0x4010,
                                                      rng.getrandbits(16)]))
        w16(cpu, cl.PAD_HELD + 2 * p, rng.choice([0, 0, 0x1000, 0x4000, rng.getrandbits(16)]))
    w8(cpu, cl.PAUSE_DELAY, rng.choice([0, 0, 0, 1, 2]))
    for i, v in enumerate((0, rng.choice([0, 8]), 0x170, rng.choice([0xF0, 0x1E0]))):
        w16(cpu, cl.SCREEN_RECT + 2 * i, v)
    w32(cpu, 0x800A911C, SCENE_OTS)
    w32(cpu, SCENE_OTS + 0x10, vd.OT + 0x80)
    w32(cpu, cl.MODE, rng.choice([0, 1, 3, 5, 7, 8]))
    w8(cpu, cl.MODE + 0x1D, rng.randrange(4))
    w32(cpu, 0x800B70D8, rng.randrange(2))


def case_lists(cpu, rng, chk) -> None:
    random_list_state(cpu, rng)
    player, pad = rng.randrange(2), rng.randrange(2)
    vd.run_gpu(chk, "ListScreen", cpu, lambda c: c.call(0x800789E4, player, pad) and None,
               lambda r: cl.list_screen(r, player, pad))
    random_list_state(cpu, rng)
    mask, player = rng.randrange(4), rng.randrange(2)
    vd.run_gpu(chk, "PracticeCommandList", cpu, lambda c: c.call(0x8007906C, mask, player) and None,
               lambda r: cl.practice_command_list(r, mask, player))
    random_list_state(cpu, rng)
    player = rng.choice([1, 2])
    vd.run_gpu(chk, "PauseCommandPage", cpu, lambda c: c.call(0x80079298, player) and None,
               lambda r: cl.pause_command_page(r, player))


NAMES = ["MoveTextDraw", "ListScreen", "PracticeCommandList", "PauseCommandPage"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = vm.menu_cpu("title")
    vd.log_stub(cpu, 0x800756A4, SOUND_LOG, 5)
    cl.HOOKS = LogHooks()
    for _ in range(args.cases):
        case_text(cpu, rng, chk)
        case_lists(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
