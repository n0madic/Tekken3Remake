"""The C352 sound chip: registers, sample fetches and the mix, per voice with numpy.

The driver (`arcade_sound_vm.SoundVM`) reads the chip's flags to know that a sample ended or looped,
so the chip and the mix are one thing. Semantics as MAME's c352_device, checked against its output
(docs/research/arcade/audio-and-effects.md#c352): one sample at 88,200 Hz adds the frequency register to
a 16-bit counter, each carry fetches a wave byte; the four volumes ramp by 1 towards their targets
when bits 15–16 of the counter change; samples interpolate linearly unless the filter flag is set.
Key-ons and key-offs run on the write to register 0x202.
"""

from __future__ import annotations

from functools import cache

import numpy as np

SAMPLE_RATE = 88200
TICK_SAMPLES = SAMPLE_RATE // 120
VOICES = 32
MIX_GAIN_SHIFT = 3            # the board's output is the sum over 8 (MAME)
REG_VOLUME_FRONT, REG_VOLUME_REAR, REG_FREQ, REG_FLAGS, REG_BANK, REG_START, REG_END, REG_LOOP = range(8)
REG_KEYS = 0x202
BUSY, KEY_ON, KEY_OFF, LOOP_HISTORY = 0x8000, 0x4000, 0x2000, 0x0800
PHASE_FRONT_LEFT, PHASE_FRONT_RIGHT, BACKWARDS = 0x100, 0x80, 0x40
LINK, NOISE, MULAW, FILTER, LOOP, REVERSE = 0x20, 0x10, 8, 4, 2, 1
NOISE_PERIOD_LIMIT = 1 << 16
NOISE_SEED = 0x1234
COUNTER_RAMP_BITS = 0x18000


def mulaw_table() -> np.ndarray:
    """256 → s16: the chip's table (`c352_device::device_start`)."""
    table = [0] * 256
    j = 0
    for i in range(128):
        table[i] = j << 5
        if i < 16:
            j += 1
        elif i < 24:
            j += 2
        elif i < 48:
            j += 4
        elif i < 100:
            j += 8
        else:
            j += 16
    for i in range(128):
        table[i + 128] = (~table[i]) & 0xFFE0
    values = np.array(table, dtype=np.int32)
    values[values >= 0x8000] -= 0x10000
    return values.astype(np.int16)


@cache
def _noise_table() -> np.ndarray:
    values = np.empty(NOISE_PERIOD_LIMIT, dtype=np.int64)
    r = NOISE_SEED
    for i in range(NOISE_PERIOD_LIMIT):
        r = (r >> 1) ^ ((-(r & 1)) & 0xFFF6)
        values[i] = r - 0x10000 if r >= 0x8000 else r
    return values


class WaveSpace:
    """The wave ROM as the chip fetches it, one table per sample format: chips can share it."""

    def __init__(self, wave: bytes | np.ndarray) -> None:
        raw = np.frombuffer(wave, dtype=np.uint8) if isinstance(wave, (bytes, bytearray)) else wave
        if len(raw) & (len(raw) - 1):
            raise ValueError("the wave space's size must be a power of two")
        self.mask = len(raw) - 1
        self.linear = raw.astype(np.int8).astype(np.int16) << 8
        self.mulaw = mulaw_table()[raw]


class Voice:
    __slots__ = ("volume_front", "volume_rear", "freq", "flags", "bank", "start", "end", "loop",
                 "pos", "counter", "sample", "last", "level")

    def __init__(self) -> None:
        self.volume_front = self.volume_rear = self.freq = self.flags = 0
        self.bank = self.start = self.end = self.loop = 0
        self.pos = self.counter = self.sample = self.last = 0
        self.level = [0, 0]           # the front volumes as they ramp


class Chip:
    def __init__(self, wave: bytes | np.ndarray | WaveSpace, *, render: bool = True) -> None:
        space = wave if isinstance(wave, WaveSpace) else WaveSpace(wave)
        self.mask = space.mask
        self.render = render
        self.linear, self.mulaw = space.linear, space.mulaw
        self.voices = [Voice() for _ in range(VOICES)]
        self.noise = _noise_table()
        self.noise_at = 0

    # ---- what the driver sees ----

    def write(self, reg: int, value: int) -> None:
        if reg < 0x100:
            v = self.voices[reg >> 3]
            k = reg & 7
            if k == REG_VOLUME_FRONT:
                v.volume_front = value
            elif k == REG_VOLUME_REAR:
                v.volume_rear = value
            elif k == REG_FREQ:
                v.freq = value
            elif k == REG_FLAGS:
                v.flags = value
            elif k == REG_BANK:
                v.bank = value
            elif k == REG_START:
                v.start = value
            elif k == REG_END:
                v.end = value
            else:
                v.loop = value
        elif reg == REG_KEYS:
            for v in self.voices:
                if v.flags & KEY_ON:
                    v.pos = v.bank << 16 | v.start
                    v.sample = v.last = 0
                    v.counter = 0xFFFF
                    v.level = [0, 0]
                    v.flags = (v.flags | BUSY) & ~(KEY_ON | LOOP_HISTORY)
                elif v.flags & KEY_OFF:
                    v.flags &= ~(BUSY | KEY_OFF)
                    v.counter = 0xFFFF

    def read_flags(self, voice: int) -> int:
        return self.voices[voice].flags

    # ---- the mix ----

    def advance(self, samples: int = TICK_SAMPLES) -> np.ndarray | None:
        """The next `samples` samples: (left, right) as the chip adds them up; None without rendering."""
        out = np.zeros((samples, 2), dtype=np.int64) if self.render else None
        for v in self.voices:
            if v.flags & BUSY:
                self._run_voice(v, samples, out)
        return out

    def _run_voice(self, v: Voice, n: int, out: np.ndarray | None) -> None:
        freq = v.freq
        counter = v.counter + freq * np.arange(1, n + 1, dtype=np.int64)
        fetched = counter >> 16
        total = int(fetched[-1])
        fetches, ended = self._fetch(v, total) if total else (_NONE, False)
        if ended:                     # it stops at the step of its last fetch
            n = int(np.searchsorted(fetched, len(fetches))) + 1
            counter, fetched = counter[:n], fetched[:n]
        values = np.concatenate(((v.last, v.sample), fetches))
        current, previous = values[fetched + 1], values[fetched]
        fraction = counter & 0xFFFF
        if out is not None:
            s = current if v.flags & FILTER else previous + ((fraction * (current - previous)) >> 16)
            before = np.concatenate(((v.counter,), fraction[:-1]))
            ramps = np.cumsum(((before ^ (before + freq)) & COUNTER_RAMP_BITS) != 0)
            targets = v.volume_front >> 8, v.volume_front & 0xFF
            phases = v.flags & PHASE_FRONT_LEFT, v.flags & PHASE_FRONT_RIGHT
            for side in (0, 1):
                level = v.level[side]
                gap = targets[side] - level
                if gap == 0 and level == 0:
                    continue
                levels = level + np.sign(gap) * np.minimum(abs(gap), ramps)
                signed = -s if phases[side] else s
                out[:n, side] += (signed * levels) >> 8
                v.level[side] = int(levels[-1])
        else:                         # when the mix starts later it starts at the volumes reached
            v.level = [v.volume_front >> 8, v.volume_front & 0xFF]
        v.counter = int(fraction[-1])
        v.sample = int(values[fetched[-1] + 1])
        v.last = int(values[fetched[-1]])
        if ended:
            v.flags = (v.flags | KEY_OFF) & ~BUSY
            v.sample = 0

    def _fetch(self, v: Voice, count: int) -> tuple[np.ndarray, bool]:
        """The voice's next `count` fetched samples and whether it ended (its last value is then 0)."""
        flags = v.flags
        if flags & NOISE:
            at = self.noise_at
            self.noise_at = (at + count) % NOISE_PERIOD_LIMIT
            return np.take(self.noise, np.arange(at, at + count), mode="wrap"), False
        table = self.mulaw if flags & MULAW else self.linear
        mask = self.mask
        pieces: list[np.ndarray] = []
        left = count
        ended = False
        if flags & LOOP and flags & REVERSE:
            self._fetch_ping_pong(v, table, left, pieces)
            return np.concatenate(pieces), False
        step = -1 if flags & REVERSE else 1
        while left > 0:
            low = v.pos & 0xFFFF
            before_end = ((low - v.end) if step < 0 else (v.end - low)) & 0xFFFF
            n = min(left, before_end)
            if n:
                pieces.append(table[(v.pos + step * np.arange(n)) & mask])
                v.pos += step * n
                left -= n
            if left == 0:
                break
            sample = table[np.array([v.pos & mask])]      # the fetch at the end register
            left -= 1
            if flags & LINK and flags & LOOP:
                pieces.append(sample)
                v.pos = v.start << 16 | v.loop
                v.flags |= LOOP_HISTORY
            elif flags & LOOP:
                pieces.append(sample)
                v.pos = (v.pos & 0xFF0000) | v.loop
                v.flags |= LOOP_HISTORY
            else:
                pieces.append(_ZERO)
                ended = True
                break
        return (np.concatenate(pieces) if pieces else _NONE), ended

    def _fetch_ping_pong(self, v: Voice, table: np.ndarray, left: int, pieces: list[np.ndarray]) -> None:
        mask = self.mask
        while left > 0:
            low = v.pos & 0xFFFF
            back = bool(v.flags & BACKWARDS)
            limit = v.loop if back else v.end
            distance = (low - limit if back else limit - low) & 0xFFFF
            n = min(left, distance)
            if n == 0:                # at the limit: the direction turns on this fetch
                v.flags ^= BACKWARDS
                back = not back
                pieces.append(table[np.array([v.pos & mask])])
                v.pos += -1 if back else 1
                left -= 1
                continue
            at = np.arange(v.pos, v.pos - n, -1) if back else np.arange(v.pos, v.pos + n)
            pieces.append(table[at & mask])
            v.pos += -n if back else n
            left -= n


_NONE = np.zeros(0, dtype=np.int64)
_ZERO = np.zeros(1, dtype=np.int64)
