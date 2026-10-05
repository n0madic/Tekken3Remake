class_name SettingsView
extends Control
## The remake's settings screen (GameSettings): a vector panel over the main menu, opened with
## Select there (Esc, the keyboard's Select keys, or the gear on touch screens). It has two tabs,
## switched with L1 / R1, Tab or a click on them: General (the game and sound settings, the display
## ones beside them) and
## Controls (vibration, the touch controls and, where a keyboard can be at hand, the keys of the
## two keyboard layouts: a pad picture per player with a field beside each button). The
## directions move between the rows and fields by their places on the screen; on a setting left
## and right (or Cross and Start) change it, Circle or Select (Esc) close the screen. Cross, Enter
## or a click on a field waits for the field's new key (Esc cancels, a gamepad button too). A
## click or tap on a row changes it too (on a volume's bar it sets the volume there, and a drag
## along the bar follows the finger), one outside the panel closes it (the touch controls are
## hidden while it is open). Settings with a single choice in this build are not shown. The rows
## stand in two columns on landscape windows, in one on narrow ones. The interface strings are
## translated (app/translations).

signal closed

const ROWS := [
	["SETTINGS_GAME", ""], ["gameplay_fixes", "SETTINGS_FIXES_HELP"], ["game_texts", "SETTINGS_TEXTS_HELP"],
	["language", "SETTINGS_LANGUAGE_HELP"], ["memory_card", "SETTINGS_CARD_HELP"],
	["SETTINGS_SOUND", ""], ["volume_music", ""], ["volume_sfx", ""], ["volume_voices", ""], ["volume_system", ""],
	["SETTINGS_DISPLAY", ""], ["graphics", "SETTINGS_GRAPHICS_HELP"], ["texture_filter", "SETTINGS_FILTER_HELP"],
	["shading", "SETTINGS_SHADING_HELP"],
	["texture_pack", "SETTINGS_PACK_HELP"], ["interpolation", "SETTINGS_INTERPOLATION_HELP"],
	["framing", "SETTINGS_FRAMING_HELP"], ["stage_backdrops", "SETTINGS_BACKDROPS_HELP"],
	["vibration", ""], ["touch_controls", "SETTINGS_TOUCH_HELP"], ["touch_macros", "SETTINGS_MACROS_HELP"],
	["touch_size", "SETTINGS_TOUCH_SIZE_HELP"], ["default_keys", "SETTINGS_DEFAULT_KEYS_HELP"],
	["back", ""],
]
const TABS := ["SETTINGS_TAB_GAME", "SETTINGS_TAB_CONTROLS"]
const GAME := 0
const CONTROLS := 1
## Each tab's first row; Back stands on both.
static var tab_start := PackedInt32Array([0, ROWS.find(["vibration", ""])])
## Each tab's first row of the second column.
static var column_break := PackedInt32Array([ROWS.find(["SETTINGS_DISPLAY", ""]),
	ROWS.find(["touch_macros", "SETTINGS_MACROS_HELP"])])
static var back_row := ROWS.size() - 1
static var default_keys_row := ROWS.find(["default_keys", "SETTINGS_DEFAULT_KEYS_HELP"])
## The key fields beside a pad picture, top to bottom: its left side, then its right side.
const FIELD_BUTTONS := [
	PadState.L2, PadState.L1, PadState.UP, PadState.LEFT, PadState.RIGHT, PadState.DOWN, PadState.SELECT,
	PadState.R2, PadState.R1, PadState.TRIANGLE, PadState.SQUARE, PadState.CIRCLE, PadState.CROSS, PadState.START,
]
const FIELDS_PER_SIDE := 7
const LAYOUTS := 2
## The fields follow the rows in the focus order: layout × FIELD_BUTTONS.size() + button.
static var first_field := ROWS.size()
static var item_count := ROWS.size() + LAYOUTS * FIELD_BUTTONS.size()
## The pad picture (the game's KEY CONFIGURATION one, screens/pad_0.png) and each button's place on it.
const PAD_SIZE := Vector2(144, 136)
const BUTTON_SPOTS := {
	PadState.L2: Vector2(30, 10), PadState.L1: Vector2(30, 24), PadState.R2: Vector2(114, 10), PadState.R1: Vector2(114, 24),
	PadState.UP: Vector2(30, 69), PadState.LEFT: Vector2(20, 81), PadState.RIGHT: Vector2(39, 81), PadState.DOWN: Vector2(30, 93),
	PadState.SELECT: Vector2(63, 92), PadState.START: Vector2(81, 92),
	PadState.TRIANGLE: Vector2(114, 62), PadState.SQUARE: Vector2(101, 82), PadState.CIRCLE: Vector2(126, 82),
	PadState.CROSS: Vector2(114, 99),
}
const SHOULDER_NAMES := {
	PadState.L2: "L2", PadState.L1: "L1", PadState.R2: "R2", PadState.R1: "R1", PadState.SELECT: "SELECT", PadState.START: "START",
}
const GLYPH_RADIUS := 1.45            ## a face button's ButtonGlyphs radius per half of its arrow size
const LABEL_SHARE := 0.55              ## of a row's width: the label, then the value
const BAR_SHARE := 0.72                ## of the value's width: a volume's bar
const BAR_SLACK := 0.4                 ## of the row height: taps this far beside a bar still set it
const DIM := Color(0, 0, 0, 0.72)
const PANEL := Color(0.07, 0.08, 0.12, 0.94)
const EDGE := Color(0.55, 0.6, 0.75, 0.6)
const TEXT := Color(0.88, 0.9, 0.95)
const MUTED := Color(0.6, 0.63, 0.72)
const GROUP := Color(1.0, 0.78, 0.35)
const FOCUS := Color(0.3, 0.45, 0.85, 0.55)
const TAB_ON := Color(0.3, 0.45, 0.85, 0.3)
const BOX := Color(1, 1, 1, 0.08)
const LEADER := Color(1, 1, 1, 0.3)
const VALUE := Color(1, 1, 1)
const ROW_SHARE := 0.05                ## row height as a share of the window height
const MIN_ROW := 22.0
const COLUMN_ROWS := 14.0              ## a column's width in row heights
const TWO_COLUMNS_ASPECT := 1.2        ## the narrowest window (width / height) with two columns
const EXTRA_LINES := 5.0               ## the title, the help lines and the keys line, in rows
const TAB_LINES := 1.0                 ## the tabs, in rows
const FIELD_PITCH := 0.95              ## a key field's line, in rows
const PAD_LINES := 1.1 + FIELDS_PER_SIDE * FIELD_PITCH + 0.3   ## a pad picture with its title and fields
const PICTURE_SHARE := 0.42            ## the widest pad picture, of its panel's width
const GLYPH_ROWS := 1.2                ## a field's button glyph, in rows
const SCREEN_MARGIN := 8.0
const REPEAT_DELAY := 16               ## frames before a held direction repeats, then every REPEAT_RATE
const REPEAT_RATE := 4
const UP := PadState.UP
const DOWN := PadState.DOWN
const LEFT := PadState.LEFT
const RIGHT := PadState.RIGHT
const CONFIRM := PadState.CROSS | PadState.START
const CANCEL := PadState.CIRCLE | PadState.SELECT
const PREVIOUS_TAB := PadState.L1
const NEXT_TAB := PadState.R1

var cursor := 1
var tab := GAME
var listening := -1                    ## the key field waiting for its new key
var keyboard := true                   ## the key fields are shown (a keyboard can be at hand)
var pad_texture: Texture2D             ## the pad picture (none: a frame stands for it)
var font: Font
var _held := 0
var _held_frames := 0
var _rects: Array[Rect2] = []          ## each row's and field's place; empty for those not shown
var _tab_rects: Array[Rect2] = []
var _pictures: Array[Rect2] = []       ## the pad pictures (none on the Game tab or without a keyboard)
var _column_of := PackedInt32Array()   ## each row's column on the tab last arranged
var _line_of := PackedInt32Array()     ## and its line there (−1: not there)
var _dragging := -1                    ## the volume row a finger or the mouse drags along
var _panel := Rect2()
var _row := MIN_ROW
var _suppress := true                  ## buttons held when the screen opened are ignored until released


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func open() -> void:
	keyboard = Pads.has_keyboard()
	listening = -1
	cursor = _first_item(tab)
	_suppress = true
	visible = true
	queue_redraw()


func close() -> void:
	visible = false
	listening = -1
	Settings.save()
	closed.emit()


## One frame of pad input (both players' held words).
func handle(held: int) -> void:
	if not visible:
		return
	if listening >= 0:
		# The new key arrives as a key event (_input); the pads wait for their release.
		_held = held
		_suppress = true
		return
	if _suppress:
		if held != 0:
			_held = held
			return
		_suppress = false
	var pressed := held & ~_held
	if held != 0 and held == _held:
		_held_frames += 1
	else:
		_held_frames = 0
	_held = held
	var repeat := pressed
	if _held_frames >= REPEAT_DELAY and (_held_frames - REPEAT_DELAY) % REPEAT_RATE == 0:
		repeat |= held & (UP | DOWN | LEFT | RIGHT)
	if pressed & CANCEL:
		close()
		return
	# Nothing new pressed nor repeating: the screen stays as drawn (it is drawn again on a change,
	# a resize and a pointer's touch).
	if pressed == 0 and repeat == 0:
		return
	_layout()
	if pressed & (PREVIOUS_TAB | NEXT_TAB):
		switch_tab(-1 if pressed & PREVIOUS_TAB else 1)
	elif repeat & UP:
		cursor = neighbour(cursor, Vector2.UP)
	elif repeat & DOWN:
		cursor = neighbour(cursor, Vector2.DOWN)
	elif repeat & (LEFT | RIGHT):
		var step := -1 if repeat & LEFT else 1
		if _is_setting(cursor):
			_change(cursor, step)
		else:
			cursor = neighbour(cursor, Vector2(step, 0))
	elif pressed & CONFIRM:
		_change(cursor, 1)
	queue_redraw()


## Keys: a waiting field's new key, Tab between the tabs; a gamepad button stops the wait.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	var key_event := event as InputEventKey
	if key_event != null and key_event.pressed and not key_event.echo:
		var key := key_event.physical_keycode
		if listening >= 0:
			_handled()
			# The layouts read physical keys only (InputRouter): a key event without one cannot
			# be bound, and the field keeps waiting.
			if key == KEY_NONE:
				return
			if not key in InputRouter.RESERVED_KEYS:
				Settings.bind_key(field_layout(listening), field_button(listening), key)
			_stop_listening()
		elif key_event.keycode == KEY_TAB:
			_handled()
			switch_tab(-1 if key_event.shift_pressed else 1)
	elif listening >= 0 and event is InputEventJoypadButton and event.is_pressed():
		_handled()
		_stop_listening()


func _handled() -> void:
	if is_inside_tree():
		get_viewport().set_input_as_handled()


func _stop_listening() -> void:
	listening = -1
	_suppress = true
	queue_redraw()


func switch_tab(step: int) -> void:
	tab = posmod(tab + step, TABS.size())
	keyboard = Pads.has_keyboard()     # a keyboard attached while the screen is open
	listening = -1
	cursor = _first_item(tab)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	var motion := event as InputEventMouseMotion
	var drag := event as InputEventScreenDrag
	# A tap arrives as the touch and as a mouse click emulated from it (a drag as a mouse motion
	# too): only the touch counts.
	if event.device == InputEvent.DEVICE_ID_EMULATION and (click != null or motion != null):
		return
	if (click != null and click.button_index == MOUSE_BUTTON_LEFT and not click.pressed) \
			or (touch != null and not touch.pressed):
		_dragging = -1
		return
	if motion != null or drag != null:
		if _dragging >= 0 and (drag != null or motion.button_mask & MOUSE_BUTTON_MASK_LEFT):
			accept_event()
			_set_level(_dragging, drag.position.x if drag != null else motion.position.x)
		return
	var at := Vector2.INF
	if click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
		at = click.position
	elif touch != null and touch.pressed:
		at = touch.position
	if at == Vector2.INF:
		return
	accept_event()
	_layout()
	var was_listening := listening >= 0
	listening = -1
	for t in _tab_rects.size():
		if _tab_rects[t].has_point(at):
			if t != tab:
				switch_tab(t - tab)
			return
	for i in _rects.size():
		if not _rects[i].has_point(at) or not _selectable(i):
			continue
		cursor = i
		if _is_level(i):
			# On the bar (or its number) the volume goes where the finger is; the label only picks the row.
			if at.x >= _bar_rect(i).position.x - _row * BAR_SLACK:
				_dragging = i
				_set_level(i, at.x)
		else:
			_change(i, 1)
		queue_redraw()
		return
	if was_listening:
		queue_redraw()
	elif not _panel.has_point(at):
		close()


## A volume row's bar.
func _bar_rect(i: int) -> Rect2:
	var r := _rects[i]
	var pad := _row * 0.6
	var inner := r.size.x - pad * 0.8
	var at := Vector2(r.position.x + pad * 0.4 + inner * LABEL_SHARE, r.position.y)
	return Rect2(at.x, at.y + _row * 0.36, inner * (1.0 - LABEL_SHARE) * BAR_SHARE, _row * 0.28)


## Sets a volume from a place along its bar.
func _set_level(i: int, x: float) -> void:
	var bar := _bar_rect(i)
	var share := clampf((x - bar.position.x) / bar.size.x, 0.0, 1.0)
	Settings.set_value(_key(i), roundi(share * GameSettings.VOLUME_STEPS))
	queue_redraw()


static func _key(i: int) -> String:
	return str((ROWS[i] as Array)[0]) if i < ROWS.size() else ""


static func _is_group(i: int) -> bool:
	return _key(i).begins_with("SETTINGS_")


static func is_field(i: int) -> bool:
	return i >= first_field


## A key field's keyboard layout (0: left, 1: right) and button.
static func field_layout(i: int) -> int:
	return (i - first_field) / FIELD_BUTTONS.size()


static func field_button(i: int) -> int:
	return FIELD_BUTTONS[(i - first_field) % FIELD_BUTTONS.size()] as int


## The key field of a layout's button.
static func field_of(layout: int, bit: int) -> int:
	return first_field + layout * FIELD_BUTTONS.size() + FIELD_BUTTONS.find(bit)


## The tab a row or field stands on (−1: Back, on both).
static func tab_of(i: int) -> int:
	if i == back_row:
		return -1
	return CONTROLS if is_field(i) or i >= tab_start[CONTROLS] else GAME


## A row or field changed by left and right or picked by Cross: the settings that have a value.
func _is_setting(i: int) -> bool:
	return not is_field(i) and i != back_row and i != default_keys_row and not _is_group(i)


func _selectable(i: int) -> bool:
	return not _is_group(i) and shown(i) and (tab_of(i) == tab or tab_of(i) < 0)


## Whether a row or field is shown on its tab: groups, Back, volumes, the settings with a choice in
## this build, and the keys where a keyboard can be at hand.
func shown(i: int) -> bool:
	if is_field(i) or i == default_keys_row:
		return keyboard
	var key := _key(i)
	if _is_group(i) or key == "back" or _is_level(i):
		return true
	return Settings.choices(key).size() > 1


func _is_level(i: int) -> bool:
	return GameSettings.SCHEMA.has(_key(i)) and ((GameSettings.SCHEMA[_key(i)] as Array)[1] as Array).is_empty()


func _first_item(t: int) -> int:
	for i in item_count:
		if tab_of(i) == t and _selectable(i):
			return i
	return back_row


## The nearest selectable row or field from `from` in a direction (by their places on the screen);
## up and down wrap around.
func neighbour(from: int, direction: Vector2) -> int:
	if _rects.size() != item_count or _rects[from].size == Vector2.ZERO:
		return from
	var origin := _rects[from].get_center()
	var found := _nearest(from, origin, direction)
	if found < 0 and direction.y != 0.0:
		origin.y = _panel.end.y + 1.0 if direction.y < 0.0 else _panel.position.y - 1.0
		found = _nearest(from, origin, direction)
	return found if found >= 0 else from


## The nearest in a direction: first among those facing `from` (across the line of sight from its
## edge), else by distance with the sideways one counted too.
func _nearest(from: int, origin: Vector2, direction: Vector2) -> int:
	var best := -1
	var best_score := INF
	var source := _rects[from]
	for i in _rects.size():
		if i == from or _rects[i].size == Vector2.ZERO or not _selectable(i):
			continue
		var r := _rects[i]
		var along := (r.get_center() - origin).dot(direction)
		if along <= 1.0:
			continue
		var across := 0.0          # how far beside the line of sight
		var facing := false
		if direction.x != 0.0:
			across = maxf(0.0, maxf(r.position.y - origin.y, origin.y - r.end.y))
			facing = r.position.y < source.end.y and r.end.y > source.position.y
		else:
			across = maxf(0.0, maxf(r.position.x - origin.x, origin.x - r.end.x))
			facing = r.position.x < source.end.x and r.end.x > source.position.x
		var score := along if facing else along + across + _panel.size.length()
		if score < best_score:
			best_score = score
			best = i
	return best


func _change(i: int, step: int) -> void:
	if i == back_row:
		close()
		return
	if i == default_keys_row:
		Settings.reset_key_bindings()
		return
	if is_field(i):
		listening = i
		return
	Settings.cycle(_key(i), step)


## The shown value of a setting.
func value_text(key: String) -> String:
	var v: Variant = Settings.value(key)
	if (((GameSettings.SCHEMA[key] as Array)[1]) as Array).is_empty():
		return "%d" % Settings.number(key)
	if v is bool:
		return tr("SETTINGS_ON") if v else tr("SETTINGS_OFF")
	if key == "texture_pack":
		return str(v) if not str(v).is_empty() else tr("SETTINGS_NONE")
	if key == "language" and str(v) != "auto":
		return tr("LANGUAGE_" + str(v).to_upper())
	if key == "memory_card":
		return tr("SETTINGS_VALUE_CARD") % Settings.number(key)
	if key == "touch_size":
		return "%d%%" % Settings.number(key)
	if key == "graphics" and str(v) == "auto":
		return "%s (%s)" % [tr("SETTINGS_VALUE_AUTO"), tr("SETTINGS_VALUE_" + Settings.preset().to_upper())]
	return tr("SETTINGS_VALUE_" + str(v).to_upper())


## Two columns on landscape windows, one on narrow ones.
func columns() -> int:
	return 2 if size.x >= size.y * TWO_COLUMNS_ASPECT else 1


## Rows standing after the pad pictures on the Controls tab.
func _is_footer(i: int, t: int) -> bool:
	return t == CONTROLS and (i == default_keys_row or i == back_row)


## Each row's column and line on a tab (_column_of, _line_of); returns the lines the deeper column takes.
func _arrange(t: int, count: int) -> int:
	_column_of.resize(ROWS.size())
	_line_of.resize(ROWS.size())
	_line_of.fill(-1)
	var lines_in := PackedInt32Array([0, 0])
	for i in ROWS.size():
		if (tab_of(i) != t and tab_of(i) >= 0) or not shown(i) or _is_footer(i, t):
			continue
		var column := 1 if count == 2 and i >= column_break[t] else 0
		_column_of[i] = column
		_line_of[i] = lines_in[column]
		lines_in[column] += 1
	return maxi(lines_in[0], lines_in[1])


## The rows after the pad pictures shown on a tab.
func _footer(t: int) -> Array[int]:
	var out: Array[int] = []
	for i: int in [default_keys_row, back_row]:
		if _is_footer(i, t) and shown(i):
			out.append(i)
	return out


## The lines a tab's rows, pad pictures and footer take.
func _content_lines(t: int, count: int) -> float:
	var lines := float(_arrange(t, count))
	if t == CONTROLS and keyboard:
		lines += PAD_LINES * (1 if count == 2 else LAYOUTS)
	var footer := _footer(t).size()
	if footer > 0:
		lines += 1 if count == 2 else footer
	return lines


## The panel, the row height and every row's, field's and tab's rectangle for the window's size
## (the panel keeps its size on both tabs).
func _layout() -> void:
	var count := columns()
	var content := 0.0
	for t in TABS.size():
		content = maxf(content, _content_lines(t, count))
	var lines := content + EXTRA_LINES + TAB_LINES
	_row = minf(maxf(MIN_ROW, size.y * ROW_SHARE), (size.y - 2.0 * SCREEN_MARGIN) / lines)
	var pad := _row * 0.6
	var width := minf(size.x - 2.0 * SCREEN_MARGIN, count * COLUMN_ROWS * _row + (count + 1) * pad)
	var height := _row * lines
	_panel = Rect2((size - Vector2(width, height)) / 2.0, Vector2(width, height))
	var column_width := (width - (count + 1) * pad) / count
	var left := _panel.position.x + pad * 0.6     # the first column's rows, a column further each column_step
	var column_step := column_width + pad
	_tab_rects.clear()
	var tab_width := (width - 2.0 * pad) / TABS.size()
	for t in TABS.size():
		_tab_rects.append(Rect2(_panel.position.x + pad + t * tab_width, _panel.position.y + _row * 1.55, tab_width,
			_row * 0.9))
	_rects.clear()
	_rects.resize(item_count)
	_pictures.clear()
	var top := _panel.position.y + _row * (1.7 + TAB_LINES)
	var y := top + _arrange(tab, count) * _row
	for i in ROWS.size():
		if _line_of[i] >= 0:
			_rects[i] = Rect2(left + _column_of[i] * column_step, top + _line_of[i] * _row, column_width + pad * 0.8, _row)
	if tab == CONTROLS and keyboard:
		for layout in LAYOUTS:
			var column := layout if count == 2 else 0
			var at := Vector2(left + column * column_step, y + (0 if count == 2 else layout) * PAD_LINES * _row)
			_place_pad(layout, Rect2(at, Vector2(column_width + pad * 0.8, PAD_LINES * _row)))
		y += PAD_LINES * _row * (1 if count == 2 else LAYOUTS)
	var footer := _footer(tab)
	for n in footer.size():
		var column := n if count == 2 else 0
		var line := 0 if count == 2 else n
		_rects[footer[n]] = Rect2(left + column * column_step, y + line * _row, column_width + pad * 0.8, _row)


## A pad picture in its panel, centred between its two columns of key fields.
func _place_pad(layout: int, panel: Rect2) -> void:
	var pitch := _row * FIELD_PITCH
	var area := Rect2(panel.position.x, panel.position.y + _row * 1.1, panel.size.x, pitch * FIELDS_PER_SIDE)
	var picture_size := Vector2(area.size.y * 0.95 * PAD_SIZE.x / PAD_SIZE.y, area.size.y * 0.95)
	if picture_size.x > panel.size.x * PICTURE_SHARE:
		picture_size *= panel.size.x * PICTURE_SHARE / picture_size.x
	var picture := Rect2(area.get_center() - picture_size / 2.0, picture_size)
	_pictures.append(picture)
	var gap := _row * 0.4
	var field_width := (panel.size.x - picture_size.x) / 2.0 - gap
	for k in FIELD_BUTTONS.size():
		var right := k >= FIELDS_PER_SIDE
		var x := picture.end.x + gap if right else panel.position.x
		_rects[first_field + layout * FIELD_BUTTONS.size() + k] = Rect2(x,
			area.position.y + (k % FIELDS_PER_SIDE) * pitch, field_width, pitch * 0.88)


## A button's place on a layout's pad picture.
func button_spot(layout: int, bit: int) -> Vector2:
	var picture := _pictures[layout]
	return picture.position + (BUTTON_SPOTS[bit] as Vector2) * picture.size / PAD_SIZE


func _draw() -> void:
	_layout()
	draw_rect(Rect2(Vector2.ZERO, size), DIM)
	var row := _row
	var text_size := int(row * 0.56)
	draw_rect(_panel, PANEL)
	draw_rect(_panel, EDGE, false, 1.5)
	var pad := row * 0.6
	var x := _panel.position.x + pad
	var width := _panel.size.x - 2.0 * pad
	draw_string(font, Vector2(x, _panel.position.y + row * 1.1), tr("SETTINGS_TITLE"), HORIZONTAL_ALIGNMENT_CENTER,
		width, int(row * 0.8), VALUE)
	for t in _tab_rects.size():
		var r := _tab_rects[t]
		if t == tab:
			draw_rect(r, TAB_ON)
		draw_string(font, Vector2(r.position.x, r.position.y + row * 0.62), tr(str(TABS[t])), HORIZONTAL_ALIGNMENT_CENTER,
			r.size.x, int(row * 0.5), VALUE if t == tab else MUTED)
	# One line under every tab sets the tabs apart from the rows.
	if not _tab_rects.is_empty():
		var strip := _tab_rects[0].merge(_tab_rects[_tab_rects.size() - 1])
		draw_rect(Rect2(strip.position.x, strip.end.y - 2.0, strip.size.x, 2.0), GROUP)
	var bottom := 0.0
	for i in ROWS.size():
		var r := _rects[i]
		if r.size == Vector2.ZERO:
			continue
		bottom = maxf(bottom, r.end.y)
		var key := _key(i)
		var left := r.position.x + pad * 0.4
		var inner := r.size.x - pad * 0.8
		var base := r.position.y + row * 0.68
		if _is_group(i):
			draw_string(font, Vector2(left, base), tr(key), HORIZONTAL_ALIGNMENT_LEFT, inner, int(row * 0.5), GROUP)
			continue
		if i == cursor:
			draw_rect(r, FOCUS)
		var label := tr("SETTINGS_BACK") if key == "back" else tr("SETTING_" + key.to_upper())
		draw_string(font, Vector2(left + row * 0.4, base), label, HORIZONTAL_ALIGNMENT_LEFT, inner * LABEL_SHARE,
			text_size, TEXT)
		if _is_setting(i):
			_draw_value(key, i, Vector2(left + inner * LABEL_SHARE, r.position.y), inner * (1.0 - LABEL_SHARE), row,
				text_size)
	for layout in _pictures.size():
		_draw_pad(layout)
		bottom = maxf(bottom, _pictures[layout].end.y)
	# The focused row's or field's help line.
	var help := _help(cursor)
	if not help.is_empty():
		draw_multiline_string(font, Vector2(x, bottom + row * 0.7), help, HORIZONTAL_ALIGNMENT_LEFT, width,
			int(row * 0.45), 3, MUTED)
	var keys := tr("SETTINGS_KEYS")
	draw_string(font, Vector2(x, _panel.end.y - row * 0.35), keys, HORIZONTAL_ALIGNMENT_CENTER, width,
		_fitted(keys, width, int(row * 0.42)), MUTED)


func _help(i: int) -> String:
	if is_field(i):
		return tr("SETTINGS_BIND_HELP")
	var help := tr(str((ROWS[i] as Array)[1])) if not str((ROWS[i] as Array)[1]).is_empty() else ""
	if _key(i) == "game_texts" and not Settings.usa_converted:
		help += " " + tr("SETTINGS_TEXTS_MISSING")
	return help


func _draw_value(key: String, i: int, at: Vector2, width: float, row: float, text_size: int) -> void:
	if _is_level(i):
		var bar := _bar_rect(i)
		draw_rect(bar, Color(1, 1, 1, 0.15))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * Settings.level(key), bar.size.y)), VALUE)
		draw_string(font, Vector2(bar.end.x + row * 0.3, at.y + row * 0.68), value_text(key), HORIZONTAL_ALIGNMENT_LEFT,
			-1, text_size, VALUE)
		return
	var text := value_text(key)
	if i == cursor:
		text = "<  %s  >" % text
	draw_string(font, Vector2(at.x, at.y + row * 0.68), text, HORIZONTAL_ALIGNMENT_CENTER, width, text_size, VALUE)


## A layout's pad picture with its title, its key fields and their leader lines to the buttons.
func _draw_pad(layout: int) -> void:
	var row := _row
	var picture := _pictures[layout]
	var first := _rects[field_of(layout, FIELD_BUTTONS[0] as int)]
	draw_string(font, Vector2(first.position.x, first.position.y - row * 0.4), tr("SETTINGS_PLAYER_KEYS") % (layout + 1),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(row * 0.5), GROUP)
	if pad_texture != null:
		draw_texture_rect(pad_texture, picture, false)
	else:
		draw_rect(picture, EDGE, false, 1.0)
	for k in FIELD_BUTTONS.size():
		var bit: int = FIELD_BUTTONS[k]
		var i := field_of(layout, bit)
		var r := _rects[i]
		var right := k >= FIELDS_PER_SIDE
		var glyph_width := minf(row * GLYPH_ROWS, r.size.x * 0.4)
		var glyph := Rect2(r.end.x - glyph_width if right else r.position.x, r.position.y, glyph_width, r.size.y)
		var box := Rect2(r.position.x if right else glyph.end.x, r.position.y, r.size.x - glyph_width, r.size.y)
		var spot := button_spot(layout, bit)
		var from := Vector2(box.position.x if right else box.end.x, box.get_center().y)
		draw_line(from, spot, GROUP if i == cursor else LEADER, 1.0, true)
		draw_circle(spot, maxf(2.0, row * 0.08), GROUP if i == cursor else LEADER)
		if i == cursor:
			draw_rect(r, FOCUS)
		draw_rect(box, BOX)
		draw_rect(box, EDGE, false, 1.0)
		_draw_glyph(bit, glyph)
		var text := tr("SETTINGS_PRESS_KEY") if i == listening else OS.get_keycode_string(Settings.bound_key(layout, bit))
		var inset := row * 0.15
		var text_size := _fitted(text, box.size.x - 2.0 * inset, int(row * 0.45))
		draw_string(font, Vector2(box.position.x + inset, box.position.y + box.size.y * 0.5 + text_size * 0.35), text,
			HORIZONTAL_ALIGNMENT_CENTER, box.size.x - 2.0 * inset, text_size, GROUP if i == listening else VALUE)


## The largest text size up to `most` at which a text fits a width.
func _fitted(text: String, width: float, most: int) -> int:
	var at := most
	while at > 8 and font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, at).x > width:
		at -= 1
	return at


## A pad button's sign: the shoulder and Start / Select names, the direction arrows and the face
## buttons' symbols drawn (the web builds' font has no PlayStation symbols).
func _draw_glyph(bit: int, r: Rect2) -> void:
	var centre := r.get_center()
	var s := minf(r.size.x, r.size.y) * 0.32
	if SHOULDER_NAMES.has(bit):
		var name := str(SHOULDER_NAMES[bit])
		var text_size := _fitted(name, r.size.x * 0.9, int(_row * 0.42))
		draw_string(font, Vector2(r.position.x, centre.y + text_size * 0.35), name, HORIZONTAL_ALIGNMENT_CENTER, r.size.x,
			text_size, TEXT)
		return
	if bit & PadState.DIRECTIONS:
		var d := {UP: Vector2.UP, DOWN: Vector2.DOWN, LEFT: Vector2.LEFT, RIGHT: Vector2.RIGHT}[bit] as Vector2
		var side := Vector2(-d.y, d.x)
		draw_colored_polygon(PackedVector2Array([centre + d * s, centre - d * s * 0.6 + side * s,
			centre - d * s * 0.6 - side * s]), TEXT)
		return
	ButtonGlyphs.draw(self, bit, centre, s * GLYPH_RADIUS)
