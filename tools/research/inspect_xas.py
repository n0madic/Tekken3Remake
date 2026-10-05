#!/usr/bin/env python3
"""Inventory the STR movies and XA audio streams in TEKKEN3.XAS.

The XAS file mixes XA-ADPCM audio sectors (Form 2) with STR video sectors
(Form 1 data carrying MDEC bitstream chunks). This tool reads the raw BIN image,
walks every XAS sector and reports:

* STR movies: contiguous runs of video sectors whose frame numbers restart at 1,
  with frame count, resolution, bitstream version and quantiser range, and the
  XA audio channels interleaved with them;
* the XA music/voice streams selected by the executable's 50-row table
  (start group, end group, channel), with their sector counts.

Nothing is written to disk. Usage: python3 tools/research/inspect_xas.py [--release usa]
"""

from __future__ import annotations

import argparse
import collections
import logging
import mmap
import struct
from dataclasses import dataclass, field
from pathlib import Path

from compare_bns import JAPAN, SECTOR_BYTES, USA, find_directory_entry, mode2_form1_payload, parse_dir_record

ROOT = Path(__file__).resolve().parents[2]
IMAGES = {
    "jp_rev1": (ROOT / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin", JAPAN, ("TEKKEN3.XAS",)),
    "usa": (ROOT / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin", USA, ("TEKKEN3", "TEKKEN3.XAS")),
}
XA_TABLE = {"jp_rev1": 0x157E4, "usa": 0x15578}   # EXE file offsets of the 50 x <III> table
XA_ROWS = 50
STR_MAGIC = 0x0160
STR_TYPE = 0x8001
SUBHEADER = 16
USER_DATA = 24

log = logging.getLogger("inspect_xas")


@dataclass
class Movie:
    first_lba: int
    last_lba: int = 0
    frames: int = 0
    sizes: set = field(default_factory=set)
    versions: set = field(default_factory=set)
    qscales: list = field(default_factory=list)
    audio: collections.Counter = field(default_factory=collections.Counter)
    video_sectors: int = 0


def locate(image: mmap.mmap, path: tuple[str, ...]) -> tuple[int, int]:
    pvd = mode2_form1_payload(image, 16)
    lba, size, _, _ = parse_dir_record(pvd[156:190])
    for component in path:
        lba, size, _ = find_directory_entry(image, lba, size, component)
    return lba, size


def scan_movies(image: mmap.mmap, xas_lba: int, sectors: int) -> list[Movie]:
    movies: list[Movie] = []
    current: Movie | None = None
    last_frame = 0
    for i in range(sectors):
        base = (xas_lba + i) * SECTOR_BYTES
        _file, channel, submode, _coding = image[base + SUBHEADER: base + SUBHEADER + 4]
        if submode & 0x20:        # Form 2: XA audio
            if current is not None and i - current.last_lba < 16:
                current.audio[channel] += 1
            continue
        magic, kind, _chunk, _chunks, frame, _size, width, height = struct.unpack_from(
            "<HHHHIIHH", image, base + USER_DATA)
        if magic != STR_MAGIC or kind != STR_TYPE:
            continue
        if current is None or frame < last_frame or frame > last_frame + 1 or i - current.last_lba > 16:
            current = Movie(first_lba=i)
            movies.append(current)
        if frame != last_frame or current.frames == 0:
            current.frames += 1
            qscale, version = struct.unpack_from("<HH", image, base + USER_DATA + 0x20 + 4)
            current.qscales.append(qscale)
            current.versions.add(version)
        current.sizes.add((width, height))
        current.video_sectors += 1
        current.last_lba = i
        last_frame = frame
    return movies


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", choices=sorted(IMAGES), default="jp_rev1")
    args = parser.parse_args()
    image_path, _profile, xas_path = IMAGES[args.release]
    exe = (ROOT / "work" / args.release / "exe.bin").read_bytes()
    with image_path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as image:
        xas_lba, xas_size = locate(image, xas_path)
        sectors = image.size() // SECTOR_BYTES - xas_lba
        sectors = min(sectors, (xas_size + 2047) // 2048)
        log.info("XAS at LBA %d, %d sectors", xas_lba, sectors)
        movies = scan_movies(image, xas_lba, sectors)
        print("| # | XAS sector | Frames | Size | Version | qscale | Audio channels (sectors) |")
        print("|---:|---:|---:|---|---|---|---|")
        for n, m in enumerate(movies):
            sizes = ", ".join(f"{w}x{h}" for w, h in sorted(m.sizes))
            audio = ", ".join(f"{ch} ({cnt})" for ch, cnt in sorted(m.audio.items()))
            print(f"| {n} | {m.first_lba} | {m.frames} | {sizes} | {sorted(m.versions)} | "
                  f"{min(m.qscales)}–{max(m.qscales)} | {audio} |")
        rows = [struct.unpack_from("<III", exe, XA_TABLE[args.release] + 12 * i) for i in range(XA_ROWS)]
        print("\n| XA # | Start | End | Channel | Sectors |\n|---:|---:|---:|---:|---:|")
        for n, (start, end, channel) in enumerate(rows):
            print(f"| {n} | {start} | {end} | {channel} | {(end - start) // 8 + 1} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
