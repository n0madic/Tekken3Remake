# Executable layout, main loop and resource loading

Addresses are Japan Rev.1 (`SLPS_013.00`, SHA-256 `09e8b0b6…`) guest addresses unless stated. Function names are the project's names (see [`tools/ghidra/symbols.txt`](../../../tools/ghidra/symbols.txt)); PsyQ library names come from signature matching.

## Memory map

| Range | Content | Evidence |
|---|---|---|
| `0x80010000–0x8007A093` | Game code and constant data of the resident EXE. `main` at `0x80028DF4`. | Ghidra analysis |
| `0x8007A094–0x80095200` | PsyQ runtime: libc subset, libgpu/libgs, libgte, libcd/libds, libspu/libsnd, libpad/libcard, libapi. 929 functions identified by the `psx_psyq_signatures` set. | Signature matches |
| `0x80095200–0x800AFFFF` | Initialized and zeroed game data: fighter structs (`0x800A96F0`, two × `0x188C` bytes), ordering tables, BNS load queue, tables. | Code references |
| `0x800B0A10–0x800B9377` | **Mode overlay slot.** Initially the EXE's boot module (`BootInit` `0x800B0A10`, state-0 handler); later `arcade`, `practice`, `force` or `volley.ovl`. | `jal` targets of each overlay land on function prologues only at this base |
| `0x800B9378–…` | **Screen overlay slot / fight heap.** `enbu`, `select`, `title`, `ranking`, `ending` and `result.ovl` load here; during fights the same area is a bump heap (`0x8009F688`) for replay, effect, stage and camera buffers (`FightAllocBuffers` `0x80055B6C`). The EXE image itself extends to `0x80131000` (boot data, the common VAB bodies). | as above; `FUN_80052E9C` passes `0x800B9378` |
| `0x801FFFF0` | Initial stack pointer (EXE header). | PS-X EXE header |
| `0x1F800000–0x1F8003FF` | Scratchpad: per-part vertex slots, pose vector, temporary matrices. | Renderer, pose code |

The PS-X EXE header gives entry `0x8007A094` (`start`), text address `0x80010000`, text size `0x121000`.

Overlays have no header; they are raw images linked at their slot address and generally begin with data. The loader state machine (`OverlayLoader`, game state 1, `0x80052FAC`) processes a queue of up to eight `(destination, logical id)` requests (`FUN_80052EC8`; `FUN_80052E70` queues a mode overlay at `0x800B0A10`, `FUN_80052E9C` a screen overlay at `0x800B9378`) and then switches to the requested game state. After loading an overlay (logical IDs below 10) the game calls `FlushCache`. Earlier notes placed every overlay at `0x800B0000`; that was wrong and misaligned the first Ghidra overlay programs. The USA executable (`SLUS_004.02`) loads the same overlays 0x4C8 and 0x620 bytes lower: mode overlays at `0x800B0548`, screen overlays at `0x800B8D58` (found from the string addresses in their code; `make_overlay_exes.overlay_base(name, release)`).

| Logical ID | BNS ID | Overlay | Mode (inferred from name) |
|---:|---:|---|---|
| 0 | 5 | `arcade.ovl` | Arcade |
| 1 | 6 | `practice.ovl` | Practice |
| 2 | 7 | `force.ovl` | Tekken Force |
| 3 | 8 | `volley.ovl` | Tekken Ball |
| 4 | 9 | `select.ovl` | Character select |
| 5 | 10 | `title.ovl` | Title/menus |
| 6 | 11 | `ranking.ovl` | Ranking |
| 7 | 0 | `enbu.ovl` | Demonstration |
| 8 | 301 | `ending.ovl` | Endings |
| 9 | 302 | `result.ovl` | Results |

## Main loop

`main` initializes through `BootInit` and then loops forever:

1. per-frame input/system updates (`FUN_80029918`, `FUN_8006B9E4`), frame counter `0x800AFF14`;
2. selects the active display buffer and ordering table;
3. dispatches on **`g_gameState` (`0x800AE6CC`)** to one of 20 state handlers; sub-state `0x800AE6EC`;
4. links the two global primitive lists into the ordering table.

| State | Handler | State | Handler |
|---:|---|---:|---|
| 0 | `0x800B0BD0` (boot module) | 10 | `0x80055878` |
| 1 | `0x80052FAC` (overlay loader state machine) | 11 | `0x80052808` |
| 2 | `0x8004FD48` | 12–15 | `0x800EF4AC`, `0x800EFF4C`, `0x800F0A78`, `0x800F1F08` (overlay) |
| 3–6 | `0x800DB7D4`, `0x800DBBD0`, `0x800DE480`, `0x800D3844` (overlay) | 16 | `0x800504A8` |
| 7, 8 | `0x80050600`, `0x80050710` | 17 | `0x800C2A24` (overlay) |
| 9 | `0x8011056C` (overlay) | 18 | `0x8005025C` |
| | | 19 | `0x8010E8C0` (overlay) |

Handlers at `≥ 0x800B0A10` exist only while the overlay that defines them is loaded; see [modes.md](modes.md) for the mapping of states and modes to overlays.

## BNS resource loading

`TEKKEN3.BNS` records are addressed through a **logical ID**:

- `g_bnsLogicalToId` (`u16[303]` at `0x80098954`) maps logical → BNS ID. Logical 0–9 are the overlays above; for logical `L ≥ 10` the BNS ID is `L + 2`.
- `BnsQueueLoad(logical, dest, 0)` (`0x8006C208`) looks up the Rev.1 `(LBA, size)` table at `0x8002466C`, and inserts a request sorted by BNS ID into a queue of at most 8 entries (`0x800A0A60`, 28 bytes each). `BnsStartQueuedLoads` (`0x8006C36C`) merges disc-contiguous requests and starts `DsRead` (callback `0x8006C554`); `BnsIsLoading` (`0x8006C524`) polls completion.

## Character resources

A **costume slot** `s` (`0..51`, fighter field `+0x1C`) owns four consecutive logical IDs `95 + 4s .. 98 + 4s` = BNS `71 + 4s .. 74 + 4s`:

| Logical | Resource | Destination | Use after loading |
|---|---|---|---|
| `95 + 4s` | `.kmd` model | `0x800AE390[player]` | `KmdRelocate`, parts, primitives |
| `96 + 4s` | `.vh` VAB header | `0x800AE4C4[3·player]` | Sound bank setup (`FUN_80075570`) |
| `97 + 4s` | `.arc` (5 members) | `g_arcBuffer` (`0x8009F68C`) | see below |
| `98 + 4s` | `divmot` bank | motion buffer | only when not already resident |

`FighterLoadCharacter` (`0x80036564`) then processes the ARC members:

| Member | Handling |
|---|---|
| 0 | `FighterUploadTextures`: TIMs to VRAM at `+(384, 256·player)`, CLUTs at `+(0, 504 + 4·player)`. Slots 47–50 hold a nested 4-way archive, uploaded with per-child offsets. |
| 1 | The character's hit-effect flipbook, placed per player by `FUN_80076484` ([system-textures.md](../formats/system-textures.md#character-effect-flipbooks)). |
| 2 | VAB body, joined with the `.vh` in `FUN_80075570`. |
| 3 | `TK3psSDW` block copied to the fighter's buffer (`FUN_80036140`) and relocated (`PssdwRelocate`, 18 section pointers). |
| 4 | Move-name text, 0x232 bytes copied to `0x800A39D0 + 0x232·player` (player 0/1 only, not character 0x15). |

Per-costume tables indexed by `s`:

| Table | Entry | Content |
|---|---|---|
| `0x80095EC0` | 3 × `u32` | Exact sizes of the costume's `.kmd`, `.vh` and `.arc` (kept with the destinations at `0x8009C0E0`). |
| `0x80095D74`, `0x80095DA8` | `u8` | Face shapes for `HandFaceCommand` kind 3 ([moves.md](moves.md)): the default face (event `0x15`, `FUN_80034A08` at round start) and a second face (`FUN_80034998`). |
| `0x80095DF0` | 4 × `s8` | Blinking ([animation.md](../formats/animation.md#blinking)): rectangle of the eyes in the face texture, size, open-eye source, closed-eye source (−1: the costume does not blink). |
| `0x80095CE0` | 6 × `s8` | Gon's eyes: size, then left/right eye rectangles and their sources ([animation.md](../formats/animation.md#procedural-head-and-eyes)). |
| `0x80095D40` | 4 × `s8` | Gon's mouth/face texture: size, destination, two sources (`FUN_800342A0`, `FUN_80034354`). |

Rectangles are indices into the coordinate table `0x80095BC0` (`s16 x, y` in VRAM words) and the size table `0x80095C90` (`s16 w, h`); player 2 adds 256 to y (4 for Gon's mouth, which sits in the CLUT area). The copies use `MoveImage` within VRAM.

## Fighter structure (summary)

The complete field list is [fighter.md](fighter.md).

`g_fighters` at `0x800A96F0`, two entries of `0x188C` bytes. Fields confirmed so far:

| Offset | Meaning |
|---:|---|
| `+0x00, +0x04, +0x08` | World position (`s32`). |
| `+0x0E` | Facing angle (16-bit). |
| `+0x12` | Player index (0/1) used for VRAM and CLUT offsets. |
| `+0x16` | Motion bank type. |
| `+0x18` | Character ID (special cases 0x0B, 0x11, 0x14, 0x15 in code). |
| `+0x1C` | Costume slot `s`. |
| `+0x1E` | Controller/player number. |
| `+0x24..+0x28` | Root displacement from the current animation. |
| `+0x4C`, `+0x50` | Move and frame used for root motion. |
| `+0x54`, `+0x58` | Move and frame used for the pose. |
| `+0x198` | Frame counter of the current move. |
| `+0x1A0` | Current move slot. |
| `+0x1A4` | Current move row pointer. |
| `+0x402, +0x404, +0x406` | Input state used by branch matching. |
| `+0x4EC, +0x4EE` | Model scale (4096 = 100%). |
| `+0x4F0` | 22 × `FighterPart` (0x28 bytes). |
| `+0x8B0` | Root joint matrix block. |
| `+0x8F4` | Joint matrix blocks, 0x44 bytes each: local-to-world matrix pair plus parent pointer at `+0x40`. |
| `+0xF74` | 18 local joint matrices (0x20 bytes); rotation from animation, translation from the model. |
| `+0x1274` | `TK3psSDW` buffer pointer. |
