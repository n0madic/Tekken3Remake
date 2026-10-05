# USA version differences

The remake follows Japan Rev.1 (`SLPS_013.00`) and takes its English text from the USA release (`SLUS_004.02`). This document lists every difference between the two found by comparing code and text. Addresses are Japan Rev.1 unless marked USA.

Status: `confirmed`.

- **Code**: `tools/research/compare_exe_code.py` normalises instructions (`j`/`jal` targets and the immediates of loads, stores and `addiu`/`ori` dropped) and looks every Japan Rev.1 function up in the USA code. With `--overlay NAME` it compares an overlay.
- **Text**: the English strings of the executable and of all overlays were compared as sets.

## Executable

763 of 770 game functions are instruction-for-instruction identical. The others:

| Function | Difference |
|---|---|
| `MoveTextDraw` `0x80077A0C` (USA `0x80077724`), `FighterCopyMoveText` `0x80078974`, `FUN_800789E4`, `FUN_80079610`, `FUN_80079664` | The in-fight command list uses another text encoding and a shared glyph atlas ([arc-archives.md](../formats/arc-archives.md#move-text-rendering-japan-rev1)). |
| `FUN_8004BF58` (USA `FUN_8004BCC0`) | The memory card file title: English lines and different progress rules ([modes.md](modes.md#memory-card-file)). |
| `FUN_8003DCE0` (USA `FUN_8003DA8C`) | Round-start announcer. Japan plays voice `0x103B` at the start of every team-battle and survival round (frame 61 of the first round, else frame 1); the USA version says nothing there. The round-number voice and the final `0x103C` are the same. |

Other executable differences are data:

- the card file name `BASLUS-00402TEKKEN-3`;
- the disc paths `\TEKKEN3\TEKKEN3.BNS;1` and `\TEKKEN3\TEKKEN3.XAS;1` (the USA files are in a directory);
- `DOCTOR B.` instead of `DOCTOR.B.`;
- the license string;
- `SOLD OUT` replaced by `RULES` and `SELECTED`.

## Overlays

| Overlay | Code | Text |
|---|---|---|
| `arcade`, `force`, `enbu`, `result` | identical | Force level names `A BACK STREET`, `THE WILDS`, `IN THE DARK`, `UNDER THE GROUND` become `BACKSTREETS`, `BADLANDS`, `DARKNESS`, `UNDERGROUND`; `LIFE UP!` becomes `+LIFE!`; `CHALLENGE FINAL STAGE!!` becomes `FINAL STAGE CHALLENGE!!`; result titles gain a plural (`SURVIVAL RESULTS`). |
| `select` | identical | — |
| `volley` | one function differs (`0x800B4090`) | — |
| `practice` | five functions differ (`0x800B3808`, `0x800B5978`, `0x800B5ED4`, `0x800B68A0`, `0x800B7C84`) | The practice menu loses KEY DISPLAY; FREEZE SIGNAL becomes HIT ANALYSIS, REPLAY SETTINGS becomes COMBO REPLAY, FREE becomes 1P FREESTYLE, TECH ROLL becomes QUICK ROLL. |
| `title` | the record pages (`0x800DFE40`, `0x800E0140`, `0x800E0430`, `0x800E0938`) | ARRANGE becomes REMIXED, WINNING AVERAGE DATA becomes WIN AVERAGE DATA, CHARACTERS DATA becomes CHARACTER USAGE DATA, `NO TEKKEN 3 FILE!`. |
| `ranking` | three record page functions | as `title` |
| `ending` | the Theater menus and disc check (Japan `0x80110008`, `0x801104B0`, `0x80110A58`, `0x801112DC`, `0x8010E8C0`) | `TEKKEN n ARCADE MUSIC` / `REMIXED MUSIC` instead of `ARCADE SOUND` / `ARRANGE SOUND`; the help strips and disc messages are text (`INSERT TEKKEN 3 DISC`, `INSERT TEKKEN 1, 2, OR 3 DISC`, `TEKKEN SERIES MUSIC PLAYER`, `TEKKEN SERIES MOVIE THEATER`) instead of pictures; the Tekken 3 disc is recognised by `\TEKKEN3\SLUS_004.02;1`. The help texts come from a string table (USA `0x8010E1E4`): `TEKKEN SERIES MOVIE THEATER`, `TEKKEN SERIES MUSIC PLAYER`, the two disc messages, `RETURN TO THEATER MODE SCREEN`, `MUSIC PLAYER`, `SELECT MUSIC MODE`, `RETURN TO TITLE SCREEN`. The staff roll has USA localisation credits. |

The Japanese-only text is the memory card titles (above) and the move lists; everything else on screen is English in both releases.

## Details of the code differences

Found while the remake took over the English texts (M5). USA overlays load at `0x800B0548` (mode slot) and `0x800B8D58` (screen slot).

- **`practice`**: the row tables of the pause pages (`0x800B0A10` in Japan: 12 bytes per page) have 8 bytes per page in the USA release, without KEY DISPLAY (item 5): FREE `0, 7, 13, 2, 1, 3, 4, 14`, VS CPU `0, 7, 9, 10, 1, 3, 4, 14`, COMBO TRAINING as in Japan. The key display (`FUN_800B7C84`, USA `0x800B7648`) is drawn only while the guide is on (`S+0x87`) and outside FREE (`S+0x77 ≠ 0`). The recording prompt `PLAY(SEL) REC(DW+SEL)` becomes the third line of the QUICK ROLL table (`PLAY(SEL) REC(d+SEL)`, drawn by the QUICK ROLL routine with a down arrow at (9, 0x17B), colour 7), then `P` again in colour 5 at column 1, line 21.
- **`volley`** (`0x800B4090`, USA `0x800B3BC4`): the HOW TO page becomes RULES with a wider picture: the 256 × 204 picture at (0x38, 0x80) on a white card (0x34, 0x78, 0x108 × 0xDC) with its black shadow at (0x3C, 0x84), instead of 216 × 204 at (0x4C, 0x80) on a light grey card (0x40, 0x70, 0xF0 × 0xEC). The USA `stg_v` holds the English picture.
- **`title`** record pages: the same positions; the rank is printed with `%2d%s` (padded). **`ranking`**'s three record page functions differ in their code but not in their strings (not compared further).
- **`ending`** (Theater): the help strips are the lines of the table at USA `0x8010E1E4`, indexed like the Japanese strips (0 TEKKEN SERIES MOVIE THEATER, 1 … MUSIC PLAYER, 2 and 3 the disc messages, 4 RETURN TO THEATER MODE SCREEN, 5 MUSIC PLAYER, 6 SELECT MUSIC MODE, 7 RETURN TO TITLE SCREEN), font 0, colour 6, centred at 9 pixels a letter at y 400 (`FUN_80100834`).
- **Pictures**: besides the character ARCs' glyph atlas, only three overlay pictures differ: the select screen's name atlas (`DOCTOR B.`), and the title logo's mark in `title.ovl` and `enbu.ovl` (™ instead of ®).
- **Move lists**: the USA list screen (`FUN_80078550`) has the Japanese layout; only the text engine and the name measuring (`FUN_80079208`: a line break counts 100 cells, `0xFB` ten, the words their widths, bytes from `0xA1` two, the rest one) and splitting (`FUN_80079170`, which also stops after a `0xFC` line break) follow the English encoding. The list title is word 1 of the atlas at (x + 0x27, 0x61). The fonts at USA `0x80027AC0` are 6 × 12 with an advance of 6 (both players share the atlas's texture page).

## In the remake

The game converts from the USA disc alone too: its executable and overlays are mapped onto Japan Rev.1's addresses (`tools/remake_import/layouts/usa.json`), so the converter and the remake read them as Rev.1's. What the USA release lacks comes from the project: practice's KEY DISPLAY label and its pages' rows (Japan: FREE `0, 7, 13, 2, 1, 3, 4, 5, 14`, VS CPU `0, 7, 9, 10, 1, 3, 4, 5, 14`, 12 bytes a page). The ending movie list of the USA disc has its own caption flags (sets 1 and 5 on other endings) and ending 21 is shorter (last frame 553 instead of 801).

The remake keeps one interface, Japan Rev.1's structure (the more complete one), and with English game texts shows the USA wording ([remake-plan.md](../../remake-plan.md#texts-and-localisation)): strings by their body per memory block (`TextLocale`, from the project's generic wording and `tools/remake_import/usa.py`), the USA staff roll, the help lines in place of the Japanese strips, the practice prompt as above (with Japan's rows and key display), the RULES picture with its card, the English move lists with the USA engine (`MoveListView`), the pictures, and the padded record rank. The round-start voice of team battle and survival stays.
