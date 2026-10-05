#!/usr/bin/env python3
"""Build synthetic PS-X EXEs that combine the resident EXE with one overlay.

The resident code loads the four mode overlays (arcade, practice, force, volley)
at ``0x800B0A10`` and the screen overlays (enbu, select, title, ranking, ending,
result) at ``0x800B9378`` in Japan Rev.1, and at ``0x800B0548`` / ``0x800B8D58`` in the
USA release (see docs/research/code/memory-map.md; the bases were confirmed
by matching ``jal`` targets with function prologues and string addresses with strings).
Ghidra resolves calls best when the overlay lives next to the resident code, so
each output file keeps the original EXE header/bytes below the overlay's base
and appends the overlay there. The header's text size field is patched.
"""

from __future__ import annotations

import argparse
import logging
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE_HEADER_BYTES = 0x800
TEXT_BASE = 0x80010000
MODE_OVERLAY_BASE = 0x800B0A10
SCREEN_OVERLAY_BASE = 0x800B9378
USA_BASES = (0x800B0548, 0x800B8D58)   # mode, screen overlays in SLUS_004.02
MODE_OVERLAYS = {"arcade", "practice", "force", "volley"}
TEXT_SIZE_OFFSET = 0x1C

log = logging.getLogger("make_overlay_exes")


def overlay_base(name: str, release: str = "jp_rev1") -> int:
    mode = name in MODE_OVERLAYS
    if release == "usa":
        return USA_BASES[0] if mode else USA_BASES[1]
    return MODE_OVERLAY_BASE if mode else SCREEN_OVERLAY_BASE


def build(exe: bytes, overlay: bytes, base: int) -> bytes:
    resident = exe[: EXE_HEADER_BYTES + base - TEXT_BASE]
    body = resident + overlay
    body += bytes(-len(body) % 0x800)
    header = bytearray(body[:EXE_HEADER_BYTES])
    struct.pack_into("<I", header, TEXT_SIZE_OFFSET, len(body) - EXE_HEADER_BYTES)
    return bytes(header) + body[EXE_HEADER_BYTES:]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--release", default="jp_rev1")
    parser.add_argument("--out", type=Path, default=ROOT / "work" / "ghidra")
    args = parser.parse_args()
    source = ROOT / "work" / args.release
    exe = (source / "exe.bin").read_bytes()
    args.out.mkdir(parents=True, exist_ok=True)
    for overlay_path in sorted((source / "bns").glob("*.ovl")):
        name = overlay_path.name.split("_", 1)[1].removesuffix(".ovl")
        target = args.out / f"{args.release}_{name}.exe"
        base = overlay_base(name, args.release)
        target.write_bytes(build(exe, overlay_path.read_bytes(), base))
        log.info("%s -> %s at %#x", overlay_path.name, target.name, base)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
