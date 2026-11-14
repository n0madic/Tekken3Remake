extends GameShell
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
## runs; `--fresh`, a pad script, a screenshot or `--ladder-from` neither read nor write it. On the
## web the same options come from the page's query string, and the game waits for a first input.

## Without these the game cannot run; the sounds' absence only silences it.
const REQUIRED := ["screens", "hud"]
const DAY_ALL_OPEN := 120

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
var day := DAY_ALL_OPEN
var _fight_loads := -1
var _model_loads := PackedInt32Array()
var _step_usec := 0.0
var _previous_pads := 0
var _skip_movies := false
var _vblanks_left := 0
var _ladder_from := -1
var _fresh := false
var _keeps_records := false
var _store := SaveStore.new()
var _saved_records := {}
var _shown_state := -1
var _operator_changed := false          ## an operator setting changed since the flow read them


func _ready() -> void:
	var args := DevOptions.arguments()
	options = DevOptions.parse(args)
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
	Pads.escape_rules = _escape_rules
	_follow_settings()
	_setup_labels()
	if not _can_start():
		message.text = Assets.missing_message()
		message.visible = true
		set_physics_process(false)
		return
	_load()
	_wait_for_gesture()


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
	flow = ArcadeGameFlow.new(content, data, _rules(), Settings.arcade_operator(), seed_value)
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


## The cabinet reads its EEPROM at boot only; here the operator settings changed take effect when
## no game is on, before a game reads them (a game whose event mode changed under it could not go
## on, issue n0madic/Tekken3Remake#30). The cabinet copies them into the words the attract changes
## too (FUN_801BDA64's modes 3 to 5), which the remake does not run.
func _apply_operator_settings() -> void:
	if not _operator_changed or not _no_game():
		return
	_operator_changed = false
	flow.settings = Settings.arcade_operator()
	if fight_view != null:
		fight_view.effects.green_hit = flow.settings.hit_colour != 0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			OrphanNodes.free_all(self)
		NOTIFICATION_WM_CLOSE_REQUEST:
			_quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_pause_on_focus_loss()


func _quit() -> void:
	_write_records()
	Settings.save()
	screens.title.movie.stop()
	audio.stop_all()
	set_physics_process(false)
	DevOptions.quit_after_drain(get_tree())


## The cabinet has no menu and no pause: this is the remake's own. Select (Escape on the keyboard,
## Android's Back, the touch controls' Select) opens the settings in any state, and the game waits
## while they are open: that is its pause. Start is not for it, a game's Start joins a challenger.
func _open_settings() -> void:
	if settings_view.visible:
		return
	settings_view.open()
	audio.set_paused(true)
	_show_touch()


func _on_settings_closed() -> void:
	_release_pads = true
	audio.set_paused(false)
	_show_touch()


## The gear that opens the settings, where nothing else is on screen: the attract and the title.
func _gear_shown() -> bool:
	return not settings_view.visible and _idle()


## The attract and the title: no game is on.
func _idle() -> bool:
	return flow.state == ArcadeGameFlow.State.ATTRACT or flow.state == ArcadeGameFlow.State.TITLE


## No game is on: the attract and the title, and the attract's demo fights with the records pages
## and transitions after them (mode 6 until a Start, which begins a game from any of them).
func _no_game() -> bool:
	return _idle() or flow.mode == ArcadeGameFlow.MODE_DEMO


## Escape stands for Select, always: the pause, and the way out of the settings.
func _escape_rules() -> Vector2i:
	return Vector2i(PadState.SELECT, -1)


## A game's fight whose window lost focus (or went to the background) pauses; the attract's demo
## fights and a scripted session do not.
func _pause_on_focus_loss() -> void:
	if flow != null and flow.state == ArcadeGameFlow.State.MATCH and not _no_game() and _pad_script.is_empty() \
			and options.screenshot_path.is_empty():
		_open_settings()


func _on_setting_changed(key: String) -> void:
	super(key)
	if key == "attract_sound" and flow != null:
		flow.settings.attract_sound = Settings.arcade_operator().attract_sound
	elif key in GameSettings.OPERATOR_KEYS:
		_operator_changed = true


func _physics_process(_delta: float) -> void:
	settings_button.visible = _gear_shown()
	settings_button.place(touch.top_left_free if touch.visible else Rect2())
	for i in options.speed:
		var pads := _pads()
		steps += 1
		if settings_view.visible:
			settings_view.handle(pads[0] | pads[1])
		elif (pads[0] | pads[1]) & ~_previous_pads & PadState.SELECT:
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
	_apply_operator_settings()
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
	fight_view.effects.green_hit = flow.settings.hit_colour != 0


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
	# A paused game stands on its last step: interpolating would swing the poses back and forth.
	var interpolated := Settings.flag("interpolation") and not settings_view.visible
	var fraction := options.weight(Engine.get_physics_interpolation_fraction()) if interpolated else 1.0
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
