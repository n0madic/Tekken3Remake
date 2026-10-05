#!/usr/bin/env python3
"""Run the attract demonstration (enbu.ovl, Japan Rev.1) in the CPU harness and record it.

The game's own `FUN_800D3CCC` (reset and bank link) and `FUN_800D3D64` (the performance, one
call per frame) run in the Unicorn harness on the overlay's embedded motion bank, with the
common bank `divmot99` loaded. The routines that load files, upload textures, draw, play
music or set up the stage are replaced by stubs (the background and the stage set-up keep their
panorama-turn part, `BACKDROP_PATCHES`); the script runner, `MoveLookup`,
`MoveEvents`, the camera (`CameraReset`, `FUN_80069388`, `FUN_800661C0`, the camera reel
`FUN_800673E4`/`FUN_80066D00` with `CameraChoose` and `CameraUseSource`, and the director call
of the set-up frame) and `rand()` run as game code. The engine calls that `MoveEvents` makes
(effects, dust, camera shake, vibration, hand and face commands) and the fade are logged.

`record(demo)` returns one `Frame` per call of `FUN_800D3D64`, until the call that returns 1
(the script's end event). Used by `export_traces.py --enbu`.
"""

from __future__ import annotations

import logging
import struct
from dataclasses import dataclass, field

import fight_harness as fh
import psxcpu

log = logging.getLogger("enbu_harness")

FIGHTERS = (0x800A96F0, 0x800AAF7C)
DEMO = 0x800DDE2C                # u8 demonstration number (copied from 0x80098300)
RUNNER = 0x8010C43C              # per fighter 10 bytes: s16 state, costume, move slot, end, frame
RUNNER_PHASE = 0x8010C418        # 0 set-up, 1 music wait, 2 script
SCRIPT_FRAME = 0x8010C41C
FADE_LEVEL = 0x8010C428
REEL_DONE = 0x8010C450
VIEW = 0x800A8A88                # g_camera: +0 pitch, +4 yaw, +0x14 x, y, z
PROJECTION = 0x800A919C          # s16 GTE H
GAME_MODE, CPU_FLAG = 0x800AFF50, 0x800AE39C
DIVMOT_BUFFER = 0x800AE348       # g_divmotBuffer; divmot99 lives at +0xB4C94
COMMON_AT = 0x80180000           # where the harness puts divmot99 (free RAM above the overlay)
COMMON_OFFSET = 0xB4C94

MOVE_EVENTS = 0x80045B60
NOOP = {
    # set-up: loading, VRAM uploads, stage, models, replay, music
    0x8002988C, 0x80029860, 0x80036180, 0x8006C870, 0x8006C900, 0x80048324,
    0x8006C924, 0x80076484, 0x80076704, 0x80035D7C, 0x80035E14, 0x80035F34, 0x80035F3C,
    0x8004AAD4, 0x80039BB4, 0x80031F60, 0x8006B0FC,
    # per frame: drawing, lights, shadows, body spheres, effect rings
    0x800484D8, 0x8003A030, 0x8003EEFC, 0x8003A1D8, 0x80036254, 0x80077744,
    0x8004AEBC,
}
RETURN_ZERO = {0x8006CAE8, 0x80077878, 0x8006BCC8}
# The background (FUN_8006DAB4) and the stage set-up (FUN_8006CC44) reduced to the panorama's turn
# (BackdropTurn): FUN_8006E4A0 added to the angle; the angle cleared and the camera's yaw noted.
BACKDROP_PATCHES = {
    0x8006DAB4: fh.PANORAMA_TURN_ONLY[1],
    0x8006CC44: [
        0x3C08800B,                 # lui t0, 0x800B
        0xAD009650,                 # sw zero, -0x69B0(t0)     0x800A9650 angle
        0x3C09800B,                 # lui t1, 0x800B
        0x8D298A8C,                 # lw t1, -0x7574(t1)       0x800A8A8C camera yaw
        0x31290FFF,                 # andi t1, t1, 0xFFF
        0xAD099658,                 # sw t1, -0x69A8(t0)       0x800A9658
        0x03E00008,                 # jr ra
        0xAD099664,                 # sw t1, -0x699C(t0)       0x800A9664
    ],
}
BACKDROP = 0x800A9650            # angle, and at +8 / +0x14 the last and this frame's yaw
LOOK_POINT = 0x800AE0D8          # x, then z at +8
ROUND_STATE = 0x80097350
ROUND_STATE_AFTER_FIGHT = 9      # as a fight's end leaves it: the backdrop turns (FUN_8006E4A0)
# MoveEvents' engine calls: name, argument count logged
LOGGED = {
    0x80076E58: ("effect", 1),         # EffectSpawn(set, 0, point) + replay log
    0x80076EB8: ("spark", 1),          # EffectSpawn(3, index, point) + replay log
    0x8004AF1C: ("dust", 0),
    0x800760D4: ("vibrate", 2),        # FighterVibrate(player, pattern)
    0x800346F8: ("hand_face", 4),      # HandFaceCommand(fighter, hands, shape, speed)
    0x8004AF94: ("shake", 1),          # CameraShakeStart(script)
    0x8003AA6C: ("animate", 1),        # FUN_8003AA6C(fighter): lights and FighterAnimate
}
FADE_DRAW = 0x8004E2E8               # (ot, packet, level) -> next packet


@dataclass
class Frame:
    phase: int                                   # RUNNER_PHASE before the call
    script_frame: int                            # SCRIPT_FRAME before the call
    runner: list[list[int]]                      # per fighter: state, costume, slot, end, frame (after)
    fighter: list[list[int]]                     # per fighter: poseFrame, rootFrame, prevPoseFrame,
                                                 #   costumeSlot, costumeKey, charId (after)
    camera: list[int]                            # pitch, yaw, x, y, z, H (after)
    backdrop: list[int]                          # angle, last and this frame's yaw, point x, z (after)
    fade: int                                    # level passed to the fade draw, -1 without
    calls: list[tuple] = field(default_factory=list)   # (name, fighter index or -1, args...)
    done: bool = False


def _s16(cpu: psxcpu.PsxCpu, addr: int) -> int:
    return struct.unpack("<h", cpu.read(addr, 2))[0]


def _s32(cpu: psxcpu.PsxCpu, addr: int) -> int:
    return struct.unpack("<i", cpu.read(addr, 4))[0]


class EnbuHarness:
    def __init__(self) -> None:
        self.cpu = psxcpu.load_release(overlay="enbu")
        self.calls: list[tuple] = []
        self.fade = -1
        self.events_of = -1
        cpu = self.cpu
        for addr in NOOP:
            cpu.stub(addr, lambda c, *a: 0)
        for addr in RETURN_ZERO:
            cpu.stub(addr, lambda c, *a: 0)
        for addr, words in BACKDROP_PATCHES.items():
            for k in range(len(words)):
                cpu.drop_cop2(addr + 4 * k)
            cpu.write(addr, struct.pack(f"<{len(words)}I", *words))
        for addr, (name, count) in LOGGED.items():
            cpu.stub(addr, self._logger(name, count))
        cpu.stub(FADE_DRAW, self._fade)
        cpu.uc.hook_add(psxcpu.UC_HOOK_CODE, self._events_entry, begin=MOVE_EVENTS, end=MOVE_EVENTS)
        self._load_common()

    def _logger(self, name: str, count: int):
        def stub(cpu: psxcpu.PsxCpu, *args: int) -> int:
            values = [a - (1 << 32) if a & 0x80000000 else a for a in args[:count]]
            if name in ("hand_face", "animate"):
                values[0] = FIGHTERS.index(args[0])
            self.calls.append((name, self.events_of, *values))
            return 0
        return stub

    def _fade(self, cpu: psxcpu.PsxCpu, ot: int, packet: int, level: int, *_: int) -> int:
        self.fade = level - (1 << 32) if level & 0x80000000 else level
        return packet

    def _events_entry(self, uc, address: int, size: int, _user) -> None:
        self.events_of = FIGHTERS.index(uc.reg_read(psxcpu.UC_MIPS_REG_A0))

    def _load_common(self) -> None:
        """divmot99 relocated as DivmotRelocateCommon does it (g_divmotCommon = buffer + 0xB4C94)."""
        common = (fh.BNS_DIR / "279_divmot99.bin").read_bytes()
        self.cpu.write(COMMON_AT, common)
        self.cpu.write(DIVMOT_BUFFER, struct.pack("<I", COMMON_AT - COMMON_OFFSET))
        self.cpu.call(0x80069B84)

    def record(self, demo: int, limit: int = 5000) -> list[Frame]:
        cpu = self.cpu
        # The fighter records' fixed identity, set once at boot: playerIndex (+0x12), index (+0x1E)
        # and the default opponent (+0x20).
        for i, f in enumerate(FIGHTERS):
            cpu.write(f + 0x12, struct.pack("<h", i))
            cpu.write(f + 0x1E, bytes([i]))
            cpu.write(f + 0x20, bytes([1 - i]))
        cpu.write(DEMO, bytes([demo]))
        cpu.write(GAME_MODE, struct.pack("<I", 6))
        cpu.write(CPU_FLAG, struct.pack("<H", 1))
        cpu.write(ROUND_STATE, struct.pack("<I", ROUND_STATE_AFTER_FIGHT))
        cpu.call(0x800D3CCC)
        frames: list[Frame] = []
        for _ in range(limit):
            self.calls = []
            self.fade = -1
            self.events_of = -1
            phase, script_frame = _s32(cpu, RUNNER_PHASE), _s32(cpu, SCRIPT_FRAME)
            done = cpu.call(0x800D3D64) & 0xFFFFFFFF
            frames.append(Frame(
                phase=phase,
                script_frame=script_frame,
                runner=[[_s16(cpu, RUNNER + 10 * i + 2 * k) for k in range(5)] for i in range(2)],
                fighter=[[_s16(cpu, f + o) for o in (0x58, 0x50, 0x5A, 0x1C, 0x14, 0x18)] for f in FIGHTERS],
                camera=[_s32(cpu, VIEW), _s32(cpu, VIEW + 4), _s32(cpu, VIEW + 0x14), _s32(cpu, VIEW + 0x18),
                        _s32(cpu, VIEW + 0x1C), _s16(cpu, PROJECTION)],
                backdrop=[_s32(cpu, BACKDROP), _s32(cpu, BACKDROP + 8), _s32(cpu, BACKDROP + 0x14),
                          _s32(cpu, LOOK_POINT), _s32(cpu, LOOK_POINT + 8)],
                fade=self.fade,
                calls=self.calls,
                done=bool(done),
            ))
            if done:
                return frames
        raise RuntimeError(f"demonstration {demo} did not end within {limit} frames")


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    for demo in range(3):
        frames = EnbuHarness().record(demo)
        kinds: dict[str, int] = {}
        for f in frames:
            for c in f.calls:
                kinds[c[0]] = kinds.get(c[0], 0) + 1
        log.info("demonstration %d: %d frames, calls %s", demo, len(frames), kinds)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
