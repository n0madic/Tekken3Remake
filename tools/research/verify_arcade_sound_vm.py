#!/usr/bin/env python3
"""Proves the arcade's sound driver port against MAME: `tools/remake_import/arcade_sound_vm.py` must write the same
C352 registers, in the same order, in the same tick, as the original H8 program does.

The logs come from `arcade_sound_log.lua` (`--capture` runs MAME over the scenarios). Each tick replays what the
log says reached the driver: the main CPU's words and, unless `--own-chip`, the chip's answers to
its flag reads. `--own-chip` answers from `arcade_c352.Chip` instead: then a sample can end one look of the driver
apart from MAME's, so the differences are counted and listed rather than failed, unless they exceed
`--own-chip-tolerance` per cent of the ticks.

Every run also checks the check: negative controls replay the busiest log with a wrong input (a wrong sequence
number, the main CPU's words two ticks late, the program's frequency table altered) and have to fail.

`--mix-check <scenario>` compares the chip's mix of a scenario's register writes with MAME's own output, per band,
and has a mix that comes late fail too.

    python3.14 tools/research/verify_arcade_sound_vm.py [--logs a.txt b.txt] [--zip tekken3_mame.zip] [--own-chip]
"""

from __future__ import annotations

import argparse
import logging
import os
import subprocess
import sys
import wave as wave_file
from collections.abc import Iterator
from concurrent.futures import ThreadPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent.parent
sys.path.insert(0, str(ROOT / "tools" / "remake_import"))

import arcade                   # noqa: E402
import arcade_c352              # noqa: E402
import arcade_sound_vm as vm    # noqa: E402

log = logging.getLogger("verify_arcade_sound_vm")
DEFAULT_LOG_DIR = ROOT / "work" / "arcade" / "audio" / "logs" / "vm"
KEY_REG = vm.REG_KEY
SHARED_COMMAND_FIRST, SHARED_COMMAND_END = 0x0100, 0x0180
MISMATCH_CONTEXT = 6
WRONG_SEQUENCE_BIT = 1

# MAME runs the driver's clock twice per video frame, every frame of every log, and the frames at 59.8261 Hz (measured
# with the machine's time at the tick and the frame): a tick is this many of the chip's samples there, not TICK_SAMPLES.
MAME_FRAME_RATE = 59.8261
MAME_TICKS_PER_FRAME = 2
MAME_TICK_SAMPLES = arcade_c352.SAMPLE_RATE / (MAME_FRAME_RATE * MAME_TICKS_PER_FRAME)

MIX_DIR = ROOT / "work" / "arcade" / "audio" / "logs" / "mix"
MIX_CHECK_FRAMES = 3000
MIX_CHECK_SKIP = 15 * arcade_c352.SAMPLE_RATE       # past the boot's silence
MIX_CHECK_WINDOW = arcade_c352.SAMPLE_RATE // 4
MIX_CHECK_SEARCH = 256
MIX_CHECK_QUIET = 50
MIX_CHECK_LATE = arcade_c352.SAMPLE_RATE // 2
MIX_CHECK_BAND = (0, 1000)
MIX_CHECK_MINIMUM = 0.95
MIX_CHECK_GAIN = (0.9, 1.1)

# Capture scenarios: what is injected into the shared RAM, as the main CPU's sound calls do.
LUA = Path(__file__).resolve().parent / "arcade_sound_log.lua"
ROMPATH = ROOT / "work" / "arcade" / "roms"
AUDIO_DIR = ROOT / "work" / "arcade" / "audio"
BOOT_FRAMES = 700                # the main CPU's boot has cleared the commands and set up the players
MUTE_MAIN_FRAME = 640            # from here it stops interfering with the injected commands
SECTION_FRAMES = 1800            # a music scenario's time per section
FADE_FRAMES = 600
TAIL_FRAMES = 300
SECTION_VAR = 0xE0
FADE_BIT = 0x2000
MUSIC_IDS = (*range(0x01, 0x04), *range(0x10, 0x1F), *range(0x60, 0x67))
SFX_SPACING = 12                 # frames between effects
SFX_WAVES = range(0, 0x400, 1)
# (scenario, channel, sequence, wave variable, level variable, level, echo variable)
SFX_PLAYERS = (
    ("sfx_system", 0x14, 0x100, 0x10, 0x01, 0, None),
    ("sfx_voice", 0x15, 0x101, 0x11, 0x02, 0x10, 0x0C),
    ("sfx_sound", 0x17, 0x103, 0x13, 0x04, 0, None),
    ("sfx_sound2", 0x19, 0x105, 0x15, 0x04, 0, None),
)
FIXED_SEQUENCES = (0x110, 0x111, 0x112, 0x113, 0x14D)
HIGH_WAVES = range(0x400, 0x49C)  # the rest of the directory: the winners' names among them
LONG_WAVES = (14, 17, 22, 29, 38, 103, 151, 153, 155)      # the linked samples: played long enough to pass their link
LONG_SPACING = 540                # frames: the players' hold (510 ticks) and their release
FIXED_CHANNEL = 0x14


@dataclass
class Tick:
    time: int
    writes: list[tuple[int, int]] = field(default_factory=list)
    reads: list[tuple[int, int]] = field(default_factory=list)
    shared: list[tuple[int, int, bool]] = field(default_factory=list)   # offset, value, seen in this tick


class Mismatch(Exception):
    pass


class Oracle:
    """The chip as the log saw it: writes are recorded, flag reads answered from the log."""

    def __init__(self) -> None:
        self.writes: list[tuple[int, int]] = []
        self.answers: list[tuple[int, int]] = []
        self.at = 0

    def write(self, reg: int, value: int) -> None:
        self.writes.append((reg, value))

    def read_flags(self, voice: int) -> int:
        reg = voice * 8 + vm.REG_FLAGS
        if self.at >= len(self.answers):
            raise Mismatch(f"flags of voice {voice} read beyond the original's reads")
        logged_reg, value = self.answers[self.at]
        if logged_reg != reg:
            raise Mismatch(f"read reg {reg:#x} where the original read {logged_reg:#x}")
        self.at += 1
        return value

    def start_tick(self, answers: list[tuple[int, int]]) -> None:
        self.writes = []
        self.answers = answers
        self.at = 0


def tick_lengths(count: int) -> Iterator[int]:
    """The chip's whole samples for each of `count` ticks at MAME's rate: the fraction carries over."""
    done = 0
    for tick in range(1, count + 1):
        end = round(tick * MAME_TICK_SAMPLES)
        yield end - done
        done = end


class OwnChip:
    """The port's chip, recording the writes."""

    def __init__(self, wave: bytes) -> None:
        self.chip = arcade_c352.Chip(wave, render=False)
        self.writes: list[tuple[int, int]] = []

    def write(self, reg: int, value: int) -> None:
        self.writes.append((reg, value))
        self.chip.write(reg, value)

    def read_flags(self, voice: int) -> int:
        return self.chip.read_flags(voice)


def parse(path: Path) -> tuple[list[Tick], Tick]:
    """(ticks, boot): events grouped by the driver's clock writes; the boot's before its first tick."""
    boot = Tick(0)
    ticks: list[Tick] = []
    current = boot
    with path.open() as f:
        for line in f:
            kind = line[0]
            if kind == "W":
                _, reg, value = line.split()
                current.writes.append((int(reg, 16), int(value, 16)))
            elif kind == "S":
                _, reg, value = line.split()
                current.reads.append((int(reg, 16), int(value, 16)))
            elif kind == "C":
                _, ofs, value = line.split()
                current.shared.append((int(ofs, 16), int(value, 16), False))
            elif kind == "R":
                ofs = int(line.split()[1], 16)
                for i in range(len(current.shared) - 1, -1, -1):
                    if current.shared[i][0] == ofs:
                        current.shared[i] = (ofs, current.shared[i][1], True)
                        break
            elif kind == "T":
                time = int(line.split()[1], 16)
                if time == 0 and not ticks:   # the boot clears its clock again before the first tick
                    continue
                current = Tick(time)
                ticks.append(current)
    return ticks, boot


def _same_ignoring_key_value(mine: list[tuple[int, int]], theirs: list[tuple[int, int]]) -> int:
    """The first index that differs, or -1. The key register's value is whatever a register held, and the chip ignores it."""
    for i in range(min(len(mine), len(theirs))):
        a, b = mine[i], theirs[i]
        if a[0] != b[0] or (a[1] != b[1] and a[0] != KEY_REG):
            return i
    return -1 if len(mine) == len(theirs) else min(len(mine), len(theirs))


def describe(mine: list[tuple[int, int]], theirs: list[tuple[int, int]], at: int) -> str:
    def show(rows: list[tuple[int, int]]) -> str:
        part = rows[max(0, at - MISMATCH_CONTEXT):at + MISMATCH_CONTEXT]
        return " ".join(f"{r:x}={v:x}" for r, v in part)
    return f"write #{at}\n  port: {show(mine)}\n  mame: {show(theirs)}"


def replay(ticks: list[Tick], boot: Tick, program: bytes, own_wave: bytes | None = None, *,
           wrong_sequence: bool = False, late_commands: bool = False, report: int = 8) -> tuple[int, int, list[str]]:
    """(ticks compared, ticks that differ, descriptions). With the log's chip the first difference stops it.

    The wrong inputs of the negative controls: `wrong_sequence` starts another sequence than each command
    says, `late_commands` delivers what the main CPU writes two ticks late."""
    chip = OwnChip(own_wave) if own_wave is not None else Oracle()
    machine = vm.SoundVM(program, chip)
    if isinstance(chip, Oracle):
        chip.start_tick(boot.reads)
    machine.boot()
    at = _same_ignoring_key_value(chip.writes, boot.writes)
    if at >= 0:
        return 0, 1, ["boot: " + describe(chip.writes, boot.writes, at)]
    late: list[tuple[int, int]] = []
    later: list[tuple[int, int]] = []
    for row in boot.shared:
        late.append((row[0], row[1]))
    differ = 0
    notes: list[str] = []
    done = 0
    lengths = tick_lengths(len(ticks))
    for tick in ticks:
        chip.writes = []
        for ofs, value in late:
            machine.write_shared(ofs, value)
        late = later
        later = []
        for ofs, value, seen in tick.shared:
            if wrong_sequence and SHARED_COMMAND_FIRST <= ofs < SHARED_COMMAND_END and value & vm.START_BIT:
                value ^= WRONG_SEQUENCE_BIT
            if late_commands:
                later.append((ofs, value))
            elif seen:
                machine.write_shared(ofs, value)
            else:
                late.append((ofs, value))
        if isinstance(chip, Oracle):
            chip.start_tick(tick.reads)
        try:
            machine.tick()
        except (Mismatch, vm.SoundVmError) as e:
            return done, differ + 1, notes + [f"tick {done} (time {tick.time:#x}): {e}"]
        if machine.time != tick.time:
            return done, differ + 1, notes + [f"tick {done}: clock {machine.time:#x}, MAME {tick.time:#x}"]
        at = _same_ignoring_key_value(chip.writes, tick.writes)
        unread = isinstance(chip, Oracle) and chip.at != len(tick.reads)
        done += 1
        if at >= 0 or unread:
            differ += 1
            text = f"tick {done - 1} (time {tick.time:#x}): "
            text += describe(chip.writes, tick.writes, at) if at >= 0 else f"{chip.at} flag reads, the original made {len(tick.reads)}"
            if len(notes) < report:
                notes.append(text)
            if own_wave is None:
                return done, differ, notes
        if isinstance(chip, OwnChip):
            chip.chip.advance(next(lengths))
    return done, differ, notes


def scenarios() -> dict[str, tuple[int, list[tuple[int, int, int]]]]:
    """Per scenario: its frames and (frame, shared offset, value) injections."""
    out: dict[str, tuple[int, list[tuple[int, int, int]]]] = {"attract": (3000, [])}
    for sequence in MUSIC_IDS:
        rows = [(BOOT_FRAMES, vm.COMMANDS, vm.START_BIT | sequence)]
        frame = BOOT_FRAMES
        for section in (1, 2, 3):
            frame += SECTION_FRAMES
            rows.append((frame, vm.VARS + 2 * SECTION_VAR, section))
        frame += SECTION_FRAMES
        rows.append((frame, vm.COMMANDS, vm.RUN_BIT | FADE_BIT | sequence))
        frame += FADE_FRAMES
        rows.append((frame, vm.COMMANDS, vm.START_BIT | sequence))
        frame += FADE_FRAMES
        rows.append((frame, vm.COMMANDS, sequence))              # bit 15 clear on a running channel stops it
        out[f"music_{sequence:02x}"] = (frame + TAIL_FRAMES, rows)
    for name, channel, sequence, wave_var, level_var, level, echo_var in SFX_PLAYERS:
        rows = []
        frame = BOOT_FRAMES
        for wave in SFX_WAVES:
            rows.append((frame, vm.VARS + 2 * wave_var, wave))
            rows.append((frame, vm.VARS + 2 * level_var, level))
            if echo_var is not None:
                rows.append((frame, vm.VARS + 2 * echo_var, wave & 1))
            rows.append((frame, vm.COMMANDS + 2 * channel, vm.START_BIT | sequence))
            frame += SFX_SPACING
        out[name] = (frame + TAIL_FRAMES, rows)
    rows = []
    frame = BOOT_FRAMES
    for sequence in FIXED_SEQUENCES:
        rows.append((frame, vm.COMMANDS + 2 * FIXED_CHANNEL, vm.START_BIT | sequence))
        frame += TAIL_FRAMES
    out["sfx_fixed"] = (frame + TAIL_FRAMES, rows)
    name, channel, sequence, wave_var, level_var, level, _ = SFX_PLAYERS[0]
    rows = []
    frame = BOOT_FRAMES
    for wave in HIGH_WAVES:
        rows += [(frame, vm.VARS + 2 * wave_var, wave), (frame, vm.VARS + 2 * level_var, level),
                 (frame, vm.COMMANDS + 2 * channel, vm.START_BIT | sequence)]
        frame += SFX_SPACING
    out["sfx_high"] = (frame + TAIL_FRAMES, rows)
    rows = []
    frame = BOOT_FRAMES
    for wave in LONG_WAVES:
        rows += [(frame, vm.VARS + 2 * wave_var, wave), (frame, vm.VARS + 2 * level_var, level),
                 (frame, vm.COMMANDS + 2 * channel, vm.START_BIT | sequence)]
        frame += LONG_SPACING
    out["sfx_long"] = (frame + TAIL_FRAMES, rows)
    return out


def capture_one(mame: str, name: str, frames: int, rows: list[tuple[int, int, int]], out_dir: Path, wav: Path | None = None) -> None:
    inject = out_dir / f"{name}.inject"
    inject.write_text("".join(f"{f} {o:x} {v:x}\n" for f, o, v in rows))
    env = dict(os.environ, LOG_FILE=str(out_dir / f"{name}.txt"), LAST_FRAME=str(frames), INJECT_FILE=str(inject))
    if rows:
        env["MUTE_MAIN"] = str(MUTE_MAIN_FRAME)
    sound = [] if wav is None else ["-wavwrite", str(wav), "-samplerate", str(arcade_c352.SAMPLE_RATE)]
    subprocess.run([mame, "tekken3", "-rompath", str(ROMPATH), "-video", "none", "-sound", "none", "-nothrottle", "-skip_gameinfo",
                    "-autoboot_script", str(LUA), "-autoboot_delay", "0", "-cfg_directory", "cfg", "-nvram_directory", "nvram",
                    "-snapshot_directory", "snap", *sound], cwd=AUDIO_DIR, env=env, check=True, capture_output=True)
    inject.unlink()
    log.info("captured %s (%d frames)", name, frames)


def capture(mame: str, jobs: int, only: str) -> None:
    DEFAULT_LOG_DIR.mkdir(parents=True, exist_ok=True)
    with ThreadPoolExecutor(jobs) as pool:
        for future in [pool.submit(capture_one, mame, name, frames, rows, DEFAULT_LOG_DIR)
                       for name, (frames, rows) in scenarios().items() if only in name]:
            future.result()


def _band(x: np.ndarray, low: float, high: float) -> np.ndarray:
    spectrum = np.fft.rfft(x)
    frequencies = np.fft.rfftfreq(len(x), 1 / arcade_c352.SAMPLE_RATE)
    spectrum[(frequencies < low) | (frequencies >= high)] = 0
    return np.fft.irfft(spectrum, len(x))


def _window_match(mine: np.ndarray, theirs: np.ndarray) -> tuple[float, float, int]:
    """The median correlation and gain of `theirs` against `mine` over short windows, each at its best local lag, and
    the windows that had any sound."""
    scores, gains = [], []
    size, search = MIX_CHECK_WINDOW, MIX_CHECK_SEARCH
    for at in range(MIX_CHECK_SKIP, min(len(mine), len(theirs)) - size - search, size):
        x = mine[at:at + size]
        if np.sqrt(np.mean(x * x)) < MIX_CHECK_QUIET:
            continue
        y = theirs[at - search:at + size + search]
        n = 2 * (size + search)
        lags = np.fft.irfft(np.fft.rfft(y, n) * np.conj(np.fft.rfft(x, n)), n)[:2 * search + 1]
        z = y[int(np.argmax(lags)):][:size]
        scores.append(float(np.corrcoef(x, z)[0, 1]))
        gains.append(float(x @ z) / float(x @ x))
    if not scores:
        return 0.0, 0.0, 0
    return float(np.median(scores)), float(np.median(gains)), len(scores)


def mix_check(mame: str, wave_rom: bytes, scenario: str) -> bool:
    """The chip's mix of a scenario's register writes against MAME's own output (`-wavwrite`), in the band the shared
    noise generator stays out of. Over short windows: MAME applies a write to the chip at its current timeslice's time, so
    notes wander against each other by tens of samples and a whole-song correlation says nothing above the bass."""
    MIX_DIR.mkdir(parents=True, exist_ok=True)
    wav_path = MIX_DIR / f"{scenario}.wav"
    frames, rows = scenarios()[scenario]
    frames = min(frames, MIX_CHECK_FRAMES)
    if not wav_path.exists():
        capture_one(mame, scenario, frames, rows, MIX_DIR, wav_path)
    ticks, boot = parse(MIX_DIR / f"{scenario}.txt")
    chip = arcade_c352.Chip(wave_rom)
    for reg, value in boot.writes:
        chip.write(reg, value)
    blocks = []
    for tick, length in zip(ticks, tick_lengths(len(ticks))):
        for reg, value in tick.writes:
            chip.write(reg, value)
        blocks.append(chip.advance(length))
    mine = np.concatenate(blocks).astype(np.float64) / (1 << arcade_c352.MIX_GAIN_SHIFT)
    with wave_file.open(str(wav_path), "rb") as w:
        channels = w.getnchannels()
        theirs = np.frombuffer(w.readframes(w.getnframes()), dtype="<i2").reshape(-1, channels).astype(np.float64)
    if len(theirs) < MIX_CHECK_SKIP + MIX_CHECK_WINDOW or len(mine) < MIX_CHECK_SKIP + MIX_CHECK_WINDOW:
        log.error("mix check: too little audio (%d, %d samples)", len(mine), len(theirs))
        return False
    # The log's ticks start when the driver's clock first runs, the WAV with the machine.
    window = mine[MIX_CHECK_SKIP:MIX_CHECK_SKIP + arcade_c352.SAMPLE_RATE, 0]
    size = 2 * len(theirs)
    correlation = np.fft.irfft(np.fft.rfft(theirs[:, 0], size) * np.conj(np.fft.rfft(window, size)), size)
    offset = int(np.argmax(correlation[:len(theirs)])) - MIX_CHECK_SKIP
    log.info("mix %s: the WAV is %d samples ahead", scenario, offset)
    if offset < 0:
        log.error("mix check: no offset found")
        return False
    n = min(len(mine), len(theirs) - offset)
    ok = True
    for channel, name in enumerate(("left", "right")):
        a = _band(mine[:n, channel], *MIX_CHECK_BAND)
        b = _band(theirs[offset:offset + n, channel], *MIX_CHECK_BAND)
        score, gain, windows = _window_match(a, b)
        log.info("mix %s, %s: median correlation %.4f, gain %.4f over %d windows", scenario, name, score, gain, windows)
        if score < MIX_CHECK_MINIMUM or not MIX_CHECK_GAIN[0] <= gain <= MIX_CHECK_GAIN[1]:
            ok = False
        # The negative control: the same mix half a second late has to fail.
        late, _, _ = _window_match(a[:-MIX_CHECK_LATE], b[MIX_CHECK_LATE:])
        log.info("mix %s, %s, %d samples late: median correlation %.4f", scenario, name, MIX_CHECK_LATE, late)
        if late >= MIX_CHECK_MINIMUM:
            ok = False
    return ok


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--zip", type=Path, default=ROOT / "tekken3_mame.zip")
    ap.add_argument("--logs", type=Path, nargs="*", default=None)
    ap.add_argument("--own-chip", action="store_true")
    # The chip here does not run in step with MAME's to the sample (MAME applies a write at its timeslice's time, and its
    # ticks alternate in length): a voice can end one of the driver's looks (2 ticks) apart, and the next note then
    # takes another free voice until that voice's next end. Only such differences are what remains.
    ap.add_argument("--own-chip-tolerance", type=float, default=4.0)
    ap.add_argument("--skip-negative", action="store_true")
    ap.add_argument("--capture", action="store_true", help="run MAME over the scenarios first")
    ap.add_argument("--capture-only", default="", help="only the scenarios whose name holds this")
    ap.add_argument("--mame", default="mame")
    ap.add_argument("--mix-check", default="", help="also compare the chip's mix of this scenario with MAME's WAV")
    ap.add_argument("--jobs", type=int, default=8)
    args = ap.parse_args()
    if args.capture:
        capture(args.mame, args.jobs, args.capture_only)
    program, wave = arcade.sound_chips(args.zip)
    paths = args.logs if args.logs else sorted(DEFAULT_LOG_DIR.glob("*.txt"))
    if not paths:
        log.error("no logs: capture with arcade_sound_log.lua into %s", DEFAULT_LOG_DIR)
        return 2
    ok = True
    busiest: tuple[list[Tick], Tick] | None = None
    busiest_writes = -1
    total_ticks = total_writes = 0
    for path in paths:
        ticks, boot = parse(path)
        done, differ, notes = replay(ticks, boot, program)
        writes = sum(len(t.writes) for t in ticks)
        if writes > busiest_writes:
            busiest, busiest_writes = (ticks, boot), writes
        total_ticks += done
        total_writes += writes
        if differ:
            ok = False
            log.error("%s: FAILED after %d of %d ticks\n%s", path.name, done, len(ticks), "\n".join(notes))
        else:
            log.info("%s: %d ticks, %d register writes, %d flag reads: identical", path.name, done, writes,
                     sum(len(t.reads) for t in ticks))
        if args.own_chip:
            done, differ, notes = replay(ticks, boot, program, wave)
            share = 100 * differ / max(done, 1)
            log.info("%s, own chip: %d of %d ticks differ (%.2f%%)", path.name, differ, done, share)
            for note in notes:
                log.info("  %s", note)
            if share > args.own_chip_tolerance:
                ok = False
                log.error("%s, own chip: above the tolerance of %.1f%%", path.name, args.own_chip_tolerance)
    log.info("total: %d ticks, %d register writes", total_ticks, total_writes)
    if not args.skip_negative and busiest is not None:
        ticks, boot = busiest
        altered = bytearray(program)
        for i in range(vm.FREQ_TABLE, vm.FREQ_TABLE + 256, 2):
            altered[i + 1] ^= 1
        controls: list[tuple[str, dict]] = [("a wrong sequence number", {"wrong_sequence": True}),
                                            ("commands two ticks late", {"late_commands": True}),
                                            ("a wrong frequency table", {"program": bytes(altered)})]
        for label, change in controls:
            used = {"ticks": ticks, "boot": boot, "program": program} | change
            _, differ, notes = replay(**used)
            if differ:
                log.info("negative control (%s) fails as it must: %s", label, notes[0].splitlines()[0])
            else:
                ok = False
                log.error("negative control FAILED TO FAIL: %s went unnoticed", label)
    if args.mix_check and not mix_check(args.mame, wave, args.mix_check):
        ok = False
    log.info("RESULT: %s", "PASS" if ok else "FAIL")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
