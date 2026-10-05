#!/usr/bin/env python3
"""Run the whole game (Japan Rev.1) in the CPU harness from boot, frame by frame.

The game's own code runs: `BootInit` (0x800B0A10), then every frame the main loop's work
(`main` 0x80028DF4): the frame counters and random generators the vertical-blank wait steps,
the pads read through the key configuration (`FUN_8002A014`), the display buffer, and the
handler of the game state `g_gameState` (0x800AE6CC) — boot, overlay loader, transition screen,
title, main menu, options, the demonstration, fight preparation, `FightMain`, character select,
quick select, the VS screen, the results, the ranking and the ending.

The disc loader copies the BNS files of `work/jp_rev1/bns` (`FightHarness`); an overlay loaded
into one of the two overlay slots (mode 0x800B0A10, screen 0x800B9378) gets its COP2 sites from
its Ghidra listing, and the harness's stubs of overlay code follow the overlay in the slot. Hardware
libraries (GPU, CD, SPU, pads, memory card, events) and the drawing of fighters and stages are
stubbed as in `fight_harness.py`; the 2D screens draw their packets for real.

Modelled as the remake runs them:

- loading is instant (the disc loader is never busy);
- the memory card holds no Tekken 3 file at start-up (the defaults stay), and saves succeed;
- a movie ends on its first frame;
- music and CD streaming are logged calls only.

Used by `flow_trace.py`.
"""

from __future__ import annotations

import logging
import struct
from pathlib import Path

from unicorn.mips_const import UC_MIPS_REG_S2, UC_MIPS_REG_S7

import fight_harness as fh
import psxcpu
from make_overlay_exes import overlay_base

log = logging.getLogger("game_harness")

ROOT = Path(__file__).resolve().parents[2]
DECOMP = ROOT / "work" / "decomp"
MODE_SLOT, SCREEN_SLOT = 0x800B0A10, 0x800B9378
BOOT_INIT = 0x800B0A10
STATE_HANDLERS = {
    0: 0x800B0BD0, 1: 0x80052FAC, 2: 0x8004FD48, 3: 0x800DB7D4, 4: 0x800DBBD0, 5: 0x800DE480,
    6: 0x800D3844, 7: 0x80050600, 8: 0x80050710, 9: 0x8011056C, 10: 0x80055878, 11: 0x80052808,
    12: 0x800EF4AC, 13: 0x800EFF4C, 14: 0x800F0A78, 15: 0x800F1F08, 16: 0x800504A8, 17: 0x800C2A24,
    18: 0x8005025C, 19: 0x8010E8C0,
}
PAD_RECORD_CONNECTED = 0x28
PAD_INIT = 0x800B1064
FRAME_EVENTS = 0x80029AE8           # the vertical-blank counters and flags (events stubbed)
# BootInit's writes: the fighters' model flags, the players, the attract flag.
BOOT_FLAGS = ((0x800A9702, 0), (0x800AAF8E, 1), (0x800AC81A, 1), (0x800A970E, 0), (0x800AAF9A, 1),
              (0x800AC826, 2), (0x800AE6C2, 0), (0x800AE6C0, 0), (0x800AE39C, 1), (0x8009588C, 0),
              (0x800958B8, 0))
# Picture uploads to VRAM (archives and compressed TIMs): BootState's system textures, the VS
# screen's backdrop and portraits, the ranking's headers.
PICTURE_UPLOADS = (0x8004CD28, 0x8004CACC, 0x8004C9E4, 0x8004CC04)
SAVE_PENDING = 0x800AE428
MAIN_S2 = 0x800AE508                # main (0x80028DF4) keeps this address in $s2
RESIDENT_CODE = (0x80010000, 0x8008E97C)   # the game's code before the PsyQ libraries
RAM_MIRROR = (0x200000, 0x200000)   # the first mirror of the 2 MB RAM (bug #31 writes into it)
CD_READY = 0x80098BB4
THEATER_DISC = 0x800AE159
DISPLAY_ON = 0x80095850

# The memory card: the start-up read finds no Tekken 3 file (5), saves and formats succeed (0).
CARD_LOAD, CARD_SAVE, CARD_FORMAT, CARD_WRITE = 0x8004C528, 0x8004C420, 0x8004C4B4, 0x8004C1A8
CARD_FIRSTFILE = 0x8007A45C
NO_FILE = 5

# Stubs of overlay code, by overlay: address -> result (the function returns it at once).
OVERLAY_STUBS = {
    "title": {
        0x800E24F0: 0,              # movie start
        0x800E2510: 1,              # movie frame: the movie has ended
    },
}

# Instruction patches of overlay code, by overlay: address -> instruction word.
OVERLAY_PATCHES = {
    "select": {
        0x8010EB74: 0x00001021,     # FUN_8010EA2C: skip the big portrait's TIM load (VRAM only)
    },
    # game-bugs.md #47 (not reproduced): FUN_800B598C saves the player's second six angle fields
    # (+0x38..+0x42) in the save's second half instead of the first six again, and restores them
    # from that half instead of the first.
    "force": {
        **{0x800B5AE0 + 12 * k: 0x96220038 + 2 * k for k in range(6)},     # lhu $v0, 0x38+2k($s1)
        0x800B5D48: 0x97A2001C,                                            # lhu $v0, 0x1C($sp)
        **{0x800B5D54 + 12 * k: 0x9462000E + 2 * k for k in range(5)},     # lhu $v0, 0xE+2k($v1)
    },
}


def _overlay_names() -> dict[int, str]:
    """BNS id -> overlay name of the overlay files."""
    names = {}
    for p in fh.BNS_DIR.iterdir():
        if p.name[:3].isdigit() and p.suffix == ".ovl":
            names[int(p.name[:3])] = p.stem.split("_", 1)[1]
    return names


class GameHarness(fh.FightHarness):
    def __init__(self, gameplay_fixes: bool = False) -> None:
        super().__init__(gameplay_fixes)
        self.cpu.uc.mem_map(*RAM_MIRROR)
        # The R3000's quotients for zero divisors (Unicorn returns the dividend), in the resident
        # code and in each overlay while it is loaded.
        self.cpu.r3000_divide_range(*RESIDENT_CODE)
        self.slot_ends: dict[int, int] = {MODE_SLOT: MODE_SLOT, SCREEN_SLOT: SCREEN_SLOT}
        self.overlay_ids = _overlay_names()
        self.slots: dict[int, str | None] = {MODE_SLOT: None, SCREEN_SLOT: None}
        self.frames = 0
        cpu = self.cpu
        cpu.stub(CARD_LOAD, lambda c, *a: NO_FILE)
        for addr in (CARD_SAVE, CARD_FORMAT, CARD_WRITE):
            cpu.stub(addr, lambda c, *a: 0)
        cpu.write(CARD_FIRSTFILE, struct.pack("<2I", 0x03E00008, 0x24020001))   # a file is found
        for addr in PICTURE_UPLOADS:
            self._patch_return(addr, fh.RETURN_ZERO_CODE)

    # ---- overlays ------------------------------------------------------
    def _bns_load(self, cpu: psxcpu.PsxCpu, logical: int, dest: int, *_: int) -> int:
        bns = struct.unpack("<H", cpu.read(fh.LOGICAL_TO_ID + 2 * logical, 2))[0]
        name = self.overlay_ids.get(bns)
        if name is None or dest not in self.slots:
            return super()._bns_load(cpu, logical, dest)
        # The overlay's code and hooks are put in place once the stub returns (outside the emulation).
        self.cpu.defer(lambda: self.load_overlay(name, dest))
        self.calls.append(("load", bns))
        return 0

    def load_overlay(self, name: str, dest: int) -> None:
        """Copies an overlay into its slot with its COP2 sites; the previous occupant's sites and
        stubs are dropped."""
        cpu = self.cpu
        data = (fh.BNS_DIR / f"{min(k for k, v in self.overlay_ids.items() if v == name):03d}_{name}.ovl").read_bytes()
        if overlay_base(name) != dest:
            raise ValueError(f"overlay {name} loaded at {dest:#x}, expected {overlay_base(name):#x}")
        old = self.slots[dest]
        if old is not None:
            for addr in OVERLAY_STUBS.get(old, {}):
                cpu.stubs.pop(addr, None)
        end = dest + len(data)
        for site in list(cpu.cop2_sites):
            if dest <= site < end:
                cpu.drop_cop2(site)
        sites = psxcpu.read_sites(DECOMP / f"jp_rev1_{name}.exe.cop2.txt", dest, 0x80200000)
        cpu.load(dest, data, sites)
        for addr, word in OVERLAY_PATCHES.get(name, {}).items():
            cpu.write(addr, struct.pack("<I", word))
        cpu.drop_divides(dest, self.slot_ends[dest])
        cpu.r3000_divide_range(dest, end)
        self.slot_ends[dest] = end
        self.slots[dest] = name
        for addr, result in OVERLAY_STUBS.get(name, {}).items():
            cpu.stub(addr, lambda c, *a, r=result: r)

    # ---- boot and frames -----------------------------------------------
    def boot(self, seed: int) -> None:
        """BootInit (0x800B0A10) without its hardware set-up; the random generators are seeded
        with `seed` instead of the scratchpad's contents (FUN_800B0CAC)."""
        cpu = self.cpu
        for addr, args in fh.BOOT_CALLS[:4]:
            cpu.call(addr, *args)
        self.w8(SAVE_PENDING, 0)                        # FUN_800B0E1C (the card set-up)
        self.w8(SAVE_PENDING + 1, 0)
        cpu.call(PAD_INIT)
        for addr, args in fh.BOOT_CALLS[4:]:
            cpu.call(addr, *args)
        for i in range(2):
            self.w32(fh.ORDERING_TABLES + 20 * i, 10)
            self.w32(fh.ORDERING_TABLES + 20 * i + 4, fh.OT_ENTRIES + 0x1000 * i)
        for i, f in enumerate(fh.FIGHTERS):
            self.w16(f + 0x12, i)
            self.w8(f + 0x1E, i)
            self.w8(f + 0x20, 1 - i)
        for addr, value in BOOT_FLAGS:
            self.w16(addr, value)
        self.w32(fh.GAME_STATE, 0)
        self.w32(fh.SUB_STATE, 0)
        self.w32(fh.FRAME_COUNTER, 0)
        cpu.call(FRAME_EVENTS)
        # FUN_8006AE4C's first call (the CD set-up, skipped): later calls only stop the CD.
        self.w32(CD_READY, 1)
        self.w8(THEATER_DISC, 3)
        cpu.call(self.srand, seed)
        self.w32(fh.CAMERA_RNG, seed)
        self.w32(fh.FRAME_RNG, seed)

    def step(self, pads: tuple[int, int]) -> tuple[int, int]:
        """One frame of the main loop; returns the game state and sub-state after it."""
        self.calls = []
        self.frames += 1
        self.w32(fh.FRAME_COUNTER, self.s32(fh.FRAME_COUNTER) + 1)
        self.w32(fh.VBLANK, self.s32(fh.FRAME_COUNTER))
        self.w32(fh.CAMERA_RNG, (self.u32(fh.CAMERA_RNG) + 1) * 0x10DCD)
        self.w32(fh.FRAME_RNG, self.u32(fh.FRAME_RNG) * 5 + 1)
        for record, buttons in zip(fh.PAD_RECORDS, pads):
            self.w16(record, buttons)
            self.w8(record + PAD_RECORD_CONNECTED, 1)
        self.cpu.call(fh.PAD_MAP, 0)
        self._frame_buffers()
        state = self.state()
        # The main loop's saved registers that game code reads without setting them: $s2 holds
        # 0x800AE508 (bug #31's stray write), $s7 the start-up value (bug #44), taken as 0.
        self.cpu.uc.reg_write(UC_MIPS_REG_S2, MAIN_S2)
        self.cpu.uc.reg_write(UC_MIPS_REG_S7, 0)
        self.cpu.call(STATE_HANDLERS[state])
        return self.state(), self.sub_state()

    def state(self) -> int:
        return struct.unpack("<H", self.cpu.read(fh.GAME_STATE, 2))[0]

    def sub_state(self) -> int:
        return struct.unpack("<H", self.cpu.read(fh.SUB_STATE, 2))[0]


def main() -> int:
    import time
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    h = GameHarness()
    h.boot(1)
    t = time.time()
    last = None
    for frame in range(3000):
        pads = (0x800 if 700 <= frame < 702 else 0, 0)
        st = h.step(pads)
        if st != last:
            log.info("frame %d: state %d sub %d %s", frame, st[0], st[1], [c for c in h.calls if c[0] != "sound"][:4])
            last = st
    log.info("%d frames in %.0f s", h.frames, time.time() - t)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
