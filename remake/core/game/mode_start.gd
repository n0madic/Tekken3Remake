class_name ModeStart
extends RefCounted
## FUN_800DAF2C (title.ovl; menu_sim.mode_start, verified): a mode starts. The options go into
## the fight variables, the players' choices are cleared, the mode's rule bytes (0x800AFF54 …)
## and counters are set, and the game goes to the fight preparation (state 7).

## FUN_800DB4E4: the mode overlay each mode needs (arcade 0, practice 1, force 2, volley 3).
const MODE_OVERLAYS := [0, 0, 0, 0, 0, 1, 0, 3, 2]
## Per mode the rule bytes 0x800AFF54 … 0x800AFF5C.
static var FEATURES: Array[PackedInt32Array] = [
	PackedInt32Array([1, 1, 0, 1, 0, 0, 0, 1, 0]), PackedInt32Array([1, 0, 0, 1, 1, 0, 1, 1, 1]),
	PackedInt32Array([1, 1, 1, 0, 1, 1, 1, 1, 1]), PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 1, 0]),
	PackedInt32Array([0, 0, 0, 1, 0, 1, 1, 1, 0]), PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 1, 0]),
	PackedInt32Array([0, 0, 0, 0, 0, 0, 1, 1, 0]), PackedInt32Array([1, 1, 0, 0, 1, 0, 0, 0, 1]),
	PackedInt32Array([1, 0, 0, 0, 0, 0, 0, 0, 0]),
]
const NO_CHARACTER := 0x16
const NO_PICK := 0x58
const QUICK_CHALLENGE := PadState.START | PadState.L1 | PadState.R1  ## quick select


static func start(g: GameFlow, mode: int, players: int) -> void:
	_options(g, mode)
	_players(g, players)
	g.fight.replay.init_attract(g.state == GameFlow.State.ENBU)
	if _mode_rules(g, mode):
		g.progress.ranking_page = 2
	var fight := g.fight
	if fight.round_time_option > 4:
		fight.timer_stopped = 1
	g.region.mode_overlay = MODE_OVERLAYS[mode] if mode >= 0 and mode < MODE_OVERLAYS.size() else 0
	g.state = GameFlow.State.PREPARE
	g.sub = 0


## The options into the fight variables, the mode's counters cleared.
static func _options(g: GameFlow, mode: int) -> void:
	var fight := g.fight
	var region := g.region
	var progress := g.progress
	g.music_stop()
	# The records' own numbers again (+0x12 pad slot, +0x1E index; the third record is player 1's
	# side): Tekken Ball copies a hitter's whole record into the third one.
	for i in FightState.RECORDS:
		fight.fighters[i].player_index = mini(i, 1)
		fight.fighters[i].index = i
	fight.stage_cached = -1           # FUN_8006C870(0x1F)
	for at: int in [0x69, 0x5F, 0x61, 0x62, 0x63]:
		region.put8(at, 0)
	fight.timer_stopped = 0
	fight.practice = 0
	for at: int in [0x74, 0x78, 0x7C, 0x80, 0x84]:
		region.put32(at, 0)
	g.fight.challenger_lock = 0
	fight.attract = 0
	region.character_change = progress.character_change
	region.quick_select_option = progress.quick_select
	region.rounds_option = progress.fight_count
	fight.ai_difficulty = progress.difficulty
	fight.round_time_option = progress.round_time
	fight.chip_damage = progress.guard_damage
	fight.ai_level = 0
	region.mode = mode


## The players' controllers and choices cleared; `players` picks who starts active.
static func _players(g: GameFlow, players: int) -> void:
	var fight := g.fight
	var region := g.region
	var progress := g.progress
	var globals := g.globals
	for p in 2:
		globals.controller[p] = progress.controller(p)
		var held := g.held(p)
		if held & PadState.START:
			region.challenger_quick = 1 if held == QUICK_CHALLENGE else 0
		# FUN_80051A98: no carried health.
		fight.fighters[p].health = 0
		fight.fighters[p].carried_health = 0
		if progress.cursor_hold == 0:
			progress.set_last_character(p, NO_PICK)
		globals.player_char[p] = NO_CHARACTER
		globals.player_costume[p] = 0
		globals.player_keep[p] = 0
		globals.player_active[p] = 0
	var first := (players ^ 1) & 1
	globals.set_tie_winner(fight, first)
	globals.player_active[first] = 1


## The mode's rule bytes and its own settings; true when the ranking shows its usage page next.
static func _mode_rules(g: GameFlow, mode: int) -> bool:
	var fight := g.fight
	var region := g.region
	var globals := g.globals
	var tail := true
	if mode >= 0 and mode < FEATURES.size():
		var features := FEATURES[mode]
		for k in features.size():
			region.put8(0x54 + k, features[k])
	match mode:
		GameMode.ARCADE:
			_clear_stage_records(region)
		GameMode.VS, GameMode.BALL:
			if mode == GameMode.VS:
				globals.player_active[1] = 1
				globals.player_active[0] = 1
			else:
				fight.round_time_option = 5
				fight.chip_damage = 0
			region.put8(0x8A, 3)
			region.put8(0x8E, 3)
			region.put32(0x90, region.u16(0x92) << 16)
			region.put16(0x88, 0)
			region.put16(0x8C, 0)
			region.put32(0x98, 0xFFFFFFFF)
			region.put32(0x9C, 0xFFFFFFFF)
			region.put32(0x94, 0xFFFFFFFF)
		GameMode.TEAM:
			region.rounds_option = 0
			region.put8(0xB5, 4)
			region.put8(0xC2, 4)
			for k in 22:
				region.put16(0xEE - 2 * k, 0)
		GameMode.TIME_ATTACK:
			region.character_change = 0
			fight.ai_difficulty = 1
			region.rounds_option = 1
			fight.round_time_option = 2
			fight.chip_damage = 0
			_clear_stage_records(region)
		GameMode.SURVIVAL:
			fight.ai_difficulty = 1
			region.rounds_option = 0
			fight.round_time_option = 2
			fight.chip_damage = 0
			region.put32(0x90, 0)
			region.put32(0x94, 0)
			region.put32(0x98, 0)
			for k in 22:
				region.put16(0xDA - 2 * k, 0)
			region.put32(0x9C, 0)
			for k in 4:
				region.put32(0xAC - 4 * k, NO_CHARACTER)
		GameMode.PRACTICE:
			region.rounds_option = 0
			fight.round_time_option = 5
			fight.practice = 1
			fight.chip_damage = 0
			tail = false
		GameMode.DEMO:
			globals.controller[0] = 0
			globals.controller[1] = 0
			fight.round_time_option = 2
			fight.attract = 1
			_demo_fighters(g)
			tail = false
		GameMode.FORCE:
			fight.round_time_option = 4
			region.rounds_option = 0
			fight.chip_damage = 0
		_:
			tail = false
	return tail


## FUN_80051644: the arcade and time attack stage records (ten of 8 bytes at 0x800AFF90).
static func _clear_stage_records(region: ModeRegion) -> void:
	for k in 10:
		region.put32(0x90 + 8 * k, 0)
		region.put8(0x94 + 8 * k, 0)
		region.put8(0x95 + 8 * k, 0)
		region.put16(0x96 + 8 * k, 0)


## FUN_800DB54C: the demonstration fight's characters: the next of the list, and a random other
## one; both in their second costume when bit 9 of the total usage is set.
static func _demo_fighters(g: GameFlow) -> void:
	var progress := g.progress
	var globals := g.globals
	var total := 0
	for c in 22:
		total += progress.usage(c)
	var chars := PackedInt32Array()
	for c in g.data.demo_characters:
		if progress.unlocked >> (c & 31) & 1:
			chars.append(c)
	var n := chars.size()
	var i := progress.demo_position + 1
	if n <= i:
		i = 0
	progress.demo_position = i
	var costume := 1 if total & 0x200 else 0
	globals.player_cpu[0] = 1
	globals.player_char[0] = chars[i]
	globals.player_costume[0] = costume
	mirror_costumes(globals, 0)
	globals.player_cpu[1] = 1
	var r := g.fight.vblank & 0xFFF
	var q := r % (n - 1) if n > 1 else r
	globals.player_char[1] = chars[(q + i + 1) % n]
	globals.player_costume[1] = costume
	mirror_costumes(globals, 1)


## FUN_8004F3CC: in a mirror match the side that chose later (unless only the other one is a
## human) takes another costume: 0 and 1 swap, 2 and 3 become 0.
static func mirror_costumes(globals: GameGlobals, player: int) -> void:
	var other := (player + 1) & 1
	var a := PackedInt32Array([globals.player_char[player], globals.player_costume[player],
		globals.player_keep[player], globals.player_active[player]])
	var b := PackedInt32Array([globals.player_char[other], globals.player_costume[other],
		globals.player_keep[other], globals.player_active[other]])
	if b[2] != 0 and a[0] == b[0] and a[1] == b[1]:
		if b[3] == 0 and a[3] != 0:
			b[1] = a[1] ^ 1 if a[1] < 2 else 0
		else:
			a[1] = b[1] ^ 1 if b[1] < 2 else 0
	globals.player_char[player] = a[0]
	globals.player_costume[player] = a[1]
	globals.player_keep[player] = 1
	globals.player_char[other] = b[0]
	globals.player_costume[other] = b[1]
