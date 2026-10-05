#!/usr/bin/env python3
"""Compare fight_math.py with the game's routines in the CPU harness.

Random fighter states are written into the two fighter records of the harness
(field offsets from tools/ghidra/fighter_fields.tsv); each game routine is run and
its outputs compared with the Python port.

Usage: python3 tools/research/verify_fight_math.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
from pathlib import Path

import fight_math
from psxcpu import load_release

ROOT = Path(__file__).resolve().parents[2]
F0, F1 = 0x800A96F0, 0x800AAF7C
MOVE_ROW = 0x801F0000
SLOT = 0x801F0100
FighterRelativeAngles = 0x80043D2C
HitDamage = 0x80044E70
LaunchTrajectory = 0x8002F2C8
AIR_FRAMES = 0x80095B94
POSE_ROW = 0x801F0200
SIZES = {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4, "void*": 4}
FMT = {"u8": "<B", "s8": "<b", "u16": "<H", "s16": "<h", "u32": "<I", "s32": "<i", "void*": "<I"}

log = logging.getLogger("verify_fight_math")


def load_fields() -> dict[str, tuple[int, str]]:
    fields = {}
    for line in (ROOT / "tools" / "ghidra" / "fighter_fields.tsv").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        off, ctype, name = line.split("\t")[:3]
        if ctype in SIZES:
            fields[name] = (int(off, 16), ctype)
    return fields


class Record:
    def __init__(self, cpu, base: int, fields: dict[str, tuple[int, str]]) -> None:
        self.cpu, self.base, self.fields = cpu, base, fields

    def set(self, name: str, value: int) -> None:
        off, ctype = self.fields[name]
        mask = (1 << (8 * SIZES[ctype])) - 1
        self.cpu.write(self.base + off, (value & mask).to_bytes(SIZES[ctype], "little"))

    def get(self, name: str) -> int:
        off, ctype = self.fields[name]
        return struct.unpack(FMT[ctype], self.cpu.read(self.base + off, SIZES[ctype]))[0]


def check_angles(cpu, fields, exe, rng: random.Random) -> bool:
    f, o = Record(cpu, F0, fields), Record(cpu, F1, fields)
    state = {
        "rootX": rng.randint(-40000, 40000), "rootZ": rng.randint(-40000, 40000),
        "heading": rng.randint(0, 0xFFFF), "dist": rng.choice([0x100, 0x1000]),
        "fixedFacing": int(rng.random() < 0.1), "fixedFacingSide": rng.randint(0, 1),
        "aimDir": 0x1234, "oppAimDir": 0x4321,
    }
    other = {"rootX": state["rootX"] + rng.randint(-9000, 9000), "rootZ": state["rootZ"] + rng.randint(-9000, 9000),
             "heading": rng.randint(0, 0xFFFF)}
    for k, v in state.items():
        f.set(k, v)
    for k, v in other.items():
        o.set(k, v)
    cpu.call(FighterRelativeAngles, F0, F1)
    mine = dict(state)
    fight_math.relative_angles(mine, other, exe)
    names = ["targetDir", "oppToSelfDir", "oppHeading", "headingDelta", "facingQuadrant", "oppHeadingDelta",
             "oppQuadrant", "relAngle", "oppRelAngle", "aimDir", "oppAimDir"]
    game = {n: f.get(n) & 0xFFFF for n in names}
    ok = all(game[n] == mine[n] & 0xFFFF for n in names)
    if not ok:
        log.info("angles mismatch %s: %s", state, {n: (game[n], mine[n] & 0xFFFF) for n in names if game[n] != mine[n] & 0xFFFF})
    return ok


def check_damage(cpu, fields, rng: random.Random) -> bool:
    d, a = Record(cpu, F0, fields), Record(cpu, F1, fields)
    active = rng.choice([0, rng.randint(1, 40)])
    cpu.write(MOVE_ROW, bytes(0x38))
    cpu.write(MOVE_ROW + 0x2D, bytes([active]))
    dstate = {"damage": rng.randint(-60, 60), "powerTimer": int(rng.random() < 0.2), "poseFrame": rng.randint(1, 60),
              "juggleCount": rng.randint(0, 2), "poseMove": MOVE_ROW}
    astate = {"damage": rng.randint(0, 80), "powerTimer": int(rng.random() < 0.2)}
    for k, v in dstate.items():
        d.set(k, v)
    for k, v in astate.items():
        a.set(k, v)
    slot = {"guarded": int(rng.random() < 0.3), "chip": int(rng.random() < 0.5), "close": int(rng.random() < 0.2),
            "counter": int(rng.random() < 0.3), "airborne": int(rng.random() < 0.3), "zone": rng.randint(0, 13)}
    raw = bytearray(0x2C)
    struct.pack_into("<h", raw, 0x18, slot["zone"])
    for key, off in (("guarded", 0x22), ("chip", 0x23), ("counter", 0x25), ("close", 0x26), ("airborne", 0x27)):
        raw[off] = slot[key]
    cpu.write(SLOT, bytes(raw))
    cpu.call(HitDamage, F0, F1, SLOT)
    game = struct.unpack("<h", cpu.read(SLOT + 0x1E, 2))[0]
    mine = fight_math.hit_damage({**dstate, "moveActiveStart": active}, astate, slot)
    if game != mine:
        log.info("damage mismatch %s %s %s: game %d mine %d", dstate, astate, slot, game, mine)
    return game == mine


def check_launch(cpu, fields, rng: random.Random) -> bool:
    f = Record(cpu, F0, fields)
    move_len, pose_len = rng.randint(20, 90), rng.randint(20, 90)
    move_hold = rng.choice([0, rng.randint(5, 60)])
    same = rng.random() < 0.3
    for base, length, hold, anim in ((MOVE_ROW, move_len, move_hold, 0x1000), (POSE_ROW, pose_len, 0, 0x1000 if same else 0x2000)):
        row = bytearray(0x38)
        struct.pack_into("<I", row, 0, anim)
        row[0x18], row[0x1B] = length, hold
        cpu.write(base, bytes(row))
    state = {"rootY": rng.randint(-1500, 0), "groundOffset": rng.choice([440, 550, 204, 436, 1357]),
             "lastDamage": rng.randint(0, 60), "juggleCount": rng.randint(0, 5), "airKind": rng.randint(0, 5),
             "velY": rng.randint(-300, 300), "hitDirY": rng.randint(-400, 400), "state": rng.choice([0x842, 0x4, 0x2829, 0x4c02]),
             "poseFrame": rng.randint(1, 80), "targetDir": rng.randint(0, 0xFFFF), "index": 0,
             "moveRow": MOVE_ROW, "poseMove": POSE_ROW}
    for k, v in state.items():
        f.set(k, v)
    before_frames, before_speed = f.get("pushFrames"), f.get("pushSpeed")
    cpu.call(LaunchTrajectory, F0)
    mine = fight_math.launch_trajectory(state, move_hold, pose_len, move_len, same)
    game = {k: f.get(k) for k in ("airSpeed", "airVelY", "entryFrame", "pushTable", "pushTableFrames", "pushDir",
                                  "pushFrames", "pushSpeed")}
    game["airFrames"] = struct.unpack("<i", cpu.read(AIR_FRAMES, 4))[0]
    mine.setdefault("pushFrames", before_frames)
    mine.setdefault("pushSpeed", before_speed)
    norm = {k: (v & 0xFFFF if k in ("pushDir",) else v) for k, v in mine.items()}
    game["pushDir"] &= 0xFFFF
    ok = all(game[k] == norm[k] for k in game)
    if not ok:
        log.info("launch mismatch %s: %s", state, {k: (game[k], norm[k]) for k in game if game[k] != norm[k]})
    return ok


def check_transitions(cpu, fields, rng: random.Random) -> bool:
    f = Record(cpu, F0, fields)
    move = {"length": rng.randint(1, 90), "activeStart": rng.choice([0, rng.randint(1, 60)]), "activeEnd": rng.randint(0, 90)}
    row = bytearray(0x38)
    row[0x18], row[0x2D], row[0x2E] = move["length"], move["activeStart"], move["activeEnd"]
    cpu.write(MOVE_ROW, bytes(row))
    entry, pose_frame, kind, code = rng.randint(0, 90), rng.randint(0, 90), rng.randint(0, 4), rng.randint(0, 0x2B)
    for k, v in {"moveRow": MOVE_ROW, "entryFrame": entry, "poseFrame": pose_frame, "branchKind": kind}.items():
        f.set(k, v)
    game_code = cpu.call(0x800311BC, F0, code) & 0xFFFF
    game_keep = cpu.call(0x800312C4, F0) & 0xFF
    ok = (game_code == fight_math.transition_remap(code, move, entry)
          and bool(game_keep) == fight_math.move_keeps_frame(move, kind, pose_frame))
    if not ok:
        log.info("transition mismatch %s code %d entry %d frame %d kind %d: game %d/%d", move, code, entry, pose_frame, kind, game_code, game_keep)
    return ok


def check_segment(cpu, rng: random.Random) -> bool:
    cx, cy, cz = (rng.randint(-3000, 3000) for _ in range(3))
    r = rng.randint(80, 700)
    cyl = [cx, cy, cz, r, r * r]
    seg = [c + rng.randint(-900, 900) for c in (cx, cy, cz)] + [c + rng.randint(-900, 900) for c in (cx, cy, cz)]
    if rng.random() < 0.1:
        seg[4] = seg[1]
    cpu.write(SLOT, struct.pack("<6i", *seg))
    cpu.write(SLOT + 0x40, struct.pack("<3iii", cx, cy, cz, r & 0xFFFF, r * r))
    game = cpu.call(0x800479A4, SLOT, SLOT + 0x40) & 0xFF
    mine = fight_math.segment_hits_cylinder(seg, cyl)
    if bool(game) != mine:
        log.info("segment mismatch %s %s: game %d", seg, cyl, game)
    return bool(game) == mine


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=5000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    cpu = load_release()
    exe = fight_math.Exe((ROOT / "work" / "jp_rev1" / "exe.bin").read_bytes())
    fields = load_fields()
    bad_angles = sum(not check_angles(cpu, fields, exe, rng) for _ in range(args.cases))
    bad_damage = sum(not check_damage(cpu, fields, rng) for _ in range(args.cases))
    bad_launch = sum(not check_launch(cpu, fields, rng) for _ in range(args.cases))
    bad_seg = sum(not check_segment(cpu, rng) for _ in range(args.cases))
    log.info("SegmentHitsCylinder: %d cases, %d mismatches", args.cases, bad_seg)
    bad_trans = sum(not check_transitions(cpu, fields, rng) for _ in range(args.cases))
    log.info("TransitionRemap + MoveKeepsFrame: %d cases, %d mismatches", args.cases, bad_trans)
    log.info("FighterRelativeAngles: %d cases, %d mismatches", args.cases, bad_angles)
    log.info("HitDamage: %d cases, %d mismatches", args.cases, bad_damage)
    log.info("LaunchTrajectory: %d cases, %d mismatches", args.cases, bad_launch)
    return 1 if bad_angles or bad_damage or bad_launch or bad_trans or bad_seg else 0


if __name__ == "__main__":
    raise SystemExit(main())
