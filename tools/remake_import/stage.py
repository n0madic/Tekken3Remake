"""Stages (stg_*.tmd + stg_*.arc) → panorama mesh, textures and floor tiles.

Output (`stages/<letter>/`):

- `stage.json`: grid cell size, panorama height, floor colour, kind and distance shading (factor
  and fade distance, stages.md#floor), floor tiles, the light rig record (stages.md#lighting) and the view coverage the remake's camera rig uses for
  wide and tall windows (remake-plan.md#aspect-ratios);
- `panorama.bin`: `VERTEX_FLOATS` little-endian floats per corner (`x, y, z, u, v, r, g, b`).
  Object vertices are absolute panorama coordinates; the 6 × 6 grid of StageBackgroundSetup
  only selects which objects are drawn (stages.md#panorama);
- `panorama.png`: an atlas of the used regions of the 4-bit pages through their CLUTs;
- `floor.png`: the 10 × 10 floor pattern as one repeating picture, tiles oriented as drawn;
- `floor_smooth.png`: the same with the colour steps at the tile seams removed.

`stages/floor_fade.json` holds the floor's shading table (FloorDrawGrid's 1,024 bytes).
"""

from __future__ import annotations

import struct

from common import Disc, Output
from move_text import arc_members
from vram import TIM_ID, Vram, clut_xy, png_bytes, rgba, tim_sequence, tpage_xy
import atlas
import numpy as np
import sources

GRID = 6
OBJECTS = GRID * GRID
TABLE = 0x0C
ROW_BYTES = 0x1C
PACKET_BYTES = {0x24: 20, 0x28: 8, 0x2C: 20}
PANORAMA_HEIGHT = 0x80025394   # s16 per stage, stride 4 (StageBackgroundDraw)
VERTEX_FLOATS = 8
FLOOR_TILES = 10
FLOOR_ENTRY_BYTES = 8
FLOOR_KIND = 0x324
FLOOR_SHADE = 0x326            # s16 distance shading factor of a kind-0 floor (0: none)
FLOOR_FADE_TABLE = 0x8001DF6C  # FloorDrawGrid: 1,024 shading steps by scaled distance
FLOOR_FADE_ENTRIES = 1024
FLOOR_FADE = 10000             # FloorSetup: the fade distance
FLOOR_FADE_NEAR = 6500         # … on stages 1, 2 and 7
FLOOR_FADE_NEAR_STAGES = (1, 2, 7)
TPAGE_MASK = 0x39FF
TILE_TEXELS = 64
QUAD_TRIANGLES = ((0, 1, 2), (1, 3, 2))
UNTEXTURED = "untextured"
LIGHT_RECORDS = 0x8009709C     # 28 bytes per stage (stages.md#lighting)
LIGHT_RECORD_BYTES = 0x1C
PANORAMA_PARALLAX = 8          # the panorama is the object geometry scaled by 8 (StageBackgroundDraw)
COVERAGE_YAWS = 72             # view coverage: directions around the arena …
COVERAGE_STEP = 1              # … and elevation steps (degrees) tested per direction
COVERAGE_EYE = (0, -1500, 0)   # a camera position inside the arena (game units, y down)
COVERAGE_EPSILON = 1e-3        # barycentric tolerance: a ray along an edge two objects share hits


def panorama(tmd: bytes) -> tuple[int, list[tuple]]:
    cell = 10 * struct.unpack_from("<I", tmd, 4)[0]
    count = struct.unpack_from("<I", tmd, 8)[0]
    if count != OBJECTS:
        raise ValueError(f"expected {OBJECTS} panorama objects, found {count}")
    corners_out: list[tuple] = []
    for index in range(OBJECTS):
        vert_off, vert_count, _, _, prim_off, prim_count, _ = struct.unpack_from("<7I", tmd, TABLE + ROW_BYTES * index)
        verts = [struct.unpack_from("<3h", tmd, TABLE + vert_off + 8 * i) for i in range(vert_count)]
        pos = TABLE + prim_off
        for _ in range(prim_count):
            r, g, b, code = tmd[pos:pos + 4]
            if code == 0x28:
                idx = tmd[pos + 4:pos + 8]
                uvs = [(0, 0)] * 4
                key = UNTEXTURED
            else:
                u0, v0, cba = struct.unpack_from("<BBH", tmd, pos + 4)
                u1, v1, tsb = struct.unpack_from("<BBH", tmd, pos + 8)
                u2, v2, u3, v3 = tmd[pos + 12:pos + 16]
                idx = tmd[pos + 16:pos + 20] if code == 0x2C else tmd[pos + 16:pos + 19]
                uvs = [(u0, v0), (u1, v1), (u2, v2), (u3, v3)]
                key = f"{cba:04x}_{tsb:04x}"
            corners = []
            for c, vi in enumerate(idx):
                x, y, z = verts[vi]
                u, v = uvs[c]
                corners.append((key, (x, y, z), u, v, (r / 128, g / 128, b / 128)))
            for tri in ([(0, 1, 2)] if len(corners) == 3 else QUAD_TRIANGLES):
                corners_out.extend(corners[i] for i in tri)
            pos += PACKET_BYTES[code]
    return cell, corners_out


# FloorSetup (0x8009EBA8): four corner sets, the tile's texel corners for vertices c0..c3
# (0 or 63 in u and v); entry bits 30–31 select the set.
FLOOR_CORNER_SETS = (
    ((0, 0), (1, 0), (0, 1), (1, 1)),
    ((0, 1), (0, 0), (1, 1), (1, 0)),
    ((1, 1), (0, 1), (1, 0), (0, 0)),
    ((1, 0), (1, 1), (0, 0), (0, 1)),
)
# FloorDrawGrid: entry bits 25–26 give the order in which the set's corners go to v0..v3.
FLOOR_CORNER_ORDERS = ((0, 1, 2, 3), (1, 0, 3, 2), (2, 3, 0, 1), (3, 2, 1, 0))
# Picture position of the floor model's vertices: v0 (x0, z1) top left, v1 (x1, z1) top right,
# v2 (x0, z0) bottom left, v3 (x1, z0) bottom right; picture rows run towards −z.
FLOOR_VERTEX_CORNERS = ((0, 0), (1, 0), (0, 1), (1, 1))
SEAM_BAND = 4                   # texels on each side of a seam that absorb its step


def tile_transform(entry: int) -> tuple[int, int, int, int, int, int]:
    """A floor entry's texel map: the corner (u00, v00 ∈ {0, 1}) drawn at the picture's top left and
    (a, b, c, d), the texel step (a·col + b·row, c·col + d·row) per picture column and row. Every
    corner assignment is a rotation or mirror, so the map is affine."""
    corners = FLOOR_CORNER_SETS[(entry >> 30) & 3]
    order = FLOOR_CORNER_ORDERS[(entry >> 25) & 3]
    texel = {FLOOR_VERTEX_CORNERS[k]: corners[order[k]] for k in range(4)}
    (u00, v00), (u10, v10), (u01, v01) = texel[(0, 0)], texel[(1, 0)], texel[(0, 1)]
    return u00, v00, u10 - u00, u01 - u00, v10 - v00, v01 - v00


def oriented_tile(tile: np.ndarray, entry: int) -> np.ndarray:
    """The 64 × 64 picture as drawn: texel corners assigned to the quad's vertices."""
    u00, v00, a, b, c, d = tile_transform(entry)
    n = TILE_TEXELS - 1
    col, row = np.meshgrid(np.arange(TILE_TEXELS), np.arange(TILE_TEXELS))
    return tile[v00 * n + c * col + d * row, u00 * n + a * col + b * row]


def floor_pattern(out: Output, rel: str, descriptor: bytes, vram: Vram) -> tuple[list[dict], np.ndarray]:
    """The 10 × 10 floor pattern as one picture, tiles oriented as the game draws them.

    Picture column c and row r hold pattern entry 10·r + c. FloorDrawGrid walks the
    columns forwards and the rows backwards, so the tile over x ∈ [1800·tx, 1800·(tx + 1)],
    z ∈ [1800·tz, 1800·(tz + 1)] is entry column (tx + 5) mod 10, row (4 − tz) mod 10;
    in texture coordinates u = (x / 1800 + 5) / 10, v = (5 − z / 1800) / 10, repeating.
    """
    tiles = []
    picture = np.zeros((FLOOR_TILES * TILE_TEXELS, FLOOR_TILES * TILE_TEXELS, 4), dtype=np.uint8)
    for i in range(FLOOR_TILES * FLOOR_TILES):
        w0, w1 = struct.unpack_from("<II", descriptor, 4 + FLOOR_ENTRY_BYTES * i)
        u, v = w0 & 0xFF, (w0 >> 8) & 0xFF
        page_x, page_y = tpage_xy((w0 >> 16) & TPAGE_MASK)
        clut_x, clut_y = clut_xy(w1 >> 16)
        indices = vram.page_indices(page_x, page_y, 4)[v:v + TILE_TEXELS, u:u + TILE_TEXELS]
        tile = rgba(vram.clut(clut_x, clut_y, 16)[indices])
        r, c = divmod(i, FLOOR_TILES)
        picture[r * TILE_TEXELS:(r + 1) * TILE_TEXELS, c * TILE_TEXELS:(c + 1) * TILE_TEXELS] = oriented_tile(tile, w0)
        sources.page_piece(out, rel, c * TILE_TEXELS, r * TILE_TEXELS, vram, page_x, page_y, 4, u, v,
                           TILE_TEXELS, TILE_TEXELS, clut_x, clut_y, tile_transform(w0)[2:])
        tiles.append({"entry": w0, "clut": w1 >> 16})
    return tiles, picture


def smooth_seams(picture: np.ndarray, period: int = TILE_TEXELS, band: int = SEAM_BAND) -> np.ndarray:
    """Removes the colour step at every tile seam of a repeating picture.

    The stage art does not tile perfectly; at the PlayStation's resolution the step was
    hidden, at modern resolutions it shows as a line. Half of the step across each seam is
    subtracted on either side, fading out over `band` texels, which keeps the texture detail.
    Seams are treated with wrap-around, since the pattern repeats.
    """
    out = picture.astype(np.float64)
    fade = (1.0 - (np.arange(band) + 0.5) / band)[None, :, None]
    for _axis in range(2):
        width = out.shape[1]
        for x in range(0, width, period):
            left = (x - 1) % width
            step = (out[:, left, :3] - out[:, x, :3])[:, None, :]
            cols_right = [(x + i) % width for i in range(band)]
            cols_left = [(x - 1 - i) % width for i in range(band)]
            out[:, cols_right, :3] += step / 2 * fade
            out[:, cols_left, :3] -= step / 2 * fade
        out = out.transpose(1, 0, 2)
    return np.clip(np.rint(out), 0, 255).astype(np.uint8)


def lighting(disc: Disc, stage: int) -> dict:
    """The stage's light rig record (stages.md#lighting)."""
    rec = disc.exe_bytes(LIGHT_RECORDS + LIGHT_RECORD_BYTES * stage, LIGHT_RECORD_BYTES)
    ambient = struct.unpack_from("<i", rec, 0)[0]
    pitch, yaw = struct.unpack_from("<hh", rec, 0x0C)
    return {
        "ambient": ambient >> 4,
        "ambient_level": ambient & 0xFFFF,
        "base_rgb": [rec[0x04], rec[0x05], rec[0x06]],
        "light_rgb": [rec[0x0A], rec[0x09], rec[0x08]],
        "light_pitch": pitch,
        "light_yaw": yaw,
    }


def coverage(corners: list[tuple], height: int) -> list[int]:
    """Per direction (COVERAGE_YAWS around +x, counter-clockwise seen from above), the highest
    elevation in degrees up to which every view ray from COVERAGE_EYE hits the panorama
    (90: the backdrop closes overhead). The remake limits how far a tall window extends the
    view upwards by it (remake-plan.md#aspect-ratios). A ray along an edge two objects share
    counts as a hit (COVERAGE_EPSILON). Only faces turned to the eye count: the remake culls the
    others (panorama.gdshader), whose normal e1 x e2 points along the ray."""
    tris = np.array([c[1] for c in corners], dtype=np.float64).reshape(-1, 3, 3) * PANORAMA_PARALLAX
    tris[:, :, 1] += height
    v0, e1, e2 = tris[:, 0], tris[:, 1] - tris[:, 0], tris[:, 2] - tris[:, 0]
    normals = np.cross(e1, e2)
    eye = np.array(COVERAGE_EYE, dtype=np.float64)
    out = []
    for k in range(COVERAGE_YAWS):
        yaw = 2 * np.pi * k / COVERAGE_YAWS
        covered = 0
        for elevation in range(0, 91, COVERAGE_STEP):
            e = np.radians(elevation)
            d = np.array([np.cos(yaw) * np.cos(e), -np.sin(e), -np.sin(yaw) * np.cos(e)])
            p = np.cross(d, e2)
            det = np.einsum("ij,ij->i", e1, p)
            ok = np.abs(det) > 1e-9
            inv = np.where(ok, 1.0 / np.where(ok, det, 1.0), 0.0)
            t = eye - v0
            u = np.einsum("ij,ij->i", t, p) * inv
            q = np.cross(t, e1)
            v = (q @ d) * inv
            dist = np.einsum("ij,ij->i", e2, q) * inv
            eps = COVERAGE_EPSILON
            facing = normals @ d > 0
            if not np.any(ok & facing & (u >= -eps) & (v >= -eps) & (u + v <= 1 + eps) & (dist > 0)):
                break
            covered = elevation
        out.append(covered)
    # A gap narrower than one direction step (the corners where grid cells meet, seen along
    # the diagonal) is a slit the 4:3 frame already shows; it does not limit the extension.
    n = len(out)
    return [max(out[k], min(out[k - 1], out[(k + 1) % n])) for k in range(n)]


def floor_shading(descriptor: bytes, stage: int) -> dict:
    """FloorSetup's distance shading of a kind-0 floor: the factor and the fade distance."""
    return {"floor_shade": struct.unpack_from("<h", descriptor, FLOOR_SHADE)[0],
            "floor_fade": FLOOR_FADE_NEAR if stage in FLOOR_FADE_NEAR_STAGES else FLOOR_FADE}


def convert_floor_fade(disc: Disc, out: Output) -> None:
    """`stages/floor_fade.json`: FloorDrawGrid's shading table."""
    out.write_json("stages/floor_fade.json", {"table": disc.exe_u8(FLOOR_FADE_TABLE, FLOOR_FADE_ENTRIES)})


def _panorama_page(key: str) -> tuple[int, int, int, int, int] | None:
    """(page x, page y, depth, CLUT x, CLUT y) of a panorama corner key "<cba>_<tsb>", or None if untextured."""
    if key == UNTEXTURED:
        return None
    cba, tsb = (int(p, 16) for p in key.split("_"))
    return (*tpage_xy(tsb), 4, *clut_xy(cba))


def convert(disc: Disc, out: Output, stage: int, letter: str, arc_id: int, tmd_id: int) -> None:
    members = arc_members(disc.bns(arc_id))
    vram = Vram()
    tims, _ = tim_sequence(members[0])
    for tim in tims:
        vram.upload_tim(tim)
    cell, corners = panorama(disc.bns(tmd_id))
    used: dict[str, list[tuple[int, int]]] = {}
    for key, _, u, v, _ in corners:
        used.setdefault(key, []).append((u, v))
    pages = {}
    for key in used:
        page = _panorama_page(key)
        pages[key] = np.full((256, 256, 4), 255, dtype=np.uint8) if page is None else vram.page_rgba(*page)
    packed = atlas.build(pages, used)
    base = f"stages/{letter}"
    out.write(f"{base}/panorama.png", png_bytes(packed.pixels))
    atlas.record_sources(out, f"{base}/panorama.png", packed, vram, _panorama_page)
    floats: list[float] = []
    for key, position, u, v, colour in corners:
        floats.extend(position)
        floats.extend(packed.uv(key, u, v))
        floats.extend(colour)
    mesh = struct.pack(f"<{len(floats)}f", *floats)
    tiles, floor = floor_pattern(out, f"{base}/floor.png", members[1], vram)
    out.write(f"{base}/floor.png", png_bytes(floor))
    out.write(f"{base}/floor_smooth.png", png_bytes(smooth_seams(floor)))
    sources.derived(out, f"{base}/floor_smooth.png", f"{base}/floor.png", "smooth_seams")
    out.write(f"{base}/panorama.bin", mesh)
    out.write_json(f"{base}/stage.json", {
        "stage": stage,
        "letter": letter,
        "cell": cell,
        "panorama_height": disc.exe_s16(PANORAMA_HEIGHT + 4 * stage, 1)[0],
        "floor_kind": struct.unpack_from("<h", members[1], FLOOR_KIND)[0],
        **floor_shading(members[1], stage),
        "vertex_floats": VERTEX_FLOATS,
        "panorama_texture": "panorama.png",
        # Horizontal extent of the panorama geometry (min x, max x, min z, max z, object units).
        "panorama_extent": [min(c[1][0] for c in corners), max(c[1][0] for c in corners),
                            min(c[1][2] for c in corners), max(c[1][2] for c in corners)],
        "panorama_vertices": len(corners),
        "floor_tiles": tiles,
        "floor_tile_size": 1800,
        "floor_pattern": "floor.png",
        "floor_pattern_smooth": "floor_smooth.png",
        "lighting": lighting(disc, stage),
        "coverage": {"eye": list(COVERAGE_EYE), "elevation": coverage(corners, disc.exe_s16(PANORAMA_HEIGHT + 4 * stage, 1)[0])},
    })


# ---- the tile-map stages of Tekken Force (p, q, r, s: stages 15–18) and Tekken Ball (v: 19) ----

TILED_STAGES = [(15, "p", 51), (16, "q", 52), (17, "r", 53), (18, "s", 54), (19, "v", 55)]
BALL_STAGE = 19
FORCE_TILE, BALL_TILE = 64, 32
HOW_TO_SIZES = ((216, 204), (256, 204))   # Tekken Ball's HOW TO picture (stg_v; the USA RULES one is wider), CLUT 0x7C04
HOW_TO_CLUT = 0x7C04
# Tekken Force's items (force.ovl FUN_800B4198): in texture page 8, the picture (u 0–63, v 64–191,
# CLUT 0x7801) and the shadow behind it (v 0–63, CLUT 0x7800), from the level archive's last TIMs.
ITEM_PAGE = (512, 0)
ITEM_TIM = (512, 0, 16, 64)    # the shadow's TIM: the levels with items have it
ITEM_PICTURE = (64, 64, 128, 0x7801)   # v, width, height, CLUT
ITEM_SHADOW = (0, 64, 64, 0x7800)


def _tile_origin(word: int, tile: int) -> tuple[int, int, int, int]:
    """A map cell's texture word: the page (x, y) and the tile's u, v within it (FUN_800B4DF8,
    FUN_800B5F0C)."""
    page = word >> 8 & 0x1F
    if tile == FORCE_TILE:
        u, v = (word & 3) * 64, (word & 0xC) * 16
    else:
        u, v = (word & 7) * 32, (word & 0x38) * 4
    return 64 * (page & 0xF), 256 * (page >> 4 & 1), u, v


def tile_map_picture(out: Output, rel: str, vram: Vram, tile_map: bytes, tile: int) -> tuple[int, int, np.ndarray]:
    """The whole tile map as one picture (w · tile × h · tile), each cell through its CLUT."""
    w, h = struct.unpack_from("<2H", tile_map, 0)
    textures = struct.unpack_from(f"<{w * h}H", tile_map, 4)
    cluts = struct.unpack_from(f"<{w * h}H", tile_map, 4 + 2 * w * h)
    picture = np.zeros((h * tile, w * tile, 4), dtype=np.uint8)
    pages: dict[tuple, np.ndarray] = {}
    for i in range(w * h):
        px, py, u, v = _tile_origin(textures[i], tile)
        key = (px, py, cluts[i])
        if key not in pages:
            pages[key] = vram.page_rgba(px, py, 4, *clut_xy(cluts[i]))
        r, c = divmod(i, w)
        picture[r * tile:(r + 1) * tile, c * tile:(c + 1) * tile] = pages[key][v:v + tile, u:u + tile]
        sources.page_piece(out, rel, c * tile, r * tile, vram, px, py, 4, u, v, tile, tile, *clut_xy(cluts[i]))
    return w, h, picture


def _tim_rect(tim: bytes) -> tuple[int, int, int, int]:
    """A TIM's image rectangle in VRAM (x, y, width in words, height)."""
    flags = struct.unpack_from("<I", tim, 4)[0]
    cursor = 8 + (struct.unpack_from("<I", tim, 8)[0] if flags & 8 else 0)
    return struct.unpack_from("<4H", tim, cursor + 4)


def _stage_tims(members: list[bytes]) -> tuple[Vram, list[bytes]]:
    """Member 0 of a tile-map stage is an archive of TIMs, uploaded until the first member that is
    not one (volley.ovl FUN_800B5CC4, force.ovl FUN_800B4A88)."""
    vram = Vram()
    tims = []
    for member in arc_members(members[0]):
        if len(member) < 8 or struct.unpack_from("<I", member, 0)[0] != TIM_ID:
            break
        tims.append(member)
        vram.upload_tim(member)
    return vram, tims


def how_to_picture(out: Output, rel: str, members: list[bytes]) -> np.ndarray | None:
    """Tekken Ball's HOW TO (USA: RULES) picture of the stg_v archive, through CLUT 0x7C04."""
    vram, tims = _stage_tims(members)
    cx, cy = clut_xy(HOW_TO_CLUT)
    for tim in tims:
        flags = struct.unpack_from("<I", tim, 4)[0]
        x, y, pw, ph = _tim_rect(tim)
        if flags & 3 == 0 and (pw * 4, ph) in HOW_TO_SIZES:
            page = vram.page_rgba(x & ~63, y & ~255, 4, cx, cy)
            u = (x & 63) * 4
            sources.page_piece(out, rel, 0, 0, vram, x & ~63, y & ~255, 4, u, y & 255, pw * 4, ph, cx, cy)
            return page[y & 255:(y & 255) + ph, u:u + pw * 4]
    return None


def convert_tiled(disc: Disc, out: Output, stage: int, letter: str, arc_id: int) -> None:
    """A stage without a panorama TMD: its tile map as a picture, the floor, the light rig,
    Tekken Force's level script (member 3) and Tekken Ball's HOW TO picture."""
    members = arc_members(disc.bns(arc_id))
    vram, tims = _stage_tims(members)
    base = f"stages/{letter}"
    tile = BALL_TILE if stage == BALL_STAGE else FORCE_TILE
    w, h, picture = tile_map_picture(out, f"{base}/tiles.png", vram, members[2], tile)
    out.write(f"{base}/tiles.png", png_bytes(picture))
    tiles, floor = floor_pattern(out, f"{base}/floor.png", members[1], vram)
    out.write(f"{base}/floor.png", png_bytes(floor))
    out.write(f"{base}/floor_smooth.png", png_bytes(smooth_seams(floor)))
    sources.derived(out, f"{base}/floor_smooth.png", f"{base}/floor.png", "smooth_seams")
    info = {
        "stage": stage,
        "letter": letter,
        "tile_map": {"picture": "tiles.png", "tile": tile, "width": w, "height": h},
        "floor_kind": struct.unpack_from("<h", members[1], FLOOR_KIND)[0],
        **floor_shading(members[1], stage),
        "floor_tiles": tiles,
        "floor_tile_size": 1800,
        "floor_pattern": "floor.png",
        "floor_pattern_smooth": "floor_smooth.png",
        "lighting": lighting(disc, stage),
    }
    if stage == BALL_STAGE:
        picture = how_to_picture(out, f"{base}/how_to.png", members)
        if picture is not None:
            out.write(f"{base}/how_to.png", png_bytes(picture))
            info["how_to"] = "how_to.png"
    else:
        out.write(f"{base}/level.bin", members[3])
        info["level_script"] = "level.bin"
        if any(_tim_rect(tim) == ITEM_TIM for tim in tims):
            info["item"] = {}
            for key, (v, w, h, clut) in (("picture", ITEM_PICTURE), ("shadow", ITEM_SHADOW)):
                page = vram.page_rgba(*ITEM_PAGE, 4, *clut_xy(clut))
                out.write(f"{base}/item_{key}.png", png_bytes(page[v:v + h, :w]))
                sources.page_piece(out, f"{base}/item_{key}.png", 0, 0, vram, *ITEM_PAGE, 4, 0, v, w, h, *clut_xy(clut))
                info["item"][key] = f"item_{key}.png"
    out.write_json(f"{base}/stage.json", info)
