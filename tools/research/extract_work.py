#!/usr/bin/env python3
"""Extract EXEs and named BNS records from the local discs into a private work tree.

The output directory (default: ``<repo>/work``) holds copyrighted game data and
must never be published or committed. It exists so that disassemblers and
analyzers can operate on plain files instead of re-reading raw CD images.

Layout::

    work/<release>/exe.bin              full PS-X EXE including 0x800 header
    work/<release>/bns/<id>_<name>      one file per nonempty BNS record
    work/<release>/manifest.json        id, name, lba, size, sha256
"""

from __future__ import annotations

import argparse
import json
import logging
import mmap
from pathlib import Path

from compare_bns import JAPAN, USA, DiscProfile, read_iso_file, read_records
from compare_japan_revisions import ECMImage, read_original

ROOT = Path(__file__).resolve().parents[2]
RELEASES = {
    "jp_rev1": (ROOT / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin", JAPAN),
    "usa": (ROOT / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin", USA),
}
ORIGINAL_ECM = ROOT / "Tekken 3 (J) [SLPS-01300]" / "Tekken 3 (J) (Track 1) [SLPS-01300].bin.ecm"

log = logging.getLogger("extract_work")


def write_release(out: Path, exe: bytes, records: list, names: list[str]) -> None:
    (out / "bns").mkdir(parents=True, exist_ok=True)
    (out / "exe.bin").write_bytes(exe)
    manifest = []
    for record_id, (record, name) in enumerate(zip(records, names)):
        entry = {"id": record_id, "name": name, "lba": record.lba, "size": record.size, "sha256": record.sha256}
        manifest.append(entry)
        if record.size:
            (out / "bns" / f"{record_id:03d}_{name}").write_bytes(record.data)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1))
    log.info("%s: EXE %d bytes, %d records", out.name, len(exe), sum(r.size > 0 for r in records))


def read_exe(image_path: Path, profile: DiscProfile) -> bytes:
    with image_path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as image:
        return read_iso_file(image, profile.exe_path)[0]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", type=Path, default=ROOT / "work")
    args = parser.parse_args()

    original_records, _, names = read_original(ORIGINAL_ECM)
    with ORIGINAL_ECM.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as source:
        original_exe = read_iso_file(ECMImage(source), ("SLPS_013.00",))[0]
    write_release(args.out / "jp_orig", original_exe, original_records, names)

    for label, (image_path, profile) in RELEASES.items():
        records, _ = read_records(image_path, profile)
        write_release(args.out / label, read_exe(image_path, profile), records, names)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
