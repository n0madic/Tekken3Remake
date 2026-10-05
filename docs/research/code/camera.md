# Camera

The fight camera is computed by a director that blends up to five camera sources, keeps both fighters framed from the side, and cuts to scripted cameras for throws and special hits. Addresses are Japan Rev.1.

Status: architecture, data layout and triggers `confirmed` from decompiled code. The fight camera arithmetic (`CameraTrackFighters`, `CameraYawSpring`, `CameraFrameFighters`, `CameraBlend`) is ported in `tools/research/camera_sim.py` and bit-exact against the game in the harness (`tools/research/verify_camera_sim.py`); camera streams are verified by `tools/research/verify_camera_scripts.py`.

## Camera state

The active camera `g_camera` (`0x800A8A88`) holds three rotation angles (`int`, 4,096 = 360°), then the position `(x, y, z)` at `+0x14..+0x1C` (default `y = −0x4B0`). `CameraBuildView` (`0x80045F40`, called by `CameraFrame`) turns it into the view matrix at `0x800AE438`:

```text
R = Rx(−rx) · Ry(−ry) · Rz(−rz)
row 1 of R *= 0x1BD2 / 4096          # 1.739: vertical scale for the display aspect
t = −R · position
```

The GTE projection distance (`H`) is `0x800A919C`.

## Director

`CameraDirector` (`0x800633C0`, step 5 of the [fight frame](fight-frame.md)) runs a per-mode state machine; in normal fights it keeps five source weights `w0..w4` (`0x800A9140..0x800A9148`, 4,096 = 100 %) and a camera state `0x800A9138`:

| Source | Producer | Use |
|---:|---|---|
| 0 | `CameraFight` (`0x8006636C` → `CameraYawSpring`, `CameraFrameFighters`) | The normal side-view fight camera. |
| 1 | `FUN_80066568` / `FUN_80068244` | Throw presets and hit cameras. |
| 2 | `FUN_8006879C`, `FUN_800669D8` | Round intro camera; camera streams. |
| 4 | `FUN_800648F4` path | Transition camera, blended with an ease-in-out (sine) curve. |

Each source stores `(x, y, z, pitch, yaw, H)` (`int`) at `0x800A0650 + 24·i`: angles are 18-bit (`angle << 6` of the 4096 units) and `H` is the source's projection distance. Source 3 holds the blended result.

`CameraBlend` (`0x80062E5C`) combines the sources whose weight is positive (bit mask of `w0..w4`) and then copies the weights to `0x800A914A` (previous frame):

- a single source (mask 1, 2, 4, 0x10) is copied (`FUN_80064368`);
- the pairs (0, 1) and (0, 2) are blended with weight `w0` of source 0, the pair (0, 4) with the eased weight `0x800 + sin(w0/2 − 90°)/2` (`FUN_80064458`);
- any other combination calls `CameraReset`.

A pair is blended around its look points, so the view turns smoothly instead of cutting through the fighters. For each source the look point is the eye moved by `r` along its view direction (`FUN_80063FE8`), where `r` is the mean of the eye's distances to the two targets (the game uses target 0's `z` in both distances). `r`, the look point, pitch and yaw (along the shorter arc) and `H` are interpolated. The eye is placed `r` back from the blended look point, and pitch/yaw are recomputed from the eye-to-look vector with `Atan2Units4096`. The result goes to source 3.

Copying source 3 (or a single source) into the view sets `g_camera` (`rx = pitch >> 6`, `ry = yaw >> 6`, position) and `GsSetProjection(H)`, with `H` clamped to `[0x800A919E, 0x800A91A0]` (`FUN_80063F4C`).

The director's phase is `g_cameraPhase` (`0x80095890`, passed as its third argument):

| Phase | Set by | Camera |
|---:|---|---|
| 0 | Fight start | Reset all sources, choose the intro offset, go to 1. |
| 1 | Director | Round intro (source 2 fading into source 0), then 2. |
| 2 | Director; `RoundFlow` (Tekken Ball point, draw result) | Fight camera with cinematic cameras ([below](#cinematic-cameras)). `HeadLookAt` and `BodySeparate` depend on this phase (`BodySeparate` runs while the phase is below 3). |
| 3, 4 | Round result while the match continues (`FUN_8003ECF4`): winner is fighter 0 / 1 | Winner camera setup, then 5. |
| 5 | Director | Winner camera. |
| 6, 7 | Match-deciding round (`FUN_8003ECF4`): loser is fighter 0 / 1 | Loser camera. |

Game state 6 uses `FUN_800693E8` and mode 8 overlay code (`FUN_800B545C`, `FUN_800B5504`). `CameraReset` (`0x80062CF8`) returns to source 0 at full weight.

## Fight camera

**Targets.** `CameraTrackFighters` (`0x80064944`) takes one point per fighter into `0x800AE170` (16 bytes each, previous frame kept at `+0x30`): `x, z` of the move anchor — or of the root while launched, during throws, or when the move has flag bit 29 — and `y` = head height − `0x122`.

**Yaw.** `CameraYawSpring` (`0x80064AF8`) measures the direction of the line between the two targets and keeps the camera perpendicular to it (the left/right order follows the fighters' screen positions). A damped spring (`0x800A06DC` offset, `0x800A06E0` velocity) starts turning when the misalignment exceeds 5° (`0xE38`), accelerates beyond 20° (`0x38E4`), and settles when below 5° for 32 frames; the offset is clamped to ±`0xDDD0` (added to the yaw as `offset >> 6`), or to `k · 0xDDD0 / 256` with `k = 0x200, 0x180, 0x80, 0x40` while either fighter's move camera byte (move `+0x24` bits 0–7) is `0x27, 0x28, 0x29, 0x2A`. Misalignment above 20° also tilts the camera. The target pitch (`0x800A06E8`) is a sine ramp up to `0x444` (6°, 18-bit units), reached at 90°. The actual pitch `0x800A06E4` moves towards it by 1/16 of the difference (at most 256) per frame, but only on frames after the camera moved (`0x800A06D2`). `CameraFight` passes that pitch to the framing (0 in mode 7). The spring runs only for source 0, below 150° of misalignment (`0x1AAAA`), and while the fighters are at least 200 units apart (`g_fighterDistance`); a reset snaps the yaw to the axis direction and clears the state.

**Framing.** `CameraFrameFighters(f0, f1, pitch, yaw, reset, distance, src)` (`0x800650F8`) places source `src` (0 for the fight camera, 1 for presets and hit cameras):

1. Pivot: the targets' midpoint plus the camera's current horizontal offset rotated by the yaw change (on reset: `distance` along yaw + 270°). Both targets are rotated into the view (yaw, then pitch) relative to the pivot and the camera height.
2. The view is pushed back so that the mean target depth, measured at the height −450 (`0x1C2`), equals `distance` (at least 800; the default is `0x158D`).
3. Horizontal fit: the screen positions of the outer edges (each target ±150 units, `0x96`) use the projection `H` (`0x800A919C`).
   - If they span less than 281 pixels (`0x119`), a fighter closer than 48 pixels to a screen edge (`0x30·z/H`) shifts the camera by 1/8 of the excess.
   - When both are that close (or on reset), the camera centres on the depth-weighted midpoint.
   - The stored back-off (source state `+0x2C`) decays by 1/8 per frame (1/32 while negative).
   - A wider spread instead backs the camera off until the spread fits 280 pixels (`0x118`, with a 140-unit side margin `0x8C`). The back-off is approached by 1/32 when moving out and 1/8 when moving in.
4. Vertical fit: the camera also backs off (`+0x28`, never negative) until the higher target on screen is below the top margin: 100 pixels, or 128 for source 1 with a negative pitch. Moving out follows 1/8 of the difference (at most 100 units per frame); moving in follows 1/16 (at most 75).
5. Source 1 with a positive pitch adds a lift from the higher target's height, `(y + 1000)·368/640` for `y > −1001`. The lift changes by at most 28 units per frame (`0x80098754`).
6. Source 0 adds a pitch-dependent height term (`back-off·cos(pitch)·H / distance / 16`). It sets the moved flag `0x800A06D2` when the camera moved by more than about 31 units (squared distance above 1000).
7. The offsets are rotated back into the world. `x, z` are set, `y` is moved, and pitch and yaw take the requested values (via the 18-bit shortest difference).

The divisions by target depth are unchecked. A target exactly in the camera plane divides by zero, which the R3000 answers with −1 or +1 (the port reproduces this; the Unicorn harness returns the dividend instead, so the verifier skips such cases). In mode 7 the ball (`volley.ovl` `FUN_800B4948`) is a third target. It is projected like the fighters but keeps its raw depth, without the distance correction of step 2. When it lies beyond the outer fighter on screen it replaces that edge, with a further 150-unit margin. When it is higher on screen (smaller view `y`) it becomes the top target of step 4 (ported and verified).

Per-source state is at `0x800A06D0 + 0x30·src`:

| Offset | Type | Meaning |
|---:|---|---|
| `+0x00` | `s16` | Yaw swing phase (0 idle, 1 swinging). |
| `+0x02` | `s16` | Moved flag (source 0). |
| `+0x04`, `+0x06` | `s16` | Cleared by the spring. |
| `+0x08` | `s16` | Swing frame counter. |
| `+0x0C` | `int` | Swing offset (added to the yaw as `>> 6`). |
| `+0x10` | `int` | Swing speed. |
| `+0x14` | `int` | Pitch. |
| `+0x18` | `int` | Pitch target. |
| `+0x1C` | `int` | Pitch step. |
| `+0x20` | `int` | Last axis error. |
| `+0x24` | `int` | Depth step. |
| `+0x28` | `int` | Vertical back-off. |
| `+0x2C` | `int` | Horizontal back-off. |

## Cinematic cameras

Cinematic cameras are enabled (`0x800A9154`) in every mode except 6–8. Within the fight camera phase (`g_cameraPhase` = 2) the director keeps a sub-state `0x800A9138`:

| State | Weights | Action |
|---:|---|---|
| 1 | fight 100 % | Idle. If a throw runs (a fighter with `throwState > 0`), `CameraThrowStart` picks a camera for the thrower (`0x800A9156`) and a side flag (`0x800A9158`, from the fighters' screen order): a preset goes to state 3, a stream to state 6. Otherwise `CameraHitChoose` may start a hit camera (state 8). |
| 2 | preset 100 % | Hold the preset until `CameraThrowEnds`, then blend back (state 4) over the preset's blend-out length. |
| 3 | fight → preset | Wait 16 frames (cancelled by a move camera byte 9), then blend in over the preset's blend-in length and go to state 2. A throw ending during the blend goes to state 1, 4 or 5. |
| 4 | preset → fight | Linear blend back, then state 1. |
| 5 | transition → fight | The transition camera (source 4, a frozen copy of the last scripted view) fades into the fight camera over the given length (8 frames after a cancel, 35 after a reversal). |
| 6 | stream / fight by the stream's weight channel | Play the stream. Ends when either move camera byte becomes 9 (straight cut if the weight is back at 100 %, else state 5), when the thrower is thrown back (`throwState < 0`, 35-frame transition), or after the weight went to 0 and back to 320. |
| 8 | hit camera 100 % | Run the hit camera for its hold time, then cut back (state 1). |

Weights are 4.12 fixed point and are mixed by `CameraBlend`.

### Choice lists

The running move's camera byte (move `+0x24` bits 0–7) is a camera id. `CameraChoose` (`0x80067548`) rejects ids `0x19–0x2A` and everything in mode 5, then walks a flat array of 8-byte entries `(kind s16, weight u16, script s32)` — the EXE table `0x80098750` for ids below `0x2B`, the bank's section 7 for ids `≥ 0x2B` (index `id − 0x2B`) — starting at the entry after the id. Groups are separated by `(0, 0x1000, 0x1000)`. One random 12-bit number is compared with the cumulative weights; the first entry whose weight is not smaller wins. Kind 1 entries are presets; kind 2 entries come in pairs with equal weight: the second is the variant for the other side, used when the side flag is set (a single kind-2 entry is mirrored instead, `0x800A9184`). Script values `< 0x1E` select a preset, negative values a stream at `section8 + (value & 0xFFFF)`.

When the thrower's next move of a multi-part throw starts, the camera switches with it: a camera byte `< 0x2B` switches to preset framing, a larger one to the same choice index of the new id (`FUN_800676CC`); byte `0x25` keeps the current camera, and in bank type 0 byte `0x63` during a preset starts that id's stream.

`tools/research/camera_scripts.py` prints all lists, presets and streams; `tools/research/verify_camera_scripts.py` checks the stream decoder against the game (510 streams, 86,058 frames, bit-exact).

### Presets

30 presets at `0x80024184` (20 bytes; `0x800243DC[id]` = preset index + 1): blend-in and blend-out lengths (`s16`), four pitches and four yaw offsets (`s16`, one of each chosen at random by `FUN_80067DE4`, which would also clamp and halve the pitch when `0x800A91A4` is set; the retail code only ever stores 0 there). The camera keeps the normal two-fighter framing (`CameraFrameFighters`) but with the pitch `p << 5` (18-bit units), the yaw set to the direction between the fighters plus `yaw << 6` (18-bit angles; negated when the side flag is set) and 89 % of the normal distance (`0x158D · 0x72 / 128`).

| Presets | Blend in/out | Heights | Yaw offsets |
|---|---|---|---|
| 0–4 | 35 / 35 frames | 0 | +30°, +60°, 0°, −30°, −60° |
| 5–9 | 35 / 35 | −102 | same order |
| 10–14 | 35 / 35 | random of 113, 284, 455, 341 | same order |
| 15–29 | 1 / 1 (cuts) | as 0–14 | as 0–14 |

EXE camera ids use presets only: 1, 9, 0x0E → 15; 3 → 20 or 21; 6, 0x16, 0x19, 0x1C, 0x1F, 0x22 → 25 or 26; 0x0B → 20 or 25; 0x10 → 20 (78 %) or 15; 0x13 → 25 (33 %) or 15.

### Camera streams (bank section 8)

A stream is a `u16` yaw mode followed by a compact channel stream (`FUN_80038F38`):

- header `u16`: frame count (bits 0–9), channel count (bits 10–15, always 7 here);
- per channel, segments: the first descriptor also holds `segment count − 1` in bits 12–15; a descriptor is `length | kind << 10` followed by its data: kind 0 constant (1 word), kind 1 linear (`base`, `slope`; value `base + slope·t / 32`, or `/ 1` for streams shorter than 10 frames), kind 2 B-spline keys (`length` words, as the animation keyed channels with shift 4, spanning `1 + Σ(interval + 1)` frames), kind 3 raw (one word per frame);
- odd channels are stored time-reversed (sampled at `frames − 1 − t`).

The seven channels are eye `(x, y, z)`, target `(x, y, z)` and a weight. Positions are scaled by 20/32 and rotated about the vertical axis into the world around an origin — the victim's anchor (`+0x00..+0x08`) when the stream starts from a throw, the victim's root x/z with its anchor y for the stream switch at the thrower's next move (`FUN_8006320C`) — with the yaw from the victim's heading: `0x400 − facing/16` (mode 0 and 4), `0x800 − facing/16` (1), `−facing/16` (2) or `−(facing/16 + 0x400)` (3 and 5) in 4096 units; the side variant negates z. The camera looks from the eye to the target with projection distance 550 (`0x226`). The weight channel divided by 8 and clamped to 0..320 is the share of the fight camera (`w0 = weight / 320`), which lets a stream start and end as a smooth blend; after the last frame it is forced to 320.

Other stream users: the arcade overlay plays Ogre's (bank type 14) intro through id `0x4B`, and the demonstration overlay plays the reel of ids `0x2B, 0x2D, …` of fighter 0's bank.

**Camera reels** (`FUN_800673E4(kind)`: 1 the demonstration, 2 the Ogre intro; `0` steps the running reel). Starting a reel resets the stream state (yaw 0, origin 0, no side flag, `0x800A91A2 = 1`), picks the first stream with `CameraChoose` (id `0x2B`, or `0x4B` from the bank of the fighter whose bank type is 14) and samples its frame 0. Each step (`FUN_80066D00`) turns the current sample into camera source 2 and samples the next frame; after a stream's last frame the demonstration reel continues with entry `k + 1`, id `0x2B + 2k` (`FUN_80067358`), while the Ogre reel ends and returns non-zero. A reel sample is halved (toward zero), has weight 0 and projection distance 450 (`0x1C2`); with `0x800A91A2` set the eye is moved along the view line to keep the framing at the actual projection distance `H`: `eye = target + (eye − target)·H / 450` per axis (C division, 16-bit results). Source 2 is then the eye with pitch and yaw from the eye-to-target vector (`FUN_800641D4`: `ISqrt` of the horizontal distance, `Atan2Units4096`, `<< 6`) and `H`, and `CameraUseSource(2)` makes it the view. The demonstration's camera is traced frame by frame from the game's code (`tools/research/enbu_harness.py`); every choice of its reel has weight `0xFFF`, so the random number `CameraChoose` draws never matters.

### Hit cameras

After a clean hit `CameraHitChoose` (`0x80067FD4`) rates it: 3 = KO with more than 27 damage, 2 = counter hit, 1 = close hit, 0 = other. Rating 3 uses the first row of `0x80024510`; other ratings need the attacker's bank type and move slot to match a row: `(0, 316)` → list 300, `(0, 715)` → 302, `(9, 585)` and `(9, 586)` → 301. Lists (`0x800244F8`: records pointer and count per list) are 20-byte records `(weight, 0, script pointer per rating ×4)`. At the first fight `FUN_80067ECC` (flag `0x800988E4`) turns each list's weights into cumulative thresholds `sum·4096 / total` (list 300: 60, 60, 30 → 1638, 3276, 4096; lists 301 and 302 have one record → 4096). The walk compares the 12-bit random number with each threshold and would stop at a weight above `0x1000`, which it never reaches since the last threshold is `0x1000`: a matching row always picks a script. So every KO with more than 27 damage and every hit by one of the four listed moves starts a hit camera unless the script is −1. A script (`s16` words) is `kind, frames, blend-in, blend-out, start distance (s32), end distance (s32), heights[4], yaw offsets[4]`: kind 0 = preset-style framing with a random height and yaw offset; kind 1 = a view of the contact point (the first 16 bytes of the defender's `bestHitSlot`, `0x800A0800[i]`) from the chosen height/yaw direction at distance `end + (start − end)·max(0, remaining/hold − ¼)`, scaled by `0x800A919C / 750`; −1 = none. The hold time is `frames − blend-out`.

### Round intro

`FUN_8006867C` picks the next of ten intro offsets (`0x800988E8`, `(x, y, z)` `s16`; the counter `0x8009892C` advances every round, mode 7 uses `(0, 0, 3750)` at `0x80098924`) and a length of 120 frames (`0x800958A8 == 1`) or 53:

| # | Offset | # | Offset |
|---:|---|---:|---|
| 0 | (0, 0, −7500) | 5 | (−11250, 0, 0) |
| 1 | (0, 375, −6000) | 6 | (9000, 0, 7500) |
| 2 | (6000, 375, 0) | 7 | (−9000, 0, 7500) |
| 3 | (−6000, 375, 0) | 8 | (7500, −6000, −3750) |
| 4 | (11250, 0, 0) | 9 | (−7500, −6000, −3750) |

Each frame (`FUN_8006879C`) the eye is the fight camera position plus the offset times `k = 1 + sin(0xC00 + 0x400·t/length)` (`t` counting down, so `k` eases from 1 to 0) and the view is aimed at the fight camera's position with `z = 0` (`(x, y, 0)`); its weight is 100 % until the last 16 frames, which fade into the fight camera.

### Round end

When the round ends `g_cameraPhase` leaves 2 (see the table under [Director](#director)). The camera uses its own generator `0x800A95F4` (`x = (x + 1) · 0x10DCD`, the upper half is the random value).

- **Winner** (phases 3/4 → 5): two styles alternate from round to round (`0x800A0844`). Style A (`FUN_800466F8`/`FUN_80046854`): the eye starts 3953 units from the winner's root at a random angle 60°–120° off the winner's facing, 850 units up (or 290 above the head), approaches by 8 units per frame while farther than 2513, and turns towards the winner with 1/32 smoothing. Style B (`FUN_80046A38`/`FUN_80046CB8`): a random lateral offset (4500/5000/5500), forward distance (1800/2000/2200) and height (−950/−1100/−1650; distance 2200 for the lowest) on a random side; the eye then drifts backwards along the facing (`cos/512`, `sin/512` per frame), is pushed out to at least 2308 units, yaw follows with 1/32 and pitch with 1/16 smoothing, and the eye sinks when the pitch looks up.
- **Loser** (phases 6/7): set up by `FUN_80068A44` at the result. If the loser's health is 0 the camera looks straight down (pitch 90°) from 7853 units above the root, with a random yaw jitter of ±64 (4096 units) around the facing. Otherwise (time out) the eye starts 3978 units away (6596 for bank type 11) at a random angle 45°–135° from the facing, 1500 units up, approaches by 2 units per frame down to 3664 (6282), and the target follows the root and the head height with 6/128 smoothing.

## Camera shake

Move events 1–3 and landings start one of three byte scripts (`FUN_8004AF94(n)`: pointer table `0x80097EC8`, current pointer `0x80097EC4`; the same call pulses the pad through `VibrateAll`). `CameraShakeStep` (`0x8004AFCC`) adds the next signed byte to the camera's `rx` angle (`0x800A8A88`, 4096 = 360°) each frame; `-128` ends the script. The offsets are per frame, not accumulated, because the director recomputes the camera every frame.

| Script | Use | Offsets |
|---:|---|---|
| 0 | `landedB` of an active fighter (knock-down landing), move event 1 | 1, 2, 1, 0, −1, 0 |
| 1 | Landing of air kind 1, move event 2 | 3, 2, 0, −2, −3, 0, 3, 2, 0, −3, −2, 0, 2, 1, 0, −2, −1, 0, 1, 0, 0, −1, 0, 0 |
| 2 | Move event 3 | 4, 3, 0, −4, −3, 0 (×2); 3, 2, 0, −3, −2, 0 (×3); 2, 1, 0, −2, −1, 0 (×4); 1, 0, 0, −1, 0, 0 (×5) |

## Floor

`CameraFrame` (`0x800484D8`) builds the view matrix and then calls the stage's floor routine through `0x8009EAD0`: `FloorDraw` (`FUN_800490F0`) for normal stages and `FUN_80049AE0` for stages with an alternative floor (selected per stage by `FUN_80048324`, the title overlay installs its own). The floor is an endlessly tiled grid of textured quads (`POLY_GT4`) around the fighters' midpoint: tile size `0x8009EB28`, `0x8009EBCC × 0x8009EBD0` tiles, per-vertex brightness from a distance table (`0x8001DF6C`) so that the floor fades out, and only quads with a vertex on screen are emitted. Mode 8 fixes the grid height.

## Open items

- None known.
