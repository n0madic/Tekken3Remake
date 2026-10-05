#!/usr/bin/env python3
"""List or export the resident system texture archive of the executable.

The boot code (`FUN_800B0BD0`, run once from the start-up overlay area) decompresses the
archive at `0x800B9378` of the executable image (USA `0x800B8D58`, same bytes; original Japan `0x800BA428`, first member differs) with `FUN_8004CD28`: `u32 count`, then
`count` pairs `(offset, size)` relative to the archive; each member is one TIM compressed
with the LZ scheme of the `.tiz` files (`FUN_80031E50`: a flag byte for 7 tokens, LSB first;
1 = literal byte, 0 = two-byte copy with length `byte0 >> 3` (0 = 32) and an 11-bit distance
(0 = 2048)). The TIMs are uploaded at their own rectangles; CLUT-only members carry a
4-byte image block. The pages hold the HUD, fonts, effect sprites and effect palettes.

Output goes to work/ only (game data): `--export` writes `work/system_textures/vram.bin`
(1024 x 512 16-bit words) and one PNG per 4-bit page with the given CLUT.

Usage: python3 tools/research/system_textures.py [--export] [--release jp_rev1]
"""

from __future__ import annotations

import argparse
import logging
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ARCHIVE = {"jp_rev1": 0x800B9378, "jp_orig": 0x800BA428, "usa": 0x800B8D58}   # jp_rev1 and usa byte-identical
EXE_BASE = 0x80010000
EXE_HEADER = 0x800
VRAM_W, VRAM_H = 1024, 512

log = logging.getLogger("system_textures")


def decompress(src: bytes) -> bytes:
    """FUN_80031E50 until the TIM declared by the decoded header is complete."""
    out = bytearray()
    p = 0
    need = None
    while p < len(src):
        flags = src[p]
        p += 1
        for bit in range(7):
            if flags >> bit & 1:
                out.append(src[p])
                p += 1
            else:
                a, b = src[p], src[p + 1]
                p += 2
                length = (a >> 3) or 32
                distance = (((a & 7) << 8) | b) or 2048
                for _ in range(length):
                    out.append(out[-distance])
            if need is None and len(out) >= 12:
                mode = struct.unpack_from("<I", out, 4)[0]
                first = struct.unpack_from("<I", out, 8)[0]
                if not mode & 8:
                    need = 8 + first
                elif len(out) >= 8 + first + 4:
                    need = 8 + first + struct.unpack_from("<I", out, 8 + first)[0]
            if need is not None and len(out) >= need:
                return bytes(out[:need])
    raise ValueError("compressed TIM ends early")


def tim_blocks(tim: bytes) -> list[tuple[str, int, int, int, int, bytes]]:
    mode = struct.unpack_from("<I", tim, 4)[0]
    q = 8
    blocks = []
    kinds = (["clut"] if mode & 8 else []) + ["image"]
    for kind in kinds:
        length = struct.unpack_from("<I", tim, q)[0]
        if length >= 12:
            x, y, w, h = struct.unpack_from("<4H", tim, q + 4)
            blocks.append((kind, x, y, w, h, tim[q + 12:q + length]))
        q += length
    return blocks


def members(exe: bytes, release: str) -> list[tuple[int, bytes]]:
    base = ARCHIVE[release] - EXE_BASE + EXE_HEADER
    count = struct.unpack_from("<I", exe, base)[0]
    out = []
    for i in range(count):
        offset, size = struct.unpack_from("<II", exe, base + 4 + 8 * i)
        tim = decompress(exe[base + offset:base + offset + size + 64])
        out.append((struct.unpack_from("<I", tim, 4)[0], tim))
    return out


def build_vram(tims: list[tuple[int, bytes]]) -> bytearray:
    vram = bytearray(VRAM_W * VRAM_H * 2)
    for _, tim in tims:
        for _, x, y, w, h, data in tim_blocks(tim):
            for row in range(h):
                dst = ((y + row) * VRAM_W + x) * 2
                vram[dst:dst + 2 * w] = data[row * 2 * w:(row + 1) * 2 * w]
    return vram


def export_pages(vram: bytearray, out: Path) -> None:
    from PIL import Image  # optional dependency, only for --export

    def word(x: int, y: int) -> int:
        return struct.unpack_from("<H", vram, (y * VRAM_W + x) * 2)[0]

    def rgb(c: int) -> tuple[int, int, int]:
        return ((c & 31) << 3, (c >> 5 & 31) << 3, (c >> 10 & 31) << 3)

    pages = {"effects_960_256": (960, 256, 96, 503), "effects_896_256": (896, 256, 112, 503)}
    for name, (px, py, cx, cy) in pages.items():
        clut = [word(cx + i, cy) for i in range(16)]
        img = Image.new("RGB", (256, 256))
        for y in range(256):
            for x in range(256):
                img.putpixel((x, y), rgb(clut[word(px + x // 4, py + y) >> (4 * (x & 3)) & 15]))
        img.save(out / f"{name}.png")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default="jp_rev1")
    parser.add_argument("--export", action="store_true")
    args = parser.parse_args()
    exe = (ROOT / "work" / args.release / "exe.bin").read_bytes()
    tims = members(exe, args.release)
    for i, (mode, tim) in enumerate(tims):
        desc = ", ".join(f"{k} ({x},{y}) {w}x{h}" for k, x, y, w, h, _ in tim_blocks(tim))
        log.info("%3d  %2d bpp  %s", i, (4, 8, 16, 24)[mode & 3], desc)
    if args.export:
        out = ROOT / "work" / "system_textures"
        out.mkdir(parents=True, exist_ok=True)
        vram = build_vram(tims)
        (out / "vram.bin").write_bytes(vram)
        export_pages(vram, out)
        log.info("wrote %s", out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
