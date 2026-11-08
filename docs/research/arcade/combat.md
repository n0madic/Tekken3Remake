# Arcade Tekken 3 (World ver. E1) mapped onto the PlayStation build: combat, collision, reactions, fighter physics, skeleton and pose

The port is `remake/core/arcade/` (`ArcadeCombat`, `ArcadeAnimation`, the physics and hands); the fight traces prove it.

Baseline: PS1 = Japan Rev.1 (`work/decomp/SLPS_013.00.c`), arcade = `work/arcade/decomp_full/arcade_e1_full.exe.c`, disassembly with capstone on `work/arcade/prg_world_e1.unpacked.bin` (load 0x80010000, no header).

Status words: `confirmed` = read on both sides (and where said, run in the CPU harness); `inferred` = deduced, not read on both sides or by value only. All arcade addresses are this ROM's.

**Decompiler warning (arcade).** Ghidra folds loads of BSS globals to their image value 0. Example: `FUN_80198298` prints `+0x20 = 0; +0x22 = 0; +0x24 = 0`, but the instructions at `0x801982F0` load `DAT_8021FAC8/CA/CC` (the decoded root channels). Likewise `FUN_8019CD04` ends with `+0x1826 = DAT_8021FACA`, not 0. A global that "is always 0" in the arcade decompile must be checked with capstone. `gp = 0x8021EEB0`.

## Headline answers

1. **Attack segments are live from joints.** There are no baked records and no section 9. The row holds four joint bytes inline. Arcade rows can give `core` the joint numbers by a data conversion, but hit detection needs another (small, simpler) code path: `Combat.collision_shapes` always takes its joint branch. A baked conversion cannot be exact, because the joints depend on blending, look-at, heading and root at run time.
2. **The root channels are polar**, not Cartesian: `(angle, height, distance)`. Height and distance are scaled, the angle is not, and height is subtracted. See section 3.
3. **The pose pipeline is simple and was proven exactly in the harness.** Local rotation is `EulerToMatrix(x, −y, −z)`, world is the libgte `CompMatrix`, the offsets and parents come from the model file rows. Over two runs (1,170 frames): 26,440 local matrices without blend, 3,312 with blend, 39,888 world joints, 2,216 root frames and 827 segment points, 0 differences (`work/arcade/fight/pose_check.py`, details under "Harness results"). The look-at's own angles and True Ogre were not checked by it.
4. **Combat logic is the PS1's with named differences**: the counter-hit bonus formula, fractional chip damage, a level-triggered KO, no arena clamps, ramps or walls, no throw link, several new air kinds, the bounds step moved before physics.
5. **Most tables convert.** The reaction record is 56 bytes with pointers (978 records); all its PS1 fields exist and convert to the 21-word layout. Throw reactions are ordinary records with null push pointers (412 of them), so `THROW_VICTIM_SLOTS` and the `0x1nnn` tag disappear.

## 1. Function map

Confidence: `confirmed` = bodies read on both sides and the same role; `inferred` = order and shape only.

### Fight frame and dispatch

| PS1 name @ addr | Arcade @ addr | Confidence, evidence |
|---|---|---|
| FightFrame @ 8002B0AC | FUN_8018A988 | confirmed, call order |
| FUN_8003EE94 @ 8003EE94 | FUN_8019EE00 | confirmed, first call of the frame |
| ReplayUpdate @ 800323CC | FUN_8019541C | confirmed, order, replay states `DAT_8021F640` |
| RoundFlow @ 8003CDD8 | FUN_8019D560 | confirmed, sub-state machine `DAT_8021F0C0` |
| HudRoundUpdate @ 8003D904 | FUN_8019DCA8 | confirmed, order |
| CameraDirector @ 800633C0 | FUN_8018B500 → FUN_801D009C | confirmed, order |
| CameraShakeStep @ 8004AFCC | FUN_801AE9DC | inferred, order |
| CameraFrame @ 800484D8 | FUN_801A6DBC | confirmed, order |
| FUN_800421E4, FighterSavePrevSegments @ 8006AD84 | FUN_80198A48 | confirmed, differs (section 2) |
| MoveStartAll @ 80045834 | FUN_8018C498 | confirmed |
| ThrowVictimStart @ 8002D9B0 | FUN_8018F318 | confirmed |
| PairwiseDistances @ 8004391C | FUN_8018B050 (direction), FUN_8018B124 (distance) | confirmed, split |
| ArenaBounds @ 80043394 | FUN_8018B124 | confirmed, very different (section 6) |
| FighterMovePhysics @ 8003F330 | FUN_8019F3FC | confirmed, restructured (section 6) |
| FighterRelativeAngles @ 80043D2C | FUN_801A0A6C | confirmed |
| SavePlayerPosition @ 80046F98 | FUN_801A5B00 | confirmed, called only if both throw states are 0 |
| FighterVelocity @ 80040CA4 | FUN_8018B430 (+ FUN_8018B414) | confirmed |
| CollisionShapesUpdate @ 80042204 | FUN_80198BF8 | confirmed |
| BodySphereProfile @ 8003EEFC | FUN_8019EF90 + FUN_8019F00C | confirmed |
| (hurt radii setup) | FUN_8019F3A8 | confirmed |
| FUN_80043F40 (clear contacts) @ 80043F40 | none | confirmed absent |
| BodySeparate @ 8004401C | FUN_8018B808 | confirmed |
| BodyOverlapSolve @ 80046FCC (wrapper 80047968) | FUN_801A5B68 (wrapper FUN_801A6484) | confirmed |
| HitClearSlots @ 800442A0 + HitTest @ 80044304 | FUN_8018B91C | confirmed, merged |
| HitTestSegments @ 80047E54, FUN_80047FF4 (stack switch) | FUN_801A6A14, FUN_801A6BF0 (stack switch) | confirmed |
| SegmentHitsCylinder @ 800479A4 | FUN_801A64C0 | confirmed, same |
| AttackVelocity @ 80040CF8 + CopyAttackDirection | FUN_8018B47C | confirmed |
| MoveBranchAll @ 8004539C | FUN_8018C2DC | confirmed |
| MoveReactionBranch @ 8002DB08 | FUN_8018F424 | confirmed |
| BranchFindReversal @ 8002E95C | FUN_80190240 | confirmed |
| ReversalCondition | FUN_80190334 | inferred |
| MoveEvents @ 80045B60 | FUN_8018C5A4 | confirmed |
| FUN_80045260, HitApply @ 80044634, HitClassify @ 80044D24, HitDamage @ 80044E70, HitExtraDamage @ 80044C4C, HitBestSlot, HitCopySlotFlags, HitSpawnEffect | FUN_8018BB68 | confirmed, all merged |
| HitZoneScale | FUN_8018C1E8 | confirmed |
| FUN_80076EB8 (guard spark) | FUN_801AD0B8 | confirmed |
| FUN_80076F10 (hit spark) | FUN_801AD114 | confirmed |
| FUN_80076E58 | FUN_801AD050 | inferred |
| FUN_80032030 (KO replay) | FUN_80194F94 | confirmed |
| FighterSounds @ 80041138 | FUN_801A104C | inferred, order |
| InputSource @ 8002BF3C | FUN_8018B61C | confirmed |
| LatchButtonTaps @ 80040D68 | FUN_8018B710 | confirmed |
| none | FUN_8018CBD8, FUN_8018CC38 | arcade only: at a throw's pose frame 2, or contact + opponent's clean hit, tests list `PTR_DAT_801FF054[bank]` against `+0x8C` and calls FUN_801BCB0C(player): a message buffer at `0x80277538`. No effect on the fighter records seen |

### Moves and reactions

| PS1 name @ addr | Arcade @ addr | Confidence, evidence |
|---|---|---|
| MoveStepAll @ 80045450 | FUN_8018C340 | confirmed (also holds the KO collapse) |
| MoveStep @ 800454E0 + MoveBranchStep @ 8002DC3C | FUN_8018F528 | confirmed, merged |
| BranchFind @ 8002E078 | FUN_8018F9A4 | confirmed |
| BranchCondition @ 8002E310 | FUN_8018FB3C | inferred (cases 0x33, 0x34 read) |
| TransitionRemap @ 800311BC | FUN_80192A3C | confirmed |
| MoveKeepsFrame | FUN_80192B44 | confirmed |
| HitSelectReaction @ 8002EDF8 | FUN_80190600 | confirmed |
| AirReactionKind @ 8002F0E8 | FUN_80190A7C | confirmed |
| LaunchTrajectory @ 8002F2C8 | FUN_80190C78 | confirmed |
| recovery after a reaction (inline in MoveStartOrAdvance) | FUN_80190900 | confirmed |
| recovery after a throw (inline) | FUN_80190978 | confirmed |
| PushRepeatCount @ 8003159C | FUN_80192DF8 | confirmed, same |
| FighterCollapse @ 8002DA80 | FUN_8018F3A0 | confirmed (slot 0xE5C vs 0xD66) |
| MoveStartOrAdvance @ 8002F600 | FUN_80190FF8 | confirmed |
| MoveLookup @ 8002D3CC | FUN_8018ED1C | confirmed (`DAT_8021F61C[player]`) |
| MoveTotalDamage @ 8002D51C | FUN_8018EE74 | confirmed |
| FUN_8002D570 (round stance) | FUN_8018EEC8 | confirmed |
| FUN_8002D6B0 (win pose) | FUN_8018F070 | confirmed (0xE5D–0xE60 vs 0xD67–0xD6A) |
| MoveInSlotList | FUN_8018EDE8 | confirmed |
| FUN_80040C04 | FUN_801A0B58 | inferred |
| ClampSymmetric, TrackBudget | FUN_801A09CC, FUN_801A0A04 | confirmed |
| SinQ15, CosQ15 | FUN_8018A16C, FUN_8018A1B4 | confirmed |
| Atan2Angle | FUN_8018A1FC | confirmed |
| ISqrt | FUN_8018A314 | confirmed |
| SquareRoot0 @ 8004B174 | FUN_801AEC2C | confirmed, same code, table exact |
| Atan2Units4096 @ 8004B634 | FUN_801AF4D4 | confirmed by name and head of the body |
| HandFaceCommand | FUN_80194080 | confirmed |
| FUN_80034950, FUN_80034998 | FUN_80194250, FUN_80194298 | inferred |
| FUN_8003CDC0 | FUN_8019D54C | inferred |
| CameraShakeStart | FUN_801AE9B0 | confirmed |
| FUN_8004AF1C (dust) | FUN_801AE4B4 | inferred |

### Skeleton and pose

| PS1 name @ addr | Arcade @ addr | Confidence, evidence |
|---|---|---|
| FighterSkeletonUpdate @ 8002BCB8 | FUN_8018B388 | confirmed |
| FUN_8003A030, FUN_8003A1D8 (lighting), FUN_80036254, FUN_80037B4C | FUN_80199E08, FUN_80199FF4, FUN_80198230, FUN_8019A6B8 | inferred, same places |
| FUN_8003AA6C | FUN_80198390 | confirmed |
| FighterAnimate @ 8003AAD0 | FUN_80198298 | confirmed |
| AnimDecodeRoot + AnimScaleRoot | FUN_80194A90 | confirmed, scale differs |
| AnimDecodePose | FUN_80194A70 → FUN_80194744 (57 channels) | confirmed |
| FUN_80038B60 (victim's scale) | inside FUN_80194A90, FUN_80194B58 | confirmed |
| RootReanchor @ 8003AC1C | FUN_801991B4 | confirmed |
| FighterTransitionBlend @ 8003C4C4 | FUN_8019CD04 | confirmed |
| RootUpdate @ 8003AD48 | FUN_801984E8 | confirmed (harness) |
| RootRotationMatrix, FUN_8003A6B4 | FUN_801A24A4 | confirmed (harness), other rounding |
| BlendRootDy | FUN_801E0BCC | confirmed |
| BlendDstFrame | FUN_80192BA0 | confirmed |
| FighterHandPoses | FUN_80194458 | README, not re-read |
| FUN_80034354 (blink) | FUN_80193F90 | inferred |
| FighterComposeJoints @ 8003B220 | FUN_80198754 | confirmed (harness) |
| PoseBuildMatrices (IK) | none | confirmed: FUN_801984A0 + FUN_8019A498 for all 18 |
| EulerToMatrix (`PoseSolver.euler_to_matrix`) | FUN_8019A498 → FUN_8019A4AC | confirmed (harness) |
| ComposeJoint @ 8003B814 | CompMatrix @ 801EF684 | confirmed (harness) |
| MatrixAddScaled @ 8003A980 | FUN_801E1F64 | confirmed (harness) |
| MatrixOrthonormalize @ 800762B0 | FUN_801E0C04 | confirmed (harness) |
| FUN_8003A5A0 (look-at angles to matrix) | FUN_8019A498 | confirmed: same call site in the look-at; the arcade has one routine for this and for the locals |
| HeadLookAt @ 800392C8 | FUN_80199310 | confirmed |
| FUN_8004B4B0 | FUN_801AEF6C | confirmed: same call site and signature in the look-at |
| GonEyesFollow | none | confirmed absent |
| FUN_80033C54 (True Ogre sway) | FUN_80193A38 + FUN_80193B20 | confirmed, condition and tilt differ |
| FUN_80037F10 (attachments) | FUN_8019B6D8 | README (`confirmed` there) |
| ReplayPlayPose, ReplayRecordPose, ReplayRootRotation, ReplayRootPosition | FUN_80195DA8, FUN_80195BE8, FUN_801959B0, FUN_8019571C | confirmed by shape |
| joint setup | FUN_80197790 (per row), FUN_8019A36C (identity + parent) | confirmed |
| model scale, loader | FUN_80197C2C | confirmed |

## 2. Attack records

`confirmed` by reading, and in the harness over 1,170 frames: 659 end points and 168 explicit start points (`b != 0`) equal the joints, 0 differences. A start with `b == 0` is from reading only.

**Source of the joints.** The row holds them inline: `+0x32 a0, +0x33 b0, +0x34 a1, +0x35 b1`, the same meaning as the first four bytes of a PS1 descriptor (PS1 row `+0x28` points at it). There is no section 9, and no built-in descriptors (PS1 `BUILTIN_ATTACKS`, `BUILTIN_BLOB` have no counterpart).

Row counts: 4,871 rows; 1,998 have an active window, and of those all have `a0`, 901 have `a1`, 86 have `b0`, 836 have `b1` (so a second segment usually runs between two named joints). Joint values named in those rows: 1, 2, 4–6, 8–19, 21, 23, plus 24 and 25 for projectiles (5 rows, always in `a0`).

**Per frame**, for a fighter's segment `k` (`seg0` start `+0xF4`, end `+0x100`; `seg1` start `+0x10C`, end `+0x118`):

1. **`FUN_80198A48` at the very start of the frame**, before the move start and before the skeleton, with last frame's joints and last frame's row. For `k < attackSegCount (+0x98)`: if `b[k] == 0`, `start[k] = joint[a[k]].t`. Otherwise nothing. Effect: start = last frame's end while the segment has no `b`.
2. **Skeleton**, physics (the arcade's order is in section 6).
3. **`FUN_80198BF8` after the skeleton**, each fighter. In this order:
   - Weapon points, every frame, no window test, into spare joint translations. They are `ApplyMatrix(joint.rot, p) + joint.t` (MVMVA rounding, the existing `WEAPON_POINTS` code):
     - `bankType == 4`: joint 10 × (100, −720, 0) → joint 18; joint 10 × (100, −360, 0) → joint 19.
     - `bankType == 0xE` and `charId` 0x14 or 0xF: joint 11 × (100, −500, 0) → joint 22; joint 2 × (800, 0, 600) → joint 23.
     - PS1's Gon entries are absent, and PS1 allows only char 0x14 in bank 0xE.
   - Hurt zones and body spheres (below).
   - If `attackSegCount != 0`, with no window test: `end[0] = joint[a0].t`; if `b0 != 0`, `start[0] = joint[b0].t`; `end[1] = joint[a1].t`; if `b1 != 0`, `start[1] = joint[b1].t`. A joint value 0x13 reads joint 6 when `charId == 0xE`; values ≥ 0x18 are skipped.

**Counts.**

- `attackSegCount +0x98` is set at the move start (end of `FUN_80190FF8`): `row+0x30 != 0` and `row+0x34 != 0` → 2; `row+0x30 != 0` and `row+0x32 != 0` → 1; else 0. Same rule as PS1, on the inline bytes.
- `activeSegs +0xB3` is set in physics: 0 outside `[row+0x30, row+0x31]`, else 2 if `row+0x34 != 0`, else 1.

**Projectiles.** `row+0x32 − 0x18 < 2` selects the segment arrays `0x802C6C70` (player 0) or `0x802C77B0` (player 1), counts `DAT_8021FC44`, `DAT_8021FC48` (`FUN_801A6A14`). PS1 has the same rule with `d[0] >= PROJECTILE_JOINT`.

**Attachments in attack segments.** Rows name joint 21 (10 fields in window rows of the whole table; bank 14 is where they were seen), which is an attachment composed by `FUN_8019B6D8`, so `core` must keep stepping `AttachmentDynamics` for them. Joints 18 and 19 in bank 4 and joint 23 in bank 14 are weapon points. Joint 19 in bank 14 is remapped to 6 only for char 0xE; for char 0x14 it is an attachment or a stale value (open). An absent joint keeps old values: `+0x488 + 0x1C·j == 0` skips composing.

**What `core` must change** (`inferred` as design, the behaviour is `confirmed`):

- `Combat.collision_shapes`: always the `else` branch; drop `_attack_segments_baked` for arcade data. Its `WEAPON_POINTS` loop must run for the arcade's table every frame, before the segments; in PS1 mode it stays outside-window.
- `Combat.save_prev_segments`: for `k < attack_seg_count`, if `b[k] == 0`, `start[k] = joint[a[k]].t` (equal to the saved end while the joints are unchanged); no copy when the count is 0. The `segment_anchor` and `segment_end` saves are unused.
- `AttackRecords.header`: read the four inline bytes; `bytes_of`, `offset_of`, `has_descriptor` are unused.
- A consequence of the rule: on a move's first frame, `start` comes from the previous row's joint, or is stale when the previous row's count was 0 (no PS1 "lead point"). `core` must therefore keep the old `start` across moves.

**Hurt and body shapes.**

- Hurt zones `+0x154`, 14 × 0x14: `{x, y, z, s16 radius at +0xC, s32 radius² at +0x10}`, from joints in `0x801FE5B4`. Zone 8 y −0x78, zone 11 y −0x3C (same as `HURT_ZONE_Y`).
- Body spheres `+0x26C`, 8 × 0x10, radius at +0xC, from joints in `0x801FE53C`.
- `+0x2EC` = copy of zone 0's point.
- Same as PS1's `Combat.collision_shapes` second half.

## 3. Skeleton pipeline

`confirmed`: read, and the formulas below run against `FUN_80198298` in the harness (`work/arcade/fight/pose_check.py`, costumes 0 of characters 0 and 1, random pads). Root frames and joints: 0 differences; see "Harness results" after section 6. Parts the harness did not reach are named there.

### Sequence (FUN_8018B388 → FUN_80198390 → FUN_80198298, per fighter in player order)

1. **Replay** (`FUN_80195DA8`): during playback overrides the moves, frames and blend bookkeeping.
2. **Root decode** (`FUN_80194A90`): `FUN_80194744(stream of *(+0x3C), 0x8021FAC8, +0x40 − 1, 3)`. With `s = throwState < 0 ? opponent.+0x430 : own.+0x430`: `ch1 = s16(trunc12(ch1 · s))`, `ch2 = s16(trunc12(ch2 · s))`, `ch0` unscaled. `trunc12(v) = (v + (v < 0 ? 0xFFF : 0)) >> 12`.
   - `+0x430 = percent · 4096 / 100` from the model header word 1 (`FUN_80197C2C`), same as `CharacterModel.scale_fixed`.
   - PS1 scales all three with a floor shift.
3. **Pose decode** (`FUN_80194A70`): `FUN_80194744(stream of *(+0x44), 0x802C6BF8, +0x48 − 1, 57)`. Channels 0–2 of this buffer are ignored; joints read from channel 3.
4. `+0x20, +0x22, +0x24 = ch0, ch1, ch2` of the root decode.
5. **Re-anchor** (`FUN_801991B4`), if `+0xA2 != 0`:
   - clear it; `n = max(0, rootFrame − frameStep − 1)`; decode and scale the root at `n`;
   - `i = ((ang + 0x8000 − facing) >> 3) & 0x1FFE` (byte index of the s16 tables);
   - `posX = rootX − trunc12(d · sin[i])`, `posZ = rootZ + trunc12(d · cos[i])`.
   - `facing` is `+0x2`, `rootX, rootZ` are `+0x44C, +0x454`.
6. **Blend state** (`FUN_8019CD04`), if `DAT_8021FB38 != 0` and `DAT_8021F088 == 0`; then `DAT_8021F088 = 0`. See "Blending".
7. **Root** (`FUN_801984E8`):
   - Angles `ax = tiltX(+0x0) >> 4`, `ay = (0x8000 − heading(+0x28)) >> 4`, `az = tiltZ(+0x4) >> 4`, stored as s16; replay may override (and sets the heading back during playback).
   - Rotation (`FUN_801A24A4`, C arithmetic, table index `& 0xFFF`, `t = trunc12`, s16 stores):
     ```
     m00 = t(cy·cz)  m01 = t(cy·sz)  m02 = −sy
     a = t(sx·sy)    m10 = t(a·cz) − t(cx·sz)   m11 = t(a·sz) + t(cx·cz)   m12 = t(sx·cy)
     b = t(cx·sy)    m20 = t(b·cz) + t(sx·sz)   m21 = t(b·sz) − t(sx·cz)   m22 = t(cx·cy)
     ```
     Geometrically this is PS1's `rotation_xyz(−tiltX, heading − 0x8000, −tiltZ)`, but the GTE rounding of `FighterSkeleton.rotation_xyz` does not apply.
   - Weight and height: if `blendMode(+0x1830) != 0` and `blendFrames(+0x1AC8) != 0`: `weight(+0x1AD4) = (counter(+0x1AD0) << 12) / frames`, `y = s16(ch1 + trunc13(delta1(+0x1AC2) · s16(weight · 2)))`. Otherwise `weight = 0x1000`, `y = ch1`. `+0x1826 = y`.
   - Position, with `a = ((ch0 + 0x8000 − facing) >> 4) & 0xFFF`, by `airPhase(+0x9C)`:
     - `1`: root = pos.
     - `2`: rootX = posX, rootZ = posZ, rootY = posY − y.
     - else: `rootX = posX + trunc12(ch2 · sin[a])`, `rootY = posY − y`, `rootZ = posZ − trunc12(ch2 · cos[a])`.
   - So in PS1's terms `dx = d·sin θ`, `dz = −d·cos θ`, `dy = −y`, but the truncation is on the combined angle, so a static conversion to Cartesian channels is not bit-exact.
8. **Hands, face**: `FUN_80194458`, `FUN_80193F90` (no effect on joints, except that True Ogre's level channel feeds the sway).
9. **Compose** (`FUN_80198754`):
   - Root frame copy: `+0x458..+0x477` = `+0x438..+0x457` (rotation, translation).
   - For `j` in 0..17: `(x, y, z) = pose[3 + 3j .. 5 + 3j]`; `local = EulerToMatrix(x, s16(−y), s16(−z))` at `+0x728 + 0x50·j`. If `j != 0` and `blendMode != 0`: `local = Orthonormalize(AddScaled(delta[j](+0x1880 + 0x20·j), local, weight))`. Save rotation and translation at `+0x15E4 + 0x20·j` (the "displayed" locals; in PS1 only joints 1–17 are saved).
   - Head look-at (`FUN_80199310`) overwrites joint 2's local rotation (see below).
   - True Ogre (costume `+0x1E` is 0x20 or 0x21): `FUN_80193A38`, then `FUN_80193B20` per joint.
   - For `j` in 0..17, if `+0x488 + 0x1C·j != 0`: `CompMatrix(parent.world, local, world)`.
   - `+0x11B4 = 0`. For `j` in 18..23 if present: `FUN_8019B6D8` (attachment dynamics) then `CompMatrix`.
   - `FUN_8019A6D0`, `FUN_80193708`, `FUN_80192ECC` follow (not simulation state, `inferred`).

### Records and where the numbers come from

- A joint record is at `+0x724 + 0x50·j`: `+0x04` local matrix (rotation, `+0x18` translation), `+0x24` world matrix (rotation, `+0x38` translation), `+0x48` parent record pointer. Hence world rotation `+0x748 + 0x50·j`, world translation `+0x75C + 0x50·j`, local translation `+0x73C + 0x50·j`, parent `+0x76C + 0x50·j`. The root's record is at `+0x434`, so its world frame is `+0x458`.
- **Offsets and parents come from the model file rows, not tables** (`FUN_80197790`). With the file at `0x8022109C + player · 0x1C000`, its 0x10-byte header and 0x38-byte rows: local translation = `(word5, word6, −word7)`; parent = `word8`, negative means the root for rows 0–17, and for rows 18–23 `−1` means absent. This is the rule of `CharacterModel.joint_offsets` and `joint_parents`.
- `limb_basis`, `skeleton_offsets`, `limb_offsets`, `euler_slots` (PS1 IK tables): no reference in the decompile to the leads' addresses. False leads (`inferred`: value matches only, no IK code).

### Foot frames

Nothing in the code handles feet: rows 14 and 17 follow the same rule as other joints. The 90° about y lies in the data (the motions and the model parts agree). Collision uses only joints' translations and joint 2, 10, 11 rotations, and feet have no children, so it does not matter for gameplay. Only a PS1 mesh on arcade motions needs `arcade_kmd.playstation_frame`'s correction.

### Rounding and GTE

| Step | Arithmetic |
|---|---|
| Local Euler | `FUN_8019A498` = PS1's EulerToMatrix (GTE GPF sf=1, same register order), with the arcade's sine table (`PoseSolver.euler_to_matrix` with `tables.sin16`). Harness: exact. |
| World | `CompMatrix @ 0x801EF684`: three `MVMVA` (sf=1, rotation, V0 = local's column, IR results stored as s16); translation: `MVMVA` of local `t` as s16, `MACn` + parent `t`. Identical to PS1's ComposeJoint, so `JointFrame.compose_offset`. Harness: exact. |
| Root rotation | C with truncation (above); no GTE. |
| Root position | C with truncation. |
| Blend | GTE GPF with IR0 = weight, then s16 add: `FighterAnimation._add_scaled`. `FUN_801E0C04` = `_orthonormalize` (VectorNormal, OuterProduct12). The rsqrt table `0x8021A8A0` is the PS1's. |
| Weapon points | `ApplyMatrix`, `>> 12` per row, then add `joint.t`. |

### Blending (FUN_8019CD04) against FighterTransitionBlend

Same buffers and three modes (1 decay, 2 branch, 3 stance). PS1 field → arcade: blendActive `+0xE5` → `+0xB5`; blendMode `+0x181C` → `+0x1830`; lastPoseMove `+0x1824` → `+0x1838`; lastPoseFrame `+0x182C` → `+0x1840`; rootDyBlended `+0x1812` → `+0x1826`; blendRootDelta `+0x1868` → `+0x1AC0`; blendWeight `+0x186E` → `+0x1AD4`; blendFrames `+0x1870` → `+0x1AC8`; blendCounter `+0x1878` → `+0x1AD0`; blendSrcMove `+0x187C` → `+0x1AD8`; blendDstMove `+0x1880` → `+0x1ADC`; blendSrcFrame `+0x1884` → `+0x1AE0`; blendDstFrame `+0x1885` → `+0x1AE1`; prevLocalMats `+0x13B0` → `+0x15E4` (from joint 0); blendDelta `+0x15F0` → `+0x1880` (from joint 0). Globals: freeze `DAT_8009588C` → `DAT_8021FAD0`; paused `DAT_800958B8` → `DAT_8021FBD0`; hold `DAT_800A9234` → `DAT_8021FB50`; enable `DAT_800958C0` → `DAT_8021FB38`; skip `DAT_800972CC` → `DAT_8021F088`; replay `g_replayPlayback` → `DAT_8021F03C`.

The arcade's choice, in order (`N = row+0x1E`, `frame = +0x48`):

```
active = 0
if mode == 1 and counter == 0: mode = 0
if last_pose_move != pose:
    if pose.flags(+0x18) & 1 == 0:
        if move_changed:
            left = max(0, N − frame); n = 0
            if flagBA(+0x9E) == 0 and left != 0:
                if window_first != 0 and frame < window_first: n = min(window_first − frame, 0x10)
                elif throw_state < 0: n = 0x10
                elif was_hit(+0x73) == 0: n = 4
                else: mode = 0          # n stays 0
            n = min(n, left)
            if n > 1: active = 1; mode = 1; (start, skip the forward part)
    elif mode == 1: mode = 0
if mode == 1: skip the forward part
if juggle == 0 and not (in_air and was_hit) and pose.flags & 2 == 0 and trans_bit6 == 0:
    if move_row == null:                         # toward the stance
        if N − frame > 0xF: mode = 0
        elif mode == 3: if move_changed: mode = 0
        else: n = (frame_step >= 1 ? N − frame + 1 : frame); if n >= 2: mode = 3; active = 1
    elif mode == 2: if counter == frames: mode = 0
    elif frame < entry_frame: mode = 2; active = 1
else:
    mode = 0
```

Differences from `FighterAnimation._blend_choose` (PS1), all `confirmed` by reading:

| PS1 | Arcade |
|---|---|
| Suppression `_blend_suppressed`: NO_BLEND flag, `move_flag_ba`, `guarded_prev`, `in_reaction` skip the decay test | Only flag bit 0 skips; `flagBA` only forces `n = 0`; `guarded_prev`, `in_reaction` not tested |
| `_decay_length` `n = 0x10 if throw_state < 0 else 4` | Same, but `n = 0` and `mode = 0` when `was_hit` and not a victim |
| Decay test: `last_pose_move == pose and branch_kind != 3 → 0` | No `branch_kind` test |
| `_no_blend_forward` includes `move_flag_bb` | No such flag |
| Stance `n`: `left + 1` if `frame_step >= 1`, else `pose_frame` | Same |
| Branch `n = entry − frame + 1` with `branch_kind != 3` | No `branch_kind` test; frames = `entry − frame + 1`, `< 0 → 1` |
| Stance mode 3 ended also by `counter == frames` | Ended by `move_changed` or the "left > 0xF" clear; the counter stays clamped |

Same: the source and destination frames per mode. Mode 2's destination frame is entry frame for transitions in `{2, 0x12–0x16, 0x19, 0x1A, 0x1D, 0x2C}` (`FUN_80192BA0`), else 0; deltas from the decoded channels; counter stepping; the end `+0x1838, +0x1840, +0x1826 = decoded y`. No Bug #61 fallback (a null stance row): `FUN_8018ED1C` must be checked against missing slots.

Root delta in mode 1: `delta[k] = shown[k] − dst[k]`, with `shown[0]` and `shown[2]` the never-written `+0x1824` and `+0x1828` (only `delta[1]` is read). Same quirk as the PS1 (`_blend_deltas`).

Pause gating: PS1 skips rebuilding locals during freeze or pause. The arcade rebuilds them every call (the decoded frame does not change, so only the look-at's stepping continues in a freeze: `inferred` effect).

### Head look-at (FUN_80199310)

Same algorithm and constants as `FighterAnimation._head_look_at` (limits 0x11C7, −0x2AAA, step 0x71C, hold 0x3C, 400/300, the limit curve, SquareRoot0; look base `Euler(0x4000, 0, 0x4000)` from `0x8021F0B0`, built once in `0x8025B09C`). State per player at `0x8025B0BC + 0x14·p`: current `+0`, target `+8`, active `+0x10`, snap `+0x11`, hold `+0x12`.

Conditions: `row+0x17 == 1` (look-at byte) and `DAT_8021FCD0 == 2` (camera phase fight). If `row+0x30 != 0`, not before `max(row+0x31, row+0x1E − 0x11)`.

Differences (`confirmed`, both read):

- The midpoint of the opponent's joints 1 and 2 uses `(b − a) / 2` (truncating), PS1 `>> 1`.
- No Gon rule (yaw 0 for char 0x11) and no `no_look_at` flag (`+0xC9`, `fighter_animation.gd` line 428, set in physics).

The angles it produces were not compared in the harness: the head's local is reported as differing from the plain Euler whenever the look-at is active, which is expected.

### What the remake's `ArcadeAnimation` does

Input: 57 s16 channels of `pose_move` at `pose_frame − 1`, three root channels of `root_move` at `root_frame − 1`, the scale, the record fields. No state besides the blend and look-at state above.

1. `root(ch0, ch1, ch2, scale)`: keep `ch0`; `s16(trunc12(ch1·scale))`, `s16(trunc12(ch2·scale))`, the victim taking its partner's scale.
2. `reanchor`: step 5, in place of `_reanchor`.
3. `root_update`: step 7, in place of `_root_update`: a new rotation function (truncating C), polar position, subtracted height.
4. `locals`: `solver.euler_to_matrix(x, s16(−y), s16(−z))` for all 18 joints (no IK slots), the arcade sine table. PS1's table is the same (`exact` in `table_search.json`; first 0x2800 bytes).
5. Blend: `_add_scaled`, `_orthonormalize` for joints 1–17 unchanged; the choice above.
6. Look-at: `_head_look_at` with the differences above.
7. `JointFrame.compose_offset(parent, local, offset)` for rows 0–17 with `offset = (word5, word6, −word7)`, then attachments as today.
8. True Ogre: `_ogre_local` keyed by costume slot 0x20, 0x21; `DAT_8021F63C` tilt = `s16(−ch(joint 5, z)) / 4` (truncating), not the PS1's `atan2(local5[0], local5[1]) · −4`; same cycle 5 → 18 → 19 → 6 → 5.

`f.root_dx`, `root_dy`, `root_dz` then hold `(ch0, ch1, ch2)` in arcade mode. Every reader must be checked: physics reads them only through `rootY` (`+0x450`) in the arcade (`inferred`, no reader of `+0x20..+0x24` found in the physics or combat read).

## 4. Fighter record field map

All `confirmed` by the code that uses them unless noted. Record stride 0x188C → 0x1AE4, records 0x800A96F0, 0x800AAF7C → 0x8031E154, 0x8031FC38.

| PS1 +offset (name) | Arcade +offset |
|---|---|
| 0x00, 0x04, 0x08 posX, posY, posZ | 0x08, 0x0C, 0x10 |
| 0x0C, 0x10 tiltX, tiltZ | 0x00, 0x04 |
| 0x0E facing | 0x02 |
| 0x12 playerIndex, 0x1E index | 0x14 |
| 0x16 bankType | 0x18 |
| 0x18 charId | 0x1A |
| 0x1C costumeSlot | 0x1E |
| 0x24, 0x26, 0x28 rootDx, rootDy, rootDz | 0x20, 0x22, 0x24 (angle, height, distance) |
| 0x2A targetDir | 0x26 |
| 0x2C heading | 0x28 |
| 0x2E headingDelta | 0x2A |
| 0x30 relAngle | 0x2C |
| 0x32 facingQuadrant | 0x2E |
| 0x34 aimDir | 0x30 |
| 0x36 trackAccum | 0x32 |
| 0x4C rootMove | 0x3C |
| 0x50 rootFrame | 0x40 |
| 0x54 poseMove | 0x44 |
| 0x58 poseFrame | 0x48 |
| 0x5A eventFrame | 0x4A |
| 0x5C moveFrame | 0x4C |
| 0x5E damage | 0x4E |
| 0x60 state | 0x50 |
| 0x64 attack | 0x54 |
| 0x66 guard | 0x56 |
| 0x68 attackHi | 0x58 |
| 0x69 stateClass | 0x59 |
| 0x6A holdFrames | 0x5A |
| 0x6C branchWindow | 0x5C |
| 0x6E frameStep | 0x5E |
| 0x74 throwState | 0x64 |
| 0x76 hitFreeze | 0x66 |
| 0x78, 0x7C slideStepX, slideStepZ | 0x68, 0x6C |
| 0x82 slideState | 0x70 |
| 0x83.. hitDone[0–2] | 0x71 (one flag) |
| 0x86 hitDone[3] (set at a throw start) | 0x72 (set in transition 0x22) |
| 0x87 wasHitThisMove | 0x73 |
| 0x88 contactThisMove | 0x74 |
| 0x89 guardedPrev | 0x75 |
| 0x8A inReaction | 0x76 |
| 0x8B branchKind | 0x77 |
| 0x8C condFlagUsed | 0x78 |
| 0x8E launchArmed | 0x7A |
| 0x90 airKind | 0x7C |
| 0x92 ballistic | 0x7E |
| 0x94 juggleCount | 0x80 |
| 0x96 groundOffset | 0x82 |
| 0x98 airSpeed | 0x84 |
| 0x9A, 0x9C, 0x9E airVelX, Y, Z | 0x86, 0x88, 0x8A |
| 0xA0 curSlot | 0x8C |
| 0xA2 curTransition | 0x8E |
| 0xAC, 0xB0 oppStartX, oppStartZ | 0x90, 0x94 |
| 0xB4 attackSegCount | 0x98 |
| 0xB5 crouchMove | 0x99 |
| 0xB6 stepKind | 0x9A |
| 0xB7 attackClass | 0x9B |
| 0xB8 airPhase | 0x9C |
| 0xB9 trackMode | 0x9D |
| 0xBA moveFlagBA | 0x9E |
| 0xBC skipStepPhysics | 0xA0 |
| 0xBD attackPending | 0xA1 |
| 0xBE anchorDirty | 0xA2 |
| 0xCE gotHit | 0xA3 |
| 0xCF guarded | 0xA4 |
| 0xD0 hitClean | 0xA5 |
| 0xD1 contact | 0xA6 |
| 0xD2 whiffed | 0xA7 |
| 0xD3 counterHit | 0xAE |
| 0xD4 closeHit | 0xAF |
| 0xC9 noLookAt | none |
| 0xD5 bodyContact, 0xD6 bodyContactWith | none (conditions read bodyPush != 0) |
| 0xDA moveChanged | 0xA8 |
| 0xDB inAir | 0xA9 |
| 0xDC, 0xDD landedA, landedB | 0xAA, 0xAB |
| 0xDE ko | 0xAC |
| 0xDF aboutToHit | 0xAD |
| 0xE0, 0xE1, 0xE2 tapLP, tapRP, tapBoth | 0xB0, 0xB1, 0xB2 |
| 0xE3 activeSegs | 0xB3 |
| 0xE4 extraKind | 0xB4 |
| 0xE5 blendActive | 0xB5 |
| 0xE8 lastDamage + 0xCC lastExtra | 0xB6 (one accumulating field) |
| 0xEA damageOverride | 0xB8 |
| 0xEC extraDamage | 0xBA |
| 0xEE hitFreezeIn | 0xBC |
| 0x104 hitCooldown | 0xBE |
| 0x106 pushFrames | 0xC0 |
| 0x108 pushSpeed | 0xC2 |
| 0x10A pushTableFrames | 0xC4 |
| 0x10C pushDir | 0xC6 |
| 0x110 pushTable | 0xC8 |
| 0x114 turnFrames | 0xCC |
| 0x116 turnStep | 0xCE |
| 0x118 recoverMash | 0xD0 |
| 0x11A recoverFrames | 0xD2 |
| 0x11C attackAlert | 0xD4 |
| 0x122 powerTimer | 0xDA |
| 0x124 pushRepeat | 0xDC |
| 0x126 pushRepeatTimer | 0xDE |
| 0x13A last push transition | 0xE0 |
| 0x128 stepCooldown | global `DAT_8021F060[player]` |
| 0xC1 applyEndTurn | global `DAT_8021F068[player]` |
| step accumulators 0x8009E9A8, 0x8009E9B8 | 0x8021F6B0, 0x8021F6B8 |
| 0x198 entryFrame | 0xE2 |
| 0x19A transition | 0xE4 |
| 0x19C transBit7 | 0xE6 |
| 0x19E transBit6 | 0xE8 |
| 0x1A0 moveSlot | 0xEA |
| 0x1A4 moveRow | 0xEC |
| 0x1A8 reaction | 0xF0 |
| 0x1AC attackSegs (2 × 24 bytes) | 0xF4 (same layout) |
| 0x20C hurtZones | 0x154 |
| 0x324 bodyPoints | 0x26C |
| 0x3A4 prevHurtZone | 0x2EC |
| 0x3B8 prevRoot | 0x300 |
| 0x3C4 vel | 0x30C |
| 0x3D0 atkDir | 0x318 |
| 0x3DC hitDir | 0x324 |
| 0x3E8 bodyPush | 0x330 |
| 0x3F4 health | 0x33C |
| 0x3F8 healthMax | 0x340 |
| CPU level (humans below 3; `isCpu` on PS1) | 0x34A (`inferred`) |
| 0x40C inHistIndex | 0x34C |
| 0x41C inHistory | 0x360 |
| 0x4EC, 0x4EE scaleBase, scale | 0x430 (s32; the victim's value is chosen on read) |
| 0x8B0 rootJoint | 0x458 |
| 0x8F4 + 0x44·j joints | 0x748 + 0x50·j (translation at +0x14 in both) |
| 0xF54 rootMat | 0x438 |
| 0xF68, 0xF6C, 0xF70 rootX, rootY, rootZ | 0x44C, 0x450, 0x454 |
| 0xF74 localMats | 0x728 + 0x50·j |
| 0x128A airFree | 0x1158 |
| 0x12D0 ogreFreeze | 0x11B0 |
| hand channels | 0x1164.. (README) |

Hit slots do not exist: the single hit info per defender is `0x803700F8` (P1), `0x80373634` (P2): `+0` point, `+0x10` direction s16 × 3, `+0x18` zone.

Globals: `g_fighterDistance 0x800AFF04` → `DAT_8021FD90` (and `DAT_8021F614`, the value bounds compares against next frame); `distAdj` → `DAT_8021FDC0` (distance − 40 per char 0xB or 0x14); frame parity `DAT_8021FDA4`; active mask `DAT_8021FB00` (bit per player).

### Move row fields this subsystem reads (arcade 0x3C bytes at 0x80025E8C, 4,871 rows; PS1 56 bytes)

`+0x00` anim; `+0x04` state; `+0x08` attack u16; `+0x0C` branches; `+0x10` stance slot (crouch stance 0x19, PS1 40); `+0x12` damage + class u16 (PS1 +0x14); `+0x15` anchor byte `== 1` (PS1 flag bit 28); `+0x17` look-at byte; `+0x18` flags u32; `+0x1C` end turn s16 (+0x12); `+0x1E` N (+0x18); `+0x1F, +0x20` air window (+0x19, +0x1A); `+0x21` hold frame (+0x1B); `+0x22` step s16 (+0x16); `+0x28` events (+0x20); `+0x2C` reaction u16 (+0x32); `+0x2E` close u16 (+0x34); `+0x30, +0x31` active window (+0x2D, +0x2E); `+0x32–35` joints; `+0x36` hit freeze (+0x2C); `+0x38` body profile s16 (+0x30).

Flags `+0x18`: bit 0 no blend (PS1 NO_BLEND); bit 1 no forward blend; 0x04 aboutToHit (PS1 bit 10); 0x08 attackAlert (11); 0x10 launch angle, no recovery accumulation (12); 0x20 command buffer (13); 0x40 stick guard (14); 0x80 power (16); 0x100 body adjust (17); sign bit: face command (`FUN_80193F90`).

## 5. Table addresses

"Lead" is the entry of `work/arcade/fight/table_search.json`. All `confirmed` by the code line unless noted.

| Table | PS1 | Arcade | Elements | Read by | Lead |
|---|---|---|---|---|---|
| REACTIONS | 0x80010CE8, 633 × 21 s16 | **0x80011200, 978 × 0x38 bytes** | up to row `+0x2C` max 977; ends 0x8001E7F0 | FUN_8018BB68, FUN_8019F3FC, FUN_8018F318 | 0x800104FC refuted |
| PUSH_TABLES | 0x8001075C (710 s16, indexed) | **0x80010D00, 64 entries of 20 bytes**, read through record pointers | ends at REACTIONS | FUN_80190FF8 | 0x80010D14 is entry 1 |
| LAUNCH_PUSH | 0x80019D2C | 0x8015EDB8, 8 s16, same values | | FUN_80190C78 | confirmed |
| AIR_KINDS | 0x8001A630, 6 rows | **0x8015F704 (offset) / 0x8015F706 (slot), 13 rows** | | FUN_80190A7C, FUN_80190FF8 case 0x1E | none → found |
| FORCED_REACTION | 0x8001DEC0 | none, no reader | | | 0x80017FB4 unsupported |
| THROW_VICTIM_SLOTS | 0x800174C4 | **none** | victim slot = `*(s16*)(0x8001121C + row.+0x2C · 0x38)` (record +0x1C) | FUN_8018F318 | 0x801853DA refuted |
| CLOSE_REACTIONS | 0x800177DC, 58 | **0x8001E7EC** (s16 reaction), 0x8001E7EE (s16 distance); indices 1–51 used | index 0 overlaps the last reaction record, never read | FUN_8018BB68 | 0x8005D8B4 refuted |
| HURT_ZONE_JOINTS | 0x800973DC, 14 s32 | 0x801FE5B4, same values | | FUN_80198BF8 | confirmed |
| BODY_SPHERE_JOINTS | 0x80097364, 8 s32 | 0x801FE53C, same values | | FUN_80198BF8 | confirmed |
| HURT_RADII | 0x80097414 | **pointers 0x801FE5EC**, 22 characters | radii at 0x8015F68C, 0x8015F6A8, 0x8015F6C4 | FUN_8019F3A8 | 0x80011228 refuted |
| BODY_RADII | 0x80097384 | pointers 0x801FE55C, 22 characters | radii at 0x8015F65C, 0x8015F66C, 0x8015F67C | FUN_8019F00C | confirmed |
| HEALTH | 0x80022858, 9 s32 | 0x8017953C, 8 s32 (case 1 of FUN_801B7C50), plus **0x8017955C, 0x8017957C** (case 0) | see section 6 | FUN_801B7C50 | confirmed, the first 8 |
| RECOVERY_TEAM | 0x80022818 | 0x801794FC, 8 s32, same values | | decompile line 27054 | confirmed |
| RECOVERY_SURVIVAL | 0x80022838 | 0x8017951C, 8 s32, same values | | decompile line 27091 | confirmed |
| BUILTIN_ATTACKS, BUILTIN_BLOB | 0x80017C10, 0x80017BDC | **none** (joints inline in the row) | | | 0x80017010, 0x8011D154 false (`inferred`) |
| Zone percent | `FightMath.ZONE_PERCENT` | 0x80010224, 14 s16, same values | | FUN_8018C1E8 | new |
| Sine, cosine | 0x8001E8C4 | 0x80175944, 0x80176144 (5,120 s16 from sine) | | everywhere | exact |
| SQUARE_ROOT | 0x8004B1D8 (SquareRoot0), a copy at 0x800990AC; 192 s16 | 0x801AEC94 | | FUN_801AEC2C | exact |
| rsqrt, ratan | 0x8001A194, 0x8009922C | 0x8021A8A0, 0x80216088 | | VectorNormal, ratan2 | exact |
| REVERSAL_LISTS | 0x80095AB8 | **`PTR_DAT_801FCC44`**: s16 row indices compared through `DAT_80025E8C[idx · 0xF]` (the anim word), −1 ends | | FUN_8018EDE8 | none → found |
| FACE_ATTACK | 0x80095D74 | 0x801FE2EC | | | exact |
| FACE_HIT | 0x80095DA8 | 0x801FE318 (README) | | | 0x80026AA7 refuted |
| Wing tables | 0x80095CAC, 0x80095CC0 | 0x801FCF30, 0x801FCF44 | | FUN_80194458 | confirmed |
| Attachment clamps, axes, records | 0x80096134 (clamps) | 0x801FD2F0, 0x801FD170, 0x801FDC88 | | FUN_8019B6D8 | clamps exact |
| `attachment_limits` | 0x80096144 | not at the lead | | | 0x80025EC4 lies inside the move rows: false |
| euler_slots | 0x8001A330 | none | | | none, no IK |
| limb_basis, skeleton_offsets, limb_offsets | 0x800972D0, 0x800972F0, 0x80097320 | none | | | 0x80026243, 0x8001111C, 0x800275DC false (`inferred`: no reader, no IK code) |
| Joint offsets, parents | KMD rows | model file rows, loaded at 0x8022109C + p·0x1C000 | | FUN_80197790 | |
| Look base angles | 0x4000, 0, 0x4000 | 0x8021F0B0, same | | FUN_80199310 | |
| Effect segment arrays | | 0x802C6C70, 0x802C77B0 | | FUN_801A6A14 | |

### Layout of a reaction record

| Arcade | Type | Meaning | PS1 word |
|---|---|---|---|
| +0x00 | u32, low half used as s16 | push angle | +0x1C |
| +0x04 | pointer | push entry of a hit | +0x1E (index) |
| +0x08 | u32 | angle, no reader found | +0x20 (`UNUSED_ANGLE`; low half is the s16, for example 0x1555, 0xE001) |
| +0x0C | pointer | push entry of a counter hit | +0x22 (index) |
| +0x10 | u32, low half used as s16 | angle when down | +0x24 |
| +0x14 | pointer | push entry when down | +0x26 (index) |
| +0x18 | pointer | push entry of a guard | +0x28 (index) |
| +0x1C, +0x1E | s16 × 2 | front standing, crouching move slots | +0x00, +0x02 |
| +0x20, +0x22 | s16 × 2 | counter | +0x04, +0x06 |
| +0x24, +0x26 | s16 × 2 | side 1 | +0x08, +0x0A |
| +0x28, +0x2A | s16 × 2 | side 3 | +0x0C, +0x0E |
| +0x2C, +0x2E | s16 × 2 | back | +0x10, +0x12 |
| +0x30, +0x32 | s16 × 2 | guard | +0x14, +0x16 |
| +0x34 | s16 | down | +0x18 |
| +0x36 | s16 | down, other | +0x1A |

Slot selection (FUN_80190600, same order as `MoveSystem._hit_select_reaction`): first of a pair if `state & 2`, second otherwise.

**Conversion to the 21-word layout** (`confirmed` by the code reading both, field meanings against the `Reaction` enum): words 0–13 = `+0x1C..+0x37`; word 14 = `+0x00`; word 15 = index(`+0x04`); word 16 = low(`+0x08`); word 17 = index(`+0x0C`); word 18 = `+0x10`; word 19 = index(`+0x14`); word 20 = index(`+0x18`), where `index(p) = (p − 0x80010D00) / 2`. A push entry stays `frames, speed, off[8]`. The 64 entries all occur among the PS1's entries, in other positions. Move slot numbers are in the arcade's numbering.

**Throw records.** There is no `0x1nnn` tag: `+0x2C` max is 977 and nothing tests 0xF000. 412 records (record 0 and 411 others, numbers from 559 up among them) have all four push pointers null and hold a slot in `+0x1C`; FUN_8018F318 reads that slot for a throw victim. So `MoveSystem.throw_victim_start`'s first branch (`t.reactions[value][0]`) serves every arcade row and `THROW_VICTIM_SLOTS` stays empty. A null pointer needs its own converted value: 72 rows with an active window name such a record (68 with damage 0; samples name record 977), and on a hit FUN_80190FF8 would read the push entry through address 0 (see Open).

### Data differences found

- Air kinds, PS1 kind → arcade kind, with equal height offsets: 0 → 0 (slot 0xD56 → 0xE45), 1 → 1 (0xD61 → 0xE50), 2 → 4 (0xD62 → 0xE53), 3 → 6 (0xD63 → 0xE55), 4 → 9 (0xD64 → 0xE58), 5 → 12 (0xD57 → 0xE46). The arcade adds rows 2, 3, 5, 7, 8, 10, 11 (slots 0xE51, 0xE52, 0xE54, 0xE56, 0xE57, 0xE59, 0xE5A).
- `MoveSystem.LAUNCH_AIR_KIND`: 5 on PS1, 12 here. `FighterPhysics.LANDING_SHAKE`: stays kind 1.
- True Ogre's first body sphere is 540 (PS1 480), `body[2][0]`; other radii rows the same. PS1's Gon row (`0x8001A5F8`) has no counterpart; character 17 takes the default row.
- Close reaction table: other indices, other slots, the same (reaction, distance) idea.
- Health: PS1's table has a ninth entry (0x820000); the arcade's handicap table has 8 and `0x8017955C` starts right after it.

## 6. Semantic differences

Each row: PS1 location → arcade location; `.gd` that implements PS1. `C` = confirmed (read both sides), `I` = inferred.

### Frame order

- C. **Bounds run before physics and skeleton.** PS1 FightFrame: skeleton then ArenaBounds. Arcade FUN_8018A988: FUN_80198A48 × 2, FUN_8018C498, FUN_8018B050, FUN_8018B124, FUN_8019F3FC, FUN_801A5B00 (only if both throw states are 0), wind, FUN_8018B388, stage, effects, FUN_8018B430 × 2, FUN_80198BF8 × 2, landing dust inline, FUN_8019EF90, FUN_8018B808 (if `DAT_8021FCD0 < 3`), FUN_8018B91C, FUN_8018B47C × 2, FUN_8018C2DC, FUN_8018C5A4, FUN_8018BB68, FUN_8018CBD8 × 2, voices, input, taps, `+0x4A = +0x48` copy, FUN_8018C340. `.gd`: `FightSimulation` frame order, `Combat.pairwise_distances`, `arena_bounds`.
- C. **Relative angles are computed once, in physics, for both fighters** (FUN_801A0A6C). PS1 computes per fighter, and also in HitApply and MoveStep. Consequence: the damage and move code read angles from the top of the frame's physics. `.gd`: `MoveSystem.relative_angles`, `Combat.hit_apply`.

### Hit detection

- C. **HitTest** 80044304 → FUN_8018B91C; `Combat.hit_test`.
  - Geometry runs for both directions first (`FUN_801A6BF0`, returning a mask), writing the fixed hit info directly.
  - No slots, no `invulnerable` or `active` per fighter (only `DAT_8021FB00 == 3`), no slot 0x898 freeze 30, no forced hits, no throw-mode exclusion.
  - New condition: `attacker.damage != 0 || (defender.health != 0 && defender.aboutToHit == 0)`.
  - Same: low attack (0x10F) vs class 12 jump rule; stepKind 2 adds bit 0; `(attack | bit) & state & 7`; `hitDone`; freeze `row+0x36`; cooldown 4 if `damage != 0 || defender.inAir`; whiff at `row+0x31`.
- C. **HitTestSegments** 80047E54 → FUN_801A6A14: same (segment order, 14 zones, defender cooldown test per segment, first hit wins, point = segment end, direction = end − start as s16). `Combat._hit_segments`.
- C. **SegmentHitsCylinder** 800479A4 → FUN_801A64C0: same, including the overflow-prone 32-bit products (`FightMath.segment_hits_cylinder`, rule `fix_segment_hit_overflow`, so the rule applies to the arcade too).
- C. **Guard check:** `(guard & attack) == 0 || relAngle > 0x3FFF` same; `Combat._classify`.

### Damage (`Combat._classify`, `_damage`, `hit_apply`, `_extra_damage`)

- C. Base damage same: zone scale (`FUN_8018C1E8`), or for a close hit `abs(damage) + abs(damage) / 2`.
- C. Damage 0: arcade sets `guarded = 1` and spawns guard effect 1; PS1 a no-damage slot.
- C. **Counter bonus differs.** Condition same (`defender.damage != 0 && frame < window_first`, or either power timer). `W = window_first`, replaced by `frame` if 0 or below `frame`.
  - Without power, arcade: `e = (|def.damage| · 3 / 10) · frame / W`. PS1: `e = ((|def.damage| · 3 / 10) · 3 / 10) · frame / W`, applied twice.
  - With power, arcade: `e = d · 3 / 10`, `d` = the computed hit damage. PS1: `e = |def.damage| · 3 / 10`.
  - Then `d = e + d · 12 / 10` same.
- C. Air scale same (`· 80 / 100` before any juggle, `/ 2` after; in air or state bit 0x400).
- C. **Chip damage is fractional:** `(damage · 0xA0000) / 100 + 0x20000` in 16.16. PS1 `(damage / 10 + 2) << 16`. Enable `DAT_8021FDA8` (Guard damage setting, `0x8036EC54`) or attacker's power; PS1 `0x800AFF20`.
- C. **Chip KO:** health < 1 → `hitClean = 1` with `guarded` left at 1. PS1 clears `guarded`.
- C. **Extra damage:**
  - Kind 1 of the opponent applies with no `throwState < 0` test.
  - Kind 2 same (own value or own damage).
  - Kind 3 gives health back: value or, as the fallback, the **opponent's** damage; PS1's fallback is the fighter's own damage. It is not counted in `+0xB6`.
- C. **`+0xB6` accumulates** extras (1, 2) and the hit, this frame. PS1 has `lastDamage = |best slot damage|` and `lastExtra` apart. Launch and recovery read it.
- C. `DAT_8021FC4C` is PS1's `no_damage` (0x800958A0): the health is left as it was while it is set. `FUN_8019E690` equals `RoundFlow._round_over` without the Force case.
- C. **KO `+0xAC` is level-triggered**: 1 every frame with health 0 (PS1 only on the edge). The KO replay starts once (`DAT_8021F60C`, FUN_80194F94(other fighter)).
- C. Health clamps to `[0, max]` same.
- C. Practice, Ball, Force rules absent.

### Reactions (`MoveSystem` reaction selection, `FUN_8002EDF8`)

- C. Reaction pointer `+0xF0` refreshed each frame in physics from the opponent's row `+0x2C`, replaced by the close entry at the hit (close test before hit or guard). PS1 sets it at the hit.
- C. HitSelectReaction 8002EDF8 → FUN_80190600: guard branch tests `guard & opp.attack`, not the guarded flag; rest same in order and transitions.
- C. Transitions (FUN_80190FF8, compared to `MoveStartOrAdvance`):
  - 0x23 guard: record +0x18, dir `targetDir + rec[0] − 0x8000`, mode 7, facing aimDir, no recovery setup. Same.
  - 0x25: record +0x14, angle +0x10, mash 0, mode 0xB. Same.
  - 0x26: record +0xC, mode 7, recovery. Same.
  - 0x27–0x2B: record +4; 0x2A uses aimDir; PushRepeat; mode 0xB. Same. `FUN_80192DF8` = PushRepeatCount.
  - Push table frames 8 in all. Same.
- C. `row+0x15 == 1` anchors `pos = root` at the end of the cases. PS1 flag bit 28, same effect.

### Launch, air, juggle (`MoveSystem`, `FighterPhysics._flight`)

- C. AirReactionKind 8002F0E8 → FUN_80190A7C:
  - No special attacker moves (PS1's bank 9 slot 0x241, bank 0x10 slot 0x14A rules).
  - `hitDirY > 0x6D` → kind 1 same.
  - Side quadrants q1 → 9, q3 → 6 (PS1's 4, 3).
  - Late frames: PS1 slot 0xD62 always, 0xD63, 0xD64 after frame 18 → kind 2 unless `|rootY| > 0x3FF` → 0. Arcade slots 0xE53, 0xE54 always; 0xE55, 0xE58 after 18; 0xE56, 0xE59 after 10; 0xE57, 0xE5A after 7 → kind 4 unless `slot != 0xE53 && |rootY| > 0x3FF` → 0.
  - Slot 0xE46 excluded from sides (PS1 0xD58).
  - Nothing in the fight code sets kinds 2, 3, 5, 7, 8, 10, 11: FUN_80190A7C writes only 0, 1, 4, 6, 9, and case 0x1E writes 12; their rows have no writer (open).
- C. LaunchTrajectory 8002F2C8 → FUN_80190C78:
  - Signed `(v + isqrt) / 6`, `t < 1 → 1` (PS1 has an unsigned wrap bug: not here).
  - No lower clamp on `v` (PS1 clamps at −100).
  - New: kinds 3 and 5 push (frames `N − entry`, speed 0x14, dir `targetDir − 0x8000`).
  - Same: airSpeed, kind 1 slam (400, entry 6, speed 0x28), table 8 frames.
- C. Transition 0x24 lacks PS1's `if juggleCount == 0: airVel = 0`.
- C. Flight (FUN_8019F3FC): position integrates, gravity +6 same. `airVelX, airVelZ` are recomputed at the end of FUN_8018C340 (FUN_80192978), only when `curTransition` is 0x1E or 0x24, as `airSpeed · Sin(opp.targetDir) / 0x7FFF`. PS1 does it inside `_flight`, after integrating, every flight frame, from `f.target_dir + 0x8000`. `I`: the same direction by the next integration, unless the flight began by another transition. Landing same; launch kind 0xC.
- C. Class 1 attack: `damage = 0` at the move start. Same.
- C. Recovery FUN_80190900: `+0xB6 + mash / 2` capped at 0x42; 0 from them with flag 0x10. `FUN_80190978` after throws: same formula as PS1.

### Physics (`FighterPhysics.update` and helpers)

- C. **Structure:** a first loop runs slide, step, flight, push, turn, tracking for both fighters; a second loop runs bookkeeping for both. PS1 runs the whole function per fighter, so with the arcade P2 reads P1's `attackAlert` before its decrement.
- C. Tracking modes 0–10 same constants; modes 11, 12 do not exist in `FUN_8019F3FC`. Modes 7, 0xA, 0xB are set by transitions as listed.
- C. Slides, step displacement (side steps, `+0x9A`, cooldown 0x18 in `DAT_8021F060` from case 0x1C), push, recover, `aboutToHit` (minus Gon), landed rule same. `_slide`, `_step_displacement`, `_push`, `_recovery`, `_about_to_hit`.
- C. Absent: slide to point, Gon, Ball, forced hits, `noLookAt`, `_ball_drift`.
- C. Landing dust moved from physics to the fight frame (`+0xAB` → FUN_801AE4B4(root) and shake 0).
- C. **Guard:** the human test is `+0x34A < 3 && DAT_8021FC70 != 0` (`DAT_8021FC70` = setting byte `0x8036EC55`, Neutral guard); PS1 `humanGuard = !isCpu` outside mode 5. `_guard_state`.
- C. Face shape: extra condition `row+0x32 < 0xC`. `_face_shape`.

### Body collision (`Combat.body_sphere_profile`, `body_separate`, `_overlap_solve`)

- C. BodySphereProfile: case numbers shifted (arcade 5, 6 = PS1 5; 7 = PS1 6; 8 = PS1 7); FUN_8019EF90: if P1's profile is 6, P2 uses 6 too; final dropping same (flag 0x100).
- C. BodySeparate 8004401C → FUN_8018B808 + FUN_801A5B68:
  - Skipped if either throw state is nonzero; gate `DAT_8021FCD0 < 3`.
  - No pair-distance 3000, active or invulnerable test, no `bodyContact` flags.
  - Branch conditions 0x33 and 0x34 read `bodyPush != 0` directly (FUN_8018FB3C), which PS1 expresses through `+0xD5`.
  - Split `/ 2` truncates toward zero (PS1 `>> 1`, floor): `f.body_push_x = px if charging else px >> 1` needs `div_trunc` in arcade mode.
  - Roots saved (SavePlayerPosition) only without throw.
  - Same: deepest overlap, charge rule (`FRONT_REACH` 200, `FRONT_NEAR` 500, `CHARGE_OVERLAP` 400, `HEIGHT_GAP` 299), weights by movement, axis choice.

### Bounds, walls, ring-out (`Combat.arena_bounds`)

- C. **Arcade (FUN_8018B124), the whole rule:** if last frame's distance `> 0x1CFF`, for each fighter: `d = sqrt(saved opp root − own root)`; if `last distance <= d`: `pos += saved own root − own root`, `root = saved own root` (undo this frame's retreat). Then save both roots at `0x8021FE00`, `0x8021FE08` (stride 0x10) and compute the distance with ISqrt.
- C. Absent: ±300000 clamp, the 0x1E00 pull, `bound_ramp`, throw link, walls, ring-out. It runs on the previous skeleton's roots. PS1 `placed_x, placed_z` are the same save but read later.
- C. `dist_adj` same: distance − 40 per big character (0xB, 0x14).

### Throws (`MoveSystem`, `ThrowVictimStart`)

- C. MoveStartAll: same parity logic; no pairing fields (`throw_partner` is always the other fighter).
- C. Victim start 8002D9B0 → FUN_8018F318: slot from the reaction record +0x1C (no table).
- C. **Transitions 0x1F, 0x20, 0x21 are all "thrower"** in the arcade. PS1 has only 0x21; 0x1F and 0x20 fall in its default restart. Quadrant from `opp.facingQuadrant` (PS1's `oppQuadrant`, computed in PS1's relative angles). While the fighter is in a throw (`throwState < 0`): heading = heading − 0x8000 and pos = opponent's root; PS1 heading = `opp.facing`, also with row flag 0x800.
- C. Victim 0x22: `+0xA1` rule same; `throwState >= 0`: `heading −= 0x8000`, `pos = root`, `FUN_801A1A80` (voice stop). PS1's flag 0x800 case is absent. Recovery FUN_80190978 same.
- C. Close: same via `DAT_8021FD90`. Reversals FUN_8018F424: `damage / 2 + 25` same; PS1's char 0x11 exclusion is gone.

### Moves, events, misc

- C. MoveStep FUN_8018F528: same class structure; no `attackClass = 1` when `throwState > 0`; no distance or angle recompute.
- C. KO collapse (FUN_8018C340) is always PS1's `DAT_800AFF5B` branch: stance 3 or 0x19, or a non-down move without an air window → slot 0xE5C.
- C. Events FUN_8018C5A4: same numbering (1–3 shake, 4 dust, 6–10 effects, 0xB–0xD extra, 0xE–0x3D hands; hand index 0 → 3).
- C. TransitionRemap same.
- C. Health start values (FUN_801B7C50, by mode `_DAT_80374F18`): 0 → `0x8017955C` if `DAT_8021FB74 == 1`, else `0x8017957C`, indexed by the setting `DAT_8021FC54` (when `DAT_80374F32 == 2`) or `DAT_8021FDD0`; 1 → `0x8017953C` indexed by the u16 at `0x80374F52 + player · 4`; 2–6 → constants 0xAA0000, 0x6E0000, 0x8C0000, 0xC80000, 0x7D0000. `.gd`: where `tables.health` is read.
- C. Stage friction: push entries are read per frame by the same table walk; no stage-dependent friction on either side (`I` for the arcade's stages).

## Harness results

`work/arcade/fight/pose_check.py` hooks the end of FUN_80198298 and compares RAM with the formulas of section 3; costume 0 of characters 0 and 1, seed 1, random pads, each run stopped by its time limit.

| Check | Run A (698 frames) | Run B (472 frames, final formulas) |
|---|---|---|
| Root rotation, root translation | 1,334 / 1,334 each | 882 / 882 each |
| Local rotation, no blend (head excluded) | 14,758 / 14,758 | 11,682 / 11,682 |
| Local rotation, blend (head excluded) | not valid, see below | 3,312 / 3,312 |
| Head local equal to the plain formula, no blend | 587 of 839 | 461 of 675 |
| Head local equal to the plain formula, blend | not valid | 124 of 207 |
| World rotation, world translation | 24,012 / 24,012 each | 15,876 / 15,876 each |
| Segment ends, explicit starts | 547 / 547, 118 / 118 | 112 / 112, 50 / 50 |
| Blend modes seen (fighter frames) | 0: 839, 1: 193, 3: 302 | 0: 675, 1: 73, 2: 6, 3: 128 |

- Run A's blend check used an earlier version of the formula and missed by about 1 per entry; the formula in section 3 replaced it, and run B has no difference. Run A is valid for everything that does not depend on it.
- The head rows differ because the look-at overwrites joint 2's local, as expected. The look-at's angles are not checked.
- Not reached: `airPhase` 1 and 2 (always 0), throw frames with a negative `throwState`, joints 18–23 (absent in these costumes), True Ogre, the first-frame and `b == 0` start points.

## Open

1. Who sets air kinds 2, 3, 5, 7, 8, 10, 11 (FUN_80190C78 has a push for kinds 3 and 5, FUN_80190A7C does not produce them). `+0x7C` has no other writer in the decompile: maybe unused rows, or written by a pointer the search missed.
2. Role of FUN_8018CBD8 and the list `PTR_DAT_801FF054` (FUN_801BCB0C writes a message buffer at `0x80277538`); no effect on the fight records seen.
3. Joint 19 in bank 14 for char 0x14, and joint 21 in bank 14: attachment or stale values. Needs a run of those rows in the harness with True Ogre (not run here). Character 0xF in bank 14 is a weapon point owner: which costume.
4. `airPhase` 1 and 2 and the root scale with a negative `throwState` are from reading only (see "Harness results"); a run with throws and launches must confirm them. True Ogre's sway and the attachments' rows are compared in every fight trace since the rows run in the simulation (`arcade_cpu_vs_true_ogre`, `arcade_cpu_ogre`, `arcade_cpu_yoshimitsu`).
5. The `start` of a segment with `b == 0` on a move's first frame, and the stale value across moves: from reading, not seen in a run.
6. Null push pointers: 72 rows with an active window name a record whose four pointers are null. Whether any of them can reach FUN_80190600 with a hit, and what address 0 holds on System 12 if so. Until then the conversion has no proven value for null (a push entry of 0 frames is the safe guess).
7. Bug #61's case (null stance row in a forward blend) and `FUN_8018ED1C` on missing slots.
8. `FUN_80193708`, `FUN_80192ECC`, `FUN_8019A6D0` after compose were not read in depth (`inferred` not simulation state).
9. `FUN_80195DA8` family: the replay's pose fields were mapped by shape. A replay must also store `+0x1AC8`, `+0x1830`, `+0xB5` as they do.
10. `+0x34A` values were not traced to their writer (only readers: `< 3` human). Left to the CPU report.
11. PS1 `BranchCondition` cases 0x33, 0x34 were compared through the remake's `body_contact`, not the PS1 decompile. FUN_80190240, FUN_80190334 and FUN_8018FB3C in detail are left to the [moves.md](moves.md).
12. `+0x330` when BodySeparate is skipped (a throw, or camera phase 3 and up): whether old values stay readable by those conditions.
13. Which rows use thrower transitions 0x1F and 0x20; PS1 restarts on them by default.
14. Golden traces: no arcade trace exists for combat, so the differences above are by reading; `tools/research/arcade_fight_harness.py` can produce them (the pads' bit layout must be established first: the input routine `FUN_8018CD30` reads `0x1F083140`, `0x1F083142`).
