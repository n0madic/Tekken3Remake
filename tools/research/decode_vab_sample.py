#!/usr/bin/env python3
"""Export one locally verified Tekken 3 VAB sample as mono 16-bit PCM WAV.

By default the WAV rate is the game's playback rate: the game plays tone t at key
60 + t, and libsnd turns key, centre note and fine tuning into the SPU pitch
(docs/research/code/sound.md#playback-rate). `--sample-rate` overrides it.
"""

from __future__ import annotations

import argparse
import math
from pathlib import Path
import struct
import sys
import wave

from compare_bns import JAPAN, arc_members, read_records
from inspect_vab import GROUP_BASES, inspect


# Coefficients in 1/64 units, matching FFmpeg's ADPCM_PSX decoder.
COEFFICIENTS = ((0, 0), (60, 0), (115, -52), (98, -55), (122, -60))


def sample_bytes(header: bytes, body: bytes, vag_id: int) -> bytes:
    program_count = struct.unpack_from("<H", header, 0x12)[0]
    vag_count = struct.unpack_from("<H", header, 0x16)[0]
    if not 1 <= vag_id <= vag_count:
        raise ValueError(f"VAG ID must be within 1..{vag_count}")
    size_table = struct.unpack_from("<256H", header, 0x820 + program_count * 0x200)
    start = sum(size_table[1:vag_id]) << 3
    end = start + (size_table[vag_id] << 3)
    return body[start:end]


SPU_BASE_RATE = 44100
BASE_KEY = 60


def spu_pitch(key: int, center: int, shift: int) -> int:
    """libsnd SsPitchFromNote with fine tuning 0 (table 0x8009B0BC = floor(4096 * 2^(i/192)))."""
    fine = shift >> 3
    carry = fine >> 4
    fine &= 15
    n = key - (center - BASE_KEY) + carry
    base = math.floor(4096 * 2 ** (((n % 12) * 16 + fine) / 192))
    octave = n // 12 - 5
    return base << octave if octave > 0 else base >> -octave


def playback_rate(header: bytes, vag_id: int) -> int:
    """Rate at which the game plays the first active tone that references `vag_id`."""
    programs = [p for p in range(128) if header[0x20 + 16 * p]]
    for block, program in enumerate(programs):
        for tone in range(header[0x20 + 16 * program]):
            attr = 0x820 + block * 0x200 + tone * 32
            if struct.unpack_from("<h", header, attr + 22)[0] == vag_id:
                pitch = spu_pitch(BASE_KEY + tone, header[attr + 4], header[attr + 5])
                return round(SPU_BASE_RATE * pitch / 4096)
    raise ValueError(f"no active tone references VAG {vag_id}")


def decode_spu_adpcm(sample: bytes) -> tuple[list[int], tuple[int, int] | None]:
    if not sample or len(sample) % 16:
        raise ValueError("SPU-ADPCM sample must contain complete 16-byte frames")
    previous = older = 0
    pcm: list[int] = []
    loop_start_frame: int | None = None
    terminal_flag = sample[-15]
    for frame_index, offset in enumerate(range(0, len(sample), 16)):
        frame = sample[offset : offset + 16]
        predictor = frame[0] >> 4
        shift = frame[0] & 0x0F
        flags = frame[1]
        if predictor >= len(COEFFICIENTS) or flags & ~7:
            raise ValueError(f"invalid frame header at frame {frame_index}")
        if flags & 4 and terminal_flag == 3:
            if loop_start_frame is not None:
                raise ValueError("multiple loop-start frames")
            loop_start_frame = frame_index
        coefficient_1, coefficient_2 = COEFFICIENTS[predictor]
        for packed in frame[2:]:
            for nibble in (packed & 0x0F, packed >> 4):
                signed = nibble if nibble < 8 else nibble - 16
                correction_numerator = previous * coefficient_1 + older * coefficient_2
                correction = (
                    correction_numerator // 64
                    if correction_numerator >= 0
                    else -((-correction_numerator) // 64)
                )
                decoded = ((signed << 12) >> shift) + correction if flags < 7 else 0
                pcm.append(max(-32768, min(32767, decoded)))
                older, previous = previous, decoded
    if terminal_flag == 7:
        # Sony's one-shot IRQ-clear frame is an extra silent 16-byte block.
        if sample[-16:] != b"\x00\x07" + b"\x77" * 14:
            raise ValueError("unexpected one-shot terminal block")
        del pcm[-28:]
        return pcm, None
    if terminal_flag == 3 and loop_start_frame is not None:
        return pcm, (loop_start_frame * 28, len(pcm))
    raise ValueError("sample has no recognized one-shot or looping ending")


def append_loop_chunk(path: Path, rate: int, loop: tuple[int, int]) -> None:
    """Append a RIFF `smpl` chunk with one forward loop (end inclusive) and fix the RIFF size."""
    start, end = loop
    body = struct.pack("<9I", 0, 0, round(1e9 / rate), 60, 0, 0, 0, 1, 0)
    body += struct.pack("<6I", 0, 0, start, end - 1, 0, 0)
    with path.open("r+b") as wav:
        wav.seek(0, 2)
        wav.write(b"smpl" + struct.pack("<I", len(body)) + body)
        size = wav.tell()
        wav.seek(4)
        wav.write(struct.pack("<I", size - 8))


def main() -> int:
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--japan-track1", type=Path, default=root / "Tekken 3 (Japan) (Rev 1)" / "Tekken 3 (Japan) (Rev 1) (Track 1).bin")
    parser.add_argument("--vh-id", type=int, required=True, help="nonempty VH BNS ID (72 + 4n)")
    parser.add_argument("--vag-id", type=int, required=True, help="VAG ID within the bank, starting at 1")
    parser.add_argument("--sample-rate", type=int, help="override the WAV rate in Hz (default: the game's playback rate)")
    parser.add_argument("--out", type=Path, required=True, help="new WAV path; existing files are not overwritten")
    args = parser.parse_args()
    try:
        if args.vh_id not in (base + 1 for base in GROUP_BASES):
            raise ValueError("VH ID is outside repeated character groups")
        records, _ = read_records(args.japan_track1, JAPAN)
        header = records[args.vh_id].data
        body = arc_members(records[args.vh_id + 1].data)[2]
        inspect(header, body, args.vh_id)
        rate = args.sample_rate or playback_rate(header, args.vag_id)
        if not 1 <= rate <= 192000:
            raise ValueError("sample rate must be 1..192000 Hz")
        pcm, loop = decode_spu_adpcm(sample_bytes(header, body, args.vag_id))
        with args.out.open("xb") as output:
            with wave.open(output, "wb") as wav:
                wav.setnchannels(1)
                wav.setsampwidth(2)
                wav.setframerate(rate)
                wav.writeframes(struct.pack(f"<{len(pcm)}h", *pcm))
        if loop is not None:
            append_loop_chunk(args.out, rate, loop)
        origin = "caller-supplied" if args.sample_rate else "game playback"
        print(f"Wrote {args.out}: {len(pcm)} mono PCM samples at {origin} rate {rate} Hz")
        if loop is not None:
            print(f"Loop PCM sample range: [{loop[0]}, {loop[1]}) (written as a WAV smpl loop)")
    except (OSError, ValueError, struct.error) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
