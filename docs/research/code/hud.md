# HUD and on-screen text

Health bars, timer, round marks, name plates and the round messages are 2D sprites drawn by `HudRoundUpdate` (`0x8003D904`, step 4 of the [fight frame](fight-frame.md)) from the [system textures](../formats/system-textures.md). Addresses are Japan Rev.1.

Status: `confirmed` from the decompiled code; positions are in frame-buffer pixels.

## Screen

The fight runs in display mode 0 of the table at `0x800B1190` (16 bytes per mode, set by `FUN_800B0D08`): a 384 × 480 interlaced frame buffer (`GsInitGraph(384, 480, 5)`), of which 368 × 448 starting at line 20 is shown; the 3D projection centre is (192, 240). Mode 1 is 320 × 224 for other screens. All HUD coordinates below are in the 384 × 480 space (y therefore covers two field lines per unit).

Sprites are `SPRT` packets (code `0x65`, semi-transparent flag set) with a UV/CLUT word; bar fills and plate backings are `POLY_FT4` (code `0x2D`). They are linked into the HUD ordering table `0x800A96E0` (`FUN_8004DCA4`, `FUN_8004DB18`, `FUN_8004DD90` sets the texture page).

## Elements

| Element | Routine | Layout |
|---|---|---|
| Health bars | `FUN_8004E55C` | Player 1 at (10, 40), player 2 at (202, 40); 152 pixels plus 6 × 24 end caps (UV `(0xE0, 0xA8)`, `(0xEA, 0xA8)`, CLUT `0x7EDE`). Player 1's bar is anchored at its inner end (x + 154) and shrinks outwards, player 2's mirrored. |
| Timer | `FUN_8004E410` | Two 16 × 46 digits at x = 184 and 169, y = 22, UV `(16·d, 0xD0)`, CLUT `0x7F1C`; value `(frames + 59) / 60`, or `∞` (digits `0xA`, `0xB`) with infinite time. |
| Round marks | `FUN_8004E87C` | One 15 × 18 mark per round needed to win at y = 70: player 1 from x = 151 leftwards, player 2 from x = 202 rightwards, 14 apart; won marks CLUT `0x7F18`, empty `0x7F19`; the mark just won blinks (`0x800AE6E0 & 0x10`). |
| Name plates | `FUN_8004EB9C` | Name sprite at (14, 66) for player 1 and (354 − width, 66) for player 2, on a backing quad from 4 pixels left of the name to 4 right, y + 9 to y + 19, with a colour from `0x80022198`. |
| Mode line | `FUN_8004EFF8` → `FUN_8004EE3C` | Per player at y = 24, x from `0x80022228`: arcade stage (overlay), `GAME OVER`, team members left, `TEAM BATTLE`, `TIME ATTACK`, `SURVIVAL`, survival count and time, `TEKKEN BALL`, or in Tekken Force `SCORE` / `HI-SCORE` (8 digits). |
| Tekken Force progress | `force.ovl` `FUN_800B3D34` (built by `FUN_800B396C`) | Four 60-pixel segments from x 64, y 436–452, one per level, textured with one-colour CLUTs (RGB (0, 64, 128), (0, 128, 32), (128, 128, 0), (128, 16, 0)), semi-transparent. Levels already reached are lit (grey 128), later ones black. The current one is additive and pulses (brightness 128–255 with a sine, phase +64 per unpaused frame) up to the marker. The marker is a white line at the camera's progress (60 pixels per `0x8000` units from the level start, capped at the segment's end, the end once the level has ended) under a blue-to-white triangle whose width swings with the same sine. There are five grey separators at x 63 + 60k. Level 5 (the Doctor B. level) shows a 12-pixel fifth segment. Ported in `force_sim.py` (`progress_setup`, `progress_draw`). |
| Tekken Force keys | `force.ovl` `FUN_800B4924` (sprites built by `FUN_800B4740`) | One 20 × 36 sprite per key earned (`0x800B70D0`): copper, silver, gold at x 0, 20, 40, y 420, from VRAM (688, 320 / 356 / 392), CLUT (128 / 144 / 160, 486), draw mode `0xE100021A`. Hidden while text is off. Ported in `force_sim.py` (`key_icons`). |

**Health bar animation.** Each bar keeps three lengths (`0x800980F8 + 0x10·player`): the target `⌈health / (max / 152)⌉` (recomputed when health changes), the drawn health length, which drops to a lower target at once and grows towards a higher one by 3 pixels per frame (the refill at a round start, when `FUN_8004E520` has emptied all three), and a "recent damage" length that closes on it by 1/16 of the difference per frame (rounded up). `FUN_8004E868` stores both fighters' round wins at the round start (`0x80098114`), so the mark of a round won since then blinks. The fill is drawn as three stretched quads (UV column `0xE8–0xE9`, rows `0xA8–0xC0`): health (CLUT `0x7EDC`), recent damage (`0x7EDD`) and empty (`0x7EDE`).

## Round messages

`HudRoundUpdate` also runs the round text by `RoundFlow` state ([fight-frame.md](fight-frame.md#round-flow)); frame numbers count from the start of the intro (first round / later rounds):

| When | Text (colour, font, x, y) | Voice |
|---|---|---|
| Intro, frame 61 / 1 | `ROUND n` (8, 2, 107, 112), `FINAL ROUND` (x 63) on the deciding round; `TEAM BATTLE`, `SURVIVAL BATTLE`, `PRACTICE MODE`, `STAGE n` / `FINAL STAGE` in the other modes `0x103B` before the deciding round, `0x103A` on it (`FUN_8003DCE0`), then, except on the deciding round, the round number from `0x8001A3BA[round]` at frame 100 / 40 |
| Intro, frame 106 / 46 | `READY?` (9, 2, 118, 228) | `0x103C` ("fight") at frame 150 / 90 |
| Result | `K.O.` (1, 2, 140, 228), `DOUBLE K.O.` (x 63), `PERFECT!` (2, x 96), `TIME UP` (3, x 107) | From `0x8009749A…0x800974A8` by the result flags (time up, double KO, perfect, great, KO) |
| Winner | Voice (`FUN_8003E2F8`, first frame of the result display): `0x1014` for a draw; with two humans (or in team battle) the winner's own voice `0xC640` (`0xC64B` for voice set `0x15`) through `ResultWinVoice`, followed by `0x86DA` once it ends (effect type 16), or `0x1011` for a costume without one (Tiger); with one human `0x1011` when the human won, else `0x1012`. A decided match also fades the music out over 180 frames. Text: `YOU WIN!` (4) / `YOU LOSE` (5) at (96, 368) by the human sides (`0x800AE3D8`); `<NAME> WINS!` (4) centred at y = 368 in team battle and 2-player tie-break mode, with `WINNER` / `LOSER` labels at y = 104 over each side in 2-player arcade; `DRAW` (6, 140, 368) | — |
| Game over | `GAME OVER` (2, 1, 126, 260) in mode 6 | — |

## Text engine

`FUN_8004D15C(format, args…)` prints with the fonts of the system archive. Each glyph is a 5-word `SPRT` packet (code `0x65`, raw texture) linked into OT entry 7 (`*0x800A96E0 + 0x1C`). The format is `printf`-like, and `%` codes consume one 32-bit argument each. The routine is ported in [`tools/research/draw_sim.py`](../../../tools/research/draw_sim.py) (`print_text`) and matches the game byte for byte ([tooling.md](../tooling.md#verification-log)).

**Fonts** (`0x80021FD0`, 16 bytes each: glyph UV table, advance, line height, glyph width and height, texture page, CLUT offset):

| Font | Glyph | Advance | Line | Texture page | CLUT offset |
|---:|---|---:|---:|---|---:|
| 0 | 10 × 16 | 9 | 18 | `0x2D` | 0 |
| 1 | 14 × 24 | 13 | 26 | `0x2D` | 16 |
| 2 | 24 × 40 | 22 | 42 | `0x2E` | 32 |
| 3 | 24 × 40 | 21 | 42 | `0x2E` | 32 |

Font 0 is the default at every call.

**State.** The pen (`0x8009F65C/5E`), the left margin (`0x8009F658/5A`) and the colour (`0x8009F660`) carry over from one call to the next.

**Colour.** Colour `n` with the font's CLUT offset `k` selects the CLUT at `x = 256 + 16·((n + k) & 15)` and `y = 480 + ((((n + k) >> 4) + 24) & 31)` after `%c`. At the start of a call and after `%f` the row is instead `(((n + k) >> 4) + 24) | 480`.

**Characters:**

- A space advances the pen.
- `\n` moves the margin down by the line height and puts the pen at the margin.
- Every other byte is a glyph.
- Spaces and new lines are handled even inside a `%` code.

| Code | Meaning |
|---|---|
| `%c` | Colour. |
| `%f` | Font. The current texture page is flushed first (`DR_MODE`). |
| `%H`, `%V` | Pen and margin x, y. |
| `%h`, `%v` | The same in units of the advance and the line height. |
| `%p` | Link into OT entry `n` from now on (flushes the texture page). |
| `%s` | String: spaces advance, everything else is drawn, `\n` and `%` included. |
| `%C` | One character (the low byte of the argument). |
| `%d`, `%D` | Decimal (`%d` signed with a `-` glyph). Values are converted to BCD (`FUN_8004CE74`): anything above 100,000,000 prints `99999999`, while exactly 100,000,000 becomes `0xA0000000`. |
| `%x`, `%b` | Hexadecimal, binary. |
| `%%` | A `%` glyph. |

A width digit `1`–`8` may precede a number, optionally after a `0`:

- With a width but no `0`, a shorter number is right-aligned by advancing the pen.
- With `0`, or when the number is longer than the width, exactly `width` digits are printed: the top digits of a long number are cut, and a short one gets leading zeros.
- For `%d`, a negative number's `-` takes one place of the width.

Any other code calls `exit()`. At the end, the texture page is flushed, and the pen, margin and colour are saved.

All fixed HUD strings of the executable use the prefix `%c%f%H%V` (colour, font, x, y); the complete list is in the executable at `0x8001A37C–0x8001A560` and `0x80022234–0x800222BC`.
