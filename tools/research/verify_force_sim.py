#!/usr/bin/env python3
"""Compare force_sim.py with force.ovl's level script runner, key icons and progress bar (Japan Rev.1) in the CPU harness.

The game's FUN_800B1778 (the whole per-frame level runner: script, enemy slots, progress bar,
items, key icons, score and timer caps) runs on random states; all of RAM (the harness stack
excluded), the GTE registers and the return value are compared with the port. The model loader
calls are replaced by stubs that log their arguments.

Usage: python3 tools/research/verify_force_sim.py [--cases N] [--seed S]
"""

from __future__ import annotations

import argparse
import copy
import logging
import random
import struct

import draw_sim as ds
import force_sim as fs
import verify_draw_sim as vd
import verify_menu_sim as vm
import verify_projection_sim as vp

log = logging.getLogger("verify_force_sim")


def w16(cpu, a, v): cpu.write(a, struct.pack("<H", v & 0xFFFF))
def w32(cpu, a, v): cpu.write(a, struct.pack("<I", v & 0xFFFFFFFF))


SCRIPT = 0x801F7000              # test script records
ENEMY_FIGHTERS = (0x801F6000, 0x801F6800)   # stand-in fighter records for the two enemy slots (only +0 .. +0xF74 used)
HOOK_LOGS = {"fade": 0x801F8040, "move": 0x801F8080, "action": 0x801F80C0, "sound": 0x801F8100,
             "reset": 0x801F8140, "request": 0x801F8180, "bind": 0x801F81C0}
PARTS = (0x801F8200, 0x801F8204)    # what the model-part stubs return


class LogHooks(fs.ForceHooks):
    def music_fade(self, ram, a: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["fade"], a)

    def start_move(self, ram, fighter: int, slot: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["move"], slot)

    def enemy_action(self, ram, a: int, b: int, c: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["action"], b)

    def sound(self, ram, sound_id: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["sound"], sound_id)

    def model_reset(self, ram, fighter: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["reset"], fighter)

    def model_request(self, ram, index: int, key: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["request"], key)

    def model_parts(self, ram, index: int) -> tuple[int, int]:
        return ram.u32(PARTS[0]), ram.u32(PARTS[1])

    def model_bind(self, ram, fighter: int, a: int, b: int) -> None:
        vd.ram_log(ram, HOOK_LOGS["bind"], a)


def random_script(cpu, rng) -> None:
    recs = bytearray()
    trig = rng.choice([-100, 0, 500])
    for _ in range(8):
        cmd = rng.choice([0, 1, 1, 2, 3, 4, 5, 6, 7])
        param = {0: rng.randrange(3), 1: rng.choice([0, 1, 2, 3]), 2: rng.choice([0, 1, 5, 0x30, 0x31]),
                 3: rng.choice([-1, 0, 1, 2]), 6: 0}.get(cmd, rng.randrange(-5, 50))
        recs += struct.pack("<ihhhhhhH", trig, cmd, rng.randrange(-5000, 5001), 0, rng.randrange(-3000, 3000), 0,
                            param, rng.randrange(0, 12))
        trig += rng.choice([0, 0, 100, 1000])
    cpu.write(SCRIPT, bytes(recs) + struct.pack("<i", 0x7FFFFFFF))
    w32(cpu, fs.SCRIPT_PTR, SCRIPT)
    player = 0x800A96F0
    w32(cpu, fs.PLAYER, player)
    cpu.write(player + 0x1E, bytes([rng.randrange(2)]))
    clock = cpu.u32(fs.CLOCK)
    for i, f in enumerate(ENEMY_FIGHTERS):
        slot = fs.SLOTS + 0x18 * i
        w32(cpu, slot, f)
        near = lambda: clock + rng.choice([-2, -1, 0, 1, 2, 40, rng.randrange(-100, 100)]) & 0xFFFF
        cpu.write(slot + 4, struct.pack("<hhhHHhhH", rng.randrange(-50, 400), rng.randrange(0, 0x1000),
                                        rng.choice([0, 1, 1, 2, 3, 4, 5, 5, 6, 6, 7, 7, 9]), 0, near(),
                                        rng.randrange(5), rng.randrange(4), rng.randrange(4)))
        cpu.write(slot + 0x14, struct.pack("<H", near()))
        cpu.write(f + 0x3F4, struct.pack("<i", rng.choice([0, 0x100000, -5])))
        for off, v in ((0x1E, rng.randrange(2, 4)), (0x22, rng.randrange(2)), (0xE7, rng.choice([0, 0, 1])),
                       (0xC4, rng.choice([0, 0, 1])), (0xCE, rng.choice([0, 1]))):
            cpu.write(f + off, bytes([v]))
        for off in (0x990, 0x994, 0x998):
            cpu.write(f + off, struct.pack("<i", rng.randrange(-8000, 8000)))
    w32(cpu, PARTS[0], rng.getrandbits(32))
    w32(cpu, PARTS[1], rng.getrandbits(32))
    w32(cpu, ds.TEXT_OFF, rng.choice([0, 0, 0, 1]))
    for i in range(2):
        w32(cpu, fs.ITEMS + 0xBC * i, rng.choice([0, 0, 1, 2]))
    w32(cpu, fs.PATTERN_ON, rng.choice([0, 0, 1, 1, 2]))
    w32(cpu, fs.PATTERN_STOP_X, rng.choice([0, 2000, 60000]))
    w32(cpu, fs.PATTERN_PTR, fs.PATTERNS + 6 * rng.randrange(20))
    w32(cpu, fs.CAMERA + 0x14, rng.randrange(0, 40000))
    w32(cpu, 0x800B70E4, rng.randrange(0, 20000))
    w32(cpu, fs.WAIT_COUNT, rng.choice([-1, 0, 1, 3]))
    w32(cpu, fs.WAIT_DEFEATED, rng.randrange(4))
    w32(cpu, fs.PLAYER_FIGHTER, 0x800A96F0)
    for off, v in ((0x3F4, rng.choice([0, 0x320000, -1])), (0x990, rng.randrange(-8000, 8000)),
                   (0x994, rng.randrange(-2000, 500)), (0x998, rng.randrange(-8000, 8000))):
        cpu.write(0x800A96F0 + off, struct.pack("<i", v))
    w32(cpu, 0x800982D0, rng.choice([0, 1 << 19, rng.getrandbits(21)]))
    cpu.write(0x800982F8, bytes([rng.choice([0, 1, 2, 254, 255])]))
    for cell in HOOK_LOGS.values():
        w32(cpu, cell, 0)


def case_level_script(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    w32(cpu, fs.CLOCK, rng.choice([0, 1, 100, rng.randrange(-5, 5000)]))
    random_script(cpu, rng)
    vp.random_gte(cpu, rng)
    cpu.write(0x800AE438, vp.random_matrix(rng))
    w32(cpu, fs.STATE, rng.choice([0, 0, 0, 1, 1, 2, 3, 4, 5, 6, 6, 6, 7, 7, 8, 9, 10]))
    w32(cpu, fs.TALLY, rng.choice([0, 0x1D, 0x1E, 0x3B, 0x3C, 0x59, 0x5A, 0x77, 0x78, 0x79, 0xB4, 0xB5,
                                   rng.randrange(-5, 200)]))
    w32(cpu, fs.DRAWN, rng.choice([0, 1, rng.randrange(0, 3000)]))
    w32(cpu, 0x800958B8, rng.choice([0, 0, 1]))
    w32(cpu, fs.LEVEL, rng.randrange(5))
    w32(cpu, fs.KEYS, rng.choice([0, 1, 2, 3]))
    score = rng.choice([rng.getrandbits(20), fs.SCORE_CAP, fs.SCORE_CAP + 1, rng.getrandbits(32)])
    w32(cpu, fs.SCORE, score)
    w32(cpu, fs.HISCORE_RUN, rng.choice([score, score - 1, score + 1, rng.getrandbits(32)]))
    w32(cpu, fs.CLEAR_BONUS, rng.choice([0, 100, 12300, rng.randrange(30000)]))
    w32(cpu, fs.CLEAR_TIME, rng.choice([0, 59, 60, 3599, 3600, rng.randrange(20000), -30]))
    w32(cpu, fs.BONUS_TIME, rng.choice([0, 0, 1, 2400, rng.randrange(-100, 4000)]))
    w32(cpu, fs.TIMER, rng.choice([60, 120, 180, 240, 300, 0x1734, 0x1735, 0x2000, -60, rng.randrange(0x1734)]))
    w32(cpu, fs.FIGHT_START_TIMER, rng.randrange(0x1734))
    w32(cpu, fs.KEY_EARNED, rng.randrange(2))
    w32(cpu, fs.FINAL_CHALLENGE, rng.randrange(2))
    w32(cpu, 0x80097350, rng.choice([8, 8, 1, 1, 0]))
    w32(cpu, fs.BAR_PHASE, rng.getrandbits(32))
    w32(cpu, fs.BAR_DONE, rng.choice([0, 0, 1]))
    w32(cpu, fs.LEVEL_ENDED, rng.choice([0, 0, 1]))
    w32(cpu, 0x800A911C, SCENE_OTS)
    w32(cpu, SCENE_OTS + 4, vd.OT + 0x80)
    chk_ = chk["LevelScript"]
    before, scratch = vd.gsnap(cpu)
    ram = ds.GpuRam(before, scratch)
    g2 = copy.deepcopy(cpu.gte)
    state = cpu.u32(fs.STATE)
    got = cpu.call(0x800B1778) & 0xFFFFFFFF
    want = fs.level_frame(ram, g2)
    after, _ = vd.gsnap(cpu)
    d = vd.diff(after, bytes(ram.data[:ds.RAM_SIZE]))
    chk_.cases += 1
    if d or got != want or vp.gte_regs(cpu.gte) != vp.gte_regs(g2):
        chk_.bad += 1
        if chk_.bad <= 5:
            log.info("  LevelScript mismatch state %d: ret %d/%d %s", state, got, want, [hex(a) for a in d[:10]])


def case_items(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    vp.random_gte(cpu, rng)
    cpu.write(0x800AE438, vp.random_matrix(rng))
    for cell in HOOK_LOGS.values():
        w32(cpu, cell, 0)
    cam = rng.randrange(0, 40000)
    w32(cpu, fs.CAMERA + 0x14, cam)
    player = 0x800A96F0
    w32(cpu, fs.PLAYER, player)
    px, pz = cam + rng.randrange(-3000, 3000), rng.randrange(-2000, 2000)
    cpu.write(player + 0xF68, struct.pack("<i", px))
    cpu.write(player + 0xF70, struct.pack("<i", pz))
    for off, v in ((0x3F4, rng.choice([0, 0x100000, -5])), (0x990, px), (0x994, rng.randrange(-2000, 0)), (0x998, pz)):
        cpu.write(player + off, struct.pack("<i", v))
    cpu.write(player + 0xDB, bytes([rng.choice([0, 0, 1])]))
    cpu.write(player + 0x12, struct.pack("<h", rng.randrange(3)))
    clock = rng.randrange(0, 5000)
    w32(cpu, fs.CLOCK, clock)
    w32(cpu, ds.MODE, rng.choice([8, 8, 0]))
    w32(cpu, 0x800958B8, rng.choice([0, 0, 1]))
    for i in range(2):
        it = fs.ITEMS + 0xBC * i
        near = rng.random() < 0.5
        x = px + rng.randrange(-400, 400) if near else cam + rng.randrange(-7000, 7000)
        z = pz + rng.randrange(-400, 400) if near else rng.randrange(-3000, 3000)
        cpu.write(it, struct.pack("<4i", rng.choice([0, 1, 1, 2, 2]), x, rng.randrange(-800, 0), z))
        cpu.write(it + 0x14, struct.pack("<hhi", rng.randrange(0, 360), rng.randrange(0, 4000),
                                          clock + rng.choice([-1, 0, 15, 16, 30, 60])))
    w32(cpu, 0x800A911C, SCENE_OTS)
    w32(cpu, SCENE_OTS + 4, vd.OT + 0x80)
    before, scratch = vd.gsnap(cpu)
    ram = ds.GpuRam(before, scratch)
    g2 = copy.deepcopy(cpu.gte)
    cpu.call(0x800B4374)
    fs.items(ram, g2)
    after, _ = vd.gsnap(cpu)
    d = vd.diff(after, bytes(ram.data[:ds.RAM_SIZE]))
    c = chk["Items"]
    c.cases += 1
    if d or vp.gte_regs(cpu.gte) != vp.gte_regs(g2):
        c.bad += 1
        if c.bad <= 5:
            log.info("  Items mismatch: %s", [hex(a) for a in d[:10]])


def case_key_icons(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    vd.run_gpu(chk, "KeyIconsSetup", cpu, lambda c: c.call(0x800B4740) and None, lambda r: fs.key_icons_setup(r))
    vm.common(cpu, rng)
    w32(cpu, fs.KEYS, rng.choice([0, 1, 2, 3, 4, rng.randrange(-2, 6)]))
    vd.run_gpu(chk, "KeyIcons", cpu, lambda c: c.call(0x800B4924) and None, lambda r: fs.key_icons(r))


SCENE_OTS = 0x801F8280


def case_progress(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    w32(cpu, fs.LEVEL, rng.choice([0, 1, 2, 3, 4, rng.randrange(5)]))
    vd.run_gpu(chk, "ProgressSetup", cpu, lambda c: c.call(0x800B396C) and None, lambda r: fs.progress_setup(r))
    vm.common(cpu, rng)
    w32(cpu, fs.LEVEL, rng.choice([0, 1, 2, 3, 4]))
    w32(cpu, fs.BAR_PHASE, rng.getrandbits(32))
    w32(cpu, fs.BAR_DONE, rng.choice([0, 0, 1]))
    w32(cpu, fs.CAMERA_X, rng.randrange(-0x2000, 0x40000))
    w32(cpu, fs.LEVEL_START_X, rng.choice([0, rng.randrange(0x20000)]))
    w32(cpu, fs.LEVEL_ENDED, rng.choice([0, 0, 1]))
    w32(cpu, 0x800958B8, rng.choice([0, 0, 1]))
    w32(cpu, 0x800A911C, SCENE_OTS)
    w32(cpu, SCENE_OTS + 4, vd.OT + 0x40)
    vd.run_gpu(chk, "ProgressDraw", cpu, lambda c: c.call(0x800B3D34) and None, lambda r: fs.progress_draw(r))


BG_DATA, BG_PACKET_AREA = 0x801F6000, 0x801E0000
BG_OT_AREA, BG_OT = 0x801F8280, 0x801F0000


def case_background(cpu, rng, chk) -> None:
    vm.common(cpu, rng)
    vp.random_gte(cpu, rng)
    view = bytearray(vp.random_matrix(rng))
    struct.pack_into("<i", view, 0x1C, rng.randrange(0x400, 0x6000))
    cpu.write(0x800AE438, bytes(view))
    w, h = rng.choice([(16, 5), (16, 5), (rng.randrange(1, 40), rng.randrange(0, 8))])
    w32(cpu, fs.BG_W, w)
    w32(cpu, fs.BG_H, h)
    w32(cpu, fs.BG_TEX, BG_DATA)
    w32(cpu, fs.BG_CLUT, BG_DATA + 2 * w * h)
    cpu.write(BG_DATA, bytes(rng.getrandbits(8) for _ in range(4 * w * h)))
    w32(cpu, fs.BG_DIV, rng.choice([8, 16, rng.randrange(1, 64), -3]))
    w32(cpu, fs.BG_DEPTH, rng.randrange(0, 0x3F0))
    w32(cpu, fs.BG_SLOPE, rng.choice([0, 0, 0x40, -0x40, rng.randrange(-0x300, 0x300)]))
    level = rng.choice([0, 1, 2, 3, 3])
    w32(cpu, fs.BG_LEVEL, level)
    if level == 3 and w < 3:                             # narrower maps overrun the three gate tiles
        w = 3
        w32(cpu, fs.BG_W, w)
        w32(cpu, fs.BG_CLUT, BG_DATA + 2 * w * h)
    w32(cpu, fs.BG_TILE_ONLY, rng.choice([0, 0, 0, 1]))
    for i in range(3):
        w32(cpu, fs.CAMERA + 0x14 + 4 * i, rng.randrange(-0x8000, 0x40000))
    w32(cpu, fs.BG_PACKETS, BG_PACKET_AREA)
    cpu.write(BG_PACKET_AREA, bytes(rng.getrandbits(8) for _ in range(0x7E0)))
    for i in range(42):
        cpu.write(BG_PACKET_AREA + 0x14 * i + 3, b"\x04")
    for b in range(2):
        cpu.write(fs.BG_TILE + 16 * b + 3, b"\x03")
        for g in range(3):
            cpu.write(fs.BG_GATES + 0x30 * b + 16 * g + 3, b"\x03")
    w32(cpu, 0x800A911C, BG_OT_AREA)
    w32(cpu, BG_OT_AREA + 4, BG_OT)
    vp.run(chk, "Background", cpu, lambda c: c.call(0x800B4DF8) and None, fs.background_draw)
    vm.common(cpu, rng)
    w16(cpu, fs.STAGE_ID, rng.choice([15, 16, 17, 18, rng.randrange(40)]))
    w32(cpu, fs.BG_MAP, BG_DATA)
    cpu.write(BG_DATA, struct.pack("<HH", rng.choice([16, rng.randrange(1, 40)]), rng.choice([5, rng.randrange(0, 7)])))
    w32(cpu, fs.BG_TILE_ONLY, rng.choice([0, 0, 1]))
    w32(cpu, fs.BG_PACKETS, BG_PACKET_AREA)
    vd.run_gpu(chk, "BackgroundSetup", cpu, lambda c: c.call(0x800B4B44) and None, fs.background_setup)


ROLES_OUT = 0x801F7F00


def case_roles(cpu, rng, chk) -> None:
    """FUN_800B5EC0 with FUN_800B598C, and the manual target switch set-up."""
    vm.common(cpu, rng)
    w32(cpu, 0x800AFF50, rng.choice([8, 8, 8, 1]))
    cpu.write(0x800A97B5, bytes([rng.choice([0, 0, 1])]))
    for i, f in enumerate((fs.F0, fs.F1, fs.F2)):
        cpu.write(f + 0x1E, bytes([i, rng.randrange(3), rng.randrange(3), rng.randrange(3), rng.randrange(3),
                                   rng.randrange(3)]))
        cpu.write(f + 0x2A, struct.pack("<13h", *(rng.randrange(-0x8000, 0x8000) for _ in range(13))))
        cpu.write(f + 0x2C, struct.pack("<h", rng.randrange(-0x8000, 0x8000)))
        for off in (0x87, 0xC2, 0xC4, 0xC7, 0xD1):
            cpu.write(f + off, bytes([rng.choice([0, 0, 0, 1])]))
        cpu.write(f + 0x1278, struct.pack("<H", rng.choice([0, 1, 100, 399, 400, rng.getrandbits(16)])))
        cpu.write(f + 0xF68, struct.pack("<3i", rng.randrange(-0x3000, 0x3000), 0, rng.randrange(-0x3000, 0x3000)))
        w32(cpu, f + 0xF8, rng.randrange(0, 0x3000))
    for k in range(8):
        w32(cpu, 0x8009EA08 + 0x10 * k, rng.choice([100, 0x9C3, 0x9C4, rng.randrange(0, 0x3000)]))
    w32(cpu, fs.TARGET_WAIT, rng.choice([0, 0, 1, 5, -3]))
    if rng.random() < 0.4:                               # two close enemies at similar distances
        base = rng.randrange(0, 0x9C3)
        for k in range(8):
            w32(cpu, 0x8009EA08 + 0x10 * k, base + rng.randrange(-300, 300))
        for f in (fs.F0, fs.F1, fs.F2):
            cpu.write(f + 0x1278, struct.pack("<H", 100))
            cpu.write(f + 0xC2, b"\0")
        w32(cpu, fs.TARGET_WAIT, 0)
    w32(cpu, fs.MANUAL, rng.choice([0, 0, 1]))
    w32(cpu, fs.MANUAL_BUTTON, rng.choice([1, 2, 4, 8]))
    w32(cpu, fs.MANUAL_SIDE, rng.randrange(2))
    w16(cpu, fs.HUMAN_SIDE, rng.randrange(2))
    for p in range(2):
        w16(cpu, fs.PAD_PRESSED + 2 * p, rng.choice([0, 1, 2, 4, 8, rng.getrandbits(16)]))
        w16(cpu, fs.PAD_HELD + 2 * p, rng.choice([0xF0, 0xF4, 0xF1, 0xF8, 0xF2, 0xF0 | rng.getrandbits(4), rng.getrandbits(16)]))
    vd.run_gpu(chk, "Roles", cpu, lambda c: c.call(0x800B5EC0, ROLES_OUT, ROLES_OUT + 4, ROLES_OUT + 8) and None,
               lambda r: fs.fighter_roles(r, ROLES_OUT))
    player = rng.randrange(2)
    vd.run_gpu(chk, "ManualTarget", cpu, lambda c: c.call(0x800B5910, player) and None,
               lambda r: fs.manual_target_setup(r, player))


def case_walls(cpu, rng, chk) -> None:
    """ArenaBounds (0x80043394) in Tekken Force: the walls from FUN_800B2F98's lines."""
    import fight_sim as sim
    vm.common(cpu, rng)
    w32(cpu, 0x800AFF50, 8)
    w16(cpu, 0x800AE6CC, rng.choice([8, 8, 6]))
    w32(cpu, 0x80097350, rng.choice([1, 1, 0]))
    w16(cpu, fs.STAGE_ID, rng.choice([15, 16, 17, 18, 18]))
    cpu.call(0x800B2F98)
    w32(cpu, fs.BG_VIEW_X, rng.randrange(-0x2000, 0x40000))
    view = cpu.u32(fs.BG_VIEW_X)
    cpu.write(sim.BOUND_RAMP, struct.pack("<3i", *(rng.choice([0, 2000, rng.randint(0, 2000)]) for _ in range(3))))
    cpu.write(sim.BOUND_RAMP_STEP, struct.pack("<3i", *(rng.randint(0, 60) for _ in range(3))))
    w32(cpu, sim.THROW_LINK, rng.randint(0, 1))
    for base in (fs.F0, fs.F1):
        x = (view if view < 0x80000000 else view - (1 << 32)) + rng.randrange(-0x2400, 0x2400)
        cpu.write(base + 0xF68, struct.pack("<3i", x, rng.randrange(-0x800, 0), rng.randrange(-0xC00, 0xC00)))
        cpu.write(base + 0xC5, bytes([rng.choice([0, 1])]))
        for off in (0x20, 0x21, 0x22, 0x23):
            cpu.write(base + off, bytes([rng.randrange(2)]))
    vd.run_gpu(chk, "ArenaWalls", cpu, lambda c: c.call(0x80043394, fs.F0) and None,
               lambda r: sim.arena_bounds(sim.Fighter(r, fs.F0)))


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--cases", type=int, default=2000)
    parser.add_argument("--seed", type=int, default=1)
    args = parser.parse_args()
    chk = {n: vd.Checker(n) for n in ("LevelScript", "Items", "KeyIconsSetup", "KeyIcons", "ProgressSetup", "ProgressDraw", "Background", "BackgroundSetup", "Roles", "ManualTarget", "ArenaWalls")}
    rng = random.Random(args.seed)
    cpu = vm.menu_cpu("force")
    for a, key, reg in ((0x8006BF80, "fade", 4), (0x8002D93C, "move", 5), (0x800B362C, "action", 5),
                        (0x800756A4, "sound", 5), (0x800363FC, "reset", 4), (0x800360B0, "request", 5),
                        (0x80035F3C, "bind", 5)):
        vd.log_stub(cpu, a, HOOK_LOGS[key], reg)
    vm.status_stub(cpu, 0x80036124, PARTS[0])
    vm.status_stub(cpu, 0x80036140, PARTS[1])
    fs.HOOKS = LogHooks()
    for _ in range(args.cases):
        case_level_script(cpu, rng, chk)
        case_items(cpu, rng, chk)
        case_key_icons(cpu, rng, chk)
        case_progress(cpu, rng, chk)
        case_background(cpu, rng, chk)
        case_roles(cpu, rng, chk)
        case_walls(cpu, rng, chk)
    ok = all([c.report() for c in chk.values() if c.cases])
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
