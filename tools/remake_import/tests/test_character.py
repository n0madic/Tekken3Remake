"""The PlayStation character models' hand and jaw variant groups (character.py): no game data."""

from __future__ import annotations

import struct
import unittest
from types import SimpleNamespace
from unittest import mock

import numpy as np

import common  # noqa: F401  (puts tools/research on the import path)
import character
import kmd as kmdlib
import tables
from vram import Vram

HAND_ROW = kmdlib.PART_ROW[16]          # channel 0's hand: row 18
OTHER_HAND_ROW = kmdlib.PART_ROW[12]    # channel 1's hand: row 14
HEAD_ROWS = (19, 20)                    # part 17's mesh and its second mesh


def _block(variant: int, count: int, moves: tuple[int, ...]) -> SimpleNamespace:
    """A vertex block whose vertices in `moves` shift by the variant number."""
    return SimpleNamespace(coords=[(i + (variant if i in moves else 0), 0, 0) for i in range(count)])


def _model(rows: dict[int, int]) -> SimpleNamespace:
    """A model with the given rows (index → vertex count) that have variants; others have none."""
    entries = []
    for index in range(kmdlib.ROW_COUNT):
        count = rows.get(index)
        entries.append(SimpleNamespace(variants=[0] * kmdlib.VARIANT_SLOTS if count else None,
                                       verts=_block(0, count, ()) if count else None))
    return SimpleNamespace(rows=entries)


class FakeDisc:
    """A disc whose costume key table is `keys` (the costume slot of each key)."""

    def __init__(self, keys: list[int]) -> None:
        self.keys = keys

    def exe_u8(self, address: int, count: int) -> list[int]:
        assert address == tables.COSTUME_KEYS
        return (self.keys + [0] * count)[:count]


class PoseGroupTest(unittest.TestCase):
    MOVES = {HAND_ROW: (1, 2), OTHER_HAND_ROW: (0,), HEAD_ROWS[0]: (3, 4, 5), HEAD_ROWS[1]: (1,)}

    def groups(self, rows: dict[int, int], jaw: bool) -> list[character.VariantGroup]:
        def variant_block(data, model, row, variant):
            return _block(variant, rows[row], self.MOVES[row])

        with mock.patch.object(character, "variant_block", variant_block):
            return character.pose_groups(b"", _model(rows), jaw)

    def test_the_channels_hold_the_hands_unless_the_costume_has_a_jaw(self) -> None:
        self.assertEqual(character.hand_parts(False), (16, 12))
        self.assertEqual(character.hand_parts(True), (17, 12), "channel 0 selects the head's variants instead")

    def test_a_part_has_its_row_and_the_second_mesh_of_the_parts_that_draw_one(self) -> None:
        self.assertEqual(character.part_rows(16), [HAND_ROW])
        self.assertEqual(character.part_rows(17), list(HEAD_ROWS))

    def test_the_hands_are_whole_rows_per_variant(self) -> None:
        rows = {HAND_ROW: 6, OTHER_HAND_ROW: 4}
        left, right = self.groups(rows, False)
        for channel, group, row in ((0, left, HAND_ROW), (1, right, OTHER_HAND_ROW)):
            self.assertEqual((group.key, group.channel, group.part, group.count, group.packed),
                             (character.HANDS, channel, character.HAND_PARTS[channel], character.HAND_VARIANTS, False))
            self.assertEqual(group.moving, {(row, i) for i in range(rows[row])}, "every vertex of the row")
            self.assertEqual(group.coords[row][5][self.MOVES[row][0]], (self.MOVES[row][0] + 5, 0, 0))

    def test_the_jaw_covers_both_head_meshes_packed_by_the_vertices_that_move(self) -> None:
        rows = {OTHER_HAND_ROW: 4, **{row: 8 for row in HEAD_ROWS}}
        jaw, hand = self.groups(rows, True)
        self.assertEqual((jaw.key, jaw.channel, jaw.part, jaw.count, jaw.packed),
                         (character.HANDS, 0, character.JAW_PART, character.HAND_VARIANTS, True))
        self.assertEqual(jaw.moving, {(19, 3), (19, 4), (19, 5), (20, 1)})
        self.assertEqual(jaw.distinct, character.HAND_VARIANTS, "every synthetic variant differs")
        self.assertEqual(jaw.coords[20][jaw.select[7]][1], (8, 0, 0))
        self.assertEqual((hand.channel, hand.part), (1, 12), "the other hand is unchanged")

    def test_the_jaw_of_a_head_with_one_variant_row_is_that_row(self) -> None:
        (jaw,) = self.groups({HEAD_ROWS[1]: 8}, True)
        self.assertEqual(jaw.moving, {(20, 1)})
        self.assertEqual(list(jaw.coords), [20], "row 19 has no variant table: it is left as it is")

    def test_a_costume_without_variant_rows_has_no_group(self) -> None:
        self.assertEqual(self.groups({}, False), [])
        self.assertEqual(self.groups({}, True), [])

    def test_a_hand_costume_ignores_the_head_rows(self) -> None:
        self.assertEqual(self.groups({row: 8 for row in HEAD_ROWS}, False), [])
        (hand,) = self.groups({HAND_ROW: 6, HEAD_ROWS[1]: 8}, False)
        self.assertEqual((hand.channel, hand.part), (0, 16))


class JawCostumeTest(unittest.TestCase):
    def keys(self, **by_character: tuple[int, ...]) -> list[int]:
        """A key table (charId · 4 + costume) with the slots of the given characters (by id)."""
        keys = [-1] * tables.COSTUME_KEY_COUNT
        for char_id, slots in ((int(name[1:]), s) for name, s in by_character.items()):
            keys[char_id * 4:char_id * 4 + len(slots)] = slots
        return keys

    def test_kuma_panda_and_gon_have_a_jaw(self) -> None:
        disc = FakeDisc(self.keys(c11=(22, 23), c17=(42, 43), c0=(0, 1)))
        self.assertEqual([character.has_jaw(character.costume_characters(disc, slot)) for slot in (22, 23, 42, 43)], [True] * 4)
        self.assertEqual([character.has_jaw(character.costume_characters(disc, slot)) for slot in (0, 1, 2, 44)], [False] * 4)

    def test_a_slot_shared_with_other_characters_has_a_jaw_only_through_its_own(self) -> None:
        disc = FakeDisc(self.keys(c5=(36,), c18=(36,), c11=(22,)))
        self.assertFalse(character.has_jaw(character.costume_characters(disc, 36)))
        self.assertTrue(character.has_jaw(character.costume_characters(disc, 22)))


class PaletteDisc(FakeDisc):
    """A disc with Gon's palette table (size, palette, backup, swapped indices) for slot 42 and rectangles."""
    TABLE = [5, 45, 47, 44]
    RECTS = {44: (240, 506), 45: (48, 504), 47: (220, 506)}
    SIZES = {5: (16, 1)}

    def exe_u8(self, address: int, count: int) -> list[int]:
        if address == character.PALETTE_TABLE + 4 * 42:
            return self.TABLE
        return super().exe_u8(address, count)

    def exe_s16(self, address: int, count: int) -> list[int]:
        if address >= character.EYE_SIZES:
            return list(self.SIZES[(address - character.EYE_SIZES) // 4])
        return list(self.RECTS[(address - character.EYE_RECTS) // 4])


class GonPaletteTest(unittest.TestCase):
    def characters(self, char_id: int) -> tuple[PaletteDisc, set[int]]:
        keys = [-1] * tables.COSTUME_KEY_COUNT
        keys[char_id * 4] = 42
        disc = PaletteDisc(keys)
        return disc, character.costume_characters(disc, 42)

    def test_gons_swapped_palette_is_the_black_one_over_his_head_palette(self) -> None:
        disc, characters = self.characters(character.GON)
        self.assertEqual(character.palette_copy(disc, characters, 42), ((240, 506, 16, 1), (48, 504)))

    def test_other_characters_have_none(self) -> None:
        disc, characters = self.characters(11)
        self.assertIsNone(character.palette_copy(disc, characters, 42))
        self.assertIsNone(character.palette_swap(disc, characters, 42, Vram()))
        self.assertIsNone(character.gaze_strips(disc, characters, 42, Vram(), None))

    def test_the_swapped_vram_has_the_copy_and_leaves_the_original(self) -> None:
        vram = Vram()
        vram.words[504, 48:64] = np.arange(1, 17)
        vram.words[506, 240:256] = 0x8000
        disc, characters = self.characters(character.GON)
        shown = character.palette_swap(disc, characters, 42, vram)
        self.assertTrue((shown.words[504, 48:64] == 0x8000).all())
        self.assertEqual(vram.words[504, 48], 1, "the original palette is kept for the normal atlas")
        self.assertTrue((shown.words[506, 240:256] == 0x8000).all(), "the source is left as it is")


class EnemyDisc:
    """A disc whose BNS records are archives of member 0 only (an enemy texture archive)."""

    def __init__(self, member0: bytes) -> None:
        self.record = struct.pack("<III", 1, 12, len(member0)) + member0

    def bns(self, arc_id: int) -> bytes:
        return self.record


def _tim(colour: int) -> bytes:
    """A 4-bit TIM of 16 × 2 words: every pixel is index 1, whose CLUT colour is `colour`."""
    clut = struct.pack("<I4H", 12 + 32, 0, 0, 16, 1) + struct.pack("<16H", 0, colour, *[0] * 14)
    image = struct.pack("<I4H", 12 + 64, 0, 0, 16, 2) + b"\x11" * 64
    return struct.pack("<II", 0x10, 8) + clut + image


class ForceEnemyTexturesTest(unittest.TestCase):
    COLOURS = (0x001F, 0x03E0, 0x7C00, 0x7FFF)

    def setUp(self) -> None:
        members = [_tim(colour) for colour in self.COLOURS]
        header = struct.pack("<I", len(members))
        offset = 4 + 8 * len(members)
        for member in members:
            header += struct.pack("<II", offset, len(member))
            offset += len(member)
        self.disc = EnemyDisc(header + b"".join(members))

    def first_pixel(self, vram: Vram) -> tuple:
        page_x, page_y, depth, clut_x, clut_y = character.material_page(0)
        return tuple(vram.page_rgba(page_x, page_y, depth, clut_x, clut_y)[0, 0])

    def test_each_enemy_slot_is_drawn_with_its_own_set_at_the_origin(self) -> None:
        pixels = [self.first_pixel(character.model_textures(self.disc, slot, 0)) for slot in character.FORCE_ENEMY_SLOTS]
        self.assertEqual(len(set(pixels)), 4, "the four enemies have four different palettes")
        expected = [self.first_pixel(character.load_textures(self.disc.bns(0)[12:], k)) for k in range(4)]
        self.assertEqual(pixels, expected)

    def test_all_sets_upload_side_by_side_for_the_name_strip(self) -> None:
        member0 = self.disc.bns(0)[12:]
        vram = character.load_textures(member0)
        self.assertEqual(self.first_pixel(vram), self.first_pixel(character.load_textures(member0, 0)))
        shifted = vram.page_rgba(384, 0, 4, 0, character.CLUT_ORIGIN_Y + 2)[0, 64 * 2]
        self.assertEqual(tuple(shifted), self.first_pixel(character.load_textures(member0, 2)))

    def test_other_slots_share_the_costume_textures(self) -> None:
        self.disc.costume_vrams = {}
        self.assertIs(character.model_textures(self.disc, 5, 7), character.model_textures(self.disc, 5, 7))


if __name__ == "__main__":
    unittest.main()
