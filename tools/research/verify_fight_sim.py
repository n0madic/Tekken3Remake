#!/usr/bin/env python3
"""Compare fight_sim.py ports with the game's routines, byte for byte.

For each case the harness memory is prepared with two fighter records filled with
random but plausible values and pointers to random move rows. The same memory is
copied into a `fight_sim.Ram`, the original routine runs in the harness and the port
on the copy, and the fighter records plus any scratch areas are compared.

Usage: python3 tools/research/verify_fight_sim.py [--cases N] [--seed S] [--only NAME]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import fight_sim as sim
from psxcpu import load_release

F0, F1 = 0x800A96F0, 0x800AAF7C
ROWS = 0x801E0000          # 16 random move rows
SLOT = 0x801E1000
ROW_COUNT = 16

log = logging.getLogger("verify_fight_sim")


def random_row(rng: random.Random) -> bytes:
    row = bytearray(0x38)
    struct.pack_into("<I", row, 0x00, 0x801E2000 + 0x40 * rng.randint(0, 7))      # anim pointer
    struct.pack_into("<I", row, 0x04, rng.choice([0x842, 0x2829, 0x1052, 0x4, 0x404, 0x4C02, 0x10842]))
    struct.pack_into("<I", row, 0x08, rng.choice([0x217, 0x412, 0x10F, 0x607, 0x800, 0x0]) | rng.choice([0, 0x40000, 0x200000]))
    struct.pack_into("<I", row, 0x0C, 0x801E3000)
    struct.pack_into("<H", row, 0x10, rng.choice([3, 40, 153]))
    struct.pack_into("<h", row, 0x12, rng.choice([0, 0x7FFF, -0x8000, 0x4000]))
    struct.pack_into("<H", row, 0x14, rng.randint(0, 40) | rng.choice([0, 0x4000, 0x8000, 0xC000]))
    struct.pack_into("<h", row, 0x16, rng.choice([0, 0, 120, -80]))
    length = rng.randint(10, 90)
    row[0x18] = length
    if rng.random() < 0.3:
        row[0x19], row[0x1A] = rng.randint(1, length // 2), rng.randint(length // 2, length)
    row[0x1B] = rng.choice([0, rng.randint(1, length)])
    struct.pack_into("<I", row, 0x24, rng.choice([0, 0x10000000, 0x100, 0x1000, 0x400000, 0x800, 0x80000, 0x2000]))
    struct.pack_into("<I", row, 0x28, 0x801E3100)
    row[0x2C] = rng.choice([0, 5, 10])
    if rng.random() < 0.6:
        row[0x2D] = rng.randint(1, length)
        row[0x2E] = rng.randint(row[0x2D], length)
    struct.pack_into("<H", row, 0x32, rng.randint(0, 600))
    struct.pack_into("<H", row, 0x34, rng.choice([0, rng.randint(1, 30)]))
    return bytes(row)


def random_fighter(rng: random.Random) -> dict[str, int]:
    rows = [ROWS + 0x38 * i for i in range(ROW_COUNT)]
    values = {}
    for name, (off, ctype) in sim.FIELDS.items():
        size = sim.SIZES[ctype]
        if ctype == "void*":
            continue
        if size == 1:
            values[name] = rng.choice([0, 0, 1, rng.randint(0, 255)])
        elif size == 2:
            values[name] = rng.choice([0, 1, -1, rng.randint(-0x8000, 0x7FFF), rng.randint(0, 60)])
        else:
            values[name] = rng.choice([0, rng.randint(-5000, 5000), rng.randint(0, 0x7FFFFFFF)])
    values.update({
        "poseMove": rng.choice(rows), "moveRow": rng.choice(rows + [0]), "rootMove": rng.choice(rows),
        "pushTable": 0x801E3200, "poseFrame": rng.randint(0, 90), "rootFrame": rng.randint(1, 90),
        "entryFrame": rng.randint(0, 90), "frameStep": rng.choice([1, 1, -1, 0]), "transition": rng.randint(0, 0x2B),
        "branchKind": rng.randint(0, 4), "index": 0, "active": 1, "throwState": rng.choice([0, 0, 1, -1, 2]),
        "reaction": 0x80010CE8 + 42 * rng.randint(0, 632), "health": rng.choice([0, 0xA0000, 0x640000]),
    })
    return values


def prepare(cpu, rng: random.Random) -> None:
    cpu.write(ROWS, b"".join(random_row(rng) for _ in range(ROW_COUNT)))
    cpu.write(0x801E2000, bytes(rng.randrange(256) for _ in range(0x200)))
    cpu.write(0x801E3000, struct.pack("<6H", 0xC000, 0, 0, 3, 0, 0))
    cpu.write(0x801E3100, bytes([2, 10, 0, 0]))
    cpu.write(0x801E3200, bytes(rng.randrange(256) for _ in range(0x40)))
    for base, index in ((F0, 0), (F1, 1)):
        ram = sim.Ram(bytearray(sim.RAM_SIZE))
        fighter = sim.Fighter(ram, base)
        for name, value in random_fighter(rng).items():
            setattr(fighter, name, value)
        fighter.index = index
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    cpu.write(SLOT, bytes(0x2C))


def snapshot(cpu) -> sim.Ram:
    return sim.Ram(cpu.read(0x80000000, sim.RAM_SIZE))


def compare(cpu, ram: sim.Ram, regions: list[tuple[int, int]], label: str) -> bool:
    ok = True
    for base, size in regions:
        game = cpu.read(base, size)
        mine = bytes(ram.data[base & 0x1FFFFFFF:(base & 0x1FFFFFFF) + size])
        if game != mine:
            ok = False
            diffs = [i for i in range(size) if game[i] != mine[i]]
            names = {off: n for n, (off, _) in sim.FIELDS.items()}
            where = [(hex(i), names.get(i, "")) for i in diffs[:8]]
            log.info("%s: %d differing bytes at %s", label, len(diffs), where)
    return ok


def case_hit_classify(cpu, rng) -> bool:
    prepare(cpu, rng)
    cpu.write(sim.FIGHTER_DISTANCE, struct.pack("<I", rng.randint(0, 3000)))
    cpu.write(sim.CHIP_GLOBAL, struct.pack("<I", rng.choice([0, 0, 1])))
    ram = snapshot(cpu)
    cpu.call(0x80044D24, F0, F1, SLOT)
    sim.hit_classify(ram, sim.Fighter(ram, F0), sim.Fighter(ram, F1), SLOT)
    return compare(cpu, ram, [(SLOT, 0x2C), (F0, sim.FIGHTER_SIZE)], "HitClassify")


def case_move_start(cpu, rng) -> bool:
    prepare(cpu, rng)
    cpu.write(0x800AFF50, struct.pack("<I", rng.choice([0, 0, 5, 7, 8])))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    label = f"MoveStartOrAdvance (transition {f.transition}, kind {f.branchKind}, juggle {f.juggleCount})"
    cpu.call(0x8002F600, F0, F1)
    sim.move_start_or_advance(f, sim.Fighter(ram, F1))
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (sim.AIR_FRAMES, 8)], label)


BANK = 0x801E4000
INDEX = 0x801E4100
LISTS = 0x801E8000


def random_command(rng: random.Random) -> int:
    kind = rng.random()
    if kind < 0.45:
        dirs = rng.choice([0, 0, 1 << (rng.randint(1, 9) + 4), 0x3FE0 & rng.getrandbits(14)])
        return dirs | rng.choice([0, 1, 2, 4, 8, 3, 5, 10, 12, 0x10, 0x11, 0x13, 0x1F])
    if kind < 0.55:
        return rng.choice([0xC001, 0xC002, 0xC00D if False else 0xC001])
    if kind < 0.75:
        return rng.choice([0xC00E + rng.randint(0, 0x3E), 0xC7FF + rng.randint(0, 0x28)])
    if kind < 0.85:
        return 0xC00C
    return rng.randint(0, 0xBFFF)


def build_bank(cpu, rng: random.Random) -> None:
    header = bytearray(0x40)
    struct.pack_into("<I", header, 0xC, INDEX)
    cpu.write(BANK, bytes(header))
    cpu.write(INDEX, b"".join(struct.pack("<I", ROWS + 0x38 * (s % ROW_COUNT)) for s in range(4023)))
    for base in (0x800AE0E8, 0x800AE0EC):
        cpu.write(base, struct.pack("<I", BANK))
    for i in range(ROW_COUNT):
        lst = LISTS + 0x100 * i
        rows = bytearray()
        for _ in range(rng.randint(0, 6)):
            cmd = random_command(rng)
            first = rng.randint(0, 60)
            row = bytearray(12)
            struct.pack_into("<H", row, 0, cmd)
            row[2] = rng.choice([0, 0, 0, rng.randint(1, 0x73)])
            row[3] = rng.choice([0, 0, rng.randint(0, 0x4B)])
            struct.pack_into("<H", row, 4, rng.randint(0, 3000))
            struct.pack_into("<H", row, 6, rng.choice([0, 21]) if cmd == 0xC00C else rng.randint(0, 4022))
            row[8] = rng.choice([rng.randint(0, 0x2B), 0x2C, 0x1C, 0x21, 0x80 | rng.randint(0, 0x2B), 0x40])
            row[9], row[10] = first, first + rng.randint(0, 40)
            row[11] = rng.choice([rng.randint(0, 90), 0xFF])
            rows += row
        end = bytearray(12)
        struct.pack_into("<H", end, 0, 0xC000)
        struct.pack_into("<H", end, 6, rng.randint(0, 4022))
        end[8] = rng.randint(0, 0x2B)
        f = rng.randint(0, 60)
        end[9], end[10], end[11] = f, f + rng.randint(0, 30), rng.randint(0, 90)
        rows += end
        cpu.write(lst, bytes(rows))
        cpu.write(ROWS + 0x38 * i + 0xC, struct.pack("<I", lst))


def case_branch_step(cpu, rng) -> bool:
    prepare(cpu, rng)
    build_bank(cpu, rng)
    cpu.write(0x800AFF50, struct.pack("<I", rng.choice([0, 0, 5, 7, 7, 8])))
    for k in range(2):
        cpu.write(sim.BALL_DRIFT + 6 * k + 5, bytes([rng.choice([0, rng.randint(1, 40)])]))
    ram = snapshot(cpu)
    for base in (F0, F1):
        f = sim.Fighter(ram, base)
        f.playerIndex = 0 if base == F0 else 1
        f.moveRow = rng.choice([0, 0, 0, ROWS])
        f.stepCooldown = rng.choice([0, 0, rng.randint(0, 30)])
        f.inDir = 1 << (rng.randint(1, 9) + 4)
        f.inPressed = rng.choice([0, 0, rng.randint(0, 15)])
        f.inHeld = rng.randint(0, 15)
        f.inHistIndex = rng.randint(0, 59)
        for i in range(60):
            f.set_at(0x41C + i, "B", rng.randint(1, 9) | (rng.choice([0, 0, 0, rng.randint(1, 15)]) << 4))
        f.poseFrame = rng.randint(0, 70)
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    label = f"MoveBranchStep (frame {f.poseFrame}, step {f.frameStep})"
    cpu.call(0x8002DC3C, F0, F1)
    sim.move_branch_step(f, sim.Fighter(ram, F1))
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (sim.SITUATION, 12)], label)


def case_input_match(cpu, rng) -> bool:
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    kind = rng.random()
    if kind < 0.7:
        cmd = rng.choice([0xC00E + rng.randint(0, 0x3E), 0xC7FF + rng.randint(0, 0x28)])
        table = sim.SEQ_TABLE_A + 4 * (cmd - 0xC00E) if cmd < 0xC7FF else sim.SEQ_TABLE_B + 4 * (cmd - 0xC7FF)
        seq = ram.u32(table)
        steps = []
        a = seq + 2
        while ram.u16(a):
            steps.append(ram.u16(a))
            a += 2
        entries = []
        for step in steps:
            entries += [rng.randint(1, 9)] * rng.choice([0, 0, 1, 2, 5])
            buttons = (step >> 8) & 0xF
            entries.append((step & 0xF or 5) | ((buttons if rng.random() < 0.9 else rng.randint(0, 15)) << 4))
    else:
        cmd = rng.choice([0xC001, 0xC002])
        d = 6 if cmd == 0xC001 else 4
        entries = [d] * rng.randint(1, 8) + [5] * rng.randint(1, 12) + [d] * rng.randint(1, 3)
    if rng.random() < 0.2 and entries:
        entries[rng.randrange(len(entries))] = rng.randint(1, 0xFF)
    idx = rng.randint(0, 59)
    for i in range(60):
        f.set_at(0x41C + i, "B", rng.randint(1, 9))
    for back, e in enumerate(reversed(entries[-60:])):
        f.set_at(0x41C + (idx - back) % 60, "B", e)
    f.inHistIndex = idx
    last = entries[-1] if entries else 5
    f.inPressed = (last >> 4) if rng.random() < 0.8 else rng.randint(0, 15)
    f.inHeld = f.inPressed | rng.choice([0, 0, rng.randint(0, 15)])
    row = SLOT
    ram.put(row, "H", cmd)
    cpu.write(0x80000000, bytes(ram.data[:0x200000]))
    game = cpu.call(0x8002CE7C, F0, row, 1 << ((last & 0xF) + 4), f.inPressed) & 0xFFFF
    mine = sim.input_match(f, row, 1 << ((last & 0xF) + 4), f.inPressed)
    if bool(game) != mine:
        log.info("InputMatch %#x entries %s: game %d mine %d", cmd, [hex(e) for e in entries], game, mine)
    return bool(game) == mine


def case_branch_condition(cpu, rng) -> bool:
    prepare(cpu, rng)
    ram = snapshot(cpu)
    for base in (F0, F1):
        f = sim.Fighter(ram, base)
        f.state = rng.choice([0x842, 0x2829, 0x1052, 0x4, 0x404, 0x40, 0x20, 0x80, 0x280, 0x4C02, 0x2])
        f.relAngle = rng.randint(0, 0x7FFF)
        f.headingDelta = rng.randint(0, 0xFFFF)
        f.facingQuadrant = rng.randint(0, 3)
        f.oppQuadrant = rng.randint(0, 3)
        f.dist = rng.randint(0, 3000)
        f.distAdj = rng.randint(0, 3000)
        f.attack = rng.choice([0x412, 0x217, 0x10F, 0x607])
        f.guard = rng.choice([0, 8, 0x10, 0x18])
    ram.put(sim.SITUATION, "i", rng.choice([0, 0, -1, rng.randint(2, 0x13)]))
    row = SLOT
    ram.put(row + 3, "B", rng.randint(0, 0x44))
    ram.put(row + 4, "H", rng.randint(0, 3000))
    cpu.write(0x80000000, bytes(ram.data))
    f, o = sim.Fighter(ram, F0), sim.Fighter(ram, F1)
    label = f"BranchCondition type {ram.u8(row + 3):#x}"
    game = cpu.call(0x8002E310, row, F0, F1) & 0xFFFFFFFF
    mine = sim.branch_condition(ram, row, f, o)
    ok = bool(game) == mine
    if not ok:
        log.info("%s: game %d mine %d", label, game, mine)
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (sim.SITUATION, 12)], label) and ok


DUST_RING = 0x8009F648


def case_move_physics(cpu, rng) -> bool:
    prepare(cpu, rng)
    cpu.write(0x800AFF50, struct.pack("<I", rng.choice([0, 0, 5, 7, 8])))
    for k in range(2):
        first = rng.randint(0, 20)
        cpu.write(sim.BALL_DRIFT + 6 * k, struct.pack("<hBBB", rng.randint(-0x8000, 0x7FFF), rng.choice([0, rng.randint(1, 255)]),
                                                      first, first + rng.randint(0, 30)))
    cpu.write(sim.FIGHTER_DISTANCE, struct.pack("<I", rng.choice([rng.randint(0, 0x1000), rng.randint(0, 3000)])))
    cpu.write(sim.FACE_TIMER, struct.pack("<i", rng.randint(0, 3)))
    for base in (sim.STEP_ACCUM_X, sim.STEP_ACCUM_Z):
        cpu.write(base, struct.pack("<2i", rng.randint(-0x800, 0x800), rng.randint(-0x800, 0x800)))
    ram = snapshot(cpu)
    for base in (F0, F1):
        f = sim.Fighter(ram, base)
        for name in ("throwPartner", "lastAttacker", "lastHitTarget", "oppIndex"):
            setattr(f, name, rng.randint(0, 1))
        for name in ("inThrow", "wasHitThisMove", "contact", "slideToPoint", "ballistic", "hitClean", "isCpu",
                     "juggleCount", "inReaction", "stepKind", "humanGuard", "moveChanged", "inAir"):
            setattr(f, name, rng.choice([0, 0, 1]))
        f.charId = rng.choice([0, 7, 0x11, 0x14, rng.randint(0, 0x20)])
        f.costumeSlot = rng.randint(-2, 0x3A)
        f.slideState = rng.choice([0, 0, 1, 2])
        f.trackMode = rng.randint(0, 12)
        f.stateClass = rng.choice([9, rng.randint(0, 15)])
        f.airKind = rng.choice([1, 5, rng.randint(0, 8)])
        f.airVelY = rng.randint(-60, 60)
        f.airSpeed = rng.randint(-200, 200)
        f.groundOffset = rng.randint(-100, 100)
        f.posY = rng.randint(-300, 50)
        f.inHistIndex = rng.randint(0, 59)
        f.pushTableFrames = rng.choice([0, rng.randint(0, 20)])
        f.pushFrames = rng.choice([0, rng.randint(-2, 20)])
        f.recoverFrames = rng.choice([0, rng.randint(-2, 60)])
        f.recoverMash = rng.choice([0, rng.randint(-2, 60)])
        f.turnFrames = rng.choice([0, rng.randint(-2, 20)])
        f.moveFrame = rng.randint(0, 20)
        f.attackAlert = rng.choice([0, rng.randint(-1, 9)])
        f.pushRepeatTimer = rng.choice([0, rng.randint(-1, 20)])
        f.powerTimer = rng.choice([0, rng.randint(-1, 5)])
        f.velX, f.velY, f.velZ = (rng.randint(-200, 200) for _ in range(3))
        f.holdFrames = rng.choice([-1, 0, 3])
        f.slideTargetX, f.slideTargetZ = rng.randint(-3000, 3000), rng.randint(-3000, 3000)
        f.set_at(0xBC, "B", rng.choice([0, 0, 1]))
        for i in range(60):
            f.set_at(0x41C + i, "B", rng.randint(1, 9) | (rng.choice([0, 0, rng.randint(1, 15)]) << 4))
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    label = f"FighterMovePhysics (track {f.trackMode}, slide {f.slideState}, ballistic {f.ballistic})"
    ring = cpu.read(DUST_RING, 2)
    cpu.call(0x8003F330, F0)
    events = sim.move_physics(f)
    dust = cpu.read(DUST_RING, 2) != ring
    ok = dust == any(e[0] == "landing_dust" for e in events)
    if not ok:
        log.info("%s: landing dust game %s mine %s", label, dust, events)
    regions = [(F0, sim.FIGHTER_SIZE), (sim.STEP_ACCUM_X, 8), (sim.STEP_ACCUM_Z, 8), (sim.CAMERA_SHAKE, 4)]
    return compare(cpu, ram, regions, label) and ok


def case_arena_bounds(cpu, rng) -> bool:
    prepare(cpu, rng)
    mode = rng.choice([0, 0, 5, 7, 8])
    cpu.write(0x800AFF50, struct.pack("<I", mode))
    cpu.write(sim.BOUND_RAMP, struct.pack("<3i", *(rng.choice([0, 2000, rng.randint(0, 2000)]) for _ in range(3))))
    cpu.write(sim.BOUND_RAMP_STEP, struct.pack("<3i", *(rng.randint(0, 60) for _ in range(3))))
    cpu.write(sim.THROW_LINK, struct.pack("<i", rng.randint(0, 1)))
    ram = snapshot(cpu)
    for base in (F0, F1):
        f = sim.Fighter(ram, base)
        for name in ("throwPartner", "lastAttacker", "lastHitTarget", "oppIndex"):
            setattr(f, name, rng.randint(0, 1))
        span = 0x1600 if mode == 7 else rng.choice([0x3000, 320000])
        f.rootX, f.rootZ = rng.randint(-span, span), rng.randint(-span, span)
        f.rootY = rng.randint(-0x1400, 0)
        f.placedX, f.placedZ = rng.randint(-0x3000, 0x3000), rng.randint(-0x3000, 0x3000)
        f.dist = rng.choice([rng.randint(0, 0x3000), rng.randint(0x1C00, 0x2400)])
        f.targetDir = rng.randint(-0x8000, 0x7FFF)
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    label = f"ArenaBounds (mode {mode}, dist {f.dist:#x})"
    cpu.call(0x80043394, F0)
    sim.arena_bounds(f)
    regions = [(F0, sim.FIGHTER_SIZE), (F1, sim.FIGHTER_SIZE), (sim.BOUND_RAMP, 24)]
    return compare(cpu, ram, regions, label)


def case_body_separate(cpu, rng) -> bool:
    prepare(cpu, rng)
    mode = rng.choice([0, 0, 5, 7, 8])
    cpu.write(0x800AFF50, struct.pack("<I", mode))
    cpu.write(sim.THROW_COUNT, bytes([rng.randint(0, 3)]))
    cpu.write(sim.PAIR_DISTANCE + 0x10, struct.pack("<I", rng.choice([rng.randint(0, 3000), rng.randint(0, 5000)])))
    ram = snapshot(cpu)
    cx, cz = rng.randint(-0x4000, 0x4000), rng.randint(-0x4000, 0x4000)
    facing_each_other = rng.random() < 0.4
    for base in (F0, F1):
        f = sim.Fighter(ram, base)
        f.active = rng.choice([1, 1, 1, 0])
        f.invulnerable = rng.choice([0, 0, 0, 1, 2])
        f.set_at(0xD9, "B", rng.choice([0, 0, 1]))
        f.rootX, f.rootZ = cx + rng.randint(-700, 700), cz + rng.randint(-700, 700)
        f.rootY = rng.choice([0, rng.randint(-600, 0)])
        f.posX, f.posZ = f.rootX + rng.randint(-300, 300), f.rootZ + rng.randint(-300, 300)
        f.facing = rng.randint(-0x8000, 0x7FFF)
        if facing_each_other:
            side = -1 if base == F0 else 1
            f.rootX, f.rootZ = cx + rng.randint(-100, 100), cz + side * rng.randint(150, 400)
            f.facing = (0 if base == F0 else -0x8000) + rng.randint(-0x800, 0x800)
        for i in range(sim.BODY_POINT_COUNT):
            point = sim.BODY_POINTS + 16 * i
            f.set_at(point, "H", (f.rootX + rng.randint(-250, 250)) & 0xFFFF)
            f.set_at(point + 4, "H", (f.rootY + rng.randint(-1200, 0)) & 0xFFFF)
            f.set_at(point + 8, "H", (f.rootZ + rng.randint(-250, 250)) & 0xFFFF)
            f.set_at(point + 12, "H", rng.choice([0, rng.randint(40, 220)]))
        prev = sim.PREV_ROOT + 0x10 * f.index
        moved = rng.choice([0, 0, 20, 200])
        for k, v in ((4, f.rootX), (8, f.rootY), (12, f.rootZ)):
            ram.put(prev + k, "H", (v + rng.randint(-moved, moved)) & 0xFFFF)
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    cpu.write(sim.PREV_ROOT, bytes(ram.data[sim.PREV_ROOT & 0x1FFFFFFF:(sim.PREV_ROOT & 0x1FFFFFFF) + 0x20]))
    ram = snapshot(cpu)
    label = f"BodySeparate (mode {mode})"
    cpu.call(0x8004401C, F0, F1)
    sim.body_separate(sim.Fighter(ram, F0), sim.Fighter(ram, F1))
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (F1, sim.FIGHTER_SIZE)], label)


ANIM_BANK = 0x80100000
_ANIM_CACHE: dict = {}


def _anim_bank():
    if not _ANIM_CACHE:
        import motion
        data = (motion.ROOT / "work" / "jp_rev1" / "bns" / "074_divmot00.bin").read_bytes()
        bank = motion.parse_bank(data)
        offs = sorted({bank.move_row(r)[0] for r in range(bank.move_count) if bank.move_row(r)[0] < motion.COMMON_FLAG})
        _ANIM_CACHE.update(data=data, offs=[bank.anim_offset(w) for w in offs])
    return _ANIM_CACHE


def case_transition_blend(cpu, rng) -> bool:
    import psxcpu
    prepare(cpu, rng)
    build_bank(cpu, rng)
    anim = _anim_bank()
    cpu.write(ANIM_BANK, anim["data"])
    for i in range(ROW_COUNT):
        cpu.write(ROWS + 0x38 * i, struct.pack("<I", ANIM_BANK + rng.choice(anim["offs"])))
    cpu.write(sim.BLEND_HOLD, struct.pack("<i", rng.choice([0, 0, 0, 0, 2])))
    cpu.write(sim.REPLAY_PLAYBACK, struct.pack("<i", rng.choice([0, 0, 0, 0, 1])))
    for a in sim.REPLAY_FLAGS:
        cpu.write(a, struct.pack("<i", rng.choice([0] * 12 + [1])))
    cpu.write(sim.DECODED_ROOT_DY, struct.pack("<h", rng.randint(-2000, 2000)))
    ram = snapshot(cpu)
    rows = [ROWS + 0x38 * i for i in range(ROW_COUNT)]
    f = sim.Fighter(ram, F0)
    f.playerIndex = 0
    f.scale = rng.choice([4096, 4096, 3800, 4400])
    f.blendMode = rng.randint(0, 3)
    f.blendFrames = rng.randint(0, 16)
    f.blendCounter = rng.randint(-1, f.blendFrames + 1)
    f.blendActive = rng.choice([0, 0, 1])
    f.lastPoseMove = rng.choice([f.poseMove] + rows)
    f.blendSrcMove, f.blendDstMove = rng.choice(rows), rng.choice(rows)
    f.moveChanged = rng.choice([0, 1, 1])
    f.branchKind = rng.choice([0, 1, 2, 3, 4])
    f.moveRow = rng.choice([0, rng.choice(rows)])
    f.moveSlot = rng.randint(0, 4022)
    f.entryFrame = rng.randint(0, 60)
    f.transition = rng.choice([2, 0x12, 0x19, 0x2C, 5, 0x24])
    f.set_at(0x88, "I", rng.choice([0, 0, 0, 0x100]))
    f.set_at(0xBA, "B", rng.choice([0, 0, 0, 1]))
    f.set_at(0xBB, "B", rng.choice([0, 0, 0, 1]))
    f.transBit6 = rng.choice([0, 0, 0, 1])
    f.juggleCount = rng.choice([0, 0, 0, 1])
    for i in range(17):
        for e in range(9):
            f.set_at(sim.PREV_LOCAL + 0x20 * i + 2 * e, "h", rng.randint(-4096, 4096))
    for k in range(3):
        f.set_at(sim.PREV_ROOT_DISP + 2 * k, "h", rng.randint(-3000, 3000))
    cpu.write(0x80000000, bytes(ram.data))
    cpu.write(psxcpu.STACK_TOP - 0x8000, bytes(0x8000))
    label = f"FighterTransitionBlend (mode {f.blendMode}, active {f.blendActive})"
    cpu.call(0x8003C4C4, F0)
    sim.transition_blend(f, sim.Fighter(ram, F1))
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (sim.BLEND_HOLD, 4)], label)


MAT_A, MAT_B, MAT_T, MAT_O = 0x801E5000, 0x801E5040, 0x801E5080, 0x801E50C0


def case_blend_apply(cpu, rng) -> bool:
    import pose
    import motion
    tab = pose.ExeTables(motion.load_exe())
    base = pose.flat(pose.euler_to_matrix(*(rng.randint(-0x8000, 0x7FFF) for _ in range(3)), tab))
    delta = [rng.choice([0, rng.randint(-600, 600), rng.randint(-8192, 8192)]) for _ in range(9)]
    weight = rng.choice([0, 4096, rng.randint(0, 4096)])
    cpu.write(MAT_A, struct.pack("<9h", *delta) + bytes(14))
    cpu.write(MAT_B, struct.pack("<9h", *base) + bytes(14))
    cpu.call(0x8003A980, MAT_A, MAT_B, weight, MAT_T)
    cpu.call(0x800762B0, MAT_T, MAT_O)
    game_t = list(struct.unpack("<9h", cpu.read(MAT_T, 18)))
    game_o = list(struct.unpack("<9h", cpu.read(MAT_O, 18)))
    mine_t = sim.matrix_add_scaled(delta, base, weight)
    mine_o = sim.matrix_orthonormalize(mine_t)
    ok = game_t == mine_t and game_o == mine_o
    if not ok:
        log.info("BlendApply w=%d delta=%s base=%s\n game %s %s\n mine %s %s", weight, delta, base, game_t, game_o, mine_t, mine_o)
    return ok


REPLAY_STATE = 0x8009C050


def case_root_update(cpu, rng) -> bool:
    prepare(cpu, rng)
    anim = _anim_bank()
    cpu.write(ANIM_BANK, anim["data"])
    for i in range(ROW_COUNT):
        cpu.write(ROWS + 0x38 * i, struct.pack("<I", ANIM_BANK + rng.choice(anim["offs"])))
    cpu.write(REPLAY_STATE, struct.pack("<i", 0))
    cpu.write(sim.REPLAY_PLAYBACK, struct.pack("<i", 0))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    f.scale = rng.choice([4096, 3800, 4400])
    f.tiltX, f.tiltZ = rng.choice([0, rng.randint(-0x8000, 0x7FFF)]), rng.choice([0, rng.randint(-0x8000, 0x7FFF)])
    f.heading, f.facing = rng.randint(-0x8000, 0x7FFF), rng.randint(-0x8000, 0x7FFF)
    f.rootDx, f.rootDy, f.rootDz = (rng.randint(-2000, 2000) for _ in range(3))
    f.posX, f.posY, f.posZ = (rng.randint(-50000, 50000) for _ in range(3))
    f.rootX, f.rootY, f.rootZ = (rng.randint(-50000, 50000) for _ in range(3))
    f.airPhase = rng.choice([0, 0, 1, 2])
    f.blendMode = rng.choice([0, 1, 2, 3])
    f.blendFrames = rng.choice([0, rng.randint(1, 16)])
    f.blendCounter = rng.randint(0, 16)
    f.set_at(sim.BLEND_ROOT_DELTA + 2, "h", rng.randint(-3000, 3000))
    f.anchorDirty = rng.choice([0, 1])
    f.rootFrame = rng.randint(0, 80)
    f.frameStep = rng.choice([1, -1, 0])
    cpu.write(0x80000000, bytes(ram.data))
    cpu.call(0x8003AC1C, F0)
    cpu.call(0x8003AD48, F0)
    sim.root_reanchor(f)
    sim.root_update(f)
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE)], "RootReanchor+RootUpdate")


PROJECTILE_BUFFER = 0x801E8000


def case_hit_test(cpu, rng) -> bool:
    prepare(cpu, rng)
    cpu.write(0x800AFF50, struct.pack("<I", rng.choice([0, 0, 5, 7, 8])))
    projectile = rng.random() < 0.2
    cpu.write(0x801E3100, bytes([rng.randint(0x18, 0x1F) if projectile else rng.randint(0, 0x17), 10, 0, 0]))
    cpu.write(sim.PROJECTILES, struct.pack("<I", PROJECTILE_BUFFER))
    cpu.write(sim.PROJECTILE_SEGS[0], struct.pack("<2i", rng.randint(0, 3), rng.randint(0, 3)))
    ram = snapshot(cpu)
    att, dfn = sim.Fighter(ram, F0), sim.Fighter(ram, F1)
    cx, cy, cz = rng.randint(-3000, 3000), rng.randint(-1500, 0), rng.randint(-3000, 3000)
    near = lambda: [cx + rng.randint(-600, 600), cy + rng.randint(-600, 600), cz + rng.randint(-600, 600)]
    for k in range(4):
        ram.data[(F0 & 0x1FFFFFFF) + sim.ATTACK_SEGS + 24 * k:][:24] = struct.pack("<6i", *near(), *near())
    buf = PROJECTILE_BUFFER & 0x1FFFFFFF
    for which in range(2):
        for k in range(3):
            o = buf + which * 0x780 + 0x3200 + 24 * k
            ram.data[o:o + 24] = struct.pack("<6i", *near(), *near())
    for k in range(sim.HURT_ZONE_COUNT):
        r = rng.randint(60, 300)
        o = (F1 & 0x1FFFFFFF) + sim.HURT_ZONES + 20 * k
        ram.data[o:o + 20] = struct.pack("<5i", *near(), r, r * r)
    att.activeSegs = rng.choice([0, 1, 2, 4, 5])
    att.attack = rng.choice([0x217, 0x412, 0x10F, 0x607, 0x800])
    dfn.state = rng.choice([0x842, 0x2829, 0x1052, 0x3884, 0x6042, 0x4C02])
    dfn.stateClass = rng.choice([0, 12, 1])
    for f in (att, dfn):
        f.invulnerable = rng.choice([0, 0, 0, 1])
        f.active = rng.choice([1, 1, 1, 0])
        f.hitCooldown = rng.choice([0, 0, 0, 3])
    for i in range(2):
        ram.put(F1 + sim.HIT_SLOTS + sim.HIT_SLOT_SIZE * i + 0x21, "B", rng.choice([0, 0, 1]))
    att.set_at(0x83, "B", rng.choice([0, 0, 0, 1]))
    att.set_at(0x84, "B", rng.choice([0, 0, 0, 1]))
    att.forcedHit = rng.choice([0, 0, 1])
    dfn.isCpu = rng.choice([0, 1])
    dfn.set_at(0xD6, "B", rng.choice([0, 1]))
    dfn.stepKind = rng.choice([0, 2])
    att.curSlot = rng.choice([0, 0x898, 5])
    for base in (F0, F1):
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    cpu.write(PROJECTILE_BUFFER, bytes(ram.data[buf:buf + 0x3200 + 0x780 + 0x60]))
    cpu.call(0x80044304, F0, F1)
    sim.hit_test(ram, att, dfn)
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (F1, sim.FIGHTER_SIZE)], "HitTest")



def case_hit_apply(cpu, rng) -> bool:
    prepare(cpu, rng)
    mode = rng.choice([0, 0, 5, 7, 8])
    cpu.write(0x800AFF50, struct.pack("<I", mode))
    cpu.write(sim.FIGHTER_DISTANCE, struct.pack("<I", rng.randint(0, 3000)))
    cpu.write(sim.CHIP_GLOBAL, struct.pack("<I", rng.choice([0, 0, 1])))
    cpu.write(sim.NO_DAMAGE[0], struct.pack("<I", rng.choice([0, 0, 0, 1])))
    cpu.write(sim.NO_DAMAGE[1], struct.pack("<I", rng.choice([0, 0, 0, 1])))
    cpu.write(sim.KO_STARTED, struct.pack("<I", rng.choice([0, 0, 1])))
    cpu.write(sim.PRACTICE_COUNTER, struct.pack("<2I", rng.choice([0, 1]), rng.choice([0, 1])))
    cpu.write(sim.FORCE_SCORE, struct.pack("<i", rng.randint(0, 100000)))
    ram = snapshot(cpu)
    att, f = sim.Fighter(ram, F0), sim.Fighter(ram, F1)
    f.index, att.index = 1, 0
    for name in ("oppIndex", "throwPartner", "lastAttacker", "lastHitTarget"):
        setattr(f, name, 0)
        setattr(att, name, 1)
    for k in range(2):
        slot = F1 + sim.HIT_SLOTS + sim.HIT_SLOT_SIZE * k
        raw = bytearray(sim.HIT_SLOT_SIZE)
        struct.pack_into("<hhh", raw, 0x18, rng.randint(0, 13), rng.choice([0, rng.randint(-40, 40)]), rng.choice([0, 0, 5]))
        struct.pack_into("<h", raw, 0x1E, rng.choice([0, rng.randint(-20, 20)]))
        raw[0x20] = 0
        raw[0x21] = rng.choice([0, 1, 1])
        for off in (0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x28):
            raw[off] = rng.choice([0, 0, 1])
        o = slot & 0x1FFFFFFF
        ram.data[o:o + sim.HIT_SLOT_SIZE] = raw
    f.gotHit = rng.choice([0, 1, 1])
    f.health = rng.choice([0, 0x10000, 0x280000, 0xA00000])
    f.healthMax = rng.choice([0x8C0000, 0xA00000])
    f.extraKind = rng.choice([0, 1, 2, 3])
    att.extraKind = rng.choice([0, 1, 2, 3])
    f.isCpu = rng.choice([0, 1])
    row = ram.u32(att.base + 0x54)
    ram.put(row + 0x32, "H", rng.choice([rng.randint(0, 600), 0x8000 | rng.randint(0, 40)]))
    ram.put(row + 0x34, "H", rng.choice([0, rng.randint(1, 30)]))
    for base in (F0, F1):
        off = base & 0x1FFFFFFF
        cpu.write(base, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    rows = ROWS & 0x1FFFFFFF
    cpu.write(ROWS, bytes(ram.data[rows:rows + 0x38 * ROW_COUNT]))
    cpu.call(0x80044634, F1)
    sim.hit_apply(ram, f, F0)
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (F1, sim.FIGHTER_SIZE), (sim.KO_STARTED, 4), (sim.FORCE_SCORE, 4)],
                   f"HitApply (mode {mode})")


BAKED = 0x801E9000                 # random attack record with baked points (8 KB)


def case_collision_shapes(cpu, rng) -> bool:
    prepare(cpu, rng)
    record = bytearray(rng.randrange(256) for _ in range(0x2000))
    for k in range(4):
        record[k] = rng.choice([0, rng.randint(0, 0x17), 0x13, rng.randint(0x18, 0x1F)])
    record[4] = rng.randrange(256)
    record[5] = (rng.randrange(16) << 4) | rng.randrange(16)
    cpu.write(BAKED, bytes(record))
    for k in range(2):
        cpu.write(sim.SEG_MODE + 4 * k, struct.pack("<i", rng.choice([0, 0, 1, 2, 3])))
    cpu.write(sim.SEG_END0, bytes(rng.randrange(256) for _ in range(0x60)))
    cpu.write(sim.SEG_STATE, struct.pack("<6i", *(rng.randint(-5000, 5000) for _ in range(6))))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    row = f.poseMove
    ram.put(row + 0x28, "I", BAKED)
    start = rng.randint(0, 20)
    ram.put(row + 0x2D, "B", start)
    ram.put(row + 0x2E, "B", start + rng.randint(0, 20))
    f.poseFrame = start + rng.randint(-3, 25)
    f.attackSegCount = rng.choice([0, 1, 2])
    f.bankType = rng.choice([4, 14, 0x13, 0, 2])
    f.charId = rng.choice([0x14, 0xE, 3])
    f.heading = rng.randint(-0x8000, 0x7FFF)
    f.facing = rng.choice([f.heading, rng.randint(-0x8000, 0x7FFF)])
    for i, name in enumerate(("rootX", "rootY", "rootZ", "posX", "posY", "posZ")):
        setattr(f, name, rng.randint(-20000, 20000))
    joints = f.base + sim.JOINTS
    for j in range(24):
        m = [rng.randint(-4096, 4096) for _ in range(9)]
        o = (joints + sim.JOINT_SIZE * j) & 0x1FFFFFFF
        ram.data[o:o + 0x20] = struct.pack("<9hh3i", *m, 0, *(rng.randint(-20000, 20000) for _ in range(3)))
    off = F0 & 0x1FFFFFFF
    cpu.write(F0, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    rows = ROWS & 0x1FFFFFFF
    cpu.write(ROWS, bytes(ram.data[rows:rows + 0x38 * ROW_COUNT]))
    cpu.call(0x80042204, F0)
    sim.collision_shapes_update(ram, f)
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (sim.SEG_END0, 0xB0)], "CollisionShapesUpdate")


EVENTS = 0x801EB000                # random event list


def case_move_events(cpu, rng) -> bool:
    prepare(cpu, rng)
    words = []
    for _ in range(rng.randint(0, 8)):
        hi = rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 20, 21, 30, 45, 61, 62, 80])
        lo = rng.choice([rng.randint(0, 23), rng.randint(0, 255)]) if hi in (6, 7, 8, 9, 10) else rng.randint(0, 255)
        if hi in (6, 7, 8, 9, 10):
            lo = rng.randint(0, 23)
        words += [rng.randint(1, 40), hi << 8 | lo]
    words += [0, 0]
    cpu.write(EVENTS, struct.pack(f"<{len(words)}H", *words))
    ram = snapshot(cpu)
    f = sim.Fighter(ram, F0)
    ram.put(f.poseMove + 0x20, "I", rng.choice([EVENTS, EVENTS, 0]))
    f.poseFrame = rng.randint(0, 40)
    f.set_at(sim.PREV_POSE_FRAME, "h", f.poseFrame - rng.choice([0, 1, 1, 3]))
    f.set_at(0x1C, "h", rng.choice([rng.randint(0, 0x36), 0x40]))
    f.playerIndex = 0
    off = F0 & 0x1FFFFFFF
    cpu.write(F0, bytes(ram.data[off:off + sim.FIGHTER_SIZE]))
    rows = ROWS & 0x1FFFFFFF
    cpu.write(ROWS, bytes(ram.data[rows:rows + 0x38 * ROW_COUNT]))
    cpu.call(0x80045B60, F0)
    sim.move_events(ram, f)
    return compare(cpu, ram, [(F0, sim.FIGHTER_SIZE), (sim.CAMERA_SHAKE, 4)], "MoveEvents")

CASES = {"MoveEvents": case_move_events, "CollisionShapes": case_collision_shapes, "HitApply": case_hit_apply, "HitTest": case_hit_test, "RootUpdate": case_root_update, "BlendApply": case_blend_apply, "TransitionBlend": case_transition_blend, "BodySeparate": case_body_separate, "ArenaBounds": case_arena_bounds, "FighterMovePhysics": case_move_physics, "BranchCondition": case_branch_condition, "InputMatch": case_input_match, "HitClassify": case_hit_classify, "MoveStartOrAdvance": case_move_start, "MoveBranchStep": case_branch_step}


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=500)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--only")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    cpu = load_release()
    # SoundPlayFighter: no SPU in the harness; patched to `jr ra; li v0, 0` (a code hook that
    # rewrites PC crashes Unicorn after many calls)
    cpu.write(0x800756A4, struct.pack("<2I", 0x03E00008, 0x24020000))
    # HitSpawnEffect and the KO sequence (effects, sound) return at once; HitApply reports them as events.
    # Effect spawners (joint effects, sparks) as well: MoveEvents reports them as events.
    for addr in (0x80044B78, 0x80032030, 0x80076E58, 0x80076EB8):
        cpu.write(addr, struct.pack("<2I", 0x03E00008, 0))
    # force.ovl FUN_800B2E60 (the Tekken Force player record) returns fighter 0.
    cpu.write(0x800B2E60, struct.pack("<3I", 0x3C02800A, 0x03E00008, 0x344296F0))
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
