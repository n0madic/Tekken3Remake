"""The movies' entries in movies.json (media.py), from synthetic descriptors: no game data."""

from __future__ import annotations

import unittest
from unittest import mock

import media


def _entry(flags: int) -> dict:
    movie = media._Movie(first=0, last=10, width=320, height=240, last_frame=5, volume=127, flags=flags)
    with mock.patch.object(media, "convert_movie", return_value=({"video": ["m.large.ogv"]}, 1.5)):
        return media._convert_listed(None, None, "m", movie, b"", [])


class MovieEntryTest(unittest.TestCase):
    def test_the_restart_flag_loops_the_movie(self) -> None:
        # Gon's ending (descriptor 20, flags 4): the player rereads it until Start.
        self.assertTrue(_entry(media.MOVIE_RESTART)["loop"])
        self.assertFalse(_entry(0)["loop"])
        self.assertFalse(_entry(0x3 | media.MOVIE_WHITE_END)["loop"], "the opening's end modes and the logo's white end")

    def test_the_white_end_flag_stays_its_own(self) -> None:
        self.assertFalse(_entry(media.MOVIE_RESTART)["white_end"])
        self.assertTrue(_entry(media.MOVIE_WHITE_END)["white_end"])


if __name__ == "__main__":
    unittest.main()
