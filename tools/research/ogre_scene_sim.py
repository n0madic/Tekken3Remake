#!/usr/bin/env python3
"""Integer port of the Ogre scene (arcade.ovl, Japan Rev.1): the set-up FUN_800B4168 (game
sub-states 15-16) and the per-frame runner FUN_800B4528 (sub-state 17).

The set-up reloads the defeated human's fighter as the stage-9 boss and places both fighters at
the origin; the runner plays a scene script in the Enbu event format (10-byte events `s16 frame,
kind, a, b, c`): kinds 2/3 play a move on fighter 0/1 from pose frame `b` to `c`, 5 starts a fade
at speed `a`, 6 starts music track 5, -1 ends the script. Each frame it steps the scripted moves
one pose frame, runs the camera and the fight's drawing steps, and draws the fade; after the
script ends it holds a full white fade for two more frames.

The fight engine, model loader and camera are called through `OgreHooks` (their ports live in
fight_sim.py and camera_sim.py or are described in the docs); the port owns the script, the
move stepping, the screen-clear tile and the fade. Verified by `tools/research/verify_ogre_scene_sim.py`.
"""

from __future__ import annotations

import draw_sim as ds
from fight_sim import Ram

M32 = 0xFFFFFFFF

FIGHTERS = (0x800A96F0, 0x800A96F0 + 0x188C)
EVENTS = 0x800B4F14              # the next script event
STATE = 0x800B4F18               # 0 start, 1 script, 2 closing
FRAME = 0x800B4F1C               # script frame (counts down in state 2)
PAUSE = 0x800B4F20               # bit 0 freezes the moves and the fade (only ever cleared)
FADE_ON, FADE_LEVEL, FADE_SPEED = 0x800B4F24, 0x800B4F28, 0x800B4F2C
MOVES = 0x800B4F34               # per fighter (10 bytes): s16 active, 0x16, slot, end frame, frame
CAMERA_READY = 0x800B4F48        # the camera reel's start result
UNUSED_4F4C = 0x800B4F4C
BLACK = 0x800B4F50               # the fade passed 0xD0: the stage is no longer drawn
CLEAR_TILES = 0x800B4F54         # per display buffer: a black TILE behind the scene
SCRIPTS = (0x800B0BF0, 0x800B0C24)   # the human is fighter 0 / fighter 1
SCENE_OTS = 0x800A911C
STAGE = 0x800AE14C
CAMERA_ARG = 0x80095890
ROUND_STATE_FLAG = 0x800972CC
SCREEN_W, SCREEN_H, LETTERBOX_H = 0x170, 0x1E0, 0x64
BOSS_COSTUMES = {True: (0x12, 0x13), False: (0x1A, 0x1B)}   # boss is Jin (player Heihachi) / Heihachi
HEIHACHI = 0xD


class OgreHooks:
    """The engine calls the scene makes. The defaults do nothing (return 0)."""

    def call(self, ram: Ram, name: str, *args: int) -> None:
        """One engine call without a result, by name:
        floor_setup(6) FUN_80048548 (clear tiles), menu_close(0) FUN_8004B920,
        fighter_reset(f) FUN_8003C4AC (+0x181C, +0x1820 = 0), face_opponent(f, g) FUN_8002BFCC,
        select_banks() SoundSelectBanks, costume_set(f, key) FUN_80036440 (+0x14 = slot of
        the costume key in 0x80095CE8, +0x1C = key), load_request(stage, a, b, c, d) FUN_8006C900
        (the resource request 0x800A0C50), model_nop(f, a, b) FUN_80035F34 (empty),
        model_bind(f, a, b) FighterSetupParts, load_commit(mask, 1) FUN_8006C924 (marks the
        requested resource as loaded), camera_reset() CameraReset, camera_restart(f0, f1)
        FUN_80069388 (camera choice counter, then camera_sources_reset), camera_sources_reset
        FUN_800661C0, move_events(f0, f1) MoveEvents, fighter_frame(f) FUN_8003AA6C (light
        direction, back colour, FighterAnimate), camera_director(f0, f1, a) CameraDirector,
        camera_frame(f0, f1) CameraFrame, clear_tile() FUN_8006DAB4, clear_tile_black(buffer)
        FUN_8004860C, stage_colour(stage) FUN_8003A030 (fighter base colour),
        body_profile(f0, f1) BodySphereProfile, light_decay() FUN_8003A1D8 (dynamic light
        countdown), shadow_matrices() FUN_80036254, frame_count() FUN_80037B4C,
        music(5, 0) MusicPlay."""

    def camera_reel(self, ram: Ram, kind: int) -> int:
        """FUN_800673E4: starts the camera reel `kind`; returns non-zero once it runs."""
        return 0

    def move_lookup(self, ram: Ram, fighter: int, slot: int) -> int:
        """MoveLookup (0x8002D3CC): the move record for a move slot."""
        return 0

    def load_character(self, ram: Ram, fighter: int) -> tuple[int, int]:
        """FighterLoadCharacter (0x80036564): the loaded model's two parts."""
        return 0, 0

    def model_parts(self, ram: Ram, index: int) -> tuple[int, int]:
        """FUN_80036124 and FUN_80036140: a loaded model's two parts."""
        return 0, 0


HOOKS = OgreHooks()


def _div4(v: int) -> int:
    """C division by 4 (toward zero)."""
    return -(-v >> 2) if v < 0 else v >> 2


def _clear_tile(ram: Ram) -> None:
    """AddPrim of this buffer's black tile at the scene OT's last entry (skipped while text is off)."""
    if ram.u32(ds.TEXT_OFF) == 0:
        p = CLEAR_TILES + 16 * ram.u32(ds.DISPLAY_BUFFER) & M32
        ds.link(ram, ram.u32(ram.u32(SCENE_OTS) + 4) + 0xFFC & M32, p, ram.u8(p + 3))


def _reload_boss(ram: Ram, human: int, other: int) -> None:
    """Reloads `human`'s record as the stage-9 boss and binds `other`'s model to it again."""
    f0, f1 = FIGHTERS
    boss = BOSS_COSTUMES[ram.s16(human + 0x18) == HEIHACHI][int(ram.u8(0x800AFF50 + 0xB1) != 0)]
    HOOKS.call(ram, "costume_set", human, boss)
    ram.put(human + 0x16, "h", _div4(ram.s16(human + 0x14)))
    ram.put(human + 0x18, "h", _div4(ram.s16(human + 0x14)))
    idx = ram.u8(other + 0x1E)
    HOOKS.call(ram, "load_request", ram.u16(STAGE), ram.s16(f0 + 0x1C), ram.s16(f0 + 0x1C), ram.s16(f1 + 0x16))
    a, b = HOOKS.load_character(ram, human)
    HOOKS.call(ram, "model_nop", human, a, b)
    HOOKS.call(ram, "model_bind", human, a, b)
    a, b = HOOKS.model_parts(ram, idx)
    HOOKS.call(ram, "model_bind", other, a, b)


def scene_setup(ram: Ram) -> None:
    """FUN_800B4168."""
    f0, f1 = FIGHTERS
    for a in (STATE, PAUSE, FADE_ON, UNUSED_4F4C, BLACK):
        ram.put(a, "I", 0)
    HOOKS.call(ram, "floor_setup", 6)
    ram.put(0x800AFF69, "B", 1)
    HOOKS.call(ram, "menu_close", 0)
    HOOKS.call(ram, "fighter_reset", f0)
    HOOKS.call(ram, "fighter_reset", f1)
    HOOKS.call(ram, "face_opponent", f0, f1)
    HOOKS.call(ram, "face_opponent", f1, f0)
    HOOKS.call(ram, "select_banks")
    for i in range(2):
        m = MOVES + 10 * i
        ram.put(m, "H", 0)
        ram.put(m + 2, "H", 0x16)
        ram.put(m + 4, "H", 0)
        ram.put(m + 8, "H", 0)
    if ram.u8(0x800AFF50 + 0x1D) & 1:
        ram.put(EVENTS, "I", SCRIPTS[0])
        _reload_boss(ram, f0, f1)
    else:
        ram.put(EVENTS, "I", SCRIPTS[1])
        _reload_boss(ram, f1, f0)
    HOOKS.call(ram, "load_commit", 1, 1)
    HOOKS.call(ram, "load_commit", 2, 1)
    for f in (f0, f1):
        ram.put(f + 0xE, "H", 0x4000)
    for f in (f0, f1):
        ram.put(f + 0xC, "H", 0)
        ram.put(f, "I", 0)
        ram.put(f + 4, "I", 0)
        ram.put(f + 0x10, "H", 0)
        ram.put(f + 8, "I", 0)
    for f in (f0, f1):
        ram.put(f + 0x2C, "H", ram.u16(f + 0xE))
    for i in range(2):
        p = CLEAR_TILES + 16 * i
        ram.put(p + 3, "B", 3)                       # SetTile
        ram.put(p + 7, "B", 0x60)
        for k in range(3):
            ram.put(p + 4 + k, "B", 0)
        ram.put(p + 8, "I", 0)
        ram.put(p + 0xC, "H", SCREEN_W)
        ram.put(p + 0xE, "H", SCREEN_H)
    _clear_tile(ram)


def _event(ram: Ram, ev: int) -> bool:
    """Runs one event; returns True at the end of the script."""
    kind = ram.s16(ev + 2)
    if kind == -1:
        ram.put(FRAME, "I", 2)
        ram.put(STATE, "I", ram.u32(STATE) + 1 & M32)
        return True
    if kind in (2, 3):
        f, m = FIGHTERS[kind - 2], MOVES + 10 * (kind - 2)
        slot = ram.s16(ev + 4)
        if ram.s16(m + 4) != slot:
            rec = HOOKS.move_lookup(ram, f, slot)
            ram.put(f + 0x54, "I", rec & M32)
            ram.put(f + 0x4C, "I", rec & M32)
        ram.put(m + 4, "H", ram.u16(ev + 4))
        ram.put(m + 8, "H", ram.u16(ev + 6))
        ram.put(m, "H", 1)
        ram.put(m + 6, "H", ram.u16(ev + 8))
    elif kind == 5:
        ram.put(FADE_LEVEL, "I", 0)
        ram.put(FADE_ON, "I", 1)
        ram.put(FADE_SPEED, "I", ram.s16(ev + 4) & M32)
    elif kind == 6:
        HOOKS.call(ram, "music", 5, 0)
    return False


def _step_moves(ram: Ram) -> None:
    f0, f1 = FIGHTERS
    for i, f in enumerate(FIGHTERS):
        m = MOVES + 10 * i
        if ram.s16(m) != 1:
            continue
        frame = ram.u16(m + 8) + 1 & 0xFFFF
        ram.put(f + 0x58, "H", frame)
        ram.put(f + 0x50, "H", frame)
        rec = ram.u32(f + 0x54)
        flags = ram.u32(rec + 0x24)
        ram.put(rec + 0x24, "I", flags & 0xBFFFFFFF)       # no sound events while scripted
        HOOKS.call(ram, "move_events", f0, f1)
        ram.put(ROUND_STATE_FLAG, "I", 1)
        HOOKS.call(ram, "fighter_frame", f)
        rec = ram.u32(f + 0x54)
        ram.put(rec + 0x24, "I", ram.u32(rec + 0x24) & 0xBFFFFFFF | flags & 0x40000000)
        if not ram.u32(PAUSE) & 1:
            ram.put(m + 8, "H", ram.u16(m + 8) + 1 & 0xFFFF)
        if ram.s16(m + 6) < ram.s16(m + 8):
            ram.put(m + 8, "H", ram.u16(m + 6))


def _camera(ram: Ram, pausable: bool) -> None:
    f0, f1 = FIGHTERS
    if ram.u32(CAMERA_READY) == 0:
        if not (pausable and ram.u32(PAUSE) & 1):
            ram.put(CAMERA_READY, "I", HOOKS.camera_reel(ram, 0) & M32)
    else:
        HOOKS.call(ram, "camera_director", f0, f1, CAMERA_ARG)


def scene_frame(ram: Ram) -> int:
    """FUN_800B4528: returns 1 when the scene is over (or in an unknown state)."""
    f0, f1 = FIGHTERS
    st = ram.s32(STATE)
    if st == 0:
        HOOKS.call(ram, "camera_reset")
        HOOKS.call(ram, "camera_restart", f0, f1)
        HOOKS.call(ram, "camera_sources_reset", f0, f1)
        HOOKS.camera_reel(ram, 2)
        ram.put(CAMERA_READY, "I", 0)
        p = CLEAR_TILES + 16 * ram.u32(ds.DISPLAY_BUFFER) & M32
        ram.put(p + 0xC, "H", SCREEN_W)
        ram.put(p + 0xE, "H", SCREEN_H)
        _clear_tile(ram)
        ram.put(FRAME, "I", 0)
        ram.put(STATE, "I", 1)
        return 0
    if st == 2:
        ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + 0x1C, ds._pkt(ram), 0x200))
        _camera(ram, False)
        t = ram.s32(FRAME) - 1
        ram.put(FRAME, "i", t)
        return int(t < 0)
    if st != 1:
        return 1
    if ram.s32(FRAME) >= 5:                                  # from frame 5 only the top 100 lines
        p = CLEAR_TILES + 16 * ram.u32(ds.DISPLAY_BUFFER) & M32
        ram.put(p + 0xC, "H", SCREEN_W)
        ram.put(p + 0xE, "H", LETTERBOX_H)
    if not ram.s32(FRAME) < ram.s16(ram.u32(EVENTS)):
        while True:
            ev = ram.u32(EVENTS)
            if _event(ram, ev):
                break
            ram.put(EVENTS, "I", ev + 10 & M32)
            if ram.s32(FRAME) < ram.s16(ev + 10):
                break
    _step_moves(ram)
    _camera(ram, True)
    HOOKS.call(ram, "camera_frame", f0, f1)
    if ram.u32(BLACK) == 0:
        HOOKS.call(ram, "clear_tile")
        _clear_tile(ram)
    else:
        HOOKS.call(ram, "clear_tile_black", ram.u32(ds.DISPLAY_BUFFER))
    HOOKS.call(ram, "stage_colour", ram.u16(STAGE))
    HOOKS.call(ram, "body_profile", f0, f1)
    HOOKS.call(ram, "light_decay")
    HOOKS.call(ram, "shadow_matrices")
    HOOKS.call(ram, "frame_count")
    if ram.u32(FADE_ON):
        level = ram.s32(FADE_LEVEL)
        if level >= 0xD0:
            ram.put(BLACK, "I", 1)
        if level > 0x100:
            ram.put(FADE_LEVEL, "I", 0x100)
        ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + 8, ds._pkt(ram), ram.s32(FADE_LEVEL) + 0x100))
        if ram.u32(PAUSE) & 1 == 0:
            ram.put(FADE_LEVEL, "I", ram.u32(FADE_LEVEL) + ram.u32(FADE_SPEED) & M32)
    ram.put(FRAME, "I", ram.u32(FRAME) + 1 & M32)
    return 0
