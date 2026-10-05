class_name ResultView
extends PsxCanvas
## The result screens of result.ovl (draw_sim team_screen_draw, time_attack_screen_draw,
## survival_screen_draw): team battle's members, fight grid and joining lines, time attack's stage
## times over its picture, survival's beaten characters and rank, over the scrolling banner.
##
## The game draws the background slot last-linked first (the black tile, the backdrop, the banner
## band subtracted, the stripes, then the portraits and boxes) and the text slot in front; the
## blended parts are passes.

const S := ResultScreens.BASE
const MODE := ModeRegion.BASE + 0x50
const LADDER := MODE + 0x90
const TEAM_LABELS := 0x800B9378
const TEAM_MESSAGES := 0x800B9428
const FACE_UV := 0x800B9778
const STR_VS_ROW := 0x800B9494
const STR_STAGE_1X := 0x800B951C
const STR_STAGE_2D := 0x800B9530
const STR_TICKS := 0x800B9544
const STR_TIME := 0x800B9554
const STR_YOUR_TIME := 0x800B959C
const STR_TOTAL_TICKS := 0x800B9570
const STR_TOTAL_TIME := 0x800B9580
const STR_NEW_RECORD := 0x800B95B0
const STR_WIN := 0x800B968C
const STR_WINS := 0x800B9698
const STR_YOU_ARE := 0x800B96C0
const STR_GREATEST := 0x800B96D0
const STR_PRACTICE := 0x800B96E4
const ORDINALS := 0x800F29B8
const SURVIVOR_COLOURS := 0x800B96FC
const BANNER_TILES := 0x800B9838
const BANNER := 0x800FAC0C
const STR_TEAM_TITLE := 0x800B94A8
const STR_TA_TITLE := 0x800B95C4
const STR_SURV_TITLE := 0x800B9710
const STR_TOTAL := 0x800B9700
const TA_ROW_POS := 0x800B94F4
const SURVIVOR_POS := 0x800B960C
const TIME_CAP := 359_999
const TEAM_BACKDROP := 0x1830F0
const SURVIVAL_BACKDROP := 0xA0C000
const TIME_ATTACK_CLEAR := 0x2030A0
const FORCE_KEYS: Array[String] = ["COPPER", "SILVER", "GOLD"]
const FORCE_KEY_COLOURS: Array[int] = [2, 6, 5]
const FORCE_KEY_AFTER: Array[int] = [0x59, 0x77, 0x95]
const FORCE_BOSS_AFTER: Array[int] = [0, 0x13, 0x27, 0x3B]

var flow: GameFlow
var frame_count := 0
var _screen := 0                     ## the game state shown (12 team, 13 time attack, 14 survival)
var _system: VramImage
var _time_attack: VramImage
var _force: VramImage
var _portraits: Array[Texture2D] = []


func setup(hud_data: HudData, game_ram: GameRam, image: VramImage, screens_dir: String) -> void:
	setup_psx(hud_data, game_ram, image)
	_system = image
	_time_attack = image.duplicate_image()
	_time_attack.upload_file(screens_dir.path_join("result_ta.tims"))
	_force = image.duplicate_image()
	_force.upload_file(screens_dir.path_join("result_force.tims"))
	pictures_dir = screens_dir
	reload_pictures()
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, _subtracted)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _middle)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _added)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


## The portraits, from the texture pack in use.
func reload_pictures() -> void:
	_portraits = character_pictures(pictures_dir, "vs_portraits")


func show_state(game: GameFlow) -> void:
	flow = game
	_screen = game.state
	frame_count = game.fight.vblank
	vram = _time_attack if _screen == GameFlow.State.TIME_RESULT else _force if _force_result() else _system
	fade_level = ram.s32(S + ResultScreens.BRIGHT)
	redraw()


func _force_result() -> bool:
	return _screen == GameFlow.State.FORCE_RESULT


func _team() -> bool:
	return _screen == GameFlow.State.TEAM_RESULT


func _draw() -> void:
	begin()
	black()
	if flow == null:
		return
	if _screen == GameFlow.State.TIME_RESULT or _force_result():
		if not _force_result():
			fill(0, 0, SCREEN.x, SCREEN.y, psx(TIME_ATTACK_CLEAR))
		for part: Array in [[0, 0, 0x80, 0x100, 0x200, 0], [0x80, 0, 0x80, 0x100, 0x240, 0],
				[0x100, 0, 0x70, 0x100, 0x280, 0], [0, 0x100, 0x80, 0xE0, 0x200, 0x100],
				[0x80, 0x100, 0x80, 0xE0, 0x240, 0x100], [0x100, 0x100, 0x70, 0xE0, 0x280, 0x100]]:
			picture(part[0] as int, part[1] as int, part[2] as int, part[3] as int, part[4] as int, part[5] as int, 0x7FE0, 0x80)
	else:
		backdrop(0, TEAM_BACKDROP if _team() else SURVIVAL_BACKDROP)
		# The banner's text is in the background slot (%p 0): under the subtracted band.
		var y := ram.s32(ResultScreens.BANNER_BASE + 4) - 0x344
		while y < 0x170:
			ptext(0x800B9854, [0, 6, 2, y, 0xCB, ram.string(BANNER)])
			y += 0x344


func _rows_shift() -> int:
	return 5 - (ram.u8(MODE + 0x65) + ram.u8(MODE + 0x72) + 1) / 3


## The subtracted parts: the banner's band, time attack's row shading.
func _subtracted() -> void:
	if flow == null or _force_result():
		return
	if _screen == GameFlow.State.TIME_RESULT:
		_time_rows(true)
	else:
		fill(0, 0xCB, SCREEN.x, 0x2A, psx(0x606060))


## FUN_800F18FC's stripes, then the members and the fight grid's boxes.
func _middle() -> void:
	if flow == null or _screen == GameFlow.State.TIME_RESULT:
		return
	if _force_result():
		_force_portrait()
		return
	var x := ram.s32(ResultScreens.BANNER_BASE) - 0x180
	for k in 7:
		var w := ram.u32(BANNER_TILES + 4 * k)
		var xx := x
		while xx < 0x170:
			if xx > -0x30:
				ft4(xx, 0x5F, 0x30, 0x50, w & 0xFF, (w >> 8) & 0xFF, 0x18, 0x28, w >> 16, 0x6E, modulation(psx(0x606060)))
			xx += 0x180
		x += 0x30
	if _team():
		_team_grid()
		_team_members(MODE + 0x66, ram.u32(S + ResultScreens.T_LOST2), 0x28, _rows_shift() * 0x1E + 0xC0, true)
		_team_members(MODE + 0x59, ram.u32(S + ResultScreens.T_LOST1), 0x28, 100, false)


## FUN_800EE100's colour bars (additive).
func _added() -> void:
	if flow == null or not _team():
		return
	for k in 2:
		var e := _label(k)
		var shift := _rows_shift() * 0x1E if k == 1 else 0
		var top := ram.u16(e + 0xE) + shift
		var bottom := ram.u16(e + 0x14) + shift
		var left := ram.u16(e + 0xC)
		var mid := ram.u16(e + 0x10)
		var right := ram.u16(e + 0x12)
		var edge := psx(ram.u32(e + 0x18))
		var middle := psx(ram.u32(e + 0x1C))
		var end := psx(ram.u32(e + 0x20))
		gradient(left, top, mid - left, bottom - top, edge, middle, edge, middle)
		gradient(mid, top, right - mid, bottom - top, middle, end, middle, end)


func _label(k: int) -> int:
	var j := k + 2 if ram.u8(MODE + 0x1C) == 1 and k == ram.u8(MODE + 0x1F) else k
	return TEAM_LABELS + 0x24 * j


## The text slot: drawn last-linked first.
func _front() -> void:
	if flow == null:
		return
	match _screen:
		GameFlow.State.TEAM_RESULT:
			_team_grid_texts()
			_team_lines()
			for k in 2:
				var e := _label(k)
				var shift := _rows_shift() * 0x1E if k == 1 else 0
				print_fmt("%c%f%H%V" + ram.string(ram.u32(e)), [ram.u32(e + 8), 1, ram.u16(e + 4), ram.u16(e + 6) + shift, 1])
			_team_message()
			ptext(STR_TEAM_TITLE, [6, 1, 0x43, 0x1C])
		GameFlow.State.TIME_RESULT:
			_time_rows(false)
			_your_time()
			ptext(STR_TA_TITLE, [6, 1, 0x43, 0x20])
		GameFlow.State.FORCE_RESULT:
			_force_texts()
		GameFlow.State.SURVIVAL_RESULT:
			_survivors()
			if ram.s32(S + ResultScreens.S_FLAG) > 1:
				_survival_wins(ram.s32(S + ResultScreens.S_TOTAL), 0x78, 0x160)
				ptext(STR_TOTAL, [6, 1, 0x54, 0x148])
				if ram.u32(S + ResultScreens.S_WAIT) == 0:
					_survival_rank(ram.s32(S + ResultScreens.S_RANK), 400)
			ptext(STR_SURV_TITLE, [6, 1, 0x56, 0x1C])


# ---- team battle ----------------------------------------------------------------------------

## FUN_800EE3C0: YOU WIN! / YOU LOSE! / DRAW GAME / PLAYER-n WINS!, sliding in.
func _team_message() -> void:
	if ram.u32(S + ResultScreens.T_MSG) == 0:
		return
	var left1 := ram.s32(S + ResultScreens.T_LEFT1)
	var left2 := ram.s32(S + ResultScreens.T_LEFT2)
	var msg := 0
	var way := -1
	if ram.u8(MODE + 0x1C) == 1:
		if left1 == left2:
			msg = 2
		else:
			var mine := ram.s32(S + ResultScreens.T_LEFT1 + 4 * ram.u8(MODE + 0x1F))
			var theirs := ram.s32(S + ResultScreens.T_LEFT1 + 4 * ram.u8(MODE + 0x1E))
			msg = (1 if mine < theirs else 0) ^ 1
		way = -1 if ram.u8(MODE + 0x1E) == 0 else 1
	elif left1 == left2:
		msg = 2
	elif left2 < left1:
		msg = 3
	else:
		msg = 4
		way = 1
	var s := ram.string(ram.u32(TEAM_MESSAGES + 8 * msg))
	var n := s.length()
	var slide := ram.s32(S + ResultScreens.T_SLIDE)
	var x := 0xB8 if slide == 0 else Fx.div_trunc(slide * 0x170, 0x1E) * way + 0xB8
	x -= (n * 0x16) >> 1
	var yo := _rows_shift() * 0xF
	if slide == 0:
		var col := 0xC0C0C0 if left1 == left2 else (0xFF if left2 < left1 else 0xC0FF)
		var c := psx(col)
		fill(x - 8, yo + 0x9C, n * 0x16 + 0x10, 0x2E, Color(c.r, c.g, c.b, 0.5))
	text(s, 2, ram.u32(TEAM_MESSAGES + 8 * msg + 4), x, yo + 0x9E)


## FUN_800EE694: a team's eight member slots (portrait, greyed when defeated, or an empty box).
func _team_members(names: int, lost: int, x: int, y: int, second: bool) -> void:
	var count := ram.u8(names + 0xC)
	var n := mini(count, 8)
	lost = Fx.w32(lost)
	for i in 8:
		var ch := mini(ram.u8(names + i), 0x58)
		var flags := 0
		if i < lost:
			flags = 0x60
		elif i == lost and i < n:
			flags = 1 if second else 2
		if i < count:
			portrait(x, y, ch, flags, frame_count)
		else:
			fill(x, y, 0x24, 0x40, psx(0x303030))
			gradient(x + 1, y + 2, 0x22, 0x3C, Color.BLACK, Color.BLACK, psx(0xC0C0C), psx(0xC0C0C))
		x += 0x24


## FUN_800F131C: a 16 × 29 face, with flag 0x40 the lost mark over it.
func _small_face(x: int, y: int, key: int, flags: int) -> void:
	if not flags & 0x80:
		_small_face_picture(x, y, key, flags)
	if flags & 0x40:
		ft4(x, y, 0xF, 0xF, 0, 0xE0, 0x1F, 0x1F, 0x7F1D, 0x1F)
		ft4(x, y + 0x10, 0xF, 0xF, 0x20, 0xE0, 0x1F, 0x1F, 0x7F1D, 0x1F)


func _small_face_picture(x: int, y: int, key: int, flags: int) -> void:
	var i := 0x17 if key == 0x59 else key >> 2
	var uvc := ram.u32(FACE_UV + 8 * i)
	var tp := ram.u16(FACE_UV + 8 * i + 4)
	if flags & 0x20:
		uvc = (uvc & 0xFFFF) | 0x7D500000
	var clut := uvc >> 16
	var u := uvc & 0xFF
	var v := (uvc >> 8) & 0xFF
	if i == 0x14:
		ft4(x, y, 0xF, 0xB, u, v, 0x1F, 0x17, clut, tp)
		ft4(x, y + 0xC, 0xF, 0xB, (u + 0x20) & 0xFF, v, 0x1F, 0x17, clut, tp)
		ft4(x, y + 0x18, 0xF, 4, (u + 0x40) & 0xFF, v, 0x1F, 9, clut, tp)
	elif i < 0x16:
		ft4(x, y, 0xF, 0x1C, u, v, 0x1F, 0x39, clut, tp)
	else:
		ft4(x, y, 0xF, 4, u, v, 0x1F, 9, clut, tp)
		ft4(x, y + 5, 0xF, 0xB, (u + 0x20) & 0xFF, v, 0x1F, 0x17, clut, tp)
		ft4(x, y + 0x11, 0xF, 0xB, (u + 0x40) & 0xFF, v, 0x1F, 0x17, clut, tp)


func _fights() -> int:
	return mini(Fx.w32(ram.u32(S + ResultScreens.T_FIGHT)), ram.u8(MODE + 0x58))


## FUN_800EE870: one box per fight (both faces, result colour), empty boxes after.
func _team_grid() -> void:
	var names := MODE + 0x59
	var limit := _fights()
	var a := 0
	var b := 0
	var shift := _rows_shift() * 0x1E
	var col := 0
	var f1 := 0
	var f2 := 0
	for i in maxi(limit, 0):
		var code := ram.u16(MODE + 0x38 + 2 * i)
		match code:
			1:
				col = 0xFF
				f1 = 2
				f2 = 0x60
			2:
				col = 0xC0FF
				f1 = 0x60
				f2 = 1
			3:
				col = 0xC0C0C0
				f1 = 0
				f2 = 0
		var ch1 := mini(ram.u8(names + a), 0x58)
		var ch2 := mini(ram.u8(names + b + 0xD), 0x58)
		if code == 2 or code == 3:
			a += 1
		if code == 1 or code == 3:
			b += 1
		var xo := (i % 3) * 0x60
		var yo := (i / 3) * 0x1E + shift
		_grid_box(xo, yo, col)
		_small_face(xo + 0x47, yo + 0x126, ch1, f1)
		_small_face(xo + 0x6F, yo + 0x126, ch2, f2)
	var j := maxi(limit, 0)
	while j < ram.u8(MODE + 0x65) + ram.u8(MODE + 0x72) - 1:
		var xo := (j % 3) * 0x60
		var yo := (j / 3) * 0x1E + shift
		_grid_box(xo, yo, 0x404040)
		fill(xo + 0x47, yo + 0x126, 0x10, 0x1D, psx(0x201010))
		fill(xo + 0x6F, yo + 0x126, 0x10, 0x1D, psx(0x201010))
		j += 1


func _grid_box(xo: int, y: int, col: int) -> void:
	fill(xo + 0x28, y + 0x126, 0x5F, 0x1D, Color.BLACK)
	gradient(xo + 0x28, y + 0x135, 0x5F, 0xE, Color.BLACK, Color.BLACK, psx(col), psx(col))


func _team_grid_texts() -> void:
	var limit := maxi(_fights(), 0)
	var shift := _rows_shift() * 0x1E
	var total := ram.u8(MODE + 0x65) + ram.u8(MODE + 0x72) - 1
	for i in maxi(limit, total):
		var xo := (i % 3) * 0x60
		var yo := (i / 3) * 0x1E
		ptext(STR_VS_ROW, [6 if i < limit else 0x1A, 0, xo + 0x2C, shift + yo + 0x132, i + 1])


## FUN_800EF0D8: the lines joining the members of each fight (the current one grows).
func _team_lines() -> void:
	var fight := _fights()
	var shift := _rows_shift() * 0x1E
	for k in range(fight - 1, -1, -1):
		var a := ram.s32(S + ResultScreens.T_MEMBER1 + 4 * k)
		var b := ram.s32(S + ResultScreens.T_MEMBER2 + 4 * k)
		var code := ram.s16(MODE + 0x38 + 2 * k)
		var col := 0xF8 if code == 1 else (0xE0F8 if code == 2 else 0xE0E0E0)
		_line4(a * 0x24 + 0x39, 0xA4, b * 0x24 + 0x39, shift + 0xC0, col)
	var anim := ram.s32(S + ResultScreens.T_LINE)
	if anim == 0:
		return
	var x1 := ram.s32(S + ResultScreens.T_MEMBER1 + 4 * fight) * 0x24 + 0x39
	var x2 := ram.s32(S + ResultScreens.T_MEMBER2 + 4 * fight) * 0x24 + 0x39
	var y1 := 0xA4
	var y2 := shift + 0xC0
	var t := mini(anim, 8)
	var colour := 0
	match ram.u16(MODE + 0x38 + 2 * fight):
		1:
			x2 = x1 + (((x2 - x1) * t) >> 3)
			colour = 0xF8
			y2 = (((shift + 0x1C) * t) >> 3) + 0xA4
		2:
			x1 = x2 + (((x1 - x2) * t) >> 3)
			colour = 0xE0F8
			y1 = y2 + (((0xA4 - y2) * t) >> 3)
		3:
			var mid := ((x2 - x1) >> 1) + x1
			x1 = mid + (((x1 - mid) * t) >> 3)
			x2 = mid + (((x2 - mid) * t) >> 3)
			var ym := ((shift + 0x1C) >> 1) + 0xA4
			y1 = ym + (((0xA4 - ym) * t) >> 3)
			colour = 0xE0E0E0
			y2 = ym + (((y2 - ym) * t) >> 3)
	_line4(x1, y1, x2, y2, colour)


## A three-pixel-wide slanted band (POLY_F4 from (x1, y1) to (x2, y2)).
func _line4(x1: int, y1: int, x2: int, y2: int, col: int) -> void:
	var c := psx(col)
	quad(Vector2(x1, y1), Vector2(x1 + 3, y1), Vector2(x2, y2), Vector2(x2 + 3, y2), c, c, c, c)


# ---- time attack ----------------------------------------------------------------------------

func _stage_time(k: int, last: int) -> int:
	return ram.u32(MODE + 0x40 + 8 * k) if k < 10 else last


## The stage rows (the one being added grows): `shading` draws their subtracted gradients.
func _time_rows(shading: bool) -> void:
	var rows := ram.s32(S + ResultScreens.A_ROWS)
	var anim := ram.s32(S + ResultScreens.A_ROW_ANIM)
	var last := 0
	for k in maxi(rows, 0):
		last = _stage_time(k, last)
		_stage_row(k, last, (ram.u8(LADDER + 4 * k) << 2) | ram.u8(LADDER + 4 * k + 1), 0x40, shading)
	if anim != 0:
		var k := maxi(rows, 0)
		last = _stage_time(k, last)
		var t := Fx.w32(last * anim)
		if t < 0:
			t += 0xF
		_stage_row(k, (t >> 4) & 0xFFFFFFFF, (ram.u8(LADDER + 4 * k) << 2) | ram.u8(LADDER + 4 * k + 1), 0, shading)


## FUN_800EFA9C: STAGE n, the stage time and the opponent's face.
func _stage_row(stage: int, frames: int, key: int, flags: int, shading: bool) -> void:
	var x := ram.s16(TA_ROW_POS + 4 * stage)
	var y := ram.s16(TA_ROW_POS + 4 * stage + 2)
	if shading:
		gradient(x + 0xD, y + 0x18, 0x80, 0x28, psx(0xDEDEDE), Color.BLACK, psx(0xDEDEDE), Color.BLACK)
		return
	_small_face(x + 0xF, y + 0x1E, key, flags)
	frames = mini(Fx.w32(frames), TIME_CAP)
	ptext(STR_TIME, [6, 1, y + 0x24, x + 0x22, frames / 60 / 60, x + 0x42, (frames / 60) % 60, x + 0x66, (frames % 60) * 100 / 60])
	ptext(STR_TICKS, [6, 1, y + 0x20, x + 0x39, x + 0x5C])
	ptext(STR_STAGE_1X if stage + 1 < 10 else STR_STAGE_2D, [6, 0, x + 0x22, y + 0x10, stage + 1])


## FUN_800EFD14: YOUR TIME, the total and the player's face; NEW RECORD blinks.
func _your_time() -> void:
	if ram.u32(S + ResultScreens.A_SHOW) == 0:
		return
	if ram.u32(S + ResultScreens.A_WAIT) == 0 and ram.u32(S + ResultScreens.A_RECORD) != 0:
		ptext(STR_NEW_RECORD, [5 if frame_count & 3 else 6, 1, 0x62, 0x1A8])
	portrait(0x121, 0x170, ram.u32(S + ResultScreens.A_KEY), 0, frame_count)
	var t := mini(ram.s32(S + ResultScreens.A_TOTAL), TIME_CAP)
	ptext(STR_TOTAL_TIME, [7, 2, 0x5E, 0x17C, t / 60 / 60, 0x97, (t / 60) % 60, 0xD7, (t % 60) * 100 / 60])
	ptext(STR_TOTAL_TICKS, [7, 2, 0x80, 0x17C, 0xBD, 200])
	ptext(STR_YOUR_TIME, [2, 1, 0x25, 0x160])


# ---- survival -------------------------------------------------------------------------------

## FUN_800F0858: each beaten character's portrait and win count.
func _survivors() -> void:
	var rows := ram.s32(S + ResultScreens.S_ROW)
	for i in maxi(rows, 0):
		var ch := ram.u8(S + ResultScreens.S_CHARS + i)
		var wins := ram.u32(S + ResultScreens.S_ANIM) if i >= rows - 1 else ram.u16(MODE + 0x60 + 2 * ch)
		var x := ram.s16(SURVIVOR_POS + 4 * i)
		var y := ram.s16(SURVIVOR_POS + 4 * i + 2)
		portrait(x + 2, y + 2, ch << 2, 0x40, frame_count)
		if ram.u32(S + ResultScreens.S_FLAG) != 0:
			# The full count (bug #28 not reproduced: the game prints it modulo 100 and shows the
			# hundreds only by the digits' colour).
			wins = Fx.w32(wins)
			var shown := str(wins)
			text(shown.lpad(2), 0, ram.u8(SURVIVOR_COLOURS), x + 0x14 - 9 * maxi(shown.length() - 2, 0), y + 0x44)


## FUN_800F04C4: the total and WIN / WINS.
func _survival_wins(wins: int, x: int, y: int) -> void:
	var value := mini(wins, 99_999_999)
	text(str(value).lpad(3), 2, 0, x + 0x1A, y)
	ptext(STR_WIN if wins < 2 else STR_WINS, [6, 1, x + 0x60, y + 0xE])


## FUN_800F068C: YOU ARE THE nth / GREATEST SURVIVOR!, or YOU NEED MORE PRACTICE!
func _survival_rank(rank: int, y: int) -> void:
	if rank == 0:
		text(ram.string(STR_PRACTICE), 1, 5 if frame_count & 0x10 else 2, 0x22, y + 0x1A)
		return
	var suffix := mini(rank, 4)
	if rank > 100:
		rank = 99
	var tens := rank / 10
	var line := ram.string(STR_YOU_ARE).replace("%c", "")
	var number := (" " if tens == 0 else str(tens)) + str(rank - tens * 10)
	# "YOU ARE THE%c" then the number and ordinal in the blinking colour.
	text(line, 1, 5, 0x56, y)
	text(number + ram.string(ram.u32(ORDINALS + 4 * suffix)), 1, 6 if frame_count & 2 else 2,
		0x56 + line.length() * 0xD, y)
	text(ram.string(STR_GREATEST), 1, 5, 0x43, y + 0x1C)


# ---- Tekken Force -------------------------------------------------------------------------------

## FUN_800F1C00 at (0x10, 100): the player's big picture (mirrored when it faces left) under a
## gradient from its tint, framed.
func _force_portrait() -> void:
	var gl := flow.globals
	var side := flow.region.ctx8(ResultScreens.FORCE_PLAYER) & 1
	var word := flow.data.attribute(gl.player_char[side], gl.player_costume[side])
	var picture := word & 0x1F
	var x := 0x12
	var y := 100 + 6
	if picture < _portraits.size():
		var dest := r(x, y, 0x7E, 0xD4)
		if ram.u8(S + ResultScreens.F_FLIP) != 0:
			# A negative size flips the picture in place.
			dest.size.x = -dest.size.x
		target.draw_texture_rect_region(_portraits[picture], dest, Rect2(0, 0x14, 0x7E, 0xD4))
	var tint := psx(ram.u32(S + ResultScreens.F_COLOUR))
	gradient(x, y, 0x7E, 0x6A, Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(tint, 0.35), Color(tint, 0.35))
	gradient(x, y + 0x6A, 0x7E, 0x6A, Color(tint, 0.35), Color(tint, 0.35), Color(0.75, 0.75, 0.75, 0.35), Color(0.75, 0.75, 0.75, 0.35))
	for e: Array in [[x - 2, y - 2, 0x82, 2], [x - 2, y + 0xD4, 0x82, 2], [x - 2, y, 2, 0xD4], [x + 0x7E, y, 2, 0xD4]]:
		fill(e[0] as int, e[1] as int, e[2] as int, e[3] as int, psx(0xF0F0F0))


## FUN_800F1F08's texts, each appearing by the frames shown (with the sounds the step plays).
func _force_texts() -> void:
	var region := flow.region
	var shown := ram.s32(S + ResultScreens.F_SHOWN)
	var frame := ram.s32(S + ResultScreens.F_FRAME)
	print_fmt("%c%f%H%VTEKKEN FORCE", [0, 2, 0x34, 0x1C])
	var y := 0x78
	if shown > 0x1D:
		print_fmt("%f%c%H%VYOUR SCORE:", [1, 5, 0x9E, 0x78])
		y = 0xC6
		print_fmt("%f%c%H%V%8D", [1, 6, 0xF9, 0x92, region.ctx32(ResultScreens.FORCE_SCORE)])
	if shown > 0x3B:
		print_fmt("%f%c%H%VHIGH SCORE:", [1, 5, 0x9E, y])
		print_fmt("%f%c%H%V%8D", [1, 6, 0xF9, y + 0x1A, flow.progress.force_hi_score])
		y += 0x34
		if region.ctx8(0x3F) != 0:
			print_fmt("%f%c%H%VNEW RECORD!!", [1, 6 if frame & 2 else 2, 0xC5, y])
	var flags := region.ctx8(ResultScreens.FORCE_FLAGS)
	if flags & ResultScreens.FORCE_BOSSES == 0:
		if flags & ResultScreens.FORCE_DOCTOR != 0:
			if shown > 0x59:
				print_fmt("%f%c%H%VYOU SAVED %cDR.BOSKONOVITCH!", [1, 8, 0xF, y + 0xB6, 6 if frame & 2 else 2])
			return
		if shown > 0x59:
			print_fmt("%f%c%H%VKEYS:", [1, 5, 0x9E, y + 0x4E])
		for k in 3:
			if flags & (1 << k) != 0 and shown > FORCE_KEY_AFTER[k]:
				print_fmt("%f%c%H%V" + FORCE_KEYS[k], [1, FORCE_KEY_COLOURS[k], 0xDF, y + 0x4E + 0x1A * k])
		if shown >= 0xB4 and shown & 0x30 != 0:
			print_fmt("%f%c%H%VTO BE CONTINUED...", [1, 8, 0x43, y + 0xB6])
		return
	var bosses := ram.s32(S + ResultScreens.F_BOSS)
	if shown > 0x59:
		print_fmt("%f%c%H%VBOSS:", [1, 5, 0x27, y + 0x68])
	for k in 4:
		if (k == 0 and shown > 0x59) or (k > 0 and bosses > FORCE_BOSS_AFTER[k]):
			portrait(0x34 + 0x24 * k, y + 0x82, region.ctx8(0x41 + k), 0, frame)
	if ram.s32(S + ResultScreens.F_PHASE) >= 1:
		print_fmt("%f%c%H%VFORCE:", [1, 5, 0xDF, y + 0x68])
		print_fmt("%f%c%H%V%4D", [1, 6, 0x12D, y + 0x82, ram.s32(S + ResultScreens.F_FORCE)])
