# Combat systems

This document covers everything between two fighters' bodies: attack and guard encoding, collision shapes, contact, damage, reactions, push-back, launches and juggles, knock-down recovery, throws, reversals and body separation. Field names refer to the [fighter structure](fighter.md), move fields to [moves.md](moves.md#move-row-fields-used-at-run-time). Addresses are Japan Rev.1.

Status: `confirmed` from the decompiled code of every routine named; constants read from the EXE. The damage formula (`HitDamage` with the zone table) and `LaunchTrajectory` are reimplemented in [`tools/research/fight_math.py`](../../../tools/research/fight_math.py) and bit-exact against the game in the harness; `HitClassify`, `HitTest`, `HitApply`, `CollisionShapesUpdate` and the other fight routines are ported in [`tools/research/fight_sim.py`](../../../tools/research/fight_sim.py), also bit-exact ([tooling.md](../tooling.md#verification-log)).

## Attack levels, postures and guards

The move's `state` word (`+0x04`) and `attack` word (`+0x08`) are copied to the fighter at move start.

| Bits | `state` | `attack` |
|---|---|---|
| 0–2 | Posture: 1 crouching, 2 standing, 4 down (lying) | Postures the attack can hit |
| 3–4 | Guard the fighter holds: `0x08` crouching guard, `0x10` standing guard | Guards that block the attack |
| 5–7 | Throw targeting: `0x20` crouching, `0x40` standing, `0x80` down (with `0x200` lying the other way) | — |
| 8 | Guard kept only for human-controlled fighters (`humanGuard`) | — |
| 10 | Airborne body (reduced damage, air reactions) | — |
| 11–15 | State class (`stateClass`; 12 = jump) | — |
| high byte | — | Level id (`attackHi`) |

State classes in the 22 distinct banks (row counts summed over the banks; the state word is the most common one of the class):

| Class | State word | Rows | Use |
|---:|---|---:|---|
| 1 | `0x842` | 7,091 | Standing moves and attacks. |
| 2 | `0x1052` | 266 | Standing guard (also forced by the stick, move flag 14). |
| 3 | `0x1952` | 66 | Standing stance (slot 3): guard for humans only (bit 8). |
| 4 | `0x2021` | 389 | Crouching moves. |
| 5 | `0x2829` | 160 | Crouching guard. |
| 6 | `0x3129` | 142 | Crouching stance (slot 40). |
| 7 | `0x3884` | 692 | Down (lying) moves, knock-downs, get-ups. |
| 8 | `0x4284` | 76 | Down variant (14 banks). |
| 9 | `0x4C02` | 458 | Launched hit reactions: airborne body; the physics turns on "down" (bit 2) from the air-window start and lands with `landedB`. |
| 10 | `0x5000` | 35 | No posture: cannot be hit by any attack word; also forced by Tekken Ball court crossing. |
| 12 | `0x6042` | 158 | Jumps. |

The common attack words decode as:

| `attack` | Hits | Blocked by | Kind |
|---|---|---|---|
| `0x412` | standing | standing guard | high (ducked by crouching) |
| `0x217` | all postures | standing guard | mid |
| `0x10F` | all postures | crouching guard | low |
| `0x607` | all postures | nothing | unblockable / ground hit |
| `0x800` | none | — | throw attempt (connects only through the throw system) |

The standing stance has `state = 0x842`. `guard` is recomputed every frame by the physics: it is the state's guard bits only while the fighter is on the ground (`inAir = 0`) and faces the opponent within 90° (`relAngle < 0x4000`), and it is cleared while `powerTimer` runs. A move with flag `0x4000` takes its guard state from the stick (4 → `0x1052`, standing guard; 1 → `0x2829`, crouching guard).

## Collision shapes

`CollisionShapesUpdate` (`0x80042204`) rebuilds the shapes from the world joint matrices (`joints`, 24 blocks of `0x44` bytes, translation at `+0x14`) every frame.

**Attack segments** (`attackSegs`, 24 bytes each: start point at `+0x1AC + 0x18·k`, end point 12 bytes later). `activeSegs` is 1, or 2 when the second pair is used. They come from two sources.

- **Inside the active window `[+0x2D, +0x2E]`** they are read from the move's attack record (`FUN_8006A6A4`), not from the skeleton. The record holds, for every active frame, baked points relative to the move anchor (`posX/Y/Z`) in the fighter's heading frame ([divmot-banks.md](../formats/divmot-banks.md#attack-records-section-9)). A point is placed as `anchor + rotate(point, −heading)`. While the body heading differs from `facing` (a turning move), the anchor is first swung about the root by that difference (`FUN_8006A518`). The layout kind decides which ends are baked and which are *swept*: a swept start is the previous frame's end point (saved by `FighterSavePrevSegments`, fight frame step 9). On the first active frame it is the baked point before it, placed at the previous frame's anchor. A swept segment therefore tests the path the striking point travelled during the last frame. Characters 14 and 15 (Ogre, Mokujin) use the record's alternative point block (`0x800A0950 = 1`, `FUN_8006A658`).
- **Outside the window** `CollisionShapesUpdate` copies joint positions. The descriptor's joint pairs `(a0, b0, a1, b1)` give the end (joint `a`) and, when `b ≠ 0`, the start (joint `b`); joint `0x13` means joint 6 for character 14, and joints `≥ 0x18` are skipped. Before that it computes the weapon points into spare joint slots: Yoshimitsu's sword (bank 4, joint 10 × `(100, −720, 0)` and `(100, −360, 0)` into joints 18 and 19), True Ogre (bank 14, character 20: joint 11 × `(100, −500, 0)` into 22, joint 2 × `(800, 0, 600)` into 23) and Gon (bank 19: joint 11 × `(200, 900, 0)` into 21, joint 2 × `(400, 0, 100)` into 23). Each point is joint matrix × point `>> 12` plus the joint translation. Only the world translation (`+0x14`) of those blocks changes: the parts are drawn with each block's second matrix (`+0x20`), built when the joints were composed, so Mokujin's stick (attachment 18, which he shows with Yoshimitsu's bank) stays in his hand (confirmed in the harness: a write watch on block 18).

Projectile descriptors (first joint `≥ 0x18`) take their segments from the effect buffer (`FUN_8006E804`, see [Contact](#contact)).

`collision_shapes_update` and `attack_segments_baked` in `tools/research/fight_sim.py` port both paths, the hurt cylinders and the body spheres; `verify_fight_sim.py` checks them against the game with random joint matrices and random attack records (all layout kinds, both point blocks, turning moves).

**Hurt cylinders** (`hurtZones`, 14 × 20 bytes: centre, radius, radius²). Vertical cylinders centred on joints, rebuilt every frame (`+0x3A4` keeps a copy of zone 0's centre); radii per character from `g_hurtRadiusByChar` (`0x80097414`), four 14-entry profiles; characters 11, 16, 17 and 20 use the larger profiles.

| Zone | Joint slot | Body part | Damage % | Radius (standard / large) |
|---:|---:|---|---:|---|
| 0, 1 | 17, 14 | feet | 90 | 200 / 300 |
| 2, 3 | 10, 6 | hands | 90 | 120 / 200 |
| 4, 5 | 16, 13 | shins | 100 | 300 / 450 |
| 6, 7 | 9, 5 | forearms | 120 | 100 / 150 |
| 8 | 2 | head (centre 120 lower) | 130 | 250 / 450 (400 or 675 for two IDs) |
| 9, 10 | 8, 4 | upper arms | 100 | 300 / 450 |
| 11 | 0 | waist (centre 60 lower) | 140 | 200 / 400 |
| 12, 13 | 15, 12 | thighs | 125 | 400 / 600 |

**Body spheres** (`bodyPoints`, 8 × 16 bytes: centre, radius) on joints 2, 9, 5, 0, 16, 13, 17, 14 (head, forearms, waist, shins, feet; table `0x80097364`). Radii from `0x80097384` by character: `(240, 96, 96, 300, 120, 120, 120, 120)`; characters 11 and 16 use a 300/375 head/waist, character 20 480/375. The move's `+0x30` word adjusts them (`FUN_8003EEFC`):

| `+0x30 & 0xF` | Radii |
|---:|---|
| 0 | Normal; bits 4–11 disable individual spheres, during the active window only if bit 12 is set. |
| 1 | Head and waist only. |
| 2 | All radius 1. |
| 3 | All halved. |
| 4 | All zero. |
| 5 | Head and waist halved, others 1. |
| 7 | All +100. |
| other | Normal. |

Attacking moves drop the forearm spheres; airborne or hit moves with flag `0x20000` drop further spheres.

## Contact

`HitTest(attacker, defender)` (`0x80044304`) runs for both directions after `HitClearSlots`. The defender has two 44-byte hit slots (`hitSlots`, one per possible attacker). A contact needs:

- a free slot (the second one is preferred); neither fighter `invulnerable`, both `active`;
- the attack has not already touched this defender (`hitDone0/1`);
- the defender is not in its `hitCooldown`;
- not a low attack (`0x10F`) against a jumping defender (`stateClass 12`) that is inside `[+0x19, +0x1A − 5]` of its move or airborne;
- a segment–cylinder intersection (`HitTestSegments` → `SegmentHitsCylinder`, ported bit-exact as `segment_hits_cylinder` in `fight_math.py`): reject by bounding box, clip the segment to the cylinder's height `[cy − r, cy + r]`, then compare the horizontal `(x, z)` distance from the centre to the clipped segment with `r`;
- `attack & defender.state & 7 ≠ 0` (the attack can hit the defender's posture); while the defender's `stepKind` is 2 the attack also hits the crouching posture.

A thrown body (`forcedHit`, set only in Tekken Force) hits a CPU fighter it is touching (`bodyContactWith`) without the geometry test: the slot gets the defender's root and half the root offset, and sound `0x4951` plays. In modes 7 and 8 a defender inside a throw cannot be hit.

On contact the slot stores the segment's end point, the segment vector (end − start, 16-bit), the cylinder index and the attacker index, and is marked used; the attacker sets `hitDone`, `contact`, `contactThisMove`, `lastHitTarget`; the defender sets `gotHit`, `wasHitThisMove` and receives `hitFreezeIn = attacker move +0x2C` (30 for slot `0x898`), and `hitCooldown = 4` if the attack deals damage or the defender is airborne. If the attacker's pose reaches `+0x2E` without contact, `whiffed` is set.

`hit_test` and `hit_test_segments` in `tools/research/fight_sim.py` port both routines; `verify_fight_sim.py` checks them against the game (including projectile segments from the effect buffer).

## Classification and damage

`HitApply` (`0x80044634`) runs after the move branches. For each used slot, `HitClassify` then `HitDamage`:

| Slot flag | Condition |
|---|---|
| `+0x28` no damage | `attacker.damage == 0`. |
| `+0x26` close | Move `+0x34 ≠ 0` and `g_fighterDistance` (the distance between the fighters) is below the entry's threshold in `g_closeReactions` (`0x800177DC`: `s16 reaction, s16 distance`). |
| `+0x22` guarded | `defender.guard & attacker.attack ≠ 0` and `defender.relAngle ≤ 90°`. |
| `+0x23` chip | Guarded, and chip is enabled globally (`0x800AFF20`) or the attacker's `powerTimer` runs. |
| `+0x24` hit | Not guarded. |
| `+0x25` counter hit | Hit, and the defender is in the startup of its own attack (`damage ≠ 0`, `poseFrame < +0x2D`) or either fighter's `powerTimer` runs. |
| `+0x27` airborne | Hit, and the defender is `inAir` or its state has bit 10. |

```text
base = attacker.damage
if guarded:     d = chip ? base / 10 + 2 : 0
else:
    d = close ? base + base / 2 : base * zone_percent[zone] / 100
    if counter hit:
        e = |defender.damage| * 3 / 10
        if neither powerTimer runs:
            W = defender move +0x2D (or poseFrame when 0 or already passed)
            e = (e * 3 / 10) * defender.poseFrame / W
        d = e + d * 12 / 10
    if airborne:  d = juggleCount == 0 ? d * 80 / 100 : d / 2
slot.base_damage = attacker.damage          # +0x1C
slot.damage += d                             # +0x1E
```

`HitExtraDamage` adds the throw and exchange terms from move events 11–13 (`extraKind`, `extraDamage`): kind 2 adds the value (or the own damage), kind 3 subtracts it, and a throw victim (`throwState < 0`) takes the partner's kind-1 value. Health (`health`, 16.16 fixed point) loses `(extra + Σ slot damage) << 16`, clamped to `[0, healthMax]` (not in the no-damage debug modes `0x800958A0`/`0x800958D8`; not from fighters other than 2 in mode 7). Reaching zero sets `ko`; a KO by chip damage (best slot `+0x23`) is turned into a clean hit (`guarded = 0`, `hitClean = 1`). `HitApply` stores the extra term in `+0xCC`.

`HitBestSlot` picks the more severe of the two slots into `bestHitSlot`: each slot's score is the sum of the weights of its flags (no damage 1, guarded 2, chip 3, close 4, hit 5, counter 6, airborne 7); the second slot wins on a higher score, or on an equal score with more damage. and `HitCopySlotFlags` copies its outcome into `lastDamage`, `closeHit`, `guarded`, `hitClean`, `counterHit` and `lastAttacker`. `HitSpawnEffect` then spawns the guard or hit spark and sound (`FUN_80076EB8`, `FUN_80076F10`).

`hit_apply` in `tools/research/fight_sim.py` ports `HitApply` with `HitExtraDamage`, `HitDamage`, `HitBestSlot` and `HitCopySlotFlags`, and reports the effect spawn and the KO start as events. `verify_fight_sim.py` checks it against the game in modes 0, 5, 7 and 8.

## Reactions

The defender's reaction record (`reaction`, 42 bytes) is chosen in `HitApply`:

- `forcedHitIn` (hit by a forced/self-inflicted hit): the fixed record `0x8001DEC0`;
- `closeHit`: from the close entry of move `+0x34`;
- otherwise move `+0x32`: values below `0x1000` index `g_reactionRecords` (`0x80010CE8`, 633 records); values `0x1xxx` point at entry `n = value & 0xFFF` of the flat `s16` array `g_throwVictimSlots` (`0x800174C4`, the victim moves of throws): the reaction pointer is `&slots[n]`, so only its first field is meaningful and a throw's victim move is `slots[n]` (transition `0x22`).

Record layout (`s16` fields):

| Offset | Content |
|---:|---|
| `+0x00`, `+0x02` | Front hit: standing, crouching reaction slot |
| `+0x04`, `+0x06` | Counter hit: standing, crouching |
| `+0x08`, `+0x0A` | Hit from side 1 |
| `+0x0C`, `+0x0E` | Hit from side 3 |
| `+0x10`, `+0x12` | Hit in the back |
| `+0x14`, `+0x16` | Guard: standing, crouching |
| `+0x18` | Hit while down |
| `+0x1A` | Hit while down, other orientation (state `0x200`) |
| `+0x1C` | Push-back angle offset |
| `+0x1E` | Push table index for hits |
| `+0x20` | Angle-like `s16` (0, ±30°, ±45°, ±60°, 90°, …; 168 of 633 records non-zero) that no routine reads — apparently an unused counter-hit push angle (counter hits use `+0x1C`). |
| `+0x22` | Push table index for counter hits |
| `+0x24` | Push angle for hits while down |
| `+0x26` | Push table index for hits while down |
| `+0x28` | Push table index for guard |

`MoveStep` (`0x800454E0`) applies the reaction when the fighter `gotHit`, depending on the attacker's `attackClass` (move `+0x14` bits 14–15): classes 0 and 1 always react, class 2 only when the defender is on its feet and not airborne, class 3 never (damage only). `HitSelectReaction` (`0x8002EDF8`) then picks, in order:

1. guarded → guard slot (standing/crouching by `state & 2`), transition `0x23`;
2. airborne (`inAir` or state bit 10) → launch, transition `0x24`, air kind from `AirReactionKind`;
3. down (state `0x200` or `4`) → `+0x1A` / `+0x18`, transition `0x25`;
4. counter hit → `+0x04/+0x06`, transition `0x26`;
5. by `facingQuadrant`: 0 → `+0x00/+0x02` (transition `0x2A`), 1 → `+0x08/+0x0A` (`0x27`), 2 → `+0x10/+0x12` (`0x2B`), 3 → `+0x0C/+0x0E` (`0x28`).

The reaction starts on the next move start with `entryFrame = poseFrame` and `branchKind = 1`; `hitFreeze` holds it for the attacker's freeze frames first. A KO'd fighter whose running move is a basic stance (stance slot 3 or 40) or who is standing without an air window goes to the collapse move `0xD66` (`FUN_8002DA80`).

## Push-back

Hit reactions push the defender along `pushDir = direction to the attacker + record angle + 180°` (`aimDir` instead of the direction for code `0x2A`). A push table entry in `g_pushTables` (`0x8001075C`, `s16` index) is `frames, speed, off[8]`: for `pushFrames` frames the anchor moves by `pushSpeed`, and for 8 frames by the next table value, plus `40·pushRepeat + 10` when `pushRepeat > 0`. `PushRepeatCount` increments `pushRepeat` when the same side reaction repeats within `N + 10` frames of the previous one, so repeated hits push further.

## Launches and juggles

A hit on an airborne defender (transition `0x24`) or a launching reaction (transition `0x1E`, air kind 5) makes the fighter ballistic (`ballistic = 1`, `airPhase = 1`, `juggleCount += 1`).

`AirReactionKind` (`0x8002F0E8`) selects the kind; the kind row of `g_airKinds` (`0x8001A630`) gives the ground offset and the air move slot:

| Kind | Ground offset | Slot | When |
|---:|---:|---:|---|
| 0 | 440 | `0xD56` | Default (front, back); also when already in kind 2 but higher than `0x400`. |
| 1 | 550 | `0xD61` | Downward hit (`hitDirY > 0x6D`) or two special attacker moves: fixed downward speed 400, entry frame 6 (slam). |
| 2 | 204 | `0xD62` | Already in kind 2, or late in kinds 3/4 (after frame 18). |
| 3 | 436 | `0xD63` | Hit from side 3. |
| 4 | 436 | `0xD64` | Hit from side 1. |
| 5 | 1357 | `0xD57` | Launch reaction (transition `0x1E`). |

`LaunchTrajectory` (`0x8002F2C8`):

```text
H  = hold frame of the air move (+0x1B), or the running move length
airSpeed = clamp(lastDamage + 7·(juggleCount + 1) + 10 (+10 for kind 5), 0, 100)
v  = clamp(4·lastDamage − ((velY + hitDirY) >> 3) − (7·juggleCount − 40), −100, 100)
airVelY = −v                                   # up is negative
t  = max(1, (v + isqrt(|v² + 12·(groundOffset + rootY)|)) / 6)
entry frame and t are adjusted so that the air move's hold frame is reached at landing
n  = t + 1
if v·n − 3·n² − rootY < groundOffset:  airVelY = −(groundOffset + rootY + 3·n²) / n
push: table 0x80019D2C for 8 frames along direction to the opponent + 180°
```

The routine computes in 32-bit C ints and divides `v + isqrt(…)` as an **unsigned** value: when a hit catches a fighter below the landing height the sum is negative, `t` becomes huge and the wrapped arithmetic that follows decides the entry frame and speed — a port must reproduce this (`launch_trajectory` in `fight_math.py`).

Each juggle hit therefore launches lower (−7 per previous hit) and farther (+7). While ballistic the physics adds gravity (`airVelY += 6` per frame), moves the anchor by the air velocity with horizontal speed `airSpeed` away from the opponent, and lands when `airVelY > 0` and `posY ≥ −groundOffset`: position snaps to the root, `airPhase = 2`, `ballistic = 0`, and `landedA` (kind 5) or `landedB` is set for the branch conditions. Air kind 1 starts camera shake 1 on landing (`FUN_8004AF94`, which also pulses the pad through `VibrateAll` except during replay playback, `0x800958C8`); every `landedB` of an active fighter adds the landing dust effect and camera shake 0.

Damage to an airborne defender is scaled (80 % for the first air hit, then 50 %).

## Knock-down recovery

Reaction transitions `0x24–0x2B` set two counters: `recoverFrames` = the reaction move's length, and `recoverMash = min(66, lastDamage + recoverMash / 2)` (0 with flag `0x1000`). After a throw (`0x22`) they are set from the thrower's move: `recoverFrames` from the partner's length or hold frame, `recoverMash = clamp(damage·32/45 + 34, 34, 66)`. Each frame `recoverFrames` counts down; once it is below 31, `recoverMash` drops by 1 per frame, by 1 more if any button was pressed and by 3 if RP was pressed. Branch conditions `0x31`/`0x32` test whether both have reached zero, so button presses shorten the time spent down before get-up options open.

## Throws

A throw is an ordinary attack move whose segments test contact with `attack = 0x800`-style data; on contact its branch list selects the throw by the [situation code](moves.md#branch-conditions) (front/side/back, standing/crouching/down) and distance, with transition code `0x21`.

1. `MoveStep` pairs the fighters: `throwPartner` of each is the other, and both set `inThrow`.
2. `MoveStartAll` (`0x80045834`, the per-frame move start for all fighters) handles a pending `0x21` move that has reached its entry frame first. If both fighters start one on the same frame, one is chosen by `frameCounter % 2`. The victim's move is the thrower's `+0x32` entry of `g_throwVictimSlots`, started with transition `0x22` (`ThrowVictimStart`), then both moves start.
3. Transition `0x21` (thrower, `throwState = 0`): heading is set from the direction to the victim, rotated by −90°, 0 or +90° for victim quadrants 1, 2, 3 (180° for quadrant 0), and turns over 16 frames to the victim's heading; the **anchor is the victim's root**. Both animations therefore play in one shared frame. `throwState` counts the steps of a multi-part throw.
4. Transition `0x22` (victim): heading turned 180°, anchored at its own root; `throwState` decrements (−1, −2, …); a throw that lands during the victim's attack startup or `powerTimer` sets `+0xBD` (counter throw).
5. Damage comes from event 11 at the chosen frame of the thrower's move (`extraKind = 1`); the victim receives it through `HitExtraDamage`.
6. Throw escapes are ordinary branch rows of the victim's thrown move (button commands inside a window); condition `0x1D` checks that the opponent is no longer throwing.

## Reversals and parries

When a fighter is hit, `MoveReactionBranch` (`0x8002DB08`, not against character 17) evaluates its **running** move's branch list with `BranchFindReversal`, which accepts only condition types `≥ 0x45`:

| Type | Accepts |
|---:|---|
| `0x45` | Being hit this frame, both fighters facing each other within 60°. |
| `0x46` / `0x47` / `0x48` | Facing each other within 60°, the attack is high / mid / low (`0x412`, `0x217`, `0x10F`), does not have flag `0x800`, and its descriptor uses joint `P` (0 = any). |
| `0x49` | As above for high or mid. |
| `0x4A` | Facing within 60° and the attacker's running slot equals `P`. |
| `0x4B` | Facing within 60° and the attacker's animation id (the `s16` stored just before each animation stream) is in list `P` (`0x80095AB8`). |

A match replaces the hit: the branch target starts, the hit slots and the attacker's contact flags are cleared, and the reversal's damage becomes `damageOverride = attacker.damage / 2 + 25`.

## Body separation

`BodySeparate` (`0x8004401C`, ported bit-exact as `body_separate` in [`tools/research/fight_sim.py`](../../../tools/research/fight_sim.py)) runs for each fighter pair when the pair distance (`0x8009EA08 + 0x10·(bit(i) + bit(j))`) is at most 3000, both fighters are `active`, neither has `invulnerable == 1`, and not both have `noBodyPush` (`+0xD9`). `BodyOverlapSolve` (`0x80046FCC`, called on the scratchpad stack through `FUN_80047968`) then computes:

1. **Overlap.** Each fighter has 8 body spheres (`+0x324`, 16 bytes each: `u16` x, y, z at `+0/+4/+8`, radius at `+0xC`; radius 0 = unused), refreshed by `CollisionShapesUpdate`. For every pair of used spheres whose 16-bit coordinate differences are all below `r1 + r2`, `overlap = max(r1 + r2 − sqrt(dx² + dy² + dz²))` (table square root `FUN_8004B174`, compared as `s16`).
2. **Height gap.** Without overlap, fighters more than 299 units apart in `rootY` are left alone.
3. **Charging.** When both running moves have an active window (`+0x2D ≠ 0`), each fighter's front point is 200 units ahead of its root along the facing vector (`angle = 0x400 − facing/16` in 4096 units, `x = cos·200/4096`, `z = sin·200/4096`). If the front points are less than 500 apart on both axes and the anchors approach each other (`(posB − posA)·(frontB − frontA) < 0`), the fighters "charge": the overlap is raised to at least 400 and the full correction is applied instead of half.
4. **Split.** `dA`, `dB` = how far each root moved since the previous frame (previous roots as `u16` at `0x8009EAA0 + 0x10·index`, `+4/+8/+0xC`). Each fighter is pushed along its own facing axis, choosing the direction that points towards the other fighter (`FUN_8004B634`, a 4096-unit atan2): `shareA = overlap·dA / (dA + dB)` (both weights 1 when neither moved), and

   ```text
   newA = rootA + dB·axisB − shareA·axisA
   newB = rootB + dA·axisA − shareB·axisB        (axis = (cos, sin) / 4096, truncated per term)
   push = (new − root) / 2   (arithmetic shift; the whole difference while charging), y = 0
   ```

   so the fighter that moved more yields more, and each is also carried by the other's motion.
5. `BodySeparate` adds the push (`bodyPushX/Y/Z`, `+0x3E8`) to anchor and root, sets `bodyContact` (`+0xD5`, branch conditions `0x33/0x34`) and `bodyContactWith[other]`; in mode 8 with two or more fighters in throws the push is doubled (or dropped for `noBodyPush` fighters).

## Mode-specific rules

- **Practice (mode 5)**: with the practice "counter hit" setting on for the defender (`0x800958E4[index]`), every clean hit on a fighter outside a reaction counts as a counter hit (`HitApply`).
- **Tekken Ball (mode 7)**: hits between the fighters do not change health (`HitApply` restores it unless the attacker is the ball record, index 2). The ball's rules are in [modes.md](modes.md#tekken-ball). The hit spark side is flipped by the defender's side (`HitSpawnEffect`).
- **Tekken Ball and Tekken Force (modes 7, 8)**: a defender inside a throw cannot be hit (`HitTest`).
- **Tekken Force (mode 8)**:
  - three fighters start moves each frame (`MoveStartAll`);
  - a KO does not start the KO sequence (`FUN_80032030`);
  - when a CPU enemy is hit, the score `0x800B70EC` grows by 10 × the base damage (`slot +0x1C`, the attack's damage before scaling) of each hit by the player or by a thrown enemy (`+0xE6`), plus 20 × a positive `HitExtraDamage` term (throw damage);
  - thrown CPU enemies flying faster than 89 units per frame (frames 11 to the end of the move) become unblockable projectiles (`attack 0x607`, damage `speed/16 + 10`) that hit the other enemies (`FighterMovePhysics`);
  - throws are skipped while the opponent is already in a throw ([moves.md](moves.md#branch-evaluation)).

## Open items

- None known.
