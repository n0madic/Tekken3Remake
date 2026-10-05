#!/usr/bin/env python3
"""List and export the caption overlays of the ending movies (ending.ovl), and port their player.

Four endings draw text captions into the decoded movie frames (formats/sound-and-video.md,
"Movie captions"). This prints each caption set's timeline and, with --export, writes every
caption bitmap as an indexed PNG to work/movie_captions/ (game data: never commit the output).

Usage: python3 tools/research/movie_captions.py [--release jp_rev1|usa] [--export]
"""

from __future__ import annotations

import argparse
import logging
import struct
from pathlib import Path

from psxcpu import load_release

log = logging.getLogger("movie_captions")

RECORD_SIGNATURE = struct.pack("<I8h", 0, 0, 170, 0, 256, 44, 128, 0, 0)   # the first caption record
BLIT_SIGNATURE = bytes.fromhex("8220040040200400")   # srl a0,a0,2; sll a0,a0,1 in the caption blit (FUN_8010F3F8)
DESCRIPTORS = 0x800B97CC         # movie descriptors: flags at +0x0A, bits 8-11 = caption set (Japan layout)


def find_tables(cpu, release: str = "jp_rev1") -> dict:
    """Locate the caption records, timeline, palettes and bitmap base in either release."""
    from make_overlay_exes import overlay_base
    OVERLAY = overlay_base("ending", release)
    data = cpu.read(OVERLAY, 0x80000)
    records = OVERLAY + data.index(RECORD_SIGNATURE)
    count = 0
    while struct.unpack("<Hh", cpu.read(records + 0x14 * count, 4)) != (0, -1):
        count += 1
    timeline = records + 0x14 * count
    # The sets (Japan four, USA five) follow each other, each closed by 0xFFFF; the palettes follow.
    sets: list[list[tuple[int, int]]] = []
    a = timeline
    while True:
        frame, cap = struct.unpack("<Hh", cpu.read(a, 4))
        a += 4
        if frame == 0xFFFF:
            if struct.unpack("<Hh", cpu.read(a, 4)) != (0, -1):
                break
            continue
        if frame == 0:
            sets.append([])
        sets[-1].append((frame, cap))
    blit = OVERLAY + data.index(BLIT_SIGNATURE)
    hi = cpu.u32(blit - 4) & 0xFFFF                   # lui v1, hi (in the preceding delay slot)
    lo = struct.unpack("<h", cpu.read(blit + 12, 2))[0]  # lw v1, lo(v1)
    bitmaps = cpu.u32((hi << 16) + lo & 0xFFFFFFFF)
    return {"records": records, "count": count, "timeline": timeline, "sets": sets, "palettes": a,
            "bitmaps": bitmaps}


def record(cpu, t: dict, idx: int) -> dict:
    off, x0, y, skip, w, h, stride, pal, _ = struct.unpack("<I8h", cpu.read(t["records"] + 0x14 * idx, 0x14))
    return {"offset": off, "x0": x0, "y": y, "skip": skip, "width": w, "height": h, "stride": stride, "palette": pal}


def export(cpu, t: dict, idx: int, out: Path) -> None:
    from PIL import Image
    r = record(cpu, t, idx)
    w, h = r["width"], r["height"]
    data = cpu.read(t["bitmaps"] + r["offset"], w * h // 2)
    pixels = bytearray()
    for b in data:
        pixels += bytes((b & 0xF, b >> 4))
    img = Image.frombytes("P", (w, h), bytes(pixels))
    pal = cpu.read(t["palettes"] + 0x80 * {0: 0, 2: 1, 3: 2}[r["palette"]], 16 * 8)
    img.putpalette(b"".join(pal[8 * k:8 * k + 3] for k in range(16)))
    img.info["transparency"] = 0
    img.save(out / f"caption_{idx:02d}.png")


# ---- the caption player (Japan Rev.1 addresses; ported from FUN_8010EF7C..FUN_8010F3F8) ----
CAPTION = 0x80194550             # s16 caption (-1 none), s16 timeline position, then a copy of its record
RECORDS, TIMELINE = 0x800B9CE0, 0x800B9E70
PALETTES = {0: 0x800B9F0C, 2: 0x800B9F8C, 3: 0x800BA00C}   # 16 x (r, g, b, blend flag, 4 unused)
BITMAP_PTR = 0x8011DA8C


def _sdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def caption_clear(ram) -> None:
    """FUN_8010EF7C."""
    ram.put(CAPTION, "h", -1)
    ram.put(CAPTION + 2, "h", -1)


def caption_set(ram, idx: int) -> None:
    """FUN_8010EF94: shows caption `idx` (a copy of its record; -1 hides it)."""
    ram.put(CAPTION, "H", idx & 0xFFFF)
    if idx < 0:
        return
    r = RECORDS + 0x14 * idx
    ram.put(CAPTION + 4, "I", ram.u32(r))
    for k in range(7):
        ram.put(CAPTION + 8 + 2 * k, "H", ram.u16(r + 4 + 2 * k))


def caption_start(ram, set_no: int) -> None:
    """FUN_8010F004: positions the timeline at the start of caption set `set_no` (0-3); -1 stops."""
    if set_no < 0:
        caption_clear(ram)
        return
    i = 0
    while i < 0x27:
        if ram.u16(TIMELINE + 4 * i) == 0:
            set_no -= 1
            if set_no < 0:
                break
        i += 1
    ram.put(CAPTION + 2, "H", i)
    ram.put(CAPTION, "H", i)
    if set_no < 0:
        ram.put(CAPTION, "h", -1)
    else:
        caption_set(ram, ram.s16(TIMELINE + 4 * i + 2))


def caption_update(ram, frame: int) -> None:
    """FUN_8010F0B4: shows the last caption of the set whose start frame is below `frame`."""
    pos = ram.s16(CAPTION + 2)
    if frame <= 0 or pos < 0:
        return
    if ram.u16(TIMELINE + 4 * pos) < frame:
        while True:
            pos += 1
            if not ram.u16(TIMELINE + 4 * pos) < frame:
                break
    caption_set(ram, ram.s16(TIMELINE + 4 * (pos - 1) + 2))


def caption_blend(ram, src: int, dst: int, rows: int, pal: int) -> None:
    """FUN_8010F138: draws `rows` rows of 16 caption pixels (4 bpp, 128 bytes per bitmap row) into
    a 24-bit macroblock column (48 bytes per row). Pixel 0 is transparent; a palette entry with
    its flag set is blended as ((movie >> 1) + colour) >> 1, otherwise copied."""
    if pal not in PALETTES:
        raise NotImplementedError(f"caption palette {pal}")
    table = PALETTES[pal]
    for _ in range(max(rows, 0)):
        for _ in range(4):
            v = ram.u16(src)
            src += 2
            for k in range(4):
                nib = v >> 4 * k & 0xF
                if nib:
                    e = table + 8 * nib
                    for c in range(3):
                        d = dst + 3 * k + c
                        if ram.u8(e + 3):
                            ram.put(d, "B", (ram.u8(d) >> 1) + ram.u8(e + c) >> 1)
                        else:
                            ram.put(d, "B", ram.u8(e + c))
            dst += 12
        src += 0x78


def caption_slice(ram, x: int, dst: int) -> None:
    """FUN_8010F3F8: the caption's part for decoded macroblock column `x` of the movie frame."""
    if ram.s16(CAPTION) < 0:
        return
    col = _sdiv(2 * x, 3) - ram.s16(CAPTION + 8)
    first, count = ram.s16(CAPTION + 0xC), ram.s16(CAPTION + 0xE)
    if col < first or not col < first + count:
        return
    src = ram.u32(BITMAP_PTR) + (ram.u32(CAPTION + 4) >> 1 << 1) + ((col & 0xFFFFFFFF) >> 2 << 1) & 0xFFFFFFFF
    caption_blend(ram, src, dst + 48 * ram.s16(CAPTION + 0xA) & 0xFFFFFFFF, ram.s16(CAPTION + 0x10),
                  ram.s16(CAPTION + 0x14))


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default="jp_rev1")
    parser.add_argument("--export", action="store_true")
    args = parser.parse_args()
    cpu = load_release(args.release, overlay="ending")
    t = find_tables(cpu, args.release)
    log.info("records %#x (%d), timeline %#x, palettes %#x, bitmaps %#x", t["records"], t["count"], t["timeline"],
             t["palettes"], t["bitmaps"])
    for s_, entries in enumerate(t["sets"]):
        log.info("set %d: %s", s_ + 1, entries)
    if args.export:
        out = Path(__file__).resolve().parents[2] / "work" / "movie_captions" / args.release
        out.mkdir(parents=True, exist_ok=True)
        for idx in range(t["count"]):
            export(cpu, t, idx, out)
        log.info("wrote %d captions to %s", t["count"], out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
