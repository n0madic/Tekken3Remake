# Character model records: `3DMK` / `.kmd`

The 52 BNS records `71 + 4n` (`n = 0..51`) are character models. The original Japanese EXE names them `.kmd` (for example `paul3.kmd`, ID 71); `3DMK` is the signature at offset 8. They are byte-identical in original Japan, Japan Rev.1 and USA.

This document was rebuilt from the game code. **The earlier revision assumed that the 56-byte rows start at `0x18`; the loader shows they start at `0x10`.** All row fields below use the corrected alignment. The earlier "fields 12/13" were the first two words of the *next* row, and the earlier "coordinate block" `[w0,w1)` was the normal block.

Status: `confirmed` unless stated otherwise. Evidence:

| Routine (Japan Rev.1) | Role |
|---|---|
| `KmdRelocate` `0x80035138` | Converts row words 0–4 and variant tables to pointers. |
| `FighterSetupModel` `0x80035E14` | Reads the scale field. |
| `FighterSetupPart` `0x80035B5C` | Maps draw parts to rows, parents and joint offsets. |
| `FighterBuildPartPrims` `0x800353E4` | Builds GPU primitives from the texture block. |
| `DrawSkinnedPart` `0x80036F00` | Transforms, stitches and emits one part per call. |
| `PartSelectVertexVariant` `0x80034A98` | Swaps in alternative vertex blocks (hand poses). |

[`tools/research/kmd.py`](../../../tools/research/kmd.py) parses all 52 models and requires every block to end exactly where the next begins. [`tools/research/verify_kmd_skin.py`](#verification) runs the game's own `DrawSkinnedPart` in the [CPU/GTE harness](../tooling.md) and compares every vertex slot with an independent Python model.

## File header

| Offset | Type | Meaning |
|---:|---|---|
| `0x00` | `u32` | Row count, always 27. |
| `0x04` | `u32` | Model scale in percent. The fighter scale is `value × 4096 / 100` (fighter `+0x4EC/+0x4EE`); root motion is multiplied by it. Observed: 45 (×2), 90 (×4), 98 (×8), 100 (×24), 102 (×2), 105 (×10), 106 (×2). |
| `0x08` | `char[4]` | `3DMK`. |
| `0x0C` | `u32` | Zero. |
| `0x10` | `KmdRow[27]` | Row table, 56 bytes each; ends at `0x5F8`. |
| `0x5F8` | — | Block data. Row 0's vertex block always starts here. |

All block offsets are relative to the file start. The relocator adds the load address to every nonzero word whose top byte is zero.

## Row (`KmdRow`, 56 bytes)

| Offset | Field | Meaning |
|---:|---|---|
| `+0x00` | `verts` | Vertex block. Zero for an empty row. |
| `+0x04` | `vertVariants` | Zero, or a table of 41 alternative vertex blocks. |
| `+0x08` | `normals` | Normal block. |
| `+0x0C` | `faces` | Face block. |
| `+0x10` | `texmap` | Texture/material block. |
| `+0x14..+0x1C` | `s32 x, y, z` | Joint offset from the parent part, in model units. The game stores `(x, y, −z)` as the translation of the joint's local matrix. |
| `+0x20` | `s32 parent` | Parent **draw-part index**, or −1. |
| `+0x24..+0x2C` | — | Zero in all models. |
| `+0x30` | `u32 active` | 1 when the row has geometry. |
| `+0x34` | — | Zero. |

1,043 of 1,404 rows are active. Row 0 is active but has no geometry (0 vertices); rows 20–26 are optional attachments.

### Draw parts, rows and matrices

The fighter has 22 draw parts (`FighterPart`, 0x28 bytes at fighter `+0x4F0`). Two EXE tables map part `k` to a row and to an animation matrix slot:

| Part | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 | 21 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Row (`0x8001A05C`) | 0 | 1 | 3 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 21 | 22 | 23 | 24 |
| Matrix (`0x8001A074`) | 0 | 1 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 2 | 18 | 19 | 20 | 21 |

Rows 2, 4 and 20 are drawn as the second meshes of parts 1, 2 and 17 (below); rows 25 and 26 are empty in all 52 models. Parts 18–21 (rows 21–24, costume attachments) are drawn only when enabled by the byte at `0x80096222 + 6·slot + part` (`FUN_80037E78`, 0 for parts below 18); the table enables exactly the attachment rows that the slot's model contains (for example slots 6, 15, 27, 32, 33, 36 and 41 use parts 18–20, slot 38 all four); for Mokujin (character 15, slots 30 and 31: a stick held by part 16) `FUN_800363B0` then rewrites part 18's draw flag every frame in `FUN_8003AA6C`, drawing the stick only while his copied bank is Yoshimitsu's (bank type 4) (confirmed in the harness: fights with banks 1, 4 and 6, and the third attract demonstration); part 0 has no primitives (table `0x8001A08C` = −1).

The parent field indexes **parts**, not rows. For `paul3.kmd` the hierarchy is:

| Part | Row | Parent part | Offset `(x,y,z)` | Probable body segment (inferred from topology) |
|---:|---:|---:|---|---|
| 0 | 0 | −1 | 0,0,0 | root/waist |
| 1 | 1 | 0 | 0,0,0 | chest |
| 2 | 3 | 0 | 0,0,0 | pelvis |
| 3, 6 | 5, 8 | 2 | 159,0,±100 | thighs |
| 4, 7 | 6, 9 | 3, 6 | 440 / 439 | shins |
| 5, 8 | 7, 10 | 4, 7 | 439 / 440 | feet |
| 9, 13 | 11, 15 | 1 | 349,0,±100 | shoulders |
| 10, 14 | 12, 16 | 9, 13 | 139 / 140 | upper arms |
| 11, 15 | 13, 17 | 10, 14 | 299 / 300 | forearms |
| 12, 16 | 14, 18 | 11, 15 | 229 | hands (rows with 41 vertex variants) |
| 17 | 19 | 1 | 399,0,0 | head |

Bones run along local +X. Segment names are inferences from the chain structure and offsets.

## Vertex block (`verts`)

```text
u32 lead                       # = 2 * (1 + nImportScratch + nImportGlobal)
u32 nImportScratch; u8 idx[n]  # packed 4 per word, word-aligned
u32 nImportGlobal;  u8 idx[n]
u32 count; SVECTOR v[count]    # s16 x, y, z, pad (pad = 0)
list blendA   (9-bit entries, 3 per word)
list addGlobal (9-bit)
list addScratch (9-bit)
list exportGlobal (9-bit)
list exportScratch (9-bit)
list halve (2-bit codes, 16 per word)
```

Every list is `u32 count` followed by `ceil(count / per_word)` words. A 9-bit entry is `index | half << 8`; `index` is a byte offset into an exchange buffer, meaning slot `index/2 − 1`.

`DrawSkinnedPart` fills a per-part slot array in the scratchpad (screen XY at `0x1F800000 + 4·slot`, Z/32 at `0x1F8001B8 + 2·slot`):

1. **Imports** copy slots sequentially to slot 0, 1, …: first from the scratchpad itself (the slot array left by the previously drawn part), then from the global exchange buffer (`0x8009C0F4`/`0x8009D0F6`).
2. **Own vertices** are transformed with RTPT/RTPS (current joint matrix) into the following slots.
3. Post lists walk the own vertices **consecutively** in this order, each entry consuming the next own vertex:
   - `blendA`: `own = (half ? own/2 : own) + global[idx]`, written back to the vertex and to `global[idx]`.
   - `addGlobal`, `addScratch`: `own = (half ? own/2 : own) + buffer[idx]`.
   - `exportGlobal`, `exportScratch`: if `half`, halve the vertex; then `buffer[idx] = own`.
   - `halve`: code ≠ 1 halves the vertex.

Halving and addition are performed on packed screen words (`xy >> 1 & 0xFFFF7FFF`, Z `>> 1`). The effect is a **0.5/0.5 blend of two joints' positions for seam vertices**, done in screen space. A remake can reproduce it with two-bone linear skinning weights of 0.5 on those vertices. Rows are processed in part order 0..21, so draw order is significant for the scratchpad imports.

Totals over 52 models: 30,529 own vertices.

### Vertex variants (`vertVariants`)

When non-zero, `vertVariants` points to 41 `u32` block pointers. `PartSelectVertexVariant` replaces `row.verts` with `table[pose]` before drawing (a zero entry keeps the current block).

**Pose selection** (`FUN_80034BC4`, every frame; values pass through the replay recorder `FUN_800332D8` so replays reproduce them):

- Two hand channels (`+0x127C` current, `+0x1280` target, `+0x1284` rate, set by `HandFaceCommand` from move events and the physics, [animation.md](animation.md#procedural-head-and-eyes)) move towards their targets by `rate` per frame. A value `v ≤ 0x200` selects variant `v/128 − 1` (0 for `v < 128`): variants 0–3 are the open-to-fist blend steps; values above `0x200` are explicit shapes, variant `v − 0x1FD` (shape `n` → variant `n + 2`).
- Channel 0 drives part 16 and channel 1 part 12 (the hands, rows 18 and 14), each including the part's second mesh. For Gon (`0x11`) and character 11 (Kuma/Panda) channel 0 drives part 17 (the head, rows 19 and 20) instead — the jaw (`confirmed`: costume slots 22 and 23, Kuma and Panda, and 42 and 43, Gon, are the only costumes whose character passes the test; `tools/research/verify_hand_poses.py` runs `FighterHandPoses` on every model relocated in RAM, 32,000 blocks equal the converter's groups). The variant numbers are the hands' (values `0..0x206` → variants 0–9). Kuma's and Panda's table is on row 20 only (row 19 has none and stays as it is; 35 and 9 vertices move, to 4 distinct blocks); Gon's is on both rows (64 and 40 vertices, 6 distinct blocks: his variants 4 and 5, shapes 1 and 2 (values `0x201`, `0x202`), close the eyelids). Variant 0 is the base block, so the head is the open mouth in pose 0 and closes as the channel value rises to the fist. The converter stores the jaw as a packed variant group (`character.pose_groups`, [character.py](../../../tools/remake_import/character.py)) and `FighterView` shows it by `FighterHands.variant[0]`; nothing in the simulation reads it.

  **Gon's head palette** (`confirmed` by the harness: `tools/research/verify_hand_poses.py` runs `FighterHandPoses` with random channel scripts for both players and compares the queued VRAM copies with this model, 3,200 steps). The faces of rows 19 and 20 with the CLUT at (48, 504) (slot 42; (64, 504) for slot 43: 34 faces: the texture pieces they sample include the eyes' strips, `confirmed` by the atlas; which other parts of the face they cover is `unknown`) change colour with the variant. `PartSelectVertexVariant` (`0x80034A98`), besides swapping the vertex block, does for Gon (character `0x11`, while `0x800B08D4` is 0, which every fight keeps) the following for **every** row it is called for, so for the head's rows with channel 0's variant and then for the hand's rows with channel 1's: when the variant differs from the one last seen (fighter `+0x1291`, 0 from the set-up), it remembers it and queues (`FUN_80029610`, run by `FUN_8002971c`) a one-row, 16-entry `MoveImage` over the head palette (`+4` rows for player 2) from the saved palette at (220, 506) (`FUN_800342A0` queues the copy of the palette to it when the fighter is set up, `FighterSetupModel`), or, for the variants 4 and 5, from (240, 506): the CLUT of the first TIM of Gon's texture sequence (all 16 entries `0x8000`, opaque black). The tables are 4 bytes per costume slot at `0x80095D40` (size index into `0x80095C90`, palette, saved palette and swapped palette indices into the rectangles at `0x80095BC0`: 5, 45 or 46, 47, 44 → 16 × 1 at (48 or 64, 504), (220, 506), (240, 506)). The queue is flushed in order before the picture is drawn, so what shows is the last copy of the frame: channel 1's call decides, and Gon's black eyelid lines (variant 4 or 5 on channel 0) show only while the hand channel also has a variant 4 or 5; with the hands open the palette is copied back at once and only the closed lids remain. The converter writes the swapped palette's atlas as `texture_swap.png` and `palette_swap` (`variants`, `texture`) in `model.json` (`character.palette_copy`, `palette_swap`); `FighterView` follows the calls (`_step_palette`). `0x800B08D4` is the overhead KO camera (`CameraDirector`, set when it takes over, cleared when the next fight starts): while it is set `PartSelectVertexVariant` leaves the palette alone, and `FUN_80034354` (the blink) does it for Gon on his moves with flag `0x40000`: it commands the jaw channel to shape 3 (`HandFaceCommand(1, 3, 1)`: value `0x202`), and once (cache `+0x1291` = 4) copies the swapped palette, which nothing copies back before the next fight is set up (`confirmed`, `tools/research/verify_gon_eyes.py`; the remake: `FighterAnimation._blink` and `FighterView.set_overhead`). Both quirks of the palette are bug entries 64 and 65 in [game-bugs.md](../code/game-bugs.md).

  **Gon's eyes' look direction** (`confirmed`: `tools/research/gon_eyes_cases.py` runs `GonEyesFollow` on 2,000 random cases that `tests/core/test_gon_eyes.gd` matches, `tools/research/verify_gon_eyes.py` runs `GonEyesSetOffset`, `FUN_8003401C` and `FUN_800342A0`, 2,400 calls for both players and both slots, 0 differences). Every frame of a fight (`FighterAnimate`, before `HeadLookAt`, which leaves Gon's yaw alone) `GonEyesFollow` (`0x80039A50`) takes the opponent's head position minus his own in the frame of his own head joint (`joints[2]`: the rotation's transpose through `ApplyRotMatrixLV`), the angle `a = Atan2Units4096(x, y)` of the result, and turns it into a shift: `a < 0x800` → `−(a / 60)` down to −17, else `−((a − 0xF00) / 60)` up to 17 (`FighterAnimation.gon_gaze`, stored in `FighterBody.gon_gaze`). `GonEyesSetOffset` (`0x80034120`) gives eye 0 the shift when it is not negative and eye 1 when it is, the other getting 0, and for each eye whose shift differs from its cache (`+0x1292`, `+0x1293`, 0 from the set-up) queues a `MoveImage` of 8 × 34 words from its saved strip's row `8 + shift` (eye 0) or `21 + shift` (eye 1) onto the strip's row 17 or 13 (`+0x100` rows for player 2). The strips are two 8 × 64 word texture pieces of the eyes, saved by `FUN_8003401C` (table `0x80095CE0`, 6 bytes per costume slot: the strip size, the window size, the two strips and their saved places, indices into the rectangles at `0x80095BC0` and the sizes at `0x80095C90`: slot 42 (432, 64) and (416, 128) saved at (448, 0) and (456, 0); slot 43 (440, 64) and (424, 128)). The neutral shifts, which leave a strip as it was, are 9 and −8 (bug entry 64). The converter writes the changes as texture patches (`tools/remake_import/gaze.py`): for the palette as loaded and swapped and for each eye the atlas rectangles that any shift changes (tiles of 8 pixels) and, for each shift, their pictures packed into `texture_gaze.png` (about 25 to 40 KB), with `gaze` in `model.json`; `GazeAtlas` pastes them over the atlas into a texture of its own and `FighterView.set_gaze` follows the cache. Every composition of the patches equals the repainted VRAM (checked over 80 random states per slot). A texture pack's larger atlas gets the patches scaled; DuckStation's packs do not have the shifted pictures either.
- True Ogre (`0x14`) instead animates part 1's second mesh (row 2, the wings) through two frame lists: `0x80095CAC` (idle, 17 frames, looping) and `0x80095CC0` (flap cycle) while `+0x128A` (airborne outside reactions) is set; row 22 follows channel 0. Row 2's variant blocks of `ogre3/ogre4` are strides into the motion bank's buffer at bank `+0x30`/`+0x34` (by costume parity, `FUN_80069A44`).

**Second meshes.** A part whose flag in `0x8001A044` is 1 (parts 1, 2 and 17) also draws the following KMD row with the same matrix (`FighterBuildPartPrims`, `FighterPart +0x0C`): rows 2, 4 and 20 are therefore the second layers of the chest, row 3's part and the head, which explains why they are never drawn as ordinary parts. Rows with variants: 14 (39 models), 18 (35), 20 (4), 19 (2), 22 (2) and 2 (2). All models except `ogre3/ogre4` store absolute offsets; there, row 2's entries 1–40 are strides relocated against an external runtime buffer (`FUN_80069A44`) and must not be read as file offsets.

## Normal block (`normals`)

Same header and import lists as the vertex block, then `u32 count; SVECTOR n[count]` (unit normals, length ≈ 4096) and two 8-bit distribution lists. Totals: 18,327 normals. With lighting enabled (`relight` argument non-zero) the renderer fills the colour slots (`u32` each; scratchpad `0x1F800290 + 4·slot`, global stash `0x8009D8F8 + 4·slot`) in this order:

1. Slot 1 onwards: the scratchpad import list, then the global import list. Entries are halfword offsets, so the source slot is `entry / 2`.
2. The lit colours of the normals: NCCT for each group of three, then NCCS for the one or two left over. The base colour `RGBC` is `0x800AE2E4`.
3. Export: starting at the first lit colour (slot `lead / 4`, where `lead = 4·(1 + imports)`), consecutive colours go to the global slots of the first distribution list, then to the scratchpad slots of the second. In the fighter models mostly row 1 exports, and the parts drawn after it import those colours for their seam vertices.

Faces then read their colours from the scratchpad slots. This order is verified slot by slot against the game (see [Verification](#verification)).

## Face block (`faces`)

Four groups in fixed order, each `u32 count` then records:

| Group | GPU primitive | Record | Count (52 models) |
|---|---|---:|---:|
| 0 | `POLY_FT3` (0x24, flat-lit textured triangle) | 8 bytes | 13,656 |
| 1 | `POLY_FT4` (0x2C) | 8 bytes | 10,658 |
| 2 | `POLY_GT3` (0x34, Gouraud textured triangle) | 8 bytes | 9,100 |
| 3 | `POLY_GT4` (0x3C) | 12 bytes | 4,068 |

Word 0 packs vertex slots as byte offsets (`slot×4`): bits 2–8 → v0, 9–15 → v1, 16–22 → v2, and for quads bits 25–31 → v3. Quads are emitted in GPU order (v0, v1, v2, v3); back-face culling uses NCLIP on v0, v1, v2.

Colour and flag fields:

| Group | Colour slots | Flags word |
|---|---|---|
| FT3 | word 1 (byte offset into the lit-colour table) | word 0 |
| FT4 | word 1 bits 2–8 | word 1 |
| GT3 | word 1: bits 2–8, 9–15 (as `>>7 & 0x1FC`), 16–31 | word 0 |
| GT4 | word 1 bits 2–8; word 2 bits 2–8, 9–15, 16–31 | word 1 |

In the flags word, bit 24 marks a **double-sided** face (878 faces) — the NCLIP sign is then used only to choose the Z bias sign — and bits 25–31 are a signed **ordering-table bias**. The OT index is `(Z[a] + Z[b] − bias)` with `Z = SZ/32`, masked to 11 bits; biases observed are −8…8 in steps of 2.

## Texture block (`texmap`)

```text
u16 P;  u16 material[P/2 − 1]   # P includes itself
u16 Q;  u8  uv[Q − 2]           # (u, v) byte pairs; Q includes itself
u8 nFT3; { u8 material, uv0, uv1, uv2 } × nFT3
u8 nFT4; { u8 material, uv0, uv1, uv2, uv3 } × nFT4
u8 nGT3; { u8 material, uv0, uv1, uv2 } × nGT3
u8 nGT4; { u8 material, uv0, uv1, uv2, uv3 } × nGT4
u16 trailer; zero padding to 4 bytes
```

Group counts equal the face-block counts, and records correspond one-to-one in order. `material` is `(tpage_bits << 8) | clut_low`. At load `FighterBuildPartPrims` writes:

```text
clut  = 0x7E00 + clut_low   (player 1)   → CLUT x = 16·(clut_low & 63), y = 504 + (clut_low >> 6)
clut  = 0x7F00 + clut_low   (player 2)   → y = 508 + …
tpage = tpage_bits + 0x06   (player 1)   → texture page x = 384 (+64 if bit 0), y = 0
tpage = tpage_bits + 0x16   (player 2)   → y = 256
```

Observed `tpage_bits`: `0x00` (4-bit, page 6), `0x01` (4-bit, page 7) and `0x80` (8-bit colour). For the four nested-costume slots 47–50, variant `k` adds `64·k` to every `u` and `0x40` to the CLUT field.

These rules match the texture upload in `FighterUploadTextures`: every TIM of ARC member 0 is uploaded at its TIM rectangle plus `(384, 256·player)`, and its CLUT at `+ (0, 504 + 4·player)`; nested costume children add `16·k` VRAM words in x and `k` rows to the CLUT y.

## Verification

- `python3 tools/research/kmd.py` parses all 52 models: 1,043 active rows, every block consumed exactly.
- `python3 tools/research/verify_kmd_skin.py` (harness test) loads each model at a RAM address, runs the game's `KmdRelocate`, then for every drawable part sets a random joint matrix, calls `DrawSkinnedPart`, and compares all scratchpad vertex slots (packed XY and Z) with the Python model of the exchange lists: **991 parts in 52 models, zero mismatches**. The same run draws with lighting on (random light and colour matrices, random base colour) and compares every colour slot of the scratchpad and of the global stash touched by the exports with the colour model: 75,284 slot comparisons with 7,611 distinct colours, zero mismatches. The lit values come from the harness GTE model; the test checks the slot bookkeeping.

## Open questions

- None known for the model format (the lighting inputs are in [stages.md](../code/stages.md#lighting)).
