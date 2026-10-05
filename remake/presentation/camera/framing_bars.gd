class_name FramingBars
extends Control
## Frames the part of the window the 3D view may not extend into (CameraRig.visible_rect) with
## the stage's clear colour (remake-plan.md#aspect-ratios).

var colour := Color.BLACK
var shown := Rect2(0, 0, 1, 1)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func frame(rect: Rect2, clear: Color) -> void:
	if rect == shown and clear == colour:
		return
	shown = rect
	colour = clear
	queue_redraw()


func _draw() -> void:
	var r := Rect2(shown.position * size, shown.size * size)
	if r.position.x > 0:
		draw_rect(Rect2(0, 0, r.position.x, size.y), colour)
		draw_rect(Rect2(r.end.x, 0, size.x - r.end.x, size.y), colour)
	if r.position.y > 0:
		draw_rect(Rect2(0, 0, size.x, r.position.y), colour)
		draw_rect(Rect2(0, r.end.y, size.x, size.y - r.end.y), colour)
