class_name HudFrame
extends RefCounted
## The fight's 2D layout: the game's 384 × 480 frame-buffer units, whose 368 shown columns
## (ScreenCanvas.SCREEN) start at x = 8 (centre 192), laid into the scene's 4:3 frame
## (CameraRig.frame_rect, in the window).

const LEFT := 8.0


## The window point of frame-buffer point (x, y) in the frame `box` (window pixels).
static func point(box: Rect2, x: float, y: float) -> Vector2:
	return ScreenBox.point(box, ScreenCanvas.SCREEN, x - LEFT, y)


## Window pixels per frame-buffer unit.
static func unit_scale(box: Rect2) -> Vector2:
	return box.size / Vector2(ScreenCanvas.SCREEN)
