#!/usr/bin/env python3
"""Find code differences between the Japan Rev.1 and USA executables.

Each instruction is normalised so that relocation does not matter: `j`/`jal` keep only the
opcode, I-type instructions drop their immediate (addresses and data offsets move between
releases) except branches, and R-type instructions are kept whole. Every Japan Rev.1 game
function (boundaries from the Ghidra export) is looked up in the USA code by its normalised
instruction sequence; functions without an identical USA counterpart are listed with the
closest USA candidate and the number of differing instructions.

With `--overlay NAME` the same comparison runs on an overlay (`NAME.ovl` of both releases,
function boundaries from `work/decomp/jp_rev1_NAME.exe.overlay.functions.tsv`).

Usage: python3 tools/research/compare_exe_code.py [--all] [--overlay NAME]
"""

from __future__ import annotations

import argparse
import logging
import struct
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE_BASE, EXE_HEADER = 0x80010000, 0x800
GAME_END_JP = 0x8007A094           # PsyQ runtime starts here (Japan Rev.1)
ANCHOR = 8                         # instructions hashed to find candidates
BRANCH_OPS = {0x01, 0x04, 0x05, 0x06, 0x07}

log = logging.getLogger("compare_exe_code")


def words(path: Path, skip: int = EXE_HEADER) -> list[int]:
    data = path.read_bytes()[skip:]
    return list(struct.unpack(f"<{len(data) // 4}I", data[: len(data) // 4 * 4]))


def normalise(w: int) -> int:
    op = w >> 26
    if op in (2, 3):
        return op << 26
    if op == 0 or op == 0x12:
        return w
    if op in BRANCH_OPS:
        return w
    return w & 0xFFFF0000


def function_starts(tsv: Path, lo: int, hi: int) -> list[int]:
    starts = []
    for line in tsv.read_text().splitlines()[1:]:
        addr = int(line.split("\t")[0], 16)
        if lo <= addr < hi and addr % 4 == 0:
            starts.append(addr)
    return sorted(set(starts))


def overlay_base(name: str, release: str = "jp_rev1") -> int:
    import sys
    sys.path.insert(0, str(ROOT / "tools" / "research"))
    from make_overlay_exes import overlay_base as base
    return base(name, release)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--all", action="store_true", help="list matched functions too")
    parser.add_argument("--overlay", help="compare this overlay instead of the executable")
    args = parser.parse_args()
    if args.overlay:
        jp_file = next((ROOT / "work" / "jp_rev1" / "bns").glob(f"*_{args.overlay}.ovl"))
        us_file = next((ROOT / "work" / "usa" / "bns").glob(f"*_{args.overlay}.ovl"))
        base = overlay_base(args.overlay)
        jp_raw, us_raw = words(jp_file, 0), words(us_file, 0)
        tsv = ROOT / "work" / "decomp" / f"jp_rev1_{args.overlay}.exe.overlay.functions.tsv"
        end = base + 4 * len(jp_raw)
    else:
        jp_raw = words(ROOT / "work" / "jp_rev1" / "exe.bin")
        us_raw = words(ROOT / "work" / "usa" / "exe.bin")
        base, end = EXE_BASE, GAME_END_JP
        tsv = ROOT / "work" / "decomp" / "SLPS_013.00.functions.tsv"
    jp = [normalise(w) for w in jp_raw]
    us = [normalise(w) for w in us_raw]
    index: dict[tuple, list[int]] = defaultdict(list)
    for i in range(len(us) - ANCHOR):
        index[tuple(us[i:i + ANCHOR])].append(i)
    starts = function_starts(tsv, base, end)
    same = changed = missing = 0
    for k, start in enumerate(starts):
        stop = starts[k + 1] if k + 1 < len(starts) else end
        a, b = (start - base) // 4, (stop - base) // 4
        body = jp[a:b]
        if len(body) < ANCHOR:
            continue
        cands = index.get(tuple(body[:ANCHOR]), [])
        best, best_diff = None, None
        for c in cands:
            other = us[c:c + len(body)]
            diff = sum(x != y for x, y in zip(body, other))
            if best_diff is None or diff < best_diff:
                best, best_diff = c, diff
        if best is not None and best_diff == 0:
            same += 1
            if args.all:
                log.info("%08x same as USA offset %#x", start, 4 * best)
        elif best is not None:
            changed += 1
            log.info("%08x (%d instr) changed: USA offset %#x, %d differing", start, len(body), 4 * best, best_diff)
        else:
            missing += 1
            log.info("%08x (%d instr) no USA anchor", start, len(body))
    log.info("identical %d, changed %d, no anchor %d", same, changed, missing)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
