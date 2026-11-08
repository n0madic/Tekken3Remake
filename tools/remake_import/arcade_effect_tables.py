"""The arcade effect objects' tables → `tables/effects.json`, read by `content/arcade_effect_tables.gd`.

Addresses and meanings: docs/research/arcade/audio-and-effects.md#4-effect-objects. The objects draw on
the shared `rand()` and the CPU's decisions read it, so they are simulation state like the fight's.

The sine table holds 8192 {sin, cos} pairs of 0x7FFF scale; the routines index it by a 4096-unit angle
times 8 bytes, that is every second pair, and only those are written.
"""

from __future__ import annotations

import arcade
from common import Output
from arcade_tables import s16s, s32s, u8s

SINE = 0x8017CB78               # FUN_801DB180, FUN_801DB110, FUN_801DAFC4
SINE_PAIRS = 8192
ANGLES = 4096
ATAN = 0x80184B78               # FUN_801DAE68: s16 by (low << 16) / high >> 4
ATAN_ENTRIES = 4096
ANGLE_BASE = 0x8017C498         # FUN_801DAE68: s16 per octant
ANGLE_SIGN = 0x8017C4A8
OCTANTS = 8
BREATH_OFFSETS = 0x8020453C     # FUN_801DC414: per fighter two SVECTORs from the head joint
CLOUD_OFFSETS = 0x8020455C      # FUN_801DC574: two SVECTORs
SVECTOR_BYTES = 8
OFFSET_POINTS = 2
FIGHTERS = 2
BURN_JOINTS = 0x8017C4BC        # FUN_801DC6C0: s32
BURN_JOINT_COUNT = 13
GLOW_JOINTS = 0x8017C4F4        # FUN_801DC81C: 8-byte records whose first word is the glowing joint
GLOW_JOINT_BYTES = 8
GLOW_JOINT_COUNT = 26           # the move's attack joints, 0 to 0x19 (past them the program's own data)
SEGMENT_FIREBALL = 0x8017C7D4   # FUN_801DEC14: u8 per burst frame, 0 ends the hit segment
SEGMENT_FIREBALL_COUNT = 8
SEGMENT_CLOUD = 0x8017C8FC      # FUN_801DFABC: u8 per cloud frame
SEGMENT_CLOUD_COUNT = 21


def _point(arc: arcade.ArcadeSet, address: int) -> list[int]:
    return s16s(arc, address, 3)


def _points(arc: arcade.ArcadeSet, address: int) -> list[list[int]]:
    return [_point(arc, address + SVECTOR_BYTES * k) for k in range(OFFSET_POINTS)]


def tables(arc: arcade.ArcadeSet) -> dict:
    pairs = s16s(arc, SINE, SINE_PAIRS * 2)
    step = SINE_PAIRS // ANGLES
    return {
        "sin": [pairs[2 * step * i] for i in range(ANGLES)],
        "cos": [pairs[2 * step * i + 1] for i in range(ANGLES)],
        "atan": s16s(arc, ATAN, ATAN_ENTRIES),
        "angle_base": s16s(arc, ANGLE_BASE, OCTANTS),
        "angle_sign": s16s(arc, ANGLE_SIGN, OCTANTS),
        "breath_offsets": [_points(arc, BREATH_OFFSETS + side * OFFSET_POINTS * SVECTOR_BYTES)
                           for side in range(FIGHTERS)],
        "cloud_offsets": _points(arc, CLOUD_OFFSETS),
        "burn_joints": s32s(arc, BURN_JOINTS, BURN_JOINT_COUNT),
        "glow_joints": [s32s(arc, GLOW_JOINTS + GLOW_JOINT_BYTES * code, 1)[0] for code in range(GLOW_JOINT_COUNT)],
        "segment_fireball": u8s(arc, SEGMENT_FIREBALL, SEGMENT_FIREBALL_COUNT),
        "segment_cloud": u8s(arc, SEGMENT_CLOUD, SEGMENT_CLOUD_COUNT),
    }


def convert(arc: arcade.ArcadeSet, out: Output) -> None:
    out.write_json("tables/effects.json", tables(arc))
