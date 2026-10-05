"""The USA release's English localization, written to `imported/usa/` (docs/remake-plan.md,
"Game texts"): optional next to a Japanese disc (both given to `convert.py`), and converted with
the game when the USA disc is its source (then without the string pairs: its texts are the
game's own).

The remake plays as Japan Rev.1 and takes the USA release's English wherever it has one
(code/usa-version.md): the texts of the executable and the overlays, the staff roll, the
Theater's help lines, the move lists in their own encoding and shared glyph atlas, and the
pictures with text on them (Tekken Ball's rules page, the select screen's names, the title logo).
Generic interface wording is also kept in the project (`remake/content/texts_en.json`), so that
the English menus work without this conversion.

- `usa/texts.json`: per game memory block (`exe` and the overlays) the Japanese string body →
  its English one (the leading `%x` format codes left out), `theater_help` (the USA help lines by
  the Japanese strip index), `staff_titles` and `staff_rows` (the USA staff roll);
- `usa/move_lists/costume_NN.bin`: member 4 of each USA ARC (0x232 bytes, as FighterCopyMoveText
  copies them), `usa/move_glyphs.png` (the atlas's four bit planes one under the other) and
  `usa/move_text.json` (the fonts, the pre-rendered words' widths and the list title);
- `usa/select.tims`, `usa/title.png`, `usa/title_enbu.png`, `usa/how_to.png`;
- `usa/captions.json` and `usa/captions/`: the ending movies' English captions (captions.py).

Strings are paired with both discs in Japan Rev.1's layout (layout.py): the texts both keep at
one address, and the entries of the pointer tables both keep at one address (these first: in a
pool of texts of other lengths one address may hold a part of another text). `string_pairs`
pairs them through the code instead, the discs in their own layouts, for layout.py.
"""

from __future__ import annotations

import collections
import re
import struct

import captions
import media
from common import EXE_BASE, EXE_HEADER, OVERLAYS, SCREEN_SLOT, USA, Block, Disc, Output, log
from move_text import arc_members
import layout
from vram import Vram, png_bytes
import character
import overlay_images
import screen_vram
import screens
import stage

TABLE_SLOTS = 512
VOWELS = frozenset("AEIOUaeiou")
TEXT_SHARE = 0.6                         # letters, digits and spaces in a text (text_pairs)
FORMAT_CODES = re.compile(r"^(%[a-zA-Z])+")
# USA addresses of what has no Japanese counterpart.
USA_THEATER_HELP = (0x8010E1E4, 8)       # ending.ovl: the help lines (the Japanese strips are pictures)
USA_MOVE_FONTS = (0x80027AC0, 4)         # MoveTextDraw's fonts: advance x, y, glyph w, h, texture page
USA_WORD_WIDTHS = (0x800989F7, 0x20)     # the pre-rendered words 0x01–0x1F: widths in cells
USA_WORD_WIDTHS_HIGH = (0x80098976, 0x100)   # the words 0xA1–0xC3 (indexed by the byte)
USA_LIST_TITLE = 0x80027C14              # the list's title: pen, ordering entry, word 1
USA_LIST_TITLE_SIZE = 8
USA_ATLAS_ORIGIN = (80, 16)              # the shared atlas's rectangle (32 words × 120 rows)
# Japanese addresses of the tables whose USA versions replace them whole.
JP_STAFF_TITLES = 0x8011DAD8
JP_STAFF_ROWS = 0x8011DAE4
TITLE_ARCHIVE_OFFSET = (0x800EC570 - SCREEN_SLOT, 0x3324C)   # title.ovl: the title picture archive
ENBU_ARCHIVE_OFFSET = 0x800B9E60 - SCREEN_SLOT                # enbu.ovl: the same offset in both
SELECT_ARCHIVE_OFFSET = screen_vram.SELECT_ARCHIVE - SCREEN_SLOT
BALL_STAGE_ARC = 55
SKIPPED = re.compile(r"[\\;]|^BISLPS|^BASLUS")   # file names and the memory card's


class UsaError(Exception):
    """The USA image does not match what the localization expects (another release or pressing)."""


def body(text: str) -> str:
    """A string without its leading format codes."""
    return FORMAT_CODES.sub("", text)


def string_pairs(jp: dict[str, Block], us: dict[str, Block], amap: dict[tuple[str, int], int]) -> dict[str, dict[str, str]]:
    """Per block the Japanese string bodies whose English differs, from the discs in their own
    layouts: strings referenced directly (the code's references matched, `amap`), and the entries
    of pointer tables walked side by side while both hold string pointers (layout.py uses it
    to find texts when it makes a layout)."""
    found: dict[tuple[str, str], collections.Counter] = collections.defaultdict(collections.Counter)
    for (name, a), b in amap.items():
        if not jp[name].contains(a) or _vote(found, name, jp[name].string(a), us[name].string(b)):
            continue
        for k in range(TABLE_SLOTS):
            pj, pu = jp[name].u32(a + 4 * k), us[name].u32(b + 4 * k)
            if not _table_entry(found, name, jp[name], us[name], pj, pu):
                break
    return _texts(found)


def text_pairs(base: Disc, english: Disc) -> dict[str, dict[str, str]]:
    """Per block the base disc's string bodies whose English differs, both discs in Japan Rev.1's
    layout (layout.py): the strings both keep at one address, and the entries of the pointer
    tables both keep at one address."""
    tables: dict[tuple[str, str], collections.Counter] = collections.defaultdict(collections.Counter)
    places: dict[tuple[str, str], collections.Counter] = collections.defaultdict(collections.Counter)
    jp, us = base.blocks(), english.blocks()
    for name, block in jp.items():
        own, other = _Aside(block, base.strings), _Aside(us[name], english.strings)
        data = block.data
        for off in range(0, len(data) - 3, 4):
            _table_entry(tables, name, own, other, own.u32(block.base + off), other.u32(block.base + off))
        places_at = [block.base + off for off in range(len(data)) if block.text_start(off)]
        for addr in places_at + sorted(own.aside):
            # An empty English string at the place of a text is data the release lacks.
            text, english_text = own.string(addr), other.string(addr)
            if english_text and _texty(text) and _texty(english_text):
                _vote(places, name, text, english_text)
    # A text pointer tables name is paired through them: in a pool of texts of other lengths the
    # same place holds a part of another text.
    return _texts({**places, **tables})


def _texty(text: str | None) -> bool:
    """Whether a printable run reads as text, not as bytes of other data that happen to be
    printable: mostly letters, digits and spaces, with a vowel."""
    if not text:
        return False
    plain = body(text)
    return (len(plain) >= 2 and sum(c.isalnum() or c == " " for c in plain) >= TEXT_SHARE * len(plain)
            and any(c in VOWELS for c in plain))


class _Aside:
    """A block whose strings too long for their place are read aside (Disc.strings)."""

    def __init__(self, block: Block, aside: dict[tuple[str, int], str]) -> None:
        self.block = block
        self.aside = {addr: text for (name, addr), text in aside.items() if name == block.name}

    def u32(self, addr: int) -> int | None:
        return self.block.u32(addr)

    def string(self, addr: int) -> str | None:
        return self.aside[addr] if addr in self.aside else self.block.string(addr)


def _vote(found: dict, name: str, s: str | None, t: str | None, entry: bool = False) -> bool:
    # An empty string is a table's entry, not the object a reference names.
    if s is None or t is None or (not entry and not s):
        return False
    found[(name, body(s))][body(t)] += 1
    return True


def _pointer(block: Block | _Aside, addr: int | None) -> bool:
    return addr is not None and addr >= EXE_BASE and block.string(addr) is not None


def _table_entry(found: dict, name: str, jp: Block | _Aside, us: Block | _Aside, pj: int | None, pu: int | None) -> bool:
    """Votes for a pointer table's entry; False where the walk of a table stops."""
    if pj is None or pu is None:
        return False
    if _pointer(jp, pj) and _pointer(us, pu):
        return _vote(found, name, jp.string(pj), us.string(pu), True)
    if _pointer(jp, pj) or _pointer(us, pu):
        return False
    # Other data: equal words, addresses and small numbers keep the walk going.
    return not (pj != pu and pj >> 24 != 0x80 and (pj > 0xFFFF or pu > 0xFFFF))


def _texts(found: dict[tuple[str, str], collections.Counter]) -> dict[str, dict[str, str]]:
    out: dict[str, dict[str, str]] = collections.defaultdict(dict)
    for (name, jp_text), counter in sorted(found.items()):
        english = [t for t, _ in counter.most_common()]
        if len(english) != 1 or english[0] == jp_text or SKIPPED.search(jp_text):
            continue
        if name == "ending" and jp_text[:1].isdigit():
            continue    # the staff roll's rows: its USA table replaces the whole list
        if sum(c.isalpha() for c in jp_text) < 2 or 0 < sum(c.isalpha() for c in english[0]) < 2:
            continue    # stray bytes, and a prompt the USA code draws differently (its first letter)
        out[name][jp_text] = english[0]
    return dict(out)


def _strings(block: Block, table: int) -> list[str]:
    """A NULL-terminated table of string pointers (flow.py `strings`)."""
    out = []
    while block.u32(table):
        out.append(block.string(block.u32(table)) or "")
        table += 4
    return out


def _move_lists(usa: Disc, out: Output, slots: list[tuple[str, int, int, int]]) -> None:
    atlas = None
    for name, _slot, _kmd, arc_id in slots:
        members = arc_members(usa.bns(arc_id))
        if len(members) <= character.MOVE_LIST_MEMBER or not members[character.MOVE_LIST_MEMBER]:
            continue
        out.write(f"usa/move_lists/{name}.bin", members[character.MOVE_LIST_MEMBER][:character.MOVE_LIST_SIZE])
        if atlas is None:
            atlas = character.move_glyph_atlas(members[0], USA_ATLAS_ORIGIN)
    if atlas is None:
        raise UsaError(f"no USA move glyph atlas at {USA_ATLAS_ORIGIN}")
    out.write("usa/move_glyphs.png", png_bytes(atlas))
    exe = usa.exe
    fonts = [list(struct.unpack_from("<hhHHH", exe, USA_MOVE_FONTS[0] - EXE_BASE + EXE_HEADER + 10 * k))
             for k in range(USA_MOVE_FONTS[1])]
    out.write_json("usa/move_text.json", {
        "fonts": fonts,
        "atlas_rows": int(atlas.shape[0]) // 4,
        "word_widths": list(usa.exe_u8(*USA_WORD_WIDTHS)),
        "word_widths_high": list(usa.exe_u8(*USA_WORD_WIDTHS_HIGH)),
        "title": list(usa.exe_u8(USA_LIST_TITLE, USA_LIST_TITLE_SIZE)),
    })


def _pictures(usa: Disc, out: Output) -> None:
    for name, bns, offset in (("", OVERLAYS["title"][0], TITLE_ARCHIVE_OFFSET[1]),
                              ("_enbu", OVERLAYS["enbu"][0], ENBU_ARCHIVE_OFFSET)):
        picture, _logo = screens._title(out, f"usa/title{name}.png", None,
                                        overlay_images.archive_members(usa.bns(bns), offset))
        out.write(f"usa/title{name}.png", png_bytes(picture))
    select = {f.address: f for f in overlay_images.scan(usa.bns(OVERLAYS["select"][0]), 0)}
    # Recorded over an empty VRAM: the pictures bring their own CLUTs.
    screen_vram.write_tims(out, "usa/select.tims", Vram(), select[SELECT_ARCHIVE_OFFSET].tims)
    picture = stage.how_to_picture(out, "usa/how_to.png", arc_members(usa.bns(BALL_STAGE_ARC)))
    if picture is None:
        raise UsaError("no rules picture in the USA stg_v")
    out.write("usa/how_to.png", png_bytes(picture))


def _theater_help(ending: Block) -> list[str]:
    lines = []
    for k in range(USA_THEATER_HELP[1]):
        pointer = ending.u32(USA_THEATER_HELP[0] + 4 * k)
        if pointer is None:
            raise UsaError(f"no Theater help table at 0x{USA_THEATER_HELP[0]:08X}")
        lines.append(ending.string(pointer) or "")
    return lines


def _pairs_and_staff(base: Disc | None, usa: Disc) -> tuple[dict[str, dict[str, str]], list[int | None]]:
    """The string pairs and the USA staff roll tables: through the USA layout (text_pairs), or,
    for a USA image the layout does not fit (another pressing), through the code that references
    them (string_pairs), the discs in their own layouts."""
    try:
        english = usa.canonical()
    except layout.LayoutError as e:
        if base is None:
            raise
        log.warning("usa: %s; the texts are paired through the code", e)
        own, us = (base.raw or base).blocks(), usa.blocks()
        amap = layout.address_map(own, us)
        staff = [amap.get(("ending", layout.source_address(base.release, "ending", a)))
                 for a in (JP_STAFF_TITLES, JP_STAFF_ROWS)]
        return string_pairs(own, us, amap), staff
    texts = {} if base is None else text_pairs(base, english)
    return texts, [layout.source_address(USA, "ending", a) for a in (JP_STAFF_TITLES, JP_STAFF_ROWS)]


def convert(base: Disc | None, usa: Disc, out: Output, slots: list[tuple[str, int, int, int]]) -> None:
    """Converts the USA localization from the USA disc. `base` is the Japanese disc the game is
    converted from (either release, in Japan Rev.1's layout), or None when the USA disc is the
    game's source: then its texts are the game's own and only the rest is converted here. Raises
    UsaError when the image is not the expected release; `usa/texts.json`, which the remake
    looks for, is written last, so a failed run leaves no localization in use."""
    ending = usa.blocks()["ending"]
    texts, staff = _pairs_and_staff(base, usa)
    if None in staff:
        raise UsaError("no USA staff roll tables")
    document = {
        "blocks": texts,
        "theater_help": _theater_help(ending),
        "staff_titles": _strings(ending, staff[0]),
        "staff_rows": _strings(ending, staff[1]),
    }
    _move_lists(usa, out, slots)
    _pictures(usa, out)
    if base is not None:                      # a USA source's own captions are movies/captions.json
        try:
            sets = media.ending_caption_sets(usa.canonical().blocks()["ending"])
        except layout.LayoutError as e:
            log.warning("usa: no English movie captions: %s", e)
        else:
            captions.write(ending, sets, out, "usa")
    out.write_json("usa/texts.json", document)
    log.info("usa: %d texts in %d blocks, the move lists and pictures", sum(map(len, texts.values())), len(texts))
