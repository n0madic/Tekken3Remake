"""Flipbook effects (effects.md#flipbook-ring) → frame strips for the remake's effect sprites.

A flipbook is a sequence of 32 × 32 4-bit frames through one CLUT, advancing one frame per
game frame. The frames are found as the game finds them:

- the system set 3 (hit, hit without damage, guard, landing dust) in the effect page of the
  system textures, from the VRAM position of its record (`0x80027C48`, block 2), walking the
  page as `FUN_80077158` advances a flipbook;
- the character sets of the fight: member 1 of the costume's ARC, uploaded by
  `FighterUploadFlipbook(player, charId)` (`effects/costume_<slot>.png`);
- the two character sets of the attract demonstration: `enbu.ovl` uploads its own copies
  (ARC `0x800CB710`, one TIM sequence per player) with `FighterUploadFlipbook(player, charId)`,
  so each TIM is one frame in playback order, all through the first TIM's CLUT; the frame
  count and light colour come from the character record (`0x80027BAC + 6 · charId`).

Output: `effects/<name>.png` (the frames left to right) and `effects/effects.json` (frame
count, blending, light colour per flipbook; the landing dust ring's layout).
"""

from __future__ import annotations

import numpy as np

from common import Disc, Output
from move_text import arc_members
from vram import Vram, clut_xy, png_bytes, rgba, tim_sequence, unpack_indices
import sources

ENBU_FLIPBOOKS = 0x800CB710
ENBU_FLIPBOOK_CHARS = (9, 4)        # FUN_800D3D64: FighterUploadFlipbook(0, 9, …), (1, 4, …)
CHAR_RECORDS = 0x80027BAC           # 6 bytes per charId: s16 frame count, R, G, B
SYSTEM_RECORDS = 0x80027C30         # 6 bytes per set-3 index: s16 frame count, R, G, B
SYSTEM_RECORD_OF = (0, 1, 1, 3)     # FUN_80076704 points index 2 at index 1's record (bug #51)
LAYOUTS = 0x80027C48                # per block 0x30: per index 12 bytes (clutX, clutY, x, y, pageW, pageH)
SYSTEM_BLOCK = 2
SYSTEM_NAMES = ("hit", "hit_no_damage", "guard", "dust")
HALF_BLEND = {3}                    # FlipbookSetup: set 3 index 3 is drawn at 50 %, others additive
FRAME = 32
CLUT_ROW, SPARE_ROW = 511, 510
FRAME_WORDS = FRAME // 4
DUST_OFFSETS = 0x8001E818           # 6 × (x, y, z, pad) s16: the landing dust ring
DUST_PUFFS = 6
DUST_HEIGHT = -0x7D00 >> 7          # FUN_8004AC28: the ring's y (`0xFFFF8300` >> 7)
DUST_INTERVAL = 2                   # FUN_8004AD28: a new puff every second frame
COSTUME_KEYS = 0x80095CE8           # s8 costume slot per costume key (charId · 4 + costume)
COSTUME_KEY_COUNT = 0x5C
COSTUME_ARC_FIRST = 73              # the costume's .arc: BNS 73 + 4 · slot
NO_FLIPBOOK_SLOTS = range(47, 51)   # slots without a fighting costume (convert.COSTUME_SLOTS)
# Effect objects' CLUTs (effects.md#common-conventions): the fixed ones of row 503 and the fade
# ramps of rows 509 and 510 (FUN_8006E848), as CLUT ids (x / 16 | y << 6).
OBJECT_CLUTS = [*range(0x7DC6, 0x7DCB), *[0x7F40 | (0x10 + i) for i in range(16)],
                *[0x7F80 | (0x10 + i) for i in range(16)]]


# The effect objects' drawing (effects.md#common-conventions): the quad models by the remake's
# EffectObjects.Model order (NONE first), each model's own 16 × 16 sprite (u, v) where it has one,
# and the UV tables of the animated phases by EffectObjects.UvTable order (after MODEL):
# (table, frames, frame size). BALL_CHARACTER reads the charged ball's character flipbook.
OBJECT_PAGE = (960, 256)            # tpage 0x3F / 0x1F: the page of every object sprite
OBJECT_MODELS = [None, 0x8002554C, 0x8002556C, 0x800256E0, 0x80025700, 0x80025740, 0x80025720, 0x800257C0,
                 0x800257E0, 0x80025800, 0x80025878, 0x80025898, 0x800258FC, 0x8002591C, 0x8002593C,
                 0x800259EC, 0x800259CC, 0x8002595C]
SPRITE_UV = {1: (0x80, 0x90), 2: (0x80, 0x80), 3: (0x80, 0x80), 4: (0x80, 0x80), 14: (0x80, 0x80)}
OBJECT_UV_TABLES = [(0x80025760, 8, 32), (0x80025770, 8, 32), (0x80025780, 8, 32), (0x80025798, 8, 16),
                    (0x800257A8, 12, 16), (0x80025820, 4, 32), (0x80025828, 4, 32), (0x80025830, 5, 32),
                    (0x80025858, 16, 16), (0x800258B8, 21, 32), (0x80025A0C, 27, 32), (0x8002597C, 12, 32)]
SPRITE_SIZE = 16
BALL_GLOW_V = 0x80                  # FUN_800743EC reads the glow's table rows 128 lines down
BALL_GLOW_FRAMES = 32               # frames a character flipbook upload may hold (30 at most)


def _object_drawing(disc: Disc, system: Vram, out: Output) -> dict:
    """The objects' page as 4-bit indices (object_page.png, value = index) and the palettes of
    OBJECT_CLUTS one per row (object_palettes.png), with the models and UV tables."""
    px, py = OBJECT_PAGE
    words = system.words[py:py + 256, px:px + 64].astype(np.uint32)
    indices = np.stack([(words >> (4 * k)) & 0xF for k in range(4)], axis=-1).reshape(256, 256).astype(np.uint8)
    page = np.zeros((256, 256, 4), dtype=np.uint8)
    page[..., 0] = indices
    page[..., 3] = 255
    out.write("effects/object_page.png", png_bytes(page))
    rows = np.zeros((len(OBJECT_CLUTS), 16, 4), dtype=np.uint8)
    for i, clut in enumerate(OBJECT_CLUTS):
        x, y = clut_xy(clut)
        rows[i] = rgba(system.words[y, x:x + 16])
    out.write("effects/object_palettes.png", png_bytes(rows))
    quads = [[disc.exe_s16(a + 8 * k, 2) for k in range(4)] if a else [] for a in OBJECT_MODELS]
    sprites = {str(model): [u, v, SPRITE_SIZE] for model, (u, v) in SPRITE_UV.items()}
    tables = [{"size": size, "frames": [disc.exe_u8(a + 2 * k, 2) for k in range(n)]} for a, n, size in OBJECT_UV_TABLES]
    return {"page": "object_page.png", "palettes": "object_palettes.png", "clut_rows": OBJECT_CLUTS,
            "quads": quads, "sprites": sprites, "uv_tables": tables, "ball_glow_frames": _ball_glow_frames(disc)}


def _ball_glow_frames(disc: Disc) -> list[int]:
    """The character flipbook frame each step of the charged ball's glow shows (FUN_800743EC): the
    table's (u in words, v + BALL_GLOW_V) from the player's upload (FighterUploadFlipbook; player
    1's lies 0x80 words further), found among the frames as the upload walks them; −1 for none."""
    _, _, x, y, page_w, page_h = disc.exe_s16(LAYOUTS, 6)
    positions = page_walk(x, y, page_w, page_h, BALL_GLOW_FRAMES)
    table, count, _ = OBJECT_UV_TABLES[-1]
    frames = []
    for k in range(count):
        u, v = disc.exe_u8(table + 2 * k, 2)
        at = (x + u, y + v + BALL_GLOW_V)
        frames.append(positions.index(at) if at in positions else -1)
    return frames


def _frames_4bit(out: Output, rel: str, vram: Vram, positions: list[tuple[int, int]],
                 clut: tuple[int, int]) -> np.ndarray:
    """The frames at VRAM word positions side by side, through a 4-bit CLUT (recorded as pieces)."""
    palette = vram.words[clut[1], clut[0]:clut[0] + 16]
    strip = np.zeros((FRAME, FRAME * len(positions), 4), dtype=np.uint8)
    for n, (x, y) in enumerate(positions):
        indices = unpack_indices(vram.words[y:y + FRAME, x:x + FRAME_WORDS], 4)
        strip[:, FRAME * n:FRAME * (n + 1)] = rgba(palette[indices])
        sources.piece(out, rel, FRAME * n, 0, vram.words, 4 * x, y, FRAME, FRAME, 4, palette)
    return strip


def page_walk(x: int, y: int, page_w: int, page_h: int, count: int) -> list[tuple[int, int]]:
    """VRAM word positions of a flipbook's frames (FlipbookSetup + FUN_80077158's advance)."""
    per_row, rows = page_w // FRAME_WORDS, page_h // FRAME
    col, row = (x % page_w) // FRAME_WORDS, (y % page_h) // FRAME
    base_x, base_y = (x // page_w) * page_w, (y // page_h) * page_h
    out = []
    for _ in range(count):
        out.append((x, y))
        x += FRAME_WORDS
        col += 1
        if col >= per_row:
            row += 1
            y += FRAME
            if row >= rows:
                row = 0
                y = base_y
                base_x += FRAME_WORDS * per_row
            col = 0
            x = base_x
    return out


def _record(disc: Disc, addr: int) -> tuple[int, list[int]]:
    count = disc.exe_s16(addr, 1)[0]
    return count, disc.exe_u8(addr + 2, 3)


def _character_flipbook(disc: Disc, out: Output, name: str, member: bytes, char_id: int) -> dict:
    """A character flipbook: one TIM per frame in playback order, all through the first TIM's
    CLUT (the TIMs have zero rectangles: the uploader places them)."""
    tims, _ = tim_sequence(member)
    count, colour = _record(disc, CHAR_RECORDS + 6 * char_id)
    vram = Vram()
    positions = []
    for n, tim in enumerate(tims[:count]):
        x, y = FRAME_WORDS * (n % 2), FRAME * (n // 2)
        vram.upload_tim(tim, x, y, 0, CLUT_ROW if n == 0 else SPARE_ROW)
        positions.append((x, y))
    strip = _frames_4bit(out, f"effects/{name}.png", vram, positions, (0, CLUT_ROW))
    out.write(f"effects/{name}.png", png_bytes(strip))
    return {"name": name, "file": f"{name}.png", "frames": len(positions), "blend": "add", "light": colour}


def convert(disc: Disc, out: Output) -> None:
    system = disc.system_vram()
    table = {"system": [], "enbu": []}
    for index, name in enumerate(SYSTEM_NAMES):
        clut_x, clut_y, x, y, page_w, page_h = disc.exe_s16(LAYOUTS + 0x30 * SYSTEM_BLOCK + 12 * index, 6)
        count, _ = _record(disc, SYSTEM_RECORDS + 6 * SYSTEM_RECORD_OF[index])
        own_count, _ = _record(disc, SYSTEM_RECORDS + 6 * index)
        strip = _frames_4bit(out, f"effects/{name}.png", system, page_walk(x, y, page_w, page_h, own_count),
                             (clut_x, clut_y))
        out.write(f"effects/{name}.png", png_bytes(strip))
        table["system"].append({"name": name, "file": f"{name}.png", "frames": own_count, "game_frames": count,
                                "blend": "half" if index in HALF_BLEND else "add"})
    data, offset = disc.source("enbu", ENBU_FLIPBOOKS)
    members = arc_members(data[offset:])
    for player, char_id in enumerate(ENBU_FLIPBOOK_CHARS):
        table["enbu"].append(_character_flipbook(disc, out, f"enbu_{player}", members[player], char_id))
    # The fight's character flipbooks: FighterLoadCharacter uploads the costume ARC's member 1
    # with FighterUploadFlipbook(player, charId), the frame count and light from the charId.
    table["costumes"] = {}
    for key, byte in enumerate(disc.exe_u8(COSTUME_KEYS, COSTUME_KEY_COUNT)):
        slot = byte - 256 if byte > 127 else byte
        if slot < 0 or str(slot) in table["costumes"] or slot in NO_FLIPBOOK_SLOTS:
            continue
        member = arc_members(disc.bns(COSTUME_ARC_FIRST + 4 * slot))[1]
        table["costumes"][str(slot)] = _character_flipbook(disc, out, f"costume_{slot:02d}", member, key >> 2)
    palettes = {}
    for clut in OBJECT_CLUTS:
        x, y = clut_xy(clut)
        palettes[str(clut)] = rgba(system.words[y, x:x + 16]).tolist()
    table["object_palettes"] = palettes
    table["objects"] = _object_drawing(disc, system, out)
    offsets = [disc.exe_s16(DUST_OFFSETS + 8 * i, 3) for i in range(DUST_PUFFS)]
    out.write_json("effects/effects.json", {
        **table,
        "dust_ring": {"offsets": offsets, "y": DUST_HEIGHT, "interval": DUST_INTERVAL, "flipbook": "dust"},
    })
