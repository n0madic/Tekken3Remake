class_name GameGlobals
extends RefCounted
## The game flow's globals outside the progress block and the mode region (modes.md): the
## players' choices and flags, the save request, the display flag. Comments give the addresses.

var player_char := PackedInt32Array([0, 0])        ## 0x800AE224: character per player
var player_costume := PackedInt32Array([0, 0])     ## 0x800AE260
var player_cpu := PackedInt32Array([0, 0])         ## 0x800A95F0: the player's fighter is a CPU
var player_active := PackedInt32Array([0, 0])      ## 0x800AE6C0: a human plays on this pad
var player_keep := PackedInt32Array([0, 0])        ## 0x800AE484: the pick is kept (quick select)
var controller := PackedInt32Array([0, 0])         ## 0x800A9621 + 0x2A·p (FUN_8002A3C0)
var other_player := 0                              ## 0x800B0A06: the side that did not start
var win_streak := 0                                ## 0x800AE218: wins in a row of the tie winner
var save_pending := 0                              ## 0x800AE428
var save_error := 0                                ## 0x800AE429: frames of AUTO SAVE ERROR!
var display_on := 0                                ## 0x80095850 (FUN_80029860)


## FUN_80051474: `player` wins ties; the other side is the other player.
func set_tie_winner(fight: FightState, player: int) -> void:
	fight.tie_choice = player & 0xFF
	other_player = (player + 1) & 1
	win_streak = 0


## FUN_80051498: another win for `player` (a new winner restarts the streak at 1).
func count_win(fight: FightState, player: int) -> void:
	if player == fight.tie_choice:
		win_streak = (win_streak + 1) & 0xFFFF
	else:
		fight.tie_choice = player & 0xFF
		other_player = (fight.tie_choice + 1) & 1
		win_streak = 1
