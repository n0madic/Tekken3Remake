class_name ScreenBox
## The 4:3 area of the window that stands for the original 368 × 480 screen: 2D screens are
## laid out in the original coordinates and scaled into it, centred in the window.

const ASPECT := 4.0 / 3.0


static func rect(window: Vector2) -> Rect2:
	var w := minf(window.x, window.y * ASPECT)
	var h := w / ASPECT
	return Rect2((window.x - w) / 2.0, (window.y - h) / 2.0, w, h)


## A point of the 368 × 480 screen in window pixels.
static func point(box: Rect2, screen: Vector2i, x: float, y: float) -> Vector2:
	return box.position + Vector2(x / screen.x * box.size.x, y / screen.y * box.size.y)


## Window pixels per original display line.
static func line_scale(box: Rect2, screen: Vector2i) -> float:
	return box.size.y / screen.y
