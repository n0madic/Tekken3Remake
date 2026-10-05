#!/usr/bin/env python3
"""Compare menu_sim.py with the game's menu screens in the CPU harness (Japan Rev.1).

Each case randomises the menu state, runs one frame of the game's handler and the port on
the same RAM, and compares all of RAM (GPU packets and ordering tables included; only the
harness stack is excluded). Sound, music, CD, VRAM uploads and display-hardware calls are
stubbed.

Usage: python3 tools/research/verify_menu_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
import menu_sim as ms
import screens_sim as ss
import verify_draw_sim as vd
from psxcpu import load_release

log = logging.getLogger("verify_menu_sim")

HARDWARE = (0x8007C730,          # SetDispMask
            0x80029690,          # VRAM clear
            0x8004CD28, 0x8004C9E4, 0x8004CC04,  # archive uploads
            0x8007CA74, 0x8007C7C8,  # LoadImage, DrawSync
            0x8006AE4C, 0x8004B8B4)  # CD/sound system reset, sound keys off


CARD_CALLS = (0x8004C528, 0x8004C420, 0x8004C4B4)   # memory card load, save, format -> ms.CardStub cells


def status_stub(cpu, a: int, cell: int) -> None:
    """lui v0, hi; jr ra; lw v0, lo(v0): the function returns the word at `cell`."""
    cpu.write(a, struct.pack("<4I", 0x3C020000 | (cell + 0x8000) >> 16 & 0xFFFF, 0x03E00008,
                             0x8C420000 | cell & 0xFFFF, 0))


def zero_stub(cpu, a: int) -> None:
    cpu.write(a, struct.pack("<2I", 0x03E00008, 0x00001021))


def menu_cpu(name: str):
    cpu = vd.frame_cpu(name)
    for a in HARDWARE:
        zero_stub(cpu, a)
    for i, a in enumerate(CARD_CALLS):
        status_stub(cpu, a, ms.CARD.base + 4 * i)
    zero_stub(cpu, 0x800E24F0)                           # movie start
    status_stub(cpu, 0x800E2510, ms.MOVIE.cell)          # movie frame -> MovieStub
    return cpu


def transition_cpu():
    """For state 2: the loader, heap and enbu.ovl calls stubbed too (enbu's sit in title.ovl's data)."""
    cpu = menu_cpu("title")
    for a in (0x80055B6C, 0x80052CB4, 0x800D3C20, 0x800D3CA8):   # FightAllocBuffers, LoadOverlayAsync, enbu
        zero_stub(cpu, a)
    status_stub(cpu, 0x80052D58, ms.LOADER.cell)         # loader busy
    status_stub(cpu, 0x8004C1A8, ms.CARD.base + 0x10)    # AutoSave's card write
    cpu.write(0x8007A45C, struct.pack("<2I", 0x03E00008, 0x24020001))   # firstfile: found
    return cpu


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))
def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


def common(cpu, rng) -> None:
    vd.prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, vd.PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    w32(cpu, ds.DISPLAY_BUFFER, rng.randrange(2))
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0, 0x10, 0x800, 0x1000, 0x4000, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_REPEAT + 2 * p, rng.choice([0, 0, 0x1000, 0x4000, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0x800, 0x80C, rng.getrandbits(16)]))
    w16(cpu, 0x800A964C, rng.randrange(4))
    w32(cpu, ds.FRAME_COUNT2, rng.getrandbits(32))
    vd.random_ranking(cpu, rng)                  # statistics for the demonstration's costume
    ss_random_unlock(cpu, rng)


def ss_random_unlock(cpu, rng) -> None:
    import verify_screens_sim as vs
    vs.random_unlock_state(cpu, rng)


def case_main_menu(cpu, rng, chk) -> None:
    common(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.choice([0, 1, 1, 1, 2, 3]))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 7, 0x1DF, 0x1E0, rng.randrange(0x1E0)]))
    for i in range(10):
        e = ms.MENU_LIST + 8 * i
        w32(cpu, e, cpu.u32(ms.MENU_ENTRIES + 8 * i))
        w32(cpu, e + 4, cpu.u32(ms.MENU_ENTRIES + 8 * i + 4))
        w8(cpu, e + 7, rng.randrange(2))
    count = rng.randrange(8, 11)
    w32(cpu, ms.MENU_COUNT, count)
    if rng.random() < 0.3:                       # choose a mode other than options/theater
        w8(cpu, ms.MENU_LIST + 8 * rng.randrange(count) + 4, rng.randrange(9))
    w8(cpu, ms.MENU_CURSOR, rng.randrange(count + (cpu.u32(ss.SUB_STATE) & 0xFFFF == 1)))   # past the end only where clamped
    w32(cpu, ms.MENU_SCROLL, rng.choice([0, 0, 0x1C, -0x1C, rng.randrange(-100, 100)]))
    w32(cpu, ms.MENU_GLOW, rng.choice([0, 0x100, rng.randrange(0x100)]))
    w32(cpu, ms.MENU_CHOSEN, rng.randrange(2))
    w32(cpu, ms.MENU_PLAYERS, rng.randrange(4))
    w8(cpu, ms.MENU_TO_OPTIONS, rng.choice([0, 0, 1]))
    for a in (0x80098306, 0x80098307):
        w8(cpu, a, rng.randrange(4))
    for a in (0x80098304, 0x80098305, 0x800982EA, 0x800982F0, 0x800982E7, 0x800982E6, 0x800982E8, 0x800982E9,
              0x800982EC, 0x800982ED, 0x800982F9, 0x800982F3):
        w8(cpu, a, rng.randrange(10))
    for p in range(2):
        for k in range(8):
            w8(cpu, 0x80098308 + 8 * p + k, rng.randrange(14))
    w16(cpu, 0x800AE6CC, rng.choice([4, 4, 6]))
    for k in range(3):
        w16(cpu, 0x800A08B8 + 8 * k, rng.choice([0xE, rng.getrandbits(16)]))
    w16(cpu, 0x800A9708, rng.choice([0x14, rng.getrandbits(8)]))
    vd.run_gpu(chk, "MainMenu", cpu, lambda c: c.call(0x800DBBD0) and None, lambda r: ms.main_menu(r),
               show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


OPTION_VALUES = ((0x800982E6, 3), (0x800982E7, 5), (0x800982E8, 6), (0x800982EA, 2), (0x800982E9, 2),
                 (0x800982F9, 2), (0x800982F0, 2), (0x800982E5, 3), (0x800982E4, 2), (0x800982F1, 2))


def case_options(cpu, rng, chk, pages=(0, 1, 2, 2, 3, 3, 3, 4, 4, 5, 6)) -> None:
    common(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.choice([0, 1, 1, 1, 1, 2, 3]))
    w8(cpu, ms.OPT_PAGE, rng.choice(pages))
    for i in range(6):
        rec = ms.OPT_PAGES + ms.OPT_PAGE_SIZE * i
        n = cpu.u32(rec + 0x28)
        w32(cpu, rec, rng.randrange(max(n, 1)))
        w32(cpu, rec + 4, rng.choice([0, 0, 0, 1, 2, 3]))
    for a, n in OPTION_VALUES:
        w8(cpu, a, rng.randrange(n))
    w8(cpu, ms.COLOUR_SCHEME, rng.randrange(2))
    w8(cpu, ms.DISPLAY_X, rng.randrange(-8, 17))
    w8(cpu, ms.DISPLAY_Y, rng.randrange(-1, 10))
    w8(cpu, ss.BALL_NEW, rng.randrange(4))
    for k in range(4):
        w16(cpu, ms.SCREEN_RECT + 2 * k, rng.choice([(0, 0, 0x170, 0x1E0)[k], rng.randrange(-50, 500)]))
    for p in range(2):
        for k in range(8):
            w8(cpu, 0x80098308 + 8 * p + k, rng.randrange(14))
    w32(cpu, ds.MODE, rng.randrange(9))
    n = 0                                        # the mode icons as the page's set-up leaves them
    for i in range(8):
        mode, uv = cpu.u32(ms.OPT_MODES_SRC + 8 * i), cpu.u32(ms.OPT_MODES_SRC + 8 * i + 4)
        w32(cpu, ms.OPT_MODES + 8 * n, mode)
        w32(cpu, ms.OPT_MODES + 8 * n + 4, uv)
        n += mode != 7 or cpu.u32(ss.BALL_NEW) & 0xFF != 0
    w32(cpu, ms.OPT_MODES_COUNT, n)
    for p in range(2):                           # key configuration records as its page leaves them
        rec = ms.KEY_CONFIG + ms.KEY_CONFIG_SIZE * p
        w32(cpu, rec, p)
        w32(cpu, rec + 0x14, 0xB8 * p)
        w32(cpu, rec + 0x18, 0)
        for i in range(8):
            src, row = ms.KEY_ROWS_SRC + 0x18 * i, rec + 0x28 + 0x38 * i
            w32(cpu, row + 4, cpu.read(src + 2, 1)[0])
            w32(cpu, row + 8, struct.unpack("<H", cpu.read(src, 2))[0])
            w32(cpu, row + 0x10, cpu.read(src + 3, 1)[0])
            for k in range(8):
                w32(cpu, row + 0x14 + 4 * k, struct.unpack("<H", cpu.read(src + 4 + 2 * k, 2))[0])
            w32(cpu, row + 0x34, cpu.u32(src + 0x14))
        w32(cpu, rec + 4, rng.randrange(4))
        w32(cpu, rec + 8, rng.randrange(2))
        w32(cpu, rec + 0xC, rng.randrange(2))
        w8(cpu, 0x800A9620 + 0x2A * p, rng.choice([4, 5, 7, 9, rng.randrange(16)]))
        w8(cpu, ms.VIBRATION + p, rng.randrange(2))
        for i in range(8):
            row = rec + 0x28 + 0x38 * i
            state = rng.choice([0, 0, 0, 1, 2, 3])
            w32(cpu, row, state)
            w32(cpu, row + 0xC, {0: 0, 1: rng.randrange(1, 9), 2: 8, 3: rng.randrange(1, 8)}[state])
        for k in range(8):
            w8(cpu, 0x80098308 + 8 * p + k, rng.randrange(13))
    for i in range(4):                           # records lists (built when the page opens)
        lst = ms.REC_LISTS + 0x20 * i
        n = rng.choice([10, 22, rng.randrange(10, 23)])
        w32(cpu, lst + 4, n)
        w32(cpu, lst, rng.randrange(max(n - 9, 1)))
        ids = list(range(10 if i == 1 else 22))
        rng.shuffle(ids)
        for k in range(22):
            w8(cpu, lst + 8 + k, ids[k % len(ids)])
    w32(cpu, ms.REC_SUBPAGE, rng.randrange(4))
    w8(cpu, ms.CARD_STATE, rng.choice([0, 0, 1, 2, 3, 4, 5, 6, 7, rng.randrange(256)]))
    for i in range(3):
        w32(cpu, ms.CARD.base + 4 * i, rng.choice([0, 0, 2, 3, 4, 5, 1, rng.randrange(256)]))
    w32(cpu, ms.REC_TOTAL, rng.choice([0, rng.randrange(1, 100000), rng.getrandbits(32)]))
    for c in range(22):
        w32(cpu, ms.TIME_RECORDS + 8 * c, rng.choice([359_999, 359_998, rng.randrange(360_000), 400_000,
                                                       rng.getrandbits(32)]))
        for k in range(4):
            w16(cpu, ss.STATS + 8 * c + 2 * k, rng.choice([0, rng.randrange(20), rng.randrange(65536)]))
    held = rng.choice([0, 0x103, 0x900, rng.getrandbits(16), 1 << rng.randrange(8), 1 << rng.randrange(16)])
    w16(cpu, ss.PAD_HELD, held)
    r = rng.random()
    if r < 0.2:
        w16(cpu, ss.PAD_PRESSED, rng.choice([0x100, 0x800]))
        w16(cpu, ss.PAD_PRESSED + 2, 0)
    elif r < 0.6:                                # quiet pads reach the deeper screens (records, card)
        w16(cpu, ss.PAD_PRESSED, rng.choice([0, 0, 0x800, 0x1000, 0x4000]))
        w16(cpu, ss.PAD_PRESSED + 2, 0)
    vd.run_gpu(chk, "Options", cpu, lambda c: c.call(0x800DE480), lambda r: ms.options(r),
               show=f"page {cpu.u32(ms.OPT_PAGE) & 0xFF} sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def case_title(cpu, rng, chk) -> None:
    common(cpu, rng)
    w32(cpu, ss.UNLOCKED, cpu.u32(ss.UNLOCKED) | 0x3FF)   # the ten starting characters are always there
    w16(cpu, ss.SUB_STATE, rng.choice(list(range(12)) + [0xFFFF, rng.randrange(65536)]))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 2, 3, 10, 11, 0xF5, 0xF6, 0x100, 300, rng.randrange(-5, 400)]))
    w8(cpu, ms.TITLE_CYCLE, rng.randrange(5))
    w32(cpu, ms.TITLE_KIND, rng.randrange(9))
    w32(cpu, ms.MOVIE_RESULT, rng.choice([0, -1, 1, 5]))
    w32(cpu, ms.MOVIE.cell, rng.choice([0, 0, 1, -1, 3]))
    w32(cpu, ms.STREAM_ACTIVE, 0)
    w8(cpu, ms.DISPLAY_X, rng.randrange(-8, 17))
    w8(cpu, ms.DISPLAY_Y, rng.randrange(-1, 10))
    if rng.random() < 0.6:
        w16(cpu, ss.PAD_PRESSED, rng.choice([0, 0x10, 0x4000]))
        w16(cpu, ss.PAD_PRESSED + 2, 0)
    for a in (0x800982E6, 0x800982E7, 0x800982E8, 0x800982E9, 0x800982EA, 0x800982F0, 0x800982E5):
        w8(cpu, a, rng.randrange(3))
    for k in range(3):
        w16(cpu, 0x800A08B8 + 8 * k, rng.choice([0xE, rng.getrandbits(16)]))
    vd.run_gpu(chk, "Title", cpu, lambda c: c.call(0x800DB7D4), lambda r: ms.title_sequence(r),
               show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def case_transition(cpu, rng, chk) -> None:
    common(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.choice(list(range(14)) + [0xFFFF]))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 0x20, 0x21, rng.randrange(-3, 40), rng.getrandbits(32)]))
    for a in (ms.TARGET, ms.PREVIOUS):
        w8(cpu, a, rng.choice([3, 4, 5, 6, 9, 19, rng.randrange(20)]))
    for a in (ms.ENBU_TARGET, ms.ENBU_CACHED, ms.CARD_READ, ms.AUTO_SAVE, ss.SAVE_PENDING):
        w8(cpu, a, rng.randrange(2))
    w8(cpu, ms.CACHE, rng.randrange(6))
    w8(cpu, ms.TITLE_CYCLE, rng.randrange(4))
    w8(cpu, ms.SAVE_ERROR, rng.choice([0, 0, 1, 0x78]))
    w32(cpu, ms.LOADER.cell, rng.choice([0, 0, 1]))
    w32(cpu, ms.CARD.base + 0x10, rng.choice([0, 0, 1, 5]))
    if rng.random() < 0.6:
        w16(cpu, ss.PAD_PRESSED, rng.choice([0, 0x10]))
        w16(cpu, ss.PAD_PRESSED + 2, 0)
    vd.run_gpu(chk, "Transition", cpu, lambda c: c.call(0x8004FD48) & 0xFFFFFFFF, lambda r: ms.transition_screen(r),
               show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def case_enbu(cpu, rng, chk) -> None:
    """enbu.ovl: its copy of the title pictures and the title card before the demonstration fight."""
    common(cpu, rng)
    kind = rng.randrange(10)
    vd.run_gpu(chk, "EnbuBackdrop", cpu, lambda c: c.call(0x800D2C30, kind) and None,
               lambda r: ms.title_backdrop(r, kind), show=f"kind {kind}")
    common(cpu, rng)
    start = rng.random() < 0.2
    w16(cpu, ss.SUB_STATE, rng.choice([1, 2, 3, 8, 4, 5, 6, 7]) if start else rng.choice([4, 5, 6, 7]))
    w16(cpu, ss.PAD_PRESSED, 0x800 if start else rng.getrandbits(16) & ~0x800)
    w16(cpu, ss.PAD_PRESSED + 2, rng.getrandbits(16) & ~0x800)
    w32(cpu, ss.STATE_TIMER, rng.choice([-1, 0, 1, 2, 3, 4, 8, 9, 0x100, 300, rng.randrange(-5, 400)]))
    w32(cpu, ms.ENBU_KIND, rng.randrange(9))
    w8(cpu, ms.TITLE_CYCLE, rng.randrange(4))
    vd.run_gpu(chk, "EnbuFrame", cpu, lambda c: 1 if c.call(0x800D3844) == 1 and start else None,
               lambda r: ms.enbu_frame(r), show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


NAMES = ["MainMenu", "Options", "Title", "Transition", "EnbuBackdrop", "EnbuFrame"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = menu_cpu("title")
    tcpu = transition_cpu()
    ecpu = menu_cpu("enbu")
    for _ in range(args.cases):
        case_main_menu(cpu, rng, chk)
        case_options(cpu, rng, chk)
        case_title(cpu, rng, chk)
        case_transition(tcpu, rng, chk)
        case_enbu(ecpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
