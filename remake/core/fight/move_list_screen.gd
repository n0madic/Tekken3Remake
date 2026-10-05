class_name MoveListScreen
extends RefCounted
## The in-fight move lists (modes.md#pause, "Move list"; the verified port
## tools/research/command_list_sim.py): the pause menu's COMMAND page (FUN_80079298) and practice's
## COMMAND LIST (FUN_8007906C) show each side's list (FUN_800789E4), scrolled by that side's pad.
## This is their input and scrolling; MoveListView draws what the MOVE_LIST event asks for.

const ROW_STEP := 64
const SOUND_MOVE := 0x546C
const SOUND_EXIT := 0x50F4
const EXIT_BUTTONS := PadState.CONFIRM
const PAGE := 5
const EXIT_DELAY := 2


## The number of moves in a fighter's list.
static func count(f: FighterState) -> int:
	return f.move_text[0] if not f.move_text.is_empty() else 0


## FUN_800789E4 before it draws: up and down move by one, left and right by five while up and
## down are not held, wrapping (sound 0x546C); the list slides 64 pixels a step and eases in,
## keeping two thirds of the offset each frame.
static func scroll(fight: FightState, player: int, pad_player: int, pads: FighterInput.PadWords,
		events: SimEvents) -> void:
	var n := count(fight.fighters[player])
	var pressed := pads.physical_pressed[pad_player]
	var d := 1 if pressed == PadState.DOWN else 0
	if pressed == PadState.UP:
		d = -1
	if pads.physical[pad_player] & (PadState.UP | PadState.DOWN) == 0:
		if pressed == PadState.RIGHT:
			d = PAGE
		elif pressed == PadState.LEFT:
			d = -PAGE
	if d != 0:
		events.add(SimEvents.Kind.SOUND, -1, SOUND_MOVE, 0)
	var cur := fight.command_cursor[player]
	var v := (cur if cur < n else 0) + d
	if v < 0:
		v += n
	if not v < n:
		v -= n
	fight.command_cursor[player] = v
	fight.command_offset[player] = Fx.w32(fight.command_offset[player] + ROW_STEP * d)
	var off := fight.command_offset[player]
	if off != 0:
		var a := absi(off)
		a = maxi(a - Fx.div_trunc(a + 3, 3), 0)
		off = -a if off < 0 else a
	fight.command_offset[player] = off


## The lists of the sides in `mask`, each scrolled by its own pad.
static func _lists(fight: FightState, mask: int, pads: FighterInput.PadWords, events: SimEvents) -> void:
	for p in 2:
		if mask >> p & 1:
			scroll(fight, p, p, pads, events)


## FUN_80079298: the pause menu's COMMAND page of the pausing `player` (1 or 2): every human
## side's list; a face button or Start returns to the menu (cursor on CANCEL). Tekken Force shows
## only the first record's list, under the left column. (The game's extra fight frame of a lagging
## frame, which scrolls with text off, is not modelled: bug #39.)
static func pause_page(fight: FightState, player: int, pads: FighterInput.PadWords, events: SimEvents) -> void:
	if fight.pause_delay != 0:
		fight.pause_delay -= 1
		return
	if pads.physical_pressed[0 if player == 1 else 1] & EXIT_BUTTONS:
		fight.pause_page = 0
		fight.pause_cursor = 0
		fight.pause_delay = EXIT_DELAY
		# FUN_80048760: the stage's horizon band (stages.md, "Clear colour") behind the scene for
		# two frames; the remake's panorama and floor always cover it.
		events.add(SimEvents.Kind.SOUND, -1, SOUND_EXIT, 0)
	if fight.mode == GameMode.FORCE:
		events.add(SimEvents.Kind.MOVE_LIST, -1, 1, 0)
		scroll(fight, 0, fight.force.human(), pads, events)
		return
	events.add(SimEvents.Kind.MOVE_LIST, -1, fight.human_mask, player - 1)
	_lists(fight, fight.human_mask, pads, events)


## FUN_8007906C: practice's COMMAND LIST: the lists in `mask` and PUSH BUTTON TO EXIT under
## `player`'s column (the menu's own item input turns it off).
static func practice_page(fight: FightState, mask: int, player: int, pads: FighterInput.PadWords,
		events: SimEvents) -> void:
	if fight.pause_delay != 0:
		fight.pause_delay -= 1
		return
	events.add(SimEvents.Kind.MOVE_LIST, -1, mask, player)
	_lists(fight, mask, pads, events)
