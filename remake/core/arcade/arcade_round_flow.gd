class_name ArcadeRoundFlow
extends RoundFlow
## FUN_8019D560: the arcade's round states, the PlayStation's numbers up to 6, then 7 the end and 8 the
## Ogre scene. A human keeps the stick after a KO, the winner's hold word has its own rule, the last
## fight won by a human skips the replay and the poses.

const FINISHED := 7
const OGRE_SCENE_STATE := 8
const ARCADE_WIN_POSE_FIRST := 0xE5D
const ARCADE_ONE_WIN_POSE := 0xE61
const ONE_WIN_POSE_COSTUME := 0x24
const ARCADE_LOSE_POSE_DOWN := 0xE5B
const ARCADE_LOSE_POSE_UP := 0xE62
const POSE_BUTTONS: Array[Array] = [[ArcadeInput.RK, 3], [ArcadeInput.LK, 2], [ArcadeInput.RP, 1], [ArcadeInput.LP, 0]]
const START := 0x8000
const HOLD_WORD := 8                   ## the history's byte of a held crouch
const LAST_LADDER_FIGHT := 9
const REQUEST_REPLAY := 1
const REQUEST_STORE := 2

var panels: ArcadeInput.Panels
var start_locked := 0                  ## 0x8021FC5C: with two humans Start does not end the win poses


func _init(fight_state: FightState, panel_words: ArcadeInput.Panels) -> void:
	super(fight_state)
	panels = panel_words


func step(sim: FightSimulation) -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	if fight.round_state > RoundState.FIGHT:
		fight.round_counter += 1
	match fight.round_state:
		RoundState.INTRO:
			fight.round_frame += 1
			if fight.round_frame < (INTRO_ROUND1 if fight.rounds_played == 1 else INTRO_LATER):
				return
			fight.round_state = RoundState.FIGHT
			fight.input_mode[0] = 1
			fight.input_mode[1] = 1
		RoundState.FIGHT:
			fight.round_frame += 1
			fight.no_damage = 1 if _round_over() else 0
			if fight.no_damage == 0:
				fight.timer -= 1
				fight.fight_clock += 1
			else:
				_result(f0, f1)
		RoundState.RESULT:
			_result_step(sim, f0, f1)
		RoundState.REPLAY:
			_request(sim, f0, f1)
		RoundState.REPLAY_DONE:
			_replay_done(sim, f0, f1)
		RoundState.WIN_POSES:
			_win_state(sim)
		RoundState.WIN_WAIT:
			_win_wait(sim, f0, f1)
		FINISHED:
			_round_end()



## State 2: only on time up or for a CPU the fighter leaves the stick, crouching winners keep crouching.
func _result_step(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	_release(f0)
	_release(f1)
	if fight.result_flags & (TIME_UP | PERFECT_FLAGS) != 0 and fight.round_counter == RESULT_CAMERA_TIME:
		fight.round_end_done = 1
	if fight.round_end_done == 0:
		return
	fight.input_mode[0] = 0
	fight.input_mode[1] = 0
	FighterSounds.script_stop(f0)
	FighterSounds.script_stop(f1)
	sim.events.add(SimEvents.Kind.VOICE_OFF, -1, 0)
	fight.round_state = RoundState.REPLAY
	_request(sim, f0, f1)


func _release(f: FighterState) -> void:
	if fight.result_flags & TIME_UP == 0 and f.is_cpu == 0:
		return
	if f.state & StateBit.DOWN == 0 or f.health == 0 or f.round_won < 1:
		fight.input_mode[f.index] = 0
	else:
		fight.input_mode[f.index] = 2
		f.recover_mash = 0
		f.in_history[f.in_hist_index] = HOLD_WORD
		f.in_dir = ArcadeInput.direction_bit(HOLD_WORD)


## State 3: after the ladder's last fight won by a human only the round is kept, else its replay.
func _request(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	if fight.region.fight_index == LAST_LADDER_FIGHT and (f0.is_cpu != 0 or f1.is_cpu != 0) and fight.match_result != 0 \
			and (fight.human_mask >> fight.match_winner) & 1:
		fight.replay_request = REQUEST_STORE
		replay_request_check(sim)
		_round_end()
		return
	fight.replay_request = REQUEST_REPLAY
	fight.round_state = RoundState.REPLAY_DONE


## State 4: the bones are composed once more even on time up.
func _replay_done(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	if fight.replay.mode != ReplayState.DONE:
		return
	fight.blend_hold = 2
	sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	FighterSounds.script_stop(f0)
	FighterSounds.script_stop(f1)
	if fight.match_result == 0 and (start_pressed(sim) or fight.replay_skip != 0):
		_round_end()
		return
	_win_poses(sim, f0, f1)
	var animation := sim.animation as ArcadeAnimation
	animation.animate_arcade(f0)
	animation.animate_arcade(f1)
	_result_camera(sim, f0, f1)
	if fight.camera_phase == CameraPhase.LOSER_0 or fight.camera_phase == CameraPhase.LOSER_1:
		_lose_poses(sim, f0, f1)
	_clear_blends()
	fight.round_state = RoundState.WIN_POSES
	_win_state(sim)


## State 6.
func _win_wait(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	fight.blend_hold = 2
	match fight.camera_phase:
		CameraPhase.FIGHT:
			if fight.round_counter == WIN_CAMERA_END:
				fight.round_end_done = 1
		CameraPhase.LOSER_0, CameraPhase.LOSER_1:
			if fight.round_counter == LOSER_CAMERA_END:
				fight.round_end_done = 1
		CameraPhase.WINNER:
			if f0.win_pose < 1 or f0.pose_move.length - 1 <= f0.pose_frame:
				fight.win_pose_done[0] = 1
			if f1.win_pose < 1 or f1.pose_move.length - 1 <= f1.pose_frame:
				fight.win_pose_done[1] = 1
			if fight.win_pose_done[0] != 0 and fight.win_pose_done[1] != 0:
				fight.round_end_done = 1
	fight.round_end_hold = maxi(fight.round_end_hold - 1, 0)
	if fight.round_end_done == 0 and fight.round_end_hold > 0 \
			and (fight.match_result != 0 or fight.replay_skip == 0 or fight.round_counter < 2):
		if (fight.human_mask == 3 and start_locked != 0) or not start_pressed(sim):
			return
	_round_end()


## State 7 and FUN_801B7B8C: the Ogre scene after the human won a round of the ladder's last fight.
func _round_end() -> void:
	fight.round_state = FINISHED
	var region := fight.region
	if fight.mode == GameMode.ARCADE and region.fight_index == LAST_LADDER_FIGHT and region.human_count == 1 \
			and region.ctx32(OGRE_SCENE) == 0 and fight.challenger_lock == 0 \
			and fight.fighters[region.human_index].round_wins > 0:
		region.ctx_put32(OGRE_SCENE, 1)
		fight.round_state = OGRE_SCENE_STATE


## FUN_8018F070: the last of the buttons held picks the pose.
func _start_win_pose(sim: FightSimulation, f: FighterState, opp: FighterState, button: int) -> void:
	var held := panels.held[f.index]
	for choice: Array in POSE_BUTTONS:
		if held & (choice[0] as int):
			button = choice[1]
	f.move_slot = ARCADE_WIN_POSE_FIRST + button
	if f.costume_slot == SPECIAL_WIN_COSTUME and button == 0:
		f.move_slot = ARCADE_WIN_POSE_FIRST + [2, 3, 1][fight.vblank % 3 - 1]
	if f.costume_slot == ONE_WIN_POSE_COSTUME:
		f.move_slot = ARCADE_ONE_WIN_POSE
	_start_move(sim, f, opp, f.move_slot, false)


## FUN_8019EBE0.
func _lose_poses(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	for pair: Array in [[f0, f1], [f1, f0]]:
		var f: FighterState = pair[0]
		var opp: FighterState = pair[1]
		if f.round_won < 0:
			f.move_slot = ARCADE_LOSE_POSE_DOWN if f.health == 0 else ARCADE_LOSE_POSE_UP
			_start_move(sim, f, opp, f.move_slot, false)


## FUN_8018AFD8 & 0x8000.
func start_pressed(_sim: FightSimulation) -> bool:
	var word := 0
	if fight.human_mask & 1:
		word |= panels.pressed[0]
	if fight.human_mask & 2:
		word |= panels.pressed[1]
	return word & START != 0
