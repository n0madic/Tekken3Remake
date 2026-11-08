#!/usr/bin/env python3
"""Run a fight of the arcade version (MAME `tekken3`, World ver. E1) in the CPU harness.

The counterpart of fight_harness.py for the arcade program: the game's own code runs in the Unicorn
harness from the start-up calls of `main` (0x801899F4) through the game flow `FUN_801B6BA4` into
its fight sub-state, where `FUN_8018A988` runs every frame. Pad input is written to the words the
input routine `FUN_8018CD30` reads. ROM transfers are replaced by copies from the ROM set; the PsyQ
libraries that drive hardware (GPU, MDEC, interrupts) are stubbed; the board's other registers read
as RAM (zero unless written). BIOS calls (through 0xA0, 0xB0 and 0xC0) are served in Python.

Randomness: the BIOS `rand` is reproduced and seeded with the scenario's seed; the two generators
the frame wait steps (`0x8021FB5C`, `0x8021F838`) a number of times that depends on the board's
timing are stepped once per frame here, as fight_harness.py does for the PlayStation's.
"""

from __future__ import annotations

import argparse
import dataclasses
import logging
import struct
from concurrent.futures import ProcessPoolExecutor
from dataclasses import dataclass, field
from pathlib import Path

import arcade_cpu
import arcade_motion
import fight_harness
import psxcpu
from unicorn.mips_const import (
    UC_MIPS_REG_A0, UC_MIPS_REG_A1, UC_MIPS_REG_A2, UC_MIPS_REG_PC, UC_MIPS_REG_RA, UC_MIPS_REG_T1, UC_MIPS_REG_V0,
)

log = logging.getLogger("arcade_fight_harness")

ROOT = Path(__file__).resolve().parents[2]
FUNCTIONS = ROOT / "work" / "arcade" / "decomp_full" / "arcade_e1_full.exe.functions.tsv"

FIGHTERS = (0x8031E154, 0x8031FC38)
FIGHTER_SIZE = 0x1AE4

# Game globals (docs/research/arcade/README.md#program-structure)
GAME_STATE, SUB_STATE = 0x8021FD20, 0x8021FD64
FRAME_COUNTER = 0x8021F278
MAIN_FRAMES = 0x8021FDA4
ACTIVE_BUFFER = 0x8021FC80
BUFFER_OFFSET = 0x8021FB68          # 0xF0 on buffer 0, unless 0x8021FC98
BUFFER_OFFSET_OFF = 0x8021FC98
ORDERING_TABLE = 0x8021FB34
ORDERING_TABLES = 0x802C6BAC        # two GsOT headers, 20 bytes each
WORK_AREAS = 0x802C8300             # per display buffer, WORK_AREA bytes
WORK_AREA = 0x16440
CAMERA_RNG = 0x8021FB5C             # (x + 1) · 0x10DCD
FRAME_RNG = 0x8021F838              # x · 5 + 1
STAGE = 0x8021FBB8
CHARACTERS = 0x8021FBF0             # u16 per player
COSTUMES = 0x8021FC0C               # u16 per player
PLAYERS_ACTIVE = 0x8021FD18         # u16 per player
FIGHT_RESULT = 0x8021FD30
SIDE_FLAGS = 0x8021F6C0             # u16 per player (FUN_801A2D9C)
DISTANCE = 0x8021FD90               # the fighters' distance
ROUND_STATE, ROUND_COUNTER = 0x8021F0C0, 0x8021F0C4
TIMER = 0x8021FB8C
PADS = (0x1F083140, 0x1F083142)     # read by FUN_8018CD30, 1 = pressed
REGION = 0x8021FB74                 # FUN_801C2FCC: parameter group 0 when 0 or 1, else 1
CONTROLS = 0x8021FB58               # u16 per player: 0 human; n: +0x34A = 2n + 1 + player, a CPU (FUN_8018A44C)
SETTINGS = 0x8036EC1C               # the EEPROM copy (FUN_801F7920)

# Settings bytes (docs/research/arcade/README.md#settings)
SET_DIFFICULTY = 0x8036EC4F
SET_FIGHTS_ONE = 0x8036EC50
SET_FIGHTS_VERSUS = 0x8036EC51
SET_LIFE_ONE = 0x8036EC52
SET_LIFE_VERSUS = 0x8036EC53
SET_GUARD_DAMAGE = 0x8036EC54
SET_NEUTRAL_GUARD = 0x8036EC55
SET_ROUND_TIME = 0x8036EC56

# Game functions
MODE_START = 0x801BDA64             # (mode, player mask)
ATTRACT_MODE = 6
LADDER_ENTRY = 0x80374FA8           # the one-player ladder's first entry: u8 character, costume, level
SNAPSHOT_FRAME = 0x801BBE04
ATTRACT_FIGHTS = 0x8021F39C
MOVIE_WAIT = 0x801BD380             # FUN_801BD318: a movie's frame waits for its fourth vblank here
READ_INPUTS = 0x8018CD30
WORK_BASE = 0x801EE0EC
HUD_TABLES = 0x801B1870
GAME_FLOW = 0x801B6BA4
# main's switch on the game state.
STATE_ROUTINES = {
    0: 0x80189EC8,                  # boot
    1: 0x801B5EEC,                  # transition
    2: 0x801BD5A0,                  # attract
    3: 0x801BD97C,                  # title and coins
    4: GAME_FLOW,
    5: 0x801C06E4,                  # character select
    7: 0x801C241C,                  # ranking
    8: 0x801E5F50,                  # ending
}
ROM_DMA = 0x801BB048
ROM_WAIT = 0x801BB1D4
GET_ACTIVE_BUFF = 0x801EF2BC
FIGHT_SUB_STATE = 7
HEALTH = 0x33C

# main's start-up calls before its loop, in its order (the ones touching only hardware are left to
# the stubs below): (address, arguments).
BOOT_CALLS = (
    (0x801BB748, ()),               # the file table
    (0x80189FF4, ()),               # settings from the EEPROM copy
    (SNAPSHOT_FRAME, (0,)),
    (0x801BACAC, ()),
    (0x801BA774, ()),
    (0x801C2CDC, ()),
    (0x801A23C4, ()),
    (0x8018EAB4, ()),               # move tables relocated
    (0x801B0DD0, ()),
    (0x8018CCE0, ()),
    (0x801BC0C8, ()),
    (0x801B0ACC, (0,)),
    (0x801BD2BC, ()),
    (0x801BAE34, ()),
    (0x801ED83C, (0x352,)),         # GsSetProjection
    (0x801A8594, ()),
    (0x801AA2CC, ()),
    (0x801D4230, ()),
    (0x801D4C9C, ()),
)
PROJECTION = (0x8021FAF4, 0x352)

# Library code: stubbed unless kept. An unnamed function follows the named one before it.
LIBRARY = (0x801E7878, 0x801F21F0)
KEEP_PREFIX = (
    # The C library's calls through the BIOS vectors, served by _bios.
    "srand", "strlen", "rand", "memcpy",
    # Pure data: primitives, TIM and TMD headers, default environments.
    "GetTPage", "GetClut", "PRIM_OBJ", "NextPrim", "IsEndPrim", "AddPrim", "CatPrim", "TermPrim", "SetSemiTrans",
    "SetShadeTex", "SetPoly", "SetSprt", "SetTile", "SetLine", "SetBlockFill", "SetDrawTPage", "SetDrawMove",
    "SetDrawLoad", "MargePrim", "OpenTIM", "ReadTIM", "OpenTMD", "ReadTMD", "TMD_OBJ", "get_tim_addr", "get_tmd_addr",
    "unpack_packet", "LoadTPage", "EXT_OBJ", "LoadClut", "SetDefDrawEnv", "SetDefDispEnv",
    # Maths: the GS coordinate layer and libgte.
    "GsMulCoord", "GsGetLw", "GsInitCoord", "Gssub", "GS_115", "GS_123", "GS_133", "GS_137", "GsSetRefView", "GsSetLs",
    "GsSetLight", "RotMatrix", "FGO_", "CompMatrix", "SetMulRot", "PushMatrix", "PopMatrix", "csqrt", "COR_05",
    "TransposeMatrix", "ratan2", "RATAN", "SetFarColor", "SquareRoot", "Apply", "SetBackColor", "SetRotMatrix",
    "MulRotMatrix", "InvSquareRoot", "VectorNormal", "MSC02", "MatrixNormal", "LightColor", "DpqColor", "Intpl",
    "Square", "AverageZ", "OuterProduct", "Lzc", "RotTrans", "SetLightMatrix", "MulMatrix", "SetColorMatrix",
    "SetTransMatrix", "rcos", "GEO_", "rsin", "sin_1", "memclr", "memset", "gte_",
)
# Unnamed library functions that stay real although the module around them is stubbed.
KEEP_ADDRESSES = {
    0x801ED83C,                     # GsSetProjection → SetGeomScreen
    0x801F0684,                     # SetGeomScreen
    0x801F07F4,                     # SetGeomOffset: the fighters' screen coordinate (+0x1154) comes through it
}
RETURN_ZERO_CODE = struct.pack("<2I", 0x03E00008, 0x00001021)     # jr ra; move v0, zero
RETURN_A2_CODE = struct.pack("<2I", 0x03E00008, 0x00C01021)       # jr ra; move v0, a2
# Game routines that only talk to the board or draw.
NOOP = {
    0x801F7CF8,                     # the EEPROM copy and the build check (test mode)
    0x8019A858,                     # a fighter part's polygons (FUN_8019A6D0 keeps its projected point)
}
# Draw routines returning the packet pointer they were given (their third argument).
PASS_PACKET = {
    0x8019B380,                     # a fighter part's extra polygons
}

# The board's address ranges, RAM to the harness. Writes stay there, reads give them back.
BOARD_RANGES = ((0x1F000000, 0x800000), (0x1F801000, 0x3000))

# BIOS calls: (vector, $t1).
BIOS_A = 0xA0
BIOS_B = 0xB0
BIOS_C = 0xC0
RAND_MULTIPLIER, RAND_INCREMENT = 0x41C64E6D, 0x3039


def function_names() -> dict[int, str]:
    names = {}
    for line in FUNCTIONS.read_text().splitlines()[1:]:
        addr, name = line.split("\t")[:2]
        names[int(addr, 16)] = name
    return names


@dataclass
class Settings:
    """The operator settings the game copies from its EEPROM block."""
    difficulty: int = 1
    fights_one: int = 1
    fights_versus: int = 1
    life_one: int = 0
    life_versus: int = 0
    guard_damage: int = 0
    neutral_guard: int = 0
    round_time: int = 2


class ArcadeFightHarness:
    def __init__(self, zip_path: Path = arcade_cpu.DEFAULT_ZIP) -> None:
        self.arc = arcade_motion.open_with_flash(zip_path)
        self.cpu = arcade_cpu.arcade_cpu(self.arc)
        self.names = function_names()
        self.unknown_bios: set[tuple[int, int]] = set()
        self.vblank_counted = False
        self.rand_state = 0
        self.buffer = 0
        for start, size in BOARD_RANGES:
            self.cpu.uc.mem_map(start, size)
            self.cpu.uc.mem_write(start, bytes(size))
        self._stub_library()
        self._hook_bios()
        self._hook_movie_wait()
        cpu = self.cpu
        cpu.stub(ROM_DMA, self._rom_dma)
        cpu.stub(ROM_WAIT, lambda c, *a: 0)
        cpu.stub(GET_ACTIVE_BUFF, lambda c, *a: self.buffer)

    # ---- stubs ---------------------------------------------------------
    def _stub_library(self) -> None:
        keep = True
        lo, hi = LIBRARY
        for addr, name in sorted(self.names.items()):
            if not lo <= addr < hi:
                continue
            if not name.startswith("FUN_"):
                keep = name.startswith(KEEP_PREFIX)
            if not keep and addr not in KEEP_ADDRESSES:
                self._return_zero(addr)

        for addr in NOOP:
            self._patch(addr, RETURN_ZERO_CODE)
        for addr in PASS_PACKET:
            self._patch(addr, RETURN_A2_CODE)

    def _return_zero(self, addr: int) -> None:
        self._patch(addr, RETURN_ZERO_CODE)

    def _patch(self, addr: int, code: bytes) -> None:
        for site in (addr, addr + 4):
            self.cpu.drop_cop2(site)
        self.cpu.write(addr, code)

    def _rom_dma(self, cpu: psxcpu.PsxCpu, dst: int, src: int, size: int, *_: int) -> int:
        aligned = src & 0xFFFFFFFC
        cpu.write(dst, self.arc.read(aligned, (size + 3) & 0xFFFFFFFC))
        return dst

    def _hook_movie_wait(self) -> None:
        """No interrupts here: the wait's reads of the vblank counter pass one vblank each. The last
        one is the frame's own, as `step` would count it."""
        def hook(_uc, _address: int, _size: int, _user) -> None:
            self.w32(FRAME_COUNTER, self.u32(FRAME_COUNTER) + 1)
            self.vblank_counted = True
        self.cpu.uc.hook_add(psxcpu.UC_HOOK_CODE, hook, begin=MOVIE_WAIT, end=MOVIE_WAIT)

    def _hook_bios(self) -> None:
        """The BIOS is not in the harness: a jump to its vectors runs the call here."""
        uc = self.cpu.uc
        for vector in (BIOS_A, BIOS_B, BIOS_C):
            self.cpu.write(vector, RETURN_ZERO_CODE)
            uc.hook_add(psxcpu.UC_HOOK_CODE, self._bios_hook(vector), begin=vector, end=vector)

    def _bios_hook(self, vector: int):
        def hook(uc, address: int, size: int, _user) -> None:
            function = uc.reg_read(UC_MIPS_REG_T1)
            a0, a1, a2 = (uc.reg_read(r) for r in (UC_MIPS_REG_A0, UC_MIPS_REG_A1, UC_MIPS_REG_A2))
            result = self._bios(vector, function, a0, a1, a2)
            uc.reg_write(UC_MIPS_REG_V0, result & 0xFFFFFFFF)
            uc.reg_write(UC_MIPS_REG_PC, uc.reg_read(UC_MIPS_REG_RA))
        return hook

    def _bios(self, vector: int, function: int, a0: int, a1: int, a2: int) -> int:
        cpu = self.cpu
        if vector == BIOS_A:
            if function == 0x1B:            # strlen
                n = 0
                while cpu.read(a0 + n, 1)[0]:
                    n += 1
                return n
            if function == 0x2A:            # memcpy
                cpu.write(a0, cpu.read(a1, a2))
                return a0
            if function == 0x2B:            # memset
                cpu.write(a0, bytes([a1 & 0xFF]) * a2)
                return a0
            if function == 0x2F:            # rand
                self.rand_state = (self.rand_state * RAND_MULTIPLIER + RAND_INCREMENT) & 0xFFFFFFFF
                return (self.rand_state >> 16) & 0x7FFF
            if function == 0x30:            # srand
                self.rand_state = a0
                return 0
        self.unknown_bios.add((vector, function))
        return 0

    # ---- memory ----------------------------------------------------------
    def w8(self, a: int, v: int) -> None: self.cpu.write(a, struct.pack("<B", v & 0xFF))
    def w16(self, a: int, v: int) -> None: self.cpu.write(a, struct.pack("<H", v & 0xFFFF))
    def w32(self, a: int, v: int) -> None: self.cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))
    def u8(self, a: int) -> int: return self.cpu.read(a, 1)[0]
    def s16(self, a: int) -> int: return struct.unpack("<h", self.cpu.read(a, 2))[0]
    def u16(self, a: int) -> int: return struct.unpack("<H", self.cpu.read(a, 2))[0]
    def s32(self, a: int) -> int: return struct.unpack("<i", self.cpu.read(a, 4))[0]
    def u32(self, a: int) -> int: return struct.unpack("<I", self.cpu.read(a, 4))[0]

    # ---- set-up ----------------------------------------------------------
    def boot(self, settings: Settings, seed: int) -> None:
        """main's start-up up to its loop, in its order."""
        cpu = self.cpu
        for address, value in ((SET_DIFFICULTY, settings.difficulty), (SET_FIGHTS_ONE, settings.fights_one),
                               (SET_FIGHTS_VERSUS, settings.fights_versus), (SET_LIFE_ONE, settings.life_one),
                               (SET_LIFE_VERSUS, settings.life_versus), (SET_GUARD_DAMAGE, settings.guard_damage),
                               (SET_NEUTRAL_GUARD, settings.neutral_guard), (SET_ROUND_TIME, settings.round_time)):
            self.w8(address, value)
        self.w32(FIGHTERS[0] + 0x14, 0)
        self.w32(FIGHTERS[1] + 0x14, 1)
        self.w32(PROJECTION[0], PROJECTION[1])
        for address, args in BOOT_CALLS:
            cpu.call(address, *args)
        self.w16(0x8021FC64, 1)
        self.w32(ORDERING_TABLE, ORDERING_TABLES)
        self.rand_state = seed
        self.rand_start = seed
        self.w32(CAMERA_RNG, seed)
        self.w32(FRAME_RNG, seed)

    def versus(self, chars: tuple[int, int], costumes: tuple[int, int], stage: int) -> None:
        """A two-player game past the character select: the flow's sub-state 2 with the choice made,
        the stage forced before the fighters load."""
        cpu = self.cpu
        cpu.call(MODE_START, 0, 3)
        for i in range(2):
            self.w16(CHARACTERS + 2 * i, chars[i])
            self.w16(COSTUMES + 2 * i, costumes[i])
        self.w32(SUB_STATE, 2)
        for _ in range(64):
            if self.s32(SUB_STATE) >= 4:
                break
            self.step((0, 0))
        else:
            raise RuntimeError("the flow did not reach the fighters' load")
        self.w16(STAGE, stage)

    def _reach_load(self, stage: int) -> None:
        """Steps the flow from its sub-state 2 to the fighters' load, the stage forced before it."""
        self.w32(SUB_STATE, 2)
        for _ in range(64):
            if self.s32(SUB_STATE) >= 4:
                break
            self.step((0, 0))
        else:
            raise RuntimeError("the flow did not reach the fighters' load")
        self.w16(STAGE, stage)

    def one_player(self, chars: tuple[int, int], costumes: tuple[int, int], stage: int, cpu_player: int, level: int) -> None:
        """A one-player game: player `cpu_player` is the CPU of the ladder's first entry (FUN_801B66D8
        reads its character, costume and level)."""
        human = 1 - cpu_player
        self.cpu.call(MODE_START, 0, 1 << human)
        self.w16(CHARACTERS + 2 * human, chars[human])
        self.w16(COSTUMES + 2 * human, costumes[human])
        for offset, value in enumerate((chars[cpu_player], costumes[cpu_player], level)):
            self.w8(LADDER_ENTRY + offset, value)
        self._reach_load(stage)

    def attract(self, chars: tuple[int, int], costumes: tuple[int, int], stage: int) -> None:
        """The demonstration: both fighters are CPUs (FUN_801BE014), here with the scenario's choice."""
        self.cpu.call(MODE_START, ATTRACT_MODE, 0)
        for i in range(2):
            self.w16(CHARACTERS + 2 * i, chars[i])
            self.w16(COSTUMES + 2 * i, costumes[i])
        self._reach_load(stage)

    # ---- frames ----------------------------------------------------------
    def step(self, pads: tuple[int, int]) -> int:
        """One frame of main's loop; returns the flow's sub-state after it."""
        cpu = self.cpu
        if not self.vblank_counted:
            self.w32(FRAME_COUNTER, self.u32(FRAME_COUNTER) + 1)
        self.vblank_counted = False
        cpu.call(SNAPSHOT_FRAME, 1)
        self.w32(CAMERA_RNG, (self.u32(CAMERA_RNG) + 1) * 0x10DCD)
        self.w32(FRAME_RNG, self.u32(FRAME_RNG) * 5 + 1)
        for address, buttons in zip(PADS, pads):
            self.w16(address, buttons)
        cpu.call(READ_INPUTS)
        self.w32(MAIN_FRAMES, self.u32(MAIN_FRAMES) + 1)
        self.buffer = self.u32(FRAME_COUNTER) & 1
        self.w16(ACTIVE_BUFFER, self.buffer)
        self.w16(BUFFER_OFFSET, 0 if self.u16(BUFFER_OFFSET_OFF) or self.buffer else 0xF0)
        self.w32(ORDERING_TABLE, ORDERING_TABLES + 20 * self.buffer)
        cpu.call(WORK_BASE, WORK_AREAS + WORK_AREA * self.buffer)
        cpu.call(HUD_TABLES, self.buffer)
        cpu.call(STATE_ROUTINES[self.s32(GAME_STATE)])
        return self.s32(SUB_STATE)

    def fighter(self, i: int) -> bytes:
        return self.cpu.read(FIGHTERS[i], FIGHTER_SIZE)


THROW_REACH = 0x700         # a throwing bot walks up to this distance
MOVE_ROWS, MOVE_ROW_SIZE = 0x80025E8C, 0x3C
_LP, _RP, _LK, _RK = fight_harness.LP, fight_harness.RP, fight_harness.LK, fight_harness.RK
_NEUTRAL = (5, 0)
# Moves a bot repeats on the opponent: its reach, then (numpad direction, buttons) per frame.
MOVE_PLANS = {
    "king_chain_a": (0x600, (_NEUTRAL,) * 10 + ((6, 0), (3, 0), (3, _LP | _LK), _NEUTRAL)),
    "king_chain_b": (0x600, (_NEUTRAL,) * 10 + ((6, 0), (3, 0), (3, _RP | _RK), _NEUTRAL)),
    "king_back": (0x700, (((2, 0),) + (_NEUTRAL,) * 24) * 3 + (_NEUTRAL,) * 30 + ((5, _RP | _RK), _NEUTRAL)),
    "side_up": (0x700, (((8, 0),) + (_NEUTRAL,) * 24) * 2 + (_NEUTRAL,) * 30 + ((5, _LP | _LK), _NEUTRAL)),
    "side_down": (0x700, (((2, 0),) + (_NEUTRAL,) * 24) * 2 + (_NEUTRAL,) * 30 + ((5, _LP | _LK), _NEUTRAL)),
    "side_back": (0x700, (((8, 0),) + (_NEUTRAL,) * 24) * 3 + (_NEUTRAL,) * 30 + ((5, _LP | _LK), _NEUTRAL)),
    "paul_arm": (0x700, ((1, _LP | _RP), _NEUTRAL)),
    "paul_sway": (0x900, ((4, _LP | _RP), _NEUTRAL)),
    "paul_smash": (0x900, ((2, 0), (2, 0), (3, 0), (3, 0), (6, _RP), _NEUTRAL)),
    "jin_step": (0x900, ((4, 0), (4, _LP | _RK), _NEUTRAL)),
}
# The next part of a multi-part throw: a move's row -> the frame of that move its list waits for, and
# the inputs that end on that frame.
CHAIN_INPUTS = {
    4653: (0x40, ((5, _RP), _NEUTRAL, (5, _LP), _NEUTRAL, (5, _LP | _RP))),
    4655: (0xA5, ((5, _LK | _RK), _NEUTRAL, (5, _LP | _RP))),
    4657: (0x81, ((5, _LP), _NEUTRAL, (5, _RP), _NEUTRAL, (5, _LK | _RK))),
    4659: (0xBE, ((5, _RP), _NEUTRAL, (5, _LP), _NEUTRAL, (5, _LK), _NEUTRAL, (5, _RK))),
    4665: (0x40, ((5, _RP), _NEUTRAL, (5, _LP), _NEUTRAL, (5, _LP | _RP))),
    4667: (0xA5, ((5, _LK | _RK), _NEUTRAL, (5, _LP | _RP))),
    4669: (0x81, ((5, _LP), _NEUTRAL, (5, _RP), _NEUTRAL, (5, _LK | _RK))),
    4671: (0xBE, ((5, _RP), _NEUTRAL, (5, _LP), _NEUTRAL, (5, _LK), _NEUTRAL, (5, _RK))),
    1134: (10, ((5, _RP),)),
    1182: (10, ((2, _LP),)),
    1202: (10, ((5, _LP),)),
    1204: (15, ((5, _RK), _NEUTRAL, (5, _LP), _NEUTRAL, (5, _LP | _RP))),
}
CHAIN_LATENCY = 1           # a frame's input is seen by the next frame's list, with this frame's pose frame


class ArcadeBot(fight_harness.Bot):
    """fight_harness.Bot on the arcade's panel and fighter record."""

    UP, DOWN, LEFT, RIGHT = 0x2000, 0x1000, 0x800, 0x400    # the table at 0x8001095C
    LP, RP, LK, RK = 0x200, 0x100, 0x40, 0x20               # FUN_8018E220

    def _field(self, off: int, fmt: str) -> int:
        return struct.unpack_from("<" + fmt, self.h.cpu.read(FIGHTERS[self.index] + off, 4))[0]

    def _opponent(self, off: int, fmt: str) -> int:
        return struct.unpack_from("<" + fmt, self.h.cpu.read(FIGHTERS[1 - self.index] + off, 4))[0]

    def right_side(self) -> bool:
        return self.h.u16(SIDE_FLAGS + 2 * self.index) != 0

    def distance(self) -> int:
        return self.h.u32(DISTANCE)

    def knocked_down(self) -> bool:
        return bool(self._field(0x50, "I") & 4)

    def opponent_attacking(self) -> bool:
        return self._opponent(0x4E, "h") != 0

    def next(self) -> int:
        entry = CHAIN_INPUTS.get((self._field(0x44, "I") - MOVE_ROWS) // MOVE_ROW_SIZE)
        if self.style in MOVE_PLANS and entry is not None:
            if self._field(0x48, "h") + CHAIN_LATENCY + len(entry[1]) - 1 == entry[0]:
                self.queue = list(entry[1])
        return super().next()

    def _plan(self) -> None:
        if self.style == "rise":
            self._tap(6 if self.knocked_down() else 5, 0, 20)
        elif self.style == "break":
            # Presses that break throws.
            self._tap(5, self.rng.choice((_LP, _RP, _LP | _RP)), self.rng.randint(1, 3))
        elif self.style in MOVE_PLANS:
            reach, inputs = MOVE_PLANS[self.style]
            if self._field(0x64, "h") != 0:     # in a throw: only its next part (CHAIN_INPUTS)
                self._hold(5, 1)
            elif self.distance() > reach:
                self._hold(6, 2)
            else:
                self.queue += list(inputs) + [_NEUTRAL] * self.rng.randint(40, 70)
        elif self.style != "throw":
            super()._plan()
        elif self.distance() > THROW_REACH:
            self._hold(6, 6)
        else:
            # Throw commands, and button mashing that may chain them.
            directions, buttons = (5, 6, 3, 2, 1, 4, 5, 5), (fight_harness.LP | fight_harness.LK,
                                                             fight_harness.RP | fight_harness.RK,
                                                             fight_harness.LP | fight_harness.RP,
                                                             fight_harness.LK | fight_harness.RK)
            self._tap(self.rng.choice(directions), self.rng.choice(buttons), self.rng.randint(1, 12))


# ---- scenarios and trace writing ------------------------------------------------------------

@dataclass
class Scenario:
    name: str
    chars: tuple[int, int]
    costumes: tuple[int, int]
    stage: int
    seed: int
    styles: tuple[str, str] = ("random", "random")
    settings: Settings = field(default_factory=Settings)
    max_frames: int = 20000
    pads: tuple[tuple[int, int], ...] | None = None     # a script instead of the bots (0 past its end)
    cpu: int | None = None          # a one-player game: the CPU's player, against a human bot
    level: int = 0                  # the CPU's level in a one-player game
    attract: bool = False           # the demonstration: two CPUs
    region: int | None = None       # forces 0x8021FB74, which picks the CPU's parameter group
    extra_ranges: tuple[tuple[str, int, int], ...] = ()      # more RAM ranges recorded per frame
    rounds: int = 1                 # how many rounds to record
    attract_fights: int = 0         # the attract's fights so far: the first style of its camera


def record(scenario: Scenario, harness: ArcadeFightHarness | None = None):
    """Runs a scenario to the end of its `rounds`-th round and yields (harness, pads, sub-state before)
    per frame, with the harness holding the state after the frame."""
    h = harness or ArcadeFightHarness()
    h.boot(scenario.settings, scenario.seed)
    if scenario.region is not None:
        h.w32(REGION, scenario.region)
    if scenario.attract:
        h.attract(scenario.chars, scenario.costumes, scenario.stage)
        h.w32(ATTRACT_FIGHTS, scenario.attract_fights)
    elif scenario.cpu is not None:
        h.one_player(scenario.chars, scenario.costumes, scenario.stage, scenario.cpu, scenario.level)
    else:
        h.versus(scenario.chars, scenario.costumes, scenario.stage)
    h.rand_start = h.rand_state
    bots = [ArcadeBot(h, i, scenario.seed * 2 + i, scenario.styles[i]) for i in range(2)]
    fought = False
    rounds = 0
    live = 0
    for _ in range(scenario.max_frames):
        sub = h.s32(SUB_STATE)
        pads = (0, 0)
        if sub == FIGHT_SUB_STATE:
            fought = True
            if scenario.pads is None:
                pads = tuple(0 if scenario.attract or i == scenario.cpu else bot.next() for i, bot in enumerate(bots))
            elif live < len(scenario.pads):
                pads = scenario.pads[live]
            live += 1
        h.step(pads)
        yield h, pads, sub
        if fought and h.s32(SUB_STATE) != FIGHT_SUB_STATE:
            fought = False
            rounds += 1
            if rounds == scenario.rounds:
                return
    raise RuntimeError(f"{scenario.name}: the fight did not end within {scenario.max_frames} frames")


TRACE_MAGIC = b"T3AF"
TRACE_VERSION = 1
FRAME_HEADER = struct.calcsize("<HHbI")
RAND_AT = struct.calcsize("<HHb")
# Global RAM ranges recorded per frame, (name, address, size).
RANGES = (
    ("globals", 0x8021F000, 0xE00),     # the game's small globals: round, camera, input, flow
    ("match", 0x80374F18, 0x40),        # mode, flags, the fight's decision
    ("ai_records", 0x8029CF00, 2 * 0x364),
    ("camera_view", 0x802C6BD4, 0x24),  # the active camera: pitch, yaw, position
    ("director", 0x802F4B98, 0xB0),     # the camera director's state
    ("camera_sources", 0x8029DE44, 5 * 0x1C),
    ("camera_source_states", 0x8029DEF8, 5 * 0x3C),
    ("camera_targets", 0x80374FD8, 2 * 0x10),
    ("camera_prev_targets", 0x8036EB94, 2 * 0x10),
    ("camera_stream_sample", 0x8029E074, 0x18),
    ("camera_work", 0x802A1098, 0xB0),  # the hit point, the intro, the loser and the replay cameras
    ("camera_winner", 0x8025E584, 0x24),
    ("view_matrix", 0x8036EBFC, 0x20),
)


def frame_bytes(h: ArcadeFightHarness, pads: tuple[int, int], sub: int, extra: tuple = ()) -> bytes:
    """One frame of a trace: u16 pad 0, u16 pad 1, s8 sub-state before; after the frame the `rand`
    state (u32, kept outside the game's RAM here), both fighter records and the RANGES."""
    parts = [struct.pack("<HHbI", pads[0], pads[1], sub, h.rand_state), h.fighter(0), h.fighter(1)]
    parts += [h.cpu.read(address, size) for _, address, size in RANGES + extra]
    return b"".join(parts)


def write_trace(scenario: Scenario, path: Path) -> int:
    """Records a scenario into a trace (fight_harness.write_trace_file's container); returns the
    frame count."""
    body = bytearray()
    frames = 0
    harness = ArcadeFightHarness()
    for h, pads, sub in record(scenario, harness):
        body += frame_bytes(h, pads, sub, scenario.extra_ranges)
        frames += 1
    if harness.unknown_bios:
        raise RuntimeError(f"{scenario.name}: unknown BIOS calls {sorted(harness.unknown_bios)}")
    header = {
        "version": TRACE_VERSION,
        "scenario": {"name": scenario.name, "chars": list(scenario.chars), "costumes": list(scenario.costumes),
                     "stage": scenario.stage, "seed": scenario.seed, "styles": list(scenario.styles),
                     "settings": dataclasses.asdict(scenario.settings)},
        "rand_start": harness.rand_start,   # before the first frame, whose load draws the wind's direction
        "fighters": list(FIGHTERS),
        "fighter_size": FIGHTER_SIZE,
        "ranges": [[name, address, size] for name, address, size in RANGES + scenario.extra_ranges],
        "frames": frames,
        "call_kinds": [],               # TODO: the sound and effect calls (fight_harness.CALL_KINDS)
    }
    fight_harness.write_trace_file(path, TRACE_MAGIC, TRACE_VERSION, header, body)
    return frames


TIME_UP_HIT = 0x200                 # a jab early in the fight, then nobody moves until the clock runs out
TIME_UP_PADS = ((0, 0),) * 150 + ((TIME_UP_HIT, 0),) * 2
SHORT_ROUND = Settings(round_time=0)
TWO_ROUNDS = Settings(fights_versus=2)
# The CPU: its candidate table, for diagnosis (0x8029D5C8, 180 entries of 12 bytes).
CPU_RANGES = (("ai_candidates", 0x8029D5C8, 180 * 12),)
PAUL, LAW, KING, YOSHIMITSU, NINA, HWOARANG, JIN, OGRE, MOKUJIN, TRUE_OGRE = 0, 1, 3, 4, 5, 6, 9, 14, 15, 20
# Scripted humans for the CPU's hooks (FUN_801CE078 and its like): moves no bot finds, from the end of
# the round's introduction on. Panel words as ArcadeBot's; player 0 starts facing right.
FIGHT_READY = ((0, 0),) * 150
PAD_DOWN, PAD_RIGHT, PAD_LP, PAD_RP = 0x1000, 0x400, 0x200, 0x100
IDLE_PADS = ((0, 0),)
CROUCH_PADS = FIGHT_READY + ((PAD_DOWN, 0),) * 3000
CROUCH_AND_RISE_PADS = FIGHT_READY + (((PAD_DOWN, 0),) * 70 + ((0, 0),) * 40) * 40
WALK_PADS = FIGHT_READY + (((PAD_RIGHT, 0),) * 30 + ((0, 0),) * 10) * 150
PAUL_SMASHER_PADS = FIGHT_READY + (((PAD_DOWN, 0),) * 3 + ((PAD_RIGHT, 0),) * 3 + ((PAD_LP, 0),) * 2 + ((0, 0),) * 70) * 40
# True Ogre: the breath from a standing start; the sweep from a walk (a standing start gives his own row).
# Each takes about 200 frames.
OGRE_FIRE_PADS = FIGHT_READY + ((0, 0),) * 40 + (((PAD_LP | PAD_RP, 0),) * 4 + ((0, 0),) * 210 + ((PAD_RIGHT, 0),) * 16
                                                 + ((PAD_DOWN | PAD_LP | PAD_RP, 0),) * 4 + ((0, 0),) * 210) * 20
JAB_PADS = FIGHT_READY + (((PAD_LP, 0),) * 2 + ((0, 0),) * 28) * 100
SCENARIOS = {s.name: s for s in (
    Scenario("probe", (0, 1), (0, 0), 0, seed=1),
    # A human bot against the CPU: the characters with hooks on either side, the difficulties and levels.
    Scenario("cpu_vs_paul", (PAUL, JIN), (0, 0), 0, seed=11, cpu=1, level=0, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=0)),
    Scenario("cpu_king", (LAW, KING), (0, 0), 1, seed=12, cpu=1, level=3, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=1), styles=("guard", "random")),
    Scenario("cpu_vs_yoshimitsu", (YOSHIMITSU, NINA), (0, 0), 2, seed=13, cpu=1, level=5, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=2)),
    Scenario("cpu_hwoarang", (HWOARANG, PAUL), (0, 0), 3, seed=14, cpu=0, level=7, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=3)),
    Scenario("cpu_vs_ogre", (OGRE, JIN), (0, 0), 4, seed=15, cpu=1, level=9, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=4), styles=("spam", "random")),
    Scenario("cpu_yoshimitsu", (YOSHIMITSU, LAW), (0, 0), 5, seed=16, cpu=0, level=9, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=4)),
    Scenario("cpu_ogre", (OGRE, KING), (0, 0), 6, seed=17, cpu=0, level=8, extra_ranges=CPU_RANGES,
             settings=Settings(difficulty=3), styles=("random", "spam")),
    Scenario("cpu_region_group", (KING, HWOARANG), (0, 0), 7, seed=18, cpu=1, level=6, region=2,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=4)),
    Scenario("cpu_past_ladder", (PAUL, KING), (0, 0), 8, seed=19, cpu=1, level=10, extra_ranges=CPU_RANGES),
    Scenario("cpu_attract", (KING, YOSHIMITSU), (0, 0), 9, seed=20, attract=True, extra_ranges=CPU_RANGES),
    Scenario("cpu_vs_paul_smasher", (PAUL, JIN), (0, 0), 0, seed=41, cpu=1, level=5, pads=PAUL_SMASHER_PADS,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=2)),
    Scenario("cpu_vs_true_ogre", (TRUE_OGRE, JIN), (0, 0), 4, seed=42, cpu=1, level=5, pads=OGRE_FIRE_PADS,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=2)),
    Scenario("cpu_king_ground", (LAW, KING), (0, 0), 2, seed=44, cpu=1, level=9, pads=CROUCH_PADS,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=4)),
    # With neutral guard the human stays on his feet longer, for the King's other two hook branches;
    # the seeds of a throw and of a crouching grab out of several tried.
    Scenario("cpu_king_standing", (LAW, KING), (0, 0), 1, seed=71, cpu=1, level=9, pads=WALK_PADS, rounds=2,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=4, neutral_guard=1)),
    Scenario("cpu_king_crouching", (LAW, KING), (0, 0), 1, seed=60, cpu=1, level=9, pads=CROUCH_AND_RISE_PADS,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=4, neutral_guard=1)),
    Scenario("cpu_hwoarang_ducking", (PAUL, HWOARANG), (0, 0), 3, seed=45, cpu=1, level=9, pads=JAB_PADS,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=4)),
    # The seed of a setup (FUN_801CE984's slot) out of several tried.
    Scenario("cpu_hwoarang_setup", (PAUL, HWOARANG), (0, 0), 3, seed=52, cpu=1, level=9, pads=IDLE_PADS,
             extra_ranges=CPU_RANGES, settings=Settings(difficulty=4, neutral_guard=1)),
    Scenario("camera_stage1", (2, 3), (0, 0), 1, seed=2),               # H 800, stream rescale, mode 1
    Scenario("camera_stage3", (4, 5), (0, 0), 3, seed=3),               # H 800, no rescale
    Scenario("camera_stage4", (6, 7), (0, 0), 4, seed=4),               # H 700, mode 0
    Scenario("camera_stage5", (8, 9), (0, 0), 5, seed=5),               # H 800, mode 2
    Scenario("camera_stage10", (10, 11), (0, 0), 10, seed=6),           # H 550, no rescale
    Scenario("camera_rounds", (0, 2), (0, 0), 7, seed=7, settings=TWO_ROUNDS, rounds=2),   # later rounds, mode 0, no rescale
    Scenario("camera_match", (9, 5), (0, 0), 0, seed=36, settings=Settings(fights_versus=0)),   # the deciding round
    Scenario("camera_time_up", (1, 3), (0, 0), 2, seed=8, settings=SHORT_ROUND, pads=TIME_UP_PADS),
    # Throws: presets and streams, per stage mode and stream rescale.
    Scenario("camera_throws_king", (KING, PAUL), (0, 0), 4, seed=21, styles=("throw", "idle")),
    Scenario("camera_throws_nina", (NINA, JIN), (0, 0), 6, seed=22, styles=("throw", "idle")),
    Scenario("camera_throws_paul", (PAUL, KING), (0, 0), 7, seed=23, styles=("throw", "idle")),
    Scenario("camera_throws_yoshimitsu", (LAW, YOSHIMITSU), (0, 0), 0, seed=24, styles=("idle", "throw")),
    Scenario("camera_throws_hwoarang", (HWOARANG, NINA), (0, 0), 5, seed=25, styles=("throw", "idle")),
    Scenario("camera_throws_low", (JIN, KING), (0, 0), 11, seed=26, styles=("throw", "throw")),
    Scenario("camera_chain_king_a", (KING, PAUL), (0, 0), 4, seed=51, styles=("king_chain_a", "rise")),
    Scenario("camera_chain_king_b", (KING, NINA), (0, 0), 7, seed=52, styles=("king_chain_b", "rise")),
    Scenario("camera_paul_arm", (PAUL, KING), (0, 0), 1, seed=53, styles=("paul_arm", "rise")),
    Scenario("camera_paul_sway", (PAUL, KING), (0, 0), 3, seed=54, styles=("paul_sway", "idle")),
    Scenario("camera_paul_smash", (PAUL, NINA), (0, 0), 5, seed=55, styles=("paul_smash", "rise")),
    Scenario("camera_jin_step", (JIN, KING), (0, 0), 10, seed=56, styles=("jin_step", "rise")),
    Scenario("camera_throws_second_king", (PAUL, KING), (0, 0), 4, seed=57, styles=("idle", "throw")),
    Scenario("camera_throws_second_nina", (KING, NINA), (0, 0), 6, seed=58, styles=("idle", "throw")),
    Scenario("camera_chain_king_second", (NINA, KING), (0, 0), 7, seed=59, styles=("rise", "king_chain_a")),
    Scenario("camera_back_king", (KING, NINA), (0, 0), 6, seed=71, styles=("king_back", "rise")),
    Scenario("camera_chain_king_b_second", (NINA, KING), (0, 0), 7, seed=59, styles=("rise", "king_chain_b")),
    Scenario("camera_breaks", (KING, PAUL), (0, 0), 7, seed=63, styles=("throw", "break")),
    Scenario("camera_breaks_second", (NINA, KING), (0, 0), 4, seed=64, styles=("break", "throw")),
    Scenario("camera_law_up", (LAW, KING), (0, 0), 3, seed=84, styles=("side_up", "rise")),
    Scenario("camera_paul_down", (PAUL, KING), (0, 0), 5, seed=96, styles=("side_down", "rise")),
    Scenario("camera_law_back", (LAW, KING), (0, 0), 10, seed=85, styles=("side_back", "rise")),
    Scenario("camera_throws_both", (KING, NINA), (0, 0), 6, seed=27, styles=("throw", "throw")),
    # The loser's camera: the CPU beats an idle human, by knockout and on time.
    Scenario("camera_loser", (PAUL, JIN), (0, 0), 1, seed=31, styles=("idle", "idle"), cpu=1, level=5,
             settings=Settings(fights_one=0)),
    Scenario("camera_loser_time", (KING, NINA), (0, 0), 5, seed=32, styles=("idle", "idle"), cpu=1, level=0,
             settings=Settings(fights_one=0, round_time=0)),
    # The attract's fights, one per stage mode: the styles of FUN_801D683C.
    Scenario("camera_attract_free", (PAUL, HWOARANG), (0, 0), 4, seed=33, attract=True),
    Scenario("camera_attract_orbit", (PAUL, HWOARANG), (0, 0), 7, seed=37, attract=True, attract_fights=1),
    Scenario("camera_attract_sweep", (KING, JIN), (0, 0), 6, seed=38, attract=True, attract_fights=3),
    Scenario("camera_attract_low", (LAW, JIN), (0, 0), 1, seed=34, attract=True, attract_fights=2),
    Scenario("camera_attract_lowest", (NINA, KING), (0, 0), 5, seed=35, attract=True, attract_fights=2),
    Scenario("camera_attract_lowest_orbit", (NINA, LAW), (0, 0), 11, seed=39, attract=True, attract_fights=1),
    Scenario("wind_stage11", (KING, JIN), (0, 0), 11, seed=41),      # six attachments each
    Scenario("mokujin", (MOKUJIN, PAUL), (0, 0), 1, seed=42, settings=TWO_ROUNDS, rounds=2),      # a character's moves per round
)}


# ---- the oracle's checks ----------------------------------------------------------------------

CHECK_FRAMES = 500
CHECK = Scenario("check", (0, 1), (0, 0), 0, seed=1)
# A routine whose loss must show in the state: the hit test.
HIT_TEST = 0x8018B91C


def _check_run(args: tuple[str, Scenario]) -> tuple[str, list[bytes], list]:
    """Runs a variant of the check; returns each frame's bytes and the BIOS calls it did not know."""
    variant, scenario = args
    harness = ArcadeFightHarness()
    if variant == "no_hits":
        harness._return_zero(HIT_TEST)
    frames = []
    for h, pads, sub in record(scenario, harness):
        frames.append(frame_bytes(h, pads, sub))
        if len(frames) >= CHECK_FRAMES:
            break
    return variant, frames, sorted(harness.unknown_bios)


def check() -> int:
    """The oracle has to be deterministic and has to fail: the same run twice gives the same bytes,
    other input and a removed routine do not."""
    other = dataclasses.replace(CHECK, seed=2)
    runs = [("first", CHECK), ("second", CHECK), ("other_seed", other), ("no_hits", CHECK)]
    # An executor, not a Pool: a worker that dies raises BrokenProcessPool here instead of hanging.
    with ProcessPoolExecutor(len(runs)) as pool:
        results = {variant: (frames, unknown) for variant, frames, unknown in pool.map(_check_run, runs)}
    first = results["first"][0]
    if len(first) != CHECK_FRAMES:
        log.error("only %d frames ran", len(first))
        return 1
    # The game has to draw on `rand`, or the seed proves nothing.
    failed = first[-1][RAND_AT:FRAME_HEADER] == first[0][RAND_AT:FRAME_HEADER]
    if failed:
        log.error("the game never called rand")
    for variant, want_equal in (("second", True), ("other_seed", False), ("no_hits", False)):
        frames = results[variant][0]
        # The records and RAM, not the seed's own word in the frame's header.
        diverged = next((i for i, (a, b) in enumerate(zip(first, frames)) if a[FRAME_HEADER:] != b[FRAME_HEADER:]), None)
        log.info("%s: %s", variant, "identical" if diverged is None else f"diverges at frame {diverged}")
        failed |= (diverged is None) != want_equal
    unknown = sorted({call for _, calls in results.values() for call in calls})
    if unknown:
        log.error("unknown BIOS calls: %s", unknown)
        failed = True
    log.info("check %s", "FAILED" if failed else "passed")
    return 1 if failed else 0


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--check", action="store_true", help="the oracle's determinism and negative controls")
    parser.add_argument("--out", type=Path, help="write the scenario's trace here")
    parser.add_argument("--scenario", default="probe", choices=sorted(SCENARIOS), help="the scenario (default: probe)")
    args = parser.parse_args()
    if args.check:
        return check()
    scenario = SCENARIOS[args.scenario]
    if args.out:
        log.info("%d frames", write_trace(scenario, args.out))
        return 0
    for frame, (h, _pads, sub) in enumerate(record(scenario)):
        if frame % 60 == 0:
            log.info("frame %d sub %d round %d timer %d health %d %d", frame, sub, h.s16(ROUND_STATE), h.s32(TIMER),
                     h.s32(FIGHTERS[0] + HEALTH) >> 16, h.s32(FIGHTERS[1] + HEALTH) >> 16)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
