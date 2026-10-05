#!/usr/bin/env python3
"""Print the character/costume records of the Tekken 3 executable.

`g_charRecords` (0x80098120 in Japan Rev.1) holds 93 pointers indexed by
`character * 4 + costume`; several indices share one record. Each record is

    +0x00  u32  pointer to the display name
    +0x04  u8   base character (select/profile index)
    +0x05..+0x07  u8  not yet identified
    +0x08  u8   voice set (index into the character voice table 0x8001AD54)
    +0x09  u8   motion bank type (divmot NN)
    +0x0A  u8   home stage
    +0x0B  u8   music track
    +0x0C  char name (the display name pointer usually points here)

Usage: python3 tools/research/char_records.py [--release usa]
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE_BASE = 0x80010000
EXE_HEADER = 0x800
RECORDS = {"jp_rev1": 0x80098120}
RECORD_COUNT = 93


def c_string(exe: bytes, addr: int) -> str:
    off = addr - EXE_BASE + EXE_HEADER
    end = exe.index(b"\0", off)
    return exe[off:end].decode("ascii", "replace")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", choices=sorted(RECORDS), default="jp_rev1")
    args = parser.parse_args()
    exe = (ROOT / "work" / args.release / "exe.bin").read_bytes()
    table = RECORDS[args.release] - EXE_BASE + EXE_HEADER
    print("| Char | Costumes | Name | Base | +5 | +6 | +7 | Voice set | Bank | Stage | Music |")
    print("|---:|---|---|---:|---:|---:|---:|---:|---:|---:|---:|")
    rows: dict[int, list[int]] = {}
    order: list[int] = []
    for index in range(RECORD_COUNT - 1):
        ptr = struct.unpack_from("<I", exe, table + 4 * index)[0]
        key = (index // 4) << 32 | ptr
        if key not in rows:
            rows[key] = []
            order.append(key)
        rows[key].append(index % 4)
    for key in order:
        char, ptr = key >> 32, key & 0xFFFFFFFF
        rec = exe[ptr - EXE_BASE + EXE_HEADER: ptr - EXE_BASE + EXE_HEADER + 12]
        name = c_string(exe, struct.unpack_from("<I", rec)[0])
        costumes = ",".join(str(c) for c in rows[key])
        print(f"| {char} | {costumes} | {name} | " + " | ".join(str(b) for b in rec[4:12]) + " |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
