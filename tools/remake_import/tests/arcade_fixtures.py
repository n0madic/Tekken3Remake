"""Synthetic pieces of an arcade set for the converter's tests: no game data."""

from __future__ import annotations

import struct

from vram import TIM_ID


def literal(data: bytes) -> bytes:
    """Data as the BIOS's LZ: only literals, seven per flag byte, then the end flag."""
    out = bytearray()
    for k in range(0, len(data), 7):
        chunk = data[k:k + 7]
        out.append(((1 << len(chunk)) - 1) | 1 << len(chunk))
        out += chunk
    return bytes(out) + b"\0"


def filled_tim(index: int, palette: list[int], size: tuple[int, int] = (16, 64)) -> bytes:
    """A 4-bit TIM of `size` words, every texel `index`, with its 16-colour CLUT."""
    w, h = size
    clut = struct.pack("<IHHHH16H", 44, 0, 0, 16, 1, *palette)
    word = index * 0x1111
    image = struct.pack("<IHHHH", 12 + 2 * w * h, 0, 0, w, h) + struct.pack(f"<{w * h}H", *[word] * (w * h))
    return struct.pack("<II", TIM_ID, 8) + clut + image
