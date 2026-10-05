class_name JointFrame
extends RefCounted
## A joint's rotation (4.12, row-major) and translation in the game's world units.

var rot: PackedInt32Array
var t: PackedInt32Array


func _init(rotation: PackedInt32Array = Fx.identity(), translation: PackedInt32Array = PackedInt32Array([0, 0, 0])) -> void:
	rot = rotation
	t = translation


## ComposeJoint / ComposeJointOffset: R = P.R·L (MVMVA per column, s16), and
## t = P.t + P.R·offset, the product read from the 32-bit MAC registers (not saturated).
## The offset is loaded into the 16-bit GTE vector registers, so it is truncated to s16.
static func compose_offset(parent: JointFrame, local_rot: PackedInt32Array, offset: PackedInt32Array) -> JointFrame:
	var r := parent.rot
	var x := Fx.s16(offset[0])
	var y := Fx.s16(offset[1])
	var z := Fx.s16(offset[2])
	var d := PackedInt32Array([
		parent.t[0] + ((r[0] * x + r[1] * y + r[2] * z) >> 12),
		parent.t[1] + ((r[3] * x + r[4] * y + r[5] * z) >> 12),
		parent.t[2] + ((r[6] * x + r[7] * y + r[8] * z) >> 12),
	])
	return JointFrame.new(Fx.mul_matrix(r, local_rot), d)
