class_name WorldSpace
## Conversion from the game's world units to Godot space.
##
## The game uses x right, y down and z forward, in units of about one millimetre.
## Godot uses metres with y up and the camera looking along −z. The conversion
## (x, y, z) → (x, −y, −z) / 1000 is a rotation by 180° about x, so it keeps the
## handedness and the on-screen winding of the game's polygons.

const UNITS_PER_METRE := 1000.0
const ANGLE_UNITS := 4096.0          ## the game's angle units per turn


static func point(x: float, y: float, z: float) -> Vector3:
	return Vector3(x, -y, -z) / UNITS_PER_METRE


static func point_i(v: PackedInt32Array) -> Vector3:
	return point(v[0], v[1], v[2])


## A game angle (4096 units per turn) in radians.
static func radians(angle: int) -> float:
	return angle * TAU / ANGLE_UNITS


## The three rows of a joint's affine matrix in Godot space, applied to points in the
## game's part-local units: G = C·[R / 4096 | t] / 1000 with C = diag(1, −1, −1).
static func joint_rows(frame: JointFrame) -> Array[Vector4]:
	var r := frame.rot
	var k := 1.0 / (Fx.ONE * UNITS_PER_METRE)
	var s := 1.0 / UNITS_PER_METRE
	return [
		Vector4(r[0] * k, r[1] * k, r[2] * k, frame.t[0] * s),
		Vector4(-r[3] * k, -r[4] * k, -r[5] * k, -frame.t[1] * s),
		Vector4(-r[6] * k, -r[7] * k, -r[8] * k, -frame.t[2] * s),
	]
