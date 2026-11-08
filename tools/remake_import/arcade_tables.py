"""The arcade's constant tables → `imported/tables/` in the layouts `content/fight_tables.gd` reads.

Addresses and record layouts: docs/research/arcade/moves.md, combat.md. A table the arcade does not
have is left empty; the arcade's fight code does not read it.
"""

from __future__ import annotations

import struct

import arcade
import arcade_camera_tables
from common import Output

# Pose and general maths
SIN, SIN_ENTRIES = 0x80175944, 4096 + 1024
SQUARE_ROOT, SQUARE_ROOT_COUNT = 0x801AEC94, 192
RATAN, RATAN_ENTRIES = 0x80216088, 1025
RSQRT, RSQRT_ENTRIES = 0x8021A8A0, 0xC0
ATAN, ATAN_ENTRIES = 0x80178148, 1025  # FUN_801AF484: s16 octant table of the 4096-unit arctangent
# Fighters
COSTUME_KEYS, COSTUME_KEY_COUNT = 0x801FE060, 0x5C
COSTUME_SLOTS = 0x29
FACE_ATTACK, FACE_HIT, HAND_OPEN = 0x801FE2EC, 0x801FE318, 0x801FE344
SOUND_TABLE, SOUND_COUNT = 0x801FE644, 197          # FUN_801A0E80: (code, parameter) per 12-bit sound id
SOUND_SCRIPTS, SOUND_SCRIPT_COUNT = 0x801FE978, 454
VOICE_SETS, VOICE_SET_BYTES, VOICE_SET_COUNT = 0x8015FEA4, 24, 23
ROUND_VOICES, ROUND_VOICE_COUNT = 0x8015F4AA, 10     # FUN_8019DEC4: per round (from 1, up to 9) the sound id of its number
WOOD_SOUNDS, SPECIAL_SOUNDS, STRIKE_SOUNDS = 0x8015F7B8, 0x8015FE9C, 0x8015F7C8
SWING_SOUNDS, SWING_SOUNDS_SLOW = 0x8015F7A4, 0x8015F7B0    # FUN_801A1EAC
FACE_ROWS, FACE_ROW_COSTUMES = 0x801FE370, 0x29      # FUN_80193EA4: 8 s8 per costume
FACE_BLINK, FACE_REACT, FACE_DOWN = 0x801FE4B8, 0x801FE4E4, 0x801FE510      # FUN_80193F90
WING_OPEN, WING_OPEN_BYTES = 0x801FCF30, 20
WING_BEAT = 0x801FCF44
CHARACTER_RECORDS, CHARACTER_KEYS = 0x801FF454, 92
# Moves
SEQUENCES_A, SEQUENCES_A_COUNT = 0x800102A8, 63     # commands 0xC00C–0xC04A
SEQUENCES_B, SEQUENCES_B_COUNT = 0x800106B0, 41     # commands 0xC7FF–0xC827
AIR_KINDS, AIR_KIND_COUNT = 0x8015F704, 13
PUSH_TABLES, PUSH_END = 0x80010D00, 0x80011200
LAUNCH_PUSH = 0x8015EDB8
REACTIONS, REACTION_COUNT, REACTION_BYTES = 0x80011200, 978, 0x38
CLOSE_REACTIONS, CLOSE_REACTION_COUNT = 0x8001E7EC, 52
REVERSAL_LISTS, REVERSAL_LIST_COUNT = 0x801FCC44, 47
DIRECTIONS = 0x8001095C
# Combat
HURT_ZONE_JOINTS, BODY_SPHERE_JOINTS = 0x801FE5B4, 0x801FE53C
HURT_RADII, BODY_RADII, RADII_CHARACTERS = 0x801FE5EC, 0x801FE55C, 22
HEALTH_HANDICAP, HEALTH_ONE_PLAYER, HEALTH_TWO_PLAYERS, HEALTH_COUNT = 0x8017953C, 0x8017955C, 0x8017957C, 8
RECOVERY_TEAM, RECOVERY_SURVIVAL = 0x801794FC, 0x8017951C
SHAKE_SCRIPTS, SHAKE_SCRIPT_COUNT = 0x801FF3C4, 3
SHAKE_END, SHAKE_CORE_END = -0x8000, -128          # the program's s16 end mark, the core's (CameraShake.END)


def s16s(arc: arcade.ArcadeSet, address: int, count: int) -> list[int]:
    return list(arc.prog_values(f"<{count}h", address))


def u16s(arc: arcade.ArcadeSet, address: int, count: int) -> list[int]:
    return list(arc.prog_values(f"<{count}H", address))


def s32s(arc: arcade.ArcadeSet, address: int, count: int) -> list[int]:
    return list(arc.prog_values(f"<{count}i", address))


def u32s(arc: arcade.ArcadeSet, address: int, count: int) -> list[int]:
    return list(arc.prog_values(f"<{count}I", address))


def u8s(arc: arcade.ArcadeSet, address: int, count: int) -> list[int]:
    return list(arc.prog_values(f"<{count}B", address))


def s8s(arc: arcade.ArcadeSet, address: int, count: int) -> list[int]:
    return list(arc.prog_values(f"<{count}b", address))


def s8_list(arc: arcade.ArcadeSet, address: int) -> list[int]:
    """s8 values up to and including the first −1."""
    out = []
    while not out or out[-1] != -1:
        out.append(s8s(arc, address + len(out), 1)[0])
    return out


def sequences(arc: arcade.ArcadeSet, address: int, count: int) -> list[list[int]]:
    """Consecutive motion sequences: a window, then u16 steps up to a 0, each aligned to 4 bytes (the
    addresses of FUN_8018D4CC and FUN_8018DD2C)."""
    out = []
    for _ in range(count):
        window = s16s(arc, address, 1)[0]
        address += 2
        steps = []
        while (step := arc.prog_values("<H", address)[0]) != 0:
            steps.append(step)
            address += 2
        address = (address + 2 + 3) & ~3
        out.append([window] + steps)
    return out


def push_index(pointer: int) -> int:
    """A record's pointer to a push entry as an s16 index into the push table; 0 for none."""
    return (pointer - PUSH_TABLES) // 2 if pointer else 0


def reaction_words(arc: arcade.ArcadeSet, index: int) -> list[int]:
    """A reaction record as the PlayStation's 21 s16 (`FightTables.REACTION_WORDS`)."""
    angle, hit, value, counter, down_angle, down, guard = struct.unpack("<IIIIIII", arc.prog(REACTIONS + REACTION_BYTES * index, 28))
    slots = s16s(arc, REACTIONS + REACTION_BYTES * index + 28, 14)
    return slots + [_s16(angle), push_index(hit), _s16(value), push_index(counter), _s16(down_angle), push_index(down),
                    push_index(guard)]


def _s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def reversal_lists(arc: arcade.ArcadeSet, row_streams: list[int]) -> list[list[int]]:
    """The lists of rows: each entry as its row's stream tag (`arcade_motion_bake.convert`), which is
    what the code compares (`FUN_8018EDE8`: the rows' animation words)."""
    out = []
    for pointer in u32s(arc, REVERSAL_LISTS, REVERSAL_LIST_COUNT):
        values = []
        while (row := s16s(arc, pointer + 2 * len(values), 1)[0]) != -1:
            values.append(row_streams[row] + 1)
        out.append(values)
    return out


def voice_set(arc: arcade.ArcadeSet, addr: int) -> dict:
    """A character's voices (FUN_801A0CD4, FUN_801A104C): the codes by category, the attack shouts,
    the damage voices (light, then heavy), the cooldown and five more sound ids."""
    voices, shouts, damage = arc.prog_values("<3I", addr)
    counts = s16s(arc, voices, 4)
    shout_count = s16s(arc, shouts, 1)[0]
    light, heavy = s16s(arc, damage, 2)
    return {
        "counts": counts,
        "voices": u16s(arc, voices + 8, sum(counts)),
        "shouts": u16s(arc, shouts + 2, max(shout_count, 1)),
        "damage_counts": [light, heavy],
        "damage": u16s(arc, damage + 4, light + heavy),
        "cooldown": s16s(arc, addr + 12, 1)[0],
        "ids": u16s(arc, addr + 14, 5),
    }


def sound_scripts(arc: arcade.ArcadeSet) -> list[list[int]]:
    """The sound scripts as the core reads them: frame | kind << 12 | code << 16, frame 0 ends. A
    script's entries are three u16 here."""
    scripts = []
    for pointer in arc.prog_values(f"<{SOUND_SCRIPT_COUNT}I", SOUND_SCRIPTS):
        entries = []
        while True:
            frame, kind, code = u16s(arc, pointer, 3)
            entries.append(frame | kind << 12 | code << 16)
            pointer += 6
            if frame == 0:
                break
        scripts.append(entries)
    return scripts


def characters(arc: arcade.ArcadeSet) -> list[dict]:
    """The character records by costume key: name, identity, voice set, bank, stage and music."""
    records = []
    for pointer in u32s(arc, CHARACTER_RECORDS, CHARACTER_KEYS):
        rec = arc.prog(pointer, 12)
        name_at = struct.unpack_from("<I", rec)[0]
        name = arc.prog(name_at, 16).split(b"\0")[0].decode("ascii") if name_at else ""
        records.append({"name": name, "base": rec[4], "unknown": list(rec[5:8]), "voice_set": rec[8], "bank": rec[9],
                        "stage": rec[10], "music": rec[11]})
    return records


def shake_scripts(arc: arcade.ArcadeSet) -> list[list[int]]:
    out = []
    for pointer in u32s(arc, SHAKE_SCRIPTS, SHAKE_SCRIPT_COUNT):
        values = []
        while not values or values[-1] != SHAKE_END:
            values.append(s16s(arc, pointer + 2 * len(values), 1)[0])
        out.append(values[:-1] + [SHAKE_CORE_END])
    return out


def radii(arc: arcade.ArcadeSet, table: int, count: int) -> list[list[int]]:
    return [s16s(arc, pointer, count) if pointer else [] for pointer in u32s(arc, table, RADII_CHARACTERS)]


def convert(arc: arcade.ArcadeSet, out: Output, row_streams: list[int]) -> None:
    # FightMath and CameraMath add idx >> 1 to the PlayStation's u8 table; the arcade's s16 table holds it.
    atan = [v - (i >> 1) for i, v in enumerate(s16s(arc, ATAN, ATAN_ENTRIES))]
    arcade_camera_tables.convert(arc, out, atan)
    out.write_json("tables/pose.json", {
        "sin": s16s(arc, SIN, SIN_ENTRIES),
        "sqrt": s16s(arc, SQUARE_ROOT, SQUARE_ROOT_COUNT),
        "euler_slots": [],
        "limb_basis": [],
        "skeleton_offsets": [],
        "limb_offsets": [],
    })
    out.write_json("tables/fighter.json", {
        "costume_keys": s8s(arc, COSTUME_KEYS, COSTUME_KEY_COUNT),
        "costume_hand_shapes": u8s(arc, FACE_ATTACK, COSTUME_SLOTS),
        "costume_open_shapes": u8s(arc, HAND_OPEN, COSTUME_SLOTS),
        "attachment_limits": [],
        "attachment_clamps": [],
        "ratan": s16s(arc, RATAN, RATAN_ENTRIES),
        "rsqrt": s16s(arc, RSQRT, RSQRT_ENTRIES),
        "wing_open": s8s(arc, WING_OPEN, WING_OPEN_BYTES),
        "wing_beat": s8_list(arc, WING_BEAT),
        "face_rows": s8s(arc, FACE_ROWS, 8 * FACE_ROW_COSTUMES),
        "face_blink": u8s(arc, FACE_BLINK, FACE_ROW_COSTUMES),
        "face_react": u8s(arc, FACE_REACT, FACE_ROW_COSTUMES),
        "face_down": u8s(arc, FACE_DOWN, FACE_ROW_COSTUMES),
    })
    out.write_json("tables/fight.json", {
        "common_branches": [],
        "sequences_a": sequences(arc, SEQUENCES_A, SEQUENCES_A_COUNT),
        "sequences_b": sequences(arc, SEQUENCES_B, SEQUENCES_B_COUNT),
        "builtin_attacks": [],
        "builtin_blob": [],
        "air_kinds": [s16s(arc, AIR_KINDS + 4 * i, 2) for i in range(AIR_KIND_COUNT)],
        "push": s16s(arc, PUSH_TABLES, (PUSH_END - PUSH_TABLES) // 2),
        "launch_push": s16s(arc, LAUNCH_PUSH, 8),
        "reactions": [reaction_words(arc, i) for i in range(REACTION_COUNT)],
        "forced_reaction": [],
        "throw_victim_slots": [],
        "close_reactions": [s16s(arc, CLOSE_REACTIONS + 4 * i, 2) for i in range(CLOSE_REACTION_COUNT)],
        "face_attack": u8s(arc, FACE_ATTACK, COSTUME_SLOTS),
        "face_hit": u8s(arc, FACE_HIT, COSTUME_SLOTS),
        "hurt_zone_joints": s32s(arc, HURT_ZONE_JOINTS, 14),
        "body_sphere_joints": s32s(arc, BODY_SPHERE_JOINTS, 8),
        "hurt_radii": radii(arc, HURT_RADII, 14),
        "body_radii": radii(arc, BODY_RADII, 8),
        "health": s32s(arc, HEALTH_HANDICAP, HEALTH_COUNT),
        "health_one_player": s32s(arc, HEALTH_ONE_PLAYER, HEALTH_COUNT),
        "health_two_players": s32s(arc, HEALTH_TWO_PLAYERS, HEALTH_COUNT),
        "recovery_team": s32s(arc, RECOVERY_TEAM, 8),
        "recovery_survival": s32s(arc, RECOVERY_SURVIVAL, 8),
        "square_root": s16s(arc, SQUARE_ROOT, SQUARE_ROOT_COUNT),
        "reversal_lists": reversal_lists(arc, row_streams),
        "shake_scripts": shake_scripts(arc),
        "directions": [[w & 0xFFFF for w in s16s(arc, DIRECTIONS + 18 * side, 9)] for side in range(2)],
        "characters": characters(arc),
        "sound_codes": [u16s(arc, SOUND_TABLE + 4 * i, 1)[0] for i in range(SOUND_COUNT)],
        "sound_scripts": sound_scripts(arc),
        "voices": [voice_set(arc, VOICE_SETS + VOICE_SET_BYTES * i) for i in range(VOICE_SET_COUNT)],
        "impact_voices": u16s(arc, WOOD_SOUNDS, 6),
        "swing_sounds": u16s(arc, SWING_SOUNDS, 4),
        "swing_sounds_slow": u16s(arc, SWING_SOUNDS_SLOW, 3),
        # ArcadeRoundSounds reads round_voices. The empty fields below are those of the PlayStation's table
        # that the arcade does not read: its effects have their own file (arcade_effect_tables.py), and it
        # has no vibration.
        "round_voices": u16s(arc, ROUND_VOICES, ROUND_VOICE_COUNT),
        "result_voices": [],
        "vibration": {"slots": [], "pulses": [], "patterns": []},
        "strike_sounds": u16s(arc, STRIKE_SOUNDS, 2),
        "special_sounds": u16s(arc, SPECIAL_SOUNDS, 3),
        "effects": {"breath_offsets": [], "flame_offsets": [], "cloud_offsets": [], "gas_offsets": [], "burn_joints": [],
                    "gas_times": [], "glow_joints": [], "hand_offsets": [], "segment_frames": {}, "mokujin_sounds": []},
    })
