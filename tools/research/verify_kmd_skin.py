#!/usr/bin/env python3
"""Strict check of KMD vertex and lit-colour exchange semantics against DrawSkinnedPart (0x80036F00).

Every part is drawn with lighting on and random light matrices; the vertex slots (packed XY, Z)
and the colour slots (scratchpad 0x1F800290, global 0x8009D8F8) are compared with the model.

Usage: python3 tools/research/verify_kmd_skin.py [max_models]
"""
import struct, sys, random
from psxcpu import load_release, GTE, s16, s32
import kmd as kmdlib
W = str(__import__('pathlib').Path(__file__).resolve().parents[2] / 'work' / 'jp_rev1' / 'bns') + '/'
KMD = 0x80150000; FIGHTER = 0x801a0000; PRIM = 0x80160000; OT = 0x801c0000
SCR_XY = 0x1f800000; SCR_Z = 0x1f8001b8
GLB_XY = 0x8009c0f4; GLB_Z = 0x8009d0f6
SCR_COL = 0x1f800290; GLB_COL = 0x8009d8f8; BASE_RGB = 0x800ae2e4
NCCS, NCCT = 0x0108041b, 0x0118043f

def rot_matrix(rng):
    import math
    a, b, c = [rng.uniform(-0.6, 0.6) for _ in range(3)]
    ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
    m = [[cb*cc, sb*sa*cc-ca*sc, sa*sc+sb*ca*cc], [cb*sc, ca*cc+sb*sa*sc, ca*sc*sb-sa*cc], [-sb, sa*cb, ca*cb]]
    return [[int(round(v*4096)) for v in r] for r in m]

def set_gte(g, m, t):
    pk = lambda a, b: (a & 0xffff) | (b & 0xffff) << 16
    g.c[0] = pk(m[0][0], m[0][1]); g.c[1] = pk(m[0][2], m[1][0]); g.c[2] = pk(m[1][1], m[1][2])
    g.c[3] = pk(m[2][0], m[2][1]); g.c[4] = m[2][2] & 0xffff
    g.c[5], g.c[6], g.c[7] = [v & 0xffffffff for v in t]
    g.c[24] = 160 << 16; g.c[25] = 120 << 16; g.c[26] = 700

def set_light(rng, *gtes):
    """Random light (c8..c12) and colour (c16..c20) matrices, back colour c13..c15."""
    rnd = lambda: rng.randint(-4096, 4096) & 0xffff
    vals = {k: rnd() | rnd() << 16 for k in (8, 9, 10, 11, 16, 17, 18, 19)}
    vals[12] = rnd(); vals[20] = rnd()
    for k in (13, 14, 15):
        vals[k] = rng.randint(0, 0x1000)
    for g in gtes:
        for k, v in vals.items():
            g.c[k] = v

def lit(g, normals, rgb):
    """Colours of the normals in the game's order: NCCT per three, then NCCS for the rest."""
    out = []
    i = 0
    while len(normals) - i >= 3:
        for k in range(3):
            x, y, z = normals[i + k]
            g.d[2 * k] = (x & 0xffff) | (y & 0xffff) << 16; g.d[2 * k + 1] = z & 0xffff
        g.d[6] = rgb; g.command(NCCT)
        out += [g.d[20], g.d[21], g.d[22]]; i += 3
    while i < len(normals):
        x, y, z = normals[i]
        g.d[0] = (x & 0xffff) | (y & 0xffff) << 16; g.d[1] = z & 0xffff
        g.d[6] = rgb; g.command(NCCS)
        out.append(g.d[22]); i += 1
    return out

def half_xy(v): return ((s32(v) >> 1) & 0xffff7fff) & 0xffffffff
def half_z(z): return z >> 1

def run(name, seed):
    rng = random.Random(seed)
    data = open(W + name, 'rb').read()
    model = kmdlib.parse(data)
    cpu = load_release()
    cpu.write(KMD, data); cpu.write(FIGHTER, bytes(0x2000))
    cpu.call(0x80035138, KMD, 27, FIGHTER)
    g = GTE()
    glob_xy = {}; glob_z = {}
    scr_xy = {}; scr_z = {}
    scr_col = {}; glob_col = {}; touched_glob = set()
    mism = 0; parts = 0
    for k, ri in enumerate(kmdlib.PART_ROW):
        row = model.rows[ri]
        if row.verts is None: continue
        m = rot_matrix(rng); t = (rng.randint(-300, 300), rng.randint(-300, 300), 4000 + rng.randint(-300, 300))
        set_gte(cpu.gte, m, t); set_gte(g, m, t); set_light(rng, cpu.gte, g)
        rgb = 0x3c000000 | rng.randrange(1 << 24)
        cpu.write(BASE_RGB, struct.pack('<I', rgb))
        cpu.call(0x80036f00, KMD + 0x10 + ri * 0x38, PRIM, OT, 1)
        colour_slots = colour_model(row.normals, g, rgb, scr_col, glob_col, touched_glob) if row.normals else 0
        # ---- python model ----
        vb = row.verts; cur = 0
        for idx in vb.import_scratch:
            s = idx // 2 - 1
            scr_xy[cur], scr_z[cur] = scr_xy.get(s, 0), scr_z.get(s, 0); cur += 1
        for idx in vb.import_global:
            scr_xy[cur], scr_z[cur] = glob_xy.get(idx, 0), glob_z.get(idx, 0); cur += 1
        for x, y, z in vb.coords:
            g.d[0] = (x & 0xffff) | (y & 0xffff) << 16; g.d[1] = z & 0xffff
            g.command(0x00080001)  # RTPS sf=1
            scr_xy[cur] = g.d[14]; scr_z[cur] = s16((g.d[19] & 0xffff) >> 5); cur += 1
        cur = len(vb.import_scratch) + len(vb.import_global)
        blend_a, add_g, add_s, exp_g, exp_s, halve = vb.post
        for e in blend_a:
            idx, fl = e & 0xff, e & 0x100
            oz, oxy = (half_z(scr_z[cur]), half_xy(scr_xy[cur])) if fl else (scr_z[cur], scr_xy[cur])
            z = s16(oz + glob_z.get(idx, 0)); xy = (oxy + glob_xy.get(idx, 0)) & 0xffffffff
            scr_z[cur] = glob_z[idx] = z; scr_xy[cur] = glob_xy[idx] = xy; cur += 1
        for lst, bz, bxy, conv in ((add_g, glob_z, glob_xy, lambda i: i), (add_s, scr_z, scr_xy, lambda i: i // 2 - 1)):
            for e in lst:
                idx, fl = conv(e & 0xff), e & 0x100
                oz, oxy = (half_z(scr_z[cur]), half_xy(scr_xy[cur])) if fl else (scr_z[cur], scr_xy[cur])
                scr_z[cur] = s16(bz.get(idx, 0) + oz); scr_xy[cur] = (bxy.get(idx, 0) + oxy) & 0xffffffff; cur += 1
        for lst, bz, bxy, conv in ((exp_g, glob_z, glob_xy, lambda i: i), (exp_s, scr_z, scr_xy, lambda i: i // 2 - 1)):
            for e in lst:
                idx, fl = conv(e & 0xff), e & 0x100
                if fl: scr_z[cur] = half_z(scr_z[cur]); scr_xy[cur] = half_xy(scr_xy[cur])
                bz[idx] = scr_z[cur]; bxy[idx] = scr_xy[cur]; cur += 1
        for code in halve:
            if code != 1: scr_z[cur] = half_z(scr_z[cur]); scr_xy[cur] = half_xy(scr_xy[cur])
            cur += 1
        n = len(vb.import_scratch) + len(vb.import_global) + len(vb.coords)
        game_xy = struct.unpack(f'<{n}I', cpu.read(SCR_XY, 4 * n)); game_z = struct.unpack(f'<{n}h', cpu.read(SCR_Z, 2 * n))
        bad = [i for i in range(n) if game_xy[i] != scr_xy[i] or game_z[i] != scr_z[i]]
        if colour_slots:
            top = max(max(scr_col, default=0) + 1, colour_slots)
            game_col = struct.unpack(f'<{top}I', cpu.read(SCR_COL, 4 * top))
            bad += [('col', i) for i in scr_col if game_col[i] != scr_col[i]]
            STATS['colour slots'] += len(scr_col); STATS['distinct colours'] |= set(scr_col.values())
            for i in touched_glob:
                if struct.unpack('<I', cpu.read(GLB_COL + 4 * i, 4))[0] != glob_col[i]:
                    bad.append(('gcol', i))
        parts += 1
        if bad:
            mism += 1
            print(name, 'part', k, 'row', ri, 'slots', n, 'mismatch', len(bad), 'first', bad[:5])
    return parts, mism

def colour_model(nb, g, rgb, scr_col, glob_col, touched_glob):
    """Imports into colour slots 1.., lit normals after them, then the two export lists.
    List entries are halfword offsets (slot = entry / 2); `lead` is the byte offset of the
    first lit colour (4 * (1 + imports))."""
    cur = 1
    for idx in nb.import_scratch:
        scr_col[cur] = scr_col.get(idx // 2, 0); cur += 1
    for idx in nb.import_global:
        scr_col[cur] = glob_col.get(idx // 2, 0); cur += 1
    for c in lit(g, nb.coords, rgb):
        scr_col[cur] = c; cur += 1
    end = cur
    src = nb.lead // 4
    to_glob, to_scr = nb.post
    for idx in to_glob:
        glob_col[idx // 2] = scr_col[src]; touched_glob.add(idx // 2); src += 1
    for idx in to_scr:
        scr_col[idx // 2] = scr_col[src]; src += 1
    return end

STATS = {'colour slots': 0, 'distinct colours': set()}

import glob, os
tot = [0, 0]
for path in sorted(glob.glob(W + '*.kmd'))[: int(sys.argv[1]) if len(sys.argv) > 1 else 999]:
    p, m = run(os.path.basename(path), 7)
    tot[0] += p; tot[1] += m
print('parts', tot[0], 'parts with mismatching slots', tot[1],
      '| colour slots compared', STATS['colour slots'], 'distinct values', len(STATS['distinct colours']))
