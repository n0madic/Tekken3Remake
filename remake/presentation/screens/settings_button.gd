class_name SettingsButton
extends Control
## The way into the settings on the main menu: a gear and "Select: settings" at the top left of
## the window (with the touch controls shown, in their top row right of the left macros: `place`). A
## click or tap on it, or near it, opens them, as Select does.

signal pressed

const SIZE_SHARE := 0.06               ## the gear's size as a share of the window height
const MIN_SIZE := 28.0
const MARGIN := 0.4                    ## of the gear's size
const HIT_SLACK := 0.5                 ## of the gear's size: taps this far outside the band count
const COLOUR := Color(1, 1, 1, 0.8)
const BAND := Color(0, 0, 0, 0.45)
const TEETH := 8

var font: Font
var _anchor := Rect2()                 ## where the band starts and its height (empty: the corner)


func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_PASS
	visible = false


## Drawn again when its hint changes language (a resize and `place` redraw it as well).
func _notification(what: int) -> void:
	if what == NOTIFICATION_TRANSLATION_CHANGED:
		queue_redraw()


## Puts the band at `anchor`'s position with its height; an empty rectangle puts it back in the
## window's corner.
func place(anchor: Rect2) -> void:
	if anchor != _anchor:
		_anchor = anchor
		queue_redraw()


func _gear_size() -> float:
	if _anchor.size.y > 0.0:
		return _anchor.size.y / (1.0 + MARGIN)
	return maxf(MIN_SIZE, size.y * SIZE_SHARE)


func area() -> Rect2:
	var s := _gear_size()
	var label := font.get_string_size(tr("SETTINGS_OPEN_HINT"), HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.45)).x
	var width := s * (1.0 + 3.0 * MARGIN) + label
	var at := _anchor.position if _anchor.size.y > 0.0 else Vector2(s * MARGIN, s * MARGIN)
	return Rect2(at, Vector2(width, s * (1.0 + MARGIN)))


func _has_point(point: Vector2) -> bool:
	return visible and area().grow(_gear_size() * HIT_SLACK).has_point(point)


func _gui_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	var touch := event as InputEventScreenTouch
	# A tap arrives as the touch and as a mouse click emulated from it: only the touch counts.
	var clicked := click != null and click.pressed and click.button_index == MOUSE_BUTTON_LEFT \
		and click.device != InputEvent.DEVICE_ID_EMULATION
	if clicked or (touch != null and touch.pressed):
		accept_event()
		pressed.emit()


func _draw() -> void:
	var s := _gear_size()
	var r := area()
	draw_rect(r, BAND)
	var c := Vector2(r.position.x + s * (0.5 + MARGIN), r.get_center().y)
	# The gear: a ring with teeth.
	for i in TEETH:
		var a := TAU * i / TEETH
		var dir := Vector2(cos(a), sin(a))
		var side := Vector2(-dir.y, dir.x) * s * 0.08
		var inner := c + dir * s * 0.3
		var outer := c + dir * s * 0.46
		draw_colored_polygon(PackedVector2Array([inner - side, outer - side, outer + side, inner + side]), COLOUR)
	draw_arc(c, s * 0.26, 0.0, TAU, 24, COLOUR, s * 0.14, true)
	draw_string(font, Vector2(c.x + s * (0.5 + MARGIN), c.y + s * 0.16), tr("SETTINGS_OPEN_HINT"),
		HORIZONTAL_ALIGNMENT_LEFT, -1, int(s * 0.45), COLOUR)
