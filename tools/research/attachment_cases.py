#!/usr/bin/env python3
"""Random cases of the costume attachments' dynamics (FUN_80037F10) run in the CPU harness.

Each case sets up one fighter record (costume slot, an attachment's rest angles and started
flag, its joint block of the previous frame, the parent joint it hangs from and the joints
that mode 1 and the lean of costume slots 0x24 / 0x29 read) and calls the game's routine; the
case records those inputs, the attachment's dynamics record and the resulting local rotation
(and the mode-1 target angles). The remake's AttachmentDynamics must reproduce every case
(tests/core/test_attachment_dynamics.gd). Used by `export_traces.py --attachments`.

Case file (`attachments.bin`): "T3AD", u32 version, u32 count, then per case:
    u8 slot, u8 attachment, u8 started, u8 pad, s16 rest[3], s16 record[12],
    6 joints in JOINT_ORDER (the attachment's own joint on the previous frame, its parent, and
    joints 12, 15, 13, 16), each s16 rot[9] + s32 t[3], s16 offset[3], s16 local[9],
    s32 target yaw, target pitch
"""

from __future__ import annotations

import random
import struct

import motion
import pose
import psxcpu

F0 = 0x800A96F0
PARAMS = 0x80096660
STATIC = 0x8009636C
RECORD = 12
FIRST = 18
JOINT_ORDER = ("previous", "parent", 12, 15, 13, 16)
SCRATCH_PARENT = 0x801F0000              # the parent matrix lives here; the joint's +0x40 points at it
TARGET_YAW, TARGET_PITCH = 0x1388, 0x138C
RECORD_POINTERS = 0x136C                 # per attachment: its dynamics record (FUN_80037EAC)
FIGHTER_BYTES = 0x188C
SLOT = 0x1C                              # s16 costume slot
REST_ANGLES = 0x129E                     # s16[3] per attachment, 8 bytes apart
STARTED = 0x1360                         # s16 per attachment
LOCALS = 0xF74                           # per part, 0x20 bytes: local s16 rot[9], then at +0x14 s32 offset[3]
LOCAL_STRIDE = 0x20
LOCAL_OFFSET = 0x14
BLOCK_PARENT = 0x40                      # a joint block's pointer to its parent's matrix


def block(joint: int) -> int:
    return F0 + 0x8F4 + 0x44 * joint


def _random_rotation(rng: random.Random, tab: pose.ExeTables) -> list[int]:
    m = pose.euler_to_matrix(rng.getrandbits(16), rng.getrandbits(16), rng.getrandbits(16), tab)
    return [m[r][c] for r in range(3) for c in range(3)]


def write_matrix(cpu: psxcpu.PsxCpu, addr: int, rot: list[int], t: list[int]) -> None:
    cpu.write(addr, struct.pack("<9h", *rot) + b"\0\0" + struct.pack("<3i", *t))


def dynamic_slots(cpu: psxcpu.PsxCpu) -> list[tuple[int, int, int, list[int]]]:
    """(costume slot, attachment, record address, record) of every attachment with dynamics."""
    out = []
    for slot in range(52):
        for i in range(4):
            ptr = struct.unpack("<I", cpu.read(PARAMS + 4 * (6 * slot + i), 4))[0]
            if ptr != STATIC:
                out.append((slot, i, ptr, list(struct.unpack(f"<{RECORD}h", cpu.read(ptr, 2 * RECORD)))))
    return out


def generate(count: int, seed: int = 5) -> bytes:
    rng = random.Random(seed)
    cpu = psxcpu.load_release()
    tab = pose.ExeTables(motion.load_exe())
    choices = dynamic_slots(cpu)
    out = bytearray(b"T3AD" + struct.pack("<II", 1, count))
    blank = bytes(FIGHTER_BYTES)
    for _ in range(count):
        slot, i, pointer, record = rng.choice(choices)
        part = FIRST + i
        cpu.write(F0, blank)
        cpu.write(F0 + SLOT, struct.pack("<h", slot))
        cpu.write(F0 + RECORD_POINTERS + 4 * i, struct.pack("<I", pointer))        # FUN_80037EAC
        cpu.write(F0 + LOCALS + LOCAL_STRIDE * part, struct.pack("<9h", 0x1000, 0, 0, 0, 0x1000, 0, 0, 0, 0x1000))
        rest = [rng.getrandbits(16) - 0x8000 for _ in range(3)] if rng.random() < 0.7 else [0, 0, 0]
        started = int(rng.random() < 0.9)
        cpu.write(F0 + REST_ANGLES + 8 * i, struct.pack("<3h", *rest))
        cpu.write(F0 + STARTED + 2 * i, struct.pack("<h", started))
        joints = {}
        for name in JOINT_ORDER:
            rot = _random_rotation(rng, tab)
            t = [rng.randrange(-2500, 2500), rng.randrange(-2200, 150), rng.randrange(-2500, 2500)]
            joints[name] = (rot, t)
        # The previous frame's own joint near its parent, so the attachment's tip is realistic.
        pr, pt = joints["parent"]
        joints["previous"] = (joints["previous"][0], [pt[0] + rng.randrange(-400, 400), pt[1] + rng.randrange(-400, 400),
                                                      pt[2] + rng.randrange(-400, 400)])
        write_matrix(cpu, block(part), *joints["previous"])
        write_matrix(cpu, SCRATCH_PARENT, *joints["parent"])
        cpu.write(block(part) + BLOCK_PARENT, struct.pack("<I", SCRATCH_PARENT))
        for j in (12, 15, 13, 16):
            write_matrix(cpu, block(j), *joints[j])
        offset = [rng.randrange(-300, 300) for _ in range(3)]
        cpu.write(F0 + LOCALS + LOCAL_STRIDE * part + LOCAL_OFFSET, struct.pack("<3i", *offset))
        cpu.write(F0 + TARGET_YAW, struct.pack("<2i", rng.getrandbits(12), rng.getrandbits(12)))
        cpu.call(0x80037F10, F0, part)
        local = list(struct.unpack("<9h", cpu.read(F0 + LOCALS + LOCAL_STRIDE * part, 18)))
        yaw, pitch = struct.unpack("<2i", cpu.read(F0 + TARGET_YAW, 8))
        out += struct.pack("<4B", slot, i, started, 0) + struct.pack("<3h", *rest) + struct.pack(f"<{RECORD}h", *record)
        for name in JOINT_ORDER:
            rot, t = joints[name]
            out += struct.pack("<9h3i", *rot, *t)
        out += struct.pack("<3h", *offset) + struct.pack("<9h", *local) + struct.pack("<2i", yaw, pitch)
    return bytes(out)
