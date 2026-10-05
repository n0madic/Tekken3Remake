#!/usr/bin/env python3
"""Verify the original SLPS-01300 ECM image: rebuild every sector's EDC/ECC and check the ECM trailer.

ECM stores Mode 2 sectors without their error-correction bytes; the decoder regenerates them, and
the four-byte trailer is the CD EDC (CRC, polynomial 0xD8018001, reflected, initial value 0) of the
whole decoded track. This tool regenerates Form 1 EDC + P/Q ECC and Form 2 EDC for all sectors with
numpy, then compares the EDC of the full output with the trailer.

Usage: python3 tools/research/verify_ecm.py [--original-ecm PATH]
"""

from __future__ import annotations

import argparse
import logging
import mmap
from pathlib import Path

import numpy as np

from compare_japan_revisions import ECMImage

log = logging.getLogger("verify_ecm")
SECTOR = 2352
CHUNK = 8192


def tables():
    f_lut = np.zeros(256, np.uint8)
    b_lut = np.zeros(256, np.uint8)
    edc = np.zeros(256, np.uint32)
    for i in range(256):
        j = ((i << 1) ^ (0x11D if i & 0x80 else 0)) & 0xFF
        f_lut[i] = j
        b_lut[i ^ j] = i
        e = i
        for _ in range(8):
            e = (e >> 1) ^ (0xD8018001 if e & 1 else 0)
        edc[i] = e
    return f_lut, b_lut, edc


F_LUT, B_LUT, EDC_LUT = tables()


def edc_rows(block: np.ndarray) -> np.ndarray:
    """EDC of every row of a (sectors, bytes) uint8 array, starting from 0."""
    crc = np.zeros(block.shape[0], np.uint32)
    for j in range(block.shape[1]):
        crc = (crc >> np.uint32(8)) ^ EDC_LUT[(crc ^ block[:, j]) & 0xFF]
    return crc


def ecc_block(src: np.ndarray, major_count: int, minor_count: int, major_mult: int, minor_inc: int) -> np.ndarray:
    """P or Q parity (ecm.c ecc_computeblock) for every row of src (the sector from offset 0xC)."""
    size = major_count * minor_count
    majors = np.arange(major_count)
    index = (majors >> 1) * major_mult + (majors & 1)
    a = np.zeros((src.shape[0], major_count), np.uint8)
    b = np.zeros_like(a)
    for _ in range(minor_count):
        t = src[:, index]
        index = index + minor_inc
        index = np.where(index >= size, index - size, index)
        a ^= t
        b ^= t
        a = F_LUT[a]
    a = B_LUT[F_LUT[a] ^ b]
    return np.concatenate([a, a ^ b], axis=1)


def rebuild(sectors: np.ndarray, kinds: np.ndarray) -> None:
    """Fill in EDC and ECC of Mode 2 sectors in place (kinds: 2 = Form 1, 3 = Form 2)."""
    form1 = kinds == 2
    if form1.any():
        s = sectors[form1]
        s[:, 0x818:0x81C] = edc_rows(s[:, 0x10:0x818]).view(np.uint8).reshape(-1, 4)
        work = s[:, 0xC:].copy()
        work[:, 0:4] = 0                                  # Mode 2: the address is zero for ECC
        s[:, 0x81C:0x8C8] = ecc_block(work, 86, 24, 2, 86)
        work[:, 0x81C - 0xC:0x8C8 - 0xC] = s[:, 0x81C:0x8C8]
        s[:, 0x8C8:0x930] = ecc_block(work, 52, 43, 86, 88)
        sectors[form1] = s
    form2 = kinds == 3
    if form2.any():
        s = sectors[form2]
        s[:, 0x92C:0x930] = edc_rows(s[:, 0x10:0x92C]).view(np.uint8).reshape(-1, 4)
        sectors[form2] = s


def shift_table(length: int) -> list[list[int]]:
    """Byte tables for the GF(2) operator 'append `length` zero bytes' of the reflected EDC."""
    def step(v: int) -> int:
        for _ in range(8 * length):
            v = (v >> 1) ^ (0xD8018001 if v & 1 else 0)
        return v
    basis = [step(1 << k) for k in range(32)]
    tabs = []
    for byte in range(4):
        t = []
        for v in range(256):
            r = 0
            for bit in range(8):
                if v >> bit & 1:
                    r ^= basis[8 * byte + bit]
            t.append(r)
        tabs.append(t)
    return tabs


def main() -> int:
    logging.basicConfig(level=logging.INFO, format="%(message)s")
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--original-ecm", type=Path,
                        default=root / "Tekken 3 (J) [SLPS-01300]" / "Tekken 3 (J) (Track 1) [SLPS-01300].bin.ecm")
    args = parser.parse_args()
    shift = shift_table(SECTOR)
    total = 0
    with args.original_ecm.open("rb") as stream, mmap.mmap(stream.fileno(), 0, access=mmap.ACCESS_READ) as source:
        image = ECMImage(source)
        count = len(image.types)
        kinds_all = np.frombuffer(bytes(image.types), np.uint8)
        for first in range(0, count, CHUNK):
            n = min(CHUNK, count - first)
            raw = np.frombuffer(image[first * SECTOR:(first + n) * SECTOR], np.uint8).reshape(n, SECTOR).copy()
            rebuild(raw, kinds_all[first:first + n])
            crcs = edc_rows(raw)
            for c in crcs.tolist():
                total = (shift[0][total & 0xFF] ^ shift[1][total >> 8 & 0xFF] ^ shift[2][total >> 16 & 0xFF]
                         ^ shift[3][total >> 24]) ^ c
        trailer = int.from_bytes(image.trailer, "little")
    log.info("%d sectors; EDC of the decoded track %08X, ECM trailer %08X: %s", count, total, trailer,
             "match" if total == trailer else "MISMATCH")
    return 0 if total == trailer else 1


if __name__ == "__main__":
    raise SystemExit(main())
