"""The arcade's effect flipbooks (arcade_effects.py) on a synthetic set: no game data."""

from __future__ import annotations

import struct
import unittest
from types import SimpleNamespace

import numpy as np

import common  # noqa: F401  (puts tools/research on the import path)
import arcade
import arcade_effects
from vram import TIM_ID

RECORD = 0x80175510
WHITE = 0x7FFF
RED = 0x001F


def _literal(data: bytes) -> bytes:
    """Data as the BIOS's LZ: only literals, seven per flag byte, then the end flag."""
    out = bytearray()
    for k in range(0, len(data), 7):
        chunk = data[k:k + 7]
        out.append(((1 << len(chunk)) - 1) | 1 << len(chunk))
        out += chunk
    return bytes(out) + b"\0"


def _tim(index: int, palette: list[int], size: tuple[int, int] = (16, 64)) -> bytes:
    """A 4-bit frame all of texel `index`, with its CLUT."""
    w, h = size
    clut = struct.pack("<IHHHH16H", 44, 0, 0, 16, 1, *palette)
    word = index * 0x1111
    image = struct.pack("<IHHHH", 12 + 2 * w * h, 0, 0, w, h) + struct.pack(f"<{w * h}H", *[word] * (w * h))
    return struct.pack("<II", TIM_ID, 8) + clut + image


def _set(tims: list[bytes], factors=(128, 128, 128), frames: int = 2, number: int = 0) -> SimpleNamespace:
    """An arcade set holding one flipbook set and its record."""
    record = struct.pack(arcade_effects.RECORD, number, frames, 64, 64, 1, *factors)

    def prog_values(fmt: str, addr: int) -> tuple:
        assert addr == RECORD
        return struct.unpack(fmt, record)

    return SimpleNamespace(prog_values=prog_values, category=lambda _: [_literal(b"".join(tims))])


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
        strip, frames = arcade_effects.flipbook(_set([_tim(1, first), _tim(2, other), _tim(1, other)]), RECORD)
        self.assertEqual(frames, 2)            # the record's count, not the set's
        self.assertEqual(strip.shape, (64, 128, 4))
        self.assertEqual(strip[0, 0].tolist(), [255, 255, 255, 255])
        self.assertEqual(strip[63, 127].tolist(), [255, 0, 0, 255])

    def test_factors_apply_and_colour_zero_is_transparent(self) -> None:
        palette = [0, WHITE] + [0] * 14
        strip, _ = arcade_effects.flipbook(_set([_tim(1, palette), _tim(0, palette)], factors=(128, 0, 0)), RECORD)
        self.assertEqual(strip[0, 0, :3].tolist(), [255, 0, 0])
        self.assertEqual(strip[0, 64, 3], 0)

    def test_too_few_frames_or_a_missing_set_are_errors(self) -> None:
        palette = [0, WHITE] + [0] * 14
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.flipbook(_set([_tim(1, palette)]), RECORD)
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.flipbook(_set([_tim(1, palette)], number=1), RECORD)

    def test_a_frame_of_another_size_is_an_error(self) -> None:
        palette = [0, WHITE] + [0] * 14
        with self.assertRaises(arcade.ArcadeError):
            arcade_effects.flipbook(_set([_tim(1, palette, (8, 32))] * 2), RECORD)

    def test_or_none_keeps_the_playstation_on_failure_or_without_a_set(self) -> None:
        palette = [0, WHITE] + [0] * 14
        self.assertIsNone(arcade_effects.flipbook_or_none(None, RECORD, "hit"))
        with self.assertLogs(common.log, "ERROR"):
            self.assertIsNone(arcade_effects.flipbook_or_none(_set([_tim(1, palette)]), RECORD, "hit"))


class RecordTest(unittest.TestCase):
    def test_records_by_character(self) -> None:
        base, step = arcade_effects.CHARACTER_RECORDS, arcade_effects.CHARACTER_RECORD_BYTES
        self.assertEqual(arcade_effects.character_record(4), base + 4 * step)
        self.assertEqual(arcade_effects.character_record(19), base + 9 * step)


if __name__ == "__main__":
    unittest.main()
