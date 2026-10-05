# Animation streams and the pose pipeline

Every move row in a [motion bank](divmot-banks.md) points to an animation stream. The stream stores up to 49 independent scalar channels sampled per frame (the game runs fights at one animation frame per display frame). Animation is **character-independent**: it drives a normalized skeleton with inverse kinematics for the limbs, and each model supplies its own joint offsets.

Status: the channel stream format and the pose-to-matrix pipeline (FK and IK) are `confirmed` bit-exact: both are reimplemented in Python and compared with the game's routines in the [CPU harness](../tooling.md).

| Routine (Japan Rev.1) | Role |
|---|---|
| `AnimDecodeRoot` `0x80038C14` | Channels 0–2 → root displacement (fighter `+0x24`). |
| `AnimDecodePose` `0x80038DA0` | Channels 0–48 → pose vector (`0x800A8AB0`). |
| `AnimSplineSample` `0x80038A1C` | Keyed channel evaluation. |
| `AnimScaleRoot` `0x80038BC4` | Multiplies root displacement by the model scale (`+0x4EE`). |
| `PoseBuildMatrices` `0x8003AF64` | Pose vector → 18 local joint rotations (FK + IK). |
| `EulerToMatrix` `0x8003A58C` | `Rz(z)·Ry(y)·Rx(x)` from three 16-bit angles. |
| `IkLimbTarget` `0x8003BC7C`, `IkSolveLimb` `0x8003BEFC` | Two-bone limb solver. |
| `FighterComposeJoints` `0x8003B220` | Local matrices → world matrices per part. |

## Stream layout

```text
u16 head                 # low byte: frame count N (1..255); high byte: key count of channel 0
u8  count[48]            # key counts of channels 1..48
s16 keys[...]            # channel 0 keys, then channel 1, ... (sum of counts)
```

The header is 25 `u16` words (50 bytes). Channel `c`'s keys follow those of channel `c − 1`. `AnimDecodeRoot` reads only channels 0–2 but uses the same layout.

### Sampling a channel

For a 0-based frame `f` clamped to `0..N−1`, **odd-numbered channels are stored time-reversed**: they are sampled at `f' = N − 1 − f`; even channels at `f' = f`. With `k` keys:

| Keys `k` | Value before doubling |
|---|---|
| 0 | 0 |
| 1 | `keys[0]` |
| 2 | `u16(keys[0]) + (keys[1]·f' >> 5 if N > 9 else keys[1]·f')` (linear) |
| `N` | `keys[f']` (one key per frame) |
| other | cubic B-spline (below) |

The decoded value is doubled and truncated to `s16`. Rotation channels are therefore 16-bit angles (65536 = 360°); position channels are model units.

### Keyed channels (B-spline)

A keyed channel is a base value followed by delta keys:

```text
s16 base
s16 key[k−1]:  delta = (key >> 5) << shift,  gap = (key & 31) + 1 frames
```

`shift` is 1 for channels 0–14 (positions) and 5 for channels 15–48 (angles) (EXE table `0x80097048`). Control points are `P[-1] = P[0] = base`, `P[i+1] = P[i] + delta_i`; knots sit at cumulative gaps, and the last knot must equal `N − 1`. The value at a local time inside a segment is

```text
P[i] + (wA·(P[i−1] − P[i]) + wB·(P[i+1] − P[i]) + wC·(P[i+2] − P[i])) >> 16
```

with weights from 16-bit tables in the EXE (`0x80096D40`, `0x80096E40`, `0x80096F42`, `0x80097044`) indexed by a byte table keyed on segment length and local time (`0x80096B1F + 32·len + t` for `len ≤ 16`, else `0x80096F60 − 32·len − t`). The tables are the uniform cubic B-spline basis (at `t = 0`: 1/6, 4/6, 1/6 of 65536); the first and last segments use modified weights. [`tools/research/motion.py`](../../../tools/research/motion.py) is a literal port that reads these tables from the user's executable.

**Verification.** `tools/research/verify_motion.py` runs the game's `AnimDecodePose` in the [CPU harness](../tooling.md) for every frame of every animation stream of a bank and compares all 49 outputs with `motion.sample_pose`. All 22 banks: 314,290 frames, zero differences ([log](../tooling.md#verification-log)).

A remake converter should **bake every frame** with this integer algorithm rather than resample the curves; the game samples integer frames only.

## Pose vector (49 channels)

| Channels | Content | Used by |
|---:|---|---|
| 0–2 | Root displacement `x, y, z` (scaled by model scale) | `AnimDecodeRoot` → fighter position |
| 3–5, 6–8, 9–11, 12–14 | Four limb **IK targets** (positions) | `IkLimbTarget` |
| 15–18 | Four limb **swivel angles** | `IkSolveLimb` |
| 19–48 | Ten joints × `(x, y, z)` Euler angles | `EulerToMatrix` |

The ten Euler joints are written to matrix slots `0, 1, 11, 2, 3, 7, 6, 10, 14, 17` (EXE table `0x8001A330`). Each rotation is `Rz(z)·Ry(y)·Rx(x)`; this was checked by running `EulerToMatrix` on 300 random angle triples (maximum difference 2/4096 from the closed form, due to fixed-point rounding).

## Pose to matrices

`PoseBuildMatrices(pose, slots)` writes the rotation part (9 `s16`, 4.12 fixed point) of 18 local matrix slots (32-byte `MATRIX`; the translation is not touched). [`tools/research/pose.py`](../../../tools/research/pose.py) is an integer port; `tools/research/verify_pose.py` compares all 18 × 9 values with the game routine ([verification log](../tooling.md#verification-log)).

1. **FK joints.** The ten Euler triples (channels 19–48) go to slots `0, 1, 11, 2, 3, 7, 6, 10, 14, 17` (`0x8001A330`) through `EulerToMatrix`: `Rz(z)·Ry(y)·Rx(x)` built from the 4,096-entry sine table with the GTE interpolation step (`IR0·IRn >> 12`, saturated to 16 bits).
2. **Limb bases.** Slots 2, 3 and 7 are post-multiplied (`MulMatrix`) by `[[0,0,−1],[0,1,0],[1,0,0]]` (`0x800972D0`).
3. **Normalised skeleton.** A root frame is formed from slot 0 and the root channels 0–2. `ComposeJointOffset` (`R = P.R·L` per column, `t = P.t + (P.R·offset) >> 12`) derives: chest = root ∘ slot 1 with offset `(0,0,0)`; right shoulder = chest ∘ slot 3 with `(350, 0, −100)`; left shoulder = chest ∘ slot 7 with `(350, 0, 100)`; hips = root ∘ slot 11 with `(0, 0, 0)` (`0x800972F0..0x8009731F`). These lengths are the same for every character.
4. **Targets into limb space.** `IkLimbTarget` rotates `target − limb_root.t` by the transposed limb-root rotation (in two 15-bit halves for precision: `high·8 + low`, each via the GTE) and adds a per-limb offset: arms `(−140, 0, 0)`, right leg `(−160, 0, 100)`, left leg `(−160, 0, −100)` (`0x80097320..`). Targets are channels 3–5 (right arm), 6–8 (left arm), 9–11 and 12–14 (legs), both legs relative to the hips.
5. **Two-bone solve** (`IkSolveLimb`, slots `4/5`, `8/9`, `12/13`, `15/16`; swivel channels 15–18):

```text
L    = isqrt(x² + y² + z²)                   (SquareRoot0; L = 0 leaves the slots unchanged)
inv  = 0x400000 / L
u    = (x, y, z) · inv >> 10                  unit direction, 4.12
# aim frame: first column u, second and third columns from a closed-form basis
k    = u.x + 4096
if k == 0:        k = −0x800, a = y·inv >> 11, e = −4096
elif k < 0x2000:  k = −0x1000000 / k, a = k·u.y >> 12, e = 4096
else:             k = −0x800, a = −u.y >> 1, e = 4096
b = (a·u.y >> 12) + e;  k = k·u.z >> 12
p = a·(e + u.x) >> 12, q = k·(e + u.x) >> 12, r = k·u.y >> 12, w = a·u.z >> 12, v = (k·u.z >> 12) + 4096
column 1 = (c·p + s·q, c·b + s·r, c·w + s·v) >> 12        c, s = cos, sin(swivel)
column 2 = (−s·p + c·q, −s·b + c·r, −s·w + c·v) >> 12
# bend (law of cosines with constant segment lengths)
arm: L > 533 → straight (lower = identity); L < 71 → lower unchanged
     d = inv·0x9204 >> 11; cosA = (L·0x800 + d)·0xD9 >> 16; cosB = (L·0x800 − d)·0x11A >> 16
     (all products are 32-bit C ints: for L ≈ 71–74, inv·0x9204 overflows and the game uses the wrapped value)
leg: L > 891 → straight; L < 3 → lower unchanged
     d = inv·0x6F8 >> 11;  cosA = (L·0x800 + d)·0x92 >> 16;  cosB = (L·0x800 − d)·0x93 >> 16
sinA = isqrt(0x1000000 − cosA²) (negated for legs), cosA clamped to ±4096 (sinA = 0 then)
upper columns 0 and 1 rotated by the angle A (IkBendMatrix)
sinB = sinA · (−0x14D4 arm / −0x1012 leg) >> 12   (0 when cosB is clamped)
D = (cosA·cosB + sinA·sinB) >> 12, O = (cosA·sinB − sinA·cosB) >> 12   (both rounded toward zero)
lower = [[D, −O, 0], [O, D, 0], [0, 0, 4096]]           rotation about z by B − A
```

The local matrix of each slot therefore has a rotation from the animation and a **translation from the model**: `FighterSetupPart` stores each part's KMD joint offset `(x, y, −z)` into its slot. `FighterComposeJoints` then composes `world[m] = world[parent(m)] · local[m]` (`ComposeJoint`, `0x8003B814`) starting from the fighter root matrix (`+0x8B0`), after optional [motion blending](../code/moves.md#motion-blending), and applies the camera and light matrices before drawing.

The consequences for a remake:

- store baked per-frame pose vectors per move, not per-character bone animations;
- solve the four limbs with the game's two-bone IK against the normalised skeleton, then apply the rotations to the character's own joint lengths — exactly as the original does, since the IK uses constant segment lengths while the mesh uses KMD offsets.

## Procedural head and eyes

After the pose matrices, `FighterComposeJoints` runs two procedural adjustments for every fighter whose `+0xC9` is clear (mode 8 sets it for CPU enemies and fixed-facing fighters). Joint numbers are world matrix blocks (`joints`, `+0x8F4 + 0x44·j`, translation at `+0x14`); the head's local matrix is `localMats` slot 2 (`+0xFB4`).

**Head look-at** (`HeadLookAt`, `0x800392C8`; per-player state `0x8009E920 + 0x14·playerIndex`: current angles `+0/+2/+4`, target angles `+8..+0xF`, active `+0x10`, snap `+0x11`, hold counter `+0x12`):

1. Active while the camera phase `0x80095890` is 2 (normal fight camera) and the running move has flag bit 30 — stances, walks, guards and other neutral moves. A move with an active window enables it only from `max(+0x2E, length − 17)` on.
2. Target = midpoint of the opponent's joints 1 and 2 (chest and head) minus the own head position, expressed in the own chest (joint 1) frame.
3. Vertical angle = −atan2 of the target elevation, clamped to [−60°, +25°] (`−0x2AAA..0x11C7`). Horizontal angle = atan2 of the lateral offset, clamped to ±L, where L falls linearly from 80° (`0x38E3`) to 30° (`0x1555`) as the chest x axis tilts away from vertical (tilt under 15° gives 80°, over 80° gives 30°). Gon (character `0x11`) keeps the horizontal angle 0.
4. The target is refreshed every frame, except that while it stays within 400 units laterally and 300 units vertically it is held for up to 60 frames (reduces jitter when the opponent is straight ahead).
5. On the first active frame the current angles are taken from the head's animated local matrix (decomposed into three angles), so there is no pop. Afterwards the vertical and horizontal angles move by half the remaining error per frame, at most 10° (`0x71C`); with the snap flag they jump to the target.
6. The head local matrix is replaced by `B · R(angles)`, where `B` (`0x8009E900`) is the rotation built once from the constant angles `(0x4000, 0, 0x4000)` at `0x8001A0F4` and `R` is built by `FUN_8003A5A0`. While active, the animation's head rotation is therefore ignored.

**Gon's eyes** (`FUN_80039A50`, character `0x11` only, before the look-at): the direction from Gon's head to the opponent's head is taken in the head frame, `a = atan2` in 4096 units, and the pupil offset is `−a/60` (clamped to −17) for `a < 0x800`, else `−(a − 0xF00)/60` (clamped to 17). `FUN_80034120` applies it by copying the eye texture within VRAM (`FUN_80029610` = `MoveImage`), shifting the left eye for positive and the right eye for negative offsets by that many pixels; texture rectangles come from `0x80095BC0` through the per-costume layout `0x80095CE0` (6 bytes per costume), with `+0x100` in y for player 2. `+0x1292/+0x1293` hold the current offsets. Face expressions (`HandFaceCommand` shapes 10–11) use the same texture-copy mechanism.

### Blinking

`FUN_80034354` runs each frame for every fighter; costumes without a closed-eye texture (`0x80095DF0[s]` byte 3 = −1) skip the copies. A countdown `+0x128E` alternates the states in `+0x1290`: open for a random `(rand() & 0xFE) + 1` frames (1–255, odd), then closed for 4 frames. Changing state copies the open- or closed-eye rectangle over the eyes in VRAM (`MoveImage`, rectangles and sizes from the per-costume table, [memory-map.md](../code/memory-map.md#character-resources)). Moves with flag bit 18 (`+0x24`), and lying-down moves (state bit 2 without flag bit 30) keep the eyes closed; Gon additionally switches his face with `HandFaceCommand` (kind 1). `FUN_80033F60` restores the open eyes when a fighter is set up.

## Costume attachments

Draw parts 18–21 (hair, belts, scarves; enabled per costume slot, [3dmk-models.md](3dmk-models.md#draw-parts-rows-and-matrices)) get no rotation from the animation. `FighterComposeJoints` composes them after joints 0–17 through `FUN_80037F10(f, part)`, which sets their local rotation (`+0xF74 + 0x20·part`; the translation is the KMD offset):

- **Data.** `FUN_80037EAC` stores per attachment `i = part − 18` the rest Euler angles from the KMD row's words `+0x24`, `+0x28`, `+0x2C` (`+0x129E + 8·i`), a pointer to its dynamics record from `0x80096660[6·slot + i]` (`+0x136C + 4·i`; `0x8009636C` = none) and clears a started flag (`+0x1360 + 2·i`). A record holds 12 `s16`: limit record, unused, inertia and gravity weights (of 256), length, gravity balance, mode, and for mode 1 a joint, a point on it and a second limit record. The limit records (`0x80096144`, 24 bytes) are six ints: the signs of the two `ratan2` arguments of each angle and the signs of the two angles.
- **Per frame.** Nothing happens for attachments without a record, for the first two attachments of costume slots `0x20`/`0x21`, or during replay rendering. On the first frame the local rotation is the rest rotation `R0`. Afterwards, with `W = parent · R0` and `Wᵀ` its transpose: the tip of the attachment on the previous frame (its own joint · `(length, 0, 0)`), minus the pivot (the parent · offset), taken into `Wᵀ` and normalised (`VectorNormal`), is the inertia direction; gravity is `Wᵀ · (b/16, (256 − b)·16, b/16)` with the balance `b`, dropped while the tip is below the floor (`y ≥ 0`, then clamped to 0); the blend is `(inertia·wᵢ + gravity·w_g) / 256` plus `(256 − wᵢ − w_g)·16` along the rest axis x. Mode 1 (`FUN_80038684`) computes target angles towards a point on another joint (the hands, 12 and 15), and uses them when they reach further along its limit record's axes; costume slots `0x24`/`0x29` aim their first attachment at a point 128 units from joint 13 towards joint 16 (`FUN_800388C0`). Yaw = `ratan2(sz·z, sx·x) · s_yaw` and pitch = `ratan2(sy·y, sd·√(x² + z²)) · s_pitch` (4096 units), then `<< 4`; slots `0x0E`, `0x0F`, `0x1B` and `0x26` cancel or limit some angles, slot `0x1A` clamps both to ±4096 and slots `0x24`/`0x29` to ±8192. The local rotation is `R0 · Euler(0, yaw, pitch)`.

The remake's port (`remake/core/fighter/attachment_dynamics.gd`) matches the game's routine in 3,000 random cases run in the harness (`tools/research/attachment_cases.py`).

## True Ogre's wings and tail

For True Ogre (character 20) `FighterComposeJoints` takes the local matrix of joints 5, 6 and attachments 18, 19 from `FUN_80033C54(f, j, tilt)` instead of `localMats[j]`. That routine returns the matrix of the next slot of the cycle 5 → 18 → 19 → 6 → 5 and, outside pauses and hit freezes, first overwrites that slot's rotation (not its translation) with a sway:

- On joint 5 the counter `+0x1294` advances; the phases are `(counter & 0x7F) << 5` and `(counter & 0x3F) << 6`, and the amplitude `A = clamp(−y₆ / 2, 0, 256)` with joint 6's world y (`+0xAA4`, still the previous frame's) is kept in `0x8009C080..0x8009C088`.
- Joint 5, 6, 18, 19 use the phase offsets 0, 1, 2, 3 (· `0x400`). With the level `v` (the hand channel `+0x1296`, through the replay hook `FUN_80033464`) and `a = A·(256 − v) / 256`, the angles are `x = sin(px + k) · a / 512`, `y = sin(py + k) · a / 256 + tilt` (`tilt = −4 · Atan2Units4096(localMats[5][0], localMats[5][1])`, taken before the loop), built by `FUN_8003A5A0` from `(0, x, y)`.
- The rotation's first column is scaled by `(v/4 + 256) / 256` (for joint 19 by `(256 − v/4) / 256`), the other two by `(v/8 + 256) / 256`.

Because `ComposeJoint` reads the joint offset from the translation of the matrix it is given, these four joints are also placed with the offset of the slot they borrow: joint 5 with attachment 18's, 18 with 19's, 19 with joint 6's and 6 with joint 5's. The model is built for that, so it is not a defect; the remake reproduces it (`FighterAnimation._ogre_slot`).
