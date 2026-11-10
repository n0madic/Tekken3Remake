"""The arcade's sound driver: a port of the H8/3002's sequence machine (program `tet1vere.11s`).

A tick (120 Hz) runs the 32 channels' scripts, then the 32 voices' pitch, volume, envelope and modulation,
and writes the C352's registers (docs/research/arcade/audio-and-effects.md#2-sequencer). The port
keeps the routine order, the state's bytes at the H8's offsets and the scratch bytes that one routine leaves
for another, because the C352 writes have to come out identical: `tools/research/verify_arcade_sound_vm.py`
compares them with MAME's, tick by tick. It reads only the program, passed in; the chip is passed
in as well (`arcade_c352.Chip`, or the verifier's replay of the chip's answers).

Only what the program's scripts reach is ported: a script walk finds the opcodes in `_OPS`, three pan modes and
four modulation shapes. What no script reaches raises `SoundVmError` instead of playing something unproven.

Addresses in the comments are the H8's. State lives in `m`, the RAM at 0x080000–0x08FFFF, big-endian:

    0x0100 + 2·ch   command word: bit 14 start, bit 15 running, bits 12–13 fade, bit 11 linked, low 11 bits the sequence
    0x0140 + 2·ch   the command word this channel's life follows (`link`)
    0x0200 + 2·i    variables, shared with the main CPU
    0x9500 + 0x50·c channel: script pointer, next-step time, call and repeat stacks
    0xA000 + 0x100·c + 0x20·t   track `t` of the channel (the fields a note copies to its voice)
    0xC000 + 0xC0·v voice: wave, pitch, envelope, modulation; a queue of 8 notes at +0x80
    0xD800 / 0xDC00 per voice and channel: the priority and the track that claim the voice
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Protocol


class SoundVmError(RuntimeError):
    """The program asked for something no script of the known set reaches."""


class ChipPort(Protocol):
    """What the driver sees of the C352."""

    def write(self, reg: int, value: int) -> None: ...
    def read_flags(self, voice: int) -> int: ...


TICK_RATE = 120              # ITU1: φ/8 with a period of 0x44E8 at 16.9344 MHz
TIME_PER_TICK = 0x40         # the driver's clock runs 0x40 units per tick
CHANNELS = 32
TRACKS = 8
VOICES = 32
COMMANDS = 0x0100
LINKS = 0x40                 # from a command word to its link word
VARS = 0x0200
VAR_LOW = 0x0201             # a variable's low byte
CHANNEL_BASE, CHANNEL_BYTES = 0x9500, 0x50
TRACK_BASE, CHANNEL_TRACKS, TRACK_BYTES = 0xA000, 0x100, 0x20
VOICE_BASE, VOICE_BYTES = 0xC000, 0xC0
VOICE_OWNERS = 0x9F00        # per voice: the track that holds it
PRIORITY_BASE = 0xD800       # 32 bytes per voice, one per channel; +0x400 the track number
PRESETS = 0xE000
QUEUE = 0x80
START_BIT, RUN_BIT, LINK_BIT = 0x4000, 0x8000, 0x0800
ID_MASK = 0x7FF

# C352 word registers: voice·8 + these.
REG_VOL_FRONT, REG_VOL_REAR, REG_FREQ, REG_FLAGS, REG_BANK, REG_START, REG_END, REG_LOOP = range(8)
REG_CONTROL = 0x200
REG_KEY = 0x202              # executes the key-ons and key-offs
FLAG_BUSY, FLAG_KEY_ON = 0x8000, 0x4000
FLAG_LOOP_HISTORY, FLAG_LINK, FLAG_LOOP = 0x0800, 0x20, 0x02

# The directory: u16le pointers at 0x8000.
DIR_SEQUENCES, DIR_WAVES, DIR_PITCH, DIR_ENVELOPES, DIR_PANS, DIR_MODULATIONS, DIR_SPLITS = (0x8000 + 2 * i for i in range(7))
FREQ_TABLE = 0x3B22          # u16be per semitone
RATE_TABLE = 0x3A22          # u16be: envelope and pan rates
PAN_SQRT = 0x3D5A            # bytes: the pan law's table
ATTENUATION = 0x6BE0         # bytes: C352 volume per attenuation step
MODULATION_WAVES = 0x3BFB    # (base, slope) per shape and quarter

# Voice routines chosen per voice, by the H8 address the driver stores.
ENV_RISE, ENV_FALL, ENV_HOLD, NO_ROUTINE = 0x5924, 0x5948, 0x5964, 0x4FBE
PAN_FIXED, PAN_TRACK_RUN, PAN_TRACK_MOVE_UP, PAN_TRACK_MOVE_DOWN = 0x4F0A, 0x5530, 0x5646, 0x565C
MODULATE = 0x4FCE
PAN_MODE_LIST_A, PAN_MODE_LIST_B = 0x7E, 0x7A
PAN_MODE_SQRT = 0x7F
MOD_SHAPE_SAW_UP = 0x0C      # the shape of the two records that do not use the table


def _pop8(value: int) -> int:
    return bin(value).count("1")


class SoundVM:
    def __init__(self, program: bytes, chip: ChipPort) -> None:
        self.rom = program
        self.chip = chip
        self.m = bytearray(0x10000)
        self.d = bytearray(8)        # the scratch bytes 0xFFFDD0–7
        self.time = 0                # 0xFFFDEA
        self.transpose = 0           # 0xFFFDEC
        self.fade_step = 0           # 0xFFFDF6 (0x9A), fades out
        self.fade_add = 0            # 0xFFFDF7 (0x1C), halves
        self.pan_mask = 0            # 0xFFFE04
        self.level = 0               # 0xFFFDDC, the voice's total attenuation
        self.op = 0                  # 0xFFFDF2
        self.top = 0                 # 0xFFFDEE, where the highest priority was found
        self.owner_slot = 0          # 0xFFFDDA
        self.ch = 0                  # 0xFFFDE0
        self.sub = 0                 # 0xFFFDE6, the channel's first track
        self.chan = 0                # 0xFFFDE8
        self.cmd = 0                 # 0xFFFDF0
        self.e3 = 0                  # the script's bank …
        self.r3 = 0                  # … and pointer
        self.voice = 0               # 0xFFFDE1
        self.seq_table = self._le(DIR_SEQUENCES)
        self.wave_table = self._le(DIR_WAVES)
        self.pitch_table = self._le(DIR_PITCH)
        self.env_table = self._le(DIR_ENVELOPES)
        self.pan_table = self._le(DIR_PANS)
        self.mod_table = self._le(DIR_MODULATIONS)
        # Called when a channel's script tests a variable (for the sections' cues): (channel, variable, taken).
        self.on_compare: Callable[[int, int, bool], None] | None = None
        # Called when a channel's script sets a variable (which channel answers the sections): (channel, variable).
        self.on_variable: Callable[[int, int], None] | None = None
        self._ops = {code: getattr(self, name) for code, name in _OPS.items()}

    # ---- the main CPU's side ----

    def command(self, channel: int, word: int) -> None:
        """`FUN_801B0968` and friends: a word into the channel's command slot."""
        self._w16(COMMANDS + 2 * channel, word)

    def set_var(self, index: int, value: int) -> None:
        """`FUN_801B0A30`."""
        self._w16(VARS + 2 * index, value)

    def var(self, index: int) -> int:
        return self._r16(VARS + 2 * index)

    def write_shared(self, offset: int, value: int) -> None:
        """A word of the main CPU at its offset in the shared RAM."""
        self._w16(offset, value)

    # ---- memory ----

    def _r16(self, a: int) -> int:
        """A word read: the bus ignores the address's low bit."""
        a &= 0xFFFE
        return self.m[a] << 8 | self.m[a + 1]

    def _w16(self, a: int, value: int) -> None:
        a &= 0xFFFE
        self.m[a] = (value >> 8) & 0xFF
        self.m[a + 1] = value & 0xFF

    def _le(self, a: int) -> int:
        """Script and table words are little-endian."""
        return self.rom[a] | self.rom[a + 1] << 8

    def _be(self, a: int) -> int:
        """The driver's own tables are words of its big-endian program."""
        return self.rom[a] << 8 | self.rom[a + 1]

    def _vreg(self, reg: int, value: int) -> None:
        self.chip.write(self.voice * 8 + reg, value)

    # ---- boot and tick ----

    def boot(self) -> None:
        """Power-on (0x3E30, 0x3EF6, 0x4256): cleared, then channel 0 starts sequence 0."""
        m = self.m
        self._w16(0x0586, FREQ_TABLE)
        self.fade_step, self.fade_add = 0x9A, 0x1C
        self.chip.write(REG_CONTROL, 0x0E9F)
        self._w16(0x058A, 0xFFFF)
        m[0x04FA] = 0xFF
        m[0x0584], m[0x0582] = CHANNELS, VOICES
        m[0x0590], m[0x058E] = 0x38, 2
        self.time = 0
        self.transpose = 0
        self._reset()
        if self._le(0x8000) == self.seq_table:
            self.command(0, START_BIT)

    def _reset(self) -> None:
        """0x4256: every channel off, every voice's key off."""
        m = self.m
        for i in range(CHANNELS):
            self._w16(COMMANDS + 2 * i, 0)
            self._w16(VOICE_OWNERS + 2 * i, 0)
        m[CHANNEL_BASE:VOICE_OWNERS] = bytes(VOICE_OWNERS - CHANNEL_BASE)
        m[PRIORITY_BASE:PRIORITY_BASE + 0x400] = bytes(0x400)
        for v in range(VOICES):
            self.chip.write(v * 8 + REG_FLAGS, 0)
            vp = VOICE_BASE + VOICE_BYTES * v
            self._w16(vp + 0x38, 0)
            self._w16(vp + 0x3E, 0)
            self._w16(vp + 0x34, 0)
            self._w16(vp, 0xFFFF)
            self._w16(vp + 0x36, vp + QUEUE)

    def tick(self) -> None:
        """0x3FA4."""
        self.time = (self.time + TIME_PER_TICK) & 0xFFFF
        if self.m[0x0580] == 0x5A:
            self._reset()
            return
        self.pan_mask = self.m[0x058A]
        self._channels()

    def _channels(self) -> None:
        """0x4030."""
        m = self.m
        count = m[0x0584]
        ch, cmd, chan, sub = 0, COMMANDS, CHANNEL_BASE, TRACK_BASE
        while True:
            self.ch, self.cmd, self.chan, self.sub = ch, cmd, chan, sub
            if m[cmd] & 0x40:
                self._start_channel()
            else:
                link = (m[cmd + LINKS] << 8 | m[cmd + LINKS + 1]) & 0xFFFE
                hi, lo = m[link], m[link + 1]
                if m[chan + 0xA] & 0x80:
                    m[chan + 0xA], m[chan + 0xB] = hi, lo
                    if not hi & 0x80:
                        # 0x5B2C jumps to the end routine without the return it pops: the routine returns
                        # to the tick's caller, so this tick neither fades this channel nor runs the
                        # later channels and the voices. (Harmless on the cabinet; kept for the writes.)
                        self._end_channel()
                        return
                    self._run_channel()
                    self._fade()
            ch += 1
            if ch == count:
                break
            cmd += 2
            chan += CHANNEL_BYTES
            sub += CHANNEL_TRACKS
        self._voices()

    def _start_channel(self) -> None:
        """0x4184."""
        m = self.m
        chan = self.chan
        if m[chan + 0xA] & 0x80:
            self._stop_linked()
        cmd = self.cmd
        if not m[cmd] & (LINK_BIT >> 8):
            self._w16(cmd + LINKS, cmd)
        word = ((m[cmd] << 8 | m[cmd + 1]) & 0x3FFF) | RUN_BIT
        self._w16(cmd, word)
        p = self.seq_table + 3 * (word & ID_MASK)
        self._w16(chan + 0x10, self._le(p))
        self._w16(chan, self.time)
        m[chan + 0x12] = self.rom[p + 2]
        self._w16(chan + 0x18, 0)
        self._w16(chan + 0xE, 0)
        self._w16(chan + 0x1A, 0)
        self._w16(chan + 0x14, 0)
        self._w16(chan + 0x16, 0)
        self._w16(chan + 0xA, word)
        for t in range(TRACKS):
            m[self.sub + 0x13 + TRACK_BYTES * t] = 0

    def _stop_linked(self) -> None:
        """0x44CA: every channel that follows this command word ends. The channel pointer stays this
        channel's, so a stopped child keeps its running bit and now follows channel 0's word (0x6868)."""
        target = self.cmd
        saved = self.cmd, self.ch, self.sub
        cmd, ch, sub = COMMANDS, 0, TRACK_BASE
        for _ in range(CHANNELS):
            self.cmd, self.ch, self.sub = cmd, ch, sub
            if self._r16(cmd + LINKS) == target:
                self._end_channel()
            cmd += 2
            ch += 1
            sub += CHANNEL_TRACKS
        self.cmd, self.ch, self.sub = saved

    def _end_channel(self) -> None:
        """0x6702: the channel's tracks let go of their voices; another channel's track waiting for a
        voice takes it."""
        m = self.m
        d = self.d
        r1 = PRIORITY_BASE + self.ch
        for _ in range(4):
            for j in range(0, 0x100, TRACK_BYTES):
                m[r1 + j] = 0
            r1 += 0x100
        d[0] = 0
        sub = self.sub
        for t in range(TRACKS):
            d[4] = TRACKS - t
            if m[sub + 0x13]:
                m[sub + 0x13] = 0
                hard = (m[sub + 0x1D] << 1) & 0xFF
                d[2], d[3] = sub >> 8, sub & 0xFF
                number = m[sub + 0x11]
                vp = self._r16(sub + 0x16)
                m[vp + 0x34] = m[vp + 0x35]
                if hard:
                    self.chip.write(number * 8 + REG_FLAGS, 0)
                elif m[vp + 6]:
                    m[vp + 0x2E] = 1
                else:
                    self.chip.write(number * 8 + REG_FLAGS, self.chip.read_flags(number) & 0xFFFD)
                self.owner_slot = VOICE_OWNERS + 2 * number
                self._w16(self.owner_slot, 0)
                if self._priority_top(PRIORITY_BASE + number * 0x20):
                    self._next_owner()
            sub += TRACK_BYTES
        d[4] = 0
        cmd = self.cmd
        self._w16(cmd, self._r16(cmd) & 0x7FFF)
        self._w16(cmd + LINKS, COMMANDS)
        self._w16(self.chan + 0xA, 0)
        self.e3 = 0

    def _priority_top(self, r2: int) -> int:
        """0x441E: the highest priority among the channels; remembers where."""
        m = self.m
        top = 0
        for i in range(m[0x0582]):
            if m[r2 + i] > top:
                top = m[r2 + i]
                self.top = r2 + i
        return top

    def _next_owner(self) -> None:
        """0x4452: the track of the highest priority gets the voice."""
        m = self.m
        slot = self.top + 0x400
        owner = TRACK_BASE + ((((slot & 0x1F) << 3) + m[slot]) & 0xFF) * TRACK_BYTES
        self._w16(self.owner_slot, owner)
        m[owner + 0x13] = 0xFF

    def _fade(self) -> None:
        """0x4106: the channel's attenuation, with its fade (command bits 12–13)."""
        m = self.m
        chan = self.chan
        word = m[chan + 0xA] << 8 | m[chan + 0xB]
        kind = word & 0x3000
        base = m[self._r16(chan + 0x1E)]
        if kind == 0:
            value = base
        elif not kind & 0x2000:
            value = min(base + self.fade_add, 0xFF)
        else:
            level = (self.fade_step * 2 + self._r16(chan + 0x18)) & 0xFFFF
            self._w16(chan + 0x18, level)
            if level >= 0xD000:
                self._w16(self.cmd, self._r16(self.cmd) & 0x7FFF)
                return
            value = min(base + m[chan + 0x18], 0xFF)
        m[chan + 0x20] = value

    # ---- scripts ----

    def _run_channel(self) -> None:
        """0x5B32: a step of the script when its time has come."""
        m = self.m
        rom = self.rom
        chan = self.chan
        due = ((m[chan] << 8 | m[chan + 1]) - self.time) & 0xFFFF
        if due and due < 0x8000:
            return
        self.e3 = m[chan + 0x12]
        self.r3 = m[chan + 0x10] << 8 | m[chan + 0x11]
        if m[chan + 0x1A]:
            m[chan + 0x1A] -= 1
        else:
            ops = self._ops
            while True:
                b = rom[self.e3 << 16 | self.r3]
                self.r3 = (self.r3 + 1) & 0xFFFF
                if b & 0x80:
                    m[chan + 0x1A] = b & 0x7F
                    break
                self.op = b
                handler = ops.get(b & 0x3F)
                if handler is None:
                    raise SoundVmError(f"opcode {b & 0x3F:#x} at {self.e3:x}:{self.r3:04x}")
                done = handler()
                if done == _ENDED:
                    return
                if done == _NOTE:           # 0x5B9A
                    if m[chan + 0x17]:
                        continue
                    if m[chan + 0x13]:
                        m[chan + 0x13] -= 1
                        continue
                    break
        self._step_time()

    def _step_time(self) -> None:
        """0x5BC6: when the next step is due."""
        m = self.m
        chan = self.chan
        if m[chan + 0x1B] or m[chan + 0xD]:
            raise SoundVmError("a timebase variable or tempo table: no script uses them")
        step = m[chan + 9] * m[chan + 7]
        self._w16(chan, (m[chan] << 8 | m[chan + 1]) + step)
        self._w16(chan + 0x10, self.r3)
        self.e3 = 0

    def _masked(self, after: Callable[[int, int], None] | None = None) -> None:
        """0x5D5E: mask, register, then a value per selected track (or one for all); a register with bit
        7 takes the values as variable numbers. 'after' is the op's own step for each track."""
        m = self.m
        rom = self.rom
        base = self.e3 << 16
        r3 = self.r3
        mask = rom[base | r3]
        r3 = (r3 + 1) & 0xFFFF
        reg = rom[base | r3]
        common = bool(self.op & 0x40)
        value = 0
        if common:
            value = rom[(base | r3) + 1]
            self.op = value
            r3 = (r3 + 1) & 0xFFFF
        r3 = (r3 + 1) & 0xFFFF
        by_var = bool(reg & 0x80)
        r1 = self.sub + (reg & 0x7F)
        while True:
            selected = mask & 0x80
            mask = (mask << 1) & 0xFF
            if selected:
                if not common:
                    value = rom[base | r3]
                    r3 = (r3 + 1) & 0xFFFF
                v = m[VAR_LOW + 2 * value] if by_var else value
                m[r1] = v
                if after is not None:
                    self.r3 = r3
                    after(r1, v)
                    r3 = self.r3
            r1 += TRACK_BYTES
            if not mask:
                break
        self.r3 = r3

    def _op_poke8(self) -> None:
        a = self.e3 << 16 | self.r3
        target = self._le(a)
        if target in (0x5484, 0x4484):
            target = 0x0584
        elif target in (0x5482, 0x4482):
            target = 0x0582
        self.m[target] = self.rom[a + 2]
        self.r3 = (self.r3 + 3) & 0xFFFF

    def _op_poke16(self) -> None:
        a = self.e3 << 16 | self.r3
        target = self._le(a)
        value = self._le(a + 2)
        if target == 0x2400:
            self.chip.write(REG_CONTROL, (value & 0x1FF) | 0xE00)
        elif target == 0xDC:
            self.transpose = value
        else:
            self._w16(target, value)
        self.r3 = (self.r3 + 4) & 0xFFFF

    def _op_channel_byte(self) -> None:
        """0x5D16: a byte of the channel."""
        a = self.e3 << 16 | self.r3
        reg = self.rom[a]
        value = self.rom[a + 1]
        if reg & 0x80:
            value = self.m[VAR_LOW + 2 * value]
        self.m[self.chan + (reg & 0x7F)] = value
        self.r3 = (self.r3 + 2) & 0xFFFF

    def _op_step_base(self) -> None:
        """0x5E02."""
        self.m[self.chan + 0x1B] = 0
        self._op_channel_byte()

    def _op_atten_self(self) -> None:
        """0x5E0C: the channel's attenuation is its own byte 6."""
        self._w16(self.chan + 0x1E, self.chan + 6)
        self._op_channel_byte()

    def _op_atten_var(self) -> None:
        """0x5E4C: the channel's attenuation is a variable's low byte."""
        v = self.rom[self.e3 << 16 | self.r3]
        self.r3 = (self.r3 + 1) & 0xFFFF
        self._w16(self.chan + 0x1E, VAR_LOW + 2 * v)

    def _op_step_size(self) -> None:
        """0x5E62: the step's size, without a tempo table."""
        self._w16(self.chan + 0xC, 0)
        self._op_channel_byte()

    def _op_start(self) -> None:
        """0x5ED8: starts a sequence on another channel; that one follows this channel's command word."""
        a = self.e3 << 16 | self.r3
        ch = self.rom[a]
        word = (self._le(a + 1) & ID_MASK) | START_BIT | LINK_BIT
        self.r3 = (self.r3 + 3) & 0xFFFF
        slot = COMMANDS + 2 * ch
        self._w16(slot, word)
        self._w16(slot + LINKS, self.cmd)

    def _op_jump(self) -> None:
        """0x68BE."""
        a = self.e3 << 16 | self.r3
        self.r3 = self._le(a)
        self.e3 = self.rom[a + 2]
        self.m[self.chan + 0x12] = self.e3

    def _op_call(self) -> None:
        """0x66AC: stack entries of 3 bytes, written by words: an odd entry's word lands one byte lower."""
        m = self.m
        chan = self.chan
        depth = m[chan + 0x14]
        slot = chan + 0x22 + 3 * depth
        a = self.e3 << 16 | self.r3
        target = self._le(a)
        bank = self.rom[a + 2]
        m[slot + 2] = self.e3
        self._w16(slot, (self.r3 + 3) & 0xFFFF)
        self.r3 = target
        self.e3 = bank
        m[chan + 0x12] = bank
        m[chan + 0x14] = (depth + 1) & 0xFF

    def _op_return(self) -> str | None:
        """0x66F8."""
        m = self.m
        chan = self.chan
        depth = m[chan + 0x14]
        if depth == 0:
            self._end_channel()
            return _ENDED
        depth -= 1
        m[chan + 0x14] = depth
        slot = chan + 0x22 + 3 * depth
        self.r3 = self._r16(slot)
        self.e3 = m[slot + 2]
        m[chan + 0x12] = self.e3
        return None

    def _op_repeat(self) -> None:
        """0x68D6."""
        m = self.m
        chan = self.chan
        depth = m[chan + 0x15]
        slot = chan + 0x34 + 4 * depth
        if depth:
            top = slot - 4
            if self.r3 == self._r16(top + 2) and self.e3 == m[top + 1]:
                m[top] = (m[top] - 1) & 0xFF
                if not m[top]:
                    m[chan + 0x15] = depth - 1
                    self.r3 = (self.r3 + 4) & 0xFFFF
                    return
                self._repeat_jump()
                return
        self._w16(slot + 2, self.r3)
        a = self.e3 << 16 | self.r3
        m[slot] = self.rom[a]
        m[slot + 1] = self.e3
        m[chan + 0x15] = (depth + 1) & 0xFF
        self._repeat_jump()

    def _repeat_jump(self) -> None:
        a = self.e3 << 16 | self.r3
        target = self._le(a + 1)
        self.e3 = self.rom[a + 3]
        self.m[self.chan + 0x12] = self.e3
        self.r3 = target

    def _op_end(self) -> str:
        self._end_channel()
        return _ENDED

    def _op_text(self) -> None:
        """0x6688: a label for the sound test screen, up to a byte that shifts to zero."""
        a = self.e3 << 16 | self.r3
        n = 0
        while True:
            c = self.rom[a + n]
            n += 1
            if not (c << 1) & 0xFF:
                break
        self.r3 = (self.r3 + n) & 0xFFFF

    def _op_word(self) -> None:
        """0x5FE4: a word with bit 15 set (the wave's `first time` mark, 0x471A), or a variable's."""
        a = self.e3 << 16 | self.r3
        if self.rom[a + 1] & 0x80:
            self._op_word_from_var()
            return
        common = bool(self.op & 0x40)
        high = self.rom[a + 3] if common else 0

        def store(r2: int, low: int) -> None:
            if common:
                hi = high
            else:
                hi = self.rom[self.e3 << 16 | self.r3]
                self.r3 = (self.r3 + 1) & 0xFFFF
            self.m[r2] = hi | 0x80
            self.m[r2 + 1] = low

        self._masked(store)
        if common:
            self.r3 = (self.r3 + 1) & 0xFFFF

    def _op_word_from_var(self) -> None:
        """0x6040: a variable into word 0 of the selected tracks. With one value for all the code also
        decrements a stray byte in unused RAM (0x60: an address it means to be its flag's)."""
        m = self.m
        base = self.e3 << 16
        r3 = self.r3
        mask = self.rom[base | r3]
        r3 = (r3 + 1) & 0xFFFF
        common = bool(self.op & 0x40)
        value = 0
        if common:
            value = self.rom[(base | r3) + 1]
            r3 = (r3 + 1) & 0xFFFF
            stray = (self.chan + 0xFDE2) & 0xFFFF
            m[stray] = (m[stray] - 1) & 0xFF
        r3 = (r3 + 1) & 0xFFFF
        r1 = self.sub
        while mask:
            selected = mask & 0x80
            mask = (mask << 1) & 0xFF
            if selected:
                if not common:
                    value = self.rom[base | r3]
                    r3 = (r3 + 1) & 0xFFFF
                self._w16(r1, self._r16(VARS + 2 * value))
            r1 += TRACK_BYTES
        self.r3 = r3

    def _op_note_word(self) -> None:
        """0x5FC6: the selected tracks' next wave, marked 0x80 in the high byte."""
        def store(r2: int, value: int) -> None:
            self.m[r2 + 1] = value
            self.m[r2] = 0x80
        self._masked(store)

    def _op_track_init(self) -> None:
        """0x6A10: the selected tracks start afresh with this priority for their voice."""
        self._masked(self._track_init)

    def _track_init(self, r2: int, priority: int) -> None:
        """0x6A1C. Note 0x6AA8's byte: `r2 + 0x6E` lies three tracks further on."""
        m = self.m
        self.d[2] = priority
        m[r2 + 0x10] = 0
        m[r2:r2 + 0x10] = bytes(0x10)
        m[r2 + 0x12:r2 + 0x1A] = bytes(8)
        m[r2 + 0x1C:r2 + 0x20] = bytes(4)
        self._w16(r2 + 0x18, r2)
        number = m[r2 + 0x11]
        self._w16(r2 + 0x16, VOICE_BASE + VOICE_BYTES * number)
        # 0x4362: this track's claim on the voice.
        track = (r2 & 0xE0) >> 5
        self.d[3] = track
        table = PRIORITY_BASE + number * 0x20
        m[table + self.ch] = priority
        m[table + self.ch + 0x400] = track
        if self._priority_top(table) == priority:
            m[r2 + 0x6E] = 0
            self._claim_voice(r2)

    def _claim_voice(self, r2: int) -> None:
        """0x43B0: this track holds the voice; a track that held it lets go."""
        m = self.m
        m[r2 + 0x13] = 0xFF
        self.owner_slot = VOICE_OWNERS + 2 * m[r2 + 0x11]
        holder = self._r16(self.owner_slot)
        if holder == r2:
            return
        if holder:
            m[holder + 0x13] = 0
        self._w16(self.owner_slot, r2)

    def _op_pan_list(self) -> None:
        """0x6AF6: the value, and pan mode 0x7E in the same track."""
        def store(r2: int, _value: int) -> None:
            self.m[r2 + 0xB] = PAN_MODE_LIST_A
        self._masked(store)

    def _op_pan_sqrt(self) -> None:
        """0x5E1A: the value, and pan mode 0x7F."""
        def store(r2: int, _value: int) -> None:
            self.m[r2 + 0xB] = PAN_MODE_SQRT
        self._masked(store)

    def _op_wave_first(self) -> None:
        """0x6AD2: marks the tracks' wave to be set up again on the next note."""
        def mark(r2: int, _value: int) -> None:
            head = r2 & 0xFFF0
            self._w16(head, self._r16(head) | RUN_BIT)
        self._masked(mark)

    def _op_alu(self) -> None:
        """0x60C4: set, add and subtract are the kinds scripts use."""
        m = self.m
        rom = self.rom
        base = self.e3 << 16
        r3 = self.r3
        f = rom[base | r3]
        x = rom[(base | r3) + 1]
        if f & 0x40:
            x = m[VAR_LOW + 2 * x]
        dst = VARS + 2 * x
        r3 = (r3 + 2) & 0xFFFF
        if f & 0x20:
            if f & 0x10:
                src = self._le(base | r3)
                r3 = (r3 + 1) & 0xFFFF
            else:
                src = rom[base | r3]
        else:
            y = rom[base | r3]
            if f & 0x10:
                y = m[VAR_LOW + 2 * y]
            src = self._r16(VARS + 2 * y)
        self.r3 = (r3 + 1) & 0xFFFF
        kind = f & 0xF
        if kind == 0:
            value = src
        elif kind == 1:
            value = self._r16(dst) + src
        elif kind == 2:
            value = self._r16(dst) - src
        else:
            raise SoundVmError(f"arithmetic kind {kind}: no script uses it")
        self._w16(dst, value & 0xFFFF)
        if self.on_variable is not None:
            self.on_variable(self.ch, x)

    def _compare_arg(self, r3: int, immediate: bool, wide: bool) -> tuple[int, int]:
        """0x6340: an argument after `r3`; returns its value and the new `r3`."""
        base = self.e3 << 16
        if immediate:
            if wide:
                return self._le(base | r3 + 1), (r3 + 1) & 0xFFFF
            return self.rom[(base | r3) + 1], r3
        v = self.rom[(base | r3) + 1]
        if wide:
            v = self._r16(VARS + 2 * v) & 0xFF
        return self._r16(VARS + 2 * v), r3

    def _op_compare(self) -> None:
        """0x6232: arg1, arg2, a target when true, a target when false. Equal, and the two orderings."""
        rom = self.rom
        base = self.e3 << 16
        r3 = self.r3
        start = base | r3
        f = rom[start]
        arg1, r3 = self._compare_arg(r3, bool(f & 0x80), bool(f & 0x40))
        r3 = (r3 + 1) & 0xFFFF
        arg2, r3 = self._compare_arg(r3, bool(f & 0x20), bool(f & 0x10))
        kind = f & 0xF
        if kind == 0:
            taken = arg2 == arg1
        elif kind == 4:
            taken = arg2 < arg1
        elif kind == 5:
            taken = arg2 > arg1
        else:
            raise SoundVmError(f"comparison {kind}: no script uses it")
        if self.on_compare is not None and not f & 0xC0:
            self.on_compare(self.ch, rom[start + 1], taken)
        a = (base | r3) + (2 if taken else 5)
        self.r3 = self._le(a)
        self.e3 = rom[a + 2]
        self.m[self.chan + 0x10] = self.r3 >> 8
        self.m[self.chan + 0x11] = self.r3 & 0xFF
        self.m[self.chan + 0x12] = self.e3

    def _op_note(self) -> str | None:
        """0x6382: mode 0 plays the note, 1 sets the volume to it, 2 sets its delay. Tracks that follow a
        played track (track byte 0x14) repeat its note."""
        m = self.m
        rom = self.rom
        code = self.op & 0x3F
        if code & 1:
            raise SoundVmError("a note from a variable: no script uses it")
        mode = (code - 0x20) >> 1
        self.d[1] = mode
        base = self.e3 << 16
        r3 = self.r3
        mask = rom[base | r3]
        r3 = (r3 + 1) & 0xFFFF
        common = bool(self.op & 0x40)
        value = 0
        if common:
            value = rom[base | r3]
            r3 = (r3 + 1) & 0xFFFF
        if m[self.chan + 0x17] & 0x80:
            if not common:
                r3 = (r3 + _pop8(mask)) & 0xFFFF
            self.r3 = r3
            return None
        sub = self.sub
        left = mask
        r2 = sub
        while True:
            m[r2 + 0x1B] = left
            selected = left & 0x80
            left = (left << 1) & 0xFF
            if selected:
                if not common:
                    value = rom[base | r3]
                    r3 = (r3 + 1) & 0xFFFF
                m[r2 + 0x1A] = value
                self._note_on(r2, value)
            if not left:
                break
            r2 += TRACK_BYTES
        left = ~mask & 0xFF
        r2 = sub
        while True:
            selected = left & 0x80
            left = (left << 1) & 0xFF
            if selected and m[r2 + 0x14]:
                leader = sub + ((m[r2 + 0x14] - 1) & 0xFF) * TRACK_BYTES
                if m[leader + 0x1B] & 0x80:
                    self._note_on(r2, m[leader + 0x1A])
            if not left:
                break
            r2 += TRACK_BYTES
        self.r3 = r3
        return _NOTE

    def _note_on(self, r2: int, note: int) -> None:
        """0x650A: into the voice's queue, due `track byte 8` ticks from the channel's time."""
        m = self.m
        if not m[r2 + 0x13]:
            return
        d = self.d
        split = m[r2 + 0x10]
        if split:
            self._key_split(r2, split - 1, note)
        else:
            self._w16(r2 + 0x18, r2)
        if d[1] == 2:
            m[r2 + 8] = note
        d[0] = note
        vp = m[r2 + 0x16] << 8 | m[r2 + 0x17]
        q = m[vp + 0x34]
        m[vp + 0x34] = (q + 1) & 0xFF
        entry = vp + QUEUE + (q & 7) * 8
        mode = d[1]
        tie = m[r2 + 0x12]
        if tie:
            m[r2 + 0x12] = tie - 1
            mode |= 0x80
        m[entry + 2], m[entry + 3] = note, mode
        m[entry + 4], m[entry + 5] = m[r2 + 0x18], m[r2 + 0x19]
        a = m[r2 + 0x1C]
        self._w16(entry + 6, VARS + 2 * a if a else self.chan + 0x20)
        chan = self.chan
        t = m[chan] << 8 | m[chan + 1]
        delay = m[r2 + 8]
        if delay:
            t = (t + delay * TIME_PER_TICK) & 0xFFFF
        m[entry], m[entry + 1] = t >> 8, t & 0xFF

    def _key_split(self, r2: int, index: int, note: int) -> None:
        """0x65FC: a preset by the note's range."""
        rom = self.rom
        p = (index * 16 + self._le(DIR_SPLITS)) & 0xFFFF
        r3 = p + 1
        if p & 0xFF != 0xFF:
            for count in range(TRACKS, 0, -1):
                if note < rom[r3 + 1] or count == 1:
                    break
                r3 += 2
        preset = rom[r3]
        self._w16(r2 + 0x18, PRESETS + preset * 16 if preset else r2)

    # ---- voices ----

    def _voices(self) -> None:
        """0x459C."""
        m = self.m
        time = self.time
        vp = VOICE_BASE
        for v in range(m[0x0582]):
            self.voice = v
            if m[vp + 0x35] != m[vp + 0x34]:
                head = m[vp + 0x36] << 8 | m[vp + 0x37]
                due = ((m[head] << 8 | m[head + 1]) - time) & 0xFFFF
                if due == 0 or due & 0x8000:
                    while True:
                        entry = m[vp + 0x36] << 8 | m[vp + 0x37]
                        n = (m[vp + 0x35] + 1) & 0xFF
                        m[vp + 0x35] = n
                        head = vp + QUEUE + (n & 7) * 8
                        m[vp + 0x36], m[vp + 0x37] = head >> 8, head & 0xFF
                        if n == m[vp + 0x34]:
                            break
                        if not ((m[head] << 8 | m[head + 1]) - time) & 0x8000:
                            break
                    self._key_on(vp, entry)
            if m[vp + 0x38] or m[vp + 0x39]:
                self._voice_tick(vp)
            vp += VOICE_BYTES
        self.chip.write(REG_KEY, m[0x0582])

    def _voice_off(self, vp: int) -> None:
        """0x59CA."""
        self._vreg(REG_FLAGS, 0)
        self.m[vp + 0x38] = 0

    def _key_on(self, vp: int, e: int) -> None:
        """0x46A4: a queued note reaches its voice."""
        m = self.m
        d = self.d
        m[vp + 0x3C], m[vp + 0x3D] = m[e + 4], m[e + 5]
        m[vp + 0x48], m[vp + 0x49] = m[e + 6], m[e + 7]
        note, mode = m[e + 2], m[e + 3]
        d[4], d[5] = note, mode
        r6 = m[vp + 0x3C] << 8 | m[vp + 0x3D]
        if note == 0x7F and not mode & 0x7F:
            self._release(vp)
            return
        m[vp + 2:vp + 6] = m[r6 + 2:r6 + 6]
        kind = mode & 0x7F
        wave = -1
        if kind == 1:
            m[vp + 2] = note
        elif kind == 3:
            raise SoundVmError("note mode 3: no script uses it")
        elif kind != 2:
            if note & 0x80:
                wave = note & 0x7F
            elif note == 0x7F:
                self._release(vp)
                return
            else:
                m[vp + 5] = note
        if wave < 0:
            m[vp + 0xA], m[vp + 0xB] = m[r6 + 0xA], m[r6 + 0xB]
            word = m[r6] << 8 | m[r6 + 1]
            if word & 0x8000:
                wave = word & 0x7FFF
                self._w16(r6, wave)
            elif (m[vp] << 8 | m[vp + 1]) != word:
                wave = word
            elif m[vp + 0x32]:
                self._load_wave(vp, m[vp + 0x10] << 8 | m[vp + 0x11], m[vp + 0x2C] << 8 | m[vp + 0x2D])
        if wave >= 0:
            self._wave_setup(vp, wave)
        m[vp + 6:vp + 0xA] = m[r6 + 6:r6 + 0xA]
        m[vp + 0xC:vp + 0x10] = m[r6 + 0xC:r6 + 0x10]
        m[vp + 5] = (m[vp + 5] + m[vp + 0xB]) & 0xFF
        m[vp + 0x38] = 0xFF
        if not mode & 0x80:
            self._trigger(vp)

    def _release(self, vp: int) -> None:
        """0x4738."""
        if self.m[vp + 6]:
            self.m[vp + 0x2E] = 1
        else:
            self._voice_off(vp)

    def _wave_setup(self, vp: int, wave: int) -> None:
        """0x5A78."""
        m = self.m
        self._w16(vp, wave)
        p = self._le((2 * wave + self.wave_table) & 0xFFFF)
        self._w16(vp + 0x10, p)
        self._w16(vp + 0x46, self._le(p))
        self._w16(vp + 0x14, self._le(p + 2))
        flags = self._le(p + 4)
        self._w16(vp + 0x2C, flags)
        self._load_wave(vp, p, flags)

    def _load_wave(self, vp: int, p: int, flags: int) -> None:
        """0x5AC4: the sample's registers; a linked sample keeps its next piece's address."""
        m = self.m
        self._vreg(REG_START, (m[vp + 0xA] + self._le(p + 6)) & 0xFFFF)
        self._vreg(REG_END, self._le(p + 8))
        self._vreg(REG_LOOP, self._le(p + 0xA))
        self._w16(vp + 0x12, p + 2)
        m[vp + 0x32] = 0xFF if flags & 0x20 else 0

    def _trigger(self, vp: int) -> None:
        """0x47E0: pitch curve, envelope, pan and modulation start; the key goes on."""
        m = self.m
        rom = self.rom
        self._vreg(REG_FLAGS, 0)
        if m[vp + 7]:
            m[vp + 0x26] = 0
            r3 = self._le((2 * (m[vp + 7] - 1) + self.pitch_table) & 0xFFFF)
            m[vp + 0x2F], m[vp + 0x30] = rom[r3], rom[r3 + 1]
            r3 += 2
            self._w16(vp + 0x28, r3)
            m[vp + 0x27] = rom[r3]
            self._w16(vp + 0x24, r3 + 1)
        if m[vp + 6]:
            slot = (2 * (m[vp + 6] - 1) + self.env_table) & 0xFFFF
            self._w16(vp + 0x1C, slot)
            r3 = self._le(slot)
            m[vp + 0x2E] = m[vp + 9]
            if not rom[r3] & 0x80:
                self._w16(vp + 0x1E, 0xFFFF)
            self._env_next(vp, r3)
        else:
            m[vp + 0x1E] = 0
            self._w16(vp + 0x5C, NO_ROUTINE)
        self._w16(vp + 0x40, 0)
        self._w16(vp + 0x44, 0)
        self._pan_start(vp)
        self._modulation_start(vp)
        self._vreg(REG_BANK, self._r16(vp + 0x14))
        self._vreg(REG_FLAGS, self._r16(vp + 0x2C) | FLAG_KEY_ON)

    def _pan_start(self, vp: int) -> None:
        """0x48AC."""
        m = self.m
        mode = m[vp + 0xE]
        if mode in (PAN_MODE_LIST_A, PAN_MODE_LIST_B):
            self._pan_list_start(vp, mode)
            return
        if not mode & 0x80:
            m[vp + 0x6E] = mode
            m[vp + 0x6F] = m[vp + 3]
        if mode == PAN_MODE_SQRT:
            self._pan_sqrt(m[vp + 3])
        elif mode < 0x40 or mode & 0x80:
            self._pan_stereo(m[vp + 3], mode)
        else:
            raise SoundVmError(f"pan mode {mode:#x}: no script uses it")
        d = self.d
        m[vp + 0x70], m[vp + 0x71], m[vp + 0x72], m[vp + 0x73] = d[0], d[1], d[2], d[3]
        self._w16(vp + 0x60, PAN_FIXED)

    def _pan_list_start(self, vp: int, mode: int) -> None:
        """0x499C: a list of pan moves, by the voice's byte 3."""
        m = self.m
        rom = self.rom
        r3 = self._le((2 * ((m[vp + 3] - 1) & 0xFF) + self.pan_table) & 0xFFFF)
        first = rom[r3]
        r3 += 1
        if first == 0xFF:
            if mode != PAN_MODE_LIST_A and m[vp + 3] == m[vp + 0x6F]:
                return
            m[vp + 0x6E] = PAN_MODE_LIST_B
            m[vp + 0xE] = PAN_MODE_LIST_B
            m[(m[vp + 0x3C] << 8 | m[vp + 0x3D]) + 0xE] = PAN_MODE_LIST_B
            m[vp + 0x6F] = m[vp + 3]
            first = 1
        elif first == 0:
            first = 1
        m[vp + 0x31] = first
        m[vp + 0x67] = m[vp + 0x6C] = rom[r3]
        r3 += 1
        self._w16(vp + 0x60, PAN_TRACK_RUN)
        self._w16(vp + 0x3E, r3)
        self._w16(vp + 0x6A, r3)

    def _modulation_start(self, vp: int) -> None:
        """0x4A86."""
        m = self.m
        rom = self.rom
        if not m[vp + 0xC]:
            self._w16(vp + 0x5A, NO_ROUTINE)
            return
        r = (8 * (m[vp + 0xC] - 1) + self.mod_table) & 0xFFFF
        self._w16(vp + 0x5A, MODULATE)
        m[vp + 0x54] = rom[r + 2]
        m[vp + 0x55] = 0
        m[vp + 0x56] = rom[r + 3]
        m[vp + 0x57] = 0
        self._w16(vp + 0x50, self._be(RATE_TABLE + 2 * rom[r + 6]))
        self._w16(vp + 0x52, self._be(RATE_TABLE + 2 * rom[r + 7]))
        self._w16(vp + 0x58, 0)
        m[vp + 0x4C] = rom[r]
        m[vp + 0x4E] = rom[r + 1]
        m[vp + 0x4D] = rom[r + 4]
        m[vp + 0x4F] = rom[r + 5]

    def _env_step(self, vp: int) -> None:
        """0x5916."""
        m = self.m
        routine = m[vp + 0x5C] << 8 | m[vp + 0x5D]
        if routine == ENV_RISE:
            level = (m[vp + 0x1E] << 8 | m[vp + 0x1F]) + (m[vp + 0x18] << 8 | m[vp + 0x19])
            m[vp + 0x1E], m[vp + 0x1F] = (level >> 8) & 0xFF, level & 0xFF
            if level > 0xFFFF or m[vp + 0x1E] >= m[vp + 0x1A]:
                self._env_reached(vp, m[vp + 0x20] << 8 | m[vp + 0x21])
                return
        elif routine == ENV_FALL:
            level = (m[vp + 0x1E] << 8 | m[vp + 0x1F]) - (m[vp + 0x18] << 8 | m[vp + 0x19])
            m[vp + 0x1E], m[vp + 0x1F] = (level >> 8) & 0xFF, level & 0xFF
            if level < 0 or m[vp + 0x1A] >= m[vp + 0x1E]:
                self._env_reached(vp, m[vp + 0x20] << 8 | m[vp + 0x21])
                return
        elif routine != ENV_HOLD:
            return
        # 0x5964: the key's release after the note's length; the list's mark 0xFE is the sustain's end.
        hold = m[vp + 0x2E]
        if not hold:
            return
        m[vp + 0x2E] = hold - 1
        if hold != 1:
            return
        rom = self.rom
        r3 = m[vp + 0x20] << 8 | m[vp + 0x21]
        while True:
            b = rom[r3]
            if b == 0:
                r3 += 2
                continue
            r3 += 1
            if b == 0xFF:
                self._voice_off(vp)
                return
            if b == 0xFE:
                self._env_reached(vp, r3)
                return
            r3 += 1

    def _env_reached(self, vp: int, r3: int) -> None:
        """0x59A4."""
        m = self.m
        m[vp + 0x1E] = m[vp + 0x1A]
        m[vp + 0x1F] = 0x80
        self._env_next(vp, r3)

    def _env_next(self, vp: int, r3: int) -> None:
        """0x59B2: the envelope's next (rate, level)."""
        m = self.m
        rom = self.rom
        while True:
            b = rom[r3]
            if b == 0:
                r3 = self._le((2 * rom[r3 + 1] + (m[vp + 0x1C] << 8 | m[vp + 0x1D])) & 0xFFFF)
                b = rom[r3]
            elif b == 0xFE:
                self._w16(vp + 0x5C, ENV_HOLD)
                return
            elif b == 0xFF:
                self._voice_off(vp)
                return
            self.d[6] = b
            target = rom[r3 + 1]
            r3 += 2
            m[vp + 0x20], m[vp + 0x21] = r3 >> 8, r3 & 0xFF
            m[vp + 0x1A] = target
            level = m[vp + 0x1E]
            if target == level:
                continue
            self._w16(vp + 0x5C, ENV_RISE if target > level else ENV_FALL)
            self._w16(vp + 0x18, self._be(RATE_TABLE + 2 * b))
            return

    def _pitch_curve(self, vp: int) -> None:
        """0x5386."""
        m = self.m
        rom = self.rom
        d = self.d
        if not m[vp + 7]:
            return
        r3 = m[vp + 0x24] << 8 | m[vp + 0x25]
        phase = m[vp + 0x2F] + m[vp + 0x26]
        m[vp + 0x26] = phase & 0xFF
        d[1] = phase & 0xFF
        if phase > 0xFF:
            m[vp + 0x27] = rom[r3]
            r3 += 1
            m[vp + 0x24], m[vp + 0x25] = r3 >> 8, r3 & 0xFF
        d[0] = 0
        current = m[vp + 0x27]
        d[2], d[3] = current, 0
        b = rom[r3]
        if b < 0xF0:
            delta = b - current
            if delta < 0:
                delta = (delta & 0xFF) | 0xFF00
            signed = delta - 0x10000 if delta & 0x8000 else delta
            value = (signed * d[1] + (current << 8)) & 0xFFFF
            m[vp + 0x2A], m[vp + 0x2B] = value >> 8, value & 0xFF
            self._pitch_curve_apply(vp)
        elif b == 0xFE:
            m[vp + 0x26] = 0
            m[vp + 0x24], m[vp + 0x25] = m[vp + 0x28], m[vp + 0x29]
        elif b == 0xFD:
            m[vp + 0x2F] = rom[r3 + 1]
            m[vp + 0x30] = rom[r3 + 2]
            r3 += 3
            self._w16(vp + 0x24, r3)
            self._w16(vp + 0x28, r3)
        else:
            m[vp + 0x2A] = current
            m[vp + 0x2B] = 0
            self._pitch_curve_apply(vp)
            m[vp + 7] = 0

    def _pitch_curve_apply(self, vp: int) -> None:
        """0x5450."""
        m = self.m
        d = self.d
        scale = m[vp + 0x30]
        if not scale:
            return
        d[2], d[3] = 0, scale
        value = m[vp + 0x2A] << 8 | m[vp + 0x2B]
        below = value < 0x6400
        r0 = (value - 0x6400) & 0xFFFF
        if below:
            r0 = -r0 & 0xFFFF
        r0 = _shar16(r0)
        product = r0 * scale
        high, low = product >> 16, product & 0xFFFF
        d[4], d[5] = high >> 8, high & 0xFF
        d[2], d[3] = low >> 8, low & 0xFF
        result = ((high & 0xFF) << 8) | (low >> 8)
        if below:
            result = ~result & 0xFFFF
        m[vp + 0x40], m[vp + 0x41] = result >> 8, result & 0xFF

    def _portamento(self, vp: int) -> None:
        """0x530A."""
        m = self.m
        d = self.d
        speed = m[vp + 0xD]
        target = m[vp + 5] << 8 | m[vp + 4]
        current = m[vp + 0x42] << 8 | m[vp + 0x43]
        if speed:
            diff = (target - current) & 0xFFFF
            if not diff:
                return
            d[0], d[1] = diff >> 8, diff & 0xFF
            if d[0] & 0x80:
                r0 = ((d[0] - 1) & 0xFFFF) | 0xFF00
            else:
                r0 = ((diff & 0xFF00) + d[0] + 1) & 0xFF
            product = (r0 * speed) & 0xFFFF
            d[2], d[3] = product >> 8, product & 0xFF
            moved = (_shar16(product) + current) & 0xFFFF
            m[vp + 0x42], m[vp + 0x43] = moved >> 8, moved & 0xFF
            if ((moved - target) ^ diff) & 0x8000:
                return
        m[vp + 0x42], m[vp + 0x43] = target >> 8, target & 0xFF

    def _modulate(self, vp: int) -> None:
        """0x4FCE."""
        m = self.m
        d = self.d
        delay = m[vp + 0x4E]
        if delay:
            m[vp + 0x4E] = delay - 1
            return
        self._mod_slide(vp)
        self._mod_slide(vp + 2)
        shape = m[vp + 0x4C]
        if shape == MOD_SHAPE_SAW_UP:
            m[vp + 0x58] = (m[vp + 0x58] + m[vp + 0x54]) & 0xFF
            self._mod_output(vp, m[vp + 0x58])
            return
        if shape > MOD_SHAPE_SAW_UP:
            raise SoundVmError(f"modulation shape {shape:#x}: no record uses it")
        d[0] = (m[vp + 0x59] << 3) & 0xFF
        phase = _shar16(m[vp + 0x58] << 8 | m[vp + 0x59])
        index = ((((phase & 0xF0) | shape) & 0xFF) << 4 | ((phase & 0xF0) | shape) >> 4) & 0xFF
        at = index * 2 + MODULATION_WAVES
        slope = self.rom[at]
        magnitude = ((slope << 1) & 0xFF) * d[0]
        value = (magnitude >> 8) & 0xFF
        if slope & 0x80:
            value = -value & 0xFF
        value = (value + self.rom[at - 1]) & 0xFF
        self._mod_output(vp, value)
        phase_word = (m[vp + 0x54] + (m[vp + 0x58] << 8 | m[vp + 0x59])) & 0xFFFF
        m[vp + 0x58], m[vp + 0x59] = phase_word >> 8, phase_word & 0xFF

    def _mod_slide(self, r2: int) -> None:
        """0x517E: a parameter towards its target at its rate (word +0x54, byte target +0x4D, rate +0x50)."""
        m = self.m
        now = m[r2 + 0x54]
        goal = m[r2 + 0x4D]
        if now == goal:
            return
        rising = now < goal
        rate = m[r2 + 0x50] << 8 | m[r2 + 0x51]
        if not rising:
            rate = -rate & 0xFFFF
        total = rate + (m[r2 + 0x54] << 8 | m[r2 + 0x55])
        carry = total > 0xFFFF
        total &= 0xFFFF
        m[r2 + 0x54], m[r2 + 0x55] = total >> 8, total & 0xFF
        if rising != carry:           # (rising + carry) is odd: no overflow past the end of the range
            now = m[r2 + 0x54]
            if now != goal and rising == (now < goal):
                return
        m[r2 + 0x54] = goal
        m[r2 + 0x55] = 0

    def _mod_output(self, vp: int, value: int) -> None:
        """0x51D4."""
        m = self.m
        depth = m[vp + 0x56]
        if value & 0x80:
            r0 = (((-value & 0xFF) * depth) ^ 0xFFFF)
            r0 = _shar16(_shar16(r0)) | 0xE000
        else:
            r0 = _shar16(_shar16(value * depth))
        m[vp + 0x44], m[vp + 0x45] = (r0 >> 8) & 0xFF, r0 & 0xFF

    def _pan_stereo(self, x: int, y: int) -> None:
        """0x4C0C: the two sides of the voice's four volumes, front/rear by the second value."""
        d = self.d
        d[0] = d[1] = d[2] = d[3] = 0
        if x & 0x80:
            v = ((x ^ 0xFF) << 2) & 0xFF
            d[1] = d[3] = v
        else:
            v = (x << 2) & 0xFF
            d[0] = d[2] = v
        if y & 0x80:
            v = ((y ^ 0xFF) << 2) & 0xFF
            d[0] = min(v + d[0], 0xFF)
            d[1] = min(v + d[1], 0xFF)
        else:
            v = (y << 2) & 0xFF
            d[2] = min(v + d[2], 0xFF)
            d[3] = min(v + d[3], 0xFF)

    def _pan_sqrt(self, x: int) -> None:
        """0x4CE6: a position on a circle of 256 steps, quarter by quarter."""
        d = self.d
        rom = self.rom
        d[0] = d[1] = d[2] = d[3] = 0xFF
        at = ((x & self.pan_mask) + 0x20) & 0xFF
        i = at & 0x3F
        a = rom[PAN_SQRT + i]
        b = rom[PAN_SQRT + (i ^ 0x3F)]
        d[5] = a
        quarter = at & 0xC0
        d[4] = (at << 1) & 0xFF
        if quarter == 0:
            d[1], d[0] = b, a
        elif quarter == 0x40:
            d[3], d[1] = b, a
        elif quarter == 0x80:
            d[2], d[3] = b, a
        else:
            d[0], d[2] = b, a

    def _pan_run(self, vp: int) -> None:
        """Voice byte 0x60's routine: sets the scratch bytes 0–3 for `_apply_volume`."""
        m = self.m
        routine = m[vp + 0x60] << 8 | m[vp + 0x61]
        if routine == PAN_FIXED:
            d = self.d
            d[0], d[1], d[2], d[3] = m[vp + 0x70], m[vp + 0x71], m[vp + 0x72], m[vp + 0x73]
            return
        if routine == PAN_TRACK_RUN:
            hold = (m[vp + 0x31] - 1) & 0xFF
            m[vp + 0x31] = hold
            if hold:
                self._pan_sqrt(m[vp + 0x66])
            else:
                m[vp + 0x66] = 0x80
                self._pan_list_next(vp)
        elif routine == PAN_TRACK_MOVE_UP:
            r0 = (m[vp + 0x66] << 8 | m[vp + 0x67]) - (m[vp + 0x62] << 8 | m[vp + 0x63])
            if r0 < 0:
                self._pan_list_next(vp)
            else:
                m[vp + 0x66], m[vp + 0x67] = r0 >> 8, r0 & 0xFF
                self._pan_sqrt((m[vp + 0x6C] - m[vp + 0x66]) & 0xFF)
        elif routine == PAN_TRACK_MOVE_DOWN:
            r0 = (m[vp + 0x66] << 8 | m[vp + 0x67]) + (m[vp + 0x62] << 8 | m[vp + 0x63])
            if r0 > 0xFFFF:
                self._pan_list_next(vp)
            else:
                m[vp + 0x66], m[vp + 0x67] = r0 >> 8, r0 & 0xFF
                self._pan_sqrt((m[vp + 0x6C] - m[vp + 0x66]) & 0xFF)
        else:
            raise SoundVmError(f"pan routine {routine:#x}: no script uses it")

    def _pan_list_next(self, vp: int) -> None:
        """0x555C."""
        m = self.m
        rom = self.rom
        r3 = m[vp + 0x6A] << 8 | m[vp + 0x6B]
        while True:
            b = rom[r3]
            r3 += 1
            if b == 0x80:
                self._w16(vp + 0x60, PAN_FIXED)
                # The routine returns without setting the volumes this tick (0x55F4).
                self._pan_done = False
                return
            if b == 0x81:
                r3 += 2
                self._w16(vp + 0x3E, r3)
            elif b == 0x82:
                r3 = m[vp + 0x3E] << 8 | m[vp + 0x3F]
            elif b == 0x83:
                track = m[vp + 0x3C] << 8 | m[vp + 0x3D]
                m[track + 3] = (m[track + 3] + 1) & 0xFF
                m[vp + 3] = (m[vp + 0x6F] + 1) & 0xFF
                hold = rom[r3]
                r3 += 1
                if hold != 0xFF:
                    m[vp + 0xE] = PAN_MODE_LIST_A
                    m[vp + 0x31] = hold
                r3 = self._pan_list_start_value(vp, r3)
            elif b == 0x84:
                m[vp + 0x31] = 0
                r3 = self._pan_list_start_value(vp, (m[vp + 0x3E] << 8 | m[vp + 0x3F]) - 1)
            else:
                break
        if b & 0x80:
            rate = self._be(RATE_TABLE + 2 * (-b & 0xFF))
            self._w16(vp + 0x60, PAN_TRACK_MOVE_DOWN)
        else:
            rate = self._be(RATE_TABLE + 2 * b)
            self._w16(vp + 0x60, PAN_TRACK_MOVE_UP)
        self._w16(vp + 0x62, rate)
        value = rom[r3]
        r3 += 1
        self._w16(vp + 0x6A, r3)
        m[vp + 0x66] = (value - m[vp + 0x6C]) & 0xFF
        m[vp + 0x67] = 0
        m[vp + 0x6C] = value
        self._pan_sqrt((m[vp + 0x6C] - m[vp + 0x66]) & 0xFF)

    def _pan_list_start_value(self, vp: int, r3: int) -> int:
        """0x55BA."""
        m = self.m
        m[vp + 0x67] = m[vp + 0x6C] = self.rom[r3]
        r3 += 1
        self._w16(vp + 0x3E, r3)
        self._w16(vp + 0x6A, r3)
        return r3

    def _voice_tick(self, vp: int) -> None:
        """0x4D78: the voice's tick: its chip status, envelope, pitch and volume."""
        m = self.m
        d = self.d
        v = self.voice
        flags = self.chip.read_flags(v)
        if flags & FLAG_BUSY:
            if flags & FLAG_LINK:
                self._link_reload(vp)
        elif flags < FLAG_KEY_ON:
            m[vp + 0x38] = 0
            return
        var = m[vp + 0xF]
        if var:
            word = self._r16(VARS + 2 * var)
            m[vp + 5] = word >> 8
            m[vp + 4] = word & 0xFF
        self._env_step(vp)
        self._pitch_curve(vp)
        self._portamento(vp)
        if (m[vp + 0x5A] << 8 | m[vp + 0x5B]) == MODULATE:
            self._modulate(vp)
        # 0x4E64: pitch word to frequency.
        pitch = ((m[vp + 0x42] << 8 | m[vp + 0x43]) + (m[vp + 0x40] << 8 | m[vp + 0x41]) + (m[vp + 0x44] << 8 | m[vp + 0x45])
                 + self.transpose + (m[vp + 0x46] << 8 | m[vp + 0x47])) & 0xFFFF
        hi, lo = pitch >> 8, pitch & 0xFF
        rom = self.rom
        at = FREQ_TABLE + ((hi << 1) & 0xFF)
        a = rom[at] << 8 | rom[at + 1]
        b = rom[at + 2] << 8 | rom[at + 3]
        product = ((b - a) & 0xFFFF) * lo
        low, high = product & 0xFFFF, product >> 16
        d[0], d[1], d[2], d[3] = low >> 8, low & 0xFF, high >> 8, high & 0xFF
        chip = self.chip
        chip.write(v * 8 + REG_FREQ, ((high & 0xFF) << 8 | low >> 8) + a & 0xFFFF)
        # 0x4EE0: envelope + the voice's + the channel's attenuation.
        level = m[vp + 0x1E] + m[vp + 2]
        if level <= 0xFF:
            level += m[m[vp + 0x48] << 8 | m[vp + 0x49]]
        self.level = level if level <= 0xFF else 0xFF
        self._pan_done = True
        self._pan_run(vp)
        if self._pan_done:
            self._apply_volume(v)

    def _apply_volume(self, v: int) -> None:
        """0x4F1A: side offsets + level through the attenuation table."""
        d = self.d
        rom = self.rom
        level = self.level
        d[4] = d[5] = d[6] = d[7] = 0
        if d[1] + level <= 0xFF:
            d[5] = rom[ATTENUATION + d[1] + level]
        if d[0] + level <= 0xFF:
            d[4] = rom[ATTENUATION + d[0] + level]
        if d[3] + level <= 0xFF:
            d[7] = rom[ATTENUATION + d[3] + level]
        if d[2] + level <= 0xFF:
            d[6] = rom[ATTENUATION + d[2] + level]
        chip = self.chip
        chip.write(v * 8 + REG_VOL_FRONT, d[4] << 8 | d[5])
        chip.write(v * 8 + REG_VOL_REAR, d[6] << 8 | d[7])

    def _link_reload(self, vp: int) -> None:
        """0x5204: a long sample's next piece; the chip jumps to (start, loop) at the piece's end."""
        m = self.m
        rom = self.rom
        r3 = m[vp + 0x12] << 8 | m[vp + 0x13]
        if m[vp + 0x32] & 0x80:
            m[vp + 0x32] = 0x7F
            self._vreg(REG_LOOP, self._le(r3 + 0xC))
            self._vreg(REG_START, self._le(r3 + 8))
            if rom[r3 + 0xA] & 1:
                self._w16(vp + 6, (self._r16(vp + 6) + 1) & 0xFFFF)
            self._w16(vp + 0x12, r3 + 8)
            return
        if not self.chip.read_flags(self.voice) & FLAG_LOOP_HISTORY:
            return
        self._vreg(REG_END, self._le(r3 + 6))
        piece_flags = self._le(r3 + 2)
        if not piece_flags & FLAG_LINK:
            self._vreg(REG_FLAGS, piece_flags)
            self._vreg(REG_END, self._le(r3 + 6))
            self._vreg(REG_LOOP, self._le(r3 + 8))
            return
        if rom[r3 + 9] & 0x80:
            r3 = self._le(r3 + 0xA)
        else:
            r3 += 8
        next_flags = self._le(r3 + 2)
        self._vreg(REG_FLAGS, (piece_flags & 0xFFFE) | (next_flags & 1))
        self._vreg(REG_LOOP, self._le(r3 + 4))
        self._vreg(REG_START, self._le(r3))
        self._w16(vp + 0x12, r3)


def _shar16(value: int) -> int:
    """`shar.w`: an arithmetic shift of a 16-bit value; the result is 16 bits again."""
    return ((value >> 1) | (value & 0x8000)) & 0xFFFF


_ENDED = "ended"             # the end routine ran: the step is over
_NOTE = "note"               # a note op: one step passes unless the channel chains notes

# Every opcode a script reaches (a walk over the 90 sequences' code): the handlers at 0x3DCC.
_OPS = {
    0x01: "_op_poke8", 0x02: "_op_poke16", 0x04: "_masked", 0x06: "_op_step_base", 0x07: "_op_atten_self",
    0x08: "_op_pan_sqrt", 0x0A: "_op_atten_var", 0x0D: "_op_start", 0x10: "_op_jump", 0x11: "_op_call", 0x12: "_op_repeat",
    0x14: "_op_return", 0x15: "_op_end", 0x17: "_op_text", 0x1B: "_op_word", 0x1C: "_op_note_word", 0x1D: "_op_track_init",
    0x1E: "_op_alu", 0x1F: "_op_compare", 0x20: "_op_note", 0x22: "_op_note", 0x28: "_op_wave_first", 0x29: "_op_pan_list",
    0x2D: "_op_step_size",
}
