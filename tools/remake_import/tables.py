"""Constant tables from the game executable that the remake's simulation core needs.

The code repository never embeds game data; these tables reach the remake only
through the converter. Addresses are Japan Rev.1 (see docs/research).
"""

from __future__ import annotations

import struct

from common import Disc, Output
import fight_math
import pose

SIN_ENTRIES = 4096 + 1024       # g_sinTable; g_cosTable starts 1024 entries in
SQRT_ENTRIES = 0x100 - 0x40     # SquareRoot0 mantissa table, indexed by x − 0x40
EULER_JOINTS = 10
ATAN_ENTRIES = 1025             # Atan2Units4096's octant table (u8, plus t/2)
COSTUME_KEYS = 0x80095CE8       # s8 costume slot per costume key (charId · 4 + costume)
COSTUME_KEY_COUNT = 0x5C
COSTUME_HAND_SHAPES = 0x80095D74  # u8 default hand shape per costume slot (FUN_800364E8)
COSTUME_HAND_SHAPE_COUNT = 0x37
ATTACHMENT_LIMITS = 0x80096144  # 24-byte records of six ints: atan2 axis signs and scales (FUN_80037F10)
ATTACHMENT_LIMIT_COUNT = 10
ATTACHMENT_CLAMPS = 0x80096134  # two (max, min) s16 pairs: costume slots 0x1A and 0x24/0x29
RATAN_TABLE = 0x8009922C        # libgte ratan2's octant table
RATAN_ENTRIES = 1025
RSQRT_TABLE = 0x8001A194        # reciprocal square roots of VectorNormal (and MatrixOrthonormalize)
RSQRT_ENTRIES = 0xC0
WING_OPEN = 0x80095CAC          # s8 True Ogre wing variants while they open, −1 ends (read in steps
WING_OPEN_BYTES = 20            # of two, so up to the byte after the first −1)
WING_BEAT = 0x80095CC0          # s8 wing variants of one beat, −1 ends
# Fighter sounds (sound.md)
SOUND_CODES = 0x80097474        # g_soundTable: u16 sound code per 12-bit sound id
SOUND_CODE_COUNT = 212
SOUND_SCRIPTS = 0x8009761C      # pointers to the sound scripts
SOUND_SCRIPT_COUNT = 470
VOICE_SETS = 0x8001AD54         # g_charVoices, 24 bytes per voice set
VOICE_SET_BYTES = 24
VOICE_SET_COUNT = 23            # up to the Mokujin code remap at 0x8001AF7C
IMPACT_VOICES = 0x8001A6F0      # FUN_80041ED8: Mokujin's opponent sounds
ROUND_VOICES = 0x8001A3BA       # FUN_8003DCE0: announcer "ROUND n" per round number (entry 0 unused)
ROUND_VOICE_COUNT = 11
RESULT_VOICES = 0x8009749A      # FUN_8003E158: announcer sounds of the round result
RESULT_VOICE_COUNT = 8
VIBRATION_SLOTS = 0x80010050    # PadVibrate: the queue slot (0-3) of each pattern
VIBRATION_PATTERNS = 0x80095758 # per pattern: small-motor and large-motor script pointers
VIBRATION_PATTERN_COUNT = 28
VIBRATION_PULSES = 0x80095838   # small-motor pulse masks by level (bit = frame & 7)
VIBRATION_PULSE_COUNT = 16
STRIKE_SOUNDS = 0x8001A6FC      # FUN_80041F4C: light strike sounds
SPECIAL_SOUNDS = 0x8001AD4C     # FUN_80041C48 case 3
# Effect objects (effects.md#effect-objects)
BREATH_OFFSETS = 0x80098BE0     # fire breath: per player two SVECTORs from the head joint
FLAME_OFFSETS = 0x80098C00      # Gon's flame
CLOUD_OFFSETS = 0x80098C10      # breath cloud
GAS_OFFSETS = 0x80098C20        # gas emitter (from joint 11)
BURN_JOINTS = 0x800253DC        # s32 × 10: the joints a burning body's flames follow
GAS_TIMES = 0x80025994          # s16 (frame, speed, height) … −1
GLOW_JOINTS = 0x80025420        # per descriptor joint: the power-glow joint (8-byte records)
GLOW_JOINT_COUNT = 26
HAND_OFFSETS = 0x80025590       # per character: SVECTORs of the glow at joints 6 and 10
HAND_OFFSET_CHARS = 21
SEGMENT_FRAMES = {"fireball": (0x80025790, 8), "flame": (0x8002583C, 9), "cloud": (0x800258E4, 21),
                  "gas": (0x80025A44, 27)}   # u8 per frame: 0 turns the projectile segment off
MOKUJIN_SOUNDS = 0x8001AF7C     # (sound id, replacement code) … −1
# Camera director (camera.md#cinematic-cameras)
CAMERA_PRESETS = 0x80024184     # 30 x 10 s16: blend in, blend out, heights[4], yaw offsets[4]
CAMERA_PRESET_COUNT = 30
CAMERA_PRESET_INDEX = 0x800243DC  # s16 preset index + 1 per preset script value
# FUN_80067C8C reads the blend-out word of "preset" −1 or −2 for the scripts that are not presets:
# the s16 at 0x80024172 (and 0x8002415E, the same value), outside the table.
CAMERA_OUTSIDE_BLEND_OUT = 0x80024172
CAMERA_CHOICES = 0x80098750     # (kind s16, weight u16, script s32) for the EXE camera ids
CAMERA_CHOICE_COUNT = 0x25      # ids 1–0x18 read up to entry 0x1A; ids 0x19–0x2A are rejected
HIT_CAMERA_ROWS = 0x80024510    # 4 x (bank type, move slot, list id)
HIT_CAMERA_LISTS = 0x800244F8   # per list id − 300: (records pointer, record count)
HIT_CAMERA_LIST_COUNT = 3
HIT_CAMERA_SCRIPTS = 0x80024418  # 7 scripts of 16 s16 words
HIT_CAMERA_SCRIPT_COUNT = 7
INTRO_OFFSETS = 0x800988E8      # 10 x (x, y, z) s16
INTRO_OFFSET_COUNT = 10
INTRO_OFFSET_BALL = 0x80098924  # mode 7
WINNER_LATERAL = 0x8001DF54     # 3 s16 each: winner camera style B
WINNER_FORWARD = 0x8001DF5C
WINNER_HEIGHT = 0x8001DF64
ATTRACT_STYLES = 0x80024528     # u16 x 4: the demonstration camera's styles (FUN_800693E8)
ATTRACT_PITCHES = 0x80098930    # s16 x 8: the circling camera's pitches (FUN_80068E90)
ATTRACT_SPEEDS = 0x80098940     # s16 x 2: its yaw steps


def convert(disc: Disc, out: Output) -> None:
    convert_fight(disc, out)
    out.write_json("tables/pose.json", {
        "sin": disc.exe_s16(pose.SIN_TABLE, SIN_ENTRIES),
        "sqrt": disc.exe_s16(pose.SQRT_TABLE, SQRT_ENTRIES),
        "euler_slots": disc.exe_u8(pose.EULER_SLOTS, EULER_JOINTS),
        "limb_basis": disc.exe_s16(pose.LIMB_BASIS, 9),
        "skeleton_offsets": disc.exe_s32(pose.SKELETON_OFFSETS, 12),
        "limb_offsets": disc.exe_s32(pose.LIMB_OFFSETS, 12),
    })
    out.write_json("tables/camera.json", _camera(disc))
    out.write_json("tables/fighter.json", {
        "costume_keys": [b - 256 if b > 127 else b for b in disc.exe_u8(COSTUME_KEYS, COSTUME_KEY_COUNT)],
        "costume_hand_shapes": disc.exe_u8(COSTUME_HAND_SHAPES, COSTUME_HAND_SHAPE_COUNT),
        "attachment_limits": [disc.exe_s32(ATTACHMENT_LIMITS + 24 * i, 6) for i in range(ATTACHMENT_LIMIT_COUNT)],
        "attachment_clamps": disc.exe_s16(ATTACHMENT_CLAMPS, 4),
        "ratan": disc.exe_s16(RATAN_TABLE, RATAN_ENTRIES),
        "rsqrt": disc.exe_s16(RSQRT_TABLE, RSQRT_ENTRIES),
        "wing_open": [b - 256 if b > 127 else b for b in disc.exe_u8(WING_OPEN, WING_OPEN_BYTES)],
        "wing_beat": _s8_list(disc, WING_BEAT),
    })


def _camera(disc: Disc) -> dict:
    """The camera director's tables. Hit camera list weights are turned into cumulative
    thresholds out of 0x1000 as FUN_80067ECC does once at the first fight; the last record's
    threshold is 0x1000, so the game's walk (which would run on until a weight above 0x1000)
    always stops inside the list."""
    choices = []
    for i in range(CAMERA_CHOICE_COUNT):
        kind, weight = disc.exe_s16(CAMERA_CHOICES + 8 * i, 1)[0], disc.exe_u16(CAMERA_CHOICES + 8 * i + 2, 1)[0]
        choices.append([kind, weight, disc.exe_s32(CAMERA_CHOICES + 8 * i + 4, 1)[0]])
    hit_lists = []
    for i in range(HIT_CAMERA_LIST_COUNT):
        pointer, count = disc.exe_u32(HIT_CAMERA_LISTS + 8 * i, 2)
        records = []
        for k in range(count):
            weight = disc.exe_s16(pointer + 20 * k, 1)[0]
            scripts = [(p - HIT_CAMERA_SCRIPTS) // 32 for p in disc.exe_u32(pointer + 20 * k + 4, 4)]
            records.append([weight, *scripts])
        total = sum(r[0] for r in records)
        cumulative = 0
        for r in records:
            cumulative += r[0]
            r[0] = int((cumulative << 12) / total)   # C division truncates towards zero
        hit_lists.append(records)
    scripts = []
    for k in range(HIT_CAMERA_SCRIPT_COUNT):
        a = HIT_CAMERA_SCRIPTS + 32 * k
        scripts.append(disc.exe_s16(a, 4) + disc.exe_s32(a + 8, 2) + disc.exe_s16(a + 16, 8))
    return {
        "atan": disc.exe_u8(fight_math.ATAN_TABLE, ATAN_ENTRIES),
        "presets": [disc.exe_s16(CAMERA_PRESETS + 20 * i, 10) for i in range(CAMERA_PRESET_COUNT)],
        "preset_index": disc.exe_s16(CAMERA_PRESET_INDEX, CAMERA_PRESET_COUNT),
        "outside_blend_out": disc.exe_s16(CAMERA_OUTSIDE_BLEND_OUT, 1)[0],
        "choices": choices,
        "hit_rows": [disc.exe_s16(HIT_CAMERA_ROWS + 6 * i, 3) for i in range(4)],
        "hit_lists": hit_lists,
        "hit_scripts": scripts,
        "intro_offsets": [disc.exe_s16(INTRO_OFFSETS + 6 * i, 3) for i in range(INTRO_OFFSET_COUNT)],
        "intro_offset_ball": disc.exe_s16(INTRO_OFFSET_BALL, 3),
        "winner_lateral": disc.exe_s16(WINNER_LATERAL, 3),
        "winner_forward": disc.exe_s16(WINNER_FORWARD, 3),
        "winner_height": disc.exe_s16(WINNER_HEIGHT, 3),
        "attract_styles": disc.exe_u16(ATTRACT_STYLES, 4),
        "attract_pitches": disc.exe_s16(ATTRACT_PITCHES, 8),
        "attract_speeds": disc.exe_s16(ATTRACT_SPEEDS, 2),
    }


def _s8_list(disc: Disc, addr: int) -> list[int]:
    """s8 values up to and including the first −1."""
    out = []
    while True:
        v = disc.exe_u8(addr + len(out), 1)[0]
        v = v - 256 if v > 127 else v
        out.append(v)
        if v == -1:
            return out


# ---- the fight (M2): tables of the move system, combat and characters -------------------------

COMMON_BRANCHES = 0x80017C78    # 12-byte common branch rows (command 0xC00C calls one)
COMMON_BRANCH_COUNT = 672       # up to the RETURN after the highest row any bank calls (668)
SEQUENCES_A = 0x800958F4        # 63 pointers: motion sequences of commands 0xC00E–0xC04C
SEQUENCES_A_COUNT = 63
SEQUENCES_B = 0x800959F0        # 41 pointers: commands 0xC7FF–0xC827
SEQUENCES_B_COUNT = 41
BUILTIN_ATTACKS = 0x80017C10    # 13 × (u32 id, u32 pointer) built-in attack descriptors
BUILTIN_ATTACK_COUNT = 13
BUILTIN_BLOB = 0x80017BDC       # the descriptors' bytes and what follows (records are read past them)
BUILTIN_BLOB_BYTES = 0x400
AIR_KINDS = 0x8001A630          # 6 × (s16 ground offset, s16 air move slot)
AIR_KIND_COUNT = 6
PUSH_TABLES = 0x8001075C        # s16 array; a push entry is frames, speed, 8 offsets
PUSH_ENTRIES = 700 + 10         # the highest index the reaction records use, plus one entry
LAUNCH_PUSH = 0x80019D2C        # 8 s16 offsets of a launch
REACTIONS = 0x80010CE8          # 633 × 21 s16 reaction records
REACTION_COUNT = 633
REACTION_WORDS = 21
FORCED_REACTION = 0x8001DEC0    # the record of a body thrown into a fighter
THROW_VICTIM_SLOTS = 0x800174C4 # s16 victim move slots (reaction 0x1nnn)
THROW_VICTIM_COUNT = 397 + 21   # the entries, then what a 21-word reaction read from one reaches
CLOSE_REACTIONS = 0x800177DC    # (s16 reaction, s16 distance) by move +0x34
CLOSE_REACTION_COUNT = 58
FACE_ATTACK = 0x80095D74        # u8 per costume slot: face shape while attacking (FUN_800364E8)
FACE_HIT = 0x80095DA8           # u8 per costume slot: face shape on a clean hit (FUN_80036518)
FACE_SLOTS = 0x37
HURT_ZONE_JOINTS = 0x800973DC   # s32[14]
BODY_SPHERE_JOINTS = 0x80097364 # s32[8]
HURT_RADII = 0x80097414         # per character a pointer to 14 s16 radii (0: none)
BODY_RADII = 0x80097384         # per character a pointer to 8 s16 body sphere radii
CHARACTERS = 23
HEALTH = 0x80022858             # s32 16.16 health by handicap / mode entry
RECOVERY_TEAM = 0x80022818      # s32 × 8: team battle: the winner's recovery by health left (eighths)
RECOVERY_SURVIVAL = 0x80022838  # s32 × 8: survival: the recovery by the fight's time
HEALTH_COUNT = 9
SQUARE_ROOT = 0x8004B1D8        # s16[192] mantissas of FUN_8004B174
SQUARE_ROOT_COUNT = 192
SHAKE_SCRIPTS = 0x80097EC8      # 3 pointers to s8 camera shake scripts ending at −128
DIRECTIONS = 0x80010738         # per side 9 pad direction words for numpad directions 1–9
REVERSAL_LISTS = 0x80095AB8     # pointers to s16 animation-tag lists (reversal condition 0x4B)
REVERSAL_LIST_COUNT = 52        # every list a bank's rows name (parameters 0–51)
CHAR_RECORDS = 0x80098120       # 92 record pointers by costume key
COSTUME_KEYS_ALL = 92


def _branch_rows(disc: Disc, addr: int, count: int) -> list[list[int]]:
    data = disc.exe_bytes(addr, 12 * count)
    return [list(struct.unpack_from("<HBBHHBBBB", data, 12 * i)) for i in range(count)]


def _sequences(disc: Disc, table: int, count: int) -> list[list[int]]:
    out = []
    for pointer in disc.exe_u32(table, count):
        window = disc.exe_s16(pointer, 1)[0]
        steps = []
        p = pointer + 2
        while (step := disc.exe_s16(p, 1)[0] & 0xFFFF) != 0:
            steps.append(step)
            p += 2
        out.append([window] + steps)
    return out


def _positive_lists(disc: Disc, table: int, count: int) -> list[list[int]]:
    """s16 lists ending at the first value below 1 (MoveInSlotList)."""
    out = []
    for pointer in disc.exe_u32(table, count):
        values = []
        while (v := disc.exe_s16(pointer + 2 * len(values), 1)[0]) >= 1:
            values.append(v)
        out.append(values)
    return out


def _s8_until(disc: Disc, addr: int, end: int) -> list[int]:
    """s8 values up to and including `end`."""
    out = []
    while True:
        v = disc.exe_u8(addr + len(out), 1)[0]
        out.append(v - 256 if v > 127 else v)
        if out[-1] == end:
            return out


def _effects(disc: Disc) -> dict:
    """The effect objects' tables."""
    def vectors(addr: int, count: int) -> list[list[int]]:
        return [disc.exe_s16(addr + 8 * i, 3) for i in range(count)]

    gas = []
    at = GAS_TIMES
    while True:
        frame = disc.exe_s16(at, 1)[0]
        if frame == -1:
            break
        gas.append(disc.exe_s16(at, 3))
        at += 6
    mokujin = []
    at = MOKUJIN_SOUNDS
    while True:
        pair = disc.exe_s16(at, 2)
        if pair[0] == -1:
            break
        mokujin.append([pair[0], pair[1] & 0xFFFF])
        at += 4
    return {
        "breath_offsets": [vectors(BREATH_OFFSETS + 16 * p, 2) for p in range(2)],
        "flame_offsets": vectors(FLAME_OFFSETS, 2),
        "cloud_offsets": vectors(CLOUD_OFFSETS, 2),
        "gas_offsets": vectors(GAS_OFFSETS, 2),
        "burn_joints": disc.exe_s32(BURN_JOINTS, 10),
        "gas_times": gas,
        "glow_joints": [disc.exe_u32(GLOW_JOINTS + 8 * i, 1)[0] for i in range(GLOW_JOINT_COUNT)],
        "hand_offsets": [vectors(HAND_OFFSETS + 16 * c, 2) for c in range(HAND_OFFSET_CHARS)],
        "segment_frames": {k: disc.exe_u8(a, n) for k, (a, n) in SEGMENT_FRAMES.items()},
        "mokujin_sounds": mokujin,
    }


def _sound_scripts(disc: Disc) -> list[list[int]]:
    """The sound scripts: u32 entries frame (12 bits) | type (4) | code (16), ending at frame 0."""
    scripts = []
    for pointer in disc.exe_u32(SOUND_SCRIPTS, SOUND_SCRIPT_COUNT):
        entries = []
        while True:
            word = disc.exe_u32(pointer, 1)[0]
            entries.append(word)
            pointer += 4
            if word & 0xFFF == 0:
                break
        scripts.append(entries)
    return scripts


def _vibration(disc: Disc) -> dict:
    """PadVibrate's patterns (sound.md#vibration): per pattern its queue slot and the two motor
    scripts, each a list of u16 steps `flags(4) | level(4) | frames(8)` where flag 1 continues
    with the next step (a script whose first step has no flags is not started)."""
    def script(pointer: int) -> list[int]:
        words = []
        while True:
            word = disc.exe_u16(pointer + 2 * len(words), 1)[0]
            words.append(word)
            if word & 0xF000 != 0x1000:
                return words
    patterns = []
    for i in range(VIBRATION_PATTERN_COUNT):
        small, large = disc.exe_u32(VIBRATION_PATTERNS + 8 * i, 2)
        patterns.append([script(small), script(large)])
    return {
        "slots": disc.exe_u8(VIBRATION_SLOTS, VIBRATION_PATTERN_COUNT),
        "pulses": disc.exe_u8(VIBRATION_PULSES, VIBRATION_PULSE_COUNT),
        "patterns": patterns,
    }


def _voice_set(disc: Disc, addr: int) -> dict:
    """A g_charVoices record: the voice codes by category, the attack shouts, the damage voices
    (light, then heavy), the voice cooldown and five more sound ids. A set without shouts
    (Mokujin's) keeps the word after its count: FighterSounds picks shout
    `count * rand / 256` = 0 regardless and plays that word."""
    voices, shouts, damage = disc.exe_u32(addr, 3)
    counts = disc.exe_s16(voices, 4)
    shout_count = disc.exe_s16(shouts, 1)[0]
    light, heavy = disc.exe_s16(damage, 2)
    return {
        "counts": counts,
        "voices": disc.exe_u16(voices + 8, sum(counts)),
        "shouts": disc.exe_u16(shouts + 2, max(shout_count, 1)),
        "damage_counts": [light, heavy],
        "damage": disc.exe_u16(damage + 4, light + heavy),
        "cooldown": disc.exe_s16(addr + 12, 1)[0],
        "ids": disc.exe_u16(addr + 14, 5),
    }


def _char_records(disc: Disc) -> list[dict]:
    records = []
    for key, pointer in enumerate(disc.exe_u32(CHAR_RECORDS, COSTUME_KEYS_ALL)):
        rec = disc.exe_bytes(pointer, 12)
        name_at = struct.unpack_from("<I", rec)[0]
        name = disc.exe_text(name_at)
        records.append({"name": name, "base": rec[4], "unknown": list(rec[5:8]), "voice_set": rec[8],
                        "bank": rec[9], "stage": rec[10], "music": rec[11]})
    return records


def convert_fight(disc: Disc, out: Output) -> None:
    builtins = [disc.exe_u32(BUILTIN_ATTACKS + 8 * i, 2) for i in range(BUILTIN_ATTACK_COUNT)]
    out.write_json("tables/fight.json", {
        "common_branches": _branch_rows(disc, COMMON_BRANCHES, COMMON_BRANCH_COUNT),
        "sequences_a": _sequences(disc, SEQUENCES_A, SEQUENCES_A_COUNT),
        "sequences_b": _sequences(disc, SEQUENCES_B, SEQUENCES_B_COUNT),
        "builtin_attacks": [[ident, pointer - BUILTIN_BLOB] for ident, pointer in builtins],
        "builtin_blob": disc.exe_u8(BUILTIN_BLOB, BUILTIN_BLOB_BYTES),
        "air_kinds": [disc.exe_s16(AIR_KINDS + 4 * i, 2) for i in range(AIR_KIND_COUNT)],
        "push": disc.exe_s16(PUSH_TABLES, PUSH_ENTRIES),
        "launch_push": disc.exe_s16(LAUNCH_PUSH, 8),
        "reactions": [disc.exe_s16(REACTIONS + 2 * REACTION_WORDS * i, REACTION_WORDS)
                      for i in range(REACTION_COUNT)],
        "forced_reaction": disc.exe_s16(FORCED_REACTION, REACTION_WORDS),
        "throw_victim_slots": disc.exe_s16(THROW_VICTIM_SLOTS, THROW_VICTIM_COUNT),
        "close_reactions": [disc.exe_s16(CLOSE_REACTIONS + 4 * i, 2) for i in range(CLOSE_REACTION_COUNT)],
        "face_attack": disc.exe_u8(FACE_ATTACK, FACE_SLOTS),
        "face_hit": disc.exe_u8(FACE_HIT, FACE_SLOTS),
        "hurt_zone_joints": disc.exe_s32(HURT_ZONE_JOINTS, 14),
        "body_sphere_joints": disc.exe_s32(BODY_SPHERE_JOINTS, 8),
        "hurt_radii": [disc.exe_s16(p, 14) if p else [] for p in disc.exe_u32(HURT_RADII, CHARACTERS)],
        "body_radii": [disc.exe_s16(p, 8) if p >= 0x80010000 else [] for p in disc.exe_u32(BODY_RADII, CHARACTERS)],
        "health": disc.exe_s32(HEALTH, HEALTH_COUNT),
        "recovery_team": disc.exe_s32(RECOVERY_TEAM, 8),
        "recovery_survival": disc.exe_s32(RECOVERY_SURVIVAL, 8),
        "square_root": disc.exe_s16(SQUARE_ROOT, SQUARE_ROOT_COUNT),
        "reversal_lists": _positive_lists(disc, REVERSAL_LISTS, REVERSAL_LIST_COUNT),
        "shake_scripts": [_s8_until(disc, p, -128) for p in disc.exe_u32(SHAKE_SCRIPTS, 3)],
        "directions": [[w & 0xFFFF for w in disc.exe_s16(DIRECTIONS + 18 * side, 9)] for side in range(2)],
        "characters": _char_records(disc),
        "sound_codes": disc.exe_u16(SOUND_CODES, SOUND_CODE_COUNT),
        "sound_scripts": _sound_scripts(disc),
        "voices": [_voice_set(disc, VOICE_SETS + VOICE_SET_BYTES * i) for i in range(VOICE_SET_COUNT)],
        "impact_voices": disc.exe_u16(IMPACT_VOICES, 5),
        "round_voices": disc.exe_u16(ROUND_VOICES, ROUND_VOICE_COUNT),
        "result_voices": disc.exe_u16(RESULT_VOICES, RESULT_VOICE_COUNT),
        "vibration": _vibration(disc),
        "strike_sounds": disc.exe_u16(STRIKE_SOUNDS, 2),
        "special_sounds": disc.exe_u16(SPECIAL_SOUNDS, 3),
        "effects": _effects(disc),
    })
