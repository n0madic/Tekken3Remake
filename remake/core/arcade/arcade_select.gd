class_name ArcadeSelect
extends ArcadeFlowPart
## The arcade's character select (FUN_801C06E4, context 0x802C8300): two records driven by their
## panels; the unlocked characters fill one row or two (the second centred).

const SIZE_ONE_ROW := 10
const NONE := 0x16
const ROW_CELLS := 10
const CELLS := 20
const TIME_BASE := 0x3C                 ## FUN_801BE670: the time per step
const TIME_EXTRA := 3                   ## per character beyond ten
const TIME_STEPS := 0x14
const MUSIC_DELAY := 0x12
const MUSIC_TRACK := 0x61
const MOVE_SOUND := 0x113
const PICK_SOUND := 0x112
const JOIN_SOUND := 0x110
const MOVE_CHANNEL := 0x15
const JOIN_CHANNEL := 0x1E
const CHOSEN_WAIT := 0x5A
const CHOSEN_ANIM := 0x1C
const CURSOR_REST := 0x28
const DRAW_FROM := 3
const PUNCHES := 0x300
const KICKS := 0x60
const ANY_BUTTON := 0x360
const START_COSTUME := 0x8360
const STICK_UP_DOWN := 0x3000
const LAST_CELL := 9
const SECOND_ROW_MIDDLE := 0xF          ## FUN_801BE554: the second row's cells count from here
const MIDDLE_CELL := 5
enum PlayerState { SET_UP, CHOOSING, WAITING, CHOOSING_OTHER, CPU, NONE_SHOWN, CHOSEN, CHOSEN_BY_OTHER }


var mode := 0                           ## +0
var two_rows := 0                       ## +4
var frame := 0                          ## +8
var time := 0                           ## +0xC: frames left
var time_step := 0                      ## +0x10
var grid := PackedInt32Array()          ## +0x14: two rows of ten
var mask := 0                           ## +0x28
var count := 0                          ## +0x2C
var music_delay := 0                    ## +0x30
var sides: Array[ArcadeSelectSide] = []
var sparks := ArcadeSelectSparks.new()  ## +0x168


func _init(game: ArcadeGameFlow) -> void:
	super(game)
	sides.append(ArcadeSelectSide.new())
	sides.append(ArcadeSelectSide.new())


## The state's frame.
func step() -> void:
	match flow.sub:
		0, 1:
			flow.sub += 1
			return
		2:
			_set_up()
			flow.sub = 3
		3:
			if time > 0:
				time -= 1
			var first := _side_step(0)
			var second := _side_step(1)
			if first and second:
				flow.sub = 4
		4:
			_finish()
			flow.state = flow.return_state
			flow.sub = flow.return_sub
			return
	if music_delay != 0:
		music_delay -= 1
		if music_delay == 0:
			flow.music(MUSIC_TRACK)
	if flow.sub >= 3:
		frame += 1
		if frame >= DRAW_FROM:
			for side in sides:
				side.chosen_anim = maxi(side.chosen_anim - 1, 0)
			sparks.step(frame, flow.fight.frame_counter, flow.data.select_spark_x, flow.data.select_spark_y[two_rows], flow.fight)


## Sub-state 2.
func _set_up() -> void:
	mode = flow.mode
	_fill_grid()
	two_rows = 1 if count > SIZE_ONE_ROW else 0
	frame = 0
	music_delay = MUSIC_DELAY
	flow.challenger_lock = 0
	sparks.clear()
	for p in 2:
		var s: ArcadeSelectSide = sides[p]
		s.state = PlayerState.SET_UP
		s.kept_character = flow.picks_character[p]
		s.kept_costume = flow.picks_costume[p]
		s.default_cell = flow.data.select_default_cell[p]
		_side_step(p)


## FUN_801BE554: the roster's unlocked characters, ten in the first row, the rest centred below.
func _fill_grid() -> void:
	grid.resize(CELLS)
	grid.fill(NONE)
	mask = 0
	count = 0
	var roster := flow.data.roster
	for key in roster:
		if flow.progress.unlocked >> key & 1:
			mask |= 1 << key
			count += 1
	var at := 0
	var placed := 0
	while placed < ROW_CELLS:
		if mask >> roster[at] & 1:
			grid[placed] = roster[at]
			placed += 1
		at += 1
	if count > ROW_CELLS - 1:
		var next := SECOND_ROW_MIDDLE - ((count - 9) >> 1)
		while placed < count:
			if mask >> roster[at] & 1:
				grid[next] = roster[at]
				next += 1
				placed += 1
			at += 1


## FUN_801BECCC: returns whether the side is done.
func _side_step(p: int) -> bool:
	var s: ArcadeSelectSide = sides[p]
	var other := 1 - p
	var o: ArcadeSelectSide = sides[other]
	var done := false
	match s.state:
		PlayerState.SET_UP:
			_time_limit()
			s.chosen_wait = 0
			s.chosen_anim = 0
			if flow.chosen[p] != 0:
				_chosen_marks(s)
			_show_start(s, p)
			match mode:
				ArcadeGameFlow.MODE_ARCADE, ArcadeGameFlow.MODE_DEMO:
					var how := flow.side_kind(p)
					if how == 2:
						s.state = PlayerState.CHOOSING
					elif how == 3:
						s.state = PlayerState.CHOSEN
					elif how >= 0:
						s.state = PlayerState.CPU
		PlayerState.CHOOSING:
			_move_cursor(s, (flow.sim.panels.repeat[p] & ~STICK_UP_DOWN) | (flow.sim.panels.pressed[p] & STICK_UP_DOWN))
			if s.rest != 0:
				s.rest -= 1
			var pressed := flow.sim.panels.pressed[p]
			var accept := ANY_BUTTON
			var hit := pressed & ANY_BUTTON
			if flow.progress.costumes >> s.character & 1 != 0 and s.rest == 0:
				accept = START_COSTUME
				hit = pressed & accept
			if hit != 0 or time == 0:
				var costume := 0
				if pressed & accept != 0 and pressed & PUNCHES == 0:
					costume = 1 if pressed & KICKS != 0 else 2
				if _pick(s, costume) < NONE:
					_chosen_marks(s)
					s.state = PlayerState.CHOSEN
		PlayerState.WAITING:
			if o.state == PlayerState.CHOSEN:
				s.cell = o.cell
				s.row = o.row
				s.state = PlayerState.CHOOSING_OTHER
		PlayerState.CHOOSING_OTHER:
			_move_cursor(s, (flow.sim.panels.repeat[other] & ~STICK_UP_DOWN) | (flow.sim.panels.pressed[other] & STICK_UP_DOWN))
			if flow.sim.panels.pressed[other] & ANY_BUTTON != 0 or time == 0:
				var pressed := flow.sim.panels.pressed[p]
				var costume := 0
				if pressed & 0x200 == 0 and pressed & 0x40 == 0 and pressed & 0x100 == 0:
					costume = 1
				if _pick(s, costume) < NONE:
					_chosen_marks(s)
					s.state = PlayerState.CHOSEN_BY_OTHER
		PlayerState.CPU:
			if flow.flags & ArcadeGameFlow.FLAG_CHALLENGERS != 0 and flow.challenger(p) != 0:
				s.state = PlayerState.SET_UP
				flow.sound(JOIN_SOUND, JOIN_CHANNEL)
				_end_side(s)
				return false
			done = true
		PlayerState.NONE_SHOWN:
			done = true
		PlayerState.CHOSEN:
			if flow.sim.panels.pressed[p] & ArcadeGameFlow.START != 0:
				s.chosen_wait = 0
			if s.chosen_wait < 1:
				done = true
			else:
				s.chosen_wait -= 1
		PlayerState.CHOSEN_BY_OTHER:
			if flow.sim.panels.pressed[other] & ArcadeGameFlow.START != 0:
				s.chosen_wait = 0
			if s.chosen_wait > 0:
				s.chosen_wait -= 1
			else:
				done = true
	_end_side(s)
	return done


## FUN_801BECA0.
func _end_side(s: ArcadeSelectSide) -> void:
	var anim := flow.data.select_state_anim
	s.anim_a = anim[s.state * 2]
	s.anim_b = anim[s.state * 2 + 1]


## FUN_801BE670.
func _time_limit() -> void:
	time_step = TIME_BASE if count < SIZE_ONE_ROW + 1 else (count - SIZE_ONE_ROW) * TIME_EXTRA + TIME_BASE
	time = time_step * TIME_STEPS


## FUN_801BEC40.
func _chosen_marks(s: ArcadeSelectSide) -> void:
	s.chosen_wait = CHOSEN_WAIT
	s.chosen_anim = CHOSEN_ANIM


## FUN_801BE758.
func _show_start(s: ArcadeSelectSide, p: int) -> void:
	match flow.side_kind(p):
		0:
			s.character = NONE
			s.costume = 0
		1:
			s.character = flow.chars[p]
			s.costume = flow.costumes[p]
		2:
			s.character = _at_cursor_of(s, s.kept_character)
			s.costume = s.kept_costume
		3:
			s.character = _at_cursor_of(s, flow.chars[p])
			s.costume = flow.costumes[p]
	s.rest = CURSOR_REST
	s.shown_key = NONE
	s.shown_costume = 1


## FUN_801BE6DC: the cursor goes to the character; without one to the side's own first cell.
func _at_cursor_of(s: ArcadeSelectSide, character: int) -> int:
	if character < NONE:
		var at := grid.find(character)
		if at >= 0:
			s.row = at / ROW_CELLS
			s.cell = at % ROW_CELLS
			return character
	s.row = 0
	s.cell = s.default_cell
	return grid[s.cell]


## FUN_801BE890 with the stick's word.
func _move_cursor(s: ArcadeSelectSide, word: int) -> void:
	var cell := s.cell
	var row := s.row
	if cell > LAST_CELL:
		cell = 0
	if row > 1:
		row = 0
	var across := (word >> 10 & 1) - (word >> 11 & 1)
	var moved := cell + across
	if across != 0:
		if moved < 0 or moved > LAST_CELL:
			moved = LAST_CELL - cell
		cell = moved
		if grid[row * ROW_CELLS + cell] > NONE - 1:
			row = 1 if row == 0 else 0
			if count & 1 != 0 and cell < MIDDLE_CELL:
				cell += 1
	else:
		var down := (word >> 12 & 1) - (word >> 13 & 1)
		if down != 0:
			var next_row := row + down
			if next_row >= 0 and next_row < 2:
				row = next_row
			if row != s.row and count & 1 != 0 and cell > 4:
				cell += 1 if row == 0 else -1
			if grid[row * ROW_CELLS + cell] > NONE - 1:
				var dir := 1 if cell < MIDDLE_CELL else -1
				var at := cell + dir
				var found := false
				while at >= 0 and at <= LAST_CELL:
					if grid[row * ROW_CELLS + at] != NONE:
						found = true
						break
					at += dir
				if found:
					cell = at
				else:
					cell = s.cell
					row = s.row
	if s.cell != cell or s.row != row:
		flow.sound(MOVE_SOUND, MOVE_CHANNEL)
		s.rest = 0
		s.costume = 0
	s.cell = cell
	s.row = row
	s.character = grid[row * ROW_CELLS + cell]


## FUN_801BEB68.
func _pick(s: ArcadeSelectSide, costume: int) -> int:
	var character := s.character
	if costume >= 3:
		return NONE
	if character <= NONE:
		s.costume = costume
		_resolve_costume(s)
		character = s.character
		s.kept_character = character
		s.kept_costume = s.costume
		flow.voice(flow.data.voice_of(character * 4 + s.costume))
		flow.sound(PICK_SOUND, MOVE_CHANNEL)
	return character


## FUN_801BEAA4, FUN_801B4F14: the two sides may not show the same costume.
func _resolve_costume(s: ArcadeSelectSide) -> void:
	var o: ArcadeSelectSide = sides[1] if s == sides[0] else sides[0]
	var decided := flow.data.select_decided
	if decided[o.state * 2] != 0 and s.character == o.character and s.costume == o.costume:
		if decided[o.state * 2 + 1] == 0 and decided[s.state * 2 + 1] != 0:
			o.costume = s.costume ^ 1 if s.costume < 2 else 0
		else:
			s.costume = o.costume ^ 1 if o.costume < 2 else 0


## FUN_801BF23C: the choice leaves for the mode's globals.
func _finish() -> void:
	for p in 2:
		var s: ArcadeSelectSide = sides[p]
		flow.picks_character[p] = s.character
		flow.picks_costume[p] = s.costume
		if flow.active[p] != 0:
			flow.chars[p] = s.character
			flow.costumes[p] = s.costume
			flow.chosen[p] = 1
			flow.cpu_control[p] = 0
