#!/usr/bin/env python3
"""Inspect Tekken 3 stage TMD-shaped BNS records without exporting assets."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, Record, read_records, tim_sequence


STAGE_IDS = range(56, 71)
PACKET_BYTES = {0x24: 20, 0x28: 8, 0x2C: 20}


def inspect(data: bytes, record_id: int) -> dict[str, object]:
    if len(data) < 12:
        raise ValueError(f"stage ID {record_id}: truncated header")
    identifier, flags, object_count = struct.unpack_from("<III", data)
    table_end = 12 + 28 * object_count
    if identifier != 0x41 or object_count != 36 or table_end > len(data):
        raise ValueError(f"stage ID {record_id}: unexpected header/table")
    rows = [struct.unpack_from("<6Ii", data, 12 + 28 * index) for index in range(object_count)]
    primitive_starts = [12 + row[4] for row in rows]
    vertex_starts = [12 + row[0] for row in rows]
    if primitive_starts[0] != table_end:
        raise ValueError(f"stage ID {record_id}: primitive data does not follow object table")
    if not all(primitive_starts[i] <= primitive_starts[i + 1] for i in range(35)):
        raise ValueError(f"stage ID {record_id}: primitive ranges are not ordered")
    if not all(vertex_starts[i] <= vertex_starts[i + 1] for i in range(35)):
        raise ValueError(f"stage ID {record_id}: vertex ranges are not ordered")
    if primitive_starts[-1] > vertex_starts[0]:
        raise ValueError(f"stage ID {record_id}: primitive data overlaps vertices")

    modes = Counter()
    xyz_min, xyz_max = 32767, -32768
    for index, row in enumerate(rows):
        vertex_start = vertex_starts[index]
        vertex_end = vertex_start + row[1] * 8
        next_vertex = vertex_starts[index + 1] if index + 1 < 36 else len(data)
        if vertex_end != next_vertex:
            raise ValueError(f"stage ID {record_id} object {index}: vertex span mismatch")
        for offset in range(vertex_start, vertex_end, 8):
            x, y, z, padding = struct.unpack_from("<4h", data, offset)
            if padding:
                raise ValueError(f"stage ID {record_id} object {index}: vertex padding is nonzero")
            xyz_min = min(xyz_min, x, y, z)
            xyz_max = max(xyz_max, x, y, z)

        packet_end = primitive_starts[index + 1] if index + 1 < 36 else vertex_starts[0]
        cursor = primitive_starts[index]
        for packet_index in range(row[5]):
            if cursor + 4 > packet_end:
                raise ValueError(f"stage ID {record_id} object {index}: packet truncated")
            mode = data[cursor + 3]
            packet_size = PACKET_BYTES.get(mode)
            if packet_size is None or cursor + packet_size > packet_end:
                raise ValueError(f"stage ID {record_id} object {index}: unknown packet mode 0x{mode:02X}")
            indices = data[cursor + (4 if mode == 0x28 else 16) : cursor + packet_size]
            referenced = indices[:3] if mode == 0x24 else indices
            if any(vertex >= row[1] for vertex in referenced):
                raise ValueError(f"stage ID {record_id} object {index}: packet vertex index out of range")
            if mode == 0x24 and indices[3] != 0:
                raise ValueError(f"stage ID {record_id} object {index}: triangle fourth slot is nonzero")
            if mode == 0x24 and data[cursor + 14 : cursor + 16] != b"\0\0":
                raise ValueError(f"stage ID {record_id} object {index}: triangle texture pad is nonzero")
            modes[mode] += 1
            cursor += packet_size
        if cursor != packet_end:
            raise ValueError(f"stage ID {record_id} object {index}: packet span mismatch")

    return {
        "flags": flags,
        "objects": object_count,
        "vertices": sum(row[1] for row in rows),
        "primitives": sum(row[5] for row in rows),
        "modes": modes,
        "xyz_min": xyz_min,
        "xyz_max": xyz_max,
        "normal_pointer_pattern": rows[0][2] == len(data) - 12 and all(row[2] == 0 for row in rows[1:]),
        "scale_zero": all(row[6] == 0 for row in rows),
    }


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--japan-track1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa-track1", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    args = parser.parse_args()
    try:
        japan, _ = read_records(args.japan_track1, JAPAN)
        usa, _ = read_records(args.usa_track1, USA)
        print("# Stage TMD-shaped BNS records, Japan Rev.1 and USA")
        print()
        print("| ID | Bytes | Header word 1 | Objects | Vertices | Packets 0x24 / 0x28 / 0x2C | XYZ range | USA identical |")
        print("|---:|---:|---:|---:|---:|---|---|---|")
        totals = Counter()
        arc_tim_counts = []
        for record_id in STAGE_IDS:
            a: Record = japan[record_id]
            b: Record = usa[record_id]
            ja = inspect(a.data, record_id)
            us = inspect(b.data, record_id)
            if ja != us or a.data != b.data:
                raise ValueError(f"stage ID {record_id}: regional mismatch")
            if not ja["normal_pointer_pattern"] or not ja["scale_zero"]:
                raise ValueError(f"stage ID {record_id}: object-row invariant changed")
            modes: Counter[int] = ja["modes"]  # type: ignore[assignment]
            totals.update(modes)
            print(f"| {record_id} | {a.size:,} | `0x{ja['flags']:X}` | {ja['objects']} | {ja['vertices']} | {modes[0x24]} / {modes[0x28]} / {modes[0x2C]} | {ja['xyz_min']}…{ja['xyz_max']} | yes |")
            arc_id = record_id - 20
            arc = japan[arc_id].data
            if arc != usa[arc_id].data or struct.unpack_from("<I", arc)[0] != 2:
                raise ValueError(f"stage ARC ID {arc_id}: regional mismatch or unexpected member count")
            first_offset, first_size, second_offset, second_size = struct.unpack_from("<4I", arc, 4)
            if first_offset != 24 or first_offset + first_size != second_offset or second_offset + second_size != len(arc) or second_size != 808:
                raise ValueError(f"stage ARC ID {arc_id}: unexpected two-member layout")
            tim_count, tail_size, tail_zero = tim_sequence(arc[first_offset:second_offset])
            arc_tim_counts.append((arc_id, tim_count, tail_size, tail_zero))
        print()
        print(f"Total packets: {sum(totals.values()):,}; modes: " + ", ".join(f"`0x{mode:02X}` {totals[mode]:,}" for mode in sorted(totals)))
        print("Matching stage ARC IDs 36–50: each has two members; member 1 is 808 bytes and byte-identical across regions.")
        print("TIM runs in member 0: " + ", ".join(f"{arc_id}:{count}+{tail}" for arc_id, count, tail, _ in arc_tim_counts))
        if sum(tail == 4 and zero for _, _, tail, zero in arc_tim_counts) != 14:
            raise ValueError("stage ARC TIM sequence profile changed")
        return 0
    except (OSError, ValueError, struct.error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
