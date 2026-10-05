"""Character models (.kmd + ARC textures) → the remake's skinned mesh format.

Every face corner of a KMD model is either one vertex of one part or the 0.5/0.5 blend
of two vertices of two parts (the seam exchange of DrawSkinnedPart, verified slot by
slot in `tools/research/verify_kmd_skin.py`). The two halves do not coincide in any single
pose, so a glTF skin with one bind position per vertex cannot reproduce the seams.
The mesh therefore stores both part-local positions per corner, and the remake's
shader blends them with the two joint matrices exactly as the game does.

Output (`characters/<name>/`):

- `model.json`: parts (row, parent, joint offset, matrix slot), surfaces, scale, the hand and
  wing surfaces per vertex variant, and the closed-eye texture when the costume has one;
- `mesh.bin.gz` (gzip): per surface, `VERTEX_FLOATS` little-endian floats per corner:
  `pa.xyz, pb.xyz, wb, n.xyz, u, v, bone_a, bone_b, bone_n, s_own.xyz, s_other.xyz, bone_other,
  curves, pc.xyz, wc, bone_c`: the position is `pa` in joint `bone_a` blended with `pb` in `bone_b`
  by `wb` and with `pc` in `bone_c` by `wc` (the PlayStation's seams halve two joints, wc = 0; the
  arcade's weigh up to three, arcade_character.py), `s_own` (in joint `bone_n`) and `s_other` (in joint `bone_other`) are the smooth
  normal's two halves (`smooth_normals`) and `curves` is 1 when the triangle's edge from this
  corner to the next may bulge on the curved surfaces (`smooth_edges`); `smooth_crease_cos` in
  `model.json` is the cosine of the angle the shader joins the halves within;
- `texture.png`: an atlas of the used regions of every material (texture page through its CLUT);
- `texture_closed.png`: the same atlas after the closed-eye rectangle is copied over the eyes
  (the blink's `MoveImage`, animation.md#blinking).
- `texture_eye<n>.png` (arcade models): the same after the arcade's eye shape `n` is copied over
  the eyes (arcade_eyes.py), listed by shape in `eye_textures`.

Vertex variants: the hand rows have 41 alternative vertex blocks with the same exchange lists as
the base block (checked for all 52 models and the demonstration models), so only their own
coordinates change. The faces that use a hand vertex are therefore stored once per variant
the game can select (`HAND_VARIANTS`), and the remake swaps those surfaces as
`FighterHandPoses` swaps the blocks. Every such set of faces is a `VariantGroup`; the arcade's
True Ogre has two more, wings and tail (arcade_character.py), listed under "wings". The PlayStation's
hands are whole rows, a surface set per variant. The jaw of its Kuma, Panda and Gon (channel 0, the
head's rows 19 and 20, of which much stays still) and the arcade's hands and jaws (all 41 variants)
are `packed`: one set of surfaces (the first variant's), `poses` (the part-local positions of the group's moving vertices in every distinct
variant, float32 triples, and per corner of that set the three vertex numbers its positions are,
int32, −1: not moving, both in `mesh.bin.gz`) and `select`, which maps the variants to the
distinct ones. The remake patches the corners' positions (`POSITION_FLOATS`) with a variant's table.
"""

from __future__ import annotations

import math
import struct
from collections.abc import Callable, Sequence
from dataclasses import dataclass

import numpy as np

from common import Disc, Output, gzipped
from move_text import arc_members
import kmd as kmdlib
import tables
from vram import Vram, atlas_planes, png_bytes, tim_sequence
import atlas
import gaze
from gaze import EYE_RECTS, EYE_SIZES, GON      # the eye rectangles' tables, Gon's character id

# Draw parts whose next KMD row is a second mesh drawn with the same matrix (EXE 0x8001A044).
SECOND_MESH_PARTS = (1, 2, 17)
ATTACHMENT_ENABLE = 0x80096222      # u8 per (costume slot, part): attachment parts 18–21 drawn
EYE_LAYOUT = 0x80095DF0             # 4 × s8 per costume slot: eye rectangle, size, open, closed
EYE_TEXTURE = "texture_eye"         # an eye shape's atlas: texture_eye<shape>.png (the arcade's shapes)
# Gon's head palette (3dmk-models.md#vertex-variants): 4 × s8 per costume slot, indices into EYE_SIZES
# and EYE_RECTS: the palette's size, its place, where FUN_800342a0 saves it and the rectangle (an
# all-black palette in his ARC) PartSelectVertexVariant copies over it for variants PALETTE_SWAP_VARIANTS.
PALETTE_TABLE = 0x80095D40
PALETTE_SWAP_VARIANTS = (4, 5)
PALETTE_SWAP = "texture_swap"       # the atlas with the swapped palette: texture_swap.png
HAND_PARTS = (16, 12)               # hand channel 0 and 1 (FighterHandPoses)
# FighterHandPoses points channel 0 at the head, part 17, instead of the hand of part 16 for Kuma and
# Panda (character 11) and Gon (0x11): the jaw (3dmk-models.md#vertex-variants).
JAW_PART = 17
JAW_CHARACTERS = (11, 0x11)
ATTACHMENT_PARAMS = 0x80096660      # per (costume slot, attachment): pointer to the dynamics record
ATTACHMENT_STATIC = 0x8009636C      # the record of attachments without dynamics
ATTACHMENT_RECORD = 12              # s16 per record (FUN_80037F10, FUN_80038684)
REST_ANGLE_WORDS = (9, 10, 11)      # KMD row +0x24, +0x28, +0x2C: rest Euler angles (FUN_80037EAC)
HAND_VARIANTS = 10                  # channel values 0..0x206 select variants 0..9
HANDS, WINGS = "hands", "wings"     # model.json's lists of variant groups
ATTACHMENT_STRIDE = 6
FIRST_ATTACHMENT_PART = 18
TEXTURE_ORIGIN = (384, 0)           # player 1: TIM rectangle offset in VRAM
CLUT_ORIGIN_Y = 504                 # player 1: CLUT row offset
FORCE_ENEMY_SETS = 4                # Tekken Force's enemies: texture sets in one archive
FORCE_ENEMY_FIRST_SLOT = 47         # their costume slots, one per set (the set number is slot − 47)
FORCE_ENEMY_SLOTS = range(FORCE_ENEMY_FIRST_SLOT, FORCE_ENEMY_FIRST_SLOT + FORCE_ENEMY_SETS)
ENEMY_SET_STEP = 16                 # VRAM words between them
EIGHT_BIT = 0x80
VERTEX_FLOATS = 28
POSITION_FLOATS = (0, 3, 23)        # the floats of a corner's pa, pb and pc (the positions a variant moves)
# Smooth normals: the game's normals at a point within this angle of each other are averaged.
SMOOTH_CREASE_DEGREES = 80.0
QUAD_TRIANGLES = ((0, 1, 2), (1, 3, 2))
MOVE_LIST_MEMBER = 4
MOVE_LIST_SIZE = 0x232
MOVE_GLYPHS_ORIGIN = (80, 16)      # the glyph atlas's own rectangle (uploaded at (464, 16) + 256·player)  # GPU order v0 v1 v2 v3 → two triangles, same winding


@dataclass(frozen=True)
class Term:
    part: int
    row: int
    index: int


class Blend(dict):
    """A linear combination of part-local vertices: Term → weight."""

    def plus(self, other: "Blend") -> "Blend":
        out = Blend(self)
        for key, weight in other.items():
            out[key] = out.get(key, 0.0) + weight
        return out

    def halved(self) -> "Blend":
        return Blend({key: weight / 2 for key, weight in self.items()})


def drawn_rows(model: kmdlib.Kmd, attachments: list[bool]) -> list[tuple[int, int]]:
    """(part, row) in draw order: FighterDrawParts draws each part, then its second mesh."""
    out = []
    for part, row_index in enumerate(kmdlib.PART_ROW):
        if part >= FIRST_ATTACHMENT_PART and not attachments[part - FIRST_ATTACHMENT_PART]:
            continue
        rows = [row_index] + ([row_index + 1] if part in SECOND_MESH_PARTS else [])
        for r in rows:
            if model.rows[r].verts is not None:
                out.append((part, r))
    return out


def exchange_positions(model: kmdlib.Kmd, order: list[tuple[int, int]]) -> dict[tuple[int, int], dict[int, Blend]]:
    """Vertex slots of every drawn row as blends of part-local vertices."""
    scratch: dict[int, Blend] = {}
    shared: dict[int, Blend] = {}
    result = {}
    for part, row_index in order:
        vb = model.rows[row_index].verts
        cur = 0
        for idx in vb.import_scratch:
            scratch[cur] = scratch[idx // 2 - 1]
            cur += 1
        for idx in vb.import_global:
            scratch[cur] = shared[idx // 2 - 1]
            cur += 1
        for i in range(len(vb.coords)):
            scratch[cur + i] = Blend({Term(part, row_index, i): 1.0})
        blend_a, add_global, add_scratch, export_global, export_scratch, halve = vb.post
        for e in blend_a:
            slot = (e & 0xFF) // 2 - 1
            own = scratch[cur].halved() if e & 0x100 else scratch[cur]
            scratch[cur] = shared[slot] = own.plus(shared[slot])
            cur += 1
        for entries, buffer in ((add_global, shared), (add_scratch, scratch)):
            for e in entries:
                own = scratch[cur].halved() if e & 0x100 else scratch[cur]
                scratch[cur] = own.plus(buffer[(e & 0xFF) // 2 - 1])
                cur += 1
        for entries, buffer in ((export_global, shared), (export_scratch, scratch)):
            for e in entries:
                if e & 0x100:
                    scratch[cur] = scratch[cur].halved()
                buffer[(e & 0xFF) // 2 - 1] = scratch[cur]
                cur += 1
        for code in halve:
            if code != 1:
                scratch[cur] = scratch[cur].halved()
            cur += 1
        count = len(vb.import_scratch) + len(vb.import_global) + len(vb.coords)
        result[(part, row_index)] = {i: scratch[i] for i in range(count)}
    return result


def exchange_normals(model: kmdlib.Kmd, order: list[tuple[int, int]]) -> dict[tuple[int, int], dict[int, Term]]:
    """Lit-colour slots of every drawn row as the normal that produced the colour."""
    scratch: dict[int, Term] = {}
    shared: dict[int, Term] = {}
    result = {}
    for part, row_index in order:
        nb = model.rows[row_index].normals
        cur = 1
        for idx in nb.import_scratch:
            scratch[cur] = scratch[idx // 2]
            cur += 1
        for idx in nb.import_global:
            scratch[cur] = shared[idx // 2]
            cur += 1
        for i in range(len(nb.coords)):
            scratch[cur] = Term(part, row_index, i)
            cur += 1
        source = nb.lead // 4
        to_global, to_scratch = nb.post
        for idx in to_global:
            shared[idx // 2] = scratch[source]
            source += 1
        for idx in to_scratch:
            scratch[idx // 2] = scratch[source]
            source += 1
        result[(part, row_index)] = dict(scratch)
    return result


def material_page(material: int) -> tuple[int, int, int, int, int]:
    """(page x, page y, depth, CLUT x, CLUT y) of a KMD material word for player 1."""
    bits, clut_low = material >> 8, material & 0xFF
    depth = 8 if bits & EIGHT_BIT else 4
    page_x = TEXTURE_ORIGIN[0] + (64 if bits & 1 and depth == 4 else 0)
    return page_x, TEXTURE_ORIGIN[1], depth, 16 * (clut_low & 63), CLUT_ORIGIN_Y + (clut_low >> 6)


def load_textures(data: bytes, only_set: int | None = None) -> Vram:
    """FighterUploadTextures for player 1: a TIM sequence at (384, 0), CLUTs from row 504.

    Tekken Force's enemies (slots 47–50) share an archive of four TIM sequences instead, one
    per enemy (FighterSetupModel uploads them all): sequence k goes 16 · k words to the right,
    its CLUTs k rows down. The first also holds the enemies' name strip (52 × 64 at x 80).
    With `only_set`, just that sequence, uploaded where sequence 0 goes."""
    vram = Vram()
    tims, _ = tim_sequence(data)
    if tims:
        for tim in tims:
            vram.upload_tim(tim, *TEXTURE_ORIGIN, 0, CLUT_ORIGIN_Y)
        return vram
    for k, member in enumerate(arc_members(data)[:FORCE_ENEMY_SETS]):
        if only_set not in (None, k):
            continue
        shift = 0 if only_set is not None else k
        for tim in tim_sequence(member)[0]:
            vram.upload_tim(tim, TEXTURE_ORIGIN[0] + ENEMY_SET_STEP * shift, TEXTURE_ORIGIN[1], 0, CLUT_ORIGIN_Y + shift)
    return vram


def costume_textures(disc: Disc, arc_id: int) -> Vram:
    """`load_textures` of a costume ARC's member 0, made once per disc (shared: not to be changed)."""
    if arc_id not in disc.costume_vrams:
        disc.costume_vrams[arc_id] = load_textures(arc_members(disc.bns(arc_id))[0])
    return disc.costume_vrams[arc_id]


def model_textures(disc: Disc, slot: int, arc_id: int) -> Vram:
    """The VRAM a costume's model is drawn with. FighterSetupPart adds the set number k of a Tekken
    Force enemy (slot − 47) to its faces' texture coordinates (u + 64 · k) and CLUT row, so the
    model sees its own set as if it were the first: that set alone, at the origin."""
    if slot in FORCE_ENEMY_SLOTS:
        return load_textures(arc_members(disc.bns(arc_id))[0], slot - FORCE_ENEMY_FIRST_SLOT)
    return costume_textures(disc, arc_id)


def eye_rects(disc: Disc, slot: int) -> tuple[tuple[int, int, int, int], tuple[int, int]] | None:
    """The closed-eye copy of a costume slot: source rectangle (x, y, w, h) and destination."""
    dest, size, _, closed = (b - 256 if b > 127 else b for b in disc.exe_u8(EYE_LAYOUT + 4 * slot, 4))
    if min(dest, size, closed) < 0:
        return None
    x, y = disc.exe_s16(EYE_RECTS + 4 * closed, 2)
    w, h = disc.exe_s16(EYE_SIZES + 4 * size, 2)
    return (x, y, w, h), tuple(disc.exe_s16(EYE_RECTS + 4 * dest, 2))


def convert(disc: Disc, out: Output, name: str, slot: int, kmd_id: int, arc_id: int, model: bool = True) -> None:
    """A fighting costume: its .kmd and the TIM sequence of its ARC member 0 (unless `model` is
    false: the arcade's replaces them, arcade_character.py), and its Japanese move list
    (member 4) with the glyphs it is written in (the USA release's are English, in another
    encoding: usa.py)."""
    members = arc_members(disc.bns(arc_id))
    if model:
        convert_model(disc, out, name, slot, disc.bns(kmd_id), model_textures(disc, slot, arc_id))
    if not disc.release.english:
        convert_move_list(out, name, members)


def convert_move_list(out: Output, name: str, members: list[bytes]) -> None:
    """The in-fight move list (formats/arc-archives.md, "Move-text rendering"): member 4 as it is
    (a count, then name / command strings; FighterCopyMoveText copies 0x232 bytes of it), and the
    glyph atlas, the 4-bit TIM of member 0 stored at (80, 16) (the first TIM, after Gon's CLUT-only
    one): its four bit planes are four glyph sets (CLUTs 0x7ED8 + plane show one plane each),
    written as the planes one under the other, white where the bit is set."""
    if len(members) <= MOVE_LIST_MEMBER or not members[MOVE_LIST_MEMBER]:
        return
    atlas = move_glyph_atlas(members[0], MOVE_GLYPHS_ORIGIN)
    if atlas is None:
        raise ValueError(f"{name}: no move glyph atlas at {MOVE_GLYPHS_ORIGIN} in ARC member 0")
    out.write(f"characters/{name}/move_list.bin", members[MOVE_LIST_MEMBER][:MOVE_LIST_SIZE])
    out.write(f"characters/{name}/move_glyphs.png", png_bytes(atlas))


def move_glyph_atlas(tims: bytes, origin: tuple[int, int]) -> np.ndarray | None:
    """The bit planes (vram.atlas_planes) of the CLUT-less TIM of a sequence stored at `origin`."""
    for tim in tim_sequence(tims)[0]:
        if struct.unpack_from("<I", tim, 4)[0] & 8:
            continue
        _, x, y, w, h = struct.unpack_from("<IHHHH", tim, 8)
        if (x, y) == origin:
            return atlas_planes(tim[20:20 + 2 * w * h], w, h)
    return None


def convert_model(disc: Disc, out: Output, name: str, slot: int, kmd_data: bytes, vram: Vram) -> dict:
    """Converts one model with its textures uploaded (`load_textures`); returns its summary (name,
    scale, attachments)."""
    model = kmdlib.parse(kmd_data)
    attachments = enabled_attachments(disc, slot)
    order = drawn_rows(model, attachments)
    positions = exchange_positions(model, order)
    normals = exchange_normals(model, order)
    characters = costume_characters(disc, slot)
    groups = pose_groups(kmd_data, model, has_jaw(characters))
    swapped = palette_swap(disc, characters, slot, vram)

    def local(term: Term) -> tuple[int, int, int]:
        return model.rows[term.row].verts.coords[term.index]

    def normal(term: Term) -> tuple[float, float, float]:
        return unit(model.rows[term.row].normals.coords[term.index])

    # Every face with its corners' blend terms; a face using a hand vertex belongs to that hand.
    faces = []
    for part, row_index in order:
        row = model.rows[row_index]
        slots = positions[(part, row_index)]
        colours = normals[(part, row_index)]
        for face, tex in zip(row.faces, row.tex.faces):
            material = row.tex.materials[tex.material]
            corners = []
            for c, vertex_slot in enumerate(face.verts):
                terms = blend_terms(slots[vertex_slot], 2, name)
                colour_offset = face.colors[0 if face.kind in ("ft3", "ft4") else c]
                u, v = row.tex.uvs[tex.uvs[c]]
                corners.append((material, terms, colours[colour_offset >> 2], u, v))
            faces.append((face.double_sided, face_group(corners, groups, name), corners))

    record = {
        "name": name,
        "costume_slot": slot,
        "scale_percent": model.scale_percent,
        "parts": ps1_parts(disc, slot, model, order),
    }
    write_model(out, f"characters/{name}", record, faces, local, normal, lambda part: kmdlib.PART_MATRIX[part],
                vram, material_page, closed_eyes(vram, eye_rects(disc, slot)), groups=groups,
                swap=swapped, gaze_strips=gaze_strips(disc, characters, slot, vram, swapped))
    return {"name": name, "scale_percent": model.scale_percent, "attachments": attachments}


def costume_characters(disc: Disc, slot: int) -> set[int]:
    """The character ids whose costume keys (charId · 4 + costume, tables.COSTUME_KEYS) map to the slot."""
    keys = disc.exe_u8(tables.COSTUME_KEYS, tables.COSTUME_KEY_COUNT)
    return {key // 4 for key, key_slot in enumerate(keys) if key_slot == slot}


def has_jaw(characters: set[int]) -> bool:
    """Whether a costume slot of these characters (costume_characters) belongs to one of JAW_CHARACTERS."""
    return bool(characters & set(JAW_CHARACTERS))


def palette_copy(disc: Disc, characters: set[int], slot: int) -> tuple[tuple[int, int, int, int], tuple[int, int]] | None:
    """Gon's swapped-palette copy for a costume slot of these characters, ((x, y, w, h), (dx, dy)): the
    all-black palette over his head's; None for any other character."""
    if GON not in characters:
        return None
    size, palette, _, swapped = (b - 256 if b > 127 else b for b in disc.exe_u8(PALETTE_TABLE + 4 * slot, 4))
    w, h = disc.exe_s16(EYE_SIZES + 4 * size, 2)
    x, y = disc.exe_s16(EYE_RECTS + 4 * swapped, 2)
    return (x, y, w, h), tuple(disc.exe_s16(EYE_RECTS + 4 * palette, 2))


def palette_swap(disc: Disc, characters: set[int], slot: int, vram: Vram) -> Vram | None:
    """The VRAM of a costume slot of Gon once PartSelectVertexVariant has copied the swapped palette
    over his head's (the variants PALETTE_SWAP_VARIANTS), None for any other character."""
    copy = palette_copy(disc, characters, slot)
    return None if copy is None else eye_image(vram, copy)


def gaze_strips(disc: Disc, characters: set[int], slot: int, vram: Vram, swapped: Vram | None
                ) -> tuple[gaze.Layout, dict[bool, Vram]] | None:
    """Gon's eye strips (gaze.layout) and the VRAM with them saved, for the head palette as loaded
    (False) and swapped (True, `swapped`: palette_swap); None for any other character."""
    where = gaze.layout(disc, characters, slot)
    if where is None or swapped is None:
        return None
    return where, {False: gaze.with_saves(where, vram), True: gaze.with_saves(where, swapped)}


def hand_parts(jaw: bool) -> tuple[int, int]:
    """The part each hand channel selects the variants of (FighterHandPoses)."""
    return (JAW_PART if jaw else HAND_PARTS[0], HAND_PARTS[1])


def part_rows(part: int) -> list[int]:
    """The KMD rows a draw part shows, whose vertex blocks the part's variants replace: its own
    and, for the parts with a second mesh, the next one."""
    row = kmdlib.PART_ROW[part]
    return [row, row + 1] if part in SECOND_MESH_PARTS else [row]


def pose_groups(data: bytes, model: kmdlib.Kmd, jaw: bool) -> list[VariantGroup]:
    """The faces the fight view swaps per vertex variant (`write_model`'s `groups`) of a PlayStation
    model parsed from `data`: the hand of each channel (`hand_parts`) in the rows that have variants,
    with the HAND_VARIANTS the channel value selects. A hand's group is the whole rows; the jaw
    (the head's rows 19 and 20, much of which stays still) keeps only the vertices that move, packed."""
    groups = []
    for channel, part in enumerate(hand_parts(jaw)):
        rows = [row for row in part_rows(part) if model.rows[row].variants]
        if not rows:
            continue
        blocks = {row: [variant_block(data, model, row, v).coords for v in range(HAND_VARIANTS)] for row in rows}
        if part == JAW_PART:
            groups.append(variant_group(HANDS, channel, part, blocks, {row: model.rows[row].verts.coords for row in rows}, True))
        else:
            groups.append(variant_group(HANDS, channel, part, blocks))
    return groups


def enabled_attachments(disc: Disc, slot: int) -> list[bool]:
    """Whether the costume draws attachment parts 18–21 (the table at ATTACHMENT_ENABLE)."""
    enable = disc.exe_u8(ATTACHMENT_ENABLE + ATTACHMENT_STRIDE * slot + FIRST_ATTACHMENT_PART, 4)
    return [bool(b) for b in enable]


def unit(v: tuple[int, int, int]) -> tuple[float, float, float]:
    x, y, z = v
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    return x / length, y / length, z / length


def blend_terms(blend: dict, most: int, name: str) -> tuple[tuple[Term, float], ...]:
    """A vertex slot's blend as at most `most` (term, weight) pairs in a fixed order; the
    weights must add up to one (4.12 weights: within one unit per term)."""
    terms = tuple(sorted(blend.items(), key=lambda kv: (kv[0].part, kv[0].row, kv[0].index)))
    if not 1 <= len(terms) <= most or abs(sum(w for _, w in terms) - 1.0) > len(terms) / 4096:
        raise ValueError(f"{name}: unexpected seam blend {terms}")
    return terms


@dataclass(frozen=True)
class VariantGroup:
    """Faces that follow a pose value of the fight view (a hand's vertex variant, True Ogre's wing
    sequence): every face with a vertex in `moving` is stored once per variant and the remake swaps
    them. `key` is the model.json list the group goes to (HANDS, WINGS), `channel` the index of its
    value in the view's list, `part` the part (a row for wings) it belongs to, and
    `coords[row][variant][vertex]` the part-local position each variant gives the group's rows.

    `select[v]` is the entry of `coords` the pose value's variant `v` shows (the identity, unless the
    group is `packed`). A packed group, for the arcade's many hand variants, keeps only the distinct
    variants and is written as one set of surfaces and the moving vertices' positions per variant
    (`write_model`), not as a surface set per variant."""
    key: str
    channel: int
    part: int
    coords: dict[int, list[list[tuple[int, int, int]]]]
    moving: frozenset[tuple[int, int]]
    select: tuple[int, ...]
    packed: bool = False

    @property
    def count(self) -> int:
        """The variants a pose value selects."""
        return len(self.select)

    @property
    def distinct(self) -> int:
        """The variants that differ in the moving vertices (the entries of `coords`)."""
        return len(next(iter(self.coords.values())))


def variant_group(key: str, channel: int, part: int, coords: dict[int, list[list[tuple[int, int, int]]]],
                  base: dict[int, list[tuple[int, int, int]]] | None = None, packed: bool = False) -> VariantGroup:
    """A group over `coords`' rows. Without `base` every vertex of the rows is moving; with it only
    the vertices that some variant puts elsewhere than the row's base block (a wing's row also
    holds the vertices that stay). `packed` keeps one entry per distinct variant (of the moving
    vertices) and `select` maps every variant to its entry."""
    if len({len(variants) for variants in coords.values()}) != 1:
        raise ValueError(f"{key} {channel}: the rows have different numbers of variants")
    count = len(next(iter(coords.values())))
    moving = frozenset((row, i) for row, variants in coords.items() for i in range(len(variants[0]))
                       if base is None or any(v[i] != base[row][i] for v in variants))
    if not packed:
        return VariantGroup(key, channel, part, coords, moving, tuple(range(count)))
    entries: dict[tuple, int] = {}
    select = tuple(entries.setdefault(tuple(tuple(variants[v][i] for i in sorted(i for r, i in moving if r == row))
                                            for row, variants in coords.items()), len(entries))
                   for v in range(count))
    first = [select.index(k) for k in range(len(entries))]
    kept = {row: [variants[v] for v in first] for row, variants in coords.items()}
    return VariantGroup(key, channel, part, kept, moving, select, True)


def face_group(corners: list, groups: list[VariantGroup], name: str) -> int:
    """The index of the group a face belongs to (one of its vertices is a moving one), else −1."""
    hit = {g for g, group in enumerate(groups) for _, terms, _, _, _ in corners for t, _ in terms
           if (t.row, t.index) in group.moving}
    if len(hit) > 1:
        raise ValueError(f"{name}: a face uses the vertices of more than one variant group")
    return hit.pop() if hit else -1


def three_terms(terms: tuple) -> tuple[tuple[Term, float], ...]:
    """A corner's terms as exactly three (term, weight) pairs: missing ones repeat the first
    term with weight 0 (the mesh blends `a` with `b` by wb and with `c` by wc)."""
    first = (terms[0][0], 0.0)
    return (terms[0], *terms[1:], first, first)[:3]


def eye_image(vram: Vram, copy: tuple) -> Vram:
    """The VRAM after an eye shape's MoveImage, copy ((x, y, w, h), (dx, dy)): a rectangle over the eyes."""
    shown = vram.copy()
    (x, y, w, h), (dx, dy) = copy
    shown.move_image(x, y, w, h, dx, dy)
    return shown


def closed_eyes(vram: Vram, eyes: tuple | None) -> Vram | None:
    """The VRAM after the blink's MoveImage of the closed-eye rectangle, or None."""
    return None if eyes is None else eye_image(vram, eyes)


def ps1_parts(disc: Disc, slot: int, model: kmdlib.Kmd, order: list[tuple[int, int]]) -> list[dict]:
    """The skeleton the fight code builds from the PlayStation model (FighterSetupParts): every
    draw part's row, parent, joint offset and matrix slot, and the attachments' rest angles and
    dynamics records."""
    parts = []
    for part, row_index in enumerate(kmdlib.PART_ROW):
        row = model.rows[row_index]
        entry = {
            "row": row_index,
            "parent": row.parent,
            "offset": list(row.offset),
            "joint": kmdlib.PART_MATRIX[part],
            "drawn": any(p == part for p, _ in order),
        }
        if part >= FIRST_ATTACHMENT_PART:
            entry["rest"] = [struct.unpack("<h", struct.pack("<H", row.words[w] & 0xFFFF))[0] for w in REST_ANGLE_WORDS]
            pointer = disc.exe_u32(ATTACHMENT_PARAMS + 4 * (6 * slot + part - FIRST_ATTACHMENT_PART), 1)[0]
            entry["dynamics"] = None if pointer == ATTACHMENT_STATIC else disc.exe_s16(pointer, ATTACHMENT_RECORD)
        parts.append(entry)
    return parts


def write_model(out: Output, base: str, record: dict, faces: list, local: Callable, normal: Callable,
                joint_of: Callable[[int], int], vram: Vram, page_of: Callable, closed: Vram | None,
                sources: bool = True, eyes: dict[int, Vram] | None = None,
                groups: Sequence[VariantGroup] = (), swap: Vram | None = None,
                gaze_strips: tuple[gaze.Layout, dict[bool, Vram]] | None = None) -> None:
    """Writes a costume's mesh, texture atlas (and closed-eye atlas, the atlases of the eye
    shapes `eyes`, the atlas of Gon's swapped head palette `swap` and the patches of his eyes'
    look directions `gaze_strips`) and model.json (`record` plus the surfaces).

    `faces` are (double sided, index in `groups` or −1, corners); a corner is (material, terms,
    normal term, u, v) with terms ((term, weight), …), at most three. `local(term)` is a term's
    part-local position in its base block (a group's faces take the rows' positions from the
    group, once per variant), `normal(term)` its unit normal, `joint_of` maps a term's part to its
    joint, `page_of(material)` gives the material's page and CLUT."""
    used: dict[object, list[tuple[int, int]]] = {}
    for _, _, corners in faces:
        for material, _, _, u, v in corners:
            used.setdefault(material, []).append((u, v))
    smooth, keys = smooth_normals(faces, local, normal)
    curved_edges = smooth_edges(faces, keys, smooth)

    def edge_curves(face_index: int, corner_count: int, i: int, j: int) -> bool:
        """Whether the edge from corner i to corner j may bulge (a quad's diagonal always may)."""
        if faces[face_index][1] >= 0:
            return False
        if corner_count == 4 and {i, j} == {1, 2}:
            return True
        return frozenset((keys[(face_index, i)], keys[(face_index, j)])) in curved_edges

    pages = {m: vram.page_rgba(*page_of(m)) for m in used}
    packed = atlas.build(pages, used)
    out.write(f"{base}/texture.png", png_bytes(packed.pixels))
    if sources:
        atlas.record_sources(out, f"{base}/texture.png", packed, vram, page_of)
    summary = {"texture": "texture.png"}

    def write_variant(name: str, shown: Vram) -> str:
        """The atlas after the eyes changed to `shown`'s: `name`.png beside texture.png."""
        pixels = packed.repaint({m: shown.page_rgba(*page_of(m)) for m in used})
        out.write(f"{base}/{name}.png", png_bytes(pixels))
        if sources:
            atlas.record_sources(out, f"{base}/{name}.png", packed, shown, page_of)
        return f"{name}.png"

    if closed is not None:
        summary["texture_closed"] = write_variant("texture_closed", closed)
    if gaze_strips is not None:
        summary["gaze"] = gaze.write(out, base, *gaze_strips, lambda shown: packed.repaint(
            {m: shown.page_rgba(*page_of(m)) for m in used}), packed.pixels.shape[1::-1])
    if swap is not None:
        summary["palette_swap"] = {"variants": list(PALETTE_SWAP_VARIANTS), "texture": write_variant(PALETTE_SWAP, swap)}
    if eyes:
        summary["eye_textures"] = {str(shape): write_variant(f"{EYE_TEXTURE}{shape}", shown)
                                   for shape, shown in sorted(eyes.items())}

    mesh = bytearray()

    def emit(selected: list, group: VariantGroup | None = None, variant: int = 0,
             refs: list[int] | None = None, slot_of: dict[tuple[int, int], int] | None = None) -> list[dict]:
        """Appends the corners of `selected` faces, split by sidedness, with the positions of
        `group`'s variant; returns their surfaces. With `refs` every corner also appends the
        `slot_of` entries (−1: not in it) of its three positions' vertices."""
        nonlocal mesh

        def position(term: Term) -> tuple[int, int, int]:
            return group.coords[term.row][variant][term.index] if group and term.row in group.coords else local(term)

        surfaces = []
        for double_sided in (False, True):
            floats: list[float] = []
            count = 0
            for face_index, (sided, _, corners) in selected:
                if sided != double_sided:
                    continue
                tris = [(0, 1, 2)] if len(corners) == 3 else QUAD_TRIANGLES
                for tri in tris:
                    for k, i in enumerate(tri):
                        material, terms, nt, u, v = corners[i]
                        (ta, _), (tb, wb), (tc, wc) = three_terms(terms)
                        if refs is not None:
                            refs.extend(slot_of.get((t.row, t.index), -1) for t in (ta, tb, tc))
                        s_own, _, s_other, part_other = smooth[(face_index, i)]
                        curves = edge_curves(face_index, len(corners), i, tri[(k + 1) % 3])
                        floats.extend([*position(ta), *position(tb), wb, *normal(nt)])
                        floats.extend(packed.uv(material, u, v))
                        floats.extend((joint_of(ta.part), joint_of(tb.part), joint_of(nt.part)))
                        floats.extend((*s_own, *s_other, joint_of(part_other), 1.0 if curves else 0.0))
                        floats.extend((*position(tc), wc, joint_of(tc.part)))
                        count += 1
            if count:
                surfaces.append({"double_sided": double_sided, "offset": len(mesh), "vertex_count": count})
                mesh += struct.pack(f"<{len(floats)}f", *floats)
        return surfaces

    surface_list = emit([(k, f) for k, f in enumerate(faces) if f[1] < 0])
    lists: dict[str, list] = {HANDS: [], WINGS: []}
    for g, group in enumerate(groups):
        selected = [(k, f) for k, f in enumerate(faces) if f[1] == g]
        if not selected:
            continue
        entry = {"channel": group.channel, "part": group.part}
        if group.packed:
            # One set of surfaces (the first variant's), and the moving vertices' part-local
            # positions of every distinct variant: the remake patches the corners' positions
            # (POSITION_FLOATS) of the surfaces with the vertices `refs` gives per corner.
            keys = sorted(group.moving)
            refs: list[int] = []
            entry["variants"] = [emit(selected, group, 0, refs, {key: k for k, key in enumerate(keys)})]
            table = [float(c) for e in range(group.distinct) for row, i in keys for c in group.coords[row][e][i]]
            entry["select"] = list(group.select)
            entry["poses"] = {"count": group.distinct, "vertices": len(keys), "table": len(mesh), "refs": len(mesh) + 4 * len(table)}
            mesh += struct.pack(f"<{len(table)}f", *table) + struct.pack(f"<{len(refs)}i", *refs)
        else:
            entry["variants"] = [emit(selected, group, v) for v in range(group.count)]
        lists[group.key].append(entry)
    out.write(f"{base}/mesh.bin.gz", gzipped(bytes(mesh)))
    out.write_json(f"{base}/model.json", {
        **record,
        "vertex_floats": VERTEX_FLOATS,
        "smooth_crease_cos": math.cos(math.radians(SMOOTH_CREASE_DEGREES)),
        **summary,
        "surfaces": surface_list,
        **lists,
    })


def smooth_normals(faces: list, position: Callable[[Term], tuple[int, int, int]],
                   normal: Callable[[Term], tuple[float, float, float]]) -> tuple[dict, dict]:
    """The smooth normal of every face corner, (face, corner) → (s_own, part_own, s_other,
    part_other), and the point every corner is at, (face, corner) → key.

    The game lights every face corner with a normal of its own, so the faces meeting at a point
    often disagree and the model looks faceted. The normals live in their parts' joints, which
    turn apart in every pose, so they are only compared within one joint here: the corners at a
    point (the same part-local positions and seam weights) whose normals share a joint are grouped
    by angle, transitively (two normals within SMOOTH_CREASE_DEGREES of each other are in one
    group), and `s_own` is the sum of the corner's group, in its own normal's joint. `s_other` is
    the sum of every normal at the point in one other joint (the seam's other part, or a
    neighbour's); the shader adds it after skinning only while the two halves lie within the
    crease angle in the current pose (fighter_skin.gdshaderinc smooth_normal). Normals of a third
    joint are left out."""
    crease = math.cos(math.radians(SMOOTH_CREASE_DEGREES))
    keys = {}
    at: dict[tuple, list[tuple[int, int]]] = {}
    for face_index, (_, _, corners) in enumerate(faces):
        for c, (_, terms, _, _, _) in enumerate(corners):
            if len(terms) == 1:
                key = ((terms[0][0].part, *position(terms[0][0])),)
            else:
                key = tuple(sorted((t.part, *position(t), round(w, 6)) for t, w in terms))
            keys[(face_index, c)] = key
            at.setdefault(key, []).append((face_index, c))

    def corner(fc: tuple[int, int]) -> tuple:
        return faces[fc[0]][2][fc[1]]

    result = {}
    for point in at.values():
        normals = [normal(corner(fc)[2]) for fc in point]
        parts = [corner(fc)[2].part for fc in point]
        # Groups within each joint: the transitive closure of "within the crease angle".
        group = list(range(len(point)))

        def root(i: int) -> int:
            while group[i] != i:
                group[i] = group[group[i]]
                i = group[i]
            return i

        for i in range(len(point)):
            for j in range(i + 1, len(point)):
                if parts[i] == parts[j] and sum(x * y for x, y in zip(normals[i], normals[j])) >= crease:
                    group[root(i)] = root(j)
        group_sums: dict[int, tuple[float, float, float]] = {}
        part_sums: dict[int, tuple[float, float, float]] = {}
        for i, n in enumerate(normals):
            r = root(i)
            group_sums[r] = tuple(x + y for x, y in zip(group_sums.get(r, (0.0, 0.0, 0.0)), n))
            part_sums[parts[i]] = tuple(x + y for x, y in zip(part_sums.get(parts[i], (0.0, 0.0, 0.0)), n))
        for i, fc in enumerate(point):
            _, terms, nt, _, _ = corner(fc)
            seam = [t.part for t, _ in terms if t.part != nt.part]
            others = seam or [p for p in part_sums if p != nt.part]
            other = others[0] if others else nt.part
            s_other = part_sums.get(other, (0.0, 0.0, 0.0)) if other != nt.part else (0.0, 0.0, 0.0)
            result[fc] = (group_sums[root(i)], nt.part, s_other, other)
    return result, keys


def face_edges(corner_count: int) -> tuple[tuple[int, int], ...]:
    """The outline of a triangle or of a quad split into QUAD_TRIANGLES."""
    return ((0, 1), (1, 2), (2, 0)) if corner_count == 3 else ((0, 1), (1, 3), (3, 2), (2, 0))


def smooth_edges(faces: list, keys: dict, smooth: dict) -> set[frozenset]:
    """The edges (pairs of point keys) the curved surfaces may bulge along: shared by two faces
    or more that all give both ends the same smooth normal. Every other edge stays straight, so
    the faces on both sides of a crease or an open border still meet (fighter_skin.gdshaderinc).
    Two corners with the same halves get the same normal in every pose (the shader's test of the
    halves is symmetric). Nor does an edge of a variant group's face (a hand's or a wing's) bulge: its
    vertex variants bend the fingers or the wing while the normals stay the base block's, so its
    patches would fold, and the faces next to it must keep the edge straight too."""
    def signature(face_index: int, c: int) -> frozenset:
        s_own, part_own, s_other, part_other = smooth[(face_index, c)]
        return frozenset({(part_own, tuple(round(x, 4) for x in s_own)),
                          (part_other, tuple(round(x, 4) for x in s_other))})

    ends: dict[frozenset, set] = {}
    uses: dict[frozenset, int] = {}
    group_edges: set[frozenset] = set()
    for face_index, (_, group, corners) in enumerate(faces):
        for i, j in face_edges(len(corners)):
            edge = frozenset((keys[(face_index, i)], keys[(face_index, j)]))
            if group >= 0:
                group_edges.add(edge)
            ka = keys[(face_index, i)]
            pair = frozenset(((ka, signature(face_index, i)), (keys[(face_index, j)], signature(face_index, j))))
            ends.setdefault(edge, set()).add(pair)
            uses[edge] = uses.get(edge, 0) + 1
    return {e for e, pairs in ends.items() if uses[e] >= 2 and len(pairs) == 1 and e not in group_edges}


def variant_block(data: bytes, model: kmdlib.Kmd, row: int, variant: int) -> kmdlib.VertexBlock:
    """Vertex variant `variant` of a row (PartSelectVertexVariant), parsed from the model file."""
    start = model.rows[row].variants[variant]
    base = model.rows[row].verts
    block = kmdlib.parse_vertex_block(data, start, len(data), normals=False)
    if (block.lead, block.import_scratch, block.import_global, len(block.coords), block.post) != \
            (base.lead, base.import_scratch, base.import_global, len(base.coords), base.post):
        raise ValueError(f"row {row} variant {variant} changes the exchange lists")
    return block
