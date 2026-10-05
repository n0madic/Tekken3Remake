#!/usr/bin/env python3
"""The arcade's motions (MAME's tekken3 set, World ver. E1) decoded by its own routine in the CPU
harness.

Layout (docs/research/arcade/README.md#motions): the move tables at MOVE_TABLES hold
MOVE_SLOTS row indices per motion type (17 types: the PlayStation's banks 0–16), relocated at
start-up into pointers to 0x3C-byte move rows at MOVE_ROWS (`FUN_8018eab4`). A row's first word
indexes the animation table (ANIM_TABLE, 8 bytes per animation, read from the file system), whose
first word is the stream's ROM address with a region in its top nibble (REGIONS). A stream starts
with its frame count; `FUN_80194744 (stream, out, frame, 57)` decodes one frame's 57 s16 channels:
three for the root, then joints 0–17's Euler angles (x, y, z), turned into the joint's local
rotation as Euler(x, −y, −z) (`FUN_801984a0`, `FUN_8019a498`).
"""

from __future__ import annotations

import struct
import zipfile
from pathlib import Path

import arcade_cpu

import arcade

MOVE_TABLES = 0x8006D430
MOVE_SLOTS = 0xEDE
MOVE_TYPES = 17
MOVE_ROWS = 0x80025E8C
MOVE_ROW = 0x3C
ANIM_TABLE = 0x22DAD08          # file-table address (program ROM)
ANIM_TABLE_BYTES = 0x9838
ANIM_ENTRY = 8
REGIONS = {0xA0000000: 0x61800000, 0x90000000: 0x70387290, 0xB0000000: 0x522DAD08}
REGION_MASK = 0xF0000000
DECODE = 0x80194744
ROM_READ = 0x801BB418
DMA_WAIT = 0x801BB1D4
CHANNELS = 57
ROOT_CHANNELS = 3
JOINTS = 18
OUT = 0x80300000
FLASH_CHIPS = (("tet1fl3l.12", 0x45513073), ("tet1fl3u.13", 0x1917D993))   # banked 0x1800000


def open_with_flash(path: Path) -> arcade.ArcadeSet:
    """The set with its flash bank after the three banked pairs (some streams live there)."""
    arc = arcade.open_set(path)
    with zipfile.ZipFile(path) as archive:
        arc.banked += arcade.interleave(*(arcade._chip(archive, n, c) for n, c in FLASH_CHIPS))
    return arc


class ArcadeMotion:
    def __init__(self, path: Path = arcade_cpu.DEFAULT_ZIP) -> None:
        self.arc = open_with_flash(path)
        self.anims = self.arc.read(ANIM_TABLE, ANIM_TABLE_BYTES)
        self.cpu = arcade_cpu.arcade_cpu(self.arc)
        self.cpu.stub(ROM_READ, lambda cpu, dst, src, size, _: (cpu.write(dst, self.arc.read(src, size)), dst)[1])
        self.cpu.stub(DMA_WAIT, lambda cpu, *_: 0)

    def row(self, motion_type: int, slot: int) -> tuple[int, ...]:
        index = self.arc.prog_values("<I", MOVE_TABLES + 4 * (motion_type * MOVE_SLOTS + slot))[0]
        return self.arc.prog_values("<15I", MOVE_ROWS + MOVE_ROW * index)

    def address(self, anim: int) -> int:
        a = struct.unpack_from("<I", self.anims, ANIM_ENTRY * anim)[0]
        region = a & REGION_MASK
        return (a + REGIONS[region]) & 0xFFFFFFFF if region in REGIONS else a

    def frames(self, address: int) -> int:
        return self.arc.read(address, 1)[0]

    def streams(self, motion_type: int) -> dict[int, int]:
        """Every animation of a motion type's moves: stream address → frame count."""
        out = {}
        for slot in range(MOVE_SLOTS):
            try:
                address = self.address(self.row(motion_type, slot)[0])
                n = self.frames(address)
            except (arcade.ArcadeError, struct.error):
                continue
            if n >= 2:
                out.setdefault(address, n)
        return out

    def pose(self, address: int, frame: int) -> list[int]:
        """The 57 channels of 0-based `frame`."""
        self.cpu.write(OUT, bytes(2 * CHANNELS))
        self.cpu.call(DECODE, address, OUT, frame, CHANNELS)
        return list(struct.unpack(f"<{CHANNELS}h", self.cpu.read(OUT, 2 * CHANNELS)))

    @staticmethod
    def joint_angles(pose: list[int], joint: int) -> tuple[int, int, int]:
        """A joint's local rotation as Euler angles (x, y, z) for EulerToMatrix (16-bit units)."""
        x, y, z = pose[ROOT_CHANNELS + 3 * joint:ROOT_CHANNELS + 3 * joint + 3]
        return x, -y, -z
