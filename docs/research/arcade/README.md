# Arcade version (Namco System 12)

The arcade Tekken 3 runs on Namco System 12. That board has the PlayStation chipset (R3000A with GTE, PS GPU) with a faster CPU, a 1024 × 1024 VRAM, banked data ROMs and a C352 sound chip driven by an H8/3002. This part of the documentation describes the arcade data as a source of assets the PlayStation release does not have. The main asset is the polygonal stage scenery, which the PlayStation port replaced with flat panoramas ([stages.md](../code/stages.md#panorama)).

Status: ROM layout, program compression and file system `confirmed` (decoded and compared with MAME RAM dumps); stage formats in [stages.md](stages.md); character models, their attachment dynamics and the motion streams below; the program's structure in [Program structure](#program-structure).

The arcade's game logic is documented against the PlayStation build, subsystem by subsystem. The remake's arcade build ([remake-plan.md](../../remake-plan.md#m6-arcade-only-build)) is written from these:

| Document | Subject | How far it is proven |
|---|---|---|
| [fight-frame.md](fight-frame.md) | The fight frame, round flow, round HUD, camera director | Read on both builds; the frame's order and the round flow by the fight traces. |
| [moves.md](moves.md) | Move rows, slots, branch lists, tables | Read and measured on the data; the running fighters by the fight traces. |
| [combat.md](combat.md) | Attacks, collision, reactions, physics, skeleton and pose | Read; the pose pipeline and combat by the fight traces. |
| [ai.md](ai.md) | The CPU opponent | Read on both builds; the port's own trace in progress. |
| [flow-and-screens.md](flow-and-screens.md) | The whole game's states, ladder, unlocks, 2D screens, asset catalogue, text system | Read and observed in MAME; the flow by the flow traces, [section 6](flow-and-screens.md#6-proof-and-corrections). |
| [audio-and-effects.md](audio-and-effects.md) | C352 bank, the H8's sequencer, sound commands, effect objects | Read; nothing of the sound is ported. |

## Source set

The set is MAME's `tekken3`, *Tekken 3 (World, TET2/VER.E1)*. It has nine clones (`tekken3a`…`tekken3ud`) that differ only in the program ROM pair, plus `tekken3a`'s own flash pair. MAME 0.289 verifies the set (`mame -verifyroms tekken3`).

Notation: `rom` addresses below are offsets in MAME's `bankedroms` region, so `rom0` starts at 0, `rom1` at `0x800000`, `rom2` at `0x1000000` and `fl3` at `0x1800000`. `prg` is the 4 MB program region.

| Region | Files | Size | Content |
|---|---|---:|---|
| `maincpu:rom` (`prg`) | `tet2vere1.2e` / `.2j` | 4 MB | BIOS (`COH-100`, "PS-X ROM monitor Ver.2.4b") up to `0x28000`, the compressed game program from `0x28000`, data files from about `0xE6000`. |
| `bankedroms` 0x0000000 | `tet1rom0l.6` / `u.9` | 8 MB | Character models (`3DMK`) with their TIMs, collision hulls, compressed images. |
| 0x0800000 | `tet1rom1l.7` / `u.10` | 8 MB | Mostly compressed data (not yet classified). |
| 0x1000000 | `tet1rom2l.8` / `u.11` | 8 MB | Effect pages, then the 13 stage scenes (TMD + TIM blocks). |
| 0x1800000 | `tet1fl3l.12` / `u.13` | 4 MB | Flash bank: motion streams among others ([motions](#motions)). |
| `sub` | `tet1vere.11s` | 512 KB | H8/3002 sound program. |
| `c352` | `tet1wave0.5`, `tet1wave1.4` | 8 MB | C352 samples. |

Every ROM pair is 16-bit wide: the `l` / `.2e` chip holds the even bytes and the `u` / `.2j` chip the odd bytes. MAME loads them with `ROM_LOAD16_BYTE`; a flat image interleaves them byte by byte.

## Program compression and boot

The BIOS decompresses the whole game in one call: `0x1FC205E4 (src = 0x1FC28000, dst = 0x80010000)`, i.e. from `prg + 0x28000`. This was established with a MAME breakpoint on the routine's entry. The output is 2,837,420 bytes (`0x80010000…0x802C4BAC`), and the stream ends at `prg + 0xE55FD`. Its text, data and the BSS start agree with RAM dumps of the running game.

The scheme is the LZ of the PlayStation's compressed TIMs ([compressed-tim.md](../formats/compressed-tim.md)): each reference is two bytes `a, b`, with `length = (a >> 3) or 32` and `distance = ((a & 7) << 8 | b) or 2048`. Two details differ in the BIOS decoder:

- The token count comes from a **sentinel**. A flag byte is consumed least-significant bit first (1 = literal, 0 = reference) while the remaining value is ≥ 2; once it drops below 2, the next flag byte is read. So `0xDF` gives seven tokens, exactly like the PlayStation's fixed seven-token grammar.
- A flag byte of **0 ends** the stream, and a flag of 1 is skipped.

The game's own compressed TIMs in the data ROMs (`DF 10 00 00 00 08 …`) decode with the same rules.

Program facts used elsewhere (World ver. E1):

| Address | Meaning |
|---|---|
| `0x801E7888` | PsyQ start-up (BSS clear `0x8021F5FC…0x8037521C`, then `main`). |
| `0x8017C320` | Stage → file category, 13 × `s32` (below). |
| `0x801749A0` | Stage sky records ([stages.md](stages.md#sky)). |

The game code is a different build from the PlayStation executable. Only about 107 of the roughly 1,500 Japan Rev.1 functions match even with immediates masked, so code findings cannot be carried over by address.

## File system

All game data is read through one file table (`FUN_801BB748` builds it at start-up, `0x80273338`, 835 entries of `u32 address, u32 size`). The `address` is a `bankedroms` offset for values below `0x2000000` and `prg + (address − 0x2000000)` above. The table is grouped into 44 **categories** (`0x801FF738`: `{first entry, count}` × 44). A file is loaded by `(category, index)`: `FUN_801BB648(dest, category, index)` copies it, and `FUN_801BB618(category)` returns the count. The ROM holds the table in archive form, as a list of archive directories per category (`u32 count`, then `(offset, size)` pairs relative to the directory, `FUN_801BB6C0`).

| Category | Entries | Content (`confirmed` unless marked) |
|---:|---:|---|
| 0 | 261 | MDEC pictures played in sequence (4.5 MB). `FUN_801BE3EC` loads the next entry and `FUN_801BE474` decodes it (`DecDCTvlc`, `DecDCTin`, `DecDCTout`); `FUN_801BE180` restarts at entry 0. Every entry has the bitstream frame header: `u16` length, `0x3800`, `u16` quantiser (1–6), `u16` version (1). The attract movie: [flow-and-screens.md](flow-and-screens.md#movie). |
| 1–18 | 1–59 each | One compressed TIM per entry (273 entries, 2.3 MB decoded). Their use is `unknown`. |
| 19 | 64 | Character models of costume slots 0–31: entry `2·slot` a TIM block, `2·slot + 1` its `3DMK` model ([models](#character-models)). |
| 20 | 82 | The same pairs for slots 0–40, compressed; 4-byte entries are empty. A model here replaces category 19's (slots 7, 15, 21, 29 and 32–40 have one); a TIM block here is uploaded after category 19's (`FUN_80197e88`, `FUN_80197b38`). |
| 21 | 11 | Low-polygon hull meshes (`inferred`: collision or shadow bodies). |
| 22 | 39 | Compressed TIM sets of effect flipbooks (hit sparks, smoke, lightning): [below](#effect-flipbooks). |
| 23–35 | 3–8 each | Stage scenes 0–12: file 0 the scene TMD, then plain TIM blocks ([stages.md](stages.md)). |
| 36, 37 | 9 each | A 14th scene (TMD at `prg + 0x283B08`, cell 10,120) with eight compressed TIM blocks. Stage 7 uses category 36 instead of 30, and its loader decompresses the TIM blocks. |
| 38 | 3 | Copy of category 32. |
| 39–43 | 1–7 | Small single-object TMDs (props) and TIM sets (`unknown` use). |

Walking the directories as `arcade.py` does gives 837 entries against the 835 above; the difference is `unknown`.

## Character models

`FUN_80197b38` loads costume slot `s`'s model from category 20 entry `2s + 1` (decompressed) when that entry is longer than 4 bytes, else from category 19 entry `2s + 1`. The textures come from entry `2s` of category 19, then of category 20 (`FUN_80197e88`: each TIM's image at its rectangle plus (768, 256), its CLUT plus (768, 368), both 128 rows lower for player 2). Slots 0–40 exist: every PlayStation costume except slots 41–51 (Anna's third and fourth, Gon, Dr. Bosconovitch, Tekken Force, Gun Jack's third). The texture artwork is the PlayStation's at the same resolution, packed differently.

The format is the PlayStation's `3DMK` ([3dmk-models.md](../formats/3dmk-models.md)) with these differences (`confirmed`: the loader `FUN_80196e30`, the primitive builder `FUN_801970d4` and the skinned renderer `FUN_8019a858`; the parser `tools/research/arcade_kmd.py`, whose vertices, normals and seam weights reproduce the screen positions of a frame's primitives in a MAME RAM dump within 1–2 pixels):

- **Rows.** 24 rows; row `k` is drawn with animation matrix `k` (rows 0–17 are the PlayStation's 18 matrix slots in order, rows 18–23 six attachments). There are no second meshes. The joint offsets equal the PlayStation's within one unit. Words 9–11 are rest Euler angles in all rows (read only for attachments, `FUN_8019b634`), word 12 selects the colour buffers.
- **Vertex block.** `u32 n; SVECTOR v[n]`, then three lists of `u32 count` and `u32` entries: **imports** (global slot indices, appended after the own vertices), **exports** and **blends**. Exports and blends walk the own vertices in order; an entry is `index | weight << 16` with a 4.12 weight. An export stores `own × weight` in the global slot; a blend sets `own = own × weight + global` and stores it back. A weight of 0x1000 copies `own` instead in both. The arithmetic runs on screen coordinates (GPF), so seam vertices are weighted sums of up to three joints (for example the pelvis 0.5 and each thigh 0.25), not the PlayStation's halves.
- **Normal block.** The same layout without the blend weights: exports store the lit colour or its half, blends add the half to the global colour.
- **Faces.** The four groups and record sizes are the PlayStation's, but vertex and colour slots are bytes (256 slots per row). Triangles: word 0 bytes 0–2 are the vertices, bit 31 double-sided, bits 24–30 the ordering bias. The faces are filed in the ordering table as the PlayStation's are ([3dmk-models.md](../formats/3dmk-models.md#drawing-order); `FUN_8019A858`). Quads: word 0 bytes 0–3 (GPU order), the flags in the next word (bit 15, bits 8–14) for flat quads and in word 2 (bit 7, bits 0–6) for Gouraud quads.
- **Texture block.** Three words per face of every group: `clut << 16 | uv0`, `tpage << 16 | uv1`, `uv2 | uv3 << 16`. The renderer adds `0x5C30` to the CLUT and `0x1C` to the tpage (player 1).
- **Vertex variants.** The 41 variant blocks (the hands in rows 6 and 10, Kuma's and Panda's jaw in row 2, True Ogre's wings in row 1 and rows 18–19) are in the file with the base block's lists; how the game selects them is [below](#true-ogres-wings-and-the-variant-selection).
- **Feet.** The feet's frames (rows 14 and 17) turn 90° about y against the PlayStation's: in every frame of every motion the arcade's local foot rotation is the PlayStation's times Ry(−90°) (`inferred` from the motion comparison below), so a foot vertex `v` is `Ry(−90°) · v` in the PlayStation's frame. The converter turns the feet only for the PlayStation's motions (`--arcade` with a disc); the arcade-only build plays the arcade's motions and keeps the feet as modelled, which a mesh in the PlayStation's frames would show turned 90° sideways (`confirmed` by eye on the attract: Jin's feet point along his knees only without the turn).
- **Attachments.** The enable table at `0x801FD2E6` (`u8` per costume slot × 6 + row) is 0 (hidden), 1 (static) or above 1 (swinging). Several costumes have more attachments than on the PlayStation (Hwoarang's first, Xiaoyu's, Julia's second, Anna's), and they are part of the seam exchange. As a model loads, `FUN_80197578` turns the vertices, variants and normals of every swinging attachment by the Euler angles at `0x801FD3E4 + 8 · enable` (`EulerToMatrix`, then MVMVA, IR saturated): most turn 180° about y, so their stored geometry points along −x (`confirmed`: the turned blocks equal the loaded model in RAM dumps of ten costumes).
- **Attachment dynamics.** `FUN_8019b6d8` (each step, rows 18–23 after the skeleton) is the PlayStation's `FUN_80037F10` with other tables: the local rotation is `Euler(rest + record[0..2]) · Euler(0, yaw, pitch)`, the yaw and pitch from a blend of the direction to the attachment's tip of the last step (smoothed over `record[4]` steps), gravity (with the wind) and the rest direction; mode 1 (`FUN_8019bed0`) aims at a point on another joint, mode 2 (`FUN_8019c15c`) keeps the tip off a line fixed to another joint, slot 0x24's second attachment leans between joints 13 and 16 (`FUN_8019c598`), slots 0x1A and 0x24 clamp the angles, slot 0x26 flips its axis record. Records (s16) at `0x801FDC88 + 4 · (slot × 6 + attachment)`; axis records (six `s8`) at `0x801FD170`; clamps at `0x801FD2F0`. `confirmed`: the remake's port reproduces 3,000 random calls of the routine in the harness and 24 runs of 40 steps of the whole loop (the routine, then `CompMatrix` `0x801EF684`, for every drawn attachment in row order; `tools/research/arcade_attachment_cases.py`), and given a RAM dump's skeleton it settles on the dump's attachment joints. The wind (`FUN_8019c738`, every step before the skeleton, in the replay's frames too) blows sideways only on stage 11 (the helicopter's downwash; elsewhere the normalised vector points straight up, and only its x and z are read): `FUN_801e6acc`, at the end of each model's set-up, picks one of eight directions (`rand() & 0xE00`, then two more draws) for the first fighter when the game state is 4, slots 0x20 and 0x21 (True Ogre) still the air again, and every fighter takes four more draws, `inferred` from reading until the traces' `rand` check runs. The gust is a triangle wave of period 16 steps, which `FUN_8019c72c` starts again each round. The remake runs all this in `core` (`ArcadeBody`, `ArcadeAttachments`, `ArcadeWind`), and every fight trace compares the wind and the rows' translations with the original's joints: those depend on the parent's rotation, so they also proved the round start's head reset `FUN_801992B0`. On rows held by a freeze, an ending or a replay `FUN_8019B6D8` returns at once and keeps the local matrix of `+0x728`.
- **Eyes.** 8 `s8` per costume slot at `0x801FE370`: the eyes' rectangle and size (`0x801FCE98`, `0x801FCF1C`) and six eye shapes; see [Eye shapes](#eye-shapes).

### True Ogre's wings and the variant selection

`FUN_80194458` (every animated frame, the PlayStation's `FighterHandPoses`) chooses the variant of each row from the fighter record's hand channels and, for True Ogre (costume slots `0x20`, `0x21`; the record's `+0x1E`), a wing sequence. It writes `table[variant]` over the row's current block (`FUN_80194428`; the record's row pointer at `+0x48C + 0x1C · row` leads to the pair `{current block, table}`); the entries it replaces are those of the 41 pointers at the row's `words[1]`. In replays `FUN_80196194` / `FUN_80196304` pass the values through the recorder, in play they return them. `confirmed` by running the routine in the CPU harness on a synthetic record (`tools/research/verify_arcade_wings.py`: 600 steps of random airborne scripts for both Ogre slots, and the other costumes' hands; 0 differences from the model below) and, for the hands and jaws, on every costume's relocated model with the file's own block tables (42,000 blocks compared with the converter's groups, 0 differences).

- **Hands** (other costumes): channels `+0x1164 / +0x1168 / +0x116C` (current, target, rate; `s16`) approach their targets as the PlayStation's do, and are set by the same `HandFaceCommand` (`FUN_80194080`: a blend over `0x200 / (|speed| + 1)` for shapes 0 and 1, `shape + 0x1FF` for the others, 10 and up are face shapes) from the same inputs: the move events 14–61 (20: the reset table `0x801FE344`, all 0 as the PlayStation's open hands; 21: the costume's table `0x801FE2EC`), the attack shape (`FUN_80194250`, the table `0x801FE2EC`) and the hit shape (`FUN_80194298`, `0x801FE318`, all 0); `FUN_80194328` starts a round with the table's value. The three tables equal the PlayStation's `costume_hand_shapes` / `face_attack` / `face_hit` (`confirmed`, compared byte for byte), so the simulation's channels are the game's. Channel 0 selects the variant of row 10, channel 1 of row 6: `value >> 4` for `value ≤ 0x200` (variants 0–32, a blend from the open hand to the fist in 33 steps), `value − 0x1E0` above (variants 33–40, the shapes `shape + 31`). The variant is an index into the row's 41 blocks (`FUN_80194428` stores `table[variant]` as the row's current block, a block is not mixed with another): the models have 33 to 38 distinct hand blocks, the entries of the shapes a costume lacks repeat the fist's or another block. The PlayStation has coarser numbers (`value >> 7` − 1: 0–3; shapes `value − 0x1FD`).
- **Jaw** (Kuma and Panda, costume slots `0x16` and `0x17`; `confirmed` in the harness): their models have no hand variants. Channel 0 selects the variant of row 2, the head's mesh with the jaw (33 distinct blocks, 35 and 9 of the head's vertices move, by up to 60 and 48 units at the fist's value), by the same numbers as a hand; channel 1 still selects row 6, which has no variants (the routine leaves a row without a table as it is). The jaw is moved by the commands that close the hands (the PlayStation's models do the same with the head's second mesh, [3dmk-models.md](../formats/3dmk-models.md#vertex-variants)); Gon (the PlayStation's jaw channel 1 reads `gon_mouth`) is not in the arcade set. In a simulated fight the channel opens by up to its full range while Kuma attacks.
- **Wings** (row 1, the chest and the wings in one mesh; 40 variants, the 41st entry is the base block): `+0x115C` frame and `+0x1160` phase step with the airborne flag `+0x1158` (the PlayStation's `+0x128A`). Phase 0 (folded): airborne, the frame rises by one and the sequence `0x801FCF30` (variants 0–16, `−1` ends) is read; at its end phase 1 starts at frame 0; on the ground the frame falls by one to 0. Phase 1 (open): the frame rises by one through the beat `0x801FCF44` (variants 16–39, `−1` ends) and wraps to 0 while airborne, or returns to phase 0 at frame `0x10` when not. The variant is the table's entry at the frame. The tables are the PlayStation's (`0x80095CAC`, `0x80095CC0`, the same bytes), so the variant numbers match; the steps do not: the PlayStation's opening steps the frame by two and its first beat step by two (`FighterHands._update_wings`), the arcade's by one (the harness run and a model of both differ in most steps of random flights). Only 70 of row 1's 138 vertices move between variants.
- **Tail** (rows 18 and 19, attachments with the enable value 13): the level channel (`+0x1164`, 0 to `0x100`: `HandFaceCommand`'s shape 2 targets `0x100`, others 0, as the PlayStation's channel 0) selects variant `value >> 4` (0–16) of both rows. Row 18's variants all hold its base block's vertices; 24 of row 19's 30 move. The level for the sway is separate (`+0x1178`, target `+0x117A`, rate `+0x117C`; `+0x1296` on the PlayStation). Variants 17–40 of both rows are the base block's pointer.
- **Load turn.** `FUN_80197578` also turns the first 17 variant blocks of a swinging attachment row by the same Euler angles (skipping entries that are the base block, already turned): the harness compares every turned block of True Ogre's rows 18–21 with `arcade_kmd.variant` after relocating the file in RAM (`FUN_80196E30`), 0 differences.

The remake converts rows 1, 18 and 19 as `VariantGroup`s (only the vertices that move; `arcade_character.pose_groups`, `model.json` `wings`) and shows them by the simulation's wing variant and level channel (`FighterView.set_hands`), so the wing timing is the PlayStation's.

The hands and the jaw are `VariantGroup`s of all 41 variants too (`model.json` `hands`; channel 0 and 1, the jaw is channel 0 with part 17), stored packed: the faces of the moving vertices once (the first variant's), the part-local positions of the moving vertices of every distinct block (`poses`) and the vertex each corner position is, and a `select` list from the 41 variants to the distinct blocks; `CharacterModel` patches the corner positions into one surface set per distinct block when it loads. `FighterView.set_hands` gives an arcade model's hands the variant of `ArcadePoses.hand_variant(channel value)`, the arcade's numbers, from the simulation's `FighterHands.current` (the PlayStation's models keep `FighterHands.variant`). A closed fist is variant 32 (the old PlayStation numbers showed the arcade's variant 3, barely closed). Size: the models' `mesh.bin.gz` for costume slots 0–40 (without Mokujin's) went from 4.6 MB (ten whole-row variants per hand) to 2.7 MB.

Measured against the PlayStation's models in the same pose (PlayStation motions fit the arcade's part frames, apart from the feet): 0–56 % more triangles, typically 15 % (Paul 1,275 against 1,081; True Ogre 1,192 against 800). The texture artwork is the same.

## Eye shapes

A costume's face texture has up to six *eye shapes* (the face's eye and mouth strip) that the game copies over the face as the fighter reacts. Statuses are `confirmed` unless marked.

- **Layout.** `s8 × 8` per costume slot at `0x801FE370`: the rectangle index of the face strip (`dest`), the size index and the rectangles of shapes 0–5 (−1: the slot lacks it; slots 6–9, 22–25, 28–35 and 37 have no layout at all). Rectangles are `(x, y)` `s16` at `0x801FCE98` (16 words wide, 64 rows, in the page row 256 / 320), sizes `(w, h)` at `0x801FCF1C`; player 2's rows are 128 lower. Shape 0 is the face as loaded: `FUN_80193DD8` (round start) saves it into shape 0's rectangle and clears the state (`+0x1172` shape, `+0x1174` hold counter). `FUN_80193EA4(fighter, shape, frames)` sets the counter and, when the shape differs from the current one and the slot has it, `MoveImage`s its rectangle over the strip (skipped while the [main state](#main-loop) `0x8021FD20` is 2; `inferred`: the attract state).
- **Per frame.** `FUN_80193F90` (called from `FUN_80198298`): a move whose row has `+0x18 < 0` shows the *held* shape for 2 frames (table `0x801FE4E4`, 1 for every costume); else a lying fighter (move state bit 2 with `+0x17 = 0`) the *down* shape (`0x801FE510`, 2); then, when the counter is zero, open eyes (shape 0) become the *blink* shape for 3 frames (`0x801FE4B8`: shape 2 for slots 0–3, 12, 13, 18–21, 26, 27, 39, 40; shape 3 for 16 and 17; shape 4 for 10, 11, 14, 15, 36, 38; 0, no blink, for the rest) and any other shape becomes shape 0 for `(rand() & 0xFE) | 1` frames. Tables are `s8` per costume slot (41).
- **Shouts.** `FUN_801A104C` plays a character's attack voices (voice ids `0x2000`–`0x2008`: from a move's sound list at its first frame, or a random grunt while attacking) and calls `FUN_801A1C74(fighter, id)`, which shows a *shout* shape for as many frames as the sample lasts, by character id (`+0x1a`: `FUN_8019CAC0` maps `id × 4 + colour` through `0x801FE060` to the slot): ids 0, 1 and 7 shape 3 and id 6 shape 5, nothing for the others, with 0 frames (no visible change) for code `0x2008` of ids 0, 1 and 7. The converter reads the shapes and frame counts from the routine itself (`arcade_eyes.shouts` interprets its instructions on the program; `tools/research/verify_arcade_eyes.py` checks that against the CPU harness for every id and code). The shapes of slot 0 on screen: 1 a wince (brow down, eye shut, teeth), 2 closed eyes, 3 open mouth.
- **Not eyes.** The `s8` tables at `0x801FE2EC` and `0x801FE318` (`FUN_8019CBE4`, `FUN_8019CC10`, `FUN_8019CC3C`) are values below 10 for `FUN_80194080` (`inferred`: hand variants, which the PlayStation's face command also carries); it sends only values 10 and up to `FUN_80193EA4` (value − 10 is the shape), and only the shout code passes one.
- **Verification.** `tools/research/verify_arcade_eyes.py` runs `FUN_80193F90` (with `FUN_80193EA4`) for seven costume slots over 600 frames of held, lying and shouting inputs with a fixed `rand`, comparing the `MoveImage` copies per frame with the Python model the remake's `ArcadeFace` ports, and `FUN_801A1C74` for every id and code against the converter's tables (all match).
- **In the remake** (`inferred`). The arcade's move rows are not the PlayStation's (rows of 0x3C bytes, flags spread over bytes), so the *held* and *down* inputs are the PlayStation's own blink conditions: flag bit 18 and a lying move without the look-at flag. Across 4,015 rows present in both, the arcade's `+0x18 < 0` appears in 431, 313 of them with flag bit 18 (which 516 PlayStation rows have). The shout input is the simulation's attack voice of category `0x2` (`SimEvents.SHOUT`): the PlayStation's voice ids index the same attack list, so the frame counts by id are assumed to fit its samples. The blink's timing is the view's own, not the simulation's (3 frames closed, as in the arcade; the PlayStation's takes 4).

## Effect flipbooks

The arcade draws the PlayStation's flipbook ring ([effects.md](../code/effects.md#flipbook-ring)) with frames of 64 × 64 instead of 32 × 32. `confirmed` unless marked.

- **Sets.** Category 22, each entry compressed: one 4-bit TIM of 16 words × 64 lines per frame. Only the first TIM's CLUT is uploaded (`FUN_801af068`), so all frames go through it.
- **Records.** 0x18 bytes: `u32` set, `s16` frame count, width, height (texels), additive flag, three `s16` colour factors (R, G, B, 128 neutral), `s16` a red and green exchange, then the light colour's bytes. One per charId at `0x80175510` (22), the system sets at `0x80175720` (hit, hit without damage, guard); `FUN_801ac680` loads the dust from the record at `0x80175798` instead of the table's fourth. It would load the record at `0x80175780` (set 0, red) as the hit when the word `0x8021F7A0` is 1, but sets that word to 0 just before.
- **Palette.** `FUN_801af068` multiplies each non-zero colour by the factors (`channel · factor >> 7`, clamped to 31) and turns a result of black into `0x0400`, so that it stays opaque. With the exchange word set and the setting `0x8021FBBC` (copied from `0x8036EC5B`, the test menu's hit colour, [Settings](#settings)) red takes green's value and green red's halved (`confirmed`, the routine's code), which turns the red hit green. Of the system records only the hit's has the word. The PlayStation's hit colours are those of the unchanged palette (`inferred`, the comparison below: 2.2 levels against 16), so the converter does not exchange.
- **Size.** `FUN_801ad2fc`, the draw routine, sizes a sprite `w · (H · 0xAFE60 / 0xEEC0) / (4 · otz)` pixels wide. At the projection distance `H` = 500 a 64-texel frame is `32 · 0x2E0C / (4 · otz)`, within a part in 10,000 of the PlayStation's 32-texel `32 · 0x2E0B / (4 · otz)`, so the frames cover the same 754 world units (`inferred`: the routine's `otz` is taken to be the PlayStation's).
- **Same drawing.** Frame step, last-ten-frames fade (`0x9999`), spawn drift (`0x1900`, decaying by `0x76 / 128` per frame) and the three-slot ring are the PlayStation's. `FUN_801ac974` keeps the sets of characters 4 and 9 in spare VRAM and `FUN_801aca14` copies them over a player's (`inferred`: for the attract demonstration, whose PlayStation copies in `enbu.ovl` are the same pair).
- **Against the PlayStation** (`tools/research/compare_arcade_flipbooks.py`: every arcade strip reduced to 32 × 32 and compared with every PlayStation strip, all 54 closest to the converter's choice). The character sets are the PlayStation's frame for frame, with the same 30 or 22 frames. The system sets have more frames: hit 30 (the PlayStation's 27 are its frames 3–29), hit without damage 28 (21, from frame 1), guard 30 (25), dust 30 (27).
- **Characters.** The arcade picks by charId and the PlayStation by the costume's ARC. They differ in two places. Costume slot 36 is Anna's first and Nina's third on both, and its ARC holds Anna's set; the arcade gives Nina's third costume Nina's. The PlayStation's charId 19 (slots 44, 45) has the Mishima lightning, while the arcade's record 19 is another character's. charIds 17, 18, 20 and 21 (Tekken Force's enemies, whose record is set 4, the Mishima lightning) fit.

The remake converts these with `--arcade` (`arcade_effects.py`, used by `effects.py`): only the frames and their count, while blending, light colours and the costume's flipbook stay the PlayStation's. No record the routine loads names sets 3, 6–9, 11–16, 18–21, 25 and 29.

## Sword glow

Yoshimitsu's sword glow ([effects.md](../code/effects.md#sword-glow)) is drawn by `FUN_80192ecc`, once per fighter and frame after the parts. `confirmed`, by running the routine in the CPU harness (`tools/research/verify_arcade_sword_glow.py`, the whole 4 MB RAM compared for random fighters, views, sword matrices, buffers and frame counters).

- **Same ribbon.** The blade table (`0x801FCD00`) and the ten quads' point numbers and depth points (first four bytes and last byte of the 13-byte entries at `0x8015F0C4`) are the PlayStation's, as are the sine and octant tables, the projection (view `0x8036EBFC`, joint row 10's world matrix at the fighter `+0xA68`) and the depth entry `(SZ >> 5) − 8`.
- **Differences.** The half width is `2000 / depth` of the first point (2000 at depth 0), and the ribbon's ends are as wide as the rest. The quads are `POLY_FT4`, code `0x2E` (additive, tpage (0x3C0, 0x100) 4-bit, mode `B + F`), rebuilt every frame in the ten primitives at `0x8021FE60 + 800 · player + 400 · display buffer`; the table's other eight bytes give the four corners' texels. All four corners share the colour, and the picture does the fading.
- **Picture.** 16 × 16 4-bit texels at VRAM (960, 256) through the CLUT at (768, 375), the second player's 128 rows lower (the texels' v plus `0x80`, CLUT row 503): part of the costume textures of Yoshimitsu (slots 8 and 9) and of Mokujin (30, 31), the same in all four. The CLUT counts down in grey steps of two from white (level 31, then 28, 26 … 2, and black for index 15), the texels run from index 15 at the top left to index 0 at the bottom right, so a texel's brightness grows across the quad (u) and down (v) and the corner texel `(15, 15)` is white. The quads' texels: centre line `u = 15`, edge `u = 0`; `v` 0 or 15, the last quads' far corner 7, so the ends fade in and out.
- **Colour.** By costume slot `+0x1E` and the parity of the frame counter `DAT_8021FD58` (a timer snapshot of the main loop): slot 8 `(0x10, 0x28, 0)` / `(0x20, 0x40, 0)`, slot 9 `(0x40, 0x20, 0)` / `(0x60, 0x28, 0)`, others `(0x28, 0x18, 0)` / `(0x50, 0x28, 0)` (even / odd). Blue is 0. The routine runs for slots 8 and 9 and for the character word `+0x18` = `0xF0004` (Mokujin with Yoshimitsu's moves).
- **Remake.** `ArcadeSwordGlow` for the models converted from the arcade (Yoshimitsu's; Mokujin's stays the PlayStation's, see `PLAYSTATION_SLOTS`): golden cases `arcade_sword_glow.bin` (`tools/research/arcade_sword_glow_cases.py`), the picture's levels from the converter (`characters/arcade_sword_glow.json`, read from slot 8's textures). `inferred`: the remake takes the display buffer for the frame counter's parity.

## Motions

`FUN_8018eab4` relocates the move tables: per motion type (17 types, the PlayStation's banks 0–16), `0x8006D430 + type × 0x3B78` holds 3,806 move-row indices (the PlayStation has 4,023 slots), relocated to pointers to 0x3C-byte rows at `0x80025E8C`. A row's first word indexes the animation table (0x9838 bytes at file address `0x22DAD08`, 8 bytes per animation), whose first word is the stream's address: its top nibble 0x9, 0xA or 0xB adds 0x70387290, 0x61800000 or 0x522DAD08 (streams in the gaps of banked ROM 0–1, in the flash bank `tet1fl3`, and in the program ROM). A stream starts with its frame count; `FUN_80194744 (stream, out, frame, 57)` decodes a frame's 57 `s16` channels from keyframes every 16 frames and variable-length deltas (`confirmed` by running it in the harness, `tools/research/arcade_motion.py`): three root channels, then each joint's Euler angles, turned into its local rotation as `Euler(x, −y, −z)` (`FUN_801984a0`, `FUN_8019a498`). There is no IK: the PlayStation's pose vector (IK targets, `PoseBuildMatrices`) and spline keys are a compression of these streams.

Compared frame by frame, 96–100 % of each PlayStation bank's animations have an arcade animation of the same type and length; the joints and limb tips of matched animations lie 10–36 model units apart on average (about 1–4 cm), with single frames of fast moves up to 0.5–1 m apart where the PlayStation's splines lag a few frames behind. The arcade's foot joints turn 90° about y against the PlayStation's in every frame (see Feet).

## Program structure

How the program runs, as far as reading it shows. Here `confirmed` means read in the decompile, and in the disassembly where it says so. This section is the overview from reading; the documents listed above go further and prove what they say they prove.

### Main loop

`main` (`0x801899F4`) sets the display once ([Display](#display)), seeds the generators ([Frame wait and generators](#frame-wait-and-generators)) and then repeats these steps (`confirmed`):

1. `FUN_8019C9E0`, then the frame wait `FUN_801BBBE8`.
2. `FUN_801F21F0` (`inferred`: the test mode's entry) and a write to `0x1F018000` (`inferred`: the watchdog). Either edge of bit `0x20` of the system inputs toggles `0x8021F03A`, and while it is set the loop stays in steps 1 and 2, so the game is held.
3. The active buffer and ordering table, `FUN_801A2404`, then the routine of the state word `0x8021FD20`. Its sub-state is the word `0x8021FD64`.

| State | Routine | Role (`inferred` unless marked) |
|---:|---|---|
| 0 | `FUN_80189EC8` | Boot. |
| 1 | `FUN_801B5EEC` | Transition: `FUN_801B5EC0` enters it, and it restores the state saved in `0x8021F22D`. |
| 2 | `FUN_801BD5A0` | Attract: it sets mode 6. |
| 3 | `FUN_801BD97C` | Title and coins. |
| 4 | `FUN_801B6BA4` | Game flow: it calls the fight frame from several sub-states (`confirmed`). |
| 5 | `FUN_801C06E4` | Character select. |
| 7 | `FUN_801C241C` | After the game (weak: from the callers that set it). |
| 8 | `FUN_801E5F50` | Ending; it calls the fight frame too (`confirmed`). |
| 10 | `FUN_80192EC4` | An empty routine (`confirmed`). No assignment of 10 was found, but the copies from `0x8021F22D` and `0x80374F1E` were not traced. |

### Fight frame

`FUN_8018A988` runs one frame for the fighter records at `0x8031E154` and `0x8031FC38` (`0x1AE4` bytes apart). A nonzero `0x8021FAD0` makes it draw only. `FUN_8019541C` returns the word `0x8021F03C`, which selects the replay path (`FUN_801969B4`, `FUN_801D6C08`, then drawing) over the live one (`inferred`). The live path's calls, in order (order `confirmed`, roles `inferred`):

| Calls | Role |
|---|---|
| `FUN_8019EE00`, `FUN_8019541C`, `FUN_8019D560`, `FUN_8019DCA8` | Frame reset, replay, round flow, HUD. |
| `FUN_8018B500` (`FUN_801D009C`), `FUN_801AE9DC`, `FUN_801A6DBC` | Camera director and camera frame. |
| `FUN_801E2114` (stages 6 and 12 only), `FUN_801E3D0C` | Stage objects. |
| `FUN_80198A48` × 2, `FUN_8018C498` (`FUN_80190FF8`) | Sides, move start. |
| `FUN_8018B050`, `FUN_8018B124`, `FUN_8019F3FC`, `FUN_801A5B00` | Direction and distances, saved positions, physics, the round's body-pair step ([fight-frame.md](fight-frame.md#1-fight-frame)). |
| `FUN_8019C738`, `FUN_8018B388`, `FUN_801D8FD0` | Wind (`confirmed` above), skeleton, stage drawing. |
| `FUN_801DC758` × 2, `FUN_801DC990`, `FUN_8018B430` × 2 | Effect objects. |
| `FUN_80198BF8` × 2, `FUN_8019EF90`, `FUN_8018B808`, `FUN_8018B91C`, `FUN_8018B47C` × 2, `FUN_8018C2DC` | Collision shapes and what follows them. |
| `FUN_8018C5A4`, `FUN_8018BB68`, `FUN_8018CBD8` × 2 | Hits. |
| `FUN_801A104C` × 2, `FUN_8018B57C`, `FUN_801ADAF4`, `FUN_801AE4E4` | Voices (`confirmed` above), then conditional effects. |
| `FUN_8018B61C` (`FUN_8018E0DC`), `FUN_8018B710`, `FUN_8018C340` (`FUN_8018F528`) | Input, human or CPU (`FUN_801C3614`); the move step. |

### Game modes

The word `0x80374F18` holds the mode, and 14 functions refer to it directly. The only direct assignment is in `FUN_801BDA64(mode, players)`, which has two `jal` sites and no pointer to it in the program: `FUN_801B7810` passes 0 and `FUN_801BD5A0` passes 6 (`confirmed`, the sites from the program's words). So modes 1–5 are not entered by any direct call.

Most of what these modes would run in the flow is empty: `FUN_801B662C`, `FUN_801B6634`, `FUN_801B663C`, `FUN_801B6644`, `FUN_801B664C`, `FUN_801B6654` and `FUN_801B665C` are each `jr ra; nop` (`confirmed`, disassembly). What remains is texts, status routines and a few branches.

| Mode | Name | Flow hooks of `FUN_801B6BA4` | Status routine |
|---:|---|---|---|
| 0 | Normal | `FUN_801B6664`, `FUN_801B66D8`, `FUN_801B67E0` | `FUN_801B4514` |
| 1 | `unknown` | `FUN_801B6644` (empty) | None |
| 2 | Team | `FUN_801B662C`, `FUN_801B6634`, `FUN_801B664C` (empty) | `FUN_801B462C` |
| 3 | Time attack | Mode 0's first two, then `FUN_801B6654` (empty) | `FUN_801B46AC` |
| 4 | Survival | `FUN_801B663C`, `FUN_801B665C` (empty) | `FUN_801B46F0` |
| 5 | Practice | Returns to sub-state 0 after the fight | None |
| 6 | Attract demo | None | A constant |

The names come from the texts in `FUN_8019E034`, `FUN_801B437C` and `FUN_801BF520` (`inferred`: the last switches on the mode word through its argument). Whether a mode forced in the harness plays through is `unknown`.

### Frame wait and generators

`FUN_801BBDB8` installs `0x801BBD88` with `VSyncCallback`, which arms `0x801BBCCC` through `FUN_801F216C`. That handler increments the frame counter `0x8021F278` and the word `0x8021F8A4` (`confirmed`, disassembly). `FUN_801BBBE8` snapshots the counter into `0x8021FD58` (`FUN_801BBE04`), clears `0x8021F8A4` and spins until it is set, stepping two generators once per spin (`confirmed`):

- `0x8021FB5C`: `(x + 1) · 0x10DCD`. `FUN_801A458C`, `FUN_801A511C` and `FUN_801D59FC` step it themselves and use its top bits.
- `0x8021F838`: `x · 5 + 1` in `FUN_801B2468`. The decompile shows that routine as `void`, but it leaves the value in `$v0`, and `FUN_801B50EC`, `FUN_801B551C`, `FUN_801B557C`, `FUN_801BF6B4` and `FUN_801BF8B4` use it (`confirmed`, disassembly).

The number of spins depends on how long the frame's work took, so these two values depend on timing as well as on the game's logic (`inferred`). `rand` (`0x801E7B24`) is a separate BIOS call through `0xA0` and the wait does not step it; the decompile has 215 lines calling it in 68 functions, among them the eyes, the voices and the wind.

`FUN_801AEAB8`, called once from `main`, seeds both `srand` and `0x8021FB5C` with the sum of the first 256 scratchpad words added to `$s0` as the routine finds it (`confirmed`). It is the only `srand` call.

After the spin, `FUN_801BBBE8` waits for `0x1F083006` to be 0 (`unknown`), then `FUN_801B0BB8` polls `0x1F083200`, `0x1F083240`, `0x1F083900` and `0x1F083940` (`inferred`: coins), and `FUN_8018CD30` reads `0x1F083380` (system inputs, masked with `0x807C`, edges in `0x8021FBD8` and `0x8021FBC0`) and `0x1F083140`, `0x1F083142` (`inferred`: the players).

### Settings

The block `0x8036EC1C` (`0xDC` bytes) is a copy of the EEPROM: `FUN_801F7920` reads it from the address in `0x8021FD10` and `FUN_801F7820`, whose messages name the EEPROM, writes it back. `FUN_80189FF4` copies settings from it into words such as `0x8021FBBC` (`confirmed`).

Two tables of descriptor pointers drive the test menus: `0x8021C600` for the bytes from `0x8036EC44`, `0x801FCB58` for the bytes from `0x8036EC4F`. A descriptor has a label pointer at `+0`, the lowest and highest value at `+4` and `+5`, the default at `+6` (`FUN_801FC164` draws a value that differs from it in another colour and puts it back when out of range), the defaults at `+7` to `+0xA`, chosen by `0x8036ECF4` (`+8`, `+9`, `+0xA` for 2, 3, 4, else `+7`; `FUN_801F9B10`, `FUN_801F9A08`), and from `+0xC` a pointer to each value's label. What sets `0x8036ECF4` is `unknown`. The labels (`confirmed`):

| Byte | Setting |
|---|---|
| `0x8036EC44`, `…45` | Start cost, continue cost. |
| `…46`–`…49` | Coin mechanism values (`inferred` from a short label). |
| `…4A`, `…4E` | Credit (`…4E` mirrors `…4A`). |
| `…4B`, `…4D` | Coin counter (`…4D` mirrors `…4B`). |
| `…4C` | Free play. |
| `…4F` | Difficulty level. |
| `…50`, `…51` | Fight count: one player, versus. |
| `…52`, `…53` | Life bar: one player, versus. |
| `…54`, `…55`, `…56` | Guard damage, neutral guard, round time. |
| `…57`, `…58` | Character change: at continue, at a versus game. |
| `…59`, `…5A`, `…5B` | Music in attract, event mode, hit colour. |
| `0x8036ECF0` | Display: 0 non-interlaced, 1 interlaced (labels at `0x8021C630`). |

- **Free play.** `FUN_801B0DD0` sets `0x8021F818` when `0x8036EC4C` is nonzero, and `FUN_801B0ED8`, `FUN_801B1070`, `FUN_801B114C`, `FUN_801B13A8` and `FUN_801B1514` test that word (`confirmed`).
- **GAME OPTIONS** (`FUN_801FC164`, the descriptors from `0x801FCB58`, `confirmed`): values and the `+7` defaults. Difficulty EASY, MEDIUM, HARD, VERY HARD, ULTRA HARD (MEDIUM); fight count 1–5 for 1P and VS (2, 2); life bar −2, −1, NORMAL, +1, +2 for 1P and VS (−1, +1; the life tables at `0x8017955C` and `0x8017957C`); guard damage (OFF); neutral guard (ON); round time 20–60 s by 10 (40); character change at continue (YES) and at a versus game (NO); music in attract (YES); event mode (OFF); hit colour RED, GREEN (RED). The remake offers them in the arcade build's settings with these defaults; its traces run with the harness's bytes (`arcade_fight_harness.Settings`).
- **Hit colour.** Its default is 0, or 1 when `0x8036ECF4` is 2 (`confirmed`, the descriptor's bytes). [Effect flipbooks](#effect-flipbooks) has its effect on the palette.

### Display

`FUN_801A23C4`, the only caller of `FUN_801BB838`, passes mode 4. The routine reduces the mode with `& 3` unless `0x8021FD3C` (copied from `0x8036ECF0`) is nonzero. Its table at `0x801FF898` (16 bytes per mode) makes mode 0 512 × 240 and mode 4 512 × 480, so the game draws 512 wide, against the PlayStation's 368 (`confirmed`, the table read from the program). A test-mode routine sets `0x8036ECF0` to 0 when `0x8036ECF4` is 2, 3 or 4, else to 1, and a test menu toggles it. `FUN_801BB838` also sets `0x8036EA34` and `0x8036EA36` to `0x100` and `0xF0` (`inferred`: the screen's centre).

### Sound commands

`FUN_801B0810`, `FUN_801B086C`, `FUN_801B0924`, `FUN_801B0968`, `FUN_801B09AC`, `FUN_801B09C4` and `FUN_801B0A30` write commands to `0x1F080100 + 2 · channel` and parameters to `0x1F080200 + 2 · n`; `FUN_801B0ACC` clears them. Apart from these, only `FUN_801F58C8` (`inferred`: the sound test) refers to the two addresses, so the game's logic does not read anything back from the sound CPU through them (`confirmed` by searching the decompile for direct references).

### Program map

Address ranges by subsystem (`inferred`, from call graphs, strings and the routines named above). The decompile lists 1,667 entries, of which 1,153 have no name; the others carry library names, mostly PsyQ's.

| Range | Content |
|---|---|
| `0x80189…`–`0x8018D…` | `main`, start-up, the fight frame's helpers. |
| `0x8018E…`–`0x80192…` | Moves. |
| `0x80193…`–`0x8019C…` | Models and pose. |
| `0x8019D…`–`0x8019E…` | Round flow and HUD. |
| `0x801A0BD0`–`0x801A23…` | Sound wrappers and voices. |
| `0x801AC…`–`0x801AF…` | Flipbook effects. |
| `0x801B0…`–`0x801B4…` | Services: sound commands, coins, texts. |
| `0x801B5…`–`0x801C2…` | Game flow and screens. |
| `0x801C2F6C`–`0x801CDB38` | CPU AI (67 functions). |
| `0x801D0…`–`0x801D6…` | Camera. |
| `0x801D9…`–`0x801DB…` | Stage. |
| `0x801DC…`–`0x801E0…` | Effect objects. |
| `0x801E7888`–`0x801F21…` | PsyQ libraries. |
| `0x801F21F0`… | Test mode. |

### Against the PlayStation's data

Measured with a one-off script: every read of the converter's `tables`, `ai` and `flow` modules and of its floor fade from the PlayStation's executable and overlays, searched in the decompressed program with pointer words masked (`confirmed` as a measurement).

- **Byte for byte.** 22.4 % of the 80.7 KB occur unchanged. By reading function: `stage.convert_floor_fade` 100 %, `tables.convert` 96.5 %, `tables.vectors` 90.4 %, `tables._camera` 45.1 %, `tables._voice_set` 38.8 %, `tables._effects` 32.8 %, `flow.convert` 3.7 %, `tables.convert_fight` 3.0 %, `tables._sound_scripts` 0.7 %, `flow._exe` 0.4 %, `tables._branch_rows` and `tables._char_records` 0 %.
- **At the best alignment.** Bytes equal after aligning a table by voting on 4-byte matches: AI scripts 61.6 %, branch rows 53.7 %, flow progress 42.4 %, sequences 13.7 %, camera presets 10.3 %, character records 0 %.
- **Move rows.** The arcade's rows are 0x3C bytes against the PlayStation's 56. The gap from `0x80025E8C` to `0x8006D430` holds 4,871 of them (`inferred`: rows fill it).

So values from the PlayStation's tables hold for the arcade only where they were compared.

## Method and tools

- MAME (`brew install mame`, 0.289) runs the set. Lua autoboot scripts dump the RAM through the CPU's program space (`read_range`) and the VRAM through the GPU save item `0/p_vram` (`emu.item(...):read_block(0, count * size)`, 1024 × 1024 halfwords). Write taps and watchpoints on RAM never fire for this CPU (MAME accesses its RAM directly), but breakpoints and `trace` work through `manager.machine.debugger:command(...)` with `-debug -debugger none`.
- The decompressed program is analysed in Ghidra as a synthetic PS-X EXE (entry `0x801E7888`, BSS as above).
- Ghidra folds BSS words to 0 and then drops blocks it believes unreachable (`Removing unreachable block` at the top of a function). Every such warning in the routines the remake ports was checked with capstone (`arcade.open_set(...).prog(addr, n)`), 18 routines and about 60 blocks (`confirmed`). Most cannot run:
  - the divide traps (`break 7`, `break 6`) behind a constant divisor;
  - the sign fix-up before an arithmetic shift (`addiu 0x7FFF`, `0xFFF`, `0x3F`, `0x1F` when negative) on a value that is never negative, such as `((rand() + lcg) & 0x7FFF) · k` in the AI's draws or an 18-bit masked difference in the camera.

  Real code dropped this way:
  - `FUN_801B9138`'s button-wait restart and `FUN_801C241C`'s entry sounds ([flow-and-screens.md](flow-and-screens.md)); both were missing from the port;
  - `FUN_801B8A44`'s VS background by kind, from file `0x11` `min(kind, 2)`, plus file 3 for kind 3 (in the converter);
  - the rounding toward zero in `FUN_801984E8` (root position), `FUN_801D3970` and `FUN_801D3D14` (stream camera).

  Ghidra's whole output for `FUN_801D3970` and `FUN_801D3D14` is wrong, because it folds the sample buffer `0x8029E074` to 0. `FUN_801D4100`'s test `0x8029E07E + 0x8029E076 < 0` (the reel stream's end) is shown as unconditional.
- The CPU harness (`tools/research/psxcpu.py`) runs arcade routines too: the System 12 CPU is the PlayStation's R3000A with a GTE. The decompressed program is loaded at `0x80010000` behind a synthetic PS-X EXE header, with 4 MB of RAM and the stack moved above the BSS (`0x803FF000`). `tools/research/verify_arcade_sky.py` runs the sky's setup and drawing this way, takes the primitives from the ordering table and draws them from the stage's VRAM.
- Ghidra's COP2 site list misses libgte's register moves (VectorNormal's LZCS / LZCR); `arcade_cpu.py` adds every COP2 encoding of libgte's code (`0x801EFC00`–`0x801F1400`).
- A costume can be put into the attract mode's fights by a debugger breakpoint on the texture loader that rewrites the fighter's costume slot (`bpset 80197a08,(w@(8031e172+a0*1ae4))==a,{w@(8031e172+a0*1ae4)=24;g}` turns Nina into Anna); the RAM dumps of such frames, with the primitives of their double buffer, give the arcade's own joints and screen positions to compare with.
- Game data never enters the repository: ROM images, dumps and renders stay under the git-ignored `work/arcade/`.
