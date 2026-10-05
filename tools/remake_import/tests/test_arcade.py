"""The arcade stage converter (arcade.py) on synthetic ROM data: no game data."""

from __future__ import annotations

import struct
import tempfile
import unittest
import zipfile
from pathlib import Path

import numpy as np

import arcade
from vram import Vram

TSB_4BIT = 0x0008            # page (512, 0), 4-bit
CBA = (300 << 6) | 2         # CLUT at (32, 300)


def _packet(mode: int, flag: int, words: list[int]) -> bytes:
    return bytes((len(words) + 2, len(words), flag, mode)) + struct.pack(f"<{len(words)}I", *words)


def _uv(u: int, v: int, high: int = 0) -> int:
    return u | v << 8 | high << 16


def _tmd(objects: dict[int, tuple[list[tuple[int, int, int]], list[bytes]]]) -> bytes:
    """A scene TMD with 256 rows; `objects`: index → (vertices, packets)."""
    table = bytearray(12 + 28 * arcade.SCENE_OBJECTS)
    struct.pack_into("<III", table, 0, 0x41, 400, arcade.SCENE_OBJECTS)
    body = bytearray()
    rows = {}
    for index, (verts, packets) in objects.items():
        prim_top = len(table) - 12 + len(body)
        body += b"".join(packets)
        rows[index] = (verts, prim_top, len(packets))
    for index, (verts, prim_top, count) in rows.items():
        vert_top = len(table) - 12 + len(body)
        for x, y, z in verts:
            body += struct.pack("<4h", x, y, z, 0)
        struct.pack_into("<6Ii", table, 12 + 28 * index, vert_top, len(verts), 0, 0, prim_top, count, 0)
    return bytes(table + body)


class DecompressTest(unittest.TestCase):
    def test_literals_references_and_end(self) -> None:
        # Flag 0b1101 (sentinel bit 3): literal 'a', reference, literal 'b'; then a flag of 0 ends.
        # The reference copies 3 bytes from distance 1 (overlapping its own output).
        stream = bytes([0b1101, ord("a"), 3 << 3, 1, ord("b"), 0])
        out, end = arcade.decompress(stream)
        self.assertEqual(out, b"aaaab")
        self.assertEqual(end, len(stream))

    def test_zero_encodings(self) -> None:
        # Length 0 means 32; a flag of 1 has no tokens and is skipped.
        stream = bytes([0b11, ord("x"), 1, 0b10, 0, 1, 0])
        out, _ = arcade.decompress(stream)
        self.assertEqual(out, b"x" * 33)

    def test_reference_before_start(self) -> None:
        with self.assertRaises(arcade.ArcadeError):
            arcade.decompress(bytes([0b10, 1 << 3, 5, 0]))

    def test_interleave(self) -> None:
        self.assertEqual(arcade.interleave(b"ace", b"bdf"), b"abcdef")


class PacketTest(unittest.TestCase):
    def test_unlit_textured_quad(self) -> None:
        data = _packet(0x2D, 1, [_uv(1, 2, CBA), _uv(3, 4, TSB_4BIT), _uv(5, 6), _uv(7, 8),
                                 0x00302010, 1 | 2 << 16, 3 | 0 << 16])
        packet, end = arcade.parse_packet(data, 0)
        self.assertEqual(end, len(data))
        self.assertEqual(packet.verts, [1, 2, 3, 0])
        self.assertEqual(packet.uvs, [(1, 2), (3, 4), (5, 6), (7, 8)])
        self.assertEqual((packet.cba, packet.tsb), (CBA, TSB_4BIT))
        self.assertEqual(packet.colours, [(0x10, 0x20, 0x30)])
        self.assertIsNone(packet.window)

    def test_lit_gouraud_quad_uses_neutral_colour(self) -> None:
        # Lit packets interleave normal and vertex indices; the game builds them with 0x80.
        data = _packet(0x3C, 0, [_uv(0, 0, CBA), _uv(0, 0, TSB_4BIT), 0, 0,
                                 9 | 4 << 16, 9 | 5 << 16, 9 | 6 << 16, 9 | 7 << 16])
        packet, _ = arcade.parse_packet(data, 0)
        self.assertEqual(packet.verts, [4, 5, 6, 7])
        self.assertEqual(packet.colours, [arcade.LIT_COLOUR])

    def test_window_from_padding(self) -> None:
        # Mode bit 0x80: w, h in uv2's padding, x, y in uv3's.
        data = _packet(0xAD, 1, [_uv(0, 0, CBA), _uv(63, 0, TSB_4BIT), _uv(0, 63, 16 | 32 << 8),
                                 _uv(63, 63, 0), 0x808080, 0 | 1 << 16, 2 | 3 << 16])
        packet, _ = arcade.parse_packet(data, 0)
        self.assertEqual(packet.window, (0, 0, 16, 32))

    def test_lit_untextured_keeps_its_colour(self) -> None:
        # FUN_801E2370 builds lit flat and Gouraud polygons with the packet's colour.
        flat = _packet(0x28, 0, [0x00302010, 9 | 0 << 16, 1 | 2 << 16, 3])
        packet, _ = arcade.parse_packet(flat, 0)
        self.assertEqual(packet.verts, [0, 1, 2, 3])
        self.assertEqual(packet.colours, [(0x10, 0x20, 0x30)])
        gouraud = _packet(0x30, 0, [0x00605040, 9 | 4 << 16, 9 | 5 << 16, 9 | 6 << 16])
        packet, _ = arcade.parse_packet(gouraud, 0)
        self.assertEqual(packet.verts, [4, 5, 6])
        self.assertEqual(packet.colours, [(0x40, 0x50, 0x60)])

    def test_corner_colours(self) -> None:
        # Textured: the packet colour scales the texel; untextured: the colour shown, in linear light.
        self.assertEqual(arcade.corner_colour((0x80, 0x40, 0), True), (1.0, 0.5, 0.0))
        self.assertEqual(arcade.corner_colour((255, 0, 0), False), (1.0, 0.0, 0.0))
        red, green, _ = arcade.corner_colour((0x1E, 0x1E, 0), False)
        self.assertAlmostEqual(red, 0.01298, places=5)
        self.assertEqual(red, green)

    def test_flat_untextured(self) -> None:
        packet, _ = arcade.parse_packet(_packet(0x29, 1, [0x00030201, 0 | 1 << 16, 2 | 3 << 16]), 0)
        self.assertIsNone(packet.uvs)
        self.assertEqual(packet.colours, [(1, 2, 3)])


class SceneTest(unittest.TestCase):
    def test_corners_skip_and_keys(self) -> None:
        quad = [(0, 0, 0), (100, 0, 0), (0, -100, 0), (100, -100, 0)]
        textured = _packet(0x2D, 1, [_uv(0, 0, CBA), _uv(15, 0, TSB_4BIT), _uv(0, 15), _uv(15, 15),
                                     0x808080, 0 | 1 << 16, 2 | 3 << 16])
        windowed = _packet(0xAD, 1, [_uv(0, 0, CBA), _uv(31, 0, TSB_4BIT), _uv(0, 31, 16 | 16 << 8),
                                     _uv(31, 31), 0x808080, 0 | 1 << 16, 2 | 3 << 16])
        tmd = _tmd({0: (quad, [textured]), 0xC6: (quad, [windowed])})
        cell, corners = arcade.scene_corners(tmd, 1)
        self.assertEqual(cell, 4000)
        self.assertEqual(len(corners), 12)
        self.assertEqual({c[0] for c in corners}, {f"{CBA:04x}_{TSB_4BIT:04x}", f"{CBA:04x}_{TSB_4BIT:04x}_0_0_16_16"})
        # Stage 0 leaves object 0xC6 out (FUN_801D73E4).
        _, corners = arcade.scene_corners(tmd, 0)
        self.assertEqual(len(corners), 6)
        self.assertEqual([c[1] for c in corners[:3]], quad[:3])

    def test_mesh_windows_and_atlas(self) -> None:
        vram = Vram(1024)
        vram.words[300, 32:48] = np.arange(16, dtype=np.uint16) | 0x8000   # opaque CLUT
        vram.words[0:64, 512:528] = 0x4321
        quad = [(0, 0, 0), (100, 0, 0), (0, -100, 0), (100, -100, 0)]
        windowed = _packet(0xAD, 1, [_uv(0, 0, CBA), _uv(31, 0, TSB_4BIT), _uv(0, 31, 16 | 16 << 8),
                                     _uv(31, 31), 0x808080, 0 | 1 << 16, 2 | 3 << 16])
        _, corners = arcade.scene_corners(_tmd({0: (quad, [windowed])}), 1)
        packed, (mesh,) = arcade.scene_mesh(vram, corners)
        floats = np.frombuffer(mesh, "<f4").reshape(-1, arcade.SCENE_FLOATS)
        self.assertEqual(len(floats), 6)
        # Window corners keep page texels and carry the window's atlas rectangle.
        self.assertEqual(tuple(floats[1, 3:5]), (31.0, 0.0))
        self.assertEqual(tuple(floats[0, 7:9]), (16.0, 16.0))
        region = next(iter(packed.regions.values()))
        self.assertEqual(region.pixels.shape[:2], (16, 16))


class PropTest(unittest.TestCase):
    def test_one_object_tmd_shares_the_scene_atlas(self) -> None:
        quad = [(0, 0, 0), (100, 0, 0), (0, -100, 0), (100, -100, 0)]
        textured = _packet(0x2D, 1, [_uv(0, 0, CBA), _uv(15, 0, TSB_4BIT), _uv(0, 15), _uv(15, 15),
                                     0x808080, 0 | 1 << 16, 2 | 3 << 16])
        scene = _tmd({0: (quad, [textured])})
        prop = bytearray(_tmd({0: (quad, [textured])}))
        struct.pack_into("<I", prop, 8, 1)
        corners = arcade.prop_corners(bytes(prop), "prop")
        self.assertEqual(len(corners), 6)
        _, scene_corners = arcade.scene_corners(scene, 1)
        packed, meshes = arcade.scene_mesh(Vram(1024), scene_corners, corners)
        self.assertEqual(len(meshes), 2)
        self.assertEqual(meshes[0], meshes[1])
        self.assertEqual(len(packed.regions), 1)
        with self.assertRaises(arcade.ArcadeError):
            arcade.prop_corners(scene, "scene")


class AnimationTest(unittest.TestCase):
    def test_cycle_frames_through_the_scene_clut(self) -> None:
        """FUN_801E2114's copies, seen through the scene texture that shows the target block."""
        program = bytearray(arcade.TEXTURE_CYCLE - arcade.PROGRAM_BASE + 8 * arcade.TEXTURE_CYCLE_FRAMES)
        for k in range(arcade.TEXTURE_CYCLE_FRAMES):
            struct.pack_into("<4H", program, arcade.TEXTURE_CYCLE - arcade.PROGRAM_BASE + 8 * k, 512, 0, 64 * (k % 8), 0)
        arc = arcade.ArcadeSet(b"", b"", bytes(program))
        vram = Vram(1024)
        vram.words[300, 32:48] = np.arange(16, dtype=np.uint16) | 0x8000   # CLUT entry i = colour i
        for k in range(8):
            vram.words[64 * k:64 * (k + 1), 512:528] = 0x1111 * k             # source k: index k
        tx, ty = arcade.TEXTURE_CYCLE_TARGET[6]
        tsb = (tx // 64) | ((ty - 512) // 256) << 4 | 1 << 11                 # the target's 4-bit page
        quad = [(0, 0, 0), (100, 0, 0), (0, -100, 0), (100, -100, 0)]
        u0, v0 = 4 * (tx % 64), ty % 256
        textured = _packet(0x2D, 1, [_uv(u0, v0, CBA), _uv(u0 + 63, v0, tsb), _uv(u0, v0 + 63), _uv(u0 + 63, v0 + 63),
                                     0x808080, 0 | 1 << 16, 2 | 3 << 16])
        _, corners = arcade.scene_corners(_tmd({0: (quad, [textured])}), 6)
        packed, _ = arcade.scene_mesh(vram, corners)
        info, frames = arcade.scene_animation(arc, vram, packed, 6)
        region = next(iter(packed.regions.values()))
        self.assertEqual(info["rect"], [region.x, region.y, 64, 64])
        self.assertEqual(frames.shape, (64 * arcade.TEXTURE_CYCLE_FRAMES, 64, 4))
        expected = arcade.rgba(vram.clut(32, 300, 16))
        for k in (0, 3, 9):
            self.assertTrue((frames[64 * k:64 * (k + 1)] == expected[k % 8]).all(), k)

    def test_no_scene_texture_shows_the_block(self) -> None:
        arc = arcade.ArcadeSet(b"", b"", bytes(arcade.TEXTURE_CYCLE - arcade.PROGRAM_BASE + 128))
        quad = [(0, 0, 0), (100, 0, 0), (0, -100, 0), (100, -100, 0)]
        textured = _packet(0x2D, 1, [_uv(0, 0, CBA), _uv(15, 0, TSB_4BIT), _uv(0, 15), _uv(15, 15),
                                     0x808080, 0 | 1 << 16, 2 | 3 << 16])
        _, corners = arcade.scene_corners(_tmd({0: (quad, [textured])}), 6)
        packed, _ = arcade.scene_mesh(Vram(1024), corners)
        with self.assertRaises(arcade.ArcadeError):
            arcade.scene_animation(arc, Vram(1024), packed, 6)


class SkyTest(unittest.TestCase):
    def test_skipped_cells_are_retouched_as_tiles(self) -> None:
        self.assertEqual(arcade.sky_cell(ord("0")), arcade.SKY_TILE)
        self.assertEqual(arcade.sky_cell(0), arcade.SKY_TILE)

    def test_arcade_drawing_leaves_them(self) -> None:
        self.assertEqual(arcade.sky_cell(ord("0"), retouch=False), ord("0"))

    def test_drawn_and_fill_cells_are_kept(self) -> None:
        for cell in (arcade.SKY_TILE, arcade.SKY_FILL_LOWER, arcade.SKY_FILL_TINT):
            for retouch in (True, False):
                self.assertEqual(arcade.sky_cell(cell, retouch), cell)

    def _stage_zero_sky(self) -> tuple[arcade.ArcadeSet, Vram]:
        """Stage 0's sky: two tile columns (words 0 and 1: 4-bit pictures of index 1 and 2) and a
        four-cell map `1 0 d 1` (span 720: map width 4)."""
        base = 0x80170000
        cell_map, words, cluts = base, base + 16, base + 32
        program = bytearray(arcade.SKY_COLOURS + 12 - arcade.PROGRAM_BASE)
        struct.pack_into("<hhIIIhH", program, arcade.SKY_RECORDS - arcade.PROGRAM_BASE, 2, 1, words, cluts, cell_map, 0, 720)
        struct.pack_into("<3I", program, arcade.SKY_COLOURS - arcade.PROGRAM_BASE, 1 << 24 | 0x333333, 0, 1 << 24 | 0x0A0B0C)
        program[cell_map - arcade.PROGRAM_BASE:cell_map - arcade.PROGRAM_BASE + 4] = b"10d1"
        struct.pack_into("<2H", program, words - arcade.PROGRAM_BASE, 0x0000, 0x0001)   # u = 0, then 64
        struct.pack_into("<2H", program, cluts - arcade.PROGRAM_BASE, CBA, CBA)
        vram = Vram(1024)
        vram.words[300, 32:36] = [0x8000, 0x801F, 0x83E0, 0xFC00]                # CLUT: colours 0 to 3
        vram.words[0:64, 0:16] = 0x1111                                           # tile 0: index 1
        vram.words[0:64, 16:32] = 0x2222                                          # tile 1: index 2
        return arcade.ArcadeSet(b"", b"", bytes(program)), vram

    def test_picture_draws_skipped_cell_as_its_columns_tile(self) -> None:
        arc, vram = self._stage_zero_sky()
        _, picture = arcade.sky(arc, vram, 0)
        tile0, tile1 = picture[:, 0:64], picture[:, 64:128]
        self.assertTrue((tile0 == arcade.rgba(vram.clut(32, 300, 16))[1]).all())
        # Column 1 is `0`: drawn as word 1 (column 1 mod 2 columns of art), not left empty.
        self.assertTrue((tile1 == arcade.rgba(vram.clut(32, 300, 16))[2]).all())
        self.assertTrue((picture[:, 128:192, :3] == (0x0C, 0x0B, 0x0A)).all())    # 'd': the lower fill

    def test_picture_without_retouch_leaves_it_empty(self) -> None:
        arc, vram = self._stage_zero_sky()
        _, picture = arcade.sky(arc, vram, 0, retouch=False)
        self.assertTrue((picture[:, 64:128, 3] == 0).all())
        self.assertTrue((picture[:, 0:64, 3] == 255).all())


class FloorTest(unittest.TestCase):
    def test_tile_orientation_and_clut(self) -> None:
        vram = Vram(1024)
        vram.words[300, 32:48] = np.arange(16, dtype=np.uint16) | 0x8000
        vram.words[0:64, 512:528] = np.arange(16, dtype=np.uint16) * 0x1111   # column runs of index
        w0 = 0 | 0 << 8 | 0x0008 << 16
        tile = arcade._floor_tile(vram, w0, CBA << 16, w0)
        self.assertEqual(tile.shape, (64, 64, 4))
        expected = arcade.rgba(vram.clut(32, 300, 16))
        self.assertTrue((tile[:, 0] == expected[0]).all())
        self.assertTrue((tile[:, 63] == expected[15]).all())
        # Corner set 2 (bits 30–31) turns the tile half a turn.
        turned = arcade._floor_tile(vram, w0, CBA << 16, w0 | 2 << 30)
        self.assertTrue((turned[:, 0] == expected[15]).all())


class AddressTest(unittest.TestCase):
    def test_tall_vram_pages_and_cluts(self) -> None:
        self.assertEqual(arcade.tpage_xy(0x0813), (192, 768))
        self.assertEqual(arcade.clut_xy((700 << 6) | 5), (80, 700))
        self.assertEqual(arcade.depth_bits(0x0080), 8)


class SetTest(unittest.TestCase):
    def test_missing_chip(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "tekken3.zip"
            with zipfile.ZipFile(path, "w") as archive:
                archive.writestr("tet2vere1.2e", b"not the chip")
            with self.assertRaises(arcade.ArcadeError):
                arcade.open_set(path)

    def test_categories(self) -> None:
        """A category lists archive directories; files follow one another."""
        program = bytearray(arcade.CATEGORY_TABLE - arcade.PROGRAM_BASE + 8 * arcade.CATEGORIES + 64)
        lists = arcade.CATEGORY_TABLE + 8 * arcade.CATEGORIES
        struct.pack_into("<II", program, arcade.CATEGORY_TABLE - arcade.PROGRAM_BASE + 8 * 5, lists, 2)
        struct.pack_into("<II", program, lists - arcade.PROGRAM_BASE, 0x100, arcade.PRG_FILES + 0x40)
        banked = bytearray(0x200)
        struct.pack_into("<I2I2I", banked, 0x100, 2, 20, 3, 23, 1)
        banked[0x114:0x118] = b"abcd"
        program_rom = bytearray(0x80)
        struct.pack_into("<I2I", program_rom, 0x40, 1, 12, 2)
        program_rom[0x4C:0x4E] = b"xy"
        files = arcade.ArcadeSet(bytes(program_rom), bytes(banked), bytes(program)).category(5)
        self.assertEqual(files, [b"abc", b"d", b"xy"])


if __name__ == "__main__":
    unittest.main()
