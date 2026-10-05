#!/usr/bin/env python3
"""Compare ai_sim.py with the game's CPU-opponent routines in the CPU harness.

Usage: python3 tools/research/verify_ai_sim.py [--cases N] [--seed S] [--only NAME]
"""

from __future__ import annotations

import argparse
from unicorn import UC_HOOK_CODE
import logging
import random
import struct

import ai_sim as ai
import ai_update
import fight_sim as sim
from psxcpu import STACK_TOP, load_release
from verify_fight_sim import F0, F1, INDEX, LISTS, ROW_COUNT, ROWS, build_bank, compare, prepare, snapshot

log = logging.getLogger("verify_ai_sim")
REC = ai.AI_RECORDS                # slot 0
CALL_SP = STACK_TOP - 0x100        # stack pointer psxcpu.call hands to the routine


def patch_harness(cpu) -> None:
    """No SPU in the harness: SoundPlayFighter returns at once. The Tekken Force overlay routine
    FUN_800B2E60 (the player record) returns F0."""
    cpu.write(0x800756A4, struct.pack("<2I", 0x03E00008, 0x24020000))
    cpu.write(0x800B2E60, struct.pack("<3I", 0x3C02800A, 0x03E00008, 0x344296F0))


def setup_ai(cpu, rng) -> None:
    prepare(cpu, rng)
    build_bank(cpu, rng)
    for k in range(ROW_COUNT):
        if rng.random() < 0.15:
            row = ROWS + 0x38 * k
            state = struct.unpack("<I", cpu.read(row + 4, 4))[0]
            cpu.write(row + 4, struct.pack("<I", state | 0x800000))
    rec = bytearray(rng.randrange(256) for _ in range(ai.AI_RECORD_SIZE))
    struct.pack_into("<I", rec, 0xC, INDEX)
    struct.pack_into("<I", rec, 0x58, ROWS + 0x38 * rng.randrange(ROW_COUNT))
    struct.pack_into("<I", rec, 0x64, rng.randrange(32))
    struct.pack_into("<I", rec, 0x7C, rng.choice([0, 0, ai.FILTER_NO_LOWS]))
    cpu.write(REC, bytes(rec))
    cpu.write(ai.AI_SELF, struct.pack("<I", F0))
    cpu.write(ai.AI_OPP, struct.pack("<I", F1))


def case_collect(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    current_only = rng.choice([0, 0, 1])
    stale_slot = CALL_SP - 0x58 + 0x1C
    ram = snapshot(cpu)
    targets = [ram.u32(INDEX + 4 * s) for s in range(0, 4023, 97)]
    stale = rng.choice([0x12345678, rng.choice(targets)])
    cpu.write(stale_slot, struct.pack("<I", stale))
    f = sim.Fighter(ram, F0)
    f.poseFrame = rng.randint(0, 70)
    off = F0 & 0x1FFFFFFF
    cpu.write(F0, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    count = cpu.call(0x80056A4C, REC, current_only) & 0xFFFFFFFF
    mine = ai.collect_candidates(ram, REC, current_only, stale)
    ok = compare(cpu, ram, [(ai.CANDIDATES, 12 * ai.MAX_CANDIDATES), (REC, ai.AI_RECORD_SIZE)], "AiCollectCandidates")
    if count != mine:
        log.info("AiCollectCandidates: count %d, port %d", count, mine)
        ok = False
    return ok


BRANCHES = 0x801F0000             # branch rows the random candidates point at
TARGETS = 0x801F0800               # move rows the random candidates lead to
FILTERS = {
    0x8005758C: ai.filter_attacks,
    0x800576DC: ai.filter_attacks_no_special,
    0x80057820: ai.filter_fast_attacks,
    0x80057954: ai.filter_vs_posture,
    0x80057AC4: ai.filter_punish_level,
    0x80057C88: ai.filter_punish_level_no_high,
    0x80057E48: ai.filter_plain_attacks,
    0x80058040: ai.filter_quick_attacks,
    0x8005817C: ai.filter_quick_attacks_no_high,
    0x80058AC0: ai.filter_side_steps_then_quick,
    0x800582A0: ai.filter_defence,
    0x800616B4: ai.filter_no_lows,
}
ATTACK_WORDS = [0x412, 0x217, 0x10F, 0x607, 0x706, 0x31F, 0x51F, 0x800, 0]


def random_target(rng) -> bytes:
    row = bytearray(rng.randrange(256) for _ in range(0x38))
    state = rng.choice([0x842, 0x2829, 0x1052, 0x4, 0x404, 0x4C02, 0x843, 0x1]) | rng.choice([0, 0x100, 0x10000, 0x20000, 0x80000])
    struct.pack_into("<I", row, 4, state)
    hint = rng.choice([0, 0x10000, 0x40000, 0x80000, 0x100000, 0x200000, 0x400000, 0x1C0000])
    struct.pack_into("<I", row, 8, rng.choice(ATTACK_WORDS) | hint)
    struct.pack_into("<h", row, 0x14, rng.choice([-5, 0, 7, 30]))
    row[0x19] = rng.choice([0, 0, 3])
    row[0x2D] = rng.choice([0, 5, 13, 14, 20])
    struct.pack_into("<I", row, 0xC, LISTS + 0x100 * rng.randrange(ROW_COUNT))
    return bytes(row)


def setup_filter(cpu, rng) -> int:
    """Random candidate table and record fields; returns the candidate count."""
    n = rng.choice([0, 1, rng.randint(2, 40)])
    cpu.write(TARGETS, b"".join(random_target(rng) for _ in range(32)))
    cmds = [ai.SIDE_STEP, ai.SIDE_STEP_ALT, 0x0010, 0x0020, 0x4002, 0x8]
    cpu.write(BRANCHES, b"".join(struct.pack("<H", rng.choice(cmds)) + bytes(rng.randrange(256) for _ in range(10))
                                 for _ in range(32)))
    table = b"".join(struct.pack("<IIhxx", TARGETS + 0x38 * rng.randrange(32), BRANCHES + 12 * rng.randrange(32),
                                 rng.choice([0, 0, 0, 1, -1])) for _ in range(n))
    cpu.write(ai.CANDIDATES, table)
    put = lambda off, fmt, v: cpu.write(REC + off, struct.pack(fmt, v))
    put(0x14, "<I", rng.randint(0, 5))
    put(0x18, "<i", rng.randint(1, 5))
    put(0x1C, "<i", rng.choice([100, 2950, 2951, 5000]))
    put(0x24, "<i", rng.choice([-100, -71, -70, 0, 50]))
    put(0x70, "<h", n)
    put(0x72, "<h", rng.randint(-3, 10))
    put(0x20A, "<h", rng.choice([0, 6, 14, 30]))
    put(0x20C, "<h", rng.choice([0, 1]))
    put(0x214, "<h", rng.choice([0, 0, 1]))
    put(0x230, "<I", rng.choice([0x4C02, 0x400, 0x404, 4, 1, 2, 3, 0, 0x842, 0x2829]))
    put(0x234, "<I", rng.choice(ATTACK_WORDS))
    lcg = rng.getrandbits(32)
    if rng.random() < 0.3:                     # make FUN_800582A0's 1-in-50 draw pass
        lcg = lcg & ~0xFFF | 50 * rng.randrange(82)
    cpu.write(ai.LCG, struct.pack("<I", lcg))
    cpu.write(F0 + 0x60, struct.pack("<H", rng.choice([0x2021, 0x2829, 0x1052])))
    return n


def case_filter(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    setup_filter(cpu, rng)
    addr = 0x800582A0 if rng.random() < 0.3 else rng.choice(list(FILTERS))
    ram = snapshot(cpu)
    got = cpu.call(addr, REC) & 0xFFFFFFFF
    mine = FILTERS[addr](ram, REC) & 0xFFFFFFFF
    label = f"filter {addr:#x}"
    ok = compare(cpu, ram, [(ai.CANDIDATES, 12 * 40), (REC, ai.AI_RECORD_SIZE), (ai.LCG, 4)], label)
    if got != mine:
        log.info("%s: returns %#x, port %#x", label, got, mine)
        ok = False
    return ok


def case_hint_never(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    f.poseFrame = rng.randint(0, 70)
    for k in range(ROW_COUNT):
        if rng.random() < 0.3:
            row = ROWS + 0x38 * k
            ram.put(row + 8, "I", ram.u32(row + 8) | 0x400000)
    for base, size in ((ROWS, 0x38 * ROW_COUNT), (F0, sim.FIGHTER_SIZE)):
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + size]))
    got = cpu.call(0x80057300, REC) & 0xFFFFFFFF
    mine = ai.hint_never_open(ram, REC)
    if got != mine:
        log.info("FUN_80057300: %d, port %d", got, mine)
        return False
    return True


COMMANDS = [0xC001, 0xC002, 0xC00E, 0xC030, 0xC04C, 0xC04D, 0xC7FE, 0xC7FF, 0xC810, 0xC827, 0xC828, 0x4012, 0x8003]


def random_command(rng) -> int:
    if rng.random() < 0.5:
        return rng.choice(COMMANDS)
    return rng.getrandbits(14)


def setup_slots(cpu, rng) -> None:
    for s in range(4):
        cpu.write(ai.AI_INDEX + 4 * s, struct.pack("<I", INDEX))
    cpu.write(F0 + 0x1886, bytes([rng.randrange(4)]))
    cpu.write(ai.RAND_STATE, struct.pack("<I", rng.getrandbits(32)))
    cpu.write(ai.LCG, struct.pack("<I", rng.getrandbits(32)))


def check(cpu, ram, label, got, mine, extra=()) -> bool:
    ok = compare(cpu, ram, [(REC, ai.AI_RECORD_SIZE), (ai.LCG, 4), (ai.RAND_STATE, 4), *extra], label)
    if got != mine:
        log.info("%s: returns %#x, port %#x", label, got, mine)
        ok = False
    return ok


def case_press(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    cmd, target = random_command(rng), rng.getrandbits(32)
    ram = snapshot(cpu)
    got = cpu.call(0x80061BA8, REC, cmd, target) & 0xFFFFFFFF
    return check(cpu, ram, f"AiPressCommand {cmd:#x}", got, ai.press_command(ram, REC, cmd, target))


def case_side_step(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    setup_slots(cpu, rng)
    cpu.write(F0 + 0x3C, struct.pack("<H", rng.choice([0, 0x100, 0x101, 0x4000, 0x7FFF, 0x8000, 0x8100, 0x8101, 0xFFFF, rng.getrandbits(16)])))
    cpu.write(F0 + 0x1278, struct.pack("<h", rng.randint(-5, 5)))
    cpu.write(F1 + 0x1278, struct.pack("<h", rng.randint(-5, 5)))
    side = rng.choice([-1, -1, 0, 1])
    ram = snapshot(cpu)
    cpu.call(0x80061D40, REC, side & 0xFFFFFFFF)
    ai.side_step(ram, REC, side)
    return check(cpu, ram, "AiSideStep", 0, 0)


def setup_execute(cpu, rng) -> None:
    setup_ai(cpu, rng)
    setup_filter(cpu, rng)
    setup_slots(cpu, rng)
    cpu.write(BRANCHES, b"".join(struct.pack("<HxxxxH", random_command(rng), rng.randrange(4023))
                                 + bytes(rng.randrange(256) for _ in range(4)) for _ in range(32)))
    cpu.write(ai.GAME_MODE, struct.pack("<I", rng.choice([0, 5, 8])))
    cpu.write(F0 + 0x1E, bytes([rng.randrange(4)]))
    cpu.write(REC + 0x32C, struct.pack("<I", 0x801F1000))
    cpu.write(0x801F1000, struct.pack("<2h", rng.randint(-9, 9), rng.randint(-9, 9)))
    cpu.write(ai.FORCE_TARGETS - 4, b"".join(struct.pack("<i", rng.choice([-1, 3])) for _ in range(6)))
    for k in range(ROW_COUNT):
        if rng.random() < 0.2:
            row = ROWS + 0x38 * k
            cpu.write(row + 8, struct.pack("<I", struct.unpack("<I", cpu.read(row + 8, 4))[0] | ai.HINT_NEVER))
    marked = sum(struct.unpack("<h", cpu.read(ai.CANDIDATES + 12 * k + 8, 2))[0] > 0
                 for k in range(struct.unpack("<h", cpu.read(REC + 0x70, 2))[0]))
    cpu.write(REC + 0x72, struct.pack("<h", marked if rng.random() < 0.8 else rng.randint(0, 5)))
    cpu.write(REC + 2, struct.pack("<H", rng.getrandbits(16)))


FORCE_REGION = (ai.FORCE_TARGETS - 4, 24)


def case_script(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    script = 0x801F1100
    cpu.write(script, b"".join(struct.pack("<H", rng.choice([0, rng.getrandbits(16)])) for _ in range(2)))
    step = rng.getrandbits(16)
    ram = snapshot(cpu)
    got = cpu.call(0x80061AC4, step) & 0xFFFF
    ok = check(cpu, ram, "AiPadFromStep", got, ai.pad_from_step(ram, step))
    cpu.call(0x80061B24, REC, script)
    ai.start_script(ram, REC, script)
    return check(cpu, ram, "AiStartScript", 0, 0) and ok


def case_after_attack(cpu, rng) -> bool:
    setup_execute(cpu, rng)
    branch = BRANCHES + 12 * rng.randrange(32)
    ram = snapshot(cpu)
    cpu.call(0x80058C40, REC, branch)
    ai.after_attack(ram, REC, branch)
    return check(cpu, ram, "AiAfterAttack", 0, 0, [FORCE_REGION])


def case_execute(cpu, rng) -> bool:
    setup_execute(cpu, rng)
    ram = snapshot(cpu)
    got = cpu.call(0x80058D6C, REC) & 0xFFFFFFFF
    mine = ai.execute_candidate(ram, REC) & 0xFFFFFFFF
    return check(cpu, ram, "AiExecuteCandidate", got, mine, [FORCE_REGION, (ai.CANDIDATES, 12 * 40)])


def case_branch_open(cpu, rng) -> bool:
    setup_ai(cpu, rng)
    setup_slots(cpu, rng)
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    f.poseFrame = rng.randint(0, 40)
    f.poseMove = ROWS + 0x38 * rng.randrange(ROW_COUNT)
    off = F0 & 0x1FFFFFFF
    cpu.write(F0, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    lists = [ram.u32(ROWS + 0x38 * k + 0xC) for k in range(ROW_COUNT)]
    slots = [ram.u16(r + 6) for lst in lists for r, _ in ai._rows(ram, lst)] or [0]
    slot = rng.choice(slots) if rng.random() < 0.8 else rng.randrange(4023)
    got = cpu.call(0x80058ED0, slot, REC) & 0xFFFFFFFF
    return check(cpu, ram, "FUN_80058ED0", got, ai.branch_open_to(ram, REC, slot))


def case_whiff(cpu, rng) -> bool:
    setup_execute(cpu, rng)
    cpu.write(REC + 0x27E, struct.pack("<h", rng.choice([0, 100, 2000, 4096])))
    cpu.write(REC + 0x54, struct.pack("<h", rng.choice([-1, 0, 5])))
    cpu.write(REC + 0x2E, struct.pack("<h", rng.choice([0, 0x3800, 0x3801])))
    cpu.write(F1 + 0xDB, bytes([rng.choice([0, 1])]))
    move = TARGETS + 0x38 * rng.randrange(32)
    ram = snapshot(cpu)
    got = cpu.call(0x800593D4, REC, move) & 0xFFFFFFFF
    return check(cpu, ram, "FUN_800593D4", got, ai.whiff_punish_ok(ram, REC, move))


HOOK_SLOTS = [0x2C6, 0x2C7, 0x137, 0xDE3, 0xDE4, 0x16F, 0x456, 0x459, 0x45A, 0x45B, 0x45C, 0x472, 0x16A,
              0x43A, 0x458, 0x49C, 0x49D, 0x49E, 0x16E, 0x15, 0x100]


def setup_hook(cpu, rng) -> None:
    setup_execute(cpu, rng)
    h16 = lambda addr, fmt, *values: cpu.write(addr, struct.pack(fmt, rng.choice(values)))
    for fighter in (F0, F1):
        h16(fighter + 0xA0, "<h", *HOOK_SLOTS)
        cpu.write(fighter + 0x58, struct.pack("<h", rng.randint(0, 60)))
        cpu.write(fighter + 0x54, struct.pack("<I", ROWS + 0x38 * rng.randrange(ROW_COUNT)))
        for off in (0x2E, 0x30, 0x3C, 0x3E):
            h16(fighter + off, "<H", 0, 0x100, 0x101, 0x1000, 0x1001, 0x2000, 0x3800, 0x37FF, 0x3FFF, 0x4000,
                0x6000, 0x6001, 0x7FFF, 0x8000, 0x8101, 0xE000, 0xDFFF, rng.getrandbits(16))
        h16(fighter + 0x32, "<h", 0, 0, 1)
        h16(fighter + 0x40, "<h", 0, 0, 2, 1)
        cpu.write(fighter + 0x1278, struct.pack("<h", rng.randint(-3, 3)))
        h16(fighter + 0x16, "<h", 0x13, 3, 0)
        h16(fighter + 0xDB, "B", 0, 0, 1)
        h16(fighter + 0xDF, "B", 0, 0, 1)
    for k in range(ROW_COUNT):
        row = ROWS + 0x38 * k
        cpu.write(row + 0x2D, bytes([rng.choice([0, 5, 12, 30, 45]), rng.choice([10, 20, 40, 60])]))
    h16(REC + 0x14, "<i", 0, 1, 2, 3, 4, 5)
    h16(REC + 0x18, "<i", 1, 2, 3, 4, 5)
    h16(REC + 0x1C, "<I", 100, 0xA8C, 0xA8D, 7000, 7001, 0x10000)
    h16(REC + 0x20A, "<h", 5, 9, 10, 11)
    h16(REC + 0x208, "<h", 0, 1)
    h16(REC + 0x88, "<h", 0, 1)
    h16(REC + 0x224, "<I", 0, 1, 0x400000, 0x10)
    h16(REC + 0x230, "<I", 0, 1, 2, 3, 4)
    h16(REC + 0x24E, "<h", 0, 2000, 4096)
    h16(REC + 0x68, "<h", 0, 5, -1)
    h16(REC + 0x272, "<h", 0, 2000, 4096)
    h16(REC + 0x8A, "<h", -1, -1, 3)


FOCUS = {0x800621D8: (F1, [0xDE4, 0x16E]), 0x80061E70: (F1, [0x16F, 0x456, 0x459, 0x45B, 0x472, 0x16A, 0x43A, 0x458, 0x49E]),
         0x80062BAC: (F1, [0x2C6, 0x2C7]), 0x80062C28: (F1, [0x137]), 0x80062C84: (F0, [0xDE3])}


def focus_hook(cpu, rng, hook) -> None:
    """Steer the random state into the hook's interesting branches."""
    if hook in FOCUS:
        fighter, slots = FOCUS[hook]
        cpu.write(fighter + 0xA0, struct.pack("<h", rng.choice(slots)))
    move = struct.unpack("<I", cpu.read(F1 + 0x54, 4))[0]
    first, last = cpu.read(move + 0x2D, 2)
    frame = rng.choice([first - 31, first - 30, first - 21, first - 20, first - 9, first - 8, first, last - 1, last,
                        last + 39, last + 40, rng.randint(9, 14), rng.randint(0, 60)])
    cpu.write(F1 + 0x58, struct.pack("<h", frame))
    if hook == 0x80062804:
        cpu.write(REC + 0x68, struct.pack("<h", 0))
        cpu.write(REC + 0x24E, struct.pack("<h", 4096))
        own = struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0]
        cpu.write(own + 0x2D, bytes([0]))
        rows = struct.unpack("<I", cpu.read(own + 0xC, 4))[0]
        if rng.random() < 0.5 and struct.unpack("<H", cpu.read(rows, 2))[0] not in (ai.END, ai.COMMON):
            cpu.write(rows + 2, bytes([0, 0]))                      # no restriction, no condition
            cpu.write(rows + 6, struct.pack("<H", 0x15))
            cpu.write(rows + 9, bytes([0, 255]))
        for addr, fmt, value in ((F0 + 0x32, "<h", 0), (F0 + 0x40, "<h", 0), (F1 + 0xDB, "B", 0), (F1 + 0xDF, "B", 0),
                                 (REC + 0x20A, "<h", 10), (REC + 0x14, "<i", 1)):
            if rng.random() < 0.85:
                cpu.write(addr, struct.pack(fmt, value))


def case_hooks(cpu, rng) -> bool:
    setup_hook(cpu, rng)
    hook = rng.choice(list(ai.HOOKS))
    if rng.random() < 0.8:
        focus_hook(cpu, rng, hook)
    ram = snapshot(cpu)
    got = cpu.call(hook, REC) & 0xFFFFFFFF
    mine = ai.HOOKS[hook](ram, REC) & 0xFFFFFFFF
    return check(cpu, ram, f"hook {hook:#x}", got, mine, [FORCE_REGION, (ai.CANDIDATES, 12 * 40)])


def case_call_hook(cpu, rng) -> bool:
    setup_hook(cpu, rng)
    cpu.write(REC + 0x74, struct.pack("<I", rng.choice([0, *ai.HOOKS])))
    cpu.write(REC + 0x78, struct.pack("<I", rng.choice([0, *ai.HOOKS])))
    own = rng.choice([0, 1])
    ram = snapshot(cpu)
    got = cpu.call(0x800594C4, own, REC) & 0xFFFFFFFF
    mine = ai.call_hook(ram, own, REC) & 0xFFFFFFFF
    return check(cpu, ram, "AiCallHook", got, mine, [FORCE_REGION, (ai.CANDIDATES, 12 * 40)])


def case_hook_for_bank(cpu, rng) -> bool:
    ram = snapshot(cpu)
    own, bank = rng.choice([0, 1]), rng.choice([0, 3, 4, 6, 10, 13, 14, 16, 19, 20, rng.getrandbits(16)])
    got = cpu.call(0x80062B50, own, bank) & 0xFFFFFFFF
    return check(cpu, ram, "AiHookForBank", got, ai.hook_for_bank(ram, own, bank))


RECORDS_REGION = (ai.AI_RECORDS, 3 * ai.AI_RECORD_SIZE)


def setup_reset(cpu, rng) -> None:
    setup_ai(cpu, rng)
    setup_slots(cpu, rng)
    for fighter in (F0, F1, F1 + ai.FIGHTER_STRIDE):
        cpu.write(fighter + 0x16, struct.pack("<h", rng.choice([0, 3, 4, 6, 10, 13, 14, 16, 19, 25])))
        cpu.write(fighter + 0x18, struct.pack("<h", rng.randint(0, 3)))
        cpu.write(fighter + 0x3F4, struct.pack("<I", rng.getrandbits(32)))
    cpu.write(F0 + 0x1886, bytes([rng.randrange(3)]))
    cpu.write(ai.GAME_MODE, struct.pack("<I", rng.choice([0, 1, 5, 8, 8])))
    cpu.write(ai.TEAM_OR_SURVIVAL, struct.pack("<I", rng.choice([0, 0, 1])))
    cpu.write(ai.DIFFICULTY, bytes([rng.randrange(4)]))
    cpu.write(ai.CPU_LEVEL, bytes([rng.randrange(11)]))
    cpu.write(ai.FORCE_LAYOUT, struct.pack("<I", rng.choice([0, 1, 2])))
    cpu.write(0x800AE0F0, struct.pack("<I", 0x801E4000))


def case_reset(cpu, rng) -> bool:
    setup_reset(cpu, rng)
    args = [rng.choice([-1, 0, 1, 2, 3, 5, 9, 12]) for _ in range(2)] + [rng.choice([-1, 0, 1])]
    ram = snapshot(cpu)
    cpu.call(0x800596B0, F0, 0, *(a & 0xFFFFFFFF for a in args))
    ai.ai_reset(ram, F0, *args)
    return check(cpu, ram, "AiReset", 0, 0, [RECORDS_REGION, (ai.CANDIDATES, 12 * 180)])


def case_init_round(cpu, rng) -> bool:
    setup_reset(cpu, rng)
    ram = snapshot(cpu)
    cpu.call(0x8005993C)
    ai.init_round(ram)
    fighters = [(f + 0x1886, 2) for f in (F0, F1, F1 + ai.FIGHTER_STRIDE)]
    return check(cpu, ram, "AiInitRound", 0, 0, [RECORDS_REGION, (ai.CANDIDATES, 12 * 180), (ai.AI_INDEX, 0x30),
                                                  (ai.AI_SELF, 4), (ai.AI_OPP, 4), *fighters])


PADS = 0x801F1200                 # AiUpdate's two output words


def setup_update(cpu, rng) -> None:
    setup_hook(cpu, rng)
    cpu.write(ai.GAME_MODE, struct.pack("<I", rng.choice([0, 1, 5, 8])))
    cpu.write(ai.AI_MULTI, struct.pack("<I", rng.choice([0, 0, 1])))
    cpu.write(ai.TEAM_OR_SURVIVAL, struct.pack("<I", rng.choice([0, 0, 1])))
    cpu.write(F0 + 0x1886, bytes([0]))
    cpu.write(ai_update.FRAME_COUNTER, struct.pack("<I", rng.getrandbits(32)))
    cpu.write(ai_update.FIGHTER_DISTANCE, struct.pack("<I", rng.choice([0x100, 0x6FF, 0x700, 0x2000])))
    rec = bytearray(cpu.read(REC, ai.AI_RECORD_SIZE))
    struct.pack_into("<I", rec, 0x10, F1)
    struct.pack_into("<H", rec, 0, rng.choice([0, 1]))
    struct.pack_into("<I", rec, 8, rng.choice([0, 0, 0, 0x801F1100]))
    struct.pack_into("<h", rec, 0x21E, rng.choice([-1, -1, -1, 0, 1, 2]))
    struct.pack_into("<I", rec, 0x74, rng.choice([0, *ai.HOOKS]))
    struct.pack_into("<I", rec, 0x78, rng.choice([0, *ai.HOOKS]))
    struct.pack_into("<h", rec, 0x1FE, rng.choice([-1, 0, 1, 50]))
    struct.pack_into("<H", rec, 0x1FC, rng.randrange(8))
    for k in range(8):
        struct.pack_into("<I", rec, 0x1DC + 4 * k, rng.choice([0, ROWS + 0x38 * rng.randrange(ROW_COUNT)]))
    if rng.random() < 0.3:
        for off in range(0x314, 0x32C, 2):
            struct.pack_into("<h", rec, off, rng.randint(-200, 3000))
    else:                                    # ordered band thresholds, as in the game's tables
        for base in (0x314, 0x320):
            edge = rng.randint(200, 900)
            for k in range(4):
                struct.pack_into("<h", rec, base + 2 * k, edge)
                edge += rng.randint(200, 1200)
        struct.pack_into("<h", rec, 0x31E, rng.randint(0, 300))
        struct.pack_into("<h", rec, 0x32A, rng.randint(0, 300))
    for base, most, count in ((0xC4, 4, 0xC2), (0xDC, 48, 0xDA), (0x1A4, 10, 0x1A2)):
        for k in range(most):
            struct.pack_into("<I", rec, base + 4 * k, BRANCHES + 12 * rng.randrange(32))
        struct.pack_into("<h", rec, count, rng.randint(0, most))
    struct.pack_into("<h", rec, 0x96, rng.choice([-1, 0, 1, 3]))
    struct.pack_into("<h", rec, 0x246, rng.choice([0, 2, 5]))
    struct.pack_into("<h", rec, 0x24A, rng.choice([0, 2000, 4096]))
    struct.pack_into("<h", rec, 0x24C, rng.choice([0, 2000, 4096]))
    struct.pack_into("<I", rec, 0xA0, rng.choice([0, ROWS + 0x38 * rng.randrange(ROW_COUNT)]))
    struct.pack_into("<I", rec, 0xBC, BRANCHES + 12 * rng.randrange(32))
    struct.pack_into("<h", rec, 0x9C, rng.randint(-1, 3))
    cpu.write(REC, bytes(rec))
    throw = rng.choice([0, 0, 0, -1, 1])
    cpu.write(F0 + 0x74, struct.pack("<h", throw))
    if throw:
        cpu.write(F0 + 0x58, struct.pack("<h", rng.randint(0, 3)))
        cpu.write(F1 + 0xA0, struct.pack("<h", rng.choice([0x189, 0x18E, 0x17F, 0x181, 0x172, 0x152, 0x100])))
        cpu.write(F1 + 0x16, struct.pack("<h", rng.choice([0, 3, 9, 4])))
        cpu.write(F0 + 0x16, struct.pack("<h", rng.choice([0, 4, 0xD, 3])))
    cpu.write(0x801F1100, b"".join(struct.pack("<H", rng.choice([0, rng.getrandbits(16)])) for _ in range(4)))
    diversify(cpu, rng)
    if rng.random() < 0.7:
        go_deep(cpu, rng)
        r = rng.random()
        if r < 0.35:
            go_react(cpu, rng)
        elif r < 0.8:
            go_attack(cpu, rng)
    for fighter in (F0, F1):
        cpu.write(fighter + 0xF8, struct.pack("<I", rng.choice([100, 1500, 3000, 6000, 12000, rng.randint(0, 6000)])))
        cpu.write(fighter + 0x3F4, struct.pack("<i", rng.randint(0, 150)))
        cpu.write(fighter + 0x3F8, struct.pack("<i", rng.choice([100, 150])))
        for off in (0x87, 0xCE, 0xD2):
            cpu.write(fighter + off, bytes([rng.choice([0, 0, 1])]))
        cpu.write(fighter + 0x64, struct.pack("<h", rng.choice([0x412, 0x217, 0])))


SPECIAL_SLOTS = [0x3A7, 0xD41, 0xD24, 0xD32, 0xDE2, 0xD25, 0xD34, 0x15, 0x3B]
MARKS = 0x801F1300                 # bytes that move rows +0x28 point at


def diversify(cpu, rng) -> None:
    """Spread the random state over the branches AiUpdate tests."""
    cpu.write(MARKS, bytes([0x18, 0x1A, 0, 7]))
    for k in range(ROW_COUNT):
        row = ROWS + 0x38 * k
        state = struct.unpack("<I", cpu.read(row + 4, 4))[0]
        state |= rng.choice([0, 0, 0x80000, 0x200000, 0x400000, 0x204, 1, 0x205, 0x10000])
        word = struct.unpack("<I", cpu.read(row + 8, 4))[0] | rng.choice([0, 0, 0x200000, 0x80000, 0x400000])
        cpu.write(row + 4, struct.pack("<II", state, word))
        cpu.write(row + 0x28, struct.pack("<I", MARKS + rng.randrange(4)))
        cpu.write(row + 0x24, struct.pack("<I", rng.choice([0, 0x1000, 0x2000, 0x3000])))
    for i in range(ROW_COUNT):
        lst = LISTS + 0x100 * i
        for r in range(0, 0xF0, 12):
            cmd = struct.unpack("<H", cpu.read(lst + r, 2))[0]
            if cmd == ai.END:
                break
            if cmd != ai.COMMON and rng.random() < 0.2:
                cpu.write(lst + r + 6, struct.pack("<H", rng.choice(SPECIAL_SLOTS)))
    for fighter in (F0, F1):
        if rng.random() < 0.5:
            cpu.write(fighter + 0x3E8, bytes(12))
        cpu.write(fighter + JOINTS_Y, struct.pack("<i", rng.choice([0, -0xC1B, -0xC1C, -3000])))
        if rng.random() < 0.2:
            cpu.write(fighter + 0x58, struct.pack("<h", rng.choice([-100, -1, 255])))
    if rng.random() < 0.2:
        cpu.write(F1 + 0x16, struct.pack("<h", rng.choice([4, 0xE, 0x13])))
        cpu.write(F1 + 0xA0, struct.pack("<h", rng.choice([0x456, 0x100])))
    cpu.write(REC + 0x3E, struct.pack("<h", rng.choice([0, 1])))
    cpu.write(REC + 0x50, struct.pack("<h", rng.choice([0, 1])))
    if rng.random() < 0.2:
        move = struct.unpack("<I", cpu.read(F1 + 0x54, 4))[0]
        cpu.write(F1 + 0xA0, cpu.read(move + 0x10, 2))


JOINTS_Y = ai_update.JOINTS + 0xA0


def go_attack(cpu, rng) -> None:
    """Steer past every earlier exit into the attack choice (LAB_8005E5EC) and the movement code."""
    put = lambda addr, fmt, value: cpu.write(addr, struct.pack(fmt, value))
    pick = lambda addr, fmt, *values: put(addr, fmt, rng.choice(values))
    for off in (0x74, 0x78):
        put(REC + off, "<I", 0)
    put(REC + 0x28, "<h", 0)
    put(REC + 0x58, "<I", struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0])
    put(REC + 0x4E, "<h", -1)
    put(REC + 0x2C, "<h", 0)
    own = struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0]
    state = struct.unpack("<I", cpu.read(own + 4, 4))[0] & ~0x604 & ~0xFFFF
    put(own + 4, "<I", state | rng.choice([0x10, 0x842 & ~0x404, 0x1, 0x2, 0x80000 | 0x10, 0x20]))
    put(own + 8, "<I", struct.unpack("<I", cpu.read(own + 8, 4))[0] & ~0x200000)
    opp = struct.unpack("<I", cpu.read(F1 + 0x54, 4))[0]
    cpu.write(opp + 0x2D, bytes([rng.choice([0, 0, 0, 12]), rng.choice([15, 30])]))
    ostate = rng.choice([0x842, 0x4, 0x204, 0x4C02, 0x1, 0x2, 0x80000 | 0x842, 0x10])
    put(opp + 4, "<I", ostate)
    put(opp + 8, "<I", rng.choice([0x412, 0x217, 0x10F, 0, 0x607]) | rng.choice([0, 0x80000, 0x400000, 0x100000]))
    cpu.write(opp + 0x19, bytes([rng.choice([0, 0, 3]), rng.choice([10, 40])]))
    pick(F1 + 0x58, "<h", 0, 5, 20, 40, 60)
    pick(F0 + 0x87, "B", 0, 1, 1)
    pick(F0 + 0x30, "<h", 0, 0x800, 0x1000, 0x1800, 0x5000)
    pick(F0 + 0x3E, "<h", 0, 0x2000, 0x5000)
    pick(F1 + 0xDB, "B", 0, 0, 1)
    pick(F1 + 0xDF, "B", 0, 0, 1)
    pick(F1 + 0x16, "<h", 0, 3, 0x13, 9)
    pick(F0 + 0x16, "<h", 0, 3, 7, 9, 12, 4)
    pick(F0 + 0x122, "<h", 0, 5)
    pick(F1 + 0xA0, "<h", 6, 0x100, 0x137)
    pick(F0 + 0xD2, "B", 0, 0, 1)
    pick(F1 + 0xD2, "B", 0, 0, 1)
    for off, values in ((0x1D2, (0, 0, 50)), (0x26A, (20, 100)), (0x26E, (20, 100)), (0x4C, (0, 0, 1)),
                        (0x44, (-1, -1, 0, 4, 5)), (0x46, (-1, -1, 0, 3)), (0x3A, (0, 0, 2, 1)), (0x216, (0, 3, 10)),
                        (0x6C, (-1, 0, 2)), (0x80, (0, 0x19, 0x1A, 40)), (0x84, (0, 1, 10, 20)), (0xD4, (0, 1)),
                        (0x68, (-3, -1, 0, 5, 0x24, 0x30)), (0x42, (-1, 0)), (0x8A, (-1, -1, 0)), (0x38, (-1, 0, 5)),
                        (0x40, (-1, -1, 3)), (0x48, (-1, -1, 2)), (0x4A, (-1, -1, 3)), (0x2A, (0, 0x2D0, 0x2D1)),
                        (0x248, (0, 2000, 4096)), (0x24E, (0, 2000, 4096)), (0x250, (0, 2000, 4096)),
                        (0x252, (0, 2000, 4096)), (0x258, (0, 2000, 4096)), (0x274, (0, 4096)), (0x280, (0, 4096)),
                        (0x284, (0, 4096)), (0x27E, (0, 1000, 4096)), (0x25C, (0, 500, 4096))):
        pick(REC + off, "<h", *values)
    for off, values in ((0x8F, (0, 0, 1)), (0x91, (0, 0, 1)), (0x200, (0, 0, 0, 1)), (0x92, (0, 1))):
        pick(REC + off, "B", *values)


def go_react(cpu, rng) -> None:
    """Steer into the reaction to an incoming attack (the jump table after 0x8005C514)."""
    put = lambda addr, fmt, value: cpu.write(addr, struct.pack(fmt, value))
    put(REC + 0x216, "<h", -1)
    put(REC + 0x74, "<I", 0)
    put(REC + 0x78, "<I", 0)
    put(REC + 0x2C, "<h", 0)
    put(REC + 0x28, "<h", 0)
    put(REC + 0x58, "<I", struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0])
    put(REC + 0x4E, "<h", -1)
    own = struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0]
    state = struct.unpack("<I", cpu.read(own + 4, 4))[0] & ~0x200405 | rng.choice([0x1052, 0x2829, 0x2021, 0x10, 1])
    put(own + 4, "<I", state & ~0x404 if rng.random() < 0.9 else state)
    opp = struct.unpack("<I", cpu.read(F1 + 0x54, 4))[0]
    first = rng.randint(3, 30)
    last = first + rng.randint(0, 10)
    cpu.write(opp + 0x2D, bytes([first, last]))
    put(F1 + 0x58, "<h", rng.choice([rng.randint(0, last + 1), first - 30, first - 8, first - 9, first - 4, first - 22]))
    put(opp + 8, "<I", rng.choice([0x412, 0x217, 0x10F, 0x607, 0x706, 0x31F]) | rng.choice([0, 0x400000, 0x40000, 0x100000]))
    put(opp + 4, "<I", rng.choice([0x842, 0x4, 0x200004, 0x80000]))
    put(F1 + 0x16, "<h", rng.choice([0, 3, 9, 1]))
    put(F0 + 0x16, "<h", rng.choice([0, 3, 9, 1, 5, 7]))
    put(F1 + 0xA0, "<h", rng.choice([0x189, 0x172, 0x152, 0x100]))
    put(F0 + 0x3E, "<h", rng.choice([0, 0x2000, 0x5000]))
    put(F0 + 0x40, "<h", rng.choice([0, 2]))
    if rng.random() < 0.3:
        put(F1 + 0x16, "<h", 4)
    for off, values in ((0x6C, (0, 3, 9, -1)), (0x94, (0, 1, 2, 3, 4, 5, 6)), (0x8C, (-1, -1, 3)), (0x292, (0, 4096)),
                        (0x272, (0, 4096)), (0x296, (0, 4096)), (0x254, (0, 4096)), (0x256, (0, 4096)),
                        (0x25A, (0, 4096)), (0x258, (0, 4096)), (0x25C, (0, 4096)), (0x202, (0, 1)),
                        (0x20E, (0, 0x1F, 0x20)), (0x50, (0, 1)), (0x92, (0, 1))):
        put(REC + off, "<h" if off != 0x94 and off != 0x92 else "B", rng.choice(values))
    if rng.random() < 0.3:
        put(REC + 0x1DC, "<I", opp)


def go_deep(cpu, rng) -> None:
    """Remove the early exits so the case reaches the decision stages."""
    for addr, fmt, value in ((REC + 8, "<I", 0), (REC + 0x21E, "<h", -1), (ai.AI_MULTI, "<I", 0),
                             (F0 + 0x74, "<h", 0), (F0 + 0x1A4, "<I", 0), (F0 + 0xDB, "B", 0)):
        if rng.random() < 0.95:
            cpu.write(addr, struct.pack(fmt, value))
    if rng.random() < 0.8:
        cpu.write(ai.GAME_MODE, struct.pack("<I", rng.choice([0, 1, 5])))
    own = struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0]
    state = struct.unpack("<I", cpu.read(own + 4, 4))[0]
    if rng.random() < 0.8:
        state = state & ~0xFFFF | rng.choice([0x4, 0x404, 0x4C02, 0x1052, 0x2829, 0x2021, 0x405])
    cpu.write(own + 4, struct.pack("<I", state))
    if rng.random() < 0.5:
        cpu.write(own + 0x2D, bytes([0]))
    if rng.random() < 0.3:                              # a new move: +0x28 becomes 1
        cpu.write(REC + 0x58, struct.pack("<I", 0))
    for k in range(ROW_COUNT):
        row = ROWS + 0x38 * k
        if rng.random() < 0.3:
            cpu.write(row + 0x24, struct.pack("<I", 0x2000))
    for i in range(ROW_COUNT):
        lst = LISTS + 0x100 * i
        for r in range(0, 0xF0, 12):
            cmd = struct.unpack("<H", cpu.read(lst + r, 2))[0]
            if cmd == ai.END:
                break
            if cmd != ai.COMMON:
                if rng.random() < 0.05:
                    cpu.write(lst + r + 3, bytes([0x31]))
                elif rng.random() < 0.4:                     # open for the current frame
                    cpu.write(lst + r + 2, bytes([0, 0]))
                    cpu.write(lst + r + 9, bytes([0, 255]))
                elif rng.random() < 0.2:                     # opens on frame 1
                    last = rng.choice([5, 20, 70])
                    cpu.write(lst + r + 9, bytes([1, last, rng.choice([last, 0])]))
                if rng.random() < 0.1:
                    cpu.write(lst + r + 8, bytes([rng.choice([0x1C, 0x1D])]))
    for off, values in ((0x6E, (-1, 0, 2)), (0x68, (-5, 0, 5)), (0x29A, (0, 4096)), (0x20A, (5, 11, 12, 28, 29, 999)),
                        (0x6C, (-1, 0, 3)), (0x6A, (0, 1)), (0xC0, (0, 0, 1)), (0xD8, (0, 0, 1)),
                        (0x1CC, (0, 1)), (0x2C, (0, 0xDC, 0xDD, 300)), (0x216, (-1, 0, 3)), (0x25E, (0, 4096)),
                        (0x262, (0, 4096)), (0x25C, (0, 4096)), (0x24E, (0, 0x4000)), (0x208, (0, 1))):
        cpu.write(REC + off, struct.pack("<h", rng.choice(values)))


UPDATE_STALE = CALL_SP - 0x78 - 0x58 + 0x1C   # AiCollectCandidates' sp+0x1C when AiUpdate calls it


def case_update(cpu, rng) -> bool:
    setup_update(cpu, rng)
    stale = rng.choice([0x12345678, ROWS + 0x38 * rng.randrange(ROW_COUNT)])
    cpu.write(UPDATE_STALE, struct.pack("<I", stale))
    ram = snapshot(cpu)
    mine = ai_update.ai_update(ram, F0, stale)
    cpu.call(0x80059B78, F0, PADS, PADS + 2)
    got = struct.unpack("<2H", cpu.read(PADS, 4))
    return check(cpu, ram, "AiUpdate", got, mine, UPDATE_REGIONS)


MUTABLE = {   # record fields AiUpdate re-reads from memory after the probe points
    "h": {0x8F: None, 0x44: (-1, 0, 4, 5, 0x12), 0x46: (-1, 0, 3), 0x4C: (0, 1), 0x3A: (0, 1, 2), 0x6C: (-1, 0, 2),
          0x80: (0, 0x19, 0x1A, 0x30), 0x84: (0, 1, 0x13, 0x14), 0xD4: (0, 1), 0x68: (-3, -1, 0, 5, 0x24, 0x30),
          0x42: (-1, 0), 0x8A: (-1, 0), 0x38: (-1, 0, 5), 0x40: (-1, 3), 0x48: (-1, 2), 0x4A: (-1, 3),
          0x2A: (0, 0x2D0, 0x2D1), 0x208: (0, 1), 0x88: (0, 1), 0x20C: (0, 1), 0x214: (0, 1), 0x20E: (0, 1, 0x1F),
          0x20A: (5, 9, 10, 11, 0x1D, 999), 0x216: (-1, 0, 3), 0x6A: (0, 1), 0x50: (0, 1), 0x21A: (0, 1),
          0x1D2: (0, 50), 0x3C: (0, 1), 0x2E: (0, 0x1000, 0x2001, 0x4000, 0x4001, 0x6001), 0x94: None, 0x8C: (-1, 3)},
    "i": {0x14: (0, 1, 2, 3, 4, 5), 0x18: (1, 2, 3, 4, 5), 0x24: (-100, -11, -10, 0x32, 0x33), 0x1C: (100, 0xB86, 0xB87, 7001)},
    "I": {0x230: (0x842, 0x4, 0x204, 0x4C02, 0x1, 0x3, 0x80000 | 0x842, 0x200000, 0x605),
          0x234: (0x412, 0x217, 0x10F, 0x607, 0x706, 0x31F, 0), 0x224: (0x10, 0x1, 0x2, 0x80000, 0x400000, 0x404)},
    "B": {0x8F: (0, 1), 0x91: (0, 1), 0x200: (0, 1), 0x92: (0, 1), 0x94: (0, 1, 2, 3, 4, 5)},
}
WORD_FIELDS = (0x248, 0x24E, 0x250, 0x252, 0x254, 0x256, 0x258, 0x25A, 0x25C, 0x25E, 0x262, 0x272, 0x274, 0x27E,
               0x280, 0x284, 0x292, 0x296)


ATTACK_SCENARIOS = {                     # gates of the branches in _choose (probe 0x8005E568)
    "grounded": {0x208: 1, 0x88: 0, 0x50: 0},
    "stance": {0x208: 0, 0x274: 4096, 0x21A: 0},
    "hover": {0x208: 0, 0x46: 0},
    "chase": {0x208: 0, 0x46: -1, 0x20E: 1},
    "coming": {0x208: 0, 0x46: -1, 0x20E: 0, 0x20C: 1, 0x88: 0},
    "approach": {0x208: 0, 0x46: -1, 0x20E: 0, 0x20C: 0, 0x214: 0, 0x68: -1, 0x44: -1},
    "strafe": {0x208: 0, 0x46: -1, 0x20E: 0, 0x20C: 0, 0x214: 0, 0x68: -1, 0x44: 0},
    "wait": {0x208: 0, 0x46: -1, 0x20E: 0, 0x20C: 0, 0x214: 0, 0x68: 5},
}
ATTACK_BASE = {0x4C: 0, 0x44: -1, 0x21A: 0, 0x1D2: 0, 0x1D4: 100, 0x3A: 0, 0x6C: -1}


def attack_scenario(rng):
    name = rng.choice(list(ATTACK_SCENARIOS))
    writes = [(off, "<h", v) for off, v in {**ATTACK_BASE, **ATTACK_SCENARIOS[name]}.items()]
    writes.append((0x14, "<i", rng.choice([0, 1, 1, 2, 2, 3])))
    writes.append((ai.GAME_MODE - REC, "<I", rng.choice([0, 1, 5])))
    if name == "stance":
        writes.append((0x230, "<I", 0x4C02))
        writes.append((0x24, "<i", rng.choice([0, 0x32, 0x33])))
    else:
        writes.append((0x230, "<I", rng.choice([0x842, 0x4, 0x1, 0x3, 0x80000 | 0x842, 0x200000, 0x605])))
    return writes


MOVE_EDGES = [0x14, 0x7A, 0x1EB, 0x214, 0x666, 0xB33, 0xCC, 0x599, 0x11D, 0x199, 0x333, 0x27, 0x170, 0x218,
              0x22D, 0x241, 0x80, 0x90, 0xC0, 0x3C0, 0x50, 0x400, 0x5EB, 0x7D, 0x1F4]


def lcg_for_roll(rng):
    """A dynamic write: an LCG value that makes the next inline 12-bit roll land near a table edge."""
    v = max(0, rng.choice(MOVE_EDGES) + rng.choice([-1, 0]))
    target = v * 8 + rng.randrange(8)

    def value(read_u32):
        r = ((read_u32(ai.RAND_STATE) * 0x41C64E6D + 0x3039) & 0xFFFFFFFF) >> 16 & 0x7FFF
        return ((target - r) & 0x7FFF) | rng.getrandbits(17) << 15
    return value


def movement_scenario(rng):
    """Gates of the movement code (probe 0x800605F4)."""
    writes = [(ai.LCG - REC, "<I", lcg_for_roll(rng)), (0x8A, "<h", -1), (0x40, "<h", -1), (0x48, "<h", -1), (0x200, "B", 0),
              (0x38, "<h", rng.choice([-1, -1, 0, 5])), (0x50, "<h", 0), (0x4A, "<h", -1), (0x46, "<h", -1),
              (0x68, "<h", rng.choice([0, 0x23, 0x24, 0x30])), (0x14, "<i", rng.randint(0, 5)),
              (0x18, "<i", rng.randint(0, 5)), (0x3A, "<h", rng.choice([0, 2])),
              (0x27E, "<h", rng.choice([0, 4096])), (0x284, "<h", rng.choice([0, 4096])),
              (0x25C, "<h", rng.choice([0, 500, 4096])), (0x2A, "<h", rng.choice([0, 0x2D1])),
              (0x208, "<h", rng.choice([0, 1])), (0x3C, "<h", rng.choice([0, 1])),
              (0x224, "<I", rng.choice([0, 2, 0x10])), (0x234, "<I", rng.choice([0, 0x412])),
              (0x230, "<I", rng.choice([0, 0x80000]))]
    return writes


def react_scenario(rng):
    """Gates of the reaction dispatch (probe 0x8005C514)."""
    return [(0x216, "<h", -1), (0x88, "<h", 0), (0x6C, "<h", rng.choice([0, 3, 9])), (0x50, "<h", rng.choice([0, 1])),
            (0x94, "B", rng.randint(0, 6)), (0x20C, "<h", 1), (0x18, "<i", rng.randint(1, 3)),
            (0x8C, "<h", rng.choice([-1, 3])), (0x21A, "<h", 0), (0x6A, "<h", 0),
            (0x20A, "<h", rng.choice([4, 8, 9, 10, 11, 0x16, 0x1D])), (0x14, "<i", rng.randint(0, 4)),
            (0x1C, "<i", rng.choice([100, 0xB86, 0xB87])), (0x2E, "<h", rng.choice([0, 0x4000])),
            (0x224, "<I", rng.choice([0, 1, 0x400000])), (0x234, "<I", rng.choice([0x412, 0x217, 0x10F, 0x607])),
            (0x202, "<h", rng.choice([0, 1])), (0x20E, "<h", rng.choice([0, 0x1F]))]


def candidate_writes(rng):
    """A fresh candidate table (targets and branch rows from the random pools)."""
    n = rng.randint(0, 8)
    writes = [(ai.CANDIDATES - REC + 12 * k, "<IIh", (TARGETS + 0x38 * rng.randrange(32), BRANCHES + 12 * rng.randrange(32), 0))
              for k in range(n)]
    return writes + [(0x70, "<h", n), (0x72, "<h", 0)]


def choose_scenario(rng):
    """Gates of the attack choice (probe 0x8005E7C0)."""
    pick = lambda *v: rng.choice(v)
    writes = [(0x68, "<h", pick(-1, -1, 0, 5)), (0xD4, "<h", pick(0, 1)), (0x80, "<i", pick(0, 0x1A, 0x30)),
              (0x84, "<i", pick(0, 5, 0x14)), (0x6C, "<h", pick(-1, 0, 2)), (0x6A, "<h", 0), (0x8F, "B", pick(0, 0, 1)),
              (0x91, "B", pick(0, 0, 1)), (0x208, "<h", pick(0, 0, 1)), (0x88, "<h", 0), (0x50, "<h", 0),
              (0x2E, "<h", pick(0, 0x2000, 0x4001)), (0x274, "<h", pick(0, 4096)), (0x46, "<h", pick(-1, -1, 0)),
              (0x20E, "<h", pick(0, 0, 1)), (0x20C, "<h", pick(0, 0, 1)), (0x214, "<h", pick(0, 0, 1)),
              (0x44, "<h", pick(-1, -1, 0)), (0x14, "<i", pick(0, 1, 2, 3)), (0x18, "<i", pick(1, 2, 3, 4)),
              (0x24, "<i", pick(0, 0x33)), (0x21A, "<h", 0), (0x42, "<h", pick(-1, 0)), (0x7C, "<I", 0),
              (0x224, "<I", pick(0x10, 1)), (0x230, "<I", pick(0x842, 0x4C02, 0x1, 0x4, 0x204)),
              (F0 - REC + 0x16, "<h", pick(0, 2, 5, 6, 9, 13, 3)), (F0 - REC + 0xDB, "B", 0),
              (F1 - REC + 0xDB, "B", pick(0, 0, 1)), (F1 - REC + 0x16, "<h", pick(0, 3)), (F0 - REC + 0x122, "<h", 0),
              (F0 - REC + 0x3F4, "<i", pick(5, 100)), (F0 - REC + 0x3F8, "<i", 100)]
    for off in (0x248, 0x24E, 0x250, 0x252, 0x258, 0x27E, 0x280):
        writes.append((off, "<h", pick(0, 2048, 4096)))
    return writes + candidate_writes(rng)


def pick_movement_scenario(rng):
    """Gates of the random movement (probe 0x80060944); the first draw is the table roll."""
    return [(ai.LCG - REC, "<I", lcg_for_roll(rng)), (0x40, "<h", -1), (0x48, "<h", -1), (0x200, "B", 0),
            (0x68, "<h", rng.choice([0, 0x24])), (0x14, "<i", rng.randint(0, 5)), (0x18, "<i", rng.randint(0, 5)),
            (0x25C, "<h", rng.choice([0, 500, 4096])), (0x2A, "<h", rng.choice([0, 0x2D1])),
            (0x208, "<h", rng.choice([0, 1])), (0x224, "<I", rng.choice([0, 2])), (0x284, "<h", rng.choice([0, 4096])),
            (0x27E, "<h", rng.choice([0, 4096])), (0x3C, "<h", rng.choice([0, 1])),
            (0x230, "<I", rng.choice([0, 0x80000])), (0x234, "<I", rng.choice([0, 0x412]))] + candidate_writes(rng)


def make_mutation(rng, addr: int):
    """A random set of record writes, applied identically to the game and the port."""
    scenario = {0x8005E568: attack_scenario, 0x800605F4: movement_scenario, 0x8005C514: react_scenario,
                0x8005E7C0: choose_scenario, 0x80060944: pick_movement_scenario}.get(addr)
    if scenario is None:
        return []
    writes = scenario(rng) if rng.random() < 0.7 else []
    for fmt, fields in MUTABLE.items():
        for off, values in fields.items():
            if values and rng.random() < 0.3:
                writes.append((off, "<" + fmt, rng.choice(values)))
    for off in WORD_FIELDS:
        if rng.random() < 0.3:
            writes.append((off, "<h", rng.choice([0, 1000, 2048, 4096])))
    for fighter, off, fmt, values in ((F0, 0xDB, "B", (0, 1)), (F1, 0xDB, "B", (0, 1)), (F1, 0xDF, "B", (0, 1)),
                                      (F0, 0x16, "<h", (0, 3, 7, 9, 12)), (F1, 0x16, "<h", (0, 0x13, 4)),
                                      (F0, 0x122, "<h", (0, 3)), (F1, 0xA0, "<h", (6, 0x100))):
        if rng.random() < 0.2:
            writes.append((fighter - REC + off, fmt, rng.choice(values)))
    return writes


def pass_to_choice(rng):
    """At 0x8005C514: no reaction (+0x216 >= 0), skip the air-attack step, open the attack choice."""
    return [(0x216, "<h", 0), (0x50, "<h", 1), (0x4C, "<h", 0), (0x44, "<h", -1), (0x14, "<i", rng.choice([0, 1])),
            (0x21A, "<h", 0), (0x1D2, "<h", 0), (0x1D4, "<h", 100), (0x3A, "<h", 0), (ai.GAME_MODE - REC, "<I", 0),
            (0x20C, "<h", rng.choice([0, 1])), (0x18, "<i", rng.choice([1, 4]))]


def fail_choice(rng):
    """At 0x8005E7C0: nothing to execute, so the movement code runs."""
    return [(0x70, "<h", 0), (0x72, "<h", 0), (0x68, "<h", 5), (0x6C, "<h", 2), (0x8A, "<h", -1), (0x38, "<h", -1),
            (0x50, "<h", 0), (0x4A, "<h", -1), (0x48, "<h", -1), (0x46, "<h", -1)]


CHAINS = [
    [(0x8005C514, pass_to_choice), (0x8005E7C0, choose_scenario)],
    [(0x8005C514, pass_to_choice), (0x8005E7C0, fail_choice), (0x80060944, pick_movement_scenario)],
]


def run_chain(cpu, chain) -> list[int]:
    """Run AiUpdate in the game, stopping at each probe of `chain` to apply its writes; returns the
    probes reached. `chain` holds (address, resolved writes) pairs."""
    from unicorn.mips_const import UC_MIPS_REG_A0, UC_MIPS_REG_GP, UC_MIPS_REG_PC, UC_MIPS_REG_RA, UC_MIPS_REG_SP
    from psxcpu import RETURN_MAGIC
    uc = cpu.uc
    for i, value in enumerate((F0, PADS, PADS + 2)):
        uc.reg_write(UC_MIPS_REG_A0 + i, value)
    uc.reg_write(UC_MIPS_REG_SP, CALL_SP)
    uc.reg_write(UC_MIPS_REG_GP, cpu.gp)
    uc.reg_write(UC_MIPS_REG_RA, RETURN_MAGIC)
    pc, reached = 0x80059B78, []
    for addr, writes in chain:
        stops = []
        hook = uc.hook_add(UC_HOOK_CODE, lambda u, a, sz, _: (stops.append(a), u.emu_stop()), begin=addr, end=addr)
        try:
            cpu.run(pc)
        finally:
            uc.hook_del(hook)
        if not stops:
            return reached
        reached.append(addr)
        for off, fmt, value in writes():
            cpu.write(REC + off, struct.pack(fmt, *value) if isinstance(value, tuple) else struct.pack(fmt, value))
        pc = addr
    cpu.run(pc)
    if uc.reg_read(UC_MIPS_REG_PC) != RETURN_MAGIC:
        raise RuntimeError(f"AiUpdate chain stopped at {uc.reg_read(UC_MIPS_REG_PC):#x}")
    return reached


def case_update_chain(cpu, rng) -> bool:
    """Like case_update_probe, with several probes in sequence steering deep into the attack choice
    and the random movement."""
    setup_update(cpu, rng)
    if rng.random() < 0.5:
        go_attack(cpu, rng)
    stale = rng.choice([0x12345678, ROWS + 0x38 * rng.randrange(ROW_COUNT)])
    cpu.write(UPDATE_STALE, struct.pack("<I", stale))
    ram = snapshot(cpu)
    chain = rng.choice(CHAINS)
    plans = [(addr, make(rng)) for addr, make in chain]
    own_rows = struct.unpack("<I", cpu.read(struct.unpack("<I", cpu.read(F0 + 0x54, 4))[0] + 0xC, 4))[0]
    first = struct.unpack("<H", cpu.read(own_rows, 2))[0]
    if chain is CHAINS[0] and first not in (ai.END, ai.COMMON) and rng.random() < 0.5:
        row = own_rows - REC                  # a row open now into a bank-setup slot
        plans[-1][1].extend([(row + 2, "<H", 0), (row + 6, "<H", rng.choice([0x15, 0x3B])), (row + 9, "<BB", (0, 255)),
                             (0x42, "<h", -1), (0x50, "<h", 0), (0x224, "<I", 0x10), (0x2E, "<h", 0),
                             (0x208, "<h", 0), (0x68, "<h", -1), (0x44, "<h", -1), (0x14, "<i", rng.choice([0, 1, 2]))])
    resolved = {}
    order = []

    def make_probe(addr, writes):
        def probe(r, rec):
            order.append(addr)
            done = []
            for off, fmt, value in writes:
                if callable(value):
                    value = value(r.u32)
                done.append((off, fmt, value))
                data = struct.pack(fmt, *value) if isinstance(value, tuple) else struct.pack(fmt, value)
                base = (rec + off) & 0x1FFFFFFF
                r.data[base:base + len(data)] = data
            resolved[addr] = done
        return probe
    mine = ai_update.ai_update(ram, F0, stale, {addr: make_probe(addr, w) for addr, w in plans})
    reached = run_chain(cpu, [(addr, (lambda a=addr: resolved.get(a, []))) for addr, _ in plans])
    if reached != order[:len(reached)] or len(order) != len(reached):
        log.info("AiUpdate chain: the game reaches %s, the port %s", [hex(a) for a in reached], [hex(a) for a in order])
        return False
    got = struct.unpack("<2H", cpu.read(PADS, 4))
    return check(cpu, ram, "AiUpdate chain", got, mine, UPDATE_REGIONS)


def case_update_probe(cpu, rng) -> bool:
    """Run to a probe point, mutate the record the same way in the game and the port, finish both."""
    from unicorn.mips_const import UC_MIPS_REG_PC
    from psxcpu import RETURN_MAGIC
    setup_update(cpu, rng)
    stale = rng.choice([0x12345678, ROWS + 0x38 * rng.randrange(ROW_COUNT)])
    cpu.write(UPDATE_STALE, struct.pack("<I", stale))
    ram = snapshot(cpu)
    addr = rng.choice([0x8005E568, 0x8005C514, 0x800605F4, 0x8005E7C0, 0x8005E7C0, 0x80060944, 0x80060944])
    writes = make_mutation(rng, addr)
    hit = []

    resolved = []

    def probe(r, rec):
        hit.append(1)
        for off, fmt, value in writes:
            if callable(value):
                value = value(r.u32)
            resolved.append((off, fmt, value))
            data = struct.pack(fmt, *value) if isinstance(value, tuple) else struct.pack(fmt, value)
            base = (rec + off) & 0x1FFFFFFF
            r.data[base:base + len(data)] = data
    mine = ai_update.ai_update(ram, F0, stale, {addr: probe})
    if not run_until(cpu, 0x80059B78, addr, F0, PADS, PADS + 2):
        if hit:
            log.info("AiUpdate probe: the port reaches %#x, the game does not", addr)
            return False
        got = struct.unpack("<2H", cpu.read(PADS, 4))
        return check(cpu, ram, "AiUpdate (no probe)", got, mine, UPDATE_REGIONS)
    if not hit:
        log.info("AiUpdate probe: the game reaches %#x, the port does not", addr)
        return False
    for off, fmt, value in resolved:
        cpu.write(REC + off, struct.pack(fmt, *value) if isinstance(value, tuple) else struct.pack(fmt, value))
    cpu.run(addr)
    if cpu.uc.reg_read(UC_MIPS_REG_PC) != RETURN_MAGIC:
        log.info("AiUpdate probe: stopped at %#x", cpu.uc.reg_read(UC_MIPS_REG_PC))
        return False
    got = struct.unpack("<2H", cpu.read(PADS, 4))
    return check(cpu, ram, f"AiUpdate probe {addr:#x}", got, mine, UPDATE_REGIONS)


BALL_CPU = []
BALL = 0x801F1400


def ball_cpu():
    """A second harness with volley.ovl (Tekken Ball) loaded."""
    if not BALL_CPU:
        cpu = load_release(overlay="volley")
        cpu.write(0x800756A4, struct.pack("<2I", 0x03E00008, 0x24020000))
        cpu.r3000_divide(0x800B49D0)          # the line intercept divides by the fighters' x difference
        BALL_CPU.append(cpu)
    return BALL_CPU[0]


def case_update_ball(_cpu, rng) -> bool:
    """AiUpdate in Tekken Ball (mode 7): the ball projection, distance, back-dash and attack filter."""
    cpu = ball_cpu()
    setup_update(cpu, rng)
    cpu.write(ai.GAME_MODE, struct.pack("<I", 7))
    cpu.write(ai_update.BALL_OBJECT, struct.pack("<I", BALL))
    cpu.write(BALL + 0x68, struct.pack("<3i", rng.randint(-8000, 8000), rng.randint(-3000, 0), rng.randint(-8000, 8000)))
    x0 = rng.randint(-6000, 6000)
    x1 = x0 + rng.choice([0, 1, -1, rng.randint(1, 12000)])   # 0: the projection divides by zero
    for fighter, x in ((F0, x0), (F1, x1)):
        cpu.write(fighter + ai_update.FIGHTER_X, struct.pack("<i", x))
        cpu.write(fighter + ai_update.FIGHTER_Z, struct.pack("<i", rng.randint(-6000, 6000)))
    cpu.write(F0 + 0x12, struct.pack("<h", rng.choice([0, 1])))
    stale = rng.choice([0x12345678, ROWS + 0x38 * rng.randrange(ROW_COUNT)])
    cpu.write(UPDATE_STALE, struct.pack("<I", stale))
    ram = snapshot(cpu)
    mine = ai_update.ai_update(ram, F0, stale)
    cpu.call(0x80059B78, F0, PADS, PADS + 2)
    got = struct.unpack("<2H", cpu.read(PADS, 4))
    return check(cpu, ram, "AiUpdate (Tekken Ball)", got, mine,
                 UPDATE_REGIONS + [(ai_update.BALL_LINE, 0x14), (ai_update.BALL_CLOSER, 4)])


UPDATE_REGIONS = [FORCE_REGION, (ai.CANDIDATES, 12 * 180), (ai.AI_SELF, 4), (ai.AI_OPP, 4), (ai.AI_INDEX, 0x30),
                  (ai_update.THROW_ROWS, 48 * 4)]


def run_until(cpu, addr: int, stop: int, *args: int) -> bool:
    """Run the game routine until it first reaches `stop`; False when it returns first."""
    from unicorn.mips_const import UC_MIPS_REG_A0, UC_MIPS_REG_PC, UC_MIPS_REG_RA, UC_MIPS_REG_SP, UC_MIPS_REG_GP
    from psxcpu import RETURN_MAGIC
    uc = cpu.uc
    for i, value in enumerate(args):
        uc.reg_write(UC_MIPS_REG_A0 + i, value & 0xFFFFFFFF)
    uc.reg_write(UC_MIPS_REG_SP, CALL_SP)
    uc.reg_write(UC_MIPS_REG_GP, cpu.gp)
    uc.reg_write(UC_MIPS_REG_RA, RETURN_MAGIC)
    stops = []
    hook = uc.hook_add(UC_HOOK_CODE, lambda u, a, sz, _: (stops.append(a), u.emu_stop()), begin=stop, end=stop)
    try:
        cpu.run(addr)
    finally:
        uc.hook_del(hook)
    return bool(stops)


CASES = {"AiUpdateChain": case_update_chain, "AiUpdateBall": case_update_ball, "AiUpdate": case_update, "AiUpdateProbe": case_update_probe, "AiReset": case_reset, "AiInitRound": case_init_round, "Hooks": case_hooks, "AiCallHook": case_call_hook, "AiHookForBank": case_hook_for_bank,
         "AiScript": case_script, "AiPressCommand": case_press, "AiSideStep": case_side_step, "AiAfterAttack": case_after_attack,
         "AiExecuteCandidate": case_execute, "BranchOpenTo": case_branch_open, "WhiffPunish": case_whiff,
         "AiCollectCandidates": case_collect, "Filters": case_filter, "HintNeverOpen": case_hint_never}


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=500)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--only")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    cpu = load_release()
    patch_harness(cpu)
    failed = False
    for name, case in CASES.items():
        if args.only and name != args.only:
            continue
        bad = sum(not case(cpu, rng) for _ in range(args.cases))
        log.info("%s: %d cases, %d mismatches", name, args.cases, bad)
        failed |= bad > 0
    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
