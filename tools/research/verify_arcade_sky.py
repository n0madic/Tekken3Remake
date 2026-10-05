#!/usr/bin/env python3
"""Check the arcade sky conversion against the arcade's own drawing routine.

The System 12 CPU is the PlayStation's R3000A with a GTE, so the harness runs the arcade
program too: FUN_801A71AC(stage) sets the sky up and FUN_801A7688(buffer, yaw) builds its
primitives for a camera pitch (docs/research/arcade/stages.md#sky). The primitives are
taken from the ordering table, drawn in order into a 512 × 480 frame from the stage's VRAM, and
compared with the converter's model: the strip `arcade.sky` bakes (without its retouch of the
skipped cells, which the arcade leaves undrawn: `retouch=False`), scrolled to
((−yaw) & 0xFFF)·512 / step columns, its top row at the clamped −pitch·k / 256 + offset lines,
with the upper and lower fills around it (what StageView.set_view_pitch and arcade_sky.gdshader
draw).

The game fills 't' and 'd' cells with one tile primitive per screen slot (row, ninth of the
row): a 'd' cell sets that tile's colour to the lower colour and a 't' cell draws it without
setting a colour, so after a 'd' cell passed a slot, 't' cells there show the lower colour too
(game-bugs.md #62; only stage 5's bottom row has both). The converter keeps the tint, as meant;
the comparison follows the slots' colours so that the rest must match exactly.

Usage: python3 tools/research/verify_arcade_sky.py [--zip tekken3_mame.zip] [--stage N ...] [--dump DIR]
"""

from __future__ import annotations

import argparse
import logging
import struct
import sys
from pathlib import Path

import numpy as np

from arcade_cpu import DEFAULT_ZIP, arcade, arcade_cpu

log = logging.getLogger("verify_arcade_sky")

SKY_SETUP = 0x801A71AC
SKY_DRAW = 0x801A7688
INTERLACE = 0x8021FC98         # 1: the 480-line display
FIGHTER_CHARACTERS = (0x8031E16E, 0x8031FC52)   # True Ogre (0x14) blackens the sky
DISPLAY = 0x8021FB34           # → {…, +4 ordering table}
CAMERA_PITCH = 0x802C6BD4
DISPLAY_BLOCK = 0x80390000
ORDERING_TABLE = 0x80391000
SKY_BUCKET = 0xFFC             # FUN_801A7688 adds every primitive here
OT_END = 0xFFFFFF
WIDTH, HEIGHT = 512, 480
LOWER_FILL_END = HEIGHT * 3 // 4
CASES = ((0, 0), (1000, 0), (2600, -120), (3900, 200), (700, -400))   # (yaw, pitch)


def sky_cpu(arc: arcade.ArcadeSet):
    cpu = arcade_cpu(arc)
    cpu.write(INTERLACE, struct.pack("<i", 1))
    for address in FIGHTER_CHARACTERS:
        cpu.write(address, struct.pack("<H", 0))
    cpu.write(DISPLAY, struct.pack("<I", DISPLAY_BLOCK))
    cpu.write(DISPLAY_BLOCK + 4, struct.pack("<I", ORDERING_TABLE))
    return cpu


def primitives(cpu: psxcpu.PsxCpu) -> list[bytes]:
    """The primitives linked at the sky's bucket, in drawing order."""
    out = []
    link = cpu.u32(ORDERING_TABLE + SKY_BUCKET) & OT_END
    while link != OT_END:
        address = 0x80000000 | link
        tag = cpu.u32(address)
        out.append(cpu.read(address, 4 + 4 * (tag >> 24)))
        link = tag & OT_END
    return out


def _texels(vram: arcade.Vram, tpage: int, clut: int) -> np.ndarray:
    return arcade.page_picture(vram, clut, tpage)


def _paint(frame: np.ndarray, x0: int, y0: int, picture: np.ndarray) -> None:
    """Draws `picture` (RGBA, alpha 0 transparent) with its top left at (x0, y0)."""
    h, w = picture.shape[:2]
    xa, ya = max(x0, 0), max(y0, 0)
    xb, yb = min(x0 + w, WIDTH), min(y0 + h, HEIGHT)
    if xa >= xb or ya >= yb:
        return
    part = picture[ya - y0:yb - y0, xa - x0:xb - x0]
    shown = part[..., 3] != 0
    frame[ya:yb, xa:xb][shown] = part[shown]


def draw(vram: arcade.Vram, prims: list[bytes]) -> np.ndarray:
    """The frame the GPU draws: tiles, sprites through the current texture page, and the
    axis-aligned textured quads (their v may run upwards) and Gouraud quads FUN_801A7688 makes."""
    frame = np.zeros((HEIGHT, WIDTH, 4), dtype=np.uint8)
    tpage = 0
    for p in prims:
        if len(p) == 8 and p[7] == 0xE1:
            tpage = struct.unpack_from("<I", p, 4)[0] & 0xFFFF
            continue
        code = p[7] & 0xFC
        if code == 0x60:      # TILE
            x, y, w, h = struct.unpack_from("<4h", p, 8)
            frame[max(y, 0):max(y + h, 0), max(x, 0):max(x + w, 0)] = (*p[4:7], 255)
        elif code == 0x64:    # SPRT
            x, y = struct.unpack_from("<2h", p, 8)
            u, v, clut, w, h = p[12], p[13], *struct.unpack_from("<H2h", p, 14)
            _paint(frame, x, y, _texels(vram, tpage, clut)[v:v + h, u:u + w])
        elif code == 0x2C:    # POLY_FT4
            x0, y0 = struct.unpack_from("<2h", p, 8)
            u0, v0, clut = p[12], p[13], struct.unpack_from("<H", p, 14)[0]
            x1 = struct.unpack_from("<h", p, 16)[0]
            u1, page = p[20], struct.unpack_from("<H", p, 22)[0]
            y2 = struct.unpack_from("<h", p, 26)[0]
            v2 = p[29]
            texels = _texels(vram, page, clut)
            rows = [round(v0 + (v2 - v0) * j / max(y2 - y0 - 1, 1)) for j in range(y2 - y0)]
            cols = [round(u0 + (u1 - u0) * i / max(x1 - x0 - 1, 1)) for i in range(x1 - x0)]
            _paint(frame, x0, y0, texels[np.ix_(rows, cols)])
        elif code == 0x38:    # POLY_G4: a vertical gradient over the quad
            x0, y0 = struct.unpack_from("<2h", p, 8)
            top, bottom = np.array(list(p[4:7]), float), np.array(list(p[20:23]), float)
            x1 = struct.unpack_from("<h", p, 16)[0]
            y2 = struct.unpack_from("<h", p, 26)[0]
            for j in range(max(y0, 0), min(y2, HEIGHT)):
                t = (j - y0) / max(y2 - y0, 1)
                frame[j, max(x0, 0):min(x1, WIDTH)] = (*np.round(top + (bottom - top) * t).astype(int), 255)
        else:
            raise ValueError(f"unexpected primitive {p[7]:#x}")
    return frame


def model(info: dict, strip: np.ndarray | None, cells: bytes, slots: np.ndarray, yaw: int, pitch: int) -> np.ndarray:
    """The converter's sky for this view, as StageView and arcade_sky.gdshader draw it, with the
    't' cells in their slot's colour (`slots`: rows × 9 RGB, updated by the 'd' cells drawn)."""
    frame = np.zeros((HEIGHT, WIDTH, 4), dtype=np.uint8)
    p = pitch - 0x1000 if pitch > 0x7FF else pitch
    y = int(-p * info["pitch_scale"] / 256) + info["offset"]
    if info["clamp_top"] or info["kind"] == "gradient":
        y = min(y, 0)
    if info["clamp_bottom"] is not None:
        y = max(y, info["clamp_bottom"])
    if info["kind"] == "gradient":
        top, bottom = (np.array(c, float) for c in info["gradient"])
        for j in range(LOWER_FILL_END):   # then a black tile to three quarters of the screen
            t = min(max((j - y) / 192, 0.0), 1.0)
            frame[j] = (*np.round(top + (bottom - top) * t).astype(int), 255)
        return frame
    if info["kind"] == "fill":
        frame[:] = (*(info["upper_fill"] or (0, 0, 0)), 255)
        return frame
    x = (((-yaw) & 0xFFF) << 9) // info["step"]
    rows = info["rows"] * arcade.TILE
    for j in range(HEIGHT):
        row = j - y
        if row < 0:
            if info["upper_fill"] and y > 0:
                frame[j] = (*info["upper_fill"], 255)
        elif row < rows:
            frame[j] = strip[row, x:x + WIDTH]
        elif info["lower_fill"] and j < LOWER_FILL_END:
            frame[j] = (*info["lower_fill"], 255)
    width = info["map_width"]
    for r in range(info["rows"]):
        for i in range(arcade.SKY_SCREEN_COLUMNS):
            cell = cells[r * width + (x // arcade.TILE + i) % width]
            if cell == arcade.SKY_FILL_LOWER:
                slots[r, i] = info["lower_cells"]
            elif cell == arcade.SKY_FILL_TINT:
                x0, y0 = arcade.TILE * i - x % arcade.TILE, y + arcade.TILE * r
                frame[max(y0, 0):max(y0 + arcade.TILE, 0), max(x0, 0):max(x0 + arcade.TILE, 0), :3] = slots[r, i]
    return frame


def compare(game: np.ndarray, ours: np.ndarray) -> tuple[int, int]:
    """(differing pixels, pixels drawn by either)."""
    drawn = (game[..., 3] != 0) | (ours[..., 3] != 0)
    differ = drawn & (np.abs(game.astype(int) - ours.astype(int)).max(axis=2) > 0)
    return int(differ.sum()), int(drawn.sum())


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--stage", type=int, nargs="*", default=list(range(arcade.STAGES)))
    parser.add_argument("--dump", type=Path, help="write game/model frames of the failing cases here")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    arc = arcade.open_set(args.zip)
    cpu = sky_cpu(arc)
    failures = 0
    for number in args.stage:
        category = arc.prog_values("<i", arcade.STAGE_CATEGORY + 4 * number)[0]
        extra = [arc.category(arcade.EXTRA_TIMS[number])[0]] if number in arcade.EXTRA_TIMS else []
        vram = arcade.stage_vram(arc.category(category), extra)
        info, strip = arcade.sky(arc, vram, number, retouch=False)
        cpu.call(SKY_SETUP, number)
        cell_map = arc.prog_values("<I", arcade.SKY_RECORDS + arcade.SKY_RECORD * number + 0x0C)[0]
        cells = arc.prog(cell_map, info["rows"] * info["map_width"])
        slots = np.tile(np.array(info["tint"], dtype=np.uint8), (info["rows"], arcade.SKY_SCREEN_COLUMNS, 1))
        for yaw, pitch in CASES:
            cpu.write(ORDERING_TABLE + SKY_BUCKET, struct.pack("<I", OT_END))
            cpu.write(CAMERA_PITCH, struct.pack("<i", pitch & 0xFFF))
            cpu.call(SKY_DRAW, 0, yaw)
            game = draw(vram, primitives(cpu))
            ours = model(info, strip, cells, slots, yaw, pitch & 0xFFF)
            differ, drawn = compare(game, ours)
            ok = differ == 0
            failures += not ok
            log.info("stage %2d yaw %4d pitch %5d: %s (%d of %d pixels differ)",
                     number, yaw, pitch, "ok" if ok else "DIFFERENT", differ, drawn)
            if not ok and args.dump:
                from PIL import Image
                args.dump.mkdir(parents=True, exist_ok=True)
                Image.fromarray(np.concatenate([game, ours], 1)).save(args.dump / f"sky_{number}_{yaw}_{pitch}.png")
    log.info("%s", "all cases match" if not failures else f"{failures} cases differ")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
