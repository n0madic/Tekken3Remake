class_name TouchControls
extends Control
## The on-screen controls of touch screens (remake-plan.md#input, "Touch"): a stick on the left
## (it centres where the finger lands; eight directions past a dead zone), the four face buttons
## on the right in the pad's layout, the shoulder buttons in one row above them, L1 L2 over the
## stick and R2 R1 over the face buttons (in reach of the thumbs on tall screens too), Select and
## Start at the bottom in the middle, and the macro buttons of the settings in the top corners (two or four limbs at once,
## such as the throws 1+3 on the left and 2+4 on the right).
## Each finger works on its own; a finger on the buttons may slide from one to another. The
## result is one pad word (`bits`) that InputRouter reads as the touch device.
##
## While something plays that Start skips (a movie, the demonstration, a replay: `set_playback`)
## only Select and Start stay, in their places, so the rest does not cover the picture.
##
## The layout scales with the window's shorter side and the size setting (`scale_share`) and keeps
## inside the display's safe area.

const UNIT_SHARE := 0.085             ## the layout unit as a share of the window's shorter side
const MIN_UNIT := 28.0
const DEAD_ZONE := 0.35               ## of the unit
const STICK_RADIUS := 1.3             ## units
const BUTTON_RADIUS := 0.78
const BUTTON_SPREAD := 1.35
const HIT_SLACK := 1.25              ## a round button takes touches this far out (of its radius)
const RECT_SLACK := 0.2               ## units a rectangular button takes touches around it
const SYSTEM_SIZE := Vector2(1.9, 0.75)
const SHOULDER_SIZE := Vector2(1.5, 0.8)
const EDGE := 0.3                     ## units between the controls and the safe area's edges
const GAP := 0.3                      ## units between neighbouring rectangular buttons
const MACRO_RADIUS := 0.6
const ALPHA := 0.55
const PRESSED_ALPHA := 0.95
const OUTLINE := Color(0.62, 0.62, 0.62)   ## a button's edge at rest (white while pressed)
const FILL := 0.15                         ## a button's dark backing at rest, and pressed
const PRESSED_FILL := 0.3
const FACE := [PadState.TRIANGLE, PadState.SQUARE, PadState.CIRCLE, PadState.CROSS]
const FACE_OFFSETS := [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]
## The macro sets of the settings: two throws, or also 1+2 and 3+4.
const MACRO_SETS := {
	"none": [],
	"throws": [PadState.SQUARE | PadState.CROSS, PadState.TRIANGLE | PadState.CIRCLE],
	"all": [PadState.SQUARE | PadState.CROSS, PadState.TRIANGLE | PadState.CIRCLE,
		PadState.SQUARE | PadState.TRIANGLE, PadState.CROSS | PadState.CIRCLE],
}
const LIMB_NAMES := {PadState.SQUARE: "1", PadState.TRIANGLE: "2", PadState.CROSS: "3", PadState.CIRCLE: "4"}
## The shoulder buttons from left to right: L1 L2 over the stick, R2 R1 over the face buttons.
const SHOULDERS := [[PadState.L1, PadState.L2], [PadState.R2, PadState.R1]]
const STICK_HINT := 2.6               ## units from the safe area's bottom left corner to the stick's rest
const DIRECTIONS := [PadState.RIGHT, PadState.RIGHT | PadState.DOWN, PadState.DOWN, PadState.DOWN | PadState.LEFT,
	PadState.LEFT, PadState.LEFT | PadState.UP, PadState.UP, PadState.UP | PadState.RIGHT]

## A control on the screen: its centre, radius (circles) or rectangle, and the pad bits it holds.
class Control2:
	var bits := 0
	var centre := Vector2.ZERO
	var radius := 0.0
	var rect := Rect2()
	var label := ""

var bits := 0                         ## the pad word of the fingers down now
var macros: Array = []
var _controls: Array[Control2] = []
var _stick_zone := Rect2()
var _fingers: Dictionary = {}         ## touch index → {"stick": origin} or {"control": Control2}
var _stick_origin := Vector2.INF
var _stick_at := Vector2.ZERO
var _unit := MIN_UNIT
var scale_share := 1.0                ## the size setting: 1 is the default size
## The shoulder buttons shown (pad bits): those the game's key configuration gives an action.
var shoulders := PadState.L1 | PadState.L2 | PadState.R1 | PadState.R2
var playback := false                 ## only Select and Start shown
## The free place in the top row right of the left macros (its position and the row's height), for the
## settings gear of the main menu.
var top_left_free := Rect2()
var font: Font


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(layout)
	layout()


## Every finger is let go when the app or window loses the focus or is paused: the lifts that
## happen meanwhile are never delivered, and a stale stick finger would keep the stick for good.
func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			reset()


func set_macros(set_name: String) -> void:
	macros = MACRO_SETS.get(set_name, [])
	layout()


## Only Select and Start while something plays; every control otherwise. The fingers down are let
## go on a change (a stick or button held would otherwise stay pressed).
func set_playback(on: bool) -> void:
	if on != playback:
		playback = on
		reset()
		layout()


## The shoulder buttons to show (pad bits): those player 1's key configuration gives an action (by
## default the game leaves all four unused), all four on the KEY CONFIGURATION page itself, where
## an unused one has to be pressed to be given an action.
static func shoulders_shown(flow: GameFlow) -> int:
	if flow.state == GameFlow.State.OPTIONS and flow.options.page == OptionsScreen.PAGE_KEYS:
		return PadState.L1 | PadState.L2 | PadState.R1 | PadState.R2
	var bits := 0
	for button: int in [0, 1, 2, 3]:            # L2 R2 L1 R1: pad bits 1 << button
		if flow.progress.button_assigned(0, button):
			bits |= 1 << button
	return bits


## Shows only these shoulder buttons (pad bits); the others keep their places empty.
func set_shoulders(bits_shown: int) -> void:
	if bits_shown != shoulders:
		shoulders = bits_shown
		layout()


## The controls' size as a share of the default one.
func set_scale_share(share: float) -> void:
	scale_share = share
	layout()


## Places the controls for the window's size and safe area.
func layout() -> void:
	var area := safe_area()
	_unit = maxf(MIN_UNIT, minf(area.size.x, area.size.y) * UNIT_SHARE * scale_share)
	var u := _unit
	_controls.clear()
	var centre := area.end - Vector2(3.1, 3.1) * u
	for i in FACE.size():
		var c := Control2.new()
		c.bits = FACE[i]
		c.centre = centre + (FACE_OFFSETS[i] as Vector2) * BUTTON_SPREAD * u
		c.radius = BUTTON_RADIUS * u
		_controls.append(c)
	var r := MACRO_RADIUS * u
	var left := 0                     # the macros in the top left corner
	for i in macros.size():
		# In the top corners, alternating: the first one on the left, the next on the right.
		var c := Control2.new()
		c.bits = macros[i]
		c.radius = r
		var offset := EDGE * u + r + (i / 2) * (2.0 * r + GAP * u)
		c.centre = Vector2(area.position.x + offset if i % 2 == 0 else area.end.x - offset, area.position.y + EDGE * u + r)
		if i % 2 == 0:
			left += 1
		var names := PackedStringArray()
		for bit: int in LIMB_NAMES:
			if c.bits & bit:
				names.append(str(LIMB_NAMES[bit]))
		c.label = "+".join(names)
		_controls.append(c)
	var system := SYSTEM_SIZE * u
	var bottom := area.end.y - (EDGE * u + system.y)
	# At the bottom in the middle, clear of the HUD's bars and timer; moved left where the Cross
	# button's touch area would reach Start's (4:3 screens at the larger sizes).
	var pair := 2.0 * system.x + GAP * u
	var clear := centre.x - (BUTTON_RADIUS * HIT_SLACK + RECT_SLACK + GAP / 2.0) * u   # left of Cross's touch area
	var pair_left := minf(area.get_center().x - pair / 2.0, clear - pair)
	for i in 2:
		var x := pair_left + i * (system.x + GAP * u)
		_add_rect(PadState.SELECT if i == 0 else PadState.START, Rect2(Vector2(x, bottom), system),
			"SELECT" if i == 0 else "START")
	var shoulder := SHOULDER_SIZE * u
	# Over Triangle, their touch areas clear of its own (a rectangle's touch is taken first).
	var y := centre.y - (BUTTON_SPREAD + BUTTON_RADIUS * HIT_SLACK + RECT_SLACK + GAP / 2.0) * u - shoulder.y
	for side in 2:
		var middle := area.position.x + STICK_HINT * u if side == 0 else centre.x
		for i in 2:
			var x := middle - GAP * u / 2.0 - shoulder.x if i == 0 else middle + GAP * u / 2.0
			var bit: int = (SHOULDERS[side] as Array)[i]
			if shoulders & bit == 0:
				continue
			_add_rect(bit, Rect2(Vector2(x, y), shoulder), str(PadState.NAMES[bit]))
	top_left_free = Rect2(area.position + Vector2(EDGE * u + left * (2.0 * r + GAP * u), EDGE * u), Vector2(0, 2.0 * r))
	var top := (EDGE + GAP) * u + 2.0 * r
	_stick_zone = Rect2(area.position + Vector2(0, top), Vector2(area.size.x * 0.5, area.size.y - top))
	if playback:
		_controls = _controls.filter(func(c: Control2) -> bool: return c.bits & (PadState.SELECT | PadState.START) != 0)
		_stick_zone = Rect2()
	_rebind_fingers()
	queue_redraw()


## The fingers on controls after a layout: each holds the new control of its buttons, and lets go
## when there is none (a shoulder button no longer shown).
func _rebind_fingers() -> void:
	var changed := false
	for index: int in _fingers.keys():
		var f: Dictionary = _fingers[index]
		if not f.has("control"):
			continue
		var old := f["control"] as Control2
		var now: Control2 = null
		for c in _controls:
			if c.bits == old.bits and (c.rect.size == Vector2.ZERO) == (old.rect.size == Vector2.ZERO):
				now = c
				break
		if now == null:
			_fingers.erase(index)
		else:
			f["control"] = now
		changed = true
	if changed:
		_update()


func _add_rect(pad_bits: int, rect: Rect2, label: String) -> void:
	var c := Control2.new()
	c.bits = pad_bits
	c.rect = rect
	c.label = label
	_controls.append(c)


## The display's safe area in this control's coordinates (the whole control where unknown).
func safe_area() -> Rect2:
	var full := Rect2(Vector2.ZERO, size)
	var screen := DisplayServer.screen_get_size()
	var safe := DisplayServer.get_display_safe_area()
	if safe.size.x <= 0 or screen.x <= 0 or not OS.has_feature("mobile"):
		return full
	var scale := size / Vector2(screen)
	return Rect2(Vector2(safe.position) * scale, Vector2(safe.size) * scale).intersection(full)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	var touch := event as InputEventScreenTouch
	var drag := event as InputEventScreenDrag
	if touch != null:
		if touch.pressed:
			if press(touch.index, touch.position):
				get_viewport().set_input_as_handled()
		elif _fingers.has(touch.index):
			release(touch.index)
			get_viewport().set_input_as_handled()
	elif drag != null and _fingers.has(drag.index):
		move(drag.index, drag.position)
		get_viewport().set_input_as_handled()


## A finger down at `at`: a control, or the stick zone. True when the controls took it. The stick
## has one finger, the first one down: another in its zone (a resting palm) is taken but does nothing.
func press(index: int, at: Vector2) -> bool:
	if _fingers.has(index):
		release(index)    # a lost lift: the finger starts anew
	var c := control_at(at)
	if c != null:
		_fingers[index] = {"control": c}
	elif _stick_zone.has_point(at):
		if _stick_origin != Vector2.INF:
			return true
		_fingers[index] = {"stick": at}
		_stick_origin = at
		_stick_at = at
	else:
		return false
	_update()
	return true


func move(index: int, at: Vector2) -> void:
	var f: Dictionary = _fingers[index]
	if f.has("stick"):
		_stick_at = at
	elif (f["control"] as Control2).rect.size == Vector2.ZERO:
		# A finger on the face buttons slides between them.
		var c := control_at(at)
		if c != null and c.rect.size == Vector2.ZERO:
			f["control"] = c
	_update()


func release(index: int) -> void:
	var f: Dictionary = _fingers[index]
	_fingers.erase(index)
	if f.has("stick"):
		_stick_origin = Vector2.INF
	_update()


func control_at(at: Vector2) -> Control2:
	var best: Control2 = null
	var best_d := INF
	for c in _controls:
		if c.rect.size != Vector2.ZERO:
			if c.rect.grow(RECT_SLACK * _unit).has_point(at):
				return c
			continue
		var d := at.distance_to(c.centre)
		if d < c.radius * HIT_SLACK and d < best_d:
			best = c
			best_d = d
	return best


## The stick's direction bits for an offset from its origin.
func stick_bits(offset: Vector2) -> int:
	if offset.length() < DEAD_ZONE * _unit:
		return 0
	var sector := posmod(roundi(offset.angle() / (TAU / 8.0)), 8)
	return DIRECTIONS[sector]


func _update() -> void:
	var b := 0
	for index: int in _fingers:
		var f: Dictionary = _fingers[index]
		if f.has("stick"):
			b |= stick_bits(_stick_at - _stick_origin)
		else:
			b |= (f["control"] as Control2).bits
	bits = b
	# The touch controls are player 1's device from their first press (InputRouter).
	if b != 0 and Pads.devices[0] != InputRouter.TOUCH:
		Pads.assign_touch()
	Pads.touch_latch |= b & ~Pads.touch_bits
	Pads.touch_bits = b
	queue_redraw()


## Every finger lifted (the controls hidden, the window left).
func reset() -> void:
	_fingers.clear()
	_stick_origin = Vector2.INF
	bits = 0
	Pads.touch_bits = 0
	Pads.touch_latch = 0
	queue_redraw()


func _draw() -> void:
	var u := _unit
	if _stick_origin != Vector2.INF:
		draw_circle(_stick_origin, STICK_RADIUS * u, Color(1, 1, 1, 0.12))
		draw_arc(_stick_origin, STICK_RADIUS * u, 0, TAU, 40, Color(OUTLINE, ALPHA), 2.0, true)
		var knob := _stick_origin + (_stick_at - _stick_origin).limit_length(STICK_RADIUS * u)
		draw_circle(knob, 0.55 * u, Color(1, 1, 1, PRESSED_ALPHA * 0.6))
	elif _stick_zone.has_area():
		var hint := Vector2(_stick_zone.position.x + STICK_HINT * u, _stick_zone.end.y - STICK_HINT * u)
		draw_arc(hint, STICK_RADIUS * u, 0, TAU, 40, Color(OUTLINE, 0.25), 2.0, true)
	for c in _controls:
		var down := bits & c.bits == c.bits
		var alpha := PRESSED_ALPHA if down else ALPHA
		var edge := Color(Color.WHITE if down else OUTLINE, alpha)
		var backing := Color(0, 0, 0, (PRESSED_FILL if down else FILL) * alpha)
		if c.rect.size != Vector2.ZERO:
			draw_rect(c.rect, backing)
			draw_rect(c.rect, edge, false, 2.0)
			_label(c.label, c.rect.get_center(), c.rect.size.y * 0.42, alpha)
			continue
		draw_circle(c.centre, c.radius, backing)
		draw_arc(c.centre, c.radius, 0, TAU, 40, edge, 2.0, true)
		if c.label.is_empty():
			ButtonGlyphs.draw(self, c.bits, c.centre, c.radius * 0.8, alpha)
		else:
			_label(c.label, c.centre, c.radius * 0.8, alpha)


func _label(text: String, at: Vector2, height: float, alpha: float) -> void:
	var s := int(height)
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, s).x
	draw_string(font, at + Vector2(-w / 2.0, s * 0.36), text, HORIZONTAL_ALIGNMENT_LEFT, -1, s, Color(1, 1, 1, alpha))
