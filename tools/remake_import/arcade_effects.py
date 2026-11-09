"""The arcade's effect flipbooks (MAME's tekken3 set) → strips of 64 × 64 frames.

The arcade draws the same flipbooks as the PlayStation at twice the resolution and the same world
size (docs/research/arcade/README.md#effect-flipbooks): the PlayStation's 32 × 32 frames are these
reduced, the character sets frame for frame, the system sets with fewer frames. `FUN_801ac680` loads
them by a record per character and per system index (the PlayStation's sets 0–1 and 3).

A set is a TIM per frame (category 22, compressed), all through the first TIM's CLUT, whose
colours `FUN_801af068` multiplies by the record's factors. The same routine can exchange a
palette's red and green (the record's last word, under the setting `0x8021FBBC`); that is not done
here: the PlayStation's colours are those of the unchanged palette (`inferred`, by comparison,
tools/research/compare_arcade_flipbooks.py).
"""

from __future__ import annotations

import struct

import numpy as np

import arcade
import system_textures
from common import log
from vram import rgba, tim_sequence, unpack_indices

CATEGORY = 22
# Records (0x18 bytes, read as RECORD: set, frames, width, height, additive, R, G, B factors of 128):
# one per charId, and the system sets hit, hit without damage, guard, dust (FUN_801ac680 loads the
# dust from its own record, not the fourth of the table).
CHARACTER_RECORDS = 0x80175510
CHARACTER_RECORD_BYTES = 0x18
SYSTEM_RECORDS = (0x80175720, 0x80175738, 0x80175750, 0x80175798)
RECORD = "<I4h3h"
RECORD_LIGHT = 0x14                     # R, G, B of the character's dynamic light
FACTOR_SHIFT = 7
# The PlayStation's charId 19 (costume slots 44, 45) is not the arcade's: its flipbook is the Mishima
# lightning, as charId 9's; the arcade's record 19 holds another character's set.
CHARACTER_RECORD_OF = {19: 9}
FRAME = 64
FRAME_WORDS = FRAME // 4
CLUT_COLOURS = 16


def tint(palette: np.ndarray, factors: tuple[int, int, int]) -> np.ndarray:
    """FUN_801af068's palette: each channel times its factor / 128, clamped; colour 0 (transparent)
    stays, and a colour that becomes black is kept from turning transparent."""
    channels = [np.minimum((((palette.astype(np.int32) >> shift) & 0x1F) * factor) >> FACTOR_SHIFT, 0x1F)
                for shift, factor in zip((0, 5, 10), factors)]
    out = (palette & 0x8000) | channels[0] | channels[1] << 5 | channels[2] << 10
    out[out & 0x7FFF == 0] |= 0x400
    out[palette == 0] = 0
    return out.astype(np.uint16)


def clut_and_words(tim: bytes) -> tuple[np.ndarray, np.ndarray | None]:
    """A 4-bit TIM's 16 CLUT colours and pixel words, None without pixels (the rectangles are
    the uploader's to place)."""
    blocks = {kind: (w, h, data) for kind, _, _, w, h, data in system_textures.tim_blocks(tim)}
    if "clut" not in blocks:
        raise arcade.ArcadeError("an effect TIM without a CLUT")
    clut = np.frombuffer(blocks["clut"][2], dtype="<u2", count=CLUT_COLOURS)
    w, h, data = blocks.get("image", (0, 0, b""))
    if w * h == 0:
        return clut, None
    return clut, np.frombuffer(data, dtype="<u2", count=w * h).reshape(h, w)


def frame_blocks(tim: bytes) -> tuple[np.ndarray, np.ndarray]:
    """A flipbook frame TIM's CLUT colours and its 16 × 64 pixel words."""
    clut, words = clut_and_words(tim)
    if words is None or words.shape != (FRAME, FRAME_WORDS):
        size = "no" if words is None else f"{words.shape[1]} × {words.shape[0]}"
        raise arcade.ArcadeError(f"a flipbook frame of {size} words")
    return clut, words


def flipbook(arc: arcade.ArcadeSet, record: int) -> tuple[np.ndarray, int]:
    """The RGBA strip (frames left to right) and frame count of the set a record names."""
    number, frames, _, _, _, *factors = arc.prog_values(RECORD, record)
    sets = arc.category(CATEGORY)
    if number >= len(sets):
        raise arcade.ArcadeError(f"flipbook set {number} of {len(sets)}")
    tims, _ = tim_sequence(arcade.decompress(sets[number])[0])
    if len(tims) < frames:
        raise arcade.ArcadeError(f"flipbook set {number}: {len(tims)} frames of {frames}")
    palette = tint(frame_blocks(tims[0])[0], tuple(factors))
    strip = np.zeros((FRAME, FRAME * frames, 4), dtype=np.uint8)
    for n, tim in enumerate(tims[:frames]):
        strip[:, FRAME * n:FRAME * (n + 1)] = rgba(palette[unpack_indices(frame_blocks(tim)[1], 4)])
    return strip, frames


def character_record(char_id: int) -> int:
    return CHARACTER_RECORDS + CHARACTER_RECORD_BYTES * CHARACTER_RECORD_OF.get(char_id, char_id)


def light_of(arc: arcade.ArcadeSet, char_id: int) -> list[int]:
    """The dynamic light of a character's flipbook (the same colours as the PlayStation's records)."""
    return list(arc.prog(character_record(char_id) + RECORD_LIGHT, 3))


def flipbook_or_none(arc: arcade.ArcadeSet | None, record: int, name: str) -> tuple[np.ndarray, int] | None:
    """`flipbook`, or None to keep the PlayStation's: without a set, or with a logged reason."""
    if arc is None:
        return None
    try:
        return flipbook(arc, record)
    except (arcade.ArcadeError, struct.error, ValueError, IndexError) as e:
        log.error("arcade: flipbook %s: %s; the PlayStation's is kept", name, e)
        return None
