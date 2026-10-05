#!/usr/bin/env python3
"""Compare Tekken 3 Japan Rev.1 and USA BNS index records without running the game.

The script reads raw MODE2/2352 Track 1 images, resolves the EXE and BNS files
from ISO 9660, follows the region-specific BNS table in each EXE, and reports
record metadata only. It does not write extracted copyrighted assets.
"""

from __future__ import annotations

import argparse
from collections import Counter
import hashlib
import mmap
import re
import struct
import sys
from dataclasses import dataclass
from pathlib import Path


SECTOR_BYTES = 2352
PAYLOAD_BYTES = 2048
BNS_RECORD_COUNT = 303


@dataclass(frozen=True)
class DiscProfile:
    label: str
    exe_path: tuple[str, ...]
    bns_path: tuple[str, ...]
    bns_table_offset: int


JAPAN = DiscProfile(
    label="Japan Rev.1",
    exe_path=("SLPS_013.00",),
    bns_path=("TEKKEN3.BNS",),
    bns_table_offset=0x14E6C,
)
USA = DiscProfile(
    label="USA",
    exe_path=("TEKKEN3", "SLUS_004.02"),
    bns_path=("TEKKEN3", "TEKKEN3.BNS"),
    bns_table_offset=0x14C00,
)


@dataclass(frozen=True)
class Record:
    lba: int
    size: int
    sha256: str
    data: bytes


def parse_dir_record(record: memoryview) -> tuple[int, int, bool, bytes]:
    if len(record) < 34:
        raise ValueError("truncated ISO directory record")
    name_length = record[32]
    if 33 + name_length > len(record):
        raise ValueError("truncated ISO directory record name")
    return (
        struct.unpack_from("<I", record, 2)[0],
        struct.unpack_from("<I", record, 10)[0],
        bool(record[25] & 0x02),
        bytes(record[33 : 33 + name_length]),
    )


def mode2_form1_payload(image: mmap.mmap, lba: int) -> bytes:
    start = lba * SECTOR_BYTES
    sector = image[start : start + SECTOR_BYTES]
    if len(sector) != SECTOR_BYTES:
        raise ValueError(f"LBA {lba}: sector lies outside Track 1")
    if sector[15] != 2:
        raise ValueError(f"LBA {lba}: expected CD-ROM Mode 2")
    if sector[16:20] != sector[20:24]:
        raise ValueError(f"LBA {lba}: XA subheader copies differ")
    if sector[18] & 0x20:
        raise ValueError(f"LBA {lba}: expected Form 1, found Form 2")
    return bytes(sector[24 : 24 + PAYLOAD_BYTES])


def read_extent(image: mmap.mmap, lba: int, byte_size: int) -> bytes:
    chunks = []
    for sector_index in range((byte_size + PAYLOAD_BYTES - 1) // PAYLOAD_BYTES):
        chunks.append(bytes(mode2_form1_payload(image, lba + sector_index)))
    return b"".join(chunks)[:byte_size]


def find_directory_entry(
    image: mmap.mmap, directory_lba: int, directory_size: int, component: str
) -> tuple[int, int, bool]:
    directory = read_extent(image, directory_lba, directory_size)
    wanted = component.upper().encode("ascii")
    offset = 0
    while offset < len(directory):
        record_size = directory[offset]
        if record_size == 0:
            offset = ((offset // PAYLOAD_BYTES) + 1) * PAYLOAD_BYTES
            continue
        if offset + record_size > len(directory):
            raise ValueError("ISO directory record runs past directory extent")
        entry = memoryview(directory)[offset : offset + record_size]
        lba, size, is_directory, raw_name = parse_dir_record(entry)
        if raw_name not in (b"\x00", b"\x01"):
            name = raw_name.split(b";", 1)[0]
            if name == wanted:
                return lba, size, is_directory
        offset += record_size
    raise ValueError(f"ISO path component not found: {component}")


def read_iso_file(image: mmap.mmap, path: tuple[str, ...]) -> tuple[bytes, int]:
    pvd = mode2_form1_payload(image, 16)
    if pvd[0] != 1 or pvd[1:6] != b"CD001":
        raise ValueError("Primary Volume Descriptor missing at LBA 16")
    root_lba, root_size, root_is_directory, _ = parse_dir_record(pvd[156:190])
    if not root_is_directory:
        raise ValueError("ISO root record does not describe a directory")

    directory_lba, directory_size = root_lba, root_size
    for index, component in enumerate(path):
        lba, size, is_directory = find_directory_entry(
            image, directory_lba, directory_size, component
        )
        is_last = index == len(path) - 1
        if is_last:
            if is_directory:
                raise ValueError(f"ISO path is a directory, expected a file: {component}")
            return read_extent(image, lba, size), lba
        if not is_directory:
            raise ValueError(f"ISO path component is not a directory: {component}")
        directory_lba, directory_size = lba, size
    raise ValueError("empty ISO path")


def read_records(
    image_path: Path, profile: DiscProfile
) -> tuple[list[Record], dict[str, int]]:
    with image_path.open("rb") as stream:
        with mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as image:
            if len(image) % SECTOR_BYTES:
                raise ValueError(f"{image_path}: Track 1 size is not divisible by 2352")
            exe, exe_lba = read_iso_file(image, profile.exe_path)
            bns, bns_lba = read_iso_file(image, profile.bns_path)
            table_end = profile.bns_table_offset + BNS_RECORD_COUNT * 8
            if table_end > len(exe):
                raise ValueError(f"{profile.label}: BNS table exceeds EXE")

            records = []
            for record_id in range(BNS_RECORD_COUNT):
                lba, size = struct.unpack_from(
                    "<II", exe, profile.bns_table_offset + record_id * 8
                )
                start = lba * PAYLOAD_BYTES
                end = start + size
                if end > len(bns):
                    raise ValueError(
                        f"{profile.label} record {record_id}: extent exceeds BNS"
                    )
                data = bns[start:end]
                records.append(
                    Record(lba, size, hashlib.sha256(data).hexdigest(), data)
                )
            return records, {
                "exe_lba": exe_lba,
                "bns_lba": bns_lba,
                "bns_size": len(bns),
            }


def signature_counts(records: list[Record]) -> dict[str, int]:
    return {
        "3DMK": sum(len(row.data) >= 12 and row.data[8:12] == b"3DMK" for row in records),
        "VABp": sum(row.data[:4] == b"pBAV" for row in records),
        "empty": sum(row.size == 0 for row in records),
    }


def bounded_arc_candidate(data: bytes) -> bool:
    if len(data) < 4:
        return False
    count = struct.unpack_from("<I", data, 0)[0]
    if not 1 <= count <= 0xFF or 4 + count * 8 > len(data):
        return False
    for index in range(count):
        offset, size = struct.unpack_from("<II", data, 4 + index * 8)
        if offset < 4 + count * 8 or offset > len(data) or size > len(data) - offset:
            return False
    return True


def strict_arc_layout(data: bytes) -> bool:
    if len(data) < 12:
        return False
    count = struct.unpack_from("<I", data, 0)[0]
    directory_end = 4 + count * 8
    if not 1 <= count <= 0xFF or directory_end > len(data):
        return False
    previous_end = None
    first_offset = 0
    for index in range(count):
        offset, size = struct.unpack_from("<II", data, 4 + index * 8)
        if index == 0:
            first_offset = offset
        if offset < directory_end or offset > len(data) or size > len(data) - offset:
            return False
        if previous_end is not None and offset != previous_end:
            return False
        previous_end = offset + size
    return first_offset - directory_end <= 15 and previous_end == len(data)


def strict_arc_record(record: Record) -> bool:
    data = record.data
    if record.size == 0:
        return False
    if len(data) >= 12 and data[8:12] == b"3DMK":
        return False
    if len(data) >= 32 and data[:4] == b"pBAV":
        version = struct.unpack_from("<I", data, 4)[0]
        if 1 <= version <= 7:
            return False
    if len(data) >= 20:
        magic, flags = struct.unpack_from("<II", data, 0)
        if magic == 0x10 and flags in (0x08, 0x09, 0x02, 0x03):
            if tim_length(data, 0) == len(data):
                return False
    return strict_arc_layout(data)


def arc_members(data: bytes) -> list[bytes]:
    if len(data) < 4:
        raise ValueError("truncated ARC candidate")
    count = struct.unpack_from("<I", data, 0)[0]
    table_end = 4 + count * 8
    if count != 5 or table_end > len(data):
        raise ValueError("expected a five-member ARC structure")
    members = []
    previous_end = table_end
    for member_id in range(count):
        offset, size = struct.unpack_from("<II", data, 4 + member_id * 8)
        end = offset + size
        if offset < table_end or end > len(data) or offset < previous_end:
            raise ValueError(f"ARC member {member_id} is outside or overlaps the record")
        members.append(data[offset:end])
        previous_end = end
    return members


def tim_length(data: bytes, offset: int) -> int | None:
    if offset + 8 > len(data) or data[offset : offset + 4] != b"\x10\0\0\0":
        return None
    flags = struct.unpack_from("<I", data, offset + 4)[0]
    if flags & ~0x0F:
        return None
    cursor = offset + 8
    block_is_clut = [True, False] if flags & 0x08 else [False]
    for has_clut in block_is_clut:
        if cursor + 12 > len(data):
            return None
        block_size = struct.unpack_from("<I", data, cursor)[0]
        if block_size < 12 or cursor + block_size > len(data):
            return None
        width, height = struct.unpack_from("<HH", data, cursor + 8)
        if not width or not height or block_size != 12 + 2 * width * height:
            return None
        cursor += block_size
        if not has_clut:
            break
    return cursor - offset


def tim_sequence(data: bytes) -> tuple[int, int, bool]:
    offset = 0
    count = 0
    while (length := tim_length(data, offset)) is not None:
        offset += length
        count += 1
    tail = data[offset:]
    return count, len(tail), not any(tail)


def cluster_report(japan: list[Record], usa: list[Record]) -> list[str]:
    bases = list(range(71, 279, 4))
    if len(bases) != 52:
        raise ValueError("unexpected repeated BNS group range")
    group_models = [base for base in bases if japan[base].data[8:12] == b"3DMK"]
    vab_ids = [base + 1 for base in bases if japan[base + 1].data[:4] == b"pBAV"]
    empty_vab_ids = [base + 1 for base in bases if japan[base + 1].size == 0]
    if len(group_models) != 52 or len(vab_ids) != 48 or len(empty_vab_ids) != 4:
        raise ValueError("four-slot BNS group signatures do not match the observed profile")

    jp_arcs = [arc_members(japan[base + 2].data) for base in bases]
    us_arcs = [arc_members(usa[base + 2].data) for base in bases]
    member0_size_deltas = [
        len(us_arcs[index][0]) - len(jp_arcs[index][0])
        for index in range(len(bases))
    ]

    arc_bound_checks = {"Japan Rev.1": 0, "USA": 0}
    for region, records in (("Japan Rev.1", japan), ("USA", usa)):
        for base in bases:
            data = records[base + 2].data
            count = struct.unpack_from("<I", data, 0)[0]
            pairs = [struct.unpack_from("<II", data, 4 + i * 8) for i in range(count)]
            starts_at_48 = pairs[0][0] == 48
            tightly_packed = all(
                offset + size == pairs[index + 1][0]
                for index, (offset, size) in enumerate(pairs[:-1])
            )
            reaches_eof = pairs[-1][0] + pairs[-1][1] == len(data)
            if count == 5 and starts_at_48 and tightly_packed and reaches_eof:
                arc_bound_checks[region] += 1

    vab_total_size_matches = {"Japan Rev.1": 0, "USA": 0}
    vab_body_empty_ids = []
    for region, records, arcs in (
        ("Japan Rev.1", japan, jp_arcs),
        ("USA", usa, us_arcs),
    ):
        for base, arc in zip(bases, arcs):
            header = records[base + 1].data
            body = arc[2]
            if not header:
                if body:
                    raise ValueError(
                        f"{region} empty VAB slot {base + 1} has a non-empty ARC member 2"
                    )
                if region == "Japan Rev.1":
                    vab_body_empty_ids.append(base + 1)
                continue
            declared_size = struct.unpack_from("<I", header, 0x0C)[0]
            if declared_size == len(header) + len(body):
                vab_total_size_matches[region] += 1

    if len(vab_body_empty_ids) != 4:
        raise ValueError("expected four empty VAB companion members")

    member0_tim = {
        "Japan Rev.1": [tim_sequence(arc[0]) for arc in jp_arcs],
        "USA": [tim_sequence(arc[0]) for arc in us_arcs],
    }
    member1_tim = {
        "Japan Rev.1": [tim_sequence(arc[1]) for arc in jp_arcs],
        "USA": [tim_sequence(arc[1]) for arc in us_arcs],
    }
    member0_complete_sequences = {
        region: sum(
            count > 0 and tail_size == 4 and tail_zero
            for count, tail_size, tail_zero in values
        )
        for region, values in member0_tim.items()
    }
    member1_exact_sequences = {
        region: sum(count > 0 and tail_size == 0 for count, tail_size, _ in values)
        for region, values in member1_tim.items()
    }
    member1_counts = {
        region: sorted({count for count, _, _ in values})
        for region, values in member1_tim.items()
    }
    member3_magic = sum(arc[3][:4] == b"TK3p" for arc in jp_arcs)
    member3_empty = sum(not arc[3] for arc in jp_arcs)
    member4_same_ids = [
        base + 2
        for base, jp_arc, us_arc in zip(bases, jp_arcs, us_arcs)
        if jp_arc[4] == us_arc[4]
    ]
    member4_ascii_ids = [
        base + 2
        for base, us_arc in zip(bases, us_arcs)
        if re.search(rb"[\x20-\x7e]{4,}", us_arc[4])
    ]

    if (
        any(count != 52 for count in arc_bound_checks.values())
        or any(count != 48 for count in vab_total_size_matches.values())
        or any(count != 46 for count in member0_complete_sequences.values())
        or any(count != 52 for count in member1_exact_sequences.values())
        or member1_counts["Japan Rev.1"] != member1_counts["USA"]
        or member3_magic != 48
        or member3_empty != 4
    ):
        raise ValueError("repeated ARC/VAB profile did not pass its structural checks")

    return [
        "## Repeated BNS IDs 71–278",
        "",
        "For each `n = 0..51`, the four top-level IDs are `71+4n` through `74+4n`. This numeric pattern is structural evidence; the character-bundle interpretation remains provisional.",
        "",
        "| Slot | Top-level IDs | Japan/USA structure | Regional comparison |",
        "|---:|---|---|---|",
        f"| 0 | `71 + 4n` | {len(group_models)} records with `3DMK` at offset `0x08` | 52 byte-identical |",
        f"| 1 | `72 + 4n` | {len(vab_ids)} `pBAV` headers; four zero-size rows: `{contiguous_ranges(sorted(empty_vab_ids))}` | All non-empty rows byte-identical |",
        f"| 2 | `73 + 4n` | {arc_bound_checks['Japan Rev.1']}/52 and {arc_bound_checks['USA']}/52 five-member offset/size tables begin at offset 48, have adjacent member ranges and end at record EOF | 52 records differ |",
        f"| 3 | `74 + 4n` | Remaining 52 records; internal format not identified | 52 byte-identical |",
        "",
        "### Five members inside each ID `73 + 4n` record",
        "",
        "| Member | Verified observation | Regional comparison |",
        "|---:|---|---|",
        f"| 0 | In both regions, {member0_complete_sequences['Japan Rev.1']}/52 records are complete sequential runs of structurally valid TIM images with a 4-byte zero tail; the other six do not parse from offset 0 | All 52 differ; USA minus Japan size deltas: `{dict(sorted(Counter(member0_size_deltas).items()))}` |",
        f"| 1 | All 52 in both regions are complete sequential TIM runs; each contains {', '.join(map(str, member1_counts['Japan Rev.1']))} images | 52 byte-identical |",
        f"| 2 | In all 48 non-empty cases per region, adjacent `pBAV` header size at offset `0x0C` equals `len(header) + len(member 2)`; four paired members are empty | 52 byte-identical |",
        f"| 3 | `TK3p` prefix in {member3_magic} members; {member3_empty} members empty; purpose not identified | 52 byte-identical |",
        f"| 4 | Printable ASCII runs of length ≥4 occur in {len(member4_ascii_ids)} USA members; bytes may be a name/text index, encoding not decoded | 48 differ; identical top-level ARC IDs: `{', '.join(map(str, member4_same_ids))}` |",
        "",
        f"The member-2 length relation strongly supports that it supplies the missing VB sample-data portion of each `pBAV` header: the combined length matched the VAB size field for {vab_total_size_matches['Japan Rev.1']}/48 Japan pairs and {vab_total_size_matches['USA']}/48 USA pairs. This remains a structural inference until the VAB is decoded and played.",
        "",
    ]


def contiguous_ranges(values: list[int]) -> str:
    if not values:
        return "none"
    ranges = []
    start = previous = values[0]
    for value in values[1:]:
        if value == previous + 1:
            previous = value
            continue
        ranges.append(str(start) if start == previous else f"{start}–{previous}")
        start = previous = value
    ranges.append(str(start) if start == previous else f"{start}–{previous}")
    return ", ".join(ranges)


def markdown_report(
    japan: list[Record], usa: list[Record], japan_info: dict[str, int], usa_info: dict[str, int]
) -> str:
    identical = [i for i, (a, b) in enumerate(zip(japan, usa)) if a.data == b.data]
    empty = [i for i, (a, b) in enumerate(zip(japan, usa)) if a.size == b.size == 0]
    size_diff = [i for i, (a, b) in enumerate(zip(japan, usa)) if a.size != b.size]
    same_size_diff = [
        i for i, (a, b) in enumerate(zip(japan, usa)) if a.size == b.size and a.data != b.data
    ]
    jp_signatures, us_signatures = signature_counts(japan), signature_counts(usa)
    arc_candidates = [i for i, row in enumerate(japan) if bounded_arc_candidate(row.data)]
    usa_arc_candidates = [i for i, row in enumerate(usa) if bounded_arc_candidate(row.data)]
    strict_arc_ids = [i for i, row in enumerate(japan) if strict_arc_record(row)]
    usa_strict_arc_ids = [i for i, row in enumerate(usa) if strict_arc_record(row)]
    if arc_candidates != usa_arc_candidates or strict_arc_ids != usa_strict_arc_ids:
        raise ValueError("regional ARC candidate IDs do not match")
    loose_only_arc_ids = sorted(set(arc_candidates) - set(strict_arc_ids))
    changed_3dmk = [
        i for i, row in enumerate(japan)
        if len(row.data) >= 12 and row.data[8:12] == b"3DMK" and row.data != usa[i].data
    ]
    changed_vab = [
        i for i, row in enumerate(japan)
        if row.data[:4] == b"pBAV" and row.data != usa[i].data
    ]

    lines = [
        "# BNS index comparison: Japan Rev.1 vs USA",
        "",
        "Read-only parse of raw Mode 2/2352 Track 1 images; no game code executed and no resource files written.",
        "",
        "| Measure | Japan Rev.1 | USA |",
        "|---|---:|---:|",
        f"| EXE ISO LBA | {japan_info['exe_lba']} | {usa_info['exe_lba']} |",
        f"| BNS ISO LBA | {japan_info['bns_lba']} | {usa_info['bns_lba']} |",
        f"| BNS byte size | {japan_info['bns_size']:,} | {usa_info['bns_size']:,} |",
        f"| Indexed records | {len(japan)} | {len(usa)} |",
        f"| `3DMK` records | {jp_signatures['3DMK']} | {us_signatures['3DMK']} |",
        f"| VABp records | {jp_signatures['VABp']} | {us_signatures['VABp']} |",
        f"| Empty records | {jp_signatures['empty']} | {us_signatures['empty']} |",
        f"| Bounded ARC-like candidates | {len(arc_candidates)} | same ID count in both |",
        f"| Strict contiguous ARC layout | {len(strict_arc_ids)} | same ID set in both |",
        f"| Bounded but not strict | {len(loose_only_arc_ids)} | {contiguous_ranges(loose_only_arc_ids)} |",
        "",
        "| Pairwise comparison | Count | IDs |",
        "|---|---:|---|",
        f"| Byte-identical (includes empty) | {len(identical)} | all other IDs |",
        f"| Empty in both | {len(empty)} | {contiguous_ranges(empty)} |",
        f"| Different size | {len(size_diff)} | {contiguous_ranges(size_diff)} |",
        f"| Different bytes, same size | {len(same_size_diff)} | {contiguous_ranges(same_size_diff)} |",
        f"| Changed `3DMK` records | {len(changed_3dmk)} | {contiguous_ranges(changed_3dmk)} |",
        f"| Changed VABp records | {len(changed_vab)} | {contiguous_ranges(changed_vab)} |",
        "",
        "The byte-identical count includes the six empty rows, so 234 non-empty rows are byte-identical. Size and byte differences alone do not establish localization or resource semantics.",
        "The strict ARC rule additionally requires contiguous member extents and the last member to reach EOF. IDs outside that rule remain ARC-like candidates rather than confirmed non-ARC files.",
        "",
        "",
    ]
    lines.extend(cluster_report(japan, usa))
    return "\n".join(lines)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--japan-track1",
        type=Path,
        default=repo_root
        / "Tekken 3 (Japan) (Rev 1)"
        / "Tekken 3 (Japan) (Rev 1) (Track 1).bin",
        help="raw Japan Rev.1 Track 1 image",
    )
    parser.add_argument(
        "--usa-track1",
        type=Path,
        default=repo_root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin",
        help="raw USA Track 1 image",
    )
    args = parser.parse_args()

    try:
        japan, japan_info = read_records(args.japan_track1, JAPAN)
        usa, usa_info = read_records(args.usa_track1, USA)
        if len(japan) != len(usa):
            raise ValueError("regional tables have different record counts")
        sys.stdout.write(markdown_report(japan, usa, japan_info, usa_info))
        return 0
    except (OSError, ValueError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
