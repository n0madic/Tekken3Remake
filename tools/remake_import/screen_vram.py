"""The M3 screens' pictures as the game's own VRAM contents (docs/remake-plan.md, M3).

The screens draw sprites by texture page, CLUT and texel coordinates, as the game does, from a
VRAM image the remake builds at run time (`remake/content/vram_image.gd`): the resident system
textures, then each screen's pictures uploaded in the game's order.

- `screens/vram_system.bin`: the 1024 × 512 VRAM words after the system textures (raw u16 LE);
- `screens/<screen>.tims`: a screen's TIMs in upload order (u32 count, then per TIM its u32
  length and bytes);
- `screens/portraits/<n>.png`: the character select's big portraits (126 × 252, 8-bit TIMs with
  their own CLUT), loaded one at a time by the game;
- `screens/vs_portraits/<n>.png`: the pre-fight VS screen's portraits (`face_b<n>.tiz`, BNS 14–35,
  126 × 252; other pictures than the select's);
- `screens/<screen>.tims` of the other screens' overlays: `result_ta` (time attack's picture,
  result.ovl FUN_800F10C8), `ranking_<n>` (ranking.ovl's picture n, FUN_8004CC04's member),
  `staff` (the staff roll's three TIMs, ending.ovl FUN_80112798) and `theater` (the Theater's
  62 pictures, ending.ovl state 19);
- `screens/makuma_<n>.tims`: the VS screen's backgrounds (`makuma00/01.tia`, BNS 12 and 13: 42
  compressed TIMs each, uploaded at their own rectangles).
"""

from __future__ import annotations

import struct

import numpy as np

from common import Disc, Output
import overlay_images
import sources
from inspect_compressed_tim import decompress_tim, tia_members
from vram import Vram, png_bytes, rgba

# The overlays whose tables and strings the screens' drawing reads (loaded at their slot).
RAM_OVERLAYS = ("title", "select", "ranking", "result", "ending", "arcade", "practice", "force", "volley")
# force.ovl's key icons (copper, silver, gold): 20 × 36 at VRAM (688, 320 + 36 · i), CLUT (128 + 16 · i, 486)
FORCE_KEYS = (0x800B1000, 0x800B11A8, 0x800B1350)
# title.ovl's archive uploaded on the title and the main menu (FUN_8004CD28 at sub-state 0), kept
# in VRAM for the fights: the pad buttons and direction arrows of the move lists and practice's
# key display (tpage 6, (384, 224)).
TITLE_BUTTONS = 0x800D4FB8
SELECT_ARCHIVE = 0x80118C48          # select.ovl: the screen's pictures (uploaded at sub-state 0)
SELECT_PORTRAITS = 0x800B974C        # select.ovl: the big portraits by attribute (22)
RESULT_TIME_ATTACK = 0x800B99B4      # result.ovl: time attack's 368 × 480 picture (6 members)
RESULT_FORCE = 0x800D8A20            # result.ovl: Tekken Force's result picture (6 members, FUN_800F110C)
RANKING_PICTURES = 0x800B96B4        # ranking.ovl: one member uploaded (0x800984DC)
STAFF_TIMS = (0x8011E5FC, 0x8011F7F4, 0x801215BC)   # ending.ovl: the staff roll's plain TIMs
THEATER_PICTURES = 0x80123C64        # ending.ovl: the Theater's pictures (62 members)
# ending.ovl's plain TIMs of the Theater (stored at (0, 0)) and where FUN_8010FB24's table
# (0x800BA374) puts them: disc 3's logo in two parts and the sound page's picture.
THEATER_TIMS = ((0x800E75D0, (512, 511), (384, 0)), (0x800EE3F0, (512, 511), (384, 256)),
                (0x800D88D8, (640, 510), (676, 320)))
VS_BACKGROUNDS = (12, 13)            # makuma00.tia, makuma01.tia (logical ids 10, 11)
VS_PORTRAITS = 14                    # face_b00.tiz … face_b21.tiz
PORTRAITS = 22


def _runtime(out: Output, system: Vram, name: str, tims: list[bytes]) -> None:
    """Records the VRAM a screen builds at run time: the system image, then `tims` (sources.py)."""
    if out.sources is not None:
        vram = system.copy()
        for tim in tims:
            vram.upload_tim(tim)
        sources.runtime_vram(out, name, vram.words)


def write_tims(out: Output, rel: str, system: Vram, tims: list[bytes]) -> None:
    """A `.tims` file, recorded as a run-time VRAM state over the system image."""
    out.write(rel, _tims_file(tims))
    _runtime(out, system, rel, tims)


def _tims_file(tims: list[bytes]) -> bytes:
    out = bytearray(struct.pack("<I", len(tims)))
    for t in tims:
        out += struct.pack("<I", len(t)) + t
    return bytes(out)


def _relocated(tim: bytes, clut_xy: tuple[int, int], image_xy: tuple[int, int]) -> bytes:
    """A TIM with its CLUT and pixel blocks moved to the given VRAM positions."""
    out = bytearray(tim)
    pos = 8
    flags = struct.unpack_from("<I", tim, 4)[0]
    for xy in ([clut_xy] if flags & 8 else []) + [image_xy]:
        struct.pack_into("<2H", out, pos + 4, *xy)
        pos += struct.unpack_from("<I", tim, pos)[0]
    return bytes(out)


PORTRAIT_BLOCK_ROWS = 64  # a big portrait's rows per quarter of its CLUT


def _portrait_rgba(tim: bytes) -> np.ndarray:
    """A big portrait's 8-bit TIM through its own CLUT, whatever their upload coordinates (the
    TIMs put both blocks at (0, 0); the game uploads them elsewhere). The pixels are 6-bit: the
    drawing (select.ovl FUN_8010F760, the VS screen's alike) moves the CLUT on by 64 entries
    (CLUT id + 4) every 64 rows, so each block of rows has its own quarter of the palette."""
    pos = 8
    clut_len, _, _, cw, ch = struct.unpack_from("<IHHHH", tim, pos)
    palette = np.frombuffer(tim, dtype="<u2", count=cw * ch, offset=pos + 12)
    pos += clut_len
    _, _, _, w, h = struct.unpack_from("<IHHHH", tim, pos)
    indices = np.frombuffer(tim, dtype=np.uint8, count=2 * w * h, offset=pos + 12).reshape(h, 2 * w)
    block = (np.arange(h) // PORTRAIT_BLOCK_ROWS * PORTRAIT_BLOCK_ROWS)[:, None]
    return rgba(palette[(indices.astype(np.int32) + block) % palette.size])


def convert(disc: Disc, out: Output) -> None:
    # The game's memory the screens' drawing reads: the executable and the overlays.
    blocks = disc.blocks()
    index = {}
    for name in ("exe", *RAM_OVERLAYS):
        out.write(f"screens/ram/{name}.bin", blocks[name].data)
        index[name] = {"file": f"ram/{name}.bin", "base": blocks[name].base}
    # Texts of another release that do not fit where Japan Rev.1 keeps them (layout.py), read
    # by address first.
    for (block, addr), text in sorted(disc.strings.items()):
        if block in index:
            index[block].setdefault("strings", {})[str(addr)] = text
    out.write_json("screens/ram.json", index)
    title = disc.images("title")
    system = disc.system_vram().copy()
    for tim in title[TITLE_BUTTONS].tims:
        system.upload_tim(tim)
    out.write("screens/vram_system.bin", system.words.astype("<u2").tobytes())
    _runtime(out, system, "screens/vram_system.bin", [])
    found = disc.images("select")
    write_tims(out, "screens/select.tims", system, found[SELECT_ARCHIVE].tims)
    for i, tim in enumerate(overlay_images.archive_members(*disc.source("select", SELECT_PORTRAITS))):
        out.write(f"screens/portraits/{i}.png", png_bytes(_portrait_rgba(tim)))
    result = disc.images("result")
    write_tims(out, "screens/result_ta.tims", system, result[RESULT_TIME_ATTACK].tims)
    write_tims(out, "screens/result_force.tims", system, result[RESULT_FORCE].tims)
    ranking = disc.images("ranking")
    for i, tim in enumerate(ranking[RANKING_PICTURES].tims):
        write_tims(out, f"screens/ranking_{i}.tims", system, [tim])
    ending = disc.images("ending")
    write_tims(out, "screens/staff.tims", system, [ending[a].tims[0] for a in STAFF_TIMS])
    theater = [_relocated(ending[a].tims[0], clut, image) for a, clut, image in THEATER_TIMS]
    write_tims(out, "screens/theater.tims", system, theater + ending[THEATER_PICTURES].tims)
    for i, bns in enumerate(VS_BACKGROUNDS):
        tims = [decompress_tim(m)[0] for m in tia_members(disc.bns(bns))]
        write_tims(out, f"screens/makuma_{i}.tims", system, tims)
    force = disc.images("force")
    write_tims(out, "screens/force_keys.tims", system, [force[a].tims[0] for a in sorted(force) if a in FORCE_KEYS])
    for i in range(PORTRAITS):
        out.write(f"screens/vs_portraits/{i}.png", png_bytes(_portrait_rgba(decompress_tim(disc.bns(VS_PORTRAITS + i))[0])))
