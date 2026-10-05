#!/usr/bin/env python3
"""Parse Tekken 3 character models (.kmd / "3DMK").

Layout verified against the loader (KmdRelocate 0x80035138), the primitive
builder (FighterBuildPartPrims 0x800353E4) and the skinned renderer
(DrawSkinnedPart 0x80036F00) of Japan Rev.1. See
docs/research/formats/3dmk-models.md.

All offsets inside the file are relative to the file start.
"""

from __future__ import annotations

import argparse
import logging
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger("kmd")

HEADER_BYTES = 0x10
ROW_BYTES = 0x38
ROW_COUNT = 27
VARIANT_SLOTS = 41
FACE_GROUPS = ("ft3", "ft4", "gt3", "gt4")  # GPU primitive kinds, in stream order
FACE_RECORD_BYTES = (8, 8, 8, 12)
FACE_VERTS = (3, 4, 3, 4)
TEX_RECORD_BYTES = (4, 5, 4, 5)

# Draw part -> KMD row, and part -> animation matrix slot (EXE tables 0x8001A05C/0x8001A074).
PART_ROW = (0, 1, 3, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24)
PART_MATRIX = (0, 1, 11, 12, 13, 14, 15, 16, 17, 3, 4, 5, 6, 7, 8, 9, 10, 2, 18, 19, 20, 21)


class KmdError(ValueError):
    pass


@dataclass
class Reader:
    data: bytes
    pos: int
    end: int

    def u32(self) -> int:
        if self.pos + 4 > self.end:
            raise KmdError(f"read past block end at {self.pos:#x}")
        v = struct.unpack_from("<I", self.data, self.pos)[0]
        self.pos += 4
        return v

    def words(self, n: int) -> list[int]:
        return [self.u32() for _ in range(n)]


def packed_entries(words: list[int], count: int, bits: int, per_word: int) -> list[int]:
    """Unpack `count` entries of `bits` each, `per_word` entries per little-endian word."""
    mask = (1 << bits) - 1
    out = []
    for i in range(count):
        out.append((words[i // per_word] >> (bits * (i % per_word))) & mask)
    return out


def read_list(r: Reader, bits: int, per_word: int) -> list[int]:
    count = r.u32()
    nwords = (count + per_word - 1) // per_word
    return packed_entries(r.words(nwords), count, bits, per_word)


@dataclass
class VertexBlock:
    """Vertex (or normal) block: imports, own SVECTORs, then seam/export lists."""
    lead: int
    import_scratch: list[int]   # byte offsets into the scratchpad exchange buffer
    import_global: list[int]    # byte offsets into the global exchange buffer
    coords: list[tuple[int, int, int]]
    post: list[list[int]] = field(default_factory=list)
    end: int = 0


def parse_vertex_block(data: bytes, start: int, end: int, normals: bool) -> VertexBlock:
    r = Reader(data, start, end)
    lead = r.u32()
    imports = [read_list(r, 8, 4), read_list(r, 8, 4)]
    count = r.u32()
    coords = []
    for _ in range(count):
        if r.pos + 8 > end:
            raise KmdError("coordinate array exceeds block")
        x, y, z, pad = struct.unpack_from("<4h", data, r.pos)
        if pad:
            raise KmdError(f"nonzero SVECTOR pad at {r.pos:#x}")
        coords.append((x, y, z))
        r.pos += 8
    post: list[list[int]] = []
    if normals:
        # Normal blocks end with two 8-bit distribution lists (lit color export).
        post = [read_list(r, 8, 4), read_list(r, 8, 4)]
    else:
        # blendA, addB x2, export x2 use 9-bit entries (3 per word); halve uses 2-bit codes.
        for _ in range(5):
            post.append(read_list(r, 9, 3))
        post.append(read_list(r, 2, 16))
    if lead != 2 * (1 + len(imports[0]) + len(imports[1])) and not normals:
        raise KmdError(f"lead {lead} inconsistent with imports at {start:#x}")
    return VertexBlock(lead, imports[0], imports[1], coords, post, r.pos)


@dataclass
class Face:
    kind: str
    verts: tuple[int, ...]       # vertex slot indices (byte offset / 4)
    colors: tuple[int, ...]      # lit color slot byte offsets
    double_sided: bool
    z_bias: int


def parse_faces(data: bytes, start: int, end: int) -> list[Face]:
    faces = []
    pos = start
    for gi, kind in enumerate(FACE_GROUPS):
        count = struct.unpack_from("<I", data, pos)[0]
        pos += 4
        for _ in range(count):
            w = struct.unpack_from(f"<{FACE_RECORD_BYTES[gi] // 4}I", data, pos)
            pos += FACE_RECORD_BYTES[gi]
            v0 = w[0]
            if kind in ("ft3", "gt3"):
                verts = ((v0 & 0x1FC) >> 2, (v0 >> 9) & 0x7F, (v0 >> 16) & 0x7F)
                flags = v0
            else:
                verts = ((v0 & 0x1FC) >> 2, (v0 >> 9) & 0x7F, (v0 >> 16) & 0x7F, v0 >> 25)
                flags = w[1]
            if kind == "ft3":
                colors = (w[1],)
            elif kind == "ft4":
                colors = (w[1] & 0x1FC,)
            elif kind == "gt3":
                colors = (w[1] & 0x1FC, (w[1] >> 7) & 0x1FC, w[1] >> 16)
            else:
                colors = (w[1] & 0x1FC, w[2] & 0x1FC, (w[2] >> 7) & 0x1FC, w[2] >> 16)
            z = flags >> 25
            if z & 0x40:
                z -= 0x80
            faces.append(Face(kind, verts, colors, bool(flags & 0x1000000), z))
    if pos != end:
        raise KmdError(f"face block ends at {pos:#x}, expected {end:#x}")
    return faces


@dataclass
class TexFace:
    kind: str
    material: int
    uvs: tuple[int, ...]


@dataclass
class TexBlock:
    materials: list[int]           # u16: (tpage bits << 8) | CLUT x/16 low byte
    uvs: list[tuple[int, int]]     # (u, v)
    faces: list[TexFace]
    end: int


def parse_texmap(data: bytes, start: int, end: int, counts: list[int]) -> TexBlock:
    p = struct.unpack_from("<H", data, start)[0]
    materials = list(struct.unpack_from(f"<{p // 2 - 1}H", data, start + 2))
    uv_base = start + p
    q = struct.unpack_from("<H", data, uv_base)[0]
    raw = data[uv_base + 2 : uv_base + q]
    uvs = [(raw[i], raw[i + 1]) for i in range(0, len(raw), 2)]
    pos = uv_base + q
    faces = []
    for gi, kind in enumerate(FACE_GROUPS):
        count = data[pos]
        pos += 1
        if count != counts[gi]:
            raise KmdError(f"texmap {kind} count {count} != face count {counts[gi]}")
        for _ in range(count):
            rec = data[pos : pos + TEX_RECORD_BYTES[gi]]
            pos += TEX_RECORD_BYTES[gi]
            if rec[0] >= len(materials) or any(i >= len(uvs) for i in rec[1:]):
                raise KmdError(f"texmap index out of range at {pos:#x}")
            faces.append(TexFace(kind, rec[0], tuple(rec[1:])))
    # Two-byte trailer then zero padding to a four-byte boundary.
    pos += 2
    tail = data[pos:end]
    if len(tail) > 3 or any(tail):
        raise KmdError(f"unexpected texmap tail {tail.hex()} at {pos:#x}")
    return TexBlock(materials, uvs, faces, pos)


@dataclass
class Row:
    index: int
    words: tuple[int, ...]
    verts: VertexBlock | None = None
    variants: list[int] | None = None
    normals: VertexBlock | None = None
    faces: list[Face] | None = None
    tex: TexBlock | None = None

    @property
    def offset(self) -> tuple[int, int, int]:
        return tuple(struct.unpack("<3i", struct.pack("<3I", *self.words[5:8])))

    @property
    def parent(self) -> int:
        return struct.unpack("<i", struct.pack("<I", self.words[8]))[0]


@dataclass
class Kmd:
    scale_percent: int
    rows: list[Row]


def parse(data: bytes) -> Kmd:
    if data[8:12] != b"3DMK":
        raise KmdError("missing 3DMK signature")
    row_count, scale = struct.unpack_from("<II", data, 0)
    if row_count != ROW_COUNT:
        raise KmdError(f"row count {row_count}")
    rows = [Row(i, struct.unpack_from("<14I", data, HEADER_BYTES + i * ROW_BYTES)) for i in range(row_count)]
    table_end = HEADER_BYTES + row_count * ROW_BYTES
    # Every block start (words 0..4, variant targets) ordered; a block ends at the next start.
    starts = set()
    for row in rows:
        for w in row.words[:5]:
            if w:
                starts.add(w)
    variant_tables = {}
    for row in rows:
        if row.words[1]:
            table = list(struct.unpack_from(f"<{VARIANT_SLOTS}I", data, row.words[1]))
            variant_tables[row.index] = table
            if table[1] == 0:
                # Ogre (character 0x14) row 2: entries 1..40 are strides relocated against an
                # external runtime buffer (FUN_80069A44), not file offsets.
                starts.add(table[0])
            else:
                starts.update(t for t in table if 0 < t < len(data))
    bounds = sorted(starts) + [len(data)]
    nxt = dict(zip(bounds, bounds[1:]))
    if bounds[0] != table_end:
        raise KmdError(f"first block at {bounds[0]:#x}, table ends {table_end:#x}")
    for row in rows:
        w = row.words
        if not w[0]:
            continue
        row.verts = parse_vertex_block(data, w[0], nxt[w[0]], normals=False)
        if row.verts.end != nxt[w[0]]:
            raise KmdError(f"row {row.index} vertex block ends {row.verts.end:#x} != {nxt[w[0]]:#x}")
        row.normals = parse_vertex_block(data, w[2], nxt[w[2]], normals=True)
        if row.normals.end != nxt[w[2]]:
            raise KmdError(f"row {row.index} normal block ends {row.normals.end:#x} != {nxt[w[2]]:#x}")
        row.faces = parse_faces(data, w[3], nxt[w[3]])
        counts = [sum(f.kind == k for f in row.faces) for k in FACE_GROUPS]
        row.tex = parse_texmap(data, w[4], nxt[w[4]], counts)
        row.variants = variant_tables.get(row.index)
    return Kmd(scale, rows)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bns-dir", type=Path, default=Path(__file__).resolve().parents[2] / "work" / "jp_rev1" / "bns")
    args = parser.parse_args()
    failures = 0
    totals = {"models": 0, "rows": 0, "verts": 0, "normals": 0, **{k: 0 for k in FACE_GROUPS}}
    for path in sorted(args.bns_dir.glob("*.kmd")):
        try:
            kmd = parse(path.read_bytes())
        except (KmdError, struct.error) as e:
            failures += 1
            log.error("%s: %s", path.name, e)
            continue
        totals["models"] += 1
        for row in kmd.rows:
            if row.verts:
                totals["rows"] += 1
                totals["verts"] += len(row.verts.coords)
                totals["normals"] += len(row.normals.coords)
                for f in row.faces:
                    totals[f.kind] += 1
    log.info("parsed %s; failures %d", totals, failures)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
