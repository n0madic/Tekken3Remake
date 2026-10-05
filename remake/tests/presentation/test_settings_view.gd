extends TestSuite
## The settings screen's layout (SettingsView): two tabs (General: the game and sound settings,
## the display ones beside them; Controls: vibration, the touch controls and the keyboard layouts'
## key fields beside their pad pictures); two columns on landscape windows, one on narrow windows; every row and
## field inside the panel and the panel inside the window, none overlapping, on both tabs; the
## settings with a single choice not shown; a tap or a drag on a volume's bar sets it there; a key
## field takes the next key, Escape keeps its key.


func _view(window: Vector2, tab: int) -> SettingsView:
	var view := SettingsView.new()
	view.size = window
	view.tab = tab
	view._layout()
	return view


func _check(window: Vector2, columns: int) -> void:
	for tab in SettingsView.TABS.size():
		var view := _view(window, tab)
		var at := "%s on tab %d" % [window, tab]
		expect_equal(view.columns(), columns, "%d column(s) at %s" % [columns, at])
		expect(Rect2(Vector2.ZERO, window).encloses(view._panel), "the panel inside the window at %s" % at)
		var placed: Array[Rect2] = []
		for i in view._rects.size():
			var r := view._rects[i]
			var there := view.shown(i) and (SettingsView.tab_of(i) == tab or SettingsView.tab_of(i) < 0)
			if not there:
				expect_equal(r, Rect2(), "%d not on this tab: no place at %s" % [i, at])
				continue
			expect(view._panel.encloses(r), "%d inside the panel at %s" % [i, at])
			placed.append(r)
		placed.append_array(view._pictures)
		for a in placed.size():
			for b in range(a + 1, placed.size()):
				expect(not placed[a].grow(-1.0).intersects(placed[b].grow(-1.0)), "%s and %s apart at %s" % [placed[a],
					placed[b], at])
		if tab == SettingsView.GAME and columns == 2:
			var display := view._rects[SettingsView.column_break[SettingsView.GAME]]
			expect(display.position.x > view._rects[0].end.x - 1.0, "Display heads the right column")
			expect_equal(display.position.y, view._rects[0].position.y, "both columns start on one line")
			var sound := view._rects[SettingsView.ROWS.find(["SETTINGS_SOUND", ""])]
			expect(sound.position.x == view._rects[0].position.x and sound.position.y > view._rects[0].position.y,
				"Sound under Game")
		if tab == SettingsView.CONTROLS:
			expect_equal(view._pictures.size(), 2, "two pad pictures at %s" % at)
			var fields := 0
			for i in view._rects.size():
				if SettingsView.is_field(i) and view._rects[i].size != Vector2.ZERO:
					fields += 1
			expect_equal(fields, 28, "14 key fields per pad at %s" % at)
			for layout in 2:
				expect(view._pictures[layout].has_point(view.button_spot(layout, PadState.CROSS)), "Cross on its picture")
		else:
			expect(view._rects[SettingsView.ROWS.find(["vibration", ""])] == Rect2(), "Controls rows only on their tab")
		view.free()


func test_layout() -> void:
	_check(Vector2(2400, 1080), 2)
	_check(Vector2(1280, 720), 2)
	_check(Vector2(1024, 768), 2)
	_check(Vector2(720, 1280), 1)


func test_panel_keeps_its_size_across_tabs() -> void:
	var general := _view(Vector2(1280, 720), SettingsView.GAME)
	var controls := _view(Vector2(1280, 720), SettingsView.CONTROLS)
	expect_equal(general._panel, controls._panel, "one panel for both tabs")
	general.free()
	controls.free()


func test_no_keyboard_no_key_fields() -> void:
	var view := SettingsView.new()
	view.keyboard = false
	view.size = Vector2(1280, 720)
	view.tab = SettingsView.CONTROLS
	view._layout()
	expect(view._pictures.is_empty(), "no pad pictures")
	expect_equal(view._rects[SettingsView.first_field], Rect2(), "no key fields")
	expect_equal(view._rects[SettingsView.default_keys_row], Rect2(), "no Default keys")
	expect(view._rects[SettingsView.ROWS.find(["vibration", ""])] != Rect2(), "vibration stays")
	expect(view._rects[SettingsView.back_row] != Rect2(), "and Back")
	view.free()


func test_single_choices_hidden() -> void:
	var view := SettingsView.new()
	var packs := Settings.texture_packs
	Settings.texture_packs = PackedStringArray()
	var pack := SettingsView.ROWS.find(["texture_pack", "SETTINGS_PACK_HELP"])
	expect(not view.shown(pack) and not view._selectable(pack), "no texture pack installed: the row is hidden")
	view.size = Vector2(1280, 720)
	view._layout()
	expect_equal(view.neighbour(pack - 1, Vector2.DOWN), pack + 1, "and skipped")
	Settings.texture_packs = PackedStringArray(["hd"])
	expect(view.shown(pack), "shown with a pack")
	Settings.texture_packs = packs
	view.free()


func test_tabs_and_directions() -> void:
	var saved := Settings.values.duplicate(true)     # left and right change the settings they pass
	var view := _view(Vector2(1280, 720), SettingsView.GAME)
	view.visible = true
	view._suppress = false
	view.handle(PadState.R1)
	expect_equal(view.tab, SettingsView.CONTROLS, "R1: the next tab")
	expect_equal(view.cursor, SettingsView.ROWS.find(["vibration", ""]), "on its first row")
	view.handle(0)
	var l2 := SettingsView.field_of(0, PadState.L2)
	for n in 4:
		view.handle(PadState.DOWN)
		view.handle(0)
		if view.cursor == l2:
			break
	expect(SettingsView.is_field(view.cursor), "down reaches the key fields")
	var from := view.cursor
	view.handle(PadState.RIGHT)
	view.handle(0)
	expect(view.cursor != from and SettingsView.is_field(view.cursor), "right moves between fields")
	view.handle(PadState.L1)
	expect_equal(view.tab, SettingsView.GAME, "L1: back")
	expect_equal(Settings.values, saved, "no setting changed on the way")
	Settings.values = saved
	Settings._dirty = false
	view.free()


func test_key_field_takes_the_next_key() -> void:
	var saved: Variant = Settings.values[GameSettings.KEY_BINDINGS]
	var layouts := Pads.layouts.duplicate()
	Settings.reset_key_bindings()
	var view := _view(Vector2(1280, 720), SettingsView.CONTROLS)
	view.visible = true
	view._suppress = false
	var field := SettingsView.field_of(1, PadState.TRIANGLE)
	view.cursor = field
	view.handle(PadState.CROSS)
	expect_equal(view.listening, field, "Cross: waiting for a key")
	var key := InputEventKey.new()
	key.pressed = true
	key.physical_keycode = KEY_ESCAPE
	view._input(key)
	expect_equal(view.listening, -1, "Escape: no longer waiting")
	expect_equal(Settings.bound_key(1, PadState.TRIANGLE), KEY_I, "and the key kept")
	view.listening = field
	key.physical_keycode = KEY_N
	view._input(key)
	expect_equal(Settings.bound_key(1, PadState.TRIANGLE), KEY_N, "the next key bound")
	expect_equal(view.listening, -1, "done")
	view.handle(PadState.CROSS)
	expect_equal(view.listening, -1, "buttons held from the binding wait for their release")
	Settings.set_value(GameSettings.KEY_BINDINGS, saved)
	Pads.layouts = layouts
	Settings._dirty = false
	view.free()


func test_volume_by_touch() -> void:
	var view := _view(Vector2(2400, 1080), SettingsView.GAME)
	var row := SettingsView.ROWS.find(["volume_music", ""])
	var saved := Settings.number("volume_music")
	var bar := view._bar_rect(row)
	var touch := InputEventScreenTouch.new()
	touch.pressed = true
	touch.position = Vector2(bar.position.x + bar.size.x * 0.3, bar.get_center().y)
	view._gui_input(touch)
	expect_equal(Settings.number("volume_music"), 3, "a tap at 30 % of the bar")
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(bar.position.x - 50.0, bar.get_center().y + 200.0)
	view._gui_input(drag)
	expect_equal(Settings.number("volume_music"), 0, "a drag past its start")
	touch.pressed = false
	view._gui_input(touch)
	drag.position = bar.end
	view._gui_input(drag)
	expect_equal(Settings.number("volume_music"), 0, "a drag after the finger lifted changes nothing")
	var label := InputEventScreenTouch.new()
	label.pressed = true
	label.position = view._rects[row].position + Vector2(10, 10)
	view._gui_input(label)
	expect_equal(Settings.number("volume_music"), 0, "a tap on the label only picks the row")
	expect_equal(view.cursor, row, "picked")
	Settings.set_value("volume_music", saved)
	Settings._dirty = false
	view.free()
