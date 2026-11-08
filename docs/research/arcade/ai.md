# The CPU opponent: arcade World E1 against PS1 Japan Rev.1

The port is `remake/core/arcade/arcade_cpu*.gd`, its tables come from `tools/remake_import/arcade_ai_tables.py`.

Rules used here: `confirmed` means read on both sides, in the arcade decompile or capstone disassembly (`work/arcade/decomp_full/arcade_e1_full.exe.c`, `work/arcade/prg_world_e1.unpacked.bin`) and on the PS1 side in the decompile (`work/decomp/SLPS_013.00.c`) or the verified ports (`tools/research/ai_update.py`, `tools/research/ai_sim.py`). `inferred` means one side only, or a conclusion drawn from what was read. Nothing was run in a harness: the arcade logic below is read code, except the few RAM dump checks, which are marked. "Remake" means `remake/core/ai/ai_decision.gd` and `cpu_opponent.gd`, with what both builds share in their bases `cpu_decision.gd` (the movement picks, the guard test), `cpu_machinery.gd` (the draws, `level_vs_state`, the row and hint names, script start, command pad, approach reset, the side choice and the common rules of the Paul, Hwoarang and Ogre-side hooks) and `cpu_record.gd` (the record fields both builds hold).

## Headline

- **Same design, older build.** Every PS1 step exists, in a chain of small functions instead of one giant `AiUpdate`. Record fields are s32 instead of s16, predicates are function pointers passed to one marking loop, and fighter fields are read live instead of cached.
- **The arcade CPU really plays strings.** The follow-up list code that PS1 killed (bug #10) is live, with its words and caps, and so is `whiff_punish_ok`. This is the largest behavioural difference. Strings proper start only outside attract (`strings_on`, as on PS1); planned follow-ups and links also run in attract.
- **Parameters have another shape.** Arcade: 2 region groups × 5 difficulties × 10 levels × 60 s16 (`0x801FFE04`). PS1: 3 × 10 × 55. All values come from a ramp of 17 distinct records; PS1 groups 1 and 2 are exact slices of it.
- **Most PS1 AI bugs are PS1-only.** #10, #11, #17 (as written), #18, #19, #20, #23 do not exist in that form. #21 and #22 are present.
- **Word draws use `rand()&0xFFF`**, not the LCG. The uniform rolls `n*((rand()+LCG)&0x7FFF)>>15` are unchanged.

## 1. Function map

The AI range `0x801C2F6C`–`0x801CDB4C` has 70 Ghidra functions in the decompile (the brief counts 67). All are listed. PS1 "inline" means a part of `AiUpdate` (`0x80059B78`); the name is the port's function.

| PS1 name @ addr | Arcade FUN @ addr | Confidence, evidence |
|---|---|---|
| `random_below` FUN_800569D0 | `FUN_801c2f6c` | `confirmed`: same formula, same LCG step. |
| `AiLoadParams` 0x80061770 | `FUN_801c2fcc` | `confirmed` as a role; indexing differs (section 2). |
| inline timers (`approach`, `kind`, `hold`) | `FUN_801c3118(a,b)` | `confirmed`: `+0x4C=a, +0x50=b, +0x5C=a+0x3C` (PS1 `0xFA,2,0x136`). |
| inline timers | `FUN_801c3134(a)` | `confirmed`: `+0x4C=a, +0x50=0, +0x5C=a+0x28`. |
| `AiInitRound` 0x8005993C (entry) | `FUN_801c3158` | `confirmed`: wrapper, called from the round set-up. |
| `AiInitRound` + `AiReset` 0x800596B0 | `FUN_801c3178` | `confirmed`: merged, loops over 2 records. |
| `AiUpdate` entry | `FUN_801c3614` | `confirmed`: wrapper called from the input routine (`FUN_8018e000` area). |
| `AiUpdate` entry and exit | `FUN_801c3634(f,*held,*pressed)` | `confirmed`: sets REC, SELF, OPP; `pressed = pad & (pad ^ prev)`. |
| `_finish` | `FUN_801c3730` | `confirmed`. |
| `_decide` | `FUN_801c3c74` | `confirmed`: writes the step id to `0x8021F394`; dumps show ids 2, 5, 9, 11, 99 (`confirmed`, RAM). |
| `AiStartScript` 0x80061B24 + `AiPadFromStep` 0x80061AC4 | `FUN_801c3ea0` | `confirmed`. |
| `AiPressCommand` 0x80061BA8 | `FUN_801c3f30(cmd,target)` | `confirmed`. |
| inline `f.move_row != null` | `FUN_801c4044` | `confirmed`: fighter `+0xEC` (PS1 `+0x1A4`). |
| script step of `_fixed_input` | `FUN_801c4058` | `confirmed`, plus a pending pad `+0xA` nothing sets. |
| escape row pick in `_throws` | `FUN_801c4108` | `confirmed`: logic differs (section 4). |
| `_throw_follow_ups` | `FUN_801c43d4` | `confirmed`. |
| thrower part of `_throws` | `FUN_801c4628` | `confirmed`. |
| `_throws` | `FUN_801c473c` | `confirmed`. |
| `_situation` + `_track` + `_distance_bands` + `_opponent_attack` + `_guard_state` + `_needs_guard` | `FUN_801c4898` | `confirmed`: always returns 0. |
| `AiCollectCandidates(0)` 0x80056A4C | `FUN_801c560c` | `confirmed`. |
| `AiCollectCandidates(1)` | `FUN_801c5cb8` | `confirmed`. |
| `hint_never_open` FUN_80057300 | `FUN_801c5fe4` | `confirmed`. |
| `reach_ok` (and the approach form) | `FUN_801c62a8(move,band,row)` | `confirmed`: row 0 band reach, row 1 approach reach. |
| `level_vs_state` | `FUN_801c6300(move,kind)` | `confirmed`: both callers (predicates `0x801C6AFC`, `0x801C6BA8`) pass kind 1, which equals PS1; the stricter kind 0 is dead. |
| `_can_counter` / unsafe approach | `FUN_801c644c(row)` | `confirmed`. |
| `mark_candidates` (inlined loops) | `FUN_801c64d4(pred)` | `confirmed`. |
| unmark loops (`no_strings`, `filter_no_lows`) | `FUN_801c6598(pred)` | `confirmed`: returns in `v0` the number of hit candidates whose mark was above 0 (Ghidra's void is wrong) and subtracts it from `+0xB4`. At the end of collection all marks are 0, so `FUN_801c560c` subtracts 0. |
| slot list of reaction 5 | `FUN_801c7350(cand)` | `confirmed`: 2 s16 at `0x8017A5A4`. |
| `filter_defence` FUN_800582A0 | `FUN_801c757c` | `confirmed`: bug #21 present. |
| throw part of `_approach_attack` | `FUN_801c7810` | `confirmed`. |
| `filter_side_steps_then_quick` FUN_80058AC0 | `FUN_801c78e8` | `confirmed`. |
| `AiAfterAttack` 0x80058C40 | `FUN_801c79a8` | `confirmed`. |
| none | `FUN_801c7a80` | `confirmed`: identity, called once from `FUN_801c7b5c`; arcade only. |
| walk of `marked_pick` | `FUN_801c7a88` | `confirmed`: uniform both ways. |
| `AiExecuteCandidate` 0x80058D6C | `FUN_801c7b5c` | `confirmed`. |
| strings list of `_new_move` | `FUN_801c7c4c` | `confirmed`. |
| `_planned_follow_ups` | `FUN_801c7d50` | `confirmed`: logic differs. |
| links list of `_new_move` | `FUN_801c7f6c` | `confirmed`. |
| `_new_move` | `FUN_801c8178` | `confirmed`: logic differs. |
| `branch_open_to` FUN_80058ED0 | `FUN_801c832c` | `confirmed`. |
| list test for `RECOVERED` | `FUN_801c88a0(cond)` | `confirmed`. |
| `_duck_or_back` | `FUN_801c88f8` | `confirmed`. |
| `_follow_through` | `FUN_801c894c` | `confirmed`. |
| `_choose`, `_vs_grounded`, `_vs_stance`, `_approach_attack` | `FUN_801c8a18(wait)` | `confirmed`. |
| `_attack`, `_last_resort` | `FUN_801c9854` | `confirmed`. |
| `whiff_punish_ok` FUN_800593D4 (dead on PS1) | `FUN_801c9cb4(target)` | `confirmed`: live here. |
| strings pressing, dead part of `_expire_lists` | `FUN_801c9dac` | `confirmed`: live here. |
| planned pressing, dead part of `_expire_lists` | `FUN_801ca204` | `confirmed`: live here. |
| links pressing, dead part of `_expire_lists` | `FUN_801ca6a8` | `confirmed`: live here. |
| `_hold_guard` | `FUN_801caeb4` | `confirmed`: no whiff draw. |
| `_avoid_air_attack` | `FUN_801caf94` | `confirmed`. |
| `_pick_movement`, `_by_distance`, `_by_closing` | `FUN_801cb2f0` | `confirmed`: same numbers. |
| `_movement`, `_do_movement` | `FUN_801cb698` | `confirmed`. |
| `_move` fall-through | `FUN_801cbcec` | `confirmed`. |
| alternate-frame rule of `_fixed_input` | `FUN_801cbd3c` | `confirmed`: other place in the chain. |
| `_stance` | `FUN_801cbd84` | `confirmed`: extra branch. |
| inline "attack ≠ 0, ≠ 0x607, or +0x290 > 0" | `FUN_801cbeb8` | `confirmed`. |
| `_crouch_and_actions`, `_action_mask` | `FUN_801cbef8` | `confirmed`. |
| `_reaction_kind` | `FUN_801cc4b8` | `confirmed`: kinds renumbered. |
| `filter_quick_attacks` as a wrapper | `FUN_801cccec` | `confirmed`. |
| `_counter` | `FUN_801ccd14` | `confirmed`: extra defence filter. |
| `_react`, `_evade` | `FUN_801ccf24` | `confirmed`. |
| `AiCallHook` 0x800594C4 (hook A) | `FUN_801cd708` | `confirmed`. |
| `AiCallHook` (hook B) | `FUN_801cd828` | `confirmed`. |
| `_pad_back_on_even` FUN_800595E4 | `FUN_801cd948` | `confirmed`. |
| `AiSideStep` 0x80061D40 | `FUN_801cda04` | `confirmed`. |
| `install_no_lows` FUN_8005967C | `FUN_801cdac4` | `confirmed`. |
| back dash FUN_8005968C | `FUN_801cdad8` | `confirmed`. |
| inline `o+0xA0 == 6` | `FUN_801cdb38` | `confirmed`. |
| inline `band > x ? forward : -1` | `FUN_801cdb4c(x)` | `confirmed`. |

**Past the listed range or not Ghidra functions (hooks).**

| PS1 | Arcade address | Confidence |
|---|---|---|
| `_ogre_side` (pre-calc, then step) | `0x801CDB78`, `0x801CDBE8` | `confirmed`. |
| `AiHookVsYoshimitsu` 0x80061E70 | `0x801CDC98` | `confirmed`. |
| `AiHookVsPaul` 0x80062BAC | `0x801CE078` | `confirmed`. |
| `AiHookVsOgre` 0x800621D8 | `0x801CE160` | `confirmed`. |
| `AiHookAsKing` 0x80062804 | `0x801CE618` | `confirmed`. |
| idle 0x80062C7C | `0x801CE97C` | `confirmed`. |
| `AiHookAsHwoarang` 0x80062C84 | `0x801CE984` | `confirmed`. |
| `AiHookForBank` 0x80062B50 | `FUN_801cea0c(which,bank)` | `confirmed`. |
| `AiHookVsGon` 0x80062C28 | none | `confirmed` absent. |
| idle hooks returning -1 | `0x801CE070`, `0x801CE0E0`–`0x801CE158`, `0x801CE5D8`–`0x801CE610`, `0x801CEA04` | `confirmed`. |

**Predicates passed to `FUN_801c64d4` / `FUN_801c6598`** (labels; the argument is the candidate record). All read in disassembly.

| PS1 | Arcade | Note |
|---|---|---|
| mark all | `0x801C6668` | |
| desperation (`_last_resort`) | `0x801C6670` | row `+0x18 & 0x80` |
| buffer flag (`no_strings`) | `0x801C6684` | row `+0x18 & 0x20` |
| `filter_attacks` FUN_8005758C | `0x801C6698` | |
| `filter_attacks_no_special` FUN_800576DC | `0x801C6784` | |
| `filter_no_lows` FUN_800616B4, also action 0x10 | `0x801C6864` | |
| `filter_fast_attacks` FUN_80057820 | `0x801C689C` | startup below 12 (PS1 14) |
| `filter_vs_posture` FUN_80057954 | `0x801C698C` | |
| neutral-cooldown pick of `_choose` | `0x801C6ABC` | state `& 0xA0000 == 0x80000`, no air window |
| `filter_punish_level` FUN_80057AC4 | `0x801C6AFC` | |
| `filter_punish_level_no_high` FUN_80057C88 | `0x801C6BA8` | |
| `filter_plain_attacks` FUN_80057E48 | `0x801C6C60` | |
| `_side_step_or_special` | `0x801C6D30` | bits `0x600000` read from word `+8`, PS1 state `+4` |
| plain throws, throw rows | `0x801C6E30`, `0x801C6E6C` | |
| `_low_or_hint` (`0x51F`) | `0x801C6EE4` | no `first < 0x51` |
| `_low_or_hint` (`0x51F`, `0x10F`) | `0x801C6F2C` | no `first < 0x51` |
| wake-up (first row condition `0x35`, not "never") | `0x801C6F7C` | |
| `filter_quick_attacks` FUN_80058040 | `0x801C6FB4` | |
| `filter_quick_attacks_no_high` FUN_8005817C | `0x801C707C` | |
| crouching attacks in reach (kind 1 against `0x412`) | `0x801C719C` | |
| guard high, guard low of `filter_defence` | `0x801C721C`, `0x801C7260` | both always exclude state bit `0x100` |
| `is_neutral` | `0x801C7290` | |
| `_hint_ground` | `0x801C72C0` | |
| command `0xC001`, `0xC002` | `0x801C7300`, `0x801C731C` | |
| `state & 0x20000` | `0x801C7338` | |
| slot equals `0x8017A5B4[0]` (reaction 6) | `0x801C7390` | |
| rare neutral pick excluding the reaction slots | `0x801C73CC` | |
| air attack pick of `_approach_attack`, air-cooldown pick of `_choose` | `0x801C7484`, `0x801C74E0` | |
| row byte `+8` in `0x1C`–`0x1D`; `== 0x1E` | `0x801C753C`, `0x801C7558` | second is arcade only |

**Unreferenced code.** A search for `jal`, `j`, data words and `lui`/`addiu` pairs over the whole program finds no reference to `0x801C5FA0`, `0x801C8120`, `0x801CAB20`, `0x801CD980`, `0x801CDB00`, or the predicates `0x801C695C`, `0x801C6D94`, `0x801C6E10`, `0x801C6EAC`, `0x801C6EC8`, `0x801C7124`, `0x801C7200`, `0x801C7430`, `0x801C7444`, `0x801C7574` (`confirmed` by search; a register-built pointer cannot be fully excluded). `0x801C8120` and `0x801CAB20` are older list builders; the latter has the "count stays 0" pattern of PS1 bug #10, which suggests where that bug came from (`inferred`).

## 2. Table addresses

Reading code is the arcade routine that reads the table. All addresses read in that code (`confirmed`) unless stated. "Lead" is `work/arcade/fight/table_search.json`.

| Table (`tools/remake_import/ai.py`) | PS1 | Arcade | Count, layout, reader | Lead |
|---|---|---|---|---|
| `AI_PARAMS` | `0x80023418`, 3×10×55 s16 | `0x801FFE04`, 2×5×10×60 s16 | `base + group·6000 + difficulty·1200 + level·120`, 0x78 bytes copied to rec `+0x2D4`; `FUN_801c2fcc`. Ends at `0x80202CE4`. | `0x801FFEA8` refuted: it is base+0xA4, an alignment artefact. |
| `BAND_THRESHOLDS` | `0x80098640` | `0x80202CE4` | 12 bytes per char id, 22 ids + one zero row (id 22); self to rec `+0x34C`, opponent to `+0x358`; `FUN_801c3178`. Char 17 and char 20 start at 1408 (PS1 1280, 1536); all else equal. | Confirmed. |
| `BAND_REACH` | `0x80098610` | `0x801FFD38` | u32×6, row 0 of `FUN_801c62a8`. Identical values. | Confirmed. |
| `APPROACH_REACH` | `0x80098628` | `0x801FFD50` | u32×6, row 1. Identical values. | Confirmed. |
| `NUMPAD_PADS` | `0x80023288` | `0x8017A2A0` | u16×10, arcade pad bits; `FUN_801c3ea0`, `FUN_801c4058`. | `0x80178C51` refuted. |
| `DIRECTION_MASKS` | `0x800232A8` | `0x8017A2C0` | u16×10, read downward from `0x8017A2D2`; `FUN_801c3f30`. Identical. | Confirmed. |
| `DIRECTION_PADS` | `0x800232BC` | `0x8017A2D4` | u16×10; `FUN_801c3f30`. | `0x80178C51` refuted. |
| `BUTTON_PADS` | `0x800232D0` | `0x8017A2E8` | u16×4; `FUN_801c3f30`. | `0x801984F2` refuted. |
| `SIDE_STEP_SCRIPTS` | `0x800232DA` | `0x8017A2F2` | 2 scripts, stride 0x18; `FUN_801cda04`. Identical. | Confirmed. |
| `TAP_FORWARD`, `TAP_BACK` | `0x8001006C`, `0x80010078` | `0x80010290`, `0x8001029C` | used at +2; `FUN_8018ea28`. Identical. | Confirmed. |
| Motion sequences | `0x800958F4` (0x3F), `0x800959F0` (0x29) | `FUN_8018d4cc` (`0xC00C`–`0xC04A`, 63), `FUN_8018dd2c` (`0xC7FF`–`0xC827`, 41) | Switches, not pointer tables. First code is `0xC00C` (PS1 `0xC00E`). Contents belong to the [moves.md](moves.md). | |
| `BACK_DASH` | `0x80022EB2` | `0x8017A33E` | `FUN_801cdad8`, also `FUN_801ccf24`. Identical. | Confirmed. |
| `WAKE_UP` | `0x80022E96` | `0x8017A322` | `FUN_801c8a18`. Identical. | Confirmed. |
| `KING_THROWS` | `0x8002334A` | `0x8017A762` | stride 14, `(rand&0xFFF)%3`; `0x801CE618`. Identical. | Confirmed. |
| `KING_VS_CROUCH` | `0x8002332E` | `0x8017A746` | stride 14, `rand&1`. Identical. | Confirmed. |
| `KING_GROUND` | `0x80023312` | `0x8017A72A` | stride 14, `rand&1`. Identical. | Confirmed. |
| `OGRE_ESCAPES` | `0x80023308` | `0x8017A720` | u16×4, `rand&3`; `0x801CE160`. Same buttons in arcade bits. | No lead. |
| `ACTIONS` | `0x800230E0`, u16×6 | `0x8017A5B8`, u32×6 | `FUN_801cbef8`. Same values 1..0x20. | `0x8017A2C2` refuted: inside the masks. |
| `EVASION_STATES` | `0x800230EC`, u8 stride 2 ×7 | `0x8017A5D0`, u32×7 | `FUN_801ccf24`. Same seven values, no 6 or 8. | `0x80204EF4` refuted. |
| `HOOKS` | `0x800233A0`, 10 × (u16,u16,u32,u32) | `0x8017A78C`, 22 + end × (s32 bank, hook A, hook B) | Stride 12; `FUN_801cea0c`. Row 22 holds bank `0x16` and nulls. | `0x80025F34` refuted. |
| `BANK_RECORDS` | `0x80022F80`, 22×16 | `0x8017A434`, stride 16 | `+0` counter (read as s32), `+4` parry high, `+8` parry low, `+0xC` setups (8-byte entries: s16 chance, s16 slot, script pointer used at +2; chance < 0 ends). Readers `FUN_801cc4b8`, `FUN_801ccf24`, `FUN_801c8a18`. Rows above bank 16 look unreachable (see below). | `0x8001F4CC` refuted. |
| `FORCE_WORDS` | `0x80023210` | none | No Tekken Force word is read in the AI code (`confirmed` absent). | |

**Other tables.**

- Reaction slots: `0x8017A5A4` (2 s16) and `0x8017A5B4` (1 s16); values in section 3 (slots).
- Scripts `0x8017A32A` and `0x8017A352`: the first has a reader in unreferenced `0x801CDB00` only; the second in movement case 7 of `FUN_801cb698`, which `FUN_801cb2f0` never returns.
- Sine table `0x80175944`, for the distance wobble.
- Hook rows: real hooks are A0 vs Paul, A4 vs Yoshimitsu, A14 and A20 vs Ogre, B3 King, B4 idle, B6 Hwoarang. Every other hook A is an idle hook, not null, so its word `+0x312` draw still consumes `rand`; every other hook B is null.

**Bank records against PS1** (`confirmed`, both dumped). The counter flags are identical per bank. Differences:

- Setups: the slots are the renumbered ones (PS1 `0x3B` → `0x2C`, `0x15` → `8`). Banks 6, 9, 13 use chance 1024 (PS1 2048). Bank 2's and banks 0, 5's chance stays 1024.
- Parry scripts: same scripts, except bank 7's high parry at `0x8017A40C`, which reads `0 0 0x900` where PS1 has `0 5 0x900`. `FUN_801c3ea0` ends a script whose second step is 0, so this entry presses nothing, and `_steps()` in `ai.py` already yields `[0]` for it.

**Bank range.** The arcade's index table `0x8006D430` (`0x3B78` bytes per type) has 17 real types, 0–16; reads at type 17 and up give values that are not indexes (`confirmed`). The AI tables keep 22 rows, so rows 17–21 are unreachable (`inferred`; the [flow-and-screens.md](flow-and-screens.md) owns the fighter's type). Bank 15 shares its move rows with bank 9. The arcade's row 20 holds the Ogre hook as hook A; PS1 has no row for bank 20 and lists bank 14 twice.

### Parameters and difficulty

**Indexing** (`FUN_801c2fcc`, `confirmed`):

- `group`: 0 for region codes 0 and 1, 1 otherwise. `DAT_8021fb74` copies `0x8036ECF4`, the region code from ROM word `0x1FC201FE` (`0xFFFF` → 1 Japan; `0xFE00` → 2 World; `0xFD01` → 3 US; `0xFC02` → 4; else 0). World E1 → group 1; the dumps hold region code 2 (`confirmed`, RAM).
- `difficulty`: `DAT_8021fd28`, the test-menu byte `0x8036EC4F` ("DIFFICULTY LEVEL", descriptor `0x801FC77C`, range 0–4). Default 1 for region "other", 2 for codes 2, 3, 4. The game-mode set-up forces it to 1 in its cases 3 and 4 (decompile lines 31025, 31039; which modes these are belongs to the [flow-and-screens.md](flow-and-screens.md)).
- `level`: `DAT_8021fd40`, byte `[2]` of the ladder entry (`FUN_801b66d8`), the stage index 0–9. Attract forces 4. Any index out of range falls back to `(group 0, difficulty 1, level 6)`.
- After the copy `+0x260 = max(+0x30E, +0x30A)`.

**RAM check** (`confirmed`): all 20 dumps are attract, difficulty 2, level byte 0. In the 18 with records loaded, `+0x348` names "J HARD #5" for both CPUs, as attract's level index 4 predicts.

**Shape of a record.** 60 s16: words 0–3 are the four hold lengths (PS1 keeps these in bytes of words 0–1, same values); **arcade word n+2 = PS1 word n for n ≥ 2**, so rec offset = PS1 offset + `0xA0` (PS1 `+0x23C` ↔ `+0x2DC`, `+0x27E` ↔ `+0x31E`). Words 55–57 are zero. Words 58–59 are a u32 pointer to a name string (`0x8017A8A0`–`0x8017AB04`: "J EASY #1" to "J U.HARD #10"). No reader was found in the AI range, so its use for debugging is `inferred`.

Arcade words read: 0–3, 4–11, 13–32, 37, 38, 40, 47, 49, 51, 52, in PS1 numbering 2–9, 11–30, 35, 36, 38, 45, 47, 49, 50. So:

- PS1 word 10 is not read: `FUN_801c4628` uses the constant `0xB33` instead.
- PS1 word 50, "never read" on PS1, is read: `+0x33C`, the arcade-only stance branch.
- PS1 words 23–28 (`+0x306`–`+0x310`) are the live follow-up words.
- PS1's common parameters at `+0x2A6` (`0x8002408E`) are absent.

**Does difficulty map the same? No.** PS1's group is a console option and its level the stage; the arcade adds a region group. There are only 17 distinct records (word for word, name pointer aside; `confirmed`, compared by script). They are numbered here by first appearance in the table. Each column is a stretch of one ramp, 0 1 2 3 4 8 5 6 7 9 10 … 16; that it runs easy to hard is `inferred`. All debug names say "J", also in group 1.

| Arcade (group, difficulty, debug name) | Records at levels 1–10 |
|---|---|
| 0, 0 EASY | 0 0 0 1 2 3 4 5 6 7 |
| 0, 1 NORMAL | 0 1 2 3 4 8 5 6 6 7 |
| 0, 2 HARD | 2 3 4 8 5 6 7 9 10 11 |
| 0, 3 V.HARD | 2 3 5 6 7 9 10 11 12 13 |
| 0, 4 U.HARD | 4 8 7 9 10 11 12 13 14 15 |
| 1, 0 EASY | 0 1 2 3 4 8 5 6 7 9 |
| 1, 1 NORMAL | 2 3 4 8 5 6 7 9 10 11 |
| 1, 2 HARD | 2 3 5 6 7 9 10 11 12 13 |
| 1, 3 V.HARD | 4 8 6 7 9 10 11 12 13 14 |
| 1, 4 V.HARD | 4 8 9 10 11 12 13 14 15 16 |

PS1 group 1 equals arcade (0,1) word for word; PS1 group 2 equals arcade (0,4) (PS1 words 2–54 against arcade 4–56). PS1 group 0 matches no arcade record: its level 1 is 4 words from record 0, higher levels up to 23 words, so it is console-only (`inferred`). World E1 at its default difficulty 2 uses (1,2).

## 3. Record field maps

### AI record

Base `0x8029CF00`, stride `0x364`, 2 records (PS1 `0x8009F6C0`, `0x330`, up to 3). Candidates `0x8029D5C8`, 12 bytes × 180. `confirmed` throughout unless noted. PS1 offsets and names are those of `remake/core/ai/ai_record.gd`.

| PS1 +offset (name) | Arcade |
|---|---|
| `+0x00` slot | `+0x00` (int) |
| `+0x02` frame_count | `+0x04` |
| `+0x04` pad | `+0x06` |
| `+0x06` prev_pad | `+0x08` |
| none | `+0x0A` pending pad; only ever written 0, so dead |
| `+0x08` script | `+0x0C` |
| `+0x0C` (no remake field) | `+0x10`: the move index table of `FUN_8018ed00` |
| `+0x10` target | none, opponent is `1 − slot` |
| `+0x14` band | `+0x20` |
| `+0x18` reach_band | `+0x24` |
| `+0x1C` distance | global `DAT_8021fd90` |
| `+0x20` prev_distance | `+0x30` |
| `+0x24` distance_change | `+0x34` |
| none | `+0x28` wobble, `+0x2C` phase |
| `+0x28` move_changed | `+0x1C` |
| `+0x2A` far_count | `+0x38` |
| `+0x2C` move_frames | `+0x3C` |
| `+0x2E` angle | fighter `+0x2C`, read live |
| `+0x30` health_seen | `+0x40` |
| `+0x34` pose_frame_seen | `+0x44` |
| `+0x36` neutral_action | `+0x48` |
| `+0x38` approach | `+0x4C` |
| `+0x3A` approach_kind | `+0x50` |
| `+0x3C` crouching | `+0x54` |
| `+0x3E` guarding | `+0x58` |
| `+0x40` approach_hold | `+0x5C` |
| `+0x42` setup_cooldown | `+0x60` |
| `+0x44` neutral_cooldown | `+0x64` |
| `+0x46` air_cooldown | `+0x68` |
| `+0x48` direction_hold | `+0x6C` |
| `+0x4A` crouch_timer | `+0x70` |
| `+0x4C` crouch_attack_hold | `+0x74` |
| `+0x4E` move_frame_seen | `+0x78` |
| `+0x50` attacking | `+0x7C` |
| `+0x52` special_open | `+0x80` |
| `+0x54` whiff_timer | `+0x84` |
| `+0x58` collected_move | `+0x88` |
| `+0x5C` pressed_move | `+0x8C` |
| `+0x60` last_attack | `+0x90` |
| `+0x64` situation | none; conditions `0x24`–`0x27`, `0x30` computed live with the same tests in `FUN_8018fb3c` |
| none | `+0x94` default continuation move (written in `FUN_801c560c`, cleared in `FUN_801c4898`, no reader in the AI range) |
| `+0x68` wait | `+0x98` |
| `+0x6A` guard_holds | `+0x9C` |
| `+0x6C` guard_delay | `+0xA0` |
| `+0x6E` cancel_wait | `+0xA4` |
| none | `+0xA8`, `+0xAC`: only ever written 0, so dead (one dead branch in `FUN_801caeb4`) |
| `+0x70` candidate_count | `+0xB0` |
| `+0x72` marked_count | `+0xB4` |
| `+0x74` hook_opponent | `+0xB8` (function pointer) |
| `+0x78` hook_own | `+0xBC` |
| `+0x7C` filter_no_lows | `+0xC0` (the predicate pointer) |
| `+0x80` announced_frames | `+0xC4` |
| `+0x84` passed_frames | `+0xC8` |
| `+0x88` vs_stance | `+0xCC` |
| `+0x8A` move_block | `+0xD0` |
| `+0x8C` guard_suspend | `+0xD4` |
| `+0x8E` parried | `+0xE4` |
| `+0x8F` punish | `+0xE8` |
| `+0x90` throw_next | `+0xEC` |
| `+0x91` throw_chance | `+0xF0` |
| `+0x92` evade_reason | `+0xF4` |
| `+0x93` guard_memory | `+0xF8` |
| `+0x94` evasion | `+0xFC` |
| `+0x96` throw_steps | `+0x100` |
| `+0x98` throw_list | `+0x104` |
| `+0xA0` throw_move | `+0x10C` |
| `+0x9C` throw_press_frame | `+0x128` |
| `+0xBC` throw_row | `+0x12C` |
| `+0xC0` strings_on | `+0x130` |
| `+0xC2` strings_count | `+0x134` |
| `+0xC4` strings (4) | `+0x138` |
| `+0xD4` no_strings | `+0x148` |
| `+0xD8` planned_on | `+0x150` |
| `+0xDA` planned_count | `+0x154` |
| `+0xDC` planned (48) | `+0x158` |
| `+0x1CC` link_skip | `+0x220` |
| `+0x1A0` links_on | `+0x224` |
| `+0x1A2` links_count | `+0x228` |
| `+0x1A4` links (10) | `+0x22C` |
| `+0x1D0` link_last | `+0x258` |
| `+0x1D2` attacks_in_row | `+0x25C` |
| `+0x1D4` attack_limit | `+0x260` |
| `+0x1D8` (nothing writes) | `+0x264` |
| `+0x1DC` history (8) | `+0x268`, `+0x26C`, `+0x270`: shift register of 3, `+0x268` newest |
| `+0x1FC` history_at, `+0x1FE` reload_timer | none |
| `+0x200` opp_breath | `+0x274`, computed at frame end from bank and slot |
| `+0x201` opp_gon_special | none |
| `+0x202` adaptive | `+0x278`: all 3 history entries equal; no reload |
| `+0x204` opp_move_changed | `+0x27C` |
| `+0x206` | `+0x280` |
| `+0x208` opp_down | `+0x284` |
| `+0x20A` opp_until | `+0x288` |
| `+0x20C` opp_coming | `+0x28C` |
| `+0x20E` opp_unblockable | `+0x290` |
| `+0x210` opp_charging | `+0x294` |
| `+0x212` coming_seen | `+0x298` |
| `+0x214` opp_grabs | `+0x29C` |
| `+0x216` opp_string | `+0x2A0` |
| `+0x218` | `+0x2A4`: opponent's joint y, written, never read |
| `+0x21A` opp_high | `+0x2AC` |
| `+0x21E` input_mode | none |
| none | `+0x2B0` countdown (0x32 after a neutral-action attack), `+0x2B4` counter of it, never read otherwise |
| none | `+0x2B8` neutral frame counter |
| `+0x220` own_word | `+0x2BC` |
| `+0x224` own_state | `+0x2C0` |
| `+0x228` own_attack | `+0x2C4` |
| `+0x22C` opp_word | `+0x2C8` |
| `+0x230` opp_state | `+0x2CC` |
| `+0x234` opp_attack | `+0x2D0` |
| `+0x238` params | `+0x2D4` |
| `+0x314` own_bands | `+0x34C` |
| `+0x320` opp_bands | `+0x358` |
| `+0x32C` force_words | none |

### Fighter record

Records `0x8031E154`, `0x8031FC38`. `confirmed` as read by the AI. PS1 offsets are those of `docs/research/code/ai.md` and the ports.

| PS1 +offset (name) | Arcade |
|---|---|
| `+0x12` slot | `+0x14` |
| `+0x16` bank_type | `+0x18` |
| `+0x18` char_id | `+0x1A` |
| `+0x2E` heading_delta | `+0x2A` |
| `+0x30` rel_angle | `+0x2C` |
| `+0x32` facing_quadrant | `+0x2E` |
| `+0x3C` opp_heading_delta, `+0x3E` opp_rel_angle, `+0x40` opp_quadrant | opponent's `+0x2A`, `+0x2C`, `+0x2E`, read directly |
| `+0x54` pose_move | `+0x44` |
| `+0x58` pose_frame | `+0x48` |
| `+0x60` state | `+0x50` |
| `+0x64` attack | `+0x54` |
| `+0x74` throw_state | `+0x64` |
| `+0x87` was_hit_this_move | `+0x73` |
| `+0xA0` cur_slot | `+0x8C` |
| `+0xCE` got_hit | `+0xA3` |
| `+0xD2` whiffed | `+0xA7` |
| `+0xDB` in_air | `+0xA9` |
| `+0xDF` about_to_hit | `+0xAD` |
| `+0x122` power_timer | `+0xDA` |
| `+0x1A4` move_row | `+0xEC` |
| `+0x3E8`, `+0x3EC`, `+0x3F0` body_push | `+0x330`, `+0x334`, `+0x338` |
| `+0x3F4` health | `+0x33C` |
| `+0x3F8` health_max | `+0x340` |
| joint 2 y (`0x8F4 + 0xA0`) | `+0x800` |
| `+0x1278` screen_x | `+0x1154` |
| `+0x1886` ai_slot, `+0x1887` ai_target | none (`+0x14` serves) |

### Move row and branch row

Move row as read by the AI (stride 0x3C):

| PS1 | Arcade |
|---|---|
| `+0x04` state, `+0x08` attack word, `+0x0C` branches | same |
| `+0x14` damage | `+0x12` |
| `+0x19`, `+0x1A` air first, last | `+0x1F`, `+0x20` |
| `+0x24` flags | `+0x18`: PS1 `>>8 & 0x20` → `& 0x20` (buffer), `>>8 & 0x10` → `& 0x10` (launch), `>>8 & 8` → `& 8` (alert), `>>8 & 0x100` → `& 0x80` (power; `inferred`) |
| `+0x2D`, `+0x2E` active first, last | `+0x30`, `+0x31` |
| `+0x10` | not used by the AI |

Branch rows keep the 12-byte layout (`+0` command, `+2` restriction, `+3` condition, `+6` target, `+8` flags, `+9` first, `+0xA` last, `+0xB` entry). Terminator `0xC000`. No `0xC00C` common-row expansion appears in the AI code (`confirmed`): the arcade's `0xC00C` is a motion command (first code of `FUN_8018d4cc`).

Candidates: PS1 target `+0`, branch `+4`, mark `+8`. Arcade mark s16 `+0`, target `+4`, branch row `+8`.

### Pads

| PS1 | Arcade |
|---|---|
| up `0x1000` | `0x2000` |
| forward `0x2000` | `0x400` |
| down `0x4000` | `0x1000` |
| back `0x8000` | `0x800` |
| directions mask `0xF000` | `0x3C00` |
| □ `0x80` | `0x200` |
| △ `0x10` | `0x100` |
| ○ `0x20` | `0x20` |
| ✕ `0x40` | `0x40` |

Script steps keep their format; button bits map `0x100` → `0x200`, `0x200` → `0x100`, `0x400` → `0x40`, `0x800` → `0x20`. The arcade's numpad and direction pad tables hold the same values.

### Slots and character ids in the AI code

Banks and character ids are the same numbers. All of these are read in the code on both sides; the mapping agrees with `work/arcade/fight/slotmap_final.json` unless noted (`confirmed` by that cross-check).

| Use | Bank | PS1 slot | Arcade slot |
|---|---|---|---|
| Hook vs Paul | 0 | `0x2C6`, `0x2C7` | `0x2CA`, `0x2CB` |
| Hook vs Yoshimitsu, wait | 4 | `0x16F` | `0x157` |
| " | 4 | `0x16A`, `0x43A` | `0x152`, `0x453` |
| " stance (`vs_stance`) | 4 | `0x456` | `0x470` |
| " | 4 | `0x458` | `0x472` |
| " | 4 | `0x459`–`0x45B` | `0x473`–`0x475` |
| " returns −1 | 4 | `0x472` | `0x494`; the slot map says `0x494` = PS1 `0x477` and `0x48D` = PS1 `0x472`. No effect: both return −1. |
| " | 4 | `0x49C`–`0x49E` | `0x4C0`–`0x4C2` |
| Hook vs Ogre, breath flag | 14 | `0x16E` | `0x156` |
| Hook vs Ogre, breath flag | 14 | `0xDE4` (undefined on PS1) | `0x904`, **defined**: attack word `0x607`, window 58–126 |
| Hook as Hwoarang | 6 | `0xDE3` (undefined on PS1) | `0x827`, **defined**: no attack, flag 8 |
| King's throw branch | 3 | `0x15` | `8` |
| Setups | 0, 5 | `0x3B` | `0x2C` |
| Setups | 2, 6, 9, 13 | `0x15` | `8` |
| Reaction: counter slots | any | `0x1EE`, `0x6A3` | `0x1DA`, `0x6DE` |
| Reaction: Jin | 9 | `0x22C` | `0x21B` |
| Throw filter, never | | `0x3A7` | `0x3B5` |
| Throw filter | 4 | `0xD41` | `0xE30` |
| Throw filter | 0, 13 | `0xD24`, `0xD32` | `0xE13`, `0xE21` |
| Throw filter | 0, 13 | `0xD25`, `0xD34` | `0xE14`, `0xE23` |
| Throw filter | 0 | `0xDE2` | `0x2E2`; the slot map has no PS1 row for it |
| Throw filter | 4, attract | none | `0xB68`, never for bank 4 in attract |
| Forced escapes | any | `0x189`, `0x17F`, `0x181` | `0x170`, `0x167`, `0x168` |
| Forced escapes | any | `0x18E` | not in the list (its slot is `0x179`) |
| Forced escapes | 9, 0 | `0x172` | `0x15A` |
| Forced escapes | 3 | `0x152` | `0x13B` |
| "Opponent in slot 6" | any | `6` | `6` (map: arcade 6 = PS1 6; the earlier suspicion is cleared) |

The throw filter has the same rules on both sides, in arcade slots: `0x3B5` never; `0xE30` for bank 4 only with `rand&0x70 != 0`; `0xE13`, `0xE21` for banks 0 and 13 only with `rand&0x70 == 0`; `0xE14`, `0xE23` never for banks 0 and 13; `0x2E2` for bank 0 only with `rand&0x70 == 0`. The arcade draws only for a row that needs it and runs the filter on every row walk; PS1 draws once per row, only in `_throw_follow_ups`.

## 4. Decision logic differences

"Same" means same structure and same numbers, after the maps of section 3, with word draws from `rand()&0xFFF` wherever the remake has `lcg_next() & 0xFFF`. That RNG rule is not repeated below. Parity tests read `(+4 & 1) == slot` where the remake reads `frame_count & 1`. `confirmed` throughout unless noted.

### `ai_decision.gd`

- **`update`, `_decide`.** Different order. Arcade chain (step id, function):

  0 `FUN_801c4058` script, 1 `FUN_801c4898` refresh, 2 `FUN_801c473c` throws, 3 `FUN_801cbd84` stance, 5 `FUN_801c4044` queued row, 4 `FUN_801cbef8` neutral actions, 6 `FUN_801cd708` and 7 `FUN_801cd828` hooks, 8 `FUN_801caeb4` hold guard, **9 `FUN_801cbd3c` attract alternate frames**, 10 `FUN_801c8178`, 11 `FUN_801c894c`, 12 `FUN_801ccd14`, 13 `FUN_801ccf24`, **14–16 the live lists**, 17 `FUN_801caf94`, 18 `FUN_801c9854`, 19 `FUN_801cb698`, 99 `FUN_801cbcec`, then `FUN_801c3730` always.

  `FUN_801c3c74` itself does the part of `_situation` that remains: it clears `+0x8C`, counts the frame and caches the six move words, also during a script. With the alternate-frame rule this late, throws, stance, neutral actions, hooks and hold guard run on every attract frame.
- **`_draw`**: `rand()&0xFFF`.
- **`_situation`**: no cached bits; Gon word `|= 0x10000` absent. Breath flag: set in `_finish` from bank 14 and slot (`0x904`, `0x156`), so one frame late, instead of the attack record's first byte.
- **`_fixed_input`**: input modes 0 and 1 absent. Alternate frames: attract only, both CPUs (`(frame & 1) == slot`), and after hooks and hold guard. PS1: while `ai.multi`, only slot 1 on odd frames, before `_track`. Tekken Force absent.
- **`_track`**: same, except `+0x2A0` has no cap at 10. Opponent move changed `+0x27C` is still always 1 (`inferred`: no writer of `+0x264`, `+0x280` found).
- **`_distance_bands`**: same thresholds and margins. Arcade adds `+0x2C += rand&0x3F; +0x28 = sin(+0x2C)·0xC0 >> 12` to both the band and the reach values. Ball absent.
- **`_opponent_attack`**: same, except `+0x290` has no reset on the move's own stance slot (PS1 `om.stance_slot == o.cur_slot`).
- **`_needs_guard`**: same.
- **`_guard_state`**: same; also stores the joint y (`+0x2A4`), unused. Yoshimitsu slot `0x470`.
- **`_throws`**: thrower side same, but the continue chance is the constant `0xB33`, not word 10. Being thrown: the forced list is gone (only word 9 draws), and `FUN_801c4108` picks among up to 16 rows that pass window, restriction, slot filter and condition (PS1: any of 48 rows unfiltered).
- **`_escape_press`**: absent. The row's command is pressed as is.
- **`_throw_follow_ups`**: same shape, up to 6, renamed slots, plus `0xB68` (`never` for bank 4 in attract). The slot filter is also inlined in every other row walk (see `collect_candidates`).
- **`_collect`**: same.
- **`_stance`**: adds a branch before word 49: draw against `+0x33C` (PS1 word 50), mark rows with byte `+8 == 0x1E`, then `+0xE4 = +0xE8 = 1`, `wait = -1`, execute.
- **`_crouch_and_actions`**:
  - Stall test: the same shape, but it also requires opponent bank 14, slot `0x904` and `DIST < 2000`, drops `opp_until < 0x1D`, and is skipped once `+0x2B8` reaches `0xB4`.
  - Gon test absent.
  - `+0x2B8` counts neutral frames; from `0xB4` the mask is `0x3F`, and with nothing marked the CPU presses up on `((+4 >> 1) & 7) == 0`.
  - Action 4 is always back (PS1's Doctor B exception absent).
  - With nothing marked, the pad is cleared (PS1 leaves it).
  - After a successful neutral attack `+0x2B0 = 0x32`.
- **`_action_mask`**: same masks and numbers.
- **`_side_step_or_special`**: bits `0x600000` are read from word `+8`, not state `+4`. In the word these are the hints special and never, so the arcade excludes such targets; PS1 tests the same bits of the state.
- **`_hold_guard`**: the whiff draw (`word 16 + opp_string·difficulty·30`, sets `punish`) is absent. Guard hold test same. Dead branch on `+0xA8`.
- **`_gather`, `_gather_ordered`**: inlined per list; restriction test per `restriction_ok` below, plus the slot filter.
- **`_new_move`**:
  - A list that comes out empty does not end the frame: the chain continues (PS1 `done = true` either way).
  - Candidates are collected every frame, also when a list is ready (PS1 only when not done).
  - After `0xDC` frames in a move all candidates are marked and one executed, as on PS1, here even over a list just built.
- **`_planned_follow_ups`**:
  - The "never" moves pass when `rand&0xFFF < word 11`; PS1 when `lcg & 0x7FFF > word 11`, so the sense is reversed and the range differs.
  - Arcade adds `state & 0x20000 == 0`, and for bank 0 air moves pass only when one draw per list is below `0xD`.
- **`_follow_through`**: same.
- **`_counter`**: the duck branch first tries `filter_defence` and executes; duck or back only if nothing marks or the pick fails. PS1 only ducks or steps back.
- **`_reach_ok`, `_can_counter`**: same.
- **`_reaction_kind`**: renumbered, arcade to PS1: 1, 2 same; 3 and 4 → 3; 5 → 4; 6 → 5; 7 → 6; 8 → 7; 9 → 8; 10 → 9. Forced-escape slots as in section 3. The history test compares the newest of 3 entries; PS1 compares slot 0 of an 8-entry ring (bug #23). `+0x278`, the 1-in-16 route to kind 1, is set when all 3 entries match, with no parameter reload behind it.
- **`_low_parry_or_escape`**: same (kind 10 here).
- **`_execute_marked`**, **`_react`**: same behaviour. Filters as below.
- **`_pad_back_on_even`**: forward when `(+4 & 1) != slot`.
- **`_evade`**: same, table the same seven values. Case 6 and an arcade-only case 8 (bank counter or crouch dash, reading `FUN_801c7350`) exist but nothing sets `+0xFC` to 6 or 8 (bug #22 present, `confirmed`; writers of `+0xFC` are only 0, 1, 2, 3, 4 and the table).
- **`_open_now`**: inlined.
- **`_expire_lists`**: **replaced by live code**, in this order. Each runs while its "on" counter allows (`≥ 1` for strings and planned, `≥ 0` for links), gathers the open rows with window, restriction, slot filter and condition, and needs `self+0x2C < 0x2000`. "Pressed" below means `FUN_801c3f30` then `FUN_801c79a8`, and ends the chain.
  - *Strings* `FUN_801c9dac` (up to 4 rows): draw ≥ `+0x308` (PS1 word 24): hold direction, stop. Else pick uniformly. A target without a window is pressed. With a window: `++on ≤ +0x306` (word 23) and `first ≤ opp_until`, then pressed. Otherwise clear the list, set `no_strings`, continue the chain.
  - *Planned* `FUN_801ca204` (up to 48): no open row or bad angle: clear, continue. Pick uniformly; target with the special hint: `++on`. Pressed when the target has no window, or `first ≤ opp_until`, `on ≤ +0x30A` (word 25), `attacks_in_row < limit` and `whiff_punish_ok` is false. When pressed and the target lacks state `0x80000`, a draw ≥ `+0x30C` (word 26) clears the list. If not pressed: clear, hold direction, stop.
  - *Links* `FUN_801ca6a8` (up to 10): draw ≥ `+0x310` (word 28): hold, stop. Pressed when no window, or `on < +0x30E` (word 27), `attacks_in_row < limit`, `first ≤ opp_until`, `whiff_punish_ok` false. Otherwise clear, continue.
- **`_duck_or_back`**: same.
- **`_avoid_air_attack`**: same, except the walk-in choice at reach below 3: back on `rand&1` (PS1 parity bit).
- **`_attack`**: same, without Tekken Force. `last_attack` same. `strings_on` is set only when not in attract, as on PS1.
- **`_last_resort`**: same; `& 0x80` flag on row `+0x18`.
- **`_choose`**:
  - Bank Gon test absent from the throw gate and `_approach_attack`.
  - `_vs_stance` entry adds `(opp_state & 2) == 0`.
  - The first filter is `FUN_801c6598` with the buffer predicate.
  - `DIRECT` has no twin: the rare neutral pick just returns a positive count.
  - Ball absent.
- **`_low_or_hint`**: no `first < 0x51`.
- **`_vs_grounded`**: turned away (`angle > 0x4000`), a 1-in-8 draw (PS1 1-in-16) marks targets with state `0x20000`; it returns only if something marked (PS1 always returns). Otherwise same thresholds.
- **`_hint_ground`**: same (`0x801C72C0`).
- **`_vs_stance`**: same.
- **`_approach_attack`**: same numbers. Setups as read; chances per the bank records. Filter order differs (attack filter first, then side steps), with the same marks and count.
- **`_move`, `_movement`**: same.
- **`_pick_movement`, `_by_distance`, `_by_closing`, `_do_movement`**: same numbers. Cases 7, 9, 10 exist in `FUN_801cb698` but `FUN_801cb2f0` never returns them.
- **`_finish`**:
  - The parameter reload is absent.
  - Tekken Force timers absent.
  - One draw against word 35 runs every frame, not only on a health drop.
  - Otherwise same timers and hit responses, plus `+0x2B0`.
- **`_raise_capped`**: same steps, inlined.
- **`learned`**: compares the newest of 3.
- **`_learn_from_damage`**: 3-entry shift register; no adaptive level 9; `+0x278` is set while all 3 entries match and is used by `_reaction_kind` only. `ai.multi` is not tested. **Arcade-only bug**: the shift loop makes 3 copies starting with `+0x270` → `+0x274`, and `+0x274` is the breath flag, just computed. After such a damage frame the flag holds a move pointer (non-zero once 3 entries are stored) until the next `_finish`, so the next frame's decisions see an opponent breathing fire (`confirmed` code; effect `inferred`).
- **`_ball_*`**: absent.

### `cpu_opponent.gd`

- **`lcg_next`**: `0x8021F8DC`, same `5x+3`. **`random_below`**: same.
- **`slot_move`**: `DAT_8021f8d4[slot]`; empty slots lead to a real sentinel row (index `0x1306`), so bug #61 has no garbage read (`inferred`).
- **`list_rows`**: no common blocks.
- **`restriction_ok`**: **differs, in the AI only.** The AI tests inline: 0 pass; `1..0x17` own bank == v−1; `0x18..0x2E` own bank **== v−0x18**; `0x2F` and up never. PS1's AI uses `!=` for the second range and has the opponent bank and char id ranges. The fight matcher `FUN_8018f914` does have `!=` and the other ranges, with the last boundary at `0x5C` (PS1 `0x5D`).
- **`cond_ok`, `situation_bit`**: no cache; `FUN_8018fb3c` live.
- **`collect_candidates`, `_walk_lookahead`, `_cond_ok_lookahead`, `_open_lookahead`**:
  - Every row also passes the **slot filter** of `_throw_follow_ups` (with `rand()&0x70`).
  - Targets with state bit 23 are not added at all (PS1 adds them and marks them −1 afterwards, so counts differ).
  - The real form of bug #17: with `rand&7 != 0` or attract, the first candidate equal to `+0x90` is dropped, across both walks.
  - The look-ahead needs `first < 2` and a normal window test, and evaluates the row's own condition (no bug #18; PS1 skips `0x26`, `0x27`, `0x30` there).
  - `+0x94` holds the continuation, unused.
- **`mark_candidates`**: same.
- **`reach_ok`, `is_attack`, `grounded_or_special`, `_attack_in_reach`, `damage_of`**: same with the mapped fields.
- **`filter_*`**: same, except:
  - `filter_fast_attacks` startup below 12.
  - The damage filters also exclude bit 23.
  - Guard predicates always exclude state bit `0x100`.
  - Reaction 1's extra is crouching attacks in reach, as on PS1.
- **`filter_defence`**: same, bug #21 present.
- **`filter_no_lows`**: same.
- **`hint_never_open`**: same plus slot filter.
- **`pad_from_step`, `start_script`, `input_sequence`, `press_command`**: same with arcade pads; first motion code `0xC00C`.
- **`reset_approach`, `side_step`**: same.
- **`after_attack`**: same, no Tekken Force.
- **`execute_candidate`, `marked_pick`**: uniform both ways, no bug #19.
- **`branch_open_to`, `_walk_to`**: terminator row read directly, no common rows; no bug #20.
- **`call_hook`, `_run_hook`**: same; the draw comes after the null test (PS1 before).
- **Hooks**: same logic in Paul, Yoshimitsu, Ogre, King, Hwoarang after the slot map. Paths read in full. Differences:
  - King's Gon test absent.
  - The Ogre `0x904` branch and the Hwoarang hook are **live**.
  - Gon hook absent.
  - The hook table covers banks 0–21, with idle A-hooks where PS1 has none, so those banks consume a `rand` draw that PS1 does not.
- **`load_params`**: section 2. `reload` and Tekken Force absent.
- **`reset`**:
  - Wait: `+0x98 = word5·roll(128)/256 + 0x3C` (PS1 word 3 alone, the same word).
  - `+0x5C = roll(48) + 0x32` (PS1 `roll(30) + 30`).
  - Attract halves the same four words and quarters the guard word. `+0x28`, `+0x2C`, `+0x2B4`, `+0x2B8` start at 0, `+0x2B0` at −1.
- **`init_round`**: 2 records, target `1 − slot`. Both fighters always get records, whoever plays them.

### PS1 bugs in the arcade

| PS1 bug | Arcade |
|---|---|
| #10 lists dropped | Absent, live code. |
| #11 dead slots | Absent, slots defined. |
| #17 stale word | The same code in working form. |
| #18 look-ahead row | Absent. |
| #19 forward walk | Absent. |
| #20 continuation row | Absent. |
| #21 guard count | Present. |
| #22 state 6 unset | Present. |
| #23 history slot 0 | Absent (newest entry compared). |
| #24 ball | No Ball. |
| #61 empty slot | Sentinel row (`inferred`). |

## 5. What the arcade lacks or adds

**Lacks** (`confirmed`, no such reads):

- Gon hook and all Gon tests; `opp_gon_special`.
- Doctor B's action exception.
- Tekken Force: words, timers, the mode's branches; the third record.
- Ball: `_ball_*` and every Ball test.
- Input modes `+0x21E`.
- Common parameters and adaptive reload at level 9 (`+0x1FE`).
- `_escape_press` and the forced escape list while being thrown.
- Whiff term in `_hold_guard`.

**Adds**:

- Live follow-up lists and `whiff_punish_ok`.
- Distance wobble (`+0x28`, `+0x2C`).
- Neutral frame counter `+0x2B8` with the mask `0x3F` and press-up after 180 frames.
- Stance branch with word 50.
- Slot filter on all row walks.
- `0xB68` filter.
- Region group in the parameters.
- Bank 0 restriction on air moves in the planned list.
- Stall test against Ogre `0x904`.
- `+0x2B0`, `+0x2B4` counters.
- Debug step id `0x8021F394` and debug names in the records.

## Open

- `+0x94`, `+0x2A4`, `+0x2B4`, `+0x264`/`+0x280`: written or read without a decision depending on them, as far as read. Treated as dead (`inferred`).
- Bank type range: rows 17–21 of the AI tables are believed unreachable, based on the index table only. Whether anything sets a fighter's `+0x18` above 16 is for the flow and move reports.
- Which game modes are cases 3 and 4 of the mode set-up, forcing difficulty 1 (lines 31025, 31039).
- Exact replay is not verified: nothing was run in a harness and there are no arcade golden traces. `rand` is shared with about 215 other call sites in the program, so a frame-exact CPU depends on the whole program's call order.
- PS1 words 23–28 and word 50: their roles come from reading the live code; nothing has been measured in play.
- The effect of the `+0x274` overwrite (section 4, `_learn_from_damage`) on play is not measured.
- Bit `row+0x18 & 0x80` as PS1's power flag is `inferred`.
- `0x8017A352` and `0x8017A32A` have no reachable reader; contents not interpreted.
- Arcade slot `0x494` against PS1 `0x472`: the hook returns −1 either way, so the slot map's different pairing has no effect here, but the two mappings are not reconciled.
