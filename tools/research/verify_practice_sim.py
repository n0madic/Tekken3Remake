#!/usr/bin/env python3
"""Compare practice_sim.py with practice.ovl (Japan Rev.1) in the CPU harness.

Each case randomises the practice state, runs the game's routine and the port on the same RAM and
compares all of RAM (GPU packets and ordering tables included; only the harness stack is excluded).

Usage: python3 tools/research/verify_practice_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
import practice_sim as ps
import verify_draw_sim as vd
import verify_menu_sim as vm

log = logging.getLogger("verify_practice_sim")


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))
def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))


def random_state(cpu, rng) -> None:
    vm.common(cpu, rng)
    s = cpu.u32(ps.S_PTR)
    for off, n in ((0x75, 2), (0x77, 3), (0x78, 11), (0x79, 11), (0x7A, 11), (0x7B, 2), (0x7C, 8), (0x7D, 9),
                   (0x7E, 3), (0x7F, 10), (0x81, 5), (0x83, 2), (0x9D, 2), (0x9E, 2), (0xA0, 2), (0xA7, 2)):
        w8(cpu, s + off, rng.randrange(n))
    for f in ps.FIGHTERS:
        w16(cpu, f + 0x14, rng.randrange(0x58))
        w16(cpu, f + 0x16, rng.choice([rng.randrange(18), 11, 14, 15]))
    cpu.write(ds.TEXT_OFF, struct.pack("<I", rng.choice([0, 0, 0, 1])))


PAGES = (("ModeSelect", 0x800B5834, ps.page_mode_select), ("PageFree", 0x800B5978, ps.page_free),
         ("PageVsCpu", 0x800B5ED4, ps.page_vs_cpu), ("PageCombo", 0x800B6368, ps.page_combo),
         ("PausePage", 0x800B57AC, ps.pause_page))


def case_pages(cpu, rng, chk) -> None:
    for name, addr, fn in PAGES:
        random_state(cpu, rng)
        vd.run_gpu(chk, name, cpu, lambda c: c.call(addr) and None, lambda r: fn(r))
    random_state(cpu, rng)
    which, x, y, col = rng.randrange(2), rng.randrange(-20, 360), rng.randrange(-20, 480), rng.randrange(256)
    vd.run_gpu(chk, "TechRoll", cpu, lambda c: c.call(0x800B7704, which, x, y, col) and None,
               lambda r: ps.tech_roll_line(r, which, x, y, col))


def random_hud(cpu, rng) -> None:
    random_state(cpu, rng)
    s = cpu.u32(ps.S_PTR)
    for off, n in ((0x87, 2), (0x8A, 2), (0x82, 10), (0x84, 2), (0x85, 2), (0x74, 4), (0xA2, 2), (0xA3, 7), (0xA4, 256)):
        w8(cpu, s + off, rng.randrange(n))
    for p in range(2):
        d = s + 0x14 + 0x20 * p
        cpu.write(d, struct.pack("<i", rng.choice([0, 12, 250, -40, rng.randrange(-999, 1000)])))
        cpu.write(d + 8, struct.pack("<i", rng.choice([0, 5, 99, 150, -12, rng.randrange(-300, 300)])))
        for off in (0xC, 0xE, 0x10, 0x12):
            w16(cpu, d + off, rng.choice([0, 1, 2, 30, rng.randrange(-100, 200)]))
        for off in (0x1A, 0x1B, 0x1D):
            w8(cpu, d + off, rng.choice([0, 1, 2, 5, 12, rng.randrange(256)]))
    for i in range(4):
        m = s + 0x54 + 8 * i
        w16(cpu, m, rng.choice([0x412, 0x217, 0x31F, 0x51F, 0x10F, 0x607, 0x706, 0x800, rng.getrandbits(16)]))
        w16(cpu, m + 2, rng.choice([0, 1, 30]))
        w16(cpu, m + 4, rng.randrange(-40, 400))
        w16(cpu, m + 6, rng.randrange(-40, 500))
    for i in range(0x32):
        cpu.write(ps.KEY_RING + 4 * i, struct.pack("<BBH", rng.choice([0, 0, 0x1, 0x2, 0x4, 0x8, rng.randrange(16)]),
                                                   rng.choice([0, 0, 1, 2, 3, 4, 6, 8, 9, 12, rng.randrange(16)]),
                                                   rng.getrandbits(16)))
    for p in range(2):
        cpu.write(ps.KEY_HEADS + 4 * p, struct.pack("<i", rng.choice([0, 49, rng.randrange(-2, 52)])))
    cpu.write(ps.KEY_GUIDE_END, struct.pack("<i", rng.choice([-1, 0, 20, 49, rng.randrange(-5, 60)])))
    cpu.write(0x800958E0, struct.pack("<I", rng.choice([0, 0, 0, 1])))


def case_hud(cpu, rng, chk) -> None:
    random_hud(cpu, rng)
    vd.run_gpu(chk, "PracticeHud", cpu, lambda c: c.call(0x800B6898) and None, lambda r: ps.practice_hud(r))
    random_hud(cpu, rng)
    vd.run_gpu(chk, "KeyDisplay", cpu, lambda c: c.call(0x800B7C84, c.u32(ps.S_PTR)) and None,
               lambda r: ps.key_display(r, r.u32(ps.S_PTR)))
    random_hud(cpu, rng)
    a, b = rng.randrange(0, 100), rng.randrange(-300, 300)
    vd.run_gpu(chk, "ComboCounter", cpu, lambda c: c.call(0x800B6F58, a, b) and None, lambda r: ps.combo_counter(r, a, b))


SOUND_LOG, COMMAND_LOG = 0x801F8040, 0x801F8080


class LogHooks(ps.PracticeHooks):
    def sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, SOUND_LOG, sound_id)

    def command_list(self, ram, mask: int, player: int) -> None:
        vd.ram_log(ram, COMMAND_LOG, mask)


def random_menu(cpu, rng) -> None:
    random_state(cpu, rng)
    for cell in (SOUND_LOG, COMMAND_LOG):
        cpu.write(cell, struct.pack("<I", 0))
    s = cpu.u32(ps.S_PTR)
    pad = rng.choice([0, 0, 0x10, 0x20, 0x100, 0x2000, 0x8000, 0xA000, 0x1000, 0x4000, rng.getrandbits(16)])
    w16(cpu, s + 2, pad)
    w16(cpu, s + 4, rng.choice([0, 0, 0x1000, 0x4000, 0x5000, rng.getrandbits(16)]))
    w8(cpu, s + 0x75, rng.choice([0, 0, 1]))
    w8(cpu, s + 0x77, rng.choice([0, 1, 2, 2, 3, 4, rng.randrange(-2, 7)]))
    for off, n in ((0x78, 9), (0x79, 9), (0x7A, 8)):
        w8(cpu, s + off, rng.choice([rng.randrange(n), rng.randrange(-1, n + 1)]))
    for off, n in ((0x7E, 3), (0x7F, 10), (0x7D, 9), (0x81, 5)):
        w8(cpu, s + off, rng.choice([0, n - 1, rng.randrange(n), rng.randrange(-1, n + 1)]))
    for off in (0x80, 0x83, 0x86, 0x87, 0x9D, 0x9E, 0x9F, 0xA0, 0xA3, 0xA7, 0xA9, 0xAC):
        w8(cpu, s + off, rng.randrange(3))
    w8(cpu, s + 0x84, rng.randrange(2))
    w8(cpu, s + 0x85, 1 - cpu.read(s + 0x84, 1)[0])
    w8(cpu, s + 0x7B, rng.randrange(2))
    for f in ps.FIGHTERS:                        # characters with and without combos
        w16(cpu, f + 0x16, rng.choice([0, 1, 5, 8, 11, 14, 16, 17, rng.randrange(18)]))
    kind = cpu.u32(ps.FIGHTERS[cpu.read(s + 0x7B, 1)[0]] + 0x16) & 0xFFFF
    n = cpu.u32(ps.COMBO_TABLE + 8 * kind)
    w8(cpu, s + 0x7C, rng.randrange(n) if n and rng.random() < 0.8 else rng.choice([0, n, 0xFF]))
    for p in range(2):
        cpu.write(ps.KEY_HEADS + 4 * p, struct.pack("<i", rng.choice([-1, 0, 5, rng.randrange(-3, 50)])))
    cpu.write(0x800AFF68, bytes([rng.choice([0, 0, 1])]))


SCENE_OTS = 0x801F8280


def case_backdrop(cpu, rng, chk) -> None:
    random_menu(cpu, rng)
    for i, v in enumerate((0, rng.choice([0, 8]), 0x170, rng.choice([0xF0, 0x1E0]))):
        w16(cpu, ps.SCREEN_RECT + 2 * i, v)
    cpu.write(0x800A911C, struct.pack("<I", SCENE_OTS))
    cpu.write(SCENE_OTS + 4, struct.pack("<I", vd.OT + 0x40))
    cpu.write(SCENE_OTS + 0x10, struct.pack("<I", vd.OT + 0x80))
    vd.run_gpu(chk, "MenuBackdrop", cpu, lambda c: c.call(0x800B6DA0) and None, lambda r: ps.menu_backdrop(r))


def case_menu(cpu, rng, chk) -> None:
    random_menu(cpu, rng)
    vd.run_gpu(chk, "MenuCursor", cpu, lambda c: c.call(0x800B49C4) and None, lambda r: ps.menu_cursor(r))
    random_menu(cpu, rng)
    s = cpu.u32(ps.S_PTR)
    vd.run_gpu(chk, "MenuInput", cpu, lambda c: c.call(0x800B4C44) and None, lambda r: ps.menu_input(r),
               show=f"75={cpu.read(s + 0x75, 1)[0]} 77={cpu.read(s + 0x77, 1)[0]}")


NAMES = [p[0] for p in PAGES] + ["TechRoll", "PracticeHud", "KeyDisplay", "ComboCounter", "MenuCursor", "MenuInput", "MenuBackdrop"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = vm.menu_cpu("practice")
    vd.log_stub(cpu, 0x800756A4, SOUND_LOG, 5)
    vd.log_stub(cpu, 0x8007906C, COMMAND_LOG, 4)
    ps.HOOKS = LogHooks()
    for _ in range(args.cases):
        case_pages(cpu, rng, chk)
        case_hud(cpu, rng, chk)
        case_menu(cpu, rng, chk)
        case_backdrop(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
