#!/usr/bin/env python3
"""Validate raw move-name/command pairs in character ARC member 4."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path
import sys

from compare_bns import JAPAN, USA, arc_members, read_records


ARC_IDS = range(73, 278, 4)


def normalize_japanese_command_tokens(command: bytes) -> bytes:
    """Apply only the two locally supported Japan-to-USA token-bank shifts."""
    return bytes(
        value - 0x3D if 0xBD <= value <= 0xCC else
        value - 0x40 if (0xD2 <= value <= 0xDB or 0xDD <= value <= 0xDF) else value
        for value in command
    )


def parse_move_pairs(member: bytes, record_id: int) -> tuple[tuple[bytes, bytes], ...]:
    """Return raw byte strings; glyph and command-token decoding is separate."""
    if not member:
        return ()
    pair_count = member[0]
    if not pair_count:
        raise ValueError(f"ARC ID {record_id}: nonempty member has zero pairs")
    cursor = 1
    fields = []
    for field_id in range(pair_count * 2):
        end = member.find(b"\0", cursor)
        if end < 0:
            raise ValueError(f"ARC ID {record_id}: missing terminator for field {field_id}")
        value = member[cursor:end]
        if not value:
            raise ValueError(f"ARC ID {record_id}: empty field {field_id}")
        fields.append(value)
        cursor = end + 1
    pad = member[cursor:]
    if len(pad) != (-cursor) % 4 or pad != bytes([0xAB]) * len(pad):
        raise ValueError(f"ARC ID {record_id}: invalid final alignment bytes")
    return tuple(zip(fields[::2], fields[1::2]))


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--japan-track1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa-track1", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    args = parser.parse_args()
    try:
        japan, _ = read_records(args.japan_track1, JAPAN)
        usa, _ = read_records(args.usa_track1, USA)
        stats: Counter[str] = Counter()
        japanese_sets: dict[bytes, list[int]] = defaultdict(list)
        american_sets: dict[bytes, list[int]] = defaultdict(list)
        for record_id in ARC_IDS:
            japanese = arc_members(japan[record_id].data)[4]
            american = arc_members(usa[record_id].data)[4]
            japanese_pairs = parse_move_pairs(japanese, record_id)
            american_pairs = parse_move_pairs(american, record_id)
            if len(japanese_pairs) != len(american_pairs):
                raise ValueError(f"ARC ID {record_id}: regional pair counts differ")
            if japanese == american and japanese:
                raise ValueError(f"ARC ID {record_id}: expected localized member bytes")
            stats["arc_records"] += 1
            stats["empty_members" if not japanese else "nonempty_members"] += 1
            stats["pairs_with_repeated_sets"] += len(japanese_pairs)
            if japanese:
                stats[f"pair_count_{len(japanese_pairs)}"] += 1
                japanese_sets[japanese].append(record_id)
                american_sets[american].append(record_id)
        japanese_groups = sorted(tuple(ids) for ids in japanese_sets.values())
        american_groups = sorted(tuple(ids) for ids in american_sets.values())
        if japanese_groups != american_groups:
            raise ValueError("Japan/USA localized member reuse groups differ")
        stats["distinct_localized_sets"] = len(japanese_groups)
        stats["pairs_in_distinct_sets"] = sum(len(parse_move_pairs(member, ids[0])) for member, ids in japanese_sets.items())
        for japanese_member, ids in japanese_sets.items():
            american_member = arc_members(usa[ids[0]].data)[4]
            for (_, japanese_command), (_, american_command) in zip(
                parse_move_pairs(japanese_member, ids[0]),
                parse_move_pairs(american_member, ids[0]),
            ):
                normalized = normalize_japanese_command_tokens(japanese_command)
                if normalized == american_command:
                    stats["token_shift_exact_commands"] += 1
                    stats["token_shift_matching_bytes"] += sum(
                        left != right for left, right in zip(japanese_command, normalized)
                    )
        print("# Character ARC member 4 move text, Japan Rev.1 and USA")
        for key in ("arc_records", "nonempty_members", "empty_members", "pairs_with_repeated_sets", "distinct_localized_sets", "pairs_in_distinct_sets", "token_shift_exact_commands", "token_shift_matching_bytes"):
            print(f"- {key}: {stats[key]}")
        print("- pair-count distribution (members):")
        for count in sorted({int(key.removeprefix("pair_count_")) for key in stats if key.startswith("pair_count_")}):
            print(f"  - {count} pairs: {stats[f'pair_count_{count}']}")
        print("- shared three-record sets (BNS ARC IDs):")
        for ids in japanese_groups:
            if len(ids) == 3:
                print(f"  - {', '.join(map(str, ids))}")
    except (OSError, ValueError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
