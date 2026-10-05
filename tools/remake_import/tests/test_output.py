"""The converter's output folder (common.Output): no game data."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from common import Output, is_foreign_folder


class OutputTest(unittest.TestCase):
    def test_prune_keeps_the_sidecars_of_produced_files(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            out = Output(root)
            out.write("movies/a.ogv", b"movie")
            for name in ("movies/a.ogv.import", "movies/a.ogv.uid", "movies/old.ogv", "movies/old.ogv.uid"):
                (root / name).write_bytes(b"")
            self.assertEqual(out.prune(), 2)
            self.assertEqual(sorted(p.name for p in (root / "movies").iterdir()), ["a.ogv", "a.ogv.import", "a.ogv.uid"])

    def test_a_run_that_ended_early_leaves_a_folder_the_next_run_accepts(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder) / "imported"
            self.assertFalse(is_foreign_folder(root), "a missing folder")
            root.mkdir()
            self.assertFalse(is_foreign_folder(root), "an empty folder")
            out = Output(root)
            out.mark()
            out.write("tables/a.json", b"{}")        # ... and then the run ends: no manifest.json
            self.assertFalse(is_foreign_folder(root), "the marked folder of an unfinished run")

    def test_a_folder_of_other_files_is_foreign(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "notes.txt").write_bytes(b"mine")
            self.assertTrue(is_foreign_folder(root))
            (root / "manifest.json").write_bytes(b'{"converter_version": 3}')
            self.assertFalse(is_foreign_folder(root), "folders of earlier runs have a manifest")

    def test_a_foreign_manifest_does_not_make_a_folder_the_converters_own(self) -> None:
        for content in (b"{}", b'{"name": "other-tool"}', b"[1]", b"not json", b""):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as folder:
                root = Path(folder)
                (root / "manifest.json").write_bytes(content)
                (root / "notes.txt").write_bytes(b"mine")
                self.assertTrue(is_foreign_folder(root))

    def test_invalidating_removes_only_the_manifest(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            out = Output(root)
            out.invalidate_manifest()                 # no manifest yet: nothing to do
            (root / "manifest.json").write_bytes(b'{"converter_version": 3}')
            out.write("tables/a.json", b"{}")
            out.invalidate_manifest()
            self.assertFalse((root / "manifest.json").exists())
            self.assertTrue((root / "tables/a.json").exists())

    def test_prune_keeps_the_marker(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            out = Output(root)
            out.mark()
            self.assertEqual(out.prune(), 0)
            self.assertTrue((root / ".converter").exists())


if __name__ == "__main__":
    unittest.main()
