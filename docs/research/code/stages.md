# Stages

A fight stage is drawn from three parts: a clear colour, a distant panorama made of a 6 × 6 grid of `stg_*.tmd` objects, and an endless tiled floor. Addresses are Japan Rev.1.

Status: resource mapping, grid layout, floor descriptor and floor kinds `confirmed` from decompiled code and the data files; per-object panorama culling is summarised.

## Stage numbers and resources

`g_stage` (`0x800AE14C`) is chosen by `StageAndMusicSelect` (`0x8004F698`) from the character record of the player whose stage is used ([`tools/research/char_records.py`](../../../tools/research/char_records.py) prints the home stage and music of every character). Mode 7 always uses stage 19; mode 8 uses `15 + level`.

| Stage | Letter | Home stage of | TMD |
|---:|---|---|---|
| 0 | a | Paul, Bryan | yes |
| 1 | b | Law, Kuma, Panda | yes |
| 2 | c | Yoshimitsu, Mokujin | yes |
| 3 | d | Xiaoyu (costumes 0/1) | yes |
| 4 | e | Hwoarang | yes |
| 5 | f | Lei | yes |
| 6 | g | Ogre, True Ogre | yes |
| 7 | n | Xiaoyu, Jin (costumes 2/3) | yes |
| 8 | i | Jin | yes |
| 9 | j | Nina, Anna, Gun Jack | yes |
| 10 | k | Eddy, Tiger | yes |
| 11 | l | King | yes |
| 12 | m | Julia, Heihachi | yes |
| 13 | t | Gon | yes |
| 14 | u | Doctor B. | yes |
| 15–18 | p, q, r, s | Tekken Force levels (mode 8) | no |
| 19 | v | Tekken Ball court (mode 7) | no |

`StageLoad` (`0x80036854`) loads logical `34 + stage` (BNS `36 + stage`, `stg_<letter>.arc`) and, in normal modes, logical `54 + stage` (BNS `56 + stage`, `stg_<letter>.tmd`).

`stg_*.arc` (count, then `(offset, size)` pairs):

| Member | Content |
|---:|---|
| 0 | TIM images uploaded to VRAM with their CLUTs (`FUN_8006E664`). In modes 7 and 8 the overlay uploads them instead (`volley.ovl` `FUN_800B5CC4`, `force.ovl` `FUN_800B4A88`: `OpenTIM`/`ReadTIM`, then `LoadImage` of the pixels and the CLUT at the rectangles of each TIM's own header, stopping at the first invalid member). These are the panorama tiles: `stg_p..s` hold 87, 93, 72 and 24 4-bit 64 × 64 tiles (16 × 64 halfwords) at VRAM x 512–703, `stg_v` 256 4-bit 32 × 32 tiles (8 × 32 halfwords) at x 512–639 plus four 64 × 64 tiles and a 216 × 204 picture at x 640. Each tile has its own 16-colour CLUT on rows 480–495. A map cell's texture word selects the tile: page `w >> 8 & 0x1F`, and u, v within the page from its low bits ([modes.md](modes.md#tekken-ball)). |
| 1 | Floor descriptor (808 bytes), copied to the floor buffer (`0x800AE150`). |
| 2 | Mode 7/8 only: the background panorama as a tile map, which replaces the normal panorama: `u16 width, u16 height`, then one `u16` texture word per cell (u, v and texture page), then one `u16` CLUT word per cell. Tekken Ball (`stg_v`, 1,028 bytes, 32 × 8): `volley.ovl` `FUN_800B5CC4` stores it (`0x800B6B28..0x800B6B34`) and `FUN_800B5F0C` draws it as 32 × 32 sprites scrolling with the camera. Tekken Force (`stg_p..s`, 64–324 bytes, 16 × 5 for level 1): `force.ovl` `FUN_800B4B44` stores it (`0x800B7078..0x800B7084`) and `FUN_800B4DF8` draws it as 64 × 64 sprites. Both are ported in `ball_sim.py` and `force_sim.py` ([modes.md](modes.md#tekken-ball)). |
| 3 | Mode 8 only: the 2,560-byte level script ([modes.md](modes.md#tekken-force)), copied to `FUN_800B15EC`'s buffer. |

## Clear colour

The background behind the panorama is a full-screen `TILE` per display buffer (`0x8009EAE0`, built by `FUN_80048548` after the panorama is set up). It is black, except (72, 104, 200) on stage 11 when `0x800AFF68` is clear. `FUN_8006DAB4` links it at the scene ordering table's last entry (`+0xFFC`, drawn first) on stage 11, whose panorama goes to entry `+0xFF4` instead of `+0xFC8`, and in True Ogre fights, which draw no panorama. Stage 11's floor tiles are grates (texels of value 0, which the GPU leaves undrawn), so the colour shows through the floor there (`inferred` from the tiles and the remake's drawing).

`StageSelectFloor` (`0x80048324`) → `FUN_80048648` prepares a second pair of tiles (`0x8009EB00`): a 368 × 80 band at y 280 in the stage's colour from `0x80097E88` (stages 0–14; black for the others). `CameraFrame` links the band at the same last entry while the counter `0x8009EB20` runs (`FUN_80048708`). `FUN_80048760` sets it to 2 (not in True Ogre fights) when the pause menu or practice's menu hands the screen back, and on every frame of the ranking pages drawn over the 3D backdrop:

| Stage | RGB | Stage | RGB | Stage | RGB |
|---:|---|---:|---|---:|---|
| 0 | 48, 40, 32 | 5 | 48, 48, 48 | 10 | 16, 40, 0 |
| 1 | 56, 40, 32 | 6 | 0, 0, 0 | 11 | 72, 104, 200 |
| 2 | 16, 24, 0 | 7 | 64, 48, 40 | 12 | 0, 0, 0 |
| 3 | 0, 0, 8 | 8 | 0, 0, 0 | 13 | 136, 136, 112 |
| 4 | 64, 64, 48 | 9 | 0, 0, 0 | 14 | 0, 0, 0 |

**True Ogre.** `0x800AFF68` is a bitmask of the fighters whose character is True Ogre (`0x14`, `FUN_800515EC`). While it is non-zero the panorama is not drawn (only the clear colour, `FUN_8006DAB4`) and a standard floor is replaced by the spotlight floor (kind 2 below) — the dark arena of the True Ogre fight.

## Panorama

`StageBackgroundSetup` (`0x8006CC44`) registers the 36 objects of the stage TMD with the cells of a 6 × 6 **visibility grid** centred on the origin; the cell size is **`10 ×` the TMD's second header word** (400–565, so 4,000–5,650 units). The cell centres are stored with each object (`FUN_8006CE00`, object record `+0x1C..+0x20`) but are not added to its vertices: the vertices are absolute panorama coordinates, and every object is transformed with the same matrix. In `stg_e` they form a box of ±1,200 units whose outer cells hold walls 769 units high and whose inner cells hold the sky at `y = −769`. Each frame `StageBackgroundDraw` (`0x8006D2FC`):

- rotates the panorama by an accumulating angle (`0x800A9650`, 4096 units; the objects are turned by `Ry(−angle)` about the panorama's origin): `FUN_8006E4A0` keeps a point 4096 units ahead of the camera (`0x800AE0D8`/`0x800AE0E0`: camera x, z plus the sine and cosine of −yaw) and the yaws of this and the last frame (`0x800A9664`, `0x800A9658`). While a round runs (`0x80097350` ≠ 0) and the yaw moved by at most one unit, the bearing from the camera to the last frame's point (`Atan2Units4096` − 0x400) minus the yaw, ·16 as `s16` and divided by 24 (2/3 of it), clamped to ±0xAA, is added: a sideways slide of the camera turns the backdrop, which then keeps its bearing like a distant scene. `FUN_8006CB40` (the round start) and `StageBackgroundSetup` straighten it (the latter also notes the camera's yaw as this and the last frame's). `FUN_8006DAB4` runs it in every drawn fight frame, at the round start, in the Ogre scene, the attract performance and behind the ranking, except in Tekken Ball, Tekken Force and True Ogre fights and on FightMain's second frame of a lagging frame (`0x800AE16C`). Ported as the remake's `BackdropTurn`, compared with the fight and flow traces;
- offsets it by one eighth of the camera's displacement from the fighters' (smoothed) midpoint, and by a per-stage height (`0x80025394`, 290–460), so the backdrop shows slight parallax but stays distant;
- selects the visible cells (`FUN_8006DC44`, visibility parameter 600, or 780 in game state 6): it walks the two edge rays of the view cone across the grid from the camera position, marks the cells they cross and the border cells between them, and maps cells to objects through `0x80025A60`; it draws at most 200 objects.

Because the translation is one eighth of the camera's displacement, the panorama is equivalent to the object geometry scaled by 8 around the fighters' midpoint, lowered by the per-stage height: in `stg_e` the walls stand 9,600 units from the midpoint, just beyond the 10 × 10-tile floor (±9,000 units).

## Floor

The floor descriptor (stage ARC member 1, 808 bytes):

| Offset | Content |
|---:|---|
| `0x000` | `u32` 0x80 (the same in every stage). |
| `0x004` | 10 × 10 tile entries, 8 bytes each (row stride `0x50`); the pattern repeats across the endless floor. |
| `0x324` | `s16` floor kind (below). |
| `0x326` | `s16` distance shading factor for kind 0 (negative = darker with distance; 0 disables shading). |

A tile entry is two words that go straight into the `POLY_GT4`:

| Bits | Word 0 | Word 1 |
|---|---|---|
| 0–15 | Base texture coordinate (`u`, `v << 8`) of the 64 × 64 texel tile | 0 |
| 16–31 | Texture page bits (mask `0x39FF0000` → the `tpage` half of `uv1`); bits 25–26 and 30–31 select one of 16 orientations: bits 30–31 pick one of four corner-offset sets (`0x8009EBA8`: corners `(0,0) (63,0) (0,63) (63,63)` and their rotations), bits 25–26 the order in which they are assigned to the four vertices | CLUT (`clut` half of `uv0`) |

`FloorSetup` (`0x800489A4`) deduplicates word 0 (masked) into a palette of at most 40 entries (one OT bucket per texture page), sets the fade distance to 10,000 units (6,500 for stages 1, 2 and 7) and enables gouraud texturing when a shading factor is present.

**Geometry.** The floor model comes from `0x8001E36C` (mode 8: `0x8001E6C4`), a compressed TMD (`FUN_80031E50`, the same LZ scheme as the compressed TIMs): 10 × 10 tiles of 1,800 units (11 × 11 vertices). Each vertex is one word, `z` in the low and `x` in the high halfword (`y = 0`, loaded by `FUN_8004A5FC`), and quad `10·r + c` lists the vertices `v0 (x0, z1)`, `v1 (x1, z1)`, `v2 (x0, z0)`, `v3 (x1, z0)` of the tile over `x0 = −9000 + 1800·c`, `z0 = −9000 + 1800·r`; mode 8 uses 10 × 3 tiles of 2,500 units (11 × 4 vertices) at a fixed `z = 0x145`. Each frame the grid is centred on the tile under the fighters' midpoint (shifted towards the camera when it looks steeply down), the texture pattern is indexed by the tile's position: `FloorDrawGrid` (`0x80049290`) walks the columns forwards and the rows backwards, so the tile over `x ∈ [1800·tx, 1800·(tx + 1)]`, `z ∈ [1800·tz, 1800·(tz + 1)]` uses entry column `(tx + 5) mod 10`, row `(4 − tz) mod 10`. A tile's texture corners come from the four corner sets at `0x8009EBA8` (built by `FloorSetup`), each listing corners for `c0..c3`: set 0 `(0,0) (63,0) (0,63) (63,63)`, set 1 `(0,63) (0,0) (63,63) (63,0)`, set 2 `(63,63) (0,63) (63,0) (0,0)`, set 3 `(63,0) (63,63) (0,0) (0,63)`. Entry bits 30–31 pick the set and bits 25–26 the order in which its corners go to `v0..v3`: `c0 c1 c2 c3`, `c1 c0 c3 c2`, `c2 c3 c0 c1` or `c3 c2 c1 c0`. Every combination is a rotation or mirror of the tile. With set 0 and order 0, texture `u` runs along `+x` and `v` along `−z`. The stage art does not tile seamlessly: in `stg_e` the colour step across a tile seam averages 18 (8-bit RGB) against 11 between neighbouring texels, which the PlayStation's resolution hides. Only quads with at least one vertex on screen are emitted, double buffered (2 × 100 `POLY_GT4`). Nothing is drawn while the camera looks up (`sin(rx + 0xEF) ≤ 0`).

**Floor kinds.** Kind 0 is `FloorDraw` (`FUN_800490F0` → `FloorDrawGrid`): vertex brightness `0x80 + table[d]·shade / 128` (clamped 0–254), where `d` is the vertex depth minus the camera's distance to the fighters' midpoint, scaled by the fade distance into the 1,024-entry table `0x8001DF6C`. Kinds 1–4 use `FUN_80049AE0`, a spotlight floor whose grey vertex colour is `K / r²` from one or two light points (clamped to 254 unless noted):

| Kind | Stages | Light | `K` |
|---:|---|---|---:|
| 1 | g | one light under each fighter (sum of both) | 253,755,392 |
| 2 | d, i, j, m, u; any kind-0 stage with True Ogre | the fighters' midpoint; clamp `0x800AE25C` = 192 (128 for stages 13 and 19 with True Ogre) | 800,000,000 |
| 3 | r (Tekken Force) | the player's root | 512,000,000 |
| 4 | Tekken Force level 4 (forced) | camera x, `z = −2000` | 414,720,000 |

## Lighting

Fighters are lit per vertex with the GTE (`DrawSkinnedPart`: `NCCT` on the skin normals, base colour `0x800AE2E4`). The stage selects the light rig from a 28-byte record at `0x8009709C + 0x1C·stage` (`FUN_80039BB4` at fight start, `FUN_8003A030`):

| Offset | Content |
|---:|---|
| `+0x00` | Ambient level: the back colour is `value >> 4` on all three channels (`FUN_8003A3B8`). |
| `+0x04` | Base RGB of the fighters' vertex colours (`0x800AE2E4`, byte order R, G, B in the low three bytes read by `ldRGB`). |
| `+0x08..+0x0A` | Main light colour B, G, R (colour matrix column 0, `<< 4`). |
| `+0x0C`, `+0x0E` | Main light pitch and yaw (4096 units): direction `(cos(yaw − 0x800)·cos p, sin p, sin(yaw − 0x800)·cos p)`, normalised; the light matrix row is its negation. |
| `+0x10` | Shadow colour (R, G, B): the fighters' drop-shadow polygons (`FighterBuildShadowPrims` `0x8003533C`, opaque `POLY_F3`/`POLY_F4`, `FUN_8003A0F0`) and the Tekken Ball shadow. |
| `+0x14`, `+0x16` | Shadow projection angles b and a (`FUN_8003A098`): `FUN_80036180` rotates the unit x axis by the angles (0, −a, −b) and builds the floor shear `0x800B0018` (identity with `m01 = −4096·dx/dy`, `m21 = −4096·dz/dy`) that flattens the shadow meshes onto the floor. |
| `+0x18` | Tekken Force shadow colour (`FUN_8003A118`): in mode 8 `FUN_800796B4` replaces the mesh shadow with four subtractive textured quads (`POLY_GT4`, texture page at (512, 0) with subtractive blending, CLUT at (272, 511)) per buffer, coloured on two corners. |

A second light shines straight up from below (direction `(0, −1, 0)`) with half the main colour (off for stage 17), and the third column is reserved for the effects' dynamic point light (`FUN_8003A160`, [effects.md](effects.md#common-conventions)). The back colour a fighter is lit with is set per fighter and frame by `FUN_8003AA6C` (`confirmed`: ported as `projection_sim.fighter_back_colour` and checked against the original in the CPU harness, `verify_projection_sim.py`), just before `FighterAnimate` draws that fighter, and it lights fighters only (`DrawSkinnedPart` is the only GTE-lit drawing in the resident code; the floor's brightness is computed on the CPU and the panorama is unlit; the Tekken Ball's ball sets its own, [modes.md](modes.md)). In order:

1. the fighter's `keepLight` flag (`+0x1888`, set while the body burns, [effects.md](effects.md)) set: `SetBackColor(0, 0, 0)` (`FUN_8003A564`), and the flash counter below does not step;
2. in practice mode (game state 5) with the flag byte of `0x800AE430 + 4·player` set: the colour in its three following bytes (R, G, B; the freeze signal, [modes.md](modes.md));
3. while the counter `0x8009E998[player]` `c` (1 to 32) is not zero: red and green are `((0x2000 − A)·(33 − c)·0x80 / 4096 + A) >> 4` (`A` the record's word `+0x00`; the product rounds towards zero), blue is the same on odd `c` and `A >> 4` on even ones; so the level starts at `0x200` (2.0 in GTE units, twice the white level), falls linearly by about `(0x2000 − A) / 32` per frame to just above `A >> 4`, and the colour flickers between white and yellow every frame. The counter is read for this frame's colour, then stepped (32 → 0). Only `FUN_8003A388` starts it (`c = 1`), and only in Tekken Force's item pick-up (force.ovl `FUN_800B4374`, mode 8): the counter is not a hit or KO flash;
4. otherwise `SetBackColor(A >> 4)` on all channels.

`SetBackColor` stores each byte `<< 4` in the GTE back colour, so the stage's own colour is `A` with its low four bits cleared (`confirmed`: the table's ambient values are `A >> 4`. Stage 4 has `A` = 2200, byte 137, and its flash gives (R, G, B) = (512, 512, 512), (500, 500, 137), (488, 488, 488), …, (149, 149, 137) for `c` = 1, 2, 3, …, 32.) `DrawSkinnedPart` writes the lit vertex colours into the primitives only when its `relight` argument is set (`FighterDrawParts`: `((0x8009E8F8 ^ 0x8009E8F8 >> 1) ^ player) & 1`, so on two frames of four, per player), so a fighter's lighting, flash included, is refreshed at half rate and the other frames reuse the colours of the buffer's last relight (`inferred` from the decompile, not run: the remake lights every frame).

| Stage | Ambient | Base RGB | Light RGB | Pitch, yaw |
|---:|---:|---|---|---|
| 0 | 93 | 176, 146, 126 | 180, 184, 152 | 384, 2560 |
| 1 | 175 | 118, 118, 118 | 188, 188, 188 | 512, 2560 |
| 2 | 137 | 126, 128, 128 | 192, 248, 164 | 512, 2560 |
| 3 | 125 | 120, 140, 248 | 234, 234, 34 | 512, 2560 |
| 4 | 137 | 126, 126, 128 | 234, 220, 188 | 512, 2560 |
| 5 | 162 | 128, 128, 128 | 174, 174, 174 | 512, 2560 |
| 6 | 112 | 176, 138, 112 | 228, 154, 74 | 512, 2560 |
| 7 | 112 | 156, 128, 126 | 152, 152, 152 | 384, 2560 |
| 8 | 137 | 128, 128, 128 | 200, 200, 200 | 512, 2560 |
| 9 | 100 | 128, 142, 254 | 210, 158, 62 | 512, 2560 |
| 10 | 112 | 136, 136, 136 | 242, 242, 242 | 704, 2752 |
| 11 | 137 | 128, 128, 128 | 200, 200, 200 | 512, 2560 |
| 12 | 137 | 128, 128, 128 | 200, 200, 200 | 512, 320 |
| 13 | 112 | 136, 136, 136 | 242, 242, 242 | 704, 2752 |
| 14 | 75 | 132, 132, 132 | 200, 200, 120 | 160, 2592 |
| 15 | 125 | 160, 130, 110 | 164, 168, 136 | 384, 3840 |
| 16 | 137 | 128, 128, 128 | 200, 114, 80 | 512, 1536 |
| 17 | 81 | 192, 192, 254 | 128, 254, 128 | 672, 512 |
| 18 | 137 | 128, 112, 96 | 200, 168, 64 | 384, 1280 |
| 19 | 137 | 128, 128, 128 | 200, 200, 200 | 512, 2560 |

The same view matrix, multiplied by a floor-projection shear derived from the light (`0x800B0018`, `FUN_80036180`), draws the fighters' shadow meshes ([pssdw-member.md](../formats/pssdw-member.md)).

Shadow fields per stage (colour R, G, B; projection angles b, a; Tekken Force shadow colour):

| Stage | Shadow RGB | Angles b, a | Force RGB |
|---:|---|---|---|
| 0 | 54, 24, 16 | 416, 2560 | 255, 255, 255 |
| 1 | 36, 32, 28 | 512, 2560 | 255, 255, 255 |
| 2 | 14, 20, 12 | 512, 2560 | 255, 255, 255 |
| 3 | 16, 16, 28 | 512, 2560 | 255, 255, 255 |
| 4 | 0, 0, 0 | 512, 2560 | 255, 255, 255 |
| 5 | 16, 16, 16 | 512, 2560 | 255, 255, 255 |
| 6 | 0, 0, 0 | 32, 2560 | 255, 255, 255 |
| 7 | 40, 24, 0 | 384, 2560 | 255, 255, 255 |
| 8 | 20, 16, 22 | 512, 2560 | 255, 255, 255 |
| 9 | 0, 20, 8 | 512, 2560 | 255, 255, 255 |
| 10 | 14, 20, 14 | 704, 2752 | 255, 255, 255 |
| 11 | 0, 0, 0 | 512, 2560 | 255, 255, 255 |
| 12 | 16, 12, 2 | 512, 320 | 255, 255, 255 |
| 13 | 14, 20, 14 | 704, 2752 | 255, 255, 255 |
| 14 | 12, 12, 0 | 160, 2592 | 128, 128, 128 |
| 15 | 48, 48, 48 | 1024, 2560 | 55, 55, 55 |
| 16 | 0, 0, 0 | 1024, 2560 | 70, 63, 59 |
| 17 | 0, 0, 0 | 1024, 512 | 80, 80, 80 |
| 18 | 0, 0, 0 | 1024, 2560 | 48, 48, 48 |
| 19 | 0, 0, 0 | 1024, 2560 | 128, 128, 128 |

## Arena limits

Normal stages are unbounded for practical purposes (`|x|, |z| ≤ 300,000`); see [fight-frame.md](fight-frame.md#arena-bounds).

## Open items

- None known.
