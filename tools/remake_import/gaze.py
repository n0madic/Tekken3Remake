"""Gon's eyes' look direction as texture patches (docs/research/formats/3dmk-models.md).

Gon's pupils follow the opponent by shifting the texture strips of his eyes in VRAM. When a fight
is set up FUN_8003401C saves each eye's 64-row strip next to the texture page (a MoveImage), and
GonEyesSetOffset (0x80034120) copies 34 rows of the saved strip, from a row that depends on the
shift, over the strip's rows in the page: eye 0 takes the shifts 0 to 17 (strip row 17 ← saved row
8 + shift), eye 1 the shifts 0 to −17 (strip row 13 ← saved row 21 + shift); the opponent's
direction is turned into the shift by FighterAnimation.gon_gaze. With the shifts 9 and −8 the copy
is the strip as it was, and an eye that was never copied shows the strip as loaded.

The atlas of each state would be a picture of its own, so the converter writes only what differs
from the unshifted atlas: per palette (the swapped head palette changes what the strips show, see
character.palette_swap) and eye, the rectangles that any shift changes, cut from the atlas of each
shift and packed into one sheet (`texture_gaze.png`). The remake pastes them over its atlas.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass

import numpy as np

from common import Disc
from vram import Vram, png_bytes

GON = 0x11                          # character id
TABLE = 0x80095CE0                  # 6 × s8 per costume slot (see `layout`)
EYE_RECTS = 0x80095BC0              # (x, y) s16 VRAM positions
EYE_SIZES = 0x80095C90              # (w, h) s16 in VRAM words
# Per eye: the saved strip's row offset (added to the shift) and the strip's row the copy lands at
# (GonEyesSetOffset: eye 0 adds 8 and 0x11, eye 1 0x15 and 0xD), and the shifts the eye gets.
SOURCE_ROWS = (8, 21)
DEST_ROWS = (17, 13)
SHIFTS = (range(0, 18), range(-17, 1))
EYES = 2
TILE = 8                            # patch rectangles are made of tiles of this many atlas pixels
SHEET = "texture_gaze"
SHEET_WIDTH = 1024


@dataclass(frozen=True)
class Eye:
    strip: tuple[int, int]          # the strip in the texture page: VRAM x, y
    saved: tuple[int, int]          # its saved copy


@dataclass(frozen=True)
class Layout:
    strip_size: tuple[int, int]     # w, h in VRAM words
    window_size: tuple[int, int]    # the rows a shift copies
    eyes: tuple[Eye, Eye]


def layout(disc: Disc, costume_characters: set[int], slot: int) -> Layout | None:
    """The eye strips of a costume slot of Gon (table 0x80095CE0: strip size, window size, the two
    strips, their saved copies), None for any other character."""
    if GON not in costume_characters:
        return None
    size, window, strip0, strip1, saved0, saved1 = (b - 256 if b > 127 else b for b in disc.exe_u8(TABLE + 6 * slot, 6))

    def rect(index: int) -> tuple[int, int]:
        x, y = disc.exe_s16(EYE_RECTS + 4 * index, 2)
        return x, y

    def rect_size(index: int) -> tuple[int, int]:
        w, h = disc.exe_s16(EYE_SIZES + 4 * index, 2)
        return w, h

    return Layout(rect_size(size), rect_size(window),
                  (Eye(rect(strip0), rect(saved0)), Eye(rect(strip1), rect(saved1))))


def with_saves(where: Layout, vram: Vram) -> Vram:
    """The VRAM once FUN_8003401C has saved the strips."""
    saved = vram.copy()
    w, h = where.strip_size
    for eye in where.eyes:
        saved.move_image(*eye.strip, w, h, *eye.saved)
    return saved


def shifted(where: Layout, saved: Vram, eye: int, shift: int) -> Vram:
    """`saved` (with_saves) after GonEyesSetOffset has copied the window of `eye`'s saved strip for
    `shift` over its strip."""
    w, h = where.window_size
    e = where.eyes[eye]
    shown = saved.copy()
    shown.move_image(e.saved[0], e.saved[1] + SOURCE_ROWS[eye] + shift, w, h,
                     e.strip[0], e.strip[1] + DEST_ROWS[eye])
    return shown


def tile_rects(mask: np.ndarray) -> list[tuple[int, int, int, int]]:
    """Rectangles (x, y, w, h) of whole tiles that cover the True pixels of `mask`: runs of tiles in
    a row, merged with the identical runs of the rows below."""
    height, width = mask.shape
    rows, cols = -(-height // TILE), -(-width // TILE)
    padded = np.zeros((rows * TILE, cols * TILE), dtype=bool)
    padded[:height, :width] = mask
    tiles = padded.reshape(rows, TILE, cols, TILE).any(axis=(1, 3))
    rects: list[tuple[int, int, int, int]] = []
    active: dict[tuple[int, int], int] = {}
    for row in range(rows + 1):
        runs: set[tuple[int, int]] = set()
        if row < rows:
            x = 0
            while x < cols:
                if tiles[row, x]:
                    end = x
                    while end < cols and tiles[row, end]:
                        end += 1
                    runs.add((x, end))
                    x = end
                else:
                    x += 1
        for run, start in active.items():
            if run not in runs:
                rects.append((run[0] * TILE, start * TILE, (run[1] - run[0]) * TILE, (row - start) * TILE))
        active = {run: active.get(run, row) for run in runs}
    return [(x, y, min(w, width - x), min(h, height - y)) for x, y, w, h in rects]


def patches(where: Layout, saved: Vram, repaint: Callable[[Vram], np.ndarray]
            ) -> dict[tuple[int, int], tuple[list[tuple[int, int, int, int]], dict[int, list[np.ndarray]]]]:
    """Per eye and per state of `saved` (the VRAM with the strips saved, and the swapped palette or
    not): the rectangles of the atlas that any shift changes, and for each shift their pictures.
    `repaint` turns a VRAM into the atlas picture. Keys (eye, 0), values (rects, {shift: crops})."""
    base = repaint(saved)
    out = {}
    for eye in range(EYES):
        pictures = {shift: repaint(shifted(where, saved, eye, shift)) for shift in SHIFTS[eye]}
        mask = np.zeros(base.shape[:2], dtype=bool)
        for picture in pictures.values():
            mask |= (picture != base).any(axis=2)
        rects = tile_rects(mask)
        out[(eye, 0)] = (rects, {shift: [p[y:y + h, x:x + w] for x, y, w, h in rects]
                                 for shift, p in pictures.items()})
    return out


def overlap(a: list[tuple[int, int, int, int]], b: list[tuple[int, int, int, int]]) -> bool:
    return any(ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah
               for ax, ay, aw, ah in a for bx, by, bw, bh in b)


def sheet(pictures: list[np.ndarray]) -> tuple[np.ndarray, list[tuple[int, int]]]:
    """Shelf-packs the pictures into a sheet SHEET_WIDTH wide; returns it and each one's position."""
    order = sorted(range(len(pictures)), key=lambda i: (-pictures[i].shape[0], -pictures[i].shape[1], i))
    where: dict[int, tuple[int, int]] = {}
    x = y = shelf = 0
    for i in order:
        h, w = pictures[i].shape[:2]
        if w > SHEET_WIDTH:
            raise ValueError(f"a patch {w} pixels wide does not fit the sheet ({SHEET_WIDTH}): GazeAtlas reads that width")
        if x + w > SHEET_WIDTH:
            x, y, shelf = 0, y + shelf, 0
        where[i] = (x, y)
        x += w
        shelf = max(shelf, h)
    pixels = np.zeros((max(y + shelf, 1), SHEET_WIDTH, 4), dtype=np.uint8)
    for i, (px, py) in where.items():
        h, w = pictures[i].shape[:2]
        pixels[py:py + h, px:px + w] = pictures[i]
    return pixels, [where[i] for i in range(len(pictures))]


def write(out, base: str, where: Layout, vrams: dict[bool, Vram], repaint: Callable[[Vram], np.ndarray],
          size: tuple[int, int]) -> dict:
    """Writes `base`/texture_gaze.png and returns model.json's "gaze": the atlas `size`, the sheet, and
    per palette (`vrams`: swapped or not → the VRAM with the strips saved) and eye the rectangles of
    the atlas and, per shift, where in the sheet each one's picture is: {swapped: {eye: {"rects":
    [[x, y, w, h]], "shifts": {shift: [[sheet x, sheet y]]}}}} (keys as text)."""
    pictures: list[np.ndarray] = []
    layout_of: dict[tuple[int, int], tuple[list, dict[int, list[int]]]] = {}
    for swapped, saved in vrams.items():
        found = patches(where, saved, repaint)
        if overlap(found[(0, 0)][0], found[(1, 0)][0]):
            raise ValueError("the eyes' patches overlap")
        for (eye, _), (rects, by_shift) in found.items():
            if not rects:
                continue
            first = {}
            for shift, crops in by_shift.items():
                first[shift] = len(pictures)
                pictures.extend(crops)
            layout_of[(int(swapped), eye)] = (rects, first)
    pixels, positions = sheet(pictures)
    out.write(f"{base}/{SHEET}.png", png_bytes(pixels))
    patches_json: dict[str, dict[str, dict]] = {}
    for (swapped, eye), (rects, first) in layout_of.items():
        patches_json.setdefault(str(swapped), {})[str(eye)] = {
            "rects": [list(r) for r in rects],
            "shifts": {str(shift): [list(positions[start + k]) for k in range(len(rects))]
                       for shift, start in first.items()},
        }
    return {"size": list(size), "sheet": f"{SHEET}.png", "patches": patches_json}
