class_name FightSimulation
extends RefCounted
## One VS match as the game runs it (fight-frame.md): the match set-up (FUN_8002A660), FightMain's
## round transitions (states 5–7, the round start FUN_8002AB68) and FightFrame (0x8002B0AC)
## every frame, with the camera director, the round flow and the replay.
##
## `step` is one frame of the main loop with both pads' physical buttons. Everything that is
## heard or seen goes out as SimEvents; the presentation reads the state and never writes it.
##
## CPU fighters take their input from the AI (CpuOpponent, AiDecision). Tekken Ball (mode 7)
## adds the ball (TekkenBall) and its stand-in attacker in the third record; Tekken Force (mode 8)
## fights with all three records and runs its level (TekkenForce).

const MAIN_NEXT_ROUND := 5
const MAIN_ROUND_START := 7
const MAIN_FIGHT := 8
const LAST_BANK_TYPE := BankType.FORCE_ENEMY
const SLOTS := 0xFB7
const FALLBACK_SLOT := 0xDC5
const PLACEMENT_X := 1000
const PLACEMENT_FACING := 0x4000
const START_HEAD_Y := -0x591         ## FUN_8002BFCC: joint 2's height before the first frame
const START_CHEST_Y := -0x41B        ## joint 1's
const START_SCREEN_X := 100
const STANCE_HOLD := 0x90            ## physical Triangle or Square at round 1: stance slot 0
const STANCE_CHOICE := 0x44          ## Cross or L1: slot 2, else a coin flip between 0 and 2
const LONG_STANCE := 0x96
const LOOK_START := 0x38E
const HAND_SPEED := 10
const SAVED_DISTANCE := 1000
const VS_HANDICAPS := 0x3A           ## mode context: per player (4 bytes apart) the health index

var fight: FightState
var content: FightContent
var setup: FightSetup
var t: FightTables
var moves: MoveSystem
var physics: FighterPhysics
var combat: Combat
var animation: FighterAnimation
var camera: CameraDirector
var round_flow: RoundFlow
var ai: CpuOpponent
var cpu: AiDecision
var practice: PracticeMode             ## practice.ovl's hooks in mode 5 (set by the game flow)
var ball: TekkenBall:                  ## volley.ovl's state and hooks in mode 7 (FightState.ball)
	get: return fight.ball
var loads := 0                         ## fights set up so far (the presentation builds the stage and models again)
## Per record: models swapped in during the fight so far (Tekken Force's enemy variants and boss,
## the Ogre scene's costume): the presentation replaces only that record's model.
var model_loads := PackedInt32Array()
var events := SimEvents.new()
var pads := FighterInput.PadWords.new()
var view := ViewMatrix.new()           ## the frame's camera (after the shake)
var fighter_view := ViewMatrix.new()   ## what the fighters are drawn with (FUN_80036254)
var main_state := MAIN_ROUND_START     ## FightMain's sub-state (0x800AE6EC)
var state_timer := 0                    ## 0x800AE6DC
var finished := false                  ## the match is over (VS: FUN_800B15CC)
var exit_requested := false            ## MenuExitCheck: RESET or Start + Select leaves the fight
var key_tables: Array[PackedInt32Array] = []   ## per player: the mapped word of each physical bit


## A fight simulation; with a set-up it starts that VS match at once (the M2 app and the fight
## trace tests), without one the game flow drives it (GameFlow: load_fighters, round_start,
## fight_frame).
func _init(fight_content: FightContent, fight_setup: FightSetup, rules: RuleSet) -> void:
	content = fight_content
	t = content.tables
	fight = FightState.new(t, rules)
	model_loads.resize(FightState.RECORDS)
	moves = MoveSystem.new(fight)
	physics = FighterPhysics.new(fight, moves)
	combat = Combat.new(fight, moves, physics)
	animation = FighterAnimation.new(fight)
	camera = CameraDirector.new(fight)
	animation.camera = camera
	round_flow = RoundFlow.new(fight)
	ai = CpuOpponent.new(fight, moves)
	cpu = AiDecision.new(ai)
	if fight_setup != null:
		start_vs(fight_setup)


# ==== match and rounds ============================================================================

## A VS match as the fight harness starts one: the VS mode start (FUN_800DAF2C) with the set-up's
## options, FightMain's match counters, the stage, the seeds, then the fighters (FUN_8002A660).
func start_vs(fight_setup: FightSetup) -> void:
	setup = fight_setup
	key_tables = setup.key_tables
	fight.mode = 1
	# The VS mode's feature bytes (FUN_800DAF2C: 0x800AFF54 …).
	fight.pause_allowed = 1
	fight.draw_wins = 1
	fight.carry_health = 0
	fight.team_round = 1
	fight.collapse_on_ko = 1
	fight.tie_choice = 0
	fight.unlocked = setup.unlocked
	fight.round_time_option = setup.round_time
	# Past 60 s the timer is infinite (0x800958D4 set by FUN_800DAF2C).
	fight.timer_stopped = 1 if setup.round_time > 4 else 0
	fight.rounds_option = setup.rounds
	fight.chip_damage = 1 if setup.chip_damage else 0
	fight.human_mask = setup.human_mask()
	fight.ai_difficulty = setup.ai_difficulty
	fight.ai_level = setup.ai_level
	fight.attract = 1 if setup.attract else 0
	fight.stage = setup.stage
	for p in 2:
		fight.region.ctx_put16(VS_HANDICAPS + 4 * p, setup.handicaps[p])
	fight.rng.set_seed(setup.seed)
	fight.camera_rng = setup.seed & 0xFFFFFFFF
	fight.frame_rng = setup.seed & 0xFFFFFFFF
	load_fighters(setup.chars, setup.costumes, setup.cpu)
	main_state = MAIN_ROUND_START


## The mode overlay was (re)loaded (FightPrepare): its data starts from the overlay's image.
func mode_overlay_loaded() -> void:
	fight.ball = null
	fight.force = null


## FightPrepare's FightAllocBuffers: Tekken Ball's ball object, Tekken Force's state (with the
## overlay's data when it was loaded); the fighting records.
func prepare_mode() -> void:
	if fight.mode == GameMode.BALL and fight.ball == null:
		fight.ball = TekkenBall.new(fight)
		fight.ball.load_overlay(content.mode_ram("volley"))
	if fight.mode == GameMode.FORCE and fight.force == null:
		fight.force = TekkenForce.new(fight, content.mode_ram("force"))
	fight.count = FightState.RECORDS if fight.mode == GameMode.FORCE else FightState.FIGHTERS


## FUN_8002A660: the match's fighters (identity, CPU flag, model, health) and round counters.
func load_fighters(chars: PackedInt32Array, costumes: PackedInt32Array, cpu_flags: PackedInt32Array) -> void:
	fight.rounds_played = 0
	fight.rounds_to_win = mini(fight.rounds_option + 1, 5)
	fight.max_rounds = fight.rounds_to_win * 2 - 1
	var ids: Array[PackedInt32Array] = []      # per loaded record: character, costume, CPU flag
	for i in FightState.FIGHTERS:
		ids.append(PackedInt32Array([chars[i], costumes[i], cpu_flags[i]]))
	if fight.mode == GameMode.FORCE:
		ids = _force_fighters(chars, costumes, cpu_flags)
	var ogre_mask := 0
	for i in ids.size():
		var f := fight.fighters[i]
		_identity(f, ids[i][0], ids[i][1])
		f.is_cpu = ids[i][2]
		if f.char_id == Character.TRUE_OGRE:
			ogre_mask |= 1 << i
	fight.true_ogre_mask = ogre_mask
	# FUN_80036854: a stage archive read from the disc (LoadOverlaySync) stops the music
	# (FUN_8006B834, GameFlow.disc_read). Tekken Ball and Tekken Force read theirs every time; the
	# other modes only when the stage in memory is another (the game skips the read in the attract
	# performance's state as well, which loads its stage itself), and then note it.
	if fight.mode == GameMode.BALL or fight.mode == GameMode.FORCE:
		events.add(SimEvents.Kind.MUSIC_STOP, -1)
	else:
		if fight.stage != fight.stage_cached:
			events.add(SimEvents.Kind.MUSIC_STOP, -1)
		fight.stage_cached = fight.stage
		fight.backdrop.setup(camera.view)   # StageBackgroundSetup (FUN_8006CC44)
	if fight.mode == GameMode.FORCE:
		fight.force.level_setup(content.level_script(fight.stage))
	# On the Doctor B. level (TILE_ONLY) the third record keeps its model and parts: FUN_8002A660
	# skips its FUN_80036564, FUN_80035F34 and FUN_80035F3C.
	var loaded := ids.size()
	if fight.mode == GameMode.FORCE and TekkenForce.tile_only_level(fight.region.fight_index):
		loaded = FightState.RECORDS - 1
	for i in ids.size():
		var f := fight.fighters[i]
		# The load leaves the record's matrices (Tekken Force's next level shows the last level's
		# pose on its first fight frame).
		# A record holding no model yet (a session started on that level) still needs one.
		if i < loaded or f.body == null:
			_reload_model(f)
		if fight.mode != GameMode.FORCE:
			f.health_max = _health_max(f)
		f.round_wins = 0
	if fight.mode == GameMode.FORCE:
		var p := fight.force.player()
		p.health_max = _health_max(p)
	if fight.mode == GameMode.BALL:
		# The third record is the ball's attacker (health by mode, FUN_800519B4).
		var third := fight.fighters[FightState.RECORDS - 1]
		third.health_max = _health_max(third)
	fight.replay.recorded = 0
	loads += 1


## FUN_8002A660 in Tekken Force: the player (side 0's pick, or side 1's when side 0 is the CPU)
## is record 0; records 1 and 2 are the level's two enemy variants, or Doctor B. and an enemy on
## the Doctor B. level.
func _force_fighters(chars: PackedInt32Array, costumes: PackedInt32Array, cpu_flags: PackedInt32Array) -> Array[PackedInt32Array]:
	var side := 1 if cpu_flags[0] != 0 else 0
	var lv := fight.stage - ModeRules.FORCE_FIRST_STAGE
	var out: Array[PackedInt32Array] = [PackedInt32Array([chars[side], costumes[side], 0])]
	if fight.region.fight_index < TekkenForce.DOCTOR_LEVEL:
		out.append(PackedInt32Array([TekkenForce.ENEMY, fight.force.enemy_key(lv, 0), 1]))
		out.append(PackedInt32Array([TekkenForce.ENEMY, fight.force.enemy_key(lv, 1), 1]))
	else:
		out.append(PackedInt32Array([Character.DOCTOR_B, 0, 1]))
		out.append(PackedInt32Array([TekkenForce.ENEMY, 0, 1]))
	return out


## FUN_8004F55C: a record's identity from the character record of its costume key.
func _identity(f: FighterState, character: int, costume: int) -> void:
	var key := character * 4 + (costume & 3)
	var record := t.character(mini(key, 0x58) if key > 0x5C else key)
	f.char_id = character
	f.costume_key = key
	f.bank_type = mini(JsonFile.number(record["bank"]), LAST_BANK_TYPE)
	f.voice_set = JsonFile.number(record["voice_set"])
	f.costume_slot = t.fighter.costume_keys[key] if key < 0x5C else -1


## FighterLoadCharacter and FighterSetupParts: the model of the record's costume, its hands and
## face at rest (FUN_80034010, FUN_80034A08).
func _load_model(f: FighterState) -> void:
	f.body = FighterBody.new(content.model(f.costume_slot), t.fighter, t.pose, animation.solver)
	f.move_text = content.move_text(f.costume_slot)
	f.scale_base = f.body.scale_base()
	f.scale = f.scale_base
	setup_parts(f)


## A new model in a record that already holds one: the record's matrices stay.
func _reload_model(f: FighterState) -> void:
	var old := f.body
	_load_model(f)
	if old != null:
		f.body.keep_matrices(old)


## FighterSetupParts' resets (FUN_80034010, FUN_80034A08): the face and the hands at rest.
func setup_parts(f: FighterState) -> void:
	f.hands.face_speed = 0
	f.hands.face = 0
	hands_rest(f)


## A Tekken Force enemy slot's new variant (force.ovl FUN_800B1778 state 3: FUN_800363FC,
## FUN_800360B0, FUN_80035F3C): the model of its costume key.
func reload_enemy(f: FighterState) -> void:
	f.costume_slot = t.fighter.costume_keys[f.costume_key]
	_reload_model(f)
	_model_loaded(f.index)


## A record's model was swapped in during the fight.
func _model_loaded(i: int) -> void:
	model_loads[i] += 1


## FUN_8002D93C: the fighter starts move slot `slot` from its first frame.
func start_move(f: FighterState, slot: int) -> void:
	f.move_slot = slot
	var row := fight.move_for_slot(f, slot)
	f.pose_move = row
	f.root_move = row
	f.move_row = row
	f.pose_frame = 1
	f.entry_frame = 1
	f.transition = FightMath.transition_remap(Transition.FACE_OPPONENT, f.move_row, f.entry_frame)
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	moves.start_or_advance(f, f)


## The Ogre scene's reload of a fighter in a new costume (FighterLoadCharacter,
## FighterSetupParts): its model, hands and the players' merged move index.
func reload_fighter(i: int) -> void:
	var f := fight.fighters[i]
	f.body = FighterBody.new(content.model(f.costume_slot), t.fighter, t.pose, animation.solver)
	f.move_text = content.move_text(f.costume_slot)
	f.scale_base = f.body.scale_base()
	f.scale = f.scale_base
	setup_parts(f)
	_link_banks()
	_model_loaded(i)


## FUN_800519B4: a fighter's full health by mode (16.16): arcade by the human count, VS by the
## handicap chosen on the select screen, team 170, survival 140, practice 200, the demonstration
## 125, other modes 130 (Tekken Force's enemies take theirs from the level runner).
func _health_max(f: FighterState) -> int:
	match fight.mode:
		GameMode.ARCADE:
			return t.health[3 if fight.region.human_count == 2 else 8]
		GameMode.VS:
			return t.health[fight.region.ctx16(VS_HANDICAPS + 4 * f.player_index)]
		GameMode.TEAM:
			return 0xAA0000
		GameMode.SURVIVAL:
			return 0x8C0000
		GameMode.PRACTICE:
			return 0xC80000
		GameMode.DEMO:
			return 0x7D0000
	return 0x820000


## FUN_80034A08: both hands to the costume's own shape, the face and True Ogre's channels at rest.
func hands_rest(f: FighterState) -> void:
	var shape := t.fighter.hand_shape(f.costume_slot) & 0xFF
	for c in 2:
		f.hands.target[c] = shape
		f.hands.current[c] = shape
		f.hands.rate[c] = 0
	f.air_free = 0
	f.hands.wing_frame = 0
	f.hands.wing_phase = 0
	f.hands.ogre_level = 0
	f.hands.ogre_target = 0
	f.hands.ogre_rate = 0
	fight.gon_mouth[f.player_index] = 0


## FUN_8002AB68: the start of a round.
func round_start() -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	fight.round_frame = 0
	fight.round_frame_seen = 0
	fight.rounds_played += 1
	# Tekken Force keeps the timer from level to level.
	if fight.mode != GameMode.FORCE or fight.region.fight_index == 0:
		fight.timer = (fight.round_time_option + 2) * 600
	fight.no_damage = 0
	fight.camera_phase = CameraPhase.RESET
	fight.freeze = 0
	fight.undrawn_mask = 0
	fight.pause_request = 0
	fight.pause_shown = 0
	fight.paused_player = 0
	set_input_mode(0)
	fight.result_flags = 0
	camera.attract_state = 0            # FUN_80063358: the demonstration camera starts again
	fight.ko_started = 0
	fight.replay_skip = 0
	fight.replay_playing = 0
	fight.throw_count = 0
	fight.round_state = RoundState.INTRO
	fight.win_pose_done = PackedInt32Array([0, 0])
	fight.round_counter = 0
	fight.wooden_sounds = PackedInt32Array([0, 0])
	for f: FighterState in [f0, f1]:
		if f.char_id == Character.MOKUJIN:
			_mokujin_bank(f)
			# Down held on the pad: Tekken Force's player on the human's pad.
			var pad := fight.force.human() if fight.mode == GameMode.FORCE and f.index == 0 else f.index
			if pads.physical[pad] & PadState.DOWN:
				fight.wooden_sounds[f.index] = 1
	_link_banks()
	for f in fight.active():
		fight.alt_points[f.index] = 1 if f.char_id == Character.OGRE or f.char_id == Character.MOKUJIN else 0
	fight.replay.reset()
	fight.backdrop.reset()              # FUN_8006CB40, then the background (FUN_8006DAB4)
	background()
	for f in fight.active():
		f.blend_mode = FighterAnimation.Blend.NONE
		f.blend_mode_b = 0
	fight.blend_hold = 0x14
	EffectObjects.round_start(fight)
	events.add(SimEvents.Kind.VOICES_OFF, -1, 1 if fight.rounds_played != 1 else 0)
	for i in 3:
		fight.prev_roots[i][0] = 100
	events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	fight.shake_script = -1
	fight.replay.log_reset()
	fight.health_flash = PackedInt32Array([0, 0])     # FUN_8003A374
	fight.flash_level = PackedInt32Array([0, 0, 0])
	FighterInput.clear(fight, f0)
	FighterInput.clear(fight, f1)
	if fight.mode == GameMode.FORCE:
		FighterInput.clear(fight, fight.fighters[2])
		_force_placement()
	else:
		place(f0, f1)
		place(f1, f0)
	if fight.mode == GameMode.BALL:
		var third := fight.fighters[FightState.RECORDS - 1]
		place(third, f0)
		third.about_to_hit = 1           # FUN_8002C298
	combat.pairwise_distances()
	camera.round_start(f0, f1)
	ai.init_round()
	# FUN_8004E520 (Tekken Force: FUN_800B30DC) and FUN_8004E868.
	if fight.mode == GameMode.FORCE:
		fight.force.bars_reset()
	else:
		RoundHud.reset_bars(fight)
	fight.hud_wins_seen = PackedInt32Array([f0.round_wins, f1.round_wins])
	for f in fight.active():
		var look := f.body.look_at
		look.current = PackedInt32Array([0, LOOK_START, 0, look.current[3]])
		look.active = 0
		look.snap = 1
	fight.replay_request = 0
	if fight.mode == GameMode.BALL:
		ball.drift_clear(0)
		ball.drift_clear(1)
		ball.fight_start(self)
	if fight.mode == GameMode.PRACTICE and practice != null:
		practice.setup()
	events.add(SimEvents.Kind.MUSIC, -1, fight.music)


## FUN_8002AB68 in Tekken Force: the player and both enemy records at the origin facing +x (the
## Doctor B. level: the player at −1000, the others at +1000), placed where they stand; the
## enemies hidden until their slots bring them in.
func _force_placement() -> void:
	var p := fight.force.player()
	var e0 := fight.force.slot_fighter(0)
	var e1 := fight.force.slot_fighter(1)
	var doctor := fight.region.fight_index >= TekkenForce.DOCTOR_LEVEL
	p.pos_x = -PLACEMENT_X if doctor else 0
	e0.pos_x = PLACEMENT_X if doctor else 0
	e1.pos_x = PLACEMENT_X if doctor else 0
	for f: FighterState in [p, e0, e1]:
		f.pos_z = 0
		f.facing = PLACEMENT_FACING
	place(p, e0, false)
	place(e0, p, false)
	place(e1, p, false)
	for e: FighterState in [e0, e1]:
		e.active = 0
		e.invulnerable = 1


## FUN_8004F5C4: Mokujin takes the moves of a random unlocked character each round (frame
## generator 0x8009F650 against the unlock mask 0x800982D0).
func _mokujin_bank(f: FighterState) -> void:
	var mask := fight.unlocked & 0x13FFF
	var count := 0
	for b in 32:
		if mask & (1 << b):
			count += 1
	var pick := _frame_random() & 0xFFF
	var chosen := 0
	var seen := 0
	for b in 0x16:
		if mask & (1 << b):
			if seen == pick % count:
				chosen = b
				break
			seen += 1
	var key := mini(chosen << 2, 0x58)
	f.bank_type = JsonFile.number(t.character(key)["bank"])


## FUN_8004D13C: one step of the frame generator; its value.
func _frame_random() -> int:
	fight.frame_rng = (fight.frame_rng * 5 + 1) & 0xFFFFFFFF
	return fight.frame_rng


## FUN_8006A440: the players' banks (DivmotLinkBank) and DivmotMergeSharedSlots: a slot empty in
## one bank takes the other bank's move, or slot 0xDC5 when both lack it.
func _link_banks() -> void:
	var banks: Array[MotionBank] = []
	for f in fight.active():
		f.bank = content.bank(f.bank_type)
		banks.append(f.bank)
	fight.slots = [_slot_rows(fight.fighters[0].bank_type), _slot_rows(fight.fighters[1].bank_type)]
	var own: Array = fight.slots[0]
	var other: Array = fight.slots[1]
	var fallback_own: MoveRow = own[FALLBACK_SLOT]
	var fallback_other: MoveRow = other[FALLBACK_SLOT]
	for s in SLOTS:
		var empty_own := banks[0].slot_empty(s)
		var empty_other := banks[1].slot_empty(s)
		if empty_own:
			own[s] = other[s] if not empty_other else fallback_own
		if empty_other:
			other[s] = own[s] if not empty_own else fallback_other


func _slot_rows(bank_type: int) -> Array:
	var bank := content.bank(bank_type)
	var own := content.rows(bank_type)
	var rows := []
	rows.resize(SLOTS)
	for s in mini(SLOTS, bank.move_index.size()):
		var entry := bank.move_index[s]
		if entry == MotionBank.EMPTY_SLOT:
			continue
		rows[s] = content.common_rows[entry - MotionBank.COMMON_FLAG] if entry >= MotionBank.COMMON_FLAG else own[entry]
	return rows


## FUN_8002BFCC: the fighter placed facing `opp`, everything the round resets, its stance. A
## fresh placement puts it at ±1000 facing the other side; otherwise it stays where its anchor
## and facing are (Tekken Ball and Tekken Force set them first).
func place(f: FighterState, opp: FighterState, fresh := true) -> void:
	var x := f.pos_x
	var z := f.pos_z
	var facing := f.facing
	if fresh:
		x = -PLACEMENT_X if f.index == 0 else PLACEMENT_X
		z = 0
		facing = PLACEMENT_FACING if f.index == 0 else -PLACEMENT_FACING
	f.cur_opp_index = opp.index
	# FighterSavePlacement (before the new position is set).
	f.dist = SAVED_DISTANCE
	f.dir_x = SAVED_DISTANCE
	f.dir_z = SAVED_DISTANCE
	f.placed_x = f.pos_x
	f.placed_z = f.pos_z
	_start_stance(f, opp)
	_set_position(f, x, z, facing)
	if fight.carry_health != 0 and f.carried_health != 0 and f.carried_health <= f.health_max:
		f.health = f.carried_health
	else:
		f.health = f.health_max
	_clear_round_state(f)
	Combat.clear_hit_slots(f)
	f.best_hit_slot = 0
	FighterSounds.script_stop(f)
	_hurt_radii(f)
	f.hands.command(3, t.fighter.hand_shape(f.costume_slot), HAND_SPEED, f.char_id)
	f.prev_root_x = f.root_x
	f.prev_root_y = f.root_y
	f.prev_root_z = f.root_z


## The fighter stands at (x, z) facing `facing`, the head and chest joints above it.
func _set_position(f: FighterState, x: int, z: int, facing: int) -> void:
	f.facing = facing
	f.pos_x = x
	f.pos_y = 0
	f.pos_z = z
	f.tilt_x = 0
	f.tilt_z = 0
	f.heading = facing
	f.rel_angle = facing
	f.screen_x = -START_SCREEN_X if f.index == 0 else START_SCREEN_X
	if f.body != null:
		f.body.joints[2].t = PackedInt32Array([x, START_HEAD_Y, z])
		f.body.joints[1].t = PackedInt32Array([x, START_CHEST_Y, z])
	f.root_x = x
	f.root_z = z
	f.body_push_x = 0
	f.body_push_y = 0
	f.body_push_z = 0


## The per-round state cleared: movement, reactions, hits, timers and blending.
func _clear_round_state(f: FighterState) -> void:
	f.hold_frames = -1
	f.health_left = 0
	f.hit_freeze = 0
	f.slide_state = 0
	f.ballistic = 0
	f.juggle_count = 0
	f.air_vel_x = 0
	f.air_vel_y = 0
	f.air_vel_z = 0
	f.crouch_move = 0
	f.was_hit_this_move = 0
	f.guarded_prev = 0
	f.in_reaction = 0
	f.attack_class = 0
	f.cond_flag_used = 0
	f.move_flag_ba = 0
	f.move_flag_bb = 0
	f.attack_pending = 0
	f.air_phase = 0
	f.round_won = 0
	f.win_pose = 0
	f.hit_cooldown = 0
	f.push_frames = 0
	f.push_table_frames = 0
	f.turn_frames = 0
	f.turn_step = 0
	f.recover_mash = 0
	f.recover_frames = 0
	f.push_repeat = 0
	f.push_repeat_timer = 0
	f.power_timer = 0
	f.step_cooldown = 0
	f.last_extra_damage = 0
	f.counter_hit = 0
	f.close_hit = 0
	f.guarded = 0
	f.hit_clean = 0
	f.ko = 0
	f.last_damage = 0
	f.in_air = 0
	f.extra_damage = 0
	f.anchor_dirty = 0
	f.slide_to_point = 0
	f.reset_flag_c0 = 0
	f.apply_end_turn = 0
	f.invulnerable = 0
	f.active = 1
	f.in_throw = 0
	f.no_look_at = 0
	f.fixed_facing = 0
	f.blend_frames = 0
	f.blend_counter = 0
	f.blend_weight = 0
	f.blend_root_delta = PackedInt32Array([0, 0, 0])


## HurtRadiusSetup (0x8003F2DC): the hurt cylinders' radii of the character.
func _hurt_radii(f: FighterState) -> void:
	var radii := t.hurt_radii[f.char_id]
	for k in 14:
		var r := radii[k]
		f.hurt_zones[k][3] = r
		f.hurt_zones[k][4] = r * r


## FUN_800B2B3C (FightMain sub-state 23, Tekken Force's area change): enemy slot 0 becomes the
## level's boss (by the player's costume, force.ovl's table), loaded with its model and music,
## 4,096 units ahead of the camera with the boss health, and starts its entrance (move slot 3).
func force_boss() -> void:
	var force := fight.force
	var p := force.player()
	var boss := force.slot_fighter(0)
	var x := p.pos_x
	var z := p.pos_z
	var pick := force.boss_of(p.costume_key)
	_identity(boss, pick.x, pick.y)
	events.add(SimEvents.Kind.FORCE_NAMES, -1, 1, pick.x)
	fight.region.ctx_put8(TekkenForce.BOSSES + (force.level() & 3), pick.x * 4 + pick.y)
	if boss.char_id == Character.MOKUJIN:
		_mokujin_bank(boss)
	_link_banks()
	_reload_model(boss)
	setup_parts(p)
	_model_loaded(boss.index)
	fight.music = JsonFile.number(t.character(boss.costume_key)["music"])
	events.add(SimEvents.Kind.MUSIC, -1, fight.music)
	var s := TekkenForce.slot(0)
	force.put16(s + 0xE, 4)
	force.put16(s + 8, 1)
	force.put16(s + 0xA, 0)
	start_move(boss, 3)
	TekkenForce.place(boss, camera.view.x + TekkenForce.BOSS_AHEAD, 0)
	boss.active = 1
	var hp := force.ram.s32(TekkenForce.ENEMY_HEALTH + 4 * 4 + force.level() * 0x14)
	boss.invulnerable = 0
	boss.pos_y = 0
	boss.ballistic = 0
	boss.air_phase = 0
	boss.health_max = hp
	boss.health = hp
	_hurt_radii(boss)
	TekkenForce.place(p, x, z)


## FighterStartStance (0x8002D570): the stance move of the round start. In the first round the
## physical buttons held choose it (or a coin flip).
func _start_stance(f: FighterState, opp: FighterState) -> void:
	var held := pads.physical[0 if f.index == 0 else 1]
	var slot := 1
	if fight.rounds_played == 1 and fight.mode != GameMode.BALL:
		if held & STANCE_HOLD:
			slot = 0
		else:
			slot = 2
			if held & STANCE_CHOICE == 0 and fight.rng.next() & 1:
				slot = 0
	f.move_slot = slot
	var row := fight.move_for_slot(f, slot)
	f.pose_move = row
	f.root_move = row
	f.move_row = row
	var start := 1
	if fight.rounds_played == 1 and f.pose_move.length > LONG_STANCE:
		start = f.pose_move.length - (LONG_STANCE - 1)
	f.pose_frame = 1
	f.entry_frame = 1
	f.transition = FightMath.transition_remap(Transition.FACE_OPPONENT, f.move_row, f.entry_frame)
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	moves.start_or_advance(f, opp)
	f.root_frame = start
	f.pose_frame = start


## FUN_8002BE54: every fighter's input cleared and its input mode set.
func set_input_mode(mode: int) -> void:
	for f in fight.fighters:
		FighterInput.clear(fight, f)
		fight.input_mode[f.index] = mode


# ==== main loop ===================================================================================

## The main loop's work before the game state runs (main 0x80028DF4): the frame counters, the
## random generators its vertical-blank wait steps (once per frame at 60 fps), the display
## buffer and the pads (FUN_8002A014 with the key configuration `tables`).
func begin_frame(buttons: PackedInt32Array, tables: Array[PackedInt32Array]) -> void:
	events.clear()
	fight.effects.lights.clear()
	fight.frame_counter += 1
	fight.vblank = fight.frame_counter
	fight.display_buffer = fight.frame_counter & 1
	fight.camera_rng = ((fight.camera_rng + 1) * 0x10DCD) & 0xFFFFFFFF
	fight.frame_rng = (fight.frame_rng * 5 + 1) & 0xFFFFFFFF
	pads.read(buttons, tables)


## One frame of the main loop in the fight: `buttons` are the pads' physical words.
func step(buttons: PackedInt32Array) -> void:
	begin_frame(buttons, key_tables)
	if PauseMenu.exit_requested(fight, pads):
		exit_requested = true
	match main_state:
		MAIN_NEXT_ROUND:
			main_state = 6
		6:
			main_state = MAIN_ROUND_START
		MAIN_ROUND_START:
			camera.overhead = 0
			round_start()
			fight.hud_shown = 1
			state_timer = 8
			main_state = MAIN_FIGHT
		MAIN_FIGHT:
			if state_timer != 0:
				state_timer -= 1
			var result := fight_frame()
			if result >= RoundState.END:
				if fight.match_result == 0:
					main_state = MAIN_NEXT_ROUND
				else:
					finished = true


## FightFrame (0x8002B0AC); returns the round state.
func fight_frame() -> int:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var a := f1 if f0.is_cpu != 0 else f0
	var b := f0 if f0.is_cpu != 0 else f1
	var c := fight.fighters[2]
	if fight.mode == GameMode.FORCE:
		# FUN_800B5EC0: the player, the enemy it faces and the other one.
		var r := fight.force.roles(moves, pads)
		a = r[0]
		b = r[1]
		c = r[2]
	else:
		a.opp_index = b.index
		b.opp_index = a.index
		a.cur_opp_index = b.index
		b.cur_opp_index = a.index
	_pause_check()
	fight.blend_enabled = 1
	if fight.freeze == 0 and fight.paused_player == 0:
		round_flow.replay_request_check(self)
		fight.replay_playing = round_flow.replay_update(self)
		round_flow.step(self)
		if fight.replay_playing == 0:
			RoundHud.update(fight, events)
			_frame(a, b, c)
		else:
			_replay_frame()
	elif fight.replay_playing == 0:
		f0.ogre_freeze = 1
		f1.ogre_freeze = 1
		RoundHud.update(fight, events)
		_draw_frame()
		EffectObjects.update(fight, false, events)
		if fight.mode == GameMode.FORCE:
			fight.force.level_frame(self, events)
		if fight.mode == GameMode.BALL:
			_ball_frame()
		if fight.challenger == 0 and fight.mode != GameMode.PRACTICE:
			PauseMenu.step(fight, fight.paused_player, pads, events)
		events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_HOLD)
		for f in fight.active():
			FighterInput.source(fight, f, pads, cpu)
		FighterInput.latch_taps(fight, f0)
	else:
		_draw_frame()
		EffectObjects.update(fight, false, events)
		events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_HOLD)
	if fight.mode == GameMode.PRACTICE and practice != null:
		fight.practice_paused = practice.frame()
	return fight.round_state


## The fight's own frame (FightFrame without pause, replay or freeze). Tekken Force runs every
## per-fighter step for the third record too, tests hits between all three, and ends with its
## level runner.
func _frame(a: FighterState, b: FighterState, c: FighterState) -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	var all := fight.active()
	var force := fight.mode == GameMode.FORCE
	camera.step(f0, f1)
	FighterInput.update_side(a, b)
	FighterInput.update_side(b, a)
	if force:
		FighterInput.update_side(c, a)
	_camera_frame()
	for f in all:
		combat.save_prev_segments(f)
	moves.start_all()
	if fight.mode == GameMode.BALL:
		ball.move_tuning(f0)
		ball.move_tuning(f1)
	fight.throw_count = combat.count_throws()
	combat.pairwise_distances()
	var logged := events.items.size()
	for f in all:
		physics.update(f, events)
	_log_effects(logged)
	combat.save_position(f0)
	combat.save_position(f1)
	if fight.mode == GameMode.BALL or force:
		combat.save_position(fight.fighters[FightState.RECORDS - 1])
	animation.update_all(fighter_view, fight.blend_enabled != 0, true)
	for f in all:
		combat.arena_bounds(f)
	combat.update_throw_link()
	for f in all:
		combat.throw_anchor(f)
	combat.ramp_step()
	background()
	EffectObjects.descriptor_spawn(fight, f0, true, events)
	EffectObjects.descriptor_spawn(fight, f1, true, events)
	EffectObjects.update(fight, fight.blend_enabled != 0, events)
	Vibration.hits(fight, events)
	for f in all:
		Combat.velocity(f)
	for f in all:
		combat.collision_shapes(f, f.body.joints)
	for f in all:
		combat.body_sphere_profile(f)
	combat.clear_contacts()
	if fight.camera_phase < CameraPhase.WINNER_0:
		combat.body_separate(f0, f1)
		if force:
			combat.body_separate(f0, fight.fighters[2])
			combat.body_separate(f1, fight.fighters[2])
	for f in all:
		Combat.clear_hit_slots(f)
	combat.hit_test(a, b, events)
	combat.hit_test(b, a, events)
	if force:
		combat.hit_test(a, c, events)
		combat.hit_test(c, a, events)
		combat.hit_test(b, c, events)
		combat.hit_test(c, b, events)
	for f in all:
		Combat.attack_velocity(f)
	moves.branch_all()
	if fight.mode == GameMode.BALL:
		_ball_frame()
	logged = events.items.size()
	for f in all:
		MoveEvents.run(f, t.fighter, events)
	_log_effects(logged)
	move_event_calls(logged)
	for f in all:
		_clear_hit_flags(f)
	for f in all:
		combat.hit_apply(f, events)
	for f in all:
		if f.active != 0:
			FighterSounds.run(fight, f, fight.opponent(f), events)
	# FUN_8002BDAC: the loser camera (phases 6 and 7) neither draws nor steps the flipbooks.
	if fight.camera_phase < CameraPhase.LOSER_0 or fight.camera_phase > CameraPhase.LOSER_1:
		events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
		fight.replay.log_advance()
	for f in all:
		FighterInput.source(fight, f, pads, cpu)
	for f in all:
		FighterInput.latch_taps(fight, f)
	for f in all:
		f.event_frame = f.pose_frame
	moves.step_all()
	fight.round_frame_seen = fight.round_frame
	if force and fight.force.level_frame(self, events):
		fight.round_state = RoundState.AREA_CHANGE


## FUN_8006DAB4: the background. Tekken Force's panorama keeps the camera's view-space x, which
## its walls read; a panorama turns with the camera (StageBackgroundDraw; not drawn in Tekken Ball
## and True Ogre fights). The drawing is the presentation's.
func background() -> void:
	if fight.mode == GameMode.FORCE:
		fight.force.background(view, camera.view)
	elif fight.mode != GameMode.BALL and fight.true_ogre_mask == 0:
		fight.backdrop.step(camera.view, fight.round_state, t.pose, t.camera)


## The effect log (FUN_8004A840 / FUN_8004A860) of the flipbooks and dust rings the events from
## `from` on start: move events 6–10 as flipbooks, ground impacts and landings as dust rings.
func _log_effects(from: int) -> void:
	var zero := PackedInt32Array([0, 0, 0])
	for i in range(from, events.items.size()):
		var e := events.items[i]
		match e.kind:
			SimEvents.Kind.EFFECT:
				fight.replay.log_effect(e.a, 0, e.point, zero, 0)
			SimEvents.Kind.SPARK:
				fight.replay.log_effect(3, e.a, e.point, zero, 0)
			SimEvents.Kind.DUST, SimEvents.Kind.LANDING_DUST:
				fight.replay.log_effect(0, 0, e.point, zero, 1)


## MoveEvents' FighterVibrate and CameraShakeStart calls from `from` on, run in place: the
## requests are replaced by the events the calls produce.
func move_event_calls(from: int) -> void:
	var tail := events.items.slice(from)
	events.items = events.items.slice(0, from)
	for e: SimEvents.Event in tail:
		match e.kind:
			SimEvents.Kind.FIGHTER_VIBRATE:
				Vibration.fighter(fight, e.fighter, e.a, events)
			SimEvents.Kind.SHAKE_REQUEST:
				CameraShake.start(fight, e.a, events)
			_:
				events.items.append(e)


## FUN_80045260: the previous frame's hit outcome flags.
static func _clear_hit_flags(f: FighterState) -> void:
	f.last_damage = 0
	f.close_hit = 0
	f.guarded = 0
	f.hit_clean = 0
	f.counter_hit = 0
	f.ko = 0


## CameraShakeStep, CameraFrame (the view) and FUN_80036254 (the fighters' view).
func _camera_frame() -> void:
	camera.view.pitch += CameraShake.step(fight)
	view_frame()


## CameraFrame (the view) and FUN_80036254 (the fighters' view), without the shake: the Ogre
## scene's camera frame.
func view_frame() -> void:
	view = ViewMatrix.build(camera.view, t)
	fighter_view = view.fighter_view(camera.overhead != 0)


## A frame that only draws (pause or freeze): the HUD, the view and the skeletons.
func _draw_frame() -> void:
	view = ViewMatrix.build(camera.view, t)
	fighter_view = view.fighter_view(camera.overhead != 0)
	animation.update_all(fighter_view, fight.blend_enabled != 0, true)
	background()


## The replay's frame (FightFrame with a playing replay): the blend and the effects run on the
## even half frames only; Start ends the replay.
func _replay_frame() -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	fight.blend_enabled = (fight.replay.play ^ 1) & 1
	if fight.mode != GameMode.PRACTICE and round_flow.start_pressed(self):
		fight.replay.skip = 1
		fight.replay_skip = 1
	if fight.mode == GameMode.BALL:
		camera.step(f0, f1)
	else:
		camera.replay_step(f0, f1)
	_camera_frame()
	var enabled := fight.blend_enabled != 0
	animation.update_all(fighter_view, enabled, true)
	background()
	EffectObjects.descriptor_spawn(fight, f0, enabled, events)
	EffectObjects.descriptor_spawn(fight, f1, enabled, events)
	EffectObjects.update(fight, enabled, events)
	# FUN_8004A954 replays the log, then draws the dust rings and flipbooks (FUN_8004AEBC,
	# FUN_80077744), stepping them with the same flag.
	if enabled:
		EffectObjects.play_log(fight, events)
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE if enabled else SimEvents.EFFECTS_HOLD)
	if fight.mode == GameMode.BALL:
		_ball_frame()


## FUN_800B0E14 with the frame's camera (the popups keep it).
func _ball_frame() -> void:
	ball.view = view
	ball.frame(self, events)


## FUN_8002B9EC: the pause request (Start of a human in round state 1) and its sound. In
## practice the player's Start pauses (the first pause comes by itself while practice waits).
func _pause_check() -> void:
	var p0 := fight.human_mask & 1 != 0 and pads.physical_pressed[0] & PadState.START != 0
	var p1 := fight.human_mask & 2 != 0 and pads.physical_pressed[1] & PadState.START != 0
	if fight.mode == GameMode.PRACTICE:
		if fight.replay_playing != 0:
			p0 = false
			p1 = false
		elif fight.practice_intro != 0:
			p0 = fight.tie_choice == 0
			p1 = fight.tie_choice == 1
		else:
			p0 = fight.tie_choice == 0 and pads.physical_pressed[0] & PadState.START != 0
			p1 = fight.tie_choice == 1 and pads.physical_pressed[1] & PadState.START != 0
	if fight.pause_allowed == 0 or fight.round_state != RoundState.FIGHT:
		fight.pause_request = 0
	elif fight.pause_request == 0:
		if p0:
			fight.pause_request = 1
		if p1:
			fight.pause_request = 2
	if fight.pause_page == PauseMenu.PAGE_CANCEL:
		fight.pause_request = 0
		fight.pause_page = 0
	if fight.pause_close != 0:
		fight.pause_request = 0
		fight.pause_close = 0
	if fight.pause_request != fight.pause_shown:
		if fight.pause_request == 0:
			fight.pause_page = 0
		else:
			fight.pause_cursor = PauseMenu.OPENED
		events.add(SimEvents.Kind.MUSIC_VOLUME, -1, 0x7F if fight.pause_request == 0 else 0x1E, 0x14)
	fight.pause_shown = fight.pause_request
	fight.paused_player = fight.pause_request
	if fight.round_frame == 0:
		fight.paused_player = 0
