#!/usr/bin/env python3
"""Match stage TMD textured packets to same-name ARC TIMs by PSX VRAM coordinates."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, read_records, tim_length
from inspect_stage_tmd import PACKET_BYTES, STAGE_IDS, inspect as inspect_stage


def read_tims(arc: bytes, arc_id: int) -> tuple[
    list[tuple[tuple[int, int, int, int], tuple[int, int, int, int]]],
    int,
    set[tuple[int, int]],
    int,
    int,
    int,
]:
    if len(arc) < 24 or struct.unpack_from("<I", arc)[0] != 2:
        raise ValueError(f"stage ARC ID {arc_id}: expected two members")
    first, first_size, second, second_size = struct.unpack_from("<4I", arc, 4)
    if first != 24 or first + first_size != second or second + second_size != len(arc) or second_size != 808:
        raise ValueError(f"stage ARC ID {arc_id}: invalid member extents")
    data = arc[first:second]
    tims = []
    palettes: dict[tuple[int, int], set[bytes]] = defaultdict(set)
    palette_indices: dict[tuple[int, int], set[int]] = defaultdict(set)
    image_words: dict[tuple[int, int], bytes] = {}
    repeated_image_words = differing_image_words = 0
    cursor = 0
    while (length := tim_length(data, cursor)) is not None:
        flags = struct.unpack_from("<I", data, cursor + 4)[0]
        if flags != 8:
            raise ValueError(f"stage ARC ID {arc_id}: expected 4bpp TIM with CLUT")
        clut_start = cursor + 8
        clut_length = struct.unpack_from("<I", data, clut_start)[0]
        clut = struct.unpack_from("<4H", data, clut_start + 4)
        clut_address = clut[:2]
        palettes[clut_address].add(data[clut_start + 12 : clut_start + clut_length])
        image_start = clut_start + clut_length
        image = struct.unpack_from("<4H", data, image_start + 4)
        if clut[2:] != (16, 1):
            raise ValueError(f"stage ARC ID {arc_id}: expected one 16-color CLUT")
        image_x, image_y, image_width, image_height = image
        pixels = data[image_start + 12 : image_start + 12 + 2 * image_width * image_height]
        for packed in pixels:
            palette_indices[clut_address].update((packed & 0x0F, packed >> 4))
        for y in range(image_height):
            for x in range(image_width):
                address = (image_x + x, image_y + y)
                word = pixels[2 * (y * image_width + x) : 2 * (y * image_width + x) + 2]
                if address in image_words:
                    repeated_image_words += 1
                    differing_image_words += image_words[address] != word
                image_words[address] = word
        tims.append((clut, image))
        cursor += length
    tail = data[cursor:]
    if len(tail) not in (4, 2116) or (len(tail) == 4 and any(tail)):
        raise ValueError(f"stage ARC ID {arc_id}: unexpected TIM tail")
    conflicting_cluts = {address for address, bodies in palettes.items() if len(bodies) > 1}
    visible_palette_conflicts = sum(
        any(len({body[index * 2 : index * 2 + 2] for body in palettes[address]}) > 1 for index in palette_indices[address])
        for address in conflicting_cluts
    )
    return tims, len(tail), conflicting_cluts, repeated_image_words, differing_image_words, visible_palette_conflicts


def inspect_materials(
    tmd: bytes,
    tims: list[tuple[tuple[int, int, int, int], tuple[int, int, int, int]]],
    conflicting_cluts: set[tuple[int, int]],
    stage_id: int,
) -> tuple[Counter[str], set[int]]:
    inspect_stage(tmd, stage_id)
    rows = [struct.unpack_from("<7I", tmd, 12 + 28 * row) for row in range(36)]
    stats: Counter[str] = Counter()
    used: set[int] = set()
    for object_id, row in enumerate(rows):
        cursor = 12 + row[4]
        for packet_id in range(row[5]):
            mode = tmd[cursor + 3]
            if mode == 0x28:
                stats["untextured"] += 1
            else:
                cba, tsb = struct.unpack_from("<HxxH", tmd, cursor + 6)
                uv = [
                    (tmd[cursor + 4], tmd[cursor + 5]),
                    (tmd[cursor + 8], tmd[cursor + 9]),
                    (tmd[cursor + 12], tmd[cursor + 13]),
                ]
                if mode == 0x2C:
                    uv.append((tmd[cursor + 14], tmd[cursor + 15]))
                clut_x, clut_y = (cba & 0x3F) * 16, (cba >> 6) & 0x1FF
                texture_format = (tsb >> 7) & 0x03
                page = tsb & 0x1F
                page_x, page_y = (page & 0x0F) * 64, (page & 0x10) * 16
                if texture_format != 0 or tsb & ~0x1FF or cba & 0x8000:
                    raise ValueError(f"stage ID {stage_id} object {object_id} packet {packet_id}: unexpected texture encoding")
                vram = [(page_x + u // 4, page_y + v) for u, v in uv]
                matches = []
                for tim_id, (clut, image) in enumerate(tims):
                    cx, cy, cw, ch = clut
                    ix, iy, iw, ih = image
                    if (
                        cx <= clut_x < cx + cw
                        and cy <= clut_y < cy + ch
                        and all(ix <= x < ix + iw and iy <= y < iy + ih for x, y in vram)
                    ):
                        # Check the full pixel coordinate as well as the word coordinate.
                        if all(0 <= 4 * (page_x - ix) + u < iw * 4 for u, _ in uv):
                            matches.append(tim_id)
                if len(matches) != 1:
                    raise ValueError(f"stage ID {stage_id} object {object_id} packet {packet_id}: {len(matches)} matching TIMs")
                used.add(matches[0])
                stats["textured"] += 1
                stats["palette_conflict_exposed"] += (clut_x, clut_y) in conflicting_cluts
            cursor += PACKET_BYTES[mode]
    return stats, used


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--japan-track1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa-track1", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    args = parser.parse_args()
    try:
        japan, _ = read_records(args.japan_track1, JAPAN)
        usa, _ = read_records(args.usa_track1, USA)
        total: Counter[str] = Counter()
        total_tims = total_used = total_palette_collisions = 0
        total_repeated_words = total_differing_words = total_visible_palette_conflicts = 0
        print("# Stage TMD packet-to-TIM matching")
        print()
        print("| TMD ID | ARC ID | TIMs | Used TIMs | Textured packets, unique TIM | Untextured packets | Packets at conflicting CLUT | Conflicting CLUT sites | Used-index palette conflicts | Repeated image words | Differing image words | TIM tail bytes |")
        print("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|")
        for stage_id in STAGE_IDS:
            arc_id = stage_id - 20
            if japan[stage_id].data != usa[stage_id].data or japan[arc_id].data != usa[arc_id].data:
                raise ValueError(f"stage ID {stage_id}: regional mismatch")
            tims, tail, conflicting_cluts, repeated_words, differing_words, visible_palette_conflicts = read_tims(japan[arc_id].data, arc_id)
            counts, used = inspect_materials(japan[stage_id].data, tims, conflicting_cluts, stage_id)
            total.update(counts)
            total_tims += len(tims)
            total_used += len(used)
            total_palette_collisions += len(conflicting_cluts)
            total_repeated_words += repeated_words
            total_differing_words += differing_words
            total_visible_palette_conflicts += visible_palette_conflicts
            print(f"| {stage_id} | {arc_id} | {len(tims)} | {len(used)} | {counts['textured']} | {counts['untextured']} | {counts['palette_conflict_exposed']} | {len(conflicting_cluts)} | {visible_palette_conflicts} | {repeated_words} | {differing_words} | {tail} |")
        print()
        print(f"Total: {total['textured']:,} textured packets each match exactly one TIM; {total['untextured']:,} untextured packets; {total_used:,} of {total_tims:,} TIMs referenced.")
        print(f"CLUT coordinates with differing palette payloads within a stage ARC: {total_palette_collisions}; conflicts at indices used by any same-site TIM image: {total_visible_palette_conflicts}.")
        print(f"Textured packets addressing conflicting CLUT sites: {total['palette_conflict_exposed']:,}.")
        print(f"Repeated image VRAM words: {total_repeated_words:,}; differing payloads at those words: {total_differing_words:,}.")
    except (OSError, ValueError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
