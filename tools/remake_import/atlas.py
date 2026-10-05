"""Packs the used regions of texture pages into one atlas and remaps texel coordinates.

Each material (a texture page seen through one CLUT) contributes only the rectangle
its faces use. Regions get an edge-replicated gutter so that filtered sampling does
not bleed into neighbours.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Callable

import numpy as np

import sources

GUTTER = 2
ATLAS_WIDTH = 2048


@dataclass
class Region:
    key: object
    pixels: np.ndarray          # h × w × 4 crop of the page
    u0: int                     # page texel of the crop's top-left corner
    v0: int
    x: int = 0                  # atlas position of the crop (inside the gutter)
    y: int = 0


@dataclass
class Atlas:
    width: int
    height: int
    pixels: np.ndarray
    regions: dict = field(default_factory=dict)

    def uv(self, key: object, u: int, v: int) -> tuple[float, float]:
        """Normalised atlas coordinate of page texel (u, v)'s centre."""
        r = self.regions[key]
        return ((r.x + u - r.u0 + 0.5) / self.width, (r.y + v - r.v0 + 0.5) / self.height)

    def repaint(self, pages: dict) -> np.ndarray:
        """The same layout filled from other page pictures (for example after a VRAM copy)."""
        pixels = np.zeros_like(self.pixels)
        for key, r in self.regions.items():
            h, w = r.pixels.shape[:2]
            _paste(pixels, pages[key][r.v0:r.v0 + h, r.u0:r.u0 + w], r.x, r.y)
        return pixels


def used_rect(uvs: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    us = [u for u, _ in uvs]
    vs = [v for _, v in uvs]
    return min(us), min(vs), max(us) + 1, max(vs) + 1


def build(pages: dict, used: dict, wrapped: frozenset = frozenset()) -> Atlas:
    """`pages`: key → 256 × 256 × 4 page picture; `used`: key → list of (u, v) texels. The
    regions of the `wrapped` keys repeat (a GPU texture window): their gutter wraps around."""
    regions = []
    for key, page in pages.items():
        u0, v0, u1, v1 = used_rect(used[key])
        regions.append(Region(key, page[v0:v1, u0:u1], u0, v0))
    # Shelf packing, tallest first.
    regions.sort(key=lambda r: (-r.pixels.shape[0], -r.pixels.shape[1], str(r.key)))
    x = y = shelf = 0
    for r in regions:
        h, w = r.pixels.shape[0] + 2 * GUTTER, r.pixels.shape[1] + 2 * GUTTER
        if x + w > ATLAS_WIDTH:
            x, y, shelf = 0, y + shelf, 0
        r.x, r.y = x + GUTTER, y + GUTTER
        x += w
        shelf = max(shelf, h)
    height = 1
    while height < y + shelf:
        height *= 2
    width = ATLAS_WIDTH
    while width > 256 and all(r.x + r.pixels.shape[1] + GUTTER <= width // 2 for r in regions):
        width //= 2
    pixels = np.zeros((height, width, 4), dtype=np.uint8)
    for r in regions:
        _paste(pixels, r.pixels, r.x, r.y, "wrap" if r.key in wrapped else "edge")
    return Atlas(width, height, pixels, {r.key: r for r in regions})


def record_sources(out, rel: str, packed: Atlas, vram, page_of: Callable[[object], tuple | None]) -> None:
    """Records the atlas's regions as VRAM pieces (sources.py); `page_of(key)` gives a region's
    (page x, page y, depth, CLUT x, CLUT y), or None for a region not cut from VRAM."""
    for key, r in packed.regions.items():
        page = page_of(key)
        if page is not None:
            h, w = r.pixels.shape[:2]
            page_x, page_y, depth, clut_x, clut_y = page
            sources.page_piece(out, rel, r.x, r.y, vram, page_x, page_y, depth, r.u0, r.v0, w, h, clut_x, clut_y,
                               pad=GUTTER)


def _paste(pixels: np.ndarray, crop: np.ndarray, x: int, y: int, mode: str = "edge") -> None:
    """Writes a crop at (x, y) with its gutter: edge-replicated, or wrapped around for a region
    that repeats."""
    padded = np.pad(crop, ((GUTTER, GUTTER), (GUTTER, GUTTER), (0, 0)), mode=mode)
    pixels[y - GUTTER:y - GUTTER + padded.shape[0], x - GUTTER:x - GUTTER + padded.shape[1]] = padded
