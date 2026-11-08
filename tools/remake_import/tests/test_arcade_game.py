"""The conversion from the arcade's set alone (arcade_game.py, arcade_character.parts_from_rows) on
synthetic data: no game data."""

from __future__ import annotations

import struct
import types
import unittest

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_character
import arcade_game
import arcade_kmd
import character
import kmd as kmdlib
import stage

FLOOR = {"kind": 0, "shade": -51, "fade": 10000, "tile_size": 2500}


def _rows() -> list[types.SimpleNamespace]:
    """A skeleton: joint k hangs from joint k − 1 at offset (k, 2k, 3k); the first has no parent."""
    return [types.SimpleNamespace(index=k, parent=k - 1, offset=(k, 2 * k, 3 * k)) for k in range(arcade_kmd.ROWS)]


class PartsFromRows(unittest.TestCase):
    def setUp(self) -> None:
        self.parts = arcade_character.parts_from_rows(types.SimpleNamespace(rows=_rows()))

    def test_one_entry_per_playstation_part(self) -> None:
        self.assertEqual(len(self.parts), len(kmdlib.PART_MATRIX))
        self.assertEqual([p["joint"] for p in self.parts], list(kmdlib.PART_MATRIX))

    def test_the_parent_is_a_part_number(self) -> None:
        part_of_joint = {joint: part for part, joint in enumerate(kmdlib.PART_MATRIX)}
        for part, entry in enumerate(self.parts[:character.FIRST_ATTACHMENT_PART]):
            joint = kmdlib.PART_MATRIX[part]
            parent = -1 if joint == 0 else part_of_joint[joint - 1]
            self.assertEqual(entry["parent"], parent, f"part {part}")

    def test_the_offset_is_the_joints(self) -> None:
        for part, entry in enumerate(self.parts[:character.FIRST_ATTACHMENT_PART]):
            k = kmdlib.PART_MATRIX[part]
            self.assertEqual(entry["offset"], [k, 2 * k, 3 * k])
            self.assertTrue(entry["drawn"])

    def test_the_attachment_parts_have_no_matrix(self) -> None:
        for entry in self.parts[character.FIRST_ATTACHMENT_PART:]:
            self.assertEqual(entry["parent"], -1, "FighterSetupPart: no parent, no matrix")
            self.assertFalse(entry["drawn"])
            self.assertIsNone(entry["dynamics"])


class StageRecord(unittest.TestCase):
    def _arc(self, record: bytes) -> types.SimpleNamespace:
        def prog(addr: int, size: int) -> bytes:
            self.assertEqual(addr, arcade_game.LIGHT_RECORDS + arcade_game.LIGHT_RECORD_BYTES * 2)
            return record[:size]
        return types.SimpleNamespace(prog=prog)

    def test_the_light_record_reads_as_the_playstations(self) -> None:
        record = struct.pack("<i", 1500) + bytes((176, 146, 126, 0, 152, 184, 180, 0)) + struct.pack("<hh", 384, 2560)
        out = arcade_game.stage_record(self._arc(record), 2, "c", FLOOR)
        self.assertEqual(out["lighting"], stage.lighting_record(record))
        self.assertEqual(out["lighting"]["light_rgb"], [180, 184, 152])
        self.assertEqual(out["lighting"]["ambient"], 93)

    def test_the_floor_comes_from_the_scene(self) -> None:
        out = arcade_game.stage_record(self._arc(bytes(16)), 2, "c", FLOOR)
        self.assertEqual((out["stage"], out["letter"], out["floor_tile_size"], out["floor_shade"]), (2, "c", 2500, -51))
        self.assertEqual(len(out["coverage"]["elevation"]), arcade_game.COVERAGE_DIRECTIONS)


if __name__ == "__main__":
    unittest.main()
