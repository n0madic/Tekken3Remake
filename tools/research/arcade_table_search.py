#!/usr/bin/env python3
"""Locate the PlayStation's constant tables in the decompressed arcade program.

For every table the converter reads from the Japan Rev.1 executable (`tables.py`, `ai.py`), the
table's bytes are searched in the arcade program (MAME `tekken3`, World ver. E1): an exact match
when there is one, else the alignment that most 4-byte windows of the table vote for, with the
share of bytes equal there. A candidate is only a lead: a table's arcade address is `confirmed` by
the routine that reads it (docs/research/arcade/moves.md, Table addresses).

Usage: arcade_table_search.py [--json FILE]
"""

from __future__ import annotations

import argparse
import collections
import json
import logging
import sys
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "remake_import"))
sys.path.insert(0, str(ROOT / "tools" / "research"))

import ai  # noqa: E402
import arcade  # noqa: E402
import pose  # noqa: E402
import tables  # noqa: E402

log = logging.getLogger("arcade_table_search")

PS1_EXE = ROOT / "work" / "jp_rev1" / "exe.bin"
ZIP = ROOT / "tekken3_mame.zip"
EXE_BASE = 0x80010000
EXE_HEADER = 0x800
WINDOW = 4
MAX_VOTERS = 20000               # k-mers per table; enough for the largest tables


@dataclass(frozen=True)
class Table:
    name: str
    address: int
    size: int


def table_list() -> list[Table]:
    t, a = tables, ai
    return [Table(*row) for row in (
        ("sin", pose.SIN_TABLE, 2 * t.SIN_ENTRIES),
        ("sqrt", pose.SQRT_TABLE, 2 * t.SQRT_ENTRIES),
        ("euler_slots", pose.EULER_SLOTS, t.EULER_JOINTS),
        ("limb_basis", pose.LIMB_BASIS, 18),
        ("skeleton_offsets", pose.SKELETON_OFFSETS, 48),
        ("limb_offsets", pose.LIMB_OFFSETS, 48),
        ("costume_keys", t.COSTUME_KEYS, t.COSTUME_KEY_COUNT),
        ("costume_hand_shapes", t.COSTUME_HAND_SHAPES, t.COSTUME_HAND_SHAPE_COUNT),
        ("attachment_limits", t.ATTACHMENT_LIMITS, 24 * t.ATTACHMENT_LIMIT_COUNT),
        ("attachment_clamps", t.ATTACHMENT_CLAMPS, 8),
        ("ratan", t.RATAN_TABLE, 2 * t.RATAN_ENTRIES),
        ("rsqrt", t.RSQRT_TABLE, 2 * t.RSQRT_ENTRIES),
        ("wing_open", t.WING_OPEN, t.WING_OPEN_BYTES),
        ("wing_beat", t.WING_BEAT, 30),
        ("sound_codes", t.SOUND_CODES, 2 * t.SOUND_CODE_COUNT),
        ("sound_scripts", t.SOUND_SCRIPTS, 4 * t.SOUND_SCRIPT_COUNT),
        ("voice_sets", t.VOICE_SETS, t.VOICE_SET_BYTES * t.VOICE_SET_COUNT),
        ("impact_voices", t.IMPACT_VOICES, 10),
        ("round_voices", t.ROUND_VOICES, 2 * t.ROUND_VOICE_COUNT),
        ("result_voices", t.RESULT_VOICES, 2 * t.RESULT_VOICE_COUNT),
        ("strike_sounds", t.STRIKE_SOUNDS, 4),
        ("special_sounds", t.SPECIAL_SOUNDS, 6),
        ("breath_offsets", t.BREATH_OFFSETS, 32),
        ("flame_offsets", t.FLAME_OFFSETS, 16),
        ("cloud_offsets", t.CLOUD_OFFSETS, 16),
        ("gas_offsets", t.GAS_OFFSETS, 16),
        ("burn_joints", t.BURN_JOINTS, 40),
        ("gas_times", t.GAS_TIMES, 60),
        ("glow_joints", t.GLOW_JOINTS, 8 * t.GLOW_JOINT_COUNT),
        ("hand_offsets", t.HAND_OFFSETS, 16 * t.HAND_OFFSET_CHARS),
        ("segment_fireball", 0x80025790, 8),
        ("segment_flame", 0x8002583C, 9),
        ("segment_cloud", 0x800258E4, 21),
        ("segment_gas", 0x80025A44, 27),
        ("mokujin_sounds", t.MOKUJIN_SOUNDS, 40),
        ("camera_presets", t.CAMERA_PRESETS, 20 * t.CAMERA_PRESET_COUNT),
        ("camera_preset_index", t.CAMERA_PRESET_INDEX, 2 * t.CAMERA_PRESET_COUNT),
        ("camera_choices", t.CAMERA_CHOICES, 8 * t.CAMERA_CHOICE_COUNT),
        ("hit_camera_rows", t.HIT_CAMERA_ROWS, 24),
        ("hit_camera_lists", t.HIT_CAMERA_LISTS, 8 * t.HIT_CAMERA_LIST_COUNT),
        ("hit_camera_scripts", t.HIT_CAMERA_SCRIPTS, 32 * t.HIT_CAMERA_SCRIPT_COUNT),
        ("intro_offsets", t.INTRO_OFFSETS, 6 * t.INTRO_OFFSET_COUNT),
        ("intro_offset_ball", t.INTRO_OFFSET_BALL, 6),
        ("winner_lateral", t.WINNER_LATERAL, 6),
        ("winner_forward", t.WINNER_FORWARD, 6),
        ("winner_height", t.WINNER_HEIGHT, 6),
        ("attract_styles", t.ATTRACT_STYLES, 8),
        ("attract_pitches", t.ATTRACT_PITCHES, 16),
        ("attract_speeds", t.ATTRACT_SPEEDS, 4),
        ("common_branches", t.COMMON_BRANCHES, 12 * t.COMMON_BRANCH_COUNT),
        ("sequences_a", t.SEQUENCES_A, 4 * t.SEQUENCES_A_COUNT),
        ("sequences_b", t.SEQUENCES_B, 4 * t.SEQUENCES_B_COUNT),
        ("builtin_attacks", t.BUILTIN_ATTACKS, 8 * t.BUILTIN_ATTACK_COUNT),
        ("builtin_blob", t.BUILTIN_BLOB, t.BUILTIN_BLOB_BYTES),
        ("air_kinds", t.AIR_KINDS, 4 * t.AIR_KIND_COUNT),
        ("push", t.PUSH_TABLES, 2 * t.PUSH_ENTRIES),
        ("launch_push", t.LAUNCH_PUSH, 16),
        ("reactions", t.REACTIONS, 2 * t.REACTION_WORDS * t.REACTION_COUNT),
        ("forced_reaction", t.FORCED_REACTION, 2 * t.REACTION_WORDS),
        ("throw_victim_slots", t.THROW_VICTIM_SLOTS, 2 * t.THROW_VICTIM_COUNT),
        ("close_reactions", t.CLOSE_REACTIONS, 4 * t.CLOSE_REACTION_COUNT),
        ("face_attack", t.FACE_ATTACK, t.FACE_SLOTS),
        ("face_hit", t.FACE_HIT, t.FACE_SLOTS),
        ("hurt_zone_joints", t.HURT_ZONE_JOINTS, 56),
        ("body_sphere_joints", t.BODY_SPHERE_JOINTS, 32),
        ("hurt_radii", t.HURT_RADII, 4 * t.CHARACTERS),
        ("body_radii", t.BODY_RADII, 4 * t.CHARACTERS),
        ("health", t.HEALTH, 4 * t.HEALTH_COUNT),
        ("recovery_team", t.RECOVERY_TEAM, 32),
        ("recovery_survival", t.RECOVERY_SURVIVAL, 32),
        ("square_root", t.SQUARE_ROOT, 2 * t.SQUARE_ROOT_COUNT),
        ("shake_scripts", t.SHAKE_SCRIPTS, 12),
        ("directions", t.DIRECTIONS, 36),
        ("reversal_lists", t.REVERSAL_LISTS, 4 * t.REVERSAL_LIST_COUNT),
        ("char_records", t.CHAR_RECORDS, 4 * t.COSTUME_KEYS_ALL),
        ("ai_params", a.AI_PARAMS, a.AI_GROUP_BYTES * a.AI_GROUPS),
        ("ai_band_thresholds", a.BAND_THRESHOLDS, 12 * a.BAND_THRESHOLD_COUNT),
        ("ai_band_reach", a.BAND_REACH, 4 * a.BAND_COUNT),
        ("ai_approach_reach", a.APPROACH_REACH, 4 * a.BAND_COUNT),
        ("ai_numpad_pads", a.NUMPAD_PADS, 20),
        ("ai_direction_masks", a.DIRECTION_MASKS, 20),
        ("ai_direction_pads", a.DIRECTION_PADS, 20),
        ("ai_button_pads", a.BUTTON_PADS, 8),
        ("ai_side_steps", a.SIDE_STEP_SCRIPTS, 48),
        ("ai_tap_forward", a.TAP_FORWARD, 12),
        ("ai_tap_back", a.TAP_BACK, 12),
        ("ai_back_dash", a.BACK_DASH, 12),
        ("ai_wake_up", a.WAKE_UP, 12),
        ("ai_king_throws", a.KING_THROWS, 42),
        ("ai_king_vs_crouch", a.KING_VS_CROUCH, 28),
        ("ai_king_ground", a.KING_GROUND, 28),
        ("ai_ogre_escapes", a.OGRE_ESCAPES, 8),
        ("ai_actions", a.ACTIONS, 12),
        ("ai_evasion_states", a.EVASION_STATES, 14),
        ("ai_hooks", a.HOOKS, 12 * a.HOOK_COUNT),
        ("ai_bank_records", a.BANK_RECORDS, 16 * a.BANK_RECORD_COUNT),
    )]


def search(data: bytes, haystack: bytes) -> tuple[int, float, str]:
    """(offset, share of equal bytes, how) of `data` in `haystack`; (-1, 0, "none") when no
    4-byte window of `data` occurs there."""
    at = haystack.find(data)
    if at >= 0:
        unique = haystack.find(data, at + 1) < 0
        return at, 1.0, "exact" if unique else "exact, repeated"
    votes: collections.Counter[int] = collections.Counter()
    step = max(1, (len(data) - WINDOW) // MAX_VOTERS)
    for i in range(0, max(1, len(data) - WINDOW + 1), step):
        window = data[i:i + WINDOW]
        if len(set(window)) == 1:          # runs of one byte vote everywhere
            continue
        p = haystack.find(window)
        hits = 0
        while p >= 0 and hits < 64:
            votes[p - i] += 1
            p = haystack.find(window, p + 1)
            hits += 1
    best = -1
    best_share = 0.0
    for offset, _ in votes.most_common(16):
        if offset < 0 or offset + len(data) > len(haystack):
            continue
        share = sum(a == b for a, b in zip(data, haystack[offset:offset + len(data)])) / len(data)
        if share > best_share:
            best, best_share = offset, share
    return best, best_share, "aligned" if best >= 0 else "none"


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--json", type=Path, help="also write the results to this file (game data: keep it in work/)")
    args = parser.parse_args()
    exe = PS1_EXE.read_bytes()
    program = arcade.open_set(ZIP).program
    results = []
    for table in table_list():
        start = table.address - EXE_BASE + EXE_HEADER
        data = exe[start:start + table.size]
        if len(data) != table.size:
            log.error("%s is outside the executable", table.name)
            return 1
        offset, share, how = search(data, program)
        address = EXE_BASE + offset if offset >= 0 else 0
        results.append({"name": table.name, "ps1": table.address, "size": table.size, "arcade": address,
                        "share": round(share, 4), "how": how})
        log.info("%-24s ps1 %08X size %5d  arcade %08X  %5.1f%%  %s", table.name, table.address, table.size, address,
                 100 * share, how)
    if args.json is not None:
        args.json.write_text(json.dumps(results, indent=1))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
