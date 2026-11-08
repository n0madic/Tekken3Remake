#!/usr/bin/env python3
"""Record the arcade version's whole game in the CPU harness for the remake's flow tests.

The counterpart of flow_trace.py: `main`'s start-up and its loop run from state 0 in
`arcade_fight_harness.py`, with free play on (the remake has no coins). A scenario gives the day
counter (the operator's clock that opens the fighters) and a `Driver`'s presses by the game state;
the fights are played by the bots or by nobody. A scenario can also empty one player's health early
in each round, so that a whole ladder fits a trace: the remake's test does not play those rounds.

File (`arcade_flow_<scenario>.bin`, fight_harness.write_trace_file's container, magic "T3AG"): JSON
header (scenario, ranges, frames); body, per frame: u16 pad 0, u16 pad 1, u16 state, u16 sub-state,
u32 `rand` state after the frame, then the ranges.

    python3.14 tools/research/arcade_flow_trace.py [names] [--jobs N]
    python3.14 tools/research/arcade_flow_trace.py --check
"""

from __future__ import annotations

import argparse
import logging
import struct
from collections.abc import Callable
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

import arcade_fight_harness as afh
import fight_harness

log = logging.getLogger("arcade_flow_trace")

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "work" / "traces"
MAGIC = b"T3AG"
VERSION = 1

# Settings bytes and game globals.
SET_FREE_PLAY = 0x8036EC4C
DAY = 0x802F4B8C
ATTRACT_STEP = 0x8021F231
FRAME_HEADER = "<HHHHI"

# The panel (FUN_8018CD30's words, 1 = pressed).
UP, DOWN, LEFT, RIGHT = 0x2000, 0x1000, 0x800, 0x400
LP, RP, LK, RK = 0x200, 0x100, 0x40, 0x20
START = 0x8000

# Game states (main's switch).
BOOT, TRANSITION, ATTRACT, TITLE, MATCH, SELECT, RANKING, ENDING = 0, 1, 2, 3, 4, 5, 7, 8
FIGHT_SUB = afh.FIGHT_SUB_STATE
CONTINUE_SUB = 9
ROUND_FIGHTING = 1                      # 0x8021F0C0

# A fighter's record.
MOVES_AT, MOVES_BYTES = 0x3C, 0x10
JOINTS_AT, JOINTS_BYTES = 0x75C, 24 * 0x50

# What the flow's tests compare, (name, address, size).
RANGES = (
    ("globals", 0x8021F000, 0xE00),     # the small globals: state, timers, round, players, pads
    ("match", 0x80374F18, 0x300),       # the mode's context, the ladder, the ranking's block, the stage times
    ("vs", 0x80273244, 0x20),           # the VS screen's steps
    ("name_entry", 0x802732EC, 0x10),   # a versus record's entry in the fight
    ("ranking_entry", 0x8029CEF0, 0x10),
    ("day", DAY, 4),
    ("select", 0x802C8300, 0x168 + 0x40 * 0x14),   # the character select's context and its sparks
    *(item for i, base in enumerate(afh.FIGHTERS) for item in (
        (f"fighter{i}_moves", base + MOVES_AT, MOVES_BYTES),    # root and pose: move and frame
        (f"fighter{i}_joints", base + JOINTS_AT, JOINTS_BYTES), # the skeleton of the fights and the scenes
    )),
)

PRESS_FRAMES = 2


@dataclass
class Press:
    """Pads to play once the game is in `state` (and `sub`), `after` frames later."""
    state: int
    sub: int | None = None
    after: int = 0
    pads: tuple[tuple[int, int], ...] = ()


def press(state: int, sub: int | None, after: int, pad0: int = 0, pad1: int = 0) -> Press:
    return Press(state, sub, after, tuple([(pad0, pad1)] * PRESS_FRAMES + [(0, 0)] * PRESS_FRAMES))


class Driver:
    """Plays the presses in order; idle meanwhile, the bots in a fight when told so."""

    def __init__(self, h: afh.ArcadeFightHarness, scenario: Scenario) -> None:
        self.h = h
        self.scenario = scenario
        self.presses = list(scenario.presses)
        self.queue: list[tuple[int, int]] = []
        self.waited = 0
        self.bots = [afh.ArcadeBot(h, i, scenario.seed * 2 + i, "random") for i in range(2)]
        self.fought = 0

    def _knock_out(self) -> None:
        """The scenario's loser has no health left `ko_after` frames into each round."""
        h = self.h
        if h.s16(afh.ROUND_STATE) != ROUND_FIGHTING:
            self.fought = 0
            return
        self.fought += 1
        if self.fought == self.scenario.ko_after:
            h.w32(afh.FIGHTERS[self.scenario.ko_side] + afh.HEALTH, 0)

    def next(self) -> tuple[int, int]:
        h = self.h
        state, sub = h.s32(afh.GAME_STATE), h.s32(afh.SUB_STATE)
        if self.scenario.ko_side >= 0 and state == MATCH and sub == FIGHT_SUB:
            self._knock_out()
        if self.queue:
            return self.queue.pop(0)
        if self.presses:
            want = self.presses[0]
            if want.state == state and (want.sub is None or want.sub == sub):
                self.waited += 1
                if self.waited > want.after:
                    self.presses.pop(0)
                    self.waited = 0
                    self.queue = list(want.pads)
                    return self.queue.pop(0)
        if state == MATCH and sub == FIGHT_SUB and self.scenario.fight_bots:
            return tuple(self.bots[i].next() if self.scenario.fight_bots & (1 << i) else 0 for i in range(2))
        return (0, 0)


@dataclass
class Scenario:
    name: str
    frames: int
    seed: int = 1
    day: int = 0
    presses: tuple[Press, ...] = ()
    fight_bots: int = 0                 # bit i: player i is played by a bot in the fights
    ko_side: int = -1                   # this player loses each round, `ko_after` frames into its fight
    ko_after: int = 120
    settings: afh.Settings = field(default_factory=afh.Settings)


# Start in attract (free play): from state 2 the game starts at once.
_START_AT_ATTRACT = press(ATTRACT, None, 120, START)
_PICK = press(SELECT, None, 40, LP)

SCENARIOS = {s.name: s for s in (
    Scenario("attract", 15000),
    Scenario("solo", 9000, presses=(_START_AT_ATTRACT, _PICK)),
    Scenario("solo_day120", 3000, day=120, presses=(_START_AT_ATTRACT, _PICK)),
    # Nobody plays, the CPU wins; Start in the countdown goes back to the select, and the second fight
    # is lost as well.
    Scenario("continued", 12000, presses=(_START_AT_ATTRACT, _PICK, press(MATCH, CONTINUE_SUB, 120, START), _PICK)),
    # The second player comes in during the first fight; the bots play the versus fights.
    Scenario("challenger", 12000, fight_bots=3,
             presses=(_START_AT_ATTRACT, _PICK, press(MATCH, FIGHT_SUB, 400, 0, START), press(SELECT, None, 40, LP, LP))),
    # The whole ladder won, Ogre's scene and True Ogre, the ending and the staff roll, the name entry.
    Scenario("ladder", 40000, day=120, ko_side=1, presses=(_START_AT_ATTRACT, _PICK)),
)}


def boot(h: afh.ArcadeFightHarness, scenario: Scenario) -> None:
    h.w8(SET_FREE_PLAY, 1)
    h.boot(scenario.settings, scenario.seed)
    # After the start-up: FUN_801BACAC finds the harness's backed-up clock invalid and clears the day.
    h.w32(DAY, scenario.day)


def record(scenario: Scenario, harness: afh.ArcadeFightHarness | None = None):
    """Yields (harness, pads) per frame, with the harness holding the state after the frame."""
    h = harness or afh.ArcadeFightHarness()
    boot(h, scenario)
    driver = Driver(h, scenario)
    for _ in range(scenario.frames):
        pads = driver.next()
        h.step(pads)
        yield h, pads


def frame_bytes(h: afh.ArcadeFightHarness, pads: tuple[int, int]) -> bytes:
    head = struct.pack(FRAME_HEADER, pads[0], pads[1], h.s32(afh.GAME_STATE), h.s32(afh.SUB_STATE), h.rand_state)
    return head + b"".join(h.cpu.read(address, size) for _, address, size in RANGES)


def write_trace(scenario: Scenario, path: Path) -> int:
    body = bytearray()
    frames = 0
    harness = afh.ArcadeFightHarness()
    last = None
    for h, pads in record(scenario, harness):
        body += frame_bytes(h, pads)
        where = (h.s32(afh.GAME_STATE), h.s32(afh.SUB_STATE))
        if where != last:
            log.info("%s: frame %d state %d sub %d", scenario.name, frames, *where)
            last = where
        frames += 1
    if harness.unknown_bios:
        raise RuntimeError(f"{scenario.name}: unknown BIOS calls {sorted(harness.unknown_bios)}")
    header = {
        "version": VERSION,
        "scenario": {"name": scenario.name, "seed": scenario.seed, "day": scenario.day,
                     "ko_side": scenario.ko_side, "ko_after": scenario.ko_after},
        "ranges": [[name, address, size] for name, address, size in RANGES],
        "frames": frames,
    }
    fight_harness.write_trace_file(path, MAGIC, VERSION, header, body)
    return frames


def _export(args: tuple[str, Path]) -> tuple[str, int]:
    name, out = args
    return name, write_trace(SCENARIOS[name], out / f"arcade_flow_{name}.bin")


# ---- the oracle's checks ----------------------------------------------------------------------

CHECK_FRAMES = 1200


def _check_run(args: tuple[str, Scenario]) -> tuple[str, list[bytes]]:
    variant, scenario = args
    frames = []
    for h, pads in record(scenario):
        frames.append(frame_bytes(h, pads))
        if len(frames) >= CHECK_FRAMES:
            break
    return variant, frames


def check() -> int:
    """The same run twice gives the same bytes; a Start press makes another run."""
    plain = Scenario("check", CHECK_FRAMES)
    started = Scenario("started", CHECK_FRAMES, presses=(_START_AT_ATTRACT,))
    runs: list[tuple[str, Scenario]] = [("first", plain), ("second", plain), ("started", started)]
    with ProcessPoolExecutor(len(runs)) as pool:
        results = dict(pool.map(_check_run, runs))
    failed = False
    for variant, want_equal in (("second", True), ("started", False)):
        diverged = next((i for i, (a, b) in enumerate(zip(results["first"], results[variant])) if a != b), None)
        log.info("%s: %s", variant, "identical" if diverged is None else f"diverges at frame {diverged}")
        failed |= (diverged is None) != want_equal
    log.info("check %s", "FAILED" if failed else "passed")
    return 1 if failed else 0


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*", help="scenarios (default: all)")
    parser.add_argument("--check", action="store_true", help="the oracle's determinism and negative control")
    parser.add_argument("--jobs", type=int, default=2)
    parser.add_argument("--out", type=Path, default=OUT_DIR)
    args = parser.parse_args()
    if args.check:
        return check()
    names = args.names or list(SCENARIOS)
    args.out.mkdir(parents=True, exist_ok=True)
    with ProcessPoolExecutor(args.jobs) as pool:
        for name, frames in pool.map(_export, [(name, args.out) for name in names]):
            log.info("%s: %d frames", name, frames)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
