extends Node
## The game from MAME's set alone, no disc (`manifest.source` "arcade"): the frame loop of
## ArcadeGameFlow, the arcade's own screens over the shared fight view. game.gd comes here at once
## when the conversion is the arcade's, so nothing of the PlayStation's flow, modes or fighters runs.
##
## Each physics tick is one step with both panels' words (ArcadeInput.panel_word of the pads). The
## command line takes `--screenshot=<path>`, `--frames=<n>`, `--speed=<n>`, `--seed=<n>`, `--stats`
## and `--pads=<file>` as the PlayStation game's does, and `--day=<n>` the operator's day counter
## that opens the fighters (default: all of them). `--ladder-from=<n>` is for development: the ladder
## goes on from fight n, the CPU's fighters at one point of life, a quick way to its last fights and
## the ending.
## `--no-movies` plays as a build without movies does. The records stay in SaveStore's file between
## runs; `--fresh`, a pad script, a screenshot or `--ladder-from` neither read nor write it.

## Without these the game cannot run; the sounds' absence only silences it.
const REQUIRED := ["screens", "hud"]
const DAY_ALL_OPEN := 120
const MESSAGE_SHARE := 0.035
const MESSAGE_MIN_SIZE := 18

var flow: ArcadeGameFlow
var content: ArcadeFightContent
var effect_data: EffectData
var hud_data: HudData
var screen_data: ArcadeScreenData
var fight_view: FightView
var backdrop: StageBackdrop
var bars := FramingBars.new()
var hud := ArcadeFightHud.new()
var screens := ArcadeScreens.new()
var fade := FadeOverlay.new()
var audio := ArcadeAudio.new()
var message := Label.new()
var stats := Label.new()
var touch := TouchControls.new()
var settings_view := SettingsView.new()
var settings_button := SettingsButton.new()
var options := DevOptions.new()
var day := DAY_ALL_OPEN
var steps := 0
var _pad_script: Array[Vector2i] = []
var _fight_loads := -1
var _model_loads := PackedInt32Array()
var _step_usec := 0.0
var _previous_pads := 0
var _release_pads := false
var _skip_movies := false
var _vblanks_left := 0
var _ladder_from := -1
var _fresh := false
var _keeps_records := false
var _store := SaveStore.new()
var _saved_records := {}
var _shown_state := -1


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	options = DevOptions.parse(args)
	stats.visible = options.stats
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg.begins_with("--pads="):
			_load_pad_script(value)
		elif arg.begins_with("--day="):
			day = value.to_int()
		elif arg == "--no-movies":
			_skip_movies = true
		elif arg == "--fresh":
			_fresh = true
		elif arg.begins_with("--ladder-from="):
			_ladder_from = value.to_int()
	get_tree().auto_accept_quit = false
	add_child(audio)
	Settings.apply_audio()
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	for view: Control in [bars, hud, screens]:
		layer.add_child(view)
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	for view: Control in [fade, message, stats, touch, settings_button, settings_view]:
		top.add_child(view)
	settings_view.closed.connect(_on_settings_closed)
	settings_button.pressed.connect(_open_settings)
	Settings.changed.connect(_on_setting_changed)
	RenderQuality.apply_viewport(get_viewport())
	TranslationServer.set_locale(Settings.locale())
	touch.visible = DisplayServer.is_touchscreen_available()
	stats.position = Vector2(8, 8)
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", maxi(MESSAGE_MIN_SIZE, int(get_viewport().get_visible_rect().size.y * MESSAGE_SHARE)))
	message.visible = false
	if not _can_start():
		message.text = Assets.missing_message()
		message.visible = true
		set_physics_process(false)
		return
	_load()


func _can_start() -> bool:
	if not FileAccess.file_exists(Assets.path(ArcadeFlowData.FILE)):
		return false
	for gap in Assets.gaps():
		if gap in REQUIRED:
			return false
	return true


func _load() -> void:
	content = ArcadeFightContent.load_arcade(AssetCatalog.ROOT)
	effect_data = EffectData.load_from(Assets.path("effects"))
	hud_data = HudData.load_from(Assets.path("hud"))
	screen_data = ArcadeScreenData.load_from(Assets.path("screens"))
	var seed_value := options.seed if options.seed >= 0 else Time.get_ticks_usec() & 0x7FFFFFFF
	Log.debug("arcade game: seed %d" % seed_value)
	var data := ArcadeFlowData.load_from(Assets.path(ArcadeFlowData.FILE))
	var operator := ArcadeSettings.new()
	operator.attract_sound = _attract_sound()
	flow = ArcadeGameFlow.new(content, data, _rules(), operator, seed_value)
	flow.progress.day = day
	flow.progress.apply_schedule(data)
	# A session that is a test of something leaves the records file as it is.
	_keeps_records = not _fresh and _pad_script.is_empty() and options.screenshot_path.is_empty() and _ladder_from < 0
	if _keeps_records:
		flow.progress.restore_records(_store.load_arcade_records())
	_saved_records = flow.progress.saved_records()
	hud.setup(hud_data, screen_data)
	screens.setup(hud_data, screen_data)
	if Assets.has_group("movies") and not _skip_movies:
		screens.title.movie.load_entry()


## The cabinet writes its EEPROM as things happen; here, when the game moves to another state.
func _write_records() -> void:
	if not _keeps_records:
		return
	var records := flow.progress.saved_records()
	if records != _saved_records and _store.save_arcade_records(records):
		_saved_records = records


func _rules() -> RuleSet:
	return RuleSet.with_gameplay_fixes() if Settings.flag("gameplay_fixes") else RuleSet.original()


## The operator's attract sound switch (EEPROM 0x8036EC59), which the remake's setting stands for.
func _attract_sound() -> int:
	return 1 if Settings.flag("attract_sound") else 0


## A development pad script (game.gd's format): lines `<steps> <pad 1> [<pad 2>]` in hex words.
func _load_pad_script(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.warning("arcade game: no pad script %s" % path)
		return
	while not f.eof_reached():
		var words := f.get_line().get_slice("#", 0).split(" ", false)
		if words.size() < 2:
			continue
		var second := words[2].hex_to_int() if words.size() > 2 else 0
		for i in words[0].to_int():
			_pad_script.append(Vector2i(words[1].hex_to_int(), second))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			OrphanNodes.free_all(self)
		NOTIFICATION_WM_CLOSE_REQUEST:
			_quit()


func _quit() -> void:
	_write_records()
	Settings.save()
	set_physics_process(false)
	DevOptions.quit_after_drain(get_tree())


## The cabinet has no menu: the settings open from the attract and the title, where no game is on.
func _settings_allowed() -> bool:
	return flow.state == ArcadeGameFlow.State.ATTRACT or flow.state == ArcadeGameFlow.State.TITLE


func _open_settings() -> void:
	if _settings_allowed():
		settings_view.open()


func _on_settings_closed() -> void:
	_release_pads = true


func _on_setting_changed(key: String) -> void:
	if key == "stage_backdrops" or key == "graphics":
		RenderQuality.apply_viewport(get_viewport())
	elif key == "attract_sound" and flow != null:
		flow.settings.attract_sound = _attract_sound()


func _physics_process(_delta: float) -> void:
	settings_button.visible = _settings_allowed() and not settings_view.visible
	settings_button.place(touch.top_left_free if touch.visible else Rect2())
	for i in options.speed:
		var pads := _pads()
		steps += 1
		if settings_view.visible:
			settings_view.handle(pads[0] | pads[1])
		elif _settings_allowed() and (pads[0] | pads[1]) & ~_previous_pads & PadState.SELECT:
			_open_settings()
		else:
			_step(pads)
		_previous_pads = pads[0] | pads[1]
		if options.screenshot_due(steps):
			options.capture(get_viewport(), _quit)
			set_physics_process(false)
			return


func _pads() -> PackedInt32Array:
	var pads := PackedInt32Array([Pads.held[0], Pads.held[1]])
	if not _pad_script.is_empty():
		var scripted: Vector2i = _pad_script.pop_front()
		pads = PackedInt32Array([scripted.x, scripted.y])
	return pads


func _step(pads: PackedInt32Array) -> void:
	audio.advance()
	# The frame before lasts its vblanks (the movie's, the ending's waits): the flow runs again after
	# them. The flow has counted those its counter sees.
	_vblanks_left -= 1
	if _vblanks_left > 0:
		return
	if _release_pads:
		_release_pads = pads[0] | pads[1] != 0
		pads = PackedInt32Array([0, 0])
	var started := Time.get_ticks_usec()
	flow.step(ArcadeInput.panel_word(pads[0]), ArcadeInput.panel_word(pads[1]))
	audio.handle(flow.sim.events, flow.fight, flow.sounds_on())
	if _ladder_from >= 0:
		_shorten_ladder()
	_vblanks_left = flow.frame_vblanks()
	if flow.state != _shown_state:
		_shown_state = flow.state
		_write_records()
	_step_usec = lerpf(_step_usec, Time.get_ticks_usec() - started, 0.05)
	if flow.sim.loads != _fight_loads:
		_fight_loads = flow.sim.loads
		_build_fight_view()
	_replace_fighters()
	_show()


func _shorten_ladder() -> void:
	if flow.state == ArcadeGameFlow.State.SELECT:
		flow.match_flow.fight_number = _ladder_from
	elif flow.state == ArcadeGameFlow.State.MATCH:
		# The fights skipped count as won with this character, so a clear can set a time record.
		var side := flow.match_flow.human_index
		for i in _ladder_from:
			flow.match_flow.stage_records[i * 3] = flow.chars[side]
			flow.match_flow.stage_records[i * 3 + 1] = flow.costumes[side]
			flow.match_flow.stage_records[i * 3 + 2] = side
		for f in flow.fight.fighters:
			if f.is_cpu != 0 and f.body != null:
				f.health = mini(f.health, 1)


## The state's views after a step.
func _show() -> void:
	var fighting := flow.showing_fight()
	if fight_view != null:
		fight_view.visible = fighting
		if fighting:
			fight_view.apply(flow.sim)
	var with_hud := fighting and flow.state == ArcadeGameFlow.State.MATCH and flow.sub != ArcadeMatchFlow.Sub.OGRE
	hud.visible = with_hud
	if with_hud:
		hud.show_state(flow)
	screens.show_state(flow)
	_ranking_backdrop()
	fade.show_levels(flow.fades)


## The fighters a scene gave another model.
func _replace_fighters() -> void:
	for i in _model_loads.size():
		var loads := flow.sim.model_loads[i]
		if loads == _model_loads[i]:
			continue
		_model_loads[i] = loads
		if fight_view != null:
			var f := flow.fight.fighters[i]
			fight_view.replace_fighter(i, content.model(f.costume_slot), f.costume_slot, true)


func _build_fight_view() -> void:
	if fight_view != null:
		fight_view.queue_free()
		fight_view = null
	_model_loads = flow.sim.model_loads.duplicate()
	var fight := flow.fight
	if fight.fighters[0].body == null:
		return
	var models: Array[CharacterModel] = []
	var slots := PackedInt32Array()
	var chars := PackedInt32Array()
	for p in fight.count:
		var f := fight.fighters[p]
		models.append(content.model(f.costume_slot))
		slots.append(f.costume_slot)
		chars.append(f.char_id)
	fight_view = FightView.new()
	add_child(fight_view)
	fight_view.setup(content.stage_number(fight.stage), effect_data, models, slots, chars)


## The ranking's stage, turning behind its rows (FUN_801E5B14).
func _ranking_backdrop() -> void:
	var shown := flow.state == ArcadeGameFlow.State.RANKING and flow.ranking.layer != ArcadeRanking.Layer.NONE
	if not shown:
		if backdrop != null:
			backdrop.visible = false
		return
	var stage := flow.ranking.backdrop_stage
	if backdrop == null or backdrop.number != stage:
		if backdrop != null:
			backdrop.queue_free()
		backdrop = StageBackdrop.new()
		add_child(backdrop)
		backdrop.setup(content.stage_number(stage))
	backdrop.visible = true
	backdrop.show_view(flow.ranking.backdrop_view(), flow.sub <= 3)


func _process(_delta: float) -> void:
	if flow == null:
		return
	if stats.visible:
		stats.text = "%s  state %d sub %d  step %d  %.0f µs" % [options.render_stats(get_viewport()), flow.state, flow.sub, steps, _step_usec]
	var window := get_viewport().get_visible_rect().size
	var fraction := options.weight(Engine.get_physics_interpolation_fraction()) if Settings.flag("interpolation") else 1.0
	var surround := Settings.text("framing") == "stage"
	if fight_view != null and fight_view.visible:
		fight_view.rig.camera.make_current()
		fight_view.interpolate(fraction, window)
		bars.frame(fight_view.rig.visible_rect, fight_view.clear_colour if surround else Color.BLACK)
		hud.place(fight_view.rig.frame_rect)
		RenderingServer.set_default_clear_color(fight_view.clear_colour)
		bars.visible = true
	elif backdrop != null and backdrop.visible:
		backdrop.rig.camera.make_current()
		backdrop.interpolate(fraction, window)
		RenderingServer.set_default_clear_color(Color.BLACK)
		bars.visible = false
	else:
		RenderingServer.set_default_clear_color(Color.BLACK)
		bars.visible = false
