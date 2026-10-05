#!/usr/bin/env python3
"""Validate the TK3psSDW member in all character ARCs on three local discs."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, arc_members, read_records
from compare_japan_revisions import read_original


ARC_IDS = range(73, 278, 4)


def triangle(word: int) -> tuple[int, int, int]:
    """Projected-slot indices of a packed triangle word (ShadowBuildPrims reads them as byte offsets)."""
    return (word & 0x3FC) >> 2, (word >> 8 & 0x3FC) >> 2, (word >> 18 & 0x3FC) >> 2


def inspect_member(data: bytes, record_id: int) -> Counter:
    if not data:
        return Counter(empty=1)
    if len(data) < 0x80 or data[:8] != b"TK3psSDW":
        raise ValueError(f"ARC {record_id}: TK3psSDW signature/header missing")
    section_end, word_count, quad_count = struct.unpack_from("<3I", data, 8)
    pointers = struct.unpack_from("<27I", data, 0x14)
    if pointers[0] != 0x80 or any(pointers[18:]) or not all(
        left < right for left, right in zip(pointers[:18], pointers[1:18])
    ) or not pointers[17] < section_end < len(data):
        raise ValueError(f"ARC {record_id}: invalid 27-slot section directory")

    stats: Counter = Counter()
    valid_indices = set()
    vertex_index = 0
    for section_id, start in enumerate(pointers[:18]):
        stop = pointers[section_id + 1] if section_id < 17 else section_end
        if stop - start < 4:
            raise ValueError(f"ARC {record_id} section {section_id}: truncated count")
        count = struct.unpack_from("<I", data, start)[0]
        padded_count = ((count + 2) // 3) * 3
        if stop - start != 4 + padded_count * 8:
            raise ValueError(f"ARC {record_id} section {section_id}: vector span mismatch")
        for local_index in range(padded_count):
            vector = struct.unpack_from("<4h", data, start + 4 + 8 * local_index)
            if vector[3]:
                raise ValueError(f"ARC {record_id} section {section_id}: nonzero fourth coordinate")
            if local_index >= count:
                if vector[:3] != (0, 0, 0):
                    raise ValueError(f"ARC {record_id} section {section_id}: nonzero pad vector")
            else:
                valid_indices.add(vertex_index + local_index)
        vertex_index += padded_count
        stats["sections"] += 1
        stats["vectors"] += count
        stats["zero_pad_vectors"] += padded_count - count

    cursor = section_end
    tail_word_count = struct.unpack_from("<I", data, cursor)[0]
    cursor += 4
    if tail_word_count != word_count or cursor + 4 * word_count + 4 > len(data):
        raise ValueError(f"ARC {record_id}: first tail count disagrees with header")
    for k in range(word_count):                  # packed triangles: slot indices in bits 2-9, 10-17, 20-27
        word = struct.unpack_from("<I", data, cursor + 4 * k)[0]
        if any(index not in valid_indices for index in triangle(word)):
            raise ValueError(f"ARC {record_id} triangle {k}: invalid coordinate index")
    cursor += 4 * word_count
    tail_quad_count = struct.unpack_from("<I", data, cursor)[0]
    cursor += 4
    if tail_quad_count != quad_count or cursor + 4 * quad_count != len(data):
        raise ValueError(f"ARC {record_id}: four-byte table does not reach EOF")
    for row in range(quad_count):
        indices = data[cursor + 4 * row : cursor + 4 * (row + 1)]
        if len(set(indices)) != 4 or any(index not in valid_indices for index in indices):
            raise ValueError(f"ARC {record_id} row {row}: duplicate or invalid coordinate index")
    stats["packed_words"] = word_count
    stats["four_index_rows"] = quad_count
    stats["vertex_slots"] = vertex_index
    stats[("profile", section_end, word_count, quad_count, len(data))] += 1
    return stats


def write_raw_obj(data: bytes, record_id: int, output_path: Path) -> None:
    """Write the untransformed shadow mesh: packed triangles and four-index quads."""
    inspect_member(data, record_id)
    if not data:
        raise ValueError(f"ARC {record_id}: no TK3psSDW geometry to export")
    section_end, word_count, quad_count = struct.unpack_from("<3I", data, 8)
    pointers = struct.unpack_from("<18I", data, 0x14)
    vertices = []
    old_to_new = {}
    old_index = 0
    for section_id, start in enumerate(pointers):
        count = struct.unpack_from("<I", data, start)[0]
        padded_count = ((count + 2) // 3) * 3
        for local_index in range(count):
            old_to_new[old_index + local_index] = len(vertices) + 1
            vertices.append(struct.unpack_from("<3h", data, start + 4 + local_index * 8))
        old_index += padded_count
    index_start = section_end + 8 + 4 * word_count
    lines = [
        f"# ARC {record_id} TK3psSDW raw coordinate/index diagnostic",
        "# Original signed coordinate units and file winding; no transforms or materials",
    ]
    lines.extend(f"v {x} {y} {z}" for x, y, z in vertices)
    for k in range(word_count):
        word = struct.unpack_from("<I", data, section_end + 4 + 4 * k)[0]
        lines.append("f " + " ".join(str(old_to_new[index]) for index in triangle(word)))
    for row in range(quad_count):
        original_indices = data[index_start + 4 * row : index_start + 4 * (row + 1)]
        lines.append("f " + " ".join(str(old_to_new[index]) for index in original_indices))
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(lines) + "\n", encoding="ascii")


def inspect(records: list, label: str) -> tuple[Counter, dict[int, bytes]]:
    total: Counter = Counter()
    members = {}
    groups: dict[bytes, list[int]] = defaultdict(list)
    for record_id in ARC_IDS:
        data = arc_members(records[record_id].data)[3]
        total.update(inspect_member(data, record_id))
        members[record_id] = data
        groups[data].append(record_id)
    profiles = {key[1:]: value for key, value in total.items()
                if isinstance(key, tuple) and key[0] == "profile"}
    print(f"{label}: {52-total['empty']} nonempty, {total['empty']} empty; "
          f"{len(groups)-1} distinct nonempty byte strings; "
          f"{total['sections']} sections, {total['vectors']} coordinates, "
          f"{total['zero_pad_vectors']} zero pad coordinates, "
          f"{total['packed_words']} packed words, {total['four_index_rows']} four-index rows")
    print(f"  profiles (section end, packed words, index rows, file bytes): {profiles}")
    return total, members


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-ecm", type=Path, default=root / "Tekken 3 (J) [SLPS-01300]" / "Tekken 3 (J) (Track 1) [SLPS-01300].bin.ecm")
    parser.add_argument("--japan-rev1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    parser.add_argument("--record-id", type=int, choices=ARC_IDS, metavar="ARC_ID",
                        help="ARC ID to use with --raw-obj")
    parser.add_argument("--raw-obj", type=Path,
                        help="write one untransformed OBJ coordinate/index diagnostic")
    args = parser.parse_args()
    if (args.record_id is None) != (args.raw_obj is None):
        parser.error("--record-id and --raw-obj must be supplied together")
    try:
        original, _, _ = read_original(args.original_ecm)
        japan, _ = read_records(args.japan_rev1, JAPAN)
        usa, _ = read_records(args.usa, USA)
        _, baseline = inspect(original, "Japan original")
        for label, records in (("Japan Rev.1", japan), ("USA", usa)):
            _, observed = inspect(records, label)
            if observed != baseline:
                raise ValueError(f"{label}: member-3 bytes differ from original Japan")
        print("All 52 member-3 byte strings match across the three releases.")
        if args.raw_obj is not None:
            write_raw_obj(baseline[args.record_id], args.record_id, args.raw_obj)
            print(f"Raw OBJ diagnostic: {args.raw_obj}")
        return 0
    except (OSError, ValueError, struct.error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
