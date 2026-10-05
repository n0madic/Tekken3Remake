#!/usr/bin/env python3
"""Integer ports of Tekken 3 fight routines that operate on a copy of game RAM.

Each port reads and writes guest memory through `Ram`, using the same addresses
and field offsets as the game (Japan Rev.1). `tools/research/verify_fight_sim.py`
runs the original routine in the CPU harness on identical memory and compares
the fighter records byte for byte afterwards.

Field offsets come from tools/ghidra/fighter_fields.tsv (see
docs/research/code/fighter.md).
"""

from __future__ import annotations

import struct
from pathlib import Path

from fight_math import div_trunc, s16, trunc12, w32

ROOT = Path(__file__).resolve().parents[2]
RAM_BASE = 0x80000000
RAM_SIZE = 0x200000
FIGHTER_SIZE = 0x188C
SIZES = {"u8": 1, "s8": 1, "u16": 2, "s16": 2, "u32": 4, "s32": 4, "void*": 4}
FMT = {"u8": "B", "s8": "b", "u16": "H", "s16": "h", "u32": "I", "s32": "i", "void*": "I"}


def load_fields() -> dict[str, tuple[int, str]]:
    fields = {}
    for line in (ROOT / "tools" / "ghidra" / "fighter_fields.tsv").read_text().splitlines():
        if line.startswith("#") or not line.strip():
            continue
        off, ctype, name = line.split("\t")[:3]
        if ctype in SIZES:
            fields[name] = (int(off, 16), ctype)
    return fields


FIELDS = load_fields()


class Ram:
    """Little-endian guest memory (kseg0 RAM only)."""

    def __init__(self, data: bytes | bytearray) -> None:
        self.data = bytearray(data)

    def _off(self, addr: int) -> int:
        off = (addr & 0x1FFFFFFF)
        if off >= RAM_SIZE:
            raise ValueError(f"address {addr:#x} outside RAM")
        return off

    def get(self, addr: int, fmt: str) -> int:
        return struct.unpack_from("<" + fmt, self.data, self._off(addr))[0]

    def put(self, addr: int, fmt: str, value: int) -> None:
        size = struct.calcsize(fmt)
        value &= (1 << (8 * size)) - 1
        if fmt.islower() and value >= 1 << (8 * size - 1):
            value -= 1 << (8 * size)
        struct.pack_into("<" + fmt, self.data, self._off(addr), value)

    def u8(self, a: int) -> int: return self.get(a, "B")
    def s8(self, a: int) -> int: return self.get(a, "b")
    def u16(self, a: int) -> int: return self.get(a, "H")
    def s16(self, a: int) -> int: return self.get(a, "h")
    def u32(self, a: int) -> int: return self.get(a, "I")
    def s32(self, a: int) -> int: return self.get(a, "i")


class Fighter:
    """Named-field view of one fighter record in `Ram`."""

    def __init__(self, ram: Ram, base: int) -> None:
        object.__setattr__(self, "ram", ram)
        object.__setattr__(self, "base", base)

    def __getattr__(self, name: str) -> int:
        off, ctype = FIELDS[name]
        return self.ram.get(self.base + off, FMT[ctype])

    def __setattr__(self, name: str, value: int) -> None:
        off, ctype = FIELDS[name]
        self.ram.put(self.base + off, FMT[ctype], value)

    def at(self, off: int, fmt: str) -> int:
        return self.ram.get(self.base + off, fmt)

    def set_at(self, off: int, fmt: str, value: int) -> None:
        self.ram.put(self.base + off, fmt, value)


# ---------------------------------------------------------------- HitClassify

CHIP_GLOBAL = 0x800AFF20
FIGHTER_DISTANCE = 0x800AFF04
CLOSE_REACTIONS = 0x800177DC


def hit_classify(ram: Ram, defender: Fighter, attacker: Fighter, slot: int) -> None:
    """HitClassify (0x80044D24): set the outcome bytes of a hit slot."""
    if attacker.damage == 0:
        ram.put(slot + 0x28, "B", 1)
        return
    close = ram.u16(attacker.poseMove + 0x34)
    if close and ram.u32(FIGHTER_DISTANCE) < (ram.s16(CLOSE_REACTIONS + close * 4 + 2) & 0xFFFFFFFF):
        ram.put(slot + 0x26, "B", 1)
    if (defender.guard & attacker.attack) == 0 or (defender.relAngle & 0xFFFF) > 0x3FFF:
        ram.put(slot + 0x24, "B", 1)
        startup = defender.damage != 0 and defender.poseFrame < ram.u8(defender.poseMove + 0x2D)
        if startup or defender.powerTimer != 0 or attacker.powerTimer != 0:
            ram.put(slot + 0x25, "B", 1)
        if defender.inAir or (ram.u32(defender.poseMove + 4) & 0x400):
            ram.put(slot + 0x27, "B", 1)
    else:
        ram.put(slot + 0x22, "B", 1)
        if ram.s32(CHIP_GLOBAL) != 0 or attacker.powerTimer != 0:
            ram.put(slot + 0x23, "B", 1)


# ------------------------------------------------------- move start / advance

import fight_math  # noqa: E402  (ports shared with fight_math)

EXE_PATH = ROOT / "work" / "jp_rev1" / "exe.bin"
GAME_MODE = 0x800AFF50
BALL_DRIFT = 0x800B6B40            # volley.ovl, per player: s16 angle offset, u8 speed, u8 first/last frame
AIR_KINDS = 0x8001A630
PUSH_TABLES = 0x8001075C
AIR_FRAMES = 0x80095B94
ANGLE_FIELDS = ("targetDir", "oppToSelfDir", "oppHeading", "headingDelta", "facingQuadrant",
                "oppHeadingDelta", "oppQuadrant", "relAngle", "oppRelAngle", "aimDir", "oppAimDir")
_EXE: fight_math.Exe | None = None


def exe() -> fight_math.Exe:
    global _EXE
    if _EXE is None:
        _EXE = fight_math.Exe(EXE_PATH.read_bytes())
    return _EXE


def relative_angles(f: Fighter, opp: Fighter) -> None:
    """FighterRelativeAngles (0x80043D2C) on RAM."""
    state = {n: getattr(f, n) & 0xFFFF for n in ANGLE_FIELDS}
    state.update(fixedFacing=f.fixedFacing, fixedFacingSide=f.fixedFacingSide, heading=f.heading,
                 rootX=f.rootX, rootZ=f.rootZ, dist=f.dist)
    other = {"rootX": opp.rootX, "rootZ": opp.rootZ, "heading": opp.heading}
    fight_math.relative_angles(state, other, exe())
    for name in ANGLE_FIELDS:
        setattr(f, name, state[name])


def launch_trajectory(f: Fighter) -> None:
    """LaunchTrajectory (0x8002F2C8) on RAM."""
    ram = f.ram
    move, pose = f.moveRow, f.poseMove
    state = {n: getattr(f, n) for n in ("rootY", "groundOffset", "lastDamage", "juggleCount", "airKind",
                                        "velY", "hitDirY", "state", "poseFrame", "targetDir")}
    out = fight_math.launch_trajectory(state, ram.u8(move + 0x1B), ram.u8(pose + 0x18), ram.u8(move + 0x18),
                                       ram.u32(pose) == ram.u32(move))
    ram.put(AIR_FRAMES + 4 * f.index, "i", out.pop("airFrames"))
    for name, value in out.items():
        setattr(f, name, value)


def input_buffer_enable(f: Fighter, on: bool) -> None:
    """FUN_8002C33C / FUN_8002C360: open (counters 0) or close (-1) the command buffer."""
    if on and f.at(0x410, "i") < 0:
        for off in (0x410, 0x414, 0x418):
            f.set_at(off, "i", 0)
    elif not on and f.at(0x410, "i") >= 0:
        for off in (0x410, 0x414, 0x418):
            f.set_at(off, "i", -1)


def sound_script_stop(f: Fighter) -> None:
    """SoundScriptStop (0x80041C30)."""
    f.set_at(0x70, "H", 0xFFFF)
    f.set_at(0x72, "h", 0)
    f.set_at(0x11E, "h", 0)
    f.set_at(0x120, "h", 0)


def push_repeat_count(f: Fighter) -> None:
    """PushRepeatCount (0x8003159C)."""
    code = f.transition & 0xFFFF
    if code - 0x27 < 2 or code == 0x2B:
        if f.pushRepeatTimer == 0:
            f.pushRepeat = 0
        elif (f.pushRepeatTrans & 0xFFFF) == code:
            f.pushRepeat = f.pushRepeat + 1
        f.pushRepeatTrans = f.transition
        f.pushRepeatTimer = f.ram.u8(f.moveRow + 0x18) + 10


def _turn_step(target: int, heading: int, frames: int) -> int:
    return div_trunc(s16(target - heading), s16(frames))


def _move_len(f: Fighter, row: int) -> int:
    return f.ram.u8(row + 0x18)


def _continue_frames(f: Fighter) -> None:
    move = {"length": _move_len(f, f.moveRow), "activeStart": f.ram.u8(f.moveRow + 0x2D),
            "activeEnd": f.ram.u8(f.moveRow + 0x2E)}
    if fight_math.move_keeps_frame(move, f.branchKind, f.poseFrame):
        f.poseFrame = f.poseFrame + 1
        f.rootFrame = f.rootFrame + 1
    else:
        f.poseFrame = f.rootFrame = 1
    _clamp_to_length(f)


def _clamp_to_length(f: Fighter) -> None:
    n = _move_len(f, f.moveRow)
    if n < f.poseFrame:
        f.poseFrame = f.rootFrame = n


def _recover_mash(f: Fighter) -> None:
    value = 0
    if not (f.ram.u32(f.poseMove + 0x24) >> 8) & 0x10:
        value = f.lastDamage + div_trunc(s16(f.recoverMash), 2)
    f.recoverMash = 0x42 if s16(value) > 0x41 else value
    f.recoverFrames = _move_len(f, f.moveRow)


def _load_push(f: Fighter, index: int) -> None:
    table = PUSH_TABLES + 2 * index
    f.pushFrames = f.ram.s16(table)
    f.pushSpeed = f.ram.s16(table + 2)
    f.pushTable = table + 4
    f.pushTableFrames = 8


def _advance(f: Fighter) -> None:
    ram = f.ram
    f.moveFrame = f.moveFrame + 1
    f.moveChanged = 0
    freeze = f.hitFreeze
    if freeze > 0:
        f.hitFreeze = freeze - 1
        if freeze != 1:
            return
        f.hitFreeze = 0
        f.poseFrame = f.rootFrame = f.poseFrame + 1
        f.rootMove = f.poseMove
        return
    hold = f.holdFrames
    hold_frame = ram.u8(f.poseMove + 0x1B)
    if hold < 0:
        if f.ballistic == 0:
            f.poseFrame = f.poseFrame + f.frameStep
            if f.poseFrame < 1:
                f.poseFrame = 1
            f.rootFrame = f.poseFrame
        elif (f.poseFrame & 0xFFFF) != hold_frame:
            f.poseFrame = f.rootFrame = f.poseFrame + 1
        return
    if (f.poseFrame & 0xFFFF) == hold_frame:
        if hold < 1:
            if hold != 0:
                return
            f.poseFrame = f.rootFrame = f.poseFrame + 1
            f.rootMove = f.poseMove
            return
        f.holdFrames = hold - 1
    else:
        f.poseFrame = f.poseFrame + 1
    f.rootFrame = f.rootFrame + 1


def move_start_or_advance(f: Fighter, opp: Fighter) -> None:
    """MoveStartOrAdvance (0x8002F600)."""
    ram = f.ram
    if f.active == 0:
        return
    f.stepCooldown = f.stepCooldown - 1
    if f.stepCooldown < 0:
        f.stepCooldown = 0
    start = True
    if f.moveRow == 0:
        start = False
    elif f.frameStep < 1:
        if f.frameStep < 0:
            start = f.poseFrame <= f.entryFrame or f.poseFrame < 1
    else:
        start = not (f.poseFrame < f.entryFrame) or _move_len(f, f.poseMove) <= f.poseFrame
    if not start:
        _advance(f)
        return
    move = f.moveRow
    if f.branchKind == 3:
        f.entryFrame = 1
    f.prevPoseFrame = f.poseFrame
    f.prevSlot = f.curSlot
    f.prevMoveUnk10 = ram.s16(move + 0x10)
    for off in (0x86, 0xBA, 0xBC, 0x85):
        f.set_at(off, "B", 0)
    f.airPhase = f.slideState = f.trackMode = 0
    f.holdFrames = -1
    f.oppStartX = opp.rootX
    f.oppStartZ = opp.rootZ
    f.frameStep = 1
    f.trackAccum = 0
    f.stepKind = f.condFlagUsed = 0
    f.hitFreeze = 0
    f.hitDone0 = f.hitDone1 = 0
    f.hitCooldown = 0
    if f.damageOverride == 0:
        word = ram.u16(move + 0x14)
        f.attackClass = word >> 14
        f.damage = 0 if f.attackClass == 1 else word & 0x3FFF
    else:
        f.damage = f.damageOverride
    f.state = ram.u32(move + 4)
    f.attack = ram.u16(move + 8)
    f.guard = f.state & 0x18
    f.stateClass = (f.state >> 11) & 0x1F
    f.attackHi = f.attack >> 8
    if ram.s32(GAME_MODE) != 5:
        f.humanGuard = 1 if f.isCpu == 0 else 0
    if f.state & 0x100 and f.humanGuard == 0:
        f.state = f.state & 0xFFFFFFE7
        f.guard = f.guard & 0xFFE7
    move_flags = ram.u32(move + 0x24) >> 8
    pose_flags_word = ram.u32(f.poseMove + 0x24)
    f.crouchMove = 1 if move_flags & 0x20 else 0
    input_buffer_enable(f, bool(move_flags & 0x20))
    if f.at(0x414, "i") < f.at(0x410, "i"):
        f.set_at(0x414, "i", f.at(0x414, "i") + 1)
    f.guardedPrev = 1 if f.guarded else 0
    if f.gotHit == 0:
        f.wasHitThisMove = 0
        f.ballistic = 0
        f.juggleCount = 0
    if f.contact == 0:
        f.contactThisMove = 0
    chain = (f.hitClean != 0 or ((pose_flags_word >> 8) & 0x400 and move_flags & 0x400)
             or (f.throwState < 0 and move_flags & 0x400))
    if chain:
        f.reactChain = f.reactChain + 1
    elif f.inReaction == 0 and f.throwState >= 0:
        f.reactChain = 0
    elif ((f.transition - 0x1A) & 0xFFFF) > 1:
        if f.transition == 0x22:
            f.reactChain = f.reactChain + 1
        elif (f.moveSlot & 0xFFFF) == 0x9A6:
            pass
        elif (f.moveSlot & 0xFFFF) == 0xCC6:
            f.reactChain = f.reactChain + 1
        else:
            f.reactChain = 0
    f.inReaction = f.hitClean
    if f.gotHit and f.health != 0:
        f.hitFreeze = f.hitFreezeIn
    if f.branchKind in (1, 3) or ram.u32(move) != ram.u32(f.poseMove):
        f.moveChanged = 1
    reanchor = (pose_flags_word >> 28) & 1
    if (pose_flags_word >> 8) & 0x100:
        f.powerTimer = 0x78
    if move_flags & 8:
        f.attackAlert = 9
    if f.transBit7:
        f.transBit7 = 0
        f.heading = f.heading - 0x8000
        f.facing = f.facing - 0x8000
    if f.applyEndTurn and f.transition != 0x22:
        f.heading = f.facing = f.heading + ram.s16(f.poseMove + 0x12)
    relative_angles(f, opp)
    tail = _transition(f, opp, f.transition, reanchor)
    if tail and reanchor:
        f.posX, f.posZ = f.rootX, f.rootZ
    _finish(f)


def _transition(f: Fighter, opp: Fighter, code: int, reanchor: int) -> bool:
    """Apply one transition case; returns True when the common re-anchor tail runs."""
    ram = f.ram
    move = f.moveRow

    def restart() -> None:
        f.poseFrame = f.rootFrame = 1

    def anchor() -> None:
        f.posX, f.posZ = f.rootX, f.rootZ

    def anchor_if_flagged() -> None:
        if reanchor:
            anchor()

    def clear_turn() -> None:
        f.turnFrames = 0
        f.turnStep = 0

    def timed_turn(target: int) -> None:
        frames = ram.u8(move + 0x2D) - 1
        f.turnFrames = frames if frames >= 1 else 1
        f.turnStep = _turn_step(target, f.heading, f.turnFrames)

    def keep_root_move() -> None:
        f.rootFrame = f.rootFrame + 1
        n = _move_len(f, f.rootMove)
        if n < f.rootFrame:
            f.rootFrame = n

    if code == 0:
        restart()
        f.throwState = 0
        f.rootMove = move
        f.heading = f.facing = f.targetDir
        anchor()
        return False
    if code in (1, 2, 3):
        if code == 1:
            f.facing = f.heading
        _continue_frames(f)
        f.trackMode = 11
        f.throwState = 0
        f.anchorDirty = 1
        f.rootMove = move
        anchor()
        return False
    if code == 4:
        f.poseFrame = 1
        keep_root_move()
        f.trackMode = 11
        f.holdFrames = f.branchWindow
        f.facing = f.heading
        if f.relAngle < 0x4FA5:
            timed_turn(f.targetDir)
        f.throwState = 0
        return False
    if code == 5:
        f.poseFrame = 1
        keep_root_move()
        f.holdFrames = f.branchWindow
        f.facing = f.heading
        f.trackMode = 4 if f.relAngle < 0x4FA4 else 6
        clear_turn()
        f.throwState = 0
        return False
    if code == 6:
        restart()
        f.rootMove = move
        f.facing = f.heading
        anchor_if_flagged()
        f.throwState = 0
        return False
    if code == 7:
        f.rootMove = move
        f.facing = f.heading
        f.poseFrame = f.rootFrame = _move_len(f, move)
        anchor_if_flagged()
        f.frameStep = -1
        f.throwState = 0
        return False
    if code == 8:
        f.poseFrame = f.poseFrame - 1
        if f.poseFrame < 1:
            f.poseFrame = 1
        f.frameStep = -1
        f.anchorDirty = 1
        f.throwState = 0
        f.rootFrame = f.poseFrame
        f.rootMove = move
        f.facing = f.heading
        anchor()
        return False
    if code == 9:
        restart()
        f.trackMode = 5
        f.throwState = 0
        clear_turn()
        f.rootMove = move
        f.facing = f.aimDir
        return True
    if code in (10, 11):
        f.facing = f.heading if code == 10 else f.aimDir
        restart()
        f.rootMove = move
        if ram.u8(move + 0x2D) == 0:
            frames = min(0x10, ram.u8(f.poseMove + 0x18))
        else:
            frames = ram.u8(move + 0x2D) - 1
        f.turnFrames = frames
        if f.turnFrames < 1:
            f.turnFrames = 1
        f.aimDir = f.targetDir if (f.relAngle & 0xFFFF) < 0x4000 else f.targetDir - 0x8000
        f.turnStep = _turn_step(f.aimDir, f.heading, f.turnFrames)
        anchor_if_flagged()
        f.trackMode = 11
        f.throwState = 0
        return False
    if code in (12, 13, 14):
        restart()
        f.rootMove = move
        if f.relAngle < 0x4FA4:
            f.facing, f.trackMode = f.targetDir, {12: 4, 13: 3, 14: 2}[code]
        else:
            f.facing, f.trackMode = f.aimDir, 6
        f.throwState = 0
        clear_turn()
        return True
    if code == 15:
        restart()
        f.trackMode = 1
        f.throwState = 0
        clear_turn()
        f.rootMove = move
        f.facing = f.aimDir
        return True
    if code in (16, 18, 19):
        if code == 16:
            restart()
        else:
            _continue_frames(f)
        f.trackMode = 11
        f.rootMove = move
        f.facing = f.targetDir
        f.throwState = 0
        f.slideState = 1
        f.slideStepX = f.slideStepZ = 0
        if code == 19:
            f.heading = f.heading - 0x8000
        timed_turn(f.targetDir)
        return True
    if code == 17:
        return False
    if code in (20, 21):
        _continue_frames(f)
        f.rootMove = move
        if f.relAngle < 0x4FA4:
            f.trackMode = 4 if code == 20 else 2
        else:
            f.trackMode = 6
        f.throwState = 0
        clear_turn()
        f.anchorDirty = 1
        anchor()
        return False
    if code in (22, 25):
        if code == 25:
            f.throwState = 0
        _continue_frames(f)
        f.trackMode = 8
        f.throwState = 0
        if code == 22:
            clear_turn()
        f.anchorDirty = 1
        f.rootMove = move
        anchor()
        return False
    if code == 23:
        restart()
        f.rootMove = move
        f.facing = f.heading
        anchor_if_flagged()
        f.trackMode = 9
        f.throwState = 0
        return False
    if code == 24:
        restart()
        f.throwState = 0
        f.trackMode = 8
        f.rootMove = move
        f.facing = f.aimDir
        return True
    if code in (26, 27):
        f.poseFrame = f.poseFrame + 1
        f.rootFrame = f.rootFrame + 1
        _clamp_to_length(f)
        f.rootMove = move
        f.facing = f.heading
        f.stepKind = 1 if code == 26 else 2
        return False
    if code == 28:
        restart()
        f.trackMode = 10
        f.throwState = 0
        clear_turn()
        f.facing = f.heading
        f.rootMove = move
        anchor_if_flagged()
        f.stepCooldown = 0x18
        return False
    if code == 29:
        _continue_frames(f)
        f.trackMode = 10
        f.throwState = 0
        clear_turn()
        f.facing = f.heading
        f.rootMove = move
        return True
    if code in (30, 36):
        if code == 30:
            f.airKind = 5
            f.launchArmed = 1
            f.posY = f.rootY
            f.moveSlot = ram.s16(AIR_KINDS + 4 * 5 + 2)
            f.groundOffset = ram.s16(AIR_KINDS + 4 * 5)
        else:
            f.posY = f.rootY
            if f.juggleCount == 0:
                f.airVelX = f.airVelY = f.airVelZ = 0
        launch_trajectory(f)
        f.poseFrame = f.rootFrame = f.entryFrame
        f.airPhase = 1
        f.ballistic = 1
        f.throwState = 0
        f.rootMove = move
        f.juggleCount = f.juggleCount + 1
        _recover_mash(f)
        f.trackMode = 11
        if (ram.u32(f.poseMove + 0x24) >> 8) & 0x10:
            f.facing = f.aimDir + ram.s16(f.reaction + 0x1C)
        else:
            f.facing = f.aimDir
        clear_turn()
        return True
    if code == 33:
        restart()
        f.rootMove = move
        if f.throwState == 0:
            target, side = f.targetDir, f.oppQuadrant
            f.heading = target - 0x8000
            if side == 1:
                f.heading = target - 0x4000
            elif side == 2:
                f.heading = target
            elif side == 3:
                f.heading = target + 0x4000
            f.turnFrames = 0x10
            f.facing = f.heading
            f.turnStep = div_trunc(s16(opp.heading - f.heading), 0x10)
            f.posX, f.posZ = opp.rootX, opp.rootZ
        elif f.throwState < 0 or (ram.u32(move + 0x24) >> 8) & 0x800:
            f.heading = f.facing = opp.facing
            f.posX, f.posZ = opp.rootX, opp.rootZ
        f.pushFrames = f.pushSpeed = f.pushTableFrames = 0
        f.throwState = 1 if f.throwState < 0 else f.throwState + 1
        return False
    if code == 34:
        if f.throwState >= 0:
            pose = f.poseMove
            counter = not ((ram.s16(pose + 0x14) == 0 or ram.u8(pose + 0x2D) <= f.poseFrame)
                           and opp.powerTimer == 0)
            f.set_at(0xBD, "B", 1 if counter else 0)
        restart()
        f.set_at(0x86, "B", 1)
        f.rootMove = move
        if f.throwState < 0:
            if (ram.u32(move + 0x24) >> 8) & 0x800:
                f.facing = f.heading
                anchor()
        else:
            f.heading = f.facing = f.heading - 0x8000
            anchor()
            sound_script_stop(f)
        f.throwState = f.throwState - 1 if f.throwState < 1 else -1
        other = opp.moveRow
        if ram.u8(other + 0x1B) == 0:
            diff = ram.u8(other + 0x18) - ram.u8(move + 0x18)
            f.recoverFrames = ram.u8(other + 0x18) if diff < 1 else ram.u8(move + 0x18) + diff
            if f.recoverFrames < 0:
                f.recoverFrames = 0
            if f.recoverFrames > 300:
                f.recoverFrames = 300
        else:
            f.recoverFrames = ram.u8(other + 0x1B) + ram.u8(move + 0x18)
        mash = div_trunc(ram.s16(other + 0x14) * 0x20, 0x2D) + 0x22
        f.recoverMash = mash
        if s16(mash) > 0x41:
            f.recoverMash = 0x42
        if f.recoverMash < 0x23:
            f.recoverMash = 0x22
        f.pushFrames = f.pushSpeed = f.pushTableFrames = 0
        return False
    if code in (35, 38):
        if code == 38:
            _recover_mash(f)
        _load_push(f, ram.s16(f.reaction + (0x28 if code == 35 else 0x22)))
        restart()
        f.throwState = 0
        f.rootMove = move
        f.pushDir = f.targetDir + ram.s16(f.reaction + 0x1C) - 0x8000
        f.trackMode = 7
        clear_turn()
        f.facing = f.aimDir
        return True
    if code == 37:
        _recover_mash(f)
        _load_push(f, ram.s16(f.reaction + 0x26))
        restart()
        f.recoverMash = 0
        f.throwState = 0
        f.rootMove = move
        f.pushDir = f.targetDir + ram.s16(f.reaction + 0x24) - 0x8000
        f.trackMode = 11
        clear_turn()
        f.facing = f.heading
        return True
    if 39 <= code <= 43:
        _recover_mash(f)
        _load_push(f, ram.s16(f.reaction + 0x1E))
        base = f.aimDir if code == 0x2A else f.targetDir
        f.pushDir = base + ram.s16(f.reaction + 0x1C) - 0x8000
        push_repeat_count(f)
        restart()
        f.throwState = 0
        f.rootMove = move
        f.trackMode = 11
        clear_turn()
        f.facing = f.heading
        return True
    restart()
    f.rootMove = move
    f.facing = f.heading = f.targetDir
    return True


def _finish(f: Fighter) -> None:
    ram = f.ram
    move = f.moveRow
    f.moveRow = 0
    f.poseMove = move
    f.curSlot = f.moveSlot
    f.moveSlot = -1
    segs = 0
    if ram.u8(move + 0x2D):
        desc = ram.u32(move + 0x28)
        segs = 2 if ram.u8(desc + 2) else (1 if ram.u8(desc) else 0)
    f.attackSegCount = segs
    f.moveFrame = 1 if f.moveChanged else f.poseFrame
    f.curTransition = f.transition
    f.transition = f.transBit7 = f.transBit6 = 0
    f.applyEndTurn = 0
    f.inThrow = 1 if f.throwState != 0 else 0
    if f.bankType == 0x13 and f.poseFrame == 1 and ram.u8(f.poseMove + 0x19) != 1:
        f.posY = 0


# ------------------------------------------------------------ branch evaluation

COMMON_ROWS = 0x80017C78
SEQ_TABLE_A = 0x800958F4
SEQ_TABLE_B = 0x800959F0
SITUATION = 0x80095B88
BANK_TABLE = 0x800AE0E8
HISTORY = 0x41C
HIST_LEN = 60
END, CALL, RETURN = 0xC000, 0xC00C, 0xC00D


def hist(f: Fighter, i: int) -> int:
    return f.at(HISTORY + i, "B")


def prev_index(i: int) -> int:
    return i - 1 if i > 0 else HIST_LEN - 1


def buttons_match(spec: int, pressed: int, held: int) -> bool:
    """Shared button test of commands and sequence steps (spec = 5-bit button field)."""
    if spec & 0x1F == 0x10:
        return True
    if spec & 0x10:
        return (pressed & spec & 0xF) != 0
    mask = spec & 0xF
    if mask == 0 and pressed == 0:
        return True
    return (pressed & mask) != 0 and mask == (held & mask)


def double_tap(f: Fighter, direction: int) -> bool:
    """FUN_8002CB08 (direction 6) / FUN_8002CBF0 (direction 4)."""
    i = f.inHistIndex
    if hist(f, i) & 0xF != direction:
        return False
    j = prev_index(i)
    if hist(f, j) & 0xF != 5:
        return False
    budget = 0x13
    k = j
    while True:
        k = prev_index(j)
        d = hist(f, k) & 0xF
        if d != 5:
            if d != direction:
                return False
            break
        budget -= 1
        j = k
        if budget <= 0:
            break
    if budget <= 0:
        return False
    while True:
        m = prev_index(k)
        if hist(f, m) & 0xF != direction:
            break
        budget -= 1
        k = m
        if budget <= 0:
            break
    return budget > 0


def sequence_match(f: Fighter, seq: int) -> bool:
    """InputSequenceMatch (0x8002CCD8)."""
    ram = f.ram
    window = ram.s16(seq)
    steps = []
    p = seq + 2
    while ram.u16(p) != 0:
        steps.append(ram.u16(p))
        p += 2
    idx = f.inHistIndex & 0xFFFFFFFF
    k = len(steps) - 1
    last = steps[k] if steps else 0
    if (last & 0xF) == last:
        pos = idx + 1 if idx < 0x3B else 0
        want = last
    else:
        if (last & 0xF) != (hist(f, idx) & 0xF):
            return False
        if not buttons_match(last >> 8, f.inPressed, f.inHeld):
            return False
        k -= 1
        if k < 0:
            return True
        want = steps[k]
        pos = idx
    while True:
        if window < 1:
            return False
        pos = pos - 1 if pos > 0 else 0x3B
        entry = hist(f, pos)
        hit = False
        if (want & 0xF) == (entry & 0xF):
            spec = want >> 8
            if spec & 0x1F == 0x10:
                hit = True
            elif spec & 0x10:
                hit = (spec & (entry >> 4)) != 0
            else:
                hit = (spec & 0xF) == (entry >> 4)
        if not hit:
            if entry >> 4:
                return False
        else:
            k -= 1
            if k < 0:
                return True
            want = steps[k]
        window -= 1


def input_match(f: Fighter, row: int, direction: int, pressed: int) -> bool:
    """InputMatch (0x8002CE7C)."""
    ram = f.ram
    cmd = ram.u16(row)
    if cmd < 0xC000:
        if (cmd & direction) == 0 and (cmd & 0x3FE0) != 0:
            return False
        if cmd & 0x1F == 0x10:
            return True
        if cmd & 0x10:
            return (cmd & 0xF & pressed) != 0
        mask = cmd & 0xF
        if mask != 0 or pressed != 0:
            if (mask & pressed) == 0:
                return False
            return mask == (f.inHeld & mask)
        return True
    if cmd < 0xC00E:
        if cmd == 0xC001:
            return double_tap(f, 6)
        if cmd == 0xC002:
            return double_tap(f, 4)
        return False
    if cmd < 0xC7FF:
        if cmd - 0xC00E < 0x3F:
            return sequence_match(f, ram.u32(SEQ_TABLE_A + 4 * (cmd - 0xC00E)))
        return False
    if cmd - 0xC7FF < 0x29:
        return sequence_match(f, ram.u32(SEQ_TABLE_B + 4 * (cmd - 0xC7FF)))
    return False


def restriction_ok(f: Fighter, opp: Fighter, value: int) -> bool:
    if value == 0:
        return True
    if value < 0x18:
        return f.bankType == value - 1
    if value < 0x2F:
        return (value - 0x18) != f.bankType
    if value < 0x46:
        return opp.bankType == value - 0x2F
    if value < 0x5D:
        return f.charId == value - 0x46
    return (value - 0x5D) != f.charId


def situation_classify(f: Fighter, opp: Fighter) -> None:
    """SituationClassify (0x800313B0)."""
    code = -1
    if f.contact and opp.inAir == 0 and opp.aboutToHit == 0:
        q = f.oppQuadrant
        if f.relAngle < 0x2AAA:
            state = opp.state
            table = None
            if state & 0x80:
                table = (10, 12, 11, 13) if not state & 0x200 else (14, 16, 15, 17)
            elif state & 0x40:
                table = (2, 4, 3, 5)
            elif state & 0x20:
                table = (6, 8, 7, 9)
            if table is not None and 0 <= q <= 3:
                code = table[q]
        elif f.relAngle > 0x5555 and opp.state & 2:
            code = {0: 0x12, 2: 0x13}.get(q, -1)
    f.ram.put(SITUATION + 4 * f.index, "i", code)


def branch_condition(ram: Ram, row: int, f: Fighter, opp: Fighter) -> bool:
    """BranchCondition (0x8002E310), types 0x00-0x44."""
    kind = ram.u8(row + 3)
    param = ram.u16(row + 4)
    sit = SITUATION + 4 * f.index
    if kind == 0:
        return True
    if kind == 1:
        return f.contact != 0
    if 2 <= kind <= 0x17:
        if ram.s32(sit) == 0:
            situation_classify(f, opp)
        if kind <= 0x13:
            return (f.distAdj & 0xFFFFFFFF) <= param and kind == ram.u32(sit)
        if param < (f.distAdj & 0xFFFFFFFF):
            return False
        code = ram.s32(sit)
        return code in {0x14: (2, 6), 0x15: (3, 7), 0x16: (4, 8), 0x17: (5, 9)}[kind]
    if kind == 0x18:
        return not (param < (f.dist & 0xFFFFFFFF))
    if kind == 0x19:
        return not ((f.dist & 0xFFFFFFFF) < param)
    if kind == 0x1A:
        return f.contact != 0 and (f.attack & opp.guard) == 0
    if kind == 0x1B:
        return opp.guarded != 0
    if kind == 0x1C:
        return f.whiffed != 0
    if kind == 0x1D:
        return opp.transition != 0x21
    if kind == 0x1E:
        return opp.damage != 0
    if kind == 0x1F:
        return opp.damage != 0 and (opp.state & 7) == 2
    if kind == 0x20:
        return opp.damage != 0 and (opp.state & 7) == 1
    if kind == 0x21:
        return opp.damage == 0
    if kind == 0x22:
        return (opp.state & 0x407) == 2
    if kind == 0x23:
        return (opp.state & 0x407) == 1
    if kind == 0x24:
        return not (f.relAngle < 0x4001)
    if kind == 0x25:
        return ((f.headingDelta - 0x4E38) & 0xFFFF) < 0x31C8
    if kind == 0x26:
        return (f.headingDelta & 0xFFFF) > 0x7FFF and not ((f.headingDelta & 0xFFFF) > 0xB1C6)
    if 0x27 <= kind <= 0x2A:
        return f.facingQuadrant == {0x27: 0, 0x28: 1, 0x29: 3, 0x2A: 2}[kind]
    if 0x2B <= kind <= 0x2E:
        return f.oppQuadrant == {0x2B: 0, 0x2C: 1, 0x2D: 3, 0x2E: 2}[kind]
    if kind == 0x2F:
        return False
    if kind == 0x30:
        return (opp.attack == 0x412 and opp.poseFrame <= ram.u8(opp.poseMove + 0x2E)
                and (f.dist & 0xFFFFFFFF) < 0x700)
    if kind == 0x31:
        return f.at(0x118, "i") == 0
    if kind == 0x32:
        return f.at(0x118, "i") != 0
    if kind == 0x33:
        return f.at(0xD5, "B") != 0
    if kind == 0x34:
        return f.at(0xD5, "B") != 0 and opp.inAir == 0 and (opp.state & 4) == 0
    if kind == 0x35:
        return (opp.state & 4) != 0
    if kind == 0x36:
        return (opp.state & 4) == 0
    if kind == 0x37:
        if (opp.state & 4) == 0 or ram.u8(opp.poseMove + 0x19) != 0:
            return False
        return not (param < (f.dist & 0xFFFFFFFF))
    if kind == 0x38:
        return (opp.state & 4) != 0 and not (f.relAngle < 0x4000)
    if kind == 0x39:
        return opp.counterHit != 0 and opp.inAir == 0
    if kind in (0x3A, 0x3B, 0x3C):
        f.condFlagUsed = 1
        return f.at(0xE0 + kind - 0x3A, "B") != 0
    if kind == 0x3D:
        return f.health == 0
    if kind == 0x3E:
        return f.sideFlag == 0
    if kind == 0x3F:
        return f.sideFlag != 0
    if kind in (0x40, 0x41):
        if (f.sideFlag != 0) != (kind == 0x41):
            return False
        return not (f.relAngle < 0x4001)
    if kind == 0x42:
        return f.launchArmed == 0 and f.health != 0
    if kind == 0x43:
        return f.powerTimer != 0
    if kind == 0x44:
        return f.powerTimer == 0
    return False


def branch_find(f: Fighter, opp: Fighter, rows: int, frame: int) -> int:
    """BranchFind (0x8002E078): address of the matching row, or of the list terminator."""
    ram = f.ram
    direction, pressed = f.inDir, f.inPressed
    ram.put(SITUATION + 4 * f.index, "i", 0)
    ret = 0
    while True:
        match = None
        while True:
            cmd = ram.u16(rows)
            if cmd == END:
                match = rows
                break
            if cmd == RETURN:
                rows = ret + 12
                continue
            if cmd == CALL:
                ret = rows
                row = COMMON_ROWS + 12 * ram.u16(rows + 6)
            else:
                row = rows
            if (input_match(f, row, direction, pressed) and ram.u8(row + 9) <= frame <= ram.u8(row + 10)
                    and restriction_ok(f, opp, ram.u8(row + 2)) and ram.u8(row + 3) < 0x45
                    and (ram.u8(row + 3) == 0 or branch_condition(ram, row, f, opp))):
                match = row
                break
            rows = row + 12
        flag = ram.u8(match + 8)
        if flag == 0x2C:
            while ram.u16(match) != END:
                match += 12
            flag = ram.u8(match + 8)
        at_end = ram.u16(match) == END
        skip_step = flag == 0x1C and not at_end and f.stepCooldown != 0
        skip_throw = (ram.s32(GAME_MODE) == 8 and ram.u8(match + 8) == 0x21 and not at_end
                      and f.inThrow == 0 and opp.inThrow != 0)
        if not (skip_step or skip_throw):
            return match
        rows = match + 12


def move_lookup(f: Fighter, slot: int) -> int:
    ram = f.ram
    bank = ram.u32(BANK_TABLE + 4 * f.playerIndex)
    return ram.u32(ram.u32(bank + 0xC) + 4 * s16(slot))


def _remap(f: Fighter, code: int) -> int:
    move = f.moveRow
    ram = f.ram
    info = {"length": ram.u8(move + 0x18), "activeStart": ram.u8(move + 0x2D), "activeEnd": ram.u8(move + 0x2E)}
    return fight_math.transition_remap(code, info, f.entryFrame)


def move_branch_step(f: Fighter, opp: Fighter) -> None:
    """MoveBranchStep (0x8002DC3C)."""
    ram = f.ram
    f.branchWindow = -1
    if f.moveRow != 0 or f.stepCooldown > 0x19:
        return
    row = branch_find(f, opp, ram.u32(f.poseMove + 0xC), f.poseFrame)
    if ram.u16(row) != END:
        f.moveSlot = ram.s16(row + 6)
        f.moveRow = move_lookup(f, f.moveSlot)
        f.branchWindow = ram.u8(row + 10) - f.poseFrame
        flags = ram.u8(row + 8)
        f.transition = _remap(f, flags & 0x3F)
        f.transBit7 = flags >> 7
        f.transBit6 = (flags >> 6) & 1
        f.entryFrame = ram.u8(row + 10) if f.frameStep < 0 else ram.u8(row + 11)
        if (f.entryFrame & 0xFFFF) == 0xFF:
            f.entryFrame = ram.u8(f.poseMove + 0x18)
        f.branchKind = 2
        return
    first, last = ram.u8(row + 9), ram.u8(row + 10)
    look = False
    if f.poseFrame < first - 5:
        look = False
        early = False
    else:
        early = True
    if early and f.poseFrame < first:
        look = f.frameStep >= 1 and (hist(f, f.inHistIndex) & 0xF0) != 0
    if not look and first <= f.poseFrame and f.poseFrame <= last and f.frameStep > 0:
        look = True
    if not look and ram.s32(GAME_MODE) == 7:
        # Tekken Ball: the continuation may look ahead from a per-player frame of volley.ovl.
        start = ram.u8(BALL_DRIFT + 6 * f.playerIndex + 5)
        look = start != 0 and f.poseFrame >= start and f.frameStep >= 1
    if look:
        target = move_lookup(f, ram.s16(row + 6))
        heading = f.heading
        f.heading = heading + ram.s16(f.poseMove + 0x12)
        relative_angles(f, opp)
        found = branch_find(f, opp, ram.u32(target + 0xC), 1)
        f.heading = heading
        relative_angles(f, opp)
        if ram.u16(found) != END:
            f.moveSlot = ram.s16(found + 6)
            f.moveRow = move_lookup(f, f.moveSlot)
            f.entryFrame = first
            f.transBit6 = (ram.u8(row + 8) >> 6) & 1
            f.branchWindow = ram.u8(found + 10) - f.poseFrame
            flags = ram.u8(found + 8)
            f.transition = _remap(f, flags & 0x3F)
            f.applyEndTurn = 1
            f.branchKind = 3
            f.transBit7 = flags >> 7
            return
    frame = f.poseFrame + f.frameStep
    if ram.u8(f.poseMove + 0x18) < frame or frame < 1:
        f.entryFrame = f.poseFrame
        f.moveSlot = ram.s16(row + 6)
        f.moveRow = move_lookup(f, f.moveSlot)
        flags = ram.u8(row + 8)
        f.transition = _remap(f, flags & 0x3F)
        f.transBit7 = flags >> 7
        f.applyEndTurn = 1
        f.branchKind = 4
        f.transBit6 = (flags >> 6) & 1


# --------------------------------------------------------------- move physics

STEP_ACCUM_X = 0x8009E9A8          # s32[2] per-player 24.8 remainders of move step displacement
STEP_ACCUM_Z = 0x8009E9B8
FACE_TABLE_A = 0x80095D74          # u8[0x37] per costume: face shape while attacking
FACE_TABLE_B = 0x80095DA8          # u8[0x37] per costume: face shape on a clean hit
FIGHTERS = 0x800A96F0
CAMERA_SHAKE = 0x80097EC4          # current camera shake script (s8 pitch offsets, -128 ends)
CAMERA_SHAKE_TABLE = 0x80097EC8
FACE_TIMER = 0x80097350
LANDING_GROUND = 1                 # airKind that rumbles on landing


def sinq(angle: int) -> int:
    return fight_math.sin_q15(angle, exe())


def cosq(angle: int) -> int:
    return fight_math.cos_q15(angle, exe())


def polar(length: int, angle: int) -> tuple[int, int]:
    """(length * sin / 0x7FFF, length * cos / 0x7FFF) in 32-bit C arithmetic."""
    return div_trunc(w32(length * sinq(angle)), 0x7FFF), div_trunc(w32(length * cosq(angle)), 0x7FFF)


def fighter_opponent(f: Fighter) -> Fighter:
    """FighterOpponent (0x80045EB0)."""
    if f.inThrow:
        i = f.throwPartner
    elif f.wasHitThisMove:
        i = f.lastAttacker
    elif f.contact:
        i = f.lastHitTarget
    else:
        i = f.oppIndex
    return Fighter(f.ram, FIGHTERS + FIGHTER_SIZE * i)


def camera_shake(ram: Ram, script: int) -> None:
    """FUN_8004AF94: start camera shake script n; the pad rumble of VibrateAll is not modelled."""
    ram.put(CAMERA_SHAKE, "I", ram.u32(CAMERA_SHAKE_TABLE + 4 * script))


def hand_face_command(f: Fighter, hands: int, shape: int, speed: int) -> None:
    """HandFaceCommand (0x800346F8); the face texture upload for shapes 10/11 is not modelled."""
    if shape >= 10:
        index = shape - 10
        if index < 2:
            f.set_at(0x128E, "h", speed)
            if f.at(0x1290, "B") != index & 0xFF:
                f.set_at(0x1290, "B", index)
        return
    if shape >= 8:
        return
    if f.charId == 0x14:
        if speed == 0:
            speed = 1
        rate = div_trunc(0x100, 1 - speed) if speed < 0 else div_trunc(0x100, speed + 1)
        f.set_at(0x129A, "h", 0)
        level = f.at(0x1296, "h")
        if shape in (2, 3):
            f.set_at(0x1298, "h", 0x100)
            if level < 0x100:
                f.set_at(0x129A, "h", rate)
        else:
            f.set_at(0x1298, "h", 0)
            if level > 0:
                f.set_at(0x129A, "h", rate)
        f.set_at(0x1280, "h", 0x100 if shape == 2 else 0)
        f.set_at(0x1284, "h", rate)
        return
    for i in range(2):
        if (i + 1) & hands:
            target = 0 if shape == 0 else (0x200 if shape == 1 else shape + 0x1FF)
            base = 2 * i
            if f.at(0x127C + base, "h") < 0x201 and target < 0x201:
                if speed != 0:
                    rate = div_trunc(0x200, 1 - speed) if speed < 0 else div_trunc(0x200, speed + 1)
                    f.set_at(0x1284 + base, "h", rate)
            else:
                f.set_at(0x127C + base, "h", target)
                f.set_at(0x1284 + base, "h", 0)
            f.set_at(0x1280 + base, "h", target)


def _face_shape(f: Fighter, table: int) -> int:
    """FUN_800364E8 / FUN_80036518: per-costume byte, 0 for out-of-range slots."""
    slot = f.costumeSlot
    return f.ram.u8(table + slot) if 0 <= slot < 0x37 else 0


def clamp_symmetric(v: int, limit: int) -> int:
    """ClampSymmetric (0x80040B58)."""
    v = s16(v)
    if v < 0:
        return s16(-limit) if v < -limit else v
    return s16(limit) if limit < v else v


def track_budget(step: int, accum: int, limit: int) -> int:
    """TrackBudget (0x80040B9C): the step clipped to the remaining budget, 0 while within it."""
    a, step = abs(s16(accum)), s16(step)
    if limit < a + abs(step):
        rest = s16(limit - a)
        return -rest if step < 0 else rest
    return 0


def _degrees(d: int) -> int:
    return div_trunc(d * 0xFFFF, 0x168)


def _towards(target: int, current: int, frames: int) -> int:
    return s16(div_trunc(s16(target - current), frames))


def move_physics(f: Fighter) -> list[tuple]:
    """FighterMovePhysics (0x8003F330). Returns side effects outside the fighter record:
    ("camera_shake", n) and ("landing_dust", root pointer). Tekken Ball (mode 7) push is not ported."""
    ram = f.ram
    events: list[tuple] = []
    opp = fighter_opponent(f)
    f.landedA = f.landedB = f.aboutToHit = 0
    relative_angles(f, opp)
    if f.slideState == 1:
        root = f.rootMove
        if ram.u8(root + 0x19) <= f.poseFrame:
            frames = ram.u8(root + 0x1A) - f.poseFrame or 1
            f.slideState = 2
            dist = ram.u32(FIGHTER_DISTANCE)
            total = 0xA0C if dist > 0xC00 else w32(dist - 500)
            f.slideStepX, f.slideStepZ = polar(s16(div_trunc(total, frames)), f.targetDir)
            f.airPhase = 2
    elif f.slideState == 2:
        f.posZ = f.posZ + f.slideStepZ
        f.posX = f.posX + f.slideStepX
        if ram.u8(f.rootMove + 0x1A) <= f.poseFrame:
            f.slideState = 0
            f.slideStepX = f.slideStepZ = 0
            f.posX, f.posZ = f.rootX, f.rootZ
    if f.ballistic == 0 or (f.hitFreeze != 0 and opp.bankType == 0xE):
        pose = f.poseMove
        first = ram.u8(pose + 0x19)
        step = ram.s16(pose + 0x16)
        if first != 0 and first - 1 <= f.poseFrame <= ram.u8(pose + 0x1A) and step != 0:
            ax, az = STEP_ACCUM_X + 4 * f.index, STEP_ACCUM_Z + 4 * f.index
            old_x, old_z = f.posX, f.posZ
            dx, dz = polar(step, f.facing)
            ram.put(ax, "I", ram.s32(ax) + dx)
            ram.put(az, "I", ram.s32(az) + dz)
            f.posX = f.posX - (ram.s32(ax) >> 8)
            f.posZ = f.posZ - (ram.s32(az) >> 8)
            ram.put(ax, "I", ram.s32(ax) + w32(w32(f.posX - old_x) * 0x100))
            ram.put(az, "I", ram.s32(az) + w32(w32(f.posZ - old_z) * 0x100))
    else:
        f.airVelY = f.airVelY + 6
        f.posY = f.posY + f.airVelY
        f.posX = f.posX + f.airVelX
        f.posZ = f.posZ + f.airVelZ
        f.airVelX, f.airVelZ = polar(f.airSpeed, f.targetDir + 0x8000)
        if f.airVelY > 0 and -f.groundOffset <= f.posY:
            if f.airKind == LANDING_GROUND:
                camera_shake(ram, 1)
                events.append(("camera_shake", 1))
            f.posZ, f.posY, f.posX = f.rootZ, 0, f.rootX
            if f.airKind == 5:
                f.landedA = 1
            else:
                f.landedB = 1
            f.ballistic = 0
            f.airPhase = 2
    if f.charId == 0x11 and f.inReaction and f.juggleCount == 0:
        if f.inAir == 0:
            f.posY = 0
        else:
            y = w32(f.rootY + 0x80)
            if y < 0:
                f.posY = y >> 1
    if ram.s32(GAME_MODE) == 7:
        # Tekken Ball: volley.ovl drift of the anchor (s16 angle offset, u8 speed, u8 frame window).
        drift = BALL_DRIFT + 6 * f.playerIndex
        speed = ram.u8(drift + 2)
        if speed and ram.u8(drift + 3) <= f.poseFrame <= ram.u8(drift + 4):
            angle = f.targetDir + ram.s16(drift)
            f.posX = w32(f.posX + div_trunc(speed * sinq(angle), 0x7FFF))
            f.posZ = w32(f.posZ + div_trunc(speed * cosq(angle), 0x7FFF))
    if f.inAir == 0:
        f.launchArmed = 0
    if f.turnFrames != 0:
        f.turnFrames = f.turnFrames - 1
        f.heading = f.heading + f.turnStep
        if f.throwState == 1:
            f.facing = f.heading
    if f.slideToPoint == 1:
        f.slideToPoint = 0
        dz = w32(f.rootZ - f.slideTargetZ)
        dx = w32(f.rootX - f.slideTargetX)
        f.pushDir = fight_math.atan2_angle(dz, dx, exe())
        f.pushFrames = 0x10
        dist = fight_math.isqrt(w32(dx * dx + dz * dz) & 0xFFFFFFFF)
        f.pushSpeed = div_trunc(dist, f.pushFrames)
        ox, oz = polar(dist, f.pushDir + 0x8000)
        f.posX = f.rootX - ox
        f.posZ = f.rootZ - oz
    push = 0
    if f.pushFrames > 0:
        push = f.pushSpeed
        f.pushFrames = f.pushFrames - 1
    if f.pushTableFrames > 0:
        f.pushTableFrames = f.pushTableFrames - 1
        push += ram.s16(f.pushTable)
        f.pushTable = f.pushTable + 2
        if f.pushRepeat > 0:
            push += f.pushRepeat * 0x28 + 10
    if push != 0:
        px, pz = polar(push, f.pushDir)
        f.posX = f.posX + px
        f.posZ = f.posZ + pz
    _tracking(f, opp)
    if f.attackAlert > 0:
        f.attackAlert = f.attackAlert - 1
    if f.hitCooldown > 0:
        f.hitCooldown = f.hitCooldown - 1
    pose = f.poseMove
    if f.poseFrame < ram.u8(pose + 0x2D) or ram.u8(pose + 0x2E) < f.poseFrame:
        f.activeSegs = 0
    else:
        f.activeSegs = 2 if ram.u8(ram.u32(pose + 0x28) + 2) else 1
    f.forcedHit = 0
    if ram.s32(GAME_MODE) == 8:
        if f.isCpu:
            if f.throwState < 0 and 10 < f.poseFrame < ram.u8(pose + 0x18):
                speed = fight_math.isqrt(w32(f.velX * f.velX + f.velY * f.velY + f.velZ * f.velZ) & 0xFFFFFFFF)
                if speed > 0x59:
                    f.forcedHit, f.attackHi, f.attack = 1, 6, 0x607
                    f.damage = (speed >> 4) + 10
        elif (ram.u32(pose + 0x24) >> 8) & 0x100:
            f.forcedHit, f.attackHi, f.attack, f.damage = 1, 6, 0x607, 10
            if f.moveChanged and f.health > 0xA0000:
                f.health = f.health - 0xA0000
    if f.juggleCount != 0 or ram.u8(pose + 0x19) <= f.poseFrame <= ram.u8(pose + 0x1A):
        f.inAir = 1
    else:
        f.inAir = 0
    if (f.poseFrame == ram.u8(pose + 0x1A) and f.holdFrames == -1 and f.poseFrame != 1
            and f.airPhase != 2):
        if f.wasHitThisMove == 0 or f.airKind == 5 or (f.stateClass != 9 and f.state & 4 == 0):
            f.landedA = 1
        else:
            f.landedB = 1
    if f.recoverFrames != 0:
        f.recoverFrames = f.recoverFrames - 1
        if f.recoverFrames < 0 or f.hitClean:
            f.recoverFrames = 0
    if f.recoverFrames < 0x1F and f.recoverMash != 0:
        entry = hist(f, f.inHistIndex)
        mash = 3 if entry & 0x20 else (1 if entry & 0xF0 else 0)
        f.recoverMash = f.recoverMash - 1 - mash
        if f.recoverMash < 0:
            f.recoverMash = 0
    if f.damage != 0:
        active = ram.u8(pose + 0x2D)
        low = active - 3 if active >= 3 else 1
        if low <= f.poseFrame <= active:
            f.aboutToHit = 1
    if (ram.u32(pose + 0x24) >> 8) & 4:
        f.aboutToHit = 1
    if f.charId == 0x11 and opp.charId != 0x11:
        f.aboutToHit = 1
    _guard_state(f)
    if f.stateClass == 9:                          # FUN_80040C04
        first = ram.u8(f.poseMove + 0x19)
        if first != 0 and first <= f.poseFrame:
            f.state = f.state | 4
    if f.hitClean:
        hand_face_command(f, 3, _face_shape(f, FACE_TABLE_B), 10)
    elif f.at(0xBC, "B") == 0:
        if (f.moveChanged and f.damage == 0 and f.inReaction == 0
                and (ram.s32(FACE_TIMER) - 1) & 0xFFFFFFFF < 2):
            hand_face_command(f, 3, _face_shape(f, FACE_TABLE_A), 10)
        if f.damage != 0 and ram.u8(f.poseMove + 0x2D) - f.poseFrame < 8:
            hand_face_command(f, 3, _face_shape(f, FACE_TABLE_A), 10)
    f.set_at(0x12D0, "I", 1 if (f.hitFreeze != 0 and opp.bankType == 0xE) else 0)
    f.set_at(0x128A, "B", 1 if (f.inReaction == 0 and f.inAir != 0) else 0)
    if f.hitClean == 0 and opp.hitClean == 0:
        if f.powerTimer != 0:
            f.powerTimer = f.powerTimer - 1
            f.guard = f.guard & 0xFFE7
            if f.powerTimer < 0:
                f.powerTimer = 0
    else:
        f.powerTimer = 0
    if f.inAir:
        f.pushRepeatTimer = 0
    if f.pushRepeatTimer < 1:
        f.pushRepeatTimer = 0
    else:
        f.pushRepeatTimer = f.pushRepeatTimer - 1
    if f.pushRepeatTimer == 0:
        f.pushRepeat = 0
    if ram.s32(GAME_MODE) == 8:
        f.set_at(0xC9, "B", 0 if (f.isCpu == 0 and f.fixedFacing == 0) else 1)
    if f.active and f.landedB:
        events.append(("landing_dust", f.base + FIELDS["rootX"][0]))
        camera_shake(ram, 0)
        events.append(("camera_shake", 0))
    return events


def _set_guard_state(f: Fighter, state: int) -> None:
    f.state = state
    f.guard = state & 0x18


def _guard_state(f: Fighter) -> None:
    """Guard stance from the stick while a move allows it (flag 0x4000 or a sidestep)."""
    pose = f.poseMove
    direction = hist(f, f.inHistIndex) & 0xF
    if not (f.ram.u32(pose + 0x24) >> 8) & 0x40:
        if f.stepKind:
            if direction == 4:
                _set_guard_state(f, 0x1052)
            elif direction == 1:
                _set_guard_state(f, 0x2829)
            else:
                _set_guard_state(f, f.ram.s16(pose + 4))
                if f.state & 0x100 and f.humanGuard == 0:
                    f.state = f.state & 0xFFFFFFE7
    elif f.humanGuard == 0:
        if direction == 4:
            _set_guard_state(f, 0x1052)
        elif direction == 1:
            _set_guard_state(f, 0x2829)
    elif direction in (4, 5):
        _set_guard_state(f, 0x1052)
    elif direction in (1, 2):
        _set_guard_state(f, 0x2829)
    f.guard = f.state & 0x18 if (f.inAir == 0 and f.relAngle < 0x4000) else 0


def _track_step(f: Fighter, step: int, budget: int, set_facing: bool = False) -> None:
    over = track_budget(step, f.trackAccum, budget)
    if over:
        f.trackMode = 6
        step = over
    accum = f.trackAccum
    f.heading = f.heading + step
    if set_facing:
        f.facing = f.heading
    f.trackAccum = accum + step
    if f.ram.u8(f.poseMove + 0x2D) <= f.poseFrame:
        f.trackMode = 6


def _timed_turn(f: Fighter) -> None:
    f.turnFrames = f.ram.u8(f.poseMove + 0x2D) - (f.poseFrame & 0xFFFF)
    if f.turnFrames < 1:
        f.turnFrames = 1
    f.turnStep = clamp_symmetric(_towards(f.targetDir, f.heading, f.turnFrames), 0x9F4)
    f.trackMode = 12


def _tracking(f: Fighter, opp: Fighter) -> None:
    """Heading tracking by trackMode (move +0x1C); 12 = timed turn in progress, others idle."""
    ram = f.ram
    pose = f.poseMove
    mode = f.trackMode
    remaining = s16(ram.u8(pose + 0x2D) + 1 - (f.poseFrame & 0xFFFF))
    if remaining < 1:
        remaining = 1
    alert = opp.attackAlert != 0 and f.attackSegCount != 0
    if mode == 0:
        f.heading = f.facing
    elif mode == 1:
        step = clamp_symmetric(_towards(f.aimDir, f.heading, remaining), 0x1555)
        _track_step(f, step, 0x7FFF, set_facing=True)
    elif mode in (2, 3):
        if alert and f.moveFrame < 9:
            _timed_turn(f)
            return
        degrees = 1 if f.inAir else (0xE if f.moveFrame > 7 else 3)
        limit = _degrees(degrees)
        limit = s16(w32(limit << 16) >> 17) if mode == 3 else s16(limit)
        _track_step(f, clamp_symmetric(_towards(f.targetDir, f.heading, remaining), limit), 0x5555)
    elif mode == 4:
        if f.turnFrames == 0 and not alert:
            degrees = 1 if f.inAir else (3 if f.moveFrame > 7 else 2)
            step = clamp_symmetric(_towards(f.targetDir, f.heading, remaining), s16(_degrees(degrees)))
            _track_step(f, step, 0xE38)
    elif mode == 5:
        if not alert or f.moveFrame > 8:
            degrees = 4 if f.inAir else (100 if f.moveFrame > 7 else 3)
            step = clamp_symmetric(_towards(f.targetDir, f.heading, remaining), s16(_degrees(degrees)))
            _track_step(f, step, 0x9554)
        else:
            _timed_turn(f)
    elif mode == 6:
        if f.damage == 0 or ram.u8(pose + 0x19) == 0 or f.inAir or f.poseFrame < ram.u8(pose + 0x2E):
            frame, active = f.poseFrame, ram.u8(pose + 0x2D)
            if active < frame and (frame - active) % 5 == 0 and f.relAngle < 0x5556:
                length = ram.u8(pose + 0x18)
                f.turnFrames = 5 if length - frame < 6 else length - frame
                if f.turnFrames < 0:
                    f.turnFrames = 0
                else:
                    f.turnStep = clamp_symmetric(_towards(f.aimDir, f.heading, f.turnFrames), 0x222)
        else:
            f.turnFrames = f.turnStep = 0
    elif mode == 7:
        end = ram.u8(pose + 0x1A) or ram.u8(pose + 0x18)
        if f.poseFrame <= end:
            delta = s16(div_trunc(s16(f.aimDir - f.heading) * f.poseFrame, end or 1))
            f.heading = f.heading + clamp_symmetric(delta, 0x38E)
    elif mode == 8:
        frames = min(f.moveFrame, 8)
        delta = s16(div_trunc(s16(f.aimDir - f.heading) * frames, 8))
        f.heading = f.heading + clamp_symmetric(delta, 0x71C)
    elif mode == 9:
        if ram.u32(FIGHTER_DISTANCE) > 0x4AF:
            aim = fight_math.atan2_angle(w32(f.oppStartZ - f.rootZ), w32(f.oppStartX - f.rootX), exe())
            diff = ((f.facing & 0xFFFF) - aim) & 0xFFFFFFFF
            if diff & 0x8000:
                diff = ~diff
            if diff & 0xFFFF > 0x3FFF:
                aim -= 0x8000
            delta = s16(div_trunc(s16(aim - (f.facing & 0xFFFF)) * f.poseFrame, ram.u8(pose + 0x18)))
            f.facing = f.facing + clamp_symmetric(delta, 0x5B0)
            f.anchorDirty = 1
            f.heading = f.facing
    elif mode == 10:
        length = ram.u8(pose + 0x18)
        if f.poseFrame <= length:
            if f.charId == 7 and f.facingQuadrant == 2:
                side = 0x71C if f.rootDx < 0 else -0x71C
            else:
                side = -0x11C7 if f.rootDx < 0 else 0x11C7
            f.anchorDirty = 1
            f.facing = f.aimDir + s16(div_trunc(side * f.poseFrame, length))
            f.heading = f.facing


# --------------------------------------------------------------- arena bounds

BOUND_RAMP = 0x80097E68            # s32[3] per fighter: max correction per frame (FUN_800431D8 ramps it to 2000)
BOUND_RAMP_STEP = 0x80097E74       # s32[3]: ramp increment, +2 per frame
THROW_LINK = 0x80097E80            # move the throw partner with the fighter
THROW_COUNT = 0x800958C4           # s8: fighters currently in a throw (FUN_80045B10)
ARENA_HALF = 300000
FOLLOW_START = 0x1CFF
FOLLOW_MAX = 0x1E00


def _excess(v: int, limit: int) -> int:
    """Correction that brings v back inside [-limit, limit] (0 when inside)."""
    over = abs(v) - limit
    if over <= 0:
        return 0
    return -over if v > 0 else over


def _clamp_ramp(v: int, limit: int) -> int:
    if limit < abs(v):
        return -limit if v < 1 else limit
    return v


FORCE_VIEW_X = 0x800B70F0          # force.ovl: the camera's view-space x of this frame
FORCE_WALLS = 0x800B6AE8           # force.ovl: slope, offset pairs for x = z·k/1000 + c (FUN_800B2F98)


def _force_line(ram: Ram, pair: int, v: int) -> int:
    """force.ovl FUN_800B3020 / FUN_800B309C: v·k/1000 + c."""
    return w32(div_trunc(w32(v * ram.s32(pair)), 1000) + ram.s32(pair + 4))


def _force_walls(ram: Ram, f: Fighter) -> tuple[int, int]:
    """The Tekken Force walls of ArenaBounds: z between -0x898 (on stage 18 a line of x) and
    0x8FC; the player's x between two lines of z relative to the camera, a CPU enemy within
    0x1068 of the camera."""
    dz = dx = 0
    z = f.rootZ
    if w32(z - 0x8FC) > 0:
        dz = w32(-(z - 0x8FC))
    v = w32(z + 0x898)
    if ram.u16(0x800AE14C) == 0x12:
        v = w32(f.rootZ - _force_line(ram, FORCE_WALLS + 0x10, w32(f.rootX - ram.s32(FORCE_VIEW_X))))
    if v < 0:
        dz = w32(-v)
    view = ram.s32(FORCE_VIEW_X)
    if f.at(0xC5, "B") == 0:
        rel = w32(f.rootX - view)
        lo = _force_line(ram, FORCE_WALLS, f.rootZ)
        hi = _force_line(ram, FORCE_WALLS + 8, f.rootZ)
        if w32(rel - lo) < 0:
            dx = w32(-(rel - lo))
        v = w32(rel - hi)
    else:
        t = w32(w32(f.rootX + 0x1068) - view)
        if t < 0:
            dx = w32(-t)
        v = w32(w32(f.rootX - 0x1068) - view)
    if v > 0:
        dx = w32(-v)
    return dz, dx


def arena_bounds(f: Fighter) -> None:
    """ArenaBounds (0x80043394); mode 8 reads its wall lines from force.ovl."""
    ram = f.ram
    mode = ram.s32(GAME_MODE)
    opp = fighter_opponent(f)
    dx = dy = dz = 0
    if mode == 7:
        dz = _excess(f.rootZ, 0x100)
        dx = _excess(f.rootX, 0x1400)
        x = f.rootX
        if (f.index == 0 and x >= 0) or (f.index == 1 and x < 1):
            dx = -x
            if abs(x) > 1000:
                f.state = 0x5000
                f.hitDone1 = f.hitDone0 = 0
                f.set_at(0xD9, "B", 1)
        if -0x1200 - f.rootY > 0:
            dy = -0x1200 - f.rootY
    elif mode == 8 and ram.s16(0x800AE6CC) != 6 and ram.s32(0x80097350) != 0:
        dz, dx = _force_walls(ram, f)
    else:
        dx = _excess(f.rootX, ARENA_HALF)
        dz = _excess(f.rootZ, ARENA_HALF)
        if FOLLOW_START < f.dist:
            ex, ez = w32(opp.placedX - f.rootX), w32(opp.placedZ - f.rootZ)
            d = fight_math.sqrt_table(w32(ex * ex + ez * ez), exe())
            if d < FOLLOW_MAX + 1:
                if f.dist <= d:
                    dx = w32(f.placedX - f.rootX)
                    dz = w32(f.placedZ - f.rootZ)
            else:
                dx, dz = polar(w32(d - FOLLOW_MAX), f.targetDir)
    ramp = BOUND_RAMP + 4 * f.index
    if mode == 7 and f.throwState < 0:
        ram.put(ramp, "i", 0)
        ram.put(BOUND_RAMP_STEP + 4 * f.index, "i", 0)
    limit = ram.s32(ramp)
    dx, dy, dz = (_clamp_ramp(v, limit) for v in (dx, dy, dz))
    movers = [f]
    if f.inThrow and opp.inThrow and ram.s32(THROW_LINK) != 0:
        movers.append(opp)
    for m in movers:
        m.posX, m.posZ, m.posY = m.posX + dx, m.posZ + dz, m.posY + dy
        m.rootX, m.rootZ, m.rootY = m.rootX + dx, m.rootZ + dz, m.rootY + dy


# --------------------------------------------------------------- body separation

PAIR_DISTANCE = 0x8009EA08         # u32 per fighter pair (index bit sum * 0x10)
PREV_ROOT = 0x8009EAA0             # per fighter 0x10 bytes: previous root x/y/z as u16 at +4/+8/+0xC
BODY_POINTS = 0x324                # 8 x 16 bytes: x, y, z (u16 at +0/+4/+8), radius (u16 at +0xC)
BODY_POINT_COUNT = 8
SEPARATION_RANGE = 3000
FRONT_REACH = 200
FRONT_NEAR = 500
CHARGE_OVERLAP = 400
HEIGHT_GAP = 299


def _body_points(f: Fighter) -> list[tuple[int, int, int, int]]:
    return [tuple(f.at(BODY_POINTS + 16 * i + k, "H") for k in (0, 4, 8, 12)) for i in range(BODY_POINT_COUNT)]


def _axis_angle(facing: int) -> int:
    """0x400 - facing / 16 (4096-unit angle of the facing vector, not masked)."""
    return 0x400 - div_trunc(s16(facing), 16)


def _deepest_overlap(a: Fighter, b: Fighter) -> int:
    ex = exe()
    best = 0
    other = _body_points(b)
    for ax, ay, az, ar in _body_points(a):
        if ar == 0:
            continue
        for bx, by, bz, br in other:
            if br == 0:
                continue
            reach = ar + br
            dx, dy, dz = s16(bx - ax), s16(by - ay), s16(bz - az)
            if abs(dx) < reach & 0xFFFF and abs(dy) < reach & 0xFFFF and abs(dz) < reach & 0xFFFF:
                dist = fight_math.sqrt_table(w32(dx * dx + dy * dy + dz * dz), ex)
                if s16(best) < s16(reach - dist):
                    best = (reach - dist) & 0xFFFF
    return s16(best)


def body_overlap_solve(a: Fighter, b: Fighter) -> None:
    """BodyOverlapSolve (0x80046FCC): fills bodyPushX/Y/Z of both fighters."""
    ram, ex = a.ram, exe()
    for f in (a, b):
        f.bodyPushX = f.bodyPushY = f.bodyPushZ = 0
    overlap = _deepest_overlap(a, b)
    charging = False
    if ram.u8(a.poseMove + 0x2D) and ram.u8(b.poseMove + 0x2D):
        if overlap < 1 and abs(a.rootY - b.rootY) > HEIGHT_GAP:
            return
        fronts = []
        for f in (a, b):
            angle = _axis_angle(f.facing) & 0xFFF
            fronts.append((trunc12(fight_math.trig_raw(angle, ex, fight_math.COS_TABLE) * FRONT_REACH),
                           trunc12(fight_math.trig_raw(angle, ex) * FRONT_REACH)))
        gx = w32(b.rootX + fronts[1][0] - (a.rootX + fronts[0][0]))
        gz = w32(b.rootZ + fronts[1][1] - (a.rootZ + fronts[0][1]))
        if (abs(gx) < FRONT_NEAR and abs(gz) < FRONT_NEAR
                and w32(w32((b.posX - a.posX) * gx) + w32((b.posZ - a.posZ) * gz)) < 0):
            charging = True
            if overlap < CHARGE_OVERLAP:
                overlap = CHARGE_OVERLAP
    if overlap <= 0:
        return
    moved = []
    for f in (a, b):
        prev = PREV_ROOT + 0x10 * f.index
        d = [s16(f.rootX - ram.u16(prev + 4)), s16(f.rootY - ram.u16(prev + 8)), s16(f.rootZ - ram.u16(prev + 12))]
        moved.append(fight_math.sqrt_table(w32(sum(v * v for v in d)), ex) & 0xFFFF)
    toward = fight_math.atan2_4096(w32(b.rootX - a.rootX), w32(b.rootZ - a.rootZ), ex)
    axes = []
    for f, target in ((a, toward), (b, s16(toward + 0x800))):
        angle = _axis_angle(f.facing)
        off = (angle - target) & 0xFFF
        if off > 0x7FF:
            off = 0x1000 - off
        if off > 0x400:
            angle = 0xC00 - div_trunc(s16(f.facing), 16)
        axes.append(angle & 0xFFF)
    d1, d2 = moved
    w1, w2 = (1, 1) if d1 == 0 and d2 == 0 else (d1, d2)     # weights; the displacement terms keep d1, d2
    total = w1 + w2
    shares = (div_trunc(w32(overlap * w1), total), div_trunc(w32(overlap * w2), total))
    cos = [fight_math.trig_raw(x, ex, fight_math.COS_TABLE) for x in axes]
    sin = [fight_math.trig_raw(x, ex) for x in axes]
    new_a = (a.rootX + trunc12(cos[1] * d2) - trunc12(cos[0] * shares[0]),
             a.rootZ + trunc12(sin[1] * d2) - trunc12(sin[0] * shares[0]))
    new_b = (b.rootX + trunc12(cos[0] * d1) - trunc12(cos[1] * shares[1]),
             b.rootZ + trunc12(sin[0] * d1) - trunc12(sin[1] * shares[1]))
    for f, (nx, nz) in ((a, new_a), (b, new_b)):
        px, pz = w32(nx - f.rootX), w32(nz - f.rootZ)
        f.bodyPushX, f.bodyPushZ = (px, pz) if charging else (px >> 1, pz >> 1)
        f.bodyPushY = 0


def _pair_bit(index: int) -> int:
    return 1 << (index - 1) if index > 1 else index


def body_separate(a: Fighter, b: Fighter) -> None:
    """BodySeparate (0x8004401C)."""
    ram = a.ram
    pair = PAIR_DISTANCE + 0x10 * (_pair_bit(a.index) + _pair_bit(b.index))
    solid = all(f.invulnerable != 1 and f.active for f in (a, b))
    if not (ram.u32(pair) < SEPARATION_RANGE + 1 and solid
            and (a.at(0xD9, "B") == 0 or b.at(0xD9, "B") == 0)):
        return
    body_overlap_solve(a, b)
    for f, other in ((a, b), (b, a)):
        if f.bodyPushX or f.bodyPushY or f.bodyPushZ:
            f.set_at(0xD5, "B", 1)
            f.set_at(0xD6 + other.index, "B", 1)
            if ram.s32(GAME_MODE) == 8 and ram.s8(THROW_COUNT) > 1:
                if f.at(0xD9, "B") == 0:
                    f.bodyPushX, f.bodyPushZ, f.bodyPushY = f.bodyPushX << 1, f.bodyPushZ << 1, f.bodyPushY << 1
                else:
                    f.bodyPushZ = f.bodyPushY = f.bodyPushX = 0
            f.posX, f.posY, f.posZ = f.posX + f.bodyPushX, f.posY + f.bodyPushY, f.posZ + f.bodyPushZ
            f.rootX, f.rootY, f.rootZ = f.rootX + f.bodyPushX, f.rootY + f.bodyPushY, f.rootZ + f.bodyPushZ


# --------------------------------------------------------------- motion blending

import motion  # noqa: E402
import pose as pose_mod  # noqa: E402

RSQRT_TABLE = 0x8001A194           # s16 reciprocal square roots used by VectorNormal
PREV_LOCAL = 0x13B0                # 17 x 32 bytes: displayed local rotations, slots 1-17
BLEND_DELTA = 0x15F0               # 17 x 32 bytes: 9 s16 rotation deltas per slot
PREV_ROOT_DISP = 0x1810            # s16[3] displayed root displacement (fighter offset)
BLEND_ROOT_DELTA = 0x1868
REPLAY_FLAGS = (0x8009588C, 0x800958B8)
BLEND_HOLD = 0x800A9234            # frames during which blending is skipped
REPLAY_PLAYBACK = 0x800958C8
DECODED_ROOT_DY = 0x800A8A52


def _spline() -> motion.SplineTables:
    return motion.SplineTables(motion.load_exe())


def vector_normal(v: list[int]) -> list[int]:
    """FUN_8003A86C (VectorNormal): components are taken as s16, result is 4.12."""
    x, y, z = (s16(c) for c in v)
    sq = w32(x * x + y * y + z * z)
    lz = 0
    if sq >= 0:
        lz = (32 - sq.bit_length() if sq else 32) & 0x1E
    shift = (31 - lz) >> 1
    norm = sq << (lz - 24) if lz >= 24 else sq >> (24 - lz)
    r = exe().u8(RSQRT_TABLE + 2 * (w32(norm) - 0x40)) | exe().u8(RSQRT_TABLE + 2 * (w32(norm) - 0x40) + 1) << 8
    r = s16(r)
    return [w32(r * c) >> shift for c in (x, y, z)]


def matrix_orthonormalize(m: list[int]) -> list[int]:
    """MatrixOrthonormalize (0x800762B0) on a row-major 3x3 of s16."""
    c0 = vector_normal([m[0], m[3], m[6]])
    dot = w32(m[1] * c0[0] + m[4] * c0[1] + m[7] * c0[2]) >> 12
    v = [w32(m[1] - (w32(dot * c0[0]) >> 12)), w32(m[4] - (w32(dot * c0[1]) >> 12)),
         w32(m[7] - (w32(dot * c0[2]) >> 12))]
    c1 = vector_normal(v)
    d1, d2, d3 = (s16(c) for c in c0)
    i1, i2, i3 = (s16(c) for c in c1)
    c2 = [(d2 * i3 - d3 * i2) >> 12, (d3 * i1 - d1 * i3) >> 12, (d1 * i2 - d2 * i1) >> 12]
    out = [0] * 9
    for r in range(3):
        out[3 * r], out[3 * r + 1], out[3 * r + 2] = s16(c0[r]), s16(c1[r]), s16(c2[r])
    return out


def _sat16(v: int) -> int:
    return max(-0x8000, min(0x7FFF, v))


def matrix_add_scaled(delta: list[int], base: list[int], weight: int) -> list[int]:
    """MatrixAddScaled (0x8003A980): base + sat16(weight * delta >> 12), GTE GPF sf=1."""
    w = s16(weight)
    return [s16(_sat16((w * s16(d)) >> 12) + b) for d, b in zip(delta, base)]


def _stream(ram: Ram, row: int) -> motion.AnimStream:
    return motion.parse_anim(ram.data, ram.u32(row) & 0x1FFFFFFF)


def _decode_root(ram: Ram, f: Fighter, row: int, frame: int, spline) -> list[int]:
    stream = _stream(ram, row)
    scale = f.scale
    return [s16((motion.sample_channel(stream, k, frame, spline) * scale) >> 12) for k in range(3)]


def _pose_slots(ram: Ram, row: int, frame: int, spline, tab) -> list[list[int]]:
    vec = motion.sample_pose(_stream(ram, row), frame, spline)
    slots = [[0] * 9 for _ in range(18)]
    pose_mod.pose_build_matrices(vec, slots, tab)
    return slots


def _blend_suppressed(f: Fighter) -> bool:
    return bool((f.ram.u32(f.poseMove + 0x24) >> 8) & 1 or f.at(0xBA, "B") or f.at(0x88, "I") & 0xFFFF00)


def _blend_decay_length(f: Fighter) -> int:
    pose_row = f.poseMove
    if f.lastPoseMove == pose_row and f.branchKind != 3:
        return 0
    if not f.moveChanged:
        return 0
    frame = f.poseFrame
    left = max(0, f.ram.u8(pose_row + 0x18) - frame)
    n = 0
    if left != 0:
        active = f.ram.u8(pose_row + 0x2D)
        if active == 0 or active <= frame:
            n = 0x10 if f.throwState < 0 else 4
        else:
            n = min(active - frame, 0x10)
    if left < n:
        n = left
    return n if n >= 2 else 0


def _no_blend_forward(f: Fighter) -> bool:
    ram = f.ram
    return bool((ram.u32(f.poseMove + 0x24) >> 8) & 2 or f.at(0xBB, "B") or f.transBit6 or f.juggleCount
                or (f.inAir and f.at(0x87, "B")))


def _blend_branch_length(f: Fighter) -> int:
    if f.moveRow == 0:
        return 0
    if f.poseFrame < f.entryFrame and f.branchKind != 3:
        return max(0, f.entryFrame - f.poseFrame + 1)
    return 0


def _blend_stance_length(f: Fighter) -> int:
    if f.moveRow != 0:
        return 0
    left = f.ram.u8(f.poseMove + 0x18) - f.poseFrame
    if left >= 0x10:
        return 0
    n = left + 1 if f.frameStep >= 1 else f.poseFrame
    return n if n >= 2 else 0


def _entry_dst_frame(f: Fighter) -> int:
    return f.entryFrame if f.transition in (2, 0x12, 0x13, 0x14, 0x15, 0x16, 0x19, 0x1A, 0x1D, 0x2C) else 0


def transition_blend(f: Fighter, opp: Fighter) -> None:
    """FighterTransitionBlend (0x8003C4C4): blend state machine and pose deltas."""
    ram = f.ram
    spline, tab = _spline(), pose_mod.ExeTables(motion.load_exe())
    n = 0
    if ram.s32(REPLAY_FLAGS[0]) or ram.s32(REPLAY_FLAGS[1]):
        _blend_finish(f)
        return
    if ram.s32(BLEND_HOLD) == 0:
        if ram.s32(REPLAY_PLAYBACK) == 0:
            f.blendActive = 0
            to_forward = True
            if not _blend_suppressed(f):
                if f.blendMode == 1 and f.blendCounter == 0:
                    f.blendMode = 0
                n = _blend_decay_length(f)
                if n:
                    f.blendActive, f.blendMode = 1, 1
                to_forward = f.blendMode != 1
            elif f.blendMode == 1:
                f.blendMode = 0
            if to_forward:
                if not _no_blend_forward(f):
                    if f.blendMode == 2 and f.blendCounter == f.blendFrames:
                        f.blendMode = 0
                    if f.blendMode == 3 and (f.blendCounter == f.blendFrames or f.moveChanged):
                        f.blendMode = 0
                    if f.blendMode == 0:
                        n = _blend_branch_length(f)
                        mode = 2
                        if n == 0:
                            n = _blend_stance_length(f)
                            mode = 3
                        if n:
                            f.blendMode, f.blendActive = mode, 1
                elif f.blendMode in (2, 3):
                    f.blendMode = 0
        if f.blendActive:
            playback = ram.s32(REPLAY_PLAYBACK) != 0
            mode = f.blendMode
            if mode == 2:
                if not playback:
                    f.blendSrcMove = f.poseMove
                    f.blendSrcFrame = f.entryFrame
                    f.blendDstMove = move_lookup(f, f.moveSlot)
                    f.blendDstFrame = _entry_dst_frame(f)
                    f.blendFrames = n
                f.blendCounter = 0
            elif mode == 3:
                if not playback:
                    f.blendSrcMove = f.poseMove
                    f.blendSrcFrame = 0 if f.frameStep < 1 else ram.u8(f.poseMove + 0x18)
                    f.blendDstMove = move_lookup(f, ram.s16(f.poseMove + 0x10))
                    f.blendDstFrame = 0
                    f.blendFrames = n
                f.blendCounter = 0
            elif mode == 1:
                if not playback:
                    f.blendCounter = n - 1
                    f.blendFrames = n
                    f.blendSrcMove = f.lastPoseMove
                    f.blendSrcFrame = f.at(0x5A, "B") - 1
                    f.blendDstMove = f.poseMove
                    f.blendDstFrame = f.poseFrame - 1
                else:
                    f.blendCounter = f.blendFrames - 1
            mode = f.blendMode
            if mode == 1:
                dst = _decode_root(ram, f, f.blendDstMove, f.blendDstFrame, spline)
                for k in range(3):
                    f.set_at(BLEND_ROOT_DELTA + 2 * k, "h", f.at(PREV_ROOT_DISP + 2 * k, "h") - dst[k])
                slots = _pose_slots(ram, f.blendDstMove, f.blendDstFrame, spline, tab)
                for i in range(1, 18):
                    for e in range(9):
                        prev = f.at(PREV_LOCAL + 0x20 * (i - 1) + 2 * e, "h")
                        f.set_at(BLEND_DELTA + 0x20 * (i - 1) + 2 * e, "h", prev - slots[i][e])
            elif 0 < mode < 4:
                src = _decode_root(ram, f, f.blendSrcMove, f.blendSrcFrame, spline)
                dst = _decode_root(ram, f, f.blendDstMove, f.blendDstFrame, spline)
                for k in range(3):
                    f.set_at(BLEND_ROOT_DELTA + 2 * k, "h", dst[k] - src[k])
                a = _pose_slots(ram, f.blendSrcMove, f.blendSrcFrame, spline, tab)
                b = _pose_slots(ram, f.blendDstMove, f.blendDstFrame, spline, tab)
                for i in range(1, 18):
                    for e in range(9):
                        f.set_at(BLEND_DELTA + 0x20 * (i - 1) + 2 * e, "h", b[i][e] - a[i][e])
    else:
        ram.put(BLEND_HOLD, "i", ram.s32(BLEND_HOLD) - 1)
        f.blendMode = 0
    if not f.blendActive:
        mode = f.blendMode
        if mode == 1:
            if f.blendCounter >= 1:
                f.blendCounter = f.blendCounter - 1
            elif f.blendCounter < 0:
                f.blendCounter = 0
        elif mode == 0:
            f.blendCounter = f.blendFrames = 0
        elif mode in (2, 3):
            if f.blendCounter < f.blendFrames:
                f.blendCounter = f.blendCounter + 1
            elif f.blendFrames < f.blendCounter:
                f.blendCounter = f.blendFrames
    _blend_finish(f)


def _blend_finish(f: Fighter) -> None:
    f.lastPoseMove = f.poseMove
    f.lastPoseFrame = f.poseFrame
    f.rootDyBlended = f.ram.s16(DECODED_ROOT_DY)


# --------------------------------------------------------------- root update

ROOT_MAT = 0xF54                   # 3x3 s16 root rotation


def _gpf12(ir0: int, v: list[int]) -> list[int]:
    return [_sat16((s16(ir0) * s16(x)) >> 12) for x in v]


def root_rotation(x: int, y: int, z: int) -> list[int]:
    """FUN_8003A6B4: Rx·Ry·Rz with the game's GTE rounding (row-major s16)."""
    def cs(a: int) -> tuple[int, int]:
        return (fight_math.trig_raw(a >> 4, exe(), fight_math.COS_TABLE),
                fight_math.trig_raw(a >> 4, exe(), fight_math.SIN_TABLE))
    cx, sx = cs(x)
    cy, sy = cs(y)
    cz, sz = cs(z)
    a1, a2, a3 = _gpf12(sx, [cz, sz, cy])
    cxcz = (cx * cz) >> 12
    b1, b2, b3 = _gpf12(sy, [a1, a2, cxcz])
    cxsz = (cx * sz) >> 12
    c1, c2, c3 = _gpf12(cy, [cz, -sz, cx])
    return [s16(c1), s16(c2), s16(sy),
            s16(b1 + cxsz), s16(cxcz - b2), s16(-a3),
            s16(a2 - b3), s16(((cxsz * sy) >> 12) + a1), s16(c3)]


def trunc_shift13(v: int) -> int:
    v = w32(v)
    return (v + 0x1FFF if v < 0 else v) >> 13


def root_update(f: Fighter) -> None:
    """RootUpdate (0x8003AD48) outside replays: root matrix, blend weight, root position."""
    x, y, z = s16(-f.tiltX), s16(f.heading - 0x8000), s16(-f.tiltZ)
    for i, v in enumerate(root_rotation(x & 0xFFFF, y & 0xFFFF, z & 0xFFFF)):
        f.set_at(ROOT_MAT + 2 * i, "h", v)
    dy = f.rootDy
    if f.blendMode == 0 or f.blendFrames == 0:
        f.blendWeight = 0x1000
        f.rootDyBlended = dy
    else:
        f.blendWeight = div_trunc(w32(f.blendCounter << 12), f.blendFrames)
        dy = s16(trunc_shift13(f.at(BLEND_ROOT_DELTA + 2, "h") * f.blendWeight * 2) + dy)
        f.rootDyBlended = dy
    f.rootX, f.rootY, f.rootZ = f.posX, f.posY, f.posZ
    if f.airPhase == 0:
        a = ((0x8000 - f.facing) >> 4) & 0xFFF
        c = fight_math.trig_raw(a, exe(), fight_math.COS_TABLE)
        s_ = fight_math.trig_raw(a, exe())
        f.rootX = f.rootX + trunc12(f.rootDx * c - f.rootDz * s_)
        f.rootY = f.rootY + dy
        f.rootZ = f.rootZ + trunc12(f.rootDx * s_ + f.rootDz * c)
    elif f.airPhase == 2:
        f.rootY = f.rootY + dy


def root_reanchor(f: Fighter) -> None:
    """RootReanchor (0x8003AC1C): move the anchor so the root does not jump when rootMove changes."""
    if not f.anchorDirty:
        return
    frame = max(0, f.rootFrame - f.frameStep - 1)
    f.anchorDirty = 0
    dx, _, dz = _decode_root(f.ram, f, f.rootMove, frame, _spline())
    a = (((0x8000 - f.facing) >> 3) & 0x1FFE) >> 1
    c = fight_math.trig_raw(a, exe(), fight_math.COS_TABLE)
    s_ = fight_math.trig_raw(a, exe())
    f.posX = f.rootX - trunc12(dx * c - dz * s_)
    f.posZ = f.rootZ - trunc12(dx * s_ + dz * c)


# --------------------------------------------------------------- hit test

HIT_SLOTS = 0x13C                  # two 0x2C-byte hit records per defender
HIT_SLOT_SIZE = 0x2C
ATTACK_SEGS = 0x1AC                # 4 x (s32 start[3], s32 end[3])
HURT_ZONES = 0x20C                 # 14 x (s32 centre[3], s32 radius (s16 used), s32 radius^2)
HURT_ZONE_COUNT = 14
PROJECTILES = 0x800AE148           # effect buffer; per player 0x780 bytes, segments at +0x3200
PROJECTILE_SEGS = (0x800AE374, 0x800AE378)
FORCED_HIT_SOUND = 0x4951
PROJECTILE_JOINT = 0x18            # attack descriptor joints from here on are projectiles
LOW_ATTACK = 0x10F
JUMP_CLASS = 12


def _words(ram: Ram, addr: int, n: int) -> list[int]:
    return [ram.s32(addr + 4 * i) for i in range(n)]


def hit_test_segments(ram: Ram, attacker: Fighter, defender: Fighter, slot: int) -> bool:
    """HitTestSegments (0x80047E54, called through the scratchpad-stack wrapper 0x80047FF4).

    Tests the attacker's live segments against the defender's 14 hurt cylinders and records the
    first contact in `slot`: the segment end, its direction (end - start, 16-bit) and the cylinder.
    For projectile descriptors the segments come from the effect buffer of fighters 0 and 1;
    other fighter indices read uninitialised registers in the game and are not modelled.
    """
    if ram.u8(ram.u32(attacker.poseMove + 0x28)) < PROJECTILE_JOINT:
        count = min(attacker.activeSegs, 4)
        seg = attacker.base + ATTACK_SEGS
    else:
        if attacker.index > 2:
            raise NotImplementedError("projectile segments of fighter index > 2")
        which = 1 if attacker.index else 0
        count = ram.s32(PROJECTILE_SEGS[which])
        base = ram.u32(PROJECTILES)
        seg = base + which * 0x780 + 0x3200 if base else 0
    for _ in range(max(count, 0)):
        if defender.hitCooldown != 0:
            return False
        s = _words(ram, seg, 6)
        for k in range(HURT_ZONE_COUNT):
            if fight_math.segment_hits_cylinder(s, _words(ram, defender.base + HURT_ZONES + 20 * k, 5)):
                ram.put(slot + 0x18, "h", k)
                for i in range(3):
                    ram.put(slot + 4 * i, "i", s[3 + i])
                    ram.put(slot + 0x10 + 2 * i, "h", s16(s[3 + i] - s[i]))
                return True
        seg += 24
    return False


def hit_test(ram: Ram, attacker: Fighter, defender: Fighter) -> list[tuple]:
    """HitTest (0x80044304); returns the sounds it plays."""
    events: list[tuple] = []
    slot = 0
    for i in range(2):
        rec = defender.base + HIT_SLOTS + HIT_SLOT_SIZE * i
        if ram.u8(rec + 0x21) == 0:
            slot = rec
    done = attacker.base + 0x85 + defender.index - 2      # hitDone0/1 (index 2: mode 8)
    if (slot and not attacker.invulnerable and not defender.invulnerable and attacker.active
            and defender.active and ram.u8(done) == 0):
        pose = defender.poseMove
        skip = (attacker.attack == LOW_ATTACK and defender.stateClass == JUMP_CLASS
                and (ram.u8(pose + 0x19) <= defender.poseFrame <= ram.u8(pose + 0x1A) - 5 or defender.inAir))
        if not skip and (ram.s32(GAME_MODE) not in (7, 8) or defender.inThrow == 0):
            level = attacker.attack | (1 if defender.stepKind == 2 else 0)
            forced = (attacker.forcedHit and defender.isCpu
                      and ram.u8(defender.base + 0xD6 + attacker.index))
            if not forced:
                hit = hit_test_segments(ram, attacker, defender, slot)
            else:
                for i, (a, d) in enumerate(((attacker.rootX, defender.rootX), (attacker.rootY, defender.rootY),
                                            (attacker.rootZ, defender.rootZ))):
                    ram.put(slot + 4 * i, "i", d)
                    ram.put(slot + 0x10 + 2 * i, "h", s16(w32(a - d) >> 1))
                hit = True
                events.append(("sound", FORCED_HIT_SOUND))
            if hit and level & defender.state & 7:
                ram.put(done, "B", 1)
                attacker.contactThisMove = 1
                attacker.contact = 1
                attacker.lastHitTarget = defender.index
                defender.wasHitThisMove = 1
                defender.gotHit = 1
                defender.hitFreezeIn = ram.u8(attacker.poseMove + 0x2C)
                ram.put(slot + 0x21, "B", 1)
                ram.put(slot + 0x20, "B", attacker.index)
                defender.forcedHitIn = attacker.forcedHit
                if attacker.curSlot == 0x898:
                    defender.hitFreezeIn = 0x1E
                if attacker.damage != 0 or defender.inAir:
                    defender.hitCooldown = 4
    if ram.u8(attacker.poseMove + 0x2E) == attacker.poseFrame and attacker.contactThisMove == 0:
        attacker.whiffed = 1
    return events


# --------------------------------------------------------------- hit apply

REACTION_RECORDS = 0x80010CE8      # 42-byte reaction records
THROW_VICTIM_SLOTS = 0x800174C4    # u16 move slots for throw victims
FORCED_REACTION = 0x8001DEC0       # reaction of a body thrown into a fighter
NO_DAMAGE = (0x800958A0, 0x800958D8)
KO_STARTED = 0x800958BC
PRACTICE_COUNTER = 0x800958E4      # s32 per fighter: practice COUNTER ATTACKS
FORCE_SCORE = 0x800B70EC
SLOT_WEIGHTS = ((0x28, 1), (0x22, 2), (0x23, 3), (0x26, 4), (0x24, 5), (0x25, 6), (0x27, 7))
EXTRA_DAMAGE = 0xCC                # s16: HitExtraDamage of the last HitApply


def hit_extra_damage(f: Fighter) -> int:
    """HitExtraDamage (0x80044C4C)."""
    total = 0
    own = f.extraDamage or f.damage
    if f.extraKind == 2:
        total = own
    if f.extraKind == 3:
        total -= own
    if f.throwState < 0:
        opp = fighter_opponent(f)
        if opp.extraKind == 1:
            total += opp.extraDamage or opp.damage
    return total


def hit_damage_slot(ram: Ram, defender: Fighter, attacker: Fighter, slot: int) -> None:
    """HitDamage (0x80044E70): stores the attacker's base damage (`+0x1C`) and adds the hit's damage (`+0x1E`)."""
    ram.put(slot + 0x1C, "H", attacker.damage & 0xFFFF)
    d = fight_math.hit_damage(
        {"damage": defender.damage, "powerTimer": defender.powerTimer, "poseFrame": defender.poseFrame,
         "juggleCount": defender.juggleCount, "moveActiveStart": ram.u8(defender.poseMove + 0x2D)},
        {"damage": attacker.damage, "powerTimer": attacker.powerTimer},
        {"guarded": ram.u8(slot + 0x22), "chip": ram.u8(slot + 0x23), "close": ram.u8(slot + 0x26),
         "counter": ram.u8(slot + 0x25), "airborne": ram.u8(slot + 0x27), "zone": ram.s16(slot + 0x18)})
    ram.put(slot + 0x1E, "h", s16(ram.s16(slot + 0x1E) + d))


def _slot_score(ram: Ram, slot: int) -> int:
    return sum(w for off, w in SLOT_WEIGHTS if ram.u8(slot + off))


def hit_best_slot(ram: Ram, f: Fighter) -> int:
    """HitBestSlot (0x800450CC): the second slot wins on a higher summed score, or on equal score with more damage."""
    best, other = f.base + HIT_SLOTS, f.base + HIT_SLOTS + HIT_SLOT_SIZE
    if ram.u8(other + 0x21):
        a, b = _slot_score(ram, best), _slot_score(ram, other)
        if a < b or (a == b and ram.s16(best + 0x1E) < ram.s16(other + 0x1E)):
            best = other
    return best


def hit_copy_slot_flags(ram: Ram, f: Fighter, slot: int) -> None:
    """HitCopySlotFlags (0x8004527C)."""
    f.lastDamage = abs(ram.s16(slot + 0x1E))
    f.closeHit = ram.u8(slot + 0x26)
    f.guarded = ram.u8(slot + 0x22)
    f.hitClean = ram.u8(slot + 0x24)
    f.counterHit = ram.u8(slot + 0x25)
    f.lastAttacker = ram.u8(slot + 0x20)


def _reaction_from(ram: Ram, value: int) -> int:
    if value & 0xF000 == 0:
        return REACTION_RECORDS + value * 0x2A
    return THROW_VICTIM_SLOTS + ((value & 0xFFF) << 1)


def hit_apply(ram: Ram, f: Fighter, force_player: int = FIGHTERS) -> list[tuple]:
    """HitApply (0x80044634). `force_player` is the record force.ovl FUN_800B2E60 returns (mode 8).

    Returns the side effects not modelled here: ("hit_effect", slot, damage) for HitSpawnEffect and
    ("ko", opponent index) for FUN_80032030."""
    events: list[tuple] = []
    mode = ram.s32(GAME_MODE)
    opp = fighter_opponent(f)
    extra = hit_extra_damage(f)
    total = 0
    for i in range(2):
        slot = f.base + HIT_SLOTS + HIT_SLOT_SIZE * i
        if ram.u8(slot + 0x21):
            f.fixedFacing = 0
            opp = Fighter(ram, FIGHTERS + FIGHTER_SIZE * ram.u8(slot + 0x20))
            relative_angles(f, opp)
            hit_classify(ram, f, opp, slot)
            hit_damage_slot(ram, f, opp, slot)
            total += ram.s16(slot + 0x1E)
    if f.gotHit:
        best = hit_best_slot(ram, f)
        f.bestHitSlot = best
        hit_copy_slot_flags(ram, f, best)
        if mode == 5 and ram.u32(PRACTICE_COUNTER + 4 * f.index) and not f.inReaction and f.hitClean:
            f.counterHit = 1
        for k in range(3):
            f.set_at(0x3DC + 4 * k, "i", opp.at(0x3D0 + 4 * k, "i"))
        if f.forcedHitIn:
            f.reaction = FORCED_REACTION
        elif not f.closeHit:
            f.reaction = _reaction_from(ram, ram.u16(opp.poseMove + 0x32))
        else:
            close = ram.u16(opp.poseMove + 0x34)
            f.reaction = _reaction_from(ram, ram.u16(CLOSE_REACTIONS + 4 * close))
    old = f.health
    if ram.u32(NO_DAMAGE[0]) == 0 and ram.u32(NO_DAMAGE[1]) == 0:
        f.health = w32(old - (extra + total) * 0x10000)
    if mode == 7 and opp.index != 2:
        f.health = old
    if f.health < 0:
        f.health = 0
    if f.healthMax < f.health:
        f.health = f.healthMax
    if f.health == 0 and old != 0:
        f.ko = 1
    if f.ko and ram.u8(f.bestHitSlot + 0x23):
        f.guarded = 0
        f.hitClean = 1
    if f.gotHit:
        events.append(("hit_effect", f.bestHitSlot, s16(total)))
    if f.ko and ram.u32(KO_STARTED) == 0 and mode != 8:
        events.append(("ko", opp.index))
        ram.put(KO_STARTED, "i", 1)
    if mode == 8 and f.isCpu:
        score = 0
        if f.gotHit:
            for i in range(2):
                slot = f.base + HIT_SLOTS + HIT_SLOT_SIZE * i
                if ram.u8(slot + 0x21):
                    attacker = FIGHTERS + FIGHTER_SIZE * ram.u8(slot + 0x20)
                    if attacker == force_player or ram.u8(attacker + 0xE6):
                        score += ram.s16(slot + 0x1C)       # base damage (HitDamage)
        if extra > 0:
            score += extra * 2
        if score:
            ram.put(FORCE_SCORE, "i", w32(ram.s32(FORCE_SCORE) + score * 10))
    f.set_at(EXTRA_DAMAGE, "h", s16(extra))
    return events


# --------------------------------------------------------------- collision shapes

JOINTS = 0x8F4                     # 24 x 0x44: MATRIX (s16 m[9], pad), s32 t[3] at +0x14, ...
JOINT_SIZE = 0x44
BODY_POINTS_OFF = 0x324            # 8 x 16 bytes (centre s32 x, y, z, radius)
HURT_ZONE_JOINTS = 0x800973DC      # s32[14]
BODY_SPHERE_JOINTS = 0x80097364    # s32[8]
HURT_ZONE_Y = {8: -0x78, 11: -0x3C}
SEG_STATE = 0x800A0920             # per player: anchor (12 bytes)
SEG_END0 = 0x800A08D0              # per player: segment 0 end of the previous frame
SEG_END1 = 0x800A08F4              # per player: segment 1 end of the previous frame
SEG_MODE = 0x800A0950              # s32 per player: 1 for characters 14 and 15 (alternative point block)
SEG_TRIG = 0x800A0960              # sin/cos(-heading), sin/cos(-(heading - facing)), heading - facing, root
# Weapon points outside the active window: (bank, character or None, joint, local point, target joint).
WEAPON_POINTS = (
    (4, None, 10, (100, -720, 0), 18), (4, None, 10, (100, -360, 0), 19),
    (14, 0x14, 11, (100, -500, 0), 22), (14, 0x14, 2, (800, 0, 600), 23),
    (0x13, None, 11, (200, 900, 0), 21), (0x13, None, 2, (400, 0, 100), 23),
)
# Byte offset of frame t's points in a baked attack record, by layout kind.
LAYOUT_STRIDE = {0: (10, 0), 1: (5, 5), 2: (10, 10), 3: (15, 5), 4: (15, 5), 5: (20, 0), 6: (10, 5),
                 7: (10, 5), 9: (10, 5), 10: (15, 0), 12: (15, 0), 13: (15, 0), 14: (15, 0)}


def _joint_t(ram: Ram, f: Fighter, joint: int) -> list[int]:
    return _words(ram, f.base + JOINTS + JOINT_SIZE * joint + 0x14, 3)


def apply_matrix(ram: Ram, matrix: int, v: tuple[int, int, int]) -> list[int]:
    """PsyQ ApplyMatrix: GTE MVMVA (sf = 1) result MAC1..3 = (M v) >> 12."""
    m = [ram.s16(matrix + 2 * i) for i in range(9)]
    return [w32((m[3 * r] * v[0] + m[3 * r + 1] * v[1] + m[3 * r + 2] * v[2]) >> 12) for r in range(3)]


def unpack_point(ram: Ram, addr: int) -> list[int]:
    """FUN_800699FC: 40-bit point, x and y 13 bits (bias 0x1000), z 14 bits (bias 0x2000)."""
    v = int.from_bytes(bytes(ram.u8(addr + i) for i in range(5)), "little")
    return [(v & 0x1FFF) - 0x1000, ((v >> 13) & 0x1FFF) - 0x1000, (v >> 26) - 0x2000]


def _trig_neg16(angle: int) -> tuple[int, int]:
    """sin, cos of -angle (16-bit angle units; `angle` is used as a plain int)."""
    a = -angle
    idx = ((a + 0xF if a < 0 else a) >> 4) & 0xFFF
    return (fight_math.trig_raw(idx, exe(), fight_math.SIN_TABLE),
            fight_math.trig_raw(idx, exe(), fight_math.COS_TABLE))


def _place(ram: Ram, out: int, p: list[int], origin: list[int]) -> None:
    """FUN_8006A518: origin (swung about the root by heading - facing) + point rotated by -heading."""
    ox, oy, oz = origin
    if ram.s32(SEG_TRIG + 0x10):
        s, c = ram.s32(SEG_TRIG + 8), ram.s32(SEG_TRIG + 12)
        rx, rz = ram.s32(SEG_TRIG + 0x14), ram.s32(SEG_TRIG + 0x1C)
        dx, dz = w32(rx - ox), w32(rz - oz)
        ox = w32(rx - trunc12(w32(dx * c - dz * s)))
        oz = w32(rz - trunc12(w32(dx * s + dz * c)))
    s, c = ram.s32(SEG_TRIG), ram.s32(SEG_TRIG + 4)
    x, y, z = p
    ram.put(out, "i", w32(ox + trunc12(w32(x * c)) - trunc12(w32(z * s))))
    ram.put(out + 4, "i", w32(oy + y))
    ram.put(out + 8, "i", w32(oz + trunc12(w32(x * s)) + trunc12(w32(z * c))))


def _copy3(ram: Ram, dst: int, src: int) -> None:
    for i in range(3):
        ram.put(dst + 4 * i, "I", ram.u32(src + 4 * i))


def attack_segments_baked(ram: Ram, f: Fighter) -> None:
    """FUN_8006A6A4: attack segments inside the active window from the baked points of the attack record."""
    desc = ram.u32(f.poseMove + 0x28)
    if f.attackSegCount == 0 or ram.u8(desc) > 0x17:
        return
    player = f.index
    seg0, end0 = f.base + ATTACK_SEGS, f.base + ATTACK_SEGS + 12
    seg1, end1 = f.base + ATTACK_SEGS + 24, f.base + ATTACK_SEGS + 36
    delta = f.heading - f.facing
    ram.put(SEG_TRIG + 0x10, "i", delta)
    if delta:
        _copy3(ram, SEG_TRIG + 0x14, f.base + 0xF68)
        s, c = _trig_neg16(delta)
        ram.put(SEG_TRIG + 8, "i", s)
        ram.put(SEG_TRIG + 12, "i", c)
    s, c = _trig_neg16(f.heading)
    ram.put(SEG_TRIG, "i", s)
    ram.put(SEG_TRIG + 4, "i", c)
    flags = ram.u8(desc + 4) << 8 | ram.u8(desc + 5)
    mode = ram.s32(SEG_MODE + 4 * player)
    if mode == 1:
        extra = (flags & 0x7FFF) >> 4
    elif mode == 2:
        extra = (flags & 0x7FFE) >> 3 if ram.u8(desc + 4) & 0x80 else 0
    elif mode == 0:
        extra = 0
    else:
        return
    kind = flags & 0xF
    t = f.poseFrame - ram.u8(f.poseMove + 0x2D)
    if kind not in LAYOUT_STRIDE:
        return
    per, base = LAYOUT_STRIDE[kind]
    p = desc + 6 + per * t + base + extra
    cur = [f.posX, f.posY, f.posZ]
    prev = _words(ram, SEG_STATE + 12 * player, 3)
    if kind in (1, 2, 4, 6, 7):
        if t != 0:
            _copy3(ram, seg0, SEG_END0 + 12 * player)
        else:
            _place(ram, seg0, unpack_point(ram, p - (10 if kind == 2 else 5)), prev)
        _place(ram, end0, unpack_point(ram, p), cur)
        q = p + 5
    else:
        _place(ram, seg0, unpack_point(ram, p), cur)
        _place(ram, end0, unpack_point(ram, p + 5), cur)
        q = p + 10
    if kind in (2, 3):
        if t != 0:
            _copy3(ram, seg1, SEG_END1 + 12 * player)
        else:
            _place(ram, seg1, unpack_point(ram, q - (10 if kind == 2 else 15)), prev)
        _place(ram, end1, unpack_point(ram, q), cur)
    elif kind in (4, 5):
        _place(ram, seg1, unpack_point(ram, q), cur)
        _place(ram, end1, unpack_point(ram, q + 5), cur)
    elif kind in (6, 10):
        _place(ram, seg1, unpack_point(ram, q), cur)
        _copy3(ram, end1, end0)
    elif kind == 7:
        _copy3(ram, seg1, end0)
        _place(ram, end1, unpack_point(ram, q), cur)
    elif kind in (9, 12):
        if kind == 12:
            _place(ram, seg1, unpack_point(ram, q), cur)
        elif t == 0:
            _place(ram, seg1, unpack_point(ram, q - 5), prev)
        else:
            _copy3(ram, seg1, SEG_END1 + 12 * player)
        _copy3(ram, end1, seg0)
    elif kind == 13:
        _copy3(ram, seg1, seg0)
        _place(ram, end1, unpack_point(ram, q), cur)
    elif kind == 14:
        _place(ram, end1, unpack_point(ram, q), cur)
        _copy3(ram, seg1, end1)


def _segment_joint(f: Fighter, joint: int) -> int | None:
    if joint == 0x13 and f.charId == 0xE:
        return 6
    if joint == 0x13:
        return joint
    return joint if joint < 0x18 else None


def collision_shapes_update(ram: Ram, f: Fighter) -> None:
    """CollisionShapesUpdate (0x80042204)."""
    pose = f.poseMove
    if ram.u8(pose + 0x2D) <= f.poseFrame <= ram.u8(pose + 0x2E):
        attack_segments_baked(ram, f)
    else:
        for bank, char, joint, point, target in WEAPON_POINTS:
            if f.bankType != bank or (char is not None and f.charId != char):
                continue
            matrix = f.base + JOINTS + JOINT_SIZE * joint
            v = apply_matrix(ram, matrix, point)
            t = _joint_t(ram, f, joint)
            dst = f.base + JOINTS + JOINT_SIZE * target + 0x14
            for i in range(3):
                ram.put(dst + 4 * i, "i", w32(v[i] + t[i]))
        desc = ram.u32(pose + 0x28)
        for k in range(f.attackSegCount):
            seg = f.base + ATTACK_SEGS + 24 * k
            a = _segment_joint(f, ram.u8(desc + 2 * k))
            if a is not None:
                for i, v in enumerate(_joint_t(ram, f, a)):
                    ram.put(seg + 12 + 4 * i, "i", v)
            b = ram.u8(desc + 2 * k + 1)
            if b:
                b = _segment_joint(f, b)
                if b is not None:
                    for i, v in enumerate(_joint_t(ram, f, b)):
                        ram.put(seg + 4 * i, "i", v)
    for k in range(HURT_ZONE_COUNT):
        t = _joint_t(ram, f, ram.s32(HURT_ZONE_JOINTS + 4 * k))
        zone = f.base + HURT_ZONES + 20 * k
        t[1] = w32(t[1] + HURT_ZONE_Y.get(k, 0))
        for i in range(3):
            ram.put(zone + 4 * i, "i", t[i])
    for k in range(8):
        t = _joint_t(ram, f, ram.s32(BODY_SPHERE_JOINTS + 4 * k))
        for i in range(3):
            ram.put(f.base + BODY_POINTS_OFF + 16 * k + 4 * i, "i", t[i])
    _copy3(ram, f.base + 0x3A4, f.base + HURT_ZONES)


# --------------------------------------------------------------- frame events

FACE_VARIANTS = 0x80095D74         # u8 per costume key (< 0x37)
PREV_POSE_FRAME = 0x5A


def face_variant(f: Fighter) -> int:
    """FUN_800364E8."""
    key = f.at(0x1C, "h")
    return f.ram.u8(FACE_VARIANTS + key) if 0 <= key < 0x37 else 0


def move_events(ram: Ram, f: Fighter) -> list[tuple]:
    """MoveEvents (0x80045B60): fires the running move's (frame, command) events passed this frame.

    Returns the effects it spawns: ("effect", owner, point), ("spark", kind, point),
    ("dust", root point), ("vibrate", player, pattern) and ("camera_shake", n)."""
    events: list[tuple] = []
    lst = ram.u32(f.poseMove + 0x20)
    f.extraKind = 0
    if not f.active or not lst:
        return events
    while (frame := ram.u16(lst)) != 0:
        if f.poseFrame >= frame > f.at(PREV_POSE_FRAME, "h"):
            cmd = ram.u16(lst + 2)
            hi, lo = cmd >> 8, cmd & 0xFF
            if 6 <= hi <= 10:
                point = tuple(_joint_t(ram, f, lo))
                if hi == 6:
                    events += [("effect", f.index, point), ("vibrate", f.index, 1)]
                elif hi == 7:
                    events.append(("effect", f.at(0x1F, "B"), point))
                else:
                    events.append(("spark", {8: 0, 9: 1, 10: 3}[hi], point))
            elif 14 <= hi < 0x3E:
                f.set_at(0xBC, "B", 1)
                code = hi - 14
                hands = code >> 4 or 3
                if hi == 20:
                    hand_face_command(f, hands, 0, lo)
                elif hi == 21:
                    hand_face_command(f, hands, face_variant(f), lo)
                else:
                    hand_face_command(f, hands, code & 7, lo)
            elif hi in (1, 2, 3):
                camera_shake(ram, hi - 1)
                events.append(("camera_shake", hi - 1))
            elif hi == 4:
                events += [("dust", (f.rootX, f.rootY, f.rootZ)), ("vibrate", f.playerIndex, 2)]
            elif hi in (11, 12, 13):
                f.extraKind = hi - 10
                f.extraDamage = lo
        lst += 4
    return events
