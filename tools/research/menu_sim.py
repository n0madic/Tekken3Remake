#!/usr/bin/env python3
"""Integer ports of the menu screens of Tekken 3 (Japan Rev.1), logic and drawing together.

Like `draw_sim.py`, every routine writes the same RAM as the game, GPU packets and ordering
tables included, so `tools/research/verify_menu_sim.py` compares all of RAM with the harness.
Sound, music, CD, VRAM uploads and display-hardware calls are not ported (stubbed in the game).

Covered: the main menu (`title.ovl` state 4) with the mode start `FUN_800DAF2C`.
"""

from __future__ import annotations

import draw_sim as ds
import screens_sim as ss
from fight_sim import Ram

MENU_ENTRIES = 0x800B9464        # title.ovl: 10 x (string, mode, two-player flag, colour, spare)
MENU_LIST = 0x800EC590           # the visible entries: 8 bytes each, +7 = "new" mark
MENU_COUNT = 0x800EC584
MENU_SCROLL, MENU_GLOW, MENU_CHOSEN, MENU_PLAYERS = 0x800EC588, 0x800EC58C, 0x800EC580, 0x800EC574
MENU_CURSOR = 0x80098320
MENU_TO_OPTIONS = 0x80098321
MENU_PACKETS = 0x8015D368
MODE_OVERLAY = (0, 0, 0, 0, 0, 1, 0, 3, 2)   # FUN_800DB4E4: mode -> mode overlay logical id
DEMO_LIST = 0x800E3040
BUTTON_TABLE, BUTTON_TAIL = 0x800B9AF0, 0x800B9B0C


def pad_connected(ram: Ram, port: int) -> int:
    """FUN_8002A338."""
    return ram.u16(0x800A964C) >> (port & 31) & 1


def button_map(ram: Ram, player: int) -> None:
    """FUN_800DE7B4: the player's button layout (0x80098308) to the input map at 0x80098290."""
    dst = 0x80098290 + 0x20 * player
    for k in range(8):
        ram.put(dst + 2 * k, "H", ram.u16(BUTTON_TABLE + 2 * ram.u8(0x80098308 + 8 * player + k)))
    for k in range(8):
        ram.put(dst + 0x10 + 2 * k, "H", ram.u16(BUTTON_TAIL + 2 * k))


def mirror_costumes(ram: Ram, player: int) -> None:
    """FUN_8004F3CC: in a mirror match the other side takes a different costume."""
    other = player + 1 & 1
    a = [ram.u16(0x800AE224 + 2 * player), ram.u16(0x800AE260 + 2 * player), ram.u16(0x800AE484 + 2 * player),
         ram.u16(0x800AE6C0 + 2 * player)]
    b = [ram.u16(0x800AE224 + 2 * other), ram.u16(0x800AE260 + 2 * other), ram.u16(0x800AE484 + 2 * other),
         ram.u16(0x800AE6C0 + 2 * other)]
    if b[2] and a[0] == b[0] and a[1] == b[1]:
        if b[3] == 0 and a[3] != 0:
            b[1] = a[1] ^ 1 if a[1] < 2 else 0
        else:
            a[1] = b[1] ^ 1 if b[1] < 2 else 0
    ram.put(0x800AE224 + 2 * player, "H", a[0])
    ram.put(0x800AE260 + 2 * player, "H", a[1])
    ram.put(0x800AE484 + 2 * player, "H", 1)
    ram.put(0x800AE224 + 2 * other, "H", b[0])
    ram.put(0x800AE260 + 2 * other, "H", b[1])


def demo_fighters(ram: Ram) -> None:
    """FUN_800DB54C: the demonstration fight's two characters (next in the list, and a random other)."""
    total = sum(ss.usage(ram, c) for c in range(22)) & 0xFFFFFFFF
    chars = [ram.u8(DEMO_LIST + i) for i in range(14) if ram.u32(ss.UNLOCKED) >> (ram.u8(DEMO_LIST + i) & 31) & 1]
    n = len(chars)
    i = ram.u8(0x800982F3) + 1
    if n <= i:
        i = 0
    ram.put(0x800982F3, "B", i)
    costume = int(total & 0x200 != 0)
    ram.put(0x800A95F0, "H", 1)
    ram.put(0x800AE224, "H", chars[i])
    ram.put(0x800AE260, "H", costume)
    mirror_costumes(ram, 0)
    ram.put(0x800A95F2, "H", 1)
    r = ram.u32(0x800AE6E0) & 0xFFF
    q = r % (n - 1) if n > 1 else r                   # divu by zero leaves the dividend (one character)
    ram.put(0x800AE226, "H", chars[(q + i + 1) % n])
    ram.put(0x800AE262, "H", costume)
    mirror_costumes(ram, 1)


def replay_init(ram: Ram) -> None:
    """ReplayInit(0) (0x80031F60)."""
    ram.put(0x8009C040, "I", 0x17)
    if ram.u16(0x800AE6CC) == 6:
        ram.put(0x8009C050, "I", 0)


def music_stop(ram: Ram, mask: int) -> None:
    """FUN_8006C870: stop the music channels in `mask` (bits 0-4)."""
    for k in range(5):
        if mask >> k & 1:
            ram.put(0x800A0C40 + 2 * k, "H", 0xFFFF)
    if mask & 0xC:
        sound_slots_stop(ram, 3)


def sound_slots_stop(ram: Ram, mask: int) -> None:
    """FUN_80069ABC: stop the three effect slots in `mask` (-1 all)."""
    mask = ds._s32(mask)
    if ((mask & 1 and ram.u16(0x800A08B8) == 0xE) or (mask & 2 and ram.u16(0x800A08C0) == 0xE)) and \
            (ram.u16(0x800A9708) == 0x14 or ram.u16(0x800AAF94) == 0x14):
        music_stop(ram, 3)
    for k in range(3):
        if mask >> k & 1:
            ram.put(0x800A08B8 + 8 * k, "H", 0xFFFF)
            ram.put(0x800A08BA + 8 * k, "H", 0)
            ram.put(0x800A08BC + 8 * k, "I", 0)


def mode_start(ram: Ram, mode: int, players: int) -> None:
    """FUN_800DAF2C: set up the fight variables and per-mode feature bytes, then go to state 7."""
    music_stop(ram, 0x1F)
    sound_slots_stop(ram, -1)
    b, h, w = (lambda a, v: ram.put(a, "B", v)), (lambda a, v: ram.put(a, "H", v)), (lambda a, v: ram.put(a, "I", v))
    h(0x800AAF8E, 1)
    h(0x800AC81A, 1)
    h(0x800AAF9A, 1)
    h(0x800A9702, 0)
    h(0x800A970E, 0)
    h(0x800AC826, 2)
    for a in (0x800AFF69, 0x800AFF5F, 0x800AFF61, 0x800AFF62, 0x800AFF63):
        b(a, 0)
    for a in (0x800958D4, 0x800958D8, 0x800AFF74, 0x800AFF78, 0x800AFF7C, 0x800AFF80, 0x800AFF84):
        w(a, 0)
    h(0x800AE6DA, 0)
    h(0x800AE39C, 0)
    b(0x800AFF5D, ram.u8(0x800982EA))
    b(0x800AFF5E, ram.u8(0x800982F0))
    b(0x800AFF70, ram.u8(0x800982E7))
    h(0x800AE6D0, ram.u8(0x800982E6))
    h(0x800AE3C0, ram.u8(0x800982E8))
    h(0x800AFF20, ram.u8(0x800982E9))
    b(0x800AE6D9, 0)
    w(ss.MODE, mode)
    for p in range(2):
        ss.controller_setting(ram, p, ram.u8(0x800982EC + p))
        pad = ram.u16(ss.PAD_HELD + 2 * p)
        if pad & 0x800:
            b(0x800AFF5F, int(pad == 0x80C))
        ram.put(0x800A9AE4 + 0x188C * p, "I", 0)          # FUN_80051A98
        ram.put(0x800A9AEC + 0x188C * p, "I", 0)
        if ram.u8(0x800982F9) == 0:
            b(0x800982EE + p, 0x58)
        h(0x800AE224 + 2 * p, 0x16)
        h(0x800AE260 + 2 * p, 0)
        h(0x800AE484 + 2 * p, 0)
        h(0x800AE6C0 + 2 * p, 0)
    first = (players ^ 1) & 1
    b(0x800AE406, first)
    b(0x800B0A06, first + 1 & 1)
    b(0x800AE218, 0)
    h(0x800AE6C0 + 2 * first, 1)
    replay_init(ram)
    feats = {0: (1, 1, 0, 1, 0, 0, 0, 1, 0), 1: (1, 0, 0, 1, 1, 0, 1, 1, 1), 2: (1, 1, 1, 0, 1, 1, 1, 1, 1),
             3: (0, 0, 0, 0, 0, 0, 0, 1, 0), 4: (0, 0, 0, 1, 0, 1, 1, 1, 0), 5: (1, 0, 0, 0, 0, 0, 0, 1, 0),
             6: (0, 0, 0, 0, 0, 0, 1, 1, 0), 7: (1, 1, 0, 0, 1, 0, 0, 0, 1), 8: (1, 0, 0, 0, 0, 0, 0, 0, 0)}
    tail = True
    if mode in feats:
        for k, v in enumerate(feats[mode]):
            b(0x800AFF54 + k, v)
    if mode == 0:
        _clear_stage_records(ram)
    elif mode in (1, 7):
        if mode == 1:
            h(0x800AE6C2, 1)
            h(0x800AE6C0, 1)
        else:
            h(0x800AE3C0, 5)
            h(0x800AFF20, 0)
        b(0x800AFF8A, 3)
        b(0x800AFF8E, 3)
        w(0x800AFF90, ram.u16(0x800AFF92) << 16)
        h(0x800AFF88, 0)
        h(0x800AFF8C, 0)
        w(0x800AFF98, 0xFFFFFFFF)
        w(0x800AFF9C, 0xFFFFFFFF)
        w(0x800AFF94, 0xFFFFFFFF)
    elif mode == 2:
        b(0x800AFF70, 0)
        b(0x800AFFB5, 4)
        b(0x800AFFC2, 4)
        for k in range(22):
            h(0x800AFFEE - 2 * k, 0)
    elif mode == 3:
        b(0x800AFF5D, 0)
        h(0x800AE6D0, 1)
        b(0x800AFF70, 1)
        h(0x800AE3C0, 2)
        h(0x800AFF20, 0)
        _clear_stage_records(ram)
    elif mode == 4:
        h(0x800AE6D0, 1)
        b(0x800AFF70, 0)
        h(0x800AE3C0, 2)
        h(0x800AFF20, 0)
        w(0x800AFF90, 0)
        w(0x800AFF94, 0)
        w(0x800AFF98, 0)
        for k in range(22):
            h(0x800AFFDA - 2 * k, 0)
        w(0x800AFF9C, 0)
        for k in range(4):
            w(0x800AFFAC - 4 * k, 0x16)
    elif mode == 5:
        b(0x800AFF70, 0)
        h(0x800AE3C0, 5)
        w(0x800958D8, 1)
        h(0x800AFF20, 0)
        tail = False
    elif mode == 6:
        ss.controller_setting(ram, 0, 0)
        ss.controller_setting(ram, 1, 0)
        h(0x800AE3C0, 2)
        h(0x800AE39C, 1)
        demo_fighters(ram)
        tail = False
    elif mode == 8:
        h(0x800AE3C0, 4)
        b(0x800AFF70, 0)
        h(0x800AFF20, 0)
    else:
        tail = False
    if tail:
        ram.put(0x800984DC, "B", 2)                     # FUN_800519A4
    if ram.u16(0x800AE3C0) > 4:
        w(0x800958D4, 1)
    b(0x800AFF66, MODE_OVERLAY[mode] if 0 <= mode < 9 else 0)
    h(ss.GAME_STATE, 7)
    h(ss.SUB_STATE, 0)


def _clear_stage_records(ram: Ram) -> None:
    """FUN_80051644: meant to clear the ten stage records, clears only the first (game-bugs entry 34)."""
    ram.put(0x800AFF90, "I", 0)
    ram.put(0x800AFF96, "H", 0)
    ram.put(0x800AFF94, "B", 0)
    ram.put(0x800AFF95, "B", 0)


def goto_screen_loader(ram: Ram, target: int) -> None:
    """FUN_80050208: go to a state through the screen-overlay loader (state 18)."""
    ss.display_request(ram, 1)
    ram.put(0x80098319, "B", ram.u16(ss.GAME_STATE))
    ram.put(ss.GAME_STATE, "H", 0x12)
    ram.put(0x80098318, "B", target)
    ram.put(ss.SUB_STATE, "H", 0)


STR_COPYRIGHT, STR_RIGHTS = 0x800B9378, 0x800B93A0
START_PROMPTS = 0x80022328       # 4 x (string, half width): INSERT COIN, PUSH P1/P2 START, PUSH P1 AND/OR P2


def start_prompt(ram: Ram) -> None:
    """FUN_8004F0FC: the blinking start prompt for the connected controllers."""
    p0, p1 = pad_connected(ram, 0), pad_connected(ram, 1)
    if not ram.u32(ds.FRAME_COUNT) & 0x30:
        return
    hi, lo = max(p0, p1), min(p0, p1)
    i = 0 if hi < 1 else 3 if lo >= 1 else 2 if p1 >= 1 else 1
    e = START_PROMPTS + 8 * i
    ds.text(ram, ds.STR_COIN, 0xB8 - ram.u32(e + 4), 0x16C, 5, ram.u32(e))


def title_backdrop(ram: Ram, kind: int) -> None:
    """FUN_800DAAD8: the title/menu pictures. 0 black, 1/7 nothing, 2 title with start prompt,
    3 title with the PRESS START picture, 4 title, 5 the menu backdrop, 6 the options', other: black fade."""
    ot = ds.ot0(ram)
    if kind == 0:
        ds._set_pkt(ram, ds.tile(ram, ot, ds._pkt(ram), 0x60000000, 0, 0x1E00170))
        return
    if kind in (1, 7):
        return
    if kind == 2:
        start_prompt(ram)
    if kind in (2, 3):
        ds._set_pkt(ram, ds.image(ram, ot + 0x1C, ds._pkt(ram), 0x97, 0x184, 0x48, 0x10, 0x320, 0, 0x7820, 0))
    if kind in (2, 3, 4):
        ds.text(ram, STR_COPYRIGHT, 6, 0x2D, 0x19C)
        ds.text(ram, STR_RIGHTS, 6, 0x2D, 0x1B0)
        kind = 5
    if kind not in (5, 6):
        ds._set_pkt(ram, ds.fade(ram, ot + 0x1C, ds._pkt(ram), 0))
        return
    cluts = (0x7EA0, 0x7EE0, 0x7F20, 0x7F60, 0x7FA0, 0x7FE0) if kind == 5 else (0x7D20, 0x7D60, 0x7DA0, 0x7DE0, 0x7E20, 0x7E60)
    p = ds._pkt(ram)
    for (sx, sy, w_, h_, vx, vy), clut in zip(((0, 0, 0x80, 0x100, 0x200, 0), (0x80, 0, 0x80, 0x100, 0x240, 0),
                                               (0x100, 0, 0x70, 0x100, 0x280, 0), (0, 0x100, 0x80, 0xE0, 0x200, 0x100),
                                               (0x80, 0x100, 0x80, 0xE0, 0x240, 0x100),
                                               (0x100, 0x100, 0x70, 0xE0, 0x280, 0x100)), cluts):
        p = ds.image(ram, ot, p, sx, sy, w_, h_, vx, vy, clut, 0x80)
    ds._set_pkt(ram, p)


# ---- title sequence (game state 3) ----
TITLE_KIND = 0x800EB290          # the picture drawn this frame (title_backdrop kind)
TITLE_MOVIE = 0x800B09B8         # which opening movie (bit 0)
MOVIE_RESULT = 0x800EC570        # the movie player's last result (-1: skipped / failed)
TITLE_CYCLE = 0x8009831E         # attract cycle 0-3: 0/1 movie 0, 2 movie 1, 3 title only
STREAM_ACTIVE = 0x800A8B34       # FUN_8006C840: CD streaming busy
DEMO_ARCHIVE = 0x800D4FB8


class MovieStub:
    """The opening movie player (FUN_800E24F0 start, FUN_800E2510 one decoded frame: > 0 at the end,
    -1 when skipped). Played through the MDEC from the table in formats/sound-and-video.md; the
    verifier stubs it as a fixed result."""

    def __init__(self, cell: int = 0x801F800C) -> None:
        self.cell = cell

    def start(self, ram: Ram, which: int) -> None:
        pass

    def frame(self, ram: Ram) -> int:
        return ram.s32(self.cell)


MOVIE = MovieStub()


def next_title_cycle(ram: Ram) -> None:
    """FUN_8004FB58."""
    v = ram.u8(TITLE_CYCLE) + 1
    ram.put(TITLE_CYCLE, "B", 0 if v > 3 else v)


# ---- the title card of enbu.ovl (game state 6) ----
ENBU_KIND = 0x800DDE28           # enbu.ovl's title_backdrop kind (its FUN_800D2C30 is the same code)
ENBU_PACKETS = 0x8010A5FC        # + buffer * 0xF00


def enbu_frame(ram: Ram) -> int | None:
    """enbu.ovl FUN_800D3844 for sub-states 4-7: the title fades in from white (3 levels per
    frame), stays 300 frames with the start prompt, and fades to black (8 levels per frame).
    Start in any sub-state after 0 returns to the main menu. Sub-states 0-3 load the
    demonstration and 8 starts its fight (FightStart(6, 0)); they are not ported."""
    sub = ram.s16(ss.SUB_STATE)
    if sub > 0 and (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x800:
        next_title_cycle(ram)
        ss.controllers_reset(ram)
        ss.goto_transition(ram, 4)
        return 1
    timer = ram.s32(ss.STATE_TIMER)
    if sub == 4:
        ram.put(ENBU_KIND, "I", 5)
        timer = 0x100
        sub = 5
        ram.put(ss.SUB_STATE, "H", 5)
    if sub == 5:
        if timer < 1:
            ram.put(ss.STATE_TIMER, "i", 300)
            ram.put(ss.SUB_STATE, "H", 6)
        else:
            ram.put(ss.STATE_TIMER, "i", timer - 3)
            ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + 0xC, ds._pkt(ram), timer + 0xFD))
    elif sub == 6:
        ram.put(ENBU_KIND, "I", 2)
        ram.put(ss.STATE_TIMER, "i", timer - 1)
        if timer - 1 == 0:
            ram.put(ss.STATE_TIMER, "i", 0x100)
            ram.put(ss.SUB_STATE, "H", 7)
    elif sub == 7:
        if timer < 1:
            ram.put(ENBU_KIND, "I", 8)
            ram.put(ss.SUB_STATE, "H", 8)
        else:
            ram.put(ss.STATE_TIMER, "i", timer - 8)
            ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + 0x1C, ds._pkt(ram), timer - 8))
    else:
        raise NotImplementedError(f"enbu sub-state {sub}")
    saved = ds._pkt(ram)
    ds._set_pkt(ram, ENBU_PACKETS + 0xF00 * ram.u32(ds.DISPLAY_BUFFER) & 0xFFFFFFFF)
    title_backdrop(ram, ram.s32(ENBU_KIND))
    ds._set_pkt(ram, saved)
    return None


def title_sequence(ram: Ram) -> int | None:
    """FUN_800DB7D4 (game state 3): opening movie, white flash, title, then the demonstration fight.

    Start at any point goes to the main menu (returns 1)."""
    sub = ram.s16(ss.SUB_STATE)
    timer = ram.s32(ss.STATE_TIMER)
    fade = None                                          # (OT offset, level)
    if sub == 0:
        display_position(ram)                            # FUN_800DB6C0's border clears are VRAM only
        ram.put(MOVIE_RESULT, "I", 0)
        cycle = ram.u8(TITLE_CYCLE)
        if cycle == 3:
            ram.put(ss.SUB_STATE, "H", 3)
        else:
            ram.put(TITLE_MOVIE, "I", int(cycle == 2))
            ram.put(ss.SUB_STATE, "H", 1)
        ram.put(TITLE_KIND, "I", 8)
        ram.put(ss.STATE_TIMER, "i", 0)
    elif sub == 1:
        ram.put(TITLE_KIND, "I", 1)
        MOVIE.start(ram, ram.u32(TITLE_MOVIE) & 1)
        ram.put(ss.SUB_STATE, "H", 2)
    elif sub == 2:
        while True:
            r = MOVIE.frame(ram)
            ram.put(MOVIE_RESULT, "i", r)
            if r > 0:
                ram.put(ss.SUB_STATE, "H", 6)
            if ram.u32(STREAM_ACTIVE) == 0:
                break
    elif sub in (3, 4, 5):
        if sub == 3:
            ram.put(TITLE_KIND, "I", 0)
            timer = 0
            ram.put(ss.SUB_STATE, "H", 4)
        if sub != 5 and timer + 10 < 0x100:
            ram.put(ss.STATE_TIMER, "i", timer + 10)
            fade = (0xC, timer + 0x10A)
        else:
            if sub != 5:
                timer = 0
                ram.put(ss.SUB_STATE, "H", 5)
            ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + 0xC, ds._pkt(ram), 0x200))
            timer += 1
            ram.put(ss.STATE_TIMER, "i", timer)
            if timer >= 11:
                ram.put(ss.SUB_STATE, "H", 6)
    elif sub in (6, 7):
        if sub == 6:
            ram.put(TITLE_KIND, "I", 5)
            timer = 0x100
            ram.put(ss.SUB_STATE, "H", 7)
        if timer <= 0:
            ram.put(ss.STATE_TIMER, "i", 300)
            ram.put(ss.SUB_STATE, "H", 8)
        else:
            ram.put(ss.STATE_TIMER, "i", timer - 3)
            fade = (0xC, timer + 0xFD)
    elif sub == 8:
        ram.put(TITLE_KIND, "I", 2)
        ram.put(ss.STATE_TIMER, "i", timer - 1)
        if timer - 1 == 0:
            ram.put(ss.STATE_TIMER, "i", 0x100)
            ram.put(ss.SUB_STATE, "H", 9)
    elif sub == 9:
        if timer <= 0:
            ram.put(TITLE_KIND, "I", 8)
            ram.put(ss.SUB_STATE, "H", 10)
        else:
            ram.put(ss.STATE_TIMER, "i", timer - 8)
            fade = (0x1C, timer - 8)
    else:
        next_title_cycle(ram)                            # (loads the demonstration archive)
        ram.put(TITLE_KIND, "I", 8)
        mode_start(ram, 6, 0)
    if fade:
        ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + fade[0], ds._pkt(ram), fade[1]))
    if (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x800 or ram.s32(MOVIE_RESULT) == -1:
        next_title_cycle(ram)
        ss.controllers_reset(ram)
        ss.goto_transition(ram, 4)
        return 1
    saved = ds._pkt(ram)
    ds._set_pkt(ram, MENU_PACKETS + ram.u32(ds.DISPLAY_BUFFER) * 0x3C00)
    title_backdrop(ram, ram.u32(TITLE_KIND))
    ds._set_pkt(ram, saved)
    return None


# ---- transition screen (game state 2) ----
TARGET, PREVIOUS, ENBU_TARGET, ENBU_CACHED, CACHE = 0x80098318, 0x80098319, 0x8009831A, 0x8009831B, 0x8009831C
CARD_READ = 0x8009831D           # the start-up memory card read has been done
SAVE_ERROR = 0x800AE429          # frames left of AUTO SAVE ERROR!
STR_PRESENTS, STR_SAVE_ERROR = 0x80022678, 0x80021C48


class LoaderStub:
    """The overlay loader as the transition screen uses it: FUN_80052D58 (non-zero while loading),
    LoadOverlayAsync (queue a load), and the overlay set-up calls after loading (title.ovl
    FUN_800DB748 uploads; enbu.ovl FUN_800D3C20 uploads and FUN_800D3CA8 set-up)."""

    def __init__(self, cell: int = 0x801F8014) -> None:
        self.cell = cell

    def busy(self, ram: Ram) -> int:
        return ram.u32(self.cell)

    def queue(self, ram: Ram, which: int) -> None:
        pass

    def enbu_uploads(self, ram: Ram) -> None:
        pass

    def enbu_setup(self, ram: Ram) -> None:
        pass


LOADER = LoaderStub()


def title_uploads(ram: Ram) -> None:
    """FUN_800DB748: the title pictures (VRAM uploads, not ported) inside a draw hold."""
    ss.draw_hold(ram, 1)
    ss.draw_hold(ram, 0)


def auto_save(ram: Ram) -> None:
    """AutoSave (0x8004C6A0): write the save when AUTO SAVE is on and something changed."""
    if ram.u8(AUTO_SAVE) and ram.u8(ss.SAVE_PENDING):
        ram.put(SAVE_ERROR, "B", 0 if CARD.write(ram) == 0 else 0x78)
    ram.put(ss.SAVE_PENDING, "B", 0)


def auto_save_error(ram: Ram) -> int:
    """AutoSaveErrorShow (0x8004C758): 120 frames of a blinking AUTO SAVE ERROR! on black."""
    t = ram.u8(SAVE_ERROR)
    if t == 0:
        return 0
    ram.put(SAVE_ERROR, "B", t - 1)
    ds.text(ram, STR_SAVE_ERROR, 2 if ram.u32(ds.FRAME_COUNT) & 2 else 10, 1, 0x50, 0xF0)
    ds._set_pkt(ram, ds.tile(ram, ds.ot0(ram) + 0x1C, ds._pkt(ram), 0x60000000, 0, 0x1E00170))
    return 1


def presents_draw(ram: Ram, mode: int, level: int) -> None:
    """FUN_8004FA38: 0 NAMCO PRESENTS with a fade (level 0-0xFF), 1 NAMCO PRESENTS, 2 black, other nothing."""
    if mode not in (0, 1, 2):
        return
    if mode != 2:
        if mode == 0 and level < 0x100:
            v = 0xFF - level & 0xFFFFFFFF
            ot = ds.ot0(ram) + 0x1C
            p = ds.tile(ram, ot, ds._pkt(ram), v | v << 8 | v << 16 | 0x62000000, 0xF00075, 0x120087)
            ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0x40))
        ds.text(ram, STR_PRESENTS, 2, 0, 0x75, 0xF0, 6)
    ds._set_pkt(ram, ds.tile(ram, ds.ot0(ram), ds._pkt(ram), 0x60000000, 0, 0x1E00170))


def _queue_menu_overlay(ram: Ram) -> None:
    if ram.u8(CACHE) == 0:
        LOADER.queue(ram, 7 if ram.u8(ENBU_TARGET) else 5)
        ram.put(CACHE, "B", 0)


def _overlay_loaded(ram: Ram) -> bool:
    """Steps 3/8: after the load, the overlay's uploads (cache 2). False while still loading."""
    if ram.u8(CACHE) == 0:
        if LOADER.busy(ram):
            return False
        if ram.u8(ENBU_TARGET) == 0:
            title_uploads(ram)
        else:
            LOADER.enbu_uploads(ram)
        ram.put(CACHE, "B", 2)
    return True


def _overlay_ready(ram: Ram) -> bool:
    """Steps 4/9: enbu's set-up once loaded (cache 3)."""
    if ram.u8(CACHE) < 3:
        if ram.u8(ENBU_TARGET):
            if LOADER.busy(ram):
                return False
            LOADER.enbu_setup(ram)
        ram.put(CACHE, "B", 3)
    return True


def transition_screen(ram: Ram, level: int = 0) -> int | None:
    """TransitionScreen (0x8004FD48, game state 2). `level` stands for the caller's s3, which the
    game passes to the draw unset outside the fades (only read by mode 0)."""
    sub = ram.s16(ss.SUB_STATE)
    if ram.u8(CARD_READ) and 5 < sub < 11 and (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x800:
        ss.goto_transition(ram, 4)
        return 1
    mode = 3
    timer = ram.s32(ss.STATE_TIMER)
    if sub == 0:
        # FightAllocBuffers(0) resets the fight heap here (memory-map.md; not ported)
        ram.put(0x80095850, "I", 1)                        # FUN_80029860(0)
        ram.put(0x800AE39C, "H", 1)
        if (ram.u8(PREVIOUS) - 2) & 0xFFFFFFFF >= 4 or ram.u8(CACHE) >= 4:
            ram.put(CACHE, "B", 0)
        if ram.u8(ENBU_TARGET) != ram.u8(ENBU_CACHED):
            ram.put(CACHE, "B", 0)
            ram.put(ENBU_CACHED, "B", ram.u8(ENBU_TARGET))
        ram.put(ss.SUB_STATE, "H", 5)
        t = ram.u8(TARGET)
        if t != 6 and (t != 3 or ram.u8(TITLE_CYCLE) == 3):
            ram.put(ss.SUB_STATE, "H", 1)
    elif sub in (1, 2, 3, 4):
        if sub == 1:
            _queue_menu_overlay(ram)
            ram.put(ss.SUB_STATE, "H", 2)
        if sub <= 2:
            auto_save(ram)
            ram.put(ss.SUB_STATE, "H", 3)
        if sub <= 3:
            if not _overlay_loaded(ram):
                return _presents_end(ram, 3, level)
            ram.put(ss.SUB_STATE, "H", 4)
        if _overlay_ready(ram):
            ram.put(ss.SUB_STATE, "H", 0xC)
    elif sub in (5, 6):
        if sub == 5:
            _queue_menu_overlay(ram)
            timer = 0
            ram.put(ss.SUB_STATE, "H", 6)
        level = ds._s32(timer << 3)
        timer += 1
        ram.put(ss.STATE_TIMER, "i", timer)
        mode = 0
        if timer > 0x20:
            mode = 1
            ram.put(ss.SUB_STATE, "H", 7)
            ram.put(ss.STATE_TIMER, "I", ram.u32(ds.FRAME_COUNT))
    elif sub in (7, 8, 9):
        mode = 1
        if sub == 7:
            if ram.u8(CARD_READ) == 0:
                CARD.load(ram)                               # FUN_8004C658: read the save at start-up
                ram.put(CARD_READ, "B", 1)
            else:
                auto_save(ram)
            ram.put(ss.SUB_STATE, "H", 8)
        if sub <= 8:
            if not _overlay_loaded(ram):
                return _presents_end(ram, 1, level)
            ram.put(ss.SUB_STATE, "H", 9)
        if _overlay_ready(ram) and (ram.u32(ds.FRAME_COUNT) - ram.u32(ss.STATE_TIMER)) & 0xFFFFFFFF > 0x5A:
            ram.put(ss.STATE_TIMER, "i", 0x20)
            ram.put(ss.SUB_STATE, "H", 10)
    elif sub == 10:
        level = ds._s32(timer << 3)
        timer -= 1
        ram.put(ss.STATE_TIMER, "i", timer)
        mode = 0
        if timer < 1:
            ram.put(ss.STATE_TIMER, "i", 0)
            ram.put(ss.SUB_STATE, "H", 0xB)
            mode = 2
    elif sub in (11, 12):
        if sub == 11:
            mode = 2
            ram.put(ss.SUB_STATE, "H", 0xC)
        if auto_save_error(ram):
            return 1
        ram.put(ss.SUB_STATE, "H", 0)
        ram.put(ss.GAME_STATE, "H", ram.u8(TARGET))
    return _presents_end(ram, mode, level)


def _presents_end(ram: Ram, mode: int, level: int) -> None:
    presents_draw(ram, mode, level)
    return None


def main_menu(ram: Ram) -> None:
    """FUN_800DBBD0 (game state 4)."""
    pressed = ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)
    rep = ram.u16(ss.PAD_REPEAT) | ram.u16(ss.PAD_REPEAT + 2)
    one_pad = pad_connected(ram, 0) == 0 or pad_connected(ram, 1) == 0
    sub = ram.u16(ss.SUB_STATE)
    if sub == 1:
        timer = ram.s32(ss.STATE_TIMER) + 1
        ram.put(ss.STATE_TIMER, "i", timer)
        if timer < 0x1E1:
            cur = ram.u8(MENU_CURSOR)
            step = (rep >> 14 & 1) - (rep >> 12 & 1)
            count = ram.u32(MENU_COUNT)
            if count <= cur:
                cur = 0
            while True:
                nxt = (cur + step) & 0xFFFFFFFF
                if count <= nxt:
                    nxt = (count - (cur + 1)) & 0xFFFFFFFF
                ram.put(MENU_SCROLL, "i", ram.s32(MENU_SCROLL) + step * 0x1C)
                if ram.u8(MENU_LIST + 8 * nxt + 5) != 1 or not one_pad:
                    break
                cur = nxt
                if step == 0:
                    step = 1
            ram.put(MENU_CURSOR, "B", nxt)
            if step:
                ram.put(ss.STATE_TIMER, "i", 8)
            if pressed & 0x8F0:
                ram.put(MENU_CHOSEN, "I", 1)
                ram.put(MENU_SCROLL, "I", 0)
                ram.put(MENU_GLOW, "I", 0x100)
                players = int(ram.u16(ss.PAD_PRESSED) & 0x8F0 != 0)
                if ram.u16(ss.PAD_PRESSED + 2) & 0x8F0:
                    players |= 2
                ram.put(MENU_PLAYERS, "I", players)
                ram.put(ss.SUB_STATE, "H", 2)
        else:
            ram.put(ss.SUB_STATE, "H", 3)
            ram.put(MENU_CHOSEN, "I", 1)
    elif sub == 0:
        display_position(ram)
        ss.controllers_reset(ram)
        ss.draw_hold(ram, 1)
        ss.draw_hold(ram, 0)
        ram.put(0x800AE6C2, "H", 0)
        ram.put(0x800AE6C0, "H", 0)
        button_map(ram, 0)
        button_map(ram, 1)
        count = 0
        ram.put(MENU_CHOSEN, "I", 0)
        for i in range(10):
            src, dst = MENU_ENTRIES + 8 * i, MENU_LIST + 8 * count
            ram.put(dst, "I", ram.u32(src))
            ram.put(dst + 4, "I", ram.u32(src + 4))
            ram.put(dst + 7, "B", 0)
            mode = ram.u8(src + 4)
            v = ram.u8(0x80098306) if mode == 7 else ram.u8(0x80098307) if mode == 10 else 3
            if v:
                if v < 3:
                    ram.put(dst + 7, "B", 1)
                count += 1
        ram.put(MENU_COUNT, "I", count)
        if ram.u8(MENU_TO_OPTIONS):
            ram.put(MENU_TO_OPTIONS, "B", 0)
            i = 0
            while i < count and ram.u8(MENU_LIST + 8 * i + 4) != 9:
                i += 1
            ram.put(MENU_CURSOR, "B", 0 if i > 10 else i)
        ram.put(ss.STATE_TIMER, "i", 0)
        ram.put(MENU_SCROLL, "I", 0)
        ram.put(MENU_GLOW, "I", 0)
        ram.put(ss.SUB_STATE, "H", 1)
    elif sub == 2:
        mode = ram.u8(MENU_LIST + 8 * ram.u8(MENU_CURSOR) + 4)
        if mode == 9:
            ss.goto_transition(ram, 5)
        elif mode == 10:
            if ram.u8(ss.THEATER_NEW) < 3:
                ram.put(ss.THEATER_NEW, "B", ram.u8(ss.THEATER_NEW) + 1)
            ram.put(0x800AE3D8, "H", 0)
            goto_screen_loader(ram, 0x13)
        else:
            if mode == 7 and ram.u8(ss.BALL_NEW) < 3:
                ram.put(ss.BALL_NEW, "B", ram.u8(ss.BALL_NEW) + 1)
            mode_start(ram, mode, ram.u32(MENU_PLAYERS))
    elif sub == 3:
        ss.goto_transition(ram, 3)
    _main_menu_draw(ram)


def _main_menu_draw(ram: Ram) -> None:
    saved = ds._pkt(ram)
    ds._set_pkt(ram, MENU_PACKETS + ram.u32(ds.DISPLAY_BUFFER) * 0x3C00)
    ot = ds.ot_text(ram)
    p = ds.draw_area_xywh(ram, ot, ds._pkt(ram), 0, 0, 0x170, 0x1E0)
    p = ds.poly_g4(ram, ot, p, 0x3AE0E0E0, 0xE0E0E0, 0, 0, 0x13C0044, 0x13C012C, 0x1580044, 0x158012C)
    p = ds.poly_g4(ram, ot, p, 0x3A000000, 0, 0xF8F8F8, 0xF8F8F8, 0x1940044, 0x194012C, 0x1B00044, 0x1B0012C)
    ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0x40))
    v = ram.s32(MENU_SCROLL)
    n = 0
    if v:
        neg = v < 0
        v = abs(v)
        n = v - (v + 3 >> 2)
        if n < 1:
            n = 0
        if neg:
            n = -n
    count = ram.u32(MENU_COUNT)
    cur = ram.u8(MENU_CURSOR)
    idx = (cur - 3 + count) & 0xFFFFFFFF if cur < 3 else cur - 3
    ram.put(MENU_SCROLL, "i", n)
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    y = n + 0x116
    for _ in range(7):
        idx %= count
        e = MENU_LIST + 8 * idx
        ds.strcpy(ram, tail, ram.u32(e))
        width = ds.strlen(ram, tail)
        col = ram.u8(e + 6)
        if ram.u32(MENU_CHOSEN) == 0 and ram.u8(e + 7) and ram.u32(ds.FRAME_COUNT2) & 3 == 0:
            col = 0xE
        ds.text(ram, ds.SCRATCH, col, 1, 0xB8 - (width * 0xD >> 1), y)
        idx += 1
        y += 0x1C
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ot, ds._pkt(ram), 0x30, 0x13C, 0x140, 0x74))
    if ram.s32(MENU_SCROLL) == 0:
        g = min(ram.s32(MENU_GLOW) + 0x18, 0x100)
        ram.put(MENU_GLOW, "i", g)
        c, f = ds.scale_colour(0xC0C0C0, g), ds.scale_colour(0xF8F8F8, g)
        o8 = ds.ot0(ram) + 8
        p = ds._pkt(ram)
        for args in ((0x38000000, f, 0, f, 0x1680000, 0x16800B8, 0x16A0000, 0x16A00B8),
                     (f | 0x38000000, 0, f, 0, 0x16800B8, 0x1680170, 0x16A00B8, 0x16A0170),
                     (0x38000000, f, 0, f, 0x1820000, 0x18200B8, 0x1840000, 0x18400B8),
                     (f | 0x38000000, 0, f, 0, 0x18200B8, 0x1820170, 0x18400B8, 0x1840170),
                     (0x38000000, c, 0, c, 0x1680008, 0x16800B8, 0x1840008, 0x18400B8),
                     (c | 0x38000000, 0, c, 0, 0x16800B8, 0x1680168, 0x18400B8, 0x1840168)):
            p = ds.poly_g4(ram, o8, p, *args)
        ds._set_pkt(ram, p)
    else:
        ram.put(MENU_GLOW, "I", 0)
    title_backdrop(ram, 5)
    ds._set_pkt(ram, saved)


# ---- options (game state 5) ----
OPT_PAGE = 0x800EC5E8            # u8: the page shown (0 main list .. 5 display adjust, 6 = leave)
OPT_PAGES = 0x800EB2F0           # 6 page records, 0x34 bytes each (see modes.md)
OPT_PAGE_SIZE = 0x34
OPT_MODES_SRC, OPT_MODES, OPT_MODES_COUNT = 0x800EB45C, 0x800EC5F8, 0x800EC638   # mode icons (mode, uv|clut)
KEY_CONFIG = 0x800EC640          # 2 key-configuration records, 0x1E8 bytes each
KEY_CONFIG_SIZE = 0x1E8
KEY_ROWS_SRC = 0x800EB4D8        # 8 rows x 0x18 bytes
COLOUR_SCHEME = 0x800982EB       # titles in colour 1 when set, else 6 (L1+R1+Select+Start... toggles it)
DISPLAY_X, DISPLAY_Y = 0x80098304, 0x80098305
SCREEN_RECT = 0x800AE6F8
OPT_ARROWS = (0x7ED4E060, 0x7ED5E06C, 0x7ED6E078, 0x7ED7E084)   # pad button pictures (uv|clut)
STR_ADJUST, STR_DEFAULT, STR_EXIT = 0x800B9A78, 0x800B9A90, 0x800B9AB0
STR_1D, STR_2D = 0x800B98D4, 0x800B98D8            # "%1d", "%2d": numeric option values
SND_MOVE, SND_OK, SND_DEFAULT = 0x546C, 0x4CEB, 0x4D87


def _title_colour(ram: Ram) -> int:
    return 1 if ram.u8(COLOUR_SCHEME) else 6


def display_position(ram: Ram) -> None:
    """FUN_800DAED0: the display position from the display-adjust bytes (with FUN_8002980C)."""
    ram.put(0x800AE2DC, "H", 0x102)
    ram.put(0x800AE2DE, "H", 0xF0)
    ram.put(0x800AE2D8, "H", ram.s8(DISPLAY_X) & 0xFFFF)
    ram.put(0x800AE2DA, "H", ram.s8(DISPLAY_Y) & 0xFFFF)
    ram.put(0x80095854, "I", ram.u32(0x8009585C + 4 * min(ram.u8(DISPLAY_Y), 7)))


def _option_modes(ram: Ram) -> None:
    """The mode icons of the game-option page; Tekken Ball's (mode 7) only once it is unlocked."""
    n = 0
    for i in range(8):
        src, dst = OPT_MODES_SRC + 8 * i, OPT_MODES + 8 * n
        ram.put(dst, "I", ram.u32(src))
        ram.put(dst + 4, "I", ram.u32(src + 4))
        if ram.u32(src) != 7 or ram.u8(ss.BALL_NEW):
            n += 1
    ram.put(OPT_MODES_COUNT, "I", n)


def key_config_init(ram: Ram) -> None:
    """FUN_800DF9EC: both key-configuration records, and the input maps from the button layouts."""
    for p in range(2):
        rec = KEY_CONFIG + KEY_CONFIG_SIZE * p
        for off, v in ((0, p), (4, 0), (8, 0), (0x14, p * 0xB8), (0x18, 0), (0xC, 0), (0x10, 0)):
            ram.put(rec + off, "I", v)
        for i in range(8):
            src, e = KEY_ROWS_SRC + 0x18 * i, rec + 0x28 + 0x38 * i
            ram.put(e, "I", 0)
            ram.put(e + 0xC, "I", 0)
            ram.put(e + 8, "I", ram.u16(src))
            ram.put(e + 4, "I", ram.u8(src + 2))
            ram.put(e + 0x10, "I", ram.u8(src + 3))
            for k in range(8):
                ram.put(e + 0x14 + 4 * k, "I", ram.u16(src + 4 + 2 * k))
            ram.put(e + 0x34, "I", ram.u32(src + 0x14))
        button_map(ram, p)


def _cycle(v: int, step: int, n: int) -> int:
    """The options' wrap: past the end gives n - (v + 1) (so the last from the first, the first from the last)."""
    t = (v + step) & 0xFFFFFFFF
    return t if t < n else (n - (v + 1)) & 0xFFFFFFFF


def option_list_input(ram: Ram, rec: int) -> None:
    """FUN_800DCE20: cursor, value changes and actions of an option list page."""
    rep = ram.u16(ss.PAD_REPEAT) | ram.u16(ss.PAD_REPEAT + 2)
    pressed = ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)
    step = (rep >> 14 & 1) - (rep >> 12 & 1)
    lr = (rep >> 13 & 1) - (rep >> 15)
    cur = _cycle(ram.u32(rec), step, ram.u32(rec + 0x28))
    ram.put(rec, "I", cur)
    items = ram.u32(rec + 0x20)
    e = items + 0x14 * cur
    kind = ram.u8(e + 0xC)
    if kind in (1, 2):
        v = _cycle(ram.u8(ram.u32(e)), lr, ram.u8(e + 0xD))
        if kind == 2 and lr and v & 0xFF:
            ram.put(rec + 4, "I", 3)                     # auto save on: the memory-card check
        else:
            ram.put(ram.u32(e), "B", v)
    e = items + 0x14 * ram.u32(rec)
    act = ram.u8(e + 0xE)
    if act == 1 and pressed & 0x8F0:
        ram.put(ram.u32(e), "B", ram.u8(e + 0xF))
    elif act == 2:
        if pressed & 0x8F0:
            ram.put(ram.u32(e), "B", ram.u8(e + 0xF))
        if ram.u16(ss.PAD_HELD) | ram.u16(ss.PAD_HELD + 2) == 0x103 and pressed == 0x100:
            ram.put(COLOUR_SCHEME, "B", ram.u8(COLOUR_SCHEME) + 1 & 1)
    elif act == 3 and pressed & 0x8F0:
        ram.put(rec + 4, "I", ram.u32(rec) + 1)
    if ram.u8(rec + 0x30) == 1 and pressed & 0x100:
        ram.put(ram.u32(rec + 0x2C), "B", ram.u8(rec + 0x31))


def _option_glow(ram: Ram, x: int, y: int, w: int, pulse: int) -> None:
    """FUN_800DC838: the cursor bar behind an option."""
    c = 0xFF4020
    if pulse:
        c = ds.scale_colour(0xFF4020, (ds.triangle_wave(ram.u32(ds.FRAME_COUNT) << 4) >> 1) + 0x80)
    ds._set_pkt(ram, ds.tile(ram, ds.ot0(ram) + 0x10, ds._pkt(ram), c | 0x60000000,
                             (x - 3) & 0xFFFF | (y - 3) << 16 & 0xFFFFFFFF, (w + 6) & 0xFFFF | 0x160000))


def option_list_draw(ram: Ram, rec: int) -> None:
    """FUN_800DCA90: the page title and its items (label, value right-aligned in the value column)."""
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    if ram.u32(rec + 0x24):
        ds.strcpy(ram, tail, ram.u32(rec + 0x24))
        ds.text(ram, ds.SCRATCH, _title_colour(ram), 1, ram.u32(rec + 8), ram.u32(rec + 0xC))
    y, x = ram.s32(rec + 0x14), ram.s32(rec + 0x10)
    col_w = ram.s32(rec + 0x1C)
    for i in range(max(ram.s32(rec + 0x28), 0)):
        e = ram.u32(rec + 0x20) + 0x14 * i
        v = ram.u8(ram.u32(e))
        col = 10
        if i == ram.u32(rec):
            col = 5
            w = ds.strlen(ram, ram.u32(e + 4)) * 9 if ram.u16(e + 0x10) == 1 else col_w
            _option_glow(ram, x, y, w, 1)
        vcol = 1 if ram.u8(e + 0xC) and ram.u8(e + 0xF) == ram.u8(ram.u32(e)) else 6
        tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
        ds.strcpy(ram, tail, ram.u32(e + 4))
        dk = ram.u16(e + 0x10)
        if dk == 1:
            ds.text(ram, ds.SCRATCH, col, 0, x, y)
        elif dk in (2, 3, 4):
            ds.text(ram, ds.SCRATCH, col, 0, x, y)
            if dk == 2:
                ds.strcpy(ram, tail, ram.u32(ram.u32(e + 8) + 4 * v))
                vx = x + col_w - ds.strlen(ram, tail) * 9
            else:
                ds.strcpy(ram, tail, STR_1D if dk == 3 else STR_2D)
                vx = x + col_w - (9 if dk == 3 else 0x12)
            ds.text(ram, ds.SCRATCH, vcol, 0, vx, y, v)
        y += ram.s32(rec + 0x18)


def option_mode_icons(ram: Ram, mask: int) -> None:
    """FUN_800DC914: the modes an option applies to (greyed when the mask bit is clear)."""
    ot = ds.ot0(ram) + 0x1C
    p = ds._pkt(ram)
    n = ram.u32(OPT_MODES_COUNT)
    y = 0x2A
    for i in range(n):
        uv = ram.u32(OPT_MODES + 8 * i + 4)
        if not mask >> (ram.u32(OPT_MODES + 8 * i) & 31) & 1:
            uv = uv & 0xFFFF | 0x7E5E0000
        p = ds.sprt(ram, ot, p, 0x64808080, y << 16 | 0xF7, 0xE0060, uv)
        y += 0xE
    p = ds.tile(ram, ot, p, 0x60000000, 0x2A00F7, (n * 0xE0000 | 0x60) & 0xFFFFFFFF)
    p = ds.tile(ram, ot, p, 0x60C0C0C0, 0x2800F6, ((n * 0xE + 4) << 16 | 0x62) & 0xFFFFFFFF)
    ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0xB))


def pad_pictures(ram: Ram, x: int, y: int) -> None:
    """FUN_800DC6B4: the four face-button pictures of the display-adjust help line."""
    for dx, uv in zip((0, 0x12, 0x24, 0x50), OPT_ARROWS):
        ot = ds.ot0(ram) + 0x10
        p = ds.sprt(ram, ot, ds._pkt(ram), 0x65000000, (x + dx) & 0xFFFF | y << 16 & 0xFFFFFFFF, 0x14000C, uv)
        ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0x1F))


def display_adjust(ram: Ram) -> None:
    """FUN_800DE04C: move the picture with the pad (x -6..14, y 0..8); Start restores (-2, 0)."""
    display_position(ram)
    pressed = ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)
    rep = ram.u16(ss.PAD_REPEAT) | ram.u16(ss.PAD_REPEAT + 2)
    if pressed & 0x1F0:
        ram.put(OPT_PAGE, "B", 0)
    lr = (rep >> 13 & 1) - (rep >> 15)
    ud = (rep >> 14 & 1) - (rep >> 12 & 1)
    x0, y0 = ram.s8(DISPLAY_X), ram.s8(DISPLAY_Y)
    x = min(max(x0 + lr, -6), 14)
    y = min(max(y0 + ud, 0), 8)
    if pressed == 0x800:
        x, y = -2, 0
    ram.put(DISPLAY_X, "B", x & 0xFF)
    ram.put(DISPLAY_Y, "B", y & 0xFF)
    off = -(-x * 0x5B >> 6) if x < 0 else x * 0x5B + 0x3F >> 6
    dy = 2 * y0                                          # the text follows the previous frame's y
    ds.text(ram, STR_ADJUST, _title_colour(ram), 1, 0x5B - off, 0x28 - dy)
    ds.text(ram, STR_DEFAULT, 0, 0x22 - off, 0x17A - dy, 2, 6)
    ds.text(ram, STR_EXIT, 0, 0x22 - off, 0x19E - dy, 5, 6)
    pad_pictures(ram, 0x9F - off, 0x19C - dy)
    sx, sy = ram.s16(SCREEN_RECT), ram.s16(SCREEN_RECT + 2)
    sw, sh = ram.s16(SCREEN_RECT + 4), ram.s16(SCREEN_RECT + 6)
    cx, cy = sx + (sw >> 1), sy + (sh >> 1)
    hx, vy = (cx - 0x2E) & 0xFFFF, (cy - 0x50) << 16
    ot = ds.ot0(ram)
    p = ds._pkt(ram)
    for xy, wh in (((sx + 6) & 0xFFFF | vy, 0xA00002), (hx | (sy + 10) << 16, 0x3005C),
                   ((sw + sx - 8) & 0xFFFF | vy, 0xA00002), (hx | (sh + sy - 0xD) << 16, 0x3005C),
                   ((cx - 1) & 0xFFFF | vy, 0xA00002), (hx | (cy - 1) << 16, 0x3005C)):
        p = ds.tile(ram, ot, p, 0x60E0E0E0, xy & 0xFFFFFFFF, wh)
    ds._set_pkt(ram, p)


# ---- key configuration (options page 4) ----
KEY_NAMES = 0x800EB49C           # 13 action names (string pointers)
KEY_LINE_ENDS = 0x800B9B84       # per pad layout (analog 9 / other) x 8 rows: u16 x, y of the pointer line's end
VIBRATION_WORDS = 0x800EB4D0     # " NO", "YES"
DEFAULT_LAYOUT = 0x800B9B1C
STR_KEY_ITEM, STR_SETTING, STR_VIBRATION = 0x800B9B74, 0x800B9BC4, 0x800B9BDC
STR_KEY_DEFAULT, STR_KEY_EXIT, STR_KEY_TITLE = 0x800B9BF8, 0x800B9C08, 0x800B9C18
VIBRATION = 0x800982EC           # per player: 1 = on
VIBRATE_SLOTS = 0x80010050       # per vibration pattern: the slot it plays in (4 or more: none)


def pad_vibrate(ram: Ram, player: int, pattern: int) -> None:
    """PadVibrate (0x80029114) for one player."""
    slot = ram.u8(VIBRATE_SLOTS + pattern)
    if slot < 4:
        ram.put(0x8009BDE8 + 8 * player + 2 * slot, "H", pattern)


def _lerp8(a: int, b: int, k: int) -> int:
    """a moved k/8 of the way to b (truncating toward a)."""
    return a + ((b - a) * k >> 3) if a < b else a - ((a - b) * k >> 3)


def key_item(ram: Ram, x: int, y: int, item: int, layer: int, selected: int, used: int) -> None:
    """FUN_800DE838: one action name of a button's list (grey when another button has it)."""
    if item >= 0xD:
        return
    col = 5 if selected else 10 if used >> (item & 31) & 1 else 6
    ot = ds.ot0(ram) + 4 * layer
    if item in (10, 11):
        uv = (col | 0x7E10) << 16 | (0x8A if item == 11 else 0x80)
        p = ds.sprt(ram, ot, ds._pkt(ram), 0x65000000, (x + 8) & 0xFFFF | (y + 3) << 16 & 0xFFFFFFFF, 0x10000A, uv)
        ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0xB))
    name = ram.u32(KEY_NAMES + 4 * item)
    ds.text(ram, STR_KEY_ITEM, layer, col, 0, x - ((ds.strlen(ram, name) * 9 >> 1) - 0x20), y + 3, name)
    if selected:
        c = ds.scale_colour(0xFF4020, (ds.triangle_wave(ram.u32(ds.FRAME_COUNT) << 4) >> 1) + 0x80)
        ds._set_pkt(ram, ds.tile(ram, ot, ds._pkt(ram), c | 0x60000000,
                                 (x + 1) & 0xFFFF | (y + 2) << 16 & 0xFFFFFFFF, 0x12003E))


def key_row_draw(ram: Ram, rec: int, row: int) -> None:
    """FUN_800DEA48: a button's box: closed it shows the action, open (state 1/2) the whole list."""
    w = lambda i: ram.s32(row + 4 * i)
    state = w(0)
    if state == 0:
        layer, open_ = w(4), 0
    elif state in (1, 2):
        layer, open_ = 4, 1
    else:                                            # 3 (the game leaves s7/a2 unset beyond 0..3)
        layer, open_ = 3, 0
    player = ram.u32(rec)
    k = w(3)
    rx, ry = ram.s32(rec + 0x14), ram.s32(rec + 0x18)
    used = ram.u32(rec + 0x24)
    cur = ram.u8(0x80098308 + 8 * player + w(1))
    x = rx + _lerp8(w(5), w(7), k)
    if open_:
        for i in range(0xD):
            ds_y = ry + _lerp8(w(6), w(8) + 0x12 * i, k)
            key_item(ram, x, ds_y, i, layer + (i == cur), int(i == cur), used)
    else:
        key_item(ram, x, ry + _lerp8(w(6), w(8) + cur * 0x12, k), cur, layer, 0, 0)
    by = ry + _lerp8(w(6), w(8), k)
    h = 0xD8 * k >> 3
    colour = ram.u32(row + 0x34)
    ot = ds.ot0(ram) + 4 * layer
    p = ds.tile(ram, ot, ds._pkt(ram), 0x60000000, (x + 1) & 0xFFFF | (by + 2) << 16 & 0xFFFFFFFF, (h + 0x12) << 16 | 0x3E)
    p = ds.tile(ram, ot, p, colour | 0x60000000, x & 0xFFFF | by << 16 & 0xFFFFFFFF, (h + 0x16) << 16 | 0x40)
    lx = x + _lerp8(w(9), w(11), k)
    ly = (by + _lerp8(w(10), w(12), k)) << 16 & 0xFFFFFFFF
    end = KEY_LINE_ENDS + (0x20 if ram.u32(rec + 0x10) != 9 else 0) + 4 * w(1)
    tip = (ram.u16(end) + rx) & 0xFFFF | (ram.u16(end + 2) + ry) << 16 & 0xFFFFFFFF
    p = ds.line_f2(ram, ot, p, colour | 0x40000000, (lx + 2) & 0xFFFF | ly, tip)
    ds._set_pkt(ram, ds.poly_f3(ram, ot, p, colour | 0x20000000, lx & 0xFFFF | ly, (lx + 5) & 0xFFFF | ly, tip))


def key_row_input(ram: Ram, rec: int, row: int) -> None:
    """FUN_800DEF98: holding the row's button opens its list (8 frames); up/down picks the action."""
    player = ram.u32(rec)
    k = ram.s32(row + 0xC)
    if ram.u32(rec + 0x1C) & ram.u32(row + 8):
        k += 1
        state = 1 if k < 9 else 2
        k = min(k, 8)
    else:
        k -= 1
        state = 3 if k > 0 else 0
        k = max(k, 0)
    ram.put(row + 0xC, "i", k)
    ram.put(row, "I", state)
    if k:
        ram.put(rec + 0xC, "I", 1)
    slot = 0x80098308 + 8 * player + ram.u32(row + 4)
    if state == 2:
        rep = ram.u32(rec + 0x20)
        step = (rep >> 14 & 1) - (rep >> 12 & 1)
        ram.put(slot, "B", ss.wrap(0, step + ram.u8(slot), 0xC) & 0xFF)
    ram.put(rec + 0x24, "I", ram.u32(rec + 0x24) | 1 << (ram.u8(slot) & 31))


def key_setting(ram: Ram, rec: int, selected: int) -> None:
    """FUN_800DF14C: the pad picture with the eight button boxes."""
    player = ram.u32(rec)
    ram.put(rec + 0x10, "I", ram.u8(0x800A9620 + 0x2A * player))
    ram.put(rec + 0x24, "I", 0)
    if selected:
        ram.put(rec + 0x1C, "I", ram.u16(ss.PAD_HELD + 2 * player))
        ram.put(rec + 0x20, "I", ram.u16(ss.PAD_REPEAT + 2 * player))
        if ram.u32(rec + 8) == 0:
            ram.put(rec + 0x1C, "I", 0)
        if ram.u8(rec + 0x1C):
            ram.put(rec + 0xC, "I", 1)
        if ss.popcount(ram.u8(rec + 0x1C)) != 1:
            ram.put(rec + 0x1C, "I", 0)
        for i in range(8):
            key_row_input(ram, rec, rec + 0x28 + 0x38 * i)
    for i in range(8):
        key_row_draw(ram, rec, rec + 0x28 + 0x38 * i)
    analog = ram.u32(rec + 0x10) == 9
    x, y = ram.s32(rec + 0x14), ram.s32(rec + 0x18)
    ds._set_pkt(ram, ds.image(ram, ds.ot0(ram), ds._pkt(ram), x + 0x14, y + 0x88, 0x90, 0x88, 0x180,
                              0x100 if analog else 0, 0x7CE0 if analog else 0x7CA0, 0x80))
    ds.text(ram, STR_SETTING, 5 if selected else 10, 0, x + 0x14, y + 0x154)
    if selected:
        _option_glow(ram, x + 0x14, y + 0x154, 0x3F, int(ram.u32(rec + 0xC) == 0))


def key_vibration(ram: Ram, rec: int, selected: int) -> None:
    """FUN_800DF324: the vibration switch (a short buzz when turned on)."""
    player = ram.u32(rec)
    v = ram.u8(VIBRATION + player)
    if selected and ram.u16(ss.PAD_PRESSED + 2 * player) & 0xA000:
        v = v + 1 & 1
        ram.put(VIBRATION + player, "B", v)
        ram.put(rec + 0xC, "I", 1)
        ram.put(ss.PLAYER_ACTIVE + 2 * player, "H", 1)
        ss.controller_setting(ram, player, v)
        pad_vibrate(ram, player, 0xD)
    x, y = ram.s32(rec + 0x14) + 0x14, ram.s32(rec + 0x18) + 0x16E
    ds.text(ram, STR_VIBRATION, 5 if selected else 10, 0, x, y, 6 if v else 1, ram.u32(VIBRATION_WORDS + 4 * v))
    if selected:
        _option_glow(ram, x, y, 0x90, 1)


def key_config(ram: Ram) -> int:
    """FUN_800DF630: both players' key configuration; 1 when left (Select, or EXIT with no row busy)."""
    leave = 0
    for player in range(2):
        rec = KEY_CONFIG + KEY_CONFIG_SIZE * player
        if ram.u32(rec + 8) == 0 and ram.u16(ss.PAD_PRESSED + 2 * player):
            ram.put(rec + 8, "I", 1)                 # armed once a button is pressed on this page
        ram.put(rec + 0xC, "I", 0)
        for item in range(4):
            sel = int(item == ram.u32(rec + 4))
            pressed = ram.u16(ss.PAD_PRESSED + 2 * player)
            x, y = ram.s32(rec + 0x14) + 0x14, ram.s32(rec + 0x18)
            if item == 0:
                key_setting(ram, rec, sel)
            elif item == 1:
                key_vibration(ram, rec, sel)
            elif item == 2:
                if sel and pressed & 0x8F0:
                    ram.put(VIBRATION + player, "B", 0)
                    for k in range(8):
                        ram.put(0x80098308 + 8 * player + k, "B", ram.u8(DEFAULT_LAYOUT + k))
                    ram.put(rec + 0xC, "I", 1)
                ds.text(ram, STR_KEY_DEFAULT, 5 if sel else 10, 0, x, y + 0x188)
                if sel:
                    _option_glow(ram, x, y + 0x188, 0x3F, 1)
            elif sel and pressed & 0x8F0:
                leave = 1
            else:
                ds.text(ram, STR_KEY_EXIT, 5 if sel else 10, 0, x, y + 0x1A2)
                if sel:
                    _option_glow(ram, x, y + 0x1A2, 0x24, 1)
        if ram.u32(rec + 0xC) == 0:
            rep = ram.u16(ss.PAD_REPEAT + 2 * player)
            ram.put(rec + 4, "I", ss.wrap(0, (rep >> 14 & 1) - (rep >> 12 & 1) + ram.s32(rec + 4), 3) & 0xFFFFFFFF)
    ds.text(ram, STR_KEY_TITLE, _title_colour(ram), 1, 0x4A, 0x28)
    if (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x100:
        leave = 1
    if leave and not (ram.u32(KEY_CONFIG + 0xC) | ram.u32(KEY_CONFIG + KEY_CONFIG_SIZE + 0xC)):
        key_config_init(ram)
        return 1
    return 0


# ---- records (options page 2) ----
REC_SUBPAGE, REC_MASK, REC_TOTAL = 0x800ECA10, 0x800ECA14, 0x800ECA18
REC_LISTS = 0x800ECA20           # 4 x 0x20: s32 top row, s32 count, u8 ids[22]
TIME_RECORDS = 0x8009832C        # 22 x (u32 frames, name[4])
SURVIVOR_RECORDS = 0x800983DC    # 10 x (u16 costume key, u16 wins, name[4])
REC_TITLES = 0x800EB5C8          # the four sub-page titles
REC_ORDINALS = 0x800EB5B8        # "ST", "ND", "RD", "TH"
REC_DIGITS = 0x800EB594          # "%1d".."%8d" at index 1-8
STR_REC_PREFIX, STR_SPACES8 = 0x800B9C54, 0x800B9C60
STR_REC_RANK, STR_REC_NAME = 0x800B9C98, 0x800B9CCC
STR_REC_TIME = 0x800B9CA8        # "%c%f%H%V%02d'%02d\"%02d"
STR_WIN, STR_WINS = 0x800B9CC0, 0x800B9CC4
STR_PCT0, STR_PCT100, STR_PCT = 0x800B9C6C, 0x800B9C74, 0x800B9C7C
REC_HEADERS = (0x800B9D34, 0x800B9D58, 0x800B9D7C, 0x800B9DA0)   # the column headings of sub-pages 0-3
STR_RECORDS, STR_PAGE, STR_NEXT, STR_REC_EXIT = 0x800B9DC4, 0x800B9DD4, 0x800B9DF8, 0x800B9E18


def _sorted_ids(ram: Ram, lst: int, pairs: list[list[int]], n: int, ascending: int) -> None:
    ram.put(lst + 4, "I", n)
    if n > len(pairs):
        raise ValueError("more mask bits than characters")   # the game would sort stale stack words
    ss.sort_pairs(pairs, ascending)
    for i in range(n):
        ram.put(lst + 8 + i, "B", pairs[i][0] & 0xFF)


def records_init(ram: Ram) -> None:
    """FUN_800E0E2C: the four records lists (best times, survivors, usage, winning average)."""
    mask = ram.u32(ss.UNLOCKED) & 0xFFDFFFFF
    ram.put(REC_MASK, "I", mask)
    ram.put(REC_TOTAL, "I", sum(ss.usage(ram, c) for c in range(22)) & 0xFFFFFFFF)
    for i in range(4):
        lst = REC_LISTS + 0x20 * i
        ram.put(lst, "I", 0)
        ram.put(lst + 4, "I", 0)
        if i == 0:
            m = 0x3FF
            for c in range(22):
                if ram.u32(TIME_RECORDS + 8 * c) <= 359_998:
                    m |= 1 << c
            m &= 0xFFDFFFFF
            _sorted_ids(ram, lst, [[c, ram.u32(TIME_RECORDS + 8 * c)] for c in range(22) if m >> c & 1],
                        ss.popcount(m), 1)
        elif i == 1:
            ram.put(lst + 4, "I", 10)
            for k in range(10):
                ram.put(lst + 8 + k, "B", k)
        elif i == 2:
            _sorted_ids(ram, lst, [[c, ss.usage(ram, c)] for c in range(22) if mask >> c & 1], ss.popcount(mask), 0)
        else:
            pairs = []
            for c in range(22):
                if mask >> c & 1:
                    w, l_ = ram.u16(ss.STATS + 8 * c + 2), ram.u16(ss.STATS + 8 * c + 4)
                    pairs.append([c, (ss.permille(w, w + l_) * 0x100000 + w + l_) & 0xFFFFFFFF])
            _sorted_ids(ram, lst, pairs, ss.popcount(mask), 0)
    ram.put(REC_SUBPAGE, "I", 0)


def _rank_and_name(ram: Ram, row: int, key: int, y: int) -> None:
    ds.text(ram, STR_REC_RANK, 6, 0, 0x12, y, 99 if row + 1 > 100 else row + 1,
            ram.u32(REC_ORDINALS + 4 * (row % 10 if row < 4 else 3)))
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    ds.strcpy(ram, tail, ss.char_name(ram, key))
    ds.text(ram, ds.SCRATCH, 6, 0, 0x7E - (ds.strlen(ram, tail) * 9 >> 1), y)


def _right_number(ram: Ram, value: int, width: int, x: int, y: int, *extra: int) -> None:
    """A number right-aligned in `width` digits (FUN_800DFB74's and the rate pages' pattern)."""
    k, value = ds._digits_format(ram, value, width)
    tail = ds.strcpy(ram, ds.SCRATCH, STR_REC_PREFIX)
    ds.strcpy(ram, tail, STR_SPACES8)
    ds.strcpy(ram, tail + width - k, ram.u32(REC_DIGITS + 4 * k))
    ds.text(ram, ds.SCRATCH, 6, 0, x, y, value, *extra)


def _rate(ram: Ram, v: int, x: int, y: int, prev: tuple[int, int]) -> tuple[int, int]:
    """A per-mille share as "12.3%"; 0 and 1000 use fixed strings (1000 in colour 1)."""
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    col = 6
    if v == 0:
        fmt = STR_PCT0
    elif v == 1000:
        col, fmt = 1, STR_PCT100
    else:
        fmt, prev = STR_PCT, (v // 10, v % 10)
    ds.strcpy(ram, tail, fmt)
    ds.text(ram, ds.SCRATCH, col, 0, x, y, *prev)
    return prev


def _rec_rows(ram: Ram, lst: int):
    top = ram.s32(lst)
    for i in range(min(ram.s32(lst + 4), 10)):
        yield top + i, ram.u8(lst + 8 + top + i), 0x92 + 0x14 * i


def records_times(ram: Ram, lst: int) -> None:
    """FUN_800DFE40: best Time Attack time per character."""
    ds.text(ram, REC_HEADERS[0], 6, 0, 0x75, 0x7E)
    for row, c, y in _rec_rows(ram, lst):
        _rank_and_name(ram, row, (c % 22) * 4, y)
        t = ram.s32(TIME_RECORDS + 8 * c)
        t = min(t, 359_999)
        sec = ds._sdiv(t, 60)
        ds.text(ram, STR_REC_TIME, 6, 0, 0xC6, y, ds._sdiv(sec, 60), sec - ds._sdiv(sec, 60) * 60,
                ds._sdiv((t - sec * 60) * 100, 60))
        ds.text(ram, STR_REC_NAME, 6, 0, 0x132, y, TIME_RECORDS + 8 * c + 4)


def records_survivors(ram: Ram, lst: int) -> None:
    """FUN_800E0140: the ten greatest survivors."""
    ds.text(ram, REC_HEADERS[1], 6, 0, 0x75, 0x7E)
    for row, i, y in _rec_rows(ram, lst):
        e = SURVIVOR_RECORDS + 8 * i
        _rank_and_name(ram, row, (ram.u16(e) % 22) * 4, y)
        wins = ram.u16(e + 2)
        _right_number(ram, wins, 3, 0xC6, y)                # FUN_800DFB74
        ds.text(ram, STR_REC_NAME, 6, 0, 0xC6 + 0x24, y, STR_WIN if wins < 2 else STR_WINS)
        ds.text(ram, STR_REC_NAME, 6, 0, 0x132, y, e + 4)


def records_usage(ram: Ram, lst: int) -> None:
    """FUN_800E0430: each character's share of all fights, and the fight count."""
    ds.text(ram, REC_HEADERS[2], 6, 0, 0x75, 0x7E)
    prev = (0, 0)
    for row, c, y in _rec_rows(ram, lst):
        n = ss.usage(ram, c)
        _rank_and_name(ram, row, (c % 22) * 4, y)
        prev = _rate(ram, ss.permille(n, ram.u32(REC_TOTAL)), 0xE1, y, prev)
        _right_number(ram, n, 5, 0x120, y, prev[1])


def records_average(ram: Ram, lst: int) -> None:
    """FUN_800E0938: winning average, wins and losses per character."""
    ds.text(ram, REC_HEADERS[3], 6, 0, 0x75, 0x7E)
    prev = (0, 0)
    for row, c, y in _rec_rows(ram, lst):
        _rank_and_name(ram, row, (c % 22) * 4, y)
        w, l_ = ram.u16(ss.STATS + 8 * c + 2), ram.u16(ss.STATS + 8 * c + 4)
        prev = _rate(ram, ss.permille(w, w + l_), 0xAB, y, prev)
        _right_number(ram, w, 5, 0xEA, y, prev[1])
        _right_number(ram, l_, 5, 0x120, y)


def records(ram: Ram) -> int:
    """FUN_800E10E8: records browsing; left/right changes sub-page, up/down scrolls; 1 when left."""
    pressed = ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)
    if pressed & 0x1F0:
        return 1
    rep = ram.u16(ss.PAD_REPEAT) | ram.u16(ss.PAD_REPEAT + 2)
    sub = ss.wrap(0, ram.s32(REC_SUBPAGE) + (rep >> 13 & 1) - (rep >> 15), 3)
    ram.put(REC_SUBPAGE, "i", sub)
    lst = REC_LISTS + 0x20 * sub
    top = ram.u32(lst)
    n = ram.s32(lst + 4)
    if n < 11:
        top = 0
    else:
        t = (top + (rep >> 14 & 1) - (rep >> 12 & 1)) & 0xFFFFFFFF
        if t < (n - 9) & 0xFFFFFFFF:
            top = t
    ram.put(lst, "I", top)
    (records_times, records_survivors, records_usage, records_average)[sub](ram, lst)
    ds.text(ram, STR_RECORDS, 6, 1, 0x8B, 0x28)
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    ds.strcpy(ram, tail, ram.u32(REC_TITLES + 4 * sub))
    ds.text(ram, ds.SCRATCH, 6, 0, 0xB8 - (ds.strlen(ram, tail) * 9 >> 1), 0x5A)
    ds.text(ram, STR_PAGE, 6, 0, 0xE, 2, sub + 1)
    ds.text(ram, STR_NEXT, 0, 0x3F, 0x17C, 7, 6)
    ds.text(ram, STR_REC_EXIT, 0, 0x3F, 0x1A4, 2, 6)
    pad_pictures(ram, 0xA1, 0x1A2)
    return 0


# ---- memory card (options page 3) ----
CARD_STATE = 0x800EC63C          # u8: 0 prompt, else the card result + 1
AUTO_SAVE = 0x800982F1
STR_LOAD_PROMPT, STR_SAVE_PROMPT, STR_CANCEL = 0x800B98F0, 0x800B99C8, 0x800B9910
STR_YES_PROMPT, STR_NO_PROMPT = 0x800B9A1C, 0x800B9A3C
STR_INITIALIZE, STR_SOMETHING = 0x800B99B0, 0x800B997C
LOAD_MESSAGES = {1: (0x800B9930, 1), 2: (0x800B993C, 2), 3: (0x800B9948, 2), 4: (0x800B993C, 2),
                 5: (0x800B9958, 5), 6: (0x800B9968, 5)}     # LOAD OK / LOAD ERROR / NO MEMORY CARD / ...
SAVE_MESSAGES = {1: (0x800B99E8, 1), 2: (0x800B99F4, 2), 3: (0x800B9948, 2), 5: (0x800B9958, 5)}


class CardStub:
    """The memory-card calls (FUN_8004C528 load, FUN_8004C420 save, FUN_8004C4B4 format) as fixed
    results read from RAM, the way the verifier stubs them. Card results: 0 done, 2 no card,
    3 unformatted, 4 full, 5 no file / read error; the real I/O is described in formats/memory-card.md."""

    def __init__(self, base: int = 0x801F8000) -> None:
        self.base = base

    def load(self, ram: Ram) -> int:
        return ram.u32(self.base)

    def save(self, ram: Ram, mode: int) -> int:
        return ram.u32(self.base + 4)

    def format(self, ram: Ram) -> int:
        return ram.u32(self.base + 8)

    def write(self, ram: Ram) -> int:
        """FUN_8004C1A8 as AutoSave calls it (after the directory check)."""
        return ram.u32(self.base + 0x10)


CARD = CardStub()


def _card_retry(call, stops: tuple[int, ...]) -> int:
    """Try twice (stopping at a result in `stops`); an unformatted card (3) gets two more tries."""
    for _ in range(2):
        r = call()
        if r in stops:
            break
    if r == 3:
        for _ in range(2):
            r = call()
            if r in stops:
                break
    return r


def _card_save(ram: Ram, mode: int) -> int:
    return _card_retry(lambda: CARD.save(ram, mode), (0, 5))


def _card_format_and_save(ram: Ram) -> int:
    r = _card_retry(lambda: CARD.format(ram), (0,))
    return _card_save(ram, 1) if r == 0 else r


def _card_message(ram: Ram, s: int, colour: int) -> None:
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    ds.strcpy(ram, tail, s)
    ds.text(ram, ds.SCRATCH, colour, 0, 0xB8 - (ds.strlen(ram, tail) * 9 >> 1), 0x168)


def _card_prompts(ram: Ram, first: int, second: int) -> None:
    ds.text(ram, first, 0, 4, 0x15, 2, 6)
    ds.text(ram, second, 0, 4, 0x17, 5, 6)
    pad_pictures(ram, 0x98, 0x19C)


def _card_gate(ram: Ram, quiet_states: tuple[int, ...]) -> bool:
    pressed = ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)
    return bool(pressed & (0xF0 if ram.u8(CARD_STATE) in quiet_states else 0x58F0))


def card_load_screen(ram: Ram) -> int:
    """FUN_800DD198: Start loads; any other button (a message showing: also Start, up, down) leaves."""
    if _card_gate(ram, (0,)):
        return 1
    st = ram.u8(CARD_STATE)
    if st == 0:
        if (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x800:
            ram.put(CARD_STATE, "B", _card_retry(lambda: CARD.load(ram), (0,)) + 1 & 0xFF)
        _card_prompts(ram, STR_LOAD_PROMPT, STR_CANCEL)
        return 0
    _card_message(ram, *LOAD_MESSAGES.get(st, (STR_SOMETHING, 3)))
    return 0


def card_save_screen(ram: Ram) -> int:
    """FUN_800DD544: Start saves (after formatting when the card asked to be initialised)."""
    if _card_gate(ram, (0, 4)):
        return 1
    st = ram.u8(CARD_STATE)
    if st in (0, 4):
        if st == 4:
            _card_message(ram, STR_INITIALIZE, 7)
        _card_prompts(ram, STR_SAVE_PROMPT, STR_CANCEL)
        if (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x800:
            r = _card_save(ram, 1) if ram.u8(CARD_STATE) == 0 else _card_format_and_save(ram)
            ram.put(CARD_STATE, "B", r + 1 & 0xFF)
        return 0
    _card_message(ram, *SAVE_MESSAGES.get(st, (STR_SOMETHING, 3)))
    return 0


def card_auto_save_screen(ram: Ram) -> int:
    """FUN_800DD9E4: turning auto save on first saves (test mode -1); 2 when that worked."""
    if _card_gate(ram, (0, 4, 6)):
        return 1
    st = ram.u8(CARD_STATE)
    if st == 0:
        ram.put(CARD_STATE, "B", _card_save(ram, -1) + 1 & 0xFF)
        return 0
    if st == 1:
        return 2
    if st in (4, 6):
        if st == 4:
            _card_message(ram, STR_INITIALIZE, 7)
        if (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2)) & 0x800:
            r = _card_save(ram, 1) if st == 6 else _card_format_and_save(ram)
            ram.put(CARD_STATE, "B", r + 1 & 0xFF)
        _card_prompts(ram, STR_YES_PROMPT, STR_NO_PROMPT)
        return 0
    _card_message(ram, *SAVE_MESSAGES.get(st, (STR_SOMETHING, 3)))
    return 0


def memory_card_page(ram: Ram, rec: int) -> None:
    """FUN_800DDED0: the memory card list and its save / load / auto-save screens."""
    sub = ram.s32(rec + 4)
    if sub == 0:
        ram.put(CARD_STATE, "B", 0)
        option_list_input(ram, rec)
    elif sub == 1:
        if card_save_screen(ram):
            ram.put(rec + 4, "I", 0)
    elif sub == 2:
        if card_load_screen(ram):
            ram.put(rec + 4, "I", 0)
    elif sub == 3:
        ram.put(AUTO_SAVE, "B", 1)                       # the test save already records auto save on
        r = card_auto_save_screen(ram)
        ram.put(AUTO_SAVE, "B", 0)
        if r == 2:
            ram.put(AUTO_SAVE, "B", 1)
        if r in (1, 2):
            ram.put(rec + 4, "I", 0)
    display_position(ram)
    _option_modes(ram)
    option_list_draw(ram, rec)


def _options_exit_allowed(ram: Ram) -> bool:
    """Select+Start is ignored while a memory-card save or load runs."""
    if ram.u8(OPT_PAGE) != 3:
        return True
    return ram.u32(OPT_PAGES + 3 * OPT_PAGE_SIZE + 4) in (0, 3)


def options(ram: Ram) -> int:
    """FUN_800DE480 (game state 5)."""
    if _options_exit_allowed(ram):
        mode = ram.u32(ds.MODE)
        ram.put(ds.MODE, "I", 0)
        r = ss.menu_exit(ram)
        ram.put(ds.MODE, "I", mode)
        if r:
            return 1
    saved = ds._pkt(ram)
    ds._set_pkt(ram, MENU_PACKETS + ram.u32(ds.DISPLAY_BUFFER) * 0x3C00)
    sub = ram.s16(ss.SUB_STATE)
    if sub == 2:
        ss.goto_transition(ram, 4)
    elif sub in (0, 1):
        if sub == 0:
            ram.put(MENU_TO_OPTIONS, "B", 1)
            ss.draw_hold(ram, 1)
            ss.draw_hold(ram, 0)
            _option_modes(ram)
            key_config_init(ram)
            for i in range(6):
                ram.put(OPT_PAGES + OPT_PAGE_SIZE * i, "I", 0)
                ram.put(OPT_PAGES + OPT_PAGE_SIZE * i + 4, "I", 0)
            ram.put(OPT_PAGE, "B", 0)
            ram.put(ss.SUB_STATE, "H", 1)
        page = ram.u8(OPT_PAGE)
        rec = OPT_PAGES + OPT_PAGE_SIZE * page
        if page in (0, 1):
            option_list_input(ram, rec)
            if page == 1:
                e = ram.u32(rec + 0x20) + 0x14 * ram.u32(rec)
                option_mode_icons(ram, ram.u16(e + 0x12))
            option_list_draw(ram, rec)
        elif page == 2:
            if ram.u32(rec + 4) == 0:
                records_init(ram)
                ram.put(rec + 4, "I", ram.u32(rec + 4) + 1)
            if records(ram):
                ram.put(rec + 4, "I", 0)
                ram.put(ram.u32(rec + 0x2C), "B", ram.u8(rec + 0x31))
        elif page == 3:
            memory_card_page(ram, rec)
        elif page == 4:
            if key_config(ram):
                ram.put(OPT_PAGE, "B", 0)
        elif page == 5:
            display_adjust(ram)
        else:
            ram.put(ss.SUB_STATE, "H", 2)
    title_backdrop(ram, 6)
    ds._set_pkt(ram, saved)
    return 0
