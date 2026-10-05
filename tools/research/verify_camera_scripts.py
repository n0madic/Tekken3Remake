#!/usr/bin/env python3
"""Compare camera_scripts.CameraStream with the game's stream sampler FUN_80038F38.

Every stream referenced by a bank's section 7 is copied into harness RAM and sampled at
every frame by the original routine and by the port.

Usage: python3 tools/research/verify_camera_scripts.py
"""

from __future__ import annotations

import logging
import struct

import camera_scripts as cs
import motion
from psxcpu import load_release

log = logging.getLogger("verify_camera_scripts")
BUFFER = 0x80100000
OUT = 0x801FF000
SAMPLE = 0x80038F38


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    cpu = load_release()
    tab = motion.SplineTables(motion.load_exe())
    streams = frames = bad = 0
    for code, bank in cs.distinct_banks().items():
        s7, s8, s9 = bank.bounds[7], bank.bounds[8], bank.bounds[9]
        cpu.write(BUFFER, bank.data[s8:s9] + bytes(64))
        offsets = sorted({c.script & 0xFFFF for c in cs.read_choices(bank.data, s7, (s8 - s7) // 8)
                          if c.script < 0 and c.script != -1})
        for off in offsets:
            _, stream = cs.stream_at(bank.data, s8 + off, tab)
            streams += 1
            for f in range(stream.frames):
                cpu.write(OUT, bytes(16))
                cpu.call(SAMPLE, BUFFER + off + 2, OUT, f)
                game = [v - 0x10000 if v & 0x8000 else v
                        for v in struct.unpack("<7H", cpu.read(OUT, 14))][:stream.channels]
                mine = stream.sample(f)
                frames += 1
                if game != mine:
                    bad += 1
                    if bad < 10:
                        log.info("bank %d stream %#x frame %d: game %s mine %s", code, off, f, game, mine)
    log.info("%d streams, %d frames, %d mismatches", streams, frames, bad)
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
