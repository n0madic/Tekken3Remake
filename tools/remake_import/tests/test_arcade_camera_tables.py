"""The arcade camera director's tables (arcade_camera_tables.py) on synthetic lists: no game data."""

from __future__ import annotations

import struct
import unittest

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_camera_tables as tables

LIST_AT = tables.IMAGE_FROM + 0x1000
SECOND_LIST_AT = LIST_AT + 0x100


def _image(size: int = tables.IMAGE_TO - tables.IMAGE_FROM) -> tables.Image:
    return tables.Image(bytearray(size))


def _entry(image: tables.Image, at: int, flags: int, weight: int, script: int = 0, mirrored: int = 0) -> None:
    struct.pack_into("<4h", image.data, at - tables.IMAGE_FROM, flags, weight, script, mirrored)


def _row(image: tables.Image, row: int, entries: int, count: int) -> None:
    struct.pack_into("<Ih", image.data, tables.CHOICE_ROWS + row * tables.CHOICE_ROW_BYTES - tables.IMAGE_FROM, entries, count)


class Choices(unittest.TestCase):
    def _normalised(self) -> tables.Image:
        image = _image()
        for row in range(tables.CHOICE_ROW_COUNT):
            _row(image, row, SECOND_LIST_AT, 0)
        _row(image, 0, LIST_AT, 3)
        _entry(image, LIST_AT, 0, 1)
        _entry(image, LIST_AT + 8, 0x11, 1, 5, 6)
        _entry(image, LIST_AT + 16, 2, 2)
        tables.normalise_choices(image)
        return image

    def test_weights_become_cumulative_out_of_a_full_weight(self) -> None:
        image = self._normalised()
        self.assertEqual([image.s16(LIST_AT + 2 + 8 * k) for k in range(3)], [0x400, 0x800, 0x1000])

    def test_a_marked_entry_sets_the_first_threshold(self) -> None:
        image = self._normalised()
        self.assertEqual(image.s16(tables.CHOICE_ROWS + 8), 0x400)

    def test_the_second_threshold_is_the_raw_cumulative_weight_of_the_first_special(self) -> None:
        image = self._normalised()
        self.assertEqual(image.s16(tables.CHOICE_ROWS + 10), 1)

    def test_an_entry_with_two_scripts_is_not_mirrored_and_the_mark_is_cleared(self) -> None:
        image = self._normalised()
        self.assertEqual(image.s16(LIST_AT + 8) & 0xFFFF, 2)

    def test_a_row_without_a_mark_gets_the_full_weight(self) -> None:
        image = self._normalised()
        at = tables.CHOICE_ROWS + tables.CHOICE_ROW_BYTES
        self.assertEqual(image.s16(at + 8), tables.FULL_WEIGHT)
        self.assertEqual(image.s16(at + 10), -1)


class HitLists(unittest.TestCase):
    def test_weights_become_cumulative(self) -> None:
        image = _image()
        for k in range(tables.HIT_LIST_COUNT):
            struct.pack_into("<Ii", image.data, tables.HIT_LISTS + 8 * k - tables.IMAGE_FROM, LIST_AT, 0)
        struct.pack_into("<Ii", image.data, tables.HIT_LISTS - tables.IMAGE_FROM, LIST_AT, 2)
        struct.pack_into("<h", image.data, LIST_AT + 2 - tables.IMAGE_FROM, 3)
        struct.pack_into("<h", image.data, LIST_AT + tables.HIT_RECORD_BYTES + 2 - tables.IMAGE_FROM, 1)
        tables.normalise_hit_lists(image)
        self.assertEqual(image.s16(LIST_AT + 2), 0xC00)
        self.assertEqual(image.s16(LIST_AT + tables.HIT_RECORD_BYTES + 2), 0x1000)

    def test_scripts_are_shared_by_pointer(self) -> None:
        image = _image()
        for k in range(tables.HIT_LIST_COUNT):
            struct.pack_into("<Ii", image.data, tables.HIT_LISTS + 8 * k - tables.IMAGE_FROM, LIST_AT, 0)
        struct.pack_into("<Ii", image.data, tables.HIT_LISTS - tables.IMAGE_FROM, LIST_AT, 1)
        script = SECOND_LIST_AT
        struct.pack_into(tables.HIT_SCRIPT_FORMAT, image.data, script - tables.IMAGE_FROM,
                         1, 40, 5, 6, 1000, 2000, 1, 2, 3, 4, 5, 6, 7, 8)
        struct.pack_into("<h4I", image.data, LIST_AT + 2 - tables.IMAGE_FROM, 0x1000, script, script, script, script)
        out = tables.hit_tables(image)
        self.assertEqual(out["hit_lists"], [[[0x1000, 0, 0, 0, 0]], [], []])
        self.assertEqual(out["hit_scripts"], [[1, 40, 5, 6, 1000, 2000, 1, 2, 3, 4, 5, 6, 7, 8]])


class BlendOuts(unittest.TestCase):
    def test_a_kind_is_read_before_the_preset_table(self) -> None:
        image = _image()
        struct.pack_into("<h", image.data, tables.PRESETS + 2 - tables.PRESET_BYTES - tables.IMAGE_FROM, 77)
        struct.pack_into("<h", image.data, tables.PRESETS + 2 - 3 * tables.PRESET_BYTES - tables.IMAGE_FROM, 99)
        values = tables.blend_outs(image)
        self.assertEqual(values[0], 77, "script −1: kind 0")
        self.assertEqual(values[2], 99, "stream 2: kind −2")


class FakeSet:
    """The arcade set's program, as `camera_tables` reads it."""

    def __init__(self, image: tables.Image) -> None:
        self.image = image

    def prog(self, _address: int, size: int) -> bytes:
        return bytes(self.image.data[:size])


class AttractTables(unittest.TestCase):
    def test_the_styles_pitches_and_speeds(self) -> None:
        image = _image()
        for row in range(tables.CHOICE_ROW_COUNT):
            _row(image, row, SECOND_LIST_AT, 0)
        struct.pack_into("<4H", image.data, tables.ATTRACT_STYLES - tables.IMAGE_FROM, 10, 20, 30, 40)
        struct.pack_into("<8i", image.data, tables.ATTRACT_PITCHES - tables.IMAGE_FROM, -1, 2, -3, 4, -5, 6, -7, 8)
        struct.pack_into("<2i", image.data, tables.ATTRACT_SPEEDS - tables.IMAGE_FROM, 9, -9)
        reel_end = tables.IMAGE_FROM + len(image.data) - 2
        image.put16(reel_end, -1)
        struct.pack_into(f"<{tables.REEL_COUNT}I", image.data, tables.REELS - tables.IMAGE_FROM,
                         *[reel_end] * tables.REEL_COUNT)
        out, _ = tables.camera_tables(FakeSet(image))
        self.assertEqual(out["attract_styles"], [10, 20, 30, 40])
        self.assertEqual(out["attract_pitches"], [-1, 2, -3, 4, -5, 6, -7, 8])
        self.assertEqual(out["attract_speeds"], [9, -9])


if __name__ == "__main__":
    unittest.main()
