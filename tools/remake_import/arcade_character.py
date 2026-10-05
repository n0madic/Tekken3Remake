"""The arcade's character models (MAME's tekken3 set) → the remake's skinned mesh format.

The arcade has costume slots 0–40 (docs/research/arcade/README.md#character-models):
the same texture artwork as the PlayStation's, about 15 % more triangles and seams weighed
across up to three joints. They replace the PlayStation's mesh and texture atlas of those slots
(character.write_model); `model.json` keeps the PlayStation's skeleton and attachment records,
which the fight code builds its joints from (character.ps1_parts), so gameplay is unchanged.

As the arcade loads a model, the vertices and normals of its swinging attachments are turned by
angles of their enable value (arcade_kmd.turn_attachments, FUN_80197578); so are they here. The
feet's vertices and normals are turned into the PlayStation's foot frames
(arcade_kmd.playstation_frame): the arcade's foot joints turn 90° about y against them.

The arcade's own attachments (rows 18–23: hair, sashes, tails, skirts) hang from joints
ATTACHMENT_JOINT + i, which the remake moves with the arcade's attachment dynamics
(FUN_8019b6d8); `arcade_attachments` in `model.json` lists them with their parent joint, offset,
rest angles and dynamics record.

Slots kept from the PlayStation (PLAYSTATION_SLOTS): Mokujin's, whose stick the arcade model
does not have.
"""

from __future__ import annotations

import struct
from collections.abc import Callable

import arcade
import arcade_eyes
import arcade_kmd
import character
import kmd as kmdlib
from common import Disc, Output, log
from vram import Vram, tim_sequence

SLOTS = 41                              # costume slots 0–40 exist in the arcade set
PLAYSTATION_SLOTS = (30, 31)            # Mokujin: the stick (attachment part 18) is PlayStation-only
MODEL_CATEGORY, PACKED_CATEGORY = 19, 20
PACKED_EMPTY = 4                        # bytes of an empty category 20 entry
ATTACHMENT_JOINT = 22                   # the joint of attachment row 18 (after the fight's 22)
RECORD_WORDS = 16                       # s16 read from a dynamics record (FUN_8019b6d8 and helpers)
# FUN_8019b6d8's tables: the yaw and pitch's axis records (six s8 each: atan2 signs and angle
# scales) up to the enable table, and the clamps (max, min) of costume slots 0x1A and 0x24.
AXIS_RECORDS = 0x801FD170
AXIS_RECORD = 6
AXIS_RECORD_COUNT = (arcade_kmd.ATTACHMENT_ENABLE + arcade_kmd.FIRST_ATTACHMENT - AXIS_RECORDS) // AXIS_RECORD
CLAMPS = 0x801FD2F0
CLAMP_WORDS = 4
TABLES_FILE = "characters/arcade_attachments.json"
# True Ogre's wings are two groups of vertex variants, each with the view's value that selects
# them (FUN_80194458, arcade/README.md#true-ogres-wings): row 1 takes the wing sequence's variant
# (the tables at 0x801FCF30 and 0x801FCF44 give 0–39), rows 18 and 19 (the tail) the level
# channel's value >> 4 (0–0x100 give 0–16). Only the vertices a variant moves are in a group.
WING_GROUPS = (((1,), 40), ((18, 19), 17))
# The hand channels' variants (FUN_80194458): channel 0 selects the left hand's row 10, channel 1
# the right hand's row 6; Kuma's and Panda's channel 0 selects the jaw (the head's row 2) instead.
# The variant numbers are the arcade's own, 0–40: `value >> 4` over a channel value up to 0x200
# (a blend from the open hand to the fist), `value − 0x1E0` above (shapes), so a group keeps them
# all, packed (character.VariantGroup).
JAW_SLOTS = (22, 23)
JAW_ROW = 2
MODEL_FILES = ("model.json", "mesh.bin.gz", "texture.png")   # character.write_model's, and its eye atlases


def costume(arc: arcade.ArcadeSet, slot: int) -> tuple[bytes, list[bytes]]:
    """FUN_80197b38 / FUN_80197e88: the model from category 20 when it has one, else 19; the
    texture blocks of category 19, then of category 20 (uploaded on top)."""
    packed = arc.category(PACKED_CATEGORY)
    plain = arc.category(MODEL_CATEGORY)
    entry = packed[2 * slot + 1]
    model = arcade.decompress(entry)[0] if len(entry) > PACKED_EMPTY else plain[2 * slot + 1]
    textures = []
    if 2 * slot < len(plain):
        textures.append(plain[2 * slot])
    if len(packed[2 * slot]) > PACKED_EMPTY:
        textures.append(arcade.decompress(packed[2 * slot])[0])
    return model, textures


def load_textures(blocks: list[bytes]) -> Vram:
    """FUN_80197e88 for player 1: each TIM's image at its rectangle plus TEXTURE_ORIGIN, its
    CLUT plus CLUT_ORIGIN, in the System 12's 1024-row VRAM."""
    vram = Vram(arcade_kmd.VRAM_ROWS)
    for block in blocks:
        for tim in tim_sequence(block)[0]:
            vram.upload_tim(tim, *arcade_kmd.TEXTURE_ORIGIN, *arcade_kmd.CLUT_ORIGIN)
    return vram


def material_page(material: tuple[int, int]) -> tuple[int, int, int, int, int]:
    """(page x, page y, depth, CLUT x, CLUT y) of a (tpage, clut) pair."""
    tpage, clut = material
    depth = 8 if (tpage >> 7) & 3 else 4
    return (tpage & 0xF) * 64, ((tpage >> 4) & 1) * 256, depth, (clut & 0x3F) * 16, (clut >> 6) & 0x3FF


def is_model_file(rel: str) -> bool:
    """Whether `rel` (in a costume's folder) is one of character.write_model's files."""
    return rel in MODEL_FILES or rel.startswith(character.EYE_TEXTURE)


def joint_of_row(row: int) -> int:
    return row if row < arcade_kmd.JOINTS else ATTACHMENT_JOINT + row - arcade_kmd.FIRST_ATTACHMENT


def write_tables(out: Output, arc: arcade.ArcadeSet) -> None:
    """The attachment dynamics' axis records and clamps (remake: ArcadeAttachments)."""
    out.write_json(TABLES_FILE, {
        "limits": [list(arc.prog_values("<6b", AXIS_RECORDS + AXIS_RECORD * k)) for k in range(AXIS_RECORD_COUNT)],
        "clamps": list(arc.prog_values(f"<{CLAMP_WORDS}h", CLAMPS)),
    })


def replaces(slot: int) -> bool:
    """Whether the arcade's model replaces the PlayStation's in costume `slot`."""
    return slot < SLOTS and slot not in PLAYSTATION_SLOTS


def convert_or_keep(disc: Disc, out: Output, arc: arcade.ArcadeSet, name: str, slot: int, kmd_id: int,
                    arc_id: int) -> None:
    """`convert`, or the PlayStation's model with a logged reason if the arcade's cannot be used."""
    try:
        convert(disc, out, arc, name, slot, kmd_id)
    except (arcade.ArcadeError, arcade_kmd.ArcadeKmdError, struct.error, ValueError) as e:
        log.error("arcade: costume slot %d: %s; the PlayStation's model is kept", slot, e)
        # Whatever the failed conversion wrote goes with the run's prune unless written again.
        base = f"characters/{name}/"
        out.files -= {f for f in out.files if f.startswith(base) and is_model_file(f[len(base):])}
        character.convert_model(disc, out, name, slot, disc.bns(kmd_id), character.model_textures(disc, slot, arc_id))


def convert(disc: Disc, out: Output, arc: arcade.ArcadeSet, name: str, slot: int, kmd_id: int) -> None:
    """Writes costume `slot`'s arcade mesh and atlas with the PlayStation's skeleton."""
    data, blocks = costume(arc, slot)
    enable = arc.prog(arcade_kmd.ATTACHMENT_ENABLE + arcade_kmd.ATTACHMENTS * slot, arcade_kmd.ROWS)
    sine = list(arc.prog_table(f"<{arcade_kmd.SINE_ENTRIES}h", arcade_kmd.SINE))
    turns = arcade_kmd.load_turns(arc.prog_values, slot, enable)
    model, drawn, faces, local, normal, groups = model_faces(data, enable, turns, sine, name, slot)
    vram = load_textures(blocks)
    ps1 = kmdlib.parse(disc.bns(kmd_id))
    order = character.drawn_rows(ps1, character.enabled_attachments(disc, slot))
    record = {
        "name": name,
        "costume_slot": slot,
        "scale_percent": ps1.scale_percent,
        "source": "arcade",
        "parts": character.ps1_parts(disc, slot, ps1, order),
        "arcade_attachments": attachments(arc, model, slot, drawn),
    }
    eyes = arcade_eyes.record(arc, slot)
    if eyes is not None:
        record["arcade_eyes"] = eyes
    character.write_model(out, f"characters/{name}", record, faces, local, normal, lambda joint: joint,
                          vram, material_page, None, sources=False, eyes=arcade_eyes.images(arc, slot, vram),
                          groups=groups)


def model_faces(data: bytes, enable: bytes, turns: dict[int, tuple[int, int, int]], sine: list[int],
                name: str, slot: int) -> tuple[arcade_kmd.Model, set[int], list, Callable, Callable,
                                                list[character.VariantGroup]]:
    """A model's drawn rows and its faces for character.write_model, with `local` and `normal`
    and the variant groups the faces belong to (`pose_groups`): the swinging attachments turned
    as the model loads (`turns`, arcade_kmd.load_turns) and the feet in the PlayStation's frames."""
    model = arcade_kmd.parse(data)
    arcade_kmd.turn_attachments(model, turns, sine)
    drawn = {row.index for row in model.rows
             if row.verts is not None and (row.index < arcade_kmd.JOINTS or enable[row.index])}
    positions = arcade_kmd.slot_weights(model, drawn)
    colours = arcade_kmd.colour_terms(model, drawn)
    groups = pose_groups(data, model, slot)

    def term(key: tuple[int, int]) -> character.Term:
        row, index = key
        return character.Term(joint_of_row(row), row, index)

    def local(t: character.Term) -> tuple[int, int, int]:
        return arcade_kmd.playstation_frame(t.row, model.rows[t.row].verts.coords[t.index])

    def normal(t: character.Term) -> tuple[float, float, float]:
        return character.unit(arcade_kmd.playstation_frame(t.row, model.rows[t.row].normals.coords[t.index]))

    faces = []
    for row in model.rows:
        if row.index not in drawn:
            continue
        for face in row.faces:
            corners = []
            for c, vertex_slot in enumerate(face.verts):
                blend = {term(k): w for k, w in positions[row.index][vertex_slot].items()}
                terms = character.blend_terms(blend, 3, name)
                lit = colours[row.index][face.colours[c if len(face.colours) > 1 else 0]]
                normal_key = max(lit.items(), key=lambda kv: (kv[1], -kv[0][0], -kv[0][1]))[0]
                u, v = face.uvs[c]
                corners.append(((face.tpage, face.clut), terms, term(normal_key), u, v))
            faces.append((face.double_sided, character.face_group(corners, groups, name), corners))
    return model, drawn, faces, local, normal, groups


def pose_groups(data: bytes, model: arcade_kmd.Model, slot: int) -> list[character.VariantGroup]:
    """The faces the fight view swaps per vertex variant (character.write_model's `groups`) of a
    model of costume `slot` parsed from `data` and turned as it loads: the hands (or the jaw) with
    all the arcade's variants (`hand_rows`), then True Ogre's wings and tail (WING_GROUPS) where the
    model has their variants."""
    def group(key: str, channel: int, part: int, rows: list[int], count: int, packed: bool) -> character.VariantGroup:
        variants = {row: [[arcade_kmd.playstation_frame(row, v) for v in arcade_kmd.variant(data, model, row, k).coords]
                          for k in range(count)] for row in rows}
        base = {row: [arcade_kmd.playstation_frame(row, v) for v in model.rows[row].verts.coords] for row in rows}
        return character.variant_group(key, channel, part, variants, base, packed)

    groups = [group(character.HANDS, channel, part, [row], arcade_kmd.VARIANTS, True)
              for channel, (row, part) in enumerate(hand_rows(slot)) if model.rows[row].variants]
    for channel, (rows, count) in enumerate(WING_GROUPS):
        rows = [row for row in rows if model.rows[row].variants]
        if rows:
            groups.append(group(character.WINGS, channel, rows[0], rows, count, False))
    return groups


def hand_rows(slot: int) -> list[tuple[int, int]]:
    """The (row, part) each hand channel selects the variant of (FUN_80194458): channel 0 the left
    hand's row 10, channel 1 the right hand's row 6; for Kuma and Panda channel 0 the head's row 2
    (the jaw, as on the PlayStation: 3dmk-models.md#vertex-variants). The part is the PlayStation's."""
    rows = [(kmdlib.PART_MATRIX[part], part) for part in character.HAND_PARTS]
    if slot in JAW_SLOTS:
        rows[0] = (JAW_ROW, character.JAW_PART)
    return rows


def attachments(arc: arcade.ArcadeSet, model: arcade_kmd.Model, slot: int, drawn: set[int]) -> list[dict]:
    """The drawn attachment rows: joint, parent joint, offset, rest angles, whether the record is
    the static one, and the record (FUN_8019b634, FUN_8019b6d8)."""
    out = []
    for i in range(arcade_kmd.ATTACHMENTS):
        row = model.rows[arcade_kmd.FIRST_ATTACHMENT + i]
        if row.index not in drawn or not row.verts.coords:
            continue
        pointer = arc.prog_values("<I", arcade_kmd.ATTACHMENT_RECORDS + 4 * (arcade_kmd.ATTACHMENTS * slot + i))[0]
        out.append({
            "joint": joint_of_row(row.index),
            "parent": joint_of_row(row.parent),
            "offset": list(row.offset),
            "rest": list(row.rest),
            "static": pointer == arcade_kmd.STATIC_RECORD,
            "record": list(arc.prog_values(f"<{RECORD_WORDS}h", pointer)),
        })
    return out
