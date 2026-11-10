# Arcade Tekken 3 (World E1): audio and effect objects, against the PS1 build

The effect objects' data is in `tools/remake_import/arcade_effects.py`. The sound is rendered from the ROM set by `tools/remake_import/arcade_sounds.py` over a port of the driver ([the port](#the-port-and-its-proof)); the remake plays it with `ArcadeAudio` ([remake-plan.md](../../remake-plan.md#m6-arcade-only-build)).

Addresses: `0x80…` are the arcade program (`prg_world_e1.unpacked.bin`) unless marked PS1 (Japan Rev.1). H8 addresses are the sub-CPU program `tet1vere.11s`, word-swapped into `work/arcade/audio/h8.bin`. `confirmed` = read in code or observed in MAME; `inferred` = deduced, not observed. All scripts and logs are under `work/arcade/audio/`, run from that folder with `python3.14`.

Headlines:

- The whole sample bank is decoded and proven against MAME.
- Offline music rendering works: the driver's port writes the C352 registers MAME's log has, in every tick of every sequence (604,702 ticks). The whole music takes about a minute to render, without MAME.
- Sounds keep the PS1's id space. Most sound scripts are identical. The ids need new tables and small logic changes.
- Effect objects are the same machine with different constants and fixed random chances, no CLUT fade ramps, and no Gon, Doctor B. or ball types. Their pages are category 42.

## 1. C352 sample bank

Chip: `confirmed`, MAME `-listxml` clock 25,401,600 Hz. Divider 288 gives **88,200 Hz**; the measured drift between rendered samples and the recording is 0 after using this rate (`ratecheck.py`), while the 87,855 Hz I first assumed drifted by 3.8 ms/s.

**Location.** ROM is `tet1wave0.5` + `tet1wave1.4` concatenated, 8 MB, no swap. The directory is in the H8 program. `0x8000` holds 7 u16le pointers:

| Slot | Value | Content | Read at |
|---:|---:|---|---|
| 0 | `0x800E` | sequence pointers, 512 × LE24 (default `0x010000` = none) | `0x41DC` |
| 1 | `0x860E` | wave pointers, 1180 × u16le | `0x5A82` |
| 2 | `0xBE68` | pitch/LFO records, by sub-track reg 7 | `0x480A` |
| 3 | `0xCE76` | volume envelopes, by sub-track reg 6 (run by `0x59B2`) | `0x4856` |
| 4 | `0xC920` | lists by reg 3, for marker values 0x7C/7E/7A/79 in sub-track `+0x0E` | `0x49A8` |
| 5 | `0xD812` | lists, same dispatch | `0x4A9E` |
| 6 | `0xDCBA` | key-split tables, 16 bytes | `0x6612` |

Roles of slots 2–5 are `confirmed` as far as which register indexes them; the record contents are only partly read.

**Record** (`0x5A78`–`0x5B16`), little-endian: `+0` pitch word (semitone<<8 | fraction), `+2` bank, `+4` flags, `+6` start, `+8` end, `+A` loop only if flag 2. So records are 10 or 12 bytes. Linked samples (flags `0x22`) continue with 8-byte pieces `[bank, flags|0x8000, start, end]`, each up to 64 KB; the driver reloads them at `0x5204`–`0x5300`, and the C352 jumps to `start<<16 | loop`.

**Flags** (MAME's): 0x8000 busy, 0x4000 key-on, 0x2000 key-off, 0x20 link, 0x10 noise, 8 mu-law, 4 no interpolation, 2 loop, 1 reverse (with 2: ping-pong), 0x100/0x80/0x200 phase invert.

**Counts** (`extract_samples.py`, `samples/index.json`): 1180 pointers = 853 samples + 302 empty + 19 noise (ids 0xED–0xFF, zero-length) + 6 continuation artifacts. 8,354,047 of the ROM's 8,388,608 bytes are covered, with gaps only at bank ends. 1185 s in total at the rates below; the longest is 10.3 s. Encoding: 566 mu-law, 287 signed 8-bit.

| Ids | Samples | Seconds | Use |
|---|---:|---:|---|
| 0x000–0x0FF | 231 | 694 | music instruments, drums, noise (`inferred` from the sequences' use) |
| 0x10A–0x14C | 64 | 62 | system and announcer (sound table ids 1–0x40) |
| 0x14E–0x2FE | 343 | 287 | character voices (voice-set lists) |
| 0x300–0x41D | 135 | 102 | effects, plus winner-name specials 0x406–0x41D |
| 0x44C–0x49B | 80 | 40 | unknown use (no table I read names them) |

**Rate.** `sum = note + transpose + wave pitch word…` (`0x4E64`–`0x4ED0`); `freq = T[hi] + ((T[hi+1]−T[hi])·lo >> 8)`, T = u16be × 128 at `0x3B22`; rate = 88200 · freq / 65536. All voice and effect scripts play note 0x30. Pitch word → rate at that note: `0x121C` → 8312 Hz (342 samples, voices and system), `0x1402` → 9275, `0x1E10` → 16,579 (94), `0x0F2A` → 7013, `0x0E20` → 6604, `0x179B` → 11,421, `0x1278` → 8490, `0x1B2A` → 14,025, `0x23A2` → 22,879. A music sample's rate depends on its note; the rate in the index is only the note 0x30 rate.

**Proof** (`confirmed`, observed):

- *Directory:* 511 injected commands (every sound-table code, every distinct voice wave; `inject_sfx.txt`, `lua/inject.lua`): each keyed voice had exactly the directory's bank and start, 0 misses, and the computed freq.
- *Content:* `-wavwrite` with `lua/wavcheck.lua`, `wavcheck.py`, for 6 waves: normalised correlation with the extracted sample **0.985–0.999**. Alternatives score far lower: other decoding 0.51–0.65, ±1 semitone at most 0.34, half rate at most 0.16. Duration within a frame of the BUSY span; RMS after the computed end is 0.

## 2. Sequencer

**Driver** (`confirmed`, read; H8/3002 at 16.9344 MHz, reset `0x100`). Function table `0x3D9A`, copied to `0xFFFE10`. Tick about **120 Hz** ([measured](#the-drivers-tick)) (ITU1 overflow, vector 30 → `0x38E6` → `0x3FA4`): `0x4030` loops over 32 channels, and `0x5B2A` runs each one's script. State: channel `0x089500 + 0x50·ch`, 8 sub-tracks per channel at `0x08A000 + 0x100·ch` (0x20 each), voice `0x08C000 + 0xC0·v`. C352 registers: `0x280000 + v·0x10` (+0 vol front L/R, +2 vol rear, +4 freq, +6 flags, +8 bank, +A start, +C end, +E loop); `0x280404` executes key-ons and key-offs.

**Sequence format** (`seqdis.py <id>` disassembles any). A byte with bit 7 set is a delay (`&0x7F`); otherwise op = `&0x3F`, bit 6 = one common value for all selected sub-tracks. 48 opcodes (handler table `0x3DCC`): register writes by sub-track mask, notes (0x20–0x27, bit 0 = note from a variable), tempo (0x09, 0x0A, 0x0B, 0x0C), start sequence on a channel (0x0D, 0x0E), jump, call, repeat, volta, return, end (0x10–0x15), ALU (0x1E), compare and branch (0x1F), text label (0x17). No random op occurs in the music's script trees (scan of the 19 music sequences).

**Ids** (`confirmed`, the scripts' own text labels and the main CPU's calls):

| Sequence | Label | PS1 track equivalent |
|---|---|---|
| 0x10, 0x12–0x17, 0x19, 0x1B–0x1E | BGM01 paul, Law, LAY, king, YSMT, NINA, HEIHACHI, FALAUN, xiao, BGM13, JIN, ORGE | 7–16, 20, 21 by character |
| 0x11 (0x18, 0x1A same pointer) | BGM02 mischell | shared theme, as PS1 arcade stream 6 |
| 0x60 | MOVIE, attract, channel 0xC (`FUN_801bd5a0`) | 5 (`inferred`) |
| 0x61, 0x62 | BGM18 C_SELECT (`FUN_801c06e4`) | 1 |
| 0x63 | BGM20 CONTINUE? | 2 |
| 0x64 | BGM21 GAME_OVER | 3 |
| 0x65 | BGM22 S-ROLL (`FUN_801e5f50`) | 4 |
| 0x66 | BGM23 EMBU (`FUN_801e0e30`) | 0 |
| 0x20–0x2E, 0x30–0x3E, 0x40–0x4E | a BGM's parts, started by it on channels 1, 2, 3 | |
| 0x100–0x106, 0x110–0x113 | effect and voice players | |

PS1 track 6 (RESULT) has no arcade call I found. The stage's music is the costume record's byte `+0x0B` (pointers `0x801FF454`, 4 per character; `FUN_801b5270`, stored at `DAT_8021fbd4`): a sequence id directly, 16–30, or 1 for True Ogre.

**Sections** (`confirmed`, read). `FUN_8019dec4` calls `FUN_8019eed4(track)` when the counter `DAT_8021fd88` is 3. A new track starts the sequence. The same track again sets `var[0xE0]` to the next of 1, 2, 3, 2, 3…; track 1 means sequence 0x1E with `var[0xE0]=1`. In most BGMs a polling channel (sequence 0x40 and each BGM's own) waits for `var[e0]` and sets `var[e1]`, which the melody and drums test after every `call`, jumping to a section with its own loop; in 0x16, 0x19, 0x1C and 0x1D there is no poller and they test `var[e0]` itself, and 0x14, 0x15, 0x17 and 0x1B choose some sections one way and some the other. So a BGM is an intro plus up to three more looping sections ([as run](#sections-as-the-driver-runs-them)). The main CPU never writes `var[c0]` (the callers of `FUN_801b0a30` write only e0, 1, 0xC and 2–5), so EMBU starts at its beginning (`inferred`: from the calls, not observed).

**Viability.**

- **(b) MAME capture** is not viable: it needs MAME on the user's machine. It stays useful only for verification.
- **(a) A Python port of the sequence VM plus a numpy C352 mixer is viable**, and half is proven:
  - `c352mix.py` renders a log of C352 register writes (`lua/c352regs.lua`) per voice. Against `-wavwrite` over 40 s of attract, with routes 0 and 1 only: correlation **0.992** overall, 0.9998 below 1 kHz, 0.988 at 1–4 kHz, 0.935 at 4–8 kHz, gain exactly 1/8 (`mixcheck.py`). The high bands fall because the shared noise generator is not interleaved sample-exactly and because of resampling.
  - Speed: 40 s of audio in about 4 s.
  - Rear routes make it worse (0.949), so MAME routes only the front registers (`confirmed` by that measurement; the cabinet's wiring is not known).
  - Load: about 2500 register writes per second at most, 101,666 in 40 s. No main-CPU dependency except `var[e0]` and `var[c0]`.
- **The VM port is done** (below). About 12 KB of H8 code at `0x3D9A`–`0x6C00`: dispatch and ops, pitch and volume per tick (`0x4D78`), envelope (`0x5916`, `0x59B2`), LFO-like handlers (`0x54A8`, `0x5386`, `0x530A`, `0x4FC0`).
- **A Python H8 interpreter** would have avoided the semantic port but costs about 1.5–3 s per game second (`inferred`: up to about 1M instructions per game second at about 2 µs each), 1–2 h for all sections on one core. Not needed.

### The port and its proof

`tools/remake_import/arcade_sound_vm.py` is the driver, `arcade_c352.py` the chip; what no script reaches raises `SoundVmError` rather than guessing. `tools/research/verify_arcade_sound_vm.py` replays MAME's logs (`arcade_sound_log.lua`: the main CPU's words, the chip's answers to flag reads) and compares every register write:

- **`confirmed`:** 33 scenarios (every music sequence, the four player routes over all waves, the fixed sequences, the linked waves, the attract): 604,702 ticks, 14,612,958 register writes, identical in value, order and tick.
- **Negative controls fail as they must:** a wrong sequence number, the main CPU's words two ticks late, a frequency table altered.
- **With the port's own chip answering the flag reads:** 1,540 of the ticks differ (0.25 %; at most 3.48 % of one scenario). They are voice ends one look of the driver (2 ticks) apart and, after such an end, a next note on another free voice: MAME applies a write at its timeslice's time, so its notes wander by tens of samples against each other (measured: up to about 60 samples at 88.2 kHz). This does not exist on a board; it says nothing of the cabinet.
- **The mix:** `--mix-check music_10` against `-wavwrite`, windows of 0.25 s at their best local lag: median correlation 0.980 (left), 0.987 (right) below 1 kHz, gain 0.975, 0.983 at the 1/8 of MAME's sum. The same mix half a second late gives 0.05. A whole-song correlation means nothing here because of that wander.

Ported from reading and reached by no log, so `inferred`: the fade through bit 12 of a command, a chained note's continuation, `poke16` to other targets, opcode 0x15 taken directly, key split, note mode 2, following tracks, the pan list's ops 0x81–0x83 and its hold branch, the pitch variable at `vp+0xF`, a third piece of a linked wave (only two-piece links exist, 9 of them), negative stereo pans.

### The driver's tick

The handler reloads ITU1 with `0xBB18` at each overflow (17,640 counts at φ/8: 120 Hz, plus its own latency). In MAME (`confirmed`, measured with the machine's time at each tick and frame): **exactly 2 ticks per video frame in every frame of every log**, the frames at 59.8261 Hz, the ticks alternately 8.340 and 8.375 ms apart, the first of a frame 0.05 ms after the frame's end. So a tick is 737.1 chip samples there, not 735. What locks the timer to the frame is `inferred` from the code and those numbers: no handler touches ITU1 but its own, whose period (8.340 ms twice, 16.68 ms) is shorter than a frame (16.715 ms), so the ticks drift earlier each frame until one falls inside the IRQ1 handler (vector 13 → `0x398A`, about 49 µs with its delay loop), which holds it until it ends. That the frame fires IRQ1 was not checked, and the real board was not measured.

The remake needs no more: its simulation runs 2 ticks per 60 Hz step, and music and sounds are rendered at 735 samples per tick. They run 0.29 % faster than in MAME, as does the whole game.

### Sections as the driver runs them

Run in the port with the write at many different times (`confirmed` for the port, whose every register write equals MAME's; the transitions themselves are the scenarios `music_*`):

- The script clears e0 and e1 at its first steps: a write before the start is lost (measured on 0x1E). `FUN_8019EED4` writes True Ogre's `var[e0]=1` just before it starts 0x1E, so that write is without effect (`inferred`: no log has that fight). The next round's write is then 2, which the poller, waiting for 1, ignores; `ArcadeAudio` follows the same rule.
- A silent channel (3 in the BGMs that have one) polls: it waits for e0 == 1, then 2, then 3, then 2 and 3 in turn. Any other value does nothing. It then writes e1 about a bar later (208–253 ticks).
- Most channels jump when they test e1 == the section, at their next bar. Some test e0 itself and jump **a bar earlier**: channel 2 in 0x10–0x14; in 0x1E channels 0 and 4 for section 1 (channel 1 follows 676 ticks later), 2 for section 2, 2 and 4 for section 3.
- Those relations held for 89 of 90 write times tried (0x10, 0x13, 0x14, 0x1E; three transitions each): in the other one, 0x13's section 3, channel 0 jumped a bar after channel 1 and stayed a bar apart.
- Where e0 alone chooses a section, every channel that carries it tests e0, so the jump is at their next bar with no poller's delay: 0x16, 0x19, 0x1C, 0x1D for all three sections, 0x14 section 3, 0x15 sections 2 and 3, 0x17 section 1, 0x1B section 1 (`confirmed`: each scenario `music_<seq>` writes e0 = 1, 2, 3 thirty seconds apart and the port's register writes equal MAME's there; which variable each channel tested was logged in the port). In 0x1B's section 3 (and in 0x15's, depending on when e0 is written) channels testing e0 jump and one testing e1 follows about a bar later, as in 0x10–0x14. The game writes e0 once a round; when e0 alone chose the last section, writing the next value before every channel has tested it (in 0x1B channel 0 jumps a tick before channels 1 and 2) leaves those behind, so the converter waits 1,024 ticks after such a jump.
- Sections reached: every BGM has four (0–3). The converter took only the jumps on e1 until issue n0madic/Tekken3Remake#31 (Jin's music never left its intro), and left 0x14 with three, 0x15 with two and 0x16, 0x17, 0x19, 0x1B, 0x1C, 0x1D with one. 0x18 and 0x1A = 0x11; 0x62 = 0x61 (same scripts). No loop: 0x60, 0x64, 0x65, 0x66.

### What the converter writes

`arcade_sounds.py`, FFmpeg as for the PlayStation's music; 22 sequences, 58 files, 47.3 min of music, 42 MB. MAME is not needed. A second run gives identical files.

- **`music/arcade.json` (group `music`), `music/s<seq>_<section>.ogg`:** per sequence its sections, each with `length`, `loop`, `cues` (the file's times of the tests of the variable the next section's jump tests: e1, or e0 by the channels that are no poller; the jump back from 3 to 2 is taken to test what the jump from 1 to 2 does, `inferred`), `delay` (from the write to e1; 0 where e0 itself is tested). The converter first runs each BGM to find how it enters sections 1, 2, 3 (`explore_sections`: the first jump on e1, unless channels testing e0 jumped and no e1 jump followed within 1,024 ticks), then replays those jumps for each section's analysis and render (each write after the sequence has settled: at a jump on e1, 1,024 ticks after one on e0). Rendered stereo at half the chip's rate, the board's sum × 4 (`MASTER_GAIN`; the loudest section peaks at 30703), and each sequence's `peak`, the loudest sample of its sections.
- **`sounds/arcade.json`, `sounds/w<wave>.wav`:** 513 samples as they are, at their rates, and 63 plans read by running the player sequences: on which C352 voice, at which tick, how loud per tick. A player script holds its note **510 ticks** (4.25 s), then releases; a linked wave's pieces, a replay's echoes and the winner's chained name come out of those runs, so no number of the scripts is in the runtime.

`ArcadeAudio` runs the plans on a clock of 2 ticks per step; `SectionMusic` switches music files at the next cue after `delay`, with a 30 ms crossfade. How it was checked:

- A capture of the game with Godot's movie writer (`--write-movie`, 45 s, pad script through the select and a fight): non-silent throughout the fight, RMS about 2000; the log shows music 0x61, BGM 0x13, section 1 at the second round, and each sound request.
- A capture of `ArcadeAudio` alone, section writes at known steps, against the port's render of one continuous run with the same writes: 158 windows of 0.5 s, median correlation 0.98 below 1.5 kHz, drifting by at most 6 ms over four section changes.

**Known differences from the board** (both from that comparison):

- A section's file starts where the channels that test e1 jump. In the bar before, the runtime keeps playing the old section; on the board the channels that test e0 already play the new one (correlation falls to 0.2–0.4 for that 2 s). Fixing it takes a file per group of channels. `TODO:` in `section_music.gd`.
- In the rare case above the file has the channels together, the board a bar apart until the next change.
- The music was rendered alone, so the sound channels take no voices from it, as they do by priority on the board.
- `FUN_801B0A70`, the coin's sound, is not ported: the remake has no coins.

### Merged music

With a disc and `--arcade`, the converter renders the BGMs (0x10–0x1E, 15 sequences, 52 files) into the same `music/arcade.json` and adds `ps_tracks`: per PlayStation fight track (7–28, [sound.md](../code/sound.md)) the arcade sequence it stands for, the section it starts in and whether later rounds move it on (`arcade_sounds.PS_TRACKS`, issue n0madic/Tekken3Remake#31). The sequence is the arcade character's own, from the arcade's character records (byte `+0x0B`): Anna has Nina's 0x16 and Tiger Eddy's 0x1C there, where the PlayStation's ARCADE soundtrack gives both the shared stream 6; Doctor B. and Gon, absent from the arcade, take the shared theme 0x11. Ogre's two tracks are the two parts of 0x1E as the arcade plays them: the Ogre fight (21) stays in the intro, since `FUN_8019EED4` moves the Ogre's BGM on only after his scene, and True Ogre (27) goes on from section 1, which the scene wrote.

`AudioDirector` plays a fight's track as that BGM when the BGM option is ARCADE (the Theater keeps the disc's streams). The PlayStation asks for the stage's track at every round start; where the disc's music only gets its volume back, the arcade BGM gets the next section written, 1, 2, 3, 2, 3…, and a match's first round starts it again, as the arcade's fighters' load forgets its track (the remake reads the round from the fight, `AudioDirector.fight_round`). It plays at the track's ARCADE volume raised by 1.9, the median ratio of the disc's ARCADE streams' RMS to the renders' over all sections (1.2–2.7 by track), but no further than the sequence's `peak` allows below full scale (`inferred`: measured on the files, not judged by ear).

## 3. Sound commands

**Protocol** (`confirmed`, decompile and injection). Main `0x1F080000` = H8 `0x080000`, same word values. Commands at `+0x100 + 2·ch` (32 channels), variables at `+0x200 + 2·i`, gate `DAT_8021fc20 != 0 || DAT_8021fc64 == 0`.

- Word: bit 14 start, id = `&0x7FF`; bit 11 link to another channel; bit 15 is set by the driver while running, and bit 15 clear on a running channel stops it; bits 12–13 are fade logic (`0x4106`).
- Functions: `FUN_801b0810(id,ch,slot,val)`, `FUN_801b086c` (stop), `FUN_801b0924`/`FUN_801b0968` (start), `FUN_801b09ac` (ch 0 = 0xFFF), `FUN_801b09c4` (id|0x2000), `FUN_801b0a30(slot,val)` (variable), `FUN_801b0acc(keep)`, `FUN_801b0b14` (init 0x100–0x106).

**Id spaces.** The main CPU sends a player sequence and passes the wave number in a variable:

| Call | Variables | Channel, sequence, C352 voice |
|---|---|---|
| `FUN_801a0c10(id)` system | var[1]=param, var[0x10]=wave | ch 0x14, seq 0x100, voice 0x14 |
| `FUN_801a0cd4(p,char,id)` voice | var[0xC]=echo, var[2 or 3]=0x10, var[0x11 or 0x12]=wave | ch 0x15/0x16, seq 0x101/0x102 |
| `FUN_801a0e80(p,id)` sound | var[0xC]=replay, var[4 or 5]=param, var[0x13/0x14]=wave | ch 0x17/0x18, seq 0x103/0x104 |
| same, nibble 7 | var[0x15/0x16]=wave | ch 0x19/0x1A, seq 0x105/0x106 |

Fixed: seq 0x110 wave 0x3E8, 0x111 wave 0x3A1 (coin), 0x112 wave 0x3FE, 0x113 wave 0x3EA; `FUN_801b0a88` wave 0x304 param 0x30 (credit). Attenuation: C352 volume byte = `0x6BE0[param + …]`, about 0.18 dB per step (33 steps = −6 dB).

**The H8 scripts replace PS1 effect objects.** Seq 0x101/0x102 play the voice, plus two echoes spaced by `trk2d[09]=0x2D` with attenuations 0x0A, 0x50, 0x82 when var[0xC] ≠ 0: this is PS1 types 17/18. Seq 0x100 with waves 0x406–0x41D plays the winner's name, then wave 0x125 with `var[01]+=var[0D]`: this is PS1 type 16 / `SOUND_AFTER_VOICE` (`inferred`).

**Tables** (`confirmed` by the reading routines; "lead" = `table_search.json`):

| PS1 table | Arcade | Count, format | Lead |
|---|---|---|---|
| SOUND_CODES (212 u16 VAB codes) | `0x801FE644` | 197 × {u16 wave, u16 attenuation}; one wave per id | refuted (0x8001FAAD) |
| SOUND_SCRIPTS (470, u32 packed) | `0x801FE978` | 454 pointers → 6-byte {u16 frame, type, code}, end frame 0 | was "none", found |
| VOICE_SETS | `0x8015FEA4` | 23 × 0x18, same fields | confirmed |
| IMPACT_VOICES (5) | `0x8015F7B8` | 6: 0x709A–0x709E, 0x7071, index `(r&0xFF)·3>>7` | confirmed |
| ROUND_VOICES | `0x8015F4AA` | same ids 0x1034–0x1039, 0x103D, 0x103E, 0x103A (entry 0 unused) | confirmed |
| RESULT_VOICES | none | inline in `FUN_8019e1f0` (0x1013, 0x1019, 0x1015, 0x101A, 0x1018) and `FUN_8019e318` (0x1014, 0x1012, 0x1011). PS1's table is `SOUND_CODES + 0x13` entries, so the same ids | "none" correct |
| STRIKE_SOUNDS | `0x8015F7C8` | 0x7041, 0x7064 by `(r>>6)&2`, then 0x7065 | confirmed |
| SPECIAL_SOUNDS | `0x8015FE9C` | 0x1057, 0x1058, 0x1077 | confirmed |
| MOKUJIN_SOUNDS | none | `FUN_801a0e80` has no remap (`confirmed` for that routine); voice set 16 has zero counts | "none" correct |
| (new) swing | `0x8015F7A4`, `0x8015F7B0` | 0x1083–0x1086; 0x6049, 0x604B, 0x604C | |
| (new) strike types | `0x801FE958` | lists of 0x7042… | |

Against the PS1 (`compare_tables.py`, `confirmed`):

- Of the 454 scripts by index, 354 are identical and 355 have the same frames and types; the differences start at index 355, after which the lists are not aligned. 406 of 424 distinct arcade scripts occur on the PS1. A move's script index must therefore come from the arcade move data.
- Voice sets: the tail fields (cooldown, land ids, name ids) are identical except sets 18, 20 and 22. Counts differ in 3, 12, 18, 19, 20, 22; damage counts differ in most sets. Arcade list values are wave numbers.

**Logic differences from `fighter_sounds.gd`** (`FUN_801a104c`, `confirmed`, read). These draw from the shared `rand()`, so they are simulation state:

- Swing: `FUN_801a1eac`: characters 5, 7, 10, 0x12 with frame < 9 pick `0x8015F7A4[(r>>5)&6 /2]`; others `0x8015F7B0[(r&0xFF)·3>>8]` (PS1 fixed 0x604A).
- Damage voice gate `(DAT_8021fda4 & 3) != 0` (PS1 frame & 1); no 40-frame hold.
- Attack shout `rand()&1` (PS1 `&3==0`), cooldown `0x8015FEB0`; shapes in `FUN_801a1c74`.
- KO latch `DAT_8021fc30[p]`. Strike `FUN_801a2058` draws `rand` in every light branch. Gun Jack `FUN_801a1f74`: 0x706D, 0x705D, or 0x7099/0x7098 by `DAT_8021fd58&3`.
- Script start uses the same fields (+0x60, +0x62, +0xD6, +0xD8).

**Moves without a strike sound** (`confirmed`, data and harness). The strike of a hit comes only from the pose move's sound list (`+0x44` → `+0x24`, codes with nibble 1 or 7), except the KO impact, which is played without it. Of the 1,917 rows with damage and an active window, 33 have no such code. 20 of them have an exact twin on the PS1 (same damage and window, found through the slot pairs): all are silent there too except Eddy's flip, rows 2324–2326 (back + right kick, right kick), whose PS1 twins (rows 268–270 of his bank) have `0x6049, 0x7042`. The harness confirms the cabinet's silence: with a script of that input against a standing Paul, the program calls `FUN_801A0E2C` and the board's `FUN_801B0810` on the first kick's contact frame and on neither of the flip's. The other 13 rows have no PS1 twin (arcade-only or changed moves), so their intent is `unknown`; rows 2381–2383, a flip like Eddy's, are silent on both. Register entry [82](../code/game-bugs.md#arcade-world-ver-e1): the remake keeps the arcade's silence.

**Mapping for `SimEvents`.** Ids stay as they are; the code path changes. `Kind.SOUND` carries a PS1 code today (`sound_codes[id]`, with bank, voice and volume bits decoded in `AudioDirector.play_code`). For the arcade: `wave, param = table[id & 0xFFF]`, and a fixed voice per kind from the table above, where a new sound stops the voice's old one. `SOUND_AFTER_VOICE`, echoes and `_mokujin` go away, replaced by the H8 scripts' behaviour.

## 4. Effect objects

**Function map** (`confirmed`, read; PS1 names from `effect_objects.gd`):

| PS1 | Arcade | |
|---|---|---|
| `EffectsUpdate` 0x8006F8A8 | `FUN_801dc990` | dispatch types 0–7, 9–0xD only |
| `EffectAlloc` 0x8006F7DC / `FUN_8006F894` / `FUN_8006F840` / `FUN_8006F750` | `FUN_801dd0b0` / `FUN_801dd168` / `FUN_801dd110` / `FUN_801dd024` | pool **120** × 0xA0 at `0x802B6A58` (PS1 80) |
| round start `FUN_8006E8FC` | `FUN_801dc094` | same 8 glows |
| `FUN_8006E408` / `FUN_8006E3B8` / `FUN_8006E21C` | `FUN_801db180` / `FUN_801db110` / `FUN_801daf50` | aim, flat aim, direction |
| `PowerGlowJoints` 0x8006F5D8 | `FUN_801dc81c` | no Gon case |
| `EffectDescriptorSpawn` 0x8006F3DC | `FUN_801dc758` → `FUN_801dc414`, `FUN_801dc574` | codes 0x18, 0x19 at move `+0x32`, window `+0x30..+0x31` |
| `FUN_8006F248` burn | `FUN_801dc6c0` | 13 flames |
| hit objects (`FUN_80076F10`) | `FUN_801ad114` | same threshold 0x15, order, log codes 0x80–0x84 |
| `FUN_8004A954` replay | `FUN_801acce4` | `inferred`: it spawns the same types from a log record |
| `FUN_8006E848` (ramps) | `FUN_801dbc9c` | loads pages; no ramps |
| owner-active test | `FUN_801e0b3c` | |

Type routines: 0 `801dd17c`; 1 `801dd21c`; 2 `801dd67c`; 3 `801dda9c`; 4 `801dded0`; 5 `801de204`; 6 `801de520`; 7 `801dedf0`; 9 `801df394`; 10 `801df8c8`; 11 `801dfcc0`; 12 `801e02bc`; 13 `801e071c`.

**Absent types:** 8 (Gon's flame), 15 (ball), 16–18 (sound, done in H8), 19, 20 (gas).

**Tables and leads** (`confirmed` by the routines):

| Table | Arcade | Lead verdict |
|---|---|---|
| breath_offsets | `0x8020453C`, 2 × 2 SVECTOR | confirmed |
| cloud_offsets | `0x8020455C`, 2 | confirmed |
| glow_joints | `0x8017C4F4`, 8-byte records | confirmed |
| segment_cloud | `0x8017C8FC`, 21 | confirmed |
| segment_fireball | `0x8017C7D4`, 8 (1,1,1,0…) | lead refuted |
| burn_joints | `0x8017C4BC`, 13 × s32 | lead refuted |
| hand_offsets | **none**: the glow reads the joint's translation directly | lead refuted |
| flame_offsets, gas_offsets, gas_times, segment_flame, segment_gas | none: the types do not exist | leads refuted |
| light colours | `0x8017C4B8` fire, `0x8017C6C0` glow (via `FUN_80199f60`) | |
| ease sine | `0x8017CB78`, 8192 × {s16 sin, s16 cos}, 0x7FFF scale | new |
| dust ring offsets | `0x80175824`, 6, byte-identical to PS1 `0x8001E818` | new |

**Models and UV tables** (`confirmed`; models are quads, half-sizes in world units, PS1 in parentheses):

| Object | Model | Half-size | UV table, frames × cell | Page, CLUT (category 42 member) |
|---|---|---:|---|---|
| Spark, types 1–2 | `0x8017C63C` | 55 (55) | `0x8017C5F8`, 32 × 16 | 0 |
| Power spark, 12–13 | `0x8017C958` | 35 (35) | `0x8017C914`, 32 × 16 | 1 |
| Glow, 3 | `0x8017C6A0` | 120 (140) | `0x8017C65C`, 8 × 16 | 1 |
| Rise, 4 | `0x8017C6E4` | 60 (80) | `0x8017C6C4`, 16 (u step 32, v step 16) | 1 |
| Ember, 5 | `0x8017C744` | 30 (30) | `0x8017C704`, 32 × 16 | 1 |
| Fireball, 6 (A/B) | `0x8017C764`, `0x8017C784` | 432 square (345 × 432) | `0x8017C7A4` grow, `0x8017C7B4` loop, 8 × 64 | 4 |
| Burst | same | | `0x8017C7C4`, 8 × 32 | 5 |
| Smoke, 7 | `0x8017C7DC` | 48 (48) | `0x8017C7B4`, then `0x8017C7C4` | 4, then 5 |
| Floor fire, 9 | `0x8017C83C` | 256 (256) | `0x8017C7FC`, then `0x8017C81C`, 16 × 32 | 2, then 3 |
| Cloud, 10 | `0x8017C85C` | −192…192, −276…108 (same) | `0x8017C87C`, page per frame `0x8017C8A8`, 21 × 64 | dust set, CLUT of member 6 |
| Burn, 11 | `0x8017C764` | 432 (345) | `0x8017C7B4`, then `0x8017C7C4` | 4, then 5 |

**Differences from `effect_objects.gd`** (`confirmed`, read; none run yet):

- Fades are UV frames, not CLUT ramps: no rows 509/510. `o.clut` is fixed per phase, and the presentation must use frame tables.
- Optional spawns are fixed masks, not the live-count `_chance`: glow's ember `(rand&0xF)==0`; fireball's smoke `&0x3F`; floor fire `&0x7F`, a second draw whenever y is the floor (no `elif`, no `d` test); floor fire's and burn's smoke `&0x1F`. Fire light `&0xF` of a fresh draw. Smoke counts therefore differ in `rand` use.
- Spray counts: type 1 and 12 × 12 (PS1 6), type 2 and 13 × 30 (PS1 20), burn × 13 (PS1 10).
- Spark speed: `c + ((d−c)·((cos[a·0x7FF/b] + 0x7FFF)/2) >> 15)`, an ease from 1 to 0; PS1 goes 0.75 to 0.25. Spark frame index `(a·0x10 / (b>>1))`, 32 frames.
- Rise 16 frames (same); fireball burst 7 frames (PS1 8); smoke fade 8 (PS1 12); floor fire's fade 32 frames (PS1 16, same acceleration).
- Burn: after the follow phase one 16-frame burst (`-0x18000`), not 7 + 5.
- Fireball and cloud segments: flag 4 (PS1 flag 2), published each frame while set, side flag 0x10; records of 0x18 bytes at `0x802C6C70` / `0x802C77B0`. No display-buffer gating: the previous position is saved every frame.
- Cloud has no Doctor variant. Glow has no hand offset or True Ogre block.
- Replay reset by `DAT_8021f960`; end clear by `DAT_8021f964`, with `DAT_8021fcd0−3 < 5`.

**Effect pages** (`confirmed`, `FUN_801dbc9c`; extracted by `effect_pages.py` to `effects/page*.png` and checked by eye): **category 42 (0x2A)**, 7 compressed TIMs, 4-bit, zero rectangles in the TIM (the loader places them). CLUTs at `(0x200, member)`.

| Member | VRAM (x, y, texels) | Tpage variable | Look |
|---:|---|---|---|
| 0 | 0x3C0, 0, 128 × 64 | `0x8036EA5C` | spark dots |
| 1 | 0x3E0, 0, 128 × 64 | same page | glow, rise, ember |
| 2 | 0x3C0, 0x40, 256 × 64 | same | floor fire |
| 3 | 0x3C0, 0x80, 256 × 64 | same | floor fire fade |
| 4 | 0x380, 0, 256 × 256 | `0x8036EA60` | fireball |
| 5 | 0x3C0, 0xC0, 128 × 64 | `0x8036EA5C` | burst |
| 6 | CLUT only | | cloud palette |

The cloud has no page of its own. Its tpages `0x8036EA64`, `0x8036EA68` are (0x380, 0x300) and (0x3C0, 0x300), where the system dust flipbook sits (`0x801757F0` row 3, set 38, category 22). So cloud frames are dust frames 1, 3, 5, 7, 9–13, 15, 17–27 through member 6's CLUT (`effect_cloud.py`, `effects/cloud_strip.png`, purple as expected). Dust upload walk: 4 × 4 frames per 64-word column, then x + 0x40 (`FUN_801af068`).

**Pages, CLUTs and blending per phase** (`confirmed` by reading `FUN_801dbc9c` and the type routines' set-up). `LoadTPage(…, tp 0, abr 1, …)` makes the objects' two pages additive (`0x8036EA5C` at (0x3C0, 0), holding members 0–3 and 5; `0x8036EA60` at (0x380, 0), member 4); `GetTPage(0, 0, …)` makes the cloud's two abr 0, 50 %. The CLUT words `0x8036B9A4 + 4n` are member n's. Each type routine sets its primitives' page and CLUT once, with semi-transparency on and colour 0x80, so they follow the UV table a phase shows: spark member 0; power spark, glow, rise, ember member 1; the fireball's grow and loop (also smoke's and burn's first phase) the fireball page with member 4; the burst (also smoke's and burn's last) member 5; floor fire 2 and its fade 3; the cloud member 6, its page per frame (`0x8017C8A8`, an index into the tpage words from `0x8036EA5C`: 2 or 3). Frame cells are square: the routines add `0xF`, `0x1F` or `0x3F` to u and v (16 for the first five tables, 64 for grow, loop and cloud, 32 for burst and floor fire).

**In the remake** (`arcade_effect_objects.py`): the four pages side by side in one atlas of indices (`effects/arcade_object_page.png`, the dust frames where the upload walk puts them), the seven CLUTs (`arcade_object_palettes.png`), the models and the UV tables in `ArcadeEffectObjects.Book` order, each with its palette and blending, in the `objects` block of `effects/effects.json`. `EffectObjectsView` takes a table's own palette and blending when it names one (the arcade's objects have no `clut` or `tpage`). Checked by eye in the arcade build (True Ogre's fire breath, the big hit's sparks, the floor fire), not against MAME's frames.

**What `effects.py` takes from the PS1 disc, and its arcade source:**

| Today | Arcade source |
|---|---|
| Object page, palettes and ramps (`_object_drawing`, system VRAM) | category 42 members 0–5, CLUT member 6, dust set 38 |
| `OBJECT_MODELS`, `OBJECT_UV_TABLES`, `SPRITE_UV` | tables above; no `SPRITE_UV` needed |
| Light colour and frame count, per character | record `+0x14`, `+4` at `0x80175510`; identical to PS1 except charId 19 |
| Blending | record `+0xA` (dust 0 = half) |
| Dust ring `DUST_OFFSETS` | `0x80175824` |
| Costume key → flipbook | record per charId (README, Effect flipbooks) |
| Enbu flipbooks | `FUN_801ac974`: sets 10 and 4 |
| `BALL_GLOW_*`, ball | not needed: no ball type on the arcade |

### Effect logs of the replay

`confirmed` by the code. Where the PlayStation keeps one log (`FUN_8004A700`, 64 entries), the arcade keeps two, of 300 frame slots each (first entry in 24 bits, count in the top byte):

| | Flipbooks and hit objects | Dust rings |
|---|---|---|
| Reset | `FUN_801ADB1C` | `FUN_801AE50C` |
| Add (at most `limit − 1` per cycle of the frames) | `FUN_801ADB6C`, limit 0x29 | `FUN_801AE55C`, limit 0x15 |
| Entries | 40 × 0x18 at `0x80269190` | 20 × 0x10 at `0x8026F510` |
| Next frame | `FUN_801ADC64` | `FUN_801AE600` |
| Rewind by the frames played back | `FUN_801ADCE4` | `FUN_801AE680` |
| Play | `FUN_801ADD18` | `FUN_801AE6B4` |
| Keep with a fight | `FUN_801ADE80` | `FUN_801AE79C` |
| Restore | `FUN_801ADF88` | `FUN_801AE888` |

- An entry: the point (3 words), +0x10 pitch, +0x12 yaw, +0x14 damage (or a hit's direction in the three), +0x16 set, +0x17 index. Sets 0 and 1 are the fighters' flipbooks, set 2 the system's (the PlayStation's number is 3: the remake's `EffectLog.SYSTEM_SET` keeps that one).
- Index below 0x80 is a flipbook. The rest are `FUN_801ACCE4`'s objects: 0x80 sparks (`FUN_801DC118`), 0x81 spray (`FUN_801DC1CC`), 0x82 burn (`FUN_801DC6C0`, its point is uninitialised stack and not used), 0x83 and 0x84 the power glow's (`FUN_801DC274`, `FUN_801DC328`). Replaying them draws `rand` again, so the objects count for the CPU's decisions after a KO.
- A hit (`FUN_801AD114`) logs its system flipbook (`FUN_801AD0B8`), the attacker's flipbook from damage 0x15 (`FUN_801AD050`), then the objects. A move event 6 or 7 logs a character flipbook, 8–10 a system one, 4 a dust ring (`FUN_8018C5A4`); so does a landing.
- The frame's advance is skipped in camera phases 6 and 7 (`FUN_8018B57C`), and so is the drawing of both kinds. A replay frame plays them only on the even half frames (`0x8021FB38`); a held frame draws them without advancing.
- A kept fight stores its logs aligned on the frame being written: slot 299 is the live slot. On restore the playback starts at slot `299 − (count − 2)`, where `count` is the frames kept − 1; the poses start from slot 0 of their own ring. For 300 frames kept, the effects start two frames after the poses. Slots past the kept frames are whatever the ring held before, as the poses are (game-bugs.md #69).
- A scene's flipbook swap (`FUN_801ACA14`, event 4 of the demonstration, characters 4 and 9, sets 10 and 4 loaded by `FUN_801AC974`) points set 0 or 1 at another character's record; a scene's model change does not touch the flipbooks. `inferred` from the code alone: the attract's trace has no picture of them.

## 5. Gaps, ranked

1. **Effect object variant** (pool, masks, counts, ease, segments): see [the plan](../../remake-plan.md#m6-arcade-only-build) for its state. Needs golden traces.
2. **Move script index and other data links** into the arcade's move records (script index beyond 354): small, depends on the move-system report.
3. **Identify waves 0x44C–0x49B and sequence 0x14D**: small. The scenarios `sfx_high` and `sfx_fixed` run them; what they are is not known.

## Open

- A BGM rendered from the ROM has been compared with MAME by number, not judged by ear: the mix check covers 0x10, the register log all of them.
- Noise voices: `arcade_c352` shares one generator as MAME does, but is not in step with it to the sample, so the noise bands do not correlate.
- Rear C352 outputs: MAME does not route them; real cabinet wiring is unknown. The driver does write rear volumes (6522 of 31,564 writes non-zero).
- Effect objects were read, not run: no harness comparison. `FUN_801db4d4` (sprite draw), flag 0x20 and `FUN_80199f60` (light) are not compared with the PS1.
- Sound scripts from index 355 on: alignment with moves unverified. No RESULT music found on the arcade; absence is from the calls I read, not proof.
- Slots 2–5 of the H8 directory: record formats not documented.
- MAME's C352 semantics in `arcade_c352.py` come from a recollection of `c352.cpp`, checked only by the matches above.
