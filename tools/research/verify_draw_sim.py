#!/usr/bin/env python3
"""Compare draw_sim.py with the game's drawing code in the CPU harness (Japan Rev.1).

The GPU packet builders, the text engine and the screen drawing routines run on random
arguments and state; the packet buffer, the ordering table and all other RAM are compared
byte for byte afterwards (only the harness stack is excluded).

Usage: python3 tools/research/verify_draw_sim.py [--cases N] [--seed S] [--only NAME]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
from fight_sim import Ram
from psxcpu import STACK_TOP, load_release

log = logging.getLogger("verify_draw_sim")

RAM_START, RAM_SIZE = 0x80000000, 0x200000
OT = 0x801F9000                  # test ordering table (64 entries)
PACKETS = 0x801E8000             # test packet buffer
STRINGS = 0x801F9800             # test format strings
STUB_ZERO = (0x800756A4, 0x800758E8, 0x8006B0FC, 0x8007B27C)


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))
def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


def snapshot(cpu) -> bytes:
    return cpu.read(RAM_START, RAM_SIZE)


def diff(game: bytes, port: bytes) -> list[int]:
    lo, hi = STACK_TOP - 0x4000 - RAM_START, STACK_TOP - RAM_START
    g, p = bytearray(game), bytearray(port)
    g[lo:hi] = p[lo:hi] = bytes(hi - lo)
    if g == p:
        return []
    return [RAM_START + i for i in range(RAM_SIZE) if g[i] != p[i]][:9]


class Checker:
    def __init__(self, name: str):
        self.name, self.cases, self.bad = name, 0, 0

    def run(self, cpu, game, port, show="") -> None:
        ram = Ram(snapshot(cpu))
        gv = game(cpu)
        pv = port(ram)
        d = diff(snapshot(cpu), bytes(ram.data))
        self.cases += 1
        if d or (pv is not None and (gv & 0xFFFFFFFF) != (pv & 0xFFFFFFFF)):
            self.bad += 1
            if self.bad <= 5:
                log.info("  %s mismatch: game %s port %s bytes %s %s", self.name,
                         hex(gv & 0xFFFFFFFF) if gv is not None else gv,
                         hex(pv & 0xFFFFFFFF) if pv is not None else pv, [hex(a) for a in d], show)

    def report(self) -> bool:
        log.info("%s: %d cases, %d mismatches", self.name, self.cases, self.bad)
        return self.bad == 0


def log_stub(cpu, a: int, cell: int, reg: int) -> None:
    """Replace the function at `a` by one that appends register `reg` to the log at `cell`
    (u32 count, then the values); `ram_log` writes the same log from a port."""
    t0, t1, t2 = 8, 9, 10
    hi, lo = (cell + 0x8000) >> 16 & 0xFFFF, cell & 0xFFFF
    code = (0x3C000000 | t0 << 16 | hi,                        # lui t0, hi
            0x8C000000 | t0 << 21 | t1 << 16 | lo,             # lw t1, lo(t0)
            0,
            t1 << 16 | t2 << 11 | 2 << 6,                      # sll t2, t1, 2
            t2 << 21 | t0 << 16 | t2 << 11 | 0x21,             # addu t2, t2, t0
            0xAC000000 | t2 << 21 | reg << 16 | lo + 4 & 0xFFFF,  # sw reg, lo+4(t2)
            0x24000000 | t1 << 21 | t1 << 16 | 1,              # addiu t1, t1, 1
            0x03E00008,                                        # jr ra
            0xAC000000 | t0 << 21 | t1 << 16 | lo)             # sw t1, lo(t0)
    cpu.write(a, struct.pack(f"<{len(code)}I", *code))


def ram_log(ram: Ram, cell: int, value: int) -> None:
    n = ram.u32(cell)
    ram.put(cell + 4 + 4 * n, "I", value & 0xFFFFFFFF)
    ram.put(cell, "I", n + 1 & 0xFFFFFFFF)


def prepare(cpu, rng) -> None:
    for i in range(64):
        w32(cpu, OT + 4 * i, rng.choice([0x00FFFFFF, rng.getrandbits(32)]))
    w32(cpu, ds.OT_BASE, OT)


def call(cpu, addr, *args):
    return cpu.call(addr, *args) & 0xFFFFFFFF


def rand_word(rng) -> int:
    return rng.choice([rng.getrandbits(32), rng.getrandbits(16), rng.randrange(-400, 400) & 0xFFFFFFFF])


def case_prims(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    ot = OT + 4 * rng.randrange(64)
    p = PACKETS + 4 * rng.randrange(64)
    a = [rand_word(rng) for _ in range(8)]
    chk["PolyFT4"].run(cpu, lambda c: call(c, 0x8004DB18, ot, p, *a), lambda r: ds.poly_ft4(r, ot, p, *a))
    chk["PolyG4"].run(cpu, lambda c: call(c, 0x8004DB98, ot, p, *a), lambda r: ds.poly_g4(r, ot, p, *a))
    chk["PolyF4"].run(cpu, lambda c: call(c, 0x8004DABC, ot, p, *a[:5]), lambda r: ds.poly_f4(r, ot, p, *a[:5]))
    chk["Tile"].run(cpu, lambda c: call(c, 0x8004DCF8, ot, p, *a[:3]), lambda r: ds.tile(r, ot, p, *a[:3]))
    chk["Tile2"].run(cpu, lambda c: call(c, 0x8004DD44, ot, p, *a[:3]), lambda r: ds.tile(r, ot, p, *a[:3]))
    chk["Sprt"].run(cpu, lambda c: call(c, 0x8004DCA4, ot, p, *a[:4]), lambda r: ds.sprt(r, ot, p, *a[:4]))
    tp = rng.getrandbits(32)
    chk["DrMode"].run(cpu, lambda c: call(c, 0x8004DD90, ot, p, tp), lambda r: ds.dr_mode(r, ot, p, tp))
    lv = rng.choice([0, 0xFF, 0x100, 0x101, 0x1FF, 0x200, rng.randrange(-100, 0x300)])
    chk["Fade"].run(cpu, lambda c: call(c, 0x8004E2E8, ot, p, lv & 0xFFFFFFFF),
                    lambda r: ds.fade(r, ot, p, lv) if lv != 0x100 else p)
    col, k = rng.getrandbits(32), rng.choice([rng.randrange(0x200), rng.getrandbits(16)])
    chk["ScaleColour"].run(cpu, lambda c: call(c, 0x8004E254, col, k), lambda r: ds.scale_colour(col, k))
    v = rng.getrandbits(32)
    chk["TriangleWave"].run(cpu, lambda c: call(c, 0x8004E2C8, v), lambda r: ds.triangle_wave(v))


PIECES = ["%c", "%f", "%H", "%V", "%h", "%v", "%d", "%D", "%x", "%b", "%C", "%s", "%p",
          "%2d", "%05d", "%8D", "%3x", "%02x", "%4b", "%%", "\n", " ", "A", "Z", "0", "9", "-", ".", "!", "WIN", "%c%f%H%V"]


def random_text(rng):
    """A random format string and the arguments its codes consume (parsed like the engine)."""
    fmt = "".join(rng.choice(PIECES) for _ in range(rng.randrange(1, 10))).encode("latin-1")
    args, escape = [], 0
    for ch in fmt.decode("latin-1"):
        if ch in " \n":
            continue
        if ch == "%":
            escape = 0 if escape else 1
            continue
        if not escape:
            continue
        escape = 1 if ch in "012345678" else 0
        if ch == "c":
            args.append(rng.randrange(40))
        elif ch == "f":
            args.append(rng.randrange(4))
        elif ch in "HV":
            args.append(rng.randrange(-50, 400) & 0xFFFFFFFF)
        elif ch in "hv":
            args.append(rng.randrange(40))
        elif ch == "p":
            args.append(rng.randrange(16))
        elif ch == "s":
            args.append(STRINGS + 0x100)
        elif ch == "C":
            args.append(rng.choice([0x20, rng.randrange(0x21, 0x7F)]))
        elif ch in "dDxb":
            args.append(rng.choice([0, 7, 10, 99, 100, 12345, 99_999_999, 100_000_000,
                                    rng.getrandbits(32), rng.randrange(-5000, 5000) & 0xFFFFFFFF]))
    return fmt, args


def case_text(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    fmt, args = random_text(rng)
    cpu.write(STRINGS, fmt + b"\0")
    cpu.write(STRINGS + 0x100, bytes(rng.choice(b"ABC 12-.") for _ in range(rng.randrange(8))) + b"\0")
    w32(cpu, ds.PACKET_PTR, PACKETS + 4 * rng.randrange(16))
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(-20, 400))
    w32(cpu, ds.TEXT_STATE + 8, rng.getrandbits(32))
    w32(cpu, ds.TEXT_OFF, rng.choice([0, 0, 0, 1]))
    args = args + [0] * 2
    stack = args[3:]

    def game(c):
        from psxcpu import STACK_TOP as top
        sp = top - 0x100
        for k, v in enumerate(stack[:56]):
            w32(c, sp + 0x10 + 4 * k, v)
        return c.call(0x8004D15C, STRINGS, *(args[:3] + [0] * (3 - len(args[:3])))) & 0

    chk["PrintText"].run(cpu, game, lambda r: ds.print_text(r, STRINGS, args) or 0, show=fmt)


def case_big(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    ot = OT + 4 * rng.randrange(64)
    p = PACKETS + 4 * rng.randrange(16)
    w32(cpu, ds.FRAME_COUNT, rng.getrandbits(32))
    x, y = rng.randrange(-50, 400) & 0xFFFFFFFF, rng.randrange(-50, 500) & 0xFFFFFFFF
    key, flags = rng.choice([rng.randrange(0x5C), 0x59, 0x50, 0x58]), rng.getrandbits(8)
    chk["Portrait"].run(cpu, lambda c: call(c, 0x8004BBC0, ot, p, x, y, key, flags),
                        lambda r: ds.portrait(r, ot, p, x, y, key, flags))
    kind, col = rng.randrange(2), rng.getrandbits(24)
    chk["Backdrop"].run(cpu, lambda c: call(c, 0x800551FC, ot, p, kind, col), lambda r: ds.backdrop(r, ot, p, kind, col))
    sx, sy = rng.randrange(0, 400), rng.randrange(0, 500)
    w, h = rng.choice([rng.randrange(1, 400), 0x80, 0x100, 0x70]), rng.choice([rng.randrange(1, 300), 0x100, 0xE0])
    vx, vy = rng.randrange(0, 1024), rng.randrange(0, 512)
    clut, mode = rng.getrandbits(16), rng.choice([0, 0x80, 0x100, rng.getrandbits(16) & 0x7F | rng.choice([0, 0x80, 0x100])])
    args = (sx, sy, w, h, vx, vy, clut, mode)
    chk["Image"].run(cpu, lambda c: call(c, 0x8004DE84, ot, p, *args), lambda r: ds.image(r, ot, p, *args),
                     show=str(args))


def ovl_cpu(name):
    cpu = load_release(overlay=name)
    for a in STUB_ZERO:
        cpu.write(a, struct.pack("<2I", 0x03E00008, 0x00001021))
    return cpu


def gsnap(cpu) -> tuple[bytes, bytes]:
    return cpu.read(RAM_START, RAM_SIZE), cpu.read(ds.SCRATCH, 0x1000)


def run_gpu(chk, name, cpu, game, port, show="") -> None:
    ram_bytes, scratch = gsnap(cpu)
    ram = ds.GpuRam(ram_bytes, scratch)
    gv = game(cpu)
    pv = port(ram)
    g, gs = gsnap(cpu)
    d = diff(g, bytes(ram.data[:RAM_SIZE]))
    c = chk[name]
    c.cases += 1
    if d or (pv is not None and gv is not None and (gv & 0xFFFFFFFF) != (pv & 0xFFFFFFFF)):
        c.bad += 1
        if c.bad <= 5:
            log.info("  %s mismatch: game %s port %s bytes %s %s", name, gv, pv, [hex(a) for a in d], show)


def case_result_parts(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    ot = OT + 4 * rng.randrange(8)
    p = PACKETS
    x, y = rng.randrange(-20, 380) & 0xFFFFFFFF, rng.randrange(-20, 480) & 0xFFFFFFFF
    key = rng.choice([rng.randrange(0x5C), 0x59, 0x50, 0x51, 0x58])
    flags = rng.getrandbits(8)
    run_gpu(chk, "SmallFace", cpu, lambda c: call(c, 0x800F131C, ot, p, x, y, key, flags),
            lambda r: ds.small_face(r, ot, p, x, y, key, flags))
    ctx = ds.MODE
    for a, v in ((0x1C, rng.choice([1, 2])), (0x1E, rng.randrange(2)), (0x1F, rng.randrange(2)),
                 (0x65, rng.randrange(1, 6)), (0x72, rng.randrange(1, 6))):
        w8(cpu, ctx + a, v)
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    run_gpu(chk, "TeamLabels", cpu, lambda c: call(c, 0x800EE100, ctx) and None, lambda r: ds.team_labels(r, ctx))


def random_team(cpu, rng) -> None:
    ctx = ds.MODE
    w8(cpu, ctx + 0x1C, rng.choice([1, 2]))
    w8(cpu, ctx + 0x1E, rng.randrange(2))
    w8(cpu, ctx + 0x1F, rng.randrange(2))
    n1, n2 = rng.randrange(1, 6), rng.randrange(1, 6)
    w8(cpu, ctx + 0x65, n1)
    w8(cpu, ctx + 0x72, n2)
    w8(cpu, ctx + 0x58, rng.randrange(1, n1 + n2))
    for i in range(10):
        w16(cpu, ctx + 0x38 + 2 * i, rng.choice([1, 2, 3]))
    for i in range(13):
        w8(cpu, ctx + 0x59 + i, rng.choice([rng.randrange(22), 0x58, 0x59, 0x5A]))
        w8(cpu, ctx + 0x66 + i, rng.choice([rng.randrange(22), 0x58, 0x59]))
    for k in range(10):
        w32(cpu, ds.T_MEMBER1 + 4 * k, rng.randrange(6))
        w32(cpu, ds.T_MEMBER2 + 4 * k, rng.randrange(6))
    for a in (ds.T_LEFT1, ds.T_LEFT2):
        w32(cpu, a, rng.randrange(6))
    w32(cpu, ds.T_MSG, rng.randrange(2))
    w32(cpu, ds.T_SLIDE, rng.choice([0, 0, 1, 15, 30]))
    w32(cpu, ds.FRAME_COUNT2, rng.getrandbits(32))


def case_result_draws(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    random_team(cpu, rng)
    ctx = ds.MODE
    run_gpu(chk, "TeamMessage", cpu, lambda c: call(c, 0x800EE3C0, ctx) and None, lambda r: ds.team_message(r, ctx))
    lost, x, y, sec = rng.randrange(-1, 10), rng.randrange(0, 60), rng.randrange(60, 300), rng.randrange(2)
    names = ctx + rng.choice([0x59, 0x66])
    run_gpu(chk, "TeamMembers", cpu, lambda c: call(c, 0x800EE694, names, lost, x, y, sec) and None,
            lambda r: ds.team_members(r, names, lost & 0xFFFFFFFF, x, y, sec))
    fights = rng.randrange(0, 11)
    run_gpu(chk, "TeamGrid", cpu, lambda c: call(c, 0x800EE870, ctx, fights, ctx + 0x59) and None,
            lambda r: ds.team_grid(r, ctx, fights, ctx + 0x59))
    fight, anim, col = rng.randrange(0, 10), rng.choice([0, 1, 5, 8, 9]), rng.getrandbits(24)
    run_gpu(chk, "TeamLines", cpu, lambda c: call(c, 0x800EF0D8, ctx, fight, anim, col) and None,
            lambda r: ds.team_lines(r, ctx, fight, anim, col))
    stage, frames = rng.randrange(10), rng.choice([rng.randrange(0, 400000), rng.getrandbits(32)])
    key, flags = rng.choice([rng.randrange(0x5C), 0x59, 0x50]), rng.getrandbits(8)
    x, y = rng.randrange(0, 200), rng.randrange(0, 300)
    run_gpu(chk, "StageRow", cpu, lambda c: call(c, 0x800EFA9C, stage, frames, key, flags, x, y) and None,
            lambda r: ds.stage_row(r, stage, frames, key, flags, x, y))
    for a, v in ((ds.A_SHOW, rng.randrange(2)), (ds.A_WAIT, rng.choice([0, 1])), (ds.A_RECORD, rng.randrange(2)),
                 (ds.A_TOTAL, rng.choice([rng.randrange(400000), rng.getrandbits(32)])), (ds.A_KEY, rng.randrange(0x5C))):
        w32(cpu, a, v)
    run_gpu(chk, "YourTime", cpu, lambda c: call(c, 0x800EFD14) and None, lambda r: ds.your_time(r))
    wins = rng.choice([0, 1, 2, 9, 10, 99, 100, 999, 1000, 123456789, rng.randrange(-5, 5000)])
    run_gpu(chk, "SurvivalWins", cpu, lambda c: call(c, 0x800F04C4, wins, x, y) and None,
            lambda r: ds.survival_wins(r, wins & 0xFFFFFFFF, x, y))
    rank = rng.choice([0, 1, 2, 3, 4, 5, 10, 11, 21, 99, 100, 101])
    run_gpu(chk, "SurvivalRank", cpu, lambda c: call(c, 0x800F068C, rank, 99, y) and None,
            lambda r: ds.survival_rank(r, rank, 99, y))
    w32(cpu, ds.S_SHOW, rng.randrange(3))
    run_gpu(chk, "SurvivorCell", cpu, lambda c: call(c, 0x800F0858, wins, key, flags, x, y) and None,
            lambda r: ds.survivor_cell(r, wins & 0xFFFFFFFF, key, flags, x, y))
    ot = OT + 4 * rng.randrange(8)
    run_gpu(chk, "ResultPicture", cpu, lambda c: call(c, 0x800F1150, ot, PACKETS),
            lambda r: ds.result_picture(r, ot, PACKETS))
    w32(cpu, ds.BANNER_X, rng.choice([rng.randrange(0x400), rng.getrandbits(32)]))
    w32(cpu, ds.BANNER_Y, rng.choice([rng.randrange(0x800), rng.getrandbits(32)]))
    w32(cpu, ds.SCREEN_X, rng.randrange(-20, 20) & 0xFFFF | rng.randrange(0, 400) << 16)
    col = rng.getrandbits(24)
    run_gpu(chk, "ResultBanner", cpu, lambda c: call(c, 0x800F18FC, col) and None, lambda r: ds.result_banner(r, col))
    for i in range(4):
        w16(cpu, ds.F_TEX + 2 * i, rng.getrandbits(16))
    w32(cpu, ds.F_COLOUR, rng.getrandbits(24))
    w8(cpu, ds.F_FLIP, rng.randrange(2))
    x, y = rng.randrange(0, 200), rng.randrange(0, 200)
    run_gpu(chk, "ForcePortrait", cpu, lambda c: call(c, 0x800F1C00, x, y) and None, lambda r: ds.force_portrait(r, x, y))


FRAME_ZERO = {"ending": (0x801147DC,)}         # the staff roll's VRAM uploads; its drawing runs


def frame_cpu(name):
    """An overlay CPU for whole screens: sound, music and VRAM uploads stubbed, drawing real."""
    import verify_screens_sim as vs
    cpu = load_release(overlay=name)
    zero = tuple(a for a in vs.RETURN_ZERO if a != 0x8004D15C) + FRAME_ZERO.get(name, vs.EXTRA_ZERO.get(name, ()))
    vs.stub_all(cpu, extra_zero=(), extra_status=vs.EXTRA_STATUS.get(name, ()))
    for a in vs.RETURN_PACKET:              # undo the packet stubs: drawing runs for real
        cpu.write(a, load_release().read(a, 8))
    for a in vs.RETURN_ZERO:
        cpu.write(a, load_release().read(a, 8))
    for a in zero:
        cpu.write(a, struct.pack("<2I", 0x03E00008, 0x00001021))
    if name == "result":                    # force.ovl FUN_800B6404: lw v0, 0x800982F4
        cpu.write(0x800B6404, struct.pack("<4I", 0x3C02800A, 0x03E00008, 0x8C4282F4, 0))
    return cpu


def case_result_frames(cpu, rng, chk) -> None:
    import screens_sim as ss
    import verify_screens_sim as vs
    for case, name, addr, logic, draw in (
            (vs.case_team, "TeamScreen", 0x800EF4AC, ss.team_result, ds.team_screen_draw),
            (vs.case_time_attack, "TimeAttackScreen", 0x800EFF4C, ss.time_attack_result, ds.time_attack_screen_draw),
            (vs.case_survival, "SurvivalScreen", 0x800F0A78, ss.survival_result, ds.survival_screen_draw),
            (vs.case_force, "ForceScreen", 0x800F1F08, ss.force_result, ds.force_screen_draw)):
        captured = {}

        class Grab:
            def __getitem__(self, key):
                return self

            def run(self, cpu_, game, port, show=None):
                captured["ok"] = True
        case(cpu, rng, Grab())              # randomise the screen state exactly as the logic verifier does
        prepare(cpu, rng)
        w32(cpu, ds.TEXT_OFF, 0)
        w32(cpu, ds.PACKET_PTR, PACKETS)
        w32(cpu, ds.DISPLAY_BUFFER, rng.randrange(2))
        for i in range(4):
            w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
        if name == "TeamScreen":
            random_team(cpu, rng)
            for k in range(10):
                w16(cpu, ds.MODE + 0x38 + 2 * k, rng.choice([1, 2, 3]))
        if name == "SurvivalScreen":
            w32(cpu, ds.S_ROW, rng.randrange(0, 22))
        run_gpu(chk, name, cpu, lambda c: c.call(addr) and None, lambda r: logic(r, draw), show=f"sub {cpu.u32(0x800AE6EC) & 0xFFFF}")


def random_ranking(cpu, rng) -> None:
    w16(cpu, ds.VRAM_SIZE, rng.choice([1024, 1024, rng.randrange(1, 1100)]))
    w16(cpu, ds.VRAM_SIZE + 2, rng.choice([512, 512, rng.randrange(1, 600)]))
    for c in range(22):
        w32(cpu, ds.R_RECORDS + 8 * c, rng.choice([rng.randrange(400000), rng.getrandbits(32)]))
        cpu.write(ds.R_RECORDS + 8 * c + 4, bytes(rng.choice(b"ABZ .") for _ in range(3)) + b"\0")
    for i in range(10):
        w16(cpu, ds.R_SURVIVORS + 8 * i, rng.randrange(22))
        w16(cpu, ds.R_SURVIVORS + 8 * i + 2, rng.choice([0, 1, 2, 999, 1000, rng.randrange(65536)]))
        cpu.write(ds.R_SURVIVORS + 8 * i + 4, bytes(rng.choice(b"ABZ .") for _ in range(3)) + b"\0")


def case_ranking_draws(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    random_ranking(cpu, rng)
    rank, char = rng.choice([0, 1, 2, 3, 4, 9, 10, 99, 100, 150]), rng.randrange(22)
    x, y = rng.randrange(0, 40), rng.choice([rng.randrange(0, 0x230), rng.randrange(-100, 700) & 0xFFFFFFFF])
    style = rng.randrange(2)
    rec = ds.R_RECORDS + 8 * char
    run_gpu(chk, "TimeRow", cpu, lambda c: call(c, 0x800C133C, rank, char, rec, x, y, style) and None,
            lambda r: ds.time_row(r, rank, char, rec, x, y, style))
    entry = ds.R_SURVIVORS + 8 * rng.randrange(10)
    run_gpu(chk, "SurvivorRow", cpu, lambda c: call(c, 0x800C16C0, rank, entry, x, y, style) and None,
            lambda r: ds.survivor_row(r, rank, entry, x, y, style))
    share, top, anim = rng.randrange(0, 1001), rng.choice([0, rng.randrange(1, 1001)]), rng.choice([0, 1, 32, 64])
    run_gpu(chk, "UsageRow", cpu, lambda c: call(c, 0x800C19C4, rank, char, share, top, anim, x, y, style) and None,
            lambda r: ds.usage_row(r, rank, char, share, top, anim, x, y, style))
    bar = rng.choice([0, 1, 7, 8, 500, 1000, 1001, 5000])
    run_gpu(chk, "UsageBar", cpu, lambda c: call(c, 0x800C1154, char, bar, x + 0x111, y) and None,
            lambda r: ds.usage_bar(r, char, bar, x + 0x111, y))
    rect = STRINGS + 0x200
    for i in range(4):
        w16(cpu, rect + 2 * i, rng.randrange(-50, 1200))
    ot = OT + 4 * rng.randrange(8)
    run_gpu(chk, "DrawArea", cpu, lambda c: call(c, 0x8004DE10, ot, PACKETS, rect), lambda r: ds.draw_area(r, ot, PACKETS, rect))
    a = [rand_word(rng) for _ in range(11)]
    run_gpu(chk, "PolyGT4", cpu, lambda c: call(c, 0x8004DC0C, ot, PACKETS, *a), lambda r: ds.poly_gt4(r, ot, PACKETS, *a))


def random_ranking_table(cpu, rng) -> None:
    t = ds.R_TABLE
    n = rng.randrange(0, 23)
    w16(cpu, t + 0xC, n)
    for i in range(22):
        w16(cpu, t + 0xE + 2 * i, rng.randrange(22) if rng.random() < 0.9 else rng.randrange(10))
        w16(cpu, t + 0x58 + 2 * i, rng.randrange(0, 1001))
    w16(cpu, t + 2, rng.randrange(-1600, 200))
    w16(cpu, t + 6, rng.choice([0, 1, 59, 60, 61, 3000]))
    w16(cpu, t + 0xA, rng.randrange(0, 65))
    w32(cpu, t + 0x54, rng.randrange(-2, 23))
    w16(cpu, t + 0x84, rng.choice([0, rng.randrange(1, 1001)]))
    w16(cpu, t + 0x86, rng.randrange(6))
    w16(cpu, t + 0x88, rng.choice([0xFFFF, rng.randrange(n + 1)]))
    w16(cpu, ds.R_NAME + 4, rng.randrange(5))
    w32(cpu, ds.FRAME_COUNT2, rng.getrandbits(32))
    for i in range(4):
        w16(cpu, ds.SCREEN_RECT + 2 * i, rng.choice([0, 0x170, 0x1E0, rng.randrange(-20, 600)]))


def case_ranking_pages(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    random_ranking(cpu, rng)
    random_ranking_table(cpu, rng)
    for survivor_ids in range(1):
        pass
    run_gpu(chk, "RankingHeader", cpu, lambda c: call(c, 0x800C2108) and None, lambda r: ds.ranking_header(r))
    page = rng.randrange(4)
    if page == 1:                           # survivor rows index ten entries
        for i in range(22):
            w16(cpu, ds.R_TABLE + 0xE + 2 * i, rng.randrange(10))
    run_gpu(chk, "RankingPage", cpu, lambda c: call(c, 0x800C23D8, page) and None, lambda r: ds.ranking_page(r, page))
    run_gpu(chk, "RankingEntryPage", cpu, lambda c: call(c, 0x800C2898, page) and None,
            lambda r: ds.ranking_entry_page(r, page))


def case_ranking_frames(cpu, rng, chk) -> None:
    import screens_sim as ss
    import verify_screens_sim as vs

    class Grab:
        def __getitem__(self, key):
            return self

        def run(self, *a, **k):
            pass
    vs.case_ranking_frame(cpu, rng, Grab())
    prepare(cpu, rng)
    w32(cpu, ds.TEXT_OFF, 0)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.DISPLAY_BUFFER, rng.randrange(2))
    random_ranking(cpu, rng)
    t = ds.R_TABLE
    w16(cpu, t + 2, rng.randrange(-1600, 200))
    w16(cpu, t + 0x84, rng.choice([0, rng.randrange(1, 1001)]))
    w16(cpu, t + 0x86, rng.randrange(6))
    page = cpu.read(0x800984DC, 1)[0]
    if page == 1:
        for i in range(22):
            w16(cpu, t + 0xE + 2 * i, rng.randrange(10))
    run_gpu(chk, "RankingScreen", cpu, lambda c: c.call(0x800C2A24) and None, lambda r: ss.ranking_frame(r, ds.RANKING_DRAW),
            show=f"sub {cpu.u32(0x800AE6EC) & 0xFFFF} mode {cpu.u32(t) & 0xFFFF} page {page}")


def case_roll_frames(cpu, rng, chk) -> None:
    import screens_sim as ss
    import verify_screens_sim as vs

    class Grab:
        def __getitem__(self, key):
            return self

        def run(self, *a, **k):
            pass
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    base = rng.choice([0x801E0000, 0x801D0000])
    w32(cpu, ds.R_PACKETS_G, base)
    w32(cpu, ds.R_PACKETS_T, base + 0x4000)
    s3 = rng.choice([0, 1, 2, 3, -1])
    from unicorn.mips_const import UC_MIPS_REG_S3
    state = {}

    def game(c):
        c.uc.reg_write(UC_MIPS_REG_S3, s3 & 0xFFFFFFFF)
        return c.call(0x80112798, state["init"]) & 0xFFFFFFFF
    vs.case_staff_roll.__globals__["roll_call"] = vs.roll_call
    captured = {}

    class Cap:
        def __getitem__(self, key):
            return self

        def run(self, cpu_, g, p, show=None):
            pass
    vs.case_staff_roll(cpu, rng, Cap())      # random roll state as in the logic verifier
    state["init"] = 0
    run_gpu(chk, "StaffRollScreen", cpu, game, lambda r: ss.staff_roll(r, 0, s3, ds.ROLL_DRAW),
            show=f"phase {cpu.u32(0x80194620)} clock {cpu.u32(0x8011E5F0)}")


def roll_whole(cpu, rng, chk) -> None:
    """The whole staff roll with drawing, frame by frame."""
    import screens_sim as ss
    from unicorn.mips_const import UC_MIPS_REG_S3
    prepare(cpu, rng)
    w8(cpu, ss.BALL_NEW, rng.choice([0, 1]))
    w32(cpu, ss.START_COSTUMES, rng.choice([0, 0x40000]))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, 0)
    w32(cpu, ss.SPU_STATUS, 0)
    w32(cpu, ss.R_SKIP, 0)
    w32(cpu, ss.R_END, 0)
    w32(cpu, 0x80000000, 3)                 # the BIOS leaves word 0 = 3 (psx-spx)
    ram = ds.GpuRam(*gsnap(cpu))
    c = chk["StaffRollRun"]
    for frame in range(20000):
        for target in (cpu, ram):
            if target is cpu:
                w32(cpu, 0x800AE3C4, frame & 1)
            else:
                ram.put(0x800AE3C4, "I", frame & 1)
        init = int(frame == 0)
        cpu.uc.reg_write(UC_MIPS_REG_S3, 2)
        g = cpu.call(0x80112798, init) & 0xFFFFFFFF
        p = ss.staff_roll(ram, init, 2, ds.ROLL_DRAW)
        d = diff(cpu.read(RAM_START, RAM_SIZE), bytes(ram.data[:RAM_SIZE]))
        c.cases += 1
        if d or g != p:
            c.bad += 1
            log.info("  StaffRollRun frame %d: %s %s %s", frame, g, p, [hex(a) for a in d])
            return
        if g == 1:
            return


HUD_OT_AREA = OT + 0x200


def random_hud(cpu, rng) -> None:
    ctx = ds.MODE
    w32(cpu, ctx, rng.choice([0, 1, 2, 3, 4, 5, 6]))
    for off in (0x7, 0x12, 0x13, 0x1C, 0x1E, 0x21, 0x23, 0x62, 0x65, 0x6F, 0x72):
        w8(cpu, ctx + off, rng.choice([0, 1, 2, 3, rng.randrange(6)]))
    for off in (0x24, 0x2C, 0x34, 0x38, 0x3C, 0x40, 0x44):
        w32(cpu, ctx + off, rng.choice([0, 1, 9, 10, 99, 1000, 12345, rng.randrange(400000)]))
    for i, f in enumerate(ds.FIGHTERS):
        w16(cpu, f + 0x44, rng.randrange(0, 6))
        w16(cpu, f + 0x46, rng.choice([-1, 0, 1]))
        w16(cpu, f + 0x14, rng.choice([0x22, rng.randrange(0x5C)]))
        m = rng.choice([152, 200, 0x1680000, rng.randrange(152, 1 << 26)])
        w32(cpu, f + 0x3F8, m)
        w32(cpu, f + 0x3F4, rng.choice([m, 0, rng.randrange(0, m + 1), -5 & 0xFFFFFFFF]))
        e = ds.HEALTH + 0x10 * i
        w32(cpu, e, rng.choice([0, rng.getrandbits(32)]))
        for k in range(3):
            w16(cpu, e + 4 + 2 * k, rng.randrange(-5, 160))
        w16(cpu, e + 0xA, rng.randrange(2))
        w16(cpu, e + 0xC, rng.randrange(0, 250))
        w16(cpu, e + 0xE, rng.randrange(0, 60))
        w16(cpu, ds.NAME_W + 2 * i, rng.randrange(20, 150))
        w32(cpu, ds.NAME_UV + 4 * i, rng.getrandbits(32))
        w16(cpu, ds.NAME_TP + 2 * i, rng.getrandbits(16))
        w16(cpu, ds.NAME_COL + 2 * i, rng.randrange(4))
        w8(cpu, ds.PREV_WINS + i, rng.randrange(6))
        w16(cpu, 0x800AE6C0 + 2 * i, rng.randrange(2))
    w16(cpu, 0x800AE2C4, rng.randrange(1, 6))
    w16(cpu, ds.MAX_ROUNDS, rng.randrange(1, 10))
    w32(cpu, ds.ROUND_NO, rng.randrange(1, 10))
    w32(cpu, ds.ROUND_CLOCK, rng.choice([0, 1, 0x2D, 0x2E, 0x3C, 0x3D, 0x69, 0x6A, rng.randrange(200)]))
    w16(cpu, ds.ROUND_STATE, rng.choice([0, 0, 2, 2, 6, 9, 1, 3]))
    w32(cpu, 0x80097354, rng.choice([0, 1, 1, 2]))
    w32(cpu, ds.RESULT_FLAGS, rng.getrandbits(5))
    w32(cpu, 0x80097358, rng.choice([0, 0, 1]))
    for a in (0x800958A4, 0x800958B0, 0x800958D4):
        w32(cpu, a, rng.choice([0, 0, 1]))
    w16(cpu, 0x800AE39C, rng.choice([0, 0, 0, 1]))
    w8(cpu, 0x800AFF63, rng.choice([0, 0, 0, 1]))
    w16(cpu, 0x800AE6C8, rng.choice([1, 1, 1, 0]))
    w16(cpu, 0x800AE3D8, rng.randrange(4))
    w16(cpu, 0x800AE6DA, rng.randrange(2))
    w32(cpu, 0x800AE094, rng.randrange(0, 4000))
    w8(cpu, ds.PADS, rng.randrange(4))
    w8(cpu, 0x80098DDD, rng.randrange(4))
    w8(cpu, 0x800A8B3A, rng.randrange(2))
    w32(cpu, 0x8009811C, rng.choice([0, 0, 1, 5, 50, 500]))
    w32(cpu, 0x80098118, rng.randrange(2))
    w32(cpu, ds.FRAME_COUNT2, rng.getrandbits(32))
    w32(cpu, ds.HUD_OT, HUD_OT_AREA)
    for k in range(64):
        w32(cpu, HUD_OT_AREA + 4 * k, 0x00FFFFFF)
    # a small effect free list (two nodes, or empty)
    nodes = (0x801F9C00, 0x801F9C40)
    if rng.random() < 0.8:
        w32(cpu, ds.EFFECT_FREE, nodes[0])
        w32(cpu, nodes[0] + 4, nodes[1])
        w32(cpu, nodes[1] + 4, ds.EFFECT_FREE_END)
    else:
        w32(cpu, ds.EFFECT_FREE, ds.EFFECT_FREE_END)
    w32(cpu, ds.EFFECT_USED, 0x801F9C80)
    w32(cpu, 0x801F9C80 + 4, ds.EFFECT_USED)


def case_hud(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, rng.choice([0, 0, 0, 0, 1]))
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    random_hud(cpu, rng)
    f0, f1 = ds.FIGHTERS
    run_gpu(chk, "Hud", cpu, lambda c: c.call(0x8003D904, f0, f1) and None, lambda r: ds.hud_frame(r, f0, f1),
            show=f"mode {cpu.u32(ds.MODE)} rs {cpu.u32(ds.ROUND_STATE) & 0xFFFF}")


def case_hud_overlay(cpu, rng, chk, mode) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    random_hud(cpu, rng)
    w32(cpu, ds.MODE, mode)
    if mode == 8:
        third = 0x800AC808
        w32(cpu, ds.F_PLAYER, ds.FIGHTERS[0])
        w32(cpu, ds.F_ENEMIES, ds.FIGHTERS[1])
        w32(cpu, ds.F_ENEMIES + 4, third)
        w32(cpu, ds.F_SLOTS, ds.FIGHTERS[1])
        w32(cpu, ds.F_SLOTS + 24, third)
        for k, f in enumerate((ds.FIGHTERS[1], third)):
            w16(cpu, ds.F_SLOTS + 24 * k + 0xE, rng.randrange(5))
            w8(cpu, f + 0xC2, rng.choice([0, 0, 1]))
        m = rng.randrange(0x1000, 1 << 24)
        w32(cpu, third + 0x3F8, m)
        w32(cpu, third + 0x3F4, rng.randrange(0, m + 1))
        for i in range(3):
            e = ds.F_HEALTH + 0x10 * i
            w32(cpu, ds.F_HEALTH_LAST + 0x10 * i, rng.getrandbits(32))
            for k in range(3):
                w16(cpu, e + 2 * k, rng.randrange(-5, 160))
            w16(cpu, e + 6, rng.randrange(2))
            w16(cpu, e + 8, rng.randrange(0, 250))
            w16(cpu, e + 0xA, rng.randrange(0, 60))
            w16(cpu, ds.F_NAME_W + 2 * i, rng.randrange(20, 150))
            w32(cpu, ds.F_NAME_UV + 4 * i, rng.getrandbits(32))
            w16(cpu, ds.F_NAME_TP + 2 * i, rng.getrandbits(16))
            w16(cpu, ds.F_NAME_COL + 2 * i, rng.getrandbits(16))
        w32(cpu, ds.FORCE_SCORE, rng.randrange(100_000_000))
        w32(cpu, ds.FORCE_HISCORE, rng.randrange(100_000_000))
    f0, f1 = ds.FIGHTERS
    run_gpu(chk, "Hud", cpu, lambda c: c.call(0x8003D904, f0, f1) and None, lambda r: ds.hud_frame(r, f0, f1),
            show=f"mode {mode} rs {cpu.u32(ds.ROUND_STATE) & 0xFFFF}")


def case_vs(cpu, rng, chk) -> None:
    prepare(cpu, rng)
    w32(cpu, ds.PACKET_PTR, PACKETS)
    w32(cpu, ds.TEXT_OFF, 0)
    w32(cpu, ds.DISPLAY_BUFFER, rng.randrange(2))
    for i in range(4):
        w16(cpu, ds.TEXT_STATE + 2 * i, rng.randrange(400))
    w32(cpu, ds.VS_SLIDE, rng.choice([0, 1, 2, 8, rng.randrange(9)]))
    strings = STRINGS + 0x300
    cpu.write(strings, b"%c%f%H%VVS\0")
    kinds = [1, 3, 4, 4, 7, 8, 8, 2, 5, 5, 6, 6] + [rng.randrange(0, 10) for _ in range(6)]
    for i in range(64):
        obj = ds.VS_OBJECTS + 0x28 * i
        kind = kinds[i] if i < len(kinds) else 0
        w16(cpu, obj, kind)
        w16(cpu, obj + 4, rng.randrange(-60, 360))
        w16(cpu, obj + 6, rng.randrange(-60, 480))
        w16(cpu, obj + 8, rng.randrange(-200, 250))
        w16(cpu, obj + 10, rng.randrange(-200, 250))
        w16(cpu, obj + 0xC, rng.getrandbits(16))
        w16(cpu, obj + 0xE, rng.getrandbits(16))
        w16(cpu, obj + 0x10, rng.randrange(10) if kind in (7, 8) else rng.getrandbits(16))
        w16(cpu, obj + 0x12, rng.randrange(4) if kind in (7, 8) else rng.getrandbits(16))
        w32(cpu, obj + 0x14, rng.getrandbits(24))
        w32(cpu, obj + 0x18, strings)
        w32(cpu, obj + 0x1C, rng.choice([rng.randrange(0x5C), rng.randrange(40)]))
        w32(cpu, obj + 0x20, rng.getrandbits(8))
        w16(cpu, obj + 0x24, rng.randrange(2))
    if rng.random() < 0.5:                       # type 4/6 read a word at +4/+8 as xy/wh
        pass
    w16(cpu, 0x800AE6EC, rng.choice([2, 2, 3, 4]))
    w8(cpu, 0x800AFF64, rng.randrange(20))
    w8(cpu, 0x800AFF65, rng.randrange(8))
    run_gpu(chk, "VsScreen", cpu, lambda c: c.call(0x80052808) and None, lambda r: ds.vs_frame(r),
            show=f"sub {cpu.u32(0x800AE6EC) & 0xFFFF} slide {cpu.u32(ds.VS_SLIDE)}")


def case_vs_setup(cpu, rng, chk, modes=(0, 1, 2, 3, 4, 6, 9)) -> None:
    """FUN_80052808 sub-states 0-1 (the arcade.ovl modes' and practice.ovl's object set-up)."""
    prepare(cpu, rng)
    w32(cpu, ds.MODE, rng.choice(modes))
    for p in range(2):
        w16(cpu, 0x800AE224 + 2 * p, rng.randrange(0x16))
        w16(cpu, 0x800AE260 + 2 * p, rng.randrange(4))
        team = ds.MODE + 0x59 + 0xD * p
        for i in range(8):
            w8(cpu, team + i, rng.choice([rng.randrange(0x58), 0x58, 0x59, rng.getrandbits(8)]))
        w8(cpu, team + 9, rng.randrange(9))
        w8(cpu, team + 10, rng.randrange(9))
        w8(cpu, team + 0xC, rng.choice([1, 2, 3, 4, 5, 8, rng.randrange(12)]))
        w8(cpu, 0x800984E6 + p, rng.randrange(0x20))
    w8(cpu, 0x800AFF6C, rng.choice([1, 2]))
    for off in (0x24, 0x28, 0x44):
        w32(cpu, ds.MODE + off, rng.choice([0, 1, 5, rng.randrange(100)]))
    w8(cpu, ds.MODE + 0x58, rng.randrange(10))
    if cpu.u32(ds.MODE) == 8:
        w32(cpu, ds.MODE + 0x24, rng.randrange(5))
        w8(cpu, ds.MODE + 0x3E, rng.randrange(2))
    w16(cpu, 0x800984E4, rng.choice([0, 1, rng.getrandbits(16)]))
    w32(cpu, 0x8009584C, rng.choice([0, 1, 2]))
    for i in range(64):
        w16(cpu, ds.VS_OBJECTS + 0x28 * i, rng.choice([0, 0, rng.randrange(9)]))
    w16(cpu, 0x800AE6EC, rng.choice([0, 1, 1, 1]))
    run_gpu(chk, "VsSetup", cpu, lambda c: c.call(0x80052808) and None, lambda r: ds.vs_frame(r),
            show=f"sub {cpu.u32(0x800AE6EC) & 0xFFFF} mode {cpu.u32(ds.MODE)}")


CASES = (case_prims, case_text, case_big)
OVL_CASES = {"result": (case_result_parts, case_result_draws), "ranking": (case_ranking_draws, case_ranking_pages)}
NAMES = ["VsSetup", "PolyFT4", "PolyG4", "PolyF4", "Tile", "Tile2", "Sprt", "DrMode", "Fade", "ScaleColour",
         "TriangleWave", "PrintText", "Portrait", "Backdrop", "Image",
         "SmallFace", "TeamLabels", "TeamMessage", "TeamMembers", "TeamGrid", "TeamLines", "StageRow",
         "YourTime", "SurvivalWins", "SurvivalRank", "SurvivorCell", "ResultPicture", "ResultBanner", "ForcePortrait",
         "TeamScreen", "TimeAttackScreen", "SurvivalScreen", "ForceScreen",
         "TimeRow", "SurvivorRow", "UsageRow", "UsageBar", "DrawArea", "PolyGT4",
         "RankingHeader", "RankingPage", "RankingEntryPage", "RankingScreen",
         "StaffRollScreen", "StaffRollRun", "Hud", "VsScreen"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: Checker(n) for n in NAMES}
    cpu = load_release()
    for a in STUB_ZERO:
        cpu.write(a, struct.pack("<2I", 0x03E00008, 0x00001021))
    rng = random.Random(args.seed)
    for _ in range(args.cases):
        for case in CASES:
            case(cpu, rng, chk)
    fcpu = frame_cpu("result")
    frng = random.Random(args.seed)
    for _ in range(args.cases):
        case_result_frames(fcpu, frng, chk)
    hcpu = frame_cpu("arcade")
    scpu, pcpu, vcpu, fcpu2 = frame_cpu("arcade"), frame_cpu("practice"), frame_cpu("volley"), frame_cpu("force")
    for a in (0x80052DB8, 0x8004CACC, 0x8004CD28):   # LoadOverlaySync and the picture uploads
        for c in (scpu, pcpu, vcpu, fcpu2):
            c.write(a, struct.pack("<2I", 0x03E00008, 0x00001021))
    for _ in range(args.cases):
        case_hud(hcpu, frng, chk)
    for _ in range(args.cases):
        case_vs(hcpu, frng, chk)
        case_vs_setup(scpu, frng, chk)
        case_vs_setup(pcpu, frng, chk, modes=(5,))
        case_vs_setup(vcpu, frng, chk, modes=(7,))
        case_vs_setup(fcpu2, frng, chk, modes=(8,))
    for name, mode in (("volley", 7), ("force", 8)):
        ocpu = frame_cpu(name)
        for _ in range(args.cases):
            case_hud_overlay(ocpu, frng, chk, mode)
    ecpu = frame_cpu("ending")
    for _ in range(args.cases):
        case_roll_frames(ecpu, frng, chk)
    for _ in range(2):
        roll_whole(ecpu, frng, chk)
    rcpu = frame_cpu("ranking")
    for _ in range(args.cases):
        case_ranking_frames(rcpu, frng, chk)
    for name, cases in OVL_CASES.items():
        ocpu = ovl_cpu(name)
        orng = random.Random(args.seed)
        for _ in range(args.cases):
            for case in cases:
                case(ocpu, orng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
