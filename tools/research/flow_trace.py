#!/usr/bin/env python3
"""Record the whole game running in the CPU harness (`game_harness.py`) for the remake's flow tests.

A scenario boots the game with a random seed and drives the pads frame by frame: a `Driver`
presses buttons by the game state (menus, character select, prompts) and plays the fights with
the bots of `fight_harness.py`. Each frame records the pads, the game state and sub-state after
the frame, the engine calls (sounds, music, vibration, loads), the RAM ranges of the game's
progress, mode and player globals and, in the fight states, the fighter records (three in
Tekken Ball and Tekken Force, whose third record is the ball's attacker or the second enemy).

A scenario may change the progress block right after boot (`pokes`, as a memory card would:
Tekken Ball open, Tekken Force keys, Doctor B.), and may refill the player's health in Tekken
Force fights (`refill`: after a frame in which fighter 0 has less than REFILL_BELOW left but is
alive, its health is set to its maximum; while the round runs, a timer below TIMER_BELOW frames
is set to TIMER_REFILL), so that the bots reach the later levels; and may keep the CPU's health
low (`drain`: after a frame of a running round, a CPU fighter holding more than DRAIN_TO is set
to it), so that one hit wins a round and the bot climbs the arcade ladder to Ogre, the Ogre scene
and True Ogre. The header lists these rules for the remake's test, which does the same.

File (`flow_<scenario>.bin`): "T3GF", u32 version, u32 header length, JSON header (scenario,
ranges, pointed blocks, call kinds, frames, the motion banks' epochs, the pokes), u32 body
length, u32 zlib length, zlib(body). Body, per frame: u16 pad 0, u16 pad 1, u16 state, u16
sub-state, u8 call count, per call u8 kind, u8 argument count, s32 arguments; the ranges (raw);
the pointed blocks (the bytes at the address a pointer holds, zeros for a null pointer); u8
fighter records (0, 2 or 3), then the records.

    python3 tools/research/flow_trace.py [names] [--jobs N]
"""

from __future__ import annotations

import argparse
import logging
import struct
import time
from dataclasses import dataclass, field
from pathlib import Path

import fight_harness as fh
import game_harness as gh

log = logging.getLogger("flow_trace")

ROOT = Path(__file__).resolve().parents[2]
OUT_DIR = ROOT / "work" / "traces"
MAGIC = b"T3GF"
VERSION = 2
CALL_KINDS = fh.CALL_KINDS
RANGES = (
    ("progress", 0x800982D0, 0x220),     # the save block, flow globals and the record block
    ("mode", 0x800AFF00, 0x110),         # the mode context 0x800AFF50 and the fight's globals
    ("globals", 0x800AE140, 0x300),      # stage, music, players' characters, pads, rules
    ("state", 0x800AE6C0, 0x40),         # players, game state, timers, difficulty, level
    ("fight_flags", 0x80095840, 0xC0),
    ("round", 0x80097340, 0x30),
    ("pause", 0x80098DD8, 0x08),
    ("cpu_flags", 0x800A95F0, 4),         # 0x800A95F0: the players' CPU flags
    ("keep", 0x800AE484, 4),              # 0x800AE484: the picks are kept
    ("other", 0x800B0A04, 4),             # 0x800B0A06: the side that did not start
    ("screen", 0x800B9378, 0x170),        # the screen context (quick select, VS screen objects)
    ("select", 0x80118C48, 0x14C),        # select.ovl: the character select context
    ("cells", 0x80129CE8, 22 * 12),       # select.ovl: the portrait grid
    ("practice", 0x800B916C, 0x20C),      # practice.ovl: the practice state S and the key ring
    ("practice_globals", 0x800958D8, 0x18),  # practice flag, paused, intro, counter attacks
    ("signal", 0x800AE430, 8),            # the freeze signal's back light colours
    ("options", 0x800EB2F0, 6 * 0x34),    # title.ovl: the options' page records
    ("options_state", 0x800EC5E8, 0x58),  # title.ovl: the page byte, mode pictures, card state
    ("key_config", 0x800EC640, 2 * 0x1E8),  # title.ovl: the key configuration records
    ("records", 0x800ECA10, 0x90),        # title.ovl: the records pages
    ("result", 0x800FAC48, 0x238),        # result.ovl: the result screens' state
    ("banner", 0x80102690, 8),            # result.ovl: the scrolling banner
    ("voice_seq", 0x800A37A8, 2),         # the victory voice's sequence and delay
    ("ranking", 0x800CBE68, 0x8C),        # ranking.ovl: the page table
    ("name", 0x800D36F8, 0x40),           # ranking.ovl: the name entry and the backdrop camera
    ("rand", 0x800A3E80, 4),
    ("frame_rng", 0x8009F650, 4),
    ("camera_rng", 0x800A95F4, 4),
    ("intro_counter", 0x80098920, 0x10),  # the round intro's counter 0x8009892C (kept across matches)
    ("camera_sources", 0x800A0640, 0x240),  # the camera sources and the winner style 0x800A0844
    ("camera", 0x800A8A80, 0x28),         # the view
    ("director", 0x800A9130, 0x80),       # the camera director's state and the reel's
    ("panorama", 0x800A9650, 0x30),       # the backdrop's turn (FUN_8006E4A0): angle, yaws, points
    ("look_point", 0x800AE0D8, 0xC),      # FUN_8006E4A0: the point ahead of the camera
    ("ai_globals", 0x8009F690, 0x30),     # the AI slots' move indices, the Ball and Force words
    ("ai_records", 0x8009F6C0, 0x660),
    ("ball_mode", 0x800B6400, 0xA00),     # volley.ovl: options, tuning, gauges, popups, projection
    ("force_mode", 0x800B69F0, 0x720),    # force.ovl: targeting, slots, items, script, score, camera
)
# Blocks read through a pointer: (name, pointer address, size).
POINTED = (
    ("ball", 0x800AE23C, 0x160),          # the Tekken Ball ball object in the fight heap
)
FIGHT_STATE = 8
RANKING_STATE = 17
ENDING_STATE = 19
GAME_MODE = 0x800AFF50
FIGHTERS = fh.FIGHTERS + (0x800AC808,)
HEALTH, HEALTH_MAX = 0x3F4, 0x3F8
REFILL_BELOW = 0x280000               # 40 health (16.16)
TIMER_BELOW, TIMER_REFILL = 600, 3600  # frames: 10 s left becomes 60 s (before the countdown)
IS_CPU = 0xC5                         # the fighter record's CPU flag (u8)
DRAIN_TO = 0x10000                    # 1 health (16.16): one hit ends the round
FORCE_LEVEL_ENDED = 0x800B70E8            # the level's enemies are over: its closing fight runs
PAUSED = 0x800958B0                   # the pausing player (practice's menu included)

BALL_NEW = 0x80098306                 # the TEKKEN BALL menu entry's "new" counter (0: hidden)
FORCE_KEYS = 0x800982F8
UNLOCKED = 0x800982D0                 # bit per character; bit 19 is Doctor B.

UP, RIGHT, DOWN, LEFT = 0x1000, 0x2000, 0x4000, 0x8000
START, SELECT, CROSS, CIRCLE, SQUARE, TRIANGLE = 0x800, 0x100, 0x40, 0x20, 0x80, 0x10
L1, R1, L2, R2 = 0x4, 0x8, 0x1, 0x2


class ForceBot(fh.Bot):
    """Tekken Force's player: walks forward while no enemy is out (the camera scrolls with the
    player), else fights like the fight harness's bot; the level's closing fight (its boss is in
    no slot) is fought too."""

    SLOTS = 0x800B6A7C

    def next(self) -> int:
        h = self.h
        if h.u32(FORCE_LEVEL_ENDED) == 0 and all(h.s16(self.SLOTS + 0x18 * k + 8) in (0, 1, 2, 3) for k in range(2)):
            self.queue = []
            return self._pad(6, 0)
        return super().next()


class Driver:
    """Presses buttons by the game state. `steps` is a list of (condition, presses): when the
    condition holds (a callable of the harness), the presses (a list of (pad0, pad1) per frame,
    each followed by a release frame) are played; then the next step waits for its condition.
    In the fight sub-state the bots play the humans' pads."""

    def __init__(self, h: gh.GameHarness, steps: list, seed: int, fight_styles=("random", "random")) -> None:
        self.h = h
        self.steps = list(steps)
        self.queue: list[tuple[int, int]] = []
        self.seed = seed
        self.styles = fight_styles
        self.bots: list[fh.Bot] | None = None
        self.bot_fight = -1

    def next(self) -> tuple[int, int]:
        if self.queue:
            return self.queue.pop(0)
        h = self.h
        if self.steps:
            condition, presses = self.steps[0]
            if condition(h):
                self.steps.pop(0)
                for p in presses:
                    self.queue += [p, (0, 0)]
                return self.queue.pop(0) if self.queue else (0, 0)
        if h.state() == FIGHT_STATE and h.sub_state() == 8:
            if h.u32(PAUSED):
                return (0, 0)                  # the bots wait while the game is paused
            if self.bots is None:
                bot = ForceBot if h.s32(GAME_MODE) == 8 else fh.Bot
                self.bots = [bot(h, i, self.seed * 2 + i, self.styles[i]) for i in range(2)]
            humans = h.cpu.read(0x800AE3D8, 1)[0]
            return tuple(self.bots[i].next() if humans >> i & 1 else 0 for i in range(2))
        self.bots = None
        return (0, 0)


def at(state: int, sub: int | None = None, after: int = 0):
    """A condition: the game is in `state` (and `sub`), for at least `after` frames."""
    seen = {"n": 0}

    def check(h: gh.GameHarness) -> bool:
        ok = h.state() == state and (sub is None or h.sub_state() == sub)
        seen["n"] = seen["n"] + 1 if ok else 0
        return ok and seen["n"] > after
    return check


def paused(after: int = 0):
    """A condition: a fight is paused (the practice menu is up) for at least `after` frames."""
    seen = {"n": 0}

    def check(h: gh.GameHarness) -> bool:
        ok = h.state() == FIGHT_STATE and h.u32(PAUSED) != 0
        seen["n"] = seen["n"] + 1 if ok else 0
        return ok and seen["n"] > after
    return check


def presses(*pads: int, player: int = 0) -> list[tuple[int, int]]:
    return [(p, 0) if player == 0 else (0, p) for p in pads]


@dataclass
class Scenario:
    name: str
    seed: int
    steps: list = field(default_factory=list)
    frames: int = 6000
    styles: tuple[str, str] = ("random", "random")
    pokes: tuple[tuple[int, int], ...] = ()    # (address, byte) written after boot
    refill: bool = False                       # the player's health is refilled in Tekken Force
    drain: bool = False                        # the CPU's health is kept at DRAIN_TO in every fight
    # (state, frames): the scenario ends that many frames after the game first enters the state,
    # if that comes before `frames`
    end_after: tuple[int, int] | None = None


def _to_menu() -> list:
    """From boot to the main menu: Start on the transition screen once the card was read."""
    return [(at(2, 9, after=2), presses(START))]


def _vs_mode() -> list:
    """VS MODE from the main menu (cursor on ARCADE MODE): down, Cross."""
    return [(at(4, 1, after=4), presses(DOWN)), (at(4, 1, after=2), presses(CROSS))]


def _arcade() -> list:
    """ARCADE MODE (the menu's first entry), a character from the select grid, and one continue."""
    return [(at(4, 1, after=4), presses(CROSS)),
            (at(9, 1, after=30), presses(RIGHT, DOWN, CIRCLE)),
            (at(8, 10, after=100), presses(START))]


def _menu(index: int) -> list:
    """The main menu's entry `index` (from ARCADE MODE, down), chosen with Cross."""
    return [(at(4, 1, after=4), presses(*([DOWN] * index))), (at(4, 1, after=2), presses(CROSS))]


def _force_pick(direction: int = RIGHT) -> list:
    """A character on the select screen of Tekken Force."""
    return [(at(9, 1, after=30), presses(direction, CROSS))]


def _options() -> list:
    """OPTION MODE: GAME OPTION values, KEY CONFIGURATION (vibration, default, exit), RECORDS
    pages, MEMORY CARD (save, load, auto save on) and EXIT. DISPLAY ADJUST (hidden in the remake)
    is never reached: the cursor goes up from GAME OPTION to MEMORY CARD."""
    opt = lambda *pads: (at(5, 1, after=6), presses(*pads))
    return [opt(CROSS), opt(RIGHT, DOWN, RIGHT, DOWN, DOWN, LEFT), opt(SELECT),
            opt(DOWN, CROSS), opt(DOWN, RIGHT), opt(DOWN, CROSS), opt(DOWN, CROSS),
            opt(DOWN, CROSS), opt(RIGHT, RIGHT, DOWN, RIGHT), opt(CROSS),
            opt(UP, UP, UP, UP, CROSS), opt(START), opt(CROSS), opt(DOWN, CROSS), opt(START), opt(CROSS),
            opt(DOWN, RIGHT), opt(CROSS), opt(DOWN, CROSS), opt(DOWN, CROSS)]


SCENARIOS = (
    Scenario("vs_mode", seed=41, frames=9000, steps=_to_menu() + _vs_mode() + [
        (at(10, None, after=20), presses(RIGHT, RIGHT, CROSS, CROSS)),
        (at(10, None, after=4), presses(LEFT, SQUARE, CROSS, player=1)),
    ]),
    Scenario("arcade", seed=7, frames=30000, steps=_to_menu() + _arcade()),
    Scenario("time_attack", seed=13, frames=16000, steps=_to_menu() + _menu(3) + [
        (at(9, 1, after=30), presses(LEFT, UP, CROSS)),
        (at(8, 10, after=60), presses(START))]),
    # Survival, team battle and attract stop at the ranking: the harness crashes Unicorn when the
    # attract demonstration's overlay replaces the ranking's with arcade.ovl loaded (tooling.md).
    Scenario("survival", seed=23, frames=9100, steps=_to_menu() + _menu(4) + [
        (at(9, 1, after=30), presses(RIGHT, RIGHT, SQUARE)),
        (at(17, 12, after=20), presses(RIGHT, CROSS, RIGHT, CROSS, RIGHT, CROSS))]),
    Scenario("team_battle", seed=31, frames=9900, steps=_to_menu() + _menu(2) + [
        (at(10, 2, after=20), presses(LEFT, LEFT, CROSS)),
        (at(10, 2, after=6), presses(CROSS)),
        (at(10, 2, after=6), presses(RIGHT, CROSS))]),
    Scenario("practice", seed=19, frames=6000, steps=_to_menu() + _menu(6) + [
        (at(9, 1, after=30), presses(RIGHT, CROSS)),
        (at(9, 1, after=10), presses(DOWN, CROSS)),
        # The pause menu opens by itself once the round starts: FREE; the dummy crouch-guards,
        # counter attacks and the freeze signal on, then OK.
        (paused(after=40), presses(CROSS)),
        (paused(after=8), presses(DOWN, DOWN, RIGHT, RIGHT, RIGHT, DOWN, RIGHT, DOWN, DOWN, RIGHT)),
        (paused(after=8), presses(UP, UP, UP, UP, UP, CROSS)),
        # Fight, then VS CPU.
        (at(8, 8, after=500), presses(START)),
        (paused(after=8), presses(UP, CROSS)),
        (paused(after=8), presses(DOWN, CROSS)),
        (paused(after=8), presses(DOWN, DOWN, RIGHT, UP, UP, CROSS)),
        # Fight the CPU, then COMBO TRAINING with its guide.
        (at(8, 8, after=500), presses(START)),
        (paused(after=8), presses(UP, CROSS)),
        (paused(after=8), presses(DOWN, CROSS)),
        (paused(after=8), presses(CROSS)),
        (at(8, 8, after=60), presses(SELECT)),
        (at(8, 8, after=300), presses(START)),
        (paused(after=8), presses(UP, CROSS)),
        (paused(after=8), presses(DOWN, DOWN, CROSS))]),
    Scenario("options", seed=5, frames=3000, steps=_to_menu() + _menu(7) + _options()),
    # Tekken Ball (open: its menu entry's counter 0x80098306 at 1): one player against the first
    # opponent, Gon, then a two-player match with the second ball type.
    Scenario("ball", seed=5, frames=9000, pokes=((BALL_NEW, 1),), steps=_to_menu() + _menu(5) + [
        (at(10, None, after=20), presses(RIGHT, CROSS)),
        (at(10, None, after=40), presses(RIGHT, CROSS)),
        (at(10, None, after=40), presses(CROSS))]),
    Scenario("ball_versus", seed=9, frames=12000, pokes=((BALL_NEW, 1),), steps=_to_menu() + _menu(5) + [
        (at(10, None, after=20), presses(LEFT, LEFT, CROSS)),
        (at(10, None, after=4), presses(START, player=1)),
        (at(10, None, after=20), presses(RIGHT, SQUARE, player=1)),
        (at(10, None, after=40), presses(RIGHT, RIGHT, CROSS)),
        (at(10, None, after=40), presses(CROSS))]),
    # Tekken Force: the bot clears level 1 and loses to its boss; with the health refilled, the
    # levels and their bosses; with three keys, the four levels, the Doctor B. level, the result
    # and 200 frames of the ranking (ending before the attract loop, whose demonstration fight
    # after the ranking crashes Unicorn); with Doctor B. unlocked, the boss list.
    Scenario("force", seed=3, frames=7000, steps=_to_menu() + _menu(5) + _force_pick()),
    Scenario("force_run", seed=11, frames=40000, refill=True, steps=_to_menu() + _menu(5) + _force_pick()),
    Scenario("force_final", seed=15, frames=80000, refill=True, pokes=((FORCE_KEYS, 3),), end_after=(RANKING_STATE, 200),
             steps=_to_menu() + _menu(5) + _force_pick(LEFT)),
    Scenario("force_bosses", seed=21, frames=40000, refill=True, pokes=((UNLOCKED + 2, 0x0F),),
             steps=_to_menu() + _menu(5) + _force_pick(DOWN)),
    Scenario("attract", seed=17, frames=2700),     # boot, title, demonstration fight, ranking
    # Arcade with the CPU's health drained: the ten ladder fights, the Ogre scene after the first
    # round won against Ogre, and True Ogre, up to the ending (whose movie player crashes Unicorn).
    Scenario("ogre", seed=27, frames=20000, drain=True, end_after=(ENDING_STATE, 2),
             steps=_to_menu() + _arcade()[:2]),
)


def record(scenario: Scenario):
    h = gh.GameHarness()
    h.boot(scenario.seed)
    for address, value in scenario.pokes:
        h.w8(address, value)
    driver = Driver(h, scenario.steps, scenario.seed, scenario.styles)
    last = None
    left = None                                # frames still to record once end_after's state came
    for _ in range(scenario.frames):
        if left is not None:
            if left == 0:
                break
            left -= 1
        pads = driver.next()
        h.step(pads)
        if scenario.refill:
            refill(h)
        if scenario.drain:
            drain(h)
        if left is None and scenario.end_after and h.state() == scenario.end_after[0]:
            left = scenario.end_after[1] - 1
        state = (h.state(), h.sub_state(), tuple(c for c in h.calls if c[0] == "load"))
        if state != last or h.frames % 1000 == 0:
            log.debug("%s frame %d: state %d sub %d loads %s overlays %s", scenario.name, h.frames, *state,
                      dict(h.slots))
            last = state
        yield h, pads


def refill(h: gh.GameHarness) -> None:
    """The player's health back to its maximum and the timer back to a minute when they run low
    in a Tekken Force fight."""
    if h.state() != FIGHT_STATE or h.s32(GAME_MODE) != 8:
        return
    health = h.s32(FIGHTERS[0] + HEALTH)
    if 0 < health < REFILL_BELOW:
        h.w32(FIGHTERS[0] + HEALTH, h.s32(FIGHTERS[0] + HEALTH_MAX))
    if h.s32(fh.ROUND_STATE) != 1:
        return
    if 0 < h.s32(fh.TIMER) < TIMER_BELOW:
        h.w32(fh.TIMER, TIMER_REFILL)


def drain(h: gh.GameHarness) -> None:
    """While a round runs, a CPU fighter's health down to DRAIN_TO."""
    if h.state() != FIGHT_STATE or h.s32(fh.ROUND_STATE) != 1:
        return
    for address in fh.FIGHTERS:
        if h.cpu.read(address + IS_CPU, 1)[0] and h.s32(address + HEALTH) > DRAIN_TO:
            h.w32(address + HEALTH, DRAIN_TO)


def _fighter_count(h: gh.GameHarness) -> int:
    if h.state() != FIGHT_STATE:
        return 0
    return 3 if h.s32(GAME_MODE) in (7, 8) else 2


def write_trace(scenario: Scenario, path: Path) -> int:
    body = bytearray()
    frames = 0
    epochs: list[dict] = []
    for h, pads in record(scenario):
        calls = h.calls
        body += struct.pack("<HHHHB", pads[0], pads[1], h.state(), h.sub_state(), len(calls))
        for name, *args in calls:
            body += struct.pack("<BB", CALL_KINDS.index(name), len(args))
            body += struct.pack(f"<{len(args)}i", *args)
        for _, addr, size in RANGES:
            body += h.cpu.read(addr, size)
        for _, pointer, size in POINTED:
            at = h.u32(pointer)
            body += h.cpu.read(at, size) if 0x80000000 <= at < 0x80200000 else bytes(size)
        count = _fighter_count(h)
        body += struct.pack("<B", count)
        for i in range(count):
            body += h.cpu.read(FIGHTERS[i], fh.FIGHTER_SIZE)
        if count:
            banks = fh._banks(h)
            if not epochs or epochs[-1]["banks"] != banks:
                epochs.append({"frame": frames, "banks": banks})
        frames += 1
    header = {
        "version": VERSION,
        "scenario": {"name": scenario.name, "seed": scenario.seed},
        "frames": frames,
        "call_kinds": list(CALL_KINDS),
        "ranges": [[name, addr, size] for name, addr, size in RANGES],
        "pointed": [[name, pointer, size] for name, pointer, size in POINTED],
        "fighter_size": fh.FIGHTER_SIZE,
        "fighters": list(FIGHTERS),
        "bank_epochs": epochs,
        "pokes": [list(p) for p in scenario.pokes],
        "refill": [HEALTH, REFILL_BELOW, TIMER_BELOW, TIMER_REFILL] if scenario.refill else None,
        "drain": [HEALTH, IS_CPU, DRAIN_TO] if scenario.drain else None,
    }
    fh.write_trace_file(path, MAGIC, VERSION, header, body)
    return frames


def _export_one(args: tuple[str, str]) -> tuple[str, int, float, str]:
    """Runs in a worker; the scenario is looked up by name (its steps hold closures)."""
    import traceback
    name, out_dir = args
    scenario = next(s for s in SCENARIOS if s.name == name)
    t = time.time()
    try:
        frames = write_trace(scenario, Path(out_dir) / f"flow_{scenario.name}.bin")
    except Exception:
        return scenario.name, 0, time.time() - t, traceback.format_exc()
    return scenario.name, frames, time.time() - t, ""


class _Serial:
    """A stand-in for Pool with one job, run in this process."""

    def __enter__(self) -> "_Serial":
        return self

    def __exit__(self, *exc: object) -> None:
        return None

    @staticmethod
    def imap_unordered(fn, items):
        return map(fn, items)


def export(names: list[str] | None, out_dir: Path, jobs: int) -> None:
    from multiprocessing import Pool
    chosen = [s for s in SCENARIOS if not names or s.name in names]
    work = [(s.name, str(out_dir)) for s in chosen]
    failed = []
    # One job runs in this process, so a crash of the emulator shows here instead of hanging the pool.
    with Pool(max(1, min(jobs, len(chosen)))) if jobs > 1 else _Serial() as pool:
        for name, frames, seconds, error in pool.imap_unordered(_export_one, work):
            if error:
                log.error("flow %s failed after %.0f s:\n%s", name, seconds, error)
                failed.append(name)
            else:
                log.info("flow %s: %d frames in %.0f s", name, frames, seconds)
    if failed:
        raise RuntimeError(f"flow scenarios failed: {failed}")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("names", nargs="*")
    parser.add_argument("--jobs", type=int, default=4)
    parser.add_argument("--probe", action="store_true", help="print the state changes of the first scenario")
    parser.add_argument("--verbose", action="store_true", help="log each scenario's state changes and loads")
    args = parser.parse_args()
    if args.verbose:
        logging.getLogger().setLevel(logging.DEBUG)
    if args.probe:
        scenario = next(s for s in SCENARIOS if not args.names or s.name in args.names)
        last = None
        for h, pads in record(scenario):
            st = (h.state(), h.sub_state())
            if st != last or pads != (0, 0) and h.state() != FIGHT_STATE:
                log.info("frame %d: state %d sub %d pads %s %s", h.frames, st[0], st[1], pads,
                         [c for c in h.calls if c[0] not in ("load",)][:3])
                last = st
        return 0
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    export(args.names, OUT_DIR, args.jobs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
