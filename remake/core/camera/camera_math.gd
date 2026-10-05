class_name CameraMath
## Integer helpers of the camera code: `ISqrt` and `Atan2Units4096` with the game's
## rounding (camera.md). Ports of `fight_math.isqrt` and `fight_math.atan2_4096`.


## ISqrt (0x8002A578) of an unsigned 32-bit value: Newton iteration from a power of two.
static func isqrt(n: int) -> int:
	n &= 0xFFFFFFFF
	if n == 0:
		return 0
	var guess := 1
	var rest := n
	while guess < rest:
		guess <<= 1
		rest >>= 1
	while true:
		var prev := guess
		guess = (n / prev + prev) >> 1
		if guess >= prev:
			return prev
	return 0


## Atan2Units4096 (FUN_8004B634): the angle of (x, z) in 4096 units, as a signed 16-bit value.
static func atan2_units4096(x: int, z: int, tables: CameraTables) -> int:
	x = Fx.w32(x)
	z = Fx.w32(z)
	if x == 0 and z == 0:
		return 0
	var r := 0
	if x < 0:
		if z < 0:
			if -x < -z:
				r = 0xC00 - _octant(Fx.div_trunc(Fx.w32(x << 10), z), tables)
			else:
				r = _octant(Fx.div_trunc(Fx.w32(z << 10), x), tables) + 0x800
		elif -x < z:
			r = _octant(Fx.div_trunc(Fx.w32(x * -0x400), z), tables) + 0x400
		else:
			r = 0x800 - _octant(Fx.div_trunc(Fx.w32(z << 10), -x), tables)
	elif z < 0:
		if x < -z:
			r = _octant(Fx.div_trunc(Fx.w32(x << 10), -z), tables) + 0xC00
		else:
			r = 0x1000 - _octant(Fx.div_trunc(Fx.w32(z * -0x400), x), tables)
	elif x < z:
		r = 0x400 - _octant(Fx.div_trunc(Fx.w32(x << 10), z), tables)
	else:
		r = _octant(Fx.div_trunc(Fx.w32(z << 10), x), tables)
	return Fx.s16(r)


static func _octant(t: int, tables: CameraTables) -> int:
	return tables.atan_table[t] + (t >> 1)


## `(v < 0 ? v + 0x3F : v) >> 6`: an 18-bit camera angle back to 4096 units.
static func sar6(v: int) -> int:
	return (v + 0x3F) >> 6 if v < 0 else v >> 6
