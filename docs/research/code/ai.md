# CPU opponent

The computer opponent produces controller input: every frame it writes a held and a pressed pad word that go through the same `InputUpdate` as a human pad, so it can only perform moves that the move data allows from the current state. Its choices are drawn from the running move's **branch list**, filtered by hint bits stored in the move rows and weighted by difficulty tables. Addresses are Japan Rev.1.

Status: `confirmed` and ported. `tools/research/ai_sim.py` (helpers, filters, hooks, reset) and `tools/research/ai_update.py` (`AiUpdate`) reproduce the game bit for bit. `tools/research/verify_ai_sim.py` checks them against the original code in the CPU harness: random states, states steered into each decision, and mid-function probes that change the record identically in the game and the port. Every routine matches with 0 differences, including the Tekken Ball helpers in `volley.ovl` (checked with that overlay loaded).

## Entry and state

`InputSource` (`0x8002BF3C`) reads the per-player input mode (`0x80095894`: 0 = none, 1 = live, 2 = scripted word at fighter `+0x408`). Live input goes through `CpuOrPadInput` (`0x8002C4CC`): a fighter with `isCpu` (`+0xC5`) calls `AiUpdate` (`0x80059B78`), otherwise the pad words are used; there L2 and L1 act as side-step shortcuts (a press becomes an up or down tap held for two frames and remembered for 35 frames).

Each CPU fighter owns a `0x330`-byte record at `0x8009F6C0 + 0x330·slot` (slot in fighter `+0x1886`, target fighter at record `+0x10`). `AiInitRound` (`0x8005993C`) assigns slots and targets at round start; `AiReset` (`0x800596B0`) clears the record and loads the difficulty parameters.

| Record offset | Content |
|---:|---|
| `+0x00`, `+0x02` | AI slot; frame counter (advances whenever the fighter's pose frame changes; bit 0 alternates the candidate walk direction). |
| `+0x04`, `+0x06` | Held pad word produced this frame; the previous frame's. |
| `+0x08` | Pointer into a multi-frame input script (`u16` steps: direction in bits 0–3 through the numpad→pad table `0x80023288`, buttons in bits 8–11). |
| `+0x0C` | The bank's move index. |
| `+0x10` | Target fighter. |
| `+0x14` | Distance band 0–5 (0–1 inside the first threshold; 0 when either fighter is being pushed; thresholds `+0x314..+0x31A` from the table `0x80098640` by the CPU's `+0x18`). |
| `+0x18` | Reach band 1–5 of the opponent: the distance (reduced by an approach) against the opponent's thresholds `+0x320..+0x326` plus margins `0x80`, `0x100`, `0x200`, `0x280`. |
| `+0x1C`, `+0x20`, `+0x24` | Distance, previous distance, change. |
| `+0x28` | The CPU's move changed (or its frame went back) this frame. |
| `+0x2C` | Frames in the current move. |
| `+0x2E` | The CPU's angle to the opponent (fighter `+0x30`). |
| `+0x30` | The CPU's health last frame. |
| `+0x38`, `+0x3A`, `+0x40`, `+0x48` | Approach timers (reset to `0, 0, 40, −1` by `FUN_80056A30`). |
| `+0x3C`, `+0x3E` | Standing with state bit 0 (and not 2 or 9); guarding last frame. |
| `+0x42`, `+0x44`, `+0x46`, `+0x4C` | Cool-downs: bank setups, neutral-move repeats, air moves, keep direction after a crouch attack. |
| `+0x4A` | Crouch hold timer (random 20–49 frames while crouching). |
| `+0x50`, `+0x52` | The CPU's move has an active window; its move is usable in the air or as a special and its window is still open. |
| `+0x54` | Set to 30 when the CPU whiffs close up. |
| `+0x58`, `+0x4E` | The move the candidates were collected from and its frame. |
| `+0x5C`, `+0x60` | The move pressed this frame; the last attack executed. |
| `+0x64` | Situation bits: 1 turned away (`relAngle > 0x4000`), 2 and 4 turned to either side, 8 the opponent's high attack `0x412` is coming within `0x700` units (condition `0x30`), `0x10` facing the opponent. |
| `+0x68` | Wait before the next attack; counts down in several places, −1 means "attack now". |
| `+0x6A` | The CPU already holds the guard that stops the opponent's attack level. |
| `+0x6C` | Frames to wait before guarding an attack that is coming (−1 none). |
| `+0x70`, `+0x72` | Candidate count and number of marked candidates. |
| `+0x74`, `+0x78` | Character-specific hooks (below). |
| `+0x7C` | This frame's extra candidate filter (only `FUN_800616B4`). |
| `+0x80`, `+0x84` | Frames the opponent's attack has been announced; frames since the opponent's attack passed while the CPU attacks. |
| `+0x88` | The opponent is Yoshimitsu in slot `0x456`. |
| `+0x8A`, `+0x8C` | Frames without movement decisions; frames with the guard step suspended. |
| `+0x8E..+0x94` | Flags: kind-9 parry used, punish chance (`+0x8F`, also set after an opponent's whiff), throw/down chance (`+0x92`), evasion state (`+0x94`, below). |
| `+0x96`, `+0x9C`, `+0xA0`, `+0xBC` | Throw: follow-up count, frame to press, throw move, chosen row. |
| `+0xC0..+0x1A4` | Follow-up lists built when a move starts (strings `+0xC4`, planned follow-ups `+0xDC`, frame-1 rows `+0x1A4`); never executed ([below](#follow-up-lists)). |
| `+0x1D2`, `+0x1D4` | Attacks started in a row; their limit (the larger of words 25 and 27). |
| `+0x1DC..+0x1FC` | History of the last 8 opponent moves that hurt the CPU, and its write index. |
| `+0x1FE`, `+0x202` | Frames until the parameters are reloaded; the adaptive mode is on. |
| `+0x200`, `+0x201` | The opponent is Ogre breathing fire / Gon in a special move. |
| `+0x208` | The opponent is down (state bits 2 or 9, not stance `0x4C02`) and not airborne. |
| `+0x20A` | Frames until the opponent's current attack is active (999 when it is not attacking). |
| `+0x20C`, `+0x20E`, `+0x210`, `+0x214` | The opponent's attack is coming; frames of an announced unblockable; frames in state bit 19; the opponent grabs (`+0x08` bit 22). |
| `+0x216` | The opponent's attacks in the current string (−1 when it is not attacking). |
| `+0x21A` | The opponent is high in the air (joint 2 above −3,099). |
| `+0x21E` | Input mode: 0 no input, 1 hold up while crouching, otherwise AI. |
| `+0x220..+0x234` | The CPU's and the opponent's move state and attack words, cached. |
| `+0x238` | Difficulty parameters (110 bytes). |
| `+0x2A6` | Common parameters (110 bytes from `0x8002408E`). |
| `+0x314`, `+0x320` | Band thresholds of the CPU and the opponent (12 bytes each from `0x80098640`). |
| `+0x32C` | Tekken Force: pointer to the pattern words (`0x80023210`). |

## Difficulty parameters

`AiLoadParams` (`0x80061770`) copies 110 bytes from `0x80023418 + 0x44C·group + 0x6E·level` (3 groups × 10 levels) into the record: `group` is the difficulty option (`0x800AE6D0`, clamped to 2) and `level` the CPU strength (`0x800AE6D9`, 1–9; the arcade mode raises it stage by stage). The record is reloaded when its countdown `+0x1FE` expires. The words are mostly probabilities out of 4,096 compared with a 12-bit random number (`rand()` mixed with the LCG `0x800AE168 = 5x + 3`) and frame delays; for example words 3–6 fall from `150, 200, 200, 250` at the easiest setting to `10, 30, 30, 30` at the hardest, and the escape and follow-up probabilities rise from 0 to about 70 %. Individual meanings are listed where identified:

| Word | Use |
|---:|---|
| 0–1 | Four bytes: a random one gives the length of a held input (`+0x238 + (rand & 3)`). |
| 2–6 | Wait after starting an attack: word 2 plus a random one of words 3–6, in frames (`AiAfterAttack`); `AiReset` halves words 3–6 in some situations. |
| 7 | Maximum number of follow-up steps of a multi-part throw (`+0x246`). |
| 8 | Probability of a throw attempt at close range (`+0x248`); zero while the opponent is dangerous (attacking, airborne, Gon, or its attack is less than 10 frames away). |
| 9 | Probability of trying to escape a throw (`+0x24A`). |
| 10 | Probability of continuing a multi-part throw (`+0x24C`). |
| 11 | Choice between the two throw lists at close range (not against Gon), and King's hook (`+0x24E`). |
| 12, 13 | Probabilities of the two extra candidate filters `FUN_80057954` and `FUN_80057820` while collecting attacks; set to 0 when the opponent has 10 % health or less. |
| 14, 15 | Reaction 2 (guard or evade) while the opponent's attack is coming (`+0x254`; word 15 also as a second chance for long announced attacks). Each hit the CPU takes raises word 14 by 10 up to word 15 (not in the demonstration fight: with the attract flag `0x800AE39C`, which only mode 6 keeps set, every CPU plays at level 4 with words 3–6 halved and word 14 quartered). |
| 16, 17 | Punish and hold-guard probability (`+0x258`), plus `+0x216 · difficulty · 30` after an opponent's whiff; +10 per hit taken, capped by word 17. Word 17 is also the chance to answer a move that already hurt the CPU. Words 12, 13, 16 and 17 are zeroed when the opponent has 10 % health or less. |
| 18 | Side step against an attack arriving in 9–11 frames (`+0x25C`); the chance of movement choice 8. |
| 19, 20 | Counter-attack while the opponent's attack is coming (`+0x25E`), +20 per hit taken, capped by word 20. |
| 21, 22 | Duck or step back from an attack that is coming (`+0x262`), +40 per hit taken, capped by word 22. |
| 25, 27 | The larger of the two is the number of attacks the CPU starts in a row before it pauses (`+0x1D4`). |
| 29 | Probability of consulting the character hooks (`+0x272`); also the evasion pick and the forced throw escape. |
| 30 | Attack an opponent in state `0x4C02` (`+0x274`). |
| 35 | General "focus" threshold (`+0x27E`): most secondary draws compare against it. |
| 36 | Back away from an opponent's air attack at close range (`+0x280`). |
| 38 | Probability of keeping movement choices 3 and 6 (else no movement). |
| 45 | Bank-specific counter moves (reactions 5–8) when the reach band matches (`+0x292`). |
| 47 | Guard or evade against a grab (`+0x22C` bit 22) (`+0x296`). |
| 49 | Probability of a stance action (`+0x29A`). |

Words 31–34, 37, 39–44, 46, 48 and 50–54 are never read (checked in the resident code, the overlays and the raw instruction stream).

Words 23, 24, 26 and 28 are read only by the dead follow-up code ([below](#follow-up-lists)): word 24 or 28 would be the probability of pressing a random open follow-up, word 23 a cap on repeated attempts (`+0xC0`), word 26 the chance of keeping the follow-up flags. `FUN_800593D4` (a whiff-punish test with word 35) is only called from that dead code.

Each hit taken with `+0x216 > 0` also raises words 21 and 19 by 40 and 20 (caps 22 and 20).

**Adaptive difficulty.** When the CPU loses health and a draw passes word 35, its wait `+0x68` drops by 3. In one-on-one play the opponent's move is also written into an 8-entry history (`+0x1DC`). If that move is already in the history twice, the parameters are reloaded at level 9 of the current difficulty group for 600 frames (`+0x1FE`, flag `+0x202`), and the CPU then answers that move more often (word 17). Repeating one move therefore makes the CPU stronger for ten seconds.

## Candidates from the branch list

`AiCollectCandidates` (`0x80056A4C`) walks the running move's branch list (expanding `0xC00C` common rows) and keeps every row whose window contains the current frame, whose restriction byte accepts the fighter, and whose condition holds (`BranchCondition`, with conditions `0x24–0x27` and `0x30` taken from the cached situation bits). Each candidate stores the target move row, the branch row and a mark (`0x8009FD20`, 12-byte entries, at most 180). A final pass marks as unusable (−1) the candidates whose target has state bit 23, and those equal to an uninitialised stack word; that word never holds a move row in the game ([game-bugs.md](game-bugs.md) #17), so ports pass `stale=None`.

The filters `FUN_8005758C`, `FUN_800576DC`, `FUN_80057820`, `FUN_80057954`, `FUN_80057AC4`, `FUN_80057C88` and `FUN_80057E48` mark candidates by properties of the target move:

- it is an attack (`+0x2D ≠ 0`) and not excluded by the AI hint bits (below);
- its reach bits match the current distance band: band 1–2 any reach, band 3 short or medium, band 4 long, band 5 none (`0x80098610`);
- its attack level suits the opponent's posture (for example no highs against a crouching opponent, lows against one that guards high, mids against low guard);
- its startup (`+0x2D < 14` for fast attacks), damage sign, air window and state flags.

Each filter marks unmarked candidates (mark 0 → 1) and adds the count to `+0x72`. "Reach" below means the target's reach bits (none = close or middle) meet the band mask `0x80098610[+0x14]`. An attack has an active window, no air window, no "never chosen" hint and no state bit 17.

| Filter | Marks |
|---|---|
| `FUN_8005758C` | Ground moves (or state bit 19, or hint bit 5): side steps `0xC001`, state bit 19 moves, and attacks in reach (state bit 16 overrides the reach). |
| `FUN_800576DC` | The same attacks without the words `0x412` and `0x706`. |
| `FUN_80057820` | Damaging attacks with startup below 14 frames. |
| `FUN_80057954` | Attacks in reach whose level suits the opponent's posture (`+0x230`): bit 1 no `0x412`; bit 0 neither `0x412` nor `0x10F`; bit 2 neither `0x412` nor `0x217`. |
| `FUN_80057AC4` | Attacks in reach that hit the opponent's state: stance `0x4C02` any; bit 10 `0x412/0x217/0x31F`; bit 2 `0x10F/0x51F`; bit 0 `0x217/0x10F`; bit 1 `0x10F/0x217/0x412`. |
| `FUN_80057C88` | As `FUN_80057AC4` without `0x412`. |
| `FUN_80057E48` | Attacks in reach from rows without direction bits (plain buttons). |
| `FUN_80058040` | Damaging attacks in reach faster than the opponent's attack (`+0x20A`). |
| `FUN_8005817C` | The same without `0x412`. |
| `FUN_80058AC0` | Side steps (`0xC001`) with probability 32/4096 at band 2 and 1024/4096 at band 3, then `FUN_8005817C` (opponent state bit 0) or `FUN_80058040`. |
| `FUN_800582A0` | Guard and evasion rows against the opponent's attack word ([below](#reactions)). |
| `FUN_800616B4` | Unmarks candidates with hint bit 0 or the word `0x10F`. |

`AiExecuteCandidate` (`0x80058D6C`) draws `k` below the marked count and walks the table: backwards on even `+0x02` frames (uniform), forwards on odd ones, where it stops at `k ≤ 0` and therefore favours the first marked candidate ([game-bugs.md](game-bugs.md) #19). `AiPressCommand` (`0x80061BA8`) turns the command word into pad input: direction bits (5–13) select the most specific numpad direction (table `0x800232A8`, pads `0x800232BC`), bits 0–3 the buttons (`0x800232D0`), and motion commands (`0xC001`, `0xC002`, `0xC00E..`, `0xC7FF..`) become a script from `FUN_8002CFD0` (`0x8001006C`, `0x80010078`, `g_inputSeqA/B`). `AiAfterAttack` (`0x80058C40`) then counts forced "never chosen" moves (`+0x96`) and, for an attack, sets the wait `+0x68` to word 2 plus a random one of words 3–6.

### Move row hint bits

The byte at move row `+0x0A` (bits 16–23 of the `u32` at `+0x08`) exists only for the AI:

| Bit (of the byte) | Mask in the word | Meaning |
|---:|---:|---|
| 0 | `0x10000` | Treated as a safe/priority attack by several filters. |
| 2 | `0x40000` | Reach: close. |
| 3 | `0x80000` | Reach: middle. |
| 4 | `0x100000` | Reach: far. No reach bit means close or middle. |
| 5 | `0x200000` | Usable as an airborne or special move. |
| 6 | `0x400000` | Never chosen by the AI (counted separately when forced). |

## Per-frame behaviour

`AiUpdate` (`0x80059B78`, port `ai_update.py`) refreshes the record and then runs the steps below in order until one produces input. Pads are in the CPU's frame: `0x2000` forward, `0x8000` back, `0x1000` up, `0x4000` down.

1. **Bookkeeping**: situation bits, cached move words, distance and reach bands, the opponent's attack timing (`+0x20A`), guard need (`+0x6A`), crouch timer.
2. **Fixed input**: a pending script step; input mode `+0x21E` 0 (no input) or 1 (hold up while crouching). In the demonstration fight and in Tekken Force (`0x8009F6A4`, set by `AiInitRound` from the attract flag `0x800AE39C` or mode 8) odd AI slots only repeat their direction on odd frames of `g_frameCounter`, so they think every other frame; a Tekken Force enemy with a positive second countdown does the same.
3. **Throws**: as the victim, with a forced escape against a few throws (`0x17F`, `0x181`, `0x189`, `0x18E`, `0x172` of banks 0 and 9, `0x152` of bank 3) or with probability word 9, press a random one of the first 48 rows of the throw's branch list (escape conditions `0x3A`/`0x3C` press 1, `0x3B` presses 2, others their command). As the thrower, with probability word 10 and up to word 7 steps, pick one of up to six open follow-up rows and press it on its first frame; a few slots are tied to banks (`0x3A7` never; `0xD41` for bank 4, `0xDE2` for bank 0 with a 7-in-8 draw; `0xD24`/`0xD32` for banks 0 and 13 with a 1-in-8 draw; `0xD25`/`0xD34` never for banks 0 and 13).
4. **Stance** (own state `0x4C02`, not attacking): with probability word 49 execute a candidate whose branch row byte `+8` is `0x1C` or `0x1D`; otherwise no input.
5. A queued move row (fighter `+0x1A4`) ends the frame.
6. **Neutral actions** (grounded, own state bits 2 or 10): if the running move has a row with condition `0x31`, press button `0x10` and then wait a random byte of words 0–1 in frames. Otherwise, with candidates open, pick an action from a mask and the table `0x800230E0` (`1 2 4 8 0x10 0x20`): 1 up (`0x1000`), 2 button `0x80` (with down every 8th frame), 4 back (forward for bank 18), 8 `FUN_8005758C`, `0x10` hint-bit-0 or low attacks, `0x20` side steps and state-bit-19 moves. The mask depends on the opponent: not attacking — `7`, or `0x3F` at reach band below 4 (far), else on odd frames `7` (`0x38` 1 in 64 when the wait is over); attack coming within 12 frames — against lows or Gon's specials `2`, `4` or `0x38` by draws on odd frames, otherwise `0x3F` (`1` out of reach); otherwise `0x28`/`0x38` at band 0–1. Gon's special hold (`+0x201`) with own state bit 9 holds back.
7. **Hooks** ([below](#character-hooks)): the hook for the opponent's bank, then the CPU's own.
8. **Hold the guard**: after the opponent whiffs, a draw against word 16 sets the punish flag `+0x8F`; otherwise, while `+0x6A` says the current guard stops the coming attack, keep the direction.
9. **New move** (`+0x28`): build a [follow-up list](#follow-up-lists) and hold the direction. Otherwise collect candidates of the running move (including the default continuation); after 220 frames in one move execute any of them.
10. **Follow-through**: during a move usable in the air or as a special (`+0x52`), execute any candidate when the opponent's attack comes later, the band is above 2 or the CPU faces away.
11. **Attack coming** (`+0x20C`, `+0x216 ≥ 0`, reach band below 4): counter with `FUN_80058040` (word 19 or the punish flag); duck or step back (word 21, crouch-back `0xC000`, back `0x8000` against `0x217`); side-step when the attack arrives in 9–11 frames (word 18).
12. **Reaction** to the opponent's attack when it has not attacked yet in this string (`+0x216 < 0`): see [Reactions](#reactions).
13. **Follow-up lists** expire.
14. **Position** (outside its own attack): against an air attack at close range (word 36) walk forward or forward-down (`0x2000`, `0x6000`); when turned away, with a draw weighted by the angle (`+0x2E`), walk or step back to face the opponent (bank 7 walks); when behind it at close range press down with a button against a downed opponent (`0x4020`/`0x4040`), else walk forward.
15. **Attack choice** ([below](#attack-choice)).
16. **Movement** ([below](#movement)).

At the end, timers count down (`+0x38..+0x54`, `+0x8A`, `+0x8C`, `+0x1FE`, the Tekken Force countdowns); the parameters are reloaded when `+0x1FE` reaches 0; hits taken adjust the words above; and the routine returns the held pad and the newly pressed bits.

### Reactions

When the opponent's attack has not yet been answered, a reaction kind is chosen (jump table `0x8002317C`):

| Kind | When | Action |
|---:|---|---|
| 0 | Otherwise. | Continue with the next steps. |
| 1 | A forced-escape throw (word 29); `+0x6C > 8` (1/32); the adaptive mode (1/16); the opponent's move equals slot 0 of the damage history (word 17; [game-bugs.md](game-bugs.md) #23); a draw against word 16; 31+ announced frames and word 17. | Counter-attack: `FUN_80057820` when nothing is coming, `FUN_8005817C` against `0x607`/`0x706` or a standing opponent, else `FUN_80058040`; against `0x412` also standing attacks in reach. |
| 2 | The guard delay `+0x6C` has just run out while the CPU is not attacking; word 14 (or 15) while the attack is coming; the flag `+0x92`; word 47 against a grab. | `FUN_800582A0` guard/evade rows; if none, crouch-back `0xC000` (back against `0x217`). |
| 3 | The evasion state `+0x94` is 1 or 3–6 and `+0x8C` has run out. | [Evasion](#evasion). |
| 4 | Reach band 2, standing, against `0x412` arriving in 9–11 frames, word 18. | Side step and a shorter wait. |
| 5 | The attack arrives in 8–9 frames and the CPU's bank has a counter move (`0x80022F80`), word 45. | Execute branches to slots `0x1EE`/`0x6A3`. |
| 6 | Bank 9, the attack arrives in 22–26 frames, word 45. | Execute branches to slot `0x22C`. |
| 7, 8 | The attack arrives in 4–10 frames; mid/high (7) or low (8); word 45; the bank has a parry script. | Start the bank's parry script (`0x80022F84`/`0x80022F88`). |
| 9 | 1 in 64 of kind 1 against `0x412`. | Execute a neutral move and set `+0x8E`. |

`FUN_800582A0` (only within 2,950 units) marks guard rows by the attack word: against `0x31F` standing or crouching guards (not `0xC002` rows), against `0x217` and `0x412` the standing guard (`0x412` also neutral moves 1 in 50 times, or neutral moves when the CPU is already crouched), against `0x10F` the crouching guard, against `0x706` neutral moves; against grabs neutral moves; and crouch dashes (`0xC002`) from reach band 3 on or when approached fast. Its return value keeps only the last pass ([game-bugs.md](game-bugs.md) #21).

### Evasion

`+0x94` holds an evasion state, set when the opponent's attack passed its window (2), by a draw against word 29 against unblockables and state bit 21 (1), and advanced by kind 3:

- 1: pick 3 (after a failed draw against word 35 at band 0–2) or a random entry of `5 3 5 4 3 4 3` (`0x800230EC`);
- 3, retreat: attack with `FUN_800576DC` at close range when the attack is far off, else step back on even frames (`+0x68` random); step back when the attack is near (`0x8000` facing, else nothing); from band 3 switch to 4 and step back;
- 4, back off: walk forward when turned away at reach band 2+, attack at band 0–1 with `FUN_800576DC` when the attack is 9+ frames away, else back-dash (script `0x80022EB2`);
- 5, side step: walk forward (`0x2000`) unless a 1-in-8 draw and at least 7 frames allow a side step (then 3 if turned away);
- 6 (no code path sets it): keep out.

States other than 1 and 2 end at 2,951 units or more (3,251 against Yoshimitsu), with no input.

### Follow-up lists

When a move starts, `AiUpdate` prepares one of three lists: string continuations (`+0xC4`, up to 4 rows leading to moves with `+0x24` bit 13, after an attack flagged the same), planned follow-ups (`+0xDC`, up to 48 rows in reach, after an attack with state bit 19), or rows that open on frame 1 of the CPU's own attack (`+0x1A4`, up to 10). The CPU holds its direction on that frame. On the next frame the lists are filtered to their open rows into `0x800A0590` and dropped: the code that would press one reads a count register that is never incremented ([game-bugs.md](game-bugs.md) #10). So the CPU never deliberately continues a string or combo this way; it only continues through ordinary candidate picks.

### Attack choice

Before choosing, `AiUpdate` gives up for this frame with probability 11/12 at bands 3+, and 1/8 at band 2 and above. It also stops when the CPU has started `+0x1D4` attacks in a row or is on a cool-down. Then, in order:

1. With a pending wait (`+0x68 ≥ 1` and no punish flag or late-announcement draw), only a 4-in-4096 neutral move.
2. Opponent down (`+0x208`): a draw table over words — wake-up attacks (rows with condition `0x35`), a side step, hint-bit-0 lows, neutral moves, crouch dashes, the ground script `0x80022E96`, or low attacks.
3. Opponent in state `0x4C02` (word 30): side steps or hint-bit-0 ground moves, then `FUN_80057C88`/`FUN_80057AC4` after a word-35 draw.
4. After an air move (`+0x46 ≥ 0`): air or special attacks.
5. An announced unblockable (`+0x20E`): `FUN_80058AC0` after word 16, else `FUN_8005758C`/`FUN_800576DC`.
6. The opponent's attack is coming or it grabs: the same.
7. Otherwise, at close range: throws (word 8, rows with the "never chosen" hint, word 11 choosing between the two throw lists); bank setups (`0x80022F8C`: per bank a list of `s16 chance, s16 slot, script`; the first entry whose chance passes starts its script when a branch into the slot is open); neutral moves; side steps; then words 12, 13, 35 choose between `FUN_80057954`, `FUN_80057820`, `FUN_800576DC`, `FUN_80057E48`, air moves (1/8) and `FUN_8005758C`.

At 10 % health and at reach band 3+, a 1-in-4 draw against word 16 adds the desperation moves (`+0x24` bit 16). The executed attack decides the follow-up list of the next move and a 12-frame direction hold after crouching attacks.

### Movement

When no attack was executed and no input script is pending (`+0x8A < 0`):

- while an approach is running (`+0x38 ≥ 0`) and a draw passes word 35, an attack that is coming and in reach (`0x80098628` by reach band) restarts the approach and draws a movement; otherwise a long approach (`+0x3A = 2`) keeps walking forward (back 32 in 4096 times close up), and a short one side-steps 1 in 16 times at reach band 2 or keeps the direction;
- with the approach timers idle, a random movement is drawn by distance band, or by reach band when the wait is long (`+0x68 ≥ 0x24`; choices 3 and 6 then pass word 38). Choices 3 and 6 are dropped by a word-35 draw while the opponent attacks. The choices are 1 side step or walk in, 2 walk in (timers by band), 3 step back (`0x8000`, `0xC000` while standing), 4 side step with a long approach or dash in, 5 dash in (`0x2000`, `0x6000` while standing), 6 crouch dash or step back, 8 side step (reach band 3+ or 11+ frames) followed by a candidate.

With no movement, the CPU holds down while its crouch timer runs (`+0x4A`), keeps its direction while `+0x48` runs, or releases the pad.

## Character hooks

`AiReset` installs two hooks per CPU record with `AiHookForBank` (`0x80062B50`) from the table `0x800233A0` (10 entries of `u16 bank, pad, hook A, hook B`):

- `+0x74` is hook A of the **opponent's** bank type (counter-play against a character);
- `+0x78` is hook B of the CPU's **own** bank type (its special tactics).

`AiCallHook` (`0x800594C4`) calls `+0x74` and then `+0x78` when no input script is pending (`+0x8A < 0`). Each call first passes a separate draw against word 29 (`+0x272`). The result means:

| Result | Effect |
|---:|---|
| −1 | No action; `AiUpdate` continues with the next step. |
| −2 | The hook started an input script (or deliberately waits); the frame is consumed. |
| −3 | Execute a marked candidate (if any). |
| other | Pad word to hold. Forward (`0x2000`) and back (`0x8000`) also set the timers `+0x38 = 16`, `+0x3A = 0`, `+0x40 = 0x38`. |

Record fields used by the hooks, all refreshed by `AiUpdate` every frame:

| Field | Meaning |
|---:|---|
| `+0x68` | Wait counter; the hooks set it to −1 and skip while it is positive. |
| `+0x88` | The opponent is Yoshimitsu in slot `0x456`. |
| `+0xD8` | Set to 1 after the King throw attempt. |
| `+0x208` | The opponent is down: its state has bit 2 or bit 9, it is not class 9, and it is not airborne. |
| `+0x20A` | Frames until the opponent's current move can be interrupted (999 when it is not attacking). |
| `+0x230` | The opponent's current `state` word (posture bits 0–2). |

The hooks by bank type:

| Bank | Hook A (against this character) | Hook B (playing this character) |
|---:|---|---|
| 0 Paul | `0x80062BAC` | — |
| 3 King | — | `0x80062804` |
| 4 Yoshimitsu | `0x80061E70` | `0x80062C7C` (returns −1) |
| 6 Hwoarang | — | `0x80062C84` |
| 10 Julia, 13 Heihachi, 16 Gun Jack | `0x80062C10`, `0x80062C18`, `0x80062C20` (return −1) | — |
| 14 Ogre / True Ogre | `0x800621D8` | — |
| 19 Gon | `0x80062C28` | — |

Slots below are identified from the branch rows that lead to them (Tekken notation; `tools/research` bank data). Two helpers recur:

- **Filter**: `FUN_8005967C` installs `FUN_800616B4` as this frame's candidate filter (`+0x7C`). It removes low attacks (`0x10F`) and attacks with AI hint bit 0 from the marked candidates.
- **Side step**: `AiSideStep` (`0x80061D40`) starts a side-step script (`2 2 2 2`, or `8 8 8 8` for the other side, tables `0x800232DA`). It is given a side, or chooses one from the heading difference (random when nearly straight) and the fighters' screen order. The Ogre hook refuses it when the CPU's own state has bit 22 or the fighters are 7,001 units or more apart.

`+0x8C` suspends the guard step while it counts down.

- **Against Paul**: slot `0x2C6` is `1` from the crouch dash (slot `0x61`), continuing into `0x2C7` at frame 10. In `0x2C7`, with the closing-speed band below 3, the CPU waits (`+0x68 = −1`) until the opponent's pose frame reaches 16, then holds back.
- **Against Gon**: slot `0x137` is `1+2`. The CPU waits at speed band 0–1 (returns −2) and holds back at bands 2–3.
- **Against Yoshimitsu** (`0x80061E70`):
  - `0x16F` (`d+3+4`): wait while the speed band is below 3.
  - `0x456` (a stance with exits `0x458` on 1/2/3, `0x459–0x45B` on 7/8/9 and `0x49C` on a double tap): at speed band 0–2 suspend guarding for 4 frames, apply the filter and wait; otherwise walk forward.
  - Its jump exits `0x459–0x45B`:
    - point blank (distance band 0): before and after the active window, guard off for 4 frames, apply the filter and wait (−2); stand neutral during it;
    - Yoshimitsu turned 45°–135° away from the CPU: guard off for 20 frames, then the filter and a wait at band 1, walking forward from band 2;
    - otherwise, at bands 1–2: side-step with probability 1/8 unless the CPU crouches or its own state (`+0x224`) has bit 22; else stand neutral;
    - from band 3: walk forward with guard off for 10 frames.
  - `0x16A` (`d/b+1`) and its follow-up `0x43A`:
    - after the active window: neutral and wait;
    - while Yoshimitsu faces more than 22.5° away from the CPU: walk forward at speed band 0–1;
    - otherwise:
      - back-dash (`4 4`, script `0x80022EB2`) when approaching fast (speed band ≥ 3) within 2,700 units;
      - stay neutral when the opponent needs fewer than 11 frames, or when far;
      - side-step to a random side at speed band 2.
  - `0x458` and `0x49C–0x49E`:
    - while Yoshimitsu faces more than 90° away: wait at distance band 0–1;
    - otherwise: stand still at bands 0–1; at band 2 apply the filter and wait; from band 3 walk forward.
  - `0x472` (`b,b+1`): nothing.
- **Against Ogre / True Ogre** (`0x800621D8`): slot `0x16E` (`d+1+2`, the fire breath) suspends guarding for 8 frames.
  - Until 8 frames before its first active frame: at distance band 0 wait and walk in. At bands 1–2 walk forward. Further away, side-step with probability 1/8 if the CPU faces Ogre, its own heading is within 45° of Ogre's direction and the side step is allowed; the side follows the screen order. Otherwise walk forward with probability 1/8, else stand neutral.
  - Until its last active frame: if the CPU is not facing Ogre it presses one of `3+2`, `3+1`, `3+4`, `3+4` (table `0x80023308`) at distance band 0–1, and holds `3` at band 2. If it faces Ogre it holds `3` when closer than 7,001 units.
  - Slot `0xDE4` is also tested, but no bank defines or branches to it (dead code).
- **Playing Hwoarang**: the hook only reacts to Hwoarang's slot `0xDE3`, which no bank defines, so it never acts. It would hold forward with probability 15/16; during pose frames 13–17 only while the opponent needs at least 10 more frames.
- **Playing King**: the hook runs only while `+0x68 ≤ 0`, after a draw against word 11. Every case needs:
  - the opponent's move is not about to hit (`aboutToHit`);
  - King is not in an attack move;
  - the opponent needs at least 9 more frames;
  - King faces the opponent.

  In the first matching case King starts a scripted command (numpad directions, Tekken buttons):

  1. **Command throws.** The opponent stands (`state & 2`) and is not Gon. The distance band is below 3, the opponent is on the ground and faces King, a branch into slot `0x15` is open now (`FUN_80058ED0`), and a 1/8 draw passes. King inputs one of `5 6 3 3+1+3`, `5 6 3 3+2+4`, `5 6 3 3+1+2` (tables `0x8002334A`; one third each).
  2. **Against a crouching opponent.** The opponent crouches, the distance band is below 2, it faces King, and a branch to a move with the AI hint "never chosen" (bit 6, reserved for hooks) is open (`FUN_80057300`). King inputs `2 2+2+4 2 2` (`0x8002332E`).
  3. **Ground throws.** The opponent is down, the distance band is below 2, and it faces King or has its back turned. It must not be the Yoshimitsu slot `0x456`, and a reserved branch must be open. King inputs `1 1+1+3 1 1` or `1 1+2+4 1 1` (`0x80023312`, one half each).

## Mode-specific behaviour

**Tekken Ball (mode 7).** Each frame `volley.ovl` `FUN_800B4958` projects the scene onto the line between the players into `0x800B6AF0` (the line's z intercept divides by the fighters' x difference, [game-bugs.md](game-bugs.md) #24): `+0` player 1's position along the line, `+4` player 2's, `+8` the ball's, `+0x10` the ball's lateral offset.

- **Distance** (`FUN_800B4B08`): the distance used for the bands becomes the fighter's distance to the ball (`√(Δ² + lateral²)`) whenever that is smaller than the distance to the opponent. `0x8009F6A0 = 1` marks this.
- **Back-dash** (`FUN_800B4B64`): when the ball is behind the CPU on the line (player 1: ball < own position; player 2: ball > own position), the CPU back-dashes (`4 4`) to get under it and ends the frame.
- **Attack filter** (`FUN_800B4BE4`): in the attack choice, before the downed-opponent test, filter `FUN_8005758C` replaces the usual choice when the ball is ahead: for player 1 more than 2,000 units ahead, for player 2 ahead but closer than 2,000 units. The two tests are not mirror images ([game-bugs.md](game-bugs.md) #3).

**Tekken Force (mode 8).** Two per-enemy countdowns (`0x8009F6A8[slot]`, `0x8009F6B0[slot]`, decremented each frame):

- while the second is positive, the enemy keeps its previous direction input;
- when the first has run out and the player is targeting a different enemy (`FUN_800B2E60` returns the player; its `+0x1F` is the current opponent), the enemy draws against the pattern's probability (`0x8009F9EC` record `+4`). On success it skips the attack and counter-attack decisions for this frame and only moves, so enemies the player is not fighting often move instead of attacking.

## Unused debug names

The executable keeps a table of 46 string pointers at `0x80097D80` with names such as `shu_attack`, `shu_sidestep`, `shu_guardfree`, `shu_keephome`, `shu_line8`, `shu_jmpatk`, `shu_target` and `shu_recall`, plus reaction names (`shu_frontdmg`, `shu_backdmg`, `shu_thrown`, …; strings from `0x8001DC58`). No code or overlay references the table, so it is a leftover of a debug display. Its names match behaviour kinds of an enemy or AI state machine, but the index mapping is not recoverable from code.

## Open items

None. Every executable line of `ai_update.py` has been compared with the game ([tooling.md](../tooling.md#verification-log)).
