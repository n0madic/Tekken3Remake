#!/usr/bin/env python3
"""Integer ports of the screen and flow logic around the fight (Japan Rev.1).

Each port works on a copy of guest RAM (`fight_sim.Ram`) with the game's addresses, so
`tools/research/verify_screens_sim.py` can run the original routine in the CPU harness on the
same memory and compare all of RAM afterwards. The screens' drawing is ported in draw_sim.py;
the verifier stubs the drawing primitives, sound, music and VRAM uploads in the game (see
`STUBS` there), and the ports skip them. The continue countdown draws its text and is
verified with the text engine running (verify_screens_sim.case_continue).

Covered (docs/research/code/modes.md):
- resident: the continue countdown, FightMain's continue / game over / new challenger
  sub-states (9-14), the fight's pause update and pause menu, the Ogre-scene check, a challenger joining, the
  transition request, the unlock schedule, the play-count unlocks, the Gon unlock,
  the helper routines they use;
- `arcade.ovl`: recording an arcade clear;
- `volley.ovl`: the single-player Tekken Ball opponent choice;
- `ranking.ovl`: name entry, the three record tables and the per-frame state machine;
- `result.ovl`: the four result screens;
- `ending.ovl`: the staff roll.
"""

from __future__ import annotations

import command_list_sim as cl
import draw_sim as ds
from fight_sim import Ram

# ---- resident globals ----
PAD_HELD = 0x800AE230            # u16[2]
PAD_PRESSED = 0x800AE3D0         # u16[2]
PAD_REPEAT = 0x800AE3C8          # u16[2]
PLAYER_ACTIVE = 0x800AE6C0       # u16[2]
KEEP_CHAR = 0x800AE484           # u16[2]
GAME_STATE = 0x800AE6CC          # u16
SUB_STATE = 0x800AE6EC           # u16
STATE_TIMER = 0x800AE6DC         # s32
FRAME_COUNT = 0x800AE6E0         # u32
MODE = 0x800AFF50                # mode context
UNLOCKED = 0x800982D0
START_COSTUMES = 0x800982D4
CLEARED = 0x800982D8
CLEARED2 = 0x800982DC
NEW_CHAR = 0x800982F2
FIGHTS_SINCE_UNLOCK = 0x800982FC  # u16
PLAY_STEPS = 0x800982FA
PLAY_STEPS_SEEN = 0x800982FB
UNLOCK_CLASS = 0x800982FF
BALL_FIRST_DONE = 0x800982FE
BALL_NEW = 0x80098306
THEATER_NEW = 0x80098307
SCHEDULE = 0x800985F4
STATS = 0x8009842C               # 22 x (plays, wins, losses, draws) u16
SAVE_PENDING = 0x800AE428
CHAR_RECORDS = 0x80098120
LCG2 = 0x8009F650                # FUN_8004D13C: x = 5x + 1
START_COSTUME_MASK = 0x50382
FIGHTER = (0x800A96F0, 0x800AAF7C)
ROUNDS_TO_WIN = 0x800AE2C4
ROUND_WINS = 0x44


# ---- small resident helpers ----
def wrap(lo: int, v: int, hi: int) -> int:
    """FUN_8004CF68: below lo gives hi, above hi gives lo."""
    if v < lo:
        return hi
    return lo if hi < v else v


def popcount(v: int) -> int:
    """FUN_8004CF94."""
    return bin(v & 0xFFFFFFFF).count("1")


def strcpy(ram: Ram, dst: int, src: int) -> int:
    """FUN_8004CEF0; returns the address of the terminating zero."""
    while True:
        c = ram.u8(src)
        src += 1
        if c == 0:
            break
        ram.put(dst, "B", c)
        dst += 1
    ram.put(dst, "B", 0)
    return dst


def strcmp(ram: Ram, a: int, b: int) -> int:
    """FUN_8004CF18: 0 when equal, -1 on an early mismatch, 1 when a is longer."""
    while ram.u8(b):
        if ram.u8(a) != ram.u8(b):
            return -1
        a += 1
        b += 1
    return int(ram.u8(a) != ram.u8(b))


def sort_pairs(pairs: list[list[int]], ascending: int) -> None:
    """FUN_8004D068: stable insertion sort of (id, key) pairs by the unsigned key."""
    n = len(pairs)
    for i in range(n - 1):
        j = i
        while j >= 0:
            a, b = pairs[j][1], pairs[j + 1][1]
            if not (b < a if ascending else a < b):
                break
            pairs[j], pairs[j + 1] = pairs[j + 1], pairs[j]
            j -= 1


def permille(part: int, total: int) -> int:
    """FUN_8004D008: part * 1000 / total, scaled to avoid overflow."""
    if part > total:                          # not reached: a share never exceeds the total
        return 1000
    while total > 0x3FFFFF:
        total >>= 1
        part >>= 1
    return 0 if total == 0 else part * 1000 // total


def usage(ram: Ram, char: int) -> int:
    """FUN_80051948: plays + losses + draws of a character."""
    base = STATS + (char % 22) * 8
    return ram.u16(base) + ram.u16(base + 4) + ram.u16(base + 6)


def char_name(ram: Ram, key: int) -> int:
    """FUN_8004F2D8(char, 0) / FUN_8004F2B0(key): the name pointer of a costume key."""
    if key > 0x5C:
        key = 0x58
    return ram.u32(ram.u32(CHAR_RECORDS + 4 * key))


def lcg2(ram: Ram) -> int:
    """FUN_8004D13C."""
    x = (ram.u32(LCG2) * 5 + 1) & 0xFFFFFFFF
    ram.put(LCG2, "I", x)
    return x


def display_request(ram: Ram, on: int) -> None:
    """FUN_80029860."""
    ram.put(0x80095850, "I", int(on == 0))


def draw_hold(ram: Ram, on: int) -> None:
    """FUN_8002988C."""
    v = ram.u32(0x8009584C)
    if on:
        ram.put(0x8009584C, "I", v + 1)
    elif v:
        ram.put(0x8009584C, "I", v - 1)


# ---- unlocks ----
def unlock_char(ram: Ram, char: int) -> None:
    """FUN_80056498."""
    bit = 1 << char
    if not ram.u32(UNLOCKED) & bit:
        ram.put(NEW_CHAR, "B", char)
        ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
    ram.put(UNLOCKED, "I", ram.u32(UNLOCKED) | bit)


def unlock_class(ram: Ram) -> None:
    if ram.u32(UNLOCKED) & 0x80000:
        ram.put(UNLOCK_CLASS, "B", 2)
    else:
        ram.put(UNLOCK_CLASS, "B", int(popcount(ram.u32(UNLOCKED)) >= 15))


def start_costume(ram: Ram, bit: int) -> None:
    if not ram.u32(START_COSTUMES) & bit:
        ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
    ram.put(START_COSTUMES, "I", (ram.u32(START_COSTUMES) | bit) & START_COSTUME_MASK)


def arcade_unlocks(ram: Ram, n: int) -> None:
    """ArcadeUnlocks (FUN_800564C8): apply the first n schedule steps."""
    if n & 0xFFFFFFFF > 14:           # unsigned test: a negative count also means 14
        n = 14
    for step in range(max(n, 0)):
        kind, value = ram.u8(SCHEDULE + 2 * step), ram.u8(SCHEDULE + 2 * step + 1)
        if kind == 0:
            ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
        elif kind == 1:
            unlock_char(ram, value & 31)
        elif kind == 2:
            start_costume(ram, 1 << (value & 31))
        elif kind == 3:
            if ram.u32(CLEARED) & 0x3FF == 0x3FF and ram.u8(THEATER_NEW) == 0:
                ram.put(THEATER_NEW, "B", 1)
                ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
        elif kind == 4:
            if ram.u8(BALL_NEW) == 0:
                ram.put(BALL_NEW, "B", 1)
                ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
        elif kind == 5:
            for c in range(22):
                if 0x1FFFFF >> c & 1:
                    unlock_char(ram, c)
                if START_COSTUME_MASK >> c & 1:
                    start_costume(ram, 1 << c)
            for flag in (BALL_NEW, THEATER_NEW):
                if ram.u8(flag) == 0:
                    ram.put(flag, "B", 1)
                    ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
            unlock_class(ram)
    if ram.u32(CLEARED) & 0x3FF == 0x3FF and ram.u8(THEATER_NEW) == 0:
        ram.put(THEATER_NEW, "B", 1)
        ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
    unlock_class(ram)


def play_unlocks(ram: Ram) -> None:
    """FUN_800567A0: Start costumes by usage, then one more schedule step per 100 (50) fights."""
    for char, need, bit in ((9, 50, 0x200), (7, 50, 0x80), (18, 25, 0x40000), (16, 10, 0x10000)):
        if usage(ram, char) >= need:
            start_costume(ram, bit)
    unlock_class(ram)
    need = 50 if ram.u8(PLAY_STEPS_SEEN) else 100
    if ram.u16(FIGHTS_SINCE_UNLOCK) >= need:
        ram.put(PLAY_STEPS_SEEN, "B", 1)
        steps = min(ram.u8(PLAY_STEPS) + 1, 14)
        ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)
        ram.put(PLAY_STEPS, "B", steps)
        arcade_unlocks(ram, steps)


def save_pending(ram: Ram) -> None:
    """FUN_8004C678."""
    play_unlocks(ram)
    ram.put(SAVE_PENDING, "B", 1)


def gon_check(ram: Ram, char: int) -> None:
    """FUN_8005696C: beating Gon in arcade or Tekken Ball unlocks him."""
    if char == 0x11 and not ram.u32(UNLOCKED) & 0x20000 and ram.u32(MODE) in (0, 7):
        ram.put(UNLOCKED, "I", ram.u32(UNLOCKED) | 0x20000)
        ram.put(NEW_CHAR, "B", 0x11)
        ram.put(FIGHTS_SINCE_UNLOCK, "H", 0)


def record_clear(ram: Ram, char: int, costume: int) -> None:
    """FUN_800B2350 (arcade.ovl): mark an arcade clear and apply the clear-based steps."""
    if ram.u32(MODE) != 0:
        return
    ram.put(NEW_CHAR, "B", 0x16)
    d8, dc = ram.u32(CLEARED), ram.u32(CLEARED2)
    if char == 11:
        if costume == 1:
            dc |= 0x800
        else:
            d8 |= 0x800
    elif char == 8:
        if costume < 2:
            d8 |= 0x100
        else:
            dc |= 0x100
    elif char == 16:
        if not d8 & 0x10000:
            d8 |= 0x10000
        else:
            dc |= 0x10000
    else:
        d8 |= 1 << (char & 31)
    ram.put(CLEARED, "I", d8 & 0x1FFFFF)
    ram.put(CLEARED2, "I", dc & 0x1FFFFF)
    k = popcount((d8 | dc) & 0x1FFFFF)
    arcade_unlocks(ram, sum(1 for i in range(k) if (1 << i) & 0x83FF))


# ---- match flow ----
class FlowHooks:
    """The calls of the flow routines that are not ported here: sound (SoundPlayFighter(0, id, 0)),
    FUN_80040E98 (SoundPlaySystem(id & 0xFFF)), the music fade FUN_8006BF80 and MusicPlay (first argument),
    the overlay load FUN_80052D1C, and FightFrame (0x8002B0AC, the fight itself; returns its
    round status). The defaults do nothing; the verifier logs them."""

    def sound(self, ram: Ram, sound_id: int) -> None:
        pass

    def system_sound(self, ram: Ram, sound_id: int) -> None:
        pass

    def music_fade(self, ram: Ram, a: int) -> None:
        pass

    def music_play(self, ram: Ram, track: int) -> None:
        pass

    def load_overlay(self, ram: Ram, k: int) -> None:
        pass

    def fight_frame(self, ram: Ram) -> int:
        raise NotImplementedError("FightFrame is the fight (fight_sim.py)")

    def sound_reset(self, ram: Ram, a: int) -> None:
        """FUN_8004B920."""

    def command_list_screen(self, ram: Ram, player: int) -> None:
        """FUN_80079298: the pause menu's COMMAND page (the move list; default: its port)."""
        cl.pause_command_page(ram, player)

    def how_to(self, ram: Ram, player: int) -> None:
        """volley.ovl FUN_800B4088: the pause menu's HOW TO page in Tekken Ball (default: its port)."""
        how_to_page(ram, player)


HOOKS = FlowHooks()
STR_CONTINUE = 0x800226CC        # "%c%f%H%VCONTINUE? %d"


def continue_countdown(ram: Ram, player: int) -> int:
    """FUN_800502D8: 1 continue with the same fight, 2 continue via select, 0 counting, -1 over.
    While counting it prints CONTINUE? n (n = (timer + 90) / 90) and plays system sound 4 + n
    for each digit from 8 down to 1 on the frame it appears."""
    pressed = ram.u16(PAD_PRESSED + 2 * player)
    if pressed & 0x800:
        ram.put(PLAYER_ACTIVE + 2 * player, "H", 1)
        HOOKS.sound(ram, 0x4CC0)                   # FUN_8004B88C
        if ram.u8(MODE + 0xD) == 0:
            ram.put(KEEP_CHAR + 2 * player, "H", 1)
            return 1
        ram.put(KEEP_CHAR + 2 * player, "H", 0)
        return 2
    t = ram.s32(STATE_TIMER)
    if pressed & 0xF0:
        t = 0 if t < 90 else t - 90
        ram.put(STATE_TIMER, "i", t)
    if t == 0:
        return -1
    if t > 0:
        ram.put(STATE_TIMER, "i", t - 1)
    t = ram.s32(STATE_TIMER) + 90
    n = ds._sdiv(t, 90)
    if 0 <= n < 9 and t - 90 * n == 89:
        HOOKS.system_sound(ram, 0x1004 + n if n else 0x1017)
    ds.text(ram, STR_CONTINUE, 9, 2, 0x3F, 200, n)
    return 0


STR_GAME_OVER = 0x800226FC       # "%c%f%H%VGAME OVER"
STR_CHALLENGER = 0x80022710      # "%c%f%H%VA NEW CHALLENGER\n     ENTERS!!"
FIGHT_PACKETS = 0x800AE520       # + buffer * 28: FightMain's packet pointer
FREEZE = 0x8009588C              # FightFrame only draws


def set_continuing(ram: Ram, player: int) -> None:
    """FUN_80051474: the continuing player and the other side (CPU)."""
    ram.put(0x800AE406, "B", player)
    ram.put(0x800B0A06, "B", player + 1 & 1)
    ram.put(0x800AE218, "H", 0)


def goto_ranking(ram: Ram) -> None:
    """FUN_80050478."""
    display_request(ram, 1)
    ram.put(GAME_STATE, "H", 16)
    ram.put(SUB_STATE, "H", 0)


def fight_main(ram: Ram) -> int | None:
    """FightMain (0x80050710) for sub-states 9-14: the continue, game over and new-challenger
    screens. Returns 1 when Select + Start leaves the mode. The other sub-states (set-up and the
    fight) are not ported."""
    if menu_exit(ram):
        return 1
    saved = ram.u32(ds.PACKET_PTR)
    ram.put(ds.PACKET_PTR, "I", ram.u32(FIGHT_PACKETS + 28 * ram.u32(ds.DISPLAY_BUFFER) & 0xFFFFFFFF))
    sub = ram.s16(SUB_STATE)
    if sub == 9:
        HOOKS.system_sound(ram, 0x16)
        HOOKS.music_fade(ram, 0x3C)
        ram.put(STATE_TIMER, "i", 808)              # FUN_800502C8
        ram.put(MODE + 0x12, "B", 1)
        ram.put(SUB_STATE, "H", 10)
        sub = 10
    if sub == 10:
        HOOKS.fight_frame(ram)
        r = continue_countdown(ram, ram.u8(MODE + 0x23))
        if r in (1, 2):
            ram.put(SUB_STATE, "H", 2 if r == 1 else 0)
            ram.put(MODE + 0x12, "B", 0)
            set_continuing(ram, ram.u8(MODE + 0x22))
        elif r != 0:
            ram.put(SUB_STATE, "H", 11)
            ram.put(MODE + 0x12, "B", 0)
    elif sub in (11, 12):
        if sub == 11:
            ram.put(STATE_TIMER, "i", 0)
            ram.put(PLAYER_ACTIVE + 2 * ram.u8(MODE + 0x23), "H", 0)
            HOOKS.system_sound(ram, 0x1017)
            HOOKS.music_play(ram, 3)
            ram.put(SUB_STATE, "H", 12)
        ds.text(ram, STR_GAME_OVER, 1, 2, 0x55, 200)
        HOOKS.fight_frame(ram)
        t = ram.s32(STATE_TIMER) + 1
        ram.put(STATE_TIMER, "i", t)
        if t >= 0x79:
            goto_ranking(ram)
    elif sub in (13, 14):
        done = False
        if sub == 13:
            HOOKS.sound(ram, 0x49A1)
            HOOKS.music_fade(ram, 0)
            ram.put(STATE_TIMER, "i", 8)
            ram.put(MODE + 0x13, "B", 1)
            done = ram.u32(MODE + 0xC) & 0xFFFF00FF != 0   # FUN_80051204: a side already chose
            if not done:
                ram.put(SUB_STATE, "H", 14)
        if not done:
            if HOOKS.fight_frame(ram) > 0 or ram.s32(STATE_TIMER) >= 0x18:
                ram.put(FREEZE, "I", 1)
            t = ram.s32(STATE_TIMER)
            if t & 0x18:
                ds.text(ram, STR_CHALLENGER, 7, 2, 8, 0x120)
            if t == 0x28:
                HOOKS.load_overlay(ram, 4)
            ram.put(STATE_TIMER, "i", t + 1)
            done = t + 1 >= 0x4A
        if done:
            display_request(ram, 1)
            if ram.u8(MODE + 6):
                ram.put(KEEP_CHAR + 2, "H", 0)
                ram.put(KEEP_CHAR, "H", 0)
            ram.put(SUB_STATE, "H", 0)
    else:
        raise NotImplementedError(f"FightMain sub-state {sub}")
    ram.put(ds.PACKET_PTR, "I", saved)
    return None


# ---- the pause menu of the fight ----
PAUSED, PAUSED_PREV, PAUSE_PLAYER = 0x800958B0, 0x800958B4, 0x800958B8   # 0 or the pausing player (1, 2)
PAUSE_CURSOR = 0x80098DDC        # u8; 0xFF when the menu (re)opens
PAUSE_CHOICE = 0x80098DDD        # u8: 1 CANCEL, 2 COMMAND, 3 RESET (menu_exit), 4 HOW TO; = MENU_EXIT_FLAG
PAUSE_DELAY = 0x800A8B3A         # u8: frames the menu stays inert after a choice
PAUSE_ITEMS = 0x80098DE0         # CANCEL, COMMAND, RESET, HOW TO
STR_PAUSE = 0x80027E4C           # "%p%c%f%H%V%dP PAUSE"
STR_ITEM_PREFIX = 0x80027E48     # "%p"
PAUSE_TEXT = 0x1F800200          # the item string is built here (the game uses its stack)
SCREEN_RECT = 0x800AE6F8         # s16 x, y, w, h of the display
PRACTICE_RESUME = 0x800958AC


def pause_update(ram: Ram) -> None:
    """FUN_8002B9EC: Start from an active player pauses a fight in progress (round state 1) when
    the mode allows it (0x800AFF54). Only CANCEL (or practice's resume request) unpauses. The
    music drops to volume 0x1E while paused."""
    p0, p1 = False, False
    if ram.u32(MODE) == 5:
        if ram.u32(0x800958C8) == 0:                # no replay playing
            who = ram.u8(0x800AE406)
            if ram.u32(0x800958E0):
                p0, p1 = who == 0, who == 1
            else:
                p0 = who == 0 and bool(ram.u16(PAD_PRESSED) & 0x800)
                p1 = who == 1 and bool(ram.u16(PAD_PRESSED + 2) & 0x800)
    else:
        p0 = bool(ram.u16(PLAYER_ACTIVE)) and bool(ram.u16(PAD_PRESSED) & 0x800)
        p1 = bool(ram.u16(PLAYER_ACTIVE + 2)) and bool(ram.u16(PAD_PRESSED + 2) & 0x800)
    if ram.u8(MODE + 4) == 0 or ram.u32(0x80097350) != 1:
        ram.put(PAUSED, "I", 0)
    elif ram.u32(PAUSED) == 0:
        if p0:
            ram.put(PAUSED, "I", 1)
        if p1:
            ram.put(PAUSED, "I", 2)
    if ram.u8(PAUSE_CHOICE) == 1:
        ram.put(PAUSED, "I", 0)
        ram.put(PAUSE_CHOICE, "B", 0)
    if ram.u32(PRACTICE_RESUME):
        ram.put(PAUSED, "I", 0)
        ram.put(PRACTICE_RESUME, "I", 0)
    paused = ram.u32(PAUSED)
    if paused != ram.u32(PAUSED_PREV):
        if paused:
            ram.put(PAUSE_CURSOR, "B", 0xFF)
            HOOKS.music_fade(ram, 0x1E)
        else:
            ram.put(PAUSE_CHOICE, "B", 0)
            HOOKS.music_fade(ram, 0x7F)
    ram.put(PAUSED_PREV, "I", paused)
    ram.put(PAUSE_PLAYER, "I", paused if ram.u32(0x80095884) else 0)


def pause_menu(ram: Ram, player: int) -> None:
    """FUN_80078498: the pause menu, or the COMMAND / HOW TO page it opened."""
    if ram.u32(ds.TEXT_OFF):
        return
    if ram.u8(PAUSE_CURSOR) == 0xFF:
        ram.put(PAUSE_CHOICE, "B", 0)
        ram.put(PAUSE_CURSOR, "B", 0)
        ram.put(PAUSE_DELAY, "B", 2)
        HOOKS.sound_reset(ram, 0)
        HOOKS.sound(ram, 0x50F4)
    choice = ram.u8(PAUSE_CHOICE)
    if choice == 2:
        HOOKS.command_list_screen(ram, player)
    elif choice == 4:
        HOOKS.how_to(ram, player)
    else:
        pause_menu_draw(ram, player)


def _rect(ram: Ram) -> tuple[int, int, int, int]:
    return tuple(ram.u16(SCREEN_RECT + 2 * i) for i in range(4))


def pause_menu_draw(ram: Ram, player: int) -> None:
    """FUN_8007854C: CANCEL / COMMAND / RESET (/ HOW TO in Tekken Ball) centred on x 184 from
    y 104, 20 pixels apart (colour 2 on the cursor, else 6), in a dark box with a light border,
    and a blinking `nP PAUSE`. The draw areas clip the fight scene around the box."""
    if ram.u32(ds.TEXT_OFF):
        return
    delay = ram.u8(PAUSE_DELAY)
    if delay:
        ram.put(PAUSE_DELAY, "B", delay - 1)
        return
    x, y, w, h = _rect(ram)
    ot = ds.ot0(ram)
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ot, ds._pkt(ram), x, y, w, h - 0x20 & 0xFFFF))
    box_h, n = (0x55, 4) if ram.u32(MODE) == 7 else (0x41, 3)
    pad = ram.u16(PAD_PRESSED + (0 if player == 1 else 2))
    if pad & 0x1000:
        cur = ram.u8(PAUSE_CURSOR)
        ram.put(PAUSE_CURSOR, "B", cur - 1 if cur else n - 1)
        HOOKS.sound(ram, 0x546C)
    if pad & 0x4000:
        ram.put(PAUSE_CURSOR, "B", (ram.u8(PAUSE_CURSOR) + 1) % n)
        HOOKS.sound(ram, 0x546C)
    if pad & 0x8F0:
        ram.put(PAUSE_DELAY, "B", 2)
        ram.put(PAUSE_CHOICE, "B", ram.u8(PAUSE_CURSOR) + 1)
        HOOKS.sound(ram, 0x50F4)
    for i in range(n):
        item = ram.u32(PAUSE_ITEMS + 4 * i)
        ix = 0xB8 - ((9 * ds.strlen(ram, item) & 0xFFFFFFFF) >> 1)
        end = ds.strcpy(ram, PAUSE_TEXT, ds.FMT_PREFIX)
        end = ds.strcpy(ram, end, STR_ITEM_PREFIX)
        ds.strcpy(ram, end, item)
        ds.text(ram, PAUSE_TEXT, 2 if i == ram.u8(PAUSE_CURSOR) else 6, 0, ix, 0x68 + 0x14 * i, 0)
    p = ds.tile(ram, ot, ds._pkt(ram), 0x60301000, 0x640094, box_h << 16 | 0x48)
    ds._set_pkt(ram, ds.tile(ram, ot, p, 0x60E0E0E0, 0x620093, (box_h + 4) << 16 | 0x4A))
    if ram.u32(ds.FRAME_COUNT) & 0x20:
        px = 0x20 if player == 1 else ram.s16(SCREEN_RECT) + ram.s16(SCREEN_RECT + 4) - 0x88
        ds.text(ram, STR_PAUSE, 7, 5, 1, px, 0x78, player)
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ot, ds._pkt(ram), x, 0x62, w, box_h + 4))
    scene = ram.u32(0x800A911C)
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ram.u32(scene + 4) + 8 & 0xFFFFFFFF, ds._pkt(ram), x, y, 0, 0))
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ram.u32(scene + 0x10), ds._pkt(ram), x, y, w, 0xA2))


def how_to_page(ram: Ram, player: int) -> None:
    """volley.ovl FUN_800B4088: Tekken Ball's HOW TO picture (216 x 204 at (76, 128)) on a white
    frame with a black shadow; a face button or Start returns to the pause menu."""
    if ram.u32(ds.TEXT_OFF):
        return
    delay = ram.u8(PAUSE_DELAY)
    if delay:
        ram.put(PAUSE_DELAY, "B", delay - 1)
        return
    if ram.u16(PAD_PRESSED + (0 if player == 1 else 2)) & 0x8F0:
        ram.put(PAUSE_CURSOR, "B", 0)
        ram.put(PAUSE_CHOICE, "B", 0)
        ram.put(PAUSE_DELAY, "B", 3)
        HOOKS.sound(ram, 0x50F4)
    x, y, w, h = _rect(ram)
    scene = ram.u32(0x800A911C)
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ram.u32(scene + 4) + 8 & 0xFFFFFFFF, ds._pkt(ram), x, y, 0, 0))
    ot = ds.ot_text(ram)
    p = ds.sprt(ram, ot, ds._pkt(ram), 0x65000000, 0x80004C, 0xCC00D8, 0x7C040000)
    p = ds.tile(ram, ot, p, 0x60F0F0F0, 0x700040, 0xEC00F0)
    p = ds.tile(ram, ot, p, 0x60000000, 0x780046, 0xEC00F0)
    p = ds.dr_mode(ram, ot, p, 0x1A)
    p = ds.draw_area_xywh(ram, ot, p, 0x40, 0x70, 0xF6, 0x108)
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ram.u32(scene + 0x10), p, x, y, w, 0x40))


def ogre_scene_check(ram: Ram) -> int:
    """FUN_800514EC: request the Ogre -> True Ogre scene (round state 10)."""
    if ram.u32(MODE) not in (0, 3) or ram.u32(MODE + 0x24) != 9 or ram.u8(MODE + 0x1C) != 1:
        return 0
    if ram.u32(MODE + 0xBC) or ram.u16(0x800AE6DA):
        return 0
    human, cpu = FIGHTER[0] + 0x188C * ram.u8(MODE + 0x1E), FIGHTER[0] + 0x188C * ram.u8(MODE + 0x1F)
    if ram.s16(cpu + ROUND_WINS) < ram.u16(ROUNDS_TO_WIN) and ram.s16(human + ROUND_WINS) > 0:
        ram.put(MODE + 0xBC, "I", 1)
        return 1
    return 0


def challenger_join(ram: Ram, player: int) -> int:
    """FUN_80051244: a player who is not playing presses Start."""
    if not ram.u16(PAD_PRESSED + 2 * player) & 0x800 or ram.u16(0x800AE6DA):
        return 0
    if ram.u16(PLAYER_ACTIVE + 2 * player):
        return 0
    if ram.u16(PAD_HELD + 2 * player) & 0x800:
        ram.put(MODE + 0xF, "B", int(ram.u16(PAD_HELD + 2 * player) == 0x80C))
    ram.put(PLAYER_ACTIVE + 2 * player, "H", 1)
    ram.put(KEEP_CHAR + 2 * player, "H", 0)
    ram.put(0x800B0A06, "B", player)
    return 1


def goto_transition(ram: Ram, target: int) -> None:
    """FUN_8004FBE0: go to a state through the transition screen (state 2)."""
    display_request(ram, 1)
    ram.put(0x8009831A, "B", 0)
    if target == 3:
        demo = ram.u8(0x80098300)
        held = ram.u16(PAD_HELD)
        if held & 0xFFF3:
            held = 0
        top = ram.u8(UNLOCK_CLASS)
        if top == 0 or held == 0:
            if ram.u8(0x8009831E) == 1:
                demo += 1
        else:
            choice = {8: 0, 4: 1, 12: 2}.get(held, demo)
            if top < choice:
                choice = ram.u8(0x80098300)
            else:
                ram.put(0x8009831E, "B", 1)
            demo = choice
        if top < demo:
            demo = 0
        ram.put(0x80098300, "B", demo)
        ram.put(0x8009831A, "B", 1)
        if ram.u8(0x8009831E) == 1:
            target = 6
        else:
            ram.put(0x8009831A, "B", 0)
    ram.put(0x80098318, "B", target)
    ram.put(0x80098319, "B", ram.u16(GAME_STATE))
    ram.put(GAME_STATE, "H", 2)
    ram.put(SUB_STATE, "H", 0)


# ---- Tekken Ball ----
def ball_opponent(ram: Ram, ctx: int, s2: int) -> None:
    """FUN_800B528C (volley.ovl). s2 is the caller's $s2 (0x800AE508 in the game)."""
    mask = ram.u32(UNLOCKED) & 0x53FFF
    pairs = [[c, ram.u16(ctx + 0x44 + 2 * c)] for c in range(22) if mask >> c & 1]
    sort_pairs(pairs, 0)
    count = 0
    while count < len(pairs) and not pairs[0][1] + 4 < pairs[count][1]:
        count += 1
    if ram.u8(BALL_FIRST_DONE) == 0:
        ram.put(BALL_FIRST_DONE, "B", 1)
        key = 0x44
    else:
        s2 = pairs[lcg2(ram) % count][0]
        key = s2 * 4 + (ram.u32(0x800AE6E0) & 1)
    ram.put(ctx + 0x70, "I", key)
    slot = (ctx + 0x44 + 2 * s2) & 0xFFFFFFFF
    ram.put(slot, "H", ram.u16(slot) + 1)


# ---- ranking.ovl ----
NAME = 0x800D36F8                # name-entry record: char[4], u16 pos, u8 pressed, u8 moved, u16 cursor, u16 char, u16 player
ALPHABET = 0x800B9674            # 40 symbols
BLANK_NAME = 0x800B96AC          # "   "
GON_NAME = 0x800B96B0            # "GON"
REJECTED = 0x800CBE44            # 5 name pointers
RECORDS = 0x8009832C             # time attack records: 22 x (u32 frames, char name[4])
SURVIVORS = 0x800983DC           # 10 x (u16 char, u16 wins, char name[4])
TIME_RECORD_PTR = 0x80098324
SURVIVOR_PTR = 0x80098328
PAGE = 0x800984DC
NAME_PENDING = 0x800984DE
NAME_PLAYER = 0x800984DF
NAME_CHAR = 0x800984E0
TABLE = 0x800CBE68               # page table (see ranking_frame)
BACKDROP_STAGE = 0x800984DD
TIME_CAP = 359_999
COS_TABLE = 0x8001F0C4
SIN_TABLE = 0x8001E8C4


def name_init(ram: Ram, p: int, player: int, char: int) -> None:
    """FUN_800C3438."""
    ram.put(p + 0xC, "H", player)
    ram.put(p + 0xA, "H", char)
    strcpy(ram, p, BLANK_NAME)
    ram.put(p + 4, "H", 0)
    ram.put(p + 8, "H", 0)
    ram.put(p + 6, "B", 0)
    ram.put(p + 7, "B", 0)


def _default_name(ram: Ram, p: int) -> None:
    src = char_name(ram, ram.u16(p + 0xA) * 4)
    for i in range(3):
        ram.put(p + i, "B", ram.u8(src + i))
    ram.put(p + 3, "B", 0)


def _finish_name(ram: Ram, p: int) -> None:
    for i in range(ram.u16(p + 4), 3):
        ram.put(p + i, "B", 0x20)
    ram.put(p + 3, "B", 0)
    ram.put(p + 4, "H", 3)
    if any(strcmp(ram, ram.u32(REJECTED + 4 * k), p) == 0 for k in range(5)):
        _default_name(ram, p)


def name_entry(ram: Ram, p: int, mode: int) -> int:
    """FUN_800C3480: mode 0 = one frame of input, 1 = time out, 2 = take the character's name."""
    ram.put(p + 6, "B", 0)
    ram.put(p + 7, "B", 0)
    if mode == 1:
        _finish_name(ram, p)
        return 1
    if mode == 2:
        _default_name(ram, p)
        ram.put(p + 4, "H", 3)
        return 1
    if mode != 0:
        return 0
    player = ram.u16(p + 0xC)
    pressed = ram.u16(PAD_PRESSED + 2 * player)
    rep = ram.u16(PAD_REPEAT + 2 * player)
    step = (rep >> 13 & 1) - (rep >> 15)
    if step:
        ram.put(p + 7, "B", 1)
    cursor = wrap(0, ram.u16(p + 8) + step, 39)
    ram.put(p + 8, "H", cursor)
    pos = ram.u16(p + 4)
    ch = ram.u8(ALPHABET + cursor) if pos < 3 else 0
    ram.put(p + pos, "B", ch)
    if not pressed & 0xF0:
        return 0
    ram.put(p + 6, "B", 1)
    if ch == ord("<"):
        if pos:
            ram.put(p + pos, "B", 0x20)
            ram.put(p + 4, "H", pos - 1)
        return 0
    if ch == ord("="):
        _finish_name(ram, p)
        return 1
    ram.put(p + pos, "B", ch)
    pos = (pos + 1) & 0xFFFF
    ram.put(p + 4, "H", pos)
    if pos < 3:
        return 0
    if not ram.u32(UNLOCKED) & 0x20000:
        typed = Ram(bytes(ram.u8(p + i) for i in range(3)) + b"\0")   # the stack copy
        if _cstr(ram, GON_NAME) == _cstr(typed, 0):
            unlock_char(ram, 0x11)
    _finish_name(ram, p)
    return 1


def _cstr(ram: Ram, a: int) -> bytes:
    out = bytearray()
    while ram.u8(a):
        out.append(ram.u8(a))
        a += 1
    return bytes(out)


def time_table(ram: Ram, t: int, recptr: int) -> int:
    """FUN_800C1D1C: page 0 rows; returns the row of the record `*recptr` points at, or -1."""
    ram.put(t + 8, "H", 150)
    mask = 0x3FF
    for c in range(22):
        if ram.u32(recptr + 8 + 8 * c) < TIME_CAP:
            mask |= 1 << c
    n = popcount(mask & 0x1FFFFF)
    ram.put(t + 0xC, "H", n)
    pairs = [[c, ram.u32(recptr + 8 + 8 * c)] for c in range(22) if (mask & 0x1FFFFF) >> c & 1]
    sort_pairs(pairs, 1)
    for i, (c, _) in enumerate(pairs):
        ram.put(t + 0xE + 2 * i, "H", c)
    for i in range(n):
        if (recptr + 8 + 8 * ram.u16(t + 0xE + 2 * i)) & 0xFFFFFFFF == ram.u32(recptr):
            return i
    return -1


def survivor_sort(ram: Ram, table: int, entry: int) -> int:
    """FUN_800C1E8C: re-sort the ten survivors by wins; returns the old index of `entry` or -1."""
    rows = []
    found = -1
    for i in range(10):
        a = table + 8 * i
        rows.append((ram.u16(a), ram.u16(a + 2), bytes(ram.data[(a + 4) & 0x1FFFFF:(a + 8) & 0x1FFFFF])))
        if a == entry:
            found = i
    pairs = [[i, rows[i][1]] for i in range(10)]
    sort_pairs(pairs, 0)
    for k, (i, _) in enumerate(pairs):
        a = table + 8 * k
        ram.put(a, "H", rows[i][0])
        ram.put(a + 2, "H", rows[i][1])
        name = rows[i][2]
        end = name.index(0) if 0 in name else None
        if end is None:
            raise ValueError("unterminated survivor name")   # port guard, not a game path
        for j in range(end):
            ram.put(a + 4 + j, "B", name[j])
        ram.put(a + 4 + end, "B", 0)
    return found


def usage_table(ram: Ram, t: int) -> None:
    """FUN_800C1FA8: page 2 rows, sorted by usage, with per-mille shares at t+0x58."""
    mask, total = 0x3FF, 0
    for c in range(22):
        u = usage(ram, c)
        if u:
            mask |= 1 << c
            total += u
    n = popcount(mask & 0x1FFFFF)
    ram.put(t + 0xC, "H", n)
    pairs = []
    for c in range(22):
        if (mask & 0x1FFFFF) >> c & 1:
            u = usage(ram, c)
            pairs.append([c, u])
            ram.put(t + 0x58 + 2 * c, "H", permille(u, total & 0xFFFFFFFF))
    sort_pairs(pairs, 0)
    for i, (c, _) in enumerate(pairs):
        ram.put(t + 0xE + 2 * i, "H", c)
    ram.put(t + 8, "H", 150)
    ram.put(t + 0x84, "H", ram.u16(t + 0x58 + 2 * (pairs[0][0] if pairs else ram.s32(0))))


def backdrop_camera(ram: Ram) -> None:
    """FUN_800C3AAC (the camera build and stage drawing it then calls are not ported)."""
    ram.put(0x800D370C, "i", ram.s32(0x800D370C) - 3)
    a = (ram.u16(0x800D3730) - 3) & 0xFFF
    ram.put(0x800D3730, "H", a)
    x = ram.s16(COS_TABLE + 2 * a) * 5000
    z = ram.s16(SIN_TABLE + 2 * a) * 5000
    x = (x + 0xFFF if x < 0 else x) >> 12
    z = (z + 0xFFF if z < 0 else z) >> 12
    ram.put(0x800D372C, "h", x)
    ram.put(0x800D372E, "h", z)
    ram.put(0x800D371C, "i", ram.s16(0x800D372C))
    ram.put(0x800D3724, "i", ram.s16(0x800D372E))


def _survivor_page(ram: Ram) -> int:
    i = survivor_sort(ram, SURVIVORS, ram.u32(SURVIVOR_PTR))
    if i != -1:
        ram.put(SURVIVOR_PTR, "I", SURVIVORS + 8 * i)
    ram.put(TABLE + 0xC, "H", 10)
    for k in range(10):
        ram.put(TABLE + 0xE + 2 * k, "H", k)
    ram.put(TABLE + 8, "H", 150)
    return i


def ranking_frame(ram: Ram, draw=None) -> int:
    """FUN_800C2A24: one frame of game state 17. `draw(ram)` replaces the drawing section."""
    sub = ram.u16(SUB_STATE)
    if sub > 1 and (ram.u16(PAD_PRESSED) | ram.u16(PAD_PRESSED + 2)) & 0x800:
        pending = ram.u8(NAME_PENDING)
        if pending:
            name_entry(ram, NAME, 2)
            if pending & 1:
                strcpy(ram, ram.u32(TIME_RECORD_PTR) + 4, NAME)
            if pending & 2:
                strcpy(ram, ram.u32(SURVIVOR_PTR) + 4, NAME)
            ram.put(NAME_PENDING, "B", 0)
            save_pending(ram)
        goto_transition(ram, 4)
        return 1
    t = TABLE
    timer = ram.s32(STATE_TIMER)
    if sub == 0:
        if ram.u8(NAME_PENDING) == 0:
            held = ram.u16(PAD_HELD + 2)
            if held & 0x2000:
                ram.put(PAGE, "B", 0)
            elif held & 0x8000:
                ram.put(PAGE, "B", 1)
            elif held & 0x1000:
                ram.put(PAGE, "B", 2)
        sub = 1
        ram.put(SUB_STATE, "H", 1)
    if sub == 1:
        pending = ram.u8(NAME_PENDING)
        if pending:
            if not pending & 1:
                if not pending & 2:
                    ram.put(PAGE, "B", 2)
                    ram.put(NAME_PENDING, "B", 0)
                    return _ranking_draw(ram, draw)
                ram.put(PAGE, "B", 1)
                ram.put(t + 0x88, "H", _survivor_page(ram))
            else:
                ram.put(PAGE, "B", 0)
                ram.put(t + 0x88, "H", time_table(ram, t, TIME_RECORD_PTR))
            name_init(ram, NAME, ram.u8(NAME_PLAYER), ram.u8(NAME_CHAR))
        else:
            page = ram.u8(PAGE)
            if page == 1:
                _survivor_page(ram)
            elif page == 0:
                time_table(ram, t, TIME_RECORD_PTR)
            elif page == 2:
                usage_table(ram, t)
            ram.put(t + 0x88, "H", 0xFFFF)
        ram.put(SUB_STATE, "H", 2)
        ram.put(t + 6, "H", 0)
        ram.put(t, "H", 0)
        return _ranking_draw(ram, draw)
    if sub == 2:
        ram.put(t, "H", 1)
        timer = 0
        sub = 3
        ram.put(SUB_STATE, "H", 3)
    if sub == 3:
        if draw:
            draw.fade(ram, timer)
        timer += 8
        ram.put(STATE_TIMER, "i", timer)
        if timer > 0xFF:
            ram.put(SUB_STATE, "H", 4 if ram.u8(NAME_PENDING) == 0 else 10)
    elif sub == 4:
        count = ram.u16(t + 0xC)
        ram.put(t + 0x54, "I", count)
        r = count % 5 or 5
        ram.put(t + 0x50, "I", count - r)
        ram.put(SUB_STATE, "H", 5)
        ram.put(t, "H", 2)
        ram.put(t + 2, "h", count * -0x48 + 0xA8)
    elif sub == 5:
        group = ram.s32(t + 0x50)
        ram.put(t + 4, "h", group * -0x48 + 0xA8)
        ram.put(t + 2, "h", ram.u16(t + 2) + 12)
        if ram.s16(t + 4) <= ram.s16(t + 2):
            ram.put(t + 6, "H", 0)
            ram.put(t + 0xA, "H", 0)
            ram.put(SUB_STATE, "H", 6)
            ram.put(t + 0x54, "I", group)
            ram.put(t + 2, "H", ram.u16(t + 4))
    elif sub == 6:
        hold = ram.u16(t + 6)
        ram.put(t + 0xA, "H", hold if hold < 0x40 else 0x40)
        ram.put(t + 6, "H", hold + 1)
        if ram.u16(t + 8) <= ram.u16(t + 6):
            if ram.s32(t + 0x50) < 1:
                ram.put(STATE_TIMER, "i", 0)
                ram.put(SUB_STATE, "H", 7)
            else:
                ram.put(SUB_STATE, "H", 5)
                ram.put(t + 0x50, "i", ram.s32(t + 0x50) - 5)
    elif sub == 7:
        timer += 1
        ram.put(STATE_TIMER, "i", timer)
        if timer > 0x3B:
            ram.put(SUB_STATE, "H", 8)
    elif sub in (8, 9):
        if sub == 8:
            timer = 0x100
            ram.put(SUB_STATE, "H", 9)
        if draw:
            draw.fade(ram, timer)
        timer -= 8
        ram.put(STATE_TIMER, "i", timer)
        if timer <= 0:
            ram.put(SUB_STATE, "H", 0xE)
            ram.put(t, "H", 0)
    elif sub == 10:
        sel = ram.u16(t + 0x88)
        count = ram.u16(t + 0xC)
        if sel < 2:
            ram.put(t + 0x50, "I", 0)
            ram.put(t + 0x86, "H", sel)
        else:
            ram.put(t + 0x50, "I", count - 5)
            if count - 3 < sel:
                ram.put(t + 0x86, "H", 5 - (count - sel))
            else:
                ram.put(t + 0x50, "I", sel - 2)
                ram.put(t + 0x86, "H", 2)
        ram.put(t + 0xA, "H", 0x40)
        ram.put(SUB_STATE, "H", 0xB)
        ram.put(t + 0x54, "I", 0)
        ram.put(t, "H", 2)
        ram.put(t + 2, "h", count * -0x48 + 0xA8)
    elif sub == 0xB:
        target = (ram.s32(t + 0x50) * -0x48 + 0xA8) & 0xFFFF
        ram.put(t + 4, "H", target)
        target = target - 0x10000 if target & 0x8000 else target
        step = (target - ram.s16(t + 2) + 0xF) >> 4
        step = 1 if step == 0 else min(step, 0x10)
        y = (ram.u16(t + 2) + step) & 0xFFFF
        ram.put(t + 2, "H", y)
        if ram.s16(t + 4) <= (y - 0x10000 if y & 0x8000 else y):
            ram.put(t + 6, "H", 3000)
            ram.put(t, "H", 3)
            ram.put(SUB_STATE, "H", 0xC)
            ram.put(t + 2, "H", ram.u16(t + 4))
    elif sub == 0xC:
        left = (ram.u16(t + 6) - 1) & 0xFFFF
        ram.put(t + 6, "H", left)
        done = name_entry(ram, NAME, int(left == 0))
        pending = ram.u8(NAME_PENDING)
        if pending & 1:
            strcpy(ram, ram.u32(TIME_RECORD_PTR) + 4, NAME)
        if pending & 2:
            strcpy(ram, ram.u32(SURVIVOR_PTR) + 4, NAME)
        if done:
            ram.put(NAME_PENDING, "B", 0)
            save_pending(ram)
            ram.put(t, "H", 4)
            ram.put(STATE_TIMER, "i", 0)
            ram.put(SUB_STATE, "H", 0xD)
    elif sub == 0xD:
        timer += 1
        ram.put(STATE_TIMER, "i", timer)
        if timer > 0x77:
            ram.put(SUB_STATE, "H", 8)
    elif sub == 0xE:
        ram.put(t, "H", 0)
        ram.put(PAGE, "B", (ram.u8(PAGE) + 1) % 3)
        goto_transition(ram, 3)
    return _ranking_draw(ram, draw)


def _ranking_draw(ram: Ram, draw=None) -> int:
    if draw:
        draw(ram)
        return 0x800B0000
    mode = ram.u16(TABLE)
    if mode in (1, 2, 3, 4):
        cl.horizon_band(ram)
        backdrop_camera(ram)
    return 0x800B0000


def _round12(v: int) -> int:
    return (v + 0xFFF if v < 0 else v) >> 12


def ranking_backdrop_setup(ram: Ram) -> None:
    """FUN_800C390C (game state 16): the stage backdrop of the ranking screen.

    The fighter/scene reset it calls (FUN_80036BC8) is not ported.
    """
    ram.put(MODE, "I", 6)
    ram.put(0x800AFF68, "B", 0)
    ram.put(0x800AE39C, "H", 1)
    skip = [ram.u32(0x800CBE58 + 4 * i) for i in range(4)]
    while True:
        stage = ram.u8(BACKDROP_STAGE) % 13
        ram.put(BACKDROP_STAGE, "B", stage)
        if stage not in skip:
            break
        ram.put(BACKDROP_STAGE, "B", stage + 1)
    ram.put(BACKDROP_STAGE, "B", stage + 1)
    ram.put(0x800AE14C, "H", stage)
    ram.put(0x800D3730, "H", 0xC00)
    x = _round12(ram.s16(COS_TABLE + 2 * 0xC00) * 5000)
    z = _round12(ram.s16(COS_TABLE + 2 * 0x800) * 5000)
    ram.put(0x800D372C, "h", x)
    ram.put(0x800D372E, "h", z)
    ram.put(0x800AA658, "i", -1000)
    ram.put(0x800ABEE4, "i", 1000)
    ram.put(0x800AA660, "i", 0)
    ram.put(0x800ABEEC, "i", 0)
    ram.put(0x800D371C, "i", ram.s16(0x800D372C))
    ram.put(0x800D3720, "i", -0x578)
    ram.put(0x800D3724, "i", ram.s16(0x800D372E))
    for off in (0, 4, 8):
        ram.put(0x800D3708 + off, "i", 0)


# ---- result.ovl ----
BRIGHT = 0x800FAE78              # s32 screen brightness (0x100 = full)
SEQ_STATE, SEQ_DELAY = 0x800A37A8, 0x800A37A9
SPU_STATUS = 0x801F8000          # where the verifier's SpuGetKeyStatus stub reads its answer
BANNER_X, BANNER_Y = 0x80102690, 0x80102694
MENU_EXIT_FLAG = 0x80098DDD
# team battle
T_FIGHT, T_LOST1, T_LOST2, T_LEFT1, T_LEFT2 = 0x800FAC48, 0x800FAC50, 0x800FAC54, 0x800FAC58, 0x800FAC5C
T_MSG, T_SLIDE, T_LINE = 0x800FAC60, 0x800FAC64, 0x800FAC68
T_MEMBER1, T_MEMBER2 = 0x800FAC78, 0x800FAD28
# time attack
A_FRAME, A_ROWS, A_ROW_ANIM, A_SHOW, A_WAIT = 0x800FADF8, 0x800FADD8, 0x800FADDC, 0x800FADF0, 0x800FADF4
A_TOTAL, A_RECORD, A_PLAYER, A_KEY = 0x800FADEC, 0x800FADE0, 0x800FADE4, 0x800FADE8
# survival
S_FRAME, S_COUNT, S_CHARS, S_ROW, S_FLAG, S_WAIT = 0x800FAE44, 0x800FAE00, 0x800FAE10, 0x800FAE28, 0x800FAE38, 0x800FAE3C
S_TOTAL, S_ANIM, S_PLAYER, S_RANK, S_KEY = 0x800FAE40, 0x800FAE48, 0x800FAE2C, 0x800FAE30, 0x800FAE34
# Tekken Force
F_FRAME, F_TEX, F_COLOUR, F_FLIP = 0x800FAE60, 0x800FAE50, 0x800FAE58, 0x800FAE5C
F_SHOWN, F_BOSS, F_PHASE, F_FORCE = 0x800FAE64, 0x800FAE68, 0x800FAE6C, 0x800FAE70
RESULT_WAIT = 0x1248             # 4,680 frames


def attract_advance(ram: Ram) -> None:
    """FUN_8004FB9C: next attract step, skipping 3."""
    step = ram.u8(0x8009831E)
    while True:
        step = step + 1 if step + 1 <= 3 else 0
        if step != 3:
            break
    ram.put(0x8009831E, "B", step)


def controller_setting(ram: Ram, player: int, value: int) -> None:
    """FUN_8002A3C0."""
    ram.put(0x800A9621 + 0x2A * player, "B", value)


def controllers_reset(ram: Ram) -> None:
    """FUN_800291B0."""
    for p in range(2):
        for k in range(4):
            ram.put(0x8009BDE8 + 8 * p + 2 * k, "H", 0)
        controller_setting(ram, p, 0)
    ram.put(0x8009BDE0, "B", 0)


def menu_exit(ram: Ram) -> int:
    """FUN_80051304: Select + Start (Start alone in the demonstration) returns to the main menu.

    The CD/sound resets it performs (FUN_8006AE4C, FUN_8004B8B4) are not ported; its sound
    (FUN_8004B88C) goes through HOOKS.
    """
    p0, p1 = ram.u16(PAD_PRESSED), ram.u16(PAD_PRESSED + 2)
    if ram.u32(MODE) == 6:
        if not (p0 | p1) & 0x800:
            return 0
    elif not ((ram.u16(PAD_HELD) & 0xFFF3) == 0x900 and p0 & 0x100) \
            and not ((ram.u16(PAD_HELD + 2) & 0xFFF3) == 0x900 and p1 & 0x100) \
            and ram.u8(MENU_EXIT_FLAG) != 3:
        return 0
    ram.put(MENU_EXIT_FLAG, "B", 0)
    controllers_reset(ram)
    HOOKS.sound(ram, 0x4CC0)
    goto_transition(ram, 4)
    return 1


def win_voice(ram: Ram, player: int) -> int:
    """FUN_80075A90: 1 for Tiger (costume key 0x22), else plays the voice and returns 0."""
    return int(ram.s16(FIGHTER[0] + 0x188C * player + 0x14) == 0x22)


def result_sounds(ram: Ram, player: int) -> None:
    if win_voice(ram, player) == 0:
        ram.put(SEQ_STATE, "B", ram.u8(SEQ_STATE) + 1)          # FUN_80075B34


def seq_reset(ram: Ram) -> None:
    """FUN_80075B1C."""
    ram.put(SEQ_STATE, "B", 0)
    ram.put(SEQ_DELAY, "B", 15)


def seq_tick(ram: Ram) -> None:
    """FUN_80075B4C: after the victory voice, wait for SPU voice 2 and 15 frames, then 0x86DA."""
    state = ram.s8(SEQ_STATE)
    if state != 1:
        if state < 2:
            return
        if state != 2:
            if state != 3:
                return
            delay = (ram.u8(SEQ_DELAY) - 1) & 0xFF
            ram.put(SEQ_DELAY, "B", delay)
            if delay and delay < 0x80:
                return
            ram.put(SEQ_STATE, "B", 0)
            return
        if ram.u32(SPU_STATUS) == 1:
            return
    ram.put(SEQ_STATE, "B", state + 1)


def banner_scroll(ram: Ram) -> None:
    """The state kept by FUN_800F18FC (scrolling tiles and banner)."""
    ram.put(BANNER_X, "I", (ram.u32(BANNER_X) + 0x17F) % 0x180)
    ram.put(BANNER_Y, "I", (ram.u32(BANNER_Y) + 0x342) % 0x344)


def total_time(ram: Ram) -> int:
    """FUN_800F28E8: the ten stage times of the time attack run, capped."""
    total = sum(ram.u32(MODE + 0x40 + 8 * k) for k in range(10)) & 0xFFFFFFFF
    total = total - (1 << 32) if total & 0x80000000 else total
    return TIME_CAP if total > TIME_CAP else total


def _fade_in(ram: Ram, next_sub: int) -> bool:
    b = ram.s32(BRIGHT) + 8
    if b < 0x100:
        ram.put(BRIGHT, "i", b)
        return False
    ram.put(BRIGHT, "i", 0x100)
    ram.put(SUB_STATE, "H", next_sub)
    return True


def _fade_out(ram: Ram, next_sub: int) -> None:
    b = ram.s32(BRIGHT) - 4
    if b < 1:
        b = 0
        ram.put(SUB_STATE, "H", next_sub)
    ram.put(BRIGHT, "i", b)


def team_result(ram: Ram, draw=None) -> None:
    """FUN_800EF4AC (game state 12). `draw(ram)` replaces the drawing (default: only its state)."""
    if menu_exit(ram):
        return
    sub = ram.u16(SUB_STATE)
    if sub > 1:
        for p in range(2):
            if ram.u16(PAD_PRESSED + 2 * p) & 0x800:
                ram.put(PLAYER_ACTIVE + 2 * p, "H", 1)
                ram.put(0x800AE406, "B", p)                     # FUN_80051474
                ram.put(0x800B0A06, "B", (p + 1) & 1)
                ram.put(0x800AE218, "B", 0)
                ram.put(SUB_STATE, "H", 10)
        sub = ram.u16(SUB_STATE)
    timer = ram.s32(STATE_TIMER)
    if sub == 0:
        a = b = 0
        for k in range(ram.u8(MODE + 0x58)):
            ram.put(T_MEMBER1 + 4 * k, "i", b)
            ram.put(T_MEMBER2 + 4 * k, "i", a)
            code = ram.u16(MODE + 0x38 + 2 * k)
            if code in (1, 3):
                a += 1
            if code in (2, 3):
                b += 1
        for addr in (T_FIGHT, BRIGHT, T_LOST1, T_LOST2, T_LINE, T_MSG, T_SLIDE):
            ram.put(addr, "I", 0)
        ram.put(SUB_STATE, "H", 1)
        ram.put(T_LEFT1, "I", ram.u8(MODE + 0x65))
        ram.put(T_LEFT2, "I", ram.u8(MODE + 0x72))
    elif sub == 1:
        _fade_in(ram, 2)
    elif sub == 2:
        line = ram.s32(T_LINE) + 1
        ram.put(T_LINE, "i", line)
        if line >= 9:
            ram.put(T_LINE, "i", 8)
            code = ram.u16(MODE + 0x38 + 2 * ram.s32(T_FIGHT))
            if code in (1, 3):
                ram.put(T_LOST2, "i", ram.s32(T_LOST2) + 1)
                ram.put(T_LEFT2, "I", ram.u32(T_LEFT2) - 1)
            if code in (2, 3):
                ram.put(T_LOST1, "i", ram.s32(T_LOST1) + 1)
                ram.put(T_LEFT1, "I", ram.u32(T_LEFT1) - 1)
            ram.put(STATE_TIMER, "i", 0)
            ram.put(SUB_STATE, "H", 3)
    elif sub == 3:
        timer += 1
        ram.put(STATE_TIMER, "i", timer)
        if timer >= 2:
            ram.put(T_LINE, "i", 0)
            fight = ram.s32(T_FIGHT) + 1
            ram.put(T_FIGHT, "i", fight)
            ram.put(SUB_STATE, "H", 4 if ram.u8(MODE + 0x58) <= fight else 2)
    elif sub in (4, 5):
        if sub == 4:
            ram.put(T_MSG, "i", 1)
            ram.put(T_SLIDE, "i", 0x1E)
            ram.put(SUB_STATE, "H", 5)
        slide = ram.s32(T_SLIDE) - 1
        if slide < 1:
            slide = 0
            ram.put(SUB_STATE, "H", 6)
        ram.put(T_SLIDE, "i", slide)
    elif sub in (6, 7):
        if sub == 6:
            timer = 0
            ram.put(STATE_TIMER, "i", 0)
            ram.put(SUB_STATE, "H", 7)
        pads = ram.u16(PAD_PRESSED) | ram.u16(PAD_PRESSED + 2)
        if pads == 0x100:
            ram.put(SUB_STATE, "H", 0)
        else:
            if pads & 0xF0:
                ram.put(T_MSG, "i", (ram.s32(T_MSG) + 1) & 1)
            timer += 1
            ram.put(STATE_TIMER, "i", timer)
            if timer > 0x707:
                ram.put(T_MSG, "i", 0)
                ram.put(BRIGHT, "i", 0x100)
                ram.put(SUB_STATE, "H", 8)
    elif sub == 8:
        _fade_out(ram, 9)
    elif sub == 9:
        ram.put(GAME_STATE, "H", 0x10)
        ram.put(SUB_STATE, "H", 0)
    elif sub == 10:
        ram.put(GAME_STATE, "H", 8)
        ram.put(SUB_STATE, "H", 0)
    (draw or banner_scroll)(ram)


def time_attack_result(ram: Ram, draw=None) -> None:
    """FUN_800EFF4C (game state 13)."""
    ram.put(A_FRAME, "i", ram.s32(A_FRAME) + 1)
    sub = ram.u16(SUB_STATE)
    if (ram.u16(PAD_PRESSED) | ram.u16(PAD_PRESSED + 2)) & 0x800 and (sub - 2) & 0xFFFFFFFF < 5:
        sub = 7
        ram.put(SUB_STATE, "H", 7)
    timer = ram.s32(STATE_TIMER)
    if sub == 0:
        draw_hold(ram, 1)
        draw_hold(ram, 0)
        attract_advance(ram)
        for addr in (A_FRAME, A_ROWS, A_ROW_ANIM, A_SHOW, BRIGHT, A_WAIT):
            ram.put(addr, "I", 0)
        ram.put(A_TOTAL, "i", total_time(ram))
        ram.put(A_RECORD, "I", ram.u8(NAME_PENDING) & 1)
        ram.put(SUB_STATE, "H", 1)
        ram.put(A_PLAYER, "I", ram.u32(MODE + 0x38))
        ram.put(A_KEY, "I", ram.u32(MODE + 0x3C))
        seq_reset(ram)
    elif sub == 1:
        _fade_in(ram, 2)
    elif sub == 2:
        anim = ram.s32(A_ROW_ANIM) + 1
        ram.put(A_ROW_ANIM, "i", anim)
        if anim > 0x10:
            ram.put(STATE_TIMER, "i", 0)
            ram.put(A_ROW_ANIM, "i", 0)
            ram.put(SUB_STATE, "H", 3)
            ram.put(A_ROWS, "i", ram.s32(A_ROWS) + 1)
    elif sub == 3:
        timer += 1
        ram.put(STATE_TIMER, "i", timer)
        if timer >= 6:
            ram.put(SUB_STATE, "H", 4 if ram.s32(A_ROWS) > 9 else 2)
    elif sub in (4, 5):
        if sub == 4:
            ram.put(A_SHOW, "i", 1)
            ram.put(A_WAIT, "i", 0x1E)
            ram.put(SUB_STATE, "H", 5)
        wait = ram.s32(A_WAIT) - 1
        ram.put(A_WAIT, "i", wait)
        if wait < 1:
            ram.put(A_WAIT, "i", 0)
            result_sounds(ram, ram.u32(A_PLAYER))
            ram.put(SUB_STATE, "H", 6)
    elif sub in (6, 7):
        stay = False
        if sub == 6:
            if ram.u16(PAD_PRESSED + 2 * ram.u32(A_PLAYER)) & 0xF0:
                ram.put(A_SHOW, "i", (ram.s32(A_SHOW) + 1) & 1)
            stay = ram.s32(A_FRAME) < RESULT_WAIT
        if not stay:
            ram.put(A_SHOW, "i", 0)
            ram.put(BRIGHT, "i", 0x100)
            ram.put(SUB_STATE, "H", 8)
    elif sub == 8:
        _fade_out(ram, 9)
    elif sub == 9:
        ram.put(GAME_STATE, "H", 0x10)
        ram.put(SUB_STATE, "H", 0)
    seq_tick(ram)
    if draw:
        draw(ram)


def survival_result(ram: Ram, draw=None) -> None:
    """FUN_800F0A78 (game state 14)."""
    ram.put(S_FRAME, "i", ram.s32(S_FRAME) + 1)
    sub = ram.u16(SUB_STATE)
    if (ram.u16(PAD_PRESSED) | ram.u16(PAD_PRESSED + 2)) & 0x800 and (sub - 2) & 0xFFFFFFFF < 6:
        sub = 8
        ram.put(SUB_STATE, "H", 8)
    timer = ram.s32(STATE_TIMER)
    if sub == 0:
        attract_advance(ram)
        seq_reset(ram)
        pairs, mask = [], 0
        for c in range(22):
            wins = ram.u16(MODE + 0x60 + 2 * c)
            if 0x1FFFFF >> c & 1 and wins:
                pairs.append([c, wins])
                mask |= 1 << c
        count = popcount(mask)
        ram.put(S_COUNT, "i", count)
        sort_pairs(pairs, 0)
        for i, (c, _) in enumerate(pairs[:count]):
            ram.put(S_CHARS + i, "B", c)
        ram.put(S_FRAME, "i", 0)
        ram.put(BRIGHT, "i", 0)
        ram.put(STATE_TIMER, "i", 0)
        ram.put(S_ROW, "i", 0)
        ram.put(S_FLAG, "i", 2)
        ram.put(S_WAIT, "i", 0x1E)
        ram.put(S_TOTAL, "i", 0)
        ram.put(SUB_STATE, "H", 1)
        ram.put(S_PLAYER, "I", ram.u32(MODE + 0x38))
        ram.put(S_KEY, "I", ram.u32(MODE + 0x3C))
        ram.put(S_RANK, "I", ram.u32(MODE + 0x40))
    elif sub == 1:
        b = ram.s32(BRIGHT) + 8
        ram.put(BRIGHT, "i", b)
        if b > 0xFF:
            ram.put(BRIGHT, "i", 0x100)
            ram.put(SUB_STATE, "H", 2)
            ram.put(S_ROW, "i", 0)
            ram.put(S_ANIM, "I", 0)
            if ram.s32(S_COUNT) < 1:
                ram.put(SUB_STATE, "H", 4)
                ram.put(S_ROW, "i", ram.s32(S_COUNT))
    elif sub in (2, 3):
        if sub == 2:
            ram.put(S_ANIM, "I", 1)
            timer = 4
            ram.put(SUB_STATE, "H", 3)
            ram.put(S_TOTAL, "i", ram.s32(S_TOTAL) + 1)
        timer -= 1
        ram.put(STATE_TIMER, "i", timer)
        if timer < 1:
            char = ram.u8(S_CHARS + ram.s32(S_ROW))
            if ram.u32(S_ANIM) < ram.u16(MODE + 0x60 + 2 * char):
                ram.put(STATE_TIMER, "i", 4)
                ram.put(S_ANIM, "I", ram.u32(S_ANIM) + 1)
                ram.put(S_TOTAL, "i", ram.s32(S_TOTAL) + 1)
            else:
                row = ram.s32(S_ROW) + 1
                ram.put(S_ROW, "i", row)
                ram.put(STATE_TIMER, "i", 0)
                if row < ram.s32(S_COUNT):
                    ram.put(SUB_STATE, "H", 2)
                else:
                    ram.put(SUB_STATE, "H", 4)
                    ram.put(S_ROW, "i", ram.s32(S_COUNT))
    elif sub == 4:
        ram.put(STATE_TIMER, "i", 4)
        ram.put(SUB_STATE, "H", 5)
    elif sub in (5, 6):
        if sub == 5:
            ram.put(S_FLAG, "i", 2)
            ram.put(S_WAIT, "i", 0x1E)
            ram.put(SUB_STATE, "H", 6)
        wait = ram.s32(S_WAIT) - 1
        ram.put(S_WAIT, "i", wait)
        if wait == 0:
            if ram.u32(S_RANK):
                result_sounds(ram, ram.u32(S_PLAYER))
            ram.put(SUB_STATE, "H", 7)
    elif sub in (7, 8):
        if sub == 8 or ram.s32(S_FRAME) >= RESULT_WAIT:
            ram.put(S_FLAG, "i", 0)
            ram.put(BRIGHT, "i", 0x100)
            ram.put(SUB_STATE, "H", 9)
    elif sub == 9:
        _fade_out(ram, 10)
    elif sub == 10:
        ram.put(GAME_STATE, "H", 0x10)
        ram.put(SUB_STATE, "H", 0)
    elif sub == 11:
        ram.put(GAME_STATE, "H", 8)
        ram.put(SUB_STATE, "H", 0)
    seq_tick(ram)
    (draw or banner_scroll)(ram)


def force_result(ram: Ram, draw=None) -> None:
    """FUN_800F1F08 (game state 15). `draw(ram)` draws and runs the display counters instead."""
    ram.put(F_FRAME, "i", ram.s32(F_FRAME) + 1)
    player = ram.u8(MODE + 0x3E)
    if ram.u16(PAD_PRESSED + 2 * player) & 0x800 and ram.s16(SUB_STATE) == 2:
        ram.put(SUB_STATE, "H", 3)
    sub = ram.s16(SUB_STATE)
    if sub == 0:
        draw_hold(ram, 1)
        draw_hold(ram, 0)
        attract_advance(ram)
        side = player & 1
        ram.put(F_FRAME, "i", 0)
        ram.put(BRIGHT, "i", 0)
        for i in range(4):
            ram.put(F_TEX + 2 * i, "H", ram.u16(0x800FAC34 + 8 * side + 2 * i))
        char, costume = ram.u16(0x800AE224 + 2 * side), ram.u16(0x800AE260 + 2 * side)
        if char > 0x15 or costume > 3:
            char, costume = 0x16, 0
        word = ram.u32(ram.u32(0x80097EDC + 4 * (char * 4 + costume)))
        ram.put(F_COLOUR, "I", word >> 8)
        for addr in (F_SHOWN, F_BOSS, F_PHASE, F_FORCE):
            ram.put(addr, "I", 0)
        ram.put(SUB_STATE, "H", 1)
        ram.put(F_FLIP, "B", (word & 0xFF) >> 5 & 1)
        seq_reset(ram)
    elif sub == 1:
        b = ram.s32(BRIGHT) + 8
        ram.put(BRIGHT, "i", b)
        if b > 0xFF:
            ram.put(BRIGHT, "i", 0x100)
            ram.put(SUB_STATE, "H", 2)
    elif sub == 2:
        if ram.s32(F_FRAME) > RESULT_WAIT:
            ram.put(SUB_STATE, "H", 3)
    elif sub == 3:
        ram.put(BRIGHT, "i", 0x100)
        ram.put(SUB_STATE, "H", 4)
    elif sub == 4:
        _fade_out(ram, 5)
    elif sub == 5:
        ram.put(GAME_STATE, "H", 0x10)
        ram.put(SUB_STATE, "H", 0)
    if ram.s16(SUB_STATE) > 1:
        ram.put(F_SHOWN, "i", ram.s32(F_SHOWN) + 1)
    if draw:
        draw(ram)
        return
    shown = ram.s32(F_SHOWN)
    flags = ram.u32(MODE + 0x40)
    if not flags & 0x10:
        return
    if shown > 0x59:
        ram.put(F_BOSS, "i", ram.s32(F_BOSS) + 1)
    phase = ram.s32(F_PHASE)
    if phase == 1:
        if shown & 1 == 0:
            ram.put(F_FORCE, "i", ram.s32(F_FORCE) + 1)
        if ram.u16(MODE + 0x3C) < ram.s32(F_FORCE) or ram.s16(SUB_STATE) > 2:
            ram.put(F_PHASE, "i", 2)
    elif phase < 2 and phase == 0 and ram.s32(F_BOSS) > 0x4F:
        ram.put(F_PHASE, "i", 1)
        ram.put(F_FORCE, "i", 0)


# ---- ending.ovl: staff roll ----
ROLL_TITLES = 0x8011DAD8         # the title block (NULL-terminated pointer list)
ROLL_ROWS = 0x8011DAE4           # the scrolling rows (NULL-terminated pointer list)
R_CLOCK, R_SKIP, R_END = 0x8011E5F0, 0x8011E5F4, 0x8011E5F8
R_OFFSET, R_FIRST, R_PHASE = 0x80194618, 0x8019461C, 0x80194620
R_BASE_BRIGHT, R_RGB = 0x80194624, 0x80194626           # u8; three s8 colour offsets
R_LEFT, R_Y, R_X0, R_X1, R_INDENT, R_WIDTH = 0x8019462C, 0x80194630, 0x80194634, 0x80194638, 0x8019463C, 0x80194640
R_HALF, R_BRIGHT, R_ROW, R_ROW_Y, R_WIDTH2, R_RAMP = 0x80194644, 0x80194648, 0x8019464C, 0x80194650, 0x80194654, 0x80194658
R_FADE, R_HOLD = 0x8019465C, 0x80194660
R_PACKETS, R_PACKETS2, R_OT = 0x80194664, 0x80194668, 0x8019466C
FONT_WIDE, FONT_NARROW = 0x800BC014, 0x800BC054         # glyph widths for font flag 1 / 0


def text_width(ram: Ram, s: int, wide: int) -> int:
    """FUN_801144B0: pixel width of a string (the kind digit of a row included)."""
    table, space = (FONT_WIDE, 8) if wide else (FONT_NARROW, 10)
    w = 0
    while ram.u8(s):
        c = ram.u8(s)
        if c < 0x31:
            w += space if c == 0x20 else ram.u8(table + c - 0x21)
        else:
            w += ram.u8(table + c - 0x22)
        s += 1
    return w


def _s8(v: int) -> int:
    v &= 0xFF
    return v - 256 if v & 0x80 else v


def _ramp_near_bottom(ram: Ram, y: int) -> None:
    """Colour of a row entering at the bottom of the screen (y 360-440)."""
    k = (0x1B8 - y) & 0xFFFFFFFF
    k = k - (1 << 32) if k & 0x80000000 else k
    ram.put(R_RAMP, "i", k)
    v = (k * 2 & 0xFF) | 1
    if v > 0x5A:
        v = (0x5A - ((v - 0x5A) >> 1)) & 0xFFFFFFFF
        ram.put(R_BRIGHT, "B", v)
        if v & 0xFF < 0x50:
            ram.put(R_BRIGHT, "B", 0x50)
    ram.put(R_RGB, "B", -3 - _s8(min(k * 7, 0xFD)))
    ram.put(R_RGB + 1, "B", -0x25 - _s8(min(k * 6, 0xDB)))
    ram.put(R_RGB + 2, "B", -0x4A - _s8(min(k * 5, 0xB6)))


def _ramp_near_top(ram: Ram, y: int) -> None:
    """Colour of a row leaving at the top of the screen (y 20-100)."""
    k = 100 - y
    ram.put(R_RAMP, "i", k)
    ram.put(R_BRIGHT, "B", y - 0x13)
    ram.put(R_RGB, "B", min(int(k * 7 / 2), 0xFD))
    ram.put(R_RGB + 1, "B", min(k * 3, 0xDB))
    ram.put(R_RGB + 2, "B", min(int(k * 5 / 2), 0xB6))


def _place(ram: Ram, entry: int, wide: int, y: int) -> None:
    w = text_width(ram, entry, wide)
    ram.put(R_WIDTH, "i", w)
    left = 0x98 - int(w / 2)
    ram.put(R_LEFT, "i", left)
    ram.put(R_Y, "i", y)
    ram.put(R_X0, "i", left + ram.s32(R_INDENT))
    ram.put(R_X1, "i", ram.s32(R_X0) + w)
    ram.put(R_WIDTH2, "i", w)


FULL_GLOW = (0xFD, 0xDB, 0xB6)


def _row_colour(ram: Ram, y_row: int, y: int, bottom: int, top_lo: int, top_len: int, draw=None) -> None:
    if (y_row - bottom) & 0xFFFFFFFF < 0x50:
        _ramp_near_bottom(ram, y)
        glow = None
    elif (y_row - top_lo) & 0xFFFFFFFF < top_len:
        _ramp_near_top(ram, y)
        glow = None
    elif (y_row - top_lo) & 0xFFFFFFFF < 0x1A4:
        ram.put(R_BRIGHT, "B", 0x50)
        return
    else:
        ram.put(R_BRIGHT, "B", 1)
        glow = FULL_GLOW
    if draw:
        draw.glow(ram, glow)


def staff_roll(ram: Ram, init: int, s3: int = 0, draw=None) -> int:
    """FUN_80112798: init = 1 sets up; each later call is one frame. Returns 1 when finished
    or skipped. s3 is the kind carried over from the caller's register for a row whose kind
    byte is not '0'-'5' (only the terminator, read from address 0)."""
    ram.put(R_OT, "I", ram.u32(0x800A96E0) + 0x1C)
    if init:
        for addr, v in ((R_PHASE, 0), (R_OFFSET, 0x1E0), (R_FIRST, 0), (R_INDENT, 0x20), (R_HALF, 0),
                        (R_CLOCK, 0), (R_ROW, 0), (R_HOLD, 0), (R_FADE, 0)):
            ram.put(addr, "i", v)
        ram.put(R_BASE_BRIGHT, "B", 0x78)
        ram.put(R_BASE_BRIGHT + 1, "B", 0)
        for i, v in enumerate((-3, -0x25, -0x4A)):
            ram.put(R_RGB + i, "b", v)
        ram.put(R_CLOCK, "i", ram.s32(R_CLOCK) + 1)
        return ram.u32(R_SKIP)
    if (ram.u16(PAD_PRESSED) | ram.u16(PAD_PRESSED + 2)) & 0x8F0:
        ram.put(R_SKIP, "i", 1)
    buf = ram.u32(0x800AE3C4)
    ram.put(R_PACKETS, "I", 0x80194670 + buf * 0x5000)
    ram.put(R_PACKETS2, "I", 0x8019E670 + buf * 0x7800)
    phase = ram.s32(R_PHASE)
    c = ram.s32(R_CLOCK)
    if phase == 0:
        if c > 0x1E:
            ram.put(R_PHASE, "i", 1)
            ram.put(R_CLOCK, "i", 0)
    elif phase == 1:
        if c == 0xF0:
            ram.put(R_PHASE, "i", 2)
    elif phase == 2:
        if ram.u32(SPU_STATUS) == 0:                     # FUN_8006BCC8, stubbed to the test word
            ram.put(R_PHASE, "i", 3)
            ram.put(R_FIRST, "i", 0)
            ram.put(R_CLOCK, "i", 0)
    elif phase == 3:
        if c == 0x3C:
            ram.put(R_PHASE, "i", 4)
            ram.put(R_CLOCK, "i", 0)
    elif phase == 4:
        ram.put(R_BRIGHT, "B", 0x5A)
        while ram.u32(ROLL_TITLES + 4 * ram.s32(R_ROW)):
            idx = ram.s32(R_ROW)
            entry = ram.u32(ROLL_TITLES + 4 * idx)
            first = int(idx == 0)
            _place(ram, entry, first, (0 if first else 0x12) + 0xDC)
            if c < 0x25:
                if c < 0x1E:
                    v = ((0x1B8 - ram.s32(R_Y)) * 2 & 0xFF) | 1
                    if v > 0x5A:
                        v = 0x5A - ((v - 0x5A) >> 1)
                        ram.put(R_BRIGHT, "B", v)
                        if v & 0xFF < 0x50:
                            ram.put(R_BRIGHT, "B", 0x50)
                ram.put(R_RGB, "B", -3 - _s8(min(c * 7, 0xFD)))
                ram.put(R_RGB + 1, "B", -0x25 - _s8(min(c * 6, 0xDB)))
                ram.put(R_RGB + 2, "B", -0x4A - _s8(min(c * 5, 0xB6)))
                if draw:
                    draw.glow(ram)
            elif c > 0xB4:
                ram.put(R_BRIGHT, "B", (0xD2 - c) * 3 + 1)
                ram.put(R_RAMP, "i", ram.u8(R_BASE_BRIGHT) + (0xD2 - c) * -4)
            if draw and c < 0xD2:
                draw.text(ram, ram.s32(R_Y), first, entry)
            ram.put(R_ROW, "i", idx + 1)
        ram.put(R_ROW, "i", 0)
        if c == 0xEF:
            ram.put(R_PHASE, "i", 5)
    elif phase == 5:
        if ram.s32(R_OFFSET) < -0x12:
            ram.put(R_FIRST, "i", ram.s32(R_FIRST) + 1)
            ram.put(R_OFFSET, "i", ram.s32(R_OFFSET) + 0x12)
            if ram.u32(ROLL_ROWS + 4 * ram.s32(R_FIRST)) == 0:
                ram.put(R_OFFSET, "i", 0)
                ram.put(R_PHASE, "i", 6)
                ram.put(R_BRIGHT, "B", 0)
                return 0
        ram.put(R_BRIGHT, "B", 0x5A)
        ram.put(R_ROW, "i", ram.s32(R_FIRST))
        ram.put(R_ROW_Y, "i", ram.s32(R_OFFSET))
        while ram.s32(R_ROW_Y) < 0x1E0:
            entry = ram.u32(ROLL_ROWS + 4 * ram.s32(R_ROW))
            if entry == 0 and ram.s32(R_END) == 0:
                ram.put(R_END, "i", 1)
                break
            kind = ram.u8(entry)
            if kind == 0x30:
                s3 = 0
            elif kind == 0x31:
                s3 = 1
            elif kind == 0x32:
                s3 = 2
            elif kind == 0x33:
                s3 = 3 if ram.u8(BALL_NEW) else -1
            elif kind == 0x34:
                s3 = -1 if ram.u8(BALL_NEW) else 0
            elif kind == 0x35:
                s3 = 1 if ram.u32(START_COSTUMES) & 0x40000 else -1
            y_row = ram.s32(R_ROW_Y)
            if s3 == 1:
                _place(ram, entry, 0, y_row)
                _row_colour(ram, y_row, y_row, 0x168, 0x14, 0x50, draw)
                if draw:
                    draw.text(ram, y_row, 0, entry + 1)
            elif s3 == 0:
                _place(ram, entry, 1, y_row + 4)
                end = ram.s32(R_END)
                if end == 0:
                    _row_colour(ram, y_row, y_row + 4, 0x164, 0x10, 0x50, draw)
                else:
                    if end == 1:
                        ram.put(R_HOLD, "i", ram.s32(R_HOLD) + 1)
                    if ram.s32(R_HOLD) == 0x26C:
                        ram.put(R_END, "i", 2)
                        ram.put(R_HOLD, "i", 0)
                    if ram.s32(R_END) > 1:
                        k = ram.s32(R_FADE) + 1
                        ram.put(R_FADE, "i", k)
                        if ram.s32(R_END) == 2:
                            ram.put(R_BRIGHT, "B", 0x50 - k)
                            if k == 0x50:
                                ram.put(R_END, "i", 3)
                                ram.put(R_FADE, "i", 0)
                            ram.put(R_RAMP, "i", k)
                            ram.put(R_RGB, "B", min(k * 7, 0xFD))
                            ram.put(R_RGB + 1, "B", min(k * 6, 0xDB))
                            ram.put(R_RGB + 2, "B", min(k * 5, 0xB6))
                            if draw:
                                draw.glow(ram)
                        elif ram.s32(R_END) != 3:
                            ram.put(R_BRIGHT, "B", 0x50)
                        else:
                            ram.put(R_BRIGHT, "B", 1)
                            ram.put(R_RAMP, "i", k)
                            if k == 0x50:
                                ram.put(R_END, "i", 4)
                                ram.put(R_OFFSET, "i", 0)
                                ram.put(R_PHASE, "i", 6)
                                ram.put(R_BRIGHT, "B", 0)
                                return 0
                            ram.put(R_RGB, "B", -3 - _s8(min(k * 7, 0xFD)))
                            ram.put(R_RGB + 1, "B", -0x25 - _s8(min(k * 6, 0xDB)))
                            ram.put(R_RGB + 2, "B", -0x4A - _s8(min(k * 5, 0xB6)))
                            if draw:
                                draw.glow(ram)
                if draw:
                    draw.text(ram, y_row + 4, 1, entry + 1)
            elif s3 == 3:
                _place(ram, entry, 1, y_row + 0x14)
                _row_colour(ram, y_row, y_row + 0x14, 0x154, 0, 0x50, draw)
                if draw:
                    draw.text(ram, y_row + 0x14, 1, entry + 1)
            ram.put(R_ROW, "i", ram.s32(R_ROW) + 1)
            ram.put(R_ROW_Y, "i", ram.s32(R_ROW_Y) + 0x12)
        if ram.s32(R_END) == 0:
            ram.put(R_OFFSET, "i", ram.s32(R_OFFSET) - (1 if ram.s32(R_HALF) == 0 else 2))
    elif phase == 6:
        if c == 0x2364:
            ram.put(R_CLOCK, "i", 0)
            ram.put(R_PHASE, "i", 7)
    elif phase == 7:
        if c > 0xB3:
            return 1
        if c < 0xB:
            ram.put(R_BRIGHT, "B", ram.u8(R_BRIGHT) + 0xC)
        elif c > 0x78:
            ram.put(R_BRIGHT, "B", ram.u8(R_BRIGHT) - 2)
        if draw:
            draw.logo(ram)
    half = ram.s32(R_HALF) + 1
    ram.put(R_HALF, "i", 0 if half == 2 else half)
    ram.put(R_CLOCK, "i", ram.s32(R_CLOCK) + 1)
    return ram.u32(R_SKIP)


# ---- arcade.ovl opponent picks: team battle CPU teams and survival ----
TEAM_MET = 0x800AFFC4            # u16 per character: times met in team battle
PICK_COUNT = 0x800B4F10          # arcade.ovl: the working list's length


def _bits_list(mask: int) -> list[int]:
    return [c for c in range(22) if mask >> c & 1]


def team_fill(ram: Ram, cpu: int, team: int, other: int) -> None:
    """arcade.ovl FUN_800B2724: completes a team (13 bytes: members as costume keys, +10 count
    already chosen, +11 costume, +12 size) from the unlocked characters (0x800982D0 & 0x1F7FFF)
    not in it. A CPU team of three or more first takes one of the two least-used characters
    (usage = plays + losses + draws). The rest come at random from the characters met least
    often in team battle (0x800AFFC4), widening the met-count window until there are enough,
    and the members are shuffled into the free places. A member takes the team costume, or the
    other one when that exact key is already in the other team. Every member's met count goes up."""
    avail = ram.u32(0x800982D0) & 0x1F7FFF
    for i in range(ram.u8(team + 10)):
        avail &= ~(1 << (ram.u8(team + i) >> 2 & 0x1F))
    extra, chosen = 0, 0
    if cpu and ram.u8(team + 12) >= 3:
        pairs = [[c, usage(ram, c)] for c in _bits_list(avail)]
        if pairs:
            sort_pairs(pairs, 1)
        if len(pairs) >= 2:
            extra = 1
            c = pairs[lcg2(ram) & 1][0]
            chosen |= 1 << (c & 0x1F)
            avail &= ~(1 << (c & 0x1F))
    pairs = [[c, ram.u16(TEAM_MET + 2 * c)] for c in _bits_list(avail)]
    if pairs:
        sort_pairs(pairs, 1)
    need = ram.u8(team + 12) - (ram.u8(team + 10) + extra)
    tol = 0
    while True:
        thr = pairs[0][1] + tol & 0xFFFFFFFF
        n = 0
        while n < len(pairs) and not thr < pairs[n][1]:
            n += 1
        if not n < need:
            break
        tol += 1
    pool = 0
    for k in range(n):
        pool |= 1 << (pairs[k][0] & 0x1F)

    def draw(buf: list[int]) -> int:
        cnt = ram.u32(PICK_COUNT)
        idx = lcg2(ram) % cnt
        cnt -= 1
        ram.put(PICK_COUNT, "I", cnt)
        c = buf[idx]
        buf[idx] = buf[cnt]
        return c

    buf = _bits_list(pool)
    ram.put(PICK_COUNT, "I", len(buf))
    for _ in range(extra, ram.u8(team + 12) - ram.u8(team + 10)):
        chosen |= 1 << (draw(buf) & 0x1F)
    buf = _bits_list(chosen)
    ram.put(PICK_COUNT, "I", len(buf))
    costume = ram.u8(team + 11)
    for s in range(ram.u8(team + 10), ram.u8(team + 12)):
        c = draw(buf)
        key = c * 4 + costume & 0xFF
        if any(ram.u8(other + i) == key for i in range(ram.u8(other + 10))):
            key = c * 4 + (costume ^ 1) & 0xFF
        ram.put(team + s, "B", key)
    for i in range(ram.u8(team + 12)):
        c = ram.u8(team + i) >> 2
        ram.put(TEAM_MET + 2 * c, "H", ram.u16(TEAM_MET + 2 * c) + 1 & 0xFFFF)


def survival_pick(ram: Ram, ctx: int) -> None:
    """arcade.ovl FUN_800B2B98: the next survival opponent. By the stage counter (+0x24) the
    pool is the ten original characters for stages 0-6, all but Ogre and True Ogre for 7-16,
    then all (always within 0x157FFF), minus the last four opponents (+0x50 ring, index +0x4C).
    The pick is random among those met least often (+0x60, u16 per character; within 4 of the
    least from 20 wins on, +0x44), in a costume from the frame counter's parity."""
    wins = ram.s32(ctx + 0x24)
    mask = 0x3FF if wins < 7 else 0x1FFFFF if wins >= 0x11 else 0xFBFFF
    mask &= 0x157FFF
    for i in range(4):
        v = ram.u32(ctx + 0x50 + 4 * i)
        if v != 0x16:
            mask &= ~(1 << (v & 0x1F))
    pairs = [[c, ram.u16(ctx + 0x60 + 2 * c)] for c in _bits_list(mask)]
    if pairs:
        sort_pairs(pairs, 1)
    thr = pairs[0][1] + (4 if ram.u32(ctx + 0x44) >= 0x14 else 0) & 0xFFFFFFFF
    n = 0
    while n < len(pairs) and not thr < pairs[n][1]:
        n += 1
    c = pairs[lcg2(ram) % n][0]
    ram.put(ctx + 0x48, "I", c * 4 + (ram.u32(0x800AE6E0) & 1))
    idx = ram.s32(ctx + 0x4C) + 1
    if idx >= 4:
        idx = 0
    ram.put(ctx + 0x4C, "I", idx)
    ram.put(ctx + 0x50 + 4 * idx, "I", c)
