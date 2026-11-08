"""The arcade flow's tables (arcade_flow.py) on a synthetic program: no game data."""

from __future__ import annotations

import struct
import unittest

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_flow


class Program:
    """`ArcadeSet.prog` over a few written ranges; anything else reads as zeros."""

    def __init__(self) -> None:
        self.written: dict[int, int] = {}

    def put(self, address: int, data: bytes) -> None:
        for i, byte in enumerate(data):
            self.written[address + i] = byte

    def prog(self, address: int, size: int) -> bytes:
        return bytes(self.written.get(address + i, 0) for i in range(size))

    def prog_values(self, fmt: str, address: int) -> tuple:
        return struct.unpack(fmt, self.prog(address, struct.calcsize(fmt)))


class Tables(unittest.TestCase):
    def test_the_sparks_read_each_side_and_layout(self) -> None:
        program = Program()
        for side, x in enumerate((0x12, 0x123)):
            program.put(arcade_flow.SELECT_PLAYERS + arcade_flow.SELECT_PLAYER_BYTES * side + arcade_flow.SELECT_PORTRAIT_X,
                        struct.pack("<h", x))
        for layout, y in enumerate((0xC8, 0xA0)):
            program.put(arcade_flow.SELECT_LAYOUTS + arcade_flow.SELECT_LAYOUT_BYTES * layout + arcade_flow.SELECT_PLATE_Y,
                        struct.pack("<i", y))
        data = arcade_flow.select_sparks(program)
        self.assertEqual(data["select_spark_x"], [0x12, 0x123])
        self.assertEqual(data["select_spark_y"], [0xC8, 0xA0])

    def test_the_schedule_ends_at_its_mark(self) -> None:
        program = Program()
        program.put(arcade_flow.UNLOCKS, struct.pack("<HHI", 3, 2, 10) + struct.pack("<HHI", 7, 3, 11)
                    + struct.pack("<HHI", arcade_flow.UNLOCK_END, 0, 0) + struct.pack("<HHI", 9, 9, 9))
        self.assertEqual(arcade_flow.unlock_schedule(program), [[3, 2, 10], [7, 3, 11]])

    def test_the_demonstration_keeps_its_end_mark(self) -> None:
        program = Program()
        program.put(arcade_flow.ENBU_SCRIPT, struct.pack("<5h", 0, 2, 1, 0, 0) + struct.pack("<5h", 20, arcade_flow.ENBU_END, 0, 0, 0)
                    + struct.pack("<5h", 30, 2, 2, 0, 0))
        self.assertEqual(arcade_flow.scene_script(program, arcade_flow.ENBU_SCRIPT), [0, 2, 1, 0, 0, 20, arcade_flow.ENBU_END, 0, 0, 0])

    def test_a_string_stops_at_its_zero(self) -> None:
        program = Program()
        program.put(0x80100000, b"PAUL\0XYZ")
        self.assertEqual(arcade_flow.string_at(program, 0x80100000), "PAUL")

    def test_a_character_record_by_its_pointer(self) -> None:
        program = Program()
        record = 0x80100000
        name = 0x80100100
        program.put(name, b"KING\0")
        raw = bytearray(arcade_flow.RECORD_MUSIC + 1)
        struct.pack_into("<I", raw, arcade_flow.RECORD_NAME, name)
        raw[arcade_flow.RECORD_VOICE] = 2
        raw[arcade_flow.RECORD_MOKUJIN_BANK] = 3
        raw[arcade_flow.RECORD_STAGE] = 11
        raw[arcade_flow.RECORD_MUSIC] = 20
        program.put(record, bytes(raw))
        program.put(arcade_flow.VOICES + arcade_flow.VOICE_SET_BYTES * 2, struct.pack("<h", 0x1024))
        for key in range(arcade_flow.CHARACTER_KEYS):
            program.put(arcade_flow.CHARACTER_RECORDS + 4 * key, struct.pack("<I", record))
        first = arcade_flow.character_records(program)[0]
        self.assertEqual(first, {"name": "KING", "stage": 11, "music": 20, "voice": 0x1024, "mokujin_bank": 3})


if __name__ == "__main__":
    unittest.main()
