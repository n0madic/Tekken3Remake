class_name ArcadeSelectView
extends ArcadeCanvas
## The arcade's character select (FUN_801C06E4's drawing), painted in the reverse of its calls, since
## they all link into one ordering-table slot: the scrolling tiles and the banner over black, the
## portraits' glow (added), the portraits by bands, the panel's gradient and frames, the faces, the
## name plates, the time limit and the cursors. The sparks rise between the portraits and the panel.

const CURSOR_PULSE := 0x1F
const CURSOR_STEP := 0x10
const CURSOR_WRAP := 0xFF
const CURSOR_TOP := 0x1FF
const CURSOR_LEFT := 2
const BAND_ROWS := 0x7E
const BAND_LINES := 2
const FULL_BAND := 0x20
const TILE_ROWS := 8
const TILES_END := 0x155
const NO_CHARACTER := Character.NONE

var flow: ArcadeGameFlow
var _bands: Array = []


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_arcade(hud_data, screens)
	_bands = data.select["bands"]
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _glows)
	add_pass(CanvasItemMaterial.BLEND_MODE_SUB, _silhouettes)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _portraits)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _sparks)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


func show_state(game: ArcadeGameFlow) -> void:
	flow = game
	frame_count = game.frame()
	redraw()


func _shown() -> bool:
	return flow != null and flow.sub >= 3 and flow.select.frame >= ArcadeSelect.DRAW_FROM


func _layout() -> Dictionary:
	var layouts: Array = data.select["layouts"]
	return layouts[flow.select.two_rows]


func _player(p: int) -> Dictionary:
	var players: Array = data.select["players"]
	return players[p]


func _attribute(p: int) -> Dictionary:
	var side: ArcadeSelectSide = flow.select.sides[p]
	return data.attribute(side.character, side.costume)


func _draw() -> void:
	begin()
	black()
	if _shown():
		_tiles()


## FUN_801C04D8: eight columns of tiles scrolling up with the frame, the banner, cut at the panel.
func _tiles() -> void:
	var layout := _layout()
	var limit: int = layout["panel_top"]
	var tiles: Dictionary = data.select["tiles"]
	var tile_size: int = tiles["size"]
	var scale_of: int = tiles["scroll_scale"]
	var shift: int = tiles["scroll_shift"]
	var files: Dictionary = tiles["files"]
	var rows: Array = tiles["rows"]
	var scrolled := (frame_count * scale_of) >> shift
	var row := 7 - ((scrolled - 1) >> 6)
	var y := -((tile_size - scrolled) & (tile_size - 1))
	while y < TILES_END:
		var cells: Array = rows[row & (TILE_ROWS - 1)]
		for column in cells.size():
			var file: Variant = files.get(str(cells[column]))
			if file != null:
				picture_clipped(data.texture(str(file)), column * tile_size, y, 0, limit)
		y += tile_size
		row += 1
	var banner: Dictionary = data.select["banner"]
	var x: int = banner["x"]
	var top: int = banner["y"]
	picture_at(str(banner["file"]), x, top)


## FUN_801BFE58: behind each portrait, black to the attribute's colour to grey (added).
func _glows() -> void:
	if not _shown():
		return
	var glow: Dictionary = data.select["glow"]
	var width: int = glow["width"]
	var top: int = glow["top"]
	var middle: int = glow["middle"]
	var bottom: int = glow["bottom"]
	var end := ArcadeScreenData.colour_of(glow["end_colour"])
	var y: int = _layout()["portrait_y"]
	for p in 2:
		var x: int = _player(p)["portrait_x"]
		var c := ArcadeScreenData.colour_of(_attribute(p)["colour"])
		gradient(x, y + top, width, middle - top, Color.BLACK, Color.BLACK, c, c)
		gradient(x, y + middle, width, bottom - middle, c, c, end, end)


func _flipped(p: int) -> bool:
	var side: ArcadeSelectSide = flow.select.sides[p]
	if side.character == NO_CHARACTER:
		return false
	var facing: int = _attribute(p)["facing"]
	return (facing != 0) != (p == 1)


## FUN_801BFA7C: a portrait by bands of two lines, each at its brightness; the white figure of an
## empty side is only subtracted.
func _portrait(p: int, silhouettes: bool) -> void:
	var attribute := _attribute(p)
	var silhouette: bool = attribute["silhouette"]
	if silhouette != silhouettes:
		return
	var tex := data.texture(str(attribute["portrait"]))
	if tex == null:
		return
	var band_index: int = attribute["band"]
	var band: Array = _bands[band_index]
	var side: ArcadeSelectSide = flow.select.sides[p]
	var fade := FULL_BAND - side.chosen_anim
	var x: int = _player(p)["portrait_x"]
	var y: int = _layout()["portrait_y"]
	var width: int = data.select["portrait_width"]
	var flip := _flipped(p)
	var at := 0
	while at < BAND_ROWS:
		var value: int = band[at]
		var run := 1
		while at + run < BAND_ROWS and JsonFile.number(band[at + run]) == value:
			run += 1
		var level := (value * fade >> 5) / float(FULL_BAND)
		var tint := Color(level, level, level, 1.0) if silhouette else Color(1, 1, 1, level)
		var dest := r(x, y + at * BAND_LINES, width, run * BAND_LINES)
		if flip:
			dest.size.x = -dest.size.x
		target.draw_texture_rect_region(tex, dest, Rect2(0, at * BAND_LINES, width, run * BAND_LINES), tint)
		at += run


func _silhouettes() -> void:
	if not _shown():
		return
	for p in 2:
		_portrait(p, true)


func _portraits() -> void:
	if not _shown():
		return
	for p in 2:
		_portrait(p, false)


## FUN_801BF6B4: a line one pixel wide, its top grey and its end blue, cut at the panel (FUN_801BF990).
func _sparks() -> void:
	if not _shown():
		return
	var limit: int = _layout()["panel_top"]
	for spark: SelectSparks.Spark in flow.select.sparks.sparks:
		if spark.active == 0:
			continue
		var height := mini(SelectSparks.LENGTH, limit - spark.y)
		if height <= 0:
			continue
		var level := float(spark.brightness & SelectSparks.LEVEL_MASK) / SelectSparks.LEVEL_MASK
		var top := Color(level, level, level)
		var end := top.lerp(Color(0, 0, level), float(height) / SelectSparks.LENGTH)
		gradient(spark.x, spark.y, SelectSparks.WIDTH, height, top, top, end, end)


func _front() -> void:
	if not _shown():
		return
	_panel()
	_faces()
	_timer()
	for p in 2:
		_plate(p)
	for p in 2:
		_cursor(p)


## FUN_801C0398: the gradient under the frame pictures.
func _panel() -> void:
	var layout := _layout()
	var grade: Dictionary = layout["gradient"]
	var top: int = grade["top"]
	var bottom: int = grade["bottom"]
	var above := ArcadeScreenData.colour_of(grade["top_colour"])
	var below := ArcadeScreenData.colour_of(grade["bottom_colour"])
	gradient(0, top, LAYOUT.x, bottom - top, above, above, below, below)
	var frames: Array = layout["frames"]
	for piece: Dictionary in frames:
		var x: int = piece["x"]
		var y: int = piece["y"]
		var width: int = piece["width"]
		var height: int = piece["height"]
		image(data.texture(str(piece["file"])), x, y, width, height)


func _cell(row: int, cell: int) -> Vector2i:
	var parities: Array = data.select["cells"]
	var by_row: Array = parities[flow.select.count & 1]
	var cells: Array = by_row[row]
	return ArcadeScreenData.point_of(cells[cell])


## FUN_801BFFC0.
func _faces() -> void:
	var layout := _layout()
	var faces_y: int = layout["faces_y"]
	var faces: Dictionary = layout["faces"]
	for row in 2:
		for cell in ArcadeSelect.ROW_CELLS:
			var character := flow.select.grid[row * ArcadeSelect.ROW_CELLS + cell]
			if character >= NO_CHARACTER:
				continue
			var file: Variant = faces.get(str(character))
			if file != null:
				var at := _cell(row, cell)
				picture_at(str(file), at.x, at.y + faces_y)


## FUN_801BF4B4: the seconds left.
func _timer() -> void:
	var select := flow.select
	if select.time_step == 0:
		return
	var seconds := (select.time + select.time_step - 1) / select.time_step
	var timer: Dictionary = data.select["timer"]
	var x: int = timer["x"]
	var tens_x: int = timer["tens_x"]
	var layout := _layout()
	var y: int = layout["timer_y"]
	var digits: Array = layout["digits"]
	picture_at(str(digits[seconds % 10]), x, y)
	picture_at(str(digits[seconds / 10 % 10]), tens_x, y)


## FUN_801BF520: the side's prompt and name plate by its state.
func _plate(p: int) -> void:
	var side: ArcadeSelectSide = flow.select.sides[p]
	if side.anim_b == 2:
		var prompt: Dictionary = data.select["prompt"]
		var x: int = prompt["x"]
		var step: int = prompt["step"]
		var y: int = prompt["y"]
		var colour: int = _layout()["prompt_colour"]
		side_prompt(p, x + p * step, y, colour)
	if side.anim_b != 1 and side.anim_b != 2:
		return
	if side.character >= NO_CHARACTER:
		return
	var record := data.character(side.character * ArcadeScreenData.COSTUMES + side.costume)
	var entry: Variant = record["plate"]
	if entry == null:
		return
	var plates: Dictionary = data.select["plates"]
	var file: Variant = plates.get(str(JsonFile.number(entry)))
	if file == null:
		return
	var width: int = record["plate_width"]
	var centre: int = _player(p)["plate_centre_x"]
	var plate_y: int = _layout()["plate_y"]
	picture_at(str(file), centre - width / 2, plate_y)


## FUN_801C0124: the cursor and its tag; pulsing while the side chooses.
func _cursor(p: int) -> void:
	var side: ArcadeSelectSide = flow.select.sides[p]
	var brightness := NEUTRAL
	match side.anim_a:
		0:
			return
		1, 3:
			brightness = (frame_count & CURSOR_PULSE) * CURSOR_STEP
			if brightness > CURSOR_WRAP:
				brightness = CURSOR_TOP - brightness
	var layout := _layout()
	var faces_y: int = layout["faces_y"]
	var cursor_y: int = layout["cursor_y"]
	var tag_y: int = layout["tag_y"]
	var cursors: Array = layout["cursors"]
	var at := _cell(side.row, side.cell)
	var level := brightness / float(NEUTRAL)
	var tint := Color(level, level, level, 1.0)
	var x := at.x - CURSOR_LEFT
	var y := at.y + faces_y
	picture_at(str(cursors[p]), x, y + cursor_y, tint)
	var tag: Dictionary = _player(p)["tag"]
	var dx: int = tag["dx"]
	picture_at(str(tag["file"]), x + dx, y + tag_y, tint)
