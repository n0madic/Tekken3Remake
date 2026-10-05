#!/usr/bin/env python3
"""Compare ball_sim.py with Tekken Ball's 3D drawing (volley.ovl, Japan Rev.1) in the CPU harness.

Each case randomises the camera, the view matrix, the GTE and the panorama's tile map, runs the
game's routine and the port on the same RAM, and compares all of RAM (packets and ordering
tables included) and the GTE registers.

Usage: python3 tools/research/verify_ball_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import copy
import logging
import random
import struct

import ball_sim as bs
import projection_sim as pj
import verify_draw_sim as vd
import verify_menu_sim as vm
import verify_projection_sim as vp

log = logging.getLogger("verify_ball_sim")
M32 = 0xFFFFFFFF
MAP_DATA = 0x801F6000            # test tile map: texture words, then CLUTs
PACKETS = 0x801E0000             # test background packet area
SCENE_OT_AREA, SCENE_OT = 0x801F8280, 0x801F0000


def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & M32))


def common(cpu, rng) -> None:
    vm.common(cpu, rng)
    vp.random_gte(cpu, rng)
    cpu.write(pj.VIEW, vp.random_matrix(rng))
    w32(cpu, bs.SCENE_OTS, SCENE_OT_AREA)
    w32(cpu, SCENE_OT_AREA + 4, SCENE_OT)
    for off in (0xFBC, 0xFC0, 0xFF8, 0xFFC):
        w32(cpu, SCENE_OT + off, rng.getrandbits(32))


def case_background(cpu, rng, chk) -> None:
    common(cpu, rng)
    w, h = rng.choice([(32, 8), (32, 8), (rng.randrange(1, 40), rng.randrange(0, 10))])
    w32(cpu, bs.MAP_W, w)
    w32(cpu, bs.MAP_H, h)
    w32(cpu, bs.MAP_TEX, MAP_DATA)
    w32(cpu, bs.MAP_CLUT, MAP_DATA + 2 * w * h)
    cpu.write(MAP_DATA, bytes(rng.getrandbits(8) for _ in range(4 * w * h)))
    w32(cpu, bs.SCROLL_DIV, rng.choice([0x60, 0x60, rng.randrange(1, 0x200)]))
    w32(cpu, bs.YAW_REF, rng.getrandbits(32) if rng.random() < 0.3 else rng.randrange(-0x2000, 0x2000))
    w32(cpu, bs.MODE_KIND, rng.choice([0, 0, 1, 2]))
    w32(cpu, bs.LAST_KIND, rng.choice([0, 1, 2]))
    w32(cpu, bs.CAMERA + 4, rng.choice([rng.randrange(-0x2000, 0x2000), rng.getrandbits(32)]))
    for i in range(3):
        w32(cpu, bs.CAMERA + 0x14 + 4 * i, rng.randrange(-0x8000, 0x8000))
    w32(cpu, bs.ROUND_FLOW, rng.choice([0, 1, 2, 3, 4]))
    for i, v in enumerate((0, rng.choice([0, 8]), 0x170, rng.choice([0xF0, 0x1E0]))):
        w16(cpu, bs.SCREEN + 2 * i, v)
    w32(cpu, bs.BG_PACKETS, PACKETS)
    cpu.write(PACKETS, bytes(rng.getrandbits(8) for _ in range(0x1A40)))
    for i in range(240):
        cpu.write(PACKETS + 0x14 * i + 3, b"\x04")
    for b in range(2):
        cpu.write(bs.SKY + 16 * b + 3, b"\x03")
    vp.run(chk, "BackgroundDraw", cpu, lambda c: c.call(0x800B5F0C) and None, bs.background_draw)


BALL = 0x801E2000               # test ball record (0x1460 bytes with the court packets)
BALL_VERTS = 0x801E5800          # 42 test vertices
EFFECTS = 0x801E5000             # effect nodes (0x40 bytes each)
LENGTHS = ((0x154, 0x1C, 32, 6), (0x4D4, 0x24, 64, 8), (0xDD4, 0x18, 8, 5), (0xEAC, 0x1C, 8, 6), (0xE94, 0xC, 2, 2))


def random_effect_list(cpu, rng) -> None:
    import draw_sim as ds
    n = rng.choice([0, 3, 16, 20, 20])
    nodes = [EFFECTS + 0x40 * i for i in range(n)]
    w32(cpu, ds.EFFECT_FREE, nodes[0] if nodes else ds.EFFECT_FREE_END)
    for i, a in enumerate(nodes):
        w32(cpu, a + 4, nodes[i + 1] if i + 1 < n else ds.EFFECT_FREE_END)
    w32(cpu, ds.EFFECT_USED, 0x801F9C80)
    w32(cpu, 0x801F9C80 + 4, ds.EFFECT_USED)


def case_ball(cpu, rng, chk) -> None:
    common(cpu, rng)
    view = bytearray(vp.random_matrix(rng))
    struct.pack_into("<i", view, 0x1C, rng.randrange(0x800, 0x6000))
    cpu.write(pj.VIEW, bytes(view))
    w32(cpu, bs.TEXT_OFF, rng.choice([0, 0, 0, 0, 1]))
    cpu.write(bs.BALL_TYPE, bytes([rng.randrange(3)]))
    cpu.write(BALL, bytes(rng.getrandbits(8) for _ in range(0xF90)))
    for base, size, count, words in LENGTHS:
        for i in range(count):
            cpu.write(BALL + base + size * i + 3, bytes([words]))
    for off, lo, hi in ((0x68, -0x800, 0x800), (0x6C, -0x600, 0x100), (0x70, -0x800, 0x800)):
        w32(cpu, BALL + off, rng.randrange(lo, hi))
    w32(cpu, BALL + 0xB4, BALL_VERTS)
    cpu.write(BALL_VERTS, b"".join(struct.pack("<4h", *(rng.randrange(-0x180, 0x180) for _ in range(3)), 0)
                                   for _ in range(43)))
    cpu.write(BALL + 0x146, bytes([rng.choice([0, 1, 2, 2, 3, 4, 4, 5, 6, 7, 8, 9, 10, 11]),
                                   rng.choice([0, 1, 3, 5, 5, 8, rng.randrange(256)])]))
    w16(cpu, BALL + 0x150, rng.choice([0, 0, rng.randrange(-0x400, 0x400)]))
    w32(cpu, pj.LIGHT_POWER, rng.choice([0, 0x1000, rng.randrange(-5, 0x4000)]))
    cpu.write(pj.LIGHT_SOURCE, struct.pack("<3i", *(rng.randrange(-0x4000, 0x4000) for _ in range(3))))
    cpu.write(pj.LIGHT_MATRIX, vp.random_matrix(rng)[:0x14])
    w32(cpu, bs.FRAME, rng.getrandbits(32))
    w32(cpu, bs.FROZEN, rng.choice([0, 0, 1]))
    w32(cpu, 0x800A3E80, rng.getrandbits(32))
    random_effect_list(cpu, rng)
    vp.run(chk, "BallDraw", cpu, lambda c: c.call(0x800B3198, BALL) and None, lambda r, g: bs.ball_draw(r, g, BALL))


SETUP_LOG = {"upload": 0x801F8040, "floor": 0x801F8080}


class LogHooks(bs.BallHooks):
    def upload_textures(self, ram, archive: int) -> None:
        vd.ram_log(ram, SETUP_LOG["upload"], 1)
        vd.ram_log(ram, SETUP_LOG["upload"], 0)

    def floor_setup(self, ram, arg: int) -> None:
        vd.ram_log(ram, SETUP_LOG["floor"], arg)


def case_setup(cpu, rng, chk) -> None:
    common(cpu, rng)
    for cell in SETUP_LOG.values():
        w32(cpu, cell, 0)
    cpu.write(MAP_DATA, struct.pack("<HH", rng.choice([32, rng.randrange(1, 40)]), rng.choice([8, rng.randrange(0, 9)])))
    archive = MAP_DATA + 0x800
    w32(cpu, archive, 0)                                 # no textures: the uploads are VRAM only
    w32(cpu, bs.BG_PACKETS, PACKETS)
    cpu.write(0x800AFF68, bytes([rng.choice([0, 0, 1, 4])]))
    arg = rng.getrandbits(8)
    vd.run_gpu(chk, "BackgroundSetup", cpu, lambda c: c.call(0x800B5CC4, arg, MAP_DATA, archive) and None,
               lambda r: bs.background_setup(r, arg, MAP_DATA, archive))


def case_court(cpu, rng, chk) -> None:
    common(cpu, rng)
    view = bytearray(vp.random_matrix(rng))
    struct.pack_into("<i", view, 0x1C, rng.randrange(0x800, 0x6000))
    cpu.write(pj.VIEW, bytes(view))
    w32(cpu, bs.TEXT_OFF, rng.choice([0, 0, 0, 1]))
    cpu.write(BALL, bytes(rng.getrandbits(8) for _ in range(0x1460)))
    for base, size, count, words in ((0x120C, 0x24, 16, 8), (0xF8C, 0x14, 32, 4), (0x144C, 0xC, 2, 2)):
        for i in range(count):
            cpu.write(BALL + base + size * i + 3, bytes([words]))
    a, b = rng.randrange(-0x4000, 0x4000), rng.randrange(-0x4000, 0x4000)
    vp.run(chk, "CourtDraw", cpu, lambda c: c.call(0x800B3DA4, a, b, BALL) and None,
           lambda r, g: bs.court_draw(r, g, a, b, BALL))


TRAMPOLINES = 0x801E3A00
PHYS_LOG = {"sound": 0x801F8100, "vibrate": 0x801F8140, "shake": 0x801F8180, "replay": 0x801F81C0}
FIGHTERS = (0x800A96F0, 0x800AAF7C)
POSITIONS = 0x801F7F00           # the two position pointers (fighter + 0xF68)
MOVE_REC, MOVE_KIND = 0x801F7F20, 0x801F7F60
PROJECTILES = 0x801D0000          # projectile segment tables (2 x 0x780 at +0x3200)


class PhysicsLog(bs.BallPhysicsHooks):
    def sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, PHYS_LOG["sound"], sound_id)

    def vibrate(self, ram, player: int, kind: int) -> None:
        vd.ram_log(ram, PHYS_LOG["vibrate"], kind)

    def camera_shake(self, ram, kind: int) -> None:
        vd.ram_log(ram, PHYS_LOG["shake"], kind)

    def replay_event(self, ram, player: int, kind: int) -> None:
        vd.ram_log(ram, PHYS_LOG["replay"], player)


def random_segments(cpu, rng, a: int, n: int, near: tuple[int, int, int]) -> None:
    for i in range(n):
        if rng.random() < 0.5:
            p = [near[k] + rng.randrange(-0x300, 0x300) for k in range(3)]
            q = [p[k] + rng.randrange(-0x300, 0x300) for k in range(3)]
        else:
            p = [rng.randrange(-0x3000, 0x3000) for _ in range(3)]
            q = [rng.randrange(-0x3000, 0x3000) for _ in range(3)]
        cpu.write(a + 0x18 * i, struct.pack("<6i", *p, *q))


def random_fighter(cpu, rng, f: int, index: int, ball: tuple[int, int, int]) -> None:
    cpu.write(f + 0x12, struct.pack("<hh", index, rng.choice([0, 4, 4, 7, rng.randrange(20)])))
    cpu.write(f + 0x18, struct.pack("<h", rng.choice([0, 0x11, rng.randrange(20)])))
    cpu.write(f + 0x1E, bytes([index]))
    cpu.write(f + 0x22, bytes([rng.randrange(2), rng.randrange(3)]))
    w32(cpu, f + 0x54, MOVE_REC)
    level = rng.choice([0x412, 0x217, 0x31F, 0x10F, 0x51F, 0x607, 0x706, 0x607, rng.getrandbits(16)])
    cpu.write(f + 0x5E, struct.pack("<h", rng.choice([0, 0, 10, 25, rng.randrange(0, 120)])))
    cpu.write(f + 0x64, struct.pack("<HH", level, rng.getrandbits(16)))
    cpu.write(f + 0x85, bytes([rng.choice([0, 0, 0, 1])]))
    cpu.write(f + 0xA0, struct.pack("<h", rng.choice([0, 0x181, rng.randrange(0x400)])))
    cpu.write(f + 0xC3, bytes([rng.choice([1, 1, 0]), rng.choice([0, 0, 0, 1])]))
    cpu.write(f + 0xDB, bytes([rng.choice([0, 0, 1])]))
    cpu.write(f + 0xE3, bytes([rng.choice([0, 1, 2, 4, 6])]))
    random_segments(cpu, rng, f + 0x1AC, 4, ball)
    for k in range(14):
        c = f + 0x20C + 0x14 * k
        r = rng.choice([0, 0x80, 0x100, 0x200])
        p = [ball[i] + rng.randrange(-0x400, 0x400) for i in range(3)] if rng.random() < 0.4 else \
            [rng.randrange(-0x3000, 0x3000) for _ in range(3)]
        cpu.write(c, struct.pack("<3ihhi", *p, r, 0, r * r))
    w32(cpu, f + 0x3F4, rng.choice([0x320000, 0x10000, rng.randrange(0, 0x800000)]))
    w32(cpu, f + 0x950, rng.randrange(-0x1000, 0))
    x = rng.randrange(-0x1800, -0x800) if index == 0 else rng.randrange(0x800, 0x1800)
    cpu.write(f + 0xF68, struct.pack("<3i", x, 0, rng.randrange(-0x200, 0x200)))


def case_physics(cpu, rng, chk) -> None:
    import verify_select_sim as vs
    from unicorn.mips_const import UC_MIPS_REG_S7
    common(cpu, rng)
    for cell in PHYS_LOG.values():
        w32(cpu, cell, 0)
    cpu.write(BALL, bytes(rng.getrandbits(8) for _ in range(0x160)))
    pos = (rng.randrange(-0x2C00, 0x2C00), rng.choice([-0x180, -0x100, -0x189, -0x1500, -0x2100,
                                                          rng.randrange(-0x2200, 0)]), rng.randrange(-0x300, 0x300))
    cpu.write(BALL, struct.pack("<h", rng.choice([0, 1, 2, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8, 9, 9, 10, -1])))
    cpu.write(BALL + 0x68, struct.pack("<3i", *pos))
    cpu.write(BALL + 0x78, struct.pack("<3i", *(rng.randrange(-0x8000, 0x8000) for _ in range(3))))
    cpu.write(BALL + 0x8C, struct.pack("<i", rng.choice([0x200, 0x100, 0x2AA])))
    cpu.write(BALL + 0xA8, struct.pack("<ihh", rng.choice([0, 0x800, 0x1000, 0x1800, rng.randrange(0, 0x8000)]),
                                        0, rng.randrange(-0x1000, 0x1000)))
    cpu.write(BALL + 0xB2, struct.pack("<h", rng.choice([0, 0, 1])))
    cpu.write(BALL + 0xC4, struct.pack("<ii", 0x100, 0x10000))
    cpu.write(BALL + 0xCC, bytes([rng.choice([0, 0, 0, 1, 5])]))
    f_a, f_b = FIGHTERS
    for i, f in enumerate(FIGHTERS):
        random_fighter(cpu, rng, f, i, pos)
    owner = rng.choice([f_a, f_b])
    w32(cpu, BALL + 0x130, owner)
    w32(cpu, BALL + 0x134, f_b if owner == f_a else f_a)
    w32(cpu, BALL + 0x138, rng.choice(FIGHTERS))
    cpu.write(BALL + 0x13C, struct.pack("<hhhhBBBB", rng.randrange(0, 150), rng.randrange(0, 150),
                                        rng.choice([0, 0, 30, 120]), rng.randrange(0, 0x2000), rng.randrange(3),
                                        rng.randrange(2), rng.choice([0, 9, 2]), rng.choice([1, 2, 5, 30])))
    cpu.write(BALL + 0x148, struct.pack("<3hh", 0, 0, 0, rng.randrange(0, 0x200)))
    random_segments(cpu, rng, BALL + 0xD0, 4, pos)
    cpu.write(MOVE_REC + 0x28, struct.pack("<I", MOVE_KIND))
    cpu.write(MOVE_KIND, bytes([rng.choice([0, 0, 0, 0x18, 0x20])]))
    w32(cpu, POSITIONS, f_a + 0xF68)
    w32(cpu, POSITIONS + 4, f_b + 0xF68)
    w32(cpu, 0x800AE148, rng.choice([0, PROJECTILES]))
    w32(cpu, 0x800AE374, rng.randrange(0, 4))
    w32(cpu, 0x800AE378, rng.randrange(0, 4))
    for t in range(2):
        random_segments(cpu, rng, PROJECTILES + 0x3200 + 0x780 * t, 4, pos)
    btype = rng.randrange(3)
    cpu.write(0x800AFF91, bytes([btype]))
    unit, g, gain, zone = ((384, 512, 60, 2304), (368, 512, 80, 1920), (352, 682, 100, 1536))[btype]
    cpu.write(bs.SPEED_UNIT, struct.pack("<hhhhh", unit, rng.choice([16, 24, 32]), g, zone, gain))
    w32(cpu, bs.IDLE, rng.choice([0, 0, 599, 598]))
    w32(cpu, bs.TOUCH_SOUND_WAIT, rng.choice([0, 0, 3]))
    w32(cpu, bs.LOB_BASE, rng.choice([0x400, 0x900, 0x1000, rng.randrange(0, 0x3000)]))
    w32(cpu, bs.NO_SCORE, rng.choice([0, 0, 0, 1]))
    w32(cpu, bs.NO_WINNER_MARK, rng.choice([0, 0, 1]))
    w32(cpu, bs.ROUND_CLOCK, rng.choice([0, 100, 599, 600, 700]))
    w32(cpu, 0x80097350, rng.choice([1, 1, 1, 6]))
    w32(cpu, 0x800A3E80, rng.getrandbits(32))
    random_effect_list(cpu, rng)
    vs.random_popups(cpu, rng)
    if rng.random() < 0.5:                                # a flying ball that a fighter touches
        pos = (rng.randrange(-0x2000, 0x2000), rng.randrange(-0x1000, -0x200), rng.randrange(-0x100, 0x100))
        cpu.write(BALL, struct.pack("<h", rng.choice([2, 2, 3, 3, 4, 9])))
        cpu.write(BALL + 0x68, struct.pack("<3i", *pos))
        cpu.write(BALL + 0xCC, b"\0")
        f = rng.choice(FIGHTERS)
        if rng.random() < 0.7:
            cpu.write(f + 0x85, b"\0")
            cpu.write(f + 0xE3, bytes([rng.randrange(1, 5)]))
            cpu.write(MOVE_KIND, b"\0")
            cpu.write(f + 0x1AC, struct.pack("<6i", pos[0] - 0x80, pos[1], pos[2], pos[0] + 0x80, pos[1], pos[2]))
        else:
            cpu.write(f + 0xC4, b"\0")
            other = f_b if f == f_a else f_a
            cpu.write(other + 0xC4, b"\0")
            cpu.write(f + 0x20C, struct.pack("<3ihhi", pos[0], pos[1], pos[2], 0x100, 0, 0x10000))
            random_segments(cpu, rng, BALL + 0xD0, 4, pos)
            cpu.write(BALL + 0xD0, struct.pack("<6i", pos[0] - 0x80, pos[1], pos[2], pos[0] + 0x80, pos[1], pos[2]))
    s7 = rng.choice([0, 0, 1, 2, 0x800AE508])
    cpu.uc.reg_write(UC_MIPS_REG_S7, s7)

    def game(c):
        c.uc.reg_write(UC_MIPS_REG_S7, s7)
        c.call(0x800B16A4, BALL, f_a, f_b, POSITIONS)

    if chk is None:
        return
    vd.run_gpu(chk, "BallUpdate", cpu, game,
               lambda r: bs.ball_update(r, copy.deepcopy(cpu.gte), BALL, f_a, f_b, POSITIONS, s7) and None)


FLOW_LOG = {"face": 0x801F8200, "replay": 0x801F8240}


class FlowLog(bs.BallFlowHooks):
    def face_opponent(self, ram, fighter: int, other: int) -> None:
        vd.ram_log(ram, FLOW_LOG["face"], fighter)

    def replay_ball(self, ram, ball: int) -> None:
        vd.ram_log(ram, FLOW_LOG["replay"], ball)


def case_flow(cpu, rng, chk) -> None:
    """The render kind, the move tuning, the set-ups and the whole frame hook."""
    common(cpu, rng)
    for cell in list(FLOW_LOG.values()) + list(PHYS_LOG.values()):
        w32(cpu, cell, 0)
    w32(cpu, bs.BALL_PTR, BALL)
    cpu.write(BALL, struct.pack("<h", rng.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])))
    cpu.write(BALL + 0x140, struct.pack("<h", rng.choice([0, 0, 30, 99, 100, 150])))
    cpu.write(BALL + 0x145, bytes([rng.randrange(2)]))
    cpu.write(BALL + 0xCC, bytes([rng.choice([0, 0, 5, 3])]))
    cpu.write(BALL + 0xCD, bytes([rng.randrange(2)]))
    cpu.write(BALL + 0xB2, struct.pack("<h", rng.choice([0, 1])))
    cpu.write(BALL + 0x150, struct.pack("<h", rng.choice([0, 0x40, 0x7F, 0x80, 0x300, rng.randrange(-0x100, 0x400)])))
    cpu.write(BALL + 0x78, struct.pack("<3i", *(rng.randrange(-0x4000, 0x4000) for _ in range(3))))
    w32(cpu, BALL + 0x130, rng.choice(FIGHTERS))
    for i, f in enumerate(FIGHTERS):
        cpu.write(f + 0x1E, bytes([i]))
    cpu.write(bs.GLOWS, bytes([rng.getrandbits(4)]))
    random_effect_list(cpu, rng)
    vd.run_gpu(chk, "AfterUpdate", cpu, lambda c: c.call(0x800B2F14, BALL) and None,
               lambda r: bs.ball_after_update(r, BALL))
    f = rng.choice(FIGHTERS)
    cpu.write(f + 0x12, struct.pack("<h", rng.randrange(2)))
    cpu.write(f + 0xA0, struct.pack("<h", rng.choice([0x18 + rng.randrange(10), rng.randrange(0x40), 0x17, 0x22])))
    vd.run_gpu(chk, "MoveTuning", cpu, lambda c: c.call(0x800B0B54, f) and None, lambda r: bs.move_tuning(r, f))
    cpu.write(0x800AFF91, bytes([rng.randrange(3)]))
    cpu.write(bs.MODE_FLAGS, bytes([rng.randrange(2)]))
    w32(cpu, 0x800958A8, rng.choice([1, 2, 3]))
    w16(cpu, 0x800AE14C, rng.randrange(20))
    vd.run_gpu(chk, "FightStart", cpu, lambda c: c.call(0x800B0C90) and None, bs.fight_start)
    vd.run_gpu(chk, "RoundReset", cpu, lambda c: c.call(0x800B0DD8) and None, bs.round_reset)


def case_frame(cpu, rng, chk) -> None:
    from unicorn.mips_const import UC_MIPS_REG_S7
    case_physics(cpu, rng, None)
    w32(cpu, bs.BALL_PTR, BALL)
    for cell in list(FLOW_LOG.values()):
        w32(cpu, cell, 0)
    w32(cpu, 0x800958B8, rng.choice([0, 0, 0, 1]))
    w32(cpu, bs.FROZEN_FIGHT, rng.choice([0, 0, 0, 1]))
    w32(cpu, bs.REPLAY_PLAYBACK, rng.choice([0, 0, 0, 1]))
    cpu.write(0x80098DDD, bytes([rng.choice([0, 2])]))
    cpu.write(0x800AFF6C, bytes([rng.randrange(2)]))
    cpu.write(BALL + 0x146, bytes([rng.choice([0, 3, 5, 9])]))
    cpu.write(bs.BALL_TYPE, bytes([rng.randrange(3)]))
    for base, size, count, words in LENGTHS:
        for i in range(count):
            cpu.write(BALL + base + size * i + 3, bytes([words]))
    for base, size, count, words in ((0x120C, 0x24, 16, 8), (0xF8C, 0x14, 32, 4), (0x144C, 0xC, 2, 2)):
        for i in range(count):
            cpu.write(BALL + base + size * i + 3, bytes([words]))
    w32(cpu, BALL + 0xB4, BALL_VERTS)
    cpu.write(BALL_VERTS, b"".join(struct.pack("<4h", *(rng.randrange(-0x180, 0x180) for _ in range(3)), 0)
                                   for _ in range(43)))
    for g in range(2):
        cpu.write(0x800B68E8 + 0x10 * g, struct.pack("<ihhh", rng.randrange(0, 100), *(rng.randrange(0, 76) for _ in range(3))))
    s7 = rng.choice([0, 1])
    f_a, f_b = FIGHTERS

    def game(c):
        c.uc.reg_write(UC_MIPS_REG_S7, s7)
        c.call(0x800B0E14, f_a, f_b)

    vd.run_gpu(chk, "BallFrame", cpu, game,
               lambda r: bs.ball_frame(r, copy.deepcopy(cpu.gte), f_a, f_b, s7) and None)


NAMES = ["BackgroundDraw", "BallDraw", "BackgroundSetup", "CourtDraw", "BallUpdate", "AfterUpdate", "MoveTuning",
         "FightStart", "RoundReset", "BallFrame"]

FLOW_LOG = {"face": 0x801F8200, "replay": 0x801F8240}


class FlowLog(bs.BallFlowHooks):
    def face_opponent(self, ram, fighter: int, other: int) -> None:
        vd.ram_log(ram, FLOW_LOG["face"], fighter)

    def replay_ball(self, ram, ball: int) -> None:
        vd.ram_log(ram, FLOW_LOG["replay"], ball)


def case_flow(cpu, rng, chk) -> None:
    """The render kind, the move tuning, the set-ups and the whole frame hook."""
    common(cpu, rng)
    for cell in list(FLOW_LOG.values()) + list(PHYS_LOG.values()):
        w32(cpu, cell, 0)
    w32(cpu, bs.BALL_PTR, BALL)
    cpu.write(BALL, struct.pack("<h", rng.choice([0, 1, 2, 3, 4, 5, 6, 7, 8, 9])))
    cpu.write(BALL + 0x140, struct.pack("<h", rng.choice([0, 0, 30, 99, 100, 150])))
    cpu.write(BALL + 0x145, bytes([rng.randrange(2)]))
    cpu.write(BALL + 0xCC, bytes([rng.choice([0, 0, 5, 3])]))
    cpu.write(BALL + 0xCD, bytes([rng.randrange(2)]))
    cpu.write(BALL + 0xB2, struct.pack("<h", rng.choice([0, 1])))
    cpu.write(BALL + 0x150, struct.pack("<h", rng.choice([0, 0x40, 0x7F, 0x80, 0x300, rng.randrange(-0x100, 0x400)])))
    cpu.write(BALL + 0x78, struct.pack("<3i", *(rng.randrange(-0x4000, 0x4000) for _ in range(3))))
    w32(cpu, BALL + 0x130, rng.choice(FIGHTERS))
    for i, f in enumerate(FIGHTERS):
        cpu.write(f + 0x1E, bytes([i]))
    cpu.write(bs.GLOWS, bytes([rng.getrandbits(4)]))
    random_effect_list(cpu, rng)
    vd.run_gpu(chk, "AfterUpdate", cpu, lambda c: c.call(0x800B2F14, BALL) and None,
               lambda r: bs.ball_after_update(r, BALL))
    f = rng.choice(FIGHTERS)
    cpu.write(f + 0x12, struct.pack("<h", rng.randrange(2)))
    cpu.write(f + 0xA0, struct.pack("<h", rng.choice([0x18 + rng.randrange(10), rng.randrange(0x40), 0x17, 0x22])))
    vd.run_gpu(chk, "MoveTuning", cpu, lambda c: c.call(0x800B0B54, f) and None, lambda r: bs.move_tuning(r, f))
    cpu.write(0x800AFF91, bytes([rng.randrange(3)]))
    cpu.write(bs.MODE_FLAGS, bytes([rng.randrange(2)]))
    w32(cpu, 0x800958A8, rng.choice([1, 2, 3]))
    w16(cpu, 0x800AE14C, rng.randrange(20))
    vd.run_gpu(chk, "FightStart", cpu, lambda c: c.call(0x800B0C90) and None, bs.fight_start)
    vd.run_gpu(chk, "RoundReset", cpu, lambda c: c.call(0x800B0DD8) and None, bs.round_reset)


def case_frame(cpu, rng, chk) -> None:
    from unicorn.mips_const import UC_MIPS_REG_S7
    case_physics(cpu, rng, None)
    w32(cpu, bs.BALL_PTR, BALL)
    for cell in list(FLOW_LOG.values()):
        w32(cpu, cell, 0)
    w32(cpu, 0x800958B8, rng.choice([0, 0, 0, 1]))
    w32(cpu, bs.FROZEN_FIGHT, rng.choice([0, 0, 0, 1]))
    w32(cpu, bs.REPLAY_PLAYBACK, rng.choice([0, 0, 0, 1]))
    cpu.write(0x80098DDD, bytes([rng.choice([0, 2])]))
    cpu.write(0x800AFF6C, bytes([rng.randrange(2)]))
    cpu.write(BALL + 0x146, bytes([rng.choice([0, 3, 5, 9])]))
    cpu.write(bs.BALL_TYPE, bytes([rng.randrange(3)]))
    for base, size, count, words in LENGTHS:
        for i in range(count):
            cpu.write(BALL + base + size * i + 3, bytes([words]))
    for base, size, count, words in ((0x120C, 0x24, 16, 8), (0xF8C, 0x14, 32, 4), (0x144C, 0xC, 2, 2)):
        for i in range(count):
            cpu.write(BALL + base + size * i + 3, bytes([words]))
    w32(cpu, BALL + 0xB4, BALL_VERTS)
    cpu.write(BALL_VERTS, b"".join(struct.pack("<4h", *(rng.randrange(-0x180, 0x180) for _ in range(3)), 0)
                                   for _ in range(43)))
    for g in range(2):
        cpu.write(0x800B68E8 + 0x10 * g, struct.pack("<ihhh", rng.randrange(0, 100), *(rng.randrange(0, 76) for _ in range(3))))
    s7 = rng.choice([0, 1])
    f_a, f_b = FIGHTERS

    def game(c):
        c.uc.reg_write(UC_MIPS_REG_S7, s7)
        c.call(0x800B0E14, f_a, f_b)

    vd.run_gpu(chk, "BallFrame", cpu, game,
               lambda r: bs.ball_frame(r, copy.deepcopy(cpu.gte), f_a, f_b, s7) and None)


NAMES = ["BackgroundDraw", "BallDraw", "BackgroundSetup", "CourtDraw", "BallUpdate", "AfterUpdate", "MoveTuning",
         "FightStart", "RoundReset", "BallFrame"]


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in NAMES}
    rng = random.Random(args.seed)
    cpu = vm.menu_cpu("volley")
    vd.log_stub(cpu, 0x8002988C, SETUP_LOG["upload"], 4)
    vd.log_stub(cpu, 0x80048548, SETUP_LOG["floor"], 4)
    bs.HOOKS = LogHooks()
    for i, (a, key, reg) in enumerate(((0x800756A4, "sound", 5), (0x800760D4, "vibrate", 5),
                                       (0x8004AF94, "shake", 4), (0x8004A840, "replay", 4))):
        tramp = TRAMPOLINES + 0x40 * i                    # FUN_8004A840 is shorter than a log stub
        vd.log_stub(cpu, tramp, PHYS_LOG[key], reg)
        cpu.write(a, struct.pack("<2I", 0x08000000 | tramp >> 2 & 0x3FFFFFF, 0))
    bs.PHYSICS_HOOKS = PhysicsLog()
    for i, (a, key, reg) in enumerate(((0x8002BFCC, "face", 4), (0x800339F4, "replay", 4))):
        tramp = TRAMPOLINES + 0x100 + 0x40 * i
        vd.log_stub(cpu, tramp, FLOW_LOG[key], reg)
        cpu.write(a, struct.pack("<2I", 0x08000000 | tramp >> 2 & 0x3FFFFFF, 0))
    bs.FLOW_HOOKS = FlowLog()
    cpu.r3000_divide_range(0x800B16A4, 0x800B2F14)
    for _ in range(args.cases):
        case_background(cpu, rng, chk)
        case_ball(cpu, rng, chk)
        case_setup(cpu, rng, chk)
        case_court(cpu, rng, chk)
        case_physics(cpu, rng, chk)
        case_flow(cpu, rng, chk)
        case_frame(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
