"""VABs read from memory (sounds.py): a synthetic bank, no game data."""

from __future__ import annotations

from pathlib import Path
import struct
import tempfile
import unittest

import common  # noqa: F401  (puts tools/research on the import path)
import sounds

VH_ADDR = 0x1000
BODY_ADDR = 0x2000
BODY = b"\x00\x07" + b"\x77" * 14       # Sony's one-shot terminal block
VH_SIZE = sounds.VH_TABLES + sounds.TONES_PER_PROGRAM * sounds.TONE_BYTES + 0x200


def memory() -> bytes:
    """One program, one tone, one VAG, at VH_ADDR and BODY_ADDR of a zeroed memory."""
    vh = bytearray(VH_SIZE)
    struct.pack_into("<4sIIIHHHH", vh, 0, b"pBAV", 7, 0, VH_SIZE + len(BODY), 0, 1, 1, 1)
    vh[0x18] = 127
    vh[0x20:0x25] = bytes((1, 127, 0, 0, 64))
    attr = sounds.VH_TABLES
    vh[attr + 2:attr + 6] = bytes((127, 64, 60, 0))
    struct.pack_into("<h", vh, attr + 22, 1)
    struct.pack_into("<H", vh, sounds.VH_TABLES + 0x200 + 2, len(BODY) >> 3)
    mem = bytearray(BODY_ADDR + len(BODY))
    mem[VH_ADDR:VH_ADDR + VH_SIZE] = vh
    mem[BODY_ADDR:BODY_ADDR + len(BODY)] = BODY
    return bytes(mem)


class FakeOutput:
    def __init__(self) -> None:
        self.files: dict[str, bytes] = {}

    def write(self, rel: str, data: bytes) -> None:
        self.files[rel] = data


class ReadVabTest(unittest.TestCase):
    def test_header_and_body_are_cut_by_the_header_sizes(self) -> None:
        data = memory()
        head, body = sounds.read_vab(lambda addr, size: data[addr:addr + size], VH_ADDR, BODY_ADDR)
        self.assertEqual(len(head), VH_SIZE)
        self.assertEqual(body, BODY)

    def test_a_bank_read_from_memory_gives_its_tone(self) -> None:
        data = memory()
        out = FakeOutput()
        read = lambda addr, size: data[addr:addr + size]  # noqa: E731
        bank = sounds.convert_bank(out, sounds.STAFF_ROLL_BANK, *sounds.read_vab(read, VH_ADDR, BODY_ADDR))
        self.assertEqual(list(bank["tones"]), ["0_0"])
        self.assertIn("sounds/staff_roll/0_0.wav", out.files)


class CompressedImportTest(unittest.TestCase):
    def test_only_the_compressed_samples_are_imported_again(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            (root / "combat").mkdir()
            (root / "combat/a.wav.import").write_text("[params]\ncompress/mode=2\n", encoding="utf-8")
            (root / "combat/b.wav.import").write_text("[params]\ncompress/mode=0\n", encoding="utf-8")
            (root / "combat/a.wav").write_bytes(b"sample")
            self.assertEqual(sounds.drop_compressed_imports(root), 1)
            self.assertEqual(sorted(p.name for p in (root / "combat").iterdir()), ["a.wav", "b.wav.import"])

    def test_the_project_imports_samples_uncompressed(self) -> None:
        project = Path(__file__).resolve().parents[3] / "remake/project.godot"
        self.assertRegex(project.read_text(encoding="utf-8"), r'wav=\{\s*"compress/mode": 0\s*\}')


if __name__ == "__main__":
    unittest.main()
