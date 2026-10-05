# ARC and other nested BNS resources

This document describes the 52 five-member BNS records in the repeated ID `71–278` groups. Both the strict exact-USA BNS scan and the local reproduction identify 75 ARC records. The original Japanese EXE names precisely those 75 `.arc`. A more permissive bounded-table scan also finds IDs `12` and `13`, named `makuma00.tia` and `makuma01.tia` in the original EXE. Their separate [42-member compressed TIM format](compressed-tim.md) is documented independently.

Each `.tia` has 42 members: `u32 count` at offset 0, followed by 42 `<u32 offset, u32 size>` pairs at offset 4. The directory ends at `0x154` (340), where the first member begins. Later offsets are four-byte aligned with 0–3 zero bytes after the preceding member. ID 12 is 23,928 bytes and its last member reaches EOF; ID 13 is 18,616 bytes and ends with two zero bytes. Each of the 84 members decodes to one structurally valid 4-bit TIM; see [compressed-tim.md](compressed-tim.md). Both `.tia` resources are byte-identical across the three studied releases.

## Five-member ARC directory

Each of the 52 repeated-group ARC records in Japan Rev.1 and USA has:

| Offset | Field | Verified condition |
|---:|---|---|
| `0x00` | Little-endian `u32` member count | Exactly 5. |
| `0x04` | Five `(u32 offset, u32 size)` pairs | Every member range lies within the BNS record. |
| `0x2C` | Directory end | Directory occupies 44 bytes; first payload begins at `0x30`. |
| `0x30` onward | Five member payloads | Ranges are adjacent, nonoverlapping, and end exactly at record EOF. Offsets are relative to the record start. |

This ARC layout has no separate magic string. Identify it by member count, offset/size directory, and complete range coverage. [`compare_bns.py`](../../../tools/research/compare_bns.py) checks the repeated range without assigning every bounded-table record to this exact layout.

Named stage `.arc` records at IDs `36–50` use a separate two-member profile: a TIM sequence in member 0 and 808 bytes in member 1. Their pairing with like-named `.tmd` records and the `stg_m.arc` exception are documented in [stage-tmd.md](stage-tmd.md).

## Repeated BNS groups

For `n = 0..51`, four adjacent top-level IDs are `71 + 4n` through `74 + 4n`:

| Slot | IDs | Verified byte properties |
|---:|---|---|
| `+0` | `71, 75, …, 275` | Fifty-two `3DMK` records; byte-identical across regions. Original filenames end in `.kmd`. |
| `+1` | `72, 76, …, 276` | Forty-eight `pBAV` headers; IDs `260, 264, 268, 272` have zero size. Nonempty records are regionally identical. Original filenames end in `.vh`. |
| `+2` | `73, 77, …, 277` | Fifty-two five-member ARC records; every record differs between Japan Rev.1 and USA. |
| `+3` | `74, 78, …, 278` | Fifty-two [`divmot*.bin` motion banks](divmot-banks.md) (move rows, animations, branch and event lists, all documented). Bytes are regionally identical. |

Original EXE filenames verify these extensions and examples such as `paul3.kmd`. The older `FileMap.md` calls the groups character bundles. `FighterLoadCharacter` loads a group per costume slot and handles each member as described in [memory-map.md](../code/memory-map.md#character-resources).

## Five members of IDs `73 + 4n`

The observations below were checked directly on Japan Rev.1 and USA; `python3 tools/research/compare_bns.py` reproduces the structural summary.

| Member | Direct observation | Interpretation and limit |
|---:|---|---|
| 0 | All 52 differ by region. Forty-six are standard TIM sequences followed by four zero bytes. Two begin with a CLUT-only 56-byte TIM-like prelude, then standard TIMs. Four contain a nested four-member directory whose children are TIM sequences. USA minus Japan length differences: +3,456 bytes for 46 members, +4 for four, and +6,912 for two. | The first TIM is the move-text glyph atlas ([below](#move-text-rendering-japan-rev1)); the others are the model textures. `FighterUploadTextures` uploads them in file order at `+(384, 256·player)` with CLUTs at `+(0, 504 + 4·player)`; texture modes, CLUTs and lit colours are in [3dmk-models.md](3dmk-models.md). |
| 1 | All 52 are exact concatenations of 22 or 30 standard TIMs with no tail. All bytes match across regions. | The character's hit-effect flipbook ([system-textures.md](system-textures.md#character-effect-flipbooks)). |
| 2 | Forty-eight nonempty, four empty. For each nonempty group in both regions, the adjacent `pBAV` record length plus member 2 length equals the `u32` at `pBAV` offset `0x0C`. All member bytes match across regions. | The adjacent [VAB study](vab-banks.md) verifies VH/VB assembly and exact boundaries of 785 ADPCM samples; the game's pitch, volume, pan and voice use are in [sound.md](../code/sound.md). |
| 3 | Forty-eight nonempty members begin `TK3psSDW`; four are empty. The [bounded coordinate and four-index structure](pssdw-member.md) parses fully, and all bytes match across original Japan, Japan Rev.1 and USA. | The fighter's shadow mesh ([pssdw-member.md](pssdw-member.md)), drawn with a floor-projection shear ([stages.md](../code/stages.md#lighting)). |
| 4 | Forty-eight members differ by region and contain [counted move-name/command pairs](#character-move-text-in-member-4); four members in top-level ARC IDs `261, 265, 269, 273` are empty in both regions. | The in-fight command list; every byte is decoded for both regions ([below](#move-text-rendering-japan-rev1)). |

### Member-0 special layouts

The converter's texture loader (`load_textures` in `tools/remake_import/character.py`) handles all 52 member-0 structures in both Japan Rev.1 and USA:

- **ARC IDs 241 and 245:** byte 0 starts `10 00 00 00 08 00 00 00`, followed by a 44-byte TIM CLUT block with VRAM rectangle `(240,2,16,1)`. At byte 52 is `u32 4`, which supplies only the image-block length and no image rectangle or pixels. The next standard TIM starts at byte 56. The remaining sequence has 18 and 21 TIMs respectively, then four zero bytes. [Sony's TIM definition](https://psx.arthus.net/sdk/Psy-Q/DOCS/FileFormat47.pdf) includes an image rectangle after the pixel-block byte length, so a strict standard-TIM parser correctly rejects the 56-byte prelude as an image. `FighterUploadTextures` uploads its CLUT and skips the empty image block (the next image rectangle it reads has height 0), so a converter only needs the CLUT.
- **ARC IDs 261, 265, 269 and 273:** member 0 starts with `u32 count = 4` and four `<u32 offset, u32 size>` entries. Japanese offsets start at byte 36; USA starts at byte 40 with `FF FF FF FF` at bytes 36–39. The four member sizes are `3992, 2884, 2308, 2308` bytes in both regions; extents are contiguous and end at member-0 EOF. Each child holds respectively 5, 5, 4 and 4 standard TIMs, followed by four zero bytes. The first child begins with a direct-color TIM and four indexed TIMs; the remaining children contain indexed TIMs. This is a nested container: `FighterSetupModel` uploads all four children, child `k` shifted by `16·k` words in x and `k` CLUT rows, and the model selects its variant by adding `64·k` to `u` and `0x40` to the CLUT field ([3dmk-models.md](3dmk-models.md)). These slots have no voice bank, shadow mesh or command list.

### Character move text in member 4

[`inspect_arc_move_text.py`](../../../tools/research/inspect_arc_move_text.py) consumes the entire member in each of the 48 nonempty character ARCs in Japan Rev.1 and USA with this grammar:

```text
u8 pair_count
repeat pair_count times:
    byte name[];    u8 zero terminator
    byte command[]; u8 zero terminator
byte 0xAB[0..3]  # pad entire member to a four-byte boundary
```

All names and commands are nonempty. Counts agree between regions for every ARC ID: 44 members have 20 pairs, two have 22, and two have one, giving 926 pairs with reused sets. The 48 nonempty members reduce to **21 distinct sets and 403 distinct-set pairs** in each region. The reuse partitions agree exactly across Japan and USA; six sets appear in three records each (`81/85/233`, `129/133/225`, `137/141/221`, `145/149/229`, `209/213/277`, `217/237/257`) and the other 15 appear twice. The original Japan/Rev.1 BNS comparison independently establishes byte equality for these member-4 resources.

The USA names contain printable English alongside non-ASCII glyph/control bytes; commands also use non-ASCII bytes. The Japanese strings use a different byte vocabulary and should not be decoded as Shift-JIS without a checked font map. Preserve both fields as **raw bytes** and their pair order. The game copies member 4 to `0x800A39D0 + 0x232·player` and draws it in the in-fight command list; the byte meanings of both regions are [below](#move-text-rendering-japan-rev1). Member 0 also changes in every regional ARC, so localized differences extend beyond these strings.

Pair-order comparison gives a **partial command-token correspondence** between the two regions:

| Japanese command byte | USA command byte | Operation |
|---|---|---|
| `0xBD..0xCC` | `0x80..0x8F` | Subtract `0x3D`. |
| Observed bytes in `0xD2..0xDF` | Corresponding bytes in `0x92..0x9F` | Subtract `0x40`. `0xDC` (not in the data) would be the button diagram for mask 11 (1+2+4) by the renderer table below. |

Applying only those two substitutions to the raw Japanese command field yields **221 byte-identical USA commands among the 403 pairs in distinct sets**. All 221 include at least one substituted byte, totaling 664 matching substitutions. For example, the first command of ARC ID 73 changes `BE BF C1 D3` to `81 82 84 93`. The other 182 pairs include region-specific formatting or wording and do not become identical under this rule. This is evidence for two shared control-code banks; it is not a complete Japanese-to-English text conversion or a decoding of the button symbols.

### Regional glyph atlas in member 0

[`inspect_arc_glyph_atlas.py`](../../../tools/research/inspect_arc_glyph_atlas.py) parses the first TIM and subsequent TIM sequence in 46 of the 52 character ARCs per region. The first TIM has declared TIM mode `0` and an image upload at VRAM `(80,16)` with a width of **32 16-bit words**. It is 66 rows high in Japan and 120 rows high in USA: raw image payloads of 4,224 and 7,680 bytes respectively, an exact 3,456-byte regional difference. The first USA TIM is byte-identical in all 46 parsed ARCs; the Japanese set contains 20 different first TIMs. The six members without an initial TIM are ARC IDs `241, 245, 261, 265, 269, 273`.

When each raw image word is viewed as four 4-bit indices instead of one direct-color pixel, the USA upload visibly contains English word fragments, and the Japanese upload contains Japanese glyphs. The analyzer can generate a grayscale diagnostic without assigning a palette:

```sh
python3 tools/research/inspect_arc_glyph_atlas.py \
  --render-japan-png work/japan-glyphs.png \
  --render-usa-png work/usa-glyphs.png
```

Across the 46 parsable regional pairs, 42 differ only in TIM 0, two (`249, 253`) differ in TIMs 0 and 1, and two (`201, 205`) differ in TIMs 0 and 2. The latter two duplicate the changed glyph upload. This makes member 0 a concrete lead for decoding member-4 text bytes. The renderer sections below give the game's lookup: 4-bit texture mode, one bit plane per CLUT, and the code-to-cell mapping.

## VAB/VH/VB evidence boundary

Neighboring ID `72 + 4n` is a `pBAV` header in 48 groups. Member 2 of ID `73 + 4n` supplies exactly the bytes needed to reach the header's declared VAB size. In the four groups without a VAB header, member 2 is also empty. The [VAB analysis](vab-banks.md) validates the program/tone tables, sample segmentation and SPU-ADPCM decoding; playback pitch, volume, pan and voice allocation are in [sound.md](../code/sound.md).

The [Sony PSY-Q Sound Artist Tool manual](https://psx.arthus.net/sdk/Psy-Q/DOCS/Devrefs/Sound20.pdf) documents platform VAB/VH/VB conventions, not Tekken-specific values. Do not assign sound names to BNS IDs without checking the content and callers.

### Move-text rendering (Japan Rev.1)

The Japanese executable draws member-4 strings in the in-fight command list (`FUN_800789E4`, a scrolling list driven by the d-pad) with `MoveTextDraw` (`0x80077A0C`). Byte meanings:

| Byte | Meaning |
|---|---|
| `0x00` | End of string. |
| `0x01–0x05` | Narrow glyphs drawn with back-spacing (joiners). |
| `0x06` | Neutral-stick icon (star). |
| `0x07–0xBC` | Glyph `g = byte − 1` of the character's own atlas (member 0, first TIM, uploaded at VRAM `(80, 16)`): texture `u = 64 + 12·(g mod 10)`, `v = 16 + 11·(g div 40)`, CLUT `0x7ED8 + ((g div 10) & 3)`. Each 12 × 11 cell stores **four glyphs in the four bit planes** of the 4-bit texels; the four CLUTs at `(384 + 16p, 507)` each show one plane. |
| `0xBD–0xCC` | Direction arrow `i = byte − 0xBD`, a 20 × 32 quad (`FUN_800778A8`): `i & 7` = db, d, df, b, f, ub, u, uf (three arrow images from `0x80027D44`, mirrored), `i & 8` selects the second CLUT = held direction. |
| `0xD1–0xE0` | Button diagram for mask `byte − 0xD1` (1 LP, 2 RP, 4 LK, 8 RK): two 20 × 32 sprites, the image chosen by the low three bits and the CLUT (rows `0x1FC/0x1FD`) by RK. |
| `0xFD`, `0xFE` | Full and half space. |
| `0xFF` | Escape: the next byte − `0x12` selects a formatting command (set x/y, set colour, newline, select font `0x80027D1C`, draw a nested string, change ordering-table layer). |

This explains why the Japanese atlases differ per character: each holds exactly the kanji and kana its move names need.

The pen, colour and font live in the scratchpad at `0x1F800380` while a string is drawn and are kept at `0x800A39B0` between calls. The fonts at `0x80027D1C` are `(advance x, advance y, glyph w, h, texture page)`: 0 and 1 are the two players' atlases (12 × 11 glyphs, advance 12), 2 and 3 the 20 × 32 icons. The escapes are `n` (new line), `s` (a string argument, each byte a glyph), `H`/`V` (pen x/y), `h`/`v` (pen x/y in advances), `i` (colour), `p` (ordering-table entry) and `t` (font); other letters stop the game (`FUN_8007B27C`). The joiners draw glyph `byte − 1` (bytes 1 and 2: fixed glyphs 0 and 1) with the pen moved back by half or a quarter advance around them. Consecutive button diagrams share one draw-mode packet. `MoveTextDraw` and the list screens are ported in [`tools/research/command_list_sim.py`](../../../tools/research/command_list_sim.py).

### Move-text rendering (USA)

The USA executable's `MoveTextDraw` (`0x80077724` in `SLUS_004.02`) uses another encoding and a shared atlas (identical in all 46 USA ARCs): bytes `0x21–0x7F` are ASCII drawn from a 6 × 12 font (glyph `c = byte − 0x20` at `u = 6·(c & 15)`, `v = 12·(c >> 6)`, bit plane `(c >> 4) & 3`); bytes `0x01–0x1F` and `0xA1–0xC3` are pre-rendered words from the same atlas (widths in cells from EXE tables `0x800989F7` and `0x80098976`); `0x80–0x90` are direction arrows (index as in Japan, 16 = neutral) and `0x91–0xA0` button diagrams (mask as in Japan); `0x20`, `0xFE`, `0xFD`, `0xFB` are spaces of 1, 1, 2 and 10 cells and `0xFC` a line break. [`tools/research/move_text.py`](../../../tools/research/move_text.py) decodes every USA command list into Tekken notation, reading the pre-rendered words back by matching their 6-pixel cells against the ASCII glyphs (so the tool stores no game text). The arrow and button assignments were confirmed on known commands (quarter-circle motions, `d+3+4`, the universal `1+3`/`2+4` throws).
