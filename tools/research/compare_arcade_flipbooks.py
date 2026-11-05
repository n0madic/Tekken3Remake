#!/usr/bin/env python3
"""Check which arcade effect flipbook the converter gives each PlayStation flipbook.

Converts the effects twice, with and without the arcade's set, and reduces every arcade strip's
64 × 64 frames to 32 × 32: each PlayStation frame is compared with the frames of every distinct
arcade flipbook. The converter's choice must be the closest, in colour, over the frames it has
in common (docs/research/arcade/README.md#effect-flipbooks). The output prints the distance (mean
difference of 0–255 channels), the next flipbook's, and the arcade frame of the first PlayStation
frames, which shows dropped frames.

Usage: python3 tools/research/compare_arcade_flipbooks.py --image <disc> [--zip tekken3_mame.zip]
"""

from __future__ import annotations

import argparse
import json
import sys
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "remake_import"))

import arcade  # noqa: E402
import effects  # noqa: E402
from common import Disc, Output  # noqa: E402

PS_FRAME, ARCADE_FRAME = 32, 64


def frames(path: Path, count: int, size: int) -> np.ndarray:
    """A strip's frames as RGB, transparent texels black (as additive drawing shows them)."""
    pixels = np.asarray(Image.open(path).convert("RGBA"), dtype=np.float32)
    rgb = pixels[..., :3] * (pixels[..., 3:] > 0)
    return np.stack([rgb[:, size * k:size * (k + 1)] for k in range(count)])


def reduced(strip: np.ndarray) -> np.ndarray:
    return (strip[:, ::2, ::2] + strip[:, 1::2, ::2] + strip[:, ::2, 1::2] + strip[:, 1::2, 1::2]) / 4


def entries(table: dict) -> dict[str, dict]:
    return {e["name"]: e for e in (*table["system"], *table["enbu"], *table["costumes"].values())}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--image", type=Path, required=True)
    parser.add_argument("--zip", type=Path, default=Path("tekken3_mame.zip"))
    args = parser.parse_args()
    disc = Disc.open(args.image).canonical()
    arc = arcade.open_set(args.zip)
    failed = 0
    with tempfile.TemporaryDirectory() as tmp:
        ps_dir, arcade_dir = Path(tmp, "ps"), Path(tmp, "arcade")
        effects.convert(disc, Output(ps_dir))
        effects.convert(disc, Output(arcade_dir), arc)
        ps = entries(json.loads((ps_dir / "effects/effects.json").read_text()))
        converted = entries(json.loads((arcade_dir / "effects/effects.json").read_text()))
        books = {name: reduced(frames(arcade_dir / "effects" / e["file"], e["frames"], ARCADE_FRAME))
                 for name, e in converted.items()}
        for name, e in ps.items():
            strip = frames(ps_dir / "effects" / e["file"], e["frames"], PS_FRAME)
            distances = {}
            for other, book in books.items():
                by_frame = np.abs(strip[:, None] - book[None]).mean(axis=(2, 3, 4))
                distances[other] = (float(by_frame.min(axis=1).mean()), by_frame.argmin(axis=1))
            own, nearest = distances[name]
            same = [other for other, book in books.items() if np.array_equal(book, books[name])]
            rival = min((d for other, (d, _) in distances.items() if other not in same), default=float("inf"))
            verdict = "ok" if own < rival else "WRONG"
            failed += own >= rival
            print(f"{name:14} {e['frames']:2} → {converted[name]['frames']:2} frames  {own:5.1f}  next {rival:5.1f}  "
                  f"frames {[int(k) for k in nearest[:6]]}  {verdict}")
    print(f"{failed} of {len(ps)} flipbooks are closer to another arcade flipbook")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
