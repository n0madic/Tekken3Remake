class_name ArcadeSimulation
extends FightSimulation
## One match of the arcade program (World ver. E1): the game flow's fighter sub-states 4–7 around
## FUN_8018A44C (the match), FUN_8018A6D0 (a round) and FUN_8018A988 (a frame). Two records, no pause
## menu, no Tekken Ball or Force. Proven by tests/fight/test_arcade_fight_traces.gd.

const SCENE_KEYS := 0x58                 ## FUN_8019CB04
const MODEL_DRAWS := 4                   ## FUN_801E6ACC
const SUB_LOAD := 4
const SUB_ROUND := 6
const SUB_FIGHT := 7
const START_ROUND_HOLD := 0x14
const SAVED_DISTANCE_START := 100
const FAR_APART := 0x1CFF               ## FUN_8018B124: above it a jump of the roots is undone
const WIDE_CHARACTERS: Array[int] = [0xB, 0x14]
const WIDE_DISTANCE := 40
const STANCE_PUNCHES := 0x300           ## the panel's punches at round 1: stance slot 0
const STANCE_KICKS := 0xC0              ## kicks: slot 2, else a coin flip between 0 and 2
const DEMO_HEALTH := 0x7D0000


## A match's choices and the operator's settings it reads.
class Match:
	var mode := GameMode.ARCADE as int
	var chars := PackedInt32Array([0, 1])
	var costumes := PackedInt32Array([0, 0])
	var cpu := PackedInt32Array([0, 0])
	var joined := 3                     ## 0x80374F33: the players who have joined
	var start_locked := 0               ## 0x8021FC5C
	var stage := 0
	var rounds := 1                     ## 0x80374F36: rounds to win − 1
	var round_time := 2                 ## 0x8021FC84
	var neutral_guard := 0              ## 0x8021FC70
	var life := 0                       ## 0x8021FC54 with two humans, else 0x8021FDD0
	var one_player_table := false       ## 0x8021FB74 == 1
	var cpu_group := 0                  ## 0x8021FB74: the CPU's parameter group (FUN_801C2FCC)
	var difficulty := 1                 ## 0x8021FD28
	var level := 0                      ## 0x8021FD40
	var attract := 0                    ## 0x8021FC64


var panels := ArcadeInput.Panels.new()
var saved_x := PackedInt32Array([0, 0]) ## 0x8021FE00: last frame's roots
var saved_z := PackedInt32Array([0, 0]) ## 0x8021FE08
var saved_distance := 0                 ## 0x8021F614
var distance_adjusted := 0              ## 0x8021FDC0
var match_choice: Match
var winner_frames := 0                 ## 0x8021F04C
var arcade_combat: ArcadeCombat
var sounds: ArcadeSounds
var round_sounds := ArcadeRoundSounds.new()
var effect_objects: ArcadeEffectObjects
var wind := ArcadeWind.new()
var in_match := true                ## 0x8021FD20 is the match's state: the wind blows only then
var _attachment_tables: ArcadeAttachmentTables


func _make_parts() -> void:
	moves = ArcadeMoveSystem.new(fight)
	physics = ArcadeFighterPhysics.new(fight, moves)
	sounds = ArcadeSounds.new(fight)
	arcade_combat = ArcadeCombat.new(fight, moves, physics)
	combat = arcade_combat
	animation = ArcadeAnimation.new(fight)
	camera = ArcadeCamera.new(fight)
	combat.camera = camera
	animation.camera = camera
	round_flow = ArcadeRoundFlow.new(fight, panels)
	fight.replay = ArcadeReplay.new()
	ai = ArcadeCpu.new(fight, moves)
	cpu = ArcadeAiDecision.new(ai)
	effect_objects = ArcadeEffectObjects.new(fight, (content as ArcadeFightContent).effect_tables)
	arcade_combat.effect_objects = effect_objects
	_attachment_tables = (content as ArcadeFightContent).attachment_tables(animation.solver)
	wind.tables = _attachment_tables
	(animation as ArcadeAnimation).wind = wind


## The main loop's work before the flow runs (FUN_8018CD30 for the panels).
func begin_panels(words: PackedInt32Array) -> void:
	_tick_counters()
	panels.read(words)


## FUN_801B6BA4's sub-state `sub` for one frame.
func flow_step(sub: int) -> void:
	match sub:
		SUB_LOAD:
			start_match(match_choice)
		SUB_ROUND:
			round_start()
		SUB_FIGHT:
			if fight_frame() == ArcadeRoundFlow.FINISHED:
				(fight.replay as ArcadeReplay).store_round(fight)


# ==== match and rounds ============================================================================

## FUN_8018A44C.
func start_match(choice: Match) -> void:
	match_choice = choice
	(fight.replay as ArcadeReplay).stored = 0
	(moves as ArcadeMoveSystem).neutral_guard = choice.neutral_guard
	fight.mode = choice.mode
	fight.stage = choice.stage
	fight.rounds_option = choice.rounds
	fight.round_time_option = choice.round_time
	fight.human_mask = choice.joined
	fight.region.human_mask = choice.joined
	(round_flow as ArcadeRoundFlow).start_locked = choice.start_locked
	fight.ai_difficulty = choice.difficulty
	fight.ai_level = choice.level
	fight.attract = choice.attract
	(ai as ArcadeCpu).region_word = choice.cpu_group
	round_sounds.before_load()
	load_fighters(choice.chars, choice.costumes, choice.cpu)
	round_sounds.after_load()


func load_fighters(chars: PackedInt32Array, costumes: PackedInt32Array, cpu_flags: PackedInt32Array) -> void:
	fight.rounds_played = 0
	fight.rounds_to_win = mini(fight.rounds_option + 1, 5)
	fight.max_rounds = fight.rounds_to_win * 2 - 1
	for i in FightState.FIGHTERS:
		var f := fight.fighters[i]
		_identity(f, chars[i], costumes[i])
		f.bank_type = mini(f.bank_type, LAST_BANK_TYPE)
		f.is_cpu = cpu_flags[i]
		f.active = 1
		_load_model(f)
		f.health_max = _health_max(f)
		f.round_wins = 0
	loads += 1


func _load_model(f: FighterState) -> void:
	_set_model(f)
	model_draws(f)


## A new model in the record: the matrices it holds stay, so the first frame reads the last pose
## (True Ogre's sway height comes from joint 6 of the frame before).
func _set_model(f: FighterState) -> void:
	var old := f.body
	f.body = ArcadeBody.new(content.model(f.costume_slot), t.fighter, t.pose, animation.solver, _attachment_tables)
	if old != null:
		f.body.keep_matrices(old)
	f.scale_base = f.body.scale_base()
	f.scale = f.scale_base
	f.hands = ArcadeHands.new(t.fighter, f.costume_slot)


## FUN_801E6ACC, the end of a model's setup: the wind of a match on the helicopter stage, then four
## numbers of `rand` for a fighter (+0x1270, +0x1272 twice over), which the program never reads.
func model_draws(f: FighterState) -> void:
	if f.index == 0:
		wind.calm()
		if in_match and fight.stage == ArcadeWind.STAGE:
			wind.blow(fight.rng.next())
			fight.rng.next()
			fight.rng.next()
	if f.costume_slot in ArcadeAttachments.REST_ONLY_SLOTS:
		wind.calm()
	for i in MODEL_DRAWS:
		fight.rng.next()


## FUN_801B7C50 in the game's modes 0 and 6, the two the arcade's flow has.
func _health_max(_f: FighterState) -> int:
	if match_choice.mode == GameMode.DEMO:
		return DEMO_HEALTH
	var table := t.health_one_player if match_choice.one_player_table else t.health_two_players
	return table[match_choice.life]


## FUN_8018EC9C: every bank type has its own full table of slots.
func _link_banks() -> void:
	for f in fight.active():
		f.bank = content.bank(f.bank_type)
	var c := content as ArcadeFightContent
	fight.slots = [c.slot_rows(fight.fighters[0].bank_type), c.slot_rows(fight.fighters[1].bank_type)]


## FUN_801B5224 for each Mokujin: the moves of a random unlocked character; Down held, wooden sounds.
func _mokujin_rounds(f0: FighterState, f1: FighterState) -> void:
	fight.wooden_sounds = PackedInt32Array([0, 0])
	for f: FighterState in [f0, f1]:
		if f.char_id == Character.MOKUJIN:
			_mokujin_bank(f)
			if panels.held[f.index] & ArcadeInput.PANEL_DOWN:
				fight.wooden_sounds[f.index] = 1


## FUN_8018A6D0.
func round_start() -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	fight.undrawn_mask = 0
	fight.round_frame = 0
	fight.round_frame_seen = 0
	fight.no_damage = 0
	fight.camera_phase = CameraPhase.RESET
	fight.paused_player = 0
	fight.freeze = 0
	fight.input_mode[0] = 0
	fight.input_mode[1] = 0
	fight.rounds_played += 1
	fight.timer = (fight.round_time_option + 2) * 600
	fight.result_flags = 0
	f0.active = 1
	f1.active = 1
	fight.round_state = RoundState.INTRO
	fight.round_counter = 0
	fight.round_end_done = 0
	fight.replay_request = 0
	fight.replay_skip = 0
	fight.replay_playing = 0
	fight.replay.reset()
	fight.ko_started = 0
	(camera as ArcadeCamera).shake_stop()
	events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	fight.replay.log_reset()
	_mokujin_rounds(f0, f1)
	_link_banks()
	for f: FighterState in [f0, f1]:
		f.blend_mode = FighterAnimation.Blend.NONE
		f.blend_mode_b = 0
	fight.blend_hold = START_ROUND_HOLD
	sounds.ko_voiced.fill(0)
	ArcadeInput.clear(f0, panels)
	ArcadeInput.clear(f1, panels)
	_place(f0, f1)
	_place(f1, f0)
	_settle(f0, f1)
	camera.round_start(f0, f1)
	effect_objects.round_start()
	round_sounds.round_start(events)
	(ai as ArcadeCpu).init_round()
	_reset_look_at()                    # FUN_801992B0
	wind.round_start()


# ==== the scripted scenes =========================================================================

## FUN_8019CB04: the first costume key that has the model; the fighter takes its model and the moves
## of its character (FUN_8018EC9C), keeping its voices.
func scene_model(i: int, model_slot: int) -> void:
	var f := fight.fighters[i]
	var key := _scene_key(model_slot)
	f.costume_key = key
	f.char_id = key >> 2
	f.bank_type = key >> 2
	f.costume_slot = model_slot
	_set_model(f)
	_link_banks()
	_model_loaded(i)


## FUN_8019CB04's search: the first costume key that has the model, 0 when none has it.
func _scene_key(model_slot: int) -> int:
	for at in SCENE_KEYS:
		if t.fighter.costume_keys[at] == model_slot:
			return at
	return 0


## The demonstration's fighters: its view is built anew for them and its stage.
func scene_fighters(model_slots: PackedInt32Array) -> void:
	for i in FightState.FIGHTERS:
		var f := fight.fighters[i]
		f.active = 1
		var key := _scene_key(model_slots[i])
		f.costume_key = key
		f.char_id = key >> 2
		f.bank_type = key >> 2
		f.costume_slot = model_slots[i]
		_load_model(f)
	_link_banks()
	loads += 1


## FUN_8019CCEC for both, FUN_8018C8BC.
func scene_place() -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	for f: FighterState in [f0, f1]:
		f.blend_mode = FighterAnimation.Blend.NONE
		f.blend_mode_b = 0
	fight.blend_hold = START_ROUND_HOLD
	_place(f0, f1)
	_place(f1, f0)


## A scene's fighter one frame on: its frame events, its skeleton. FUN_8018C5A4 fires the events of
## both fighters for each one playing (game bug: see game-bugs.md): each fires once here.
func scene_frame(f: FighterState) -> void:
	var first := events.items.size()
	MoveEvents.run(f, t.fighter, events)
	_log_effects(first)
	move_event_calls(first)
	fight.blend_skip = 1
	(animation as ArcadeAnimation).animate_arcade(f)


## FUN_801969C8: the stage and fighters of a kept fight, in its replay; false when none was kept.
func load_kept_fight(slot: int) -> bool:
	var replay := fight.replay as ArcadeReplay
	if slot >= ArcadeReplay.SLOTS or replay.kept[slot].stage == ArcadeReplay.NO_STAGE:
		return false
	var kept := replay.kept[slot]
	var played := fight.rounds_played
	replay.stored = 0
	fight.stage = kept.stage
	load_fighters(kept.chars, kept.costumes, PackedInt32Array([0, 0]))
	fight.rounds_played = played
	replay.restore_logs(slot)
	round_start()
	fight.fighters[0].round_won = 1
	replay.play_kept(slot)
	return true


## FUN_8018AE8C: a frame of the winner alone, with the winner's camera.
func winner_frame(player: int) -> void:
	var f := fight.fighters[player]
	var other := fight.fighters[(player + 1) & 1]
	fight.input_mode[0] = 0
	fight.input_mode[1] = 0
	if winner_frames == 0:
		FighterSounds.script_stop(f)
		FighterSounds.script_stop(other)
		f.move_changed = 1
		events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
		fight.camera_phase = CameraPhase.WINNER_0 if player == 0 else CameraPhase.WINNER_1
		winner_frames = 1
	else:
		fight.camera_phase = CameraPhase.WINNER
	f.active = 1
	other.active = 0
	f.round_won = 1
	other.round_won = -1
	fight_frame()


## FUN_8018C8BC for one fighter.
func _place(f: FighterState, opp: FighterState) -> void:
	_start_stance(f, opp)
	var x := -PLACEMENT_X if f.index == 0 else PLACEMENT_X
	_set_position(f, x, 0, PLACEMENT_FACING if f.index == 0 else -PLACEMENT_FACING)
	f.health = f.health_max
	_clear_round_state(f)
	FighterSounds.script_stop(f)
	_hurt_radii(f)
	f.hands.command(3, t.face_shape(t.face_attack, f.costume_slot), HAND_SPEED)
	(animation as ArcadeAnimation).root_update(f)
	f.prev_root_x = f.root_x
	f.prev_root_y = f.root_y
	f.prev_root_z = f.root_z


## FUN_8018EEC8's choice of the slot: the panel's punches or kicks held at the first round.
func _stance_slot(f: FighterState) -> int:
	var held := panels.held[f.index]
	var slot := 1
	if fight.rounds_played == 1:
		if held & STANCE_PUNCHES:
			slot = 0
		else:
			slot = 2
			if held & STANCE_KICKS == 0 and fight.rng.next() & 1:
				slot = 0
	return slot


func _clear_round_state(f: FighterState) -> void:
	_clear_shared_round_state(f)
	f.got_hit = 0
	f.contact = 0
	f.whiffed = 0
	f.hit_freeze_in = 0


## FUN_8018CB08: both roots from the second fighter's channels, then the directions and the distance.
func _settle(f0: FighterState, f1: FighterState) -> void:
	var anim := animation as ArcadeAnimation
	anim.decode_root(f0)
	anim.decode_root(f1)
	anim.root_update(f0)
	anim.root_update(f1)
	for f: FighterState in [f0, f1]:
		saved_x[f.index] = f.pos_x
		saved_z[f.index] = f.pos_z
	saved_distance = SAVED_DISTANCE_START
	_directions(f0, f1)
	_distance(f0, f1)


## FUN_8018B050.
func _directions(f0: FighterState, f1: FighterState) -> void:
	var angle := FightMath.atan2_angle(Fx.w32(f1.root_z - f0.root_z), Fx.w32(f1.root_x - f0.root_x), t)
	f0.target_dir = angle
	f1.target_dir = (angle - FightMath.HALF_TURN) & 0xFFFF


## FUN_8018B124: a jump of the roots by more than the fighters' distance is undone; then the distance.
func _distance(f0: FighterState, f1: FighterState) -> void:
	if saved_distance > FAR_APART:
		for i in FightState.FIGHTERS:
			var f := fight.fighters[i]
			var dx := Fx.w32(saved_x[1 - i] - f.root_x)
			var dz := Fx.w32(saved_z[1 - i] - f.root_z)
			if saved_distance <= FightMath.sqrt_table(Fx.w32(dx * dx + dz * dz), t):
				f.pos_x = Fx.w32(f.pos_x + saved_x[i] - f.root_x)
				f.pos_z = Fx.w32(f.pos_z + saved_z[i] - f.root_z)
				f.root_x = saved_x[i]
				f.root_z = saved_z[i]
	for f: FighterState in [f0, f1]:
		saved_x[f.index] = f.root_x
		saved_z[f.index] = f.root_z
	var x := Fx.w32(f1.root_x - f0.root_x)
	var z := Fx.w32(f1.root_z - f0.root_z)
	var d := CameraMath.isqrt(Fx.w32(x * x + z * z))
	saved_distance = d
	fight.fighter_distance = d
	var wide := 0
	for f: FighterState in [f0, f1]:
		if f.char_id in WIDE_CHARACTERS:
			wide += 1
	distance_adjusted = d - WIDE_DISTANCE * wide
	f0.dist = d
	f1.dist = d
	f0.dist_adj = distance_adjusted
	f1.dist_adj = distance_adjusted


# ==== the frame ===================================================================================

## FUN_8018A988; returns the round state.
func fight_frame() -> int:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	fight.blend_enabled = 1
	fight.paused_player = 0
	if fight.freeze != 0:
		_stopped_frame(f0, f1)
		return fight.round_state
	round_flow.replay_request_check(self)
	fight.replay_playing = round_flow.replay_update(self)
	round_flow.step(self)
	round_sounds.step(fight, events)
	if fight.replay_playing == 0:
		_arcade_frame(f0, f1)
	else:
		_arcade_replay_frame(f0, f1)
	return fight.round_state


## The frame of a playing replay: the blends run on the even half frames only, Start ends it.
func _arcade_replay_frame(f0: FighterState, f1: FighterState) -> void:
	fight.blend_enabled = (fight.replay.play ^ 1) & 1
	if round_flow.start_pressed(self):
		fight.replay.skip = 1
		fight.replay_skip = 1
	camera.replay_step(f0, f1)
	_camera_frame()
	wind.step()
	(animation as ArcadeAnimation).update_pair()
	var enabled := fight.blend_enabled != 0
	_effects_update(enabled)
	if enabled:
		effect_objects.play_log(events, camera.view)
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE if enabled else SimEvents.EFFECTS_HOLD)


## FUN_8018A988 with 0x8021FAD0 set: the fight only draws, its voices go on and the panels are still read.
func _stopped_frame(f0: FighterState, f1: FighterState) -> void:
	if fight.replay_playing != 0:
		frame_view()
		(animation as ArcadeAnimation).update_pair()
		_effects_update(false)
		events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_HOLD)
		return
	f0.ogre_freeze = 1
	f1.ogre_freeze = 1
	round_sounds.step(fight, events)
	frame_view()
	(animation as ArcadeAnimation).update_pair()
	effect_objects.update(false)
	events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_HOLD)
	ArcadeInput.source(fight, f0, panels, fight.input_mode[0], cpu)
	ArcadeInput.source(fight, f1, panels, fight.input_mode[1], cpu)
	ArcadeInput.latch_taps(fight)


func _arcade_frame(f0: FighterState, f1: FighterState) -> void:
	camera.step(f0, f1)
	ArcadeInput.update_sides(f0, f1)
	_camera_frame()
	arcade_combat.save_segment_starts(f0)
	arcade_combat.save_segment_starts(f1)
	moves.start_all()
	_directions(f0, f1)
	_distance(f0, f1)
	(physics as ArcadeFighterPhysics).update_pair(f0, f1, events)
	if f0.throw_state == 0 and f1.throw_state == 0:
		combat.save_position(f0)
		combat.save_position(f1)
	wind.step()
	(animation as ArcadeAnimation).update_pair()
	_effects_update(true)               # they draw on `rand` here, before the frame's sounds
	Combat.velocity(f0)
	Combat.velocity(f1)
	arcade_combat.shapes(f0)
	arcade_combat.shapes(f1)
	_landing_dust(f0)
	_landing_dust(f1)
	arcade_combat.sphere_profiles(f0, f1)
	if fight.camera_phase < CameraPhase.WINNER_0:
		arcade_combat.separate(f0, f1)
	arcade_combat.test_hits(f0, f1)
	ArcadeCombat.attack_direction(f0, f1)
	ArcadeCombat.attack_direction(f1, f0)
	moves.branch_all()
	var logged := events.items.size()
	MoveEvents.run(f0, t.fighter, events)
	MoveEvents.run(f1, t.fighter, events)
	_log_effects(logged)
	move_event_calls(logged)
	arcade_combat.apply_hits(f0, f1, events)
	if f0.active != 0:
		sounds.run(f0, f1, events)
	if f1.active != 0:
		sounds.run(f1, f0, events)
	# FUN_8018B57C: the loser camera (phases 6 and 7) neither draws nor steps the flipbooks.
	if fight.camera_phase < CameraPhase.LOSER_0 or fight.camera_phase > CameraPhase.LOSER_1:
		events.add(SimEvents.Kind.EFFECTS_DRAW, -1, SimEvents.EFFECTS_ADVANCE)
		fight.replay.log_advance()
	ArcadeInput.source(fight, f0, panels, fight.input_mode[0], cpu)
	ArcadeInput.source(fight, f1, panels, fight.input_mode[1], cpu)
	ArcadeInput.latch_taps(fight)
	f0.event_frame = f0.pose_frame
	f1.event_frame = f1.pose_frame
	moves.step_all()
	fight.round_frame_seen = fight.round_frame


## FUN_801DC758 for both fighters, FUN_801DC990. `enabled` is 0x8021FB38.
func _effects_update(enabled: bool) -> void:
	effect_objects.descriptor_spawn(fight.fighters[0], enabled)
	effect_objects.descriptor_spawn(fight.fighters[1], enabled)
	effect_objects.update(enabled)


## FUN_801AE9DC, FUN_801A6DBC. `fighter_view` is for presentation, which reads the display's points in
## the PlayStation's layout (SwordGlow); the frame's screen positions come from the arcade's own view.
func _camera_frame() -> void:
	camera.view.pitch += CameraShake.step(fight)
	frame_view()


## FUN_801A6DBC.
func frame_view() -> void:
	view = ArcadeViewMatrix.build_arcade(camera.view, t)
	fighter_view = ViewMatrix.build(camera.view, t)
	(animation as ArcadeAnimation).frame_view = view


## The landing's dust and shake moved here from the physics.
func _landing_dust(f: FighterState) -> void:
	if f.landed_b != 0 and f.active != 0:
		var logged := events.items.size()
		events.add_at(SimEvents.Kind.DUST, f.index, PackedInt32Array([f.root_x, f.root_y, f.root_z]))
		_log_effects(logged)
		CameraShake.start(fight, 0, events)
