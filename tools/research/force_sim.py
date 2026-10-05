#!/usr/bin/env python3
"""Integer port of Tekken Force's level script runner and screens (force.ovl, Japan Rev.1).

`level_script` is FUN_800B1778 up to the start of its enemy-slot state machine (0x800B25A8):
the script commands (scroll mode, spawns, spawn patterns, waits, items, end of level), the
wait state, the end-of-level states with NOW LOADING, the bonus frame that shows the remaining
bonus time over the player (projected with projection_sim) and the bonus tally, the boss set-up
and the pattern spawner. The enemy-slot machine (model loading, entrances, defeat) that follows
calls into the fight engine and is described in modes.md. Ghidra's decompile drops the whole
tally (it takes the counter `0x800B6A6C` for read-only data); this port follows the disassembly.
Also ported: the HUD key icons and the level progress bar. Verified by `tools/research/verify_force_sim.py`.
"""

from __future__ import annotations

import draw_sim as ds
import screens_sim as ss
from fight_sim import Ram

M32 = 0xFFFFFFFF

STATE = 0x800B70DC               # end-of-level state
CLOCK = 0x800B70D4               # frames while the fight runs (not frozen by 0x800958B8)
DRAWN = 0x800B6AE4               # frames with text on
TALLY = 0x800B6A6C               # the tally's frame counter
SCORE = 0x800B70EC
LEVEL = 0x800B7104
STAGE_BONUS = 0x800B0BD0         # per level: 5,000 / 10,000 / 15,000 / 20,000
CLEAR_BONUS = 0x800B6AE0         # health left x 100
CLEAR_TIME, BONUS_TIME = 0x800B6AD8, 0x800B6ADC
TIMER = 0x800AE094               # the fight timer (frames)
TALLY_DONE = 0x800B70E0
KEY_EARNED, FINAL_CHALLENGE = 0x800B70FC, 0x800B70F8
KEYS = 0x800B70D0
STR_NOW_LOADING = 0x800B0D54
STR_STAGE_BONUS, STR_CLEAR_BONUS = 0x800B0D80, 0x800B0D9C
STR_CLEAR_TIME, STR_BONUS_TIME = 0x800B0DB8, 0x800B0DDC
STR_KEY, STR_FINAL = 0x800B0E00, 0x800B0E18


def _mss(t: int) -> tuple[int, int, int]:
    """Frames as minutes (mod 60), seconds and hundredths, with the game's truncating divisions."""
    m = ds._sdiv(t, 3600)
    return m - ds._sdiv(m, 60) * 60, ds._sdiv(t, 60) - 60 * m, ds._smod(ds._sdiv(t * 100, 60), 100)


def tally(ram: Ram) -> None:
    """State 7: STAGE BONUS, CLEAR BONUS, CLEAR TIME and BONUS TIME (or the key / final stage
    message) appear 30 frames apart, each with sound 0x4C6C (0x4CEB for the key and final stage
    messages, FUN_800B4A1C); the bonuses are added as they appear."""
    t = ram.s32(TALLY) + 1
    ram.put(TALLY, "i", t)
    if t >= 0x1E:
        bonus = ram.u32(STAGE_BONUS + 4 * ram.s32(LEVEL) & 0xFFFFFFFF)
        if t == 0x1E:
            ram.put(SCORE, "I", ram.u32(SCORE) + bonus & 0xFFFFFFFF)
            HOOKS.sound(ram, 0x4C6C)
        ds.text(ram, STR_STAGE_BONUS, 1, 4, 0x2F, 0xB4, bonus)
    if t >= 0x3C:
        if t == 0x3C:
            ram.put(SCORE, "I", ram.u32(SCORE) + ram.u32(CLEAR_BONUS) & 0xFFFFFFFF)
            HOOKS.sound(ram, 0x4C6C)
        ds.text(ram, STR_CLEAR_BONUS, 1, 1, 0x2F, 0xE8, ram.u32(CLEAR_BONUS))
    cs = 0
    if t >= 0x5A:
        if t == 0x5A:
            HOOKS.sound(ram, 0x4C6C)
        m, s, cs = _mss(ram.s32(CLEAR_TIME))
        ds.text(ram, STR_CLEAR_TIME, 1, 5, 0x2F, 0x11C, m, s, cs)
    if t < 0x78:
        return
    ram.put(TALLY_DONE, "I", 1)
    b = ram.s32(BONUS_TIME)
    if ram.s32(LEVEL) < 3 and b:
        m, s, c = _mss(b)
        if cs + c < 100:
            c = 100 - cs
        ds.text(ram, STR_BONUS_TIME, 1, 6, 0x2F, 0x150, m, s, c)
        if t == 0x78:
            ram.put(TIMER, "I", ram.u32(TIMER) + b & 0xFFFFFFFF)
            HOOKS.sound(ram, 0x4C6C)
    elif ram.u32(KEY_EARNED):
        ds.text(ram, STR_KEY, 1, 6 if t & 2 else 2, 0x56, 0x150)
        if t == 0x78:
            ram.put(KEYS, "I", ram.u32(KEYS) + 1 & 0xFFFFFFFF)
            HOOKS.sound(ram, 0x4CEB)
    elif ram.u32(FINAL_CHALLENGE):
        ds.text(ram, STR_FINAL, 1, 6 if t & 4 else 2, 0x22, 0x150)
        if t == 0x78:
            HOOKS.sound(ram, 0x4CEB)


class ForceHooks:
    """Calls into the fight engine and sound: the music fade FUN_8006BF80(a, 30), a fighter's
    move start FUN_8002D93C(fighter, slot) and the enemy action set-up FUN_800B362C(a, b, c).
    The defaults do nothing; the verifier logs them."""

    def music_fade(self, ram: Ram, a: int) -> None:
        pass

    def start_move(self, ram: Ram, fighter: int, slot: int) -> None:
        pass

    def enemy_action(self, ram: Ram, a: int, b: int, c: int) -> None:
        pass

    def sound(self, ram: Ram, sound_id: int) -> None:
        """SoundPlayFighter(0, id, 0)."""

    def model_reset(self, ram: Ram, fighter: int) -> None:
        """FUN_800363FC: releases the fighter's model before a new costume."""

    def model_request(self, ram: Ram, index: int, key: int) -> None:
        """FUN_800360B0(fighter index, costume key + 1): loads a model."""

    def model_parts(self, ram: Ram, index: int) -> tuple[int, int]:
        """FUN_80036124 and FUN_80036140: the loaded model's two parts."""
        return 0, 0

    def model_bind(self, ram: Ram, fighter: int, a: int, b: int) -> None:
        """FUN_80035F3C: attaches the loaded model to the fighter."""


HOOKS = ForceHooks()
SLOTS = 0x800B6A7C               # 2 enemy slots, 0x18 bytes: fighter, ..., s16 state at +8, type +0xE, costume +0x10/+0x12
SCRIPT_PTR = 0x800B6ABC          # the next 20-byte script record
PLAYER_FIGHTER = 0x800B6AB4      # FUN_800B2E70(0)
SCROLL_PARAM, SCROLL_MODE = 0x800B6A70, 0x800B70B4
WAIT_DEFEATED, WAIT_COUNT = 0x800B6AC0, 0x800B6AC4
PATTERN_ON, PATTERN_STOP_X, PATTERN_PTR = 0x800B6AC8, 0x800B6ACC, 0x800B6AD0
PATTERNS = 0x800B0A10            # 6-byte (costume, type, 0) entries, 99 ends a pattern
ALLOWANCE = 0x800B0BBC           # per level: bonus time allowance (frames)
FIGHT_START_TIMER = 0x800B6AD4
ITEMS = 0x800B6E90               # 2 x 0xBC: state, x, _, z, ...
ENEMY_HEALTH = 0x800B0B4C        # per level (5 types, 16.16)
CAMERA = 0x800A8A88              # camera record: x at +0x14
STR_BONUS_LEFT = 0x800B0D6C      # "%f%c%H%V%2D\"%02D"
PROJ_SCRATCH = 0x1F800300        # the game uses its stack


def free_slot(ram: Ram) -> int:
    """FUN_800B2EB0: the first enemy slot in state 1 (free), or 0."""
    for i in range(2):
        if ram.s16(SLOTS + 0x18 * i + 8) == 1:
            return SLOTS + 0x18 * i
    return 0


def slot_release(ram: Ram, slot: int) -> None:
    """FUN_800B2F30."""
    f = ram.u32(slot)
    ram.put(f + 0x3F4, "I", 0)
    ram.put(f + 0xC3, "B", 0)
    ram.put(f + 0xC2, "B", 1)
    ram.put(slot + 8, "H", 1)


def place_fighter(ram: Ram, f: int, x: int, z: int) -> None:
    """FUN_800B2F50."""
    for off, v in ((0xF68, x), (0, x), (0xF70, z), (8, z)):
        ram.put(f + off, "I", v & M32)


def place_item(ram: Ram, x: int, z: int) -> None:
    """FUN_800B4328: the first free item slot gets the item."""
    for i in range(2):
        it = ITEMS + 0xBC * i
        if ram.u32(it) == 0:
            ram.put(it + 4, "I", x & M32)
            ram.put(it + 0xC, "I", z & M32)
            ram.put(it, "I", 1)
            return


def scroll_mode(ram: Ram, mode: int) -> None:
    """FUN_800B53E0: 0 free scrolling, 1 locked, 2 locked with bounds 5,000 units either side."""
    if mode == 0:
        ram.put(0x800B70C4, "I", 1)
    elif mode == 2:
        r = 0x800B7098
        x = ram.s32(r + 4)
        for off, v in ((0x28, -100), (0x2C, 60), (0x30, x - 5000), (0x34, x + 5000)):
            ram.put(r + off, "i", ds._s32(v))
    ram.put(SCROLL_MODE, "I", mode & M32)


def _spawn(ram: Ram, slot: int, costume: int, kind: int, x: int, z: int) -> None:
    """A new enemy in `slot`: state 4 (enter) when the model is already loaded, else 2 (load)."""
    if ram.s16(slot + 0x10) == costume:
        ram.put(slot + 8, "H", 4)
    else:
        ram.put(slot + 8, "H", 2)
        ram.put(slot + 0x12, "H", costume & 0xFFFF)
    ram.put(slot + 0xE, "H", ds._smod(ds._s16(kind), 5) & 0xFFFF)
    place_fighter(ram, ram.u32(slot), x, z)


def _commands(ram: Ram, progress: int) -> None:
    """State 0: runs every script record whose trigger the camera has passed."""
    if ram.u32(0x80097350) != 1 or progress < ram.s32(ram.u32(SCRIPT_PTR)):
        return
    stop = False
    while not stop:
        rec = ram.u32(SCRIPT_PTR)
        cmd = ram.s16(rec + 4)
        cam = ram.s32(CAMERA + 0x14)
        if cmd == 0:
            ram.put(SCROLL_PARAM, "i", ram.s16(rec + 0xE))
            scroll_mode(ram, ram.s16(rec + 0xE))
        elif cmd == 1:
            slot = free_slot(ram)
            if slot:
                _spawn(ram, slot, ram.u16(rec + 0xE), ram.u16(rec + 0x10), cam + ram.s16(rec + 6), ram.s16(rec + 0xA))
        elif cmd == 2:
            ram.put(PATTERN_ON, "I", ram.u32(PATTERN_ON) + 1 & M32)
            ram.put(PATTERN_STOP_X, "I", ram.u16(rec + 0x10))
            if ram.u16(rec + 0xE) < 0x31:
                ram.put(PATTERN_PTR, "I", PATTERNS + 6 * ram.s16(rec + 0xE) & M32)
        elif cmd == 3:
            stop = True
            ram.put(WAIT_DEFEATED, "I", 0)
            ram.put(STATE, "I", 1)
            ram.put(WAIT_COUNT, "i", ram.s16(rec + 0xE))
        elif cmd == 4:
            place_item(ram, cam + ram.s16(rec + 6), ram.s16(rec + 0xA))
        elif cmd == 6:
            for i in range(2):
                slot_release(ram, SLOTS + 0x18 * i)
            HOOKS.music_fade(ram, 0)
            stop = True
            ram.put(ds.MODE + 4, "B", 0)
            ram.put(PATTERN_ON, "I", 0)
            ram.put(STATE, "I", 3)
            ram.put(TALLY, "I", ram.u32(CLOCK) + 0x3C & M32)
        ram.put(SCRIPT_PTR, "I", rec + 0x14)
        if progress < ram.s32(rec + 0x14):
            break


def _bonus_frame(ram: Ram, gte) -> None:
    """State 6: clear and bonus time, the remaining bonus time over the player, and on the stage
    clear (round state 8) the clear bonus and the key rule."""
    import projection_sim as pj
    player = ram.u32(PLAYER_FIGHTER)
    clear = ram.s32(FIGHT_START_TIMER) - ram.s32(TIMER)
    bonus = ram.s32(ALLOWANCE + 4 * ram.s32(LEVEL) & M32) - clear
    ram.put(CLEAR_TIME, "i", ds._s32(clear) if clear >= 0 else 0)
    ram.put(BONUS_TIME, "i", ds._s32(bonus) if bonus >= 0 else 0)
    b = ram.s32(BONUS_TIME)
    if b > 0 and ram.s32(player + 0x3F4) > 0:
        sx, sy, _ = pj.screen_of(ram, gte, ram.s32(player + 0x990), ram.s32(player + 0x994) - 500,
                                 ram.s32(player + 0x998), PROJ_SCRATCH)
        ds.text(ram, STR_BONUS_LEFT, 0, 5, (sx & 0xFFFF) - 0x16, sy, ds._smod(ds._sdiv(b, 60), 60),
                ds._smod(ds._sdiv(ds._s32(b * 100), 60), 100))
    if ram.u32(0x80097350) != 8:
        return
    health = ram.s32(0x800A9AE4)
    ram.put(CLEAR_BONUS, "i", ds._s32((health + 0xFFFF if health < 0 else health) >> 16) * 100)
    if ram.s32(LEVEL) == 3:
        dr_b = ram.u32(0x800982D0) >> 19 & 1
        keys = ram.s32(KEYS)
        if keys < 3 and not dr_b:
            ram.put(KEY_EARNED, "I", 1)
            n = ram.u8(0x800982F8) + 1
            ram.put(0x800982F8, "B", min(n, 0xFF))
            ss.save_pending(ram)
            flag = {0: 1, 1: 3, 2: 7}.get(keys)
            if flag:
                ram.put(ds.MODE + 0x40, "B", ram.u8(ds.MODE + 0x40) | flag)
        elif keys == 3 and not dr_b:
            ram.put(FINAL_CHALLENGE, "I", 1)
    ram.put(TALLY, "I", 0)
    ram.put(STATE, "I", 7)


def _boss(ram: Ram) -> None:
    """State 8 (the level-4 boss fight): slot 0 becomes a type-4 enemy with the level's boss
    health, its entrance starts, the camera locks (scroll mode 2) and state 9 times the fight."""
    slot = SLOTS
    f = ram.u32(slot)
    ram.put(slot + 0xE, "H", 4)
    ram.put(slot + 8, "H", 1)
    ram.put(slot + 0xA, "H", 0)
    HOOKS.start_move(ram, f, 3)
    ram.put(f + 0xC3, "B", 1)
    hp = ram.u32(ENEMY_HEALTH + 20 * ram.s32(LEVEL) + 4 * ram.s16(slot + 0xE) & M32)
    ram.put(f + 0xC2, "B", 0)
    ram.put(f + 4, "I", 0)
    ram.put(f + 0x92, "H", 0)
    ram.put(f + 0xB8, "B", 0)
    ram.put(f + 0x3F8, "I", hp)
    ram.put(f + 0x3F4, "I", hp)
    HOOKS.enemy_action(ram, 1, 0x13, 0)
    ram.put(SCROLL_PARAM, "I", 2)
    scroll_mode(ram, 2)
    ram.put(0x800B70E8, "I", 1)
    ram.put(STATE, "I", 9)
    ram.put(FIGHT_START_TIMER, "I", ram.u32(TIMER))


def _patterns(ram: Ram, progress: int) -> None:
    """The spawn pattern (script command 2): a new enemy enters from the right (camera x + 5,000)
    whenever a slot is free, until the pattern ends or the camera passes its stop."""
    n = ram.u32(PATTERN_ON)
    if n != 1:
        return
    if not progress < ram.s32(PATTERN_STOP_X):
        ram.put(PATTERN_ON, "I", 0)
        return
    pat = ram.u32(PATTERN_PTR)
    if ram.u16(pat) == 0x63:
        return
    slot = free_slot(ram)
    if not slot:
        return
    _spawn(ram, slot, ram.u16(pat), ram.u16(pat + 2), ram.s32(CAMERA + 0x14) + 5000, 0)
    ram.put(PATTERN_PTR, "I", pat + 6 & M32)


def level_script(ram: Ram, gte) -> int:
    """FUN_800B1778 up to its enemy-slot state machine (0x800B25A8); returns 1 on the frame
    NOW LOADING ends (FightFrame then changes the area, round state 7)."""
    area_change = 0
    progress = ds._s32(ram.s32(CAMERA + 0x14) - ram.s32(0x800B70E4))
    if ram.u32(0x800958B8) == 0:
        ram.put(CLOCK, "I", ram.u32(CLOCK) + 1 & M32)
    if ram.u32(ds.TEXT_OFF) == 0:
        ram.put(DRAWN, "I", ram.u32(DRAWN) + 1 & M32)
    st = ram.u32(STATE)
    clock = ram.s32(CLOCK)
    frozen = ram.u32(0x800958B8)
    if st == 0:
        _commands(ram, progress)
    elif st == 1:                                   # wait for kills, or both slots empty
        w = ram.s32(WAIT_COUNT)
        if w < 0:
            if ram.s16(SLOTS + 8) == 1 and ram.s16(SLOTS + 0x18 + 8) == 1:
                ram.put(STATE, "I", 0)
        elif not ram.s32(WAIT_DEFEATED) < w:
            ram.put(STATE, "I", 0)
    elif st == 3:                                   # wait for the frozen fight to resume
        if ram.s32(TALLY) < clock and not frozen:
            ram.put(TALLY, "I", clock + 2 & M32)
            ram.put(STATE, "I", 4)
    elif st == 4:
        ds.text(ram, STR_NOW_LOADING, 0, 6, 0xF2, 0x1A6)
        if ram.s32(TALLY) < clock and not frozen:
            area_change = 1
            ram.put(STATE, "I", 5)
    elif st == 5:
        ram.put(0x800B70E8, "I", 1)
        ram.put(ds.MODE + 4, "B", 1)                # 0x800AFF54
        ram.put(STATE, "I", 6)
        ram.put(FIGHT_START_TIMER, "I", ram.u32(TIMER))
    elif st == 6:
        _bonus_frame(ram, gte)
    elif st == 7:
        tally(ram)
    elif st == 8:
        _boss(ram)
    elif st == 9:
        d = ram.s32(FIGHT_START_TIMER) - ram.s32(TIMER)
        ram.put(CLEAR_TIME, "i", max(d, 0))
        if ram.u32(0x80097350) == 8:
            ram.put(TALLY, "I", 0)
            ram.put(STATE, "I", 10)
            ram.put(ds.MODE + 0x40, "B", ram.u8(ds.MODE + 0x40) | 8)
    elif st == 10:
        t = ram.s32(TALLY)
        ram.put(TALLY, "i", t + 1)
        if t >= 0xB5:
            ram.put(TALLY_DONE, "I", 1)
    _patterns(ram, progress)
    return area_change


ENEMY_KEYS = 0x800B0BB0          # per level: the two costume keys (variant 0, 1)
KILL_SECONDS = 0x800B0B38        # per enemy type: u16 ?, u16 seconds added for a kill
HISCORE_RUN = 0x800B7100
SCORE_CAP = 99_999_990
COUNTDOWN_SOUNDS = 0x8009747E    # sounds for 1..5 seconds left


def enemy_key(ram: Ram, level: int, variant: int) -> int:
    """FUN_800B2F64."""
    return ram.u8(ENEMY_KEYS + 2 * (level & 3) + (variant & 1))


def _enemy_slot(ram: Ram, gte, slot: int, player: int) -> None:
    """One enemy slot's state: 0 release, 1 free, 2-3 load the costume's model, 4 enter with full
    health, 5 fight, 6 defeated (+n SEC), 7 blink out."""
    import projection_sim as pj
    f = ram.u32(slot)
    st = ram.s16(slot + 8)
    clock = ram.s32(CLOCK)
    if st == 0:
        ram.put(f + 0xC3, "B", 0)
        ram.put(f + 0x3F4, "I", 0)
        ram.put(f + 0xC2, "B", 1)
        ram.put(slot + 8, "H", 1)
    elif st == 2:
        ram.put(f + 0xC3, "B", 0)
        ram.put(slot + 8, "H", 3)
        ram.put(slot + 0xC, "H", ram.u16(DRAWN) + 2 & 0xFFFF)
    elif st == 3:
        if ram.s16(slot + 0xC) < ram.s32(DRAWN) and not ram.u32(ds.TEXT_OFF):
            costume = ram.u16(slot + 0x12)
            ram.put(slot + 0x10, "H", costume)
            key = enemy_key(ram, ram.s32(LEVEL), ds._s16(costume))
            ram.put(f + 0x14, "H", key + 0x54)
            HOOKS.model_reset(ram, f)
            idx = ram.u8(f + 0x1E)
            HOOKS.model_request(ram, idx, ram.s16(slot + 0x10) + 1)
            a, b = HOOKS.model_parts(ram, idx)
            HOOKS.model_bind(ram, f, a, b)
            HOOKS.enemy_action(ram, idx, 0x15, key)
            ram.put(slot + 8, "H", 4)
    elif st == 4:
        ram.put(f + 0xC3, "B", 1)
        hp = ram.u32(ENEMY_HEALTH + 20 * ram.s32(LEVEL) + 4 * ram.s16(slot + 0xE) & M32)
        ram.put(f + 0xC2, "B", 0)
        ram.put(f + 0x3F8, "I", hp)
        ram.put(f + 0x3F4, "I", hp)
        ram.put(slot + 8, "H", 5)
        HOOKS.start_move(ram, f, 3)
        ram.put(f + 4, "I", 0)
        ram.put(f + 0x92, "H", 0)
        ram.put(f + 0xB8, "B", 0)
    elif st == 5:
        if ram.s32(f + 0x3F4) > 0:
            return
        ram.put(slot + 8, "H", 6)
        ram.put(slot + 0xC, "H", ram.u16(CLOCK) + 0x3C & 0xFFFF)
        if ram.u8(f + 0x22) != ram.u8(player + 0x1E) and ram.u8(f + 0xE7) == 0:
            return
        t = ram.s32(TIMER)
        sec = ram.u16(KILL_SECONDS + 4 * ram.s16(slot + 0xE) + 2 & M32)
        ram.put(TIMER, "I", t + 59 - ds._smod(t, 60) + sec * 60 & M32)
        sx, sy, _ = pj.screen_of(ram, gte, ram.s32(f + 0x990), ram.s32(f + 0x994) - 300, ram.s32(f + 0x998),
                                 PROJ_SCRATCH)
        ram.put(slot + 4, "H", (sx & 0xFFFF) - 0x1B & 0xFFFF)
        ram.put(slot + 6, "H", sy << 4 & 0xFFFF)
        ram.put(slot + 0x14, "H", ram.u16(CLOCK) + 0x3C & 0xFFFF)
        ram.put(ds.MODE + 0x3C, "H", ram.u16(ds.MODE + 0x3C) + 1 & 0xFFFF)
    elif st == 6:
        if clock < ram.s16(slot + 0x14):
            y = ram.s16(slot + 6) >> 4
            sec = ram.u16(KILL_SECONDS + 4 * ram.s16(slot + 0xE) + 2 & M32)
            ds.text(ram, 0x800B0E38, 0, 5, ram.s16(slot + 4), y + 4)
            ds.text(ram, 0x800B0E44, 1, y, sec)
            ds.text(ram, 0x800B0E4C, 0, 6, y + 6)
            if ram.u32(0x800958B8) == 0:
                ram.put(slot + 6, "H", ram.u16(slot + 6) - 8 & 0xFFFF)
        if ram.s16(slot + 0xC) < ram.s32(CLOCK) and ram.u8(f + 0xC4) == 0:
            ram.put(slot + 8, "H", 7)
            ram.put(slot + 0xC, "H", ram.u16(CLOCK) + 0x28 & 0xFFFF)
            ram.put(f + 0xC2, "B", 1)
        elif ram.u8(f + 0xCE) and ram.u8(f + 0x22) == ram.u8(player + 0x1E):
            ram.put(slot + 0xC, "H", ram.u16(CLOCK) + 0x3C & 0xFFFF)
    elif st == 7:
        ram.put(f + 0xC3, "B", ram.u8(CLOCK) & 1)
        if ram.s16(slot + 0xC) < ram.s32(CLOCK):
            ram.put(WAIT_DEFEATED, "I", ram.u32(WAIT_DEFEATED) + 1 & M32)
            ram.put(f + 0xC3, "B", 0)
            ram.put(slot + 8, "H", 1)


def level_frame(ram: Ram, gte) -> int:
    """FUN_800B1778 in full: the script (level_script), the two enemy slots, the progress bar,
    the items, the key icons, the score cap and hi-score, the 99-second timer cap and the
    announcer's countdown at 5-1 seconds. Returns 1 when the area changes."""
    player = ram.u32(PLAYER)
    area_change = level_script(ram, gte)
    for i in range(2):
        _enemy_slot(ram, gte, SLOTS + 0x18 * i, player)
    progress_draw(ram)
    items(ram, gte)
    key_icons(ram)
    if SCORE_CAP < ram.u32(SCORE):
        ram.put(SCORE, "I", SCORE_CAP)
    if ram.u32(HISCORE_RUN) < ram.u32(SCORE):
        ram.put(ds.MODE + 0x3F, "B", 1)
        ram.put(HISCORE_RUN, "I", ram.u32(SCORE))
    if ram.s32(TIMER) >= 0x1735:
        ram.put(TIMER, "I", 0x1734)
    if ram.u32(0x800958B8) == 0 and ram.u32(0x80097350) == 1:
        t = ram.s32(TIMER)
        if t in (60, 120, 180, 240, 300):
            HOOKS.sound(ram, ram.u16(COUNTDOWN_SOUNDS + 2 * (t // 60 - 1)))
    return area_change


# ---- items ----
ITEM_QUADS = 0x800B6DF0          # per item (0xBC): per buffer two POLY_FT4 (0x28 each), the second 0x50 on
STR_LIFE_UP = 0x800B0EF0         # "%f%c%H%V LIFE UP!"
PLAYER = 0x800B6AAC              # FUN_800B2E60


def health_flash(ram: Ram, fighter: int) -> None:
    """FUN_8003A388: in Tekken Force, starts the fighter's back colour flash (projection_sim.fighter_back_colour)."""
    if ram.u32(ds.MODE) == 8:
        ram.put(0x8009E998 + ram.s16(fighter + 0x12) & M32, "B", 1)


def _set_quad(ram: Ram, p: int, x0: int, x1: int, y0: int, y1: int) -> None:
    for off, x, y in ((8, x0, y0), (0x10, x1, y0), (0x18, x0, y1), (0x20, x1, y1)):
        ram.put(p + off, "H", x & 0xFFFF)
        ram.put(p + off + 2, "H", y & 0xFFFF)


def items(ram: Ram, gte) -> None:
    """FUN_800B4374: the two item slots. A placed item (state 1) is drawn as two camera-facing
    quads over its projected position and removed 5,000 units behind the camera; the player
    picks it up within 500 units in x and z (health +50, sound 0x4E6A), which starts LIFE UP!
    (state 2: rising half a pixel per frame for 60 frames, sound 0x87C0 15 frames before the end)."""
    import projection_sim as pj
    player = ram.u32(PLAYER)
    for i in range(2):
        it = ITEMS + 0xBC * i
        state = ram.u32(it)
        if state == 1:
            if ram.s32(it + 4) < ds._s32(ram.s32(CAMERA + 0x14) - 5000):
                ram.put(it, "I", 0)
                continue
            if not ram.u32(ds.TEXT_OFF):
                sx, sy, z4 = pj.screen_of(ram, gte, ram.s32(it + 4), ram.s32(it + 8), ram.s32(it + 0xC), PROJ_SCRATCH)
                depth = ((z4 & 0x3FFF) >> 3) - 1
                d = z4 or 1
                w, h = ds._sdiv(0x15E00, d), ds._sdiv(0x2BC00, d)
                left = (sx & 0xFFFF) - ds._sdiv(w, 2)
                base = sy - h
                right = left + w
                ot = ram.u32(ram.u32(0x800A911C) + 4) + 4 * depth & M32
                p = ITEM_QUADS + 0xBC * i + 0x28 * ram.u32(ds.DISPLAY_BUFFER) & M32
                _set_quad(ram, p, left, right, base - h, base)
                ds.link(ram, ot, p, ram.u8(p + 3))
                q = p + 0x50
                _set_quad(ram, q, left, right, base - w, base)
                ds.link(ram, ot + 4 & M32, q, ram.u8(q + 3))
            dx = abs(ds._s32(ram.s32(player + 0xF68) - ram.s32(it + 4)))
            dz = abs(ds._s32(ram.s32(player + 0xF70) - ram.s32(it + 0xC)))
            hp = ram.s32(player + 0x3F4)
            if dx < 0x1F5 and dz < 0x1F5 and hp > 0 and ram.u8(player + 0xDB) == 0:
                ram.put(player + 0x3F4, "I", hp + 0x320000 & M32)
                HOOKS.sound(ram, 0x4E6A)
                sx, sy, _ = pj.screen_of(ram, gte, ram.s32(player + 0x990), ram.s32(player + 0x994) - 300,
                                         ram.s32(player + 0x998), PROJ_SCRATCH)
                ram.put(it, "I", 2)
                ram.put(it + 0x18, "I", ram.u32(CLOCK) + 0x3C & M32)
                ram.put(it + 0x14, "H", (sx & 0xFFFF) - 0x24 & 0xFFFF)
                ram.put(it + 0x16, "H", sy << 4 & 0xFFFF)
                health_flash(ram, player)
        elif state == 2:
            colour = 2 if ram.u32(CLOCK) & 2 else 5
            if ram.u32(0x800958B8) == 0:
                ram.put(it + 0x16, "H", ram.u16(it + 0x16) - 8 & 0xFFFF)
            ds.text(ram, STR_LIFE_UP, 0, colour, ram.s16(it + 0x14), ram.s16(it + 0x16) >> 4)
            if ram.u32(CLOCK) == ram.u32(it + 0x18) - 0xF & M32:
                HOOKS.sound(ram, 0x87C0)
            if ram.s32(it + 0x18) < ram.s32(CLOCK):
                ram.put(it, "I", 0)


# ---- key icons on the HUD ----
KEY_ICONS = 0x800B6F80           # per display buffer (0x3C bytes): 3 SPRTs, copper, silver, gold
KEY_ICON_MODE = 0x800B6F70       # per display buffer: a one-word draw mode packet
KEY_ICON_SOURCE = ((0x140, 0x80), (0x164, 0x90), (0x188, 0xA0))   # VRAM y at x 688; CLUT x at y 486


def key_icons_setup(ram: Ram) -> None:
    """FUN_800B4740: builds both buffers' key sprites (20 x 36 at x 0, 20, 40, y 420)."""
    for b in range(2):
        m = KEY_ICON_MODE + 8 * b
        ram.put(m + 3, "B", 1)
        ram.put(m + 4, "I", 0xE100021A)
        for i, (vy, cx) in enumerate(KEY_ICON_SOURCE):
            p = KEY_ICONS + 0x3C * b + 0x14 * i
            ram.put(p + 3, "B", 4)
            ram.put(p + 7, "B", 0x64)               # SetSprt, SetShadeTex(p, 0)
            ram.put(p + 0x10, "H", 0x14)
            ram.put(p + 0x12, "H", 0x24)
            for k in (4, 5, 6):
                ram.put(p + k, "B", 0x80)
            ram.put(p + 0xE, "H", 0x1E6 << 6 | cx >> 4 & 0x3F)
            ram.put(p + 8, "H", 0x14 * i)
            ram.put(p + 0xD, "B", vy & 0xFF)
            ram.put(p + 0xC, "B", (0x2B0 & 0x3F) << 2)
            ram.put(p + 0xA, "H", 0x1A4)


def key_icons(ram: Ram) -> None:
    """FUN_800B4924: one key per key earned (KEYS), while text is on."""
    if ram.u32(ds.TEXT_OFF):
        return
    b = ram.u32(ds.DISPLAY_BUFFER)
    ot = ds.ot_text(ram)
    for i in range(3):
        if ram.s32(KEYS) > i:
            _add_prim(ram, ot, KEY_ICONS + 0x3C * b + 0x14 * i & M32)
    _add_prim(ram, ot, KEY_ICON_MODE + 8 * b & M32)


def _add_prim(ram: Ram, ot: int, p: int) -> None:
    """AddPrim (0x8007BE98): links a prebuilt packet, keeping its length byte."""
    ds.link(ram, ot, p, ram.u8(p + 3))


# ---- the level progress bar ----
BAR_QUADS = 0x800B6B30           # per buffer (200 bytes): 4 level segments + the rest of the current one (POLY_FT4)
BAR_LINES = 0x800B6D20           # per buffer (100 bytes): 5 separators (LINE_G2)
BAR_MARKER = 0x800B6CC0          # per buffer: the camera marker (LINE_F2)
BAR_POINTER = 0x800B6CE0         # per buffer (0x1C bytes): the pointer above it (POLY_G3)
BAR_PHASE, BAR_DONE = 0x800B6DE8, 0x800B6DEC
BAR_COLOURS = 0x800B69FC         # 4 x RGB: the segments' CLUT colours (uploaded to VRAM (16k, 486))
CAMERA_X, LEVEL_START_X, LEVEL_ENDED = 0x800A8A9C, 0x800B70E4, 0x800B70E8
SIN_TABLE = 0x8001E8C4
BAR_TOP, BAR_BOTTOM = 0x1B4, 0x1C4


def _xy4(ram: Ram, p: int, x0: int, x1: int) -> None:
    for off, x, y in ((8, x0, BAR_TOP), (0x10, x1, BAR_TOP), (0x18, x0, BAR_BOTTOM), (0x20, x1, BAR_BOTTOM)):
        ram.put(p + off, "H", x & 0xFFFF)
        ram.put(p + off + 2, "H", y)


def _unit_uv(ram: Ram, p: int, clut: int) -> None:
    ram.put(p + 0xE, "H", clut)
    for off, uv in ((0xC, 0), (0x14, 1), (0x1C, 0x100), (0x24, 0x101)):
        ram.put(p + off, "H", uv)


def progress_setup(ram: Ram) -> None:
    """FUN_800B396C (after its CLUT upload): builds both buffers' progress bar at y 436-452:
    four 60-pixel level segments from x 64 (lit up to the current level, the current one
    additive), five separators, the marker line and the pointer triangle."""
    level = ram.s32(LEVEL)
    for b in range(2):
        x = 0x40
        for i in range(4):
            p = BAR_QUADS + 200 * b + 0x28 * i
            ram.put(p + 3, "B", 9)
            ram.put(p + 7, "B", 0x2C)
            for k in (4, 5, 6):
                ram.put(p + k, "B", 0 if level < i else 0x80)
            ram.put(p + 0x16, "H", 0x28 if i == level else 8)
            _unit_uv(ram, p, i & 0x3F | 0x7980)
            ram.put(p + 7, "B", ram.u8(p + 7) | 2)
            _xy4(ram, p, x, x + 0x3C)
            x += 0x3C
        p = BAR_QUADS + 200 * b + 0xA0
        ram.put(p + 3, "B", 9)
        ram.put(p + 7, "B", 0x2C)
        _unit_uv(ram, p, 0x7983)
        ram.put(p + 7, "B", ram.u8(p + 7) | 2)
        if level < 4:
            ram.put(p + 0x16, "H", 8)
            for k in (4, 5, 6):
                ram.put(p + k, "B", 0)
        else:
            ram.put(p + 0x16, "H", 0x28)
            for k in (4, 5, 6):
                ram.put(p + k, "B", 0x80)
            _xy4(ram, p, x, x + 0xC)
        for k in range(5):
            q = BAR_LINES + 100 * b + 0x14 * k
            ram.put(q + 3, "B", 4)
            ram.put(q + 7, "B", 0x50)
            ram.put(q + 8, "H", 0x3F + 0x3C * k)
            ram.put(q + 0x10, "H", 0x3F + 0x3C * k)
            ram.put(q + 0xA, "H", BAR_TOP)
            for c in (4, 5, 6):
                ram.put(q + c, "B", 0xFF)
                ram.put(q + c + 8, "B", 0x80)
            ram.put(q + 0x12, "H", BAR_BOTTOM)
        m = BAR_MARKER + 16 * b
        ram.put(m + 3, "B", 3)
        ram.put(m + 7, "B", 0x40)
        for c in (4, 5, 6):
            ram.put(m + c, "B", 0xFF)
        g = BAR_POINTER + 0x1C * b
        ram.put(g + 3, "B", 6)
        ram.put(g + 7, "B", 0x30)
        for off, v in ((4, 0), (5, 0x80), (6, 0xFF), (0xC, 0), (0xD, 0x80), (0xE, 0xFF), (0x14, 0xFF), (0x15, 0xFF),
                       (0x16, 0xFF)):
            ram.put(g + off, "B", v)
    ram.put(BAR_PHASE, "I", 0)
    ram.put(BAR_DONE, "I", 0)


def _pulse(ram: Ram) -> int:
    v = ram.s16(SIN_TABLE + 2 * (ram.u32(BAR_PHASE) & 0xFFF))
    return min(ds._asr(v + 0x1000 if v + 0x1000 >= 0 else v + 0x103F, 6) + 0x80, 0xFF)


def _link(ram: Ram, ot: int, p: int) -> None:
    ds.link(ram, ot, p, ram.u8(p + 3))


def progress_draw(ram: Ram) -> None:
    """FUN_800B3D34: the progress bar each frame. The marker follows the camera through the
    current level's segment (60 pixels per 0x8000 units from the level start); the current
    segment is split at the marker and pulses."""
    if ram.u32(0x800958B8) == 0:
        ram.put(BAR_PHASE, "I", ram.u32(BAR_PHASE) + 0x40 & M32)
    if ram.u32(ds.TEXT_OFF):
        return
    b = ram.u32(ds.DISPLAY_BUFFER)
    scene = ram.u32(ram.u32(0x800A911C) + 4)
    for k in range(5):
        _link(ram, scene + 0xC & M32, BAR_LINES + 100 * b + 0x14 * k & M32)
    level = ram.s32(LEVEL)
    start = level * 60
    x0 = start + 0x40
    if ram.u32(BAR_DONE) == 0:
        v = (ram.s32(CAMERA_X) - ram.s32(LEVEL_START_X)) * 60
        v = ds._s32(v)
        mark = x0 + ds._asr(v + 0x7FFF if v < 0 else v, 15)
        mark = min(mark, start + 0x7C)
        if ram.u32(LEVEL_ENDED):
            ram.put(BAR_DONE, "I", 1)
    else:
        mark = start + 0x7C
    if level == 4:
        mark = x0 + 0xC
    quads = BAR_QUADS + 200 * b & M32
    for i in range(4):
        p = quads + 0x28 * i
        if i == level:
            c = _pulse(ram)
            for k in (4, 5, 6):
                ram.put(p + k, "B", c)
            _xy4(ram, p, x0, mark)
            rest = quads + 0xA0
            _xy4(ram, rest, mark, x0 + 0x3C)
            _link(ram, scene + 0xC & M32, rest)
        _link(ram, scene + 0xC & M32, p)
    if level == 4:
        rest = quads + 0xA0
        c = _pulse(ram)
        for k in (4, 5, 6):
            ram.put(rest + k, "B", c)
        _link(ram, scene + 0xC & M32, rest)
    m = BAR_MARKER + 16 * b & M32
    for off, v in ((8, mark), (0xA, BAR_TOP), (0xC, mark), (0xE, BAR_BOTTOM)):
        ram.put(m + off, "H", v & 0xFFFF)
    _link(ram, scene + 8 & M32, m)
    s = ram.s16(SIN_TABLE + 2 * (ram.u32(BAR_PHASE) & 0xFFF)) * 12
    neg = s < 0
    half = ds._asr(s + (0xFFF if neg else 0), 12) + int(neg) >> 1       # (sin * 12 / 4096) / 2, truncated
    g = BAR_POINTER + 0x1C * b & M32
    for off, v in ((8, mark - half), (0xA, 0x1A8), (0x10, mark + half), (0x12, 0x1A8), (0x18, mark), (0x1A, BAR_TOP)):
        ram.put(g + off, "H", v & 0xFFFF)
    _link(ram, scene + 0xC & M32, g)


# ---- the stage background (FUN_800B4DF8) ----
BG_W, BG_H = 0x800B7078, 0x800B707C            # tile map size (member 2 of stg_p..s)
BG_TEX, BG_CLUT = 0x800B7080, 0x800B7084       # u16 per cell: texture word, CLUT
BG_DIV = 0x800B7088                            # camera x per pixel of scroll
BG_DEPTH = 0x800B708C                          # scene OT entry of the panorama
BG_SLOPE = 0x800B7090                          # angle: the map rises by 64 px · tan every 3 columns
BG_LEVEL = 0x800B7094                          # level 3 adds the gate sprites on the bottom row
BG_TILE_ONLY = 0x800B70F4                      # only the ground tile is drawn
BG_VIEW_X = 0x800B70F0
BG_TILE = 0x800B6FF8                           # per buffer: TILE under the map
BG_GATES = 0x800B7018                          # per buffer (0x30): 3 sprites
BG_PACKETS = 0x800AE220                        # per buffer: 21 SPRTs (0x348); at +0x690 21 draw modes (0x150)
BG_SCRATCH = 0x1F800300


def _cdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def background_draw(ram: Ram, gte) -> None:
    """FUN_800B4DF8: the level's panorama as 64 x 64 sprites (7 columns) scrolling with the
    camera x, climbing with the slope angle, above a tile that fills the ground below it."""
    import projection_sim as pj
    buf = ram.u32(ds.DISPLAY_BUFFER)
    v, out = BG_SCRATCH, BG_SCRATCH + 0x10
    for i in range(3):
        ram.put(v + 4 * i, "I", ram.u32(CAMERA + 0x14 + 4 * i))
    pj.apply_matrix_lv_gte(ram, gte, pj.VIEW, v, out)
    vx = ram.s32(out)
    width = ram.s32(BG_W)
    scroll = _cdiv(vx, ram.s32(BG_DIV))
    scroll = scroll - width * 64 * _cdiv(scroll, width * 64)
    ram.put(BG_VIEW_X, "I", vx & M32)
    if scroll < 0:
        scroll += width * 64
    zero, m = BG_SCRATCH + 0x20, BG_SCRATCH + 0x28
    for i in range(3):
        ram.put(zero + 2 * i, "H", 0)
    pj.rot_matrix_angles(ram, gte, zero, m)
    ram.put(m + 0x18, "I", 0)
    ram.put(m + 0x1C, "I", 0x9C4)
    ram.put(m + 0x14, "I", ram.u32(CAMERA + 0x14))
    pj.local_matrix(ram, gte, pj.VIEW, m)
    sxy = BG_SCRATCH + 0x50
    pj.rot_trans_pers_psyq(ram, gte, zero, sxy, sxy + 4, sxy + 8)
    top = pj._s32(ram.s16(sxy + 2) - (ram.u32(BG_H) << 6))
    column = _cdiv(scroll, 64)
    scene_ot = ram.u32(ram.u32(0x800A911C) + 4) + 4 * ram.u32(BG_DEPTH) & M32
    tile_only = ram.u32(BG_TILE_ONLY)
    if ram.u32(BG_LEVEL) == 3 or tile_only:
        tile = BG_TILE + 16 * buf & M32
        if tile_only:
            ram.put(tile + 0xC, "H", 0x170)
            ram.put(tile + 0xE, "H", ram.u16(sxy + 2) - 0x10 & 0xFFFF)
        ds.link(ram, scene_ot + 4 & M32, tile, ram.u8(tile + 3))
        if tile_only:
            return
    tex, clut = ram.u32(BG_TEX), ram.u32(BG_CLUT)
    base = ram.u32(BG_PACKETS)
    modes = base + 0x150 * buf + 0x690 & M32 if base else 0
    sprites = base + 0x348 * buf & M32 if base else 0
    angle = ram.u32(BG_SLOPE) & 0xFFF
    cos = ram.s16(pj.SIN_TABLE + 0x800 + 2 * angle)
    sin = ram.s16(pj.SIN_TABLE + 2 * angle)
    rise = pj._s32(_cdiv(0xC0000, cos) * sin)
    phase = pj._s32(0xB8000 - ((_cdiv(scroll, 192) * 192 - scroll) << 12))
    y = pj._s32((top << 12) + pj._s32(_cdiv(phase, cos) * sin))
    x0 = pj._s32(_cdiv(scroll, 64) * 64 - scroll << 12)
    gates = 0
    # Map size, OT entry and level are read again where the game reads them: more than three
    # gate tiles overrun BG_GATES into these globals (a map narrower than three columns).
    ot_entry = lambda: ram.u32(ram.u32(0x800A911C) + 4) + 4 * ram.u32(BG_DEPTH) & M32
    row = 0
    while row < ram.s32(BG_H):
        row_y = y
        x, c = x0, column
        for _ in range(7):
            if not (y < -0x40000 or 0x1E0 << 12 < y):
                w = ram.s32(BG_W)
                cell = 2 * (pj._s32(c - w * _cdiv(c, w)) + row * w)
                word = ram.u16(tex + cell & M32)
                ram.put(sprites + 0xE, "H", ram.u16(clut + cell & M32))
                ram.put(sprites + 0xC, "B", (word & 3) << 6)
                ram.put(sprites + 0xD, "B", word << 4 & 0xC0)
                ram.put(sprites + 8, "H", _cdiv(x, 0x1000) & 0xFFFF)
                ram.put(sprites + 0xA, "H", _cdiv(y, 0x1000) & 0xFFFF)
                ds.link(ram, ot_entry(), sprites, ram.u8(sprites + 3))
                sprites += 0x14
                ram.put(modes + 3, "B", 1)
                ram.put(modes + 4, "I", 0xE1000200 | word >> 8 & 0x1F)
                ds.link(ram, ot_entry(), modes, 1)
                modes += 8
            if ram.u32(BG_LEVEL) == 3 and row == ram.s32(BG_H) - 1:
                w = ram.s32(BG_W)
                if c - w * _cdiv(c, w) == 0:
                    g = BG_GATES + 0x30 * buf + 16 * gates & M32
                    ram.put(g + 8, "H", _cdiv(x, 0x1000) & 0xFFFF)
                    ram.put(g + 0xA, "H", _cdiv(y, 0x1000) + 0x40 & 0xFFFF)
                    gates += 1
                    ds.link(ram, ot_entry(), g, ram.u8(g + 3))
            c += 1
            x = pj._s32(x + 0x40000)
            if c == _cdiv(c, 3) * 3:
                y = pj._s32(y - rise)
        row += 1
        y = pj._s32(row_y + 0x40000)


BG_MAP = 0x800AE1D4              # stage archive member 2: u16 w, u16 h, u16 texture[w·h], u16 clut[w·h]
STAGE_ID = 0x800AE14C


def _set_sprite(ram: Ram, p: int, size: int) -> None:
    """The panorama sprite set-up: grey 0x80, size x size, SetShadeTex(p, 1) then SetSprt(p)
    (which rewrites the code byte, so the raw-texture bit does not survive; with colour 0x80
    it makes no difference)."""
    for k in range(3):
        ram.put(p + 4 + k, "B", 0x80)
    ram.put(p + 0x10, "H", size)
    ram.put(p + 0x12, "H", size)
    ram.put(p + 7, "B", ram.u8(p + 7) | 1)
    ram.put(p + 3, "B", 4)
    ram.put(p + 7, "B", 0x64)


def _set_tile(ram: Ram, p: int) -> None:
    """SetTile (0x8007C0B4)."""
    ram.put(p + 3, "B", 3)
    ram.put(p + 7, "B", 0x60)


def background_setup(ram: Ram) -> None:
    """FUN_800B4B44: reads the level's tile map, picks the slope (level 4: angle 0xD8) and the
    OT entry, and prepares the sprites, the ground tile and the three gate tiles."""
    level = ram.u16(STAGE_ID) - 15 & M32
    ram.put(BG_LEVEL, "I", level)
    m = ram.u32(BG_MAP)
    ram.put(BG_TEX, "I", m + 4 & M32)
    ram.put(BG_W, "I", ram.u16(m))
    ram.put(BG_H, "I", ram.u16(m + 2))
    ram.put(BG_DIV, "I", 0x14)
    ram.put(BG_CLUT, "I", m + 4 + 2 * (ram.u16(m) * ram.u16(m + 2) & M32) & M32)
    if level == 3:
        ram.put(BG_SLOPE, "I", 0xD8)
        ram.put(BG_DEPTH, "I", 0x3FE)
    else:
        ram.put(BG_SLOPE, "I", 0)
        ram.put(BG_DEPTH, "I", 0x3F0)
    if ram.u32(BG_TILE_ONLY):
        ram.put(BG_DEPTH, "I", 0x3F0)
    for buf in range(2):
        base = ram.u32(BG_PACKETS)
        p = base + 0x348 * buf & M32 if base else 0
        for _ in range(max(ram.s32(BG_H), 0) * 7):
            _set_sprite(ram, p, 0x40)
            p += 0x14
        if ram.u32(BG_LEVEL) == 3 or ram.u32(BG_TILE_ONLY):
            t = BG_TILE + 16 * buf
            if not ram.u32(BG_TILE_ONLY):
                ram.put(t + 0xC, "H", 0x110)
                ram.put(t + 0xE, "H", 0x64)
            ram.put(t + 8, "H", 0)
            ram.put(t + 0xA, "H", 0x14)
            for k in range(3):
                ram.put(t + 4 + k, "B", 0)
            _set_tile(ram, t)
            for g in range(3):
                gt = BG_GATES + 0x30 * buf + 16 * g
                for k in range(3):
                    ram.put(gt + 4 + k, "B", 0)
                ram.put(gt + 0xC, "H", 0x40)
                ram.put(gt + 0xE, "H", 0x20)
                _set_tile(ram, gt)
    ram.put(BG_VIEW_X, "I", 0)


# ---- who fights whom (FUN_800B5EC0, FUN_800B598C) ----
F0, F1, F2 = 0x800A96F0, 0x800AAF7C, 0x800AC808
TARGET_WAIT = 0x800B6A20         # frames before the automatic target may change again
CLOSE_A, CLOSE_B = 0x800B6A0C, 0x800B6A10   # the candidate's +0x1278 is 1..399
MANUAL, MANUAL_BUTTON, MANUAL_SIDE = 0x800B6A14, 0x800B6A18, 0x800B6A1C
QUADRANT_ORDER = 0x800B0F04      # s32[4]: 2, 0, 1, 0
PAD_HELD = 0x800AE230            # u16 per player
PAD_PRESSED = 0x800AE3D0
HUMAN_SIDE = 0x800A95F0
ANGLES = (0x2A, 0x2C, 0x2E, 0x30, 0x32, 0x34)   # targetDir, heading, headingDelta, relAngle, facingQuadrant, aimDir


def opponent_index(ram: Ram, f: int) -> int:
    """FighterOpponentIndex (0x80045E50)."""
    if ram.u8(f + 0xC4):
        return ram.u8(f + 0x21)
    if ram.u8(f + 0x87):
        return ram.u8(f + 0x22)
    if ram.u8(f + 0xD1):
        return ram.u8(f + 0x23)
    return ram.u8(f + 0x20)


def _pair_distance(ram: Ram, i: int, j: int) -> int:
    """FUN_80043C88."""
    i = 1 << (i - 1 & 0x1F) if i > 1 else i
    j = 1 << (j - 1 & 0x1F) if j > 1 else j
    return ram.s32(0x8009EA08 + 0x10 * (i + j) & M32)


def choose_target(ram: Ram, player: int, a: int, b: int) -> int:
    """FUN_800B598C: which of the two enemy records `a`, `b` the player faces. A hidden enemy
    (+0xC2) is skipped; while only one is close (+0x1278 in 1..399) it is taken; with both
    close the nearer one wins by 400 units, else the one more in front of the player (facing
    quadrant order 1, 3, 2, 0, then relative angle when the difference reaches a quarter to
    three quarters turn); a change waits 120 frames. With the manual mode the chosen button
    swaps the two. The angle fields are restored afterwards from a copy of the first six
    only, so the opponent-side fields +0x38..+0x42 get the player's own (game-bugs.md #47)."""
    import fight_sim
    wait = ram.s32(TARGET_WAIT)
    if wait > 0:
        ram.put(TARGET_WAIT, "I", wait - 1 & M32)
    if ram.s32(TARGET_WAIT) < 0:
        ram.put(TARGET_WAIT, "I", 0)
    pick = a
    if ram.u8(a + 0xC2):
        if ram.u8(b + 0xC2) == 0:
            pick = b
    elif ram.u8(b + 0xC2):
        pass
    elif ram.u32(CLOSE_A) == 0:
        if ram.u32(CLOSE_B):
            pick = b
    elif ram.u32(CLOSE_B) == 0 or ram.u32(TARGET_WAIT) != 0:
        pass
    else:
        s5 = ram.u8(a + 0x1E)
        da = _pair_distance(ram, ram.u8(player + 0x1E), s5)
        db = _pair_distance(ram, ram.u8(player + 0x1E), ram.u8(b + 0x1E))
        diff = fight_sim.fight_math.w32(da - db)
        if da < 0x9C4 or db < 0x9C4:
            if (-diff if diff < 0 else diff) >= 0x190:
                pick = b if diff > 0 else a
            else:
                saved = [ram.u16(player + o) for o in ANGLES]
                fp = fight_sim.Fighter(ram, player)
                fight_sim.relative_angles(fp, fight_sim.Fighter(ram, a))
                qa, ra = ram.s16(player + 0x32), ram.s16(player + 0x30)
                fight_sim.relative_angles(fp, fight_sim.Fighter(ram, b))
                qb, rb = ram.s16(player + 0x32), ram.s16(player + 0x30)
                if qa == qb:
                    thr = 0x1000 if qa == 0 else 0x2000 if qa == 2 else 0x3000
                    if (-(ra - rb) if ra < rb else ra - rb) >= thr:
                        pick = a if ra < rb else b
                else:
                    order = lambda q: ram.s32(QUADRANT_ORDER + 4 * q & M32)
                    pick = a if order(qb) < order(qa) else b
                for k, o in enumerate(ANGLES):
                    ram.put(player + o, "H", saved[k])
                    ram.put(player + o + 0xE, "H", saved[k])
        if ram.u32(MANUAL):
            side = ram.u32(MANUAL_SIDE)
            pad = PAD_PRESSED + (2 if ram.u16(HUMAN_SIDE) else 0)
            if ram.s16(pad) & ram.s32(MANUAL_BUTTON):
                side = side + 1 & 1
                ram.put(MANUAL_SIDE, "I", side)
            pick = b if ram.u32(MANUAL_SIDE) else a
        if ram.u8(pick + 0x1E) != s5:
            ram.put(TARGET_WAIT, "I", 0x78)
    if ram.u32(MANUAL):
        ram.put(MANUAL_SIDE, "I", int(pick != a))
    return pick


def fighter_roles(ram: Ram, out: int) -> None:
    """FUN_800B5EC0(out, out + 4, out + 8): the player, the enemy it faces and the other one.
    The player is fighter 0 unless 0x800A97B5 is set; in Tekken Force the enemies are the two
    other records. Also sets each fighter's opponent index (+0x20, +0x1F) and the player's
    "both enemies active" flag +0xC7."""
    player, a = (F0, F1) if ram.u8(0x800A97B5) == 0 else (F1, F0)
    b = F2
    if ram.s32(0x800AFF50) == 8:
        if ram.u8(player + 0x1E) == 0:
            if ram.u8(player + 0x20) == 1:
                a, b = F1, F2
            else:
                a, b = F2, F2 - 0x188C
        else:
            if ram.u8(player + 0x20) == 0:
                a, b = F0, F1
            else:
                a, b = F1, F1 - 0x188C
    ram.put(CLOSE_A, "I", int((ram.u16(a + 0x1278) - 1 & M32) < 399))
    ram.put(CLOSE_B, "I", int((ram.u16(b + 0x1278) - 1 & M32) < 399))
    ram.put(out, "I", player)
    target = choose_target(ram, player, a, b)
    other = b if a == target else a
    ram.put(out + 4, "I", target)
    ram.put(out + 8, "I", other)
    ram.put(player + 0xC7, "B", 0 if (ram.u8(a + 0xC2) == 0 or ram.u8(b + 0xC2) == 0) else 1)
    ram.put(player + 0xC8, "B", 0)
    ram.put(player + 0x20, "B", ram.u8(target + 0x1E))
    ram.put(target + 0x20, "B", ram.u8(player + 0x1E))
    ram.put(other + 0x20, "B", ram.u8(player + 0x1E))
    for f in (player, target, other):
        ram.put(f + 0x1F, "B", opponent_index(ram, f))


def manual_target_setup(ram: Ram, player: int) -> None:
    """FUN_800B5910 at the start of Tekken Force: holding all four face buttons turns on the
    manual target switch, on L1 if held, else L2, R1 or R2 (L2 when none is held)."""
    pad = ram.u16(PAD_HELD + 2 * player & M32)
    if pad & 0xF0 != 0xF0:
        return
    button = 4 if pad & 4 else 1 if pad & 1 else 8 if pad & 8 else 2 if pad & 2 else 1
    ram.put(MANUAL_BUTTON, "I", button)
    ram.put(MANUAL, "I", 1)


def manual_target_off(ram: Ram) -> None:
    """FUN_800B58FC."""
    ram.put(MANUAL_BUTTON, "I", 0)
    ram.put(MANUAL, "I", 0)


BOSS_TABLE = 0x800B685C          # per costume key: pointer to 4 × (u16 character, s16 costume or -1)


def boss_for(mem, key: int, level: int) -> tuple[int, int]:
    """The boss of a level for the player's costume key (FUN_800B2B3C): the table's character,
    and its costume, or for -1 the player's other costume when the boss is the player's own
    character (else costume 0). `mem` is a `Ram` or anything with read(address, size)."""
    import struct
    read = mem.read if hasattr(mem, "read") else (lambda a, n: bytes(mem.data[mem._off(a):mem._off(a) + n]))
    entry = struct.unpack("<I", bytes(read(BOSS_TABLE + 4 * key, 4)))[0] + 4 * (level & 3)
    char, costume = struct.unpack("<Hh", bytes(read(entry, 4)))
    if costume == -1:
        costume = int((key & 3) == 0) if key >> 2 == char else int((key & 3) != 0)
    return char, costume
