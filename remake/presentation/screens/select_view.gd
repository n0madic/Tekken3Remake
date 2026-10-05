class_name SelectView
extends PsxCanvas
## The character select screen (select.ovl's drawing, select_sim.select_draw), on the screen's own
## pictures (VRAM after select.ovl's upload). The game links it all into the background slot, so it
## draws in the reverse order of the calls: the scrolling tiles over the title pictures, the
## coloured backlights (added), the layout's pictures over their gradient, the grid of faces, the
## name plates, the time limit, the NEW arrows, the big portraits and the rising sparks; the
## cursors are in the slots above.
##
## The portraits' bands (FUN_8010F38C): at full brightness drawn as they are; below it (and always
## at the top and bottom, which fade over their height) the band's shape is first subtracted
## through CLUT 0x7FD0 (all white but 0) and the picture added, both scaled, so it fades in over
## the backlight. Portrait attribute 0x15 is only ever subtracted.

const CTX := CharacterSelect.BASE
const SMALL_FACES := 0x800B93C8      ## one-row layout: per character u32 uv|clut, u16 tpage
const BG_ROWS := 0x80118BDC
const BG_TILES := 0x80118C1C
const PORTRAIT_BANDS := 0x80118B9C   ## per strip layout (attribute >> 6): three band heights
const BAND_SHADES := 0x80118BCC      ## four brightness weights (x/32) at the band edges
const IMAGE_LISTS: Array[int] = [0x800B9418, 0x800B9528]
const PORTRAIT_W := 0x7E
const FULL := 0x100
const SUBTRACTED_PORTRAIT := 0x15    ## the attribute byte of the portrait drawn subtracted
## How `_portraits` draws: the bands at full brightness, the fading bands' shapes subtracted, the
## fading bands added, and the subtracted portrait.
enum Bands { OPAQUE, SHAPES, FADING, SUBTRACTED }

var select: CharacterSelect
var portraits: Array[Texture2D] = []
var frame_count := 0


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	setup_psx(hud_data, game_ram, image)
	pictures_dir = screens_dir
	reload_pictures()
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _backlights)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _middle)
	add_texel_mask_pass(func() -> void: _portraits(Bands.SHAPES))
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, func() -> void: _portraits(Bands.SUBTRACTED))
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _glowing)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _cursors)


## The portraits, from the texture pack in use.
func reload_pictures() -> void:
	portraits = character_pictures(pictures_dir, "portraits")


func show_state(game: GameFlow) -> void:
	select = game.select
	frame_count = game.fight.vblank
	redraw()


func _shown() -> bool:
	return select != null and select.frames() >= CharacterSelect.DRAW_FROM


func rec(p: int) -> int:
	return CTX + CharacterSelect.RECORDS + CharacterSelect.RECORD_SIZE * p


func _draw() -> void:
	begin()
	black()
	if _shown():
		_background()


## FUN_801102A0: the black top, the title pictures, and over them the diagonally scrolling tiles
## (clipped above the grid).
func _background() -> void:
	var limit := ram.s32(CTX + 0x128)
	fill(0, 0, SCREEN.x, limit, Color.BLACK)
	picture(0x80, 0x3A, 0x6E, 0x20, 0x24D, 0x112, 0x7CA4, 0)
	picture(0x54, 0x62, 0xC6, 0xE, 0x242, 0x13A, 0x7CA4, 0)
	picture(0x80, 0x78, 0x70, 0x1E, 0x24D, 0x150, 0x7CA4, 0)
	var s := -(frame_count << 7) & 0xFFFFFFFF
	var v := Fx.w32(s) >> 4
	var frac := (0x40 - v) & 0x3F
	var h := 0x40 - frac
	var row := 7 - ((v - 1) >> 6)
	var y := DISPLAY.position.y
	while y < mini(0x155, limit):
		var pat := BG_ROWS + (row & 7) * 8
		var x := 0
		var du := 8
		var w := 0x28
		for i in 8:
			var uv := ram.u32(BG_TILES + 4 * ram.u8(pat))
			pat += 1
			uv += du
			uv += frac << 8
			sprt(x, y, w, mini(h, limit - y), uv & 0xFFFFFFFF, 0x18)
			x += w
			w = 0x30
			du = 0
		y += h
		h = 0x40
		frac = 0
		row += 1


func _attr_colour(p: int) -> Color:
	var key := ram.s32(rec(p) + CharacterSelect.R_SHOWN_KEY)
	var costume := ram.s32(rec(p) + CharacterSelect.R_SHOWN_COSTUME)
	return psx(select.g.data.attribute(key, costume) >> 8)


## FUN_8010FBFC: the glow behind each portrait, in the character's colour (added).
func _backlights() -> void:
	if not _shown():
		return
	for p in 2:
		var c := _attr_colour(p)
		var x := ram.u16(rec(p) + 0x54)
		var y := ram.s32(CTX + 0x120)
		gradient(x, y - 0x14, 0x7E, 0xE4, Color.BLACK, Color.BLACK, c, c)
		gradient(x, y + 0xD0, 0x7E, 0x48, c, c, psx(0xC0C0C0), psx(0xC0C0C0))


## The layout's pictures, the grid of faces, the name plates, the time limit, the NEW arrows and
## the portraits' fully bright bands.
func _middle() -> void:
	if not _shown():
		return
	_pictures()
	_grid_faces()
	_name_plates()
	var d := ram.s32(CTX + 0x18)
	if d != 0:
		timer((ram.s32(CTX + 0x14) + d - 1) / d, 0xB8, ram.u32(CTX + 0x140), ram.u32(CTX + 0x144))
	_new_arrows()
	_portraits(Bands.OPAQUE)


## The portraits' fading bands and the sparks (added).
func _glowing() -> void:
	if not _shown():
		return
	_portraits(Bands.FADING)
	_sparks()


## FUN_80110154: the gradient under the grid, then the layout's static pictures over it.
func _pictures() -> void:
	var two_rows := ram.u32(CTX + 4)
	var c := 0xD0 if two_rows else 0
	var y0 := ram.s32(CTX + 0x128) + 0x10
	gradient(0, y0, SCREEN.x, SCREEN.y - y0, Color.BLACK, Color.BLACK, psx(c), psx(c))
	var e: int = IMAGE_LISTS[1 if two_rows else 0]
	var entries: Array[int] = []
	while ram.u16(e) != 0xFFFF:
		entries.append(e)
		e += 16
	# Linked in list order: the last picture is drawn first.
	entries.reverse()
	for at in entries:
		picture(ram.u16(at + 2), ram.u16(at + 4), ram.u16(at + 6), ram.u16(at + 8), ram.u16(at + 10),
			ram.u16(at + 12), ram.u16(at + 14), ram.u16(at))


## FUN_8010F760: the big portraits in three bands, brightening in over 32 frames, mirrored to face
## the middle, from the layout's first texel row (v 0; the CLUT moves on every 64 rows, which the
## pictures carry). `kind`: which of the bands' draws (Bands) this pass makes.
func _portraits(kind: Bands) -> void:
	if not _shown():
		return
	for p in 2:
		var rp := rec(p)
		var key := ram.s32(rp + CharacterSelect.R_SHOWN_KEY)
		var costume := ram.s32(rp + CharacterSelect.R_SHOWN_COSTUME)
		if key >= CharacterSelect.NO_CELL:
			continue
		var attr := select.g.data.attribute(key, costume) & 0xFF
		if (attr & 0x1F) >= portraits.size():
			continue
		var subtracted := attr == SUBTRACTED_PORTRAIT
		if subtracted != (kind == Bands.SUBTRACTED):
			continue
		var slide := ram.s32(rp + CharacterSelect.R_CHOSEN_ANIM)
		var k := 0x20 - slide if slide else 0x20
		var x := ram.u16(rp + 0x54)
		var y := ram.s32(CTX + 0x120)
		var flip := ram.u32(rp + CharacterSelect.R_FLIP) == 1
		var tex := portraits[attr & 0x1F]
		var bands := PORTRAIT_BANDS + (attr >> 6) * 12
		var w_prev := ram.s32(BAND_SHADES)
		var row := 0
		for band in 3:
			var b0 := Fx.w32(w_prev * k) >> 5
			w_prev = ram.s32(BAND_SHADES + 4 + 4 * band)
			var b1 := Fx.w32(w_prev * k) >> 5
			var h := ram.s32(bands + 4 * band)
			var opaque := b0 == b1 and b0 >= FULL and not subtracted
			var shown := b0 != b1 or b0 != 0
			if h > 0 and shown and opaque == (kind == Bands.OPAQUE):
				_band(tex, x, y, h, row, flip, _band_shade(b0, opaque), _band_shade(b1, opaque))
			y += h
			row += h


## A band edge's colour: FUN_8004E254 scales 0x7F7F7F by the brightness (/0x100), a texture
## modulation of 0x80 = 1.
func _band_shade(brightness: int, opaque: bool) -> Color:
	if opaque:
		return Color.WHITE
	var c := modulation(psx(scale_colour(0x7F7F7F, brightness)))
	return Color(minf(c.r, 1.0), minf(c.g, 1.0), minf(c.b, 1.0))


func _band(tex: Texture2D, x: float, y: float, h: int, row: int, flip: bool, top: Color, bottom: Color) -> void:
	var size := tex.get_size()
	var u0 := 0.0
	var u1 := PORTRAIT_W / size.x
	if flip:
		var t := u0
		u0 = u1
		u1 = t
	var v0 := row / size.y
	var v1 := (row + h) / size.y
	var points := PackedVector2Array([pt(x, y), pt(x + PORTRAIT_W, y), pt(x + PORTRAIT_W, y + h), pt(x, y + h)])
	var uvs := PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)])
	target.draw_polygon(points, PackedColorArray([top, top, bottom, bottom]), uvs, tex)


## FUN_8010FD64: the grid of small faces (the two-row layout shows the HUD portraits).
func _grid_faces() -> void:
	var dy := ram.s32(CTX + 0x12C)
	var two_rows := ram.u32(CTX + 4)
	for i in range(CharacterSelect.CELL_COUNT - 1, -1, -1):
		var c := CharacterSelect.CELLS_BASE + CharacterSelect.CELL_SIZE * i
		var key := ram.s16(c + 6)
		if ram.u8(c + 5) == 0 or key >= 0x16:
			continue
		var x := ram.s16(c + 8)
		var y := ram.s16(c + 0xA) + dy
		if two_rows:
			portrait(x, y, key << 2, 8)
		else:
			sprt(x, y, 0x20, 0x44, ram.u32(SMALL_FACES + 8 * key), ram.u16(SMALL_FACES + 8 * key + 4))


## FUN_8010FEA0: each side's cursor frame (pulsing while choosing) in two halves, each side's own
## half in the higher slot, and its tag above.
func _cursors() -> void:
	if not _shown():
		return
	var halves: Array[Array] = []
	var tags: Array[Array] = []
	for p in 2:
		var rp := rec(p)
		var kind := ram.u32(rp + 8)
		if kind == 0:
			continue
		var level := 0x80
		var layer := 0
		if kind == 1 or kind == 3:
			level = triangle(frame_count << 4)
			layer = 2
		var c := CharacterSelect.CELLS_BASE + CharacterSelect.CELL_SIZE * ram.u32(rp + 4)
		if ram.u8(c + 5) == 0:
			continue
		var x := ram.s16(c + 8) - 2
		var y := ram.s16(c + 0xA) + ram.s32(CTX + 0x12C)
		var k := scale_colour(0xFFFFFF, level) & 0xFF
		var tint := Color(k / 128.0, k / 128.0, k / 128.0)
		var chosen := ((kind - 3) & 0xFFFFFFFF) < 2
		var uv := ram.u32(rp + 0x70) if chosen else ram.u32(rp + 0x6C)
		tags.append([x + ram.u16(rp + 0x7A), y + ram.s32(CTX + 0x13C), uv, tint])
		uv = ram.u32(rp + 0x64) if ram.u32(CTX + 4) == 0 else ram.u32(rp + 0x68)
		if chosen:
			uv = (uv & 0xFFFF) | 0x7CA90000
		y += ram.s32(CTX + 0x138)
		for i in 2:
			halves.append([layer * 4 + (4 if i == p else 0), -(p * 2 + i), x, y, uv, tint])
			x += 0x12
			uv = (uv & 0xFFFFFF00) | ((uv + 0x12) & 0xFF)
	halves.sort()
	for hv: Array in halves:
		sprt(hv[2] as int, hv[3] as int, 0x12, ram.u32(CTX + 0x134), hv[4] as int, 0x19, hv[5] as Color)
	for t: Array in tags:
		sprt(t[0] as int, t[1] as int, 0x14, 0x10, t[2] as int, 0xE, t[3] as Color)


## FUN_8010EDFC: each side's name plate (and the start prompt of a side that can join).
func _name_plates() -> void:
	var y := ram.s32(CTX + 0x124)
	for p in 2:
		var rp := rec(p)
		var x := ram.u16(rp + 0x56)
		var kind := ram.s32(rp + 0xC)
		if kind == 2:
			coin(p, x, 0x22, ram.u32(CTX + 0x148), frame_count)
		if kind == 1 or kind == 2:
			var w := ram.u32(rp + CharacterSelect.R_RECORD5)
			if w != 0:
				var n := ram.u32(rp + CharacterSelect.R_BASE)
				var uv := ((n << 3) & 0x80) | ((n & 0xF) << 12) | 0x7CA50000
				sprt(x - (w >> 1), y, w, 0x10, uv, 0xB)


## FUN_8010EC9C: blinking arrows at the grid's ends while a character is new.
func _new_arrows() -> void:
	if ram.u32(CTX + 0x10) == 0:
		return
	var y := ram.s32(CTX + 0x128) - 0xA0
	var v := triangle(frame_count << 4)
	var d := frame_count & 0x1F
	if d >= 0x11:
		d = 0x1F - d
	d >>= 1
	var tint := Color(v / 128.0, v / 128.0, v / 128.0)
	sprt(0xC - d, y, 0xA, 0x10, 0x7E1500E0, 0x19, tint)
	sprt(0x15A + d, y, 0xA, 0x10, 0x7E1500EA, 0x19, tint)


## FUN_8010F020: the rising streaks (added).
func _sparks() -> void:
	for spark in select.sparks:
		if spark.active != 1:
			continue
		var a := clampi(spark.bright, 0, 0xFF) / 255.0
		var top := Color(a, a, a)
		gradient(spark.x, spark.y, 1, 0xA0, top, top, Color.BLACK, Color.BLACK)
