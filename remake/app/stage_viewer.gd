extends Node
## A development viewer for the stages: the fight's stage view (FightView without fighters) seen
## from a free camera around the fighters' midpoint, with the backdrop's turn set by hand, so that
## every stage can be gone through quickly (the arcade sky and scenery, the floor, the turn).
##
## Keys: PageUp / PageDown (or , .) the stage, B Arcade / PlayStation backdrops, ← → the camera's
## yaw, ↑ ↓ its distance, W S its height, R F its pitch, Q E the backdrop's turn, Shift ×8,
## 0 resets, Space sweeps the yaw and the turn around the values set (what the label shows).
##
## Command line (after `--`): `--stage=<n>`, `--yaw=<units>`, `--turn=<units>`, `--distance=<units>`,
## `--height=<units>` (up), `--pitch=<units>`, `--sweep`, `--backdrops=<arcade|playstation>` and
## `--screenshot=<path> --frames=<n>` (a frame after n drawn frames, then quit).

const STAGES := 15
const DEFAULT_DISTANCE := 5300         ## the fight camera's distance to the midpoint
const DEFAULT_HEIGHT := 1112           ## and its height (the game's y is down)
const PROJECTION := 500
const TURN_MAX := 0xFFF
const SWEEP_TURN := 0x1DD              ## the turns the fights reach (about ±477)
const SWEEP_YAW := 0x180
const SPOT_SPREAD := 800               ## kind 1's two light points, each side of the midpoint (game units)

var content: FightContent
var effect_data: EffectData
var view: FightView
var options := DevOptions.new()
var stage := 0
var yaw := 0
var turn := 0
var distance := DEFAULT_DISTANCE
var height := DEFAULT_HEIGHT
var pitch := 0
var sweep := false
var label := Label.new()
var _steps := 0
var _frames := 0


func _ready() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	layer.add_child(label)
	label.position = Vector2(8, 8)
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	label.add_theme_constant_override("outline_size", 6)
	if not Assets.is_available():
		label.text = AssetCatalog.missing_message()
		set_process(false)
		set_physics_process(false)
		return
	content = FightContent.load_from(AssetCatalog.ROOT)
	effect_data = EffectData.load_from(Assets.path("effects"))
	_parse_arguments()
	RenderQuality.apply_viewport(get_viewport())
	_show_stage()


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	options = DevOptions.parse(args)
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--stage="):
			stage = clampi(value.to_int(), 0, STAGES - 1)
		elif arg.begins_with("--yaw="):
			yaw = value.to_int()
		elif arg.begins_with("--turn="):
			turn = value.to_int()
		elif arg.begins_with("--distance="):
			distance = value.to_int()
		elif arg.begins_with("--height="):
			height = value.to_int()
		elif arg.begins_with("--pitch="):
			pitch = value.to_int()
		elif arg == "--sweep":
			sweep = true
		elif arg.begins_with("--backdrops=") and value in Settings.choices("stage_backdrops"):
			Settings.session["stage_backdrops"] = value


## Builds the stage's view (the backdrops setting is read when a stage is set up). The old view
## leaves the tree at once, so that its environment and lights do not overlap the new ones.
func _show_stage() -> void:
	if view != null:
		remove_child(view)
		view.queue_free()
	view = FightView.new()
	add_child(view)
	view.setup(content.stage_number(stage), effect_data, [], PackedInt32Array(), PackedInt32Array())
	RenderingServer.set_default_clear_color(view.clear_colour)


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return
	var k := 8 if key.shift_pressed else 1
	match key.physical_keycode:
		KEY_PAGEUP, KEY_COMMA:
			stage = posmod(stage - 1, STAGES)
			_show_stage()
		KEY_PAGEDOWN, KEY_PERIOD:
			stage = posmod(stage + 1, STAGES)
			_show_stage()
		KEY_B:
			# Only when the arcade stages were converted (the setting offers both then).
			if "arcade" in Settings.choices("stage_backdrops"):
				var arcade: bool = Settings.text("stage_backdrops") == "arcade"
				Settings.session["stage_backdrops"] = "playstation" if arcade else "arcade"
				_show_stage()
		KEY_LEFT:
			yaw -= 16 * k
		KEY_RIGHT:
			yaw += 16 * k
		KEY_UP:
			distance -= 100 * k
		KEY_DOWN:
			distance += 100 * k
		KEY_W:
			height += 50 * k
		KEY_S:
			height -= 50 * k
		KEY_R:
			pitch -= 8 * k
		KEY_F:
			pitch += 8 * k
		KEY_Q:
			turn -= 8 * k
		KEY_E:
			turn += 8 * k
		KEY_SPACE:
			sweep = not sweep
		KEY_0:
			sweep = false
			yaw = 0
			turn = 0
			distance = DEFAULT_DISTANCE
			height = DEFAULT_HEIGHT
			pitch = 0


## One step of the stage's animation and the camera and turn for it.
func _physics_process(_delta: float) -> void:
	_steps += 1
	var shown_yaw := yaw
	var shown_turn := turn
	if sweep:
		shown_yaw += roundi(SWEEP_YAW * sin(_steps / 90.0))
		shown_turn += roundi(SWEEP_TURN * sin(_steps / 140.0))
	var angle := WorldSpace.radians(shown_yaw)
	var camera := CameraView.new(pitch & 0xFFF, shown_yaw & 0xFFF, roundi(distance * sin(angle)), -height,
			roundi(-distance * cos(angle)), PROJECTION)
	view.rig.set_view(camera, true)
	view.stage_view.follow(Vector3.ZERO)
	view.stage_view.set_floor_distance(float(distance))
	view.stage_view.set_backdrop_turn(shown_turn & TURN_MAX)
	view.stage_view.step(shown_yaw & 0xFFF)
	_spotlight()


## The spotlight floors' light points (FightView._spotlight): under the midpoint, kind 1 under two
## fighters' places.
func _spotlight() -> void:
	var kind := view.stage_view.floor_kind()
	if kind <= 0 or kind >= FightView.SPOT_K.size():
		view.stage_view.set_spotlight(0, Vector3.ZERO, Vector3.ZERO, 0, 0)
		return
	var a := Vector3.ZERO
	var b := Vector3.ZERO
	if kind == 1:
		a = WorldSpace.point(-SPOT_SPREAD, 0, 0)
		b = WorldSpace.point(SPOT_SPREAD, 0, 0)
	var limit := FightView.SPOT_LIMIT_MIDPOINT if kind == 2 else FightView.SPOT_LIMIT
	var k := FightView.SPOT_K[kind] / (WorldSpace.UNITS_PER_METRE * WorldSpace.UNITS_PER_METRE)
	view.stage_view.set_spotlight(kind, a, b, k, limit)


func _process(_delta: float) -> void:
	view.interpolate(1.0, get_viewport().get_visible_rect().size)
	var backdrops := "arcade" if view.stage_view.arcade != null else "playstation"
	label.text = "stage %d  %s  yaw %d  turn %d  distance %d  height %d  pitch %d%s" % [stage,
			backdrops, yaw, turn, distance, height, pitch, "  sweep" if sweep else ""]
	_frames += 1
	if options.screenshot_due(_frames) and not options.capturing:
		options.capture(get_viewport(), get_tree().quit)


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		OrphanNodes.free_all(self)
