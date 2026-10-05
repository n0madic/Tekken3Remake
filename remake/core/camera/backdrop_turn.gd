class_name BackdropTurn
extends RefCounted
## The panorama's turn (StageBackgroundDraw, FUN_8006E4A0; stages.md#panorama): each drawn frame the
## game keeps a point 4096 units ahead of the camera; while a round runs and the camera has not
## turned since the last frame (its yaw moved by at most one unit), the bearing from the camera to
## the last frame's point shows how far it slid sideways, and the backdrop turns by 2/3 of that
## (at most 0xAA units a frame). The angle turns the panorama about the fighters' midpoint.

const AHEAD_TURN_LIMIT := 0x11     ## the yaw's change (· 16) below which the camera counts as still
const TURN_DIVISOR := 0x18         ## the bearing's difference (· 16) / 24: 2/3 of it
const TURN_MAX := 0xAA
const QUARTER := 0x400

var angle := 0                     ## 0x800A9650 (4096 units)
var prev_yaw := 0                  ## 0x800A9658: the camera's yaw a frame before
var yaw := 0                       ## 0x800A9664: the camera's yaw this frame
var point_x := 0                   ## 0x800AE0D8: the point ahead of the camera
var point_z := 0                   ## 0x800AE0E0


## FUN_8006CB40 (the round start): the backdrop straight again.
func reset() -> void:
	angle = 0


## FUN_8006CC44 (StageBackgroundSetup): the backdrop straight and the camera's yaw noted as both
## this and the last frame's.
func setup(view: CameraView) -> void:
	angle = 0
	prev_yaw = view.yaw & 0xFFF
	yaw = prev_yaw


## StageBackgroundDraw's turn of this frame (the sine table is the pose tables').
func step(view: CameraView, round_state: int, poses: PoseTables, camera_tables: CameraTables) -> void:
	angle = (angle + _turn(view, round_state, poses, camera_tables)) & 0xFFF


## FUN_8006E4A0.
func _turn(view: CameraView, round_state: int, poses: PoseTables, camera_tables: CameraTables) -> int:
	var bearing := Fx.s16(CameraMath.atan2_units4096(point_x - view.x, point_z - view.z, camera_tables))
	var y := view.yaw & 0xFFF
	prev_yaw = yaw & 0xFFF
	yaw = y
	point_x = Fx.w32(poses.sin12(-y) + view.x)
	point_z = Fx.w32(poses.cos12(-y) + view.z)
	var u := (bearing - QUARTER) & 0xFFF
	if round_state == RoundState.INTRO:
		return 0
	var turned := Fx.s16(prev_yaw * 16 - y * 16)
	if turned < 0:
		turned = Fx.s16(-turned)
	if turned >= AHEAD_TURN_LIMIT:
		return 0
	var d := Fx.s16(u * 16 - y * 16)
	if d < 0:
		var q := (((y - u) * 16) & 0xFFFF) / TURN_DIVISOR
		return (-TURN_MAX if q > TURN_MAX else -q) & 0xFFF
	var q := d / TURN_DIVISOR
	return q & 0xFFF if q <= TURN_MAX else TURN_MAX
