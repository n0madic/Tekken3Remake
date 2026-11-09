"""The arcade's 2D assets (arcade_screens.py) on a synthetic set: made-up bytes, no game data."""

from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import common  # noqa: F401  (puts tools/research on the import path)
import arcade
import arcade_game
import arcade_screens as screens
from common import Output
from tests.arcade_fixtures import literal
from vram import TIM_ID, Vram

WHITE = 0x7FFF
RED = 0x001F
BLUE = 0x7C00
OPAQUE_WHITE = (255, 255, 255, 255)
PROGRAM_SIZE = 0x220000
FACE_CLUT = 1008 << 6           # CLUT (0, 1008)
STRINGS = 0x80100000
RECORDS = 0x80120000
GLYPHS = 0x80130000
FONTS = [screens.Font(GLYPHS, 12, 18, 12, 16, 0x2C, 0),
         screens.Font(GLYPHS, 18, 26, 18, 24, 0x2C, 0x10),
         screens.Font(GLYPHS, 30, 42, 32, 40, 0x2D, 0x20)]


def _block(x: int, y: int, w: int, h: int, words: list[int]) -> bytes:
    return struct.pack("<IHHHH", 12 + 2 * len(words), x, y, w, h) + struct.pack(f"<{len(words)}H", *words)


def _tim(image: tuple[int, int, int, int, list[int]], clut: tuple[int, int, int, int, list[int]] | None = None,
         depth: int = 4) -> bytes:
    flags = (1 if depth == 8 else 0) | (8 if clut else 0)
    return struct.pack("<II", TIM_ID, flags) + (_block(*clut) if clut else b"") + _block(*image)


def _clut_only(x: int, y: int, words: list[int], depth: int = 4) -> bytes:
    """A palette and the stub of a pixel block: a header promising pixels, a rectangle at (0, 0)."""
    stub = struct.pack("<IHHHH", 16, 0, 0, 4, 4) + b"\0\0\0\0"
    flags = (1 if depth == 8 else 0) | 8
    return struct.pack("<II", TIM_ID, flags) + _block(x, y, len(words), 1, words) + stub


def _picture_tim(index: int, width_words: int = 2, height: int = 2, colour: int = WHITE) -> bytes:
    """A TIM with its own palette, drawn by no rectangle (at (0, 0)), all of texel `index`."""
    palette = [0] * 16
    palette[index] = colour
    return _tim((0, 0, width_words, height, [index * 0x1111] * (width_words * height)), (0, 0, 16, 1, palette))


class Program:
    """A zeroed program image with tables written by address."""

    def __init__(self) -> None:
        self.data = bytearray(PROGRAM_SIZE)
        self.next_string = STRINGS

    def put(self, addr: int, data: bytes) -> None:
        offset = addr - arcade.PROGRAM_BASE
        self.data[offset:offset + len(data)] = data

    def pack(self, addr: int, fmt: str, *values: int) -> None:
        self.put(addr, struct.pack(fmt, *values))

    def string(self, text: str, addr: int | None = None) -> int:
        at = self.next_string if addr is None else addr
        self.put(at, text.encode("latin-1") + b"\0")
        if addr is None:
            self.next_string += len(text) + 1
        return at


def _fake_set() -> arcade.ArcadeSet:
    """A whole set's worth of tables and pictures for `arcade_screens.convert`."""
    p = Program()
    for k, font in enumerate(FONTS):
        p.pack(screens.FONT_TABLE + 20 * k, screens.FONT_RECORD, font.table, 0, font.advance, font.line, font.width,
               font.height, font.tpage, font.clut_base)
    p.pack(RECORDS, screens.CHARACTER_RECORD, p.string("AB"), 0, 8, 0, 1, 2, 3, 4, 5)
    p.pack(RECORDS + 16, "<II", 0x40 | 0x80 | 2, 0x030201)
    p.pack(screens.PICK_VOICES + screens.PICK_VOICE_STRIDE * 2, "<h", 77)
    p.pack(screens.CHARACTER_RECORDS, f"<{screens.CHARACTER_KEYS}I", *[RECORDS] * screens.CHARACTER_KEYS)
    p.pack(screens.ATTRIBUTES, f"<{screens.CHARACTER_KEYS}I", *[RECORDS + 16] * screens.CHARACTER_KEYS)
    p.pack(screens.ATTRIBUTE_DEFAULT, "<II", screens.ATTRIBUTE_SILHOUETTE, 0xB3B3B3)
    # Pointer tables: every string exists.
    text = p.string("TEXT %1x")
    for table, count in ((screens.PROMPTS, screens.PROMPT_COUNT), (screens.SIDE_PROMPTS, screens.SIDE_PROMPT_COUNT),
                         (screens.CREDITS, screens.CREDIT_COUNT)):
        for k in range(count):
            p.pack(table + 8 * k, "<Ih", text, 10 + k)
    for k in range(screens.STREAK_ENTRIES):
        p.pack(screens.STREAK_TABLE + 8 * k, "<I2h", p.string("%f%c%H%VW%01d"), 16, 300 + k)
    p.pack(screens.RANK_SUFFIXES, f"<{screens.RANK_SUFFIX_COUNT}I", *[p.string("X")] * screens.RANK_SUFFIX_COUNT)
    p.pack(screens.RANK_REJECTED, f"<{screens.RANK_REJECTED_COUNT}I", *[p.string("ZZZ")] * screens.RANK_REJECTED_COUNT)
    p.string(("Q" * screens.RANK_ALPHABET_SIZE), screens.RANK_ALPHABET)
    # Staff: every list is one name and its end.
    name, end = p.string("1N"), p.string("2")
    staff_list = RECORDS + 0x100
    p.pack(staff_list, "<II", name, end)
    for page in range(screens.STAFF_PAGE_COUNT):
        p.pack(screens.STAFF_PAGES + 8 * page, "<II", staff_list, staff_list)
    for table in screens.STAFF_FIRST_LISTS:
        p.pack(table, "<II", name, end)
    # Texts.
    p.string("%c%f%H%VHI", screens.TEXTS["ready"][0])
    # Select: frames end after a row; character 0's face in both layouts' VRAM.
    for table in screens.FRAME_TABLES:
        p.pack(table, screens.FRAME_RECORD, 0, 5, 6, 8, 4, 512, 768, 0x7A50)
        p.pack(table + 16, screens.FRAME_RECORD, screens.FRAME_END, 0, 0, 0, 0, 0, 0, 0)
    p.pack(screens.FACE_TABLE, "<IH", FACE_CLUT << 16, 0x884)
    for layout in range(2):
        fields = [0] * screens.LAYOUT_FIELDS
        fields[screens.LAYOUT_FACE_HEIGHT] = 4
        fields[screens.LAYOUT_CURSOR_HEIGHT] = 8
        fields[screens.LAYOUT_PANEL_TOP] = 100
        fields[screens.LAYOUT_TIMER_CLUT] = 0x791A
        p.pack(screens.LAYOUTS + 4 * screens.LAYOUT_FIELDS * layout, f"<{screens.LAYOUT_FIELDS}i", *fields)
    p.pack(screens.TILE_ROWS, f"<{screens.TILE_MAP ** 2}B", *[3] * screens.TILE_MAP ** 2)
    # The categories.
    font_clut = _clut_only(screens.TEXT_CLUT_X + 16 * 2, screens.TEXT_CLUT_Y, [0] + [WHITE] * 15)
    face = [0x0101] * 16
    categories = {
        1: [literal(font_clut)],
        2: [_tim((786, 78, 4, 24, [0x1111] * 96), (screens.TEXT_CLUT_X, 484, 16, 1, [0, RED] + [0] * 14))],
        3: [_tim((768, 0, 64, 48, [0x1111] * (64 * 48)))],
        5: [_tim((1, 1, 2, 2, [0x2222] * 4))],
        6: [literal(_tim((0, 512, 2, 2, [0x0101] * 4), (256, 488, 256, 1, [0, BLUE] + [0] * 254), depth=8))],
        7: [_picture_tim(1) for _ in range(12)],
        8: [_clut_only(256, 489, [RED] * 16), _clut_only(256, 489, [BLUE] * 16), _clut_only(256, 489, [WHITE] * 16)],
        9: [_tim((768, 464, 2, 2, [0x0101] * 4), (256, 485, 256, 1, [0, RED] + [0] * 254), depth=8) for _ in range(3)],
        # The two layouts' faces differ by palette.
        10: [_tim((256, 512, 4, 4, face), (0, 1008, 256, 1, [0, RED] + [0] * 254), depth=8)],
        11: [_tim((256, 512, 4, 4, face), (0, 1008, 256, 1, [0, BLUE] + [0] * 254), depth=8)],
        14: [_picture_tim(1, width_words=4, height=16)],
        16: [_picture_tim(1) for _ in range(20)],
        17: [_tim((0, 512, 2, 2, [0x0101] * 4), (256, 485, 256, 1, [0, WHITE] + [0] * 254), depth=8) for _ in range(3)]
        + [_clut_only(256, 485, [0, 0x0421] + [0] * 254, depth=8)],
        43: [_picture_tim(1), _picture_tim(1)],
    }
    return arcade.ArcadeSet(b"", b"", bytes(p.data), _categories=categories)


def _image(path: Path) -> np.ndarray:
    return np.asarray(Image.open(path).convert("RGBA"))


class UploadTest(unittest.TestCase):
    def setUp(self) -> None:
        self.vram = Vram(screens.VRAM_ROWS)

    def test_a_block_at_the_origin_is_skipped(self) -> None:
        screens.upload(self.vram, _tim((0, 0, 2, 2, [0x1234] * 4), (0, 0, 2, 1, [RED, RED])))
        self.assertFalse(self.vram.words.any())

    def test_a_block_with_x_or_y_alone_at_zero_is_uploaded(self) -> None:
        screens.upload(self.vram, _tim((0, 600, 1, 1, [0x1234]), (16, 0, 1, 1, [RED])))
        self.assertEqual(self.vram.words[600, 0], 0x1234)
        self.assertEqual(self.vram.words[0, 16], RED | screens.STP_BIT)

    def test_no_clut_without_flag_8(self) -> None:
        tim = bytearray(_tim((4, 4, 1, 1, [7]), (16, 16, 1, 1, [RED])))
        struct.pack_into("<I", tim, 4, 0)          # the flag off: the first block is the pixel block
        screens.upload(self.vram, bytes(tim))
        self.assertEqual(self.vram.words[16, 16], RED)  # the only block goes up as pixels, unmarked

    def test_every_colour_but_word_zero_gets_the_stp_bit(self) -> None:
        screens.upload(self.vram, _clut_only(16, 16, [0, 1, 0x8000, WHITE]))
        self.assertEqual(self.vram.words[16, 16:20].tolist(), [0, 1 | 0x8000, 0x8000, WHITE | 0x8000])

    def test_a_clut_only_tim_replaces_the_palette_alone(self) -> None:
        self.vram.words[0:2, 0:2] = 0x5555
        screens.upload(self.vram, _clut_only(32, 480, [RED, BLUE]))
        self.assertEqual(self.vram.words[480, 32:34].tolist(), [RED | 0x8000, BLUE | 0x8000])
        self.assertEqual(self.vram.words[0, 0], 0x5555)

    def test_overrides_move_the_blocks_and_a_clut_override_at_the_origin_skips_it(self) -> None:
        tim = _tim((1, 1, 1, 1, [9]), (16, 16, 1, 1, [RED]))
        screens.upload(self.vram, tim, clut_at=(32, 32), image_at=(8, 8))
        self.assertEqual(self.vram.words[8, 8], 9)
        self.assertEqual(self.vram.words[32, 32], RED | 0x8000)
        self.assertEqual(self.vram.words[1, 1], 0)
        self.assertEqual(self.vram.words[16, 16], 0)
        other = Vram(screens.VRAM_ROWS)
        screens.upload(other, tim, clut_at=(0, 0))
        self.assertEqual(other.words[16, 16], 0)
        self.assertEqual(other.words[0, 0], 0)
        self.assertEqual(other.words[1, 1], 9)

    def test_not_a_tim(self) -> None:
        with self.assertRaises(arcade.ArcadeError):
            screens.parse_tim(b"\0" * 16)

    def test_a_stored_file_and_a_compressed_one(self) -> None:
        tim = _tim((1, 1, 1, 1, [9]))
        arc = arcade.ArcadeSet(b"", b"", b"", _categories={1: [tim, literal(tim)]})
        self.assertEqual(screens.tim_file(arc, 1, 0), tim)
        self.assertEqual(screens.tim_file(arc, 1, 1), tim)


class PictureTest(unittest.TestCase):
    def setUp(self) -> None:
        self.vram = Vram(screens.VRAM_ROWS)

    def _clut(self, clut_id: int, colours: list[int]) -> None:
        x, y = arcade.clut_xy(clut_id)
        self.vram.words[y, x:x + len(colours)] = colours

    def test_4_bit_texels_lowest_first_and_colour_zero_transparent(self) -> None:
        self.vram.words[600, 64] = 0x0210
        self._clut(0x7E10, [0, WHITE, RED])
        pixels = screens.picture(self.vram, 64, 600, 4, 1, 4, 0x7E10)
        self.assertEqual(pixels.shape, (1, 4, 4))
        self.assertEqual(pixels[0, 0, 3], 0)
        self.assertEqual(tuple(pixels[0, 1]), OPAQUE_WHITE)
        self.assertEqual(tuple(pixels[0, 2]), (255, 0, 0, 255))
        self.assertEqual(pixels[0, 3, 3], 0)

    def test_black_with_the_stp_bit_stays_opaque(self) -> None:
        screens.upload(self.vram, _clut_only(16, 16, [0, 0x8000]))
        self.vram.words[600, 64] = 0x0001
        pixels = screens.picture(self.vram, 64, 600, 1, 1, 4, 16 * 64 + 1)
        self.assertEqual(tuple(pixels[0, 0]), (0, 0, 0, 255))

    def test_a_clut_row_above_512(self) -> None:
        self.assertEqual(arcade.clut_xy(0x7E10), (256, 504))
        self._clut(0x7E10, [0, BLUE])
        self.vram.words[0, 64] = 1
        self.assertEqual(tuple(screens.picture(self.vram, 64, 0, 1, 1, 4, 0x7E10)[0, 0]), (0, 0, 255, 255))

    def test_a_sprite_starts_inside_a_word_of_its_page(self) -> None:
        self.vram.words[512 + 3, 128 + 1] = 0x1000          # tpage 0x802: (128, 512), 4-bit
        self._clut(0x7B50, [0, WHITE])
        pixels = screens.sprite(self.vram, 0x802, 7, 3, 2, 1, 0x7B50)
        self.assertEqual(tuple(pixels[0, 0]), OPAQUE_WHITE)
        self.assertEqual(pixels[0, 1, 3], 0)

    def test_an_8_bit_page_takes_its_depth_from_the_tpage_word(self) -> None:
        self.vram.words[512, 256] = 0x0100                   # tpage 0x884: (256, 512), 8-bit
        self._clut(0x7E00, [0, WHITE])
        pixels = screens.sprite(self.vram, 0x884, 0, 0, 2, 1, 0x7E00)
        self.assertEqual(pixels[0, 0, 3], 0)
        self.assertEqual(tuple(pixels[0, 1]), OPAQUE_WHITE)

    def test_own_picture_goes_through_the_tims_first_palette(self) -> None:
        tim = _tim((0, 0, 1, 1, [0x0001]), (0, 0, 16, 2, [0, WHITE] + [0] * 14 + [0, RED] + [0] * 14))
        pixels = screens.own_picture(tim)
        self.assertEqual(pixels.shape, (1, 4, 4))
        self.assertEqual(tuple(pixels[0, 0]), OPAQUE_WHITE)

    def test_own_picture_refuses_a_clut_only_tim(self) -> None:
        with self.assertRaises(arcade.ArcadeError):
            screens.own_picture(_clut_only(16, 16, [0, WHITE]))


class TextRunsTest(unittest.TestCase):
    def _runs(self, fmt: str, *args: int | None) -> list[dict]:
        return screens.text_runs(fmt, args, FONTS)

    def test_a_plain_format(self) -> None:
        self.assertEqual(self._runs("%c%f%H%VHI", 8, 2, 10, 20),
                         [{"text": "HI", "font": 2, "colour": 8, "x": 10, "y": 20}])

    def test_the_font_starts_at_zero_and_the_arguments_follow_the_codes(self) -> None:
        self.assertEqual(self._runs("%c%H%VHI", 8, 10, 20), [{"text": "HI", "font": 0, "colour": 8, "x": 10, "y": 20}])
        self.assertEqual(self._runs("%p%c%f%V%HHI", None, 4, 1, 20, 10),
                         [{"text": "HI", "font": 1, "colour": 4, "x": 10, "y": 20}])

    def test_a_colour_change_continues_at_the_advance(self) -> None:
        runs = self._runs("%c%H%VAB %cCD", 2, 100, 20, 6)
        self.assertEqual([(r["text"], r["colour"], r["x"], r["y"]) for r in runs],
                         [("AB ", 2, 100, 20), ("CD", 6, 136, 20)])

    def test_a_pen_change_starts_a_run(self) -> None:
        runs = self._runs("%c%f%H%VAB%HC%HD", 2, 2, 7, 9, 50, 300)
        self.assertEqual([(r["text"], r["x"], r["y"]) for r in runs], [("AB", 7, 9), ("C", 50, 9), ("D", 300, 9)])

    def test_placeholders_and_percent_stay_for_the_view(self) -> None:
        runs = self._runs("%c%f%H%V%02d%f%H%V.%H%1x%%", None, 1, 0, 0, 0, 36, 4, 46)
        self.assertEqual([r["text"] for r in runs], ["%02d", ".", "%1x%%"])
        self.assertEqual([r["font"] for r in runs], [1, 0, 0])
        self.assertEqual([r["x"] for r in runs], [0, 36, 46])
        self.assertIsNone(runs[0]["colour"])

    def test_a_percent_sign_counts_as_one_letter(self) -> None:
        runs = self._runs("%c%H%V%%A%cB", 1, 0, 0, 2)
        self.assertEqual(runs[1]["x"], 24)

    def test_after_a_value_the_pen_is_not_known(self) -> None:
        runs = self._runs("%c%H%V%sA%cB", 1, 0, 0, 2)
        self.assertEqual([r["text"] for r in runs], ["%sA", "B"])
        self.assertIsNone(runs[1]["x"])

    def test_a_run_time_position_is_null(self) -> None:
        runs = self._runs("%c%f%H%V%s", 8, 2, None, None)
        self.assertEqual(runs, [{"text": "%s", "font": 2, "colour": 8, "x": None, "y": None}])

    def test_a_newline_returns_to_the_last_h_a_line_down(self) -> None:
        runs = self._runs("%c%f%H%VAB\n  C", 7, 2, 16, 100)
        self.assertEqual([(r["text"], r["x"], r["y"]) for r in runs], [("AB", 16, 100), ("  C", 16, 142)])

    def test_an_empty_format_has_no_runs(self) -> None:
        self.assertEqual(self._runs(""), [])

    def test_a_code_the_screens_do_not_use_is_refused(self) -> None:
        with self.assertRaises(arcade.ArcadeError):
            self._runs("%h")

    def test_a_stray_percent_is_refused(self) -> None:
        with self.assertRaises(arcade.ArcadeError):
            self._runs("A%")


class StaffTest(unittest.TestCase):
    def _lines(self, items: list[str], y: int = 100) -> list[dict]:
        p = Program()
        table = RECORDS
        for k, item in enumerate(items):
            p.pack(table + 4 * k, "<I", p.string(item))
        return screens.staff_lines(arcade.ArcadeSet(b"", b"", bytes(p.data)), table, y)

    def test_headers_names_and_blanks(self) -> None:
        lines = self._lines(["0HEAD", "1NAME", "1", "5X", "0H2", "2"])
        self.assertEqual(lines, [
            {"text": "HEAD", "x": 0, "y": 98, "colour": 1},
            {"text": "NAME", "x": 0x14, "y": 100 + 0x16 - 4, "colour": 6},
            {"text": "H2", "x": 0, "y": 100 + 0x16 + 3 * 0x14 - 2, "colour": 1},
        ])

    def test_a_list_that_never_ends_is_refused(self) -> None:
        with self.assertRaises(arcade.ArcadeError):
            self._lines(["1A"] * (screens.STAFF_MAX_ITEMS + 1))

    def test_the_pages_y_and_the_left_only_page(self) -> None:
        p = Program()
        name, end = p.string("1N"), p.string("2")
        lists = RECORDS
        p.pack(lists, "<II", name, end)
        for page in range(screens.STAFF_PAGE_COUNT):
            p.pack(screens.STAFF_PAGES + 8 * page, "<II", lists, lists)
        for table in screens.STAFF_FIRST_LISTS:
            p.pack(table, "<II", name, end)
        pages = screens.staff_pages(arcade.ArcadeSet(b"", b"", bytes(p.data)))
        self.assertEqual(len(pages), screens.STAFF_PAGE_COUNT)
        self.assertEqual(pages[0]["left"]["lines"][0]["y"], 0x19 - 4)
        self.assertEqual(pages[0]["right"]["lines"][0]["y"], 0xFF - 4)
        self.assertEqual(pages[1]["left"]["lines"][0]["y"], 0x14 - 4)
        self.assertEqual(pages[1]["right"]["lines"][0]["y"], 0xEE - 4)
        self.assertEqual(pages[4]["right"]["lines"][0]["y"], 0xE6 - 4)
        self.assertEqual(pages[7]["right"]["lines"][0]["y"], 0xE6 - 4)
        self.assertEqual(set(pages[6]), {"left"})
        self.assertEqual((pages[2]["left"]["x"], pages[2]["right"]["x"]), (0x1E, 0xDC))


class ConvertTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.temp = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        screens.convert(_fake_set(), Output(cls.root))
        cls.document = json.loads((cls.root / screens.SCREENS_DIR / "screens.json").read_text())
        cls.hud = json.loads((cls.root / screens.HUD_DIR / "hud.json").read_text())

    def _screen(self, name: str) -> np.ndarray:
        return _image(self.root / screens.SCREENS_DIR / name)

    def _hud(self, name: str) -> np.ndarray:
        return _image(self.root / screens.HUD_DIR / name)

    def test_hud_json_is_what_hud_data_loads(self) -> None:
        self.assertEqual(set(self.hud), {"names", "digits", "fonts"})
        self.assertEqual(self.hud["digits"], 12)
        self.assertEqual(len(self.hud["names"]), screens.CHARACTER_KEYS)
        self.assertEqual(self.hud["names"]["0"], {"file": "name_00.png", "width": 8, "plate": "plate_0.png"})
        self.assertEqual(self.hud["names"]["7"]["plate"], "plate_3.png")
        self.assertEqual(self.hud["fonts"]["2"], {"advance": 30, "line": 42, "width": 32, "height": 40,
                                                  "first": 0x20, "columns": 16})
        for entry in self.hud["names"].values():
            self.assertTrue((self.root / screens.HUD_DIR / entry["file"]).exists())
            self.assertTrue((self.root / screens.HUD_DIR / entry["plate"]).exists())

    def test_the_hud_pieces_have_the_arcades_sizes(self) -> None:
        sizes = {"bar_health.png": (16, 2), "bar_damage.png": (16, 2), "bar_empty.png": (16, 2),
                 "bar_backing.png": (24, 2), "bar_cap_left.png": (24, 8), "bar_cap_right.png": (24, 8),
                 "digit_0.png": (46, 20), "digit_11.png": (46, 20), "mark_won.png": (18, 20), "mark_empty.png": (18, 20),
                 "name_00.png": (16, 8), "plate_0.png": (10, 2)}
        for name, size in sizes.items():
            self.assertEqual(self._hud(name).shape[:2], size, name)

    def test_a_sheet_only_for_the_colours_the_cluts_define(self) -> None:
        self.assertEqual(self.document["text_colours"], {"0": [2], "1": [], "2": []})
        files = sorted(p.name for p in (self.root / screens.HUD_DIR).glob("font_*"))
        self.assertEqual(files, ["font_0_2.png"])

    def test_a_sheet_holds_the_glyphs_in_rows_of_16_without_the_space(self) -> None:
        sheet = self._hud("font_0_2.png")
        self.assertEqual(sheet.shape[:2], (4 * 16, 16 * 12))
        # Glyph UV (0, 0) of font 0's texels: texel value 1, opaque white; the space stays empty.
        self.assertEqual(sheet[:16, :12, 3].max(), 0)
        self.assertEqual(tuple(sheet[0, 12]), OPAQUE_WHITE)

    def test_the_font_patch_goes_to_its_place_without_its_clut(self) -> None:
        vram = screens.system_vram(_fake_set())
        x, y = screens.FONT_PATCH_AT
        self.assertEqual(vram.words[y, x], 0x2222)
        self.assertEqual(vram.words[1, 1], 0)

    def test_a_format_becomes_runs(self) -> None:
        self.assertEqual(self.document["texts"]["ready"], [{"text": "HI", "font": 2, "colour": 9, "x": 0xA6, "y": 0xE4}])
        self.assertEqual(set(self.document["texts"]), set(screens.TEXTS))

    def test_the_prompts(self) -> None:
        prompts = self.document["prompts"]
        self.assertEqual(prompts["main"]["entries"][1], {"text": "TEXT %1x", "x": 11})
        self.assertEqual(len(prompts["side"]["entries"]), screens.SIDE_PROMPT_COUNT)
        self.assertEqual(len(prompts["credits"]["entries"]), screens.CREDIT_COUNT)
        self.assertEqual(prompts["credits"]["x"], [10, 0x172])

    def test_the_layouts_read_their_vram(self) -> None:
        layouts = self.document["select"]["layouts"]
        self.assertEqual(layouts[0]["faces"], {"0": "select_face_0_0.png"})
        self.assertEqual(tuple(self._screen("select_face_0_0.png")[0, 0]), (255, 0, 0, 255))
        self.assertEqual(tuple(self._screen("select_face_1_0.png")[0, 0]), (0, 0, 255, 255))
        self.assertEqual(self._screen("select_face_0_0.png").shape[:2], (4, 44))
        self.assertEqual(self._screen(layouts[0]["frames"][0]["file"]).shape[:2], (4, 8))
        self.assertEqual({k: layouts[0]["frames"][0][k] for k in ("x", "y", "width", "height")},
                         {"x": 5, "y": 6, "width": 8, "height": 4})
        self.assertEqual(len(layouts[0]["frames"]), 1)

    def test_each_layout_has_its_panel_clut(self) -> None:
        # Frame row 0 reads word (512, 768) through CLUT 0x7A50: the panel entries are its only source.
        arc = _fake_set()
        system = screens.system_vram(arc)
        cx, cy = arcade.clut_xy(0x7A50)
        self.assertEqual(screens._select_vram(arc, system, 0).words[cy, cx], WHITE | 0x8000)
        self.assertEqual(screens._select_vram(arc, system, 1).words[cy, cx], BLUE | 0x8000)
        self.assertFalse(system.words[cy, cx])

    def test_the_gradient_reddens_only_the_second_layout(self) -> None:
        layouts = self.document["select"]["layouts"]
        self.assertEqual(layouts[0]["gradient"]["bottom_colour"], [0, 0, 0])
        self.assertEqual(layouts[1]["gradient"], {"top": 100 + 0x10, "bottom": 0x1E0, "top_colour": [0, 0, 0],
                                                  "bottom_colour": [0xE0, 0, 0]})

    def test_only_the_used_tiles_are_written(self) -> None:
        self.assertEqual(self.document["select"]["tiles"]["files"], {"3": "select_tile_3.png"})
        self.assertEqual(self._screen("select_tile_3.png").shape[:2], (64, 64))

    def test_the_vs_kinds(self) -> None:
        names = self.document["vs"]["backgrounds"]
        self.assertEqual(names, ["vs_bg_0.png", "vs_bg_1.png", "vs_bg_2.png", "vs_bg_3.png"])
        self.assertEqual(self._screen("vs_bg_2.png").shape[:2], (240, 256))
        self.assertEqual(tuple(self._screen("vs_bg_2.png")[0, 0]), OPAQUE_WHITE)
        # Kind 3 is the same picture through the CLUT-only entry.
        self.assertEqual(tuple(self._screen("vs_bg_3.png")[0, 0][:3]), (8, 8, 8))

    def test_the_title_joins_its_strips_through_its_clut(self) -> None:
        title = self._screen("title.png")
        self.assertEqual(title.shape[:2], (480, 512))
        self.assertEqual(tuple(title[0, 0]), (0, 0, 255, 255))
        self.assertEqual(title[0, 4, 3], 0)

    def test_the_ranking_tables(self) -> None:
        ranking = self.document["ranking"]
        self.assertEqual(self._screen(ranking["titles"][2]).shape[:2], (48, 512))
        self.assertEqual(ranking["suffixes"], ["X"] * 4)
        self.assertEqual(ranking["rejected"], ["ZZZ"] * 5)
        self.assertEqual(ranking["alphabet"], "Q" * 40)
        self.assertEqual(len(ranking["bars"]["colours"]), 22)
        self.assertEqual({name: len(rows[0]) for name, rows in ranking["colours"].items()},
                         {"time": 5, "wins": 4, "usage": 3})

    def test_the_character_records(self) -> None:
        characters = self.document["characters"]
        self.assertEqual(len(characters), screens.CHARACTER_KEYS)
        self.assertEqual(characters[5], {"name": "AB", "plate": 0, "plate_width": 8, "face": "face_0.png", "status": 1,
                                         "voice": 2, "pick_voice": 77, "bank": 3, "stage": 4, "music": 5})

    def test_the_attributes(self) -> None:
        attributes = self.document["attributes"]
        self.assertEqual(attributes["keys"][3], {"portrait": "portrait_2.png", "facing": 1, "band": 1, "silhouette": False,
                                                 "colour": [1, 2, 3]})
        self.assertEqual(attributes["default"], {"portrait": "portrait_19.png", "facing": 0, "band": 0, "silhouette": True,
                                                 "colour": [0xB3, 0xB3, 0xB3]})

    def test_every_file_the_document_names_exists(self) -> None:
        def names(value: object) -> list[str]:
            if isinstance(value, str):
                return [value] if value.endswith(".png") else []
            if isinstance(value, dict):
                return [n for item in value.values() for n in names(item)]
            if isinstance(value, list):
                return [n for item in value for n in names(item)]
            return []

        found = names(self.document)
        self.assertGreater(len(found), 100)
        for name in found:
            self.assertTrue((self.root / screens.SCREENS_DIR / name).exists(), name)

    def test_the_manifest_gaps_no_longer_list_them(self) -> None:
        self.assertNotIn("screens", arcade_game.GAPS)
        self.assertNotIn("hud", arcade_game.GAPS)


if __name__ == "__main__":
    unittest.main()
