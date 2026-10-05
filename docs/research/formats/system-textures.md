# System textures

The textures that stay in VRAM for the whole game — fonts, HUD pieces, character portraits, effect sprites and effect palettes — are not in `TEKKEN3.BNS`. They are an archive of compressed TIMs inside the executable image. Addresses are Japan Rev.1.

Status: `confirmed` from the loader code and by decoding all members; [`tools/research/system_textures.py`](../../../tools/research/system_textures.py) lists the members and exports a VRAM image and the effect pages to `work/system_textures/` (game data, keep local).

## Archive

| Release | Address | Notes |
|---|---|---|
| Japan Rev.1 | `0x800B9378` | 127 members. |
| USA | `0x800B8D58` | Byte-identical to Japan Rev.1. |
| Original Japan | `0x800BA428` | 127 members; member 0 differs in size. |

The archive lies in the part of the executable image that later becomes the screen-overlay slot, so it is consumed once at start-up: `FUN_800B0BD0` calls `FUN_8004CD28(0x80128C9C, archive)`, which for each member decompresses one TIM into the work buffer with `FUN_80031E50` (the `.tiz` scheme, [compressed-tim.md](compressed-tim.md)) and uploads its pixel and CLUT blocks at their own rectangles (a zero rectangle skips the upload).

Layout: `u32 count`, then `count` pairs `(offset, size)` relative to the archive start. Members 32–126 are CLUT-only TIMs whose image block is just its 4-byte length.

## Contents

| Members | VRAM (words) | Depth | Content |
|---|---|---|---|
| 0 | (833, 224) 63 × 32 | 4 | Small font (digits, capitals, symbols). |
| 1 | (875, 0) 21 × 224 | 4 | Medium font. |
| 2 | (896, 0) 48 × 224 | 4 | Large font (character names, round messages). |
| 3 | (896, 208) 48 × 46 | 4 | Timer digits and `∞`. |
| 4–6 | (945–955, 0) 5 × 16 | 4 | `CPU`, `1P`, `2P` marks. |
| 7 | (896, 256) 64 × 256 | 4 | Effect page 2: fire and explosion flipbooks (32 × 32 frames). |
| 8 | (960, 256) 64 × 256 | 4 | Effect page 1: dust and smoke flipbooks, small particles, sparks, the hit star, practice labels `HIGH/MID/LOW`, pad button icons, arrows. |
| 9–28 | (944–1008, 24–255) 16 × 58 | 8 | HUD portraits, 32 × 58 pixels, of character ids 0–19 (member `9 + id`), each with its own CLUT row `480 + id`. |
| 29–31 | (960, 0), (1000, 14), (1008, 0) | 8 / 4 | Small HUD pieces. |
| 32–124 | CLUT rows 503–511 | 4 | 16-colour palettes for the fonts, HUD and effects (for example the effect CLUTs `0x7DC6–0x7DCA` at (96–160, 503)). |
| 125, 126 | (256, 509), (256, 510) 256 × 1 | 8 | Palette ramps: sixteen 16-colour steps each, used to fade effect sprites by switching the CLUT id per frame (`0x800A91C8`, `0x800B0970`, [effects.md](../code/effects.md)). |

## Character effect flipbooks

Each character ARC's member 1 (22 or 30 standard 4-bit TIMs of 32 × 32 pixels, all with zero rectangles) is the character's own hit-effect flipbook: a fire ring for Paul, blue lightning for Jin, Heihachi and Gon, a blade flash for Yoshimitsu, and so on. `FighterLoadCharacter` hands it to `FUN_80076484`, which places the frames per player: CLUT at (0, 503) for player 1 and (16, 503) for player 2, frames from x = 368 (player 1) or 496 (player 2), two 8-word frames per 16-word column, stacked down the page. The frame count per character id is the first `s16` of the 6-byte records at `0x80027BAC`.
