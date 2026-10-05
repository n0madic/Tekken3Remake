# Visual effects

Hit flashes, sparks, dust, fire, gas and the power-up glow come from two systems in the resident executable: a three-slot **flipbook ring** and a pool of **effect objects**. All sprites are 4-bit textures from the [system texture pages](../formats/system-textures.md) or the characters' own flipbooks (character ARC member 1). Addresses are Japan Rev.1.

Status: `confirmed` from the decompiled code of every spawner and update routine, with the texture pages decoded; sizes are in world units, times in frames.

## Common conventions

- **Sprites** are camera-facing `POLY_FT4` quads (object flag `0x40`): the four corners of a small model (`+0x08`, e.g. `(±55, ±55, 0)`) are transformed with the camera matrix, whose vertical row is scaled by `20/12` for the display aspect, and inserted into the ordering table by depth (`FUN_8006E734`). Each object keeps two primitives (double buffering, `+0x50` and `+0x78`).
- **Texture pages** (`tpage` words): `0x3F` = page (960, 256), additive blending (`B + F`); `0x1F` = the same page, 50 % blending (`B/2 + F/2`); per-object pages are built for the Tekken Ball flipbook. Colour is neutral (`0x80`).
- **Palettes**: fixed CLUTs `0x7DC6–0x7DCA` (x = 96–160, y = 503). Fading sprites switch every frame to the next of 16 CLUTs of a ramp: `0x800A91C8[i]` (row 509) or `0x800B0970[i]` (row 510), `i = 16·age/lifetime` (`FUN_8006E848`).
- **UV animation**: flipbook frames are 32 × 32 (`u, v` to `u + 31, v + 31`) or 16 × 16 texels, taken per frame from byte tables `(u, v)` in the executable (`0x80025760`, `0x80025770`, `0x80025780`, `0x80025798`, `0x800257A8`, `0x80025820–0x80025830`, `0x80025858`, `0x800258B8`, `0x80025A0C`).
- **Motion**: velocity from a direction `(pitch, yaw)` and a speed (`FUN_8006E408`: `vx = s·cos(p)·sin(y)`, `vy = s·sin(p)`, `vz = s·cos(p)·cos(y)`, 4.12); most particles die when they reach the floor (`y ≥ 0`, y is negative upwards).
- **Budget**: at most 80 objects (`0xA0` bytes each, free list in the effect buffer `0x800AE148`). Optional spawns (smoke, embers) use the probability `(80 − live objects)·k`, so busy scenes thin out automatically.
- **Projectile hit segments**: an object with flag `0x02` publishes its previous and current position as a segment in the effect buffer (`+0x3200 + 0x780·owner + 0x18·i`, owner by flag `0x10`); attack descriptors with joints `≥ 0x18` read these segments (`FUN_8006E804`) instead of skeleton joints, so fireballs and gas clouds can hit ([combat.md](combat.md#collision-shapes)). The flag is cleared by table (`0x800258E4`, `0x8002583C`, `0x80025790`, `0x80025A44`) when the sprite animation reaches its harmless frames, or when the owner's move leaves its active window.
- **Dynamic light**: fire effects call `FUN_8003A160(position, colour)`, a single point light (fighter colour matrix column) that decays over 48 frames: orange `(255, 128, 0)` for fire, `(192, 192, 255)` for the power glow; hit flashes use the attacker character's colour.

## Flipbook ring

`EffectSpawn(set, index, point, noVelocity)` (`0x80076B6C`) with `index & 0x80 == 0` fills one of three 64-byte records (`0x800A37B0`, round robin) drawn with three `POLY_FT4` each (`0x800A3870`). `FUN_8007699C` sets up the animation: frame count from the set's record, VRAM layout from `0x80027C48 + 0x30·block + 0x0C·index` `(clutX, clutY, x, y, pageWidth, pageHeight)`. The point is stored `<< 7`; unless `noVelocity` is set the flipbook drifts at `0x1900 / 128` units per frame along the hit direction stored in the hit slot. Sets 0 and 1 are the two players' character flipbooks (block 0 or 1), lit with the character's colour; set 2 is the third fighter (mode 8) or player 2; set 3 is the system set (block 2):

| Set 3 index | Frames | CLUT | First frame | Use |
|---:|---:|---|---|---|
| 0 | 27 | (32, 503) | (896, 256), fire page | Every hit. |
| 1 | 21 | (48, 503) | (920, 352) | Hit without damage. |
| 2 | 25 | (64, 503) | (896, 448) | Guard. |
| 3 | 27 | (80, 503) | (968, 288), dust page | Landing dust (`FUN_8004AC28`). |

Character flipbooks (`0x80027BAC + 6·charId`: frame count `s16` then an RGB light colour): 30 frames for most characters, 22 for Jin, Heihachi, Gon, Doctor B. and the Tekken Force enemies; for example Paul's fire ring (orange) and the Mishima blue lightning `(0, 192, 255)`.

Every spawn is also logged so that replays can re-create it. The effect log (`FUN_8004A700`) keeps a 64-entry ring of 28-byte entries (`0x8009EBF0`: position, angles, set, index, mode) and one slot per recorded frame (`0x8009EBEC`, 300 slots of 8 bytes: first entry, count; the write slot `0x8009EBDC`, stopped after `0x41` entries per cycle). Mode 0 re-spawns the flipbook (`EffectSpawn`), mode 1 a landing dust ring (`FUN_8004AC28`). `FUN_8004A840`, the hit spark logger, always passes mode 0 (Ghidra loses the `a3 = 0` of its delay slot), `FUN_8004A860` mode 1 for dust. During playback `FUN_8004A954` replays the slot of the play position and advances it (`FUN_8004A91C(n)` seeks `n` frames back).

**Drawing** (`FUN_80077158`, one call per ring with the record count). A running record is projected at its point and drawn as a square sprite of `32·0x2E0B / (4·otz)` by `32·0x140247C/1024 / (4·otz)` pixels, which is 32·0x2E0B / H = 754 world units at the game's projection distance 500. Its frame advances by one every frame: the texel position moves 8 VRAM words right, wraps to the next 32-line row after `pageWidth / 8` frames and to the next page column after `pageHeight / 32` rows (so a frame sequence is the flipbook's TIMs in upload order). The record dies after its frame count. Additive sprites fade over their last ten frames (colour `0x80 − (frame − count + 10)·0x9999 >> 12`); the landing dust (set 3 index 3) is drawn at 50 % instead. `FUN_80076704` initialises the set records; it points set 3 index 2 (guard) at index 1's record, so the guard flash plays 21 frames ([game-bugs.md](game-bugs.md) #51). In the demonstration (game state 6) sets 0 and 1 are the overlay's copies of character 9's and character 4's flipbooks.

**Landing dust ring** (`FUN_8004AC28`, `FUN_8004AD28`; three rings of six puffs at `0x8009EBF8`): the ring stands at the root's `x, z` and `y = −250`; its first puff starts at once and the others one every second frame, at the offsets `0x8001E818` (0, 0), (445, 324), (−124, 380), (−500, 0), (−139, −427), (486, −354); each puff is the dust flipbook.

## Hit effects

`HitSpawnEffect` → `FUN_80076EB8` for guards and hits without damage (set 3 index 2 or 1) or `FUN_80076F10` for damaging hits:

1. set 3 index 0 at the contact point;
2. damage ≥ 21: the attacker's character flipbook as well;
3. attacker descriptor `0x18` or `0x1A` (fire breath): the defender catches fire (type 11);
4. otherwise damage ≥ 21: sparks along the attack direction — types 2 + 1, or types 13 + 12 while the attacker's `powerTimer` runs.

## Effect objects

`EffectAlloc` (`0x8006F7DC`) takes an object from the free list; `EffectsUpdate` (`0x8006F8A8`, [fight frame](fight-frame.md) step 16) runs one update routine per object by its type byte (`+0x0C`); the state byte `+0x0E` sequences initialisation and phases.

| Type | Spawned by | Look and behaviour |
|---:|---|---|
| 0 | — | Placeholder, freed after 2 frames. |
| 1 | hit, damage ≥ 21 | 6 sparks: 16 × 16 particle `(128, 144)`, additive, size ±55; direction = hit direction ± 60°; speed `a + (b − a)·(0.25 + 0.5·cos(90°·age/lifetime))` with `a = 0–0x1FF`, `b = 0x680–0x87F` (decelerating); lifetime 10–41; fade ramp row 510. |
| 2 | hit, damage ≥ 21 | 20 sparks: same sprite, start jittered ±127 units, direction ±5.5°, constant speed `(0–0x7FF)·5/4`, lifetime 20–51, ramp row 510. |
| 3 | fight start (8 objects) | Power glow on joints 6 and 10 (hands) and 14 and 17 (feet) of each fighter: 16 × 16 glow `(128, 128)`, size ±140, ramp row 509 cycling. Visible while `FUN_8006F5D8` sets the joint's bit: while `powerTimer` runs, the joints of the running attack's descriptor (via `0x80025420`), or both hands for moves without attack joints; hands of character 20 use an offset (`0x80025590`). Emits rising sparks (types 4, 5) and the bluish light. |
| 4, 5 | type 3 | Rising glow particles: size ±80 / ±30, jitter ±63 / ±127, accelerate upwards (`vy −= 1.125` per frame), 16 / 32 frames on ramp row 509. |
| 6 | fire breath (descriptor `0x18`, Ogre, True Ogre, Gon) | Fireball from the head joint along the mouth direction (`0x80098BE0` offsets): 32 × 32 flipbook, CLUT `0x7DC8`, speed `0xA00` while it grows (7 frames), then `0x1000` looping 8 frames for 5–8 frames, then an 8-frame burst (CLUT `0x7DC9`); slides along the floor at `y = −216`; hit segment; emits smoke (type 7), scorch fire (type 9) and the orange light; pad vibration 3 at the active frame. |
| 7 | fire effects | Smoke/ember puff: 16 × 16 flicker, size ±48, jitter ±127, accelerates upwards (3 units/frame²), 0–31 frames then a 12-frame fade. |
| 8 | fire breath variant (descriptor `0x1A`, Gon) | As type 6 with a longer flame (`0x800257E0/0x80025800` quads, speed `0x800`), cancelled when the owner is hit, stops when the owner's move ends; vibration 4. |
| 9 | type 6 on the floor | Ground fire at `y = −256`: 16 × 16 flicker, size ±256, 60–91 frames, then rises for 16 frames; emits embers. |
| 10 | descriptors `0x19` (all characters, common slot 2413) and `0x1C` (Doctor B.) | Breath cloud from the mouth: 21-frame 32 × 32 flipbook (`0x800258B8`) on the 50 % page, CLUT `0x7DCA` (`0x7DC6` for `0x1C`), speed `0x300`, direction ±11°, tall quad (±192 × −276..); hit segment for the first frames. |
| 11 | victim of fire breath | Burning body: 10 flames (1 for Gon) attached to joints 1, 2, 4, 8, 5, 9, 12, 13, 15, 16 for 60–75 frames, flickering 32 × 32 frames, embers and light; then each flame rises and bursts (5 frames). Sets the fighter's burning flag (`+0x1888`). |
| 12, 13 | power hits | As types 1 and 2 with the ramp of row 509 (other colours). |
| 15 | Tekken Ball overlay | Follows the ball (`FUN_800B0C70`): kind 0 = the hitting player's character flipbook looped (12-frame table `0x8002597C`) as a glow on the ball, kind 1 = a fireball-style flame; removed when the ball state changes. |
| 16 | `FUN_8003E38C` | Sound only: waits for SPU voice 2 to stop, then plays `0x86DA`. |
| 17, 18 | voices | Sound only: replays a fighter sound two more times 15 frames apart (twice as fast during replay playback, `0x800958C8`), changing the variant bits 10–13 of the sound code — voice echoes. |
| 19 | descriptor `0x1B` (Gon's gas attack) | Emitter at joint 11 (hips): spawns type 20 clouds on a timetable (`0x80025994`: frame, speed, height; −1 ends) while the move is active. |
| 20 | type 19 | Gas cloud: 27-frame 32 × 32 flipbook (`0x80025A0C`) on the 50 % page, CLUT `0x7DC6`, rises slowly (`vy −= 0.225`), hit segment during the early frames. |

### Drawing by type and phase

The update routines write the model (`+0x08`) and the frame's UV corners (`+0x5C…`, `u, v` to `u + 15` or `u + 31`) into both primitives; the page is (960, 256) for every object except Tekken Ball's character glow.

| Types | Model (half size) | Sprite or UV table by phase |
|---|---|---|
| 1, 2 | `0x8002554C` (±55) | (128, 144), 16 × 16 |
| 12, 13 | `0x8002593C` (±35) | (128, 128), 16 × 16 |
| 3 / 4 / 5 | `0x8002556C` (±140) / `0x800256E0` (±80) / `0x80025700` (±30) | (128, 128), 16 × 16 |
| 6 | `0x80025740` / `0x80025720` (±345 × ±432, the second mirrored) | grow `0x80025760`, loop `0x80025770` (frame `c & 7`), burst `0x80025780`; 32 × 32 |
| 7 | `0x800257C0` (±48) | puff `0x80025798` (frame `(a & 0xE) / 2`), fade `0x800257A8`; 16 × 16 |
| 8 | `0x800257E0` / `0x80025800` (±432, mirrored) | grow `0x80025820`, loop `0x80025828`, burst `0x80025830`; 32 × 32 |
| 9 | `0x80025878` (±256) | flicker `0x80025798`, rise `0x80025858`; 16 × 16 |
| 10 | `0x80025898` (±192 × −276…108) | `0x800258B8`, 21 frames, 32 × 32 |
| 11 | `0x800258FC` (±345), Gon `0x8002591C` (±448) | following and rising `0x80025828`, burst `0x80025830`; 32 × 32 |
| 15 | `0x8002595C` (±576) | kind 0: `0x8002597C` (12 frames: `u` in words and `v` added to the player's flipbook upload at x = 0x170 + 0x80·player, v + 128, CLUT `0x7DC0 + player`, `FUN_800743EC`: with the upload's two frames per 32-line row these are frames 9–20 of the character flipbook); kind 1: as type 6's grow and loop |
| 20 | `0x800259EC` / `0x800259CC` | `0x80025A0C`, 27 frames (frame `c / 2`), 32 × 32 |

## Other effects

- **Landing dust and camera shake**: [moves.md](moves.md#per-frame-bookkeeping-in-fightermovephysics), [camera.md](camera.md#camera-shake).
- **Move events** 6–10 ([moves.md](moves.md#frame-events)) spawn flipbooks at joints and sparks.
- **Face and hand shapes**: [animation.md](../formats/animation.md#procedural-head-and-eyes).
