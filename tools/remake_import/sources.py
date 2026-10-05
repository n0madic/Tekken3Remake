"""Where the converted pictures' texels come from in VRAM, for texture-pack importers.

A converter run given `--texture-sources FILE` records, for every picture cut from VRAM, its
pieces: a rectangle of texels of one depth in a VRAM snapshot, seen through a CLUT, and where it
lands in the picture (possibly rotated or mirrored). It also records the VRAM states the remake
builds at run time (the 2D screens' `VramImage`). `tools/remake/texture_pack.py import-duckstation`
reads the file to place an emulator's replacement textures, which are keyed by VRAM contents.

The file holds game data (the VRAM snapshots): it stays with the other converted data, private.
"""

from __future__ import annotations

import json
import zipfile
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

SNAPSHOTS = "snapshots.npz"
INDEX = "sources.json"
IDENTITY = (1, 0, 0, 1)


@dataclass
class Recorder:
    snapshots: list[np.ndarray] = field(default_factory=list)
    pictures: dict[str, dict] = field(default_factory=dict)
    runtime: list[dict] = field(default_factory=list)
    cluts: list[list[int]] = field(default_factory=list)
    _snapshot_ids: dict[tuple, int] = field(default_factory=dict)
    _clut_ids: dict[tuple, int] = field(default_factory=dict)

    def snapshot(self, words: np.ndarray) -> int:
        """The id of a VRAM state (a copy is kept: the array may change afterwards)."""
        key = (words.shape, int(words.sum(dtype=np.uint64)), words[::7, ::13].tobytes())
        found = self._snapshot_ids.get(key)
        if found is None or not np.array_equal(self.snapshots[found], words):
            found = len(self.snapshots)
            self.snapshots.append(words.copy())
            self._snapshot_ids[key] = found
        return found

    def clut(self, colours: np.ndarray) -> int:
        key = tuple(int(c) for c in colours)
        if key not in self._clut_ids:
            self._clut_ids[key] = len(self.cluts)
            self.cluts.append(list(key))
        return self._clut_ids[key]

    def piece(self, rel: str, x: int, y: int, words: np.ndarray, tx: int, ty: int, w: int, h: int,
              depth: int, clut: np.ndarray, transform: tuple[int, int, int, int] = IDENTITY, pad: int = 0) -> None:
        """Texels [tx, tx + w) × [ty, ty + h) of `words` (texel units of `depth`: 4, 8 or 16 bits)
        through `clut`, drawn at picture position (x, y). `transform` (a, b, c, d) maps a picture
        offset (col, row) to the source offset (a·col + b·row, c·col + d·row) from the source
        corner that lands at (x, y); `pad` texels around the piece repeat its edges (atlas gutters)."""
        entry = {"snapshot": self.snapshot(words), "x": x, "y": y, "tx": tx, "ty": ty, "w": w, "h": h,
                 "depth": depth, "clut": self.clut(clut)}
        if tuple(transform) != IDENTITY:
            entry["transform"] = list(transform)
        if pad:
            entry["pad"] = pad
        self.pictures.setdefault(rel, {}).setdefault("pieces", []).append(entry)

    def derived(self, rel: str, base: str, post: str) -> None:
        """`rel` is `base` after a filter (`post`) the importer applies again at the new scale."""
        self.pictures.setdefault(rel, {})["derived"] = {"from": base, "post": post}

    def runtime_vram(self, name: str, words: np.ndarray) -> None:
        """A VRAM state the remake builds at run time, sprites cut from it by page and CLUT."""
        self.runtime.append({"name": name, "snapshot": self.snapshot(words)})

    def save(self, path: Path) -> None:
        """A zip: the snapshots (`snapshots.npz`) and the pieces (`sources.json`)."""
        path.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(path, "w", zipfile.ZIP_DEFLATED) as z:
            with z.open(SNAPSHOTS, "w") as f:
                np.savez(f, *self.snapshots)
            z.writestr(INDEX, json.dumps({"pictures": self.pictures, "runtime": self.runtime,
                                          "cluts": self.cluts}))


@dataclass
class Sources:
    """A saved recording."""
    snapshots: list[np.ndarray]
    pictures: dict[str, dict]
    runtime: list[dict]
    cluts: list[np.ndarray]

    @classmethod
    def load(cls, path: Path) -> "Sources":
        with zipfile.ZipFile(path) as z:
            with z.open(SNAPSHOTS) as f:
                arrays = np.load(f)
                snapshots = [arrays[f"arr_{i}"] for i in range(len(arrays.files))]
            index = json.loads(z.read(INDEX))
        return cls(snapshots, index["pictures"], index["runtime"],
                   [np.array(c, dtype=np.uint16) for c in index["cluts"]])


def piece(out, rel: str, x: int, y: int, words: np.ndarray, tx: int, ty: int, w: int, h: int, depth: int,
          clut: np.ndarray, transform: tuple[int, int, int, int] = IDENTITY, pad: int = 0) -> None:
    """Records a piece when the run records sources (`out.sources`), else nothing."""
    if out.sources is not None:
        out.sources.piece(rel, x, y, words, tx, ty, w, h, depth, clut, transform, pad)


def page_piece(out, rel: str, x: int, y: int, vram, page_x: int, page_y: int, depth: int, u: int, v: int,
               w: int, h: int, clut_x: int, clut_y: int, transform: tuple[int, int, int, int] = IDENTITY,
               pad: int = 0) -> None:
    """A piece given as a texture page (VRAM words), texels (u, v) in it and a CLUT position."""
    if out.sources is not None:
        per_word = 16 // depth
        out.sources.piece(rel, x, y, vram.words, page_x * per_word + u, page_y + v, w, h, depth,
                          vram.clut(clut_x, clut_y, 1 << depth), transform, pad)


def derived(out, rel: str, base: str, post: str) -> None:
    if out.sources is not None:
        out.sources.derived(rel, base, post)


def runtime_vram(out, name: str, words: np.ndarray) -> None:
    if out.sources is not None:
        out.sources.runtime_vram(name, words)
