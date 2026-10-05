#!/usr/bin/env python3
"""Compare original SLPS-01300 ECM BNS records with Japan Rev.1, read only.

Only original CD sector headers and ISO Form 1 user payloads are reconstructed.
The ECM trailer checksum covers regenerated ECC/EDC bytes; verify_ecm.py checks it.
"""

from __future__ import annotations

import argparse
from array import array
from collections import Counter
import hashlib
import mmap
from pathlib import Path
import re
import struct
import sys

from compare_bns import (
    BNS_RECORD_COUNT,
    JAPAN,
    Record,
    arc_members,
    bounded_arc_candidate,
    contiguous_ranges,
    read_iso_file,
    read_records,
    signature_counts,
    strict_arc_record,
    tim_sequence,
)


class ECMImage:
    """Sector-addressable view of the observed ECM1 header + Mode 2 run pattern."""

    def __init__(self, source: mmap.mmap):
        if source[:4] != b"ECM\0":
            raise ValueError("ECM1 header missing")
        self.source = source
        self.headers = array("I")
        self.bodies = array("I")
        self.types = bytearray()
        pos = 4
        pending_header = None
        while True:
            if pos >= len(source):
                raise ValueError("ECM ended before end marker")
            code = source[pos]
            pos += 1
            run_type = code & 3
            count_minus_one = (code >> 2) & 31
            shift = 5
            while code & 0x80:
                if pos >= len(source):
                    raise ValueError("truncated ECM run length")
                code = source[pos]
                pos += 1
                count_minus_one |= (code & 0x7F) << shift
                shift += 7
                if shift > 40:
                    raise ValueError("ECM run length overflow")
            if count_minus_one == 0xFFFFFFFF:
                break
            count = count_minus_one + 1
            if run_type == 0:
                if count != 16 or pending_header is not None:
                    raise ValueError("unexpected ECM raw run; expected one 16-byte header")
                pending_header = pos
                pos += count
            elif run_type in (2, 3):
                if count != 1 or pending_header is None:
                    raise ValueError("unexpected ECM sector run")
                stored_size = 0x804 if run_type == 2 else 0x918
                if pos + stored_size > len(source):
                    raise ValueError("truncated ECM sector body")
                header = source[pending_header : pending_header + 16]
                subheader = source[pos : pos + 4]
                if header[15] != 2 or bool(subheader[2] & 0x20) != (run_type == 3):
                    raise ValueError(f"ECM sector {len(self.types)} has inconsistent Mode 2 form")
                self.headers.append(pending_header)
                self.bodies.append(pos)
                self.types.append(run_type)
                pending_header = None
                pos += stored_size
            else:
                raise ValueError("unexpected ECM Mode 1 run")
        if pending_header is not None or pos + 4 != len(source):
            raise ValueError("ECM end marker/trailer position invalid")
        self.trailer = bytes(source[pos : pos + 4])

    def __len__(self) -> int:
        return len(self.types) * 2352

    def __getitem__(self, key: slice) -> bytes:
        if not isinstance(key, slice) or key.step not in (None, 1):
            raise TypeError("ECM view supports only contiguous slices")
        start, stop, _ = key.indices(len(self))
        output = bytearray()
        while start < stop:
            sector_id, offset = divmod(start, 2352)
            header_pos = self.headers[sector_id]
            body_pos = self.bodies[sector_id]
            run_type = self.types[sector_id]
            body_size = 0x804 if run_type == 2 else 0x918
            checksum_size = 280 if run_type == 2 else 4
            sector = (
                self.source[header_pos : header_pos + 16]
                + self.source[body_pos : body_pos + 4]
                + self.source[body_pos : body_pos + body_size]
                + bytes(checksum_size)
            )
            take = min(stop - start, 2352 - offset)
            output.extend(sector[offset : offset + take])
            start += take
        return bytes(output)


def read_original(ecm_path: Path) -> tuple[list[Record], dict[str, int | str], list[str]]:
    with ecm_path.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as source:
        image = ECMImage(source)
        exe, exe_lba = read_iso_file(image, ("SLPS_013.00",))
        bns, bns_lba = read_iso_file(image, ("TEKKEN3.BNS",))
        offset = 0x14CC8
        if offset + BNS_RECORD_COUNT * 12 > len(exe):
            raise ValueError("original Japanese BNS table exceeds EXE")
        records = []
        names = []
        for record_id in range(BNS_RECORD_COUNT):
            lba, size, pointer = struct.unpack_from("<III", exe, offset + record_id * 12)
            start = lba * 2048
            end = start + size
            if end > len(bns):
                raise ValueError(f"original Japanese BNS ID {record_id} exceeds BNS")
            data = bns[start:end]
            records.append(Record(lba, size, hashlib.sha256(data).hexdigest(), data))
            name_offset = pointer - 0x80010000 + 0x800
            if not 0 <= name_offset < len(exe):
                raise ValueError(f"original BNS ID {record_id} filename pointer outside EXE")
            name_end = exe.find(b"\0", name_offset, name_offset + 64)
            if name_end < 0 or not re.fullmatch(rb"[\x20-\x7e]+", exe[name_offset:name_end]):
                raise ValueError(f"original BNS ID {record_id} filename is not NUL-terminated printable ASCII")
            names.append(exe[name_offset:name_end].decode("ascii"))
        return records, {
            "sectors": len(image.types), "exe_lba": exe_lba, "bns_lba": bns_lba,
            "bns_size": len(bns), "ecm_trailer": image.trailer.hex(),
            "ecm_sha256": hashlib.sha256(source).hexdigest(),
            "exe_sha256": hashlib.sha256(exe).hexdigest(),
            "bns_sha256": hashlib.sha256(bns).hexdigest(),
        }, names


def report(original: list[Record], rev1: list[Record], info: dict[str, int | str], names: list[str]) -> str:
    same = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.data == b.data]
    size_diff = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.size != b.size]
    same_size_diff = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.size == b.size and a.data != b.data]
    both_empty = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.size == b.size == 0]
    original_only_empty = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.size == 0 and b.size]
    rev1_only_empty = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.size and b.size == 0]
    changed_models = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.data[8:12] == b"3DMK" and a.data != b.data]
    changed_vabs = [i for i, (a, b) in enumerate(zip(original, rev1)) if a.data[:4] == b"pBAV" and a.data != b.data]
    extensions = Counter(name.rsplit(".", 1)[-1] for name in names)
    strict_arc_names = [i for i, row in enumerate(original) if strict_arc_record(row)]
    named_arc = [i for i, name in enumerate(names) if name.endswith(".arc")]
    if strict_arc_names != named_arc:
        raise ValueError("strict ARC structural IDs disagree with original filename suffixes")
    changed = sorted(set(size_diff + same_size_diff))
    lines = [
        "# Japan SLPS-01300 original vs Rev.1 BNS",
        "",
        "Original image is read directly from ECM1; user payloads and BNS records are compared in memory. `verify_ecm.py` checks the regenerated sector ECC/EDC against the ECM trailer checksum.",
        "",
        f"- Original virtual Track 1: {info['sectors']:,} sectors; ECM trailer `{info['ecm_trailer']}`.",
        f"- Original EXE ISO LBA {info['exe_lba']}; BNS LBA {info['bns_lba']}; BNS size {info['bns_size']:,} bytes.",
        f"- Original BNS signatures: {signature_counts(original)}; Rev.1: {signature_counts(rev1)}.",
        f"- Byte-identical records: {len(same)} (including {len(both_empty)} empty).",
        f"- Different size: {len(size_diff)}; IDs `{contiguous_ranges(size_diff)}`.",
        f"- Same size, different bytes: {len(same_size_diff)}; IDs `{contiguous_ranges(same_size_diff)}`.",
        f"- Empty in both: `{contiguous_ranges(both_empty)}`; original-only empty: `{contiguous_ranges(original_only_empty)}`; Rev.1-only empty: `{contiguous_ranges(rev1_only_empty)}`.",
        f"- Changed original `3DMK` records: {len(changed_models)}; changed `pBAV`: {len(changed_vabs)}.",
        f"- ARC-like bounded counts: {sum(bounded_arc_candidate(r.data) for r in original)} original, {sum(bounded_arc_candidate(r.data) for r in rev1)} Rev.1; strict counts: {sum(strict_arc_record(r) for r in original)} original, {sum(strict_arc_record(r) for r in rev1)} Rev.1.",
        f"- Third index field points to valid NUL-terminated ASCII filenames in the EXE for all 303 rows: {len(set(names))} distinct names; suffix counts `{dict(sorted(extensions.items()))}`.",
        f"- All {len(named_arc)} `.arc` names match the strict ARC structural classifier exactly. The two extra bounded candidates are `.tia` IDs 12 and 13.",
        "",
        "| Changed ID | Original EXE filename | Original bytes | Rev.1 bytes |",
        "|---:|---|---:|---:|",
        *(f"| {i} | `{names[i]}` | {original[i].size:,} | {rev1[i].size:,} |" for i in changed),
        "",
        "## Four-slot group comparison",
        "",
    ]
    for slot, label in enumerate(("3DMK", "VAB header", "five-member ARC", "opaque companion")):
        ids = list(range(71 + slot, 279, 4))
        match = [i for i in ids if original[i].data == rev1[i].data]
        lines.append(f"- Slot {slot} ({label}): {len(match)}/{len(ids)} byte-identical; changed IDs `{contiguous_ranges(sorted(set(ids)-set(match)))}`.")
    orig_arcs = [arc_members(original[i].data) for i in range(73, 278, 4)]
    rev_arcs = [arc_members(rev1[i].data) for i in range(73, 278, 4)]
    lines.extend(["", "## Nested ARC members", ""])
    for member in range(5):
        same_member = [73 + 4*n for n, (a,b) in enumerate(zip(orig_arcs, rev_arcs)) if a[member] == b[member]]
        lines.append(f"- Member {member}: {len(same_member)}/52 byte-identical; changed top-level IDs `{contiguous_ranges(sorted(set(range(73,278,4))-set(same_member)))}`.")
    tim0 = [tim_sequence(a[0]) for a in orig_arcs]
    tim1 = [tim_sequence(a[1]) for a in orig_arcs]
    lines.append(f"- Original member 0: {sum(c>0 and tail==4 and zero for c,tail,zero in tim0)}/52 parse as TIM sequence + four zero bytes.")
    lines.append(f"- Original member 1: {sum(c>0 and tail==0 for c,tail,_ in tim1)}/52 parse as exact TIM sequence.")
    return "\n".join(lines) + "\n"


def index_map(original: list[Record], names: list[str], info: dict[str, int | str]) -> str:
    lines = [
        "# Original Japan SLPS-01300 BNS filename index",
        "",
        "Each filename comes from the third word of the original 12-byte EXE index row, interpreted as a guest pointer to a NUL-terminated ASCII string. Sizes and SHA-256 values are for BNS record bytes, not an exported file.",
        "",
        f"Source ECM SHA-256: `{info['ecm_sha256']}`; extracted EXE SHA-256: `{info['exe_sha256']}`; BNS SHA-256: `{info['bns_sha256']}`. ECM trailer ECC/EDC validation: `verify_ecm.py`.",
        "",
        "| ID | Filename in EXE | BNS relative LBA | Bytes | SHA-256 |",
        "|---:|---|---:|---:|---|",
    ]
    for i, (row, name) in enumerate(zip(original, names)):
        lines.append(f"| {i} | `{name}` | {row.lba} | {row.size} | `{row.sha256}` |")
    return "\n".join(lines) + "\n"


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--original-ecm", type=Path, default=root / "Tekken 3 (J) [SLPS-01300]" / "Tekken 3 (J) (Track 1) [SLPS-01300].bin.ecm")
    parser.add_argument("--japan-rev1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--index-map", action="store_true", help="print complete original EXE filename/BNS index map")
    args = parser.parse_args()
    try:
        original, info, names = read_original(args.original_ecm)
        if args.index_map:
            sys.stdout.write(index_map(original, names, info))
        else:
            rev1, _ = read_records(args.japan_rev1, JAPAN)
            sys.stdout.write(report(original, rev1, info, names))
        return 0
    except (OSError, ValueError, struct.error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
