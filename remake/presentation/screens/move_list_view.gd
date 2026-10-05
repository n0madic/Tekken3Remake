class_name MoveListView
extends FightCanvas
## The in-fight move lists (FUN_800789E4 with the text engine MoveTextDraw 0x80077A0C; the
## verified port tools/research/command_list_sim.py) while the MOVE_LIST event says they are shown
## (MoveListScreen: the pause menu's COMMAND page, practice's COMMAND LIST).
##
## Each side's list is a 182-pixel column (player 2's from x 184): a dark column with two light
## lines and the title (glyphs 6–10 of the side's atlas), six moves 64 pixels apart in boxes
## clipped between the lines, and PUSH BUTTON TO EXIT under the column of the side that leaves.
## Meanwhile the game gives the scene's ordering table an empty draw area (the pause page keeps
## its top 32 lines): the paused scene is not redrawn and stays in the frame buffers as it was
## drawn during the page's delay frames, so the lists lie over the frozen fight.
##
## The move strings (formats/arc-archives.md, "Move-text rendering (Japan Rev.1)") are glyphs of
## the character's own atlas (four 12 × 11 glyph sets in the bit planes of one picture, see
## `move_glyphs.png`), direction arrows and button diagrams (title.ovl's picture at tpage 6).
## With English game texts a side whose USA list was converted is drawn as the USA release
## draws it ("Move-text rendering (USA)": MoveTextDraw 0x80077724 of SLUS_004.02): ASCII in a
## 6 × 12 font and pre-rendered words from one shared atlas (`usa/move_glyphs.png`), its own
## codes for arrows, buttons, spaces and line breaks, and names measured in cells.

const LISTS_TOP := 0x74              ## the rows' draw area: y 116 … 435
const LISTS_HEIGHT := 0x13F
const COLUMN := 0xB8
const ROWS := 6
const ROW_STEP := 64
const NAME_WIDTH := 0x1C             ## half-cells of a name's first line
const TEXT_COLOUR := 0x707070
const EXIT_Y := 0x1B8
const STR_EXIT := 0x80027E70         ## "%p%f%H%V%cPUSH %cBUTTON %cTO %cEXIT"
const STR_TITLE := 0x80098DF0        ## "\xFFp" and glyphs 6–10
const FONTS := 0x80027D1C            ## 4 × (s16 advance x, advance y, u16 w, h, tpage)
const ARROWS := 0x80027D44           ## 9 × (u16 uv, u16 flip flags: 1 horizontal, 2 vertical)
const ICON_TPAGE := 6
const ARROW_HELD_CLUT := 0x7FB3
const ARROW_CLUT := 0x7FB4
const BUTTON_BACK_CLUT := 0x7FB1
const ATLAS_V := 0x10                ## the atlas's first texel row in its texture page
const ATLAS_ROWS := 66               ## a plane's rows in move_glyphs.png
const ESCAPE := 0xFF
const USA_TITLE_X := 0x27            ## the USA title's pen x in the column
const USA_ARROWS := 0x80             ## USA codes: arrows 0x80–0x90 (0x90 neutral), buttons 0x91–0xA0
const USA_BUTTONS := 0x91
const USA_LINE_BREAK := 0xFC
const USA_WIDE_SPACE := 0xFB
const BOX_EDGE := 0x602010
const BOX_FILL := 0xB89246
const BOX_FRAME := 0xD0D0D0
const LINE := 0xE0E0E0
## Hwoarang's move groups: (first move, last move or −1, edge, fill).
const HWOARANG_GROUPS := [[6, 13, 0x204000, 0x5FA255], [14, -1, 0x103040, 0x2090A0]]

var root := ""
var flow: GameFlow
var shown := false
var mask := 0
var exit_side := 0
var _atlases: Dictionary = {}        ## costume slot → Texture2D
var _usa: Dictionary = {}            ## usa/move_text.json: fonts, word widths, title
var _usa_atlas: Texture2D
var _english := false                ## the list being drawn is in the USA encoding
## The text engine's pen (0x1F800380 while a string draws, kept at 0x800A39B0 between strings).
var _x := 0
var _y := 0
var _margin_x := 0
var _line_y := 0
var _colour := Color.WHITE
var _font := 0


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, assets_root: String) -> void:
	setup_psx(hud_data, game_ram, image)
	root = assets_root
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _rows_pass, Rect2(0, LISTS_TOP, SCREEN.x, LISTS_HEIGHT))


func show_state(game: GameFlow) -> void:
	flow = game
	var e := game.sim.events.first(SimEvents.Kind.MOVE_LIST)
	shown = e != null
	if shown:
		mask = e.a
		exit_side = e.b
	visible = shown
	redraw()


func _draw() -> void:
	begin()
	if not shown:
		return
	for p in 2:
		if mask >> p & 1:
			_column(p)
	ptext(STR_EXIT, [0, 0, exit_side * COLUMN | 6, EXIT_Y, 6, 5, 6, 5])


func _rows_pass() -> void:
	if not shown:
		return
	for p in 2:
		if mask >> p & 1:
			_rows(p)


## The column, its lines and its title (the lists' ordering-table entry 0, under the rows).
func _column(p: int) -> void:
	var x0 := COLUMN * p
	fill(x0 | 1, 0x5C, 0xB6, 0x170, psx(BOX_EDGE))
	fill(x0 | 2, 0x1B3, 0xB4, 2, psx(LINE))
	fill(x0 | 2, 0x72, 0xB4, 2, psx(LINE))
	_style(p)
	if _english:
		_draw_string(_usa_title(), 0, [x0 + USA_TITLE_X, 0x61, 0])
		return
	_position(x0 + 0x3C, 0x61)
	_draw_string(ram.bytes(STR_TITLE, 16), 0, [0])


## The six moves from the scrolled position: the name (on two lines when wider than 28
## half-cells), the command, the box; each row drawn before the one above it.
func _rows(p: int) -> void:
	var f := flow.fight.fighters[p]
	var list := f.move_text
	var count := MoveListScreen.count(f)
	if count == 0:
		return
	var x0 := COLUMN * p
	var off := flow.fight.command_offset[p]
	var shift := Fx.div_trunc(off, ROW_STEP) + (1 if off > 0 else 0)
	var y := off + 0x76 - ROW_STEP * shift
	var idx := flow.fight.command_cursor[p] - shift
	idx = posmod(idx, count)
	var s := _skip_strings(list, 1, 2 * idx)
	var rows := ROWS
	if f.char_id == Character.MOKUJIN:
		y = 0xF6
		rows = 1
	var laid: Array[Array] = []
	for r in rows:
		laid.append([y, idx, s])
		s = _skip_strings(list, s, 2)
		idx += 1
		if idx >= count:
			s = 1
			idx = 0
		y += ROW_STEP
	laid.reverse()
	for row: Array in laid:
		_row(p, f.char_id, list, row[0] as int, row[1] as int, row[2] as int)


func _row(p: int, character: int, list: PackedByteArray, y: int, idx: int, s: int) -> void:
	var x0 := COLUMN * p
	var edge := BOX_EDGE
	var fill_colour := BOX_FILL
	var boxed := true
	if character == Character.HWOARANG:
		for group: Array in HWOARANG_GROUPS:
			var first: int = group[0]
			var last: int = group[1]
			if idx >= first and (last < 0 or idx <= last):
				edge = group[2]
				fill_colour = group[3]
				if idx == first:
					fill_colour = BOX_EDGE
					boxed = false
	if boxed:
		fill(x0 | 2, y - 3, 0xB4, 0x42, psx(BOX_FRAME))
		fill(x0 | 3, y - 2, 0xB2, 0x3F, psx(edge))
		gradient(x0 | 3, y - 2, 0xB2, 0x1A, psx(edge), psx(edge), psx(fill_colour), psx(fill_colour))
	else:
		fill(x0 | 2, y - 2, 0xB4, 0x3F, psx(edge))
		fill(x0 | 3, y - 2, 0xB2, 0x1A, psx(fill_colour))
	_style(p)
	# The command, then the name over it (the game links the name first).
	var command_at := _skip_strings(list, s, 1)
	_position(x0 + 6, y + 0x27)
	_draw_string(list, command_at, [])
	if _name_width(list, s) >= NAME_WIDTH + 1:
		var cut := _name_end(list, s, NAME_WIDTH)
		_position(x0 + 6, y)
		_draw_string(list.slice(s, cut.x), 0, [])
		_position(x0 + 6, y + 0xC)
		_draw_string(list, cut.y, [])
	else:
		_position(x0 + 6, y + 6)
		_draw_string(list, s, [])


func _style(p: int) -> void:
	_colour = modulation(psx(TEXT_COLOUR))
	_font = p
	var f := flow.fight.fighters[p]
	_english = flow.content.move_text_english(f.costume_slot) and _load_usa()


func _position(x: int, y: int) -> void:
	_x = x
	_margin_x = x
	_y = y
	_line_y = y


func _advance_x() -> int:
	return _usa_font(0) if _english else ram.s16(FONTS + 10 * _font)


func _advance_y() -> int:
	return _usa_font(1) if _english else ram.s16(FONTS + 10 * _font + 2)


## Field k (advance x, advance y, glyph w, h, texture page) of the USA font in use.
func _usa_font(k: int) -> int:
	var fonts: Array = _usa["fonts"]
	return JsonFile.number((fonts[clampi(_font, 0, fonts.size() - 1)] as Array)[k])


## The converted USA list data, loaded on first use; false when missing.
func _load_usa() -> bool:
	if not _usa.is_empty():
		return true
	var locale := ram.locale
	var path := locale.usa_file("move_text.json") if locale != null else ""
	var atlas := locale.usa_file("move_glyphs.png") if locale != null else ""
	if path.is_empty() or atlas.is_empty():
		return false
	_usa = JsonFile.read(path)
	_usa_atlas = load(atlas) as Texture2D
	return true


func _usa_title() -> PackedByteArray:
	var out := PackedByteArray()
	for b: int in JsonFile.ints(_usa["title"]):
		out.append(b)
	return out


func _name_width(list: PackedByteArray, at: int) -> int:
	return _usa_width(list, at) if _english else _text_width(list, at)


## Where a name's first line ends and its second line starts (Vector2i).
func _name_end(list: PackedByteArray, at: int, width: int) -> Vector2i:
	if _english:
		return _usa_end(list, at, width)
	var end := _width_end(list, at, width)
	return Vector2i(end, end)


## USA FUN_80079208: a string's width in cells (a line break counts 100, 0xFB ten, the words
## their widths, bytes from 0xA1 two, the rest one).
func _usa_width(list: PackedByteArray, at: int) -> int:
	var n := 0
	while at < list.size() and list[at] != 0:
		n += _usa_weight(list[at], true)
		at += 1
	return n


func _usa_weight(c: int, line_break_counts: bool) -> int:
	if c == USA_LINE_BREAK:
		return 100 if line_break_counts else 0
	if c == USA_WIDE_SPACE:
		return 10
	if c >= 0xA1:
		return 2
	if c < 0x20:
		return (_usa["word_widths"] as Array)[c]
	return 1


## USA FUN_80079170: the first line is copied until `width` cells are used or a line break; the
## second line starts after the break (skipped) or where the copy stopped.
func _usa_end(list: PackedByteArray, at: int, width: int) -> Vector2i:
	while width > 0 and at < list.size():
		var c := list[at]
		if c == USA_LINE_BREAK:
			return Vector2i(at, at + 1)
		width -= _usa_weight(c, false)
		at += 1
	return Vector2i(at, at)


## FUN_800795E4: past `n` zero-terminated strings.
static func _skip_strings(list: PackedByteArray, at: int, n: int) -> int:
	while n > 0 and at < list.size():
		while at < list.size() and list[at] != 0:
			at += 1
		at += 1
		n -= 1
	return at


static func _weight(c: int) -> int:
	return 1 if c == 0xFE or (c >= 1 and c <= 5) else 2


## FUN_80079664: a string's width in half-cells (joiners and half spaces 1, the rest 2).
static func _text_width(list: PackedByteArray, at: int) -> int:
	var n := 0
	while at < list.size() and list[at] != 0:
		n += _weight(list[at])
		at += 1
	return n


## FUN_80079610: where copying `width` half-cells of the string stops.
static func _width_end(list: PackedByteArray, at: int, width: int) -> int:
	while width > 0 and at < list.size():
		width -= _weight(list[at])
		at += 1
	return at


## MoveTextDraw (0x80077A0C) of the string at `at`: glyphs of the font's atlas, arrows and
## button diagrams; 0xFF escapes n (new line), s (a nested string of glyphs), H / V (pen x / y),
## h / v (in advances), i (colour), p (ordering-table entry: the drawing order here) and t (font).
func _draw_string(bytes: PackedByteArray, at: int, args: Array) -> void:
	var escape := false
	if _english:
		_draw_usa(bytes, at, args)
		return
	while at < bytes.size():
		var c := bytes[at]
		at += 1
		if c == 0:
			break
		if c == ESCAPE and not escape:
			escape = true
			continue
		if escape and c != ESCAPE:
			escape = false
			_escape(c, args, false)
			continue
		escape = false
		if c >= 0xD1 and c <= 0xE0:
			_button(c - 0xD1)
		elif c >= 0xBD and c <= 0xCC:
			_arrow(c - 0xBD)
		elif c == 6:
			_arrow(0x10)
		elif c == 0xFD:
			_x += _advance_x()
		elif c == 0xFE:
			_x += Fx.div_trunc(_advance_x(), 2)
		elif c == 1:
			_x -= Fx.div_trunc(_advance_x(), 2)
			_glyph(0)
		elif c == 2:
			_glyph(1)
			_x -= Fx.div_trunc(_advance_x(), 2)
		elif c == 3:
			_x -= Fx.div_trunc(_advance_x(), 4)
			_glyph(2)
			_x -= Fx.div_trunc(_advance_x(), 4)
		elif c == 4 or c == 5:
			_x += 2 - Fx.div_trunc(_advance_x(), 4)
			_glyph(c - 1)
			_x -= 2 + Fx.div_trunc(_advance_x(), 4)
		else:
			_glyph(c - 1)


## An escape (after 0xFF): n (new line), s (a nested string: glyph byte − 1, in the USA engine
## ASCII), H / V (pen x / y), h / v (in advances), i (colour), p (ordering-table entry: the drawing
## order here) and t (font).
func _escape(c: int, args: Array, usa: bool) -> void:
	match char(c):
		"n":
			_line_y += _advance_y()
			_x = _margin_x
			_y = _line_y
		"s":
			var nested: PackedByteArray = args.pop_front()
			for b: int in nested:
				if b == 0:
					break
				if usa:
					_usa_letter(b)
				else:
					_glyph(b - 1)
		"H", "h":
			var v: int = args.pop_front()
			if c == 0x68:
				v *= _advance_x()
			_x = v
			_margin_x = v
		"V", "v":
			var v: int = args.pop_front()
			if c == 0x76:
				v *= _advance_y()
			_y = v
			_line_y = v
		"i":
			_colour = modulation(psx(args.pop_front() as int))
		"p":
			args.pop_front()
		"t":
			_font = args.pop_front() as int
		_:
			Log.warning("move text: unknown escape 0x%X" % c)


## USA MoveTextDraw (0x80077724 of SLUS_004.02): as the Japanese engine with the same escapes,
## but ASCII from 0x21, pre-rendered words (0x01–0x1F, 0xA1–0xC3), arrows 0x80–0x90, button
## diagrams 0x91–0xA0, spaces 0x20 / 0xFE (one cell), 0xFD (two), 0xFB (ten) and 0xFC a line break.
func _draw_usa(bytes: PackedByteArray, at: int, args: Array) -> void:
	var escape := false
	while at < bytes.size():
		var c := bytes[at]
		at += 1
		if c == 0:
			break
		if c == ESCAPE and not escape:
			escape = true
			continue
		if escape and c != ESCAPE:
			escape = false
			_escape(c, args, true)
			continue
		escape = false
		var adv := _advance_x()
		if c >= USA_BUTTONS and c < USA_BUTTONS + 16:
			_button(c - USA_BUTTONS)
		elif c >= USA_ARROWS and c <= USA_ARROWS + 0x10:
			_arrow(c - USA_ARROWS)
		elif c == USA_LINE_BREAK:
			_escape(0x6E, args, true)
		elif c == 0x20 or c == 0xFE:
			_x += adv
		elif c == 0xFD:
			_x += 2 * adv
		elif c == USA_WIDE_SPACE:
			_x += 10 * adv
		elif c < 0x20:
			var w := adv * JsonFile.number((_usa["word_widths"] as Array)[c])
			_usa_cell(0, ((c + 5) >> 2) * 12, (c + 1) & 3, w, w)
		elif c >= 0xA1:
			var w := adv * JsonFile.number((_usa["word_widths_high"] as Array)[c])
			if c <= 0xA3:
				_usa_cell(0, ((c - 0x7C) >> 2) * 12, (c - 0x80) & 3, w, w)
			else:
				_usa_cell(0x3C, ((c - 0x9C) >> 2) * 12, (c - 0xA4) & 3, w, w)
		else:
			_usa_letter(c)


## An ASCII letter of the USA atlas: u = 6 · (c & 15), v = 12 · (c >> 6), bit plane (c >> 4) & 3.
func _usa_letter(c: int) -> void:
	var g := c - 0x20
	_usa_cell((g & 15) * 6, (g >> 6) * 12, (g & 0x30) >> 4, _usa_font(2), _advance_x())


## `width` texels of the USA atlas from (u, v) in bit plane `plane` at the pen, which moves on by
## `advance`.
func _usa_cell(u: int, v: int, plane: int, width: int, advance: int) -> void:
	var h := _usa_font(3)
	if _usa_atlas != null and width > 0:
		var rows := JsonFile.number(_usa["atlas_rows"])
		target.draw_texture_rect_region(_usa_atlas, r(_x, _y, width, h), Rect2(u, plane * rows + v, width, h), _colour)
	_x += advance


## Glyph `g` of the font's atlas (12 × 11 cells, ten a row, the bit plane (g / 10) & 3); the
## pen moves on by the advance.
func _glyph(g: int) -> void:
	var atlas := _atlas(_font)
	if atlas != null:
		var u := g % 10 * 12
		var v := (g / 40 * 11 + ATLAS_V) & 0xFF
		var plane := g / 10 & 3
		var w := ram.u16(FONTS + 10 * _font + 4)
		var h := ram.u16(FONTS + 10 * _font + 6)
		target.draw_texture_rect_region(atlas, r(_x, _y, w, h),
			Rect2(u, plane * ATLAS_ROWS + v - ATLAS_V, w, h), _colour)
	_x += _advance_x()


## FUN_800778A8: a 20 × 32 direction arrow (index & 8: held; 0x10 the neutral star), one of three
## pictures flipped, from 12 pixels above the pen.
func _arrow(index: int) -> void:
	var t := 8 if index == 0x10 else index & 7
	var uv := ram.u16(ARROWS + 4 * t)
	var flags := ram.u16(ARROWS + 4 * t + 2)
	var clut := ARROW_HELD_CLUT if index & 8 else ARROW_CLUT
	var tex := vram.sprite(uv & 0xFF, uv >> 8, 0x13, 0x1F, clut, ICON_TPAGE)
	if tex != null:
		var dest := r(_x, _y - 12, 0x13, 0x1F)
		if flags & 1:
			dest.size.x = -dest.size.x
		if flags & 2:
			dest.size.y = -dest.size.y
		target.draw_texture_rect(tex, dest, false, _colour)
	_x += 0x14


## A button diagram for `buttons` (1 LP, 2 RP, 4 LK, 8 RK): the four buttons' outline, and over
## it the pressed ones through the CLUT of the mask.
func _button(buttons: int) -> void:
	var clut := ((0x1FC + (1 if buttons & 8 else 0)) << 6) | 0x30 | (buttons & 7)
	sprt(_x, _y - 12, 0x14, 0x20, (BUTTON_BACK_CLUT << 16) | 0xE014, ICON_TPAGE, _colour)
	sprt(_x, _y - 12, 0x14, 0x20, (clut << 16) | 0xE000, ICON_TPAGE, _colour)
	_x += 0x14


## The glyph atlas of font 0 or 1: the side's fighter's costume.
func _atlas(font: int) -> Texture2D:
	var slot := flow.fight.fighters[clampi(font, 0, 1)].costume_slot
	if not _atlases.has(slot):
		var path := root.path_join("characters/costume_%02d/move_glyphs.png" % slot)
		_atlases[slot] = load(path) as Texture2D if ResourceLoader.exists(path) else null
	return _atlases[slot]
