class_name ScreenMask
extends Control
## Black outside what the console showed of a 2D screen: the 4:3 screen in the window, and in it
## the display rectangle the game draws to (PsxCanvas.DISPLAY: y 20–467 of the 480 lines). The
## screens draw past it (the VS background's last column, sliding pictures).


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	resized.connect(queue_redraw)


func _draw() -> void:
	var box := ScreenBox.rect(size)
	var scale := box.size.y / ScreenCanvas.SCREEN.y
	var top := box.position.y + PsxCanvas.DISPLAY.position.y * scale
	var bottom := box.position.y + PsxCanvas.DISPLAY.end.y * scale
	draw_rect(Rect2(0, 0, box.position.x, size.y), Color.BLACK)
	draw_rect(Rect2(box.end.x, 0, size.x - box.end.x, size.y), Color.BLACK)
	draw_rect(Rect2(0, 0, size.x, top), Color.BLACK)
	draw_rect(Rect2(0, bottom, size.x, size.y - bottom), Color.BLACK)
