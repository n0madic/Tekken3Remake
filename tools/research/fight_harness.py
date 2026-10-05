#!/usr/bin/env python3
"""Run a whole VS fight (Japan Rev.1) in the CPU harness and record it frame by frame.

The game's own code runs in the Unicorn harness: the parts of `BootInit` that set up the
fight buffers, `FightAllocBuffers`, the fighter and stage loading (`FUN_8002A660`), the round
start (`FUN_8002AB68`) and then `FightMain` in its fight sub-state every frame, with pad input
injected at the pad driver (`FUN_80029E64`) and mapped by the game's key configuration
(`FUN_8002A014`). The disc loader is replaced by copies of the BNS files from
`work/jp_rev1/bns`; the PsyQ libraries that drive hardware (GPU, CD, SPU, pads, memory card,
events) and the game's drawing routines are stubbed. Sound, voice, vibration, effect and
camera-shake requests are logged per frame.

Randomness: `rand()` is seeded by `srand(seed)` after the set-up. The camera generator
(`0x800A95F4`, `(x + 1)·0x10DCD`) and the generator `0x8009F650` (`5x + 1`, FUN_8004D13C) are
stepped by the game's main loop while it waits for the vertical blank, a number of times that
depends on the console's timing; the harness (and the remake) seed both with the scenario's seed
and step each once per frame.

Used by `export_traces.py --fight`.
"""

from __future__ import annotations

import collections
import dataclasses
import logging
import struct
from dataclasses import dataclass
from pathlib import Path

import menu_sim
import psxcpu

log = logging.getLogger("fight_harness")

ROOT = Path(__file__).resolve().parents[2]
BNS_DIR = ROOT / "work" / "jp_rev1" / "bns"
FUNCTIONS = ROOT / "work" / "decomp" / "SLPS_013.00.functions.tsv"

FIGHTERS = (0x800A96F0, 0x800AAF7C)
FIGHTER_SIZE = 0x188C
LOGICAL_TO_ID = 0x80098954          # u16[303]
PSYQ = (0x8007A094, 0x80095200)

# Game globals
GAME_STATE, SUB_STATE = 0x800AE6CC, 0x800AE6EC
GAME_MODE = 0x800AFF50
FRAME_COUNTER = 0x800AFF14
VBLANK = 0x800AE6E0                 # video frames at the main-loop frame's start (FUN_80029B78)
STAGE = 0x800AE14C
MUSIC = 0x800AE1D0
PLAYERS_ACTIVE = (0x800AE6C0, 0x800AE6C2)
OPTION_ROUNDS = 0x800982E7          # FIGHT COUNT: rounds to win − 1
OPTION_ROUND_TIME = 0x800982E8      # ROUND TIME: 20, 30, 40, 50, 60 seconds, 5 infinite
OPTION_GUARD_DAMAGE = 0x800982E9
CAMERA_RNG = 0x800A95F4
FRAME_RNG = 0x8009F650              # x·5 + 1, stepped by the same wait loop (FUN_8004D13C)
PAD_RECORDS = (0x800A95F8, 0x800A9622)
ROUND_STATE, ROUND_COUNTER = 0x80097350, 0x80097354
TIMER = 0x800AE094
CAMERA_PHASE = 0x80095890

DISPLAY_BUFFER = 0x800AE3C4         # GsGetActiveBuff of the frame
ORDERING_TABLE = 0x800A911C         # the current GsOT
ORDERING_TABLES = 0x800A8A58        # two GsOT headers, 20 bytes each
OT_ENTRIES = 0x800A6A50
WORK_BASE = 0x800A9660              # GsSetWorkBase
PACKET_AREAS = 0x800AE508           # per display buffer, 7 words (FightAllocBuffers)

KEY_TABLES = (0x80098290, 0x800982B0)  # per player: mapped word of each physical pad bit
# Default key configuration (title.ovl FUN_800DE7B4 with the save block's default actions
# 12, 12, 12, 12, 1, 3, 2, 0): the shoulder buttons unused, face buttons, Select, Start and the
# directions unchanged.
DEFAULT_KEY_TABLE = (0, 0, 0, 0, 0x10, 0x20, 0x40, 0x80, 0x100, 0, 0, 0x800, 0x1000, 0x2000, 0x4000, 0x8000)
MATCH_OVER = 0x800AFF71
AI_DIFFICULTY = 0x800AE6D0          # u16: the AI group (DIFFICULTY LEVEL)
AI_LEVEL = 0x800AE6D9               # u8: the CPU level
ATTRACT = 0x800AE39C                # u16: outside a started mode (the demonstration fight)
COSTUME_SLOTS = 0x80095CE8          # s8 per costume key (character · 4 + costume), −1: none

# Game functions
HUD_TABLES = 0x8004C96C
VS_END_HOOK = 0x800B15CC            # arcade.ovl; the harness stops when FightMain calls it
FIGHT_ALLOC = 0x80055B6C
LOAD_FIGHTERS = 0x8002A660
ROUND_START = 0x8002AB68
FIGHT_MAIN = 0x80050710
PAD_MAP = 0x8002A014
PAD_READ = 0x80029E64
SRAND = None                        # resolved from the function list

# Boot pieces run before the fight (from BootInit 0x800B0A10), in its order.
BOOT_CALLS = (
    (0x80055B6C, (0,)),             # FightAllocBuffers(0)
    (0x800B0D08, (0,)),             # display mode 0 (384 × 480): the GTE offset (192, 240), H 500
    (0x8007508C, ()),               # SoundInit (libsnd stubbed): VAB slot table
    (0x8004B8B4, (0,)),
    (0x800291B0, ()),
    (0x80029700, ()),
    (0x8006C850, ()),
    (0x80029B78, (0,)),             # frame timing
    (0x80069ABC, (0xFFFFFFFF,)),    # motion bank cache
    (0x8008165C, (500,)),
    (0x800699F0, ()),
    (0x80067540, ()),
    (0x80067ECC, ()),
)

# BNS loader
BNS_RESET, BNS_QUEUE, BNS_START, BNS_LOADING = 0x8006C190, 0x8006C208, 0x8006C36C, 0x8006C524

# Library functions that stay real: libc, libgte and the libsnd pitch helpers.
KEEP_PREFIX = (
    "memset", "memcpy", "bzero", "rand", "srand", "str", "toupper", "tolower", "memchr", "InitGeom",
    "SquareRoot", "MulMatrix", "Apply", "ReadLight", "SetMulRot", "ScaleMatrix", "SetRotMatrix",
    "SetLightMatrix", "SetColorMatrix", "SetTransMatrix", "SetBackColor", "SetFarColor", "RotTrans",
    "ColorMatCol", "TransposeMatrix", "ratan2", "RATAN", "gte_", "Gssub", "GS_115", "GS_123", "MEMSET",
    "STRCMP", "STRNCMP", "MEMCHR", "BZERO", "__main",
)

# Unnamed library functions that stay real although the module around them is stubbed: they set
# the GTE projection (screen positions decide which side a fighter stands on).
KEEP_ADDRESSES = {
    0x8008165C,                     # GsSetProjection → SetGeomScreen
    0x80082B4C,                     # SetGeomOffset
    0x80082B6C,                     # SetGeomScreen
}

# Game routines that only draw, upload or talk to hardware.
NOOP = {
    0x8007A27C, 0x8007A28C,         # EnterCriticalSection / ExitCriticalSection wrappers (syscall)
    0x8006E664,                     # stage TIM upload
    0x80035998,                     # FighterUploadTextures
    0x80076484,                     # FighterUploadFlipbook
    0x80036F00,                     # DrawSkinnedPart
    0x800490F0, 0x80049AE0,         # FloorDraw, the alternative floor
    0x8004860C,                     # the clear tile
}
# StageBackgroundDraw (0x8006D2FC) is replaced by its only part that keeps state: the panorama's
# turn, FUN_8006E4A0 added to 0x800A9650 (the remake's BackdropTurn).
PANORAMA_TURN_ONLY = (0x8006D2FC, [
    0x27BDFFF8,                     # addiu sp, sp, -8
    0xAFBF0004,                     # sw ra, 4(sp)
    0x0C01B928,                     # jal FUN_8006E4A0
    0x00000000,
    0x3C08800B,                     # lui t0, 0x800B
    0x8D099650,                     # lw t1, -0x69B0(t0)       0x800A9650
    0x01224821,                     # addu t1, t1, v0
    0x31290FFF,                     # andi t1, t1, 0xFFF
    0xAD099650,                     # sw t1, -0x69B0(t0)
    0x8FBF0004,                     # lw ra, 4(sp)
    0x03E00008,                     # jr ra
    0x27BD0008,                     # addiu sp, sp, 8
])
# FUN_8006DAB4 (the background: the stage panorama and clear tile above, or the Tekken Force and
# Tekken Ball tile panoramas) runs: Tekken Force's panorama stores the camera's view-space x
# (0x800B70F0), which its walls read.

# Presentation bugs the remake does not reproduce are fixed in the traced game code
# (remake-plan.md#original-bugs). Trampolines live in the dead body of the stubbed
# DrawSkinnedPart.
TRAMPOLINES = 0x80036F00 + 8
ISQRT = 0x8002A578
NORMAL_CLIP = 0x80082BAC
SP, A0, A1, A2, V0, V1, T1, T5, T6, T7, S0, S3, S4 = 29, 4, 5, 6, 2, 3, 9, 13, 14, 15, 16, 19, 20
A3, T4, RA, ZERO = 7, 12, 31, 0
GAMEPLAY_TRAMPOLINES = TRAMPOLINES + 0x100
SEGMENT_HITS_CYLINDER = 0x800479A4


def _r(rs: int, rt: int, rd: int, funct: int) -> int:
    return rs << 21 | rt << 16 | rd << 11 | funct


def _lw(rt: int, offset: int, base: int) -> int:
    return 0x8C000000 | base << 21 | rt << 16 | offset & 0xFFFF


def _jal(target: int) -> int:
    return 0x0C000000 | (target >> 2) & 0x3FFFFFF


def _j(target: int) -> int:
    return 0x08000000 | (target >> 2) & 0x3FFFFFF


def _shift(rt: int, rd: int, amount: int, funct: int) -> int:
    return rt << 16 | rd << 11 | amount << 6 | funct


def _branch(op: int, rs: int, rt: int, site: int, target: int) -> int:
    return op << 26 | rs << 21 | rt << 16 | ((target - site - 4) >> 2) & 0xFFFF


def _gameplay_fixes() -> list[tuple[int, tuple[int, ...]]]:
    """The Gameplay fixes (remake-plan.md#original-bugs) as code patches, for the fixed trace
    set; #9 is a Python replacement of SegmentHitsCylinder (FightHarness.__init__)."""
    patches = []
    tramp = GAMEPLAY_TRAMPOLINES
    # Bug #7: LaunchTrajectory divides a negative sum as unsigned; the fix takes a flight time
    # of 0 (the game's own minimum then makes it 1). mfhi/srl at 0x8002F404 go to a trampoline.
    patches.append((0x8002F404, (_jal(tramp), 0)))
    code = (_r(0, 0, A3, 0x10),                     # mfhi a3
            _shift(A3, A2, 2, 2),                   # srl a2, a3, 2
            _branch(1, V0, 1, tramp + 8, tramp + 20),   # bgez v0, done
            0,
            _r(ZERO, ZERO, A2, 0x21),               # addu a2, zero, zero
            _r(RA, 0, 0, 8),                        # done: jr ra
            0)
    patches.append((tramp, code))
    tramp += 4 * len(code)
    # Bug #8: IkSolveLimb's arm bend inv · 0x9204 (shifts and adds) wraps to 32 bits; the fix
    # shifts the 64-bit product right by 11.
    patches.append((0x8003C1CC, (0x34029204,         # ori v0, zero, 0x9204
                                 _r(T4, V0, 0, 0x18),  # mult t4, v0
                                 _r(0, 0, V0, 0x12),   # mflo v0
                                 _r(0, 0, A0, 0x10),   # mfhi a0
                                 _shift(V0, V0, 11, 2),  # srl v0, v0, 11
                                 _shift(A0, A0, 21, 0),  # sll a0, a0, 21
                                 _r(V0, A0, V0, 0x25),   # or v0, v0, a0
                                 0)))
    # Bug #52: LatchButtonTaps' frozen path stores whatever $a2 holds; the fix loads the newest
    # history entry first.
    patches.append((0x80040DA8, (_branch(5, V0, ZERO, 0x80040DA8, tramp),)))   # bnez v0, tramp
    code = (_lw(A0, 0x40C, A1),                     # lw a0, 0x40c(a1)
            0,
            _r(A1, A0, A0, 0x21),                   # addu a0, a1, a0
            0x90860000 | 0x41C,                     # lbu a2, 0x41c(a0)
            _j(0x80040E3C),
            0)
    patches.append((tramp, code))
    return patches


# Where a fixed path is taken, for counting how often a fix changes the outcome.
FIX_SITES = {"7": GAMEPLAY_TRAMPOLINES + 16, "8": 0x8003C1CC, "52": GAMEPLAY_TRAMPOLINES + 28}


def _fix_hooks(h: "FightHarness") -> None:
    """Counts the frames' uses of a Gameplay fix that change a value (FightHarness.fix_hits)."""
    uc = h.cpu.uc
    from unicorn.mips_const import UC_MIPS_REG_A1, UC_MIPS_REG_A2, UC_MIPS_REG_T4

    def launch(uc, address, size, _user) -> None:
        h.fix_hits["7"] += 1

    def elbow(uc, address, size, _user) -> None:
        inv = uc.reg_read(UC_MIPS_REG_T4)
        inv = inv - (1 << 32) if inv & 0x80000000 else inv
        wrapped = (inv * 0x9204) & 0xFFFFFFFF
        wrapped = wrapped - (1 << 32) if wrapped & 0x80000000 else wrapped
        if wrapped >> 11 != (inv * 0x9204) >> 11:
            h.fix_hits["8"] += 1

    def latch(uc, address, size, _user) -> None:
        f = uc.reg_read(UC_MIPS_REG_A1)
        index = struct.unpack("<i", h.cpu.read(f + 0x40C, 4))[0]
        newest = h.cpu.read(f + index + 0x41C, 1)[0]
        if newest != uc.reg_read(UC_MIPS_REG_A2) & 0xFFFF:
            h.fix_hits["52"] += 1

    for name, hook in (("7", launch), ("8", elbow), ("52", latch)):
        uc.hook_add(psxcpu.UC_HOOK_CODE, hook, begin=FIX_SITES[name], end=FIX_SITES[name])


def _segment_hits_cylinder_exact(h: "FightHarness"):
    """Bug #9 fixed: SegmentHitsCylinder with exact products (fight_math port)."""
    import fight_math

    def stub(cpu: psxcpu.PsxCpu, seg: int, cyl: int, *_: int) -> int:
        s = list(struct.unpack("<6i", cpu.read(seg, 24)))
        cx, cy, cz, r, r2 = struct.unpack("<3iii", cpu.read(cyl, 20))
        c = [cx, cy, cz, r & 0xFFFF, r2]
        hit = fight_math.segment_hits_cylinder(s, c, exact=True)
        if hit != fight_math.segment_hits_cylinder(s, c):
            h.fix_hits["9"] += 1
        return int(hit)
    return stub


def _fixes() -> list[tuple[int, tuple[int, ...]]]:
    """(address, words) patches, trampolines included."""
    patches = []
    tramp = TRAMPOLINES
    # Bug #1: CameraLookPoint (0x80063FE8) measures the distance to target 1 with target 0's z.
    # The sum for target 1 jumps to a trampoline that adds (T1.z − z)² instead of (T0.z − z)²,
    # then tail-calls ISqrt, which returns to 0x80064100.
    patches.append((0x800640F8, (_jal(tramp), _r(A2, T1, S0, 0x21), 0)))
    code = (_lw(T6, 0x38, SP),                  # z (the caller's argument slot)
            _lw(T7, 8, T5),                     # T1.z (0x800AE188)
            0,
            _r(T7, T6, T7, 0x23),               # subu t7, t7, t6
            _r(T7, T7, 0, 0x18),                # mult t7, t7
            _r(0, 0, T7, 0x12),                 # mflo t7
            _r(S0, T7, S0, 0x21),               # addu s0, s0, t7
            _j(ISQRT), 0)
    patches.append((tramp, code))
    tramp += 4 * len(code)
    # Bug #53: CameraDirector breaks a tie of the targets' screen x with 0x800AE19C (a third
    # target) against the previous frame's target 0; compare the previous frame's targets.
    for site, base in ((0x80063758, A1), (0x80063830, V1)):
        patches.append((site, (_lw(V0, 0x3C, base), _lw(V1, 0x4C, base))))
    # Bug #54: FUN_800670E4 passes NormalClip the stack addresses of its three points instead
    # of their packed values; the trampoline loads the values.
    patches.append((0x800672A0, (_jal(tramp),)))
    code = (_lw(A0, 0, A0), _lw(A1, 0, A1), _lw(A2, 0, A2), _j(NORMAL_CLIP), 0)
    patches.append((tramp, code))
    tramp += 4 * len(code)
    # Bug #59: CpuOrPadInput gives a CPU fighter without health its uninitialised stack words
    # (sp+0x10, sp+0x14) as pad input; the branch past AiUpdate clears them first.
    patches.append((0x8002C708, (_branch(4, V0, ZERO, 0x8002C708, tramp),)))   # beqz v0, tramp
    code = (0xAFA00010, 0xAFA00014, _j(0x8002C720), 0)     # sw zero, 0x10(sp); sw zero, 0x14(sp)
    patches.append((tramp, code))
    # Bug #55: after switching to a preset the stream step returns FightFrame's $s3 (1); set
    # $s3 to −1 in the delay slot of its CameraReset call, as the switch path returns.
    patches.append((0x80067330, (0x2413FFFF,)))         # addiu s3, zero, -1
    # Bug #58: HitVibration starts the KO pad index at −1, so a KO without a clean hit or throw
    # damage this frame flags a stack word; start it at the hit's attacker (+0x22, $s3).
    patches.append((0x80075D60, (_r(S3, ZERO, S4, 0x21),)))   # addu s4, s3, zero
    return patches


RETURN_ZERO_CODE = struct.pack("<2I", 0x03E00008, 0x00001021)     # jr ra; move v0, zero
RETURN_A1_CODE = struct.pack("<2I", 0x03E00008, 0x00051021)       # jr ra; move v0, a1
RETURN_A2_CODE = struct.pack("<2I", 0x03E00008, 0x00061021)       # jr ra; move v0, a2
# Drawing routines that return their packet pointer (second argument).
RETURN_PACKET = {
    0x80037CF0,                     # ShadowProjectSection
}
# Drawing routines that return their ordering-table link (third argument).
RETURN_LINK = {
    0x80037D7C,                     # ShadowBuildPrims
}

# Engine calls replaced by a logging stub: address -> (name, argument count).
LOGGED_STUBS: dict[int, tuple[str, int]] = {
    0x8006B0FC: ("music", 2),       # MusicPlay(track, prepare): CD streaming
    0x8006BF80: ("music_volume", 2),
}
# Engine calls that run and are logged at their entry: address -> (name, argument count).
LOGGED_CALLS: dict[int, tuple[str, int]] = {
    0x800756A4: ("sound", 3),       # SoundPlayFighter(player, code, attenuation)
    0x8007588C: ("sound_stop", 2),  # SoundStopFighter
    0x800758E8: ("system_sound", 1),
    0x80029114: ("vibrate", 2),     # PadVibrate(player, pattern)
    0x80076E58: ("effect", 3),
    0x80076EB8: ("spark", 3),
    0x8004AF1C: ("dust", 1),
    0x8004AF94: ("shake", 1),       # CameraShakeStart(script)
}


class CpuRam:
    """The harness's guest memory with the interface of `fight_sim.Ram`, so that the verified
    screen ports (menu_sim.mode_start) can set up the game's state directly."""

    def __init__(self, cpu: psxcpu.PsxCpu) -> None:
        self.cpu = cpu

    def get(self, addr: int, fmt: str) -> int:
        return struct.unpack("<" + fmt, self.cpu.read(addr, struct.calcsize(fmt)))[0]

    def put(self, addr: int, fmt: str, value: int) -> None:
        size = struct.calcsize(fmt)
        value &= (1 << (8 * size)) - 1
        if fmt.islower() and value >= 1 << (8 * size - 1):
            value -= 1 << (8 * size)
        self.cpu.write(addr, struct.pack("<" + fmt, value))

    def u8(self, a: int) -> int: return self.get(a, "B")
    def s8(self, a: int) -> int: return self.get(a, "b")
    def u16(self, a: int) -> int: return self.get(a, "H")
    def s16(self, a: int) -> int: return self.get(a, "h")
    def u32(self, a: int) -> int: return self.get(a, "I")
    def s32(self, a: int) -> int: return self.get(a, "i")


def _function_names() -> dict[int, str]:
    names = {}
    for line in FUNCTIONS.read_text().splitlines()[1:]:
        addr, name = line.split("\t")[:2]
        names[int(addr, 16)] = name
    return names


class FightHarness:
    def __init__(self, gameplay_fixes: bool = False) -> None:
        self.names = _function_names()
        self.cpu = psxcpu.load_release()
        self.calls: list[tuple] = []
        self._bns = {int(p.name[:3]): p for p in BNS_DIR.iterdir() if p.name[:3].isdigit()}
        cpu = self.cpu
        by_name = {n: a for a, n in self.names.items()}
        self.srand = by_name["srand"]
        # Library functions are stubbed unless kept; an unnamed one follows the named function
        # before it (it belongs to the same library module).
        keep = True
        for addr, name in sorted(self.names.items()):
            if not PSYQ[0] <= addr < PSYQ[1]:
                continue
            if not name.startswith("FUN_"):
                keep = name.startswith(KEEP_PREFIX)
            if not keep and addr not in KEEP_ADDRESSES:
                self._patch_return(addr, RETURN_ZERO_CODE)
        for addr in NOOP:
            self._patch_return(addr, RETURN_ZERO_CODE)
        for addr in RETURN_PACKET:
            self._patch_return(addr, RETURN_A1_CODE)
        for addr in RETURN_LINK:
            self._patch_return(addr, RETURN_A2_CODE)
        for addr, words in [PANORAMA_TURN_ONLY] + _fixes() + (_gameplay_fixes() if gameplay_fixes else []):
            for k in range(len(words)):
                cpu.drop_cop2(addr + 4 * k)
            cpu.write(addr, struct.pack(f"<{len(words)}I", *words))
        self.fix_hits: collections.Counter = collections.Counter()
        if gameplay_fixes:
            cpu.stub(SEGMENT_HITS_CYLINDER, _segment_hits_cylinder_exact(self))
            _fix_hooks(self)
        cpu.stub(BNS_RESET, lambda c, *a: 0)
        cpu.stub(BNS_START, lambda c, *a: 0)
        cpu.stub(BNS_LOADING, lambda c, *a: 0)
        cpu.stub(BNS_QUEUE, self._bns_load)
        # The pad driver is replaced: step() writes the pad records before the key mapping runs.
        # (Guest memory is written from Python only between calls: writes from inside a hook
        # have crashed Unicorn.)
        cpu.stub(PAD_READ, lambda c, *a: 0)
        for addr, (name, count) in LOGGED_STUBS.items():
            cpu.stub(addr, self._logging_stub(name, count))
        for addr, (name, count) in LOGGED_CALLS.items():
            cpu.uc.hook_add(psxcpu.UC_HOOK_CODE, self._logging_hook(name, count), begin=addr, end=addr)

    # ---- stubs ---------------------------------------------------------
    def _patch_return(self, addr: int, code: bytes) -> None:
        """Replace a function by an immediate return, patched into RAM before anything runs
        (Python stubs on hundreds of addresses made Unicorn crash now and then)."""
        for site in (addr, addr + 4):
            self.cpu.drop_cop2(site)
        self.cpu.write(addr, code)

    def _bns_load(self, cpu: psxcpu.PsxCpu, logical: int, dest: int, *_: int) -> int:
        bns = struct.unpack("<H", cpu.read(LOGICAL_TO_ID + 2 * logical, 2))[0]
        # Empty records (the Tekken Force enemies' voice banks) have no file.
        data = self._bns[bns].read_bytes() if bns in self._bns else b""
        if data:
            cpu.write(dest, data)
        self.calls.append(("load", bns))
        return 0

    def _logging_stub(self, name: str, count: int):
        def stub(cpu: psxcpu.PsxCpu, *args: int) -> int:
            self.calls.append((name, *[psxcpu.s32(a) for a in args[:count]]))
            return 0
        return stub

    def _logging_hook(self, name: str, count: int):
        regs = (psxcpu.UC_MIPS_REG_A0, psxcpu.UC_MIPS_REG_A1, psxcpu.UC_MIPS_REG_A2, psxcpu.UC_MIPS_REG_A3)

        def hook(uc, address: int, size: int, _user) -> None:
            self.calls.append((name, *[psxcpu.s32(uc.reg_read(r)) for r in regs[:count]]))
        return hook


    # ---- set-up ----------------------------------------------------------
    def w8(self, a: int, v: int) -> None: self.cpu.write(a, struct.pack("<B", v & 0xFF))
    def w16(self, a: int, v: int) -> None: self.cpu.write(a, struct.pack("<H", v & 0xFFFF))
    def w32(self, a: int, v: int) -> None: self.cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))
    def s16(self, a: int) -> int: return struct.unpack("<h", self.cpu.read(a, 2))[0]
    def s32(self, a: int) -> int: return struct.unpack("<i", self.cpu.read(a, 4))[0]
    def u32(self, a: int) -> int: return struct.unpack("<I", self.cpu.read(a, 4))[0]

    def setup(self, chars: tuple[int, int], costumes: tuple[int, int], stage: int, seed: int,
              round_time: int = 2, rounds: int = 1, chip: bool = False,
              key_tables: tuple[tuple[int, ...], tuple[int, ...]] | None = None,
              cpu: tuple[int, int] = (0, 0), difficulty: int = 1, level: int = 0, attract: bool = False) -> None:
        emu = self.cpu
        for table, words in zip(KEY_TABLES, key_tables or (DEFAULT_KEY_TABLE, DEFAULT_KEY_TABLE)):
            emu.write(table, struct.pack("<16H", *words))
        for addr, args in BOOT_CALLS:
            emu.call(addr, *args)
        # The two ordering tables of BootInit.
        for i in range(2):
            self.w32(ORDERING_TABLES + 20 * i, 10)
            self.w32(ORDERING_TABLES + 20 * i + 4, OT_ENTRIES + 0x1000 * i)
        self._frame_buffers()
        # The fighters' fixed identity, set by BootInit.
        for i, f in enumerate(FIGHTERS):
            self.w16(f + 0x12, i)
            self.w8(f + 0x1E, i)
            self.w8(f + 0x20, 1 - i)
        # The options, then the main menu's VS start (title.ovl FUN_800DAF2C, ported bit-exact
        # as menu_sim.mode_start): feature bytes, handicaps (3: 140 health), players.
        ram = CpuRam(emu)
        ram.put(OPTION_ROUNDS, "B", rounds)
        ram.put(OPTION_ROUND_TIME, "B", round_time)
        ram.put(OPTION_GUARD_DAMAGE, "B", int(chip))
        menu_sim.mode_start(ram, 1, 1)
        # FightMain sub-state 2: the human count and mask, the match counters.
        humans = [i for i in range(2) if not cpu[i]]
        mask = sum(1 << i for i in humans)
        self.w8(0x800AFF6C, len(humans))
        self.w8(0x800AFF6D, mask)
        self.w16(0x800AE3D8, mask)
        # The AI group and CPU level (mode_start copies DIFFICULTY LEVEL, the modes set the level),
        # and the attract flag of the demonstration fight.
        self.w16(AI_DIFFICULTY, difficulty)
        self.w8(AI_LEVEL, level)
        self.w16(ATTRACT, int(attract))
        self.w8(0x800AFF6E, 0)
        self.w8(0x800AFF6F, 0)
        for a in (0x800AFF71, 0x800AFF72, 0x800AFF73):
            self.w8(a, 0)
        self.w32(0x800AFF7C, self.s32(0x800AFF80))
        self.w16(STAGE, stage)
        emu.call(FIGHT_ALLOC, 1)
        for char, costume in zip(chars, costumes):
            if self.cpu.read(COSTUME_SLOTS + 4 * char + costume, 1)[0] >= 0x80:
                raise ValueError(f"character {char} has no costume {costume}")
        self.cpu.call(LOAD_FIGHTERS, chars[0], cpu[0], costumes[0], chars[1], cpu[1], costumes[1])
        emu.call(self.srand, seed)
        self.w32(CAMERA_RNG, seed)
        self.w32(FRAME_RNG, seed)
        self.w32(GAME_STATE, 8)
        self.w32(SUB_STATE, 7)

    # ---- frames ----------------------------------------------------------
    def _frame_buffers(self) -> None:
        """The main loop's per-frame buffer set-up: the display buffer (GsGetActiveBuff, taken
        as the frame counter's parity as the remake does: the hardware's phase depends on the
        swaps since boot), its ordering table, packet work base (GsSetWorkBase) and the HUD
        ordering tables (FUN_8004C96C)."""
        buffer = self.s32(FRAME_COUNTER) & 1
        self.w32(DISPLAY_BUFFER, buffer)
        self.w32(ORDERING_TABLE, ORDERING_TABLES + 20 * buffer)
        self.w32(WORK_BASE, self.s32(PACKET_AREAS + 28 * buffer))
        self.cpu.call(HUD_TABLES, buffer)

    def step(self, pads: tuple[int, int]) -> int:
        """One frame of the main loop in the fight state; returns FightMain's sub-state after it."""
        cpu = self.cpu
        self.calls = []
        self.w32(FRAME_COUNTER, self.s32(FRAME_COUNTER) + 1)
        # One video frame per main-loop frame (the fight runs at 60 fps), counted like the frame
        # counter; the remake uses the same convention.
        self.w32(VBLANK, self.s32(FRAME_COUNTER))
        self.w32(CAMERA_RNG, (self.u32(CAMERA_RNG) + 1) * 0x10DCD)
        self.w32(FRAME_RNG, self.u32(FRAME_RNG) * 5 + 1)
        for record, buttons in zip(PAD_RECORDS, pads):
            # +0 the buttons (1 = pressed, in the game's layout), +0x28 connected.
            self.w16(record, buttons)
            self.w8(record + 0x28, 1)
        self._frame_buffers()
        cpu.call(PAD_MAP, 0)
        cpu.call(FIGHT_MAIN)
        return self.s32(SUB_STATE)

    def fighter(self, i: int) -> bytes:
        return self.cpu.read(FIGHTERS[i], FIGHTER_SIZE)


# ---- input generation ---------------------------------------------------------------------

UP, RIGHT, DOWN, LEFT = 0x1000, 0x2000, 0x4000, 0x8000
LP, RP, LK, RK = 0x80, 0x10, 0x40, 0x20
START = 0x800
BUTTON_SETS = (LP, RP, LK, RK, LP | RP, LK | RK, LP | LK, RP | RK, LP | RK, LK | RP, LP | RP | LK | RK)
# Numpad directions relative to the fighter (6 = forward); the bot turns them into screen bits.
ATTACK_DIRECTIONS = (5, 5, 5, 6, 3, 2, 1, 4, 9, 8, 7)


class Bot:
    """A random but plausible player: approaches, attacks with single buttons, strings, motion
    inputs and throws, guards, steps, jumps and dashes, and mashes when knocked down. It reads
    the game state from the harness (distance, side, the opponent's attack) to choose, so a trace
    records play with hits, guards, throws and juggles. Deterministic for a seed."""

    def __init__(self, harness: FightHarness, index: int, seed: int, style: str = "random") -> None:
        import random
        self.h = harness
        self.index = index
        self.rng = random.Random(seed)
        self.style = style
        self.queue: list[tuple[int, int]] = []      # (numpad direction, buttons) per frame

    def _field(self, off: int, fmt: str) -> int:
        return struct.unpack_from("<" + fmt, self.h.cpu.read(FIGHTERS[self.index] + off, 4))[0]

    def _opponent(self, off: int, fmt: str) -> int:
        return struct.unpack_from("<" + fmt, self.h.cpu.read(FIGHTERS[1 - self.index] + off, 4))[0]

    def _pad(self, direction: int, buttons: int) -> int:
        right_side = self._field(0xC6, "B") != 0
        horizontal = {1: -1, 4: -1, 7: -1, 3: 1, 6: 1, 9: 1}.get(direction, 0)   # +1 forward
        vertical = {7: UP, 8: UP, 9: UP, 1: DOWN, 2: DOWN, 3: DOWN}.get(direction, 0)
        pad = vertical | buttons
        if horizontal:
            forward_is_right = not right_side
            pad |= RIGHT if (horizontal > 0) == forward_is_right else LEFT
        return pad

    def _hold(self, direction: int, frames: int, buttons: int = 0) -> None:
        self.queue += [(direction, buttons)] * frames

    def _tap(self, direction: int, buttons: int = 0, gap: int = 1) -> None:
        self.queue += [(direction, buttons)] + [(5, 0)] * gap

    def _plan(self) -> None:
        rng = self.rng
        if self.style == "idle":
            self._hold(5, 30)
            return
        if self.style == "guard":
            self._hold(4, 30)
            return
        if self.style == "spam":
            # One move again and again (the CPU's adaptive difficulty learns repeated moves).
            if self._field(0xF8, "I") > 0x900:
                self._hold(6, 10)
            else:
                self._tap(6, RP, 12)
            return
        dist = self._field(0xF8, "I")
        down = self._field(0x60, "I") & 4
        opp_attacking = self._opponent(0x5E, "h") != 0
        if down:
            # Knocked down: mash, roll or get up with a kick.
            choice = rng.random()
            if choice < 0.4:
                for _ in range(rng.randint(2, 6)):
                    self._tap(5, rng.choice((LP, RP, LK, RK)), rng.randint(1, 3))
            elif choice < 0.6:
                self._tap(rng.choice((8, 2)), 0, rng.randint(2, 8))
            elif choice < 0.8:
                self._tap(5, rng.choice((LK, RK, LK | RK)), rng.randint(5, 15))
            else:
                self._hold(rng.choice((5, 6, 4)), rng.randint(5, 25))
            return
        if opp_attacking and dist < 0x900 and rng.random() < 0.35:
            self._hold(rng.choice((4, 4, 1)), rng.randint(6, 20))
            return
        if dist > 0xB00 and rng.random() < 0.7:
            if rng.random() < 0.3:
                self._tap(6), self._tap(6, 0, 0), self._hold(6, rng.randint(4, 16))
            else:
                self._hold(6, rng.randint(8, 30))
            return
        choice = rng.random()
        if choice < 0.45:
            # One attack, possibly a short string.
            for _ in range(rng.choice((1, 1, 1, 2, 3, 4))):
                self._tap(rng.choice(ATTACK_DIRECTIONS), rng.choice(BUTTON_SETS[:4] if rng.random() < 0.7 else BUTTON_SETS),
                          rng.randint(2, 14))
        elif choice < 0.55:
            # Motion inputs: quarter circles, dragon punch, back-forward.
            motion = rng.choice(((2, 3, 6), (2, 1, 4), (6, 2, 3), (4, 6), (6, 6), (2, 2), (4, 1, 2, 3, 6)))
            for d in motion:
                self._tap(d, 0, 0)
            self._tap(motion[-1], rng.choice(BUTTON_SETS[:4]), rng.randint(3, 12))
        elif choice < 0.62:
            self._tap(rng.choice((5, 6)), rng.choice((LP | LK, RP | RK)), rng.randint(10, 30))    # throws
        elif choice < 0.70:
            self._tap(rng.choice((8, 2)), 0, rng.randint(3, 12))                                  # side step
        elif choice < 0.76:
            self._hold(rng.choice((7, 8, 9)), rng.randint(3, 20), rng.choice((0, 0, LK, RK, LP)))  # jumps
        elif choice < 0.82:
            self._tap(4), self._tap(4, 0, 0), self._hold(4, rng.randint(4, 12))                   # back dash
        elif choice < 0.90:
            self._hold(rng.choice((2, 1, 3)), rng.randint(5, 25), 0)                              # crouch
        else:
            self._hold(rng.choice((5, 6, 4)), rng.randint(3, 20))

    def next(self) -> int:
        if not self.queue:
            self._plan()
        direction, buttons = self.queue.pop(0)
        return self._pad(direction, buttons)


# ---- scenarios and trace writing ------------------------------------------------------------

@dataclass
class Scenario:
    name: str
    chars: tuple[int, int]
    costumes: tuple[int, int]
    stage: int
    seed: int
    styles: tuple[str, str] = ("random", "random")
    round_time: int = 2
    rounds: int = 1
    chip: bool = False
    key_tables: tuple[tuple[int, ...], tuple[int, ...]] | None = None
    max_frames: int = 20000
    gameplay_fixes: bool = False
    cpu: tuple[int, int] = (0, 0)     # 1: the player is a CPU fighter (its pad is 0)
    difficulty: int = 1
    level: int = 0
    attract: bool = False


def record(scenario: Scenario):
    """Runs a scenario to the end of its match and yields (pads, sub-state before, calls) per
    frame, with the harness holding the state after the frame."""
    h = FightHarness(scenario.gameplay_fixes)
    over = []
    h.cpu.stub(VS_END_HOOK, lambda c, *a: over.append(1) or 0)
    h.setup(scenario.chars, scenario.costumes, scenario.stage, scenario.seed, scenario.round_time,
            scenario.rounds, scenario.chip, scenario.key_tables, scenario.cpu, scenario.difficulty,
            scenario.level, scenario.attract)
    bots = [Bot(h, i, scenario.seed * 2 + i, scenario.styles[i]) for i in range(2)]
    for _ in range(scenario.max_frames):
        sub = h.s32(SUB_STATE)
        pads = tuple(0 if scenario.cpu[i] else bots[i].next() for i in range(2)) if sub == 8 else (0, 0)
        h.step(pads)
        yield h, pads, sub, list(h.calls)
        if over:
            return
    raise RuntimeError(f"{scenario.name}: the match did not end within {scenario.max_frames} frames")


TRACE_MAGIC = b"T3FT"
TRACE_VERSION = 2
CALL_KINDS = ("load", "music", "music_volume", "sound", "sound_stop", "system_sound", "vibrate", "effect",
              "spark", "dust", "shake")
# Global RAM ranges recorded per frame, (name, address, size).
RANGES = (
    ("fight_flags", 0x80095840, 0xC0),
    ("input_state", 0x80095A90, 0x110),
    ("round", 0x80097340, 0x170),
    ("arena", 0x80097E60, 0x70),
    ("hud_bars", 0x800980F0, 0x40),
    ("camera_lift", 0x80098750, 0x10),
    ("intro_counter", 0x80098920, 0x10),
    ("replay", 0x8009C040, 0x40),
    ("look_at", 0x8009E8F8, 0x98),
    ("physics", 0x8009E990, 0x280),
    ("hands", 0x8009C080, 0x20),
    ("camera_sources", 0x800A0640, 0x240),
    ("anchors", 0x800A0900, 0x60),
    ("rand", 0x800A3E80, 4),
    ("frame_rng", 0x8009F650, 4),
    ("camera", 0x800A8A80, 0x28),
    ("pads_mapped", 0x800A9110, 4),
    ("director", 0x800A9130, 0x80),
    ("blend_hold", 0x800A9230, 8),
    ("camera_rng", 0x800A95F4, 4),
    ("panorama", 0x800A9650, 0x30),       # the backdrop's turn (FUN_8006E4A0): angle, yaws, points
    ("look_point", 0x800AE0D8, 0xC),      # FUN_8006E4A0: the point ahead of the camera
    ("timer", 0x800AE090, 8),
    ("fight_globals", 0x800AE140, 0x70),
    ("round_rules", 0x800AE2C0, 0x10),
    ("results", 0x800AE330, 0x20),
    ("pads", 0x800AE3C0, 0x50),
    ("view", 0x800AE438, 0x20),
    ("mode", 0x800AFF00, 0x80),
)
# Recorded as well when a CPU fights: the AI globals (0x8009F690: the AI slots' move indices, the
# Tekken Ball and Tekken Force words) and the two AI records (ai.md).
AI_RANGES = (
    ("ai_globals", 0x8009F690, 0x30),
    ("ai_records", 0x8009F6C0, 0x660),
)
FIGHTER_BANKS = 0x800AE0E8          # g_fighterDivmot[2], then g_divmotCommon


def write_trace(scenario: Scenario, path: Path) -> int:
    """Records a scenario into a fight trace; returns the frame count.

    File: "T3FT", u32 version, u32 header length, JSON header, u32 body length, u32 zlib length,
    zlib(body). Body, per frame: u16 pad 0, u16 pad 1, s8 FightMain sub-state before the frame,
    u8 call count, per call u8 kind (CALL_KINDS), u8 argument count, s32 arguments; then both
    fighter records (raw, 0x188C bytes each) and the RANGES (raw), all after the frame.
    The header names the scenario, the ranges and the motion banks (bank table and each bank's
    relocated section pointers, one set per stretch of frames with the same banks) so that
    pointers in the records can be turned into rows.
    """
    body = bytearray()
    frames = 0
    header: dict = {}
    for h, pads, sub, calls in record(scenario):
        if not header:
            header = _trace_header(h, scenario)
        banks = _banks(h)
        epochs = header["bank_epochs"]
        if not epochs or epochs[-1]["banks"] != banks:
            # Mokujin loads another character's bank at each round start.
            epochs.append({"frame": frames, "banks": banks})
        body += struct.pack("<HHbB", pads[0], pads[1], sub, len(calls))
        for name, *args in calls:
            body += struct.pack("<BB", CALL_KINDS.index(name), len(args))
            body += struct.pack(f"<{len(args)}i", *args)
        body += h.fighter(0) + h.fighter(1)
        for _, addr, size in _ranges(scenario):
            body += h.cpu.read(addr, size)
        frames += 1
        header["fix_hits"] = dict(h.fix_hits)
    header["frames"] = frames
    write_trace_file(path, TRACE_MAGIC, TRACE_VERSION, header, body)
    return frames


def write_trace_file(path: Path, magic: bytes, version: int, header: dict, body: bytes | bytearray) -> None:
    """Writes a fight or flow trace: magic, u32 version, u32 header length, JSON header,
    u32 body length, u32 zlib length, zlib(body)."""
    import json
    import zlib
    head = json.dumps(header, indent=1).encode()
    packed = zlib.compress(bytes(body), 6)
    path.write_bytes(magic + struct.pack("<II", version, len(head)) + head
                     + struct.pack("<II", len(body), len(packed)) + packed)


def _ranges(scenario: Scenario) -> tuple:
    return RANGES + (AI_RANGES if any(scenario.cpu) else ())


def _banks(h: FightHarness) -> list[dict]:
    """g_fighterDivmot[2] (0x800AE0E8) and g_divmotCommon (0x800AE0F0): each bank's base, type
    and relocated section pointers."""
    banks = []
    for k in range(3):
        base = h.u32(FIGHTER_BANKS + 4 * k)
        banks.append({"base": base, "type": h.cpu.read(base + 1, 1)[0],
                      "sections": [h.u32(base + 4 + 4 * i) for i in range(13)]})
    return banks


def _trace_header(h: FightHarness, scenario: Scenario) -> dict:
    return {
        "version": TRACE_VERSION,
        "scenario": {
            "name": scenario.name, "chars": list(scenario.chars), "costumes": list(scenario.costumes),
            "stage": scenario.stage, "seed": scenario.seed, "styles": list(scenario.styles),
            "round_time": scenario.round_time, "rounds": scenario.rounds, "chip": scenario.chip,
            "key_tables": [list(t) for t in scenario.key_tables] if scenario.key_tables else None,
            "gameplay_fixes": scenario.gameplay_fixes,
            "cpu": list(scenario.cpu), "difficulty": scenario.difficulty, "level": scenario.level,
            "attract": scenario.attract,
        },
        "fighters": [f for f in FIGHTERS],
        "fighter_size": FIGHTER_SIZE,
        "call_kinds": list(CALL_KINDS),
        "ranges": [[name, addr, size] for name, addr, size in _ranges(scenario)],
        "bank_epochs": [],
    }


# The fight scenarios of the remake's trace suites: every character (Tiger, Panda and Anna as
# costumes too) and every fight stage, the round-flow cases and the game options.
SCENARIOS = (
    Scenario("paul_law", (0, 1), (0, 2), 0, seed=1),
    Scenario("lei_king", (2, 3), (1, 1), 1, seed=2),
    Scenario("yoshimitsu_nina", (4, 5), (0, 1), 2, seed=3),
    Scenario("hwoarang_xiaoyu", (6, 7), (1, 2), 3, seed=4),
    Scenario("eddy_jin", (8, 9), (0, 2), 4, seed=5),
    Scenario("julia_kuma", (10, 11), (1, 0), 5, seed=6),
    Scenario("bryan_heihachi", (12, 13), (0, 1), 6, seed=7),
    Scenario("ogre_mokujin", (14, 15), (0, 0), 7, seed=8),
    Scenario("jack_gon", (16, 17), (2, 0), 8, seed=9),
    Scenario("anna_doctorb", (18, 19), (2, 0), 9, seed=10),
    Scenario("trueogre_tiger", (20, 8), (0, 2), 10, seed=11),
    Scenario("panda_anna", (11, 5), (1, 2), 11, seed=12),
    Scenario("xiaoyu_king_chip", (7, 3), (1, 1), 12, seed=13, chip=True),
    Scenario("draw", (0, 0), (0, 1), 13, seed=14, styles=("idle", "idle"), round_time=0, rounds=0),
    Scenario("perfect", (9, 13), (0, 0), 14, seed=15, styles=("random", "idle"), rounds=0),
    Scenario("long_match", (6, 12), (0, 1), 0, seed=16, round_time=4, rounds=2),
)
# The same matches with the Gameplay fixes (remake-plan.md#original-bugs): the bots answer the
# game state, so the pads differ from the unfixed matches after the first changed outcome.
FIXED_SCENARIOS = tuple(dataclasses.replace(s, name="fixes_" + s.name, gameplay_fixes=True) for s in SCENARIOS)
# Matches against CPU fighters (ai.md): every difficulty group, low to high levels, the character
# hooks (against Paul, Yoshimitsu, Ogre and Gon; King and Hwoarang as the CPU), CPU against CPU
# with the demonstration's attract flag, and a player repeating one move (adaptive difficulty).
CPU_SCENARIOS = (
    Scenario("cpu_paul_king", (0, 3), (0, 0), 1, seed=21, cpu=(0, 1), difficulty=1, level=4, rounds=1),
    Scenario("cpu_yoshimitsu_hwoarang", (4, 6), (0, 1), 2, seed=22, cpu=(0, 1), difficulty=2, level=9),
    Scenario("cpu_ogre_jin", (14, 9), (0, 0), 3, seed=23, cpu=(0, 1), difficulty=1, level=7),
    Scenario("cpu_gon_nina", (17, 5), (0, 0), 4, seed=24, cpu=(0, 1), difficulty=0, level=1),
    Scenario("cpu_king_law", (1, 3), (0, 1), 5, seed=25, cpu=(1, 0), difficulty=1, level=2),
    Scenario("cpu_trueogre_xiaoyu", (20, 7), (0, 0), 6, seed=26, cpu=(0, 1), difficulty=2, level=5),
    Scenario("cpu_spam_eddy", (12, 8), (0, 0), 7, seed=27, cpu=(0, 1), difficulty=1, level=6,
             styles=("spam", "random")),
    Scenario("cpu_attract", (8, 2), (0, 1), 4, seed=28, cpu=(1, 1), attract=True, round_time=2),
    Scenario("cpu_vs_cpu", (13, 10), (1, 0), 8, seed=29, cpu=(1, 1), difficulty=2, level=9, rounds=2),
    Scenario("cpu_julia_heihachi", (10, 13), (0, 0), 9, seed=30, cpu=(0, 1), difficulty=0, level=0),
)
ALL_SCENARIOS = SCENARIOS + FIXED_SCENARIOS + CPU_SCENARIOS


def _export_one(args: tuple[Scenario, str]) -> tuple[str, int, float, str]:
    import time
    import traceback
    scenario, out_dir = args
    t = time.time()
    try:
        frames = write_trace(scenario, Path(out_dir) / f"fight_{scenario.name}.bin")
    except Exception:           # reported by the parent: Unicorn's errors do not pickle
        return scenario.name, 0, time.time() - t, traceback.format_exc()
    return scenario.name, frames, time.time() - t, ""


def export(names: list[str] | None, out_dir: Path, jobs: int) -> None:
    """Writes the fight traces of the named scenarios (all by default), `jobs` in parallel."""
    from multiprocessing import Pool
    chosen = [s for s in ALL_SCENARIOS if not names or s.name in names]
    unknown = set(names or ()) - {s.name for s in chosen}
    if unknown:
        raise ValueError(f"unknown fight scenarios: {sorted(unknown)}")
    with Pool(min(jobs, len(chosen))) as pool:
        failed = []
        for name, frames, seconds, error in pool.imap_unordered(_export_one, [(s, str(out_dir)) for s in chosen]):
            if error:
                log.error("fight %s failed after %.0f s:\n%s", name, seconds, error)
                failed.append(name)
            else:
                log.info("fight %s: %d frames in %.0f s", name, frames, seconds)
    if failed:
        raise RuntimeError(f"fight scenarios failed: {failed}")


def main() -> int:
    import collections
    import time
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    scenario = Scenario("probe", (0, 1), (0, 0), 0, seed=1)
    t = time.time()
    transitions = collections.Counter()
    calls = collections.Counter()
    frames = 0
    for h, pads, sub, frame_calls in record(scenario):
        frames += 1
        for i in range(2):
            f = FIGHTERS[i]
            transitions[h.s16(f + 0xA2)] += 1
        for c in frame_calls:
            calls[c[0]] += 1
        if frames % 600 == 0:
            log.info("frame %d round %d timer %d health %d %d wins %d %d", frames, h.s16(ROUND_STATE), h.s32(TIMER),
                     h.s32(FIGHTERS[0] + 0x3F4) >> 16, h.s32(FIGHTERS[1] + 0x3F4) >> 16,
                     h.s16(FIGHTERS[0] + 0x44), h.s16(FIGHTERS[1] + 0x44))
    log.info("%d frames in %.0f s", frames, time.time() - t)
    log.info("transitions %s", sorted(transitions))
    log.info("calls %s", dict(calls))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
