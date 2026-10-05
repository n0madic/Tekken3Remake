#!/usr/bin/env python3
"""The other releases' images in Japan Rev.1's layout (docs/remake-plan.md, "Discs").

The converter, the remake and the docs name the game's data by Japan Rev.1 addresses. The
original Japanese release and the USA release hold the same data at other addresses: their
code and data are shifted, their overlays load at other slots, and a few functions, tables and
texts differ (code/usa-version.md). A layout (`layouts/<release>.json`, made by this tool from
both discs) maps a release's executable and overlays onto Japan Rev.1's; `rebased()` then builds
Japan Rev.1-layout images from that release's disc alone, and the converter reads them as it
reads Japan Rev.1.

A layout holds numbers only: per block the SHA-256 of the release's block (the layout fits that
image only), Japan Rev.1's block size, and

- `segments`: `[offset, length, source offset]`, runs copied from the release's block (bytes
  equal in both but for pointers and code immediates, whose values may differ in place);
- `points`: `[address, source address]` of objects the code names outside the segments
  (variables beyond the image, zero-filled data): pointers near them keep their shift;
- `relocs`: the offsets of the words in the segments that are pointers: rewritten from the
  release's addresses to Japan Rev.1's; `pinned`: `[offset, address]`, pointers to an object
  the segments place wrongly (a pointer before its object), with the address itself;
- `strings`: `[address, source address, room]`, texts of the release that differ from Japan
  Rev.1's (outside the segments): written at the address when they fit in `room` bytes, else
  kept aside (`Disc.strings`, `screens/ram.json`: read by address first);
- `texts` and `patches` (from EXTRAS): wording and small tables Japan Rev.1 has and the release
  has not; `tables`: `[address, source address, rows, row size, source row size]`, tables whose
  rows the release keeps longer.

Everything else is zero: code of the functions that differ (never read as data) and data of the
release that Japan Rev.1 has not. The tool's report lists what differs from Japan Rev.1 after
the rebase by kind; `unmapped` bytes are Japan Rev.1 data the release lacks and must be none the
converter or the remake reads.

    python3 tools/remake_import/layout.py --image REV1_IMAGE --image IMAGE [--image IMAGE] [--check]
"""

from __future__ import annotations

import argparse
import bisect
import collections
import functools
import hashlib
import json
import logging
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

from common import (CANONICAL, EXE_BASE, EXE_HEADER, OVERLAYS, RELEASES, ROOT, Block, Disc, DiscError,
                    Release, log, open_discs, printable, text_start)
from disc_image import ImageError

LAYOUTS = Path(__file__).resolve().parent / "layouts"
PROJECT_WORDING = ROOT / "remake" / "content" / "texts_en.json"   # the USA wording kept in the project
ANCHOR = 16                  # bytes of a unique window that anchors an alignment
ANCHOR_STEP = 4
JOIN_GAP = 64                # runs of one shift joined across a gap this long (in-place differences)
FILL_GAP = 0x1000            # ... and this long when no object the code names there has another shift
POINTER_MASK = b"\xa5\xa5\xa5\xa5"   # stands for every address word in the alignment (not text)
MIN_SEGMENT = 8
MIN_LONE = 32                # bytes a match of a single anchor must reach
SAME_WINDOW = 128            # bytes compared to tell whether two pointers name one object
SAME_SHARE = 0.75
PIN_REACH = 16               # bytes a pointer before its object may be misplaced by
POINT_REACH = 0x400          # bytes past an object the code names that keep its shift
STRING_LIMIT = 200
WINDOW = 12                  # instructions matched around a code reference
LOOKAHEAD = 24               # instructions searched after a `lui` for its low half
LOAD_STORE_OPS = {0x08, 0x09, 0x0D, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x28, 0x29, 0x2A, 0x2B, 0x2E}
BRANCH_OPS = {1, 4, 5, 6, 7}
IMMEDIATE_OPS = LOAD_STORE_OPS | {0x0A, 0x0B, 0x0C, 0x0E, 0x0F, 0x32, 0x3A}
ADDRESS_RANGE = (0x80000000, 0x80200000)
# What differs in structure, by release and block: `texts` (generic wording only: address →
# text) and `patches` (address → bytes, small tables documented in the docs) that Japan Rev.1 has
# and the release has not, and `tables` (address → rows, Japan Rev.1's row size, the release's)
# whose rows the release keeps with more bytes: each row's first bytes are copied.
EXTRAS: dict[str, dict[str, dict[str, dict[int, object]]]] = {
    "jp_orig": {
        # The XA stream table (sound.md#music): (start, end, channel) and a name pointer per row.
        "exe": {"tables": {0x80024FE4: (50, 12, 16)}},
    },
    "usa": {
        # The practice menu's KEY DISPLAY (usa-version.md): its label, and the pages' rows with
        # item 5 (FREE, VS CPU, COMBO TRAINING; 12 bytes a page, then a pointer).
        "practice": {
            "texts": {0x800B0CFC: "KEY DISPLAY"},
            "patches": {0x800B0A10: bytes([0, 7, 13, 2, 1, 3, 4, 5, 14, 0, 0, 0,
                                           0, 7, 9, 10, 1, 3, 4, 5, 14, 0, 0, 0,
                                           0, 7, 15, 16, 1, 3, 4, 14])},
        },
    },
}


class LayoutError(Exception):
    """A layout does not fit the image (another pressing), or cannot be applied."""


# --- code references (also usa.py) ---------------------------------------------------------------

def normalised(w: int) -> int:
    """An instruction without what relocation changes (compare_exe_code.py)."""
    op = w >> 26
    if op in (2, 3):
        return op << 26
    if op == 0 or op == 0x12 or op in BRANCH_OPS:
        return w
    return w & 0xFFFF0000


def _low_half(w: int) -> int:
    lo = w & 0xFFFF
    return lo - 0x10000 if w >> 26 != 0x0D and lo & 0x8000 else lo


def _references(words: list[int]) -> list[tuple[int, int, int]]:
    """(low instruction index, `lui` index, address) of every `lui` + load/store/addiu/ori pair."""
    out = []
    for i, w in enumerate(words):
        if w >> 26 != 0x0F:
            continue
        rt = (w >> 16) & 31
        for k in range(i + 1, min(i + LOOKAHEAD, len(words))):
            x = words[k]
            if x >> 26 in LOAD_STORE_OPS and (x >> 21) & 31 == rt:
                out.append((k, i, ((w & 0xFFFF) << 16) + _low_half(x) & 0xFFFFFFFF))
            if x >> 26 == 0x0F and (x >> 16) & 31 == rt:
                break
    return out


def address_map(a: dict[str, Block], b: dict[str, Block]) -> dict[tuple[str, int], int]:
    """(block, address in `a`) → address in `b` of every object the code references: the same
    instruction of the matching function (found by its normalised instruction window)."""
    votes: dict[tuple[str, int], collections.Counter] = collections.defaultdict(collections.Counter)
    for name, ab in a.items():
        bb = b[name]
        an = [normalised(w) for w in ab.words]
        bn = [normalised(w) for w in bb.words]
        same = an == bn
        index: dict[tuple, list[int]] = collections.defaultdict(list)
        if not same:
            for j in range(len(bn) - WINDOW):
                index[tuple(bn[j:j + WINDOW])].append(j)
        for k, i, addr in _references(ab.words):
            j = k
            if not same:
                j = -1
                for back in range(0, 2 * WINDOW, 4):
                    hits = index.get(tuple(an[k - back:k - back + WINDOW])) if k >= back else None
                    if hits and len(hits) == 1:
                        j = hits[0] + back
                        break
                if j < 0:
                    continue
            ji = j - (k - i)
            if j >= len(bb.words) or ji < 0 or bb.words[ji] >> 26 != 0x0F or bb.words[j] >> 26 != ab.words[k] >> 26:
                continue
            target = ((bb.words[ji] & 0xFFFF) << 16) + _low_half(bb.words[j]) & 0xFFFFFFFF
            owner = name if name != "exe" and ab.contains(addr) else "exe"
            votes[(owner, addr)][target] += 1
    return {key: counter.most_common(1)[0][0] for key, counter in votes.items()}


# --- alignment -----------------------------------------------------------------------------------

def _masked(data: bytes) -> bytes:
    """`data` with its address words (and `lui` of an address) replaced by one pattern, so that
    tables of pointers and code align although the releases' addresses differ."""
    out = bytearray(data)
    for off in range(0, len(data) - 3, 4):
        w = struct.unpack_from("<I", data, off)[0]
        if _address_like(w) or (w >> 26 == 0x0F and ADDRESS_RANGE[0] >> 16 <= w & 0xFFFF < ADDRESS_RANGE[1] >> 16):
            out[off:off + 4] = POINTER_MASK
    return bytes(out)


def _trimmed(a: bytes, b: bytes, piece: list[int]) -> list[int]:
    """A run without a text it only partly covers in either block (a run grown into a text up to
    the first letter that differs, or from its last letters): the text is then paired whole."""
    start, end, shift = piece
    if end - start >= 2 and printable(a[end - 1]):
        ends_text = (end == len(a) or a[end] == 0) and (end + shift == len(b) or b[end + shift] == 0)
        k = end
        while k > start and printable(a[k - 1]):
            k -= 1
        if not ends_text and end - k >= 2 and text_start(a, k):
            end = k
    if start < end and printable(a[start]) and start > 0 and (
            printable(a[start - 1]) or (start + shift > 0 and printable(b[start + shift - 1]))):
        k = a.find(b"\0", start, end)
        start = k + 1 if k >= 0 else end
    return [start, end, shift]


def align(a: bytes, b: bytes) -> list[list[int]]:
    """Segments `[offset in a, length, offset in b]` of `a` found in `b`, in order in both:
    unique windows anchor them, runs grow while the bytes are equal (addresses masked) and runs
    of the same shift are joined across gaps."""
    a, b = _masked(a), _masked(b)
    count = collections.Counter(b[i:i + ANCHOR] for i in range(len(b) - ANCHOR))
    unique = {b[i:i + ANCHOR]: i for i in range(len(b) - ANCHOR) if count[b[i:i + ANCHOR]] == 1}
    runs: list[list[int]] = []                         # [start, end, shift, anchors]
    for p in range(0, len(a) - ANCHOR, ANCHOR_STEP):
        window = a[p:p + ANCHOR]
        if window not in unique or len(set(window)) <= 2 or POINTER_MASK in window:
            continue
        shift = unique[window] - p
        if runs and runs[-1][2] == shift and p <= runs[-1][1] + JOIN_GAP:
            runs[-1][1] = p + ANCHOR
            runs[-1][3] += 1
        else:
            runs.append([p, p + ANCHOR, shift, 1])
    for r in runs:
        while r[0] > 0 and r[0] + r[2] > 0 and a[r[0] - 1] == b[r[0] - 1 + r[2]]:
            r[0] -= 1
        while r[1] < len(a) and r[1] + r[2] < len(b) and a[r[1]] == b[r[1] + r[2]]:
            r[1] += 1
    # A lone anchor must grow into a longer match; longer runs win where runs overlap.
    runs = [r for r in runs if r[3] > 1 or r[1] - r[0] >= MIN_LONE]
    runs.sort(key=lambda r: r[0] - r[1])
    taken: list[tuple[int, int]] = []                  # sorted, disjoint
    pieces: list[list[int]] = []
    for start, end, shift, _ in runs:
        cursor = start
        k = bisect.bisect_right(taken, (start, start))
        k = max(k - 1, 0)
        free = []
        while cursor < end:
            while k < len(taken) and taken[k][1] <= cursor:
                k += 1
            nxt = taken[k][0] if k < len(taken) else end
            if nxt > cursor:
                free.append((cursor, min(nxt, end)))
                cursor = min(nxt, end)
            else:
                cursor = taken[k][1]
        for f0, f1 in free:
            if f1 - f0 >= MIN_SEGMENT:
                pieces.append([f0, f1, shift])
                bisect.insort(taken, (f0, f1))
    pieces = [p for p in (_trimmed(a, b, piece) for piece in sorted(pieces)) if p[1] - p[0] >= MIN_SEGMENT]
    out: list[list[int]] = []
    for start, end, shift in pieces:
        if out and out[-1][2] - out[-1][0] == shift and start - (out[-1][0] + out[-1][1]) <= JOIN_GAP:
            out[-1][1] = end - out[-1][0]
        else:
            out.append([start, end - start, start + shift])
    return out


# --- translation ---------------------------------------------------------------------------------

@dataclass
class Map:
    """A release's addresses → Japan Rev.1's, per block: the segments, the strings, and the
    points (objects the code names outside the segments: variables, pointer tables), whose
    neighbourhood up to POINT_REACH keeps their shift (fields of a variable)."""

    blocks: dict[str, Block]                                   # the release's blocks
    canonical_bases: dict[str, int]
    segments: dict[str, list[list[int]]]
    strings: dict[str, dict[int, int]] = field(default_factory=dict)   # source address → canonical
    points: dict[str, list[list[int]]] = field(default_factory=dict)   # [canonical, source] addresses
    _sources: dict[str, list[int]] = field(default_factory=dict)
    _longest: dict[str, int] = field(default_factory=dict)
    _points: dict[str, list[tuple[int, int]]] = field(default_factory=dict)

    def __post_init__(self) -> None:
        self.segments = {n: sorted(segs, key=lambda s: s[2]) for n, segs in self.segments.items()}
        for name, segs in self.segments.items():
            self._sources[name] = [s[2] for s in segs]
        self._longest = {n: max((s[1] for s in segs), default=0) for n, segs in self.segments.items()}
        self.index_points()

    def index_points(self) -> None:
        self._points = {n: sorted((s, c) for c, s in pts) for n, pts in self.points.items()}

    def owner(self, block: str, value: int) -> str:
        """The block a pointer of `block` points into: its own overlay, else the executable (with
        the memory beyond its image)."""
        own = self.blocks[block]
        return block if block != "exe" and own.base <= value <= own.base + len(own.data) else "exe"

    def translate(self, block: str, value: int) -> int | None:
        if not _address_like(value):
            return None
        name = self.owner(block, value)
        if value in self.strings.get(name, {}):
            return self.strings[name][value]
        points = self._points.get(name, [])
        k = bisect.bisect_left(points, (value, 0))
        if k < len(points) and points[k][0] == value:     # what the code names, exactly
            return points[k][1]
        off = value - self.blocks[name].base
        segs, best = self.segments[name], None
        k = bisect.bisect_right(self._sources[name], off) - 1
        # Segments may share source bytes (data the release keeps once): the longest one wins.
        while k >= 0 and segs[k][2] + self._longest[name] >= off:
            c, length, s = segs[k]
            if off <= s + length and (best is None or length > best[1]):     # the end too: one past an object
                best = segs[k]
            k -= 1
        if best is not None:
            return self.canonical_bases[name] + best[0] + off - best[2]
        k = bisect.bisect_right(points, (value, 1 << 32)) - 1
        if k >= 0 and value - points[k][0] < POINT_REACH:
            return points[k][1] + value - points[k][0]
        return None


def _address_like(w: int) -> bool:
    return ADDRESS_RANGE[0] <= w < ADDRESS_RANGE[1]


def _code_pair(a: int, b: int) -> bool:
    """Whether two words are one instruction with different immediates or jump targets."""
    op = a >> 26
    if op != b >> 26:
        return False
    if op in (2, 3):
        return True
    return op in IMMEDIATE_OPS and a >> 16 == b >> 16


def _room(block: Block, addr: int) -> int:
    """The bytes a string of Japan Rev.1 occupies: its text, the terminator and the zeros up to
    the next word."""
    off = addr - block.base
    end = block.data.index(b"\0", off) + 1
    while end % 4 and end < len(block.data) and block.data[end] == 0:
        end += 1
    return end - off


def _inside(segments: list[list[int]], off: int, starts: list[int] | None = None) -> bool:
    """Whether `off` lies in one of the segments (sorted; `starts` their offsets, if at hand)."""
    k = bisect.bisect_right(starts if starts is not None else [s[0] for s in segments], off) - 1
    return k >= 0 and off < segments[k][0] + segments[k][1]


# --- building --------------------------------------------------------------------------------------

def _sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _text_strings(block: Block, segments: list[list[int]], taken: set[int]) -> list[int]:
    """The offsets of the texts of a block outside its segments: printable runs of two or more
    characters where a text may start (Block.text_start), ended by a zero."""
    data, out = block.data, []
    starts = [seg[0] for seg in segments]
    off = 0
    while off < len(data):
        if off not in taken and block.text_start(off) and not _inside(segments, off, starts):
            end = data.find(b"\0", off, off + STRING_LIMIT)
            if end - off >= 2 and all(printable(c) for c in data[off:end]):
                out.append(off)
                off = end
        off += 1
    return out


def _find_text(block: Block, text: str) -> int | None:
    """The address of the one zero-terminated occurrence of `text` in a block, or None."""
    raw, data = text.encode("ascii") + b"\0", block.data
    hits = []
    at = data.find(raw)
    while at >= 0 and len(hits) < 2:
        if at == 0 or data[at - 1] == 0:
            hits.append(at)
        at = data.find(raw, at + 1)
    return block.base + hits[0] if len(hits) == 1 else None


def build(canon: Disc, source: Disc) -> dict:
    """The layout of `source`'s release on Japan Rev.1 (both discs at hand)."""
    import usa   # noqa: PLC0415  (usa imports this module)
    cb, sb = canon.blocks(), source.blocks()
    segments = {}
    for name in cb:
        segments[name] = align(cb[name].data, sb[name].data)
        log.info("%s %s: %d segments", source.release.key, name, len(segments[name]))
    refs = address_map(cb, sb)
    strings: dict[str, dict[int, tuple[int, int]]] = collections.defaultdict(dict)   # canonical → (source, room)
    amap = Map(sb, {n: b.base for n, b in cb.items()}, segments)

    def pair(name: str, c_addr: int, s_addr: int) -> bool:
        cblock = cb[name]
        if not cblock.contains(c_addr) or _inside(segments[name], c_addr - cblock.base):
            return False
        text, other = cblock.string(c_addr, STRING_LIMIT), sb[name].string(s_addr, STRING_LIMIT)
        if not text or other is None:
            return False
        if c_addr not in strings[name]:
            strings[name][c_addr] = (s_addr, _room(cblock, c_addr))
            amap.strings.setdefault(name, {})[s_addr] = c_addr
        return True

    # Objects the code names, then objects pointer words name: texts are paired, the rest grows
    # from there while the bytes are equal (addresses masked: pointer tables, variables); what
    # does not grow is a point.
    masked = {n: (_masked(cb[n].data), _masked(sb[n].data)) for n in cb}
    # Where objects start: what the code names and what pointers point at. A run grown from one
    # object stops at the next (zero-filled variables are equal whatever their shift).
    starts: dict[str, list[int]] = {}
    for name, cblock in cb.items():
        found = {a - cblock.base for (n, a) in refs if n == name and cblock.contains(a)}
        for other in (cblock, cb["exe"]):
            found.update(w - cblock.base for w in other.words if cblock.contains(w))
        starts[name] = sorted(found)

    def grow(name: str, c_addr: int, s_addr: int) -> bool:
        cblock, sblock = cb[name], sb[name]
        if not (cblock.contains(c_addr) and sblock.contains(s_addr)):
            return False
        c, s_off, segs = c_addr - cblock.base, s_addr - sblock.base, segments[name]
        k = bisect.bisect_right([seg[0] for seg in segs], c)
        if k and c < segs[k - 1][0] + segs[k - 1][1]:
            return False
        end = segs[k][0] if k < len(segs) else len(cblock.data)
        j = bisect.bisect_right(starts[name], c)
        if j < len(starts[name]):
            end = min(end, starts[name][j])
        ma, mb = masked[name]
        n = 0
        while c + n < end and s_off + n < len(mb) and ma[c + n] == mb[s_off + n]:
            n += 1
        piece = _trimmed(ma, mb, [c, c + n, s_off - c])
        if piece[1] - piece[0] < 4:
            return False
        segs.insert(k, [piece[0], piece[1] - piece[0], piece[0] + s_off - c])
        return True

    points: dict[str, list[list[int]]] = collections.defaultdict(list)
    for (name, c_addr), s_addr in sorted(refs.items()):
        if not pair(name, c_addr, s_addr) and not grow(name, c_addr, s_addr):
            points[name].append([c_addr, s_addr])
    grown = True
    while grown:
        grown = False
        for name, cblock in cb.items():
            sdata = sb[name].data
            for c, length, s in list(segments[name]):
                if (c - s) % 4:
                    continue
                for off in range(c + (-c) % 4, c + length - 3, 4):
                    cw = struct.unpack_from("<I", cblock.data, off)[0]
                    sw = struct.unpack_from("<I", sdata, off - c + s)[0]
                    if not (_address_like(cw) and _address_like(sw)):
                        continue
                    target = name if name != "exe" and cblock.contains(cw) else "exe"
                    if not pair(target, cw, sw) and grow(target, cw, sw):
                        grown = True
    # Gaps between runs of one shift keep it (code with other immediates, data of other values)
    # unless an object the code names there has another shift.
    for name, cblock in cb.items():
        shifts = sorted((c_addr - cblock.base, s_addr - c_addr) for (n, c_addr), s_addr in refs.items()
                        if n == name and cblock.contains(c_addr))
        filled: list[list[int]] = []
        for seg in sorted(segments[name]):
            if filled:
                c, length, s = filled[-1]
                gap = seg[0] - c - length
                if 0 <= gap <= FILL_GAP and seg[2] - seg[0] == s - c:
                    k = bisect.bisect_left(shifts, (c + length, -(1 << 40)))
                    other = False
                    while k < len(shifts) and shifts[k][0] < seg[0]:
                        other = other or shifts[k][1] != (s - c) + sb[name].base - cblock.base
                        k += 1
                    if not other:
                        filled[-1][1] = seg[0] + seg[1] - c
                        continue
            filled.append(list(seg))
        segments[name] = filled
    amap = Map(sb, {n: b.base for n, b in cb.items()}, segments, amap.strings, points)
    # Texts outside the segments found by their text: the same, or the release's wording of it.
    wording: dict[str, dict[str, str]] = {}
    if source.release.english:
        wording = json.loads(PROJECT_WORDING.read_text())["blocks"]
        for name, pairs in usa.string_pairs(cb, sb, refs).items():
            wording.setdefault(name, {}).update(pairs)
    for name, cblock in cb.items():
        taken = {a - cblock.base for a in strings[name]}
        for off in _text_strings(cblock, segments[name], taken):
            text = cblock.string(cblock.base + off, STRING_LIMIT)
            codes = text[:len(text) - len(usa.body(text))]
            other = wording.get(name, {}).get(usa.body(text), usa.body(text))
            found = _find_text(sb[name], codes + other)
            if found is not None:
                pair(name, cblock.base + off, found)

    def same_object(cw: int) -> bool:
        """Whether the rebase puts at `cw` what Japan Rev.1 has there (masked bytes mostly equal,
        through the segments that cover them)."""
        ct = next((n for n, b in cb.items() if n != "exe" and b.contains(cw)), "exe")
        if not cb[ct].contains(cw):
            return False
        o = cw - cb[ct].base
        segs = segments[ct]
        seg_starts = [seg[0] for seg in segs]
        a, b = masked[ct]
        equal = 0
        for i in range(o, min(o + SAME_WINDOW, len(a))):
            k = bisect.bisect_right(seg_starts, i) - 1
            if k >= 0 and i < segs[k][0] + segs[k][1]:
                equal += a[i] == b[segs[k][2] + i - segs[k][0]]
        return equal >= SAME_SHARE * SAME_WINDOW

    relocs: dict[str, list[int]] = {}
    pinned: dict[str, list[list[int]]] = collections.defaultdict(list)
    for name, cblock in cb.items():
        sdata, found = sb[name].data, []
        for c, length, s in segments[name]:
            if (c - s) % 4:
                continue
            for off in range(c + (-c) % 4, c + length - 3, 4):
                cw = struct.unpack_from("<I", cblock.data, off)[0]
                sw = struct.unpack_from("<I", sdata, off - c + s)[0]
                if cw == sw or not (_address_like(cw) and _address_like(sw)):
                    continue
                if amap.translate(name, sw) is None:
                    pair(amap.owner(name, sw), cw, sw)
                target = amap.translate(name, sw)
                if (target is not None and target != cw and abs(target - cw) <= PIN_REACH
                        and not usa._texty(cblock.string(cw) if cblock.contains(cw) else cb["exe"].string(cw))
                        and same_object(cw)):
                    # One object whose address the segments miss (a pointer before its object,
                    # into another that moved otherwise): its address is kept.
                    pinned[name].append([off, cw])
                elif target is not None:
                    # The release's own object when the pointers differ in more than the address.
                    found.append(off)
        relocs[name] = found
    layout = {"release": source.release.key, "canonical": CANONICAL.key, "blocks": {}}
    for name, cblock in cb.items():
        extras = EXTRAS.get(source.release.key, {}).get(name, {})
        for a in extras.get("tables", {}):
            if (name, a) not in refs:
                raise LayoutError(f"{name} 0x{a:08X}: the code names no counterpart of this table")
        layout["blocks"][name] = {
            "sha256": _sha256(sb[name].data),
            "size": len(cblock.data),
            "segments": sorted(segments[name]),
            "points": sorted(points[name]),
            "relocs": relocs[name],
            "pinned": pinned[name],
            "strings": [[a, s, room] for a, (s, room) in sorted(strings[name].items())],
            "texts": [[a, text] for a, text in sorted(extras.get("texts", {}).items())],
            "tables": [[a, refs[(name, a)], *shape] for a, shape in sorted(extras.get("tables", {}).items())],
            "patches": [[a, bytes(data).hex()] for a, data in sorted(extras.get("patches", {}).items())],
        }
    return layout


# --- rebasing --------------------------------------------------------------------------------------

@functools.cache
def load(release: Release) -> dict:
    path = LAYOUTS / f"{release.key}.json"
    if not path.exists():
        raise LayoutError(f"no layout for the {release.label} release ({path.name})")
    return json.loads(path.read_text())


def rebase(layout: dict, source: Disc) -> tuple[dict[str, bytes], dict[tuple[str, int], str]]:
    """Japan Rev.1-layout images of `source`'s blocks and the texts kept aside."""
    sb = source.blocks()
    for name, entry in layout["blocks"].items():
        if _sha256(sb[name].data) != entry["sha256"]:
            raise LayoutError(f"the {source.release.label} image's {name} differs from the one its layout "
                              "was made from (another pressing or a modified image)")
    canonical_bases = {"exe": EXE_BASE, **{n: CANONICAL.slots[slot] for n, (_, slot) in OVERLAYS.items()}}
    blocks = layout["blocks"]
    amap = Map(sb, canonical_bases, {n: [list(s) for s in e["segments"]] for n, e in blocks.items()},
               {n: {s: a for a, s, _ in e["strings"]} for n, e in blocks.items()},
               {n: e["points"] for n, e in blocks.items()})
    images, aside = {}, {}
    for name, entry in layout["blocks"].items():
        data, src, base = bytearray(entry["size"]), sb[name].data, canonical_bases[name]
        for c, length, s in entry["segments"]:
            data[c:c + length] = src[s:s + length]
        for off in entry["relocs"]:
            value = amap.translate(name, struct.unpack_from("<I", data, off)[0])
            if value is None:
                raise LayoutError(f"{name}: the pointer at 0x{base + off:08X} has no counterpart")
            struct.pack_into("<I", data, off, value)
        for off, value in entry["pinned"]:
            struct.pack_into("<I", data, off, value)
        texts = [(a, sb[name].string(s, STRING_LIMIT), room) for a, s, room in entry["strings"]]
        texts += [(a, text, 0) for a, text in entry["texts"]]
        for addr, text, room in texts:
            if text is None:
                raise LayoutError(f"{name}: no text for 0x{addr:08X}")
            raw = text.encode("ascii") + b"\0"
            if len(raw) <= room:
                data[addr - base:addr - base + len(raw)] = raw
            else:
                aside[(name, addr)] = text
        for addr, source_addr, rows, size, source_size in entry["tables"]:
            at = source_addr - sb[name].base
            for row in range(rows):
                start = addr - base + size * row
                data[start:start + size] = src[at + source_size * row:at + source_size * row + size]
        for addr, hexdata in entry["patches"]:
            patch = bytes.fromhex(hexdata)
            data[addr - base:addr - base + len(patch)] = patch
        images[name] = bytes(data)
    return images, aside


def _bases(release: Release, block: str) -> tuple[int, int]:
    """A block's base in Japan Rev.1 and in `release`."""
    if block == "exe":
        return EXE_BASE, EXE_BASE
    slot = OVERLAYS[block][1]
    return CANONICAL.slots[slot], release.slots[slot]


def source_address(release: Release, block: str, addr: int) -> int | None:
    """The address in `release`'s own layout of what Japan Rev.1 keeps at `addr` (in a segment)."""
    if release == CANONICAL:
        return addr
    canonical_base, source_base = _bases(release, block)
    off = addr - canonical_base
    for c, length, s in load(release)["blocks"][block]["segments"]:
        if c <= off < c + length:
            return source_base + s + off - c
    return None


def canonical_address(release: Release, block: str, addr: int) -> int | None:
    """The Japan Rev.1 address of what `release` keeps at `addr` (the longest segment holding it)."""
    if release == CANONICAL:
        return addr
    canonical_base, source_base = _bases(release, block)
    off = addr - source_base
    best = None
    for c, length, s in load(release)["blocks"][block]["segments"]:
        if s <= off < s + length and (best is None or length > best[1]):
            best = (c, length, s)
    return None if best is None else canonical_base + best[0] + off - best[2]


def rebased(source: Disc) -> Disc:
    """`source` in Japan Rev.1's layout: its executable and overlays rebased, the rest as is."""
    images, aside = rebase(load(source.release), source)
    records = list(source.records)
    for name, (bns, _) in OVERLAYS.items():
        records[bns] = images[name]
    exe = source.exe[:EXE_HEADER] + images["exe"]
    log.info("%s: rebased onto the %s layout (%d texts kept aside)", source.release.label, CANONICAL.label, len(aside))
    return Disc(source.release, exe, records, source.image, CANONICAL, aside, source)


# --- report ----------------------------------------------------------------------------------------

def _ranges(offsets: list[int]) -> list[tuple[int, int]]:
    out: list[list[int]] = []
    for off in offsets:
        if out and off <= out[-1][1] + 8:
            out[-1][1] = off + 1
        else:
            out.append([off, off + 1])
    return [(a, b - a) for a, b in out]


def report(layout: dict, canon: Disc, source: Disc, detail: int) -> dict[str, dict[str, int]]:
    """What differs from Japan Rev.1 after the rebase, per block and kind (bytes)."""
    images, aside = rebase(layout, source)
    cb = canon.blocks()
    totals: dict[str, dict[str, int]] = {}
    for name, entry in layout["blocks"].items():
        base, want, got = cb[name].base, cb[name].data, images[name]
        segs = entry["segments"]
        starts = [seg[0] for seg in segs]
        text_bytes = set()
        for a, _s, room in entry["strings"]:
            text_bytes.update(range(a - base, a - base + room))
        for a, text in entry["texts"]:
            text_bytes.update(range(a - base, a - base + len(text) + 1))
        kinds: dict[str, list[int]] = collections.defaultdict(list)
        for off in range(len(want)):
            if want[off] == got[off]:
                continue
            if off in text_bytes:
                kinds["text"].append(off)
            elif not _inside(segs, off, starts):
                kinds["unmapped"].append(off)
            else:
                w = off & ~3
                cw = struct.unpack_from("<I", want, w)[0] if w + 4 <= len(want) else 0
                gw = struct.unpack_from("<I", got, w)[0] if w + 4 <= len(got) else 0
                kinds["code" if _code_pair(cw, gw) else "data"].append(off)
        totals[name] = {k: len(v) for k, v in kinds.items()}
        log.info("%s: %s", name, ", ".join(f"{k} {len(v)}" for k, v in sorted(kinds.items())) or "identical")
        for kind in ("data", "unmapped"):
            for start, length in _ranges(kinds[kind])[:detail]:
                sample = want[start:start + min(length, 24)]
                log.info("  %s 0x%08X +%d: rev1 %s | rebased %s", kind, base + start, length, sample.hex(),
                         got[start:start + min(length, 24)].hex())
    for (name, addr), text in sorted(aside.items()):
        log.info("aside %s 0x%08X: %r", name, addr, text)
    return totals


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--image", type=Path, action="append", required=True,
                        help="a disc image, one per release: Japan Rev.1's and those of the releases to lay out")
    parser.add_argument("--check", action="store_true", help="report on the saved layouts, write nothing")
    parser.add_argument("--detail", type=int, default=20, help="differing ranges listed per block and kind")
    args = parser.parse_args()
    try:
        discs = open_discs(args.image)
    except (DiscError, ImageError) as e:
        log.error("%s", e)
        return 1
    canon = discs.pop(CANONICAL.key, None)
    if canon is None or not discs:
        log.error("layouts need a %s image and one of another release", CANONICAL.label)
        return 1
    for release in RELEASES:
        if release.key not in discs:
            continue
        source = discs[release.key]
        layout = load(release) if args.check else build(canon, source)
        if not args.check:
            LAYOUTS.mkdir(exist_ok=True)
            (LAYOUTS / f"{release.key}.json").write_text(json.dumps(layout, separators=(",", ":")) + "\n")
        log.info("--- %s", release.label)
        report(layout, canon, source, args.detail)
    return 0


if __name__ == "__main__":
    sys.exit(main())
