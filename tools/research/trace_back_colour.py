#!/usr/bin/env python3
"""Runs a flow scenario (flow_trace.py) in the CPU harness and prints, for every frame in which a
back colour flash counter (0x8009E998, Tekken Force's item pick-ups) is not zero, the frame, the
counters and the GTE's back colour in bytes after the frame, i.e. what the last SetBackColor of the
frame left (the last fighter drawn's). The golden values of the remake's `test_force_pickup_flash`
come from `force` (about ten minutes: the whole scenario runs; stop it once the first flash is over).

With `--out FILE` it writes the golden file of `test_force_pickup_flash` instead (work/traces/
force_back_colour.json): the stage's light record word and, for the frames after the pick-up's
frame in which the first player's counter runs (counts 1 to 25, while the player is the last fighter
drawn), the red (= green) and blue the GTE holds.

Usage: python3 tools/research/trace_back_colour.py [scenario] [--limit N] [--out FILE]   (default: force, 70 lines)
"""

from __future__ import annotations

import argparse
import json
import logging
from pathlib import Path

import flow_trace as ft
import projection_sim as pj

log = logging.getLogger("trace_back_colour")
BACK_COLOUR_REGISTERS = (13, 14, 15)
STAGE = 0x800AE14C              # the stage number of the fight
GOLDEN_FRAMES = 25              # the frames after the pick-up whose colour the player's draw leaves in the GTE


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("scenario", nargs="?", default="force")
    parser.add_argument("--limit", type=int, default=70)
    parser.add_argument("--out", type=Path, help="write the force pick-up golden file instead of printing")
    args = parser.parse_args()
    scenario = next(s for s in ft.SCENARIOS if s.name == args.scenario)
    printed = 0
    golden: list[list[int]] = []
    for h, _pads in ft.record(scenario):
        first, second = h.cpu.read(pj.FLASH, 2)
        if args.out is not None:
            if first:
                # The pick-up's own frame is still lit with the stage's level: the colours that follow count.
                colour = [h.cpu.gte.read_ctrl(r) >> 4 for r in BACK_COLOUR_REGISTERS]
                golden.append([colour[0], colour[2]])
                if len(golden) > GOLDEN_FRAMES:
                    stage = h.s32(STAGE)
                    ambient = h.cpu.read(pj.STAGE_RECORDS + (stage + 1) * pj.STAGE_RECORD_BYTES, 2)
                    args.out.write_text(json.dumps({"ambient": int.from_bytes(ambient, "little"),
                                                    "colours": golden[1:]}) + "\n")
                    log.info("%s: stage %d, %d frames", args.out, stage, GOLDEN_FRAMES)
                    return 0
            continue
        if first or second:
            colour = [h.cpu.gte.read_ctrl(r) >> 4 for r in BACK_COLOUR_REGISTERS]
            log.info("frame %d state %d mode %d flash %d %d back colour %s", h.frames, h.state(), h.s32(ft.GAME_MODE),
                     first, second, colour)
            printed += 1
            if printed >= args.limit:
                break
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
