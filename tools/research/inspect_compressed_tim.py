#!/usr/bin/env python3
"""Inspect Tekken 3's `.tiz` and `.tia` TIM compression on local discs.

The decoder emits only measurements. It does not write game assets.
"""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, read_records, tim_length
from compare_japan_revisions import read_original


MAX_TIM_SIZE = 1 << 20


def declared_tim_size(data: bytes) -> int | None:
    """Return the TIM envelope size once its block lengths are available."""
    if len(data) < 12:
        return None
    if data[:4] != b"\x10\0\0\0":
        raise ValueError("decoded stream has no TIM magic")
    flags = struct.unpack_from("<I", data, 4)[0]
    if flags not in (8, 9):
        raise ValueError(f"unexpected TIM flags {flags:#x}")
    cursor = 8
    for _ in range(2):  # Both observed modes have a CLUT and a pixel block.
        if len(data) < cursor + 4:
            return None
        block_size = struct.unpack_from("<I", data, cursor)[0]
        if not 12 <= block_size <= MAX_TIM_SIZE:
            raise ValueError(f"invalid TIM block size {block_size}")
        cursor += block_size
        if cursor > MAX_TIM_SIZE:
            raise ValueError("TIM exceeds the inspection bound")
    return cursor


def decompress_tim(source: bytes) -> tuple[bytes, int, int]:
    """Decode the observed seven-token flag groups to one complete TIM.

    Seven low flag bits are consumed LSB first: 1 is a literal and 0 is a
    two-byte backwards copy. In a copy, the first byte's top five bits give
    the length (zero means 32); its low three bits and the second byte form
    an 11-bit distance (zero means 2048). Copies may overlap.
    """
    output = bytearray()
    source_pos = 0
    target_size = None
    references = 0
    while source_pos < len(source):
        flags = source[source_pos]
        source_pos += 1
        for bit in range(7):
            if source_pos >= len(source):
                raise ValueError("compressed stream ends within a flag group")
            if flags & (1 << bit):
                output.append(source[source_pos])
                source_pos += 1
            else:
                if source_pos + 2 > len(source):
                    raise ValueError("truncated backreference")
                first, second = source[source_pos : source_pos + 2]
                source_pos += 2
                length = (first >> 3) or 32
                distance = (((first & 7) << 8) | second) or 2048
                if distance > len(output):
                    raise ValueError(
                        f"backreference distance {distance} exceeds output {len(output)}"
                    )
                references += 1
                for _ in range(length):
                    output.append(output[-distance])
            if len(output) > MAX_TIM_SIZE:
                raise ValueError("decoded stream exceeds the inspection bound")
            if target_size is None:
                target_size = declared_tim_size(output)
            if target_size is not None:
                if len(output) > target_size:
                    raise ValueError("backreference overruns the declared TIM size")
                if len(output) == target_size:
                    if tim_length(output, 0) != target_size:
                        raise ValueError("decoded TIM block geometry is invalid")
                    tail = source[source_pos:]
                    if len(tail) > 4 or any(tail):
                        raise ValueError("compressed stream has nonzero or long trailing data")
                    return bytes(output), len(tail), references
    raise ValueError("compressed stream ends before its TIM")


def tia_members(data: bytes) -> list[bytes]:
    if len(data) < 340 or struct.unpack_from("<I", data)[0] != 42:
        raise ValueError("expected a 42-member TIA directory")
    members = []
    previous_end = 340
    for index in range(42):
        offset, size = struct.unpack_from("<II", data, 4 + 8 * index)
        if offset % 4 or offset < previous_end or offset + size > len(data):
            raise ValueError(f"TIA member {index} has an invalid extent")
        if offset - previous_end > 3 or any(data[previous_end:offset]):
            raise ValueError(f"TIA member {index} has unexpected alignment bytes")
        members.append(data[offset : offset + size])
        previous_end = offset + size
    if len(data) - previous_end > 2 or any(data[previous_end:]):
        raise ValueError("TIA record has unexpected trailing bytes")
    return members


def inspect(records: list, label: str) -> dict[int, tuple]:
    summary = Counter()
    fingerprints = {}
    for record_id in range(12, 36):
        data = records[record_id].data
        members = tia_members(data) if record_id in (12, 13) else [data]
        for member_id, member in enumerate(members):
            try:
                tim, padding, references = decompress_tim(member)
            except ValueError as exc:
                raise ValueError(f"{label} record {record_id} member {member_id}: {exc}") from exc
            flags = struct.unpack_from("<I", tim, 4)[0]
            clut_size = struct.unpack_from("<I", tim, 8)[0]
            clut = struct.unpack_from("<4H", tim, 12)
            image = struct.unpack_from("<4H", tim, 8 + clut_size + 4)
            summary[("mode", flags)] += 1
            summary[("size", len(tim))] += 1
            summary[("padding", padding)] += 1
            summary["references"] += references
            fingerprints[(record_id, member_id)] = (tim, clut, image)
    print(f"{label}: {len(fingerprints)} TIMs; modes {dict(sorted((k[1], v) for k, v in summary.items() if k[0] == 'mode'))}; decoded sizes {dict(sorted((k[1], v) for k, v in summary.items() if k[0] == 'size'))}; source zero padding {dict(sorted((k[1], v) for k, v in summary.items() if k[0] == 'padding'))}; backreferences {summary['references']}")
    return fingerprints


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-ecm", type=Path, default=root / "Tekken 3 (J) [SLPS-01300]" / "Tekken 3 (J) (Track 1) [SLPS-01300].bin.ecm")
    parser.add_argument("--japan-rev1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    args = parser.parse_args()
    try:
        original, _, names = read_original(args.original_ecm)
        if names[12:14] != ["makuma00.tia", "makuma01.tia"] or not all(
            name.startswith("face_b") and name.endswith(".tiz") for name in names[14:36]
        ):
            raise ValueError("original EXE filenames do not match the inspected range")
        japan, _ = read_records(args.japan_rev1, JAPAN)
        usa, _ = read_records(args.usa, USA)
        baseline = inspect(original, "Japan original")
        for label, records in (("Japan Rev.1", japan), ("USA", usa)):
            observed = inspect(records, label)
            if observed != baseline:
                raise ValueError(f"{label} decoded TIMs differ from Japan original")
        print("All 106 decoded TIMs are byte-identical across the three releases.")
        print("TIA member 0: CLUT and image rectangles", baseline[(12, 0)][1:])
        print("TIZ record 14: CLUT and image rectangles", baseline[(14, 0)][1:])
        return 0
    except (OSError, ValueError, struct.error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
