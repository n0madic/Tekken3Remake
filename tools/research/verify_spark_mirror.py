#!/usr/bin/env python3
"""Check the flipbook mirror flag EffectSpawn (FUN_80076B6C) stores against the port's formula (Japan Rev.1).

EffectSpawn keeps, in a flipbook record's +0x3C, the sign of an int32 expression of the spawn point
P, the hit direction D (the point struct's shorts at +0x10 and +0x14) and the camera's x and z
(0x800A8A9C, 0x800A8AA4); FUN_80077158 draws the quad with its left and right texels swapped when
it is set. The remake's `EffectObjects.spawn_mirrored` is the same expression. This runs the game's
EffectSpawn (set 3, the system flipbooks) on random points, directions and camera positions, reads
the flag from the record the call filled, and compares it with the port's.

`--export` prints the first cases as GDScript rows for tests/core/test_spark_mirror.gd.

Usage: python3.14 tools/research/verify_spark_mirror.py [--cases N] [--seed S] [--export]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

from psxcpu import load_release

log = logging.getLogger("verify_spark_mirror")

EFFECT_SPAWN = 0x80076B6C
CAMERA_X = 0x800A8A9C
CAMERA_Z = 0x800A8AA4
WRITE_SLOT = 0x800A3960        # the ring's next record (three of 0x40 bytes from 0x800A37B0)
RECORDS = 0x800A37B0
MIRROR = 0x3C                  # offset in the record (0x800A37EC for the first)
SET_TABLE = 0x800A39A0         # set 3's flipbook table, what FUN_80076704 points at 0x80027C30
SET_3_RECORDS = 0x80027C30
POINT = 0x801F0000             # scratch: the point struct
EXPORTED = 12


def s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - (1 << 32) if v & 0x80000000 else v


def mirrored(px: int, pz: int, dx: int, dz: int, cx: int, cz: int) -> bool:
    """The port: EffectObjects.spawn_mirrored."""
    behind = s32((pz - dz - cz) * (px - cx))
    across = s32((cx - (px - dx)) * (pz - cz))
    return s32(behind + across) < 0


def game_flag(cpu, px: int, py: int, pz: int, dx: int, dy: int, dz: int, cx: int, cz: int) -> bool:
    cpu.write(POINT, struct.pack("<iiii", px, py, pz, 0) + struct.pack("<hhh", dx, dy, dz))
    cpu.write(CAMERA_X, struct.pack("<i", cx))
    cpu.write(CAMERA_Z, struct.pack("<i", cz))
    slot = struct.unpack("<h", cpu.read(WRITE_SLOT, 2))[0]
    cpu.call(EFFECT_SPAWN, 3, 0, POINT, 0)
    return struct.unpack("<H", cpu.read(RECORDS + 0x40 * slot + MIRROR, 2))[0] != 0


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("--cases", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument("--export", action="store_true")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    rng = random.Random(args.seed)
    cpu = load_release()
    for i in range(4):
        cpu.write(SET_TABLE + 4 * i, struct.pack("<I", SET_3_RECORDS + 6 * i))
    cpu.write(WRITE_SLOT, struct.pack("<h", 0))
    bad = 0
    sides = [0, 0]
    rows = []
    for case in range(args.cases):
        # Mostly what a fight reaches (the camera some metres away, the point in the arena), some far
        # out so that the products pass 2^31 and the game's 32-bit wrap shows.
        reach = 6000 if case % 8 else 90000
        px, pz = rng.randint(-reach, reach), rng.randint(-reach, reach)
        cx, cz = rng.randint(-reach, reach), rng.randint(-reach, reach)
        py = rng.randint(-2000, 0)
        dx, dy, dz = (rng.randint(-32768, 32767) if case % 8 == 0 else rng.randint(-4096, 4096) for _ in range(3))
        want = mirrored(px, pz, dx, dz, cx, cz)
        got = game_flag(cpu, px, py, pz, dx, dy, dz, cx, cz)
        sides[got] += 1
        if got != want:
            bad += 1
            log.error("case %d: game %s, port %s: P (%d, %d) D (%d, %d) C (%d, %d)", case, got, want, px, pz, dx, dz, cx, cz)
        if len(rows) < EXPORTED and (case % 8 == 0 or len(rows) < EXPORTED // 2):
            rows.append(f"\t[{px}, {pz}, {dx}, {dz}, {cx}, {cz}, {str(got).lower()}],")
    log.info("%d cases (not mirrored %d, mirrored %d): %s", args.cases, sides[0], sides[1],
             "all equal" if not bad else f"{bad} differ")
    if args.export:
        print("\n".join(rows))
    raise SystemExit(1 if bad else 0)


if __name__ == "__main__":
    main()
