"""The ending movies' captions (captions.py), on a synthetic ending overlay: no game data."""

from __future__ import annotations

import struct
import unittest

import captions
from common import Block

BASE = 0x80100000
POINTER = 0x40                   # where the bitmaps' base pointer is kept
BLIT = 0x100
RECORDS = 0x200
BITMAPS = 0x1000
PLAIN, BLENDED = (10, 20, 30), (200, 100, 50)


def _overlay() -> Block:
    data = bytearray(0x8000)
    pointer = BASE + POINTER
    struct.pack_into("<I", data, POINTER, BASE + BITMAPS)
    struct.pack_into("<I", data, BLIT - 4, 0x3C030000 | pointer >> 16)          # lui v1, hi
    data[BLIT:BLIT + 8] = captions.BLIT_SIGNATURE
    struct.pack_into("<h", data, BLIT + 12, pointer & 0xFFFF)                    # lw v1, lo(v1)
    data[RECORDS:RECORDS + captions.RECORD_SIZE] = captions.RECORD_SIGNATURE
    struct.pack_into("<I8h", data, RECORDS + captions.RECORD_SIZE, 256 * 44 // 2, 16, 176, 0, 256, 32, 128, 2, 0)
    timeline = [(0, -1), (3, 0), (10, -1), (9, 1), (20, -1), (0xFFFF, 0)] + [(0, -1), (5, 1), (0xFFFF, 0)] * 4   # five sets, as USA has
    at = RECORDS + 2 * captions.RECORD_SIZE
    for k, entry in enumerate(timeline):
        struct.pack_into("<Hh", data, at + 4 * k, *entry)
    palettes = at + 4 * len(timeline)
    struct.pack_into("<4B", data, palettes + captions.PALETTE_ENTRY, *BLENDED, 1)
    struct.pack_into("<4B", data, palettes + 2 * captions.PALETTE_ENTRY, *PLAIN, 0)
    data[BITMAPS] = 0x21         # the first two pixels: entries 1 and 2
    return Block("ending", BASE, bytes(data))


class CaptionsTest(unittest.TestCase):
    def test_pictures_and_places(self) -> None:
        found, _ = captions.read(_overlay())
        self.assertEqual([(c.x, c.y, c.pixels.shape) for c in found], [(0, 170, (44, 256, 4)), (16, 176, (32, 256, 4))])
        pixels = found[0].pixels
        # ((movie >> 1) + colour) >> 1 = movie / 4 + colour / 2: alpha 0.75 over the movie, colour · 2/3.
        self.assertEqual(list(pixels[0, 0]), [c * 2 // 3 for c in BLENDED] + [captions.BLENDED_ALPHA])
        self.assertEqual(list(pixels[0, 1]), [*PLAIN, captions.OPAQUE])
        self.assertEqual(pixels[0, 2, 3], 0)     # entry 0 is transparent

    def test_sets_follow_the_timeline_scan(self) -> None:
        _, sets = captions.read(_overlay())
        # Entry (10, −1) is passed over: from frame 11 the scan stops after (9, 1).
        self.assertEqual(sets[0], [[4, 0], [11, 1], [21, -1]])
        self.assertEqual(sets[1:], [[[6, 1]]] * 4)

    def test_timeline_cut_short(self) -> None:
        block = _overlay()
        cut = block.data[:RECORDS + 2 * captions.RECORD_SIZE + 4 * 3]   # three timeline entries left
        with self.assertRaisesRegex(captions.CaptionError, "timeline runs past"):
            captions.read(Block("ending", BASE, cut))

    def test_no_tables(self) -> None:
        with self.assertRaises(captions.CaptionError):
            captions.read(Block("ending", BASE, bytes(0x400)))


if __name__ == "__main__":
    unittest.main()
