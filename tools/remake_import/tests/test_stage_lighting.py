"""The stage light rig record (stage.lighting, stages.md#lighting) on a synthetic record: no game data."""

from __future__ import annotations

import struct
import unittest
from types import SimpleNamespace

import stage


def _disc(record: bytes, number: int):
    """A disc whose executable holds `record` as stage `number`'s light rig."""

    def exe_bytes(addr: int, count: int) -> bytes:
        assert addr == stage.LIGHT_RECORDS + stage.LIGHT_RECORD_BYTES * number
        assert count == stage.LIGHT_RECORD_BYTES
        return record

    return SimpleNamespace(exe_bytes=exe_bytes)


class LightingTest(unittest.TestCase):
    def test_record_fields(self) -> None:
        # Ambient word, base R, G, B (ldRGB order), light B, G, R, then pitch and yaw.
        record = struct.pack("<I4B4B2h", 0x898, 176, 146, 126, 0, 152, 184, 180, 0, 384, 2560)
        record += bytes(stage.LIGHT_RECORD_BYTES - len(record))
        light = stage.lighting(_disc(record, 3), 3)
        self.assertEqual(light["ambient"], 137)
        self.assertEqual(light["ambient_level"], 0x898)
        self.assertEqual(light["base_rgb"], [176, 146, 126])
        self.assertEqual(light["light_rgb"], [180, 184, 152])
        self.assertEqual((light["light_pitch"], light["light_yaw"]), (384, 2560))


if __name__ == "__main__":
    unittest.main()
