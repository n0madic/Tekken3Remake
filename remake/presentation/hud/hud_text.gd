class_name HudText
extends RefCounted
## FUN_8004D15C's glyph walk with the game's fonts (HudData): one advance per character, "\n"
## starts a new line, a space only advances. `to_window` maps the layout's units (a text from
## (x, y)) to window pixels.

const NEWLINE := 0x0A
const SPACE := 0x20
const LAST_COLOUR := 31             ## the glyph sheets' colours: 0 to 31 (HudData.glyphs)


static func draw(item: CanvasItem, hud: HudData, text: String, font_index: int, colour: int, x: float, y: float,
		to_window: Transform2D, tint := Color.WHITE) -> void:
	var info: HudData.FontInfo = hud.fonts.get(font_index)
	if info == null:
		return
	var sheet := hud.glyphs(font_index, clampi(colour, 0, LAST_COLOUR))
	var glyph := to_window.basis_xform(Vector2(info.width, info.height))
	var row := 0
	var column := 0
	for i in text.length():
		var code := text.unicode_at(i)
		if code == NEWLINE:
			row += 1
			column = 0
			continue
		if code != SPACE:
			var n := code - info.first
			var source := Rect2((n % info.columns) * info.width, (n / info.columns) * info.height, info.width, info.height)
			var at := to_window * Vector2(x + column * info.advance, y + row * info.line)
			item.draw_texture_rect_region(sheet, Rect2(at, glyph), source, tint)
		column += 1


## The linear map of a layout whose point (0, 0) lies at `origin` and (1, 1) at `unit` (window).
static func layout(origin: Vector2, unit: Vector2) -> Transform2D:
	var scale := unit - origin
	return Transform2D(Vector2(scale.x, 0), Vector2(0, scale.y), origin)
