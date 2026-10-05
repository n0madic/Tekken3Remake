#!/usr/bin/env python3
"""Run individual Tekken 3 functions on a MIPS R3000 CPU model with a software GTE.

This is a verification harness, not a console emulator: there is no GPU, SPU,
CD-ROM, interrupt or BIOS. It executes original game code from the EXE (and
optionally one overlay) so that decoded data can be compared against the
game's own routines.

Unicorn provides the MIPS I integer core. Every COP2 instruction (MFC2, CFC2,
MTC2, CTC2, LWC2, SWC2 and GTE commands) is replaced by a NOP in emulated memory
and emulated in a per-address code hook that runs before the NOP. The GTE model
follows the psx-spx "Geometry Transformation Engine" chapter
(https://psx-spx.consoledev.net/geometrytransformationenginegte/).
"""

from __future__ import annotations

import logging
import struct
from pathlib import Path

from unicorn import UC_ARCH_MIPS, UC_HOOK_CODE, UC_HOOK_INTR, UC_MODE_LITTLE_ENDIAN, UC_MODE_MIPS32, Uc
from unicorn.mips_const import (
    UC_MIPS_REG_A0, UC_MIPS_REG_A1, UC_MIPS_REG_A2, UC_MIPS_REG_A3, UC_MIPS_REG_GP,
    UC_MIPS_REG_PC, UC_MIPS_REG_RA, UC_MIPS_REG_SP, UC_MIPS_REG_V0, UC_MIPS_REG_V1,
    UC_MIPS_REG_HI, UC_MIPS_REG_LO, UC_MIPS_REG_ZERO,
)

from make_overlay_exes import overlay_base

log = logging.getLogger("psxcpu")

RAM_SIZE = 0x200000
SCRATCH_BASE = 0x1F800000
SCRATCH_SIZE = 0x1000
TEXT_BASE = 0x80010000
EXE_HEADER = 0x800
RETURN_MAGIC = 0x80000100  # inside the unused exception-vector area
# Beyond the console's 2 MB: a word-copy routine and its source buffer, for code loaded after the
# emulation has run (see PsxCpu._copy_code).
COPY_BASE = 0x00400000
COPY_SIZE = 0x200000
COPY_CODE = 0x80400000
COPY_DATA = 0x80401000
COPY_ROUTINE = (0x8CA80000, 0x24A50004, 0xAC880000, 0x24C6FFFC, 0x1CC0FFFB, 0x24840004, 0x03E00008, 0x00000000)
# lw t0,0(a1); addiu a1,4; sw t0,0(a0); addiu a2,-4; bgtz a2,loop; addiu a0,4; jr ra; nop
STACK_TOP = 0x801FFF00
NOP = 0

GPR = [UC_MIPS_REG_ZERO + i for i in range(32)]


def s16(v: int) -> int:
    v &= 0xFFFF
    return v - 0x10000 if v & 0x8000 else v


def s32(v: int) -> int:
    v &= 0xFFFFFFFF
    return v - 0x100000000 if v & 0x80000000 else v


def _unr_table() -> list[int]:
    return [max(0, (0x40000 // (i + 0x100) + 1) // 2 - 0x101) for i in range(0x101)]


UNR = _unr_table()


class GTE:
    """Software model of the PlayStation Geometry Transformation Engine."""

    def __init__(self) -> None:
        self.d = [0] * 32  # data registers, stored as raw 32-bit values
        self.c = [0] * 32  # control registers

    # ---- register file -------------------------------------------------
    def read_data(self, r: int) -> int:
        d = self.d
        if r in (1, 3, 5, 8, 9, 10, 11):
            return s16(d[r]) & 0xFFFFFFFF
        if r in (7, 16, 17, 18, 19):
            return d[r] & 0xFFFF
        if r == 15:
            return d[14]
        if r in (28, 29):
            def c5(v: int) -> int:
                return min(0x1F, max(0, s16(v) >> 7))
            return c5(d[9]) | c5(d[10]) << 5 | c5(d[11]) << 10
        return d[r] & 0xFFFFFFFF

    def write_data(self, r: int, v: int) -> None:
        v &= 0xFFFFFFFF
        d = self.d
        if r == 15:
            d[12], d[13], d[14] = d[13], d[14], v
            return
        if r == 28:
            d[28] = v & 0x7FFF
            d[9] = (v & 0x1F) << 7
            d[10] = ((v >> 5) & 0x1F) << 7
            d[11] = ((v >> 10) & 0x1F) << 7
            return
        if r == 29:
            return
        if r == 30:
            d[30] = v
            x = s32(v)
            if x < 0:
                x = ~x & 0xFFFFFFFF
            n = 32 - x.bit_length() if x else 32
            d[31] = n
            return
        if r == 31:
            return
        d[r] = v

    def read_ctrl(self, r: int) -> int:
        c = self.c
        if r in (4, 12, 20, 26, 27, 29, 30):
            return s16(c[r]) & 0xFFFFFFFF
        if r == 31:
            f = c[31] & 0x7FFFF000
            if f & 0x7F87E000:
                f |= 0x80000000
            return f
        return c[r] & 0xFFFFFFFF

    def write_ctrl(self, r: int, v: int) -> None:
        self.c[r] = v & 0xFFFFFFFF
        if r == 31:
            self.c[31] = v & 0x7FFFF000

    # ---- helpers ------------------------------------------------------
    def _v(self, i: int) -> tuple[int, int, int]:
        d = self.d
        if i == 3:
            return s16(d[9]), s16(d[10]), s16(d[11])
        return s16(d[i * 2]), s16(d[i * 2] >> 16), s16(d[i * 2 + 1])

    def _mat(self, base: int) -> list[list[int]]:
        c = self.c
        a, b, e, f, g = c[base], c[base + 1], c[base + 2], c[base + 3], c[base + 4]
        return [
            [s16(a), s16(a >> 16), s16(b)],
            [s16(b >> 16), s16(e), s16(e >> 16)],
            [s16(f), s16(f >> 16), s16(g)],
        ]

    def _flag(self, bit: int) -> None:
        self.c[31] |= 1 << bit

    def _mac(self, i: int, value: int) -> int:
        # 44-bit overflow flags for MAC1..3
        if value > 0x7FFFFFFFFFF:
            self._flag(31 - i)
        elif value < -0x80000000000:
            self._flag(28 - i)
        return value

    def _set_mac(self, i: int, value: int, shift: int) -> int:
        self._mac(i, value)
        v = value >> shift
        self.d[24 + i] = v & 0xFFFFFFFF
        return s32(v)

    def _ir(self, i: int, value: int, lm: bool) -> int:
        lo = 0 if lm else -0x8000
        if value > 0x7FFF:
            value = 0x7FFF
            self._flag(25 - i)
        elif value < lo:
            value = lo
            self._flag(25 - i)
        self.d[8 + i] = value & 0xFFFF
        return value

    def _mac0(self, value: int) -> int:
        if value > 0x7FFFFFFF:
            self._flag(16)
        elif value < -0x80000000:
            self._flag(15)
        self.d[24] = value & 0xFFFFFFFF
        return value

    def _push_sz(self, value: int) -> None:
        if value > 0xFFFF:
            value = 0xFFFF
            self._flag(18)
        elif value < 0:
            value = 0
            self._flag(18)
        d = self.d
        d[16], d[17], d[18], d[19] = d[17], d[18], d[19], value

    def _push_sxy(self, x: int, y: int) -> None:
        if x > 0x3FF:
            x = 0x3FF
            self._flag(14)
        elif x < -0x400:
            x = -0x400
            self._flag(14)
        if y > 0x3FF:
            y = 0x3FF
            self._flag(13)
        elif y < -0x400:
            y = -0x400
            self._flag(13)
        d = self.d
        d[12], d[13], d[14] = d[13], d[14], (x & 0xFFFF) | (y & 0xFFFF) << 16

    def _push_color(self) -> None:
        d = self.d
        out = d[6] & 0xFF000000
        for i in range(3):
            v = s32(d[25 + i]) >> 4
            if v < 0:
                v = 0
                self._flag(21 - i)
            elif v > 0xFF:
                v = 0xFF
                self._flag(21 - i)
            out |= v << (8 * i)
        d[20], d[21], d[22] = d[21], d[22], out

    def _divide(self, h: int, sz3: int) -> int:
        if h < sz3 * 2:
            z = 16 - sz3.bit_length()
            n = h << z
            dd = sz3 << z
            u = UNR[(dd - 0x7FC0) >> 7] + 0x101
            dd = (0x2000080 - dd * u) >> 8
            dd = (0x0000080 + dd * u) >> 8
            return min(0x1FFFF, (n * dd + 0x8000) >> 16)
        self._flag(17)
        return 0x1FFFF

    # ---- commands ------------------------------------------------------
    def _rtp(self, vi: int, sf: int, lm: bool, last: bool) -> None:
        c = self.c
        vx, vy, vz = self._v(vi)
        m = self._mat(0)
        tr = (s32(c[5]), s32(c[6]), s32(c[7]))
        shift = 12 * sf
        macs = []
        for i in range(3):
            macs.append(self._set_mac(i + 1, (tr[i] << 12) + m[i][0] * vx + m[i][1] * vy + m[i][2] * vz, shift))
        self._ir(1, macs[0], lm)
        self._ir(2, macs[1], lm)
        # IR3 saturation flag uses the unshifted value when sf == 0
        mac3 = macs[2]
        ir3 = max(-0x8000 if not lm else 0, min(0x7FFF, mac3))
        flag_src = mac3 >> 12 if sf == 0 else mac3
        if flag_src > 0x7FFF or flag_src < -0x8000:
            self._flag(22)
        self.d[11] = ir3 & 0xFFFF
        sz = (mac3 >> (12 - shift)) if sf == 0 else mac3
        if sf == 0:
            sz = mac3 >> 12
        self._push_sz(sz)
        h = c[26] & 0xFFFF
        div = self._divide(h, self.d[19] & 0xFFFF)
        ofx, ofy = s32(c[24]), s32(c[25])
        sx = self._mac0(div * s16(self.d[9]) + ofx) >> 16
        sy = self._mac0(div * s16(self.d[10]) + ofy) >> 16
        self._push_sxy(sx, sy)
        if last:
            mac0 = self._mac0(div * s16(c[27]) + s32(c[28]))
            ir0 = mac0 >> 12
            if ir0 > 0x1000:
                ir0 = 0x1000
                self._flag(12)
            elif ir0 < 0:
                ir0 = 0
                self._flag(12)
            self.d[8] = ir0 & 0xFFFF

    def _mvmva_core(self, m: list[list[int]], v: tuple[int, int, int], cv: tuple[int, int, int], sf: int, lm: bool) -> None:
        shift = 12 * sf
        for i in range(3):
            mac = self._set_mac(i + 1, (cv[i] << 12) + m[i][0] * v[0] + m[i][1] * v[1] + m[i][2] * v[2], shift)
            self._ir(i + 1, mac, lm)

    def _ir_vec(self) -> tuple[int, int, int]:
        return s16(self.d[9]), s16(self.d[10]), s16(self.d[11])

    def _bk(self) -> tuple[int, int, int]:
        return s32(self.c[13]), s32(self.c[14]), s32(self.c[15])

    def _fc(self) -> tuple[int, int, int]:
        return s32(self.c[21]), s32(self.c[22]), s32(self.c[23])

    def _rgbc(self, reg: int = 6) -> tuple[int, int, int]:
        v = self.d[reg]
        return v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF

    def _color_raw(self, rgb: tuple[int, int, int]) -> list[int]:
        ir = self._ir_vec()
        return [(rgb[i] * ir[i]) << 4 for i in range(3)]

    def _finish(self, raw: list[int], sf: int, lm: bool) -> None:
        for i in range(3):
            self._ir(i + 1, self._set_mac(i + 1, raw[i], 12 * sf), lm)

    def _interp(self, raw: list[int], sf: int, lm: bool) -> None:
        """Depth-cue interpolation of an unshifted MAC vector towards the far color."""
        shift = 12 * sf
        fc = self._fc()
        for i in range(3):
            self._ir(i + 1, self._set_mac(i + 1, (fc[i] << 12) - raw[i], shift), False)
        ir0 = s16(self.d[8])
        ir = self._ir_vec()
        self._finish([ir[i] * ir0 + raw[i] for i in range(3)], sf, lm)

    def _light(self, vi: int, sf: int, lm: bool) -> None:
        self._mvmva_core(self._mat(8), self._v(vi), (0, 0, 0), sf, lm)
        self._mvmva_core(self._mat(16), self._ir_vec(), self._bk(), sf, lm)

    def command(self, op: int) -> None:
        self.c[31] = 0
        sf = (op >> 19) & 1
        lm = bool((op >> 10) & 1)
        fn = op & 0x3F
        shift = 12 * sf
        d = self.d
        if fn == 0x01:
            self._rtp(0, sf, lm, True)
        elif fn == 0x30:
            for i in range(3):
                self._rtp(i, sf, lm, i == 2)
        elif fn == 0x06:
            xy = [(s16(d[12 + i]), s16(d[12 + i] >> 16)) for i in range(3)]
            (x0, y0), (x1, y1), (x2, y2) = xy
            self._mac0(x0 * y1 + x1 * y2 + x2 * y0 - x0 * y2 - x1 * y0 - x2 * y1)
        elif fn == 0x0C:
            m = self._mat(0)
            d1, d2, d3 = m[0][0], m[1][1], m[2][2]
            i1, i2, i3 = self._ir_vec()
            for i, val in enumerate((i3 * d2 - i2 * d3, i1 * d3 - i3 * d1, i2 * d1 - i1 * d2)):
                self._ir(i + 1, self._set_mac(i + 1, val, shift), lm)
        elif fn == 0x12:
            mx = (op >> 17) & 3
            vi = (op >> 15) & 3
            cvi = (op >> 13) & 3
            m = self._mat((0, 8, 16, 0)[mx]) if mx != 3 else [[0] * 3 for _ in range(3)]
            cv = (tuple(s32(self.c[5 + i]) for i in range(3)), self._bk(), self._fc(), (0, 0, 0))[cvi]
            if cvi == 2:
                log.debug("MVMVA with FC translation (hardware bug not modelled)")
            self._mvmva_core(m, self._v(vi), cv, sf, lm)
        elif fn == 0x28:
            ir = self._ir_vec()
            for i in range(3):
                self._ir(i + 1, self._set_mac(i + 1, ir[i] * ir[i], shift), lm)
        elif fn == 0x2D:
            zsf3 = s16(self.c[29])
            mac0 = self._mac0(zsf3 * ((d[17] & 0xFFFF) + (d[18] & 0xFFFF) + (d[19] & 0xFFFF)))
            self._otz(mac0 >> 12)
        elif fn == 0x2E:
            zsf4 = s16(self.c[30])
            mac0 = self._mac0(zsf4 * sum(d[16 + i] & 0xFFFF for i in range(4)))
            self._otz(mac0 >> 12)
        elif fn == 0x3D:
            ir0 = s16(d[8])
            ir = self._ir_vec()
            for i in range(3):
                self._ir(i + 1, self._set_mac(i + 1, ir0 * ir[i], shift), lm)
            self._push_color()
        elif fn == 0x3E:
            ir0 = s16(d[8])
            ir = self._ir_vec()
            for i in range(3):
                self._ir(i + 1, self._set_mac(i + 1, (s32(d[25 + i]) << shift) + ir0 * ir[i], shift), lm)
            self._push_color()
        elif fn in (0x1E, 0x20):
            for vi in range(3 if fn == 0x20 else 1):
                self._light(vi, sf, lm)
                self._push_color()
        elif fn in (0x1B, 0x3F):
            for vi in range(3 if fn == 0x3F else 1):
                self._light(vi, sf, lm)
                self._finish(self._color_raw(self._rgbc()), sf, lm)
                self._push_color()
        elif fn in (0x13, 0x16):
            for vi in range(3 if fn == 0x16 else 1):
                self._light(vi, sf, lm)
                self._interp(self._color_raw(self._rgbc()), sf, lm)
                self._push_color()
        elif fn == 0x1C:
            self._mvmva_core(self._mat(16), self._ir_vec(), self._bk(), sf, lm)
            self._finish(self._color_raw(self._rgbc()), sf, lm)
            self._push_color()
        elif fn == 0x14:
            self._mvmva_core(self._mat(16), self._ir_vec(), self._bk(), sf, lm)
            self._interp(self._color_raw(self._rgbc()), sf, lm)
            self._push_color()
        elif fn == 0x10:
            self._interp([v << 16 for v in self._rgbc()], sf, lm)
            self._push_color()
        elif fn == 0x2A:
            for _ in range(3):
                self._interp([v << 16 for v in self._rgbc(20)], sf, lm)
                self._push_color()
        elif fn == 0x11:
            self._interp([v << 12 for v in self._ir_vec()], sf, lm)
            self._push_color()
        elif fn == 0x29:
            self._interp(self._color_raw(self._rgbc()), sf, lm)
            self._push_color()
        else:
            raise NotImplementedError(f"GTE command {op:#x}")

    def _otz(self, value: int) -> None:
        if value > 0xFFFF:
            value = 0xFFFF
            self._flag(18)
        elif value < 0:
            value = 0
            self._flag(18)
        self.d[7] = value


class PsxCpu:
    """MIPS I integer core plus software GTE, loaded with one executable image."""

    def __init__(self, exe: bytes, overlay: bytes | None = None,
                 exe_cop2: set[int] | None = None, overlay_cop2: set[int] | None = None,
                 overlay_addr: int | None = None) -> None:
        self.uc = Uc(UC_ARCH_MIPS, UC_MODE_MIPS32 | UC_MODE_LITTLE_ENDIAN)
        self.uc.mem_map(0, RAM_SIZE)
        self.uc.mem_map(SCRATCH_BASE, SCRATCH_SIZE)
        self.gte = GTE()
        self.cop2_sites: dict[int, int] = {}
        self.stubs: dict[int, object] = {}
        self.lazy_cop2 = 0
        self.fault: tuple[int, int, int] | None = None
        self._stop_pending = False
        self._deferred: list = []
        self._cop2_hooks: dict[int, int] = {}
        # Zero-divisor fixes by the address after the `div` (rs, rt, unsigned), None once the code
        # there was replaced; one hook per address, kept for good (see drop_cop2).
        self.divides: dict[int, tuple[int, int, bool] | None] = {}
        self._divide_hooks: dict[int, int] = {}
        self._stub_hooks: dict[int, int] = {}
        self._running = False
        self._ran = False
        self._copy_ready = False
        self.uc.hook_add(UC_HOOK_INTR, self._intr_hook)
        header = exe[:EXE_HEADER]
        if header[:8] != b"PS-X EXE":
            raise ValueError("not a PS-X EXE")
        self.gp = struct.unpack_from("<I", header, 0x14)[0]
        self.load(TEXT_BASE, exe[EXE_HEADER:], exe_cop2)
        if overlay is not None:
            if overlay_addr is None:
                raise ValueError("overlay_addr is required with an overlay")
            self.load(overlay_addr, overlay, overlay_cop2)

    # ---- memory ------------------------------------------------------
    @staticmethod
    def phys(addr: int) -> int:
        if 0x80000000 <= addr < 0xA0000000:
            return addr & 0x1FFFFFFF
        if 0xA0000000 <= addr < 0xC0000000:
            return addr & 0x1FFFFFFF
        return addr

    def write(self, addr: int, data: bytes) -> None:
        self.uc.mem_write(self.phys(addr), bytes(data))

    def read(self, addr: int, size: int) -> bytes:
        return bytes(self.uc.mem_read(self.phys(addr), size))

    def u32(self, addr: int) -> int:
        return struct.unpack("<I", self.read(addr, 4))[0]

    def load(self, addr: int, code: bytes, cop2_sites: set[int] | None = None) -> None:
        """Copy code/data into RAM and neutralize the given COP2 instruction sites.

        `cop2_sites` should come from a disassembler listing (Ghidra), because data
        words can carry COP2-looking opcodes. COP2 instructions that are executed
        but missing from the list are handled lazily by the exception hook.
        """
        buf = bytearray(code)
        count = 0
        for site in sorted(cop2_sites or ()):
            off = site - addr
            if not 0 <= off <= len(buf) - 4:
                continue
            word = struct.unpack_from("<I", buf, off)[0]
            if word >> 26 not in (0x12, 0x32, 0x3A):
                raise ValueError(f"listed COP2 site {site:#x} holds {word:#010x}")
            self._register_cop2(site, word)
            struct.pack_into("<I", buf, off, NOP)
            count += 1
        if self._ran:
            self._copy_code(addr, bytes(buf))
        else:
            self.write(addr, buf)
        log.debug("loaded %d bytes at %#x, %d COP2 sites", len(code), addr, count)

    def _copy_code(self, addr: int, data: bytes) -> None:
        """Writes code over memory the emulation may have translated: the guest itself copies it
        (a word loop), so its stores invalidate the stale translated blocks as self-modifying code
        does. Host writes (`mem_write`) leave them in place, and flushing the translation cache
        instead (`ctl_flush_tb`, `ctl_remove_cache`) crashed Unicorn later. Must run outside the
        emulation (see `defer`)."""
        if self._running:
            raise RuntimeError("code can only be loaded outside the emulation")
        uc = self.uc
        if not self._copy_ready:
            uc.mem_map(COPY_BASE, COPY_SIZE)
            self.write(COPY_CODE, struct.pack(f"<{len(COPY_ROUTINE)}I", *COPY_ROUTINE))
            self._copy_ready = True
        if len(data) > COPY_SIZE - (COPY_DATA - COPY_CODE):
            raise ValueError(f"{len(data)} bytes do not fit the copy buffer")
        padded = data + bytes(-len(data) % 4)
        self.write(COPY_DATA, padded)
        saved = uc.context_save()
        uc.reg_write(UC_MIPS_REG_A0, addr)
        uc.reg_write(UC_MIPS_REG_A1, COPY_DATA)
        uc.reg_write(UC_MIPS_REG_A2, len(padded))
        uc.reg_write(UC_MIPS_REG_RA, RETURN_MAGIC)
        uc.emu_start(COPY_CODE, RETURN_MAGIC)
        uc.context_restore(saved)

    def defer(self, fn) -> None:
        """Runs `fn` once the current stub returns, outside the emulation (loading code or adding
        hooks from inside a hook corrupts Unicorn's translation state)."""
        self._deferred.append(fn)
        self._stop_pending = True

    def _register_cop2(self, site: int, word: int) -> None:
        if site not in self._cop2_hooks:
            self._cop2_hooks[site] = self.uc.hook_add(UC_HOOK_CODE, self._cop2_hook, begin=site, end=site)
        self.cop2_sites[site] = word

    def _patch_cop2(self, site: int, word: int) -> None:
        """A lazily found COP2 site: its hook, and a NOP over it stored by the guest (see
        `_copy_code`)."""
        self._register_cop2(site, word)
        self._copy_code(site, struct.pack("<I", NOP))

    def drop_cop2(self, site: int) -> None:
        """Forgets a COP2 site (code replaced by an overlay). Its hook stays and does nothing:
        translated blocks keep pointers to their hooks, so deleting one crashed Unicorn when a
        block compiled with it ran again."""
        if site in self.cop2_sites:
            self.cop2_sites[site] = None

    def _intr_hook(self, uc: Uc, intno: int, _user) -> None:
        pc = uc.reg_read(UC_MIPS_REG_PC)
        word = struct.unpack("<I", self.read(pc, 4))[0]
        if word >> 26 in (0x12, 0x32, 0x3A):
            # Unlisted COP2 instruction: emulate it now and stop; its hook and the NOP over it are
            # put in place outside the emulation (adding a hook or writing code from inside a hook
            # corrupts Unicorn's translation state).
            self.cop2_sites[pc] = word
            self._cop2_hook(uc, pc, 4, None)
            uc.reg_write(UC_MIPS_REG_PC, pc + 4)
            self.lazy_cop2 += 1
            self.defer(lambda: self._patch_cop2(pc, word))
            uc.emu_stop()
            return
        uc.emu_stop()
        self.fault = (intno, pc, word)

    # ---- COP2 ----------------------------------------------------------
    def _cop2_hook(self, uc: Uc, address: int, size: int, _user) -> None:
        site = address
        word = self.cop2_sites.get(site)
        if word is None:
            return
        op = word >> 26
        rt = (word >> 16) & 31
        rd = (word >> 11) & 31
        if op == 0x12:
            if word & (1 << 25):
                self.gte.command(word & 0x1FFFFFF)
                return
            rs = (word >> 21) & 31
            if rs == 0:
                self._set_gpr(rt, self.gte.read_data(rd))
            elif rs == 2:
                self._set_gpr(rt, self.gte.read_ctrl(rd))
            elif rs == 4:
                self.gte.write_data(rd, uc.reg_read(GPR[rt]))
            elif rs == 6:
                self.gte.write_ctrl(rd, uc.reg_read(GPR[rt]))
            else:
                raise NotImplementedError(f"COP2 rs={rs} at {site:#x}")
            return
        base = (word >> 21) & 31
        offset = s16(word)
        ea = (uc.reg_read(GPR[base]) + offset) & 0xFFFFFFFF
        if op == 0x32:
            self.gte.write_data(rt, struct.unpack("<I", self.read(ea, 4))[0])
        else:
            self.write(ea, struct.pack("<I", self.gte.read_data(rt)))

    def _set_gpr(self, r: int, v: int) -> None:
        if r:
            self.uc.reg_write(GPR[r], v & 0xFFFFFFFF)

    # ---- division --------------------------------------------------------
    def r3000_divide(self, site: int) -> None:
        """Give the `div`/`divu` at `site` the R3000 result for a zero divisor (Unicorn follows QEMU):
        LO = -1 for a non-negative dividend and +1 for a negative one (`divu`: all ones), HI = dividend.
        The fix runs just before the next instruction, which cannot have changed the operands yet."""
        word = self.u32(site)
        if word >> 26 != 0 or word & 0x3F not in (0x1A, 0x1B):
            raise ValueError(f"no div at {site:#x}")
        at = site + 4
        self.divides[at] = (word >> 21 & 0x1F, word >> 16 & 0x1F, word & 0x3F == 0x1B)
        if at not in self._divide_hooks:
            self._divide_hooks[at] = self.uc.hook_add(UC_HOOK_CODE, self._divide_hook, begin=at, end=at)

    def _divide_hook(self, uc: Uc, address: int, size: int, _user) -> None:
        fix = self.divides.get(address)
        if fix is None:
            return
        rs, rt, unsigned = fix
        if uc.reg_read(GPR[rt]) != 0:
            return
        dividend = uc.reg_read(GPR[rs]) & 0xFFFFFFFF
        if unsigned:
            lo = 0xFFFFFFFF
        else:
            lo = 1 if dividend & 0x80000000 else 0xFFFFFFFF
        uc.reg_write(UC_MIPS_REG_LO, lo)
        uc.reg_write(UC_MIPS_REG_HI, dividend)

    def drop_divides(self, lo: int, hi: int) -> None:
        """Forgets the zero-divisor fixes of the code in [lo, hi) (replaced by an overlay). Their
        hooks stay and do nothing: deleting a hook crashes Unicorn when a block translated with it
        runs again."""
        for at in range(lo + 4, hi + 4, 4):
            if at in self.divides:
                self.divides[at] = None

    def r3000_divide_range(self, lo: int, hi: int) -> None:
        """r3000_divide for every `div`/`divu` encoding in [lo, hi)."""
        for site in range(lo, hi, 4):
            word = self.u32(site)
            if word >> 26 == 0 and word & 0xFFC0 == 0 and word & 0x3F in (0x1A, 0x1B):
                self.r3000_divide(site)

    # ---- calls -----------------------------------------------------------
    def stub(self, addr: int, func) -> None:
        """Replace a function with a Python callable receiving (cpu, a0..a3); returns v0."""
        self.stubs[addr] = func
        if addr not in self._stub_hooks:
            self._stub_hooks[addr] = self.uc.hook_add(UC_HOOK_CODE, self._stub_hook, begin=addr, end=addr)

    def _stub_hook(self, uc: Uc, address: int, size: int, _user) -> None:
        site = address
        func = self.stubs.get(site)
        if func is None:
            return
        args = [uc.reg_read(r) for r in (UC_MIPS_REG_A0, UC_MIPS_REG_A1, UC_MIPS_REG_A2, UC_MIPS_REG_A3)]
        result = func(self, *args)
        uc.reg_write(UC_MIPS_REG_V0, (result or 0) & 0xFFFFFFFF)
        uc.reg_write(UC_MIPS_REG_PC, uc.reg_read(UC_MIPS_REG_RA))
        if self._stop_pending:
            uc.emu_stop()

    def run(self, pc: int, max_instructions: int = 50_000_000) -> None:
        """Emulates from `pc` until RETURN_MAGIC, a fault or a stop by an outside hook, running the
        deferred work (see `defer`) whenever the emulation stopped for it and resuming. Callers
        driving the emulation themselves use this instead of `emu_start`, which would end at the
        first such stop."""
        uc = self.uc
        while True:
            self._running = True
            self._ran = True
            try:
                uc.emu_start(pc, RETURN_MAGIC, count=max_instructions)
            finally:
                self._running = False
            if not self._stop_pending:
                return
            self._stop_pending = False
            deferred, self._deferred = self._deferred, []
            for fn in deferred:
                fn()
            pc = uc.reg_read(UC_MIPS_REG_PC)
            if pc == RETURN_MAGIC or self.fault:
                return

    def call(self, addr: int, *args: int, max_instructions: int = 50_000_000) -> int:
        uc = self.uc
        sp = STACK_TOP - 0x100
        regs = (UC_MIPS_REG_A0, UC_MIPS_REG_A1, UC_MIPS_REG_A2, UC_MIPS_REG_A3)
        for i, value in enumerate(args):
            if i < 4:
                uc.reg_write(regs[i], value & 0xFFFFFFFF)
            else:
                self.write(sp + 4 * i, struct.pack("<I", value & 0xFFFFFFFF))
        uc.reg_write(UC_MIPS_REG_SP, sp)
        uc.reg_write(UC_MIPS_REG_GP, self.gp)
        uc.reg_write(UC_MIPS_REG_RA, RETURN_MAGIC)
        self.run(addr, max_instructions)
        if self.fault:
            intno, pc, word = self.fault
            self.fault = None
            raise RuntimeError(f"CPU exception {intno} at {pc:#x} (word {word:#010x})")
        if uc.reg_read(UC_MIPS_REG_PC) != RETURN_MAGIC:
            raise RuntimeError(f"call {addr:#x} stopped at {uc.reg_read(UC_MIPS_REG_PC):#x}")
        return uc.reg_read(UC_MIPS_REG_V0) | uc.reg_read(UC_MIPS_REG_V1) << 32


def read_sites(path: Path, lo: int, hi: int) -> set[int]:
    if not path.exists():
        log.warning("no COP2 site list %s; relying on lazy handling", path)
        return set()
    sites = {int(line, 16) for line in path.read_text().split()}
    return {a for a in sites if lo <= a < hi}


def load_release(release: str = "jp_rev1", overlay: str | None = None) -> PsxCpu:
    top = Path(__file__).resolve().parents[2] / "work"
    root = top / release
    exe = (root / "exe.bin").read_bytes()
    decomp = top / "decomp"
    ovl = None
    ovl_sites: set[int] | None = None
    if overlay:
        matches = list((root / "bns").glob(f"*_{overlay}.ovl"))
        if len(matches) != 1:
            raise FileNotFoundError(f"overlay {overlay!r} not found in {root}")
        ovl = matches[0].read_bytes()
        ovl_addr = overlay_base(overlay, release)
        ovl_sites = read_sites(decomp / f"{release}_{overlay}.exe.cop2.txt", ovl_addr, 0x80200000)
        exe_sites = read_sites(decomp / f"{release}_{overlay}.exe.cop2.txt", TEXT_BASE, ovl_addr)
    else:
        ovl_addr = None
        exe_sites = read_sites(decomp / "SLPS_013.00.cop2.txt", TEXT_BASE, 0x80200000)
    return PsxCpu(exe, ovl, exe_sites, ovl_sites, ovl_addr)
