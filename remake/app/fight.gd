extends Node
## The M2 build: VS fights for two players on the fight simulation (FightSimulation), from a
## temporary set-up screen (FightSetupScreen) until the game's own screens arrive in M3.
##
## Each physics tick is one simulation step with both pads' physical words; the view, the HUD
## and the pause menu read the state after it, the audio director and the pad vibration play
## its events. RESET in the pause menu, Start + Select, or the end of the match return to the
## set-up screen.
##
## Command line (after `--`): `--chars=<a>,<b>`, `--costumes=<a>,<b>`, `--stage=<n>` and
## `--fixes` preset the set-up; `--start` begins the fight at once; `--screenshot=<path>
## --frames=<n>` saves a frame after n steps and quits; `--stats` shows the frame and step timings;
## `--autoplay` starts fights by itself and presses random buttons for both players, one match after
## another (a soak test), `--speed=<n>` runs n
## steps per physics tick, `--quit-after-match` quits when the match is over and `--seed=<n>`
## fixes the match's random seed and the autoplay inputs (each fight logs its seed), `--graphics=<preset>`
## uses a graphics preset for the session.

const RESULT_HOLD := 90                     ## frames the last picture stays before the set-up

enum State { SETUP, FIGHT, OVER }

var state := State.SETUP
var content: FightContent
var effect_data: EffectData
var hud_data: HudData
var audio := AudioDirector.new()
var setup_screen := FightSetupScreen.new()
var sim: FightSimulation
var view: FightView
var hud := FightHud.new()
var pause_view := PauseMenuView.new()
var bars := FramingBars.new()
var vibration: PadVibration
var stats := Label.new()
var options := DevOptions.new()      ## --screenshot, --frames, --speed, --seed, --stats
var steps := 0
var _over_left := 0
var _step_usec := 0.0
var _start_now := false
var autoplay := false
var quit_after_match := false
var _bot := RandomNumberGenerator.new()
var _bot_pads := PackedInt32Array([0, 0])


func _ready() -> void:
	get_tree().auto_accept_quit = false
	add_child(audio)
	# The volume settings on the buses the audio director has just added.
	Settings.apply_audio()
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	layer.add_child(bars)
	layer.add_child(hud)
	layer.add_child(pause_view)
	layer.add_child(setup_screen)
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	top.add_child(stats)
	stats.position = Vector2(8, 8)
	stats.visible = false
	if not Assets.is_available():
		var label := Label.new()
		label.text = AssetCatalog.missing_message()
		layer.add_child(label)
		set_physics_process(false)
		return
	content = FightContent.load_from(AssetCatalog.ROOT)
	effect_data = EffectData.load_from(Assets.path("effects"))
	hud_data = HudData.load_from(Assets.path("hud"))
	vibration = PadVibration.new(content.tables.vibration)
	audio.use_tables(content.tables)
	setup_screen.setup(content.tables)
	setup_screen.start_requested.connect(_start_fight)
	pause_view.setup(hud)
	_parse_arguments()
	RenderQuality.apply_viewport(get_viewport())
	if _start_now:
		_start_fight.call_deferred()


func _parse_arguments() -> void:
	var args := OS.get_cmdline_user_args()
	options = DevOptions.parse(args)
	stats.visible = options.stats
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--chars="):
			for p in 2:
				setup_screen.chars[p] = clampi(value.get_slice(",", p).to_int(), 0, FightSetupScreen.CHARACTERS - 1)
		elif arg.begins_with("--costumes="):
			for p in 2:
				setup_screen.costumes[p] = clampi(value.get_slice(",", p).to_int(), 0, FightSetupScreen.COSTUMES - 1)
		elif arg.begins_with("--stage="):
			setup_screen.stage = clampi(value.to_int(), 0, FightSetupScreen.STAGES - 1)
		elif arg == "--fixes":
			setup_screen.gameplay_fixes = true
		elif arg == "--start":
			_start_now = true
		elif arg == "--autoplay":
			autoplay = true
			_start_now = true
		elif arg == "--quit-after-match":
			quit_after_match = true
	# A costume the character does not have becomes its nearest one, as on the set-up screen.
	for p in 2:
		setup_screen.costumes[p] = setup_screen.valid_costume(setup_screen.chars[p], setup_screen.costumes[p], 1)


func _start_fight() -> void:
	var s := FightSetup.new()
	s.chars = setup_screen.chars.duplicate()
	s.costumes = setup_screen.costumes.duplicate()
	s.stage = setup_screen.stage
	s.rounds = setup_screen.rounds - 1
	s.round_time = setup_screen.round_time
	s.seed = options.seed if options.seed >= 0 else Time.get_ticks_usec() & 0x7FFFFFFF
	_bot.seed = s.seed
	Log.info("fight: characters %s, costumes %s, stage %d, seed %d" % [s.chars, s.costumes, s.stage, s.seed])
	var rules := RuleSet.with_gameplay_fixes() if setup_screen.gameplay_fixes else RuleSet.original()
	sim = FightSimulation.new(content, s, rules)
	var models: Array[CharacterModel] = []
	var slots := PackedInt32Array()
	var chars := PackedInt32Array()
	for p in 2:
		var f := sim.fight.fighters[p]
		models.append(content.model(f.costume_slot))
		slots.append(f.costume_slot)
		chars.append(f.char_id)
	audio.set_fighters(slots, chars)
	var stage := content.stage_number(s.stage)
	view = FightView.new()
	add_child(view)
	view.setup(stage, effect_data, models, slots, PackedInt32Array([s.chars[0], s.chars[1]]))
	hud.setup(hud_data, slots)
	vibration.clear()
	setup_screen.visible = false
	hud.visible = true
	state = State.FIGHT


func _end_fight() -> void:
	audio.stop_all()
	vibration.clear()
	PadVibration.stop_motors()
	if view != null:
		view.queue_free()
		view = null
	sim = null
	hud.visible = false
	pause_view.visible = false
	bars.visible = false
	setup_screen.visible = true
	setup_screen.queue_redraw()
	state = State.SETUP
	if autoplay:
		_start_fight.call_deferred()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()
	elif what == NOTIFICATION_PREDELETE:
		OrphanNodes.free_all(self)


func _quit() -> void:
	audio.stop_all()
	PadVibration.stop_motors()
	set_physics_process(false)
	DevOptions.quit_after_drain(get_tree())


func _input(event: InputEvent) -> void:
	if DevOptions.toggles_stats(event):
		stats.visible = not stats.visible


func _physics_process(_delta: float) -> void:
	match state:
		State.SETUP:
			setup_screen.input(Pads.pressed[0] | Pads.pressed[1])
		State.FIGHT:
			for i in options.speed:
				if state != State.FIGHT or not _step():
					break
		State.OVER:
			_over_left -= 1
			_rumble()
			if _over_left <= 0:
				_end_fight()


## One simulation step and everything that shows it; false when stepping must stop for this
## tick (the screenshot frame).
func _step() -> bool:
	var started := Time.get_ticks_usec()
	sim.step(_bot_input() if autoplay else PackedInt32Array([Pads.held[0], Pads.held[1]]))
	_step_usec = lerpf(_step_usec, Time.get_ticks_usec() - started, 0.05)
	steps += 1
	view.apply(sim)
	hud.show_state(sim)
	pause_view.show_state(sim)
	audio.handle(sim.events)
	for e in sim.events.items:
		if e.kind == SimEvents.Kind.VIBRATE:
			vibration.vibrate(e.a, e.b)
	_rumble()
	if options.screenshot_due(steps):
		options.capture(get_viewport(), _quit)
		set_physics_process(false)
		return false
	if sim.exit_requested:
		_end_fight()
	elif sim.finished:
		_over_left = RESULT_HOLD
		state = State.OVER
		if quit_after_match:
			Log.info("match over after %d steps, result %d" % [steps, sim.fight.match_result])
			_quit()
	return true


## Random pads for `--autoplay`: a new direction and button set every few frames, never Start
## or Select (they would pause or leave).
func _bot_input() -> PackedInt32Array:
	for p in 2:
		if _bot.randi() % 6 == 0:
			var directions := PackedInt32Array([0, PadState.LEFT, PadState.RIGHT, PadState.UP, PadState.DOWN])
			var buttons := PackedInt32Array([0, PadState.SQUARE, PadState.TRIANGLE, PadState.CROSS, PadState.CIRCLE])
			_bot_pads[p] = directions[_bot.randi() % directions.size()] | buttons[_bot.randi() % buttons.size()]
	return _bot_pads


func _rumble() -> void:
	vibration.drive(Settings.flag("vibration"))


func _process(_delta: float) -> void:
	if stats.visible:
		stats.text = "%s  step %d  %.0f µs" % [options.render_stats(get_viewport()), steps, _step_usec]
	if view != null and state != State.SETUP:
		var window := get_viewport().get_visible_rect().size
		view.interpolate(options.weight(Engine.get_physics_interpolation_fraction()), window)
		bars.frame(view.rig.visible_rect, view.clear_colour)
		bars.visible = true
		hud.place(view.rig.frame_rect)
		RenderingServer.set_default_clear_color(view.clear_colour)
