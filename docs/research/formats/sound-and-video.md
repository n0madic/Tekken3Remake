# Tekken 3 PSX sound and video

## CDDA and ISO aliases

The image has two raw CDDA tracks, Track 2 and Track 3. Their files are identical between the local USA and Japan Rev.1 releases. ISO entries `TEKKEN3.DA` and `TEKKEN3.DMY` point to those tracks' INDEX 01 positions. They are not ordinary 2048-byte-sector data files; see the [cross-track calculation](disc-layout.md). Track 2 is music track 4, STAFF ROLL (found through the TOC); Track 3 is silence and unused. The XA music tracks and their names are listed in [sound.md](../code/sound.md#music).

The local [VAB bank study](vab-banks.md) validates the complete VH table envelope, program-to-tone grouping and VAG-size-table segmentation of ARC member 2 in all 48 nonempty groups. Four absent VABs correspond to empty member 2. It identifies 785 bounded raw SPU-ADPCM samples and a PCM decoder matched byte for byte against FFmpeg on one-shot and looping examples. Playback calls and sample rates are described in [sound.md](../code/sound.md).

## XA audio in `TEKKEN3.XAS`

A [USA release analysis](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/MODDING.md) treats XAS as a mixed XA-audio and STR/MDEC-video region. It reports a 50-row XA descriptor table, with inclusive start and end groups plus XA channel; selected sectors advance by eight from `start + channel` through `end + channel`. Ordinary sectors use XA coding `0x01` and submode `0x64`, with one terminal `0xE4` sector per stream. It also reports 22 contiguous STR regions made from interleaved frame/chunk sectors.

The local raw-sector scan from ISO LBA/size confirms a mixed sector region:

| Release | XAS raw sectors | Form 1 | Form 2 | File 1 / channel 1 / submode `0x48` / coding `0x00` |
|---|---:|---:|---:|---:|
| Japan Rev.1 | 251,473 | 117,370 | 134,103 | 112,726 sectors |
| USA | 249,552 | 115,694 | 133,858 | 111,099 sectors |

Every examined XAS raw sector has mode byte 2 and identical XA subheader bytes at `16..19` and `20..23`. Both releases contain XA Form 2 sectors with file 1, channels 0–7, submode `0x64`, and coding `0x01`. The eight-way interleave agrees with the descriptor interpretation. The USA set of 111,099 `0x48` sectors matches the externally reported STR sector count, but this count and header check do not independently validate STR magic, chunk order or frames.

### XA descriptor table

Both Japan Rev.1 and USA EXEs contain 50 twelve-byte little-endian `<III` rows: `start_group`, `end_group`, `channel`. Table offsets are `0x157E4` (Japan Rev.1) and `0x15578` (USA); all 50 rows are byte-identical. The original Japan EXE has a different twelve-byte BNS index, and its XAS descriptor table has not been located at the known Rev.1/USA locators.

For `(start, end, channel)`, validated absolute BIN/CUE sector selection is:

```text
disc_lba = xas_iso_lba + start + channel + 8 * n
0 <= n <= (end - start) / 8
```

All 50 rows are eight-sector aligned, remain within XAS, do not overlap one another, and match raw subheaders in both local releases. Each selected stream has ordinary submode `0x64`, coding `0x01`, and exactly one terminal `0xE4` sector. This verifies both the descriptor structure and release-specific addressing.

The rows select 118,001 raw sectors out of 134,103 Japanese and 133,858 USA XA Form 2 sectors. The respective 16,102 and 15,857 remaining Form 2 sectors are all channel-1 audio (submode `0x64`, coding `0x01`) of the 22 STR movies ([below](#str-movies)): 16,018 / 15,781 lie between a movie's first and last video sector, the rest are the audio lead-ins (up to 65 sectors before a movie) and tails (up to 305 sectors after it), including the final `0xE4` sector of XAS, which ends the last movie's audio. So every Form 2 sector belongs either to one of the 50 streams or to a movie.

USA XAS has 51 sectors with submode `0xE4`: EOF `0x80`, realtime `0x40`, Form 2 `0x20`, and audio `0x04`. The EOR bit `0x01` is absent in the checked USA XAS submodes. Fifty terminal sectors belong to the selected streams; the additional EOF-marked sector at the final XAS LBA ends the audio of the last movie (the logo). The count 51 does not represent STR-region count.

Japan Rev.1 XAS is 1,921 logical sectors longer than USA. The difference comprises 1,627 additional `0x48` sectors (`112,726 - 111,099`), 245 additional channel-1/`0x64` XA sectors (`30,603 - 30,358`), and 49 additional channel-0/`0x00` sectors (`4,644 - 4,595`). These counts explain the size difference but do not establish an extra game mode or more complete content.

The 22 movies of both releases are scanned by `inspect_xas.py` ([below](#str-movies)). The local USA Track 1 and EXE SHA-256 match the release used by the published analysis. Do not assign song, voice, movie or fighter names from XA numeric IDs alone.

The external [XAS discussion](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/MODDING.md) and [inventory tool](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/tools/XAS_TOOL.md) report 22 USA STR regions with magic/type, chunk-order and frame-number validation. Our `0x48` sector count corroborates their aggregate count, and `inspect_xas.py` repeats the magic/type and frame-number grouping locally (22 movies in each release). This is third-party USA research, not an official Namco format specification or proof of each XA stream's role.

Original Japan SLPS-01300 has the same XAS ISO user-payload SHA-256 as Japan Rev.1, and all 251,473 raw XA subheaders match sector by sector. Rev.1 is therefore a suitable Japanese XAS data source while the original EXE/BNS remains a separate analysis target.

## PlayStation Sound Artist Tool

Sony's PSY-Q [Sound Artist Tool manual](https://psx.arthus.net/sdk/Psy-Q/DOCS/Devrefs/Sound20.pdf) describes general platform VAB, VH, VB, VAG, SEQ, SEP and XA structures. It can guide field interpretation but does not show that Tekken 3 uses every listed format. In particular, the current game analysis has not established SEQ or SEP files.

## STR movies

[`tools/research/inspect_xas.py`](../../../tools/research/inspect_xas.py) walks every XAS sector of a raw image and groups the Form 1 video sectors (STR header `0x0160`, type `0x8001`) into movies by their frame numbers; the XA audio sectors inside a movie's range give its sound channel. Both releases contain **22 movies**, all with MDEC bitstream **version 3**, interleaved XA audio on channel 1 (one audio sector per eight, double-speed playback) and about 20 frames per second (for example 648 frames over 4,860 sectors, 32.4 s at 150 sectors/s):

| Japan Rev.1 XAS sector | Frames | Size | Use |
|---:|---:|---|---|
| 122000 … 226098 | 458–1010 each (20 movies) | 256 × 224, 256 × 192 or 256 × 176 | Character endings |
| 233673 | 1950 | 256 × 224 | Opening |
| 248409 | 276 | 320 × 240 | Short logo movie |

**Playback.** Both `title.ovl` (opening; `0x800E1DFC`–`0x800E2CE0`) and `ending.ovl` (endings and Theater; `0x8010D474`–`0x8010E7B0` and a library copy at `0x80114D1C`–`0x801154CC`) carry the same player, built on the PsyQ streaming library and `libpress`:

- **Streaming.** The movie is opened by path (`\MOVIE\<name>.STR;1` in `ending.ovl`, `FUN_8010E6CC`) or LBA. It streams through a 32-sector ring (`StSetRing`, `StSetStream(1, 0, −1, …)`, `DsRead2(lba, 0x1C0)` retried until it starts; `FUN_800E1FD4`/`FUN_8010E180`).
- **Decoding.** Each frame is fetched with `StGetNext` (`FUN_800E22D8`), its bitstream decoded by the VLC routine (`FUN_800E2CE0`, `FUN_801154CC`) into one of two run-length buffers, and sent through the MDEC with the DMA helpers (`DecDCTReset`/`DecDCTin`/`DecDCTout`, `FUN_800E2620`–`FUN_800E2C2C`).
- **Output.** The MDEC decodes in 24-bit colour: the image is width × 3/2 halfwords wide, in 16-pixel (24-halfword) slices, centred in two display buffers at y 0 and 240 (`FUN_800E1DFC`).
- **End.** A movie ends at its last frame number or when no frame arrives for 600 vertical blanks (`FUN_800E2214`/`FUN_800E2420`, `FUN_8010E3F0`/`FUN_8010E5FC`). The MDEC wait loops print `MDEC_in_sync`/`MDEC_out_sync timeout` and reset the decoder after 0x100000 polls.

The USA disc stores the same movies in a different order; its version of the 256 × 192 ending at Japanese sector 156398 has 561 frames instead of 809, which with the extra Japanese XA sectors accounts for the Japanese XAS being 1,921 sectors longer.

### Movie table (`ending.ovl`)

The movie player lives in `ending.ovl` (game state 19, `0x8010E8C0`; custom version-3 MDEC decoder `0x801154CC`, DecDCT VLC table built by `DecDCTvlcBuild`). A movie is selected by index through two tables at the start of the overlay; the retail layout (source kind 3, `FUN_8006B000`) uses sector ranges at `0x800B9378` (16-byte rows: first and last XAS sector) and 16-byte descriptors at `0x800B97CC`:

| Offset | Field |
|---:|---|
| `+0x00` | `u8` row of the sector table |
| `+0x02`, `+0x04` | `s16` width, height |
| `+0x06` | `s16` last frame |
| `+0x08` | `u8` audio volume |
| `+0x0A` | `u16` flags: bits 0–1 end/fade mode, bit 2 restart the stream when it runs past its range, bit 3 clears the screen to white instead of black when the movie ends (`FUN_8010D228`), bits 8–11 caption set (1–4) drawn over the movie |
| `+0x0C` | `u32` (−1) |

Descriptor 0 is the opening (volume 112), 1 and 2 the logo, and 3–23 the endings. `title.ovl` carries its own copy of the tables (sector rows at `0x800B9E38`, descriptors at `0x800BA28C`) for the opening movies of the title sequence: descriptor 0 the opening (rows 21, sectors 233,673–248,408, played to frame 1,942) and 1 the logo (row 22, flags `0xB`: the screen turns white when it ends). The ending index is looked up in `0x800B9BFC` by `character · 4 + costume` of the winning player: characters 0–18 use descriptors `3 + character`, except that Tiger (Eddy's costume 2) uses 22, Panda (Kuma's costume 1) uses 23, Doctor B. uses Yoshimitsu's movie and True Ogre uses Ogre's; costume 3 has no entry. Two further table pairs (source kinds 1 and 2) describe development layouts with file names or different sector ranges and are not used by the retail disc.

### Movie captions

Four endings have text captions that the player draws into each decoded frame (`FUN_8010F3F8` → `FUN_8010F138`, called for every 16-pixel column the MDEC decoder outputs). The descriptor's caption set (flags bits 8–11) picks a timeline:

| Set | Movie | Captions (Japan Rev.1) |
|---:|---|---|
| 1 | descriptor 13 (Julia) | 0–10: her dialogue |
| 2 | descriptor 8 (Nina) | 11–12: a location caption and a line of narration |
| 3 | descriptor 11 (Eddy) | 16–18: a tagline and two place-and-time captions (green) |
| 4 | descriptor 19 (Gun Jack) | 19: a name caption |

- **Timeline** (`0x800B9E70`, 4-byte entries `u16 frame, s16 caption`): each set starts with `(0, −1)` and ends with `0xFFFF`. From the given movie frame the caption is shown, −1 clears it. `FUN_8010F004` selects the set at movie start (the state at `0x80194550`: current caption, set start, a copy of the record). Every frame `FUN_8010F0B4` scans from the set start and shows the last entry whose frame is below the current one.
- **Caption records** (`0x800B9CE0`, 0x14 bytes): `u32` bitmap offset, `s16` x start (pixels), y (170, or 176 for the 32-row ones), first column, width 256, height 44 or 32, 128, palette index (0, 2 or 3), 0.
- **Bitmaps** (base pointer `0x8011DA8C` → `0x800BD0D4`): 4 bits per pixel, 128 bytes per row, 0x1600 bytes per caption. Pixel 0 is transparent.
- **Palettes** (16 entries of 8 bytes: R, G, B, blend flag): set 0 greys at `0x800B9F0C`, set 2 greens at `0x800B9F8C`, set 3 greys at `0x800BA00C`. Without the blend flag a pixel replaces the movie pixel; with it the result is `((movie >> 1) + colour) >> 1` per channel. Only palette 0's colours 1–4 (the outline) have the flag.
- **Drawing** (`FUN_8010F3F8(x, column)`): for each 16-pixel macroblock column of 24-bit pixels (48 bytes per row), with `x` = 24 × column index, the caption column is `2x/3 − x start`. When it lies in `[first, first + width)`, `FUN_8010F138` draws `height` rows of 16 caption pixels from bitmap byte `offset + column/2` into the column at pixel row `y`.

The player (`FUN_8010EF7C`, `FUN_8010EF94`, `FUN_8010F004`, `FUN_8010F0B4`, `FUN_8010F3F8`, `FUN_8010F138`) is ported in `tools/research/movie_captions.py` and verified by `verify_theater_sim.py`.

`tools/research/movie_captions.py` prints the timelines and exports the bitmaps as PNG to `work/movie_captions/` (game data, not for the repository). The USA version has 9 English captions in five sets (a set's end marker is followed by the next set's `(0, −1)` or by the palettes), captioning other movies of the same list: descriptors 8 (set 2), 10 (set 1), 11 (3), 14 and 23 (5), 19 and 24 (4), none for Julia's 13; with other timings (set 1 is `XIAOYU LAND` / `HEIHACHI LAND`, the Nina texts are translated, Eddy's read `SEEK THE TRUTH...`, `EDDY'S ROOM 23:00 HRS`, `ORGANIZATION HQ 0:00 HRS`, and `Dr. Abel`); its tables sit 0x620 bytes lower, like the whole USA screen overlay ([memory-map.md](../code/memory-map.md)).

## Unknowns

- None known. Playback rate, volume, pan, ADSR and SPU voice allocation are in [sound.md](../code/sound.md). Sound effects and voices are single key-ons of VAB tones; the executable never opens a SEQ/SEP sequence (only the libsnd tick `SsSeqCalledTbyT` runs).
