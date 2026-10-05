# Function index: overlay routines not covered elsewhere

Status: `confirmed` from decompiled code (Japan Rev.1). Most overlay routines are described in the documents of their screens or modes ([modes.md](modes.md), [hud.md](hud.md), [stages.md](stages.md)). This index lists the remaining ones, found by a sweep for routines whose address appears in no document or port. They are small helpers of documented features, library copies, or set-up code, and each is named here with its role.

## `arcade.ovl`

| Routine | Role |
|---|---|
| `FUN_800B0C5C` | Arcade start: builds the ladder (`ArcadeBuildLadder`) for the human's costume key unless the mode keeps it (`+0x11`), and clears the Ogre-scene flag `+0xBC`. |
| `FUN_800B0DC0` | Before each stage: the CPU level `0x800AE6D9` = the entry's level byte. With one human, loads the stage's opponent (character, costume) for the CPU side (`FUN_8004F3CC`) and writes back the key it actually got. |
| `FUN_800B2724` | Team battle CPU team fill: see [modes.md](modes.md#arcade-ladder) (ported, `screens_sim.team_fill`). |
| `FUN_800B2B98` | Survival opponent pick: see [modes.md](modes.md#arcade-ladder) (ported, `screens_sim.survival_pick`). |
| `FUN_800B3818`, `FUN_800B38B0` | VS screen: a sliding portrait sprite (`FUN_8004BBC0`), and a white (224, 224, 224) tile while the slide has not started. |
| `FUN_800B4C80` | Returns 0 (an unused hook slot). |

## `volley.ovl`

| Routine | Role |
|---|---|
| `FUN_800B4690` | Starts effect type 15 (a glow) for index `n` once (bit `n` of `0x800B645C`); `FUN_800B4720` is the same with `player + 2·big`. |
| `FUN_800B4C58` | Clears both players' move tuning records (`FUN_800B0B24`). |
| `FUN_800B4C80` | Tekken Ball stage start: CPU level `difficulty·4 + 1` (`0x800AE6D0`), and with one human the opponent pick (`FUN_800B528C`, [modes.md](modes.md#unlocks)) loaded for the CPU side. |
| `FUN_800B4D24` | End of a Tekken Ball match: records the play for the human's character (`FUN_8005169C`) and, when the human won, Gon's unlock check (`FUN_8005696C`); in two-player games both characters' plays. Clears `0x800AE484..0x800AE486` and the sub-state. |

## `practice.ovl`

| Routine | Role |
|---|---|
| `FUN_800B2D74` | Resets the practice state `S` to its defaults (the bold values in [modes.md](modes.md#practice)). |
| `FUN_800B2BC4` | Round start per sub-mode: assigns the fighters (`FUN_800B4684`), resets the AI in VS CPU (`AiReset(dummy, 1, S+0x7E, S+0x7F, −1)`), empties the key ring, and in COMBO TRAINING loads the guide (`FUN_800B7A88`, `FUN_800B8244`, `FUN_800B7FB4`). |
| `FUN_800B4684` | Input sources: the player on pad (`0x80095894 = 1`), the dummy on the scripted word (2, via `FUN_800B87C8`), on the pad (CONTROLLER) or CPU (VS CPU). |
| `FUN_800B4600`, `FUN_800B6CF4` | The freeze signal for both fighters (`FUN_800B3520`) and its back-light colours at `0x800AE430`. |
| `FUN_800B48A4` | Resets a sub-mode's page when it is entered from MODE SELECT. |
| `FUN_800B4818` | Attack data: whether a hit belongs to the running combo (the attacker's move is in its active window or a follow-up is pending, or the victim is in a reaction). |
| `0x800B4EF8` | The OK item of the pause menu, a case of the item jump table `0x800B0A58` that Ghidra split off as a function: a face button or Start (`0x9F0`) resumes the fight (`0x800958AC = 1`, `S+0xAC = 1`). |
| `FUN_800B680C` | Key display clicks: sounds `0x4C70`–`0x4C73` for the four face buttons. |
| `FUN_800B78C0` | Key display: one button icon sprite. |
| `FUN_800B7968` | Key display: per-player hold timers. |
| `FUN_800B82F4` | Key ring: marks the replay head entry. |
| `FUN_800B85A0`, `FUN_800B8764` | Combo training: loads a combo's input steps as the guide ([modes.md](modes.md#practice)). |
| `FUN_800B8904` | Dummy on the ground (move `state & 0x204`): holds up. |
| `FUN_800B899C` | Dummy facing: not facing the player (`+0x32 ≠ 0`) with no move pending, it holds back (`0x8000`); facing and in an idle slot (the stance slot, 3, 4, 5 or the default continuation), no input. |
| `FUN_800B8AAC`, `FUN_800B8ACC`, `FUN_800B8AEC`, `FUN_800B8B94` | UKEMI MAE / OKU: LK+RK (`0x60`) or LP+RP (`0x90`) on every other frame during a reaction with an air window whose move has a tech-roll branch (condition `0x1C`). |
| `FUN_800B8CD8` | Stops a replay: resets the replay system, effects, camera shake, vibration and both fighters' sound scripts. |
| `FUN_800B4C80`, `FUN_800B4E3C` | Empty. |

## `title.ovl` and `ending.ovl`

| Routine | Role |
|---|---|
| `0x800E1DFC`–`0x800E2CE0` (title), `0x8010D474`–`0x8010E7B0`, `0x80114D1C`–`0x801154CC` (ending) | The STR movie player and its `libpress` copy ([sound-and-video.md](../formats/sound-and-video.md#str-movies)). |
| `FUN_800DC5D4` | Button icon sprite words (texture page and CLUT) for a pad-bit mask, used by the options and key config pages. |
| `FUN_800DF468`, `FUN_800DF57C` | KEY CONFIGURATION: the DEFAULT row (a face button restores the player's eight-button map `0x80098308 + 8·player` from `0x800B9B1C`, clears `0x800982EC[player]`, sound `0x4D87`) and the EXIT row (text colour 5 on the cursor, else 10, with the cursor box). |
| `FUN_800DFD24` | RECORDS: the mask of characters with a time-attack record (time below 359,999). |
| `FUN_800E0358`, `FUN_800E07F8` | RECORDS: build the character lists of the character-data pages, sorted by usage (`FUN_80051948`). |
| `FUN_800E10F4` | RECORDS: page input (left/right, sound `0x546C`). |
| `FUN_800E13C8` | DISPLAY ADJUST: applies the display offset (`DISPENV`). |

## `ranking.ovl`, `result.ovl`

| Routine | Role |
|---|---|
| `FUN_800C33AC` | Uploads the ranking pictures (`FUN_800C390C`) with the vertical-blank callback paused. |
| `FUN_800C33DC` | Copies a character's name (`FUN_8004F2D8`) into a name-entry buffer. |
| `FUN_800C3BA0` | Returns 0 when a value is one of the four in `0x800CBE58`. |
| `FUN_800F2930` | Reads arcade stage record `n` (`0x800AFF90 + 8·n`) for the time attack result; true past the tenth. |

## Resident code

The remaining unnamed resident routines (444, 78 KB) are listed one by one in [resident-functions.md](resident-functions.md), grouped by their documented caller, with notes for every routine of 200 bytes or more.
