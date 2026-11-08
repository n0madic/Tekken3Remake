"""The application icon and Android's adaptive layers, from a title picture."""

from __future__ import annotations

import numpy as np
from PIL import Image

from common import Output
from vram import png_bytes

ICON_SIZE = 256
ADAPTIVE_SIZE = 432                # Android's adaptive layers (108 dp at xxxhdpi)
ADAPTIVE_SAFE = 0.64               # the share of the layer a launcher's mask always shows
MONOCHROME_LEVEL = 110             # the luminance from which the logo counts in the monochrome layer


def icon(picture: np.ndarray, crop: tuple[int, int, int]) -> np.ndarray:
    """The logo square of the title picture (x, y, side), scaled to ICON_SIZE."""
    x, y, side = crop
    square = Image.fromarray(np.ascontiguousarray(picture[y:y + side, x:x + side]), "RGBA")
    return np.asarray(square.resize((ICON_SIZE, ICON_SIZE), Image.LANCZOS))


def adaptive(square: np.ndarray) -> dict[str, np.ndarray]:
    """Android's adaptive icon layers from the square icon."""
    inner = int(ADAPTIVE_SIZE * ADAPTIVE_SAFE)
    at = (ADAPTIVE_SIZE - inner) // 2
    logo = np.asarray(Image.fromarray(square, "RGBA").resize((inner, inner), Image.LANCZOS))
    foreground = np.zeros((ADAPTIVE_SIZE, ADAPTIVE_SIZE, 4), dtype=np.uint8)
    foreground[at:at + inner, at:at + inner] = logo
    background = np.zeros((ADAPTIVE_SIZE, ADAPTIVE_SIZE, 4), dtype=np.uint8)
    background[..., 3] = 255
    monochrome = np.zeros_like(foreground)
    luminance = foreground[..., :3].astype(np.uint16).max(axis=-1)
    monochrome[..., :3] = 255
    monochrome[..., 3] = np.where(luminance >= MONOCHROME_LEVEL, 255, 0)
    return {"foreground": foreground, "background": background, "monochrome": monochrome}


def write(out: Output, picture: np.ndarray, crop: tuple[int, int, int]) -> None:
    """Writes `icon.png` and `icon_<layer>.png` at the root of the conversion."""
    square = icon(picture, crop)
    out.write("icon.png", png_bytes(square))
    for layer, pixels in adaptive(square).items():
        out.write(f"icon_{layer}.png", png_bytes(pixels))
