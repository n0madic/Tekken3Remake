class_name FightMath
## Small integer routines of the fight code with the game's rounding and wrap-around, written
## from the verified ports in tools/research/fight_math.py (bit-exact in the CPU harness):
## Atan2Angle, FighterRelativeAngles' quadrant and fold, SinQ15/CosQ15, the table square root,
## TransitionRemap, MoveKeepsFrame, SegmentHitsCylinder, HitDamage and LaunchTrajectory.

const ZONE_PERCENT: Array[int] = [90, 90, 90, 90, 100, 100, 120, 120, 130, 100, 100, 140, 125, 125]
const TRIG_LIMIT := 0xFFF
const QUARTER_TURN := 0x4000       ## fight angles are 16-bit: 0x10000 per turn
const HALF_TURN := 0x8000


## FUN_8004B5E0: arctangent of x/4096 in 1/1024 of a quarter turn (s16).
static func atan_table(x: int, t: FightTables) -> int:
	var idx := absi(Fx.div_trunc(x, 4))
	var v := t.atan[idx] + (idx >> 1)
	return Fx.s16(-v if x < 0 else v)


## Atan2Angle (0x8002A478): the 16-bit angle of (dz, dx); only the low 16 bits of each count.
static func atan2_angle(dz: int, dx: int, t: FightTables) -> int:
	var z := Fx.s16(dz)
	var x := Fx.s16(dx)
	var a := absi(z) & 0xFFFF
	var b := absi(x) & 0xFFFF
	var s := 0
	if a == b:
		s = 0x200
	elif b < a:
		s = atan_table((b << 12) / a, t)
	else:
		s = Fx.s16(0x400 - atan_table((a << 12) / b, t))
	var u := (s * 16) & 0xFFFF
	var r := 0
	if z < 0:
		r = u + 0x8000 if x < 0 else -s * 16 + 0x7FFF
	else:
		r = ~u if x < 0 else u
	return r & 0xFFFF


## The quadrant of a heading difference: 0 front, 1 and 3 the sides, 2 back.
static func quadrant(delta: int) -> int:
	var q := (delta + 0x2000) & 0xFFFF
	if q < 0x4000:
		return 0
	if q < 0x8000:
		return 1
	return 2 if q < 0xC000 else 3


## |delta| of a 16-bit angle difference as the game folds it (~delta for negative values).
static func fold(delta: int) -> int:
	delta &= 0xFFFF
	return (~delta & 0xFFFF) if delta & 0x8000 else delta


## SinQ15 (0x8002A3E8) / CosQ15: sin · 0x7FF8 from the 4096-entry table.
static func sin_q15(angle: int, t: FightTables) -> int:
	return _trig(t.sin_table[((angle & 0xFFFFFFFF) >> 4) & 0xFFF])


static func cos_q15(angle: int, t: FightTables) -> int:
	return _trig(t.sin_table[(((angle & 0xFFFFFFFF) >> 4) & 0xFFF) + 1024])


static func _trig(v: int) -> int:
	v = clampi(v, -TRIG_LIMIT, TRIG_LIMIT)
	return Fx.s16((v << 19) >> 16)


## Raw 4.12 g_sinTable / g_cosTable entries (index masked to 12 bits).
static func sin12(index: int, t: FightTables) -> int:
	return t.sin_table[index & 0xFFF]


static func cos12(index: int, t: FightTables) -> int:
	return t.sin_table[(index & 0xFFF) + 1024]


## FUN_8004B174 (PsyQ SquareRoot0): leading-zero count plus a 192-entry table.
static func sqrt_table(n: int, t: FightTables) -> int:
	n = Fx.w32(n)
	if n == 0:
		return 0
	var magnitude := n if n > 0 else ~n & 0xFFFFFFFF
	var bits := 0
	while magnitude >> bits:
		bits += 1
	var lz := (32 - bits) & 0xFFFE
	var shift := 0x18 - lz
	var v := n >> shift if shift >= 0 else Fx.w32(n << -shift)
	var e := t.square_root[v - 0x40]
	return ((e << (((0x1F - lz) >> 1) & 0x1F)) & 0xFFFFFFFF) >> 12


## BranchEntersBeforeActiveEnd (0x8003127C) for the pending move.
static func enters_before_active_end(move: MoveRow, entry_frame: int) -> bool:
	return move.active_first != 0 and entry_frame + 1 < move.active_last and move.active_last <= move.length


## TransitionRemap (0x800311BC).
static func transition_remap(code: int, move: MoveRow, entry_frame: int) -> int:
	match code:
		Transition.CONTINUE:
			return Transition.CONTINUE_TRACK_SLOW if enters_before_active_end(move, entry_frame) else code
		Transition.TRACK_SLOW, Transition.TRACK_HALF, Transition.TRACK, Transition.TRACK_AIM:
			return code if move.active_first != 0 else Transition.TURN_AIM
		Transition.CONTINUE_TRACK_SLOW, Transition.CONTINUE_TRACK:
			return code if enters_before_active_end(move, entry_frame) else Transition.TURN_AIM
		Transition.CONTINUE_EASE_TURNING:
			return Transition.CONTINUE_EASE if enters_before_active_end(move, entry_frame) else code
	return code


## MoveKeepsFrame (0x800312C4) for the pending move.
static func move_keeps_frame(move: MoveRow, branch_kind: int, pose_frame: int) -> bool:
	if branch_kind == 3:
		return false
	if move.active_first == 0:
		return true
	return move.active_first <= move.length and pose_frame <= move.active_last


## SegmentHitsCylinder (0x800479A4): segment (x0, y0, z0, x1, y1, z1) against a vertical
## cylinder (cx, cy, cz, radius, radius²): bounding boxes, the clip to the slab cy ± r, then
## the horizontal distance. The perpendicular-foot products wrap to 32 bits unless `exact`
## (game bug #9, a Gameplay fix: callers pass `rules.fix_segment_hit_overflow`).
static func segment_hits_cylinder(seg: PackedInt32Array, cyl: PackedInt32Array, exact: bool) -> bool:
	var x0 := seg[0]
	var y0 := seg[1]
	var z0 := seg[2]
	var x1 := seg[3]
	var y1 := seg[4]
	var z1 := seg[5]
	var cx := cyl[0]
	var cy := cyl[1]
	var cz := cyl[2]
	var r := Fx.s16(cyl[3])
	var r2 := cyl[4]
	if (absi(x1 - x0) >> 1) + r < absi(cx - Fx.div_trunc(x0 + x1, 2)):
		return false
	if (absi(z1 - z0) >> 1) + r < absi(cz - Fx.div_trunc(z0 + z1, 2)):
		return false
	if (absi(y1 - y0) >> 1) + r < absi(cy - Fx.div_trunc(y0 + y1, 2)):
		return false
	var sx := x0
	var sz := z0
	var ex := x1
	var ez := z1
	var dx := x1 - x0
	var dy := y1 - y0
	var dz := z1 - z0
	if y0 != y1:
		var lo := cy - r
		var hi := cy + r
		if y1 < y0:
			if hi < y0:
				var t := Fx.div_trunc(Fx.w32((hi - y0) * 0x1000), dy)
				sx = x0 + Fx.trunc12(Fx.w32(t * dx))
				sz = z0 + Fx.trunc12(Fx.w32(t * dz))
			if y1 < lo:
				var t := Fx.div_trunc(Fx.w32((lo - y0) * 0x1000), dy)
				ex = x0 + Fx.trunc12(Fx.w32(t * dx))
				ez = z0 + Fx.trunc12(Fx.w32(t * dz))
		else:
			if hi < y1:
				var t := Fx.div_trunc(Fx.w32((hi - y0) * 0x1000), dy)
				ex = x0 + Fx.trunc12(Fx.w32(t * dx))
				ez = z0 + Fx.trunc12(Fx.w32(t * dz))
			if y0 < lo:
				var t := Fx.div_trunc(Fx.w32((lo - y0) * 0x1000), dy)
				sx = x0 + Fx.trunc12(Fx.w32(t * dx))
				sz = z0 + Fx.trunc12(Fx.w32(t * dz))
	var vx := ex - sx
	var vz := ez - sz
	var px := sx - cx
	var pz := sz - cz
	var length2 := Fx.w32(vx * vx + vz * vz)
	var proj := Fx.w32(-(vx * px + vz * pz))
	var d2 := 0
	if length2 == 0 or proj < 0:
		d2 = Fx.w32(px * px + pz * pz)
	elif length2 < proj:
		var qx := ex - cx
		var qz := ez - cz
		d2 = Fx.w32(qx * qx + qz * qz)
	elif exact:
		px += Fx.div_trunc(vx * proj, length2)
		pz += Fx.div_trunc(vz * proj, length2)
		d2 = px * px + pz * pz
	else:
		px += Fx.div_trunc(Fx.w32(vx * proj), length2)
		pz += Fx.div_trunc(Fx.w32(vz * proj), length2)
		d2 = Fx.w32(Fx.w32(px * px) + Fx.w32(pz * pz))
	return d2 <= r2
