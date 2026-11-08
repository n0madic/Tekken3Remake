class_name ArcadeCanvas
extends ScreenCanvas
## The base of the arcade's 2D views: its 512 × 480 layout in the window's 4:3 area, its texts as
## `screens.json` gives them (printf formats, one run per stretch of font, colour and pen) and its
## prompts on free play.

const LAYOUT := Vector2i(512, 480)
const FOLLOW := -1                      ## a run's own colour
const PROMPT_ON_FREE_PLAY := 6          ## FUN_801B13A8: the main prompt's entry
const SIDE_PROMPT_ON_FREE_PLAY := 2     ## FUN_801B1514: + the player
const CREDITS_ON_FREE_PLAY := 0         ## FUN_801B114C
const NEUTRAL := 0x80                   ## a texture's colour that leaves it as it is

var data: ArcadeScreenData
var frame_count := 0


func setup_arcade(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_canvas(hud_data)
	data = screens


func pt(x: float, y: float) -> Vector2:
	return ScreenBox.point(box, LAYOUT, x, y)


## A key of the texts: its runs in turn from `origin` (added to the runs' own positions), the values
## going to the runs that print them, a run without a colour taking `colour`.
func show_text(key: String, values: Array = [], origin := Vector2i.ZERO, colour := FOLLOW) -> void:
	var used := 0
	for run: Dictionary in data.text_runs(key):
		used += show_run(run, values.slice(used), origin, colour)


## One run: how many values it took.
func show_run(run: Dictionary, values: Array, origin: Vector2i, colour := FOLLOW) -> int:
	var own_x: Variant = run["x"]
	var own_y: Variant = run["y"]
	var own_colour: Variant = run["colour"]
	var x := origin.x + (0 if own_x == null else JsonFile.number(own_x))
	var y := origin.y + (0 if own_y == null else JsonFile.number(own_y))
	var shade := colour if own_colour == null else JsonFile.number(own_colour)
	var format: String = run["text"]
	var font: int = run["font"]
	var fields: Array = [x, y]
	fields.append_array(values)
	print_fmt("%H%V" + format, fields, font, shade)
	return _value_count(format)


## The values a format takes: `%%` takes none.
static func _value_count(format: String) -> int:
	return format.count("%") - 2 * format.count("%%")


## FUN_801B13A8 on free play.
func main_prompt() -> void:
	var main: Dictionary = data.prompts["main"]
	var mask: int = main["blink_mask"]
	if frame_count & mask == 0:
		return
	var entries: Array = main["entries"]
	var entry: Dictionary = entries[PROMPT_ON_FREE_PLAY]
	var x: int = entry["x"]
	var y: int = main["y"]
	var colour: int = main["colour"]
	text(str(entry["text"]), 0, colour, x, y)


## FUN_801B10B0 on free play.
func credits_line() -> void:
	var credits: Dictionary = data.prompts["credits"]
	var entries: Array = credits["entries"]
	var entry: Dictionary = entries[CREDITS_ON_FREE_PLAY]
	var places: Array = credits["x"]
	var x: int = places[0]
	var y: int = credits["y"]
	var colour: int = credits["colour"]
	text(str(entry["text"]), 0, colour, x, y)


## FUN_801B1278 on free play: the side's start prompt, and FREE PLAY in turn.
func side_prompt(player: int, x: int, y: int, colour: int) -> void:
	var side: Dictionary = data.prompts["side"]
	var blink: int = side["blink_mask"]
	if frame_count & blink == 0:
		return
	var alternate: int = side["alternate_mask"]
	var entry: Dictionary
	if frame_count & alternate == 0:
		var entries: Array = side["entries"]
		entry = entries[SIDE_PROMPT_ON_FREE_PLAY + player]
	else:
		var credits: Dictionary = data.prompts["credits"]
		var entries: Array = credits["entries"]
		entry = entries[CREDITS_ON_FREE_PLAY]
	var dx: int = entry["x"]
	text(str(entry["text"]), 0, colour, x + dx, y)


## A picture at its size from a file of the screens.
func picture_at(file: String, x: float, y: float, modulate_colour := Color.WHITE) -> void:
	image(data.texture(file), x, y, -1.0, -1.0, modulate_colour)


## A picture at its size, cut to the lines from `top` down to `bottom`.
func picture_clipped(tex: Texture2D, x: float, y: float, top: float, bottom: float) -> void:
	if tex == null:
		return
	var sz := tex.get_size()
	var first := maxf(top - y, 0.0)
	var last := minf(bottom - y, sz.y)
	if last > first:
		target.draw_texture_rect_region(tex, r(x, y + first, sz.x, last - first), Rect2(0, first, sz.x, last - first))
