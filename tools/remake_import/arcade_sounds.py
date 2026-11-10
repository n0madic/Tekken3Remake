"""The arcade's music and sounds, rendered from the sound chips' ROMs with the driver's port.

Music (`music/arcade.json`, group `music`): each sequence runs in `arcade_sound_vm` over `arcade_c352`, one file per
section (and part, with `music_parts`). A BGM is an intro and up to three more sections: the main CPU writes the section variable and the
melody and drums jump to the section's own loop at one of their calls. In most BGMs a polling channel sees the
write and, a while later, sets a gate variable those calls test; in others they test the section variable itself,
and in many both kinds do, a bar apart. By default a section is one file, which changes at the bar of the jump
that decides it: the channels that go before it do so a bar late. With `music_parts` (`--music-parts`) the
channels that go together are a part, with a file of their own, and each changes at its own bar, at the cost of
about 70 % more music (a part costs Vorbis about as much as the whole mix). The table gives each part's loop
start, the times of those tests (the cues) and how long the gate takes to get through
(docs/research/arcade/audio-and-effects.md#sections).

Converted next to a disc (`--arcade`), only the BGMs are, with the PlayStation tracks they stand for (`ps_tracks`):
the ARCADE soundtrack plays a fight's track as its arcade BGM, a section further each round
(docs/research/arcade/audio-and-effects.md#merged-music).

Sounds (`sounds/arcade.json`, `sounds/w<wave>.wav`): the samples as they are, at their rates. What the
player sequences do with them (which C352 voice, when, how loud, the echoes and the chained name of a
winner) is read by running them, so that the runtime keeps a plan per request and no number of the scripts.
"""

from __future__ import annotations

import hashlib
import logging
import os
import struct
import zlib
from collections.abc import Callable, Iterable, Sequence
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field, replace
from typing import Any

import numpy as np

import arcade_c352 as c352
import arcade_sound_vm as vm
import media
import sounds as psx_sounds
from common import Output

log = logging.getLogger("arcade_sounds")

TICK_RATE = vm.TICK_RATE
OUTPUT_RATE = c352.SAMPLE_RATE // 2
BOOT_LIMIT_TICKS = 2000
SCRIPT_READY_TICKS = 30          # the sequence's first steps clear the section variables
SECTION_VAR, SECTION_GATE_VAR = 0xE0, 0xE1
SECTIONS = 4                     # the intro and the sections 1–3 the variable can name
SECTION_WAIT_TICKS = 60 * TICK_RATE      # no jump within this: the sequence has no such section
SECTION_LIMIT_TICKS = 600 * TICK_RATE    # a section that does not repeat is cut here
# After a channel that tests the section variable itself has jumped: the time a gated jump may still follow (the
# pollers set the gate 208–253 ticks after the write, the gated channels jump at their next bar).
GATE_GRACE_TICKS = 1024
SECTION_AGAIN = 2                # after the last section the variable names 2 and 3 in turn (FUN_8019EED4)
QUIET_TICKS = TICK_RATE // 4     # silence that ends a sequence which has stopped
CUE_MERGE_TICKS = 8              # tests of one bar by several channels are one cue
CROSSFADE_TICKS = 2              # the loop's seam
MASTER_GAIN = 4.0                # on top of the board's sum / 8, for music and sounds alike: the loudest section stays under full scale
FILTER_TAPS = 31
FILTER_CUTOFF = 0.45             # of the output's rate: the 2:1 filter

# Sequences the game starts as music: the BGMs (stage records) and the flow's.
BGM_SEQUENCES = range(0x10, 0x1F)
FLOW_SEQUENCES = range(0x60, 0x67)


@dataclass(frozen=True)
class PsTrack:
    """The arcade BGM a PlayStation fight track stands for."""

    sequence: int
    first_section: int = 0       # the True Ogre fight goes on in the section the Ogre scene wrote
    advance: bool = True         # the Ogre fight stays in its intro (FUN_8019EED4 skips the Ogre's BGM)


SHARED_BGM = 0x11                # the theme of the arcade's other characters (and the ARCADE soundtrack's stream 6)
OGRE_BGM = 0x1E
# PlayStation fight track (the character records' music byte, sound.md#music) → the arcade character's own BGM
# (the arcade's character records, byte +0x0B). Anna and Tiger have Nina's and Eddy's there; Doctor B. and Gon, who
# are not in the arcade, the shared theme as in the ARCADE soundtrack.
PS_TRACKS: dict[int, PsTrack] = {
    7: PsTrack(0x10), 8: PsTrack(0x12), 9: PsTrack(0x13), 10: PsTrack(0x14), 11: PsTrack(0x15), 12: PsTrack(0x16),
    13: PsTrack(0x19), 14: PsTrack(0x1B), 15: PsTrack(0x1C), 16: PsTrack(0x1D),
    17: PsTrack(SHARED_BGM), 18: PsTrack(SHARED_BGM), 19: PsTrack(SHARED_BGM), 20: PsTrack(0x17),
    21: PsTrack(OGRE_BGM, advance=False), 22: PsTrack(SHARED_BGM), 23: PsTrack(SHARED_BGM), 24: PsTrack(0x16),
    25: PsTrack(SHARED_BGM), 26: PsTrack(SHARED_BGM), 27: PsTrack(OGRE_BGM, first_section=1), 28: PsTrack(0x1C),
}


@dataclass(frozen=True)
class Route:
    """A way the main CPU asks for a sound (FUN_801A0C10, FUN_801A0CD4, FUN_801A0E80): the channel it starts,
    the player sequence on it and the variables that tell the sequence its wave and its level."""

    name: str
    player: int
    channel: int
    sequence: int
    wave_var: int
    level_var: int


ROUTES = (
    Route("system", 0, 0x14, 0x100, 0x10, 0x01),
    Route("voice", 0, 0x15, 0x101, 0x11, 0x02),
    Route("voice", 1, 0x16, 0x102, 0x12, 0x03),
    Route("sound", 0, 0x17, 0x103, 0x13, 0x04),
    Route("sound", 1, 0x18, 0x104, 0x14, 0x05),
    Route("hit", 0, 0x19, 0x105, 0x15, 0x04),
    Route("hit", 1, 0x1A, 0x106, 0x16, 0x05),
)
VOICE_LEVEL = 0x10               # FUN_801A0CD4's level
ECHO_VAR = 0x0C                  # FUN_801A0CD4, FUN_801A0E80: the replay's echoes
FIXED_SEQUENCES = (0x110, 0x111, 0x112, 0x113)       # started by number, each on the channel the flow names
FIXED_CHANNEL = 0x1E
CREDIT = Route("credit", 0, 0x17, 0x103, 0x13, 0x04)  # FUN_801B0A88: the sound player with its own wave and level
CREDIT_WAVE, CREDIT_LEVEL = 0x304, 0x30
PROBE_LIMIT_TICKS = 40 * TICK_RATE
GAIN_DIGITS = 5

FLAG_REVERSE, FLAG_LOOP, FLAG_MULAW, FLAG_LINK = 1, 2, 8, 0x20
NOTE_OF_SCRIPTS = 0x30           # every effect script plays this note
RECORD_BYTES = 10                # a wave record up to its loop word
LINK_PIECE_BYTES = 8


# ---- samples ----

def wave_record(program: bytes, wave: int) -> tuple[int, int, int, int, int, int | None]:
    """(pitch, bank, flags, start, address of the last byte, loop) of the driver's wave record (0x5A78); a linked
    sample's last byte is in its last piece."""
    table = struct.unpack_from("<H", program, vm.DIR_WAVES)[0]
    p = struct.unpack_from("<H", program, table + 2 * wave)[0]
    pitch, bank, flags, start, end = struct.unpack_from("<5H", program, p)
    if flags & FLAG_LINK:
        q = p + RECORD_BYTES
        while True:
            last_bank, piece_flags, _, end = struct.unpack_from("<4H", program, q)
            q += LINK_PIECE_BYTES
            if not piece_flags & FLAG_LINK:
                return pitch, bank, flags, start, last_bank << 16 | end, None
    loop = struct.unpack_from("<H", program, p + RECORD_BYTES)[0] if flags & FLAG_LOOP else None
    return pitch, bank, flags, start, bank << 16 | end, loop


def decode_wave(program: bytes, wave_rom: bytes, wave: int) -> tuple[np.ndarray, int | None]:
    """The sample's frames (s16, in playing order) and the frame its loop goes back to."""
    _, bank, flags, start, last, loop = wave_record(program, wave)
    first = bank << 16 | start
    if flags & FLAG_REVERSE and not flags & FLAG_LINK:
        low = first - ((start - last) & 0xFFFF)
        raw = np.frombuffer(wave_rom, dtype=np.uint8, count=first - low + 1, offset=low)[::-1]
        loop = None
    else:
        if last < first:
            last += 0x10000
        raw = np.frombuffer(wave_rom, dtype=np.uint8, count=last - first + 1, offset=first)
    if flags & FLAG_MULAW:
        pcm = c352.mulaw_table()[raw]
    else:
        pcm = raw.astype(np.int8).astype(np.int16) << 8
    frame = None
    if loop is not None:
        at = (bank << 16 | loop) - first
        frame = at if 0 <= at < len(pcm) else None
    return pcm, frame


def wave_rate(program: bytes, wave: int) -> int:
    """The sample's rate at the scripts' note: pitch word to frequency register (0x4E64), 65,536 = 88,200 Hz."""
    word = (NOTE_OF_SCRIPTS << 8) + wave_record(program, wave)[0]
    a, b = struct.unpack_from(">2H", program, vm.FREQ_TABLE + 2 * ((word >> 8) & 0x7F))
    freq = (a + ((((b - a) & 0xFFFF) * (word & 0xFF)) >> 8)) & 0xFFFF
    return max(1, round(c352.SAMPLE_RATE * freq / 65536))


# ---- the driver as a machine ----

class Machine:
    """The driver over the chip, past its boot. `at` counts its ticks; `writes` holds the last tick's register writes
    and `blocks` the mixes from tick `render_from` on: with `parts` (a part per channel) a mix per part, each voice
    in the part of the channel that holds it, or held it last (its release)."""

    def __init__(self, program: bytes, space: c352.WaveSpace, parts: Sequence[int] | None = None) -> None:
        self.chip = c352.Chip(space, render=False)
        self.writes: list[tuple[int, int]] = []
        self.render_from: int | None = None
        self.blocks: list[np.ndarray] = []
        self.parts = parts
        self._part_count = max(parts) + 1 if parts else 1
        self._voice_parts = [0] * c352.VOICES
        self.at = 0
        self.vm = vm.SoundVM(program, self)
        self.vm.boot()
        for _ in range(BOOT_LIMIT_TICKS):
            self.tick()
            if self.quiet():
                break
        self.at = 0

    def write(self, reg: int, value: int) -> None:
        self.writes.append((reg, value))
        self.chip.write(reg, value)

    def read_flags(self, voice: int) -> int:
        return self.chip.read_flags(voice)

    def tick(self) -> None:
        self.writes.clear()
        self.vm.tick()
        self.at += 1
        if self.render_from is not None:
            self.chip.render = self.at >= self.render_from
        if self.parts is not None:
            # Every tick, mixed or not: a voice its channel let go of before the mix starts still rings in its part.
            for voice, channel in enumerate(self.vm.voice_channels()):
                if channel is not None:
                    self._voice_parts[voice] = self.parts[channel]
        if self.parts is None or not self.chip.render:
            block = self.chip.advance()
        else:
            block = self.chip.advance_parts(self._voice_parts, self._part_count)
        if block is not None:
            self.blocks.append(block)

    def channel_running(self, channel: int) -> bool:
        return bool(self.vm.m[vm.COMMANDS + 2 * channel] & (vm.RUN_BIT >> 8))

    def running(self) -> bool:
        return any(self.channel_running(ch) for ch in range(vm.CHANNELS))

    def quiet(self) -> bool:
        return not self.running() and not any(v.flags & c352.BUSY for v in self.chip.voices)

    def signature(self) -> bytes:
        """What the scripts do next, relative to now: equal signatures repeat each other. The section variables
        do not count, so that two sections on the same code compare equal."""
        driver = self.vm
        m = driver.m
        variables = bytearray(m[vm.VARS:vm.VARS + 0x200])
        variables[2 * SECTION_VAR:2 * SECTION_GATE_VAR + 2] = bytes(4)
        parts = [bytes(variables)]
        for ch in range(vm.CHANNELS):
            chan = vm.CHANNEL_BASE + vm.CHANNEL_BYTES * ch
            if m[chan + 0xA] & (vm.RUN_BIT >> 8):
                due = ((m[chan] << 8 | m[chan + 1]) - driver.time) & 0xFFFF
                parts.append(bytes((ch, due >> 8, due & 0xFF)))
                parts.append(bytes(m[chan + 0x10:chan + 0x50]))
        return hashlib.blake2b(b"".join(parts), digest_size=16).digest()


# ---- sections ----

@dataclass(frozen=True)
class Jump:
    """How a sequence goes into a section once the main CPU writes its number."""

    ticks: int                   # from the write to the end of the tick the first channel jumped in
    delay: int                   # from the write until the gate variable changed; 0 when the channels test the number
    variable: int                # what the jumping channels test: the gate variable, or the section variable itself
    # From the write until the next write may come. The game writes once a round; the search writes as soon as the
    # sequence has gone over: at the gated jump, as the gate holds the number for the others, but GATE_GRACE_TICKS
    # after a jump on the section variable itself, as the other channels test it a tick or a bar later.
    settled: int
    # Each channel's own jump (pollers' too): (channel, the variable it tested, ticks from the write to the end of
    # the tick it jumped in).
    channels: tuple[tuple[int, int, int], ...] = ()


@dataclass(frozen=True)
class Part:
    """Channels that go into every section at the same bar, testing the same variable. In most BGMs some channels
    test the section variable and go a bar before those that wait for the gate
    (docs/research/arcade/audio-and-effects.md#sections): a file per part lets each change when its channels do."""

    moves: tuple[tuple[int, int], ...]   # per jump: the variable its channels test, the ticks from the write to theirs
    channels: frozenset[int]             # the first part's are every channel of no other part


@dataclass(frozen=True)
class Chain:
    """A sequence's way through its sections 1, 2, 3 (as far as it goes) and the channels that only poll."""

    jumps: tuple[Jump, ...]
    pollers: frozenset[int]      # channels that answer the section variable by setting the gate variable
    parts: tuple[Part, ...] = ()  # the first moves with the jumps above

    def part_of(self, channel: int) -> int:
        return next((i for i, part in enumerate(self.parts) if i and channel in part.channels), 0)

    def channel_parts(self) -> list[int] | None:
        """Per channel its part; None where the channels make one part."""
        return [self.part_of(ch) for ch in range(vm.CHANNELS)] if len(self.parts) > 1 else None

    def whole(self) -> Chain:
        """Every channel in the first part: one file per section, changing at the decisive jump's bar."""
        if len(self.parts) <= 1:
            return self
        return replace(self, parts=(Part(self.parts[0].moves, frozenset(range(vm.CHANNELS))),))


@dataclass
class SectionPlan:
    """A section's run, on the machine's clock: the mix of tick `entry` is the file's first."""

    sequence: int
    section: int
    entry: int
    loop_start: int | None       # the tick a loop goes back to
    end: int                     # the first tick after the file
    jumps: tuple[Jump, ...] = ()  # the jumps into sections 1 … `section`
    entry_signature: bytes = b""
    signatures: frozenset[bytes] = frozenset()
    moves: tuple[int, ...] = (0,)  # per part of the chain: the ticks from the last write to its channels' jump
    entries: tuple[int, ...] = ()  # per part: the first tick of its file (part 0's is `entry`)
    tests: dict[int, dict[int, list[int]]] = field(default_factory=dict)  # by variable and channel: its tests' ticks

    @property
    def start(self) -> int:
        """The first tick of any part."""
        return min(self.entries, default=self.entry)

    @property
    def cues(self) -> dict[int, list[int]]:
        """By variable: a tick per bar that tests it, in [entry, end), by every channel (the pollers left out)."""
        return {variable: _cues([t for ticks in by_channel.values() for t in ticks], self.entry, self.end)
                for variable, by_channel in self.tests.items()}

    @property
    def delay(self) -> int:
        """Ticks from the section variable's write until the gate variable changes (0 for the intro)."""
        return self.jumps[-1].delay if self.jumps else 0


def _start(machine: Machine, sequence: int) -> None:
    machine.vm.command(0, vm.START_BIT | sequence)
    for _ in range(SCRIPT_READY_TICKS):
        machine.tick()


def _replay(machine: Machine, jumps: Sequence[Jump], last: int | None = None) -> int:
    """Asks for sections 1, 2 … in turn, each when the sequence has settled in the last; stops `last` ticks after
    the last write (at its jump by default). Returns the last write's tick.

    TODO: the game writes once a round, and some channels carry what they did into the next section (0x1E's
    channel 2 in section 3; notes still ringing in a file's first bars): writing after the last section's loop
    has come round may match play better (docs/research/arcade/audio-and-effects.md#what-the-converter-writes)."""
    written = machine.at
    for stage, jump in enumerate(jumps, 1):
        written = machine.at
        machine.vm.set_var(SECTION_VAR, stage)
        until = (jump.ticks if last is None else last) if stage == len(jumps) else jump.settled
        while machine.at < written + until:
            machine.tick()
    return written


def _next_jump(machine: Machine, stage: int, pollers: set[int]) -> Jump | None:
    """Writes the section variable and runs until the sequence goes there. Some channels test the gate variable a
    poller sets about a bar later, some the section variable itself, and in some sequences both kinds jump: the first
    gated jump wins, as the gated channels carry the melody (docs/research/arcade/audio-and-effects.md#sections).
    A jump on the variable itself counts only when no gated jump follows it within GATE_GRACE_TICKS."""
    written = machine.at
    machine.vm.set_var(SECTION_VAR, stage)
    gated: list[int] = []
    leads: dict[int, int] = {}
    taken_by: dict[int, tuple[int, int]] = {}    # each channel's first jump: its variable, its tick

    def watch(channel: int, variable: int, taken: bool) -> None:
        if not taken or variable not in (SECTION_VAR, SECTION_GATE_VAR) or machine.vm.var(variable) != stage:
            return
        tick = machine.at + 1                    # it runs in the tick about to be counted
        taken_by.setdefault(channel, (variable, tick))
        if variable == SECTION_GATE_VAR and not gated:
            gated.append(tick)
        elif variable == SECTION_VAR:
            leads.setdefault(channel, tick)

    machine.vm.on_compare = watch
    gate_seen = None
    jump = None
    while jump is None:
        machine.tick()
        if gate_seen is None and machine.vm.var(SECTION_GATE_VAR) == stage:
            gate_seen = machine.at
        if gated:
            ticks = gated[0] - written
            jump = Jump(ticks, 0 if gate_seen is None else gate_seen - written, SECTION_GATE_VAR, ticks)
            break
        lead = min((t for channel, t in leads.items() if channel not in pollers), default=None)
        timed_out = machine.at - written > SECTION_WAIT_TICKS or not machine.running()
        if lead is not None and (machine.at - lead > GATE_GRACE_TICKS or timed_out):
            jump = Jump(lead - written, 0, SECTION_VAR, lead - written + GATE_GRACE_TICKS)
        elif timed_out:
            return None
    # The channels that go over later still (only noted: the replays write the next number at `settled`, and a
    # tick later is another way through some BGMs, 0x15's section 3).
    while machine.at < written + jump.ticks + GATE_GRACE_TICKS and machine.running():
        machine.tick()
    channels = tuple(sorted((channel, variable, tick - written) for channel, (variable, tick) in taken_by.items()))
    return replace(jump, channels=channels)


def _parts(jumps: Sequence[Jump], pollers: frozenset[int]) -> tuple[Part, ...]:
    """The channels grouped by how they go into each section: at one jump, those that test the same variable within
    CUE_MERGE_TICKS of each other go together; a channel that does not jump goes with the jump's own channels."""
    main: list[tuple[int, int]] = []
    rows: dict[int, list[tuple[int, int] | None]] = {}
    for stage, jump in enumerate(jumps):
        own = (jump.variable, jump.ticks)
        last: dict[int, tuple[int, tuple[int, int]]] = {}
        for ticks, variable, channel in sorted((t, v, c) for c, v, t in jump.channels if c not in pollers):
            before = last.get(variable)
            move = before[1] if before is not None and ticks - before[0] <= CUE_MERGE_TICKS else (variable, ticks)
            last[variable] = (ticks, move)
            rows.setdefault(channel, [None] * len(jumps))[stage] = move
            if (variable, ticks) == (jump.variable, jump.ticks):
                own = move
        main.append(own)
    together: dict[tuple[tuple[int, int], ...], set[int]] = {}
    for channel, row in rows.items():
        moves = tuple(main[stage] if move is None else move for stage, move in enumerate(row))
        together.setdefault(moves, set()).add(channel)
    first = tuple(main)
    others = sorted(((moves, channels) for moves, channels in together.items() if moves != first),
                    key=lambda item: min(item[1]))
    return (Part(first, frozenset(together.get(first, ()))),
            *(Part(moves, frozenset(channels)) for moves, channels in others))


def explore_sections(program: bytes, space: c352.WaveSpace, sequence: int) -> Chain:
    """Asks for sections 1, 2, 3 in turn, each as soon as the sequence has settled in the last, and finds how each is
    entered. Each search starts again from the sequence's start, as the search runs past the jump."""
    jumps: list[Jump] = []
    pollers: set[int] = set()
    for stage in range(1, SECTIONS):
        machine = Machine(program, space)

        def answered(channel: int, variable: int, driver: vm.SoundVM = machine.vm) -> None:
            if variable == SECTION_GATE_VAR and driver.var(SECTION_GATE_VAR) != 0:   # the scripts clear it as they start
                pollers.add(channel)

        machine.vm.on_variable = answered
        _start(machine, sequence)
        _replay(machine, jumps)
        jump = _next_jump(machine, stage, pollers)
        if jump is None:
            break
        jumps.append(jump)
    return Chain(tuple(jumps), frozenset(pollers), _parts(jumps, frozenset(pollers)))


def _part_entries(machine: Machine, sequence: int, jumps: Sequence[Jump], moves: Sequence[int]) -> tuple[int, ...]:
    """Starts the sequence and takes `jumps`, up to the first tick of the part that goes first; returns each part's
    first tick (`moves`: the ticks from the last write to each part's jump)."""
    if not jumps:
        machine.vm.command(0, vm.START_BIT | sequence)
        return (1,) * len(moves)
    _start(machine, sequence)
    written = _replay(machine, jumps, min(moves))
    return tuple(written + move for move in moves)


def _cues(tests: Iterable[int], entry: int, end: int) -> list[int]:
    """One per bar: several channels test it within a few ticks; the section's first test is its jump."""
    cues: list[int] = []
    last = entry
    for t in sorted(t for t in tests if entry <= t < end):
        if t - last > CUE_MERGE_TICKS:
            cues.append(t)
        last = t
    return cues


def analyse_section(program: bytes, space: c352.WaveSpace, sequence: int, section: int,
                    chain: Chain | None = None) -> SectionPlan | None:
    """Runs the section without its sound: where it starts, repeats and ends. `chain` is `explore_sections`'s."""
    if chain is None:
        chain = explore_sections(program, space, sequence)
    if section > len(chain.jumps):
        return None
    jumps = chain.jumps[:section]
    parts = chain.parts or (Part(tuple((j.variable, j.ticks) for j in chain.jumps), frozenset()),)
    moves = tuple(part.moves[section - 1][1] for part in parts) if jumps else (0,) * len(parts)
    machine = Machine(program, space)
    entries = _part_entries(machine, sequence, jumps, moves)
    entry, latest = entries[0], max(entries)
    tests: dict[int, dict[int, list[int]]] = {SECTION_VAR: {}, SECTION_GATE_VAR: {}}

    def watch(channel: int, variable: int, _taken: bool) -> None:
        if variable in tests and channel not in chain.pollers:
            tests[variable].setdefault(channel, []).append(machine.at + 1)   # it runs in the tick about to be counted

    machine.vm.on_compare = watch
    seen: dict[bytes, int] = {}
    per_tick: dict[int, int] = {}
    first = period = None
    entry_signature = machine.signature()
    repeated: set[bytes] = set()
    silent = 0
    while machine.at - entry < SECTION_LIMIT_TICKS:
        if machine.running():
            signature = machine.signature()
            if first is None:
                if signature in seen:
                    first, period = seen[signature], machine.at - seen[signature]
                else:
                    seen[signature] = machine.at
            if first is not None:
                repeated.add(signature)
                if machine.at >= first + 2 * period:
                    break
        elif first is not None:          # it stopped after all
            first = period = None
        machine.tick()
        per_tick[machine.at] = zlib.crc32(repr(machine.writes).encode())
        silent = silent + 1 if machine.quiet() else 0
        if silent >= QUIET_TICKS:
            break
    if first is None or period is None:
        end = max(latest + 1, machine.at - silent + 1)
        return SectionPlan(sequence, section, entry, None, end, jumps, entry_signature, moves=moves, entries=entries,
                           tests=tests)
    # The loop starts where the writes start to repeat: before that, the notes of what came before still ring. Every
    # part has entered by then (the run repeats from `first`, which may come before a late part's entry).
    start = max(first + period, latest + 1)
    while start > latest + 1 and per_tick.get(start - 1) == per_tick.get(start - 1 + period):
        start -= 1
    end = start + period
    return SectionPlan(sequence, section, entry, start, end, jumps, entry_signature, frozenset(repeated), moves, entries,
                       tests)


def part_cues(plan: SectionPlan, chain: Chain, part: int, stage: int | None) -> list[int]:
    """The part's cues for the jump into `stage`: the tests of the variable its channels test there, by every channel
    that jumps with them, from the part's first tick (with no such jump: every channel's tests of the gate)."""
    if stage is None:
        ticks = [t for by_channel in plan.tests[SECTION_GATE_VAR].values() for t in by_channel]
    else:
        move = chain.parts[part].moves[stage - 1]
        ticks = [t for channel, by_channel in plan.tests[move[0]].items()
                 if chain.parts[chain.part_of(channel)].moves[stage - 1] == move for t in by_channel]
    return _cues(ticks, plan.entries[part], plan.end)


def _seal_loop(mix: np.ndarray, plan: SectionPlan, entry: int) -> np.ndarray:
    """A loop's seam: the first samples after its start fade in from what really follows its end. `mix` starts at
    tick `entry`."""
    if plan.loop_start is None:
        return mix
    samples = c352.TICK_SAMPLES
    at = (plan.loop_start - entry) * samples
    end = (plan.end - entry) * samples
    n = CROSSFADE_TICKS * samples
    weight = np.linspace(0.0, 1.0, n, endpoint=False)[:, None]
    sealed = mix.astype(np.float64)
    sealed[at:at + n] = sealed[end:end + n] * (1.0 - weight) + sealed[at:at + n] * weight
    return sealed[:end]


def render_parts(program: bytes, space: c352.WaveSpace, plan: SectionPlan,
                 channel_parts: Sequence[int] | None = None) -> list[np.ndarray]:
    """The section's samples per part (stereo, the chip's rate, the chip's sum), each from its part's first tick: the
    same run with the mix on. Without `channel_parts` one mix of every channel, from `plan.entry`."""
    machine = Machine(program, space, channel_parts)
    machine.render_from = plan.start
    entries = _part_entries(machine, plan.sequence, plan.jumps, plan.moves)
    if plan.entries and entries != plan.entries:
        raise vm.SoundVmError(f"sequence {plan.sequence:#x}: section {plan.section} runs differently the second time")
    end = plan.end + (CROSSFADE_TICKS if plan.loop_start is not None else 0)
    while machine.at < end:
        machine.tick()
    if channel_parts is None:
        mixes, firsts = [np.concatenate(machine.blocks)], [plan.entry]
    else:
        mixes, firsts = list(np.concatenate(machine.blocks, axis=1)), list(plan.entries)
    return [_seal_loop(mix[(entry - plan.start) * c352.TICK_SAMPLES:], plan, entry) for mix, entry in zip(mixes, firsts)]


def render_section(program: bytes, space: c352.WaveSpace, plan: SectionPlan) -> np.ndarray:
    """The section's samples, every channel in one mix from `plan.entry`."""
    return render_parts(program, space, plan)[0]


def to_output(mix: np.ndarray) -> np.ndarray:
    """The chip's sum to 16-bit samples at half its rate."""
    taps = np.arange(FILTER_TAPS) - (FILTER_TAPS - 1) / 2
    fir = np.sinc(taps * FILTER_CUTOFF) * np.hamming(FILTER_TAPS)
    fir /= fir.sum()
    left, right = (np.convolve(mix[:, side], fir, mode="same")[::2] for side in (0, 1))
    scaled = np.stack((left, right), axis=1) * MASTER_GAIN / (1 << c352.MIX_GAIN_SHIFT)
    return np.clip(np.rint(scaled), -32768, 32767).astype("<i2")


# ---- parallel jobs ----

_program = b""
_space: c352.WaveSpace | None = None


def _worker(program: bytes, wave_rom: bytes) -> None:
    global _program, _space
    _program = program
    _space = c352.WaveSpace(wave_rom)


def _parallel(function: Callable[[Any], Any], jobs: Sequence[Any], program: bytes, wave_rom: bytes, workers: int) -> list[Any]:
    if workers <= 1 or len(jobs) <= 1:
        _worker(program, wave_rom)
        return [function(job) for job in jobs]
    with ProcessPoolExecutor(min(workers, len(jobs)), initializer=_worker, initargs=(program, wave_rom)) as pool:
        return list(pool.map(function, jobs))


def _explore_job(sequence: int) -> Chain:
    assert _space is not None
    return explore_sections(_program, _space, sequence)


def _analyse_job(job: tuple[int, int, Chain]) -> SectionPlan | None:
    assert _space is not None
    return analyse_section(_program, _space, *job)


def _render_job(job: tuple[SectionPlan, Sequence[int] | None, media.FFmpeg | None]) -> tuple[list[tuple[bytes, str, int]], int]:
    """Per part the section's file, its extension, its frames; the peak of the parts' sum."""
    plan, channel_parts, tool = job
    assert _space is not None
    entries = plan.entries if channel_parts is not None else (plan.entry,)
    # Every part on the first one's grid at half the chip's rate: one whose start is an odd count of the chip's
    # samples from it starts a sample earlier (a few µs), or the parts would be half a sample apart.
    firsts = [(entry - plan.entry) * c352.TICK_SAMPLES for entry in entries]
    pcms = [to_output(np.pad(mix, ((first % 2, 0), (0, 0))))
            for mix, first in zip(render_parts(_program, _space, plan, channel_parts), firsts)]
    offsets = [first // 2 - min(firsts) // 2 for first in firsts]
    total = np.zeros((max((o + len(pcm) for o, pcm in zip(offsets, pcms)), default=0), 2), np.int32)
    for offset, pcm in zip(offsets, pcms):
        total[offset:offset + len(pcm)] += pcm
    peak = int(np.abs(total).max(initial=0))
    files = []
    for pcm, entry, first in zip(pcms, entries, firsts):
        if tool is not None and tool.ogg:
            files.append((media._vorbis(tool, pcm.tobytes(), OUTPUT_RATE, 2), "ogg", len(pcm)))
            continue
        loop = None
        if plan.loop_start is not None:
            loop = (((plan.loop_start - entry) * c352.TICK_SAMPLES + first % 2) // 2, len(pcm))
        files.append((media.wav_bytes(pcm.tobytes(), OUTPUT_RATE, 2, loop), "wav", len(pcm)))
    return files, peak


# ---- music ----

def sequence_groups(program: bytes, sequences: Iterable[int]) -> dict[int, int]:
    """Per sequence the first of those with the same script."""
    table = struct.unpack_from("<H", program, vm.DIR_SEQUENCES)[0]
    firsts: dict[bytes, int] = {}
    return {s: firsts.setdefault(program[table + 3 * s:table + 3 * s + 3], s) for s in sequences}


def same_section(a: SectionPlan | None, b: SectionPlan | None) -> bool:
    return a is not None and b is not None and a.entry_signature == b.entry_signature and a.signatures == b.signatures


def next_section(section: int) -> int:
    """The section the next write of the variable asks for: 1, 2, 3, then 2 and 3 in turn."""
    return section + 1 if section + 1 < SECTIONS else SECTION_AGAIN


def part_row(kept: SectionPlan, part: int, cues: Sequence[int], delay: int, name: str, frames: int) -> dict:
    """A part's file in a section's row, its times in seconds of the file: its cues are the ticks its channels may
    jump to the next section at, `delay` the ticks from the write until they may."""
    entry = kept.entries[part]
    return {
        "file": name,
        "length": frames / OUTPUT_RATE,
        "loop": None if kept.loop_start is None else (kept.loop_start - entry) / TICK_RATE,
        "cues": [(c - entry) / TICK_RATE for c in cues],
        "delay": delay / TICK_RATE,
    }


def convert_music(program: bytes, wave_rom: bytes, out: Output, tool: media.FFmpeg | None,
                  sequences: Iterable[int] = (*BGM_SEQUENCES, *FLOW_SEQUENCES), workers: int | None = None,
                  ps_tracks: dict[int, PsTrack] | None = None, music_parts: bool = False) -> None:
    """`ps_tracks`: the PlayStation tracks the sequences stand for (a conversion next to a disc); those whose
    sequence is not converted are left out. `music_parts`: a file per part, else per section."""
    workers = workers or os.cpu_count() or 1
    groups = sequence_groups(program, sequences)
    firsts = sorted(set(groups.values()))
    chains = {s: chain if music_parts else chain.whole()
              for s, chain in zip(firsts, _parallel(_explore_job, firsts, program, wave_rom, workers))}
    jobs = [(s, k, chains[s]) for s in firsts for k in range(SECTIONS) if k <= len(chains[s].jumps)]
    plans = {(s, k): plan for (s, k, _), plan in zip(jobs, _parallel(_analyse_job, jobs, program, wave_rom, workers))
             if plan is not None}
    kept: dict[tuple[int, int], tuple[int, int]] = {}
    for (sequence, section), plan in plans.items():
        same = [k for k in range(section) if same_section(plans.get((sequence, k)), plan)]
        kept[(sequence, section)] = (sequence, same[0] if same else section)
    rendered = sorted(set(kept.values()))
    results = _parallel(_render_job, [(plans[key], chains[key[0]].channel_parts(), tool) for key in rendered],
                        program, wave_rom, workers)
    files: dict[tuple[int, int], list[tuple[str, int]]] = {}
    peaks: dict[tuple[int, int], int] = {}
    for key, (part_files, section_peak) in zip(rendered, results):
        files[key] = []
        for part, (data, extension, frames) in enumerate(part_files):
            name = f"s{key[0]:03x}_{key[1]}{f'_p{part}' if part else ''}.{extension}"
            out.write(f"music/{name}", data)
            files[key].append((name, frames))
        peaks[key] = section_peak
    tracks: dict[str, dict] = {}
    for sequence, first in groups.items():
        chain = chains[first]
        rows = []
        peak = 0
        for k in range(SECTIONS):
            plan = plans.get((first, k))
            if plan is None:
                continue
            source = plans[kept[(first, k)]]
            # The jump back from 3 to 2 is taken as the jump from 1 to 2 (`inferred`: so in every sequence run).
            after = next_section(k) if (first, next_section(k)) in plans else None
            parts = []
            for part, (name, frames) in enumerate(files[kept[(first, k)]]):
                gated = k > 0 and chain.parts[part].moves[k - 1][0] == SECTION_GATE_VAR
                cues = part_cues(source, chain, part, after)
                parts.append(part_row(source, part, cues, plan.delay if gated else 0, name, frames))
            rows.append({"section": k, "parts": parts})
            peak = max(peak, peaks[kept[(first, k)]])
        # The loudest sample of all its sections: how far a player may raise it before it clips.
        tracks[str(sequence)] = {"sections": rows, "peak": peak}
    table: dict[str, Any] = {"tracks": tracks}
    if ps_tracks is not None:
        table["ps_tracks"] = {str(track): {"sequence": t.sequence, "first_section": t.first_section, "advance": t.advance}
                              for track, t in sorted(ps_tracks.items()) if str(t.sequence) in tracks}
    out.write_json("music/arcade.json", table)
    every = [frames for part_files in files.values() for _, frames in part_files]
    log.info("arcade music: %d sequences, %d files, %.1f minutes, peak %d of 32767", len(groups), len(every),
             sum(every) / OUTPUT_RATE / 60, max(peaks.values(), default=0))


# ---- what the players do ----

@dataclass
class Probe:
    """A player sequence as it ran: the row the runtime plays and the variables its script tested."""

    row: dict
    tested: frozenset[int]


def _gain(volume_front: int) -> float:
    """The chip's two front bytes as one linear gain on the samples, on the mix's scale."""
    both = ((volume_front >> 8) + (volume_front & 0xFF)) / 2 / 256
    return round(both * MASTER_GAIN / (1 << c352.MIX_GAIN_SHIFT), GAIN_DIGITS)


def probe(program: bytes, space: c352.WaveSpace, channel: int, sequence: int, variables: dict[int, int], own_wave: int) -> Probe:
    """Runs a player sequence: its notes (tick, C352 voice, wave or -1 for the request's, gain per tick until it holds)
    and the tick its channel ends, when its voices go."""
    machine = Machine(program, space)
    driver = machine.vm
    tested: set[int] = set()
    driver.on_compare = lambda _c, variable, _t: tested.add(variable)
    for number, value in variables.items():
        driver.set_var(number, value)
    driver.command(channel, vm.START_BIT | sequence)
    notes: list[dict] = []
    sounding: dict[int, dict] = {}
    end = None
    for _ in range(PROBE_LIMIT_TICKS):
        machine.tick()
        now = machine.at - 1
        for reg, value in machine.writes:
            if reg < vm.REG_CONTROL and reg & 7 == vm.REG_FLAGS and value & vm.FLAG_KEY_ON:
                number = reg >> 3
                wave = driver._r16(vm.VOICE_BASE + vm.VOICE_BYTES * number)
                note = {"tick": now, "voice": number, "wave": -1 if wave == own_wave else wave, "gain": []}
                notes.append(note)
                sounding[number] = note
        for number, note in sounding.items():
            note["gain"].append(_gain(machine.chip.voices[number].volume_front))
        if not machine.channel_running(channel):
            end = now
            break
    for note in notes:
        gain = note["gain"]
        while len(gain) > 1 and gain[-1] == gain[-2]:
            gain.pop()
    return Probe({"channel": channel, "end": end, "notes": notes}, frozenset(tested))


def _probe_job(job: tuple[int, int, dict[int, int], int]) -> Probe:
    assert _space is not None
    return probe(_program, _space, *job)


def convert_sounds(program: bytes, wave_rom: bytes, out: Output, sound_table: Sequence[tuple[int, int]],
                   voice_waves: Iterable[int], workers: int | None = None) -> None:
    """`sound_table`: (wave, level) per 12-bit sound id; `voice_waves`: every wave of the voice sets."""
    workers = workers or os.cpu_count() or 1
    voice_waves = set(voice_waves)
    psx_sounds.drop_compressed_imports(out.root / "sounds")
    any_wave = sound_table[0][0]

    # Whether a route's script asks about its wave: that decides how many runs it takes.
    _worker(program, wave_rom)
    asks_wave = {route: route.wave_var in _probe_job((route.channel, route.sequence, {route.wave_var: any_wave, route.level_var: VOICE_LEVEL},
                                                      any_wave)).tested for route in ROUTES}
    jobs: list[tuple[int, int, dict[int, int], int]] = []
    keys: dict[tuple, int] = {}

    def job_of(route: Route, wave: int, level: int, echo: int = 0) -> int:
        key = (route, wave if asks_wave[route] else any_wave, level, echo)
        if key not in keys:
            keys[key] = len(jobs)
            jobs.append((route.channel, route.sequence, {route.wave_var: key[1], route.level_var: level, ECHO_VAR: echo}, key[1]))
        return keys[key]

    # A voice: one level, its wave from the set, with and without the replay's echoes. The others: a job per sound id.
    table: dict[str, Any] = {"sound": [None, None], "hit": [None, None], "voice": [None, None]}
    for route in ROUTES:
        if route.name == "voice":
            table["voice"][route.player] = [job_of(route, any_wave, VOICE_LEVEL, echo) for echo in (0, 1)]
        elif route.name == "system":
            table["system"] = [job_of(route, wave, level) for wave, level in sound_table]
        else:
            table[route.name][route.player] = [job_of(route, wave, level) for wave, level in sound_table]
    fixed_first = len(jobs)
    jobs += [(FIXED_CHANNEL, sequence, {}, -1) for sequence in FIXED_SEQUENCES]
    jobs.append((CREDIT.channel, CREDIT.sequence, {CREDIT.wave_var: CREDIT_WAVE, CREDIT.level_var: CREDIT_LEVEL}, -1))
    probes: list[Probe] = _parallel(_probe_job, jobs, program, wave_rom, workers)

    # The same plan for many ids is kept once.
    plans: list[dict] = []
    plan_of_key: dict[str, int] = {}
    plan_of_job: list[int] = []
    for result in probes:
        plan_of_job.append(plan_of_key.setdefault(repr(result.row), len(plans)))
        if plan_of_job[-1] == len(plans):
            plans.append(result.row)

    def plan_rows(value: Any) -> Any:
        return plan_of_job[value] if isinstance(value, int) else [plan_rows(v) for v in value]

    used = voice_waves | {wave for wave, _ in sound_table}
    used |= {note["wave"] for plan in plans for note in plan["notes"] if note["wave"] >= 0}
    waves: dict[str, str] = {}
    for wave in sorted(used):
        pcm, loop = decode_wave(program, wave_rom, wave)
        name = f"w{wave:03x}.wav"
        out.write(f"sounds/{name}", media.wav_bytes(pcm.astype("<i2").tobytes(), wave_rate(program, wave), 1,
                                                    None if loop is None else (loop, len(pcm))))
        waves[str(wave)] = name
    out.write_json("sounds/arcade.json", {
        "tick_rate": TICK_RATE,
        "waves": waves,
        "table": [wave for wave, _ in sound_table],
        "plans": plans,
        "routes": {name: plan_rows(value) for name, value in table.items()},
        "sequences": {str(sequence): plan_of_job[fixed_first + i] for i, sequence in enumerate((*FIXED_SEQUENCES, CREDIT.sequence))},
    })
    log.info("arcade sounds: %d samples, %d plans", len(waves), len(plans))
