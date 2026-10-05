#!/usr/bin/env python3
"""End-to-end check of Tekken Force's hidden manual target switch in the original code (Japan Rev.1).

Everything below runs the game's own routines in the CPU harness; only the two pad library
queries are stubbed (a digital pad on port 1). It feeds the pad driver's receive bytes (buttons
active low) to the per-frame pad read `FUN_8002A014`, runs the mode-start check `FUN_800B5910`,
then plays fight frames through `FUN_800B5EC0` with two equally close enemies and checks that
the target changes only on a press of the chosen button (not during the 120-frame wait that
follows a change), and that without the secret the button does nothing.

Usage: python3 tools/research/check_force_manual_target.py
"""

from __future__ import annotations

import struct
import sys

import force_sim as fs
import verify_menu_sim as vm

REC = 0x800A95F8                 # port 1 pad record: +0 decoded buttons, +2 status, +4/+5 raw bytes
OUT = 0x801F7F00


def setup():
    cpu = vm.menu_cpu("force")
    cpu.write(0x80092BA8, struct.pack("<2I", 0x03E00008, 0x24020004))                        # jr ra; li v0, 4
    cpu.write(0x80092C68, struct.pack("<5I", 0x38A80001, 0x2D080001, 0x03E00008, 0x00081080, 0))  # v0 = (a1 == 1) * 4
    return cpu


def run(secret: int) -> list[int]:
    cpu = setup()
    w8 = lambda a, v: cpu.write(a, bytes([v & 0xFF]))
    w16 = lambda a, v: cpu.write(a, struct.pack("<H", v & 0xFFFF))
    w32 = lambda a, v: cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))
    u16 = lambda a: struct.unpack("<H", cpu.read(a, 2))[0]

    def pad_frame(low: int, high: int = 0) -> None:
        w8(REC + 2, 0)
        w8(REC + 4, ~high)
        w8(REC + 5, ~low)
        w8(REC + 0x2A + 2, 1)                             # port 2: no pad
        cpu.call(0x8002A014, 0)

    w16(0x800AE230, 0)
    pad_frame(secret)
    w32(fs.MANUAL, 0)
    w32(fs.MANUAL_BUTTON, 0)
    cpu.call(0x800B5910, 0)
    w32(0x800AFF50, 8)
    cpu.write(0x800A97B5, b"\0")
    for i, f in enumerate((fs.F0, fs.F1, fs.F2)):
        cpu.write(f + 0x1E, bytes([i]))
        for off in (0x87, 0xC2, 0xC4, 0xD1):
            cpu.write(f + off, b"\0")
        cpu.write(f + 0x1278, struct.pack("<H", 100))
    cpu.write(fs.F0 + 0x20, b"\x01")
    for k in range(8):
        w32(0x8009EA08 + 0x10 * k, 1000)
    w32(fs.TARGET_WAIT, 0)
    w32(fs.MANUAL_SIDE, 0)
    w16(fs.HUMAN_SIDE, 0)
    targets = [u16(0x800AE230), cpu.u32(fs.MANUAL), cpu.u32(fs.MANUAL_BUTTON)]
    def frame(press: int) -> int:
        pad_frame(press)
        cpu.call(0x800B5EC0, OUT, OUT + 4, OUT + 8)
        return cpu.u32(OUT + 4)

    targets.append(frame(0))                              # idle
    targets.append(frame(0x04))                           # L1: swap
    targets.append(frame(0))                           # idle
    targets.append(frame(0))
    pad_frame(0)
    targets.append(frame(0x04))                           # L1 again during the 120-frame wait: ignored
    for _ in range(119):
        frame(0)
    targets.append(frame(0x04))                           # L1 after the wait: swaps back
    return targets


def main() -> int:
    on = run(0xF0 | 0x04)                                 # triangle, circle, cross, square and L1 held
    off = run(0x04)                                       # only L1 held
    print("with the secret:", [hex(v) for v in on])
    print("without it:     ", [hex(v) for v in off])
    ok = on[:3] == [0xF4, 1, 4] and on[3] != on[4] == on[5] == on[6] == on[7] and on[8] == on[3] \
        and off[1] == 0 and len(set(off[3:])) == 1
    print("PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
