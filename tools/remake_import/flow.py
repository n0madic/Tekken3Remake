"""The game flow's data (docs/research/code/modes.md) as `tables/flow.json`.

The game keeps its progress, the mode context and several screens' state in blocks with a
layout of their own; the remake keeps those blocks as bytes (`remake/core/game/`), so their
initial images and the tables the screens read are converted as byte lists. Texts are decoded.
"""

from __future__ import annotations

from common import Block, Disc, Output

VS_PRACTICE_POS = 0x800B9134           # practice.ovl: the VS screen's portraits (per side x, y, slide x, slide y)
VS_PRACTICE_NAMES = 0x800B9144
VS_PRACTICE_TEXTS = {"vs": 0x800B0EB8, "caption": 0x800B0EC4}
PRACTICE_ROWS = (0x800B0A10, 3, 12)     # practice.ovl: per page (FREE, VS CPU, COMBO) the item id of each row
PRACTICE_COMBOS = (0x800B2AD8, 17)      # practice.ovl: per bank type (combo records, count)
PRACTICE_TEXTS = {"mode_select": 0x800B0C1C, "free": 0x800B0C30, "vs_cpu": 0x800B0C40, "combo": 0x800B0C50,
                  "player_select": 0x800B0C68, "reset": 0x800B0C80, "vs_cpu_title": 0x800B0D20,
                  "command_list": 0x800B0C9C, "training_dummy": 0x800B0CAC, "counter": 0x800B0CC0,
                  "attack_data": 0x800B0CD0, "freeze": 0x800B0CDC, "replay": 0x800B0CEC,
                  "key_display": 0x800B0CFC, "return": 0x800B0D08, "cpu_difficulty": 0x800B0D30,
                  "cpu_level": 0x800B0D40, "combo_player": 0x800B0D4C, "combo_type": 0x800B0D68, "none": 0x800B0D74}

PROGRESS = (0x800982D0, 0x218)    # the save block, flow globals and records (GameProgress)
KEY_TABLES = (0x80098290, 0x40)   # per player the mapped word of each physical pad bit
QUICK_GRID = (0x800229D4, 21 * 6)  # quick select: 3 rows × 7 cells (s16 x, s16 y, u8 key, pad)
QUICK_PREFS = (0x80098540, 2 * 0x34)
QUICK_STATE_ANIM = (0x80022A90, 3 * 16)
QUICK_DECIDED = (0x80022A70, 2 * 16)
UNLOCK_SCHEDULE = (0x800985F4, 2 * 14)   # ArcadeUnlocks' steps: (kind, value)
DEMO_CHARACTERS = (0x800E3040, 14)       # title.ovl: the demonstration fight's character list
ATTRIBUTES = 0x80097EDC           # per costume key: pointer to the attribute word (FUN_8004BA28)
ATTRIBUTE_KEYS = 0x5C
VS_BACKGROUNDS = (0x800228FC, 2 * 2)     # u16 per background kind
VS_CAPTION_COLOURS = (0x80022900, 4 * 7)  # u32 RGB per caption bar kind
VS_CAPTION_WIDTHS = (0x8002291C, 2 * 7)
VS_PLAYER_POS = 0x800B4ED0        # arcade.ovl: per side 4 s16 (x, y, slide x, slide y) of the portrait
VS_PLAYER_NAMES = 0x800B4EE0      # of the name
VS_TEAM_POS = 0x800B4EF0
VS_TEAM_NAMES = 0x800B4F00
VS_TEAM_ICONS = 0x800B0B9C        # arcade.ovl: per side u16 x, y, step, x with eight members
VS_TEXTS = {"vs": 0x800B0BAC, "stage": 0x800B0BB8, "round": 0x800B0BCC, "demo": 0x800B0BE0}   # arcade.ovl
TEXT_CODES = "%c%f%H%V"           # the text engine's colour, font and position prefix
MENU_ENTRIES = 0x800B9464         # title.ovl: 10 × (string, mode, two-player flag, index, pad)
MENU_ENTRY_COUNT = 10
BUTTON_ACTIONS = (0x800B9AF0, 2 * 14)   # title.ovl: the pad word of each key configuration action
BUTTON_TAIL = (0x800B9B0C, 2 * 8)       # the fixed words of Select, L3, R3, Start and the directions
RANKING_ALPHABET = (0x800B9674, 40)     # ranking.ovl: the name entry's symbols (no terminator)
RANKING_REJECTED = (0x800CBE44, 5)      # ranking.ovl: pointers to the names replaced by the character's
RANKING_SKIPPED = (0x800CBE58, 4)       # ranking.ovl: stages the backdrop never shows (s32)
RANKING_GON = 0x800B96B0                # ranking.ovl: the name that unlocks Gon
ENDING_MOVIES = (0x800B9BFC, 21 * 4)    # ending.ovl: per character and costume the ending movie (255 none)
STAFF_TITLES = 0x8011DAD8               # ending.ovl: the staff roll's title block (NULL-terminated pointers)
STAFF_ROWS = 0x8011DAE4                 # ending.ovl: the staff roll's rows (a kind digit, then the text)
STAFF_FONT_WIDE = (0x800BC014, 0x40)    # ending.ovl: glyph widths of the heading font (from '!')
STAFF_FONT_NARROW = (0x800BC054, 0x40)  # ending.ovl: glyph widths of the name font
THEATER_MOVIES = (0x800BA858, 26)       # ending.ovl: the Tekken 3 movie list (0x1C bytes per entry)
THEATER_TRACKS = (0x800BB49C, 29)       # ending.ovl: the Tekken 3 sound list
THEATER_ENTRY = 0x1C
THEATER_NAMES = {"0": (0x800BB234, 0x800BB7D4, 0x800BBE00), "1": (0x800BB1AC, 0x800BBE18, 0x800BBE20),
                 "2": (0x800BBE2C, 0x800BB7E8, 0x800BB7E8), "3": (0x800BB7F4, 0x800BB7C8, 0x800BBE3C)}
THEATER_TEXTS = {"cancel": 0x800BBE4C, "disc": 0x800BBE90, "sound": 0x800BBE98, "exit": 0x800BBEA0,
                 "locked": 0x800BBEA8, "theater": 0x800BBEC4, "bgm": 0x800BBECC, "arrange": 0x800BBED8,
                 "arcade": 0x800BBEE8}
OPTION_PAGES = (0x800EB2F0, 6)          # title.ovl: the options' page records (0x34 bytes)
OPTION_PAGE_SIZE = 0x34
OPTION_ITEM_SIZE = 0x14
PROGRESS_BASE = 0x800982D0
OPTION_PAGE_BYTE = 0x800EC5E8           # title.ovl: the page shown (items of the menus set it)
KEY_ROWS = (0x800EB4D8, 8)              # title.ovl: the key configuration's eight button rows (0x18 bytes)
KEY_DEFAULT = (0x800B9B1C, 8)           # title.ovl: the default action per button
KEY_NAMES = (0x800EB49C, 13)            # title.ovl: the action names (string pointers)
OPTION_MODES = (0x800EB45C, 8)          # title.ovl: GAME OPTION's mode pictures (mode, uv|clut)
RECORD_TITLES = (0x800EB5C8, 4)         # title.ovl: the records sub-page titles
OGRE_SCRIPTS = (0x800B0BF0, 0x800B0C24)  # arcade.ovl: the Ogre scene (the human is fighter 0 / 1), 10-byte events
SELECT_GRID_KEYS = (0x800B9638, 22)     # select.ovl: the character of each portrait cell
SELECT_PLAYER_LAYOUT = (0x800B9378, 2 * 0x28)   # per player the words copied to the record at +0x54
SELECT_STATE_ANIM = (0x800B966C, 2 * 8)  # per state the two bytes kept at +0x08/+0x0C
SELECT_DECIDED = (0x800B965C, 2 * 8)     # per state the costume-clash flags
SELECT_LAYOUTS = (0x801108FC, 2 * 0x30)  # the one-row and two-row layout words (context +0x11C)
SELECT_CONTEXT = (0x80118C48, 0x14C)     # the screen context's initial image (up to the sparks)


def _exe(disc: Disc, block: tuple[int, int]) -> list[int]:
    return disc.exe_u8(block[0], block[1])


def convert(disc: Disc, out: Output) -> None:
    blocks = disc.blocks()

    def string(overlay: Block, addr: int) -> str:
        return disc.text(overlay.name, addr)

    title = blocks["title"]
    entries = []
    for k in range(MENU_ENTRY_COUNT):
        at = MENU_ENTRIES + 8 * k
        text = title.u32(at)
        mode, two_players, index = title.u8s(at + 4, 3)
        entries.append({"text": string(title, text), "mode": mode, "two_players": two_players, "index": index})
    arcade, select, ranking, ending = blocks["arcade"], blocks["select"], blocks["ranking"], blocks["ending"]

    def text(overlay: Block, addr: int) -> str:
        return string(overlay, addr).replace(TEXT_CODES, "").replace("%f%c%H%V", "")

    def title_text(addr: int) -> str:
        if not addr:
            return ""
        if title.contains(addr):
            return string(title, addr)
        return disc.exe_text(addr)

    def variable(addr: int) -> dict:
        if addr == OPTION_PAGE_BYTE:
            return {"page": True}
        if addr:
            return {"progress": addr - PROGRESS_BASE}
        return {}

    pages = []
    for p in range(OPTION_PAGES[1]):
        r = OPTION_PAGES[0] + OPTION_PAGE_SIZE * p
        words = [title.u32(r + 4 * k) for k in range(13)]
        items = []
        for i in range(words[10] if words[8] else 0):
            e = words[8] + OPTION_ITEM_SIZE * i
            b = title.u8s(e + 0xC, 8)
            values = []
            if title.u32(e + 8):
                values = [title_text(title.u32(title.u32(e + 8) + 4 * k)) for k in range(b[1])]
            items.append({"variable": variable(title.u32(e)), "label": title_text(title.u32(e + 4)),
                          "values": values, "kind": b[0], "count": b[1], "action": b[2], "value": b[3],
                          "layout": b[4], "modes": b[6] | b[7] << 8})
        pages.append({"x": words[2], "y": words[3], "list_x": words[4], "list_y": words[5], "spacing": words[6],
                      "value_width": words[7], "title": title_text(words[9]), "items": items,
                      "back": words[12] & 0xFF, "back_value": words[12] >> 8 & 0xFF})

    def events(overlay: Block, addr: int) -> list[list[int]]:
        out = []
        while True:
            e = overlay.s16s(addr, 5)
            out.append(e)
            if e[1] == -1:
                return out
            addr += 10

    practice = blocks["practice"]
    combos = []
    for kind in range(PRACTICE_COMBOS[1]):
        table, count = practice.u32(PRACTICE_COMBOS[0] + 8 * kind), practice.u32(PRACTICE_COMBOS[0] + 8 * kind + 4)
        kind_combos = []
        for c in range(count):
            r = table + 12 * c
            steps, moves, counts = practice.u32(r), practice.u32(r + 4), practice.u32(r + 8)
            kind_combos.append({"steps": [practice.u32(steps + 4 * k) for k in range(counts & 0xFFFF)],
                                "moves": practice.u16s(moves, counts >> 16)})
        combos.append(kind_combos)

    key_rows = []
    for i in range(KEY_ROWS[1]):
        e = KEY_ROWS[0] + 0x18 * i
        raw = title.u8s(e, 0x18)
        key_rows.append({"mask": raw[0] | raw[1] << 8, "index": raw[2], "layer": raw[3],
                         "layout": title.s16s(e + 4, 8),
                         "colour": title.u32(e + 0x14)})

    movies = []
    for i in range(THEATER_MOVIES[1]):
        e = THEATER_MOVIES[0] + THEATER_ENTRY * i
        lines = [ending.u32(e + 0x14), ending.u32(e + 0x18)]
        movie, alternative, picture = ending.s16s(e, 3)
        movies.append({"movie": movie, "alternative": alternative, "picture": picture,
                       "mask": ending.u32(e + 8), "rule": ending.u32(e + 0xC),
                       "name": string(ending, ending.u32(e + 0x10)),
                       "lines": [string(ending, a) for a in lines if a]})
    tracks = []
    for i in range(THEATER_TRACKS[1]):
        e = THEATER_TRACKS[0] + THEATER_ENTRY * i
        tracks.append({"track": ending.u8s(e, 1)[0], "name": string(ending, ending.u32(e + 0x10))})

    def strings(overlay: Block, table: int) -> list[str]:
        out = []
        while overlay.u32(table):
            out.append(string(overlay, overlay.u32(table)))
            table += 4
        return out
    attributes = []
    for key in range(ATTRIBUTE_KEYS):
        pointer = disc.exe_u32(ATTRIBUTES + 4 * key, 1)[0]
        attributes.append(disc.exe_u32(pointer, 1)[0])

    out.write_json("tables/flow.json", {
        "progress": _exe(disc, PROGRESS),
        "key_tables": _exe(disc, KEY_TABLES),
        "quick_grid": _exe(disc, QUICK_GRID),
        "quick_prefs": _exe(disc, QUICK_PREFS),
        "quick_state_anim": _exe(disc, QUICK_STATE_ANIM),
        "quick_decided": _exe(disc, QUICK_DECIDED),
        "menu_entries": entries,
        "button_actions": title.u8s(*BUTTON_ACTIONS),
        "button_tail": title.u8s(*BUTTON_TAIL),
        "unlock_schedule": _exe(disc, UNLOCK_SCHEDULE),
        "demo_characters": title.u8s(*DEMO_CHARACTERS),
        "attributes": attributes,
        "vs_backgrounds": _exe(disc, VS_BACKGROUNDS),
        "vs_caption_colours": _exe(disc, VS_CAPTION_COLOURS),
        "vs_caption_widths": _exe(disc, VS_CAPTION_WIDTHS),
        "vs_player_pos": arcade.s16s(VS_PLAYER_POS, 8),
        "vs_player_names": arcade.s16s(VS_PLAYER_NAMES, 8),
        "vs_team_pos": arcade.s16s(VS_TEAM_POS, 8),
        "vs_team_names": arcade.s16s(VS_TEAM_NAMES, 8),
        "vs_team_icons": arcade.s16s(VS_TEAM_ICONS, 8),
        "vs_texts": {k: string(arcade, a).removeprefix(TEXT_CODES) for k, a in VS_TEXTS.items()},
        "ranking_alphabet": ranking.read(*RANKING_ALPHABET).decode("ascii"),
        "ranking_rejected": [string(ranking, ranking.u32(RANKING_REJECTED[0] + 4 * k)) for k in range(RANKING_REJECTED[1])],
        "ranking_skipped": [ranking.u32(RANKING_SKIPPED[0] + 4 * k) for k in range(RANKING_SKIPPED[1])],
        "ranking_gon": string(ranking, RANKING_GON),
        "ending_movies": ending.u8s(*ENDING_MOVIES),
        "staff_titles": strings(ending, STAFF_TITLES),
        "staff_rows": strings(ending, STAFF_ROWS),
        "staff_font_wide": ending.u8s(*STAFF_FONT_WIDE),
        "staff_font_narrow": ending.u8s(*STAFF_FONT_NARROW),
        "theater_movies": movies,
        "theater_tracks": tracks,
        "theater_names": {k: [string(ending, a) for a in v] for k, v in THEATER_NAMES.items()},
        "theater_texts": {k: text(ending, a) for k, a in THEATER_TEXTS.items()},
        "ogre_scripts": [events(arcade, a) for a in OGRE_SCRIPTS],
        "vs_practice_pos": practice.s16s(VS_PRACTICE_POS, 8),
        "vs_practice_names": practice.s16s(VS_PRACTICE_NAMES, 8),
        "vs_practice_texts": {k: string(practice, a).replace(TEXT_CODES, "") for k, a in VS_PRACTICE_TEXTS.items()},
        "practice_rows": [practice.u8s(PRACTICE_ROWS[0] + PRACTICE_ROWS[2] * k, PRACTICE_ROWS[2]) for k in range(PRACTICE_ROWS[1])],
        "practice_combos": combos,
        "practice_texts": {k: string(practice, a).replace(TEXT_CODES, "") for k, a in PRACTICE_TEXTS.items()},
        "option_pages": pages,
        "option_modes": [title.u32(OPTION_MODES[0] + 8 * k) for k in range(OPTION_MODES[1])],
        "key_rows": key_rows,
        "key_default": title.u8s(*KEY_DEFAULT),
        "key_names": [title_text(title.u32(KEY_NAMES[0] + 4 * k)) for k in range(KEY_NAMES[1])],
        "record_titles": [title_text(title.u32(RECORD_TITLES[0] + 4 * k)) for k in range(RECORD_TITLES[1])],
        "select_grid_keys": select.u8s(*SELECT_GRID_KEYS),
        "select_player_layout": select.u8s(*SELECT_PLAYER_LAYOUT),
        "select_state_anim": select.u8s(*SELECT_STATE_ANIM),
        "select_decided": select.u8s(*SELECT_DECIDED),
        "select_layouts": select.u8s(*SELECT_LAYOUTS),
        "select_context": select.u8s(*SELECT_CONTEXT),
    })
