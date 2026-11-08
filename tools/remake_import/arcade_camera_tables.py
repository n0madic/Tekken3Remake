"""The arcade camera director's constant tables → `imported/tables/camera.json` and its camera streams
→ `imported/tables/camera_streams.bin.gz`.

The game normalises its choice and hit lists in place at start-up (FUN_801D4230, FUN_801D4C9C); both run
here on a copy of the program, so the rows read back as the running game has them. Some rows of the
director are read past their tables (`blend_outs`), so the values are taken from the same copy.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass

import arcade
from common import Output, gzipped

STAGE_ROWS, STAGE_ROW_COUNT = 0x8017AB04, 14        # FUN_801D0320: H, lowest H, highest H, stream rescale, mode
STREAM_OFFSETS, STREAM_COUNT = 0x8017AC40, 473      # FUN_801D3110: per stream id − 1
STREAMS_AT = 0x231CC28                              # the file-table address the offsets count from
STREAMS_TAIL = 0x1000                               # bytes kept past the last stream's start
CHOICE_ROWS, CHOICE_ROW_COUNT, CHOICE_ROW_BYTES = 0x8017B410, 0xD7, 12
CHOICE_ENTRY_BYTES = 8
CHOICE_ENTRIES_END = 0x802044A8                     # the hit lists follow the choice lists
PRESETS, PRESET_COUNT, PRESET_BYTES = 0x8017BE24, 30, 0x14
SCRIPT_KINDS, SCRIPT_KIND_COUNT = 0x8017C07C, 0x1E  # FUN_801D4650: the preset (or a stream's −id) of a script
LAST_SCRIPT = 0x232                                 # scripts from here on are nothing
HIT_LISTS, HIT_LIST_COUNT = 0x8017C198, 3           # (records, count)
HIT_RECORD_BYTES = 0x14
HIT_ROWS, HIT_ROW_COUNT, HIT_ROW_BYTES = 0x8017C1B0, 4, 12
HIT_SCRIPT_FORMAT = "<4h2i4h4h"
INTRO_OFFSETS, INTRO_COUNT, INTRO_BYTES = 0x8017C1E8, 10, 0xE
REELS, REEL_COUNT = 0x80202DF8, 2                   # FUN_801D3554: the scenes' lists of scripts, each up to a negative value
ATTRACT_STYLES, ATTRACT_STYLE_COUNT = 0x8017C1E0, 4        # FUN_801D67F4
ATTRACT_PITCHES, ATTRACT_PITCH_COUNT = 0x80204514, 8       # FUN_801D6004
ATTRACT_SPEEDS, ATTRACT_SPEED_COUNT = 0x80204534, 2
RATINGS = 4
FULL_WEIGHT = 0x1000
# The image's part the tables live in, copied once to be normalised.
IMAGE_FROM, IMAGE_TO = 0x80175000, 0x80205000


@dataclass
class Image:
    """The tables' part of the program, writable."""
    data: bytearray

    def s16(self, address: int) -> int:
        return struct.unpack_from("<h", self.data, address - IMAGE_FROM)[0]

    def put16(self, address: int, value: int) -> None:
        struct.pack_into("<H", self.data, address - IMAGE_FROM, value & 0xFFFF)

    def u32(self, address: int) -> int:
        return struct.unpack_from("<I", self.data, address - IMAGE_FROM)[0]

    def values(self, fmt: str, address: int) -> tuple:
        return struct.unpack_from(fmt, self.data, address - IMAGE_FROM)


def reels(image: Image) -> list[list[int]]:
    """FUN_801D3554's lists, without their end marks."""
    out = []
    for pointer in image.values(f"<{REEL_COUNT}I", REELS):
        scripts = []
        while image.s16(pointer + 2 * len(scripts)) >= 0:
            scripts.append(image.s16(pointer + 2 * len(scripts)))
        out.append(scripts)
    return out


def s16_of(value: int) -> int:
    return (value & 0x7FFF) - (value & 0x8000)


def c_div(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a < 0) == (b < 0) else -q


def normalise_choices(image: Image) -> None:
    """FUN_801D4230: each row's weights become cumulative out of 0x1000, its two thresholds are set; a
    list two rows share is normalised twice, as in the game."""
    for row in range(CHOICE_ROW_COUNT):
        at = CHOICE_ROWS + row * CHOICE_ROW_BYTES
        records = image.u32(at)
        count = image.s16(at + 4)
        first_special = -1
        marked = -1
        cumulative = 0
        total = 0
        for k in range(count):
            record = records + k * CHOICE_ENTRY_BYTES
            flags = image.s16(record) & 0xFFFF
            if flags & 3 and first_special < 0:
                first_special = cumulative
            if flags & 0x10:
                flags &= 0xFFEF
                if marked < 0:
                    marked = cumulative
                    if cumulative < 1:
                        marked = -1
            if flags & 3 == 1 and image.s16(record + 4) != image.s16(record + 6):
                flags = flags & 0xFFFC | 2
            image.put16(record, flags)
            weight = image.s16(record + 2)
            total += weight
            cumulative = s16_of(weight + cumulative)
            image.put16(record + 2, cumulative)
        for k in range(count):
            record = records + k * CHOICE_ENTRY_BYTES
            image.put16(record + 2, c_div(image.s16(record + 2) << 12, total))
        image.put16(at + 8, FULL_WEIGHT if marked < 0 else c_div(marked << 12, total))
        image.put16(at + 6, FULL_WEIGHT)
        image.put16(at + 10, first_special)


def normalise_hit_lists(image: Image) -> None:
    """FUN_801D4C9C: the same for the hit lists' weights."""
    for k in range(HIT_LIST_COUNT):
        records, count = image.values("<Ii", HIT_LISTS + 8 * k)
        cumulative = 0
        total = 0
        for i in range(count):
            at = records + i * HIT_RECORD_BYTES + 2
            weight = image.s16(at)
            total += weight
            cumulative = s16_of(weight + cumulative)
            image.put16(at, cumulative)
        for i in range(count):
            at = records + i * HIT_RECORD_BYTES + 2
            image.put16(at, c_div(image.s16(at) << 12, total))


def choice_tables(image: Image) -> dict:
    """`choice_rows`: (first entry, threshold of mode 1, threshold of mode 2) per camera id;
    `choice_entries`: (flags, cumulative weight, script, mirrored script). A row's count is not kept: the
    game walks the entries by their weights alone."""
    pointers = [image.u32(CHOICE_ROWS + row * CHOICE_ROW_BYTES) for row in range(CHOICE_ROW_COUNT)]
    first = min(pointers)
    rows = []
    for row, pointer in enumerate(pointers):
        if (pointer - first) % CHOICE_ENTRY_BYTES:
            raise arcade.ArcadeError(f"camera row {row}: entries at {pointer:#x} are not aligned")
        at = CHOICE_ROWS + row * CHOICE_ROW_BYTES
        rows.append([(pointer - first) // CHOICE_ENTRY_BYTES, image.s16(at + 8), image.s16(at + 10)])
    entries = []
    for record in range(first, CHOICE_ENTRIES_END, CHOICE_ENTRY_BYTES):
        flags = image.s16(record) & 0xFFFF
        entries.append([flags, image.s16(record + 2), image.s16(record + 4), image.s16(record + 6)])
    return {"choice_rows": rows, "choice_entries": entries}


def hit_tables(image: Image) -> dict:
    """The hit rows, the records (cumulative weight, then a script per rating) and the scripts they name."""
    scripts: dict[int, int] = {}
    script_rows: list[list[int]] = []

    def script_of(pointer: int) -> int:
        if pointer not in scripts:
            scripts[pointer] = len(script_rows)
            script_rows.append(list(image.values(HIT_SCRIPT_FORMAT, pointer)))
        return scripts[pointer]

    lists = []
    for k in range(HIT_LIST_COUNT):
        records, count = image.values("<Ii", HIT_LISTS + 8 * k)
        rows = []
        for i in range(count):
            at = records + i * HIT_RECORD_BYTES
            rows.append([image.s16(at + 2)] + [script_of(image.u32(at + 4 + 4 * r)) for r in range(RATINGS)])
        lists.append(rows)
    hit_rows = []
    for k in range(HIT_ROW_COUNT):
        at = HIT_ROWS + k * HIT_ROW_BYTES
        hit_rows.append([image.values("<i", at)[0], image.s16(at + 4), image.values("<i", at + 8)[0]])
    return {"hit_rows": hit_rows, "hit_lists": lists, "hit_scripts": script_rows}


def blend_outs(image: Image) -> list[int]:
    """FUN_801D4B2C reads the preset table at the kind − 1 of any script, also of a stream (kind −id) or of
    none (kind 0): per −kind, the s16 it finds."""
    return [image.s16(PRESETS + 2 + (-n - 1) * PRESET_BYTES) for n in range(LAST_SCRIPT - SCRIPT_KIND_COUNT + 2)]


def stream_bytes(arc: arcade.ArcadeSet, offsets: list[int]) -> bytes:
    end = max(offsets) + STREAMS_TAIL
    return arc.read(STREAMS_AT, end)


def camera_tables(arc: arcade.ArcadeSet) -> tuple[dict, list[int]]:
    """The director's tables (for camera.json) and the streams' offsets."""
    image = Image(bytearray(arc.prog(IMAGE_FROM, IMAGE_TO - IMAGE_FROM)))
    normalise_choices(image)
    normalise_hit_lists(image)
    offsets = list(image.values(f"<{STREAM_COUNT}I", STREAM_OFFSETS))
    tables = {
        "stage_rows": [list(image.values("<5h", STAGE_ROWS + 10 * k)) for k in range(STAGE_ROW_COUNT)],
        "presets": [list(image.values("<10h", PRESETS + k * PRESET_BYTES)) for k in range(PRESET_COUNT)],
        "script_kinds": list(image.values(f"<{SCRIPT_KIND_COUNT}h", SCRIPT_KINDS)),
        "blend_outs": blend_outs(image),
        "reels": reels(image),
        "attract_styles": list(image.values(f"<{ATTRACT_STYLE_COUNT}H", ATTRACT_STYLES)),
        "attract_pitches": list(image.values(f"<{ATTRACT_PITCH_COUNT}i", ATTRACT_PITCHES)),
        "attract_speeds": list(image.values(f"<{ATTRACT_SPEED_COUNT}i", ATTRACT_SPEEDS)),
        "intro_offsets": [list(image.values("<7h", INTRO_OFFSETS + k * INTRO_BYTES)) for k in range(INTRO_COUNT)],
        "stream_offsets": offsets,
    }
    tables.update(choice_tables(image))
    tables.update(hit_tables(image))
    return tables, offsets


def convert(arc: arcade.ArcadeSet, out: Output, atan: list[int]) -> None:
    tables, offsets = camera_tables(arc)
    tables["atan"] = atan
    out.write_json("tables/camera.json", tables)
    out.write("tables/camera_streams.bin.gz", gzipped(stream_bytes(arc, offsets)))
