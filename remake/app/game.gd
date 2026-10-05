extends Node
## The game (remake-plan.md, M3): the whole frame loop of GameFlow from boot, with every mode, the
## screens, the fights, the movies and the music, and the progress kept in the save file.
##
## Each physics tick is one step of GameFlow with both pads' physical words; the views of the
## state the step left read what it did, the audio director plays its sound requests and the pad
## vibration its patterns. A tap or click is the first pad's Start.
##
## Select on the main menu (which the game does not read there) opens the remake's settings
## (SettingsView); the flow waits while they are open. The Gameplay fixes apply to the game from
## the next mode started, the text region at once.
##
## Command line (after `--`): `--screenshot=<path>` saves the frame after `--frames=<n>` steps
## and quits; `--speed=<n>` runs n steps per physics tick; `--seed=<n>` fixes the random
## generators; `--no-movies` plays as a build without movies does; `--stats` shows the frame
## and step timings (F3 toggles them); `--fresh` ignores the save file; `--unlock` opens every character,
## costume and mode for the session without saving that; `--texture-pack=<name or folder>` uses an
## installed texture pack or a pack's folder for the session (the setting unchanged), `--graphics=<preset>`
## a graphics preset for the session. For development `--replay=<scenario>`
## plays a flow trace's pads (`--replay-frames=<n>`: its first n steps), `--pads=<file>` a pad
## script after it. On the web the same options come from the page's query string. `--m0` opens
## the character viewer, `--fight` the M2 VS set-up, `--stages` the stage viewer.

const M0_SCENE := "res://app/m0_viewer.tscn"
const FIGHT_SCENE := "res://app/fight.tscn"
const STAGES_SCENE := "res://app/stage_viewer.tscn"
## The development scenes the command line opens at once, in priority order.
const DEV_SCENES := {"--m0": M0_SCENE, "--stages": STAGES_SCENE, "--fight": FIGHT_SCENE}
const FLOW_TRACE_READER := "res://dev/flow_trace.gd"
const ENBU_STAGE := "e"
const MESSAGE_SHARE := 0.035           ## the message's text height as a share of the window height
const MESSAGE_MIN_SIZE := 18
## The game's overlays by logical id (the loader's slots): the screens' drawing reads their tables.
const OVERLAY_NAMES := {0: "arcade", 1: "practice", 4: "select", 5: "title", 6: "ranking", 8: "ending", 9: "result"}

var flow: GameFlow
var content: FightContent
var effect_data: EffectData
var hud_data: HudData
var screens: ScreenData
var ram: GameRam
var vram_system: VramImage
var card := ProgressCard.new()
var audio := AudioDirector.new()
var vibration: PadVibration
var enbu_view := EnbuView.new()
var enbu_assets: EnbuAssets
var fight_view: FightView
var backdrop: StageBackdrop               ## the ranking's turning stage
var hud := FightHud.new()
var pause_view := PauseMenuView.new()
var bars := FramingBars.new()
var attract_screen := AttractScreen.new()
var main_menu_view := MainMenuView.new()
var options_view := OptionsView.new()
var select_view := SelectView.new()
var quick_view := QuickSelectView.new()
var vs_view := VsView.new()
var result_view := ResultView.new()
var ranking_view := RankingView.new()
var ending_view := EndingView.new()
var practice_view := PracticeView.new()
var move_list_view := MoveListView.new()
var mode_hud := ModeHudView.new()
var movie := MoviePlayer.new()
var mask := ScreenMask.new()
var fade := FadeOverlay.new()
var blackout := ColorRect.new()
var message := Label.new()
var stats := Label.new()
var settings_view := SettingsView.new()
var settings_button := SettingsButton.new()
var touch := TouchControls.new()
var rule_set := RuleSet.original()
var locale: TextLocale
var movies: Dictionary = {}
var options := DevOptions.new()            ## --screenshot, --frames, --speed, --seed, --stats
var seed := -1
var skip_movies := false
var fresh := false
var unlock_all := false
var replay_name := ""
var dev_screen := ""
var _replay: Object                        ## the flow trace a replay reads its pads from
var replay_frames := -1                    ## the replay's steps played (−1: all)
var _pad_script: Array[Vector2i] = []      ## `--pads`: the steps' pads after the replay
var steps := 0
var _fight_loads := -1
var _model_loads := PackedInt32Array()     ## FightSimulation.model_loads the fight view shows
var _fight_view_due := false               ## a new fight was set up: _show builds its view
var _slots := PackedInt32Array([-1, -1])
var _step_usec := 0.0
var _tap := false
var _prev_pads := 0                       ## both pads the step before (Select opens the settings on a press)
var _waiting_for_gesture := false         ## the web build before its first input
var _release_pads := false                 ## after the settings: the game gets no buttons until all are released
var _joypads := 0                          ## gamepads connected (the title's start prompt)
var _fading_views: Array[ScreenCanvas] = []   ## the screens with a fade of their own
var _pause_owed := false                   ## the window lost focus in a fight: its pause opens as soon as one can


func _ready() -> void:
	var args := _arguments()
	for flag: String in DEV_SCENES:
		if flag in args:
			set_physics_process(false)
			set_process(false)
			get_tree().change_scene_to_file.call_deferred(DEV_SCENES[flag] as String)
			return
	_parse_arguments(args)
	get_tree().auto_accept_quit = false
	add_child(audio)
	add_child(enbu_view)
	var layer := CanvasLayer.new()
	layer.layer = 1
	add_child(layer)
	for view: Control in [bars, hud, mode_hud, pause_view, practice_view, move_list_view, attract_screen, main_menu_view, options_view,
			select_view, quick_view, vs_view, result_view, ranking_view, ending_view, mask, movie]:
		layer.add_child(view)
	var top := CanvasLayer.new()
	top.layer = 10
	add_child(top)
	top.add_child(blackout)
	top.add_child(fade)
	top.add_child(message)
	top.add_child(stats)
	top.add_child(touch)
	top.add_child(settings_button)
	top.add_child(settings_view)
	settings_view.closed.connect(_on_settings_closed)
	Pads.escape_rules = _escape_rules
	_fading_views = [quick_view, result_view, ranking_view]
	_joypads = Input.get_connected_joypads().size()
	Input.joy_connection_changed.connect(func(_device: int, _connected: bool) -> void:
		_joypads = Input.get_connected_joypads().size())
	settings_button.pressed.connect(_open_settings)
	Settings.changed.connect(_on_setting_changed)
	Settings.apply_audio()
	RenderQuality.apply_viewport(get_viewport())
	TranslationServer.set_locale(Settings.locale())
	_show_touch()
	blackout.color = Color.BLACK
	blackout.mouse_filter = Control.MOUSE_FILTER_IGNORE
	blackout.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	stats.position = Vector2(8, 8)
	stats.add_theme_color_override("font_outline_color", Color.BLACK)
	stats.add_theme_constant_override("outline_size", 4)
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.visible = false
	message.add_theme_font_size_override("font_size", maxi(MESSAGE_MIN_SIZE, int(get_viewport().get_visible_rect().size.y * MESSAGE_SHARE)))
	movie.visible = false
	movie.finished.connect(_on_movie_finished)
	if not Assets.is_available() or not FileAccess.file_exists(Assets.path("tables/flow.json")):
		message.text = AssetCatalog.missing_message()
		message.visible = true
		set_physics_process(false)
		return
	_load()
	# Browsers start audio only after a user gesture: the web build waits for the first input
	# before the game (and its sound) starts.
	if OS.has_feature("web") and options.screenshot_path.is_empty():
		message.text = tr("WEB_START")
		message.visible = true
		set_physics_process(false)
		_waiting_for_gesture = true


func _load() -> void:
	content = FightContent.load_from(AssetCatalog.ROOT)
	locale = TextLocale.load_from(AssetCatalog.ROOT)
	content.locale = locale
	effect_data = EffectData.load_from(Assets.path("effects"))
	hud_data = HudData.load_from(Assets.path("hud"))
	var screens_dir := Assets.path("screens")
	screens = ScreenData.load_from(screens_dir)
	ram = GameRam.load_from(screens_dir)
	ram.locale = locale
	vram_system = VramImage.load_system(screens_dir.path_join("vram_system.bin"))
	vibration = PadVibration.new(content.tables.vibration)
	audio.use_tables(content.tables)
	var data := FlowData.load_from(Assets.path("tables/flow.json"))
	if not replay_name.is_empty():
		_load_replay()
	if seed < 0:
		seed = Time.get_ticks_usec() & 0x7FFFFFFF
	# The seed repeats a session with `--seed=<n>`.
	Log.debug("game: seed %d" % seed)
	# A trace replay runs the original rules, as the game does.
	if _replay == null:
		_apply_rules()
	flow = GameFlow.new(content, data, rule_set, seed)
	flow.performance_factory = _new_performance
	flow.movies_available = Assets.has_group("movies") and not skip_movies
	if flow.movies_available:
		movies = JsonFile.read(Assets.path("movies/movies.json"))
	flow.theater.music_available = Assets.has_group("music")
	card.reads = not fresh
	# A fresh session (`--fresh`, a replay) leaves the save file as it is.
	card.writes = not fresh
	card.auto_save_default = not fresh
	card.unlock_all = unlock_all
	card.defaults = flow.progress.save_data()
	card.select(Settings.number("memory_card"))
	card.fresh_progress(flow.progress)
	flow.card_loader = card.read
	flow.options.save_writer = card.write
	if _replay != null:
		# The trace's pokes (unlocks the scenario starts with).
		for poke: PackedInt64Array in _replay.call("pokes"):
			flow.progress.put8(poke[0] - GameProgress.BASE, poke[1])
	_map_blocks()
	enbu_view.setup(content.stage(ENBU_STAGE), effect_data)
	attract_screen.setup(screens, false)
	main_menu_view.setup(hud_data, TexturePacks.texture(screens_dir.path_join("title.png")))
	options_view.setup(hud_data, ram, vram_system, screens_dir)
	settings_view.pad_texture = options_view.pads[0]
	select_view.setup(hud_data, ram, vram_system, screens_dir)
	quick_view.setup(hud_data, ram, vram_system)
	vs_view.setup(hud_data, ram, vram_system, screens_dir)
	result_view.setup(hud_data, ram, vram_system, screens_dir)
	ranking_view.setup(hud_data, ram, vram_system, screens_dir)
	ending_view.setup(hud_data, ram, vram_system, screens_dir)
	practice_view.setup(hud_data, ram, vram_system)
	move_list_view.setup(hud_data, ram, vram_system, AssetCatalog.ROOT)
	mode_hud.setup_modes(hud_data, ram, vram_system, content.mode_ram("force"), screens_dir)
	pause_view.setup(hud)
	_apply_texts()


## `--replay`: the flow trace's reader is development tooling (`dev/`), which exported builds leave
## out (a web page's `?replay=` reaches here too); without it, or without the trace, the game starts
## as usual.
func _load_replay() -> void:
	if not ResourceLoader.exists(FLOW_TRACE_READER):
		Log.warning("game: --replay needs the tests (%s), not in this build" % FLOW_TRACE_READER)
		replay_name = ""
		return
	var reader := load(FLOW_TRACE_READER) as GDScript
	_replay = reader.call("load_scenario", replay_name) as Object
	if _replay == null:
		Log.warning("game: no flow trace %s" % replay_name)
		replay_name = ""
		return
	# A replay starts from the trace's progress, never the card's.
	fresh = true
	var header: Dictionary = _replay.get("header")
	seed = (header["scenario"] as Dictionary)["seed"]


## The remake's byte blocks at their game addresses, for the screens' drawing.
func _map_blocks() -> void:
	ram.map(GameProgress.BASE, flow.progress)
	ram.map(ModeRegion.BASE, flow.region)
	ram.map(CharacterSelect.BASE, flow.select.ctx)
	ram.map(CharacterSelect.CELLS_BASE, flow.select.cells)
	ram.map(RankingScreen.TABLE_BASE, flow.ranking.table)
	ram.map(RankingScreen.NAME_BASE, flow.ranking.name)
	ram.map(RankingScreen.BACKDROP_BASE, flow.ranking.backdrop)
	ram.map(ResultScreens.BASE, flow.results.state)
	ram.map(ResultScreens.BANNER_BASE, flow.results.banner)
	ram.map(PracticeMode.BASE, flow.practice.s)


func _parse_arguments(args: PackedStringArray) -> void:
	options = DevOptions.parse(args)
	seed = options.seed
	stats.visible = options.stats
	for arg in args:
		var value := arg.get_slice("=", 1)
		if arg == "--no-movies":
			skip_movies = true
		elif arg == "--fresh":
			fresh = true
		elif arg == "--unlock":
			unlock_all = true
		elif arg.begins_with("--texture-pack="):
			TexturePacks.use_for_session(value)
		elif arg.begins_with("--screen="):
			dev_screen = value
		elif arg.begins_with("--replay="):
			replay_name = value
		elif arg.begins_with("--replay-frames="):
			replay_frames = value.to_int()
		elif arg.begins_with("--pads="):
			_load_pad_script(value)


## A development pad script: lines `<steps> <pad 1> [<pad 2>]` (hex words) played in turn once the
## replay ends (or from boot); `#` starts a comment.
func _load_pad_script(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.warning("game: no pad script %s" % path)
		return
	while not f.eof_reached():
		var words := f.get_line().get_slice("#", 0).split(" ", false)
		if words.size() < 2:
			continue
		var p1 := words[2].hex_to_int() if words.size() > 2 else 0
		for i in words[0].to_int():
			_pad_script.append(Vector2i(words[1].hex_to_int(), p1))


## Command-line options, or on the web the page's query string as `--name[=value]` options.
static func _arguments() -> PackedStringArray:
	if not OS.has_feature("web"):
		return OS.get_cmdline_user_args()
	var query := str(JavaScriptBridge.eval("window.location.search", true))
	var out := PackedStringArray()
	for item in query.trim_prefix("?").split("&", false):
		out.append("--" + item.uri_decode())
	return out


func _new_performance(number: int) -> EnbuPerformance:
	var assets := _enbu_assets()
	enbu_view.load_demo(assets.demo(number), assets.models(number))
	return assets.performance(number)


## The attract demonstrations' assets, loaded when first needed.
func _enbu_assets() -> EnbuAssets:
	if enbu_assets == null:
		enbu_assets = EnbuAssets.load_from(Assets.path(""))
	return enbu_assets


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			OrphanNodes.free_all(self)
		NOTIFICATION_WM_CLOSE_REQUEST:
			_quit()
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			_pause_owed = flow != null and flow.state == GameFlow.State.FIGHT and not flow.pause_menu_open()
		NOTIFICATION_APPLICATION_FOCUS_IN, NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_WM_WINDOW_FOCUS_IN:
			# A mobile app does not step in the background: its pause comes after the return. A
			# fight that was not yet open to a pause (its intro) does not pause a player who is back.
			_pause_owed = _pause_owed and flow != null and flow.pause_pad() >= 0


func _quit() -> void:
	Settings.save()
	movie.stop()
	audio.stop_all()
	PadVibration.stop_motors()
	set_physics_process(false)
	DevOptions.quit_after_drain(get_tree())


func _input(event: InputEvent) -> void:
	if _waiting_for_gesture and event.is_pressed() and not event.is_echo() \
			and (event is InputEventKey or event is InputEventMouseButton or event is InputEventScreenTouch
			or event is InputEventJoypadButton):
		_waiting_for_gesture = false
		message.visible = false
		set_physics_process(true)
		get_viewport().set_input_as_handled()
		return
	if DevOptions.toggles_stats(event):
		stats.visible = not stats.visible


## The settings' Gameplay fixes on the rule set the game shares (RuleSet is read by the fights and
## the progress rules, so it is changed in place).
func _apply_rules() -> void:
	rule_set.set_gameplay_fixes(Settings.flag("gameplay_fixes"))


## The game texts' language on everything that shows them (a trace replay keeps the Japanese
## release's, as the traces were recorded).
func _apply_texts() -> void:
	locale.english = Settings.text("game_texts") == "english" and _replay == null
	flow.data.localize(locale)
	attract_screen.set_locale(locale)
	pause_view.locale = locale
	select_view.vram = _select_vram()
	movie.captions = MovieCaptions.load_from(locale.file_or("captions.json",
		Assets.path("movies").path_join("captions.json")))
	_reload_pictures()


## The pictures the 2D views took from TexturePacks when they were set up, again: for the texts'
## language (the USA title) and after the texture pack or filter changed (the fighters and stages
## reload their own, FighterView and StageView). The settings change these over the main menu
## while the game stands: its picture is drawn again at once.
func _reload_pictures() -> void:
	main_menu_view.title = TexturePacks.texture(_screen_file("title.png"))
	main_menu_view.redraw()
	attract_screen.reload_pictures()
	pause_view.reset_pictures()
	for view: PsxCanvas in [options_view, select_view, vs_view, result_view]:
		view.reload_pictures()
	settings_view.pad_texture = options_view.pads[0]
	settings_view.queue_redraw()


## A converted screen file in the texts' language: the USA one when English is on and it exists.
func _screen_file(name: String) -> String:
	return locale.file_or(name, Assets.path("screens/" + name))


## The select screen's VRAM: the system textures and select.ovl's pictures (the USA names in
## English).
func _select_vram() -> VramImage:
	var image := vram_system.duplicate_image()
	image.upload_file(_screen_file("select.tims"))
	return image


func _on_setting_changed(key: String) -> void:
	match key:
		"gameplay_fixes":
			if _replay == null:
				_apply_rules()
		"language":
			TranslationServer.set_locale(Settings.locale())
		"game_texts":
			_apply_texts()
		"graphics":
			RenderQuality.apply_viewport(get_viewport())
		"texture_pack", "texture_filter":
			TexturePacks.clear()
			_reload_pictures()
		"stage_backdrops":
			_rebuild_stages()
		"touch_controls", "touch_macros", "touch_size":
			_show_touch()


## Whether the settings may open: on the main menu's list (not while it opens or leaves).
func _settings_allowed() -> bool:
	return flow != null and flow.state == GameFlow.State.MENU and flow.sub == 1 and _replay == null


## The touch controls where the settings want them, with their macro buttons (hidden while the
## settings are open: the panel takes the taps).
func _show_touch() -> void:
	touch.set_macros(Settings.text("touch_macros"))
	touch.set_scale_share(Settings.touch_scale())
	touch.visible = Settings.touch_enabled() and not settings_view.visible
	if not touch.visible:
		touch.reset()


## A tap waiting for the next step is dropped as the settings open or close: the step does not run
## while they are open, and the tap was meant for them (a tap on the gear with the touch controls
## hidden arrives first as an emulated click, which the gear does not take).
func _open_settings() -> void:
	if _settings_allowed() and not settings_view.visible:
		_tap = false
		settings_view.open()
		_show_touch()


func _on_settings_closed() -> void:
	_tap = false
	_release_pads = true
	_show_touch()
	if Settings.number("memory_card") != card.card:
		_switch_card()


## Another memory card: its progress replaces the one in memory (a card with no save starts fresh),
## and the main menu opens again through the transition screen, so that its entries and the key
## configuration follow the new progress.
func _switch_card() -> void:
	card.select(Settings.number("memory_card"))
	card.load_into(flow.progress)
	flow.goto_transition(GameFlow.State.MENU)


func _unhandled_input(event: InputEvent) -> void:
	# With the touch controls shown, Start is their button: other taps do nothing.
	if touch.visible:
		return
	var finger := event as InputEventScreenTouch
	var click := event as InputEventMouseButton
	if (finger != null and finger.pressed) or (click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT):
		_tap = true


func _physics_process(_delta: float) -> void:
	# Android's Back backs out of the settings but does not open them from the main menu.
	Pads.back_allowed = flow.state != GameFlow.State.MENU or settings_view.visible
	settings_button.visible = _settings_allowed() and not settings_view.visible
	settings_button.place(touch.top_left_free if touch.visible else Rect2())
	touch.set_shoulders(TouchControls.shoulders_shown(flow))
	touch.set_playback(_playback())
	if Pads.escape_pressed and flow.pause_menu_open():
		flow.escape_pressed = true
	for i in options.speed:
		var pads := _pads()
		steps += 1
		if settings_view.visible:
			settings_view.handle(pads[0] | pads[1])
		elif _settings_allowed() and (pads[0] | pads[1]) & ~_prev_pads & PadState.SELECT:
			_open_settings()
		else:
			_step(pads)
		_prev_pads = pads[0] | pads[1]
		if options.screenshot_due(steps):
			options.capture(get_viewport(), _quit)
			set_physics_process(false)
			return
	_rumble()


## Whether the touch controls show only Select and Start: over what Start skips (movies, the
## title and demonstration, replays) and the records pages without a name to enter, which Start
## leaves.
func _playback() -> bool:
	if SkipButtons.skippable(flow, movie.playing):
		return true
	return flow.state in [GameFlow.State.RANKING_LOAD, GameFlow.State.RANKING] and flow.progress.name_entry == 0


## What the keyboard's Escape does on this screen: the pause in a fight, a move list's exit and a
## movie skip (Start), back out of the options and Theater (Select), and back to the main menu
## from the character selects (Start + Select, the game's own way out); elsewhere Select, which no
## screen there reads. On an open pause menu it presses nothing: GameFlow leaves the menu.
func _escape_buttons() -> int:
	if movie.playing:
		return PadState.START
	if flow.pause_menu_open():
		return 0
	match flow.state:
		GameFlow.State.FIGHT, GameFlow.State.PREPARE, GameFlow.State.VS:
			return PadState.START
		GameFlow.State.SELECT, GameFlow.State.QUICK_SELECT:
			return PadState.START | PadState.SELECT
	return PadState.SELECT


## What Escape stands for on the screen showing now and who it presses for (InputRouter asks before
## it reads the pads of a frame).
func _escape_rules() -> Vector2i:
	if flow == null:
		return Vector2i(PadState.START, -1)
	return Vector2i(_escape_buttons(), flow.escape_pad(Pads.escape_owner()))


## This step's pads: the players', a trace replay's or the pad script's.
func _pads() -> PackedInt32Array:
	var pads := PackedInt32Array([Pads.held[0], Pads.held[1]])
	if _replay != null:
		var frames: int = _replay.get("frames")
		if steps >= (frames if replay_frames < 0 else mini(frames, replay_frames)):
			_replay = null
		else:
			pads = PackedInt32Array([_replay.call("pad", steps, 0), _replay.call("pad", steps, 1)])
	if _replay == null and not _pad_script.is_empty():
		var scripted: Vector2i = _pad_script.pop_front()
		pads = PackedInt32Array([scripted.x, scripted.y])
	return pads


## One step of the game and everything that shows it.
func _step(pads: PackedInt32Array) -> void:
	# A trace replay keeps its pads.
	if _replay == null:
		pads = SkipButtons.apply(pads, flow, movie.playing)
	if _release_pads:
		_release_pads = pads[0] | pads[1] != 0
		pads = PackedInt32Array([0, 0])
	if _tap:
		var tap_pad := flow.tap_pad()
		if tap_pad >= 0:
			pads[tap_pad] |= PadState.START
		_tap = false
	_apply_focus_pause(pads)
	var waiting := flow.movie_blocking
	var handled := flow.sim.events.items.size() if waiting else 0
	if not dev_screen.is_empty() and flow.state in [GameFlow.State.TITLE, GameFlow.State.MENU]:
		_open_dev_screen()
	var started := Time.get_ticks_usec()
	var in_options := flow.state == GameFlow.State.OPTIONS
	flow.step(pads)
	# Leaving OPTIONS saves the options (ProgressCard): the game would keep them until its next
	# auto save.
	var save := flow.save_requested or (in_options and flow.state != GameFlow.State.OPTIONS
		and card.saves_options(flow.progress))
	_step_usec = lerpf(_step_usec, Time.get_ticks_usec() - started, 0.05)
	# A new fight: its view is built by _show, and the last fight's rumble stops before this step's
	# own starts.
	if flow.sim.loads != _fight_loads:
		_fight_loads = flow.sim.loads
		_fight_view_due = true
		vibration.clear()
	if waiting and flow.movie_blocking:
		if movie.playing and SkipButtons.skips_blocking_movie(flow):
			# The movie ends; the next step finishes the frame that started it.
			movie.stop()
		return
	audio.soundtrack = flow.progress.bgm
	audio.set_mono(flow.progress.speaker == GameProgress.SPEAKER_MONO)
	audio.handle(flow.sim.events, handled)
	for i in range(handled, flow.sim.events.items.size()):
		var e := flow.sim.events.items[i]
		if e.kind == SimEvents.Kind.VIBRATE:
			vibration.vibrate(e.a, e.b)
	if save and card.write(flow.progress.save_data()) != SaveStore.CARD_DONE:
		flow.save_failed()
	if flow.movie_started >= 0 and _replay != null:
		# The harness's movies end on their first frame.
		while flow.movie_blocking:
			flow.movie_result = 1
			flow.step(pads)
		flow.movie_result = 1
	elif flow.movie_started >= 0:
		_start_movie(flow.movie_started, flow.movie_blocking)
	if movie.playing and not flow.movie_blocking and not (flow.state == GameFlow.State.TITLE and flow.sub == 2):
		movie.stop()
	_overlays()
	_show()


## A fight whose window lost focus (or went to the background) opens its pause as the human's Start
## would, as soon as the round state takes one; a trace replay and the pad script keep their pads.
func _apply_focus_pause(pads: PackedInt32Array) -> void:
	if not _pause_owed:
		return
	if _replay != null or not _pad_script.is_empty() or flow.state != GameFlow.State.FIGHT:
		_pause_owed = false
		return
	var pad := flow.pause_pad()
	if pad >= 0:
		pads[pad] |= PadState.START
		_pause_owed = false


## `--screen`: the Theater (as its menu entry opens it), an arcade ending for player 1's costume
## key (`ending:<key>`, Paul's by default), or an attract demonstration (`enbu:<0-2>`, the first by
## default; any of them, whatever the progress has unlocked).
func _open_dev_screen() -> void:
	var kind := dev_screen.get_slice(":", 0)
	var number := dev_screen.get_slice(":", 1).to_int()
	dev_screen = ""
	match kind:
		"enbu":
			# The title's way into the demonstration: attract step 1 (FUN_8004FBE0).
			flow.progress.attract_step = 1
			flow.goto_transition(GameFlow.State.TITLE)
			flow.progress.demo_number = clampi(number, 0, _enbu_assets().data.demos.size() - 1)
			return
		"theater":
			flow.fight.human_mask = 0
		"ending":
			flow.fight.human_mask = 1
			flow.fight.fighters[0].costume_key = number
	flow.goto_screen_loader(GameFlow.State.ENDING)


## The overlays the loader put in its slots: their tables join the game memory the views read.
func _overlays() -> void:
	for slot in 2:
		if flow.slots[slot] != _slots[slot]:
			_slots[slot] = flow.slots[slot]
			if OVERLAY_NAMES.has(_slots[slot]):
				ram.load_overlay(str(OVERLAY_NAMES[_slots[slot]]))


## The views of the state the step left.
func _show() -> void:
	var state := flow.state
	var sub := flow.sub
	var frames := flow.fight.vblank
	var fight_state := state == GameFlow.State.FIGHT or state == GameFlow.State.PREPARE
	# The fighters of a new fight: the stage and models are built again; a model swapped in during
	# the fight replaces only its own.
	if _fight_view_due:
		_fight_view_due = false
		_model_loads = flow.sim.model_loads.duplicate()
		_build_fight_view()
	elif flow.sim.model_loads != _model_loads:
		_replace_fighters()
	var fighting := fight_state and fight_view != null and (state == GameFlow.State.PREPARE or sub >= 7)
	if fight_view != null:
		fight_view.visible = fighting
		if fighting:
			fight_view.apply(flow.sim)
	# The Ogre scene draws no HUD (its engine calls are the stage, the two fighters and the fade).
	var hud_shown := fighting and not (sub >= MatchFlow.Sub.OGRE_DISPLAY_ON and sub <= MatchFlow.Sub.OGRE_DISPLAY_OFF)
	hud.visible = hud_shown
	pause_view.visible = hud_shown
	if hud_shown:
		hud.flow_texts = flow.texts.duplicate()
		hud.show_state(flow.sim)
		pause_view.show_state(flow.sim)
	mode_hud.show_state(flow.sim, hud_shown)
	practice_view.visible = fighting and flow.region.mode == GameMode.PRACTICE
	if practice_view.visible:
		practice_view.show_state(flow)
	if fighting:
		move_list_view.show_state(flow)
	else:
		move_list_view.visible = false
	var enbu := state == GameFlow.State.ENBU
	if flow.performed and flow.performance != null and flow.performance.drawn:
		enbu_view.apply(flow.performance)
	enbu_view.visible = enbu and flow.performed and flow.performance != null and flow.performance.drawn
	attract_screen.setup_variant(enbu)
	attract_screen.prompt = 3 if _joypads >= 2 else 1
	attract_screen.show_frame(flow.presents_mode, flow.presents_level, flow.picture, frames)
	main_menu_view.visible = state == GameFlow.State.MENU
	if main_menu_view.visible:
		main_menu_view.show_state(flow.menu, frames)
	options_view.visible = state == GameFlow.State.OPTIONS
	if options_view.visible:
		options_view.show_state(flow)
	select_view.visible = state == GameFlow.State.SELECT
	if select_view.visible:
		select_view.show_state(flow)
	# The quick select's context lies in the screen overlays' slot: it is read only in its state. Its
	# first sub-states draw nothing (the last visit's frame must not show), but start its counters.
	var quick := state == GameFlow.State.QUICK_SELECT
	quick_view.visible = quick and sub > 1
	if quick:
		ram.map(QuickSelect.BASE, flow.quick.ctx)
		quick_view.show_state(flow)
	else:
		ram.unmap(flow.quick.ctx)
	# The VS screen stays while the fighters load (FightMain's sub-states 3 and 4 draw nothing).
	vs_view.visible = state == GameFlow.State.VS or (state == GameFlow.State.FIGHT and (sub == 3 or sub == 4))
	if vs_view.visible:
		vs_view.show_state(flow)
	result_view.visible = state >= GameFlow.State.TEAM_RESULT and state <= GameFlow.State.FORCE_RESULT
	if result_view.visible:
		result_view.show_state(flow)
	ranking_view.visible = state == GameFlow.State.RANKING
	if ranking_view.visible:
		ranking_view.show_state(flow)
	_ranking_backdrop(state == GameFlow.State.RANKING and flow.ranking.table.u16(RankingScreen.T_MODE) != RankingScreen.TableMode.HIDDEN)
	ending_view.visible = state == GameFlow.State.ENDING and not movie.playing
	if ending_view.visible:
		ending_view.show_state(flow)
	mask.visible = not fighting and not enbu_view.visible and not (backdrop != null and backdrop.visible)
	blackout.visible = flow.globals.display_on == 0 and not movie.playing
	var levels := flow.fades.duplicate()
	for view in _fading_views:
		if view.visible and view.fade_level != ScreenCanvas.NO_FADE:
			levels.append(view.fade_level)
	fade.show_levels(levels)


## The ranking's stage (ranking.ovl FUN_800C390C picks it, FUN_800C3AAC turns the camera).
func _ranking_backdrop(shown: bool) -> void:
	if not shown:
		if backdrop != null:
			backdrop.visible = false
		return
	var stage := flow.fight.stage
	if backdrop == null or backdrop.number != stage:
		if backdrop != null:
			backdrop.queue_free()
		backdrop = StageBackdrop.new()
		add_child(backdrop)
		backdrop.setup(content.stage_number(stage))
	backdrop.visible = true
	# RankingScreen makes the turning backdrop camera the game's camera (FUN_80046458).
	backdrop.show_view(flow.sim.camera.view.copy(), flow.sub <= 2)


func _build_fight_view() -> void:
	if fight_view != null:
		fight_view.queue_free()
		fight_view = null
	var fight := flow.fight
	if fight.fighters[0].body == null:
		return
	var models: Array[CharacterModel] = []
	var slots := PackedInt32Array()
	var chars := PackedInt32Array()
	# The records that fight: Tekken Force's third too (Tekken Ball's third is the ball's
	# stand-in attacker and is not drawn).
	for p in fight.count:
		var f := fight.fighters[p]
		models.append(content.model(f.costume_slot))
		slots.append(f.costume_slot)
		chars.append(f.char_id)
	_set_audio_fighters()
	fight_view = FightView.new()
	add_child(fight_view)
	var stage := content.stage_number(fight.stage)
	var light_stage: StageData = null
	if fight.mode == GameMode.FORCE and TekkenForce.tile_only_level(flow.region.fight_index):
		light_stage = content.stage_number(TekkenForce.TILE_ONLY_LIGHT_STAGE)
	fight_view.setup(stage, effect_data, models, slots, chars, light_stage)
	fight_view.setup_modes(stage, fight.tables, content.mode_ram("volley") if fight.mode == GameMode.BALL else null)
	hud.setup(hud_data, slots)
	practice_view.camera = fight_view.rig.camera


## The records whose model changed since the fight view showed them.
func _replace_fighters() -> void:
	var fight := flow.fight
	for i in _model_loads.size():
		if flow.sim.model_loads[i] == _model_loads[i]:
			continue
		_model_loads[i] = flow.sim.model_loads[i]
		var f := fight.fighters[i]
		if fight_view != null and i < fight_view.fighters.size():
			fight_view.replace_fighter(i, content.model(f.costume_slot), f.costume_slot)
		hud.set_slot(i, f.costume_slot)
	_set_audio_fighters()


## The two fighters whose voices the audio plays.
func _set_audio_fighters() -> void:
	var fighters := flow.fight.fighters
	audio.set_fighters(PackedInt32Array([fighters[0].costume_slot, fighters[1].costume_slot]),
		PackedInt32Array([fighters[0].char_id, fighters[1].char_id]))


func _rumble() -> void:
	vibration.drive(Settings.flag("vibration") and not settings_view.visible)


## The views whose stage follows the Stage backdrops setting, as it changes (a fight's view is
## built for each fight): the attract demonstration's stage is built again, the ranking's backdrop
## when next shown.
func _rebuild_stages() -> void:
	enbu_view.queue_free()
	enbu_view = EnbuView.new()
	add_child(enbu_view)
	enbu_view.setup(content.stage(ENBU_STAGE), effect_data)
	if backdrop != null:
		backdrop.queue_free()
		backdrop = null


func _process(_delta: float) -> void:
	if flow == null:
		return
	if stats.visible:
		stats.text = "%s  state %d sub %d  step %d  %.0f µs" % [options.render_stats(get_viewport()), flow.state,
			flow.sub, steps, _step_usec]
	var window := get_viewport().get_visible_rect().size
	var fraction := options.weight(Engine.get_physics_interpolation_fraction()) if Settings.flag("interpolation") else 1.0
	var surround := Settings.text("framing") == "stage"
	# Each 3D view has its own camera: the one shown must be the current one.
	if fight_view != null and fight_view.visible:
		fight_view.rig.camera.make_current()
		fight_view.interpolate(fraction, window)
		bars.frame(fight_view.rig.visible_rect, fight_view.clear_colour if surround else Color.BLACK)
		hud.place(fight_view.rig.frame_rect)
		mode_hud.place(fight_view.rig.frame_rect)
		practice_view.place(fight_view.rig.frame_rect)
		move_list_view.place(fight_view.rig.frame_rect)
		RenderingServer.set_default_clear_color(fight_view.clear_colour)
		bars.visible = true
	elif backdrop != null and backdrop.visible:
		backdrop.rig.camera.make_current()
		backdrop.interpolate(fraction, window)
		RenderingServer.set_default_clear_color(Color.BLACK)
		bars.visible = false
	elif enbu_view.visible:
		enbu_view.rig.camera.make_current()
		enbu_view.interpolate(fraction, window)
		bars.frame(enbu_view.rig.visible_rect, Color.BLACK)
		RenderingServer.set_default_clear_color(Color.BLACK)
		bars.visible = true
	else:
		RenderingServer.set_default_clear_color(Color.BLACK)
		bars.visible = false


## A movie of the title (`title`) or of the ending and the Theater (`ending`, played inside a
## frame: the flow waits for it).
func _start_movie(which: int, blocking: bool) -> void:
	var list: Array = movies.get("ending" if blocking else "title", [])
	if which < 0 or which >= list.size():
		flow.movie_result = 1
		return
	var entry: Dictionary = list[which]
	var level: float = entry.get("volume", 127)
	if blocking:
		audio.stop_all()
	if not movie.play(Assets.path("movies"), entry, level / 127.0, which if blocking else -1):
		flow.movie_result = 1


func _on_movie_finished() -> void:
	if flow.movie_blocking or (flow.state == GameFlow.State.TITLE and flow.sub == 2):
		flow.movie_result = 1
