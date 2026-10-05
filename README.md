# Tekken 3 Remake

A remake of **Tekken 3** for the PlayStation, built in [Godot 4.7](https://godotengine.org) from a
study of the original game.

The fights, the CPU, the modes, the unlocks and the screen flow are rebuilt from the original
code's documented rules and checked frame by frame against the original running in an emulated
CPU. The graphics are modernised: shadows, bloom, smooth textures, any window shape, high frame
rates. The remake runs on macOS, Windows, Linux, the web, Android and iOS.

**No game data is included.** The remake uses your own copy of the game: a converter reads the
disc image and writes the models, stages, sounds, music and movies the remake uses into
`remake/imported/`. That folder, and every build made with it, contains Namco's data: build it for
yourself from your own disc image and do not publish or share it (see [Legal](#legal)).

## What is in the game

The complete console game:

- Arcade with the Ogre scene, True Ogre, endings and the staff roll.
- VS, Team Battle, Time Attack, Survival and Practice.
- Tekken Ball and Tekken Force.
- Options with records, key configuration and a memory card saved to a file.
- The ranking with name entry, Theater, and the attract sequence with its demonstration.
- Every character, costume and unlock.

Additions of the remake:

- **Gameplay fixes**: an option that fixes the original's gameplay bugs. Off by default.
- **Game texts**: the USA release's English wording, or the Japanese release's texts.
- **Graphics presets, crisp or smooth textures, and texture packs**: HD replacements of the
  fighters, stages and floors.
- **Controllers**: gamepads (including DualShock 4 and DualSense, with vibration), keyboard, and
  touch controls on phones and tablets.

## What you need

- **A game disc image.** Any one of these releases is enough:
  - *Tekken 3 (Japan) (Rev 1)* (SLPS-91202, the PlayStation the Best re-release): the release the
    remake is built on.
  - *Tekken 3 (Japan)*, the original pressing (SLPS-01300): the same game with a few differences of
    its own (see below).
  - *Tekken 3 (USA)* (SLUS-00402): the whole game in English.

  Both Japanese pressings carry `SLPS_013.00` as their executable; the converter tells them apart by
  their contents.

  With a Japanese disc, a USA disc next to it adds the English names, move lists, credits and
  pictures with text. Without it the English menus still work (generic wording) and the rest stays
  Japanese.

  Images may be `.cue` sheets with their tracks (tracks compressed as `.ecm`, `.ape`, `.flac` or
  `.wav` are found under the sheet's names), single data tracks (`.bin`, `.ecm`), `.iso` files
  (without music and movies: an ISO does not keep them) or `.chd` files (these need MAME's
  `chdman`).
- **The arcade ROM set** (optional): MAME's `tekken3.zip` (World ver. E1). With `--arcade` the
  converter adds the arcade version's stage scenes, skies and floors (stages 0–12), which the remake
  draws instead of the PlayStation's backdrops (the *Stage backdrops* setting switches back), and
  the arcade's character models for costume slots 0–40. It does not replace the disc image: the
  game itself still comes from a disc.
- **Python 3** with NumPy and Pillow, for the converter (and xxhash to convert DuckStation
  texture packs, `tools/remake/texture_pack.py import-duckstation`):

  ```sh
  python3 -m pip install numpy pillow xxhash
  ```

- **Godot 4.7** (standard build, not .NET). On macOS the Makefile finds
  `/Applications/Godot.app`; elsewhere put `godot` on the `PATH` or set `GODOT=/path/to/godot`.
  - To make builds, also install Godot's export templates (Editor → Manage Export Templates).
  - Android builds also need the Android SDK and a JDK set up in Godot's editor settings.
  - iOS builds are exported as an Xcode project that you sign and build in Xcode.
- **FFmpeg** with the Vorbis and Theora encoders (optional). It converts the music to Ogg Vorbis and
  the movies to Ogg Theora. Without it the music becomes WAV and the movies JPEG frames, which is
  larger but works. Audio tracks compressed as `.ape` or `.flac` need FFmpeg in any case.

The converter reads the disc images you give it with `--image`, one per release, wherever they
are: a `.cue` sheet (tracks compressed as `.ecm`, `.ape`, `.flac` or `.wav` are found under the
sheet's names), a `.chd` (needs MAME's `chdman`) or a lone data track (`.bin`, `.ecm`, `.iso`; an
ISO has no music and movies). It tells the releases apart itself and converts the game from Japan
Rev.1 if given, else from the original Japanese disc, else from the USA disc. A USA disc given
with a Japanese one adds its English: the move lists, names, credits and pictures with text. Disc
images are git-ignored.

The original Japanese release differs from Rev.1 in a few places the remake keeps as they are on
that disc: some pictures and credits have typos that Rev.1 corrected and two Theater movies have
other titles. That disc has no stage colours for the band drawn over the stage when a menu
returns to it (a Rev.1 addition), so the remake draws it black.

## Quick start

```sh
make convert CONVERT_ARGS='--image "/path/to/Tekken 3 (Japan) (Rev 1).cue"'   # into remake/imported/ (a few minutes)
make import     # let Godot import the converted pictures and sounds (once)
make run        # play
```

To run from the editor instead, open the `remake/` folder in Godot 4.7 and press Play.

`make help` lists every command. The images and options of the conversion go through `CONVERT_ARGS`:

```sh
make convert CONVERT_ARGS='--image "/path/to/Tekken 3 (Japan) (Rev 1).cue" --image "/path/to/Tekken 3 (USA).cue"'
make convert CONVERT_ARGS='--image "/path/to/Tekken 3 (Japan) (Rev 1).cue"'   # without the USA English
make convert CONVERT_ARGS='--image "/path/to/Tekken 3 (USA).cue"'             # the game from the USA disc
make convert-nomovies CONVERT_ARGS='--image ...'   # without movies, music kept
make convert-lite CONVERT_ARGS='--image ...'   # without music and movies (much smaller)
make convert CONVERT_ARGS='--image "/path/to/Tekken 3 (Japan) (Rev 1).cue" --arcade /path/to/tekken3.zip'   # plus the arcade stages and models
```

Run the conversion again after updating the project: it rewrites only what changed and removes
files it no longer produces.

## Controls

Each gamepad, and each half of the keyboard, joins the game on its first press. Touch controls
appear on touch screens and belong to player 1.

| Action | Pad | Keyboard, player 1 | Keyboard, player 2 |
|---|---|---|---|
| Move | D-pad or left stick | W A S D | arrow keys |
| Left punch / right punch | □ / △ | R / T | U / I |
| Left kick / right kick | ✕ / ○ | F / G | J / K |
| Start / Select | Start / Select | Space / Q | Enter / Backspace |
| Shoulder buttons | L1 R1 L2 R2 | Z X C V | O P L ; |

- **Esc** pauses a fight, skips a movie, and goes back in the menus.
- ✕ and ○ also skip what Start skips: the start-up, the attract sequence, replays and movies.
- A click or tap is player 1's Start.
- **F3** shows the frame rate.

The game's own key configuration (in OPTIONS) works as in the original.

## Settings

Press **Select** on the main menu (Esc, Q or Backspace; on touch screens, the gear at the top left)
to open the remake's settings:

- **Gameplay fixes**: fix the original's gameplay bugs, from the next mode started.
- **Game texts**: English (USA) or Japanese (English only when converted from the USA disc).
- **Interface language**: for the remake's own screens.
- **Memory card**: slot 1 or 2, two separate saves (progress, records and game options); switching
  loads the other card's progress.
- **Graphics preset**, **Textures** (smooth or crisp), **Texture pack** and **Frame interpolation**.
- **Beyond the scene**: what fills a window wider or taller than the original screen.
- **Volumes** for music, effects, voices and system sounds.
- **Vibration**, **Touch controls** (auto, on or off) and **Touch macros** (buttons for two limbs at
  once, such as throws).

Settings are kept in the user data folder (`settings.json`). Game progress is kept separately
(`progress.json`, the second card `progress2.json`) and is saved as the original saves to its memory
card, with AUTO SAVE on for a new save and the game options saved on leaving OPTIONS.

## Texture packs

A texture pack replaces the pictures of the fighters, stage panoramas, floors and Tekken Force /
Tekken Ball backdrops with pictures of any resolution.

```sh
python3 tools/remake/texture_pack.py dump my_pack     # the original pictures, named by their keys
# edit or upscale the PNGs, keeping their aspect ratio and layout
python3 tools/remake/texture_pack.py check my_pack    # report unknown keys and changed aspect ratios
```

Copy the folder to `texture_packs/` in the game's user data folder, then choose it under Settings →
Texture pack. The user data folder is `~/Library/Application Support/Godot/app_userdata/Tekken 3
Remake/` on macOS, `%APPDATA%\Godot\app_userdata\Tekken 3 Remake\` on Windows and
`~/.local/share/godot/app_userdata/Tekken 3 Remake/` on Linux. A pack made from the originals
contains game data: keep it private.

## Builds

Every platform has a **full** build, a **nomovies** build (music, no movies) and a **lite** build (neither). Builds are
written to `remake/export/`, and the script prints each one's size.

```sh
make export                # every platform, all three builds
make export-web-lite       # one build: export-<macos|windows|linux|web|android|ios>[-full|-nomovies|-lite]
make export-android        # all builds of one platform
make serve-web             # try the web build at http://localhost:8060 (WEB=full or WEB=nomovies for the others)
make clean-export
```

Notes by platform:

- **Web**: a single-threaded build for a static web server of your own (local or private, not a
  public host). It waits for a click or key before it starts, so the browser lets it play sound.
- **Android**: an APK for arm64, signed with the keystore in
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH` / `_USER` / `_PASSWORD` (by default Godot's debug keystore,
  for installing on your own device).
- **iOS**: an Xcode project. Set your team in Xcode, then build and sign there.

Builds contain the converted game data. They are for your own devices only.

## Development

- `remake/README.md`: the remake's layout, all command-line options and the tests.
- `docs/remake-plan.md`: the plan, architecture and decisions.
- `docs/research/`: the documentation of the original game: file formats, fight logic,
  AI, camera, modes and the register of the original's bugs.
- `CLAUDE.md`: a condensed guide to the repository.

```sh
make test-quick       # the fast tests (seconds)
make test             # every test, including the frame-by-frame comparisons with the original
make test-converter   # the converter's own tests (unittest; no game data needed)
```

The comparisons with the original need golden traces made from the research tools
(`tools/research/`); without them those suites are skipped.

## Legal

Tekken 3 is © Bandai Namco Entertainment. This project is an unofficial fan work, not affiliated
with or endorsed by Bandai Namco.

**The project's code and documentation** are licensed under the
[PolyForm Noncommercial License 1.0.0](LICENSE.md) (SPDX: `PolyForm-Noncommercial-1.0.0`) from
commit `31e937c` (5 October 2026) on: any noncommercial use, including by noncommercial
organizations, with modification and redistribution under its terms; no commercial use. Revisions
before that commit were released under the MIT License, and stay under it.

**The game is not covered by that licence.** Its data, and any build that contains it, stay
Bandai Namco's; so do the game texts the repository quotes, such as the USA release's interface
wording in `remake/content/texts_en.json` and the strings cited in `docs/research/`. Converted data
and builds may not be distributed: use the remake only with a copy of the game you own, and keep
what it makes private. This follows from the game's copyright; it is not an extra term of the
code's licence.
