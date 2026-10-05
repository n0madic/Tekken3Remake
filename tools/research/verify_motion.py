#!/usr/bin/env python3
"""Verify motion.py against the game's AnimDecodePose (0x80038DA0) in the CPU harness.

Usage: python3 tools/research/verify_motion.py <bank file name> ...   (names as in work/jp_rev1/bns)
Every animation stream referenced by a move row of each bank is decoded for every
frame by both implementations; all 49 channel values must match.
"""
import struct, sys, time
from psxcpu import load_release
import motion
cpu = load_release()
tab = motion.SplineTables(motion.load_exe())
BANK = 0x80140000; OUT = 0x801f0000
bad = checked = 0; t=time.time()
for name in sys.argv[1:]:
    data = open(motion.ROOT / 'work' / 'jp_rev1' / 'bns' / name, 'rb').read()
    bank = motion.parse_bank(data)
    cpu.write(BANK, data)
    offs = sorted({bank.move_row(r)[0] for r in range(bank.move_count) if bank.move_row(r)[0] < motion.COMMON_FLAG})
    for w0 in offs:
        off = bank.anim_offset(w0)
        st = motion.parse_anim(data, off)
        for f in range(st.frames):
            cpu.call(0x80038da0, BANK + off, OUT, f)
            game = list(struct.unpack('<49h', cpu.read(OUT, 98)))
            mine = motion.sample_pose(st, f, tab)
            checked += 1
            if game != mine:
                bad += 1
                if bad < 4:
                    print("mismatch", name, hex(off), f, [(i, g, m) for i, (g, m) in enumerate(zip(game, mine)) if g != m][:6])
    print(name, 'anims', len(offs), 'frames checked', checked, 'mismatches', bad, '%.1fs' % (time.time()-t))
