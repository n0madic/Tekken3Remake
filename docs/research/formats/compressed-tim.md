# Compressed TIM resources: `.tiz` and `.tia`

The original Japanese EXE names BNS IDs `12–13` `makuma00.tia` and
`makuma01.tia`, and IDs `14–35` `face_b00.tiz` through `face_b21.tiz`.
[`inspect_compressed_tim.py`](../../../tools/research/inspect_compressed_tim.py) reads
those records directly from the original Japan ECM image, Japan Rev.1 and USA.
It validates the decoded TIM envelopes and compares their bytes across all
three releases. The script does not write game assets.

## Seven-token compression grammar

Each compressed TIM begins with a flag byte. Consume its **low seven bits in
least-significant-bit order**. A set bit copies the next source byte literally;
a clear bit consumes a two-byte backwards reference. The eighth bit is not a
token flag. After seven tokens, read another flag byte.

For reference bytes `a, b`:

```text
length   = (a >> 3) or 32
distance = (((a & 7) << 8) | b) or 2048
repeat length times: output.append(output[-distance])
```

The reference may overlap its own output. The zero encodings are essential:
`a >> 3 == 0` represents length 32, and an eleven-bit distance of zero
represents 2,048. Treating the format as the FF7 eight-token LZSS variant
produces an invalid TIM block length of zero on the first `.tia` member.

The first `.tiz` stream begins `DF 10 00 00 00 09 18 04 0C D9 02 …`.
The first flag gives five literals (`10 00 00 00 09`), a three-byte copy
(`18 04`), then literal `0C`. The next flag is `D9`, whose first literal
is `02`. The resulting TIM starts `10 00 00 00 09 00 00 00 0C 02 00 00`:
the CLUT block length is `0x020C` (524 bytes). This is a useful discriminating
header example, not the only evidence for the decoder.

Stop decoding when the declared TIM blocks have been filled. Every observed
compressed member then has **one to four zero source bytes** of padding. A
reader must bound both the source and the declared output, reject references
before the beginning of the output, and validate each TIM block's
`12 + 2 × width_words × height` byte length. Interpreting padding as further
tokens can create spurious output or a truncated reference.

The [PSX-SPX TIM description](https://psx-spx.consoledev.net/cdromfileformats/)
provides the standard TIM block layout. The compression grammar above was
derived and checked against the local Tekken 3 images; the general TIM
specification alone does not describe it.

## `.tia` container

Both `.tia` records contain a little-endian `u32` count of 42 followed by 42
`(u32 offset, u32 size)` pairs. Offsets are relative to the record start.
The directory ends at `0x154`, the first member begins there, and later
members start on four-byte boundaries. Between members are zero gaps of
zero to three bytes. ID 12 is 23,928 bytes and ends at its last member;
ID 13 is 18,616 bytes with two final zero bytes.

Each member is one compressed, palette-bearing, **4-bit TIM** (`flags=0x08`).
All 84 decode successfully and have either 256 or 576 bytes:

| Per `.tia` | CLUT upload | Pixel upload | Decoded TIM size |
|---:|---|---|---:|
| 35 members | 16 words × 1 row | 8 words × 32 rows (32 pixels wide in 4-bit mode) | 576 bytes |
| 7 members | 16 words × 1 row | 3 words × 32 rows (12 pixels wide in 4-bit mode) | 256 bytes |

All 42 decoded TIMs within each `.tia` are byte-distinct. Corresponding
members of the two `.tia` records use the same upload rectangles, although
their image contents differ. For example, member 0 uploads its CLUT to VRAM
`(0,500)` and its pixel rectangle to `(832,0)`. The 42 members are the cells
of one picture (7 rows × 6 columns on texture page 13), composed by the VS
screen ([modes.md](../code/modes.md#pre-fight-vs-screen)); "makuma" (幕間) is the
screen between fights.

## `.tiz` images

Each of the 22 `face_b*.tiz` records is one compressed, palette-bearing,
**8-bit TIM** (`flags=0x09`). Every decoded TIM is 32,296 bytes. Its CLUT
is `256 × 1` VRAM words and its image is `63 × 252` words, or 126 × 252
8-bit pixels. The TIM's own upload coordinates are `(0,0)`; the game
ignores them and places the portrait per player (below). The drawing is in
[modes.md](../code/modes.md#pre-fight-vs-screen).

## Runtime use

Both kinds are drawn by the pre-fight "VS" screen, game state 11 (`0x80052808`), which each mode fills through its overlay (`FUN_800B3C70` and siblings):

- **Background**: `FUN_80051FC4(variant, caption)` stores the logical ID `0x800228FC[variant]` in `0x800B9378`. Logical 10 is `makuma00.tia` (exactly one human player, `0x800AFF6C = 1`) and 11 is `makuma01.tia` (two players, or none in the demonstration). "Makuma" is 幕間, the screen between fights. When the ID differs from the cached one (`0x800984E4`), the archive is read into `0x800C1FC0` and `FUN_8004CD28` decodes and uploads all 42 members at their TIM rectangles.
- **Portraits**: `FUN_800523FC(player, character·4 + costume)` takes the portrait index from the low five bits of the character record's first word; bit 5 is the facing, flipped for player 2. The index is stored in `0x800B937A + player`. When it changes (cache `0x800984E6`), `face_b<index>.tiz` (logical `12 + index`) is decoded by `FUN_8004CACC` to VRAM `x = 769` (player 1) or `833` (player 2), `y = 256`, with its CLUT at `(256, 502)` or `(256, 503)` (table `0x800984E8`).
- **Captions**: the `caption` argument selects the mode caption sprite (`0x80022900`, widths at `0x8002291C`). Arcade and time attack pass the background variant (0 or 1); VS and the demonstration pass 1; team battle 2, survival 3, practice 4, Tekken Ball 5, Tekken Force 6.

The character select screens use their own images: `select.ovl` carries compressed TIMs in its data and decodes them with `FUN_80031E50`.

## Verification boundary

The local inspection accepted **106 complete TIMs per release**: 84 from
`.tia` and 22 from `.tiz`. In each of the three releases the distribution is
14 TIMs of 256 bytes, 70 of 576 bytes, and 22 of 32,296 bytes. All 106
decoded TIM byte strings match across original Japan, Japan Rev.1 and USA.
This establishes the container, compression grammar and standard TIM block
geometry for these records; the upload and drawing code is described above and
in [modes.md](../code/modes.md#pre-fight-vs-screen).

## Indexed conversion and palette semantics

The [Sony PlayStation File Formats reference](https://psx.arthus.net/sdk/Psy-Q/DOCS/Devrefs/Filefrmt.pdf)
defines each palette word as `STP:B5:G5:R5`, with the red component in the
least-significant five bits. In 4-bit mode, the low nibble of a 16-bit image
word is the leftmost pixel; in 8-bit mode, its low byte is the leftmost pixel.
The image rectangle's width is expressed in 16-bit VRAM words. These rules
give 32- or 12-pixel-wide `.tia` images and 126-pixel-wide `.tiz` images.

For all 84 `.tia` TIMs, every one of the 1,344 CLUT entries has STP set,
including 153 entries equal to `0x8000` (opaque black under the Sony rule).
No CLUT entry is `0x0000`; all 77,056 decoded `.tia` pixels therefore refer
to a nonzero palette word. Across the 22 `.tiz` TIMs, 5,418 of 5,632 CLUT
entries have STP set and the other 214 are exactly `0x0000`. Those zero
entries are referenced by 263,412 of 698,544 decoded pixels. These counts
were measured from the decoded local images. Both kinds are drawn with opaque
raw-textured quads (command `0x2D`), so STP never blends: `.tia` pixels are all
drawn, and the `0x0000` entries of the `.tiz` portraits are transparent (the
background shows through).

[`export_compressed_tim.py`](../../../tools/research/export_compressed_tim.py)
exports each selected member as:

- `.tim`: the exact decompressed PlayStation TIM;
- `.indices.png`: an 8-bit grayscale image whose sample values are the
  original 4-bit or 8-bit palette indices, without color conversion;
- `.preview.png`: BGR555 expanded to RGBA with only `0x0000` made transparent;
- `.json`: source hashes, BNS ID and member, VRAM rectangles, raw palette
  words and STP-marked palette indices.

The preview models an **opaque textured draw**. It does not map STP to an
arbitrary alpha value because PlayStation semitransparency has multiple GPU
blend modes and may be disabled for a given primitive. For a faithful engine
material, use the index image and raw palette metadata with the game-side
draw state once that state has been recovered.

Example using the original Japanese ECM image:

```sh
python3 tools/research/export_compressed_tim.py \
  --record-id 14 --output-dir work/tim-export
```

The exporter was exercised on all 106 resources. Reopening every generated
index PNG reproduced the TIM's pixel-index bytes exactly; all 106 JSON TIM
hashes matched the exported TIM files. The first `.tiz` opaque-draw preview
visually resolves to a character portrait. This checks the palette and index
ordering as a useful conversion diagnostic; it does not prove the game's
screen placement or blending.

Reproduce the inspection with:

```sh
python3 tools/research/inspect_compressed_tim.py
```
