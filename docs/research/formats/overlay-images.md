# Overlay images

Screen and mode overlays carry pictures that are in neither `TEKKEN3.BNS` nor the [system textures](system-textures.md). Addresses are Japan Rev.1 guest addresses (overlay slots in [memory-map.md](../code/memory-map.md)).

Status: `confirmed`. [`tools/research/overlay_images.py`](../../../tools/research/overlay_images.py) finds every item below by structure, lists them and exports PNGs to `work/overlay_images/` (game data, keep local). Each loader call was traced in the decompiled overlays.

## Storage

Pictures are stored in two ways:

- **Plain TIM files.** They are uploaded with `OpenTIM`/`ReadTIM`/`LoadImage`, or as a sequence of TIMs with `FUN_8006E664` (the stage-texture uploader, [stages.md](../code/stages.md)).
- **Archives of compressed TIMs.** They use the [system-texture layout](system-textures.md#archive): `u32 count`, `count` pairs `(offset, size)`, and each member is a TIM compressed with the `.tiz` LZ scheme. `FUN_8004CD28(work, archive)` uploads every member; `FUN_8004CC04(work, archive, n)` uploads member `n` only.

Some members contain only a palette: their image block is just its 4-byte length. Others have no CLUT and use palettes that are already in VRAM. `select.ovl` archive `0x80118C48` member 8 declares a 2,275-byte image block for 36 × 31 words (2,244 bytes); the loader uses the rectangle, so the extra length is harmless.

## Inventory

| Overlay | Address | Kind | Members | Content | Loaded by |
|---|---|---|---:|---|---|
| `title.ovl` | `0x800BA6A4` | archive | 127 | Byte-identical copy of the system-texture archive, re-uploaded after the opening movie has used VRAM. | `FUN_8004CD28` |
| `title.ovl` | `0x800EC570` | archive | 15 | Title screen: the 368 × 480 8-bit `TEKKEN 3` logo picture in six strips (VRAM 512–703, CLUT rows 506–511), the Namco logo, and menu sprites (some 4-bit members without a CLUT). | `FUN_8004CD28` |
| `title.ovl` | `0x800D4FB8` | archive | 1 | 4-bit 140 × 32 sprite without a CLUT, at VRAM (384, 224). | `FUN_8004CD28` |
| `title.ovl` | `0x800D5384` | archive | 2 | Controller pictures of the options' button configuration (loaded when the options open). | `FUN_8004CD28` |
| `select.ovl` | `0x800B974C` | archive | 22 | Select-screen character pictures, one per character ID 0–20, plus a soft white silhouette mask (member 21). | `FUN_8004CD28` |
| `select.ovl` | `0x80118C48` | archive | 48 | Select-screen frame: panel strips, the `PLAYER SELECT` logo, cursor frames, arrow, small portraits, a name sheet, and palette-only members. | `FUN_8004CD28` |
| `result.ovl` | `0x800B99B4` | archive | 6 | Time attack result background: the 368 × 480 logo on a gold burst ([result screens](../code/modes.md#result-screens)). | `FUN_800F10C8` |
| `result.ovl` | `0x800D8A20` | archive | 6 | Tekken Force result background: the logo on red lightning. | `FUN_800F110C` |
| `ranking.ovl` | `0x800B96B4` | archive | 3 | The three ranking page headers, 128 × 144 at VRAM (384, 0) ([ranking screen](../code/modes.md#ranking-screen)). | `FUN_8004CC04` |
| `ending.ovl` | `0x80123C64` | archive | 62 | Theater: movie thumbnails for the Tekken 1, 2 and 3 movie lists, framed as film strips. | `FUN_8004CD28` |
| `ending.ovl` | `0x800D88D8`, `0x800D8A58`, `0x800E75D0`, `0x800EE3F0`, `0x800EEBF8` | TIM | — | Theater DISC page: a disc icon, the Tekken 1 and Tekken 2 cover pictures, a title strip, and the Japanese text asking for a Tekken disc. | `LoadImage` |
| `ending.ovl` | `0x8011E5FC`, `0x8011F7F4`, `0x801215BC` | TIM | — | Staff roll: two 4-bit font sheets and the Namco logo ([staff roll](../code/modes.md#arcade-ending-and-staff-roll)). | `FUN_801147DC` |
| `enbu.ovl` | `0x8010A5FC` | TIM list | 248 | Copy of the stage-4 textures (`stg_e.arc` member 0), uploaded once by `FUN_800D3C20`. The area is then reused as the packet buffer and for the demonstration's model archive. | `FUN_8006E664` |
| `enbu.ovl` | `0x800CB710` | ARC (2 members) | 52 TIMs | Copies of the character effect flipbooks (lightning and sparks, the same bytes as in `jin*.arc`, `hei8*.arc`, `gon*.arc`, `dr_b*.arc`, `fore*.arc`). | `FighterUploadFlipbook` |
| `enbu.ovl` | `0x800B9E60` | archive | 7 | The Tekken 3 logo on red lightning in six strips (the picture of the Tekken Force result, stored separately) and the Namco logo. | `FUN_8004CD28` |
| `force.ovl` | `0x800B0FE0` (TIMs at `0x800B1000`, `0x800B11A8`, `0x800B1350`) | ARC (3 members) | 3 | Copper, silver and gold key sprites. | `OpenTIM` on each member |

`arcade.ovl`, `practice.ovl` and `volley.ovl` contain no pictures.

Unique assets a remake needs: the title, select, result, ranking, Theater and staff-roll pictures, and the Tekken Force keys. The `enbu.ovl` TIMs and the title copy of the system textures duplicate data found elsewhere.
