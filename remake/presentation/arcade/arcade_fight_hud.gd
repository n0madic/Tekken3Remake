class_name ArcadeFightHud
extends ArcadeCanvas
## The arcade fight's HUD (FUN_8019DCA8): the life bars, timer, round marks, name plates, the status
## line with the stage and clock or a side's prompt, the win streak, the round's messages and the
## flow's texts over the fight, in the scene's 4:3 frame.

enum Status { NONE, CONTINUE, PROMPT, GAME_OVER, CLOCK }

const STATUS_BLINK := 0x18
const STREAK_FLAG := 8                  ## 0x80374F1C
const READY_ROUND1 := 0x6A
const READY_LATER := 0x2E
const ROUND_ROUND1 := 0x3D
const TIME_UP := 1
const DOUBLE_KO := 4
const PERFECT := 8
const BOTH_HUMANS := 3
const NO_CONTINUE_DIGIT_PART := 0x59
const CONTINUE_DIGIT := 0x5A
const TIME_LIMIT := 359999
const FRAMES := 60
const BAR_GROWTH := 3
const NO_LIMIT := -1
const FLOW_CONTINUE := ArcadeGameFlow.TEXT_CONTINUE
const FINAL_FLASH := 0x20
const LAST_STAGE := 10

var flow: ArcadeGameFlow
var _frame := Rect2()
## FUN_801B374C: per side the life seen, the target, the drawn and the recent lengths.
var _bars: Array[PackedInt32Array] = [PackedInt32Array([0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0])]


func setup(hud_data: HudData, screens: ArcadeScreenData) -> void:
	setup_arcade(hud_data, screens)


func layout_box() -> Rect2:
	return _frame


## After a step of the flow.
func show_state(game: ArcadeGameFlow) -> void:
	flow = game
	frame_count = game.frame()
	var fight := game.fight
	if fight.round_state == RoundState.INTRO and fight.round_frame <= 1:
		_bars = [PackedInt32Array([0, 0, 0, 0]), PackedInt32Array([0, 0, 0, 0])]
	if game.round_started != 0:
		for p in 2:
			_update_bar(p)
	redraw()


## The original 4:3 frame in the window (CameraRig.frame_rect, normalised).
func place(frame_rect: Rect2) -> void:
	var window := size
	var placed := Rect2(frame_rect.position * window, frame_rect.size * window)
	if placed != _frame:
		_frame = placed
		redraw()


func _layout(key: String) -> Dictionary:
	return data.hud[key]


func _draw() -> void:
	begin()
	if flow == null or data == null or box.size.x <= 0:
		return
	var fight := flow.fight
	var matching := flow.match_flow
	if flow.round_started != 0 and fight.replay_playing == 0:
		_draw_bars()
		_draw_timer()
		_draw_marks()
		_draw_names()
		if flow.flags & STREAK_FLAG != 0:
			_draw_streak()
		for p in 2:
			_draw_status(p)
	if flow.attract_silent == 0 and matching.freeze_on_challenger == 0:
		_round_messages()
	_flow_texts()


# ==== the life bars ===============================================================================

## FUN_801B374C's lengths: a drop shows at once, a refill grows 3 per frame, the recent damage closes
## 1/16 of its length per frame.
func _update_bar(p: int) -> void:
	var life: Dictionary = _layout("life")
	var length: int = life["length"]
	var f := flow.fight.fighters[p]
	var bar := _bars[p]
	var wanted := bar[1]
	if bar[0] != f.health:
		bar[0] = f.health
		var step := f.health_max / length
		if step != 0:
			wanted = (f.health - 1 + step) / step
	wanted = mini(wanted, length)
	var drawn := bar[2]
	var recent := drawn
	if drawn < bar[3]:
		recent = bar[3] - ((bar[3] - drawn + 0xF) >> 4)
	var grown := wanted
	if wanted > drawn and drawn + BAR_GROWTH <= wanted:
		grown = drawn + BAR_GROWTH
	_bars[p] = PackedInt32Array([bar[0], wanted, grown, maxi(recent, grown)])


## Painted in the reverse of the routine's order: the backing, the caps, then the fills.
func _draw_bars() -> void:
	var life: Dictionary = _layout("life")
	var sides: Array = life["sides"]
	var length: int = life["length"]
	var top: int = life["fill_top"]
	var bottom: int = life["fill_bottom"]
	var backing_dx: int = life["backing_dx"]
	var backing_width: int = life["backing_width"]
	var right_dx: int = life["cap_right_dx"]
	for p in 2:
		var side: Dictionary = sides[p]
		var x: int = side["x"]
		var y: int = side["y"]
		var towards_right: int = side["direction"]
		var pen: int = side["grow_x"]
		var backing := hud.texture("bar_backing.png")
		var cap_left := hud.texture("bar_cap_left.png")
		var cap_right := hud.texture("bar_cap_right.png")
		target.draw_texture_rect(backing, r(x + backing_dx, y, backing_width, backing.get_size().y), false)
		image(cap_left, x, y)
		image(cap_right, x + right_dx, y)
		var bar := _bars[p]
		var parts := [["bar_health.png", bar[2]], ["bar_damage.png", bar[3] - bar[2]], ["bar_empty.png", length - bar[3]]]
		for part: Array in parts:
			var part_length: int = part[1]
			if part_length <= 0:
				continue
			var from := pen if towards_right != 0 else pen - part_length
			target.draw_texture_rect(hud.texture(str(part[0])), r(from, y + top, part_length, bottom - top), false)
			pen = pen + part_length if towards_right != 0 else pen - part_length


# ==== the timer and the marks =====================================================================

## FUN_801B35FC: the seconds left or the infinity's halves.
func _draw_timer() -> void:
	var timer: Dictionary = _layout("timer")
	var x: int = timer["x"]
	var tens_x: int = timer["tens_x"]
	var y: int = timer["y"]
	var seconds := (flow.fight.timer + 0x3B) / FRAMES
	var units := seconds % 10
	var tens := seconds / 10 % 10
	if flow.fight.timer == NO_LIMIT or flow.fight.timer_stopped != 0:
		var infinity: Array = timer["infinity"]
		tens = infinity[0]
		units = infinity[1]
	image(hud.texture("digit_%d.png" % units), x, y)
	image(hud.texture("digit_%d.png" % tens), tens_x, y)


## FUN_801B3B34: the newest won mark blinks until the round starts.
func _draw_marks() -> void:
	var marks: Dictionary = _layout("marks")
	var places: Array = marks["x"]
	var steps: Array = marks["step"]
	var y: int = marks["y"]
	var blink: int = marks["blink_mask"]
	for p in 2:
		var wins := flow.fight.fighters[p].round_wins
		var x: int = places[p]
		var step: int = steps[p]
		for i in flow.fight.rounds_to_win:
			var empty := i >= wins
			if i == wins - 1 and flow.fight.hud_wins_seen[p] != wins:
				empty = frame_count & blink != 0
			image(hud.texture("mark_empty.png" if empty else "mark_won.png"), x, y)
			x += step


## FUN_801B3E20: the name on its backing quad.
func _draw_names() -> void:
	var names: Dictionary = _layout("names")
	var places: Array = names["x"]
	var y: int = names["y"]
	var height: int = names["height"]
	var margin: int = names["plate_margin"]
	var plate_top: int = names["plate_top"]
	var plate_bottom: int = names["plate_bottom"]
	for p in 2:
		var key := flow.chars[p] * ArcadeScreenData.COSTUMES + flow.costumes[p]
		var tex := hud.name_texture(key)
		if tex == null:
			continue
		var width := hud.name_width(key)
		var place: int = places[p]
		var x := place if p == 0 else place - width
		var plate := hud.plate_texture(key)
		if plate != null:
			target.draw_texture_rect(plate, r(x - margin, y + plate_top, width + 2 * margin, plate_bottom - plate_top), false)
		image(tex, x, y, width, height)


# ==== the status line =============================================================================

## FUN_801B4734, FUN_801B4514.
func _status_of(p: int) -> Status:
	if flow.mode == ArcadeGameFlow.MODE_DEMO:
		return Status.PROMPT
	var matching := flow.match_flow
	if matching.humans == 1:
		if p == matching.human_index:
			return Status.PROMPT if flow.active[p] == 0 else Status.CLOCK
		if matching.in_continue == 0 and flow.challenger_lock == 0:
			if matching.freeze_on_challenger != 0:
				return Status.NONE
			return Status.PROMPT if flow.loser_timer[p] == 0 else Status.CONTINUE
		return Status.GAME_OVER
	if matching.humans == 2:
		var result := flow.fight.match_result
		if result == 0 or result == BOTH_HUMANS or flow.fight.match_loser != p or frame_count & STATUS_BLINK == 0:
			return Status.NONE
		return Status.GAME_OVER
	return Status.NONE


## FUN_801B437C.
func _draw_status(p: int) -> void:
	var status: Dictionary = _layout("status")
	var y: int = status["y"]
	var clocks: Array = status["clock_x"]
	var clock_x: int = clocks[p]
	match _status_of(p):
		Status.CONTINUE:
			var places: Array = status["continue_x"]
			var place: int = places[p]
			var bottom: int = status["continue_y"]
			show_text("status_continue", [(flow.loser_timer[p] + NO_CONTINUE_DIGIT_PART) / CONTINUE_DIGIT], Vector2i(place, bottom))
			_status_prompt(status, p, y)
		Status.PROMPT:
			_status_prompt(status, p, y)
		Status.GAME_OVER:
			show_text("status_game_over", [], Vector2i(clock_x, y))
		Status.CLOCK:
			_draw_clock(clock_x, y)


func _status_prompt(status: Dictionary, p: int, y: int) -> void:
	var places: Array = status["prompt_x"]
	var place: int = places[p]
	var colour: int = status["prompt_colour"]
	side_prompt(p, place, y, colour)


## FUN_801B407C: the fight's number, or FINAL in turn with it, and the time of the game.
func _draw_clock(x: int, y: int) -> void:
	var matching := flow.match_flow
	var stage := matching.fight_number + 1
	var at := Vector2i(x, y)
	if stage < LAST_STAGE or frame_count & FINAL_FLASH != 0:
		show_text("status_stage", [stage], at)
	else:
		show_text("status_final", [], at)
	show_text("status_clock_marks", [], at)
	var time := mini(flow.fight.fight_clock + matching.total_time, TIME_LIMIT)
	show_text("status_clock_digits", [time / FRAMES / FRAMES, time / FRAMES % FRAMES, time % FRAMES * 100 / FRAMES], at)


## FUN_801B3FE4: the streak, on the leader's side.
func _draw_streak() -> void:
	var matching := flow.match_flow
	var streak := mini(matching.win_streak, 999)
	if streak == 0:
		return
	var status: Dictionary = _layout("status")
	var rows: Array = status["streak"]
	var row: Dictionary
	if streak < 2:
		row = rows[0]
	elif streak < 10:
		row = rows[1]
	elif streak < 100:
		row = rows[2]
	else:
		row = rows[3]
	var places: Array = row["x"]
	var place: int = places[1 if matching.lead != 0 else 0]
	var runs: Array = row["runs"]
	for run: Dictionary in runs:
		show_run(run, [streak], Vector2i(place, 0))


# ==== the round's messages ========================================================================

func _round_messages() -> void:
	var fight := flow.fight
	match fight.round_state:
		RoundState.INTRO:
			if fight.round_frame != 0:
				_round_start()
		RoundState.RESULT:
			_round_result()
		RoundState.REPLAY:
			show_text("replay")
		RoundState.WIN_WAIT, ArcadeRoundFlow.FINISHED:
			_round_winner()


## FUN_8019E034.
func _round_start() -> void:
	var fight := flow.fight
	var first := fight.rounds_played == 1
	if fight.rounds_played >= fight.max_rounds:
		show_text("final_round")
	elif fight.round_frame >= (ROUND_ROUND1 if first else 1):
		show_text("round", [fight.rounds_played])
	if fight.round_frame >= (READY_ROUND1 if first else READY_LATER):
		show_text("ready")


## FUN_8019E260.
func _round_result() -> void:
	var flags := flow.fight.result_flags
	if flags & TIME_UP != 0:
		show_text("time_up")
	elif flags & PERFECT != 0:
		show_text("perfect")
	elif flags & DOUBLE_KO != 0:
		show_text("double_ko")
	else:
		show_text("ko")


## FUN_8019E400.
func _round_winner() -> void:
	var fight := flow.fight
	var first := fight.fighters[0].round_won
	var second := fight.fighters[1].round_won
	var decided := fight.match_result != 0 and flow.mode == ArcadeGameFlow.MODE_ARCADE
	if first == second:
		show_text("draw")
		if decided and flow.settings.event_mode != 0:
			show_text("fight_game_over")
		return
	var winner := 1 if first <= second else 0
	if fight.human_mask == BOTH_HUMANS:
		var layout: Dictionary = _layout("fight")
		var name_text := str(data.character(flow.chars[winner] * ArcadeScreenData.COSTUMES + flow.costumes[winner])["name"])
		var right: int = layout["wins_right"]
		var per_letter: int = layout["wins_per_letter"]
		show_text("wins", [name_text], Vector2i(right - name_text.length() * per_letter, 0))
		if decided:
			var winners: Array = layout["winner_x"]
			var losers: Array = layout["loser_x"]
			var winner_x: int = winners[winner]
			var loser_x: int = losers[1 - winner]
			show_text("winner", [], Vector2i(winner_x, 0))
			show_text("loser", [], Vector2i(loser_x, 0))
			if flow.settings.event_mode != 0:
				show_text("fight_game_over")
	elif fight.human_mask >> winner & 1 != 0:
		show_text("you_win")
	else:
		show_text("you_lose")


# ==== the flow's texts ============================================================================

func _flow_texts() -> void:
	var matching := flow.match_flow
	for key in flow.texts:
		match key:
			FLOW_CONTINUE:
				show_text(key, [matching.continue_digit])
			_:
				show_text(key)
	if flow.mode == ArcadeGameFlow.MODE_DEMO:
		_demo_texts()


## FUN_801B76AC: the new fighter's banner every other demonstration, and always GAME OVER.
func _demo_texts() -> void:
	var matching := flow.match_flow
	if matching.banner_shown != 0:
		var progress := flow.progress
		var key := progress.new_fighter * ArcadeScreenData.COSTUMES
		var name_text := str(data.character(key)["name"])
		var banner: Dictionary = data.banner
		var offset: int = name_text.length()
		var per_letter: int = banner["per_letter"]
		var name_right: int = banner["name_right"]
		var selectable_right: int = banner["selectable_right"]
		var face: Dictionary = banner["face"]
		var face_x: int = face["x"]
		var face_y: int = face["y"]
		picture_at(str(data.character(key)["face"]), face_x, face_y)
		show_text("banner_new_fighter")
		show_text("banner_name", [name_text], Vector2i(name_right - offset * per_letter, 0))
		show_text("banner_characters")
		show_text("banner_selectable", [], Vector2i(selectable_right - offset * per_letter, 0))
		show_text("banner_count", [ProgressRules.popcount(progress.unlocked)])
	show_text("demo_game_over")
