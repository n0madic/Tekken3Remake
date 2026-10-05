extends Node3D
## M0 test scene: one character on one stage, animated by the simulation core.
##
## Pad: L1 / R1 previous / next move slot, Triangle pause, Cross / Circle held run the small /
## large motor, right stick or mouse drag orbits the camera.
## Command line (after `--`): `--screenshot=<path>` saves
## the frame after `--frames=<n>` physics frames and quits; `--slot=<n>` picks the move;
## `--yaw=`, `--pitch=` (radians) and `--distance=` (metres) place the camera; `--costume=<key>`
## shows another costume (character · 4 + costume); `--hand=<value>[,<value 1>]` holds both hand channels
## at a channel value (0 open, 0x200 fist, 0x201 and up shapes; decimal or `0x` hex; the jaw of Kuma, Panda
## and Gon is channel 0), or channel 0 at the first and channel 1 at the second; `--gaze=<shift>` holds
## Gon's eyes' look direction (−17 to 17).

const DEFAULT_COSTUME := 0            ## Paul's first costume
const STAGE := "e"                    ## the attract demonstration's stage (stage 4)
const START_SLOT := 3                 ## standing stance
const SLOT_COUNT := 4023
const ORBIT_TARGET := Vector3(0, 1.0, 0)
const ORBIT_DISTANCE := 3.4
const ORBIT_SPEED := 1.6
const RUMBLE_LARGE := 160

var skeleton: FighterSkeleton
var model_name := ""
var motions: MotionSet
var blinker := Blinker.new()
var move: MotionSet.Ref
var fighter := FighterView.new()
var hands := FighterHands.new()
var gaze_value := 0                   ## --gaze: Gon's eyes' look direction
var hand_values := PackedInt32Array()  ## --hand: the channel value each hand is held at, none if empty
var stage_view := StageView.new()
var lighting := StageLighting.new()
var camera := Camera3D.new()
var info := Label.new()
var slot := START_SLOT
var costume_key := DEFAULT_COSTUME
var anim: MotionSet.Ref
var frame := 0
var paused := false
var yaw := 0.6
var pitch := 0.12
var distance := ORBIT_DISTANCE
var step_usec := 0
var frames_run := 0
var options := DevOptions.new()      ## --screenshot, --frames


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		OrphanNodes.free_all(self)


func _ready() -> void:
	_parse_arguments()
	_build_environment()
	add_child(info)
	info.position = Vector2(12, 8)
	if not Assets.is_available():
		info.text = AssetCatalog.missing_message()
		return
	var content := FightContent.load_from(AssetCatalog.ROOT)
	var record := content.tables.character(costume_key)
	motions = MotionSet.new(content.bank(JsonFile.number(record["bank"])), content.common)
	var model := content.model(content.tables.fighter.costume_keys[costume_key])
	model_name = model.name
	var tables := PoseTables.load_from(Assets.path("tables/pose.json"))
	skeleton = FighterSkeleton.new(tables, model, content.tables.fighter)
	fighter.setup(model)
	add_child(fighter)
	# The attract demonstration's stage and light rig, as EnbuView draws them.
	var stage := StageData.load_from(Assets.path("stages/" + STAGE))
	stage_view.setup(stage)
	add_child(stage_view)
	lighting.setup(stage, camera)
	stage_view.apply_environment(lighting.environment)
	add_child(lighting)
	fighter.set_lighting(StageLighting.fighter_parameters(stage))
	_select_slot(slot, 1)


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	options = DevOptions.parse(args)
	for arg in args:
		if arg.begins_with("--slot="):
			slot = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--yaw="):
			yaw = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--pitch="):
			pitch = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--distance="):
			distance = arg.get_slice("=", 1).to_float()
		elif arg.begins_with("--costume="):
			costume_key = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--gaze="):
			gaze_value = arg.get_slice("=", 1).to_int()
		elif arg.begins_with("--hand="):
			for text in arg.get_slice("=", 1).split(","):
				hand_values.append(text.hex_to_int() if text.begins_with("0x") else text.to_int())
			if hand_values.size() == 1:
				hand_values.append(hand_values[0])


func _build_environment() -> void:
	camera.far = 400.0
	add_child(camera)
	_place_camera()


func _physics_process(delta: float) -> void:
	if skeleton == null:
		return
	_handle_pads(delta)
	if not paused:
		var start := Time.get_ticks_usec()
		var pose := anim.bank.pose(anim.value, frame)
		skeleton.update(pose, PackedInt32Array([0, 0, 0]), 0, 0)
		step_usec = Time.get_ticks_usec() - start
		fighter.set_joints(skeleton.joints)
		if not hand_values.is_empty():
			for channel in FighterHands.CHANNELS:
				hands.current[channel] = hand_values[channel]
				hands.variant[channel] = FighterHands.variant_of(hand_values[channel])
			fighter.set_hands(hands)
		fighter.set_gaze(gaze_value)
		var flags := move.bank.move_flags(move.value)
		var state: int = move.bank.moves[move.value][1]
		if fighter.face != null:
			fighter.step_face(Blinker.held(flags), Blinker.lying(flags, state))
		else:
			fighter.set_eyes_closed(blinker.step(flags, state))
		frame = (frame + 1) % anim.bank.frame_count(anim.value)
	frames_run += 1
	_update_info()
	if options.screenshot_due(frames_run):
		options.capture(get_viewport(), get_tree().quit)
		set_physics_process(false)     # the saved frame is this one


func _handle_pads(delta: float) -> void:
	for player in InputRouter.PLAYERS:
		var pressed := Pads.pressed[player]
		if pressed & PadState.R1:
			_select_slot(slot + 1, 1)
		if pressed & PadState.L1:
			_select_slot(slot - 1, -1)
		if pressed & PadState.TRIANGLE:
			paused = not paused
		Pads.set_motors(player, Pads.held[player] & PadState.CROSS != 0, RUMBLE_LARGE if Pads.held[player] & PadState.CIRCLE else 0)
		var device := Pads.devices[player]
		if device >= 0:
			yaw -= Input.get_joy_axis(device, JOY_AXIS_RIGHT_X) * ORBIT_SPEED * delta
			pitch = clampf(pitch + Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y) * ORBIT_SPEED * delta, -0.3, 1.5)
	_place_camera()


func _unhandled_input(event: InputEvent) -> void:
	var drag := event as InputEventMouseMotion
	if drag != null and drag.button_mask & MOUSE_BUTTON_MASK_LEFT:
		yaw -= drag.relative.x * 0.01
		pitch = clampf(pitch + drag.relative.y * 0.01, -0.3, 1.5)


## Moves to the next slot in `direction` that has an animation.
func _select_slot(start: int, direction: int) -> void:
	var s := posmod(start, SLOT_COUNT)
	for i in SLOT_COUNT:
		var found := motions.anim_for_slot(s)
		if found != null:
			slot = s
			anim = found
			move = motions.move_for_slot(s)
			frame = 0
			return
		s = posmod(s + direction, SLOT_COUNT)


func _place_camera() -> void:
	var offset := Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
	camera.position = ORBIT_TARGET + offset
	camera.look_at(ORBIT_TARGET)
	# The arcade stage's sky follows the view.
	stage_view.set_view_pitch(StageView.camera_pitch(camera))


func _update_info() -> void:
	var lines := PackedStringArray([
		"%s  slot %d (%s)  frame %d / %d%s" % [model_name, slot, anim.bank.name, frame, anim.bank.frame_count(anim.value), "  [paused]" if paused else ""],
		"pose + joints: %d µs   fps: %d" % [step_usec, Engine.get_frames_per_second()],
	])
	for player in InputRouter.PLAYERS:
		lines.append("P%d %s: %s" % [player + 1, Pads.device_name(player), PadState.describe(Pads.held[player])])
	lines.append("L1/R1 move   Triangle pause   Cross/Circle rumble   right stick or drag: camera")
	info.text = "\n".join(lines)
