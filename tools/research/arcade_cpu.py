"""The arcade program (MAME `tekken3`, World ver. E1) in the CPU harness.

The System 12 CPU is the PlayStation's R3000A with a GTE, so psxcpu runs the arcade's routines
too (docs/research/arcade/README.md#method-and-tools): the decompressed program is
loaded at 0x80010000 behind a synthetic PS-X EXE header, with 4 MB of RAM and the stack above the
BSS. Its GTE instructions are the ones Ghidra lists in work/arcade/decomp_full (written by the
decompilation, like the PlayStation's work/decomp lists).
"""

from __future__ import annotations

import struct
import sys
from pathlib import Path

from unicorn import UC_HOOK_MEM_WRITE

import psxcpu

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools" / "remake_import"))
import arcade  # noqa: E402

ARCADE_RAM = 0x400000
STACK = 0x803FF000
GP = 0x8021EEB0                # the entry code's $gp (0x801E7908)
DEFAULT_ZIP = ROOT / "tekken3_mame.zip"
COP2_SITES = ROOT / "work" / "arcade" / "decomp_full" / "arcade_e1_full.exe.cop2.txt"
SINE = 0x80175944              # 4096 s16, 4096 = 1.0
# libgte's code, where Ghidra's list misses COP2 register moves (VectorNormal's LZCS / LZCR at
# 0x801F0508 / 0x801F0514): every COP2 encoding there is a site too.
LIBGTE = (0x801EFC00, 0x801F1400)
COP2, LWC2, SWC2 = 0x12, 0x32, 0x3A
UNUSED_ADDRESS = 0x7FFFFFF0    # in kuseg, where the game has nothing


def arcade_cpu(arc: arcade.ArcadeSet) -> psxcpu.PsxCpu:
    psxcpu.RAM_SIZE = ARCADE_RAM
    psxcpu.STACK_TOP = STACK
    header = bytearray(psxcpu.EXE_HEADER)
    header[:8] = b"PS-X EXE"
    struct.pack_into("<I", header, 0x14, GP)
    sites = psxcpu.read_sites(COP2_SITES, psxcpu.TEXT_BASE, psxcpu.TEXT_BASE + len(arc.program))
    sites |= libgte_sites(arc)
    cpu = psxcpu.PsxCpu(bytes(header) + arc.program, exe_cop2=sites)
    # A memory hook, on addresses nothing uses, makes the translated code go through the memory
    # helpers. Without one, loads at 0x801C30B0 in FUN_801C3178 (the AI parameter copy) returned host
    # machine code in Unicorn 2.1 on arm64, and later code crashed with a bus error, differently from
    # run to run; the same memory read correctly through `mem_read` and through any other routine.
    # The cause inside Unicorn's translated fast path is not known.
    cpu.uc.hook_add(UC_HOOK_MEM_WRITE, lambda *_: None, begin=UNUSED_ADDRESS, end=UNUSED_ADDRESS)
    return cpu


def libgte_sites(arc: arcade.ArcadeSet) -> set[int]:
    """The COP2 instructions (moves, commands, LWC2 / SWC2) in LIBGTE."""
    lo, hi = LIBGTE
    words = arc.prog_values(f"<{(hi - lo) // 4}I", lo)
    return {lo + 4 * k for k, w in enumerate(words) if w >> 26 in (COP2, LWC2, SWC2)}


def sine_table(arc: arcade.ArcadeSet) -> list[int]:
    return list(arc.prog_values("<4096h", SINE))
