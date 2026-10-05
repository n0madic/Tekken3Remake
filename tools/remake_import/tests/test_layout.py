"""Layouts (layout.py): another release's images rebased onto Japan Rev.1's addresses, on
synthetic images: no game data."""

from __future__ import annotations

import random
import struct
import unittest

from common import BNS_RECORDS, CANONICAL, EXE_BASE, EXE_HEADER, OVERLAYS, Disc, Release
import layout

TEXTS = ["HELLO", "WORLD", "SHORT", "TAIL"]
OTHER_TEXTS = ["HELLO", "WORLD", "A LONGER TEXT", "TAIL"]
FILLER = 512
HEAD_POINTER = 0x100
INSERTED = 16
OTHER = Release("other", "Other", (), (), (), 0, 8, (CANONICAL.slots[0] + 0x100, CANONICAL.slots[1] + 0x200), False)


def _exe(rng: random.Random, head: bytes, tail: bytes, texts: list[str], inserted: bytes) -> bytes:
    """Data naming a table of pointers to texts (as the code names it), the table, the texts and
    more data."""
    table = len(head) + len(inserted)
    head = head[:HEAD_POINTER] + struct.pack("<I", EXE_BASE + table) + head[HEAD_POINTER + 4:]
    pool = table + 4 * len(texts)
    words, raw = [], b""
    for text in texts:
        words.append(EXE_BASE + pool + len(raw))
        raw += text.encode() + b"\0"
    raw += bytes(-len(raw) % 4)
    return head + inserted + struct.pack(f"<{len(words)}I", *words) + raw + tail


def _disc(release: Release, exe_data: bytes, overlays: dict[int, bytes]) -> Disc:
    records = [b""] * BNS_RECORDS
    for record_id, data in overlays.items():
        records[record_id] = data
    return Disc(release, bytes(EXE_HEADER) + exe_data, records, None, release)


def _pair() -> tuple[Disc, Disc, int]:
    rng = random.Random(3)
    head, tail = rng.randbytes(FILLER), rng.randbytes(FILLER)
    overlays = {bns: rng.randbytes(256) for bns, _ in OVERLAYS.values()}
    canon = _disc(CANONICAL, _exe(rng, head, tail, TEXTS, b""), overlays)
    other = _disc(OTHER, _exe(rng, head, tail, OTHER_TEXTS, rng.randbytes(INSERTED)), overlays)
    return canon, other, EXE_BASE + FILLER


class LayoutTest(unittest.TestCase):
    def test_align_finds_shifted_runs(self) -> None:
        rng = random.Random(1)
        a, b = rng.randbytes(400), rng.randbytes(300)
        segments = layout.align(a + b, a + rng.randbytes(40) + b)
        self.assertIn([0, 400, 0], segments)
        self.assertIn([400, 300, 440], segments)

    def test_rebase_restores_the_canonical_layout(self) -> None:
        canon, other, table = _pair()
        built = layout.build(canon, other)
        images, aside = layout.rebase(built, other)
        exe = images["exe"]
        for k, text in enumerate(TEXTS):
            pointer = struct.unpack_from("<I", exe, table - EXE_BASE + 4 * k)[0]
            self.assertEqual(pointer, struct.unpack_from("<I", canon.exe, table - EXE_BASE + EXE_HEADER + 4 * k)[0])
            end = exe.index(b"\0", pointer - EXE_BASE)
            placed = aside.get(("exe", pointer), exe[pointer - EXE_BASE:end].decode())
            self.assertEqual(placed, OTHER_TEXTS[k])
        self.assertIn(("exe", struct.unpack_from("<I", exe, table - EXE_BASE + 8)[0]), aside)   # too long to fit
        canon_exe = canon.exe[EXE_HEADER:]
        self.assertEqual(exe[:FILLER], canon_exe[:FILLER])       # the pointer to the table rewritten too
        self.assertEqual(exe[-FILLER:], canon_exe[-FILLER:])
        for name, (bns, _) in OVERLAYS.items():
            self.assertEqual(images[name], canon.records[bns], name)

    def test_rebase_refuses_another_image(self) -> None:
        canon, other, _ = _pair()
        built = layout.build(canon, other)
        changed = _disc(OTHER, other.exe[EXE_HEADER:-1] + b"\x01", {bns: other.records[bns] for bns, _ in OVERLAYS.values()})
        with self.assertRaises(layout.LayoutError):      # a layout applied to another image
            layout.rebase(built, changed)

    def test_source_and_canonical_addresses(self) -> None:
        self.assertEqual(layout.source_address(CANONICAL, "title", 0x800B9400), 0x800B9400)
        self.assertEqual(layout.canonical_address(CANONICAL, "exe", 0x80020000), 0x80020000)


if __name__ == "__main__":
    unittest.main()
