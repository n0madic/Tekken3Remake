"""The arcade effect objects' drawing (arcade_effect_objects.py) on a synthetic set: no game data."""

from __future__ import annotations

import io
import struct
import unittest
from types import SimpleNamespace

import numpy as np
from PIL import Image

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_effect_objects as objects
import arcade_effects
from tests.arcade_fixtures import filled_tim, literal

BASE = 0x80175000
MEMORY = 0xC000
DUST_SET = 3
CLOUD_PAGE_OF_FRAME = 3                 # the cloud's second frame comes from the dust's second page
SPARK_UV = (0x10, 0x20)


def _member(index: int, size: tuple[int, int]) -> bytes:
    """Category 42 member `index`: all texels index + 1, colour k = k."""
    return filled_tim(index + 1, list(range(16)), size)


class FakeSet:
    """Category 42's members, the dust set and the program's tables the converter reads."""

    def __init__(self) -> None:
        self.memory = bytearray(MEMORY)
        sizes = [(32, 64), (32, 64), (64, 64), (64, 64), (64, 256), (32, 64), (4, 1)]
        self.members = [literal(_member(i, size)) for i, size in enumerate(sizes)]
        dust = [filled_tim(9, [0] * 16) for _ in range(20)]
        self.dust = literal(b"".join(dust))
        self._put(arcade_effects.SYSTEM_RECORDS[-1], struct.pack(arcade_effects.RECORD, DUST_SET, 20, 64, 64, 0, 128, 128, 128))
        self._put(objects.UV_TABLES[0][0], bytes(SPARK_UV))
        self._put(objects.UV_TABLES[-1][0], bytes([0x40, 0, 0x40, 0x40]))
        self._put(objects.CLOUD_PAGES, struct.pack("<2I", 2, CLOUD_PAGE_OF_FRAME))
        self._put(objects.MODELS[1], struct.pack("<8h", -55, -55, 0, 0, 55, -55, 0, 0))

    def _put(self, address: int, data: bytes) -> None:
        self.memory[address - BASE:address - BASE + len(data)] = data

    def prog(self, address: int, count: int) -> bytes:
        return bytes(self.memory[address - BASE:address - BASE + count])

    def prog_values(self, fmt: str, address: int) -> tuple:
        return struct.unpack_from(fmt, self.memory, address - BASE)

    def category(self, number: int) -> list[bytes]:
        if number == objects.CATEGORY:
            return self.members
        return [b""] * DUST_SET + [self.dust]


class DrawingTest(unittest.TestCase):
    def setUp(self) -> None:
        self.files: dict[str, bytes] = {}
        out = SimpleNamespace(write=lambda rel, data: self.files.__setitem__(rel, data))
        self.block = objects.drawing(FakeSet(), out)
        self.atlas = np.array(Image.open(io.BytesIO(self.files["effects/arcade_object_page.png"])))[..., 0]

    def test_members_lie_where_the_loader_puts_them(self) -> None:
        for member, (page, x, y) in enumerate(objects.MEMBERS):
            ox, oy = objects.PAGE_ORIGINS[page]
            self.assertEqual(self.atlas[oy + y, ox + x], member + 1, f"member {member}")

    def test_dust_frames_fill_the_cloud_pages(self) -> None:
        cloud_x, cloud_y = objects.PAGE_ORIGINS[objects.DUST_PAGE]
        self.assertEqual(self.atlas[cloud_y, cloud_x], 9)
        second_x, second_y = objects.PAGE_ORIGINS[objects.DUST_PAGE + 1]
        self.assertEqual(self.atlas[second_y, second_x + 3 * objects.DUST_FRAME], 9)   # frame 19

    def test_a_table_frame_is_its_page_origin_plus_its_uv(self) -> None:
        spark = self.block["uv_tables"][0]
        self.assertEqual(spark["frames"][0], list(SPARK_UV))
        self.assertEqual((spark["size"], spark["palette"], spark["half"]), (16, 0, False))
        fire = self.block["uv_tables"][6]
        self.assertEqual((fire["frames"][1], fire["palette"]), ([objects.PAGE, 0], 4))

    def test_the_cloud_takes_each_frame_page_and_blends_half(self) -> None:
        cloud = self.block["uv_tables"][-1]
        ox, oy = objects.PAGE_ORIGINS[CLOUD_PAGE_OF_FRAME]
        self.assertEqual(cloud["frames"][:2], [[0x40, objects.PAGE], [ox + 0x40, oy + 0x40]])
        self.assertEqual((cloud["palette"], cloud["half"]), (objects.CLOUD_PALETTE, True))

    def test_models_are_their_four_corners(self) -> None:
        quads = self.block["quads"]
        self.assertEqual(len(quads), objects.MODEL_COUNT)
        self.assertEqual(quads[1][:2], [[-55, -55], [55, -55]])
        self.assertEqual(quads[8], [])


if __name__ == "__main__":
    unittest.main()
