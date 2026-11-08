"""The arcade CPU's tables (arcade_ai_tables.py) on a synthetic program image: no game data."""

from __future__ import annotations

import struct
import types
import unittest

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_ai_tables as tables
import arcade_tables

PROGRAM_BASE = 0x80010000
PROGRAM_SIZE = 0x200000


def _image() -> tuple[bytearray, types.SimpleNamespace]:
    image = bytearray(PROGRAM_SIZE)

    def prog_values(fmt: str, addr: int) -> tuple:
        return struct.unpack_from(fmt, image, addr - PROGRAM_BASE)

    return image, types.SimpleNamespace(prog_values=prog_values)


def _put(image: bytearray, fmt: str, addr: int, *values: int) -> None:
    struct.pack_into(fmt, image, addr - PROGRAM_BASE, *values)


def _steps_fixture(image: bytearray) -> None:
    """A script at each single-script table: its address's low bits make it recognisable."""
    _put(image, "<3H", tables.BACK_DASH, 0x11, 0x12, 0)
    _put(image, "<4H", tables.WAKE_UP, 0, 0x21, 0x22, 0)
    _put(image, "<3H", tables.TAP_FORWARD, 0x7777, 0x31, 0)      # the window word is skipped
    _put(image, "<3H", tables.TAP_BACK, 0x7777, 0x41, 0)
    _put(image, "<2H", tables.SIDE_STEP_SCRIPTS, 0x51, 0)
    _put(image, "<2H", tables.SIDE_STEP_SCRIPTS + tables.SIDE_STEP_STRIDE, 0x52, 0)
    _put(image, "<2H", tables.KING_THROWS + 2 * tables.KING_SCRIPT_STRIDE, 0x63, 0)


class Params(unittest.TestCase):
    def test_flattened_by_group_difficulty_and_level(self) -> None:
        image, arc = _image()
        group, difficulty, level, word = 1, 3, 7, 59
        offset = group * 6000 + difficulty * 1200 + level * 120 + word * 2     # FUN_801C2FCC's address
        _put(image, "<h", tables.AI_PARAMS + offset, -5)
        params = tables.tables(arc)["params"]
        self.assertEqual(len(params), 10)
        self.assertEqual(len(params[0]), 10)
        self.assertEqual(len(params[0][0]), 60)
        self.assertEqual(params[group * tables.AI_DIFFICULTIES + difficulty][level][word], -5)


class Sequences(unittest.TestCase):
    def test_each_sequence_starts_on_four_bytes(self) -> None:
        image, arc = _image()
        at = PROGRAM_BASE + 0x1000
        _put(image, "<4H", at, 0x3B, 0x11, 0x12, 0)              # ends on a boundary
        _put(image, "<5H", at + 8, 0x3C, 0x21, 0x22, 0x23, 0)    # one padding word follows
        _put(image, "<3H", at + 20, 0x3D, 0x31, 0)
        self.assertEqual(arcade_tables.sequences(arc, at, 3), [[0x3B, 0x11, 0x12], [0x3C, 0x21, 0x22, 0x23], [0x3D, 0x31]])


class Pads(unittest.TestCase):
    def test_a_step_reads_every_value_of_its_low_nibble(self) -> None:
        image, arc = _image()
        _put(image, "<H", tables.NUMPAD_PADS + 2 * 9, 0x2400)
        _put(image, "<H", tables.NUMPAD_PADS + 2 * 15, 0x77)
        pads = tables.tables(arc)["numpad_pads"]
        self.assertEqual(len(pads), 16)
        self.assertEqual((pads[9], pads[15]), (0x2400, 0x77))


class Scripts(unittest.TestCase):
    def setUp(self) -> None:
        image, arc = _image()
        _steps_fixture(image)
        self.t = tables.tables(arc)

    def test_a_script_stops_at_its_terminator(self) -> None:
        self.assertEqual(self.t["back_dash"], [0x11, 0x12])

    def test_a_first_step_of_zero_is_kept(self) -> None:
        self.assertEqual(self.t["wake_up"], [0, 0x21, 0x22])

    def test_sequences_skip_their_window(self) -> None:
        self.assertEqual(self.t["tap_forward"], [0x31])
        self.assertEqual(self.t["tap_back"], [0x41])

    def test_strided_scripts(self) -> None:
        self.assertEqual(self.t["side_steps"], [[0x51], [0x52]])
        self.assertEqual(self.t["king_throws"][2], [0x63])
        self.assertEqual(self.t["king_throws"][0], [0])


class Hooks(unittest.TestCase):
    def test_names_by_address(self) -> None:
        image, arc = _image()
        _put(image, "<iII", tables.HOOKS, 0, 0x801CE078, 0)
        _put(image, "<iII", tables.HOOKS + tables.HOOK_STRIDE, 3, 0x801CE070, 0x801CE618)
        rows = tables.tables(arc)["hooks"]
        self.assertEqual(len(rows), tables.HOOK_COUNT)
        self.assertEqual(rows[0], [0, "vs_paul", ""])
        self.assertEqual(rows[1], [3, "idle", "as_king"])


class Banks(unittest.TestCase):
    def test_setups_end_at_a_negative_chance(self) -> None:
        image, arc = _image()
        setups, script, high = 0x80100000, 0x80100100, 0x80100200
        _put(image, "<iIII", tables.BANK_RECORDS + tables.BANK_RECORD_STRIDE, 1, high, 0, setups)
        _put(image, "<hhI", setups, 1024, 0x2C, script)
        _put(image, "<hhI", setups + tables.SETUP_STRIDE, -1, -1, 0)
        _put(image, "<3H", script, 0x7777, 0x71, 0)
        _put(image, "<2H", high, 0x81, 0)
        bank = tables.tables(arc)["banks"][1]
        self.assertEqual(bank["counter"], 1)
        self.assertEqual(bank["parry_high"], [0x81])
        self.assertEqual(bank["parry_low"], [])
        self.assertEqual(bank["setups"], [[1024, 0x2C, [0x71]]])

    def test_a_null_table_gives_nothing(self) -> None:
        _image_, arc = _image()
        bank = tables.tables(arc)["banks"][0]
        self.assertEqual(bank, {"counter": 0, "parry_high": [], "parry_low": [], "setups": []})


if __name__ == "__main__":
    unittest.main()
