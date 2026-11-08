class_name ArcadeNameEntry
extends RefCounted
## The three letters of a record: FUN_801B8E04, FUN_801B8E4C and FUN_801B8D18's rejected names, and
## the in-fight entry of a versus record (FUN_801B902C, FUN_801B9138, FUN_801B90D0).

const LETTERS := 3
const BACK := "<"
const END := "="
const SYMBOLS := 0x27                   ## the alphabet's last index
const ACCEPT := 0x360
const RIGHT_BIT := 10
const LEFT_BIT := 11
const INPUT := 0
const TIME_UP := 1
const FORCED := 2
const WAIT_FRAMES := 0x708
const BUTTON_FRAMES := 300
const DONE_FRAMES := 0x3B
const ACTIVE := 1
const SHOWN_DONE := 2
const START_ENDS := 0x8000
const START_NAME := "   "               ## 0x8021F244: every entry starts blank

var name := PackedByteArray([0x20, 0x20, 0x20])  ## 0x802732F8
var letter := 0                         ## +4
var symbol := 0                         ## +8
var character := 0                      ## +0xA
var player := 0                         ## +0xC
var moved := 0                          ## +7
var accepted := 0                       ## +6
var phase := 0                          ## 0x802732EC: 0 none, 1 entering, 2 shown
var wins := 0                           ## 0x802732F2
var wait := 0                           ## 0x802732F4
var button_wait := 0                    ## 0x802732F6


## FUN_801B8E04: the character's name comes only when the entry ends with no name or a rejected one.
func open(for_player: int, for_character: int) -> void:
	player = for_player
	character = for_character
	name = START_NAME.to_ascii_buffer()
	letter = 0
	symbol = 0
	moved = 0
	accepted = 0


## FUN_801B8E4C: `how` INPUT, TIME_UP or FORCED; true when the name is done.
func enter(flow: ArcadeGameFlow, how: int) -> bool:
	moved = 0
	accepted = 0
	match how:
		TIME_UP:
			return _finish(flow)
		FORCED:
			_default_name(flow)
			letter = LETTERS
			return true
		INPUT:
			var word := flow.repeat(player)
			var across := (word >> RIGHT_BIT & 1) - (word >> LEFT_BIT & 1)
			if across != 0:
				moved = 1
			symbol = clampi(symbol + across, 0, SYMBOLS)
			var code := flow.data.alphabet.unicode_at(symbol) if letter < LETTERS else 0
			if letter < LETTERS:
				name[letter] = code
			if flow.pressed(player) & ACCEPT != 0:
				accepted = 1
				if code == BACK.unicode_at(0):
					if letter != 0:
						name[letter] = 0x20
						letter -= 1
				elif code == END.unicode_at(0):
					return _finish(flow)
				else:
					if letter < LETTERS:
						name[letter] = code
					letter += 1
					if letter >= LETTERS:
						return _finish(flow)
	return false


## FUN_801B8D84: the rest blank; a rejected name becomes the character's.
func _finish(flow: ArcadeGameFlow) -> bool:
	while letter < LETTERS:
		name[letter] = 0x20
		letter += 1
	letter = LETTERS
	if name.get_string_from_ascii() in flow.data.rejected_names:
		_default_name(flow)
	return true


## FUN_801B8CD4: the first letters of the character's name.
func _default_name(flow: ArcadeGameFlow) -> void:
	name = ArcadeProgress.short_name(flow.data, character).to_ascii_buffer()


## FUN_801B902C: a versus record to enter while the winner fights on.
func begin(flow: ArcadeGameFlow, for_player: int, for_character: int, streak: int) -> void:
	if flow.ranking.wins_place(streak) == 0:
		return
	open(for_player, for_character)
	phase = ACTIVE
	wins = streak
	wait = 0
	button_wait = 0


## FUN_801B9138. A move or a press in the frame before restarts the button wait (the block at
## 0x801B9194, which Ghidra drops as unreachable); the counters count on whatever they compare.
func step(flow: ArcadeGameFlow) -> void:
	if phase == ACTIVE:
		if moved != 0 or accepted != 0:
			button_wait = 0
		var how := TIME_UP
		if wait < WAIT_FRAMES:
			var waited := button_wait
			button_wait += 1
			if waited < BUTTON_FRAMES:
				how = FORCED if flow.pressed(player) & START_ENDS != 0 else INPUT
		wait += 1
		if enter(flow, how):
			flow.ranking.store_wins(character, wins, name.get_string_from_ascii())
			phase = SHOWN_DONE
			button_wait = 0
	elif phase == SHOWN_DONE:
		var shown := button_wait
		button_wait += 1
		if shown > DONE_FRAMES:
			phase = 0


## FUN_801B90D0.
func finish(flow: ArcadeGameFlow) -> void:
	if phase == ACTIVE:
		enter(flow, FORCED)
		flow.ranking.store_wins(character, wins, name.get_string_from_ascii())
	phase = 0
