#!/usr/bin/env python3
"""Integer port of AiUpdate (0x80059B78), the per-frame CPU opponent routine (Japan Rev.1).

It follows the game's control flow closely; the helpers live in ai_sim.py. `verify_ai_sim.py`
compares it with the game in the CPU harness. Record offsets are documented in code/ai.md.
"""

from __future__ import annotations

from types import SimpleNamespace

import ai_sim as ai
from camera_sim import _div
from fight_math import EXE_BASE, EXE_HEADER, Exe, atan2_4096, isqrt, trig_raw, trunc12, w32, COS_TABLE, SIN_TABLE
from fight_sim import Ram

FRAME_COUNTER = 0x800AFF14
FIGHTER_DISTANCE = 0x800AFF04
BALL_CLOSER = 0x8009F6A0           # mode 7: the ball is closer than the opponent
THROW_ROWS = 0x800A0590            # scratch list of branch-row pointers (48 entries)
JOINTS = 0x8F4


# --- Tekken Ball (volley.ovl) ------------------------------------------------------------------

BALL_OBJECT = 0x800AE23C           # pointer to the ball object; its position is at +0x68 (x, y, z)
BALL_LINE = 0x800B6AF0             # s32: P1 and P2 along the line, the ball, its height, its lateral offset
FIGHTER_X, FIGHTER_Z = 0xF68, 0xF70


def _exe_view(ram: Ram) -> Exe:
    """The resident executable as fight_math's Exe (for the trig and atan tables)."""
    start = EXE_BASE & 0x1FFFFFFF
    return Exe(bytes(EXE_HEADER) + bytes(ram.data[start:start + 0x90000]))


def ball_project(ram: Ram) -> None:
    """FUN_800B4958: project both fighters and the ball onto the line through the fighters.
    The line's z intercept divides by the fighters' x difference with no zero check."""
    exe = _exe_view(ram)
    ball = ram.u32(BALL_OBJECT) + 0x68
    bx, by, bz = ram.s32(ball), ram.s32(ball + 4), ram.s32(ball + 8)
    f0, f1 = ai.FIGHTER_BASE, ai.FIGHTER_BASE + ai.FIGHTER_STRIDE
    x0, z0 = ram.s32(f0 + FIGHTER_X), ram.s32(f0 + FIGHTER_Z)
    x1, z1 = ram.s32(f1 + FIGHTER_X), ram.s32(f1 + FIGHTER_Z)
    dx, dz = w32(x1 - x0), w32(z1 - z0)
    angle = atan2_4096(dx, dz, exe)
    c = trig_raw(-angle, exe, COS_TABLE)
    s = trig_raw(-angle, exe, SIN_TABLE)
    k = w32(z0 - _div(w32(dz * x0), dx))
    line = [trunc12(w32(x0 * c - w32(z0 - k) * s)), trunc12(w32(x1 * c - w32(z1 - k) * s)),
            trunc12(w32(bx * c - w32(bz - k) * s))]
    ram.put(BALL_LINE, "i", line[0])
    ram.put(BALL_LINE + 4, "i", line[1])
    ram.put(BALL_LINE + 8, "i", line[2])
    ram.put(BALL_LINE + 0x10, "i", trunc12(w32(bx * s + w32(bz - k) * c)))
    ram.put(BALL_LINE + 0xC, "i", by)


def ball_distance(ram: Ram, fighter: int) -> int:
    """FUN_800B4B08: the fighter's distance to the ball in the projected plane."""
    d = w32(ram.s32(BALL_LINE + 4 * ram.s16(fighter + 0x12)) - ram.s32(BALL_LINE + 8))
    lat = ram.s32(BALL_LINE + 0x10)
    return isqrt(w32(d * d + lat * lat) & 0xFFFFFFFF)


def ball_behind(ram: Ram, rec: int) -> bool:
    """FUN_800B4B64: the ball is behind the CPU on the line; back-dash (script 0x80022EB2)."""
    line = [ram.s32(BALL_LINE), ram.s32(BALL_LINE + 4)]
    ball = ram.s32(BALL_LINE + 8)
    behind = ball < line[0] if ram.s16(rec) == 0 else line[1] < ball
    if behind:
        ai.start_script(ram, rec, ai.IDLE_SCRIPT)
    return behind


def ball_ahead(ram: Ram, rec: int) -> int:
    """FUN_800B4BE4: 1 when the ball is ahead of the CPU; for player 1 more than 2,000 units ahead,
    for player 2 less than 2,000 units ahead (game-bugs.md #3)."""
    ball = ram.s32(BALL_LINE + 8)
    if ram.u16(rec) == 0:
        p = ram.s32(BALL_LINE)
        return int(p < ball and p + 0x7D0 < ball)
    p = ram.s32(BALL_LINE + 4)
    return int(ball < p and p - 0x7D0 < ball)


class Done(Exception):
    """The decision produced this frame's input (LAB_80061154)."""


def _dec(ram: Ram, addr: int) -> None:
    """Count a non-negative s16 down (it stays at -1)."""
    v = ram.s16(addr)
    if v >= 0:
        ram.put(addr, "h", v - 1)


def ai_update(ram: Ram, fighter: int, stale: int | None = None, probes=None) -> tuple[int, int]:
    """AiUpdate: returns (held pad, newly pressed pad). `stale` is the uninitialised stack word that
    AiCollectCandidates compares candidates with (game-bugs.md #17); None never matches."""
    rec = ai.AI_RECORDS + ai.AI_RECORD_SIZE * ram.u8(fighter + 0x1886)
    opp = ram.u32(rec + 0x10)
    ram.put(ai.AI_OPP, "I", opp)
    ram.put(ai.AI_SELF, "I", fighter)
    if ram.u32(ai.GAME_MODE) == 7:
        ball_project(ram)
    c = SimpleNamespace(ram=ram, rec=rec, f=fighter, o=opp, stale=stale, probes=probes or {})
    try:
        _decide(c)
    except Done:
        pass
    return _finish(c)


def _probe(c, addr: int) -> None:
    """Verification hook: lets a test change the state at a game address the port also passes."""
    if addr in c.probes:
        c.probes[addr](c.ram, c.rec)


def _situation(c) -> None:
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    ram.put(rec + 0x5C, "I", 0)
    frame = ram.s16(f + 0x58)
    prev = ram.s16(rec + 0x34)
    ram.put(rec + 0x34, "h", frame)
    if frame != prev:
        ram.put(rec + 2, "h", ram.s16(rec + 2) + 1)
    sm, om = ram.u32(f + 0x54), ram.u32(o + 0x54)
    ram.put(rec + 0x224, "I", ram.u32(sm + 4))
    ram.put(rec + 0x220, "I", ram.u32(sm + 8))
    ram.put(rec + 0x228, "I", ram.u16(sm + 8))
    ram.put(rec + 0x230, "I", ram.u32(om + 4))
    ram.put(rec + 0x22C, "I", ram.u32(om + 8))
    ram.put(rec + 0x234, "I", ram.u16(om + 8))
    ram.put(rec + 0x1C, "I", ram.u32(f + 0xF8))
    sit = int(ram.s16(f + 0x30) > 0x4000)
    ram.put(rec + 0x2E, "h", ram.s16(f + 0x30))
    heading = ram.u16(f + 0x2E)
    if (heading - 0x4E38) & 0xFFFFFFFF < 0x31C8:
        sit |= 2
    if (heading + 0x8000) & 0xFFFF < 0x31C7:
        sit |= 4
    if (ram.s16(o + 0x64) == 0x412 and ram.s16(o + 0x58) <= ram.u8(om + 0x2E)
            and ram.u32(FIGHTER_DISTANCE) < 0x700):
        sit |= 8
    if ram.s16(f + 0x32) == 0:
        sit |= 0x10
    ram.put(rec + 0x201, "B", 0)
    ram.put(rec + 0x200, "B", 0)
    ram.put(rec + 0x64, "I", sit)
    if ram.s16(o + 0x16) == 0xE and ram.u8(ram.u32(om + 0x28)) == 0x18:
        ram.put(rec + 0x200, "B", 1)
    elif ram.s16(o + 0x16) == 0x13 and ram.u8(ram.u32(om + 0x28)) == 0x1A:
        ram.put(rec + 0x201, "B", 1)
        ram.put(rec + 0x22C, "I", ram.u32(rec + 0x22C) | 0x10000)


def _fixed_input(c) -> None:
    """Pending script steps, the disabled modes (+0x21E) and the alternate-frame rule; raise Done."""
    ram, rec = c.ram, c.rec
    p = ram.u32(rec + 8)
    if p:
        step = ram.u16(p)
        ram.put(rec + 8, "I", p + 2)
        if ram.s16(p + 2) == 0:
            ram.put(rec + 8, "I", 0)
        ram.put(rec + 4, "H", ai.pad_from_step(ram, step))
        raise Done
    mode = ram.s16(rec + 0x21E)
    if mode == 0:
        ram.put(rec + 4, "H", 0)
        raise Done
    if mode == 1:
        ram.put(rec + 4, "H", ram.u32(rec + 0x224) << 10 & 0x1000)
        raise Done
    slot = ram.u16(rec)
    if ((ram.u32(ai.AI_MULTI) and ram.u32(FRAME_COUNTER) & slot & 1)
            or (ram.u32(ai.GAME_MODE) == 8 and ram.s32(ai.FORCE_TARGETS + 8 + 4 * slot) > 0)):
        ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
        raise Done


def _decide(c) -> None:
    _situation(c)
    _fixed_input(c)
    _track(c)
    _probe(c, 0x8005A9DC)
    _throws(c)
    _stance(c)
    if c.ram.u32(c.f + 0x1A4):                  # a move row is queued
        raise Done
    _crouch_and_actions(c)
    if ai.call_hook(c.ram, 0, c.rec) or ai.call_hook(c.ram, 1, c.rec):
        raise Done
    _hold_guard(c)
    _new_move(c)
    _follow_through(c)
    _counter(c)
    _probe(c, 0x8005C514)
    kind = _reaction_kind(c)
    if _react(c, kind):
        raise Done
    _expire_lists(c)
    _avoid_air_attack(c)
    _probe(c, 0x8005E568)
    if _attack(c):
        raise Done
    _probe(c, 0x800605F4)
    _move(c)


def _collect(c, current_only: int) -> int:
    ram, rec = c.ram, c.rec
    ram.put(rec + 0x72, "h", 0)
    ram.put(rec + 0x58, "I", ram.u32(c.f + 0x54))
    n = ai.collect_candidates(ram, rec, current_only, c.stale)
    ram.put(rec + 0x70, "H", n & 0xFFFF)
    return _h(n)


def _stance(c) -> None:
    """Stance moves (state 0x4C02, no active window): with probability word 49 (+0x29A) execute a
    candidate whose branch row byte +8 is 0x1C or 0x1D."""
    ram, rec = c.ram, c.rec
    if ram.s16(rec + 0x224) != 0x4C02 or ram.u8(ram.u32(c.f + 0x54) + 0x2D):
        return
    ai.reset_approach(ram, rec)
    if _collect(c, 1) > 0 and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x29A):
        marked = ai.mark_candidates(ram, rec, lambda t, br: (ram.u8(br + 8) - 0x1C) & 0xFFFFFFFF < 2)
        if marked > 0:
            ai.execute_candidate(ram, rec)
            raise Done
    ram.put(rec + 4, "H", 0)
    raise Done


ACTION_TABLE = 0x800230E0          # u16 x 6: 1 step in, 2 crouch dash/jump, 4 back, 8 attack, 0x10 low, 0x20 air


def _crouch_and_actions(c) -> None:
    """Grounded CPU in a neutral state (+0x224 bits 2 or 10): crouch-cancel rows (condition 0x31) or
    a random action from a mask chosen by the opponent's attack timing."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    if ram.u8(f + 0xDB) or not ram.u32(rec + 0x224) & 0x404:
        ram.put(rec + 0x36, "h", 0)
        return
    if any(ram.u8(row + 3) == 0x31 for row in _list_rows(ram, ram.u32(ram.u32(f + 0x54) + 0xC))):
        v = (ram.s16(rec + 0x6E) - 1) & 0xFFFF
        ram.put(rec + 0x36, "h", 1)
        ram.put(rec + 0x6E, "H", v)
        if _h(v) >= 0:
            ram.put(rec + 4, "H", 0)
            raise Done
        wait = ram.u8(rec + 0x238 + (ram.u32(ai.LCG) & 3))
        ai._lcg_next(ram)
        ram.put(rec + 4, "H", 0x10)
        ram.put(rec + 0x6E, "H", wait)
        raise Done
    if _collect(c, 1) < 1:
        ram.put(rec + 4, "H", 0)
        raise Done
    ram.put(rec + 0x36, "h", 1)
    ram.put(rec + 0x40, "h", 0x28)
    ram.put(rec + 0x48, "h", -1)
    ram.put(rec + 0x3A, "h", 0)
    ram.put(rec + 0x38, "h", 0)
    ram.put(rec + 0x8A, "h", 0x10)
    if ram.u8(rec + 0x201) and ram.u16(f + 0x60) & 0x200:
        ram.put(rec + 4, "H", 0x8000)
        raise Done
    om, first, last, frame = c.om, c.op_first, c.op_last, c.op_frame
    if (((ram.u32(rec + 0x230) & 0x200000 and first == 0)
         or (ram.u32(rec + 0x234) == 0x607 and not ram.u32(rec + 0x22C) & 0x10000 and ram.s16(rec + 0x20A) < 0x1D))
            and frame < last):
        ram.put(rec + 4, "H", 0)
        raise Done
    mask = _action_mask(c)
    if mask == 0:
        ram.put(rec + 4, "H", 0)
        raise Done
    while True:
        r = ai.rand(ram)
        u = (r + ai._lcg_next(ram)) & 0x7FFF
        action = ram.u16(ACTION_TABLE + 2 * (u * 6 >> 15))
        if mask & action:
            break
    if action == 1:
        ram.put(rec + 4, "H", 0x1000)
        raise Done
    if action == 2:
        ram.put(rec + 4, "H", 0x80 if ram.u16(rec + 2) & 7 else 0x4080)
        raise Done
    if action == 4:
        ram.put(rec + 4, "H", 0x2000 if ram.s16(f + 0x16) == 0x12 else 0x8000)
        raise Done
    if action == 8:
        ai.filter_attacks(ram, rec)
    elif action == 0x10:
        ai.mark_candidates(ram, rec, lambda t, br: bool(ram.u32(t + 8) & 0x10000) or ram.u32(t + 8) & 0xFFFF == 0x10F)
    elif action == 0x20:
        ai.mark_candidates(ram, rec, lambda t, br: ram.s16(br) == -0x3FFF or (
            ram.u32(t + 4) & 0xA0000 == 0x80000 and not ram.u32(t + 4) & 0x600000))
    if ram.s16(rec + 0x72) > 0:
        ai.execute_candidate(ram, rec)
    raise Done


def _action_mask(c) -> int:
    ram, rec = c.ram, c.rec
    band, closing = ram.s32(rec + 0x14), ram.s32(rec + 0x18)
    first, last, frame = c.op_first, c.op_last, c.op_frame
    if first == 0:
        if band > 2:
            ram.put(rec + 0x36, "h", 0)
            return 7 if closing >= 4 else 0x3F
        if not ram.u16(rec + 2) & 1:
            return 0
        ram.put(rec + 0x36, "h", 0)
        if ram.s16(rec + 0x68) < 0 and ai._lcg_next(ram) & 0x3F == 0:
            return 0x38
        return 7
    if ram.s16(rec + 0x20A) < 0xC and frame <= last:
        if ram.u32(rec + 0x234) == 0x10F or ram.u32(rec + 0x22C) & 0x10000:
            if not ram.u16(rec + 2) & 1:
                return 0
            ram.put(rec + 0x36, "h", 0)
            x = ram.u32(ai.LCG)
            x1 = (5 * x + 3) & 0xFFFFFFFF
            if x & 2:
                ram.put(ai.LCG, "I", x1)
                return 0x38
            if (ram.u8(c.om + 0x19) == 0 and ram.s16(rec + 0x2E) <= 0x4000
                    and not ram.u32(rec + 0x230) & 0x200000):
                ram.put(ai.LCG, "I", x1)
                return 4
            ram.put(ai.LCG, "I", (5 * x1 + 3) & 0xFFFFFFFF)
            return 4 if x1 & 0x3F == 0 else 2
        if closing < 3 and (closing < 2 or ram.s32(rec + 0x24) < 0xB):
            mask = 0x3F if ai._lcg_next(ram) & 0xF else 0
        else:
            mask = 1
        ram.put(rec + 0x36, "h", 0)
        return mask
    if band < 2:
        ram.put(rec + 0x36, "h", 0)
        return 0x38 if ram.u32(rec + 0x230) & 2 else 0x28
    return 0


def _self_target(c, row: int) -> int:
    """The move a branch row leads to, through the CPU's own AI slot index."""
    ram = c.ram
    index = ram.u32(ai.AI_INDEX + 4 * ram.u8(c.f + 0x1886))
    return ram.u32(index + 4 * ram.u16(row + 6))


def _open_for(c, row: int) -> bool:
    return ai.restriction_ok(ai.Fighter(c.ram, c.f), ai.Fighter(c.ram, c.o), c.ram.u8(row + 2))


def _gather(c, rows: int, limit: int, accept) -> list[int]:
    """Rows of a branch list (common blocks expanded) that pass the restriction and `accept`, up to
    `limit` (the walk stops at the limit)."""
    ram = c.ram
    found = []
    while ram.u16(rows) != ai.END:
        if ram.u16(rows) == ai.COMMON:
            base, n = ai.COMMON_ROWS + 12 * ram.u16(rows + 6), ram.u8(rows + 11)
        else:
            base, n = rows, 1
        for k in range(n):
            row = base + 12 * k
            if _open_for(c, row) and accept(row):
                found.append(row)
                if len(found) >= limit:
                    return found
        rows += 12
    return found


def _store_rows(ram: Ram, addr: int, rows: list[int]) -> None:
    for k, row in enumerate(rows):
        ram.put(addr + 4 * k, "I", row)


def _new_move(c) -> None:
    """When the CPU's move changed (+0x28), prepare the follow-up lists: string continuations
    (+0xC4, while +0xC0 > 0), planned follow-ups in reach (+0xDC, while +0xD8 > 0) or rows that open on
    frame 1 of an attack (+0x1A4); holding the direction while a list is ready. Otherwise collect
    candidates, and after 220 frames in one move execute any of them."""
    _probe(c, 0x8005B994)
    ram, rec, f = c.ram, c.rec, c.f
    ram.put(rec + 0x72, "h", 0)
    ram.put(rec + 0x70, "h", 0)
    done = False
    if ram.s16(rec + 0x28):
        ram.put(rec + 0x58, "I", ram.u32(f + 0x54))
        ram.put(rec + 0x4E, "h", ram.s16(f + 0x58))
        rows = ram.u32(ram.u32(rec + 0x58) + 0xC)
        if ram.s16(rec + 0xC0) >= 1:
            found = _gather(c, rows, 4, lambda row: bool(ram.u32(_self_target(c, row) + 0x24) >> 8 & 0x20))
            _store_rows(ram, rec + 0xC4, found)
            ram.put(rec + 0xC2, "h", len(found))
            done = True
            if found:
                ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
            else:
                ram.put(rec + 0xC2, "h", 0)
                ram.put(rec + 0xC0, "h", 0)
        elif ram.s16(rec + 0xD8) >= 1:
            found = _planned_follow_ups(c, rows)
            _store_rows(ram, rec + 0xDC, found)
            ram.put(rec + 0xDA, "h", len(found))
            done = True
            if found:
                ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
            else:
                ram.put(rec + 0xDA, "h", 0)
                ram.put(rec + 0xD8, "h", 0)
        elif ram.s16(rec + 0x52) == 0:
            if ram.u8(ram.u32(f + 0x54) + 0x2D) == 0:
                for off in (0x1A2, 0xDA, 0xC2, 0x1A0, 0xD8, 0xC0, 0x98):
                    ram.put(rec + off, "h", 0)
            else:
                found = []
                if ram.s16(rec + 0x1CC) == 0:
                    ram.put(rec + 0x1D0, "h", 0)
                    word35 = ram.s16(rec + 0x27E)

                    def frame_one(row: int) -> bool:
                        return ram.u8(row + 9) == 1 and ram.u8(row + 10) == ram.u8(row + 11)

                    def accept(row: int) -> bool:
                        if ram.u32(_self_target(c, row) + 0x24) >> 8 & 0x20 and ai._lcg_next(ram) & 0xFFF < word35:
                            return False
                        return True

                    found = _gather_ordered(c, rows, 10, frame_one, accept)
                    for k, row in enumerate(found):
                        ram.put(rec + 0x1A4 + 4 * k, "I", row)
                        last = ram.u8(row + 10)
                        if last < 0x3C and ram.s16(rec + 0x1D0) < last:
                            ram.put(rec + 0x1D0, "H", last)
                    ram.put(rec + 0x1A2, "h", len(found))
                else:
                    ram.put(rec + 0x1CC, "h", 0)
                done = True
                if not found:
                    ram.put(rec + 0x1A2, "h", 0)
                    ram.put(rec + 0x1A0, "h", 0)
                else:
                    ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
                    ram.put(rec + 0x1A0, "h", ram.s16(rec + 0x1A0) + 1)
    ram.put(rec + 0x4E, "h", ram.s16(f + 0x58))
    if not done:
        n = _h(ai.collect_candidates(ram, rec, 0, c.stale))
        ram.put(rec + 0x70, "h", n)
        if ram.s16(rec + 0x2C) > 0xDC:
            marked = 0
            for k in range(n):
                e = ai.CANDIDATES + 12 * k + 8
                if ram.s16(e) == 0:
                    ram.put(e, "h", 1)
                    marked += 1
            ram.put(rec + 0x72, "h", ram.s16(rec + 0x72) + marked)
            if marked > 0:
                ai.execute_candidate(ram, rec)
                done = True
    if done or (ram.u32(ai.GAME_MODE) == 7 and ball_behind(ram, rec)):
        raise Done


def _gather_ordered(c, rows: int, limit: int, pre, accept) -> list[int]:
    """Like _gather, but the restriction is tested after `pre` (the game's order of tests)."""
    ram = c.ram
    found = []
    while ram.u16(rows) != ai.END:
        if ram.u16(rows) == ai.COMMON:
            base, n = ai.COMMON_ROWS + 12 * ram.u16(rows + 6), ram.u8(rows + 11)
        else:
            base, n = rows, 1
        for k in range(n):
            row = base + 12 * k
            if pre(row) and _open_for(c, row) and accept(row):
                found.append(row)
                if len(found) >= limit:
                    return found
        rows += 12
    return found


def _planned_follow_ups(c, rows: int) -> list[int]:
    """The +0xDC list: rows in reach whose target is usable; AI-excluded (bit 22) targets pass only
    when +0x208 is clear, and plain ground moves with bit 22 only after a draw above word +0x24E."""
    ram, rec = c.ram, c.rec
    index = ram.u32(rec + 0xC)
    w208, w24e = ram.s16(rec + 0x208), ram.s16(rec + 0x24E)
    ai._lcg_next(ram)
    reach = ram.u32(ai.BAND_REACH + 4 * ram.u32(rec + 0x14))

    def accept(row: int) -> bool:
        t = ram.u32(index + 4 * ram.u16(row + 6))
        if not ((w208 == 0 or not ram.u32(t + 8) & ai.HINT_NEVER) and not ram.u32(t + 4) & 0x20000):
            return False
        w = ram.u32(t + 8)
        if not w & 0x200000 and not ram.u32(t + 4) & 0x80000:
            if not w & ai.HINT_NEVER:
                return False
            if ai._lcg_next(ram) & 0x7FFF <= w24e:
                return False
            w = ram.u32(t + 8)
        r = w & 0xFFFF0000
        if not w & 0x1C0000:
            r |= 0xC0000
        return bool(r & reach)

    return _gather(c, rows, 48, accept)


def _mark_all(ram: Ram, rec: int) -> int:
    return ai.mark_candidates(ram, rec, lambda t, br: True)


def _follow_through(c) -> None:
    """During a move usable in the air or as a special (+0x52), execute any open candidate when
    the opponent's attack comes later than this move's, the distance band is above 2 or the CPU
    faces away; this ends the decision either way."""
    ram, rec, f = c.ram, c.rec, c.f
    if not (ram.s16(rec + 0x52) and ram.s16(rec + 0x70) and ram.u8(rec + 0x200) == 0):
        return
    if (ram.s16(rec + 0x20A) < ram.u8(ram.u32(f + 0x54) + 0x2D) - ram.s16(f + 0x58)
            or ram.s32(rec + 0x14) > 2 or ram.s16(f + 0x32) == 2):
        if _mark_all(ram, rec) > 0 and ai.execute_candidate(ram, rec) >= 0:
            ram.put(rec + 0x68, "h", -1)
    raise Done


def _counter(c) -> None:
    """The opponent's attack is coming: attack first (word 18 at +0x25E), crouch or duck away
    (word 21 at +0x262) or side-step (word 20 at +0x25C)."""
    ram, rec, f = c.ram, c.rec, c.f
    if not (ram.s16(rec + 0x20C) and ram.s16(rec + 0x216) >= 0 and ram.s32(rec + 0x18) < 4):
        return
    if ram.u8(rec + 0x8F) or ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x25E):
        v = ram.s16(rec + 0x20A)
        if 1 < v < 0x1E:
            k = ai.filter_quick_attacks(ram, rec)
            if k > 0 and ai.execute_candidate(ram, rec) >= 0:
                raise Done
    if ram.s16(rec + 0x50) == 0:
        attack = ram.s16(rec + 0x22C)
        if ((attack != 0 and attack != 0x607) or ram.s16(rec + 0x20E) > 0) and (
                ram.u8(rec + 0x92) or ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x262)):
            ram.put(rec + 4, "H", _duck_or_back(c))
            raise Done
    if ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x25C):
        ok = False
        if (ram.u16(rec + 0x20A) - 9) & 0xFFFFFFFF < 3 and ram.s16(rec + 0x2E) < 0x4000:
            ok = not ram.u32(rec + 0x224) & 0x400000
        if ok and ram.s32(rec + 0x18) > 1:
            ai.side_step(ram, rec, -1)
            ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 10)
            raise Done


GUARD_MOVES = 0x80022F80          # per bank type, 16 bytes: s16 +0 counter move, s32 +4 / +8 parry flags


def _reach_ok(c, band_off: int) -> bool:
    """The opponent's move reach bits against the band mask of record +band_off."""
    ram, rec = c.ram, c.rec
    w = ram.u32(c.om + 8)
    r = w & 0xFFFF0000
    if not w & 0x1C0000:
        r |= 0xC0000
    return bool(r & ram.u32(ai.BAND_REACH + 4 * ram.s32(rec + band_off)))


def _can_counter(c) -> bool:
    ram, rec = c.ram, c.rec
    return (ram.s16(rec + 0x20C) != 0 and ram.s16(rec + 0x6A) == 0 and ram.s16(c.f + 0x3E) < 0x5000
            and ram.s32(rec + 0x1C) < 0xB87 and _reach_ok(c, 0x18))


def _reaction_kind(c) -> int:
    """The reaction to the opponent's attack (jump table 0x8002317C): 0 none, 1 escape attempt,
    2 guard/evade candidates (FUN_800582A0), 3 ..., 5/6/7/8 bank-specific counters, 9 low parry."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    if ram.s16(rec + 0x216) >= 0:
        return 0
    kind = 0
    if ram.s16(rec + 0x88) != 0:
        return 0
    if ram.s16(rec + 0x6C) == 0:
        kind = 2
        if ram.s16(rec + 0x50) == 0:
            return 2
    if ram.u8(rec + 0x94) == 0:
        kind = 0
        if not (ram.s16(rec + 0x20C) != 0 and ram.s32(rec + 0x18) < 4):
            return 0
    return _reaction_body(c, kind)


def _draw(c, off: int) -> bool:
    """A 12-bit draw below the record word at +off."""
    return ai._lcg_next(c.ram) & 0xFFF < c.ram.s16(c.rec + off)


def _reaction_body(c, kind: int) -> int:
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    om = c.om
    if (ram.u8(om + 0x2D) and ram.u8(om + 0x2E) < ram.s16(o + 0x58)) or ram.s16(f + 0x40) == 2:
        ram.put(rec + 0x94, "B", 2)
    if (ram.u8(rec + 0x94) == 0 and (ram.u32(rec + 0x234) in (0x607, 0x706) or ram.u32(rec + 0x230) & 0x200000)
            and _draw(c, 0x272)):
        ram.put(rec + 0x94, "B", 1)
    if ram.s16(rec + 0x8C) < 0 and ram.u8(rec + 0x94) != 2:
        kind = 3
        if ram.u8(rec + 0x94) != 0:
            return 3
    bank = ram.s16(f + 0x16)
    grounded = ram.u32(rec + 0x228) == 0 and ram.u8(f + 0xDB) == 0
    until = ram.u16(rec + 0x20A)
    if ((until - 8) & 0xFFFFFFFF < 2 and grounded and ram.s16(GUARD_MOVES + 16 * bank) != 0
            and not ram.u32(om + 0x24) >> 8 & 8 and ram.u8(o + 0xDB) == 0):
        if _can_counter(c):
            kind = 5
            if _draw(c, 0x292):
                return 5
    if bank == 9 and 0x15 < ram.s16(rec + 0x20A) < 0x1B and grounded:
        if _can_counter(c):
            kind = 6
            if _draw(c, 0x292):
                return 6
    if (until - 4) & 0xFFFFFFFF < 7 and grounded and ram.u8(o + 0xDB) == 0:
        if _can_counter(c) and _draw(c, 0x292):
            attack = ram.u32(rec + 0x234)
            if attack in (0x412, 0x217, 0x607, 0x706):
                kind = 7
                if ram.s32(GUARD_MOVES + 4 + 16 * bank):
                    return 7
            if attack == 0x10F:
                kind = 8
                if ram.s32(GUARD_MOVES + 8 + 16 * bank):
                    return 8
    if ram.u32(rec + 0x22C) & 0x400000:
        slot, obank = ram.s16(o + 0xA0), ram.s16(o + 0x16)
        if slot in FORCED_ESCAPES or (slot == 0x172 and obank in (9, 0)) or (obank == 3 and slot == 0x152):
            kind = 1
            if _draw(c, 0x272):
                return 1
        if ram.s16(rec + 0x20A) <= 0x1D and _draw(c, 0x296):
            ram.put(rec + 0x92, "B", 2)
            return 2
    attack = ram.s16(rec + 0x22C)
    if (attack != 0 and attack != 0x607) or ram.s16(rec + 0x20E) > 0:
        if ram.s16(rec + 0x6A) != 0:
            return 0
        if ram.s16(rec + 0x50) != 0:
            return 0
        if ram.u8(rec + 0x92):
            return 2
        x = ai._lcg_next(ram)
        if x & 0xFFF < ram.s16(rec + 0x254) or (ram.s16(rec + 0x20E) > 0x1E and _draw(c, 0x256)):
            ram.put(rec + 0x92, "B", 5)
            return 2
    if ram.s16(rec + 0x6C) > 8 and ai._lcg_next(ram) & 0x1F == 0:
        return 1
    if ram.s16(rec + 0x202) != 0 and ai._lcg_next(ram) & 0xF == 0:
        return 1
    if ram.u32(o + 0x54) == ram.u32(rec + 0x1DC) and ram.s16(rec + 0x88) == 0 and _draw(c, 0x25A):
        return 1
    if ram.s16(rec + 0x88) == 0 and _draw(c, 0x258):
        return _low_parry_or_escape(c)
    if ram.s16(rec + 0x20E) >= 0x1F and _draw(c, 0x25A):
        return _low_parry_or_escape(c)
    ok = False
    if (ram.u16(rec + 0x20A) - 9) & 0xFFFFFFFF < 3 and ram.s16(rec + 0x2E) < 0x4000:
        ok = not ram.u32(rec + 0x224) & 0x400000
    if not ok or ram.s32(rec + 0x18) != 2:
        return 0
    if (ram.u32(rec + 0x224) & 1 or ram.u8(f + 0xDB) or ram.s16(rec + 0x50) != 0
            or ram.u32(rec + 0x234) != 0x412):
        return 0
    return 4 if _draw(c, 0x25C) else 0


EVADE_STATES = 0x800230EC          # u8 at stride 2: random evasion states 5 3 5 4 3 4 3


def _execute_marked(c, count: int, execute: bool) -> bool:
    """LAB_8005D7A4: with `execute`, run a marked candidate (and restart the approach timers when
    one was pressed); the reaction then ends the decision."""
    ram, rec = c.ram, c.rec
    if not execute:
        return False
    if count > 0 and ai.execute_candidate(ram, rec) >= 0:
        ram.put(rec + 0x40, "h", 0x28)
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x38, "h", 0)
        ram.put(rec + 0x48, "h", -1)
    return True


def _react(c, kind: int) -> bool:
    """The reaction cases; True ends the decision."""
    ram, rec, f = c.ram, c.rec, c.f
    if kind == 0:
        return False
    if kind == 9:
        n = ai.mark_candidates(ram, rec, lambda t, br: ram.u32(t + 4) & 1 == 1 and ram.u8(t + 0x2D) == 0)
        if n > 0:
            ram.put(rec + 0x8E, "B", 1)
            ram.put(rec + 0x68, "h", -1)
        return _execute_marked(c, n, n > 0)
    if kind == 1:
        attack = ram.u32(rec + 0x234)
        if ram.s16(rec + 0x20C) == 0:
            n = ai.filter_fast_attacks(ram, rec)
        elif attack in (0x607, 0x706) or ram.u32(rec + 0x230) & 0x200001:
            n = ai.filter_quick_attacks_no_high(ram, rec)
        else:
            n = ai.filter_quick_attacks(ram, rec)
        if attack == 0x412:
            n += ai.mark_candidates(ram, rec, lambda t, br: ram.u8(t + 0x2D) != 0
                                    and ram.u32(t + 4) & 0x20001 == 1 and ai.reach_ok(ram, rec, t))
        return _execute_marked(c, n, n > 0)
    if kind == 2:
        n = ai.filter_defence(ram, rec)
        if n > 0:
            return _execute_marked(c, n, True)
        pad = 0
        if ram.s16(f + 0x32) == 0:
            pad = 0x8000 if ram.u32(rec + 0x234) == 0x217 else 0xC000
            ai.reset_approach(ram, rec)
        ram.put(rec + 4, "H", pad)
        return True
    if kind == 3:
        return _evade(c)
    if kind == 4:
        ai.side_step(ram, rec, -1)
        ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 10)
        return True
    if kind == 5:
        n = ai.mark_candidates(ram, rec, lambda t, br: ram.u16(br + 6) in (0x1EE, 0x6A3))
        return _execute_marked(c, n, n > 0)
    if kind == 6:
        n = ai.mark_candidates(ram, rec, lambda t, br: ram.u16(br + 6) == 0x22C)
        return _execute_marked(c, n, n > 0)
    script = ram.u32(GUARD_MOVES + 16 * ram.s16(f + 0x16) + (4 if kind == 7 else 8))
    ai.start_script(ram, rec, script)
    return True


def _pad_back_on_even(ram: Ram, rec: int) -> int:
    """FUN_800595E4: restart the approach timers; 0x2000 (back) on frames with +0x02 bit 0 clear."""
    ai.reset_approach(ram, rec)
    return 0x2000 if not ram.u16(rec + 2) & 1 else 0


def _evade(c) -> bool:
    """Evasion state machine in +0x94 (1 pick, 3 retreat, 4 back off, 5 side step, 6 keep out).
    The game re-tests the distance (2,951 or more) inside states 3, 4 and 6; the test before them
    already returned for those distances, so the port leaves the repeats out."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    if ram.s16(rec + 0x21A):
        return False
    dist = ram.s32(rec + 0x1C)
    band = ram.s32(rec + 0x14)
    if ram.u8(rec + 0x94) == 1:
        if band < 3 and ai._lcg_next(ram) & 0xFFF >= ram.s16(rec + 0x27E):
            ram.put(rec + 0x94, "B", 3)
        else:
            ram.put(rec + 0x94, "B", ram.u8(EVADE_STATES + 2 * ai.random_below(ram, 7)))
    if ram.s16(o + 0x16) == 4:
        dist -= 0x12C
    state = ram.u8(rec + 0x94)
    if state not in (1, 2) and dist >= 0xB87:
        ram.put(rec + 0x94, "B", 0)
        ram.put(rec + 4, "H", 0)
        return True
    until = ram.s16(rec + 0x20A)
    facing = ram.s16(f + 0x3E)
    if state == 3:
        ai.reset_approach(ram, rec)
        om = ram.u32(o + 0x54)
        if ram.u8(om + 0x2D) and ram.u8(om + 0x2E) < ram.s16(o + 0x58):
            return False               # unreachable: _reaction_body has set state 2 for this
        if until >= 0x1D:
            if band >= 3:
                ram.put(rec + 4, "H", _pad_back_on_even(ram, rec))
                ram.put(rec + 0x68, "h", ai._lcg_next(ram) & 0xF)
                return True
            return ai.filter_attacks_no_special(ram, rec) <= 0
        if until < 9:
            ram.put(rec + 4, "H", 0x8000 if facing < 0x4000 else 0)
            return True
        if band < 3:
            if ai.filter_attacks_no_special(ram, rec) <= 0:
                return True
            ram.put(rec + 0x68, "h", -1)
            return False
        if facing < 0x4000:
            ram.put(rec + 0x94, "B", 4)
            ram.put(rec + 4, "H", 0x8000)
            return True
        return False
    if state == 4:
        ai.reset_approach(ram, rec)
        if facing > 0x4000 and ram.s32(rec + 0x18) >= 2:
            ram.put(rec + 4, "H", 0x2000)
            return True
        if until >= 9 and band < 2:
            if ai.filter_attacks_no_special(ram, rec) <= 0:
                return True
            ram.put(rec + 0x68, "h", -1)
            return False
        ai.start_script(ram, rec, ai.IDLE_SCRIPT)
        return True
    if state == 5:
        if ram.u32(rec + 0x224) & 0x400000 or ai._lcg_next(ram) & 7 or until < 7:
            ram.put(rec + 4, "H", 0x2000)
            return False
        if facing >= 0x4000:
            ram.put(rec + 0x94, "B", 3)
        ai.side_step(ram, rec, -1)
        return True
    if state == 6:                     # no code path sets state 6 (game-bugs.md)
        ai.reset_approach(ram, rec)
        if until >= 0x1D:
            ram.put(rec + 4, "H", 0x8000 if ram.s32(rec + 0x18) > 0 else 0)
            return True
        if ram.s32(rec + 0x18) >= 2 or until < 8:
            ai.start_script(ram, rec, ai.IDLE_SCRIPT)
            return True
        ram.put(rec + 4, "H", 0x3000)
        ram.put(rec + 0x48, "h", 0x14)
        return True
    return False


def _open_now(c, row: int) -> bool:
    """Window, restriction and condition of a branch row for the CPU this frame."""
    ram = c.ram
    fighter, opp = ai.Fighter(ram, c.f), ai.Fighter(ram, c.o)
    return (ram.u8(row + 9) <= ram.s16(c.f + 0x58) <= ram.u8(row + 10)
            and ai.restriction_ok(fighter, opp, ram.u8(row + 2))
            and ai._cond_ok(ram, row, fighter, opp, ram.u32(c.rec + 0x64)))


def _expire_lists(c) -> None:
    """The follow-up lists prepared by _new_move are filtered to their open rows (into 0x800A0590)
    and then dropped: the code that would press one counts the open rows in a register that is
    never incremented (game-bugs.md #10), so none is ever executed."""
    ram, rec = c.ram, c.rec
    if ram.s16(rec + 0xC0) > 0:
        k = 0
        for i in range(ram.s16(rec + 0xC2)):
            row = ram.u32(rec + 0xC4 + 4 * i)
            if _open_now(c, row):
                ram.put(THROW_ROWS + 4 * k, "I", row)
                k += 1
        ram.put(rec + 0xC0, "h", 0)
        ram.put(rec + 0xC2, "h", 0)
        ram.put(rec + 0xD4, "h", 1)
    if ram.s16(rec + 0xD8) > 0:
        k = 0
        for i in range(ram.s16(rec + 0xDA)):
            row = ram.u32(rec + 0xDC + 4 * i)
            if _open_now(c, row):
                ram.put(THROW_ROWS + 4 * k, "I", row)
                k += 1
        ram.put(rec + 0xD8, "h", 0)
        ram.put(rec + 0xDA, "h", 0)
    if ram.s16(rec + 0x1A0) >= 0:
        for i in range(ram.s16(rec + 0x1A2)):
            row = ram.u32(rec + 0x1A4 + 4 * i)
            if _open_now(c, row):
                ram.put(THROW_ROWS, "I", row)
        ram.put(rec + 0x1A0, "h", 0)
        ram.put(rec + 0x1A2, "h", 0)


def _duck_or_back(c) -> int:
    """Pad against an attack: crouch-back 0xC000 (back 0x8000 against 0x217) when facing the
    opponent, else nothing; restarts the approach timers."""
    ram, rec = c.ram, c.rec
    if ram.s16(c.f + 0x32) != 0:
        return 0
    ram.put(rec + 0x40, "h", 0x28)
    ram.put(rec + 0x48, "h", -1)
    ram.put(rec + 0x3A, "h", 0)
    ram.put(rec + 0x38, "h", 0)
    return 0x8000 if ram.u32(rec + 0x234) == 0x217 else 0xC000


def _avoid_air_attack(c) -> None:
    """Outside its own attack (+0x50 == 0) the CPU backs off from airborne attacks at close range,
    turns towards the opponent, or dashes back (bank 7 moves differently)."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    if ram.s16(rec + 0x50) != 0:
        return
    om = ram.u32(o + 0x54)
    angle, closing = ram.s16(rec + 0x2E), ram.s32(rec + 0x18)
    a = ram.u8(om + 0x19) == 0 or closing > 1 or ram.s16(rec + 0x280) <= ai._lcg_next(ram) & 0xFFF
    pad = None
    if not a:
        if angle > 0x3FFF or (ram.s32(rec + 0x24) > -0xB):
            if ram.u8(om + 0x1A) - ram.s16(o + 0x58) < 0x15 or angle < 0x4001:
                b = True
            else:
                b, pad = False, 0x2000
        else:
            b, pad = False, 0x6000
        if not b:
            ram.put(rec + 4, "H", pad)
            raise Done
    if angle < 0x6001 or closing > 1:
        if angle <= 0x1000:
            return
        if ai._lcg_next(ram) & 0x7FFF >= angle:
            return
        if ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x27E):
            return
        ram.put(rec + 0x38, "h", 8)
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x40, "h", 0x30)
        if ram.s16(f + 0x16) == 7:
            ram.put(rec + 4, "H", 0x8000 if angle > 0x3FFF else 0x2000)
            raise Done
        if ram.s16(rec + 0x20C) == 0 or ai._lcg_next(ram) & 7:
            pad = 0x2000
            if closing < 3:
                pad = 0x8000 if ram.u16(rec + 2) & 1 else 0x2000
        else:
            pad = _duck_or_back(c)
        ram.put(rec + 4, "H", pad)
        raise Done
    if ram.u8(o + 0xDB):
        ram.put(rec + 4, "H", 0)
    elif ram.s16(rec + 0x208):
        ram.put(rec + 4, "H", 0x4040 if ram.u16(rec + 2) & 1 else 0x4020)
    else:
        if ai._lcg_next(ram) & 0xFFF >= ram.s16(rec + 0x27E):
            ram.put(rec + 0x68, "h", -2)
            return
        if ram.s16(f + 0x16) == 7:
            ram.put(rec + 4, "H", 0x8000 if angle > 0x3FFF else 0x2000)
        else:
            ram.put(rec + 4, "H", 0x2000)
    raise Done


FORCE_LEADER_RETURN = ai.FIGHTER_BASE   # FUN_800B2E60 (Tekken Force overlay) returns the player record


def _roll(ram: Ram, n: int) -> int:
    """n * ((rand() + LCG) & 0x7FFF) >> 15 with the LCG advanced (the game's inline uniform draw)."""
    return ai.random_below(ram, n)


def _mark(c, pred) -> int:
    return ai.mark_candidates(c.ram, c.rec, pred)


def _neutral(ram: Ram):
    return lambda t, br: ram.u32(t + 4) & 1 == 1 and ram.u8(t + 0x2D) == 0


def _side_step_or_special(ram: Ram):
    return lambda t, br: ram.s16(br) == -0x3FFF or (
        ram.u32(t + 4) & 0xA0000 == 0x80000 and not ram.u32(t + 4) & 0x600000)


def _attack(c) -> bool:
    """LAB_8005E568..LAB_800605EC: pick and execute an attack; True ends the decision."""
    ram, rec, f = c.ram, c.rec, c.f
    if ram.u32(ai.GAME_MODE) == 8:
        if ram.s32(ai.FORCE_TARGETS + 4 * ram.u16(rec)) >= 1:
            return False
        if ram.u8(FORCE_LEADER_RETURN + 0x1F) != ram.u8(f + 0x1E):
            if ai._lcg_next(ram) & 0xFFF < ram.s16(ram.u32(rec + 0x32C) + 4):
                return False
    if ram.s16(rec + 0x4C) >= 1:
        ram.put(rec + 0x4C, "h", ram.s16(rec + 0x4C) - 1)
        ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
        return True
    if ram.s16(rec + 0x44) >= 5:
        ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
        return True
    band = ram.s32(rec + 0x14)
    if not (band < 4 and ram.s16(rec + 0x21A) == 0 and ram.s16(rec + 0x1D2) < ram.s16(rec + 0x1D4)):
        return False
    if band > 2 and _roll(ram, 12) != 0:
        return False
    if band > 1 and _roll(ram, 8) == 0:
        return False
    if ram.s16(rec + 0x3A) != 0:
        if ram.s16(rec + 0x6C) < 1 and (ram.s16(rec + 0x20C) == 0 or ram.s32(rec + 0x18) > 3):
            if ram.u32(rec + 0x230) & 4 and _roll(ram, 0x1000) < 0x100:
                return False
        else:
            ram.put(rec + 4, "H", 0x8000)
            return True
    n = _choose(c)
    if n is not None:
        n = _last_resort(c, n)
        if n < 0:
            ai.reset_approach(ram, rec)
            return True
    pick = ai.execute_candidate(ram, rec)
    if pick < 0:
        return False
    ram.put(rec + 0x40, "h", 0x28)
    ram.put(rec + 0x48, "h", -1)
    ram.put(rec + 0x3A, "h", 0)
    ram.put(rec + 0x38, "h", 0)
    target = ram.u32(ai.CANDIDATES + 12 * pick)
    if ram.s16(ai.TEAM_OR_SURVIVAL) == 0 and ram.u32(target + 0x24) >> 8 & 0x20:
        ram.put(rec + 0xC0, "h", 1)
    elif ((ram.u32(rec + 0x224) & 0x80000 and ai._lcg_next(ram) & 0x3F < 0x20)
          or (ram.u32(target + 4) & 0x80000 and ai._lcg_next(ram) & 0x3F < 0x30)):
        ram.put(rec + 0xD8, "h", 1)
    pressed = ram.u32(rec + 0x5C)
    state = ram.s16(pressed + 4) if pressed else 0
    if state in (0x2021, 0x2829):
        ram.put(rec + 0x4C, "h", 0xC)
    if ram.u8(target + 0x2D) == 0 and not ram.u32(target + 4) & 0x80000:
        return True
    ram.put(rec + 0x60, "I", target)
    return True


def _last_resort(c, n: int) -> int:
    """LAB_80060350: with nothing marked, far away and at 10 % health, a 1-in-4 draw and word 17
    (+0x258) mark the moves flagged +0x24 bit 16 (desperation moves)."""
    ram, rec, f = c.ram, c.rec, c.f
    if (n == 0 and ram.s32(rec + 0x18) > 2 and ram.s16(f + 0x122) == 0
            and ram.s32(f + 0x3F4) <= int(ram.s32(f + 0x3F8) / 10)
            and ai._lcg_next(ram) & 3 == 0 and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x258)):
        n = _mark(c, lambda t, br: bool(ram.u32(t + 0x24) >> 8 & 0x100))
    return n


def _choose(c):
    """LAB_8005E7C0: mark the candidates to execute. Returns their count (-1: input already set) for
    LAB_80060350, or None to execute directly (the rare neutral-move pick while waiting)."""
    _probe(c, 0x8005E7C0)
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    wait = ram.s16(rec + 0x68)
    threshold = ram.s16(rec + 0x248)
    if ram.s16(rec + 0xD4):
        removed = 0
        k = 0
        while k < ram.s16(rec + 0x70):
            e = ai.CANDIDATES + 12 * k
            mark = ram.s16(e + 8)
            if mark >= 0 and ram.u32(ram.u32(e) + 0x24) >> 8 & 0x20:
                if mark > 0:
                    removed += 1
                ram.put(e + 8, "h", -1)
            k += 1
        ram.put(rec + 0x72, "h", ram.s16(rec + 0x72) - removed)
    if ram.s32(rec + 0x80) >= 0x1A and ram.s16(rec + 0x6C) < 0 and ram.s16(rec + 0x6A) == 0:
        t = ram.s16(rec + 0x20A) - ((ram.u32(ai.LCG) & 7) + 4)
        ai._lcg_next(ram)
        ram.put(rec + 0x6C, "h", max(t, 3))
    if ram.s16(rec + 0x6C) >= 1:
        return 0
    word35 = ram.s16(rec + 0x27E)
    if (ram.u8(rec + 0x8F) or ram.u8(rec + 0x91)
            or (ram.s32(rec + 0x80) > 0x19 and int(word35 / 2) <= ai._lcg_next(ram) & 0xFFF)
            or ((ram.s32(rec + 0x84) - 1) & 0xFFFFFFFF < 0x13 and word35 <= ai._lcg_next(ram) & 0xFFF)):
        wait = -1
    om = ram.u32(o + 0x54)
    band = ram.s32(rec + 0x14)
    if ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x280) and ram.u8(o + 0xDB) and ram.s16(rec + 0x230) != 0x4C02:
        last, first = ram.u8(om + 0x1A), ram.u8(om + 0x19)
        frame = ram.s16(o + 0x58)
        if first + int((last - first) / 2) <= frame <= last and ram.s16(rec + 0x2E) < 0x4001 and band == 2:
            ram.put(rec + 0x68, "h", -1)
    if ram.s16(o + 0xA0) == 6 and band < 3 and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x258):
        ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 2)
    if (ram.u32(rec + 0x230) & 0x605 or ram.u8(o + 0xDB) or ram.u8(o + 0xDF) or ram.s16(o + 0x16) == 0x13
            or ram.s16(rec + 0x20A) < 10):
        threshold = 0
        ram.put(rec + 0x91, "B", 0)
    if ram.u32(ai.GAME_MODE) == 7 and ball_ahead(ram, rec) > 0:
        return ai.filter_attacks(ram, rec)
    if ram.s16(rec + 0x208) and ram.s16(rec + 0x88) == 0:
        return _vs_grounded(c, wait)
    if ram.s16(rec + 0x230) == 0x4C02 and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x274):
        return _vs_stance(c)
    if ram.s16(rec + 0x46) >= 0:
        n = _mark(c, lambda t, br: ram.u8(t + 0x2D) != 0 and bool(
            ram.u32(t + 4) & 0x80000 or ram.u32(t + 8) & 0x200000) and not ram.u32(t + 4) & 0x20000)
        if n > 0:
            ram.put(rec + 0x46, "h", -1)
        return n
    if ram.s16(rec + 0x20E) != 0:
        if ram.u8(rec + 0x8F) == 0 and ram.s16(rec + 0x258) <= ai._lcg_next(ram) & 0xFFF:
            if wait < 1:
                return (ai.filter_attacks_no_special(ram, rec) if ram.u32(rec + 0x230) & 1
                        else ai.filter_attacks(ram, rec))
            return 0
        return ai.filter_side_steps_then_quick(ram, rec)
    if (ram.s16(rec + 0x20C) or ram.s16(rec + 0x214)) and ram.s16(rec + 0x88) == 0:
        if ram.u8(rec + 0x8F) or ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x258):
            return ai.filter_side_steps_then_quick(ram, rec)
        if wait < 1:
            return (ai.filter_attacks_no_special(ram, rec) if ram.u32(rec + 0x230) & 1
                    else ai.filter_attacks(ram, rec))
        return 0
    if wait < 1:
        if ram.s16(rec + 0x44) < 0:
            return _approach_attack(c, threshold)
        n = _mark(c, lambda t, br: ram.u32(t + 4) & 0xA0000 == 0x80000 and ram.u8(t + 0x19) == 0)
        ram.put(rec + 0x44, "h", -1)
        return n
    if band > 2 or ram.u32(rec + 0x224) & 1 or ai._lcg_next(ram) & 0xFFF > 3:
        return 0
    if _mark(c, _neutral(ram)) < 1:
        return 0
    return None


def _vs_grounded(c, wait: int) -> int:
    """The opponent is down or crouching (+0x208)."""
    ram, rec = c.ram, c.rec
    if ram.s16(rec + 0x50) != 0:
        return 0
    x = ai._lcg_next(ram)
    if ram.s16(rec + 0x27E) <= x & 0xFFF:
        wait = -1
    if not (ram.s16(rec + 0x2E) < 0x4001 or ai._lcg_next(ram) & 0xF != 0):
        return _mark(c, lambda t, br: bool(ram.u32(t + 4) & 0x20000))
    if wait >= 0:
        return 0
    x = ai._lcg_next(ram)
    u = x & 0xFFF
    if u < 0x334:
        return _mark(c, lambda t, br: ram.u8(ram.u32(t + 0xC) + 3) == 0x35 and not ram.u32(t + 8) & ai.HINT_NEVER)
    if u < 0x3AF:
        ai.side_step(ram, rec, x & 1)
        return -1

    def low_or_hint(extra: tuple):
        def pred(t, br):
            w = ram.u32(t + 8)
            return (ram.u8(t + 0x2D) < 0x51 and (bool(w & 0x10000) or w & 0xFFFF in extra)
                    and not w & ai.HINT_NEVER)
        return pred

    if u < 0x6E2:
        return _mark(c, low_or_hint((0x51F,)))
    if u < 0x75D and not ram.u32(rec + 0x224) & 1:
        return _mark(c, _neutral(ram))
    if u < 0x829:
        return _mark(c, lambda t, br: ram.s16(br) == -0x3FFE)
    if (ram.s32(rec + 0x14) - 2) & 0xFFFFFFFF < 2 and u < 0x9C3:
        ai.start_script(ram, rec, WAKE_UP_SCRIPT)
        return -1
    return _mark(c, low_or_hint((0x51F, 0x10F)))


WAKE_UP_SCRIPT = 0x80022E96


def _hint_ground(ram: Ram):
    return lambda t, br: bool(ram.u32(t + 8) & 0x10000) and ram.u8(t + 0x2D) == 0 and ram.u8(t + 0x19) == 0


def _vs_stance(c) -> int:
    """The opponent is in a stance (state 0x4C02), after a draw against word 28 (+0x274)."""
    ram, rec, o = c.ram, c.rec, c.o
    band = ram.s32(rec + 0x14)
    n = 0
    if band < 3:
        if band > 1:
            x = ai._lcg_next(ram)
            if x & 0xF == 0:
                n = _mark(c, lambda t, br: ram.s16(br) == -0x3FFF)
            else:
                n = _mark(c, _hint_ground(ram))
    else:
        side = True
        if ram.s32(rec + 0x24) < 0x33:
            x = ai._lcg_next(ram)
            if x & 7 == 0:
                n = _mark(c, _hint_ground(ram))
                side = False
        if side:
            n = _mark(c, lambda t, br: ram.s16(br) == -0x3FFF)
            if n > 0:
                ram.put(rec + 0x3A, "h", 2)
                ram.put(rec + 0x38, "h", 0xFA)
                ram.put(rec + 0x40, "h", 0x136)
    if (band < 4 and ram.s16(rec + 0x21A) == 0
            and ram.s16(rec + 0x27E) <= ai._lcg_next(ram) & 0xFFF):
        ram.put(rec + 0x68, "h", -1)
        if ram.u8(o + 0xDB) == 0 and ai._lcg_next(ram) & 0x3F < 0x20 and ram.u32(rec + 0x7C) == 0:
            n += ai.filter_punish_level_no_high(ram, rec)
        else:
            n += ai.filter_punish_level(ram, rec)
    return n


BANK_SETUPS = 0x80022F8C           # per bank type (16-byte stride): pointer to (s16 chance, s16 slot, u32 script) x n


def _approach_attack(c, threshold: int) -> int:
    """Waiting is over and nothing urgent: throws (AI hint bit 22 rows), bank-specific setups,
    neutral moves, side steps or the regular attack filters."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    band = ram.s32(rec + 0x14)
    if ((ram.u8(rec + 0x91) or ai._lcg_next(ram) & 0xFFF < threshold)
            and band < 2 and ram.s16(o + 0x16) != 0x13):
        x = ai._lcg_next(ram)
        n = 0
        throw_rows = lambda t, br: bool(ram.u32(t + 8) & ai.HINT_NEVER) and ram.u16(br) & 0xC200 != 0x200
        plain_throws = lambda t, br: bool(ram.u32(t + 8) & ai.HINT_NEVER) and ram.u16(br) & 0xFFE0 == 0
        if x & 0xFFF < ram.s16(rec + 0x24E):
            n = _mark(c, throw_rows)
            if n < 1:
                n = _mark(c, plain_throws)
            else:
                ram.put(rec + 0x98, "h", 1)
        else:
            n = _mark(c, plain_throws)
        if n > 0:
            return n
    table = ram.u32(BANK_SETUPS + 16 * ram.s16(f + 0x16))
    if (ram.s16(rec + 0x42) < 0 and table and ram.s16(rec + 0x50) == 0 and not ram.u32(rec + 0x224) & 1
            and ram.s16(f + 0xA0) != ram.s16(table + 2) and ram.s16(rec + 0x2E) < 0x2001
            and ram.u8(f + 0xDB) == 0 and band < 3 and ram.s16(rec + 0x208) == 0):
        u = ai._lcg_next(ram) & 0xFFF
        p = table
        while True:
            if u <= ram.s16(p):
                if ai.branch_open_to(ram, rec, ram.s16(p + 2)):
                    ai.start_script(ram, rec, ram.u32(p + 4) + 2)
                    ram.put(rec + 0xD8, "h", 1)
                    ram.put(rec + 0x42, "H", (ai._lcg_next(ram) & 0xF) + 0x1C)
                    return -1
                break
            p += 8
            if ram.s16(p) < 0:
                break
    if band < 3 and ram.u8(f + 0xDB) == 0 and not ram.u32(rec + 0x224) & 1 and ai._lcg_next(ram) & 0x3F < 0xE:
        return _mark(c, _neutral(ram))
    x = ai._lcg_next(ram)
    if x & 0x3F < 0x20:
        if ai._lcg_next(ram) & 1:
            return _mark(c, _side_step_or_special(ram))
        return ai.filter_punish_level(ram, rec)
    if (ram.s16(rec + 0x44) < 0 and ram.s16(rec + 0x46) < 0 and not ram.u32(rec + 0x224) & 1
            and ram.u8(f + 0xDB) == 0 and ai._lcg_next(ram) & 0xFFF < 0x200):
        n = _mark(c, _neutral(ram))
        if n > 0:
            ram.put(rec + 0x44, "h", 0x12)
            ram.put(rec + 0x68, "h", -1)
            return n
    n = _mark(c, _side_step_or_special(ram))
    if ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x250):
        return n + ai.filter_vs_posture(ram, rec)
    if ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x252):
        return n + ai.filter_fast_attacks(ram, rec)
    if ram.u32(rec + 0x230) & 1 and ai._lcg_next(ram) & 0xFFF >= ram.s16(rec + 0x27E):
        return n + ai.filter_attacks_no_special(ram, rec)
    if ai._lcg_next(ram) & 0x3F < 10:
        return n + ai.filter_plain_attacks(ram, rec)
    if ram.u8(f + 0xDB) == 0 and ram.s16(rec + 0x46) < 0 and _roll(ram, 0x1000) < 0x200:
        n = _mark(c, lambda t, br: ram.u8(t + 0x19) != 0 and not ram.u32(t + 4) & 0x20000 and bool(
            ram.u32(t + 4) & 0x80000 or ram.u32(t + 8) & 0x200000))
        if n > 0:
            ram.put(rec + 0x46, "h", 4)
            a, b, d = _roll(ram, 4), _roll(ram, 4), _roll(ram, 4)
            ram.put(rec + 0x46, "h", a + b + d + 1)
            return n
    if _roll(ram, 0x1000) < 10:
        return n + _mark(c, lambda t, br: ram.u8(t + 0x2D) == 0 and ram.u8(t + 0x19) == 0
                         and not ram.u32(t + 4) & 0x20000 and ram.s16(br + 6) not in (0x1EE, 0x6A3))
    return n + ai.filter_attacks(ram, rec)


APPROACH_REACH = 0x80098628        # u32 per closing band: reach bits that make an approach unsafe


def _move(c) -> None:
    """LAB_800605EC..LAB_80061108: movement when no attack was executed."""
    ram, rec = c.ram, c.rec
    if _movement(c) == 0:
        if ram.s16(rec + 0x4A) >= 0:
            ram.put(rec + 4, "H", 0x4000)
        elif ram.s16(rec + 0x48) >= 0:
            ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
        else:
            ram.put(rec + 4, "H", 0)


def _movement(c) -> int:
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    if ram.s16(rec + 0x8A) >= 0:
        return 0
    if ram.s16(rec + 0x38) < 0:
        if (ram.s16(rec + 0x50) == 0 and ram.s16(rec + 0x4A) < 0 and ram.s16(rec + 0x48) < 0
                and ram.s16(rec + 0x46) < 0):
            return _pick_movement(c)
        return 0
    if (ram.u8(rec + 0x200) == 0 or ram.s32(rec + 0x1C) > 7000) and ram.s32(rec + 0x14) > 0:
        x = ram.u32(ai.LCG)
        x1 = (5 * x + 3) & 0xFFFFFFFF
        if ram.s16(rec + 0x27E) <= x & 0xFFF:
            unsafe = False
            if ram.s16(rec + 0x20C) != 0 and ram.s16(rec + 0x6A) == 0 and ram.s16(f + 0x3E) < 0x5000:
                if ram.s32(rec + 0x1C) < 0xB87:
                    w = ram.u32(ram.u32(o + 0x54) + 8)
                    r = w & 0xFFFF0000
                    if not w & 0x1C0000:
                        r |= 0xC0000
                    unsafe = bool(r & ram.u32(APPROACH_REACH + 4 * ram.s32(rec + 0x18)))
            ram.put(ai.LCG, "I", x1)
            if unsafe:
                ai.reset_approach(ram, rec)
                return _pick_movement(c)
        ram.put(ai.LCG, "I", x1)
        if ram.s16(rec + 0x3A) == 2:
            if ram.s32(rec + 0x18) < 3 and ai._lcg_next(ram) & 0xFFF < 0x20:
                ai.reset_approach(ram, rec)
                pad = 0x8000
            else:
                pad = 0x2000
            ram.put(rec + 4, "H", pad)
            return 1
        if ram.s16(rec + 0x68) < 0x24 and ram.s32(rec + 0x18) == 2 and ai._lcg_next(ram) & 0xF == 0:
            if _mark(c, lambda t, br: ram.s16(br) == -0x3FFF) > 0 and ai.execute_candidate(ram, rec) >= 0:
                ram.put(rec + 0x3A, "h", 0)
                ram.put(rec + 0x38, "h", 0)
                ram.put(rec + 0x40, "h", 0x28)
                return 1
        ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
        return 1
    ai.reset_approach(ram, rec)
    return _pick_movement(c)


def _pick_movement(c) -> int:
    """LAB_80060944: a random movement by distance band (or, while waiting long, closing band)."""
    _probe(c, 0x80060944)
    ram, rec = c.ram, c.rec
    if ram.s16(rec + 0x40) >= 0 or ram.s16(rec + 0x48) >= 0:
        return 0
    v = _roll(ram, 0x1000)
    choice = 0
    if ram.u8(rec + 0x200) == 0:
        if ram.s16(rec + 0x68) < 0x24:
            choice = _by_distance(c, v)
        else:
            choice = _by_closing(c, v)
            if choice in (3, 6) and ram.s16(rec + 0x284) <= ai._lcg_next(ram) & 0xFFF:
                choice = 0
        if (choice in (3, 6) and (ram.u32(rec + 0x230) & 0x80000 or ram.u32(rec + 0x234) != 0)
                and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x27E)):
            choice = 0
    return _do_movement(c, choice)


def _by_distance(c, v: int) -> int:
    ram, rec = c.ram, c.rec
    band = ram.s32(rec + 0x14)
    if band in (0, 1):
        return 3 if v < 0x14 else 0
    if band == 2:
        if v < 0x7A:
            return 5
        if v < 0x1EB:
            return 1
        if v < 0x214:
            return 3
        return 8 if v < int((ram.s16(rec + 0x25C) << 12) / 1000) else 0
    if band == 3:
        return 2 if v < 0x666 else 1 if v < 0xB33 else 0
    if band == 4:
        return 2 if v < 0xCC else 4 if v < 0x599 else 1
    if band == 5:
        if ram.s16(rec + 0x2A) < 0x2D1 and ram.s16(rec + 0x208) == 0 and v > 0x11D:
            return 1
        return 4
    return 0                           # unreachable: the band is 0-5


def _by_closing(c, v: int) -> int:
    ram, rec = c.ram, c.rec
    closing = ram.s32(rec + 0x18)
    if closing in (0, 1):
        return 6 if v < 0x199 else 3 if v < 0x333 else 0
    if closing == 2:
        if v <= 0x27:
            return 2
        return 3 if v < 0x170 else 0
    if closing == 3:
        if v < 0x1EB:
            return 2
        if v < 0x214:
            return 5
        if v < 0x218:
            return 3
        if v < 0x22D:
            return 1
        return 8 if v < 0x241 and ram.u32(rec + 0x224) & 2 else 0
    if closing == 4:
        if v < 0x80:
            return 2
        if v < 0x90:
            return 5
        if v < 0xC0:
            return 8
        return 1 if v < 0x3C0 else 0
    if closing == 5:
        if ram.s16(rec + 0x2A) < 0x2D1 and ram.s16(rec + 0x208) == 0 and v > 0x50:
            return 2 if v < 0xCC else 1 if v < 0x400 else 5 if v < 0x5EB else 0
        return 4
    return 0                           # unreachable: the reach band is 1-5


def _do_movement(c, choice: int) -> int:
    """Movement cases: 1 side step or walk in, 2 walk in, 3 step back, 4 side step or dash in,
    5 dash in, 6 crouch dash (0xC002 rows) or step back, 8 side step, then execute a candidate."""
    ram, rec = c.ram, c.rec
    side_steps = lambda cmd: (lambda t, br: ram.s16(br) == cmd)
    if choice == 0:
        return 0
    if choice == 1:
        if _mark(c, side_steps(-0x3FFF)) >= 1:
            ram.put(rec + 0x3A, "h", 0)
            ram.put(rec + 0x38, "h", 0)
            ram.put(rec + 0x40, "h", 0x28)
            return int(ai.execute_candidate(ram, rec) >= 0)
        choice = 2
    if choice == 4:
        if _mark(c, side_steps(-0x3FFF)) >= 1:
            ram.put(rec + 0x3A, "h", 2)
            ram.put(rec + 0x38, "h", 0xFA)
            ram.put(rec + 0x40, "h", 0x136)
            return int(ai.execute_candidate(ram, rec) >= 0)
        choice = 5
    if choice == 6:
        if _mark(c, side_steps(-0x3FFE)) >= 1:
            ram.put(rec + 0x40, "h", 0x3C)
            return int(ai.execute_candidate(ram, rec) >= 0)
        choice = 3
    if choice == 2:
        band = ram.s32(rec + 0x14)
        if 0 <= band < 3:
            q = _roll(ram, 8)
            short, long_ = q + 4, q + 0x2C
        elif band == 3:
            q = _roll(ram, 10)
            short, long_ = q + 10, q + 0x32
        else:
            q = _roll(ram, 0xF)
            short, long_ = q + 0xF, q + 0x37
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x38, "h", short)
        ram.put(rec + 0x40, "h", long_)
        ram.put(rec + 4, "H", 0x6000 if ram.s16(rec + 0x3C) > 0 else 0x2000)
        return 1
    if choice == 3:
        q = _roll(ram, 5)
        ram.put(rec + 0x38, "h", q + 0x14)
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x40, "h", q + 0x3C)
        ram.put(rec + 4, "H", 0xC000 if ram.s16(rec + 0x3C) > 0 else 0x8000)
        return 1
    if choice == 5:
        q = _roll(ram, 0x14)
        ram.put(rec + 0x38, "h", q + 0x28)
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x40, "h", q + 0x50)
        ram.put(rec + 4, "H", 0x6000 if ram.s16(rec + 0x3C) > 0 else 0x2000)
        return 1
    if choice == 8 and (ram.s32(rec + 0x18) > 2 or ram.s16(rec + 0x20A) > 10):
        ai.side_step(ram, rec, -1)
    return int(ai.execute_candidate(ram, rec) >= 0)


def _low_parry_or_escape(c) -> int:
    """Kind 1, or kind 9 on a 1-in-64 draw against the attack word 0x412."""
    ram = c.ram
    if ram.u32(c.rec + 0x234) != 0x412:
        return 1
    return 9 if ai._lcg_next(ram) & 0x3F == 0 else 1


def _hold_guard(c) -> None:
    """After the opponent whiffs, a draw (+0x258 plus a difficulty term) marks a punish chance
    (+0x8F); otherwise hold the current direction while the guard state (+0x6A) says so."""
    ram, rec, o = c.ram, c.rec, c.o
    if ram.u8(o + 0xD2):
        threshold = ram.s16(rec + 0x258) + _w(ram.s16(rec + 0x216) * ram.u16(ai.DIFFICULTY) * 30)
        if ai._lcg_next(ram) & 0xFFF < threshold:
            ram.put(rec + 0x8F, "B", 1)
            return
    first = c.op_first
    if ((ram.s16(rec + 0x6C) >= 0 or first == 0 or first - 0x1E < c.op_frame) and ram.s16(rec + 0x6A) != 0):
        ram.put(rec + 4, "H", ram.u16(rec + 6) & 0xF000)
        raise Done


def _track(c) -> None:
    """Per-frame bookkeeping before the decision: windows, distance bands, guard needs."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    c.om = om = ram.u32(o + 0x54)
    c.sm = sm = ram.u32(f + 0x54)
    c.my_first, c.my_last, c.my_frame = ram.u8(sm + 0x2D), ram.u8(sm + 0x2E), ram.s16(f + 0x58)
    c.op_first, c.op_last, c.op_frame = ram.u8(om + 0x2D), ram.u8(om + 0x2E), ram.s16(o + 0x58)
    ram.put(rec + 0x7C, "I", 0)
    if not ram.u32(sm + 0x24) >> 8 & 0x20:
        ram.put(rec + 0xD4, "h", 0)
    b8e, b90 = ram.u8(rec + 0x8E), ram.u8(rec + 0x90)
    ram.put(rec + 0x8E, "B", 0)
    ram.put(rec + 0x90, "B", 0)
    ram.put(rec + 0x8F, "B", b8e)
    ram.put(rec + 0x91, "B", b90)
    if ram.s32(o + 0x3F4) <= int(ram.s32(o + 0x3F8) / 10):
        for off in (0x250, 0x252, 0x258, 0x25A):
            ram.put(rec + off, "h", 0)
    x = ai._lcg_next(ram)
    if (ram.s16(rec + 0x27E) <= x & 0xFFF and ram.s16(rec + 0x2E) > 0x1FFF and ram.s16(f + 0x3E) < 0x6001
            and ram.s32(rec + 0x18) < 3):
        ram.put(rec + 0x8F, "B", 1)
    ram.put(rec + 0x28, "h", int(sm != ram.u32(rec + 0x58) or c.my_frame < ram.s16(rec + 0x4E)))
    ram.put(rec + 0x204, "h", int(om != ram.u32(rec + 0x1D8) or c.op_frame < ram.s16(rec + 0x206)))
    ram.put(rec + 0x2C, "h", ram.s16(rec + 0x2C) + 1)
    if ram.u32(rec + 0x58) != sm:
        ram.put(rec + 0x58, "I", sm)
        ram.put(rec + 0x2C, "h", 0)
    ram.put(rec + 0x4E, "h", c.my_frame)
    if ram.u32(rec + 0x224) & 0x400000:
        ai.reset_approach(ram, rec)
    if c.my_first == 0:
        if not ram.u32(rec + 0x220) & 0x80000 and ram.u8(o + 0x87) == 0:
            ram.put(rec + 0x1D2, "h", 0)
    elif c.my_first == c.my_frame:
        ram.put(rec + 0x1D2, "h", ram.s16(rec + 0x1D2) + 1)
    if c.op_first == 0:
        if not ram.u32(rec + 0x22C) & 0x80000 and ram.u8(f + 0x87) == 0:
            ram.put(rec + 0x216, "h", -1)
    elif c.op_first == c.op_frame:
        ram.put(rec + 0x216, "h", ram.s16(rec + 0x216) + 1)
        if ram.s16(rec + 0x216) > 10:
            ram.put(rec + 0x216, "h", 10)
    _distance_bands(c)
    _opponent_attack(c)
    _guard_state(c)


def _distance_bands(c) -> None:
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    d = ram.s32(rec + 0x1C)
    ram.put(BALL_CLOSER, "I", 0)
    if ram.u32(ai.GAME_MODE) == 7:
        b = ball_distance(ram, f)
        if b < d:
            ram.put(BALL_CLOSER, "I", 1)
            d = b
    prev = ram.s32(rec + 0x20)
    ram.put(rec + 0x20, "i", d)
    e = d - ram.s16(rec + 0x32A) - 0x80
    ram.put(rec + 0x24, "i", _w(d - prev))
    if e < ram.s16(rec + 0x314):
        pushed = any(ram.s32(fighter + off) for fighter in (f, o) for off in (0x3E8, 0x3EC, 0x3F0))
        if not pushed:
            ram.put(rec + 0x14, "i", 1)
            if ram.s16(rec + 0x50) == 0:
                ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 1)
        else:
            ram.put(rec + 0x14, "i", 0)
            if ram.s16(rec + 0x50) == 0:
                ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 2)
        ram.put(rec + 0x2A, "h", 0)
    elif e < ram.s16(rec + 0x316):
        ram.put(rec + 0x14, "i", 2)
        ram.put(rec + 0x2A, "h", 0)
    elif e < ram.s16(rec + 0x318):
        ram.put(rec + 0x14, "i", 3)
        ram.put(rec + 0x2A, "h", 0)
    else:
        band, extra = (4, 2) if e < ram.s16(rec + 0x31A) else (5, 3)
        ram.put(rec + 0x14, "i", band)
        r = ai.rand(ram)
        v = ((r + ram.u32(ai.LCG)) & 0x7FFF) * extra
        ai._lcg_next(ram)
        ram.put(rec + 0x2A, "h", _h(ram.s16(rec + 0x2A) + band + (v >> 15)))
    if ram.s16(rec + 0x50) == 0 or ram.u8(o + 0xDB):
        ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 1)
    g = _w(ram.s32(rec + 0x1C) - ram.s16(rec + 0x31E))
    if ram.s32(rec + 0x24) < 0:
        g = _w(g + ram.s32(rec + 0x24))
    band = 1
    for off, margin in ((0x320, 0x80), (0x322, 0x100), (0x324, 0x200), (0x326, 0x280)):
        if g < ram.s16(rec + off) + margin:
            break
        band += 1
    ram.put(rec + 0x18, "i", band)


def _w(v: int) -> int:
    """Wrap to a signed 32-bit int."""
    return (v + 0x80000000) % 0x100000000 - 0x80000000


def _h(v: int) -> int:
    """Wrap to a signed 16-bit int."""
    return (v + 0x8000) % 0x10000 - 0x8000


def _opponent_attack(c) -> None:
    """How long until the opponent's attack is active (+0x20A), whether to guard (+0x20C, +0x6A)."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    om, first, last, frame = c.om, c.op_first, c.op_last, c.op_frame
    if first != 0 or not ram.u32(rec + 0x230) & 0x80000:
        ram.put(rec + 0x20E, "h", 0)
    else:
        ram.put(rec + 0x20E, "h", ram.s16(rec + 0x20E) + 1)
        if ram.u16(om + 0x10) == ram.s16(o + 0xA0):
            ram.put(rec + 0x20E, "h", 0)
    coming = int(ram.s16(rec + 0x20E) > 0 or (first != 0 and frame <= last + 1))
    ram.put(rec + 0x20C, "h", coming)
    if coming == 0 or first - 3 <= frame:
        ram.put(rec + 0x80, "i", 0)
    else:
        ram.put(rec + 0x80, "i", ram.s32(rec + 0x80) + 1)
    if c.my_first == 0 or frame <= last + 1:
        ram.put(rec + 0x84, "i", 0)
    else:
        ram.put(rec + 0x84, "i", ram.s32(rec + 0x84) + 1)
    if ram.s16(rec + 0x20C) == 0:
        ram.put(rec + 0x6C, "h", -1)
    elif ram.s16(rec + 0x6C) > 0:
        ram.put(rec + 0x6C, "h", ram.s16(rec + 0x6C) - 1)
    if ram.s16(rec + 0x20C) == 0 and ram.u32(rec + 0x230) & 0x200000:
        ram.put(rec + 0x20C, "h", 1)
    if ram.u32(rec + 0x230) & 0x80000:
        ram.put(rec + 0x210, "h", ram.s16(rec + 0x210) + 1)
    else:
        ram.put(rec + 0x210, "h", 0)
    grab = int(bool(ram.u32(rec + 0x22C) & 0x400000) and (first == 0 or frame <= last))
    ram.put(rec + 0x214, "h", grab)
    if ram.s16(rec + 0x20C) == 0 and grab == 0:
        ram.put(rec + 0x20A, "h", 999)
        ram.put(rec + 0x92, "B", 0)
    elif first == 0:
        ram.put(rec + 0x20A, "H", (ram.u8(ram.u32(om + 0xC) + 10) - frame + 1) & 0xFFFF)
    else:
        value = 0x3E5
        if frame <= last:
            ram.put(rec + 0x20A, "h", _h(first - frame))
            if _h(first - frame) < 0x65:
                value = None
            else:
                value = 0x3E6
        if value is not None:
            ram.put(rec + 0x214, "h", 0)
            ram.put(rec + 0x20C, "h", 0)
            ram.put(rec + 0x20A, "h", value)


def _needs_guard(c) -> int:
    """+0x6A: 1 when the CPU already holds the guard that stops the opponent's attack level."""
    ram, rec = c.ram, c.rec
    posture = ram.u16(rec + 0x224)
    if ram.s32(rec + 0x1C) >= 0xB87 or ram.s16(rec + 0x88):
        return 0
    attack = ram.u32(rec + 0x234)
    if ram.s16(rec + 0x214):
        return 0 if attack == 0x217 else int(posture in (0x2021, ai.GUARD_LOW))
    if ram.s16(rec + 0x20C) == 0 or ram.s16(rec + 0x2E) > 0x3000:
        return 0
    accepted = {0x412: (0x2021, ai.GUARD_LOW, ai.GUARD_HIGH), 0x217: (ai.GUARD_HIGH,), 0x10F: (ai.GUARD_LOW,),
                0x31F: (ai.GUARD_LOW, ai.GUARD_HIGH), 0x706: (ai.GUARD_LOW, 0x2021)}.get(attack, ())
    return int(posture in accepted)


def _guard_state(c) -> None:
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    ram.put(rec + 0x21A, "H", int(ram.s32(o + JOINTS + 0xA0) < -0xC1B))
    if (ram.s16(f + 0x3E) > 0x3000
            or (not ram.u32(rec + 0x230) & 0x200000 and ram.u32(rec + 0x234) not in (0x607, 0x706))):
        ram.put(rec + 0x94, "B", 0)
    if ram.s16(rec + 0x54) >= 0 and ram.s32(rec + 0x18) < 2 and ram.s16(rec + 0x27E) <= ai._lcg_next(ram) & 0xFFF:
        ram.put(rec + 0x92, "B", 1)
    v = 0
    if ram.u32(rec + 0x230) & 0x204 and ram.u32(rec + 0x230) & 0xFFFF != 0x4C02:
        v = int(ram.u8(o + 0xDB) == 0)
    ram.put(rec + 0x208, "H", v)
    v = int(ram.s16(o + 0x16) == 4 and ram.s16(o + 0xA0) == 0x456)
    ram.put(rec + 0x88, "H", v)
    if v:
        ram.put(rec + 0x216, "h", -1)
    ram.put(rec + 0x6A, "h", _needs_guard(c))
    if not ram.u32(rec + 0x224) & 1:
        ram.put(rec + 0x4A, "h", -1)
    elif ram.s16(rec + 0x3C) > 0:
        ram.put(rec + 0x4A, "h", ram.s16(rec + 0x4A) - 1)
    elif not ram.u32(c.sm + 0x24) >> 8 & 0x10:
        x0 = ai._lcg_next(ram)
        x1 = ai._lcg_next(ram)
        x2 = ai._lcg_next(ram)
        ram.put(rec + 0x4A, "H", (x0 & 7) + (x1 & 0xF) + 0x14 + (x2 & 7))
    ram.put(rec + 0x50, "h", int(c.my_first != 0))
    v = 0
    if ram.u32(c.sm + 4) & 0x200000 and ram.u32(c.sm + 8) & 0x200000:
        v = int(c.my_frame <= c.my_last)
    ram.put(rec + 0x52, "H", v)


# Opponent slots whose throws the CPU always tries to escape.
FORCED_ESCAPES = {0x189, 0x18E, 0x17F, 0x181}
ESCAPE_PRESS = {0x3A: 1, 0x3B: 2, 0x3C: 1}  # latched escape conditions -> command pressed


def _list_rows(ram: Ram, rows: int):
    """Every row of a branch list with common blocks expanded (the terminator excluded)."""
    return [row for row, _ in ai._rows(ram, rows)]


def _throws(c) -> None:
    """Throw escapes (the CPU is thrown, throwState < 0) and throw follow-ups (it throws)."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    state = ram.s16(f + 0x74)
    if state == 0:
        ram.put(rec + 0xA0, "I", 0)
        ram.put(rec + 0x96, "h", 0)
        ram.put(rec + 0x9C, "h", -1)
        ram.put(rec + 0xBC, "I", 0)
        return
    ai.reset_approach(ram, rec)
    move = ram.u32(f + 0x54)
    if state < 1:
        if move == ram.u32(rec + 0xA0):
            ram.put(rec + 4, "H", 0)
            raise Done
        ram.put(rec + 0x96, "h", ram.s16(rec + 0x96) - 1)
        ram.put(rec + 0xA0, "I", move)
        slot, bank = ram.s16(o + 0xA0), ram.s16(o + 0x16)
        forced = slot in FORCED_ESCAPES or (slot == 0x172 and bank in (9, 0)) or (bank == 3 and slot == 0x152)
        if not forced and ai._lcg_next(ram) & 0xFFF >= ram.s16(rec + 0x24A):
            raise Done
        rows = _list_rows(ram, ram.u32(move + 0xC))[:48]
        for k, row in enumerate(rows):
            ram.put(THROW_ROWS + 4 * k, "I", row)
        press = 0
        if rows:
            row = rows[ai.random_below(ram, len(rows))]
            press = ESCAPE_PRESS.get(ram.u8(row + 3), ram.s16(row))
        if press:
            ai.press_command(ram, rec, press, 0)
        else:
            ram.put(rec + 4, "H", 0)
        raise Done
    if (move != ram.u32(rec + 0xA0) and ram.s16(rec + 0x96) >= 0
            and ram.s16(rec + 0x96) < ram.s16(rec + 0x246) - 1
            and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x24C)):
        rows = _throw_follow_ups(c, ram.u32(move + 0xC))
        if not rows:
            ram.put(rec + 0x96, "h", -1)
            ram.put(rec + 0x9C, "h", -1)
            ram.put(rec + 0xBC, "I", 0)
        else:
            ram.put(rec + 0x96, "h", ram.s16(rec + 0x96) + 1)
            ram.put(rec + 0xA0, "I", ram.u32(f + 0x54))
            row = rows[ai.random_below(ram, len(rows))]
            ram.put(rec + 0x9C, "H", ram.u8(row + 9) + 1)
            ram.put(rec + 0xBC, "I", row)
    if ram.s16(f + 0x58) != ram.s16(rec + 0x9C):
        ram.put(rec + 4, "H", 0)
        raise Done
    row = ram.u32(rec + 0xBC)
    index = ram.u32(ai.AI_INDEX + 4 * ram.u8(f + 0x1886))
    ai.press_command(ram, rec, ram.u16(row), ram.u32(index + 4 * ram.u16(row + 6)))
    raise Done


def _throw_follow_ups(c, rows: int) -> list[int]:
    """Up to six branch rows of the running throw that the CPU may continue with. A few slots are
    tied to banks: 0x3A7 never, 0xD41 (bank 4) and 0xDE2 (bank 0) with a 7-in-8 draw, 0xD24/0xD32
    (banks 0, 13) with a 1-in-8 draw, 0xD25/0xD34 never for banks 0 and 13."""
    ram, f, o = c.ram, c.f, c.o
    fighter, opp = ai.Fighter(ram, f), ai.Fighter(ram, o)
    bank = ram.s16(f + 0x16)
    found = []
    while ram.u16(rows) != ai.END:
        if ram.u16(rows) == ai.COMMON:
            base, n = ai.COMMON_ROWS + 12 * ram.u16(rows + 6), ram.u8(rows + 11)
        else:
            base, n = rows, 1
        for k in range(n):
            row = base + 12 * k
            if not ai.restriction_ok(fighter, opp, ram.u8(row + 2)):
                continue
            u = ai._lcg_next(ram) & 0x70
            slot = ram.s16(row + 6)
            ok = True
            if slot == 0x3A7:
                ok = False
            elif slot == 0xD41:
                ok = bank != 4 or u != 0
            elif slot in (0xD24, 0xD32):
                ok = u == 0 if bank in (0, 0xD) else True
            elif slot == 0xDE2:
                ok = not (bank == 0 and u != 0)
            elif slot in (0xD25, 0xD34):
                ok = bank not in (0, 0xD)
            if ok and (ram.u8(row + 3) == 0 or ai.branch_condition(ram, row, fighter, opp)):
                found.append(row)
                if len(found) > 5:
                    return found
        rows += 12
    return found


def _finish(c) -> tuple[int, int]:
    """LAB_80061154: timers, adaptive difficulty, guard memory and the pad output."""
    ram, rec, f, o = c.ram, c.rec, c.f, c.o
    state = ram.u32(rec + 0x224)
    target = ram.u32(rec + 0x5C)
    ram.put(rec + 0x3C, "H", int(state & 0x205 == 1))
    if target and ram.s16(rec + 0x48) < 0 and ram.u8(target + 0x19):
        ram.put(rec + 0x48, "H", ram.u8(target + 0x19))
    for off in (0x48, 0x38, 0x40, 0x54, 0x46, 0x44, 0x42, 0x8A, 0x8C):
        _dec(ram, rec + off)
    if ram.s16(rec + 0x1FE) == 0:
        ai.load_params(ram, rec, -1, -1, -1)
    _dec(ram, rec + 0x1FE)
    if ram.u32(ai.GAME_MODE) == 8:
        slot = ram.u16(rec)
        for base in (ai.FORCE_TARGETS, ai.FORCE_TARGETS + 8):
            v = ram.s32(base + 4 * slot)
            ram.put(base + 4 * slot, "i", v - 1 if v >= 0 else v)
    posture = state & 0xFFFF
    ram.put(rec + 0x212, "h", ram.s16(rec + 0x20C))
    guarding = posture in (ai.GUARD_HIGH, ai.GUARD_LOW)
    if ram.s16(rec + 0x3E) == 0:
        ram.put(rec + 0x3E, "h", int(guarding))
        ram.put(rec + 0x93, "B", 0)
    else:
        ram.put(rec + 0x3E, "h", int(guarding))
        if not guarding and ram.u8(rec + 0x93):
            ram.put(rec + 0x93, "B", 0)
    if ram.u8(f + 0xCE):                       # got hit
        ai.reset_approach(ram, rec)
        for off in (0xD8, 0xC0, 0x1A0, 0x98):
            ram.put(rec + off, "h", 0)
    if ram.u8(f + 0xD2) and ram.s32(rec + 0x18) < 3:
        ram.put(rec + 0x54, "h", 0x1E)
    if ram.u8(o + 0xD2) and ram.s32(rec + 0x14) < 2 and ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x258):
        ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 3)
    if ram.s32(f + 0x3F4) < ram.s32(rec + 0x30):
        _learn_from_damage(c)
    ram.put(rec + 0x30, "i", ram.s32(f + 0x3F4))
    if ram.u8(f + 0xCE) and ram.u32(ai.TEAM_OR_SURVIVAL) == 0:
        ram.put(rec + 0x40, "h", 0x28)
        ram.put(rec + 0x48, "h", -1)
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x38, "h", 0)
        _raise_capped(ram, rec + 0x254, 10, rec + 0x256)
        _raise_capped(ram, rec + 0x258, 10, rec + 0x25A)
        if ram.s16(rec + 0x216) > 0:
            _raise_capped(ram, rec + 0x262, 0x28, rec + 0x264)
            _raise_capped(ram, rec + 0x25E, 0x14, rec + 0x260)
    pad = ram.u16(rec + 4)
    pressed = pad & (pad ^ ram.u16(rec + 6))
    ram.put(rec + 6, "H", pad)
    return pad, pressed


def _raise_capped(ram: Ram, addr: int, step: int, cap: int) -> None:
    ram.put(addr, "h", (ram.s16(addr) + step + 0x8000) % 0x10000 - 0x8000)
    if ram.s16(cap) < ram.s16(addr):
        ram.put(addr, "h", ram.s16(cap))


def _learn_from_damage(c) -> None:
    """The CPU lost health: after a draw against word 35 (+0x27E), shorten the wait (+0x68) and, in
    one-on-one play, remember the opponent's move in an 8-entry history (+0x1DC). A move that is
    already in the history twice or more switches to level 9 for 600 frames (+0x1FE, +0x202)."""
    ram, rec, o = c.ram, c.rec, c.o
    if ai._lcg_next(ram) & 0xFFF < ram.s16(rec + 0x27E):
        return
    ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 3)
    move = ram.u32(o + 0x54)
    if ram.u32(ai.AI_MULTI):
        return
    ram.put(rec + 0x202, "h", 0)
    seen = sum(ram.u32(rec + 0x1DC + 4 * k) == move for k in range(8))
    if seen > 1:
        if ram.s16(rec + 0x1FE) < 1:
            ai.load_params(ram, rec, 0, 9, -1)
        ram.put(rec + 0x1FE, "h", 600)
        ram.put(rec + 0x202, "h", 1)
    k = ram.u16(rec + 0x1FC)
    ram.put(rec + 0x1DC + 4 * k, "I", move)
    ram.put(rec + 0x1FC, "H", (k + 1) & 7)
