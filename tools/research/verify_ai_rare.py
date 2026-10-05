#!/usr/bin/env python3
"""Reach the rare branches of ai_update.py and compare those frames with the game.

The port is run many times on random, steered states (with random record writes at probe points,
see verify_ai_sim.case_update_chain); a line tracer spots frames that execute a not yet covered
target line, and exactly those frames are then run in the game and compared.

Usage: python3 tools/research/verify_ai_rare.py [--attempts N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
import sys

import ai_sim as ai
import ai_update
import verify_ai_sim as v
from psxcpu import load_release
from verify_fight_sim import F0, ROW_COUNT, ROWS, snapshot

log = logging.getLogger("verify_ai_rare")

# (function, unique source snippet) of each branch the random tests rarely reach
TARGETS = [
    ("_crouch_and_actions", 'ram.put(rec + 4, "H", 0x8000)'),
    ("_action_mask", "return 0x38"),
    ("_counter", "ai.side_step(ram, rec, -1)"),
    ("_reaction_body", "return 4 if _draw(c, 0x25C) else 0"),
    ("_react", 'ram.put(rec + 0x8E, "B", 1)'),
    ("_react", "ai.side_step(ram, rec, -1)"),
    ("_evade", 'ram.put(rec + 0x94, "B", 3)'),
    ("_choose", "return None"),
    ("_vs_stance", "side = False"),
    ("_approach_attack", 'ram.put(rec + 0x98, "h", 1)'),
    ("_approach_attack", 'ram.put(rec + 0x46, "h", a + b + d + 1)'),
    ("_approach_attack", "ram.s16(br + 6) not in (0x1EE, 0x6A3))"),
    ("_approach_attack", 'ram.put(rec + 0x44, "h", 0x12)'),
    ("_last_resort", "n = _mark(c"),
]


def target_lines() -> dict[int, tuple[str, str]]:
    """Source line of each target (the first match of the snippet inside its function)."""
    lines = open(ai_update.__file__).read().splitlines()
    found = {}
    for func, snippet in TARGETS:
        start = next(i for i, t in enumerate(lines) if t.startswith(f"def {func}("))
        for i in range(start + 1, len(lines)):
            if lines[i].startswith("def "):
                raise ValueError(f"{snippet!r} not in {func}")
            if snippet in lines[i]:
                found[i + 1] = (func, snippet)
                break
    return found


def pre_throw(rng):
    """Writes at 0x8005A9DC (before the throw section) for the early branches."""
    pick = lambda *vals: rng.choice(vals)
    return [(v.F0 - v.REC + 0x74, "<h", 0), (v.F0 - v.REC + 0x1A4, "<I", 0), (v.F0 - v.REC + 0xDB, "B", 0),
            (0x224, "<I", pick(0x404, 0x4, 0x604, 0x205)), (0x201, "B", pick(0, 1)),
            (v.F0 - v.REC + 0x60, "<H", pick(0x200, 0)), (0x2, "<h", pick(1, 3)), (0x68, "<h", pick(-1, 3)),
            (0x20A, "<h", pick(5, 11, 999)), (0x234, "<I", pick(0x10F, 0x412, 0)), (0x22C, "<I", pick(0, 0x10000)),
            (0x14, "<i", pick(0, 1, 3)), (0x18, "<i", pick(1, 2, 4)), (0x8A, "<h", -1)]


def lcg_before(value: int, draws: int) -> int:
    """The LCG value that yields `value` after `draws` steps (x = 5x + 3 is invertible mod 2^32)."""
    for _ in range(draws):
        value = (value - 3) * 0xCCCCCCCD & 0xFFFFFFFF
    return value


def counter_side(rng):
    """At 0x8005B994: an attack arriving in 9-11 frames, no counter-attack or duck, word 18 passes."""
    return [(0x28, "<h", 0), (0x2C, "<h", 0), (0x52, "<h", 0), (0x20C, "<h", 1), (0x216, "<h", rng.choice([0, 2])),
            (0x18, "<i", rng.choice([2, 3])), (0x8F, "B", 0), (0x25E, "<h", 0), (0x50, "<h", 1),
            (0x25C, "<h", 4096), (0x20A, "<h", rng.choice([9, 10, 11])), (0x2E, "<h", 0), (0x224, "<I", 0x10)]


def reaction_4_9(rng):
    """At 0x8005C514: reaction kinds 4 and 9 (the low parry is a 1-in-64 draw)."""
    return [(0x216, "<h", -1), (0x88, "<h", 0), (0x6C, "<h", 3), (0x94, "B", 0), (0x20C, "<h", 1), (0x18, "<i", 2),
            (0x8C, "<h", 3), (0x20A, "<h", rng.choice([9, 10, 11])), (0x6A, "<h", 1), (0x22C, "<I", 0),
            (0x20E, "<h", 0), (0x202, "<h", 0), (0x258, "<h", rng.choice([0, 4096])), (0x2E, "<h", 0),
            (0x224, "<I", 0x10), (0x50, "<h", 0), (0x234, "<I", 0x412), (0x25C, "<h", 4096), (0x1DC, "<I", 0),
            (0x292, "<h", 0), (0x230, "<I", 0x842), (v.F0 - v.REC + 0xDB, "B", 0), (v.F0 - v.REC + 0x40, "<h", 0),
            (ai.LCG - v.REC, "<I", rng.getrandbits(32))] + v.candidate_writes(rng)


CHOICE_BASE = [(0x6C, "<h", -1), (0x80, "<i", 0), (0x84, "<i", 0), (0x8F, "B", 0), (0x91, "B", 0), (0xD4, "<h", 0),
               (0x230, "<I", 0x842), (0x20A, "<h", 999), (v.F1 - v.REC + 0xDB, "B", 0), (v.F1 - v.REC + 0xDF, "B", 0),
               (v.F1 - v.REC + 0x16, "<h", 0), (v.F1 - v.REC + 0xA0, "<h", 0x100), (0x208, "<h", 0), (0x46, "<h", -1),
               (0x20E, "<h", 0), (0x20C, "<h", 0), (0x214, "<h", 0), (0x88, "<h", 0), (0x280, "<h", 0),
               (ai.GAME_MODE - v.REC, "<I", 0), (0x224, "<I", 0x10), (v.F0 - v.REC + 0xDB, "B", 0)]


def wait_neutral(rng):
    """At 0x8005E7C0: still waiting; the 4-in-4096 neutral move (second draw after the probe)."""
    return CHOICE_BASE + [(0x68, "<h", 5), (0x14, "<i", rng.choice([0, 1, 2])),
                          (ai.LCG - v.REC, "<I", lcg_before(rng.getrandbits(20) << 12 | rng.randint(0, 3), 1))] \
        + v.candidate_writes(rng)


def stance_hint(rng):
    """At 0x8005E7C0: opponent in stance, band 3+, slow approach, the 1-in-8 hint-bit-0 pick."""
    return CHOICE_BASE + [(0x230, "<I", 0x4C02), (0x274, "<h", 4096), (0x14, "<i", 3), (0x24, "<i", 0),
                          (ai.LCG - v.REC, "<I", lcg_before(rng.getrandbits(29) << 3, 2))] + v.candidate_writes(rng)


def approach(rng):
    """At 0x8005E7C0: nothing urgent, waiting over; the approach attack tree."""
    return CHOICE_BASE + [(0x68, "<h", -1), (0x44, "<h", -1), (0x91, "B", rng.choice([0, 1])),
                          (0x24E, "<h", rng.choice([0, 4096])), (0x42, "<h", 0), (0x14, "<i", rng.choice([0, 1, 2])),
                          (0x250, "<h", 0), (0x252, "<h", 0), (0x27E, "<h", rng.choice([0, 4096])),
                          (ai.LCG - v.REC, "<I", rng.getrandbits(32))] + v.candidate_writes(rng)


CPU = []                            # the harness, for scenarios that need runtime addresses


def own_list() -> int:
    """The branch list of the CPU's running move."""
    cpu = CPU[0]
    move = struct.unpack("<I", cpu.read(v.F0 + 0x54, 4))[0]
    return struct.unpack("<I", cpu.read(move + 0xC, 4))[0], move


def bank_setup(rng):
    """At 0x8005E7C0: a row open now into a bank-setup slot (0x15 or 0x3B) for a bank with setups."""
    rows, _ = own_list()
    row = rows - v.REC
    return approach(rng) + [(0x42, "<h", -1), (0x50, "<h", 0), (0x2E, "<h", 0), (0x208, "<h", 0),
                            (v.F0 - v.REC + 0x16, "<h", rng.choice([0, 2, 5, 6, 9, 13])),
                            (v.F0 - v.REC + 0xA0, "<h", 0x100), (0x14, "<i", rng.choice([0, 1, 2])),
                            (row, "<HBBHHBBBB", (0x0020, 0, 0, 0, rng.choice([0x15, 0x3B]), 0, 0, 255, 0)),
                            (row + 12, "<H10x", (ai.END,))]


def frame_one_rows(rng):
    """At 0x8005B994: a new attack move whose list holds 11 rows opening on frame 1 (+0x1A4 list)."""
    rows, move = own_list()
    writes = [(0x28, "<h", 1), (0xC0, "<h", 0), (0xD8, "<h", 0), (0x52, "<h", 0), (0x1CC, "<h", 0),
              (0x27E, "<h", rng.choice([0, 4096])), (move - v.REC + 0x2D, "B", 5)]
    for k in range(11):
        writes.append((rows - v.REC + 12 * k, "<HBBHHBBBB", (0x0020, 0, 0, 0, rng.randrange(16), 0, 1, 7, 7)))
    writes.append((rows - v.REC + 12 * 11, "<H10x", (ai.END,)))
    return writes


def reaction_1(rng):
    """At 0x8005C514: kind 1 from a long guard delay (1/32) or a long announcement (word 17)."""
    return [(0x216, "<h", -1), (0x88, "<h", 0), (0x6C, "<h", rng.choice([9, 3])), (0x94, "B", 0), (0x20C, "<h", 1),
            (0x18, "<i", 2), (0x8C, "<h", 3), (0x20A, "<h", 20), (0x6A, "<h", 0), (0x22C, "<I", 0),
            (0x20E, "<h", 0x1F), (0x92, "B", 0), (0x254, "<h", 0), (0x256, "<h", 0), (0x202, "<h", 0),
            (0x258, "<h", 0), (0x25A, "<h", 4096), (0x50, "<h", 0), (0x1DC, "<I", 0), (0x292, "<h", 0),
            (0x230, "<I", 0x842), (v.F0 - v.REC + 0x40, "<h", 0), (ai.LCG - v.REC, "<I", rng.getrandbits(32))]


def turned_away(rng):
    """At 0x8005C514: no reaction; the CPU faces away at close range (bank 7 walks)."""
    return [(0x216, "<h", 0), (0x50, "<h", 0), (0x2E, "<h", 0x7000), (0x18, "<i", 1), (0x208, "<h", 0),
            (0x27E, "<h", 4096), (v.F1 - v.REC + 0xDB, "B", 0), (v.F0 - v.REC + 0x16, "<h", 7)]


def force_leader(rng):
    """At 0x8005C514: Tekken Force, the player fights another enemy, the pattern draw passes."""
    return [(0x216, "<h", 0), (0x50, "<h", 1), (ai.GAME_MODE - v.REC, "<I", 8), (ai.FORCE_TARGETS - v.REC, "<i", 0),
            (v.F0 - v.REC + 0x1F, "B", 1), (v.F0 - v.REC + 0x1E, "B", 0), (0x32C, "<I", 0x801F1000),
            (0x801F1000 - v.REC, "<hhh", (0, 0, 4096))]


def long_approach(rng):
    """At 0x800605F4: a long approach (+0x3A = 2) close up, the 32-in-4096 step back."""
    return [(0x8A, "<h", -1), (0x38, "<h", 5), (0x14, "<i", 1), (0x200, "B", 0), (0x27E, "<h", 0),
            (0x20C, "<h", 0), (0x3A, "<h", 2), (0x18, "<i", rng.choice([1, 2])),
            (ai.LCG - v.REC, "<I", lcg_before(rng.getrandbits(27) << 5, 1))]


def parry(rng):
    """At 0x8005C514: reactions 7 and 8 (parry scripts of banks 1, 7 and the low parries)."""
    return [(0x216, "<h", -1), (0x88, "<h", 0), (0x6C, "<h", 3), (0x94, "B", 0), (0x20C, "<h", 1), (0x8C, "<h", 3),
            (0x20A, "<h", rng.choice([4, 5, 6, 7, 10, 22, 24, 26])), (0x228, "<I", 0), (0x6A, "<h", 0), (0x1C, "<i", 100),
            (0x18, "<i", 1), (0x234, "<I", rng.choice([0x10F, 0x412, 0x217])), (0x292, "<h", 4096),
            (v.F0 - v.REC + 0xDB, "B", 0), (v.F1 - v.REC + 0xDB, "B", 0), (v.F0 - v.REC + 0x3E, "<h", 0),
            (v.F0 - v.REC + 0x16, "<h", rng.choice([1, 2, 3, 7, 9, 10])), (v.F0 - v.REC + 0x40, "<h", 0)]


def evade(rng):
    """At 0x8005C514: reaction 3 in evasion states 3 and 5."""
    return [(0x216, "<h", -1), (0x88, "<h", 0), (0x6C, "<h", 3), (0x94, "B", rng.choice([3, 5])), (0x20C, "<h", 1),
            (0x18, "<i", 2), (0x8C, "<h", -1), (0x21A, "<h", 0), (0x1C, "<i", 100), (0x224, "<I", 0x10),
            (0x20A, "<h", rng.choice([8, 12, 20, 40])), (0x14, "<i", rng.choice([2, 3])),
            (v.F0 - v.REC + 0x3E, "<h", rng.choice([0, 0x5000])), (v.F0 - v.REC + 0x40, "<h", 0),
            (v.F1 - v.REC + 0x16, "<h", 0), (ai.LCG - v.REC, "<I", rng.getrandbits(32))]


def unmark(rng):
    """At 0x8005E7C0: +0xD4 drops marked string moves (targets with +0x24 bit 13)."""
    writes = CHOICE_BASE + [(0xD4, "<h", 1)]
    n = rng.randint(1, 6)
    for k in range(n):
        writes.append((ai.CANDIDATES - v.REC + 12 * k, "<IIh",
                       (v.ROWS + 0x38 * rng.randrange(v.ROW_COUNT), v.BRANCHES + 12 * rng.randrange(32), 1)))
    for k in range(v.ROW_COUNT):
        writes.append((v.ROWS - v.REC + 0x38 * k + 0x24, "<I", rng.choice([0, 0x2000])))
    return writes + [(0x70, "<h", n), (0x72, "<h", n)]


def air_middle(rng):
    """At 0x8005E7C0: the opponent is in the middle of an air move at distance band 2."""
    _, _ = own_list()
    move = struct.unpack("<I", CPU[0].read(v.F1 + 0x54, 4))[0]
    return CHOICE_BASE + [(0x280, "<h", 4096), (v.F1 - v.REC + 0xDB, "B", 1), (move - v.REC + 0x19, "BB", (10, 30)),
                          (v.F1 - v.REC + 0x58, "<h", rng.choice([20, 25, 30])), (0x2E, "<h", 0), (0x14, "<i", 2)]


def pass_to_new_move(rng):
    """At 0x8005A9DC: no throw, stance, queued row, neutral action, hook or held guard."""
    return [(v.F0 - v.REC + 0x74, "<h", 0), (v.F0 - v.REC + 0x1A4, "<I", 0), (0x224, "<I", 0x10), (0x74, "<I", 0),
            (0x78, "<I", 0), (0x6A, "<h", 0), (v.F1 - v.REC + 0xD2, "B", 0)]


def kind_9(rng):
    """At 0x8005C514: the 1-in-64 low parry with neutral candidates to execute."""
    writes = reaction_4_9(rng)
    writes = [w for w in writes if w[0] not in (0x258, 0x70, 0x72) and not (ai.CANDIDATES - v.REC <= w[0] < 0)]
    n = rng.randint(1, 4)
    for k in range(n):
        target = v.TARGETS + 0x38 * k
        writes += [(target - v.REC + 4, "<I", 1), (target - v.REC + 0x2D, "B", 0),
                   (ai.CANDIDATES - v.REC + 12 * k, "<IIh", (target, v.BRANCHES + 12 * rng.randrange(32), 0))]
    return writes + [(0x258, "<h", 4096), (0x70, "<h", n), (0x72, "<h", 0)]


CHAINS = [[(0x8005A9DC, pre_throw)], [(0x8005B994, counter_side)], [(0x8005C514, reaction_4_9)],
          [(0x8005C514, v.pass_to_choice), (0x8005E7C0, wait_neutral)],
          [(0x8005C514, v.pass_to_choice), (0x8005E7C0, stance_hint)],
          [(0x8005C514, v.pass_to_choice), (0x8005E7C0, approach)],
          [(0x8005C514, v.pass_to_choice), (0x8005E7C0, bank_setup)], [(0x8005A9DC, pass_to_new_move), (0x8005B994, frame_one_rows)],
          [(0x8005A9DC, pass_to_new_move), (0x8005C514, kind_9)],
          [(0x8005C514, reaction_1)], [(0x8005C514, turned_away)], [(0x8005C514, force_leader)],
          [(0x800605F4, long_approach)], [(0x8005C514, parry)], [(0x8005C514, evade)],
          [(0x8005C514, v.pass_to_choice), (0x8005E7C0, unmark)],
          [(0x8005C514, v.pass_to_choice), (0x8005E7C0, air_middle)]] + v.CHAINS


def attempt(cpu, rng, targets, tracer_hits):
    """One steered frame; returns (hit lines, the data to replay it) or None."""
    kind = rng.random()
    if kind < 0.6:
        chain = CHAINS[attempt.n % len(CHAINS)]
        attempt.n += 1
    else:
        addr = rng.choice([0x8005E568, 0x8005C514, 0x800605F4, 0x8005E7C0, 0x80060944])
        chain = [(addr, lambda r, a=addr: v.make_mutation(r, a))]
    plans = [(addr, make(rng)) for addr, make in chain]
    stale = rng.choice([0x12345678, ROWS + 0x38 * rng.randrange(ROW_COUNT)])
    return plans, stale


def executable_lines() -> set[int]:
    """Every line of ai_update.py that belongs to executable code (from the code objects)."""
    import types
    found = set()

    def walk(code):
        found.update(line for _, _, line in code.co_lines() if line)
        for const in code.co_consts:
            if isinstance(const, types.CodeType):
                walk(const)
    for obj in vars(ai_update).values():
        if isinstance(obj, types.FunctionType) and obj.__code__.co_filename == ai_update.__file__:
            walk(obj.__code__)
    lines = open(ai_update.__file__).read().splitlines()
    return {n for n in found if not lines[n - 1].strip().startswith(("def ", '"""', "#"))
            and "# unreachable" not in lines[n - 1]}


attempt.n = 0


def run_port(ram, stale, plans, lines):
    """Run the port with probes; returns (result, set of target lines executed, resolved writes)."""
    hits, resolved = set(), {}

    def make_probe(addr, writes):
        def probe(r, rec):
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

    src = ai_update.__file__

    def tracer(frame, event, arg):
        if frame.f_code.co_filename != src:
            return None
        if event == "line" and frame.f_lineno in lines:
            hits.add(frame.f_lineno)
        return tracer
    sys.settrace(tracer)
    try:
        result = ai_update.ai_update(ram, F0, stale, {addr: make_probe(addr, w) for addr, w in plans})
    finally:
        sys.settrace(None)
    return result, hits, resolved


def ball_frame(cpu, rng, open_lines, lines) -> bool:
    """A Tekken Ball frame (as verify_ai_sim.case_update_ball), compared when it reaches new lines."""
    import io
    buf = io.StringIO()
    state = rng.getstate()
    stale_rng = random.Random()
    stale_rng.setstate(state)
    # run the port first with a tracer on a copy made by the verifier's own setup
    ram_hits = set()
    src = ai_update.__file__

    def tracer(frame, event, arg):
        if frame.f_code.co_filename != src:
            return None
        if event == "line" and frame.f_lineno in open_lines:
            ram_hits.add(frame.f_lineno)
        return tracer
    sys.settrace(tracer)
    try:
        ok = v.case_update_ball(None, rng)
    finally:
        sys.settrace(None)
    for line in sorted(ram_hits):
        log.info("ball frame: line %d %r reached, %s", line, lines[line][1], "match" if ok else "MISMATCH")
    open_lines -= ram_hits
    return ok


def sim_ram(base):
    """A private copy of a RAM snapshot."""
    return type(base)(bytearray(base.data))


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--attempts", type=int, default=20000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--auto", action="store_true", help="target every executable line of ai_update.py")
    parser.add_argument("--inner", type=int, default=40, help="random-number retries per state at 0x8005E7C0")
    args = parser.parse_args()
    rng = random.Random(args.seed)
    cpu = load_release()
    v.patch_harness(cpu)
    CPU.append(cpu)
    if args.auto:
        lines = {n: ("line", open(ai_update.__file__).read().splitlines()[n - 1].strip()) for n in executable_lines()}
    else:
        lines = target_lines()
    open_lines = set(lines)
    ball = None
    bad = 0
    for n in range(args.attempts):
        if not open_lines:
            break
        use_ball = args.auto and rng.random() < 0.05
        if use_ball:
            ball = ball or v.ball_cpu()
            if not ball_frame(ball, rng, open_lines, lines):
                bad += 1
            continue
        v.setup_update(cpu, rng)
        steer = rng.random()
        if steer < 0.3:
            v.go_attack(cpu, rng)
        elif steer < 0.5:
            v.go_react(cpu, rng)
        elif steer < 0.7:
            v.go_deep(cpu, rng)
        plans, stale = attempt(cpu, rng, lines, None)
        cpu.write(v.UPDATE_STALE, struct.pack("<I", stale))
        base = snapshot(cpu)
        tries = args.inner if plans[-1][0] == 0x8005E7C0 else 1
        for _ in range(tries):
            ram = sim_ram(base)
            mine, hits, resolved = run_port(ram, stale, plans, open_lines)
            if hits:
                break
            # same state, other random numbers at the last probe
            plans[-1][1][:] = [w for w in plans[-1][1] if w[0] not in (ai.LCG - v.REC, ai.RAND_STATE - v.REC)] + [
                (ai.LCG - v.REC, "<I", rng.getrandbits(32)), (ai.RAND_STATE - v.REC, "<I", rng.getrandbits(32))]
        if not hits:
            continue
        reached = v.run_chain(cpu, [(addr, (lambda a=addr: resolved.get(a, []))) for addr, _ in plans])
        got = struct.unpack("<2H", cpu.read(v.PADS, 4))
        ok = reached == [a for a, _ in plans if a in resolved] and v.check(cpu, ram, "AiUpdate rare", got, mine,
                                                                          v.UPDATE_REGIONS)
        for line in sorted(hits):
            log.info("attempt %d: line %d %s %r reached, %s", n, line, *lines[line], "match" if ok else "MISMATCH")
        bad += not ok
        open_lines -= hits
    for line in sorted(open_lines):
        log.info("not reached: line %d %s %r", line, *lines[line])
    log.info("%d targets reached, %d mismatches, %d not reached", len(lines) - len(open_lines), bad, len(open_lines))
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
