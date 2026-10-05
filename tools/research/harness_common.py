"""Pieces shared by the harness scripts that run the PlayStation's fighter routines on synthetic
fighter records (verify_hand_poses.py, verify_gon_eyes.py, gon_eyes_cases.py): the fighter record's
fields they set, and FUN_80029610's GPU command list, where the VRAM copies of the faces end up."""

from __future__ import annotations

import struct

PLAYER, CHAR_ID, COSTUME_SLOT = 0x12, 0x18, 0x1C         # s16 fields of a fighter record
COMMANDS = 0x8009BFF8            # the command list: a pointer to its end, then the count
COMMAND_BUFFER = 0x801B0000      # where the scripts point it
COMMAND_BYTES = 16               # s16 2, ., x, y, w, h, dx, dy: a MoveImage of a rectangle to a point
MOVE_COMMAND = 2


def reset_commands(cpu) -> None:
    """Empties the command list (FUN_80029700)."""
    cpu.write(COMMANDS, struct.pack("<II", COMMAND_BUFFER, 0))


def read_commands(cpu) -> list[tuple[int, ...]]:
    """The commands queued since `reset_commands`, as (kind, x, y, w, h, dx, dy)."""
    (count,) = struct.unpack("<I", cpu.read(COMMANDS + 4, 4))
    out = []
    for i in range(count):
        kind, _, *rest = struct.unpack("<8h", cpu.read(COMMAND_BUFFER + COMMAND_BYTES * i, COMMAND_BYTES))
        out.append((kind, *rest))
    return out
