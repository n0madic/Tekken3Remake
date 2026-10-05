class_name ViewMatrix
extends RefCounted
## The camera's view matrix as `CameraBuildView` (0x80045F40) builds it from `g_camera`
## (camera.md#camera-state), and the fighters' copy of it (`FUN_80036254`). Rotation row-major
## 4.12 (row 1 scaled by 0x1BD2 / 4096 for the display aspect), translation in world units.

const ASPECT := 0x1BD2
const SCREEN_OFFSET_X := 192        ## GTE OFX of display mode 0 (FUN_800B0D08)
const SCREEN_OFFSET_Y := 240
const OVERHEAD_DEPTH := 0xA3A       ## FUN_80036254: fighters moved towards the overhead KO camera

var rot := Fx.identity()
var t := PackedInt32Array([0, 0, 0])
var h := 500                        ## the GTE projection plane of the frame


## CameraBuildView: R = Rx(−pitch) · Ry(−yaw) · Rz(−roll), row 1 scaled, t = −R · eye. The
## fight camera's roll is always 0, which makes Rz the identity.
static func build(view: CameraView, tables: FightTables) -> ViewMatrix:
	var m := ViewMatrix.new()
	var yaw := -view.yaw & 0xFFF
	var sy := FightMath.sin12(yaw, tables)
	var cy := FightMath.cos12(yaw, tables)
	var ry := PackedInt32Array([cy, 0, -sy, 0, Fx.ONE, 0, sy, 0, cy])
	if view.roll != 0:
		var roll := -view.roll & 0xFFF
		var sz := FightMath.sin12(roll, tables)
		var cz := FightMath.cos12(roll, tables)
		ry = Fx.mul_matrix(ry, PackedInt32Array([cz, -sz, 0, sz, cz, 0, 0, 0, Fx.ONE]))
	var pitch := -view.pitch & 0xFFF
	var sx := FightMath.sin12(pitch, tables)
	var cx := FightMath.cos12(pitch, tables)
	var rx := PackedInt32Array([Fx.ONE, 0, 0, 0, cx, sx, 0, -sx, cx])
	var r := Fx.mul_matrix(rx, ry)
	for k in range(3, 6):
		r[k] = Fx.s16(Fx.trunc12(r[k] * ASPECT))
	m.rot = r
	m.t = Gte.apply_lv(r, PackedInt32Array([-view.x, -view.y, -view.z]))
	m.h = view.h
	return m


## FUN_80036254: the matrix the fighters are drawn with. The overhead KO camera
## (0x800B08D4) draws them 0xA3A units closer to the eye.
func fighter_view(overhead: bool) -> ViewMatrix:
	var m := ViewMatrix.new()
	m.rot = rot
	m.t = t.duplicate()
	m.h = h
	if overhead:
		m.t[2] = Fx.w32(t[2] - OVERHEAD_DEPTH)
	return m


## FighterDrawParts → FUN_80036CFC: the screen position (x, y) and depth of a joint's origin;
## its view-space translation is FUN_8003B970's (ApplyMatrixLV plus the view translation).
func screen_of(joint: JointFrame) -> PackedInt32Array:
	var v := Gte.apply_lv(rot, joint.t)
	var tr := PackedInt32Array([Fx.w32(v[0] + t[0]), Fx.w32(v[1] + t[1]), Fx.w32(v[2] + t[2])])
	return Gte.rtps_origin(tr, h, SCREEN_OFFSET_X, SCREEN_OFFSET_Y)
