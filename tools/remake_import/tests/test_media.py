"""The FFmpeg wrapper (media.FFmpeg): no game data, a stand-in executable."""

from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path

from media import FFmpeg, MediaError

# Exits 0 only when its standard input is the null device.
STDIN_PROBE = f"""#!{sys.executable}
import os, sys
sys.exit(0 if os.path.samestat(os.fstat(0), os.stat(os.devnull)) else 1)
"""


@unittest.skipIf(os.name != "posix", "the stand-in executable is a script with a shebang")
class FFmpegTest(unittest.TestCase):
    def test_run_never_hands_the_terminal_to_ffmpeg(self) -> None:
        # FFmpeg with a terminal on stdin changes its settings; parallel encodes
        # (arcade music) then restore each other's and leave the shell without echo.
        with tempfile.TemporaryDirectory() as folder:
            probe = Path(folder) / "ffmpeg"
            probe.write_text(STDIN_PROBE)
            probe.chmod(0o755)
            try:
                FFmpeg(str(probe), frozenset()).run(["-i", "in.wav", "out.ogg"])
            except MediaError:
                self.fail("FFmpeg was started with an inherited standard input")


if __name__ == "__main__":
    unittest.main()
