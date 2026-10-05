#!/usr/bin/env python3
"""Texture packs for the remake (remake/content/texture_packs.gd).

A pack is a folder `<user data>/texture_packs/<name>/` with a `pack.json` and PNG pictures named
after the converted picture they replace: `<key>.png`, the key being the first 16 hex digits of
the SHA-256 of the converted file (`remake/imported/texture_index.json`). A replacement may be
larger (HD): the meshes address their textures in normalised coordinates, so it should keep the
original's aspect ratio and layout.

    python3 tools/remake/texture_pack.py dump OUT_DIR     # the originals under their keys, a
                                                          # names.txt and a pack.json to start from
    python3 tools/remake/texture_pack.py check PACK_DIR   # unknown keys and changed aspect ratios
    python3 tools/remake/texture_pack.py import-duckstation DUCKSTATION_DIR PACK_DIR --image X.cue ...
                                                          # a DuckStation replacement pack converted
                                                          # (duckstation_pack.py; needs xxhash)

`import-duckstation` converts the discs again into a temporary folder, recording where each
picture's texels come from in VRAM (the same `--image` arguments as the conversion installed in
remake/imported/), or reads such a recording (`--sources`). The pack's keys are those of the
installed conversion.

The originals are converted game data: keep the dumped folder and any pack built from it private.
"""

from __future__ import annotations

import argparse
import json
import logging
import shutil
import struct
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
IMPORTED = ROOT / "remake" / "imported"
CONVERTER = ROOT / "tools" / "remake_import"
sys.path.insert(0, str(CONVERTER))
INDEX = IMPORTED / "texture_index.json"
ASPECT_TOLERANCE = 0.01

log = logging.getLogger("texture_pack")


def png_size(path: Path) -> tuple[int, int]:
    with path.open("rb") as f:
        head = f.read(24)
    if head[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError(f"{path} is not a PNG")
    return struct.unpack(">II", head[16:24])


def load_index() -> dict[str, str]:
    if not INDEX.exists():
        raise SystemExit(f"{INDEX} is missing: run tools/remake_import/convert.py first")
    return json.loads(INDEX.read_text())


def dump(out: Path) -> int:
    index = load_index()
    out.mkdir(parents=True, exist_ok=True)
    names = []
    for rel, key in sorted(index.items()):
        shutil.copyfile(IMPORTED / rel, out / f"{key}.png")
        names.append(f"{key}\t{rel}")
    (out / "names.txt").write_text("\n".join(names) + "\n")
    manifest = out / "pack.json"
    if not manifest.exists():
        manifest.write_text(json.dumps({"name": out.name, "author": "", "version": 1}, indent=1) + "\n")
    log.info("%d pictures in %s", len(index), out)
    return 0


def check(pack: Path) -> int:
    index = load_index()
    by_key = {key: rel for rel, key in index.items()}
    problems = 0
    if not (pack / "pack.json").exists():
        log.error("%s has no pack.json", pack)
        problems += 1
    for picture in sorted(pack.glob("*.png")):
        rel = by_key.get(picture.stem)
        if rel is None:
            log.error("%s: no converted picture has this key", picture.name)
            problems += 1
            continue
        w, h = png_size(picture)
        ow, oh = png_size(IMPORTED / rel)
        if abs(w / h - ow / oh) > ASPECT_TOLERANCE * ow / oh:
            log.error("%s (%s): %d × %d does not keep the original's %d × %d aspect", picture.name, rel, w, h, ow, oh)
            problems += 1
    vram_index = pack / "vram.json"
    if vram_index.exists():
        for entry in json.loads(vram_index.read_text()).get("entries", []):
            picture = pack / entry["file"]
            x, y, w, h = entry["rect"]
            if not picture.exists():
                log.error("vram.json: %s is missing", entry["file"])
                problems += 1
            elif png_size(picture) != (w * entry["scale"], h * entry["scale"]):
                log.error("vram.json: %s is not %d × %d at scale %d", entry["file"], w, h, entry["scale"])
                problems += 1
    log.info("%s: %d problems", pack, problems)
    return 1 if problems else 0


def import_duckstation(pack: Path, out: Path, images: list[Path], recording: Path | None, scale: int | None) -> int:
    import duckstation_pack
    from sources import Sources
    problem = duckstation_pack.output_problem(pack, out)
    if problem is not None:
        log.error("%s", problem)
        return 1
    index = load_index()
    with tempfile.TemporaryDirectory(prefix="t3_sources_") as folder:
        if recording is None:
            if not images:
                log.error("give the disc images (--image, as for the conversion) or a recording (--sources)")
                return 1
            recording = Path(folder) / "sources.zip"
            command = [sys.executable, str(CONVERTER / "convert.py"), "--out", str(Path(folder) / "imported"),
                       "--no-music", "--no-movies", "--texture-sources", str(recording)]
            for image in images:
                command += ["--image", str(image)]
            log.info("converting the discs to record the pictures' VRAM sources")
            if subprocess.run(command, stdout=subprocess.DEVNULL).returncode != 0:
                log.error("the conversion failed")
                return 1
        sources = Sources.load(recording)
    return duckstation_pack.import_pack(pack, out, sources, IMPORTED, index, scale)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("dump").add_argument("out", type=Path)
    sub.add_parser("check").add_argument("pack", type=Path)
    ds = sub.add_parser("import-duckstation", help="convert a DuckStation texture replacement pack")
    ds.add_argument("duckstation", type=Path, help="the pack's folder (its replacements are searched recursively)")
    ds.add_argument("out", type=Path, help="the remake pack's folder (replaced), e.g. <user data>/texture_packs/<name>")
    ds.add_argument("--image", type=Path, action="append", default=[], help="a disc image, as for convert.py")
    ds.add_argument("--sources", type=Path, help="a recording of convert.py --texture-sources instead of the images")
    ds.add_argument("--scale", type=int, help="the pictures' scale (default: the replacements' largest, at most 8)")
    args = parser.parse_args()
    if args.command == "dump":
        return dump(args.out)
    if args.command == "check":
        return check(args.pack)
    return import_duckstation(args.duckstation, args.out, args.image, args.sources, args.scale)


if __name__ == "__main__":
    sys.exit(main())
