# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Two linked projects:

1. **Research into Tekken 3 (PlayStation)** — `docs/research/` documents every format and all game logic; `tools/research/` holds verified Python ports of the game's routines and the harnesses that prove them against the original code.
2. **A remake in Godot 4.7 (typed GDScript only)** — `remake/`, planned in `docs/remake-plan.md` (milestones M0–M5, architecture, decisions, bug policy). Gameplay must match the original frame for frame; visuals may be modernised.

Japan Rev.1 is the baseline: every address in the code and docs is its own. The game can be converted from any one release (Japan Rev.1, the original Japanese SLPS-01300, or USA): the others' executable and overlays are rebased onto Rev.1's layout first. A USA disc next to a Japanese one adds the English texts (one unified interface: Japan's structure, USA wording where it exists).

## Commands

The root `Makefile` wraps everything (`make help`). `GODOT` may point at the Godot 4.7 binary (default: `/Applications/Godot.app/...`, else `godot`).

```sh
make convert            # disc → remake/imported/ (python3 tools/remake_import/convert.py; CONVERT_ARGS='--image X.cue [--image Y.cue] ... [--arcade tekken3.zip]', one image per release, required; `--arcade` adds the arcade stages and character models from MAME's set)
make import             # Godot import of the converted assets (needed once before running/testing)
make run                # the game (godot --path remake)
make test               # every suite, ~3-4 min, parallel runners (JOBS=<n>)
make test-quick         # without trace comparisons (suites with `const SLOW := true`), ~10 s
make test-converter     # the converter's unittest suite (synthetic images, no game data)
make export-web-lite    # one build; export-<macos|windows|linux|web|android|ios>[-full|-nomovies|-lite], export = all
make serve-web          # serve remake/export/web-<WEB> on :8060
```

- Single test or suite: `tools/remake/run_tests.sh <substring>` matches suite file or test names (e.g. `run_tests.sh menu_exit`, `run_tests.sh test_settings`); a filtered run uses one runner.
- Golden traces for the tests: `python3 tools/research/export_traces.py` and `python3 tools/research/flow_trace.py [scenario ...] [--jobs 4]` (need the `work/` tree from `python3 tools/research/extract_work.py`). Suites whose inputs are missing are skipped, not failed.
- Useful game options after `--`: `--screenshot=<png> --frames=<n>` (save a frame and quit), `--pads=<file>` (pad script: `<steps> <pad1 hex> [<pad2 hex>]` per line), `--replay=<scenario>` (play a flow trace), `--no-movies`, `--seed=<n>`, `--speed=<n>`, `--fight`, `--m0`. Full list in `remake/README.md`. Pad bits (`platform/pad_state.gd`): Select 0x100, Start 0x800, Up 0x1000, Right 0x2000, Down 0x4000, Left 0x8000; △ 0x10, ○ 0x20, ✕ 0x40, □ 0x80.
- Research verifiers: `python3 tools/research/verify_<port>.py` run a Python port against the original routine in the Unicorn CPU harness (`tools/research/psxcpu.py`, MIPS + software GTE).

GDScript warnings for untyped declarations and unsafe access/calls are errors (`remake/project.godot`): always type locals and cast Variants (`as int`, typed `for x: T in`), or the scripts fail to load.

## Game data never enters git

Converted assets (`remake/imported/`), the extraction tree and decompiled code (`work/`), traces (`work/traces/`), builds (`remake/export/`) and texture-pack dumps contain Namco data: they are git-ignored and must never be committed or published. The repository may only hold the project's own code, docs and generic interface wording (e.g. `remake/content/texts_en.json`, `remake/app/translations.csv`). Names, credits, move lists, pictures and anything else creative come from the discs through the converter only.

## Remake architecture (`remake/`)

Layers, dependencies pointing down only:

- `core/` — deterministic 60 Hz simulation in integers (4096 angle units per turn, 4.12 fixed point, GTE rounding in `core/math`). Plain `RefCounted` state, **no Nodes, scene tree or autoloads**. `GameFlow` (`core/game/game_flow.gd`) is the whole game's state machine (the original's game states and sub-states: boot, title, menus, select, VS, fight, results, ranking, ending/Theater, loader); `FightSimulation` runs one fight in `FightFrame` order. Output leaves the sim only as per-frame `SimEvents` (sounds, music, effects, vibration, HUD messages). `RuleSet` holds the Gameplay-fix flags (each named after its `game-bugs.md` entry; code reads named booleans).
- `content/` — loaders for `res://imported/` (JSON, gzip `*.gz` via `DataFile`/`JsonFile`, motion banks baked per frame, models). `GameRam` exposes the executable/overlay images by game address so screens read the game's own tables and strings; `TextLocale` swaps strings for English per memory block.
- `presentation/` — views that read the sim after each step and consume its events: fighters (GPU skinning; seam corners blend two part-local positions, so meshes are not glTF), stages, effects, camera rig, HUD, 2D screens drawn with the game's own pictures/fonts in the 368 × 480 layout (`PsxCanvas`/`ScreenCanvas` transcribe the Python draw ports), audio, movies, settings screen, touch controls, `RenderQuality` presets and `TexturePacks`.
- `platform/` — autoloads `Assets` (asset catalog + manifest groups: music, movies, usa), `Pads` (`InputRouter`: devices join on first press; keyboard layouts, pads, touch), `Settings` (`user://settings.json`).
- `app/` — `game.gd`/`game.tscn` wires `GameFlow` to the views, audio, save file (`user://progress.json`), settings and movies; renders interpolate between sim steps.

The converter (`tools/remake_import/`, one module per asset kind, `convert.py` entry) writes only what the remake uses straight to `remake/imported/` (the single copy; `Output.prune()` deletes stale files). There is no in-game importer. Lite builds exclude `imported/music` and `imported/movies` by export filters; nomovies builds exclude only `imported/movies`.

- Discs: the images are given explicitly (`--image`, one per release; no search), `disc_image.py` opens cue sheets (compressed tracks found by name), raw/ECM/ISO data tracks and CHDs; `common.Disc.open` identifies the release (`common.RELEASES`: exe/BNS/XAS paths, BNS index format, overlay slots). Converter modules read `disc.canonical()` by Rev.1 addresses only.
- Layouts: `layout.py` makes `layouts/<release>.json` from Rev.1 plus the other disc (`make layouts LAYOUT_ARGS='--image <Rev.1> --image <other>'`; numbers only: segments, pointer relocations, text pairs, hashes of the release's blocks) and rebases that release's images with it. Objects whose size differs (picture archives, system textures) are read from the release's own images (`Disc.source`, `Disc.images`, `Disc.system_textures`); texts too long for Rev.1's place are kept aside (`Disc.strings` → `screens/ram.json` "strings", read first by `GameRam`). Structural differences a layout cannot find by itself go into `layout.EXTRAS`. After changing it, compare conversions from each disc (`imported/` trees) with the Rev.1 one: only the known release differences may remain.
- `manifest.json` records `source`; converted from the USA disc there are no Japanese texts (`Assets.japanese_texts()`), and English is forced.

## Faithfulness and verification

- Remake code is idiomatic, written from the documented rules — not a line-by-line port — and proven equal by golden traces: tests replay the traces' inputs through `core` and compare state field by field every frame (fights from the game's own `FightMain` in `tools/research/fight_harness.py`, the whole game from boot via `flow_trace.py`).
- Must match: everything in `core` and screen flow/timing. May differ: pixels, shading, effects' look, UI layout details, audio mixing, loading times.
- Original bugs: every defect found goes into `docs/research/code/game-bugs.md` (location, original behaviour, effect, fix) **and** is classified in `docs/remake-plan.md#original-bugs` in the same step. Gameplay-affecting bugs are reproduced by default and fixed together by the single "Gameplay fixes" option; cosmetic/latent ones are not reproduced. Python ports stay bit-exact (fixes live in the register, not the ports).

## Research workflow

- `work/` (from `tools/research/extract_work.py`): per release `exe.bin`, BNS records, Ghidra project `work/ghidra/proj/T3`, decompiled C in `work/decomp/*.c` (search `// ===== <Name> @ <addr>`). EXE address → file offset: `addr − 0x80010000 + 0x800`. Mode overlays load at `0x800B0A10`, screen overlays at `0x800B9378` (USA: `0x800B0548` / `0x800B8D58`).
- Symbol names: `tools/ghidra/symbols.txt`; re-annotate with `sh work/ghidra/annotate_all.sh`. Ghidra's decompile is sometimes wrong for overlays (merged functions, folded tables): port from capstone disassembly then.
- Verify semantics by running the original routine in the harness before documenting; mark claims `confirmed` / `inferred` / `unknown` with their source (rules in `docs/research/README.md`).

## Conventions

- Docs, code comments and user-facing strings in English; remake UI strings go through `app/translations.csv` (EN/JA).
- Logging through `Log` (`platform/log.gd`) in GDScript and `logging` in Python, not `print`.
- Deferred work is marked `TODO:` in code and listed in the milestone's status in `docs/remake-plan.md`.
- Keep `remake/README.md` and the relevant docs in step when behaviour they describe changes.
