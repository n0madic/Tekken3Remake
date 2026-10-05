# Game modes and overlays

The resident executable runs the fight; menus, screens and mode rules live in overlays. This document maps game states and modes to overlays and records the mode rules found so far. Addresses are Japan Rev.1; see [memory-map.md](memory-map.md) for the two overlay slots.

Status: `confirmed` from decompiled code and overlay data. This covers the state, mode and overlay mapping; the arcade, survival, team, unlock, Tekken Force and Tekken Ball rules; the match flow; the main menu and game options; the result, ranking and staff roll screens; and the save block. The flow and screen logic (continue, challenger, Ogre scene check, unlocks, Tekken Ball opponent choice, name entry, ranking, results, staff roll) is ported in [`tools/research/screens_sim.py`](../../../tools/research/screens_sim.py) and matches the game byte for byte in the harness ([tooling.md](../tooling.md#verification-log)). The screens' drawing is ported in `draw_sim.py`, `menu_sim.py`, `select_sim.py`, `practice_sim.py`, `force_sim.py` and `theater_sim.py`; the Tekken Force level runner in `force_sim.py`, the Ogre scene in `ogre_scene_sim.py`, and Tekken Ball's 3D drawing in `ball_sim.py`.

## Overlays

| Overlay | Slot | Serves |
|---|---|---|
| `arcade.ovl` | mode `0x800B0A10` | Modes 0–4: arcade ladder, VS, team battle, time attack, survival; captions and unlocks. |
| `practice.ovl` | mode | Mode 5 (practice). |
| `force.ovl` | mode | Mode 8 (Tekken Force). |
| `volley.ovl` | mode | Mode 7 (Tekken Ball). |
| `title.ovl` | screen `0x800B9378` | Title, main menu, options. |
| `select.ovl` | screen | Character select. |
| `result.ovl` | screen | Match results. |
| `ranking.ovl` | screen | Ranking and records. |
| `ending.ovl` | screen | Movie player: opening, logo, endings ([sound-and-video.md](../formats/sound-and-video.md#str-movies)); game state 19. |
| `enbu.ovl` | screen | The attract demonstration with its own models (`enbmdl1–3.arc`), [below](#enbu-attract-demonstration). |

## Game states

The main loop dispatches on `g_gameState` (`0x800AE6CC`), with the sub-state in `0x800AE6EC`. Handlers above `0x800B0A10` exist only while their overlay is loaded. `FUN_8004FBE0(target)` goes to a state through the transition screen (state 2); `FUN_80050208(target)` goes through the screen-overlay loader (state 18).

| State | Handler | Screen |
|---:|---|---|
| 0 | `0x800B0BD0` | Boot code in the EXE image; the overlay slots overwrite it later. It uploads the [system textures](../formats/system-textures.md), turns the display on and goes to the title (`FUN_8004FBE0(3)`). |
| 1 | `OverlayLoader` `0x80052FAC` | Loads the queued overlays and data, then switches to the requested state ([memory-map.md](memory-map.md)). |
| 2 | `0x8004FD48` | [Transition screen](#transition-screen). |
| 3, 4, 5 | `title.ovl` | Title, main menu, options ([main menu](#main-menu)). |
| 6 | `enbu.ovl` `0x800D3844` | [Enbu](#enbu-attract-demonstration). |
| 7 | `0x80050600` | Fight preparation. Reloads the mode overlay when the mode changed (`0x800AFF66` ≠ `0x800AFF67`), allocates the fight heap (`FightAllocBuffers` `0x80055B6C`: layout 1, 2 for mode 7, 3 for mode 8), then goes to state 8. |
| 8 | `FightMain` `0x80050710` | [Match flow](#match-flow). |
| 9 | `select.ovl` `0x8011056C` | [Character select](#character-select). |
| 10 | `0x80055878` | Quick select. |
| 11 | `0x80052808` | [Pre-fight VS screen](#pre-fight-vs-screen). |
| 12–15 | `result.ovl` | [Result screens](#result-screens): team battle, time attack, survival, Tekken Force. |
| 16 | `0x800504A8` | Loads `ranking.ovl` and saves unless a name entry is pending. It sets up the ranking backdrop and goes to state 17. |
| 17 | `ranking.ovl` `0x800C2A24` | [Ranking screen](#ranking-screen). |
| 18 | `0x8005025C` | Queues the screen overlay for the target (`ending.ovl` for 19, otherwise `result.ovl`) and goes there through the loader. |
| 19 | `ending.ovl` `0x8010E8C0` | [Arcade ending and staff roll](#arcade-ending-and-staff-roll), or [Theater](#theater). |

### Transition screen

State 2 (`0x8004FD48`) runs between screens. The target is in `0x80098318` and the previous state in `0x80098319`. `FUN_8004FBE0(3)` (back to the title) goes to Enbu (state 6) instead at attract step 1 ([Enbu](#enbu-attract-demonstration)).

- **Enbu, or the title except at attract step 3.** The screen shows `NAMCO PRESENTS.` (font 0 at (117, 240); `NAMCO` in colour 2, `PRESENTS.` in colour 6):
  - a 32-frame fade-in;
  - on the first pass, the memory card is read (`FUN_8004C528`); on later passes, an autosave;
  - at least 90 frames on screen;
  - a 32-frame fade-out.

  Once the card has been read, Start during this screen jumps to the main menu (sound `0x4CC0`).
- **Any other target.** The screen stays blank.

In every case the state then:

- loads `title.ovl` or `enbu.ovl` if it is not cached (`0x8009831C`);
- autosaves when AUTO SAVE is on (`0x800982F1`) and the save-pending flag `0x800AE428` is set (`FUN_8004C6A0`, file `bu00:BISLPS-01300TEKKEN-3`);
- shows `AUTO SAVE ERROR!` for 120 frames if the save failed (`FUN_8004C758`);
- switches to the target.

The fade is a subtractive `TILE` of grey `255 − 8·t` over the text box (135 × 18 at (117, 240)); `AUTO SAVE ERROR!` blinks between colours 2 and 10 (font 1, at (80, 240)) on black. The screen is ported with its sub-states in [`tools/research/menu_sim.py`](../../../tools/research/menu_sim.py) (`transition_screen`; the overlay loader and the card are hooks).

## Modes

`g_gameMode` (`0x800AFF50`) is the first word of a mode context passed to the overlay hooks. Values identified from the caption code (`ModeCaption` `0x8004EE3C`) and the per-mode hooks:

| Mode | Name | Notes |
|---:|---|---|
| 0 | Arcade | 10-stage ladder; unlocks. |
| 1 | VS battle | No caption. |
| 2 | Team battle | Members per side; CPU level from the remaining members. |
| 3 | Time attack | Arcade ladder with a restricted character mask. |
| 4 | Survival | CPU level from the number of wins. |
| 5 | Practice | Dummy control, no guard restriction for state bit 8, input display. |
| 6 | Demonstration fight | Started by the title sequence when it runs out (`FUN_800DAF2C(6, 0)`): both fighters CPU-controlled (`0x800AE39C = 1`), vibration off, no ladder. Fighter 0 cycles through the unlocked characters of the list Law, Eddy, Paul, King, Lei, Xiaoyu, Hwoarang, Jin, Yoshimitsu, Nina, Heihachi, Julia, Bryan, Anna (`0x800E3040`, position `0x800982F3`); fighter 1 is a different random one from the same list (`list[(position + 1 + (frame counter & 0xFFF) mod (n − 1)) mod n]`). Both use their second costume when bit 9 of the summed character usage (`FUN_80051948` over all 22 characters) is set. `enbu.ovl` carries a copy of this routine (`FUN_800D3648`). |
| 7 | Tekken Ball | Court of `|z| ≤ 0x100`, `|x| ≤ 0x1400`; a ball object is the only source of damage ([below](#tekken-ball)); stage 19. |
| 8 | Tekken Force | Side-scrolling levels with CPU enemies (character 21 in costumes Crow, Falcon, Hawk, Owl, motion bank 20), walls from the overlay, score (`0x800B70EC`), "STAGE CLEAR"; stages 15–18. Enemy CPU level by level: 3, 4, 5, 5 (`FUN_800B6110`, force.ovl). |

## Arcade ladder

`ArcadeBuildLadder` (`0x800B2494`, arcade.ovl) fills ten 4-byte stage entries (character, costume, stage index):

1. Stages 1–4: random distinct characters from the ten original characters (IDs 0–9), excluding the player's character and the stage-9 boss.
2. Stages 5–8: random distinct characters from the remaining unlocked characters (`0x800982D0`; time attack masks it with `0x157FFF`), excluding Heihachi, Ogre and True Ogre. In arcade (not time attack), Gon (17) joins this pool once the first Tekken Ball game has been played (`0x800982FE`), even while he is locked; that is how he can be met and unlocked in arcade ([unlocks](#unlocks)).
3. Stage 9: Heihachi (13), or Jin (9) when the player is Heihachi.
4. Stage 10: Ogre (14). Winning a round against him turns the fight into True Ogre ([Ogre scene](#match-flow)).

Opponents use costume 1 when the player's costume is not 0 (`(costume & 3) ≠ 0`), otherwise costume 0; Ogre and True Ogre always use 0. The picks use `FUN_8004D13C` (the `x·5 + 1` generator at `0x8009F650`). The CPU level for each stage is its index (0–9), loaded into `0x800AE6D9` before the fight ([ai.md](ai.md#difficulty-parameters)). After stage 10 the game goes to state 19 (ending movie).

**Survival** (`0x800B104C`) sets the CPU group to 1 and the level from the number of wins `w`: `w < 5` → 1–3, `< 10` → 2–4, `< 20` → 3–7, `< 50` → 3–7 (group 2 when an option bit is set), then every tenth win level 0, otherwise 3–9 with group 2.

**Team battle CPU team** (`FUN_800B2724`, called for both sides at the start, ported as `screens_sim.team_fill`, verified):

- **Pool.** Free places are filled from the unlocked characters (`0x800982D0 & 0x1F7FFF`) not already in the team.
- **Least-used member.** A team of three or more whose first argument is set first takes one of the two least-used characters (plays + losses + draws, chosen by `FUN_8004D13C() & 1`). The argument is meant as the CPU flag, but the set-up `FUN_800B0CD0` passes the side's active flag, so the rule never applies to a CPU team ([bug #60](game-bugs.md)).
- **Least met.** The others come at random from the characters met least often in team battle (`0x800AFFC4`, u16 per character). The met-count window is widened by one until it holds enough characters.
- **Order and costume.** The chosen characters are shuffled into the free places, in the team's costume, or the other costume when that exact costume key is already in the opposing team.
- **Met counts.** Every member's met count then goes up by one.

**Survival opponents** (`FUN_800B2B98`, ported as `screens_sim.survival_pick`, verified):

- **Pool.** Chosen by the stage counter (`+0x24`): the ten original characters for stages 0–6, then everyone but Ogre and True Ogre for 7–16, then everyone, always within `0x157FFF`, without the last four opponents (a ring at `+0x50`).
- **Pick.** A random character among the least met (`+0x60`); from 20 wins (`+0x44`) on, the window reaches 4 above the least.
- **Costume.** Chosen by the parity of the frame counter.

**Team battle** (`0x800B0E78`) swaps in the next member when one is defeated; the CPU level is `difficulty + 3 + (option & 3)`, plus 1 or 3 when the human side has one or two more members left than the CPU side.

## Tekken Force

`force.ovl` (functions rebuilt with `tools/ghidra/RefunctionRange.java`, see [tooling.md](../tooling.md)) drives mode 8. The player fights up to two CPU enemies at a time (enemy slots `0x800B6A7C`, 24 bytes each, driving the two fighter records not used by the player; `FUN_800B5EC0` picks the player, the current opponent and the third fighter every frame). Enemies are character 21 with costume key `0x54 + costume`, where the costume comes from the level and the pattern's variant bit (`0x800B0BB0`): level 1 Crow/Falcon, level 2 Crow/Hawk, level 3 Falcon/Hawk, level 4 Hawk/Owl.

**Level script.** Stage ARC member 3 of stages 15–17 (2,560 bytes) is a list of 20-byte records `(s32 trigger, s16 command, s16 dx, s16, s16 z, s16, s16 param, u16 arg)`, consumed in order while the camera has scrolled at least `trigger` units from its start (`FUN_800B1778` state 0):

| Command | Effect |
|---:|---|
| 0 | Scroll mode (`param`): 0 free scrolling, 1 lock the screen for a fight, 2 lock at the end. |
| 1 | Spawn an enemy in a free slot at `(camera x + dx, z)` (±5,000 = from the right/left edge), type `arg % 5`, variant `param`. |
| 2 | Start a spawn pattern: `param` selects a list of `(variant, type, 0)` triples in the overlay (`0x800B0A10 + 6·param`, terminated by 99); a new enemy enters from the right whenever a slot is free, until the camera passes `arg`. |
| 3 | Wait until `param` more enemies are defeated (`0xFFFF` = until both slots are empty); the script pauses. |
| 4 | Place an item at `(camera x + dx, z)` (two item slots, `0x800B6E90`). See [items](#tekken-force-items). |
| 6 | End of level: stage clear, `NOW LOADING...`, bonus tally. |

<a id="tekken-force-items"></a>**Items** (`FUN_800B4374`, each frame of the level script). An item is drawn as two camera-facing textured quads above its projected position (screen depth z = SZ3 / 4; the point is at y `0x420`, under the floor, set by `FUN_800B4198`), both `0x15E00 / z` wide, centred, and ending `0x2BC00 / z` above the point: one `0x2BC00 / z` high, the other `0x15E00 / z` high. The tall one is the picture (the roast chicken: texture page 8, u 0–63, v 64–191, CLUT `0x7801`, opaque), the square one behind it its shadow (v 0–63, CLUT `0x7800`, shade `0x20`, semi-transparent); the level archive's last three TIMs hold them. They go into the ordering-table entry for z (`((z & 0x3FFF) >> 3) − 1`) and the one after it. It is removed once it is 5,000 units behind the camera. It is picked up when the player's position is within 500 units of it in x and z, the player is alive and not in a throw (`+0xDB`):

- the health goes up by 50 (`+0x3F4 += 0x320000`, 16.16), with sound `0x4E6A` and `FUN_8003A388` (starts the player's back colour flash, [stages.md](stages.md#lighting));
- `LIFE UP!` (font 0) appears 36 pixels left of the point 300 units above the player and rises half a pixel per frame for 60 frames, blinking between colours 5 and 2 (level clock bit 1);
- sound `0x87C0` plays 15 frames before it disappears.

Ported in `force_sim.py` (`items`) with the projection of `projection_sim.py`.

**Script runner** (`FUN_800B1778`, ported in full in [`tools/research/force_sim.py`](../../../tools/research/force_sim.py) as `level_frame`: `level_script` for the commands, the wait state 1, the end-of-level states, the boss set-up of state 8 and the pattern spawner; then the two enemy slots, the progress bar, the items, the key icons, the score and timer caps and the countdown; it returns 1 on the frame NOW LOADING ends, which makes `FightFrame` change the area). State 1 waits until `0x800B6AC0` enemies have been defeated since the wait began, or, when the count is negative, until both slots are free. State 8 turns slot 0 into a type-4 boss with the level's boss health, starts its entrance (`FUN_8002D93C(fighter, 3)`, `FUN_800B362C(1, 0x13, 0)`), locks the camera (scroll mode 2: bounds 5,000 units either side) and times the fight in state 9. The pattern spawner adds the next pattern enemy at camera x + 5,000 whenever a slot is free, until the pattern's 99 or the camera passing the stop x.

**End of level** (`FUN_800B1778` states 3–10; the tally is part of the port, Ghidra's decompile drops it because it treats the counter `0x800B6A6C` as read-only data). After command 6 the fight is frozen, `NOW LOADING...` (font 0, colour 6, at (242, 422)) shows while the next level's data loads, and the remaining time is shown over the player (`%2D"%02D`). The tally (state 7, one line every 30 frames from frame 30, font 1 at x 47): `STAGE BONUS : n` (colour 4, y 180; 5,000 / 10,000 / 15,000 / 20,000 by level), `CLEAR BONUS : n` (colour 1, y 232; remaining health × 100), `CLEAR TIME : mm'ss"cc` (colour 5, y 284) and at frame 120 either `BONUS TIME : …` (colour 6, y 336; added to the timer, levels 1–3), `YOU GOT A KEY!!` (blinking colours 2/6 at x 86) or `CHALLENGE FINAL STAGE!!` (x 34). Each bonus is added to the score (`0x800B70EC`) as it appears, and each line plays sound `0x4C6C` (`0x4CEB` for the key and final stage messages, `FUN_800B4A1C`). The BONUS TIME hundredths are replaced by `100 − clear-time hundredths` when their sum is below 100.

**Enemies.** A slot (24 bytes at `0x800B6A7C`) holds the fighter pointer, the `+n SEC` position (`+4` x, `+6` y × 16), the state (`+8`), a timer (`+0xC`), the type (`+0xE`), the current and requested costume variant (`+0x10`, `+0x12`) and the popup's end frame (`+0x14`). The states run every frame for both slots:

| State | Action |
|---:|---|
| 0 | Release: hide the fighter (`+0xC3` = 0), health 0, frozen (`+0xC2` = 1); then state 1. |
| 1 | Free. |
| 2 | Hide the fighter and wait two text frames (`0x800B6AE4`). |
| 3 | When text is on: load the requested variant's model. The costume key is `0x800B0BB0[2·(level & 3) + (variant & 1)]`; `+0x14` = key + `0x54`, then `FUN_800363FC`, `FUN_800360B0(index, variant + 1)`, `FUN_80035F3C` with the parts of `FUN_80036124`/`FUN_80036140`, and `FUN_800B362C(index, 0x15, key)`. |
| 4 | Show the fighter with full health (`0x800B0B4C[5·level + type]`, also `+0x3F8`), unfreeze it, start move slot 3 (`FUN_8002D93C`), clear `+4`, `+0x92`, `+0xB8`. |
| 5 | Fight until the health is 0 or less; then state 6 with a 60-frame timer. When the player dealt the blow (`+0x22` = the player's index) or the body was thrown into it (`+0xE7`), the timer gains the type's seconds, rounded up to a whole second (`t + 59 − t mod 60 + 60·s`), `+n SEC` is placed 300 units above the fighter (27 pixels left) for 60 frames, and the defeat counter `0x800AFF8C` goes up. |
| 6 | Draw `+` (colour 5), the seconds (font 1) and `SEC` (colour 6) at the popup, rising half a pixel per frame. After the timer, once the fighter has landed (`+0xC4` = 0), freeze it and go to state 7 for 40 frames; while it is still being juggled by the player (`+0xCE`), the timer restarts. |
| 7 | Blink (`+0xC3` = clock bit 0); then hide it, count the defeat for command 3 (`0x800B6AC0`) and free the slot. |

After the slots: the score is capped at 99,999,990; a score above the hi-score `0x800B7100` replaces it and sets the new-record flag `0x800AFF8F`; the timer is capped at 99 seconds; and while the fight runs (`RoundFlow` state 1) the announcer calls 5…1 at 300, 240, 180, 120 and 60 frames (`SoundPlayFighter(0, 0x80097486 … 0x8009747E)`).

Health (16.16, `0x800B0B4C`) by level and type:

| Level | Type 0 | 1 | 2 | 3 | 4 (boss) |
|---:|---:|---:|---:|---:|---:|
| 1 | 15 | 20 | 25 | 30 | 130 |
| 2 | 20 | 25 | 30 | 40 | 150 |
| 3 | 20 | 25 | 30 | 40 | 170 |
| 4 | 20 | 25 | 30 | 40 | 250 |

Defeating an enemy (by the player's hit or a thrown body) adds 2, 4, 6 or 8 seconds by type (`0x800B0B3A`) to the timer, shown as a rising `+n SEC`, and counts for command 3. The timer is capped at 99 seconds (`0x1734` frames); the announcer counts down at 5…1 seconds.

**Bosses.** Every level ends with a real fighter (sub-state 23, `FUN_800B2B3C`: model reload, the boss's music, placed 4,096 units ahead of the camera, move slot 3, boss health from the table above). The boss depends on the player's character (table `0x800B685C`, per costume key; a variant of −1 means the other costume of the player's own character when the boss is the same character, else costume 0):

| Player | Level 1 | Level 2 | Level 3 | Level 4 |
|---|---|---|---|---|
| Paul | Law | Kuma | Jin | Heihachi |
| Law | Paul | Hwoarang | Eddy | Heihachi |
| Lei | Nina | Hwoarang | Bryan | Heihachi |
| King | Lei | Paul | Nina | Heihachi |
| Yoshimitsu | Yoshimitsu | Mokujin | Bryan | Heihachi |
| Nina | Jin | Anna | Anna | Heihachi |
| Hwoarang | Eddy | Law | Jin | Heihachi |
| Xiaoyu | Lei | Kuma | Jin (costume 2) | Heihachi |
| Eddy | Julia | Gun Jack | Tiger | Heihachi |
| Tiger | Eddy | Eddy (costume 1) | Tiger | Heihachi |
| Jin | Paul | Nina | Hwoarang | Heihachi |
| Julia | King | Eddy | Jin | Heihachi |
| Kuma | Panda | Xiaoyu | Paul | Heihachi |
| Panda | Kuma | Xiaoyu (costume 2) | Jin (costume 2) | Heihachi |
| Bryan | Lei | Gun Jack | Yoshimitsu | Heihachi |
| Heihachi | Eddy | Julia | Jin | Heihachi |
| Ogre, True Ogre | King | Hwoarang | Jin | Heihachi |
| Mokujin | Mokujin | Mokujin | Mokujin | Mokujin |
| Gun Jack | Gun Jack | Yoshimitsu | Bryan | Heihachi |
| Gon | Kuma | Panda | Mokujin | Heihachi |
| Anna | Yoshimitsu | Gun Jack | Nina | Heihachi |
| Doctor B. | Nina | Anna | Bryan | Heihachi |

The boss's character and costume are recorded per level at `0x800AFF91 + level` (character · 4 + costume).

**Targeting** (`FUN_800B5EC0` every frame, `FUN_800B598C`; ported in `force_sim.py` as `fighter_roles` and `choose_target`, verified). The player is fighter 0 (fighter 1 when `0x800A97B5` is set) and the two other records are the enemies. The player faces:

- the enemy that is not hidden (`+0xC2`);
- else the only one "close" (`+0x1278` in 1..399);
- with both close and no switch for 120 frames: the nearer when their distances differ by 400 or more (both at 2,500 or more: no change);
- else the one more in front, by facing quadrant (front, then the sides, then behind) or, in the same quadrant, by relative angle once the gap reaches a quarter turn (front), half (back) or three quarters (sides).

A change starts the 120-frame wait. The chosen enemy becomes every fighter's opponent index (`+0x20`, `+0x1F` from `FighterOpponentIndex`).

**Manual target switch** (hidden). Holding △, ○, × and □ when Tekken Force starts (`FUN_800B5910` for the player's pad, reading the held buttons `0x800AE230`) turns on manual targeting.

- **Buttons.** These are the physical buttons, before the KEY CONFIGURATION mapping (`FUN_8002A014` fills `0x800AE230` from the pad's raw bytes and applies the mapping only to the game input `0x800A9110`). The switch button is L1 if held, else L2, R1 or R2, and L2 when none of them is held.
- **Use.** During the fight each press of it swaps the enemy the player faces (`0x800B6A14..0x800B6A1C`, cleared by `FUN_800B58FC` when the mode is set up again).
- **Wait.** A press is only read while both enemies are close and the 120-frame wait after the last change has run out, so a second press within two seconds does nothing.
- **Checks.** `tools/research/check_force_manual_target.py` runs this chain in the original code, from the pad bytes to the change of target, with and without the secret. `tools/research/check_force_bosses.py` runs the boss loader for all 88 costume keys and 4 levels against the boss table above.

**Walls** (`ArenaBounds` in mode 8, ported in `fight_sim.py`). Fighters stay within z ∈ [−0x898, 0x8FC]. On level 4 (stage 18) the lower limit is instead a line of the fighter's x relative to the camera (`FUN_800B309C`). The player's x relative to the camera's view-space x (`0x800B70F0`) stays between two lines of z (`FUN_800B3020`), and a CPU enemy stays within ±0x1068 of the camera. `FUN_800B2F98` sets the lines per level:

| Level | Left limit x | Right limit x | Stage-18 lower z |
|---|---|---|---|
| 1–3 | −0.323·z − 2,553 | 0.329·z + 1,971 | −0.259·x − 2,285 |
| 4 | −0.375·z − 2,445 | 0.333·z + 2,175 | same |

**Mode start** (`FUN_800B60A4`, `FUN_800B1508`): keys from the save (`FUN_800B63B0`), score 0, the saved hi-score (`0x800982F4`, written by `FUN_800B6414`), the three key pictures uploaded, the Doctor B. flag in the result byte (`FUN_800B6358`: `0x800982D0` bit 19; `FUN_800B6370` unlocks him, `FUN_800B63C0` adds a key up to 255). `FUN_800B2E10` sets the player and enemy pointers `0x800B6AAC`/`0x800B6AB4`, `FUN_800B34B0` the HUD bars' names and colours, `FUN_800B4198` the item quads (texture page 8, CLUTs `0x7800`/`0x7801`), and `FUN_800B6514` the level title texts.

**Panorama** (`FUN_800B4B44` set-up, `FUN_800B4DF8` each frame, ported in `force_sim.py` as `background_setup` and `background_draw`). The level's tile map (stage ARC member 2: `u16 w, u16 h`, then `u16` texture words and `u16` CLUT words, one per cell) is drawn as 64 × 64 sprites, seven columns per row, at scene OT entry `0x3F0` (`0x3FE` on level 4). It scrolls one pixel per 20 units of the camera's view-space x (modulo the map width); its top edge is the projection of the world point (camera x, 0, 2,500), minus 64 × the map height. The maps are 16 × 5, 15 × 5 and 13 × 5 cells for levels 1–3 and 3 × 5 for level 4. On level 4 the map climbs like a staircase: every third column (one repetition of the 3-wide map) is raised by `64 · tan(0xD8)`, a black 272 × 100 tile at (0, 20) fills the ground behind it one OT entry later, and a black 64 × 32 tile closes the bottom row below each repetition (at most three on screen, one per buffer slot at `0x800B7018`). With `0x800B70F4` set only a black full-width tile down to the horizon − 16 is drawn. The texture word gives u = (w & 3) · 64, v = (w & 0xC) · 16 and the texture page (`w >> 8 & 0x1F`, set by a draw-mode packet before each sprite).

**Scoring.** Score `0x800B70EC` (capped at 99,999,990) and hi-score; at the end of a level: stage bonus 5,000 / 10,000 / 15,000 / 20,000 (`0x800B0BD0`), clear bonus = the player's remaining health × 100, and bonus time = the level's time allowance (40, 50, 60 s at `0x800B0BBC`) minus the time used, carried over to the next level's timer. Level 4 has no script: it is a 60-second fight against a type-4 boss in slot 0 (`FUN_800B1778` state 8). **Keys.** The key count is saved (`0x800982F8`, save block `+0x28`) and read into `0x800B70D0` at the start of the mode. On the frame the fight freezes after level 4 (`FUN_800B1778` state 6, round state 8), while Doctor B. is still locked (`0x800982D0` bit 19):

- with fewer than 3 keys, the run earns a key: `YOU GOT A KEY!!` in the tally, the saved count goes up by one (saturating at 255, save pending), and the result flags `0x800AFF90` get bit 0, 0–1 or 0–2 (1, 2 or 3 keys);
- with 3 keys, `CHALLENGE FINAL STAGE!!` shows and the Doctor B. level follows.

The same state computes the clear time (the timer when the fight after NOW LOADING began, `0x800B6AD4` set in state 5, minus the timer now), the bonus time (the level's allowance minus the clear time, at least 0) and the clear bonus (the player's health `0x800A9AE4 >> 16` × 100). While bonus time is left and the player is alive, it prints the bonus time `ss"cc` (`%2D"%02D`, colour 5, font 0) starting 22 pixels left of the point 500 units above the player, projected with the fight camera (`FUN_8004B05C`, `FUN_80036D28`, ported in `projection_sim.py`).

**The resident code in mode 8.** Several resident routines read force.ovl variables; Ghidra's decompile of the executable drops those reads (the addresses lie outside the program it analysed), so the conditions below come from the disassembly:

- `MoveStepAll` steps the third record only while `0x800B70E8` (the level's enemies are over) is clear.
- `FUN_8003E608` (round over): while `0x800B70E8` is clear the round ends when the player's health (`FUN_800B2E60`) is 0 or less; in the boss fight when the first or second record's is; then the time.
- `0x800B70D8` is the human's pad (0 or 1; the player is always the first record): `CpuOrPadInput` reads that pad (and faces the current opponent `+0x1F`), `FUN_8002BC28` (Start during the round end), `FUN_800761D8` (vibration: the first record on that pad, the enemies on the other), the pause menu's COMMAND page (`FUN_80079298`: only the first record's list, scrolled by that pad), the round start's Mokujin check, `StageAndMusicSelect` (the human's character picks the music) and `FUN_800B5910` (the manual target switch) all use it. Tekken Ball's COMMAND page without text reads the same address, past volley.ovl's data (bug #39).
- `PairwiseDistances` counts a CPU record as off screen while its enemy slot is free and `0x800B70E8` is clear (`FUN_800B2EEC`).
- `BodySeparate` doubles the push of a pushable body and cancels the other's while two or more fighters are in a throw (`0x800958C4 > 1`).
- `HitApply` adds ten points per damage (the hit's base damage for hits by the player or a forced hit, twice the extra damage) to the score of an enemy hit, and starts no KO replay.
- `FighterMovePhysics`: a CPU body thrown faster than `0x59` (from frame 11 of the throw) and the player's power moves (flag 16, costing 10 health) hit whoever they touch (forced hits: `HitTest` places the contact at the defender's root and plays `0x4951`); `+0xC9` is set for a CPU or fixed-facing record.

## Tekken Ball

`volley.ovl` supplies the mode-7 hooks called by the resident fight loop: `FUN_800B0C90` at fight start, `FUN_800B0B54` for each fighter after `MoveStartAll`, and `FUN_800B0E14` (ball update, gauges) after `MoveBranchAll`. The players stand at `x = ∓0x1400` facing each other across the court ([arena bounds](fight-frame.md#arena-bounds)); two points are needed per round (`0x800AFF8C = 2`).

**Ball object.** The ball is its own structure (`0x800AE23C`, allocated in the fight heap), not a fighter: state `+0x00`, position `+0x68/+0x6C/+0x70` (`s32`), velocity `+0x78/+0x7C/+0x80` (8.8), gravity `+0x8C` added to the vertical velocity every frame, horizontal speed `+0xA8` (8.8) along the angle `+0xB0`, homing flag `+0xB2`, spin `+0x98–+0xA4`, owner `+0x130` and target `+0x134` fighter pointers, the two players' power `+0x13C/+0x13E`, the charge carried `+0x140`, and a timer byte `+0x147`. Four points around the ball (`0x800B6808`, ±128) form its hit volume.

**Port.** The whole ball is ported in [`tools/research/ball_sim.py`](../../../tools/research/ball_sim.py) and verified against the game by `verify_ball_sim.py`, with all of RAM compared:

- the fight-start hook (`fight_start`, `FUN_800B0C90`), the round reset (`round_reset`, `FUN_800B0DD8`) and the ball set-up (`ball_init`, `FUN_800B0FDC`);
- the frame hook (`ball_frame`, `FUN_800B0E14`), the physics and touches (`ball_update`, `FUN_800B16A4`, with the attack and body tests `FUN_80048030` and `FUN_800481AC`), and the squash and render kind (`ball_after_update`, `FUN_800B2F14`);
- the move tuning (`move_tuning`, `FUN_800B0B54`), and the court, the ball and the panorama drawing.

A round starts with the ball at x = −0xD00 (+0xD00 when `0x800AFF90` is set, which also makes that player the owner), y = −0x500, a serve countdown of 100 frames in round 1 and 40 later, and a hit radius of 608 (`+0xC4`). The render kind `+0x146` is chosen after the physics:

| Kind | When |
|---:|---|
| 0 | serve countdown |
| 1 | reset |
| 2 | point scored |
| 3 | flying |
| 4 | set |
| 5 | just touched |
| 6, 7 | charged by player 1 or 2 |
| 8 | re-hit charge |
| 9 | charge of 100 or more |

A charged hit starts the hitter's glow once per player and size (effect type 15, `FUN_800B4720`; flags `0x800B645C`), and while `0x800B6B54` is set `HitApply` takes the reaction of the ball's stand-in attacker (the third record's move) instead of the opponent's (a read of volley.ovl data the executable's decompile drops). `FUN_800B0B54` sets, after `MoveStartAll`, a per-player tuning record `0x800B6B40` from the running move slot (`+0xA0` − 0x18). The move system reads its look-ahead frame (`fight_sim.py`).

**Ball options** (`0x800AFF91`, chosen on the side-selection screen `FUN_800B569C`; table `0x800B6460`, 24 bytes each):

| Option | Speed unit `0x800B6AD8` | Gravity `0x800B6ADC` | Power gain `0x800B6AE0` | Neutral zone `0x800B6ADE` |
|---:|---:|---:|---:|---:|
| 0 | 384 | 512 | 60 % | ±2,304 |
| 1 | 368 | 512 | 80 % | ±1,920 |
| 2 | 352 | 682 | 100 % | ±1,536 |

**States** (`FUN_800B16A4`):

| State | Behaviour |
|---:|---|
| 0 | Serve countdown (`+0x147`: 100 frames in round 1, else 40), then state 8 with sound `0x4CE8`. |
| 1, 8 | 32-frame wait, then 2 (or 9), with the ball placed on the line between the players. |
| 9 | Serve: the ball bobs at `y ≈ −0x500` (sine) until someone touches it or 600 frames pass. |
| 2, 3, 4 | In flight: `pos += vel >> 8`, gravity added, horizontal velocity from speed and angle; while homing, the angle tracks the target fighter's root and the vertical velocity is re-aimed so the ball arrives at the target's head height (`+0x950`). State 4 is a spike whose speed and fall are much larger (vertical `−0x48·g`, speed `10·unit`), falling back to 2 at the ceiling `y = −0x1400`. |
| 5 | The ball struck a player and drops dead. |
| 7 | Point scored: 5 frames, then 6. |
| 6 | 16-frame reset, then 1 (the ball reappears above the centre, sound `0x4CE9`). |

**Floor.** When the ball comes down to `y = −0x180` inside `|x| ≤ 0x2800`: inside the neutral zone it bounces (vertical velocity halved and reversed, spin halved); elsewhere the player on whose half it landed loses 30 health (`−0x1E0000` in 16.16), that side's power is reset and the point ends (state 7). A ball lying still for 600 frames is reset.

**Touches.** Each frame the ball is tested against both fighters' attack segments (`FUN_80048030`) and bodies (`FUN_800481AC`):

- **Body touch** by a fighter who is not carrying the ball's charge: the ball is knocked towards the opponent in an arc computed from the fighter distance (sound `0x704E`).
- **Charged ball hits the opponent** (the ball's owner is the other player and it carries a charge): the resident hit system is used with the third fighter record `0x800AC808` as the attacker, whose damage is set to the charge. Unguarded, the victim takes the charge as damage, catches fire (effect type 11) when the charge is at least 100, and the ball drops (state 5; sound `0x4E6D` below 50, else `0x4DAF`); guarded, sound `0x7043` and only a lethal charge burns.
- **Attack hit** by a fighter: the whole fighter record is copied to `0x800AC808` (so the ball carries that move's attack data), vibration 5, and the hitter's power grows by `damage · gain / 100`, which becomes the ball's charge. The trajectory depends on the attack level: highs (`0x412`) fly flat and fast (a high hit on a state-3 ball becomes a spike); mids (`0x217`, `0x31F`) and other levels lob the ball to the opponent (the charge is kept when re-hit, `+0x145`); lows (`0x10F`, `0x51F`) shoot low and fast; unblockable attacks (`0x607/0x706`) keep the charge and home in; attacks without damage "set" the ball (state 3). Both players hitting at once pops it up neutrally. Bank type 4 (Yoshimitsu) hitting the ball with an unblockable attack loses health equal to the opponent's stored power and ends the point.

**HUD.** `FUN_800B4E6C` draws the two power gauges (records `0x800B68E8`), each at y 434 (player 1 at x 10, filling rightwards; player 2 at x 278, leftwards) between two 6 × 24 end caps.

- The fill moves 3 pixels per frame towards `power · 76 / 100` (the ball context's `+0x13C`, `+0x13E`). A lighter trail follows a drop by a sixteenth of the gap per frame.
- The gauge of the player charging a ball pulses while the game is not paused. The gauges are hidden while the pause COMMAND page shows two lists.
- Popup texts (`FUN_800B445C`: `!` when a charged ball is hit back, and the damage of a charged hit, in font 1 for 30 frames) are placed over the ball's projected position. They rise one pixel per frame (`FUN_800B4350`; eight slots in a linked list at `0x800B6C58`).

**Ball and court drawing** (ported in [`tools/research/ball_sim.py`](../../../tools/research/ball_sim.py) with the PsyQ GTE library of `projection_sim.py`; verified by `verify_ball_sim.py`):

- **The ball** (`FUN_800B3198`) is a 42-vertex sphere: 16 triangles (vertex indices at `0x800B6748`) and 32 quads (`0x800B6788`), Gouraud-shaded, with back faces removed by `NormalClip`. Its matrix comes from the ball's angles (`+0x98`) and position (`+0x68`). A hit squashes it along an axis (`+0x148`) by `+0x150`/4096: scale 1 − s along the axis, 1 + s across it. The stage's point light (`0x8009E988`, power `0x8009E994`) points the light matrix at the ball (`FUN_8003A210`); the light matrix's first row is doubled, and every vertex colour comes from `ColorMatCol` with the vertex normal (`0x800B65F8`), the ball type's face colour (`0x800B6828 + 64·type`: 8 triangle and 8 quad colours) and its specular power (`0x800B6460 + 24·type + 0xC`); the back colour comes from the same record (`+0xD..0xF`). Kind 4 pulses the back colour (`FUN_8004E2C8`, frame counter × 16). Kinds 0, 1, 2, 5 and 8 draw it flat instead: 0 fades from black (−8·k), 1 to white (8·k − 1) by the strength `+0x147`, and 2, 5 and 8 are white. The ball goes to the scene OT at its depth (the 2D OT for kinds 0 and 10) and is not drawn beyond depth `0x4000`.
- **Kind 2** also draws four additive streaks from the ball's centre to the top and bottom of the screen, 8·k pixels wide and jittered by `rand()` while the fight runs (held while it is frozen); with k = 5 it spawns 16 sparks (`FUN_800B47B4`, effect type 1 within ±255 units).
- **The shadow** is four flat quads in the stage's shadow colour (`0x80097090 + 0x1C·(stage + 1)`, set when the ball is created) made of the ball's equator ring (vertices 18–25) flattened onto the floor with the ball's yaw and squash. It is scaled in x and z by (4096 + y/2)/4096, where y is the ball's height `+0x6C` (negative above the floor), so it shrinks as the ball rises.
- **The court** (`FUN_800B3DA4`, called with both fighters' z `+0xF70` and the ball record `0x800AE23C`) follows the fighters: its z is the midpoint of their positions. The centre band is 8 additive Gouraud quads 200 units wide from z = −8,000 in steps of 1,536 (brightness 0, 48, 96, 144, 192, 144, 96, 48, 0 along it) and the two side lines are 16 additive Gouraud lines with the same fade, at scene OT entry `0x3F6`.
- **The panorama** (`FUN_800B5CC4` set-up, `FUN_800B5F0C` each frame) is `stg_v`'s 32 × 8 tile map drawn as 32 × 32 sprites, 15 per row. It scrolls with the camera's view-space position (`(x·cos + z·sin) / 96`) and with half the camera yaw change since `0x800AFF88` last changed (the yaw is then recorded in `0x800B6B3C`); with `0x800AFF88` = 1 the panorama is not drawn. A sky tile (33, 58, 148) fills the screen above the map's top edge. That edge is the projection of the point ((x − 6,656·sin) / 4096, 256, (z + 6,656·cos) / 4096), built from the camera position (x, z) and yaw, minus 32 × the map height. The texture word gives u = (w & 7) · 32 and v = (w & 0x38) · 4.

The gauges, the popups and their creation are ported in `draw_sim.py` (`ball_gauges`, `ball_popups`, `ball_popup_add`; the projection in `projection_sim.py`). A popup's text is shifted left by 5, 7 or 12 pixels per character and up by 8, 12 or 20 for fonts 0, 1 and 2. A slot still showing blocks a new popup. `FUN_800B4958` expresses the ball in the frame of the line between the players (camera and CPU), and effect type 15 makes the charged ball glow with the hitter's character flipbook ([effects.md](effects.md)).

## Unlocks

Characters, costumes and modes unlock along a 14-step schedule at `0x800985F4`. `ArcadeUnlocks(n)` (`0x800564C8`) applies its first `n` steps; applying a step twice changes nothing. Two counters drive `n`:

- **Arcade clears** (`FUN_800B2350`, arcade mode only). A clear with character `c` sets bit `c` in `0x800982D8`. Kuma in costume 1 (Panda), Eddy in costume 2 (Tiger) and Gun Jack's second clear set the bit in `0x800982DC` instead. With `k` = the number of distinct characters in `0x800982D8 | 0x800982DC`, the game counts the positions `i < k` whose bit is in `0x83FF` (IDs 0–9 and 15), which gives:
  - `n = k` for `k ≤ 10`;
  - `n = 10` for `k` from 11 to 15;
  - `n = 11` from `k = 16`.

  So any character's first clears count, and clears alone never reach steps 12–14 ([game-bugs.md](game-bugs.md), entry 29).
- **Play count** (`FUN_800567A0`, run by every save-pending update `FUN_8004C678`, that is after every statistics update). The fight counter `0x800982FC` (`u16`) counts updates since the last unlock; every newly applied step or costume resets it. When it reaches 100 (50 once this has happened before, `0x800982FB`), step counter `0x800982FA` grows by one (at most 14) and `ArcadeUnlocks(0x800982FA)` runs. The whole schedule therefore also opens by playing.

The same routine unlocks Start costumes by usage (plays + losses + draws, `FUN_80051948`): Jin at 50, Xiaoyu at 50, Anna at 25 and Gun Jack at 10. It also recomputes `0x800982FF`.

Other routes:

- **Gon.** Beating Gon as the CPU opponent in arcade or Tekken Ball unlocks him (`FUN_8005696C`). The first single-player Tekken Ball game always pits the player against Gon (costume key `0x44`, `FUN_800B528C`, flag `0x800982FE`), and from then on Gon can appear in arcade stages 5–8. Entering the name `GON` on the ranking screen also unlocks him ([name entry](#ranking-screen)).
- **Doctor B.** Beating him in the extra Tekken Force level ([Tekken Force](#tekken-force)).

| Step | Unlock |
|---:|---|
| 1 | Kuma |
| 2 | Julia |
| 3 | Gun Jack |
| 4 | Mokujin |
| 5 | Anna |
| 6 | Bryan |
| 7 | Heihachi |
| 8 | Ogre |
| 9 | True Ogre |
| 10 | Tekken Ball mode (`0x80098306` = 1) |
| 11 | Tiger: bit 8 of the Start-costume mask `0x800982D4` (Eddy's Start costume) |
| 12 | Gon |
| 13 | Doctor B. |
| 14 | Everything |

Clearing with all ten original characters opens Theater mode (`0x80098307` = 1). `0x80098306` and `0x80098307` are the menu entries' "new" counters (see [main menu](#main-menu)). `0x800982D4` holds the characters whose extra costume is chosen with Start or △ (costume 2; ✕/○ choose 1, other buttons 0); it is masked with `0x50382` (Law, Xiaoyu, Eddy, Jin, Gun Jack, Anna) and starts as Law only. Schedule step kinds: 1 = character bit in `0x800982D0` (also records it in `0x800982F2` for the memory card title), 2 = Start-costume bit, 3 = Theater, 4 = Tekken Ball, 5 = everything. `0x800982FF` records whether character 19 is unlocked (2) or at least 15 characters are (1).

## Main menu

`title.ovl` runs states 3 (logo, opening movie and title fade; `0x800DB7D4`), 4 (main menu; `0x800DBBD0`) and 5 (options; `0x800DE480`). The title sequence ends in the demonstration fight (mode 6).

**Title sequence** (state 3, ported as `title_sequence` in `menu_sim.py`). The attract step `0x8009831E` chooses what plays: steps 0 and 1 the opening movie 0, step 2 movie 1, step 3 straight to the title. Then:

1. the movie (the player in `title.ovl`, `FUN_800E1614`/`FUN_800E1940`; Start or a failed movie skips to the main menu). The two movies are descriptors 0 and 1 of the player's table (`0x800BA28C`, sector rows at `0x800B9E38`): the opening (XAS sectors 233,673–248,408, 256 × 224, played to frame 1,942, volume 112) and the logo (248,409–251,472, 320 × 240, 276 frames, volume 127, flag bit 3: the screen turns white at its end). A movie that ends normally goes straight to step 3;
2. without a movie (step 3), a white flash: a black screen brightening to white over 25 frames (additive fade level `0x10A + 10·t`, `t` = 0, 10, …, 240), then 11 frames of full white (`0x200`);
3. the title picture (the menu backdrop, kind 5) fading in from white over 86 frames (level `t + 0xFD`, `t` from 256 down by 3);
4. 300 frames of the title with the blinking prompt (`INSERT COIN`, `PUSH P1 START BUTTON`, `PUSH P2 START BUTTON` or `PUSH P1 AND/OR P2 BUTTON` by the connected pads, colour 5, centred at y 364, visible while bit 4 or 5 of the frame counter is set), the Namco logo (a 72 × 16 picture at (151, 388), member 6 of the title archive) and the copyright lines (`©1994 1995 1996 1998 NAMCO LTD.` / `ALL RIGHTS RESERVED`, colour 6 at (45, 412) and (45, 432));
5. a 32-frame fade to black, then the demonstration fight (mode 6) with the attract step advanced.

The whole cycle (transition screens, title sequences, the demonstration, the demonstration fight and the ranking) is traced frame by frame from the game run in the CPU harness (`tools/research/flow_trace.py`, scenario `attract`), which the remake's `GameFlow` matches.

Start at any point advances the attract step and goes to the main menu (sound `0x4CC0`).

The main menu lists ten entries (`0x800B9464`, 8 bytes: string pointer, mode byte, a two-player flag, an index):

| Entry | Mode | Condition |
|---|---:|---|
| ARCADE MODE | 0 | — |
| VS MODE | 1 | Needs both controllers; skipped by the cursor otherwise. |
| TEAM BATTLE MODE | 2 | — |
| TIME ATTACK MODE | 3 | — |
| SURVIVAL MODE | 4 | — |
| TEKKEN BALL MODE | 7 | Shown when `0x80098306 ≠ 0`. |
| TEKKEN FORCE MODE | 8 | — |
| PRACTICE MODE | 5 | — |
| THEATER MODE | 10 | Shown when `0x80098307 ≠ 0`; goes to state 19 (`ending.ovl`). |
| OPTION MODE | 9 | State 5. |

Up/down move the cursor (wrapping, sound `0x546C`), Start or a face button (`0x8F0`) confirms (sound `0x4D87`). The cursor is remembered in `0x80098320`. After 480 frames without a choice the game returns to the title sequence (state 3).

The two flags are "new" counters: an unlocked entry starts at 1 and shows a NEW mark while the counter is below 3; each time it is chosen the counter grows (up to 3). The memory card file title uses the same flag (see [memory card file](#memory-card-file)).

`FUN_800DAF2C(mode, player)` starts a mode:

- it copies the options into the fight variables (difficulty `0x800AE6D0`, round time `0x800AE3C0`, fight count `0x800AFF70`, guard damage `0x800AFF20`, character change and quick select into `0x800AFF5D/5E`);
- it applies each player's button layout;
- it sets the per-mode feature bytes `0x800AFF54..0x800AFF5C`, the team sizes and the survival counters;
- it goes to state 7.

## Options

`GAME OPTION` items (`0x800B96AC`, 20-byte records `(variable, label, value strings, kind/count/default, layout)`); values stored in the save block:

| Item | Variable | Values (default in bold) |
|---|---|---|
| DIFFICULTY LEVEL | `0x800982E6` | EASY, **MEDIUM**, HARD |
| FIGHT COUNT | `0x800982E7` | 1, **2**, 3, 4, 5 (rounds to win) |
| ROUND TIME | `0x800982E8` | 20, 30, **40**, 50, 60 SEC |
| CHARACTER CHANGE AT CONTINUE | `0x800982EA` | **NO**, YES |
| GUARD DAMAGE | `0x800982E9` | **NO**, YES |
| SELECT CURSOR HOLD | `0x800982F9` | **NO**, YES (keep the last character, `0x800982EE/EF`; otherwise the cursor restarts at `0x58`) |
| QUICK SELECT | `0x800982F0` | **NO**, YES |
| BGM SELECT | `0x800982E5` | **ARRANGE**, ARCADE, SILENT |
| SPEAKER OUT | `0x800982E4` | MONO, **STEREO** |

ROUND TIME has a sixth value shown as the infinity glyphs (`"  abc"` in the value table, index 5); the mode setup (`FUN_800DAF2C`) sets the infinite-time flag `0x800958D4` for any value above 4 (the timer still starts at `(option + 2) · 600` but does not count down).

**Options screen** (state 5, `0x800DE480`; ported with its drawing in [`tools/research/menu_sim.py`](../../../tools/research/menu_sim.py)). Six page records at `0x800EB2F0` (0x34 bytes: cursor, sub-state, title x/y, list x/y, line spacing, value-column width, item table, title, item count, the byte to set on Select and its value). The page byte `0x800EC5E8` selects 0 OPTION MODE, 1 GAME OPTION, 2 RECORDS, 3 MEMORY CARD, 4 KEY CONFIGURATION, 5 DISPLAY ADJUST, 6 leave (back to the main menu through the transition screen). Every page is drawn over the options backdrop (six 128/112 × 256/224 pictures, CLUT rows `0x7D20`–`0x7E60`), with titles in font 1 and items in font 0:

- **List pages** (`FUN_800DCE20` input, `FUN_800DCA90` drawing). Up/down move the cursor (wrapping, sound `0x546C`), left/right change a value (wrapping). The item under the cursor is colour 5 on a pulsing bar (`0xFF4020` scaled by the triangle wave, 22 pixels high, 3 pixels around the text); other items are colour 10; a value equal to its default is colour 1, otherwise 6; values are right-aligned in the value column (9 pixels per character). Select resets the page byte to the page's "back" value. The title is colour 1, or 6 when `0x800982EB` is 0; holding exactly L2 + R2 + Select (`0x103`) and pressing Select on the OPTION MODE list toggles that byte.
- **GAME OPTION** also shows, right of the list, the modes the item under the cursor applies to (`FUN_800DC914`): one 96 × 14 picture per mode from `0x800EB45C` (Tekken Ball only once unlocked), greyed (CLUT `0x7E5E`) when the item's mode mask (item `+0x12`) lacks the mode, on a black box with a grey translucent frame.
- **RECORDS** (`FUN_800E0E2C` builds, `FUN_800E10E8` runs). Four sub-pages, left/right to change, up/down to scroll when there are more than 10 rows, any face button to leave. Rows start at y 146, 20 pixels apart: rank (`1ST`…, `TH` from the fifth) at x 18, the name centred at x 126, then: CHARACTER TIME ATTACK DATA (the ten starting characters plus every character with a time, sorted by time, `mm'ss"cc` at x 198 and the record holder's name at x 306); GREATEST SURVIVORS DATA (the ten survivor records: wins right-aligned in three digits with `WIN`/`WINS`, name); CHARACTERS DATA (unlocked characters by fights played: share of all fights in per-mille shown as `12.3%` at x 225, colour 1 for 100 %, and the count at x 288); WINNING AVERAGE DATA (by wins·per-mille + fights: rate at x 171, wins at x 234 and losses at x 288). Headers at (117, 126), the sub-page title centred at y 90, `PAGE:n`, and the help lines with the pad pictures at the bottom.
- **MEMORY CARD** (`FUN_800DDED0`). CARD SAVE (`FUN_800DD544`), CARD LOAD (`FUN_800DD198`) and turning AUTO SAVE on (`FUN_800DD9E4`, which first saves in test mode `-1`; auto save is kept only when that works) show a Start/cancel prompt and then one result message, centred at y 360 in font 0: `SAVE OK!`/`LOAD OK!` (colour 1), `SAVE ERROR!`/`LOAD ERROR!`, `NO MEMORY CARD!` (colour 2), `CARD IS FULL!`, `NO TEKKEN3 FILE!` (colour 5), `INITIALIZE MEMORY CARD?` (colour 7, then Start formats and saves) and, for a result the screen does not expect, the leftover `SOMETHING MESSAGE` (colour 3). Card calls are retried twice, and twice more for an unformatted card. Select + Start does not leave the options while a save or load screen is up.
- **KEY CONFIGURATION** (`FUN_800DF630`). Each pad button gets an action: LP, RP, LK, RK, LP+RP, LK+RK, LP+LK, RP+RK, LP+RK, LK+RP, STEP (two codes, drawn with an up and a down arrow), NO USE (codes 0–12). Each player has 8 bytes (`0x80098308`, `0x80098310`) for L2, R2, L1, R1, △, ○, ✕, □; the default is `12, 12, 12, 12, 1, 3, 2, 0` (shoulders unused, □ LP, △ RP, ✕ LK, ○ RK). Both players are shown side by side (184 pixels apart): the pad picture (analog pads use the second picture), eight button boxes that open into the 13-action list while the button is held (8 frames to open; up/down then choose; actions used by another button are colour 10), VIBRATION (YES/NO, △/✕ toggles it and buzzes pattern 13), DEFAULT and EXIT. Select, or EXIT when no box is open, leaves and re-reads the layout.
- **DISPLAY ADJUST** (`FUN_800DE04C`): the pad moves the picture (x −6…14, y 0…8, `0x80098304/05`), Start restores (−2, 0), any face button leaves. The page draws a cross and frame of 2-pixel lines at the screen centre and edges, the title and two help lines shifted by the offset (x by `offset·91/64`, y by twice the offset; see [bug 35](game-bugs.md)).

## Character select

`select.ovl` (state 9, `0x8011056C`) builds the grid from the list at `0x800B9638`: two rows of eleven positions.

- Top row: Xiaoyu, Yoshimitsu, Nina, Law, Hwoarang, Eddy, Paul, King, Lei, Jin, Gon.
- Bottom row: Doctor B., Bryan, Kuma, Heihachi, Ogre, True Ogre, Julia, Gun Jack, Mokujin, Anna, Gon.

Only unlocked characters (`0x800982D0`) get a cell, and the cursor links (`0x80129CE8`, 12 bytes per cell: index, the cells reached with up/down/left/right, shown flag, character, x, y) are rebuilt from the unlocked ones (`FUN_8010DC04`, ported in [`tools/research/select_sim.py`](../../../tools/research/select_sim.py)):

- Each row's unlocked cells form a ring (left/right wrap). Only the first ten positions of a row get a screen position, 35 pixels apart from x 11 (top row at y 0, bottom row at y 62, plus the layout's offset).
- The shorter row is centred under the longer one and the rows are linked vertically pair by pair; with an odd difference the middle cell of the longer row points at its neighbour.
- The eleventh positions (Gon, cells 10 and 21) are linked into their row's ring but never drawn: moving past either end of the row reaches Gon, with an invisible cursor, and his big portrait appears. While Gon is unlocked, blinking arrows at both ends of the grid hint at this for the first 180 frames of the screen.
- With the bottom row empty the screen uses the one-row layout (`CTX+4 = 0`, 32 × 68 faces from `0x800B93C8`), otherwise the two-row layout with the HUD portraits. The two layouts differ in the values copied from `0x801108FC` (grid and portrait positions, the timer's position and CLUT).

Moving the cursor plays `0x55F5`.

Choosing (`FUN_8010E0D8` in `select.ovl`, `FUN_800530CC` in quick select):

- A face button picks the character: □ costume 0, ✕ or ○ costume 1. △ or Start picks costume 2 when the character is in the Start-costume mask; otherwise △ is costume 0. The pick plays `0x50F4`.
- Cell value `0x58` is a locked character. `0x59` is a character that is unlocked but not available in this selection, such as a team member already taken; each team pick removes the character from the side's available mask.
- The selection timer starts at `20 · T` select-screen frames, where `T` is 60, or `60 + 3·(n − 10)` with `n > 10` unlocked characters; `T` is also stored for the display. It counts down once per frame while both players are choosing (`0x80110738`), and at 0 each player gets the character under the cursor.
- A side without a human is chosen by the other player (state 3; Select hands the choice back).
- Each player's cursor starts at `0x800982EE/EF` (the last pick when SELECT CURSOR HOLD is on).

Start and Select held together (the shoulder buttons may be held too) with Select newly pressed (`FUN_80051304`: `0x800AE230 & 0xFFF3 == 0x900` and `0x800AE3D0 & 0x100`; any mode except the demonstration, where Start alone is enough) returns to the main menu from the select screen and from fights.

Two sides choosing the same character and costume get different costumes (`FUN_8004F334`): the side that chose later changes unless only the other side is a human; costume 0/1 swap, 2 and 3 become 0.

**Select screen drawing** (from the third frame; packets at `0x801210DC + buffer·0x4600`), back to front: the scrolling tile background (8 × 64-pixel tiles moving diagonally, one row pattern per 64 lines) with the three title pictures; the coloured glow behind each big portrait (black → the colour in the attribute word → grey `0xC0C0C0`); the pictures of the layout and a gradient under the grid; the grid faces; each side's cursor (pulsing while choosing, 20 × 16 corner pieces and two 18-pixel halves); the name plate (a 16-pixel-high strip from the character record's plate picture), the blinking start prompt for an empty side, or the mode caption (`TIME ATTACK!`, `SURVIVAL!`, `PRACTICE!`, `TEKKEN FORCE!`, colour 5 font 1, kept 8 pixels inside the screen); the two-digit timer; the Gon arrows; the big portraits (126 × 208, drawn in three bands whose brightness fades in over 32 frames after each change, a CLUT per 64 lines, facing each other); and rising sparks (a 1 × 160 fading streak from a random point of alternating portraits every fourth frame), clipped above the plates.

**Tekken Ball's select** (quick select with `volley.ovl` hooks): the handicap bar becomes a 6-step ball damage choice (`FUN_800B5C4C`); the first side to finish picks the ball type (`FUN_800B569C`): left/right spin the ball to the previous/next type (`0x800B6928`: BEGINNER / BEACH BALL, EXPERT / GUM BALL, GRAND MASTER / IRON BALL) with blinking yellow arrows, a face button confirms, Select backs out. When the ball rests, its name (colour 11), description (font 1, colour 4), `BALL DAMAGE` and `60%`/`80%`/`100%` are drawn (`FUN_800B593C`); the ball itself is the fight's 3D ball renderer (`FUN_800B3198`, render kind 10, in the 2D OT). `FUN_800B5B6C` copies the view matrix from `0x800AE460` (the identity, which `GsInitGraph` `0x80080DFC` stores at start-up: no display-aspect row, so the ball shows flattened) and translates it by (−0x40, 0x440, 0x1380); with H 500 and offsets (192, 240) the resting ball's centre is at (185, 348). The CPU harness skips that library set-up, so there the matrix is zero and every vertex lands on the centre.

**Quick select drawing** (`FUN_80055878`, packets at `0x800B94E8 + buffer·0x3C00`; ported in `select_sim.py`): a 16-frame fade-in, `VS` (colour 7, font 2, at (161, 348)) or the VS handicap bars (`arcade.ovl` `FUN_800B3204`: 8 segments per side, `LIFE` and ` 70%`…`140%`, sliding 24 pixels a frame) with the VS record (`FUN_800B2D44`: wins in colour by hundreds, `-`, `DRAW`); each side's picked members (HUD portraits in rows of four, 36 × 64 apart); the cursor frames; per side the team size choice (`1`–`8`, `n PLAYERS ON TEAM`), the name under the cursor on its plate, `NO ENTRY` (colour 9) for a locked cell, `SOLD OUT` (colour 5) for a taken one, the start prompt or `PLEASE WAIT!`/mode caption; the screen title (`PLAYER SELECT`, `VS BATTLE SELECT`, `TEAM BATTLE SELECT`; after 480 idle frames it slides out and `PUSH START+SELECT TO EXIT` slides in); the 21 portraits (the ones under a choosing cursor highlighted); the mode picture, the scrolling stripes and `THE KING OF IRON FIST TOURNAMENT 3` banner, two gradients per mode colour pair (`0x80022DB8`) and a black tile.

**Quick select.** When `FUN_80051204` finds any of bytes 0, 2 and 3 of `0x800AFF5C` set, the fight flow goes to state 10 instead of loading `select.ovl`. That covers VS, team battle and Tekken Ball (byte 0 set by `FUN_800DAF2C`), the QUICK SELECT option (byte 2), and byte 3: a challenger joining with Start while holding L1 + R1 (pad word exactly `0x80C`, `FUN_80051244`). State 10 (`0x80055878`) is a resident select screen: a 3 × 7 grid of 6-byte cells `(x, y, id)` at `0x800229D4`, with the same pick rules (`FUN_800530CC`):

- Law, Ogre, Kuma, Mokujin, Julia, True Ogre, Paul;
- Xiaoyu, Yoshimitsu, Nina, Heihachi, King, Lei, Jin;
- Hwoarang, Doctor B., Bryan, Gon, Gun Jack, Anna, Eddy.

## Enbu (attract demonstration)

Game state 6 runs `enbu.ovl` (EMBU, 演武): two fighters perform scripted move sequences with a camera reel, as part of the attract loop. The attract step `0x8009831E` cycles 0 → 1 → 2 → 3 → 0 (`FUN_8004FB58` advances it); when the game returns to the title (`FUN_8004FBE0`) at step 1 it goes to state 6 instead. The demonstration number `0x80098300` (0–2) then advances by one, or is chosen by the buttons held at that moment: R1 = 0, L1 = 1, L1 + R1 = 2. Numbers above the unlocked maximum `0x800982FF` fall back to 0. That maximum is 0 at first, 1 once 15 characters are unlocked, and 2 after the unlock flag `0x800982D0` bit 19.

Each demonstration loads its own model archive `enbmdl<n + 1>.arc` (BNS 1–3, logical 69–71): 13 or 15 pairs of a `.kmd` model and its TIM sequence, then two `TK3psSDW` shadow meshes. A costume slot `s` maps to pair `0x800B99A4[45·n + s]` (model = member `2·pair`, textures = member `2·pair + 1`, shadow = member `0x800DDE30[n] + fighter`). Stage 4 is used, and music track 0 plays.

The script at `0x800B945C + 0x1C2·n` is a list of 10-byte events `s16 frame, kind, a, b, c`, run when the frame counter reaches `frame`:

| Kind | Effect |
|---:|---|
| 0, 1 | Fighter 0 / 1 changes to costume slot `a`; the model is reloaded over the next frames. |
| 2, 3 | Fighter 0 / 1 plays move slot `a` from pose frame `b` to `c`, advancing one frame per frame, with its frame events. |
| 5 | Start a fade with speed `a`. |
| −1 | End. |

The three scripts share the timing and moves (slots `0xD6E–0xD83`, 45 events ending at script frame 3,542, about 59 s) and differ only in the costumes: demonstration 1 uses the second costume of the characters of demonstration 0, and demonstration 2 uses 15 other characters. The fighters start in costume slots `0x0C`/`0x00`, `0x0D`/`0x01` and `0x17`/`0x1E` (constants in `FUN_800D3D64`). A costume value is a costume slot: `FUN_80036440` looks up its costume key (the first index of the slot in `0x80095CE8`, so `charId = key / 4`). The motion bank is embedded in the overlay (`0x800DDE34`, type 98, 22 moves; `FUN_800D47E4` relocates and links it for both fighters). The camera plays the stream reel of the bank's ids `0x2B, 0x2D, …` ([camera.md](camera.md#camera-streams-bank-section-8)): 22 streams of 3,572 frames in all, more than the performance's 3,545 reel steps, so the demonstration never reaches the director.

**Sub-states** (`FUN_800D3844`, `0x800AE6EC`). `enbu.ovl` also shows the title screen, with a copy of `title.ovl`'s picture routine (`FUN_800D2C30` = `FUN_800DAAD8`, kind in `0x800DDE28`, packets at `0x8010A5FC + buffer·0xF00`):

| Sub-state | Action |
|---:|---|
| 0 | Allocates buffers (`FUN_80055B6C(4)`), sets the display offsets, mode 6, both controllers to 0, stops the music. |
| 1 | Resets the performance (`FUN_800D3CCC`) and links both fighters' motion banks to the demonstration's bank (`FUN_800D47E4`). |
| 2 | The performance (`FUN_800D3D64`, one call per frame until the script's end event; 1 + 5 + 3,543 frames). Its first frame sets up stage 4 (lights, floor, panorama), both fighters at the origin facing +x (`facing = heading = 0x4000`), their flipbooks (set 0 from character 9's copy, set 1 from character 4's; `0x800CB710`), models and move slot 0, the camera (`CameraReset`, which also fixes the projection distance at 500, and the reel start `FUN_800673E4(1)` with its first step), and starts music track 0. It then waits for the music (`FUN_8006BCC8` returns 0) with a counter from 4 to −1, taking one reel step on the last wait frame; nothing is drawn during the wait. From then on every frame runs the due script events, draws the camera of the previous frame (`CameraFrame`), steps each scripted fighter, takes a reel step (`FUN_800673E4(0)`; the director `FUN_800D47C0` would take over once the reel ended), draws the fade (`FUN_8004E2E8` at level + 256, brightening to white; the level stops at 256 and grows by the event's speed), advances the script frame and copies each fighter's pose frame to `+0x5A`. A stepped fighter gets pose and root frame `frame + 1`, its frame events (`MoveEvents` — for both fighters, [game-bugs.md](game-bugs.md) #49), and `FUN_8003AA6C` (lights and `FighterAnimate`, which also draws the fighter); its move's head look-at flag (bit 30 of `+0x24`) is cleared around both calls, and transition blending is off (`0x800972CC = 1`). Only fighters stepped this frame are drawn: a fighter whose move has ended, or whose costume is changing, disappears. Sounds are silent because the performance never runs `FighterSounds`, and there is no blinking (`FighterAnimate` skips `FUN_80034354` in game state 6). A costume change (kinds 0/1 with a new slot) sets the costume at once and reloads the model over the next frames: a count from 2 to −1, then load the members, set up the model (drawn with the new costume from here on), set up the parts; a move event on that fighter restarts its move and ends the reload. A move event (kinds 2/3) looks the move up only when the slot changes. The runner is traced frame by frame from the game's own code (`tools/research/enbu_harness.py`). The [Ogre scene](#match-flow) (`ogre_scene_sim.py`) uses the same event format with a similar runner. |
| 3 | Uploads the title pictures (the Tekken 3 logo archive `0x800B9E60`, the same picture as `title.ovl`'s). Nothing is drawn on this frame. |
| 4, 5 | The title fades in from white: fade level `t + 0xFD` with `t` from 256 down by 3 per frame (86 frames). |
| 6 | The title with the start prompt for 300 frames. |
| 7 | Fade to black over 32 frames (level `t − 8`, `t` from 256 down by 8). |
| 8 | Advances the attract step and starts the demonstration fight (`FUN_800D3028(6, 0)`, mode 6). |

Start in any sub-state after 0 returns to the main menu (sound `0x4CC0`). Sub-states 4–7 are ported in `menu_sim.py` (`enbu_frame`). The overlay's other routines:

- `FUN_800D37BC`: clears the screen borders around the display area.
- `FUN_800D3B70`–`FUN_800D3BE0`: model and texture members of the demonstration archive.
- `FUN_800D47E4`: links the motion banks of both fighters to the demonstration's bank.
- `FUN_800D47C0`: the camera director.
- `FUN_800D483C`, `FUN_800D4A5C`, `FUN_800D4F68`, `FUN_800D4BDC`, `FUN_800D50F8`: a copy of the floor renderer ([stages.md](stages.md#floor)) with flat grey (103) `POLY_FT4` tiles instead of Gouraud ones. It builds the texture palette, finds where the camera's view meets the floor when it looks steeply down, and draws 10 × 10 tiles of 1,800 units around that point.

## Pre-fight VS screen

Game state 11 (`0x80052808`) shows the screen between character select and the fight. Its state `0x800AE6EC`:

- 0: clears the display (`FUN_80029860`);
- 1: clears the object table and calls the mode's setup, then loads the background (`makuma00/01.tia`) and the two portraits (`face_b*.tiz`) when they differ from the cached ones ([compressed-tim.md](../formats/compressed-tim.md#runtime-use)); sets the slide counter `0x800B937C = 8`;
- 2: draws, counting the slide counter down to 0 (8 frames);
- 3: draws once more with everything in place;
- 4: goes on to the next game state; the last frame stays on screen while the fight loads.

**Objects.** The screen is a table of 64 objects of 0x28 bytes at `0x800B9380` (`+0` type, `+4/+6` final x, y, `+8/+10` slide offset). While the slide counter `n` is positive, an object is drawn at `final + n · offset / 8`, so everything moves in over 8 frames.

| Type | Drawn by | Object |
|---:|---|---|
| 1 | `FUN_80051C9C` | Background. While sliding, a black `TILE` 368 × 480. At rest, the 42 `.tia` members as a grid of 7 rows × 6 columns of opaque raw-textured quads (`0x2D`): texture page 13 (VRAM x 832), 32 × 32 texels per cell, member `i` with CLUT `(16·(i mod 16), 500 + i div 16)`. Column edges x = 0, 69, 137, 206, 274, 343, 411 (`0x800228C6`), rows 64 pixels tall from y = 20 (`0x800228D8`). The last column is only 12 texels wide; the screen ends at x = 368. |
| 3 | `FUN_80051E74` | Mode caption bar (`FUN_80051FC4`): an opaque `TILE` in the mode colour at (0, 36), width − 110 by 36, then a colour-to-black gradient quad over the last 110 pixels, drawn twice with semi-transparency modes 1 and 2 (`0x800228F4`). Colours (`0x80022900`, RGB) and widths (`0x8002291C`): variant 0 (104, 0, 128), 1 (216, 0, 8), team (240, 48, 24), survival (0, 192, 160), practice (0, 192, 192), Tekken Ball (248, 56, 96), Tekken Force (144, 112, 248); width 216 (practice 248, Tekken Force 232). |
| 4 | `FUN_80052394` → `FUN_800520A0` | Portrait (`FUN_800523FC`): 126 × 212 texels of the `.tiz` from texel row 20, drawn opaque (`0x2D`, CLUT entries `0x0000` are transparent) at (x + 2, y + 6), mirrored for the facing bit of the character record (flipped for player 2). A light grey frame (`TILE` (232, 232, 232): rectangles (0, 0, 130, 6), (0, 218, 130, 6), (0, 6, 2, 212), (128, 6, 2, 212), `0x8002292C`) and an additive tint (semi-transparency mode 1): black to the character's colour over the upper half, the colour to (192, 192, 192) over the lower half. The colour is the character record's first word shifted right by 8. |
| 7, 8 | `FUN_80052538` | Text (`FUN_800525DC`, printed by `FUN_8004D15C` with the HUD codes `%c%f%H%V`, [hud.md](hud.md)). Type 7 appears only at rest; type 8 (character names, `FUN_80052650`) also slides. Names use colour 8, font 3, 21 pixels per character, clamped to x 12–356; a negative x right-aligns. |
| 2, 5, 6 | overlay | Team battle: the team members' order (`FUN_800B3928`): HUD portraits (type 5) for every member except the one now fighting, starting with the members after him, then the defeated ones dimmed (flags `0x68`); members beyond the team's current count show as locked. They are placed from `0x800B0B9C` (per side x, y, step, and the x used for eight members), with a light grey frame (type 6) around them; type 2 draws the team bars. |

**Per mode** (the overlay setup, [overlays](#overlays)): every mode places the two portraits (arcade: player 1 at (12, 100) sliding from 160 to the left, player 2 at (226, 210) from 160 to the right, `0x800B4ED0`) and the names (`0x800B4EE0`), prints `VS` (colour 0, font 2, at (162, 250)) and a caption line at (28, 42) with font 1 and colour 6: `STAGE n` in arcade and time attack (the fight index `+0x24` + 1), `STAGE 1` in the demonstration, `FIGHT n` in VS (the match count `+0x28` + 1), team battle (the team round byte `+0x58` + 1) and survival (the win count `+0x44` + 1), `PRACTICE MODE`, `TEKKEN BALL`, and `TEKKEN FORCE` with `STAGE n` / `FINAL STAGE` below it. The caption bar and background kind: arcade and time attack use the human count (one or two humans), VS and the demonstration kind 1, team battle bar 2, survival bar 3 on background 0. Sub-states 0–4 with the `arcade.ovl` set-ups are ported in `draw_sim.py` (`vs_frame`, `vs_setup`). Tekken Force shows only the player's portrait and lists the enemy names on the right (`force.ovl` `FUN_800B6648`).

## Match flow

`FightMain` (state 8, `0x80050710`) runs the matches of every mode. The mode context at `0x800AFF50` is passed to the overlay hooks. It holds the human count (`+0x1C`), the human mask (`+0x1D`), the human and CPU fighter indices (`+0x1E`, `+0x1F`), the arcade fight index (`+0x24`), the ladder (`+0x90`, [arcade ladder](#arcade-ladder)) and the Ogre-scene flag (`+0xBC`).

| Sub-state | Action |
|---:|---|
| 0, 1 | Character select (`select.ovl`, state 9, or quick select, state 10), then the mode's start hook. The demonstration skips select. |
| 2 | Next fight: the mode's fight hook (CPU level, ladder entry), stage and music (`StageAndMusicSelect`), then the VS screen (state 11), which returns to sub-state 3. |
| 3–7 | Load the fighters; start the fight at least 60 frames after the VS screen began. |
| 8 | The fight: `FightFrame` every frame. When `RoundFlow` hands over (round state 9), the fight goes to sub-state 5 for the next round, or when the match is over (`0x800AFF71`) to the mode's end hook. Round state 10 starts the Ogre scene, round state 7 (Tekken Force area change) sub-states 21–23, and round state 11 (the practice menu's exit) the main menu. The demonstration fight (mode 6) ends as soon as its first round is decided (round state above 2): it goes to the ranking (state 16), or to the title at attract step 3. |
| 9–10 | Continue. |
| 11–12 | Game over. |
| 13–14 | New challenger. |
| 15–20 | Ogre scene. |

End hooks (arcade overlay unless noted):

- **Arcade** (`FUN_800B134C`). With one human, a win moves to the next ladder fight; after the tenth the game goes to the ending (state 19). A loss leads to the continue. With two humans the winner goes on and the loser drops out.
- **VS** (`FUN_800B15CC`): the win and draw statistics, then back to select.
- **Team battle** (`FUN_800B16F0`) records each fight's outcome (`+0x38`) and defeated members. When a side has no members left it goes to the team result (state 12).
- **Time attack** (`FUN_800B197C`): like arcade. After the tenth fight it records the time ([records](#records)) and shows the time attack result (state 13).
- **Survival** (`FUN_800B1B10`): each win counts per defeated character (`+0x60`, 22 `u16`) and in total (`+0x44`). The loss records the run and shows the survival result (state 14).
- **Tekken Force** (`force.ovl` `FUN_800B61D4`): losing stores the high score and goes to game over, without a continue. Clearing the last level shows the Tekken Force result (state 15). That level is level 4, or the Doctor B. level when it was earned.

**Pause** (every mode but practice, which has its own menu). `FUN_8002B9EC` runs each fight frame:

- Start from an active player pauses while the round is in progress (`RoundFlow` state 1) and the mode allows it (`0x800AFF54`). `0x800958B0` holds the pausing player (1 or 2), and `0x800958B8` repeats it while the fight runs (`0x80095884`).
- Pressing Start again does not unpause; only CANCEL does (or practice's resume request `0x800958AC`).
- On pausing, the music volume drops to `0x1E` (`FUN_8006BF80(0x1E, 20)`) and the menu cursor `0x80098DDC` is set to `0xFF`; on unpausing, the volume returns to `0x7F`.

While paused, `FightFrame` draws the frozen scene and calls `FUN_80078498(player)`. It opens the menu (cursor 0, sound `0x50F4`, `FUN_8004B920(0)`), then shows the chosen page (`0x80098DDD`): 2 the move list (`FUN_80079298`), 4 Tekken Ball's HOW TO (`volley.ovl` `FUN_800B4088`), else the menu (`FUN_8007854C`):

- **Items**: `CANCEL`, `COMMAND`, `RESET`, plus `HOW TO` in Tekken Ball (`0x80098DE0`). They are centred on x 184 from y 104, 20 pixels apart, in font 0: colour 2 on the cursor, else 6.
- **Box**: a dark blue tile, RGB (0, 16, 48), at (148, 100), 72 × 65 (85 in Tekken Ball), over a light grey (224, 224, 224) tile at (147, 98), 74 × (box height + 4).
- **Title**: `1P PAUSE` / `2P PAUSE` (colour 5, font 1, y 120), blinking with bit 5 of the frame counter, at x 32 for player 1 and at screen x + width − 136 for player 2.
- **Clipping**: draw areas limit the frozen scene around the box (the display less 32 lines, the box band y 98 to 98 + box height + 4, and the scene's OTs).
- **Input** (the pausing player's pad): up and down move with sound `0x546C`, wrapping. A face button or Start stores the choice + 1 in `0x80098DDD` (sound `0x50F4`) and keeps the menu inert for 2 frames (`0x800A8B3A`).
- **Choices**: CANCEL unpauses. RESET (3) is the value `FUN_80051304` treats as leaving to the main menu.

The HOW TO page (`FUN_800B4088`) shows a 216 × 204 picture (CLUT `0x7C04`, texture page `0x1A`) at (76, 128) on a light (240, 240, 240) frame at (64, 112), 240 × 236, with a black shadow 6 pixels right and 8 down. A face button or Start returns to the menu (sound `0x50F4`, the menu stays inert for 3 frames).

Ported in `screens_sim.py` (`pause_update`, `pause_menu`, `pause_menu_draw`, `how_to_page`).

**Move list** (the pause menu's COMMAND page `FUN_80079298`, and practice's COMMAND LIST `FUN_8007906C`). Each list is a 182-pixel column: player 1's on the left, player 2's from x 184. Tekken Force shows the player's only; otherwise every active side's list is shown. `PUSH BUTTON TO EXIT` is at y 440. On the COMMAND page a face button or Start returns to the menu (sound `0x50F4`). A list (`FUN_800789E4`, member 4 of the character's ARC copied to `0x800A39D0 + 0x232·player`: a count, then name / command string pairs):

- **Rows**: six moves 64 pixels apart from y 118, over the title (glyphs 6–10 of the atlas at (60, 97)) and between two light lines at y 114 and 435, on a dark column (y 92, 368 high).
- **Text**: the name at y + 6, or on two lines (y, y + 12) when it is wider than 28 half-cells (joiners and half spaces count 1, everything else 2). The command is at y + 39. Both are drawn with the colour `0x707070` and the player's glyph atlas (font 0 or 1).
- **Boxes**: each row is a Gouraud box from dark blue (16, 32, 96) at the top to light blue (70, 146, 184) at the bottom, with a light grey frame (208, 208, 208).
- **Hwoarang** (character 6): moves 6–13 are green (0, 64, 32) → (85, 162, 95) and 14 onwards gold (64, 48, 16) → (160, 144, 32). The first move of each group is a header drawn as a plain bar.
- **Mokujin** (character 15): a single row at y 246.
- **Scrolling**: up/down moves by one, left/right by five when up/down is not held, wrapping (sound `0x546C`). The list slides 64 pixels per step and eases in, keeping two-thirds of the remaining offset each frame (`0x800A39C0`: cursor, offset per player).

The text engine is `MoveTextDraw` ([arc-archives.md](../formats/arc-archives.md#move-text-rendering-japan-rev1)). Everything is ported in `tools/research/command_list_sim.py`. The arrows and button diagrams (and practice's key display) sample texture page 6 at VRAM (384, 224): `title.ovl`'s compressed archive at `0x800D4FB8` (one 35 × 32 TIM), uploaded by `FUN_8004CD28` on the title and at the main menu's sub-state 0 and left in VRAM for the fights; the button CLUTs at rows 508–509 come from the system archive.

**Continue** (sub-states 9–10):

- Setup: system sound `0x16`, the music fades (`FUN_8006BF80(60, 60)`) and a timer of 808 frames starts (`FUN_800502C8`). The fight scene keeps running behind the prompt.
- `FUN_800502D8` shows `CONTINUE? n` (colour 9, font 2, at (63, 200)), with `n = (timer + 90) / 90`: 9 for the first 88 frames, then each digit for 90 frames. When a digit from 8 down to 1 appears (`(timer + 90) mod 90 = 89`), system sound `4 + n` plays (`FUN_80040E98(0x1004 + n)`; that wrapper calls `SoundPlaySystem(id & 0xFFF)`). Ported with its drawing in `screens_sim.py` (`continue_countdown`).
- A face button takes 90 frames off the timer.
- Start continues (sound `0x4CC0`). With CHARACTER CHANGE AT CONTINUE off (`0x800AFF5D = 0`) the same fight restarts (sub-state 2). With it on, the player returns to select (sub-state 0).
- When the timer runs out, the game is over.

**Game over** (sub-states 11–12): system sound `0x17`, music track 3, and `GAME OVER` (colour 1, font 2, at (85, 200)) for 121 frames, then the ranking (state 16). Sub-states 9–14 (continue, game over, new challenger) are ported in `screens_sim.py` (`fight_main`), with `FightFrame` as a hook.

**New challenger** (sub-states 13–14). A player who is not playing can join when the mode allows it (`0x800AFF55`), from the eighth frame of a fight on:

- Pressing Start marks the player active (`FUN_80051244`); with L1 + R1 held, quick select is also requested ([quick select](#character-select)).
- Sound `0x49A1` plays and the music fades out over 30 frames.
- With quick select the game goes straight to sub-state 0.
- Otherwise it shows `A NEW CHALLENGER` / `ENTERS!!` (colour 7, font 2, at (8, 288); visible while bits 3–4 of the counter are set) for 66 frames. The counter starts at 8, and `select.ovl` starts loading at count 40. The fight freezes (`0x8009588C`: `FightFrame` only draws) once the round is past its intro or after 16 frames.

**Ogre scene** (`FUN_800514EC`, checked at every round hand-over). It starts when all of these hold:

- the mode is arcade or time attack;
- it is the tenth ladder fight (Ogre);
- there is exactly one human and no challenger joined (`0x800AE6DA`);
- the scene has not played yet (`+0xBC`);
- the CPU has fewer round wins than needed and the human has at least one.

So it follows the first round the player wins against Ogre. Time attack skips the scene itself and goes straight to the reload.

The sub-states:

- **15–16** (`FUN_800B4168`): the human's fighter record is reloaded as the stage-9 boss, in the costume of ladder entry 8. That boss is Heihachi (costume slots 26/27), or Jin (slots 18/19) when the player is Heihachi. Both fighters are placed at the origin.
- **17** (`FUN_800B4528`) runs a scene script in the [Enbu](#enbu-attract-demonstration) event format (`0x800B0BF0` when the human is fighter 0, `0x800B0C24` otherwise):
  - frame 2: music track 5;
  - frame 10: the boss plays move slot `0x8B4` and Ogre slot `0x8B3`, both from Ogre's bank (`divmot14`, rows `0x149` and `0x148`, 255 frames, no sound or frame events), pose frames 0–255. Sampled with `tools/research/motion.py`, the boss starts lying on the floor (root height about 150) while Ogre bends down (root 1,040 → 660); from pose frame 96 Ogre's right hand rises from about 150 to 2,050 and the boss's root follows to about 2,100 by frame 168, so Ogre picks the defeated boss up and holds him overhead until the fade;
  - frame 192: a fade at speed 4;
  - frame 256: the end.

  The human's Start skips it.

  The runner (ported with the set-up in [`tools/research/ogre_scene_sim.py`](../../../tools/research/ogre_scene_sim.py), engine calls as hooks; verified by `verify_ogre_scene_sim.py`) starts the camera (`CameraReset`, `FUN_80069388`, `FUN_800661C0`, reel `FUN_800673E4(2)`), then each frame runs the due events, steps each scripted move one pose frame up to its end frame (with the move's head look-at flag, bit `0x40000000` of `+0x24`, cleared while `MoveEvents` and `FUN_8003AA6C` run), runs the camera director, the camera frame and a reduced fight frame (see below), and draws the fade (`FUN_8004E2E8` at level + 256, the level growing by the event's speed). A black 368 × 480 tile clears the screen behind the scene, only its top 100 lines from frame 5; once the fade passes 208 the stage stops drawing (`FUN_8004860C`). After the end event it holds a full fade for two more frames. The pause bit `0x800B4F20` would freeze the moves and the fade, but nothing sets it.

  The engine calls of the scene, in order:

  | Call | Role |
  |---|---|
  | `CameraReset`, `FUN_80069388`, `FUN_800661C0` | Camera source 0 at full weight; the camera-choice counter `0x800A086C` wraps to 0–3 (`0x800A086E` from `0x80024528`); the five camera source records (`0x800A06D0`) are cleared, both fighters tracked twice (`CameraTrackFighters`) and the two default eye points set (y −1,450, z −8,000). |
  | `FUN_800673E4(2)`, then `(0)` until it returns non-zero | Starts camera stream `0x4B` from the bank of the fighter whose `+0x16` is 14 (Ogre; [camera.md](camera.md#camera-streams-bank-section-8)), then plays it; when it ends the director takes over (`CameraUseSource(2)`). |
  | `MoveLookup` | The move record of a scripted slot. |
  | `MoveEvents`, `FUN_8003AA6C` | Per scripted fighter: frame events (with the sound bit masked), then `FUN_800363B0` (`+0x7C0` = (`+0x16` = 4) for character 15), the point light towards the fighter (`FUN_8003A210`), the back colour (`FUN_8003A3B8`: stage ambient, Tekken Force's pick-up flash `0x8009E998`, practice's freeze signal; black while the fighter's `keepLight` flag is set, [stages.md](stages.md#lighting)), and `FighterAnimate`. |
  | `CameraDirector`, `CameraFrame` | [camera.md](camera.md). |
  | `FUN_8006DAB4` / `FUN_8004860C` | The stage background and clear tile ([stages.md](stages.md#clear-colour)); after the fade passes 208 only the black clear tile. |
  | `FUN_8003A030` | The fighters' base colour from the stage's light record ([stages.md](stages.md#lighting)). |
  | `BodySphereProfile` | [fight-frame.md](fight-frame.md) step 19. |
  | `FUN_8003A1D8` | Counts the dynamic point light down (`0x8009E994`) and turns it off at 0. |
  | `FUN_80036254` | The shadow matrices: `0x800AE2E8` = the view matrix, `0x800AE310` = view × floor shear `0x800B0018` (with `0x800B08D4` set, an identity rotation with the translation z moved by −2,618 instead). |
  | `FUN_80037B4C` | Counts drawn frames (`0x8009E8F8`) while text is on. |

  The set-up's loader calls: `FUN_80036440(fighter, key)` finds the costume slot of a costume key in `0x80095CE8` (92 entries; `+0x14` slot, `+0x1C` key); `FUN_8006C900` fills the resource request `0x800A0C50` (stage, then four halfwords) and `FUN_8006C924(mask, 1)` marks request bits 1 and 2 as loaded, so the next resource pass reloads only the boss; `FighterLoadCharacter` and `FighterSetupParts` rebuild the model ([pssdw-member.md](../formats/pssdw-member.md), [3dmk-models.md](../formats/3dmk-models.md)); `FUN_8003C4AC` clears `+0x181C`/`+0x1820` and sets `0x800A9234` = 20; `FUN_80048548(6)` rebuilds the clear tiles.
- **20**: ladder entry 9 becomes True Ogre (`FUN_800B2D38`: character `0x14`), stage and music are chosen again and both fighters are reloaded from the selection. The round number and both round-win counts are saved and restored around the reload (`FUN_8002A5D8`/`FUN_8002A634`), so the match continues against True Ogre with the same score. With one-round matches (maximum rounds below 2) the score restarts at 0.

## Result screens

`result.ovl` has one handler per mode (states 12–15). Each one:

- plays music track 6;
- fades in by 8 per frame (`FUN_8004E2E8` brightness, 32 frames);
- ticks with sound `0x55F5` while its lines appear;
- fades out by 4 per frame (64 frames);
- goes to the ranking (state 16).

Select + Start returns to the main menu, as everywhere.

Screens:

- **Backgrounds.** Team battle and survival draw a scrolling tile pattern with the moving banner `THE KING OF IRON FIST TOURNAMENT 3` (`FUN_800F18FC`). Time attack and Tekken Force draw a full-screen 368 × 480 8-bit picture. It is stored in the overlay as a six-member compressed-TIM archive (`0x800B99B4` for time attack, `0x800D8A20` for Tekken Force). `FUN_800F10C8`/`FUN_800F110C` upload it to VRAM (512–703, 0–479, CLUT rows 506–511), and `FUN_800F1150` draws it as six quads. Both pictures show the Tekken 3 logo: time attack on a gold burst, Tekken Force on red lightning.
- **Winner's sounds.** The time attack result always ends with them, and the survival result does when the player placed in the top ten. `FUN_80075A90` plays sound `0xC640` (`0xC64B` for voice set `0x15`), and `FUN_80075B4C` plays `0x86DA` once SPU voice 2 has gone quiet and 15 more frames have passed. Tiger (costume key `0x22`) plays `0x86CA` instead.

| State | Screen | Content and timing |
|---:|---|---|
| 12 | Team battle (`FUN_800EF4AC`) | `TEAM BATTLE RESULT`. Both teams' portraits sit in rows (y 100 and y 192 + 30·(5 − (n₁ + n₂ + 1) / 3)). The fights are replayed one by one, 11 frames each with a tick: the line is drawn over 8 frames, a line joins the two members who fought, red for a player-1 win, yellow for player 2, grey for a draw. A grid of per-fight boxes (`FUN_800EE870`) shows the fight number and both portraits. After the last fight the message slides in over 30 frames with sound `0x50F4`. With one human it is `YOU WIN!`, `YOU LOSE!` or `DRAW GAME`, by the members left. With two humans it is `PLAYER-1 WINS!`, `PLAYER-2 WINS!` or `DRAW GAME`. The screen ends after 1,800 frames. A face button hides or shows the message. Start on either pad starts a new team battle (the player joins, then state 8 from select). Select alone restarts the result presentation from its first frame. |
| 13 | Time attack (`FUN_800EFF4C`) | `TIME ATTACK CLEAR!`. The ten stage rows appear one every 23 frames, in two columns (x 34 and 182, y 64 + 52·k; `0x800B94F4`). Each row has `STAGE n`, the opponent's portrait and the stage time `mm'ss"hh`; the newest row counts up over 16 frames. Then `YOUR TIME` with the total (the sum of the ten stage times, at most 359,999 frames, `0x800F28E8`) and the winner's portrait. `NEW RECORD` blinks when a record name entry is pending (`0x800984DE` bit 0, `0x800F2988`). The screen ends 4,680 frames after it started; Start skips to the fade-out. |
| 14 | Survival (`FUN_800F0A78`) | `SURVIVAL RESULT`. Every character beaten at least once (IDs 0–20) gets a portrait cell with its win count, sorted by wins, descending and stable (`FUN_8004D068`). Counts go up by one every 4 frames with the tick sound. A cell prints only the count modulo 100 (two digits); the digit colour gives the hundreds (colours 6, 5, 8, 9 for 0–99 … 300–399, repeating after that; `0x800B96FC`). `TOTAL` with `n WIN`/`WINS`, then after 30 frames (sound `0x50F4`) the rank line: `YOU ARE THE nST/ND/RD/TH` / `GREATEST SURVIVOR!` for a place in the top ten, or `YOU NEED MORE PRACTICE!`. The screen ends at 4,680 frames; Start skips to the fade-out. |
| 15 | Tekken Force (`FUN_800F1F08`) | `TEKKEN FORCE`, with the player's portrait in a coloured frame (`FUN_800F1C00`; the colour comes from the character record). Counting from the end of the fade-in, lines appear at frame 30 (`YOUR SCORE:`), 60 (`HIGH SCORE:` = the stored `0x800982F4`, with a blinking `NEW RECORD!!` when the run beat it, `0x800AFF8F`) and 90, each with sound `0x4C6C`. What follows depends on the result flags `0x800AFF90`. **Keys** (bits 0–2, before Doctor B. is unlocked): `KEYS:` with `COPPER`, `SILVER` and `GOLD` at frames 90, 120 and 150, then from frame 180 a blinking `TO BE CONTINUED...`. **Saved** (bit 3, Doctor B. was beaten): `YOU SAVED DR.BOSKONOVITCH!` blinking from frame 90, with sound `0x50F4`. **Boss list** (bit 4, Doctor B. already unlocked at the start): `BOSS:` with the four level bosses' portraits, 20 frames apart (`0x800AFF91–94`, character·4 + costume), then `FORCE:` counting the defeated enemies (`0x800AFF8C`) up by one every 2 frames with the tick sound. The screen ends at 4,680 frames; Start skips to the fade-out. |

## Ranking screen

State 16 loads `ranking.ovl`, whose setup (`FUN_800C390C`) makes a backdrop: only the stage is drawn (mode 6), the next one of the cycle 0–12 (`0x800984DD`), skipping stages 5, 6, 7 and 12. The camera circles it at radius 5,000, advancing 3 angle units per frame (`FUN_800C3AAC`). State 17 (`FUN_800C2A24`) shows one of three pages (`0x800984DC`), each with a header picture (compressed TIMs at `0x800B96B4`, loaded with `FUN_8004CC04`):

| Page | Rows |
|---:|---|
| 0 | Character time records: the ten original characters plus every character with a record below 359,999 frames, sorted by time (ascending, stable). |
| 1 | Greatest survivors: the ten entries of the record table, re-sorted by wins. |
| 2 | Character usage: every character used at least once plus the ten originals, sorted by usage, with the percentage of the total (one decimal; `100%` and `0%` printed specially). |

The pages are the [records](#records); rows are 72 pixels apart. The list starts below its end and scrolls (12 pixels per frame) to the last group of five rows, then up by five rows at a time, holding each group for 150 frames, so ranks 1–5 come last. After 60 more frames it fades out (8 per frame). The page number advances by one (mod 3) and the game returns to the title (`FUN_8004FBE0(3)`). Start from either pad goes to the main menu. Holding right, left or up on controller 2 when the ranking starts picks page 0, 1 or 2.

**Name entry.** A new record sets `0x800984DE`:

- bit 0: time attack, with the record pointer `0x80098324`;
- bit 1: survival, with the pointer `0x80098328`, re-sorted first (`FUN_800C1E8C`).

The ranking then plays music track 2 and opens that page, scrolled to the new row, which is highlighted. The entering player (`0x800984DF`) and character (`0x800984E0`) are stored with the flag. `FUN_800C3480` runs the entry:

- **Alphabet.** 40 symbols, `A–Z`, `0–9`, `<`, `=`, `.` and space (`0x800B9674`); left and right on the entering pad cycle through them with wrap-around.
- **Letters.** A face button enters the symbol under the cursor (sound `0x50F4`; moving the cursor plays `0x55F5`). `<` steps back one letter; `=` ends the name, padding it with spaces.
- **Timer.** 3,000 frames, shown in seconds. At 0 the name is completed with spaces.
- **Rejected names.** A complete name that equals one of `"   "`, `AAA`, `SEX`, `SOB` or `AUM` (`0x800CBE44`) is replaced by the first three letters of the character's name (`FUN_8004F2D8`). Start during the entry stores the character's name as well and leaves for the main menu.
- **Gon.** A name completed as the three letters `GON`, not ended with `=`, unlocks Gon (character 17) if he is still locked (`FUN_80056498(0x11)`).

After the entry the record is saved (save-pending flag), and 120 frames later the screen fades out.
## Practice

`practice.ovl` drives mode 5. Its state is a structure `S` at `0x800B9180` (pointer `0x800B904C`); `S+0x84` is the player's fighter index and `S+0x85` the dummy's. MODE SELECT offers FREE, VS CPU, COMBO TRAINING, PLAYER SELECT and RESET (`S+0x77` = sub-mode 0, 1, 2). Each frame `FUN_800B3084` updates the attack data, draws the practice HUD (`FUN_800B6898`), sets the freeze signal and runs the replay control (`FUN_800B8D50`).

**Pause menu.** Each sub-mode has its own cursor (`S+0x78/79/7A`), rows mapped to item ids (`0x800B0A10/1C/28`) and a handler per item (jump table `0x800B0A58`, code at `0x800B4E4C`). Left/right change a value (sound `0x546C`, and `S+0xA7` is cleared); OK resumes (`0x800958AC = 1`). Input (ported in `practice_sim.py`, `menu_cursor` and `menu_input`):

- **Cursor** (`FUN_800B49C4`, `FUN_800B4BA8`): up and down on the repeat pad (`S+4`), wrapping; MODE SELECT has rows 0–4, the pages 0–8 (FREE, VS CPU) or 0–7 (COMBO TRAINING). Moving to another sub-mode on MODE SELECT resets it: FREE turns ATTACK DATA on; VS CPU clears COUNTER ATTACKS and REPLAY SETTINGS; COMBO TRAINING also turns KEY DISPLAY on and the dummy to STAND. All three clear COMMAND LIST, the combo type and `S+0x86`/`S+0x87`, make the player the combo player, and empty the key ring and replay.
- **MODE SELECT choice** (`FUN_800B4C8C`, a face button): FREE, VS CPU and COMBO TRAINING open their page (cursors to 0, sound `0x4CEB`); COMBO TRAINING loads the first combo as the input guide (`FUN_800B7FB4`). PLAYER SELECT ends the round with `RoundFlow` state 9 (back to character select); RESET with state 11 (the main menu).
- **Items**: a face button on a value row sends the cursor back to the first row. COMMAND LIST toggles on a face button and, while on, calls the command list display every frame for the player (and the dummy when it is on CONTROLLER). COMBO PLAYER and COMBO TYPE reload the guide. RETURN TO MODE SELECT reopens MODE SELECT.
- **Frame order** while paused (`S+0x8A`), once the delay `S+0xA9` has run out and text is on: the backdrop (`FUN_800B6DA0`: a dark blue panel (0, 16, 48) with a light grey frame, MODE SELECT at (8, 40) 172 × 192, the pages at (64, 40) 240 × 316), the page and the cursor (these three are skipped while COMMAND LIST is on), then the item input.
- **Key ring** (`0x800B9230`, 50 words; heads `0x800B9368`): `FUN_800B7A88` empties it; `FUN_800B7FB4` copies a combo's steps into it and sets the head to the step count − 1; `FUN_800B8244` restarts the replay from its first entry.

| Item | Sub-modes | Variable | Values (default in bold) |
|---|---|---|---|
| COMMAND LIST | all | `S+0x9F` | **off** / on: shows the command list (`FUN_8007906C`) of the player, or of both players when the dummy is on CONTROLLER |
| TRAINING DUMMY | FREE | `S+0x7D` | **STAND**, CROUCH, STAND GUARD, CROUCH GUARD, GUARD ALL, AUTO GUARD, UKEMI MAE, UKEMI OKU, CONTROLLER (0–8, wrapping) |
| COUNTER ATTACKS | FREE | `S+0x9E` | **OFF** / ON: copied to `0x800958E4[dummy]`, so every clean hit on the dummy outside a reaction is a counter hit |
| CPU DIFFICULTY | VS CPU | `S+0x7E` | EASY, **MEDIUM**, HARD: the AI group |
| CPU LEVEL | VS CPU | `S+0x7F` | STAGE 1, 2, **3**, …, 9, FINAL STAGE: the AI level (`AiReset(dummy, 1, difficulty, level, −1)`) |
| COMBO PLAYER | COMBO TRAINING | `S+0x7B` | **player 1** / player 2: whose character's combo list is used |
| COMBO TYPE | COMBO TRAINING | `S+0x7C` | NONE (−1) or one of the character's combos |
| ATTACK DATA | all | `S+0x9D` | OFF / **ON** |
| FREEZE SIGNAL | all | `S+0x83` | **OFF** / ON |
| REPLAY SETTINGS | all | `S+0x81` | **OFF**, +4 COMBO, +5 COMBO, +6 COMBO, MANUAL (MANUAL not in combo training) |
| KEY DISPLAY | FREE, VS CPU | `S+0xA0` | OFF / **ON** |
| RETURN TO MODE SELECT | all | `S+0x75 = 1` | — |

Items 6, 11 and 12 of the jump table (a toggle of `S+0x87`, face-timer values 9 and 11) are not in any menu.

**Pause menu drawing** (`FUN_800B57AC` → `FUN_800B5834` MODE SELECT, `FUN_800B5978` FREE, `FUN_800B5ED4` VS.CPU, `FUN_800B6368` COMBO TRAINING; ported in [`tools/research/practice_sim.py`](../../../tools/research/practice_sim.py)). The title is colour 10, font 1, at (72, 56) (MODE SELECT at x 16). Rows are font 0 at x 72 (MODE SELECT: x 16, rows 22 pixels apart from y 110); each row's colour is kept in `S+0x8C…` (11, the cursor's row 10). The first row is OK/CANCEL at y 110, then COMMAND LIST at y 132, then the page's items from y 162, 22 pixels apart; values are right-aligned to column 25 (x = 72 + 9·(25 − length)); RETURN TO MODE SELECT is at y 328. FREE shows TRAINING DUMMY on its own line with the setting below it; the tech-roll settings print `TECH ROLL` with an up or down arrow sprite. COMBO TRAINING shows `COMBO PLAYER n-` with the character's name at x 207 and COMBO TYPE (`1`…, or `NONE` when the character has no combos).

**Practice HUD** (`FUN_800B6898`). Prompts at line 21 in font 1 (`PLAY = SELECT`, `PLAY(SEL) REC(DW+SEL)`, `START REC = ANY KEY`, `REC (STOP = SEL)`, `PLAY`, `GUIDE MODE`, `REPLAY = SELECT`). With ATTACK DATA on: `TOTAL DMG:n` for each side (columns 23 and 1, line 3), `DMG:nnn(ppp%)` (line 4; colour 7 when the hit exceeded the previous one, 6 equal, 3 lower), `COUNTER` (colour 2) and `CLEAN HIT` (colour 5) on lines 5 and 6, the big `n COMBO` / `n DAMAGE` counters (`FUN_800B6F58`, font 1 at (12, 136) and (22, 166)), and up to four hit markers (`FUN_800B75AC`, 48 × 48 with a 48 × 16 level label, the unblockable one taller). The key display (`FUN_800B7C84`) shows the last 15 inputs at y 400 from x 12, 23 pixels apart: direction arrows (19 × 31 quads flipped from three pictures, CLUT by guide colour) and the pressed face buttons (20 × 32 icons); with a combo guide loaded the inputs after the guide's end use the second colour.

**Training dummy.** In FREE the dummy's input source is the scripted word (`0x80095894[dummy] = 2`, fighter `+0x408`), written every frame by `FUN_800B87C8`. CONTROLLER instead gives the dummy the second pad, and VS CPU makes it a CPU fighter. Bank type 18 is never driven. While the dummy lies on the ground (move `state & 0x204`) it holds up to stand. Otherwise:

| Setting | Scripted input |
|---|---|
| STAND | Nothing. |
| CROUCH | Down. |
| STAND GUARD | Back while the player's attack can be blocked standing (`attack & 0x10`) and its active window has not ended; otherwise nothing. |
| CROUCH GUARD | Down, or down-back while the attack can be blocked crouching (`attack & 0x08`) until its active window ends. |
| GUARD ALL | Back for attacks blockable standing, down-back for those blockable crouching, until the active window ends. |
| AUTO GUARD | Nothing, but `humanGuard = 1`, so the idle stance guards as a human's does (other settings clear it). |
| UKEMI MAE / UKEMI OKU | During a reaction whose move has an air window and a tech-roll branch (flag `0x1C`), LK+RK (forward) or LP+RP (backward) on every other frame. |

**Freeze signal.** For each fighter `FUN_800B3520` tests whether any branch of the running move (or of its default continuation within the buffer window) can be taken now. The result goes to `0x800AE430 + 4·player` as a colour: `(1, 0, 250, 0)` green when it can act, `(1, 250, 0, 0)` red when it cannot. `FUN_8003A3B8` uses it as the fighter's back light colour, so the model glows green or red: a live frame-advantage display. The USA version calls it HIT ANALYSIS.

**Attack data** (`FUN_800B3808` and the HUD):

- a per-player combo counter (capped at 99, `0x800B91A8 + 32·player`);
- the damage of the last hit with its share of the combo (`DMG:%03d(%03d%%)`), coloured by whether it rose or fell;
- the combo's total damage (±999, `TOTAL DMG`);
- the COUNTER and CLEAN HIT labels;
- a 60-frame marker at the hit point, drawn in the colour of the attack level (high, mid, low, unblockable). The marker is at the end of the attacker's attack segment, or at the defender's hurt-zone joint when the attack descriptor's joint is `≥ 0x18`.

**Replay settings** (`FUN_800B8D50`). After a combo of at least 4, 5 or 6 hits (per-player counter), or on Select in MANUAL, the game replays the last `min(frames since the combo started, combo length + 30)` frames, clamped to 90–300, through the replay system (`ReplayStart`). The counters restart after a replay.

**Key display** (`FUN_800B7B08`, drawn by `FUN_800B7C84`). A 50-entry ring at `0x800B9230` logs the input. Each `u32` holds:

- the pressed buttons (`pad & 0xF0 >> 4`) in byte 0;
- the direction (`pad >> 12`) in byte 1;
- a hold count in bits 16–30 (capped at `0x3FFF`);
- bit 31, the fighter's `+0xC6` flag.

A repeated input increments the count of the current entry.

**Combo training.** Table `0x800B2AD8` gives, per bank type, a list of combos and their count. There are combos for bank types 0–10, 12, 13, 16 and 17 (1–7 each). A combo record is 12 bytes: a pointer to its input steps, a pointer to its move slots, `u16` step count, `u16` move count. The steps use the key-display format and are loaded into the ring as a guide (`FUN_800B7FB4`). The move slots (for example Paul's first combo: stance, then slots `0x2C7`, `0x12E`, `0x2CB`) are the moves the player must perform in order. The HUD shows `PLAY = SELECT` / `GUIDE MODE` prompts.

## Arcade ending and staff roll

After the tenth arcade fight the game enters state 19 with `0x800AE158 = 0`; a non-zero value is Theater. The handler (`0x8010E8C0`):

1. picks the winner's ending movie (`0x800AE15C`, [movie table](../formats/sound-and-video.md#movie-table-endingovl)) and plays it (sub-state 2);
2. sets up the staff roll (`FUN_80112798(1)`) and prepares music track 4;
3. runs the roll over a black screen every frame (sub-state 3);
4. when the roll returns 1, goes to the ranking (state 16, `FUN_80050478`).

**Staff roll** (`FUN_80112798`). The frame counter `c` is `0x8011E5F0`. Setup uploads three plain TIMs from the overlay: two 4-bit font sheets at VRAM (640, 0) and (640, 36), and the Namco logo at (640, 128). The phases:

| Phase | Duration | Content |
|---:|---|---|
| 0 | 31 frames | Silence, then sound `0xC7C0`. |
| 1 | until `c` = 240 | Music track 4 starts. |
| 2 | until `FUN_8006BCC8` returns 0 | Waits for the music. |
| 3 | 60 frames | Pause. `c` restarts here and at the next phase. |
| 4 | 240 frames | Title block (`0x8011DAD8`: `THE KING OF IRON FIST TOURNAMENT 3` and a second line), centred on x = 152 at y 220 and 238, with a colour ramp in and a fade after frame 180. |
| 5 | 8,722 frames | The scroll: the list at `0x8011DAE4` (705 rows in Japan Rev.1), 18 pixels per row, entering at y = 480 and rising 1 and 2 pixels on alternate frames; then the end-of-list hold and fades below. |
| 6 | until `c` = 9,060 | Hold: 100 frames for the retail list, so the credits end with the music. |
| 7 | 180 frames | The Namco logo: two textured quads at x 54–315, y 220–265 (`FUN_80114550`). The brightness rises by 12 per frame for 11 frames, holds, and falls by 2 per frame after frame 120. Then the roll returns 1. |

Any face button or Start (`0x8F0`) ends the roll at once. Without a skip, the roll lasts 9,573 frames from its set-up when the music starts at once (phase 2 takes one frame).

**Rows.** Each row string starts with a kind digit:

| Kind | Row |
|---|---|
| `0` | Heading (font flag 1, 4 pixels lower). |
| `1` | Name (font flag 0). |
| `2` | Blank. |
| `3` | Heading shown only when Tekken Ball is unlocked (`0x80098306 ≠ 0`), 20 pixels lower. |
| `4` | Heading shown only while Tekken Ball is locked. With `3`, it puts one of two headings in the same place. |
| `5` | Name shown only when Anna's Start costume is unlocked (`0x800982D4` bit 18). |

Rows fade in near the bottom (y 360–440) and out near the top (y 20–100) through a colour ramp (`FUN_80113A3C`, `FUN_80114494`).

**End of the list.** The scroll stops when the NULL terminator comes on screen. Then the last rows hold for 620 counts, fade for 80 and fade again for 80 (`0x80194660`, `0x8019465C`). These counters advance once per visible heading row (kind `0`) per frame, not once per frame. The retail list has three headings on the last screen, so the hold lasts 207 frames and each fade 26–27 frames. While the list is stopped, the terminator is read as a row every frame ([game-bugs.md](game-bugs.md)).

## Theater

THEATER MODE (state 19, `ending.ovl`, `0x800AE158 ≠ 0`) has a movie page and a sound page. Theater itself is unlocked by clearing arcade with all ten original characters ([unlocks](#unlocks)). The port is `tools/research/theater_sim.py`.

**Context** (`0x800AE158`):

| Address | Content |
|---|---|
| `0x800AE158` | Page: 1 movie theater, 2 arrange sound, 3 arcade sound (0 = arcade ending). |
| `0x800AE159` | Disc: 1 Tekken, 2 Tekken 2, 3 Tekken 3. |
| `0x800AE15A`, `+0x15B` | Movie and track counts of the disc (12 / 30 / 26 movies, 14 / 28 / 29 tracks). |
| `0x800AE15C`, `+0x15D` | Movie and track to play. |
| `0x800AE15E`, `+0x15F` | Cursor; first visible grid row or list line. |
| `0x800AE162` (`s16`) | Focus: 0 the list, 1 EXIT, 2 SOUND (movie page) or THEATER (sound page), 3 DISC, 4 BGM SELECT. |
| `0x800AE164` (`s16`) | Every Tekken 3 movie is open (`FUN_801109D4`). Only then are DISC and SOUND offered. |
| `0x800AE166` | Frames without a held button (the title banner). |

**Movie lists** (0x1C bytes per entry; Tekken 3 `0x800BA858`, Tekken 2 `0x800BAD3C`, Tekken `0x800BB29C`): `s16` movie, `s16` alternative movie, `s16` picture, `u32` clear mask at `+8`, `u32` rule at `+0xC`, then the name and one or two title lines. An entry's status (`FUN_8010FC7C`):

- mask 0: always open. Movie −2 marks an empty cell.
- rule 0: open when the mask meets the arcade clears `0x800982D8`.
- rule 1 (Kuma / Panda, bit `0x800`) and rule 2 (Gun Jack, bit `0x10000`): the second-clear bit in `0x800982DC` gives the alternative movie, else the first-clear bit the movie.
- rule 3 (Tiger): `0x800982DC` bit `0x100` (Eddy's second costume).
- otherwise −1 (locked).

The names `0`–`3` stand for shared slots and are spelled from the clears: YOSHIMITSU / DOCTOR.B. (bits 4 and 19), KUMA / PANDA, GUN JACK -BAD- / GUN JACK, OGRE / TRUE OGRE (bits 14 and 20). Both clears join the names with a comma (`FUN_8010F634`).

**Movie page** (`FUN_80110A58`):

- A 6 × 4 grid of 48 × 64 pictures at x = 40 + 48·column, y = 72 + 64·row. Open cells show a frame sprite and the movie's picture; locked cells show the frame and picture 0. Empty cells are skipped.
- The cursor is a red 4-tile frame (panel 2), drawn while frame counter bits `0x1C` are non-zero.
- The buttons sit at y 344: with every movie open, DISC (x 82), SOUND (x 162) and EXIT (x 252); otherwise only EXIT at x 162.
- The selected open movie shows its picture at (30, 384), its name in the large font at y 386, and the title lines at y 422, or at y 413 and 431.
- A selected locked movie that has a picture shows `???`.

**Sound page** (`FUN_801112DC`):

- A white frame at (24, 72, 206 × 290) holds 14 lines of `nn:NAME`, 20 pixels apart. Lines are colour 11 on ARRANGE and 10 on ARCADE; the selected line is colour 5 over a pulsing bar.
- The buttons THEATER, BGM SELECT, DISC and EXIT are at x 250, y 200 / 230 / 260 / 290.
- The disc's two logos (TIMs `2·disc − 2`, `2·disc − 1`) are at (242, 90) and (242, 346).
- The selected track shows its name, TIM 7 and `ARRANGE` or `ARCADE`.

A track entry's first byte is `2·track`. The ARCADE page plays it with bit 0 set ([sound.md](sound.md#music)).

**Common parts:**

- **Buttons** (`FUN_801106A8`): white 2-pixel frames. Labels are colour 5 when focused, else 10. The fill is dark blue (0, 0, 128), or pulses towards (32, 64, 255) when focused. The fill sits 2 pixels higher than the frame ([game-bugs.md](game-bugs.md) #37).
- **Footer** (`FUN_80110008`): a blue Gouraud panel with a white frame at (18, 374, 332 × 82) over a full-screen blue gradient (panel table `0x800BA730`, [game-bugs.md](game-bugs.md) #36).
- **Help strips** at y 400: picture strips from table `0x800BA838` for the focused button. When the list has focus, the details of the selected entry show instead.
- **Banner** (`FUN_80112554`): the page title (for example `TEKKEN3 MOVIE THEATER`) at y 34. After 480 idle frames it alternates every 256 frames with `PUSH START TO PLAY`, sliding 11.5 pixels per frame during the last 32 frames of each half.

**Input.** Menu sound `0x546C` on a move, `0x4CEB` on a choice. Select (`0x100`) exits from either page.

- Movie page (`FUN_80111A68`):
  - Left and right skip empty cells. Moving down into an empty cell slides towards the middle column.
  - Down from the last full row moves the focus to SOUND (or EXIT).
  - With a button focused, left and right move between the buttons and up returns to the grid.
  - A choice plays an open movie. SOUND opens the ARRANGE page and uploads that disc's TIMs and TIMs 6–7. DISC starts the disc change, EXIT leaves.
- Sound page (`FUN_80111FEC`):
  - Up and down move through the list, 14 lines at a time; right focuses THEATER.
  - With a button focused, up and down move through the buttons and left returns to the list. DISC is skipped while not every movie is open.
  - THEATER returns to the movie page. BGM SELECT toggles ARRANGE and ARCADE and stops the music. A choice in the list plays the track.

**States** (`FUN_8010E8C0`, sub-state `0x800AE6EC`):

| State | Action |
|---:|---|
| 0 | Set-up: disc 3, `0x800AE164`, TIMs 4–7, then state 1 (or 2 for the arcade ending). |
| 1 | The menu. When the CD lid opens, the music stops and the state is 6. Result 1 plays the movie (state 2) or the track (`FUN_8006B47C`); 4 exits (state 10); 5 changes the disc (state 4). |
| 2 | Plays movie `0x800AE15C`, then state 1 and reloads TIM 6 (the pictures). |
| 4 | Stops the music and the CD (`DsControlF(CdlStop)`), then state 5. |
| 5 | "Open the lid" message (footer 1, with the CANCEL line). A face button or an open lid goes to state 6. |
| 6, 7 | "Insert a disc" (footer 2 with every movie open, else 4). When the lid closes (`FUN_8008FB14` = 1), state 8. |
| 8 | `DsGetDiskType`: a CD-ROM goes to state 9; no disc or another format goes back to state 6. |
| 9 | Looks for `\TEKKEN.EXE;1`, `\TEKKEN2\TEKKEN2.XAS;1` and `\TEKKEN3.XAS;1` (footer 3). Tekken and Tekken 2 register their XA file (`FUN_8006B098`). A found disc becomes the movie page's disc (only Tekken 3 until every movie is open); otherwise back to state 4. |
| 10 | EXIT: a black screen. With the Tekken 3 disc in, it returns to the main menu (`FUN_8004FBE0(4)`). Otherwise it asks for it (footer 5), and a button goes to state 7. |

**Other discs.** Tekken 2 movies are played from `TEKKEN2.XAS`. Tekken 1 movies come from `\MOVIE\<name>.STR;1` with the names PAUL, NINJA, NINA, MICHELLE, KING, JACK, KAZUYA, KAZ_OP, OPENING, NAMCO and LOGO.

## Records

The memory card file also stores the 432-byte record block at `0x8009832C` (after the save block; `FUN_8004C1A8`), shown by the RECORDS option:

| Offset | Content |
|---:|---|
| `+0x000` | Time attack: 22 × `(u32 time, char name[4])`, indexed by character ID 0–21 (the default names are three-letter placeholders). Times are in frames and shown as `mm'ss"hh` (hundredths `= (frames mod 60)·100/60`). The default times are 53–58 minutes for the ten original characters and 359,999 (99'59"98, the cap) for the others. |
| `+0x0B0` | Greatest survivors: 10 × `(u16 character, u16 wins, char name[4])`, sorted by wins; the defaults run from 5 wins down to 1. |
| `+0x100` | Character statistics: 22 × 4 `u16`: `+0` plays (one per finished arcade run or VS win, `FUN_8005169C`), `+2` wins, `+4` losses (`FUN_80051740(winner, loser)`), `+6` draws (`FUN_80051838`, both characters). All start at 0 and saturate at 65,535. |

The pages are:

- **Winning average**: `wins·1000 / (wins + losses)`, shown with one decimal, with the win and loss counts.
- **Characters data**: each character's usage (`plays + losses + draws`, `FUN_80051948`) as a share of the total over all characters.
- **Greatest survivors**.
- **Character time attack**.

Updates (arcade overlay):

- **Time attack** (`FUN_800B4B80`): after the tenth stage the ten stage times (`0x800AFF90`, 8 bytes each: frames, character, costume) are summed. The total counts only when every stage was played with the same character and costume. If it beats the stored time, it replaces the record, the name is reset to three spaces, and name entry is flagged (`0x800984DE` bit 0, record pointer `0x80098324`).
- **Survival** (`FUN_800B4C94`): a run with more wins than one of the ten entries is inserted, and the table is re-sorted and cut to ten.

## Memory card file

The game saves one block, `BISLPS-01300TEKKEN-3` (USA `BASLUS-00402TEKKEN-3`), with `FUN_8004C1A8` and loads it with `FUN_8004C528`. Every statistics or unlock update sets the save-pending flag `0x800AE428` (`FUN_8004C678`).

- **Header (512 bytes)**: `"SC"`, icon flag `0x13` (three-frame animated icon), block count 1. At `+4` is the title in full-width Shift-JIS (`FUN_8004BF58`; USA `FUN_8004BCC0`). The icon CLUT is at `+0x60` (from `0x80021C78`) and the three 16 × 16 4-bit icon frames are at `+0x80`.
- **Data (512 bytes)**: byte 0 is a checksum, the negated sum of bytes 1–511. Bytes 1–72 hold the save block and bytes 73–504 the record block. The whole block is then scrambled from byte 1 on: `c = byte + 5·c + 1` (8-bit, starting from the checksum), each byte replaced by the running `c`.

The title reflects progress. Japan Rev.1 writes the message, the game's title in brackets and then the company name, or a "N left" count when 1–14 characters are still locked. The USA version writes the title in brackets followed by the message. The message is the first matching case:

| Case | Message (the game's own string tables hold the wording; the converter never copies it here) |
|---|---|
| Only characters 0–9 unlocked | the opening line (Japan Rev.1 and USA have one each) |
| Japan only: all characters unlocked and cleared | the closing line, also the "Otherwise" one |
| Gon locked, Tekken Ball new (`0x80098306` = 1) | the Tekken Ball announcement |
| Gon locked, Tekken Ball already chosen (`0x80098306` ≥ 2) | the pointer back to Arcade mode |
| A character was just unlocked (`0x800982F2 < 22`) | Japan: that character's own line (`0x8009804C`); USA: a count of the characters still locked (nothing when 0 or more than 14) |
| Everything except Doctor B. (ignoring Gon) unlocked | the Tekken Force hint |
| An unlocked character has not cleared arcade | Japan: the first such character's line; USA: "USE" plus the character's name (names at `0x80097C28`) |
| Otherwise | USA: a general line; Japan: the closing line |

Japan's per-character lines are hints for the next goal (`0x80021840..0x80021BB0`).

## Save block

The 72 bytes at `0x800982D0` are what the memory card stores (built into the card file by `FUN_8004C1A8`, restored by `FUN_8004C528`); the EXE image holds the defaults.

| Offset | Content |
|---:|---|
| `+0x00` | Unlocked characters (bit per character ID; default `0x3FF`). |
| `+0x04` | Start-costume mask (default `0x2`). |
| `+0x08`, `+0x0C` | Characters that cleared arcade (first/second clear). |
| `+0x14..+0x1A` | Speaker, BGM, difficulty, fight count, round time, guard damage, character change. |
| `+0x1C`, `+0x1D` | Per-player controller setting passed to `FUN_8002A3C0`. |
| `+0x1E`, `+0x1F` | Last selected character per player (`0x58` = none). |
| `+0x20`, `+0x21` | Quick select, auto save. |
| `+0x22` | Most recently unlocked character (22 = none) for the memory card title. |
| `+0x23` | Demonstration character position. |
| `+0x28` | Tekken Force keys earned (0–3; saturating counter). |
| `+0x29` | Select cursor hold. |
| `+0x2C` | `u16` fights since the last unlock (saturating; every statistics update adds 1, every unlock clears it). |
| `+0x2F` | Number of unlocked characters class (0, 1 at 15 or more, 2 with Doctor B.). |
| `+0x34`, `+0x35` | Display adjust. |
| `+0x36`, `+0x37` | Tekken Ball / Theater "new" counters. |
| `+0x38..+0x47` | Button layouts of both players. |

## Open items

- None known.
