class_name StaffRoll
extends RefCounted
## The staff roll after an arcade ending (ending.ovl FUN_80112798; modes.md#arcade-ending-and-
## staff-roll), written from the verified port `tools/research/screens_sim.py` (staff_roll) and the
## decompiled overlay (its sound and music). Each frame lists the lines to draw (`lines`) with
## their brightness and glow, and the Namco logo's brightness in the last phase.

## The roll's phases: the start sound, the music's delay and loading, the titles, the scrolling
## rows, the wait after them and the logo.
enum Phase { WAIT, MUSIC_DELAY, MUSIC_LOAD, TITLE_DELAY, TITLES, SCROLL, END_WAIT, LOGO }

const SOUND_START := 0xC7C0
const START_DELAY_FRAMES := 30       ## phase frame counts
const MUSIC_DELAY_FRAMES := 240
const TITLE_DELAY_FRAMES := 60
const TITLES_FRAMES := 239
const END_WAIT_FRAMES := 9060
const MUSIC_ROLL := 4
const SKIP_BUTTONS := PadState.CONFIRM
const ROW_HEIGHT := 0x12
const SCREEN_HEIGHT := 0x1E0
const CENTRE := 0x98
const TITLE_Y := 0xDC
const END_HOLD := 0x26C
const END_FADE := 0x50
const LOGO_FRAMES := 0xB3
const FULL_GLOW := Vector3i(0xFD, 0xDB, 0xB6)
const BASE_RGB := Vector3i(-3, -0x25, -0x4A)

## A line drawn this frame: its text, left x, y, font (true: the heading font), brightness and,
## when it glows, the glow's colour offsets.
class Line:
	extends RefCounted
	var text := ""
	var x := 0
	var y := 0
	var wide := false
	var bright := 0
	var glow := false
	var rgb := Vector3i.ZERO
	var width := 0                   ## the placed text's width (the glow's extent)


var data: FlowData
var phase := Phase.WAIT              ## 0x80194620
var clock := 0                       ## 0x8011E5F0
var skip := 0                        ## 0x8011E5F4 (kept from the overlay's load)
var end := 0                         ## 0x8011E5F8: 1 the list's end is on screen, 2 and 3 fading, 4 done
var offset := 0                      ## 0x80194618: the first row's y
var first := 0                       ## 0x8019461C: the first row shown
var indent := 0x20                   ## 0x8019463C
var half := 0                        ## 0x80194644: alternate frames rise 1 and 2 pixels
var bright := 0                      ## 0x80194648 (u8)
var base_bright := 0x78              ## 0x80194624
var rgb := BASE_RGB                  ## 0x80194626: the glow's colour offsets (s8)
var ramp := 0                        ## 0x80194658
var hold := 0                        ## 0x80194660
var fade := 0                        ## 0x8019465C
var kind := 0                        ## the last row kind read (the caller's $s3 in the game)
var lines: Array[Line] = []
var logo_bright := -1                ## Phase.LOGO: the logo's brightness, −1 not shown
var _x0 := 0
var _y := 0
var _width := 0
var _ball_new := 0                   ## Tekken Ball is unlocked: its heading replaces another
var _anna_start := 0                 ## Anna's Start costume is unlocked: one more name


func _init(flow_data: FlowData) -> void:
	data = flow_data


## A new roll (the overlay just loaded): the skip and end flags start clear.
func reset() -> void:
	skip = 0
	end = 0


## FUN_80112798(1): the set-up; returns the skip flag.
func start() -> int:
	phase = Phase.WAIT
	offset = SCREEN_HEIGHT
	first = 0
	indent = 0x20
	half = 0
	clock = 0
	hold = 0
	fade = 0
	base_bright = 0x78
	rgb = BASE_RGB
	clock += 1
	return skip


## FUN_80112798(0): one frame; true when the roll is over or skipped.
func step(g: GameFlow) -> bool:
	lines.clear()
	logo_bright = -1
	_ball_new = g.progress.ball_new
	_anna_start = (g.progress.start_costumes >> Character.ANNA) & 1
	if g.pressed_any() & SKIP_BUTTONS:
		skip = 1
	var c := clock
	match phase:
		Phase.WAIT:
			if c > START_DELAY_FRAMES:
				g.sound(SOUND_START)
				phase = Phase.MUSIC_DELAY
				clock = 0
		Phase.MUSIC_DELAY:
			if c == MUSIC_DELAY_FRAMES:
				g.music(MUSIC_ROLL)
				phase = Phase.MUSIC_LOAD
		Phase.MUSIC_LOAD:
			if g.music_ready():
				phase = Phase.TITLE_DELAY
				first = 0
				clock = 0
		Phase.TITLE_DELAY:
			if c == TITLE_DELAY_FRAMES:
				phase = Phase.TITLES
				clock = 0
		Phase.TITLES:
			_titles(c)
			if c == TITLES_FRAMES:
				phase = Phase.SCROLL
		Phase.SCROLL:
			if not _scroll():
				return false
		Phase.END_WAIT:
			if c == END_WAIT_FRAMES:
				clock = 0
				phase = Phase.LOGO
		Phase.LOGO:
			if c > LOGO_FRAMES:
				return true
			if c < 0xB:
				bright = (bright + 0xC) & 0xFF
			elif c > 0x78:
				bright = (bright - 2) & 0xFF
			logo_bright = bright
	half += 1
	if half == 2:
		half = 0
	clock += 1
	return skip != 0


## FUN_801144B0: a string's width in pixels.
func text_width(text: String, wide: bool) -> int:
	var table := data.staff_font_wide if wide else data.staff_font_narrow
	var space := 8 if wide else 10
	var w := 0
	for i in text.length():
		var ch := text.unicode_at(i)
		if ch < 0x31:
			w += space if ch == 0x20 else table[ch - 0x21]
		else:
			w += table[ch - 0x22]
	return w


func _place(text: String, wide: bool, y: int) -> void:
	var w := text_width(text, wide)
	_x0 = CENTRE - w / 2 + indent
	_y = y
	_width = w



func _line(text: String, wide: bool, glow: bool) -> void:
	var l := Line.new()
	l.text = text
	l.x = _x0
	l.y = _y
	l.wide = wide
	l.bright = bright
	l.glow = glow
	l.rgb = rgb
	l.width = _width
	lines.append(l)


func _glow_in(k: int) -> void:
	rgb = Vector3i(Fx.s8(-3 - Fx.s8(mini(k * 7, 0xFD))), Fx.s8(-0x25 - Fx.s8(mini(k * 6, 0xDB))),
		Fx.s8(-0x4A - Fx.s8(mini(k * 5, 0xB6))))


## Phase 4: the title block, glowing in and fading out.
func _titles(c: int) -> void:
	bright = 0x5A
	for i in data.staff_titles.size():
		var text := data.staff_titles[i]
		var wide := i == 0
		_place(text, wide, (0 if wide else ROW_HEIGHT) + TITLE_Y)
		var glow := false
		if c < 0x25:
			if c < 0x1E:
				var v := (((0x1B8 - _y) * 2) & 0xFF) | 1
				if v > 0x5A:
					v = 0x5A - ((v - 0x5A) >> 1)
					bright = v & 0xFF
					if v & 0xFF < 0x50:
						bright = 0x50
			_glow_in(c)
			glow = true
		elif c > 0xB4:
			bright = ((0xD2 - c) * 3 + 1) & 0xFF
			ramp = base_bright + (0xD2 - c) * -4
		if c < 0xD2:
			_line(text, wide, glow)


## A row's colour entering at the bottom (y 360–440).
func _ramp_near_bottom(y: int) -> void:
	var k := Fx.w32((0x1B8 - y) & 0xFFFFFFFF)
	ramp = k
	var v := ((k * 2) & 0xFF) | 1
	if v > 0x5A:
		v = (0x5A - ((v - 0x5A) >> 1)) & 0xFFFFFFFF
		bright = v & 0xFF
		if v & 0xFF < 0x50:
			bright = 0x50
	_glow_in(k)


## A row's colour leaving at the top (y 20–100).
func _ramp_near_top(y: int) -> void:
	var k := 100 - y
	ramp = k
	bright = (y - 0x13) & 0xFF
	rgb = Vector3i(Fx.s8(mini(Fx.div_trunc(k * 7, 2), 0xFD)), Fx.s8(mini(k * 3, 0xDB)), Fx.s8(mini(Fx.div_trunc(k * 5, 2), 0xB6)))


## The row's brightness by its place on the screen; true when it glows.
func _row_colour(y_row: int, y: int, bottom: int, top_lo: int, top_len: int) -> bool:
	if ((y_row - bottom) & 0xFFFFFFFF) < 0x50:
		_ramp_near_bottom(y)
		return true
	if ((y_row - top_lo) & 0xFFFFFFFF) < top_len:
		_ramp_near_top(y)
		return true
	if ((y_row - top_lo) & 0xFFFFFFFF) < 0x1A4:
		bright = 0x50
		return false
	bright = 1
	rgb = Vector3i(Fx.s8(FULL_GLOW.x), Fx.s8(FULL_GLOW.y), Fx.s8(FULL_GLOW.z))
	return true


## The end of the list: the hold (620 frames), the fade out and the glow out (80 each), counted
## once per frame (bug #27 not reproduced: the game counts once per heading row on screen).
## False when the roll is over (the phase changed).
func _end_tick() -> bool:
	if end == 2 and fade == END_FADE:
		end = 3
		fade = 0
	if end == 1:
		hold += 1
		if hold == END_HOLD:
			end = 2
			hold = 0
	if end > 1:
		fade += 1
		if end == 3 and fade == END_FADE:
			end = 4
			offset = 0
			phase = Phase.END_WAIT
			bright = 0
			return false
	return true


## Phase.SCROLL: the rows scroll up; false returns from the frame early (the phase changed).
func _scroll() -> bool:
	var rows := data.staff_rows
	if offset < -ROW_HEIGHT:
		first += 1
		offset += ROW_HEIGHT
		if first >= rows.size():
			offset = 0
			phase = Phase.END_WAIT
			bright = 0
			return false
	bright = 0x5A
	if end != 0 and not _end_tick():
		return false
	var row := first
	var y_row := offset
	while y_row < SCREEN_HEIGHT:
		var at_end := row >= rows.size()
		if at_end and end == 0:
			end = 1
			break
		var entry := "" if at_end else rows[row]
		if not at_end:
			match entry.unicode_at(0):
				0x30: kind = 0
				0x31: kind = 1
				0x32: kind = 2
				0x33: kind = 3 if _ball_new != 0 else -1
				0x34: kind = -1 if _ball_new != 0 else 0
				0x35: kind = 1 if _anna_start != 0 else -1
		# Rows are centred on their text without the leading kind digit (bug #32 not reproduced).
		var text := entry.substr(1)
		match kind:
			1:
				_place(text, false, y_row)
				_line(text, false, _row_colour(y_row, y_row, 0x168, 0x14, 0x50))
			0:
				_place(text, true, y_row + 4)
				var glow := false
				if end == 0:
					glow = _row_colour(y_row, y_row + 4, 0x164, 0x10, 0x50)
				elif end > 1:
					var k := fade
					if end == 2:
						bright = (END_FADE - k) & 0xFF
						ramp = k
						rgb = Vector3i(Fx.s8(mini(k * 7, 0xFD)), Fx.s8(mini(k * 6, 0xDB)), Fx.s8(mini(k * 5, 0xB6)))
						glow = true
					else:
						bright = 1
						ramp = k
						_glow_in(k)
						glow = true
				else:
					bright = 0x50
				_line(text, true, glow)
			3:
				_place(text, true, y_row + 0x14)
				_line(text, true, _row_colour(y_row, y_row + 0x14, 0x154, 0, 0x50))
		row += 1
		y_row += ROW_HEIGHT
	if end == 0:
		offset -= 1 if half == 0 else 2
	return true

