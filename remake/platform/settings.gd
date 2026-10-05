class_name GameSettings
extends Node
## The remake's own settings (autoload `Settings`, remake-plan.md#save-data-and-settings): the
## Gameplay fixes, the game texts' language (English: the USA release's), the graphics preset and its options, the texture pack, audio
## volumes, vibration, touch controls, the keyboard layouts, the interface language and the memory
## card in use (its progress is ProgressCard's). They are kept in
## `user://settings.json` apart from the game's progress. The game's own options (difficulty,
## rounds, the key configuration, ...) stay on its OPTIONS screen and in the progress block.
##
## Each setting is one key of SCHEMA with its choices; `choices(key)` narrows them to what this
## build and platform offer (the presets by the renderer, the texture packs found).

signal changed(key: String)

const VOLUME_STEPS := 10
## key → [default, choices]; an empty choice list is an integer 0–VOLUME_STEPS, a list with
## "" first is a name chosen at run time (the texture packs).
const SCHEMA := {
	"gameplay_fixes": [false, [false, true]],
	"memory_card": [1, [1, 2]],
	"game_texts": ["english", ["english", "japanese"]],
	"language": ["auto", ["auto", "en", "ja"]],
	"fullscreen": [false, [false, true]],
	"graphics": ["auto", ["auto", "web", "mobile", "mobile_high", "desktop_low", "desktop_high"]],
	"texture_filter": ["smooth", ["smooth", "crisp"]],
	"shading": ["smooth", ["original", "smooth", "curved"]],
	"texture_pack": ["", [""]],
	"interpolation": [true, [true, false]],
	"framing": ["stage", ["stage", "bars"]],
	"stage_backdrops": ["arcade", ["arcade", "playstation"]],
	"volume_music": [VOLUME_STEPS, []],
	"volume_sfx": [VOLUME_STEPS, []],
	"volume_voices": [VOLUME_STEPS, []],
	"volume_system": [VOLUME_STEPS, []],
	"vibration": [true, [true, false]],
	"touch_controls": ["auto", ["auto", "on", "off"]],
	"touch_macros": ["throws", ["throws", "all", "none"]],
	"touch_size": [100, [70, 85, 100, 115, 130]],
}
## The keys of the two keyboard layouts (InputRouter.layouts), kept apart from SCHEMA as
## {"keyboard_1": {"up": "W", ...}, "keyboard_2": {...}}: each InputRouter.BINDABLE button and its
## key's name (OS.get_keycode_string); no key twice, none of InputRouter.RESERVED_KEYS.
const KEY_BINDINGS := "key_bindings"
const LAYOUT_NAMES := ["keyboard_1", "keyboard_2"]
const BUS_VOLUMES := {"volume_music": &"Music", "volume_sfx": &"SFX", "volume_voices": &"Voices", "volume_system": &"System"}
## The presets each renderer can draw (remake-plan.md#quality-presets).
const RENDERER_PRESETS := {
	"gl_compatibility": ["web"],
	"mobile": ["mobile", "mobile_high"],
	"forward_plus": ["desktop_low", "desktop_high"],
}

var store := SaveStore.new()
var values: Dictionary = {}
var usa_converted := false              ## the USA localization was converted (imported/usa)
var texture_packs := PackedStringArray()
## Choices of this session only (`--graphics=`, `--shading=`, `--texture-pack=`): key → value, read
## before the saved ones (and offered among the choices) and never saved; choosing anything for
## that key in the settings ends it.
var session: Dictionary = {}
var _dirty := false                     ## changed since the last save


func _ready() -> void:
	usa_converted = Assets.has_group("usa")
	texture_packs = TexturePacks.installed()
	load_saved()


func load_saved() -> void:
	values = sanitized(store.load_settings())
	_apply_volumes()
	_apply_key_layouts()


## `saved` with unknown keys dropped and every missing or invalid value replaced by its default.
static func sanitized(saved: Dictionary) -> Dictionary:
	var out := {}
	for key: String in SCHEMA:
		var entry: Array = SCHEMA[key]
		var value: Variant = saved.get(key, entry[0])
		var list: Array = entry[1]
		# JSON keeps numbers as floats.
		var is_number := value is float or value is int
		if list.is_empty():
			value = clampi(JsonFile.number(value), 0, VOLUME_STEPS) if is_number else entry[0]
		elif list[0] is String and (list[0] as String).is_empty():
			value = str(value)
		else:
			if list[0] is int and is_number:
				value = JsonFile.number(value)
			if not value in list:
				value = entry[0]
		out[key] = value
	out[KEY_BINDINGS] = sanitized_bindings(saved.get(KEY_BINDINGS))
	# A Japanese interface saved where it cannot be drawn (the web builds) follows the system.
	if out["language"] == "ja" and not japanese_interface():
		out["language"] = "auto"
	return out


## The default keyboard layouts (InputRouter.DEFAULT_LAYOUTS) in the settings' form.
static func default_bindings() -> Dictionary:
	var out := {}
	for layout in LAYOUT_NAMES.size():
		var keys := {}
		var defaults: Dictionary = InputRouter.DEFAULT_LAYOUTS[layout]
		for key: Key in defaults:
			keys[_button_name(defaults[key] as int)] = OS.get_keycode_string(key)
		out[LAYOUT_NAMES[layout]] = keys
	return out


## Saved key bindings with every missing, unknown, reserved or repeated key replaced: by the
## button's default when it is free, else by a free default key of another button (a saved key
## took it, so that one's default is left over); every other binding is kept.
static func sanitized_bindings(saved: Variant) -> Dictionary:
	var defaults := default_bindings()
	if not saved is Dictionary:
		return defaults
	var out := {}
	var used := {}
	var missing: Array[PackedStringArray] = []     # [layout, button] still without a key
	for layout_name: String in LAYOUT_NAMES:
		var given: Dictionary = (saved as Dictionary).get(layout_name) if (saved as Dictionary).get(layout_name) is Dictionary else {}
		var keys := {}
		for button: String in InputRouter.BINDABLE:
			var key := key_of(given.get(button))
			if key == KEY_NONE or used.has(key):
				missing.append(PackedStringArray([layout_name, button]))
				continue
			used[key] = true
			keys[button] = OS.get_keycode_string(key)
		out[layout_name] = keys
	var spare: Array[Key] = []                     # default keys nobody holds, in layout order
	for layout_name: String in LAYOUT_NAMES:
		for button: String in InputRouter.BINDABLE:
			var key := key_of((defaults[layout_name] as Dictionary)[button])
			if not used.has(key):
				spare.append(key)
	for entry in missing:
		var key := key_of((defaults[entry[0]] as Dictionary)[entry[1]])
		if used.has(key):
			# The default of the button that holds this one's (a swap), else any left over.
			var holder := _holder(out, OS.get_keycode_string(key))
			var swapped := key_of((defaults[holder[0]] as Dictionary)[holder[1]]) if not holder.is_empty() else KEY_NONE
			key = swapped if swapped != KEY_NONE and not used.has(swapped) else _first_free(spare, used)
			if key == KEY_NONE:
				return defaults     # cannot happen: each missing button leaves a default key over
		used[key] = true
		(out[entry[0]] as Dictionary)[entry[1]] = OS.get_keycode_string(key)
	return out


static func _first_free(keys: Array[Key], used: Dictionary) -> Key:
	for key in keys:
		if not used.has(key):
			return key
	return KEY_NONE


## [layout, button] bound to a key name in `bindings`, empty if none.
static func _holder(bindings: Dictionary, name: String) -> PackedStringArray:
	for layout_name: String in bindings:
		var keys: Dictionary = bindings[layout_name]
		for button: String in keys:
			if keys[button] == name:
				return PackedStringArray([layout_name, button])
	return PackedStringArray()


## The key a saved name stands for; KEY_NONE for anything but a plain key no layout may take.
static func key_of(name: Variant) -> Key:
	if not name is String or (name as String).is_empty():
		return KEY_NONE
	var key := OS.find_keycode_from_string(name as String)
	if key & KEY_MODIFIER_MASK or key in InputRouter.RESERVED_KEYS:
		return KEY_NONE
	return key


static func _button_name(bit: int) -> String:
	return str(InputRouter.BINDABLE.find_key(bit))


## A keyboard layout (0: left, 1: right) as key → pad bit, for InputRouter.layouts.
func key_layout(layout: int) -> Dictionary:
	var keys: Dictionary = (values[KEY_BINDINGS] as Dictionary)[LAYOUT_NAMES[layout]]
	var out := {}
	for button: String in keys:
		out[key_of(keys[button])] = InputRouter.BINDABLE[button]
	return out


## The key of a button in a keyboard layout.
func bound_key(layout: int, bit: int) -> Key:
	var keys: Dictionary = (values[KEY_BINDINGS] as Dictionary)[LAYOUT_NAMES[layout]]
	return key_of(keys[_button_name(bit)])


## Binds a key to a button of a keyboard layout; the button that had the key (in either layout)
## takes this button's old one.
func bind_key(layout: int, bit: int, key: Key) -> void:
	if key_of(OS.get_keycode_string(key)) == KEY_NONE:
		return
	var bindings: Dictionary = (values[KEY_BINDINGS] as Dictionary).duplicate(true)
	var button := _button_name(bit)
	var name := OS.get_keycode_string(key)
	var old: String = (bindings[LAYOUT_NAMES[layout]] as Dictionary)[button]
	var holder := _holder(bindings, name)
	if not holder.is_empty():
		(bindings[holder[0]] as Dictionary)[holder[1]] = old
	(bindings[LAYOUT_NAMES[layout]] as Dictionary)[button] = name
	set_value(KEY_BINDINGS, bindings)


func reset_key_bindings() -> void:
	set_value(KEY_BINDINGS, default_bindings())


## A setting's value; a choice this build does not offer reads as its first one (converted from
## the USA disc the game texts are English), while the saved choice stays for another build.
func value(key: String) -> Variant:
	if session.has(key):
		return session[key]
	var v: Variant = values.get(key, (SCHEMA[key] as Array)[0])
	if key == "game_texts" and not v in choices(key):
		return choices(key)[0]
	return v


func flag(key: String) -> bool:
	var v: Variant = value(key)
	return v is bool and v as bool


func text(key: String) -> String:
	return str(value(key))


func number(key: String) -> int:
	var v: Variant = value(key)
	return v as int if v is int else 0


func level(key: String) -> float:
	return float(number(key)) / VOLUME_STEPS


## The choices this build offers for a key (empty: an integer 0–VOLUME_STEPS).
func choices(key: String) -> Array:
	var list := _offered(key)
	if session.has(key) and not session[key] in list:
		list = list + [session[key]]
	return list


func _offered(key: String) -> Array:
	var list: Array = (SCHEMA[key] as Array)[1]
	match key:
		"graphics":
			return ["auto"] + (RENDERER_PRESETS.get(renderer(), []) as Array)
		"texture_pack":
			return [""] + Array(texture_packs)
		"language":
			return list if japanese_interface() else ["auto", "en"]
		"game_texts":
			return list if Assets.japanese_texts() else ["english"]
		"stage_backdrops":
			return list if Assets.has_group("arcade") else ["playstation"]
		"fullscreen":
			return list if OS.has_feature("pc") else [false]
	return list


func set_value(key: String, v: Variant) -> void:
	# A session choice ends with any other choice, the saved one too.
	if session.has(key):
		if session[key] == v:
			return
		session.erase(key)
	elif values.get(key) == v:
		return
	values[key] = v
	if BUS_VOLUMES.has(key):
		_apply_volumes()
	if key == KEY_BINDINGS:
		_apply_key_layouts()
	elif key == "fullscreen":
		_apply_fullscreen(v as bool)
	_dirty = true
	changed.emit(key)


## Writes the settings when they changed since the last save (the settings screen saves as it
## closes; leaving or pausing the application saves too). A failed write keeps them unsaved, so
## the next save tries again.
func save() -> void:
	if _dirty and store.save_settings(values):
		_dirty = false


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST or what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_PREDELETE:
		save()


## The next (or with `step` −1 the previous) choice of a key, wrapping; volumes stop at their ends.
func cycle(key: String, step: int) -> void:
	var list := choices(key)
	if list.is_empty():
		set_value(key, clampi(number(key) + step, 0, VOLUME_STEPS))
		return
	if list.size() == 1:
		return
	var i := list.find(value(key))
	set_value(key, list[posmod(i + step, list.size())])


## Whether `event` is a press of a fullscreen hotkey: F11 or Alt + Enter, on the systems where they
## act (InputRouter.fullscreen_hotkeys).
static func is_fullscreen_hotkey(event: InputEvent, os_name: String = OS.get_name()) -> bool:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo or not InputRouter.fullscreen_hotkeys(os_name):
		return false
	return key.physical_keycode == InputRouter.FULLSCREEN_KEY \
		or InputRouter.is_alt_enter(key.physical_keycode, key.alt_pressed, os_name)


## Fullscreen is for the desktop builds (the others' windows are the system's).
func fullscreen_offered() -> bool:
	return choices("fullscreen").size() > 1


func _input(event: InputEvent) -> void:
	if is_fullscreen_hotkey(event):
		get_viewport().set_input_as_handled()
		toggle_fullscreen()


## Switches the window between fullscreen and windowed, from the window's mode as it is now (it can
## have been changed outside the setting: the engine's --fullscreen, the system).
func toggle_fullscreen() -> void:
	if not fullscreen_offered():
		return
	var on := not _window_fullscreen()
	if values.get("fullscreen") == on:
		_apply_fullscreen(on)
	else:
		set_value("fullscreen", on)


## The saved fullscreen to the window at the start, by the entry points once their options are read
## (DevOptions.parse): only a saved fullscreen is applied, so a window already made fullscreen (the
## engine's --fullscreen) is left as it is.
func apply_window() -> void:
	if flag("fullscreen"):
		_apply_fullscreen(true)


static func _window_fullscreen() -> bool:
	var mode := DisplayServer.window_get_mode()
	return mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN


## The window's mode to `on` (a borderless full-screen window, not the exclusive mode: it switches
## quickly and keeps the desktop's other windows usable). Not on builds without the setting (a
## synced settings file) and not without a window.
func _apply_fullscreen(on: bool) -> void:
	if DisplayServer.get_name() == "headless" or not fullscreen_offered():
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)


## The renderer this run uses: its method name as in the project settings.
static func renderer() -> String:
	return str(RenderingServer.get_current_rendering_method())


## The graphics preset in effect: the chosen one, or for "auto" the renderer's first (desktop
## builds start on the high preset).
func preset() -> String:
	var chosen := text("graphics")
	var offered: Array = RENDERER_PRESETS.get(renderer(), ["desktop_low"])
	if chosen in offered:
		return chosen
	return "desktop_high" if "desktop_high" in offered else str(offered[0])


## Whether the touch controls are shown: "auto" on devices with a touch screen.
func touch_enabled() -> bool:
	match text("touch_controls"):
		"on":
			return true
		"off":
			return false
	return DisplayServer.is_touchscreen_available()


## The touch controls' size as a share of the default one ("touch_size" is a percentage).
func touch_scale() -> float:
	return number("touch_size") / 100.0


## The interface locale: "auto" follows the system's language (Japanese or else English);
## English where the Japanese interface cannot be drawn.
func locale() -> String:
	if not japanese_interface():
		return "en"
	var chosen := text("language")
	if chosen != "auto":
		return chosen
	return "ja" if OS.get_locale_language() == "ja" else "en"


## Whether the interface can be shown in Japanese: the project bundles no CJK font, so it relies on
## the system fonts' fallback, which the web builds do not have.
## TODO: bundle a CJK font (Noto Sans JP, OFL) so the web builds get the Japanese interface too.
static func japanese_interface() -> bool:
	return not OS.has_feature("web")


func _apply_volumes() -> void:
	for key: String in BUS_VOLUMES:
		var bus := AudioServer.get_bus_index(BUS_VOLUMES[key] as StringName)
		if bus < 0:
			continue
		var share := level(key)
		AudioServer.set_bus_mute(bus, share <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(share, 0.001)))


## The keyboard layouts to the input router (Pads).
func _apply_key_layouts() -> void:
	for layout in LAYOUT_NAMES.size():
		Pads.layouts[layout] = key_layout(layout)


## After the audio buses exist (the audio director adds them).
func apply_audio() -> void:
	_apply_volumes()
