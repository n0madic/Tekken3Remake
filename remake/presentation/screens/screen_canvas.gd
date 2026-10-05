class_name ScreenCanvas
extends Control
## The base of the game's 2D screens: the original 368 × 480 screen scaled into the window's 4:3
## area, the game's bitmap fonts in their 16 colours (FUN_8004D15C, the HUD's glyph sheets) and
## flat, Gouraud and textured shapes in the original coordinates.
##
## The game's semi-transparent primitives blend with what is under them (PSX modes: B+F, B−F);
## a view draws them in passes (`add_pass`): child items in their own blend mode, drawn after the
## canvas and the passes before them, in the order the game's ordering table draws them.

const SCREEN := Vector2i(368, 480)
const NO_FADE := 0x100
const MAX_POLYGON := Vector2i(1023, 511)   ## the GPU's largest polygon extent (x, y)
const PERCENT := 0x25                ## print_fmt's characters: "%" (and HudText.NEWLINE), the width digits "0" … "8"
const DIGIT_0 := 0x30
const DIGIT_8 := 0x38
const BCD_LIMIT := 100_000_000       ## FUN_8004CE74: numbers from here on print as 99999999
const TEXEL_MASK_SUB := preload("res://presentation/screens/texel_mask_sub.gdshader")

var hud: HudData
var box := Rect2()
var target: CanvasItem = self        ## the item the helpers draw into (a pass while it draws)
## The screen fade the view draws this frame (FUN_8004E2E8's level; 0x100 none): the game adds it
## to the frame's fades.
var fade_level := NO_FADE
var _passes: Array[Control] = []


func setup_canvas(hud_data: HudData) -> void:
	hud = hud_data
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


## Call first in `_draw`: the 4:3 area of this frame.
func begin() -> void:
	box = layout_box()


## Where the 368 × 480 screen lies in the window: the centred 4:3 box.
func layout_box() -> Rect2:
	return ScreenBox.rect(size)


## A drawing pass in a blend mode (CanvasItemMaterial.BLEND_MODE_*): `painter` draws it with the
## helpers, after the canvas's own `_draw` and the passes added before it. `clip` (screen
## coordinates) limits it to a draw area.
func add_pass(blend: int, painter: Callable, clip := Rect2()) -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = blend as CanvasItemMaterial.BlendMode
	_add_pass_item(m, painter, clip)


## A subtractive pass in which each opaque texel subtracts the vertex colour (a texture drawn
## through a CLUT of white entries).
func add_texel_mask_pass(painter: Callable) -> void:
	var m := ShaderMaterial.new()
	m.shader = TEXEL_MASK_SUB
	_add_pass_item(m, painter, Rect2())


func _add_pass_item(m: Material, painter: Callable, clip: Rect2) -> void:
	var item := Control.new()
	item.mouse_filter = Control.MOUSE_FILTER_IGNORE
	item.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if clip.has_area():
		item.clip_contents = true
		item.set_meta(&"clip", clip)
	else:
		item.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	item.material = m
	item.draw.connect(func() -> void:
		begin()
		target = item
		item.draw_set_transform(-item.position)
		painter.call()
		target = self)
	add_child(item)
	_passes.append(item)


## Redraws the canvas and its passes.
func redraw() -> void:
	queue_redraw()
	box = layout_box()
	for item in _passes:
		if item.has_meta(&"clip"):
			var clip: Rect2 = item.get_meta(&"clip")
			var area := r(clip.position.x, clip.position.y, clip.size.x, clip.size.y)
			item.position = area.position
			item.size = area.size
		item.queue_redraw()


func pt(x: float, y: float) -> Vector2:
	return ScreenBox.point(box, SCREEN, x, y)


func r(x: float, y: float, w: float, h: float) -> Rect2:
	var a := pt(x, y)
	return Rect2(a, pt(x + w, y + h) - a)


func black() -> void:
	target.draw_rect(Rect2(Vector2.ZERO, size), Color.BLACK)


func fill(x: float, y: float, w: float, h: float, c: Color) -> void:
	target.draw_rect(r(x, y, w, h), c)


## LINE_F2: a one-pixel line, clipped to `clip` (a draw area) when given.
func line(x0: float, y0: float, x1: float, y1: float, c: Color, clip := Rect2()) -> void:
	var a := Vector2(x0, y0)
	var b := Vector2(x1, y1)
	if clip.has_area():
		# Liang–Barsky against the draw area (right and bottom edges exclusive, as the GPU's).
		var d := b - a
		var t0 := 0.0
		var t1 := 1.0
		var edges := [[-d.x, a.x - clip.position.x], [d.x, clip.end.x - 1 - a.x],
			[-d.y, a.y - clip.position.y], [d.y, clip.end.y - 1 - a.y]]
		for e: Array in edges:
			var pe: float = e[0]
			var qe: float = e[1]
			if is_zero_approx(pe):
				if qe < 0:
					return
				continue
			var t := qe / pe
			if pe < 0:
				t0 = maxf(t0, t)
			else:
				t1 = minf(t1, t)
		if t0 > t1:
			return
		b = a + d * t1
		a = a + d * t0
	# A pixel-wide rectangle along the line (the lines here are horizontal or vertical).
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y))
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y))
	target.draw_rect(r(lo.x, lo.y, hi.x - lo.x + 1, hi.y - lo.y + 1), c)


## A quad with a colour per corner: top-left, top-right, bottom-left, bottom-right.
func gradient(x: float, y: float, w: float, h: float, tl: Color, tr: Color, bl: Color, br: Color) -> void:
	if w == 0 or h == 0:
		return
	var points := PackedVector2Array([pt(x, y), pt(x + w, y), pt(x + w, y + h), pt(x, y + h)])
	target.draw_polygon(points, PackedColorArray([tl, tr, br, bl]))


## POLY_GT4 over an axis-aligned rectangle: a texture modulated by a colour per corner
## (top-left, top-right, bottom-left, bottom-right; 0x80 grey leaves it as it is).
func textured(tex: Texture2D, x: float, y: float, w: float, h: float, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	if tex == null or w == 0 or h == 0:
		return
	var points := PackedVector2Array([pt(x, y), pt(x + w, y), pt(x + w, y + h), pt(x, y + h)])
	var uvs := PackedVector2Array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
	target.draw_polygon(points, PackedColorArray([modulation(c0), modulation(c1), modulation(c3), modulation(c2)]), uvs, tex)


## A PSX texture colour as a modulation (0x80 is 1.0).
static func modulation(c: Color) -> Color:
	return Color(c.r * 2.0, c.g * 2.0, c.b * 2.0, 1.0)


## POLY_G4 with its corners anywhere (top-left, top-right, bottom-left, bottom-right), drawn as
## the GPU does: the triangles (0, 1, 2) and (1, 2, 3), so a thin or crossed quad still draws.
func quad(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, c0: Color, c1: Color, c2: Color, c3: Color) -> void:
	target.draw_primitive(PackedVector2Array([pt(p0.x, p0.y), pt(p1.x, p1.y), pt(p2.x, p2.y)]),
		PackedColorArray([c0, c1, c2]), PackedVector2Array())
	target.draw_primitive(PackedVector2Array([pt(p1.x, p1.y), pt(p2.x, p2.y), pt(p3.x, p3.y)]),
		PackedColorArray([c1, c2, c3]), PackedVector2Array())


func image(tex: Texture2D, x: float, y: float, w: float = -1.0, h: float = -1.0, modulate_colour := Color.WHITE,
		flip := false) -> void:
	if tex == null:
		return
	var sz := tex.get_size()
	var rect := r(x, y, sz.x if w < 0 else w, sz.y if h < 0 else h)
	if flip:
		# A negative size flips the texture in place.
		rect.size.x = -rect.size.x
	target.draw_texture_rect(tex, rect, false, modulate_colour)


## The pixel width of a text in a font (one advance per character).
func text_width(text: String, font_index: int) -> int:
	var info: HudData.FontInfo = hud.fonts.get(font_index)
	return 0 if info == null else text.length() * info.advance


## FUN_8004D15C: a text in the game's font and colour from (x, y); "\n" starts a new line.
func text(s: String, font_index: int, colour: int, x: float, y: float, alpha := 1.0) -> void:
	HudText.draw(target, hud, s, font_index, colour, x, y, HudText.layout(pt(0, 0), pt(1, 1)), Color(1, 1, 1, alpha))


## FUN_8004D15C with colour changes: `runs` alternates text and colour, starting with a text in
## `colour` ("PUSH %cSTART%c+…" with its arguments).
func text_runs(runs: Array, font_index: int, colour: int, x: float, y: float) -> void:
	var info: HudData.FontInfo = hud.fonts.get(font_index)
	if info == null:
		return
	var c := colour
	for i in runs.size():
		if i % 2 == 1:
			c = runs[i]
			continue
		var s: String = runs[i]
		text(s, font_index, c, x, y)
		x += s.length() * info.advance


## FUN_8004D15C with its format: %c colour, %f font, %H / %V the pen's x / y, %h / %v the same
## in character cells, %s, %C a character, %d (decimal) and %x with an optional width (%2d keeps
## the two low digits; %02d pads with zeros), %p (an argument, not drawn), %%. Each call starts in
## font 0 and `colour`.
func print_fmt(fmt: String, args: Array, font_index := 0, colour := 0) -> void:
	var x := 0.0
	var y := 0.0
	var mx := 0.0                    ## the line start (%H / %h)
	var run := ""                    ## the text not drawn yet, at (x, y)
	var font := font_index
	var n := fmt.length()
	var a := 0
	var i := 0
	while i < n:
		var ch := fmt.unicode_at(i)
		if ch != PERCENT and ch != HudText.NEWLINE:
			# The plain characters up to the next code or line break.
			var j := i + 1
			while j < n and fmt.unicode_at(j) != PERCENT and fmt.unicode_at(j) != HudText.NEWLINE:
				j += 1
			run += fmt.substr(i, j - i)
			i = j
			continue
		i += 1
		if ch == HudText.NEWLINE:
			x = _flush_run(run, font, colour, x, y)
			run = ""
			var info: HudData.FontInfo = hud.fonts.get(font)
			y += info.line if info != null else 0
			x = mx
			continue
		var zero := false
		var width := 0
		while i < n and fmt.unicode_at(i) >= DIGIT_0 and fmt.unicode_at(i) <= DIGIT_8:
			if fmt.unicode_at(i) == DIGIT_0:
				zero = true
			else:
				width = fmt.unicode_at(i) - DIGIT_0
			i += 1
		var code := fmt[i] if i < n else ""
		i += 1
		if code == "%":
			run += "%"
			continue
		var value: Variant = args[a] if a < args.size() else 0
		a += 1
		var number := 0
		if value is int:
			number = value
		match code:
			"c", "f", "H", "V", "h", "v":
				x = _flush_run(run, font, colour, x, y)
				run = ""
				var info: HudData.FontInfo = hud.fonts.get(font)
				match code:
					"c": colour = number
					"f": font = number
					"H":
						x = float(Fx.s16(number & 0xFFFF))
						mx = x
					"V": y = float(Fx.s16(number & 0xFFFF))
					"h":
						x = float(number * (info.advance if info != null else 0))
						mx = x
					"v": y = float(number * (info.line if info != null else 0))
			"s":
				run += str(value)
			"C":
				run += String.chr(number & 0xFF)
			"d", "D", "x":
				run += _number_text(number, code, width, zero)
	_flush_run(run, font, colour, x, y)


## %d / %D / %x as FUN_8004D15C prints them: BCD digits (≥ 10⁸ shows 99999999; the game prints
## exactly 10⁸ as A0000000, game-bugs #66, not reproduced), %d signed, %D and %x unsigned (a
## negative %D is past 10⁸), a width keeps the low digits, leading spaces or zeros fill it, a minus
## sign takes one place of it.
static func _number_text(value: int, code: String, width: int, zero: bool) -> String:
	var neg := code == "d" and value < 0
	var v := absi(value) if code == "d" else value & 0xFFFFFFFF
	var digits_text := ("%x" % v).to_upper() if code == "x" else ("99999999" if v >= BCD_LIMIT else str(v))
	var digits := digits_text.length()
	if width == 0:
		width = digits
	else:
		if neg:
			width -= 1
		if width < digits or zero:
			digits = width
	var shown := digits_text.right(digits).lpad(digits, "0")
	return " ".repeat(maxi(width - digits, 0)) + ("-" if neg else "") + shown


## Draws `run` at (x, y); the pen's x after it.
func _flush_run(run: String, font: int, colour: int, x: float, y: float) -> float:
	if run.is_empty():
		return x
	text(run, font, colour, x, y)
	var info: HudData.FontInfo = hud.fonts.get(font)
	return x + run.length() * (info.advance if info != null else 0)


func centred(s: String, font_index: int, colour: int, centre_x: float, y: float, alpha := 1.0) -> void:
	text(s, font_index, colour, centre_x - text_width(s, font_index) / 2.0, y, alpha)


## A GPU colour word (0xBBGGRR).
static func psx(c: int) -> Color:
	return Color8(c & 0xFF, (c >> 8) & 0xFF, (c >> 16) & 0xFF)


## The game's triangle wave of the frame counter (draw_sim.triangle_wave): 0 … 0xFF … 0.
static func triangle(v: int) -> int:
	v &= 0x1FF
	return 0x1FF - v if v >= 0x100 else v


## A packet coordinate as the GPU reads it: 11 bits, signed.
static func gpu_coordinate(v: int) -> int:
	return ((v & 0x7FF) ^ 0x400) - 0x400


## Whether the GPU draws a polygon with these packet vertices: it skips one wider than
## MAX_POLYGON.x or taller than MAX_POLYGON.y.
static func gpu_draws(vertices: Array[Vector2i]) -> bool:
	var lo := vertices[0]
	var hi := vertices[0]
	for v in vertices:
		lo = lo.min(v)
		hi = hi.max(v)
	return hi.x - lo.x <= MAX_POLYGON.x and hi.y - lo.y <= MAX_POLYGON.y
