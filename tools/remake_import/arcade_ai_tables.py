"""The arcade CPU's tables → `tables/ai.json`, in the layout `content/ai_tables.gd` reads.

Addresses and meanings: work/arcade/fight/reports/ai.md. Input scripts are lists of u16 steps as in
`ai.py`: the first step, then the following ones up to the 0 terminator. Hooks are code, named by
their role as in `ai.py`; "idle" hooks only return -1.

The parameter table's shape differs from the PlayStation's: 2 region groups x 5 difficulties x 10
levels x 60 s16 words. It is written flattened as `params[group * 5 + difficulty][level]`.
"""

from __future__ import annotations

import arcade
from common import Output
from arcade_tables import s16s, s32s, u16s, u32s

AI_PARAMS = 0x801FFE04
AI_REGIONS, AI_DIFFICULTIES, AI_LEVELS, AI_WORDS = 2, 5, 10, 60
AI_LEVEL_BYTES = AI_WORDS * 2
BAND_THRESHOLDS = 0x80202CE4    # 6 s16 per character id
BAND_THRESHOLD_COUNT = 23
BAND_REACH = 0x801FFD38         # u32 per distance band: the reach bits a candidate may have
APPROACH_REACH = 0x801FFD50     # u32 per reach band: the opponent's reach bits that stop an approach
BAND_COUNT = 6
NUMPAD_PADS = 0x8017A2A0        # u16 pad bits per step low nibble: numpad 0-9, then none (script steps)
NUMPAD_PAD_COUNT = 16
DIRECTION_MASKS = 0x8017A2C0    # u16 per numpad direction 0-9: its branch command direction bit
DIRECTION_PADS = 0x8017A2D4     # u16 pad bits per numpad direction 0-9 (plain commands)
BUTTON_PADS = 0x8017A2E8        # u16 pad bits of command bits 0-3
SIDE_STEP_SCRIPTS = 0x8017A2F2  # two scripts, 24 bytes apart
SIDE_STEP_STRIDE = 24
TAP_FORWARD, TAP_BACK = 0x80010290, 0x8001029C   # the sequences of commands 0xC001 / 0xC002: a window, then steps
BACK_DASH = 0x8017A33E
WAKE_UP = 0x8017A322
KING_THROWS = 0x8017A762        # 14-byte scripts: three command throws
KING_THROW_COUNT = 3
KING_VS_CROUCH = 0x8017A746     # two
KING_GROUND = 0x8017A72A        # two
KING_PAIR_COUNT = 2
KING_SCRIPT_STRIDE = 14
OGRE_ESCAPES = 0x8017A720       # u16 x 4: pads against Ogre's fire breath
OGRE_ESCAPE_COUNT = 4
ACTIONS = 0x8017A5B8            # u32 x 6: the neutral actions
ACTION_COUNT = 6
EVASION_STATES = 0x8017A5D0     # u32 x 7
EVASION_COUNT = 7
HOOKS = 0x8017A78C              # (s32 bank, u32 hook A, u32 hook B)
HOOK_STRIDE = 12
HOOK_COUNT = 22
# FUN_801CEA0C's hooks by address; every other one returns -1 (no action).
HOOK_NAMES = {0: "", 0x801CE078: "vs_paul", 0x801CDC98: "vs_yoshimitsu", 0x801CE160: "vs_ogre",
              0x801CE618: "as_king", 0x801CE984: "as_hwoarang"}
IDLE_HOOK = "idle"
BANK_RECORDS = 0x8017A434       # per bank type 16 bytes: s32 counter moves, u32 parry scripts x 2, u32 setups
BANK_RECORD_STRIDE = 16
BANK_RECORD_COUNT = 22
SETUP_STRIDE = 8                # s16 chance, s16 slot, u32 script
AI_WINDOW_WORD = 2              # sequences start with a window the CPU's press skips


def _steps(arc: arcade.ArcadeSet, address: int) -> list[int]:
    """An input script at `address`: its first step, then the steps up to the 0 terminator."""
    out = [u16s(arc, address, 1)[0]]
    while (step := u16s(arc, address + 2 * len(out), 1)[0]) != 0:
        out.append(step)
    return out


def _hook_name(address: int) -> str:
    return HOOK_NAMES.get(address, IDLE_HOOK)


def _bank(arc: arcade.ArcadeSet, bank: int) -> dict:
    record = BANK_RECORDS + BANK_RECORD_STRIDE * bank
    counter = s32s(arc, record, 1)[0]
    parry_high, parry_low, setups = u32s(arc, record + 4, 3)
    entries = []
    if setups:
        at = setups
        while True:
            chance, slot = s16s(arc, at, 2)
            if chance < 0:
                break
            entries.append([chance, slot, _steps(arc, u32s(arc, at + 4, 1)[0] + AI_WINDOW_WORD)])
            at += SETUP_STRIDE
    return {
        "counter": counter,
        "parry_high": _steps(arc, parry_high) if parry_high else [],
        "parry_low": _steps(arc, parry_low) if parry_low else [],
        "setups": entries,
    }


def _hooks(arc: arcade.ArcadeSet) -> list[list]:
    rows = []
    for k in range(HOOK_COUNT):
        at = HOOKS + HOOK_STRIDE * k
        hook_a, hook_b = u32s(arc, at + 4, 2)
        rows.append([s32s(arc, at, 1)[0], _hook_name(hook_a), _hook_name(hook_b)])
    return rows


def _params(arc: arcade.ArcadeSet) -> list[list[list[int]]]:
    groups = AI_REGIONS * AI_DIFFICULTIES
    return [[s16s(arc, AI_PARAMS + AI_LEVEL_BYTES * (group * AI_LEVELS + level), AI_WORDS)
             for level in range(AI_LEVELS)] for group in range(groups)]


def _scripts(arc: arcade.ArcadeSet, address: int, count: int, stride: int = KING_SCRIPT_STRIDE) -> list[list[int]]:
    return [_steps(arc, address + stride * k) for k in range(count)]


def tables(arc: arcade.ArcadeSet) -> dict:
    return {
        "params": _params(arc),
        "band_thresholds": [s16s(arc, BAND_THRESHOLDS + 12 * c, BAND_COUNT) for c in range(BAND_THRESHOLD_COUNT)],
        "band_reach": u32s(arc, BAND_REACH, BAND_COUNT),
        "approach_reach": u32s(arc, APPROACH_REACH, BAND_COUNT),
        "numpad_pads": u16s(arc, NUMPAD_PADS, NUMPAD_PAD_COUNT),
        "direction_masks": u16s(arc, DIRECTION_MASKS, 10),
        "direction_pads": u16s(arc, DIRECTION_PADS, 10),
        "button_pads": u16s(arc, BUTTON_PADS, 4),
        "side_steps": _scripts(arc, SIDE_STEP_SCRIPTS, 2, SIDE_STEP_STRIDE),
        "tap_forward": _steps(arc, TAP_FORWARD + AI_WINDOW_WORD),
        "tap_back": _steps(arc, TAP_BACK + AI_WINDOW_WORD),
        "back_dash": _steps(arc, BACK_DASH),
        "wake_up": _steps(arc, WAKE_UP),
        "king_throws": _scripts(arc, KING_THROWS, KING_THROW_COUNT),
        "king_vs_crouch": _scripts(arc, KING_VS_CROUCH, KING_PAIR_COUNT),
        "king_ground": _scripts(arc, KING_GROUND, KING_PAIR_COUNT),
        "ogre_escapes": u16s(arc, OGRE_ESCAPES, OGRE_ESCAPE_COUNT),
        "actions": u32s(arc, ACTIONS, ACTION_COUNT),
        "evasion_states": s32s(arc, EVASION_STATES, EVASION_COUNT),
        "hooks": _hooks(arc),
        "banks": [_bank(arc, b) for b in range(BANK_RECORD_COUNT)],
        "force_words": [],              # Tekken Force is the PlayStation's
    }


def convert(arc: arcade.ArcadeSet, out: Output) -> None:
    out.write_json("tables/ai.json", tables(arc))
