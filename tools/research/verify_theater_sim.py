#!/usr/bin/env python3
"""Compare theater_sim.py with the Theater menus of ending.ovl (Japan Rev.1) in the CPU harness.

Each case randomises the Theater context, runs the game's routine and the port on the same RAM and
compares all of RAM (GPU packets and ordering tables included; only the harness stack is excluded).
SoundPlayFighter, the music stop and the TIM upload are replaced by stubs that log their argument
the way theater_sim.TheaterHooks does, so the calls are compared too.

Usage: python3 tools/research/verify_theater_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
import screens_sim as ss
import movie_captions as mc
import theater_sim as ts
import verify_draw_sim as vd
import verify_menu_sim as vm

log = logging.getLogger("verify_theater_sim")

SOUND_LOG, STOP_LOG, TIM_LOG = 0x801F8040, 0x801F8080, 0x801F80C0


class LogHooks(ts.TheaterHooks):
    def sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, SOUND_LOG, sound_id)

    def music_stop(self, ram) -> None:
        vd.ram_log(ram, STOP_LOG, 0)

    def load_tim(self, ram, k: int) -> None:
        vd.ram_log(ram, TIM_LOG, k)


def theater_cpu():
    cpu = vm.menu_cpu("ending")
    vd.log_stub(cpu, 0x800756A4, SOUND_LOG, 5)     # SoundPlayFighter(0, id, 0): log a1
    vd.log_stub(cpu, 0x8006B834, STOP_LOG, 4)
    vd.log_stub(cpu, 0x80112390, TIM_LOG, 4)
    ts.HOOKS = LogHooks()
    return cpu


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))
def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


def random_state(cpu, rng, pages=(1, 1, 2, 3, 0)) -> None:
    vm.common(cpu, rng)
    for base in (SOUND_LOG, STOP_LOG, TIM_LOG):
        w32(cpu, base, 0)
    page, disc = rng.choice(pages), rng.randrange(1, 4)
    w8(cpu, ts.PAGE, page)
    w8(cpu, ts.DISC, disc)
    mlist, mcount = ts.MOVIE_LISTS[disc]
    _, scount = ts.SOUND_LISTS[disc]
    w8(cpu, ts.MOVIE_COUNT, mcount)
    w8(cpu, ts.SOUND_COUNT, scount)
    if page == 1:
        cells = [i for i in range(mcount) if struct.unpack("<h", cpu.read(mlist + ts.ENTRY * i, 2))[0] >= 0]
        cur = rng.choice(cells + [cells[-1], 0])    # the cells the cursor can reach
        rows = (mcount + 5) // 6
        w8(cpu, ts.TOP, rng.choice([0, max(0, cur // 6 - 3), rng.randrange(rows)]))
    else:
        cur = rng.choice([rng.randrange(scount), rng.randrange(scount), scount - 1, 0])
        w8(cpu, ts.TOP, rng.choice([0, max(0, cur - 13), rng.randrange(scount - 13)]))
    w8(cpu, ts.CURSOR, cur)
    w16(cpu, ts.FOCUS, rng.choice([0, 0, 0, 1, 2, 3, 4]))
    w16(cpu, ts.ALL_MOVIES, rng.choice([0, 1]))
    w16(cpu, ts.IDLE, rng.choice([0, 0x1DF, 0x1E0, 0x1E0 + rng.randrange(0x400), 0x1E0 + rng.randrange(0x400), rng.randrange(0x10000)]))
    w32(cpu, ts.FRAME_COUNTER, rng.getrandbits(32))
    w32(cpu, ds.FRAME_COUNT, rng.getrandbits(32))
    w32(cpu, ss.CLEARED, rng.choice([0, 0x1FFFFF, rng.getrandbits(21), rng.getrandbits(32)]))
    w32(cpu, ss.CLEARED2, rng.choice([0, 0x10900, rng.getrandbits(21) & 0x10900, rng.getrandbits(32)]))
    if rng.random() < 0.7:                      # no button held: the banner's idle count runs
        w32(cpu, ss.PAD_HELD, 0)
    for p in range(2):
        w16(cpu, ss.PAD_REPEAT + 2 * p, rng.choice([0, 0, 0x1000, 0x2000, 0x4000, 0x8000, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0, 0x20, 0x100, 0x800, rng.getrandbits(16)]))


def case_draw(cpu, rng, chk) -> None:
    random_state(cpu, rng)
    kind = rng.choice([0, 0, 0, 0, rng.randrange(7)])
    vd.run_gpu(chk, "Draw", cpu, lambda c: c.call(0x80111894, kind) and None, lambda r: ts.theater_draw(r, kind),
               f"kind {kind}")


def case_input(cpu, rng, chk) -> None:
    random_state(cpu, rng, (1, 2, 3))
    vd.run_gpu(chk, "Input", cpu, lambda c: c.call(0x80111A28), lambda r: ts.theater_input(r))


def case_rules(cpu, rng, chk) -> None:
    random_state(cpu, rng)
    vd.run_gpu(chk, "AllMovies", cpu, lambda c: c.call(0x801109D4), lambda r: ts.all_movies(r))
    random_state(cpu, rng)
    disc = rng.randrange(1, 4)
    lst, n = ts.MOVIE_LISTS[disc]
    idx = rng.randrange(n)
    vd.run_gpu(chk, "MovieName", cpu, lambda c: c.call(0x8010F634, lst, idx) and None,
               lambda r: ts.movie_name(r, lst, idx))


CAPTION_BITMAPS, CAPTION_FRAME = 0x801E0000, 0x801F0000   # test bitmap and macroblock buffers


def case_captions(cpu, rng, chk) -> None:
    """The ending-movie caption player (movie_captions.py)."""
    vm.common(cpu, rng)
    c = mc.CAPTION
    w16(cpu, c, rng.choice([-1, rng.randrange(40)]))
    w16(cpu, c + 2, rng.choice([-1, rng.randrange(40)]))
    w32(cpu, c + 4, rng.randrange(0, 0x2000))
    for off, lo, hi in ((8, -20, 60), (0xA, 0, 6), (0xC, -4, 40), (0xE, 0, 40), (0x10, 0, 17)):
        w16(cpu, c + off, rng.randrange(lo, hi))
    w16(cpu, c + 0x14, rng.choice([0, 2, 3]))
    w32(cpu, mc.BITMAP_PTR, CAPTION_BITMAPS)
    cpu.write(CAPTION_BITMAPS, rng.randbytes(0x3000))
    cpu.write(CAPTION_FRAME, rng.randbytes(0x800))
    x = rng.randrange(-4, 120)
    vd.run_gpu(chk, "CaptionSlice", cpu, lambda cc: cc.call(0x8010F3F8, x, CAPTION_FRAME) and None,
               lambda r: mc.caption_slice(r, x, CAPTION_FRAME))
    set_no = rng.choice([-1, 0, 1, 2, 3])
    vd.run_gpu(chk, "CaptionStart", cpu, lambda cc: cc.call(0x8010F004, set_no) and None,
               lambda r: mc.caption_start(r, set_no))
    frame = rng.choice([0, 1, rng.randrange(-5, 3000)])
    vd.run_gpu(chk, "CaptionUpdate", cpu, lambda cc: cc.call(0x8010F0B4, frame) and None,
               lambda r: mc.caption_update(r, frame))


NAMES = ["Draw", "Input", "AllMovies", "MovieName", "CaptionSlice", "CaptionStart", "CaptionUpdate"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = theater_cpu()
    for _ in range(args.cases):
        case_draw(cpu, rng, chk)
        case_input(cpu, rng, chk)
        case_rules(cpu, rng, chk)
        case_captions(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
