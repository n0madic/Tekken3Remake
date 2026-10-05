# Fight frame and round flow

`FightFrame` (`0x8002B0AC`, Japan Rev.1) advances a fight by one frame. This document lists its subsystems in call order and describes the round state machine. The individual systems are documented in [moves.md](moves.md) (branches, transitions, tracking, root motion, blending, events), [combat.md](combat.md) (collision, damage, reactions, throws), [sound.md](sound.md) and [camera.md](camera.md). The fighter record is described in [fighter.md](fighter.md).

Fighters are the records at `0x800A96F0` and `0x800AAF7C`; game modes 7 and 8 add a third record at `0x800AC808` (`g_gameMode`, `0x800AFF50`; see [modes.md](modes.md)).

## Frame sequence (normal play)

| # | Call | Role |
|---:|---|---|
| 1 | `FUN_8003EE94` | Deferred reset of effects, camera shake and replay state when a round (re)starts. |
| 2 | `ReplayUpdate` `0x800323CC` | Replay recorder/player (600-frame ring of fighter states); while a replay plays, an alternative sequence runs instead. |
| 3 | `RoundFlow` `0x8003CDD8` | [Round state machine](#round-flow). |
| 4 | `HudRoundUpdate` `0x8003D904` | Timer display, health bars, round marks, messages ([hud.md](hud.md)). |
| 5 | `CameraDirector` `0x800633C0` | Camera sources, blending and cinematic cuts ([camera.md](camera.md)). |
| 6 | `FighterUpdateSide` `0x800464CC` ×2 | `sideFlag` (left/right side, mirrors the stick) from the fighters' screen positions (`screenX`), unless `fixedFacing`. |
| 7 | `CameraShakeStep` `0x8004AFCC` | Plays the active camera-shake script. |
| 8 | `CameraFrame` `0x800484D8` | View matrix from the camera, then the stage floor ([camera.md](camera.md#floor)). |
| 9 | `FUN_800421E4` ×n | `FUN_8006AD84`: saves each fighter's anchor (`0x800A0920 + 12·index`) and copies the attack segment end points to their start points, so descriptors with `b = 0` sweep the joint's path ([combat.md](combat.md#collision-shapes)). |
| 10 | `MoveStartAll` `0x80045834` | Starts pending moves (throws first) or advances the running moves ([moves.md](moves.md#transition-codes)). |
| 11 | `PairwiseDistances` `0x8004391C` | Distance, offset and direction for every pair of fighters (`0x8009EA08`); `dist`, `distAdj`, `targetDir`; `g_fighterDistance`. |
| 12 | `FighterMovePhysics` `0x8003F330` ×n | Slides, step displacement, launches, push-back, tracking, guard state, `activeSegs`. |
| 13 | `SavePlayerPosition` `0x80046F98` | Stores the root for the body-separation split. |
| 14 | `FighterSkeletonUpdate` `0x8002BCB8` | `FighterAnimate` for active fighters: decode, blend, compose joints. |
| 15 | `ArenaBounds` `0x80043394`, `FUN_80043260`, `FUN_800432B0`, `FUN_800431D8` | Keeps fighters inside the arena (and within `0x1E00` of each other), with mode 7/8 walls and partner locking. |
| 16 | `FUN_8006DAB4`, `FUN_8006F3DC`, `EffectsUpdate` `0x8006F8A8`, `HitVibration` `0x80075CBC` | Stage background ordering table, weapon/projectile shapes for attack joints `0x18–0x1C`, particle effects, vibration for this frame's hits. |
| 17 | `FighterVelocity` `0x80040CA4` | `velX/Y/Z` = root displacement since the previous frame. |
| 18 | `CollisionShapesUpdate` `0x80042204` | Attack segments, hurt cylinders, body spheres. |
| 19 | `BodySphereProfile` `0x8003EEFC` | Applies the move's body-sphere profile (`+0x30`). |
| 20 | `FUN_80043F40`, `BodySeparate` `0x8004401C` | Clears contact flags; pushes overlapping bodies apart. |
| 21 | `HitClearSlots` `0x800442A0` | Clears the hit slots. |
| 22 | `HitTest` `0x80044304` (A→B, B→A) | Contact detection. |
| 23 | `AttackVelocity` `0x80040CF8` | `atkDir` = direction of the first attack segment. |
| 24 | `MoveBranchAll` `0x8004539C` | Per fighter (alternating order): `MoveReactionBranch` (reversals/parries). |
| 25 | `MoveEvents` `0x80045B60` ×n | Frame events of the running moves. |
| 26 | `FUN_80045260` | Clears the last-hit outcome flags. |
| 27 | `HitApply` `0x80044634` | Classification, damage, reaction record, KO. |
| 28 | `FighterSounds` `0x80041138` | Voices and sound effects ([sound.md](sound.md#fighter-sound-logic)). |
| 29 | `InputSource` `0x8002BF3C` | Next input per player: pad, CPU ([ai.md](ai.md)) or replay. |
| 30 | `LatchButtonTaps` `0x80040D68` | Latches LP, RP and LP+RP taps for branch conditions `0x3A–0x3C`. |
| 31 | `MoveStepAll` `0x80045450` → `MoveStep` `0x800454E0` | Distances, reactions to hits, KO collapse, throw pairing, branch evaluation. |

Processing of the two fighters **alternates by frame parity** in `MoveBranchAll` and `MoveStepAll` (`g_frameCounter & 1` picks who goes first).

A move selected in step 31 of frame `n` is started by step 10 of a later frame, once the running move reaches the branch's entry frame; its physics, collision and hit test then run in the same frame.

## Arena bounds

`ArenaBounds` corrects both the anchor and the root of each fighter by one vector `(dx, dy, dz)` (ported bit-exact as `arena_bounds` in [`tools/research/fight_sim.py`](../../../tools/research/fight_sim.py); the mode 8 walls are verified with `force.ovl` loaded by `verify_force_sim.py`):

- normal modes: the root is pushed back inside `|x|, |z| ≤ 300,000` (effectively endless stages). When `dist > 0x1CFF`, `d` = distance from the root to the opponent's placement point (`placedX/Z`, `+0x12C/+0x130`, saved by `FUN_800431B4` when the fighters are placed for a round; `d` via the table square root `FUN_8004B174`): if `d > 0x1E00` the fighter is pulled towards the opponent by `d − 0x1E00` along `targetDir`, else if `dist ≤ d` it is sent back to its own placement point;
- mode 7 (Tekken Ball): court `|z| ≤ 0x100`, `|x| ≤ 0x1400`; a fighter on the opponent's half (fighter 0 at `x ≥ 0`, fighter 1 at `x ≤ 0`) is pushed back to `x = 0`, and one more than 1000 units across gets `state = 0x5000`, clears its hit-done flags and sets `+0xD9`; `rootY` is kept above `−0x1200`;
- mode 8 (Tekken Force, outside game state 6 and while the round runs): side walls `z ≤ 0x8FC` and `z ≥ −0x898` (stage 18 uses the overlay floor profile `FUN_800B309C`), x limits from the overlay (`FUN_800B3020`) for the player and `|x| ≤ 0x1068` for CPU enemies.

Each component is limited to `±ramp` (`0x80097E68[index]`). `FUN_800431D8` grows the ramp every frame by an increment that itself grows by 2 per frame (`0x80097E74`), up to 2000; a mode 7 throw victim resets both to 0. When both fighters are in a throw and the link flag `0x80097E80` is set (`FUN_80043260` sets it when the number of fighters in a throw (`0x800958C4`, counted after `MoveStartAll`) changes and is at least 2, clears it below 2), the partner receives the same correction; `FUN_800432B0` (modes 7/8) also snaps a throw victim's anchor to the thrower's, dropping the link in mode 8 when the pair drifts more than `0x578` apart after frame 18.

## Round start

`FUN_8002AB68` runs from `FightMain` state 7 before every round, in this order (the remake's `FightSimulation._round_start` keeps it, since several steps draw random numbers or read state set by an earlier one):

1. Counters and flags: round frame, rounds played + 1, the timer `(option + 2) · 600` (kept between Tekken Force levels), result flags, pause, freeze and input modes cleared.
2. Mokujin (`+0x18 = 15`) picks the bank of the round from the frame generator (`FUN_8004F5C4`); holding Down on his pad selects the wooden sounds.
3. The banks are linked and merged (`FUN_80069D90`, `FUN_8006A25C`, `FUN_8006A440`, `FUN_8006A658` per fighter), the replay is initialised (`ReplayInit(2)`) and the blend modes cleared (`FUN_8003C4AC`).
4. Effects: the object pool with the eight power glows (`FUN_8006E8FC`), the stage ordering (`FUN_8006DAB4`), every voice keyed off but the announcer's (`FUN_8004B920`, keeping the music voices after the first round, [sound.md](sound.md#voice-key-off)), the saved roots (`FUN_80046F6C`), the flipbook rings (`FUN_800777AC`), the camera shake and the effect log.
5. `InputClear` for every fighter, then the placement `FUN_8002BFCC` (fighter 0 against 1, then 1 against 0; mode 7 and 8 place their own fighters).
6. `PairwiseDistances` (two fighters, three in mode 8) — after the placement, so distances, `dist`, `distAdj` and the directions start from the placed roots.
7. The camera: `FUN_800661C0` (sources and target sets) and `FUN_8006867C(0)` (the round intro's offset and base).
8. `AiInitRound`: one `rand()` per fighter and the AI generator `0x800AE168` stepped `x·5 + 3` per fighter, whether or not the fighter is CPU-controlled.
9. The HUD: the health bars emptied to refill (`FUN_8004E520`; Tekken Force: `FUN_800B30DC`) and the round wins stored for the blinking mark (`FUN_8004E868`); then the look-at state (`FUN_80039288`), `FUN_8003A140`, `FUN_8003EE88`, the Tekken Ball and practice set-ups, and `MusicPlay` of the stage's track.

## Round flow

`RoundFlow` keeps its state in `0x80097350` and a frame counter in `0x80097354`.

| State | Action |
|---:|---|
| 0 | Intro: wait 151 frames in the first round, 91 frames in later rounds, then enable control. |
| 1 | Fight: the timer (`0x800AE094`) counts down one per frame unless time is infinite. When a fighter's health reaches zero or the timer runs out (`FUN_8003E608`), the health bars are converted to fractions of 4,096 (`+0x400`), the result flags and round wins are computed, and the state advances. |
| 2 | Result pause: per-fighter result display state (`0x80095894`: 1 winner, 2 loser or KO); 90 frames after the result the sounds are stopped. |
| 3, 4 | Wait for the replay system (`FUN_80032810`), reset effects and camera shake, and set up the result sequence. |
| 5, 6 | Result sequence (replay and victory pose; `FighterStartWinPose` picks slots `0xD67–0xD6A` by the button held) for at most 300 frames; it ends early when its phase-specific condition holds or Start is pressed. |
| 8 | Tekken Force stage clear: `STAGE CLEAR!!` (font 2, colour 8, at (41, 112)) until the counter reaches 300, then state 9; the player's result display state (`0x80095894`) is set to 2 every frame. |
| 9, 10 | Hand-over to the mode code (`FUN_800514EC`). |

Timer and round settings come from the options: `timer = (option + 2) · 600` frames (20–60 seconds, shown as `(timer + 59) / 60`), rounds to win `min(5, option + 1)`, maximum rounds `2 · wins − 1`.

Result flags (`0x800AE340`):

| Bit | Meaning |
|---:|---|
| `0x01` | Time up. |
| `0x02` | KO. |
| `0x08` | Perfect: the winner's health bar is full. |
| `0x10` | Great: the winner has less than `0xCD/0x1000` (5 %) left. |
| `0x20` | Draw: equal health. |
| `0x06` with `0x20` | Double KO. |

A round won adds one to `+0x44` (round wins) and sets `+0x46` to 1 (winner) or −1. Draws give both fighters a point; on the deciding round the tie-break option (`0x800AE3D8`) decides.

## Replay

The KO replay is not a re-simulation: during the fight every frame of both fighters is recorded, and the replay plays the records back through the normal animation path.

- **Buffer** (`0x800AE330`, allocated in the fight heap): per player a ring of 300 records of `0x34` bytes (`+0x3CF0` per player, `+0x79E0` per buffer), written at index `0x8009C060` (advanced by `ReplayUpdate` state 7 every frame; `0x8009C078` counts the recorded frames).
- **Record**: `+0x00` pose move, `+0x04/+0x08` blend source/destination moves, `+0x0C` root position, `+0x18` anchor, `+0x24` root rotation angles (3 `s16`), `+0x2A/+0x2B` hand-pose variants, `+0x2C/+0x2D` blend source/destination frames, `+0x2E` pose frame, `+0x2F` blend length, `+0x30` True Ogre wing frame, `+0x31` `powerTimer`, `+0x32` another half-resolution value, `+0x33` `blendMode << 4 | blendActive`; sounds are logged separately (`ReplayRecordSound`), effect spawns through `FUN_8004A840`.
- **Wrappers**: each recorded value passes through a small function (`FUN_80032C0C` rotation, `FUN_80032838` root/anchor, `FUN_800332D8` hands, `FUN_80033158`, `FUN_80033464`, `FUN_80033600` power timer, `FUN_80032DE8`/`FUN_80032EC8` pose and blend state) that stores the value while recording and returns the recorded one during playback, so the rest of the frame code runs unchanged.
- **Playback** (`g_replayState` `0x8009C050`: 7 recording, 2 → 3 → 1 start, 1 playing, 6 playing at full speed, 4/5 finished): the play position `0x8009C064` counts half-frames modulo 600; in state 1 it advances by 1 per frame, so the replay runs at half speed and odd half-frames average the root and anchor of two consecutive records; state 6 advances by 2. `FUN_8003209C(n)` starts a replay `n` frames back (at most 298), by default 150 frames before the end, 30 in Tekken Ball; skipping (`0x8009C070`) or reaching the recording position ends it, after which blending is held for 20 frames (`0x800A9234`). `REPLAY` (colour 7, font 1) blinks at (244, 30) while playing (frame counter `0x800AFF14` bit 4), and `0x800958C8` marks playback for the other systems (effects, vibration, sounds).

## Open items

- None known.
