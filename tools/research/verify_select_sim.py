#!/usr/bin/env python3
"""Compare select_sim.py with select.ovl (character select, Japan Rev.1) in the CPU harness.

Each case randomises the screen state, runs the game's routine and the port on the same RAM and
compares all of RAM (GPU packets and ordering tables included; only the harness stack is
excluded). Sound, music, VRAM uploads and the big-portrait TIM loads are stubbed.

Usage: python3 tools/research/verify_select_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
import screens_sim as ss
import select_sim as sel
import verify_draw_sim as vd
import verify_menu_sim as vm

log = logging.getLogger("verify_select_sim")


def select_cpu():
    cpu = vm.menu_cpu("select")
    cpu.write(0x8010EB74, struct.pack("<I", 0x00001021))   # FUN_8010EA2C: skip the portrait TIM load
    return cpu


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))
def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


def random_unlocks(cpu, rng) -> None:
    w32(cpu, ss.UNLOCKED, rng.choice([0x3FF, 0x1FFFFF, 0x3FF | rng.getrandbits(21), rng.getrandbits(21),
                                      0, 1 << rng.randrange(21), 0x3FF & rng.getrandbits(10)]))


def case_grid(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_unlocks(cpu, rng)
    for i in range(22 * 12):
        w8(cpu, sel.CELLS + i, rng.getrandbits(8))
    vd.run_gpu(chk, "GridBuild", cpu, lambda c: c.call(0x8010DC04, sel.CTX) and None,
               lambda r: sel.grid_build(r))


def random_players(cpu, rng) -> None:
    """A built grid and two player records in any state."""
    random_unlocks(cpu, rng)
    cpu.call(0x8010DC04, sel.CTX)
    w32(cpu, sel.CTX, rng.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, rng.randrange(12)]))
    w32(cpu, sel.CTX + 0xC, rng.randrange(3))
    w32(cpu, sel.CTX + 0x14, rng.choice([0, 0, 1, 100, rng.randrange(2000)]))
    w32(cpu, sel.CTX + 8, rng.getrandbits(32))
    for p in range(2):
        rec = sel.rec_of(sel.CTX, p)
        w32(cpu, rec, rng.choice([0, 1, 1, 2, 3, 3, 4, 5, 6, 7]))
        w32(cpu, rec + 4, rng.randrange(22))
        for off in (0x14, 0x1C, 0x3C):
            w32(cpu, rec + off, rng.choice([rng.randrange(0x16), 0x16, rng.randrange(0x18)]))
        for off in (0x18, 0x20, 0x40):
            w32(cpu, rec + off, rng.randrange(4))
        w32(cpu, rec + 0x24, rng.choice([0, 1, 0x5A, rng.randrange(-3, 100)]))
        for k in range(10):
            w32(cpu, rec + 0x54 + 4 * k, cpu.u32(sel.PLAYER_LAYOUT + 0x28 * p + 4 * k))
        w16(cpu, rec + 0x78, rng.randrange(22))
        w16(cpu, ss.PLAYER_ACTIVE + 2 * p, rng.randrange(2))
        w16(cpu, ss.KEEP_CHAR + 2 * p, rng.randrange(2))
        w16(cpu, 0x800AE224 + 2 * p, rng.choice([rng.randrange(0x16), rng.randrange(0x18)]))
        w16(cpu, 0x800AE260 + 2 * p, rng.randrange(4))
    w32(cpu, 0x800982D4, rng.getrandbits(21))
    w8(cpu, 0x800AFF55, rng.randrange(2))
    w16(cpu, 0x800AE6DA, rng.choice([0, 0, 1]))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0x10, 0x20, 0x40, 0x80, 0x100, 0x800, 0x810,
                                                      rng.getrandbits(16)]))
        w16(cpu, ss.PAD_REPEAT + 2 * p, rng.choice([0, 0, 0x1000, 0x2000, 0x4000, 0x8000, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0x800, 0x80C, rng.getrandbits(16)]))


def case_players(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_players(cpu, rng)
    p = rng.randrange(2)
    vd.run_gpu(chk, "PlayerStep", cpu, lambda c: c.call(0x8010E250, sel.CTX, p) & 0xFFFFFFFF,
               lambda r: sel.player_step(r, sel.CTX, p), show=f"state {cpu.u32(sel.rec_of(sel.CTX, p))}")
    w32(cpu, ds.MODE, rng.randrange(9))
    vd.run_gpu(chk, "Commit", cpu, lambda c: c.call(0x8010E948, ds.MODE, sel.CTX) and None,
               lambda r: sel.commit(r, ds.MODE, sel.CTX))
    vd.run_gpu(chk, "PortraitUpdate", cpu, lambda c: c.call(0x8010EA2C, sel.CTX) and None,
               lambda r: sel.portrait_update(r, sel.CTX))


def random_screen(cpu, rng) -> None:
    """random_players plus the layout values, slides, sparks and timers of a running screen."""
    random_players(cpu, rng)
    w32(cpu, sel.CTX + 4, rng.randrange(2))
    lay = sel.LAYOUTS + 0x30 * (cpu.u32(sel.CTX + 4) & 1)
    for k in range(12):
        w32(cpu, sel.CTX + 0x11C + 4 * k, cpu.u32(lay + 4 * k))
    w32(cpu, sel.CTX + 0x10, rng.choice([0, 0, 1, 0xB4, rng.randrange(0xB4)]))
    w32(cpu, sel.CTX + 0x18, rng.choice([0x3C, 0x3F, rng.randrange(1, 100)]))
    w32(cpu, sel.CTX + 0x14, rng.randrange(0x3C * 20))
    w32(cpu, sel.CTX + 0x148, rng.randrange(16))
    for p in range(2):
        rec = sel.rec_of(sel.CTX, p)
        w32(cpu, rec + 8, rng.randrange(5))
        w32(cpu, rec + 0xC, rng.choice([1, 2, 3, 0, rng.randrange(5)]))
        w32(cpu, rec + 0x10, rng.randrange(2))
        w32(cpu, rec + 0x28, rng.randrange(32))
        w32(cpu, rec + 0x2C, rng.choice([0, rng.randrange(0x80)]))
        w32(cpu, rec + 0x30, rng.choice([0, 0, 0x1C, rng.randrange(0x20)]))
        w32(cpu, rec + 0x14, rng.choice([rng.randrange(0x16), 0x16]))
        w32(cpu, rec + 0x18, rng.randrange(4))
    for i in range(sel.SPARK_COUNT):
        s = sel.CTX + sel.SPARKS + sel.SPARK_SIZE * i
        w16(cpu, s, rng.choice([0, 0, 1, 2]))
        w16(cpu, s + 2, rng.choice([0, 1, 1, 2]))
        for off in (4, 6, 8, 0xA):
            w16(cpu, s + off, rng.getrandbits(16) if rng.random() < 0.3 else rng.randrange(-50, 400))
        w32(cpu, s + 0xC, rng.randrange(-10, 0x70))
        w32(cpu, s + 0x10, rng.randrange(8))
    w32(cpu, ds.PACKET_PTR, vd.PACKETS)
    for k, v in enumerate((0, 0, 0x170, 0x1E0)):
        w16(cpu, 0x800AE6F8 + 2 * k, rng.choice([v, v, rng.randrange(-20, 500)]))


DRAWS = (("NewArrows", 0x8010EC9C, sel.new_arrows), ("NamePlates", 0x8010EDFC, sel.name_plates),
         ("Sparks", 0x8010F1B4, sel.sparks), ("Portraits", 0x8010F760, sel.portraits),
         ("Backlights", 0x8010FBFC, sel.backlights), ("GridFaces", 0x8010FD64, sel.grid_faces),
         ("Cursors", 0x8010FEA0, sel.cursors), ("Pictures", 0x80110154, sel.pictures),
         ("Background", 0x801102A0, sel.background))


def case_draws(cpu, rng, chk) -> None:
    for name, addr, fn in DRAWS:
        vm.common(cpu, rng)
        random_screen(cpu, rng)
        if name == "NamePlates" and cpu.u32(sel.CTX) >= 9:
            w32(cpu, sel.CTX, rng.randrange(9))
        vd.run_gpu(chk, name, cpu, lambda c: c.call(addr, sel.CTX) and None, lambda r: fn(r, sel.CTX))


def case_frame(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_screen(cpu, rng)
    w32(cpu, sel.CTX, rng.randrange(9))
    w16(cpu, ss.SUB_STATE, rng.choice([0, 1, 1, 1, 2, 3]))
    w32(cpu, sel.CTX + 8, rng.choice([0, 1, 2, 3, rng.randrange(1000)]))
    w32(cpu, ds.MODE, rng.randrange(9))
    w8(cpu, ds.MODE + 0x14, rng.randrange(20))
    w8(cpu, ds.MODE + 0x15, rng.randrange(5))
    for p in range(2):
        w8(cpu, 0x800982EE + p, rng.getrandbits(8))
    for k in range(3):
        w16(cpu, 0x800A08B8 + 8 * k, rng.choice([0xE, rng.getrandbits(16)]))
    vd.run_gpu(chk, "Frame", cpu, lambda c: c.call(0x8011056C) & 0xFFFFFFFF, lambda r: sel.character_select(r),
               show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def quick_cpu():
    return vm.menu_cpu("arcade")


def random_quick(cpu, rng) -> None:
    """Two quick-select records in any state (Tekken Ball's volley.ovl states excluded)."""
    random_unlocks(cpu, rng)
    q = sel.QCTX
    w32(cpu, q, rng.choice([0, 1, 2, 3, 4, 5, 6, 8, 9, 10, 11]))   # Tekken Ball (7) needs volley.ovl
    w32(cpu, q + 8, rng.choice([0, 1, 1, 2]))
    w32(cpu, q + 0xC, rng.choice([0, 0x10, 0xF0, 0x100, rng.randrange(0x120)]))
    w32(cpu, ds.MODE, rng.choice([0, 1, 2, 3, 4, 5, 6, 8]))
    for p in range(2):
        rec = sel.qrec_of(q, p)
        w32(cpu, rec, rng.choice([0, 1, 2, 3, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14]))
        w32(cpu, rec + 8, rng.choice([rng.randrange(7), rng.randrange(9)]))
        w32(cpu, rec + 0xC, rng.choice([rng.randrange(3), rng.randrange(5)]))
        w32(cpu, rec + 0x24, rng.choice([cpu.u32(ss.UNLOCKED), rng.getrandbits(22)]))
        w32(cpu, rec + 0x28, rng.choice([1, 2, 4, rng.randrange(10)]))
        n = rng.randrange(cpu.u32(rec + 0x28) + 1)
        w32(cpu, rec + 0x2C, n)
        for i in range(8):
            w32(cpu, rec + 0x38 + 4 * i, rng.choice([rng.randrange(0x58), 0x58, 0x59]))
        w32(cpu, rec + 0x34, rng.randrange(2))
        w32(cpu, rec + 0x58, rng.randrange(8))
        w32(cpu, rec + 0x64, rng.choice([rng.randrange(0x58), 0x58, rng.getrandbits(8)]))
        for k in range(0x34 // 4):
            w32(cpu, rec + 0x78 + 4 * k, cpu.u32(sel.QPLAYER_PREFS + 0x34 * p + 4 * k))
        w16(cpu, rec + 0x98, rng.randrange(2))
        w16(cpu, ss.PLAYER_ACTIVE + 2 * p, rng.randrange(2))
        w16(cpu, ss.KEEP_CHAR + 2 * p, rng.randrange(2))
        w16(cpu, 0x800AE224 + 2 * p, rng.randrange(0x16))
        w16(cpu, 0x800AE260 + 2 * p, rng.randrange(4))
        w8(cpu, ds.MODE + 0x65 + 13 * p, rng.randrange(1, 9))
        w16(cpu, ds.MODE + 0x3A + 4 * p, rng.randrange(8))
    w32(cpu, 0x800982D4, rng.getrandbits(21))
    w8(cpu, 0x800AFF55, rng.randrange(2))
    w8(cpu, ds.MODE + 0x43, rng.choice([0, 1, 2]))
    w16(cpu, 0x800AE6DA, rng.choice([0, 0, 1]))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0x10, 0x20, 0x40, 0x80, 0x100, 0x800, 0x810,
                                                      rng.getrandbits(16)]))
        w16(cpu, ss.PAD_REPEAT + 2 * p, rng.choice([0, 0, 0x1000, 0x2000, 0x4000, 0x8000, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0x800, 0x80C, rng.getrandbits(16)]))


def case_quick(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_quick(cpu, rng)
    q = sel.QCTX
    p = rng.randrange(2)
    rec = sel.qrec_of(q, p)
    pad = rng.getrandbits(16)
    vd.run_gpu(chk, "QuickPick", cpu, lambda c: c.call(0x800530CC, q, rec, pad) & 0xFFFFFFFF,
               lambda r: sel.quick_pick(r, q, rec, pad))
    vd.run_gpu(chk, "QuickStep", cpu, lambda c: c.call(0x800532E8, ds.MODE, q, p) & 0xFFFFFFFF,
               lambda r: sel.quick_step(r, ds.MODE, q, p), show=f"state {cpu.u32(rec)} mode {cpu.u32(q)}")
    vd.run_gpu(chk, "QuickCommit", cpu, lambda c: c.call(0x80054294, ds.MODE, q) and None,
               lambda r: sel.quick_commit(r, ds.MODE, q))


QDRAWS = (("QuickMembers", 0x8005447C, sel.quick_members), ("QuickCursors", 0x80054668, sel.quick_cursors),
          ("QuickTexts", 0x8005497C, sel.quick_texts), ("QuickTitle", 0x80054E30, sel.quick_title),
          ("QuickGrid", 0x80054FE8, sel.quick_grid), ("QuickBackground", 0x80055368, sel.quick_background))


def random_quick_screen(cpu, rng) -> None:
    random_quick(cpu, rng)
    q = sel.QCTX
    w32(cpu, q, rng.choice([0, 1, 2, 3, 4]))
    for off in (4, 0x10):
        w32(cpu, q + off, rng.choice([0, 1, 0x1DF, 0x1E0, 0x2C0, rng.randrange(0x400), rng.getrandbits(32)]))
    # the countdown: a huge value makes the game's own timer digits read past their table
    w32(cpu, q + 0x14, rng.choice([0, 1, 0x1DF, 0x1E0, 0x2C0, rng.randrange(0x400)]))
    for p in range(2):
        rec = sel.qrec_of(q, p)
        w32(cpu, rec + 0x18, rng.randrange(5))
        w32(cpu, rec + 0x1C, rng.randrange(6))
        w32(cpu, rec + 0x20, rng.randrange(5))
        w32(cpu, rec + 0x28, rng.randrange(9))
        w32(cpu, rec + 0x2C, rng.randrange(9))
        w32(cpu, rec + 0x10, cpu.u32(rec + 0x90) if rng.random() < 0.7 else rng.randrange(400))
        w32(cpu, rec + 0x14, cpu.u32(rec + 0x92) & 0xFFFF if rng.random() < 0.7 else rng.randrange(400))
        w32(cpu, rec + 0x5C, rng.choice([cpu.u32(rec + 0x9A) & 0xFFFF, cpu.u32(rec + 0x9C) & 0xFFFF]))
        w32(cpu, rec + 0x60, rng.choice([cpu.u32(rec + 0x5C), rng.randrange(-100, 400)]))
        w32(cpu, rec + 0x58, rng.randrange(8))
    w32(cpu, ds.PACKET_PTR, vd.PACKETS)
    for k, v in enumerate((0, 0, 0x170, 0x1E0)):
        w16(cpu, 0x800AE6F8 + 2 * k, rng.choice([v, v, rng.randrange(-20, 500)]))


def case_quick_draws(cpu, rng, chk) -> None:
    for name, addr, fn in QDRAWS:
        vm.common(cpu, rng)
        random_quick_screen(cpu, rng)
        if rng.random() < 0.5:
            w16(cpu, ss.PAD_HELD, 0)
            w16(cpu, ss.PAD_HELD + 2, 0)
        vd.run_gpu(chk, name, cpu, lambda c: c.call(addr, sel.QCTX) and None, lambda r: fn(r, sel.QCTX))
    vm.common(cpu, rng)
    random_quick_screen(cpu, rng)
    w32(cpu, sel.QCTX, 1)
    w32(cpu, ds.MODE, 1)
    for k in range(3):
        w16(cpu, ds.MODE + 0x38 + 4 * k, rng.choice([0, 7, 99, 100, 250, rng.randrange(65536)]))
    vd.run_gpu(chk, "VsHandicaps", cpu, lambda c: c.call(0x800B3204, sel.QCTX) and None,
               lambda r: sel.vs_handicaps(r, sel.QCTX))
    vd.run_gpu(chk, "VsRecord", cpu, lambda c: c.call(0x800B2D44, ds.MODE) and None,
               lambda r: sel.vs_record(r, ds.MODE))


def case_quick_frame(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_quick_screen(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.choice([0, 1, 2, 2, 2, 3, 4]))
    w32(cpu, sel.QCTX + 8, rng.choice([0, 0, 1, 2]))
    w32(cpu, ds.MODE, cpu.u32(sel.QCTX) if rng.random() < 0.8 else rng.choice([0, 1, 2, 3, 4]))
    w8(cpu, ds.MODE + 0x14, rng.randrange(20))
    w8(cpu, ds.MODE + 0x15, rng.randrange(5))
    for p in range(2):
        w8(cpu, 0x800982EE + p, rng.getrandbits(8))
    vd.run_gpu(chk, "QuickFrame", cpu, lambda c: c.call(0x80055878) and None, lambda r: sel.quick_select(r) and None,
               show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF} mode {cpu.u32(sel.QCTX)}")


def case_quick_practice(cpu, rng, chk, mode=5, name="QuickBackgroundPractice") -> None:
    """Quick select in practice (or Tekken Force) mode: the overlay's backdrop hook."""
    vm.common(cpu, rng)
    random_quick_screen(cpu, rng)
    w32(cpu, sel.QCTX, mode)
    vd.run_gpu(chk, name, cpu, lambda c: c.call(0x80055368, sel.QCTX) and None,
               lambda r: sel.quick_background(r, sel.QCTX))


BALL_AREA = 0x801E0000           # a free RAM area for the ball object


def ball_cpu():
    cpu = vm.menu_cpu("volley")
    for a in (0x800B3198, 0x800B0DD8, 0x80039BB4, 0x80082B0C):   # ball renderer and scene set-up
        vm.zero_stub(cpu, a)
    return cpu


def random_ball(cpu, rng) -> None:
    w32(cpu, sel.BALL_PTR, BALL_AREA)
    for off in range(0, 0x150, 4):
        w32(cpu, BALL_AREA + off, rng.getrandbits(32))
    w32(cpu, BALL_AREA + 0x68, rng.choice([0, 0x800, -0x800, 0x7FF, -0x7FF, 0x1000, rng.randrange(-0x1400, 0x1400)]))
    w32(cpu, BALL_AREA + 0x78, rng.choice([0, 0x1000, -0x1000, rng.randrange(-0x1400, 0x1400)]))
    w16(cpu, BALL_AREA + 0xB0, rng.choice([1, 0xFFFF, 0]))
    w8(cpu, ds.MODE + 0x40, rng.randrange(2))
    w8(cpu, ds.MODE + 0x41, rng.randrange(3))
    w8(cpu, ds.MODE + 0x43, rng.choice([0, 1, 2, 3, 3]))


POPUP_SLOTS = 0x800B6B58


def random_popups(cpu, rng) -> None:
    """A doubly linked list of popup texts in the eight slots, in random order."""
    order = rng.sample(range(8), rng.randrange(0, 9))
    nodes = [POPUP_SLOTS + 0x20 * i for i in order]
    for i, n in enumerate(nodes):
        body = rng.choice([b"!", b"12", b"100", b"7"])
        cpu.write(n + 8, b"%p%c%f%H%V" + body + b"\0")
        w32(cpu, n, nodes[i + 1] if i + 1 < len(nodes) else 0)
        w32(cpu, n + 4, nodes[i - 1] if i else 0)
        cpu.write(n + 0x18, struct.pack("<hhBBBB", rng.randrange(-20, 380), rng.randrange(-20, 480),
                                         rng.randrange(1, 8), rng.randrange(2), rng.choice([0, 0, 1, 2, 30]), 1))
    w32(cpu, ds.BALL_POPUPS, nodes[0] if nodes else 0)


def case_ball_hud(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    for g in range(2):
        r = ds.BALL_GAUGES + 0x10 * g
        w32(cpu, r, rng.choice([0, 50, rng.randrange(-5, 130)]))
        for off in (4, 6, 8):
            w16(cpu, r + off, rng.choice([0, 3, 40, 76, rng.randrange(-5, 90)]))
    w32(cpu, ds.PAUSED, rng.choice([0, 0, 1]))
    p1, p2 = rng.choice([0, 50, 100, rng.randrange(-10, 150)]), rng.choice([0, 25, 100, rng.randrange(-10, 150)])
    mx, hl = rng.choice([100, 100, rng.randrange(1, 200)]), rng.choice([0, 1, 2, 3])
    vd.run_gpu(chk, "BallGauges", cpu, lambda c: c.call(0x800B4E6C, p1, mx, p2, hl) and None,
               lambda r: ds.ball_gauges(r, p1, mx, p2, hl))
    vm.common(cpu, rng)
    random_popups(cpu, rng)
    frozen = rng.choice([0, 0, 1])
    vd.run_gpu(chk, "BallPopups", cpu, lambda c: c.call(0x800B4350, frozen) and None,
               lambda r: ds.ball_popups(r, frozen))


def case_ball_popup_add(cpu, rng, chk) -> None:
    import copy
    import verify_projection_sim as vp
    vm.common(cpu, rng)
    random_popups(cpu, rng)
    vp.random_gte(cpu, rng)
    cpu.write(0x800AE438, vp.random_matrix(rng))
    w32(cpu, ds.POPUP_NEXT, rng.choice([0, 3, 7, -1, rng.randrange(-9, 9)]))
    text, pos = 0x801F8300, 0x801F8340
    cpu.write(text, rng.choice([b"!", b"12", b"100", b""]) + b"\0")
    cpu.write(pos, struct.pack("<3i", *(rng.randrange(-0x40000, 0x40000) for _ in range(3))))
    colour, font, frames = rng.randrange(1, 8), rng.choice([0, 1, 1, 2, 3]), rng.choice([0x1E, 1, 0])
    before, scratch = vd.gsnap(cpu)
    ram = ds.GpuRam(before, scratch)
    g2 = copy.deepcopy(cpu.gte)
    cpu.call(0x800B445C, text, pos, colour, font, frames)
    ds.ball_popup_add(ram, g2, text, pos, colour, font, frames)
    d = vd.diff(vd.gsnap(cpu)[0], bytes(ram.data[:ds.RAM_SIZE]))
    c = chk["BallPopupAdd"]
    c.cases += 1
    if d or tuple(cpu.gte.read_ctrl(r) for r in (5, 6, 7)) != tuple(g2.read_ctrl(r) for r in (5, 6, 7)):
        c.bad += 1
        if c.bad <= 5:
            vd.log.info("  BallPopupAdd mismatch %s", [hex(a) for a in d])


def case_ball(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_quick_screen(cpu, rng)
    random_ball(cpu, rng)
    q = sel.QCTX
    w32(cpu, q, 7)
    w32(cpu, ds.MODE, 7)
    vd.run_gpu(chk, "BallSideSelect", cpu, lambda c: c.call(0x800B569C) & 0xFFFFFFFF, lambda r: sel.BALL.side_select(r))
    vd.run_gpu(chk, "BallDraw", cpu, lambda c: c.call(0x800B593C) and None, lambda r: sel.BALL.draw(r))
    vd.run_gpu(chk, "BallStart", cpu, lambda c: c.call(0x800B5B6C, 1) and None, lambda r: sel.BALL.start(r))
    p = rng.randrange(2)
    rec = sel.qrec_of(q, p)
    arg = cpu.u32(rec + 0x9C) & 0xFFFF
    vd.run_gpu(chk, "BallSetup", cpu, lambda c: c.call(0x800B5C4C, ds.MODE, rec, p, arg) and None,
               lambda r: sel.BALL.setup(r, ds.MODE, rec, p, arg))
    vm.common(cpu, rng)
    random_quick_screen(cpu, rng)
    random_ball(cpu, rng)
    w32(cpu, q, 7)
    w32(cpu, ds.MODE, 7)
    w32(cpu, rec, rng.choice([0, 2, 3, 14, 15, 15]))
    vd.run_gpu(chk, "BallQuickStep", cpu, lambda c: c.call(0x800532E8, ds.MODE, q, p) & 0xFFFFFFFF,
               lambda r: sel.quick_step(r, ds.MODE, q, p), show=f"state {cpu.u32(rec)}")
    vm.common(cpu, rng)
    random_quick_screen(cpu, rng)
    random_ball(cpu, rng)
    w32(cpu, q, 7)
    w32(cpu, ds.MODE, 7)
    w16(cpu, ss.SUB_STATE, rng.choice([1, 2, 2, 3]))
    w32(cpu, q + 8, rng.choice([0, 1]))
    vd.run_gpu(chk, "BallQuickFrame", cpu, lambda c: c.call(0x80055878) and None, lambda r: sel.quick_select(r) and None,
               show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


NAMES = ["BallGauges", "BallPopups", "BallPopupAdd", "BallSideSelect", "BallDraw", "BallStart", "BallSetup", "BallQuickStep", "BallQuickFrame", "QuickBackgroundPractice", "QuickBackgroundForce"] + [d[0] for d in QDRAWS] + ["VsHandicaps", "VsRecord", "QuickFrame", "QuickPick", "QuickStep", "QuickCommit", "GridBuild", "PlayerStep", "Commit", "PortraitUpdate"] + [d[0] for d in DRAWS] + ["Frame"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=1000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = select_cpu()
    qcpu = quick_cpu()
    qpcpu = vm.menu_cpu("practice")
    bcpu = ball_cpu()
    fcpu = vm.menu_cpu("force")
    for _ in range(args.cases):
        case_quick(qcpu, rng, chk)
        case_quick_draws(qcpu, rng, chk)
        case_quick_frame(qcpu, rng, chk)
        case_quick_practice(qpcpu, rng, chk)
        case_ball(bcpu, rng, chk)
        case_ball_hud(bcpu, rng, chk)
        case_ball_popup_add(bcpu, rng, chk)
        case_quick_practice(fcpu, rng, chk, 8, "QuickBackgroundForce")
        case_grid(cpu, rng, chk)
        case_players(cpu, rng, chk)
        case_draws(cpu, rng, chk)
        case_frame(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
