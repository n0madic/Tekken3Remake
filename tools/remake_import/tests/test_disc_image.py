"""Disc image formats (disc_image.py), on synthetic images: no game data."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest import mock

import common  # noqa: F401  (tools/research on the path)
import disc_image
from compare_bns import SECTOR_BYTES, mode2_form1_payload
from disc_image import PAYLOAD_BYTES, SYNC, AudioTrack, ImageError, IsoSectors, open_image

AUDIO_SECTORS = 3


def _raw_track(path: Path, sectors: int = 2) -> None:
    sector = SYNC + bytes(3) + b"\x02" + bytes(SECTOR_BYTES - len(SYNC) - 4)
    path.write_bytes(sector * sectors)


class DiscImageTest(unittest.TestCase):
    def setUp(self) -> None:
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        self.dir = Path(folder.name)

    def _open(self, name: str) -> disc_image.DiscImage:
        """The image, closed when the test ends."""
        image = open_image(self.dir / name)
        self.addCleanup(image.close)
        return image

    def test_sheet_with_compressed_tracks(self) -> None:
        _raw_track(self.dir / "Game (Track 1).bin")
        (self.dir / "Game (Track 2).ape").write_bytes(b"MAC ")
        (self.dir / "Game.cue").write_text(
            'FILE "Game (Track 1).bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n'
            'FILE "Game (Track 2).bin" BINARY\n  TRACK 02 AUDIO\n    INDEX 01 00:02:00\n')
        image = self._open("Game.cue")
        self.assertEqual(image.data_file.name, "Game (Track 1).bin")
        self.assertTrue(image.xa)
        self.assertEqual(image.audio, {2: AudioTrack(self.dir / "Game (Track 2).ape")})
        with self.assertRaises(ImageError):
            image.audio_pcm(2, None)          # an APE track needs FFmpeg

    def test_sheet_with_unquoted_names(self) -> None:
        _raw_track(self.dir / "game.bin")
        (self.dir / "game.cue").write_text("FILE game.bin BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n")
        self.assertEqual(self._open("game.cue").data_file, self.dir / "game.bin")

    def test_sheet_with_a_missing_track(self) -> None:
        (self.dir / "Game.cue").write_text('FILE "Gone.bin" BINARY\n  TRACK 01 MODE2/2352\n')
        with self.assertRaisesRegex(ImageError, "not found"):
            open_image(self.dir / "Game.cue")

    def test_tracks_sharing_a_file(self) -> None:
        """One file: data track at 0, then audio tracks from their pregaps (INDEX 00)."""
        _raw_track(self.dir / "Game.bin", sectors=2 + 150 + 3 + 5)
        (self.dir / "Game.cue").write_text(
            'FILE "Game.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n'
            '  TRACK 02 AUDIO\n    INDEX 00 00:00:02\n    INDEX 01 00:02:02\n'
            '  TRACK 03 AUDIO\n    INDEX 01 00:02:05\n')
        image = self._open("Game.cue")
        self.assertEqual(image.data_file, self.dir / "Game.bin")
        self.assertEqual(image.audio[2], AudioTrack(self.dir / "Game.bin", 2 * SECTOR_BYTES, 155 * SECTOR_BYTES))
        self.assertEqual(image.audio[3], AudioTrack(self.dir / "Game.bin", 155 * SECTOR_BYTES, None))
        self.assertEqual(len(image.audio_pcm(2, None)), 153 * SECTOR_BYTES)
        self.assertEqual(len(image.audio_pcm(3, None)), 5 * SECTOR_BYTES)

    def test_data_track_must_start_its_file(self) -> None:
        _raw_track(self.dir / "Game.bin", sectors=4)
        (self.dir / "Game.cue").write_text(
            'FILE "Game.bin" BINARY\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n'
            '  TRACK 02 MODE2/2352\n    INDEX 01 00:00:02\n')
        with self.assertRaisesRegex(ImageError, "does not start"):
            open_image(self.dir / "Game.cue")

    def test_lone_track_finds_its_audio(self) -> None:
        _raw_track(self.dir / "Game (Track 1).bin")
        (self.dir / "Game (Track 2).bin").write_bytes(bytes(SECTOR_BYTES * AUDIO_SECTORS + 5))
        image = self._open("Game (Track 1).bin")
        self.assertEqual(image.audio, {2: AudioTrack(self.dir / "Game (Track 2).bin")})
        self.assertEqual(len(image.audio_pcm(2, None)), SECTOR_BYTES * AUDIO_SECTORS)   # whole sectors

    def test_iso_seen_as_raw_sectors(self) -> None:
        payloads = [bytes([k]) * PAYLOAD_BYTES for k in (1, 2, 3)]
        (self.dir / "game.iso").write_bytes(b"".join(payloads))
        image = self._open("game.iso")
        self.assertIsInstance(image.sectors, IsoSectors)
        self.assertFalse(image.xa)
        self.assertEqual(len(image.sectors), 3 * SECTOR_BYTES)
        self.assertEqual(mode2_form1_payload(image.sectors, 1), payloads[1])
        self.assertEqual(image.sectors[SECTOR_BYTES - 2:SECTOR_BYTES + 12], bytes(2) + SYNC)

    def test_unknown_format(self) -> None:
        (self.dir / "game.bin").write_bytes(b"not a disc")
        with self.assertRaises(ImageError):
            open_image(self.dir / "game.bin")

    def _fake_chdman(self, track: bytes) -> None:
        """chdman writing a one-track sheet with the given data track, for the rest of the test."""
        def run(args: list[str], capture_output: bool):
            sheet = Path(args[args.index("-o") + 1])
            (sheet.parent / "disc.bin").write_bytes(track)
            sheet.write_text('FILE "disc.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n')
            return type("Result", (), {"returncode": 0, "stderr": b""})()

        for patch in (mock.patch.object(disc_image.shutil, "which", lambda name: "/fake/chdman"),
                      mock.patch.object(disc_image.subprocess, "run", run)):
            patch.start()
            self.addCleanup(patch.stop)

    def test_chd_extraction_ends_with_the_image(self) -> None:
        _raw_track(self.dir / "track.bin")
        self._fake_chdman((self.dir / "track.bin").read_bytes())
        (self.dir / "game.chd").write_bytes(b"MComprHD")
        image = open_image(self.dir / "game.chd")
        folder = image.data_file.parent
        self.assertTrue(image.xa and folder.is_dir())
        image.close()
        self.assertFalse(folder.exists())

    def test_chd_extraction_removed_when_unreadable(self) -> None:
        self._fake_chdman(b"not a track")
        (self.dir / "game.chd").write_bytes(b"MComprHD")
        folders = set(Path(tempfile.gettempdir()).glob("t3chd*"))
        with self.assertRaises(ImageError):
            open_image(self.dir / "game.chd")
        self.assertEqual(set(Path(tempfile.gettempdir()).glob("t3chd*")), folders)


if __name__ == "__main__":
    unittest.main()
