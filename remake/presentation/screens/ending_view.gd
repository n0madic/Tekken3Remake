class_name EndingView
extends PsxCanvas
## ending.ovl's screens after the movie: the staff roll (draw_sim roll_glow, roll_text, roll_logo:
## additive glyphs from the roll's font sheets, a glow behind the lines that fade in and out, the
## Namco logo) and THEATER MODE (theater_sim.theater_draw: the movie grid or the sound list, the
## buttons, the selected entry, the panels and the page title that gives way to PUSH START).
##
## The Theater's disc mode is out of scope (TheaterScreen): its DISC buttons are not drawn.

## The roll's fonts (FUN_8011484C): columns, v0, cell, space. Headings (StaffRoll.Line.wide) use
## font 1 with the wide widths, names font 0 with the narrow widths.
const ROLL_FONTS := {true: [0x15, 0, 0xC, 8], false: [0xE, 0x24, 0x12, 0xC]}
const ROLL_CLUT := 0x1828
const ROLL_TPAGE := 0x2A
const LOGO_CLUT := 0x2C28
const PICTURES := 0x800BA08C
const CELL_FRAME := 0x800BA368
const TIMS := 0x800BA374
const PANELS := 0x800BA730
const STRIPS := 0x800BA838
const STRIP_PIECES := 0x800BA790
const BANNERS := 0x8011DAA8
const IDLE_FRAMES := 0x1E0

var flow: GameFlow
var frame_count := 0
var _idle := 0
var _roll: VramImage
var _theater: VramImage


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	setup_psx(hud_data, game_ram, image)
	_roll = image.duplicate_image()
	_roll.upload_file(screens_dir.path_join("staff.tims"))
	_theater = image.duplicate_image()
	_theater.upload_file(screens_dir.path_join("theater.tims"))
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _staff_roll)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _theater_page)


func show_state(game: GameFlow) -> void:
	flow = game
	frame_count = game.fight.vblank
	vram = _theater if game.theater.kind != 0 else _roll
	_idle = 0 if game.held(0) != 0 or game.held(1) != 0 else _idle + 1
	redraw()


func _draw() -> void:
	begin()
	black()


# ---- the staff roll -------------------------------------------------------------------------

func _staff_roll() -> void:
	if flow == null or flow.theater.kind != 0 or flow.sub != 3:
		return
	var roll := flow.ending.roll
	for l in roll.lines:
		if l.glow:
			_glow(l)
		_roll_text(l)
	if roll.logo_bright >= 0:
		var k := roll.logo_bright / 128.0
		var tint := Color(k, k, k)
		ft4(0x36, 0xDC, 0x100, 0x2D, 0, 0x80, 0xFF, 0x2C, LOGO_CLUT, 0xA, tint)
		ft4(0x136, 0xDC, 5, 0x2D, 0, 0x80, 4, 0x2C, LOGO_CLUT, 0xB, tint)


## FUN_8011484C: a credit line as glyphs 12 pixels high, modulated by the line's brightness.
func _roll_text(l: StaffRoll.Line) -> void:
	var f: Array = ROLL_FONTS[l.wide]
	var cols: int = f[0]
	var v0: int = f[1]
	var cell: int = f[2]
	var space: int = f[3]
	var widths := flow.data.staff_font_wide if l.wide else flow.data.staff_font_narrow
	var k := l.bright / 128.0
	var tint := Color(k, k, k)
	var x := l.x
	for i in l.text.length():
		var c := l.text.unicode_at(i)
		if c == 0x20:
			x += space
			continue
		var n := c - 0x21 if c < 0x31 else c - 0x22
		if n < 0 or n >= widths.size():
			continue
		var w := widths[n]
		ft4(x, l.y, w, 0xC, ((n % cols) * cell) & 0xFF, ((n / cols) * 0xC + v0) & 0xFF, w, 0xC, ROLL_CLUT, ROLL_TPAGE, tint)
		x += w


## FUN_80113A3C: the glow behind a line (25 Gouraud quads, additive).
func _glow(l: StaffRoll.Line) -> void:
	var r := l.rgb.x & 0xFF
	var g := l.rgb.y & 0xFF
	var b := l.rgb.z & 0xFF
	var full := Color8(r, g, b)
	var half := Color8(r >> 1, g >> 1, b >> 1)
	var none := Color.BLACK
	var left := StaffRoll.CENTRE - l.width / 2
	var y := l.y
	var x0 := l.x
	var x1 := l.x + l.width
	var a1 := left - 0x10
	var a17 := left + 0x18
	var a2 := left + 0x30
	var a13 := x0 + 0x10
	var a3 := x0 + 0x10 + l.width - 0x28
	var a4 := x1
	var a10 := x1 - 0x18
	var a5 := x1 + 0x28
	var a11 := left - 0x20
	var a12 := left + 0x24
	var a6 := x1 - 0xC
	var a7 := x1 + 0x38
	var b22 := left + 0x16
	var c2 := x1 + 2
	# [x left, x right, y top, y bottom, colours top-left, top-right, bottom-left, bottom-right]
	var quads: Array = [
		[a1, a17, -2, 1, none, half, none, half], [a17, a2, -2, 1, half, half, half, full],
		[a13, a3, -2, 1, half, half, full, full], [a4, a10, -2, 1, half, half, half, full],
		[a5, a4, -2, 1, none, half, none, half], [a11, a12, 1, 4, none, full, none, full],
		[a12, a2, 1, 4, full, full, full, full], [a13, a3, 1, 4, full, full, full, full],
		[a10, a6, 1, 4, full, full, full, full], [a6, a7, 1, 4, full, none, full, none],
		[a11, b22, 4, 7, none, half, none, full], [b22, a2, 4, 7, half, full, full, full],
		[a13, a3, 4, 7, full, full, full, full], [c2, a10, 4, 7, half, full, full, full],
		[a7, c2, 4, 7, none, half, none, full], [a11, a12, 7, 10, none, full, none, full],
		[a12, a2, 7, 10, full, full, full, full], [a13, a3, 7, 10, full, full, full, full],
		[a10, a6, 7, 10, full, full, full, full], [a6, a7, 7, 10, full, none, full, none],
		[a17, a1, 10, 13, half, none, half, none], [a2, a17, 10, 13, full, half, half, half],
		[a13, a3, 10, 13, full, full, half, half], [a10, a4, 10, 13, full, half, half, half],
		[a4, a5, 10, 13, half, none, half, none]]
	for q: Array in quads:
		var xl: int = q[0]
		var xr: int = q[1]
		var yt: int = y + (q[2] as int)
		var yb: int = y + (q[3] as int)
		quad(Vector2(xl, yt), Vector2(xr, yt), Vector2(xl, yb), Vector2(xr, yb), q[4] as Color, q[5] as Color,
			q[6] as Color, q[7] as Color)


# ---- THEATER MODE ---------------------------------------------------------------------------

func _theater_page() -> void:
	if flow == null or flow.theater.kind == 0 or flow.sub != 1:
		return
	var t := flow.theater
	_panel(0)
	_panel(1)
	if t.kind == TheaterScreen.PAGE_MOVIES:
		_movie_grid(t)
	else:
		_sound_list(t)
	_banner(t.kind)


func _frame4(x: int, y: int, w: int, h: int, side: int, top: int, colour: int) -> void:
	var c := psx(colour)
	fill(x, y, w, top, c)
	fill(x, y, side, h, c)
	fill(x, y + h - top, w, top, c)
	fill(x + w - side, y, side, h, c)


func _panel_frame(k: int, dx: int, dy: int) -> void:
	var r := PANELS + 0x20 * k
	_frame4(ram.s16(r) + dx, ram.s16(r + 2) + dy, ram.s16(r + 4), ram.s16(r + 6), ram.u8(r + 0xA), ram.u8(r + 0xB),
		ram.u32(r + 0x1C))


## A panel: its Gouraud quad, semi-transparent with flag 2 (bug #36 not reproduced: the game
## ORs the flag into the first corner's red), then its frame.
func _panel(k: int) -> void:
	var r := PANELS + 0x20 * k
	var flags := ram.u16(r + 8)
	if flags & 1:
		var alpha := 0.5 if flags & 2 else 1.0
		var c: Array[Color] = []
		for i in 4:
			var col := psx(ram.u32(r + 0xC + 4 * i))
			col.a = alpha
			c.append(col)
		gradient(ram.u16(r), ram.u16(r + 2), ram.u16(r + 4), ram.u16(r + 6), c[0], c[1], c[2], c[3])
	if ram.u8(r + 0xA):
		_panel_frame(k, 0, 0)


func _sprite(x: int, y: int, rec: int, u: int, w: int, h: int, tpage: int) -> void:
	var clut := ((ram.s16(rec + 2) << 6) | ((ram.s16(rec) >> 4) & 0x3F)) & 0xFFFF
	sprt(x, y, w, h, (u & 0xFF) | ((ram.s16(rec + 6) & 0xFF) << 8) | (clut << 16), tpage)


## An 8-bit 48 × 64 movie picture (0: the locked picture).
func _picture(x: int, y: int, k: int) -> void:
	var r := PICTURES + 12 * k
	var px := ram.s16(r + 4)
	var py := ram.s16(r + 6)
	_sprite(x, y, r, (px & 0x7F) << 1, 0x30, 0x40, ((py & 0x100) >> 4) | ((px & 0x380) >> 6) | 0x80)


func _cell_frame(x: int, y: int) -> void:
	var px := ram.s16(CELL_FRAME + 4)
	var py := ram.s16(CELL_FRAME + 6)
	_sprite(x, y, CELL_FRAME, 0x60, 0x30, 0x40, ((py & 0x100) >> 4) | ((px & 0x3C0) >> 6))


## FUN_8010FB24: TIM k (the disc logos 0–5, the sound picture 7) as one sprite.
func _tim_sprite(x: int, y: int, k: int) -> void:
	var r := TIMS + 14 * k
	var px := ram.s16(r + 4)
	var py := ram.s16(r + 6)
	var mode := ram.u16(r + 0xC) & 1
	_sprite(x, y, r, (px & 0x3F) << (1 if mode else 2), ram.u16(r + 8), ram.u16(r + 0xA),
		(mode << 7) | ((py & 0x100) >> 4) | ((px & 0x380) >> 6))


## Help strip k: pieces of a text picture in a row at y 400, centred; in English the USA
## release's line k (ending.ovl FUN_80100834: font 0, colour 6, centred at 9 pixels a letter).
func _strip(k: int) -> void:
	var line := ram.locale.theater_line(k) if ram.locale != null else ""
	if not line.is_empty():
		text(line, 0, 6, (0x170 - 9 * line.length()) >> 1, 400)
		return
	var x := (0x170 - 12 * ram.s16(STRIPS + 4 * k)) >> 1
	var r := STRIP_PIECES + 12 * ram.s16(STRIPS + 4 * k + 2)
	while true:
		var clut := (((ram.s16(r + 8) * 16 + 0x200) >> 4) & 0x3F) | 0x7F80
		var w := ram.u16(r + 4)
		sprt(x, 400, w, ram.u16(r + 6), ram.u8(r) | (ram.u8(r + 2) << 8) | (clut << 16), 0x16)
		x += ram.s16(r + 4)
		var more := ram.s16(r + 0xA)
		r += 12
		if more == 0:
			break


func _help_strip(focus: int, page: int) -> void:
	var table := {1: 7, 2: 5, 3: 0} if page == TheaterScreen.PAGE_MOVIES else {1: 7, 2: 4, 3: 1, 4: 6}
	if table.has(focus):
		_strip(table[focus] as int)


func _pulse() -> int:
	return scale_colour(0xFF4020, (triangle(frame_count << 4) >> 1) + 0x80)


## FUN_801106A8: a label in a white frame over a dark blue box, or a pulsing one when selected
## (bug #37 not reproduced: the game starts the box 2 pixels above the frame).
func _button(focus: int, which: int, x: int, y: int, label: String) -> void:
	var selected := focus == which
	var x0 := x - 8
	var y0 := y - 6
	var w := 16 + 9 * label.length()
	var h := 12 + 16
	fill(x0, y0, w, h, psx(_pulse() if selected else 0x800000))
	_frame4(x0, y0, w, h, 2, 2, 0xFFFFFF)
	text(label, 0, 5 if selected else 10, x, y)


## FUN_80110A58: 6 × 4 pictures, the buttons and the selected movie's names, drawn in the
## reverse of their linking: the names first, the cursor's frame last.
func _movie_grid(t: TheaterScreen) -> void:
	var movies := flow.data.theater_movies
	var count := movies.size()
	var texts := flow.data.theater_texts
	_movie_names(t)
	if flow.ending.all_movies != 0:
		_button(t.focus, TheaterScreen.Focus.EXIT, 0xFC, 0x158, str(texts["exit"]))
		_button(t.focus, TheaterScreen.Focus.SWITCH, 0xA2, 0x158, str(texts["sound"]))
	else:
		_button(t.focus, TheaterScreen.Focus.EXIT, 0xA2, 0x158, str(texts["exit"]))
	for row in range(3, -1, -1):
		var y := 0x48 + 0x40 * row
		for col in range(5, -1, -1):
			var i := col + (row + t.top) * 6
			if i >= count:
				continue
			var e: Dictionary = movies[i]
			var x := 0x28 + 0x30 * col
			if t.entry_status(i) >= 0:
				if JsonFile.number(e["picture"]) >= 0:
					_picture(x, y, JsonFile.number(e["picture"]))
				_cell_frame(x, y)
			elif JsonFile.number(e["movie"]) >= 0:
				_picture(x, y, 0)
				_cell_frame(x, y)
	if t.focus == TheaterScreen.Focus.LIST and flow.fight.vblank & 0x1C:
		_panel_frame(2, t.cursor % 6 * 0x30 + 0x26, (t.cursor / 6 - t.top) * 0x40 + 0x45)


## The selected movie's picture, name and title lines (or ??? while locked), or the focused
## button's help strip.
func _movie_names(t: TheaterScreen) -> void:
	var movies := flow.data.theater_movies
	if t.focus != TheaterScreen.Focus.LIST or t.cursor >= movies.size():
		_help_strip(t.focus, t.kind)
		return
	var e: Dictionary = movies[t.cursor]
	var picture := JsonFile.number(e["picture"])
	if t.entry_status(t.cursor) < 0:
		if picture > 0:
			text(str(flow.data.theater_texts["locked"]), 1, 6, 0xC1, 0x182)
		return
	var lines: Array = e["lines"]
	var ys := PackedInt32Array([0x1A6]) if lines.size() == 1 else PackedInt32Array([0x19D, 0x1AF])
	for k in mini(lines.size(), 2):
		var s := str(lines[k])
		text(s, 0, 5, ((0xE6 - 9 * s.length()) >> 1) + 0x64, ys[k])
	var name := t.movie_name(t.cursor)
	text(name, 1, 6, ((0xE9 - 13 * name.length()) >> 1) + 0x60, 0x182)
	if picture > 0:
		_picture(0x1E, 0x180, picture)


## FUN_801112DC: 14 lines of the track list, the buttons, the selected track and the disc logos,
## drawn in the reverse of their linking: the logos first, the list's frame last.
func _sound_list(t: TheaterScreen) -> void:
	var tracks := flow.data.theater_tracks
	var texts := flow.data.theater_texts
	_tim_sprite(0xF2, 0x15A, t.disc * 2 - 1)
	_tim_sprite(0xF2, 0x5A, t.disc * 2 - 2)
	if t.focus == TheaterScreen.Focus.LIST and t.cursor < tracks.size():
		var name := str((tracks[t.cursor] as Dictionary)["name"])
		var x := (0x170 - 13 * name.length()) >> 1
		text(str(texts["arrange" if t.kind == TheaterScreen.PAGE_ARRANGE else "arcade"]), 0, 5, 0x104, 0x1A6)
		_tim_sprite(x - 0xE, 0x182, 7)
		text(name, 1, 6, x + 0x10, 0x186)
	else:
		_help_strip(t.focus, t.kind)
	_button(t.focus, TheaterScreen.Focus.EXIT, 0xFA, 0x122, str(texts["exit"]))
	_button(t.focus, TheaterScreen.Focus.BGM, 0xFA, 0xE6, str(texts["bgm"]))
	if flow.movies_available:
		_button(t.focus, TheaterScreen.Focus.SWITCH, 0xFA, 0xC8, str(texts["theater"]))
	for i in range(TheaterScreen.LINES_SHOWN - 1, -1, -1):
		var idx := t.top + i
		if idx >= tracks.size():
			continue
		var hit := t.focus == TheaterScreen.Focus.LIST and idx == t.cursor
		if hit:
			fill(0x19, 0x4F + 0x14 * i, 0xCC, 0x12, psx(_pulse()))
		var colour := 5 if hit else (0xB if t.kind == TheaterScreen.PAGE_ARRANGE else 0xA)
		text("%2d:%s" % [idx + 1, str((tracks[idx] as Dictionary)["name"])], 0, colour, 0x1E, 0x50 + 0x14 * i)
	_frame4(0x18, 0x48, 0xCE, 0x122, 2, 2, 0xFFFFFF)


## FUN_80112554: the page title; after 480 idle frames it alternates every 256 frames with
## PUSH START TO PLAY, sliding for the last 32 frames of each half.
func _banner(page: int) -> void:
	var t := _idle - IDLE_FRAMES if _idle >= IDLE_FRAMES else 0
	var x := 0x228 if t & 0x100 else 0xB8
	if t & 0xE0 == 0xE0:
		var d := ((t & 0x1F) * 23) >> 1
		x += -d if t & 0x100 else d
	var title := ram.string(ram.u32(BANNERS + 4 * (page - 1) + 12 * flow.theater.disc))
	print_fmt("%c%f%H%V" + title, [6, 1, x - ((title.length() * 13) >> 1), 0x22, 1 if page == 2 else 6])
	var hint := ram.string(ram.u32(BANNERS + 8))
	print_fmt("%c%f%H%V" + hint, [6, 0, x - ((hint.length() * 9) >> 1) - 0x170, 0x22, 5, 6, 5])
