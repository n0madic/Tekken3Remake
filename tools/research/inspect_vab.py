#!/usr/bin/env python3
"""Validate local Tekken 3 pBAV headers and paired ARC SPU-ADPCM bodies."""

from __future__ import annotations

import argparse
from collections import Counter
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, arc_members, read_records


GROUP_BASES = range(71, 279, 4)
PROGRAM_TABLE_OFFSET = 0x20
PROGRAM_TABLE_BYTES = 128 * 16
TONE_TABLE_OFFSET = PROGRAM_TABLE_OFFSET + PROGRAM_TABLE_BYTES


def inspect(header: bytes, body: bytes, bns_id: int) -> Counter[str]:
    stats: Counter[str] = Counter()
    if not header:
        if body:
            raise ValueError(f"BNS ID {bns_id}: absent VH has a nonempty VB")
        stats["absent_banks"] = 1
        return stats
    if len(header) < TONE_TABLE_OFFSET + 512 or header[:4] != b"pBAV":
        raise ValueError(f"BNS ID {bns_id}: invalid VH signature or length")

    version, bank_id, file_size = struct.unpack_from("<3I", header, 4)
    reserved0, program_count, tone_count, vag_count = struct.unpack_from("<4H", header, 0x10)
    master_volume, master_pan, attr1, attr2 = struct.unpack_from("<4B", header, 0x18)
    reserved1 = struct.unpack_from("<I", header, 0x1C)[0]
    if (
        version != 7
        or bank_id != 0
        or file_size != len(header) + len(body)
        or reserved0 != 0xEEEE
        or reserved1 != 0xFFFFFFFF
        or not 0 < program_count <= 128
        or not 0 < tone_count <= 2048
        or not 0 < vag_count <= 254
    ):
        raise ValueError(f"BNS ID {bns_id}: unexpected VabHdr fields")
    expected_header = TONE_TABLE_OFFSET + program_count * 16 * 32 + 256 * 2
    if len(header) != expected_header:
        raise ValueError(f"BNS ID {bns_id}: VH table lengths do not reach EOF")
    stats["banks"] = 1
    stats["programs"] = program_count
    stats["tones"] = tone_count
    stats["vags"] = vag_count

    programs = []
    for program_id in range(128):
        offset = PROGRAM_TABLE_OFFSET + program_id * 16
        tones = header[offset]
        if tones > 16:
            raise ValueError(f"BNS ID {bns_id}: program {program_id} has too many tones")
        if tones:
            programs.append((program_id, tones))
    if len(programs) != program_count or sum(tones for _, tones in programs) != tone_count:
        raise ValueError(f"BNS ID {bns_id}: program-tone counts disagree with VabHdr")

    for block_id, (program_id, tones) in enumerate(programs):
        for tone_id in range(16):
            offset = TONE_TABLE_OFFSET + (block_id * 16 + tone_id) * 32
            tone_program, vag_id = struct.unpack_from("<hh", header, offset + 20)
            if tone_program != program_id:
                raise ValueError(f"BNS ID {bns_id}: tone program reference mismatch")
            if tone_id < tones:
                if not 0 <= vag_id <= vag_count:
                    raise ValueError(f"BNS ID {bns_id}: tone VAG reference out of range")
                stats["tone_without_vag"] += vag_id == 0
            elif vag_id:
                raise ValueError(f"BNS ID {bns_id}: unused tone slot references a VAG")

    size_table = struct.unpack_from("<256H", header, expected_header - 512)
    if size_table[0] or any(size_table[vag_count + 1 :]):
        raise ValueError(f"BNS ID {bns_id}: unexpected VAG size-table entries")
    body_offset = 0
    for vag_id in range(1, vag_count + 1):
        byte_count = size_table[vag_id] << 3
        if byte_count < 16 or byte_count % 16 or body_offset + byte_count > len(body):
            raise ValueError(f"BNS ID {bns_id}: VAG {vag_id} size invalid")
        sample = body[body_offset : body_offset + byte_count]
        if sample[:16] != bytes(16):
            raise ValueError(f"BNS ID {bns_id}: VAG {vag_id} has no observed zero lead-in frame")
        markers = []
        for frame_offset in range(0, byte_count, 16):
            predictor_shift, flags = sample[frame_offset : frame_offset + 2]
            if predictor_shift >> 4 > 4 or predictor_shift & 0x0F > 12 or flags & ~7:
                raise ValueError(f"BNS ID {bns_id}: VAG {vag_id} frame header invalid")
            stats[f"frame_flag_{flags}"] += 1
            stats["adpcm_frames"] += 1
            if flags & 4:
                markers.append((frame_offset // 16, flags))
        terminal = sample[-15]
        if terminal == 7:
            if sample[-16:] != b"\x00\x07" + b"\x77" * 14 or sample[-31] != 1 or markers != [(1, 4), (byte_count // 16 - 1, 7)]:
                raise ValueError(f"BNS ID {bns_id}: VAG {vag_id} has invalid observed one-shot ending")
            stats["one_shot_samples"] += 1
        elif terminal == 3:
            if len(markers) != 1 or markers[0][1] != 6:
                raise ValueError(f"BNS ID {bns_id}: VAG {vag_id} has invalid observed loop markers")
            stats["looped_samples"] += 1
        else:
            raise ValueError(f"BNS ID {bns_id}: VAG {vag_id} has unexpected terminal flag")
        stats["adpcm_bytes"] += byte_count
        body_offset += byte_count
    if body_offset != len(body):
        raise ValueError(f"BNS ID {bns_id}: VAG size table does not consume VB")
    return stats


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
        for base in GROUP_BASES:
            japan_header = japan[base + 1].data
            usa_header = usa[base + 1].data
            japan_body = arc_members(japan[base + 2].data)[2]
            usa_body = arc_members(usa[base + 2].data)[2]
            if japan_header != usa_header or japan_body != usa_body:
                raise ValueError(f"BNS ID {base + 1}: regional VH/VB mismatch")
            total.update(inspect(japan_header, japan_body, base + 1))
        print("# Tekken 3 VH/VB bank validation, Japan Rev.1 and USA")
        for name in ("banks", "absent_banks", "programs", "tones", "vags", "tone_without_vag", "one_shot_samples", "looped_samples", "adpcm_frames", "adpcm_bytes"):
            print(f"- {name}: {total[name]:,}")
    except (OSError, ValueError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
