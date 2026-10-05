# Arcade stages

An arcade stage is drawn in four layers. A scrolling tiled **sky** is drawn first, then a polygonal **scene** (a 256-object TMD) and an endless tiled **floor**, plus a few per-stage extras. The scene is where the PlayStation release differs most: its `stg_*.tmd` panoramas are flat painted boxes ([stages.md](../code/stages.md#panorama)), while the arcade scenes are modelled in depth, so their layers move against each other as the camera moves.

Addresses are World ver. E1 (`tekken3`). Tables live in the decompressed program, and data files are given by file-table category ([README.md](README.md#file-system)). Status: formats `confirmed` by decoding every stage and rendering it. The sky's drawing is `confirmed` by running the arcade's own routines in the CPU harness (`tools/research/verify_arcade_sky.py`: the System 12 CPU is the PlayStation's R3000A with a GTE; every stage at five camera angles matches the converter's sky pixel for pixel, with the skipped cells left undrawn as the arcade leaves them: `arcade.sky(..., retouch=False)`; the remake's sky retouches them, see Skipped cells). The scene, floor and texture-animation rules are read from the decompiled routines (`inferred` from code, not run). The converter is `tools/remake_import/arcade.py` (`--arcade`); the remake draws the result with `StageView` (remake-plan.md, Arcade stages).

## Stage numbers

`FUN_801D711C(stage)` loads a stage from category `0x8017C320[stage]`: stages 0–12 use categories 23–29, 36, 31–35. Stage 7 takes category 36, whose TIM blocks are compressed and decompressed on load. Stages 13 and 14 (Gon, Doctor B.) and the mode 7/8 courts exist only on the PlayStation.

| Stage | Category | Scene TMD (`rom`) | Cell | Prims | Content |
|---:|---:|---|---:|---:|---|
| 0 | 23 | `0x11D6678` | 4,990 | 840 | Street: elevated railway, brick buildings, graffiti walls, billboards. |
| 1 | 24 | `0x125AB7C` | 5,410 | 1,052 | Chinese palace: dragon wall, pavilion on a rock edge. |
| 2 | 25 | `0x12D550C` | 5,060 | 639 | Forest with a shrine and rock walls. |
| 3 | 26 | `0x133878C` | 4,870 | 865 | Amusement park: arcades, staircase, carousel. |
| 4 | 27 | `0x1381828` | 4,510 | 786 | Temple courtyard with gate and balustrades. |
| 5 | 28 | `0x13CE3F4` | 10,620 | 823 | Hong Kong street with signboards. |
| 6 | 29 | `0x142D82C` | 7,930 | 1,017 | Pyramid hall with pillars and fire bowls. |
| 7 | 36 | `prg + 0x283B08` | 10,120 | — | School: buildings, sports ground with goals (its TIM blocks are compressed). |
| 8 | 31 | `0x1491838` | 2,250 | 1,132 | Japanese hall with painted screens. |
| 9 | 32 | `0x152164C` | 4,130 | 1,541 | Industrial plant with towers and pipes. |
| 10 | 33 | `0x15570EC` | 3,990 | 719 | Jungle cliffs with palms. |
| 11 | 34 | `0x15C7A50` | 1,750 | 312 | Small scene (its TIMs are in category 34's files 1–2). |
| 12 | 35 | `0x15F6F2C` | 11,870 | 782 | Stone temple with a long pillared corridor. |

The arcade numbering agrees with the PlayStation stage numbers wherever both are recognisable: 0 street (Paul), 2 forest (Yoshimitsu), 3 amusement park (Xiaoyu), 4 temple with mountains (Hwoarang), 5 Hong Kong (Lei), 6 pyramid (Ogre), 10 jungle (Eddy). It is therefore taken as the same numbering (`inferred` for the rest).

## Scene TMD

The scene is a **standard Sony TMD** ([file format](https://psx.arthus.net/sdk/Psy-Q/DOCS/FileFormat47.pdf)) apart from its header:

| Offset | Content |
|---:|---|
| `0x00` | `u32 0x41`. |
| `0x04` | Cell size / 10 (the PlayStation `stg_*.tmd` uses the same convention). |
| `0x08` | `u32 256` objects. |
| `0x0C` | 256 object rows: vertex top, count, normal top, count, primitive top, count, scale (offsets relative to `0x0C`). |

Primitive packets carry the standard header `olen, ilen, flag, mode` and are `4 + 4·ilen` bytes. Vertex indices are `u16` into the object's own vertex array.

| Mode | Flag | `ilen` | Packet |
|---|---:|---:|---|
| `0x2C`/`0xAC` | 0 | 7 | Textured quad, lit: 4 × (u, v) with CBA and TSB in the first two, normal + 4 vertices. |
| `0x2D`/`0xAD` | 1 | 7 | Textured quad, unlit: 4 × (u, v), RGB, 4 vertices. |
| `0x3C` | 0 | 8 | Textured Gouraud quad, lit: 4 × (u, v), 4 × (normal, vertex). |
| `0x3D`/`0xBD` | 1 | 10 | Textured Gouraud quad, unlit: 4 × (u, v), 4 × RGB, 4 vertices. |
| `0x24`/`0x25`, `0x34`/`0x35` | 0/1 | 5–8 | The triangle forms of the above. |
| `0x29` | 1 | 3 | Flat untextured quad. |

Bit `0x80` of the mode is set on about 10 % of the packets, and the packets keep the standard size (meaning `unknown`). Vertices are absolute scene coordinates with y = 0 at floor level and up negative. The scenes extend 1,400–9,500 units from the centre.

**Textures.** The other files of the stage's category are TIM blocks, plain TIMs back to back ending with four zero bytes (`FUN_801DB408` uploads them in order). Images and CLUTs go anywhere in the 1024 × 1024 VRAM. The texture page decodes as on the PlayStation plus **bit 11 = +512 rows**, and the CBA y is 10 bits:

```text
page_x = 64 * (tsb & 15)
page_y = 256 * ((tsb >> 4) & 1) + 512 * ((tsb >> 11) & 1)
depth  = (tsb >> 7) & 3            # 0 = 4-bit, 1 = 8-bit, 2 = 15-bit
clut   = (16 * (cba & 63), (cba >> 6) & 1023)
```

**Visibility grid.** The loader registers the objects on a 16 × 16 grid of `cell` units centred on the origin (`FUN_801D73E4`). The object row order is the cell order, row-major from (−7.5 cells, −7.5 cells).

## Scene drawing

`FUN_801D9118` (every fight frame, via `FUN_801D8FD0`) follows the PlayStation's `StageBackgroundDraw`, with different constants:

- **Turn.** It keeps a backdrop turn angle (`0x8021FB60`) updated by `FUN_801DB238`, identical to the PlayStation's (a sideways slide of the camera turns the scene by `(bearing − yaw)·16/24`, clamped to ±`0xAA`, only while the yaw moved by at most one unit). The scene is rotated by `Ry(−turn)`.
- **The floor does not turn.** The floor (`FUN_801A941C`) is drawn in world axes from the tile under the camera target, without the turn, so after a sideways slide the scene's ground and wall bases meet the floor's outer edge square at an angle (the edge kinks or humps against the surroundings; stages 1, 8 and 11 show it most from a raised camera: `--stages --stage=8 --turn=400 --height=3200 --distance=7000 --pitch=260`). `inferred` from the code and the remake's stage viewer, not checked against the arcade's picture. The remake keeps it (game-bugs.md #67, decision of 2026-10-05).
- **Translation.** It translates by **one tenth** of the camera's displacement from the fighters' midpoint: x, z from the midpoint (smoothed as on the PlayStation: one fighter's 4-frame mean and the other's current position, chosen by `FUN_801CEB2C`, or the raw midpoint), and y from `0x8017C454[stage] − camera y`, which is 50 for every stage. The scene is therefore the TMD **scaled by 10** about the fighters' midpoint (8 on the PlayStation), its origin 50 units below the floor.
- **Vertical rows.** The view matrix row 1 is scaled by 95/100 (stage 3 by a further 7/10), and the camera rotation's row 1 by `10/16 << interlace`.
- **Culling.** Cells are selected with the view cone as on the PlayStation (`FUN_801DA734`, radius `cell·14/20`), at most 256 objects.
- **True Ogre.** Not drawn while a fighter is True Ogre (`0x8021FDA0`); the sky is then drawn alone.

## Sky

The sky is a 2D panorama of 64 × 64 tiles behind everything, set up by `FUN_801A71AC` and drawn by `FUN_801A7688(buffer, yaw)`. It is the arcade counterpart of the PlayStation's Tekken Force and Tekken Ball tile maps. Per-stage record at `0x801749A0 + 20·stage`:

| Offset | Type | Meaning |
|---:|---|---|
| `+0x00` | `s16` | `cols`: texture tiles per row (the texture repeats around the horizon). |
| `+0x02` | `s16` | `rows`. |
| `+0x04` | `ptr` | Texture words, `rows × cols` `u16`. |
| `+0x08` | `ptr` | CLUT words, `rows × cols` `u16` (CBA). |
| `+0x0C` | `ptr` | Cell map, `rows × mapw` bytes, `mapw = (184320 / span) >> 6`: `'1'` draw the tile, `'d'` (100) fill with the lower colour (whatever its enable flag), `'t'` (0x74) fill with the tint colour, anything below `'1'` skip. |
| `+0x10` | `s16` | Vertical offset in pixels (halved in 240-line mode). |
| `+0x12` | `u16` | `span`: degrees of yaw per 512 screen pixels. |

A texture word `w` selects a 64 × 64 4-bit tile: `u = 64·(w & 3)`, `v = 64·((w >> 2) & 3)`, page x `(w >> 8) & 15`, `+256` rows if bit 12, `+512` rows if bit 13.

**Scrolling.** The horizontal pixel offset is `((−yaw) & 0xFFF)·512·360 / (span·4096)`. The texture column is the offset modulo `64·cols`, and the map column the same modulo `64·mapw`, so the cell map covers the full turn while the art repeats. The vertical position is `y = (−pitch · k >> 8) + offset`, with pitch signed from the camera's x angle, `k = 0x80174AA4[stage]` (halved in 240-line mode) and rows 64 pixels apart (32 in 240-line mode, drawn as stretched `POLY_FT4`). Nine tiles cover a 512-pixel row.

**Fills.** `0x80174AC0 + 12·stage` holds three colours: tile tint, upper fill and lower fill, each with an enable flag in its top byte. The upper fill covers the screen above the sky when `y > 0`, and the lower fill covers it from below the last row to three quarters of the screen height.

Stage exceptions: stage 3 draws a vertical gradient `POLY_G4` from (0, 20, 102) to black over 192 lines instead of tiles, then black to three quarters of the screen; stage 6 draws one full-screen tile; stages 0, 5 and 11 keep `y ≤ 0`, and stage 11 keeps `y ≥ −192`. Stage 5's row 3 is drawn as `POLY_FT4` whose `v` runs from the tile's bottom to its top: upside down (a reflection).

**Skipped cells.** Cells below `'1'` in the map (the maps use `'0'`) are not drawn at all, so the framebuffer's clear colour (`inferred`: black, as in True Ogre fights, where the sky is drawn alone) shows in them wherever the scene does not cover them: stage 0 skips 74 of its 240 cells (15 full-height columns, about 75° of yaw), stage 1 68, stage 2 60, stage 4 29, stage 5 175, stage 7 72, stage 8 135, stage 9 11, stage 10 59 and stage 12 16; stages 3 and 11 have none, and stage 6 draws one tile whatever its map says (game-bugs.md #68). The sky is drawn with the camera's yaw minus the backdrop's turn (`FUN_801D8FD0`: `_DAT_802C6BD8 − DAT_8021FB60`; the remake's scene and sky both take the turn), so it swings round with the scene and the camera can reach the skipped cells (the arcade's own demonstration script, `FUN_801E1758`, stops drawing the scene once its fade counter `DAT_8021F9B0` passes 0xBF and then draws the sky with the plain yaw, `DAT_8021F9C0`; the remake's demonstration plays the PlayStation's performance, which it draws with the turn throughout, so nothing differs there that the remake shows); how far the arcade's own cameras let it is `unknown`. The converter retouches them as the art meant (decision of 2026-10-05): a skipped cell is drawn as its own tile, `words[row·cols + column mod cols]`, the picture repeating round the horizon (`arcade.sky_cell`). The `'d'` and `'t'` fills are kept (stage 5's beige and dark cells, stage 8's and 12's black blocks).

**Fill cells.** The `'d'` and `'t'` cells are drawn with one `TILE` per screen slot (row and ninth of the row, one set per display buffer). A `'d'` cell writes the lower colour into its slot's tile, and a `'t'` cell draws the tile without setting a colour. The setup fills every slot with the tint, so a `'t'` cell shows the lower colour once a `'d'` cell has passed through its slot (game-bugs.md #62). Only stage 5's bottom row has both kinds; the converter keeps the tint there.

## Floor

The floor is the PlayStation's design ([stages.md](../code/stages.md#floor)) with larger tiles:

- **Geometry.** A compressed TMD at `0x801751B4` (one object, 11 × 11 vertices, 100 quads), decompressed by `FUN_801A8594`. The tiles are **2,500** units (`FUN_801A941C`: the grid is centred on the tile under the camera target, `(x + 1250) / 2500`).
- **Split tiles.** `FUN_801A941C` walks the grid by rows of growing z, then growing x (tile row `r`, column `c` lies over `x ∈ [2500·(ix − 5 + c), …]`, `z` likewise, with `ix, iz` the tile under the camera target). A tile is drawn when its four corners have a non-zero depth (`SZ`) and one corner's `sx` lies in 0–511 and one corner's `sy` in 0–239 (0–479 interlaced). A drawn tile is split into its 2 × 2 quarter-tile entries while fewer than 11 are, when a corner's `SZ` is below `|camera y| · 4096 / sin(pitch + 0xEF) + 0x801FF390[stage]` (−1,200 … 1,600; 0 when the sine is 0) or when the pitch is `0x400`–`0x600` (looking down). The others are drawn from their tile entry, the same picture at half the resolution (and slightly different colours in some stages). The quarters' vertex colours are the averages of the tile's corners.
- **Descriptor.** `0x801748EC[stage]` (8-byte rows) points to a 4,008-byte descriptor in the program:

| Offset | Content |
|---:|---|
| `0x000` | `u32 0x80`. |
| `0x004` | 10 × 10 tile entries, 8 bytes each, row stride `0x50`: the PlayStation entry format (word 0 `u | v << 8 | tpage << 16` with the orientation bits, word 1 the CBA). |
| `0x324` | 10 × 10 × 4 quarter-tile entries (row stride `0x140`, the second sub-row at `+0xA0`, column `+0x10`, right quarter `+8`): used when a tile is split (above). A quarter takes the corner set of its tile's entry (bits 30–31) and its own order bits (25–26). |
| `0xFA4` | `s16` floor kind: 0 plain with distance shading, 1 and 2 spotlight floors (as the PlayStation's kinds). |
| `0xFA6` | `s16` distance shading factor (−25 … −76). |
| `0xFA8` | `s16` non-zero: an extra per-frame effect (`FUN_801A84A8`). |

The floor tiles are the last 64 × 64 TIMs of the stage's TIM blocks.

## Extras

- **Animated textures.** Stages 6 and 12 upload category 39's TIM block (16 pictures of 64 × 64 4-bit texels at VRAM x 512 and 528, y 0–960) and animate their fire bowls with it (`FUN_801E2090`, `FUN_801E2114`). Every frame of the stage's display a counter advances; at 4 it is reset and the next of 16 source rectangles from the table `0x8020456C` (`u16 x, _, y, _`) is copied (`MoveImage`, 16 × 64 words) to (16, `0x380`) on stage 6 or (16, `0x3C0`) on stage 12, cycling. The scene shows that block through its own CLUT; until the first copy it shows the uploaded picture.
- **Animated props** (`confirmed` in the harness: `tools/research/verify_arcade_props.py` runs the game's routines frame by frame against `arcade_props_sim.py`). Stages 3 and 11 load files 1… of categories 41 and 40 as one-object TMDs (`FUN_801E2258`), drawn with the scene's matrices, so in scene units (`FUN_801E2A68`; unlit, back faces culled; untextured lit packets keep their colour, which the GPU draws as is: the converter turns it into linear light, while textured packets' colours scale the texels with 0x80 = 1). Stage 3: a carousel (four props, `RotMatrix` = Rx·Ry·Rz, prop 0 turns −5 a frame for 0x88 frames and restarts). Stage 11: a helicopter, body and main rotor (`RotMatrixYXZ` = Ry·Rx·Rz, the rotor at body offset (0, −300, 0); file 3, a tail rotor (one 170 × 20 quad in the plane x = 0, colour (0x17, 0x0C, 0x0A)), is loaded, given the body offset (0, 0x118, −0x4CE) and spun +0x29F about x every frame (`FUN_801E40C0`), but `FUN_801E2C64` draws only the first two objects (capstone: two `FUN_801E32BC` calls), so the arcade never shows it; at that offset it would hang below the tail fin, in the fin's plane, which suggests it was left unfinished), shown only after the round's end or in replays (`FUN_801E2A2C`); started each round (`FUN_801E3DE0`) in one of four modes chosen by the first player's held attack buttons (0x200 LP, 0x100 RP, 0x40 LK, 0x20 RK: `FUN_8018F070` picks a pose with the same bits in the order the PlayStation's `FighterStartWinPose` uses □ △ ✕ ○) or the counter's low bits: 0 hovers and circles to stay in view after the camera turned more than 0x17C, 1–3 fly scripted figures (`FUN_801E4A0C`, `FUN_801E4E04`, `FUN_801E54B4`). Mode 0's circling never runs in the game (game-bugs.md #63).
