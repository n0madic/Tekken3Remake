class_name ArcadeRanking
extends ArcadeFlowPart
## The ranking's state 7 (FUN_801C241C, block 0x80375024): three pages over a turning stage and the
## name entry of a new record; and the records' keeping (FUN_801B4C60, FUN_801B4D68, FUN_801B4AD4).

const PAGE_TIME := 0
const PAGE_WINS := 1
const PAGE_USAGE := 2
const PAGES := 3
const PENDING_TIME := 1
const PENDING_WINS := 2
const FADE_STEP := 8
const FADE_FULL := 0x100
const SCROLL_STEP := 0xC
const SCROLL_BASE := 0xA8
const ROW_HEIGHT := 0x48
const ROWS_ON_PAGE := 5
const NAME_SCROLL_MAX := 0x10
const NAME_FRAMES := 3000
const NAME_SHOWN := 0x77
const WAIT_AFTER := 0x3B
const RISE_FRAMES := 0x40
const HOLD_TIME := 0x96
const HOLD_WINS := 0x78
const WINS_ROWS := 10
const BLANK_NAME := "   "               ## 0x8021F1A4: a new record's name until the player enters one
const MUSIC_RECORD := 99
const NO_ROW := -1
const FORCE_TIME_BIT := 0x400
const FORCE_WINS_BIT := 0x800
const FORCE_USAGE_BIT := 0x2000
const BACKDROP_LEFT_OUT: Array[int] = [5, 7, 6, 12]
const BACKDROP_TURN := 2
const BACKDROP_TURNS_BACK := 5
const BACKDROP_EYE := -0x4B0            ## 0x802C4038
const BACKDROP_PROJECTION := 400        ## 0x8021FAF4
enum Layer { NONE = 0, BACKDROP = 1, ROWS = 2, ENTRY = 3, ENTERED = 4 }

var kind := PAGE_TIME                   ## +0
var pending := 0                        ## +2
var entry_player := 0                   ## +3
var entry_character := 0                ## +4
var new_row := NO_ROW                   ## 0x8037520C: the row of the new record
var layer := Layer.NONE as int          ## 0x80375184
var scroll := 0                         ## 0x80375186
var scroll_target := 0                  ## 0x80375188
var page_clock := 0                     ## 0x8037518A
var hold := 0                           ## 0x8037518C
var row_rise := 0                       ## 0x8037518E
var row_count := 0                      ## 0x80375190
var rows := PackedInt32Array()          ## 0x80375192
var usage_share := PackedInt32Array()   ## 0x803751DC: per character, per mille
var top_row := 0                        ## 0x803751D4
var first_shown := 0                    ## 0x803751D8
var entry_row := 0                      ## 0x8037520A
var entry := ArcadeNameEntry.new()      ## 0x8029CEF0
var time_row := -1                      ## 0x8037502C: the character's row of the new time
var wins_row := -1                      ## 0x80375030: the row of the new wins
var backdrop_next := 0                  ## 0x8021FA78
var backdrop_stage := 0                 ## 0x8021FBB8
var backdrop_yaw := 0                   ## 0x802C4024


func _init(game: ArcadeGameFlow) -> void:
	super(game)
	usage_share.resize(ArcadeProgress.CHARACTERS)


func step() -> void:
	var g := flow
	if g.sub > 2:
		_turn_backdrop()
	if g.sub != 0 and g.start_check():
		if pending != 0:
			entry.enter(g, ArcadeNameEntry.FORCED)
			_store_entry()
			pending = 0
		return
	match g.sub:
		0:
			_choose()
		1:
			if pending != 0:
				g.music(MUSIC_RECORD)
			g.sub = 2
		2:
			_set_up_backdrop()
			g.sub = 3
		3:
			layer = Layer.BACKDROP
			g.timer = 0
			g.sub = 4
			_fade_in()
		4:
			_fade_in()
		5:
			_page_start()
		6:
			scroll_target = top_row * -ROW_HEIGHT + SCROLL_BASE
			scroll += SCROLL_STEP
			if scroll_target <= scroll:
				page_clock = 0
				row_rise = 0
				g.sub = 7
				first_shown = top_row
				scroll = scroll_target
		7:
			row_rise = mini(page_clock, RISE_FRAMES)
			page_clock += 1
			if hold <= page_clock:
				if top_row < 1:
					g.timer = 0
					g.sub = 8
				else:
					g.sub = 6
					top_row -= ROWS_ON_PAGE
		8:
			g.timer += 1
			if g.timer > WAIT_AFTER:
				g.sub = 9
		9:
			g.timer = FADE_FULL
			g.sub = 10
			_fade_out()
		10:
			_fade_out()
		0xB:
			_entry_start()
		0xC:
			_entry_scroll()
		0xD:
			page_clock -= 1
			var done := entry.enter(g, ArcadeNameEntry.TIME_UP if page_clock == 0 else ArcadeNameEntry.INPUT)
			_store_entry()
			# The blocks at 0x801C2AFC and 0x801C2B18 (Ghidra drops them): the select screen's sounds.
			if entry.accepted != 0:
				g.sound(ArcadeSelect.PICK_SOUND, ArcadeSelect.MOVE_CHANNEL)
			if entry.moved != 0:
				g.sound(ArcadeSelect.MOVE_SOUND, ArcadeSelect.MOVE_CHANNEL)
			if done:
				pending = 0
				layer = Layer.ENTERED
				g.timer = 0
				g.sub = 0xE
		0xE:
			g.timer += 1
			if g.timer > NAME_SHOWN:
				g.stop_music()
				g.sub = 9
		0xF:
			layer = Layer.NONE
			kind = (kind + 1) % PAGES
			g.goto_transition(ArcadeGameFlow.State.ATTRACT)


func _choose() -> void:
	var g := flow
	if pending == 0:
		var word := g.held(1)
		if word & FORCE_TIME_BIT != 0:
			kind = PAGE_TIME
		elif word & FORCE_WINS_BIT != 0:
			kind = PAGE_WINS
		elif word & FORCE_USAGE_BIT != 0:
			kind = PAGE_USAGE
		match kind:
			PAGE_TIME:
				_time_rows()
			PAGE_WINS:
				_wins_rows()
			PAGE_USAGE:
				_usage_rows()
		new_row = NO_ROW
	else:
		if pending & PENDING_TIME != 0:
			kind = PAGE_TIME
			new_row = _time_rows()
		elif pending & PENDING_WINS != 0:
			kind = PAGE_WINS
			new_row = _wins_rows()
		else:
			kind = PAGE_USAGE
			pending = 0
			return
		entry.open(entry_player, entry_character)
	g.stop_sounds(1)
	page_clock = 0
	layer = Layer.NONE
	g.sub = 1


## FUN_801E5B14: the next stage in turn but the ones the table 0x802045FC leaves out; the camera
## starts facing the same way.
func _set_up_backdrop() -> void:
	backdrop_next %= ArcadeGameFlow.STAGES
	while backdrop_next in BACKDROP_LEFT_OUT:
		backdrop_next = (backdrop_next + 1) % ArcadeGameFlow.STAGES
	backdrop_stage = backdrop_next
	backdrop_next += 1
	backdrop_yaw = 0


## FUN_801E5C4C: the turn of a ranking frame.
func _turn_backdrop() -> void:
	backdrop_yaw += BACKDROP_TURN if backdrop_stage == BACKDROP_TURNS_BACK else -BACKDROP_TURN


## The stage's camera: at its centre, turning.
func backdrop_view() -> CameraView:
	var view := CameraView.new()
	view.y = BACKDROP_EYE
	view.yaw = backdrop_yaw & 0xFFF
	view.h = BACKDROP_PROJECTION
	return view


func _fade_in() -> void:
	var g := flow
	g.add_fade(g.timer)
	g.timer += FADE_STEP
	if g.timer >= FADE_FULL:
		g.sub = 5 if pending == 0 else 0xB


func _fade_out() -> void:
	var g := flow
	g.add_fade(g.timer)
	g.timer -= FADE_STEP
	if g.timer < 1:
		layer = Layer.NONE
		g.sub = 0xF


func _page_start() -> void:
	var g := flow
	first_shown = row_count
	top_row = first_shown % ROWS_ON_PAGE
	if top_row == 0:
		top_row = ROWS_ON_PAGE
	top_row = first_shown - top_row
	g.sub = 6
	layer = Layer.ROWS
	scroll = row_count * -ROW_HEIGHT + SCROLL_BASE


func _entry_start() -> void:
	var g := flow
	if new_row < 2:
		top_row = 0
		entry_row = new_row
	else:
		top_row = row_count - ROWS_ON_PAGE
		if row_count - 3 < new_row:
			entry_row = ROWS_ON_PAGE - (row_count - new_row)
		else:
			top_row = new_row - 2
			entry_row = 2
	row_rise = RISE_FRAMES
	first_shown = 0
	g.sub = 0xC
	layer = Layer.ROWS
	scroll = row_count * -ROW_HEIGHT + SCROLL_BASE


func _entry_scroll() -> void:
	var g := flow
	scroll_target = top_row * -ROW_HEIGHT + SCROLL_BASE
	var step_by := clampi((scroll_target - scroll + 0xF) >> 4, 1, NAME_SCROLL_MAX)
	scroll += step_by
	if scroll_target <= scroll:
		page_clock = NAME_FRAMES
		layer = Layer.ENTRY
		g.sub = 0xD
		scroll = scroll_target


func _store_entry() -> void:
	var text := entry.name.get_string_from_ascii()
	if pending & PENDING_TIME != 0 and time_row >= 0:
		flow.progress.times[time_row].name = text
	if pending & PENDING_WINS != 0 and wins_row >= 0:
		flow.progress.wins[wins_row].name = text


# ==== the pages' rows =============================================================================

## FUN_801C1634: the time page, the characters seen, the fastest first.
func _time_rows() -> int:
	hold = HOLD_TIME
	var mask := ArcadeProgress.ROSTER_FIRST
	var p := flow.progress
	for i in ArcadeProgress.CHARACTERS:
		if p.times[i].value & ArcadeProgress.TIME_MASK < ArcadeProgress.TIME_NONE:
			mask |= 1 << i
	mask &= p.unlocked
	var list: Array[Vector2i] = []
	for i in ArcadeProgress.CHARACTERS:
		if mask >> i & 1:
			list.append(Vector2i(i, p.times[i].value & ArcadeProgress.TIME_MASK))
	_insertion_sort(list, true)
	_take_rows(list)
	for at in row_count:
		if rows[at] == time_row:
			return at
	return NO_ROW


## FUN_801C1964: the versus wins, most first.
func _wins_rows() -> int:
	var p := flow.progress
	var list: Array[Vector2i] = []
	for i in WINS_ROWS:
		list.append(Vector2i(i, p.wins[i].count))
	_insertion_sort(list, false)
	var sorted: Array[ArcadeProgress.Row] = []
	var moved_to := NO_ROW
	for at in WINS_ROWS:
		var index := list[at].x
		sorted.append(p.wins[index])
		if index == wins_row and moved_to == NO_ROW:
			moved_to = at
	p.wins = sorted
	if moved_to != NO_ROW:
		wins_row = moved_to
	row_count = WINS_ROWS
	rows.resize(WINS_ROWS)
	for i in WINS_ROWS:
		rows[i] = WINS_ROWS - 1 - i
	hold = HOLD_WINS
	return moved_to


## FUN_801C1A74: the characters by how often they were played.
func _usage_rows() -> void:
	var mask := ArcadeProgress.ROSTER_FIRST
	var total := 0
	for i in ArcadeProgress.CHARACTERS:
		var used := usage_of(i)
		if used != 0:
			mask |= 1 << i
			total += used
	mask &= flow.progress.unlocked
	var list: Array[Vector2i] = []
	for i in ArcadeProgress.CHARACTERS:
		if mask >> i & 1:
			var used := usage_of(i)
			list.append(Vector2i(i, used))
			usage_share[i] = _share(used, total)
	_insertion_sort(list, false)
	_take_rows(list)
	hold = HOLD_TIME


func _take_rows(list: Array[Vector2i]) -> void:
	row_count = list.size()
	rows.resize(row_count)
	for at in row_count:
		rows[at] = list[at].x


## FUN_801B2394: an insertion sort of (id, value) pairs, stable.
func _insertion_sort(list: Array[Vector2i], ascending: bool) -> void:
	for i in range(1, list.size()):
		var at := i
		while at > 0:
			var before := list[at - 1].y > list[at].y if ascending else list[at - 1].y < list[at].y
			if not before:
				break
			var swap := list[at - 1]
			list[at - 1] = list[at]
			list[at] = swap
			at -= 1


## FUN_801B2328: per mille.
func _share(part: int, whole: int) -> int:
	if part > whole:
		return 1000
	while whole > 0x3FFFFF:
		whole >>= 1
		part >>= 1
	return 0 if whole == 0 else part * 1000 / whole


## FUN_801B9864.
func usage_of(character: int) -> int:
	var at := (character % ArcadeProgress.CHARACTERS) * 4
	var plays := flow.progress.plays
	return plays[at] + plays[at + 2] + plays[at + 3]


# ==== the records =================================================================================

## FUN_801B4A98: the wins' place of a streak, 0 when it makes none.
func wins_place(streak: int) -> int:
	var rows_of := flow.progress.wins
	for i in WINS_ROWS:
		if rows_of[i].count < streak:
			return i + 1
	return 0


## FUN_801B4D68.
func note_wins(player: int, character: int, streak: int) -> void:
	if wins_place(streak) == 0:
		return
	entry_player = player
	entry_character = character
	wins_row = _insert_wins(character, streak, BLANK_NAME)
	pending |= PENDING_WINS


## FUN_801B4AD4: nothing when the streak makes no place (any more).
func store_wins(character: int, streak: int, text: String) -> void:
	if wins_place(streak) != 0:
		_insert_wins(character, streak, text)


func _insert_wins(character: int, streak: int, text: String) -> int:
	var p := flow.progress
	var row := ArcadeProgress.Row.new()
	row.value = character
	row.count = streak
	row.name = text
	var at := wins_place(streak) - 1
	p.wins.insert(at, row)
	p.wins.resize(WINS_ROWS)
	return at


## FUN_801B4C60, FUN_801B49F0: all ten fights with one character at a better total.
func note_time(flow_match: ArcadeMatchFlow, winner: int) -> void:
	var g := flow
	var character := g.chars[winner]
	var total := 0
	var last := (ArcadeMatchFlow.LADDER_FIGHTS - 1) * 3
	var costume := flow_match.stage_records[last + 1]
	var side := flow_match.stage_records[last + 2]
	var who := flow_match.stage_records[last]
	for i in ArcadeMatchFlow.LADDER_FIGHTS:
		if flow_match.stage_records[i * 3 + 2] != side or flow_match.stage_records[i * 3] != who:
			kind = PAGE_TIME
			return
		total += flow_match.stage_times[i]
	var row := g.progress.times[who]
	kind = PAGE_TIME
	if total >= row.value & ArcadeProgress.TIME_MASK:
		return
	pending |= PENDING_TIME
	entry_character = character
	entry_player = side
	time_row = who
	row.value = (total & ArcadeProgress.TIME_MASK) | (g.settings.rounds_one + 1 & 7) << 28 \
		| (1 << 31 if flow_match.joins != 0 else 0)
	row.count = costume
	row.name = BLANK_NAME
