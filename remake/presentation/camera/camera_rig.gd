class_name CameraRig
extends Node3D
## Shows the simulation's camera (CameraView) with a Godot camera, for any window shape
## (remake-plan.md#aspect-ratios).
##
## The game's view matrix is `Rx(−pitch)·Ry(−yaw)` (CameraBuildView) looking along +z with y
## down, and the projection distance H is in pixels of the 368 × 480 display, whose rows are
## scaled by 0x1BD2/4096 for the 4:3 picture: the 4:3 frame spans ±184/H horizontally and
## ±138/H vertically in view-plane units. That frame is always fully visible. A wider window
## extends it sideways (up to 21:9); a taller one extends it upwards as far as the stage's
## backdrop reaches (its coverage data) and downwards over the endless floor for the rest, so
## the 4:3 frame sits higher in a tall window. What cannot be extended is framed.

const HALF_WIDTH := 184.0            ## half the 368-pixel display width
const HALF_HEIGHT := 138.0           ## 240 display lines / 1.739
const MAX_ASPECT := 21.0 / 9.0
const NEAR := 0.05
const FAR := 400.0

var camera := Camera3D.new()
var coverage := PackedInt32Array()   ## per direction: highest covered elevation (degrees)
## The part of the window that shows the scene (normalised); the rest is framed.
var visible_rect := Rect2(0, 0, 1, 1)
## Where the original 4:3 frame lies in the window (normalised): the HUD's frame.
var frame_rect := Rect2(0, 0, 1, 1)
## The 4:3 frame's half extent in view-plane units (±184/H, ±138/H): the arcade sky's screen.
var frame_tan := Vector2(HALF_WIDTH, HALF_HEIGHT) / 500.0
var _previous: CameraView
var _current: CameraView


func _ready() -> void:
	camera.near = NEAR
	camera.far = FAR
	add_child(camera)


## A new simulation step's camera; `snap` drops interpolation (cuts).
func set_view(view: CameraView, snap: bool = false) -> void:
	_previous = view if snap or _current == null else _current
	_current = view


## Places the camera between the last two steps (`weight` 0 → previous, 1 → current).
func place(weight: float, window: Vector2) -> void:
	if _current == null:
		return
	var a := _previous
	var b := _current
	var pitch := lerp_angle(WorldSpace.radians(a.pitch), WorldSpace.radians(b.pitch), weight)
	var yaw := lerp_angle(WorldSpace.radians(a.yaw), WorldSpace.radians(b.yaw), weight)
	var eye := WorldSpace.point(lerpf(a.x, b.x, weight), lerpf(a.y, b.y, weight), lerpf(a.z, b.z, weight))
	camera.transform = Transform3D(view_basis(pitch, yaw), eye)
	_project(lerpf(a.h, b.h, weight), pitch, yaw, window)


## Camera-to-world basis in Godot space: S·Mᵀ·S with M = Rx(−pitch)·Ry(−yaw), S = diag(1, −1, −1).
static func view_basis(pitch: float, yaw: float) -> Basis:
	var cy := cos(-yaw)
	var sy := sin(-yaw)
	var cx := cos(-pitch)
	var sx := sin(-pitch)
	var y := Basis(Vector3(cy, 0, sy), Vector3(0, 1, 0), Vector3(-sy, 0, cy))      # columns
	var x := Basis(Vector3(1, 0, 0), Vector3(0, cx, -sx), Vector3(0, sx, cx))
	var m := x * y
	var s := Basis(Vector3(1, 0, 0), Vector3(0, -1, 0), Vector3(0, 0, -1))
	return s * m.transposed() * s


func _project(h: float, pitch: float, yaw: float, window: Vector2) -> void:
	var tan_x := HALF_WIDTH / h
	var tan_y := HALF_HEIGHT / h
	frame_tan = Vector2(tan_x, tan_y)
	var aspect := window.x / maxf(window.y, 1.0)
	var base := tan_x / tan_y
	if aspect >= base:
		# Wider than 4:3: extend sideways, at most to 21:9.
		camera.projection = Camera3D.PROJECTION_PERSPECTIVE
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = rad_to_deg(2.0 * atan(tan_y))
		var shown := minf(aspect, MAX_ASPECT) / aspect
		visible_rect = Rect2((1.0 - shown) / 2.0, 0, shown, 1)
		var frame_width := base / aspect
		frame_rect = Rect2((1.0 - frame_width) / 2.0, 0, frame_width, 1)
	else:
		# Taller than 4:3: upwards as far as the backdrop covers, downwards over the floor
		# for the rest of the window (an off-centre frustum).
		var window_tan := tan_x / aspect
		var up := clampf(_covered_tan(pitch, yaw, tan_x, tan_y), tan_y, window_tan)
		var down := 2.0 * window_tan - up
		camera.projection = Camera3D.PROJECTION_FRUSTUM
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.size = 2.0 * tan_x * NEAR
		camera.frustum_offset = Vector2(0, (up - down) / 2.0 * NEAR)
		visible_rect = Rect2(0, 0, 1, 1)
		var span := up + down
		frame_rect = Rect2(0, (up - tan_y) / span, 1, 2.0 * tan_y / span)


## The coverage direction the camera faces: coverage direction k points along the game's
## (cos θ, −sin θ) in x and z with θ = k·360°/count (tools/remake_import/stage.py), so θ comes
## from the view's forward vector (Godot z is the game's −z).
static func coverage_index(yaw: float, count: int) -> int:
	return roundi(coverage_angle(yaw) / TAU * count) % count


## θ of the direction the camera faces, 0 to 2π.
static func coverage_angle(yaw: float) -> float:
	var forward := -view_basis(0.0, yaw).z
	return fposmod(atan2(forward.z, forward.x), TAU)


## The covered elevation (degrees) at direction position f (θ·count/2π), linear between the
## stage's directions.
func _coverage_at(f: float) -> float:
	var count := coverage.size()
	var k := floori(f)
	return lerpf(coverage[posmod(k, count)], coverage[posmod(k + 1, count)], f - k)


## How far above the view centre (in view-plane units) the backdrop still covers, at least the
## 4:3 frame: the lowest covered elevation across the view's width (±atan(side_tan) around the
## faced direction), so no corner shows past the backdrop and turning the camera changes it
## smoothly. Pitch is positive looking down; the elevations come from the stage data.
func _covered_tan(pitch: float, yaw: float, side_tan: float, frame_tan: float) -> float:
	if coverage.is_empty():
		return INF
	# The minimum of the piecewise-linear coverage over the span: its ends and the directions
	# inside it.
	var per_radian := coverage.size() / TAU
	var centre := coverage_angle(yaw) * per_radian
	var half := atan(side_tan) * per_radian
	var lowest := minf(_coverage_at(centre - half), _coverage_at(centre + half))
	for k in range(ceili(centre - half), floori(centre + half) + 1):
		lowest = minf(lowest, coverage[posmod(k, coverage.size())])
	var limit := deg_to_rad(lowest)
	if limit >= PI / 2.0 - 0.001:
		return INF
	var room := limit + pitch            # angle between the view axis and the covered top
	return maxf(tan(clampf(room, 0.0, PI / 2.0 - 0.01)), frame_tan)
