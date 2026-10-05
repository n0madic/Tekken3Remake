# Character ARC member 3: `TK3psSDW` (shadow mesh)

The nonempty member 3 of character ARCs `73 + 4n` starts with the exact
eight-byte signature `TK3psSDW`. Forty-eight of 52 members are nonempty;
IDs `261, 265, 269, 273` have an empty member 3. The format below is checked
by [`inspect_arc_pssdw.py`](../../../tools/research/inspect_arc_pssdw.py) against
original Japan, Japan Rev.1 and USA. Every member-3 byte string matches
across those releases.

**Role (confirmed from code):** this is the fighter's **drop-shadow mesh**. `FighterLoadCharacter` copies the member into the fighter's buffer (`Fighter.pssdw`, `+0x1274`) and `PssdwRelocate` (`0x800352D4`) turns the 18 section offsets and `section_end` into pointers. Each frame `FighterComposeJoints` multiplies every joint's world matrix by the camera and a ground-projection matrix (`0x800AE310` = camera × `0x800B0018`) and calls `ShadowProjectSection` (`0x80037CF0`), which projects the joint's section with RTPT three points at a time and appends the screen coordinates to a scratchpad array at `0x1F800200`. `ShadowBuildPrims` (`0x80037D7C`) then emits one `POLY_F3` per packed word and one `POLY_F4` per four-index row, using indices into that array; the colour word is prebuilt by `FighterBuildShadowPrims` (`0x8003533C`, at model set-up: code `0x21`/`0x29` with the stage's shadow colour, [stages.md](../code/stages.md#lighting)). Tekken Force (mode 8) builds a textured blob shadow instead (`FUN_800796B4`). Section `i` belongs to joint matrix `i` (18 joints).

## Bounded layout

All offsets below are from the start of member 3 and all multi-byte fields
are little-endian:

```text
0x00  byte[8] magic = "TK3psSDW"
0x08  u32 section_end                    # 0x380 or 0x350 locally
0x0C  u32 packed_word_count               # 20 or 24
0x10  u32 four_index_row_count            # 44, 41 or 40
0x14  u32 section_offsets[27]             # first 18 nonzero, last 9 zero
0x80  18 variable-size coordinate sections
section_end:
      u32 packed_word_count_again
      u32 packed_words[packed_word_count]
      u32 four_index_row_count_again
      byte index_rows[four_index_row_count][4]
EOF
```

The first section starts at `0x80`. The first 18 directory entries are
strictly increasing and the nine remaining entries are zero. The section
boundary after section 17 is `section_end`. Each section has:

```text
u32 coordinate_count
repeat coordinate_count times: i16 x, i16 y, i16 z, i16 zero
repeat until coordinate slots are a multiple of 3:
    i16 zero, i16 zero, i16 zero, i16 zero
```

Thus its byte span is exactly `4 + 8 × 3 × ceil(coordinate_count / 3)`.
All 864 sections in the local 48 nonempty members end at their next
directory boundary. The 3,682 declared coordinates have a zero fourth
word; all 482 alignment coordinate slots are entirely zero. The data
therefore has the same eight-byte coordinate shape as the `.kmd` arrays,
but no coordinate-system or linkage equivalence has been established.

The two tail counts repeat the corresponding header fields exactly. The
tail's packed-word array and four-byte index rows consume the file to EOF.
Across the 48 nonempty members there are 976 packed words and 2,098
four-index rows.

- **Packed word = triangle.** Vertex indices are bits 2–9, 10–17 and 20–27
  (the game reads `w & 0x3FC`, `w >> 8 & 0x3FC`, `w >> 18 & 0x3FC` as byte
  offsets into the projected array). Other bits are ignored.
- **Four-index row = quad**, one index per byte, in `POLY_F4` vertex order.

Indices count projected slots across all 18 sections in order, **including**
the zero padding slots: sections are padded to a multiple of three because
RTPT transforms three vertices at a time. All 976 triangles and 2,098 quads
index declared (non-padding) coordinates.

Each byte in every four-index row is below the total number of coordinate
slots obtained by concatenating the 18 padded sections. It points to a
**declared, non-padding** coordinate; none points to any of the 482 zero
padding slots. The four indices in each row are distinct. All 2,098 rows
pass this reference check. This matches the quad interpretation confirmed in code.

## Observed profiles and reuse

| `section_end` | Packed words | Four-index rows | Member bytes | ARC records |
|---:|---:|---:|---:|---:|
| `0x380` | 20 | 44 | 1,160 | 44 |
| `0x380` | 24 | 41 | 1,164 | 2 (`193, 197`) |
| `0x350` | 24 | 40 | 1,112 | 2 (`241, 245`) |

There are five distinct nonempty byte strings, because the 1,160-byte
profile has three content variants: one shared by 38 ARCs, one by IDs
`105, 109`, and one by IDs `161, 165, 201, 205`. Thus a file profile is
not a complete identity key. The 27 directory slots equal the `.kmd` row
count, but the observed member is reused by many different `.kmd` records;
the slot-to-model association remains unproven.

Reproduce the three-release check with:

```sh
python3 tools/research/inspect_arc_pssdw.py
```

For a structural OBJ diagnostic, the same tool can omit the zero pad slots
and remap the validated four-index rows:

```sh
python3 tools/research/inspect_arc_pssdw.py \
  --record-id 73 --raw-obj work/arc73-pssdw-raw.obj
```

The ID-73 export has 77 vertices, 20 triangles and 44 quads, with every OBJ
index in range (the tool also checks every triangle index of all members). Coordinates are joint-local;
a correct shadow needs each section transformed by its joint matrix.
