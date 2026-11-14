extends TestSuite
## What both games share (GameShell): the settings both builds offer reach the PlayStation's game
## and the arcade's alike.

const GAMES := ["res://app/game.gd", "res://app/arcade_game.gd"]


func _game(path: String) -> Node:
	return (load(path) as GDScript).new() as Node


func test_interface_language_follows_the_setting() -> void:
	if not GameSettings.japanese_interface():
		skip("no Japanese interface on this platform")
		return
	var saved: Variant = Settings.values.get("language")
	var saved_locale := TranslationServer.get_locale()
	Settings.values["language"] = "ja"
	for path: String in GAMES:
		TranslationServer.set_locale("en")
		var game := _game(path)
		game.call("_on_setting_changed", "language")
		expect_equal(TranslationServer.get_locale(), "ja", "%s: the interface in Japanese" % path.get_file())
		game.free()
	Settings.values["language"] = saved
	TranslationServer.set_locale(saved_locale)


## Touch controls turned off in the settings give player 1 back to the device they displaced.
func test_touch_turned_off_gives_player_one_back() -> void:
	var saved: Variant = Settings.values.get("touch_controls")
	var saved_devices := Pads.devices.duplicate()
	Settings.values["touch_controls"] = "off"
	for path: String in GAMES:
		Pads.devices = PackedInt32Array([InputRouter.KEYBOARD, InputRouter.NO_DEVICE])
		Pads.assign_touch()
		var game := _game(path)
		game.call("_show_touch")
		expect_equal(Pads.devices, PackedInt32Array([InputRouter.KEYBOARD, InputRouter.NO_DEVICE]),
			"%s: the keyboard is player 1 again" % path.get_file())
		game.free()
	Settings.values["touch_controls"] = saved
	Pads.devices = saved_devices
