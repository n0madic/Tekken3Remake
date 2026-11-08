# Arcade whole-game flow and 2D screens (World ver. E1)

The remake's port is `remake/core/arcade/arcade_game_flow.gd` and its parts, proven against the original in the CPU harness as [section 6](#6-proof-and-corrections) says. The screens' numbers leave the program through `tools/remake_import/arcade_screens.py`, whose docstring is the file format; the flow's tables through `arcade_flow.py`.

Everything below is `confirmed` (read in the decompile or disassembly of the unpacked program, or decoded from the ROM) unless marked `inferred`. `observed` means seen in headless MAME runs with `work/arcade/flow/lua/scenario.lua`. Frame numbers are 60 Hz frames. Addresses are World E1.

Evidence under `work/arcade/flow/`:

- `contact_screens.png` (one frame per screen), `contact_attract.png`, `contact_a1.png` (coin → game over), `contact_b.png` (challenger, 2P), `contact_c.png` (Ogre, ending, name entry), `contact_d2.png`, `contact_e2.png` (COMING SOON!, WHO IS IT?), `contact_f.png` (demo banner), `contact_g.png` (11-character select), `contact_ladder.png`, `contact_rank.png`.
- `catalog/catNN.png` (categories 1–18, 42, 43), `catalog/catalogue.txt`, `.json`.
- `run/*.log` (per-frame state changes), `snap_*/` (raw snapshots), `tools/` (`fn.py`, `callers.py`, `prog.py`, `catalog.py`, `sheet.py`, `pick.py`), `lua/`.

Scenario knobs for repeating runs: `SCN_FREE`, `SCN_DAY`, `SCN_WIN`, `SCN_LOSE`, `SCN_CONT`, `SCN_P2`, `SCN_RIGHT`, `SCN_NAME`, `SCN_NOSTART`. A KO is forced by writing 0 to the fighter's life `+0x33C`.

## Display

- `FUN_801BB838(4)` picks a row of the mode table `0x801FF898` (16 bytes per mode). The mode is reduced `& 3` unless `0x8021FD3C` (cabinet setting `0x8036ECF0`, "Interlace") is set.
  - Mode 0: `GsInitGraph(512, 240, 4)`, the default. `observed`: 512 × 240, `0x8021FC04` = 1.
  - Mode 4: 512 × 480 interlaced.
- All draw coordinates are in a **512 × 480 layout**. With `0x8021FC04` = 1 (low-res) the primitives `FUN_801B2BF0/2CA0/2D74/2E3C/2EC4` and `FUN_801B312C` halve y, and the TIM loader drops every second row when told to (`FUN_801B1974(halve)`, `FUN_801B18EC`/`FUN_801B1998`).
- Hi-res and low-res variants exist in the ROM, so **a remake at 480 lines can use the hi-res set** (section 4). Numbers below are 480-line values.

## 1. State machine

State word `0x8021FD20`, sub-state `0x8021FD64`, timer `0x8021FD4C`, frame snapshot `0x8021FD58`, mode context `0x80374F18`.

### States

| State | Routine | Role | PS1 and remake equivalent |
|---:|---|---|---|
| 0 | `FUN_80189EC8` | Boot: loads cats 3 (or 4), 1, 2, then transition to 2. | `BOOT` |
| 1 | `FUN_801B5EEC` | Transition, `NAMCO PRESENTS.` | `TRANSITION` |
| 2 | `FUN_801BD5A0` | Attract: movie or enbu or white flash, then title. | `TITLE` + `ENBU` merged |
| 3 | `FUN_801BD97C` | Title with coin prompt. | New (replaces `MENU`) |
| 4 | `FUN_801B6BA4` | Match flow, including the VS screen. | `PREPARE` + `FIGHT` + `VS` |
| 5 | `FUN_801C06E4` | Character select. | `SELECT` |
| 7 | `FUN_801C241C` | Ranking and name entry. | `RANKING_LOAD` + `RANKING` |
| 8 | `FUN_801E5F50` | Ending and staff roll. | `ENDING` (different content) |
| 10 | `FUN_80192EC4` | Empty, never entered (`inferred`). | None |

### State 1, transition

`FUN_801B5EC0(target)` stores the target at `0x8021F22D`, the previous state at `0x8021F22E`.

| Sub | Meaning | `observed` frame (boot, blank NVRAM) |
|---:|---|---:|
| 0, 1 | Black | 851, 852 |
| 2 | `FUN_801B1E58(0)` reloads cats 3/4, 1, 2, 6 and the cat 5 patch when needed (10 frames) | 853 |
| 3 | Text fades in, level `t << 3`, 33 frames | 863 |
| 4 | EEPROM flush `FUN_801BAB44` | 894 |
| 5 | Hold until 0x5A (90) frames | 906 |
| 6 | Fade out 0x20 frames | 985 |
| 7 | Go to target | 1017 |

If target ≠ 2 or attract step is 1 or 3, sub 2 goes straight to 7, with no text (`observed` 10–12 frames). Text is `"%c%H%VNAMCO %cPRESENTS."`, colour 2 then 6, at (0xA0, 0xF0). `FUN_801B7810` (coin and start) runs from sub > 2. Same numbers as the remake's `PRESENTS_FADE_FRAMES`, `PRESENTS_HOLD`.

Boot takes 851 frames on a blank NVRAM and 467 with one (`observed`).

### State 2, attract

Attract step `0x8021F231`: 0 movie, 1 and 3 flash, 2 enbu. Picture kind `0x8021F288` as in PS1 (`FUN_801BD318`).

| Sub | Meaning | Frames (`observed`) |
|---:|---|---:|
| 1, 2 | [Movie](#movie): `FUN_801BE180(0)`, music `FUN_801B0968(0x60, 0xC)`, 261 pictures, one per 4 vblanks | 1052 |
| 3, 4, 5 | Enbu: stage 4, `rand() & 3`, script `0x80186FF8` (10-byte events, PS1 format), credits only | 3562 |
| 6, 7, 8 | White flash, +10 per frame in the OT at +0xC, then 11 frames white | 26 + 10 |
| 9, 10 | Title, fade from white, `t` from 0x100 by −3, level `t + 0xFD` | 86 |
| 11 | Title + prompt | 300 |
| 12 | Fade −8 per frame at OT +0x1C | 33 |
| 13 | Step++ (wraps after 3), `FUN_801BDA64(6, 0)` → demo in state 4 | 1 |

`observed` loop, starting at step 2 after boot:

```
PRESENTS, enbu, title, demo                 (step → 3)
flash, title, demo, ranking                 (step → 0)
PRESENTS, movie, title, demo                (step → 1)
flash, title, demo, ranking                 (step → 2)
```

After the demo, state 4 sub 0x12: `FUN_801B5E1C` with the step at 0 or 2 → state 7 ranking; otherwise transition to 2. A full cycle is about 13,350 frames (depends on the demo length, 1300–1530 frames each). The ranking pages advance one each visit: time, wins, usage (`observed` time, wins; section 3 has the rule after a game).

The sub-state values match the PS1 enbu and title numbers: `WHITE_HOLD` 11, `TITLE_FRAMES` 300, fades −3 and −8, flash +10.

### State 3, title and coins

Sub 0: `step = (step + 2) & 2`, `FUN_801B0ACC(1)`. Sub 1: 480 frames (0x1E0) since the last coin, a coin resets the timer, then transition to 2. Draws picture 2 with the prompt.

### Coins and credits

| Routine | Role |
|---|---|
| `FUN_801B0BB8` | Per frame: reads shared-RAM counters, service `0x1F083200` (ack `0x1F083240`), coin `0x1F083900` (ack `0x1F083940`). Sets `0x8021F824` service credits, `0x8021F804` coins, sums `0x8021F828`, `0x8021F808`; edge bits `0x8021FBCC` (bit `i` coin, `1 << (i + 16) | 0x8000` service). Coin sound `0x1F08013E = 0x4111`. |
| `FUN_801B0DD0` | Settings: split credit `0x8021F814` (EC4A), start cost `0x8021F80C` (EC44), continue cost `0x8021F810` (EC45), mechanism `0x8021F81C/1E` (EC46/47), counter `0x8021F830` (EC4B), **free play `0x8021F818` (EC4C)**. |
| `FUN_801B0ED8(p)` | Pays: free play → always 1; else service credit first, else cost (continue cost if `0x8021FC74[p]` ≠ 0); 0 if short. |
| `FUN_801B7810` | Start edge + paid → `FUN_801BDA64(0, players)`; else coin edge `(0x8021FBCC & 0x8003)` and state ≠ 3 → transition to 3. Called from states 1 (sub > 2), 2, 3, 7. |

**Free play** (`0x8036EC4C` ≠ 0) is what an arcade-only remake needs: Start in attract starts a game at once (`observed` run b, state 2 → state 4 with no state 3). Prompts change to `FREE PLAY`, `PUSH P1 OR P2 BUTTON`. The remake can run with free play always on and skip `FUN_801B0BB8`.

### State 4, match flow

`FUN_801BDA64(mode, players)` (2 callers, modes 0 and 6 only) resets per-player flags, evaluates unlocks (`FUN_801BAE34`), rounds = `0x8021FD94`; event mode `0x8021FC5C` (EC5A) forces both players. Modes 1–5 exist as leftovers (`TEMA BATTLE`, `SURVIVAL`, `PRACTICE`) but are unreachable.

| Sub | Meaning | Remake `MatchFlow.Sub` |
|---:|---|---|
| 0 | Mode ≠ 6: set return (4, 1) in `0x80374F1E/1F`, go to state 5 | `SELECT` |
| 1 | `FUN_801B6664` builds the ladder once (`0x8021FD34`) | `MODE_START` |
| 2 | Sides, `FUN_801B66D8` (entry → CPU side, clash `FUN_801B4FAC`, rounds), `FUN_801B5270` stage and music, VS init | `NEXT_FIGHT` |
| 3 | `FUN_801B8A44` VS screen, 15 frames (`observed`) | `State.VS` |
| 4 | `FUN_8018A44C` load | `LOAD` |
| 5 | Hold until ≥ 0x2A (42) frames since sub 2 | `LOAD_WAIT` (PS1 > 0x3B) |
| 6 | `FUN_8018A6D0` round init | `DISPLAY_OFF/ON`, `ROUND_START` |
| 7 | Winner name entry `FUN_801B9138`, challenger check `FUN_801B7924` if flags & 2, `FUN_8018A988` fight frame; mode 6 banner + `GAME OVER`, result ≥ 3 → 0x12; result 8 → 0xE, 9 → 0x13, ≥ 7 and match decided → `FUN_801B67E0`, else sub 6 | `FIGHT` |
| 8, 9 | Voice 0x1016, music 99, timer 0x328 (808); `FUN_801B6230` continue | `CONTINUE_START`, `CONTINUE` |
| 0xA, 0xB | `FUN_801B4D68` wins record, music 100, voice 0x1017; `GAME OVER` for 0x97 (151) frames, save → state 7 | `GAME_OVER_START`, `GAME_OVER` (PS1 0x79) |
| 0xC, 0xD | Challenger: t from 8 to 0x5B (83 frames `observed`), freeze `0x8021FAD0` after t > 0x17 or result > 0; flags & 4 clears the choice → sub 0 | `CHALLENGER_*` (PS1 ends 0x4A) |
| 0xE, 0xF | Ogre scene `FUN_801E1758`, scripts `0x80187208`, `0x8018723C`, Start skips (262 frames `observed`) | `OGRE*` |
| 0x10 | Ladder[9] char = 0x14 True Ogre, reload, sub 6 (rounds kept) | `TRUE_OGRE` |
| 0x11 | 2P game end → state 7 | None |
| 0x12 | Demo end → state 7 or transition to 2 | `DEMO_OVER` |
| default | Transition to 3 | `EXIT` |

- **Continue** `FUN_801B6230`: coin → timer 0x32A; Start + paid → continues++, returns 1 (same character, sub 2) or 2 (setting `0x8021FB10`, EC57: reselect, sub 0); buttons 0x360 subtract 0x5A; 0 → −1 (sub 0xA). Digit = (t + 0x5A) / 0x5A, voice 0x1004 + digit. Same as `_continue_countdown`, plus payment. `observed` 2666 → 3474 without input, and a continue at 2926 returns to sub 1.
- **Match end** `FUN_801B67E0`: one human won: stage++, intruder `FUN_801B5C50`, sub 2; after stage 10 records and state 8; lost → sub 8. Two humans, not event: loser's timer `FUN_801B6488` (`0x8021FB4C` = 0x328, HUD `CONTINUE? %1x` at the bottom), winner goes on, sub 2; event: sub 0x11.
- **Challenger** `FUN_801B7924` during a fight: Start + paid; joins++. `observed` run b: coin at 1860, Start at 1920, sub 0xC at 1922, select at 2005, VS at 2342.
- **`FUN_801BCC98`** every frame writes status records `0x80277538` (stride 0x14) to shared RAM `0x1F083820`; `FUN_801BC37C` builds a mask of the unlocks for it. `inferred`: cabinet output, with no effect on the game. Not needed.

## 2. Arcade ladder and unlocks

### Ladder `FUN_801B557C`

Ten 4-byte entries at `0x80374FA8` (character, costume, level, pad).

| Stage | Rule |
|---:|---|
| 1–3 | Random from the ten originals, excluding player and boss. **PS1 has 4 here.** |
| 4–8 | Random from what is left of `0x8021FD60 & 0xFFEF9FFF` minus player and boss (no Heihachi, Ogre, True Ogre; the bitmask keeps the rest of the unlocked set). |
| 9 | Heihachi (13), or Jin (9) if the player is Heihachi. |
| 10 | Ogre (14). Winning a round → Ogre scene → True Ogre (20), round score kept. |

Costume: `(key & 3) != 0` except 14 and 20 → 0. Level = index. Generator `FUN_801B551C` via `FUN_801B2468` (x·5 + 1, also stepped in the frame wait, so timing-dependent). `observed` (`contact_ladder.png`, day 120, Xiaoyu): Lei, Law, Hwoarang, Nina, Yoshimitsu, Bryan, Mokujin, Eddy, Heihachi, Ogre. `Opponents.ladder` needs one constant changed; Gon (not in the arcade) goes.

### Intruders `FUN_801B5C50`

**Not in the PS1 ladder.** Called with the next stage index `n` after a win. `0x80374F2D` holds one candidate: the character of the latest kind 1 schedule entry, so only the current COMING SOON! fighter can intrude. When its condition holds, its ladder entry is overwritten and `0x80374F2C` is set (once per game); a failed condition returns and retries after the next win. `n` must be 1–7. Candidates without a case (Heihachi, Ogre, True Ogre) or none (0x16) just set the flag.

| Character | Window (days) | Condition | Entry | Level |
|---|---:|---|---:|---:|
| Kuma | 34–43 | `n` = 3 | 3 | 5 |
| Julia | 48–57 | Win streak ≥ 3 (`0x8021FBE4`) | `n` | `n` + 2 |
| Gun Jack | 61–67 | `n` = 2 and `FUN_801B4924(2)` (sum of the first two stage times) < (`0x8021FD94` + 1) · 1500 | 2 | 4 |
| Mokujin | 76–82 | Continues (`0x80374F24`) ≠ 0 | `n` | `n` + 2 |
| Bryan | 88–94 | Last round was a Perfect (`FUN_8019E7A4`, `0x8021FC28` bit 3) | `n` | `n` + 2 |

### Stages and music

From the character record of the opponent (`FUN_801B5270`): `0x801FF454 + 4·key`, key = id << 2 | costume, record +10 stage, +11 music. Examples: Paul stage 0 music 0x10, Heihachi 0xC / 0x17, Ogre 6 / 0x1E, True Ogre (id 20 or Ogre costume 2, 3) 6 / 0x01, Xiaoyu 3 (costume 2, 3: stage 7) / 0x1B. Other record bytes: +0 name, +4 plate entry, +5 plate width, +6 face entry, +8 voice index into `0x8015FEB8` · 0x18. Costume keys hide the alternates: Nina 2, 3 = Anna; Eddy 2, 3 = Tiger; Kuma 1, 3 = Panda; Ogre 2, 3 = True Ogre.

### Difficulty

- `0x8021FD40` low byte = ladder level; `0x8021FD28` = difficulty setting EC4F; both read by `FUN_801C2FCC` with a group from `0x8036ECF4` (see the [ai.md](ai.md)).
- Life `FUN_801B7C50`: mode 0 table `0x8017957C` (or `0x8017955C` when `0x8036ECF4` = 1) indexed by EC52 (one player) or EC53 (versus); mode 6 fixed 0x7D0000. Default value 0x7D0000.
- Rounds: EC50 (one player), EC51 (versus). Round time EC56.

### Unlocks: operator time, not plays

Table `0x801FF648` (`u16 day, u16 kind, u32 arg`, ends at day 0xFFFF), applied in order by `FUN_801BAE34` at every mode start up to the day counter `0x802F4B8C`.

| Kind | Effect |
|---:|---|
| 0 | WHO IS IT? on the demo VS (`0x80273258`) |
| 1 | COMING SOON! on the demo VS (`0x80273254`), and the character arms as an intruder |
| 2 | Unlock (`FUN_801B5424`, mask 0x11FFFF on `0x8021FD60`) + NEW FIGHTER banner (`0x80374F2F`) |
| 3 | Extra costume bit (`FUN_801B5468`, on `0x8021FD6C`) |
| 4 | Clear (`FUN_801BADF4(1)`) |

Schedule (day: kind char):

```
0: 3 Law | 30: 0 Kuma | 34: 1 Kuma | 44: 2 Kuma, 0 Julia | 48: 1 Julia | 58: 2 Julia, 0 GunJack
61: 1 GunJack | 68: 2 GunJack, 0 none | 73: 3 Jin, 3 Xiaoyu, 0 Mokujin | 76: 1 Mokujin
83: 2 Mokujin, 0 none | 88: 3 Nina, 1 Bryan | 95: 2 Bryan, 1 Heihachi | 100: 2 Heihachi, 1 Ogre
105: 2 Ogre, 1 TrueOgre | 110: 2 TrueOgre, 0 none | 115: 4 | 120: 3 Eddy
```

Clock `FUN_801BAD1C`: frames `0x802F4B80`, hour `0x802F4B84` every 0x34BC0 (216,000) frames. At hour 6, if shared word `0x1F083032` differs from saved `0x802F4B8E`, day++ and SECRET_EEP is saved (`inferred`: the word is a board value that changes between days). Starting mask `FUN_801B54BC` = 0x3FF. `observed`: day 0 gives 10 faces, day 44 gives 11 (Kuma, banner, WHO IS IT? with Julia), day 120 gives 18.

**For the remake:** a setting for the day (or "all unlocked" = day ≥ 110), since uptime has no meaning at home. Bit 17 (Jun) cannot unlock; id 21 `SAKE` has a record only.

### Select roster and cells

Roster `0x80179BA8`, 18 keys, `FUN_801C06E4` context `0x802C8300`. First 10 unlocked on the top row; others on a bottom row centred with start `0x23 − ((n − 9) >> 1)`. Layout = (n > 10). `observed` both.

Costume by button, `FUN_801BECCC`: buttons 0x300 → 0, 0x60 → 1, Start (0x8000) → 2 only if the character is in `0x8021FD6C` and the cursor rest counter is 0; timeout picks. Pick voice from `0x8015FEB8`, sound 0x112; move sound 0x113; state 4 accepts a challenger.

Timer T = 60, or 60 + 3(n − 10) for n > 10; total 20·T frames. `observed` 20 → 15 in 326 frames at n = 10; 20 → 17 in 318 frames at n = 18.

## 3. Screens

Colour (`c`) and font (`f`) refer to section 5. `FUN_801B312C(ot, prim, x, y, w, h, u_words, v, clutId, mode)` draws big pictures, mode 0x80 is 8-bit.

**Title** (`FUN_801BD318`, kinds as PS1):

- Kind 5: cat 6, 512 × 480 8-bit at VRAM (0, 512), CLUT (256, 488), at (0, 0).
- Kind 3: Namco logo, cat 1 e0, 96 × 16 at VRAM (256, 512), CLUT (256, 489), at (0xD4, 0x184).
- Kind 4: `@1994 1995 1996 NAMCO LTD.` and `ALL RIGHTS RESERVED`, c6 f0, at (0x30, 0x19C), (0x30, 0x1B0).
- Kind 2: prompt + credits + 3 + 4. Prompt `FUN_801B13A8`, table `0x8017894C` (pointer, x): y 0x16C, c5, blink `(frame & 0x30) != 0`. Credits `FUN_801B114C`, table `0x80178A6C`: at (10, 0x1C2).
- Secret `FUN_801BD4E4`: 8 directions (table `0x80179AD0`) while buttons `(0x8021FBF4 & 0x360) == 0x140` set `0x8021F27C`: settings text `FUN_801B996C` at (0x168, 0x19C) and `%03d:%02d:%02d` day:hour:minute `FUN_801BABD4` at (0x30, 0x1B0). Not ported: it shows the operator's settings, which the remake has elsewhere, and it changes nothing in the game.

**Movie:** `FUN_801BE328` decodes 320 × 240 into 20 strips at (0x200+, 0x200), `FUN_801BE1C0` draws five quads 0x68 wide, stretched to the screen: [Movie](#movie).

**Character select** (`FUN_801C06E4`). Sub 0–2 loads (8 frames) cat 7, faces cat 10/12 (n ≤ 10) or 11/13, CLUT cat 8 entry 2 or 1. Music 0x61 after 18 frames. Each frame `FUN_801BF31C` streams one side's portrait (cat 16) + plate (cat 14/15). From frame 3:

| Routine | Draws |
|---|---|
| `FUN_801BF4B4` | Timer: digits 20 × 46 at x 0x100 (and 0xEC), y from the layout; CLUT 0x791A (10 faces, yellow) or 0x791B (red) |
| `FUN_801BF520` | Plates (`FUN_801B312C`, CLUT 0x791D), side prompts, mode text |
| `FUN_801C0124` | Cursor (cat 7 e19–24: frames and 1P, 2P) |
| `FUN_801BFFC0` | Faces at `0x801FFB10` + (n & 1)·0x50 + row·0x28; UV, CLUT at `0x80179BBC` + c·8; tpage `0x80179BC0` + c·8; 44 wide |
| `FUN_801C0398` | Frame pictures, tables `0x80179C84` (layout 0), `0x80179D34` (layout 1), 16 bytes each |
| `FUN_801BF990`, `FUN_801BF6B4` | Sparks; see below |
| `FUN_801BFA7C` | Portraits 168 wide, bands `0x801FFBB0`, `0x801FFC2F` |
| `FUN_801BFE58` | Glow, attribute colour to 0xC0C0C0 |
| `FUN_801C04D8` | Tile background: 8 columns of 64 × 64, scrolling up with the frame (`frame · −0x80 >> 4`), row map `0x801FFCB0`, tile words `0x801FFCF0`; then `PLAYER SELECT` banner, cat 7 e12, 288 × 128 at (112, 40) from VRAM (0, 0x280), CLUT 0x7B10 |

Layout records at `0x801FFAA8` (13 s32, copied to `0x802C8434`). Layout 0 and 1: plate y 0x142 / 0x120, panel top 0x154 / 0x132, faces y 0x170 / 0x150, row step (one row) / 0x3E, timer y 0xF8 / 0xC8, timer CLUT (labels `inferred` from use; the first two values and the last, 1 / 3, are `unknown`). The empty side shows portrait e19 (white silhouette) with the side prompt. New fighter tag: cat 7 e11 (`inferred` from the picture). Remake's `SelectView` has the same drawing routines on PS1 tables.

**Sparks** (`FUN_801BF8B4`, `FUN_801BF990`, `FUN_801BF6B4`; 64 records of 0x14 bytes at `0x802C8468`, cleared by `FUN_801BF88C`). From the select's fourth frame on, with `frame & 3 == 0` and a free record, a spark starts at the layout's plate y over a portrait: side 1 when `frame & 4`, else side 0, x = the player record's portrait x + `((bit 3 of frame, bit 4 of frame, 10 bits of g >> 2) · 0xA8) >> 12`, g being the frame generator `0x8021F838` (`FUN_801B2468`, x · 5 + 1), not `rand`. On its first step it takes brightness 0xA0, the displayed-frame clock `0x8021FD58` and a fade of `(g & 3) + 6`. Each step: brightness − fade, y = start y − 16 per displayed frame; it ends with brightness < 1 or y + 0xA0 < 0. It draws as a 1 × 0xA0 semi-transparent added quad, grey `(b, b, b)` at the top and blue `(0, 0, b)` at the end, clipped at the panel's top, between the portraits and the frames. The two steps of the generator make the sparks part of the simulation: the ladder's picks (`FUN_801B50EC`, `FUN_801B551C`, `FUN_801B557C`) draw from the same one. `confirmed` by reading; the trace comparison is in [section 6](#6-proof-and-corrections).

**VS** (`FUN_801B8A44`, `0x80273244`, sides stride 0x48 at `0x8027325C`). Kind `0x80273248`: 0 one human, 1 otherwise (two humans or demo), 2 COMING SOON!, 3 WHO IS IT?; 2 and 3 only in mode 6. Background cat 17 entry = kind (e0 red lightning, e1 purple burst, e2 logo); kind 3 also loads e2 then CLUT-only e3 (dark palette, `confirmed` by disassembly at `0x801B8BCC`, correcting the decompile). `FUN_801B7FD0(1)`: quad 512 × 481, CLUT 0x7950 (256, 485), tpage 0x880. Slide 8 frames; side positions `0x801FF5C4`, names `0x801FF604`; frame `FUN_801B8088` (rects `0x801795D8`, 0xF0F0F0); portrait 168 × 212 from row +20; gradient black → colour → 0xC0C0C0 at y + 6, + 0x70, + 0xDA.

Texts: `STAGE %d` c6 f1 (0x1C, 0x2A), `VS` c0 f2 (0xE2, 0xFA), `COMING SOON!` c1 f2 (0x4C, 0x3C), `WHO IS IT?` c3 f2 (0x6A, 0x154); names c8 f2, 30 px per letter, clamp 0x12–0x1EE. `observed` all kinds except kind 1 in a 2P game (demo shows kind 1).

**HUD** (`FUN_8019DCA8`, same structure as PS1 `HudRoundUpdate`):

| Element | Routine | Layout |
|---|---|---|
| Life | `FUN_801B374C`, records `0x801FF3DC` stride 0x1C | Player 1 at (0x10, 0x28), player 2 at (0x118, 0x28); 210 (0xD2) px fill, y + 4…+ 0x14, CLUT 0x7910, 0x7911, 0x7912 (health, drained, empty); caps 8 × 24 UV (0x38, 0x4E), (0x40, 0x4E); backing 200 wide. Same three-length animation as PS1 with 152 → 210. |
| Timer | `FUN_801B35FC(n, 0x100, 0x16, 31000)` | Two 20 × 46 digits, x 0x100, 0xEC, y 0x16, UV (0x14·d, 0xD0), tpage 0xD, CLUT 0x7918 |
| Round marks | `FUN_801B3B34` | 20 × 18 at y 0x46; player 1 from 0xD4 by −0x14, player 2 from 0x118 by +0x14; sprite words at `0x8021F140` |
| Name plates | `FUN_801B3E20`, loaded by `FUN_801B3CAC` | Table `0x80178FE0`: (0x16, 0x42) and (0x1EA − width, 0x42), from cat 14/15 at VRAM (0x300, 0xE0 / 0xF0); backing quad y + 9…+ 0x13, x − 6…+ 6, CLUT by costume `0x80178FF0` |
| Status line | `FUN_801B4734`, `FUN_801B4514`, `FUN_801B437C` | y 0x18, x `0x801790FC`, `0x80179100`: `STAGE` + clock `FUN_801B407C`, `GAME OVER` c2 f0, side prompts `FUN_801B1278`; `CONTINUE? %1x` c9 f1 at y 0x1B0, x `0x80179104` |
| Win streak | `FUN_801B3FE4` | `WIN %1d`, `WINS %2d`… f1 c8 at y 0x1B0, table `0x80179000`, x by side `0x8021F148` |
| Round text | `FUN_8019E034`, `FUN_8019E260`, `FUN_8019E400` | `ROUND %1x` c8 f2 (0x97, 0x70), `FINAL ROUND` x 0x5B, `READY?` c9 f2 (0xA6, 0xE4), `K.O.` c1 f2 (0xC4, 0xE4), `DOUBLE K.O.` x 0x5B, `PERFECT!` c2 (0x88), `TIME UP` c3 (0x97); `DRAW` c6 f2 (0xC4, 0x170), `YOU WIN!` c4, `YOU LOSE` c5 (0x88, 0x170), `%s WINS!` c4 centred, `WINNER`, `LOSER` c3 f1 y 0x68 |

Intro frame numbers are PS1's (61 / 1, 106 / 46, 0x96 / 0x5A voice).

**Demo banner** (`FUN_801B75B4`, `FUN_801B76AC`, every other demo, when a new fighter is set). Face cat 11/13 to (0x318, 0x40), CLUT (0, 0x1E0); sprite at (0x1A0, 0x168) 44 × 58. `NEW FIGHTER` f0 c5 (0x114, 0x16E); name f0 c3 (0x1CC − len·12, 0x1A8); `NOW    CHARACTERS` f0 c10 (0x28, 400); `ARE SELECTABLE!` f0 c10 (0xF0 − len·12, 0x1A8); count `%2d` f1 c2 (0x50, 0x18A); always `GAME OVER` f1 c2 (0xAE, 0x104).

**Challenger:** blink `(t & 0x18)`, `A NEW CHALLENGER\n     ENTERS!!` c7 f2 (0x10, 0x120). **Continue:** `CONTINUE? %d` c9 f2 (0x5B, 200). **Game over:** `GAME OVER` c1 f2 (0x79, 200).

**Ranking** (`FUN_801C241C`, block `0x80375024`, kind +0 cycles 0, 1, 2):

| Kind | Page | Routine | Data |
|---:|---|---|---|
| 0 | `CHARACTER TIME RECORD` | `FUN_801C1634` | Rows `0x80375034`, 8 bytes |
| 1 | `VS GAME WINS RECORD` | `FUN_801C1964` | `0x803750E4`, 8 bytes, top 10 |
| 2 | `CHARACTERS` usage % | `FUN_801C1A74`, `FUN_801B9864` | |

- Records: `FUN_801C2CDC` fills the block when the operator's data is reset: 22 time rows at `0x80375034` (a u32 of `180000 + 3600·i` with `2 << 28`, the character's id, costume and the first three letters of the short name), 10 wins rows at `0x803750E4` (u16 character, u16 count, name) from the table the converter writes as `record_wins`. The first ranking the attract reaches shows kind 0. Proven by the flow trace, which compares both blocks.
- Set-up, sub 2: cat 1, backdrop `FUN_801E5B14` (next stage `% 0xD` that `FUN_801E5CF0` accepts, no fighters, camera `FUN_801ED83C(0x226)`), cat 9 entry kind (512 × 48 title band at (768, 464), CLUT (256, 485)), `FUN_801C2E44` all 22 faces cat 11/13 to a grid x = (i % 15 % 5)·0x16 + 0x300 + (i / 15)·0x80, y = (i % 15 / 5)·0x3A + 0x100, CLUT (0, 0x1E0 + i).
- Page choice, sub 0: `0x80375026` pending flags: bit 0 → kind 0 with name entry; bit 1 → kind 1 with name entry; other non-zero → kind 2 (`observed` after a game over without a record). Flags 0: the kind stored in the block (sub 0xF advances it), unless raw pad bits `0x8021FBF8` & 0x400, 0x800, 0x2000 force kind 0, 1, 2.
- Timing `observed`: fade 31 frames; scroll a page in 30 (+0xC per frame), hold 150 (120 on the wins page), scroll, hold, 60 more, fade 31. Coin or Start interrupts.
- Rows 0x48 apart: `FUN_801C12B8`, `FUN_801C13DC`, `FUN_801C14D8`. Rank suffix `0x801FFD1C`, colours `0x801FFD2C`, `0x8021F384`, `0x8021F38C`; face sprite 44 × 58 UV `0x8017A098`; divider 0x909090; bars `0x80179EE0`.
- Name entry subs 0xB–0xE: `FUN_801B8E4C`, 3 letters, alphabet `0x80179678` with back `<` and end `=`, left and right via repeat bits 10, 11 of `0x8021FC88`, accept 0x360; a letter taken sounds 0x112 and a move 0x113 on channel 0x15, the select screen's (blocks at `0x801C2AFC`, `0x801C2B18` that Ghidra drops; `confirmed` capstone); countdown 3000 frames, `%2d` at (0x1B8, 0x30); rejected names `0x801FF624` become the first letters of the character's name (`FUN_801B8CD4`; `observed` `AAA` → `XIA`). In-fight variant for VS wins: `FUN_801B9138` (`0x801FF638`), begun by `FUN_801B902C` only for a streak that makes a place. It times up 300 frames after the last move or press: the button wait `0x802732F6` restarts when the halfword at `0x802732FE` (the previous call's accepted and moved bytes) is non-zero, a block at `0x801B9194` that Ghidra drops as unreachable; it counts on whenever the whole wait `0x802732F4` is below 0x708, which times up the entry too. Start (bit 15 of `0x8021FC90`) ends it with the character's letters. The stored name stays shown while the old count is up to 0x3B, 61 frames. `FUN_801B4AD4` stores nothing when the streak no longer makes a place. A game in mode 0 clears the entry's phase (`FUN_801B901C` in `FUN_801BDA64`). All `confirmed` from capstone (`ArcadeNameEntry`, tests/game/test_arcade_records.gd), not traced.
- Play counts `0x8036EE40` (four u16 per character, the first three picks, versus wins, versus losses): every increment saturates at 0xFFFF (`FUN_801B93E8` through `FUN_801B940C`, `FUN_801B947C`; `confirmed` decompile).

**Ending** (`FUN_801E5F50`, no movie; port `ArcadeEnding`, view `ArcadeEndingView`). `observed` sub 0 at 13191, staff from 13560, sub 0x34 at 17450, state 7 at 18069. Start after sub 3 → state 7.

- Sub 0: music 0x65, cat 43 e0 (512 × 480 logo on bronze) at VRAM (0x280, 0x300), CLUT (0x200, 0xFE).
- Sub 1: `ALL STAGE CLEAR!` c2 f1 (0x6E, 0x28) at t > 0x40; `YOU  ARE` (0x7F, 0x78), `THE` (0xCF, 0xB4), `CHAMPION` (0x7F, 0xF0) c2 f2 at t > 0x60; `YOUR TIME IS` c4 f1 (0x93, 0x154) at t > 0xA0; time, and blinking `NEW RECORD` c6 f0 (0xC3, 0x1AE) at t > 0xE0; ends at t > 0x160. The fade: `0x1FF − 4t` to t = 0x40, 0xCA held, from t = 0x120 `0xCA + 5(t − 0x11F)`: the screen goes white before the first page.
- Subs 4–0x33: ten pages of four subs each: the wait and load, the page, two frames between. `FUN_801969C8(n, …)` loads the stage, fighters and replay of the fight kept for page n (stages `0x80220FE0`, 0x17 = none, fighters `0x80221038`; the kept records are the fights the player won, so the pages of a short run are empty and skipped), `FUN_8018A988` plays it to the end of the record.
- A page lasts 400 vblanks at least: when a replay took less than `0x18E`, the load waits in a blocking `VSync` loop for `(400 − elapsed) / 2` passes of 2 vblanks, holding the picture. An empty page shows the black screen for those 400 vblanks.
- `FUN_801E5E4C` draws the page's left and right staff blocks. They arrive `0x50` frames before the replay's end, in 16 frames (offset `(N − (t + 0x40)) << 4`, N the replay's frames), and stay. `NAMCO PRODUCTION STAFF` c2 f0 (0x7C, 0x19) on page 0, until the blocks arrive.
- Subs 0x34–0x36: after a further wait of the same kind, the winner's pose on the last page's stage, slot `0xE5D` through `FUN_8018ED4C` (the replay in pose-only mode, the fighter at its root), `PRODUCED BY` (0xBD, 0xDC), logo (0xD4, 0xF0), copyright (0x30, 400 / 0x1A4) from frame 0x1E, to the move's last frame.
- Subs 0x37, 0x38: cat 43 e1 or e2 at (0, 0x200), CLUT (0x200, 0xFF), 392 × 48 logo at (70, 215), red fade in (clock from 0x140, level `(0x140 − clock)·4`), held, out (`clock·2` from 0x80). At clock 0 the ranking.
- `FUN_8018A6D0` clears the record at a round's start, so the replay always plays to the last of its 300 frames: past the round's end it shows the old contents of the ring (game-bugs.md #69).

## 3a. Scripted scenes

The attract's demonstration (`FUN_801E0E30`, port `ArcadeEnbu`) and the scene before True Ogre (`FUN_801E173C`, `FUN_801E1758`, port `ArcadeOgreScene`) share a script format and the fighters' handling (`ArcadeScene`). The stage is drawn by the fight view.

**Script:** 5 s16 per event: frame, kind, three arguments. Events are taken in order while their frame is due.

| Kind | Meaning | Arguments |
|---:|---|---|
| 0, 1 | Model of side `kind` (a new model: `FUN_8019CB04`, wait 2 frames, then 4 frames of loading, the fighter not drawn) | slot |
| 2, 3 | Move of side `kind − 2`, one frame per frame | move slot, first frame, last frame |
| 4 | Swap a side's flipbooks (`FUN_801ACA14`, 7 frames of state) | side, kind |
| 5 | Fade towards white | speed |
| −1 | End | |

A side is drawn only while its move plays (`_step_moves`' `undrawn_mask` in the port). A move's step sets `+0x48` and `+0x40` by hand and clears the row's byte `+0x17` (`LOOK_AT`) around the skeleton step. `FUN_8018C5A4`, which runs a fighter's frame events, is called for each side playing and runs both sides' events (game-bugs.md #70).

**Demonstration:** stage 4, music 0x66, first models `0xC` and 0, script `0x80186FF8` (47 events, ends at frame 3542), camera reel 0. It clears the kept fights first (`FUN_80194EFC(0)`): the demonstration's fighters are not a player's ladder. `0x8021FC64` (`fight.attract`) is set for `FUN_801D009C`. Start or a credit ends it.

**Ogre:** scripts `0x80187208` (human on side 0) and `0x8018723C` (side 1): model 26 at frame 0, moves 2331 and 2332 from frame 10, fade speed 4 at frame 192, end at frame 256; then 4 frames of solid white (`0x200`). Past fade level 0xBF the game stops drawing the stage (`0x8021F9C0`; the remake keeps it under the fade). The figure lifted is chosen by the ladder's ninth fight: its costume 0 → model 26 (Heihachi), or `0x12` (Jin) if the human plays Heihachi; otherwise `0x1B` or `0x13`. The move ends by holding its last frame, and `+0x4A` stays stale for the whole scene (game-bugs.md #71). Start skips to True Ogre. `observed`: 262 frames and white, then the fight (`contact_c.png`).

**Camera:** `FUN_801D4100(mode)` plays a list of streams from `0x80202DF8` (mode 1, the demonstration: scripts 479–500, 22 streams; mode 2, Ogre: 501), then the director takes over ([fight-frame.md](fight-frame.md) has the stream format). In total 3548 frames in the demonstration and 257 in the scene.

## 4. Asset catalogue

`arcade.py` category → TIM. "CLUT-only" = image rect 0, 0 (`FUN_801B1A94` skips it). Identification by viewing the sheets. Halve = loader drops rows at low-res.

| Cat | Entries | Content | VRAM | Loaded by, halve |
|---:|---:|---|---|---|
| 0 | 261 | MDEC pictures, 320 × 240, attract movie (15 fps) | Strips (0x200+, 0x200) | `FUN_801BE3EC`, `FUN_801BE474` |
| 1 | 59 | e0 Namco logo; e1–e48 text and HUD colour sets (CLUT-only, rows 480–484); e40 8-bit CLUT (256, 487); e49 font 1; e50 font 2; e51, e58 timer digits and ∞; e52, e53, e56, e57 round marks; e54 life caps; e55 plate backing | See below | Boot, ranking, ending; halve |
| 2 | 2 | Life fill column (786, 78), plate backing (818, 92) | | Boot; no |
| 3 | 3 | Hi-res: e0 font 0 at (768, 0) 64 × 48; e1, e2 fonts 1, 2 | | Boot; no |
| 4 | 1 | Low-res font 0 at (768, 0) 64 × 24 | | Boot; no |
| 5 | 1 | Patch of font 2: `V`, `W` | (0x368, 0x50), low-res 0x28 | Transition; halve |
| 6 | 4 | Title picture strips, 8-bit | (0, 512) | Transition; halve |
| 7 | 35 | Select: e0–3 side frames, e4–5 hazard strip, e6–7 lit panel, e8–9 metal panel, e10 divider, e11 NEW tag, e12 `PLAYER SELECT`, e13–18 and e25–30 tiles, e31–34 more tiles, e19–22 cursor frames, e23–24 1P, 2P | y 768–884, (0, 0x280) | Select; halve |
| 8 | 3 | Select panel CLUTs (256, 489), CLUT-only | | Select |
| 9 | 3 | Ranking title bands | (768, 464), CLUT (256, 485) | Ranking; halve |
| 10, 12 | 19 | Select faces 44 × 68, 44 × 34 (one-row layout) | | Select; no |
| 11, 13 | 21 | Faces 44 × 58, 44 × 29 (two rows, ranking, banner) | | Select, ranking, banner; no |
| 14, 15 | 25 | Name plates, 16 / 8 rows, 4-bit (white letters; includes unused `SOUL`, `INSECT`, a second `PANDA`) | (0x300, 0xE0 / 0xF0) or per select side | `FUN_801B3CAC`, `FUN_801BF31C`; no |
| 16 | 22 | Portraits 168 × 252, 8-bit: ids in order; e19 white silhouette (empty side, also id 19); e20 Gun Jack (attribute of id 16); e21 True Ogre; e16 is unused by the attribute table (`inferred`) | Per side | Select, VS; halve |
| 17 | 4 | VS backgrounds, 256 × 240 pixels 8-bit (128 VRAM words wide), stretched to 512 × 481: e0 lightning, e1 burst, e2 logo; e3 CLUT-only dark palette | (0, 512), CLUT (256, 485) | VS; no (e3 yes) |
| 18 | 6 | Sunset sky strips 768 × 64, 8-bit | (0, 512–832), CLUT rows 992–997 | **No reference found** (Open) |
| 42 | 7 | Fire and explosion flipbooks, 4-bit | Set by `FUN_801DBC9C` | See the [audio-and-effects.md](audio-and-effects.md) |
| 43 | 3 | Ending: e0 logo on bronze, e1, e2 large Namco logos | | Ending |

**System textures** (stay in VRAM; PS1 equivalent is the archive in `formats/system-textures.md`):

| Piece | Hi-res file | VRAM (words, 480-line) | Used with |
|---|---|---|---|
| Font 0 | Cat 3 e0 (low-res cat 4 e0) | (768, 0) 64 × 48 | tpage 0x2C |
| Font 1 | Cat 1 e49, cat 3 e1 | (768, 128) 64 × 96 | tpage 0x2C |
| Font 2 | Cat 1 e50, cat 3 e2, cat 5 patch | (832, 0) 64 × 224 | tpage 0x2D |
| Timer digits | Cat 1 e58, CLUT from e51 (384, 484) | (832, 208) 64 × 46 | tpage 0xD, CLUT 0x7918 |
| Round marks | Cat 1 e52, e53 | (768, 104), (773, 104) 5 × 18 | UV (0, 0x68), (0x14, 0x68), CLUT 0x7914, 0x7915 |
| Life caps | Cat 1 e54 | (782, 78) 4 × 24 | UV 0x38, 0x40; CLUT 0x7912 |
| Life fill | Cat 2 e0 | (786, 78) 4 × 24 | UV (0x50, 0x52); CLUT 0x7910–12 |
| Plate backing | Cat 1 e55, cat 2 e1 | (817, 92), (818, 92) 1 × 12 | UV (0xC8, 0x5C) |
| Text colours | Cat 1 e1–e48 | (256–496, 480–482) and row 484 HUD | Section 5 |

**HUD draw routine** is `FUN_8019DCA8` (called from the fight frame), pieces in section 3.

**Ranking** exists: 3 pages + name entry, stored in EEPROM. Blocks, table `0x8017992C` (12 bytes each; `FUN_801BAA84`): USER_EEP (`0x8036EE1C`, 0xD4 bytes, settings), RANKING_EEP (`0x80375034`, 0x100 bytes), SECRET_EEP (`0x802F4B8C`, 4 bytes, day). Magic `TEKKEN3A` at the table's end. `observed` defaults: time page 50'00"00 for id 0, one minute more per id, names = first 3 letters; wins page 5 down to 1.

### Movie

Category 0, attract step 0 only; its music, 0x60, belongs to the sound board and is not in the files. **None at endings.** No character endings exist. `tools/remake_import/arcade_movie.py` converts it to the PlayStation movies' format, `presentation/arcade/arcade_movie_view.gd` shows it.

**Files** (`confirmed`: the game's `DecDCTvlc`, `0x801E82E8`, run in the harness gives the converter's values on six files). 261 files of one picture each, with no container: `u16` size, `0x3800`, `u16` quantiser (1–6), `u16` version (1), then 16-bit little-endian words read from the top bit. A block starts with a raw 10-bit DC value (0x1FF there ends the picture), then MPEG-1's table B.14 of AC codes with a sign bit; `10` ends the block, `000001` escapes to 6 bits of run and 10 of level. `FUN_801BE3EC` loads the next file, `FUN_801BE474` decodes it: `DecDCTvlc`, `DecDCTin(buffer, 2)`, `DecDCTout`.

**Picture** (`confirmed`). 320 × 240 in 15 bits, 20 × 15 macroblocks from top to bottom and then the next column, each Cr, Cb, Y0–Y3. `FUN_801BE328` sends each column to VRAM as a 16 × 240 strip at (0x200 + 16·k, 0x200). The tables `MDEC_reset` sends are in the program: quantisers at `0x80204AB0` (64 for Y, 64 for colour), the IDCT's scale at `0x80204B34`.

**Arithmetic** (`observed`: gives every pixel of MAME's frames; the real MDEC's rounding is `unknown`). DC = level · Q[0]; AC = level · Q[z] · quantiser / 8, truncated towards zero; the IDCT with `(s[u][x] · s[v][y]) >> 9` and a last `>> 23`; R = y + (1435·cr >> 10), G = y + (−351·cb >> 10) + (−731·cr >> 10), B = y + (1814·cb >> 10), clipped to −128…127, plus 128, `>> 3` to 15 bits.

**On screen** (`confirmed` in the code, `observed` in MAME's frames). `FUN_801BE1C0` draws five quads 0x68 wide and 480 tall, 64 × 240 texels each: 520 pixels, so the picture's right side passes the 512-wide screen. Black rectangles cover the last two lines (y 0x1DE) and columns (x 0x1FE). MAME's frames are 512 × 240, with lines 0–9 and 238–239 black on every screen, the title's too.

**Time** (`observed`: `tools/research/arcade_movie_capture.lua`, a snapshot and the state at each MAME frame). One pass of the main loop per 4 vblanks (`FUN_801BD318`, picture kind 1). The timer `0x8021FD4C` goes 0 … 263 (the length `0x8021F284` is 262), 264 passes or 1,056 vblanks: sub-state 2 from frame 8527, sub-state 9 from frame 9579 (1,052 vblanks), the title's picture from frame 9583. Pass `t` decodes file `t`, but the screen shows file `clamp(t − 2, 0, 260)` (why two passes: `inferred`, the upload queue runs at the start of the next loop). Past the last file `FUN_801BB648` loads nothing and the old buffer is decoded again, so the last picture stays. Files 0 and 1 are black. The last pictures fade to white, and the title then fades from white.

**Proof.** `tools/research/verify_arcade_movie.py`: 0 of 1,083 MAME frames differ (timers 0–263, 5 bits per channel, lines 10–237, columns 0–509); four negative controls (`--control`: picture one file off, chroma swapped, a wrong scale, a damaged stream) fail. With `--out` it checks the encoded movie too: 264 frames at 15 fps, a PSNR against the decoded pictures.

**In the remake.** The video has one frame per timer value, the two passes' delay and the repeats baked in: 264 frames at 15 fps, 17.6 s. The flow's `step` is one pass, as in the original, so `ArcadeGameFlow.frame_vblanks()` says how long the frame lasts and `arcade_game.gd` waits the rest. Theora cannot seek: `ArcadeMovieView` brings the player to the frame the timer names by its speed and holds it there; the JPEG fallback shows the frame directly. Without the `movies` group the screen stays black, the time the same. Start is read once per pass, as in the original, so a tap shorter than 4 vblanks can be missed.

## 5. Text system

`FUN_801B25B8(fmt, …)`. Glyph sprite `FUN_801B253C` (code 0x65, SPRT), scratch `0x1F800380`, position persists across calls.

Codes: `%c` colour; `%f` font; `%H`, `%V` pen in pixels (V is shifted at low-res); `%h`, `%v` in cells; `%C` char; `%s`; `%d`, `%D` (BCD `FUN_801B20D0`); `%x`; `%b`; width digits; `%0`; `%p` OT layer. Also `\n` and space. Digit lookup `0x80178E64`.

Colour `FUN_801B2488`: CLUT id `((c + base) >> 4 + 0x1E0) · 0x40 | ((c + base) & 0xF) | 0x10`, so x = 256 + 16·((c + base) & 15), y = 480 + ((c + base) >> 4). PS1 uses rows from 504, otherwise the same.

Fonts `0x80178E14`, 0x14 bytes × 3, copied to RAM `0x802731F4` by `FUN_801B2B54(lowres)`:

| Font | Glyph | Advance | Line | tpage | CLUT base | UV table hi / low (indexed by character code) |
|---:|---|---:|---:|---|---:|---|
| 0 | 12 × 16 | 12 | 18 | 0x2C | 0 | `0x80178ACC` / `0x80178C50` |
| 1 | 18 × 24 | 18 | 26 | 0x2C | 0x10 | `0x80178B50` / `0x80178CD4` |
| 2 | 32 × 40 | 30 | 42 | 0x2D | 0x20 | `0x80178BD0` / `0x80178D54` |

Low-res halves glyph height and line. Compare PS1 10 × 16, 14 × 24, 24 × 40. The tables start low because only codes ≥ 0x20 are used (their bases overlap strings). The `hud.py` route of glyph sheets works unchanged with these tables.

Strings used by the flow:

| Address | Text | Address | Text |
|---|---|---|---|
| `0x8015F4C0` | ROUND | `0x8015F574` | K.O. |
| `0x8015F4D4` | FINAL ROUND | `0x8015F584` | DRAW |
| `0x8015F52C` | READY? | `0x8015F594` | GAME OVER |
| `0x8015F53C` | TIME UP | `0x8015F5A8` | %s WINS! |
| `0x8015F54C` | PERFECT! | `0x8015F5DC` | YOU WIN! |
| `0x8015F560` | DOUBLE K.O. | `0x801793C4` | CHALLENGER |
| `0x801789FC` | INSERT COIN(S) | `0x801793EC` | NEW FIGHTER |
| `0x801789E8` | INSERT MORE COIN(S) | `0x80179428` | ARE SELECTABLE! |
| `0x801789D0`, `…B8` | PUSH P1 / P2 START BUTTON | `0x80187E10` | YOUR TIME IS |
| `0x801789A0`, `0x80178984` | PUSH P1 OR P2, AND/OR P2 BUTTON | `0x80187E28` | NEW RECORD |
| `0x80178A0C`, `0x80178A58`… | INSERT COIN, side prompts | `0x80178AE0` | FREE PLAY |

The strings are in the program, so a remake reads them through a `GameRam`-like image of `prg_world_e1` and they stay out of git.

## 6. Proof and corrections

`tools/research/arcade_flow_trace.py` runs `main` from boot in the CPU harness (`arcade_fight_harness.py`) with scripted panels and writes a trace (`work/traces/arcade_flow_<scenario>.bin`). `remake/tests/game/test_arcade_flow_traces.gd` replays its panels through `ArcadeGameFlow` and compares the state, sub-state, timers, `rand`, the frame's generator, the mode context, the select's records and sparks, the ranking's records and both fighters' skeletons every frame. Headless MAME (`work/arcade/flow/run/*.log`) is the second, independent witness of the timings.

Scenario `solo` (an idle player, 9,000 frames) matches from boot through the transition, the attract, the select, the VS screen, the load, real rounds, continue, game over, the ranking and back to the attract. `continued` adds a continue with Start and `challenger` a second player joining in a fight, with the stopped fight behind the message and the select that follows (12,000 frames each). Scenario `attract` (no input, 15,000 frames) matches the whole attract loop: demonstration, title, demo with its GAME OVER, movie, ranking with its records.

Scenario `ladder` (40,000 frames) wins the whole ladder: the harness takes the CPU's health `ko_after` (120) frames into each round's fighting (`ko_side`, written to the trace's header), and the test does the same to the port, so every round is a real one. It matches through all ten fights, the Ogre scene, True Ogre, the ending with its kept fights and the winner's pose, the ranking with the new time record and its name entry (left to time out, so the record takes the character's name), and back to the attract. The trace in `work/` was recorded before the day was written after the boot, so it runs at day 0 (the test reads the day from the trace).

Skeletons are compared from the first frame a fighter is posed in: until then the game's memory still holds the last fight's pose.

The scenes' and the ending's pictures were compared with MAME by eye (`contact_a1.png`, `contact_c.png`): their timing is proven, and the demonstration's skeletons too (`attract`); a scene's camera is not in a trace yet.

What the reading above got wrong or left out, found by these runs (`confirmed`):

| Subject | Correction |
|---|---|
| Decompiler | Ghidra folds loads of BSS globals to 0: the VS screen's slide prints as `0x8027324C = -1`, the instructions at step 3 decrement it. Read such writes in capstone. |
| Movie length | `FUN_801BE180(0)` returns the word for file group `0x8021F290[0]` from `0x801FF73C`, which reads 1 in the image: `FUN_801BB748` replaces the table's counts at boot by the number of files in each group. Group 0 has 261 files, so `0x8021F284` = 262 and the timer ends at 263 ([Movie](#movie)): 263 passes × 4 vblanks = 1,052 frames in sub-state 2, as MAME shows, and one pass more in sub-state 9. |
| Movie frame | `FUN_801BD318` kind 1 waits until 4 vblanks have passed since the frame's start (`0x801BD380`): the harness counts them in a hook, since it has no interrupts. |
| Select | The portrait's `+0x34` fade counter goes down in the draw code (`FUN_801BFA7C`) only from the frame the screen draws: the frame count goes up first (`FUN_801BF31C`), then `frame > 2` is tested. |
| New records | `FUN_801B4C60` (time) and `FUN_801B4D68` (wins) give a new record the blank name at `0x8021F1A4` (three spaces); the name entry starts from `0x8021F244`, three more spaces that no code writes (`FUN_801B8E04`; blank in every frame of every trace), so the record reads the cursor's letter and blanks while the player enters it. The character's first three letters (`FUN_801B8CD4`) come only when the entry ends blank or rejected, e.g. on time-out. |
| Model change | A new model does not clear the record's joints (`+0x75C`): the first frame reads the last pose. True Ogre's sway height comes from joint 6 of the frame before (`FUN_80193B20`), so his first frame after the Ogre scene depends on Ogre's last pose in it. |
| Day counter | `FUN_801BACAC` at start-up clears the day `0x802F4B8C` when the backed-up clock is invalid, as it always is in the harness: a scenario's day has to be written after the boot. |
| Stopped fight | `0x8021FAD0` makes `FUN_8018A988` only draw, read the panels and go on with the round's voices; the routine clears `0x8021FBD0`, not this flag, at its start. The challenger's message sets it, when `FUN_8018A988` returned a round state above 0 or the timer ran out, and so does the ending between two kept fights. |
| Kept fight's camera | In the ending's second kept-fight playback (`play` 2), the replay's root step for fighter 1 (`FUN_8019571C`) also starts the replay camera (`FUN_801D6DA8`), which draws `rand` twice. |
| Ending's page wait | The wait that makes a page last 400 vblanks (`(400 − elapsed) / 2` passes of 2 vblanks, a quarter for the pose) is one frame's length, not extra passes of the frame: nothing but `VSync` runs in it. The harness has no vblank interrupt, so the frame counter `0x8021FD58` leaves those vblanks out, and so does the port; on a board the handler `0x801BBCCC` counts them (`inferred`), which would only shift what the counter times, such as blinks. |
| Initial values | `0x8021F22D` = 2, `0x8021F22E` = 4, `0x8021F232` = 4 in the image; `0x8021F288`, `0x80374F36` start at 0. |
| Scene moves | The byte `+0x17` a scene clears around a move's step is the row's `LOOK_AT`. |
| Scene fighters | A fighter that lost the fight is inactive but drawn in the Ogre scene: the scene draws by its own mask, not by `active`. The mask does not outlive the scene: `FUN_8018A6D0` clears it. |

## Open

- Category 18 (sunset strips): no reference found by number or in the stage category table `0x8017C320`.
- Cat 1 e51 at (896, 0): same digits as e58; only its CLUT is confirmed in use. Cat 16 e16 and cat 14 `SOUL`, `INSECT`, second `PANDA`: apparently unused.
- `0x1F083032`: what it holds on real hardware (`inferred` board value). Decides how a real board's day advances, not needed in the remake.
- `FUN_801BCC98` records to `0x1F083820`: purpose is `inferred` only.
- Not exercised in MAME: `FUN_801B9138` winner name entry, Jin as boss, event mode, reselect at continue (EC57), hi-res mode 4 (asset paths read only), all intruders (read only; run c at day 120 has no candidate, so its Bryan was a pool pick), the secret title display.
- Field labels of `0x801FFAA8`, `0x80179B58`, `0x801FF5C4` are `inferred` from use; port from the routines named before relying on them.
- The ending's page wait on a board: whether the vblanks it holds reach `0x8021FD58` (the harness cannot show it; see [section 6](#6-proof-and-corrections)).
- Raw pad bits forcing a ranking page at sub 0 of state 7: meaning of the bits on the cabinet not checked.
- `FUN_801B0ACC(1)` in state 3 and the music numbers are left to the [audio-and-effects.md](audio-and-effects.md).
