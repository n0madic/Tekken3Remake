"""Motion banks (divmot*.bin) → move tables, baked pose vectors and baked camera streams.

Animation streams are sampled once, for every frame, with the verified integer
sampler (`tools/research/motion.py`, bit-exact with AnimDecodePose for all 314,290 frames).
The remake reads the baked 49-channel pose vectors instead of evaluating the
B-spline curves at run time, as animation.md recommends for converters. Camera
streams (section 8) are baked the same way with `camera_scripts.CameraStream`
(bit-exact with FUN_80038F38 for all 86,058 frames).

Output (`motion/<bank>.json.gz`, `motion/<bank>.poses.bin.gz`, `motion/<bank>.camera.bin`,
`motion/<bank>.attacks.bin`):

- `moves`: the 56-byte move rows as 14 unsigned words each (decoded by `content`);
- `move_index`: the 4,023 slot entries (`0x40000000 + row` refers to the common bank);
- `empty_slots`: section 5 as u16 words, bit `s` set when slot `s` is empty in this bank;
- `anims`: stream offset (section 6) → `[first pose, frame count, first byte, tag]`: the stream
  header's first byte (DivmotLinkBank stores it as the move's length) and the `s16` animation
  tag before the stream (reversal condition 0x4B);
- `branches`: section 0 as `[command, restriction, condition, parameter, target, flags, first,
  last, entry]` rows (divmot-banks.md#branch-rows-section-0-12-bytes);
- `sounds`: section 3 as u16 words; a move's list starts at word `move +0x1C`;
- `events`: section 4 as u16 words; a move's list starts at word `2 · (move +0x20)`;
- `camera_choices`: section 7 as `[kind, weight, script]` entries (camera.md#choice-lists);
- `camera_streams`: section-8 offset → `[first sample, frame count, yaw mode]`;
- `poses.bin.gz` (gzip): all baked frames, 49 little-endian s16 per frame;
- `attacks.bin`: section 9 as it is (attack records, referenced by move `+0x28` − 4);
- `camera.bin`: all baked camera samples, 7 little-endian s16 per frame (eye x, y, z,
  target x, y, z, weight), as FUN_80038F38 returns them.
"""

from __future__ import annotations

import struct

from common import Disc, Output, gzipped
import camera_scripts
import motion

COMMON_BANK = "divmot99"
CHOICE_BYTES = 8
BRANCH_SECTION, SOUND_SECTION, EMPTY_SECTION = 0, 3, 5
EVENT_SECTION, CHOICE_SECTION, STREAM_SECTION, ATTACK_SECTION = 4, 7, 8, 9
BRANCH_BYTES = 12


def anim_offsets(bank: motion.MotionBank) -> list[int]:
    """Section-6 offsets of every stream the bank's own move rows reference."""
    found = set()
    for row in range(bank.move_count):
        word = bank.move_row(row)[0]
        if word < motion.COMMON_FLAG:
            found.add(word)
    return sorted(found)


def common_offsets(bank: motion.MotionBank) -> set[int]:
    """Section-6 offsets of the common bank's streams the bank's move rows reference."""
    return {w - motion.COMMON_FLAG for w in (bank.move_row(r)[0] for r in range(bank.move_count))
            if w >= motion.COMMON_FLAG}


def convert_all(disc: Disc, out: Output, banks: list[tuple[str, int]], common: str) -> None:
    """Every bank; the common bank also bakes the streams the other banks' rows use."""
    used: set[int] = set()
    for name, record_id in banks:
        if name != common:
            used |= common_offsets(motion.parse_bank(disc.bns(record_id)))
    for name, record_id in banks:
        convert_bank(disc, out, name, disc.bns(record_id), used if name == common else set())


def section(bank: motion.MotionBank, index: int) -> bytes:
    return bank.data[bank.bounds[index]:bank.bounds[index + 1]]


def camera_choices(bank: motion.MotionBank) -> list[list[int]]:
    data = section(bank, CHOICE_SECTION)
    return [list(struct.unpack_from("<hHi", data, i)) for i in range(0, len(data) - CHOICE_BYTES + 1, CHOICE_BYTES)]


def convert(disc: Disc, out: Output, name: str, record_id: int) -> None:
    convert_bank(disc, out, name, disc.bns(record_id))


def convert_bank(disc: Disc, out: Output, name: str, data: bytes,
                 extra: set[int] = frozenset()) -> motion.MotionBank:
    bank = motion.parse_bank(data)
    spline = motion.SplineTables(disc.exe)
    poses = bytearray()
    anims = {}
    frame_total = 0
    for offset in sorted(set(anim_offsets(bank)) | extra):
        at = bank.anim_offset(offset)
        stream = motion.parse_anim(data, at)
        tag = struct.unpack_from("<h", data, at - 2)[0]
        anims[str(offset)] = [frame_total, stream.frames, data[at], tag]
        for frame in range(stream.frames):
            poses += struct.pack("<49h", *motion.sample_pose(stream, frame, spline))
        frame_total += stream.frames

    choices = camera_choices(bank)
    samples = bytearray()
    streams = {}
    sample_total = 0
    for kind, _, script in choices:
        offset = script & 0xFFFF
        if kind != 2 or script >= 0 or script == -1 or str(offset) in streams:
            continue
        mode, stream = camera_scripts.stream_at(data, bank.bounds[STREAM_SECTION] + offset, spline)
        streams[str(offset)] = [sample_total, stream.frames, mode]
        for frame in range(stream.frames):
            samples += struct.pack("<7h", *stream.sample(frame))
        sample_total += stream.frames

    has_index = bank.bounds[3] > bank.bounds[2]
    events = section(bank, EVENT_SECTION)
    sounds = section(bank, SOUND_SECTION)
    empty = section(bank, EMPTY_SECTION)
    branch_data = section(bank, BRANCH_SECTION)
    branches = [list(struct.unpack_from("<HBBHHBBBB", branch_data, i))
                for i in range(0, len(branch_data) - BRANCH_BYTES + 1, BRANCH_BYTES)]
    out.write(f"motion/{name}.poses.bin.gz", gzipped(bytes(poses)))
    out.write(f"motion/{name}.attacks.bin", section(bank, ATTACK_SECTION))
    out.write(f"motion/{name}.camera.bin", bytes(samples))
    out.write_json(f"motion/{name}.json.gz", {
        "name": name,
        "type": bank.type_code,
        "moves": [list(bank.move_row(r)) for r in range(bank.move_count)],
        "move_index": bank.move_index if has_index else [],
        "empty_slots": list(struct.unpack(f"<{len(empty) // 2}H", empty)),
        "branches": branches,
        "sounds": list(struct.unpack(f"<{len(sounds) // 2}H", sounds)),
        "anims": anims,
        "frames": frame_total,
        "events": list(struct.unpack(f"<{len(events) // 2}H", events)),
        "camera_choices": choices,
        "camera_streams": streams,
    })
    return bank
