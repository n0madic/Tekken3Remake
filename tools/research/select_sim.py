#!/usr/bin/env python3
"""Integer port of the character select screen (`select.ovl`, game state 9; Japan Rev.1).

Like `menu_sim.py`, every routine writes the same RAM as the game, GPU packets and ordering
tables included, so `tools/research/verify_select_sim.py` compares all of RAM with the harness.
Sound, music, VRAM uploads and the big-portrait TIM loads are not ported (stubbed in the game).

Screen context `CTX` (0x80118C48):
  +0x00 mode, +0x04 layout (0: one row of portraits, 1: two rows), +0x08 frame counter,
  +0x0C cursor-moved flag, +0x10 NEW blink timer, +0x14/+0x18 slide timers,
  +0x1C unlocked mask, +0x20 unlocked count, +0x24/+0xA0 the two player records (0x7C bytes),
  +0x11C..+0x14C layout values (one of the two sets at 0x801108FC), +0x14C 64 sparks (20 bytes),
  +0x64C the big-portrait TIM buffer.
Grid cells `CELLS` (0x80129CE8, 22 x 12 bytes): +0 index, +1..+4 the cell reached with
up/down/left/right (0x16 = none), +5 shown, +6 s16 character (0x16 = locked), +8/+0xA s16 x, y.
"""

from __future__ import annotations

import draw_sim as ds
import menu_sim as ms
import screens_sim as ss
from fight_sim import Ram

CTX = 0x80118C48
CELLS = 0x80129CE8
CELL_SIZE = 12
NO_CELL = 0x16
GRID_KEYS = 0x800B9638           # the character of each of the 22 cells
DUMMY_CELL = 0x800B9650          # an all-0x16 cell for an empty row
CELL_STEP = 0x23                 # horizontal spacing of the portraits


class _Row:
    """The grid builder's per-row record (a stack struct in the game: +0 first cell, +4 current,
    +8 last, +0xC/+0xE x/y, +0x10 row, +0x11 phase, +0x12 odd, +0x13 middle, +0x14 skip,
    +0x15 remaining, +0x16 half, +0x17 total)."""

    def __init__(self, first: int, row: int, y: int) -> None:
        self.first = self.cur = self.last = first
        self.x, self.y = 0xB, y
        self.row, self.phase, self.odd, self.middle = row, 0, 0, NO_CELL
        self.skip = self.remaining = self.half = self.total = 0


def _cell(i: int) -> int:
    return CELLS + CELL_SIZE * (i & 0xFF)


def _vertical(ram: Ram, row: _Row, cell: int) -> int:
    """The cell's link toward the other row (up from the bottom row, down from the top)."""
    return ram.u8(cell + 1) if row.row else ram.u8(cell + 2)


def _row_step(ram: Ram, row: _Row, cell: int) -> int:
    """FUN_8010D810: place one cell of a row and return the cell to pair with next."""
    if row.phase >= 3:
        return cell
    if row.phase == 0:
        if row.skip:
            ram.put(cell + 3, "B", _vertical(ram, row, cell))
            row.skip = row.skip - 1 & 0xFF
            return cell
        if row.odd:
            ram.put(cell + 3, "B", _vertical(ram, row, cell))
        row.phase += 1
    if row.phase == 1:
        if row.remaining:
            if row.odd and row.remaining == row.middle:
                row.middle = 0xFF
                return cell
            ram.put(cell + 8, "H", row.x)
            ram.put(cell + 0xA, "H", row.y)
            row.remaining = row.remaining - 1 & 0xFF
            row.x = row.x + CELL_STEP & 0xFFFF
            if row.remaining:
                return _cell(ram.u8(cell + 4))
        row.phase += 1
    if row.odd:
        ram.put(cell + 4, "B", _vertical(ram, row, cell))
    elif row.half:
        ram.put(cell + 4, "B", ram.u8(_cell(_vertical(ram, row, cell)) + 4))
    row.phase += 1
    return cell


def _pair_rows(ram: Ram, a: _Row, b: _Row) -> None:
    """FUN_8010DA30: centre the shorter row under the longer one and link the rows vertically."""
    big, small = (b, a) if a.remaining < b.remaining else (a, b)
    if big.remaining == 0:
        big.cur, big.phase = DUMMY_CELL, 3
    if small.remaining:
        diff = big.remaining - small.remaining & 0xFFFFFFFF
        if diff & 1:
            small.odd = 1
        small.half = small.skip = diff >> 1 & 0xFF
        small.middle = (small.remaining >> 1) + 1
        small.x = small.x + ((10 - small.remaining) * CELL_STEP >> 1) & 0xFFFF
    else:
        small.cur, small.phase = DUMMY_CELL, 3
    c1, c0 = big.cur, small.cur
    for _ in range(big.remaining):
        if big.phase < 3:
            ram.put(c1 + (1 if big.row else 2), "B", ram.u8(c0))
        if small.phase < 3:
            ram.put(c0 + (1 if small.row else 2), "B", ram.u8(c1))
        c1 = _row_step(ram, big, c1)
        c0 = _row_step(ram, small, c0)


def grid_build(ram: Ram, ctx: int = CTX) -> None:
    """FUN_8010DC04: the portrait grid from the unlocked characters (cells 10 and 21 are hidden
    extras that only start the NEW blink)."""
    mask = ram.u32(ss.UNLOCKED) & 0x1FFFFF
    ram.put(ctx + 0x10, "I", 0)
    shown = 0
    for i in range(22):
        c = _cell(i)
        ram.put(c, "B", i)
        key = ram.u8(GRID_KEYS + i)
        if mask >> key & 1:
            ram.put(c + 6, "H", key)
            if i % 11 < 10:
                ram.put(c + 5, "B", 1)
            else:
                ram.put(c + 5, "B", 0)
                ram.put(ctx + 0x10, "I", 0xB4)
            shown |= 1 << key
        else:
            ram.put(c + 6, "H", NO_CELL)
            ram.put(c + 5, "B", 0)
        for k in range(1, 5):
            ram.put(c + k, "B", NO_CELL)
    ram.put(ctx + 0x20, "I", ss.popcount(shown))
    ram.put(ctx + 0x1C, "I", shown)
    rows = (_Row(_cell(0), 0, 0), _Row(_cell(11), 1, 0x3E))
    for row, base in zip(rows, (0, 11)):
        found = False
        last = row.first
        for k in range(11):
            c = _cell(base + k)
            if ram.s16(c + 6) == NO_CELL:
                continue
            if not found:
                row.cur, found = c, True
            else:
                ram.put(last + 4, "B", ram.u8(c))
                ram.put(c + 3, "B", ram.u8(last))
            row.total = row.total + 1 & 0xFF
            if k < 10:
                row.remaining = row.remaining + 1 & 0xFF
            last = c
        ram.put(last + 4, "B", ram.u8(row.cur))          # close the ring
        ram.put(row.cur + 3, "B", ram.u8(last))
        row.last = last
    ram.put(ctx + 4, "I", int(rows[1].remaining != 0))
    _pair_rows(ram, rows[0], rows[1])


# ---- per-player selection ----
PLAYER_LAYOUT = 0x800B9378       # 2 x 0x28 bytes copied to the record at +0x54
PLAYER_OFF, PLAYER_SIZE = 0x24, 0x7C
STATE_ANIM = 0x800B966C          # per state: the two bytes kept at +0x08/+0x0C
DECIDED = 0x800B965C             # per state: the costume-clash flags (+0x4C/+0x50)
PORTRAIT_ARCHIVE = 0x800B974C    # big-portrait compressed TIMs by attribute
ATTRS = 0x80097EDC               # per costume key: the character attribute byte
ATTR_SLOT = 0x800984E6           # per player: attribute & 0x1F (FUN_800527BC)
SND_MOVE, SND_CHOOSE, SND_CANCEL, SND_JOIN = 0x55F5, 0x50F4, 0x50F4, 0x49A1


def rec_of(ctx: int, player: int) -> int:
    return ctx + PLAYER_OFF + PLAYER_SIZE * player


def attribute(ram: Ram, key: int, costume: int) -> int:
    """FUN_8004BA28: the attribute byte of a costume (bits 0-4 portrait, 5 facing, 6-7 strip layout)."""
    if key > 0x15 or costume > 3:
        key, costume = 0x16, 0
    return ram.u8(ram.u32(ATTRS + 4 * (key * 4 + costume) & 0xFFFFFFFF))


def char_record(key: int, costume: int) -> int:
    """FUN_8004F2D8's index."""
    k = key << 2 | costume
    return 0x58 if k > 0x5C else k


def _find_cell(ram: Ram, key: int) -> int:
    if key < 0x16:
        for i in range(22):
            if ram.s16(_cell(i) + 6) == key:
                return i
    return -1


def player_start(ram: Ram, ctx: int, rec: int, player: int) -> None:
    """FUN_8010DF20: the starting cursor from the kept character (or the last choice)."""
    kind = (ram.u16(ss.PLAYER_ACTIVE + 2 * player) != 0) << 1 | (ram.u16(ss.KEEP_CHAR + 2 * player) != 0)
    if kind == 0:
        key, costume = NO_CELL, 0
    elif kind == 1:
        key, costume = ram.u16(0x800AE224 + 2 * player), ram.u16(0x800AE260 + 2 * player)
    else:
        if kind == 2:
            key, costume = ram.u32(rec + 0x3C), ram.u32(rec + 0x40)
        else:
            key, costume = ram.u16(0x800AE224 + 2 * player), ram.u16(0x800AE260 + 2 * player)
        i = _find_cell(ram, ds._s32(key))
        if i >= 0:
            ram.put(rec + 4, "I", i)
        else:
            i = ram.u16(rec + 0x78)
            ram.put(rec + 4, "I", i)
            key = ram.s16(_cell(i) + 6)
    ram.put(rec + 0x14, "I", NO_CELL)
    ram.put(rec + 0x1C, "I", key & 0xFFFFFFFF)
    ram.put(rec + 0x20, "I", costume & 0xFFFFFFFF)
    ram.put(rec + 0x18, "I", 1)


def costume_clash(ram: Ram, a: int, b: int) -> None:
    """FUN_8004F334 on (key, costume, decided, human) records: the same costume twice changes one."""
    if ram.u32(b + 8) and ram.u32(a) == ram.u32(b) and ram.u32(a + 4) == ram.u32(b + 4):
        c = ram.s32(a + 4)
        if ram.u32(b + 12) == 0 and ram.u32(a + 12):
            ram.put(b + 4, "I", c ^ 1 if c < 2 else 0)
        else:
            cb = ram.s32(b + 4)
            ram.put(a + 4, "I", cb ^ 1 if cb < 2 else 0)


def choose(ram: Ram, ctx: int, rec: int, pressed: int) -> int:
    """FUN_8010E0D8: a face button (or the time running out) picks the costume; 0 when chosen.

    □/✕ (0x80, 0x10...) costume 0, ○/△ (0x60) costume 1, Start or L1 (0x810) the Start costume when unlocked."""
    extra = 0x810 if ram.u32(0x800982D4) >> (ram.u32(rec + 0x1C) & 31) & 1 else 0
    if not (extra | 0xF0) & pressed and ram.u32(ctx + 0x14):
        return 1
    costume = 2 if extra & pressed else int(pressed & 0x60 != 0)
    key = ram.s32(rec + 0x1C)
    if key < 0x17:
        ram.put(rec + 0x20, "I", costume)
        for q in range(2):
            r = rec_of(ctx, q)
            ram.put(r + 0x44, "I", ram.u32(r + 0x1C))
            ram.put(r + 0x48, "I", ram.u32(r + 0x20))
            s = ram.u32(r)
            ram.put(r + 0x4C, "I", ram.u8(DECIDED + 2 * s))
            ram.put(r + 0x50, "I", ram.u8(DECIDED + 2 * s + 1))
        other = rec_of(ctx, 1) if rec == rec_of(ctx, 0) else rec_of(ctx, 0)
        costume_clash(ram, rec + 0x44, other + 0x44)
        for q in range(2):
            r = rec_of(ctx, q)
            ram.put(r + 0x1C, "I", ram.u32(r + 0x44))
            ram.put(r + 0x20, "I", ram.u32(r + 0x48))
        ram.put(rec + 0x3C, "I", ram.u32(rec + 0x1C))
        ram.put(rec + 0x40, "I", ram.u32(rec + 0x20))
    return int(key >= 0x16)


def _direction(ram: Ram, player: int, cell: int) -> int:
    """Pad direction to the neighbouring cell (repeat for left/right, repeat or press for up/down)."""
    rep = ram.u16(ss.PAD_REPEAT + 2 * player)
    v = rep & 0xAFFF | ram.u16(ss.PAD_PRESSED + 2 * player) & 0x5000
    if rep & 0xA000:
        v = rep & 0xA000
    link = {0x1000: 1, 0x4000: 2, 0x8000: 3, 0x2000: 4}.get(v)
    return ram.u8(_cell(cell) + link) if link else NO_CELL


def _move(ram: Ram, ctx: int, rec: int, pad: int) -> None:
    nxt = _direction(ram, pad, ram.u32(rec + 4))
    if nxt != NO_CELL:
        ram.put(rec + 4, "I", nxt)
        ram.put(rec + 0x20, "I", 0)
        ram.put(ctx + 0xC, "I", 2)
    ram.put(rec + 0x1C, "i", ram.s16(_cell(ram.u32(rec + 4)) + 6))


def player_step(ram: Ram, ctx: int, player: int) -> int:
    """FUN_8010E250: one player's selection; 1 when this side is done.

    States: 0 set-up, 1 choosing, 2 waiting for the other side, 3 choosing the other side's
    character (the other pad drives it), 4 CPU side (a challenger may join), 5 no fighter,
    6 chosen (90 frames or Start), 7 chosen by the other pad."""
    other = player + 1 & 1
    rec, orec = rec_of(ctx, player), rec_of(ctx, other)
    state = ram.u32(rec)
    done = 0
    if state == 0:
        for k in range(10):
            ram.put(rec + 0x54 + 4 * k, "I", ram.u32(PLAYER_LAYOUT + 0x28 * player + 4 * k))
        ram.put(rec + 0x2C, "I", 0)
        ram.put(rec + 0x28, "I", 0)
        n = ram.s32(ctx + 0x20)
        t = 0x3C if n < 11 else (n - 10) * 3 + 0x3C
        ram.put(ctx + 0x18, "i", t)
        ram.put(ctx + 0x14, "i", t * 20)
        ram.put(rec + 0x24, "I", 0)
        ram.put(rec + 0x30, "I", 0)
        if ram.u16(ss.KEEP_CHAR + 2 * player):
            ram.put(rec + 0x24, "I", 0x5A)
            ram.put(rec + 0x30, "I", 0x1C)
        player_start(ram, ctx, rec, player)
        mode = ram.u32(ctx)
        active = ram.u16(ss.PLAYER_ACTIVE + 2 * player)
        if mode in (3, 4, 8):
            ram.put(rec, "I", 1 if active else 5)
        elif mode == 5:
            ram.put(rec, "I", 1 if active else 2)
        else:
            kind = (active != 0) << 1 | (ram.u16(ss.KEEP_CHAR + 2 * player) != 0)
            ram.put(rec, "I", {0: 4, 1: 4, 2: 1, 3: 6}[kind])
    elif state == 1:
        _move(ram, ctx, rec, player)
        if choose(ram, ctx, rec, ram.u16(ss.PAD_PRESSED + 2 * player)) == 0:
            ram.put(rec + 0x24, "I", 0x5A)
            ram.put(rec + 0x30, "I", 0x1C)
            ram.put(rec, "I", 6)
    elif state == 2:
        if ram.u32(orec) == 6:
            ram.put(rec, "I", 3)
            ram.put(rec + 4, "I", ram.u32(orec + 4))
    elif state == 3:
        _move(ram, ctx, rec, other)
        if ram.u16(ss.PAD_PRESSED + 2 * other) & 0x100:          # Select: back to the other side's choice
            ram.put(orec, "I", 1)
            ram.put(rec, "I", 2)
            ram.put(ctx + 0xC, "I", 2)
            ram.put(rec + 0x1C, "I", NO_CELL)
            ram.put(rec + 0x20, "I", 0)
        elif choose(ram, ctx, rec, ram.u16(ss.PAD_PRESSED + 2 * other)) == 0:
            ram.put(rec + 0x24, "I", 0x5A)
            ram.put(rec + 0x30, "I", 0x1C)
            ram.put(rec, "I", 7)
    elif state == 4:
        if ram.u8(0x800AFF55) and ss.challenger_join(ram, player):
            ram.put(rec, "I", 0)
        else:
            done = 1
    elif state == 5:
        done = 1
    elif state in (6, 7):
        pad = player if state == 6 else other
        if ram.u16(ss.PAD_PRESSED + 2 * pad) & 0x800:
            ram.put(rec + 0x24, "I", 0)
        t = ram.s32(rec + 0x24)
        if t > 0:
            ram.put(rec + 0x24, "i", t - 1)
        else:
            done = 1
    s = ram.u32(rec)
    ram.put(rec + 8, "I", ram.u8(STATE_ANIM + 2 * s))
    ram.put(rec + 0xC, "I", ram.u8(STATE_ANIM + 2 * s + 1))
    return done


def commit(ram: Ram, mode_ctx: int, ctx: int) -> None:
    """FUN_8010E948: the chosen characters into the fight variables and the select memory."""
    for q in range(2):
        rec = rec_of(ctx, q)
        key, costume = ram.u32(rec + 0x3C), ram.u32(rec + 0x40)
        active = ram.u16(ss.PLAYER_ACTIVE + 2 * q)
        if ram.u32(mode_ctx) != 5 or active:
            ram.put(0x800982EE + q, "B", (key << 2 | costume & 3) & 0xFF)
        if active or ram.u32(ctx) == 5:
            ram.put(0x800AE224 + 2 * q, "H", key & 0xFFFF)
            ram.put(0x800AE260 + 2 * q, "H", costume & 0xFFFF)
            ram.put(ss.KEEP_CHAR + 2 * q, "H", 1)
            ram.put(0x800A95F0 + 2 * q, "H", 0)


class PortraitStub:
    """The big-portrait TIM load of FUN_8010EA2C (decompress into CTX+0x64C, upload to VRAM at the
    record's +0x58/+0x5A with CLUT +0x5C); VRAM only, so not ported."""

    def load(self, ram: Ram, rec: int, attr: int) -> None:
        pass


PORTRAIT = PortraitStub()


def portrait_update(ram: Ram, ctx: int) -> None:
    """FUN_8010EA2C: every other frame one side's big portrait follows its cursor."""
    n = ram.u32(ctx + 8) + 1 & 0xFFFFFFFF
    ram.put(ctx + 8, "I", n)
    p = n & 1
    rec = rec_of(ctx, p)
    if ram.u32(rec + 0x14) == ram.u32(rec + 0x1C) and ram.u32(rec + 0x18) == ram.u32(rec + 0x20):
        return
    key, costume = ram.s32(rec + 0x1C), ram.s32(rec + 0x20)
    ram.put(rec + 0x14, "I", key & 0xFFFFFFFF)
    ram.put(rec + 0x18, "I", costume & 0xFFFFFFFF)
    attr = attribute(ram, key, costume)
    r = ram.u32(ss.CHAR_RECORDS + 4 * char_record(key, costume))
    ram.put(rec + 0x2C, "I", ram.u8(r + 5))
    ram.put(rec + 0x28, "I", ram.u8(r + 4))
    facing_right = ram.u16(rec + 0x60) == 1
    flip = bool(attr & 0x20) != facing_right and ram.u32(rec + 0x14) != NO_CELL
    ram.put(rec + 0x10, "I", int(flip))
    ram.put(ATTR_SLOT + p, "B", attr & 0x1F)
    PORTRAIT.load(ram, rec, attr & 0xFFFFFF1F)


# ---- drawing ----
PORTRAIT_BANDS = 0x80118B9C      # per strip layout (attribute >> 6): three band heights
BAND_SHADES = 0x80118BCC         # 4 brightness weights (x/32) at the band edges
BG_ROWS = 0x80118BDC             # 8 rows x 8 tile indices of the scrolling background
BG_TILES = 0x80118C1C            # uv|clut per background tile
BG_SCROLL = 0x80118C44
SMALL_FACES = 0x800B93C8         # one-row layout: per character u32 uv|clut, u16 tpage
IMAGE_LISTS = (0x800B9418, 0x800B9528)   # static pictures per layout (mode, sx, sy, w, h, vx, vy, clut)
LAYOUTS = 0x801108FC             # 2 x 12 words copied to CTX+0x11C
CAPTIONS = {3: 0x800B96C4, 4: 0x800B96D4, 5: 0x800B96E0, 8: 0x800B96EC}   # TIME ATTACK! ...
STR_NONE, STR_CAPTION = 0x800B96FC, 0x800B9700
SPARKS, SPARK_SIZE, SPARK_COUNT = 0x14C, 20, 64
SELECT_PACKETS = 0x801210DC      # + buffer * 0x4600
GREY = 0x7F7F7F


def _xy(x: int, y: int) -> int:
    return x & 0xFFFF | (y & 0xFFFF) << 16


def _screen_rect(ram: Ram) -> list[int]:
    return [ram.u16(ss_rect) for ss_rect in (0x800AE6F8, 0x800AE6FA, 0x800AE6FC, 0x800AE6FE)]


def new_arrows(ram: Ram, ctx: int) -> None:
    """FUN_8010EC9C: while a new character was just added, blinking arrows at the grid's ends."""
    p = ds._pkt(ram)
    t = ram.u32(ctx + 0x10)
    if t:
        ram.put(ctx + 0x10, "I", t - 1)
        y = ram.s32(ctx + 0x128) - 0xA0
        if ram.s32(ctx + 0x24) < 4 or ram.s32(ctx + 0xA0) < 4:
            f = ram.u32(ds.FRAME_COUNT)
            v = f << 4 & 0x1FF
            if v >= 0x100:
                v = 0x1FF - v
            c = v | v << 8 | v << 16 | 0x64000000
            d = f & 0x1F
            if d >= 0x11:
                d = 0x1F - d
            d >>= 1
            ot = ds.ot0(ram)
            p = ds.sprt(ram, ot, p, c, _xy(0xC - d, y), 0x10000A, 0x7E1500E0)
            p = ds.sprt(ram, ot, p, c, _xy(0x15A + d, y), 0x10000A, 0x7E1500EA)
            p = ds.dr_mode(ram, ot, p, 0x19)
    ds._set_pkt(ram, p)


def name_plates(ram: Ram, ctx: int) -> None:
    """FUN_8010EDFC: each side's name plate (kind 2 adds the start prompt, 3 the mode caption)."""
    ot = ds.ot0(ram)
    y = ram.s32(ctx + 0x124)
    for p_ in range(2):
        rec = rec_of(ctx, p_)
        x = ram.u16(rec + 0x56)
        kind = ram.s32(rec + 0xC)
        if kind == 2:
            ds.hud_coin(ram, p_, x, 0x22, ram.u32(ctx + 0x148))
        if kind in (1, 2):
            w = ram.u32(rec + 0x2C)
            if w:
                n = ram.u32(rec + 0x28)
                uv = (n << 3 & 0x80) | (n & 0xF) << 12 | 0x7CA50000
                q = ds.sprt(ram, ot, ds._pkt(ram), 0x65000000, _xy(x - (w >> 1), y), w & 0xFFFF | 0x100000, uv)
                ds._set_pkt(ram, ds.dr_mode(ram, ot, q, 0xB))
        elif kind == 3:
            mode = ram.u32(ctx)
            if mode >= 9:
                raise NotImplementedError("caption for mode >= 9 (the game uses a stale register)")
            s = CAPTIONS.get(mode, STR_NONE)
            w = ds.strlen(ram, s) * 0xD
            x0 = x - (w >> 1)
            if x0 < 8:
                x0 = 8
            if x0 + w > 0x168:
                x0 = 0x168 - w
            ds.text(ram, STR_CAPTION, 5, 1, x0, y - 0x1E, s)


def _spark_draw(ram: Ram, ot: int, p: int, s: int) -> int:
    """FUN_8010F020: a rising, fading vertical streak."""
    f = ram.u16(ds.FRAME_COUNT)
    if ram.u16(s + 2) == 0:
        ram.put(s + 0xC, "I", 0x60)
        ram.put(s + 0xA, "H", f)
        ram.put(s + 2, "H", 1)
        ram.put(s + 0x10, "I", (ss.lcg2(ram) & 3) + 4)
    elif ram.u16(s + 2) != 1:
        return p
    b = ram.s32(s + 0xC) - ram.s32(s + 0x10)
    ram.put(s + 0xC, "i", b)
    ram.put(s + 6, "H", ram.u16(s + 8) - ((f - ram.u16(s + 0xA)) << 4) & 0xFFFF)
    y = ram.s16(s + 6)
    if y + 0xA0 < 0 or b <= 0:
        ram.put(s, "H", 0)
        return p
    a = b & 0xFF
    x = ram.s16(s + 4)
    p = ds.poly_g4(ram, ot, p, 0x3A000000 | a * 0x10101, a * 0x10101, a << 16, a << 16,
                   ram.u16(s + 4) | (y & 0xFFFF) << 16, _xy(x + 1, y), _xy(x, y + 0xA0), _xy(x + 1, y + 0xA0))
    return ds.dr_mode(ram, ot, p, 0x20)


def sparks(ram: Ram, ctx: int) -> None:
    """FUN_8010F1B4: every 4th frame a new streak rises from alternating portraits, clipped above the plates."""
    ot = ds.ot0(ram)
    p = ds._pkt(ram)
    n = ram.u32(ctx + 8)
    if n & 3 == 0:
        k = n >> 3 & 3
        k = (k << 1 | k >> 1) & 3
        rec = rec_of(ctx, n >> 2 & 1)
        free = 0
        for i in range(SPARK_COUNT):
            s = ctx + SPARKS + SPARK_SIZE * i
            if ram.u16(s) == 0:
                ram.put(s + 2, "H", 0)
                free = s
                break
        if free:
            r = ss.lcg2(ram)
            a = k << 10 | (ds._s32(r) >> 2 & 0x3FF)
            ram.put(free, "H", 1)
            ram.put(free + 4, "H", ram.u16(rec + 0x54) + (a * 0x7E >> 12) & 0xFFFF)
            y = ram.u16(ctx + 0x124)
            ram.put(free + 8, "H", y)
            ram.put(free + 6, "H", y)
    rect = _screen_rect(ram)
    p = ds.draw_area_xywh(ram, ot, p, *rect)
    for i in range(SPARK_COUNT):
        s = ctx + SPARKS + SPARK_SIZE * i
        if ram.u16(s) == 1:
            p = _spark_draw(ram, ot, p, s)
    rect[3] = ram.u16(ctx + 0x128) - 0x12 - rect[1] & 0xFFFF
    ds._set_pkt(ram, ds.draw_area_xywh(ram, ot, p, *rect))


def _uvs(u: int, v: int, du: int, dv: int, clut: int, tpage: int) -> tuple[int, int, int]:
    uv0 = u & 0xFF | (v & 0xFF) << 8 | clut << 16
    uv1 = u + du & 0xFF | (v & 0xFF) << 8 | tpage << 16
    b = (v + dv & 0xFF) << 8
    return uv0 & 0xFFFFFFFF, uv1 & 0xFFFFFFFF, (u & 0xFF | b | (u + du & 0xFF | b) << 16) & 0xFFFFFFFF


def _strip(ram: Ram, ot: int, p: int, b0: int, b1: int, x: int, y: int, w: int, h: int, u: int, v: int,
           du: int, dv: int, clut: int, tpage: int) -> int:
    """FUN_8010F38C: one band of a portrait, fading from brightness b0 (top) to b1 (bottom);
    below full brightness it is drawn twice, adding (CLUT) and subtracting (CLUT 0x7FD0)."""
    c0, c1 = ds.scale_colour(GREY, b0), ds.scale_colour(GREY, b1)
    xy = (_xy(x, y), _xy(x + w, y), _xy(x, y + h), _xy(x + w, y + h))
    if b0 == b1:
        if b0 >= 0x100:
            uv0, uv1, uv23 = _uvs(u, v, du, dv, clut, tpage)
            return ds.poly_ft4(ram, ot, p, 0x2D000000, *xy, uv0, uv1, uv23)
        if b0 == 0:
            return p
        uv0, uv1, uv23 = _uvs(u, v, du, dv, clut, tpage | 0x20)
        p = ds.poly_ft4(ram, ot, p, c0 | 0x2E000000, *xy, uv0, uv1, uv23)
        uv0, uv1, uv23 = _uvs(u, v, du, dv, 0x7FD0, tpage | 0x40)
        return ds.poly_ft4(ram, ot, p, c0 | 0x2E000000, *xy, uv0, uv1, uv23)
    uv0, uv1, uv23 = _uvs(u, v, du, dv, clut, tpage | 0x20)
    p = ds.poly_gt4(ram, ot, p, c0 | 0x3E000000, c0, c1, c1, *xy, uv0, uv1, uv23)
    uv0, uv1, uv23 = _uvs(u, v, du, dv, 0x7FD0, tpage | 0x40)
    return ds.poly_gt4(ram, ot, p, c0 | 0x3E000000, c0, c1, c1, *xy, uv0, uv1, uv23)


def portraits(ram: Ram, ctx: int) -> None:
    """FUN_8010F760: both big portraits (126 x 208, three bands, a CLUT per 64 lines), sliding in."""
    ot = ds.ot0(ram)
    p = ds._pkt(ram)
    for pl in range(2):
        rec = rec_of(ctx, pl)
        x = ram.u16(rec + 0x54)
        y = ram.s32(ctx + 0x120)
        u = ram.u16(rec + 0x58) << 1 & 0x7F
        v = ram.u16(rec + 0x5A)
        if ram.u32(rec + 0x10) == 1:
            x, dx = x + 0x7E, -0x7E
        else:
            dx = 0x7E
        slide = ram.s32(rec + 0x30)
        if slide:
            k = 0x20 - slide
            ram.put(rec + 0x30, "i", slide - 1)
        else:
            k = 0x20
        limit, acc, clut_step = 0x40, 0, 0
        xa, xb = x & 0xFFFF, x + dx & 0xFFFF
        clut, tpage = ram.u16(rec + 0x5C), ram.u16(rec + 0x5E)
        attr = attribute(ram, ram.s32(rec + 0x14), ram.s32(rec + 0x18))
        bands = PORTRAIT_BANDS + (attr >> 6) * 12
        w_prev = ram.s32(BAND_SHADES)
        for band in range(3):
            b0 = ds._s32(w_prev * k) >> 5
            w_prev = ram.s32(BAND_SHADES + 4 + 4 * band)
            b1 = ds._s32(w_prev * k) >> 5
            left = ram.s32(bands + 4 * band)
            while left:
                ur = u + 0x7D
                if (acc + left) & 0xFFFFFFFF > limit:
                    clut_step = 4
                    h = limit - acc
                    limit += 0x40
                else:
                    h = left
                if h:
                    if attr == 0x15:
                        c0, c1 = ds.scale_colour(GREY, b0), ds.scale_colour(GREY, b1)
                        xy = (_xy(xa, y), _xy(xb, y), _xy(xa, y + h), _xy(xb, y + h))
                        vb = (v + h & 0xFF) << 8
                        uv0 = u & 0xFF | (v & 0xFF) << 8 | clut << 16
                        uv1 = ur | (v & 0xFF) << 8 | (tpage | 0x40) << 16
                        uv23 = (u & 0xFF | vb | (ur | vb) << 16) & 0xFFFFFFFF
                        if b0 == b1:
                            if b1:
                                p = ds.poly_ft4(ram, ot, p, c0 | 0x2E000000, *xy, uv0, uv1, uv23)
                        else:
                            p = ds.poly_gt4(ram, ot, p, c0 | 0x3E000000, c0, c1, c1, *xy, uv0, uv1, uv23)
                    else:
                        p = _strip(ram, ot, p, b0, b1, x, y, dx, h, u, v, 0x7D, h, clut, tpage)
                y += h
                v += h
                left -= h
                clut += clut_step
                acc += h
                clut_step = 0
    ds._set_pkt(ram, p)


def backlights(ram: Ram, ctx: int) -> None:
    """FUN_8010FBFC: the coloured glow behind each portrait (the colour follows the attribute byte)."""
    ot = ds.ot0(ram)
    p = ds._pkt(ram)
    for pl in range(2):
        rec = rec_of(ctx, pl)
        key, costume = ram.s32(rec + 0x14), ram.s32(rec + 0x18)
        if key > 0x15 or costume > 3:
            key, costume = 0x16, 0
        c = ram.u32(ram.u32(ATTRS + 4 * (key * 4 + costume) & 0xFFFFFFFF)) >> 8
        x = ram.u16(rec + 0x54)
        xr = x + 0x7E & 0xFFFF
        y = ram.s32(ctx + 0x120)
        top, mid, bot = (y - 0x14) << 16 & 0xFFFFFFFF, (y + 0xD0) << 16 & 0xFFFFFFFF, (y + 0x118) << 16 & 0xFFFFFFFF
        p = ds.poly_g4(ram, ot, p, 0x3A000000, 0, c, c, x | top, xr | top, x | mid, xr | mid)
        p = ds.poly_g4(ram, ot, p, c | 0x3A000000, c, 0xC0C0C0, 0xC0C0C0, x | mid, xr | mid, x | bot, xr | bot)
        p = ds.dr_mode(ram, ot, p, 0x20)
    ds._set_pkt(ram, p)


def grid_faces(ram: Ram, ctx: int) -> None:
    """FUN_8010FD64: the portrait grid (small faces; the two-row layout uses the HUD portraits)."""
    ot = ds.ot0(ram)
    p = ds._pkt(ram)
    dy = ram.s32(ctx + 0x12C)
    two_rows = ram.u32(ctx + 4)
    for i in range(22):
        c = _cell(i)
        key = ram.s16(c + 6)
        if not ram.u8(c + 5) or key >= 0x16:
            continue
        x, y = ram.s16(c + 8), ram.s16(c + 0xA) + dy
        if two_rows:
            p = ds.portrait(ram, ot, p, x, y, key << 2, 8)
        else:
            p = ds.sprt(ram, ot, p, 0x65000000, _xy(x, y), 0x440020, ram.u32(SMALL_FACES + 8 * key))
            p = ds.dr_mode(ram, ot, p, ram.u16(SMALL_FACES + 8 * key + 4))
    ds._set_pkt(ram, p)


def cursors(ram: Ram, ctx: int) -> None:
    """FUN_8010FEA0: each side's cursor frame on the grid (pulsing while choosing)."""
    ot4 = ds.ot0(ram) + 4
    p = ds._pkt(ram)
    level = layer = 0
    for pl in range(2):
        rec = rec_of(ctx, pl)
        kind = ram.u32(rec + 8)
        if kind == 0:
            continue
        if kind in (1, 3):
            layer, level = 2, ds.triangle_wave(ram.u32(ds.FRAME_COUNT) << 4)
        elif kind in (2, 4):
            layer, level = 0, 0x80
        c = _cell(ram.u32(rec + 4))
        if not ram.u8(c + 5):
            continue
        x = ram.s16(c + 8) - 2
        y = ram.s16(c + 0xA) + ram.s32(ctx + 0x12C)
        col = ds.scale_colour(0xFFFFFF, level)
        chosen = kind - 3 & 0xFFFFFFFF < 2
        uv = ram.u32(rec + 0x70) if chosen else ram.u32(rec + 0x6C)
        o = ot4 + 0xC
        p = ds.sprt(ram, o, p, col | 0x64000000, _xy(x + ram.u16(rec + 0x7A), y + ram.s32(ctx + 0x13C)), 0x100014, uv)
        p = ds.dr_mode(ram, o, p, 0xE)
        uv = ram.u32(rec + 0x64) if ram.u32(ctx + 4) == 0 else ram.u32(rec + 0x68)
        if chosen:
            uv = uv & 0xFFFF | 0x7CA90000
        y += ram.s32(ctx + 0x138)
        for i in range(2):
            o = ot4 + layer * 4 + (4 if i == pl else 0)
            p = ds.sprt(ram, o, p, col | 0x64000000, _xy(x, y), (ram.u32(ctx + 0x134) << 16 | 0x12) & 0xFFFFFFFF, uv)
            p = ds.dr_mode(ram, o, p, 0x19)
            x += 0x12
            uv = uv & 0xFFFFFF00 | uv + 0x12 & 0xFF
    ds._set_pkt(ram, p)


def pictures(ram: Ram, ctx: int) -> None:
    """FUN_80110154: the static pictures of the layout and the gradient under the grid."""
    ot = ds.ot0(ram)
    p = ds._pkt(ram)
    two_rows = ram.u32(ctx + 4)
    e = IMAGE_LISTS[1 if two_rows else 0]
    while ram.u16(e) != 0xFFFF:
        f = [ram.u16(e + 2 * k) for k in range(8)]
        p = ds.image(ram, ot, p, f[1], f[2], f[3], f[4], f[5], f[6], f[7], f[0])
        e += 16
    c = 0xD0 if two_rows else 0
    y0 = ram.s32(ctx + 0x128) + 0x10
    top, bot = y0 << 16 & 0xFFFFFFFF, 0x1E00000
    ds._set_pkt(ram, ds.poly_g4(ram, ot, p, 0x38000000, 0, c, c, top, top | 0x170, bot, bot | 0x170))


def background(ram: Ram, ctx: int) -> None:
    """FUN_801102A0: the diagonally scrolling tile background above the grid and the title pictures."""
    ot = ds.ot0(ram)
    rect = _screen_rect(ram)
    p = ds.draw_area_xywh(ram, ot, ds._pkt(ram), *rect)
    s = -(ram.u32(ds.FRAME_COUNT) << 7) & 0xFFFFFFFF
    ram.put(BG_SCROLL, "I", s)
    v = ds._s32(s) >> 4
    frac = 0x40 - v & 0x3F
    h = 0x40 - frac
    row = 7 - (v - 1 >> 6)
    y = ram.s16(0x800AE6FA)
    while y < 0x155:
        pat = BG_ROWS + (row & 7) * 8
        x, du, w = 0, 8, 0x28
        for _ in range(8):
            uv = ram.u32(BG_TILES + 4 * ram.u8(pat))
            pat += 1
            if du:
                uv += du
            if frac:
                uv += frac << 8
            p = ds.sprt(ram, ot, p, 0x65000000, _xy(x, y), w | h << 16, uv & 0xFFFFFFFF)
            x += w
            w, du = 0x30, 0
        y += h
        h, frac = 0x40, 0
        row += 1
    p = ds.dr_mode(ram, ot, p, 0x18)
    rect[3] = ram.u16(ctx + 0x128) - rect[1] & 0xFFFF
    p = ds.draw_area_xywh(ram, ot, p, *rect)
    p = ds.image(ram, ot, p, 0x80, 0x3A, 0x6E, 0x20, 0x24D, 0x112, 0x7CA4, 0)
    p = ds.image(ram, ot, p, 0x54, 0x62, 0xC6, 0xE, 0x242, 0x13A, 0x7CA4, 0)
    p = ds.image(ram, ot, p, 0x80, 0x78, 0x70, 0x1E, 0x24D, 0x150, 0x7CA4, 0)
    ds._set_pkt(ram, ds.tile(ram, ot, p, 0x60000000, 0, (ram.u32(ctx + 0x128) << 16 | 0x170) & 0xFFFFFFFF))


def select_draw(ram: Ram, ctx: int = CTX) -> None:
    """The drawing half of FUN_8011056C (from the third frame on)."""
    sparks(ram, ctx)
    portraits(ram, ctx)
    new_arrows(ram, ctx)
    d = ram.s32(ctx + 0x18)
    ds.hud_timer(ram, ds._sdiv(ram.s32(ctx + 0x14) + d - 1, d), 0xB8, ram.u32(ctx + 0x140), ram.u32(ctx + 0x144))
    name_plates(ram, ctx)
    cursors(ram, ctx)
    grid_faces(ram, ctx)
    pictures(ram, ctx)
    t = ram.s32(ctx + 0xC)
    if t > 0:
        ram.put(ctx + 0xC, "i", t - 1)
    else:
        rect = _screen_rect(ram)
        rect[3] = ram.u16(ctx + 0x128) - rect[1] & 0xFFFF
        ds._set_pkt(ram, ds.draw_area_xywh(ram, ds.ot0(ram), ds._pkt(ram), *rect))
    backlights(ram, ctx)
    background(ram, ctx)


def character_select(ram: Ram, ctx: int = CTX) -> int:
    """FUN_8011056C (game state 9)."""
    if ram.s16(ss.SUB_STATE) > 0 and ram.s32(ctx + 8) >= 3 and ss.menu_exit(ram):
        return 1
    sub = ram.s16(ss.SUB_STATE)
    if sub == 0:
        ms.music_stop(ram, 0x14)
        ms.sound_slots_stop(ram, 1)
        ram.put(ctx, "I", ram.u32(ds.MODE))          # (after the archive upload into CTX)
        grid_build(ram, ctx)
        lay = LAYOUTS + ram.u32(ctx + 4) * 0x30
        for k in range(12):
            ram.put(ctx + 0x11C + 4 * k, "I", ram.u32(lay + 4 * k))
        ram.put(ctx + 8, "I", 0)
        ram.put(ctx + 0xC, "I", 2)
        for p in range(2):
            rec = rec_of(ctx, p)
            ram.put(rec, "I", 0)
            b = ram.u8(0x800982EE + p)
            ram.put(rec + 0x3C, "I", b >> 2)
            ram.put(rec + 0x40, "I", b & 3)
            player_step(ram, ctx, p)
        for i in range(SPARK_COUNT):
            ram.put(ctx + SPARKS + SPARK_SIZE * i, "I", 0)
        ram.put(ss.SUB_STATE, "H", 1)
    elif sub == 1:
        t = ram.s32(ctx + 0x14)
        if t > 0:
            ram.put(ctx + 0x14, "i", t - 1)
        a = player_step(ram, ctx, 0) != 0
        b = player_step(ram, ctx, 1)
        if a and b:
            ram.put(ss.SUB_STATE, "H", 2)
    elif sub == 2:
        commit(ram, ds.MODE, ctx)
        ram.put(ss.GAME_STATE, "H", ram.u8(ds.MODE + 0x14))
        ram.put(ss.SUB_STATE, "H", ram.u8(ds.MODE + 0x15))
    portrait_update(ram, ctx)
    saved = ds._pkt(ram)
    ds._set_pkt(ram, SELECT_PACKETS + ram.u32(ds.DISPLAY_BUFFER) * 0x4600)
    if ram.s32(ctx + 8) >= 3:
        select_draw(ram, ctx)
    ds._set_pkt(ram, saved)
    return 0


# ==== quick select (game state 10, resident 0x80055878) ====
QCTX = 0x800B9378                # +0 mode, +8 fade-in flag, +0xC fade level; records at +0x18 (0xAC each)
QREC_OFF, QREC_SIZE = 0x18, 0xAC
QGRID = 0x800229D4               # 3 rows x 7 cells: s16 x, s16 y, u8 costume key (char << 2), pad
QPLAYER_PREFS = 0x80098540       # per player 0x34 bytes copied to the record at +0x78
QSTATE_ANIM = 0x80022A90         # per state three bytes kept at +0x18/+0x1C/+0x20
QDECIDED = 0x80022A70            # per state the costume-clash flags
QUICK_PACKETS = 0x800B94E8       # QCTX + 0x170 + buffer * 0x3C00
LOCKED_KEY, TAKEN_KEY = 0x58, 0x59


def qrec_of(qctx: int, player: int) -> int:
    return qctx + QREC_OFF + QREC_SIZE * player


def _qcell(col: int, row: int) -> int:
    return QGRID + 6 * (col + row * 7 & 0xFFFFFFFF)


def _qstart_cursor(ram: Ram, rec: int, player: int) -> None:
    """The common set-up: one member, the kept character (or the last pick) under the cursor."""
    ram.put(rec + 0x2C, "I", 0)
    ram.put(rec + 0x28, "I", 1)
    ram.put(rec + 0x30, "I", 1)
    if ram.u16(ss.KEEP_CHAR + 2 * player):
        ram.put(rec + 0x2C, "I", 1)
        key = ram.u16(0x800AE224 + 2 * player) * 4 + ram.u16(0x800AE260 + 2 * player)
        ram.put(rec + 0x38, "I", key)
    else:
        key = ram.s32(rec + 0x64)
        ram.put(rec + 0x38, "I", LOCKED_KEY)
    _qfind(ram, rec, key)


def _qfind(ram: Ram, rec: int, key: int) -> None:
    target = key & ~3 if ds._s32(key) < 0x58 else ram.u32(rec + 0x84)
    for row in range(3):
        for col in range(7):
            if ram.u8(_qcell(col, row) + 4) == target & 0xFFFFFFFF:
                ram.put(rec + 8, "I", col)
                ram.put(rec + 0xC, "I", row)
                return


def _qundo(ram: Ram, rec: int) -> bool:
    """Select: take back the last picked team member (its character becomes available again)."""
    n = ram.s32(rec + 0x2C)
    if n <= 0:
        return False
    n -= 1
    key = ram.s32(rec + 0x38 + 4 * n)
    ram.put(rec + 0x64, "i", key)
    ram.put(rec + 0x38 + 4 * n, "I", LOCKED_KEY)
    ram.put(rec + 0x24, "I", ram.u32(rec + 0x24) | 1 << (key >> 2 & 31))
    ram.put(rec + 0x2C, "i", n)
    return True


def quick_pick(ram: Ram, qctx: int, rec: int, pressed: int) -> int:
    """FUN_800530CC: pick the character under the cursor; 0 when the team is complete."""
    key = ram.u8(_qcell(ram.u32(rec + 8), ram.u32(rec + 0xC)) + 4)
    c = key >> 2
    if not ram.u32(rec + 0x24) >> (c & 31) & 1:
        key = TAKEN_KEY if ram.u32(ss.UNLOCKED) >> (c & 31) & 1 else LOCKED_KEY
        c = key >> 2
    extra = 0x810 if ram.u32(0x800982D4) >> (c & 31) & 1 else 0
    if not (extra | 0xF0) & pressed:
        return 1
    costume = 2 if extra & pressed else int(pressed & 0x60 != 0)
    k = key + costume
    if key < 0x58:
        n = ram.u32(rec + 0x2C)
        ram.put(rec + 0x38 + 4 * n, "I", k)
        if ram.u32(qctx) != 2:
            for q in range(2):
                r = qrec_of(qctx, q)
                m = ram.u32(r + 0x38)
                ram.put(r + 0x68, "I", m >> 2)
                ram.put(r + 0x6C, "I", m & 3)
                s = ram.u32(r)
                ram.put(r + 0x70, "I", ram.u8(QDECIDED + 2 * s))
                ram.put(r + 0x74, "I", ram.u8(QDECIDED + 2 * s + 1))
            other = qrec_of(qctx, 1) if rec == qrec_of(qctx, 0) else qrec_of(qctx, 0)
            costume_clash(ram, rec + 0x68, other + 0x68)
            for q in range(2):
                r = qrec_of(qctx, q)
                ram.put(r + 0x38, "I", (ram.u32(r + 0x68) << 2 | ram.u32(r + 0x6C) & 3) & 0xFFFFFFFF)
            k = ram.u32(rec + 0x38 + 4 * n)
        ram.put(rec + 0x64, "I", k)
        ram.put(rec + 0x2C, "I", ram.u32(rec + 0x2C) + 1)
        ram.put(rec + 0x24, "I", ram.u32(rec + 0x24) & ~(1 << (ds._s32(k) >> 2 & 31)) & 0xFFFFFFFF)
    return int(ram.u32(rec + 0x2C) < ram.u32(rec + 0x28))


def _qmove(ram: Ram, rec: int, pad: int) -> None:
    rep = ram.u16(ss.PAD_REPEAT + 2 * pad)
    col, row = ram.u32(rec + 8), ram.u32(rec + 0xC)
    if col >= 7:
        col = 0
    if row >= 3:
        row = 0
    lr = (rep >> 13 & 1) - (rep >> 15)
    if lr:
        t = col + lr & 0xFFFFFFFF
        col = t if t < 7 else 6 - col
    else:
        t = row + (rep >> 14 & 1) - (rep >> 12 & 1) & 0xFFFFFFFF
        if t < 3:
            row = t
    ram.put(rec + 8, "I", col & 0xFFFFFFFF)
    ram.put(rec + 0xC, "I", row & 0xFFFFFFFF)


class BallScene:
    """The 3D parts of Tekken Ball's quick select (volley.ovl): the ball renderer FUN_800B3198 (also
    used in the fight) and the scene set-up calls of FUN_800B5B6C (FUN_800B0DD8 lights/blend,
    FUN_80039BB4(5), SetBackColor(64, 64, 64)). Not ported; the verifier stubs them."""

    def render(self, ram: Ram, ball: int) -> None:
        pass

    def setup(self, ram: Ram) -> None:
        pass


BALL_SCENE = BallScene()
BALL_PTR = 0x800AE23C            # the ball object (fight heap)
BALL_NAMES = 0x800B6928          # per ball type: name, description (BEGINNER ... )
STR_BALL_DAMAGE, STR_BALL_PERCENT = 0x800B0B0C, 0x800B0B18


class BallHooks:
    """Tekken Ball's quick-select hooks in volley.ovl."""

    def setup(self, ram: Ram, mode_ctx: int, rec: int, player: int, arg: int) -> None:
        """FUN_800B5C4C: the side's handicap bar becomes the ball-damage choice (6 steps)."""
        ram.put(rec + 0x58, "I", 6)
        ram.put(rec + 0x10, "I", ram.u16(rec + 0x94))
        ram.put(rec + 0x14, "I", ram.u16(rec + 0x96))
        ram.put(rec + 0x5C, "I", ram.u16(rec + 0x9C))
        ram.put(rec + 0x60, "I", ram.u16(rec + 0x9C))
        ram.put(rec + 0x9A, "H", ram.u16(rec + 0x9A) + (0x28 if player else -0x28) & 0xFFFF)

    def start(self, ram: Ram) -> None:
        """FUN_800B5B6C: the ball preview scene (camera and ball state)."""
        ball = ram.u32(BALL_PTR)
        ram.put(ds.MODE + 0x43, "B", 0)
        BALL_SCENE.setup(ram)
        ram.put(ball + 0x8C, "I", 0x220)
        ram.put(ball + 0xB0, "H", 1)
        ram.put(ball + 0x146, "B", 10)
        for off in (0x68, 0x6C, 0x70, 0x78):
            ram.put(ball + off, "I", 0)
        for k in range(8):
            ram.put(0x800AE438 + 4 * k, "I", ram.u32(0x800AE460 + 4 * k))
        ram.put(0x800AE44C, "i", -0x40)
        ram.put(0x800AE450, "I", 0x440)
        ram.put(0x800AE454, "I", 0x1380)

    def side_select(self, ram: Ram) -> int:
        """FUN_800B569C: left/right spin the ball to the next damage type; a face button picks (1),
        Select backs out (-1); 0 while the ball turns."""
        p = ram.u8(ds.MODE + 0x40)
        ball = ram.u32(BALL_PTR)
        ram.put(ds.MODE + 0x43, "B", 3)
        ram.put(ball + 0x9A, "H", ram.u16(ball + 0x9A) + 8 & 0xFFFF)
        ram.put(ball + 0x98, "H", ram.u16(ball + 0x98) + 1 & 0xFFFF)
        a = ram.s32(ball + 0x68)
        a = a + (ram.s32(ball + 0x78) - a >> 3)
        ram.put(ball + 0x68, "i", a)
        ram.put(ball + 0x9C, "H", ram.u16(ball + 0x9C) + 2 & 0xFFFF)
        t = ram.u8(ds.MODE + 0x41)
        if a < -0x7FF and ram.s16(ball + 0xB0) == -1:
            t = 0 if t + 1 > 2 else t + 1
            ram.put(ds.MODE + 0x41, "B", t)
            ram.put(ball + 0x68, "I", 0x800)
            ram.put(ball + 0x78, "I", 0)
        if ram.s32(ball + 0x68) > 0x7FF and ram.s16(ball + 0xB0) == 1:
            ram.put(ds.MODE + 0x41, "B", 2 if t == 0 else t - 1)
            ram.put(ball + 0x68, "i", -0x800)
            ram.put(ball + 0x78, "I", 0)
        pressed = ram.u16(ss.PAD_PRESSED + 2 * p)
        if pressed & 0x8000:
            ram.put(ball + 0x78, "i", -0x1000)
            ram.put(ball + 0xB0, "H", 0xFFFF)
        if pressed & 0x2000:
            ram.put(ball + 0x78, "I", 0x1000)
            ram.put(ball + 0xB0, "H", 1)
        if abs(ram.s32(ball + 0x68) - ram.s32(ball + 0x78)) > 0x3F:
            return 0
        r = -1 if pressed & 0x100 else 0
        if ram.u32(ds.FRAME_COUNT) & 0x20:
            ot = ds.ot0(ram)
            p_ = ds.poly_f3(ram, ot, ds._pkt(ram), 0x2000FFFF, 0x14E00FC, 0x15E00FC, 0x1560104)
            ds._set_pkt(ram, ds.poly_f3(ram, ot, p_, 0x2000FFFF, 0x14E0074, 0x15E0074, 0x156006C))
        if pressed & 0xF0:
            r = 1
        return r

    def draw(self, ram: Ram) -> None:
        """FUN_800B593C: the spinning ball and, once it rests, its name, description and damage."""
        ball = ram.u32(BALL_PTR)
        ram.put(ball + 0x9A, "H", ram.u16(ball + 0x9A) + 8 & 0xFFFF)
        BALL_SCENE.render(ram, ball)
        if ram.u8(ds.MODE + 0x43) != 3 or abs(ram.s32(ball + 0x68) - ram.s32(ball + 0x78)) >= 0x40:
            return
        t = ram.u8(ds.MODE + 0x41)
        name, desc = ram.u32(BALL_NAMES + 8 * t), ram.u32(BALL_NAMES + 8 * t + 4)
        tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
        ds.strcpy(ram, tail, name)
        ds.text(ram, ds.SCRATCH, 0xB, 0, 0xB8 - ((ds.strlen(ram, name) * 9 & 0xFFFFFFFF) >> 1), 0x144)
        tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
        ds.strcpy(ram, tail, desc)
        ds.text(ram, ds.SCRATCH, 4, 1, 0xB8 - ((ds.strlen(ram, desc) * 0xD & 0xFFFFFFFF) >> 1), 0x156)
        tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
        ds.strcpy(ram, tail, STR_BALL_DAMAGE)
        ds.text(ram, ds.SCRATCH, 5, 0, 0x87, 0x19E)
        tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
        ds.strcpy(ram, tail, STR_BALL_PERCENT)
        ds.text(ram, ds.SCRATCH, 6, 1, 0xA0, 0x1B0, t * 0x14 + 0x3C, 0, 0xC9, 0x1B6)


BALL = BallHooks()


def quick_step(ram: Ram, mode_ctx: int, qctx: int, player: int) -> int:
    """FUN_800532E8: one player's quick select; 1 when this side is done.

    States: 0 set-up, 1 team size, 2 team members, 3 choosing, 4 VS handicap, 6/7 the other pad
    chooses for this side, 8 CPU side (a challenger may join), 9 team size from the other side,
    10-13 done, 14 waiting for the ball side select, 15 the ball side select."""
    other = player + 1 & 1
    rec, orec = qrec_of(qctx, player), qrec_of(qctx, other)
    state = ram.u32(rec)
    done = 0
    active = ram.u16(ss.PLAYER_ACTIVE + 2 * player)

    def setstate(s: int) -> None:
        ram.put(rec, "I", s)

    if state == 0:
        for k in range(0x34 // 4):
            ram.put(rec + 0x78 + 4 * k, "I", ram.u32(QPLAYER_PREFS + 0x34 * player + 4 * k))
        ram.put(rec + 0x24, "I", ram.u32(ss.UNLOCKED))
        mode = ram.u32(qctx)
        kind = (active != 0) << 1 | (ram.u16(ss.KEEP_CHAR + 2 * player) != 0)
        if mode in (0, 6, 7):
            if kind == 2:
                setstate(3)
            elif kind == 3:
                setstate(0xB if mode != 7 else 0xE)
            elif kind < 2:
                setstate(8)
            _qstart_cursor(ram, rec, player)
        elif mode in (3, 4, 8):
            setstate(3 if active else 0xA)
            _qstart_cursor(ram, rec, player)
        elif mode == 5:
            setstate(3 if active else 6)
            _qstart_cursor(ram, rec, player)
        elif mode == 1:
            setstate(3)
            _qstart_cursor(ram, rec, player)
        elif mode == 2:
            setstate(1 if active else 9)
            ram.put(rec + 0x2C, "I", 0)
            ram.put(rec + 0x28, "I", 4)
            ram.put(rec + 0x30, "I", 0)
            ram.put(rec + 0x34, "I", 0)
            for i in range(8):
                ram.put(rec + 0x38 + 4 * i, "I", LOCKED_KEY)
            ram.put(rec + 0x28, "I", ram.u8(mode_ctx + 0x65 + 13 * player))
            _qfind(ram, rec, LOCKED_KEY)
            ram.put(rec + 0x10, "I", ram.u16(rec + 0xA8))
            ram.put(rec + 0x14, "I", ram.u16(rec + 0xAA))
        if mode in (0, 3, 4, 5, 6, 8):
            ram.put(rec + 0x10, "I", ram.u16(rec + 0x90))
            ram.put(rec + 0x14, "I", ram.u16(rec + 0x92))
        elif mode in (1, 7):
            handicap = ram.u16(mode_ctx + 0x3A + 4 * player)
            ram.put(rec + 0x10, "I", ram.u16(rec + 0x94))
            ram.put(rec + 0x14, "I", ram.u16(rec + 0x96))
            ram.put(rec + 0x5C, "I", ram.u16(rec + 0x9C))
            ram.put(rec + 0x60, "I", ram.u16(rec + 0x9C))
            ram.put(rec + 0x58, "I", handicap)
            if mode == 7:
                BALL.setup(ram, mode_ctx, rec, player, ram.u16(rec + 0x9C))
    elif state == 1:
        rep = ram.u16(ss.PAD_REPEAT + 2 * player)
        n = ram.u32(rec + 0x28)
        lr = (rep >> 13 & 1) - (rep >> 15)
        if lr and (n + lr) & 0xFFFFFFFF < 9:
            n = n + lr
        if n >= 9:
            n = 8
        if n == 0:
            n = 1
        ram.put(rec + 0x28, "I", n)
        pressed = ram.u16(ss.PAD_PRESSED + 2 * player)
        if pressed & 0x8F0:
            ram.put(rec + 0x34, "I", int(pressed & 0x60 != 0))
            setstate(2)
    elif state in (2, 3):
        _qmove(ram, rec, player)
        pressed = ram.u16(ss.PAD_PRESSED + 2 * player)
        finish = False
        if state == 2 and pressed & 0x800:
            finish = True
        elif state == 2 and pressed & 0x100 and not _qundo(ram, rec):
            setstate(1)
        else:
            finish = quick_pick(ram, qctx, rec, pressed) == 0
        if finish:
            mode = ram.u32(qctx)
            if mode == 2:
                setstate(0xA)
            elif mode == 1:
                setstate(4)
            elif mode == 7:
                if ram.u8(mode_ctx + 0x43) == 0:
                    ram.put(mode_ctx + 0x43, "B", 1 << player)
                    setstate(0xF)
                    ram.put(mode_ctx + 0x40, "B", player)
                else:
                    setstate(0xE)
            elif mode < 9:
                setstate(0xB)
    elif state == 4:
        ram.put(rec + 0x5C, "I", ram.u16(rec + 0x9A))
        rep = ram.u16(ss.PAD_REPEAT + 2 * player)
        h = ram.u32(rec + 0x58)
        lr = (rep >> 13 & 1) - (rep >> 15)
        if ram.u32(mode_ctx) == 7:
            lr *= 2
        if lr:
            if ram.u16(rec + 0x98) == 0:
                lr = -lr
            if (h + lr) & 0xFFFFFFFF < 8:
                h = h + lr
        ram.put(rec + 0x58, "I", h)
        pressed = ram.u16(ss.PAD_PRESSED + 2 * player)
        if pressed & 0x100:
            ram.put(rec + 0x5C, "I", ram.u16(rec + 0x9C))
            _qundo(ram, rec)
            setstate(3)
        elif pressed & 0xF0:
            setstate(0xC)
    elif state == 6:
        if ram.u32(orec) == 0xB:
            ram.put(rec + 8, "I", ram.u32(orec + 8))
            setstate(7)
            ram.put(rec + 0xC, "I", ram.u32(orec + 0xC))
    elif state == 7:
        _qmove(ram, rec, other)
        pressed = ram.u16(ss.PAD_PRESSED + 2 * other)
        if pressed & 0x100:
            _qundo(ram, orec)
            setstate(6)
            ram.put(orec, "I", 3)
            for k in range(3):
                ram.put(orec + 0x18 + 4 * k, "I", ram.u8(QSTATE_ANIM + 9 + k))
        elif quick_pick(ram, qctx, rec, pressed) == 0:
            setstate(0xD)
    elif state in (8, 9):
        if state == 9:
            ram.put(rec + 0x28, "I", ram.u32(orec + 0x28))
        if ram.u8(0x800AFF55) and ss.challenger_join(ram, player):
            setstate(0)
        else:
            done = 1
    elif 10 <= state <= 13:
        done = 1
    elif state == 14:
        if ram.u16(ss.PAD_PRESSED + 2 * player) & 0x100:
            _qundo(ram, rec)
            setstate(3)
            if ram.u8(mode_ctx + 0x43) == 1 << player:
                ram.put(mode_ctx + 0x43, "B", 0)
        else:
            done = 1
    elif state == 15:
        r = BALL.side_select(ram)
        if r == 1:
            setstate(0xE)
        elif r == -1:
            _qundo(ram, rec)
            setstate(3)
            ram.put(0x800AFF93, "B", 0)
    s = ram.u32(rec)
    for k in range(3):
        ram.put(rec + 0x18 + 4 * k, "I", ram.u8(QSTATE_ANIM + 3 * s + k))
    return done


def quick_commit(ram: Ram, mode_ctx: int, qctx: int) -> None:
    """FUN_80054294: the picks into the fight variables (team battle: the member lists)."""
    for q in range(2):
        rec = qrec_of(qctx, q)
        active = ram.u16(ss.PLAYER_ACTIVE + 2 * q)
        if ram.u32(mode_ctx) != 5 or active:
            ram.put(0x800982EE + q, "B", ram.u8(rec + 0x64))
        mode = ram.u32(qctx)
        key = ram.s32(rec + 0x38)

        def fighter() -> None:
            ram.put(0x800AE224 + 2 * q, "H", key >> 2 & 0xFFFF)
            ram.put(0x800AE260 + 2 * q, "H", key & 3)

        if mode == 5:
            fighter()
            ram.put(0x800A95F0 + 2 * q, "H", 0)
            ram.put(ss.KEEP_CHAR + 2 * q, "H", 1)
        elif mode == 2:
            t = mode_ctx + 13 * q
            ram.put(t + 0x62, "B", 0)
            ram.put(t + 0x63, "B", ram.u8(rec + 0x2C))
            ram.put(t + 0x65, "B", ram.u8(rec + 0x28))
            ram.put(t + 0x64, "B", ram.u8(rec + 0x34))
            for i in range(8):
                ram.put(t + 0x59 + i, "B", ram.u8(rec + 0x38 + 4 * i))
            if active:
                ram.put(ss.KEEP_CHAR + 2 * q, "H", 1)
                ram.put(0x800A95F0 + 2 * q, "H", 0)
            else:
                ram.put(0x800A95F0 + 2 * q, "H", 1)
        elif mode < 9:
            if mode == 1:
                ram.put(mode_ctx + 0x3A + 4 * q, "H", ram.u16(rec + 0x58))
            if active:
                fighter()
                ram.put(ss.KEEP_CHAR + 2 * q, "H", 1)
                ram.put(0x800A95F0 + 2 * q, "H", 0)


# ---- quick select drawing ----
QTITLES = 0x800985A8             # per mode: PLAYER SELECT, VS BATTLE SELECT, TEAM BATTLE SELECT...
QPROMPT = 0x800985C0             # "PUSH START+SELECT TO EXIT"
QBANNER = 0x800985CC             # "THE KING OF IRON FIST TOURNAMENT 3"
QBANNER_FMT = 0x80022E00         # "%p%c%f%H%V%s"
QCAPTIONS = {3: 0x80022BD8, 4: 0x80022BE8, 5: 0x80022BF4, 8: 0x80022C00}
QCAPTION_WAIT = 0x80022C10     # PLEASE WAIT!
STR_NO_ENTRY, STR_SOLD_OUT = 0x80022B98, 0x80022BA4
STR_TEAM_SIZE = 0x80022BC0       # "%c%f%H%V%1x %s\n ON TEAM"
STR_PLAYER, STR_PLAYERS = 0x80022BB0, 0x80022BB8
STR_VS = 0x80022B78
QSTRIPES = 0x80022A54            # 7 stripe textures of the scrolling floor
QBACK_COLOURS = 0x80022DB8       # per mode: (lower gradient colour, upper gradient colour)


def _qkey_under_cursor(ram: Ram, rec: int) -> int:
    key = ram.u8(_qcell(ram.u32(rec + 8), ram.u32(rec + 0xC)) + 4)
    bit = 1 << (key >> 2 & 31)
    if not ram.u32(rec + 0x24) & bit:
        key = TAKEN_KEY if ram.u32(ss.UNLOCKED) & bit else LOCKED_KEY
    return key


def quick_members(ram: Ram, qctx: int) -> None:
    """FUN_8005447C: each side's picked team members (the member being chosen shows the cursor)."""
    ot = ds.ot0(ram) + 4
    p = ds._pkt(ram)
    for pl in range(2):
        rec = qrec_of(qctx, pl)
        x0, y0, kind = ram.u32(rec + 0x10), ram.u32(rec + 0x14), ram.u32(rec + 0x20)
        n = ram.s32(rec + 0x28)
        for i in range(max(n, 0)):
            key = ram.s32(rec + 0x38 + 4 * i)
            flags = 0
            if key > 0x57:
                key = LOCKED_KEY
            if kind == 1:
                flags = 0x84
            elif kind == 2:
                if i == ram.u32(rec + 0x2C):
                    flags = 0x10
            elif kind == 3:
                if i == ram.u32(rec + 0x2C):
                    key = min(_qkey_under_cursor(ram, rec), LOCKED_KEY)
            p = ds.portrait(ram, ot, p, x0 + (i & 3) * 0x24, y0 + (i >> 2) * 0x40, key, flags)
    ds._set_pkt(ram, p)


def quick_cursors(ram: Ram, qctx: int) -> None:
    """FUN_80054668: each side's cursor frame on the grid."""
    base = ds.ot0(ram) + 0xC
    p = ds._pkt(ram)
    for k in range(4):
        p = ds.draw_area(ram, base + 4 * k, p, 0x800AE6F8)
    level = ds.triangle_wave(ram.u32(ds.FRAME_COUNT) << 4)
    flags, colour, layer = 0, 0, 0
    for pl in range(2):
        rec = qrec_of(qctx, pl)
        cell = _qcell(ram.u32(rec + 8), ram.u32(rec + 0xC))
        sx, sy = ram.s16(cell), ram.u16(cell + 2)
        kind = ram.u32(rec + 0x18)
        if kind == 0:
            continue
        if kind in (1, 3):
            flags = ram.u32(rec + 0x78) | 0x10 if kind == 1 else 0x93
            colour = ds.scale_colour(0xFFFFFF, level)
            layer = 2
            if _qkey_under_cursor(ram, rec) > 0x57:
                flags = 0x90
        elif kind in (2, 4):
            flags = ram.u32(rec + 0x78) if kind == 2 else 0x83
            colour, layer = 0x808080, 0
        ot = base + 0x10
        if kind - 3 & 0xFFFFFFFF < 2:
            dx, uv = ram.s16(rec + 0x8A), ram.u32(rec + 0x80)
        else:
            dx, uv = ram.s16(rec + 0x88), ram.u32(rec + 0x7C)
        p = ds.sprt(ram, ot, p, colour | 0x64000000, (sx + dx) & 0xFFFF | (sy - 4) << 16 & 0xFFFFFFFF, 0x100014, uv)
        p = ds.dr_mode(ram, ot, p, 0xE)
        rx = sx
        for i in range(2):
            o = base + layer * 4 + (4 if i == pl else 0)
            p = ds.portrait_frame(ram, o, p, sx, sy, flags)
            p = ds.draw_area_xywh(ram, o, p, rx, sy, 0x12, 0x40)
            rx += 0x12
    ds._set_pkt(ram, p)


def _name_plate(ram: Ram, ot: int, p: int, x: int, y: int, w: int, colour: int) -> int:
    """FUN_8004E9EC: the textured plate under a name."""
    y0, y1 = y << 16 & 0xFFFFFFFF, (y + 10) << 16 & 0xFFFFFFFF
    x0, x1 = x & 0xFFFF, x + w & 0xFFFF
    return ds.poly_ft4(ram, ot, p, 0x2D000000, x0 | y0, x1 | y0, x0 | y1, x1 | y1,
                       ram.u16(ds.PLATE_COLOURS + 2 * colour) << 16 | 0xA8DC, 0xDA8DE, 0xB2DEB2DC)


def quick_texts(ram: Ram, qctx: int) -> None:
    """FUN_8005497C: per side the team-size choice, the name under the cursor, the start prompt or caption."""
    for pl in range(2):
        rec = qrec_of(qctx, pl)
        x, y = ram.u16(rec + 0x8C), ram.u16(rec + 0x8E)
        kind = ram.u32(rec + 0x1C)
        if kind == 1:
            y1, xx = ram.u32(rec + 0x14), ram.u32(rec + 0x10) + 8
            n = ram.u32(rec + 0x28)
            tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
            ram.put(tail + 1, "B", 0)
            for i in range(8):
                col = 10
                if n - 1 == i:
                    ds._set_pkt(ram, ds.tile(ram, ds.ot0(ram) + 0x1C, ds._pkt(ram), 0x600000FF,
                                             (xx - 2) & 0xFFFF | (y1 + 0x34) << 16 & 0xFFFFFFFF, 0x40011))
                    col = 1 if ram.u32(ds.FRAME_COUNT) & 2 else 6
                ram.put(tail, "B", 0x31 + i)
                ds.text(ram, ds.SCRATCH, col, 1, xx, y1 + 0x18)
                xx += 0x10
            ds.text(ram, STR_TEAM_SIZE, 5, 1, ram.u32(rec + 0x10) + 0xC, ram.u32(rec + 0x14) + 0x48, n,
                    STR_PLAYER if n < 2 else STR_PLAYERS)
        elif kind in (2, 3):
            if kind == 2:
                key = _qkey_under_cursor(ram, rec)
            else:
                n, done = ram.u32(rec + 0x28), ram.u32(rec + 0x2C)
                i = n - 1 if n <= done else done - 1 if ds._s32(done) > 0 else done
                key = ram.s32(rec + 0x38 + 4 * (i & 0xFFFFFFFF))
            tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
            if ds._s32(key) < 0x58 if kind == 3 else key < 0x58:
                named, s, col = True, ss.char_name(ram, key), 6
            elif key == 0x58:
                named, s, col = False, STR_NO_ENTRY, 9
            else:
                named, s, col = False, STR_SOLD_OUT, 5
            ds.strcpy(ram, tail, s)
            w = ds.strlen(ram, tail)
            x0 = x - (w * 0xD >> 1)
            ds.text(ram, ds.SCRATCH, col, 1, x0, y)
            if named:
                ds._set_pkt(ram, _name_plate(ram, ds.ot0(ram), ds._pkt(ram), x0 - 4, y + 0x12, w * 0xD + 10, key & 3))
        elif kind == 4:
            ds.hud_coin(ram, pl, x, y + 4, 10)
        elif kind == 5:
            mode = ram.u32(qctx)
            if mode >= 9:
                raise NotImplementedError("caption for mode >= 9 (the game uses a stale register)")
            s = QCAPTIONS.get(mode, QCAPTION_WAIT)
            n = ds.strlen(ram, s)
            w = n * 0xD
            x0 = x - (w >> 1)
            if x0 < 8:
                x0, right = 8, w + 8
            else:
                right = x0 + w
            if right > 0x168:
                x0 = 0x168 - n * 0xD
            ds.text(ram, STR_CAPTION_Q, 5, 1, x0, y, s)


STR_CAPTION_Q = 0x80022C20       # "%c%f%H%V%s"


def quick_title(ram: Ram, qctx: int) -> None:
    """FUN_80054E30: the screen title; after 480 idle frames it slides out and the exit hint slides in."""
    if ram.u16(ss.PAD_HELD) == 0 and ram.u16(ss.PAD_HELD + 2) == 0:
        ram.put(qctx + 4, "I", ram.u32(qctx + 4) + 1)
    else:
        ram.put(qctx + 4, "I", 0)
    t = ram.u32(qctx + 4)
    u = t - 0x1E0 & 0xFFFFFFFF if ds._s32(t) > 0x1DF else 0
    x = 0x228 if u & 0x100 else 0xB8
    if u & 0xE0 == 0xE0:
        d = (u & 0x1F) * 0x170 >> 5
        x = x - d if u & 0x100 else x + d
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    ds.strcpy(ram, tail, ram.u32(QTITLES + 4 * ram.u32(qctx)))
    ds.text(ram, ds.SCRATCH, 6, 1, x - (ds.strlen(ram, tail) * 0xD >> 1), 0x1C)
    ds.strcpy(ram, tail, ram.u32(QPROMPT))
    ds.text(ram, ds.SCRATCH, 6, 0, x - (ds.strlen(ram, tail) * 9 >> 1) - 0x170, 0x20, 5, 6, 5, 6, 5)


def quick_grid(ram: Ram, qctx: int) -> None:
    """FUN_80054FE8: the 21 portraits; the ones under a choosing cursor are highlighted."""
    under = [0x59, 0x59]
    shown = [0x59, 0x59]
    for pl in range(2):
        rec = qrec_of(qctx, pl)
        if ram.u32(rec + 0x18) == 1:
            under[pl] = ram.u8(_qcell(ram.u32(rec + 8), ram.u32(rec + 0xC)) + 4)
            shown[pl] = _qkey_under_cursor(ram, rec)
    if under[0] == under[1] and (shown[0] != 0x59 or shown[1] != 0x59):
        under = [0x59, 0x59]
    h0 = under[0] if shown[0] == 0x59 else 0x59
    h1 = under[1] if shown[1] == 0x59 else 0x59
    ot = ds.ot0(ram) + 4
    p = ds._pkt(ram)
    for i in range(21):
        c = QGRID + 6 * i
        key = ram.u8(c + 4)
        flags = 0x20 if key == h0 or key == h1 else 0
        if not ram.u32(ss.UNLOCKED) >> (key >> 2 & 31) & 1:
            key = 0x59
        p = ds.portrait(ram, ot, p, ram.u16(c), ram.s16(c + 2), key, flags)
    ds._set_pkt(ram, p)


class QuickBackdrops:
    """FUN_80055368's per-mode picture (mode overlay functions): arcade.ovl 0x800B33CC (modes 0/3/4/6)
    and practice.ovl 0x800B7060 (the same), 0x800B34A8 (VS), 0x800B367C (team battle); volley and
    force overlays not ported."""

    def draw(self, ram: Ram, ot: int, p: int, qctx: int) -> int:
        mode = ram.u32(qctx)
        if mode in (0, 3, 4, 5, 6, 8):                     # (practice.ovl 0x800B7060, force.ovl 0x800B6438 the same)
            p = ds.poly_g4(ram, ot, p, 0x3A000000, 0x282828, 0, 0x808080, 0x1400050, 0x1400094, 0x1B00050, 0x1B00094)
            p = ds.poly_g4(ram, ot, p, 0x3A282828, 0, 0x808080, 0, 0x14000DC, 0x1400120, 0x1B000DC, 0x1B00120)
            return ds.dr_mode(ram, ot, p, 0x40)
        if mode in (1, 7):                                  # (volley.ovl 0x800B53E0 draws the same)
            p = ds.tile(ram, ot, p, 0x62404040, 0x13B0058, 0x5000C0)
            p = ds.poly_g4(ram, ot, p, 0x3A000000, 0x404040, 0, 0x404040, 0x13B0030, 0x13B0058, 0x18B0030, 0x18B0058)
            p = ds.poly_g4(ram, ot, p, 0x3A404040, 0, 0x404040, 0, 0x13B0118, 0x13B0140, 0x18B0118, 0x18B0140)
            p = ds.tile(ram, ot, p, 0x62404040, 0x18B00A8, 0x160020)
            p = ds.poly_g4(ram, ot, p, 0x3A404040, 0x404040, 0x404040, 0x404040, 0x18B009A, 0x18B00A8, 0x1A100A6, 0x1A100A8)
            p = ds.poly_g4(ram, ot, p, 0x3A404040, 0x404040, 0x404040, 0x404040, 0x18B00C8, 0x18B00D6, 0x1A100C8, 0x1A100CA)
            return ds.dr_mode(ram, ot, p, 0x40)
        if mode == 2:
            for pl in range(2):
                rec = qrec_of(qctx, pl)
                p = ds.tile(ram, ot, p, 0x62000000, ram.u16(rec + 0x10) | ram.u32(rec + 0x14) << 16 & 0xFFFFFFFF, 0x800090)
            return ds.dr_mode(ram, ot, p, 0)
        return p


QUICK_BACKDROPS = QuickBackdrops()


def quick_background(ram: Ram, qctx: int) -> None:
    """FUN_80055368: gradients, the scrolling floor stripes and banner, the mode picture."""
    ot = ds.ot0(ram)
    mode = ram.u32(qctx)
    p = ds.backdrop(ram, ot, ds._pkt(ram), 1, ram.u32(QBACK_COLOURS + 4 + 8 * mode))
    p = ds.dr_mode(ram, ot, p, 0x20)
    s = ds._smod(ram.s32(qctx + 0x10) + 0x17F, 0x180)
    ram.put(qctx + 0x10, "i", s)
    x = s - 0x180
    top, bot = 0x5F0000, 0xAF0000
    for i in range(7):
        w = ram.u32(QSTRIPES + 4 * i)
        u, v = w & 0xFF, w >> 8 & 0xFF
        if x < 0x170:
            xx = x
            while xx < 0x170:
                if xx > -0x30:
                    x0, x1 = xx & 0xFFFF, xx + 0x30 & 0xFFFF
                    vb = (v + 0x28 & 0xFF) << 8
                    ur = u + 0x18 & 0xFF
                    p = ds.poly_ft4(ram, ot, p, 0x2D000000, x0 | top, x1 | top, x0 | bot, x1 | bot,
                                    u | v << 8 | w & 0xFFFF0000, ur | v << 8 | 0x6E0000, u | vb | (ur | vb) << 16)
                xx += 0x180
        x += 0x30
    ds._set_pkt(ram, p)
    b = (ram.u32(qctx + 0x14) + 0x342) % 0x344
    ram.put(qctx + 0x14, "I", b)
    x = b - 0x344
    while x < 0x170:
        ds.text(ram, QBANNER_FMT, 0, 6, 2, x, 0xCB, QBANNER)
        x += 0x344
    p = QUICK_BACKDROPS.draw(ram, ot, ds._pkt(ram), qctx)
    p = ds.backdrop(ram, ot, p, 0, ram.u32(QBACK_COLOURS + 8 * mode))
    ds._set_pkt(ram, ds.tile(ram, ot, p, 0x60000000, 0, 0x1E00170))


class QuickModeHooks:
    """The mode overlay's part of the quick-select frame (FUN_80055878's switch): arcade.ovl
    0x800B3204 + 0x800B2D44 for VS (handicap bars and the win record), volley.ovl 0x800B593C for
    Tekken Ball (the ball damage choice)."""

    def vs(self, ram: Ram, qctx: int) -> None:
        vs_handicaps(ram, qctx)
        vs_record(ram, ds.MODE)

    def ball(self, ram: Ram) -> None:
        BALL.draw(ram)


VS_FMT_RECORD, VS_FMT_DASH, VS_FMT_DRAW = 0x800B0AF8, 0x800B0B08, 0x800B0B14
VS_RECORD_COLOURS = (0x800B4EA8, 0x800B4EAC)   # per hundreds digit: wins / draws colour
VS_LIFE, VS_PERCENT = 0x800B0B94, 0x800B4EB0
VS_BAR = 0x800B0B24              # 8 segments x (width, uv lit, uv dim)


def vs_record(ram: Ram, mode_ctx: int) -> None:
    """arcade.ovl FUN_800B2D44: the VS win - win record and the draws (two digits, colour by hundreds)."""
    for off, x, y, font, colours in ((0x38, 0x78, 0x14E, 2, VS_RECORD_COLOURS[0]), (0x3C, 0xCC, 0x14E, 2, VS_RECORD_COLOURS[0]),
                                     (0x40, 0xAB, 0x181, 1, VS_RECORD_COLOURS[1])):
        n = ram.u16(mode_ctx + off)
        ds.text(ram, VS_FMT_RECORD, ram.u8(colours + (n // 100 & 3)), font, x, y, n % 100)
    ds.text(ram, VS_FMT_DASH, 7, 2, 0xAD, 0x14E)
    ds.text(ram, VS_FMT_DRAW, 7, 0, 0xA6, 0x16D)


def _vs_bar(ram: Ram, ot: int, p: int, x: int, y: int, right: int, lit: int, pulse: int) -> int:
    """arcade.ovl FUN_800B2EE0: a handicap bar (8 segments, `lit` of them bright) with its end caps."""
    level = ds.triangle_wave(ram.u32(ds.FRAME_COUNT) << 4)
    col = ds.scale_colour(0xFFFFFF, level) if pulse == 1 else 0x808080
    p = ds.sprt(ram, ot, p, 0x65000000, (x + 0x57 if right else x - 0x5F) & 0xFFFF | y << 16 & 0xFFFFFFFF, 0xA0008, 0x7E55B6D6)
    edge = x + 2 if right == 1 else x - 1
    y4, y14 = (y + 4) << 16 & 0xFFFFFFFF, (y + 0x14) << 16 & 0xFFFFFFFF
    for i in range(8):
        e = VS_BAR + 6 * i
        w = ram.u8(e) if i > 0 or ram.u32(ds.MODE) != 7 else 0x3E
        if right == 1:
            x0, nxt = edge, w + edge
        else:
            x0 = nxt = edge - w
        uvt = ram.u16(e + 4) if lit < i else ram.u16(e + 2)
        x1 = x0 + (w - 1) & 0xFFFF
        p = ds.poly_ft4(ram, ot, p, 0x2D000000, x0 & 0xFFFF | y4, x1 | y4, x0 & 0xFFFF | y14, x1 | y14,
                        uvt << 16 | 0xACE8, 0xDACE9, 0xBCE9BCE8)
        edge = nxt
    if right == 0:
        x -= 0x80
    p = ds.tile(ram, ot, p, 0x60000000, (x + 2) & 0xFFFF | (y + 4) << 16 & 0xFFFFFFFF, 0x10007C)
    yy = y << 16 & 0xFFFFFFFF
    p = ds.sprt(ram, ot, p, col | 0x64000000, x & 0xFFFF | yy, 0x180008, 0x7EDCA8E0)
    p = ds.sprt(ram, ot, p, col | 0x64000000, x + 0x78 & 0xFFFF | yy, 0x180008, 0x7EDCA8E8)
    a, b = x + 8 & 0xFFFF, x + 0x78 & 0xFFFF
    y18 = (y + 0x18) << 16 & 0xFFFFFFFF
    return ds.poly_ft4(ram, ot, p, col | 0x2C000000, a | yy, b | yy, a | y18, b | y18, 0x7EDCA8E6, 0xDA8EA, 0xC0EAC0E6)


def vs_handicaps(ram: Ram, qctx: int) -> None:
    """arcade.ovl FUN_800B3204: both handicap bars sliding toward their value, with LIFE and the percentage."""
    ot = ds.ot0(ram) + 0x1C
    p = ds._pkt(ram)
    for pl in range(2):
        rec = qrec_of(qctx, pl)
        cur, tgt = ram.s32(rec + 0x60), ram.s32(rec + 0x5C)
        if cur != tgt:
            if tgt < cur:
                d, cur2 = cur - tgt, cur - 0x18
            else:
                d, cur2 = tgt - cur, cur + 0x18
            cur = tgt if d < 0x18 else cur2
        ram.put(rec + 0x60, "i", cur)
        p = _vs_bar(ram, ot, p, cur, ram.s16(rec + 0x9E), ram.u16(rec + 0x98), ram.u32(rec + 0x58),
                    int(ram.u32(rec) == 4))
    ds._set_pkt(ram, p)
    tail = ds.strcpy(ram, ds.SCRATCH, ds.FMT_PREFIX)
    for pl in range(2):
        rec = qrec_of(qctx, pl)
        cur = ram.s32(rec + 0x60)
        ds.strcpy(ram, tail, VS_LIFE)
        ds.text(ram, ds.SCRATCH, 5, 0, ram.s16(rec + 0xA0) + cur, ram.s16(rec + 0xA2))
        ds.strcpy(ram, tail, ram.u32(VS_PERCENT + 4 * ram.u32(rec + 0x58)))
        ds.text(ram, ds.SCRATCH, 6, 0, ram.s16(rec + 0xA4) + cur, ram.s16(rec + 0xA6))


QUICK_MODE = QuickModeHooks()


def quick_select(ram: Ram, qctx: int = QCTX) -> int | None:
    """FUN_80055878 (game state 10): the resident character select of VS, team battle and Tekken Ball."""
    sub = ram.s16(ss.SUB_STATE)
    if sub != 0 and ram.u32(qctx + 8) == 0 and ss.menu_exit(ram):
        return 1
    if sub == 0:
        ram.put(0x80095850, "I", 1)                        # FUN_80029860(0)
        ram.put(ss.SUB_STATE, "H", 1)
        return None
    if sub == 1:
        ram.put(qctx + 8, "I", 1)
        for off in (0xC, 4, 0x10, 0x14):
            ram.put(qctx + off, "I", 0)
        ram.put(qctx, "I", ram.u32(ds.MODE))
        for p in range(2):
            rec = qrec_of(qctx, p)
            ram.put(rec, "I", 0)
            ram.put(rec + 4, "I", p)
            ram.put(rec + 0x64, "I", ram.u8(0x800982EE + p))
            quick_step(ram, ds.MODE, qctx, p)
        if ram.u32(ds.MODE) == 7:
            BALL.start(ram)
        ram.put(ss.SUB_STATE, "H", 2)
    elif sub == 2:
        a = quick_step(ram, ds.MODE, qctx, 0)
        b = quick_step(ram, ds.MODE, qctx, 1)
        if a & b:
            ram.put(ss.SUB_STATE, "H", 3)
    elif sub == 3:
        quick_commit(ram, ds.MODE, qctx)
        ram.put(ss.GAME_STATE, "H", ram.u8(ds.MODE + 0x14))
        ram.put(ss.SUB_STATE, "H", ram.u8(ds.MODE + 0x15))
    saved = ds._pkt(ram)
    ds._set_pkt(ram, qctx + 0x170 + ram.u32(ds.DISPLAY_BUFFER) * 0x3C00)
    if ram.u32(qctx + 8) == 1:
        lv = ram.s32(qctx + 0xC)
        ds._set_pkt(ram, ds.fade(ram, ds.ot0(ram) + 0x1C, ds._pkt(ram), lv))
        lv += 0x10
        if lv > 0x100:
            ram.put(qctx + 8, "I", 0)
        ram.put(qctx + 0xC, "i", lv)
    mode = ram.u32(qctx)
    if mode == 7:
        QUICK_MODE.ball(ram)
    elif mode == 1:
        QUICK_MODE.vs(ram, qctx)
    elif mode < 9:
        ds.text(ram, STR_VS, 7, 2, 0xA1, 0x15C)
    quick_members(ram, qctx)
    quick_cursors(ram, qctx)
    quick_texts(ram, qctx)
    quick_title(ram, qctx)
    quick_grid(ram, qctx)
    quick_background(ram, qctx)
    ds._set_pkt(ram, saved)
    return None
