class_name FightCanvas
extends PsxCanvas
## A PSX canvas drawn over the fight, laid out in the fight HUD's frame (HudFrame: the 368 shown
## columns start at x = 8 of the 4:3 frame the camera rig reports).

var frame := Rect2()                 ## the fight's 4:3 frame in the window (FightHud.place)


func place(frame_rect: Rect2) -> void:
	var f := Rect2(frame_rect.position * size, frame_rect.size * size)
	if f != frame:
		frame = f
		redraw()


## The fight's frame (the clipped passes are placed in it as well).
func layout_box() -> Rect2:
	return frame if frame.has_area() else ScreenBox.rect(size)


func pt(x: float, y: float) -> Vector2:
	return HudFrame.point(box, x, y)
