#!/usr/bin/env python3
"""Compare projection_sim.py with the game's projection helpers (Japan Rev.1) in the CPU harness.

The harness's GTE state is randomised and copied into the port's GTE model; each case compares
all of RAM, the return value and the GTE registers afterwards.

Usage: python3 tools/research/verify_projection_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import copy
import logging
import random
import struct

import projection_sim as pj
import verify_draw_sim as vd
import verify_menu_sim as vm

log = logging.getLogger("verify_projection_sim")
BUF = 0x801F8300


def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


def random_matrix(rng) -> bytes:
    rows = []
    for r in range(3):
        if rng.random() < 0.3:
            rows.append([0x1000 if k == r else 0 for k in range(3)])
        else:
            rows.append([rng.choice([0, 0x1000, -0x1000, rng.randrange(-0x1000, 0x1001)]) for _ in range(3)])
    flat = [v for row in rows for v in row]
    t = [rng.randrange(-0x8000, 0x8000), rng.randrange(-0x4000, 0x4000), rng.randrange(0x400, 0x8000)]
    return struct.pack("<9hh3i", *flat, 0, *t)


def random_gte(cpu, rng) -> None:
    g = cpu.gte
    for r in range(32):
        g.write_ctrl(r, rng.getrandbits(32))
    g.write_ctrl(24, rng.choice([0xB80000, 0xA00000, rng.getrandbits(24)]))
    g.write_ctrl(25, rng.choice([0x780000, 0xF00000, rng.getrandbits(24)]))
    g.write_ctrl(26, rng.choice([0x200, 0x2A0, rng.randrange(0x40, 0x800)]))
    for r in range(32):
        g.write_data(r, rng.getrandbits(32))


def gte_regs(g) -> tuple:
    return tuple(g.read_ctrl(r) for r in range(32)), tuple(g.read_data(r) for r in range(32))


def run(chk, name, cpu, game, port, show=""):
    """vd.run_gpu plus a comparison of the GTE registers."""
    before = copy.deepcopy(cpu.gte)
    g2 = copy.deepcopy(before)
    vd.run_gpu(chk, name, cpu, game, lambda r: port(r, g2), show)
    if gte_regs(cpu.gte) != gte_regs(g2):
        chk[name].bad += 1
        log.info("  %s GTE mismatch %s", name, show)


def case(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    random_gte(cpu, rng)
    cpu.write(pj.VIEW, random_matrix(rng))
    cpu.write(BUF, random_matrix(rng))
    x, y, z = (rng.choice([0, rng.randrange(-0x40000, 0x40000)]) for _ in range(3))
    out = BUF + 0x40
    run(chk, "ApplyMatrixLV", cpu,
        lambda c: c.call(0x80081C7C, BUF, x, y, z, out, out + 4, out + 8) and None,
        lambda r, g: [r.put(out + 4 * i, "i", v) for i, v in enumerate(pj.apply_matrix_lv(r, BUF, x, y, z))] and None)
    run(chk, "ViewPoint", cpu, lambda c: c.call(0x8004B05C, x, y, z) and None,
        lambda r, g: pj.view_point(r, g, x, y, z))
    v = BUF + 0x60
    cpu.write(v, struct.pack("<3hh", *(rng.randrange(-0x800, 0x800) for _ in range(3)), 0))
    run(chk, "RotTransPers", cpu, lambda c: c.call(0x80036D28, v, v + 8) & 0xFFFFFFFF,
        lambda r, g: pj.rot_trans_pers(r, g, v, v + 8))
    lv = BUF + 0x80
    cpu.write(lv, struct.pack("<3i", *(rng.choice([0, rng.randrange(-0x800000, 0x800000)]) for _ in range(3))))
    run(chk, "ApplyMatrixLV_GTE", cpu, lambda c: c.call(0x8008229C, BUF, lv, lv + 0x10) and None,
        lambda r, g: pj.apply_matrix_lv_gte(r, g, BUF, lv, lv + 0x10))
    ang = BUF + 0xA0
    cpu.write(ang, struct.pack("<4h", *(rng.choice([0, rng.randrange(-0x8000, 0x8000)]) for _ in range(4))))
    run(chk, "RotMatrixAngles", cpu, lambda c: c.call(0x8003A6E4, ang, BUF + 0xC0) and None,
        lambda r, g: pj.rot_matrix_angles(r, g, ang, BUF + 0xC0))
    run(chk, "SetMulRotMatrix", cpu, lambda c: c.call(0x800825BC, BUF) and None,
        lambda r, g: pj.set_mul_rot_matrix(r, g, BUF))
    run(chk, "LocalMatrix", cpu, lambda c: c.call(0x80037AB0, pj.VIEW, BUF) and None,
        lambda r, g: pj.local_matrix(r, g, pj.VIEW, BUF))
    run(chk, "RotTransPersPsyQ", cpu, lambda c: c.call(0x80082B7C, v, v + 8, v + 12, v + 16) & 0xFFFFFFFF,
        lambda r, g: pj.rot_trans_pers_psyq(r, g, v, v + 8, v + 12, v + 16))


def case_library(cpu, rng, chk) -> None:
    """The PsyQ matrix and lighting library the Tekken Ball renderer uses."""
    vm.common(cpu, rng)
    random_gte(cpu, rng)
    a, b, out = BUF, BUF + 0x20, BUF + 0x40
    cpu.write(a, random_matrix(rng))
    cpu.write(b, random_matrix(rng))
    run(chk, "MulMatrix0", cpu, lambda c: c.call(0x8008218C, a, b, out) and None,
        lambda r, g: pj.mul_matrix0(r, g, a, b, out))
    run(chk, "MulMatrix", cpu, lambda c: c.call(0x800826AC, a, b) and None, lambda r, g: pj.mul_matrix(r, g, a, b))
    run(chk, "MulMatrix2", cpu, lambda c: c.call(0x800827BC, a, b) and None, lambda r, g: pj.mul_matrix2(r, g, a, b))
    run(chk, "TransposeMatrix", cpu, lambda c: c.call(0x80082C8C, a, out) and None,
        lambda r, g: pj.transpose_matrix(r, a, out))
    sv = BUF + 0x60
    cpu.write(sv, struct.pack("<3i", *(rng.choice([0x1000, rng.randrange(-0x20000, 0x20000)]) for _ in range(3))))
    run(chk, "ScaleMatrix", cpu, lambda c: c.call(0x8008291C, a, sv) and None, lambda r, g: pj.scale_matrix(r, a, sv))
    run(chk, "ReadLightMatrix", cpu, lambda c: c.call(0x8008242C, out) and None,
        lambda r, g: pj.read_light_matrix(r, g, out))
    run(chk, "SetLightMatrix", cpu, lambda c: c.call(0x80082A8C, b) and None, lambda r, g: pj.set_light_matrix(r, g, b))
    col = [rng.randrange(256) for _ in range(3)]
    run(chk, "SetBackColor", cpu, lambda c: c.call(0x80082B0C, *col) and None, lambda r, g: pj.set_back_color(g, *col))
    case_back_colour(cpu, rng, chk)
    xy = [rng.getrandbits(32) & 0x03FF03FF ^ rng.choice([0, 0xFC00FC00]) for _ in range(3)]
    run(chk, "NormalClip", cpu, lambda c: c.call(0x80082BAC, *xy) & 0xFFFFFFFF,
        lambda r, g: pj.normal_clip(g, *xy))
    nv, cw = BUF + 0x70, BUF + 0x78
    cpu.write(nv, struct.pack("<4h", *(rng.randrange(-0x1000, 0x1001) for _ in range(3)), 0))
    cpu.write(cw, struct.pack("<I", rng.getrandbits(32)))
    power = rng.choice([0, 1, 2, 5, -1])
    run(chk, "ColorMatCol", cpu, lambda c: c.call(0x80082BDC, nv, cw, out, power) and None,
        lambda r, g: pj.color_mat_col(r, g, nv, cw, out, power))
    n = rng.choice([0, 1, 5, 0x4000, rng.getrandbits(32), rng.getrandbits(20), 0x7FFFFFFF])
    run(chk, "SquareRoot0", cpu, lambda c: c.call(0x8004B174, n) & 0xFFFFFFFF,
        lambda r, g: pj.square_root0(r, g, n))
    w32(cpu, pj.LIGHT_POWER, rng.choice([0, -1, 0x1000, rng.randrange(1, 0x10000)]))
    cpu.write(pj.LIGHT_SOURCE, struct.pack("<3i", *(rng.randrange(-0x8000, 0x8000) for _ in range(3))))
    cpu.write(sv, struct.pack("<3i", *(rng.randrange(-0x8000, 0x8000) for _ in range(3))))
    run(chk, "LightDirection", cpu, lambda c: c.call(0x8003A210, sv) and None,
        lambda r, g: pj.light_direction(r, g, sv))
    cpu.write(pj.LIGHT_MATRIX, random_matrix(rng)[:0x14])
    run(chk, "LightLocal", cpu, lambda c: c.call(0x80037A68, a) and None, lambda r, g: pj.light_local(r, g, a))
    n = rng.choice([0, 1, 2, 3, 4, 5, 6, 7, 42, rng.randrange(0, 50)])
    verts, sxy, z = BUF + 0x100, BUF + 0x300, BUF + 0x400
    cpu.write(verts, bytes(rng.getrandbits(8) & 0x0F if k % 2 else rng.getrandbits(8)
                           for k in range(8 * n)))
    if rng.random() < 0.3:
        z = verts                                    # the shadow writes its depths over its vertices
    run(chk, "RotTransPersN", cpu, lambda c: c.call(0x80036D4C, verts, sxy, z, n) and None,
        lambda r, g: pj.rot_trans_pers_n(r, g, verts, sxy, z, n))


def case_back_colour(cpu, rng, chk) -> None:
    """FUN_8003A3B8: the stage's ambient, the flash ramp (counter 0-34, both parities) and practice's
    signal, with random ambient values (including above the flash's peak) and states."""
    fighter, player, stage = BUF + 0x200, rng.randrange(2), rng.randrange(19)
    cpu.write(fighter + 0x12, struct.pack("<h", player))
    cpu.write(pj.STAGE_RECORDS + (stage + 1) * pj.STAGE_RECORD_BYTES,
              struct.pack("<H", rng.choice([rng.randrange(0x2000), rng.getrandbits(16), 1500, 2800])))
    cpu.write(pj.FLASH + player, bytes([rng.choice([0, 0, 1, 2, 31, 32, 33, rng.randrange(1, 35)])]))
    cpu.write(pj.SIGNAL + 4 * player, bytes([rng.choice([0, 1, rng.getrandbits(8)]), *rng.randbytes(3)]))
    w32(cpu, pj.MODE, rng.choice([5, 5, 8, rng.randrange(12)]))
    random_gte(cpu, rng)
    run(chk, "BackColour", cpu, lambda c: c.call(0x8003A3B8, fighter, stage) and None,
        lambda r, g: pj.fighter_back_colour(r, g, player, stage), f"stage {stage} player {player}")
    cpu.write(fighter + 0x12, struct.pack("<h", player))
    run(chk, "BlackBackColour", cpu, lambda c: c.call(0x8003A564) and None,
        lambda r, g: pj.set_back_color(g, 0, 0, 0))


NAMES = ["ApplyMatrixLV", "ViewPoint", "RotTransPers", "ApplyMatrixLV_GTE", "RotMatrixAngles", "SetMulRotMatrix",
         "LocalMatrix", "RotTransPersPsyQ", "MulMatrix0", "MulMatrix", "MulMatrix2", "TransposeMatrix", "ScaleMatrix",
         "ReadLightMatrix", "SetLightMatrix", "SetBackColor", "BackColour", "BlackBackColour", "NormalClip", "ColorMatCol", "SquareRoot0",
         "LightDirection", "LightLocal", "RotTransPersN"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=3000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = vm.menu_cpu("title")
    for _ in range(args.cases):
        case(cpu, rng, chk)
        case_library(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
