"""The arcade's eye shapes (arcade_eyes.py, character.write_model's `eyes`) on a synthetic program
and VRAM: no game data."""

from __future__ import annotations

import json
import struct
import tempfile
import unittest
from pathlib import Path

import numpy as np
from PIL import Image

import common  # noqa: F401  (puts tools/research on the import path)
import arcade_character
import arcade_eyes
import arcade_kmd
import character
from common import Output
from vram import Vram

BASE = 0x80010000
SIZE = 0x201000
NO_LAYOUT = (-1,) * 8
SHOUT_FRAMES = (11, 12, 13, 14, 15, 16, 17, 18, 0)        # synthetic: the frames of character 0's nine voices
T0, T1, V1, A0, A1, A2, A3, RA = 8, 9, 3, 4, 5, 6, 7, 31
CODE_WORDS = 4                                            # the words of one voice's test in a character's block
BLOCK_WORDS = 3 + arcade_eyes.SHOUT_CODES * CODE_WORDS + 3
PROLOGUE_WORDS = 4


def ori(rt: int, rs: int, imm: int) -> int:
    return 0x0D << 26 | rs << 21 | rt << 16 | imm


def branch(op: int, rs: int, rt: int, offset: int) -> int:
    return op << 26 | rs << 21 | rt << 16 | offset & 0xFFFF


def shout_routine(shouting: dict[int, tuple[int, tuple[int, ...]]]) -> bytes:
    """A routine shaped like FUN_801A1C74 (the same instructions) for the characters in `shouting`
    (id → face value, the frames of the voices 0x2000 on): it loads the character id and the voice
    id, goes through a block per character that sets the frames and the value, and ends with a jal
    of FUN_80194080 with the frames in $a3; the other characters return."""
    words = [0x21 << 26 | A0 << 21 | V1 << 16 | arcade_eyes.SHOUT_CHARACTER,       # lh $v1, 0x1a($a0)
             A1 << 16 | 2 << 11 | 16 << 6,                                              # sll $v0, $a1, 16
             2 << 16 | 2 << 11 | 16 << 6 | 3,                                           # sra $v0, $v0, 16
             A3 << 11 | 0x25]                                                           # move $a3, $zero
    end = arcade_eyes.SHOUT + 4 * (PROLOGUE_WORDS + BLOCK_WORDS * len(shouting) + 2)
    for char, (value, frames) in sorted(shouting.items()):
        block = [ori(T0, 0, char), branch(5, V1, T0, BLOCK_WORDS - 2), 0]
        for k, count in enumerate(frames):
            block += [ori(T1, 0, arcade_eyes.SHOUT_FIRST + k), branch(5, 2, T1, 2), 0, ori(A3, 0, count)]
        block += [ori(A2, 0, value), 0x02 << 26 | (end >> 2) & 0x3FFFFFF, 0]
        words += block
    words += [0x03E00008, 0]                                                            # jr $ra: no match
    words += [0x03 << 26 | (arcade_eyes.SHOUT_FACE >> 2) & 0x3FFFFFF, 0, 0x03E00008, 0]             # jal FUN_80194080; jr $ra
    return struct.pack(f"<{len(words)}I", *words)


class FakeProgram:
    """The three program readers of arcade.ArcadeSet over a zeroed image."""

    def __init__(self) -> None:
        self.memory = bytearray(SIZE)

    def poke(self, addr: int, data: bytes) -> None:
        self.memory[addr - BASE:addr - BASE + len(data)] = data

    def prog(self, addr: int, size: int) -> bytes:
        return bytes(self.memory[addr - BASE:addr - BASE + size])

    def prog_values(self, fmt: str, addr: int) -> tuple:
        return struct.unpack(fmt, self.prog(addr, struct.calcsize(fmt)))

    prog_table = prog_values


def program(layouts: dict[int, tuple], blink: dict[int, int], held: dict[int, int], down: dict[int, int],
            characters: dict[int, int]) -> FakeProgram:
    """A program whose costume slots have these eye layouts and role tables; `characters`: slot →
    its entry (id × colours + colour) in the character table."""
    p = FakeProgram()
    for slot, layout in layouts.items():
        p.poke(arcade_eyes.LAYOUT + arcade_eyes.LAYOUT_BYTES * slot, struct.pack("<8b", *layout))
    for base, table in ((arcade_eyes.BLINK, blink), (arcade_eyes.HELD, held), (arcade_eyes.DOWN, down)):
        for slot, shape in table.items():
            p.poke(base + slot, struct.pack("<b", shape))
    colours = [-1] * (arcade_eyes.CHARACTER_IDS * arcade_eyes.CHARACTER_COLOURS)
    for slot, entry in characters.items():
        colours[entry] = slot
    p.poke(arcade_eyes.CHARACTER_SLOTS, struct.pack(f"<{len(colours)}b", *colours))
    # Rectangle k at (16 k, 256), sizes: 0 is 4 × 8 words.
    for k in range(16):
        p.poke(arcade_eyes.RECTS + 4 * k, struct.pack("<2h", 16 * k, 256))
    p.poke(arcade_eyes.SIZES, struct.pack("<2h", 4, 8))
    p.poke(arcade_eyes.SHOUT, shout_routine({0: (13, SHOUT_FRAMES)}))
    return p


class ArcadeEyesTest(unittest.TestCase):
    def setUp(self) -> None:
        # Slot 0: eyes at rectangle 3, shapes 0–4 at rectangles 11–15 (character 0 shouts shape 3);
        # slot 1: shapes 0–1 only, so its blink (2) and shout shape are missing; slot 2: no layout.
        self.arc = program(
            {0: (3, 0, 11, 12, 13, 14, 15, -1), 1: (3, 0, 11, 12, -1, -1, -1, -1), 2: NO_LAYOUT},
            blink={0: 2, 1: 2}, held={0: 1, 1: 1}, down={0: 2, 1: 0}, characters={0: 0, 1: 1, 2: 20})

    def test_roles_name_the_shapes_the_costume_has(self) -> None:
        self.assertEqual(arcade_eyes.roles(self.arc, 0), {"blink": 2, "held": 1, "down": 2, "shout": 3})
        self.assertEqual(arcade_eyes.roles(self.arc, 1),
                         {"blink": arcade_eyes.NO_SHAPE, "held": 1, "down": 0, "shout": arcade_eyes.NO_SHAPE})

    def test_record_has_the_shout_frames_of_a_shouting_character(self) -> None:
        record = arcade_eyes.record(self.arc, 0)
        self.assertEqual(record["shout_frames"], list(SHOUT_FRAMES))
        self.assertEqual(len(record["shout_frames"]), arcade_eyes.SHOUT_CODES)
        self.assertEqual(arcade_eyes.record(self.arc, 1)["shout_frames"], list(SHOUT_FRAMES))

    def test_the_shouts_are_read_from_the_routine(self) -> None:
        arc = program({}, {}, {}, {}, {})
        arc.poke(arcade_eyes.SHOUT, shout_routine({0: (13, SHOUT_FRAMES), 6: (15, (1, 2, 3, 4, 5, 6, 7, 8, 9))}))
        self.assertEqual(arcade_eyes.shouts(arc), {0: (3, SHOUT_FRAMES), 6: (5, (1, 2, 3, 4, 5, 6, 7, 8, 9))})
        self.assertEqual(arcade_eyes.run_shout(arc, 6, arcade_eyes.SHOUT_FIRST + 2), (15, 3))
        self.assertIsNone(arcade_eyes.run_shout(arc, 3, arcade_eyes.SHOUT_FIRST), "a character that does not shout")

    def test_a_routine_with_an_unknown_instruction_is_refused(self) -> None:
        arc = program({}, {}, {}, {}, {})
        arc.poke(arcade_eyes.SHOUT, struct.pack("<I", 0x2B << 26 | 0x10 << 21))      # a store through a register
        arc.poke(arcade_eyes.SHOUT + 4, struct.pack("<I", 0x3F << 26))
        with self.assertRaises(arcade_eyes.ShoutError):
            arcade_eyes.run_shout(arc, 0, arcade_eyes.SHOUT_FIRST)

    def test_a_character_that_does_not_shout_has_none(self) -> None:
        arc = program({3: (3, 0, 11, 12, 13, 14, 15, -1)}, {3: 2}, {3: 1}, {3: 2}, {3: 20})
        self.assertEqual(arcade_eyes.roles(arc, 3)["shout"], 0)
        self.assertEqual(arcade_eyes.record(arc, 3)["shout_frames"], [])

    def test_a_slot_without_a_layout_has_no_record(self) -> None:
        self.assertIsNone(arcade_eyes.record(self.arc, 2))
        self.assertEqual(arcade_eyes.copies(self.arc, 2), {})

    def test_copies_cover_the_shapes_the_roles_use(self) -> None:
        # Slot 0 uses shapes 2 (blink, down), 1 (held) and 3 (shout), not shape 4; the eyes are
        # rectangle 3 at (48, 256), the shapes 4 × 8 words at their own rectangles.
        self.assertEqual(arcade_eyes.copies(self.arc, 0), {
            1: ((16 * 12, 256, 4, 8), (48, 256)),
            2: ((16 * 13, 256, 4, 8), (48, 256)),
            3: ((16 * 14, 256, 4, 8), (48, 256)),
        })
        self.assertEqual(sorted(arcade_eyes.copies(self.arc, 1)), [1], "the missing shapes are not copied")

    def test_images_put_each_shape_over_the_eyes(self) -> None:
        vram = Vram(arcade_kmd.VRAM_ROWS)
        for shape in range(5):
            vram.words[256:264, 16 * (11 + shape):16 * (11 + shape) + 4] = 100 + shape
        shown = arcade_eyes.images(self.arc, 0, vram)
        self.assertEqual(sorted(shown), [1, 2, 3])
        for shape, image in shown.items():
            self.assertTrue((image.words[256:264, 48:52] == 100 + shape).all(), f"shape {shape} over the eyes")
            self.assertTrue((image.words[256:264, 52:] == vram.words[256:264, 52:]).all(), "nothing else changes")
        self.assertTrue((vram.words[256:264, 48:52] == 0).all(), "the costume's own VRAM is left as loaded")


class WriteEyesTest(unittest.TestCase):
    """character.write_model writes an atlas per eye shape and lists them in model.json."""

    def write(self, **kwargs) -> tuple[Path, dict]:
        vram = Vram(512)
        vram.words[0:8, 0:4] = 0x1111          # 4-bit texels of index 1 over the eyes' rectangle
        vram.words[500, 0:16] = [0, 0x001F] + [0] * 14
        shown = vram.copy()
        shown.words[0:8, 0:4] = 0x2222         # index 2
        shown_clut = shown.copy()
        shown_clut.words[500, 2] = 0x03E0
        term = character.Term(0, 0, 0)

        def corner(u: int, v: int) -> tuple:
            return ((0, 0), ((term, 1.0),), term, u, v)

        faces = [(False, -1, [corner(0, 0), corner(15, 0), corner(0, 7)])]
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        out = Output(Path(tmp.name))
        shapes = kwargs.pop("eyes", None)
        if shapes is not None:
            shapes = {k: shown_clut if k == 2 else shown for k in shapes}
        character.write_model(out, "characters/test", {"name": "test"}, faces, lambda t: (0, 0, 0),
                              lambda t: (0.0, 1.0, 0.0), lambda part: part, vram,
                              lambda m: (0, 0, 4, 0, 500), kwargs.pop("closed", None), sources=False, eyes=shapes)
        folder = Path(tmp.name) / "characters/test"
        return folder, json.loads((folder / "model.json").read_text())

    def test_each_shape_has_its_own_atlas(self) -> None:
        folder, record = self.write(eyes=[2, 3])
        self.assertEqual(record["eye_textures"], {"2": "texture_eye2.png", "3": "texture_eye3.png"})
        self.assertNotIn("texture_closed", record)
        self.assertEqual(sorted(p.name for p in folder.glob("texture*.png")),
                         ["texture.png", "texture_eye2.png", "texture_eye3.png"])
        base = np.array(Image.open(folder / "texture.png"))
        two = np.array(Image.open(folder / "texture_eye2.png"))
        three = np.array(Image.open(folder / "texture_eye3.png"))
        self.assertEqual(base.shape, two.shape, "the same atlas layout")
        self.assertTrue((base != two).any(), "the shape changes the eyes' texels")
        self.assertTrue((three != base).any())
        self.assertTrue((two != three).any(), "shape 2 went through its own palette")

    def test_the_playstations_closed_atlas_is_unchanged(self) -> None:
        vram = Vram(512)
        closed = vram.copy()
        closed.words[0:8, 0:4] = 0x1111
        folder, record = self.write(closed=closed)
        self.assertEqual(record["texture_closed"], "texture_closed.png")
        self.assertNotIn("eye_textures", record)
        self.assertEqual(sorted(p.name for p in folder.glob("texture*.png")), ["texture.png", "texture_closed.png"])


class ModelFilesTest(unittest.TestCase):
    def test_a_failed_conversion_clears_the_eye_atlases_too(self) -> None:
        for rel in ("model.json", "mesh.bin.gz", "texture.png", "texture_eye1.png", "texture_eye5.png"):
            self.assertTrue(arcade_character.is_model_file(rel), rel)
        for rel in ("texture_closed.png", "moves.json"):
            self.assertFalse(arcade_character.is_model_file(rel), rel)


if __name__ == "__main__":
    unittest.main()
