class_name ModeLine
## What each player's line under the health bars shows (FUN_8004EFF8 and the modes' routines
## FUN_800B2170, FUN_800B2254, FUN_800B22D0, FUN_800B2310, FUN_800B5210; hud.md#elements).

enum { NONE = 0, COIN = 1, GAME_OVER = 2, STAGE_TIME = 3, TEAM = 4, TIME_ATTACK = 5, SURVIVAL = 6,
	SURVIVAL_COUNT = 8, BALL = 9, SCORE = 10 }


## The line of player `p`; `humans` is GameGlobals.player_active.
static func code(fight: FightState, humans: PackedInt32Array, p: int) -> int:
	var region := fight.region
	var active := humans[p] != 0
	match fight.mode:
		GameMode.ARCADE:
			return _arcade(fight, active, p)
		GameMode.TEAM:
			return _two_sides(region, active, p, TEAM)
		GameMode.TIME_ATTACK:
			if p != region.human_index:
				return TIME_ATTACK
			return STAGE_TIME if active else COIN
		GameMode.SURVIVAL:
			if p != region.human_index:
				return SURVIVAL
			return SURVIVAL_COUNT if active else GAME_OVER
		GameMode.DEMO:
			return COIN
		GameMode.BALL:
			return _two_sides(region, active, p, BALL)
		GameMode.FORCE:
			return SCORE
	return NONE


static func _arcade(fight: FightState, active: bool, p: int) -> int:
	var region := fight.region
	if region.human_count == 1:
		if p == region.human_index:
			return STAGE_TIME if active else COIN
		if region.continuing != 0 or fight.challenger_lock != 0:
			return GAME_OVER
		return COIN if region.challenger == 0 else NONE
	if region.human_count == 2:
		var result := region.match_result
		if result == 0 or result == 3 or region.match_loser != p or fight.vblank & 0x18 == 0:
			return NONE
		return GAME_OVER
	return NONE


## Team battle and Tekken Ball: the mode's name on the human's side, the prompt on the other.
static func _two_sides(region: ModeRegion, active: bool, p: int, name_code: int) -> int:
	if region.human_count == 1:
		if p != region.human_index:
			return COIN
		return name_code if active else COIN
	if region.human_count == 2:
		return name_code if p == 0 else NONE
	return NONE
