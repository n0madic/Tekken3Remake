"""Converts a DuckStation texture replacement pack into a remake texture pack.

DuckStation's page-mode replacements (`texpage-<mode>-<texture hash>-<palette hash>-<page size>-
<x>-<y>-<w>x<h>-P<min>-<max>.png`) are keyed by the VRAM contents they replace: the XXH3-64 of a
rectangle of VRAM words at an offset in a texture page, and of the CLUT they were drawn through
(`src/core/gpu_hw_texture_cache.cpp`: DumpTextureFromPage, HashRect, HashPartialPalette). The
converter records where every picture's texels come from in VRAM (`--texture-sources`,
tools/remake_import/sources.py); the importer finds each replacement's rectangle in those VRAM
snapshots, then:

- repaints the converted pictures it covers at the replacements' scale (the rest of a picture
  upscaled), written as `<key>.png` (remake/content/texture_packs.gd);
- for the VRAM states the 2D screens build at run time (`VramImage`), keeps the replacement as it
  is in `vram/`, listed in `vram.json` with its page, CLUT and a SHA-256 of the VRAM words it
  replaces, which the game checks before drawing it.

Replacements that match nothing the remake draws are listed in `import_report.txt`.

TODO: the pictures the converter cuts from VRAM elsewhere than the game uploads them (the big and
VS portraits, the effect flipbooks, the fighters' name plates) and `texupload-`/`vram-write-`
replacements, C16 textures and config.yaml aliases are not imported (remake-plan.md, M5).
"""

from __future__ import annotations

import hashlib
import json
import logging
import re
import shutil
from collections import defaultdict
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

from vram import VRAM_H, VRAM_W, rgba, unpack_indices

log = logging.getLogger("texture_pack")

NAME = re.compile(r"texpage-(ST)?P(4|8)-([0-9A-F]{16})-([0-9A-F]{16})-(\d+)x(\d+)-(\d+)-(\d+)-(\d+)x(\d+)"
                  r"-P(\d+)-(\d+)\.(png|jpg|jpeg|webp)", re.IGNORECASE)
PAGE_W, PAGE_H = 64, 256            # a texture page in VRAM words (4-bit: 256 texels wide)
MAX_SCALE = 8
# The largest mean difference (0–255 per channel, over texels opaque in both) between a
# replacement brought to the original size and the texels it replaces through a CLUT. DuckStation's
# palette hash covers max − min + 1 colours from the CLUT's start, a single one for some names
# (P0-0), so it may match other CLUTs; faithful replacements differ by under 11, other CLUTs' by 19
# and more (Tek3_HD08).
MAX_COLOUR_DISTANCE = 14
VRAM_DIR = "vram"
VRAM_INDEX = "vram.json"
REPORT = "import_report.txt"
PNG_LEVEL = 6                       # zlib level: optimize=True costs minutes for a few percent


def xxh3(data: bytes) -> int:
    try:
        import xxhash
    except ImportError as e:
        raise SystemExit("the DuckStation importer needs the xxhash module: python3 -m pip install xxhash") from e
    return xxhash.xxh3_64_intdigest(data)


@dataclass(frozen=True)
class Replacement:
    path: Path
    depth: int                      # 4 or 8
    semi_transparent: bool          # dumped with semi-transparent draws: alpha holds the blend, not coverage
    texture_hash: int
    palette_hash: int
    x: int                          # texels from the page's left edge
    y: int
    w: int
    h: int
    palette_min: int                # the CLUT indices the rectangle uses (DuckStation's reduced range)
    palette_max: int

    @property
    def palette_size(self) -> int:
        """CLUT entries hashed: DuckStation hashes max − min + 1 colours from the CLUT's start."""
        return self.palette_max - self.palette_min + 1

    @property
    def words(self) -> tuple[int, int]:
        """The rectangle's first word column in the page and its width in words."""
        per_word = 16 // self.depth
        return self.x // per_word, self.w // per_word

    def region(self, words: np.ndarray, page_x: int, page_y: int) -> np.ndarray:
        """The VRAM words the rectangle covers in the page at (page_x, page_y)."""
        x0, ww = self.words
        return words[page_y + self.y:page_y + self.y + self.h, page_x + x0:page_x + x0 + ww]


def parse_pack(folder: Path) -> tuple[list[Replacement], list[Path]]:
    """The page-mode replacements of a pack folder (searched recursively) and the files skipped."""
    found, skipped = [], []
    for path in sorted(folder.rglob("*")):
        if not path.is_file() or path.suffix.lower() not in (".png", ".jpg", ".jpeg", ".webp"):
            continue
        m = NAME.fullmatch(path.name)
        if m is None:
            skipped.append(path)
            continue
        st, depth, th, ph, _, _, x, y, w, h, pmin, pmax, _ = m.groups()
        depth = int(depth)
        if int(x) % (16 // depth) or int(w) % (16 // depth):
            skipped.append(path)
            continue
        found.append(Replacement(path, depth, st is not None, int(th, 16), int(ph, 16), int(x), int(y), int(w), int(h),
                                 int(pmin), int(pmax)))
    return found, skipped


@dataclass
class Match:
    replacement: Replacement
    page_x: int                     # VRAM words
    page_y: int

    def texel_rect(self) -> tuple[int, int, int, int]:
        """The rectangle in texel units of its depth: x, y, w, h."""
        per_word = 16 // self.replacement.depth
        r = self.replacement
        return self.page_x * per_word + r.x, self.page_y + r.y, r.w, r.h


class Matcher:
    """Finds replacements in VRAM snapshots by their texture hash."""

    def __init__(self, replacements: list[Replacement]) -> None:
        self.by_geometry: dict[tuple, dict[int, list[Replacement]]] = defaultdict(lambda: defaultdict(list))
        for r in replacements:
            self.by_geometry[(r.depth, r.y, r.h) + r.words][r.texture_hash].append(r)
        self._done: dict[tuple, list[Match]] = {}

    def in_page(self, words: np.ndarray, snapshot: int, page_x: int, page_y: int, depth: int) -> list[Match]:
        key = (snapshot, page_x, page_y, depth)
        if key not in self._done:
            found = []
            for (d, y, h, wx, ww), by_hash in self.by_geometry.items():
                x0 = page_x + wx
                if d != depth or x0 + ww > VRAM_W or page_y + y + h > VRAM_H:
                    continue
                digest = xxh3(np.ascontiguousarray(words[page_y + y:page_y + y + h, x0:x0 + ww]).tobytes())
                found.extend(Match(r, page_x, page_y) for r in by_hash.get(digest, ()))
            self._done[key] = found
        return self._done[key]


def palette_hash(clut: np.ndarray, size: int) -> int | None:
    return xxh3(np.ascontiguousarray(clut[:size]).astype("<u2").tobytes()) if size <= len(clut) else None


def colour_distance(small: np.ndarray, indices: np.ndarray, clut: np.ndarray) -> float:
    """How far a replacement brought to the original size (`small`) is from the texels' colours
    through `clut` (MAX_COLOUR_DISTANCE)."""
    if int(indices.max()) >= len(clut):
        return float("inf")
    ours = rgba(clut[indices]).astype(np.int32)
    both = (ours[..., 3] > 0) & (small[..., 3] > 0)
    if not both.any():
        return 0.0
    return float(np.abs(ours[..., :3] - small[..., :3]).mean(axis=-1)[both].mean())


def page_of(tx: int, ty: int, depth: int) -> tuple[int, int]:
    per_word = 16 // depth
    return (tx // per_word) // PAGE_W * PAGE_W, ty // PAGE_H * PAGE_H


def _intersect(a: tuple[int, int, int, int], b: tuple[int, int, int, int]) -> tuple[int, int, int, int] | None:
    x0, y0 = max(a[0], b[0]), max(a[1], b[1])
    x1, y1 = min(a[0] + a[2], b[0] + b[2]), min(a[1] + a[3], b[1] + b[3])
    return (x0, y0, x1 - x0, y1 - y0) if x1 > x0 and y1 > y0 else None


def load_replacement(r: Replacement) -> np.ndarray:
    """The replacement's RGBA pixels; a semi-transparent one's alpha becomes coverage (the remake
    blends such textures by their draw mode, as the game does)."""
    with Image.open(r.path) as image:
        pixels = np.array(image.convert("RGBA"))
    if r.semi_transparent:
        pixels[..., 3] = np.where(pixels[..., 3] > 0, 255, 0)
    return pixels


def scale_of(r: Replacement, pixels: np.ndarray) -> int | None:
    h, w = pixels.shape[:2]
    if w % r.w or h % r.h or w // r.w != h // r.h or w // r.w < 1:
        return None
    return w // r.w


def resized(pixels: np.ndarray, w: int, h: int) -> np.ndarray:
    if pixels.shape[1] == w and pixels.shape[0] == h:
        return pixels
    return np.asarray(Image.fromarray(np.ascontiguousarray(pixels), "RGBA").resize((w, h), Image.LANCZOS))


@dataclass
class PieceHd:
    """A picture piece at the output scale: its source rectangle's HD texels and which are replaced."""
    pixels: np.ndarray
    covered: np.ndarray
    used: set[Path] = field(default_factory=set)


class Importer:
    def __init__(self, sources, imported: Path, replacements: list[Replacement], scale: int | None) -> None:
        self.sources = sources
        self.imported = imported
        self.matcher = Matcher(replacements)
        self.scale = scale
        self._pixels: dict[Path, np.ndarray | None] = {}
        self._small: dict[Path, np.ndarray] = {}
        self._colours: dict[tuple, bool] = {}
        self._pictures: dict[str, tuple[np.ndarray, int] | None] = {}
        self._bases = {e["derived"]["from"] for e in sources.pictures.values() if "derived" in e}
        self.used: set[Path] = set()           # the replacements drawn into pictures

    def pixels(self, r: Replacement) -> np.ndarray | None:
        if r.path not in self._pixels:
            pixels = load_replacement(r)
            if scale_of(r, pixels) is None:
                log.warning("%s: %d × %d is not a whole multiple of %d × %d; skipped", r.path.name,
                            pixels.shape[1], pixels.shape[0], r.w, r.h)
                pixels = None
            self._pixels[r.path] = pixels
        return self._pixels[r.path]

    def small(self, r: Replacement) -> np.ndarray:
        """A valid replacement brought to the size of the texels it replaces (for colour checks)."""
        if r.path not in self._small:
            image = Image.fromarray(np.ascontiguousarray(self.pixels(r)), "RGBA")
            self._small[r.path] = np.asarray(image.resize((r.w, r.h), Image.BOX)).astype(np.int32)
        return self._small[r.path]

    def piece_matches(self, piece: dict) -> list[tuple[Match, tuple[int, int, int, int]]]:
        """The replacements drawn over a piece: each with the overlap of their texel rectangles."""
        depth = piece["depth"]
        if depth not in (4, 8):
            return []
        words = self.sources.snapshots[piece["snapshot"]]
        clut = self.sources.cluts[piece["clut"]]
        rect = (piece["tx"], piece["ty"], piece["w"], piece["h"])
        pages = {page_of(piece["tx"], piece["ty"], depth),
                 page_of(piece["tx"] + piece["w"] - 1, piece["ty"] + piece["h"] - 1, depth)}
        out = []
        for page_x, page_y in sorted(pages):
            for m in self.matcher.in_page(words, piece["snapshot"], page_x, page_y, depth):
                overlap = _intersect(rect, m.texel_rect())
                if (overlap is not None and palette_hash(clut, m.replacement.palette_size) == m.replacement.palette_hash
                        and self.colours_match(words, piece["snapshot"], m, clut, piece["clut"])):
                    out.append((m, overlap))
        return out

    def colours_match(self, words: np.ndarray, snapshot: int, m: Match, clut: np.ndarray, clut_key: object) -> bool:
        key = (m.replacement.path, snapshot, m.page_x, m.page_y, clut_key)
        if key not in self._colours:
            r = m.replacement
            self._colours[key] = self.pixels(r) is not None and colour_distance(
                self.small(r), unpack_indices(r.region(words, m.page_x, m.page_y), r.depth), clut) <= MAX_COLOUR_DISTANCE
        return self._colours[key]

    def picture_scale(self, matches: list[list[tuple[Match, tuple[int, int, int, int]]]]) -> int:
        if self.scale is not None:
            return self.scale
        best = 1
        for piece_matches in matches:
            for m, _ in piece_matches:
                pixels = self.pixels(m.replacement)
                if pixels is not None:
                    best = max(best, scale_of(m.replacement, pixels) or 1)
        return min(best, MAX_SCALE)

    def piece_hd(self, piece: dict, matches: list[tuple[Match, tuple[int, int, int, int]]], n: int) -> PieceHd | None:
        w, h = piece["w"], piece["h"]
        hd = PieceHd(np.zeros((h * n, w * n, 4), dtype=np.uint8), np.zeros((h * n, w * n), dtype=bool))
        # Larger replacements first, so that a smaller, more specific one ends on top.
        for m, (ox, oy, ow, oh) in sorted(matches, key=lambda p: -p[0].replacement.w * p[0].replacement.h):
            r = m.replacement
            pixels = self.pixels(r)
            if pixels is None:
                continue
            s = scale_of(r, pixels)
            rx, ry, _, _ = m.texel_rect()
            crop = pixels[(oy - ry) * s:(oy - ry + oh) * s, (ox - rx) * s:(ox - rx + ow) * s]
            crop = resized(crop, ow * n, oh * n)
            px, py = (ox - piece["tx"]) * n, (oy - piece["ty"]) * n
            hd.pixels[py:py + oh * n, px:px + ow * n] = crop
            hd.covered[py:py + oh * n, px:px + ow * n] = True
            hd.used.add(r.path)
        return hd if hd.used else None

    def picture(self, rel: str) -> tuple[np.ndarray, int] | None:
        """The picture at `rel` repainted with the replacements over its pieces, or None."""
        if rel in self._pictures:
            return self._pictures[rel]
        result = self._repaint(rel)
        if rel in self._bases:
            self._pictures[rel] = result      # kept for the pictures derived from it only: HD atlases are large
        return result

    def _repaint(self, rel: str) -> tuple[np.ndarray, int] | None:
        entry = self.sources.pictures.get(rel, {})
        derived = entry.get("derived")
        if derived is not None:
            base = self.picture(derived["from"])
            if base is None:
                return None
            return apply_post(derived["post"], base[0], base[1]), base[1]
        pieces = entry.get("pieces", [])
        if not pieces:
            return None
        matches = [self.piece_matches(piece) for piece in pieces]
        n = self.picture_scale(matches)
        with Image.open(self.imported / rel) as image:
            original = image.convert("RGBA")
        canvas = np.array(original.resize((original.width * n, original.height * n), Image.LANCZOS))
        changed = False
        for piece, piece_matches in zip(pieces, matches):
            hd = self.piece_hd(piece, piece_matches, n)
            if hd is None:
                continue
            changed = True
            self.used |= hd.used
            a, b, c, d = piece.get("transform", (1, 0, 0, 1))
            dw, dh = (piece["w"], piece["h"]) if b == 0 else (piece["h"], piece["w"])
            cols, rows = np.meshgrid(np.arange(dw * n), np.arange(dh * n))
            ou = piece["w"] * n - 1 if a < 0 or b < 0 else 0
            ov = piece["h"] * n - 1 if c < 0 or d < 0 else 0
            su, sv = ou + a * cols + b * rows, ov + c * cols + d * rows
            x, y = piece["x"] * n, piece["y"] * n
            region = canvas[y:y + dh * n, x:x + dw * n]
            covered = hd.covered[sv, su]
            region[covered] = hd.pixels[sv, su][covered]
            pad = piece.get("pad", 0) * n
            if pad:
                _repeat_edges(canvas, x, y, dw * n, dh * n, pad)
        return (canvas, n) if changed else None


def _repeat_edges(canvas: np.ndarray, x: int, y: int, w: int, h: int, pad: int) -> None:
    """Fills the gutter around a region with its edge texels (atlas.py's gutter, at scale)."""
    region = canvas[y:y + h, x:x + w]
    padded = np.pad(region, ((pad, pad), (pad, pad), (0, 0)), mode="edge")
    x0, y0 = max(x - pad, 0), max(y - pad, 0)
    x1, y1 = min(x + w + pad, canvas.shape[1]), min(y + h + pad, canvas.shape[0])
    canvas[y0:y1, x0:x1] = padded[y0 - (y - pad):y1 - (y - pad), x0 - (x - pad):x1 - (x - pad)]


def apply_post(post: str, pixels: np.ndarray, n: int) -> np.ndarray:
    if post == "smooth_seams":
        import stage
        return stage.smooth_seams(pixels, stage.TILE_TEXELS * n, stage.SEAM_BAND * n)
    raise ValueError(f"unknown picture filter {post}")


def vram_check(words: np.ndarray, page_x: int, page_y: int, r: Replacement) -> str:
    """SHA-256 of the VRAM words a replacement replaces (remake/content/texture_packs.gd)."""
    return hashlib.sha256(np.ascontiguousarray(r.region(words, page_x, page_y)).astype("<u2").tobytes()).hexdigest()


def cluts(words: np.ndarray, sizes: dict[int, set[int]], depth: int) -> dict[int, list[np.ndarray]]:
    """The CLUTs (x a multiple of 16; 16 or 256 colours) whose first n colours hash to one of
    `sizes[n]`, by that hash; each content once."""
    found: dict[int, dict[bytes, np.ndarray]] = defaultdict(dict)
    count = 1 << depth
    for cy in np.flatnonzero(words.any(axis=1)):
        for cx in range(0, VRAM_W, 16):
            clut = words[cy, cx:cx + count]
            for size, wanted in sizes.items():
                digest = palette_hash(clut, size)
                if digest in wanted:
                    found[digest][clut.tobytes()] = clut.copy()
    return {digest: list(by_content.values()) for digest, by_content in found.items()}


def runtime_entries(importer: Importer, out: Path) -> tuple[list[dict], set[Path]]:
    """The replacements found in the screens' run-time VRAM states, copied to `vram/`: each with
    its page, rectangle, the CLUT it is drawn through and the SHA-256 of its VRAM words."""
    entries: dict[tuple, dict] = {}
    used = set()
    for state in importer.sources.runtime:
        s = state["snapshot"]
        words = importer.sources.snapshots[s]
        for depth in (4, 8):
            matches = [m for page_y in range(0, VRAM_H, PAGE_H) for page_x in range(0, VRAM_W, PAGE_W)
                       for m in importer.matcher.in_page(words, s, page_x, page_y, depth)]
            sizes: dict[int, set[int]] = defaultdict(set)
            for m in matches:
                sizes[m.replacement.palette_size].add(m.replacement.palette_hash)
            found = cluts(words, sizes, depth)
            for m in matches:
                r = m.replacement
                for clut in found.get(r.palette_hash, []):
                    if not importer.colours_match(words, s, m, clut, clut.tobytes()):
                        continue
                    check = vram_check(words, m.page_x, m.page_y, r)
                    key = (m.page_x, m.page_y, r.depth, r.x, r.y, r.w, r.h, clut.tobytes(), check)
                    if key in entries:
                        continue
                    pixels = importer.pixels(r)
                    file = f"{VRAM_DIR}/{r.path.stem}.png"
                    target = out / file
                    if not target.exists():
                        target.parent.mkdir(parents=True, exist_ok=True)
                        Image.fromarray(pixels, "RGBA").save(target, compress_level=PNG_LEVEL)
                    used.add(r.path)
                    entries[key] = {"page": [m.page_x, m.page_y], "depth": r.depth, "rect": [r.x, r.y, r.w, r.h],
                                    "palette": [int(c) for c in clut], "scale": scale_of(r, pixels), "file": file,
                                    "check": check}
    return sorted(entries.values(), key=lambda e: (e["page"], e["depth"], e["rect"], e["palette"])), used


def output_problem(pack: Path, out: Path) -> str | None:
    """Why `out` may not be (re)written as the converted pack, or None. It is replaced as a whole,
    so it must be new, empty or an earlier import (its report), and apart from the source pack."""
    source, target = pack.resolve(), out.resolve()
    if target == source or target in source.parents or source in target.parents:
        return f"{out} and the DuckStation pack {pack} overlap"
    if target.exists():
        if not target.is_dir():
            return f"{out} is not a folder"
        if any(target.iterdir()) and not (target / REPORT).is_file():
            return f"{out} is not empty and not an earlier import (no {REPORT}); give a new folder"
    return None


def import_pack(pack: Path, out: Path, sources, imported: Path, index: dict[str, str], scale: int | None) -> int:
    problem = output_problem(pack, out)
    if problem is not None:
        log.error("%s", problem)
        return 1
    replacements, skipped = parse_pack(pack)
    log.info("%s: %d page replacements (%d other files skipped)", pack, len(replacements), len(skipped))
    # The pack is built beside `out` and replaces it only when complete: a failed import (a missing
    # module, an undecodable picture) keeps the earlier pack.
    staging = out.with_name(f".{out.name}.new")
    shutil.rmtree(staging, ignore_errors=True)
    staging.mkdir(parents=True)
    try:
        build_pack(pack, staging, out.name, replacements, skipped, sources, imported, index, scale)
        retired = out.with_name(f".{out.name}.old")
        shutil.rmtree(retired, ignore_errors=True)
        if out.exists():
            out.rename(retired)
        staging.rename(out)
        shutil.rmtree(retired, ignore_errors=True)
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise
    return 0


def build_pack(pack: Path, out: Path, name: str, replacements, skipped, sources, imported: Path,
               index: dict[str, str], scale: int | None) -> None:
    """Writes the converted pack into the new folder `out`, which will be named `name`."""
    importer = Importer(sources, imported, replacements, scale)
    written = 0
    unindexed = [rel for rel, e in sources.pictures.items() if rel not in index and "pieces" in e]
    if unindexed:
        log.warning("%d pictures with VRAM sources are not in texture_index.json (%s, …): the installed "
                    "conversion is older than the converter; convert again (make convert) to replace them too",
                    len(unindexed), unindexed[0])
    for rel in sorted(sources.pictures):
        key = index.get(rel)
        if key is None or not (imported / rel).exists():
            continue
        result = importer.picture(rel)
        if result is None:
            continue
        Image.fromarray(result[0], "RGBA").save(out / f"{key}.png", compress_level=PNG_LEVEL)
        written += 1
        log.info("%s ×%d → %s.png", rel, result[1], key)
    vram, in_screens = runtime_entries(importer, out)
    used = importer.used | in_screens
    (out / VRAM_INDEX).write_text(json.dumps({"entries": vram}, indent=1) + "\n")
    (out / "pack.json").write_text(json.dumps({"name": name, "author": "", "version": 1,
                                               "source": f"DuckStation texture replacements: {pack.name}"}, indent=1) + "\n")
    unused = sorted(r.path.name for r in replacements if r.path not in used)
    (out / REPORT).write_text(f"{len(replacements)} replacements, {len(replacements) - len(unused)} used, "
                              f"{written} pictures, {len(vram)} screen sprites\n"
                              f"not drawn by the remake ({len(unused)}):\n" + "".join(f"{u}\n" for u in unused)
                              + f"not page replacements ({len(skipped)}):\n" + "".join(f"{p.name}\n" for p in skipped))
    log.info("%d pictures (%d replacements), %d screen sprites (%d); %d of %d replacements used (%s)", written,
             len(importer.used), len(vram), len(in_screens), len(replacements) - len(unused), len(replacements), out.with_name(name) / REPORT)
