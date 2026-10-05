class_name PauseMenu
extends RefCounted
## The pause menu (FUN_80078498, FUN_8007854C): CANCEL, COMMAND and RESET chosen with up and
## down, confirmed with Start or a face button; CANCEL closes the pause at the next pause check,
## RESET leaves the fight (MenuExitCheck, which also leaves on Start + Select); COMMAND shows
## the move lists (MoveListScreen.pause_page) until a button returns to the menu. Tekken Ball adds
## HOW TO, a picture of its rules (volley.ovl FUN_800B4088).

const ITEMS := ["CANCEL", "COMMAND", "RESET", "HOW TO"]
const PAGE_CANCEL := 1
const PAGE_COMMAND := 2
const PAGE_RESET := 3
const PAGE_HOW_TO := 4
const HOW_TO_DELAY := 3
const OPENED := -1                  ## 0x80098DDC = 0xFF: the menu was just opened
const CONFIRM_DELAY := 2
const CONFIRM := PadState.CONFIRM
const SOUND_MOVE := 0x546C
const SOUND_CONFIRM := 0x50F4
## MenuExitCheck's soft reset: Start and Select held with nothing else but L1 / R1.
const SOFT_RESET := PadState.START | PadState.SELECT
const SOFT_RESET_MASK := ~(PadState.L1 | PadState.R1) & 0xFFFF


## One paused frame of `player` (1 or 2).
static func step(fight: FightState, player: int, pads: FighterInput.PadWords, events: SimEvents) -> void:
	if fight.pause_cursor == OPENED:
		fight.pause_page = 0
		fight.pause_cursor = 0
		fight.pause_delay = CONFIRM_DELAY
		events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
		events.add(SimEvents.Kind.SOUND, -1, SOUND_CONFIRM, 0)
	if fight.pause_page == PAGE_COMMAND:
		MoveListScreen.pause_page(fight, player, pads, events)
		return
	if fight.pause_page == PAGE_HOW_TO:
		_how_to(fight, player, pads, events)
		return
	# FUN_8007854C draws nothing while the menu is inert.
	if fight.pause_delay != 0:
		fight.pause_delay -= 1
		return
	events.add(SimEvents.Kind.PAUSE_MENU, -1, player)
	var pressed := pads.physical_pressed[clampi(player - 1, 0, 1)]
	var count := item_count(fight)
	if pressed & PadState.UP != 0:
		fight.pause_cursor = (fight.pause_cursor if fight.pause_cursor != 0 else count) - 1
		events.add(SimEvents.Kind.SOUND, -1, SOUND_MOVE, 0)
	if pressed & PadState.DOWN != 0:
		fight.pause_cursor = (fight.pause_cursor + 1) % count
		events.add(SimEvents.Kind.SOUND, -1, SOUND_MOVE, 0)
	if pressed & CONFIRM != 0:
		fight.pause_delay = CONFIRM_DELAY
		fight.pause_page = fight.pause_cursor + 1
		events.add(SimEvents.Kind.SOUND, -1, SOUND_CONFIRM, 0)


## The menu's items: HOW TO only in Tekken Ball.
static func item_count(fight: FightState) -> int:
	return ITEMS.size() if fight.mode == GameMode.BALL else ITEMS.size() - 1


## FUN_800B4088: the HOW TO picture until Start or a face button returns to the menu.
static func _how_to(fight: FightState, player: int, pads: FighterInput.PadWords, events: SimEvents) -> void:
	if fight.pause_delay != 0:
		fight.pause_delay -= 1
		return
	if pads.physical_pressed[clampi(player - 1, 0, 1)] & CONFIRM != 0:
		fight.pause_cursor = 0
		fight.pause_page = 0
		fight.pause_delay = HOW_TO_DELAY
		events.add(SimEvents.Kind.SOUND, -1, SOUND_CONFIRM, 0)


## The remake's Escape on the menu: as CANCEL confirmed. False when the menu is not taking input
## (not shown, inert, or the COMMAND page, which Escape's Start leaves).
static func escape(fight: FightState, events: SimEvents) -> bool:
	if fight.paused_player == 0 or fight.pause_page != 0 or fight.pause_delay != 0 or fight.pause_cursor == OPENED:
		return false
	fight.pause_cursor = PAGE_CANCEL - 1
	fight.pause_page = PAGE_CANCEL
	fight.pause_delay = CONFIRM_DELAY
	events.add(SimEvents.Kind.SOUND, -1, SOUND_CONFIRM, 0)
	return true


## MenuExitCheck (0x80051304): RESET chosen, or Select pressed while Start and Select are held
## (the shoulder buttons may be held too).
static func exit_requested(fight: FightState, pads: FighterInput.PadWords) -> bool:
	for p in 2:
		if pads.physical[p] & SOFT_RESET_MASK == SOFT_RESET and pads.physical_pressed[p] & PadState.SELECT != 0:
			return true
	return fight.pause_page == PAGE_RESET
