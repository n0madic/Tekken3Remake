#!/usr/bin/env python3
"""Export decoded Tekken 3 `.tia`/`.tiz` TIMs and inspectable PNGs.

The index PNG and JSON retain the information needed to reconstruct texels.
The RGBA PNG is an opaque-draw preview: it does not emulate GPU blending.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import struct
import sys

from compare_bns import JAPAN, USA, read_records, tim_length
from compare_japan_revisions import read_original
from inspect_compressed_tim import decompress_tim, tia_members


def parse_indexed_tim(tim: bytes) -> tuple[dict, bytes, list[int]]:
    if tim_length(tim, 0) != len(tim):
        raise ValueError("invalid TIM envelope")
    flags = struct.unpack_from("<I", tim, 4)[0]
    if flags not in (8, 9):
        raise ValueError(f"unsupported TIM flags {flags:#x}")
    clut_size = struct.unpack_from("<I", tim, 8)[0]
    clut_rect = struct.unpack_from("<4H", tim, 12)
    palette_size = 16 if flags == 8 else 256
    if clut_rect[2:] != (palette_size, 1):
        raise ValueError("expected one complete horizontal palette")
    palette = list(struct.unpack_from(f"<{palette_size}H", tim, 20))
    image_offset = 8 + clut_size
    image_rect = struct.unpack_from("<4H", tim, image_offset + 4)
    pixel_width = image_rect[2] * (4 if flags == 8 else 2)
    pixel_height = image_rect[3]
    raw_pixels = tim[image_offset + 12 :]
    if flags == 8:
        indices = bytes(value for packed in raw_pixels for value in (packed & 15, packed >> 4))
    else:
        indices = raw_pixels
    if len(indices) != pixel_width * pixel_height:
        raise ValueError("indexed raster size does not match the TIM rectangle")
    return {
        "tim_flags": flags,
        "bits_per_pixel": 4 if flags == 8 else 8,
        "width_pixels": pixel_width,
        "height_pixels": pixel_height,
        "clut_vram_rect_words": clut_rect,
        "image_vram_rect_words": image_rect,
    }, indices, palette


def rgba_preview(indices: bytes, palette: list[int]) -> bytes:
    """Expand BGR555 and exact-zero transparency for opaque PSX drawing."""
    colors = []
    for word in palette:
        r = word & 31
        g = (word >> 5) & 31
        b = (word >> 10) & 31
        colors.append(((r << 3) | (r >> 2), (g << 3) | (g >> 2),
                       (b << 3) | (b >> 2), 0 if word == 0 else 255))
    return bytes(channel for index in indices for channel in colors[index])


def export_member(output_dir: Path, stem: str, original_name: str,
                  record_id: int, member_id: int, record, compressed: bytes,
                  edition: str) -> None:
    try:
        from PIL import Image
    except ImportError as exc:
        raise ValueError("Pillow is required for PNG export") from exc
    tim, source_padding, _ = decompress_tim(compressed)
    shape, indices, palette = parse_indexed_tim(tim)
    width = shape["width_pixels"]
    height = shape["height_pixels"]
    Image.frombytes("L", (width, height), indices).save(output_dir / f"{stem}.indices.png")
    Image.frombytes("RGBA", (width, height), rgba_preview(indices, palette)).save(
        output_dir / f"{stem}.preview.png"
    )
    (output_dir / f"{stem}.tim").write_bytes(tim)
    metadata = {
        "source_edition": edition,
        "original_exe_filename": original_name,
        "bns_record_id": record_id,
        "bns_lba_relative": record.lba,
        "bns_record_sha256": record.sha256,
        "member_id": member_id if record_id in (12, 13) else None,
        "compressed_member_sha256": hashlib.sha256(compressed).hexdigest(),
        "decoded_tim_sha256": hashlib.sha256(tim).hexdigest(),
        "compressed_zero_padding_bytes": source_padding,
        **shape,
        "palette_bgr555_stp_words": [f"0x{word:04x}" for word in palette],
        "stp_palette_indices": [i for i, word in enumerate(palette) if word & 0x8000],
        "preview_semantics": (
            "BGR555 expanded to 8-bit channels; CLUT word 0x0000 is transparent; "
            "all other entries are opaque. STP and GPU blend mode are retained in "
            "the palette words but are not applied in preview.png."
        ),
    }
    (output_dir / f"{stem}.json").write_text(
        json.dumps(metadata, indent=2) + "\n", encoding="utf-8"
    )


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--edition", choices=("original", "japan-rev1", "usa"), default="original")
    parser.add_argument("--record-id", type=int, choices=range(12, 36), metavar="12..35",
                        help="export one BNS record instead of all 24")
    parser.add_argument("--member-id", type=int, choices=range(42), metavar="0..41",
                        help="export one `.tia` member; requires --record-id 12 or 13")
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--original-ecm", type=Path, default=root / "Tekken 3 (J) [SLPS-01300]" / "Tekken 3 (J) (Track 1) [SLPS-01300].bin.ecm")
    parser.add_argument("--japan-rev1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--usa", type=Path, default=root / "Tekken 3 (USA)" / "Tekken 3 (USA) (Track 1).bin")
    args = parser.parse_args()
    if args.member_id is not None and args.record_id not in (12, 13):
        parser.error("--member-id requires --record-id 12 or 13")
    try:
        if args.edition == "original":
            records, _, names = read_original(args.original_ecm)
        else:
            profile, path = ((JAPAN, args.japan_rev1) if args.edition == "japan-rev1"
                             else (USA, args.usa))
            records, _ = read_records(path, profile)
            names = (["makuma00.tia", "makuma01.tia"]
                     + [f"face_b{i:02d}.tiz" for i in range(22)])
            names = [""] * 12 + names
        args.output_dir.mkdir(parents=True, exist_ok=True)
        exported = 0
        record_ids = [args.record_id] if args.record_id is not None else range(12, 36)
        for record_id in record_ids:
            record = records[record_id]
            members = tia_members(record.data) if record_id in (12, 13) else [record.data]
            member_ids = ([args.member_id] if args.member_id is not None
                          else range(len(members)))
            for member_id in member_ids:
                stem = Path(names[record_id]).stem
                if record_id in (12, 13):
                    stem += f"_{member_id:02d}"
                export_member(args.output_dir, stem, names[record_id],
                              record_id, member_id,
                              record, members[member_id], args.edition)
                exported += 1
        print(f"Exported {exported} decoded TIMs with indexed PNGs, previews and JSON to {args.output_dir}")
        return 0
    except (OSError, ValueError, struct.error) as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
