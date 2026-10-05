#!/usr/bin/env python3
"""Simulate the KMD vertex-exchange pipeline of DrawSkinnedPart in 3D.

The game transforms each part's vertices to screen space and stitches seams
between parts by summing half-weighted positions through two exchange buffers
(the scratchpad slot array and a global array). This module reproduces the same
bookkeeping on 3D positions for a given set of part transforms, producing one
position per face-vertex slot, and reports how far apart the two halves of each
seam vertex are. In the authoring pose the halves should coincide.
"""

from __future__ import annotations

import argparse
import logging
import math
import sys
from dataclasses import dataclass
from pathlib import Path

import kmd as kmdlib

log = logging.getLogger("kmd_skin")

Vec = tuple[float, float, float]


def add(a: Vec, b: Vec) -> Vec:
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def half(a: Vec) -> Vec:
    return (a[0] / 2, a[1] / 2, a[2] / 2)


def dist(a: Vec, b: Vec) -> float:
    return math.dist(a, b)


@dataclass
class SeamStat:
    pairs: int = 0
    max_gap: float = 0.0
    sum_gap: float = 0.0
    unresolved: int = 0

    def add(self, gap: float) -> None:
        self.pairs += 1
        self.sum_gap += gap
        self.max_gap = max(self.max_gap, gap)


def part_world_offsets(model: kmdlib.Kmd, flip_z: bool) -> list[Vec]:
    """Accumulate joint offsets with identity rotations (authoring pose)."""
    out: list[Vec] = []
    for k, row_index in enumerate(kmdlib.PART_ROW):
        row = model.rows[row_index]
        ox, oy, oz = row.offset
        off = (float(ox), float(oy), float(-oz if flip_z else oz))
        parent = row.parent
        base = out[parent] if 0 <= parent < len(out) else (0.0, 0.0, 0.0)
        out.append(add(base, off))
    return out


def simulate(model: kmdlib.Kmd, origins: list[Vec], flip_z: bool) -> tuple[dict[int, list[Vec]], SeamStat]:
    """Seam simulation with identity rotations at the given part origins."""
    def xf(k: int, v: Vec) -> Vec:
        x, y, z = v
        return add(origins[k], (x, y, -z if flip_z else z))
    return simulate_transformed(model, xf)


def simulate_transformed(model: kmdlib.Kmd, xf) -> tuple[dict[int, list[Vec]], SeamStat]:
    """Emulate the scratchpad slot array and the global exchange array exactly.

    `xf(part_index, (x, y, z))` maps a part-local vertex to world space.
    """
    scr: dict[int, Vec] = {}
    glob: dict[int, Vec] = {}
    scr_full: dict[int, Vec] = {}
    glob_full: dict[int, Vec] = {}
    stat = SeamStat()
    slots_per_part: dict[int, list[Vec]] = {}

    def fetch(buf: dict[int, Vec], slot: int) -> Vec:
        if slot not in buf:
            stat.unresolved += 1
            return (0.0, 0.0, 0.0)
        return buf[slot]

    for k, row_index in enumerate(kmdlib.PART_ROW):
        row = model.rows[row_index]
        if row.verts is None:
            continue
        vb = row.verts
        cur = 0
        for idx in vb.import_scratch:          # compaction inside the same array
            scr[cur] = fetch(scr, idx // 2 - 1)
            scr_full.pop(cur, None)
            cur += 1
        for idx in vb.import_global:
            scr[cur] = fetch(glob, idx // 2 - 1)
            scr_full.pop(cur, None)
            cur += 1
        full: dict[int, Vec] = {}
        for i, (x, y, z) in enumerate(vb.coords):
            p = xf(k, (float(x), float(y), float(z)))
            scr[cur + i] = p
            full[cur + i] = p
        blend_a, add_g, add_s, exp_g, exp_s, halve = vb.post
        for e in blend_a:
            slot, halved = (e & 0xFF) // 2 - 1, e & 0x100
            own = half(scr[cur]) if halved else scr[cur]
            if halved and slot in glob_full:
                stat.add(dist(full[cur], glob_full[slot]))
            scr[cur] = add(own, fetch(glob, slot))
            glob[slot] = scr[cur]
            cur += 1
        for entries, buf, fullbuf in ((add_g, glob, glob_full), (add_s, scr, scr_full)):
            for e in entries:
                slot, halved = (e & 0xFF) // 2 - 1, e & 0x100
                own = half(scr[cur]) if halved else scr[cur]
                if halved and slot in fullbuf:
                    stat.add(dist(full[cur], fullbuf[slot]))
                scr[cur] = add(own, fetch(buf, slot))
                cur += 1
        for entries, buf, fullbuf in ((exp_g, glob, glob_full), (exp_s, scr, scr_full)):
            for e in entries:
                slot, halved = (e & 0xFF) // 2 - 1, e & 0x100
                value = scr[cur]
                if halved:
                    fullbuf[slot] = full[cur]
                    value = half(value)
                    scr[cur] = value
                buf[slot] = value
                cur += 1
        for code in halve:
            if code != 1:
                scr[cur] = half(scr[cur])
            cur += 1
        count = len(vb.import_scratch) + len(vb.import_global) + len(vb.coords)
        slots_per_part[k] = [scr[i] for i in range(count)]
    return slots_per_part, stat


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bns-dir", type=Path, default=Path(__file__).resolve().parents[2] / "work" / "jp_rev1" / "bns")
    parser.add_argument("--only", default="")
    args = parser.parse_args()
    for flip in (False, True):
        agg = SeamStat()
        for path in sorted(args.bns_dir.glob(f"*{args.only}*.kmd")):
            model = kmdlib.parse(path.read_bytes())
            _, st = simulate(model, part_world_offsets(model, flip), flip)
            agg.pairs += st.pairs
            agg.sum_gap += st.sum_gap
            agg.max_gap = max(agg.max_gap, st.max_gap)
            agg.unresolved += st.unresolved
        mean = agg.sum_gap / agg.pairs if agg.pairs else float("nan")
        log.info("flip_z=%s seam pairs %d mean gap %.2f max gap %.2f unresolved %d",
                 flip, agg.pairs, mean, agg.max_gap, agg.unresolved)
    return 0


if __name__ == "__main__":
    sys.exit(main())
