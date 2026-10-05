#!/usr/bin/env python3
"""A small PlayStation GPU rasteriser for reference pictures of the 2D screens.

It walks an ordering table in the CPU harness's RAM (the packets the game linked this frame) and
draws the GP0 primitives the screens use (flat, Gouraud and textured polygons, lines, tiles and
sprites, draw mode, draw area and offset, VRAM fills) into a 1024 × 512 frame buffer beside the
texture VRAM, with the four semi-transparency modes and the transparent texel 0x0000. Coverage and
texture sampling follow the GPU closely enough to compare layouts with the remake's views; they
are not bit-exact (no dithering, no exact edge rules).

    python3 tools/research/gpu_raster.py <scenario> <frame> [<frame> ...] --out <dir>

runs a flow trace scenario (flow_trace.py) in the harness and saves the 368 × 480 picture of the
2D ordering table after each listed frame (counted as the remake's `--frames`: steps from boot) as <dir>/<scenario>_<frame>.png, with the VRAM built
as the remake builds it (imported/screens: the system textures and the screen's own TIMs).
"""

from __future__ import annotations

import argparse
import logging
import struct
import sys
from pathlib import Path

import numpy as np
from PIL import Image

log = logging.getLogger("gpu_raster")

VRAM_W, VRAM_H = 1024, 512
SCREEN_W, SCREEN_H = 368, 480
OT_BASE = 0x800A96E0             # pointer to the frame's 2D ordering table
OT_ENTRIES = 8
END = 0xFFFFFF
IMPORTED = Path(__file__).resolve().parents[2] / "remake" / "imported" / "screens"
# The TIMs each screen overlay uploads (as the remake's views do), by the overlay in the screen slot.
# libgpu's packet setters, which the harness stubs as library code: their real code is put back so
# that the frame's packets are complete (draw mode, area, offset, texture window, and GetDrawMode's
# helpers SYS_OBJ_162C … SYS_OBJ_182C). They only write packet words.
GPU_SETTERS = (0x8007D490, 0x8007D4C8, 0x8007D548, 0x8007D588, 0x8007D5B0, 0x8007D5CC, 0x8007D5D8,
               0x8007DA78, 0x8007DA94, 0x8007DAB4, 0x8007DB30, 0x8007DB4C, 0x8007DBC8, 0x8007DBE4,
               0x8007DC00, 0x8007DC78)
VRAM_SIZE = 0x80098F60           # s16 width, height (ResetGraph's; SetDrawArea clamps to them)
EXE = Path(__file__).resolve().parents[2] / "work" / "jp_rev1" / "exe.bin"
SCREEN_TIMS = {"select": ["select.tims"], "result": ["result_ta.tims"], "ending": ["staff.tims", "theater.tims"]}


def _s11(v: int) -> int:
    v &= 0x7FF
    return v - 0x800 if v & 0x400 else v


class Gpu:
    def __init__(self, vram: np.ndarray) -> None:
        self.vram = vram                              # (512, 1024) u16: textures and frame buffer
        self.tpage = 0
        self.offset = (0, 0)
        self.area = (0, 0, VRAM_W - 1, VRAM_H - 1)
        self.window = (0, 0, 0, 0)

    # ---- texels and blending ----
    def _texels(self, u: np.ndarray, v: np.ndarray, clut: int, tpage: int) -> np.ndarray:
        px, py = (tpage & 0xF) * 64, ((tpage >> 4) & 1) * 256
        depth = (tpage >> 7) & 3
        mask_x, mask_y, off_x, off_y = self.window
        u = (u & ~(mask_x * 8)) | ((off_x & mask_x) * 8)
        v = (v & ~(mask_y * 8)) | ((off_y & mask_y) * 8)
        u &= 0xFF
        v &= 0xFF
        cx, cy = (clut & 0x3F) * 16, (clut >> 6) & 0x1FF
        if depth == 0:
            w = self.vram[(py + v) & 511, (px + (u >> 2)) & 1023]
            idx = (w >> ((u & 3) * 4)) & 0xF
            return self.vram[cy, (cx + idx) & 1023]
        if depth == 1:
            w = self.vram[(py + v) & 511, (px + (u >> 1)) & 1023]
            idx = (w >> ((u & 1) * 8)) & 0xFF
            return self.vram[cy, (cx + idx) & 1023]
        return self.vram[(py + v) & 511, (px + u) & 1023]

    def _plot(self, xs: np.ndarray, ys: np.ndarray, colour: np.ndarray, semi: bool, tpage: int,
              stp: np.ndarray | None = None) -> None:
        """Writes 15-bit colours (N, 3 channels 0–255) at pixels, blending semi-transparent ones."""
        x0, y0, x1, y1 = self.area
        keep = (xs >= x0) & (xs <= x1) & (ys >= y0) & (ys <= y1) & (xs >= 0) & (xs < VRAM_W) & (ys >= 0) & (ys < VRAM_H)
        xs, ys, colour = xs[keep], ys[keep], colour[keep]
        if stp is not None:
            stp = stp[keep]
        if semi:
            blend = np.ones(len(xs), dtype=bool) if stp is None else stp
            if blend.any():
                b = self._rgb(self.vram[ys[blend], xs[blend]])
                f = colour[blend]
                mode = (tpage >> 5) & 3
                if mode == 0:
                    out = b / 2 + f / 2
                elif mode == 1:
                    out = b + f
                elif mode == 2:
                    out = b - f
                else:
                    out = b + f / 4
                colour = colour.copy()
                colour[blend] = np.clip(out, 0, 255)
        c = np.clip(colour, 0, 255).astype(np.uint16) >> 3
        self.vram[ys, xs] = c[:, 0] | c[:, 1] << 5 | c[:, 2] << 10 | 0x8000

    @staticmethod
    def _rgb(words: np.ndarray) -> np.ndarray:
        return np.stack([(words & 31) << 3, ((words >> 5) & 31) << 3, ((words >> 10) & 31) << 3], axis=-1).astype(np.float64)

    def _shade(self, texel: np.ndarray, colour: np.ndarray, raw: bool) -> tuple[np.ndarray, np.ndarray, np.ndarray]:
        """Texels modulated by the vertex colour; returns colours, the drawn mask and STP bits."""
        drawn = texel != 0
        rgb = self._rgb(texel)
        if not raw:
            rgb = rgb * colour / 128.0
        return rgb, drawn, (texel & 0x8000) != 0

    # ---- primitives ----
    def triangle(self, v, c, uv, clut: int, tpage: int, textured: bool, raw: bool, semi: bool) -> None:
        (x0, y0), (x1, y1), (x2, y2) = v
        area = (x1 - x0) * (y2 - y0) - (x2 - x0) * (y1 - y0)
        if area == 0:
            return
        lo_x, hi_x = max(min(x0, x1, x2), self.area[0]), min(max(x0, x1, x2), self.area[2])
        lo_y, hi_y = max(min(y0, y1, y2), self.area[1]), min(max(y0, y1, y2), self.area[3])
        if lo_x > hi_x or lo_y > hi_y or hi_x - lo_x > 1023 or hi_y - lo_y > 511:
            return
        ys, xs = np.mgrid[lo_y:hi_y + 1, lo_x:hi_x + 1]
        xs, ys = xs.ravel(), ys.ravel()
        w0 = ((x1 - xs) * (y2 - ys) - (x2 - xs) * (y1 - ys)) / area
        w1 = ((x2 - xs) * (y0 - ys) - (x0 - xs) * (y2 - ys)) / area
        w2 = 1.0 - w0 - w1
        # Pixel centres inside, right and bottom edges excluded (close to the GPU's rule).
        inside = (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
        inside &= ~(((w0 == 0) | (w1 == 0) | (w2 == 0)) & ((xs == hi_x) | (ys == hi_y)))
        xs, ys, w0, w1, w2 = xs[inside], ys[inside], w0[inside], w1[inside], w2[inside]
        if not len(xs):
            return
        col = w0[:, None] * c[0] + w1[:, None] * c[1] + w2[:, None] * c[2]
        stp = None
        if textured:
            u = np.floor(w0 * uv[0][0] + w1 * uv[1][0] + w2 * uv[2][0] + 1e-6).astype(np.int64)
            vv = np.floor(w0 * uv[0][1] + w1 * uv[1][1] + w2 * uv[2][1] + 1e-6).astype(np.int64)
            texel = self._texels(u, vv, clut, tpage)
            col, drawn, stp = self._shade(texel, col, raw)
            xs, ys, col, stp = xs[drawn], ys[drawn], col[drawn], stp[drawn]
        self._plot(xs, ys, col, semi, tpage, stp)

    def rect(self, x: int, y: int, w: int, h: int, colour, uv=None, clut: int = 0, raw: bool = False, semi: bool = False) -> None:
        if w <= 0 or h <= 0:
            return
        ys, xs = np.mgrid[y:y + h, x:x + w]
        xs, ys = xs.ravel(), ys.ravel()
        col = np.tile(np.array(colour, dtype=np.float64), (len(xs), 1))
        stp = None
        if uv is not None:
            u = uv[0] + (xs - x)
            v = uv[1] + (ys - y)
            texel = self._texels(u, v, clut, self.tpage)
            col, drawn, stp = self._shade(texel, col, raw)
            xs, ys, col, stp = xs[drawn], ys[drawn], col[drawn], stp[drawn]
        self._plot(xs, ys, col, semi, self.tpage, stp)

    def line(self, a, b, ca, cb, semi: bool) -> None:
        (x0, y0), (x1, y1) = a, b
        n = max(abs(x1 - x0), abs(y1 - y0)) + 1
        t = np.linspace(0.0, 1.0, n)
        xs = np.round(x0 + (x1 - x0) * t).astype(np.int64)
        ys = np.round(y0 + (y1 - y0) * t).astype(np.int64)
        col = (1 - t)[:, None] * np.array(ca, dtype=np.float64) + t[:, None] * np.array(cb, dtype=np.float64)
        self._plot(xs, ys, col, semi, self.tpage)

    # ---- command decoding ----
    def packet(self, words: list[int]) -> None:
        cmd = words[0] >> 24
        if cmd >= 0xE1:
            # A packet of environment commands (SetDrawArea links E3 and E4 together).
            for w in words:
                if w >> 24 >= 0xE1:
                    self._environment(w)
            return
        if cmd == 0x02:
            c = self._colour(words[0])
            x, y = words[1] & 0x3F0, (words[1] >> 16) & 0x1FF
            w, h = ((words[2] & 0x3FF) + 15) & ~15, (words[2] >> 16) & 0x1FF
            cw = (np.clip(np.array(c), 0, 255).astype(np.uint16) >> 3)
            self.vram[y:y + h, x:x + w] = cw[0] | cw[1] << 5 | cw[2] << 10
        elif 0x20 <= cmd < 0x40:
            self._polygon(cmd, words)
        elif 0x40 <= cmd < 0x60:
            self._lines(cmd, words)
        elif 0x60 <= cmd < 0x80:
            self._rect(cmd, words)

    def _environment(self, w: int) -> None:
        cmd = w >> 24
        if cmd == 0xE1:
            self.tpage = w & 0xFFFF
        elif cmd == 0xE2:
            self.window = (w & 31, (w >> 5) & 31, (w >> 10) & 31, (w >> 15) & 31)
        elif cmd == 0xE3:
            self.area = (w & 0x3FF, (w >> 10) & 0x3FF) + self.area[2:]
        elif cmd == 0xE4:
            self.area = self.area[:2] + (w & 0x3FF, (w >> 10) & 0x3FF)
        elif cmd == 0xE5:
            self.offset = (_s11(w), _s11(w >> 11))

    @staticmethod
    def _colour(word: int) -> tuple[int, int, int]:
        return (word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF)

    def _xy(self, word: int) -> tuple[int, int]:
        return (_s11(word) + self.offset[0], _s11(word >> 16) + self.offset[1])

    def _polygon(self, cmd: int, words: list[int]) -> None:
        gouraud, quad, textured, semi, raw = cmd & 0x10, cmd & 8, cmd & 4, cmd & 2, cmd & 1
        n = 4 if quad else 3
        i = 0
        verts, cols, uvs = [], [], []
        clut = tpage = 0
        colour = self._colour(words[0])
        for k in range(n):
            if k == 0 or not gouraud:
                c = colour if k else self._colour(words[i])
                if k == 0:
                    i += 1
            else:
                c = self._colour(words[i])
                i += 1
            cols.append(np.array(c, dtype=np.float64))
            verts.append(self._xy(words[i]))
            i += 1
            if textured:
                w = words[i]
                i += 1
                uvs.append((w & 0xFF, (w >> 8) & 0xFF))
                if k == 0:
                    clut = w >> 16
                elif k == 1:
                    tpage = w >> 16
        if textured:
            self.tpage = tpage
        tris = [(0, 1, 2)] + ([(1, 2, 3)] if quad else [])
        for a, b, c in tris:
            self.triangle([verts[a], verts[b], verts[c]], [cols[a], cols[b], cols[c]],
                          [uvs[a], uvs[b], uvs[c]] if textured else None, clut, tpage if textured else self.tpage,
                          bool(textured), bool(raw), bool(semi))

    def _lines(self, cmd: int, words: list[int]) -> None:
        gouraud, semi = cmd & 0x10, cmd & 2
        c0 = self._colour(words[0])
        a = self._xy(words[1])
        if gouraud:
            c1 = self._colour(words[2])
            b = self._xy(words[3])
        else:
            c1 = c0
            b = self._xy(words[2])
        self.line(a, b, c0, c1, bool(semi))

    def _rect(self, cmd: int, words: list[int]) -> None:
        size, textured, semi, raw = (cmd >> 3) & 3, cmd & 4, cmd & 2, cmd & 1
        colour = self._colour(words[0])
        x, y = self._xy(words[1])
        i = 2
        uv = None
        clut = 0
        if textured:
            uv = (words[2] & 0xFF, (words[2] >> 8) & 0xFF)
            clut = words[2] >> 16
            i = 3
        if size == 0:
            w, h = words[i] & 0x3FF, (words[i] >> 16) & 0x1FF
        else:
            w = h = (1, 8, 16)[size - 1]
        self.rect(x, y, w, h, colour, uv, clut, bool(raw), bool(semi))


def walk(read_u32, ot: int, gpu: Gpu, limit: int = 100_000) -> int:
    """Draws the packets linked from the ordering table entry `ot`; returns the packet count."""
    addr = ot
    count = 0
    for _ in range(limit):
        try:
            head = read_u32(addr)
        except Exception:                       # a link into unmapped memory: the list ends
            log.debug("bad link %#x", addr)
            break
        n = head >> 24
        if n:
            words = [read_u32(addr + 4 + 4 * k) for k in range(n)]
            try:
                gpu.packet(words)
            except IndexError:
                log.debug("short packet at %#x: %s", addr, [hex(w) for w in words])
            count += 1
        nxt = head & 0xFFFFFF
        if nxt == END or nxt == 0:
            break
        addr = 0x80000000 | nxt
    return count


def screen_vram(overlay: str | None) -> np.ndarray:
    words = np.frombuffer((IMPORTED / "vram_system.bin").read_bytes(), dtype="<u2").reshape(VRAM_H, VRAM_W).copy()
    sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "remake_import"))
    from vram import Vram
    v = Vram()
    v.words = words
    for name in SCREEN_TIMS.get(overlay or "", []):
        data = (IMPORTED / name).read_bytes()
        count = struct.unpack_from("<I", data)[0]
        pos = 4
        for _ in range(count):
            n = struct.unpack_from("<I", data, pos)[0]
            v.upload_tim(data[pos + 4:pos + 4 + n])
            pos += 4 + n
    return v.words


def picture(h, vram: np.ndarray) -> np.ndarray:
    """The frame's 2D ordering table drawn over a black frame buffer: RGB (480, 368, 3)."""
    gpu = Gpu(vram)
    gpu.vram[0:SCREEN_H, 0:SCREEN_W] = 0
    gpu.area = (0, 20, SCREEN_W - 1, 467)             # FUN_80029860's display rectangle
    # The table is cleared forwards (entry k links to k + 1) and drawn from entry 0.
    walk(h.u32, h.u32(OT_BASE), gpu)
    rgb = Gpu._rgb(gpu.vram[0:SCREEN_H, 0:SCREEN_W])
    return rgb.astype(np.uint8)


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("scenario")
    parser.add_argument("frames", nargs="+", type=int)
    parser.add_argument("--out", type=Path, required=True)
    args = parser.parse_args()
    import flow_trace as ft
    scenario = next(s for s in ft.SCENARIOS if s.name == args.scenario)
    wanted = set(args.frames)
    args.out.mkdir(parents=True, exist_ok=True)
    import game_harness as gh
    original = gh.GameHarness._frame_buffers
    original_init = gh.GameHarness.__init__
    exe = EXE.read_bytes()

    def init(self, *a, **k) -> None:
        original_init(self, *a, **k)
        for addr in GPU_SETTERS:
            at = addr - 0x80010000 + 0x800
            self.cpu.write(addr, exe[at:at + 8])
        self.cpu.write(VRAM_SIZE, struct.pack("<2h", VRAM_W, VRAM_H))
    gh.GameHarness.__init__ = init

    def frame_buffers(self) -> None:
        # The main loop's ClearOTag of the 2D table, which the harness leaves out: entry k links
        # to k + 1, the last ends the list.
        original(self)
        ot = self.u32(OT_BASE)
        for k in range(OT_ENTRIES):
            self.w32(ot + 4 * k, END if k == OT_ENTRIES - 1 else (ot + 4 * (k + 1)) & 0xFFFFFF)
    gh.GameHarness._frame_buffers = frame_buffers
    for i, (h, _pads) in enumerate(ft.record(scenario), start=1):
        if i in wanted:
            screen = h.slots.get(0x800B9378)
            img = picture(h, screen_vram(screen).copy())
            path = args.out / f"{args.scenario}_{i}.png"
            Image.fromarray(img).save(path)
            log.info("frame %d (state %d sub %d, overlay %s): %s", i, h.state(), h.sub_state(), screen, path)
            wanted.discard(i)
            if not wanted:
                break
    return 0


if __name__ == "__main__":
    sys.exit(main())
