"""The arcade game flow's tables (World ver. E1, MAME's `tekken3`) → `tables/arcade_flow.json`.

What the states of `main` read from the program: the select's roster and its players' records, the
day schedule of the fighters that open, the demonstration's fighters, the characters' records (by
costume key: name, stage, music, the voice of the pick), the name entry's alphabet and the names it
rejects, the attract movie's length. The screens' pictures and layouts are arcade_screens.py's.
"""

from __future__ import annotations

import logging
import struct

import arcade
from common import Output

log = logging.getLogger(__name__)

ROSTER = 0x80179BA8
ROSTER_COUNT = 18
UNLOCKS = 0x801FF648                # u16 day, u16 kind, u32 argument; ends at day 0xFFFF
UNLOCK_BYTES = 8
UNLOCK_END = 0xFFFF
DEMO_CHARACTERS = 0x801FF928
DEMO_CHARACTER_COUNT = 13
CHARACTER_RECORDS = 0x801FF454      # a record's pointer per costume key
CHARACTER_KEYS = 92
RECORD_NAME = 0                     # u32 pointer to the name
RECORD_VOICE = 8
RECORD_MOKUJIN_BANK = 9
RECORD_STAGE = 10
RECORD_MUSIC = 11
VOICES = 0x8015FEB8                 # 0x18 bytes per voice set: the pick's sound first
VOICE_SET_BYTES = 0x18
ALPHABET = 0x80179678
ALPHABET_COUNT = 40
REJECTED_NAMES = 0x801FF624
REJECTED_COUNT = 5
SELECT_STATE_ANIM = 0x80179DF4      # two bytes per player state
SELECT_STATES = 8
SELECT_DECIDED = 0x80179DE4         # two bytes per player state: has a fighter, is a human
SELECT_PLAYERS = 0x80179B58         # 0x28 bytes per player: what the screen's drawing reads
SELECT_PLAYER_BYTES = 0x28
SELECT_DEFAULT_CELL = 0x24          # u16 in the player's record
SELECT_PORTRAIT_X = 0               # s16 in the player's record: where the player's sparks rise
SELECT_LAYOUTS = 0x801FFAA8         # 13 words per layout, the character select's measures
SELECT_LAYOUT_BYTES = 0x34
SELECT_LAYOUT_COUNT = 2
SELECT_PLATE_Y = 8                  # s32 in a layout: where the sparks start
ENBU_SCRIPT = 0x80186FF8            # five s16 per event: frame, kind, three arguments
OGRE_SCRIPTS = (0x80187208, 0x8018723C)  # FUN_801E1758's, by the side of the human player
RECORD_WINS = 0x80179ED4            # FUN_801C2CDC: the character of each versus record of a fresh cabinet
RECORD_WINS_COUNT = 10
ENBU_EVENT_BYTES = 10
ENBU_END = -1
MOVIE_CATEGORY = 0                  # 0x8021F290[0], which is zero at boot; FUN_801BB748 counts the
                                    # files of each category into 0x801FF73C, one movie frame per file
MAX_STRING = 32


def string_at(arc: arcade.ArcadeSet, address: int) -> str:
    """The zero-ended text at a program address."""
    raw = arc.prog(address, MAX_STRING)
    return raw[:raw.index(0)].decode("ascii")


def unlock_schedule(arc: arcade.ArcadeSet) -> list[list[int]]:
    """FUN_801BAE34's table: `[day, kind, argument]` up to its end mark."""
    out = []
    address = UNLOCKS
    while True:
        day, kind, argument = arc.prog_values("<HHI", address)
        if day == UNLOCK_END:
            return out
        out.append([day, kind, argument])
        address += UNLOCK_BYTES


def character_records(arc: arcade.ArcadeSet) -> list[dict]:
    """The records by costume key: FUN_801B5270's stage and music, FUN_801BEB68's pick voice,
    FUN_801B8CD4's name, FUN_801B5224's bank of Mokujin's round."""
    out = []
    for key in range(CHARACTER_KEYS):
        record = arc.prog_values("<I", CHARACTER_RECORDS + 4 * key)[0]
        raw = arc.prog(record, RECORD_MUSIC + 1)
        name_at = struct.unpack_from("<I", raw, RECORD_NAME)[0]
        out.append({
            "name": string_at(arc, name_at),
            "stage": raw[RECORD_STAGE],
            "music": raw[RECORD_MUSIC],
            "voice": arc.prog_values("<h", VOICES + VOICE_SET_BYTES * raw[RECORD_VOICE])[0],
            "mokujin_bank": raw[RECORD_MOKUJIN_BANK],
        })
    return out


def scene_script(arc: arcade.ArcadeSet, address: int) -> list[int]:
    """A scripted scene's events up to the end mark, included."""
    out = []
    while True:
        event = arc.prog_values("<5h", address)
        out.extend(event)
        if event[1] == ENBU_END:
            return out
        address += ENBU_EVENT_BYTES


def select_sparks(arc: arcade.ArcadeSet) -> dict:
    """FUN_801BF8B4: per side the portrait the sparks rise over, per layout where they start."""
    return {
        "select_spark_x": [arc.prog_values("<h", SELECT_PLAYERS + SELECT_PLAYER_BYTES * p + SELECT_PORTRAIT_X)[0]
                           for p in range(2)],
        "select_spark_y": [arc.prog_values("<i", SELECT_LAYOUTS + SELECT_LAYOUT_BYTES * layout + SELECT_PLATE_Y)[0]
                           for layout in range(SELECT_LAYOUT_COUNT)],
    }


def tables(arc: arcade.ArcadeSet) -> dict:
    return {
        "roster": list(arc.prog(ROSTER, ROSTER_COUNT)),
        "unlocks": unlock_schedule(arc),
        "demo_characters": list(arc.prog(DEMO_CHARACTERS, DEMO_CHARACTER_COUNT)),
        "characters": character_records(arc),
        "alphabet": arc.prog(ALPHABET, ALPHABET_COUNT).decode("ascii"),
        "rejected_names": [string_at(arc, pointer) for pointer in
                           arc.prog_values(f"<{REJECTED_COUNT}I", REJECTED_NAMES)],
        "select_state_anim": list(arc.prog(SELECT_STATE_ANIM, 2 * SELECT_STATES)),
        "select_decided": list(arc.prog(SELECT_DECIDED, 2 * SELECT_STATES)),
        "select_default_cell": [arc.prog_values("<H", SELECT_PLAYERS + SELECT_PLAYER_BYTES * p + SELECT_DEFAULT_CELL)[0]
                                for p in range(2)],
        **select_sparks(arc),
        "enbu_script": scene_script(arc, ENBU_SCRIPT),
        "ogre_scripts": [scene_script(arc, address) for address in OGRE_SCRIPTS],
        "record_wins": list(arc.prog(RECORD_WINS, RECORD_WINS_COUNT)),
        "movie_frames": len(arc.category(MOVIE_CATEGORY)),
    }


def convert(arc: arcade.ArcadeSet, out: Output) -> None:
    data = tables(arc)
    out.write_json("tables/arcade_flow.json", data)
    log.info("arcade: flow tables, %d unlocks, %d characters", len(data["unlocks"]), len(data["characters"]))
