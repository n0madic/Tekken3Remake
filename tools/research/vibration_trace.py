"""The pad vibration scripts run by the game's own code (sound.md#vibration), for the remake's
PadVibration test.

Every pattern 1–27 is queued alone on pad 0 (`PadVibrate(0, p)`), then pairs of patterns in
different and equal slots, and `VibrationUpdate` (0x80029228) runs for 160 frames with the
frame counter 0x800982E0 stepping as the vertical-blank handler steps it.

Trace (`vibration.bin`): "T3VB", u32 version, u32 case count; per case u8 pattern count, the
patterns (u8 each, queued before frame 0), u16 frame count, then per frame u8 small motor on,
u8 large motor level.
"""

from __future__ import annotations

import struct

import psxcpu

MAGIC = b"T3VB"
VERSION = 1
PAD_VIBRATE = 0x80029114
VIBRATION_UPDATE = 0x80029228
PENDING = 0x8009BDE8            # pad 0's four queued patterns
STATE = 0x8009BD58              # pad 0's slot scripts; +0x40 small motor, +0x42 large motor
STATE_BYTES = 0x44
FRAME_COUNTER = 0x800982E0
PATTERNS = 28
FRAMES = 160


def _cases() -> list[list[int]]:
    cases = [[p] for p in range(1, PATTERNS)]
    cases += [[5, 12], [12, 5], [2, 21], [9, 19], [19, 9], [14, 26], [4, 23], [3, 17]]
    return cases


def record() -> bytes:
    cpu = psxcpu.load_release()
    out = bytearray(MAGIC + struct.pack("<II", VERSION, len(_cases())))
    for patterns in _cases():
        cpu.write(PENDING, bytes(8))
        cpu.write(STATE, bytes(STATE_BYTES))
        cpu.write(FRAME_COUNTER, struct.pack("<I", 0))
        for p in patterns:
            cpu.call(PAD_VIBRATE, 0, p)
        out += struct.pack("<B", len(patterns)) + bytes(patterns) + struct.pack("<H", FRAMES)
        for frame in range(FRAMES):
            cpu.call(VIBRATION_UPDATE, PENDING, STATE)
            small, large = struct.unpack("<HH", cpu.read(STATE + 0x40, 4))
            out += struct.pack("<BB", small & 0xFF, large & 0xFF)
            cpu.write(FRAME_COUNTER, struct.pack("<I", frame + 1))
    return bytes(out)
