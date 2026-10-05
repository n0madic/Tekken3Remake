#!/usr/bin/env python3
"""Inspect character ARC member-0 TIM uploads and optionally render raw 4bpp nibbles."""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, arc_members, read_records, tim_length


ARC_IDS = range(73, 278, 4)


def split_tims(member: bytes) -> tuple[list[bytes], bytes]:
    cursor = 0
    tims = []
    while (length := tim_length(member, cursor)) is not None:
        tims.append(member[cursor : cursor + length])
        cursor += length
    return tims, member[cursor:]


def image_words(tim: bytes) -> tuple[tuple[int, int, int, int], bytes]:
    if len(tim) < 20 or struct.unpack_from("<II", tim) != (0x10, 0):
        raise ValueError("first TIM is not the observed direct-color upload profile")
    block_length, x, y, width_words, height = struct.unpack_from("<I4H", tim, 8)
    if block_length + 8 != len(tim) or block_length != 12 + 2 * width_words * height:
        raise ValueError("first TIM image word count does not fill its block")
    return (x, y, width_words, height), tim[20:]


def render_nibble_diagnostic(tim: bytes, output: Path) -> None:
    # This is a diagnostic reinterpretation of raw VRAM words, not the TIM's
    # declared direct-color pixel mode or a verified in-game palette.
    try:
        from PIL import Image
    except ImportError as error:
        raise ValueError("Pillow is required for --render-*-png") from error
    (_, _, width_words, height), words = image_words(tim)
    values = bytearray()
    for packed in words:
        values.extend(((packed & 0x0F) * 17, (packed >> 4) * 17))
    image = Image.frombytes("L", (width_words * 4, height), bytes(values))
    image = image.resize((image.width * 4, image.height * 4), Image.Resampling.NEAREST)
    image.save(output)


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--japan-track1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa-track1", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    parser.add_argument("--render-japan-png", type=Path, help="write the ID-73 first-TIM nibble diagnostic")
    parser.add_argument("--render-usa-png", type=Path, help="write the ID-73 first-TIM nibble diagnostic")
    args = parser.parse_args()
    try:
        japan, _ = read_records(args.japan_track1, JAPAN)
        usa, _ = read_records(args.usa_track1, USA)
        stats: Counter[str] = Counter()
        japanese_first_tims: dict[bytes, list[int]] = defaultdict(list)
        american_first_tims: dict[bytes, list[int]] = defaultdict(list)
        no_initial_tim_ids = []
        for arc_id in ARC_IDS:
            japanese_member = arc_members(japan[arc_id].data)[0]
            american_member = arc_members(usa[arc_id].data)[0]
            japanese_tims, japanese_tail = split_tims(japanese_member)
            american_tims, american_tail = split_tims(american_member)
            if not japanese_tims and not american_tims:
                stats["no_initial_tim"] += 1
                no_initial_tim_ids.append(arc_id)
                continue
            if not japanese_tims or len(japanese_tims) != len(american_tims):
                raise ValueError(f"ARC ID {arc_id}: regional TIM count mismatch")
            if japanese_tail != bytes(4) or american_tail != bytes(4):
                raise ValueError(f"ARC ID {arc_id}: unexpected member-0 TIM tail")
            japan_shape, _ = image_words(japanese_tims[0])
            usa_shape, _ = image_words(american_tims[0])
            if japan_shape != (80, 16, 32, 66) or usa_shape != (80, 16, 32, 120):
                raise ValueError(f"ARC ID {arc_id}: regional first-TIM shape mismatch")
            changes = tuple(
                index for index, (a, b) in enumerate(zip(japanese_tims, american_tims)) if a != b
            )
            if changes not in ((0,), (0, 1), (0, 2)):
                raise ValueError(f"ARC ID {arc_id}: unexpected regional TIM changes {changes}")
            stats["parsed_member_0"] += 1
            stats[f"changed_tim_indices_{changes}"] += 1
            japanese_first_tims[japanese_tims[0]].append(arc_id)
            american_first_tims[american_tims[0]].append(arc_id)
        stats["distinct_japan_first_tim"] = len(japanese_first_tims)
        stats["distinct_usa_first_tim"] = len(american_first_tims)
        print("# Character ARC member-0 first TIM, Japan Rev.1 and USA")
        for key in ("parsed_member_0", "no_initial_tim", "distinct_japan_first_tim", "distinct_usa_first_tim"):
            print(f"- {key}: {stats[key]}")
        print(f"- no-initial-TIM ARC IDs: {', '.join(map(str, no_initial_tim_ids))}")
        for key, value in sorted((key, value) for key, value in stats.items() if key.startswith("changed_tim_indices_")):
            print(f"- {key}: {value}")
        if args.render_japan_png:
            render_nibble_diagnostic(split_tims(arc_members(japan[73].data)[0])[0][0], args.render_japan_png)
            print(f"- Japan nibble diagnostic: {args.render_japan_png}")
        if args.render_usa_png:
            render_nibble_diagnostic(split_tims(arc_members(usa[73].data)[0])[0][0], args.render_usa_png)
            print(f"- USA nibble diagnostic: {args.render_usa_png}")
    except (OSError, ValueError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
