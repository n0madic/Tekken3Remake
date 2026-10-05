class_name ProgressRules
extends RefCounted
## The rules that change the game's progress (modes.md#unlocks, #records), written from the
## verified port `tools/research/screens_sim.py`: the unlock schedule, the play-count unlocks, arcade
## clears, Gon's unlock, the character statistics and the save request.

const START_COSTUME_MASK := 0x50382
const ALL_CHARACTERS := 0x1FFFFF
const FIGHTS_CAP := 0xFFFF
const NO_CHARACTER := 0x16
const DOCTOR_B_BIT := 1 << Character.DOCTOR_B
const UNLOCK_STEP_MASK := 0x83FF        ## the characters whose clears count as unlock steps
const SECOND_CLEARS := 0x10900          ## the second-clear bits: Kuma (Panda), Eddy (Tiger), Gun Jack
## Start costumes unlocked by usage: (character, usage, costume bit).
static var USAGE_COSTUMES: Array[PackedInt32Array] = [PackedInt32Array([9, 50, 0x200]),
	PackedInt32Array([7, 50, 0x80]), PackedInt32Array([18, 25, 0x40000]), PackedInt32Array([16, 10, 0x10000])]

var progress: GameProgress
var globals: GameGlobals
var schedule: PackedInt32Array
var region: ModeRegion
var fight_rules: RuleSet


func _init(game_progress: GameProgress, game_globals: GameGlobals, mode_region: ModeRegion, flow: FlowData,
		rule_set: RuleSet) -> void:
	progress = game_progress
	globals = game_globals
	region = mode_region
	schedule = flow.unlock_schedule
	fight_rules = rule_set


static func popcount(v: int) -> int:
	var n := 0
	v &= 0xFFFFFFFF
	while v != 0:
		n += v & 1
		v >>= 1
	return n


## FUN_80056498.
func unlock_character(character: int) -> void:
	var bit := 1 << character
	if progress.unlocked & bit == 0:
		progress.new_character = character
		progress.fights_since_unlock = 0
	progress.unlocked |= bit


## `--unlock`: every character, Start costume, mode and Theater movie open, as after the schedule's
## last step but without its side effects (no "just unlocked" character, no reset of the play
## count). The movies open with the arcade clears of every character and the three second clears.
static func open_all(p: GameProgress) -> void:
	p.cleared |= ALL_CHARACTERS
	p.cleared2 |= SECOND_CLEARS
	p.unlocked |= ALL_CHARACTERS
	p.start_costumes = (p.start_costumes | START_COSTUME_MASK) & START_COSTUME_MASK
	p.ball_new = maxi(p.ball_new, 1)
	p.theater_new = maxi(p.theater_new, 1)
	p.unlock_class = 2


func update_unlock_class() -> void:
	if progress.unlocked & DOCTOR_B_BIT:
		progress.unlock_class = 2
	else:
		progress.unlock_class = 1 if popcount(progress.unlocked) >= 15 else 0


func add_start_costume(bit: int) -> void:
	if progress.start_costumes & bit == 0:
		progress.fights_since_unlock = 0
	progress.start_costumes = (progress.start_costumes | bit) & START_COSTUME_MASK


## ArcadeUnlocks (FUN_800564C8): the first `n` steps of the schedule.
func arcade_unlocks(n: int) -> void:
	if (n & 0xFFFFFFFF) > 14:
		n = 14
	for step in maxi(n, 0):
		var kind := schedule[2 * step]
		var value := schedule[2 * step + 1]
		match kind:
			0:
				progress.fights_since_unlock = 0
			1:
				unlock_character(value & 31)
			2:
				add_start_costume(1 << (value & 31))
			3:
				_open_theater()
			4:
				if progress.ball_new == 0:
					progress.ball_new = 1
					progress.fights_since_unlock = 0
			5:
				for c in 22:
					if ALL_CHARACTERS >> c & 1:
						unlock_character(c)
					if START_COSTUME_MASK >> c & 1:
						add_start_costume(1 << c)
				if progress.ball_new == 0:
					progress.ball_new = 1
					progress.fights_since_unlock = 0
				if progress.theater_new == 0:
					progress.theater_new = 1
					progress.fights_since_unlock = 0
				update_unlock_class()
	_open_theater()
	update_unlock_class()


func _open_theater() -> void:
	if progress.cleared & 0x3FF == 0x3FF and progress.theater_new == 0:
		progress.theater_new = 1
		progress.fights_since_unlock = 0


## FUN_800567A0: Start costumes by usage, then one more schedule step per 100 (then 50) fights.
func play_unlocks() -> void:
	for rule: PackedInt32Array in USAGE_COSTUMES:
		if progress.usage(rule[0]) >= rule[1]:
			add_start_costume(rule[2])
	update_unlock_class()
	var need := 50 if progress.play_steps_seen != 0 else 100
	if progress.fights_since_unlock >= need:
		progress.play_steps_seen = 1
		var steps := mini(progress.play_steps + 1, 14)
		progress.fights_since_unlock = 0
		progress.play_steps = steps
		arcade_unlocks(steps)


## FUN_8004C678: after a statistics update, the play-count unlocks and a pending save.
func request_save() -> void:
	play_unlocks()
	globals.save_pending = 1


## FUN_8005696C: beating Gon as the CPU in arcade or Tekken Ball unlocks him.
func gon_check(character: int) -> void:
	if character == Character.GON and progress.unlocked & (1 << Character.GON) == 0 and (region.mode == GameMode.ARCADE or region.mode == GameMode.BALL):
		progress.unlocked |= 1 << Character.GON
		progress.new_character = Character.GON
		progress.fights_since_unlock = 0


## FUN_800B2350 (arcade.ovl): an arcade clear, and the steps the clears open (unlock_steps).
func record_clear(character: int, costume: int) -> void:
	if region.mode != GameMode.ARCADE:
		return
	progress.new_character = NO_CHARACTER
	var first := progress.cleared
	var second := progress.cleared2
	match character:
		11:
			if costume == 1:
				second |= 0x800
			else:
				first |= 0x800
		8:
			if costume < 2:
				first |= 0x100
			else:
				second |= 0x100
		16:
			if first & 0x10000 == 0:
				first |= 0x10000
			else:
				second |= 0x10000
		_:
			first |= 1 << (character & 31)
	progress.cleared = first & ALL_CHARACTERS
	progress.cleared2 = second & ALL_CHARACTERS
	arcade_unlocks(unlock_steps((first | second) & ALL_CHARACTERS, fight_rules.fix_unlock_pace))


## The unlock steps a cleared mask opens: the bit positions below the number of cleared
## characters that are set in 0x83FF (bug #29), or with `fixed` the cleared characters in it.
static func unlock_steps(cleared: int, fixed: bool) -> int:
	if fixed:
		return popcount(cleared & UNLOCK_STEP_MASK)
	var n := 0
	for i in popcount(cleared):
		if (1 << i) & UNLOCK_STEP_MASK:
			n += 1
	return n


func _bump(character: int, which: int) -> void:
	var c := character % 22
	progress.set_stat(c, which, mini(progress.stat(c, which) + 1, FIGHTS_CAP))
	progress.fights_since_unlock = mini(progress.fights_since_unlock + 1, FIGHTS_CAP)


## FUN_8005169C: a finished run or a VS win of `character`.
func count_play(character: int) -> void:
	_bump(character, 0)
	request_save()


## FUN_80051740: a win and a loss.
func count_result(winner: int, loser: int) -> void:
	var w := winner % 22
	progress.set_stat(w, 1, mini(progress.stat(w, 1) + 1, FIGHTS_CAP))
	var l := loser % 22
	progress.set_stat(l, 2, mini(progress.stat(l, 2) + 1, FIGHTS_CAP))
	progress.fights_since_unlock = mini(progress.fights_since_unlock + 1, FIGHTS_CAP)
	request_save()


## FUN_80051838: a draw for both characters.
func count_draw(a: int, b: int) -> void:
	_bump(a, 3)
	_bump(b, 3)
	request_save()
