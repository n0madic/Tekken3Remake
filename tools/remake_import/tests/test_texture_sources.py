"""The pictures' VRAM sources (sources.py) and the DuckStation pack importer
(tools/remake/duckstation_pack.py) on synthetic VRAM and replacements: no game data."""

from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

import numpy as np
from PIL import Image

from sources import Recorder, Sources
from vram import Vram

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "remake"))
import duckstation_pack  # noqa: E402

try:
    import xxhash
except ImportError:
    xxhash = None

PAGE = (128, 256)                 # VRAM words: tpage 2 + 16
CLUT = (32, 480)
COLOURS = (0, 0x001F, 0x03E0, 0x7C00)
SCALE = 4
GREEN = (10, 200, 30, 255)


def _vram() -> Vram:
    """A 4-bit page with texel (u, v) = (u + v) % 4 + 1 over rows 0–63, and a four-colour CLUT."""
    v = Vram()
    for y in range(64):
        for wx in range(16):
            texels = [((4 * wx + k + y) % 3) + 1 for k in range(4)]
            v.words[PAGE[1] + y, PAGE[0] + wx] = sum(t << (4 * k) for k, t in enumerate(texels))
    v.words[CLUT[1], CLUT[0]:CLUT[0] + 4] = COLOURS
    return v


def _name(vram: Vram, x: int, y: int, w: int, h: int, colours: int, semi: bool = False) -> str:
    """DuckStation's name of a page replacement of texels (x, y, w, h) of PAGE through CLUT."""
    words = np.ascontiguousarray(vram.words[PAGE[1] + y:PAGE[1] + y + h, PAGE[0] + x // 4:PAGE[0] + (x + w) // 4])
    palette = np.ascontiguousarray(vram.words[CLUT[1], CLUT[0]:CLUT[0] + colours])
    return (f"texpage-{'ST' if semi else ''}P4-{xxhash.xxh3_64_intdigest(words.tobytes()):016X}-"
            f"{xxhash.xxh3_64_intdigest(palette.tobytes()):016X}-64x256-{x}-{y}-{w}x{h}-P0-{colours - 1}.png")


def _save(folder: Path, name: str, w: int, h: int, colour: tuple[int, ...]) -> None:
    Image.new("RGBA", (w * SCALE, h * SCALE), colour).save(folder / name)


class RecorderTest(unittest.TestCase):
    def test_round_trip_keeps_snapshots_and_pieces(self) -> None:
        vram = _vram()
        rec = Recorder()
        clut = vram.clut(*CLUT, 16)
        rec.piece("a.png", 2, 3, vram.words, 4 * PAGE[0] + 8, PAGE[1], 8, 8, 4, clut, (0, 1, -1, 0), pad=2)
        rec.piece("a.png", 20, 3, vram.words, 4 * PAGE[0], PAGE[1], 8, 8, 4, clut)
        vram.words[0, 0] = 1                      # a later upload: another snapshot
        rec.piece("b.png", 0, 0, vram.words, 0, 0, 4, 4, 4, clut)
        rec.derived("c.png", "a.png", "smooth_seams")
        rec.runtime_vram("screen", vram.words)
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "sources.zip"
            rec.save(path)
            s = Sources.load(path)
        self.assertEqual(len(s.snapshots), 2)
        first, second = s.pictures["a.png"]["pieces"]
        self.assertEqual(first["transform"], [0, 1, -1, 0])
        self.assertEqual(first["pad"], 2)
        self.assertNotIn("transform", second)
        self.assertEqual(first["snapshot"], second["snapshot"])
        self.assertNotEqual(s.pictures["b.png"]["pieces"][0]["snapshot"], first["snapshot"])
        self.assertEqual(s.runtime, [{"name": "screen", "snapshot": 1}])
        self.assertEqual(s.pictures["c.png"]["derived"], {"from": "a.png", "post": "smooth_seams"})
        np.testing.assert_array_equal(s.cluts[first["clut"]], clut)


@unittest.skipIf(xxhash is None, "the importer needs the xxhash module")
class ImportTest(unittest.TestCase):
    def setUp(self) -> None:
        self.folder = tempfile.TemporaryDirectory()
        self.root = Path(self.folder.name)
        self.ds = self.root / "ds"
        self.imported = self.root / "imported"
        self.pack = self.root / "pack"
        self.ds.mkdir()
        self.imported.mkdir()
        self.vram = _vram()

    def tearDown(self) -> None:
        self.folder.cleanup()

    def _picture(self, rel: str, rec: Recorder, pieces: list[tuple]) -> None:
        """A converted picture of 16 × 8 texels holding `pieces` (x, y, u, v, w, h[, transform])."""
        page = self.vram.page_rgba(*PAGE, 4, *CLUT)
        picture = np.zeros((8, 16, 4), dtype=np.uint8)
        for x, y, u, v, w, h, *transform in pieces:
            picture[y:y + h, x:x + w] = page[v:v + h, u:u + w]
            rec.piece(rel, x, y, self.vram.words, 4 * PAGE[0] + u, PAGE[1] + v, w, h, 4, self.vram.clut(*CLUT, 16),
                      *transform)
        Image.fromarray(picture, "RGBA").save(self.imported / rel)

    def _import(self, rec: Recorder, index: dict[str, str]) -> Sources:
        rec.save(self.root / "sources.zip")
        sources = Sources.load(self.root / "sources.zip")
        duckstation_pack.import_pack(self.ds, self.pack, sources, self.imported, index, None)
        return sources

    def _faithful(self, u: int, v: int, w: int, h: int, alpha: int = 255) -> np.ndarray:
        """A replacement as an artist would make it: the texels at SCALE, their first column marked
        by a small change of red (within MAX_COLOUR_DISTANCE)."""
        page = self.vram.page_rgba(*PAGE, 4, *CLUT)[v:v + h, u:u + w]
        hd = np.repeat(np.repeat(page, SCALE, axis=0), SCALE, axis=1).copy()
        hd[:, :SCALE, 0] ^= 4
        hd[..., 3] = np.where(hd[..., 3] > 0, alpha, 0)
        return hd

    def _write(self, name: str, pixels: np.ndarray) -> None:
        Image.fromarray(pixels, "RGBA").save(self.ds / name)

    def test_a_replacement_repaints_the_pieces_it_covers(self) -> None:
        rec = Recorder()
        # Piece 1: texels (8, 0)–(16, 8) at picture (0, 0); piece 2: the same texels turned a
        # quarter (col → v, row → −u) at picture (8, 0).
        self._picture("a.png", rec, [(0, 0, 8, 0, 8, 8), (8, 0, 8, 0, 8, 8, (0, -1, 1, 0))])
        hd = self._faithful(8, 0, 8, 8)
        name = _name(self.vram, 8, 0, 8, 8, 4)
        self._write(name, hd)
        _save(self.ds, _name(self.vram, 0, 16, 8, 8, 4), 8, 8, GREEN)   # other texels: not in the picture
        other = name.split("-")
        other[3] = "0000000000000001"                                    # another CLUT's hash
        self._write("-".join(other), hd)
        # A palette hash of one colour (DuckStation's P0-0 names) matches any CLUT starting with
        # it: the colours tell this one is another CLUT's.
        _save(self.ds, _name(self.vram, 8, 0, 8, 8, 1), 8, 8, GREEN)
        self._import(rec, {"a.png": "k1"})
        out = np.asarray(Image.open(self.pack / "k1.png"))
        self.assertEqual(out.shape, (8 * SCALE, 16 * SCALE, 4))
        np.testing.assert_array_equal(out[:, :8 * SCALE], hd, "piece 1: the replacement as it is")
        # Turned: picture (col, row) shows the replacement's (u, v) = (8·SCALE − 1 − row, col).
        n = 8 * SCALE
        cols, rows = np.meshgrid(np.arange(n), np.arange(n))
        np.testing.assert_array_equal(out[:, n:], hd[cols, n - 1 - rows], "piece 2: turned")
        report = (self.pack / duckstation_pack.REPORT).read_text()
        self.assertIn("4 replacements, 1 used", report)

    def test_gutters_repeat_the_replaced_edges(self) -> None:
        rec = Recorder()
        self._picture("a.png", rec, [(4, 2, 0, 0, 8, 4, (1, 0, 0, 1), 2)])
        hd = self._faithful(0, 0, 8, 4)
        self._write(_name(self.vram, 0, 0, 8, 4, 4), hd)
        self._import(rec, {"a.png": "k1"})
        out = np.asarray(Image.open(self.pack / "k1.png"))
        for row in range(2 * SCALE):
            np.testing.assert_array_equal(out[row, 4 * SCALE:12 * SCALE], hd[0], "the gutter repeats the top edge")

    def test_semi_transparent_alpha_becomes_coverage(self) -> None:
        rec = Recorder()
        self._picture("a.png", rec, [(0, 0, 0, 0, 8, 8)])
        self._write(_name(self.vram, 0, 0, 8, 8, 4, semi=True), self._faithful(0, 0, 8, 8, alpha=128))
        self._import(rec, {"a.png": "k1"})
        out = np.asarray(Image.open(self.pack / "k1.png"))
        self.assertTrue((out[:8 * SCALE, :8 * SCALE, 3] == 255).all())

    def test_screen_vram_replacements_are_listed_with_their_check(self) -> None:
        rec = Recorder()
        rec.runtime_vram("screens/vram_system.bin", self.vram.words)
        self._write(_name(self.vram, 4, 8, 8, 4, 4), self._faithful(4, 8, 8, 4))
        self._import(rec, {})
        entries = json.loads((self.pack / duckstation_pack.VRAM_INDEX).read_text())["entries"]
        self.assertEqual(len(entries), 1)
        e = entries[0]
        self.assertEqual((e["page"], e["depth"], e["rect"], e["palette"], e["scale"]),
                         (list(PAGE), 4, [4, 8, 8, 4], list(COLOURS) + [0] * 12, SCALE))
        r = duckstation_pack.Replacement(Path(), 4, False, 0, 0, 4, 8, 8, 4, 0, 3)
        self.assertEqual(e["check"], duckstation_pack.vram_check(self.vram.words, *PAGE, r))
        self.assertTrue((self.pack / e["file"]).exists())


class OutputTest(unittest.TestCase):
    def test_only_new_empty_or_imported_folders_are_replaced(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            ds = root / "ds"
            (ds / "replacements").mkdir(parents=True)
            packs = root / "texture_packs"
            (packs / "other").mkdir(parents=True)
            (packs / "other" / "pack.json").write_text("{}")
            (root / "empty").mkdir()
            (root / "earlier").mkdir()
            (root / "earlier" / duckstation_pack.REPORT).write_text("")
            problem = duckstation_pack.output_problem
            self.assertIsNone(problem(ds, root / "new"))
            self.assertIsNone(problem(ds, root / "empty"))
            self.assertIsNone(problem(ds, root / "earlier"))
            self.assertIsNotNone(problem(ds, packs), "a folder of other packs")
            self.assertIsNotNone(problem(ds, packs / "other"), "a pack made otherwise")
            self.assertIsNotNone(problem(ds, ds), "the source pack")
            self.assertIsNotNone(problem(ds, ds / "replacements" / "out"), "inside the source pack")
            self.assertIsNotNone(problem(ds / "replacements", ds), "around the source pack")
            rec = Recorder()
            rec.save(root / "sources.zip")
            code = duckstation_pack.import_pack(ds, packs, Sources.load(root / "sources.zip"), root, {}, None)
            self.assertEqual(code, 1)
            self.assertTrue((packs / "other" / "pack.json").exists(), "nothing deleted")


class FailedImportTest(unittest.TestCase):
    def test_a_failed_import_keeps_the_earlier_pack(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            ds = root / "ds"
            (ds / "replacements").mkdir(parents=True)
            pack = root / "texture_packs" / "hd"
            pack.mkdir(parents=True)
            (pack / duckstation_pack.REPORT).write_text("earlier")
            (pack / "kept.png").write_bytes(b"png")
            Recorder().save(root / "sources.zip")
            sources = Sources.load(root / "sources.zip")
            with mock.patch.object(duckstation_pack, "Importer", side_effect=SystemExit("no xxhash")):
                with self.assertRaises(SystemExit):
                    duckstation_pack.import_pack(ds, pack, sources, root, {}, None)
            self.assertEqual((pack / "kept.png").read_bytes(), b"png", "the earlier pack stays")
            self.assertEqual(sorted(p.name for p in pack.parent.iterdir()), ["hd"], "no staging folder is left")
            self.assertEqual(duckstation_pack.import_pack(ds, pack, sources, root, {}, None), 0)
            self.assertFalse((pack / "kept.png").exists(), "a complete import replaces the pack")
            self.assertTrue((pack / "pack.json").exists())
            self.assertEqual(sorted(p.name for p in pack.parent.iterdir()), ["hd"])


class ParseTest(unittest.TestCase):
    def test_names(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            for name in ("texpage-STP8-00000000000000AB-00000000000000CD-128x256-2-128-128x65-P3-63.png",
                         "texpage-P4-0000000000000001-0000000000000002-64x256-3-0-4x4-P0-15.png",   # not whole words
                         "vram-write-0000000000000001-0000000000000002-64x64.png"):
                (root / name).write_bytes(b"")
            found, skipped = duckstation_pack.parse_pack(root)
        self.assertEqual(len(found), 1)
        r = found[0]
        self.assertEqual((r.depth, r.semi_transparent, r.texture_hash, r.palette_hash, r.x, r.y, r.w, r.h,
                          r.palette_min, r.palette_max, r.palette_size), (8, True, 0xAB, 0xCD, 2, 128, 128, 65, 3, 63, 61))
        self.assertEqual(r.words, (1, 64))
        self.assertEqual(len(skipped), 2)


if __name__ == "__main__":
    unittest.main()
