"""Gon's eyes' look direction as texture patches (gaze.py): synthetic strips, no game data."""

from __future__ import annotations

import unittest

import numpy as np

import common  # noqa: F401  (puts tools/research on the import path)
import gaze
from vram import Vram

STRIP = (8, 64)
WINDOW = (8, 34)
STRIPS = ((432, 64), (416, 128))
SAVED = ((448, 0), (456, 0))


def layout() -> gaze.Layout:
    return gaze.Layout(STRIP, WINDOW, tuple(gaze.Eye(s, v) for s, v in zip(STRIPS, SAVED)))


def vram() -> Vram:
    """VRAM whose strips hold the row number (1 to 64, eye 1's plus 100) in every word of a row."""
    v = Vram()
    for eye, (x, y) in enumerate(STRIPS):
        for row in range(STRIP[1]):
            v.words[y + row, x:x + STRIP[0]] = row + 1 + 100 * eye
    return v


def repaint(v: Vram) -> np.ndarray:
    """A picture of the strips: the low byte of their words, eye 0's at x 0–7, eye 1's at x 12–19."""
    pixels = np.zeros((70, 24, 4), dtype=np.uint8)
    for eye, (x, y) in enumerate(STRIPS):
        pixels[:STRIP[1], 12 * eye:12 * eye + STRIP[0], 0] = v.words[y:y + STRIP[1], x:x + STRIP[0]] & 0xFF
        pixels[:STRIP[1], 12 * eye:12 * eye + STRIP[0], 3] = 255
    return pixels


class StripTest(unittest.TestCase):
    def test_the_strips_are_saved_beside_the_page(self) -> None:
        saved = gaze.with_saves(layout(), vram())
        for (x, y), (sx, sy) in zip(STRIPS, SAVED):
            self.assertTrue(np.array_equal(saved.words[sy:sy + 64, sx:sx + 8], saved.words[y:y + 64, x:x + 8]))

    def test_a_shift_copies_the_window_of_the_saved_strip_over_the_strip(self) -> None:
        saved = gaze.with_saves(layout(), vram())
        shown = gaze.shifted(layout(), saved, 0, 3)
        self.assertEqual(shown.words[64 + 17, 432], 8 + 3 + 1, "strip row 17 takes saved row 8 + shift")
        self.assertEqual(shown.words[64 + 50, 432], 8 + 3 + 33 + 1)
        self.assertEqual(shown.words[64 + 16, 432], 16 + 1, "rows outside the window are kept")
        self.assertEqual(shown.words[64 + 51, 432], 51 + 1)
        self.assertEqual(shown.words[128 + 20, 416], 20 + 1 + 100, "the other eye is not touched")
        shown = gaze.shifted(layout(), saved, 1, -4)
        self.assertEqual(shown.words[128 + 13, 416], 21 - 4 + 1 + 100, "eye 1: strip row 13 takes saved row 21 + shift")

    def test_the_middle_shifts_leave_the_strips_as_they_were(self) -> None:
        saved = gaze.with_saves(layout(), vram())
        self.assertTrue(np.array_equal(gaze.shifted(layout(), saved, 0, 9).words, saved.words))
        self.assertTrue(np.array_equal(gaze.shifted(layout(), saved, 1, -8).words, saved.words))
        self.assertFalse(np.array_equal(gaze.shifted(layout(), saved, 0, 0).words, saved.words))


class PatchTest(unittest.TestCase):
    def test_tile_rects_cover_the_pixels_and_merge_equal_runs(self) -> None:
        mask = np.zeros((40, 50), dtype=bool)
        mask[3, 3] = mask[12, 30] = True
        mask[20:30, 9:20] = True
        rects = gaze.tile_rects(mask)
        covered = np.zeros_like(mask)
        for x, y, w, h in rects:
            covered[y:y + h, x:x + w] = True
        self.assertTrue(covered[mask].all())
        self.assertEqual(len(rects), 3, "two single tiles and one merged block")
        self.assertIn((8, 16, 16, 16), rects)
        self.assertEqual(gaze.tile_rects(np.zeros((5, 5), dtype=bool)), [])

    def test_tile_rects_stay_inside_the_picture(self) -> None:
        mask = np.zeros((10, 10), dtype=bool)
        mask[9, 9] = True
        self.assertEqual(gaze.tile_rects(mask), [(8, 8, 2, 2)])

    def test_the_patches_rebuild_every_shifted_picture(self) -> None:
        saved = gaze.with_saves(layout(), vram())
        base = repaint(saved)
        found = gaze.patches(layout(), saved, repaint)
        for eye in range(gaze.EYES):
            rects, by_shift = found[(eye, 0)]
            self.assertEqual(set(by_shift), set(gaze.SHIFTS[eye]))
            for shift, crops in by_shift.items():
                shown = base.copy()
                for (x, y, w, h), crop in zip(rects, crops):
                    shown[y:y + h, x:x + w] = crop
                self.assertTrue(np.array_equal(shown, repaint(gaze.shifted(layout(), saved, eye, shift))),
                                f"eye {eye} shift {shift}")

    def test_the_eyes_patches_do_not_overlap_here(self) -> None:
        found = gaze.patches(layout(), gaze.with_saves(layout(), vram()), repaint)
        self.assertFalse(gaze.overlap(found[(0, 0)][0], found[(1, 0)][0]))
        self.assertTrue(gaze.overlap([(0, 0, 8, 8)], [(4, 4, 8, 8)]))
        self.assertFalse(gaze.overlap([(0, 0, 8, 8)], [(8, 0, 8, 8)]))

    def test_the_sheet_holds_every_picture_apart(self) -> None:
        pictures = [np.full((h, w, 4), k + 1, dtype=np.uint8) for k, (w, h) in enumerate(((600, 10), (500, 20), (30, 5), (40, 40)))]
        pixels, where = gaze.sheet(pictures)
        self.assertEqual(pixels.shape[1], gaze.SHEET_WIDTH)
        for k, ((x, y), picture) in enumerate(zip(where, pictures)):
            h, w = picture.shape[:2]
            self.assertTrue((pixels[y:y + h, x:x + w] == k + 1).all(), f"picture {k}")
        self.assertEqual(int((pixels[..., 0] > 0).sum()), sum(p.shape[0] * p.shape[1] for p in pictures), "no overlap")

    def test_a_picture_wider_than_the_sheet_is_refused(self) -> None:
        with self.assertRaises(ValueError):
            gaze.sheet([np.zeros((4, gaze.SHEET_WIDTH + 1, 4), dtype=np.uint8)])


if __name__ == "__main__":
    unittest.main()
