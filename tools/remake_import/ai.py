"""The CPU opponent's tables (docs/research/code/ai.md) as `tables/ai.json`.

The input scripts the AI presses are lists of u16 steps (numpad direction in bits 0-3, buttons in
bits 8-11): the first step, which `AiStartScript` presses whatever it is (the parry scripts start
with 0, no input), then the following steps up to the 0 terminator, which `AiUpdate` presses on the
next frames. The character
hooks are code; the table names the hook of each bank type (`AiHookForBank`) by its role: "vs_<name>"
against that character (hook A), "as_<name>" playing it (hook B), "idle" for the ones that only
return -1, "" for none. The remake's `AiTables.Hook` reads the same names.
"""

from __future__ import annotations

from common import Disc, Output

AI_PARAMS = 0x80023418          # 3 difficulty groups x 10 levels x 55 s16 words (0x6E bytes)
AI_GROUPS, AI_LEVELS, AI_WORDS = 3, 10, 55
AI_GROUP_BYTES, AI_LEVEL_BYTES = 0x44C, 0x6E
BAND_THRESHOLDS = 0x80098640    # 6 s16 per character id: distance-band thresholds
BAND_THRESHOLD_COUNT = 24
BAND_REACH = 0x80098610         # u32 per distance band: the reach bits a candidate may have
APPROACH_REACH = 0x80098628     # u32 per reach band: the opponent's reach bits that stop an approach
BAND_COUNT = 6
NUMPAD_PADS = 0x80023288        # u16 pad bits per numpad direction 0-9 (script steps)
DIRECTION_MASKS = 0x800232A8    # u16 per numpad direction 0-9: its branch command direction bit
DIRECTION_PADS = 0x800232BC     # u16 pad bits per numpad direction 0-9 (plain commands)
BUTTON_PADS = 0x800232D0        # u16 pad bits of command bits 0-3
SIDE_STEP_SCRIPTS = 0x800232DA  # two scripts, 24 bytes apart
SIDE_STEP_STRIDE = 24
TAP_FORWARD, TAP_BACK = 0x8001006C, 0x80010078   # the sequences of commands 0xC001 / 0xC002
BACK_DASH = 0x80022EB2          # FUN_8005968C
WAKE_UP = 0x80022E96
KING_THROWS = 0x8002334A        # 14-byte scripts: three command throws
KING_VS_CROUCH = 0x8002332E     # two
KING_GROUND = 0x80023312        # two
KING_SCRIPT_STRIDE = 14
OGRE_ESCAPES = 0x80023308       # u16 x 4: pads against Ogre's fire breath
ACTIONS = 0x800230E0            # u16 x 6: the neutral actions
EVASION_STATES = 0x800230EC     # u8 at stride 2 x 7
HOOKS = 0x800233A0              # 10 x (u16 bank, u16 pad, u32 hook A, u32 hook B)
HOOK_COUNT = 10
# AiHookForBank's hooks by address; "idle" hooks return -1 (no action).
HOOK_NAMES = {
    0: "", 0x80062BAC: "vs_paul", 0x80062804: "as_king", 0x80061E70: "vs_yoshimitsu", 0x80062C7C: "idle",
    0x80062C84: "as_hwoarang", 0x80062C10: "idle", 0x80062C18: "idle", 0x80062C20: "idle",
    0x800621D8: "vs_ogre", 0x80062C28: "vs_gon",
}
BANK_RECORDS = 0x80022F80       # per bank type 16 bytes: s16 counter move, u32 parry scripts, setups
BANK_RECORD_COUNT = 22          # bank types 0-21
FORCE_WORDS = 0x80023210        # Tekken Force: (s16 x 3) per group (stride 0x1E) and level
FORCE_WORD_COUNT = 45


def _steps(disc: Disc, addr: int) -> list[int]:
    """An input script at `addr`: its first step, then the steps up to the 0 terminator."""
    out = [disc.exe_u16(addr, 1)[0]]
    while (step := disc.exe_u16(addr + 2 * len(out), 1)[0]) != 0:
        out.append(step)
    return out


def _bank(disc: Disc, bank: int) -> dict:
    rec = BANK_RECORDS + 16 * bank
    counter = disc.exe_s16(rec, 1)[0]
    parry_high, parry_low, setups = disc.exe_u32(rec + 4, 3)
    entries = []
    if setups:
        p = setups
        while True:
            chance, slot = disc.exe_s16(p, 2)
            if chance < 0:
                break
            # AiUpdate starts the script past its first word (the sequence's window).
            entries.append([chance, slot, _steps(disc, disc.exe_u32(p + 4, 1)[0] + 2)])
            p += 8
    return {
        "counter": counter,
        "parry_high": _steps(disc, parry_high) if parry_high else [],
        "parry_low": _steps(disc, parry_low) if parry_low else [],
        "setups": entries,
    }


def convert(disc: Disc, out: Output) -> None:
    hooks = []
    for k in range(HOOK_COUNT):
        bank, pad = disc.exe_u16(HOOKS + 12 * k, 2)
        hook_a, hook_b = disc.exe_u32(HOOKS + 12 * k + 4, 2)
        hooks.append([bank, HOOK_NAMES[hook_a], HOOK_NAMES[hook_b]])
    out.write_json("tables/ai.json", {
        "params": [[disc.exe_s16(AI_PARAMS + AI_GROUP_BYTES * g + AI_LEVEL_BYTES * lv, AI_WORDS)
                    for lv in range(AI_LEVELS)] for g in range(AI_GROUPS)],
        "band_thresholds": [disc.exe_s16(BAND_THRESHOLDS + 12 * c, 6) for c in range(BAND_THRESHOLD_COUNT)],
        "band_reach": disc.exe_u32(BAND_REACH, BAND_COUNT),
        "approach_reach": disc.exe_u32(APPROACH_REACH, BAND_COUNT),
        "numpad_pads": disc.exe_u16(NUMPAD_PADS, 10),
        "direction_masks": disc.exe_u16(DIRECTION_MASKS, 10),
        "direction_pads": disc.exe_u16(DIRECTION_PADS, 10),
        "button_pads": disc.exe_u16(BUTTON_PADS, 4),
        "side_steps": [_steps(disc, SIDE_STEP_SCRIPTS + SIDE_STEP_STRIDE * s) for s in range(2)],
        "tap_forward": _steps(disc, TAP_FORWARD + 2),
        "tap_back": _steps(disc, TAP_BACK + 2),
        "back_dash": _steps(disc, BACK_DASH),
        "wake_up": _steps(disc, WAKE_UP),
        "king_throws": [_steps(disc, KING_THROWS + KING_SCRIPT_STRIDE * k) for k in range(3)],
        "king_vs_crouch": [_steps(disc, KING_VS_CROUCH + KING_SCRIPT_STRIDE * k) for k in range(2)],
        "king_ground": [_steps(disc, KING_GROUND + KING_SCRIPT_STRIDE * k) for k in range(2)],
        "ogre_escapes": disc.exe_u16(OGRE_ESCAPES, 4),
        "actions": disc.exe_u16(ACTIONS, 6),
        "evasion_states": disc.exe_u8(EVASION_STATES, 14)[::2],
        "hooks": hooks,
        "banks": [_bank(disc, b) for b in range(BANK_RECORD_COUNT)],
        "force_words": disc.exe_s16(FORCE_WORDS, FORCE_WORD_COUNT),
    })
