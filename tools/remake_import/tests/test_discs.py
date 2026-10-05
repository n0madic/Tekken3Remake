"""The disc images given to the converter and the layout tool: required, one per release."""

from __future__ import annotations

import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest import mock

import common
import convert
import layout
from common import JP_ORIG, JP_REV1, USA, DiscError


def _fake_open(releases: dict[str, common.Release]):
    """Disc.open telling the releases apart by the image's file name."""
    return lambda path: SimpleNamespace(release=releases[path.name], image=SimpleNamespace(path=path))


class DiscsTest(unittest.TestCase):
    def test_one_disc_per_release(self) -> None:
        with mock.patch.object(common.Disc, "open", _fake_open({"a.cue": JP_REV1, "b.cue": USA, "c.cue": JP_ORIG})):
            discs = common.open_discs([Path("b.cue"), Path("a.cue"), Path("c.cue")])
        self.assertEqual({k: d.image.path.name for k, d in discs.items()},
                         {JP_REV1.key: "a.cue", USA.key: "b.cue", JP_ORIG.key: "c.cue"})

    def test_two_images_of_one_release(self) -> None:
        with mock.patch.object(common.Disc, "open", _fake_open({"a.cue": JP_REV1, "b.chd": JP_REV1})):
            with self.assertRaisesRegex(DiscError, "a.cue and b.chd are both"):
                common.open_discs([Path("a.cue"), Path("b.chd")])

    def test_canonical_rebases_once(self) -> None:
        disc = common.Disc(USA, b"", [], None, USA)
        made = []
        with mock.patch.object(layout, "rebased", lambda d: made.append(d) or object()):
            first = disc.canonical()
            self.assertIs(disc.canonical(), first)
        self.assertEqual(made, [disc])

    def test_images_required(self) -> None:
        for main in (convert.main, layout.main):
            with self.subTest(tool=main.__module__), mock.patch("sys.argv", ["tool"]), \
                    mock.patch("sys.stderr"), self.assertRaises(SystemExit) as exit_info:
                main()
            self.assertEqual(exit_info.exception.code, 2)


if __name__ == "__main__":
    unittest.main()
