#!/usr/bin/env python3
"""Compare ogre_scene_sim.py with the Ogre scene (arcade.ovl, Japan Rev.1) in the CPU harness.

Every engine call of FUN_800B4168 and FUN_800B4528 is replaced by a stub that appends its id and
arguments to one shared log in RAM (and returns test values where the scene uses a result); the
port's hooks write the same log. Each case randomises the scene state (script position, a random
script or the game's own, scripted moves, fade, camera) and compares all of RAM (packets and
ordering tables included) and the return value.

Usage: python3 tools/research/verify_ogre_scene_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import logging
import random
import struct

import draw_sim as ds
import ogre_scene_sim as og
import verify_draw_sim as vd
import verify_menu_sim as vm

log = logging.getLogger("verify_ogre_scene_sim")
M32 = 0xFFFFFFFF

CALLS = 0x801F8400               # u32 count, then id and arguments of every engine call
REEL_RET, LOOKUP_RET = 0x801F8380, 0x801F8384
PARTS_RET = (0x801F8388, 0x801F838C)
LOAD_OUT = 0x801F8390            # two words FighterLoadCharacter writes through a1, a2
TRAMPOLINES = 0x801E0000
SCRIPT = 0x801F7400
RECORDS = 0x801F7000             # stand-in move records (only +0x24 is used)
SCENE_OT_AREA, SCENE_OT = 0x801F8280, 0x801F0000

# name: (address, arguments logged, result kind)
ENGINE = {
    "floor_setup": (0x80048548, 1, None), "menu_close": (0x8004B920, 1, None),
    "fighter_reset": (0x8003C4AC, 1, None), "face_opponent": (0x8002BFCC, 2, None),
    "select_banks": (0x8007522C, 0, None), "costume_set": (0x80036440, 2, None),
    "load_request": (0x8006C900, 4, None), "load_character": (0x80036564, 1, "out"),
    "model_nop": (0x80035F34, 3, None), "model_bind": (0x80035F3C, 3, None),
    "part_a": (0x80036124, 1, PARTS_RET[0]), "part_b": (0x80036140, 1, PARTS_RET[1]),
    "load_commit": (0x8006C924, 2, None), "camera_reset": (0x80062CF8, 0, None),
    "camera_restart": (0x80069388, 2, None), "camera_sources_reset": (0x800661C0, 2, None),
    "camera_reel": (0x800673E4, 1, REEL_RET), "move_lookup": (0x8002D3CC, 2, LOOKUP_RET),
    "move_events": (0x80045B60, 2, None), "fighter_frame": (0x8003AA6C, 1, None),
    "camera_director": (0x800633C0, 3, None), "camera_frame": (0x800484D8, 2, None),
    "clear_tile": (0x8006DAB4, 0, None), "clear_tile_black": (0x8004860C, 1, None),
    "stage_colour": (0x8003A030, 1, None), "body_profile": (0x8003EEFC, 2, None),
    "light_decay": (0x8003A1D8, 0, None), "shadow_matrices": (0x80036254, 0, None),
    "frame_count": (0x80037B4C, 0, None), "music": (0x8006B0FC, 2, None),
}
IDS = {name: i + 1 for i, name in enumerate(ENGINE)}
T0, T1, T2, T3, T4, T5, T6, V0, A0, RA = 8, 9, 10, 11, 12, 13, 14, 2, 4, 31


def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & M32))


def _hi_lo(a: int) -> tuple[int, int]:
    return (a + 0x8000) >> 16 & 0xFFFF, a & 0xFFFF


def _i(op: int, rs: int, rt: int, imm: int) -> int:
    return op << 26 | rs << 21 | rt << 16 | imm & 0xFFFF


def engine_stub(ident: int, nargs: int, result) -> list[int]:
    """Appends `ident` and a0..a(n-1) to CALLS; returns the word at `result`, or copies the two
    LOAD_OUT words through a1 and a2 when `result` is "out"."""
    hi, lo = _hi_lo(CALLS)
    code = [_i(0xF, 0, T0, hi), _i(0x9, T0, T0, lo),           # lui/addiu t0 = CALLS
            _i(0x23, T0, T1, 0), 0,                              # lw t1, 0(t0)
            T1 << 16 | T2 << 11 | 2 << 6,                        # sll t2, t1, 2
            T2 << 21 | T0 << 16 | T2 << 11 | 0x21,               # addu t2, t2, t0
            _i(0x9, 0, T3, ident), _i(0x2B, T2, T3, 4)]          # sw ident, 4(t2)
    code += [_i(0x2B, T2, A0 + k, 8 + 4 * k) for k in range(nargs)]
    code += [_i(0x9, T1, T1, 1 + nargs), _i(0x2B, T0, T1, 0)]
    if result == "out":
        hi2, lo2 = _hi_lo(LOAD_OUT)
        code += [_i(0xF, 0, T4, hi2), _i(0x23, T4, T5, lo2), _i(0x23, T4, T6, lo2 + 4), 0,
                 _i(0x2B, A0 + 1, T5, 0), _i(0x2B, A0 + 2, T6, 0)]
    elif result is not None:
        hi2, lo2 = _hi_lo(result)
        code += [_i(0xF, 0, V0, hi2), _i(0x23, V0, V0, lo2), 0]
    return code + [RA << 21 | 8, 0]                            # jr ra; nop


def install_stubs(cpu) -> None:
    t = TRAMPOLINES
    for name, (addr, nargs, result) in ENGINE.items():
        code = engine_stub(IDS[name], nargs, result)
        cpu.write(t, struct.pack(f"<{len(code)}I", *code))
        cpu.write(addr, struct.pack("<2I", 0x08000000 | (t >> 2) & 0x3FFFFFF, 0))   # j t; nop
        t += 4 * len(code)


class LogHooks(og.OgreHooks):
    def _log(self, ram, name: str, args) -> None:
        vd.ram_log(ram, CALLS, IDS[name])
        n = ram.u32(CALLS)
        for k, v in enumerate(args):
            ram.put(CALLS + 4 + 4 * (n + k), "I", v & M32)
        ram.put(CALLS, "I", n + len(args))

    def call(self, ram, name: str, *args: int) -> None:
        assert len(args) == ENGINE[name][1], name
        self._log(ram, name, args)

    def camera_reel(self, ram, kind: int) -> int:
        self._log(ram, "camera_reel", (kind,))
        return ram.u32(REEL_RET)

    def move_lookup(self, ram, fighter: int, slot: int) -> int:
        self._log(ram, "move_lookup", (fighter, slot))
        return ram.u32(LOOKUP_RET)

    def load_character(self, ram, fighter: int) -> tuple[int, int]:
        self._log(ram, "load_character", (fighter,))
        return ram.u32(LOAD_OUT), ram.u32(LOAD_OUT + 4)

    def model_parts(self, ram, index: int) -> tuple[int, int]:
        self._log(ram, "part_a", (index,))
        self._log(ram, "part_b", (index,))
        return ram.u32(PARTS_RET[0]), ram.u32(PARTS_RET[1])


def random_state(cpu, rng) -> None:
    vm.common(cpu, rng)
    w32(cpu, CALLS, 0)
    for a in (REEL_RET, PARTS_RET[0], PARTS_RET[1], LOAD_OUT, LOAD_OUT + 4):
        w32(cpu, a, rng.choice([0, 1, rng.getrandbits(32)]))
    w32(cpu, LOOKUP_RET, RECORDS + 0x40 * rng.randrange(4))
    for i in range(8):
        w32(cpu, RECORDS + 0x40 * i + 0x24, rng.getrandbits(32))
    w32(cpu, og.SCENE_OTS, SCENE_OT_AREA)
    w32(cpu, SCENE_OT_AREA + 4, SCENE_OT)
    w32(cpu, SCENE_OT + 0xFFC, rng.getrandbits(32))
    w32(cpu, ds.TEXT_OFF, rng.choice([0, 0, 0, 1]))
    w16(cpu, og.STAGE, rng.randrange(16))
    for f in og.FIGHTERS:
        w32(cpu, f + 0x54, RECORDS + 0x40 * rng.randrange(4, 8))
        for off, size in ((0x14, 2), (0x16, 2), (0x18, 2), (0x1C, 2), (0x2C, 2), (0xE, 2), (0x50, 2), (0x58, 2)):
            w16(cpu, f + off, rng.choice([0xD, rng.randrange(-400, 400)]))
        cpu.write(f + 0x1E, bytes([rng.randrange(4)]))
    cpu.write(0x800AFF50 + 0x1D, bytes([rng.getrandbits(8)]))
    cpu.write(0x800AFF50 + 0xB1, bytes([rng.choice([0, 0, 1, 2])]))


def random_script(cpu, rng) -> int:
    if rng.random() < 0.5:
        base = rng.choice(og.SCRIPTS)
        n = 0
        while struct.unpack("<h", cpu.read(base + 10 * n + 2, 2))[0] != -1:
            n += 1
        return base + 10 * rng.randrange(n + 1)
    recs, frame = bytearray(), rng.randrange(0, 6)
    for _ in range(rng.randrange(1, 8)):
        kind = rng.choice([0, 1, 2, 2, 3, 3, 4, 5, 6])
        recs += struct.pack("<5h", frame, kind, rng.randrange(0, 0x900), rng.randrange(0, 50), rng.randrange(0, 300))
        frame += rng.choice([0, 0, 1, 3])
    recs += struct.pack("<5h", frame, -1, 0, 0, 0)
    cpu.write(SCRIPT, bytes(recs))
    return SCRIPT


def case_setup(cpu, rng, chk) -> None:
    random_state(cpu, rng)
    vd.run_gpu(chk, "SceneSetup", cpu, lambda c: c.call(0x800B4168) and None, og.scene_setup)


def case_frame(cpu, rng, chk) -> None:
    random_state(cpu, rng)
    ev = random_script(cpu, rng)
    w32(cpu, og.EVENTS, ev)
    frame = struct.unpack("<h", cpu.read(ev, 2))[0]
    w32(cpu, og.STATE, rng.choice([0, 1, 1, 1, 1, 2, 2, 3, -1]))
    w32(cpu, og.FRAME, rng.choice([frame, frame, frame - 1, frame + 2, 0, 4, 5, rng.randrange(-2, 300)]))
    w32(cpu, og.PAUSE, rng.choice([0, 0, 0, 1, 2]))
    w32(cpu, og.FADE_ON, rng.choice([0, 1]))
    w32(cpu, og.FADE_LEVEL, rng.choice([0, 0xCF, 0xD0, 0x100, 0x101, rng.randrange(-8, 0x110)]))
    w32(cpu, og.FADE_SPEED, rng.choice([4, rng.randrange(-4, 20)]))
    w32(cpu, og.CAMERA_READY, rng.choice([0, 1]))
    w32(cpu, og.BLACK, rng.choice([0, 0, 1]))
    for i in range(2):
        m = og.MOVES + 10 * i
        end = rng.randrange(0, 300)
        cpu.write(m, struct.pack("<5h", rng.choice([0, 1, 1, 2]), 0x16, rng.randrange(0, 0x900), end,
                                 rng.choice([end, end - 1, end + 1, rng.randrange(0, 300)])))
    for i in range(2):
        p = og.CLEAR_TILES + 16 * i
        cpu.write(p, struct.pack("<I4B4h", rng.getrandbits(32), 0, 0, 0, 0x60, 0, 0, 0x170, 0x1E0))
        cpu.write(p + 3, bytes([3]))
    vd.run_gpu(chk, "SceneFrame", cpu, lambda c: c.call(0x800B4528) & M32, og.scene_frame)


NAMES = ["SceneSetup", "SceneFrame"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = vm.menu_cpu("arcade")
    install_stubs(cpu)
    og.HOOKS = LogHooks()
    for _ in range(args.cases):
        case_setup(cpu, rng, chk)
        case_frame(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
