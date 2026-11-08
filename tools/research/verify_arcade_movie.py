#!/usr/bin/env python3
"""Check the arcade's attract movie (arcade_movie.py) against the game and against MAME.

- The game's own `DecDCTvlc` runs in the CPU harness on sample files: its run-length words must be
  the codes `arcade_movie.read_codes` reads.
- The decoded pictures, in the game's 15 bits and placed on the 512 × 240 screen as FUN_801BE1C0's
  five quads place them, must equal MAME's frames at the file `shown_file` names for the flow's
  timer. MAME's frames are the attract's snapshots (`work/arcade/flow/snap_attract`, with
  `run/attract.log`) and, when it was captured, every frame of the movie's state
  (`work/arcade/movie`, from arcade_movie_capture.lua below).
- The encoded movie, with `--out DIR` (a conversion): FFmpeg decodes it; its frame count, rate and
  picture per frame must be the converter's.

A verifier that cannot fail proves nothing, so every run also makes its negative controls (a picture
off by one, Cr and Cb swapped, the wrong quantiser scale, a damaged stream): each one must fail the
comparison with MAME. `--control NAME` compares with that control in place of the decoder, which must
print FAIL and exit 1.

The capture (MAME's frames contain game data: keep them in work/):

    cd work/arcade/movie && FLOW_LOG=movie.log mame tekken3 -rompath ../roms -video none -sound none \
        -nothrottle -skip_gameinfo -autoboot_script ../../../tools/research/arcade_movie_capture.lua \
        -snapshot_directory snap -nvram_directory nvram -cfg_directory cfg

Usage: python3.14 tools/research/verify_arcade_movie.py [--zip tekken3_mame.zip] [--out work/arcade/out_movie]
"""

from __future__ import annotations

import argparse
import logging
import re
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np
from PIL import Image

from arcade_cpu import DEFAULT_ZIP, ROOT, arcade, arcade_cpu

import arcade_movie  # noqa: E402  (arcade_cpu puts tools/remake_import on the import path)
import media  # noqa: E402

log = logging.getLogger("verify_arcade_movie")

DEC_DCT_VLC = 0x801E82E8
STREAM_ADDRESS = 0x80300000
WORDS_ADDRESS = 0x80320000
SAMPLE_FILES = (0, 2, 80, 130, 259, 260)
WORD_END_OF_BLOCK = 0xFE00
WORD_RUN_SHIFT = 10
WORD_LEVEL_MASK = 0x3FF

SCREEN_WIDTH, SCREEN_LINES = 512, 240
QUAD_WIDTH, QUAD_TEXELS = 0x68, 0x40        # FUN_801BE1C0: 64 texels stretched over 104 pixels
RASTER_FRACTION = 16                        # MAME's texture step per pixel, truncated
FIRST_LINE, END_LINE = 10, 238              # MAME's frames are black above and below these on every screen
END_COLUMN = 510                            # FUN_801BE1C0's black strip on the right
OUTPUT_BITS_DROPPED = 3                     # the MDEC's 15-bit output
MOVIE_STEP_VBLANKS = arcade_movie.VBLANKS_PER_FRAME
MIN_FAILED_SHARE = 0.002                    # a control differs in at least this share of the pixels
THEORA_MIN_PSNR = {"large": 36.0, "small": 33.0}
PSNR_MARGIN = 3.0
FAR_FRAMES = 40                             # the movie's frame compared with a picture this far away
SAMPLE_EVERY = 5

CAPTURE = ROOT / "work" / "arcade" / "movie"
ATTRACT = ROOT / "work" / "arcade" / "flow"
LINE = re.compile(r"(\d+) snap=(\d+) state=(\d+) sub=(\d+) timer=(\d+) pic=(\d+)")
SNAP_LINE = re.compile(r"SNAP (\d+) frame=(\d+) state=(\d+) sub=(\d+) mode=\d+ step=\d+ pic=(\d+)")


@dataclass(frozen=True)
class Frame:
    """A frame of MAME's, in the movie's state."""

    png: Path
    number: int
    timer: int


def capture_frames() -> list[Frame]:
    """Every frame of arcade_movie_capture.lua's run."""
    path = CAPTURE / "movie.log"
    if not path.exists():
        return []
    frames = []
    for line in path.read_text().splitlines():
        m = LINE.match(line)
        if m and int(m[3]) == 2 and int(m[6]) == arcade_movie.CATEGORY + 1:
            frames.append(Frame(CAPTURE / "snap" / "tekken3" / f"{m[2]}.png", int(m[1]), int(m[5])))
    return frames


def attract_frames() -> list[Frame]:
    """The snapshots of the attract's log: a new timer every 4 vblanks from the frame sub-state 2 shows."""
    path = ATTRACT / "run" / "attract.log"
    if not path.exists():
        return []
    frames = []
    first = None
    for line in path.read_text().splitlines():
        m = SNAP_LINE.match(line)
        if not m:
            continue
        state, sub, picture = int(m[3]), int(m[4]), int(m[5])
        if state != 2 or picture != arcade_movie.CATEGORY + 1:
            first = None
            continue
        if first is None:
            first = int(m[2])
        frames.append(Frame(ATTRACT / "snap_attract" / "tekken3" / f"{m[1]}.png", int(m[2]), (int(m[2]) - first) // MOVIE_STEP_VBLANKS))
    return frames


def game_words(cpu, data: bytes) -> list[int]:
    """The game's DecDCTvlc on a file: the words it would send to the MDEC."""
    cpu.write(STREAM_ADDRESS, data)
    cpu.call(DEC_DCT_VLC, STREAM_ADDRESS, WORDS_ADDRESS)
    count = len(arcade_movie.read_codes(data).levels) + 2 * arcade_movie.BLOCKS + 2
    raw = cpu.read(WORDS_ADDRESS, 2 * count)
    return np.frombuffer(raw, "<u2").tolist()


def codes_from_words(words: list[int]) -> tuple[list[int], list[int], list[int]]:
    """The DC values, places and levels in the game's words (the first two words are its header)."""
    dc, places, levels = [], [], []
    position = 2
    for block in range(arcade_movie.BLOCKS):
        word = words[position]
        position += 1
        dc.append(arcade_movie._signed(word & WORD_LEVEL_MASK))
        place = block * arcade_movie.BLOCK_VALUES
        while (word := words[position]) != WORD_END_OF_BLOCK:
            position += 1
            place += (word >> WORD_RUN_SHIFT) + 1
            places.append(place)
            levels.append(arcade_movie._signed(word & WORD_LEVEL_MASK))
        position += 1
    return dc, places, levels


def check_against_game(arc: arcade.ArcadeSet, files: list[bytes]) -> bool:
    cpu = arcade_cpu(arc)
    good = True
    for index in SAMPLE_FILES:
        codes = arcade_movie.read_codes(files[index])
        dc, places, levels = codes_from_words(game_words(cpu, files[index]))
        same = dc == codes.dc.tolist() and places == codes.places.tolist() and levels == codes.levels.tolist()
        log.info("  file %3d: %d values, %s", index, len(levels), "same as the game's DecDCTvlc" if same else "DIFFERENT from the game's DecDCTvlc")
        good &= same
    return good


def texel_columns() -> np.ndarray:
    """The picture's column at each screen column: the five quads, stepped as MAME's rasteriser."""
    x = np.arange(SCREEN_WIDTH)
    step = (QUAD_TEXELS << RASTER_FRACTION) // QUAD_WIDTH
    return x // QUAD_WIDTH * QUAD_TEXELS + ((x % QUAD_WIDTH * step) >> RASTER_FRACTION)


def on_screen(picture: np.ndarray) -> np.ndarray:
    """A decoded picture as MAME shows it: 5 bits per channel, 8-bit expanded, placed on the screen."""
    five = picture[:, texel_columns() % arcade_movie.WIDTH] >> OUTPUT_BITS_DROPPED
    return (five << OUTPUT_BITS_DROPPED) | (five >> (5 - OUTPUT_BITS_DROPPED))


def mismatch(picture: np.ndarray, frame: Frame) -> tuple[float, int]:
    """The share of pixels that differ from MAME's frame in the area it shows, and the largest difference."""
    with Image.open(frame.png) as image:
        reference = np.asarray(image.convert("RGB"), np.int16)
    if reference.shape != (SCREEN_LINES, SCREEN_WIDTH, 3):
        raise SystemExit(f"{frame.png}: expected a {SCREEN_WIDTH} × {SCREEN_LINES} frame")
    diff = np.abs(on_screen(picture).astype(np.int16)[FIRST_LINE:END_LINE, :END_COLUMN] - reference[FIRST_LINE:END_LINE, :END_COLUMN])
    return float((diff > 0).any(axis=-1).mean()), int(diff.max())


class Pictures:
    """What a run compares with MAME: the decoder, or a control in its place."""

    def __init__(self, files: list[bytes], tables: arcade_movie.Tables, control: str | None = None) -> None:
        self.files = files
        self.tables = tables
        self.control = control
        self.cache: dict[int, np.ndarray] = {}

    def _decoded(self, index: int) -> np.ndarray:
        data = self.files[index]
        if self.control == "swapped_chroma":
            codes = arcade_movie.read_codes(data)
            samples = arcade_movie._idct(arcade_movie._coefficients(codes, self.tables), self.tables).copy()
            samples = samples.reshape(arcade_movie.MACROBLOCKS, arcade_movie.BLOCKS_PER_MACROBLOCK, arcade_movie.BLOCK_VALUES)
            samples[:, [0, 1]] = samples[:, [1, 0]]
            return arcade_movie._rgb(samples)
        if self.control == "wrong_scale":
            codes = arcade_movie.read_codes(data)
            wrong = arcade_movie.Codes(codes.quant_scale + 1, codes.dc, codes.places, codes.levels)
            return arcade_movie._rgb(arcade_movie._idct(arcade_movie._coefficients(wrong, self.tables), self.tables))
        if self.control == "damaged_stream":
            wrong = bytearray(data)
            middle = arcade_movie.HEADER.size + (len(data) - arcade_movie.HEADER.size) // 2
            wrong[middle] ^= 0x10
            try:
                return arcade_movie.decode(bytes(wrong), self.tables)
            except arcade.ArcadeError:
                return np.zeros((arcade_movie.HEIGHT, arcade_movie.WIDTH, 3), np.uint8)
        return arcade_movie.decode(data, self.tables)

    def at(self, timer: int) -> np.ndarray:
        offset = 1 if self.control == "off_by_one" else 0
        index = arcade_movie.shown_file(timer - offset, len(self.files))
        if index not in self.cache:
            self.cache[index] = self._decoded(index)
        return self.cache[index]


def compare(pictures: Pictures, frames: list[Frame]) -> tuple[float, float, int, int]:
    """Over the frames: the mean and the worst share of differing pixels, the largest difference and
    how many frames differ at all."""
    shares = []
    largest = 0
    for frame in frames:
        share, most = mismatch(pictures.at(frame.timer), frame)
        shares.append(share)
        largest = max(largest, most)
    return float(np.mean(shares)), float(max(shares)), largest, sum(1 for s in shares if s > 0)


def encoded_frames(tool: media.FFmpeg, path: Path) -> np.ndarray:
    """The decoded frames at their times. A Theora frame equal to the one before is an empty packet,
    which FFmpeg's decoder does not output: the frames after the last one that differs are missing."""
    with tempfile.TemporaryDirectory() as tmp:
        raw = Path(tmp) / "frames.rgb"
        tool.run(["-i", str(path), "-fps_mode", "cfr", "-f", "rawvideo", "-pix_fmt", "rgb24", str(raw)])
        data = np.fromfile(raw, np.uint8)
    return data.reshape(-1, arcade_movie.HEIGHT, arcade_movie.WIDTH, 3)


def stream_packets(tool: media.FFmpeg, path: Path) -> int:
    """The stream's frames, an empty one included."""
    result = subprocess.run([tool.path, "-hide_banner", "-loglevel", "error", "-i", str(path), "-map", "0:v", "-c", "copy", "-f", "framecrc", "-"],
                            capture_output=True, text=True, check=True)
    return sum(1 for line in result.stdout.splitlines() if not line.startswith("#"))


def stream_rate(tool: media.FFmpeg, path: Path) -> float:
    result = subprocess.run([tool.path, "-hide_banner", "-i", str(path)], capture_output=True, text=True)
    found = re.search(r"Video:.* ([\d.]+) tbr", result.stderr)
    return float(found[1]) if found else 0.0


def psnr(a: np.ndarray, b: np.ndarray) -> float:
    mse = float(np.mean((a.astype(np.float64) - b.astype(np.float64)) ** 2))
    return 99.0 if mse == 0 else 10 * np.log10(255.0 ** 2 / mse)


def check_encoded(out: Path, pictures: Pictures) -> bool:
    tool = media.find_ffmpeg()
    frames = arcade_movie.frame_count(len(pictures.files))
    good = True
    for variant in media.THEORA_QUALITIES:
        path = out / "movies" / f"{arcade_movie.NAME}.{variant}.ogv"
        if not path.exists():
            log.info("  %s: no such file", path)
            return False
        decoded = encoded_frames(tool, path)
        packets = stream_packets(tool, path)
        rate = stream_rate(tool, path)
        at = range(0, len(decoded), SAMPLE_EVERY)
        values = [psnr(decoded[t], pictures.at(t)) for t in at]
        away = [psnr(decoded[t], pictures.at(t + FAR_FRAMES)) for t in at if t + FAR_FRAMES < frames]
        ok = packets == frames and rate == arcade_movie.MOVIE_FPS and float(np.mean(values)) >= THEORA_MIN_PSNR[variant]
        ok &= float(np.mean(away)) < float(np.mean(values)) - PSNR_MARGIN
        log.info("  %s: %d frames (want %d) at %.0f per second, %.1f dB (worst frame %.1f; %.1f against the picture %d frames away): %s", variant, packets, frames,
                 rate, np.mean(values), np.min(values), np.mean(away), FAR_FRAMES, "ok" if ok else "FAIL")
        good &= ok
    return good


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--out", type=Path, help="a conversion, to check its encoded movie")
    parser.add_argument("--control", choices=("off_by_one", "swapped_chroma", "wrong_scale", "damaged_stream"),
                        help="compare this control with MAME in place of the decoder: it must fail")
    args = parser.parse_args()
    arc = arcade.open_set(args.zip)
    files = arc.category(arcade_movie.CATEGORY)
    tables = arcade_movie.tables_of(arc)

    frames = attract_frames() + capture_frames()
    if not frames:
        log.error("no MAME frames: see the capture in this file's description")
        return 1
    log.info("%d files, %d MAME frames of the movie (timers %d to %d)", len(files), len(frames), min(f.timer for f in frames), max(f.timer for f in frames))

    if args.control:
        mean, worst, largest, differing = compare(Pictures(files, tables, args.control), frames)
        failed = worst >= MIN_FAILED_SHARE
        log.info("control %s: %.4f of the pixels differ (worst %.4f, largest difference %d), %d frames differ: %s", args.control, mean, worst, largest,
                 differing, "FAIL, as a control must" if failed else "PASS: this control cannot catch anything")
        return 1 if failed else 0

    good = True
    log.info("the codes against the game's DecDCTvlc, in the CPU harness:")
    good &= check_against_game(arc, files)

    mean, worst, largest, differing = compare(Pictures(files, tables), frames)
    exact = differing == 0
    log.info("the pictures against MAME: %.6f of the pixels differ (worst frame %.6f, largest difference %d), %d of %d frames differ: %s",
             mean, worst, largest, differing, len(frames), "ok" if exact else "FAIL")
    good &= exact

    # Frames of moving pictures: the first pictures and the last are alike.
    moving = [f for f in frames if arcade_movie.DISPLAY_DELAY + 8 < f.timer < len(files) - 8]
    for control in ("off_by_one", "swapped_chroma", "wrong_scale", "damaged_stream"):
        sample = moving[::max(len(moving) // 40, 1)]
        mean, worst, largest, _ = compare(Pictures(files, tables, control), sample)
        caught = worst >= MIN_FAILED_SHARE
        log.info("negative control %s: %.4f of the pixels differ on %d frames (worst %.4f): %s", control, mean, len(sample), worst,
                 "fails, as it must" if caught else "PASSES: this verifier would not see it")
        good &= caught

    if args.out is not None:
        log.info("the encoded movie in %s:", args.out)
        good &= check_encoded(args.out, Pictures(files, tables))

    log.info("%s", "PASS" if good else "FAIL")
    return 0 if good else 1


if __name__ == "__main__":
    sys.exit(main())
