class_name Gte
## The libgte routines the fighter code calls, with the GTE's integer rules
## (tools/research/projection_sim.py): matrix × vector with MAC results, the 32-bit vector variant
## that splits each component into two 15-bit halves, VectorNormal and ratan2.


## ApplyMatrix / ApplyRotMatrix: (m · v) >> 12 per row, read from the 32-bit MAC registers.
static func apply(m: PackedInt32Array, x: int, y: int, z: int) -> PackedInt32Array:
	x = Fx.s16(x)
	y = Fx.s16(y)
	z = Fx.s16(z)
	return PackedInt32Array([
		Fx.w32((m[0] * x + m[1] * y + m[2] * z) >> 12),
		Fx.w32((m[3] * x + m[4] * y + m[5] * z) >> 12),
		Fx.w32((m[6] * x + m[7] * y + m[8] * z) >> 12),
	])


## ApplyMatrixLV / ApplyRotMatrixLV: m · v for 32-bit components, as the high parts (>> 15,
## unshifted product, then << 3) plus the low 15 bits (product >> 12), signs kept.
static func apply_lv(m: PackedInt32Array, v: PackedInt32Array) -> PackedInt32Array:
	var hi := PackedInt32Array([0, 0, 0])
	var lo := PackedInt32Array([0, 0, 0])
	for k in 3:
		var c := Fx.w32(v[k])
		if c >= 0:
			hi[k] = c >> 15
			lo[k] = c & 0x7FFF
		else:
			hi[k] = -((-c) >> 15)
			lo[k] = -((-c) & 0x7FFF)
	var out := PackedInt32Array([0, 0, 0])
	for r in 3:
		var h := m[3 * r] * hi[0] + m[3 * r + 1] * hi[1] + m[3 * r + 2] * hi[2]
		var l := (m[3 * r] * lo[0] + m[3 * r + 1] * lo[1] + m[3 * r + 2] * lo[2]) >> 12
		out[r] = Fx.w32(l + (h << 3))
	return out


## VectorNormal (0x8003A86C): the vector (loaded as 16-bit) scaled to about 4096 with the
## reciprocal square root table.
static func vector_normal(v: PackedInt32Array, rsqrt: PackedInt32Array) -> PackedInt32Array:
	var x := Fx.s16(v[0])
	var y := Fx.s16(v[1])
	var z := Fx.s16(v[2])
	var sum := Fx.w32(x * x + y * y + z * z)
	if sum == 0:
		return PackedInt32Array([0, 0, 0])
	var lz := 0
	if sum >= 0:
		lz = (32 - Fx.bit_length(sum)) & 0x1E
	var shift := (31 - lz) >> 1
	var index := Fx.w32(sum << (lz - 24)) if lz >= 24 else sum >> (24 - lz)
	var ir0 := rsqrt[index - 0x40]
	return PackedInt32Array([Fx.w32(ir0 * x) >> shift, Fx.w32(ir0 * y) >> shift, Fx.w32(ir0 * z) >> shift])


## libgte ratan2(y, x): the angle of (x, y) in 4096 units from a 1,025-entry octant table.
static func ratan2(y: int, x: int, table: PackedInt32Array) -> int:
	y = Fx.w32(y)
	x = Fx.w32(x)
	var neg_x := x < 0
	var neg_y := y < 0
	x = absi(x)
	y = absi(y)
	if x == 0 and y == 0:
		return 0
	var v := 0
	if y < x:
		var t := Fx.div_trunc(Fx.w32(y << 10), x) if y & 0x7FE00000 == 0 else Fx.div_trunc(y, x >> 10)
		v = table[t]
	else:
		var t := Fx.div_trunc(Fx.w32(x << 10), y) if x & 0x7FE00000 == 0 else Fx.div_trunc(x, y >> 10)
		v = 0x400 - table[t]
	if neg_x:
		v = 0x800 - v
	if neg_y:
		v = -v
	return v


## RTPS of the vector (0, 0, 0) with the translation `tr` (sf = 1, lm = 0): the screen
## position (SX, SY, clamped to −0x400…0x3FF) and SZ3 for projection plane `h` and the
## screen offsets `ofx`, `ofy` (pixels).
static func rtps_origin(tr: PackedInt32Array, h: int, ofx: int, ofy: int) -> PackedInt32Array:
	var sz := clampi(Fx.w32(tr[2]), 0, 0xFFFF)
	var div := divide(h & 0xFFFF, sz)
	var sx := clampi((div * Fx.sat16(Fx.w32(tr[0])) + (ofx << 16)) >> 16, -0x400, 0x3FF)
	var sy := clampi((div * Fx.sat16(Fx.w32(tr[1])) + (ofy << 16)) >> 16, -0x400, 0x3FF)
	return PackedInt32Array([sx, sy, sz])


## The GTE's perspective division H / SZ3 (0.16 fixed point, at most 0x1FFFF) by the
## unsigned Newton–Raphson reciprocal (UNR table).
static func divide(h: int, sz3: int) -> int:
	if h >= sz3 * 2:
		return 0x1FFFF
	var z := 16 - Fx.bit_length(sz3)
	var n := h << z
	var d := sz3 << z
	var i := (d - 0x7FC0) >> 7
	var u := maxi(0, ((0x40000 / (i + 0x100) + 1) >> 1) - 0x101) + 0x101
	d = (0x2000080 - d * u) >> 8
	d = (0x0000080 + d * u) >> 8
	return mini(0x1FFFF, (n * d + 0x8000) >> 16)
