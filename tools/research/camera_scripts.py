#!/usr/bin/env python3
"""Decode the cinematic camera data: choice lists, presets, hit cameras and camera streams.

* EXE choice table `0x80098750` (camera ids 1-0x2A) and bank section 7 (ids >= 0x2B):
  flat arrays of 8-byte entries `(kind s16, weight u16, script s32)`; the choices of id `k`
  start at entry `k + 1` (EXE) or `k - 0x2B + 1` (bank). Groups are separated by
  `(0, 0x1000, 0x1000)`. kind 1 = preset, kind 2 = stream (pairs with equal weight: the
  second one is the alternate for the other side).
* Script values `< 0x1E` are framing presets (`0x80024184`, 20 bytes each via `0x800243DC`),
  negative values select a stream at `section8 + (value & 0xFFFF)`.
* A stream starts with a u16 yaw mode (0-5) followed by a channel stream: header
  `frames | channels << 10`; per channel a list of segments whose first descriptor also holds
  `segment count - 1` in bits 12-15; descriptor = `length | kind << 10`, kinds 0 constant
  (1 word), 1 linear (base, slope; slope / 32 unless the stream is shorter than 10 frames),
  2 B-spline keys (as animation keyed channels, shift 4), 3 raw (one word per frame).
  Odd channels are stored time-reversed. Camera streams have 7 channels: eye x, y, z,
  target x, y, z, and the fight-camera weight (0 = scripted camera only, 2560 = fight camera).

Usage: python3 tools/research/camera_scripts.py [--bank TYPE] [--frames]
"""

from __future__ import annotations

import argparse
import glob
import logging
import struct
from dataclasses import dataclass

import motion

log = logging.getLogger("camera_scripts")

EXE_CHOICES = 0x80098750
EXE_CHOICE_IDS = 0x2B
PRESETS = 0x80024184
PRESET_INDEX = 0x800243DC
PRESET_COUNT = 30
HIT_CAMERA_MATCH = 0x80024510      # 4 x (bank type, move slot, list id)
HIT_CAMERA_LISTS = 0x800244F8      # list id - 300 -> (pointer, count)
GROUP_END = (0, 0x1000, 0x1000)
CHANNEL_NAMES = ("eyeX", "eyeY", "eyeZ", "targetX", "targetY", "targetZ", "weight")


@dataclass
class Choice:
    kind: int
    weight: int
    script: int


def read_choices(data: bytes, base: int, count: int) -> list[Choice]:
    return [Choice(*struct.unpack_from("<hHi", data, base + 8 * i)) for i in range(count)]


def choice_groups(entries: list[Choice], first_id: int) -> dict[int, list[Choice]]:
    """Camera id -> its choices (the entries after a group separator)."""
    groups: dict[int, list[Choice]] = {}
    for i, e in enumerate(entries):
        if (e.kind, e.weight, e.script) != GROUP_END:
            continue
        run: list[Choice] = []
        for c in entries[i + 1:]:
            if (c.kind, c.weight, c.script) == GROUP_END:
                break
            if run and run[-1].weight >= 0xFFF and not (c.kind == 2 and c.weight == run[-1].weight):
                break              # the random draw never passes weight 0xFFF
            run.append(c)
        if run:
            groups[first_id + i] = run
    return groups


class CameraStream:
    """FUN_80038F38 (sampling) over the words of one stream."""

    def __init__(self, words: list[int], tab: motion.SplineTables) -> None:
        self.words = words
        self.tab = tab
        self.frames = words[0] & 0x3FF
        self.channels = words[0] >> 10
        self.size = self._walk()

    def _walk(self) -> int:
        p = 1
        for _ in range(self.channels):
            segments = self.words[p] >> 12
            for si in range(segments + 1):
                desc = self.words[p]
                p += 1
                kind, length = (desc >> 10) & 3, desc & 0x3FF
                p += (1, 2, length, length)[kind]
        return p

    def sample(self, frame: int) -> list[int]:
        out = []
        p = 1
        for c in range(self.channels):
            t = self.frames - (frame + 1) if c & 1 else frame
            segments = self.words[p] >> 12
            start = 0
            value = None
            for _ in range(segments + 1):
                desc = self.words[p]
                p += 1
                kind, length = (desc >> 10) & 3, desc & 0x3FF
                if kind == 2:
                    end = start + sum(1 + (w & 0x1F) for w in self.words[p + 1:p + length])
                    if value is None and t <= end:
                        keys = [motion.s16(w) for w in self.words[p:p + length]] + [0]
                        value = motion.s16(motion.spline_sample(keys, t - start, end - start + 1, 4, self.tab))
                    start = end + 1
                else:
                    if value is None and t < start + length:
                        if kind == 0:
                            value = motion.s16(self.words[p])
                        elif kind == 1:
                            q = motion.s16(self.words[p + 1]) * (t - start)
                            div = 1 if self.frames < 10 else 32
                            value = motion.s16(int(q / div) + self.words[p])
                        else:
                            value = motion.s16(self.words[p + t - start])
                    start += length
                p += (1, 2, length, length)[kind]
            out.append(value)
        return out


def stream_at(data: bytes, offset: int, tab: motion.SplineTables) -> tuple[int, CameraStream]:
    mode = struct.unpack_from("<H", data, offset)[0]
    words = list(struct.unpack_from(f"<{(len(data) - offset - 2) // 2}H", data, offset + 2))
    return mode, CameraStream(words, tab)


def distinct_banks() -> dict[int, motion.MotionBank]:
    banks: dict[int, motion.MotionBank] = {}
    for path in sorted(glob.glob(str(motion.ROOT / "work" / "jp_rev1" / "bns" / "*divmot*.bin"))):
        bank = motion.parse_bank(open(path, "rb").read())
        banks.setdefault(bank.type_code, bank)
    return banks


def exe_bytes(exe: bytes, addr: int, size: int) -> bytes:
    off = addr - 0x80010000 + 0x800
    return exe[off:off + size]


def print_exe_tables(exe: bytes) -> None:
    entries = read_choices(exe_bytes(exe, EXE_CHOICES, 8 * EXE_CHOICE_IDS), 0, EXE_CHOICE_IDS)
    print("EXE camera ids (move camera byte 1-0x2A):")
    for cid, run in choice_groups(entries, 0).items():
        print(f"  id {cid:#04x}: " + ", ".join(f"p{c.script}@{c.weight:#x}" for c in run))
    print("Presets (0x80024184): blend-in, blend-out, heights << 5, yaw offsets << 6")
    for i in range(PRESET_COUNT):
        v = struct.unpack_from("<10h", exe_bytes(exe, PRESETS + 20 * i, 20))
        print(f"  {i:2d}: in {v[0]:3d} out {v[1]:3d} heights {list(v[2:6])} yaws {list(v[6:10])}")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--bank", type=int, help="bank type code (default: all)")
    parser.add_argument("--frames", action="store_true", help="print every frame of every stream")
    args = parser.parse_args()
    exe = motion.load_exe()
    tab = motion.SplineTables(exe)
    if args.bank is None:
        print_exe_tables(exe)
    for code, bank in distinct_banks().items():
        if args.bank is not None and code != args.bank:
            continue
        s7, s8, s9 = bank.bounds[7], bank.bounds[8], bank.bounds[9]
        entries = read_choices(bank.data, s7, (s8 - s7) // 8)
        print(f"== bank type {code}: section 7 {s8 - s7} bytes, section 8 {s9 - s8} bytes")
        for cid, run in choice_groups(entries, EXE_CHOICE_IDS).items():
            parts = []
            for c in run:
                if c.script < 0 and c.script != -1:
                    mode, stream = stream_at(bank.data, s8 + (c.script & 0xFFFF), tab)
                    parts.append(f"s{c.script & 0xFFFF:#x}(mode {mode}, {stream.frames}f)@{c.weight:#x}")
                else:
                    parts.append(f"p{c.script}@{c.weight:#x}")
            print(f"  id {cid:#04x}: " + ", ".join(parts))
            if args.frames:
                for c in run:
                    if c.script < 0 and c.script != -1:
                        _, stream = stream_at(bank.data, s8 + (c.script & 0xFFFF), tab)
                        for f in range(stream.frames):
                            print(f"    {c.script & 0xFFFF:#06x} {f:3d} {stream.sample(f)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
