#!/usr/bin/env python3
"""Convert the user's Tekken 3 disc into the remake's asset folder.

The discs are the images given with `--image` (`.cue`, `.chd`, data tracks: disc_image.py), one
per release; the converter tells the releases apart itself. The game is converted from Japan
Rev.1 if given, else the original Japanese release, else USA; the other releases are rebased onto
Japan Rev.1's layout (layout.py), which the converter reads. A USA disc given with a Japanese one
adds its English (usa.py); a USA disc alone is itself English.

Only what the remake uses is converted (see MANIFEST). The output folder,
`remake/imported/` by default, is the single copy of the converted data: Godot
reads it directly and the export packs it into the PCK. It is git-ignored and
must never be published.

    python3 tools/remake_import/convert.py --image IMAGE [--image IMAGE] [--out DIR] [--no-music]
                                           [--no-movies] [--ffmpeg PATH] [--arcade ZIP]

`--arcade` adds the arcade version's polygonal stage scenes, skies and floors from MAME's
`tekken3` ROM set (arcade.py), which the remake draws instead of the PlayStation's backdrops,
and replaces the character models of costume slots 0–40 with the arcade's (arcade_character.py).
"""

from __future__ import annotations

import argparse
import hashlib
import logging
import sys
import time
from pathlib import Path

import common  # noqa: F401  (puts tools/research on the import path first)
import ai
import arcade
import arcade_character
import character
import effects
import enbu
import flow
import screen_vram
import hud
import media
import screens
import motion_bake
import sounds
import stage
import tables
import usa
from common import (CONVERTER_VERSION, DEFAULT_OUT, OUTPUT_MARKER, RELEASES, USA, DiscError, Output,
                    is_foreign_folder, log, open_discs)
from disc_image import ImageError
from layout import LayoutError
from sources import Recorder

# What the remake uses so far: M1 (the attract loop) and M2 (VS fights on every stage).
# Costume slots (costume key → slot, tables.py): the playable costumes, and the Tekken Force
# enemies (47–50), whose voice banks are empty. A slot's files are BNS 71 + 4s (.kmd), 72 + 4s
# (.vh), 73 + 4s (.arc).
FORCE_ENEMY_SLOTS = list(character.FORCE_ENEMY_SLOTS)
COSTUME_SLOTS = [s for s in range(52) if s not in FORCE_ENEMY_SLOTS]
CHARACTERS = [
    # name, costume slot, .kmd BNS id, .arc BNS id
    (f"costume_{slot:02d}", slot, 71 + 4 * slot, 73 + 4 * slot) for slot in range(52)
]
COMMON_BANK = "divmot99"
MOTION_BANKS = [
    # name, BNS id: types 0–20 (BNS 280–300; type 15 has no copy there, BNS 194 is the first)
    # and the common bank
    *[(f"divmot{t:02d}", 194 if t == 15 else 280 + t) for t in range(21)],
    ("divmot99", 279),
]
STAGE_LETTERS = "abcdefgnijklmtu"      # fight stages 0–14 (stages.md#stage-numbers-and-resources)
STAGES = [
    # stage number, letter, .arc BNS id, .tmd BNS id
    (number, letter, 36 + number, 56 + number) for number, letter in enumerate(STAGE_LETTERS)
]
MUSIC_TRACKS = list(range(29))   # every track the game plays (the Theater's sound list: 0–28)


# The pictures a texture pack may replace (remake/content/texture_packs.gd); the effect objects'
# page and palettes are data (indices and colour rows), not pictures.
REPLACEABLE = ("characters/", "stages/", "hud/", "effects/", "screens/", "usa/")
NOT_REPLACEABLE = {"effects/object_page.png", "effects/object_palettes.png"}
TEXTURE_KEY_DIGITS = 16


def texture_index(out: Output) -> dict[str, str]:
    """The replaceable pictures written this run by their keys: the first hex digits of the
    SHA-256 of the file."""
    index = {}
    for rel in sorted(out.files):
        if rel.endswith(".png") and rel.startswith(REPLACEABLE) and rel not in NOT_REPLACEABLE:
            index[rel] = hashlib.sha256((out.root / rel).read_bytes()).hexdigest()[:TEXTURE_KEY_DIGITS]
    return index


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--image", type=Path, action="append", required=True,
                        help="a disc image (.cue, .chd, or a data track .bin, .ecm, .iso), one per release: "
                        "the game from Japan Rev.1, else the original Japanese release, else USA; a USA "
                        "image with a Japanese one adds its English texts, move lists and text pictures")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--no-music", action="store_true", help="skip XA and CD-DA music")
    parser.add_argument("--no-movies", action="store_true", help="skip STR movies")
    parser.add_argument("--ffmpeg", type=Path, help="the FFmpeg to use (default: the first on the PATH with "
                        "the Theora and Vorbis encoders, else the first one; without them music is WAV "
                        "and movies are JPEG frames)")
    parser.add_argument("--arcade", type=Path, help="MAME's tekken3 ROM set (a .zip, World ver. E1): adds "
                        "the arcade stage scenes, skies and floors (stages 0–12) and character models (costume slots 0–40)")
    parser.add_argument("--texture-sources", type=Path, help="also record where each picture's texels come "
                        "from in VRAM, to this file (for tools/remake/texture_pack.py import-duckstation; "
                        "game data: keep it private)")
    args = parser.parse_args()

    # The run deletes files it did not produce; never do that in a folder it did not create.
    if is_foreign_folder(args.out):
        log.error("%s is not empty and holds neither its own manifest.json nor the %s marker of an earlier run; "
                  "refusing to convert into it", args.out, OUTPUT_MARKER)
        return 1

    # The run deletes the files it did not write below --out: the recording must lie elsewhere.
    if args.texture_sources is not None and args.out.resolve() in args.texture_sources.resolve().parents:
        log.error("--texture-sources %s is inside --out %s, which the run prunes; give a path outside it",
                  args.texture_sources, args.out)
        return 1

    start = time.time()
    try:
        discs = open_discs(args.image)
        source = next(discs[r.key] for r in RELEASES if r.key in discs)
        disc = source.canonical()
    except (DiscError, ImageError, LayoutError) as e:
        log.error("%s", e)
        return 1
    usa_disc = discs.get(USA.key)
    for unused in discs.values():
        if unused is not source and unused is not usa_disc:
            log.warning("%s (%s) is not used: the game is converted from %s", unused.image.path.name,
                        unused.release.label, source.release.label)
            unused.image.close()
    image = source.image.path
    if not source.image.xa and not (args.no_music and args.no_movies):
        log.warning("%s has no XA sectors (an ISO): no music and movies", image.name)
        args.no_music = args.no_movies = True
    log.info("the game from %s (%s)%s", image.name, source.release.label,
             f", English from {usa_disc.image.path.name}" if usa_disc is not None and usa_disc is not source else "")
    out = Output(args.out)
    out.invalidate_manifest()
    out.mark()
    if args.texture_sources is not None:
        out.sources = Recorder()
    tables.convert(disc, out)
    ai.convert(disc, out)
    flow.convert(disc, out)
    screen_vram.convert(disc, out)
    motion_bake.convert_all(disc, out, MOTION_BANKS, COMMON_BANK)
    arcade_set = arcade.open_or_none(args.arcade) if args.arcade is not None else None
    if arcade_set is not None:
        arcade_character.write_tables(out, arcade_set)
    for name, slot, kmd_id, arc_id in CHARACTERS:
        arcade_model = arcade_set is not None and arcade_character.replaces(slot)
        character.convert(disc, out, name, slot, kmd_id, arc_id, model=not arcade_model)
        if arcade_model:
            arcade_character.convert_or_keep(disc, out, arcade_set, name, slot, kmd_id, arc_id)
    for number, letter, arc_id, tmd_id in STAGES:
        stage.convert(disc, out, number, letter, arc_id, tmd_id)
    for number, letter, arc_id in stage.TILED_STAGES:
        stage.convert_tiled(disc, out, number, letter, arc_id)
    stage.convert_floor_fade(disc, out)
    arcade_stages = arcade_set is not None and arcade.convert(arcade_set, out, STAGE_LETTERS)
    enbu_models = enbu.convert(disc, out)
    sounds.convert(disc, out, COSTUME_SLOTS)
    screens.convert(disc, out)
    effects.convert(disc, out)
    hud.convert(disc, out)
    english = usa_disc is not None
    try:
        if english:
            usa.convert(None if usa_disc is source else disc, usa_disc, out, CHARACTERS)
    except (usa.UsaError, LayoutError) as e:
        if usa_disc is source:
            # The game's own move lists and pictures with text: no build without them.
            log.error("usa: %s", e)
            return 1
        log.error("usa: %s; the English texts are the project's own only", e)
        english = False
    try:
        if not (args.no_music and args.no_movies):
            tool = media.find_ffmpeg(args.ffmpeg)
            if not args.no_music:
                media.convert_music(disc, out, tool, MUSIC_TRACKS)
            if not args.no_movies:
                media.convert_title_movies(disc, out, tool)
                media.convert_ending_movies(disc, out, tool)
    except media.MediaError as e:
        log.error("%s", e)
        return 1
    out.write_json("texture_index.json", texture_index(out))
    out.write_json("manifest.json", {
        "converter_version": CONVERTER_VERSION,
        "source": source.release.key,
        "source_image_sha256": source.image_sha256(),
        "groups": {"core": True, "music": not args.no_music, "movies": not args.no_movies, "usa": english,
                   "arcade": arcade_stages},
        "characters": [c[0] for c in CHARACTERS] + enbu_models,
        "motion_banks": [b[0] for b in MOTION_BANKS],
        "stages": [s[1] for s in STAGES] + [s[1] for s in stage.TILED_STAGES],
    })
    if out.sources is not None:
        out.sources.save(args.texture_sources)
        log.info("texture sources: %d pictures, %d VRAM snapshots in %s", len(out.sources.pictures),
                 len(out.sources.snapshots), args.texture_sources)
    removed = out.prune()
    log.info("%d files written, %d unchanged, %d stale removed in %s (%.1f s)",
             out.written, out.unchanged, removed, args.out, time.time() - start)
    return 0


if __name__ == "__main__":
    sys.exit(main())
