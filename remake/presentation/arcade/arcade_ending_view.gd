class_name ArcadeEndingView
extends ArcadeCanvas
## The ending's 2D (FUN_801E5F50): the clear screen, half-transparent over black, with its texts, a
## page's staff blocks and the first page's title over the replay, the last pose's credits, the logo.

const CLEAR_TEXT := 0x40
const CHAMPION_TEXT := 0x60
const TIME_TEXT := 0xA0
const TIME_DIGITS := 0xE0
const RECORD_TEXT := 0xF0
const RECORD_BLINK := 0x10
const PICTURE_ALPHA := 0.5
const TIME_LIMIT := 359999
const FRAMES := 60

var flow: ArcadeGameFlow


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_arcade(hud_data, screens)


func show_state(game: ArcadeGameFlow) -> void:
	flow = game
	frame_count = game.frame()
	redraw()


func _draw() -> void:
	begin()
	if flow == null:
		return
	var sub := flow.sub
	var ending := flow.ending
	if sub <= ArcadeEnding.CLEAR:
		black()
		_clear(ending.clear_clock)
	elif sub >= ArcadeEnding.LOGO_START:
		black()
		var logo: Dictionary = data.ending["logo"]
		var x: int = logo["x"]
		var y: int = logo["y"]
		picture_at(str(logo["file"]), x, y)
	elif ending.in_fight():
		if sub == ArcadeEnding.POSE:
			if ending.credits_shown:
				_credits()
		elif sub < ArcadeEnding.POSE_WAIT and ending.page() <= ArcadeEnding.LAST_PAGE:
			_page(ending)
	else:
		black()


func _clear(clock: int) -> void:
	var background: Dictionary = data.ending["background"]
	var width: int = background["width"]
	var height: int = background["height"]
	image(data.texture(str(background["file"])), 0, 0, width, height, Color(1, 1, 1, PICTURE_ALPHA))
	if clock > CLEAR_TEXT:
		show_text("ending_clear")
	if clock > CHAMPION_TEXT:
		show_text("ending_you_are")
		show_text("ending_the")
		show_text("ending_champion")
	if clock > TIME_TEXT:
		show_text("ending_your_time")
	if clock > TIME_DIGITS:
		if clock > RECORD_TEXT and flow.ranking.pending & ArcadeRanking.PENDING_TIME != 0 and clock & RECORD_BLINK != 0:
			show_text("ending_new_record")
		show_text("ending_time_marks")
		var time := mini(flow.match_flow.all_fights_time(), TIME_LIMIT)
		show_text("ending_time_digits", [time / (FRAMES * FRAMES) % FRAMES, time / FRAMES % FRAMES, time % FRAMES * 100 / FRAMES])


func _page(ending: ArcadeEnding) -> void:
	if ending.title_shown:
		show_text("ending_staff_title")
	if ending.slide >= ArcadeEnding.OFF_SCREEN:
		return
	var pages: Array = data.ending["staff"]
	var page: Dictionary = pages[ending.page()]
	_block(page.get("left"), ending.slide)
	_block(page.get("right"), ending.slide)


## FUN_801E5D28: the lines of a block, sliding in from its side.
func _block(block: Variant, slide: int) -> void:
	if block == null:
		return
	var d: Dictionary = block
	var x: int = d["x"]
	var sign_of: int = d["slide"]
	var font: int = data.ending["font"]
	var lines: Array = d["lines"]
	for line_of: Dictionary in lines:
		var dx: int = line_of["x"]
		var y: int = line_of["y"]
		var colour: int = line_of["colour"]
		text(str(line_of["text"]), font, colour, x + sign_of * slide + dx, y)


func _credits() -> void:
	show_text("ending_produced_by")
	var logo: Dictionary = data.ending["namco_logo"]
	var x: int = logo["x"]
	var y: int = logo["y"]
	picture_at(str(logo["file"]), x, y)
	show_text("ending_copyright")
	show_text("ending_rights")
