"""The ending movies' captions (formats/sound-and-video.md, "Movie captions") → pictures and timelines.

Four endings draw text captions into their decoded frames (ending.ovl, FUN_8010F3F8). The tables
are found in a release's own ending.ovl by their shape, as tools/research/movie_captions.py finds them,
so the Japanese captions and the USA ones (other texts, other timings) each come from their disc.

`<folder>/captions.json`:
- "captions": per caption its picture (`captions/<n>.png`, relative to the file) and its place
  in the movie's pixels from the picture's top-left corner (x, y);
- "sets": per caption set (1 the first; Japan has four, USA five) the changes [STR frame,
  caption] (caption −1: none), as FUN_8010F0B4 shows them: from that decoded frame on;
- "movies": per movie of ending.ovl's list the caption set its descriptor names (0 none). The
  releases list the same movies in the same order but caption different ones (USA drops Julia's
  dialogue and captions others).

A picture is RGBA: palette index 0 is transparent, a plain entry replaces the movie's pixel, and a
blended entry (((movie >> 1) + colour) >> 1) becomes alpha 0.75 with the colour · 2/3, which
composites over the movie to the same.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

import numpy as np

from common import Block, Output
from vram import png_bytes

RECORD_SIGNATURE = struct.pack("<I8h", 0, 0, 170, 0, 256, 44, 128, 0, 0)   # the first caption record
RECORD_SIZE = 0x14
BLIT_SIGNATURE = bytes.fromhex("8220040040200400")   # srl a0,a0,2; sll a0,a0,1 in the caption blit
TIMELINE_END = 0xFFFF
SET_START = (0, -1)              # every set begins with this entry
PALETTE_ENTRY = 8                # r, g, b, blend flag, 4 unused
PALETTE_SIZE = 16 * PALETTE_ENTRY
PALETTE_ORDER = {0: 0, 2: 1, 3: 2}   # a record's palette index → its table after the timeline
BLENDED_ALPHA = 191              # 0.75
OPAQUE = 255


class CaptionError(Exception):
    """The ending overlay has no caption tables of the expected shape."""


@dataclass
class Caption:
    x: int
    y: int
    pixels: np.ndarray           # RGBA, height × width × 4


def read(ending: Block) -> tuple[list[Caption], list[list[list[int]]]]:
    """The captions of a release's own ending overlay and each set's changes [frame, caption]."""
    data = ending.data
    at = data.find(RECORD_SIGNATURE)
    blit = data.find(BLIT_SIGNATURE)
    if at < 0 or blit < 4:
        raise CaptionError("no caption tables in ending.ovl")
    records = []
    while True:
        here = at + RECORD_SIZE * len(records)
        if here + 4 <= len(data) and struct.unpack_from("<Hh", data, here) == SET_START:
            break                                                  # the timeline follows the records
        if here + RECORD_SIZE > len(data):
            raise CaptionError("the caption records run past ending.ovl")
        records.append(struct.unpack_from("<I8h", data, here))
    timeline = at + RECORD_SIZE * len(records)
    # The sets follow each other, each closed by TIMELINE_END; the palettes follow the last.
    entries: list[tuple[int, int]] = []
    while True:
        if timeline + 4 * (len(entries) + 2) > len(data):
            raise CaptionError("the caption timeline runs past ending.ovl")
        frame, caption = struct.unpack_from("<Hh", data, timeline + 4 * len(entries))
        entries.append((frame, caption))
        if frame == TIMELINE_END and struct.unpack_from("<Hh", data, timeline + 4 * len(entries)) != SET_START:
            break
    palettes = timeline + 4 * len(entries)
    # lui v1, hi (the delay slot before the signature); lw v1, lo(v1): the bitmaps' base pointer.
    hi = struct.unpack_from("<I", data, blit - 4)[0] & 0xFFFF
    lo = struct.unpack_from("<h", data, blit + 12)[0]
    bitmaps = ending.u32((hi << 16) + lo & 0xFFFFFFFF)
    if bitmaps is None or not ending.contains(bitmaps):
        raise CaptionError("the caption bitmaps are outside ending.ovl")
    captions = [_caption(data, bitmaps - ending.base, palettes, r) for r in records]
    return captions, _sets(entries)


def _caption(data: bytes, bitmaps: int, palettes: int, record: tuple) -> Caption:
    offset, x, y, _first, width, height, _stride, palette, _ = record
    raw = np.frombuffer(data, dtype=np.uint8, count=width * height // 2, offset=bitmaps + offset)
    index = np.empty(width * height, dtype=np.uint8)
    index[0::2] = raw & 0xF
    index[1::2] = raw >> 4
    table = np.frombuffer(data, dtype=np.uint8, count=PALETTE_SIZE,
                          offset=palettes + PALETTE_SIZE * PALETTE_ORDER[palette]).reshape(16, PALETTE_ENTRY)
    colours = np.zeros((16, 4), dtype=np.uint8)
    for k in range(1, 16):
        r, g, b, blend = (int(v) for v in table[k, :4])
        colours[k] = [r * 2 // 3, g * 2 // 3, b * 2 // 3, BLENDED_ALPHA] if blend else [r, g, b, OPAQUE]
    return Caption(x, y, colours[index].reshape(height, width, 4))


def _sets(entries: list[tuple[int, int]]) -> list[list[list[int]]]:
    """Each set's changes: for every decoded frame n ≥ 1 FUN_8010F0B4 scans the set from its start
    to the first entry whose frame is not below n and shows the caption before it."""
    starts = [k for k, (frame, _) in enumerate(entries) if frame == 0]
    sets = []
    for start in starts:
        end = next(k for k in range(start, len(entries)) if entries[k][0] == TIMELINE_END)
        last = max(frame for frame, _ in entries[start:end]) + 1
        changes, shown = [], entries[start][1]
        for n in range(1, last + 1):
            pos = start + 1
            while entries[pos][0] < n:
                pos += 1
            caption = entries[pos - 1][1]
            if caption != shown:
                changes.append([n, caption])
                shown = caption
        sets.append(changes)
    return sets


def write(ending: Block, movies: list[int], out: Output, folder: str) -> int:
    """`<folder>/captions.json` and the pictures, with `movies` (the caption set of each movie of
    the same release's list); returns the number of captions."""
    captions, sets = read(ending)
    listed = []
    for n, c in enumerate(captions):
        name = f"captions/{n:02d}.png"
        out.write(f"{folder}/{name}", png_bytes(c.pixels))
        listed.append({"picture": name, "x": c.x, "y": c.y})
    out.write_json(f"{folder}/captions.json", {"captions": listed, "sets": sets, "movies": movies})
    return len(captions)
