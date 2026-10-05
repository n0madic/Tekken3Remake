#!/usr/bin/env python3
"""Check the arcade floor's tile split rule against the arcade's own floor routine.

FUN_801A87C8(stage) sets the floor up and FUN_801A941C(target) draws it for a camera
(docs/research/arcade/stages.md#floor): the tiles it splits into quarters come back as
groups of four quads, the others as one. For random cameras (FUN_801A26A4's view matrix, the
screen offset (256, 240) of the 480-line display and a projection distance H) the split and drawn
tiles of the game are compared with `split_tiles`, the rule as documented, evaluated on the
game's own vertex depths and screen positions. (The remake draws the quarter-tile pattern on every
tile and does not use the rule.)

Usage: python3 tools/research/verify_arcade_floor.py [--zip tekken3_mame.zip] [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import math
import random
import struct
import sys
from pathlib import Path

from arcade_cpu import DEFAULT_ZIP, arcade, arcade_cpu, sine_table

log = logging.getLogger("verify_arcade_floor")

FLOOR_MESH = 0x801A8594         # decompresses and maps the floor TMD, builds the quads (once)
FLOOR_SETUP = 0x801A87C8
DRAW_SYNC = 0x801E8AEC         # waits for the GPU: none here
FLOOR_DRAW = 0x801A941C
VIEW_MATRIX = 0x801A2B24       # camera {pitch, yaw, roll, _, _, x, y, z} → GTE view matrix
CAMERA = 0x802C6BD4
VIEW_ROTATION = 0x8036EBFC     # FUN_801A26A4's matrix
Y_STRETCH = 0x1400 * 95 / 100 / 4096   # its y row: (0xA00 << interlace) · 95 / 100
INTERLACE = 0x8021FC98
BUFFER = 0x8021FC80
DISPLAY = 0x8021FB34
FIGHTERS = ((0x8031E5A0, 0x8031E5A8), (0x80320084, 0x8032008C))
VERTICES = 0x80262778          # → the floor's vertex words (set by FLOOR_SETUP)
QUADS = 0x80262788             # → per tile, its four vertex indices (bytes)
SXY = 0x1F800000               # the transformed vertices' screen positions …
SZ = 0x1F800288                # … and depths (u16)
SPLIT_PRIMS = 0x8036EF18       # four POLY_GT4 (0x34 bytes) per split tile, buffer 0
TILE_PRIMS = 0x80262D50        # one POLY_GT4 per tile (0x34 bytes), buffer 0
PRIM = 0x34
DISPLAY_BLOCK = 0x80390000
ORDERING_TABLE = 0x80391000
OT_ENTRIES = 0x400
OT_END = 0xFFFFFF
SCREEN = (512, 480)            # the 480-line display
OFFSET = (256, 240)
GTE_OFX, GTE_OFY, GTE_H = 24, 25, 26
TILES = 10
TILE_UNITS = 2500
# FUN_801A941C splits at most LIMIT tiles a frame into quarters, those with a vertex nearer than
# |camera y| · 4096 / sin(pitch + ANGLE) + the stage's offset.
LIMIT = 11
ANGLE = 0xEF
SPLIT_OFFSETS = 0x801FF390     # s32 per stage


def floor_cpu(arc: arcade.ArcadeSet):
    cpu = arcade_cpu(arc)
    cpu.write(INTERLACE, struct.pack("<i", 1))
    cpu.write(BUFFER, struct.pack("<i", 0))
    cpu.write(DISPLAY, struct.pack("<I", DISPLAY_BLOCK))
    cpu.write(DISPLAY_BLOCK + 4, struct.pack("<I", ORDERING_TABLE))
    cpu.stub(DRAW_SYNC, lambda cpu, *args: 0)
    cpu.call(FLOOR_MESH)
    return cpu


def run(cpu, camera: dict) -> tuple[list[set[int]], set[int], list[tuple[int, int, int]], list[int]]:
    """The game's split tiles (per group of quarters in drawing order, the tiles it can be: the
    screen positions of saturated corners repeat), its whole tiles, and its vertices' (sx, sy, sz)
    and quad words."""
    pitch, yaw = camera["pitch"], camera["yaw"]
    cx, cy, cz = camera["position"]
    tx, tz = camera["target"]
    cpu.write(CAMERA, struct.pack("<3i", pitch, yaw, 0))
    cpu.write(CAMERA + 0x14, struct.pack("<3i", cx, cy, cz))
    cpu.call(VIEW_MATRIX, CAMERA)
    rows = struct.unpack("<9h", cpu.read(VIEW_ROTATION, 18))
    norms = [math.sqrt(sum(v * v for v in rows[3 * r:3 * r + 3])) / 4096 for r in range(3)]
    # Depths (SZ) are in game units: the view's z row is a unit vector; only y is stretched.
    if abs(norms[2] - 1) > 0.002 or abs(norms[0] - 1) > 0.002 or abs(norms[1] - Y_STRETCH) > 0.002:
        raise RuntimeError(f"view matrix rows scaled by {norms}")
    cpu.gte.write_ctrl(GTE_OFX, OFFSET[0] << 16)
    cpu.gte.write_ctrl(GTE_OFY, OFFSET[1] << 16)
    cpu.gte.write_ctrl(GTE_H, camera["h"])
    for x_address, z_address in FIGHTERS:
        cpu.write(x_address, struct.pack("<i", tx))
        cpu.write(z_address, struct.pack("<i", tz))
    cpu.write(ORDERING_TABLE, struct.pack(f"<{OT_ENTRIES}I", *([OT_END] * OT_ENTRIES)))
    cpu.write(0x803A0000, struct.pack("<3i", tx, 0, tz))
    cpu.call(FLOOR_DRAW, 0x803A0000)
    count = 121
    sxy = [struct.unpack_from("<2h", cpu.read(SXY + 4 * v, 4)) for v in range(count)]
    sz = struct.unpack("<121H", cpu.read(SZ, 2 * count))
    vertices = [(sxy[v][0], sxy[v][1], sz[v]) for v in range(count)]
    quads = list(struct.unpack(f"<{TILES * TILES}I", cpu.read(cpu.u32(QUADS), 4 * TILES * TILES)))
    groups: dict[int, set[int]] = {}
    whole = set()
    for bucket in range(OT_ENTRIES):
        link = cpu.u32(ORDERING_TABLE + 4 * bucket) & OT_END
        while link != OT_END:
            address = 0x80000000 | link
            if TILE_PRIMS <= address < TILE_PRIMS + PRIM * TILES * TILES:
                whole.add((address - TILE_PRIMS) // PRIM)
            elif SPLIT_PRIMS <= address < SPLIT_PRIMS + PRIM * 4 * LIMIT and (address - SPLIT_PRIMS) % (4 * PRIM) == 0:
                # A group's first quad is the tile's first quarter: corner 0 is the tile's v0, corner 1
                # the middle of v0–v1 (the game's truncating halves).
                x0, y0 = struct.unpack("<2h", cpu.read(address + 8, 4))
                x1, y1 = struct.unpack("<2h", cpu.read(address + 20, 4))   # POLY_GT4: xy1 after rgb1
                groups[address] = {k for k, word in enumerate(quads) if (x0, y0, x1, y1) == _first_quarter(vertices, word)}
            link = cpu.u32(address) & OT_END
    return [groups[a] for a in sorted(groups)], whole, vertices, quads


def _first_quarter(vertices: list[tuple[int, int, int]], word: int) -> tuple[int, int, int, int]:
    def half(a: int, b: int) -> int:
        return int((a + b) / 2)
    v0, v1 = vertices[word & 0xFF], vertices[(word >> 8) & 0xFF]
    return v0[0], v0[1], half(v0[0], v1[0]), half(v0[1], v1[1])


def split_near(height: int, pitch: int, offset: int, sine: list[int]) -> int:
    """The split distance: |camera y| · 4096 / sin(pitch + 0xEF) (0 for a zero sine), plus the
    stage's offset; the division truncates, as C's."""
    s = sine[(pitch + ANGLE) & 0xFFF]
    return (int(abs(height) * 4096 / s) if s else 0) + offset


def looking_down(pitch: int) -> bool:
    return ((pitch & 0xFFF) - 0x400) & 0xFFFFFFFF < 0x201


def split_tiles(vertices: list[tuple[int, int, int]], quads: list[int], near: int, down: bool) -> tuple[list[int], set[int]]:
    """The rule (stages.md#floor) on the vertices' screen positions and depths: the split tiles in
    order, and the drawn ones."""
    split, drawn = [], set()
    for k, word in enumerate(quads):
        corners = [vertices[(word >> (8 * i)) & 0xFF] for i in range(4)]
        if any(sz == 0 for _, _, sz in corners):
            continue
        if not any(0 <= sy < SCREEN[1] for _, sy, _ in corners):
            continue
        if not any(sx & 0xFFFF < SCREEN[0] for sx, _, _ in corners):
            continue
        drawn.add(k)
        if len(split) < LIMIT and (any(sz < near for _, _, sz in corners) or down):
            split.append(k)
    return split, drawn


def random_camera(rng: random.Random) -> dict:
    target = (rng.randrange(-20000, 20000), rng.randrange(-20000, 20000))
    yaw = rng.randrange(0x1000)
    pitch = rng.choice([rng.randrange(-0x100, 0x300), rng.randrange(0x380, 0x640)])
    distance = rng.randrange(1500, 6000)
    height = rng.randrange(400, 4000)
    # The eye behind the target along the yaw (the view's forward is (−sin yaw, cos yaw) in x, z).
    fx, fz = -math.sin(yaw * math.tau / 4096), math.cos(yaw * math.tau / 4096)
    position = (int(target[0] - fx * distance), -height, int(target[1] - fz * distance))
    return {"pitch": pitch, "yaw": yaw, "position": position, "target": target, "h": rng.randrange(400, 900)}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--zip", type=Path, default=DEFAULT_ZIP)
    parser.add_argument("--cases", type=int, default=60, help="cameras per stage")
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    arc = arcade.open_set(args.zip)
    sine = sine_table(arc)
    rng = random.Random(args.seed)
    failures = 0
    split_counts = []
    for stage in range(arcade.STAGES):
        cpu = floor_cpu(arc)
        cpu.call(FLOOR_SETUP, stage)
        offset = arc.prog_values("<i", SPLIT_OFFSETS + 4 * stage)[0]
        for _ in range(args.cases):
            camera = random_camera(rng)
            groups, whole, vertices, quads = run(cpu, camera)
            near = split_near(camera["position"][1], camera["pitch"], offset, sine)
            down = looking_down(camera["pitch"])
            split, drawn = split_tiles(vertices, quads, near, down)
            split_counts.append(len(split))
            same = (len(groups) == len(split) and all(k in g for k, g in zip(split, groups))
                    and whole == drawn - set(split))
            if not same:
                failures += 1
                log.info("stage %d camera %s: game groups %s whole %s, rule split %s whole %s", stage, camera,
                         groups, sorted(whole), split, sorted(drawn - set(split)))
    log.info("split tiles per frame: %s", sorted(set(split_counts)))
    log.info("%s", "all cameras match" if not failures else f"{failures} cameras differ")
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
