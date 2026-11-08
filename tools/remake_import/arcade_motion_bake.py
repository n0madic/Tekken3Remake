"""The arcade's moves and motions (MAME's tekken3 set) → the remake's motion bank.

All 17 motion types share one table of 0x3C-byte move rows and one list of branch rows, and each
type has a full slot table (docs/research/arcade/moves.md): the bank is written once, with a slot
table per type, the rows in the 14 words `content/move_row.gd` reads plus the attack joints.

A stream (`FUN_80194744`): the frame count, the first and last frames' channels, then per 16 frames
of each channel bit-packed differences. Each frame is baked once, 57 s16 channels: 3 root channels
(angle, height, distance) and 18 joints' Euler angles. Verified against the game's routine by
tools/research/verify_arcade_motion.py.
"""

from __future__ import annotations

import struct

import arcade
from common import Output, gzipped, log

BANK_NAME = "arcade"
MOVE_ROWS = 0x80025E8C
MOVE_ROW = 0x3C
ROW_COUNT = 0x1307
SLOT_TABLES = 0x8006D430        # types × slots × u32 row number
SLOTS = 0xEDE
TYPES = 17
BRANCHES = 0x800ACA38
BRANCH_BYTES = 12
BRANCH_COUNT = 60832
EVENTS, EVENTS_END = 0x8001E8BC, 0x800222BC     # (u16 frame, u16 command) lists
SOUNDS, SOUNDS_END = 0x800222BC, MOVE_ROWS      # u16 lists ending 0xFFFF
ANIM_TABLE = 0x22DAD08          # the file table (program ROM)
ANIM_ENTRY = 8
# A stream address's top nibble names its ROM region.
REGION_MASK = 0xF0000000
REGIONS = {0xA0000000: 0x61800000, 0x90000000: 0x70387290, 0xB0000000: 0x522DAD08}
CHANNELS = 57
FIRST_FRAME = 2                 # stream offsets: u8 frames, then 57 s16 twice, then u16 per 16 frames
LAST_FRAME = FIRST_FRAME + 2 * CHANNELS
BLOCKS = LAST_FRAME + 2 * CHANNELS
BLOCK_FRAMES = 16
NO_LIST = 0xFFFFFFFF
NO_RECORD = 0xFFFFFFFF
# Difference codes: (offset, bits, mask).
CODES = {1: (-0x54, 6, 0x3F), 2: (-0x14, 4, 0xF), 3: (-4, 2, 3), 4: (1, 2, 3), 5: (5, 4, 0xF), 6: (0x15, 6, 0x3F)}
FINE_CHANNELS = (1, 2)          # the root's height and distance: steps of 4 (the others: of 16)
FINE_SHIFT, COARSE_SHIFT = 2, 4
ABSOLUTE_CODE = 7
ABSOLUTE_BITS = 12


def s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


class ChannelBlock:
    """One channel's differences through one block of a stream, a frame at a time."""

    def __init__(self, words: bytes, at: int, start: int, shift: int) -> None:
        self.words = words
        first = struct.unpack_from("<H", words, at)[0]
        self.next_block = at + 2 * (first & 0xF)
        self.at = at + 2
        self.bits = 12
        self.value = first >> 4
        self.run = 0
        self.code = 0
        self.current = start
        self.shift = shift

    def _refill(self, need: int) -> None:
        if self.bits < need:
            word = struct.unpack_from("<H", self.words, self.at)[0]
            self.at += 2
            self.value = s32(self.value + (word << self.bits))
            self.bits += 16

    def step(self) -> int:
        self._refill(16)
        if self.run == 0:
            self.code = self.value & 0xF
            if self.code > 7:
                self.run = ((self.value >> 4) + 1) & 0xF
                self.code -= 8
                self.bits -= 8
                self.value >>= 8
            else:
                self.bits -= 4
                self.value >>= 4
        else:
            self.run -= 1
        if self.code == ABSOLUTE_CODE:
            self._refill(ABSOLUTE_BITS)
            self.current = (self.value & 0xFFF) << self.shift
            self.value >>= ABSOLUTE_BITS
            self.bits -= ABSOLUTE_BITS
        elif self.code:
            offset, bits, mask = CODES[self.code]
            self.current += (offset + (self.value & mask)) << self.shift
            self.value >>= bits
            self.bits -= bits
        return self.current & 0xFFFF


def stream_frames(read, address: int) -> list[bytes]:
    """Every frame of the stream at ROM `address`, each 57 little-endian s16. `read(address, size)`
    reads the ROM."""
    count = read(address, 1)[0]
    head = read(address, BLOCKS + 2 * ((count + BLOCK_FRAMES) // BLOCK_FRAMES))
    first = head[FIRST_FRAME:FIRST_FRAME + 2 * CHANNELS]
    last = head[LAST_FRAME:LAST_FRAME + 2 * CHANNELS]
    if count < 2:
        return [last]
    base = struct.unpack(f"<{CHANNELS}H", first)
    frames = [first]
    # Frames f = 1 .. count − 2 are decoded from block (f − 1) / 16, each from the first frame's values.
    done = 1
    while done < count - 1:
        block = (done - 1) // BLOCK_FRAMES
        start = address + 2 * struct.unpack_from("<H", head, BLOCKS + 2 * block)[0]
        data = read(start, 0x600)
        at = 0
        channels = []
        for c in range(CHANNELS):
            shift = FINE_SHIFT if c in FINE_CHANNELS else COARSE_SHIFT
            channel = ChannelBlock(data, at, base[c], shift)
            channels.append(channel)
            at = channel.next_block
        for _ in range(BLOCK_FRAMES):
            if done >= count - 1:
                break
            frames.append(struct.pack(f"<{CHANNELS}H", *(channel.step() for channel in channels)))
            done += 1
    frames.append(last)
    return frames


def stream_address(arc: arcade.ArcadeSet, anim_word: int) -> int:
    a = struct.unpack("<I", arc.read(ANIM_TABLE + ANIM_ENTRY * anim_word, 4))[0]
    region = a & REGION_MASK
    return (a + REGIONS[region]) & 0xFFFFFFFF if region in REGIONS else a


def row_words(arc: arcade.ArcadeSet, index: int, stream: int) -> list[int]:
    """A move row as the 14 words of a PlayStation row (`motion_bake.py`), the anim word being the
    row's stream, plus the attack joints as a 15th."""
    raw = arc.prog(MOVE_ROWS + MOVE_ROW * index, MOVE_ROW)
    (_anim, state, attack, hints, branches, stance, damage, camera, b15, b16, b17, flags, end_turn, _frames, air_first,
     air_last, hold, step, sounds, events, reaction, close, active_first, active_last, a0, b0, a1, b1, freeze, _pad,
     body) = struct.unpack("<IIHHIHHBBBBIhBBBBhIIHHBBBBBBBBh2x", raw)
    word_flags = (camera | (flags & 0x7F) << 8 | (flags & 0x180) << 9 | (flags >> 31) << 18
                  | (b15 == 1) << 28 | (b16 == 1) << 29 | (b17 == 1) << 30)
    return [
        stream,
        state,
        attack | (hints & 0xFF) << 16,
        branches,
        stance | (end_turn & 0xFFFF) << 16,
        damage | (step & 0xFFFF) << 16,
        air_first << 8 | air_last << 16 | hold << 24,
        sounds,
        events,
        word_flags,
        NO_RECORD,
        freeze | active_first << 8 | active_last << 16,
        (body & 0xFFFF) | reaction << 16,
        close,
        a0 | b0 << 8 | a1 << 16 | b1 << 24,
    ]


def convert(arc: arcade.ArcadeSet, out: Output) -> dict:
    """Writes the bank; returns what the tables need: stream ids by row (reversal lists name rows)."""
    ids: dict[int, int] = {}            # stream address → stream id (the anim word of its rows)
    streams = []
    row_streams = []
    for r in range(ROW_COUNT):
        anim_word = struct.unpack("<I", arc.prog(MOVE_ROWS + MOVE_ROW * r, 4))[0]
        address = stream_address(arc, anim_word)
        if address not in ids:
            ids[address] = len(streams)
            streams.append(address)
        row_streams.append(ids[address])
    poses = bytearray()
    anims = {}
    first_pose = 0
    for index, address in enumerate(streams):
        frames = stream_frames(arc.read, address)
        for frame in frames:
            poses += frame
        count = arc.read(address, 1)[0]
        anims[str(index)] = [first_pose, len(frames), count, index + 1]
        first_pose += len(frames)
    branch_data = arc.prog(BRANCHES, BRANCH_BYTES * BRANCH_COUNT)
    data = {
        "name": BANK_NAME,
        "type": -1,
        "moves": [row_words(arc, r, row_streams[r]) for r in range(ROW_COUNT)],
        "slots": [list(arc.prog_values(f"<{SLOTS}I", SLOT_TABLES + 4 * SLOTS * t)) for t in range(TYPES)],
        "anims": anims,
        "branches": [list(struct.unpack_from("<HBBHHBBBB", branch_data, BRANCH_BYTES * i)) for i in range(BRANCH_COUNT)],
        "sounds": list(arc.prog_values(f"<{(SOUNDS_END - SOUNDS) // 2}H", SOUNDS)),
        "events": list(arc.prog_values(f"<{(EVENTS_END - EVENTS) // 2}H", EVENTS)),
    }
    out.write_json(f"motion/{BANK_NAME}.json.gz", data)
    out.write(f"motion/{BANK_NAME}.poses.bin.gz", gzipped(bytes(poses)))
    log.info("arcade: %d rows, %d streams, %d frames", ROW_COUNT, len(streams), first_pose)
    return {"row_streams": row_streams}
