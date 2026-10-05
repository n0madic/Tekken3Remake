class_name CameraView
extends RefCounted
## The active camera as `g_camera` holds it (camera.md#camera-state): pitch and yaw in 4096
## units, the eye position in world units (y down), and the projection distance H in pixels
## of the 368 × 480 display (0x800A919C).

var pitch: int
var yaw: int
var roll := 0                          ## +8: Tekken Force's last level rolls the camera
var x: int
var y: int
var z: int
var h: int
## The first view of a new shot (a reel stream starts): presentation must not interpolate
## into it. Not part of the game state (`equals` ignores it).
var cut := false


func _init(p: int = 0, w: int = 0, px: int = 0, py: int = 0, pz: int = 0, projection: int = 0) -> void:
	pitch = p
	yaw = w
	x = px
	y = py
	z = pz
	h = projection


## A copy (views kept for interpolation must not change under the holder).
func copy() -> CameraView:
	var c := CameraView.new(pitch, yaw, x, y, z, h)
	c.roll = roll
	c.cut = cut
	return c


func equals(other: CameraView) -> bool:
	return pitch == other.pitch and yaw == other.yaw and roll == other.roll and x == other.x and y == other.y \
		and z == other.z and h == other.h


func _to_string() -> String:
	return "(pitch %d, yaw %d, %d, %d, %d, H %d)" % [pitch, yaw, x, y, z, h]
