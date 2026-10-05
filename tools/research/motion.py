#!/usr/bin/env python3
"""Tekken 3 motion banks (divmot*.bin): header, move rows and animation streams.

Verified against Japan Rev.1 code:
- DivmotRelocate (0x8006A18C) / DivmotLinkBank (0x8002D068): header and move rows;
- AnimDecodeRoot (0x80038C14) / AnimDecodePose (0x80038DA0): channel streams;
- AnimSplineSample (0x80038A1C): keyed-channel B-spline evaluation.
The spline weight tables live in the EXE (0x80096B1F..0x80097144); they are
read from the user's executable rather than copied into this repository.
"""

from __future__ import annotations

import struct
from dataclasses import dataclass
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOVE_SLOTS = 0xFB7            # 4023 move-index slots (section 2)
MOVE_ROW_BYTES = 0x38
COMMON_FLAG = 0x40000000      # move-index / anim offsets at or above refer to divmot99
POSE_CHANNELS = 49
ROOT_CHANNELS = 3
HEADER_WORDS = 25             # u16 header + 48 count bytes
CHANNEL_SHIFT = [1] * 15 + [5] * 34  # EXE table 0x80097048
SPLINE_TABLE_BASE = 0x80096B40
EXE_TEXT = 0x80010000
EXE_HEADER = 0x800


class MotionError(ValueError):
    pass


class SplineTables:
    """Accessor for the B-spline weight/index tables in the game executable."""

    def __init__(self, exe: bytes) -> None:
        start = SPLINE_TABLE_BASE - 0x40
        end = SPLINE_TABLE_BASE + 0x620
        self.base = start
        self.blob = exe[start - EXE_TEXT + EXE_HEADER : end - EXE_TEXT + EXE_HEADER]

    def u8(self, addr: int) -> int:
        return self.blob[addr - self.base]

    def u16(self, addr: int) -> int:
        return struct.unpack_from("<H", self.blob, addr - self.base)[0]


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def spline_sample(keys: list[int], frame: int, frames: int, shift: int, tab: SplineTables) -> int:
    """Literal port of AnimSplineSample (0x80038A1C). `keys` are the channel's s16 words."""
    last = frames - 1
    t6 = t7 = 0
    t0 = keys[0]
    t4 = keys[1]
    ki = 2
    t1 = t0
    t3 = ((t4 >> 5) << shift) + t1
    t4 &= 0x1F
    t2 = t3
    while True:
        t7 += t4 + 1
        t2 = t3
        if t7 == last:
            break
        t4 = keys[ki]
        ki += 1
        t3 += (t4 >> 5) << shift
        t5 = frame - t7
        t4 &= 0x1F
        if t5 <= 0:
            break
        t6 = t7
        t0, t1 = t1, t2
    local = frame - t6
    length = t7 - t6
    t9 = SPLINE_TABLE_BASE
    if local:
        if length - 16 <= 0:
            idx = tab.u8(t9 + length * 32 + local - 0x21)
        else:
            idx = tab.u8(t9 - length * 32 - local + 0x420)
        local = idx << 1
    t8 = t9 + local
    t9 = t9 - local
    v1 = 0
    if t6 == 0:
        lo = tab.u16(t9 + 0x300) * (t3 - t1)
        a1 = tab.u16(t9 + 0x504)
        v0 = lo
    else:
        lo = tab.u16(t8 + 0x200) * (t0 - t1)
        if t7 != last:
            v1 = lo
            lo = tab.u16(t9 + 0x300) * (t3 - t1)
            a1 = tab.u16(t9 + 0x402)
            v0 = lo + v1
        else:
            a1 = tab.u16(t9 + 0x504) + tab.u16(t9 + 0x300) + 0x2AAB
            v0 = lo
    v0 += a1 * (t2 - t1)
    v0 = s32(v0) >> 16
    return s32(v0 + t1)


def s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


@dataclass
class AnimStream:
    frames: int
    counts: list[int]          # key count per channel
    channels: list[list[int]]  # raw s16 words per channel


def parse_anim(data: bytes, offset: int, channels: int = POSE_CHANNELS) -> AnimStream:
    head = struct.unpack_from("<H", data, offset)[0]
    frames = head & 0xFF
    counts = [head >> 8] + list(data[offset + 2 : offset + 2 + (channels - 1)])
    pos = offset + 2 * HEADER_WORDS
    out = []
    for c in counts:
        out.append([s16(w) for w in struct.unpack_from(f"<{c}H", data, pos)])
        pos += 2 * c
    return AnimStream(frames, counts, out)


def sample_channel(stream: AnimStream, ch: int, frame: int, tab: SplineTables) -> int:
    """Value of one channel at 0-based `frame`, as AnimDecodePose writes it (already doubled)."""
    n = stream.frames
    frame = min(max(frame, 0), n - 1)
    f = n - (frame + 1) if ch & 1 else frame
    c = stream.counts[ch]
    keys = stream.channels[ch]
    if c == 0:
        return 0
    if c == 1:
        v = keys[0]
    elif c == 2:
        t = keys[1] * f
        if n > 9:
            t >>= 5
        v = (keys[0] & 0xFFFF) + t
    elif c == n:
        v = keys[f]
    else:
        v = spline_sample(keys, f, n, CHANNEL_SHIFT[ch], tab)
    return s16(v << 1)


def sample_pose(stream: AnimStream, frame: int, tab: SplineTables, channels: int = POSE_CHANNELS) -> list[int]:
    return [sample_channel(stream, ch, frame, tab) for ch in range(channels)]


@dataclass
class MotionBank:
    data: bytes
    type_code: int
    move_count: int
    bounds: list[int]

    @property
    def move_index(self) -> list[int]:
        return list(struct.unpack_from(f"<{MOVE_SLOTS}I", self.data, self.bounds[2]))

    def move_row(self, row: int) -> tuple[int, ...]:
        return struct.unpack_from("<14I", self.data, self.bounds[1] + row * MOVE_ROW_BYTES)

    def anim_offset(self, anim_word: int) -> int:
        return self.bounds[6] + anim_word


def parse_bank(data: bytes) -> MotionBank:
    if data[0] != 0:
        raise MotionError("first byte must be zero")
    bounds = list(struct.unpack_from("<15I", data, 4))
    if bounds[0] != 0x40 or bounds[14] != len(data):
        raise MotionError("section directory does not cover the file")
    return MotionBank(data, data[1], struct.unpack_from("<H", data, 2)[0], bounds)


def load_exe(release: str = "jp_rev1") -> bytes:
    return (ROOT / "work" / release / "exe.bin").read_bytes()
