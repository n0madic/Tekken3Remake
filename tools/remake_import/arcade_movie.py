"""The arcade's attract movie (MAME's set, category 0) → `movies/` (flow-and-screens.md#movie).

Each of the category's files is one picture, 320 × 240, as a plain MDEC bitstream: the game runs
`DecDCTvlc` on it and sends the result to the MDEC in 15-bit colour (FUN_801BE474). It decodes one
file per frame of the movie's state, and a frame lasts 4 vblanks. This module decodes the pictures
itself and writes them in the format of the PlayStation's movies (media.py): Ogg Theora in two
qualities, or the JPEG-frame fallback when FFmpeg has no Theora encoder. There is no sound in the
files: the board plays the movie's music.

The movie has one frame per value of the flow's timer (`ArcadeGameFlow.timer` goes 0 … files + 2),
so the runtime shows the frame the timer names: `shown_file` says which picture the screen has
then. `movies.json`'s `attract` entry has the frame rate and count.

The tables come from the program; the code table is the public MPEG-1 one and the zigzag its order.
The picture's arithmetic gives every pixel of MAME's frames (tools/research/verify_arcade_movie.py).
"""

from __future__ import annotations

import functools
import struct
import tempfile
from dataclasses import dataclass
from pathlib import Path

import numpy as np

import media
from arcade import ArcadeError, ArcadeSet
from common import Output, log

CATEGORY = 0
NAME = "attract"
WIDTH, HEIGHT = 320, 240
MACROBLOCK = 16
COLUMNS, ROWS = WIDTH // MACROBLOCK, HEIGHT // MACROBLOCK
BLOCK_SIDE = 8
BLOCK_VALUES = BLOCK_SIDE * BLOCK_SIDE
BLOCKS_PER_MACROBLOCK = 6       # Cr, Cb, then the four of Y
CHROMA_BLOCKS = 2
MACROBLOCKS = COLUMNS * ROWS    # top to bottom, then the next column (a strip per column: FUN_801BE328)
BLOCKS = MACROBLOCKS * BLOCKS_PER_MACROBLOCK

VBLANKS_PER_FRAME = 4           # FUN_801BD318: picture kind 1 waits for the fourth
MOVIE_FPS = 60 // VBLANKS_PER_FRAME
DISPLAY_DELAY = 2               # a file decoded at timer t is on the screen at timer t + 2 (observed in MAME)
TIMER_PAST_FILES = 3            # the flow's timer ends at files + 2: FUN_801BD5A0's `> count + 1`, from 0

QUANT_TABLES = 0x80204AB0       # MDEC_reset's command 2: 64 bytes for Y, then 64 for Cr and Cb, in zigzag order
SCALE_TABLE = 0x80204B34        # MDEC_reset's command 3: the IDCT's 8 × 8 s16
TABLE_LUMA, TABLE_CHROMA = 0, 1
BITSTREAM_ID = 0x3800           # the header's second word: the MDEC's command, decode to 15 bits
HEADER = struct.Struct("<HHHH")     # size, BITSTREAM_ID, quantiser scale, version
VERSIONS = (1, 2)               # the versions with raw DC values (DecDCTvlc: version < 3)

DC_BITS = 10
ESCAPE_BITS = 16                # after the escape code: 6 bits of run, 10 of level
RUN_SHIFT = 10
LEVEL_MASK = 0x3FF
LEVEL_SIGN = 0x200
LEVEL_RANGE = 0x400
END_OF_PICTURE = 0x1FF          # where a block's DC value would be (DecDCTvlc's test)
QUANT_DIVISOR = 8

# The IDCT's fixed point: as MAME's mdec_cos_precalc and mdec_idct.
COSINE_PRODUCT_SHIFT = 9
IDCT_SHIFT = 23
# YCrCb to RGB in 10 fractional bits, each term truncated on its own: 1.402, −0.3437, −0.7143, 1.772.
COLOUR_SHIFT = 10
RED_CR, GREEN_CB, GREEN_CR, BLUE_CB = 1435, -351, -731, 1814
SAMPLE_MIN, SAMPLE_MAX, SAMPLE_OFFSET = -128, 127, 128

# The order of a block's values in the stream (MPEG-1).
ZIGZAG = np.array((
    0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5,
    12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7, 14, 21, 28,
    35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51,
    58, 59, 52, 45, 38, 31, 39, 46, 53, 60, 61, 54, 47, 55, 62, 63,
))

# The MPEG-1 table of DCT coefficients (B.14, the non-first form): code, run, level; a code is followed by
# the level's sign bit.
AC_CODES = (
    ("11", 0, 1), ("011", 1, 1), ("0100", 0, 2), ("0101", 2, 1), ("00101", 0, 3), ("00111", 3, 1), ("00110", 4, 1),
    ("000110", 1, 2), ("000111", 5, 1), ("000101", 6, 1), ("000100", 7, 1), ("0000110", 0, 4), ("0000100", 2, 2),
    ("0000111", 8, 1), ("0000101", 9, 1), ("00100110", 0, 5), ("00100001", 0, 6), ("00100101", 1, 3),
    ("00100100", 3, 2), ("00100111", 10, 1), ("00100011", 11, 1), ("00100010", 12, 1), ("00100000", 13, 1),
    ("0000001010", 0, 7), ("0000001100", 1, 4), ("0000001011", 2, 3), ("0000001111", 4, 2), ("0000001001", 5, 2),
    ("0000001110", 14, 1), ("0000001101", 15, 1), ("0000001000", 16, 1), ("000000011101", 0, 8),
    ("000000011000", 0, 9), ("000000010011", 0, 10), ("000000010000", 0, 11), ("000000011011", 1, 5),
    ("000000010100", 2, 4), ("000000011100", 3, 3), ("000000010010", 4, 3), ("000000011110", 6, 2),
    ("000000010101", 7, 2), ("000000010001", 8, 2), ("000000011111", 17, 1), ("000000011010", 18, 1),
    ("000000011001", 19, 1), ("000000010111", 20, 1), ("000000010110", 21, 1), ("0000000011010", 0, 12),
    ("0000000011001", 0, 13), ("0000000011000", 0, 14), ("0000000010111", 0, 15), ("0000000010110", 1, 6),
    ("0000000010101", 1, 7), ("0000000010100", 2, 5), ("0000000010011", 3, 4), ("0000000010010", 5, 3),
    ("0000000010001", 9, 2), ("0000000010000", 10, 2), ("0000000011111", 22, 1), ("0000000011110", 23, 1),
    ("0000000011101", 24, 1), ("0000000011100", 25, 1), ("0000000011011", 26, 1), ("00000000011111", 0, 16),
    ("00000000011110", 0, 17), ("00000000011101", 0, 18), ("00000000011100", 0, 19), ("00000000011011", 0, 20),
    ("00000000011010", 0, 21), ("00000000011001", 0, 22), ("00000000011000", 0, 23), ("00000000010111", 0, 24),
    ("00000000010110", 0, 25), ("00000000010101", 0, 26), ("00000000010100", 0, 27), ("00000000010011", 0, 28),
    ("00000000010010", 0, 29), ("00000000010001", 0, 30), ("00000000010000", 0, 31), ("000000000011000", 0, 32),
    ("000000000010111", 0, 33), ("000000000010110", 0, 34), ("000000000010101", 0, 35), ("000000000010100", 0, 36),
    ("000000000010011", 0, 37), ("000000000010010", 0, 38), ("000000000010001", 0, 39), ("000000000010000", 0, 40),
    ("000000000011111", 1, 8), ("000000000011110", 1, 9), ("000000000011101", 1, 10), ("000000000011100", 1, 11),
    ("000000000011011", 1, 12), ("000000000011010", 1, 13), ("000000000011001", 1, 14), ("0000000000010011", 1, 15),
    ("0000000000010010", 1, 16), ("0000000000010001", 1, 17), ("0000000000010000", 1, 18), ("0000000000010100", 6, 3),
    ("0000000000011010", 11, 2), ("0000000000011001", 12, 2), ("0000000000011000", 13, 2), ("0000000000010111", 14, 2),
    ("0000000000010110", 15, 2), ("0000000000010101", 16, 2), ("0000000000011111", 27, 1), ("0000000000011110", 28, 1),
    ("0000000000011101", 29, 1), ("0000000000011100", 30, 1), ("0000000000011011", 31, 1),
)
END_OF_BLOCK_CODE = "10"
ESCAPE_CODE = "000001"
RUN_END, RUN_ESCAPE, RUN_INVALID = -1, -2, -3
WINDOW_BITS = 17                # the longest code with its sign bit


@dataclass(frozen=True)
class Tables:
    """What the game loads into the MDEC: quantisation by kind of block (TABLE_*) and the IDCT's."""

    quant: np.ndarray           # (2, 64), zigzag order
    scale: np.ndarray           # (8, 8)


@dataclass(frozen=True)
class Codes:
    """One picture's bitstream: a value per place of the blocks (`block * 64 + zigzag position`)."""

    quant_scale: int
    dc: np.ndarray              # (BLOCKS,)
    places: np.ndarray
    levels: np.ndarray


def tables_of(arc: ArcadeSet) -> Tables:
    quant = np.frombuffer(arc.prog(QUANT_TABLES, 2 * BLOCK_VALUES), np.uint8).astype(np.int64).reshape(2, BLOCK_VALUES)
    scale = np.frombuffer(arc.prog(SCALE_TABLE, 2 * BLOCK_VALUES), "<i2").astype(np.int64).reshape(BLOCK_SIDE, BLOCK_SIDE)
    return Tables(quant, scale)


@functools.lru_cache(maxsize=1)
def code_table() -> list[tuple[int, int, int]]:
    """(bits used, run, level) by the next WINDOW_BITS bits of the stream."""
    table = [(0, RUN_INVALID, 0)] * (1 << WINDOW_BITS)

    def put(code: str, entry: tuple[int, int, int]) -> None:
        free = WINDOW_BITS - len(code)
        first = int(code, 2) << free
        table[first:first + (1 << free)] = [entry] * (1 << free)

    put(END_OF_BLOCK_CODE, (len(END_OF_BLOCK_CODE), RUN_END, 0))
    put(ESCAPE_CODE, (len(ESCAPE_CODE), RUN_ESCAPE, 0))
    for code, run, level in AC_CODES:
        put(code + "0", (len(code) + 1, run, level))
        put(code + "1", (len(code) + 1, run, -level))
    return table


def _windows(stream: bytes) -> list[int]:
    """The next WINDOW_BITS bits at every bit of the stream: 16-bit little-endian words, each read
    from its top bit (DecDCTvlc)."""
    words = np.frombuffer(stream, "<u2", len(stream) // 2)
    bits = np.unpackbits(np.frombuffer(words.astype(">u2").tobytes(), np.uint8))
    bits = np.concatenate((bits, np.zeros(WINDOW_BITS, np.uint8)))
    views = np.lib.stride_tricks.sliding_window_view(bits, WINDOW_BITS).astype(np.int32)
    return (views @ (1 << np.arange(WINDOW_BITS - 1, -1, -1))).tolist()


def _signed(value: int) -> int:
    return value - LEVEL_RANGE if value & LEVEL_SIGN else value


def read_codes(data: bytes) -> Codes:
    """The header and the codes of one file, as DecDCTvlc reads them."""
    if len(data) < HEADER.size:
        raise ArcadeError("movie picture: shorter than its header")
    _, marker, quant_scale, version = HEADER.unpack_from(data)
    if marker != BITSTREAM_ID or version not in VERSIONS:
        raise ArcadeError(f"movie picture: not an MDEC bitstream of version 1 or 2 ({marker:#x}, version {version})")
    windows = _windows(data[HEADER.size:])
    table = code_table()
    dc = [0] * BLOCKS
    places: list[int] = []
    levels: list[int] = []
    position = 0
    try:
        for block in range(BLOCKS):
            value = windows[position] >> (WINDOW_BITS - DC_BITS)
            if value == END_OF_PICTURE:
                break
            position += DC_BITS
            dc[block] = _signed(value)
            place = block * BLOCK_VALUES
            last = place + BLOCK_VALUES - 1
            while True:
                used, run, level = table[windows[position]]
                position += used
                if run < 0:
                    if run == RUN_END:
                        break
                    if run == RUN_INVALID:
                        raise ArcadeError(f"movie picture: invalid code in block {block}")
                    word = windows[position] >> (WINDOW_BITS - ESCAPE_BITS)
                    position += ESCAPE_BITS
                    run = word >> RUN_SHIFT
                    level = _signed(word & LEVEL_MASK)
                place += run + 1
                if place > last:
                    raise ArcadeError(f"movie picture: block {block} has more than {BLOCK_VALUES} values")
                places.append(place)
                levels.append(level)
    except IndexError:
        raise ArcadeError("movie picture: the stream ends before its last block") from None
    return Codes(quant_scale, np.array(dc, np.int64), np.array(places, np.int64), np.array(levels, np.int64))


def _coefficients(codes: Codes, tables: Tables) -> np.ndarray:
    """(BLOCKS, 64) in raster order: the MDEC's quantisation; the DC has no scale, the others divide
    by 8 towards zero."""
    table_of_block = np.full(BLOCKS, TABLE_LUMA)
    table_of_block[np.arange(BLOCKS) % BLOCKS_PER_MACROBLOCK < CHROMA_BLOCKS] = TABLE_CHROMA
    values = np.zeros((BLOCKS, BLOCK_VALUES), np.int64)
    values[:, 0] = codes.dc * tables.quant[table_of_block, 0]
    block, position = np.divmod(codes.places, BLOCK_VALUES)
    scaled = codes.levels * tables.quant[table_of_block[block], position] * codes.quant_scale
    values[block, ZIGZAG[position]] = np.sign(scaled) * (np.abs(scaled) // QUANT_DIVISOR)
    return values


def _idct(values: np.ndarray, tables: Tables) -> np.ndarray:
    """(BLOCKS, 64) samples from coefficients."""
    # Output (y, x) from input (v, u): the two axes' cosines, multiplied once in fixed point.
    cosines = np.einsum("ux,vy->yxvu", tables.scale, tables.scale) >> COSINE_PRODUCT_SHIFT
    return (values @ cosines.reshape(BLOCK_VALUES, BLOCK_VALUES).T) >> IDCT_SHIFT


def _rgb(samples: np.ndarray) -> np.ndarray:
    """(HEIGHT, WIDTH, 3) bytes from a picture's blocks: the chroma doubled, then the MDEC's matrix."""
    blocks = samples.reshape(MACROBLOCKS, BLOCKS_PER_MACROBLOCK, BLOCK_SIDE, BLOCK_SIDE)
    cr = blocks[:, 0].repeat(2, axis=1).repeat(2, axis=2)
    cb = blocks[:, 1].repeat(2, axis=1).repeat(2, axis=2)
    top = np.concatenate((blocks[:, 2], blocks[:, 3]), axis=2)
    bottom = np.concatenate((blocks[:, 4], blocks[:, 5]), axis=2)
    y = np.concatenate((top, bottom), axis=1)
    pixels = np.stack((
        y + ((RED_CR * cr) >> COLOUR_SHIFT),
        y + ((GREEN_CB * cb) >> COLOUR_SHIFT) + ((GREEN_CR * cr) >> COLOUR_SHIFT),
        y + ((BLUE_CB * cb) >> COLOUR_SHIFT),
    ), axis=-1)
    pixels = np.clip(pixels, SAMPLE_MIN, SAMPLE_MAX) + SAMPLE_OFFSET
    columns = pixels.reshape(COLUMNS, ROWS, MACROBLOCK, MACROBLOCK, 3)
    return columns.transpose(1, 2, 0, 3, 4).reshape(HEIGHT, WIDTH, 3).astype(np.uint8)


def decode(data: bytes, tables: Tables) -> np.ndarray:
    """One file: (HEIGHT, WIDTH, 3) bytes, before the MDEC's 15-bit output drops the low three bits."""
    return _rgb(_idct(_coefficients(read_codes(data), tables), tables))


def shown_file(timer: int, files: int) -> int:
    """The file on the screen at a value of the flow's timer. `FUN_801BE3EC` decodes file `timer`;
    the picture reaches the screen two frames later. Past the last file the game finds no file to
    read, decodes what its buffer still has, and the last picture stays."""
    return min(max(timer - DISPLAY_DELAY, 0), files - 1)


def frame_count(files: int) -> int:
    """The frames of the movie's state: one per value of the flow's timer."""
    return files + TIMER_PAST_FILES


def _encoded_theora(tool: media.FFmpeg, folder: Path, raw: Path, quality: int) -> bytes:
    dest = folder / f"movie_{quality}.ogv"
    tool.run(["-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", f"{WIDTH}x{HEIGHT}", "-framerate", str(MOVIE_FPS),
              "-i", str(raw), "-c:v", media.THEORA, "-q:v", str(quality), "-fflags", "+bitexact", str(dest)])
    return dest.read_bytes()


def _encoded_frames(tool: media.FFmpeg, folder: Path, raw: Path, frames: int) -> bytes:
    """The fallback container: every frame a JPEG, "arriving" at its frame number."""
    tool.run(["-f", "rawvideo", "-pixel_format", "rgb24", "-video_size", f"{WIDTH}x{HEIGHT}", "-framerate", str(MOVIE_FPS),
              "-i", str(raw), "-q:v", str(media.JPEG_QUALITY), str(folder / "%05d.jpg")])
    jpegs = [(folder / f"{i + 1:05d}.jpg").read_bytes() for i in range(frames)]
    return media.frame_container(jpegs, list(range(frames)), MOVIE_FPS)


def convert(arc: ArcadeSet, out: Output, tool: media.FFmpeg) -> None:
    """Writes the movie's files and `movies/movies.json`."""
    files = arc.category(CATEGORY)
    if not files:
        raise ArcadeError("the movie's category has no files")
    tables = tables_of(arc)
    pictures = [decode(data, tables) for data in files]
    frames = frame_count(len(files))
    entry: dict = {"name": NAME, "width": WIDTH, "height": HEIGHT, "fps": MOVIE_FPS, "frame_count": frames,
                   "duration": round(frames / MOVIE_FPS, 3)}
    with tempfile.TemporaryDirectory() as tmp:
        folder = Path(tmp)
        raw = folder / "frames.rgb"
        with raw.open("wb") as f:
            for timer in range(frames):
                f.write(pictures[shown_file(timer, len(files))].tobytes())
        if tool.ogg:
            entry["video"] = [f"{NAME}.{variant}.ogv" for variant in media.THEORA_QUALITIES]
            for variant, quality in media.THEORA_QUALITIES.items():
                out.write(f"movies/{NAME}.{variant}.ogv", _encoded_theora(tool, folder, raw, quality))
        else:
            entry["frames"] = f"{NAME}.bin"
            out.write(f"movies/{NAME}.bin", _encoded_frames(tool, folder, raw, frames))
    out.write_json("movies/movies.json", {NAME: [entry]})
    log.info("arcade: movie of %d pictures, %d frames at %d per second", len(files), frames, MOVIE_FPS)
