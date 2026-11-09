"""The arcade effect objects' drawing (docs/research/arcade/audio-and-effects.md#4-effect-objects) →
`effects/arcade_object_page.png`, `effects/arcade_object_palettes.png` and the `objects` block of
`effects/effects.json`, which `EffectObjectsView` draws.

`FUN_801dbc9c` loads category 42's members 0–5 (4-bit TIMs without rectangles) into two texture
pages and member 6's CLUT alone; the cloud reads the dust flipbook (category 22, the dust record's
set) where `FUN_801af068` uploads it, on two more pages. Each type routine sets its primitives'
page and CLUT once, so both follow the UV table (`ArcadeEffectObjects.Book`) a phase shows; only the
cloud picks its page per frame (`0x8017C8A8`). The objects' pages blend additively (`LoadTPage`
abr 1) and the cloud's at 50 % (`GetTPage` abr 0).

The four pages go side by side into one atlas of indices (value = index, as the PlayStation's
object page), so the UV tables' frames are atlas positions.
"""

from __future__ import annotations

import struct

import numpy as np

import arcade
import arcade_effects
from common import Output
from vram import png_bytes, rgba, tim_sequence, unpack_indices

CATEGORY = 42
TIM_HEADER = 8
BLOCK_HEADER = 12
CLUT_COLOURS = 16
PAGE = 256                              # texels per side of a 4-bit texture page
# Pages by their index in the tpage words from 0x8036EA5C (the cloud's per-frame table counts from
# there): the objects' two, then the dust upload's two. Atlas origin of each, in texels.
PAGE_ORIGINS = ((0, 0), (PAGE, 0), (0, PAGE), (PAGE, PAGE))
ATLAS = 2 * PAGE
# Members 0–5: (page, texel x, y in the page) from FUN_801dbc9c's LoadTPage calls; member 6 is a CLUT.
MEMBERS = ((0, 0, 0), (0, 0x80, 0), (0, 0, 0x40), (0, 0, 0x80), (1, 0, 0), (0, 0, 0xC0))
PALETTES = 7
CLOUD_PALETTE = 6
DUST_PAGE = 2                           # the dust upload's first page (VRAM 0x380, 0x300)
DUST_FRAME = 64
DUST_PER_PAGE = 16                      # 4 × 4 frames per 64-word column (FUN_801af068)
DUST_PER_ROW = 4
# The quad models by EffectObjects.Model (0 none; FLAME, BURN_GON, GAS and BALL have none here).
MODELS = {1: 0x8017C63C, 2: 0x8017C6A0, 3: 0x8017C6E4, 4: 0x8017C744, 5: 0x8017C764, 6: 0x8017C784,
          7: 0x8017C7DC, 10: 0x8017C83C, 11: 0x8017C85C, 12: 0x8017C764, 14: 0x8017C958}
MODEL_COUNT = 18
CORNERS = 4
SVECTOR_BYTES = 8
# The UV tables in ArcadeEffectObjects.Book order (from 1): address, frames, cell size, page,
# palette (category 42 member), 50 % blending. The cloud's page is per frame.
UV_TABLES = (
    (0x8017C5F8, 32, 16, 0, 0, False),   # SPARK
    (0x8017C914, 32, 16, 0, 1, False),   # POWER_SPARK
    (0x8017C65C, 8, 16, 0, 1, False),    # GLOW
    (0x8017C6C4, 16, 16, 0, 1, False),   # RISE
    (0x8017C704, 32, 16, 0, 1, False),   # EMBER
    (0x8017C7A4, 8, 64, 1, 4, False),    # FIRE_GROW
    (0x8017C7B4, 8, 64, 1, 4, False),    # FIRE_LOOP
    (0x8017C7C4, 8, 32, 0, 5, False),    # FIRE_BURST
    (0x8017C7FC, 16, 32, 0, 2, False),   # FLOOR_FIRE
    (0x8017C81C, 16, 32, 0, 3, False),   # FLOOR_FADE
    (0x8017C87C, 21, 64, None, CLOUD_PALETTE, True),  # CLOUD
)
CLOUD_PAGES = 0x8017C8A8                # u32 page index per cloud frame


def _member(arc: arcade.ArcadeSet, index: int) -> tuple[np.ndarray, np.ndarray | None]:
    """A member's 16 CLUT colours and, unless it has none, its texel indices."""
    data, _ = arcade.decompress(arc.category(CATEGORY)[index])
    clut_bytes = struct.unpack_from("<I", data, TIM_HEADER)[0]
    clut = np.frombuffer(data, dtype="<u2", count=CLUT_COLOURS, offset=TIM_HEADER + BLOCK_HEADER).copy()
    image = TIM_HEADER + clut_bytes
    if image + BLOCK_HEADER > len(data):
        return clut, None
    w, h = struct.unpack_from("<2H", data, image + 8)
    if w * h == 0:
        return clut, None
    words = np.frombuffer(data, dtype="<u2", count=w * h, offset=image + BLOCK_HEADER).reshape(h, w)
    return clut, unpack_indices(words, 4).astype(np.uint8)


def _place(atlas: np.ndarray, page: int, x: int, y: int, indices: np.ndarray) -> None:
    ox, oy = PAGE_ORIGINS[page]
    h, w = indices.shape
    if x + w > PAGE or y + h > PAGE:
        raise arcade.ArcadeError(f"an effect picture of {w} × {h} at ({x}, {y}) leaves its page")
    atlas[oy + y:oy + y + h, ox + x:ox + x + w] = indices


def _dust(arc: arcade.ArcadeSet, atlas: np.ndarray) -> None:
    """The dust flipbook's frames where its upload walk puts them, row by row in 4 × 4 per page."""
    number = arc.prog_values(arcade_effects.RECORD, arcade_effects.SYSTEM_RECORDS[-1])[0]
    tims, _ = tim_sequence(arcade.decompress(arc.category(arcade_effects.CATEGORY)[number])[0])
    for n, tim in enumerate(tims[:DUST_PER_PAGE * 2]):
        k = n % DUST_PER_PAGE
        x, y = DUST_FRAME * (k % DUST_PER_ROW), DUST_FRAME * (k // DUST_PER_ROW)
        _place(atlas, DUST_PAGE + n // DUST_PER_PAGE, x, y, unpack_indices(arcade_effects.frame_blocks(tim)[1], 4))


def drawing(arc: arcade.ArcadeSet, out: Output) -> dict:
    """Writes the atlas and palettes; returns the `objects` block for `effects/effects.json`."""
    atlas = np.zeros((ATLAS, ATLAS), dtype=np.uint8)
    palettes = np.zeros((PALETTES, CLUT_COLOURS, 4), dtype=np.uint8)
    for index in range(PALETTES):
        clut, indices = _member(arc, index)
        palettes[index] = rgba(clut)
        if index < len(MEMBERS):
            if indices is None:
                raise arcade.ArcadeError(f"effect page member {index} has no picture")
            _place(atlas, *MEMBERS[index], indices)
    _dust(arc, atlas)
    page = np.zeros((ATLAS, ATLAS, 4), dtype=np.uint8)
    page[..., 0] = atlas
    page[..., 3] = 255
    out.write("effects/arcade_object_page.png", png_bytes(page))
    out.write("effects/arcade_object_palettes.png", png_bytes(palettes))
    quads: list[list] = [[] for _ in range(MODEL_COUNT)]
    for model, address in MODELS.items():
        quads[model] = [list(arc.prog_values("<2h", address + SVECTOR_BYTES * k)) for k in range(CORNERS)]
    cloud_pages = list(arc.prog_values(f"<{UV_TABLES[-1][1]}I", CLOUD_PAGES))
    tables = []
    for address, count, size, page_index, palette, half in UV_TABLES:
        frames = []
        for k in range(count):
            u, v = arc.prog(address + 2 * k, 2)
            ox, oy = PAGE_ORIGINS[cloud_pages[k] if page_index is None else page_index]
            frames.append([ox + u, oy + v])
        tables.append({"size": size, "frames": frames, "palette": palette, "half": half})
    return {"page": "arcade_object_page.png", "palettes": "arcade_object_palettes.png",
            "quads": quads, "uv_tables": tables}
