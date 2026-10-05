# Namco resource streams

## `TEKKEN3.BNS`: address table in the executable

For Japan Rev.1 and USA, the local `Tek3Ex` reads each BNS table entry as `(relative_LBA, byte_size)`. An entry contains two little-endian `u32` values; the resource starts at `relative_LBA * 0x800` within BNS. The extractor aligns successive resources to `0x800` bytes when repacking. Both tables have 303 eight-byte entries, but their executable locations differ:

| Release | BNS table EXE offset / guest address | XAS table EXE offset / guest address |
|---|---|---|
| Japan Rev.1 | `0x14E6C` / `0x8002466C` | `0x157E4` / `0x80024FE4` |
| USA | `0x14C00` / `0x80024400` | `0x15578` / `0x80024D78` |

The gap between each BNS and XAS table is `0x978` bytes, exactly `303 * 8`. PS-X EXE guest addresses map to full executable file offsets by `offset = address - 0x80010000 + 0x800`. Japan Rev.1 places BNS at ISO LBA 603, size 38,029,312 bytes; USA places it at LBA 250156, size 38,150,144 bytes. Developer resource names are not stored in these two-word BNS records.

**Evidence:** the extractor's code gives the initial interpretation. The independent [`compare_bns.py`](../../../tools/research/compare_bns.py) reads the raw ISO sectors in both local images, checks all 303 bounds and hashes the selected bytes. The extractor's output suffixes `.3dm`, `.arc` and `.vab` are heuristics, not proof of a record's semantics.

### Original Japan SLPS-01300 exception

The original `SLPS_013.00` has a different index: 303 twelve-byte `<III>` entries at full EXE offset `0x14CC8`, guest address `0x800244C8`. The words are `(relative_BNS_LBA, byte_size, filename_pointer)`. There are 297 nonempty and six empty entries. Every pointer resolves, via the same EXE address mapping, to a NUL-terminated printable ASCII filename within the executable. Examples: ID 0 `enbu.ovl`, ID 71 `paul3.kmd`, and ID 302 `result.ovl` at EXE offset `0x15AFC`. This establishes the filename field's meaning. The original loader (`0x8006CDC0`) reads only the first two words of each 12-byte entry, so the names are unused leftovers of the build.

The first two fields differ from Japan Rev.1 for 298 of 303 IDs because of changed packing. [`compare_japan_revisions.py`](../../../tools/research/compare_japan_revisions.py) reads the ECM image, validates the twelve-byte table and compares resource contents. **293 resources are byte-identical.** The ten changed records are `.ovl` IDs 0, 5–11, 301 and 302. All 52 `.kmd`/`3DMK`, 48 nonempty `.vh`/`pBAV` and 75 `.arc` records are identical. The [original BNS index](../bns-original-index.md) lists names, sizes and SHA-256. [`verify_ecm.py`](../../../tools/research/verify_ecm.py) regenerates the EDC/ECC of all 270,799 sectors and matches the ECM trailer checksum (`DB290887`), so the whole original track is read correctly.

Static Japan Rev.1 instructions near guest address `0x8006C7FC–0x8006C820` read a `u16` selector from `0x80098954 + 2*s2`, multiply it by eight, index the BNS table at `0x8002466C`, read the size and round it up to four bytes. A local scan confirms 303 `u16` values at guest address `0x80098954` (full EXE offset `0x89154`): a permutation of IDs 0–302. The first ten mappings are `0→5`, `1→6`, `2→7`, `3→8`, `4→9`, `5→10`, `6→11`, `7→0`, `8→301`, `9→302`; IDs 12 onward follow. `s2` is the game's logical resource ID and the table maps it to the BNS ID ([memory-map.md](../code/memory-map.md)); for example the character groups use logical `95 + 4s .. 98 + 4s` = BNS `71 + 4s .. 74 + 4s`.

Across all 303 local records, 52 begin with `3DMK` at offset 8, 48 with VAB magic, and six are empty. A loose bounded offset/size scan gives 77 ARC-like candidates. The strict criterion from the USA [BNS tool](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/tools/bns_tool.py) yields 75 locally. The excluded IDs 12 and 13 have padding gaps between members; ID 13 also has two trailing bytes. The original EXE names them `makuma00.tia` and `makuma01.tia`. All 75 strict ARC records have original `.arc` names. The separate `.tia` and `.tiz` [compressed TIM format](compressed-tim.md) is now locally decoded. See the external [USA map](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/MODDING.md) and [model map](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/tools/MODEL_MAP.md).

### Japan Rev.1 versus USA

Comparison uses matching table IDs, since physical disc positions differ. Of 303 records, 240 are byte-identical, including six empty entries. Sixty-one have different lengths; two have equal lengths but different bytes. Run `python3 tools/research/compare_bns.py` for the summary.

- Different length: IDs `0`, `6–11`, `55`, `73, 77, 81, …, 277` (52 records at four-ID intervals), and `301`.
- Equal length but different bytes: IDs `5` and `302`.
- All 52 `3DMK` and 48 `pBAV` records are byte-identical.
- 234 nonempty records are byte-identical; the empty IDs are `4`, `260`, `264`, `268`, `272`, `295`.

IDs 1–3 (`enbmdl1–3.arc`) hold the attract demonstration's models ([modes.md](../code/modes.md#enbu-attract-demonstration)). Every changed ID is accounted for: the overlays (`0`, `5–11`, `301`, `302`; code and text), the Tekken Ball stage archive `55`, and the 52 character archives, whose members 0 (glyph atlas) and 4 (command list) are localized ([arc-archives.md](arc-archives.md)).

### Repeated four-slot group, IDs 71–278

For `n = 0..51`, the BNS table has this repeated pattern. The original EXE supplies `.kmd`, `.vh`, `.arc` and `divmot*.bin` names, including `paul3.kmd`. The local Japanese resource map is consistent with the pattern; the game loads one group per costume slot ([memory-map.md](../code/memory-map.md#character-resources)).

| Slot | IDs | Direct observation in Japan Rev.1 and USA | Regional difference |
|---:|---|---|---|
| `71 + 4n` | `71, 75, …, 275` | All 52 have ASCII `3DMK` at offset `0x08`. | All 52 byte-identical. |
| `72 + 4n` | `72, 76, …, 276` | 48 start with `pBAV`; IDs `260`, `264`, `268`, `272` have zero size. | All nonempty records byte-identical. |
| `73 + 4n` | `73, 77, …, 277` | All 52 start with `u32 count = 5` and have five bounded `(offset,size)` pairs in both regions. | All 52 differ; total USA size is 173,808 bytes greater. |
| `74 + 4n` | `74, 78, …, 278` | 52 [`divmot*.bin` motion banks](divmot-banks.md). | All 52 byte-identical. |

The ARC slot carries the localization: member 4 holds the in-fight command list and member 0 starts with its glyph atlas; both regions' text bytes are decoded in [ARC archives](arc-archives.md#move-text-rendering-japan-rev1).

### Signatures and names

| Marker | Observation | Status |
|---|---|---|
| ASCII `pBAV` (`LE u32 0x56414270`, usually called VABp) | The word at offset `0x0C` equals the VH header size plus ARC member 2 size in all 48 nonempty groups in each region. | Confirmed: VH/VB assembly and all samples decoded ([vab-banks.md](vab-banks.md)). |
| ASCII `3DMK` (`LE u32 0x4B4D4433`) | Found at offset 8; the old extractor calls it `.3dm`, while the original EXE calls all 52 `.kmd`. | Confirmed: the model format is in [3dmk-models.md](3dmk-models.md). |
| `u32 count` in `1..255` | Loose `.arc` heuristic; all 52 five-member group records meet strict bounds, nonoverlap and EOF checks. | Partial for these 52; a generic scan can produce false candidates. |

## `TEKKEN3.XAS`: media region

XAS is a separate ISO entry referenced from the EXE. It follows BNS in Japan and precedes BNS in USA. Japan Rev.1 size is 515,016,704 bytes; USA size is 511,082,496 bytes. A [USA analysis](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/MODDING.md) describes mixed XA audio and STR/MDEC video with 50 XA descriptors and 22 STR regions. See [sound and video](sound-and-video.md).

`Tek3Ex` locates the following Japanese EXE table but does not decode XAS. Both local Japan Rev.1 and USA copies have 50 identical three-word descriptors, and their selected XA sectors validate locally. Complete classification of all Form 2 sectors and Japanese movie regions remains outstanding. Calling XAS a distinct audio codec is unsupported.

## Preliminary record inventory

The original Japanese EXE's twelve-byte index establishes `.ovl`, `.tmd`, `.kmd`, `.vh`, `.arc`, `.bin`, `.tiz` and `.tia` names for all 303 IDs. `FileMap.md` suggests overlay, scene and character groupings; functional mappings remain provisional pending loader analysis. For each record, preserve:

- region and EXE/BNS hashes;
- ID, LBA, size, SHA-256, signatures and candidate format;
- loading context (code call, mode, fighter or stage);
- visually or audibly validated decode result;
- correspondence between Japan and USA IDs.
