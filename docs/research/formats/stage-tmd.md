# Tekken 3 stage `.tmd` records

The original Japanese EXE names BNS IDs `56–70` as `stg_*.tmd`. All 15 records are byte-identical across original Japan, Japan Rev.1, and USA. The structures below were checked directly in Rev.1 and USA with [`inspect_stage_tmd.py`](../../../tools/research/inspect_stage_tmd.py); original Japan is covered by the bytewise [`compare_japan_revisions.py`](../../../tools/research/compare_japan_revisions.py) comparison.

The extension and first word `0x41` resemble a standard Sony TMD. However, the second word is `0x190–0x235` in these records, while the [Sony File Formats manual](https://psx.arthus.net/sdk/Psy-Q/DOCS/FileFormat47.pdf) permits only the `FIXP` bit in standard TMD flags. Fields at the conventional normal-address/count positions do not describe ordinary normal arrays either. A converter therefore needs a Tekken 3 profile; not every field has a proven meaning yet.

## Verified envelope

| Offset | Size | Observation |
|---:|---:|---|
| `0x00` | 4 | Little-endian `u32 = 0x41` in all 15 records. |
| `0x04` | 4 | Little-endian `u32`, observed values `0x190–0x235`: panorama grid cell size divided by 10 (`StageBackgroundSetup` `0x8006CC44` multiplies it by 10 and lays the 36 objects out as a 6 × 6 grid; see [stages.md](../code/stages.md#panorama)). |
| `0x08` | 4 | Little-endian `u32 = 36`; number of object rows. |
| `0x0C` | `36 × 28` | Seven 32-bit words per row; table ends at `0x3FC`. |
| `0x3FC` | variable | Consecutive primitive streams for all 36 objects. |
| after primitives | variable | Thirty-six consecutive vertex arrays; the last ends exactly at file EOF. |

Offsets in the object rows below are relative to the start of the table at `0x0C`:

| Row offset | Observed meaning and evidence limit |
|---:|---|
| `+0x00` | Vertex-array offset. Addresses increase; each next array begins exactly after `vertex_count × 8` bytes. |
| `+0x04` | Vertex count. Each vertex is four signed `i16` values: `x, y, z, 0`. The last word is zero for all 15 records. |
| `+0x08` | Standard TMD `normal_top`: points exactly to EOF in the first row, zero in the other 35. Unused: `FUN_8006CE00` reads only `+0x00`, `+0x10` and `+0x14`, and the packets carry no normal indices. |
| `+0x0C` | Standard TMD `n_normal` (small values, including zero). Unused, like `+0x08`. |
| `+0x10` | Offset of the object's first primitive. Ranges increase; the first starts immediately after the table and the last ends at the vertex area. |
| `+0x14` | Primitive count. Parsing exactly that many packets consumes the object's entire range. |
| `+0x18` | Standard TMD `scale`; zero in all 540 rows and not read. |

## Primitive packets

After three color bytes, the fourth packet byte takes only `0x24`, `0x28`, or `0x2C`. These match the textured triangle, untextured quad, and textured quad command codes described by [Sony](https://psx.arthus.net/sdk/Psy-Q/DOCS/FileFormat47.pdf). Their observed packet lengths are 20, 8, and 20 bytes respectively. In all 540 objects, the listed packet count and these lengths fill the object's byte range exactly.

For `0x28`, four one-byte local vertex indices are at packet offsets `+4…+7`; for `0x24` and `0x2C`, they are at `+16…+19`. Every used index is below its object's vertex count. In each `0x24` packet, the fourth index and bytes `+14…+15` are zero. The textured packet fields now have a verified [VRAM-to-TIM association](#verified-texture-lookup) for all 15 stages.

### Verified texture lookup

The [Sony TMD file-format manual](https://psx.arthus.net/sdk/Psy-Q/DOCS/FileFormat47.pdf) describes the UV, CBA (CLUT address) and TSB (texture page) fields for these polygon commands. In Tekken 3's 20-byte packet profile, the fields occupy the following byte positions:

| Packet bytes | `0x24` triangle | `0x2C` quad |
|---:|---|---|
| `+0..+2` | Raw RGB modulation bytes | Raw RGB modulation bytes |
| `+3` | `0x24` | `0x2C` |
| `+4,+5,+6..+7` | `u0,v0,cba:u16` | Same |
| `+8,+9,+10..+11` | `u1,v1,tsb:u16` | Same |
| `+12,+13,+14,+15` | `u2,v2,0,0` | `u2,v2,u3,v3` |
| `+16..+19` | Three local vertex indices, then zero | Four local vertex indices |

All 4,111 sequential TIMs in the 15 matching stage ARCs use TIM flags `0x08`: one 16-color palette and 4-bit image pixels. Each TIM has a `16 × 1` CLUT rectangle in VRAM and an image rectangle stored in 16-bit VRAM-word units. For every textured packet, `(tsb >> 7) & 3 = 0`, selecting the 4-bit mode. The observed CBA and TSB values have no reserved high bits set. With `u,v` from the packet, the matching coordinates are:

```text
clut_x_words = 16 * (cba & 0x3f)
clut_y       = (cba >> 6) & 0x1ff
page_x_words = 64 * (tsb & 0x0f)
page_y       = 256 * ((tsb >> 4) & 1)
vram_x_words = page_x_words + floor(u / 4)
vram_y       = page_y + v

local_pixel_x = 4 * (page_x_words - tim_image_x_words) + u
local_pixel_y = page_y + v - tim_image_y
```

[`inspect_stage_materials.py`](../../../tools/research/inspect_stage_materials.py) validates that **exactly one** TIM in the matching ARC has a CLUT rectangle containing `(clut_x_words,clut_y)` and an image rectangle containing **every** packet UV after this translation. The local pixel coordinates also stay within that TIM's image width and height. All **7,538 textured packets** match uniquely across Japan Rev.1 and USA: 338 triangles and 7,200 quads. The remaining 476 packets are untextured `0x28` quads. The association uses actual TIM VRAM destinations, rather than assuming packet order equals TIM order.

The packet mapping references 4,067 of the 4,111 TIMs. The other 44 are the last one to eight TIMs of each ARC and hold the floor tiles: every one of them contains the 64 × 64 texel rectangle and CLUT of at least one tile of the stage's floor descriptor ([stages.md](../code/stages.md#floor)), and no other TIM does. The 2,116-byte tail of `stg_m.arc` is one more 4-bit TIM (CLUT at `(192, 491)`, image `(560, 128)` 16 × 64 words, then a zero word) whose ID word is 0 instead of `0x10`: `FUN_8006E664` uploads TIMs while the ID word is `0x10`, so this texture is never loaded. A geometry converter can identify the unique coordinate-compatible TIM image and calculate per-corner local UV coordinates for each textured primitive.

**Overlapping VRAM data.** Within 13 stage ARCs, distinct TIMs contain different palette bytes for the same CLUT destination: 39 conflicting coordinate sites. These sites are addressed by 491 textured packets. However, every differing palette entry has an index absent from *all* 4-bit image pixels of the TIMs sharing that CLUT destination. Thus no palette entry actually sampled by a same-site stage TIM image differs among those uploads. The analyzer checks all image pixels, including pixels outside parsed polygons; this result does not depend on identifying the visible subregions. Across all stage ARCs, 8,080 image VRAM words are written more than once, and every repeated write has identical 16-bit data. Within each matching stage ARC, neither CLUT nor image upload order changes the sampled texel values. The other fight-time uploads cannot disturb them: stage images lie in VRAM words x 512–824 and stage CLUTs in rows 480–499 (x 0–255), while character textures and effect flipbooks use x 368–511 and CLUT rows 503–510, and the resident system textures (checked rectangle by rectangle) overlap no stage rectangle.

A converter can therefore derive stage image indices and the corresponding 16-bit CLUT entries from the matching stage ARC without resolving its internal TIM upload order.

**Drawing.** `FUN_8006CF10` copies each packet's first word (RGB + command) unchanged into the GPU primitive: `0x2C`/`0x24` textured and `0x28` flat, all opaque. Textures are therefore modulated by the packet RGB (`0x80` = unchanged), texels whose CLUT entry is `0x0000` are transparent, and STP has no effect. The vertices are the object's `x, y, z` projected by the panorama matrix ([stages.md](../code/stages.md#panorama)). There is no back-face test (no `NCLIP`): a primitive is dropped only when all its vertices are left of or above the screen, or none is left of x = 368. All primitives of the panorama go into one ordering-table entry, so they are drawn in reverse packet order behind the fighters and the floor.

| ID | Original filename | Vertices | `0x24` | `0x28` | `0x2C` |
|---:|---|---:|---:|---:|---:|
| 56 | `stg_a.tmd` | 847 | 24 | 0 | 490 |
| 57 | `stg_b.tmd` | 920 | 8 | 0 | 579 |
| 58 | `stg_c.tmd` | 1,060 | 16 | 0 | 664 |
| 59 | `stg_d.tmd` | 927 | 28 | 4 | 567 |
| 60 | `stg_e.tmd` | 791 | 80 | 0 | 456 |
| 61 | `stg_f.tmd` | 765 | 29 | 0 | 400 |
| 62 | `stg_g.tmd` | 850 | 4 | 112 | 380 |
| 63 | `stg_n.tmd` | 975 | 37 | 0 | 572 |
| 64 | `stg_i.tmd` | 828 | 0 | 4 | 500 |
| 65 | `stg_j.tmd` | 803 | 0 | 4 | 528 |
| 66 | `stg_k.tmd` | 882 | 32 | 0 | 552 |
| 67 | `stg_l.tmd` | 447 | 4 | 0 | 208 |
| 68 | `stg_m.tmd` | 924 | 48 | 72 | 438 |
| 69 | `stg_t.tmd` | 880 | 0 | 0 | 552 |
| 70 | `stg_u.tmd` | 1,010 | 28 | 280 | 314 |
| **Total** | | **12,909** | **338** | **476** | **7,200** |

The 8,014 primitive packets describe BNS data, not a count of polygons visible on screen. The vertices are absolute panorama coordinates (no per-object offset, rotation or scale); the 6 × 6 grid is a visibility grid only. The panorama rotation and parallax and the cell culling are in [stages.md](../code/stages.md#panorama); the textures are uploaded from stage ARC member 0 by `FUN_8006E664`.

## Matching `.arc` names

BNS IDs `36–50` have the same `stg_a` through `stg_u` base names in the same order as `.tmd` IDs `56–70`. Each `.arc` has two members: a 20-byte directory, four bytes of alignment padding, member 0 at `0x18`, and a directly adjacent 808-byte member 1. These 15 archives are also byte-identical between Japan Rev.1 and USA.

In 14 member-0 blocks, standard TIMs parse sequentially and end with four zero bytes. The TIM count in IDs `36–47`, `49`, and `50` ranges from 48 to 486. ID `48` (`stg_m.arc`) is the exception: its 203 TIMs are followed by a 204th TIM whose ID word is 0, which the game never uploads ([above](#verified-texture-lookup)). The game uploads the TIMs in file order (`FUN_8006E664`); placement and drawing are described above and in [stages.md](../code/stages.md).
