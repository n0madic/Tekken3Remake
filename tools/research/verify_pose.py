#!/usr/bin/env python3
"""Verify pose.py against the game's PoseBuildMatrices (0x8003AF64) in the CPU harness.

For every animation stream of the given banks, pose vectors are decoded with
motion.py (bit-exact with the game) for a sample of frames, and the 18 local joint
rotations are built by both the game routine and the Python port. The matrix slots
start from the same random values on both sides, because the IK leaves the lower
limb untouched when a target is closer than the solver's minimum reach.

Usage: python3 tools/research/verify_pose.py [--step N] [bank file names ...]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct
import time

import motion
import pose
from psxcpu import load_release

POSE_ADDR = 0x801F0000
SLOTS_ADDR = 0x801F0100
SLOT_BYTES = 32
PoseBuildMatrices = 0x8003AF64

log = logging.getLogger("verify_pose")


def default_banks() -> list[str]:
    seen: set[bytes] = set()
    names = []
    for path in sorted((motion.ROOT / "work" / "jp_rev1" / "bns").glob("*divmot*.bin")):
        data = path.read_bytes()
        if data not in seen:
            seen.add(data)
            names.append(path.name)
    return names


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("banks", nargs="*")
    parser.add_argument("--step", type=int, default=3, help="check every N-th frame")
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    rng = random.Random(args.seed)
    cpu = load_release()
    exe = motion.load_exe()
    spline = motion.SplineTables(exe)
    tab = pose.ExeTables(exe)
    checked = mismatched = 0
    start = time.time()
    for name in args.banks or default_banks():
        data = (motion.ROOT / "work" / "jp_rev1" / "bns" / name).read_bytes()
        bank = motion.parse_bank(data)
        offsets = sorted({bank.move_row(r)[0] for r in range(bank.move_count)
                          if bank.move_row(r)[0] < motion.COMMON_FLAG})
        for word in offsets:
            stream = motion.parse_anim(data, bank.anim_offset(word))
            for frame in range(0, stream.frames, args.step):
                vec = motion.sample_pose(stream, frame, spline)
                init = [[rng.randint(-4096, 4096) for _ in range(9)] for _ in range(pose.SLOT_COUNT)]
                cpu.write(POSE_ADDR, struct.pack("<49h", *vec))
                raw = b"".join(struct.pack("<9h", *m) + bytes(SLOT_BYTES - 18) for m in init)
                cpu.write(SLOTS_ADDR, raw)
                cpu.call(PoseBuildMatrices, POSE_ADDR, SLOTS_ADDR)
                out = cpu.read(SLOTS_ADDR, SLOT_BYTES * pose.SLOT_COUNT)
                game = [list(struct.unpack_from("<9h", out, SLOT_BYTES * s)) for s in range(pose.SLOT_COUNT)]
                mine = [list(m) for m in init]
                pose.pose_build_matrices(vec, mine, tab)
                checked += 1
                if game != mine:
                    mismatched += 1
                    if mismatched <= 5:
                        diff = [(s, i, game[s][i], mine[s][i]) for s in range(pose.SLOT_COUNT)
                                for i in range(9) if game[s][i] != mine[s][i]]
                        log.info("mismatch %s anim %#x frame %d: %s", name, word, frame, diff[:8])
        log.info("%s: poses checked %d, mismatches %d (%.0fs)", name, checked, mismatched, time.time() - start)
    return 1 if mismatched else 0


if __name__ == "__main__":
    raise SystemExit(main())
