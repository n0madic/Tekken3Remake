"""The arcade's effect flipbooks (arcade_effects.py) on a synthetic set: no game data."""

from __future__ import annotations

import struct
import unittest
from types import SimpleNamespace

import numpy as np

import common  # noqa: F401  (puts tools/research on the import path)
import arcade
import arcade_effects
from tests.arcade_fixtures import filled_tim, literal

RECORD = 0x80175510
WHITE = 0x7FFF
RED = 0x001F


def _set(tims: list[bytes], factors=(128, 128, 128), frames: int = 2, number: int = 0) -> SimpleNamespace:
    """An arcade set holding one flipbook set and its record."""
    record = struct.pack(arcade_effects.RECORD, number, frames, 64, 64, 1, *factors)

    def prog_values(fmt: str, addr: int) -> tuple:
        assert addr == RECORD
        return struct.unpack(fmt, record)

    return SimpleNamespace(prog_values=prog_values, category=lambda _: [literal(b"".join(tims))])


class TintTest(unittest.TestCase):
    def _tint(self, colour: int, factors: tuple[int, int, int]) -> int:
        return int(arcade_effects.tint(np.array([colour], dtype=np.uint16), factors)[0])

    def test_neutral_factors_keep_the_colour(self) -> None:
        self.assertEqual(self._tint(0x1234, (128, 128, 128)), 0x1234)

    def test_each_channel_scales_and_clamps(self) -> None:
        self.assertEqual(self._tint(0x0010 | 0x10 << 5 | 0x10 << 10, (64, 128, 255)), 0x08 | 0x10 << 5 | 0x1F << 10)

    def test_transparent_stays_and_black_does_not_become_it(self) -> None:
        self.assertEqual(self._tint(0, (255, 255, 255)), 0)
        self.assertEqual(self._tint(0x0001, (1, 128, 128)), 0x0400)
        self.assertEqual(self._tint(0x8000, (128, 128, 128)), 0x8400)


class FlipbookTest(unittest.TestCase):
    def test_frames_run_left_to_right_through_the_first_clut(self) -> None:
        first = [0, WHITE, RED] + [0] * 13
        other = [0, RED, WHITE] + [0] * 13     # later CLUTs are not uploaded (FUN_801af068)
        tims = [filled_tim(1, first), filled_tim(2, other), filled_tim(1, other)]
        strip, frames = arcade_effects.flipbook(_set(tims), RECORD)
        self.assertEqual(frames, 2)            # the record's count, not the set's
        self.assertEqual(strip.shape, (64, 128, 4))
        self.assertEqual(strip[0, 0].tolist(), [255, 255, 255, 255])
        self.assertEqual(strip[63, 127].tolist(), [255, 0, 0, 255])

    def test_factors_apply_and_colour_zero_is_transparent(self) -> None:
        palette = [0, WHITE] + [0] * 14
        tims = [filled_tim(1, palette), filled_tim(0, palette)]
        strip, _ = arcade_effects.flipbook(_set(tims, factors=(128, 0, 0)), RECORD)
        self.assertEqual(strip[0, 0, :3].tolist(), [255, 0, 0])
        self.assertEqual(strip[0, 64, 3], 0)

    def test_too_few_frames_or_a_missing_set_are_errors(self) -> None:
        palette = [0, WHITE] + [0] * 14
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.flipbook(_set([filled_tim(1, palette)]), RECORD)
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.flipbook(_set([filled_tim(1, palette)], number=1), RECORD)

    def test_a_frame_of_another_size_is_an_error(self) -> None:
        palette = [0, WHITE] + [0] * 14
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.flipbook(_set([filled_tim(1, palette, (8, 32))] * 2), RECORD)

    def test_or_none_keeps_the_playstation_on_failure_or_without_a_set(self) -> None:
        palette = [0, WHITE] + [0] * 14
        self.assertIsNone(arcade_effects.flipbook_or_none(None, RECORD, "hit"))
        with self.assertLogs(common.log, "ERROR"):
            self.assertIsNone(arcade_effects.flipbook_or_none(_set([filled_tim(1, palette)]), RECORD, "hit"))


class ClutAndWordsTest(unittest.TestCase):
    def test_a_tim_without_a_clut_is_an_error(self) -> None:
        tim = bytearray(filled_tim(1, [0] * 16))
        tim[4] = 0                              # flags: 4-bit, no CLUT
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.clut_and_words(bytes(tim))

    def test_an_empty_pixel_block_has_no_words(self) -> None:
        clut, words = arcade_effects.clut_and_words(filled_tim(1, [WHITE] * 16, (0, 0)))
        self.assertEqual(clut.tolist(), [WHITE] * 16)
        self.assertIsNone(words)


class RecordTest(unittest.TestCase):
    def test_records_by_character(self) -> None:
        base, step = arcade_effects.CHARACTER_RECORDS, arcade_effects.CHARACTER_RECORD_BYTES
        self.assertEqual(arcade_effects.character_record(4), base + 4 * step)
        self.assertEqual(arcade_effects.character_record(19), base + 9 * step)


if __name__ == "__main__":
    unittest.main()
