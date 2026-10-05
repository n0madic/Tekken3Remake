"""Arcade stages (Namco System 12, MAME set `tekken3`) → `stages/<letter>/arcade/`.

The arcade game models its stage scenery in depth where the PlayStation port has flat panoramas.
The remake can draw the arcade's scene, sky and floor instead of the PlayStation's
(docs/research/arcade/). The input is the user's MAME ROM set, given with `--arcade`;
only World ver. E1 (`tekken3`) is supported, since the sky and floor tables are read from its
decompressed program by address.

Output per stage 0–12 (`stages/<letter>/arcade/`):

- `scene.bin`: SCENE_FLOATS little-endian floats per triangle corner: `x, y, z` (scene units,
  y down), `u, v` and the window `wx, wy, ww, wh` in atlas texels (with `ww = 0` the corner's
  `u, v` is its atlas texel; otherwise `u, v` are page texels that repeat inside the window at
  `wx, wy`, a GPU texture window), `r, g, b` (the factor the texel is multiplied by, linear
  light: a textured packet's colour with 1.0 = 0x80, an untextured one's own colour, which its
  white texel shows; corner_colour);
- `scene.png`: the atlas of the used texture regions;
- `scene_frames.png` (stages 6 and 12): the frames of the animated atlas rectangle, one below
  the other;
- `prop_<k>.bin` (stages 3 and 11): the animated props drawn with the scene, in scene.bin's
  format, about their own origin (their textures in scene.png);
- `sky.png`: the sky panorama as one strip, columns for a full turn plus one screen;
- `floor.png`, `floor_smooth.png`: the 10 × 10 floor pattern from the quarter-tile entries (128
  texels per tile), drawn on every tile (the arcade splits at most 11 tiles a frame into them and
  draws the others from the tile entries at half the resolution; the remake does not);
- `arcade.json`: placement, sky and floor parameters.

`stages/arcade_floor_fade.json` holds the arcade floor's shading table, `stages/arcade_sine.json`
the program's sine table (the props' orbits).
"""

from __future__ import annotations

import math
import struct
import zipfile
import zlib
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

import atlas
import stage
from common import Output, log
from vram import Vram, png_bytes, rgba, tim_sequence

SET_NAME = "tekken3"
# (file, CRC-32) pairs of the ROM chips read, from MAME's set definition (namcos12.cpp); every
# pair is one 16-bit bus, the first chip holding the even bytes.
PROGRAM_CHIPS = (("tet2vere1.2e", 0x7DED5461), ("tet2vere1.2j", 0x25C96E1E))
BANK_CHIPS = (
    (("tet1rom0l.6", 0x2886BB32), ("tet1rom0u.9", 0xC5705B92)),
    (("tet1rom1l.7", 0x0397D283), ("tet1rom1u.10", 0x502BA5CD)),
    (("tet1rom2l.8", 0xE03B1C24), ("tet1rom2u.11", 0x75EB2AB3)),
)
BANK_BYTES = 0x800000          # each banked pair
PRG_FILES = 0x2000000          # file-table addresses from here are program ROM offsets + this

# The program (arcade/README.md#program-compression-and-boot).
PROGRAM_SOURCE = 0x28000
PROGRAM_BASE = 0x80010000
CATEGORY_TABLE = 0x801FF738    # 44 × {u32 directory list, u32 directories}
CATEGORIES = 44
STAGE_CATEGORY = 0x8017C320    # s32 per stage
STAGES = 13
SKY_RECORDS = 0x801749A0       # 20 bytes per stage (stages.md#sky)
SKY_RECORD = 20
SKY_PITCH = 0x80174AA4         # s16 per stage
SKY_COLOURS = 0x80174AC0       # 3 × u32 per stage: tile tint, upper fill, lower fill
FLOOR_DESCRIPTORS = 0x801748EC  # {ptr, u32} per stage
FLOOR_DESCRIPTOR_BYTES = 0xFA8 + 2
FLOOR_FADE_TABLE = 0x80174B5C
FLOOR_FADE_ENTRIES = 1024
FADE_FILE = "stages/arcade_floor_fade.json"
SCENE_HEIGHT = 0x8017C454      # s32 per stage

# FUN_801E2090 / FUN_801E21B0: categories whose file 0 (a TIM block) these stages upload too.
EXTRA_TIMS = {3: 41, 6: 39, 11: 40, 12: 39}
# FUN_801E2258: stages 3 and 11 load files 1… of the same category as one-object TMDs, the props
# FUN_801E2A68 draws with the scene (stage 11 loads a third, its tail rotor, and never draws it).
PROPS = {3: (41, 4, "carousel"), 11: (40, 2, "helicopter")}
SINE = 0x80175944              # 4096 s16
SINE_FILE = "stages/arcade_sine.json"
# FUN_801E2090 / FUN_801E2114: stages 6 and 12 copy a 16 × 64-word VRAM block (a 64 × 64 4-bit
# picture) from the category 39 TIMs to (16, y) every fourth frame, cycling through 16 sources.
TEXTURE_CYCLE = 0x8020456C     # 16 × {u16 x, u16, u16 y, u16}
TEXTURE_CYCLE_FRAMES = 16
TEXTURE_CYCLE_PERIOD = 4
TEXTURE_CYCLE_TARGET = {6: (16, 0x380), 12: (16, 0x3C0)}
TEXTURE_CYCLE_SIZE = (16, 64)  # VRAM words
SCENE_OBJECTS = 256
SCENE_GRID = 16
SCENE_SCALE = 10               # FUN_801D9118: one tenth of the camera's displacement
SCENE_Y_SCALE = 0.95           # … with the scene's row 1 scaled by 95/100
SCENE_Y_SCALE_STAGE3 = 0.95 * 0.7
# FUN_801D73E4 leaves these objects out of the scene.
SKIPPED_OBJECTS = {0: (0xC6, 0xC7, 0xD8), 5: (0x53, 0x63, 0x6B)}
SCENE_FLOATS = 12
QUAD_TRIANGLES = ((0, 1, 2), (1, 3, 2))
UNTEXTURED = "untextured"
LIT_COLOUR = (128, 128, 128)   # lit packets are built with 0x80 and never shaded (FUN_801D82B8)
TEXTURE_UNIT = 128             # a textured packet's colour modulates its texels: 0x80 keeps them
DISPLAY_MAX = 255              # an untextured packet's colour is the displayed colour itself

TILE = 64
SKY_SCREEN_COLUMNS = 9         # FUN_801A7688 draws nine tiles across a 512-pixel row
SKY_SCREEN_WIDTH = 512
SKY_TURN = 4096
SKY_FILL_LOWER = ord("d")
SKY_FILL_TINT = ord("t")
SKY_TILE = ord("1")
SKY_CLAMP_TOP_STAGES = (0, 5, 11)   # y ≤ 0
SKY_CLAMP_BOTTOM = {11: -192}        # y ≥ −192 (480-line pixels)
SKY_GRADIENT_STAGE = 3               # a POLY_G4 instead of tiles
SKY_GRADIENT = ((0, 20, 102), (0, 0, 0))
SKY_FILL_STAGE = 6                   # one full-screen tile
SKY_FLIPPED_ROWS = {5: 3}            # drawn as POLY_FT4 with v running upwards: upside down

FLOOR_TILE_UNITS = 2500
FLOOR_TILES = 10
FLOOR_QUARTERS = 0x324         # 10 × 10 × 4 entries, row stride 0x140
FLOOR_QUARTER_ROW = 0x140
FLOOR_KIND = 0xFA4
FLOOR_SHADE = 0xFA6
FLOOR_EXTRA = 0xFA8
FLOOR_FADE = 10000
FLOOR_ORIENTATION_SET = 0xC0000000
FLOOR_ORIENTATION_ORDER = 0x06000000


class ArcadeError(Exception):
    pass


def interleave(even: bytes, odd: bytes) -> bytes:
    out = bytearray(len(even) * 2)
    out[0::2] = even
    out[1::2] = odd
    return bytes(out)


def decompress(src: bytes, pos: int = 0) -> tuple[bytes, int]:
    """The BIOS's LZ (FUN_1FC205E4): flag bytes read least-significant bit first while the value
    left is ≥ 2 (its top set bit is a sentinel), 1 = literal, 0 = a two-byte reference
    (length `a >> 3` or 32, distance `(a & 7) << 8 | b` or 2048); a flag byte of 0 ends the
    stream. Returns the output and the end of the stream."""
    out = bytearray()
    while True:
        if pos >= len(src):
            raise ArcadeError("compressed stream runs past its source")
        flags = src[pos]
        pos += 1
        if flags == 0:
            return bytes(out), pos
        while flags >= 2:
            if flags & 1:
                out.append(src[pos])
                pos += 1
            else:
                word = src[pos] << 8 | src[pos + 1]
                pos += 2
                distance = (word & 0x7FF) or 0x800
                length = ((word >> 11) & 0x1F) or 0x20
                if distance > len(out):
                    raise ArcadeError("compressed reference before the start of the output")
                for _ in range(length):
                    out.append(out[-distance])
            flags >>= 1


def tims_of(data: bytes) -> list[bytes]:
    """The TIMs of a TIM block: back to back up to the first word that is not a TIM id, as
    FUN_801DB408 uploads them (blocks end with zero bytes, one with the text "end")."""
    tims, _ = tim_sequence(data)
    if not tims:
        raise ArcadeError("not a TIM block")
    return tims


@dataclass
class ArcadeSet:
    program_rom: bytes
    banked: bytes
    program: bytes
    _categories: dict[int, list[bytes]] = field(default_factory=dict, repr=False, compare=False)
    _tables: dict[tuple[str, int], tuple] = field(default_factory=dict, repr=False, compare=False)

    def read(self, addr: int, size: int) -> bytes:
        """`size` bytes at a file-table address (a bank offset, or PRG_FILES + a program ROM offset)."""
        if addr >= PRG_FILES:
            data = self.program_rom[addr - PRG_FILES:addr - PRG_FILES + size]
        else:
            data = self.banked[addr:addr + size]
        if len(data) != size:
            raise ArcadeError(f"file {addr:#x}+{size:#x} lies outside the ROMs")
        return data

    def prog(self, addr: int, size: int) -> bytes:
        off = addr - PROGRAM_BASE
        if off < 0 or off + size > len(self.program):
            raise ArcadeError(f"program address {addr:#x} outside the program")
        return self.program[off:off + size]

    def prog_values(self, fmt: str, addr: int) -> tuple:
        return struct.unpack(fmt, self.prog(addr, struct.calcsize(fmt)))

    def prog_table(self, fmt: str, addr: int) -> tuple:
        """`prog_values` read once (tables used for every model)."""
        if (fmt, addr) not in self._tables:
            self._tables[(fmt, addr)] = self.prog_values(fmt, addr)
        return self._tables[(fmt, addr)]

    def category(self, number: int) -> list[bytes]:
        """The files of a category, in order: its archive directories (`u32 count`, then
        `(offset, size)` pairs from the directory) one after the other (FUN_801BB6C0). Read once."""
        if number not in self._categories:
            self._categories[number] = self._read_category(number)
        return self._categories[number]

    def _read_category(self, number: int) -> list[bytes]:
        lists, count = self.prog_values("<II", CATEGORY_TABLE + 8 * number)
        files = []
        for directory in self.prog_values(f"<{count}I", lists):
            entries = struct.unpack("<I", self.read(directory, 4))[0]
            for k in range(entries):
                off, size = struct.unpack("<II", self.read(directory + 4 + 8 * k, 8))
                files.append(self.read(directory + off, size))
        return files


def _chip(archive: zipfile.ZipFile, name: str, crc: int) -> bytes:
    for info in archive.infolist():
        if Path(info.filename).name == name and info.CRC == crc:
            data = archive.read(info)
            if zlib.crc32(data) != crc:
                raise ArcadeError(f"{name}: damaged in the archive")
            return data
    raise ArcadeError(f"{name} (CRC {crc:08x}) is missing: give MAME's '{SET_NAME}' set, World ver. E1")


def open_set(path: Path) -> ArcadeSet:
    try:
        with zipfile.ZipFile(path) as archive:
            program_rom = interleave(*(_chip(archive, n, c) for n, c in PROGRAM_CHIPS))
            banked = b"".join(interleave(*(_chip(archive, n, c) for n, c in pair)) for pair in BANK_CHIPS)
    except (OSError, zipfile.BadZipFile) as e:
        raise ArcadeError(f"{path}: {e}") from e
    program, _ = decompress(program_rom, PROGRAM_SOURCE)
    return ArcadeSet(program_rom, banked, program)


# ---- scene TMD (stages.md#scene-tmd) ----

@dataclass
class Packet:
    verts: list[int]
    uvs: list[tuple[int, int]] | None
    cba: int
    tsb: int
    colours: list[tuple[int, int, int]]
    window: tuple[int, int, int, int] | None    # x, y, w, h (page texels)


def parse_packet(data: bytes, pos: int) -> tuple[Packet, int]:
    """A standard TMD primitive at `pos` (header olen, ilen, flag, mode); returns it and the next."""
    _, ilen, flag, mode = data[pos:pos + 4]
    body = data[pos + 4:pos + 4 + 4 * ilen]
    if mode & 0xE0 not in (0x20, 0xA0):
        raise ArcadeError(f"scene packet mode {mode:#x} is not a polygon")
    count = 4 if mode & 0x08 else 3
    textured, gouraud, lit = bool(mode & 0x04), bool(mode & 0x10), not flag & 1
    p = 0
    uvs = None
    cba = tsb = 0
    window = None
    if textured:
        uvs = [(body[4 * k], body[4 * k + 1]) for k in range(count)]
        cba = struct.unpack_from("<H", body, 2)[0]
        tsb = struct.unpack_from("<H", body, 6)[0]
        if mode & 0x80:
            if count != 4:
                raise ArcadeError(f"texture window on a triangle (mode {mode:#x})")
            window = (body[14], body[15], body[10], body[11])   # x, y from uv3's pad, w, h from uv2's
        p = 4 * count
    if lit:
        # Textured ones are built with 0x80; untextured ones keep the packet's colour (FUN_801E2370).
        colours = [LIT_COLOUR if textured else tuple(body[p:p + 3])]
        if not textured:
            p += 4
        halves = struct.unpack_from(f"<{2 * count if gouraud else count + 1}H", body, p)
        verts = list(halves[1::2]) if gouraud else list(halves[1:])
    else:
        colours = [tuple(body[p + 4 * k:p + 4 * k + 3]) for k in range(count if gouraud else 1)]
        p += 4 * len(colours)
        verts = list(struct.unpack_from(f"<{count}H", body, p))
    return Packet(verts, uvs, cba, tsb, colours, window), pos + 4 + 4 * ilen


def scene_corners(tmd: bytes, stage_number: int) -> tuple[int, list[tuple]]:
    """The scene's triangle corners: (key, (x, y, z), u, v, (r, g, b)), key `cba_tsb[_window]`."""
    ident, cell, count = struct.unpack_from("<III", tmd, 0)
    if ident != 0x41 or count != SCENE_OBJECTS:
        raise ArcadeError(f"stage {stage_number}: not a scene TMD")
    skipped = SKIPPED_OBJECTS.get(stage_number, ())
    corners = []
    for index in range(SCENE_OBJECTS):
        if index not in skipped:
            corners += object_corners(tmd, index, f"stage {stage_number} object {index}")
    return 10 * cell, corners


def prop_corners(tmd: bytes, name: str) -> list[tuple]:
    """A prop: a TMD of one object."""
    if struct.unpack_from("<I", tmd, 0)[0] != 0x41 or struct.unpack_from("<I", tmd, 8)[0] != 1:
        raise ArcadeError(f"{name}: not a one-object TMD")
    return object_corners(tmd, 0, name)


def corner_colour(colour: tuple[int, ...], textured: bool) -> tuple[float, ...]:
    """The factor the scene shader multiplies its texel by (linear light; untextured corners
    sample white): a textured packet's colour scales the texel (0x80 = 1), an untextured one is
    the colour the GPU draws, an sRGB-like display value."""
    if textured:
        return tuple(c / TEXTURE_UNIT for c in colour)
    return tuple(_linear(c / DISPLAY_MAX) for c in colour)


def _linear(value: float) -> float:
    """sRGB transfer function, display value → linear light."""
    return value / 12.92 if value <= 0.04045 else ((value + 0.055) / 1.055) ** 2.4


def object_corners(tmd: bytes, index: int, name: str) -> list[tuple]:
    """Object `index`'s triangle corners (scene_corners's tuples)."""
    vert_top, vert_count, _, _, prim_top, prim_count, _ = struct.unpack_from("<6Ii", tmd, 12 + 28 * index)
    corners: list[tuple] = []
    if prim_count > 0:
        verts = [struct.unpack_from("<3h", tmd, 12 + vert_top + 8 * k) for k in range(vert_count)]
        pos = 12 + prim_top
        for _ in range(prim_count):
            packet, pos = parse_packet(tmd, pos)
            if any(v >= len(verts) for v in packet.verts):
                raise ArcadeError(f"{name}: vertex index out of range")
            if packet.uvs is None:
                key = UNTEXTURED
            elif packet.window is None:
                key = f"{packet.cba:04x}_{packet.tsb:04x}"
            else:
                key = f"{packet.cba:04x}_{packet.tsb:04x}_" + "_".join(str(v) for v in packet.window)
            corner = []
            for k, v in enumerate(packet.verts):
                u, w = packet.uvs[k] if packet.uvs else (0, 0)
                colour = packet.colours[k] if len(packet.colours) > 1 else packet.colours[0]
                corner.append((key, verts[v], u, w, corner_colour(colour, packet.uvs is not None)))
            for tri in (QUAD_TRIANGLES if len(corner) == 4 else ((0, 1, 2),)):
                corners.extend(corner[i] for i in tri)
    return corners


def tpage_xy(tsb: int) -> tuple[int, int]:
    """A System 12 texture page: bit 11 adds 512 rows."""
    return 64 * (tsb & 0x0F), 256 * ((tsb >> 4) & 1) + 512 * ((tsb >> 11) & 1)


def clut_xy(cba: int) -> tuple[int, int]:
    """A System 12 CLUT id: a 10-bit row."""
    return 16 * (cba & 0x3F), (cba >> 6) & 0x3FF


def depth_bits(tsb: int) -> int:
    return (4, 8, 16, 16)[(tsb >> 7) & 3]


def page_picture(vram: Vram, cba: int, tsb: int) -> np.ndarray:
    page_x, page_y = tpage_xy(tsb)
    depth = depth_bits(tsb)
    if depth == 16:
        return rgba(vram.words[page_y:page_y + 256, page_x:page_x + 256])
    return vram.page_rgba(page_x, page_y, depth, *clut_xy(cba))


def stage_vram(files: list[bytes], extra: list[bytes]) -> Vram:
    """The stage's TIM blocks (files 1…, then `extra`) uploaded in order; compressed blocks are
    unpacked."""
    vram = Vram(1024)
    for block in files[1:] + extra:
        if block[:1] != b"\x10":
            block, _ = decompress(block)
        for tim in tims_of(block):
            vram.upload_tim(tim)
    return vram


def scene_mesh(vram: Vram, *meshes: list[tuple]) -> tuple[atlas.Atlas, list[bytes]]:
    """One atlas for the corners of every mesh, and each mesh's floats."""
    used: dict[str, list[tuple[int, int]]] = {}
    for corners in meshes:
        for key, _, u, v, _ in corners:
            used.setdefault(key, []).append((u, v))
    pages = {}
    windows = {}
    for key in used:
        if key == UNTEXTURED:
            pages[key] = np.full((256, 256, 4), 255, dtype=np.uint8)
            continue
        parts = key.split("_")
        cba, tsb = int(parts[0], 16), int(parts[1], 16)
        pages[key] = page_picture(vram, cba, tsb)
        if len(parts) > 2:
            x, y, w, h = (int(p) for p in parts[2:])
            windows[key] = (x, y, w, h)
            used[key] = [(x, y), (x + w - 1, y + h - 1)]
    packed = atlas.build(pages, used, frozenset(windows))
    out = []
    for corners in meshes:
        floats: list[float] = []
        for key, position, u, v, colour in corners:
            floats.extend(position)
            region = packed.regions[key]
            if key in windows:
                x, y, w, h = windows[key]
                floats.extend((u, v, region.x, region.y, w, h))
            else:
                floats.extend((region.x + u - region.u0 + 0.5, region.y + v - region.v0 + 0.5, 0, 0, 0, 0))
            floats.extend(colour)
        out.append(struct.pack(f"<{len(floats)}f", *floats))
    return packed, out


def scene_animation(arc: ArcadeSet, vram: Vram, packed: atlas.Atlas, number: int) -> tuple[dict, np.ndarray]:
    """The atlas rectangle that shows FUN_801E2114's target block and its frames, one below the
    other: frame k is the picture after the cycle's k-th copy (source k)."""
    tx, ty = TEXTURE_CYCLE_TARGET[number]
    tw, th = TEXTURE_CYCLE_SIZE
    shown = []
    for key, r in packed.regions.items():
        if key == UNTEXTURED:
            continue
        parts = key.split("_")
        cba, tsb = int(parts[0], 16), int(parts[1], 16)
        page_x, page_y = tpage_xy(tsb)
        per_word = 16 // depth_bits(tsb)
        h, w = r.pixels.shape[:2]
        u0, u1 = max(r.u0, (tx - page_x) * per_word), min(r.u0 + w, (tx + tw - page_x) * per_word)
        v0, v1 = max(r.v0, ty - page_y), min(r.v0 + h, ty + th - page_y)
        if u0 < u1 and v0 < v1:
            if len(parts) > 2:
                raise ArcadeError(f"stage {number}: the animated block is seen through a texture window")
            shown.append((cba, tsb, r, u0, v0, u1, v1))
    if len(shown) != 1:
        raise ArcadeError(f"stage {number}: {len(shown)} scene textures show the animated block, not one")
    cba, tsb, r, u0, v0, u1, v1 = shown[0]
    frames = []
    for k in range(TEXTURE_CYCLE_FRAMES):
        sx, _, sy, _ = arc.prog_values("<4H", TEXTURE_CYCLE + 8 * k)
        copied = vram.copy()
        copied.move_image(sx, sy, tw, th, tx, ty)
        frames.append(page_picture(copied, cba, tsb)[v0:v1, u0:u1])
    rect = [r.x + u0 - r.u0, r.y + v0 - r.v0, u1 - u0, v1 - v0]
    return ({"rect": rect, "frames": TEXTURE_CYCLE_FRAMES, "period": TEXTURE_CYCLE_PERIOD,
             "texture": "scene_frames.png"}, np.concatenate(frames))


# ---- sky (stages.md#sky) ----

def colour_word(word: int) -> list[int] | None:
    """An RGB colour word whose top byte enables it."""
    return [word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF] if word >> 24 else None


def sky_cell(cell: int, retouch: bool = True) -> int:
    """What a cell of the sky's map is drawn as. The arcade skips the cells below `'1'` (the maps use
    `'0'`), which leaves the screen's clear colour (`inferred`: black) wherever the scene does not
    cover them (the camera reaches them when the backdrop's turn swings the sky round). With
    `retouch` they are drawn as the art meant: the cell's own tile, the picture repeating round the
    horizon; without it as the arcade draws them (tools/research/verify_arcade_sky.py)."""
    return SKY_TILE if retouch and cell < SKY_TILE else cell


def sky(arc: ArcadeSet, vram: Vram, number: int, retouch: bool = True) -> tuple[dict, np.ndarray | None]:
    cols, rows, tex, cluts, cell_map, offset, span = arc.prog_values("<hhIIIhH", SKY_RECORDS + SKY_RECORD * number)
    tint, upper, lower = arc.prog_values("<3I", SKY_COLOURS + 12 * number)
    step = span * SKY_TURN // 360              # yaw units per 512 pixels × 512 / 360 … (FUN_801A7688)
    map_width = (0x2D000 // span) >> 6
    turn_pixels = (SKY_TURN << 9) / step       # pixels in a full turn
    info = {
        "kind": "gradient" if number == SKY_GRADIENT_STAGE else "fill" if number == SKY_FILL_STAGE else "tiles",
        "rows": rows,
        "columns": cols,
        "map_width": map_width,
        "span": span,
        "step": step,
        "turn_pixels": turn_pixels,
        "offset": offset,
        "pitch_scale": arc.prog_values("<h", SKY_PITCH + 2 * number)[0],
        "clamp_top": number in SKY_CLAMP_TOP_STAGES,
        "clamp_bottom": SKY_CLAMP_BOTTOM.get(number),
        "tint": [tint & 0xFF, (tint >> 8) & 0xFF, (tint >> 16) & 0xFF],   # 't' cells use it unconditionally
        "upper_fill": colour_word(upper),
        "lower_fill": colour_word(lower),
        "lower_cells": [lower & 0xFF, (lower >> 8) & 0xFF, (lower >> 16) & 0xFF],   # 'd' cells: always
        "gradient": [list(c) for c in SKY_GRADIENT] if number == SKY_GRADIENT_STAGE else None,
        "screen": [SKY_SCREEN_WIDTH, 480],
    }
    if info["kind"] != "tiles":
        return info, None
    words = arc.prog_values(f"<{rows * cols}H", tex)
    clut_ids = arc.prog_values(f"<{rows * cols}H", cluts)
    cells = arc.prog(cell_map, rows * map_width)
    columns = math.ceil(turn_pixels / TILE) + SKY_SCREEN_COLUMNS
    picture = np.zeros((rows * TILE, columns * TILE, 4), dtype=np.uint8)
    for row in range(rows):
        for column in range(columns):
            cell = sky_cell(cells[row * map_width + column % map_width], retouch)
            target = picture[row * TILE:(row + 1) * TILE, column * TILE:(column + 1) * TILE]
            if cell == SKY_TILE:
                k = row * cols + column % cols
                w = words[k]
                tsb = (w >> 8) & 0xF | ((w >> 12) & 1) << 4 | ((w >> 13) & 1) << 11
                u, v = TILE * (w & 3), TILE * ((w >> 2) & 3)
                tile = page_picture(vram, clut_ids[k], tsb)[v:v + TILE, u:u + TILE]
                target[:] = tile[::-1] if SKY_FLIPPED_ROWS.get(number) == row else tile
            elif cell == SKY_FILL_LOWER:
                target[..., :3], target[..., 3] = info["lower_cells"], 255
            elif cell == SKY_FILL_TINT:
                target[..., :3], target[..., 3] = info["tint"], 255
    info["texture"] = "sky.png"
    return info, picture


# ---- floor (stages.md#floor) ----

def _floor_tile(vram: Vram, w0: int, w1: int, entry: int) -> np.ndarray:
    """A 64 × 64 floor texture (word 0 `u | v << 8 | tpage << 16`, word 1 the CBA) as drawn with
    `entry`'s orientation bits."""
    page_x, page_y = tpage_xy((w0 >> 16) & stage.TPAGE_MASK)
    u, v = w0 & 0xFF, (w0 >> 8) & 0xFF
    indices = vram.page_indices(page_x, page_y, 4)[v:v + TILE, u:u + TILE]
    return stage.oriented_tile(rgba(vram.clut(*clut_xy(w1 >> 16), 16)[indices]), entry)


def floor(arc: ArcadeSet, vram: Vram, number: int) -> tuple[dict, np.ndarray]:
    """The 10 × 10 pattern from the quarter-tile entries (128 texels per tile), which
    FUN_801A941C draws on the tiles it splits. Each quarter is drawn with the tile's corner set
    (bits 30–31 of the tile entry) and its own order bits (25–26), tile quadrants v0 top left,
    v1 top right, v2 bottom left, v3 bottom right."""
    pointer, _ = arc.prog_values("<II", FLOOR_DESCRIPTORS + 8 * number)
    descriptor = arc.prog(pointer, FLOOR_DESCRIPTOR_BYTES)
    if struct.unpack_from("<I", descriptor, 0)[0] != 0x80:
        raise ArcadeError(f"stage {number}: no floor descriptor")
    size = 2 * TILE
    fine = np.zeros((FLOOR_TILES * size, FLOOR_TILES * size, 4), dtype=np.uint8)
    for row in range(FLOOR_TILES):
        for col in range(FLOOR_TILES):
            w0 = struct.unpack_from("<I", descriptor, 4 + 8 * (FLOOR_TILES * row + col))[0]
            for quarter in range(4):
                q_row, q_col = divmod(quarter, 2)
                at = FLOOR_QUARTERS + FLOOR_QUARTER_ROW * row + 0xA0 * q_row + 0x10 * col + 8 * q_col
                q0, q1 = struct.unpack_from("<II", descriptor, at)
                entry = w0 & FLOOR_ORIENTATION_SET | q0 & FLOOR_ORIENTATION_ORDER
                y, x = row * size + q_row * TILE, col * size + q_col * TILE
                fine[y:y + TILE, x:x + TILE] = _floor_tile(vram, q0, q1, entry)
    kind, shade, extra = struct.unpack_from("<hhh", descriptor, FLOOR_KIND)
    return {"kind": kind, "shade": shade, "fade": FLOOR_FADE, "extra": extra,
            "tile_size": FLOOR_TILE_UNITS,
            "pattern": "floor.png", "pattern_smooth": "floor_smooth.png"}, fine


# ---- conversion ----

def convert_stage(arc: ArcadeSet, out: Output, number: int, letter: str) -> None:
    category = arc.prog_values("<i", STAGE_CATEGORY + 4 * number)[0]
    files = arc.category(category)
    extra = [arc.category(EXTRA_TIMS[number])[0]] if number in EXTRA_TIMS else []
    vram = stage_vram(files, extra)
    cell, corners = scene_corners(files[0], number)
    props = []
    if number in PROPS:
        prop_category, count, _ = PROPS[number]
        prop_files = arc.category(prop_category)
        props = [prop_corners(prop_files[1 + k], f"stage {number} prop {k}") for k in range(count)]
    packed, (mesh, *prop_meshes) = scene_mesh(vram, corners, *props)
    base = f"stages/{letter}/arcade"
    out.write(f"{base}/scene.bin", mesh)
    for k, prop in enumerate(prop_meshes):
        out.write(f"{base}/prop_{k}.bin", prop)
    out.write(f"{base}/scene.png", png_bytes(packed.pixels))
    animation = None
    if number in TEXTURE_CYCLE_TARGET:
        animation, frames = scene_animation(arc, vram, packed, number)
        out.write(f"{base}/{animation['texture']}", png_bytes(frames))
    sky_info, sky_picture = sky(arc, vram, number)
    if sky_picture is not None:
        out.write(f"{base}/sky.png", png_bytes(sky_picture))
    floor_info, fine = floor(arc, vram, number)
    out.write(f"{base}/{floor_info['pattern']}", png_bytes(fine))
    out.write(f"{base}/{floor_info['pattern_smooth']}", png_bytes(stage.smooth_seams(fine, TILE)))
    xs = [c[1][0] for c in corners]
    zs = [c[1][2] for c in corners]
    out.write_json(f"{base}/arcade.json", {
        "stage": number,
        "letter": letter,
        "category": category,
        "cell": cell,
        "scene_scale": SCENE_SCALE,
        "scene_height": arc.prog_values("<i", SCENE_HEIGHT + 4 * number)[0],
        "scene_y_scale": SCENE_Y_SCALE_STAGE3 if number == 3 else SCENE_Y_SCALE,
        "scene_texture": "scene.png",
        "scene_animation": animation,
        "props": {"kind": PROPS[number][2], "meshes": [f"prop_{k}.bin" for k in range(len(prop_meshes))]}
        if number in PROPS else None,
        "scene_vertices": len(corners),
        "scene_extent": [min(xs), max(xs), min(zs), max(zs)],
        "vertex_floats": SCENE_FLOATS,
        "sky": sky_info,
        "floor": floor_info,
    })


def open_or_none(path: Path) -> ArcadeSet | None:
    """The set at `path`, or None with a logged reason if it cannot be used."""
    try:
        return open_set(path)
    except ArcadeError as e:
        log.error("arcade: %s; the PlayStation's stages and models are kept", e)
        return None


def convert(arc: ArcadeSet, out: Output, letters: str) -> bool:
    """Converts stages 0–12 (`letters[n]` names stage n); False, with a logged reason, if the set
    cannot be used."""
    try:
        for number in range(STAGES):
            convert_stage(arc, out, number, letters[number])
        out.write_json(FADE_FILE,
                       {"table": list(arc.prog(FLOOR_FADE_TABLE, FLOOR_FADE_ENTRIES))})
        out.write_json(SINE_FILE, {"table": list(arc.prog_values("<4096h", SINE))})
    except (ArcadeError, struct.error, ValueError) as e:
        # Nothing partial is kept: the run's prune deletes what was written.
        out.files -= {rel for rel in out.files if "/arcade/" in rel or rel in (FADE_FILE, SINE_FILE)}
        log.error("arcade: %s; the stages keep their PlayStation backdrops", e)
        return False
    log.info("arcade: %d stage scenes", STAGES)
    return True
