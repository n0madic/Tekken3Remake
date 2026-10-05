#!/usr/bin/env python3
"""Arcade (System 12) character models: the `3DMK` variant of MAME's tekken3 set.

Layout from the arcade program (World ver. E1): the loader `FUN_80197b38` (category 20 entry
`2·slot + 1` when it is longer than 4 bytes, else category 19's), the relocator `FUN_80196e30`,
the primitive builder `FUN_801970d4` and the skinned renderer `FUN_8019a858`. See
docs/research/arcade/README.md#character-models.

Row `k` is drawn with animation matrix `k`: rows 0–17 are the PlayStation's 18 matrix slots in
order, rows 18–23 six costume attachments. A vertex block holds the part's own vertices and
three lists: imports (global slot indices appended after the own vertices), exports and blends
(entries `index | weight << 16`, a 4.12 weight, walking the own vertices in order).
"""

from __future__ import annotations

import struct
from dataclasses import dataclass, field

import pose

ROWS = 24
ROW_BYTES = 0x38
HEADER_BYTES = 0x10
JOINTS = 18                     # rows 0–17: the skeleton's matrix slots
FIRST_ATTACHMENT = 18
ATTACHMENTS = 6
VARIANTS = 41
TURNED_VARIANTS = 17            # FUN_80197578 turns an attachment row's first 17 variant blocks too
WEIGHT_ONE = 0x1000             # export: copy; blend: copy own into the global slot
FACE_WORDS = (2, 2, 2, 3)       # FT3, FT4, GT3, GT4
TEXTURE_WORDS = 3               # per face of every group: clut|uv0, tpage|uv1, uv2|uv3
QUAD_GROUPS = (1, 3)
CLUT_BASE = 0x5C30              # player 1 (FUN_801970d4)
TPAGE_BASE = 0x1C
TEXTURE_ORIGIN = (0x300, 0x100)  # FUN_80197e88: TIM image offset (player 1)
CLUT_ORIGIN = (0x300, 0x170)    # … and CLUT offset
VRAM_ROWS = 1024

# The feet's frames turn 90° about y against the PlayStation's: the arcade's motions give rows 14
# and 17 the PlayStation's rotation times Ry(−90°) in every frame (measured against the arcade's motions), so
# their vertices and normals in the PlayStation's frames are Ry(−90°) · v.
FOOT_ROWS = (14, 17)

# Program addresses (World ver. E1).
ATTACHMENT_ENABLE = 0x801FD2E6  # u8 per costume slot × 6 + row (rows ≥ 18): 0 hidden
ATTACHMENT_RECORDS = 0x801FDC88  # u32 per costume slot × 6 + attachment: dynamics record
LOAD_TURNS = 0x801FD3E4         # 8 bytes per enable value: s16 Euler angles turning a swinging
                                # attachment's vertices and normals as the model loads (FUN_80197578)
SINE = 0x80175944               # s16 sines, 4096 = 1.0; cosines from 1024 entries on (FUN_8019a4ac)
SINE_ENTRIES = 5120
STATIC_RECORD = 0x801FD4D4
REST_ONLY_SLOTS = (0x20, 0x21)  # FUN_8019b6d8: their first two attachments keep identity


class ArcadeKmdError(ValueError):
    pass


@dataclass
class Vertices:
    coords: list[tuple[int, int, int]]
    imports: list[int]
    exports: list[int]
    blends: list[int]
    end: int


@dataclass
class Face:
    group: int                      # 0 FT3, 1 FT4, 2 GT3, 3 GT4
    verts: tuple[int, ...]          # vertex slots, GPU order
    colours: tuple[int, ...]        # lit-colour slots
    double_sided: bool
    clut: int                       # player 1 values
    tpage: int
    uvs: tuple[tuple[int, int], ...]


@dataclass
class Row:
    index: int
    words: tuple[int, ...]
    verts: Vertices | None = None
    normals: Vertices | None = None
    faces: list[Face] = field(default_factory=list)
    variants: list[int] | None = None
    turn: list[int] | None = None   # the load turn's matrix of a swinging attachment (turn_attachments)

    @property
    def offset(self) -> tuple[int, int, int]:
        return self.words[5], self.words[6], self.words[7]

    @property
    def parent(self) -> int:
        return self.words[8]

    @property
    def rest(self) -> tuple[int, int, int]:
        """Rest Euler angles (16-bit units), read for attachments (FUN_8019b634)."""
        return tuple(struct.unpack("<3h", struct.pack("<3H", *(w & 0xFFFF for w in self.words[9:12]))))


@dataclass
class Model:
    scale_percent: int
    rows: list[Row]


def _words(data: bytes, pos: int, count: int) -> tuple[list[int], int]:
    if pos + 4 * count > len(data):
        raise ArcadeKmdError(f"list at {pos:#x} runs past the file")
    return list(struct.unpack_from(f"<{count}I", data, pos)), pos + 4 * count


def _list(data: bytes, pos: int) -> tuple[list[int], int]:
    count = struct.unpack_from("<I", data, pos)[0]
    return _words(data, pos + 4, count)


def parse_vertices(data: bytes, pos: int) -> Vertices:
    """A vertex or normal block: both have the same layout (in a normal block the last list adds
    halves of colours, see colour_terms)."""
    count = struct.unpack_from("<I", data, pos)[0]
    coords = [struct.unpack_from("<3h", data, pos + 4 + 8 * i) for i in range(count)]
    pos += 4 + 8 * count
    imports, pos = _list(data, pos)
    exports, pos = _list(data, pos)
    added, pos = _list(data, pos)
    return Vertices(coords, imports, exports, added, pos)


def parse_faces(data: bytes, pos: int, tex: int) -> list[Face]:
    faces: list[Face] = []
    records = []
    for group, size in enumerate(FACE_WORDS):
        count = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        for _ in range(count):
            words, pos = _words(data, pos, size)
            records.append((group, words))
    if pos != tex:
        raise ArcadeKmdError(f"face block ends at {pos:#x}, not at the texture block {tex:#x}")
    tex_records = []
    for group in range(len(FACE_WORDS)):
        count = struct.unpack_from("<I", data, tex)[0]
        tex += 4
        for _ in range(count):
            words, tex = _words(data, tex, TEXTURE_WORDS)
            tex_records.append(words)
    if len(tex_records) != len(records):
        raise ArcadeKmdError("face and texture records differ in number")
    for (group, w), t in zip(records, tex_records):
        quad = group in QUAD_GROUPS
        verts = (w[0] & 0xFF, (w[0] >> 8) & 0xFF, (w[0] >> 16) & 0xFF) + ((w[0] >> 24,) if quad else ())
        if group == 0:
            colours, double = (w[1] & 0xFF,), bool(w[0] >> 31)
        elif group == 1:
            colours, double = (w[1] & 0xFF,), bool(w[1] & 0x8000)
        elif group == 2:
            colours, double = (w[1] & 0xFF, (w[1] >> 8) & 0xFF, (w[1] >> 16) & 0xFF), bool(w[0] >> 31)
        else:
            colours, double = tuple((w[1] >> s) & 0xFF for s in (0, 8, 16, 24)), bool(w[2] & 0x80)
        uv_words = (t[0] & 0xFFFF, t[1] & 0xFFFF, t[2] & 0xFFFF) + ((t[2] >> 16,) if quad else ())
        faces.append(Face(group, verts, colours, double, CLUT_BASE + (t[0] >> 16), TPAGE_BASE + (t[1] >> 16),
                          tuple((uv & 0xFF, uv >> 8) for uv in uv_words)))
    return faces


def playstation_frame(row: int, v: tuple[int, int, int]) -> tuple[int, int, int]:
    """A vertex or normal of `row` in the PlayStation's joint frame (FOOT_ROWS: Ry(−90°) · v)."""
    if row not in FOOT_ROWS:
        return v
    x, y, z = v
    return -z, y, x


class SineTable:
    """The arcade's sine table (SINE) as pose.euler_to_matrix's tables: FUN_8019a4ac is
    EulerToMatrix with this table."""

    def __init__(self, sine: list[int]) -> None:
        self.table = sine

    def sin(self, angle: int) -> int:
        return self.table[(angle >> 4) & 0xFFF]

    def cos(self, angle: int) -> int:
        return self.table[((angle >> 4) & 0xFFF) + 1024]


def euler(x: int, y: int, z: int, sine: list[int]) -> list[int]:
    """FUN_8019a4ac: Rz(z)·Ry(y)·Rx(x) of 16-bit angles as nine 4.12 entries, with its rounding."""
    m = pose.euler_to_matrix(x, y, z, SineTable(sine))
    return [m[r][c] for r in range(3) for c in range(3)]


def turned(m: list[int], v: tuple[int, int, int]) -> tuple[int, int, int]:
    """FUN_8019c990: MVMVA (shift 12, IR saturated to s16) of one SVECTOR."""
    x, y, z = v
    return tuple(max(-0x8000, min(0x7FFF, (m[3 * r] * x + m[3 * r + 1] * y + m[3 * r + 2] * z) >> 12)) for r in range(3))


def turn_attachments(model: Model, turns: dict[int, tuple[int, int, int]], sine: list[int]) -> None:
    """FUN_80197578 as the model loads: the vertices and normals of the swinging attachment rows
    in `turns` (row → Euler angles from LOAD_TURNS) turned in place; `variant` turns the row's
    first TURNED_VARIANTS variant blocks the same way."""
    for index, angles in turns.items():
        row = model.rows[index]
        if row.verts is None:
            continue
        m = euler(*angles, sine)
        row.turn = m
        row.verts.coords = [turned(m, v) for v in row.verts.coords]
        row.normals.coords = [turned(m, v) for v in row.normals.coords]


def load_turns(prog_values, slot: int, enable: bytes) -> dict[int, tuple[int, int, int]]:
    """The load turns of a costume's swinging attachments (enable value above 1, FUN_8019b5e0)."""
    return {row: prog_values("<3h", LOAD_TURNS + 8 * enable[row])
            for row in range(FIRST_ATTACHMENT, ROWS) if enable[row] > 1}


def parse(data: bytes) -> Model:
    count, scale = struct.unpack_from("<II", data, 0)
    if count != ROWS or data[8:12] != b"3DMK":
        raise ArcadeKmdError("not an arcade 3DMK model")
    rows = []
    for k in range(ROWS):
        words = struct.unpack_from("<14i", data, HEADER_BYTES + ROW_BYTES * k)
        row = Row(k, words)
        if words[0]:
            row.verts = parse_vertices(data, words[0])
            if not words[1] and row.verts.end != words[2]:
                raise ArcadeKmdError(f"row {k}: vertex block ends at {row.verts.end:#x}, not {words[2]:#x}")
            row.normals = parse_vertices(data, words[2])
            if row.normals.end != words[3]:
                raise ArcadeKmdError(f"row {k}: normal block ends at {row.normals.end:#x}, not {words[3]:#x}")
            row.faces = parse_faces(data, words[3], words[4])
            if words[1]:
                row.variants = list(struct.unpack_from(f"<{VARIANTS}I", data, words[1]))
        rows.append(row)
    return Model(scale, rows)


def variant(data: bytes, model: Model, row: int, index: int) -> Vertices:
    """Vertex variant `index` of a row; its lists must be the base block's. An entry that points
    at the base block is the base block itself (turned with the model). Otherwise the block of a
    swinging attachment row is turned as the model loads when it is among the first
    TURNED_VARIANTS entries (FUN_80197578; a block listed twice would be turned twice)."""
    r = model.rows[row]
    base = r.verts
    if r.variants[index] == r.words[0]:
        return base
    block = parse_vertices(data, r.variants[index])
    if r.turn is not None and index < TURNED_VARIANTS:
        if r.variants[:TURNED_VARIANTS].count(r.variants[index]) > 1:
            raise ArcadeKmdError(f"row {row} variant {index} is turned more than once")
        block.coords = [turned(r.turn, v) for v in block.coords]
    if (len(block.coords), block.imports, block.exports, block.blends) != \
            (len(base.coords), base.imports, base.exports, base.blends):
        raise ArcadeKmdError(f"row {row} variant {index} changes the exchange lists")
    return block


def slot_weights(model: Model, drawn: set[int]) -> dict[int, list[dict[tuple[int, int], float]]]:
    """Every drawn row's vertex slots as weighted sums of (row, vertex) terms, in draw order
    (FUN_8019a6d0 draws rows 0–23 in order; imports read the global slots as left so far)."""
    shared: dict[int, dict[tuple[int, int], float]] = {}
    out = {}
    for row in model.rows:
        if row.verts is None or row.index not in drawn:
            continue
        vb = row.verts
        own = [{(row.index, i): 1.0} for i in range(len(vb.coords))]
        imported = []
        for index in vb.imports:
            if index not in shared:
                raise ArcadeKmdError(f"row {row.index} imports global slot {index} before it is written")
            imported.append(dict(shared[index]))
        cursor = 0
        for entry in vb.exports:
            index, weight = entry & 0xFFFF, entry >> 16
            shared[index] = {t: w * weight / WEIGHT_ONE for t, w in own[cursor].items()}
            cursor += 1
        for entry in vb.blends:
            index, weight = entry & 0xFFFF, entry >> 16
            if weight != WEIGHT_ONE:
                blend = {t: w * weight / WEIGHT_ONE for t, w in own[cursor].items()}
                for t, w in shared.get(index, {}).items():
                    blend[t] = blend.get(t, 0.0) + w
                own[cursor] = blend
            shared[index] = own[cursor]
            cursor += 1
        out[row.index] = own + imported
    return out


def colour_terms(model: Model, drawn: set[int]) -> dict[int, list[dict[tuple[int, int], float]]]:
    """Every drawn row's lit-colour slots as weighted sums of (row, normal) terms (FUN_8019a858):
    the own normals' colours, then the imported global colours; exports store a colour (weight
    WEIGHT_ONE) or its half in a global slot, the last list adds a half to the global slot."""
    shared: dict[int, dict[tuple[int, int], float]] = {}
    out = {}
    for row in model.rows:
        if row.normals is None or row.index not in drawn:
            continue
        nb = row.normals
        own = [{(row.index, i): 1.0} for i in range(len(nb.coords))]
        imported = []
        for index in nb.imports:
            if index not in shared:
                raise ArcadeKmdError(f"row {row.index} imports global colour {index} before it is written")
            imported.append(dict(shared[index]))
        cursor = 0
        for entry in nb.exports:
            index, weight = entry & 0xFFFF, entry >> 16
            scale = 1.0 if weight == WEIGHT_ONE else 0.5
            shared[index] = {t: w * scale for t, w in own[cursor].items()}
            cursor += 1
        for entry in nb.blends:
            index, weight = entry & 0xFFFF, entry >> 16
            if weight == WEIGHT_ONE:
                shared[index] = dict(own[cursor])
            else:
                blend = {t: w * 0.5 for t, w in own[cursor].items()}
                for t, w in shared.get(index, {}).items():
                    blend[t] = blend.get(t, 0.0) + w
                shared[index] = blend
            cursor += 1
        out[row.index] = own + imported
    return out
