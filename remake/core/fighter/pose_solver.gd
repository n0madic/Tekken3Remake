class_name PoseSolver
extends RefCounted
## Pose vector (49 channels) → the rotations of the 18 local joint matrices.
##
## Rules from docs/research/formats/animation.md#pose-to-matrices: ten Euler
## joints, the limb basis, the normalised skeleton, and four two-bone IK limbs. The
## arithmetic follows the game's GTE rounding; results are checked against golden traces.

const SLOT_COUNT := 18
const EULER_CHANNEL := 19
const BASIS_SLOTS: Array[int] = [2, 3, 7]
const ARM_MAX_REACH := 0x215
const ARM_MIN_REACH := 0x47
const LEG_MAX_REACH := 0x37B
const LEG_MIN_REACH := 3

## Limb solve order: IK root frame, target channel, offset index, swivel channel,
## upper and lower slot, arm or leg.
enum LimbRoot { RIGHT_SHOULDER, LEFT_SHOULDER, HIPS }
const LIMBS: Array[Array] = [
	[LimbRoot.RIGHT_SHOULDER, 3, 0, 15, 4, 5, true],
	[LimbRoot.LEFT_SHOULDER, 6, 1, 16, 8, 9, true],
	[LimbRoot.HIPS, 9, 2, 17, 12, 13, false],
	[LimbRoot.HIPS, 12, 3, 18, 15, 16, false],
]

var tables: PoseTables
var wide_elbow := false             ## Gameplay fix #8: a 64-bit product for the arm bend


func _init(pose_tables: PoseTables) -> void:
	tables = pose_tables


## Writes the rotations of `slots` (18 × PackedInt32Array(9)) for one pose vector.
## Slots the IK leaves alone (targets closer than the minimum reach) keep their values.
func build(pose: PackedInt32Array, slots: Array[PackedInt32Array]) -> void:
	for j in 10:
		var c := EULER_CHANNEL + 3 * j
		slots[tables.euler_slots[j]] = euler_to_matrix(pose[c], pose[c + 1], pose[c + 2])
	for s in BASIS_SLOTS:
		slots[s] = Fx.mul_matrix(slots[s], tables.limb_basis)
	var root := JointFrame.new(slots[0], PackedInt32Array([pose[0], pose[1], pose[2]]))
	var chest := JointFrame.compose_offset(root, slots[1], tables.skeleton_offsets[0])
	var frames: Array[JointFrame] = [
		JointFrame.compose_offset(chest, slots[3], tables.skeleton_offsets[1]),
		JointFrame.compose_offset(chest, slots[7], tables.skeleton_offsets[2]),
		JointFrame.compose_offset(root, slots[11], tables.skeleton_offsets[3]),
	]
	var targets: Array[PackedInt32Array] = []
	for limb in LIMBS:
		var c: int = limb[1]
		var frame_index: int = limb[0]
		var offset_index: int = limb[2]
		var target := PackedInt32Array([pose[c], pose[c + 1], pose[c + 2]])
		targets.append(_limb_target(target, frames[frame_index], tables.limb_offsets[offset_index]))
	for i in LIMBS.size():
		var limb: Array = LIMBS[i]
		var swivel_channel: int = limb[3]
		var is_arm: bool = limb[6]
		var upper_slot: int = limb[4]
		var lower_slot: int = limb[5]
		_solve_limb(targets[i], pose[swivel_channel], is_arm, slots, upper_slot, lower_slot)


## EulerToMatrix: Rz(z)·Ry(y)·Rx(x) with the game's rounding.
func euler_to_matrix(x: int, y: int, z: int) -> PackedInt32Array:
	var sx := tables.sin16(x)
	var cx := tables.cos16(x)
	var sy := tables.sin16(y)
	var cy := tables.cos16(y)
	var sz := tables.sin16(z)
	var cz := tables.cos16(z)
	var a1 := Fx.sat16((sx * cz) >> 12)
	var a2 := Fx.sat16((sx * sz) >> 12)
	var a3 := Fx.sat16((sx * cy) >> 12)
	var cxcz := (cx * cz) >> 12
	var b1 := Fx.sat16((sy * a1) >> 12)
	var b2 := Fx.sat16((sy * a2) >> 12)
	var b3 := Fx.sat16((sy * cxcz) >> 12)
	var cxsz := (cx * sz) >> 12
	var m := PackedInt32Array()
	m.resize(9)
	m[0] = Fx.s16(Fx.sat16((cy * cz) >> 12))
	m[1] = Fx.s16(b1 - cxsz)
	m[2] = Fx.s16(a2 + b3)
	m[3] = Fx.s16(Fx.sat16((cy * sz) >> 12))
	m[4] = Fx.s16(cxcz + b2)
	m[5] = Fx.s16(((cxsz * sy) >> 12) - a1)
	m[6] = Fx.s16(-sy)
	m[7] = Fx.s16(a3)
	m[8] = Fx.s16(Fx.sat16((cy * cx) >> 12))
	return m


## IkLimbTarget: the target in the limb root's frame. The difference is rotated in two
## 15-bit halves (high·8 + low) for precision, as the game does through the GTE.
func _limb_target(target: PackedInt32Array, root: JointFrame, offset: PackedInt32Array) -> PackedInt32Array:
	var rt := Fx.transpose(root.rot)
	var hi := PackedInt32Array([0, 0, 0])
	var lo := PackedInt32Array([0, 0, 0])
	for i in 3:
		var d := target[i] - root.t[i]
		if d < 0:
			hi[i] = -((-d) >> 15)
			lo[i] = -((-d) & 0x7FFF)
		else:
			hi[i] = d >> 15
			lo[i] = d & 0x7FFF
	var low := Fx.mvmva(rt, lo[0], lo[1], lo[2])
	var out := PackedInt32Array([0, 0, 0])
	for r in 3:
		var high := Fx.sat16(rt[3 * r] * hi[0] + rt[3 * r + 1] * hi[1] + rt[3 * r + 2] * hi[2])
		out[r] = low[r] + high * 8 + offset[r]
	return out


## IkSolveLimb: aim rotation into slot `upper_slot`, bend into `lower_slot`. All products
## wrap to 32 bits like the original C code (game-bugs.md #8 relies on it for arm targets
## near 71–74).
func _solve_limb(target: PackedInt32Array, swivel: int, is_arm: bool,
		slots: Array[PackedInt32Array], upper_slot: int, lower_slot: int) -> void:
	var upper := slots[upper_slot]
	var lower := slots[lower_slot]
	_aim_and_bend(target, swivel, is_arm, upper, lower)
	slots[upper_slot] = upper
	slots[lower_slot] = lower


func _aim_and_bend(target: PackedInt32Array, swivel: int, is_arm: bool,
		upper: PackedInt32Array, lower: PackedInt32Array) -> void:
	var x := target[0]
	var y := target[1]
	var z := target[2]
	var sq := Fx.w32(x * x + y * y + z * z)
	if sq == 0:
		return
	var length := tables.square_root0(sq)
	var inv := Fx.div_trunc(0x400000, length)
	var ux := Fx.w32(x * inv) >> 10
	var uy := Fx.w32(y * inv) >> 10
	var uz := Fx.w32(z * inv) >> 10
	var k := ux + Fx.ONE
	var a: int
	var e: int
	if k == 0:
		k = -0x800
		a = Fx.w32(y * inv) >> 11
		e = -Fx.ONE
	else:
		if k < 0x2000:
			k = Fx.div_trunc(-0x1000000, k)
			a = Fx.w32(k * uy) >> 12
		else:
			k = -0x800
			a = (-uy) >> 1
		e = Fx.ONE
	var b := (Fx.w32(a * uy) >> 12) + e
	k = Fx.w32(k * uz) >> 12
	upper[0] = Fx.s16(ux)
	upper[3] = Fx.s16(uy)
	upper[6] = Fx.s16(uz)
	var c := tables.cos16(swivel)
	var s := tables.sin16(swivel)
	var p := Fx.w32(a * (e + ux)) >> 12
	var q := Fx.w32(k * (e + ux)) >> 12
	var r := Fx.w32(k * uy) >> 12
	var w := Fx.w32(a * uz) >> 12
	var v := (Fx.w32(k * uz) >> 12) + Fx.ONE
	upper[1] = Fx.s16(Fx.w32(c * p + s * q) >> 12)
	upper[4] = Fx.s16(Fx.w32(c * b + s * r) >> 12)
	upper[7] = Fx.s16(Fx.w32(c * w + s * v) >> 12)
	upper[2] = Fx.s16(Fx.w32(-s * p + c * q) >> 12)
	upper[5] = Fx.s16(Fx.w32(-s * b + c * r) >> 12)
	upper[8] = Fx.s16(Fx.w32(-s * w + c * v) >> 12)
	var d: int
	var cos_a: int
	var cos_b: int
	if is_arm:
		if length > ARM_MAX_REACH:
			_set_identity(lower)
			return
		if length < ARM_MIN_REACH:
			return
		d = (inv * 0x9204 if wide_elbow else Fx.w32(inv * 0x9204)) >> 11
		cos_a = Fx.w32((length * 0x800 + d) * 0xD9) >> 16
		cos_b = Fx.w32((length * 0x800 - d) * 0x11A) >> 16
	else:
		if length > LEG_MAX_REACH:
			_set_identity(lower)
			return
		if length < LEG_MIN_REACH:
			return
		d = Fx.w32(inv * 0x6F8) >> 11
		cos_a = Fx.w32((length * 0x800 + d) * 0x92) >> 16
		cos_b = Fx.w32((length * 0x800 - d) * 0x93) >> 16
	var sin_a := 0
	if cos_a > Fx.ONE:
		cos_a = Fx.ONE
	elif cos_a < -Fx.ONE:
		cos_a = -Fx.ONE
	else:
		sin_a = tables.square_root0(0x1000000 - cos_a * cos_a)
		if not is_arm:
			sin_a = -sin_a
	_bend(upper, Fx.s16(sin_a), cos_a)
	var sin_b := 0
	if cos_b > Fx.ONE:
		cos_b = Fx.ONE
	elif cos_b < -Fx.ONE:
		cos_b = -Fx.ONE
	else:
		sin_b = Fx.w32(sin_a * (-0x14D4 if is_arm else -0x1012)) >> 12
	var diag := Fx.s16(Fx.trunc12(Fx.w32(cos_a * cos_b + sin_a * sin_b)))
	var off := Fx.s16(Fx.trunc12(Fx.w32(-sin_a * cos_b + cos_a * sin_b)))
	lower[0] = diag
	lower[1] = Fx.s16(-off)
	lower[2] = 0
	lower[3] = off
	lower[4] = diag
	lower[5] = 0
	lower[6] = 0
	lower[7] = 0
	lower[8] = Fx.ONE


## IkBendMatrix: rotates columns 0 and 1 of the upper limb by the bend angle.
static func _bend(m: PackedInt32Array, s: int, c: int) -> void:
	var a0 := m[0]
	var a3 := m[3]
	var a6 := m[6]
	m[0] = Fx.s16((a0 * c + m[1] * s) >> 12)
	m[3] = Fx.s16((a3 * c + m[4] * s) >> 12)
	m[1] = Fx.s16((-a0 * s + m[1] * c) >> 12)
	m[4] = Fx.s16((-a3 * s + m[4] * c) >> 12)
	m[6] = Fx.s16((a6 * c + m[7] * s) >> 12)
	m[7] = Fx.s16((-a6 * s + m[7] * c) >> 12)


static func _set_identity(m: PackedInt32Array) -> void:
	for i in 9:
		m[i] = Fx.IDENTITY[i]
