"""The remake's assets from MAME's tekken3 ROM set alone, no disc (convert.py without `--image`).

Writes what the arcade's data can give to the remake's folder layout. The set is the arcade version:
fewer modes and fighters than the PlayStation's, which the flow data leaves out so the remake does
not offer them. What is not converted yet is listed in the manifest's `gaps`, and the remake says
so instead of starting (docs/research/arcade/README.md, docs/remake-plan.md).
"""

from __future__ import annotations

import hashlib

import arcade
import arcade_ai_tables
import arcade_character
import arcade_effect_objects
import arcade_effect_tables
import arcade_effects
import arcade_flow
import arcade_motion_bake
import arcade_movie
import arcade_screens
import arcade_sounds
import arcade_tables
import effects
import media
import stage
from common import Output, log
from vram import png_bytes

STAGES = 13                     # fight stages 0–12 (arcade.py)
LIGHT_RECORDS = 0x801FCFB8      # 0x18 bytes per stage: the first 0x10 as stages.md#lighting's records
LIGHT_RECORD_BYTES = 0x18
LIGHT_RECORD_USED = 0x10
# The fighters' view (`character_view`) and the camera read the coverage for the PlayStation's
# backdrop only; the arcade's scene is closed, so every direction counts as covered.
COVERED = 90
DUST_OFFSETS = 0x80175824               # 6 × (x, y, z, pad) s16: the landing dust's ring
COVERAGE_DIRECTIONS = 72

# What the remake needs and this converter does not produce yet.
GAPS: tuple[str, ...] = ()


def lighting(arc: arcade.ArcadeSet, number: int) -> dict:
    """The stage's light rig record: the same 16 leading bytes as the PlayStation's."""
    return stage.lighting_record(arc.prog(LIGHT_RECORDS + LIGHT_RECORD_BYTES * number, LIGHT_RECORD_USED))


def stage_record(arc: arcade.ArcadeSet, number: int, letter: str, floor: dict) -> dict:
    """`stages/<letter>/stage.json` where only the arcade's scene exists (no panorama)."""
    return {
        "stage": number,
        "letter": letter,
        "floor_kind": floor["kind"],
        "floor_shade": floor["shade"],
        "floor_fade": floor["fade"],
        "floor_tile_size": floor["tile_size"],
        "lighting": lighting(arc, number),
        "coverage": {"eye": list(stage.COVERAGE_EYE), "elevation": [COVERED] * COVERAGE_DIRECTIONS},
    }


def convert_stages(arc: arcade.ArcadeSet, out: Output, letters: str) -> None:
    if not arcade.convert(arc, out, letters):
        raise arcade.ArcadeError("the stage scenes could not be converted")
    for number in range(STAGES):
        letter = letters[number]
        out.write_json(f"stages/{letter}/stage.json", stage_record(arc, number, letter, arcade.floor_info(arc, number)))


def convert_characters(arc: arcade.ArcadeSet, out: Output) -> list[str]:
    arcade_character.write_tables(out, arc)
    names = []
    for slot in range(arcade_character.SLOTS):
        name = f"costume_{slot:02d}"
        arcade_character.convert(None, out, arc, name, slot)
        names.append(name)
    log.info("arcade: %d costume models", len(names))
    return names


def convert_effects(arc: arcade.ArcadeSet, out: Output) -> None:
    """`effects/effects.json` from the set: the system flipbooks, a character's per costume slot, the
    landing dust's ring and the effect objects' drawing (arcade_effect_objects)."""
    table: dict = {"system": [], "enbu": [], "costumes": {}}
    for index, name in enumerate(effects.SYSTEM_NAMES):
        strip, frames = arcade_effects.flipbook(arc, arcade_effects.SYSTEM_RECORDS[index])
        out.write(f"effects/{name}.png", png_bytes(strip))
        table["system"].append({"name": name, "file": f"{name}.png", "frames": frames, "game_frames": frames,
                                "blend": "half" if index in effects.HALF_BLEND else "add"})
    keys = [byte - 256 if byte > 127 else byte for byte in arc.prog(arcade_tables.COSTUME_KEYS, arcade_tables.COSTUME_KEY_COUNT)]
    for slot, (char_id, owner) in effects.costume_characters(keys).items():
        name = f"costume_{slot:02d}"
        strip, frames = arcade_effects.flipbook(arc, arcade_effects.character_record(owner))
        out.write(f"effects/{name}.png", png_bytes(strip))
        table["costumes"][str(slot)] = {"name": name, "file": f"{name}.png", "frames": frames, "blend": "add",
                                        "light": arcade_effects.light_of(arc, char_id)}
    out.write_json("effects/effects.json", {
        **table,
        "objects": arcade_effect_objects.drawing(arc, out),
        "dust_ring": {"offsets": [list(arc.prog_values("<3h", DUST_OFFSETS + 8 * i)) for i in range(effects.DUST_PUFFS)],
                      "y": effects.DUST_HEIGHT, "interval": effects.DUST_INTERVAL, "flipbook": "dust"},
    })


def convert_sounds(arc: arcade.ArcadeSet, out: Output, sound: tuple[bytes, bytes], tool: media.FFmpeg | None) -> None:
    """The sound board's samples and, with FFmpeg (`tool`), its music: `sound` is `arcade.sound_chips`'s."""
    program, wave_rom = sound
    table = [arc.prog_values("<2H", arcade_tables.SOUND_TABLE + 4 * i) for i in range(arcade_tables.SOUND_COUNT)]
    voices = {wave for i in range(arcade_tables.VOICE_SET_COUNT)
              for wave in arcade_tables.voice_set(arc, arcade_tables.VOICE_SETS + arcade_tables.VOICE_SET_BYTES * i)["voices"]}
    arcade_sounds.convert_sounds(program, wave_rom, out, table, voices)
    if tool is not None:
        arcade_sounds.convert_music(program, wave_rom, out, tool)


def convert(arc: arcade.ArcadeSet, out: Output, letters: str, sound: tuple[bytes, bytes], tool: media.FFmpeg | None = None,
            music_tool: media.FFmpeg | None = None) -> dict:
    """Converts the set; returns the manifest's fields. FFmpeg: `tool` for the movie, `music_tool` for the music;
    without them neither is converted."""
    characters = convert_characters(arc, out)
    convert_stages(arc, out, letters)
    motions = arcade_motion_bake.convert(arc, out)
    arcade_tables.convert(arc, out, motions["row_streams"])
    arcade_ai_tables.convert(arc, out)
    arcade_effect_tables.convert(arc, out)
    arcade_flow.convert(arc, out)
    convert_effects(arc, out)
    arcade_screens.convert(arc, out)
    if tool is not None:
        arcade_movie.convert(arc, out, tool)
    convert_sounds(arc, out, sound, music_tool)
    return {
        "source": "arcade",
        "source_image_sha256": hashlib.sha256(arc.program_rom).hexdigest(),
        "characters": characters,
        "motion_banks": [arcade_motion_bake.BANK_NAME],
        "stages": list(letters[:STAGES]),
        "gaps": list(GAPS),
        "groups": {"core": True, "music": music_tool is not None, "movies": tool is not None, "usa": False, "arcade": True},
    }
