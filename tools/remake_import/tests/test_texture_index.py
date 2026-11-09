"""convert.texture_index: which written pictures a texture pack may replace."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

import common
import arcade_effect_objects
import convert
import effects


class TextureIndexTest(unittest.TestCase):
    def test_the_object_pages_and_palettes_of_both_builds_are_data(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            out = common.Output(Path(tmp))
            data = [effects.OBJECT_PAGE_FILE, effects.OBJECT_PALETTES_FILE,
                    arcade_effect_objects.PAGE_FILE, arcade_effect_objects.PALETTES_FILE]
            for name in data + ["hit.png"]:
                out.write(f"effects/{name}", name.encode())
            self.assertEqual(list(convert.texture_index(out)), ["effects/hit.png"])


if __name__ == "__main__":
    unittest.main()
