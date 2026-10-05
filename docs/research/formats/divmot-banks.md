# Motion banks: `divmot*.bin`

The original Japanese EXE names 73 non-empty BNS resources `divmot00.bin`–`divmot20.bin` and `divmot99.bin`. Fifty-two occupy the fourth slot of the character groups (IDs `74 + 4n`); IDs 279–300 hold one copy of each type (ID 279 = `divmot99`). All are byte-identical across original Japan, Japan Rev.1 and USA; there are 22 distinct banks.

A bank is the complete move set of one fighting style: move rows, animation streams, branch (cancel/command) lists and per-move event lists. `divmot99` is a **common bank** shared by every fighter; move-index slots and animation words at or above `0x40000000` refer to it.

Evidence (Japan Rev.1):

| Routine | Role |
|---|---|
| `DivmotRelocate` `0x8006A18C`, `DivmotRelocateCommon` `0x80069B84` | Convert header words to pointers after loading. |
| `DivmotLinkBank` `0x8002D068` | Links move rows (animation, branches, events) and the 4,023-slot index. |
| `DivmotMergeSharedSlots` `0x8002D2D0` | Resolves slots shared between the two fighters' banks. |
| `MoveLookup` `0x8002D3CC` | `moveIndex[slot]` for a fighter. |
| `MoveTotalDamage` `0x8002D51C` | Base damage plus `0x0Bxx` additions from the event list. |
| `BranchFind` `0x8002E078`, `BranchCondition` `0x8002E310`, `InputMatch` `0x8002CE7C` | Evaluate a move's branch list. |
| `AnimDecodeRoot` `0x80038C14`, `AnimDecodePose` `0x80038DA0` | Decode animation streams ([animation.md](animation.md)). |

## Loading

A fighter's bank is loaded by `FighterLoadCharacter` as logical ID `98 + 4·slot` into the shared motion buffer `g_divmotBuffer` (`0x800AE348`). The second fighter's bank goes to `+0x62958` (or `+0x5233C` when that fighter uses bank 3) unless both fighters share a bank. `divmot99` is loaded (logical ID 73) at `+0xB4C94`. `g_fighterDivmot[2]` (`0x800AE0E8`) holds each fighter's bank pointer and `g_divmotCommon` (`0x800AE0F0`) the common bank.

## Header

| Offset | Type | Meaning |
|---:|---|---|
| `0x00` | `u8` | Zero. |
| `0x01` | `u8` | Bank type (matches the filename number: 0–20, 99). Fighter field `+0x16` holds this value. |
| `0x02` | `u16` | Number of move rows (section 1). |
| `0x04` | `u32 b[15]` | Section boundaries; section `i` is `[b[i], b[i+1])`. `b[0] = 0x40`, `b[14] = file size`. Words `b[0]..b[12]` are relocated to pointers at load. |

| Section | Pointer after relocation | Content |
|---:|---|---|
| 0 | `branches` | 12-byte branch rows. |
| 1 | `moves` | 56-byte move rows. |
| 2 | `moveIndex` | 4,023 `u32` slot entries (16,092 bytes in types 0–20). |
| 3 | `sounds` | Move sound command lists (`u16`, ending at `0xFFFF`), referenced by move `+0x1C` ([sound.md](../code/sound.md#fighter-sound-logic)). |
| 4 | `events` | Frame event lists (`u16 frame, u16 command`), referenced by move `+0x20` ([moves.md](../code/moves.md#frame-events)). |
| 5 | `emptyMask` | 252 `u16` = 4,032 bits: bit `s` set when slot `s` is **not** defined by this bank (its index entry is `0x3FFFFFFF`); 504 bytes in types 0–20. |
| 6 | `animData` | Animation streams, each preceded by an `s16` animation tag. |
| 7 | `cameraChoices` | Bank-specific weighted camera choice lists (ids `≥ 0x2B`; lower ids use the EXE table `0x80098750`), 8-byte entries ([camera.md](../code/camera.md)). |
| 8 | `cameraScripts` | Camera streams referenced by negative choice entries (`offset & 0xFFFF`): a yaw mode `u16` and a 7-channel stream (eye, target, fight-camera weight), [camera.md](../code/camera.md#camera-streams-bank-section-8). |
| 9 | `attackDescriptors` | Attack records referenced by move `+0x28`: joint pairs and baked per-frame attack points ([below](#attack-records-section-9)). |
| 10 | — | Empty in all banks. |
| 11, 12 | `altModel` | Only in types 14 and 19: KMD images whose vertex-variant blocks replace those of row 2 for character 20 (`KmdRelocate`); section 11 serves costumes 0/2, section 12 costumes 1/3 (`FUN_80069A44`, fighter `+0x14` bit 0). |

Type 99 has empty sections 2 and 5 (it has no slot index of its own).

## Move-index slots (section 2)

`moveIndex[s]` for `s < 4023` is a move-row number. Values `≥ 0x40000000` select row `value − 0x40000000` of `divmot99`; `0x3FFFFFFF` marks an empty slot. After linking every entry is a pointer to a 56-byte row. Slots are the game's global move numbering: for example slot 0–2 are stance moves chosen at round start (`FUN_8002D570`), and `0xD67–0xD6A` are the four victory poses selected by LP/RP/LK/RK (`FUN_8002D6B0`; masks `0x80/0x10/0x40/0x20`).

When two fighters are loaded, `DivmotMergeSharedSlots` walks both `emptyMask`s (bit `s` of word `s / 16`, least significant bit first): a slot empty in a bank is filled with the other fighter's entry, or with the bank's own entry at slot `0xDC5` when it is empty in both. This is how a throw's victim moves, which only the thrower's bank defines, reach the victim. The merge rewrites the linked index in place, so it is repeated whenever the pair changes.

## Move row (section 1, 56 bytes)

Words marked *relocated* are converted from indices to pointers by `DivmotLinkBank`. The run-time meaning of each field is described in [moves.md](../code/moves.md#move-row-fields-used-at-run-time) and [combat.md](../code/combat.md).

| Offset | Type | Field |
|---:|---|---|
| `+0x00` | `u32` | Animation: offset in section 6 (points at the stream, after its 2-byte tag), or `0x40000000 + offset` in `divmot99`. *Relocated.* |
| `+0x04` | `u32` | State word (posture, guard, throw targeting, airborne, state class). |
| `+0x08` | `u16` | Attack word (postures hit, guards that block, level id in the high byte). |
| `+0x0A` | `u8` | AI hint bits: attack preference, reach classes, AI exclusion ([ai.md](../code/ai.md#move-row-hint-bits)). |
| `+0x0B` | `u8` | Zero. |
| `+0x0C` | `u32` | First branch row. *Relocated* to `branches + 12·index`. |
| `+0x10` | `u16` | Stance slot (3 standing, 40 crouching, …). |
| `+0x12` | `s16` | Heading change applied when the move ends. |
| `+0x14` | `u16` | Damage (bits 0–13) and attack class (bits 14–15). At load the arguments of all `0x0Bxx` events are added. |
| `+0x16` | `s16` | Step displacement per frame. |
| `+0x18` | `u8` | Frame count `N`; overwritten at load with the stream's first byte. |
| `+0x19`, `+0x1A` | `u8` | Air window (first, last frame). |
| `+0x1B` | `u8` | Hold frame. |
| `+0x1C` | `u32` | Sound list index, −1 for none. *Relocated* to `sounds + 2·index` (0 for none). |
| `+0x20` | `u32` | Event list index, −1 for none. *Relocated* to `events + 4·index` (0 for none). |
| `+0x24` | `u32` | Flags; bits 0–7 index the camera choice lists. |
| `+0x28` | `u32` | Attack descriptor: one of 13 built-in ids (`0x80017C10`: 0, `0x7FF0–0x7FFB`) or `value − 4` bytes into section 9. *Relocated.* |
| `+0x2C` | `u8` | Hit freeze given to the defender. |
| `+0x2D`, `+0x2E` | `u8` | Active window (first, last frame); `+0x2D = 0` for non-attacks. |
| `+0x2F` | `u8` | Zero. |
| `+0x30` | `u16` | Body-sphere profile ([combat.md](../code/combat.md#collision-shapes)). |
| `+0x32` | `u16` | Reaction record (`< 0x1000`) or throw-victim entry (`0x1xxx`). |
| `+0x34` | `u16` | Close-range reaction entry (0 = none). |
| `+0x36` | `u16` | Zero. |

### Attack records (section 9)

An attack record starts with four bytes `(a0, b0, a1, b1)`: joint pairs of up to two attack segments (matrix blocks of the fighter; `a ≥ 0x18` selects a weapon or projectile source). These are used outside the active window. Then follows a big-endian `u16`: bits 0–3 are the layout kind, and bits 4–14 the byte offset of an alternative point block (0 when absent). Then come the baked points of the active window, with the alternative block after them. The game uses the alternative block for characters 14 and 15 (Ogre and Mokujin).

A point is 5 bytes, a little-endian 40-bit value: `x = bits 0–12 − 0x1000`, `y = bits 13–25 − 0x1000`, `z = bits 26–39 − 0x2000`. Points are relative to the move anchor, in the fighter's heading frame. Frame `t` (pose frame − first active frame) starts at `6 + stride·t + lead` within the block:

| Kind | Stride / lead (bytes) | Segment 0 | Segment 1 | Records |
|---:|---|---|---|---:|
| 0 | 10 / 0 | two points | — | 98 |
| 1 | 5 / 5 | swept → point | — | 1,649 |
| 2 | 10 / 10 | swept → point | swept → point | 103 |
| 3 | 15 / 5 | two points | swept → point | 9 |
| 4 | 15 / 5 | swept → point | two points | 35 |
| 5 | 20 / 0 | two points | two points | 11 |
| 6 | 10 / 5 | swept → point | point → segment 0 end | 882 |
| 7 | 10 / 5 | swept → point | segment 0 end → point | 251 |
| 9 | 10 / 5 | two points | swept → segment 0 start | 1 |
| 10 | 15 / 0 | two points | point → segment 0 end | 5 |
| 12 | 15 / 0 | two points | point → segment 0 start | 0 |
| 13 | 15 / 0 | two points | segment 0 start → point | 1 |
| 14 | 15 / 0 | two points | the point itself (zero length) | 5 |
| 8, 11, 15 | — | not updated | not updated | 0 |

"Swept" is the previous frame's end point; on the first active frame it is the baked point just before the frame (5, 10 or 15 bytes earlier), placed at the previous frame's anchor. The lead bytes hold those first-frame points. In all 22 banks (3,050 records, 2,089 with an alternative block) the record lengths match this layout, except 13 records followed by 1–3 alignment bytes and one by an unreferenced block.

### Event list (section 4)

A move's event list is a sequence of `(u16 frame, u16 command)` pairs terminated by `frame = 0`; the command's high byte selects the action ([moves.md](../code/moves.md#frame-events)). Command `0x0Bxx` (throw damage) also adds `xx` to the move's damage at load time (535 occurrences).

## Branch rows (section 0, 12 bytes)

A move's branches are consecutive rows starting at `move.branches`, terminated by a row whose first `s16` is `0xC000`. `BranchFind(row, frame, self, opponent)` returns the first row that matches; an unmatched list returns the terminator.

| Offset | Type | Meaning |
|---:|---|---|
| `+0x00` | `u16 command` | Input condition (below). `0xC000` ends the list; `0xC00C` jumps to common row `+6` in the EXE table `0x80017C78`; `0xC00D` is a no-input row. |
| `+0x02` | `u8 restriction` | 0 = none; `1..0x17`: own bank type = value−1; `0x18..0x2E`: own bank ≠ value−0x18; `0x2F..0x45`: opponent bank = value−0x2F; `0x46..0x5C`: own character ID (`+0x18`) = value−0x46; `≥0x5D`: own character ≠ value−0x5D. |
| `+0x03` | `u8 condition` | `BranchCondition` type, 0 = always, must be `< 0x45`. |
| `+0x04` | `u16` | Condition parameter (for example a frame or timer threshold). |
| `+0x06` | `u16` | Target (move slot); for `0xC00C`, the common-row index. |
| `+0x08` | `u8 flags` | Bits 0–5: transition code (`FUN_800311BC`, stored in fighter `+0x19A`); bit 6 → `+0x19E`; bit 7 → `+0x19C`. As a whole byte, `0x2C` makes `BranchFind` skip to the list end, and `0x1C`/`0x21` have mode-dependent handling. |
| `+0x09` | `u8` | First frame of the current move at which the row is accepted. |
| `+0x0A` | `u8` | Last accepted frame. |
| `+0x0B` | `u8` | Frame at which the target move is entered; `0xFF` uses the move's frame-count byte. |

`MoveBranchStep` (`0x8002DC3C`) evaluates the current move's list every frame. A match starts the target move immediately; a press arriving up to five frames before the window opens is buffered (the input history is consulted). When nothing matches and the move has ended, the terminator row's target (`+0x06`) is taken as the follow-up move — every list ends with a default continuation. `FUN_8002DB08` runs the alternative walker `FUN_8002E95C` for the second evaluation path (conditions `≥ 0x45`).

Command words, input matching, motion sequences and the branch condition types are described in [moves.md](../code/moves.md#command-words).

## Verification

- All 22 banks parse with the section directory covering the file exactly.
- The animation stream decoder was compared with the game's `AnimDecodePose` on every own animation of every bank (see [animation.md](animation.md)).
