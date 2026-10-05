#!/usr/bin/env python3
"""Integer ports of the CPU opponent (Japan Rev.1), working on guest memory like fight_sim.

`tools/research/verify_ai_sim.py` compares every routine with the game in the CPU harness.
The AI record of a CPU fighter is 0x330 bytes at 0x8009F6C0 + 0x330 * slot (docs: code/ai.md).
"""

from __future__ import annotations

from fight_sim import COMMON_ROWS, Fighter, Ram, branch_condition

AI_RECORDS = 0x8009F6C0
AI_RECORD_SIZE = 0x330
CANDIDATES = 0x8009FD20            # 12-byte entries: target move row, branch row, s16 mark
MAX_CANDIDATES = 180
AI_SELF = 0x800AFF24               # fighter being driven this frame
AI_OPP = 0x800A8B44                # its target
LCG = 0x800AE168                   # x = 5x + 3
END, COMMON = 0xC000, 0xC00C
# Branch conditions answered from the cached situation bits (record +0x64).
SITUATION_BITS = {0x24: 1, 0x25: 2, 0x26: 4, 0x30: 8, 0x27: 0x10}


def ai_self(ram: Ram) -> Fighter:
    return Fighter(ram, ram.u32(AI_SELF))


def ai_opp(ram: Ram) -> Fighter:
    return Fighter(ram, ram.u32(AI_OPP))


def restriction_ok(f: Fighter, opp: Fighter, value: int) -> bool:
    """Branch row restriction byte as the AI tests it (values above 0x73 never match)."""
    if value == 0:
        return True
    if value < 0x18:
        return f.bankType == value - 1
    if value < 0x2F:
        return f.bankType != value - 0x18
    if value < 0x46:
        return opp.bankType == value - 0x2F
    if value < 0x5D:
        return f.charId == value - 0x46
    if value > 0x73:
        return False
    return f.charId != value - 0x5D


def _rows(ram: Ram, rows: int):
    """Yield (row, is_common) for a branch list, expanding 0xC00C common rows; stops at the terminator."""
    while ram.u16(rows) != END:
        if ram.u16(rows) == COMMON:
            base = COMMON_ROWS + 12 * ram.u16(rows + 6)
            for k in range(ram.u8(rows + 11)):
                yield base + 12 * k, True
        else:
            yield rows, False
        rows += 12


def _terminator(ram: Ram, rows: int) -> int:
    while ram.u16(rows) != END:
        rows += 12
    return rows


def collect_candidates(ram: Ram, rec: int, current_only: int, stale: int | None = None) -> int:
    """AiCollectCandidates (0x80056A4C).

    Collects the branch rows of the running move (record +0x58) that are open now into the
    candidate table; with `current_only == 0` it also looks ahead into the default continuation.
    Two defects are reproduced (game-bugs.md): candidates whose target equals the uninitialised
    stack word `stale` are marked -1 like those with state bit 23 (None never matches), and in the
    look-ahead the condition of an ordinary row is tested on the row after the last common-row
    block (or on the list start). Returns the count.
    """
    f, opp = ai_self(ram), ai_opp(ram)
    index = ram.u32(rec + 0xC)
    sit = ram.u32(rec + 0x64)
    rows = ram.u32(ram.u32(rec + 0x58) + 0xC)
    count = 0

    def cond_ok(row: int, cond_row: int, lookahead: bool) -> bool:
        c = ram.u8(row + 3)
        if c == 0:
            return True
        if c in (0x24, 0x25):
            return bool(sit & SITUATION_BITS[c])
        if c in (0x26, 0x30, 0x27):
            return True if lookahead else bool(sit & SITUATION_BITS[c])
        return branch_condition(ram, cond_row, f, opp)

    def add(row: int) -> None:
        nonlocal count
        e = CANDIDATES + 12 * count
        ram.put(e, "I", ram.u32(index + 4 * ram.u16(row + 6)))
        ram.put(e + 4, "I", row)
        ram.put(e + 8, "h", 0)
        count += 1

    def open_now(row: int) -> bool:
        return ram.u8(row + 9) <= f.poseFrame <= ram.u8(row + 10) and restriction_ok(f, opp, ram.u8(row + 2))

    def open_lookahead(row: int) -> bool:
        return ram.u8(row + 9) < 2 and f.poseFrame <= ram.u8(row + 10) and restriction_ok(f, opp, ram.u8(row + 2))

    def walk(start: int, is_open, lookahead: bool) -> int:
        """Returns the row the walk stopped at (the terminator, or the row where the table filled)."""
        r = start
        cond_row = start
        while ram.u16(r) != END:
            if ram.u16(r) == COMMON:
                base = COMMON_ROWS + 12 * ram.u16(r + 6)
                for k in range(ram.u8(r + 11)):
                    row = base + 12 * k
                    cond_row = row
                    if is_open(row) and cond_ok(row, row, lookahead):
                        if count > MAX_CANDIDATES - 1:
                            return r
                        add(row)
                cond_row = base + 12 * ram.u8(r + 11)
            elif is_open(r) and cond_ok(r, cond_row if lookahead else r, lookahead):
                if count > MAX_CANDIDATES - 1:
                    return r
                add(r)
            r += 12
        return r

    stop = walk(rows, open_now, False)
    if current_only:
        return count
    nxt = ram.u32(index + 4 * ram.u16(stop + 6))
    if ram.u8(stop + 9) <= f.poseFrame <= ram.u8(stop + 10) and nxt != f.poseMove:
        walk(ram.u32(nxt + 0xC), open_lookahead, True)
    for k in range(count):
        e = CANDIDATES + 12 * k
        target = ram.u32(e)
        if ram.u32(target + 4) & 0x800000 or target == stale:
            ram.put(e + 8, "h", -1)
    if ram.u32(rec + 0x7C):
        ram.put(rec + 0x70, "h", count)
        run_filter(ram, rec)
    return count


FILTER_NO_LOWS = 0x800616B4        # filter installed by FUN_8005967C
BAND_REACH = 0x80098610            # u32 per distance band: accepted reach bits
SIDE_STEP, SIDE_STEP_ALT = 0xC001, 0xC002   # branch commands the AI treats as side steps
HINT_NEVER = 0x400000              # move row +0x08: never chosen by the AI
GUARD_HIGH, GUARD_LOW = 0x1052, 0x2829      # state words of the standing and crouching guard


def _lcg_next(ram: Ram) -> int:
    """Returns the old LCG value and advances it (x = 5x + 3)."""
    x = ram.u32(LCG)
    ram.put(LCG, "I", (5 * x + 3) & 0xFFFFFFFF)
    return x


def mark_candidates(ram: Ram, rec: int, pred) -> int:
    """The loop every filter shares: mark (1) each unmarked candidate that passes `pred(target, branch)`,
    add the number to the marked count (+0x72) and return it."""
    n = ram.s16(rec + 0x70)
    marked = 0
    for k in range(n):
        e = CANDIDATES + 12 * k
        if ram.s16(e + 8) == 0 and pred(ram.u32(e), ram.u32(e + 4)):
            ram.put(e + 8, "h", 1)
            marked += 1
    if n > 0:
        ram.put(rec + 0x72, "h", ram.s16(rec + 0x72) + marked)
    return marked


def reach_ok(ram: Ram, rec: int, target: int) -> bool:
    """The target's reach bits (none = close or middle) against the distance band's mask."""
    w = ram.u32(target + 8)
    reach = w & 0xFFFF0000
    if not w & 0x1C0000:
        reach |= 0xC0000
    return bool(reach & ram.u32(BAND_REACH + 4 * ram.u32(rec + 0x14)))


def _is_attack(ram: Ram, target: int) -> bool:
    """Common test: has an active window, no air window, not AI-excluded, state bit 17 clear."""
    return (ram.u8(target + 0x2D) != 0 and ram.u8(target + 0x19) == 0
            and not ram.u32(target + 8) & HINT_NEVER and not ram.u32(target + 4) & 0x20000)


def _grounded_or_special(ram: Ram, target: int) -> bool:
    return (ram.u8(target + 0x19) == 0 or bool(ram.u32(target + 4) & 0x80000)
            or bool(ram.u32(target + 8) & 0x200000))


def _attack_in_reach(ram: Ram, rec: int, target: int) -> bool:
    """Attack test shared by filters A-C: reach matches, or state bit 16 overrides it."""
    return (not ram.u32(target + 8) & HINT_NEVER and not ram.u32(target + 4) & 0x20000
            and (reach_ok(ram, rec, target) or bool(ram.u32(target + 4) & 0x10000)))


def filter_attacks(ram: Ram, rec: int) -> int:
    """FUN_8005758C: side steps (0xC001), state bit 19 moves, and attacks in reach."""
    def pred(t, br):
        if not _grounded_or_special(ram, t):
            return False
        if ram.u16(br) == SIDE_STEP or ram.u32(t + 4) & 0x80000:
            return True
        return ram.u8(t + 0x2D) != 0 and _attack_in_reach(ram, rec, t)
    return mark_candidates(ram, rec, pred)


def filter_attacks_no_special(ram: Ram, rec: int) -> int:
    """FUN_800576DC: attacks in reach except the attack words 0x412 and 0x706."""
    def pred(t, br):
        a = ram.u32(t + 8) & 0xFFFF
        return (_grounded_or_special(ram, t) and ram.u8(t + 0x2D) != 0 and a not in (0x412, 0x706)
                and _attack_in_reach(ram, rec, t))
    return mark_candidates(ram, rec, pred)


def filter_fast_attacks(ram: Ram, rec: int) -> int:
    """FUN_80057820: damaging ground attacks with startup below 14 frames."""
    def pred(t, br):
        return (ram.s16(t + 0x14) > 0 and ram.u8(t + 0x2D) != 0 and ram.u8(t + 0x19) == 0
                and ram.u8(t + 0x2D) < 14 and _attack_in_reach(ram, rec, t))
    return mark_candidates(ram, rec, pred)


def filter_vs_posture(ram: Ram, rec: int) -> int:
    """FUN_80057954: attacks in reach whose level suits the opponent's posture (+0x230)."""
    def pred(t, br):
        if not _is_attack(ram, t) or ram.s16(t + 0x14) < 0 or not reach_ok(ram, rec, t):
            return False
        g, a = ram.u32(rec + 0x230), ram.u32(t + 8) & 0xFFFF
        if g & 2:
            return a != 0x412
        if g & 1:
            return a not in (0x412, 0x10F)
        return not (g & 4 and a in (0x412, 0x217))
    return mark_candidates(ram, rec, pred)


def _level_vs_state(g: int, a: int) -> bool:
    """Attack level `a` against the opponent state `g` (filters E and F)."""
    if g & 0xFFFF == 0x4C02:
        return True
    if g & 0x400:
        return a in (0x412, 0x217, 0x31F)
    if g & 4:
        return a in (0x10F, 0x51F)
    if g & 1:
        return a in (0x217, 0x10F)
    if g & 2:
        return a in (0x10F, 0x217, 0x412)
    return False


def filter_punish_level(ram: Ram, rec: int) -> int:
    """FUN_80057AC4: attacks in reach whose level hits the opponent's current state."""
    def pred(t, br):
        return (_is_attack(ram, t) and reach_ok(ram, rec, t)
                and _level_vs_state(ram.u32(rec + 0x230), ram.u32(t + 8) & 0xFFFF))
    return mark_candidates(ram, rec, pred)


def filter_punish_level_no_high(ram: Ram, rec: int) -> int:
    """FUN_80057C88: as FUN_80057AC4 without the attack word 0x412."""
    def pred(t, br):
        a = ram.u32(t + 8) & 0xFFFF
        return (a != 0x412 and _is_attack(ram, t) and reach_ok(ram, rec, t)
                and _level_vs_state(ram.u32(rec + 0x230), a))
    return mark_candidates(ram, rec, pred)


def filter_plain_attacks(ram: Ram, rec: int) -> int:
    """FUN_80057E48: attacks in reach from branch rows without command bits 5-13 (plain buttons)."""
    def pred(t, br):
        return (_is_attack(ram, t) and not ram.u16(br) & 0x3FE0 and ram.s16(t + 0x14) >= 0
                and reach_ok(ram, rec, t))
    return mark_candidates(ram, rec, pred)


def filter_quick_attacks(ram: Ram, rec: int) -> int:
    """FUN_80058040: damaging attacks in reach faster than record +0x20A (air ones only with bit 19)."""
    def pred(t, br):
        s = ram.u32(t + 4)
        return (not ram.u32(t + 8) & HINT_NEVER and ram.s16(t + 0x14) > 0 and ram.u8(t + 0x2D) != 0
                and (ram.u8(t + 0x19) == 0 or bool(s & 0x80000))
                and ram.u8(t + 0x2D) < ram.s16(rec + 0x20A) and not s & 0x20000 and reach_ok(ram, rec, t))
    return mark_candidates(ram, rec, pred)


def filter_quick_attacks_no_high(ram: Ram, rec: int) -> int:
    """FUN_8005817C: damaging attacks in reach faster than +0x20A, except the attack word 0x412."""
    def pred(t, br):
        w = ram.u32(t + 8)
        return (not w & HINT_NEVER and ram.s16(t + 0x14) > 0 and ram.u8(t + 0x2D) != 0
                and ram.u8(t + 0x2D) < ram.s16(rec + 0x20A) and w & 0xFFFF != 0x412
                and not ram.u32(t + 4) & 0x20000 and reach_ok(ram, rec, t))
    return mark_candidates(ram, rec, pred)


def _branch_is(ram: Ram, cmd: int):
    return lambda t, br: ram.u16(br) == cmd


def filter_side_steps_then_quick(ram: Ram, rec: int) -> int:
    """FUN_80058AC0: in band 2 (32/4096) or band 3 (1024/4096) mark side steps (0xC001), then run
    FUN_8005817C when the opponent stands (+0x230 bit 0), else FUN_80058040."""
    band = ram.u32(rec + 0x14)
    r = _lcg_next(ram) >> 1 & 0xFFF
    count = 0
    if (band == 2 and r < 0x20) or (band == 3 and r < 0x400):
        count = mark_candidates(ram, rec, _branch_is(ram, SIDE_STEP))
    if ram.u32(rec + 0x230) & 1:
        return count + filter_quick_attacks_no_high(ram, rec)
    return count + filter_quick_attacks(ram, rec)


def filter_defence(ram: Ram, rec: int) -> int:
    """FUN_800582A0: guard and evasion candidates against the opponent's attack word (+0x234).

    The return value of the last block replaces, not adds to, the earlier count (only the count
    of the final side-step pass is returned when it runs)."""
    if ram.s32(rec + 0x1C) > 0xB86:
        return 0
    attack = ram.u32(rec + 0x234)

    def neutral(t, br):
        return ram.u32(t + 4) & 1 == 1 and ram.u8(t + 0x2D) == 0

    def guard(*states, low_bit_clear=False):
        def pred(t, br):
            s = ram.u32(t + 4)
            if ram.u16(br) == SIDE_STEP_ALT or (low_bit_clear and s & 0x100):
                return False
            return s & 0xFFFF in states
        return pred

    def side_steps_if_closing() -> int:
        if ram.s32(rec + 0x18) < 3:
            return 0
        return mark_candidates(ram, rec, _branch_is(ram, SIDE_STEP_ALT))

    if ram.s16(rec + 0x214):
        count = mark_candidates(ram, rec, neutral) if attack != 0x217 else 0
        return count + side_steps_if_closing()
    count = 0
    if ram.s16(rec + 0x20C):
        if attack == 0x31F:
            count = mark_candidates(ram, rec, guard(GUARD_HIGH, GUARD_LOW, low_bit_clear=True))
        elif attack == 0x217:
            count = mark_candidates(ram, rec, guard(GUARD_HIGH))
        elif attack == 0x10F:
            count = mark_candidates(ram, rec, lambda t, br: ram.u32(t + 4) & 0xFFFF == GUARD_LOW)
            count += side_steps_if_closing()
        elif attack == 0x412:
            if ram.u16(ram.u32(AI_SELF) + 0x60) in (0x2021, GUARD_LOW):
                count = mark_candidates(ram, rec, neutral)
            else:
                count = mark_candidates(ram, rec, guard(GUARD_HIGH))
                r = _lcg_next(ram) & 0xFFF
                if r % 50 == 0:
                    count += mark_candidates(ram, rec, neutral)
                count += side_steps_if_closing()
        elif attack == 0x706:
            count = mark_candidates(ram, rec, neutral)
            count += side_steps_if_closing()
    if ram.s32(rec + 0x24) < -0x46 and ram.s32(rec + 0x18) < 3:
        count = mark_candidates(ram, rec, _branch_is(ram, SIDE_STEP_ALT))
    return count


def filter_no_lows(ram: Ram, rec: int) -> int:
    """FUN_800616B4: unmark candidates with AI hint bit 0 or the low attack word 0x10F."""
    removed = 0
    for k in range(ram.s16(rec + 0x70)):
        e = CANDIDATES + 12 * k
        mark = ram.s16(e + 8)
        if mark >= 0:
            word = ram.u32(ram.u32(e) + 8)
            if word & 0x10000 or word & 0xFFFF == 0x10F:
                if mark > 0:
                    removed += 1
                ram.put(e + 8, "h", -1)
    ram.put(rec + 0x72, "h", ram.s16(rec + 0x72) - removed)
    return removed


def run_filter(ram: Ram, rec: int) -> None:
    callback = ram.u32(rec + 0x7C)
    if callback == FILTER_NO_LOWS:
        filter_no_lows(ram, rec)
    elif callback:                     # unreachable: FUN_8005967C installs the only filter
        raise NotImplementedError(f"AI candidate filter {callback:#x}")


def hint_never_open(ram: Ram, rec: int) -> int:
    """FUN_80057300: 1 when a branch of the running move (fighter poseMove) that is open now leads
    to a move with the AI hint "never chosen" (such moves are reserved for the hooks)."""
    f, opp = ai_self(ram), ai_opp(ram)
    index = ram.u32(rec + 0xC)
    sit = ram.u32(rec + 0x64)
    for row, _ in _rows(ram, ram.u32(f.poseMove + 0xC)):
        if (ram.u8(row + 9) <= f.poseFrame <= ram.u8(row + 10) and restriction_ok(f, opp, ram.u8(row + 2))
                and _cond_ok(ram, row, f, opp, sit)
                and ram.u32(ram.u32(index + 4 * ram.u16(row + 6)) + 8) & HINT_NEVER):
            return 1
    return 0


def _cond_ok(ram: Ram, row: int, f: Fighter, opp: Fighter, sit: int) -> bool:
    c = ram.u8(row + 3)
    if c == 0:
        return True
    if c in SITUATION_BITS:
        return bool(sit & SITUATION_BITS[c])
    return branch_condition(ram, row, f, opp)


# --- random numbers -------------------------------------------------------------------------

RAND_STATE = 0x800A3E80            # libc rand(): x = x * 0x41C64E6D + 0x3039, returns bits 16-30


def rand(ram: Ram) -> int:
    x = (ram.u32(RAND_STATE) * 0x41C64E6D + 0x3039) & 0xFFFFFFFF
    ram.put(RAND_STATE, "I", x)
    return x >> 16 & 0x7FFF


def random_below(ram: Ram, n: int) -> int:
    """FUN_800569D0 and the pick in AiExecuteCandidate: n * ((rand() + LCG) & 0x7FFF) >> 15."""
    r = rand(ram)
    x = _lcg_next(ram)
    p = n * ((r + x) & 0x7FFF)
    if p < 0:                          # unreachable for the positive counts the game passes
        p += 0x7FFF
    return p >> 15


# --- pad input --------------------------------------------------------------------------------

NUMPAD_PAD = 0x80023288            # u16 pad bits per numpad direction 0-9
DIRECTION_MASKS = 0x800232A8       # u16 per numpad direction 1-9: command direction bits (bits 5-13)
DIRECTION_PAD = 0x800232BC         # u16 pad bits per direction 0-9 for plain commands
BUTTON_PAD = 0x800232D0            # u16 pad bits for command bits 0-3
SIDE_STEP_SCRIPTS = 0x800232DA     # two 12-step scripts (u16 steps)
SEQ_C001, SEQ_C002 = 0x8001006C, 0x80010078
INPUT_SEQ_A, INPUT_SEQ_B = 0x800958F4, 0x800959F0
IDLE_SCRIPT = 0x80022EB2           # FUN_8005968C


def pad_from_step(ram: Ram, step: int) -> int:
    """AiPadFromStep (0x80061AC4): numpad direction in bits 0-3, buttons in bits 8-11."""
    pad = 0x80 if step & 0x100 else 0
    if step & 0x200:
        pad |= 0x10
    if step & 0x400:
        pad |= 0x40
    if step & 0x800:
        pad |= 0x20
    return pad | ram.u16(NUMPAD_PAD + 2 * (step & 0xF))


def start_script(ram: Ram, rec: int, script: int) -> None:
    """AiStartScript (0x80061B24): press the first step now; +0x08 points at the rest (0 when none)."""
    ram.put(rec + 8, "I", script + 2 if ram.u16(script + 2) else 0)
    ram.put(rec + 4, "H", pad_from_step(ram, ram.u16(script)))


def input_sequence(ram: Ram, cmd: int) -> int:
    """FUN_8002CFD0: the step list of a motion command (0 when it has none)."""
    if cmd < 0xC00E:
        return {0xC001: SEQ_C001, 0xC002: SEQ_C002}.get(cmd, 0)
    if cmd < 0xC7FF:
        return ram.u32(INPUT_SEQ_A + 4 * (cmd - 0xC00E)) if cmd - 0xC00E < 0x3F else 0
    return ram.u32(INPUT_SEQ_B + 4 * (cmd - 0xC7FF)) if cmd - 0xC7FF < 0x29 else 0


def press_command(ram: Ram, rec: int, cmd: int, target: int) -> int:
    """AiPressCommand (0x80061BA8): turn a branch command into pad input and remember the target
    move (+0x5C). Returns the pad word, -1 for a motion script, 0 when the command has no script."""
    cmd &= 0xFFFF
    if not cmd & 0xC000:
        d = 9
        while d > 0 and not ram.u16(DIRECTION_MASKS + 2 * d) & (cmd >> 5) & 0x1FF:
            d -= 1
        buttons = 0
        for k in range(4):
            if cmd >> k & 1:
                buttons |= ram.u16(BUTTON_PAD + 2 * k)
        ram.put(rec + 4, "H", ram.u16(DIRECTION_PAD + 2 * d) | buttons)
        result = ram.u16(rec + 4)
    else:
        seq = input_sequence(ram, cmd)
        if seq == 0 or cmd & 0xC000 != 0xC000:
            return 0
        step = ram.u16(seq + 2)
        ram.put(rec + 8, "I", seq + 4 if ram.u16(seq + 4) else 0)
        ram.put(rec + 4, "H", pad_from_step(ram, step))
        result = 0xFFFFFFFF
    ram.put(rec + 0x5C, "I", target)
    return result


def reset_approach(ram: Ram, rec: int) -> None:
    """FUN_80056A30: restart the approach timers (+0x38, +0x3A, +0x40 = 40, +0x48 = -1)."""
    ram.put(rec + 0x40, "h", 0x28)
    ram.put(rec + 0x3A, "h", 0)
    ram.put(rec + 0x38, "h", 0)
    ram.put(rec + 0x48, "h", -1)


def side_step(ram: Ram, rec: int, side: int) -> None:
    """AiSideStep (0x80061D40). `side` -1 chooses from the heading difference (+0x3C; random when
    nearly straight or reversed) and the fighters' order on screen (+0x1278)."""
    if side == -1:
        f, opp = ram.u32(AI_SELF), ram.u32(AI_OPP)
        h = ram.u16(f + 0x3C)
        side = 0
        if (h - 0x101) & 0xFFFFFFFF > 0x7EFE:
            side = 1
            if (h + 0x7FFF) & 0xFFFF > 0x7EFD:
                side = rand(ram) >> 4 & 1
        if ram.s16(opp + 0x1278) < ram.s16(f + 0x1278):
            side = 1 - side
    script = SIDE_STEP_SCRIPTS + 24 * side
    first = ram.u16(script)
    ram.put(rec + 8, "I", script + 2 if ram.u16(script + 2) else 0)
    ram.put(rec + 4, "H", pad_from_step(ram, first))
    reset_approach(ram, rec)


# --- executing a candidate --------------------------------------------------------------------

AI_INDEX = 0x8009F690              # u32 per AI slot: the move index of that CPU's bank
GAME_MODE = 0x800AFF50
FORCE_TARGETS = 0x8009F6A8         # Tekken Force (mode 8): s32 per enemy, AI record +0x32C words


def after_attack(ram: Ram, rec: int, branch: int) -> None:
    """AiAfterAttack (0x80058C40): count forced "never chosen" moves (+0x96) and, for an attack,
    set a random recovery wait (+0x68 = word 1 + one of words 2-5) and reset the approach timers."""
    self_ = ram.u32(AI_SELF)
    index = ram.u32(AI_INDEX + 4 * ram.u8(self_ + 0x1886))
    target = ram.u32(index + 4 * ram.u16(branch + 6))
    if ram.u32(target + 8) & HINT_NEVER:
        ram.put(rec + 0x96, "h", ram.s16(rec + 0x96) + 1)
    if ram.u8(target + 0x2D) == 0:
        return
    u = _lcg_next(ram) & 3
    ram.put(rec + 0x68, "h", ram.s16(rec + 0x23C) + ram.s16(rec + 0x23E + 2 * u))
    if ram.u32(GAME_MODE) == 8:
        i = 2 - ram.u8(self_ + 0x1E)
        words = ram.u32(rec + 0x32C)
        ram.put(FORCE_TARGETS + 4 * i, "i", ram.s16(words))
        if ram.s32(FORCE_TARGETS + 8 + 4 * i) < 0:
            ram.put(FORCE_TARGETS + 8 + 4 * i, "i", ram.s16(words + 2))
    ram.put(rec + 0x44, "h", -1)
    if ram.s16(rec + 0x46) > 0:
        ram.put(rec + 0x46, "h", -1)
    ram.put(rec + 0x3A, "h", 0)
    ram.put(rec + 0x38, "h", 0)
    ram.put(rec + 0x40, "h", 0x28)
    ram.put(rec + 0x48, "h", -1)


def execute_candidate(ram: Ram, rec: int) -> int:
    """AiExecuteCandidate (0x80058D6C): pick the k-th marked candidate (k random below +0x72) and
    press it. Record +0x02 bit 0 walks the table forwards; then k <= 0 stops (game-bugs.md: the first
    marked candidate is twice as likely and the last one is never chosen). Backwards is uniform.
    Returns the table index, or -1."""
    m = ram.s16(rec + 0x72)
    if m <= 0:
        return -1
    k = random_below(ram, m)
    n = ram.s16(rec + 0x70)
    if ram.u16(rec + 2) & 1:
        pick = n - 1
        for i in range(n):
            if ram.s16(CANDIDATES + 12 * i + 8) > 0:
                k -= 1
                if k <= 0:
                    pick = i
                    break
        if n <= 0:
            pick = -1
    else:
        pick = n
        for i in range(n - 1, -1, -1):
            if ram.s16(CANDIDATES + 12 * i + 8) > 0:
                k -= 1
                if k < 0:
                    pick = i
                    break
        else:
            pick = 0 if n > 0 else n
    if pick < 0:
        return -1
    e = CANDIDATES + 12 * pick
    press_command(ram, rec, ram.u16(ram.u32(e + 4)), ram.u32(e))
    after_attack(ram, rec, ram.u32(e + 4))
    return pick


def branch_open_to(ram: Ram, rec: int, slot: int) -> int:
    """FUN_80058ED0: 1 when a branch of the running move to `slot` is open now or, failing that, opens
    on frame 1 of the default continuation. The continuation is read from the row after the last
    walked row, which is not the terminator when the list ends with a common-row block (game-bugs.md)."""
    f, opp = ai_self(ram), ai_opp(ram)
    sit = ram.u32(rec + 0x64)
    slot &= 0xFFFF

    def open_row(row: int, first_frame_one: bool) -> bool:
        if ram.u16(row + 6) != slot or (first_frame_one and ram.u8(row + 9) != 1):
            return False
        return (ram.u8(row + 9) <= f.poseFrame <= ram.u8(row + 10)
                and restriction_ok(f, opp, ram.u8(row + 2)) and _cond_ok(ram, row, f, opp, sit))

    def walk(rows: int, first_frame_one: bool):
        """Returns (found, row after the last walked row)."""
        after = rows
        while ram.u16(rows) != END:
            if ram.u16(rows) == COMMON:
                base, n = COMMON_ROWS + 12 * ram.u16(rows + 6), ram.u8(rows + 11)
            else:
                base, n = rows, 1
            after = base
            for k in range(n):
                if open_row(base + 12 * k, first_frame_one):
                    return True, after
                after = base + 12 * (k + 1)
            rows += 12
        return False, after

    found, after = walk(ram.u32(f.poseMove + 0xC), False)
    if found:
        return 1
    index = ram.u32(AI_INDEX + 4 * ram.u8(f.base + 0x1886))
    nxt = ram.u32(index + 4 * ram.u16(after + 6))
    if nxt == f.poseMove or not ram.u8(after + 9) <= f.poseFrame <= ram.u8(after + 10):
        return 0
    return int(walk(ram.u32(nxt + 0xC), True)[0])


def whiff_punish_ok(ram: Ram, rec: int, move: int) -> int:
    """FUN_800593D4 (reached only from the dead branches of AiUpdate): two draws (word 35 at +0x27E,
    then 31/32), then the distance band, the opponent's posture or the record's +0x2E decide."""
    x = _lcg_next(ram)
    if x & 0xFFF < ram.s16(rec + 0x27E):
        return 0
    x2 = _lcg_next(ram)
    if not x2 & 0x1F:
        return 0
    band = ram.s32(rec + 0x14)
    if band < 2 and ram.s16(rec + 0x54) >= 0:
        return 1
    if band >= 4:
        return 1
    if (ram.u32(rec + 0x230) & 4 and ram.u8(ram.u32(AI_OPP) + 0xDB) == 0 and not ram.u32(move + 8) & 0x10000
            and ram.u16(move + 4) not in (0x10F, 0x51F)):
        return 1
    return int(ram.s16(rec + 0x2E) > 0x3800)


# --- character hooks --------------------------------------------------------------------------
# Hooks return a pad word to press, -1 (nothing), -2 (input already set, e.g. a script) or -3
# (execute a marked candidate). Fighter offsets: +0x16 bank type, +0x30/+0x2E/+0x3C/+0x3E angles,
# +0x32 and +0x40 state counters, +0x54 move row, +0x58 frame, +0xA0 move slot, +0x1278 screen order.

HOOK_TABLE = 0x800233A0            # 10 x (u16 bank, pad, u32 hook for the opponent's bank, u32 own)
KING_THROWS, KING_VS_CROUCH, KING_CLOSE = 0x8002334A, 0x8002332E, 0x80023312   # 14-byte scripts
OGRE_ESCAPES = 0x80023308          # u16 x 4: pads Ogre-fighters use against the fire breath


def hook_for_bank(ram: Ram, own: int, bank: int) -> int:
    """AiHookForBank (0x80062B50): hook A (for the opponent's bank, own == 1) or B (own == 0)."""
    for k in range(10):
        e = HOOK_TABLE + 12 * k
        if ram.u16(e) == bank & 0xFFFFFFFF:
            return ram.u32(e + 8 if own == 0 else e + 4)
    return 0


def install_no_lows(ram: Ram, rec: int) -> None:
    """FUN_8005967C."""
    ram.put(rec + 0x7C, "I", FILTER_NO_LOWS)


def _fighters(ram: Ram):
    return ram.u32(AI_SELF), ram.u32(AI_OPP)


def hook_vs_paul(ram: Ram, rec: int) -> int:
    _, opp = _fighters(ram)
    move = ram.s16(opp + 0xA0)
    if move == 0x2C7 and ram.s32(rec + 0x18) < 3:
        if ram.s16(opp + 0x58) > 15:
            return 0x8000
        ram.put(rec + 0x68, "h", -1)
    return -1


def hook_vs_gon(ram: Ram, rec: int) -> int:
    _, opp = _fighters(ram)
    if ram.s16(opp + 0xA0) != 0x137:
        return -1
    if ram.s32(rec + 0x18) < 2:
        ram.put(rec + 0x68, "h", -1)
        return -2
    return -1 if ram.s32(rec + 0x18) < 4 else 0x8000


def hook_as_hwoarang(ram: Ram, rec: int) -> int:
    """Reacts to its own slot 0xDE3, which no bank defines (game-bugs.md #11)."""
    self_, _ = _fighters(ram)
    if ram.s16(self_ + 0xA0) != 0xDE3:
        return -1
    if (ram.u16(self_ + 0x58) - 0xD) & 0xFFFFFFFF > 4 or ram.s16(rec + 0x20A) > 9:
        return -1 if rand(ram) & 0xF == 0 else 0x2000
    return -1


def hook_vs_yoshimitsu(ram: Ram, rec: int) -> int:
    self_, opp = _fighters(ram)
    frame, move = ram.s16(opp + 0x58), ram.s16(opp + 0xA0)
    band, closing = ram.s32(rec + 0x14), ram.s32(rec + 0x18)
    pm = ram.u32(opp + 0x54)
    if move == 0x16F:
        if closing < 3:
            ram.put(rec + 0x68, "h", -1)
        return -1
    if move == 0x456:
        if closing > 2:
            return 0x2000
        ram.put(rec + 0x8C, "h", 4)
        install_no_lows(ram, rec)
        ram.put(rec + 0x68, "h", -1)
        return -1
    if (ram.u16(opp + 0xA0) - 0x459) & 0xFFFFFFFF > 2:
        if move == 0x472:
            return -1
        if move not in (0x16A, 0x43A):
            if move not in (0x458, 0x49C, 0x49D, 0x49E):
                return -1
            if ram.s16(self_ + 0x3E) > 0x3FFF:
                if band < 2:
                    ram.put(rec + 0x68, "h", -1)
                return -1
            if band < 2:
                ram.put(rec + 0x68, "h", 1)
                return 0
            if band < 3:
                install_no_lows(ram, rec)
                ram.put(rec + 0x68, "h", -1)
                return -1
            return 0x2000
        if ram.u8(pm + 0x2D) == 0 or frame <= ram.u8(pm + 0x2E):
            if ram.s16(self_ + 0x3E) > 0x1000:
                return -1 if closing < 2 else 0x2000
            if closing > 2 and ram.u32(rec + 0x1C) < 0xA8D:
                start_script(ram, rec, IDLE_SCRIPT)
                return -2
            if closing < 2 and ram.s16(rec + 0x20A) > 10:
                return -1
            if closing < 3 and ram.s16(rec + 0x20A) > 10:
                side_step(ram, rec, rand(ram) & 1)
                return -2
        else:
            ram.put(rec + 0x68, "h", -1)
        return 0
    # the opponent's slots 0x459-0x45B
    if band < 1:
        if ram.u8(pm + 0x2D) <= frame <= ram.u8(pm + 0x2E):
            return 0
        install_no_lows(ram, rec)
        ram.put(rec + 0x68, "h", -1)
        ram.put(rec + 0x8C, "h", 4)
        return -2
    if (ram.u16(opp + 0x30) - 0x2000) & 0xFFFFFFFF < 0x4001:
        ram.put(rec + 0x8C, "h", 0x14)
        if band < 2:
            install_no_lows(ram, rec)
            ram.put(rec + 0x68, "h", -1)
            return -1
        limit = 1
    else:
        if band < 3:
            if rand(ram) & 7:
                return 0
            if ram.u32(rec + 0x224) & 0x400001:
                return 0
            side_step(ram, rec, -1)
            return -2
        ram.put(rec + 0x8C, "h", 10)
        limit = 2
    return 0x2000 if band > limit else -1


def _ogre_side(ram: Ram, rec: int) -> int:
    """Inlined in AiHookVsOgre: pick a side from the heading (+0x3C) unless the CPU's own move has
    state bit 22, the fighters are 7,001+ apart or the heading is ambiguous; side-steps at once."""
    self_, opp = _fighters(ram)
    if ram.u32(ram.u32(self_ + 0x54) + 4) & 0x400000 or ram.u32(rec + 0x1C) >= 0x1B59:
        return -1
    h = ram.u16(self_ + 0x3C)
    if (h - 0x101) & 0xFFFFFFFF < 0x7EFF:
        side = 0
    elif (h + 0x7FFF) & 0xFFFF < 0x7EFE:
        side = 1
    else:
        return -1
    if ram.s16(opp + 0x1278) < ram.s16(self_ + 0x1278):
        side = 1 - side
    side_step(ram, rec, side)
    return side


def hook_vs_ogre(ram: Ram, rec: int) -> int:
    """Against Ogre's fire breath (slot 0x16E); the 0xDE4 branch is dead (game-bugs.md #11).
    A chosen side step is started twice (the second call repeats the first)."""
    self_, opp = _fighters(ram)
    pm, frame = ram.u32(opp + 0x54), ram.s16(opp + 0x58)
    band = ram.s32(rec + 0x14)
    move = ram.s16(opp + 0xA0)

    def give_up() -> int:              # LAB_800626F0
        ram.put(rec + 0x68, "h", -1)
        return 0x2000

    def step_twice(side: int) -> int:  # LAB_80062740
        side_step(ram, rec, side)
        return -2

    if move == 0xDE4:
        ram.put(rec + 0x8C, "h", 8)
        if (frame - 9) & 0xFFFFFFFF < 5 and band < 2 and rand(ram) & 0x1F == 0:
            install_no_lows(ram, rec)
            return give_up()
        if frame < ram.u8(pm + 0x2D) - 0x1E:
            if band <= 1:
                return give_up()
            if band < 3:
                ram.put(rec + 0x68, "h", ram.s16(rec + 0x68) - 4)
                return 0x2000
            side = _ogre_side(ram, rec)
            return 0x2000 if side == -1 else step_twice(side)
        if frame < ram.u8(pm + 0x2D) - 0x14:
            if ram.s16(self_ + 0x30) > 0x37FF:
                if band < 3:
                    return 0x2000
                side = _ogre_side(ram, rec)
                return 0x2000 if side == -1 else step_twice(side)
            if band < 3:
                return 0
            if band < 4:
                return 0x2000
        elif frame < ram.u8(pm + 0x2E):
            if ram.s16(self_ + 0x30) > 0x5FFF:
                ram.put(rec + 0x68, "h", 8)
                return 0x8000
            if ram.s16(self_ + 0x30) > 0x37FF:
                if band > 1:
                    return 0x2000
                ram.put(rec + 0x68, "h", 8)
                return 0
            side = _ogre_side(ram, rec)
            if side != -1:
                return step_twice(side)
            return 0x2000 if ram.s16(self_ + 0x32) == 0 else 0
        elif frame < ram.u8(pm + 0x2E) + 0x28:
            if band < 2:
                return give_up()
        elif band < 3:
            return give_up()
    elif move == 0x16E:
        ram.put(rec + 0x8C, "h", 8)
        if frame < ram.u8(pm + 0x2D) - 8:
            side = -1
            if ((ram.u16(self_ + 0x2E) + 0x2000) & 0xFFFF < 0x4001
                    and not ram.u32(ram.u32(self_ + 0x54) + 4) & 0x400000 and ram.u32(rec + 0x1C) < 0x1B59):
                side = int(ram.s16(self_ + 0x1278) < ram.s16(opp + 0x1278))
            if band < 1:
                return give_up()
            if band < 3:
                return 0x2000
            if rand(ram) & 7 == 0 and ram.s16(self_ + 0x32) == 0 and side != -1:
                return step_twice(side)
        else:
            if ram.u8(pm + 0x2E) <= frame:
                return -1
            if ram.s16(self_ + 0x32) == 0:
                return 0x6000 if ram.s32(rec + 0x1C) < 0x1B59 else 0
            if band < 2:
                return ram.u16(OGRE_ESCAPES + 2 * (rand(ram) & 3))
            if band < 3:
                return 0x6000
    else:
        return -1
    return 0x2000 if rand(ram) & 7 == 0 else 0


def hook_as_king(ram: Ram, rec: int) -> int:
    """King's command throws (slot 0x15 open) and the scripts against crouching opponents."""
    self_, opp = _fighters(ram)
    u = _lcg_next(ram) & 0xFFF
    if ram.s16(rec + 0x68) > 0 or u >= ram.s16(rec + 0x24E):
        return -1
    band = ram.s32(rec + 0x14)
    own_move = ram.u32(self_ + 0x54)
    if (ram.s16(opp + 0x16) != 0x13 and ram.u32(rec + 0x230) & 2 and band < 3
            and ram.u8(opp + 0xDB) == 0 and ram.u8(opp + 0xDF) == 0 and ram.u8(own_move + 0x2D) == 0
            and ram.s16(rec + 0x20A) > 8 and ram.s16(self_ + 0x32) == 0 and ram.s16(self_ + 0x40) == 0
            and rand(ram) & 7 == 0 and branch_open_to(ram, rec, 0x15)):
        start_script(ram, rec, KING_THROWS + (rand(ram) & 0xFFF) % 3 * 14)
        ram.put(rec + 0xD8, "h", 1)
        return -2
    if (ram.u32(rec + 0x230) & 1 and band <= 1 and ram.u8(opp + 0xDF) == 0 and ram.u8(own_move + 0x2D) == 0
            and ram.s16(rec + 0x20A) >= 9 and ram.s16(self_ + 0x32) == 0 and ram.s16(self_ + 0x40) == 0
            and hint_never_open(ram, rec)):
        script = KING_VS_CROUCH
    else:
        if (ram.s16(rec + 0x208) == 0 or band > 1 or ram.s16(self_ + 0x40) not in (0, 2)
                or ram.s16(self_ + 0x32) or ram.u8(opp + 0xDF) or ram.u8(own_move + 0x2D)
                or ram.s16(rec + 0x20A) < 9 or ram.s16(rec + 0x88) or not hint_never_open(ram, rec)):
            return -1
        script = KING_CLOSE
    start_script(ram, rec, script + (rand(ram) & 1) * 14)
    return -2


def _minus_one(ram: Ram, rec: int) -> int:
    return -1


HOOKS = {
    0x80062BAC: hook_vs_paul, 0x80062804: hook_as_king, 0x80061E70: hook_vs_yoshimitsu,
    0x80062C7C: _minus_one, 0x80062C84: hook_as_hwoarang, 0x80062C10: _minus_one,
    0x80062C18: _minus_one, 0x80062C20: _minus_one, 0x800621D8: hook_vs_ogre, 0x80062C28: hook_vs_gon,
}


def call_hook(ram: Ram, own: int, rec: int) -> int:
    """AiCallHook (0x800594C4): with no script pending (+0x8A < 0) and a draw below word 29
    (+0x272), run hook +0x74 (own == 0, the opponent's bank) or +0x78 (the CPU's bank).
    Returns 1 when the hook produced input."""
    if ram.s16(rec + 0x8A) >= 0:
        return 0
    x = _lcg_next(ram)
    if ram.s16(rec + 0x272) <= x & 0xFFF:
        return 0
    hook = ram.u32(rec + (0x74 if own == 0 else 0x78))
    if hook == 0:
        return 0
    r = HOOKS[hook](ram, rec)
    if r == -2:
        return 1
    if r == -3:                        # no shipped hook returns -3
        return int(ram.s16(rec + 0x72) > 0 and execute_candidate(ram, rec) >= 0)
    if r == -1:
        return 0
    if r in (0x2000, 0x8000):
        ram.put(rec + 0x38, "h", 0x10)
        ram.put(rec + 0x3A, "h", 0)
        ram.put(rec + 0x40, "h", 0x38)
    ram.put(rec + 4, "H", r & 0xFFFF)
    return 1


# --- reset and parameters ---------------------------------------------------------------------

AI_PARAMS = 0x80023418             # 3 difficulty groups x 10 levels x 110 bytes
COMMON_PARAMS = 0x8002408E         # 110 bytes copied to record +0x2A6
BAND_TABLE = 0x80098640            # 12 bytes per fighter +0x18 value: distance-band thresholds
FORCE_WORDS = 0x80023210           # mode 8: 6-byte entries per group (0x1E apart) and level
DIFFICULTY, CPU_LEVEL = 0x800AE6D0, 0x800AE6D9
TEAM_OR_SURVIVAL = 0x800AE39C      # the attract flag (set at boot and by the transition screen, cleared by
                                   # every mode start but the demonstration's): CPUs at level 4, halved waits
AI_MULTI = 0x8009F6A4              # 1 in the demonstration fight and Tekken Force
FORCE_LAYOUT = 0x800AE3D8
FIGHTER_BASE, FIGHTER_STRIDE = 0x800A96F0, 0x188C
BANKS = 0x800AE0E8                 # bank pointer per player

# AiReset: (record offset, size, value) initialisations in code order; None = fighter +0x3F4.
RESET_FIELDS = [
    (0x34, 2, -1), (0x36, 2, 0), (0x3C, 2, 0), (0x4A, 2, -1), (0x4C, 2, 0), (0x8A, 2, -1), (0x48, 2, -1),
    (0x38, 2, -1), (0x3A, 2, 0), (0x58, 4, 0), (0xA0, 4, 0), (0x54, 2, -1), (0x3E, 2, 0), (0x46, 2, -1),
    (0x44, 2, -1), (0x4E, 2, -1), (0x2C, 2, 0), (0x2A, 2, 0), (0x42, 2, -1), (0x60, 4, 0), (0x8C, 2, -1),
    (0x1FE, 2, -1), (0x6C, 2, -1), (0x6A, 2, 0), (0x72, 2, 0), (0x70, 2, 0), (0xC0, 2, 0), (0xC2, 2, 0),
    (0x30, 4, None), (0xD4, 2, 0), (0xD8, 2, 0), (0xDA, 2, 0), (0x19C, 2, 0), (0x1CC, 2, 0), (0x1A0, 2, 0),
    (0x1A2, 2, 0), (0x1CE, 2, 0), (0x1D2, 2, 0), (0x96, 2, 0), (0x98, 2, 0), (0x9C, 2, -1), (0xBC, 4, 0),
    (0x6E, 2, 0), (0x08, 4, 0), (0x216, 2, -1), (0x1FC, 2, 0),
]


def load_params(ram: Ram, rec: int, group: int, level: int, disabled: int) -> None:
    """AiLoadParams (0x80061770)."""
    if group < 1:
        group = ram.u16(DIFFICULTY)
    if level < 1:
        level = ram.u8(CPU_LEVEL)
    ram.put(rec + 0x21E, "H", disabled & 0xFFFF)
    if ram.u32(TEAM_OR_SURVIVAL):
        level = 4
    group = min(group & 0xFFFFFFFF, 2)
    level = min(level & 0xFFFFFFFF, 9)
    src = AI_PARAMS + 0x44C * group + 0x6E * level
    ram.data[(rec + 0x238) & 0x1FFFFFFF:(rec + 0x238 + 0x6E) & 0x1FFFFFFF] = ram.data[src & 0x1FFFFFFF:(src + 0x6E) & 0x1FFFFFFF]
    ram.data[(rec + 0x2A6) & 0x1FFFFFFF:(rec + 0x2A6 + 0x6E) & 0x1FFFFFFF] = \
        ram.data[COMMON_PARAMS & 0x1FFFFFFF:(COMMON_PARAMS + 0x6E) & 0x1FFFFFFF]
    for dst, fighter in ((0x314, ram.u32(AI_SELF)), (0x320, ram.u32(AI_OPP))):
        src = BAND_TABLE + 12 * ram.s16(fighter + 0x18)
        ram.data[(rec + dst) & 0x1FFFFFFF:(rec + dst + 12) & 0x1FFFFFFF] = ram.data[src & 0x1FFFFFFF:(src + 12) & 0x1FFFFFFF]
    ram.put(rec + 0x1D4, "h", max(ram.s16(rec + 0x26E), ram.s16(rec + 0x26A)))
    if ram.u32(GAME_MODE) == 8:
        level = min(level, 3)
        ram.put(rec + 0x32C, "I", FORCE_WORDS + 0x1E * (group & 3) + 6 * level)


def _half(v: int) -> int:
    return int(v / 2)


def ai_reset(ram: Ram, fighter: int, group: int, level: int, disabled: int) -> None:
    """AiReset (0x800596B0) for the record of `fighter` (+0x1886 slot). The hooks, the target band
    table and +0x30 come from the current AI_SELF / AI_OPP globals, not from `fighter`."""
    rec = AI_RECORDS + AI_RECORD_SIZE * ram.u8(fighter + 0x1886)
    self_, opp = ram.u32(AI_SELF), ram.u32(AI_OPP)
    for off, size, value in RESET_FIELDS:
        if value is None:
            value = ram.u32(self_ + 0x3F4)
        ram.put(rec + off, "h" if size == 2 else "I", value if size == 2 else value & 0xFFFFFFFF)
    for off in range(0x1DC, 0x1FC, 4):
        ram.put(rec + off, "I", 0)
    for off in (0x8F, 0x8E, 0x91, 0x90, 0x92, 0x93, 0x94):
        ram.put(rec + off, "B", 0)
    load_params(ram, rec, group, level, disabled)
    ram.put(rec + 0x74, "I", hook_for_bank(ram, 1, ram.s16(opp + 0x16)))
    ram.put(rec + 0x78, "I", hook_for_bank(ram, 0, ram.s16(self_ + 0x16)))
    if ram.u32(TEAM_OR_SURVIVAL):
        for off in (0x23E, 0x240, 0x242, 0x244):
            ram.put(rec + off, "h", _half(ram.s16(rec + off)))
        ram.put(rec + 0x254, "h", int(ram.s16(rec + 0x254) / 4))
    ram.put(rec + 0x68, "h", ram.s16(rec + 0x23E))
    r = rand(ram)
    u = (r + _lcg_next(ram)) & 0x7FFF
    ram.put(rec + 0x40, "h", (u * 30 >> 15) + 30)
    for k in range(MAX_CANDIDATES):
        ram.put(CANDIDATES + 12 * k + 8, "h", -1)


def init_round(ram: Ram) -> None:
    """AiInitRound (0x8005993C): assign AI slots and targets for the three fighter records."""
    game_mode = ram.u32(GAME_MODE)
    ram.put(AI_MULTI, "I", 1 if ram.u32(TEAM_OR_SURVIVAL) or game_mode == 8 else 0)
    for k in range(4):
        ram.put(FORCE_TARGETS + 4 * k, "i", -1)
    if game_mode == 8:
        layout = ram.u32(FORCE_LAYOUT)
        if layout == 1:
            slots, targets = (-1, 0, 1), (-1, 0, 0)
        elif layout == 2:
            slots, targets = (0, -1, 1), (1, -1, 1)
        else:
            return
    else:
        slots, targets = (0, 1, -1), (1, 0, -1)
    for i in range(3):
        fighter = FIGHTER_BASE + FIGHTER_STRIDE * i
        ram.put(fighter + 0x1886, "b", slots[i])
        ram.put(fighter + 0x1887, "b", targets[i])
        slot = slots[i]
        if slot < 0:
            continue
        rec = AI_RECORDS + AI_RECORD_SIZE * slot
        ram.put(rec + 2, "h", slot)
        ram.put(rec, "h", slot)
        opp = FIGHTER_BASE + FIGHTER_STRIDE * targets[i]
        ram.put(AI_OPP, "I", opp)
        ram.put(rec + 0x10, "I", opp)
        ram.put(AI_SELF, "I", fighter)
        index = ram.u32(ram.u32(BANKS + 4 * slot) + 0xC)
        ram.put(rec + 0xC, "I", index)
        ram.put(AI_INDEX + 4 * slot, "I", index)
        ram.put(rec + 6, "h", 0)
        ram.put(rec + 4, "h", 0)
        ai_reset(ram, fighter, -1, -1, -1)
