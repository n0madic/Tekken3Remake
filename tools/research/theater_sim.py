#!/usr/bin/env python3
"""Integer port of the Theater menus (ending.ovl, Japan Rev.1): the MOVIE THEATER grid, the sound
player list, their input handlers, the footer panel and the scrolling title banner.

The drawing writes the same GPU packets as the game (see draw_sim.py). Sound effects, the music
stop call and the TIM uploads go through `HOOKS` (the verifier logs them in RAM and replaces the
game's functions with stubs that write the same logs).
Verified by `tools/research/verify_theater_sim.py`.
"""

from __future__ import annotations

import draw_sim as ds
import screens_sim as ss
from fight_sim import Ram

# ---- the Theater context (0x800AE158) ----
PAGE = 0x800AE158                # u8: 0 arcade ending, 1 movie theater, 2 arrange sound, 3 arcade sound
DISC = 0x800AE159                # u8: 1 Tekken, 2 Tekken 2, 3 Tekken 3
MOVIE_COUNT, SOUND_COUNT = 0x800AE15A, 0x800AE15B
MOVIE, TRACK = 0x800AE15C, 0x800AE15D   # u8: the movie / list entry to play
CURSOR, TOP = 0x800AE15E, 0x800AE15F    # u8: list cursor, first visible row (grid) or line (list)
UNUSED = 0x800AE160              # u16, cleared with the others
FOCUS = 0x800AE162               # s16: 0 list, 1 EXIT, 2 SOUND / THEATER, 3 DISC, 4 BGM SELECT
ALL_MOVIES = 0x800AE164          # s16: every Tekken 3 movie is open (DISC and SOUND are offered)
IDLE = 0x800AE166                # u16: frames without a held button (banner)
FRAME_COUNTER = 0x800AFF14

MOVIE_LISTS = {1: (0x800BB29C, 12), 2: (0x800BAD3C, 30), 3: (0x800BA858, 26)}
SOUND_LISTS = {1: (0x800BBC4C, 14), 2: (0x800BB88C, 28), 3: (0x800BB49C, 29)}
ENTRY = 0x1C                     # s16 movie, s16 alternative movie, s16 picture, u32 mask at +8,
                                 # u32 rule at +0xC, name +0x10, title lines +0x14 / +0x18
NAME_BUF = 0x80194598
PICTURES = 0x800BA08C            # 12 bytes each: s16 CLUT x, CLUT y, VRAM x, VRAM y
CELL_FRAME = 0x800BA368          # the same four fields for the grid cell frame
TIMS = 0x800BA374                # 14 bytes each: CLUT x, y, VRAM x, y, w, h, u16 mode (1 = 8-bit)
PANELS = 0x800BA730              # 0x20 bytes each: x, y, w, h, u16 flags, u8 side, u8 top,
                                 # 4 gradient colours, frame colour
STRIPS = 0x800BA838              # 8 x (s16 width / 12, s16 first piece)
STRIP_PIECES = 0x800BA790        # 12 bytes each: u8 u, u8 v, u16 w, h, s16 CLUT, s16 more
BUTTON_ICONS = 0x800BBDF0        # 4 x u32 uv|clut
BANNERS = 0x8011DAA8             # per disc (12 bytes): page 1, page 2, page 3 title
STR_CANCEL = 0x800BBE4C
FMT_S = 0x800BBE84               # "%f%c%H%V%s"
STR_DISC, STR_SOUND, STR_EXIT = 0x800BBE90, 0x800BBE98, 0x800BBEA0
STR_LOCKED = 0x800BBEA8          # "%f%c%H%V???"
FMT_LINE = 0x800BBEB4            # "%f%c%H%V%2d:%s"
STR_THEATER, STR_BGM = 0x800BBEC4, 0x800BBECC
STR_ARRANGE, STR_ARCADE = 0x800BBED8, 0x800BBEE8
NAMES = {0x30: (0x10, 0x80000, 0x800BB234, 0x800BB7D4, 0x800BBE00),   # YOSHIMITSU / DOCTOR.B.
         0x31: (0x800, 0x800, 0x800BB1AC, 0x800BBE18, 0x800BBE20),    # KUMA / PANDA
         0x32: (0x10000, 0x10000, 0x800BBE2C, 0x800BB7E8, 0x800BB7E8),  # GUN JACK -BAD- / GUN JACK
         0x33: (0x4000, 0x100000, 0x800BB7F4, 0x800BB7C8, 0x800BBE3C)}  # OGRE / TRUE OGRE
SND_MOVE, SND_OK = 0x546C, 0x4CEB
M32 = 0xFFFFFFFF


class TheaterHooks:
    """SoundPlayFighter (0x800756A4), the music stop FUN_8006B834 and the TIM upload FUN_80112390
    (TIM k from the overlay's table 0x8011DA90 into the VRAM rectangle of record TIMS + 14·k).
    The defaults do nothing; the verifier logs the calls in RAM."""

    def sound(self, ram: Ram, sound_id: int) -> None:
        pass

    def music_stop(self, ram: Ram) -> None:
        pass

    def load_tim(self, ram: Ram, k: int) -> None:
        pass


HOOKS = TheaterHooks()


# ---- unlock rules ----
def entry_status(ram: Ram, e: int) -> int:
    """FUN_8010FC7C: the movie to play, -1 while locked; entries with movie -2 are empty cells."""
    mask = ram.u32(e + 8)
    if mask == 0:
        return ram.s16(e)
    rule = ram.u32(e + 0xC)
    cleared, cleared2 = ram.u32(ss.CLEARED), ram.u32(ss.CLEARED2)
    if rule == 0:
        return ram.s16(e) if cleared & mask else -1
    if rule in (1, 2):                              # Kuma / Panda, Gun Jack's two endings
        bit = 0x800 if rule == 1 else 0x10000
        if cleared2 & bit:
            return ram.s16(e + 2)
        return ram.s16(e) if cleared & bit else -1
    if rule == 3:                                   # Tiger: Eddy's second-costume clear
        return ram.s16(e) if cleared2 & 0x100 else -1
    raise NotImplementedError(f"movie rule {rule}")


def all_movies(ram: Ram) -> int:
    """FUN_801109D4: 1 when no Tekken 3 movie is locked."""
    lst, _ = MOVIE_LISTS[3]
    return int(all(entry_status(ram, lst + ENTRY * i) != -1 for i in range(26)))


def movie_name(ram: Ram, lst: int, idx: int) -> None:
    """FUN_8010F634: the entry's name into NAME_BUF; names "0"-"3" stand for the characters whose
    endings share a slot, named after the clears that opened it."""
    name = ram.u32(lst + ENTRY * idx + 0x10)
    rule = NAMES.get(ram.u8(name))
    if rule is None:
        ds.strcpy(ram, NAME_BUF, name)
        return
    bit1, bit2, s1, s2, s3 = rule
    c = ram.u32(ss.CLEARED)
    second = ram.u32(ss.CLEARED2) if ram.u8(name) in (0x31, 0x32) else c
    which = int(c & bit1 != 0) | (2 if second & bit2 else 0)
    if which:
        ds.strcpy(ram, NAME_BUF, (s1, s2, s3)[which - 1])


def reset(ram: Ram) -> None:
    """FUN_80111A08."""
    for a, f in ((CURSOR, "B"), (TOP, "B"), (UNUSED, "H"), (FOCUS, "H"), (IDLE, "H")):
        ram.put(a, f, 0)


# ---- drawing ----
def _xy(x: int, y: int) -> int:
    return x & 0xFFFF | (y & 0xFFFF) << 16


def _tile(ram: Ram, p: int, x: int, y: int, w: int, h: int, colour: int) -> int:
    return ds.tile(ram, ds.ot_text(ram), p, 0x60000000 | colour, _xy(x, y), _xy(w, h))


def frame4(ram: Ram, p: int, x: int, y: int, w: int, h: int, side: int, top: int, colour: int) -> int:
    """Four tiles along the edges of a box (top, left, bottom, right)."""
    p = _tile(ram, p, x, y, w, top, colour)
    p = _tile(ram, p, x, y, side, h, colour)
    p = _tile(ram, p, x, y + h - top, w, top, colour)
    return _tile(ram, p, x + w - side, y, side, h, colour)


def panel_frame(ram: Ram, p: int, k: int, dx: int, dy: int) -> int:
    """FUN_8010FE10: the frame of panel k, moved by (dx, dy)."""
    r = PANELS + 0x20 * k
    return frame4(ram, p, ram.s16(r) + dx, ram.s16(r + 2) + dy, ram.s16(r + 4), ram.s16(r + 6),
                  ram.u8(r + 0xA), ram.u8(r + 0xB), ram.u32(r + 0x1C))


def panel(ram: Ram, p: int, k: int) -> int:
    """The panel drawer inlined twice in FUN_80110008: frame, then a Gouraud quad. Flag bit 1 is
    meant to make the quad semi-transparent, but the game ORs it into the first vertex's red
    (game-bugs.md #36)."""
    r = PANELS + 0x20 * k
    flags = ram.u16(r + 8)
    if ram.u8(r + 0xA):
        p = panel_frame(ram, p, k, 0, 0)
    if flags & 1:
        x, y, w, h = (ram.u16(r + 2 * i) for i in range(4))
        ram.put(p + 3, "B", 8)
        ram.put(p + 7, "B", 0x38)
        xys = ((x, y), (x + w, y), (x, y + h), (x + w, y + h))
        for i in range(4):
            ram.put(p + 8 + 8 * i, "I", _xy(*xys[i]))
            c = ram.u32(r + 0xC + 4 * i) | (flags & 2 if i == 0 else 0)
            ram.put(p + 4 + 8 * i, "I", ram.u32(p + 4 + 8 * i) & 0xFF000000 | c)
        ds.link(ram, ds.ot_text(ram), p, 8)
        p += 0x24
    return p


def _sprite(ram: Ram, x: int, y: int, rec: int, u: int, w: int, h: int, tpage: int) -> None:
    """SetSprt from an image record (CLUT x, CLUT y, VRAM x, VRAM y), then its draw mode."""
    cx, cy, py = ram.s16(rec), ram.s16(rec + 2), ram.s16(rec + 6)
    clut = (cy << 6 | cx >> 4 & 0x3F) & 0xFFFF
    ot = ds.ot_text(ram)
    p = ds.sprt(ram, ot, ds._pkt(ram), 0x64808080, _xy(x, y), _xy(w, h), u & 0xFF | (py & 0xFF) << 8 | clut << 16)
    ds._set_pkt(ram, ds.dr_mode(ram, ot, p, tpage))


def picture(ram: Ram, x: int, y: int, k: int) -> None:
    """An 8-bit 48 x 64 movie picture (0 is the locked picture). The grid inlines it; the
    standalone copy FUN_8010F8D0 is never called."""
    r = PICTURES + 12 * k
    px, py = ram.s16(r + 4), ram.s16(r + 6)
    _sprite(ram, x, y, r, (px & 0x7F) << 1, 0x30, 0x40, (py & 0x100) >> 4 | (px & 0x380) >> 6 | 0x80)


def cell_frame(ram: Ram, x: int, y: int) -> None:
    """The grid cell frame (inlined; the standalone copy FUN_8010FA08 is never called)."""
    px, py = ram.s16(CELL_FRAME + 4), ram.s16(CELL_FRAME + 6)
    _sprite(ram, x, y, CELL_FRAME, 0x60, 0x30, 0x40, (py & 0x100) >> 4 | (px & 0x3C0) >> 6)


def tim_sprite(ram: Ram, x: int, y: int, k: int) -> None:
    """FUN_8010FB24: TIM k (disc logos 0-5, the sound picture 7) as one sprite."""
    r = TIMS + 14 * k
    px, py = ram.s16(r + 4), ram.s16(r + 6)
    mode = ram.u16(r + 0xC) & 1
    _sprite(ram, x, y, r, (px & 0x3F) << (1 if mode else 2), ram.u16(r + 8), ram.u16(r + 0xA),
            mode << 7 | (py & 0x100) >> 4 | (px & 0x380) >> 6)


def button_icons(ram: Ram, x: int, y: int) -> None:
    """FUN_8010F4B0: the four button icons of the CANCEL line."""
    ot = ds.ot_text(ram)
    for i, dx in enumerate((0, 0x12, 0x24, 0x50)):
        p = ds.sprt(ram, ot, ds._pkt(ram), ds.GLYPH_CODE, (x + dx) & 0xFFFF | y << 16 & M32, 0x14000C,
                    ram.u32(BUTTON_ICONS + 4 * i))
        ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0x1F))


def strip(ram: Ram, k: int) -> None:
    """Help strip k: pieces of a text picture in a row at y 400, centred."""
    x = ds._asr(0x170 - 12 * ram.s16(STRIPS + 4 * k), 1)
    r = STRIP_PIECES + 12 * ram.s16(STRIPS + 4 * k + 2)
    ot = ds.ot_text(ram)
    while True:
        clut = ds._asr(ram.s16(r + 8) * 16 + 0x200, 4) & 0x3F | 0x7F80
        w = ram.u16(r + 4)
        p = ds.sprt(ram, ot, ds._pkt(ram), 0x64808080, _xy(x, 400), _xy(w, ram.u16(r + 6)),
                    ram.u8(r) | ram.u8(r + 2) << 8 | clut << 16)
        ds._set_pkt(ram, ds.dr_mode(ram, ot, p, 0x16))
        x += ram.s16(r + 4)
        more = ram.s16(r + 0xA)
        r += 12
        if more == 0:
            break


def help_strip(ram: Ram, focus: int, page: int) -> None:
    """FUN_801104B0: the help strip of the focused button."""
    if page == 1:
        k = {1: 7, 2: 5, 3: 0}.get(focus, -1)
    else:
        k = {1: 7, 2: 4, 3: 1, 4: 6}.get(focus, -1)
    if k >= 0:
        strip(ram, k)


def pulse(ram: Ram) -> int:
    return ds.scale_colour(0xFF4020, (ds.triangle_wave(ram.u32(ds.FRAME_COUNT) << 4) >> 1) + 0x80)


def button(ram: Ram, colour: int, px: int, py: int, x: int, y: int, s: int, selected: int) -> None:
    """FUN_801106A8: a label in a white frame over a dark blue (or pulsing, when selected) box. The
    box starts at y - px instead of y - py, so it shows above the frame (game-bugs.md #37)."""
    n = ds.strlen(ram, s)
    ds.text(ram, FMT_S, 0, colour, x, y, s)
    x0, y0, w, h = x - px, y - py, 2 * px + 9 * n, 2 * py + 16
    p = frame4(ram, ds._pkt(ram), x0, y0, w, h, 2, 2, 0xFFFFFF)
    ds._set_pkt(ram, _tile(ram, p, x0, y - px, w, h, pulse(ram) if selected else 0x800000))


def _button(ram: Ram, focus: int, which: int, x: int, y: int, s: int) -> None:
    button(ram, 5 if focus == which else 10, 8, 6, x, y, s, int(focus == which))


def banner(ram: Ram) -> None:
    """FUN_80112554: the page title at the top; after 480 idle frames it alternates every 256
    frames with PUSH START TO PLAY, sliding for the last 32 frames of each half."""
    if ram.u16(ss.PAD_HELD) | ram.u16(ss.PAD_HELD + 2):
        ram.put(IDLE, "H", 0)
    else:
        ram.put(IDLE, "H", ram.u16(IDLE) + 1)
    idle = ram.u16(IDLE)
    t = idle - 0x1E0 if idle >= 0x1E0 else 0
    x = 0x228 if t & 0x100 else 0xB8
    if t & 0xE0 == 0xE0:
        d = (t & 0x1F) * 23 >> 1
        x += -d if t & 0x100 else d
    end = ds.strcpy(ram, NAME_BUF, ds.FMT_PREFIX)
    page = ram.u8(PAGE)
    if page not in (1, 2, 3):
        raise NotImplementedError(f"banner on page {page}")
    ds.strcpy(ram, end, ram.u32(BANNERS + 4 * (page - 1) + 12 * ram.u8(DISC)))
    ds.text(ram, NAME_BUF, 6, 1, x - (ds.strlen(ram, end) * 13 >> 1), 0x22, 1 if page == 2 else 6)
    ds.strcpy(ram, end, ram.u32(BANNERS + 8))
    ds.text(ram, NAME_BUF, 6, 0, x - (ds.strlen(ram, end) * 9 >> 1) - 0x170, 0x22, 5, 6, 5)


def footer(ram: Ram, kind: int) -> None:
    """FUN_80110008: the bottom panel and the background. Kind 0 is the menu (with the banner);
    1-6 are the disc messages of the state handler (1 and 5 add the CANCEL line)."""
    if kind == 0:
        banner(ram)
    if kind in (1, 5):
        ds.text(ram, STR_CANCEL, 0, 9, 0x18, 5, 6)
        button_icons(ram, 0xC5, 0x1B0)
    k = -1
    if kind in (1, 2, 3):
        k = 2 if ram.s16(ALL_MOVIES) else 3
    elif kind in (4, 5, 6):
        k = 3
    if k >= 0:
        strip(ram, k)
    p = panel(ram, ds._pkt(ram), 1)
    ds._set_pkt(ram, p)
    ds._set_pkt(ram, panel(ram, p, 0))


def movie_grid(ram: Ram, count: int, lst: int) -> None:
    """FUN_80110A58: 6 x 4 pictures, the buttons and the selected movie's names."""
    cur, top, focus = ram.u8(CURSOR), ram.u8(TOP), ram.s16(FOCUS)
    if focus == 0 and ram.u32(FRAME_COUNTER) & 0x1C:
        ds._set_pkt(ram, panel_frame(ram, ds._pkt(ram), 2, cur % 6 * 0x30 + 0x26, (cur // 6 - top) * 0x40 + 0x45))
    for r in range(4):
        y = 0x48 + 0x40 * r
        for c in range(6):
            idx = c + (r + top) * 6
            if idx >= ram.u8(MOVIE_COUNT):
                break
            e = lst + ENTRY * idx
            x = 0x28 + 0x30 * c
            if entry_status(ram, e) >= 0:
                cell_frame(ram, x, y)
                if ram.s16(e + 4) >= 0:
                    picture(ram, x, y, ram.s16(e + 4))
            elif ram.s16(e) >= 0:
                cell_frame(ram, x, y)
                picture(ram, x, y, 0)
    if ram.s16(ALL_MOVIES):
        _button(ram, focus, 3, 0x52, 0x158, STR_DISC)
        _button(ram, focus, 2, 0xA2, 0x158, STR_SOUND)
        _button(ram, focus, 1, 0xFC, 0x158, STR_EXIT)
    else:
        _button(ram, focus, 1, 0xA2, 0x158, STR_EXIT)
    if focus != 0 or cur >= count:
        help_strip(ram, focus, ram.u8(PAGE))
        return
    e = lst + ENTRY * cur
    if entry_status(ram, e) < 0:
        if ram.s16(e + 4) > 0:
            ds.text(ram, STR_LOCKED, 1, 6, 0xC1, 0x182)
        return
    movie_name(ram, lst, cur)
    if ram.s16(e + 4) > 0:
        picture(ram, 0x1E, 0x180, ram.s16(e + 4))
    ds.text(ram, FMT_S, 1, 6, ((0xE9 - 13 * ds.strlen(ram, NAME_BUF) & M32) >> 1) + 0x60, 0x182, NAME_BUF)
    lines = [ram.u32(e + 0x14)] + ([ram.u32(e + 0x18)] if ram.u32(e + 0x18) else [])
    for s, y in zip(lines, (0x1A6,) if len(lines) == 1 else (0x19D, 0x1AF)):
        ds.text(ram, FMT_S, 0, 5, ((0xE6 - 9 * ds.strlen(ram, s) & M32) >> 1) + 0x64, y, s)


def sound_list(ram: Ram, count: int, lst: int) -> None:
    """FUN_801112DC: 14 lines of the track list, the buttons, the selected track and the disc logos."""
    cur, focus, page = ram.u8(CURSOR), ram.s16(FOCUS), ram.u8(PAGE)
    ds._set_pkt(ram, frame4(ram, ds._pkt(ram), 0x18, 0x48, 0xCE, 0x122, 2, 2, 0xFFFFFF))
    for i in range(14):
        idx = ram.u8(TOP) + i
        hit = focus == 0 and idx == cur
        colour = 5 if hit else 0xB if page == 2 else 0xA
        ds.text(ram, FMT_LINE, 0, colour, 0x1E, 0x50 + 0x14 * i, idx + 1, ram.u32(lst + ENTRY * idx + 0x10))
        if hit:
            ds._set_pkt(ram, _tile(ram, ds._pkt(ram), 0x19, 0x4F + 0x14 * i, 0xCC, 0x12, pulse(ram)))
    _button(ram, focus, 2, 0xFA, 0xC8, STR_THEATER)
    _button(ram, focus, 4, 0xFA, 0xE6, STR_BGM)
    _button(ram, focus, 3, 0xFA, 0x104, STR_DISC)
    _button(ram, focus, 1, 0xFA, 0x122, STR_EXIT)
    if focus == 0 and cur < count:
        name = ram.u32(lst + ENTRY * cur + 0x10)
        x = (0x170 - 13 * ds.strlen(ram, name) & M32) >> 1
        ds.text(ram, FMT_S, 1, 6, x + 0x10, 0x186, name)
        tim_sprite(ram, x - 0xE, 0x182, 7)
        ds.text(ram, STR_ARRANGE if page == 2 else STR_ARCADE, 0, 5, 0x104, 0x1A6)
    else:
        help_strip(ram, focus, page)
    disc = ram.u8(DISC)
    tim_sprite(ram, 0xF2, 0x5A, disc * 2 - 2)
    tim_sprite(ram, 0xF2, 0x15A, disc * 2 - 1)


def theater_draw(ram: Ram, kind: int) -> None:
    """FUN_80111894: the page of PAGE (kind 0), or a disc message (footer kinds 1-6)."""
    if kind == 0:
        page, disc = ram.u8(PAGE), ram.u8(DISC)
        if page == 1:
            if disc not in MOVIE_LISTS:
                raise NotImplementedError(f"disc {disc}")
            lst, n = MOVIE_LISTS[disc]
            ram.put(MOVIE_COUNT, "B", n)
            movie_grid(ram, n, lst)
        elif page in (2, 3):
            if disc not in SOUND_LISTS:
                raise NotImplementedError(f"disc {disc}")
            lst, n = SOUND_LISTS[disc]
            ram.put(SOUND_COUNT, "B", n)
            sound_list(ram, n, lst)
        else:
            return
    footer(ram, kind)


# ---- input ----
def _pads(ram: Ram) -> tuple[int, int]:
    return (ram.u16(ss.PAD_PRESSED) | ram.u16(ss.PAD_PRESSED + 2),
            ram.u16(ss.PAD_REPEAT) | ram.u16(ss.PAD_REPEAT + 2))


def _open_sound_page(ram: Ram, page: int) -> None:
    reset(ram)
    ram.put(PAGE, "B", page)


def movie_input(ram: Ram) -> int:
    """FUN_80111A68. Returns 1 (play MOVIE), 4 (exit), 5 (DISC) or 0."""
    pressed, rep = _pads(ram)
    count, old, focus0 = ram.u8(MOVIE_COUNT), ram.u8(CURSOR), ram.s16(FOCUS)
    disc = ram.u8(DISC)
    lst = MOVIE_LISTS[disc][0] if disc in MOVIE_LISTS else None
    col, row = old % 6, old // 6

    def st(i: int) -> int:
        return entry_status(ram, lst + ENTRY * i)

    if focus0 == 0:
        if rep & 0x8000:
            if col > 0 and st(row * 6 + col - 1) >= -1:
                col -= 1
        elif rep & 0x2000:
            if col < 5 and st(row * 6 + col + 1) >= -1:
                col += 1
        if rep & 0x1000:
            if row > 0:
                row -= 1
            if row < ram.u8(TOP):
                ram.put(TOP, "B", ram.u8(TOP) - 1)
        elif rep & 0x4000:
            row += 1
            if row < ds._sdiv(count, 6):
                if st(col + row * 6) < -1:          # an empty cell: slide towards the middle
                    step = 1 if col < 3 else -1
                    while st(col + row * 6) < -1:
                        col += step
            else:
                ram.put(FOCUS, "H", 2 if ram.s16(ALL_MOVIES) else 1)
                row -= 1
            if row >= ram.u8(TOP) + 4:
                ram.put(TOP, "B", ram.u8(TOP) + 1)
    else:
        if ram.s16(ALL_MOVIES):
            if rep & 0x8000:
                ram.put(FOCUS, "H", {2: 3, 1: 2}.get(focus0, focus0))
            elif rep & 0x2000:
                ram.put(FOCUS, "H", {2: 1, 3: 2}.get(focus0, focus0))
        if rep & 0x1000:
            ram.put(FOCUS, "H", 0)
    cur = col + row * 6
    if cur < 0:
        cur = count - 1
    elif cur >= count:
        cur = 0
    ram.put(CURSOR, "B", cur)
    if cur != old or ram.s16(FOCUS) != focus0:
        HOOKS.sound(ram, SND_MOVE)
    if not pressed & 0x8F0:
        if pressed & 0x100:
            HOOKS.sound(ram, SND_OK)
            return 4
        return 0
    focus = ram.s16(FOCUS)
    if focus == 0:
        s = st(ram.u8(CURSOR)) if lst is not None else -1
        if s < 0:
            return 0
        HOOKS.music_stop(ram)
        ram.put(MOVIE, "B", s)
        return 1
    if focus == 2:
        HOOKS.sound(ram, SND_OK)
        _open_sound_page(ram, 2)
        for k in (disc * 2 - 2, disc * 2 - 1, 6, 7):
            HOOKS.load_tim(ram, k)
        return 0
    if focus == 3:
        HOOKS.sound(ram, SND_OK)
        return 5
    if focus == 1:
        HOOKS.sound(ram, SND_OK)
        return 4
    return 0


def sound_input(ram: Ram) -> int:
    """FUN_80111FEC. Returns 1 (play TRACK), 4 (exit), 5 (DISC) or 0."""
    pressed, rep = _pads(ram)
    old, count, focus0 = ram.u8(CURSOR), ram.u8(SOUND_COUNT), ram.s16(FOCUS)
    cur = old
    if focus0 == 0:
        if rep & 0x2000:
            ram.put(FOCUS, "H", 2)
        elif rep & 0x1000:
            if old > 0:
                cur = old - 1
                if cur < ram.u8(TOP):
                    ram.put(TOP, "B", ram.u8(TOP) - 1)
        elif rep & 0x4000:
            if old < count - 1:
                cur = old + 1
                if cur >= ram.u8(TOP) + 14:
                    ram.put(TOP, "B", ram.u8(TOP) + 1)
    elif rep & 0x8000:
        ram.put(FOCUS, "H", 0)
    elif rep & 0x1000:                              # up: EXIT, DISC, BGM SELECT, THEATER
        ram.put(FOCUS, "H", {1: 3, 3: 4, 4: 2}.get(focus0, focus0))
    elif rep & 0x4000:
        ram.put(FOCUS, "H", {2: 4, 4: 3, 3: 1}.get(focus0, focus0))
    if ram.s16(ALL_MOVIES) == 0 and ram.s16(FOCUS) == 3:
        ram.put(FOCUS, "H", focus0)
    ram.put(CURSOR, "B", cur)
    if cur != old or ram.s16(FOCUS) != focus0:
        HOOKS.sound(ram, SND_MOVE)
    if not pressed & 0x8F0:
        if pressed & 0x100:
            HOOKS.sound(ram, SND_OK)
            return 4
        return 0
    focus = ram.s16(FOCUS)
    if focus == 0:
        disc = ram.u8(DISC)
        if disc in SOUND_LISTS:
            ram.put(TRACK, "B", ram.u8(SOUND_LISTS[disc][0] + ENTRY * ram.u8(CURSOR)))
        if ram.u8(PAGE) == 3:
            ram.put(TRACK, "B", ram.u8(TRACK) | 1)
        HOOKS.music_stop(ram)
        return 1
    if focus == 2:
        HOOKS.music_stop(ram)
        HOOKS.sound(ram, SND_OK)
        _open_sound_page(ram, 1)
        return 0
    if focus == 4:
        HOOKS.music_stop(ram)
        HOOKS.sound(ram, SND_OK)
        ram.put(PAGE, "B", ram.u8(PAGE) ^ 1)
        return 0
    if focus in (1, 3):
        HOOKS.sound(ram, SND_OK)
        return 4 if focus == 1 else 5
    return 0


def theater_input(ram: Ram) -> int:
    """FUN_80111A28."""
    return movie_input(ram) if ram.u8(PAGE) == 1 else sound_input(ram)
