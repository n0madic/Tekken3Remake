class_name TiledPanorama
extends Control
## The screen-space backdrops of the tile-map stages, drawn behind the 3D scene (a canvas layer
## the environment shows as its background):
##
## - Tekken Ball (volley.ovl FUN_800B5F0C, `background_draw` in tools/research/ball_sim.py): 32-pixel
##   tiles scrolling with the camera's view-space position and yaw, the map's top edge on the
##   projected horizon, a sky-coloured tile above it;
## - Tekken Force (force.ovl FUN_800B4DF8, `background_draw` in tools/research/force_sim.py): 64-pixel
##   tiles scrolling with the camera's view-space x, climbing every third column on the fourth
##   level (with black gates at the map's first column), a black tile over the ground there and
##   only that tile in the Doctor B. level.
##
## Positions are the game's 384 × 480 frame-buffer units (the 368 shown columns start at x = 8),
## laid into the scene's 4:3 frame and continued sideways over a wider window.

const BALL_SKY := Color8(0x21, 0x3A, 0x94)
const BALL_SCROLL_DIV := 0x60
const BALL_REACH := 0x1A00             ## the horizon point ahead of the camera
const BALL_HORIZON_Y := 0x100
const BALL_FIRST := 2                  ## map columns left of the screen: 2, 16 at the result, 10 later
const FORCE_SCROLL_DIV := 0x14
const FORCE_HORIZON_Z := 0x9C4
const FORCE_SLOPE := 0xD8              ## the fourth level's climb (4096 units)
const FORCE_SLOPE_LEVEL := 3
const FORCE_GROUND := Rect2(0, 0x14, 0x110, 0x64)
const FORCE_GATE := Vector2(0x40, 0x20)
const SCREEN_TOP := 0x14               ## FUN_80029860's display rectangle
const SCREEN_HEIGHT := 0x1C0

var picture: Texture2D
var tile := 32
var map_width := 1                     ## cells
var map_height := 1
var ball := true
var level := 0                         ## Tekken Force: the level (stage − 15)
var frame_rect := Rect2(0, 0, 1, 1)    ## the 4:3 frame in the window (normalised)
var shown := true
var _tables: FightTables
var _yaw_ref := 0
var _last_kind := -1
var _scroll := PackedFloat32Array([0, 0])   ## previous and current step
var _top := PackedFloat32Array([0, 0])
var _started := false                  ## the first step starts at its own scroll, not at 0
var _shift := 0                        ## extra map columns (Tekken Ball's result and replays)
var _tile_only := false
var _weight := 1.0
## The line past which the map covers the floor (StageView.set_floor_edge): the ground under the
## map's bottom edge, across the view.
var floor_edge := Vector3(0, 0, 1.0e9)


func setup(stage: StageData, tables: FightTables) -> void:
	_tables = tables
	var map := stage.tile_map
	picture = TexturePacks.texture(stage.directory.path_join(str(map["picture"])))
	tile = JsonFile.number(map["tile"])
	map_width = JsonFile.number(map["width"])
	map_height = JsonFile.number(map["height"])
	ball = stage.number == ModeRules.TEKKEN_BALL_STAGE
	level = stage.number - ModeRules.FORCE_FIRST_STAGE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## After a simulation step: the scroll and the map's top edge of this frame.
func step(sim: FightSimulation) -> void:
	var view := sim.camera.view
	var m := ViewMatrix.build(view, _tables)
	var eye := Gte.apply_lv(m.rot, PackedInt32Array([view.x, view.y, view.z]))
	var scroll := 0
	var top := 0
	var fight := sim.fight
	if ball:
		var kind := fight.region.ctx32(TekkenBall.LAST_POINT)
		shown = kind != 1
		if kind != _last_kind:
			_yaw_ref = view.yaw
		_last_kind = kind
		var yaw := view.yaw & 0xFFF
		var c := FightMath.cos12(yaw, _tables)
		var s := FightMath.sin12(yaw, _tables)
		scroll = (Fx.div_trunc(Fx.w32(eye[0] * c + eye[2] * s), BALL_SCROLL_DIV) >> 12) + (Fx.w32(_yaw_ref - view.yaw) >> 1)
		var horizon := PackedInt32Array([Fx.w32(view.x - s * BALL_REACH) >> 12, BALL_HORIZON_Y,
			Fx.w32(view.z + c * BALL_REACH) >> 12])
		top = _screen_y(m, horizon) - map_height * tile
		var forward := Vector2(-s, -c).normalized()
		var at := Vector2(horizon[0], -horizon[2]) / WorldSpace.UNITS_PER_METRE
		floor_edge = Vector3(forward.x, forward.y, forward.dot(at))
		_shift = 0
		if fight.round_state == RoundState.RESULT and kind != 0:
			_shift = 14
		elif fight.round_state >= RoundState.REPLAY:
			_shift = 8
	else:
		scroll = Fx.div_trunc(eye[0], FORCE_SCROLL_DIV)
		top = _screen_y(m, PackedInt32Array([view.x, 0, FORCE_HORIZON_Z])) - map_height * tile
		floor_edge = Vector3(0, -1, FORCE_HORIZON_Z / WorldSpace.UNITS_PER_METRE)
		_tile_only = fight.force != null and fight.force.gu32(TekkenForce.TILE_ONLY) != 0
		shown = true
	var period := map_width * tile
	scroll = posmod(scroll, period)
	if not _started:
		_scroll[1] = scroll
		_top[1] = top
		_started = true
	_scroll[0] = _scroll[1]
	_top[0] = _top[1]
	# A jump of more than half the map is a wrap: continue from the nearer image.
	var d := scroll - _scroll[0]
	if absf(d) > period / 2.0:
		_scroll[0] += period * signf(d)
	_scroll[1] = scroll
	_top[1] = top


func _screen_y(m: ViewMatrix, point: PackedInt32Array) -> int:
	var v := Gte.apply_lv(m.rot, point)
	var tr := PackedInt32Array([Fx.w32(v[0] + m.t[0]), Fx.w32(v[1] + m.t[1]), Fx.w32(v[2] + m.t[2])])
	return Fx.s16(Gte.rtps_origin(tr, m.h, ViewMatrix.SCREEN_OFFSET_X, ViewMatrix.SCREEN_OFFSET_Y)[1])


## Every rendered frame: between the last two steps.
func show_between(weight: float, frame: Rect2) -> void:
	_weight = weight
	frame_rect = frame
	queue_redraw()


func _point(x: float, y: float) -> Vector2:
	var box := Rect2(frame_rect.position * size, frame_rect.size * size)
	return HudFrame.point(box, x, y)


func _rect(x: float, y: float, w: float, h: float) -> Rect2:
	var a := _point(x, y)
	return Rect2(a, _point(x + w, y + h) - a)


## The window's left and right edges in frame-buffer units.
func _extent() -> Vector2:
	var box := Rect2(frame_rect.position * size, frame_rect.size * size)
	if box.size.x <= 0:
		return Vector2(HudFrame.LEFT, HudFrame.LEFT + ScreenCanvas.SCREEN.x)
	var unit := ScreenCanvas.SCREEN.x / box.size.x
	return Vector2(HudFrame.LEFT - box.position.x * unit, HudFrame.LEFT + (size.x - box.position.x) * unit)


func _draw() -> void:
	if picture == null or not shown:
		return
	var scroll := lerpf(_scroll[0], _scroll[1], _weight)
	var top := lerpf(_top[0], _top[1], _weight)
	var span := _extent()
	if ball:
		_draw_ball(scroll, top, span)
	else:
		_draw_force(scroll, top, span)


func _draw_ball(scroll: float, top: float, span: Vector2) -> void:
	# The sky from the display's top down to the map's top edge (the whole screen when the
	# map is below it).
	var sky_bottom := minf(top, SCREEN_HEIGHT) + SCREEN_TOP
	draw_rect(_rect(span.x, 0, span.y - span.x, sky_bottom), BALL_SKY)
	# Screen x shows map pixel scroll + 32 · (first column) + x.
	var origin := scroll + tile * (BALL_FIRST + _shift)
	_draw_rows(origin, top, span)


func _draw_force(scroll: float, top: float, span: Vector2) -> void:
	var sloped := level == FORCE_SLOPE_LEVEL
	if sloped or _tile_only:
		var ground := FORCE_GROUND
		if _tile_only:
			ground = Rect2(0, FORCE_GROUND.position.y, ScreenCanvas.SCREEN.x, top + map_height * tile - 0x10)
			draw_rect(_rect(span.x, ground.position.y, span.y - span.x, ground.size.y), Color.BLACK)
			return
		draw_rect(_rect(ground.position.x, ground.position.y, ground.size.x, ground.size.y), Color.BLACK)
	if not sloped:
		_draw_rows(scroll, top, span)
		return
	# The fourth level climbs: every third column rises by 192 · tan(slope), from a phase that
	# keeps the steps in place on the map.
	var angle := WorldSpace.radians(FORCE_SLOPE)
	var rise := 192.0 * tan(angle)
	var phase := 0xB8 - (floorf(scroll / 192.0) * 192.0 - scroll)
	var y0 := top + phase * tan(angle)
	var first := floori((span.x - (floorf(scroll / tile) * tile - scroll)) / tile) - 1
	var last := ceili((span.y - (floorf(scroll / tile) * tile - scroll)) / tile) + 1
	var column0 := floori(scroll / tile)
	var x0 := column0 * tile - scroll
	for row in map_height:
		for c in range(first, last):
			var map_col := column0 + c
			var steps := floori(float(map_col) / 3.0) - floori(float(column0) / 3.0)
			var y := y0 + row * tile - steps * rise
			var x := x0 + c * tile
			_draw_cell(posmod(map_col, map_width), row, x, y)
			if row == map_height - 1 and posmod(map_col, map_width) == 0:
				draw_rect(_rect(x, y + 0x40, FORCE_GATE.x, FORCE_GATE.y), Color.BLACK)


## Straight rows: screen x shows map pixel origin + x.
func _draw_rows(origin: float, top: float, span: Vector2) -> void:
	var column0 := floori(origin / tile)
	var x0 := column0 * tile - origin
	var first := floori((span.x - x0) / tile)
	var last := ceili((span.y - x0) / tile)
	for row in map_height:
		var y := top + row * tile
		if y < -tile or y > ScreenCanvas.SCREEN.y:
			continue
		for c in range(first, last):
			_draw_cell(posmod(column0 + c, map_width), row, x0 + c * tile, y)


func _draw_cell(column: int, row: int, x: float, y: float) -> void:
	var source := Rect2(column * tile, row * tile, tile, tile)
	# Half a texel of overlap hides the seams of the scaled tiles.
	var r := _rect(x, y, tile, tile).grow(0.5)
	draw_texture_rect_region(picture, r, source)
