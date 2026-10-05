"""The arcade character models (arcade_kmd, arcade_character.py) on a synthetic model: no game data."""

from __future__ import annotations

import gzip
import json
import struct
import tempfile
import unittest
from pathlib import Path

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_character
import arcade_kmd
import character
from common import Output
from vram import Vram

ONE = arcade_kmd.WEIGHT_ONE
HALF = ONE // 2
# A sine table: sin of index i (4096 per turn) for the angles the tests use, cosines 1024 later.
SINE = [0] * arcade_kmd.SINE_ENTRIES
SINE[0], SINE[1024], SINE[2048], SINE[3072], SINE[4096] = 0, 4096, 0, -4096, 0


def _list(words: list[int]) -> bytes:
    return struct.pack(f"<I{len(words)}I", len(words), *words)


def _vertices(coords: list[tuple[int, int, int]], imports=(), exports=(), blends=()) -> bytes:
    out = struct.pack("<I", len(coords)) + b"".join(struct.pack("<3hh", *c, 0) for c in coords)
    return out + _list(list(imports)) + _list(list(exports)) + _list(list(blends))


def _model(rows: dict[int, tuple[bytes, bytes, list[tuple[int, list[int], list[int]]], int]],
           variants: dict[int, list[bytes | None]] | None = None) -> bytes:
    """A 24-row model; `rows`: index → (vertex block, normal block, faces (group, words, texture
    words), parent). Blocks follow the row table in row order. `variants`: row → its 41 variant
    blocks (None: the base block), which follow the row's blocks with their pointer table."""
    header = struct.pack("<II4sI", arcade_kmd.ROWS, 100, b"3DMK", 0)
    table_end = arcade_kmd.HEADER_BYTES + arcade_kmd.ROW_BYTES * arcade_kmd.ROWS
    blobs = bytearray()
    table = bytearray()
    for k in range(arcade_kmd.ROWS):
        words = [0] * 14
        words[8] = 0xFFFFFFFF
        if k in rows:
            verts, normals, faces, parent = rows[k]
            groups = [[f for f in faces if f[0] == g] for g in range(4)]
            face_block = b"".join(struct.pack("<I", len(g)) + b"".join(struct.pack(f"<{len(f[1])}I", *f[1]) for f in g)
                                  for g in groups)
            tex_block = b"".join(struct.pack("<I", len(g)) + b"".join(struct.pack("<3I", *f[2]) for f in g) for g in groups)
            at = table_end + len(blobs)
            words[0] = at
            words[2] = at + len(verts)
            words[3] = words[2] + len(normals)
            words[4] = words[3] + len(face_block)
            words[8] = parent
            words[12] = 1
            blobs += verts + normals + face_block + tex_block
            if variants and k in variants:
                pointers = []
                for block in variants[k]:
                    pointers.append(at if block is None else table_end + len(blobs))
                    blobs += block or b""
                words[1] = table_end + len(blobs)
                blobs += struct.pack(f"<{arcade_kmd.VARIANTS}I", *pointers)
        table += struct.pack("<14I", *(w & 0xFFFFFFFF for w in words))
    return header + bytes(table) + bytes(blobs)


class ArcadeModelTest(unittest.TestCase):
    def setUp(self) -> None:
        # Row 1 exports its vertex 0 at half weight to global slot 3; row 2 blends its vertex 0 in
        # (the other half), then a quad of row 2 uses its own vertices and an import of slot 3.
        self.data = _model({
            1: (_vertices([(10, 0, 0)], exports=[3 | HALF << 16]), _vertices([(0, 4096, 0)]), [], 0),
            2: (_vertices([(30, 0, 0), (0, 0, 7)], blends=[3 | HALF << 16]),
                _vertices([(4096, 0, 0)], exports=[5 | ONE << 16]),
                [(1, [0 | 1 << 8 | 2 << 16 | 1 << 24, 0x8000], [7 << 16 | 0x0201, 0x80 << 16 | 0x0403, 0x0605 | 0x0807 << 16])], 1),
            3: (_vertices([(0, 0, 1)], imports=[3]), _vertices([(0, 0, 4096)], imports=[5]), [], 2),
        })

    def test_parse_reads_rows_faces_and_textures(self) -> None:
        model = arcade_kmd.parse(self.data)
        row = model.rows[2]
        self.assertEqual(row.verts.coords, [(30, 0, 0), (0, 0, 7)])
        self.assertEqual(row.parent, 1)
        face = row.faces[0]
        self.assertEqual((face.group, face.verts, face.double_sided), (1, (0, 1, 2, 1), True))
        self.assertEqual(face.clut, arcade_kmd.CLUT_BASE + 7)
        self.assertEqual(face.tpage, arcade_kmd.TPAGE_BASE + 0x80)
        self.assertEqual(face.uvs, ((1, 2), (3, 4), (5, 6), (7, 8)))

    def test_seam_weights(self) -> None:
        model = arcade_kmd.parse(self.data)
        weights = arcade_kmd.slot_weights(model, {1, 2, 3})
        self.assertEqual(weights[2][0], {(2, 0): 0.5, (1, 0): 0.5}, "the blend adds row 1's half")
        self.assertEqual(weights[3][1], {(2, 0): 0.5, (1, 0): 0.5}, "and is stored back for the import")
        terms = character.blend_terms({character.Term(2, 2, 0): 0.5, character.Term(1, 1, 0): 0.5}, 3, "test")
        self.assertEqual([t.part for t, _ in terms], [1, 2], "terms in joint order")
        (a, _), (b, wb), (c, wc) = character.three_terms(terms)
        self.assertEqual((a.part, b.part, wb, c.part, wc), (1, 2, 0.5, 1, 0.0), "a missing third term weighs 0")

    def test_imports_need_an_earlier_export(self) -> None:
        model = arcade_kmd.parse(self.data)
        with self.assertRaises(arcade_kmd.ArcadeKmdError):
            arcade_kmd.slot_weights(model, {3})

    def test_colours_copy_and_import(self) -> None:
        model = arcade_kmd.parse(self.data)
        colours = arcade_kmd.colour_terms(model, {1, 2, 3})
        self.assertEqual(colours[3][1], {(2, 0): 1.0}, "a WEIGHT_ONE export copies the colour")

    def test_load_turn_and_feet(self) -> None:
        model = arcade_kmd.parse(self.data)
        half_turn = arcade_kmd.euler(0, 0x8000, 0, SINE)
        self.assertEqual(half_turn, [-4096, 0, 0, 0, 4096, 0, 0, 0, -4096], "Ry(180°)")
        arcade_kmd.turn_attachments(model, {2: (0, 0x8000, 0)}, SINE)
        self.assertEqual(model.rows[2].verts.coords, [(-30, 0, 0), (0, 0, -7)])
        self.assertEqual(model.rows[2].normals.coords, [(-4096, 0, 0)])
        self.assertEqual(arcade_kmd.turned([0x10000, 0, 0, 0, 4096, 0, 0, 0, 4096], (20000, 1, 2)), (0x7FFF, 1, 2),
                         "saturated to s16 as MVMVA's IR")
        self.assertEqual(arcade_kmd.playstation_frame(14, (1, 2, 3)), (-3, 2, 1), "a foot: Ry(−90°)")
        self.assertEqual(arcade_kmd.playstation_frame(13, (1, 2, 3)), (1, 2, 3))

    def test_load_turns_follow_the_enable_values(self) -> None:
        turns = {2 * 8: (1, 2, 3)}
        enable = bytes([0] * 18 + [1, 2, 0, 0, 0, 0])

        def values(fmt: str, addr: int) -> tuple:
            return turns[addr - arcade_kmd.LOAD_TURNS]

        self.assertEqual(arcade_kmd.load_turns(values, 0, enable), {19: (1, 2, 3)}, "static (1) and hidden rows keep theirs")


class ArcadeCharacterTest(unittest.TestCase):
    """model_faces and character.write_model end to end: a chest, a foot and a swinging
    attachment whose seam vertex weighs all three (0.5, 0.25, 0.25)."""

    def setUp(self) -> None:
        ft3 = (0, [0 | 1 << 8 | 0 << 16, 0], [0x0201, 0x0403, 0x0605])
        self.data = _model({
            1: (_vertices([(10, 0, 0)], exports=[3 | HALF << 16]), _vertices([(4096, 0, 0)]), [], 0),
            # The foot's own face uses its unblended vertex 1 (vertex 0 is a partial seam sum).
            14: (_vertices([(1, 2, 3), (0, 9, 0)], blends=[3 | (ONE // 4) << 16]), _vertices([(0, 4096, 0)]),
                 [(0, [1 | 1 << 8 | 1 << 16, 0], [0x0201, 0x0403, 0x0605])], 13),
            18: (_vertices([(0, 0, 7), (4, 0, 0)], blends=[3 | (ONE // 4) << 16]),
                 _vertices([(0, 0, 4096), (4096, 0, 0)]), [ft3], 1),
        })
        self.enable = bytes([0] * 18 + [2] + [0] * 5)
        self.turns = {18: (0, 0x8000, 0)}      # Ry(180°) as the model loads

    def test_faces_carry_turned_and_foot_frames(self) -> None:
        model, drawn, faces, local, normal, _ = arcade_character.model_faces(self.data, self.enable, self.turns, SINE, "test", 0)
        self.assertEqual(drawn, {1, 14, 18})
        self.assertEqual(len(faces), 2)
        _, terms, nt, _, _ = faces[1][2][0]          # the attachment's seam corner
        self.assertEqual([(t.part, w) for t, w in terms], [(1, 0.5), (14, 0.25), (22, 0.25)])
        attachment = terms[2][0]
        self.assertEqual(local(attachment), (0, 0, -7), "turned as the model loads")
        self.assertEqual(local(terms[1][0]), (-3, 2, 1), "the foot in the PlayStation's frame")
        self.assertEqual(normal(nt), (0.0, 0.0, -1.0), "its normal turned too")

    def test_mesh_carries_the_third_joint(self) -> None:
        model, drawn, faces, local, normal, _ = arcade_character.model_faces(self.data, self.enable, self.turns, SINE, "test", 0)
        with tempfile.TemporaryDirectory() as tmp:
            out = Output(Path(tmp))
            character.write_model(out, "characters/test", {"name": "test"}, faces, local, normal, lambda j: j,
                                  Vram(arcade_kmd.VRAM_ROWS), arcade_character.material_page, None, sources=False)
            record = json.loads((Path(tmp) / "characters/test/model.json").read_text())
            floats = struct.unpack(f"<{len(gzip.decompress((Path(tmp) / 'characters/test/mesh.bin.gz').read_bytes())) // 4}f",
                                   gzip.decompress((Path(tmp) / "characters/test/mesh.bin.gz").read_bytes()))
        stride = record["vertex_floats"]
        self.assertEqual(stride, character.VERTEX_FLOATS)
        corners = [floats[i:i + stride] for i in range(0, len(floats), stride)]
        three = [c for c in corners if c[26] > 0.0]
        self.assertTrue(three, "a corner with a third joint")
        c = three[0]
        self.assertEqual((c[0:3], c[12]), ((10.0, 0.0, 0.0), 1.0), "a: the chest")
        self.assertEqual((c[3:6], c[6], c[13]), ((-3.0, 2.0, 1.0), 0.25, 14.0), "b: the foot")
        self.assertEqual((c[23:26], c[26], c[27]), ((0.0, 0.0, -7.0), 0.25, 22.0), "c: the attachment's joint")


class VariantTest(unittest.TestCase):
    """The vertex variants as pose groups: True Ogre's wings (row 1: only the vertices a variant
    moves) and tail (rows 18 and 19, turned as the model loads like the base blocks), and the hands'
    rows moving as a whole."""

    WING_VERTICES = [(5, 0, 0), (0, 10, 0), (0, 0, 10)]      # vertex 1 moves with the variant
    TAIL_VERTICES = [(1, 0, 0), (0, 2, 0), (0, 0, 3)]        # row 19: vertex 0 moves with the level

    def wing_block(self, k: int) -> bytes:
        return _vertices([self.WING_VERTICES[0], (0, 10 + k, 0), self.WING_VERTICES[2]])

    def tail_block(self, k: int) -> bytes:
        return _vertices([(1 + k, 0, 0), *self.TAIL_VERTICES[1:]])

    def setUp(self) -> None:
        ft3 = lambda verts: (0, [verts[0] | verts[1] << 8 | verts[2] << 16, 0], [0x0201, 0x0403, 0x0605])
        normals = _vertices([(0, 4096, 0)] * 3)
        variants = arcade_kmd.VARIANTS
        # The wing row's variant 40 is the base block (what the row shows before the game picks one);
        # a tail row keeps the base block's pointer for variants 17 and on, as the game's models do.
        self.data = _model({
            1: (self.wing_block(40), normals, [ft3((0, 1, 2)), ft3((0, 0, 0))], 0),
            18: (_vertices(self.TAIL_VERTICES), normals, [], 6),
            19: (_vertices(self.TAIL_VERTICES), normals, [ft3((0, 1, 2)), ft3((1, 2, 2))], 18),
        }, {
            1: [self.wing_block(k) for k in range(variants)],
            18: [_vertices(self.TAIL_VERTICES)] * arcade_kmd.TURNED_VARIANTS + [None] * (variants - arcade_kmd.TURNED_VARIANTS),
            19: [self.tail_block(k) for k in range(arcade_kmd.TURNED_VARIANTS)]
                + [None] * (variants - arcade_kmd.TURNED_VARIANTS),
        })
        self.enable = bytes([0] * 18 + [2, 2, 0, 0, 0, 0])
        self.turns = {18: (0, 0x8000, 0), 19: (0, 0x8000, 0)}

    def groups(self) -> tuple[list, list]:
        _, _, faces, _, _, _ = arcade_character.model_faces(self.data, self.enable, self.turns, SINE, "test", 32)
        model = arcade_kmd.parse(self.data)
        arcade_kmd.turn_attachments(model, self.turns, SINE)
        return arcade_character.pose_groups(self.data, model, 32), faces

    def test_only_a_variants_moving_vertices_make_a_group(self) -> None:
        groups, faces = self.groups()
        wings, tail = groups
        self.assertEqual((wings.key, wings.channel, wings.part, wings.count), (character.WINGS, 0, 1, 40))
        self.assertEqual(wings.moving, {(1, 1)}, "the vertices that stay are not")
        self.assertEqual((tail.key, tail.channel, tail.part, tail.count), (character.WINGS, 1, 18, 17))
        self.assertEqual(tail.moving, {(19, 0)}, "row 18's variants equal its base block")
        self.assertEqual([f[1] for f in faces], [0, -1, 1, -1], "faces on vertices that stay are the body's")

    def test_the_tail_variants_turn_with_the_load_turn(self) -> None:
        tail = self.groups()[0][1]
        self.assertEqual(tail.coords[19][0][0], (-1, 0, 0), "Ry(180°) as the base block")
        self.assertEqual(tail.coords[19][16][0], (-17, 0, 0))
        self.assertEqual(tail.coords[19][16][1], (0, 2, 0), "a vertex on the axis stays")
        self.assertEqual(tail.coords[18][5], [(-1, 0, 0), (0, 2, 0), (0, 0, -3)], "row 18's variants are its base block turned")

    def test_an_entry_at_the_base_block_is_the_base_block(self) -> None:
        model = arcade_kmd.parse(self.data)
        arcade_kmd.turn_attachments(model, self.turns, SINE)
        self.assertEqual(arcade_kmd.variant(self.data, model, 19, 30).coords, model.rows[19].verts.coords,
                         "the turned base block, not a second turn of the file's")
        self.assertEqual(model.rows[19].verts.coords[0], (-1, 0, 0))

    def test_a_shared_variant_block_is_turned_once(self) -> None:
        model = arcade_kmd.parse(self.data)
        arcade_kmd.turn_attachments(model, self.turns, SINE)
        model.rows[19].variants[2] = model.rows[19].variants[1]
        with self.assertRaises(arcade_kmd.ArcadeKmdError):
            arcade_kmd.variant(self.data, model, 19, 1)

    def test_the_mesh_holds_a_surface_set_per_variant(self) -> None:
        groups, faces = self.groups()
        _, _, faces, local, normal, _ = arcade_character.model_faces(self.data, self.enable, self.turns, SINE, "test", 32)
        with tempfile.TemporaryDirectory() as tmp:
            out = Output(Path(tmp))
            character.write_model(out, "characters/test", {"name": "test"}, faces, local, normal, lambda j: j,
                                  Vram(arcade_kmd.VRAM_ROWS), arcade_character.material_page, None, sources=False,
                                  groups=groups)
            record = json.loads((Path(tmp) / "characters/test/model.json").read_text())
            raw = gzip.decompress((Path(tmp) / "characters/test/mesh.bin.gz").read_bytes())
        self.assertEqual(record["hands"], [])
        self.assertEqual([(w["channel"], w["part"], len(w["variants"])) for w in record["wings"]], [(0, 1, 40), (1, 18, 17)])
        stride = record["vertex_floats"]

        def corner(surface: dict, i: int) -> tuple[float, ...]:
            start = surface["offset"] // 4 + stride * i
            return struct.unpack_from(f"<{stride}f", raw, 4 * start)

        wing = record["wings"][0]["variants"]
        for k in (0, 7, 39):
            (surface,) = wing[k]
            self.assertEqual(surface["vertex_count"], 3, "the moving face only")
            self.assertEqual(corner(surface, 1)[0:3], (0.0, 10.0 + k, 0.0), f"vertex 1 in variant {k}")
        self.assertEqual(len(record["surfaces"]), 1, "the body keeps the static faces")
        self.assertEqual(record["surfaces"][0]["vertex_count"], 6)
        tail = record["wings"][1]["variants"]
        self.assertEqual(corner(tail[3][0], 0)[0:3], (-4.0, 0.0, 0.0), "row 19's vertex 0 in variant 3, turned")


class HandVariantTest(unittest.TestCase):
    """The hands' (and Kuma's and Panda's jaw's) variants: all of the arcade's 41, of which only the
    distinct ones are kept (the shapes 33–40 repeat the fist's block here), packed as the pose tables
    of the moving vertices the remake patches into one set of surfaces."""

    DISTINCT = 33

    @staticmethod
    def hand_block(k: int) -> bytes:
        return _vertices([(5, 0, 0), (0, 10 + min(k, 32), 0), (0, 0, 10)])      # vertex 1 closes up to the fist

    @staticmethod
    def jaw_block(k: int) -> bytes:
        return _vertices([(0, 0, 0), (1, 0, 0), (0, 0, 3), (0, 5, min(k, 32))])  # vertex 3 swings open

    def setUp(self) -> None:
        ft3 = lambda verts: (0, [verts[0] | verts[1] << 8 | verts[2] << 16, 0], [0x0201, 0x0403, 0x0605])
        normals = _vertices([(0, 4096, 0)] * 4)
        variants = arcade_kmd.VARIANTS
        self.data = _model({
            1: (_vertices([(10, 0, 0)]), normals, [], 0),
            2: (self.jaw_block(0), normals, [ft3((0, 1, 3)), ft3((0, 1, 2))], 1),
            6: (self.hand_block(0), normals, [ft3((0, 1, 2))], 1),
            10: (self.hand_block(0), normals, [ft3((0, 1, 2)), ft3((0, 0, 2))], 1),
        }, {
            2: [self.jaw_block(k) for k in range(variants)],
            6: [self.hand_block(k) for k in range(variants)],
            10: [self.hand_block(k) for k in range(variants)],
        })
        self.model = arcade_kmd.parse(self.data)

    def test_the_hand_rows_of_a_costume(self) -> None:
        self.assertEqual(arcade_character.hand_rows(0), [(10, 16), (6, 12)], "left hand: channel 0, right hand: channel 1")
        self.assertEqual(arcade_character.hand_rows(22), [(2, 17), (6, 12)], "Kuma's jaw replaces the left hand")
        self.assertEqual(arcade_character.hand_rows(23), [(2, 17), (6, 12)], "and Panda's")
        self.assertEqual(arcade_character.hand_rows(24), [(10, 16), (6, 12)])

    def test_every_variant_selects_a_distinct_block(self) -> None:
        left, right = arcade_character.pose_groups(self.data, self.model, 0)
        for channel, group, row in ((0, left, 10), (1, right, 6)):
            self.assertEqual((group.key, group.channel, group.count, group.distinct, group.packed),
                             (character.HANDS, channel, arcade_kmd.VARIANTS, self.DISTINCT, True))
            self.assertEqual(group.part, character.HAND_PARTS[channel])
            self.assertEqual(group.moving, {(row, 1)}, "only the vertex that moves")
            self.assertEqual(list(group.select), [*range(self.DISTINCT), *[self.DISTINCT - 1] * 8],
                             "the variants 33–40 repeat the fist's block")
            self.assertEqual(group.coords[row][0][1], (0, 10, 0), "the open hand")
            self.assertEqual(group.coords[row][3][1], (0, 13, 0), "variant 3: barely closed")
            self.assertEqual(group.coords[row][group.select[32]][1], (0, 42, 0), "the fist is variant 32")

    def test_a_jaw_costume_selects_the_jaw_by_channel_0(self) -> None:
        (jaw,) = [g for g in arcade_character.pose_groups(self.data, self.model, 22) if g.channel == 0]
        self.assertEqual((jaw.part, jaw.moving, jaw.count), (17, {(2, 3)}, arcade_kmd.VARIANTS))
        self.assertEqual(jaw.coords[2][jaw.select[32]][3], (0, 5, 32))
        groups = arcade_character.pose_groups(self.data, self.model, 22)
        self.assertEqual([(g.channel, g.part) for g in groups], [(0, 17), (1, 12)], "row 10 is not a hand of this costume")

    def test_a_row_without_variants_has_no_group(self) -> None:
        model = arcade_kmd.parse(_model({1: (_vertices([(10, 0, 0)]), _vertices([(0, 4096, 0)]), [], 0)}))
        self.assertEqual(arcade_character.pose_groups(b"", model, 0), [])

    def surfaces(self, groups: list) -> tuple[dict, bytes]:
        """model.json and the decoded mesh of the model written with `groups`."""
        _, _, faces, local, normal, _ = arcade_character.model_faces(self.data, bytes(24), {}, SINE, "test", 0)
        faces = [(sided, g, corners) for sided, _, corners in faces for g in [character.face_group(corners, groups, "test")]]
        with tempfile.TemporaryDirectory() as tmp:
            out = Output(Path(tmp))
            character.write_model(out, "characters/test", {"name": "test"}, faces, local, normal, lambda j: j,
                                  Vram(arcade_kmd.VRAM_ROWS), arcade_character.material_page, None, sources=False,
                                  groups=groups)
            record = json.loads((Path(tmp) / "characters/test/model.json").read_text())
            raw = gzip.decompress((Path(tmp) / "characters/test/mesh.bin.gz").read_bytes())
        return record, raw

    def test_the_packed_group_patches_to_the_surfaces_of_every_variant(self) -> None:
        packed = arcade_character.pose_groups(self.data, self.model, 0)
        full = [character.variant_group(g.key, g.channel, g.part,
                                        {row: [variants[e] for e in g.select] for row, variants in g.coords.items()},
                                        {row: variants[0] for row, variants in g.coords.items()})
                for g in packed]
        record_packed, raw_packed = self.surfaces(packed)
        record_full, raw_full = self.surfaces(full)
        stride = record_packed["vertex_floats"]

        def floats(raw: bytes, surface: dict) -> list[float]:
            return list(struct.unpack_from(f"<{surface['vertex_count'] * stride}f", raw, surface["offset"]))

        self.assertLess(len(raw_packed), len(raw_full), "the packed group is smaller")
        for hand_packed, hand_full in zip(record_packed["hands"], record_full["hands"]):
            self.assertEqual(len(hand_full["variants"]), arcade_kmd.VARIANTS)
            self.assertEqual(len(hand_packed["variants"]), 1, "the first variant's surfaces")
            poses = hand_packed["poses"]
            self.assertEqual((poses["count"], poses["vertices"]), (self.DISTINCT, 1))
            table = struct.unpack_from(f"<{poses['count'] * poses['vertices'] * 3}f", raw_packed, poses["table"])
            corners = sum(s["vertex_count"] for s in hand_packed["variants"][0])
            refs = struct.unpack_from(f"<{corners * 3}i", raw_packed, poses["refs"])
            for variant in range(arcade_kmd.VARIANTS):
                entry = hand_packed["select"][variant]
                patched = []
                corner = 0
                for surface in hand_packed["variants"][0]:
                    values = floats(raw_packed, surface)
                    for i in range(surface["vertex_count"]):
                        for k, at in enumerate(character.POSITION_FLOATS):
                            ref = refs[3 * (corner + i) + k]
                            if ref >= 0:
                                values[i * stride + at:i * stride + at + 3] = table[(entry * poses["vertices"] + ref) * 3:][:3]
                    corner += surface["vertex_count"]
                    patched.extend(values)
                expected = [v for surface in hand_full["variants"][variant] for v in floats(raw_full, surface)]
                self.assertEqual(patched, expected, f"variant {variant}")
        self.assertTrue(any(r >= 0 for r in refs) and any(r < 0 for r in refs), "positions that move and stay")


class VariantGroupTest(unittest.TestCase):
    def test_whole_rows_or_the_vertices_that_differ(self) -> None:
        coords = {4: [[(0, 0, 0), (1, 0, 0)], [(0, 0, 0), (2, 0, 0)]]}
        self.assertEqual(character.variant_group(character.HANDS, 0, 16, coords).moving, {(4, 0), (4, 1)})
        base = {4: [(0, 0, 0), (1, 0, 0)]}
        self.assertEqual(character.variant_group(character.WINGS, 0, 4, coords, base).moving, {(4, 1)})
        base = {4: [(9, 0, 0), (1, 0, 0)]}
        self.assertEqual(character.variant_group(character.WINGS, 0, 4, coords, base).moving, {(4, 0), (4, 1)},
                         "a variant that differs from the base block only")

    def test_a_packed_group_keeps_the_distinct_variants(self) -> None:
        a, b = [(0, 0, 0), (1, 0, 0)], [(0, 0, 0), (2, 0, 0)]
        coords = {4: [a, b, a, b, b]}
        group = character.variant_group(character.HANDS, 0, 16, coords, packed=True)
        self.assertEqual((group.count, group.distinct, list(group.select)), (5, 2, [0, 1, 0, 1, 1]))
        self.assertEqual(group.coords, {4: [a, b]})
        plain = character.variant_group(character.HANDS, 0, 16, coords)
        self.assertEqual((plain.count, plain.distinct, list(plain.select), plain.packed), (5, 5, [0, 1, 2, 3, 4], False))
        base = {4: [(0, 0, 0), (7, 0, 0)]}
        c = [(9, 0, 0), (1, 0, 0)]           # differs from `a` only in the vertex that stays
        grouped = character.variant_group(character.WINGS, 0, 4, {4: [a, c, a]}, base, packed=True)
        self.assertEqual(grouped.moving, {(4, 0), (4, 1)})
        self.assertEqual(list(grouped.select), [0, 1, 0])
        still = character.variant_group(character.WINGS, 0, 4, {4: [a, [(9, 0, 0), (1, 0, 0)]]},
                                        {4: [(9, 0, 0), (1, 0, 0)]}, packed=True)
        self.assertEqual(list(still.select), [0, 1], "equal only where it moves: different")

    def test_rows_with_other_numbers_of_variants_are_refused(self) -> None:
        with self.assertRaises(ValueError):
            character.variant_group(character.WINGS, 0, 1, {1: [[(0, 0, 0)]], 2: [[(0, 0, 0)], [(0, 0, 0)]]})

    def test_a_face_belongs_to_one_group(self) -> None:
        a = character.variant_group(character.HANDS, 0, 16, {4: [[(0, 0, 0)]]})
        b = character.variant_group(character.HANDS, 1, 12, {5: [[(0, 0, 0)]]})

        def corner(row: int) -> tuple:
            return (None, ((character.Term(row, row, 0), 1.0),), None, 0, 0)

        self.assertEqual(character.face_group([corner(4), corner(3)], [a, b], "test"), 0)
        self.assertEqual(character.face_group([corner(3)], [a, b], "test"), -1)
        with self.assertRaises(ValueError):
            character.face_group([corner(4), corner(5)], [a, b], "test")


if __name__ == "__main__":
    unittest.main()
