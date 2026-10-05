"""A PlayStation VRAM image for resolving texture pages and CLUTs into RGBA pictures."""

from __future__ import annotations

import io
import struct

import numpy as np
from PIL import Image

VRAM_W = 1024
VRAM_H = 512
TIM_ID = 0x10
BLOCK_HEADER = 12              # u32 length, u16 x, y, w, h


def tim_sequence(data: bytes, offset: int = 0) -> tuple[list[bytes], int]:
    """Consecutive standard TIMs from `offset`; returns them and the end offset."""
    tims = []
    while offset + 8 <= len(data) and struct.unpack_from("<I", data, offset)[0] == TIM_ID:
        flags = struct.unpack_from("<I", data, offset + 4)[0]
        cursor = offset + 8
        for _ in range(2 if flags & 8 else 1):
            cursor += struct.unpack_from("<I", data, cursor)[0]
        tims.append(data[offset:cursor])
        offset = cursor
    return tims, offset


class Vram:
    def __init__(self, height: int = VRAM_H) -> None:
        """`height`: 512 rows (the PlayStation) or 1,024 (the arcade's System 12)."""
        self.words = np.zeros((height, VRAM_W), dtype=np.uint16)

    def upload_tim(self, tim: bytes, dx: int = 0, dy: int = 0, clut_dx: int = 0, clut_dy: int = 0) -> None:
        """LoadImage of a TIM's CLUT and pixel blocks, shifted like the game's uploaders."""
        flags = struct.unpack_from("<I", tim, 4)[0]
        cursor = 8
        blocks = (["clut"] if flags & 8 else []) + ["image"]
        for kind in blocks:
            length = struct.unpack_from("<I", tim, cursor)[0]
            if length < BLOCK_HEADER:
                # Gon's CLUT-only TIMs (costume slots 42, 43) end with an empty pixel block.
                cursor += length
                continue
            x, y, w, h = struct.unpack_from("<4H", tim, cursor + 4)
            pixels = np.frombuffer(tim, dtype="<u2", count=w * h, offset=cursor + 12).reshape(h, w)
            if kind == "clut":
                x, y = x + clut_dx, y + clut_dy
            else:
                x, y = x + dx, y + dy
            self.words[y:y + h, x:x + w] = pixels
            cursor += length

    def move_image(self, x: int, y: int, w: int, h: int, dx: int, dy: int) -> None:
        """MoveImage: copies a rectangle of VRAM words."""
        self.words[dy:dy + h, dx:dx + w] = self.words[y:y + h, x:x + w].copy()

    def copy(self) -> "Vram":
        other = Vram(self.words.shape[0])
        other.words = self.words.copy()
        return other

    def clut(self, x: int, y: int, count: int) -> np.ndarray:
        return self.words[y, x:x + count]

    def page_indices(self, page_x: int, page_y: int, depth: int) -> np.ndarray:
        """256 × 256 texel indices of a 4-bit or 8-bit texture page."""
        return unpack_indices(self.words[page_y:page_y + 256, page_x:page_x + 256 // (16 // depth)], depth)

    def page_rgba(self, page_x: int, page_y: int, depth: int, clut_x: int, clut_y: int) -> np.ndarray:
        """RGBA picture of a page through a CLUT. Colour 0x0000 is transparent, as on the GPU."""
        indices = self.page_indices(page_x, page_y, depth)
        colours = self.clut(clut_x, clut_y, 1 << depth)[indices]
        return rgba(colours)


def tpage_xy(tpage: int) -> tuple[int, int]:
    """The VRAM word position of a texture page from a tpage word's page bits."""
    return 64 * (tpage & 0x0F), 256 * ((tpage >> 4) & 1)


def clut_xy(clut: int) -> tuple[int, int]:
    """The VRAM word position of a CLUT from its id (x / 16 | y << 6)."""
    return 16 * (clut & 0x3F), (clut >> 6) & 0x1FF


def atlas_planes(pixel_data: bytes, w: int, h: int) -> np.ndarray:
    """The four bit planes of a 4-bit atlas (`w` words × `h` rows) one under the other, white
    where the bit is set."""
    words = np.frombuffer(pixel_data, dtype="<u2", count=w * h).reshape(h, w)
    texels = np.stack([(words >> (4 * k)) & 0xF for k in range(4)], axis=-1).reshape(h, 4 * w)
    planes = np.concatenate([(texels >> p) & 1 for p in range(4)], axis=0).astype(np.uint8)
    pixels = np.zeros(planes.shape + (4,), dtype=np.uint8)
    pixels[..., :3] = 255
    pixels[..., 3] = planes * 255
    return pixels


def unpack_indices(words: np.ndarray, depth: int) -> np.ndarray:
    """The texel indices of a block of 4-bit or 8-bit VRAM words (lowest bits first)."""
    per_word = 16 // depth
    words = words.astype(np.uint32)
    out = np.zeros((words.shape[0], words.shape[1] * per_word), dtype=np.uint32)
    mask = (1 << depth) - 1
    for k in range(per_word):
        out[:, k::per_word] = (words >> (depth * k)) & mask
    return out


def rgba(colours: np.ndarray) -> np.ndarray:
    c = colours.astype(np.uint32)
    out = np.zeros(c.shape + (4,), dtype=np.uint8)
    out[..., 0] = ((c & 31) << 3) | ((c & 31) >> 2)
    out[..., 1] = (((c >> 5) & 31) << 3) | (((c >> 5) & 31) >> 2)
    out[..., 2] = (((c >> 10) & 31) << 3) | (((c >> 10) & 31) >> 2)
    out[..., 3] = np.where(c == 0, 0, 255)
    return out


def png_bytes(pixels: np.ndarray) -> bytes:
    buffer = io.BytesIO()
    Image.fromarray(pixels, "RGBA").save(buffer, format="PNG", optimize=True)
    return buffer.getvalue()
