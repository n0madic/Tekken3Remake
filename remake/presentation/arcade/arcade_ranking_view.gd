class_name ArcadeRankingView
extends ArcadeCanvas
## The ranking's pages over the turning stage (FUN_801C241C's drawing): the title band fading out to
## the right, and the rows sliding up, cut below it; during a name entry the new row blinks on a blue
## band with a cursor under the letter and the time left.

const ROWS_TOP := 0x60
const ROWS_HEIGHT := 0x168              ## FUN_801C1F44's draw area
const ROWS_HEIGHT_ENTRY := 0x170        ## FUN_801C2314's
const ROW_SKIP := 0x228
const TIME_LIMIT := 359999
const FRAMES := 60
const PERCENT_FULL := 1000
const ROUNDS_NOT_SHOWN := 2
const WINS_LIMIT := 999
const ENTRY_BAND := Color(0, 0, 0x10 / 255.0, 0.5)
const ENTRY_BAND_TOP := 0x68
const ENTRY_CURSOR_X := 0x1A0
const ENTRY_CURSOR_LEFT := 2
const ENTRY_CURSOR_Y := 0xA0
const ENTRY_CURSOR := Vector2i(0x18, 4)
const ENTRY_CURSOR_COLOUR := Color.RED
const LETTER_STEP := 0x12
const BLINK := 3
const SUFFIX_LAST := 3
const RANK_LIMIT := 99

var flow: ArcadeGameFlow


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_arcade(hud_data, screens)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _rows_shown, Rect2(0, ROWS_TOP, LAYOUT.x, ROWS_HEIGHT))
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _rows_entered, Rect2(0, ROWS_TOP, LAYOUT.x, ROWS_HEIGHT_ENTRY))
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


func show_state(game: ArcadeGameFlow) -> void:
	flow = game
	frame_count = game.frame()
	redraw()


func _layer() -> int:
	return ArcadeRanking.Layer.NONE if flow == null else flow.ranking.layer


func _draw() -> void:
	begin()
	var layer := _layer()
	if layer == ArcadeRanking.Layer.NONE:
		black()
	elif layer == ArcadeRanking.Layer.ENTRY:
		fill(0, flow.ranking.entry_row * ArcadeRanking.ROW_HEIGHT + ENTRY_BAND_TOP, LAYOUT.x, ArcadeRanking.ROW_HEIGHT, ENTRY_BAND)


func _rows_shown() -> void:
	if _layer() == ArcadeRanking.Layer.ROWS:
		_rows(false)


func _rows_entered() -> void:
	var layer := _layer()
	if layer == ArcadeRanking.Layer.ENTRY or layer == ArcadeRanking.Layer.ENTERED:
		_rows(true)


## Every row but those out of reach.
func _rows(highlight: bool) -> void:
	var ranking := flow.ranking
	for i in ranking.row_count:
		var y := ranking.scroll + i * ArcadeRanking.ROW_HEIGHT
		if y < 0 or y >= ROW_SKIP:
			continue
		var style := 1 if highlight and ranking.new_row == i and frame_count & BLINK != 0 else 0
		match ranking.kind:
			ArcadeRanking.PAGE_TIME:
				_time_row(i, y, style)
			ArcadeRanking.PAGE_WINS:
				_wins_row(i, y, style)
			_:
				_usage_row(i, y)


func _cell(key: String) -> Vector2i:
	var cells: Dictionary = data.ranking["cells"]
	return ArcadeScreenData.point_of(cells[key])


func _colours(page: String, style: int) -> PackedInt32Array:
	var colours: Dictionary = data.ranking["colours"]
	var rows: Array = colours[page]
	var row: Array = rows[style]
	return PackedInt32Array(row)


## FUN_801C0A78: the place with its suffix.
func _rank(i: int, y: int, colour: int) -> void:
	var at := _cell("rank")
	var suffixes: Array = data.ranking["suffixes"]
	text("%d%s" % [mini(i + 1, RANK_LIMIT), str(suffixes[mini(i, SUFFIX_LAST)])], 1, colour, at.x, y + at.y)


## FUN_801C0B40, FUN_801C0AEC: the face and name of a character.
func _face_and_name(character: int, y: int, colour: int) -> void:
	var record := data.character(character * ArcadeScreenData.COSTUMES)
	var face := _cell("face")
	picture_at(str(record["face"]), face.x, y + face.y)
	var at := _cell("name")
	text(str(record["name"]), 0, colour, at.x, y + at.y)


## FUN_801C0DDC: the entered name.
func _entry(row: ArcadeProgress.Row, y: int, colour: int) -> void:
	var at := _cell("entry")
	text(row.name, 1, colour, at.x, y + at.y)


## FUN_801C1208.
func _divider(y: int) -> void:
	var dividers: Dictionary = data.ranking["dividers"]
	var colour := ArcadeScreenData.colour_of(dividers["colour"])
	var rects: Array = dividers["rects"]
	for piece: Array in rects:
		var x: int = piece[0]
		var dy: int = piece[1]
		var width: int = piece[2]
		var height: int = piece[3]
		fill(x, y + dy, width, height, colour)


## FUN_801C12B8: rank, face, name, time, the record's rounds and mark, name.
func _time_row(i: int, y: int, style: int) -> void:
	var colours := _colours("time", style)
	var character := flow.ranking.rows[i]
	var row: ArcadeProgress.Row = flow.progress.times[character]
	_rank(i, y, colours[0])
	_face_and_name(character, y, colours[1])
	var time := mini(row.value & ArcadeProgress.TIME_MASK, TIME_LIMIT)
	var at := _cell("time")
	var origin := Vector2i(at.x, y + at.y)
	show_text("rank_time_marks", [], origin, colours[2])
	show_text("rank_time_digits", [time / FRAMES / FRAMES, time / FRAMES % FRAMES, time % FRAMES * 100 / FRAMES], origin, colours[2])
	var rounds := row.value >> 28 & 7
	var mark := _cell("mark")
	var note := ""
	if rounds != ROUNDS_NOT_SHOWN:
		note += "%X" % rounds
	if row.value >> 31 & 1 != 0:
		note += "."
	if not note.is_empty():
		text(note, 0, colours[3], mark.x, y + mark.y)
	_entry(row, y, colours[4])
	_divider(y)


## FUN_801C13DC.
func _wins_row(i: int, y: int, style: int) -> void:
	var colours := _colours("wins", style)
	var row: ArcadeProgress.Row = flow.progress.wins[flow.ranking.rows[i]]
	_rank(i, y, colours[0])
	_face_and_name(row.value, y, colours[1])
	var at := _cell("time")
	var count := mini(row.count, WINS_LIMIT)
	var origin := Vector2i(at.x, y + at.y)
	if count < 2:
		show_text("rank_win_count", [count], origin, colours[2])
		show_text("rank_win", [], origin, colours[2])
	else:
		show_text("rank_wins_count", [count], origin, colours[2])
		show_text("rank_wins", [], origin, colours[2])
	_entry(row, y, colours[3])
	_divider(y)


## FUN_801C14D8: the share rising and its bar.
func _usage_row(i: int, y: int) -> void:
	var colours := _colours("usage", 0)
	var ranking := flow.ranking
	var character := ranking.rows[i]
	var rise := ranking.row_rise if i >= ranking.first_shown else 0
	var share := ranking.usage_share[character]
	var best := ranking.usage_share[ranking.rows[0]] if ranking.row_count > 0 else 0
	var shown := share * rise >> 6
	_rank(i, y, colours[0])
	_face_and_name(character, y, colours[1])
	var at := _cell("usage")
	var origin := Vector2i(at.x, y + at.y)
	shown = mini(shown, PERCENT_FULL)
	if shown == PERCENT_FULL:
		show_text("rank_usage_full", [], origin, colours[2])
	elif shown == 0:
		show_text("rank_usage_none", [], origin, colours[2])
	else:
		show_text("rank_usage", [shown / 10, shown % 10], origin, colours[2])
	if best != 0:
		_bar(character, (share * rise * PERCENT_FULL / best) >> 6, y + at.y)
	_divider(y)


## FUN_801C0FE8: a box of the character's colours growing left from its end.
func _bar(character: int, value: int, y: int) -> void:
	var bars: Dictionary = data.ranking["bars"]
	var max_width: int = bars["max_width"]
	var width := mini(value, PERCENT_FULL) * max_width / PERCENT_FULL
	if width == 0:
		return
	var right: int = bars["dx"]
	var height: int = bars["height"]
	var depth: int = bars["depth"]
	var colours: Array = bars["colours"]
	var set_of: Array = colours[character]
	var side := ArcadeScreenData.colour_of(set_of[0])
	var front_left := ArcadeScreenData.colour_of(set_of[1])
	var front_right := ArcadeScreenData.colour_of(set_of[2])
	var top_left := ArcadeScreenData.colour_of(set_of[3])
	var top_right := ArcadeScreenData.colour_of(set_of[4])
	var left := right - width
	gradient(left, y, width, height, front_left, front_right, front_left, front_right)
	quad(Vector2(left - depth, y - depth), Vector2(left, y), Vector2(left - depth, y - depth + height), Vector2(left, y + height), side, side, side, side)
	quad(Vector2(left - depth, y - depth), Vector2(right - depth, y - depth), Vector2(left, y), Vector2(right, y), top_left, top_right, top_left, top_right)


## The title band (FUN_801C1DCC) and the name entry's cursor and time left.
func _front() -> void:
	var layer := _layer()
	if layer == ArcadeRanking.Layer.NONE:
		return
	_band()
	var ranking := flow.ranking
	if layer == ArcadeRanking.Layer.ENTRY or layer == ArcadeRanking.Layer.ENTERED:
		show_text("rank_countdown", [(ranking.page_clock + 0x3B) / FRAMES])
	if layer == ArcadeRanking.Layer.ENTRY and ranking.entry.letter < ArcadeNameEntry.LETTERS:
		fill(ENTRY_CURSOR_X + ranking.entry.letter * LETTER_STEP - ENTRY_CURSOR_LEFT,
			ranking.entry_row * ArcadeRanking.ROW_HEIGHT + ENTRY_CURSOR_Y, ENTRY_CURSOR.x, ENTRY_CURSOR.y, ENTRY_CURSOR_COLOUR)


func _band() -> void:
	var band: Dictionary = data.ranking["band"]
	var titles: Array = data.ranking["titles"]
	var tex := data.texture(str(titles[flow.ranking.kind]))
	if tex == null:
		return
	var x: int = band["x"]
	var y: int = band["y"]
	var width: int = band["width"]
	var height: int = band["height"]
	var solid: int = band["solid"]
	var strip: int = band["strip"]
	var alpha: int = band["alpha"]
	var alpha_step: int = band["alpha_step"]
	target.draw_texture_rect_region(tex, r(x, y, solid, height), Rect2(0, 0, solid, height))
	var at := solid
	while at < width and alpha > 0:
		target.draw_texture_rect_region(tex, r(x + at, y, strip, height), Rect2(at, 0, strip, height), Color(1, 1, 1, alpha / 255.0))
		at += strip
		alpha += alpha_step
