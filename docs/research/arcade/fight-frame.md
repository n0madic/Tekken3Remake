# Arcade fight frame, round flow, round HUD and camera director

Arcade: MAME `tekken3`, World ver. E1, program `prg_world_e1.unpacked.bin` (load `0x80010000`). PS1: Japan Rev.1.
Fighter records: arcade `0x8031E154` / `0x8031FC38` (stride `0x1AE4`), PS1 `0x800A96F0` / `0x800AAF7C` (stride `0x188C`).

**Evidence.** `confirmed` means read on both sides (Ghidra decompile, capstone where the decompile was doubtful). `inferred` means read on one side, or a role deduced from use. This comparison was made by reading; the port that came out of it is compared with the original routine in the CPU harness (`tools/research/arcade_fight_harness.py`, `remake/tests/fight/test_arcade_fight_traces.gd`). Data tables were dumped from the unpacked program and from `work/jp_rev1/exe.bin`.

**Headline.** The arcade's fight frame and round flow are the PS1's, with the home-only branches absent. The camera director is the same state machine, but it runs on a stage-dependent projection H (550–800, not 500), integer weights, a global list of 215 camera choices and an arcade-only stream format. Most framing constants are rescaled, and one mode field that is dead on PS1 is live here.

---

## 1. Fight frame

`FightFrame` (`0x8002B0AC`, `FightMain` game state) next to `FUN_8018A988`, called from the flow `FUN_801B6BA4` (states 7, 9, 0xB, 0xD). The prologue is `0x8021FD30 = 0, 0x8021FBD0 = 0, 0x8021FB38 = 1`. The PS1's pause detection (`FUN_8002B9EC`) has no counterpart. The pause path exists, but only flow state 0xD sets `0x8021FAD0` (challenger).

Live path, `0x8021FAD0 == 0` (PS1 `0x8009588C`/`0x800958B8` clear):

| # | PS1 | Arcade | Role | Same? |
|---:|---|---|---|---|
| 1 | `FUN_8003EE94` | `FUN_8019EE00` | Requested replay starts; request 2 also stores the round (`FUN_80195178`; PS1's `FUN_800323C4` is empty) | Same, plus the store |
| 2 | `ReplayUpdate` | `0x8021F03C = FUN_8019541C()` | Replay machine; non-zero selects the replay path | Same |
| 3 | `FUN_8003CDD8` | `FUN_8019D560` | Round flow | §3 |
| 4 | `HudRoundUpdate` | `FUN_8019DCA8` (only when not replaying) | HUD, messages, voices | §4 |
| 5 | `CameraDirector` | `FUN_801D009C` (`FUN_8018B500` first half) | Director | §5 |
| 6 | `FighterUpdateSide` ×2 | `FUN_801A2D9C` (`FUN_8018B500` second half) | Side flags, now globals `0x8021F6C0/C2` | Same test, no fixed facing |
| 7 | `CameraShakeStep` | `FUN_801AE9DC` | Shake | Same |
| 8 | `CameraFrame` | `FUN_801A6DBC` | View matrix and stage draw | Same; scale differs (§5) |
| – | – | stage 6/12 `FUN_801E2114`; `FUN_801E3D0C` | New: stage objects | New |
| 9 | `FUN_800421E4` ×2 (`FighterSavePrevSegments`) | `FUN_80198A48` ×2 | Attack segment points `+0xF4`, `+0x10C` from the joints (row `+0x32..35`, `+0x98` count; id 0x13 on char 0xE → 6) | Same place; same role (`inferred`, [combat.md](combat.md)) |
| 10 | `MoveStartAll` | `FUN_8018C498` | Move starts, alternating by `0x8021FDA4 & 1`; throw pair 0x21 by `FUN_8018F318` | Same place |
| 11 | `PairwiseDistances(FUN_80045B10())` (active count) | `FUN_8018B050`, `FUN_8018B124` | Direction, distances | **Differs**: no off-screen stand-in (§7 D3); `FUN_8018B124` has an arcade-only restore |
| 12 | `FighterMovePhysics` ×2 | `FUN_8019F3FC` | Physics (`inferred`, [combat.md](combat.md)) | |
| 13 | `SavePlayerPosition` ×2 | inside `FUN_8018B124`, **before** physics | Saved positions `0x8021FE00` | **Order differs** |
| 14 | – | both `+0x64 == 0`: `FUN_801A5B00`; `FUN_8019C738` | Round body-pair step; wind | Wind new |
| 15 | `FighterSkeletonUpdate` | `FUN_8018B388` | Skeleton **and draw**; writes the screen coordinate | Same |
| 16 | `ArenaBounds` ×2, `FUN_80043260`, `FUN_800432B0` ×2, `ArenaRampStep` | absent here | Walls | **Differs** ([combat.md](combat.md)) |
| 17 | `FUN_8006DAB4`, `EffectDescriptorSpawn` ×2, `FUN_8006F8A8`, `FUN_80075CBC` | `FUN_801D8FD0`, `FUN_801DC758` ×2, `FUN_801DC990` | Stage, effects | Same place |
| 18 | `FighterVelocity` ×2 | `FUN_8018B430` ×2 | `+0x30C` = root − saved | Same |
| 19 | `CollisionShapesUpdate` ×2 | `FUN_80198BF8` ×2 | Hit shapes | Same |
| – | – | landing: `+0xAB` and mask → `FUN_801AE4B4(root)`, `FUN_801AE9B0(0)` | New: dust and shake on landing | **New** |
| 20 | `BodySphereProfile` ×2, `FUN_80043F40` | `FUN_8019EF90` | Body sphere by row `+0x38` (6 forces both) | `FUN_80043F40`'s counterpart not identified (Open) |
| 21 | `BodySeparate` (phase < 3) | `FUN_8018B808` (phase < 3) | Only when both `+0x64 == 0` | Same gate on the phase |
| 22 | `HitClearSlots` ×2, `HitTest` ×2 | `FUN_8018B91C` | Hit test | Merged |
| 23 | `AttackVelocity` ×2 | `FUN_8018B47C` ×2 | `+0x318` | Same |
| 24 | `MoveBranchAll` | `FUN_8018C2DC` | Branches | Same |
| 25 | `MoveEvents` ×2 | `FUN_8018C5A4` | Events | Same place |
| 26 | `FUN_80045260` ×2, `HitApply` ×2 | `FUN_8018BB68` | Apply hits; first KO marks the replay | Merged |
| – | – | `FUN_8018CBD8` ×2 (`FUN_801BCB0C`) | New: operator statistics | New, no gameplay |
| 27 | `FighterSounds` ×2 (`active`) | `FUN_801A104C` by mask `0x8021FB00` | Sounds | Same |
| 28 | `if (!FUN_8002BDAC) { FUN_8007780C, FUN_8004AF4C }` | `if (!FUN_8018B57C) { FUN_801ADAF4(f0), FUN_801AE4E4 }` | Effect runs | Same |
| 29 | `InputSource` ×2 | `FUN_8018B61C` | Input by mode: 1 real (cleared if health 0, or CPU after round over), 0 cleared, 2 kept | Same modes |
| 30 | `LatchButtonTaps` ×2 | `FUN_8018B710` | Button taps; ring byte `+0x360 + [+0x34C]`, bits 0x10/0x20 | §7 D23 |
| 31 | `+0x5A = +0x58` | `+0x4A = +0x48` | Previous frame | Same |
| 32 | `MoveStepAll` | `FUN_8018C340` | Move step; KO collapse `FUN_8018F3A0`; `FUN_80192978` ×2 | Same place |
| 33 | `0x80095888 = 0x80095884` | `0x8021FBEC = 0x8021FD88` | Previous round frame | Same |

There is no third fighter and no Force or Ball branch. Every fighter loop is two records.

**Replay path** (`0x8021F03C != 0`): `0x8021FB38 = FUN_801969B4()` (half-frame parity); `FUN_8018AFD8() & 0x8000` → `FUN_8019570C`, `0x8021FB0C = 1`; `FUN_801D6C08`; `FUN_801AE9DC`; `FUN_801A6DBC`; `FUN_801E3D0C`; stage 6/12 `FUN_801E2114`; `FUN_8019C738`; `FUN_8018B388`; `FUN_801D8FD0`; `FUN_801DC758` ×2; `FUN_801DC990`; `FUN_801AE6B4`; `FUN_801ADD18`. PS1 order: `FUN_800339DC`, Start check, `FUN_800696FC`, shake, `CameraFrame`, skeleton, effects, `FUN_8004A954`. Same sequence, with wind and stage objects added. `confirmed`.

**Pause path** (`0x8021FAD0 != 0`, not replaying): `+0x11B0 = 1` both, `FUN_8019DCA8`, `FUN_801A6DBC`, `FUN_8018B388`, `FUN_801D8FD0`, `FUN_801DC990(0)`, `FUN_801AE44C(0)`, `FUN_801ADA60(0)`, `FUN_8018B61C`, `FUN_8018B710`. It returns the round state via `FUN_8019D540`. In a replay it runs `FUN_801A6DBC`, `FUN_8018B388`, `FUN_801D8FD0`, `FUN_801DC758(f, 0)` for both, `FUN_801DC990(0)`, `FUN_801AE6B4(0)`, `FUN_801ADD18(0)`. The start of the routine clears `0x8021FBD0` in either case, never `0x8021FAD0`: the caller does (`confirmed`: trace `challenger`, `ArcadeSimulation._stopped_frame`).

Called from outside the flow: `FUN_8018AE8C(p)` (`0x8021F608 = 1`, phase 3/4 then 5, `+0x36 ± 1`) is the forced end used by the challenger or debug path (`inferred`).

---

## 2. Function map

### Round flow

| PS1 | Arcade | Confidence, evidence |
|---|---|---|
| `FightFrame` `0x8002B0AC` | `FUN_8018A988` | confirmed: call order |
| `FUN_8002AB68` round start | `FUN_8018A6D0` | confirmed: same sequence of resets |
| `FUN_8002A660` match start | `FUN_8018A44C` | confirmed: rounds `+1`, cap 5, `2n−1` |
| `FUN_800519B4` full health | `FUN_801B7C50` | confirmed |
| `FUN_8002BFCC` placement | `FUN_8018C8BC` (both fighters) | confirmed: x ∓1000, facings, `+0x1154 ∓100` |
| `PairwiseDistances` after placement | `FUN_8018CB08` | inferred |
| `FUN_8003CD9C` flow reset | `FUN_8019D528` | confirmed |
| `FUN_8003CDD8` | `FUN_8019D560` | confirmed |
| `FUN_8003CE64` | states 5/6 of `FUN_8019D560` | confirmed |
| `FUN_8003E608` round over | `FUN_8019E690` | confirmed |
| `FUN_8003E6D0` | `FUN_8019E6D0` | confirmed |
| `FUN_8003E70C` result flags | `FUN_8019E718` | confirmed: same flags |
| `FUN_8003E7C4` round wins | `FUN_8019E82C` (+ stats `FUN_801BC410`) | confirmed |
| tie breaker | `FUN_8019E7D4` | confirmed |
| `FUN_8003EA98` match result | `FUN_8019EA54` | confirmed |
| `FUN_8003EB60` win pose | `FUN_8019EAE8` (`FUN_8019CCEC`, `FUN_8018F070`) | confirmed |
| `FUN_8003EBF4` lose markers | `FUN_8019EB7C` | confirmed |
| `FUN_8003EC54` lose poses | `FUN_8019EBE0` (`FUN_8018F29C`, `FUN_8018F220`) | confirmed |
| `FUN_8003ECF4` result camera | `FUN_8019EC80` | confirmed |
| `FUN_8003D7A8`, `FUN_8003D860` | no routine: inline in state 2 | confirmed: rule differs |
| `FUN_80051AD4` carried health | `FUN_801B7F04`, `FUN_801B7DAC`, `FUN_801B7E34` | confirmed: same rule |
| `OgreSceneCheck` `0x800514EC` | `FUN_801B7B8C` | confirmed: narrower |
| `FUN_8002C23C` | `FUN_8018CB70` | inferred: same place |
| `FUN_8002BE54` | inline (`0x8021FAE4/8 = 0`) | confirmed |
| `ReplayInit` | `FUN_80194EFC` | confirmed |
| `FUN_80032030` KO mark | `FUN_80194F94` | confirmed: identical |
| `ReplayStart` | `FUN_80194FD4` | confirmed: no `back` argument |
| `ReplayUpdate` | `FUN_8019541C` | confirmed |
| `FUN_80032810`, `FUN_80032828` | `FUN_801956F8`, `FUN_8019570C` | confirmed |
| `FUN_800323C4` (empty) | `FUN_80195178` | confirmed: stores the round |
| replay parity (`g_replayPlayback`) | `FUN_801969B4` | confirmed |
| `FUN_8004F5C4` Mokujin | `FUN_801B5224` | inferred |
| `FUN_8006DAB4` | `FUN_801D8FD0` | inferred: place, name |

### HUD

| PS1 | Arcade | Confidence |
|---|---|---|
| `HudRoundUpdate` `0x8003D904` | `FUN_8019DCA8` | confirmed |
| `FUN_8003DCE0` | `FUN_8019DEC4` | confirmed |
| `FUN_8003E158` (result voice) | `FUN_8019E1F0` | confirmed |
| `FUN_8003E2F8` (winner voice) | `FUN_8019E318` | confirmed |
| round text | `FUN_8019E034` | confirmed |
| result text | `FUN_8019E260` | confirmed |
| winner text | `FUN_8019E400` | confirmed |
| `FUN_8004D15C` print | `FUN_801B25B8` | confirmed: same format codes |
| `FUN_8004E410` timer | `FUN_801B35FC` | confirmed |
| `FUN_8004E55C` bars | `FUN_801B374C` | confirmed |
| `FUN_8004E87C` marks | `FUN_801B3B34` | confirmed |
| `FUN_8004EB9C` name plates | `FUN_801B3E20` | confirmed |
| `FUN_8004EFF8` mode line | `FUN_801B4734` (`FUN_801B437C`, `FUN_801B4514`, `FUN_801B462C`, `FUN_801B46AC`, `FUN_801B46F0`) | inferred: inner routines unread |
| `FUN_8004E520` | `FUN_801B3710` | confirmed |
| `FUN_8004E868` | `FUN_801B3B24` | confirmed |
| – | `FUN_801B3FE4` win streak `WIN %01d` | new |

### Camera

| PS1 | Arcade | PS1 | Arcade |
|---|---|---|---|
| `CameraDirector` `0x800633C0` | `FUN_801D009C` | `CameraReset` | `FUN_801CEA84` |
| case 1 | `FUN_801CF9AC` | case 2 | `FUN_801CEB78` |
| `FUN_800661C0` | `FUN_801D2B54` | `FUN_80063FA4` | `FUN_801D0320` |
| `CameraSetProjection` | `FUN_801D028C` | `CameraLookPoint` | `FUN_801D03D8` |
| `FUN_800641D4` | `FUN_801D05E0` | `CameraSourceCopy` | `FUN_801D06D0` |
| `FUN_80064308` | `FUN_801D0770` | `CameraUseSource` | `FUN_801D0824` |
| `CameraBlendPair` | `FUN_801D0AF8` | `FUN_800648F4` | `FUN_801D0F44` |
| `CameraTrackFighters` | `FUN_801D0F9C` | `CameraYawSpring` | `FUN_801D1344`, limit `FUN_801D11E8` |
| `CameraFight` | `FUN_801D2D1C` | `CameraFrameFighters` | `FUN_801D1AE4` |
| `FUN_80062DEC` | `FUN_801CEB2C` | `FUN_8006312C` | `FUN_801CFC28` |
| `FUN_8006320C` | `FUN_801CFD44`, `FUN_801CFEF0` | `FUN_800664A0` | `FUN_801D2E98` |
| `FUN_80066430` | `FUN_801D2E10` | `FUN_80066568` | `FUN_801D2F4C` |
| `FUN_800666E0` | `FUN_801D3110` | `FUN_800669D8` | `FUN_801D3970` |
| `FUN_800670AC` | `FUN_801D3938` | `FUN_800670E4` | `FUN_801D367C` |
| `FUN_800673E4` | `FUN_801D4100` | `FUN_80067DE4` | `FUN_801D4BA0` |
| `FUN_800676CC` | `FUN_801D45C0` | `FUN_800677C8` | `FUN_801D4650` |
| `CameraChoose` | `FUN_801D4454` | `CameraThrowStart` | `FUN_801D4800` |
| `FUN_80067B14` | `FUN_801D49A0` | `CameraThrowEnds` | `FUN_801D4698` |
| `FUN_80067C8C` | `FUN_801D4B2C` | `FUN_80067ECC` | `FUN_801D4C9C` |
| `CameraHitChoose` | `FUN_801D4E88`, `FUN_801D4DA4`, `FUN_801D4E60` | `FUN_800681F0` | `FUN_801D5030` |
| `FUN_80068210` | `FUN_801D504C` | `FUN_80068228` | `FUN_801D5060` |
| `FUN_80068244` | `FUN_801D5078` | `FUN_8006867C` | `FUN_801D556C` |
| `FUN_8006879C` | `FUN_801D56D4` | `FUN_80068998` | `FUN_801D5970` |
| `FUN_800689F4` | `FUN_801D59A4` | `FUN_80068A44` | `FUN_801D59FC` |
| `FUN_80068C44` | `FUN_801D5F4C` (`FUN_801D5BE0`, `FUN_801D5E94`) | `FUN_800693E8` | `FUN_801D683C` |
| `FUN_800696FC` | `FUN_801D6C08` | `FUN_80069824` | `FUN_801D6DA8` |
| `FUN_800466F8` | `FUN_801A511C` | `FUN_80046854` | `FUN_801A52A8` |
| `FUN_80046CB8` | `FUN_801A57A0` (dead) | `FUN_80046508` | `FUN_801A4FE8` |
| `FUN_80046A38` | not called | `FUN_800463A4` | `FUN_801A2A24` |
| `CameraBuildView` | `FUN_801A26A4` | `CameraFrame` | `FUN_801A6DBC` |
| `CameraShakeStep` | `FUN_801AE9DC` | `FUN_8004AF88` | `FUN_801AE998` |
| shake start | `FUN_801AE9B0` | `FUN_80036CFC` | `FUN_8019C7DC` |
| `FighterDrawParts` | `FUN_8019A6D0` | `FighterUpdateSide` | `FUN_801A2D9C`, reader `FUN_801A2DD4` |
| `FUN_800569D0` | `FUN_801C2F6C` (inferred) | `Atan2Units4096` | `FUN_801AF4D4` |

The whole camera table is `confirmed` by side-by-side reading unless marked otherwise. Attract cameras: `FUN_801D5F94`, `FUN_801D6004`, `FUN_801D61F0`, `FUN_801D66E0`, style setup `FUN_801D67F4` (PS1 `FUN_80068E90` family; `inferred` by shape).

---

## 3. Round flow

**Numbering.** Arcade state `0x8021F0C0`: 0 intro, 1 fight, 2 result, 3 request, 4 replay, 5/6 win, 7 end (PS1 9), 8 Ogre scene (PS1 10). The PS1's ball states, Force states and stage clear do not exist.

| State | Arcade | Against PS1 and `round_flow.gd` |
|---|---|---|
| 0 | Count to `0x97` (first round) or `0x5B`; input modes both 1 | Same (no practice exception) |
| 1 | Timer always decrements; when over: `FUN_8019E690`, `FUN_8019E6D0`, `FUN_8019E718`, `FUN_8019E82C`, `FUN_801B7F04`; lock (see below), `FUN_8019EB7C`; hold `0xF0` (`0x5A` on time up) with inputs 0 | No infinite-time flag `0x800958D4`. **New**: decided match, mode 0, `(0x80374F33 >> loser) & 1`: `0x8021FD48 = 1` and `FUN_801B65AC` (drops joined players, `inferred`) |
| 2 | Only on time up or for a CPU (`+0x34A > 2`): if not crouching (`+0x50 & 4 == 0`), health 0, or `+0x36 < 1`: mode 0; else mode 2, `+0xD0 = 0`, ring byte `= 8`. Done at counter `0x5A`, inputs 0, `FUN_801A1A80` ×2, `FUN_801B0B14`, state 3 | **Differs** (D5): a human after a KO keeps mode 1, winner or loser. No `FUN_8003D860` |
| 3 | If `0x8021FD24 == 9` and a CPU is present and the match is decided and the winner is human: request 2, `FUN_8019EE00` now, state 7. Else request 1, state 4 | **New** (D6): the last fight's human win skips replay and win poses and stores the round |
| 4 | Wait `FUN_801956F8`; `0x8021FB50 = 2`; `FUN_801ACB6C`, `FUN_801AE0B4`, sound stop ×2; undecided and (Start or skip) → state 7; `FUN_8019EAE8`; `FUN_80198390` ×2 **unconditional**; `FUN_8019EC80`; loser phase → `FUN_8019EBE0`; `FUN_8018CB70` | `FUN_8003AA6C` only when not time up on PS1 (D7); no `FUN_8004B920` |
| 5/6 | Hold 300; carry (flag 0x20) as PS1; ends: phase 2 at `0x4B`; phase 6, 7 at `0x3C`; phase 5 when both win poses end by row `+0x1E`; Start skips | **New**: mask 3 and `0x8021FC5C != 0`: Start cannot skip |
| 7 | End; `FUN_801B7B8C` → `FUN_8019EE9C`, state 8 | Ogre check narrower |

**Round start.** `FUN_8018A6D0` is `FUN_8002AB68` with these differences: no force or ball branches; `FUN_801A4C78` is added after the distances (it sets `+0x1154 = ∓100` and places the active camera from table `0x80164BA0`, 14 rows × (x, y, z), indexed by `0x8021F124 % 14`; the director overwrites the camera before the first drawn frame, and the `0x8021F708/70C` it writes have no reader, so it looks like a leftover, `inferred`); `FUN_8019C72C` wind reset; **no `MusicPlay`**, which is replaced by the round music at intro frame 3 (`FUN_8019EED4(0x8021FBD4)`); `FUN_801B09AC` only when `0x8021F048` (set at match start when the music state is clear).

**Timing.** The KO flag and timers match PS1: intro `0x97`/`0x5B`, result hold `0xF0`, time up `0x5A`, win hold 300. The HUD frame thresholds below also match.

**KO and replay.** `FUN_8018BB68` sets `+0xAC`; the first KO (latch `0x8021F60C`) calls `FUN_80194F94(opponent)`: mark `= (cursor − opp.frame − 30) · 2` wrapped to 600. No mark (time up): state 5, no replay.

Replay states as PS1: 7 record, 2 start, 3 first frame, 1 play, 4 ending, 5 done. Half-frame cursor +1 per frame in 600 units, so half speed. The end is `2·cursor − 2`, or a skip. `FUN_8019541C` returns 0 in states 5, 7, 8, else the state, as `ReplayUpdate`, selecting the replay path through `0x8021F03C`; `FUN_801969B4` gives `(cursor ^ 1) & 1`, the half-frame parity. Start is at most 150 frames back (PS1 also requires more than `0x98` recorded frames; unreachable in practice, `inferred`).

Record size `0x2C` per fighter per frame, against the PS1's `0x34`. Buffers: 11 slots of `0x6720` bytes at `0x80324ACC`, slot `0x8021F644 = 10` live, slots 0–9 keep rounds for attract by fight number (`FUN_80195178`, when the side with most health has joined, `0x8021FD18/1A`). The ring is 300 frames, as on PS1. Text `REPLAY` at (`0x154`, `0x1E`), colour 7, font 1, blinking on `0x8021FDA4 & 0x10` (PS1 x `0xF4`).

**Number of rounds, time.** Boot `FUN_80189FF4` copies the settings block (bytes in NVRAM data at `0x8036EC1C`):

| Byte | Copy | Use |
|---|---|---|
| `0x8036EC4F` | `0x8021FD28` | Set to 1 by modes 3, 4; difficulty-like ([ai.md](ai.md)) |
| `0x8036EC50` | `0x8021FD94` | Rounds to win − 1 with < 2 players (`0x80374F36`) |
| `0x8036EC51` | `0x8021FD98` | Same with 2 players |
| `0x8036EC52` | `0x8021FDD0` | Health index, one player |
| `0x8036EC53` | `0x8021FC54` | Health index, two players |
| `0x8036EC54` | `0x8021FDA8` | Chip damage switch (`FUN_8018BB68`; [combat.md](combat.md)) |
| `0x8036EC55` | `0x8021FC70` | Clears move flags with `+0x50 & 0x100`; `0` = humans too ([moves.md](moves.md)) |
| `0x8036EC56` | `0x8021FC84` | Timer `(v + 2) · 600` frames, as PS1's `0x800AE3C0`; modes 3, 4 force 2; mode 5 forces 5 |
| `0x8036EC57` | `0x8021FB10` | Flag bit 8 of `0x80374F1C` |
| `0x8036EC58` | `0x8021FCA4` | Flag bit 2 of `0x80374F1C` (challenger, `inferred`) |
| `0x8036EC59` | `0x8021FC20` | Attract sound gate |
| `0x8036EC5A` | `0x8021FC5C` | Two-player-only game (`inferred`: forces both sides in at mode 0; no Start skip; `GAME OVER`) |
| `0x8036EC5B` | `0x8021FBBC` | Gate on a picture transfer next to `FUN_801BB5C4` (`inferred`) |
| `0x8036ECF0` | `0x8021FD3C` | Allows the 480-line display mode |
| `0x8036ECF3` | `0x8021FCDC` | Unread |
| `0x8036ECF4` | `0x8021FB74` | Health table selector |

Rounds: `0x8021FC10 = 0x80374F36 + 1`, cap 5; `0x8021FCBC = 2n − 1` (as `0x800AE2C4`, `0x800AE404`); a draw decrements it (as PS1). Modes 2, 4, 5 force `0x80374F36 = 0`, mode 3 forces 1. Rounds are counted in `0x8021FC08`, saved over a challenger by `FUN_8018A380` / `FUN_8018A3F8`.

**Health.** `FUN_801B7C50`, 16.16: mode 0: `0x8017955C` if `0x8021FB74 == 1`, else `0x8017957C`, 8 × u32, by the health index above (example, `0x7D0000, 0x820000, …`; `0x5F0000, 0x6E0000, …`). Mode 1: `0x8017953C[handicap]` (8 entries, same values as PS1's `0x80022858`; handicap `0x80374F52 + 4·player`, default 3). Mode 2 `0xAA0000`, mode 3 `0x6E0000`, mode 4 `0x8C0000`, mode 5 `0xC80000`, mode 6 `0x7D0000`. PS1 `FUN_800519B4`: mode 0 fixed index 3 (2 players) or 8; mode 3 `0x820000`. Placement starts at max, or the carried `+0x344` with flag 0x20 when valid, same rule as PS1.

**Handicap at match start.** `FUN_8018A44C(char0, ctrl0, cos0, char1, ctrl1, cos1)`: control `+0x34A`: 1 (2 for player 2) for a human, `ctrl·2 + 1` / `ctrl·2 + 2` otherwise; ≥3 is CPU.

**Flow outside.** `FUN_801B6BA4` state 7 acts on the return value: 8 → Ogre scene (states 0xE, `FUN_801E173C`), 9 → state 0x13, ≥7 → `FUN_80195178`, next fight by mode. Mode 6: `GAME OVER` (2, 1, `0xAE`, `0x104`) printed here, not in the HUD, and the demo ends at state ≥3. State 9 keeps running the fight frame behind the continue screen, state 0xB behind `GAME OVER` (1, 2, `0x79`, 200, `0x97` frames) ([flow-and-screens.md](flow-and-screens.md)).

---

## 4. HUD logic

`FUN_8019DCA8` runs announcements unless `0x8021FC64` (attract) or `0x8021FB70` (challenger). State 0 (frame ≠ 0): `FUN_8019E034`, `FUN_8019DEC4`. State 2: `FUN_8019E260`; if not paused `FUN_8019E1F0`. States 6, 7: `FUN_8019E400`; if decided, or no skip, or paused, `FUN_8019E318`. Drawing if `0x8021FD1C`.

**Values** (all `confirmed`):

| Item | Arcade | PS1 / `.gd` |
|---|---|---|
| Timer | `(timer + 0x3B) / 0x3C`, digits 20 × 46 at x 0x100, 0xEC, y 0x16; argument −1 (`∞`) exists but is never passed | `FUN_8004E410`: 16 × 46 at 184, 169; `fight_hud.gd` |
| Bars | length **`0xD2` (210)**: `⌈health / (max / 210)⌉`, drawn grows +3, recent closes by `(d + 15) >> 4`; records `0x801FF3DC`, stride `0x1C`; three quads as PS1 | length 152 (`round_hud._bars`, `BAR_LENGTH`): only the 152 changes; bar values are in the sim state, so traces would differ |
| Round marks | `0x8021FC10` marks, 20 × 18, y `0x46`; x `0xD4` step −20, `0x118` step +20; blink `0x8021FD58 & 0x10` on the mark won since `FUN_801B3B24` | 15 × 18, x 151/202, step 14 |
| Name plates | Table `0x80178FE0`, stride 8 (x 22, y 66; x 490 − width, y 66) | (14, 66), (354 − w, 66) |
| Mode line | `FUN_801B4734` | No GAME OVER print here (flow); no team icons call |
| New | `FUN_801B3FE4` if `0x80374F1C & 8`: `WIN %01d`, `WINS %02d`, at y `0x1B0`, colour 1, font 8 (win streak, count `0x8021F14C`) | – |

**Messages** through `FUN_801B25B8` (`%c%f%H%V` = colour, font, x, y). The strings are the PS1's with x moved to the wider screen:

| Text | Arcade | PS1 x |
|---|---|---|
| `ROUND %1x` | 8, 2, `0x97`, `0x70` | `0x6B` |
| `FINAL ROUND` | x `0x5B` | `0x3F` |
| `TEMA BATTLE` (sic) | x `0x59` | `TEAM BATTLE`, `0x3F` |
| `SURVIVAL BATTLE` | x `0x1D` | `0x13` |
| `PRACTICE MODE` | x `0x2E` | `0x29` |
| `READY?` | 9, 2, `0xA6`, `0xE4` | `0x76` |
| `TIME UP` | 3, 2, `0x97` | `0x6B` |
| `PERFECT!` | 2, 2, `0x88` | `0x60` |
| `DOUBLE K.O.` | 1, 2, `0x5B` | `0x3F` |
| `K.O.` | 1, 2, `0xC4`; no guard on the replay request | `0x8C` |
| `DRAW` | 6, 2, `0xC4`, `0x170` | `0x8C` |
| `%s WINS!` | 4, 2, `0x100 − (len·0xF + 0x5A)`, `0x170` | `0xB8 − (len·0xB + 0x42)` |
| `WINNER` | 3, 1, `w·0x110 + 0x42`, `0x68` | colour 9, `w·0xC4 + 0x2F` |
| `LOSER` | 3, 1, `(1 − w)·0x110 + 0x4B`, `0x68` | colour 9, `·0xC3 + 0x36` |
| `YOU LOSE` / `YOU WIN!` | 5 / 4, 2, `0x88`, `0x170` | `0x60` |
| `GAME OVER` | **New**: 3, 2, `0x79`, 200, when decided, mode 0, `0x8021FC5C != 0`, on a draw or versus win | – |

HUD y stays in 480-line units in every string, on both displays (`inferred`: the 240-line mode halves them in the print layer; not read).

**Voices** (`FUN_801A0C10`, announcer): `FUN_8019DEC4`: frame 3 round music (new); frame `0x3D` / 1: `0x103A` on the last round, else `0x103B`; 100 / `0x28`: `0x8015F4AA[round]` (`0x1034…`, same as `0x8001A3BA`) unless last; `0x96` / `0x5A`: `0x103C`. No mode branches. `FUN_8019E1F0`: literal codes time up `0x1013`, perfect `0x1019`, double KO `0x1015`, great `0x1018`, KO `0x101A` (PS1 table `0x8009749A` through `SoundPlayFighter`). `FUN_8019E318`: draw `0x1014`; mask 3 or mode 2: a character voice, s16 at `0x8015FEBA + (+0x1C)·0x18`; else `0x1011` / `0x1012`. No `ResultWinVoice`, no `0x86DA` follow-up, no Tiger case, no music fade (PS1 `FUN_8006B9B0(0xF0, 0)`).

---

## 5. Camera

### Projection and display

- **H.** `0x8021FAF4` holds the current H (start `0x352`, set by `FUN_801D028C`, which clamps to the stage's range). `FUN_801D0320(stage)` reads `0x8017AB04`, 14 rows × 5 s16 (H, Hmin, Hmax, scale flag, mode; stage > 13 → 0). H by stage 0–13: 600, 800, 600, 800, 700, 800, 700, 800, 800, 600, 550, 800, 600, 800. Hmin = H, Hmax = 960 in the rows checked. PS1: fixed 500/500/500, flag 1, mode 0.
- **Fight distance.** `H · 0x4B840 / 0x9280` (≈ 8.2475 H: 550 → 4536, 600 → 4948, 700 → 5773, 800 → 6598). PS1 constant `0x158D` = 5517. So H only changes perspective; the world width visible at the fight distance stays `256 · 8.2475 ≈ 2111` on every stage (PS1 `184 · 5517 / 500 ≈ 2030`).
- **Screen.** `FUN_801A23C4` → `FUN_801BB838(4)`: 512 × 480 interlaced if `0x8021FD3C != 0`, else mode 0, 512 × 240. Table `0x801FF898`, 16-byte rows. OFX/OFY are half the mode (`FUN_801F07F4`): 256, 240 or 120. PS1 192, 240, 368 visible.
- **View matrix.** `FUN_801A26A4` is `CameraBuildView` with the Y row scale `(0xA00 << 0x8021FC98) · 95 / 100`: `0x980` (240 lines) or `0x1300` (480), against `0x1BD2`. It only touches row 1 (SY). `0xA00` is what a 512 × 240 frame needs for true proportions at 4:3 (`10/16`): the frame is ±256/H by ±202/H, proportions 1.267:1, and the monitor shows it at 4:3, so the scene is 5.26 % wider there than its geometry. `confirmed` by the 2D layout against MAME's pictures; the HUD fills the 512 columns whatever the scale.

### Side tests

The arcade does what the PS1 does. `FUN_8019A6D0` (draw, inside `FUN_80198390`, inside the skeleton step) runs `RTPS` on the origin of part `0xB` with the frame's view matrix and stores `SXY` in `+0x1154`, `SZ` in `+0x1156` (PS1 `FUN_80036CFC`, `+0x1278`). `FUN_801A2D9C` compares the two SX: `flag[i] = !(me.x < other.x)`, same as `opp.x <= me.x`. Input reads the flags (`FUN_801A2DD4` in `FUN_8018E0DC`; CPU side is 0) and so do move conditions `0x3E`–`0x41`.

- **Constants.** OFX and H do not change an order, so the decision only moves through rounding and SX saturation, and because the camera itself differs. The Y scale is irrelevant to SX.
- **Readers of `+0x1154`** (grep of the decompile, 14 lines; pointer arithmetic not excluded): side flags; `FUN_801D0F9C` (into `0x8021FBAC`, prev `0x8021FDD4`); `FUN_801D1344`; `FUN_801D2E10`; `FUN_801A2EDC`; AI `FUN_801CDA04`; round-start writes.
- **Gone.** No absolute screen test survives: `PairwiseDistances`' off-screen stand-in (`SCREEN_EDGE`, `0x191`, `0xB4 − |0xB4 − x|`) has no arcade counterpart (D3). `fixed_facing` is gone too.
- **Part `0xB`.** The index is the same on both, but whether it is the same bone needs the model map (Open).

### Director

Same structure as `CameraDirector` (`0x802F4B98` state 1–6, 8), with these changes:

- **Types.** Weights are ints (`0x802F4B9C..`, not s16), sources stride `0x1C` (x, y, z, pitch, yaw, **roll**, H) at `0x8029DE44`, per-source state stride `0x3C`.
- **No enable flag** `0x800A9154`: cinematics are always on. `FUN_801CEA84` resets weights only, without the view.
- **`FUN_801D03D8`** uses each target's own z, signed mean: this fixes the PS1's target-0 z bug.
- **Blend-out.** New state 9 is a linear blend-out over the script's blend-out; PS1 state 8 cuts back. State 6 end checks use `0x80`, not `0x140`.
- **Sources 0, 1 start** at (0, −1200, −8000); PS1 y −1450.
- **Tracking** `FUN_801D0F9C`: same, except anchor rule by row `+0x16 == 0` (PS1 flag bit `0x20000000` of the row's `+0x24` word), and no bank-type-4 slot-2 height override (`0xFFFFF948`). Id `0x5D` tracks on odd frames (`0x802F4C44`, PS1 byte `'S'`).
- **Yaw spring** `FUN_801D1344`: same constants (`0xE38, 0x38E4, 0x20, 0xDDD0, 0x1AAAA, 200, 0x600, 0x300, 0x44440`). Side by negated arguments, not `+0x800` (same up to atan table rounding, `inferred`). Limit ids `0x13..0x16` (PS1 `0x27..0x2A`).

**Framing constants** `FUN_801D1AE4`, PS1 → arcade: span `0x119 → 0x189`; margin `0x30 → 0x44`; fit `0x118 → 0x188`; side `0x8C → 0xC4`; top margin `100/0x80 → 0x8C/0xB4`; denominators `0x70 → 0x9C`; lift `(y + 1000)·0x170/0x280 → ·0x200/0x280` (limit `0x1C` same); hit script distance `·H/0x2EE → ·H/0x3BB`. Same: `800, −0x1C2, 0x96, 0x4B0, 800, 0x3E9`; presets `·0x72/128`.

**Mode** `0x802F4C38` (from the stage row; PS1 `0x800A91A4`, always 0): live.

- `FUN_801D4BA0`: pitch < 0 and mode 2 → 0; mode ≠ 0 → pitch / 2.
- Hit cams and intro: modes 1, 2 height 0; intro rows with flag re-picked when mode ≠ 0.
- `FUN_801D4454`: mode 0 `r = rand & 0xFFF`; mode 1 `FUN_801C2F6C(t1)`; mode 2 `FUN_801C2F6C(t2)`, which limits the choices to the first ones (the choice-list init sets t1 and t2).
- `FUN_801A4FE8` / `FUN_801A511C`: mode 0 winner eye height −850; otherwise head − `0x122`; pitch floored at 0.
- `FUN_801D59FC`: mode 2 limits the target's y to eye + 400.
- `FUN_801D2CD0`: mode 2 refuses next-move streams.

### Tables

| PS1 | Arcade | Count | Reader | Comparison |
|---|---|---|---|---|
| Stage constants (none) | `0x8017AB04` | 14 × 5 s16 | `FUN_801D0320` | New |
| `CAMERA_PRESETS` `0x80024184` | `0x8017BE24` | 30 × 20 | `FUN_801D2F4C` family | **Identical** |
| `CAMERA_PRESET_INDEX` `0x800243DC` | `0x8017C07C` | 30 s16 | same | **Identical** |
| `HIT_CAMERA_SCRIPTS` `0x80024418` | `0x8017C0B8` | 7 × 32 | `FUN_801D5078` | Same but words 2–3 (never read in `FUN_801D5078`) |
| `HIT_CAMERA_LISTS` `0x800244F8` | `0x8017C198` | 3 × (ptr, count) | `FUN_801D4DA4` | Same weights; records `0x802044A8`.. |
| `HIT_CAMERA_ROWS` `0x80024510` | `0x8017C1B0` | 4 × 12 (int, int, int) | `FUN_801D4E88` | Lists 300–302; slots renumbered: 316 → 293, 715 → 719, 585/586 → 573/574 |
| `ATTRACT_STYLES` `0x80024528` | `0x8017C1E0` | 4 u16 | `FUN_801D67F4` | Same |
| `INTRO_OFFSETS` `0x800988E8` | `0x8017C1E8` | 10 × 14 (eye x, y, z, target x, y, z, flag at +0xC) | `FUN_801D56D4`, `FUN_801D556C` | Eye offsets **× 4/3** of PS1's; target offsets zero; flag 1 on rows 8, 9 |
| `INTRO_OFFSET_BALL` | – | | | Gone |
| `CAMERA_CHOICES` `0x80098750` + bank lists | `0x8017B410` | 215 × 12, entries 8 bytes | `FUN_801D4230`, `FUN_801D4454` | See below |
| `ATTRACT_PITCHES` `0x80098930` | `0x80204514` | 8 s32 | `FUN_801D6004` | Same in 4096 units (PS1 × 64) |
| `ATTRACT_SPEEDS` `0x80098940` | `0x80204534` | 2 s32 | same | Same in 4096 units (PS1 × 64) |
| `WINNER_*` `0x8001DF54/5C/64` | `0x80164BF4` | 3 × 4 s16 | none in the decompile | Same values; dead: style B never runs |
| `ROUND_VOICES` `0x8001A3BA` | `0x8015F4AA` | u16 | `FUN_8019DEC4` | Same |
| `RESULT_VOICES` `0x8009749A` | literals | | `FUN_8019E1F0` | Other codes |
| Bank camera streams, section 8 | `0x8017AC40` + ROM | 473 offsets | `FUN_801D3110` | New format |
| Reel lists | `0x80202DF8` → `0x8017B3A4`, `0x8017B3D4` | s16 lists | `FUN_801D3554`, `FUN_801D4100` | New location |
| Hit contact points | `0x8020450C` | ptrs | `FUN_801D4DA4` | |

**Choice lists** `0x8017B410`.

- 215 rows `{u32 entries, s16 count, s16 0x1000, s16 t1, s16 t2}`; 185 non-empty. The id is move row `+0x14` (PS1 `+0x24`); global, not per bank; id > `0xD6` → 0. Checked 4871 rows: 174 distinct ids, max 191, 4617 zero.
- Entries `{u16 flags, s16 weight, s16 script_a, s16 script_b}`; flags 0 (480), 1 (238), 0x11 (7).
- Init `FUN_801D4230` (guard `0x8021F3AC`): `t2` = cumulative raw weight at first `flags & 3 != 0`; `t1 = (cumulative << 12) / total` at first flag 0x10 (or `0x1000`); `flags & 3 == 1` with a ≠ b becomes kind 2; weights normalised.
- Selection: first entry with cumulative ≥ r; the side picks b; mirror `0x802F4C24` only for kind 1.
- No rejected ids and no practice rejection (PS1 rejects `0x19–0x2A` and mode 5).
- Id rules renumbered: cancel 9 → 3; keep `0x25` → `0x11`; preset ids `< 0x2B` → `< 0x17`; `0x4D` then not `0x4E` restarts (`FUN_801D364C`).
- Script < `0x1E` is a preset; `≥ 0x1E, < 0x232` a stream `x − 0x1D`. Examples: id 0 `(0, 100, 15, 15)`, id 1 `(0, 100, 20, 20), (0, 100, 21, 21)`, as the PS1's first entries. List refs: 960 to presets, 490 to streams, 445 distinct, max 449.

**Streams.** Offsets at `0x8017AC40` + `0x231CC28` = file offset `0x31CC28` of `prg_world_e1.bin` (end `0x393159`). `FUN_801D3110` reads a 0x40-byte buffer at a time (`FUN_801BB348`). Decoded by a script: all 472 streams end exactly at the next offset, 32–769 frames, mean 168. `confirmed` by that fit.

- First byte is the yaw mode (293 × 0, 49 × 1, 38 × 2, 39 × 3, 27 × 4, 3 × 5, formula same as PS1). Streams 450–472 (reels, 23) have no such byte. `FUN_801D3554`: reel value ≥ 0x1E → `x − 0x1D`, list values 479–500.
- Frame: u16 selector, 2 bits per channel, LSB first: 0 delta 0, 1 repeat, 2 s8, 3 s16; values accumulate.
- A reel (`FUN_801D4100`, `FUN_801D3110(id, 0, 1)`, id = script − 29): the third argument means no yaw byte at the start of the stream and weight 0x80. On starting a reel: `script_kind` = −1, `weights[2]` = 0x1000, `weights[0, 1]` = 0, `h_min` = 600, `h_max` = 2000, `stream_frame` = 0, `enabled` = 0, origin 0, `preset_yaw` = 0, `mirror` = 0, `stream_rescale` = 0, and the replay camera's flag `0x8021F3DC` off (`FUN_801D70D4` at `0x801D41E0`; its only reader is `FUN_801D6C08`, `confirmed` capstone). Each step sets the yaw 0 before `FUN_801D3D14`, so the stream is used unrotated. Reel streams 451, 455–457, 465, 468 and 469 begin with H = 0. A reel never divides by H: the rescale is off, and every stream the director plays has H ≠ 0 (`confirmed` from the converted streams). A stream of a reel ends when `eye_y + target_y >= 0` after the next sample is read (`0x8029E076 + 0x8029E07E`); then the list's next, and after the list the director. Port: `ArcadeCamera.reel_start`, `reel_step`.
- Channels into sample `0x8029E074`: 0 eye y `[1]`, 1 target y `[5]`, 2 eye x `[0]`, 3 eye z `[2]`, 4 target x `[4]`, 5 target z `[6]`, 6 H (int `+0x14`), 7 weight (int `+0x10`, 0..0x80, `w0 = w·0x20`; a reel forces 0x80).
- No frame count, no reversal, no 20/32 scale. Ends are detected by the weight: `0x802F4BD0 = −2` until 0, `−3` until `0x80`, then back to the fight.
- H is mostly 703 (398 streams) or 955 (38 reels). Weight starts at 0x80 (367) or 0 (99), ends at 0x80 (449).
- Sampler `FUN_801D3970` (disassembled): mirror negates eye z and target z; the eye is stored **relative to the target**; if `0x802F4C34 != 0`, `eye = target + rel · H / H_stream`, H = stage H; else `eye = target + rel`, H = stream H; rotate by yaw `0x802F4C00` around origin `0x802F4C10/14/18` (anchor `+8, +0xC, +0x10`); `FUN_801D05E0` → source 2.

**Intro.** `FUN_801D556C`: index from `0x8021F3C4` % 10; mode ≠ 0 skips rows with the flag; lengths `0x78` / `0x35`; the fight camera placed at the H distance. `FUN_801D56D4`: eye = source 0 + `(sin + 1)` · offset (capstone: the source is added; the decompile hides it). **Weight stays full until the last frame**: PS1 fades over the last 16.

**Winner, loser.** `FUN_801D5970` sets style `0x8021F900 = 0`; nothing ever sets it to 1. So only style A runs: `FUN_801A511C` starts at distance `H·0x1450/0x3BB + 0x5A0` (PS1 `0xF71`), `FUN_801A52A8` approaches to `H·0x1450/0x3BB` (PS1 `0x9D1`). `FUN_801A57A0` and `0x80164BF4` are dead. Loser `FUN_801D59FC`: KO eye height from `H·8000/0x3BB`, jitter `rand & 0x3F` (PS1 `(rand & 0x7F) − 0x40`); time up distance `H·7000/0x3BB + H·600/0x3BB`, approach `H/0xBF` per frame to `H·7000/0x3BB`, eye y −1200 (PS1 −1500), no bank-type 11 case.

**Replay camera.** `FUN_801D6DA8`: distance `2 · (H·0x4B840/0x9280)` (PS1 `0x2B1A`). Style `0x802A1108` toggles. Style 0: yaw `FUN_801D6BBC()`, half-turn on `rand & 1`, `−0x71C7 + r(0xE38E)`; a `rand & 1` picks sign of `25 + r(30)` degree pair. Style 1: half-turn on `rand & 1`, `−0xAAAA + r(0x15555)` (PS1 `+0x5556`). PS1 draws `rand` (result unused), r, r, r, `rand`; arcade `rand`, r, `rand`, r, r: another random sequence, and half-turns only here.

**Shake.** Same machine: `0x801FF3C4` script pointers, `s16` list ended by `−0x8000`, adds to pitch and refreshes sin/cos `0x8021FCB0/AC`. Events 1–3 → shake 0–2.

**Randoms.** `FUN_801D2E98` and `FUN_801D5078` draw `FUN_801C2F6C(0xE3)` first. `rand` is shared with the AI, so camera choices shift the AI's sequence, as on PS1.

---

## 6. Field map

### Fighter

| PS1 | Arcade | Name |
|---|---|---|
| `+0x2C` | `+2` | facing |
| `+0, +4, +8` | `+8, +0xC, +0x10` | anchor |
| `+0x12`/`+0x1E` | `+0x14` | player index |
| `+0x14` | `+0x16` | name index |
| `+0x16` | `+0x18` | bank type |
| `+0x18` | `+0x1A` | character id |
| – | `+0x1C` | voice index (s16; `0x8015FEBA` stride 0x18) |
| – | `+0x1E` | costume slot |
| dir | `+0x26` | target direction |
| `+0x44` | `+0x34` | round wins |
| `+0x46` | `+0x36` | round won |
| `+0x48` | `+0x38` | win pose |
| `+0x54` | `+0x44` | move row |
| `+0x58` | `+0x48` | frame |
| `+0x5A` | `+0x4A` | previous frame |
| state | `+0x50` | state bits (&4 crouch) |
| `+0x74` | `+0x64` | throw state |
| `+0xA0` | `+0x8C` | slot |
| – | `+0xAB` | landing flag |
| `+0xD0` | `+0xA5` | clean hit |
| `+0xDE` | `+0xAC` | KO flag |
| `+0xD3` | `+0xAE` | |
| `+0xD4` | `+0xAF` | |
| `+0xE8` | `+0xB6` | damage |
| `+0x408` | `+0xD0` | scripted input |
| `+0x19A` | `+0xE4` | |
| `+0x3F4` | `+0x33C` | health |
| `+0x3F8` | `+0x340` | max health |
| `+0x3FC` | `+0x344` | carried health |
| `+0x400` | `+0x348` | left |
| `+0xC5` | `+0x34A` | control (≥ 3 CPU, inferred) |
| ring | `+0x34C`, `+0x360` | input ring |
| `+0xF68, _, +0xF70` | `+0x44C, +0x450, +0x454` | root |
| `+0x994` | `+0x800` | head y |
| `+0x1278` | `+0x1154` | screen x |
| `+0x127A` | `+0x1156` | SZ |
| `+0x12D0` | `+0x11B0` | |

Row: `+4` flags same; camera id `+0x24` → `+0x14`; root flag `+0x16`; length `+0x18` → `+0x1E`; events `+0x20` → `+0x28`.

### Globals, round

| PS1 | Arcade | Name |
|---|---|---|
| `0x80097350` | `0x8021F0C0` | state |
| `0x80097354` | `0x8021F0C4` | counter |
| `0x80097358` | `0x8021F0C8` | replay request |
| `0x8009735C` | `0x8021F0CC` | hold |
| `0x80097360` | `0x8021F0D0` | done |
| `0x8009E9A0/A4` | `0x8021F6A8/AC` | win pose done |
| `0x80095884` | `0x8021FD88` | round frame |
| `0x80095888` | `0x8021FBEC` | previous |
| `0x800958A8` | `0x8021FC08` | rounds played |
| `0x800AE094` | `0x8021FB8C` | timer |
| `0x800AFF7C` | `0x80374F44` | clock |
| `0x800958A0` | `0x8021FC4C` | round over |
| `0x800AE340` | `0x8021FC28` | result flags |
| `0x80095894/98` | `0x8021FAE4/8` | input modes |
| `0x80095890` | `0x8021FCD0` | camera phase |
| `0x800AE404` | `0x8021FCBC` | max rounds |
| `0x800AE2C4` | `0x8021FC10` | to win |
| `0x800AE3D8` | `0x8021FCA0` | human mask |
| `0x800AE406` | `0x8021FCC0` | tie choice |
| `0x800AFF71/72/73` | `0x80374F37/38/39` | decided, winner, loser |
| `0x800AFF50` | `0x80374F18` | mode |
| `0x800AFF57/58/59/5A` | `0x80374F1C` &8/&0x10/&0x20/&0x40 | flags |
| `0x800AFF6D` | `0x80374F33` | joined mask |
| `0x800AE6DA` | `0x8021FD48` | lock |
| `0x800A9234` | `0x8021FB50` | blend hold |
| `0x800958A4` | `0x8021FB0C` | skip |
| `0x800AE39C` | `0x8021FC64` | attract |
| `0x800AFF63` | `0x8021FB70` | challenger |
| `0x800958B0` | `0x8021FD30` | pause |
| `0x800AE6C8` | `0x8021FD1C` | HUD on |
| `0x800AFF14` | `0x8021FDA4` | frame |
| `0x800A95F4` | `0x8021FB5C` | camera generator |
| `0x800AE14C` | `0x8021FBB8` | stage |
| active bytes | `0x8021FB00` | sound mask |
| `0x800AFF04` | `0x8021FD90` | fighter distance |
| `0x800AE3C0` | `0x8021FC84` | time setting |
| `0x800AFF70` | `0x80374F36` | rounds to win − 1 |
| `0x800AFF6C` | `0x80374F32` | humans |
| `0x800AFF74` | `0x80374F3C` | fight number |
| replay `0x8009C050/60/64/68/70/78` | `0x8021F640/50/54/58/60/68` | state, write, cursor, mark, skip, count |

### Globals, camera (all `0x800A....` → `0x802F....`, unless shown)

state `9138` → `4B98`; enable `913C` → `0x8021FB9C`; weights `9140..` → `4B9C..`; prev `914A` → `4BB0`; thrower `9156` → `4BC8`; side `9158` → `4BCC`; `915A` → `4BD0`; `915C` → `4BD4`; `915E` → `4BD8`; `9160` → `4BDC`; `9162` → `4BE0`; `9164` → `4BE4`; `9166` → `4BE8`; script `9168` → `4BEC`; `916C` → `4BF0`; `916E` → `4BF4`; row `9170` → `4BF8`; pitch `9174` → `4BFC`; yaw `9178` → `4C00`; roll new `4C04`; frame `9182` → `4C08`; origin `918C/90/94` → `4C10/14/18`; `917C` → `4C20`; mirror `9184` → `4C24`; H `919C` → `4C28`; Hmin `919E` → `4C2C`; Hmax `91A0` → `4C30`; scale flag `91A2` → `4C34`; stage mode `91A4` → `4C38`; `91A6` → `4C3C`; new `4C40`; `91A8` → `4C44`.

Sources `0x800A0650` (stride `0x18`) → `0x8029DE44` (`0x1C`). Per-source `0x800A06D0` (`0x30`) → `0x8029DEF8` (`0x3C`): phase `+0` same; offset `+0xC` → `+4`; speed `+0x10` → `+8`; pitch `+0x14` → `+0xC`; target `+0x18` → `+0x10`; step `+0x1C` → `+0x14`; error `+0x20` → `+0x18`; new `+0x1C`; frames `+8` → `+0x20`; moved `+2` → `+0x24`; depth `+0x24` → `+0x28`; vertical `+0x28` → `+0x2C`; horizontal `+0x2C` → `+0x30`; `+4, +6` → `+0x34, +0x38`. Lift `0x80098754` → `0x8021F3A8`. Targets `0x800AE170` → `0x80374FD8`; prev `+0x30` → `0x8036EB94`. Active camera `0x800A8A88` → `0x802C6BD4`; view matrix `0x800AE438` → `0x8036EBFC`; sin/cos pitch `0x8021FCB0/AC`.

---

## 7. Semantic differences

All `confirmed` (read on both sides) unless marked. "No change" routines are listed at the end.

| # | PS1 | Arcade | What differs | `.gd` |
|---:|---|---|---|---|
| D1 | `CameraFrameFighters`, `FUN_800661C0`, `DISTANCE 0x158D` | `FUN_801D1AE4`, `FUN_801D0320`, `0x8017AB04` | H by stage; distance from H; all framing constants of §5 | `camera_director._frame_fighters`, `_fit_horizontal`, `_fit_vertical`, `_script_lift`, `_init_sources`, consts `DISTANCE`, `SPREAD_LIMIT`, `HIT_DISTANCE_H` |
| D2 | `0x800A91A4` dead | `0x802F4C38` live | Mode rules of §5 (pitch halving, height 0, choice limit, loser target limit, stream refusal) | `_preset_start`, `_hit_camera`, `_choose`, `_intro_start`, `_loser_step` |
| D3 | `PairwiseDistances` | `FUN_8018B050`, `FUN_8018B124` | No off-screen or fixed-facing stand-in; arcade's restore when the previous distance exceeded `0x1CFF`; `dist_adj` from ids `0xB`, `0x14` | `combat.pairwise_distances` |
| D4 | `FUN_8004E55C` | `FUN_801B374C` | Bar length 210, not 152: traced `hud_bars` differ | `round_hud._bars`, `fight_hud.gd` |
| D5 | `FUN_8003D7A8`, `FUN_8003D860` | state 2 of `FUN_8019D560` | Rule at the result (see §3): human after KO stays live; CPU or time up either released or crouch word `8` | `round_flow._result_step`, `_scripted_input`, `_hold_input` |
| D6 | – | state 3 | Last fight won by a human: no replay, no poses, store; request 2 | `round_flow.step` |
| D7 | `FUN_8003AA6C` gated on not time up | `FUN_80198390` ×2 unconditional | One extra skeleton compose on time up | `_replay_done` |
| D8 | Win skip by Start | mask 3 and `0x8021FC5C`: no skip | New | `_win_wait`, `start_pressed` |
| D9 | `FUN_8003CDD8` state 1 | no infinite time | Remove the path | `round_flow.step` |
| D10 | `OgreSceneCheck` | `FUN_801B7B8C` | Mode 0 only; `0x80374F32 == 1`; lock clear; human wins > 0; no opponent-wins test | `_round_end` |
| D11 | `FUN_8003ECF4` | `FUN_8019EC80` | Mode 6 mask 3; team flag `&0x40`; no `0x800AE6E4 = 10000`; mask replaces the active bytes; loser cam gets health | `_result_camera`, `_sounds_of` |
| D12 | state 1 of `FUN_8003CDD8` | `0x8021FD48`, `FUN_801B65AC` | Decided mode 0 with the loser joined: lock and cancel joined players | `_round_wins` (flow) |
| D13 | `FUN_8002AB68` `MusicPlay` | `FUN_8019EED4` at intro frame 3 | Music start | `fight_simulation` round start |
| D14 | `FUN_8003DCE0`, `FUN_8003E158`, `FUN_8003E2F8` | `FUN_8019DEC4`, `FUN_8019E1F0`, `FUN_8019E318` | Literal codes; no mode branches; no follow-up voice; no music fade; character voice table | `round_hud._round_start_voices`, `_result_voice`, `_winner_voice` |
| D15 | Message coordinates | §4 | x, `TEMA`, new `GAME OVER`, `WIN n`, no team icons, no guard on `K.O.` | `round_hud._round_start_messages`, `_result_message`, `_winner_messages` |
| D16 | `FUN_800519B4` | `FUN_801B7C50` | Health tables and mode values; settings indices | `fight_simulation` line ~287 |
| D17 | `FUN_80068998` | `FUN_801D5970` | Style A only; distances from H | `_winner_start`, `_winner_step`, `_winner_a_*`; `_winner_b_*` dead |
| D18 | `FUN_8006879C` | `FUN_801D56D4` | Offsets × 4/3; weight stays full to the last frame (cut, no fade); ball row gone; re-pick by flag | `_intro_step`, `_intro_start` |
| D19 | `CameraChoose`, banks | `FUN_801D4454`, `0x8017B410` | One global table; ids renumbered; no rejections; `t1/t2` | `_choose`, `_kind_of`, consts `CAMERA_BYTE_*`, `FIRST_BANK_ID`, `REJECTED_*`; `tables._camera` |
| D20 | `FUN_800666E0`, section 8 | `FUN_801D3110`, §5 | New stream format; no scaling; relative eye; rescale by `H/H_stream`; 8 channels | `_stream_sample`, `_stream_view`, `_stream_start`, `_stream_bank`, `camera_reel.gd`, `motion_bake.py` |
| D21 | state 8 cut | state 9 linear | Blend-out at the end of a script | `_blend_out`, `_cinematic_start` |
| D22 | `FUN_800670E4` side (`NormalClip` of (f.x, f.z), mid, eye) | `FUN_801D35B0` | Capstone: first point is **(f0.x, f1.x)**, not (f.x, f.z). Third point is the stream eye x, z, as PS1 (decompile shows 0). This looks like an original arcade bug: reproduce | `_stream_step`, `_switch_camera` |
| D23 | `LatchButtonTaps` bug #52 ($a2 from `InputUpdate`) | `FUN_8018B710` | Reset at round frame 1, only when frame moved (`0x8021FBEC != 0x8021FD88`), bits from the ring. The slip of bug #52 is here too, with `$t0` ([#77](../code/game-bugs.md#arcade-world-ver-e1), `confirmed` by the traces) | `latch_taps` |
| D24 | `FUN_80069824` | `FUN_801D6DA8` | Distance from H, half-turn option, random order, base yaw `FUN_801D6BBC` | `replay_start` |
| D25 | `FUN_80068A44` | `FUN_801D59FC` | H-scaled distances; jitter; eye y; no bank 11; mode 2 limit | `loser_start`, `_loser_step` |
| D26 | `CameraLookPoint` bug | `FUN_801D03D8` | Target z bug fixed | `_look_point` |
| D27 | `CameraBuildView` | `FUN_801A26A4` | Y scale; roll is used at all; `OFX 256` | `view_matrix.gd` (`ASPECT`, `SCREEN_OFFSET_X`), `camera_view.gd` |
| D28 | `FUN_8003EE94` / ReplayState | `FUN_80194F94` family | Record `0x2C`; 11 slots; `REPLAY` x; storage for attract; store ignored by a remake without attract replays | `replay_state.gd` (`start`, `update`, `start_ko`) |
| D29 | `FUN_8003CDD8` pause | `0x8021FD30` zeroed each frame | No pause menu; `FUN_8018CD30` reads panel inputs `0x1F083140/42` | `pause_menu.gd` not used |
| D30 | `CameraTrackFighters` | `FUN_801D0F9C` | No bank-type-4 slot-2 height override; root flag in row `+0x16`; `0x5D` odd frames | `track` |
| D31 | Round start sources | `FUN_801D2B54` | y −1200 | `_init_sources` |

**No change** (read on both sides): `FUN_8003E608`, `FUN_8003E70C`, `FUN_8003E7C4` draw and tie rules, `FUN_8003EA98`, `FUN_8003EB60`, `FUN_8003EBF4`, carry rules (`FUN_80051AD4`: only tables moved to `0x801794FC`, `0x8017951C`), replay state machine, `CameraYawSpring` constants, `CameraBlendPair` (adds roll, H), presets, attract styles, shake machine, `FUN_80032030`, intro lengths, placement (`FUN_8018C8BC`: x ∓1000, `+0x800 = −1425`, as `FUN_8002BFCC`).

`inferred`: arcade modes 1–5 are not reachable in normal play ([flow-and-screens.md](flow-and-screens.md)). Roles of `FUN_801A4C78`, `FUN_8018AE8C`, `FUN_801B65AC`, `FUN_8018CB70`. D23's absence of bug #52.

---

## Open

- Nothing has been run. No harness check of `FUN_8018A988`, the director or the stream sampler. The stream format is confirmed by exact fit only, not by a captured frame.
- `FUN_801D3D14` not disassembled, nor the whole of `FUN_801D2CD0`; state 8/9 hold lengths read on the arcade side only.
- Does part `0xB` (arcade `+0x1154` source) match the PS1's joint `0xB` bone? Needs the model or skeleton map.
- `FUN_801A2EDC` and `FUN_801A43A4` read `+0x1154` at round start: role not settled; `0x80164BA0` table's effect is assumed nil.
- `FUN_801D6BBC`, `FUN_801D6A28`: replay base yaw not compared with PS1's axis, and the half-turn's source.
- Settings defaults (`FUN_801BBE04`, NVRAM image) not read: default rounds, time, health index and `0x8021FD3C` unknown, and thereby which display mode a stock board uses. `0x8036ECF3` unread.
- Meaning of hit script words 2–3 (`1,1` / `5,1`, against `0,0` / `5,0`): no reader found in `FUN_801D5078`; other readers not excluded.
- HUD: `FUN_801B4514`, `FUN_801B462C`, `FUN_801B46AC`, `FUN_801B46F0`, `FUN_801B437C` unread (mode line); the print layer's y halving at 240 lines is assumed; `FUN_801B3B24` blink check by wins read only for marks.
- `FUN_80043F40` (PS1, per-fighter byte `+0xD9` loop): no arcade counterpart identified.
- `FUN_801A5B00` / `FUN_801A5B68` (body-pair step, not the winner camera) and the missing `ArenaBounds` sequence belong to the [combat.md](combat.md); this report only records the order change.
- The mode ↔ `0x80374F18` names (arcade, VS, team, time attack, survival, practice, attract) are inferred from health rules, texts and `FUN_801BDDxx`; reachability is for the [flow-and-screens.md](flow-and-screens.md).
- `D3`'s `FUN_8018B124` restore and `dist_adj` ids need the [combat.md](combat.md)'s check; `+0x34A` handicap arithmetic in `FUN_8018A44C` read only there.
- The D22 argument order is read in capstone. Its effect on play (which side a preset opens on) was not measured, and whether later ROM revisions fix it was not checked.
