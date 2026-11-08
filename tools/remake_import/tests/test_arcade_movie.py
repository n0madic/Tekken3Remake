"""The arcade's attract movie (arcade_movie.py) on synthetic bitstreams: no game data."""

from __future__ import annotations

import json
import math
import shutil
import struct
import subprocess
import tempfile
import types
import unittest
from pathlib import Path

import numpy as np

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_movie as movie
import media
from arcade import ArcadeError
from common import Output

CODE_OF = {(run, level): code for code, run, level in movie.AC_CODES}
QUANT_ONE = 8                   # with a scale of 1: (level × 8 × 1) / 8 = level
MAX_DC = 511
PICTURE_FILES = 3


def _cosines() -> np.ndarray:
    """An IDCT table of the MDEC's kind, from the formula."""
    table = np.zeros((8, 8), np.int64)
    for u in range(8):
        for x in range(8):
            weight = math.sqrt(0.5) if u == 0 else 1.0
            table[u, x] = round(32767 * weight * math.cos((2 * x + 1) * u * math.pi / 16))
    return table


def _tables(quant: int = QUANT_ONE) -> movie.Tables:
    return movie.Tables(np.full((2, movie.BLOCK_VALUES), quant, np.int64), _cosines())


def _dc_bits(value: int) -> str:
    return format(value & movie.LEVEL_MASK, f"0{movie.DC_BITS}b")


def _ac_bits(run: int, level: int) -> str:
    """A value by its table code with a sign bit, else the escape."""
    code = CODE_OF.get((run, abs(level)))
    if code is not None:
        return code + ("1" if level < 0 else "0")
    return movie.ESCAPE_CODE + format(run, "06b") + format(level & movie.LEVEL_MASK, "010b")


def _block(dc: int, values: tuple[tuple[int, int], ...] = ()) -> str:
    """A block's bits: its DC value, then (run, level) pairs."""
    return _dc_bits(dc) + "".join(_ac_bits(run, level) for run, level in values) + movie.END_OF_BLOCK_CODE


def _stream(bits: str, quant_scale: int = 1, version: int = 2) -> bytes:
    """A file: the header, then 16-bit little-endian words, each read from its top bit."""
    bits += "0" * (-len(bits) % 16)
    words = [int(bits[i:i + 16], 2) for i in range(0, len(bits), 16)]
    return movie.HEADER.pack(len(words), movie.BITSTREAM_ID, quant_scale, version) + struct.pack(f"<{len(words)}H", *words)


def _picture(dc_of_block=lambda _block: 0) -> bytes:
    """A whole picture of DC values only."""
    return _stream("".join(_block(dc_of_block(b)) for b in range(movie.BLOCKS)))


class Codes(unittest.TestCase):
    def test_a_table_value_with_its_sign(self) -> None:
        bits = _block(3, ((0, 1), (1, -1))) + "".join(_block(0) for _ in range(movie.BLOCKS - 1))
        codes = movie.read_codes(_stream(bits))
        self.assertEqual(codes.dc[0], 3)
        self.assertEqual(codes.places.tolist(), [1, 3])
        self.assertEqual(codes.levels.tolist(), [1, -1])

    def test_every_code_of_the_table(self) -> None:
        for code, run, level in movie.AC_CODES:
            bits = _dc_bits(0) + code + "1" + movie.END_OF_BLOCK_CODE + "".join(_block(0) for _ in range(movie.BLOCKS - 1))
            codes = movie.read_codes(_stream(bits))
            self.assertEqual((codes.places.tolist(), codes.levels.tolist()), ([run + 1], [-level]), code)

    def test_no_code_is_a_prefix_of_another(self) -> None:
        all_codes = [c for c, _, _ in movie.AC_CODES] + [movie.END_OF_BLOCK_CODE, movie.ESCAPE_CODE]
        self.assertEqual(len(set(all_codes)), len(all_codes))
        for a in all_codes:
            for b in all_codes:
                self.assertFalse(a != b and b.startswith(a), (a, b))

    def test_the_escape_holds_a_run_and_a_signed_level(self) -> None:
        bits = _block(0, ((60, -200),)) + "".join(_block(0) for _ in range(movie.BLOCKS - 1))
        codes = movie.read_codes(_stream(bits))
        self.assertEqual((codes.places.tolist(), codes.levels.tolist()), ([61], [-200]))

    def test_the_next_blocks_places(self) -> None:
        bits = _block(0) + _block(0, ((0, 2),)) + "".join(_block(0) for _ in range(movie.BLOCKS - 2))
        self.assertEqual(movie.read_codes(_stream(bits)).places.tolist(), [movie.BLOCK_VALUES + 1])

    def test_a_negative_dc_value(self) -> None:
        self.assertEqual(movie.read_codes(_picture(lambda b: -5 if b == 7 else 0)).dc[7], -5)

    def test_the_end_of_picture_code_stops_the_blocks(self) -> None:
        bits = _block(4) + _dc_bits(movie.END_OF_PICTURE) + _block(9)
        self.assertEqual(movie.read_codes(_stream(bits)).dc[:3].tolist(), [4, 0, 0])

    def test_a_stream_that_runs_out(self) -> None:
        with self.assertRaises(ArcadeError):
            movie.read_codes(_stream(_block(1)))

    def test_too_many_values_in_a_block(self) -> None:
        with self.assertRaises(ArcadeError):
            movie.read_codes(_stream(_dc_bits(0) + _ac_bits(62, 1) + _ac_bits(0, 1) + _ac_bits(0, 1)))

    def test_not_a_bitstream(self) -> None:
        for data in (b"", b"\0" * 32, movie.HEADER.pack(1, movie.BITSTREAM_ID, 1, 3) + bytes(8)):
            with self.assertRaises(ArcadeError):
                movie.read_codes(data)


class Pictures(unittest.TestCase):
    """The tests' blocks are flat: a DC value alone is one sample value all over."""

    def _decode(self, dc_of_block) -> np.ndarray:
        return movie.decode(_picture(dc_of_block), _tables())

    def test_the_size(self) -> None:
        self.assertEqual(self._decode(lambda _b: 0).shape, (movie.HEIGHT, movie.WIDTH, 3))

    def test_zero_is_mid_grey(self) -> None:
        picture = self._decode(lambda _b: 0)
        self.assertTrue((picture == movie.SAMPLE_OFFSET).all())

    def test_luma_moves_every_channel(self) -> None:
        def dc(block: int) -> int:
            return 40 if block % movie.BLOCKS_PER_MACROBLOCK >= movie.CHROMA_BLOCKS else 0
        picture = self._decode(dc)
        self.assertEqual(int(picture[0, 0, 0]), int(picture[0, 0, 1]))
        self.assertEqual(int(picture[0, 0, 0]), int(picture[0, 0, 2]))
        self.assertGreater(int(picture[0, 0, 0]), movie.SAMPLE_OFFSET)

    def test_cr_moves_red_up_and_green_down(self) -> None:
        pixel = self._decode(lambda b: 40 if b % movie.BLOCKS_PER_MACROBLOCK == 0 else 0)[0, 0].astype(int)
        self.assertGreater(pixel[0], movie.SAMPLE_OFFSET)
        self.assertLess(pixel[1], movie.SAMPLE_OFFSET)
        self.assertEqual(pixel[2], movie.SAMPLE_OFFSET)

    def test_cb_moves_blue_up_and_green_down(self) -> None:
        pixel = self._decode(lambda b: 40 if b % movie.BLOCKS_PER_MACROBLOCK == 1 else 0)[0, 0].astype(int)
        self.assertEqual(pixel[0], movie.SAMPLE_OFFSET)
        self.assertLess(pixel[1], movie.SAMPLE_OFFSET)
        self.assertGreater(pixel[2], movie.SAMPLE_OFFSET)

    def test_the_colours_saturate(self) -> None:
        picture = self._decode(lambda _b: MAX_DC - 1)
        self.assertEqual(int(picture.max()), movie.SAMPLE_MAX + movie.SAMPLE_OFFSET)
        picture = self._decode(lambda _b: -MAX_DC)
        self.assertEqual(int(picture.min()), movie.SAMPLE_MIN + movie.SAMPLE_OFFSET)

    def test_macroblocks_go_down_the_columns(self) -> None:
        def dc(block: int) -> int:
            macroblock, kind = divmod(block, movie.BLOCKS_PER_MACROBLOCK)
            return 40 if macroblock == 1 and kind >= movie.CHROMA_BLOCKS else 0
        picture = self._decode(dc).astype(int)
        grey = movie.SAMPLE_OFFSET
        self.assertGreater(picture[movie.MACROBLOCK + 1, 1, 0], grey, "the macroblock below the first")
        self.assertEqual(picture[1, movie.MACROBLOCK + 1, 0], grey, "not the one to its right")
        self.assertEqual(picture[1, 1, 0], grey)

    def test_the_four_luma_blocks_of_a_macroblock(self) -> None:
        places = {2: (0, 0), 3: (0, movie.BLOCK_SIDE), 4: (movie.BLOCK_SIDE, 0), 5: (movie.BLOCK_SIDE, movie.BLOCK_SIDE)}
        for kind, (y, x) in places.items():
            picture = self._decode(lambda b, k=kind: 40 if b == k else 0).astype(int)
            lit = np.argwhere(picture[..., 0] != movie.SAMPLE_OFFSET)
            self.assertEqual(lit.min(axis=0).tolist(), [y, x], f"block {kind}")
            self.assertEqual(lit.max(axis=0).tolist(), [y + movie.BLOCK_SIDE - 1, x + movie.BLOCK_SIDE - 1], f"block {kind}")

    def test_chroma_covers_the_whole_macroblock(self) -> None:
        picture = self._decode(lambda b: 40 if b == 0 else 0).astype(int)
        lit = np.argwhere(picture[..., 0] != movie.SAMPLE_OFFSET)
        self.assertEqual(lit.min(axis=0).tolist(), [0, 0])
        self.assertEqual(lit.max(axis=0).tolist(), [movie.MACROBLOCK - 1, movie.MACROBLOCK - 1])

    def test_an_ac_value_is_a_cosine_across_the_block(self) -> None:
        bits = _block(0) + _block(0) + _block(0, ((0, 40),)) + "".join(_block(0) for _ in range(movie.BLOCKS - 3))
        row = movie.decode(_stream(bits), _tables())[0, :movie.BLOCK_SIDE, 0].astype(int) - movie.SAMPLE_OFFSET
        self.assertGreater(row[0], 0)
        self.assertLess(row[-1], 0)
        self.assertLess(abs(row[0] + row[-1]), 2, "odd symmetry")

    def test_the_quantiser_scale_multiplies_the_ac_values_only(self) -> None:
        def stream(scale: int) -> bytes:
            return _stream(_block(0) + _block(0) + _block(10, ((0, 16),)) + "".join(_block(0) for _ in range(movie.BLOCKS - 3)), scale)
        one = movie.read_codes(stream(1))
        two = movie.read_codes(stream(2))
        values = movie._coefficients(one, _tables()), movie._coefficients(two, _tables())
        block = 2
        self.assertEqual(values[0][block, 0], values[1][block, 0])
        self.assertEqual(values[1][block, 1], 2 * values[0][block, 1])

    def test_the_division_goes_towards_zero(self) -> None:
        stream = _stream(_block(0) + _block(0) + _block(0, ((0, 3), (0, -3))) + "".join(_block(0) for _ in range(movie.BLOCKS - 3)))
        values = movie._coefficients(movie.read_codes(stream), _tables(quant=1))
        # (3 × 1 × 1) / 8 is 0 either side of zero; a floor would give −1 for the negative one.
        self.assertEqual(values[2, 1], 0)
        self.assertEqual(values[2, 8], 0)

    def test_chroma_and_luma_tables(self) -> None:
        tables = movie.Tables(np.stack((np.full(64, 8, np.int64), np.full(64, 16, np.int64))), _cosines())
        stream = _stream(_block(0, ((0, 1),)) + _block(0) + _block(0, ((0, 1),)) + "".join(_block(0) for _ in range(movie.BLOCKS - 3)))
        values = movie._coefficients(movie.read_codes(stream), tables)
        self.assertEqual(values[0, 1], 2, "Cr with the chroma table")
        self.assertEqual(values[2, 1], 1, "Y with the luma table")


class Timing(unittest.TestCase):
    def test_the_screen_is_two_frames_behind_the_file_decoded(self) -> None:
        self.assertEqual([movie.shown_file(t, 261) for t in range(5)], [0, 0, 0, 1, 2])

    def test_the_last_picture_stays(self) -> None:
        self.assertEqual([movie.shown_file(t, 261) for t in (261, 262, 263)], [259, 260, 260])

    def test_one_frame_per_value_of_the_flows_timer(self) -> None:
        self.assertEqual(movie.frame_count(261), 264, "0 … 263: the flow leaves when the timer passes files + 1")

    def test_the_rate_keeps_the_flows_vblanks(self) -> None:
        self.assertEqual(movie.MOVIE_FPS * movie.VBLANKS_PER_FRAME, 60)


@unittest.skipUnless(shutil.which("ffmpeg"), "no FFmpeg")
class Convert(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.out = Output(self.root)
        files = [_picture(lambda _b, k=k: 10 * k) for k in range(PICTURE_FILES)]

        def prog(addr: int, size: int) -> bytes:
            if addr == movie.QUANT_TABLES:
                return bytes([QUANT_ONE]) * size
            self.assertEqual(addr, movie.SCALE_TABLE)
            return _cosines().astype("<i2").tobytes()[:size]

        self.arc = types.SimpleNamespace(category=lambda number: files if number == movie.CATEGORY else [], prog=prog)

    def _index(self) -> dict:
        return json.loads((self.root / "movies" / "movies.json").read_text())

    def _packets(self, tool: media.FFmpeg, path: Path) -> list[str]:
        result = subprocess.run([tool.path, "-hide_banner", "-loglevel", "error", "-i", str(path), "-map", "0:v", "-c", "copy", "-f", "framecrc", "-"],
                                capture_output=True, text=True, check=True)
        return [line for line in result.stdout.splitlines() if not line.startswith("#")]

    def test_a_movie_entry_with_the_flows_frames(self) -> None:
        tool = media.find_ffmpeg()
        movie.convert(self.arc, self.out, tool)
        entry = self._index()[movie.NAME][0]
        self.assertEqual(entry["frame_count"], PICTURE_FILES + movie.TIMER_PAST_FILES)
        self.assertEqual(entry["fps"], movie.MOVIE_FPS)
        self.assertEqual((entry["width"], entry["height"]), (movie.WIDTH, movie.HEIGHT))
        self.assertAlmostEqual(entry["duration"], entry["frame_count"] / movie.MOVIE_FPS, places=3)
        if tool.ogg:
            self.assertEqual(entry["video"], [f"{movie.NAME}.{v}.ogv" for v in media.THEORA_QUALITIES])
            for file in entry["video"]:
                self.assertEqual(len(self._packets(tool, self.root / "movies" / file)), entry["frame_count"])

    def test_without_the_theora_encoder_the_frame_container(self) -> None:
        found = media.find_ffmpeg()
        movie.convert(self.arc, self.out, media.FFmpeg(found.path, frozenset()))
        entry = self._index()[movie.NAME][0]
        self.assertNotIn("video", entry)
        data = (self.root / "movies" / entry["frames"]).read_bytes()
        magic, _, width, height, count, rate = struct.unpack_from("<4sIHHII", data)
        self.assertEqual((magic, width, height, count, rate), (media.MOVIE_MAGIC, movie.WIDTH, movie.HEIGHT, entry["frame_count"], movie.MOVIE_FPS))
        arrivals = [struct.unpack_from("<III", data, struct.calcsize("<4sIHHII") + 12 * i)[2] for i in range(count)]
        self.assertEqual(arrivals, list(range(count)))

    def test_a_category_without_files(self) -> None:
        self.arc.category = lambda _number: []
        with self.assertRaises(ArcadeError):
            movie.convert(self.arc, self.out, media.find_ffmpeg())


if __name__ == "__main__":
    unittest.main()
