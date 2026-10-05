extends TestSuite
## The remake's settings (GameSettings): a saved file is sanitized, unknown keys dropped and bad
## values replaced by defaults; a Japanese interface stays only where it can be drawn, the
## Japanese game texts only when the game was converted from a Japanese disc.


func test_sanitized() -> void:
	var out := GameSettings.sanitized({"volume_music": 14.6, "graphics": "ultra", "unknown": 1, "language": "ja",
		"touch_size": 115.0, "texture_pack": "hd"})
	expect_equal(out["volume_music"], GameSettings.VOLUME_STEPS, "a volume clamped")
	expect_equal(out["graphics"], "auto", "an unknown choice back to its default")
	expect(not out.has("unknown"), "unknown keys dropped")
	expect_equal(out["touch_size"], 115, "a size read back from JSON's float")
	expect(out["touch_size"] is int, "as an integer")
	expect_equal(out["texture_pack"], "hd", "a texture pack's name kept")
	expect_equal(GameSettings.sanitized({"touch_size": 120})["touch_size"], 100, "a size not offered: the default")
	expect_equal(out["language"], "ja" if GameSettings.japanese_interface() else "auto",
		"Japanese only where the interface can show it")
	expect_equal(out.size(), GameSettings.SCHEMA.size() + 1, "every key present, and the key bindings")
	expect_equal(out[GameSettings.KEY_BINDINGS], GameSettings.default_bindings(), "no bindings saved: the defaults")


func test_key_bindings_sanitized() -> void:
	var defaults := GameSettings.default_bindings()
	expect_equal((defaults["keyboard_1"] as Dictionary)["up"], "W", "the left layout's Up")
	expect_equal((defaults["keyboard_2"] as Dictionary)["r2"], "Semicolon", "the right layout's R2")
	var saved := defaults.duplicate(true)
	(saved["keyboard_1"] as Dictionary)["up"] = "H"
	(saved["keyboard_1"] as Dictionary)["down"] = "Escape"
	(saved["keyboard_1"] as Dictionary)["left"] = "Nonsense"
	(saved["keyboard_2"] as Dictionary)["up"] = "H"
	var out := GameSettings.sanitized_bindings(saved)
	expect_equal((out["keyboard_1"] as Dictionary)["up"], "H", "a free key kept")
	expect_equal((out["keyboard_1"] as Dictionary)["down"], "S", "Escape is reserved: the default")
	expect_equal((out["keyboard_1"] as Dictionary)["left"], "A", "an unknown key: the default")
	expect_equal((out["keyboard_2"] as Dictionary)["up"], "Up", "a key taken already: the default")
	(saved["keyboard_2"] as Dictionary)["up"] = "W"
	(saved["keyboard_1"] as Dictionary)["up"] = "W"
	(saved["keyboard_1"] as Dictionary)["down"] = "Up"
	out = GameSettings.sanitized_bindings(saved)
	expect_equal((out["keyboard_1"] as Dictionary)["down"], "Up", "a free key kept, another layout's default too")
	expect_equal((out["keyboard_2"] as Dictionary)["up"], "S", "its default taken: the default key left over")
	expect_equal((out["keyboard_1"] as Dictionary)["up"], "W", "the other bindings stay")
	# A key reserved since it was bound (F3), its button's default taken by another button.
	saved = defaults.duplicate(true)
	(saved["keyboard_1"] as Dictionary)["select"] = "F3"
	(saved["keyboard_1"] as Dictionary)["start"] = "Q"
	(saved["keyboard_1"] as Dictionary)["cross"] = "H"
	out = GameSettings.sanitized_bindings(saved)
	expect_equal((out["keyboard_1"] as Dictionary)["start"], "Q", "Start keeps Q")
	expect_equal((out["keyboard_1"] as Dictionary)["select"], "Space", "Select takes the key Start left")
	expect_equal((out["keyboard_1"] as Dictionary)["cross"], "H", "custom bindings are not reset")
	expect_equal(GameSettings.sanitized_bindings("junk"), defaults, "not a dictionary")


func test_bind_key_swaps() -> void:
	var saved: Variant = Settings.values[GameSettings.KEY_BINDINGS]
	var layouts := Pads.layouts.duplicate()
	Settings.reset_key_bindings()
	Settings.bind_key(0, PadState.UP, KEY_S)
	expect_equal(Settings.bound_key(0, PadState.UP), KEY_S, "bound")
	expect_equal(Settings.bound_key(0, PadState.DOWN), KEY_W, "Down had S: it takes Up's old W")
	Settings.bind_key(0, PadState.CROSS, KEY_J)
	expect_equal(Settings.bound_key(0, PadState.CROSS), KEY_J, "a key of the other layout")
	expect_equal(Settings.bound_key(1, PadState.CROSS), KEY_F, "swapped across the layouts")
	expect_equal(Pads.layouts[0].get(KEY_J), PadState.CROSS, "the router follows")
	Settings.bind_key(0, PadState.CROSS, KEY_ESCAPE)
	expect_equal(Settings.bound_key(0, PadState.CROSS), KEY_J, "Escape is not taken")
	Settings.reset_key_bindings()
	expect_equal(Settings.values[GameSettings.KEY_BINDINGS], GameSettings.default_bindings(), "back to the defaults")
	Settings.set_value(GameSettings.KEY_BINDINGS, saved)
	Pads.layouts = layouts
	Settings._dirty = false


func test_a_failed_save_is_retried() -> void:
	var path := store_path()
	var saved_path := Settings.store.settings_path
	var saved: int = Settings.number("volume_music")
	Settings.store.settings_path = "user://no_such_folder/settings.json"
	Settings.set_value("volume_music", (saved + 1) % GameSettings.VOLUME_STEPS)
	Settings.save()
	expect(Settings._dirty, "a failed write leaves the settings unsaved")
	Settings.store.settings_path = path
	Settings.save()
	expect(not Settings._dirty, "saved once the folder is writable")
	expect(FileAccess.file_exists(path), "the retry wrote the file")
	DirAccess.remove_absolute(path)
	Settings.store.settings_path = saved_path
	Settings.set_value("volume_music", saved)
	Settings._dirty = false


func store_path() -> String:
	return "user://test_settings_retry.json"


func test_game_texts_follow_the_source() -> void:
	var saved: Dictionary = Assets.manifest
	Assets.manifest = saved.duplicate()
	var saved_texts: Variant = Settings.values.get("game_texts")
	Settings.values["game_texts"] = "japanese"
	Assets.manifest["source"] = "usa"
	expect(not Assets.japanese_texts(), "the USA disc has no Japanese texts")
	expect_equal(Settings.choices("game_texts"), ["english"], "English only")
	expect_equal(Settings.text("game_texts"), "english", "read as English")
	Settings.cycle("game_texts", 1)
	expect_equal(Settings.values["game_texts"], "japanese", "the saved choice stays")
	Assets.manifest["source"] = "jp_orig"
	expect(Assets.japanese_texts(), "the original Japanese release has them")
	expect_equal(Settings.choices("game_texts"), ["english", "japanese"], "both")
	expect_equal(Settings.text("game_texts"), "japanese", "the saved choice again")
	Assets.manifest.erase("source")
	expect_equal(Assets.source(), "jp_rev1", "a folder converted before sources were recorded")
	Assets.manifest = saved
	Settings.values["game_texts"] = saved_texts


func test_session_preset() -> void:
	var offered: Array = GameSettings.RENDERER_PRESETS.get(GameSettings.renderer(), ["desktop_low"])
	var saved: Variant = Settings.values.get("graphics")
	var chosen := str(offered[offered.size() - 1])
	Settings.session["graphics"] = chosen
	expect_equal(Settings.preset(), chosen, "--graphics= wins over the setting")
	expect_equal(Settings.text("graphics"), chosen, "and the settings screen shows it")
	Settings.set_value("graphics", "auto" if saved != "auto" else chosen)
	expect(not Settings.session.has("graphics"), "choosing a preset in the settings ends the session's")
	Settings.values["graphics"] = saved
	Settings._dirty = false


func test_session_shading_ends_with_any_choice() -> void:
	var saved: Variant = Settings.values.get("shading")
	Settings.values["shading"] = "smooth"
	Settings.session["shading"] = "original"
	expect_equal(Settings.text("shading"), "original", "--shading= wins over the setting")
	Settings.set_value("shading", "original")
	expect(Settings.session.has("shading"), "choosing the session's own value changes nothing")
	Settings.set_value("shading", "smooth")
	expect(not Settings.session.has("shading"), "choosing the saved value still ends the session's")
	expect_equal(Settings.text("shading"), "smooth", "the setting again")
	if saved == null:
		Settings.values.erase("shading")
	else:
		Settings.values["shading"] = saved
	Settings._dirty = false


## A pack folder of the session is a choice of its own: the settings show it (its path, apart from
## an installed pack of the same name), cycle from it, and drop it with any other choice.
func test_session_texture_pack_ends_with_any_choice() -> void:
	var saved: Variant = Settings.values.get("texture_pack")
	var saved_packs := Settings.texture_packs
	Settings.texture_packs = PackedStringArray(["a", "hd"])
	Settings.values["texture_pack"] = ""
	TexturePacks.use_for_session("user://elsewhere/hd/")
	expect_equal(TexturePacks.chosen(), "user://elsewhere/hd", "--texture-pack= wins over the setting")
	expect_equal(Settings.choices("texture_pack"), ["", "a", "hd", "user://elsewhere/hd"], "offered after the installed packs")
	expect_equal(TexturePacks.pack_dir("user://elsewhere/hd"), "user://elsewhere/hd", "a folder is read where it is")
	expect_equal(TexturePacks.pack_dir("hd"), TexturePacks.directory.path_join("hd"), "the installed pack of that name stays apart")
	Settings.cycle("texture_pack", -1)
	expect_equal(Settings.text("texture_pack"), "hd", "Left goes to the choice before it")
	expect(not Settings.session.has("texture_pack"), "and ends the session's")
	expect_equal(Settings.choices("texture_pack"), ["", "a", "hd"], "the folder is no choice any more")
	DirAccess.make_dir_recursive_absolute("user://test_session_pack/mypack")
	var absolute := ProjectSettings.globalize_path("user://test_session_pack/mypack")
	TexturePacks.use_for_session(absolute.get_base_dir() + "/./mypack/")
	expect_equal(TexturePacks.chosen(), absolute, "a folder is kept as its absolute path")
	expect_equal(TexturePacks.pack_dir(absolute), absolute, "and read there")
	DirAccess.remove_absolute("user://test_session_pack/mypack")
	DirAccess.remove_absolute("user://test_session_pack")
	TexturePacks.use_for_session("hd")
	expect_equal(TexturePacks.chosen(), "hd", "a name is no folder")
	expect_equal(TexturePacks.pack_dir(absolute), TexturePacks.directory.path_join(absolute),
		"a folder that is not the session's is read under the installed packs")
	expect_equal(TexturePacks.pack_dir("hd"), TexturePacks.directory.path_join("hd"), "a name is an installed pack")
	Settings.session.erase("texture_pack")
	Settings.texture_packs = saved_packs
	if saved == null:
		Settings.values.erase("texture_pack")
	else:
		Settings.values["texture_pack"] = saved
	TexturePacks.clear()
	Settings._dirty = false


func _key(code: Key, alt := false, echo := false) -> InputEventKey:
	var event := InputEventKey.new()
	event.pressed = true
	event.physical_keycode = code
	event.alt_pressed = alt
	event.echo = echo
	return event


func test_fullscreen_setting_is_sanitized() -> void:
	expect_equal(GameSettings.sanitized({})["fullscreen"], false, "windowed by default")
	expect_equal(GameSettings.sanitized({"fullscreen": "yes"})["fullscreen"], false, "a bad value: the default")
	expect_equal(GameSettings.sanitized({"fullscreen": true})["fullscreen"], true, "a saved fullscreen kept")
	expect(InputRouter.FULLSCREEN_KEY in InputRouter.RESERVED_KEYS, "F11 is no layout's key")


func test_fullscreen_hotkeys_by_system() -> void:
	for os_name: String in ["Windows", "macOS", "Linux"]:
		var acts: bool = os_name == "Windows"
		expect_equal(GameSettings.is_fullscreen_hotkey(_key(KEY_F11), os_name), acts, "F11 on " + os_name)
		expect_equal(GameSettings.is_fullscreen_hotkey(_key(KEY_ENTER, true), os_name), acts, "Alt + Enter on " + os_name)
		expect_equal(GameSettings.is_fullscreen_hotkey(_key(KEY_KP_ENTER, true), os_name), acts, "Alt + keypad Enter on " + os_name)
	expect(not GameSettings.is_fullscreen_hotkey(_key(KEY_ENTER), "Windows"), "Enter alone is the right player's Start")
	expect(not GameSettings.is_fullscreen_hotkey(_key(KEY_F11, false, true), "Windows"), "a held key does not toggle again")
	var release := _key(KEY_F11)
	release.pressed = false
	expect(not GameSettings.is_fullscreen_hotkey(release, "Windows"), "a release does not toggle")


func test_alt_enter_is_not_a_button() -> void:
	expect(InputRouter.is_alt_enter(KEY_ENTER, true, "Windows"), "Alt + Enter on Windows")
	expect(InputRouter.is_alt_enter(KEY_KP_ENTER, true, "Windows"), "Alt + keypad Enter on Windows")
	expect(not InputRouter.is_alt_enter(KEY_ENTER, false, "Windows"), "Enter alone stays a button")
	expect(not InputRouter.is_alt_enter(KEY_SPACE, true, "Windows"), "another key with Alt stays a button")
	expect(not InputRouter.is_alt_enter(KEY_ENTER, true, "macOS"), "no hotkey, no mask elsewhere")


## The toggle reads the window's mode (a headless run's stays windowed): from windowed it turns the
## setting on, and a setting already on while the window is not fullscreen stays on (the window is
## made fullscreen to match, not the setting turned off).
func test_toggle_fullscreen_follows_the_window() -> void:
	if not Settings.fullscreen_offered():
		return
	var saved: Variant = Settings.values["fullscreen"]
	var was_dirty := Settings._dirty
	Settings.values["fullscreen"] = false
	Settings.toggle_fullscreen()
	expect_equal(Settings.flag("fullscreen"), true, "windowed window, setting off → on")
	Settings.toggle_fullscreen()
	expect_equal(Settings.flag("fullscreen"), true, "windowed window, setting already on: stays on")
	Settings.values["fullscreen"] = saved
	Settings._dirty = was_dirty
