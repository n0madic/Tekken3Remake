#!/usr/bin/env python3
"""Compare screens_sim.py with the original routines in the CPU harness (Japan Rev.1).

Each case randomises the state a routine reads, runs the game code and the port on the same
RAM, and compares all 2 MB of RAM (except the harness stack). Drawing, sound, music and VRAM
primitives are stubbed in the game (`STUBS`): packet builders return their packet argument,
the rest return 0, and a few status queries return a test word the case sets.

Usage: python3 tools/research/verify_screens_sim.py [--cases N] [--seed S] [--only NAME]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
import screens_sim as ss
import verify_draw_sim as vd
from fight_sim import Ram
from psxcpu import STACK_TOP, load_release, s32

log = logging.getLogger("verify_screens_sim")

RAM_START = 0x80000000
RAM_SIZE = 0x200000
STACK_LOW = STACK_TOP - 0x4000
STATUS_CELL = 0x801F8000          # value returned by the status stubs
OT_AREA = 0x801F9000              # ordering tables the drawing code links into (not compared)
OT_POINTERS = (0x800A96E0, 0x800AE21C)
DRAW_AREAS = {                    # packet buffers written by overlay drawing code (not compared)
    "ranking": ((0x800CBEF8, 0x800CBEF8 + 2 * 0x3C00),),
    "result": ((0x800FAE80, 0x800FAE80 + 2 * 0x3C00),),
}
JR_RA = 0x03E00008
MOVE_V0_A1 = 0x00A01021
MOVE_V0_ZERO = 0x00001021

RETURN_PACKET = (0x8004DB18, 0x8004DB98, 0x8004DABC, 0x8004DCF8, 0x8004DD90, 0x8004DE84,
                 0x8004E2E8, 0x8004BBC0, 0x800551FC)
RETURN_ZERO = (0x800756A4,        # SoundPlayFighter
               0x800758E8,        # SoundPlaySystem
               0x8006B0FC,        # MusicPlay
               0x8006BF80, 0x8006B9B0, 0x8006B834, 0x8004B920, 0x8004B8B4, 0x8004B88C,
               0x80040E98,        # system sound wrapper
               0x8004D15C,        # print
               0x8004CD28, 0x8004CC04,  # archive uploads
               0x8007517C)
RETURN_STATUS = ()


def stub_all(cpu, extra_zero=(), extra_packet=(), extra_status=()) -> None:
    for a in RETURN_PACKET + tuple(extra_packet):
        cpu.write(a, struct.pack("<2I", JR_RA, MOVE_V0_A1))
    for a in RETURN_ZERO + tuple(extra_zero):
        cpu.write(a, struct.pack("<2I", JR_RA, MOVE_V0_ZERO))
    for i, a in enumerate(OT_POINTERS):
        cpu.write(a, struct.pack("<I", OT_AREA + 0x800 * i))
    for a in RETURN_STATUS + tuple(extra_status):
        # lui v0, hi; jr ra; lw v0, lo(v0) -- the load sits in the delay slot
        hi, lo = (STATUS_CELL + 0x8000) >> 16 & 0xFFFF, STATUS_CELL & 0xFFFF   # lw sign-extends lo
        cpu.write(a, struct.pack("<4I", 0x3C020000 | hi, JR_RA, 0x8C420000 | lo, 0))


def snapshot(cpu) -> bytes:
    return cpu.read(RAM_START, RAM_SIZE)


SKIP: list[tuple[int, int]] = []


def diff(game: bytes, port: bytes) -> list[int]:
    skip = [(STACK_LOW, STACK_TOP), (OT_AREA, OT_AREA + 0x1000)] + SKIP
    g, p = bytearray(game), bytearray(port)
    for lo, hi in skip:
        lo, hi = lo - RAM_START, hi - RAM_START
        g[lo:hi] = p[lo:hi] = bytes(hi - lo)
    if g == p:
        return []
    return [RAM_START + i for i in range(RAM_SIZE) if g[i] != p[i]][:9]


def w8(cpu, a, v): cpu.write(a, struct.pack("<B", v & 0xFF))
def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


class Checker:
    def __init__(self, name: str):
        self.name, self.cases, self.bad, self.skipped = name, 0, 0, 0

    def run(self, cpu, game, port, show=None) -> None:
        """game(cpu) -> value, port(ram) -> value; both from the current RAM.

        A random state the game's own drawing code cannot handle (a CPU exception in the
        harness) is counted as skipped, not compared."""
        ram = Ram(snapshot(cpu))
        before = bytes(ram.data)
        try:
            gv = game(cpu)
        except Exception:                      # noqa: BLE001 - any harness fault
            self.skipped += 1
            cpu.write(RAM_START, before)
            return
        pv = port(ram)
        d = diff(snapshot(cpu), bytes(ram.data))
        self.cases += 1
        if d or (gv is not None and pv is not None and gv != pv):
            self.bad += 1
            if self.bad <= 5:
                log.info("  %s mismatch: return game %s port %s; bytes %s%s", self.name, gv, pv,
                         [hex(a) for a in d], f" ({show})" if show else "")

    def report(self) -> bool:
        extra = f" ({self.skipped} random states skipped: the game faulted)" if self.skipped else ""
        log.info("%s: %d cases, %d mismatches%s", self.name, self.cases, self.bad, extra)
        return self.bad == 0


# ---- cases: resident flow ----
def random_unlock_state(cpu, rng) -> None:
    w32(cpu, ss.UNLOCKED, rng.choice([0x3FF, rng.getrandbits(21), 0x1FFFFF, 0x3FF | rng.getrandbits(21)]))
    w32(cpu, ss.START_COSTUMES, rng.getrandbits(19) & rng.choice([0x50382, 0xFFFFFFFF]))
    w32(cpu, ss.CLEARED, rng.choice([0x3FF, rng.getrandbits(21) & rng.choice([0x3FF, 0x1FFFFF, 0])]))
    w32(cpu, ss.CLEARED2, rng.getrandbits(21) & rng.choice([0, 0x10900]))
    for a in (ss.NEW_CHAR, ss.PLAY_STEPS, ss.PLAY_STEPS_SEEN, ss.UNLOCK_CLASS, ss.BALL_NEW, ss.THEATER_NEW):
        w8(cpu, a, rng.choice([0, 1, rng.randrange(256)]))
    w8(cpu, ss.PLAY_STEPS, rng.randrange(16))
    w16(cpu, ss.FIGHTS_SINCE_UNLOCK, rng.choice([0, 49, 50, 99, 100, rng.randrange(65536)]))
    for i in range(22 * 4):
        w16(cpu, ss.STATS + 2 * i, rng.choice([0, rng.randrange(60), rng.randrange(65536)]))
    w32(cpu, ss.MODE, rng.choice([0, 0, 3, 7, rng.randrange(9)]))


RETAIL_SCHEDULE = None


def random_schedule(cpu, rng) -> None:
    """Mostly the retail schedule; sometimes random step kinds (0-6) to reach every kind."""
    global RETAIL_SCHEDULE
    if RETAIL_SCHEDULE is None:
        RETAIL_SCHEDULE = cpu.read(ss.SCHEDULE, 28)
    if rng.random() < 0.3:
        cpu.write(ss.SCHEDULE, bytes(b for _ in range(14) for b in (rng.randrange(7), rng.randrange(22))))
    else:
        cpu.write(ss.SCHEDULE, RETAIL_SCHEDULE)


def case_unlocks(cpu, rng, chk: dict) -> None:
    random_unlock_state(cpu, rng)
    random_schedule(cpu, rng)
    if rng.random() < 0.2:
        for i in range(22 * 4):
            w16(cpu, ss.STATS + 2 * i, rng.randrange(60000, 65536))
    n = rng.randrange(-2, 17)
    chk["ArcadeUnlocks"].run(cpu, lambda c: c.call(0x800564C8, n) and None, lambda r: ss.arcade_unlocks(r, n))
    random_unlock_state(cpu, rng)
    chk["SavePending"].run(cpu, lambda c: c.call(0x8004C678) and None, lambda r: ss.save_pending(r))
    random_unlock_state(cpu, rng)
    ch = rng.choice([0x11, 0x11, rng.randrange(22)])
    chk["GonCheck"].run(cpu, lambda c: c.call(0x8005696C, ch) and None, lambda r: ss.gon_check(r, ch))


def case_record_clear(cpu, rng, chk: dict) -> None:
    random_unlock_state(cpu, rng)
    ch, co = rng.choice([8, 11, 16, rng.randrange(21)]), rng.randrange(4)
    chk["RecordClear"].run(cpu, lambda c: c.call(0x800B2350, ch, co) and None, lambda r: ss.record_clear(r, ch, co))


TEAMS = 0x801F7E00              # two 13-byte test team records


def case_picks(cpu, rng, chk: dict) -> None:
    """Team battle CPU team fill (FUN_800B2724) and the survival opponent pick (FUN_800B2B98)."""
    random_unlock_state(cpu, rng)
    w32(cpu, 0x800982D0, rng.choice([0x3FF, 0x1FFFFF, 0x3FF | rng.getrandbits(21), rng.getrandbits(22)]))
    for c in range(22):
        w16(cpu, ss.TEAM_MET + 2 * c, rng.choice([0, 0, 1, 2, 5, rng.randrange(40)]))
        for k in (0, 4, 6):
            w16(cpu, ss.STATS + 8 * c + k, rng.choice([0, 3, rng.randrange(300)]))
    w32(cpu, ss.LCG2, rng.getrandbits(32))
    team, other = TEAMS, TEAMS + 0x10
    for t in (team, other):
        size = rng.randrange(1, 9)
        fixed = rng.randrange(0, size)
        members = [rng.randrange(22) * 4 + rng.randrange(4) for _ in range(10)]
        cpu.write(t, bytes(members) + bytes([fixed, rng.randrange(2), size]))
    flag = rng.choice([0, 1, 1])
    chk["TeamFill"].run(cpu, lambda c: c.call(0x800B2724, flag, team, other) and None,
                        lambda r: ss.team_fill(r, flag, team, other))
    ctx = ss.MODE
    w32(cpu, ctx + 0x24, rng.choice([0, 6, 7, 16, 17, rng.randrange(0, 60)]))
    w32(cpu, ctx + 0x44, rng.choice([0, 19, 20, rng.randrange(0, 60)]))
    w32(cpu, ctx + 0x4C, rng.randrange(0, 4))
    for i in range(4):
        w32(cpu, ctx + 0x50 + 4 * i, rng.choice([0x16, rng.randrange(22)]))
    for c in range(22):
        w16(cpu, ctx + 0x60 + 2 * c, rng.choice([0, 0, 1, 3, rng.randrange(10)]))
    w32(cpu, 0x800AE6E0, rng.getrandbits(32))
    chk["SurvivalPick"].run(cpu, lambda c: c.call(0x800B2B98, ctx) and None, lambda r: ss.survival_pick(r, ctx))


def case_flow(cpu, rng, chk: dict) -> None:
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0x800, 0x10, 0x20, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0x80C, 0x800, 4, 8, 12, rng.getrandbits(16)]))
        w16(cpu, ss.PLAYER_ACTIVE + 2 * p, rng.randrange(2))
        w16(cpu, ss.KEEP_CHAR + 2 * p, rng.randrange(2))
    w8(cpu, ss.MODE + 0xD, rng.randrange(2))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 89, 90, 91, 808, rng.randrange(-5, 900)]))
    p = rng.randrange(2)
    w16(cpu, 0x800AE6DA, rng.choice([0, 0, 1]))
    w16(cpu, ss.PLAYER_ACTIVE + 2 * p, rng.randrange(2))
    chk["ChallengerJoin"].run(cpu, lambda c: c.call(0x80051244, p) & 0xFFFFFFFF,
                              lambda r: ss.challenger_join(r, p))
    w32(cpu, ss.MODE, rng.choice([0, 3, 1, 7]))
    w32(cpu, ss.MODE + 0x24, rng.choice([9, 9, 8]))
    w8(cpu, ss.MODE + 0x1C, rng.choice([1, 1, 2]))
    w8(cpu, ss.MODE + 0x1E, rng.randrange(2))
    w8(cpu, ss.MODE + 0x1F, rng.randrange(2))
    w32(cpu, ss.MODE + 0xBC, rng.choice([0, 0, 1]))
    w16(cpu, ss.ROUNDS_TO_WIN, rng.randrange(1, 6))
    for f in ss.FIGHTER:
        w16(cpu, f + ss.ROUND_WINS, rng.randrange(-1, 6))
    chk["OgreSceneCheck"].run(cpu, lambda c: c.call(0x800514EC) & 0xFFFFFFFF, lambda r: ss.ogre_scene_check(r))
    for a in (0x80098300, 0x8009831E, ss.UNLOCK_CLASS, 0x8009831A):
        w8(cpu, a, rng.randrange(4))
    w16(cpu, ss.GAME_STATE, rng.randrange(20))
    t = rng.choice([3, 3, 4, 6, 16])
    chk["GoToTransition"].run(cpu, lambda c: c.call(0x8004FBE0, t) and None, lambda r: ss.goto_transition(r, t))


def case_ball(cpu, rng, chk: dict) -> None:
    from unicorn.mips_const import UC_MIPS_REG_S2
    random_unlock_state(cpu, rng)
    w32(cpu, ss.UNLOCKED, rng.getrandbits(21) | 1)
    ctx = ss.MODE
    for c in range(22):
        w16(cpu, ctx + 0x44 + 2 * c, rng.choice([0, rng.randrange(10), rng.randrange(65536)]))
    w8(cpu, ss.BALL_FIRST_DONE, rng.choice([0, 1]))
    w32(cpu, ss.LCG2, rng.getrandbits(32))
    w32(cpu, 0x800AE6E0, rng.getrandbits(32))
    s2 = rng.randrange(40)       # the game's 0x800AE508 lands outside the harness RAM
    cpu.uc.reg_write(UC_MIPS_REG_S2, s2)
    chk["BallOpponent"].run(cpu, lambda c: c.call(0x800B528C, ctx) and None, lambda r: ss.ball_opponent(r, ctx, s2))


# ---- cases: ranking.ovl ----
RANKING_STUBS = (0x80046458, 0x800484D8, 0x8006DAB4, 0x80036BC8)


def random_name(rng) -> bytes:
    n = rng.randrange(4)
    return bytes(rng.choice(b"ABCGNOSXU <=.") for _ in range(n)) + b"\0" * (4 - n)


def random_records(cpu, rng) -> None:
    for c in range(22):
        t = rng.choice([ss.TIME_CAP, ss.TIME_CAP + 1, rng.randrange(3000, 400000), rng.randrange(1 << 32)])
        w32(cpu, ss.RECORDS + 8 * c, t)
        cpu.write(ss.RECORDS + 8 * c + 4, random_name(rng))
    for i in range(10):
        w16(cpu, ss.SURVIVORS + 8 * i, rng.randrange(22))
        w16(cpu, ss.SURVIVORS + 8 * i + 2, rng.choice([rng.randrange(10), rng.randrange(65536)]))
        cpu.write(ss.SURVIVORS + 8 * i + 4, random_name(rng))
    w32(cpu, ss.TIME_RECORD_PTR, ss.RECORDS + 8 * rng.randrange(22) + rng.choice([0, 0, 4]))
    w32(cpu, ss.SURVIVOR_PTR, ss.SURVIVORS + 8 * rng.randrange(10) + rng.choice([0, 0, 2]))
    big = rng.random() < 0.1                 # totals above 0x3FFFFF take the scaled path of FUN_8004D008
    for i in range(22 * 4):
        w16(cpu, ss.STATS + 2 * i, 65535 if big else rng.choice([0, 0, rng.randrange(60), rng.randrange(65536)]))


def random_name_record(cpu, rng) -> None:
    cpu.write(ss.NAME, random_name(rng) if rng.random() < 0.5 else bytes(rng.choice(b"ABGON ") for _ in range(3)) + b"\0")
    w16(cpu, ss.NAME + 4, rng.choice([0, 1, 2, 2, 3]))
    w16(cpu, ss.NAME + 8, rng.choice([0, 35, 36, 37, 38, 39, rng.randrange(40)]))
    w16(cpu, ss.NAME + 0xA, rng.choice([rng.randrange(23), rng.randrange(24, 40)]))   # 23 reads past the table
    w16(cpu, ss.NAME + 0xC, rng.randrange(2))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0x10, 0x800, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_REPEAT + 2 * p, rng.choice([0, 0x2000, 0x8000, 0xA000, rng.getrandbits(16)]))


def case_ranking(cpu, rng, chk: dict) -> None:
    random_unlock_state(cpu, rng)
    random_records(cpu, rng)
    random_name_record(cpu, rng)
    if rng.random() < 0.3:        # steer the cursor onto the name "GON"
        pos = rng.randrange(3)
        w16(cpu, ss.NAME + 4, 2)
        cpu.write(ss.NAME, b"GO\0\0")
        w16(cpu, ss.NAME + 8, ord("N") - ord("A"))
        w16(cpu, ss.PAD_REPEAT + 2 * cpu.u32(ss.NAME + 0xC) % 65536 * 0, 0)
    mode = rng.choice([0, 0, 0, 1, 2, 3, -1])
    chk["NameEntry"].run(cpu, lambda c: s32(c.call(0x800C3480, ss.NAME, mode) & 0xFFFFFFFF),
                         lambda r: ss.name_entry(r, ss.NAME, mode))
    pl, ch = rng.randrange(2), rng.randrange(23)
    chk["NameInit"].run(cpu, lambda c: c.call(0x800C3438, ss.NAME, pl, ch) and None,
                        lambda r: ss.name_init(r, ss.NAME, pl, ch))
    chk["TimeTable"].run(cpu, lambda c: s32(c.call(0x800C1D1C, ss.TABLE, ss.TIME_RECORD_PTR) & 0xFFFFFFFF),
                         lambda r: ss.time_table(r, ss.TABLE, ss.TIME_RECORD_PTR))
    entry = cpu.u32(ss.SURVIVOR_PTR)
    chk["SurvivorSort"].run(cpu, lambda c: s32(c.call(0x800C1E8C, ss.SURVIVORS, entry) & 0xFFFFFFFF),
                            lambda r: ss.survivor_sort(r, ss.SURVIVORS, entry))
    chk["UsageTable"].run(cpu, lambda c: c.call(0x800C1FA8, ss.TABLE) and None, lambda r: ss.usage_table(r, ss.TABLE))
    w8(cpu, ss.BACKDROP_STAGE, rng.randrange(256))
    chk["RankingBackdrop"].run(cpu, lambda c: c.call(0x800C390C) and None, lambda r: ss.ranking_backdrop_setup(r))


def case_ranking_frame(cpu, rng, chk: dict) -> None:
    random_unlock_state(cpu, rng)
    random_records(cpu, rng)
    random_name_record(cpu, rng)
    t = ss.TABLE
    w16(cpu, ss.SUB_STATE, rng.randrange(15))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 7, 0xF8, 0x100, 59, 60, 0x77, 0x78, rng.randrange(-20, 300)]))
    w8(cpu, ss.PAGE, rng.randrange(4))
    w8(cpu, ss.NAME_PENDING, rng.choice([0, 0, 1, 2, 3, 4]))
    w8(cpu, ss.NAME_PLAYER, rng.randrange(2))
    w8(cpu, ss.NAME_CHAR, rng.randrange(22))
    w16(cpu, t, rng.randrange(6))
    w16(cpu, t + 2, rng.randrange(-800, 400))
    w16(cpu, t + 4, rng.randrange(-800, 400))
    w16(cpu, t + 6, rng.choice([0, 1, 63, 64, 149, 150, 3000, rng.randrange(65536)]))
    w16(cpu, t + 8, rng.choice([150, rng.randrange(200)]))
    w16(cpu, t + 0xC, rng.randrange(10, 23))
    w32(cpu, t + 0x50, rng.choice([-5, 0, 1, 5, rng.randrange(-5, 23)]))
    w16(cpu, t + 0x88, rng.choice([0, 1, 2, 9, 20, 0xFFFF, rng.randrange(23)]))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0, 0x10, 0x800, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0x1000, 0x2000, 0x8000, rng.getrandbits(16)]))
    w16(cpu, ss.GAME_STATE, 17)
    w8(cpu, 0x800AFF68, rng.randrange(2))
    w16(cpu, 0x800D3730, rng.randrange(65536))
    chk["RankingFrame"].run(cpu, lambda c: c.call(0x800C2A24) & 0xFFFFFFFF, lambda r: ss.ranking_frame(r),
                            show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


# ---- cases: result.ovl ----
RESULT_ZERO = (0x8006AE4C, 0x8004B8B4)
RESULT_STATUS = (0x8008DA7C, 0x800B6404)     # SpuGetKeyStatus; Tekken Force high score (force.ovl)


def random_result_state(cpu, rng) -> None:
    ctx = ss.MODE
    w32(cpu, ctx, rng.choice([2, 3, 4, 8, 6]))
    for i in range(0x40):
        w16(cpu, ctx + 0x38 + 2 * i, rng.choice([0, 1, 2, 3, rng.randrange(60), rng.randrange(65536)]))
    for k in range(10):
        w32(cpu, ctx + 0x40 + 8 * k, rng.choice([rng.randrange(20000), rng.getrandbits(32)]))
    w32(cpu, ctx + 0x38, rng.randrange(2))
    w32(cpu, ctx + 0x3C, rng.randrange(0x5C))
    w8(cpu, ctx + 0x3E, rng.randrange(2))
    w32(cpu, ctx + 0x40, rng.choice([0, 0x10, 0x11, 8, 7, rng.randrange(11)]))
    w8(cpu, ctx + 0x58, rng.randrange(1, 10))
    w8(cpu, ctx + 0x65, rng.randrange(1, 6))
    w8(cpu, ctx + 0x72, rng.randrange(1, 6))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0, 0x100, 0x800, 0x10, rng.getrandbits(16)]))
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0x900, 0x904, rng.getrandbits(16)]))
        w16(cpu, 0x800AE224 + 2 * p, rng.randrange(24))
        w16(cpu, 0x800AE260 + 2 * p, rng.randrange(5))
        w16(cpu, ss.FIGHTER[p] + 0x14, rng.choice([0x22, rng.randrange(0x5C)]))
    w8(cpu, ss.MENU_EXIT_FLAG, rng.choice([0, 0, 3]))
    w8(cpu, ss.NAME_PENDING, rng.randrange(4))
    w8(cpu, 0x8009831E, rng.randrange(5))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 2, 5, 6, 0x707, 0x708, rng.randrange(-5, 3000)]))
    w32(cpu, ss.BRIGHT, rng.choice([0, 4, 0xF8, 0x100, rng.randrange(-8, 0x110)]))
    w8(cpu, ss.SEQ_STATE, rng.choice([0, 1, 2, 3, 4, 0xFF]))
    w8(cpu, ss.SEQ_DELAY, rng.choice([0, 1, 2, 15, 0x80, rng.randrange(256)]))
    w32(cpu, ss.SPU_STATUS, rng.choice([0, 1]))
    w32(cpu, ss.BANNER_X, rng.randrange(0x400))
    w32(cpu, ss.BANNER_Y, rng.randrange(0x800))
    w16(cpu, ss.GAME_STATE, rng.randrange(12, 16))
    frame = rng.choice([0, 100, ss.RESULT_WAIT - 1, ss.RESULT_WAIT, ss.RESULT_WAIT + 1, rng.randrange(6000)])
    for a in (ss.A_FRAME, ss.S_FRAME, ss.F_FRAME):
        w32(cpu, a, frame)


def case_team(cpu, rng, chk: dict) -> None:
    random_result_state(cpu, rng)
    for k in range(10):                     # the fight results overlap the other modes' fields
        w16(cpu, ss.MODE + 0x38 + 2 * k, rng.choice([0, 1, 2, 3]))
    w16(cpu, ss.SUB_STATE, rng.randrange(12))
    n = cpu.read(ss.MODE + 0x58, 1)[0]
    w32(cpu, ss.T_FIGHT, rng.randrange(n + 1))
    w32(cpu, ss.T_LINE, rng.choice([0, 7, 8, 9]))
    w32(cpu, ss.T_SLIDE, rng.choice([0, 1, 2, 30]))
    w32(cpu, ss.T_MSG, rng.randrange(3))
    for a in (ss.T_LOST1, ss.T_LOST2, ss.T_LEFT1, ss.T_LEFT2):
        w32(cpu, a, rng.randrange(6))
    chk["TeamResult"].run(cpu, lambda c: c.call(0x800EF4AC) and None, lambda r: ss.team_result(r),
                          show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def case_time_attack(cpu, rng, chk: dict) -> None:
    random_result_state(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.randrange(11))
    w32(cpu, ss.A_ROWS, rng.randrange(12))
    w32(cpu, ss.A_ROW_ANIM, rng.choice([0, 15, 16, 17]))
    w32(cpu, ss.A_WAIT, rng.choice([0, 1, 2, 30]))
    w32(cpu, ss.A_SHOW, rng.randrange(3))
    w32(cpu, ss.A_PLAYER, rng.randrange(2))
    w32(cpu, ss.A_KEY, rng.randrange(0x5C))
    chk["TimeAttackResult"].run(cpu, lambda c: c.call(0x800EFF4C) and None, lambda r: ss.time_attack_result(r),
                                show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def case_survival(cpu, rng, chk: dict) -> None:
    random_result_state(cpu, rng)
    for c in range(22):
        w16(cpu, ss.MODE + 0x60 + 2 * c, rng.choice([0, 0, 1, 2, rng.randrange(300)]))
    w16(cpu, ss.SUB_STATE, rng.randrange(13))
    count = rng.randrange(0, 22)
    w32(cpu, ss.S_COUNT, count)
    for i in range(22):
        w8(cpu, ss.S_CHARS + i, rng.randrange(22))
    w32(cpu, ss.S_ROW, rng.choice([rng.randrange(max(count, 1)), max(count - 1, 0)]))
    w32(cpu, ss.S_ANIM, rng.randrange(5))
    w32(cpu, ss.S_WAIT, rng.choice([0, 1, 2, 30]))
    w32(cpu, ss.S_RANK, rng.randrange(3))
    w32(cpu, ss.S_PLAYER, rng.randrange(2))
    w32(cpu, ss.S_KEY, rng.randrange(0x5C))
    chk["SurvivalResult"].run(cpu, lambda c: c.call(0x800F0A78) and None, lambda r: ss.survival_result(r),
                              show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def case_force(cpu, rng, chk: dict) -> None:
    random_result_state(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.randrange(8))
    w32(cpu, ss.F_SHOWN, rng.choice([0, 0x59, 0x5A, rng.randrange(400)]))
    w32(cpu, ss.F_BOSS, rng.choice([0, 0x4F, 0x50, rng.randrange(200)]))
    w32(cpu, ss.F_PHASE, rng.randrange(4))
    w32(cpu, ss.F_FORCE, rng.randrange(100))
    chk["ForceResult"].run(cpu, lambda c: c.call(0x800F1F08) and None, lambda r: ss.force_result(r),
                           show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


# ---- cases: ending.ovl (staff roll) ----
ENDING_ZERO = (0x80113A3C, 0x8011484C, 0x80114550, 0x801147DC)
ENDING_STATUS = (0x8006BCC8,)
ROLL_COUNT = 705


def roll_call(cpu, init: int, s3: int):
    from unicorn.mips_const import UC_MIPS_REG_S3
    cpu.uc.reg_write(UC_MIPS_REG_S3, s3 & 0xFFFFFFFF)
    return cpu.call(0x80112798, init) & 0xFFFFFFFF


def case_staff_roll(cpu, rng, chk: dict) -> None:
    w8(cpu, ss.BALL_NEW, rng.choice([0, 1, 3]))
    w32(cpu, ss.START_COSTUMES, rng.choice([0, 0x40000, rng.getrandbits(19)]))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0, 0, 0x10, 0x800, rng.getrandbits(16)]))
    w32(cpu, 0x800AE3C4, rng.randrange(2))
    w32(cpu, ss.SPU_STATUS, rng.choice([0, 1]))
    w32(cpu, ss.R_SKIP, rng.choice([0, 0, 1]))
    w32(cpu, ss.R_PHASE, rng.randrange(9))
    w32(cpu, ss.R_CLOCK, rng.choice([0, 0x1E, 0x1F, 0xF0, 0x24, 0x25, 0x3C, 0xB4, 0xB5, 0xD1, 0xD2, 0xEF, 0x2364,
                                     0xA, 0xB, 0x78, 0x79, 0xB3, 0xB4, rng.randrange(0x2400)]))
    end = rng.choice([0, 0, 1, 2, 3, 4])
    if end:
        # the scroll stopped with the terminator in the bottom row (the only reachable layout)
        first = ROLL_COUNT - 26
        offset = 0x1E0 - 0x12 * 27 + rng.randrange(1, 0x13)
    else:
        first = rng.choice([rng.randrange(ROLL_COUNT), ROLL_COUNT - rng.randrange(1, 30), ROLL_COUNT - 1])
        offset = rng.choice([0x1E0, -0x13, -0x12, -0x11, rng.randrange(-0x12, 0x1E0)])
    w32(cpu, ss.R_FIRST, first)
    w32(cpu, ss.R_OFFSET, offset)
    w32(cpu, ss.R_END, end)
    w32(cpu, ss.R_HOLD, rng.choice([0, 0x26B, 0x26C, rng.randrange(0x26C)]))
    w32(cpu, ss.R_FADE, rng.choice([0, 0x4E, 0x4F, 0x50, rng.randrange(0x50)]))
    w32(cpu, ss.R_HALF, rng.randrange(3))
    w32(cpu, ss.R_ROW, rng.randrange(3))
    w32(cpu, ss.R_INDENT, rng.choice([0x20, rng.randrange(64)]))
    w8(cpu, ss.R_BRIGHT, rng.randrange(256))
    w8(cpu, ss.R_BASE_BRIGHT, rng.randrange(256))
    s3 = rng.choice([0, 1, 2, 3, -1, 7])
    init = rng.choice([0] * 9 + [1])
    chk["StaffRoll"].run(cpu, lambda c: roll_call(c, init, s3), lambda r: ss.staff_roll(r, init, s3),
                         show=f"phase {cpu.u32(ss.R_PHASE)} clock {cpu.u32(ss.R_CLOCK)} first {cpu.u32(ss.R_FIRST)}")


def case_staff_roll_run(cpu, rng, chk: dict) -> None:
    """The whole roll frame by frame from its set-up, compared after every frame."""
    w8(cpu, ss.BALL_NEW, rng.choice([0, 1]))
    w32(cpu, ss.START_COSTUMES, rng.choice([0, 0x40000]))
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, 0)
    w32(cpu, ss.SPU_STATUS, 0)
    w32(cpu, ss.R_SKIP, 0)
    w32(cpu, ss.R_END, 0)
    w32(cpu, 0x80000000, 0)                 # the kernel byte the terminator row reads
    ram = Ram(snapshot(cpu))
    s3 = 2
    for frame in range(20000):
        w32(cpu, 0x800AE3C4, frame & 1)
        ram.put(0x800AE3C4, "I", frame & 1)
        init = int(frame == 0)
        g = roll_call(cpu, init, s3)
        p = ss.staff_roll(ram, init, s3)
        d = diff(snapshot(cpu), bytes(ram.data))
        chk["StaffRollRun"].cases += 1
        if d or g != p:
            chk["StaffRollRun"].bad += 1
            log.info("  StaffRollRun frame %d: %s %s %s", frame, g, p, [hex(a) for a in d])
            return
        if g == 1:
            log.info("  staff roll finished after %d frames (phase-4 clock ends at %d)", frame,
                     cpu.u32(ss.R_CLOCK))
            return


GROUPS = {
    None: (case_unlocks, case_flow),
    "arcade": (case_record_clear, case_picks),
    "volley": (case_ball,),
    "ranking": (case_ranking, case_ranking_frame),
    "result": (case_team, case_time_attack, case_survival, case_force),
    "ending": (case_staff_roll,),
}
RUNS = {"ending": case_staff_roll_run}
EXTRA_ZERO = {"ranking": RANKING_STUBS, "result": RESULT_ZERO, "ending": ENDING_ZERO}
EXTRA_STATUS = {"result": RESULT_STATUS, "ending": ENDING_STATUS}
NAMES = ["TeamFill", "SurvivalPick", "ArcadeUnlocks", "SavePending", "GonCheck", "RecordClear", "ContinueCountdown", "FightMainEnd", "PauseUpdate", "PauseMenu", "HowTo", "ChallengerJoin",
         "OgreSceneCheck", "GoToTransition", "BallOpponent",
         "NameEntry", "NameInit", "TimeTable", "SurvivorSort", "UsageTable", "RankingBackdrop", "RankingFrame",
         "TeamResult", "TimeAttackResult", "SurvivalResult", "ForceResult",
         "StaffRoll", "StaffRollRun"]


FLOW_LOGS = {"sound": 0x801F8040, "system": 0x801F8080, "fade": 0x801F80C0, "music": 0x801F8100, "load": 0x801F8140,
             "reset": 0x801F81C0, "command": 0x801F8200, "howto": 0x801F8240}
FIGHT_FRAME_CELL = 0x801F8180
SCENE_OTS = 0x801F8280           # a stand-in for the scene's OT pointers (*0x800A911C)


class LogHooks(ss.FlowHooks):
    def sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["sound"], sound_id)

    def system_sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["system"], sound_id)

    def music_fade(self, ram, a: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["fade"], a)

    def music_play(self, ram, track: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["music"], track)

    def load_overlay(self, ram, k: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["load"], k)

    def fight_frame(self, ram) -> int:
        return ram.s32(FIGHT_FRAME_CELL)

    def sound_reset(self, ram, a: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["reset"], a)

    def command_list_screen(self, ram, player: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["command"], player)

    def how_to(self, ram, player: int) -> None:
        vd.ram_log(ram, FLOW_LOGS["howto"], player)


def continue_cpu(overlay: str = "title"):
    """The continue countdown, FightMain's end screens and the pause menu with the text engine
    running; their sound, music and overlay calls logged and FightFrame returning a fixed status."""
    import verify_menu_sim as vm
    cpu = vm.menu_cpu(overlay)
    cpu.write(0x8004B88C, load_release().read(0x8004B88C, 0x28))   # the start sound wrapper runs
    for a, key, reg in ((0x800756A4, "sound", 5), (0x80040E98, "system", 4), (0x8006BF80, "fade", 4),
                        (0x8006B0FC, "music", 4), (0x80052D1C, "load", 4), (0x8004B920, "reset", 4),
                        (0x80079298, "command", 4)) + (((0x800B4088, "howto", 4),) if overlay == "title" else ()):
        vd.log_stub(cpu, a, FLOW_LOGS[key], reg)
    vm.status_stub(cpu, 0x8002B0AC, FIGHT_FRAME_CELL)
    ss.HOOKS = LogHooks()
    return cpu


def case_continue(cpu, rng, chk: dict) -> None:
    case_continue_state(cpu, rng)
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 2, 89, 90, 91, 179, 180, 181, 719, 808, 809, -1, -2,
                                         rng.randrange(-200, 900)]))
    p = rng.randrange(2)
    vd.run_gpu(chk, "ContinueCountdown", cpu, lambda c: s32(c.call(0x800502D8, p) & 0xFFFFFFFF),
               lambda r: ss.continue_countdown(r, p))


def case_continue_state(cpu, rng) -> None:
    import verify_menu_sim as vm
    vm.common(cpu, rng)
    for cell in FLOW_LOGS.values():
        w32(cpu, cell, 0)
    for b in range(2):                          # FightMain's packet pointers
        w32(cpu, ss.FIGHT_PACKETS + 28 * b, vd.PACKETS)
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0x800, 0x10, 0x20, rng.getrandbits(16)]))
        w16(cpu, ss.PLAYER_ACTIVE + 2 * p, rng.randrange(2))
        w16(cpu, ss.KEEP_CHAR + 2 * p, rng.randrange(2))
    w8(cpu, ss.MODE + 0xD, rng.randrange(2))


def case_fight_main(cpu, rng, chk: dict) -> None:
    """FightMain sub-states 9-14 (continue, game over, new challenger)."""
    case_continue_state(cpu, rng)
    w16(cpu, ss.SUB_STATE, rng.choice([9, 10, 10, 10, 11, 12, 12, 13, 14, 14]))
    w32(cpu, ss.STATE_TIMER, rng.choice([0, 1, 7, 8, 0x17, 0x18, 0x27, 0x28, 0x49, 0x78, 0x79, 90, 808,
                                         rng.randrange(-5, 900)]))
    w32(cpu, FIGHT_FRAME_CELL, rng.choice([0, 0, 1, 2, -1]))
    w32(cpu, ss.MODE, rng.choice([0, 0, 1, 2, 3, 4, 7, 8, 6]))
    for off in (0x22, 0x23):
        w8(cpu, ss.MODE + off, rng.randrange(2))
    w8(cpu, ss.MODE + 6, rng.randrange(2))
    w32(cpu, ss.MODE + 0xC, rng.choice([0, 0, 0x100, 1, rng.getrandbits(32)]))
    w8(cpu, ss.MENU_EXIT_FLAG, rng.choice([0, 0, 0, 3]))
    for p in range(2):
        w16(cpu, ss.PAD_HELD + 2 * p, rng.choice([0, 0, 0x900, rng.getrandbits(16)]))
    vd.run_gpu(chk, "FightMainEnd", cpu, lambda c: 1 if c.call(0x80050710) & 0xFFFFFFFF == 1 else None,
               lambda r: ss.fight_main(r), show=f"sub {cpu.u32(ss.SUB_STATE) & 0xFFFF}")


def random_pause(cpu, rng) -> None:
    case_continue_state(cpu, rng)
    w32(cpu, ss.MODE, rng.choice([0, 0, 1, 2, 3, 4, 5, 5, 7, 7, 8]))
    w8(cpu, ss.MODE + 4, rng.choice([1, 1, 1, 0]))
    w32(cpu, 0x80097350, rng.choice([1, 1, 1, 2, 9]))
    for a in (ss.PAUSED, ss.PAUSED_PREV):
        w32(cpu, a, rng.choice([0, 0, 1, 2]))
    w32(cpu, 0x800958C8, rng.choice([0, 0, 0, 1]))
    w32(cpu, 0x800958E0, rng.choice([0, 0, 1]))
    w8(cpu, 0x800AE406, rng.randrange(2))
    w32(cpu, ss.PRACTICE_RESUME, rng.choice([0, 0, 0, 1]))
    w32(cpu, 0x80095884, rng.choice([1, 1, 0]))
    w8(cpu, ss.PAUSE_CHOICE, rng.choice([0, 0, 1, 2, 3, 4]))
    w8(cpu, ss.PAUSE_CURSOR, rng.choice([0, 1, 2, 3, 0xFF]))
    w8(cpu, ss.PAUSE_DELAY, rng.choice([0, 0, 0, 1, 2]))
    w32(cpu, ds.TEXT_OFF, rng.choice([0, 0, 0, 0, 1]))
    for i, v in enumerate((0, rng.choice([0, 8, 16]), 0x170, rng.choice([0xF0, 0x1E0]))):
        w16(cpu, ss.SCREEN_RECT + 2 * i, v)
    w32(cpu, 0x800A911C, SCENE_OTS)
    w32(cpu, SCENE_OTS + 4, vd.OT + 0x40)
    w32(cpu, SCENE_OTS + 0x10, vd.OT + 0x80)
    for p in range(2):
        w16(cpu, ss.PAD_PRESSED + 2 * p, rng.choice([0, 0, 0x800, 0x1000, 0x4000, 0x20, rng.getrandbits(16)]))


def case_pause(cpu, rng, chk: dict) -> None:
    random_pause(cpu, rng)
    vd.run_gpu(chk, "PauseUpdate", cpu, lambda c: c.call(0x8002B9EC) and None, lambda r: ss.pause_update(r))
    random_pause(cpu, rng)
    player = rng.choice([1, 2])
    vd.run_gpu(chk, "PauseMenu", cpu, lambda c: c.call(0x80078498, player) and None, lambda r: ss.pause_menu(r, player))


def case_how_to(cpu, rng, chk: dict) -> None:
    random_pause(cpu, rng)
    w32(cpu, SCENE_OTS + 4, vd.OT + 0x40)
    player = rng.choice([1, 2])
    vd.run_gpu(chk, "HowTo", cpu, lambda c: c.call(0x800B4088, player) and None, lambda r: ss.how_to_page(r, player))


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--only")
    args = parser.parse_args()
    chk = {n: Checker(n) for n in NAMES}
    for overlay, cases in GROUPS.items():
        if args.only and args.only not in [c.__name__ for c in cases]:
            continue
        cpu = load_release(overlay=overlay)
        stub_all(cpu, extra_zero=EXTRA_ZERO.get(overlay, ()), extra_status=EXTRA_STATUS.get(overlay, ()))
        SKIP[:] = DRAW_AREAS.get(overlay, ())
        rng = random.Random(args.seed)
        for _ in range(args.cases):
            for case in cases:
                case(cpu, rng, chk)
        if overlay in RUNS:
            for _ in range(2):
                RUNS[overlay](cpu, rng, chk)
    if not args.only or args.only == "case_continue":
        cpu, rng = continue_cpu(), random.Random(args.seed)
        bcpu = continue_cpu("volley")
        for _ in range(args.cases):
            case_continue(cpu, rng, chk)
            case_fight_main(cpu, rng, chk)
            case_pause(cpu, rng, chk)
            case_how_to(bcpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
