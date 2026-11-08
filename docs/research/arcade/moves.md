# Arcade ↔ PS1: the move system

Arcade = MAME `tekken3`, World ver. E1, program `work/arcade/prg_world_e1.unpacked.bin` (base 0x80010000), decompile `work/arcade/decomp_full/arcade_e1_full.exe.c`. PS1 = Japan Rev.1, `work/decomp/SLPS_013.00.c`.

Scripts (local scratch in `work/arcade/fight/`, not in the repository; run from that directory, plain `python3`): `mv.py` loaders; `fn.py {ps|ar} <addr|name>` print a function (run from the repo root); `slotmap.py`, `slotchain.py`, `slotfinal.py`, `slotgreedy.py` the slot map; `rowcmp.py`, `rowdiffs.py` row fields; `branchcmp.py`, `branchalign.py` branch lists; `reactcmp.py` reactions; `seqcmp.py` sequences and small tables; `misc.py` other checks; `report_check.py` re-measures this report's counts. Result: `slotmap_final.json` (numbers only).

Evidence words: **confirmed** = read on both sides (decompile, disassembly where stated) or measured on data; **inferred** = not read through on both sides.

**Summary.** The arcade's move system is the PS1's with the data flattened: same 12-byte branch rows, same state and attack words, same transition codes and conditions. All 17 bank types share one row table and one branch table, each type has a full slot table, and common rows are inlined. Slot numbers differ by a single global map. The behavioural differences are few and listed in section 6.

**How the remake uses this.** It does not translate arcade data into PS1 numbering: 418 arcade slots have no PS1 slot, and the row and reaction tables are global. it keeps the arcade's slot, reaction and close numbers (`tools/remake_import/arcade_tables.py`), and the numbers `core` hard-codes (section 3) are the constants of the `core/arcade/` classes. The map in section 3 is for checking, not for conversion.

## 1. Function map

All rows are **confirmed** by side-by-side reading unless the last column says otherwise.

| PS1 name @ addr | Arcade | Notes |
|---|---|---|
| `DivmotLinkBank` 8002d068 | `FUN_8018eab4` | Once only (guard `DAT_8021f05c`); 0x1307 rows; 17 × 0xEDE slots. Reads the anim table from file address 0x22DAD08. |
| `DivmotMergeSharedSlots` 8002d2d0 | none | `FUN_8018ec9c` only sets `DAT_8021f61c/620` = 0x8006D430 + type·0xEDE·4. |
| `MoveLookup` 8002d3cc | `FUN_8018ed1c` | Same. |
| `MoveTotalDamage` 8002d51c | `FUN_8018ee74` | Same. |
| `MoveInSlotList` 8002d4b8 | `FUN_8018ede8` | Lists hold row numbers (end −1), compared with the row's relocated anim word. PS1: anim tags, end < 1. |
| `FighterStartStance` 8002d570 | `FUN_8018eec8` | Masks differ (6). |
| `FighterStartWinPose` 8002d6b0 | `FUN_8018f070` | Masks and slots differ (6). |
| `FighterCollapse` 8002da80 | `FUN_8018f3a0` | (6) |
| `ThrowVictimStart` 8002d9b0 | `FUN_8018f318` | Slot from the reaction record. |
| `MoveBranchStep` 8002dc3c | `FUN_8018f528` | Also holds `MoveStep`'s reaction selection. |
| `MoveReactionBranch` 8002db08 | `FUN_8018f424` | (6) |
| `MoveBranchAll` 8004539c | `FUN_8018c2dc` | Order toggle `DAT_8021fda4` = PS1 `DAT_800aff14`; no mode 8 case. |
| `MoveStepAll` 80045450 + `MoveStep` 800454e0 | `FUN_8018c340` | One routine. |
| `MoveStartAll` 80045834 | `FUN_8018c498` | Same, no mode 8 case. |
| `BranchFind` 8002e078 | `FUN_8018f9a4` | Restriction split out to `FUN_8018f914`. |
| `BranchCondition` 8002e310 | `FUN_8018fb3c` | (6) |
| `BranchFindReversal` 8002e95c | `FUN_80190240` | |
| `ReversalCondition` 8002eb24 | `FUN_80190334` | |
| `AttackUsesJoint` 8002eda0 | `FUN_801905b0` | Mapped, contents not compared line by line. |
| `InputMatch` 8002ce7c | `FUN_8018e8d8` + `FUN_8018e54c` | 4th argument of `FUN_8018e54c` = newest history entry (disassembly 0x8018e910). |
| `InputForwardDoubleTap` / `InputBackDoubleTap` 8002cb08 / 8002cbf0 | `FUN_8018e6b8` / `FUN_8018e6dc` → `FUN_8018e5d4(f, dir, 0x14)` | Same logic, one routine. |
| `InputSequenceMatch` 8002ccd8 | `FUN_8018e768` + `FUN_8018e700` | Same logic. |
| sequence dispatch (pointer tables) | switches `FUN_8018ce90`, `FUN_8018d900` | Getters `FUN_8018d4cc`, `FUN_8018dd2c`, `FUN_8018ea28`. |
| `InputUpdate` 8002c7d4 | `FUN_8018e220` | (6) |
| `InputClear` 8002c2a4 | `FUN_8018e000` | Not compared line by line. |
| `InputSource` 8002bf3c | `FUN_8018b61c` / `FUN_8018e0dc` | CPU input `FUN_801c3614`. Extra per-frame call `FUN_801bcaac` (not read). |
| `FUN_8002c33c/c360/c384` | `FUN_8018e070/094/0b8` | Input mode setters; **inferred** from shape. |
| `LatchButtonTaps` 80040d68 | `FUN_8018b710` | (6) |
| `MoveStartOrAdvance` 8002f600 | `FUN_80190ff8` | (6) |
| `TransitionRemap` 800311bc | `FUN_80192a3c` | Same. |
| `BranchEntersBeforeActiveEnd` 8003127c | `FUN_80192afc` | Same. |
| `MoveKeepsFrame` 800312c4 | `FUN_80192b44` | Same. |
| `SituationReset` / `SituationClassify` 80031398 / 800313b0 | `FUN_80192be8` / `FUN_80192c04` | Same; the opponent's quadrant is read from its own +0x2E. |
| `PushRepeatCount` 8003159c | `FUN_80192df8` | Same. |
| `HitSelectReaction` 8002edf8 | `FUN_80190600` | Same selection; record offsets differ (5). |
| `AirReactionKind` 8002f0e8 | `FUN_80190a7c` | (6) |
| `LaunchTrajectory` 8002f2c8 | `FUN_80190c78` | (6) |
| inlined recover code in `MoveStartOrAdvance` | `FUN_80190900`, `FUN_80190978` | |
| inline in `FighterMovePhysics` | `FUN_80192978` | Air velocity from `targetDir`; called at the end of `FUN_8018c340`. |
| `FUN_8002d458` / `FUN_8002d460` | `FUN_8018ed98` / `FUN_8018eda0` | Stance constants: return 3 / 0x19 (PS1 3 / 40). |
| `FUN_8002d844` (slot 0xD6C start) | `FUN_8018f220` | Slot 0xE62, transition 6. Called at lines 14703, 14711. |
| `FUN_8002d8c0` (slot 0xD65 start) | `FUN_8018f29c` | Slot 0xE5B, transition 6. Called at lines 14700, 14708. |
| `FighterMovePhysics` 8003f330 | `FUN_8019f3fc` | Both fighters in one call. |
| `ClampSymmetric` / `TrackBudget` 80040b58 / 80040b9c | `FUN_801a09cc` / `FUN_801a0a04` | Same. |
| `FUN_80040c04` | `FUN_801a0b58` | |
| `FighterRelativeAngles` 80043d2c | `FUN_801a0a6c` + `FUN_8018b050` | (6) |
| `PairwiseDistances` 8004391c | `FUN_8018b124` | (6) |
| `MoveEvents` 80045b60 | `FUN_8018c5a4` | Both fighters. (6) |
| `BodySphereProfile` 8003eefc | `FUN_8019ef90` + `FUN_8019f00c` | (6) |
| `FighterTransitionBlend` 8003c4c4 | `FUN_8019cd04` | Helpers inlined. (6) |
| `BlendBranchLength` 8003ccf0 | inline in `FUN_8019cd04` | `FUN_80192ba0` is the destination frame (PS1 `BlendDstFrame`). |
| `HandFaceCommand` | `FUN_80194080` | |
| `FUN_80034354` (blinking) | `FUN_80193f90` | **Inferred** from the same tests: flag bit 31 (line 8318), state & 4, row +0x17. Rest not compared. |
| `FightFrame` 8002b0ac | `FUN_8018a988` | Move-system order is the same (6). |
| `HitTest`, `HitApply`, `AttackVelocity`, `FighterVelocity` | `FUN_8018b91c`, `FUN_8018bb68`, `FUN_8018b47c`, `FUN_8018b430` | Read only for their row and field uses ([combat.md](combat.md)). |
| `SinQ15`, `CosQ15`, `Atan2Angle`, `ISqrt` | `FUN_8018a16c`, `FUN_8018a1b4`, `FUN_8018a1fc`, `FUN_8018a314` | |

Other arcade helpers: `FUN_8018ed00` (a player's slot table), `FUN_8018ed4c` (win pose row, slot 0xE5D; used at line 50555), `FUN_8018ed78` (clamps the type to ≤ 0x10), `FUN_801a2dd4` (side flag), `FUN_801a2df4` (camera track point, reads row +0x16).

## 2. Row field map

The arcade row is 0x3C bytes at `0x80025E8C + 0x3C·i`, 0x1307 rows, static in the program image. The PS1 row is 56 bytes.

**Data check** (`rowcmp.py`): 13,390 (type, arcade slot, PS1 slot) triples from the 3,354 slot pairs of section 3; 4,430 distinct arcade rows.

**Caveat.** The slot map used frames, state, attack, damage, active window, air window, hold, end turn and step as evidence, so those percentages are biased upward. These fields were not used and are independent evidence: hints, flags, joints, freeze, events, sounds, body, reaction, close.

| Arcade | PS1 | Rule | Match | Proving reads |
|---|---|---|---|---|
| +0x00 u32 anim index | +0x00 stream offset | Index into the anim table (0x22DAD08, 8 bytes each); anim index = row index, 1:1 | n/a | `FUN_8018eab4` |
| +0x04 u32 state | +0x04 | Identical word | 99.96% | `FUN_80190ff8`, `FUN_8018fb3c` |
| +0x08 u16 attack | +0x08 | Identical | 100% | `FUN_80190ff8` |
| +0x0A u16 AI hints | +0x0A u8 | Low byte; high byte always 0 (max 0xBC). PS1 +0x0B always 0 | 99.99% | data |
| +0x0C u32 branches | +0x0C | `0x800ACA38 + 12·i` | see below | `FUN_8018eab4` |
| +0x10 u16 stance slot | +0x10 | Arcade slot number; through the slot map | 97.91% (raw 50.41%) | `FUN_8018c340`, `FUN_8019cd04` |
| +0x12 u16 damage/class | +0x14 | Identical. At link, rows with events add their hi-0x0B event values (`FUN_8018ee74`; PS1 `MoveTotalDamage`, line 4837). The percentage compares static values | 99.99% | `FUN_8018eab4`, `FUN_8018ee74` |
| +0x14 u8 camera id | flags bits 0–7 | **Renumbered**: 399 non-zero triples, 0 equal (for example 3→9, 0x14→0x28, 0x11→0x25). 174 distinct values, max 191, global; PS1 ids ≥ 0x2B are bank-local. 159 of 168 arcade values map to one PS1 value. Use the arcade's camera tables, no rule | 0 / 399 non-zero | Camera range 801ceb78–801d49a0; not read here |
| +0x15 u8 (0/1) | flag 0x10000000 | `== 1` | 100% | `FUN_80190ff8` |
| +0x16 u8 (0/1) | flag 0x20000000 | `== 1` | 99.96% | `FUN_801a2df4`, 801d0f9c |
| +0x17 u8 (0/1) | flag 0x40000000 | `== 1` | 99.86% | `FUN_80199310`, `FUN_80193f90` |
| +0x18 u32 flags | flags bits 8–18 | Table below | 99.9–100% | |
| +0x1C s16 end turn | +0x12 | Identical | 99.30% | `FUN_8018f528`, `FUN_80190ff8` |
| +0x1E u8 frames | +0x18 | 0 in the image; from the stream's first byte at link, as PS1 | 95.21% | `FUN_8018eab4` |
| +0x1F, +0x20 air window | +0x19, +0x1A | Identical | 99.96%, 99.98% | `FUN_8018fb3c` case 0x37, `FUN_8019f3fc`, `FUN_8018b91c` |
| +0x21 hold | +0x1B | Identical | 99.94% | `FUN_80190ff8`, `FUN_80190c78`, `FUN_80190978` |
| +0x22 s16 step | +0x16 | Identical | 99.95% | `FUN_8019f3fc` |
| +0x24 u32 sounds | +0x1C | Index, −1 none, `0x800222BC + 2i` | Lists 99.14% (differences: see below) | `FUN_8018eab4` |
| +0x28 u32 events | +0x20 | Index, −1 none, `0x8001E8BC + 4i` | Lists 99.63% | `FUN_8018eab4`, `FUN_8018c5a4` |
| +0x2C u16 reaction | +0x32 | Arcade record index; no `0x1xxx` split. Map in section 5 | Raw 65.93%; the monotone map fits all but 10 votes | `FUN_8018bb68`, `FUN_8018f318` |
| +0x2E u16 close reaction | +0x34 | Index, 0 none. One-to-one: a = p + 0…3 up to p 0x2F, then p 0x39 → a 0x33 | Zero/non-zero agree in all 13,390; raw 97.76% | `FUN_8018bb68` |
| +0x30, +0x31 active window | +0x2D, +0x2E | Identical | 99.99% | `FUN_80190ff8`, `FUN_8018b91c`, `FUN_8019f00c` |
| +0x32..+0x35 joints a0, b0, a1, b1 | First 4 bytes of descriptor +0x28 | Embedded. No baked points in the arcade: segments come from live joint matrices (`FUN_80198a48`, `FUN_80198bf8`). +0x34 ≠ 0 → 2 segments, +0x32 ≠ 0 → 1 | 99.85% | same |
| +0x36 u8 hit freeze | +0x2C | Identical | 99.99% | `FUN_8018b91c` |
| +0x38 u16 body profile | +0x30 | Identical bit layout: low nibble case, bits 4–11 sphere mask, bit 12 window | 99.98% (2 triples differ) | `FUN_8019ef90`, `FUN_8019f00c` |
| +0x37, +0x3A | PS1 +0x2F, +0x36 | Always 0 on both sides | | data |

**Flags** (`rows` = triples with the arcade bit set; `of PS1` = triples with the PS1 bit set):

| Arcade +0x18 | PS1 +0x24 | Agree / rows / of PS1 | Reader |
|---|---|---|---|
| bit 0 | 0x100 | 5,445 / 5,452 / 5,447 | `FUN_8019cd04` `&1` |
| bit 1 | 0x200 | Bit never set in the arcade; none matched in PS1 | `FUN_8019cd04` `&2` |
| bit 2 | 0x400 | Bit never set in the arcade; none matched in PS1 | `FUN_8019f3fc` |
| bit 3 | 0x800 | 737 / 737 / 739 | `FUN_80190ff8` line 6681 (attackAlert = 9) |
| bit 4 | 0x1000 | 1,597 / 1,597 / 1,597 | `FUN_80190900`, `FUN_80190ff8` (launch angle) |
| bit 5 | 0x2000 | 286 / 286 / 286 | `FUN_80190ff8` line 6643, `FUN_801c9854` (command buffer) |
| bit 6 | 0x4000 | 36 / 36 / 36 | `FUN_8019f3fc` (guard stance), `FUN_80190ff8` (+0x9E rule) |
| bit 7 | 0x10000 | 18 / 18 / 18 | `FUN_80190ff8` line 6678 (powerTimer = 0x78) |
| bit 8 | 0x20000 | 17 / 17 / 17 (one row in all types) | `FUN_8019f00c` line 15033 |
| bit 31 | 0x40000 | 2,871 / 2,872 / 2,871 | `FUN_80193f90` line 8318 (eyes closed, PS1 `_blink`). The PS1's `reactChain` count is gone |
| none | 0x80000 | PS1 only, 29 triples | Partner tests removed (6) |
| none | 0x80000000 | PS1 only, 637 triples | No reader on either side |

Rule back to the PS1 word: `(f & 0x7F) << 8 | (f & 0x180) << 9 | (f >> 31) << 18 | (+15==1) << 28 | (+16==1) << 29 | (+17==1) << 30`, plus the camera id in bits 0–7. Bits seen in arcade flags: mask 0x800001F9.

**Branch rows.** Same 12-byte layout: +0 cmd, +2 restriction, +3 condition, +4 arg, +6 target, +8 flags, +9 first, +0xA last, +0xB entry (`FUN_8018f9a4`, `FUN_8018f528`).

The arcade table holds 60,832 rows and ends exactly at 0x8015EDB8. It has 4,871 terminators, one list per row, none shared. A list holds the rows of every type that shares the row, separated by restriction bytes.

After inlining the PS1's CALL rows and removing rows the type cannot take (`branchalign.py`), 142,587 rows align:

| Field | Differing rows |
|---|---|
| cmd | 35 |
| cond | 12 |
| transition | 251 |
| first | 415 |
| last | 544 |
| entry | 410 |
| target through the slot map | 142 of 141,880 (99.90% agree) |

- 90.89% of the lists are identical apart from the target number.
- Unaligned: 1,193 arcade-only and 1,428 PS1-only rows out of about 142,000.
- Restriction difference: 0x6A ↔ 0x6B (4,504 rows). This is the rule shift in section 6.

**Real data differences** (not mapping noise; arcade values come through conversion anyway):

- 116 slot pairs have different lengths in at least one type, for example a 0x95 ↔ p 0xA2 is 55 vs 30 frames, and a 0x99F ↔ p 0x91F is 30 vs 42.
- PS1-only cancel rows `0x207/0x20B/0x20D/0x20E → slot 6`, window 1–2.
- Sound commands often differ by +0x1F on the PS1 (0x816E vs 0x818D, 0x817D vs 0x819C). The [audio-and-effects.md](audio-and-effects.md) owns this.
- Events differ on 38 row pairs, mostly hi 14/21 (hand and face), 11 (throw damage), 6 (effect).

## 3. Slot numbering

**One global map, the same for all 17 types, monotone except for one reshuffled block.**

- 3,354 pairs in 219 constant-shift runs. The shift drifts from 0 at slot 0 to −246 at 0xE5B and −253 at the end.
- Longest increasing subsequence: 3,301 pairs, so 53 lie outside it.
- 40 of the 53 are the real non-monotone block, hit reactions, a 0x924–0x986 ↔ p 0x8B5–0x8F7 (for example 0x937→0x8C8 but 0x93C→0x8C4), proven by reaction records. The other 13 (a 0x412–0x413, 0x485, 0x73F, 0xAB8, 0xC20, 0xC36–0xC3C, 0xC80, 0xD4D–0xD4E) are unproven; those I looked at rest on one or two votes.
- Validation: branch targets agree with the map in 99.90% of rows; reaction record slots 486/496 records; throw victim slots 367/370.

**Deriving it** (`slotmap.py` → `slotchain.py` → `branchalign.py` / `reactcmp.py` → `slotgreedy.py`):

1. Vote (a, p) when the rows in slot a and slot p of the same type have equal frames, state, attack, damage, windows, hold, end turn and step.
2. Take the max-weight monotone chain; a per-slot maximum alone fails because identical rows tie.
3. Add votes from aligned branch targets (×3) and reaction record slots (×40), then assign one-to-one by descending evidence. Iterate twice; it is stable.

**Constants** (**confirmed**: code on both sides, plus data):

| Meaning | PS1 | Arcade | Evidence |
|---|---|---|---|
| Round stances | 0, 1, 2 | 0, 1, 2 | `FUN_8018eec8` |
| Standing | 3 | 3 | `FUN_8018ed98` |
| Crouching | 40 (0x28) | 0x19 | `FUN_8018eda0` |
| Air kinds' slots | 0xD56, 0xD61, 0xD62, 0xD63, 0xD64, 0xD57 | 0xE45, 0xE50, 0xE53, 0xE55, 0xE58, 0xE46 | Tables (section 5) |
| Air reaction exceptions | 0xD62, 0xD63, 0xD64, 0xD58 | 0xE53/0xE54, 0xE55–0xE5A, 0xE46 | `FUN_80190a7c` |
| Slot start, transition 6 | 0xD65, 0xD6C | 0xE5B, 0xE62 | `FUN_8018f29c`, `FUN_8018f220` |
| Collapse | 0xD66 | 0xE5C | `FUN_8018f3a0` |
| Win poses | 0xD67–0xD6A | 0xE5D–0xE60 | `FUN_8018f070` |
| Costume 0x24 win pose | none | 0xE61 | `FUN_8018f070` |
| Fallback | 0xDC5 | 0xEBB, an empty slot | Map; see below |
| Slots total | 0xFB7 | 0xEDE × 17 types | Link routines |
| PS1 attacker specials | 0x241 (bank 9), 0x14A (bank 0x10), 0x848–0x849 | a 0x233, a 0x133; removed from code | (6) |

**Empty slots.** Arcade: every empty slot points at row **0x1306** (33,899 of 64,702 entries): 60-frame idle stream, state 0x842, stance 3, list = one row into slot 3 plus terminator. There is no merge. Throw victim moves, which the PS1 defines only in the thrower's bank and merges at load, are filled in every type: type 0 has 1,018 filled slots with no filled PS1 partner, and 1,007 of them hold a row used by all 17 types. 1,328 rows are used by all 17 types; row 0x1140 fills 64 slots in each type. Coverage check: among the map's pairs, no slot is empty in the arcade while filled in the PS1 (all 17 types).

PS1 slot 0xDC5 is empty in all banks (type 0–16 checked), so its "fallback" is itself the out-of-range pointer of an empty entry. The arcade's row 0x1306 is a real, safe row. For the remake `FightSimulation._link_banks` (`FALLBACK_SLOT`) is not needed for arcade data.

**Slots on one side only:**

- Arcade only: 418 non-empty slots (3,771 filled, 3,353 mapped), 239 of them filled in every type. Among those: 0x23, 0xD9–0xDC, 0x172–0x173, 0x176–0x177, parts of 0x945–0x987, parts of 0xD42–0xD57, 0xE46, the extra air moves in 0xE51–0xE5A, **0xE64–0xEB9**.
- 0xE64–0xEB9: 86 rows of long streams (125–255 frames) in all 17 types, one branch target (0xE7A), no reaction reference, while p 0xD6E–0xDC4 are empty at the same shift. Their use is open. 0xEBA is empty in all types.
- PS1 only: 38 slots (3,391 filled, 3,353 mapped), among them 0x160, 0x180, 0x195, 0x197, 0x1AC, 0x1AE, 0xA11–0xA12, 0xDE6–0xDEF, 0xF5F–0xF66.
- Some of these are stance variants, about 200 of the 13,390 triples: where a PS1 row's stance is 0xDEB–0xDEE the arcade has 0x19; 0xDE6–0xDEA, 0x160, 0x180, 0x195, 0x1AC → 3; 0x197, 0x1AE → 0x8C. **Inferred:** on those rows an arcade KO can take the collapse branch where the PS1's does not, since that test compares the stance with stand and crouch.

Types are numbered as PS1 banks 0–16 (per-type agreement above).

## 4. Fighter record field map

**Confirmed** from reads on both sides (mostly `FUN_80190ff8`, `FUN_8018f528`, `FUN_8019f3fc`, `FUN_8018e220`). Names are `fighter_fields.tsv` / remake names; "same" = same offset.

| PS1 +off (name) | Arcade +off | PS1 +off (name) | Arcade +off |
|---|---|---|---|
| facing | +02 | gotHit +CE | +A3 |
| posX/Y/Z | +08/+0C/+10 | guarded | +A4 |
| playerIndex | +14 | hitClean | +A5 |
| bankType +16 | +18 | contact | +A6 |
| charId +18 | +1A | whiffed | +A7 |
| costumeSlot | +1E | moveChanged +DA | +A8 |
| rootDx | +20 | inAir +DB | +A9 |
| targetDir +2A | +26 | landedA/B | +AA/+AB |
| heading | +28 | health-zero flag | +AC |
| headingDelta +2E | +2A | aboutToHit | +AD |
| relAngle +30 | +2C | counterHit | +AE |
| facingQuadrant +32 | +2E | close-reaction flag | +AF |
| oppQuadrant +40 | opponent's +2E | tapLP/RP/Both +E0..E2 | +B0/+B1/+B2 |
| aimDir +34 | +30 | activeSegs | +B3 |
| trackAccum | +32 | extraKind +E4 | +B4 |
| rootMove | +3C | lastDamage +E8 | +B6 |
| rootFrame | +40 | damageOverride | +B8 |
| poseMove +54 | +44 | extraValue +EC | +BA |
| poseFrame +58 | +48 | hitFreezeIn | +BC |
| prevPoseFrame +5A | +4A | hitCooldown | +BE |
| moveFrame | +4C | pushFrames +106 | +C0 |
| damage | +4E | pushSpeed | +C2 |
| state +60 | +50 | pushTableFrames | +C4 |
| attack +64 | +54 | pushDir | +C6 |
| guard | +56 | pushTable | +C8 |
| attackHi | +58 | turnFrames | +CC |
| stateClass +69 | +59 | turnStep | +CE |
| holdFrames | +5A | recoverMash | +D0 |
| branchWindow | +5C | recoverFrames | +D2 |
| frameStep | +5E | attackAlert | +D4 |
| throwState +74 | +64 | powerTimer | +DA |
| hitFreeze | +66 | pushRepeat +124 | +DC |
| slideStepX/Z | +68/+6C | pushRepeatTimer +126 | +DE |
| slideState | +70 | last push transition +13A | +E0 |
| hitDone0 (PS1 has three) | +71 (single) | entryFrame +198 | +E2 |
| hitDone3 | +72 | transition +19A | +E4 |
| wasHitThisMove +87 | +73 | transBit7 +19C | +E6 (masked 0x80) |
| contactThisMove | +74 | transBit6 +19E | +E8 (masked 0x40) |
| guardedPrev | +75 | moveSlot +1A0 | +EA |
| inReaction | +76 | moveRow +1A4 | +EC |
| branchKind +8B | +77 | reaction pointer | +F0 |
| condFlagUsed +8C | +78 | hit velocities +3C8/+3E0 | +310/+328 |
| launchArmed | +7A | separation vector | +330/+334/+338 |
| airKind +90 | +7C | health | +33C |
| ballistic | +7E | maxHealth | +340 |
| juggleCount +94 | +80 | input source | +34A (1 pad 1, 2 pad 2, −1 none, > 2 CPU) |
| groundOffset +96 | +82 | inHistIndex +40C | +34C |
| airSpeed +98 | +84 | inHeld / inDir +406 / +402 | +350 (`held<<4\|dir`, one byte) |
| airVelX/Y/Z (Y +9C) | +86/+88/+8A | cmdCount +410 | +354 |
| curSlot +A0 | +8C | cmdRead +414 | +358 |
| curTransition | +8E | cmdMerge +418 | +35C |
| oppStartX/Z | +90/+94 | inHistory +41C | +360 |
| attackSegCount | +98 | cmdBuffer ~+458 | +39C |
| crouchMove | +99 | inPressedHist +462 | +3A6 |
| stepKind | +9A | pressCount +4DC..+4E8 | +420..+42C |
| attackClass | +9B | rootX/Y/Z (rootY +F6C) | +44C/+450/+454 |
| airPhase | +9C | joint blocks +8F4+0x44·j | +75C+0x50·j |
| trackMode | +9D | airFree +128A | +1158 |
| moveFlagBA +BA | +9E | ogre freeze +12D0 | +11B0 |
| hand event flag +BC | +A0 | blendMode +181C | +1830 |
| attackPending | +A1 | lastPoseMove +1824 | +1838 |
| anchorDirty | +A2 | blendCounter / blendFrames +1878 / +1870 | +1AD0 / +1AC8 |
| | | blendActive | +B5 |

Globals: stepCooldown → `DAT_8021f060[player]`; applyEndTurn → `DAT_8021f068[player]`; situation → `DAT_8021f070[player]`; air duration (PS1 0x80095B94) → `DAT_8021f078[player]`; step accumulators (PS1 0x8009E9A8/B8) → `UNK_8021f6b0/b8`; dist / distAdj (PS1 per fighter) → global `DAT_8021fd90` / `DAT_8021fdc0`; active mask → `DAT_8021fb00`; order toggle (PS1 `DAT_800aff14`) → `DAT_8021fda4`; new-input frame (PS1 0x80095884/88) → `DAT_8021fd88` / `DAT_8021fbec`; tap previous (PS1 0x8009746C) → `DAT_8021f050`; g_cameraPhase → `DAT_8021fcd0`; side flag → `DAT_8021f6c0`; pad words → `DAT_8021fbf4/f8`.

Absent in the arcade: `reactChain`, prev slot and stance (PS1 +134..138), `inThrow`, `fixedFacing`, `moveFlagBB` (**confirmed** in the routines read). `throwPartner`, `oppHeading`, `oppToSelfDir` (**inferred** from the record layout: no such fields between the neighbours above).

## 5. Table addresses

| Table (`tables.py`) | PS1 | Arcade | Count (arcade) | Arcade read |
|---|---|---|---|---|
| Rows | banks | 0x80025E8C | 0x1307 × 0x3C | `FUN_8018eab4` |
| Slots | banks | 0x8006D430 | 17 × 0xEDE × u32 | `FUN_8018ec9c`, `FUN_8018ed1c` |
| Branch rows | banks | 0x800ACA38 | 60,832 × 12 | `FUN_8018eab4` (line 5028) |
| Events | banks | 0x8001E8BC | Lists of (u16 frame, u16 cmd) | `FUN_8018c5a4` |
| Sounds | banks | 0x800222BC | u16 lists ending 0xFFFF | `FUN_801a104c` |
| Anim table | section offsets | file address 0x22DAD08 | 0x9838 bytes, 8 per anim | `FUN_8018eab4` |
| COMMON_BRANCHES | 0x80017C78 (672) | **None**: inlined. Numbers C00C/C00D are sequences | | |
| SEQUENCES_A | 0x800958F4 (63, C00E–C04C) | Switch data 0x800102A8–0x800106A4 (63, **C00C–C04A**) | Contents identical, n ↔ n+2 | `FUN_8018ce90`, `FUN_8018d4cc` |
| SEQUENCES_B | 0x800959F0 (41, C7FF–C827) | Switch data 0x800106B0–0x8001094C (41, same numbers) | Contents identical | `FUN_8018d900`, `FUN_8018dd2c` |
| Double taps | none | 0x80010290, 0x8001029C | Getter only; matching is `FUN_8018e5d4` | `FUN_8018ea28` |
| BUILTIN_ATTACKS / BLOB | 0x80017C10 / 0x80017BDC | **None**: joints in the row | | |
| AIR_KINDS | 0x8001A630 (6) | 0x8015F704 (13: kinds 0–0xC) | PS1 kind 0, 1, 2, 3, 4, 5 = arcade 0, 1, 4, 6, 9, 0xC, equal offsets (440, 550, 204, 436, 436, 1357). New: 2, 3, 5, 7, 8, 0xA, 0xB | `FUN_80190a7c`, line 7234 |
| PUSH_TABLES | 0x8001075C | 20-byte entries, 0x80010D00–0x800111EC (59 used) | Reached by pointers in records | `FUN_80190ff8` |
| LAUNCH_PUSH | 0x80019D2C | 0x8015EDB8 | 8 s16, identical | Line 6456 |
| REACTIONS | 0x80010CE8 (633 × 42) | 0x80011200 (**978 × 0x38**, hit and throw entries together) | Max index 0x3D1 | `FUN_80190600`, `FUN_8018bb68` |
| FORCED_REACTION | 0x8001DEC0 | Not located (open) | | |
| THROW_VICTIM_SLOTS | 0x800174C4 (397) | **None**: first slot of the record, 0x8001121C + r·0x38 | | `FUN_8018f318` |
| CLOSE_REACTIONS | 0x800177DC (58) | 0x8001E7EC (entries 1–51) | (s16 reaction, s16 distance) | Lines 3084, 3088 |
| REVERSAL_LISTS | 0x80095AB8 (52, tags) | Pointers `PTR_DAT_801FCC44` (47, data from 0x800AC728, **row numbers**, end −1) | Condition 0x4B's arguments are equal on both sides (0–46). 23 of 47 lists pass an exact tag check | `FUN_8018ede8`, line 5147 |
| DIRECTIONS | 0x80010738 (2 × 9 u16) | 0x8001095C (2 × 9 u16) | Same order; bits Up 0x2000, Down 0x1000, Back/Left 0x800, Fwd/Right 0x400 (mask 0x3C00) | `FUN_8018e220`, line 4587 |
| BODY_RADII | 0x80097384 | `PTR_DAT_801FE55C` | Per charId | `FUN_8019f00c` |
| FACE_ATTACK | 0x80095D74 | 0x801FE2EC (0x29) | Indexed by +0x1E | `FUN_8019cbe4` |

**Reaction record** (**confirmed**, data: 496 mapped records, angle 496, angle2 496, slots 486, push entries 493–495):

| Arcade | PS1 |
|---|---|
| +0x00 s16 angle | +0x1C |
| +0x04 push pointer | +0x1E index |
| +0x08 u32 | +0x20; 0 in 371 records, not fully resolved |
| +0x0C push pointer | +0x22 index |
| +0x10 s16 angle 2 | +0x24 |
| +0x14 push pointer | +0x26 index |
| +0x18 push pointer | +0x28 index |
| +0x1C..+0x36 slots | +0x00..+0x1A |

Index map (monotone, 861 of 864 steps; from row pairs):

| PS1 reactions | Shift (arcade − PS1) |
|---|---|
| 0–0x78 | 0 |
| 0x7A–0xA5 | −1 |
| 0xA6–0x17C | −2 |
| 0x17E–0x189 | −3 |
| 0x18A–0x221 | −2 |
| 0x223–0x22F | −3 |

`0x1nnn` throw entries: a = nnn + 574…604, for example 0x1175 → 0x3D1 (367 of 370 first slots agree through the slot map). A few high PS1 records (0x232–0x236 at +54/+55, 0x278 → 0x13D) map irregularly on few votes. Close entries (47 in use, one-to-one): equal distance, reaction through this map.

## 6. Semantic differences

### Confirmed (read on both sides)

| # | Subject | PS1 | Arcade | Implemented in |
|---|---|---|---|---|
| 1 | Bank model | Two banks + common, merge on pair change (`DivmotMergeSharedSlots`) | One table, per-type slots, no merge; empty = row 0x1306 | `FightSimulation._link_banks`, `MotionBank`, `MoveRow.link` |
| 2 | CALL/RETURN rows | C00C jumps to common rows, C00D returns (`BranchFind`). [moves.md](../code/moves.md) documented this after this comparison | Not present; lists inlined. C00C, C00D are sequences | `MoveSystem._branch_find` (`CALL`, `RETURN`) |
| 3 | Sequence numbers | C00E+n | C00C+n, same contents | `_input_match`, `FightTables.sequences_a` |
| 4 | New commands | none | C007–C00A: at least 4 presses of LP, RP, LK or RK within 60 frames (`+0x420..+0x42C`). C00B: buffered command (`FUN_8018e4a8`, row +4). **No row uses them**; dead in the data | `_input_match` |
| 5 | Restriction boundaries | char == 0x46..0x5C, char != ≥ 0x5D | 0x46..0x5B, ≥ 0x5C (`FUN_8018f914`); data confirms 0x6A ↔ 0x6B | `MoveSystem.restriction_holds` (`_restriction_characters_end`) |
| 6 | Mode-specific rows | Mode 8 throw skip (`BranchFind`); mode 7 look-ahead and ball hit (`MoveBranchStep`, `MoveStep`) | Removed | `_branch_find`, `branch_step`, `step` |
| 7 | `branchWindow` | −1 written only when no move is pending (`MoveStep` tests `moveRow` first), so a pending move keeps it | −1 at every `FUN_8018f528` entry. Transitions 4/5 (`holdFrames = branchWindow`) get −1 if the pending move waited ≥ 1 frame | `MoveSystem.step`, `branch_step`, `_hold` |
| 8 | Reaction then attackClass | `if throwState > 0: attackClass = 1` | Absent | `step` |
| 9 | KO | Two variants by `DAT_800aff5b`: reaction, or collapse (0xD66). Collapse sets `attackClass = 1` | Collapse variant only (stance 3/0x19, or state & 4 == 0 and air0 == 0), no `attackClass`; `FUN_8018f3a0` also assigns poseMove and rootMove before the start and does not write moveSlot | `step`, `_collapse`, `FightState.collapse_on_ko` |
| 10 | Relative angles | `FighterRelativeAngles` recomputes atan2 at every call (`MoveStep`, move start, physics, look-ahead) | `targetDir` written once per frame by `FUN_8018b050`, after move start and before physics, and is the only +0x26 writer. `MoveStep` and move start read the stale value; `FUN_801a0a6c` updates both fighters from it; no `fixedFacing` branch | `relative_angles`, `step` |
| 11 | Distances | Per fighter, read at `MoveStep` | Global, computed once in `FUN_8018b124`, same adjust −40·n; adds a clamp when previous distance > 0x1CFF (PS1 has that test in `ArenaBounds` 80043394, not compared) | `Combat.pairwise_distances`, `step` |
| 12 | Conditions | `bodyContact` byte in 0x33/0x34 | Separation vector non-zero. Others identical; 0x26 written differently but equal. Data uses 0x48–0x4B only among ≥ 0x45 | `condition`, `_reversal_condition` |
| 13 | Transition 7 | Start at N | N − 1 | `_transition` |
| 14 | Transition 30 | Air kind 5 (slot 0xD57, empty in all banks) | Air kind 0xC (slot 0xE46, a real row). Arcade data uses 30 once | `_start_airborne`, `_air_kind_rows` |
| 15 | Transitions 31, 32 | Default | Same as 33 (throw attacker) | `_transition`, `_start_throw` |
| 16 | Transition 33, throwState < 0 | heading = opp.facing; tests 0x80000 | Heading turned 180°, anchor from opponent's root; no 0x80000 | `_start_thrown` |
| 17 | Transition 34 | Partner-flag branch | None | `_transition` |
| 18 | Transition 36 | Resets airVel | Keeps it | `_transition` |
| 19 | End of start | Sets `inThrow`, bank 0x13 posY rule, saves prev slot and stance, `reactChain` | None of these | `_finish`, `_count_react_chain`, `step` tail |
| 20 | +0x9E (`moveFlagBA`) | Cleared at start, read as blend suppression; the decompile has no writer of 1 (`SLPS` lines 4081, 6526, 15080) | Cleared at start (line 6616), set to 1 when pose and new row both have bit 6 (line 6676), read in the decay rule (line 13596) | `_reset_for_move`, `_blend_suppressed` |
| 21 | Guard strip at start | `humanGuard` logic | `(CPU or DAT_8021fc70 == 0) and state & 0x100`; `DAT_8021fc70` from `DAT_8036ec55` (setting; meaning inferred) | `_load_move_words` |
| 22 | Air reaction | Fresh unless slot 0xD62, or 0xD63/0xD64 past frame 0x12; attacker specials (bank 9 slot 0x241; bank 0x10 slot 0x14A with 0x848–0x849); Q1→4, Q3→3; exception 0xD58 | Fresh unless 0xE53/0xE54, or 0xE55/0xE58 past 0x12, 0xE56/0xE59 past 10, 0xE57/0xE5A past 7; no specials; Q1→9, Q3→6; exception 0xE46; not-fresh → kind 4 unless root height > 0x3FF. Note: exception maps to PS1 0xD57, not 0xD58 | `_air_reaction_kind` |
| 23 | Launch | Lower clamp −100; kind check 5 | No −100 clamp; kind check 0xC; kinds 3, 5 get a push (`+C0 = N − entry`, `+C2 = 0x14`) | `_launch_trajectory` |
| 24 | Reaction branch | Gon guard, extra slot clears | Absent, otherwise same | `reaction_branch` |
| 25 | Physics | Mode 7/8, Gon, slide-to-point blocks; airVel recompute inline | Those blocks gone; recompute in `FUN_80192978` (curTransition 0x1E, 0x24) at the end of `FUN_8018c340`; landing kind 0xC; face attack shape adds `row+0x32 < 0xC`; landed dust moved to the fight frame; +F0 set each frame. Tracking modes 0–10: same constants | `FighterPhysics.update`, `_flight`, `_slide_to_point`, `_ball_drift`, `_face_shape`, `_tracking` |
| 26 | Events | hi 6 and hi 4 vibrate; joints +0x8F4+0x44·j | No vibration; joints +0x75C+0x50·j; same dispatch and window, hand target 0→3 on both. hi 0x14 reads table 0x801FE344, all zero, equal to PS1's 0; hi 0x15 reads 0x801FE2EC by +0x1E | `MoveEvents.run`, `_joint_point` |
| 27 | Input | Buttons LP 0x80, RP 0x10, LK 0x40, RK 0x20; direction mask 0xF000; inHeld and inDir separate | LP 0x200, RP 0x100, LK 0x40, RK 0x20; mask 0x3C00; one byte. History and merge rule the same | `FighterInput.update`, `source` |
| 28 | Button tap latch | Previous kept across rounds | Previous reset when `DAT_8021fd88 == 1` | `FighterInput.latch_taps` |
| 29 | Stance start | Mode 7 exception; masks 0x90 (hold), 0x44 (choice) | No mode test; masks 0x300, 0xC0 (the 0x80 bit's meaning is open) | `FightSimulation._start_stance` |
| 30 | Win pose | Buttons 0x80, 0x10, 0x40, 0x20; posY = 0 | Buttons 0x200, 0x100, 0x40, 0x20; costume 0x24 → 0xE61; no posY = 0 | `RoundFlow._start_win_pose` |
| 31 | Blend suppression | flag 0x100, +BA, guardedPrev, inReaction | Only flag bit 0. +9E moved into the decay length | `_blend_suppressed`, `_decay_length` |
| 32 | Decay blend | Skipped if same move and branchKind ≠ 3; n = 4 or 0x10 past the active start | Skipped if same move (no kind test); throwState ≥ 0: n = 4 only if `wasHitThisMove == 0`, else n = 0 and mode reset | `_decay_length` |
| 33 | Forward blend | Also suppressed by +BB; branch needs kind ≠ 3; stance mode ends at counter == frames or move changed | No +BB, no kind test; stance mode ends only on move changed; branch length clamped to 1 if negative | `_no_blend_forward`, `_branch_length`, `_stance_length`, `_blend_choose` |
| 34 | Blend poses | Matrices of joints 1–17 (`PoseBuildMatrices`) | Euler to matrix (`FUN_8019a498`) for 18 joints; root decoded by `FUN_80194b58`; `+0x1826 = 0` at the end instead of `rootDyBlended` | `_blend_start`, `_blend_deltas` |
| 35 | Body profile | Cases 5 half, 6 +0x3C, 7 +100 | Cases 5, 6 half, 7 +0x3C, 8 +100; `if own == 6: opponent's forced 6`. **No effect**: row data has low nibbles 0, 1, 2, 3, 5 only. Masks and final loop same | `Combat.body_sphere_profile` |

**Same routines** (confirmed): `MoveLookup`, `MoveTotalDamage`, `TransitionRemap`, `MoveKeepsFrame`, `BranchEntersBeforeActiveEnd`, `SituationReset`, `SituationClassify`, `PushRepeatCount`, `ClampSymmetric`, `TrackBudget`, `ThrowVictimStart` (slot source apart), the button test, sequence matching, double tap, the branch step's windows and general look-ahead, `BranchFind`'s skip 0x1C and redirect 0x2C, and the frame's move order (start, targets, physics, …, hit test, branch, events, hit apply, …, input, latch, prev = pose, `MoveStep`).

**Transition codes used by arcade branch rows:** 0, 1, 2, 3, 6, 8, 10, 11, 12, 14, 15, 16, 18, 20, 21, 23, 24, 25, 26, 28, 30, 33, 44.

### Inferred

- `DAT_8021fc70` is the neutral-guard setting (read at lines 6639, 15631, 15639; source `DAT_8036ec55`).
- `FUN_8018f220` (slot 0xE62) and `FUN_8018f29c` (0xE5B) play the same round roles as the PS1's 0xD6C and 0xD65 starts. Bodies are the same; callers at lines 14700–14711 were not compared.
- Decompiled argument of `FUN_8018c340` in `FUN_8018a988` is missing; assumed to be both fighters (registers kept from the previous call).

## Open

- **Camera byte** +0x14: renumbered, readers not traced here; the [fight-frame.md](fight-frame.md) must cover the ids and bank-local PS1 lists.
- **Forced reaction** (PS1 0x8001DEC0): counterpart not located; arcade records from about 320 on are candidates, not proven.
- **Arcade slots 0xE64–0xEB9**: 86 long rows in all types, use unknown (only one branch target, 0xE7A).
- **Reaction record +0x08 / PS1 +0x20**: zero in 371 of 496, meaning of the rest not resolved. Push entries match in 493–495 of 496, the rest not explained. PS1 records 0x232–0x236 and 0x278 map irregularly, and throw entries 0x114C and 0x106B are ambiguous.
- **Slot map**: 13 pairs outside the monotone order are unproven, and some arcade slots with changed rows may have an unfound PS1 partner. Not important if arcade numbering is kept.
- **Reversal lists**: 23 of 47 pass the exact tag check; the rest miss one tag, probably rows the map does not pair. Not resolved.
- **Not compared line by line**: `InputClear`, `AttackUsesJoint`, `FUN_80040c04`/`FUN_801a0b58`, `FUN_801bcaac`, the blink routine, the 0x1CFF clamp against `ArenaBounds`, `BranchFindReversal`'s walk apart from conditions.
- **Not mapped here**: `HitClearSlots`, `FUN_80045260`, `FUN_8018cbd8` ([combat.md](combat.md)).
- **Not read in full**: `tools/remake_import/motion_bake.py`, `docs/research/code/combat.md`, `fighter.md`.
- **Stance mask 0xC0**: which button bit 0x80 is on the arcade pad.
- **Empty PlayStation slots.** The PS1's empty fallback slot 0xDC5 and empty air kind slot 0xD57 are not in the bug register: no routine is shown to reach them.
- **Not run**: nothing was verified in the CPU harness; all results are from reading code and from static data. Behaviour of differences 7, 10 and 32 has not been measured in a trace.
