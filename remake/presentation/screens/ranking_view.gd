class_name RankingView
extends PsxCanvas
## The ranking pages (ranking.ovl FUN_800C2A24's drawing, draw_sim.ranking_screen_draw): the page
## header picture with its shaded strip, and the rows (rank, face, name, time / wins / usage share
## and bar, entered name) clipped below the header, sliding up; during name entry the new row
## blinks on a blue band with the cursor under the letter. The stage turns behind (StageBackdrop).

const T := RankingScreen.TABLE_BASE
const NAME := RankingScreen.NAME_BASE
const STR_RANK := 0x800B9540
const STR_S := 0x800B9550
const STR_TICKS := 0x800B9560
const STR_TIME := 0x800B9570
const STR_100 := 0x800B958C
const STR_0 := 0x800B95A4
const STR_PCT := 0x800B95BC
const STR_3D := 0x800B95DC
const STR_WIN := 0x800B95EC
const STR_WINS := 0x800B95FC
const STR_2D := 0x800B960C
const ORDINALS := 0x800CBE18
const STYLE_TIME := 0x800CBE28
const STYLE_SURV := 0x800CBE34
const STYLE_USE := 0x800CBE3C
const BAR_COLOURS := 0x800B9378
const RECORDS := 0x8009832C
const SURVIVORS := 0x800983DC
const PAGE := 0x800984DC
const TIME_CAP := 359_999
const ROWS_CLIP := Rect2(0, 0x60, 0x170, 0x168)

var flow: GameFlow
var frame_count := 0
var _pages: Array[VramImage] = []


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	setup_psx(hud_data, game_ram, image)
	for i in 3:
		var v := image.duplicate_image()
		v.upload_file(screens_dir.path_join("ranking_%d.tims" % i))
		_pages.append(v)
	# The rows' lines, faces and bars are clipped below the header; their texts, in the front
	# slot, are not (the draw area is reset before the text slot is drawn).
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, func() -> void: _rows(false), ROWS_CLIP)
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, func() -> void: _strip(0x7FD0))
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, func() -> void: _strip(0x7F50))
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


func show_state(game: GameFlow) -> void:
	flow = game
	frame_count = game.fight.vblank
	vram = _pages[clampi(ram.u8(PAGE), 0, 2)]
	fade_level = game.ranking.fade if game.ranking.fade >= 0 else NO_FADE
	redraw()


func _mode() -> int:
	return ram.u16(T)


func _draw() -> void:
	begin()
	if flow == null:
		return
	var mode := _mode()
	if mode == RankingScreen.TableMode.HIDDEN:
		black()
	elif mode == RankingScreen.TableMode.NAME_ENTRY:
		# The name's row on a blue band (blend mode 0).
		fill(0, ram.u16(T + RankingScreen.T_NAME_SCREEN_ROW) * 0x48 + 0x68, 0x170, 0x48, Color(0, 0, 0x10 / 255.0, 0.5))


func _header() -> void:
	picture(0, 0x24, 0x80, 0x30, 0x180, 0, 0x7F50, 0x80)
	picture(0x80, 0x24, 0x70, 0x30, 0x180, 0x30, 0x7F50, 0x80)


## The header's shaded strip (POLY_GT4, added with CLUT 0x7F50 and subtracted with 0x7FD0).
func _strip(clut: int) -> void:
	if flow == null or _mode() == RankingScreen.TableMode.HIDDEN:
		return
	var tp := 0xA6 if clut == 0x7F50 else 0xC6
	var a := psx(0x808080)
	var b := psx(0x606060)
	var c := psx(0x101010)
	textured(vram.sprite(0x70, 0x30, 0x10, 0x30, clut, tp), 0xF0, 0x24, 0x10, 0x30, a, b, a, b)
	textured(vram.sprite(0, 0x60, 0x70, 0x30, clut, tp), 0x100, 0x24, 0x70, 0x30, b, c, b, c)


func _rows(texts: bool) -> void:
	if flow == null:
		return
	var mode := _mode()
	if mode < RankingScreen.TableMode.SLIDING or mode > RankingScreen.TableMode.NAME_ENTERED:
		return
	var page := ram.u8(PAGE)
	var entry := mode != RankingScreen.TableMode.SLIDING
	var blink := frame_count & 3 != 0
	var y0 := ram.s16(T + RankingScreen.T_Y)
	match page:
		0, 1:
			for i in ram.u16(T + RankingScreen.T_ROWS):
				var c := ram.u16(T + RankingScreen.T_CHARS + 2 * i)
				var style := 1 if entry and ram.u16(T + RankingScreen.T_NAME_ROW) == i and blink else 0
				if page == 0:
					_time_row(i, c, RECORDS + 8 * c, y0 + 0x48 * i, style, texts)
				else:
					_survivor_row(i, SURVIVORS + 8 * c, y0 + 0x48 * i, style, texts)
		2:
			for i in ram.u16(T + RankingScreen.T_ROWS):
				var c := ram.u16(T + RankingScreen.T_CHARS + 2 * i)
				var anim := 0 if i < ram.s32(T + RankingScreen.T_SHOWN) else ram.u16(T + RankingScreen.T_ALPHA)
				_usage_row(i, c, ram.u16(T + RankingScreen.T_USAGE + 2 * c), ram.u16(T + RankingScreen.T_TOP_SHARE), anim, y0 + 0x48 * i, texts)


func _front() -> void:
	if flow == null or _mode() == RankingScreen.TableMode.HIDDEN:
		return
	_header()
	_rows(true)
	if _mode() >= RankingScreen.TableMode.NAME_ENTRY:
		var pos := ram.u16(NAME + RankingScreen.N_POS)
		if pos < 3 and ram.u8(PAGE) < 2:
			fill(pos * 0xD + 0x129, ram.u16(T + RankingScreen.T_NAME_SCREEN_ROW) * 0x48 + 0xA0, 0x12, 4, psx(0xFF))
		var left := ram.u16(T + RankingScreen.T_HOLD)
		ptext(STR_2D, [1, 6, 1, 0x13C, 0x30, 0 if left == 0 else (left + 0x3B) / 0x3C])


func _name_of(character: int) -> String:
	return str(flow.fight.tables.character(character * 4)["name"])


func _rank(rank: int, colour: int, y: int) -> String:
	var suffix := mini(rank % 10, 3) if rank <= 3 else 3
	var n := 99 if rank + 1 > 100 else rank + 1
	var sfx := ram.string(ram.u32(ORDINALS + 4 * suffix))
	ptext(STR_RANK, [1, colour, 1, 0xC, y - 0x22, n, sfx])
	return sfx


func _row_lines(y: int) -> void:
	fill(8, y - 0xE, 0x3E, 8, psx(0x909090))
	fill(0x46, y - 8, 0x132 - 8, 2, psx(0x909090))


## FUN_800C133C: 1ST  <face> NAME  mm'ss"hh  entered name.
func _time_row(rank: int, character: int, rec: int, y: int, style: int, texts: bool) -> void:
	if (y & 0xFFFFFFFF) >= 0x228:
		return
	var s := STYLE_TIME + 5 * style
	if not texts:
		_row_lines(y)
		portrait(0x4C, y - 0x3A, character << 2, 8)
		return
	_rank(rank, ram.u8(s), y)
	ptext(STR_S, [1, ram.u8(s + 1), 0, 0x6F, y - 0x38, _name_of(character)])
	var c := ram.u8(s + 2)
	var t := mini(ram.s32(rec), TIME_CAP)
	ptext(STR_TICKS, [1, c, 1, y - 0x26, 0xB6, 0xD9])
	ptext(STR_TIME, [1, c, 1, y - 0x22, 0x9E, t / 60 / 60, 0xBF, (t / 60) % 60, 0xE3, (t % 60) * 100 / 60])
	ptext(STR_S, [1, ram.u8(s + 3), 1, 299, y - 0x22, ram.string(rec + 4).left(4)])


## FUN_800C16C0: 1ST  <face> NAME  n WIN(S)  entered name.
func _survivor_row(rank: int, e: int, y: int, style: int, texts: bool) -> void:
	if (y & 0xFFFFFFFF) >= 0x228:
		return
	var wins := mini(ram.u16(e + 2), 999)
	var s := STYLE_SURV + 4 * style
	var character := ram.u16(e)
	if not texts:
		_row_lines(y)
		portrait(0x4C, y - 0x3A, character << 2, 8)
		return
	_rank(rank, ram.u8(s), y)
	ptext(STR_S, [1, ram.u8(s + 1), 0, 0x6F, y - 0x38, _name_of(character)])
	var c := ram.u8(s + 2)
	if wins < 2:
		ptext(STR_3D, [1, c, 1, 0xAB, y - 0x22, wins])
		ptext(STR_WIN, [1, c, 1, 0xD9, y - 0x22])
	else:
		ptext(STR_3D, [1, c, 1, 0x9E, y - 0x22, wins])
		ptext(STR_WINS, [1, c, 1, 0xCC, y - 0x22])
	ptext(STR_S, [1, ram.u8(s + 3), 1, 299, y - 0x22, ram.string(e + 4).left(4)])


## FUN_800C19C4: 1ST  <face> NAME  share %  and a bar relative to the most used character.
func _usage_row(rank: int, character: int, share: int, top: int, anim: int, y: int, texts: bool) -> void:
	if (y & 0xFFFFFFFF) > 0x227:
		return
	var shown := 0
	var bar := 0
	if top != 0:
		shown = Fx.w32(share * anim) >> 6
		bar = Fx.div_trunc(Fx.w32(Fx.w32(share * anim) * 1000), top) >> 6
	var s := STYLE_USE
	if not texts:
		_row_lines(y)
		_usage_bar(character, bar, 0x111, y - 0x22)
		portrait(0x4C, y - 0x3A, character << 2, 8)
		return
	_rank(rank, ram.u8(s), y)
	ptext(STR_S, [1, ram.u8(s + 1), 0, 0x6F, y - 0x38, _name_of(character)])
	shown = mini(shown, 1000)
	if shown == 1000 or shown == 0:
		ptext(STR_100 if shown == 1000 else STR_0, [1, ram.u8(s + 2), 1, 0x11B, y - 0x22, 0, 0x145, y - 0x1E])
	else:
		ptext(STR_PCT, [1, ram.u8(s + 2), 1, 0x119, y - 0x22, shown / 10, 0, 0x134, y - 0x1E, 0x13B, shown % 10])


## FUN_800C1154: a usage bar, 129 × share / 1000 long, in the character's colours.
func _usage_bar(character: int, share: int, x: int, y: int) -> void:
	share = mini(Fx.w32(share), 1000)
	var w := Fx.s16(Fx.div_trunc(Fx.w32(share * 0x81), 1000)) if share else 0
	if w == 0:
		return
	var e := BAR_COLOURS + 0x14 * character
	var left := x - w
	var face := psx(ram.u32(e + 4))
	var face2 := psx(ram.u32(e + 8))
	var top := psx(ram.u32(e + 0xC))
	var top2 := psx(ram.u32(e + 0x10))
	var edge := psx(ram.u32(e))
	quad(Vector2(left - 6, y - 8), Vector2(x - 8, y - 8), Vector2(left, y), Vector2(x, y), top, top2, top, top2)
	quad(Vector2(left - 6, y - 8), Vector2(left, y), Vector2(left - 6, y + 0x10), Vector2(left, y + 0x18), edge, edge, edge, edge)
	gradient(left, y, w, 0x18, face, face2, face, face2)
