#!/usr/bin/env python3
"""Integer port of practice.ovl's pause menu pages (Japan Rev.1), drawing included.

Like `menu_sim.py`, every routine writes the same RAM as the game (text glyph packets and the
ordering tables included), so `tools/research/verify_practice_sim.py` compares all of RAM with the harness.

The practice state `S` is at `*0x800B904C` (0x800B9180); see modes.md#practice for its fields.
"""

from __future__ import annotations

import command_list_sim as cl
import draw_sim as ds
from fight_sim import Ram

S_PTR = 0x800B904C
FMT_S = 0x800B0C90              # "%c%f%H%V%s"
FMT_S2 = 0x800B0F30             # the same format, used by the tech-roll line
STR_MODE_SELECT, STR_FREE, STR_VS_CPU = 0x800B0C1C, 0x800B0C30, 0x800B0C40
STR_COMBO, STR_PLAYER_SELECT, STR_RESET, STR_VS_CPU_TITLE = 0x800B0C50, 0x800B0C68, 0x800B0C80, 0x800B0D20
STR_COMMAND_LIST, STR_TRAINING_DUMMY, STR_SPACE = 0x800B0C9C, 0x800B0CAC, 0x800B0CBC
STR_COUNTER, STR_ATTACK_DATA, STR_FREEZE, STR_REPLAY = 0x800B0CC0, 0x800B0CD0, 0x800B0CDC, 0x800B0CEC
STR_KEY_DISPLAY, STR_RETURN = 0x800B0CFC, 0x800B0D08
STR_CPU_DIFFICULTY, STR_CPU_LEVEL = 0x800B0D30, 0x800B0D40
STR_COMBO_PLAYER, STR_COMBO_TYPE, STR_NONE = 0x800B0D4C, 0x800B0D68, 0x800B0D74
OFF_ON, OK_CANCEL, DUMMY_NAMES = 0x800B9050, 0x800B9058, 0x800B9060
REPLAY_NAMES, DIFFICULTY_NAMES, LEVEL_NAMES = 0x800B9084, 0x800B90A4, 0x800B90B0
COMBO_NAMES = 0x800B90E4         # "1".."8"
TECH_ROLL_LINES = 0x800B9160     # "TECH ROLL d", "TECH ROLL u" ('u'/'d' become arrow sprites)
COMBO_TABLE = 0x800B2ADC         # per bank type: u32 combo count (and a pointer before it)
FIGHTERS = (0x800A96F0, 0x800AAF7C)
TEXT_BUF = 0x1F800200            # scratchpad copy of a stack string (not part of the compared RAM)
X0, VALUE_COLUMNS = 0x48, 0x19


def _s(ram: Ram) -> int:
    return ram.u32(S_PTR)


def _colours(ram: Ram, cursor_field: int) -> int:
    """Reset the 17 row colours to 11 and light the cursor's row (10); returns S."""
    s = _s(ram)
    for i in range(0x11):
        ram.put(s + 0x8C + i, "B", 0xB)
    ram.put(s + 0x8C + ram.s8(s + cursor_field) & 0xFFFFFFFF, "B", 0xA)
    return s


def _label(ram: Ram, s: int, row: int, y: int, label: int) -> None:
    ds.text(ram, FMT_S, ram.u8(s + 0x8C + row), 0, X0, y, label)


def _value(ram: Ram, s: int, row: int, y: int, table: int, index: int) -> None:
    """A value right-aligned to 25 characters from the menu's left edge."""
    v = ram.u32(table + 4 * index & 0xFFFFFFFF)
    ds.text(ram, FMT_S, ram.u8(s + 0x8C + row), 0, X0 + (VALUE_COLUMNS - ds.strlen(ram, v)) * 9, y, v)


def tech_roll_line(ram: Ram, which: int, x: int, y: int, colour: int) -> None:
    """FUN_800B7704: TECH ROLL with an up or down arrow sprite for the 'u'/'d' marks."""
    if ram.u32(ds.TEXT_OFF):
        return
    src = ram.u32(TECH_ROLL_LINES + 4 * which)
    clut = (((colour >> 4) + 0x18 & 0x1F) + 0x1E0 << 6 | colour & 0xF | 0x10) << 16 & 0xFFFFFFFF
    out = bytearray()
    cx = x
    ot = ds.ot0(ram) + 0x1C
    while ram.u8(src):
        c = ram.u8(src)
        src += 1
        if c in (0x75, 0x64):                       # 'u', 'd'
            uv = clut | (0xE078 if c == 0x75 else 0xE082)
            p = ds.sprt(ram, ot, ds._pkt(ram), 0x65000000, cx & 0xFFFF | y << 16 & 0xFFFFFFFF, 0x10000A, uv)
            ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 6))
            c = 0x20
        out.append(c)
        cx += 9
    for i, c in enumerate(bytes(out) + b"\0"):
        ram.put(TEXT_BUF + i, "B", c)
    ds.text(ram, FMT_S2, colour, 0, x, y, TEXT_BUF)


def _common_tail(ram: Ram, s: int, row: int, y: int, key_display: bool) -> None:
    """ATTACK DATA, FREEZE SIGNAL, REPLAY SETTINGS (and KEY DISPLAY), then RETURN TO MODE SELECT."""
    rows = ((STR_ATTACK_DATA, OFF_ON, 0x9D, False), (STR_FREEZE, OFF_ON, 0x83, True),
            (STR_REPLAY, REPLAY_NAMES, 0x81, True)) + (((STR_KEY_DISPLAY, OFF_ON, 0xA0, False),) if key_display else ())
    for i, (label, table, field, signed) in enumerate(rows):
        _label(ram, s, row, y, label)
        _value(ram, s, row, y, table, ram.s8(s + field) if signed else ram.u8(s + field))
        if i < len(rows) - 1:
            row += 1
        y += 0x16
    ds.text(ram, FMT_S, ram.u8(s + 0x8D + row), 0, X0, 0x148, STR_RETURN)


def page_mode_select(ram: Ram) -> None:
    """FUN_800B5834: MODE SELECT (FREE, VS CPU, COMBO TRAINING, PLAYER SELECT, RESET)."""
    ds.text(ram, STR_MODE_SELECT, 10, 1, 0x10, 0x38)
    s = _colours(ram, 0x77)
    for k, (label, y) in enumerate(((STR_FREE, 0x6E), (STR_VS_CPU, 0x84), (STR_COMBO, 0x9A),
                                    (STR_PLAYER_SELECT, 0xB0), (STR_RESET, 0xC6))):
        ds.text(ram, label, ram.u8(s + 0x8C + k), 0, 0x10, y)


def _head(ram: Ram, title: int, cursor_field: int) -> int:
    ds.text(ram, title, 10, 1, X0, 0x38)
    s = _colours(ram, cursor_field)
    _label(ram, s, 0, 0x6E, ram.u32(OK_CANCEL + 4 * ram.u8(s + 0xA7)))
    _label(ram, s, 1, 0x84, STR_COMMAND_LIST)
    return s


def page_free(ram: Ram) -> None:
    """FUN_800B5978: the FREE pause menu."""
    s = _head(ram, STR_FREE, 0x78)
    y = 0xA2
    _label(ram, s, 2, y, STR_TRAINING_DUMMY)
    y += 0x16
    dummy = ram.s8(s + 0x7D)
    if dummy in (6, 7):
        tech_roll_line(ram, dummy - 6, X0 + 0x7E, y, ram.u8(s + 0x8E))
    else:
        _label(ram, s, 2, y, STR_SPACE)
        _value(ram, s, 2, y, DUMMY_NAMES, dummy)
    y += 0x16
    _label(ram, s, 3, y, STR_COUNTER)
    _value(ram, s, 3, y, OFF_ON, ram.u8(s + 0x9E))
    _common_tail(ram, s, 4, y + 0x16, True)


def page_vs_cpu(ram: Ram) -> None:
    """FUN_800B5ED4: the VS CPU pause menu."""
    s = _head(ram, STR_VS_CPU_TITLE, 0x79)
    y = 0xA2
    _label(ram, s, 2, y, STR_CPU_DIFFICULTY)
    _value(ram, s, 2, y, DIFFICULTY_NAMES, ram.s8(s + 0x7E))
    y += 0x16
    _label(ram, s, 3, y, STR_CPU_LEVEL)
    _value(ram, s, 3, y, LEVEL_NAMES, ram.s8(s + 0x7F))
    _common_tail(ram, s, 4, y + 0x16, True)


def combo_count(ram: Ram, s: int) -> int:
    """FUN_800B8108: the number of combos of the combo player's character."""
    f = FIGHTERS[0] + 0x188C * ram.s8(s + 0x7B)
    return ram.u32(COMBO_TABLE + 8 * ram.s16(f + 0x16) & 0xFFFFFFFF)


def page_combo(ram: Ram) -> None:
    """FUN_800B6368: the COMBO TRAINING pause menu."""
    s = _head(ram, STR_COMBO, 0x7A)
    y = 0xA2
    pl = ram.s8(s + 0x7B)
    ds.text(ram, STR_COMBO_PLAYER, ram.u8(s + 0x8E), 0, X0, y, pl + 1)
    key = ram.s16(FIGHTERS[0] + 0x188C * pl + 0x14)
    ds.text(ram, FMT_S, ram.u8(s + 0x8E), 0, X0 | 0x87, y, ram.u32(ram.u32(ds.CHAR_RECORDS + 4 * (0x58 if key > 0x5C else key))))
    y += 0x16
    _label(ram, s, 3, y, STR_COMBO_TYPE)
    if combo_count(ram, s):
        _value(ram, s, 3, y, COMBO_NAMES, ram.s8(s + 0x7C))
    else:
        ds.text(ram, FMT_S, ram.u8(s + 0x8F), 0, X0 + 0xBD, y, STR_NONE)
    y += 0x16
    _common_tail(ram, s, 4, y, False)


def pause_page(ram: Ram) -> None:
    """FUN_800B57AC: the pause menu page for the sub-mode (or MODE SELECT)."""
    s = _s(ram)
    if ram.u8(s + 0x75):
        page_mode_select(ram)
    elif ram.u8(s + 0x77) == 0:
        page_free(ram)
    elif ram.u8(s + 0x77) == 1:
        page_vs_cpu(ram)
    elif ram.u8(s + 0x77) == 2:
        page_combo(ram)


# ---- practice HUD (attack data, prompts, hit markers, key display) ----
HUD_FMT_NUMBER, HUD_FMT_COMBO, HUD_FMT_DAMAGE = 0x800B0E8C, 0x800B0E98, 0x800B0EA8
HUD_TOTAL, HUD_DMG, HUD_COUNTER, HUD_CLEAN = 0x800B0E18, 0x800B0E2C, 0x800B0E44, 0x800B0E54
HUD_REPLAY_SELECT = 0x800B0E00
HUD_PROMPTS = {1: None, 2: (0x800B0DAC, 1), 3: (0x800B0DC8, 2), 5: (0x800B0DE0, 5), 8: (0x800B0DEC, 6)}
HUD_PLAY_SELECT, HUD_PLAY_REC = 0x800B0D7C, 0x800B0D90
MARKER_UV = 0x800B9154           # per hit level: the 48 x 16 marker picture
KEY_RING, KEY_HEADS, KEY_GUIDE_END = 0x800B9230, 0x800B9368, 0x800B92F8
ARROWS = 0x800B0EDC              # per direction: u16 uv, u16 flip flags (1 horizontal, 2 vertical)


def combo_counter(ram: Ram, count: int, damage: int) -> None:
    """FUN_800B6F58: the big `n COMBO` and `n DAMAGE` counters."""
    if count:
        ds.text(ram, HUD_FMT_NUMBER, 0xC, 0x88, 1, 6, count)
        ds.text(ram, HUD_FMT_COMBO, 0x2A if count >= 10 else 0x20, 0x88, 1, 5)
    ds.text(ram, HUD_FMT_NUMBER, 0x16, 0xA6, 1, 6, damage)
    a = abs(ds._s32(damage))
    x = 0x40 if a >= 100 else 0x2A if a < 10 else 0x35
    if ds._s32(damage) < 0:
        x += 0xD
    ds.text(ram, HUD_FMT_DAMAGE, x, 0xB0, 0, 7)


def hit_marker(ram: Ram, x: int, y: int, kind: int) -> None:
    """FUN_800B75AC: the marker at a hit point (kind: 0 high, 1 mid, 2 low, 3 unblockable)."""
    if ram.u32(ds.TEXT_OFF):
        return
    ot = ds.ot0(ram) + (8 if kind == 3 else 4)
    p = ds._pkt(ram)
    if kind == 3:
        p = ds.sprt(ram, ot, p, 0x65000000, (x - 6) & 0xFFFF | (y - 0x18) << 16 & 0xFFFFFFFF, 0x30000C, 0x7FF6C090)
        uv = 0x7FF70000
    else:
        p = ds.sprt(ram, ot, p, 0x65000000, (x - 0x18) & 0xFFFF | (y - 8) << 16 & 0xFFFFFFFF, 0x100030,
                    ram.u32(MARKER_UV + 4 * kind))
        uv = 0x7FB70000
    p = ds.sprt(ram, ot, p, 0x65000000, (x - 0x18) & 0xFFFF | (y - 0x18) << 16 & 0xFFFFFFFF, 0x300030, uv | 0xC0D0)
    ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0x1F))


def key_button(ram: Ram, x: int, y: int, pad: int, guide: int) -> None:
    """FUN_800B721C: a button icon (the pressed face buttons) of the key display."""
    if ram.u32(ds.TEXT_OFF):
        return
    ot = ds.ot0(ram) + 0xC
    idx = int(pad & 0x80 != 0) | (2 if pad & 0x10 else 0) | (4 if pad & 0x40 else 0) | (8 if pad & 0x20 else 0)
    uv = ((idx & 0x18) << 3 | 0x7F00 | idx & 7 | 0x30) << 16 | 0xE000
    xy = x & 0xFFFF | y << 16 & 0xFFFFFFFF
    p = ds.sprt(ram, ot, ds._pkt(ram), 0x65000000, xy, 0x200014, uv)
    p = ds.sprt(ram, ot, p, 0x65000000, xy, 0x200014, ((int(guide != 0) * 0x10 + 0x300 >> 4 & 0x3F) | 0x7F80) << 16 | 0xE014)
    ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 6))


def key_arrow(ram: Ram, x: int, y: int, pad: int, colour: int) -> None:
    """FUN_800B7354: a direction arrow (a flipped 19 x 31 quad) of the key display."""
    if ram.u32(ds.TEXT_OFF):
        return
    ot = ds.ot0(ram) + 0xC
    p = ds._pkt(ram)
    d = pad & 0xF000
    idx = {0x1000: 1, 0x3000: 2, 0x2000: 3, 0x6000: 4, 0x4000: 5, 0xC000: 6, 0x8000: 7, 0x9000: 8}.get(d, 0)
    base, flags = ram.u16(ARROWS + 4 * idx), ram.u16(ARROWS + 4 * idx + 2)
    uv = [base, base + 0x13, base + 0x1F00, base + 0x1F13]
    if flags & 1:
        uv = [uv[1], uv[0], uv[3], uv[2]]
    if flags & 2:
        uv = [uv[2], uv[3], uv[0], uv[1]]
    clut = {1: 0x7FB3, 2: 0x7FB4, 3: 0x7FB5}.get(colour, 0x7FB2)
    xy = (y << 16 | x) & 0xFFFFFFFF
    words = (0x2D000000, xy, uv[0] | clut << 16, xy + 0x13, uv[1] | 0x60000, xy + 0x1F0000, uv[2], xy + 0x1F0013, uv[3])
    for i, w in enumerate(words):
        ram.put(p + 4 + 4 * i, "I", w & 0xFFFFFFFF)
    ds.link(ram, ot, p, 9)
    ds._set_pkt(ram, p + 0x28)


def key_display(ram: Ram, s: int) -> None:
    """FUN_800B7C84: the last 15 inputs (directions and new buttons) along the bottom, oldest first."""
    head = ram.s32(KEY_HEADS + 4 * ram.s8(s + 0x7B))
    guide_end = ram.s32(KEY_GUIDE_END)
    mode = ram.u8(s + 0xA3)
    dir_col, btn_col, dir_guide, btn_guide = 0, 1, 0, 1          # colours before / after the guide end
    if mode == 2 or (mode == 3 and ram.u8(s + 0xA4) & 0x10):
        dir_col, btn_col, dir_guide, btn_guide = 3, 0, 3, 0
    elif mode in (4, 5):
        dir_col, btn_col, dir_guide, btn_guide = 0, 1, 3, 0

    def wrap(i: int) -> int:
        return 0x31 if i < 0 else i if i < 0x32 else 0

    i = wrap(head + 1)
    items: list[tuple[int, int]] = []
    since = 0
    prev_dir = prev_btn = 0
    for _ in range(0x32):
        e = KEY_RING + 4 * i
        if i == 0:
            since = 0
        d = ram.u8(e + 1)
        if d and d != prev_dir:
            items.append((d << 12 & 0xFFFF, dir_guide if guide_end < i else dir_col))
            since += 1
        b = ram.u8(e)
        if b & (b ^ prev_btn):
            items.append((b << 4 & 0xFFFF, btn_guide if guide_end < i else btn_col))
            since += 1
        prev_dir, prev_btn = d, b
        i = wrap(i + 1)
    n = len(items)
    if ram.u8(s + 0xA2):
        shown = min(since, 15)
        shown = shown if shown < n else n
    else:
        shown = min(n, 15)
    x = 0xC
    for v, col in items[n - shown:]:
        if v & 0xF000:
            key_arrow(ram, x, 400, v, col)
            x += 0x17
        elif v & 0xF0:
            key_button(ram, x, 400, v, col)
            x += 0x17


def practice_hud(ram: Ram) -> None:
    """FUN_800B6898: the practice prompts, attack data, hit markers and key display."""
    if ram.u32(0x800958E0):
        return
    s = _s(ram)
    prompt = None
    if ram.u8(s + 0x87) and not (ram.s8(s + 0x77) == 2 and combo_count(ram, s) == 0):
        k = ram.s8(s + 0x82)
        if k == 1:
            prompt = (HUD_PLAY_SELECT, 1) if ram.s8(s + 0x77) == 2 else (HUD_PLAY_REC, 7)
        elif k in HUD_PROMPTS and k != 1:
            prompt = HUD_PROMPTS[k]
    elif not ram.u8(s + 0x8A) and ram.s8(s + 0x81) == 4 and ram.s8(s + 0x77) == 0:
        prompt = (HUD_REPLAY_SELECT, 1)
    if prompt:
        ds.text(ram, prompt[0], prompt[1], 1, 0x15)
    if ram.u8(s + 0x9D) and not ram.u8(s + 0x8A):
        me = s + 0x14 + 0x20 * ram.u8(s + 0x84)
        d = s + 0x14 + 0x20 * ram.u8(s + 0x85)
        dmg, top = ram.s16(d + 0xE), ram.s16(d + 0xC)
        ds.text(ram, HUD_TOTAL, 1, 0x17, 3, ram.u32(me))
        ds.text(ram, HUD_TOTAL, 1, 1, 3, ram.u32(d))
        hits = ram.s8(d + 0x1D)
        if hits >= 2 and ram.s16(d + 0x10) and ram.s32(d + 8) > 0:
            combo_counter(ram, hits, ram.u32(d + 8))
        elif ram.s16(d + 0x12) >= 2:
            combo_counter(ram, 0, ram.u32(d + 8))
        col = 7 if top < dmg else 6 if top == dmg else 3
        pct = ds._sdiv(dmg * 100, top) if top and dmg else 0
        ds.text(ram, HUD_DMG, col, 1, 4, dmg, pct)
        if ram.u8(d + 0x1A):
            ds.text(ram, HUD_COUNTER, 2, 1, 5)
        if ram.u8(d + 0x1B):
            ds.text(ram, HUD_CLEAN, 5, 1, 6)
        idx = ram.u8(s + 0x74)
        for _ in range(4):
            if idx < 0:
                idx = 3
            m = s + 0x54 + 8 * idx
            if ram.s16(m + 2):
                code = ram.s16(m)
                kind = {0x217: 1, 0x31F: 1, 0x51F: 1, 0x10F: 2, 0x607: 3, 0x706: 3, 0x800: 4}.get(code, 0)
                if kind != 4:
                    hit_marker(ram, ram.s16(m + 4), ram.s16(m + 6), kind)
            idx -= 1
    if ram.u8(s + 0xA0):
        key_display(ram, s)


# ---- pause menu input ----
class PracticeHooks:
    """SoundPlayFighter(0, id, 0) (default: nothing) and the command list FUN_8007906C(player
    mask, player) (default: its port). The verifier logs both."""

    def sound(self, ram: Ram, sound_id: int) -> None:
        pass

    def command_list(self, ram: Ram, mask: int, player: int) -> None:
        cl.practice_command_list(ram, mask, player)


HOOKS = PracticeHooks()
ITEM_ROWS = {0: (0x800B0A10, 0x78, 8), 1: (0x800B0A1C, 0x79, 8), 2: (0x800B0A28, 0x7A, 7)}   # item ids, cursor, last row
GUIDE_WAIT = 0x800B916C          # per player: 30 after a ring reset
RING_REPLAY = 0x800B92F8         # replay start (u32 0, then the first ring word)
RING_MARKS = 0x800B9304          # 50 x u16, cleared with the replay
ROUND_REQUEST = 0x80097350       # 9 restart the round, 11 leave practice
RESUME = 0x800958AC
SND_MOVE, SND_OK = 0x546C, 0x4CEB


def key_ring_reset(ram: Ram, player: int) -> None:
    """FUN_800B7A88: empties the key ring (bytes 0-1 and bits 16-30 of each word)."""
    for i in range(0x32):
        e = KEY_RING + 4 * i
        ram.put(e, "H", 0)
        ram.put(e, "I", ram.u32(e) & 0x8000FFFF)
    ram.put(KEY_HEADS + 4 * player & 0xFFFFFFFF, "I", 0)
    ram.put(GUIDE_WAIT + 4 * player & 0xFFFFFFFF, "I", 0x1E)


def replay_reset(ram: Ram, player: int) -> None:
    """FUN_800B8244 (with FUN_800B82D0): restarts the replay from the ring's first entry."""
    ram.put(RING_REPLAY, "I", 0)
    if ram.s32(KEY_HEADS + 4 * player & 0xFFFFFFFF) < 0:
        ram.put(RING_REPLAY + 4, "I", ram.u32(RING_REPLAY + 4) & 0x8000FFFF)
        ram.put(RING_REPLAY + 4, "H", 0)
    else:
        ram.put(RING_REPLAY + 4, "I", ram.u32(KEY_RING))
    ram.put(RING_REPLAY + 8, "I", 0)
    for i in range(0x32):
        ram.put(RING_MARKS + 2 * i, "H", 0)


def load_guide(ram: Ram, player: int, combo: int) -> int:
    """FUN_800B7FB4: copies combo `combo` of the player's character into the key ring as the
    input guide; returns its step count (0: none, the ring is emptied)."""
    kind = ram.s16(FIGHTERS[0] + 0x188C * player + 0x16 & 0xFFFFFFFF)
    t = COMBO_TABLE - 4 + 8 * kind & 0xFFFFFFFF
    if ram.u32(t + 4) == 0:
        return 0
    rec = ram.u32(t) + 12 * combo & 0xFFFFFFFF
    steps, n = ram.u32(rec), ram.s16(rec + 8)
    if n == 0:
        key_ring_reset(ram, player)
        return 0
    ram.put(KEY_HEADS + 4 * player & 0xFFFFFFFF, "i", n - 1)
    for i in range(max(n, 0)):
        ram.put(KEY_RING + 4 * i, "I", ram.u32(steps + 4 * i & 0xFFFFFFFF))
    return n


def cursor_step(ram: Ram, cur: int, last: int) -> int:
    """FUN_800B4BA8: up/down on the repeat pad, wrapping at 0 and `last`."""
    rep = ram.u16(_s(ram) + 4)
    if rep & 0x4000:
        cur += 1
        HOOKS.sound(ram, SND_MOVE)
    elif rep & 0x1000:
        cur -= 1
        HOOKS.sound(ram, SND_MOVE)
    v = _s8(cur)
    return last if v < 0 else 0 if last < v else v


def _s8(v: int) -> int:
    v &= 0xFF
    return v - 0x100 if v & 0x80 else v


def _sb(ram: Ram, s: int, off: int, v: int) -> None:
    ram.put(s + off, "B", v & 0xFF)


def menu_cursor(ram: Ram) -> None:
    """FUN_800B49C4: moves the cursor of MODE SELECT or of the current page. Choosing another
    sub-mode on MODE SELECT resets its settings."""
    s = _s(ram)
    if ram.u8(s + 0x75):
        old = ram.s8(s + 0x77)
        new = cursor_step(ram, old, 4)
        _sb(ram, s, 0x77, new)
        if new == old:
            return
        me = ram.u8(s + 0x84)
        if new == 0:
            for off, v in ((0x9D, 1), (0x87, 0), (0x9F, 0), (0x86, 0), (0x7C, 0), (0x7B, me)):
                _sb(ram, s, off, v)
            replay_reset(ram, me)
            key_ring_reset(ram, ram.u8(s + 0x84))
            _sb(ram, s, 0xA3, 1)
        elif new == 1:
            for off in (0x9E, 0x81, 0x87, 0x9F, 0x86, 0x7C):
                _sb(ram, s, off, 0)
            _sb(ram, s, 0x7B, me)
            replay_reset(ram, me)
            key_ring_reset(ram, ram.u8(s + 0x84))
            _sb(ram, s, 0xA3, 1)
        elif new == 2:
            _sb(ram, s, 0x7B, me)
            for off, v in ((0x9E, 0), (0x81, 0), (0xA0, 1), (0x87, 0), (0x9F, 0), (0x86, 0), (0x7D, 0), (0x7C, 0)):
                _sb(ram, s, off, v)
            replay_reset(ram, ram.s8(s + 0x7B))
            key_ring_reset(ram, ram.s8(s + 0x7B))
            _sb(ram, s, 0xA3, 2)
        return
    sub = ram.s8(s + 0x77)
    if sub in ITEM_ROWS:
        _, off, last = ITEM_ROWS[sub]
        _sb(ram, s, off, cursor_step(ram, ram.s8(s + off), last))


def _pressed(ram: Ram, s: int) -> int:
    return ram.u16(s + 2)


def _mode_select_confirm(ram: Ram) -> None:
    """FUN_800B4C8C."""
    s = _s(ram)
    sub = ram.s8(s + 0x77)
    if not _pressed(ram, s) & 0x9F0 or not 0 <= sub <= 4:
        return
    if sub == 3:                                    # PLAYER SELECT
        ram.put(ROUND_REQUEST, "I", 9)
        HOOKS.sound(ram, SND_OK)
        return
    if sub == 4:                                    # RESET
        ram.put(ROUND_REQUEST, "I", 0xB)
        return
    for off, v in ((0x75, 0), (0x78, 0), (0x79, 0), (0x7A, 0), (0xA7, 0), (0xA9, 3)):
        _sb(ram, s, off, v)
    if ram.s8(s + 0x77) == 2:
        for off, v in ((0x7B, ram.u8(s + 0x84)), (0x7C, 0), (0x87, 1), (0xA0, 1), (0xA3, 1)):
            _sb(ram, s, off, v)
        key_ring_reset(ram, ram.s8(s + 0x7B))
        replay_reset(ram, ram.s8(s + 0x7B))
        load_guide(ram, ram.s8(s + 0x7B), ram.s8(s + 0x7C))
    HOOKS.sound(ram, SND_OK)
    cl.horizon_band(ram)


def _changed(ram: Ram, s: int) -> None:
    _sb(ram, s, 0xA7, 0)
    HOOKS.sound(ram, SND_MOVE)


def _toggle(ram: Ram, s: int, off: int) -> bool:
    """Left or right flips a byte; returns True when a face button was pressed instead."""
    p = _pressed(ram, s)
    if p & 0x9F0:
        return True
    if p & 0xA000:
        _sb(ram, s, off, ram.u8(s + off) + 1 & 1)
        _changed(ram, s)
    return False


def _cycle(ram: Ram, s: int, off: int, last: int) -> bool:
    """Right adds one, left takes one (both may apply), wrapping at 0 and `last`."""
    p = _pressed(ram, s)
    if p & 0x9F0:
        return True
    if p & 0x2000:
        _sb(ram, s, off, ram.u8(s + off) + 1)
        _changed(ram, s)
    if _pressed(ram, s) & 0x8000:
        _sb(ram, s, off, ram.u8(s + off) - 1)
        _changed(ram, s)
    v = ram.s8(s + off)
    _sb(ram, s, off, last if v < 0 else 0 if last < v else v)
    return False


def _guide_changed(ram: Ram, s: int) -> None:
    key_ring_reset(ram, ram.s8(s + 0x7B))
    replay_reset(ram, ram.s8(s + 0x7B))
    load_guide(ram, ram.s8(s + 0x7B), ram.s8(s + 0x7C))
    _changed(ram, s)


def _item_input(ram: Ram) -> None:
    """FUN_800B4E4C: the handler of the item under the cursor (jump table 0x800B0A58). A face
    button on a value row sends the cursor back to the first row."""
    s = _s(ram)
    sub = ram.s8(s + 0x77)
    item = 0
    if sub in ITEM_ROWS:
        table, off, _ = ITEM_ROWS[sub]
        item = ram.u8(table + ram.s8(s + off) & 0xFFFFFFFF)
    p = _pressed(ram, s)
    back = False
    if item == 0:                                   # OK / CANCEL: resume
        if p & 0x9F0:
            ram.put(RESUME, "I", 1)
            _sb(ram, s, 0xAC, 1)
    elif item in (1, 2, 3):                         # ATTACK DATA, COUNTER ATTACKS, FREEZE SIGNAL
        back = _toggle(ram, s, {1: 0x9D, 2: 0x9E, 3: 0x83}[item])
    elif item == 4:                                 # REPLAY SETTINGS (no MANUAL in combo training)
        back = _cycle(ram, s, 0x81, 3 if ram.s8(s + 0x77) == 2 else 4)
    elif item == 5:                                 # KEY DISPLAY
        if p & 0x9F0:
            back = True
        elif p & 0xA000:
            _sb(ram, s, 0xA0, ram.u8(s + 0xA0) + 1 & 1)
            key_ring_reset(ram, ram.u8(s + 0x84))
            key_ring_reset(ram, ram.u8(s + 0x85))
            _changed(ram, s)
    elif item == 6:                                 # S+0x87 (not in any menu)
        if p & 0x9F0:
            back = True
        elif p & 0xA000:
            _sb(ram, s, 0x87, ram.u8(s + 0x87) + 1 & 1)
            _changed(ram, s)
            key_ring_reset(ram, 0)
            key_ring_reset(ram, 1)
    elif item == 7:                                 # COMMAND LIST
        if p & 0x9F0:
            _sb(ram, s, 0x9F, ram.u8(s + 0x9F) + 1 & 1)
            _sb(ram, s, 0xA9, 3)
            cl.horizon_band(ram)
            if ram.u8(s + 0x9F):
                ram.put(0x800A8B3A, "B", 3)
            else:
                for off in (0xA7, 0x78, 0x79, 0x7A):
                    _sb(ram, s, off, 0)
        if ram.u8(s + 0x9F):
            mask = 1 << ram.u8(s + 0x84)
            if ram.s8(s + 0x80) == 0:
                mask |= 1 << ram.u8(s + 0x85)
            HOOKS.command_list(ram, mask, ram.u8(s + 0x84))
    elif item == 9:                                 # CPU DIFFICULTY
        back = _cycle(ram, s, 0x7E, 2)
    elif item == 10:                                # CPU LEVEL
        back = _cycle(ram, s, 0x7F, 9)
    elif item == 11:                                # restart the round (not in any menu)
        if p & 0x9F0:
            ram.put(ROUND_REQUEST, "I", 9)
            HOOKS.sound(ram, SND_MOVE)
    elif item == 12:                                # leave practice (not in any menu)
        if p & 0x9F0:
            ram.put(ROUND_REQUEST, "I", 0xB)
    elif item == 13:                                # TRAINING DUMMY
        back = _cycle(ram, s, 0x7D, 8)
    elif item == 14:                                # RETURN TO MODE SELECT
        if p & 0x9F0:
            _sb(ram, s, 0x75, 1)
            _sb(ram, s, 0xA9, 3)
            cl.horizon_band(ram)
            if ram.s8(s + 0x77) == 2:
                key_ring_reset(ram, ram.s8(s + 0x7B))
                replay_reset(ram, ram.s8(s + 0x7B))
    elif item == 15:                                # COMBO PLAYER
        if p & 0x9F0:
            back = True
        elif p & 0xA000:
            _sb(ram, s, 0x7B, ram.u8(s + 0x7B) + 1 & 1)
            _sb(ram, s, 0x7C, 0)
            _guide_changed(ram, s)
    elif item == 16:                                # COMBO TYPE
        if p & 0x9F0:
            back = True
        else:
            changed = False
            if p & 0x2000:
                changed = True
                _sb(ram, s, 0x7C, ram.u8(s + 0x7C) + 1)
            if _pressed(ram, s) & 0x8000:
                changed = True
                _sb(ram, s, 0x7C, ram.u8(s + 0x7C) - 1)
            v = ram.s8(s + 0x7C)
            if v < 0:
                _sb(ram, s, 0x7C, combo_count(ram, s) - 1)
            elif combo_count(ram, s) - 1 < v:
                _sb(ram, s, 0x7C, 0)
            if changed:
                _guide_changed(ram, s)
    if back and ram.s8(s + 0x77) in ITEM_ROWS:
        _sb(ram, s, ITEM_ROWS[ram.s8(s + 0x77)][1], 0)


def menu_input(ram: Ram) -> None:
    """FUN_800B4C44: MODE SELECT's choice, or the current page's item."""
    if ram.u8(_s(ram) + 0x75):
        _mode_select_confirm(ram)
    else:
        _item_input(ram)


SCREEN_RECT = 0x800AE6F8


def menu_backdrop(ram: Ram) -> None:
    """FUN_800B6DA0: the pause menu's dark blue panel (0, 16, 48) with a light grey frame:
    MODE SELECT (8, 40) 172 x 192, a page (64, 40) 240 x 316. Draw areas keep the fight scene
    from being drawn over the panel's rows."""
    s = _s(ram)
    ot = ds.ot0(ram)
    if ram.u8(s + 0x75):
        top, h = 0x28, 0xC0
        p = ds.tile(ram, ot, ds._pkt(ram), 0x60301000, 0x280008, 0xC000AC)
        ds._set_pkt(ram, ds.tile(ram, ot, p, 0x60E0E0E0, 0x260007, 0xC400AE))
    elif ram.u8(s + 0x77) < 3:
        top, h = 0x28, 0x13C
        p = ds.tile(ram, ot, ds._pkt(ram), 0x60301000, 0x280040, 0x13C00F0)
        ds._set_pkt(ram, ds.tile(ram, ot, p, 0x60E0E0E0, 0x26003F, 0x14000F2))
    else:
        return
    x, y, w, hh = (ram.u16(SCREEN_RECT + 2 * i) for i in range(4))
    y1 = top + h + 2
    scene = ram.u32(0x800A911C)
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ram.u32(scene + 4) + 8 & 0xFFFFFFFF, ds._pkt(ram), x, y1, w,
                                       y + hh - y1 & 0xFFFF))
    ds._set_pkt(ram, ds.draw_area(ram, ot, ds._pkt(ram), SCREEN_RECT))
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ram.u32(scene + 0x10), ds._pkt(ram), x, y1, w, y + hh - y1 & 0xFFFF))
