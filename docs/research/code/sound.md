# Sound, music and vibration

This document describes how the game plays sound effects, character voices and music, and how it drives controller vibration. Sample data formats are in [vab-banks.md](../formats/vab-banks.md) and [sound-and-video.md](../formats/sound-and-video.md). Addresses are Japan Rev.1.

Status: the playback-rate rule is `confirmed` bit-exact against the game's `SsPitchFromNote` in the [CPU harness](../tooling.md); tables and control flow are `confirmed` from decompiled code, including the mapping of every music track to its scene.

## Sound banks in SPU memory

`SoundInit` (`0x8007508C`, called from boot) initialises libsnd (tick mode `0x1000`, master volume 127, CD audio volume 128) and opens four VAB slots at fixed SPU addresses (`0x80027B68`):

| VAB id | SPU address | Source | Content |
|---:|---:|---|---|
| 0 | `0x01010` | VH at EXE `0x80025AAC`, body at `0x800D3C8C` | Combat sound effects (46 samples, 50 tones, 252,880 bytes). |
| 1 | `0x3D9C0` | VH at EXE `0x80026CCC`, body at `0x8011063C` | System and menu sounds (25 samples, 103,552 bytes). |
| 2 | `0x56020` | Character VH/VB (BNS) | Voice bank of one character. |
| 3 | `0x80000 − size` | Character VH/VB (BNS) | Voice bank of a second character; sizes per bank at `0x80027B04`. |

VAB 0 and 1 are part of the executable image: their bodies lie in the area that overlays later overwrite, so they are uploaded once at boot. Slots 2 and 3 form a two-entry cache of character voice banks: `SoundSelectBanks` (`0x8007522C`) maps each fighter's character to a voice bank through `0x80027AEC` (identity for IDs 0–20, 21 → 11, 22 none), keeps a bank already resident, and loads the other (`FUN_80075570`); `g_fighterVab[2]` (`0x800A9100`) records which slot each fighter uses. Reverb is switched off.

## Sound code

Every playable sound is a 16-bit code:

| Bits | Field |
|---|---|
| 14–15 | Bank: 1–3 → VAB `value − 1`; 3 → the fighter's own voice VAB (`g_fighterVab`); 0 = no sound |
| 10–13 | SPU voice. Voices above 5 are offset by the player number so each player owns a channel; bit `0x80` of the attenuation argument adds 16. |
| 6–9 | Volume index into `0x80027B58`: `45, 70, 77, 81, 84, 88, 92, 96, 100, 104, 108, 112, 115, 119, 123, 127`, right-shifted by the attenuation argument. |
| 4–5 | VAB program. |
| 0–3 | Tone; played as key `60 + tone` with fine tuning 0. |

`SoundPlayFighter` (`0x800756A4`) stops the voice and calls `SsUtKeyOnV(voice, vab, program, tone, 60 + tone, 0, vol, vol)`; `SoundPlaySystem` (`0x800758E8`) plays entry `n` of the system table (reached only through `FUN_80040E98`: the announcer, the continue and game-over calls and the sound scripts' ids 5–9, all in VAB 1, so the entries of bank 3 — which would play VAB 2, the voice cache's first slot, whatever character it holds — are never played this way); `SoundStopFighter` (`0x8007588C`) keys the voice off. For character 15 codes are first remapped through `0x8001AF7C`.

### Playback rate

Each tone of the Tekken 3 VABs covers exactly one key (`min = max = 60 + tone`), so the game always plays a tone at its own key. libsnd converts key and tuning to the SPU pitch register (`0x1000` = 44,100 Hz):

```text
n     = key − (center − 60) + ((shift >> 3) >> 4)
pitch = table[(n mod 12)·16 + ((shift >> 3) & 15)] >> (5 − n div 12)     # table[i] = floor(4096 · 2^(i/192))
rate  = 44100 · pitch / 4096
```

with `center` and `shift` from the tone's `VagAtr` (+4, +5); this is `4096 · 2^((key − center + shift/128)/12)` quantised to 1/16 semitone. `spu_pitch` in [`decode_vab_sample.py`](../../../tools/research/decode_vab_sample.py) implements it and matches the game's `SsPitchFromNote` executed in the harness for 34,400 combinations of centre (60–109), fine tuning and tone; the exporter now writes each sample at its game playback rate by default. The tunings found in the banks therefore mean:

| `center − key` | `shift` | Pitch | Playback rate |
|---:|---:|---:|---:|
| 12 | 0 | `0x800` | 22,050 Hz |
| 18 | 70 | `0x5D2` | 16,042 Hz |
| 24 | 0 | `0x400` | 11,025 Hz |
| 30 | 50 | `0x2E3` | 7,957 Hz |
| 32 | 50 | `0x293` | 7,095 Hz |

A converter should resample each VAG at `rate` computed from its tone; the tone's ADSR, volume and pan still apply on top.

**Voice volume and pan.** Every sound goes through `SsUtKeyOnV(voice, vab, program, tone, note = 60 + tone, fine = 0, v, v)` with equal left and right `v` (the volume-table value, `SoundPlayFighter`), so the game never pans by position. The resident libsnd (`SsUtKeyOnV` → `_SsVmKeyOnNow`) computes the SPU voice volume as

```text
base = ((v · vabMasterVol · 0x3FFF) / 0x3F01) · programVol · toneVol / 0x3F01      (L = R = base)
for pan in (tone pan, program pan, key-on pan = 0x40):     # three stages, each 0..127
    if pan < 0x40: R = R · pan / 63
    else:          L = L · (127 − pan) / 63
```

(integer division; the key-on pan 0x40 leaves both sides unchanged; in mono mode both sides take the larger value). `_SsVmFlush` then writes the voice attributes with `SpuSetVoiceAttr`: ADSR1 = tone `+0x10` and ADSR2 = tone `+0x12` plus the library's damper offset `0x800AE0DC`, which is only ever set to 0 — so the envelopes are exactly the VH values.

## System sound table

`g_soundTable` (`0x80097474`) holds 212 `u16` sound codes (ids `0`–`0xD3`, followed by the sound scripts at `0x8009761C`) indexed by 12-bit sound ids. Entries 1–`0x40` are menu sounds in VAB 1 (voice 1); the later entries are combat effects in VAB 0 (voices 8 and 10) or the fighter's own bank. Move data uses ids up to `0x72`; the higher ids are played by code and by `SoundPlaySystem`. For Mokujin (character 15) `SoundPlayFighter` first passes each code through `FUN_80075830`: 13 pairs at `0x8001AF7C` `(id, replacement code)` swap the codes of ids `0x5C`, `0x7D`, `0x80`, `0x83`, `0x8C`, `0x8D`, `0x8F`, `0x91`, `0x93`, `0x94`, `0x98`, `0x99`, `0xAB` for Mokujin-specific sounds. Examples: `0x4A` swing (played at `+0x2D − 1` of every attack by `FUN_80041DC8`), `0x4F` and `0x53`/`0x54` landing and jump sounds, `0x80`–`0x84` hit impacts.

`FighterSoundById(player, id)` (`0x8004108C`) plays `g_soundTable[id & 0xFFF]` when the id's top nibble is non-zero and stops the voice when it is zero.

## Character voices

`g_charVoices` (`0x8001AD54`, 24 bytes per character ID):

| Offset | Content |
|---:|---|
| `+0x00` | Pointer to the voice list: four `s16` counts (categories 0–3), then the sound codes of all categories in order. |
| `+0x04` | Pointer to the attack-shout list: count, codes. |
| `+0x08` | Pointer to the damage-voice list: count for light hits, count for heavy hits (damage ≥ 20), codes. |
| `+0x0C` | `s16` voice cooldown (10 frames). |
| `+0x0E..` | Sound ids for landing, jump and knock-down. |

A voice id has the form `0xCnnn` with category `C − 2` (2–5) and index `nnn` in that category. `FighterVoice(player, char, id)` (`0x80040F28`) looks the code up and plays it; category-4 voices are additionally passed to `FUN_8006F4F0`, and are not written to the replay while the fighter is in a throw.

## Fighter sound logic

`FighterSounds` (`0x80041138`, per fighter per frame) handles, in order:

1. **KO**: a random KO voice from the first category.
2. **Opponent KO'd by this move**: sound `0x7044` or `0x7048` (by the attack descriptor's first joint).
3. **Move sound list** (move `+0x1C`, section 3 of the bank): up to three `u16` commands ending at `0xFFFF`, by top nibble:

| Nibble | Action |
|---:|---|
| 1, 7 | On contact: impact sound chosen by guard/hit and joint (`0x704D/0x704E`, `0x707A/0x707B` for character 15), with character-specific handlers for characters 15 and 16. |
| 2 | At frame 1, alive and not in voice cooldown: voice `id`, starts the cooldown. |
| 3 | At frame 1: voice `id` without cooldown. |
| 4, 5 | Sound id `id`. |
| 8 | Start sound script `id & 0xFFF`. |
| 9 | Special voice handling (`FUN_80041C48`). |

4. **Sound scripts** (`0x8009761C`): `u32` entries `frame (12 bits) | type (4 bits) | code (16 bits)`, ending at frame 0, run against a per-fighter frame counter (`+0x120`). Types: 0 global sound, 1 own voice or sound, 2 opponent's voice or sound, 3 special.
5. **Damage voice** on every other frame after a clean hit: light or heavy list by the attacker's damage, 40-frame cooldown.
6. **Attack shout**: one in four new attacking moves plays a random attack shout.
7. **Jump, landing, knock-down**: ids `0x1053` at the air-window start, `0x1054` on `landedA`, `0x104F` on `landedB`.
8. **Swing**: `0x604A` one frame before the active window.

Move events 1–4 also produce sounds through the camera-shake and impact effects ([moves.md](moves.md#frame-events)).

## Music

`MusicPlay(track, prepare)` (`0x8006B0FC`) plays one of 32 music tracks. The track table `0x8002523C` has two 2-byte variants per track; the variant is chosen by the BGM option `0x800982E5` (0 or 1; other values and game states 8–17 disable music).

| Byte | Meaning |
|---|---|
| 0 | Bit 7 clear: XA stream index into the 50-row XAS table (`0x80024FE4`: start, end, channel). Bit 7 set: CD-DA entry `value & 0x7F` (position table `0x800A0B40`). |
| 1 | Bit 7: loop; bits 0–6: volume. |

For XA the driver sets the CD filter (`CdlSetfilter`, file 1, the row's channel) and reads from `xas_lba + start` with `CdlReadS`; the stream ends at `xas_lba + end`. CD-DA entries use `CdlPlay`. Variant 0 uses XA streams `0x15–0x31`, variant 1 streams `0x01–0x14`, so the two variants are the two soundtracks selectable in the options; track 4 is CD-DA in both. Tracks 29–31 use streams `0x2F–0x31` in both variants.

A disc read stops the music for good: `BnsStartQueuedLoads` (every overlay and data load: the overlay loader `FUN_80052FAC`, `title.ovl`/`enbu.ovl` in `TransitionScreen`, `LoadOverlaySync` for the VS screen's background and big pictures when they are not the ones already loaded (`FUN_80052808`) and for the stage archive (`FUN_80036854`: always in Tekken Ball and Tekken Force, in the other modes only when the stage cache `0x800A0C48` holds another stage; `FUN_8006C870` empties it at a mode start (`FUN_800DAF2C`, the demonstration's `FUN_800D3028`), in `ScreenOverlayLoad`, in the movie players and in the attract performance, whose set-up `FUN_800D3D64` and the ranking's backdrop `FUN_80036BC8` put their own stage there)) and the movie players (`title.ovl` `FUN_800E1614`) call `FUN_8006B834(0)`, which fades the stream to 0, pauses the drive (`CdlPause`) and forgets the track (`0x800A09C8 = 0xFFFF`). So the select music ends when Start + Select returns to the main menu or when the VS screen loads new pictures, and no track plays over a movie.

The track names come from the Theater sound player (`ending.ovl`, table `0x800BB49C`, 28-byte records: `u8 id = 2·track`, a two-bit version mask at `+8`, the name at `+0x10`). Variant 0 is the ARRANGE soundtrack and variant 1 ARCADE (the BGM option order):

| Track | Name | Arrange / arcade stream |
|---:|---|---|
| 0 | EMBU (demonstration) | `0x03` / `0x03` |
| 1 | SELECT | `0x2B` / `0x11` |
| 2 | CONTINUE? | `0x18` / `0x01` |
| 3 | GAME OVER | `0x1C` / `0x04` |
| 4 | STAFF ROLL | CD-DA Track 2 in both |
| 5 | OGRE DEMO | `0x28` / `0x0E` |
| 6 | RESULT | `0x12` / `0x12` |
| 7–16 | PAUL, LAW, LEI, KING, YOSHIMITSU, NINA, HWOARANG, XIAOYU, EDDY, JIN | own arrange and arcade streams |
| 17–19 | JULIA, KUMA, BRYAN | own arrange stream / shared arcade stream `0x06` |
| 20, 21 | HEIHACHI, OGRE | own streams |
| 22 | MOKUJIN | `0x25` / `0x06` |
| 23–26 | GUN JACK, ANNA, DOCTOR.B., GON | own arrange stream / `0x06` |
| 27 | TRUE OGRE | `0x29` / `0x0F` |
| 28 | TIGER | `0x2C` / `0x06` |
| 29–31 | (not in the sound player) | `0x2F`, `0x30`, `0x31` in both |

Tracks 7–28 are the character themes in the order of the character records' music byte (Paul 7 … Tiger 28). In the ARCADE soundtrack the characters added for the home version share stream 6. The list's version mask is 3 for Mokujin and 1 (arrange only) for the others, but the player never reads it: its ARCADE page plays stream 6 for all of them ([game-bugs.md](game-bugs.md) #38).

The sound player also lists the Tekken 2 and Tekken 1 soundtracks for the Theater's disc mode:

- Tekken 2 (28 tracks): HEIHACHI, PAUL, LAW, JACK2, NINA, KING, YOSHIMITSU, MICHELLE, JUN, LEI, MIDDLE BOSS, KAZUYA, DEVIL, ROGER, BAEK, SELECT, STAFF ROLL, MEDLEY, NAME ENTRY, and the stages ANGKOR VAT, KING GEORGE ISLAND, CHICAGO, SZECHWAN, MONUMENT VALLEY, AKROPOLIS, KYOTO, STADIUM, ENGLAND.
- Tekken 1 (14 tracks): SELECT, and the stages STADIUM, KYOTO, ANGKOR VAT, SZECHWAN, AKROPOLIS, VENEZIA, WINDERMERE, KING GEORGE ISLAND, CHICAGO, MONUMENT VALLEY, FIJI, then STAFF ROLL, NAME ENTRY.

The stage's track comes from the character record (`0x80098120`, byte `+0x0B`) of the player whose stage is used; in mode 8 the stage number is `15 + level` and levels beyond the fourth use stage 15 with track `0x19`. The record tracks are 7–28 and, for the extra records `84–91`, 1.

| Track | Played by |
|---:|---|
| 0 | The demonstration (`enbu.ovl`). |
| 1 | Menus and character select (`select.ovl`). |
| 2 | Name entry and ranking (`ranking.ovl`). |
| 3 | Game over. |
| 4 | Staff roll (`ending.ovl`). |
| 5 | The Ogre demo in the arcade ladder (`arcade.ovl`). |
| 6 | Results (`result.ovl`). |
| 7–28 | Fights, from the stage owner's character record; Tekken Force level 5 uses 25. |
| 29–31 | Nothing: no call, character record or Theater entry selects them, so XA streams `0x2F–0x31` are never played ([game-bugs.md](game-bugs.md) #25). |

The Theater sound player (`FUN_8006B47C`) plays its list entry `id` as track `id / 2` (version `id & 1`) through the same table.

## Voice key-off

Sounds end by keying off their SPU voice (`SsUtKeyOffV`); a new sound on a voice also keys the old one off first (`SoundPlayFighter`, `SoundPlaySystem`).

- `SoundStopFighter(player, code)` (`0x8007588C`) keys off the code's voice: bits 10–13, plus the player for voices above 5; codes without a bank (`& 0xC000 = 0`) do nothing.
- `FUN_8004B920(keep)` keys off every voice 0–23 except 2 and 3, which carry the announcer (effect type 16 waits for voice 2 to end before its `0x86DA`); with `keep` set it also leaves voices 1, 6 and 7. The round start calls it with `keep` = not the first round ([fight-frame.md](fight-frame.md#round-start)); the round flow with 0 when the replay hands over to the victory poses (or the round ends without them) and when Start cuts the result sequence short; the pause menu with 0 when it opens.
- The voice echoes (effect types 17 and 18) replay a fighter sound with attenuation 1, then 2 (each `SoundPlayFighter` keys the voice off first); during a replay the echo uses its own voice with attenuation bit `0x80` (16 voices up).

## Vibration

The game drives DualShock motors through `PadVibrate(player, pattern)` (`0x80029114`; player 2 = both). The pattern's slot (`0x80010050`) selects one of four queued patterns per player; `VibrationUpdate` (`0x80029228`) runs two scripts per slot — one for the small motor (on/off, pulse mask from `0x80095838` by frame), one for the large motor (strength `((v & 0xF00) >> 4) + 15`) — each a list of `u16` steps `flags(4) | level(4) | frames(8)`, where flag `0x1000` continues with the next step. Scripts come from `0x80095758`/`0x8009575C`.

| Caller | Patterns |
|---|---|
| `FighterVibrate` (`0x800760D4`): guard, hit, ground impact, heavy hits | `0x17`/`0x0A`, `0x0F`/`0x1B`, `0x19`, `0x0C`, `0x0D`, `0x05` |
| Camera shake events 1–3 (`VibrateAll`, `0x80076078`) | pattern `shake + 1` on both pads |

## Replay recording

While the replay recorder is active (`0x8009C050 == 7`), `ReplayRecordSound` (`0x80033780`) stores every sound request (kind, player, code) in a 300-entry ring so that replays reproduce voices and effects.

## Open items

- None known.
