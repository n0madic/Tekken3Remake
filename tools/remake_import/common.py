"""Shared paths, disc access and output helpers for the remake asset converter."""

from __future__ import annotations

import gzip
import json
import logging
import re
import struct
import sys
from dataclasses import dataclass, field
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RESEARCH_TOOLS = ROOT / "tools" / "research"
if str(RESEARCH_TOOLS) not in sys.path:
    sys.path.insert(0, str(RESEARCH_TOOLS))

import compare_bns  # noqa: E402  (research tools: disc and BNS access)
import overlay_images  # noqa: E402
import system_textures  # noqa: E402
from disc_image import DiscImage, open_image  # noqa: E402
from sources import Recorder  # noqa: E402
from vram import Vram  # noqa: E402

DEFAULT_OUT = ROOT / "remake" / "imported"
EXE_BASE = 0x80010000
EXE_HEADER = 0x800
CONVERTER_VERSION = 2       # raised when the remake cannot read older output (AssetCatalog.CONVERTER_VERSION)
SIDECARS = (".import", ".uid")  # written by Godot next to imported files (textures, movies)
BNS_RECORDS = 303
# The overlays by name: BNS record and slot (0 the mode slot, 1 the screen slot).
OVERLAYS = {"arcade": (5, 0), "practice": (6, 0), "force": (7, 0), "volley": (8, 0),
            "enbu": (0, 1), "select": (9, 1), "title": (10, 1), "ranking": (11, 1),
            "ending": (301, 1), "result": (302, 1)}

log = logging.getLogger("remake_import")


class DiscError(Exception):
    """The image is not a Tekken 3 release the converter reads."""


@dataclass(frozen=True)
class Release:
    """A release of the game: where its files are and where its overlays load."""

    key: str
    label: str
    exe_path: tuple[str, ...]
    bns_path: tuple[str, ...]
    xas_path: tuple[str, ...]
    bns_table: int                  # EXE file offset of the BNS index
    bns_entry: int                  # its entry size: (LBA, size) and, in the original, a name pointer
    slots: tuple[int, int]          # the mode and the screen overlay slot
    english: bool                   # its game texts are the USA English


# Japan Rev.1 is the canonical release: the addresses of the converter, the remake and the docs
# are its own; the others' images are rebased onto it (layout.py).
JP_REV1 = Release("jp_rev1", "Japan Rev.1", ("SLPS_013.00",), ("TEKKEN3.BNS",), ("TEKKEN3.XAS",),
                  0x14E6C, 8, (0x800B0A10, 0x800B9378), False)
JP_ORIG = Release("jp_orig", "Japan (original)", ("SLPS_013.00",), ("TEKKEN3.BNS",), ("TEKKEN3.XAS",),
                  0x14CC8, 12, (0x800B19E0, 0x800BA428), False)
USA = Release("usa", "USA", ("TEKKEN3", "SLUS_004.02"), ("TEKKEN3", "TEKKEN3.BNS"), ("TEKKEN3", "TEKKEN3.XAS"),
              0x14C00, 8, (0x800B0548, 0x800B8D58), True)
CANONICAL = JP_REV1
RELEASES = (JP_REV1, JP_ORIG, USA)      # also the preference of the game's source disc
# Where the canonical layout loads the overlays: the mode overlays (arcade.ovl, practice.ovl, ...)
# and the screen overlays (title.ovl, select.ovl, ...).
MODE_SLOT, SCREEN_SLOT = CANONICAL.slots


def printable(c: int) -> bool:
    return 0x20 <= c < 0x7F


def text_start(data: bytes, off: int) -> bool:
    """Whether a text may start at `off`: after a zero, or on a word after data (texts are word
    aligned after other data)."""
    if off == 0 or data[off - 1] == 0:
        return True
    return off % 4 == 0 and not all(printable(c) for c in data[off - 4:off])


class Block:
    """One memory block of a release: the executable image or an overlay at its slot."""

    def __init__(self, name: str, base: int, data: bytes) -> None:
        self.name = name
        self.base = base
        self.data = data
        self.words = list(struct.unpack(f"<{len(data) // 4}I", data[:len(data) // 4 * 4]))

    def contains(self, addr: int) -> bool:
        return self.base <= addr < self.base + len(self.data)

    def u32(self, addr: int) -> int | None:
        off = addr - self.base
        return struct.unpack_from("<I", self.data, off)[0] if 0 <= off <= len(self.data) - 4 else None

    def read(self, addr: int, size: int) -> bytes:
        off = addr - self.base
        return self.data[off:off + size]

    def _values(self, kind: str, addr: int, count: int) -> list[int]:
        return list(struct.unpack_from(f"<{count}{kind}", self.data, addr - self.base))

    def u8s(self, addr: int, count: int) -> list[int]:
        return list(self.read(addr, count))

    def s16s(self, addr: int, count: int) -> list[int]:
        return self._values("h", addr, count)

    def u16s(self, addr: int, count: int) -> list[int]:
        return self._values("H", addr, count)

    def s32s(self, addr: int, count: int) -> list[int]:
        return self._values("i", addr, count)

    def u32s(self, addr: int, count: int) -> list[int]:
        return self._values("I", addr, count)

    def text_start(self, off: int) -> bool:
        """Whether a text starts at offset `off`: a printable character where one may start."""
        return printable(self.data[off]) and text_start(self.data, off)

    def string(self, addr: int, limit: int = 200) -> str | None:
        """The printable zero-terminated string at `addr` (possibly empty), or None."""
        off = addr - self.base
        if not 0 <= off < len(self.data):
            return None
        end = self.data.find(b"\0", off)
        if end < 0 or end - off > limit:
            return None
        raw = self.data[off:end]
        return raw.decode() if re.fullmatch(rb"[\x20-\x7e]*", raw) else None


@dataclass
class Disc:
    """A disc of one release: executable image and BNS records by ID, read from its image
    (disc_image.py). `canonical()` gives it in Japan Rev.1's layout, which the converter reads;
    `strings` are then the texts that did not fit where Japan Rev.1 keeps them, by (block,
    address)."""

    release: Release
    exe: bytes
    records: list[bytes]
    image: DiscImage
    layout: Release | None = None       # whose addresses the images have: the release's own, or CANONICAL
    strings: dict[tuple[str, int], str] = field(default_factory=dict)
    raw: "Disc | None" = None           # a rebased disc's own images (its release's layout)
    _sha256: str = ""
    _blocks: dict[str, Block] = field(default_factory=dict)
    _system_vram: Vram | None = None
    costume_vrams: dict[int, Vram] = field(default_factory=dict)   # character.costume_textures, by ARC record
    _canonical: "Disc | None" = None    # the rebased disc, made once

    @classmethod
    def open(cls, path: Path) -> "Disc":
        image = open_image(path)
        try:
            release, exe = _identify(image)
            bns = compare_bns.read_iso_file(image.sectors, release.bns_path)[0]
        except (ValueError, DiscError) as e:
            image.close()
            raise DiscError(f"{path.name}: {e}") from e
        records = []
        for record_id in range(BNS_RECORDS):
            lba, size = struct.unpack_from("<II", exe, release.bns_table + release.bns_entry * record_id)
            records.append(bns[lba * 2048:lba * 2048 + size])
        return cls(release, exe, records, image, release)

    def image_sha256(self) -> str:
        if not self._sha256:
            self._sha256 = self.image.sha256()
        return self._sha256

    def canonical(self) -> "Disc":
        """This disc in Japan Rev.1's layout (itself for Japan Rev.1), rebased once."""
        if self.layout == CANONICAL:
            return self
        if self._canonical is None:
            import layout   # noqa: PLC0415  (layout imports this module)
            self._canonical = layout.rebased(self)
        return self._canonical

    def blocks(self) -> dict[str, Block]:
        """The executable image and the overlays at their slots (in this disc's layout)."""
        if not self._blocks:
            self._blocks["exe"] = Block("exe", EXE_BASE, self.exe[EXE_HEADER:])
            for name, (bns, slot) in OVERLAYS.items():
                self._blocks[name] = Block(name, self.layout.slots[slot], self.records[bns])
        return self._blocks

    def source(self, block: str, addr: int) -> tuple[bytes, int]:
        """The bytes of `block` as the release has them and the offset there of what Japan Rev.1
        keeps at `addr`. Objects whose size differs between releases (picture archives) are read
        whole from there."""
        if self.raw is None:
            b = self.blocks()[block]
            return b.data, addr - b.base
        import layout   # noqa: PLC0415
        found = layout.source_address(self.release, block, addr)
        if found is None:
            raise layout.LayoutError(f"{block} 0x{addr:08X} has no counterpart in the {self.release.label} release")
        b = self.raw.blocks()[block]
        return b.data, found - b.base

    def images(self, block: str) -> dict[int, "overlay_images.Found"]:
        """The pictures and picture archives of a block by their Japan Rev.1 addresses."""
        own = (self.raw or self).blocks()[block]
        found = overlay_images.scan(own.data, own.base)
        if self.raw is None:
            return {f.address: f for f in found}
        import layout   # noqa: PLC0415
        out = {}
        for f in found:
            addr = layout.canonical_address(self.release, block, f.address)
            if addr is not None:
                out[addr] = f
        return out

    def system_textures(self) -> list[tuple[int, bytes]]:
        """The executable's system texture archive (FUN_8004CD28): (VRAM word, TIM) per member."""
        own = self.raw or self
        return system_textures.members(own.exe, own.release.key)

    def system_vram(self) -> Vram:
        """The VRAM after the system textures are uploaded, made once: callers that change it copy it."""
        if self._system_vram is None:
            vram = Vram()
            for _, tim in self.system_textures():
                vram.upload_tim(tim)
            self._system_vram = vram
        return self._system_vram

    def text(self, block: str, addr: int) -> str:
        """The zero-terminated string at `addr` of a block (`strings` first)."""
        if (block, addr) in self.strings:
            return self.strings[(block, addr)]
        b = self.blocks()[block]
        off = addr - b.base
        return b.data[off:b.data.index(b"\0", off)].decode("ascii", "replace")

    def exe_text(self, addr: int) -> str:
        return self.text("exe", addr)

    def bns(self, record_id: int) -> bytes:
        data = self.records[record_id]
        if not data:
            raise ValueError(f"BNS record {record_id} is empty")
        return data

    def exe_bytes(self, addr: int, size: int) -> bytes:
        return self.blocks()["exe"].read(addr, size)

    def exe_s16(self, addr: int, count: int) -> list[int]:
        return self.blocks()["exe"].s16s(addr, count)

    def exe_u16(self, addr: int, count: int) -> list[int]:
        return self.blocks()["exe"].u16s(addr, count)

    def exe_s32(self, addr: int, count: int) -> list[int]:
        return self.blocks()["exe"].s32s(addr, count)

    def exe_u8(self, addr: int, count: int) -> list[int]:
        return self.blocks()["exe"].u8s(addr, count)

    def exe_u32(self, addr: int, count: int) -> list[int]:
        return self.blocks()["exe"].u32s(addr, count)


def _original_index(exe: bytes) -> bool:
    """Whether the executable holds the original release's BNS index: 12-byte entries whose
    third word points at the record's file name."""
    for record_id in range(BNS_RECORDS):
        pointer = struct.unpack_from("<I", exe, JP_ORIG.bns_table + 12 * record_id + 8)[0]
        off = pointer - EXE_BASE + EXE_HEADER
        end = exe.find(b"\0", off, off + 64) if EXE_HEADER <= off < len(exe) else -1
        if end <= off or not re.fullmatch(rb"[\x20-\x7e]+", exe[off:end]):
            return False
    return True


def _identify(image: DiscImage) -> tuple[Release, bytes]:
    for release in (USA, JP_REV1):
        try:
            exe = compare_bns.read_iso_file(image.sectors, release.exe_path)[0]
        except ValueError:
            continue
        if release == JP_REV1 and _original_index(exe):
            release = JP_ORIG
        return release, exe
    raise DiscError("not a Tekken 3 disc of a supported release (Japan Rev.1, Japan original, USA)")


def open_discs(paths: list[Path]) -> dict[str, Disc]:
    """The discs of the given images by release key, one image per release."""
    discs: dict[str, Disc] = {}
    for path in paths:
        disc = Disc.open(path)
        if disc.release.key in discs:
            raise DiscError(f"{discs[disc.release.key].image.path.name} and {path.name} are both the "
                            f"{disc.release.label} release; give one image per release")
        discs[disc.release.key] = disc
    return discs


# Written before anything else, so that a run that ended early (no FFmpeg, a layout error, Ctrl-C)
# still leaves a folder the next run recognises as its own: manifest.json comes last.
OUTPUT_MARKER = ".converter"


def _is_own_manifest(path: Path) -> bool:
    """Whether `path` is a manifest.json written by convert.py (folders of runs before the marker
    existed have only that): a JSON object with the converter's own `converter_version` key."""
    try:
        manifest = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return False
    return isinstance(manifest, dict) and "converter_version" in manifest


def is_foreign_folder(folder: Path) -> bool:
    """Whether `folder` holds files the converter did not write (it prunes the files it does not
    produce, so it must not run in such a folder): not empty, without a marker or a manifest of its own."""
    return (folder.exists() and any(folder.iterdir())
            and not (folder / OUTPUT_MARKER).exists() and not _is_own_manifest(folder / "manifest.json"))


@dataclass
class Output:
    """Writes files below the asset root, touching only files whose content changed."""

    root: Path
    written: int = 0
    unchanged: int = 0
    files: set[str] = field(default_factory=set)
    sources: Recorder | None = None     # the pictures' VRAM sources, when the run records them

    def write(self, rel: str, data: bytes) -> None:
        path = self.root / rel
        self.files.add(rel)
        if path.exists() and path.stat().st_size == len(data) and path.read_bytes() == data:
            self.unchanged += 1
            return
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        self.written += 1

    def mark(self) -> None:
        """Marks the folder as the converter's own (OUTPUT_MARKER)."""
        self.write(OUTPUT_MARKER, b"written by tools/remake_import/convert.py\n")

    def invalidate_manifest(self) -> None:
        """Removes the manifest of an earlier run before its files are overwritten: a run that fails
        half way must not leave mixed files under a manifest that still looks complete (the new
        manifest is written last)."""
        (self.root / "manifest.json").unlink(missing_ok=True)

    def write_json(self, rel: str, value: object) -> None:
        """A JSON document; gzip-compressed when the name ends in `.gz`."""
        data = (json.dumps(value, indent=1, sort_keys=True) + "\n").encode()
        self.write(rel, gzipped(data) if rel.endswith(".gz") else data)

    def prune(self) -> int:
        """Deletes files this run did not produce, so builds never pack stale data.

        Godot's `.import` and `.uid` sidecars are kept for produced files and removed with the rest.
        """
        removed = 0
        for path in sorted(self.root.rglob("*"), reverse=True):
            rel = path.relative_to(self.root).as_posix()
            if path.is_dir():
                if not any(path.iterdir()):
                    path.rmdir()
                continue
            source = next((rel[:-len(s)] for s in SIDECARS if rel.endswith(s)), rel)
            if source not in self.files:
                path.unlink()
                removed += 1
        return removed


def gzipped(data: bytes) -> bytes:
    """`data` gzip-compressed without a time stamp (the same bytes on every run). The largest
    binaries are stored so (`*.bin.gz`): they shrink the builds, the web's above all."""
    return gzip.compress(data, compresslevel=9, mtime=0)

