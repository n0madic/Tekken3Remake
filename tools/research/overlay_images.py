#!/usr/bin/env python3
"""List or export the images embedded in the overlays (Japan Rev.1).

Screen and mode overlays carry their own pictures: plain TIM files, and archives of
compressed TIMs in the system-texture layout (`u32 count`, then `count` pairs
`(offset, size)`; each member is a TIM compressed with the `.tiz` LZ scheme), which the
game uploads with `FUN_8004CD28` (all members) or `FUN_8004CC04` (one member). This tool
finds both by structure: a TIM header with consistent block lengths, or an archive whose
offset table is contiguous and whose first member decompresses to a TIM.

Output goes to work/ only (game data): `--export` writes one PNG per image to
`work/overlay_images/<overlay>/<address>[_<member>].png`, 4- and 8-bit images drawn with
the first row of their own CLUT.

Usage: python3 tools/research/overlay_images.py [--export] [--overlay NAME]
"""

from __future__ import annotations

import argparse
import logging
import struct
from dataclasses import dataclass
from pathlib import Path

from make_overlay_exes import overlay_base
from system_textures import decompress, tim_blocks

ROOT = Path(__file__).resolve().parents[2]
BNS_DIR = ROOT / "work" / "jp_rev1" / "bns"
OUT_DIR = ROOT / "work" / "overlay_images"
TIM_MAGIC = 0x10
TIM_MODES = {0, 1, 2, 3, 8, 9}          # 4-, 8-, 16-, 24-bit, with or without CLUT
MAX_MEMBERS = 300
VRAM_W, VRAM_H = 1024, 512

log = logging.getLogger("overlay_images")


@dataclass
class Found:
    address: int
    tims: list[bytes]                    # one TIM for a plain file, the members of an archive
    archive: bool


def tim_length(data: bytes, offset: int, member: bool = False) -> int | None:
    """Byte length of a well-formed TIM at offset, or None.

    With member (a decompressed archive member), a CLUT TIM may end in an empty 4-byte
    image block (members that only upload a palette, as in the system-texture archive),
    and the image block's length field may exceed its pixel data (`select.ovl` archive
    `0x80118C48` member 8 declares 2,275 bytes for 36 x 31 words); the loader uses the
    rectangle.
    """
    if offset + 20 > len(data):
        return None
    magic, mode = struct.unpack_from("<II", data, offset)
    if magic != TIM_MAGIC or mode not in TIM_MODES:
        return None
    q = offset + 8
    for block in range(2 if mode & 8 else 1):
        if q + 4 > len(data):
            return None
        length = struct.unpack_from("<I", data, q)[0]
        last = block == (1 if mode & 8 else 0)
        if member and mode & 8 and last and length == 4:
            q += length
            continue
        if q + 12 > len(data):
            return None
        x, y, w, h = struct.unpack_from("<4H", data, q + 4)
        exact = length == 12 + 2 * w * h or (member and last and length > 12 + 2 * w * h)
        if not w or not h or x >= VRAM_W or y >= VRAM_H or not exact:
            return None
        q += length
    return q - offset


def archive_members(data: bytes, offset: int) -> list[bytes] | None:
    """Decompressed members of a compressed-TIM archive at offset, or None."""
    if offset + 12 > len(data):
        return None
    count = struct.unpack_from("<I", data, offset)[0]
    if not 1 <= count <= MAX_MEMBERS or offset + 4 + 8 * count > len(data):
        return None
    table = [struct.unpack_from("<II", data, offset + 4 + 8 * i) for i in range(count)]
    if table[0][0] != 4 + 8 * count or any(b[0] <= a[0] for a, b in zip(table, table[1:])):
        return None
    members = []
    for start, size in table:
        try:
            tim = decompress(data[offset + start:offset + start + size + 64])
        except (ValueError, IndexError):
            return None
        if tim_length(tim, 0, member=True) is None:
            return None
        members.append(tim)
    return members


def scan(data: bytes, base: int) -> list[Found]:
    found = []
    offset = 0
    while offset + 12 <= len(data):
        length = tim_length(data, offset)
        if length:
            found.append(Found(base + offset, [data[offset:offset + length]], False))
            offset += (length + 3) & ~3          # the data after a TIM is word aligned
            continue
        members = archive_members(data, offset)
        if members:
            found.append(Found(base + offset, members, True))
        offset += 4
    return found


def to_png(tim: bytes, path: Path) -> None:
    from PIL import Image

    mode = struct.unpack_from("<I", tim, 4)[0]
    blocks = {kind: (w, h, pixels) for kind, _, _, w, h, pixels in tim_blocks(tim)}
    if "image" not in blocks:
        return                                   # palette-only member
    w, h, pixels = blocks["image"]
    depth = mode & 7

    def rgb(v: int) -> tuple[int, int, int]:
        return ((v & 31) * 255 // 31, (v >> 5 & 31) * 255 // 31, (v >> 10 & 31) * 255 // 31)

    palette = []
    if "clut" in blocks:
        cw, _, clut = blocks["clut"]
        palette = [rgb(struct.unpack_from("<H", clut, 2 * i)[0]) for i in range(cw)]
    if depth == 0:
        width = 4 * w
        values = [pixels[i >> 1] >> (4 * (i & 1)) & 15 for i in range(len(pixels) * 2)]
    elif depth == 1:
        width = 2 * w
        values = list(pixels)
    else:
        width = w
        values = [struct.unpack_from("<H", pixels, 2 * i)[0] for i in range(len(pixels) // 2)]
    values = values[:width * h]                  # a member's block may declare extra bytes
    image = Image.new("RGB", (width, h))
    if depth in (0, 1):
        image.putdata([palette[v] if v < len(palette) else (255, 0, 255) for v in values])
    else:
        image.putdata([rgb(v) for v in values])
    image.save(path)


def describe(tim: bytes) -> str:
    mode = struct.unpack_from("<I", tim, 4)[0]
    parts = [f"{kind} ({x}, {y}) {w}x{h}" for kind, x, y, w, h, _ in tim_blocks(tim)]
    return f"mode {mode}: " + ", ".join(parts)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--export", action="store_true")
    parser.add_argument("--overlay", help="only this overlay (for example title)")
    args = parser.parse_args()
    for path in sorted(BNS_DIR.glob("*.ovl")):
        name = path.stem.split("_", 1)[1]
        if args.overlay and name != args.overlay:
            continue
        data = path.read_bytes()
        found = scan(data, overlay_base(name))
        members = sum(len(f.tims) for f in found)
        log.info("%s: %d plain TIMs, %d archives, %d images", name,
                 sum(not f.archive for f in found), sum(f.archive for f in found), members)
        for f in found:
            if f.archive:
                log.info("  archive 0x%08X, %d members", f.address, len(f.tims))
            for i, tim in enumerate(f.tims):
                label = f"0x{f.address:08X}" + (f"[{i}]" if f.archive else "")
                log.debug("  %s %s", label, describe(tim))
                if args.export:
                    out = OUT_DIR / name
                    out.mkdir(parents=True, exist_ok=True)
                    to_png(tim, out / (f"{f.address:08x}" + (f"_{i:03d}" if f.archive else "") + ".png"))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
