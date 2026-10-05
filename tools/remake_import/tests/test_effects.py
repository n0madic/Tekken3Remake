"""Effect conversions (effects.py) on synthetic tables: no game data."""

from __future__ import annotations

import unittest
from types import SimpleNamespace

import effects

LAYOUT = (0, 503, 368, 0, 16, 512)   # clut x, y, then the upload's x (words), y and page size


def _disc(table: list[tuple[int, int]]):
    """A disc whose executable holds player 0's upload layout and the glow's UV table."""
    uv_table = effects.OBJECT_UV_TABLES[-1][0]

    def exe_s16(addr: int, count: int) -> list[int]:
        assert addr == effects.LAYOUTS and count == len(LAYOUT)
        return list(LAYOUT)

    def exe_u8(addr: int, count: int) -> list[int]:
        return list(table[(addr - uv_table) // 2][:count])

    return SimpleNamespace(exe_s16=exe_s16, exe_u8=exe_u8)


class BallGlowTest(unittest.TestCase):
    def test_steps_name_frames_of_the_upload(self) -> None:
        # Two 8-word frames per 32-line row: (u, v + 128) = (8, 128) is row 4's second frame.
        table = [(8, 0), (0, 32), (8, 32), (0, 64)] + [(0, 0)] * 8
        self.assertEqual(effects._ball_glow_frames(_disc(table))[:4], [9, 10, 11, 12])
        self.assertEqual(effects._ball_glow_frames(_disc(table))[4], 8)

    def test_step_outside_the_upload(self) -> None:
        table = [(4, 0)] + [(0, 0)] * 11      # between two frames: none
        self.assertEqual(effects._ball_glow_frames(_disc(table))[0], -1)


if __name__ == "__main__":
    unittest.main()
