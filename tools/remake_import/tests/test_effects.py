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


class CostumeCharactersTest(unittest.TestCase):
    @staticmethod
    def _keys(**slots: int) -> list[int]:
        """A key table (`key<n>=slot`) with no costume anywhere else but Paul's first, slot 0 (key 0),
        which the placeholder keys after the named ones name as well."""
        table = [-1] * effects.COSTUME_KEY_COUNT
        table[0] = 0
        table[effects.NAMED_KEYS:] = [0] * (effects.COSTUME_KEY_COUNT - effects.NAMED_KEYS)
        for name, slot in slots.items():
            table[int(name.removeprefix("key"))] = slot
        return table

    def test_force_enemies_have_their_flipbook(self) -> None:
        # Keys 84-87 are charId 21's four sets, slots 47-50 (issue #25: they had none).
        found = effects.costume_characters(self._keys(key84=47, key85=48, key86=49, key87=50))
        for slot in range(47, 51):
            self.assertEqual(found[slot], (21, 21))

    def test_a_shared_slot_takes_the_arcade_set_of_its_owner(self) -> None:
        # Slot 36 is Nina's third costume (key 22) and Anna's first (key 72): the PlayStation's charId
        # record is the first user's, the arcade's set the last named key's.
        self.assertEqual(effects.costume_characters(self._keys(key22=36, key72=36))[36], (5, 18))

    def test_a_missing_costume_has_none(self) -> None:
        found = effects.costume_characters(self._keys(key4=2, key5=-1))
        self.assertEqual(set(found), {0, 2})

    def test_the_placeholder_keys_do_not_replace_slot_0(self) -> None:
        self.assertEqual(effects.costume_characters(self._keys())[0], (0, 0))


if __name__ == "__main__":
    unittest.main()
