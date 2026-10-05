# Tekken 3 PSX research

This documentation reconstructs the contents and behavior of the PlayStation disc release of Tekken 3 from the supplied images. Verified findings will inform a modern-engine remake and asset converters. Claims come from the images and reproducible measurements; interpretations based on filenames or older notes are labeled separately.

Research documentation is maintained in English. The remake built on it is planned in [remake-plan.md](../remake-plan.md). The [external research ledger](external-research.md) records published leads and the exact local verification boundary for each.

## Working rules

- Record the source artifact, exact release, SHA-1/SHA-256 or sector address, and verification method for each finding.
- Distinguish `confirmed` (directly checked against an image or code), `inferred` (strong structural interpretation), and `unknown` (insufficient evidence).
- Verify semantics by executing the original routines in the CPU harness ([tooling](tooling.md)) wherever an independent reimplementation exists; claims based only on reading decompiled code are marked as such.
- Compare Japan and USA by resource ID and content. Japanese text alone does not establish extra modes, and file size alone does not establish completeness.
- Preserve the source path and parent-artifact hash for each decoded or converted file.

## Disc baseline

`Tekken 3 (Japan) (Rev 1)` is the main Japanese research image. Its data-track SHA-1 matches the published Japan Rev.1 entry, and `SYSTEM.CNF` boots `SLPS_013.00`. The USA image supplies English text, localized code, and regional comparisons. This choice does not establish that the Japanese release contains more gameplay content.

The original `Tekken 3 (J) [SLPS-01300]` is also included. Its ECM Track 1 is read through virtual sectors without writing an unpacked image; APE audio was decoded through a pipe for bytewise PCM comparison. Original Japan and Rev.1 have identical XAS user payloads and CDDA. Of 303 BNS resources, 293 are byte-identical; all 10 differences have `.ovl` filenames. The original BNS index has 12-byte rows with pointers to EXE filenames, while Rev.1 has 8-byte pairs.

See the [disc catalog](disc-variants.md), [CD layout](formats/disc-layout.md), and [complete original BNS filename index](bns-original-index.md) for sizes, hashes, addresses, and layout differences.

## Method

Formats are now established from the game code, not only from byte patterns. The Japan Rev.1 EXE and all ten overlays are analysed in Ghidra with PsyQ signatures and project annotations, and individual game routines are executed in a CPU/GTE harness to compare their output with independent Python decoders. See [tooling](tooling.md).

## Format register

| Area | Status | Established facts |
|---|---|---|
| CD/CUE, ISO 9660, XA Mode 2 | `confirmed` | Track 1 uses raw 2,352-byte sectors; Form 1 user data starts at offset 24 and occupies 2,048 bytes. |
| ISO entries mapped onto CDDA tracks | `confirmed` | `TEKKEN3.DA` and `TEKKEN3.DMY` point to INDEX 01 of Tracks 2 and 3; Track 2 is music track 4 (located through the TOC), Track 3 is unused silence. |
| EXE, overlays, main loop, BNS loading | `confirmed` | [Memory map](code/memory-map.md): mode overlays load at `0x800B0A10`, screen overlays at `0x800B9378`; logical resource IDs; per-costume resource loading and ARC member handling. |
| `TEKKEN3.BNS` | `confirmed` | Original Japan: 12-byte rows with filename pointers (unused by the loader); Rev.1/USA: 8-byte rows. Logical IDs map through `0x80098954`. Every record is classified: overlays, VS-screen images, stage archives and panoramas, character groups, motion banks, attract-demo models ([namco-banks.md](formats/namco-banks.md)). |
| `TEKKEN3.XAS` | `confirmed` | 50 XA music descriptors; 22 STR movies (MDEC version 3, XA audio channel 1) parsed by `inspect_xas.py`, movie table in `ending.ovl` ([sound-and-video.md](formats/sound-and-video.md)). |
| `.kmd` character models | `confirmed` | [3dmk-models.md](formats/3dmk-models.md): **rows start at `0x10`** (earlier docs were off by 8 bytes); vertex/normal/face/texture blocks; 22 draw parts, hierarchy, seam blending — verified slot-exact against the game renderer for all 52 models. |
| Animation streams | `confirmed` | [animation.md](formats/animation.md): 49 channels, per-channel keyed B-spline; bit-exact against the game for 314,290 frames in all 22 banks. |
| Pose pipeline (FK + IK) | `confirmed` | [animation.md](formats/animation.md#pose-to-matrices): integer port `pose.py` bit-exact against `PoseBuildMatrices` (every frame of all banks). |
| `divmot*.bin` motion banks | `confirmed` layout | [divmot-banks.md](formats/divmot-banks.md): header, all move-row fields, branch rows, sound/event lists, camera lists, attack descriptors, AI hint byte. |
| Fighter record | `confirmed` | [fighter.md](code/fighter.md): ~240 named fields (every offset accessed through a typed fighter pointer), generated from `fighter_fields.tsv`; all other bytes are handled at their raw offsets by the bit-exact ports. |
| Move system | `confirmed` from code | [moves.md](code/moves.md): input, motion sequences, branch conditions, transition codes, frame advance, tracking, root motion, motion blending, frame events. |
| Combat | `confirmed` from code | [combat.md](code/combat.md): attack/guard encoding, collision shapes, contact, damage, reactions, push-back, launches and juggles, knock-down recovery, throws, reversals, body separation. |
| Fight frame, round flow | `confirmed` from code | [fight-frame.md](code/fight-frame.md). |
| HUD and text | `confirmed` from code | [hud.md](code/hud.md): screen mode, health bars and their animation, timer, round marks, name plates, mode lines, round messages with timing and voices, text engine. |
| Sound, music, vibration | `confirmed` | [sound.md](code/sound.md): sound code format, VAB slots, playback rate (bit-exact), voices, music track table, DualShock scripts. |
| Camera | `confirmed`; fight camera and streams bit-exact | [camera.md](code/camera.md): phases, director states, blending, yaw spring, framing, choice lists, presets, camera streams, hit, intro and round-end cameras, shake, floor. |
| Stages | `confirmed` layout | [stages.md](code/stages.md): stage resources, clear colours, panorama grid, floor descriptor and tile entries, spotlight floors, True Ogre arena; the Tekken Force and Tekken Ball tile-map panoramas are ported (`force_sim.py`, `ball_sim.py`). |
| Effects | `confirmed` from code | [effects.md](code/effects.md): flipbook ring (system and character flipbooks), hit effect selection, all 21 effect object types with textures, palettes, motion and lifetimes, projectile hit segments, dynamic light. |
| CPU AI | `confirmed`, ported and verified (`ai_sim.py`, `ai_update.py`) | [ai.md](code/ai.md): record layout, candidates and filters, difficulty words, adaptive difficulty, per-frame decision order, reactions, evasion, attack choice, movement, character hooks, Tekken Ball / Tekken Force behaviour, dead follow-up code. |
| Function index | `confirmed` | [function-index.md](code/function-index.md): the roles of the overlay routines not covered by other documents (helpers, library copies, set-up code); [resident-functions.md](code/resident-functions.md): all 444 remaining unnamed resident routines, each with its documented caller subsystem (effect type for effect helpers), library calls and a role note. |
| Game bugs and quirks | `confirmed` | [game-bugs.md](code/game-bugs.md): register of original defects (camera, CPU, hit tests, arithmetic overflows, dead code) with suggested fixes for an optional fixed mode. |
| USA differences | `confirmed` | [usa-version.md](code/usa-version.md): code and text differences between Japan Rev.1 and USA (move lists, memory card title, one announcer call, practice menu, record pages, Theater captions). |
| Modes, overlays, unlocks | `confirmed` | [modes.md](code/modes.md): the 20 game states, overlay slots, modes 0–8, arcade ladder, survival/team rules, match flow (continue, game over, challenger, the Ogre scene), unlock schedule, main menu, options, select screens, result screens, ranking and name entry, arcade ending and staff roll, Theater, records, save block; flow and screen logic ported and verified (`screens_sim.py`), the 2D screens and HUD ported with their drawing and verified byte for byte, texts placed by 3D projection included (`draw_sim.py`, `menu_sim.py`, `select_sim.py`, `practice_sim.py`, `force_sim.py`, `theater_sim.py`, `command_list_sim.py`, `movie_captions.py`); the Tekken Force level runner, the Ogre scene (`ogre_scene_sim.py`) and the 3D drawing of Tekken Ball and the Force/Ball panoramas (`ball_sim.py`, `force_sim.py`, with the PsyQ GTE library in `projection_sim.py`). |
| STR movies | `confirmed` inventory | [sound-and-video.md](formats/sound-and-video.md#str-movies): 22 version-3 movies, movie table, ending mapping. |
| ARC member 3 `TK3psSDW` | `confirmed` | [Shadow mesh](formats/pssdw-member.md). |
| System textures | `confirmed` | [system-textures.md](formats/system-textures.md): the 127 compressed TIMs inside the executable (fonts, HUD, portraits, effect pages, palettes); character ARC member 1 = per-character hit-effect flipbook. |
| Overlay images | `confirmed` | [overlay-images.md](formats/overlay-images.md): the pictures inside the overlays (title, select, result, ranking, Theater, staff roll, Tekken Force keys), 311 plain TIMs and 17 archives, and which are copies of other data. |
| ARC member 0 textures | `confirmed` placement | Uploaded at TIM rectangle + `(384, 256·player)`, CLUT + `(0, 504 + 4·player)`. |
| ARC member 4 move text | `confirmed` | Japanese and USA encodings from both executables' renderers ([arc-archives.md](formats/arc-archives.md#move-text-rendering-japan-rev1)); `move_text.py` decodes every USA command list into Tekken notation. |
| `.tia` / `.tiz` | `confirmed` | Compression and TIM envelopes verified; used by the pre-fight VS screen (backgrounds `makuma00/01`, portraits `face_b00–21`), [compressed-tim.md](formats/compressed-tim.md#runtime-use). |
| Stage `.tmd` | `confirmed` layout | Packets, texture lookup and grid cell size verified. |
| Arcade version (System 12) | `confirmed` layout and sky, other drawing from code | [arcade/README.md](arcade/README.md): MAME set, ROM layout, program LZ and boot, file table and categories, 24-row `3DMK` models; [arcade/stages.md](arcade/stages.md): polygonal stage scenes (standard TMD, 256-object grid, scale 10 about the fighters' midpoint), tiled sky panoramas (the arcade's drawing routine run in the CPU harness, `verify_arcade_sky.py`), 2,500-unit floor, its descriptors and tile split rule, the fire-bowl texture animation. |
| VAB `.vh/.vb` | `confirmed` | Tables, ADPCM decoding and playback rate verified. |

## Research priorities

None open. The CPU (including Tekken Ball) is ported and verified ([ai.md](code/ai.md)).

**Out of scope (by decision):**

- Runs in a full PlayStation emulator or on the console. All verification runs the game's own machine code in the CPU harness (`tools/research/psxcpu.py`, Unicorn with a software GTE), including end-to-end chains such as `check_force_manual_target.py`. None of the verified routines depends on BIOS or hardware timing.
- The one BIOS-dependent value: `$s7` at program start, which the Tekken Ball ball physics reuses ([game-bugs.md](code/game-bugs.md) #44). It affects only the ball's displayed spin; the recommended remake behaviour is recorded there.

## Source notes in this checkout

- `Tek3Ex/README.md` describes a `TEKKEN3.BNS` extraction/repacking utility.
- `Tek3Ex/useful-stuff/FileMap.md` is a preliminary Japanese resource map and labels itself incomplete.
- `Tek3Ex/Tek3Ex.cpp` shows the 8-byte LBA/size pairs and `0x800` BNS alignment used for its supported release.
- [Tekken3Recompiled MODDING.md](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/MODDING.md) studies the exact USA `SLUS-00402` release. Its Track 1 and EXE hashes match the local image. This is an independent map, not proof of every resource's meaning.
- [Tekken3Recompiled MODEL_MAP.md](https://github.com/FishB0nes98/Tekken3Recompiled/blob/main/tools/MODEL_MAP.md) describes the outer `3DMK` envelope and leaves uncertain fields unresolved.
- The [Sony PSY-Q Sound Artist Tool manual](https://psx.arthus.net/sdk/Psy-Q/DOCS/Devrefs/Sound20.pdf) describes platform VAB/VH/VB, SEQ/SEP, VAG, and XA structures; it does not establish that Tekken 3 uses each one.

These are research sources, not guarantees of complete or correct semantics.
