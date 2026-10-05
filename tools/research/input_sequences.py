#!/usr/bin/env python3
"""Print the motion-input sequence tables of the Tekken 3 executable.

Branch commands 0xC00E..0xC04C index table A (0x800958F4, 63 entries) and
0xC7FF..0xC827 index table B (0x800959F0, 41 entries). Each entry points to
    s16 window, u16 step[], 0
where a step is (button_spec << 8) | numpad_direction. The last step is matched
on the current frame; earlier steps are searched backwards in the 60-frame
input history within `window` frames (see docs/research/code/moves.md).
"""

from __future__ import annotations

import argparse
import struct
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EXE_BASE = 0x80010000
EXE_HEADER = 0x800
TABLES = {"A": (0x800958F4, 63, 0xC00E), "B": (0x800959F0, 41, 0xC7FF)}
BUTTONS = ("LP", "RP", "LK", "RK")


def exe_u16(exe: bytes, addr: int) -> int:
    return struct.unpack_from("<H", exe, addr - EXE_BASE + EXE_HEADER)[0]


def exe_u32(exe: bytes, addr: int) -> int:
    return struct.unpack_from("<I", exe, addr - EXE_BASE + EXE_HEADER)[0]


def step_text(step: int) -> str:
    direction, spec = step & 0xF, step >> 8
    text = str(direction)
    if spec & 0x1F == 0x10 or spec == 0:
        return text
    names = "+".join(b for i, b in enumerate(BUTTONS) if spec & (1 << i))
    return f"{text}{'(any ' if spec & 0x10 else '+'}{names}{')' if spec & 0x10 else ''}"


def read_sequence(exe: bytes, addr: int) -> tuple[int, list[int]]:
    window = struct.unpack("<h", struct.pack("<H", exe_u16(exe, addr)))[0]
    steps, addr = [], addr + 2
    while (step := exe_u16(exe, addr)) != 0:
        steps.append(step)
        addr += 2
    return window, steps


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--release", default="jp_rev1")
    args = parser.parse_args()
    exe = (ROOT / "work" / args.release / "exe.bin").read_bytes()
    print("| Command | Window | Sequence |\n|---|---:|---|")
    for base, count, first in TABLES.values():
        for i in range(count):
            window, steps = read_sequence(exe, exe_u32(exe, base + 4 * i))
            print(f"| `0x{first + i:04X}` | {window} | {' '.join(step_text(s) for s in steps)} |")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
