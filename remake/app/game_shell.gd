class_name GameShell
extends Node
## What the two games share around their flows (game.gd, the PlayStation's; arcade_game.gd, the
## arcade's): the development pad script, the web build's wait for a first input, the message and
## stats lines (F3 shows or hides the stats), the settings panel with its gear and the touch
## controls, and the reactions to the settings both builds offer. Each game adds its own reactions
## (calling these) and its own way into and out of the settings.

const MESSAGE_SHARE := 0.035           ## the message's text height as a share of the window height
const MESSAGE_MIN_SIZE := 18

var options := DevOptions.new()            ## --screenshot, --frames, --speed, --seed, --stats
var message := Label.new()
var stats := Label.new()
var settings_view := SettingsView.new()
var settings_button := SettingsButton.new()
var touch := TouchControls.new()
var steps := 0
var _pad_script: Array[Vector2i] = []      ## `--pads`: the steps' pads (game.gd's after its replay)
var _waiting_for_gesture := false          ## the web build before its first input
var _release_pads := false                 ## after the settings: the game gets no buttons until all are released


## A development pad script: lines `<steps> <pad 1> [<pad 2>]` (hex words) played in turn; `#`
## starts a comment.
func _load_pad_script(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		Log.warning("game: no pad script %s" % path)
		return
	while not f.eof_reached():
		var words := f.get_line().get_slice("#", 0).split(" ", false)
		if words.size() < 2:
			continue
		var second := words[2].hex_to_int() if words.size() > 2 else 0
		for i in words[0].to_int():
			_pad_script.append(Vector2i(words[1].hex_to_int(), second))


## The message line (a missing conversion, the web build's start prompt) over the window, and the
## stats line in its corner.
func _setup_labels() -> void:
	stats.position = Vector2(8, 8)
	stats.visible = options.stats
	stats.add_theme_color_override("font_outline_color", Color.BLACK)
	stats.add_theme_constant_override("outline_size", 4)
	message.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	message.add_theme_font_size_override("font_size", maxi(MESSAGE_MIN_SIZE, int(get_viewport().get_visible_rect().size.y * MESSAGE_SHARE)))
	message.visible = false


## The settings panel and its gear to the game's handlers; the settings both builds offer applied now
## and as they change. After the audio node is in: its buses take their volumes.
func _follow_settings() -> void:
	settings_view.closed.connect(_on_settings_closed)
	settings_button.pressed.connect(_open_settings)
	Settings.changed.connect(_on_setting_changed)
	Settings.apply_audio()
	RenderQuality.apply_viewport(get_viewport())
	TranslationServer.set_locale(Settings.locale())
	_show_touch()


## Browsers start audio only after a user gesture: the web build waits for the first input before
## the game (and its sound) starts. A screenshot session does not wait.
func _wait_for_gesture() -> void:
	if not OS.has_feature("web") or not options.screenshot_path.is_empty():
		return
	message.text = tr("WEB_START")
	message.visible = true
	set_physics_process(false)
	_waiting_for_gesture = true


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


## The touch controls where the settings want them, with their macro buttons (hidden while the
## settings are open: the panel takes the taps). Turned off, they give player 1 back.
func _show_touch() -> void:
	touch.set_macros(Settings.text("touch_macros"))
	touch.set_scale_share(Settings.touch_scale())
	touch.visible = Settings.touch_enabled() and not settings_view.visible
	if not touch.visible:
		touch.reset()
	if not Settings.touch_enabled():
		Pads.release_touch()


## The reactions to the settings both builds offer (the texture pack's cache is dropped by the
## settings themselves, before this).
func _on_setting_changed(key: String) -> void:
	match key:
		"language":
			TranslationServer.set_locale(Settings.locale())
		"graphics":
			RenderQuality.apply_viewport(get_viewport())
		"texture_pack", "texture_filter":
			_reload_pictures()
		"touch_controls", "touch_macros", "touch_size":
			_show_touch()


## The pictures the 2D views took from TexturePacks when they were set up, again (the fighters and
## stages reload their own).
func _reload_pictures() -> void:
	pass


## Select, the gear: the settings open where the game allows it.
func _open_settings() -> void:
	pass


func _on_settings_closed() -> void:
	pass
