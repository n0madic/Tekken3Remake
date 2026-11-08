"""The arcade version's 2D assets → `hud/` and `screens/arcade/` (Namco System 12, World ver. E1).

The arcade's screens are data-driven in the remake: they read no executable image at run time, so
every picture, glyph sheet, layout number and string a draw routine takes from the program leaves
here as a file. All strings are read from the program by address; none lives in this file.

VRAM rules (`upload`): `FUN_801B1A94` skips a TIM's pixel block when its rectangle is at (0, 0) and
its CLUT block when flag 8 is off or its rectangle is at (0, 0), so CLUT-only TIMs (a truncated
pixel block at (0, 0)) replace a palette alone; `FUN_801B18EC` sets bit 15 on every non-zero CLUT
word and leaves 0 alone, so only colour word 0 is transparent (`vram.rgba`). The hi-res loaders
(480 lines, `DAT_8021FC04` = 0) drop no rows. `FUN_801B1E58(0)` builds the VRAM that stays loaded:
categories 3, 1, 2, 6 in order, then the patch of font 2 (category 5), its CLUT skipped.

`hud/` is the format `remake/content/hud_data.gd` loads (as `hud.py` writes it for the PlayStation):
`hud.json`, `bar_{health,damage,empty}.png` (2 × 16, stretched), `bar_backing.png` (2 × 24),
`bar_cap_{left,right}.png`, `digit_<0–11>.png` (10, 11: the ∞ halves), `mark_{won,empty}.png`,
`name_<key>.png`, `plate_<costume>.png`, `font_<font>_<colour>.png` (characters 0x20–0x5F in rows of
16 cells; a sheet per colour the CLUTs define, `text_colours` below).

`screens/arcade/screens.json`, in the 512 × 480 layout; file names are relative to its folder:

- `width`, `height`.
- `texts`: key → runs, one per stretch of one font, colour and pen: `{text, font, colour, x, y}`.
  `text` is a printf format: value placeholders (`%1x`, `%02d`, `%s`) and `%%` as in the game's
  format, colour or pen null when the code computes them at run time. Keys are `TEXTS` below. Keys
  `status_*`, `rank_*` hold positions relative to their cell (documented at `TEXTS`).
- `text_colours`: font → the colours that have a glyph sheet.
- `prompts` (font 0): `main` (the title prompt, FUN_801B1328: `y`, `colour`, `blink_mask`, `entries`
  {text, x}); `side` (`entries`, x added to the caller's: `select.prompt`, `hud.status.prompt_x`;
  FUN_801B1278 draws them while `frame & blink_mask`, and the `credits` entries instead, at their
  own x added likewise, when `frame & alternate_mask`); `credits` (FUN_801B10B0: `x` per side, `y`,
  `colour`, `entries`, whose x counts only in the side prompt's place).
- `icon.png`, `icon_<layer>.png` at the conversion's root: the application icons, from the title's logo.
- `title`: `picture`, `logo` {file, x, y}, `copyright` (keys of `texts`).
- `select`: `layouts` (index 0 up to 10 faces, 1 more): `portrait_y`, `plate_y`, `panel_top`,
  `faces_y`, `face_height`, `cursor_height`, `cursor_y`, `tag_y`, `timer_y`, `prompt_colour`,
  `frames` [{file, x, y, width, height}], `gradient` {top, bottom, top_colour, bottom_colour},
  `faces` {character: file}, `cursors` [file per side], `digits` [file per digit]. `players` per
  side: `portrait_x`, `plate_centre_x`, `tag` {file, dx}. `roster` (18 characters), `cells`
  (by face count parity, then row: [x, y] × 10), `face_width`, `tiles` {size, columns, scroll_scale,
  scroll_shift, files {index: file}, rows (8 × 8 indices)}: FUN_801C04D8's scrolling background,
  clipped with the banner at `panel_top`, `banner` {file, x, y}, `plates`
  {entry: file}, `plate_height`, `timer` {x, tens_x}, `prompt` {x, step, y}, `bands` (2 × 127
  portrait brightness tables, chosen by the attribute's `band`), `state_anim`, `decided`,
  `portrait_width`, `glow` {width, top, middle, bottom, end_colour}, `unreferenced` (cat 7's
  pictures no routine draws).
- `vs`: `backgrounds` [file per kind], `background_size`, `positions`, `names` ([x, y, dx, dy] per
  record: 4), `frame` {rects, colour}, `portrait` {x, y, width, height, source_y}, `gradient`
  {top, middle, bottom, end_colour} relative to the record's y, `slide` {start, shift},
  `name` {advance, left, right}, `unknown_name` (the VS kind 3 name).
- `ranking`: `titles` [file per kind], `band` {x, y, width, height, solid, strip, alpha, alpha_step},
  `row_step`, `cells` (name → [dx, dy] from the row: `rank`, `face`, `name`, `time`, `mark`, `entry`,
  `usage`), `fonts`, `face_size`, `dividers` {colour, rects [dx, dy, w, h]}, `suffixes`, `colours`
  (`time` rows of 5: rank, name, time, mark, entry; `wins` rows of 4: rank, name, wins, entry;
  `usage` rows of 3: rank, name, percent; row 0 normal, row 1 the highlighted row), `bars`
  {dx, max_width, height, depth, colours (per character: side face; front left, right; top left,
  right)}, `alphabet`, `rejected`, `fight_entry` ([wins x, y, name x, y] per side).
- `ending`: `background` {file, width, height, fade_hold: the level of FUN_801B354C's full-screen
  fade it is held under: below 0x100 it subtracts 0xFF − level from every channel}, `logo`
  {file, x, y}, `namco_logo` {file, x, y}, `font`, `staff`: ten pages, `left` and `right` blocks
  {x, slide (−1, +1: sign of the slide offset), lines [{text, x (from the block's), y, colour}]}.
- `banner` (demo's new fighter): `face` {x, y, width, height}, `name_right`, `selectable_right`,
  `per_letter`.
- `hud`, the fight's layout numbers: `life` {sides [{direction, x, y, grow_x: where the fill
  starts}], length, fill_top, fill_bottom, backing_dx, backing_width, cap_right_dx}; `timer` {x,
  tens_x, y, width, height, infinity: the digits drawn at tens_x and x}; `marks` {x, step (per side),
  y, blink_mask}; `names` {x (P1's; P2's right edge), y, height, plate_margin, plate_top,
  plate_bottom}; `status` {y, clock_x, prompt_x, continue_x (per side), continue_y, prompt_colour,
  streak [{runs, x per side}]: 1 win, up to 9, up to 99, more}; `fight` {wins_right, wins_per_letter
  (the x of `wins`: right − letters · per_letter), winner_x, loser_x (per side)}.
- `characters` (88 costume keys, id << 2 | costume): `name`, `plate` (entry, null without a name
  plate), `plate_width`, `face` (file), `status`, `voice`, `pick_voice`, `bank`, `stage`, `music`.
- `attributes`: `keys` (88) and `default`: `portrait` (file), `facing`, `band`, `silhouette`,
  `colour` [r, g, b].

`docs/research/arcade/` and the report on the flow describe the screens these numbers draw.
TODO: the secret operator overlay (FUN_801B996C, FUN_801BABD4) and the texts of the modes the arcade
flow cannot enter (team battle, time attack, survival, practice) are not converted.
"""

from __future__ import annotations

import re
import struct
from dataclasses import dataclass
from typing import Sequence

import numpy as np

import arcade
import icons
from common import Output, log
from vram import TIM_ID, Vram, png_bytes, rgba, unpack_indices

VRAM_ROWS = 1024
SCREEN_WIDTH, SCREEN_HEIGHT = 512, 480
HUD_DIR = "hud"
ICON_CROP = (38, 0, 432)        # the title picture's logo: x, y and side of the square
SCREENS_DIR = "screens/arcade"
BLOCK_HEADER = 12
STP_BIT = 0x8000
MAX_STRING = 300

# Categories (flow report §4).
SYSTEM_CATEGORIES = (3, 1, 2, 6)
CAT_FONT_PATCH = 5
FONT_PATCH_AT = (0x368, 0x50)
CAT_SELECT = 7
CAT_PANELS = 8
PANEL_ENTRY = (2, 1)            # by select layout
CAT_RANK_TITLES = 9
RANK_TITLES = 3
SELECT_FACES = (10, 11)         # by select layout
CAT_FACES = 11
CAT_PLATES = 14
CAT_PORTRAITS = 16
CAT_VS = 17
CAT_ENDING = 43
ENDING_BACKGROUND, ENDING_LOGO = 0, 1
VS_KINDS = 4
VS_DARK_KIND = 3
VS_DARK_PALETTE = 3

# Fonts: FUN_801B2B54's table; `FUN_801B2488`: CLUT x = 256 + 16·(k & 15), y = 480 + (k >> 4).
FONT_TABLE = 0x80178E14
FONT_RECORD = "<IIHHHHHH"
FONT_COUNT = 3
FONT_COLOURS = 16
TEXT_CLUT_X, TEXT_CLUT_Y = 256, 480
TEXT_CLUT_COLOURS = 16
FIRST_CHAR, LAST_CHAR = 0x20, 0x5F
SHEET_COLUMNS = 16

# HUD: FUN_801B374C (life), FUN_801B35FC (timer), FUN_801B3B34 (marks), FUN_801B3E20 (names).
HUD_TPAGE = 0x0C
LIFE_RECORDS = 0x801FF3DC
LIFE_RECORD = 0x1C
LIFE_LENGTH = 210
LIFE_FILL_TOP, LIFE_FILL_BOTTOM = 4, 0x14
LIFE_GROW_DX = (0xD5, 3)        # P1 grows left from here, P2 right
LIFE_FILL_UV = (0x50, 0x52, 2, 16)
LIFE_BACKING_UV = (0x50, 0x4E, 2, 24)
LIFE_BACKING_DX, LIFE_BACKING_WIDTH = 8, 200
LIFE_CAP_RIGHT_DX = 208
LIFE_CAP_SIZE = (8, 24)
LIFE_CLUTS = {"health": 0x7910, "damage": 0x7911, "empty": 0x7912}
DIGIT_TPAGE = 0x0D
DIGIT_UV = 0x80178FA4
DIGITS = 12                     # 0–9 and the two halves of ∞
DIGIT_SIZE = (20, 46)
DIGIT_CLUT = 0x7918
INFINITY_RIGHT, INFINITY_LEFT = 11, 10
TIMER_X, TIMER_TENS_X, TIMER_Y = 0x100, 0xEC, 0x16
MARK_WORDS = 0x8021F140         # won, empty
MARK_SIZE = (20, 18)
MARK_Y = 0x46
MARK_X = (0xD4, 0x118)
MARK_STEP = (-0x14, 0x14)
MARK_BLINK = 0x10
NAME_POSITIONS = 0x80178FE0     # stride 8: x, y
NAME_COSTUME_CLUTS = 0x80178FF0  # 4 × (name, backing)
NAME_HEIGHT = 16
PLATE_UV = (0xC8, 0x5C, 2, 10)
PLATE_MARGIN, PLATE_TOP, PLATE_BOTTOM = 6, 9, 0x13
COSTUMES = 4
STATUS_Y = 0x18
STATUS_CLOCK_X = 0x801790FC     # s16 per side
STATUS_PROMPT_X = 0x80179100
STATUS_CONTINUE_X = 0x80179104
STATUS_CONTINUE_Y = 0x1B0
STATUS_GAME_OVER_DX = 0x20
STREAK_TABLE = 0x80179000       # 4 × {format, s16 x per side}
STREAK_ENTRIES = 4
STREAK_ARGS = (1, 8, None, 0x1B0)
WINNER_DX, LOSER_DX, SIDE_DX = 0x42, 0x4B, 0x110
WINS_RIGHT, WINS_PER_LETTER = 0x100 - 0x5A, 15

# Prompts: FUN_801B13A8, FUN_801B1278, FUN_801B114C.
PROMPTS = 0x8017894C
PROMPT_COUNT = 7
PROMPT_Y, PROMPT_COLOUR, PROMPT_BLINK, PROMPT_ALTERNATE = 0x16C, 5, 0x30, 0x40
SIDE_PROMPTS = 0x80178A18
SIDE_PROMPT_COUNT = 4
CREDITS = 0x80178A6C
CREDIT_COUNT = 6
CREDITS_X, CREDITS_Y = (10, 0x172), 0x1C2

# Title: FUN_801BD318.
TITLE_AT = (0, 512)
TITLE_CLUT = 0x7A10
LOGO_AT = (256, 512)
LOGO_SIZE = (96, 16)
LOGO_CLUT = 0x7A50
TITLE_LOGO_XY = (0xD4, 0x184)

# Select: FUN_801C06E4 and its draw routines.
LAYOUTS = 0x801FFAA8
LAYOUT_FIELDS = 13
# Fields no routine reads (a capstone scan of the select code): 0, 6.
LAYOUT_NAMES = {1: "portrait_y", 2: "plate_y", 3: "panel_top", 4: "faces_y", 5: "face_height",
                7: "cursor_height", 8: "cursor_y", 9: "tag_y", 10: "timer_y", 12: "prompt_colour"}
LAYOUT_FACE_HEIGHT, LAYOUT_CURSOR_HEIGHT, LAYOUT_PANEL_TOP, LAYOUT_TIMER_CLUT = 5, 7, 3, 11
PLAYER_LAYOUT = 0x80179B58
PLAYER_RECORD = 0x28
PLAYER_CURSOR_WORDS = 0x14      # u32 per layout
PLAYER_TAG_WORD = 0x1C
PLAYER_TAG_DX = 0x26
ROSTER = 0x80179BA8
ROSTER_SIZE = 18
CELLS = 0x801FFB10
CELLS_COLUMNS = 10
FACE_TABLE = 0x80179BBC         # stride 8: u32 UV | CLUT << 16, u16 tpage
FACE_WIDTH = 44
FRAME_TABLES = (0x80179C84, 0x80179D34)
FRAME_RECORD = "<8h"
FRAME_END = -1
FRAME_8BIT = 0x80
GRADIENT_INSET = 0x10
GRADIENT_BOTTOM_Y = 0x1E0
GRADIENT_BOTTOM_RED = (0, 0xE0)  # by layout
CURSOR_TPAGE = 0x801
CURSOR_WIDTH = 48               # two strips 24 wide
TAG_SIZE = (24, 16)
TILE_TPAGE = 0x802
TILE_WORDS = 0x801FFCF0
TILE_ROWS = 0x801FFCB0
TILE_MAP = 8
TILE_SIZE = 64
TILE_COLUMNS = 8
TILE_SCROLL_SCALE, TILE_SCROLL_SHIFT = -0x80, 4
SELECT_BANNER_AT = (0, 640)
SELECT_BANNER_SIZE = (288, 128)
SELECT_BANNER_CLUT = 0x7B10
SELECT_BANNER_XY = (112, 40)
SELECT_PLATE_CLUT = 0x791D
SELECT_PROMPT = {"x": 0x18, "step": 0x100, "y": 0x22}
BANDS = (0x801FFBB0, 0x801FFC2F)
BAND_BYTES = 0x7F
STATE_ANIM, DECIDED = 0x80179DF4, 0x80179DE4
STATE_BYTES = 16
PORTRAIT_WIDTH = 168
GLOW = {"width": PORTRAIT_WIDTH, "top": -0x14, "middle": 0xD0, "bottom": 0x118, "end_colour": [0xC0, 0xC0, 0xC0]}
SELECT_UNREFERENCED = {"divider": ("select_divider.png", 10), "new_tag": ("select_new_tag.png", 11)}

# VS: FUN_801B8A44, FUN_801B8880.
VS_POSITIONS = 0x801FF5C4       # stride 16: x, y, dx, dy, then VRAM numbers
VS_NAMES = 0x801FF604           # stride 8
VS_FRAME = 0x801795D8           # 4 × x, y, w, h
VS_RECORDS = 4
VS_FRAME_COLOUR = [0xF0, 0xF0, 0xF0]
VS_BACKGROUND_AT = (0, 512)
VS_BACKGROUND_SIZE = (256, 240)
VS_BACKGROUND_CLUT = 0x7950
VS_BACKGROUND_DRAWN = [512, 481]
VS_PORTRAIT = {"x": 4, "y": 6, "width": PORTRAIT_WIDTH, "height": 212, "source_y": 20}
VS_GRADIENT = {"top": 6, "middle": 0x70, "bottom": 0xDA, "end_colour": [0xC0, 0xC0, 0xC0]}
VS_SLIDE = {"start": 8, "shift": 3}
VS_NAME = {"advance": 30, "left": 0x12, "right": 0x1EE}
VS_UNKNOWN_NAME = 0x80179604

# Ranking: FUN_801C241C and the row routines.
RANK_BAND_AT = (768, 464)
RANK_BAND_SIZE = (512, 48)
RANK_BAND_CLUT = 0x7950
RANK_BAND = {"x": 0, "y": 0x24, "width": RANK_BAND_SIZE[0], "height": RANK_BAND_SIZE[1], "solid": 0x150,
             "strip": 6, "alpha": 0xF8, "alpha_step": -8}
RANK_ROW_STEP = 0x48
RANK_CELLS = {"rank": [0x12, -0x22], "face": [0x6A, -0x3A], "name": [0x9A, -0x38], "time": [0xDC, -0x22],
              "mark": [0x162, -0x1A], "entry": [0x1A0, -0x22], "usage": [0x188, -0x22]}
RANK_FONTS = {"rank": 1, "name": 0, "mark": 0, "entry": 1}
RANK_FACE_SIZE = [44, 58]
RANK_DIVIDERS = {"colour": [0x90, 0x90, 0x90], "rects": [[0xC, -0xE, 0x56, 8], [0x62, -8, 0x19E, 2]]}
RANK_SUFFIXES = 0x801FFD1C
RANK_SUFFIX_COUNT = 4
RANK_COLOURS = {"time": (0x801FFD2C, 5), "wins": (0x8021F384, 4), "usage": (0x8021F38C, 3)}
RANK_COLOUR_ROWS = 2
RANK_BARS = 0x80179EE0
RANK_BAR_WORDS = 5
RANK_BAR_LAYOUT = {"dx": 0x17C, "max_width": 0xB4, "height": 0x18, "depth": 8}
RANK_ALPHABET = 0x80179678
RANK_ALPHABET_SIZE = 40
RANK_REJECTED = 0x801FF624
RANK_REJECTED_COUNT = 5
RANK_FIGHT_ENTRY = 0x801FF638   # per side: wins x, y, name x, y

# Ending: FUN_801E5F50, the staff roll FUN_801E5E4C and FUN_801E5D28.
ENDING_BACKGROUND_SIZE = (SCREEN_WIDTH, SCREEN_HEIGHT)
ENDING_FADE_HOLD = 0xCA
ENDING_LOGO_XY = (70, 215)
ENDING_NAMCO_XY = (0xD4, 0xF0)
STAFF_PAGES = 0x8020491C        # {left, right} list pointers per page
STAFF_PAGE_COUNT = 10
STAFF_LEFT_X, STAFF_RIGHT_X = 0x1E, 0xDC
STAFF_FIRST_PAGE = 1            # its lists hang off the code, not the table
STAFF_FIRST_LISTS = (0x80204654, 0x80204684)
STAFF_FIRST_Y = (0x14, 0xEE)
STAFF_LEFT_Y, STAFF_RIGHT_Y = 0x19, 0xFF
STAFF_RIGHT_RAISED = {4: 0xE6, 7: 0xE6}
STAFF_LEFT_ONLY_PAGE = 6
STAFF_FONT = 0
STAFF_HEADER, STAFF_NAME, STAFF_END = "0", "1", "2"
STAFF_HEADER_COLOUR, STAFF_NAME_COLOUR = 1, 6
STAFF_HEADER_DY, STAFF_HEADER_STEP = -2, 0x16
STAFF_NAME_DX, STAFF_NAME_DY, STAFF_STEP = 0x14, -4, 0x14
STAFF_MAX_ITEMS = 64

# Demo banner: FUN_801B76AC.
BANNER_FACE = {"x": 0x1A0, "y": 0x168, "width": 44, "height": 58}
BANNER_NAME_RIGHT, BANNER_SELECTABLE_RIGHT, BANNER_PER_LETTER = 0x1CC, 0xF0, 12

# Records: 0x801FF454 + 4·key → name, plate entry, plate width, face entry, status, voice, bank, stage, music.
CHARACTER_RECORDS = 0x801FF454
CHARACTER_RECORD = "<I8B"
CHARACTER_KEYS = 88             # id 22 has no record; ids 0–21
PICK_VOICES = 0x8015FEB8
PICK_VOICE_STRIDE = 0x18
ATTRIBUTES = 0x801FF938
ATTRIBUTE_DEFAULT = 0x8021F350
ATTRIBUTE_FACING, ATTRIBUTE_BAND = 0x40, 0x80
ATTRIBUTE_SILHOUETTE = 0x13     # FUN_801BFA7C: one subtractive pass

# Every format a screen draws: key → (address, the control arguments in the format's order: None
# when the code computes it at run time). Value placeholders take no argument here.
# `status_*`: offsets from `hud.status`: x from `clock_x`, y from `y`; `status_continue` from
# `continue_x` and `continue_y`.
# `rank_time_*`, `rank_win*`: relative to the `time` cell; `rank_usage_*`: to the `usage` cell.
TEXTS: dict[str, tuple[int, tuple[int | None, ...]]] = {
    "replay": (0x8015F178, (7, 1, 0x154, 0x1E)),
    "round": (0x8015F4C0, (8, 2, 0x97, 0x70)),
    "final_round": (0x8015F4D4, (8, 2, 0x5B, 0x70)),
    "ready": (0x8015F52C, (9, 2, 0xA6, 0xE4)),
    "time_up": (0x8015F53C, (3, 2, 0x97, 0xE4)),
    "perfect": (0x8015F54C, (2, 2, 0x88, 0xE4)),
    "double_ko": (0x8015F560, (1, 2, 0x5B, 0xE4)),
    "ko": (0x8015F574, (1, 2, 0xC4, 0xE4)),
    "draw": (0x8015F584, (6, 2, 0xC4, 0x170)),
    "fight_game_over": (0x8015F594, (3, 2, 0x79, 200)),
    "wins": (0x8015F5A8, (4, 2, None, 0x170)),
    "winner": (0x8015F5BC, (3, 1, None, 0x68)),
    "loser": (0x8015F5CC, (3, 1, None, 0x68)),
    "you_win": (0x8015F5DC, (4, 2, 0x88, 0x170)),
    "you_lose": (0x8015F5F0, (5, 2, 0x88, 0x170)),
    "status_stage": (0x80179070, (7, 0, 0, 0)),
    "status_final": (0x80179084, (7, 0, 0, 0)),
    "status_clock_marks": (0x80179094, (5, 0, 0x7F, -2, 0xA0)),
    "status_clock_digits": (0x801790A4, (5, 0, 0x68, 0, 0x88, 0xAB)),
    "status_continue": (0x80179108, (9, 1, 0, 0)),
    "status_game_over": (0x80179120, (2, 0, STATUS_GAME_OVER_DX, 0)),
    "presents": (0x80179360, (2, 0xA0, 0xF0, 6)),
    "continue": (0x80179398, (9, 2, 0x5B, 200)),
    "game_over": (0x801793B0, (1, 2, 0x79, 200)),
    "demo_game_over": (0x801793B0, (2, 1, 0xAE, 0x104)),
    "challenger": (0x801793C4, (7, 2, 0x10, 0x120)),
    "banner_new_fighter": (0x801793EC, (0, 5, 0x114, 0x16E)),
    "banner_name": (0x80179400, (0, 3, None, 0x1A8)),
    "banner_characters": (0x8017940C, (10, 0, 0x28, 400)),
    "banner_selectable": (0x80179428, (10, 0, None, 0x1A8)),
    "banner_count": (0x80179440, (2, 1, 0x50, 0x18A)),
    "vs_name": (0x801795F8, (8, 2, None, None)),
    "vs_stage": (0x80179610, (6, 1, 0x1C, 0x2A)),
    "vs": (0x80179624, (0, 2, 0xE2, 0xFA)),
    "vs_coming_soon": (0x80179630, (1, 2, 0x4C, 0x3C)),
    "vs_who_is_it": (0x80179648, (3, 2, 0x6A, 0x154)),
    "title_copyright": (0x80179A84, (6, 0x30, 0x19C)),
    "title_rights": (0x80179AA8, (6, 0x30, 0x1B0)),
    "rank_time_marks": (0x8017A180, (None, None, 1, -4, 0x21, 0x50)),
    "rank_time_digits": (0x8017A190, (None, None, 1, 0, 0, 0x2C, 0x5E)),
    "rank_win_count": (0x8017A208, (None, None, 1, 0x12, 0)),
    "rank_wins_count": (0x8017A208, (None, None, 1, 0, 0)),
    "rank_win": (0x8017A218, (None, None, 1, 0x52, 0)),
    "rank_wins": (0x8017A228, (None, None, 1, 0x40, 0)),
    "rank_usage_full": (0x8017A1B8, (None, None, 1, 2, 0, 0, 0x3B, 4)),
    "rank_usage_none": (0x8017A1D0, (None, None, 1, 2, 0, 0, 0x3B, 4)),
    "rank_usage": (0x8017A1E8, (None, None, 1, 0, 0, 0, 0x24, 4, 0x2E)),
    "rank_countdown": (0x8017A238, (None, 6, 1, 0x1B8, 0x30)),
    "ending_clear": (0x80187DBC, (2, 1, 0x6E, 0x28)),
    "ending_you_are": (0x80187DD8, (2, 2, 0x7F, 0x78)),
    "ending_the": (0x80187DEC, (2, 2, 0xCF, 0xB4)),
    "ending_champion": (0x80187DF8, (2, 2, 0x7F, 0xF0, 0x110, 300)),
    "ending_your_time": (0x80187E10, (4, 1, 0x93, 0x154)),
    "ending_new_record": (0x80187E28, (6, 0, 0xC3, 0x1AE)),
    "ending_time_marks": (0x80187E3C, (4, 2, 0xBB, 0x17C, 0x10B, 0x116)),
    "ending_time_digits": (0x80187E4C, (4, 2, 0x82, 0x17C, 0xD2, 300)),
    "ending_staff_title": (0x80187E68, (2, 0, 0x7C, 0x19)),
    "ending_produced_by": (0x80187E88, (6, 0, 0xDC, 0xBD)),
    "ending_copyright": (0x80187E9C, (6, 0, 0x30, 400)),
    "ending_rights": (0x80187EC0, (6, 0, 0x30, 0x1A4)),
}

_CONTROL = re.compile(r"%(\d*)([A-Za-z%])")
_ARGUMENT_CODES = "cfHVp"
_VALUE_CODES = "dDxsCb"


def cstring(arc: arcade.ArcadeSet, addr: int) -> str:
    """A NUL-terminated string of the program."""
    data = bytearray()
    while len(data) < MAX_STRING:
        byte = arc.prog(addr + len(data), 1)[0]
        if byte == 0:
            break
        data.append(byte)
    return data.decode("latin-1")


def rgb(word: int) -> list[int]:
    """A packet colour, BBGGRR."""
    return [word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF]


def sprite_word(word: int) -> tuple[int, int, int]:
    """A sprite's UV + CLUT word: (u, v, CLUT id)."""
    return word & 0xFF, (word >> 8) & 0xFF, word >> 16


@dataclass
class TimBlock:
    x: int
    y: int
    w: int
    h: int
    words: np.ndarray | None    # None: truncated, a CLUT-only TIM's stub of a pixel block


def _tim_block(tim: bytes, cursor: int) -> tuple[TimBlock, int]:
    length, x, y, w, h = struct.unpack_from("<I4H", tim, cursor)
    available = (len(tim) - cursor - BLOCK_HEADER) // 2
    words = None
    if available >= w * h:
        words = np.frombuffer(tim, dtype="<u2", count=w * h, offset=cursor + BLOCK_HEADER).reshape(h, w)
    return TimBlock(x, y, w, h, words), cursor + length


def parse_tim(tim: bytes) -> tuple[TimBlock | None, TimBlock]:
    """A TIM's CLUT block (None without flag 8) and its pixel block."""
    magic, flags = struct.unpack_from("<II", tim, 0)
    if magic != TIM_ID:
        raise arcade.ArcadeError("not a TIM")
    cursor = 8
    clut = None
    if flags & 8:
        clut, cursor = _tim_block(tim, cursor)
    image, _ = _tim_block(tim, cursor)
    return clut, image


def tim_depth(tim: bytes) -> int:
    """Bits per texel from the TIM's mode."""
    mode = struct.unpack_from("<I", tim, 4)[0] & 7
    if mode > 1:
        raise arcade.ArcadeError(f"TIM mode {mode} is not paletted")
    return 8 if mode else 4


def stp(words: np.ndarray) -> np.ndarray:
    """FUN_801B18EC: bit 15 on every colour but word 0, which stays the GPU's transparent."""
    return np.where(words != 0, words | STP_BIT, 0).astype(np.uint16)


def upload(vram: Vram, tim: bytes, clut_at: tuple[int, int] | None = None,
           image_at: tuple[int, int] | None = None) -> None:
    """FUN_801B1A94: a TIM's blocks at their own rectangles, or those FUN_801B1CF4 is given; a block
    going to (0, 0) is skipped."""
    clut, image = parse_tim(tim)
    if clut is not None and clut.words is not None:
        x, y = clut_at if clut_at is not None else (clut.x, clut.y)
        if (x, y) != (0, 0):
            vram.words[y:y + clut.h, x:x + clut.w] = stp(clut.words)
    if image.words is not None:
        x, y = image_at if image_at is not None else (image.x, image.y)
        if (x, y) != (0, 0):
            vram.words[y:y + image.h, x:x + image.w] = image.words


def tim_file(arc: arcade.ArcadeSet, category: int, entry: int) -> bytes:
    """A category's TIM, unpacked unless it is stored plain."""
    data = arc.category(category)[entry]
    if struct.unpack_from("<I", data, 0)[0] == TIM_ID:
        return data
    return arcade.decompress(data)[0]


def upload_category(arc: arcade.ArcadeSet, vram: Vram, category: int) -> None:
    """FUN_801B1DAC: every entry of a category, in order."""
    for entry in range(len(arc.category(category))):
        upload(vram, tim_file(arc, category, entry))


def system_vram(arc: arcade.ArcadeSet) -> Vram:
    """FUN_801B1E58(0): what stays in VRAM on the 480-line display."""
    vram = Vram(VRAM_ROWS)
    for category in SYSTEM_CATEGORIES:
        upload_category(arc, vram, category)
    upload(vram, tim_file(arc, CAT_FONT_PATCH, 0), clut_at=(0, 0), image_at=FONT_PATCH_AT)
    return vram


def texel_indices(vram: Vram, word_x: int, row: int, w: int, h: int, depth: int, skip: int = 0) -> np.ndarray:
    """`w` × `h` texel indices from a VRAM word position, `skip` texels into its first word."""
    per_word = 16 // depth
    words = vram.words[row:row + h, word_x:word_x + (skip + w + per_word - 1) // per_word]
    return unpack_indices(words, depth)[:, skip:skip + w]


def picture(vram: Vram, word_x: int, row: int, w: int, h: int, depth: int, clut_id: int, skip: int = 0) -> np.ndarray:
    """RGBA of a VRAM rectangle through a CLUT of the same VRAM, as the GPU reads it."""
    cx, cy = arcade.clut_xy(clut_id)
    colours = vram.clut(cx, cy, 1 << depth)
    return rgba(colours[texel_indices(vram, word_x, row, w, h, depth, skip)])


def sprite(vram: Vram, tpage: int, u: int, v: int, w: int, h: int, clut_id: int) -> np.ndarray:
    """RGBA of a sprite from its texture page word, UV and CLUT id."""
    x, y = arcade.tpage_xy(tpage)
    depth = arcade.depth_bits(tpage)
    per_word = 16 // depth
    return picture(vram, x + u // per_word, y + v, w, h, depth, clut_id, u % per_word)


def own_picture(tim: bytes) -> np.ndarray:
    """RGBA of a TIM through its own (first) palette."""
    clut, image = parse_tim(tim)
    if clut is None or clut.words is None or image.words is None:
        raise arcade.ArcadeError("a TIM with no palette or no pixels")
    return rgba(stp(clut.words)[0][unpack_indices(image.words, tim_depth(tim))])


@dataclass(frozen=True)
class Font:
    table: int
    advance: int
    line: int
    width: int
    height: int
    tpage: int
    clut_base: int


def read_fonts(arc: arcade.ArcadeSet) -> list[Font]:
    """The hi-res metrics and glyph tables."""
    size = struct.calcsize(FONT_RECORD)
    fonts = []
    for k in range(FONT_COUNT):
        table, _low, advance, line, w, h, tpage, base = arc.prog_values(FONT_RECORD, FONT_TABLE + size * k)
        fonts.append(Font(table, advance, line, w, h, tpage, base))
    return fonts


def text_runs(fmt: str, args: Sequence[int | None], fonts: Sequence[Font]) -> list[dict]:
    """A format as FUN_801B25B8 draws it, split where font, colour or pen change.

    `args` holds the control arguments in the order of their codes (`%c` colour, `%f` font, `%H`,
    `%V` pen, `%p` layer); value placeholders stay in the text and take none. The font starts at 0
    on each call; the colour is what the call sets. A newline returns to the last `%H` on the next
    line. Without a value before it, a run's x follows from the advance; after one it is null.
    """
    remaining = iter(args)
    runs: list[dict] = []
    colour: int | None = None
    font = 0
    pen_x: int | None = None
    pen_y: int | None = None
    line_x: int | None = None
    text = ""

    def flush() -> None:
        nonlocal text, pen_x
        if not text:
            return
        runs.append({"text": text, "font": font, "colour": colour, "x": pen_x, "y": pen_y})
        plain = text.replace("%%", "")
        if pen_x is not None:
            pen_x = None if "%" in plain else pen_x + (len(plain) + text.count("%%")) * fonts[font].advance
        text = ""

    position = 0
    while position < len(fmt):
        char = fmt[position]
        if char == "\n":
            flush()
            pen_x = line_x
            pen_y = None if pen_y is None else pen_y + fonts[font].line
            position += 1
        elif char == "%":
            match = _CONTROL.match(fmt, position)
            if match is None:
                raise arcade.ArcadeError(f"bad format at {position}")
            code = match.group(2)
            position = match.end()
            if code == "%" or code in _VALUE_CODES:
                text += match.group()
                continue
            if code not in _ARGUMENT_CODES:
                raise arcade.ArcadeError(f"format code %{code} is not expected in a screen's text")
            flush()
            value = next(remaining)
            if code == "c":
                colour = value
            elif code == "f":
                font = 0 if value is None else value
            elif code == "H":
                pen_x = line_x = value
            elif code == "V":
                pen_y = value
        else:
            text += char
            position += 1
    flush()
    return runs


def _png(out: Output, rel: str, pixels: np.ndarray) -> None:
    out.write(rel, png_bytes(pixels))


def _screen_png(out: Output, name: str, pixels: np.ndarray) -> str:
    """Writes a picture of `screens/arcade/`; returns its name."""
    _png(out, f"{SCREENS_DIR}/{name}", pixels)
    return name


def _records(arc: arcade.ArcadeSet) -> list[tuple]:
    """The 88 character records."""
    pointers = arc.prog_values(f"<{CHARACTER_KEYS}I", CHARACTER_RECORDS)
    return [arc.prog_values(CHARACTER_RECORD, pointer) for pointer in pointers]


def _font_sheets(arc: arcade.ArcadeSet, vram: Vram, fonts: Sequence[Font], out: Output) -> dict[str, list[int]]:
    """A glyph sheet per font and colour whose CLUT is loaded; returns those colours by font."""
    available = {}
    codes = range(FIRST_CHAR, LAST_CHAR + 1)
    rows = (len(codes) + SHEET_COLUMNS - 1) // SHEET_COLUMNS
    for f, font in enumerate(fonts):
        uvs = arc.prog_values(f"<{len(codes)}H", font.table + 2 * FIRST_CHAR)
        x, y = arcade.tpage_xy(font.tpage)
        colours = []
        for colour in range(FONT_COLOURS):
            k = colour + font.clut_base
            palette = vram.clut(TEXT_CLUT_X + TEXT_CLUT_COLOURS * (k & 15), TEXT_CLUT_Y + (k >> 4), TEXT_CLUT_COLOURS)
            if not palette.any():
                continue
            sheet = np.zeros((rows * font.height, SHEET_COLUMNS * font.width, 4), dtype=np.uint8)
            for n, code in enumerate(codes):
                if code == FIRST_CHAR:
                    continue
                u, v = uvs[n] & 0xFF, uvs[n] >> 8
                indices = texel_indices(vram, x + u // 4, y + v, font.width, font.height, 4, u % 4)
                row, column = divmod(n, SHEET_COLUMNS)
                sheet[row * font.height:(row + 1) * font.height,
                      column * font.width:(column + 1) * font.width] = rgba(palette[indices])
            _png(out, f"{HUD_DIR}/font_{f}_{colour}.png", sheet)
            colours.append(colour)
        available[str(f)] = colours
    return available


def convert_hud(arc: arcade.ArcadeSet, vram: Vram, fonts: Sequence[Font], out: Output) -> dict:
    """`hud/`; returns `screens.json`'s `hud` section (`layout`) and the fonts' `colours`."""
    for name, clut in LIFE_CLUTS.items():
        _png(out, f"{HUD_DIR}/bar_{name}.png", sprite(vram, HUD_TPAGE, *LIFE_FILL_UV, clut))
    _png(out, f"{HUD_DIR}/bar_backing.png", sprite(vram, HUD_TPAGE, *LIFE_BACKING_UV, LIFE_CLUTS["empty"]))
    cap_words = arc.prog_values("<2I", LIFE_RECORDS + 0x14)
    for side, word in zip(("left", "right"), cap_words):
        u, v, clut = sprite_word(word)
        _png(out, f"{HUD_DIR}/bar_cap_{side}.png", sprite(vram, HUD_TPAGE, u, v, *LIFE_CAP_SIZE, clut))
    for digit, word in enumerate(arc.prog_values(f"<{DIGITS}I", DIGIT_UV)):
        u, v, _ = sprite_word(word)
        _png(out, f"{HUD_DIR}/digit_{digit}.png", sprite(vram, DIGIT_TPAGE, u, v, *DIGIT_SIZE, DIGIT_CLUT))
    for name, word in zip(("won", "empty"), arc.prog_values("<2I", MARK_WORDS)):
        u, v, clut = sprite_word(word)
        _png(out, f"{HUD_DIR}/mark_{name}.png", sprite(vram, HUD_TPAGE, u, v, *MARK_SIZE, clut))

    costume_cluts = arc.prog_values(f"<{2 * COSTUMES}H", NAME_COSTUME_CLUTS)
    for costume in range(COSTUMES):
        plate = sprite(vram, HUD_TPAGE, *PLATE_UV, costume_cluts[2 * costume + 1])
        _png(out, f"{HUD_DIR}/plate_{costume}.png", plate)
    names = {}
    for key, record in enumerate(_records(arc)):
        entry, width = record[1], record[2]
        if width == 0:
            continue
        costume = key & 3
        tim = tim_file(arc, CAT_PLATES, entry)
        cx, cy = arcade.clut_xy(costume_cluts[2 * costume])
        indices = _plate_indices(tim, width)
        _png(out, f"{HUD_DIR}/name_{key:02d}.png", rgba(vram.clut(cx, cy, 16)[indices]))
        names[str(key)] = {"file": f"name_{key:02d}.png", "width": width, "plate": f"plate_{costume}.png"}
    colours = _font_sheets(arc, vram, fonts, out)
    font_metrics = {str(f): {"advance": font.advance, "line": font.line, "width": font.width, "height": font.height,
                             "first": FIRST_CHAR, "columns": SHEET_COLUMNS} for f, font in enumerate(fonts)}
    out.write_json(f"{HUD_DIR}/hud.json", {"names": names, "digits": DIGITS, "fonts": font_metrics})
    return {"layout": _hud_layout(arc, fonts), "colours": colours}


def _plate_indices(tim: bytes, width: int) -> np.ndarray:
    """A name plate's texels: 16 rows, `width` long."""
    _, image = parse_tim(tim)
    if image.words is None:
        raise arcade.ArcadeError("a name plate with no pixels")
    return unpack_indices(image.words, tim_depth(tim))[:NAME_HEIGHT, :width]


def _side_values(arc: arcade.ArcadeSet, addr: int) -> list[int]:
    return list(arc.prog_values("<2h", addr))


def _hud_layout(arc: arcade.ArcadeSet, fonts: Sequence[Font]) -> dict:
    life = []
    for side in range(2):
        record = LIFE_RECORDS + LIFE_RECORD * side
        direction, x, y = arc.prog_values("<3h", record + 0xA)
        life.append({"direction": direction, "x": x, "y": y, "grow_x": x + LIFE_GROW_DX[side]})
    streak = []
    for k in range(STREAK_ENTRIES):
        pointer, *xs = arc.prog_values("<I2h", STREAK_TABLE + 8 * k)
        streak.append({"runs": text_runs(cstring(arc, pointer), STREAK_ARGS, fonts), "x": xs})
    return {
        "life": {
            "sides": life,
            "length": LIFE_LENGTH,
            "fill_top": LIFE_FILL_TOP,
            "fill_bottom": LIFE_FILL_BOTTOM,
            "backing_dx": LIFE_BACKING_DX,
            "backing_width": LIFE_BACKING_WIDTH,
            "cap_right_dx": LIFE_CAP_RIGHT_DX,
        },
        "timer": {"x": TIMER_X, "tens_x": TIMER_TENS_X, "y": TIMER_Y, "width": DIGIT_SIZE[0], "height": DIGIT_SIZE[1],
                  "infinity": [INFINITY_LEFT, INFINITY_RIGHT]},
        "marks": {"x": list(MARK_X), "step": list(MARK_STEP), "y": MARK_Y, "blink_mask": MARK_BLINK},
        "names": {"x": [arc.prog_values("<h", NAME_POSITIONS + 8 * side)[0] for side in range(2)],
                  "y": arc.prog_values("<h", NAME_POSITIONS + 2)[0], "height": NAME_HEIGHT,
                  "plate_margin": PLATE_MARGIN, "plate_top": PLATE_TOP, "plate_bottom": PLATE_BOTTOM},
        "status": {"y": STATUS_Y, "clock_x": _side_values(arc, STATUS_CLOCK_X),
                   "prompt_x": _side_values(arc, STATUS_PROMPT_X), "continue_x": _side_values(arc, STATUS_CONTINUE_X),
                   "continue_y": STATUS_CONTINUE_Y, "prompt_colour": PROMPT_COLOUR, "streak": streak},
        "fight": {"wins_right": WINS_RIGHT, "wins_per_letter": WINS_PER_LETTER, "winner_x": [WINNER_DX, WINNER_DX + SIDE_DX],
                  "loser_x": [LOSER_DX, LOSER_DX + SIDE_DX]},
    }


def _prompt_entries(arc: arcade.ArcadeSet, table: int, count: int) -> list[dict]:
    entries = []
    for k in range(count):
        pointer, x = arc.prog_values("<Ih", table + 8 * k)
        entries.append({"text": cstring(arc, pointer), "x": x})
    return entries


def _select_vram(arc: arcade.ArcadeSet, system: Vram, layout: int) -> Vram:
    """The system VRAM with what FUN_801C06E4 loads for a layout."""
    vram = system.copy()
    upload_category(arc, vram, CAT_SELECT)
    upload_category(arc, vram, SELECT_FACES[layout])
    upload(vram, tim_file(arc, CAT_PANELS, PANEL_ENTRY[layout]))
    return vram


def _select_frames(arc: arcade.ArcadeSet, vram: Vram, layout: int, out: Output) -> list[dict]:
    frames = []
    size = struct.calcsize(FRAME_RECORD)
    table = FRAME_TABLES[layout]
    while True:
        mode, x, y, w, h, u_words, v, clut = arc.prog_values(FRAME_RECORD, table + size * len(frames))
        if mode == FRAME_END:
            return frames
        depth = 8 if mode & FRAME_8BIT else 4
        pixels = picture(vram, u_words, v, w, h, depth, clut & 0xFFFF)
        file = _screen_png(out, f"select_frame_{layout}_{len(frames)}.png", pixels)
        frames.append({"file": file, "x": x, "y": y, "width": w, "height": h})


def _select_layout(arc: arcade.ArcadeSet, system: Vram, layout: int, out: Output) -> dict:
    vram = _select_vram(arc, system, layout)
    fields = arc.prog_values(f"<{LAYOUT_FIELDS}i", LAYOUTS + 4 * LAYOUT_FIELDS * layout)
    record = {name: fields[k] for k, name in LAYOUT_NAMES.items()}
    record["frames"] = _select_frames(arc, vram, layout, out)
    record["gradient"] = {"top": fields[LAYOUT_PANEL_TOP] + GRADIENT_INSET, "bottom": GRADIENT_BOTTOM_Y,
                          "top_colour": [0, 0, 0], "bottom_colour": [GRADIENT_BOTTOM_RED[layout], 0, 0]}
    faces = {}
    roster = arc.prog_values(f"<{ROSTER_SIZE}B", ROSTER)
    for character in roster:
        word, tpage = arc.prog_values("<IH", FACE_TABLE + 8 * character)
        u, v, clut = sprite_word(word)
        pixels = sprite(vram, tpage, u, v, FACE_WIDTH, fields[LAYOUT_FACE_HEIGHT], clut)
        if pixels[..., 3].any():    # layout 0 holds no face for the fighters it can never show
            faces[str(character)] = _screen_png(out, f"select_face_{layout}_{character}.png", pixels)
    record["faces"] = faces
    cursors = []
    for side in range(2):
        word = arc.prog_values("<I", PLAYER_LAYOUT + PLAYER_RECORD * side + PLAYER_CURSOR_WORDS + 4 * layout)[0]
        u, v, clut = sprite_word(word)
        pixels = sprite(vram, CURSOR_TPAGE, u, v, CURSOR_WIDTH, fields[LAYOUT_CURSOR_HEIGHT], clut)
        cursors.append(_screen_png(out, f"select_cursor_{side}_{layout}.png", pixels))
    record["cursors"] = cursors
    digits = []
    for digit in range(10):
        word = arc.prog_values("<I", DIGIT_UV + 4 * digit)[0]
        u, v, _ = sprite_word(word)
        pixels = sprite(vram, DIGIT_TPAGE, u, v, *DIGIT_SIZE, fields[LAYOUT_TIMER_CLUT])
        digits.append(_screen_png(out, f"select_digit_{layout}_{digit}.png", pixels))
    record["digits"] = digits
    return record


def _select_plates(arc: arcade.ArcadeSet, vram: Vram, out: Output) -> dict[str, str]:
    """The name plates as the select screen shows them: one file per entry, at its longest width."""
    widths: dict[int, int] = {}
    for record in _records(arc):
        if record[2]:
            widths[record[1]] = max(widths.get(record[1], 0), record[2])
    cx, cy = arcade.clut_xy(SELECT_PLATE_CLUT)
    colours = vram.clut(cx, cy, 16)
    return {str(entry): _screen_png(out, f"select_plate_{entry}.png",
                                    rgba(colours[_plate_indices(tim_file(arc, CAT_PLATES, entry), width)]))
            for entry, width in sorted(widths.items())}


def _select_section(arc: arcade.ArcadeSet, system: Vram, out: Output) -> dict:
    layouts = [_select_layout(arc, system, layout, out) for layout in range(len(SELECT_FACES))]
    vram = _select_vram(arc, system, 0)
    players = []
    for side in range(2):
        at = PLAYER_LAYOUT + PLAYER_RECORD * side
        portrait_x, plate_x = arc.prog_values("<2h", at)
        u, v, clut = sprite_word(arc.prog_values("<I", at + PLAYER_TAG_WORD)[0])
        tag = _screen_png(out, f"select_tag_{side}.png", sprite(vram, CURSOR_TPAGE, u, v, *TAG_SIZE, clut))
        players.append({"portrait_x": portrait_x, "plate_centre_x": plate_x,
                        "tag": {"file": tag, "dx": arc.prog_values("<h", at + PLAYER_TAG_DX)[0]}})
    cells = []
    for parity in range(2):
        rows = []
        for row in range(2):
            at = CELLS + 0x50 * parity + 0x28 * row
            values = arc.prog_values(f"<{2 * CELLS_COLUMNS}H", at)
            rows.append([[values[2 * k], values[2 * k + 1]] for k in range(CELLS_COLUMNS)])
        cells.append(rows)
    rows = [list(arc.prog_values(f"<{TILE_MAP}B", TILE_ROWS + TILE_MAP * r)) for r in range(TILE_MAP)]
    tile_files = {}
    for index in sorted({i for row in rows for i in row}):
        u, v, clut = sprite_word(arc.prog_values("<I", TILE_WORDS + 4 * index)[0])
        pixels = sprite(vram, TILE_TPAGE, u, v, TILE_SIZE, TILE_SIZE, clut)
        tile_files[str(index)] = _screen_png(out, f"select_tile_{index}.png", pixels)
    banner = picture(vram, *SELECT_BANNER_AT, *SELECT_BANNER_SIZE, 8, SELECT_BANNER_CLUT)
    unreferenced = {name: _screen_png(out, file, own_picture(tim_file(arc, CAT_SELECT, entry)))
                    for name, (file, entry) in SELECT_UNREFERENCED.items()}
    return {
        "layouts": layouts,
        "players": players,
        "roster": list(arc.prog_values(f"<{ROSTER_SIZE}B", ROSTER)),
        "cells": cells,
        "face_width": FACE_WIDTH,
        "tiles": {"size": TILE_SIZE, "columns": TILE_COLUMNS, "scroll_scale": TILE_SCROLL_SCALE,
                  "scroll_shift": TILE_SCROLL_SHIFT, "files": tile_files, "rows": rows},
        "banner": {"file": _screen_png(out, "player_select.png", banner),
                   "x": SELECT_BANNER_XY[0], "y": SELECT_BANNER_XY[1]},
        "plates": _select_plates(arc, vram, out),
        "plate_height": NAME_HEIGHT,
        "timer": {"x": TIMER_X, "tens_x": TIMER_TENS_X},
        "prompt": SELECT_PROMPT,
        "bands": [list(arc.prog(table, BAND_BYTES)) for table in BANDS],
        "state_anim": list(arc.prog(STATE_ANIM, STATE_BYTES)),
        "decided": list(arc.prog(DECIDED, STATE_BYTES)),
        "portrait_width": PORTRAIT_WIDTH,
        "glow": GLOW,
        "unreferenced": unreferenced,
    }


def _isolated_vram(arc: arcade.ArcadeSet, files: Sequence[tuple[int, int]]) -> Vram:
    vram = Vram(VRAM_ROWS)
    for category, entry in files:
        upload(vram, tim_file(arc, category, entry))
    return vram


def _vs_section(arc: arcade.ArcadeSet, out: Output) -> dict:
    backgrounds = []
    for kind in range(VS_KINDS):
        files = [(CAT_VS, min(kind, VS_KINDS - 2))]
        if kind == VS_DARK_KIND:
            files.append((CAT_VS, VS_DARK_PALETTE))
        vram = _isolated_vram(arc, files)
        pixels = picture(vram, *VS_BACKGROUND_AT, *VS_BACKGROUND_SIZE, 8, VS_BACKGROUND_CLUT)
        backgrounds.append(_screen_png(out, f"vs_bg_{kind}.png", pixels))
    return {
        "backgrounds": backgrounds,
        "background_size": VS_BACKGROUND_DRAWN,
        "positions": [list(arc.prog_values("<4h", VS_POSITIONS + 16 * k)) for k in range(VS_RECORDS)],
        "names": [list(arc.prog_values("<4h", VS_NAMES + 8 * k)) for k in range(VS_RECORDS)],
        "frame": {"rects": [list(arc.prog_values("<4h", VS_FRAME + 8 * k)) for k in range(VS_RECORDS)],
                  "colour": VS_FRAME_COLOUR},
        "portrait": VS_PORTRAIT,
        "gradient": VS_GRADIENT,
        "slide": VS_SLIDE,
        "name": VS_NAME,
        "unknown_name": cstring(arc, VS_UNKNOWN_NAME),
    }


def _ranking_section(arc: arcade.ArcadeSet, out: Output) -> dict:
    titles = []
    for kind in range(RANK_TITLES):
        vram = _isolated_vram(arc, [(CAT_RANK_TITLES, kind)])
        pixels = picture(vram, *RANK_BAND_AT, *RANK_BAND_SIZE, 8, RANK_BAND_CLUT)
        titles.append(_screen_png(out, f"rank_title_{kind}.png", pixels))
    colours = {name: [list(arc.prog(table + length * row, length)) for row in range(RANK_COLOUR_ROWS)]
               for name, (table, length) in RANK_COLOURS.items()}
    ids = CHARACTER_KEYS // COSTUMES
    bars = [[rgb(word) for word in arc.prog_values(f"<{RANK_BAR_WORDS}I", RANK_BARS + 4 * RANK_BAR_WORDS * k)]
            for k in range(ids)]
    return {
        "titles": titles,
        "band": RANK_BAND,
        "row_step": RANK_ROW_STEP,
        "cells": RANK_CELLS,
        "fonts": RANK_FONTS,
        "face_size": RANK_FACE_SIZE,
        "dividers": RANK_DIVIDERS,
        "suffixes": [cstring(arc, pointer) for pointer in arc.prog_values(f"<{RANK_SUFFIX_COUNT}I", RANK_SUFFIXES)],
        "colours": colours,
        "bars": {**RANK_BAR_LAYOUT, "colours": bars},
        "alphabet": arc.prog(RANK_ALPHABET, RANK_ALPHABET_SIZE).decode("latin-1"),
        "rejected": [cstring(arc, pointer) for pointer in arc.prog_values(f"<{RANK_REJECTED_COUNT}I", RANK_REJECTED)],
        "fight_entry": [list(arc.prog_values("<4h", RANK_FIGHT_ENTRY + 8 * side)) for side in range(2)],
    }


def staff_lines(arc: arcade.ArcadeSet, table: int, y: int) -> list[dict]:
    """FUN_801E5D28: a list of pointers to strings whose first character is their kind. Blank lines
    only advance; positions are x from the block's, y on the screen."""
    lines = []
    for k in range(STAFF_MAX_ITEMS):
        item = cstring(arc, arc.prog_values("<I", table + 4 * k)[0])
        kind, text = item[:1], item[1:]
        if kind == STAFF_HEADER:
            if text:
                lines.append({"text": text, "x": 0, "y": y + STAFF_HEADER_DY, "colour": STAFF_HEADER_COLOUR})
            y += STAFF_HEADER_STEP
        elif kind == STAFF_NAME:
            if text:
                lines.append({"text": text, "x": STAFF_NAME_DX, "y": y + STAFF_NAME_DY, "colour": STAFF_NAME_COLOUR})
            y += STAFF_STEP
        else:
            if kind == STAFF_END:
                return lines
            y += STAFF_STEP
    raise arcade.ArcadeError(f"staff list at {table:#x} has no end")


def staff_pages(arc: arcade.ArcadeSet) -> list[dict]:
    """FUN_801E5E4C: the pages' left and right blocks; both blocks slide by the same offset."""
    pages = []
    for page in range(STAFF_PAGE_COUNT):
        left, right = arc.prog_values("<2I", STAFF_PAGES + 8 * page)
        left_y, right_y = STAFF_LEFT_Y, STAFF_RIGHT_RAISED.get(page, STAFF_RIGHT_Y)
        if page == STAFF_FIRST_PAGE:
            left, right = STAFF_FIRST_LISTS
            left_y, right_y = STAFF_FIRST_Y
        blocks = {"left": {"x": STAFF_LEFT_X, "slide": -1, "lines": staff_lines(arc, left, left_y)}}
        if page != STAFF_LEFT_ONLY_PAGE:
            blocks["right"] = {"x": STAFF_RIGHT_X, "slide": 1, "lines": staff_lines(arc, right, right_y)}
        pages.append(blocks)
    return pages


def _ending_section(arc: arcade.ArcadeSet, out: Output) -> dict:
    background = own_picture(tim_file(arc, CAT_ENDING, ENDING_BACKGROUND))
    logo = own_picture(tim_file(arc, CAT_ENDING, ENDING_LOGO))
    return {
        "background": {"file": _screen_png(out, "ending_logo.png", background),
                       "width": ENDING_BACKGROUND_SIZE[0], "height": ENDING_BACKGROUND_SIZE[1],
                       "fade_hold": ENDING_FADE_HOLD},
        "logo": {"file": _screen_png(out, "ending_namco.png", logo), "x": ENDING_LOGO_XY[0], "y": ENDING_LOGO_XY[1]},
        "namco_logo": {"file": "namco_logo.png", "x": ENDING_NAMCO_XY[0], "y": ENDING_NAMCO_XY[1]},
        "font": STAFF_FONT,
        "staff": staff_pages(arc),
    }


def _characters(arc: arcade.ArcadeSet, out: Output) -> list[dict]:
    characters = []
    faces: set[int] = set()
    for record in _records(arc):
        name, plate, width, face, status, voice, bank, stage, music = record
        faces.add(face)
        characters.append({
            "name": cstring(arc, name),
            "plate": plate if width else None,
            "plate_width": width,
            "face": f"face_{face}.png",
            "status": status,
            "voice": voice,
            "pick_voice": arc.prog_values("<h", PICK_VOICES + PICK_VOICE_STRIDE * voice)[0],
            "bank": bank,
            "stage": stage,
            "music": music,
        })
    for face in sorted(faces):
        _screen_png(out, f"face_{face}.png", own_picture(tim_file(arc, CAT_FACES, face)))
    return characters


def _attribute(word: int, colour: int) -> dict:
    return {
        "portrait": f"portrait_{word & ~(ATTRIBUTE_FACING | ATTRIBUTE_BAND)}.png",
        "facing": 1 if word & ATTRIBUTE_FACING else 0,
        "band": 1 if word & ATTRIBUTE_BAND else 0,
        "silhouette": word == ATTRIBUTE_SILHOUETTE,
        "colour": rgb(colour),
    }


def _attributes(arc: arcade.ArcadeSet, out: Output) -> dict:
    for entry in range(len(arc.category(CAT_PORTRAITS))):
        _screen_png(out, f"portrait_{entry}.png", own_picture(tim_file(arc, CAT_PORTRAITS, entry)))
    pointers = arc.prog_values(f"<{CHARACTER_KEYS}I", ATTRIBUTES)
    return {
        "keys": [_attribute(*arc.prog_values("<II", pointer)) for pointer in pointers],
        "default": _attribute(*arc.prog_values("<II", ATTRIBUTE_DEFAULT)),
    }


def convert_screens(arc: arcade.ArcadeSet, system: Vram, fonts: Sequence[Font], hud: dict, out: Output) -> None:
    """`screens/arcade/`."""
    title = picture(system, *TITLE_AT, SCREEN_WIDTH, SCREEN_HEIGHT, 8, TITLE_CLUT)
    icons.write(out, title, ICON_CROP)
    logo = picture(system, *LOGO_AT, *LOGO_SIZE, 4, LOGO_CLUT)
    document = {
        "width": SCREEN_WIDTH,
        "height": SCREEN_HEIGHT,
        "texts": {key: text_runs(cstring(arc, addr), args, fonts) for key, (addr, args) in TEXTS.items()},
        "text_colours": hud["colours"],
        "prompts": {
            "main": {"y": PROMPT_Y, "colour": PROMPT_COLOUR, "blink_mask": PROMPT_BLINK,
                     "entries": _prompt_entries(arc, PROMPTS, PROMPT_COUNT)},
            "side": {"blink_mask": PROMPT_BLINK, "alternate_mask": PROMPT_ALTERNATE,
                     "entries": _prompt_entries(arc, SIDE_PROMPTS, SIDE_PROMPT_COUNT)},
            "credits": {"x": list(CREDITS_X), "y": CREDITS_Y, "colour": PROMPT_COLOUR,
                        "entries": _prompt_entries(arc, CREDITS, CREDIT_COUNT)},
        },
        "title": {
            "picture": _screen_png(out, "title.png", title),
            "logo": {"file": _screen_png(out, "namco_logo.png", logo), "x": TITLE_LOGO_XY[0], "y": TITLE_LOGO_XY[1]},
            "copyright": ["title_copyright", "title_rights"],
        },
        "select": _select_section(arc, system, out),
        "vs": _vs_section(arc, out),
        "ranking": _ranking_section(arc, out),
        "ending": _ending_section(arc, out),
        "banner": {"face": BANNER_FACE, "name_right": BANNER_NAME_RIGHT, "selectable_right": BANNER_SELECTABLE_RIGHT,
                   "per_letter": BANNER_PER_LETTER},
        "hud": hud["layout"],
        "characters": _characters(arc, out),
        "attributes": _attributes(arc, out),
    }
    out.write_json(f"{SCREENS_DIR}/screens.json", document)


def convert(arc: arcade.ArcadeSet, out: Output) -> None:
    """`hud/` and `screens/arcade/` from the set."""
    system = system_vram(arc)
    fonts = read_fonts(arc)
    hud = convert_hud(arc, system, fonts, out)
    convert_screens(arc, system, fonts, hud, out)
    log.info("arcade: 2D screens and HUD")
