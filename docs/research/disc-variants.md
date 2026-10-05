# Tekken 3 PSX disc catalog

Measurements refer to files in this checkout. Hashes were calculated locally. External catalog links provide independent dump-identity comparisons only.

## Selected images

| Image | Role | Observed boot path | Note |
|---|---|---|---|
| `Tekken 3 (Japan) (Rev 1)` | Primary Japanese research image | `SLPS_013.00` | Track 1 SHA-1 matches the Japan Rev.1 entry in a [catalog importing Redump data](https://openretro.org/psx/tekken-3/edit). Internal serial: `SLPS_013.00`. |
| `Tekken 3 (USA)` | English localization and regional comparison | `TEKKEN3/SLUS_004.02` | Different BNS/XAS and ISO directory tree; audio tracks are byte-identical to Japan Rev.1. |
| `Tekken 3 (J) [SLPS-01300]` | Original Japanese comparison release | `SLPS_013.00` | Track 1 was read virtually from ECM without an unpacked disc file. APE tracks were decoded through a pipe for bytewise PCM comparison. ECM trailer and regenerated EDC/ECC were not validated. |

The external Japan Rev.1 entry lists Track 1 size `636909840` and SHA-1 `44c5aabeedd12fed18fb0428586076b610186491`; both match locally. It also lists audio-track SHA-1 values `ba8cbc6a371250a92b3d12c1154f489bd6b4b70b` and `a5b34e39603ed80fed8400d879b20b39aadfe1ba`, which also match the local files. [OpenRetro Japan Rev.1 image and CUE metadata](https://openretro.org/psx/tekken-3/edit).

## Local SHA-256 values

| Image / file | Size in bytes | SHA-256 |
|---|---:|---|
| Japan Rev.1 — Track 1 | 636,909,840 | `ab71eeb5763a888c5f3132e23a74a1c41fe1e83f5d9671e23fe8d63c0ed9c42b` |
| Japan Rev.1 — Track 2 | 27,701,856 | `37cc0be9c76738e7fc1842e532126c1a4fdc9486ea51720a3b4182b69ace56d6` |
| Japan Rev.1 — Track 3 | 28,042,896 | `c7c6db2736351933f04d9843c3358a641f6548340da10a3f19a2e48562683ad2` |
| USA — Track 1 | 632,532,768 | `6b660e62748d02779e9e08362a5ed202540af7fad134de2ec0a2184ad78bb496` |
| USA — Track 2 | 27,701,856 | `37cc0be9c76738e7fc1842e532126c1a4fdc9486ea51720a3b4182b69ace56d6` |
| USA — Track 3 | 28,042,896 | `c7c6db2736351933f04d9843c3358a641f6548340da10a3f19a2e48562683ad2` |
| Original Japan SLPS-01300 — compressed Track 1 `.ecm` | 597,567,475 | `546afce9ca677e07dd8b549a3fba56331ab058f6b8f2e24af1ede51b6b485030` |

The USA Track 1 SHA-256 and extracted `SLUS_004.02` SHA-256 match the exact release analyzed in the public [MODDING.md](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/MODDING.md): `6b660e62748d02779e9e08362a5ed202540af7fad134de2ec0a2184ad78bb496` and `fbda8b68e5799dbef4af39a161783bc670c15b0aa0e87dce65e210717da19b8c`.

**Confirmed:** USA Tracks 2 and 3 match the corresponding Japan Rev.1 files completely, including the pregap sectors represented in those `.bin` files. This follows from whole-file SHA-256 equality, not merely equal durations.

The original Japan ECM Track 1 yields 270,799 virtual raw 2,352-byte sectors. The compressed source was not rewritten. Its two APE tracks decode to PCM byte-identical to raw Japan Rev.1 and USA Tracks 2/3.

## Three-release comparison

BNS hashes cover the ISO file payload. XAS hashes cover consecutive 2,048-byte ISO user blocks in the extent, excluding raw Mode 2 headers. EXE hashes cover the full PS-X EXE file, including its `0x800`-byte header.

| Image | Track 1 raw sectors | EXE: size / SHA-256 | BNS: LBA / size / SHA-256 | XAS: LBA / size / ISO user-payload SHA-256 |
|---|---:|---|---|---|
| Original Japan SLPS-01300 (virtual ECM read) | 270,799 | 1,189,888 / `2233d26402f0aef1960433dfa99ac9809064a3e96e2b1c889a275d54c955d0fd` | 605 / 38,033,408 / `755ffcf20b9bf51b2e596eb39194e862dd8e671c6c0ca14e7ac01c946e2e68a0` | 19,176 / 515,016,704 / `e73a779ee110fddbc6d3c437b0625c242d49e9b70beed956fc18a524cf98ce2b` |
| Japan Rev.1 | 270,795 | 1,185,792 / `09e8b0b6575c6ff1c81f7f827d31daf2770fa4c0a586e946b6f10f7613dd0432` | 603 / 38,029,312 / `681772b76a9e0202895acbe748d62b93fad9b23513c7f07333c16ad4e53b82ee` | 19,172 / 515,016,704 / `e73a779ee110fddbc6d3c437b0625c242d49e9b70beed956fc18a524cf98ce2b` |
| USA | 268,934 | 1,185,792 / `fbda8b68e5799dbef4af39a161783bc670c15b0aa0e87dce65e210717da19b8c` | 250,156 / 38,150,144 / `dc9c12944afb78f3f668b8c5053995561f6547dd42b5faf8e0a908d69e73eb4d` | 604 / 511,082,496 / `dc972330ce1d483d90478a17c49a3984fdeb8d005911b378abb236fbf89b5350` |

Original Japan and Rev.1 have the same XAS ISO user-payload SHA-256 and matching XA-subheader sequences across all 251,473 XAS sectors. CDDA also matches after APE decoding. Their EXE and BNS differ. PVD timestamps are `1998031501300000$` (original Japan), `1998033102000100$` (Japan Rev.1), and `1998033101000100$` (USA). Rev.1 was mastered later, but this does not prove it has more content or supersedes the original as a research artifact.

Original Japan stores 303 12-byte BNS descriptors including a filename pointer; Japan Rev.1 and USA use 8-byte `(relative_BNS_LBA, size)` pairs. All 303 original pointers resolve to NUL-terminated printable ASCII strings in the EXE. The original and Rev.1 therefore need different table profiles. See the [BNS analysis](formats/namco-banks.md) and [complete original index](bns-original-index.md).

## ISO 9660 entries

The values below are the LBA and length read from Track 1 ISO directory entries. The recorded lengths are expressed in 2,048-byte logical sectors. `DA` and `DMY` intentionally point beyond the data track and are discussed in the [CD layout](formats/disc-layout.md).

| File | Japan Rev.1: LBA / bytes | USA: LBA / bytes |
|---|---:|---:|
| `SYSTEM.CNF` | 23 / 59 | 23 / 67 |
| `SLPS_013.00` / `TEKKEN3/SLUS_004.02` | 24 / 1,185,792 | 25 / 1,185,792 |
| `TEKKEN3.BNS` | 603 / 38,029,312 | 250,156 / 38,150,144 |
| `TEKKEN3.XAS` | 19,172 / 515,016,704 | 604 / 511,082,496 |
| `TEKKEN3.DA` | 270,945 / 23,814,144 | 269,084 / 23,814,144 |
| `TEKKEN3.DMY` | 282,723 / 24,111,104 | 280,862 / 24,111,104 |

**Confirmed:** the Japanese data track places BNS before XAS; USA places XAS before BNS. BNS/XAS sizes, EXEs, and `SYSTEM.CNF` contents differ. The layout alone does not identify which differences are localization, content, or build changes.

All three local releases have 52 `3DMK` records, 48 with VAB magic, and six empty records. A permissive bounded `count + offset/size` scan finds 77 candidates, while the strict criterion from the [USA BNS tool](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/tools/bns_tool.py) identifies exactly 75 ARC records. The original Japanese filename pointers independently explain the difference: exactly those 75 are named `.arc`, while IDs 12/13 are named `.tia`. The latter's gaps, trailing bytes and 42 compressed TIM members are described [separately](formats/compressed-tim.md).

### Original Japan versus Japan Rev.1

[`compare_japan_revisions.py`](../../tools/research/compare_japan_revisions.py) reads the ECM image through virtual sectors, extracts ISO files into memory, and compares all 303 BNS records by ID. **293 are byte-identical**, including six empty records. The **10 changed records** are IDs `0`, `5–11`, `301`, and `302`; their original EXE names end in `.ovl`: `enbu`, `arcade`, `practice`, `force`, `volley`, `select`, `title`, `ranking`, `ending`, and `result`. Seven change size; three retain size but change bytes. All 52 `.kmd`, 48 nonempty `.vh`, 75 `.arc`, and their nested data are byte-identical. This establishes the BNS change boundary between the Japanese revisions; EXE changes require separate functional analysis.

The ECM reader checks Mode 2 headers and ISO user data. It does not regenerate ECC/EDC or verify the four-byte ECM trailer checksum. ECM sector handling was checked against Neill Corlett's [original `unecm.c`](https://sources.debian.org/src/ecm/1.00-1/unecm.c).

#### Executable and overlays

Found by mapping the original's executable and overlays onto Japan Rev.1's (`tools/remake_import/layout.py`) and comparing the remake's conversion of both discs file by file. Status: `confirmed` where stated from the data, `inferred` where marked.

- **Layout.** The executable is 4 KiB longer and its data is shifted in many runs; the mode overlays load at `0x800B19E0`, the screen overlays at `0x800BA428` (Rev.1: `0x800B0A10`, `0x800B9378`). The system texture archive in the screen slot of the executable image starts at `0x800BA428`; its first member differs.
- **Code.** More functions differ than between Rev.1 and USA (the practice overlay most); some read other structure offsets (e.g. halfword fields at `+0x80` in Rev.1 read as bytes at `+0x89`, `0x8002FB0C`). Not analysed further.
- **The XA stream table** (Rev.1 `0x80024FE4`, sound.md#music) has 16-byte rows in the original: start, end and channel as in Rev.1, then a pointer to the stream's name. The stream positions are the same (the XAS files are identical).
- **HUD font 1's glyph table** starts two entries earlier relative to its pointer; the glyphs drawn are the same.
- **The stage clear colours** (Rev.1 `0x80097E88`, 15 × `0x00BBGGRR`, stages.md) do not exist: the original has no data there and its `FUN_80048648` differs. `inferred`: the stage-coloured band is a Rev.1 addition.
- **Content.** The Time Attack result backdrop (`result.ovl`) reads "THE KING OF IRONFIST TOUNAMENT" without the "3"; five staff roll rows have typos Rev.1 corrects (`OMUNIBUS`, `TAEKON-DO`, `KIYOTA TAMIYA`, a missing full stop, a comma for a space); two Theater movies have other titles (`FALLING DADDY`, `MONEY MONEY`); the title logo's mark differs.

### Japan Rev.1 versus USA BNS records

[`compare_bns.py`](../../tools/research/compare_bns.py) reads EXE and BNS from ISO extents in raw Mode 2/2352 sectors, parses each region's EXE index, and compares resource bytes in memory. It does not run the game or write extracted assets.

| Result | Count | IDs |
|---|---:|---|
| Byte-identical, including empty | 240 | All IDs not listed as changed below |
| Empty in both | 6 | `4, 260, 264, 268, 272, 295` |
| Different size | 61 | `0, 6–11, 55, 73, 77, …, 277` in steps of 4, and `301` |
| Same size, different bytes | 2 | `5, 302` |

Thus 234 nonempty records match byte for byte and 63 records differ. None of the 52 `3DMK` records or 48 VAB records differ between this pair. Size and byte differences alone do not establish localization, gameplay modes, or resource semantics.

## Research baseline

Use Japan Rev.1 as the reproducible primary Japanese image: the local dump and its `SLPS_013.00` identity are verified, and its 8-byte BNS index is understood. Keep USA as the required pair for English text and regional comparisons. Retain original SLPS-01300 as a separate Japanese revision with a 12-byte index and authoritative names for all 303 resources. Its 10 changed `.ovl` records and EXE need functional comparison. [VGIndex](https://www.vgindex.org/disc/588/) also lists the original SLPS-01300 release.
