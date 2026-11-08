class_name ArcadeVsView
extends ArcadeCanvas
## The VS screen (FUN_801B8880): the kind's background stretched over the screen, each side's framed
## portrait over its glow, sliding in, the names and the texts. The sides' numbers are their record
## by kind (FUN_801B8388, FUN_801B860C): with the two fighters records 0 and 1, COMING SOON! and WHO
## IS IT? one figure with records 2 and 3, the latter a black shape without its name.

const KIND_ONE_HUMAN := 0
const KIND_TWO := 1
const KIND_COMING_SOON := 2
const KIND_WHO_IS_IT := 3

var flow: ArcadeGameFlow


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_arcade(hud_data, screens)
	add_pass(CanvasItemMaterial.BLEND_MODE_ADD, _glows)
	add_pass(CanvasItemMaterial.BLEND_MODE_MIX, _front)


func show_state(game: ArcadeGameFlow) -> void:
	flow = game
	frame_count = game.frame()
	redraw()


func _shown() -> bool:
	if flow == null:
		return false
	var matching := flow.match_flow
	if flow.sub != ArcadeMatchFlow.Sub.VS:
		return matching.vs_step != 0 and flow.sub >= ArcadeMatchFlow.Sub.LOAD and flow.sub <= ArcadeMatchFlow.Sub.ROUND
	return matching.vs_step > 3 or (matching.vs_step == 3 and matching.vs_slide < ArcadeMatchFlow.VS_SLIDE_FRAMES)


func _draw() -> void:
	begin()
	black()
	if not _shown():
		return
	var kind := flow.match_flow.vs_kind
	var backgrounds: Array = data.vs["backgrounds"]
	var area: Array = data.vs["background_size"]
	var width: int = area[0]
	var height: int = area[1]
	image(data.texture(str(backgrounds[kind])), 0, 0, width, height)


func _sides() -> int:
	return 2 if flow.match_flow.vs_kind < KIND_COMING_SOON else 1


## FUN_801B8518's placing: the record's rest position and the part of its way still to slide.
func _at(records: Array, record: int) -> Vector2i:
	var place: Array = records[record]
	var x: int = place[0]
	var y: int = place[1]
	var dx: int = place[2]
	var dy: int = place[3]
	var slide := flow.match_flow.vs_slide
	return Vector2i(x + (slide * dx >> 3), y + (slide * dy >> 3))


func _record(side: int) -> int:
	var kind := flow.match_flow.vs_kind
	return side if kind < KIND_COMING_SOON else kind


func _attribute(side: int) -> Dictionary:
	var key := flow.match_flow.vs_shown_key[side]
	return data.attribute(key >> 2, key & 3)


## FUN_801B8088's gradients (added): behind the portrait.
func _glows() -> void:
	if not _shown():
		return
	var grade: Dictionary = data.vs["gradient"]
	var top: int = grade["top"]
	var middle: int = grade["middle"]
	var bottom: int = grade["bottom"]
	var end := ArcadeScreenData.colour_of(grade["end_colour"])
	var portrait: Dictionary = data.vs["portrait"]
	var dx: int = portrait["x"]
	var width: int = portrait["width"]
	var positions: Array = data.vs["positions"]
	for side in _sides():
		var at := _at(positions, _record(side))
		var c := ArcadeScreenData.colour_of(_attribute(side)["colour"])
		gradient(at.x + dx, at.y + top, width, middle - top, Color.BLACK, Color.BLACK, c, c)
		gradient(at.x + dx, at.y + middle, width, bottom - middle, c, c, end, end)


func _front() -> void:
	if not _shown():
		return
	var positions: Array = data.vs["positions"]
	var sides := _sides()
	for side in range(sides - 1, -1, -1):
		_portrait(side, _at(positions, _record(side)))
	if flow.match_flow.vs_kind != KIND_WHO_IS_IT:
		for side in sides:
			_name(side)
	_texts()


## FUN_801B8088: the frame, then the portrait.
func _portrait(side: int, at: Vector2i) -> void:
	var frame: Dictionary = data.vs["frame"]
	var colour := ArcadeScreenData.colour_of(frame["colour"])
	var rects: Array = frame["rects"]
	for piece: Array in rects:
		var x: int = piece[0]
		var y: int = piece[1]
		var width: int = piece[2]
		var height: int = piece[3]
		fill(at.x + x, at.y + y, width, height, colour)
	var attribute := _attribute(side)
	var tex := data.texture(str(attribute["portrait"]))
	if tex == null:
		return
	var portrait: Dictionary = data.vs["portrait"]
	var dx: int = portrait["x"]
	var dy: int = portrait["y"]
	var w: int = portrait["width"]
	var h: int = portrait["height"]
	var source_y: int = portrait["source_y"]
	var kind := flow.match_flow.vs_kind
	var facing: int = attribute["facing"]
	var flip := (facing != 0) != (side == 1) if kind < KIND_COMING_SOON else facing == 0
	var dest := r(at.x + dx, at.y + dy, w, h)
	if flip:
		dest.size.x = -dest.size.x
	var tint := Color.BLACK if kind == KIND_WHO_IS_IT else Color.WHITE
	target.draw_texture_rect_region(tex, dest, Rect2(0, source_y, w, h), tint)


## FUN_801B860C: left-aligned, right-aligned or centred, kept on the screen.
func _name(side: int) -> void:
	var record := _record(side)
	var records: Array = data.vs["names"]
	var at := _at(records, record)
	var key := flow.match_flow.vs_shown_key[side]
	var name_text := str(data.character(key)["name"])
	var layout: Dictionary = data.vs["name"]
	var advance: int = layout["advance"]
	var left: int = layout["left"]
	var right: int = layout["right"]
	var width := name_text.length() * advance
	var x := at.x
	if flow.match_flow.vs_kind < KIND_COMING_SOON:
		if side == 1:
			x -= width
	else:
		x -= width >> 1
	var end := x + width
	x = maxi(x, left)
	if end > right:
		x = x + right - end
	show_text("vs_name", [name_text], Vector2i(x, at.y))


## FUN_801B8880.
func _texts() -> void:
	match flow.match_flow.vs_kind:
		KIND_ONE_HUMAN, KIND_TWO:
			show_text("vs_stage", [flow.match_flow.vs_stage_number])
			show_text("vs")
		KIND_COMING_SOON:
			show_text("vs_coming_soon")
		KIND_WHO_IS_IT:
			show_text("vs_who_is_it")
