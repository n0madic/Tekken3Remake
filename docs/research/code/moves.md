# Move lifecycle

A fighter is always executing one **move** — a 56-byte row of its [motion bank](../formats/divmot-banks.md) that names an animation and carries combat data. This document follows a move from input to the next move: branch evaluation, the transition code that starts the new move, frame advancement, facing and tracking, root motion, motion blending and per-frame events. Field names refer to the [fighter structure](fighter.md). Addresses are Japan Rev.1.

Status: control flow and constants are `confirmed` from the decompiled code of every routine named here. `FighterRelativeAngles`, `Atan2Angle`, `TransitionRemap` and `MoveKeepsFrame` are reimplemented in [`tools/research/fight_math.py`](../../../tools/research/fight_math.py); `MoveStartOrAdvance`, `MoveBranchStep` (with `BranchCondition` and `InputMatch`) and `FighterMovePhysics` in [`tools/research/fight_sim.py`](../../../tools/research/fight_sim.py). All of them are bit-exact against the game in the [CPU harness](../tooling.md#verification-log).

| Routine | Role |
|---|---|
| `MoveBranchStep` `0x8002DC3C` | Evaluates the running move's branch list; selects the pending move. |
| `BranchFind` `0x8002E078` | First branch row whose input, window, restriction and condition match. |
| `InputMatch` `0x8002CE7C` | Command word test against the fighter's input state. |
| `BranchCondition` `0x8002E310` | Condition types `0x00–0x44`. |
| `SituationClassify` `0x800313B0` | Throw situation code for conditions `0x02–0x17`. |
| `TransitionRemap` `0x800311BC` | Adjusts the 6-bit transition code of a matched row. |
| `MoveStartOrAdvance` `0x8002F600` | Starts the pending move or advances the running one by a frame. |
| `FighterMovePhysics` `0x8003F330` | Slides, move displacement, launches, push-back, tracking. |
| `FighterAnimate` `0x8003AAD0` | Decodes root and pose, blends, composes joints. |
| `MoveEvents` `0x80045B60` | Fires the move's frame events. |

## Move row fields used at run time

| Offset | Field | Use |
|---:|---|---|
| `+0x04` | state | Copied to `state` at move start ([combat.md](combat.md#attack-levels-postures-and-guards)). |
| `+0x08` | attack | Copied to `attack`. |
| `+0x0C` | branches | Branch list. |
| `+0x10` | stance slot | Slot of the neutral move of this move's stance (3 = standing, 40 = crouching, others for lying and special stances). Used by blending mode 3 and the KO test. |
| `+0x12` | `s16` end turn | Added to `heading` when the move ends through its default continuation (for example `0x8000` for moves that finish facing away). |
| `+0x14` | damage/class | Damage (bits 0–13, plus `0x0B` events at load) and attack class (bits 14–15). |
| `+0x16` | `s16` step | Forward displacement per frame inside `[+0x19 − 1, +0x1A]` (1/256 accumulator). |
| `+0x18` | `u8` length | Animation frame count `N`; written at load from the stream's first byte. |
| `+0x19`, `+0x1A` | `u8` air window | Frames during which the fighter is airborne (`inAir`): jumps, hops. Low attacks miss a jumping fighter (state class 12) during `[+0x19, +0x1A − 5]`. |
| `+0x1B` | `u8` hold frame | Frame at which the pose freezes while `holdFrames` runs out, and the apex frame while launched. |
| `+0x24` | flags | See [flags](#move-flags-0x24). |
| `+0x28` | attack descriptor | Joint pairs of the attack segments (section 9 or one of 13 built-in descriptors at `0x80017C10`). |
| `+0x2C` | `u8` hit freeze | Freeze frames given to the defender on contact. |
| `+0x2D`, `+0x2E` | `u8` active window | First and last active frame; attack segments exist only inside it (`activeSegs`). `+0x2D = 0` means "not an attack". Tracking modes and counter-hit tests use `+0x2D` as the startup boundary. |
| `+0x32` | `u16` reaction | Reaction record for the defender ([combat.md](combat.md#reactions)). |
| `+0x34` | `u16` close reaction | Index into `0x800177DC`: alternative reaction and damage ×1.5 when the fighters are closer than the entry's distance. |

### Move flags (`+0x24`)

Tests in the code use `flags >> 8`; the table lists the bit in the 32-bit word.

| Bit | Mask | Meaning (from its users) |
|---:|---:|---|
| 8 | `0x100` | No motion blending from this move (`FUN_8003CAD0`). |
| 9 | `0x200` | No blending into the next or stance move (modes 2 and 3, `FUN_8003CC08`). |
| 10 | `0x400` | The fighter counts as "about to hit" (`aboutToHit`) during the whole move. |
| 11 | `0x800` | Sets the opponent-visible `attackAlert` for 9 frames at move start; the move cannot be parried (conditions `0x46–0x49`). |
| 12 | `0x1000` | Launch reactions add the reaction record's angle to the facing; knock-down counters are not accumulated. |
| 13 | `0x2000` | Keep a command buffer during the move (`+0x410`, see [input](#input-state)). |
| 14 | `0x4000` | Guard stance follows the stick (numpad direction of the newest history entry): back (4) gives standing guard state `0x1052`, down-back (1) crouching guard `0x2829`; for human fighters (`humanGuard`) neutral (5) and down (2) count as well. |
| 16 | `0x10000` | Power move: `powerTimer` = 120 frames whenever the move starts (all modes). In Tekken Force (mode 8) a human-controlled fighter's move also becomes an unblockable `0x607` hit for 10 damage (`forcedHit`) that costs its user 10 health on the first frame. |
| 17 | `0x20000` | Body-separation adjustment in `FUN_8003EEFC`. |
| 18 | `0x40000` | Reaction chain: `reactChain` counts consecutive moves carrying the flag (no reader in the main EXE). |
| 19 | `0x80000` | Partner move: facing and anchor are taken from the throw partner. |
| 28 | `0x10000000` | Re-anchor root motion at the current root when a move is entered from this one. |
| 29 | `0x20000000` | Camera tracking point: `CameraTrackFighters` (`0x80064944`) follows the fighter's root when the flag is set (8,753 rows) and its anchor otherwise (also the root during throws). |
| 30 | `0x40000000` | Head look-at enabled ([animation.md](../formats/animation.md#procedural-head-and-eyes)). |
| 31 | `0x80000000` | Set on 140 rows; no routine tests it. |

Bits 0–7 are the move camera byte: throw-camera id (`1–0x18`, `0x2B+`), 9 = return to the fight camera, `0x25`/`0x63`/`0x53` special throw handling and `0x27–0x2A` yaw-spring limits ([camera.md](camera.md#cinematic-cameras)).

## Input state

`InputUpdate` (`0x8002C7D4`) runs once per frame per fighter with the pad state (or CPU/replay input, see `InputSource`).

- Direction: `held & 0xF000` is matched against the 9-entry table `0x80010738 + 18·sideFlag` to give numpad direction 1–9 relative to the side the fighter stands on (5 = neutral).
- Buttons: □ → LP, △ → RP, ✕ → LK, ○ → RK (pad bits `0x80`, `0x10`, `0x40`, `0x20`). `inHeld`/`inPressed` hold the button sets as bits 0–3 (LP, RP, LK, RK); `inDir = 1 << (d + 4)`.
- History: 60-entry ring `inHistory` (`+0x41C`, index `+0x40C`) with `pressed << 4 | direction`; the raw pressed words of the same 60 frames sit at `+0x462`, and `+0x4DC..+0x4E8` count presses of each button within that window.
- Command buffer (only while a move with flag `0x2000` runs): up to 9 entries at `+0x459..+0x461` of `held << 4 | direction` (entry `count` is compared for merging); presses less than 3 frames apart merge into one entry (`+0x418` is the merge timer, `+0x410`/`+0x414` the write/read counts).

### Command words

A branch row's first `u16` is the command.

| Value | Test |
|---|---|
| `< 0xC000` | Bits 0–3 buttons, bit 4 "any", bits 5–13 allowed directions (`1 << (d + 4)`). If a direction bit is set the current direction must be one of them. Low five bits `0x10`: no button test. Bit 4: any listed button newly pressed. Otherwise at least one listed button newly pressed and **all** listed buttons held; a row with no buttons fails on a frame on which any button is pressed. |
| `0xC000` | End of list (default continuation). |
| `0xC001` | Forward double tap: history shows 6, then neutral, then 6 within 20 frames. |
| `0xC002` | Back double tap (4, neutral, 4). |
| `0xC00C` | Use common row `row[3]` from the EXE table `0x80017C78` (12-byte rows). |
| `0xC00D` | No input (condition only). |
| `0xC00E–0xC04C`, `0xC7FF–0xC827` | Motion sequences from tables `0x800958F4` (63) and `0x800959F0` (41). |

A **sequence** is `s16 window` followed by `u16` steps ending with 0; a step is `(buttons << 8) | direction` with the same button encoding as a command. The last step is tested on the current frame (like a command word); earlier steps are searched backwards through the history within `window` frames, skipping frames that do not match only if no button was pressed on them. `python3 tools/research/input_sequences.py` prints both tables; examples: `0xC015` = `5 2 3 6+LP` (quarter circle forward + LP, 25 frames), `0xC01F` = a 59-frame ten-string button chain, `0xC7FF` = `4 6 2 1 4 8 9` in 40 frames.

## Branch evaluation

Every frame without a pending move, `MoveBranchStep` calls `BranchFind(poseMove.branches, poseFrame)` (not while `stepCooldown > 25`). `BranchFind` walks the 12-byte rows (layout in [divmot-banks.md](../formats/divmot-banks.md#branch-rows-section-0-12-bytes)) and returns the first row for which

1. `InputMatch` succeeds,
2. `row.first ≤ poseFrame ≤ row.last` (`+0x09`, `+0x0A`),
3. the restriction byte `+0x02` accepts the fighter (own/opponent bank type, own character), and
4. the condition `+0x03` is 0 or `BranchCondition` succeeds (types `≥ 0x45` are skipped here).

A matched row whose flag byte is `0x2C` redirects to the list's terminator. Rows with flag `0x1C` (side steps) are skipped while `stepCooldown` is non-zero, and in mode 8 rows with flag `0x21` (throws) are skipped while the opponent is in a throw and this fighter is not. In Tekken Ball (mode 7) the default continuation may also look ahead into the next move's list from the pose frame given by the per-player byte `0x800B6B45` (volley.ovl), even outside the terminator row's window.

**Matched input row.** The target slot becomes the pending move (`moveSlot`, `moveRow`), `branchWindow = row.last − poseFrame`, `transition = TransitionRemap(flags & 0x3F)`, `transBit7`/`transBit6` from flag bits 7/6, `entryFrame = row.entry` (`+0x0B`; `0xFF` = move length; when playing backwards `row.last`), `branchKind = 2`.

**Terminator (no match).** The terminator row carries the default continuation (`+0x06`) and its own window.

- **Look-ahead.** If the frame is inside the terminator's window, or up to 5 frames before it with a button pressed this frame, the game evaluates the *continuation move's* branch list at frame 1, with the heading provisionally turned by the current move's end turn (`+0x12`). A match there becomes the pending move directly (`branchKind = 3`, `entryFrame = terminator.first`, `applyEndTurn = 1`). This is how inputs made during recovery come out on the first possible frame of the next stance.
- **Move end.** If `poseFrame + frameStep` leaves `1..N`, the continuation becomes the pending move (`branchKind = 4`, `entryFrame = poseFrame`, `applyEndTurn = 1`).

Reaction and throw paths set pending moves themselves (`branchKind = 1`, see [combat.md](combat.md)).

### Branch conditions

`BranchCondition(row, self, opponent)`; `P` is the row parameter (`+0x04`).

| Type | True when |
|---:|---|
| 0 | Always. |
| 1 | `self.contact` (own attack touched the opponent this move). |
| 2–0x13 | Throw situation code equals the type and `self.distAdj ≤ P`. |
| 0x14–0x17 | Situation code in {2, 6}, {3, 7}, {4, 8}, {5, 9} and `distAdj ≤ P`. |
| 0x18 / 0x19 | `self.dist ≤ P` / `self.dist ≥ P`. |
| 0x1A | Own contact and the opponent's guard does not cover own attack (hit, not guarded). |
| 0x1B | Opponent `guarded`. |
| 0x1C | Own `whiffed`. |
| 0x1D | Opponent's transition is not `0x21` (not throwing). |
| 0x1E / 0x21 | Opponent attacking / not attacking (`damage ≠ 0`). |
| 0x1F / 0x20 | Opponent attacking from a standing (`state & 7 = 2`) / crouching (`= 1`) posture. |
| 0x22 / 0x23 | Opponent `state & 0x407` equals 2 / 1: standing / crouching and not airborne (state bit 10). |
| 0x24 | `relAngle > 90°` (own back towards the opponent). |
| 0x25 | `headingDelta` in `[0x4E38, 0x8000)` (turned about 110°–180° to one side). |
| 0x26 | `headingDelta` in `[0x8000, 0xB1C6]` (the other side). |
| 0x27–0x2A | `facingQuadrant` = 0, 1, 3, 2. |
| 0x2B–0x2E | `oppQuadrant` = 0, 1, 3, 2. |
| 0x2F | Never. |
| 0x30 | Opponent's attack is high (`0x412`) and not past its active window, and `dist < 0x700`. |
| 0x31 / 0x32 | Knock-down recovery counters (`recoverMash`, `recoverFrames`) both zero / not both zero. |
| 0x33 | Bodies in contact: `bodyContact` (`+0xD5`), set when `BodySeparate` (`0x8004401C`) pushed this fighter this frame; `bodyContactWith[i]` records the other fighter. |
| 0x34 | Bodies in contact and the opponent is neither airborne nor down. |
| 0x35 / 0x36 | Opponent down (`state & 4`) / not down. |
| 0x37 | Opponent down, its move has no air window, and `dist ≤ P`. |
| 0x38 | Opponent down and `relAngle ≥ 90°`. |
| 0x39 | The opponent's last received hit was a counter hit (`counterHit`) and it is not airborne. |
| 0x3A–0x3C | Button taps `tapLP`, `tapRP`, `tapBoth` (`+0xE0..+0xE2`); also sets `condFlagUsed`. `LatchButtonTaps` (`0x80040D68`, once per new input frame) compares the newest history entry with the previous one (`0x8009746C[index]`): a new LP sets `tapLP`, a new RP `tapRP`, LP+RP held with either new sets `tapBoth`; a frame without a new punch clears all three. While `condFlagUsed` is set and a tap is pending the taps are frozen, so a tap read once stays visible until the next move start clears `condFlagUsed`. |
| 0x3D | Own health is zero. |
| 0x3E / 0x3F | `sideFlag` clear / set. |
| 0x40 / 0x41 | `sideFlag` clear / set and `relAngle > 90°`. |
| 0x42 | `launchArmed == 0` (not in a launch reaction) and health non-zero. |
| 0x43 / 0x44 | `powerTimer` non-zero / zero. |
| 0x45–0x4B | Only in `BranchFindReversal` — see [reversals](combat.md#reversals-and-parries). |

**Throw situation codes** (`SituationClassify`, computed once per frame per player and cached in `0x80095B88`) require that the own attack made contact, the opponent is neither airborne nor about to hit, and depend on the opponent's posture bits and on `oppQuadrant` (which side of the opponent faces this fighter):

| Opponent state | `oppQuadrant` 0 | 1 | 3 | 2 |
|---|---:|---:|---:|---:|
| bit 6 (`0x40`, standing), `relAngle < 60°` | 2 | 4 | 5 | 3 |
| bit 5 (`0x20`, crouching), `relAngle < 60°` | 6 | 8 | 9 | 7 |
| bit 7 (`0x80`, down), bit 9 clear | 10 | 12 | 13 | 11 |
| bit 7 and bit 9 | 14 | 16 | 17 | 15 |
| standing posture, own `relAngle > 120°` | 18 | — | — | 19 (quadrant 2) |

Otherwise the code is −1 and no situation condition matches.

## Transition codes

`TransitionRemap` rewrites the row's code before it is stored:

| Code | Becomes | When |
|---:|---:|---|
| 2 | `0x14` | The target move has an active window, `entryFrame + 1 < +0x2E ≤ N`. |
| 12–15 | 11 | The target move has no active window. |
| 20, 21 | 11 | Unless the target move has an active window as for code 2. |
| 25 | `0x16` | Target move has an active window as for code 2. |

`MoveStartOrAdvance` starts the pending move when the running move reaches the entry frame: going forwards when `poseFrame ≥ entryFrame` or the move has run out; backwards when `poseFrame ≤ entryFrame` or `poseFrame < 1`. The branch therefore *registers* inside the row's window but *switches* at `entryFrame`.

At every start: the previous pose frame, slot and stance slot are saved (`+0x134..+0x138`); tracking, slides, holds and per-move hit flags are reset; `damage`, `attackClass`, `state`, `attack`, `guard`, `stateClass`, `attackHi` are loaded from the row (`damageOverride` replaces the damage for reversals); `hitFreeze` takes the received freeze if the fighter was hit and is alive; a finished move with flag `0x10000` sets `powerTimer = 120`; a move with flag `0x800` sets `attackAlert = 9`; `transBit7` turns heading and facing by 180°; `applyEndTurn` adds the previous move's `+0x12`; relative angles are recomputed. Then the code selects the frames and orientation.

Terms used in the table:

- **restart** — `poseFrame = rootFrame = 1`.
- **continue** — if `MoveKeepsFrame` (not a look-ahead branch, and the new move has no active window or `poseFrame ≤ +0x2E`) both frames advance by one from the old move's frame, else restart; clamped to `N`.
- **anchor** — `pos = root` (root motion restarts from where the body is).
- **anchor if flagged** — anchor when the previous move has flag bit 28.
- **timed turn to X** — `turnFrames = max(1, +0x2D − 1)` of the new move, `turnStep = (X − heading) / turnFrames` (applied by the physics each frame).

Unless stated, `rootMove` becomes the new move.

| Code | Frames | Facing | Tracking and extras |
|---:|---|---|---|
| 0 | restart | heading = facing = direction to opponent | anchor; `throwState = 0`. |
| 1 | continue | facing = heading | mode 11; anchor. |
| 2, 3 | continue | — | mode 11; anchor. |
| 4 | pose restarts, root continues on the old root move | facing = heading; timed turn to the opponent if `relAngle < 0x4FA5` (112°) | mode 11; `holdFrames = branchWindow`. |
| 5 | as 4 | facing = heading | mode 4 if `relAngle < 0x4FA4`, else 6; `holdFrames = branchWindow`. |
| 6 | restart | facing = heading | anchor if flagged. |
| 7 | start at `N`, play backwards | facing = heading | anchor if flagged. |
| 8 | one frame back, play backwards | facing = heading | anchor. |
| 9 | restart | facing = `aimDir` | mode 5. |
| 10, 11 | restart | 10: facing = heading; 11: facing = `aimDir`; `aimDir` is re-chosen (front or back, by `relAngle < 90°`); timed turn over `+0x2D − 1` frames, or `min(16, N)` when the move has no active window | mode 11; anchor if flagged. |
| 12 / 13 / 14 | restart | facing = direction to opponent if `relAngle < 0x4FA4`, else `aimDir` | mode 4 / 3 / 2, or 6 when turned away. |
| 15 | restart | facing = `aimDir` | mode 1. |
| 16 | restart | facing = direction to opponent; timed turn | mode 11; arm slide. |
| 17 | frames unchanged | unchanged | — (swaps the move only). |
| 18 | continue | facing = direction to opponent; timed turn | mode 11; arm slide. |
| 19 | continue | heading turned 180° first, then as 18 | mode 11; arm slide. |
| 20 / 21 | continue | — | mode 4 / 2 (6 when turned away); anchor. |
| 22 | continue | — | mode 8; anchor. |
| 23 | restart | facing = heading | mode 9; anchor if flagged. |
| 24 | restart | facing = `aimDir` | mode 8. |
| 25 | continue | — | mode 8; anchor. |
| 26 / 27 | +1 without the keep test | facing = heading | `stepKind` 1 / 2 (kind 2 also counts as crouching for hit tests). |
| 28 | restart | facing = heading | mode 10 (side step); `stepCooldown = 24`; anchor if flagged. |
| 29 | continue | facing = heading | mode 10. |
| 30 | `entryFrame` | `aimDir` (+ reaction angle with flag `0x1000`) | Launch into air kind 5 ([combat.md](combat.md#launches-and-juggles)). |
| 31, 32, 45+ | restart | heading = facing = direction to opponent | — |
| 33 | restart | aligned to the throw victim | Throw attacker ([combat.md](combat.md#throws)). |
| 34 | restart | turned 180° (or partner's) | Throw victim. |
| 35 | restart | `aimDir` | Guard reaction; push-back from the reaction record; mode 7. |
| 36 | `entryFrame` | `aimDir` | Airborne hit (juggle). |
| 37 | restart | heading | Hit while down; push-back; mode 11. |
| 38 | restart | `aimDir` | Counter-hit reaction; push-back; mode 7. |
| 39–43 | restart | heading | Normal hit reactions (front, sides, back); push-back; mode 11. |

After the case: anchor if flagged (for the cases that fall through), then `poseMove = moveRow`, `curSlot = moveSlot`, the pending move is cleared, `attackSegCount` is set from the attack descriptor (2 if its third byte is non-zero, 1 if its first byte is non-zero, 0 without an active window), `moveFrame = 1` if the move changed, `curTransition` keeps the code, and `inThrow = (throwState ≠ 0)`.

## Frame advancement

When no pending move starts, `MoveStartOrAdvance` advances the running move:

1. `moveFrame += 1`.
2. **Hit freeze.** While `hitFreeze > 0` it counts down and nothing else advances; on its last frame the pose advances by one.
3. **No hold** (`holdFrames < 0`): `poseFrame += frameStep` (at least 1); while launched the pose stops at the hold frame (`+0x1B`) instead. `rootFrame = poseFrame`.
4. **Hold** (`holdFrames ≥ 0`, from transitions 4/5): at the hold frame `+0x1B` the pose stays while `holdFrames` counts down (the root keeps moving); otherwise both advance.

`stepCooldown` counts down each frame.

## Facing and tracking

`FighterRelativeAngles` (`0x80043D2C`) derives, from both roots: `targetDir` (direction to the opponent), `headingDelta = heading − targetDir`, `relAngle = |headingDelta|`, `facingQuadrant` (0 when `headingDelta + 45°` is in the first quarter, then 1, 2 = back, 3), and the mirrored values of the opponent (`oppToSelfDir`, `oppHeading`, `oppRelAngle`, `oppQuadrant`). `aimDir` (and `oppAimDir`) is whichever of `targetDir` and `targetDir + 180°` is within 90° of the heading; it is updated only while the fighters are more than `0x200` units apart. With `fixedFacing` set the direction is forced to ±90° by `fixedFacingSide`.

Each frame `FighterMovePhysics` first applies a pending timed turn (`turnFrames`, `turnStep`; facing follows while `throwState == 1`), then the move's tracking mode. `clamp(v, L)` limits to `±L`; the *budget* stops tracking once the accumulated turn (`trackAccum`) would exceed the limit, switching to mode 6. `remaining = max(1, +0x2D + 1 − poseFrame)`.

| Mode | Per-frame turn |
|---:|---|
| 0 | None; heading follows facing. |
| 1 | `clamp((aimDir − heading) / remaining, 30°)`, budget 180°. |
| 2, 3 | Towards `targetDir`: `clamp(Δ / remaining, L)`, `L` = 1° in the air, 3° for the first 8 frames, 14° afterwards (mode 3 halves it); budget 120°; becomes mode 6 at `+0x2D`. If the opponent's `attackAlert` is running and this is an attack in its first 8 frames, switches to mode 12 with a timed turn clamped to 14°/frame. |
| 4 | As 2 with `L` = 1° / 2° / 3° and budget 20°, only while no timed turn runs. |
| 5 | As 2 with `L` = 3° early / 100° after 8 frames (4° in the air), budget 210°; the same switch to a timed turn (mode 12) within the first 9 frames. |
| 6 | After the active window: every 5 frames, if `relAngle < 120°`, a timed turn towards `aimDir` over the rest of the move (at least 5 frames), clamped to 3°/frame. A grounded attack with an airborne window stops turning (`turnFrames = turnStep = 0`) once past its active window end `+0x2E`. |
| 7 | `heading += clamp((aimDir − heading)·poseFrame / W, 5°)`, `W = +0x1A` or `N`. |
| 8 | `heading += clamp((aimDir − heading)·min(moveFrame, 8) / 8, 10°)`. |
| 9 | While the fighters are more than `0x4AF` apart, turn facing towards the opponent's position at move start, clamped to 8°. |
| 10 | Side step: `facing = aimDir ± 25°·poseFrame / N`, the sign from the root displacement `rootDx` (±10° for character 7 when back-turned). |
| 11, 12 | No automatic tracking (only the timed turn). |

## Displacement and slides

- **Step displacement.** While not ballistic (or frozen in a hit by a bank-type `0xE` opponent), inside `[+0x19 − 1, +0x1A]` with `+0x19 ≠ 0`, each frame adds `(+0x16 · sin(facing)) / 0x7FFF` and `(+0x16 · cos(facing)) / 0x7FFF` to per-player 24.8 accumulators (`0x8009E9A8`/`0x8009E9B8`, index = fighter `index`), subtracts `accumulator >> 8` from `posX`/`posZ`, and keeps the sub-unit remainder in the accumulator. The displacement is therefore `+0x16 / 256` units per frame, opposite to the `facing` vector.
- **Slides** (transitions 16, 18, 19): when `poseFrame` reaches `rootMove + 0x19`, the distance `min(g_fighterDistance − 500, 0xA0C)` is divided over the frames up to `+0x1A` and added to the anchor along `targetDir` each frame (`slideStepX/Z`); at `+0x1A` the anchor snaps to the root. Used by dashing attacks that close the distance to the opponent.
- **Slide to point** (`slideToPoint == 1`): once, `pushDir = atan2(rootZ − slideTargetZ, rootX − slideTargetX)`, `pushFrames = 16`, `pushSpeed = dist / 16`, and the anchor is set to the root minus `dist` along `pushDir + 180°`; the push-back then carries it over 16 frames. The code only clears and reads the flag; no writer of 1 exists in any JP program.
- **Push.** Each frame the push amount is `pushSpeed` while `pushFrames > 0` (counting down), plus the next `s16` of `pushTable` while `pushTableFrames > 0`, plus `pushRepeat · 40 + 10` when `pushRepeat > 0` (repeated hits on a guarding opponent). The anchor moves by that amount along `pushDir`.
- **Ballistic flight** is described in [combat.md](combat.md#launches-and-juggles). Character `0x11` (Gon) in a reaction and not juggled keeps `posY = 0` on the ground and `posY = (rootY + 0x80) / 2` in the air when negative.
- **Push-back and launches** are described in [combat.md](combat.md#push-back).

## Per-frame bookkeeping in `FighterMovePhysics`

After tracking, in this order:

1. `attackAlert` and `hitCooldown` count down to 0.
2. `activeSegs` = 0 outside `[+0x2D, +0x2E]`, else 2 if the attack descriptor's third byte is non-zero, else 1.
3. `forcedHit = 0`; in mode 8 a CPU enemy thrown (`throwState < 0`) between frame 11 and the move end hits others when its speed `isqrt(velX² + velY² + velZ²) > 0x59` (attack `0x607`, `attackHi = 6`, damage `speed / 16 + 10`), and a human fighter's power move (flag 16) does the same with damage 10.
4. `inAir = 1` while juggled or inside `[+0x19, +0x1A]`.
5. At `poseFrame == +0x1A` of a move without hold, not at frame 1 and not sliding (`airPhase ≠ 2`): `landedA` for a move that was not hit, air kind 5, or a state that is neither class 9 nor down (bit 2); else `landedB` (a knocked-down landing).
6. `recoverFrames` counts down (0 on a clean hit); below 31 `recoverMash` drops by 1, 2 (any button) or 4 (RP) per frame ([combat.md](combat.md#knock-down-recovery)).
7. `aboutToHit` = damage move within `[+0x2D − 3, +0x2D]` (from frame 1 when `+0x2D < 3`), flag 10, or character `0x11` (Gon) against any other character.
8. Guard stance (flag 14 or a side step, see the flag table); without flag 14 a side step takes the move's own state, dropping the guard bits of a state with bit 8 for CPU fighters. `guard = state & 0x18` only on the ground with `relAngle < 90°`, else 0. A class-9 state (thrown into the air by a hit) becomes down (bit 2) from the air-window start (`FUN_80040C04`).
9. Hand/face shape (`HandFaceCommand`, rate 10): on a clean hit the per-costume table `0x80095DA8`; otherwise, unless `+0xBC` is set, the table `0x80095D74` within 8 frames before the active window of a damage move, and at the start of a non-damage move outside reactions while `0x80097350` is 1 or 2. Character `0x14` (True Ogre) animates a single value `+0x1296` towards 0 or `0x100` instead of two hands.
10. `+0x12D0` = hit-frozen by a bank-type `0xE` opponent; `+0x128A` = airborne outside reactions.
11. `powerTimer` counts down while neither fighter has a clean hit, clearing the guard bits; it is zeroed on a clean hit.
12. `pushRepeatTimer` counts down (0 in the air); `pushRepeat` resets when it reaches 0.
13. Mode 8: `+0xC9` = CPU or fixed facing.
14. `landedB` of an active fighter spawns the landing dust effect at the root (`FUN_8004AC28`, 3-slot ring at `0x8009EBF8`, plus a floor mark through `FUN_8004A700`) and starts camera shake 0 ([camera.md](camera.md#camera-shake)).

## Root motion

`FighterAnimate` decodes the root displacement of `rootMove` at `rootFrame − 1` (channels 0–2, scaled by the model scale `+0x4EE`, [animation.md](../formats/animation.md)) and the pose of `poseMove` at `poseFrame − 1`. `RootReanchor` (`0x8003AC1C`) runs first: when `anchorDirty` is set it clears it and moves the anchor so that `anchor + displacement(rootFrame − frameStep − 1)` equals the current root, so switching `rootMove` does not make the body jump. `RootUpdate` (`0x8003AD48`) then builds the root rotation from `(−tiltX, heading − 0x8000, −tiltZ)` (`FUN_8003A6B4`, `Rx·Ry·Rz`) and sets

```text
a = (0x8000 − facing) >> 4                       # 4096-entry tables
rootX = posX + (dx·cos[a] − dz·sin[a]) / 4096     # when airPhase == 0 (truncating division)
rootY = posY + dy'                                 # when airPhase is 0 or 2
rootZ = posZ + (dx·sin[a] + dz·cos[a]) / 4096     # when airPhase == 0
```

where `dy'` is the vertical displacement plus the blended root delta (below). `airPhase = 1` (launched) leaves the root at the anchor. Both routines are ported bit-exact (`root_reanchor`, `root_update` in [`tools/research/fight_sim.py`](../../../tools/research/fight_sim.py)).

## Motion blending

`FighterTransitionBlend` (`0x8003C4C4`) smooths pose changes by storing, for local matrix slots 1–17, the difference between two poses (`blendDelta`, 9 rotation terms each) and the root displacement difference (`blendRootDelta`). `RootUpdate` sets `blendWeight = 4096 · blendCounter / blendFrames` (4096 without blending) and adds `blendRootDelta.y · weight / 4096` to the vertical displacement; `FighterComposeJoints` adds `sat16(weight · delta >> 12)` to each freshly built local rotation (`MatrixAddScaled`) and re-orthonormalises it (`MatrixOrthonormalize`, Gram–Schmidt on the first two columns with the game's reciprocal-square-root table `0x8001A194`, third column their cross product). The blended rotations are also stored as `prevLocalMats` for the next decay blend — and they are the matrices from which the collision shapes are built. All of it is ported bit-exact (`transition_blend`, `matrix_add_scaled`, `matrix_orthonormalize` in `fight_sim.py`).

| Mode | Starts when | Delta | Weight over time |
|---:|---|---|---|
| 1 | The move changed (`moveChanged`) and it is not a restart of the same move; length = frames left to the active window (≤ 16) or 4 (16 while thrown), limited by the frames left in the move, 0 if below 2 | previous displayed pose − new move's first pose | counter starts at `frames − 1` and counts down (the old pose fades out). |
| 2 | A pending move waits for its entry frame (`poseFrame < entryFrame`, not look-ahead): `entryFrame − poseFrame + 1` frames | new move at its entry frame − running move at its frame | counts up to `frames` (fades in the next move). |
| 3 | No pending move and fewer than 16 frames left: `N − poseFrame + 1` frames | stance move (`+0x10`) frame 0 − running move's last frame | counts up. |

The decay blend (mode 1) is not started while the running move has flag `0x100`, `+0xBA` is set or `+0x89/+0x8A` are non-zero; the forward blends (modes 2 and 3) are not started while the move has flag `0x200`, `+0xBB` or `transBit6` is set, the fighter is juggled, or it is airborne with `+0x87` set. Mode 3 uses `poseFrame` frames instead when the move plays backwards. Nothing is started for `0x800A9234` frames after a request (a countdown) and none during replay rendering (`0x8009588C`, `0x800958B8`); during replay playback (`0x800958C8`) the recorded source/destination are reused.

## Frame events

`MoveEvents` (`0x80045B60`) runs the running move's event list (section 4 of the bank): `(u16 frame, u16 command)` pairs up to `frame = 0`. It first clears `extraKind`, then does nothing for an inactive fighter. An event fires on the frame at which `poseFrame` passes its frame (`prevPoseFrame (+0x5A) < frame ≤ poseFrame`). `hi` and `lo` are the command bytes.

| `hi` | Action |
|---:|---|
| 1, 2, 3 | Camera shake script 0, 1, 2 (`0x80097EC8`) with a pulse on both pads. |
| 4 | Ground impact at the root: dust effect (`FUN_8004AF1C`) and pad vibration pattern 2. |
| 6 | Effect at joint `lo` (`FUN_80076E58`, owned by this fighter) and pad vibration pattern 1. |
| 7 | Effect at joint `lo` owned by `+0x1F`. |
| 8, 9, 10 | Spark effects 0, 1, 3 at joint `lo` (`FUN_80076EB8`). |
| 11 | Throw damage `lo` delivered by this fighter (`extraKind = 1`; also added to the move's damage at load). |
| 12, 13 | Damage exchange modes 2/3 with value `lo` (`HitExtraDamage`). |
| 14–61 | Hand shape and face commands (they also set `+0xBC`): `cmd = hi − 14`; hands `cmd >> 4` (1 left, 2 right, 0 = both), shape `cmd & 7`, speed `lo` unsigned (blend over `lo + 1` frames). `hi = 20` resets both hands; `hi = 21` selects the costume's face variant (`0x80095D74`), which swaps face texture rectangles in VRAM. |

Joint `lo` is a matrix block of the fighter (`+0x8F4 + 0x44·lo`, translation at `+0x14`). The hand shapes are the 41 vertex variants of the hand parts ([3dmk-models.md](../formats/3dmk-models.md)).

`move_events` in `tools/research/fight_sim.py` ports the routine (effects and vibration are returned as events); `verify_fight_sim.py` checks it against the game.

## Open items

- None known for the move system.

