"""The arcade effect objects' tables (arcade_effect_tables.py) on a synthetic program image: no game data."""

from __future__ import annotations

import struct
import types
import unittest

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_effect_tables as tables

PROGRAM_BASE = 0x80010000
PROGRAM_SIZE = 0x200000


def _image() -> tuple[bytearray, types.SimpleNamespace]:
    image = bytearray(PROGRAM_SIZE)

    def prog_values(fmt: str, addr: int) -> tuple:
        return struct.unpack_from(fmt, image, addr - PROGRAM_BASE)

    return image, types.SimpleNamespace(prog_values=prog_values)


def _put(image: bytearray, fmt: str, addr: int, *values: int) -> None:
    struct.pack_into(fmt, image, addr - PROGRAM_BASE, *values)


class Sine(unittest.TestCase):
    def test_every_second_pair_by_angle(self) -> None:
        image, arc = _image()
        for pair in (0, 1, 2, 3, 8191):
            _put(image, "<2h", tables.SINE + 4 * pair, pair + 1, -pair - 1)
        out = tables.tables(arc)
        self.assertEqual(len(out["sin"]), tables.ANGLES)
        self.assertEqual(len(out["cos"]), tables.ANGLES)
        self.assertEqual(out["sin"][:2], [1, 3])
        self.assertEqual(out["cos"][:2], [-1, -3])
        self.assertEqual(out["sin"][-1], 0, "pair 8191 is an odd one, between two angles")


class Direction(unittest.TestCase):
    def test_arctangent_and_octants_are_signed(self) -> None:
        image, arc = _image()
        _put(image, "<h", tables.ATAN + 2 * 4095, 0x1FFE)
        _put(image, "<8h", tables.ANGLE_BASE, 0, 0x4000, -0x8000, 0x4000, 0, -0x4000, -0x8000, -0x4000)
        _put(image, "<8h", tables.ANGLE_SIGN, 0, 1, 1, 0, 1, 0, 0, 1)
        out = tables.tables(arc)
        self.assertEqual(out["atan"][4095], 0x1FFE)
        self.assertEqual(out["angle_base"][2], -0x8000)
        self.assertEqual(out["angle_sign"], [0, 1, 1, 0, 1, 0, 0, 1])


class Spawns(unittest.TestCase):
    def test_offsets_keep_three_components_per_point(self) -> None:
        image, arc = _image()
        _put(image, "<4h", tables.BREATH_OFFSETS, 1, 2, 3, 99)
        _put(image, "<4h", tables.BREATH_OFFSETS + 8, 4, 5, 6, 99)
        _put(image, "<4h", tables.BREATH_OFFSETS + 16, -1, -2, -3, 99)
        _put(image, "<4h", tables.BREATH_OFFSETS + 24, -4, -5, -6, 99)
        _put(image, "<4h", tables.CLOUD_OFFSETS + 8, 7, 8, 9, 99)
        out = tables.tables(arc)
        self.assertEqual(out["breath_offsets"], [[[1, 2, 3], [4, 5, 6]], [[-1, -2, -3], [-4, -5, -6]]])
        self.assertEqual(out["cloud_offsets"][1], [7, 8, 9])

    def test_glow_joints_take_each_records_first_word(self) -> None:
        image, arc = _image()
        _put(image, "<2i", tables.GLOW_JOINTS + 8 * 4, 6, 5)
        _put(image, "<2i", tables.GLOW_JOINTS + 8 * 25, 0, 26)
        out = tables.tables(arc)
        self.assertEqual(len(out["glow_joints"]), tables.GLOW_JOINT_COUNT)
        self.assertEqual(out["glow_joints"][4], 6)
        self.assertEqual(out["glow_joints"][25], 0)

    def test_burn_joints_and_segment_frames(self) -> None:
        image, arc = _image()
        _put(image, "<i", tables.BURN_JOINTS + 4 * 12, 17)
        _put(image, "<3B", tables.SEGMENT_FIREBALL, 1, 1, 1)
        _put(image, "<B", tables.SEGMENT_CLOUD + 20, 1)
        out = tables.tables(arc)
        self.assertEqual(out["burn_joints"][12], 17)
        self.assertEqual(out["segment_fireball"], [1, 1, 1, 0, 0, 0, 0, 0])
        self.assertEqual(len(out["segment_cloud"]), tables.SEGMENT_CLOUD_COUNT)
        self.assertEqual(out["segment_cloud"][20], 1)


if __name__ == "__main__":
    unittest.main()
