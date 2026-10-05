class_name ButtonGlyphs
extends RefCounted
## The PlayStation face-button symbols (□ △ ✕ ○ in their colours) drawn as vector shapes for the
## touch controls and the settings' key bindings: shapes, not font glyphs, since the web builds' default font has no PlayStation
## symbols.

const COLOURS := {
	PadState.SQUARE: Color(0.93, 0.5, 0.75), PadState.TRIANGLE: Color(0.3, 0.85, 0.65),
	PadState.CROSS: Color(0.5, 0.65, 1.0), PadState.CIRCLE: Color(1.0, 0.4, 0.4),
}
const LINE_SHARE := 0.16             ## stroke width per radius


## A face button's symbol centred at `at` with radius `r`; `alpha` scales its opacity.
static func draw(item: CanvasItem, button: int, at: Vector2, r: float, alpha := 1.0) -> void:
	var colour: Color = COLOURS.get(button, Color.WHITE)
	colour.a *= alpha
	var s := r * 0.55
	var width := maxf(1.0, r * LINE_SHARE)
	match button:
		PadState.SQUARE:
			item.draw_rect(Rect2(at - Vector2(s, s), Vector2(2 * s, 2 * s)), colour, false, width)
		PadState.TRIANGLE:
			var h := s * 1.1
			item.draw_polyline(PackedVector2Array([at + Vector2(0, -h), at + Vector2(h * 0.95, h * 0.7),
				at + Vector2(-h * 0.95, h * 0.7), at + Vector2(0, -h)]), colour, width, true)
		PadState.CROSS:
			item.draw_line(at + Vector2(-s, -s), at + Vector2(s, s), colour, width, true)
			item.draw_line(at + Vector2(s, -s), at + Vector2(-s, s), colour, width, true)
		PadState.CIRCLE:
			item.draw_arc(at, s, 0.0, TAU, 32, colour, width, true)
