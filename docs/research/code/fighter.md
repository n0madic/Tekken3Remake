# Fighter structure

Each fighter is a `0x188C`-byte record. Fighters 0 and 1 live at `0x800A96F0` and `0x800AAF7C`; game mode 8 uses a third record at `0x800AC808`. `FighterOpponent` (`0x80045EB0`) and `FighterOpponentIndex` (`0x80045E50`) return the fighter that a routine should treat as the opponent: the throw partner while `inThrow` is set, else the last attacker when this move was interrupted by a hit, else the last fighter this move touched, else the default opponent (`+0x20`).

Conventions used by all fields:

- Angles are 16-bit binary angles (`0x10000` = 360°, `0x4000` = 90°). `sin`/`cos` come from 4,096-entry tables (`g_sinTable`, `g_cosTable`) with 4,096 = 1.0.
- Positions are model units in a right-handed world with **y pointing down**: the floor is `y = 0` and airborne fighters have negative `y`.
- `posX/Y/Z` is the **anchor** of the running move; the displayed root (`rootX/Y/Z`) is the anchor plus the animation's root displacement rotated by `facing` (see [moves.md](moves.md#root-motion)).
- A "move" is a 56-byte row of the [motion bank](../formats/divmot-banks.md); the fighter always has a running move (`poseMove`) and optionally a pending one (`moveRow`).

The table below is generated from [`tools/ghidra/fighter_fields.tsv`](../../../tools/ghidra/fighter_fields.tsv) by `python3 tools/ghidra/gen_structs.py`, which also writes the `Fighter` type used by the Ghidra annotations. Every offset that the executable or an overlay reads or writes through a typed fighter pointer is in the table; the gaps are only reached through raw offsets inside routines that are ported bit-exactly in `tools/research` (so the ports reproduce them), or not used. Names are descriptive; each has been checked against at least one reader and one writer in the code, and meanings that rest on a single use are phrased as such.

<!-- BEGIN generated fields -->
| Offset | Type | Name | Meaning |
|---:|---|---|---|
| `+0x0000` | `s32` | `posX` | anchor of the running move (root = anchor + rotated animation displacement) |
| `+0x0004` | `s32` | `posY` |  |
| `+0x0008` | `s32` | `posZ` |  |
| `+0x000C` | `s16` | `tiltX` | root rotation x (root matrix uses -tiltX) |
| `+0x000E` | `s16` | `facing` | 16-bit angle |
| `+0x0010` | `s16` | `tiltZ` | root rotation z (root matrix uses -tiltZ) |
| `+0x0012` | `s16` | `playerIndex` | 0/1, VRAM/CLUT offsets |
| `+0x0014` | `s16` | `costumeKey` | charId*4 + costume: index into g_charRecords |
| `+0x0016` | `s16` | `bankType` | motion bank type (character record +9) |
| `+0x0018` | `s16` | `charId` | selection index 0-22 (20 = True Ogre, 21+ Tekken Force enemies) |
| `+0x001A` | `s16` | `voiceSet` | character record +8: index into g_charVoices |
| `+0x001C` | `s16` | `costumeSlot` | 0..51 |
| `+0x001E` | `u8` | `index` | fighter index 0/1 (2 = third fighter in mode 8) |
| `+0x001F` | `u8` | `curOppIndex` | the opponent currently faced (FightFrame, FUN_8002BFCC); in mode 8 it follows target changes (side flag, Force AI) |
| `+0x0020` | `u8` | `oppIndex` | default opponent index |
| `+0x0021` | `u8` | `throwPartner` |  |
| `+0x0022` | `u8` | `lastAttacker` | index of the fighter whose hit was applied |
| `+0x0023` | `u8` | `lastHitTarget` |  |
| `+0x0024` | `s16` | `rootDx` | root displacement from animation |
| `+0x0026` | `s16` | `rootDy` |  |
| `+0x0028` | `s16` | `rootDz` |  |
| `+0x002A` | `s16` | `targetDir` |  |
| `+0x002C` | `s16` | `heading` | body heading (16-bit angle); facing follows it |
| `+0x002E` | `s16` | `headingDelta` | heading - targetDir |
| `+0x0030` | `s16` | `relAngle` | abs(headingDelta): 0 facing the opponent, 0x8000 back turned |
| `+0x0032` | `s16` | `facingQuadrant` | own heading vs opponent direction: 0 front, 1/3 sides, 2 back |
| `+0x0034` | `s16` | `aimDir` | targetDir or targetDir+0x8000, whichever is nearer the heading (updated beyond 0x200 units) |
| `+0x0036` | `s16` | `trackAccum` |  |
| `+0x0038` | `s16` | `oppToSelfDir` | direction from opponent to self |
| `+0x003A` | `s16` | `oppHeading` |  |
| `+0x003C` | `s16` | `oppHeadingDelta` |  |
| `+0x003E` | `s16` | `oppRelAngle` | abs(oppHeadingDelta) |
| `+0x0040` | `s16` | `oppQuadrant` | opponent heading vs direction to self: 0 facing me, 1/3 sides, 2 back turned |
| `+0x0042` | `s16` | `oppAimDir` |  |
| `+0x0044` | `s16` | `roundWins` | rounds won in the match; +1 per round won, both on a draw (FUN_8003E7C4); compared with the rounds to win 0x800AE2C4; saved and restored around a fighter reload (FUN_8002A5D8/FUN_8002A634) |
| `+0x0046` | `s16` | `roundWon` | round result (FUN_8003E7C4): 1 won, −1 lost; a draw gives both −1, or 1 to a side that reaches the rounds to win |
| `+0x0048` | `s16` | `winPose` | win-pose variant, 1 + frame parity (FUN_8003EB60); after a time-out the loser's −1 (both 0 when tied, FUN_8003EBF4); the round end waits until a positive variant's move has played |
| `+0x004C` | `void*` | `rootMove` | move row driving root motion |
| `+0x0050` | `s16` | `rootFrame` |  |
| `+0x0054` | `void*` | `poseMove` | move row driving the pose |
| `+0x0058` | `s16` | `poseFrame` |  |
| `+0x005A` | `s16` | `eventFrame` | the pose frame when the frame events last ran (MoveEvents runs the events after it up to the pose frame; blend source frame = value − 1) |
| `+0x005C` | `s16` | `moveFrame` | frames since the move started (1 at start unless the frame counter is kept) |
| `+0x005E` | `s16` | `damage` | damage of the running move (0 = not an attack) |
| `+0x0060` | `u32` | `state` | move +0x04: bits 0-2 posture (crouch/stand/down), 3-4 guard, 11-15 class |
| `+0x0064` | `u16` | `attack` | move +0x08: bits 0-2 postures hit, 3-4 guards that block, high byte level id |
| `+0x0066` | `u16` | `guard` | state bits 3-4 while guarding is possible, else 0 |
| `+0x0068` | `u8` | `attackHi` | attack >> 8: 1 low, 2 mid, 4 high, 6 unblockable/ground, 8 throw |
| `+0x0069` | `u8` | `stateClass` | state bits 11-15 (12 = jump) |
| `+0x006A` | `s16` | `holdFrames` | frames to hold the last pose frame (-1 none) |
| `+0x006C` | `s16` | `branchWindow` | remaining frames of the matched branch window |
| `+0x006E` | `s16` | `frameStep` | +1 forward, -1 playing backwards |
| `+0x0074` | `s16` | `throwState` | 0 idle; >0 thrower step count; <0 throw victim |
| `+0x0076` | `s16` | `hitFreeze` | freeze frames left (pose does not advance) |
| `+0x0078` | `s32` | `slideStepX` |  |
| `+0x007C` | `s32` | `slideStepZ` |  |
| `+0x0080` | `s16` | `reactChain` | counts consecutive reaction moves (0x400 flag chains) |
| `+0x0082` | `u8` | `slideState` | 1 armed, 2 sliding (transitions 0x10/0x12/0x13) |
| `+0x0083` | `u8` | `hitDone0` | this move already hit fighter 0 |
| `+0x0084` | `u8` | `hitDone1` | this move already hit fighter 1 |
| `+0x0085` | `u8` | `hitDone2` | this move already hit Tekken Force fighter 2 (HitTest, index - 2) |
| `+0x0086` | `u8` | `hitDone3` | the same for fighter 3; also set to 1 when a queued move starts |
| `+0x0087` | `u8` | `wasHitThisMove` |  |
| `+0x0088` | `u8` | `contactThisMove` |  |
| `+0x0089` | `u8` | `guardedPrev` | copy of +0xCF at move start |
| `+0x008A` | `u8` | `inReaction` | copy of +0xD0 at move start |
| `+0x008B` | `u8` | `branchKind` | 1 reaction, 2 input branch, 3 look-ahead branch, 4 move end |
| `+0x008C` | `u8` | `condFlagUsed` | set by branch conditions 0x3A-0x3C |
| `+0x008E` | `s16` | `launchArmed` |  |
| `+0x0090` | `s16` | `airKind` | 0-5, row of 0x8001A630 (ground offset, air move slot) |
| `+0x0092` | `s16` | `ballistic` | 1 while following a launch trajectory |
| `+0x0094` | `s16` | `juggleCount` | air hits taken during the current launch |
| `+0x0096` | `s16` | `groundOffset` |  |
| `+0x0098` | `s16` | `airSpeed` | horizontal launch speed |
| `+0x009A` | `s16` | `airVelX` |  |
| `+0x009C` | `s16` | `airVelY` |  |
| `+0x009E` | `s16` | `airVelZ` |  |
| `+0x00A0` | `s16` | `curSlot` | move slot of the running move |
| `+0x00A2` | `s16` | `curTransition` | transition code that started the running move |
| `+0x00A4` | `s32` | `slideTargetX` | point reached in 16 frames when slideToPoint is 1 (no writer of slideToPoint=1 in the code) |
| `+0x00A8` | `s32` | `slideTargetZ` |  |
| `+0x00AC` | `s32` | `oppStartX` | opponent root at move start |
| `+0x00B0` | `s32` | `oppStartZ` |  |
| `+0x00B4` | `u8` | `attackSegCount` | 1 or 2 joint pairs in the move attack descriptor, 0 without an active window |
| `+0x00B5` | `u8` | `crouchMove` | move flag 0x2000 |
| `+0x00B6` | `u8` | `stepKind` | 1/2 from transitions 0x1A/0x1B |
| `+0x00B7` | `u8` | `attackClass` | move +0x14 bits 14-15 |
| `+0x00B8` | `u8` | `airPhase` | root follows animation: 0 xyz, 1 none (launched), 2 y only (slide) |
| `+0x00B9` | `u8` | `trackMode` | 0..12, see transitions |
| `+0x00BA` | `u8` | `moveFlagBA` | cleared at move start and at reset |
| `+0x00BB` | `u8` | `moveFlagBB` | cleared at reset |
| `+0x00BC` | `u8` | `skipStepPhysics` | cleared at move start; FighterMovePhysics skips its step handling while set |
| `+0x00BD` | `u8` | `attackPending` | 1 while the running move's damage is still to come or the opponent's power timer runs |
| `+0x00BE` | `u8` | `anchorDirty` |  |
| `+0x00BF` | `u8` | `slideToPoint` |  |
| `+0x00C0` | `u8` | `resetFlagC0` | cleared at reset; no reader found |
| `+0x00C1` | `u8` | `applyEndTurn` | add move +0x12 to heading at next move start |
| `+0x00C2` | `u8` | `invulnerable` |  |
| `+0x00C3` | `u8` | `active` |  |
| `+0x00C4` | `u8` | `inThrow` |  |
| `+0x00C5` | `u8` | `isCpu` | fighter is driven by the CPU AI (InputSource) |
| `+0x00C6` | `u8` | `sideFlag` | mirrors stick left/right |
| `+0x00C7` | `u8` | `fixedFacing` |  |
| `+0x00C8` | `u8` | `fixedFacingSide` |  |
| `+0x00C9` | `u8` | `noLookAt` | disables the head look-at (and Gon's eyes); in mode 8 set for CPU and fixed-facing fighters |
| `+0x00CA` | `u8` | `humanGuard` | set for human fighters outside mode 5; moves with state bit 8 keep their guard only when set |
| `+0x00CC` | `s16` | `lastExtraDamage` | HitExtraDamage of the last HitApply |
| `+0x00CE` | `u8` | `gotHit` | hit (or guarded) this frame |
| `+0x00CF` | `u8` | `guarded` | last applied hit was guarded |
| `+0x00D0` | `u8` | `hitClean` | last applied hit connected |
| `+0x00D1` | `u8` | `contact` | own attack made contact this move |
| `+0x00D2` | `u8` | `whiffed` | active window ended without contact |
| `+0x00D3` | `u8` | `counterHit` | last applied hit was a counter hit |
| `+0x00D4` | `u8` | `closeHit` | last applied hit used the close-range entry (+0x34) |
| `+0x00D5` | `u8` | `bodyContact` | pushed apart by BodySeparate this frame (conditions 0x33/0x34); cleared by FUN_80043F40 |
| `+0x00D6` | `u8[3]` | `bodyContactWith` | per other fighter index |
| `+0x00D9` | `u8` | `noBodyPush` | set by ArenaBounds when crossing the Tekken Ball court; body separation skipped when both are set |
| `+0x00DA` | `u8` | `moveChanged` | new move differs from the previous one |
| `+0x00DB` | `u8` | `inAir` | move air window [+0x19,+0x1A] or juggled (+0x94) |
| `+0x00DC` | `u8` | `landedA` |  |
| `+0x00DD` | `u8` | `landedB` |  |
| `+0x00DE` | `u8` | `ko` |  |
| `+0x00DF` | `u8` | `aboutToHit` | damage move within 3 frames of its first active frame |
| `+0x00E0` | `u8` | `tapLP` | LatchButtonTaps: LP newly pressed; all three cleared once no punch button is newly pressed (conditions 0x3A-0x3C) |
| `+0x00E1` | `u8` | `tapRP` |  |
| `+0x00E2` | `u8` | `tapBoth` | LP and RP held with one of them newly pressed |
| `+0x00E3` | `u8` | `activeSegs` | attack segments live this frame (0 outside [+0x2D,+0x2E]) |
| `+0x00E4` | `u8` | `extraKind` | HitExtraDamage mode |
| `+0x00E5` | `u8` | `blendActive` |  |
| `+0x00E6` | `u8` | `forcedHit` |  |
| `+0x00E7` | `u8` | `forcedHitIn` |  |
| `+0x00E8` | `s16` | `lastDamage` | abs(damage) of the last applied hit |
| `+0x00EA` | `s16` | `damageOverride` | used instead of move damage (reversals) |
| `+0x00EC` | `s16` | `extraDamage` |  |
| `+0x00EE` | `s16` | `hitFreezeIn` | freeze frames received from the attacker move byte +0x2C |
| `+0x00F4` | `u32` | `distAdj` | distance to opponent minus size adjustment |
| `+0x00F8` | `u32` | `dist` | distance to opponent |
| `+0x00FC` | `s32` | `dirX` | x offset to the opponent (PairwiseDistances; ×10 on the fallback path) |
| `+0x0100` | `s32` | `dirZ` | z offset to the opponent (0 on the fallback path) |
| `+0x0104` | `s16` | `hitCooldown` | no hit tests while > 0 |
| `+0x0106` | `s16` | `pushFrames` |  |
| `+0x0108` | `s16` | `pushSpeed` |  |
| `+0x010A` | `s16` | `pushTableFrames` |  |
| `+0x010C` | `s16` | `pushDir` |  |
| `+0x0110` | `void*` | `pushTable` |  |
| `+0x0114` | `s16` | `turnFrames` |  |
| `+0x0116` | `s16` | `turnStep` |  |
| `+0x0118` | `s16` | `recoverMash` | decreased by button presses |
| `+0x011A` | `s16` | `recoverFrames` |  |
| `+0x011C` | `s16` | `attackAlert` | 9 frames after a move with flag 0x800 starts |
| `+0x0122` | `s16` | `powerTimer` | 120 after move flag 0x10000; disables guard, forces counter hits |
| `+0x0124` | `s16` | `pushRepeat` |  |
| `+0x0126` | `s16` | `pushRepeatTimer` |  |
| `+0x0128` | `s16` | `stepCooldown` | blocks branch rows with flag 0x1C |
| `+0x012C` | `s32` | `placedX` | anchor saved by FUN_800431B4 when the fighter is placed for a round (ArenaBounds pull-back target) |
| `+0x0130` | `s32` | `placedZ` |  |
| `+0x0134` | `s16` | `prevPoseFrame` |  |
| `+0x0136` | `s16` | `prevSlot` |  |
| `+0x0138` | `s16` | `prevMoveUnk10` |  |
| `+0x013A` | `s16` | `pushRepeatTrans` |  |
| `+0x013C` | `u8[88]` | `hitSlots` | 2 x 0x2C hit records (fields from +0x1C) |
| `+0x0194` | `void*` | `bestHitSlot` |  |
| `+0x0198` | `s16` | `entryFrame` |  |
| `+0x019A` | `s16` | `transition` |  |
| `+0x019C` | `s16` | `transBit7` |  |
| `+0x019E` | `s16` | `transBit6` |  |
| `+0x01A0` | `s16` | `moveSlot` | current move slot |
| `+0x01A4` | `void*` | `moveRow` | current move row |
| `+0x01A8` | `void*` | `reaction` | reaction record |
| `+0x01AC` | `u8[96]` | `attackSegs` | 4 x 24-byte segments |
| `+0x020C` | `u8[280]` | `hurtZones` | 14 x 20-byte cylinders |
| `+0x0324` | `u8[128]` | `bodyPoints` | 8 x 16-byte points |
| `+0x03A4` | `s32[3]` | `prevHurtZone` | copy of the first hurt-zone words from the previous CollisionShapesUpdate |
| `+0x03B8` | `s32` | `prevRootX` | root of the previous frame (FighterVelocity) |
| `+0x03BC` | `s32` | `prevRootY` |  |
| `+0x03C0` | `s32` | `prevRootZ` |  |
| `+0x03C4` | `s32` | `velX` |  |
| `+0x03C8` | `s32` | `velY` |  |
| `+0x03CC` | `s32` | `velZ` |  |
| `+0x03D0` | `s32` | `atkDirX` | direction of first attack segment |
| `+0x03D4` | `s32` | `atkDirY` |  |
| `+0x03D8` | `s32` | `atkDirZ` |  |
| `+0x03DC` | `s32` | `hitDirX` | attacker atkDir copied on hit |
| `+0x03E0` | `s32` | `hitDirY` |  |
| `+0x03E4` | `s32` | `hitDirZ` |  |
| `+0x03E8` | `s32` | `bodyPushX` | BodySeparate correction added to anchor and root |
| `+0x03EC` | `s32` | `bodyPushY` |  |
| `+0x03F0` | `s32` | `bodyPushZ` |  |
| `+0x03F4` | `s32` | `health` | 16.16 fixed |
| `+0x03F8` | `s32` | `healthMax` |  |
| `+0x03FC` | `s32` | `carriedHealth` | health carried into the next round when 0x800AFF59 is set (FUN_8002BFCC) |
| `+0x0400` | `s16` | `healthLeft` | health in 1/4096 of the maximum at the round result (FUN_8003E6D0); cleared at reset |
| `+0x0402` | `u16` | `inDir` | one-hot direction 1 << (d + 4) |
| `+0x0404` | `u16` | `inPressed` | buttons pressed this frame |
| `+0x0406` | `u16` | `inHeld` | buttons held |
| `+0x0408` | `u16` | `scriptInput` | scripted input word (input mode 2: demo, practice dummy) |
| `+0x040C` | `s32` | `inHistIndex` |  |
| `+0x0410` | `s32` | `cmdCount` | command-buffer entries (at most 9) |
| `+0x0414` | `s32` | `cmdRead` | command-buffer read count |
| `+0x0418` | `s32` | `cmdMergeTimer` | presses within 3 frames merge into the last entry |
| `+0x041C` | `u8[60]` | `inHistory` | pressed << 4 / direction |
| `+0x0458` | `u8[10]` | `cmdBuffer` | entries 1-9: held << 4 / direction while a move with flag 0x2000 runs |
| `+0x0462` | `u16[60]` | `inPressedHist` | raw pressed pad words of the last 60 frames (ring, index +0x40C) |
| `+0x04DC` | `s32[4]` | `pressCount` | presses of LP, RP, LK, RK within the 60-frame window |
| `+0x04EC` | `s16` | `scaleBase` | model scale, 4096 = 100% |
| `+0x04EE` | `s16` | `scale` |  |
| `+0x04F0` | `FighterPart[22]` | `parts` |  |
| `+0x08B0` | `u8[68]` | `rootJoint` |  |
| `+0x08F4` | `u8[1632]` | `joints` | 24 x 0x44 joint blocks |
| `+0x0F54` | `u8[20]` | `rootMat` | root rotation (MATRIX rotation part) from tilt and facing |
| `+0x0F68` | `s32` | `rootX` | world root position |
| `+0x0F6C` | `s32` | `rootY` |  |
| `+0x0F70` | `s32` | `rootZ` |  |
| `+0x0F74` | `u8[576]` | `localMats` | 18 x 32-byte local joint matrices |
| `+0x11B4` | `u8[32]` | `attachLocal` | local joint rotation of the first attached part (parts 18+, FighterComposeJoints) |
| `+0x1274` | `void*` | `pssdw` |  |
| `+0x1278` | `s16` | `screenX` |  |
| `+0x127A` | `s16` | `screenXCopy` | screen x stored by FighterDrawParts for bank-type 11 fighters |
| `+0x128A` | `u8` | `airFree` | airborne and not in a reaction (FighterMovePhysics) |
| `+0x128B` | `u8` | `setupFlag128B` | cleared by FighterSetupParts |
| `+0x12D0` | `u8[4]` | `ogreFreezeFlags` | set while in hit freeze against bank 14 (Ogre), else cleared (FighterMovePhysics) |
| `+0x12D4` | `u8[4]` | `composeFlags` | cleared by FighterComposeJoints each frame |
| `+0x13B0` | `u8[544]` | `prevLocalMats` | 17 x 32-byte local matrices of the previous frame (slots 1-17) |
| `+0x15F0` | `u8[544]` | `blendDelta` | 17 x 32-byte rotation deltas (9 s16 each) for motion blending |
| `+0x1810` | `s16` | `prevRootDx` |  |
| `+0x1812` | `s16` | `rootDyBlended` |  |
| `+0x181C` | `s32` | `blendMode` | 0 none, 1 decay from previous pose, 2 blend into pending branch, 3 blend into stance |
| `+0x1820` | `s32` | `blendModeB` | cleared together with the blend mode (FUN_8003C4AC) |
| `+0x1824` | `void*` | `lastPoseMove` | pose move of the previous displayed frame (blending) |
| `+0x182C` | `s32` | `lastPoseFrame` | pose frame of the previous displayed frame (blending) |
| `+0x1868` | `s16[3]` | `blendRootDelta` |  |
| `+0x186E` | `s16` | `blendWeight` | 4096 * counter / frames |
| `+0x1870` | `s32` | `blendFrames` |  |
| `+0x1878` | `s32` | `blendCounter` |  |
| `+0x187C` | `void*` | `blendSrcMove` |  |
| `+0x1880` | `void*` | `blendDstMove` |  |
| `+0x1884` | `u8` | `blendSrcFrame` |  |
| `+0x1885` | `u8` | `blendDstFrame` |  |
| `+0x1886` | `s8` | `aiSlot` | AI record slot, -1 without one (AiInitRound) |
| `+0x1887` | `s8` | `aiTarget` | index of the fighter the AI targets (AiInitRound) |
| `+0x1888` | `u8` | `keepLight` | set while the body burns: back colour black (FUN_8003A564), FUN_8003A3B8 skipped |
<!-- END generated fields -->
