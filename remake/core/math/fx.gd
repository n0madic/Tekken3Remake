class_name Fx
## Integer arithmetic of the original game: 4.12 fixed point, 16-bit GTE registers and
## 32-bit C ints. Matrices are row-major PackedInt32Array(9); vectors PackedInt32Array(3).
##
## GDScript ints are 64-bit, so every place where the original relies on 16- or 32-bit
## wrap-around or GTE saturation calls the matching helper explicitly.

const ONE := 0x1000
const IDENTITY: Array[int] = [ONE, 0, 0, 0, ONE, 0, 0, 0, ONE]


## Wraps to a signed 16-bit value (a halfword store).
static func s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v & 0x8000 else v


## Wraps to a signed 8-bit value (a byte store).
static func s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v & 0x80 else v


## The number of bits needed for a non-negative value (32 minus the count of leading zeros).
static func bit_length(v: int) -> int:
	var n := 0
	while v > 0:
		v >>= 1
		n += 1
	return n


## GTE IR saturation with lm = 0.
static func sat16(v: int) -> int:
	return clampi(v, -0x8000, 0x7FFF)


## Wraps to a signed 32-bit value, as C int arithmetic on the R3000.
static func w32(v: int) -> int:
	v &= 0xFFFFFFFF
	return v - 0x100000000 if v & 0x80000000 else v


## C integer division, truncating toward zero.
static func div_trunc(a: int, b: int) -> int:
	var q := absi(a) / absi(b)
	return q if (a >= 0) == (b >= 0) else -q


## Arithmetic shift right by 12 rounding toward zero (C division by 4096).
static func trunc12(v: int) -> int:
	return (v + 0xFFF) >> 12 if v < 0 else v >> 12


static func identity() -> PackedInt32Array:
	return PackedInt32Array(IDENTITY)


## GTE MVMVA rotation × vector with sf = 1, lm = 0 (IR results, saturated).
static func mvmva(m: PackedInt32Array, x: int, y: int, z: int) -> PackedInt32Array:
	return PackedInt32Array([
		sat16((m[0] * x + m[1] * y + m[2] * z) >> 12),
		sat16((m[3] * x + m[4] * y + m[5] * z) >> 12),
		sat16((m[6] * x + m[7] * y + m[8] * z) >> 12),
	])


## GTE GPF with sf = 1, lm = 0: sat16((ir0 · v) >> 12) for three IR values.
static func mvmva_gpf(ir0: int, a: int, b: int, c: int) -> PackedInt32Array:
	var w := s16(ir0)
	return PackedInt32Array([sat16((w * s16(a)) >> 12), sat16((w * s16(b)) >> 12), sat16((w * s16(c)) >> 12)])


## libgte MulMatrix: m0 × m1, one column at a time through MVMVA, stored as s16.
static func mul_matrix(m0: PackedInt32Array, m1: PackedInt32Array) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(9)
	for c in 3:
		var col := mvmva(m0, m1[c], m1[3 + c], m1[6 + c])
		out[c] = s16(col[0])
		out[3 + c] = s16(col[1])
		out[6 + c] = s16(col[2])
	return out


static func transpose(m: PackedInt32Array) -> PackedInt32Array:
	return PackedInt32Array([m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]])
