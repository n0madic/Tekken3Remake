class_name RoundFlow
extends RefCounted
## The round state machine (FUN_8003CDD8, fight-frame.md#round-flow) of a VS match:
##
## | State | |
## |---:|---|
## | 0 | Intro: 150 frames in round 1, 90 later, then input on. |
## | 1 | Fight: the timer runs until a KO or the time is up; then the result. |
## | 2 | Result shown (240 frames after a KO, 90 after a time out), losers on scripted input. |
## | 3, 4 | The replay (after a KO), then the win poses and the round-end camera. Tekken Ball
## |   | shows the deciding point's last 30 frames (twice, six times after an iron ball's lethal
## |   | hit) from the result, and skips state 4. |
## | 5, 6 | Win poses until they end (or 300 frames); Start skips. |
## | 9 | The round is over (FightMain starts the next round or ends the match). |
##
## Tekken Force: a won level (the player's round won) goes to state 8, STAGE CLEAR!! until the
## tally is done and Start is pressed or 300 frames pass; state 7 (the level runner's area
## change) returns to the fight.

const INTRO_ROUND1 := 0x97
const INTRO_LATER := 0x5B
const RESULT_KO_HOLD := 0xF0
const RESULT_TIME_HOLD := 0x5A
const RESULT_CAMERA_TIME := 0x5A
const WIN_HOLD := 300
const WIN_CAMERA_END := 0x4B
const LOSER_CAMERA_END := 0x3C
const TIME_UP := 1
const PERFECT_FLAGS := 0x1E           ## result bits that end the result display at 90 frames
const DRAW := 0x20
const DOUBLE_KO := 0x26
const KO := 2
const PERFECT := 10
const GREAT := 0x12
const FULL_HEALTH := 0x1000
const GREAT_HEALTH := 0xCD
const LOSE_POSE_DOWN := 0xD65
const LOSE_POSE_UP := 0xD6C
const WIN_POSE_FIRST := 0xD67
const SPECIAL_WIN_COSTUME := 0x26
const RECOVERY_CLOCK := [300, 600, 900, 1200, 1500, 1800, 2100]   ## survival's recovery steps (frames)
const OGRE_SCENE := 0xBC              ## mode context: the Ogre scene has played
const STAGE_CLEAR_FRAMES := 300
const STAGE_CLEAR_FADE := 0xB4
const BALL_REPLAY_DELAY := 0x10
const BALL_LOSER_CAMERA_END := 0xF0

var fight: FightState


func _init(fight_state: FightState) -> void:
	fight = fight_state


## FUN_8003EE94: a requested replay starts (ReplayStart(0)).
func replay_request_check(sim: FightSimulation) -> void:
	if fight.replay_request != 0:
		fight.replay.start(fight, 0)
		sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	fight.replay_request = 0


## ReplayUpdate (0x800323CC): non-zero while the replay plays.
func replay_update(sim: FightSimulation) -> int:
	return fight.replay.update(fight, sim)


## FUN_8003CDD8 for one frame.
func step(sim: FightSimulation) -> void:
	var f0 := fight.fighters[0]
	var f1 := fight.fighters[1]
	if fight.round_state > RoundState.FIGHT:
		fight.round_counter += 1
	match fight.round_state:
		RoundState.INTRO:
			fight.round_frame += 1
			var wait := INTRO_ROUND1 if fight.rounds_played == 1 else INTRO_LATER
			if fight.round_frame < wait:
				return
			if fight.mode != GameMode.PRACTICE:
				sim.set_input_mode(1)
			fight.round_state = RoundState.FIGHT
		RoundState.FIGHT:
			fight.round_frame += 1
			if fight.mode == GameMode.FORCE:
				fight.challenger_lock = 1
			fight.no_damage = 1 if _round_over() else 0
			if fight.no_damage == 0:
				if fight.timer_stopped == 0:
					fight.timer -= 1
				fight.fight_clock += 1
			else:
				_result(f0, f1)
		RoundState.RESULT:
			_result_step(sim, f0, f1)
		RoundState.REPLAY:
			_ball_result(sim, f0, f1)
		RoundState.REPLAY_DONE:
			_replay_done(sim, f0, f1)
		RoundState.WIN_POSES:
			_win_state(sim)
		RoundState.WIN_WAIT:
			_win_wait(sim, f0, f1)
		RoundState.AREA_CHANGE:
			fight.round_state = RoundState.FIGHT
		RoundState.STAGE_CLEAR:
			_stage_clear(sim)
		RoundState.END:
			_round_end()


## RESULT: the losers on scripted input until the result display ends; then the replay (Tekken
## Force: the round's end, or STAGE CLEAR!! for a won level).
func _result_step(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	_scripted_input(f0)
	_scripted_input(f1)
	if fight.mode == GameMode.FORCE:
		_scripted_input(fight.fighters[2])
	if fight.mode == GameMode.BALL:
		_ball_replays(sim, f0, f1)
	if fight.result_flags & (TIME_UP | PERFECT_FLAGS) != 0 and fight.round_counter == RESULT_CAMERA_TIME:
		fight.round_end_done = 1
	if fight.round_end_done == 0:
		return
	fight.input_mode[0] = 0
	fight.input_mode[1] = 0
	fight.input_mode[2] = 0
	FighterSounds.script_stop(f0)
	FighterSounds.script_stop(f1)
	sim.events.add(SimEvents.Kind.VOICE_OFF, -1, 0)
	if fight.mode == GameMode.FORCE:
		if fight.force.player().round_won != 1:
			fight.round_state = RoundState.END
			return
		sim.events.add(SimEvents.Kind.MUSIC_VOLUME, -1, 0, STAGE_CLEAR_FADE)
		fight.round_state = RoundState.STAGE_CLEAR
		fight.round_counter = 0
		return
	fight.round_state = RoundState.REPLAY
	_ball_result(sim, f0, f1)


## REPLAY_DONE: after the replay, the win poses and the round-end camera, or (skipped) the round's
## end.
func _replay_done(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	if fight.replay.mode != ReplayState.DONE:
		return
	fight.blend_hold = 2
	sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
	FighterSounds.script_stop(f0)
	FighterSounds.script_stop(f1)
	if fight.match_result != 0 or (start_pressed(sim) == false and fight.replay_skip == 0):
		_win_poses(sim, f0, f1)
		if fight.result_flags & TIME_UP == 0:
			sim.animation.animate(f0, sim.fighter_view, fight.blend_enabled != 0, true)
			sim.animation.animate(f1, sim.fighter_view, fight.blend_enabled != 0, true)
		_result_camera(sim, f0, f1)
		if fight.camera_phase == CameraPhase.LOSER_0 or fight.camera_phase == CameraPhase.LOSER_1:
			_lose_poses(sim, f0, f1)
		_clear_blends()
		sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
		fight.round_state = RoundState.WIN_POSES
		_win_state(sim)
	else:
		sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
		_round_end()


## STAGE_CLEAR (Tekken Force): until the tally is done and Start is pressed, or the frames run out.
func _stage_clear(sim: FightSimulation) -> void:
	var p := fight.force.player()
	if fight.round_counter < STAGE_CLEAR_FRAMES:
		if start_pressed(sim) and fight.force.gu32(TekkenForce.TALLY_DONE) != 0:
			fight.round_state = RoundState.END
	else:
		fight.round_state = RoundState.END
	fight.input_mode[p.index] = 2
	_hold_input(p)


## State RESULT of Tekken Ball: 16 frames after the result the deciding point's replay starts, with
## the loser camera; each finished replay starts the next until RESULT of them have played.
func _ball_replays(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	var region := fight.region
	if fight.round_counter == BALL_REPLAY_DELAY:
		region.ctx_put32(TekkenBall.LAST_POINT, 1)
		fight.hud_shown = 0
		fight.replay_request = 1
		var loser := f0 if f0.round_won < 0 else f1
		sim.camera.loser_start(loser, loser.health != 0)
		fight.camera_phase = CameraPhase.LOSER_0 if loser == f0 else CameraPhase.LOSER_1
		region.ctx_put8(TekkenBall.SERVE_SIDE, 0 if loser == f0 else 1)
	elif region.ctx_s32(TekkenBall.LAST_POINT) > 0:
		if fight.replay.mode != ReplayState.DONE:
			fight.round_counter -= 1
			return
		sim.events.add(SimEvents.Kind.EFFECTS_CLEAR, -1)
		FighterSounds.script_stop(f0)
		FighterSounds.script_stop(f1)
		var shown := region.ctx_s32(TekkenBall.LAST_POINT)
		if shown < region.ctx_s32(TekkenBall.RESULT):
			fight.replay_request = 1
			EffectObjects.reset(fight)
			fight.round_counter -= 1
			region.ctx_put32(TekkenBall.LAST_POINT, shown + 1)
			fight.camera_phase = CameraPhase.WINNER_0 if f0.round_won < 0 else CameraPhase.WINNER_1
		else:
			fight.hud_shown = 1


## State 3: other modes go on to the replay (state 4); Tekken Ball, whose replays are shown, to
## the win poses (a CPU's defeated opponent keeps a sliver of health).
func _ball_result(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	if fight.mode != GameMode.BALL:
		fight.round_state = RoundState.REPLAY_DONE
		fight.replay_request = 1
		return
	fight.camera_phase = CameraPhase.FIGHT
	if f0.round_won < 0 and f1.is_cpu != 0:
		f0.health = 1
	if f1.round_won < 0 and f0.is_cpu != 0:
		f1.health = 1
	_win_poses(sim, f0, f1)
	_result_camera(sim, f0, f1)
	if fight.camera_phase == CameraPhase.LOSER_0 or fight.camera_phase == CameraPhase.LOSER_1:
		_lose_poses(sim, f0, f1)
	_clear_blends()
	fight.round_state = RoundState.WIN_POSES
	fight.region.ctx_put32(TekkenBall.LAST_POINT, fight.region.ctx_s32(TekkenBall.LAST_POINT) + 1)
	_win_state(sim)


## States 5 → 6: the win poses start (FUN_8003CE64 case 5 falls into 6).
func _win_state(sim: FightSimulation) -> void:
	fight.round_end_hold = WIN_HOLD
	fight.win_pose_done = PackedInt32Array([0, 0])
	fight.round_counter = 0
	fight.round_end_done = 0
	fight.round_state += 1
	if fight.carry_health != 0:
		for f in fight.active():
			f.health = f.carried_health
	_win_wait(sim, fight.fighters[0], fight.fighters[1])


## State 6: the win poses and the round-end camera until they end, the hold runs out or Start.
func _win_wait(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	fight.blend_hold = 2
	match fight.camera_phase:
		CameraPhase.FIGHT:
			if fight.round_counter == WIN_CAMERA_END:
				fight.round_end_done = 1
		CameraPhase.LOSER_0, CameraPhase.LOSER_1:
			if fight.round_counter == (BALL_LOSER_CAMERA_END if fight.mode == GameMode.BALL else LOSER_CAMERA_END):
				fight.round_end_done = 1
		CameraPhase.WINNER:
			if f0.win_pose < 1 or f0.pose_move.length - 1 <= f0.pose_frame:
				fight.win_pose_done[0] = 1
			if f1.win_pose < 1 or f1.pose_move.length - 1 <= f1.pose_frame:
				fight.win_pose_done[1] = 1
			if fight.win_pose_done[0] != 0 and fight.win_pose_done[1] != 0:
				fight.round_end_done = 1
	fight.round_end_hold = maxi(fight.round_end_hold - 1, 0)
	if start_pressed(sim):
		sim.events.add(SimEvents.Kind.VOICES_OFF, -1, 0)
	if fight.round_end_done != 0 or fight.round_end_hold < 1 \
			or (fight.match_result == 0 and fight.replay_skip != 0 and fight.round_counter > 1) \
			or start_pressed(sim):
		_round_end()


## FUN_8003E608: a fighter is out of health or the time is up. Tekken Force watches the player
## while the enemies come, the first two records in the boss fight (0x800B70E8 set).
func _round_over() -> bool:
	if fight.mode == GameMode.FORCE:
		if not fight.force.level_ended():
			return fight.force.player().health < 1 or fight.timer < 1
		return fight.fighters[0].health < 1 or fight.fighters[1].health < 1 or fight.timer < 1
	return fight.fighters[0].health == 0 or fight.fighters[1].health == 0 or fight.timer < 1


## The round's result (state 1 → 2).
func _result(f0: FighterState, f1: FighterState) -> void:
	# FUN_8003E6D0: health left in 1/4096 of the maximum, rounded up.
	for f: FighterState in [f0, f1]:
		var unit := f.health_max >> 12
		f.health_left = Fx.s16(Fx.div_trunc(f.health + unit - 1, unit) if unit != 0 else 0)
	_result_flags(f0, f1)
	_round_wins(f0, f1)
	_carry_health(f0, f1)
	if fight.match_result != 0 and fight.mode == GameMode.ARCADE and (fight.region.human_mask >> fight.match_loser) & 1:
		fight.challenger_lock = 1
	_lose_markers(f0, f1)
	fight.win_pose_done = PackedInt32Array([0, 0])
	if fight.result_flags & TIME_UP == 0:
		fight.round_end_hold = RESULT_KO_HOLD
	else:
		fight.round_end_hold = RESULT_TIME_HOLD
		fight.input_mode[2] = 0
		fight.input_mode[1] = 0
		fight.input_mode[0] = 0
	fight.round_state = RoundState.RESULT
	fight.round_end_done = 0


## FUN_80051AD4: the health the next fight starts with. Team battle's winner and survival's
## winning human recover part of it (by the health left, by the fight's time); other modes keep it.
func _carry_health(f0: FighterState, f1: FighterState) -> void:
	for i in 2:
		var f := f0 if i == 0 else f1
		var v := f.health
		match fight.mode:
			GameMode.TEAM:
				if i == fight.match_winner and v != 0:
					var eighths := mini(((v << 3) & 0xFFFFFFFF) / f.health_max, 7)
					v = _recovered(f, fight.tables.recovery_team[eighths])
			GameMode.SURVIVAL:
				if i == fight.match_winner and i == fight.region.human_index and v != 0:
					var step := 7
					for k in RECOVERY_CLOCK.size():
						if fight.fight_clock < RECOVERY_CLOCK[k]:
							step = k
							break
					v = _recovered(f, fight.tables.recovery_survival[step])
		f.carried_health = v


func _recovered(f: FighterState, share: int) -> int:
	return mini((f.health_max >> 8) * share + f.health, f.health_max)


## Game state 9 (and every frame in it): after the first round the human wins against Ogre in
## arcade or time attack, the Ogre scene is requested (OgreSceneCheck 0x800514EC, round state 10).
func _round_end() -> void:
	fight.round_state = RoundState.END
	var region := fight.region
	if (fight.mode == GameMode.ARCADE or fight.mode == GameMode.TIME_ATTACK) and region.fight_index == 9 and region.human_count == 1 \
			and region.ctx32(OGRE_SCENE) == 0 and fight.challenger_lock == 0 \
			and fight.fighters[region.cpu_index].round_wins < fight.rounds_to_win \
			and fight.fighters[region.human_index].round_wins > 0:
		region.ctx_put32(OGRE_SCENE, 1)
		fight.round_state = RoundState.OGRE_SCENE


## FUN_8003E70C: time up, draw, double KO, KO, perfect and great flags.
func _result_flags(f0: FighterState, f1: FighterState) -> void:
	var time_up := 1 if fight.timer < 1 else 0
	var a := f0.health_left & 0xFFFF
	var b := f1.health_left & 0xFFFF
	fight.result_flags = time_up
	if a == b:
		fight.result_flags = time_up | (DOUBLE_KO if a == 0 else DRAW)
		return
	var winner_left := a if b < a else b
	var loser_left := b if b < a else a
	if loser_left == 0:
		fight.result_flags = time_up | KO
		if winner_left == FULL_HEALTH:
			fight.result_flags = time_up | PERFECT
		elif winner_left < GREAT_HEALTH:
			fight.result_flags = time_up | GREAT


## FUN_8003E7C4: the round's winner (+0x46 = 1, the loser −1) and the round wins; a draw counts
## for both (and costs a round of the maximum), the match ends when a fighter has enough wins
## or the last round is played (FUN_8003EA98).
func _round_wins(f0: FighterState, f1: FighterState) -> void:
	var a := f0.health_left & 0xFFFF
	var b := f1.health_left & 0xFFFF
	if b < a:
		f0.round_won = 1
		f1.round_won = -1
		f0.round_wins += 1
	elif a < b:
		f0.round_won = -1
		f1.round_won = 1
		f1.round_wins += 1
	else:
		fight.max_rounds -= 1
		var first := f0
		var second := f1
		if f0.round_wins <= f1.round_wins:
			if f1.round_wins > f0.round_wins or _tie_breaker() != 0:
				first = f1
				second = f0
		first.round_wins += 1
		second.round_wins += 1
		first.round_won = -1
		second.round_won = -1
		if fight.draw_wins == 0:
			if fight.rounds_to_win <= first.round_wins:
				first.round_won = 1
			if fight.rounds_to_win <= second.round_wins:
				second.round_wins -= 1
		elif fight.rounds_to_win <= first.round_wins and second.round_wins < fight.rounds_to_win:
			first.round_won = 1
	if fight.max_rounds <= fight.rounds_played or fight.rounds_to_win <= f0.round_wins \
			or fight.rounds_to_win <= f1.round_wins:
		_match_result(f0, f1)


## The draw tie breaker by the human mask (1: player 2 first; 3: the stored choice 0x800AE406).
func _tie_breaker() -> int:
	match fight.human_mask:
		1:
			return 1
		3:
			return fight.tie_choice
	return 0


## FUN_8003EA98: the match result from the round wins.
func _match_result(f0: FighterState, f1: FighterState) -> void:
	if f0.round_wins > f1.round_wins:
		fight.match_winner = 0
		fight.match_loser = 1
		fight.match_result = 1
	elif f0.round_wins < f1.round_wins:
		fight.match_winner = 1
		fight.match_loser = 0
		fight.match_result = 2
	else:
		fight.match_winner = _tie_breaker()
		fight.match_loser = (fight.match_winner + 1) & 1
		fight.match_result = 3


## FUN_8003EBF4: after a time out the losers' win-pose field takes the −1 of the result.
func _lose_markers(f0: FighterState, f1: FighterState) -> void:
	if fight.result_flags & TIME_UP == 0:
		return
	if f0.round_won == f1.round_won:
		f0.win_pose = 0
		f1.win_pose = 0
		return
	if f0.round_won < 0:
		f0.win_pose = f0.round_won
	if f1.round_won < 0:
		f1.win_pose = f1.round_won


## FUN_8003D7A8: a KO'd fighter or the loser stands still (scripted input 0); the winner of a KO
## keeps the pad unless it is CPU-controlled; the time-out winner holds its guard or crouch.
func _scripted_input(f: FighterState) -> void:
	if f.health == 0 or f.round_won < 0:
		fight.input_mode[f.index] = 2
		f.script_input = 0
	elif fight.result_flags & TIME_UP == 0 and f.is_cpu == 0:
		fight.input_mode[f.index] = 1
	else:
		fight.input_mode[f.index] = 2
		_hold_input(f)


## FUN_8003D860: the scripted word that keeps the fighter's stance (down while crouching). A
## stance slot empty in both banks has no row (bug #61, not reproduced): no hold.
func _hold_input(f: FighterState) -> void:
	if f.bank_type != BankType.DOCTOR_B:
		var row := f.move_row
		if row == null:
			row = fight.move_for_slot(f, f.pose_move.stance_slot)
		if row != null and row.state & (StateBit.DOWN_REVERSED | StateBit.DOWN) != 0:
			f.script_input = 0x1000
			return
	f.script_input = 0


## FUN_8003EB60: the round winner's win pose (1 + frame parity; the physical buttons held
## choose one).
func _win_poses(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	var parity := fight.frame_counter & 1
	var winner := f0
	var loser := f1
	if f0.round_won < 1:
		if f1.round_won < 1:
			return
		winner = f1
		loser = f0
	winner.win_pose = parity + 1
	winner.blend_mode = FighterAnimation.Blend.NONE
	winner.blend_mode_b = 0
	fight.blend_hold = 0x14
	_start_win_pose(sim, winner, loser, parity)


## FighterStartWinPose (0x8002D6B0).
func _start_win_pose(sim: FightSimulation, f: FighterState, opp: FighterState, button: int) -> void:
	var held := sim.pads.physical[f.index]
	if held & PadState.CIRCLE:
		button = 3
	if held & PadState.CROSS:
		button = 2
	if held & PadState.TRIANGLE:
		button = 1
	if held & PadState.SQUARE:
		button = 0
	match button:
		0:
			f.move_slot = WIN_POSE_FIRST
		1:
			f.move_slot = WIN_POSE_FIRST + 1
		2:
			f.move_slot = WIN_POSE_FIRST + 2
		3:
			f.move_slot = WIN_POSE_FIRST + 3
	if f.costume_slot == SPECIAL_WIN_COSTUME and f.move_slot == WIN_POSE_FIRST:
		# The game picks by the video frame count (0x800AE6E0).
		match fight.vblank % 3:
			1:
				f.move_slot = WIN_POSE_FIRST + 2
			2:
				f.move_slot = WIN_POSE_FIRST + 3
			_:
				f.move_slot = WIN_POSE_FIRST + 1
	_start_move(sim, f, opp, f.move_slot, true)


## FUN_8002D8C0 / FUN_8002D844: the loser's pose of a match-deciding round (down or standing).
func _lose_poses(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	for pair: Array in [[f0, f1], [f1, f0]]:
		var f: FighterState = pair[0]
		var opp: FighterState = pair[1]
		if f.round_won < 0:
			f.move_slot = LOSE_POSE_DOWN if f.health == 0 else LOSE_POSE_UP
			_start_move(sim, f, opp, f.move_slot, false)


## A move started from its first frame with transition 6 (`grounded`: on the floor first).
func _start_move(sim: FightSimulation, f: FighterState, opp: FighterState, slot: int, grounded: bool) -> void:
	var row := fight.move_for_slot(f, slot)
	f.pose_move = row
	f.root_move = row
	f.move_row = row
	f.pose_frame = 1
	f.entry_frame = 1
	f.transition = FightMath.transition_remap(Transition.RESTART, f.move_row, f.entry_frame)
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	if grounded:
		f.pos_y = 0
	sim.moves.start_or_advance(f, opp)


## FUN_8003ECF4: the round-end camera phase (winner 3/4, loser 6/7, none 2) and whose sounds
## stay on (FUN_8002BBE0). The loser camera only follows a match-deciding round a CPU won.
func _result_camera(sim: FightSimulation, f0: FighterState, f1: FighterState) -> void:
	if fight.mode == GameMode.DEMO:
		f0.active = 1
		f1.active = 1
		return
	var deciding := not ((f0.round_wins < fight.rounds_to_win and f1.round_wins < fight.rounds_to_win) \
		or fight.team_round == 1)
	if deciding:
		if f0.is_cpu == 0 and f0.win_pose > 0:
			fight.camera_phase = CameraPhase.WINNER_0
			_sounds_of(f0)
			return
		if not (f1.is_cpu == 0 and f1.win_pose > 0):
			if f0.win_pose > 0:
				sim.camera.loser_start(f1, f1.health != 0)
				fight.camera_phase = CameraPhase.LOSER_1
				_sounds_of(f1)
				return
			if f1.win_pose < 1:
				fight.camera_phase = CameraPhase.FIGHT
				f0.active = 1
				f1.active = 1
				return
			sim.camera.loser_start(f0, f0.health != 0)
			fight.camera_phase = CameraPhase.LOSER_0
			_sounds_of(f0)
			return
	if f0.win_pose < 1:
		fight.camera_phase = CameraPhase.WINNER_1
		if f1.win_pose > 0:
			_sounds_of(f1)
			return
		fight.camera_phase = CameraPhase.FIGHT
		f0.active = 1
		f1.active = 1
		return
	fight.camera_phase = CameraPhase.WINNER_0
	_sounds_of(f0)


## FUN_8002BBE0: only this fighter's sounds play (the `active` bytes).
func _sounds_of(f: FighterState) -> void:
	for other in fight.fighters:
		other.active = 0
	f.active = 1


## FUN_8002C23C: every fighter's blend state cleared.
func _clear_blends() -> void:
	for f in fight.active():
		f.blend_frames = 0
		f.blend_counter = 0
		f.blend_weight = 0
		f.blend_root_delta = PackedInt32Array([0, 0, 0])


## FUN_8002BC28 & 0x800: a human pressed Start (Tekken Force: the player's pad).
func start_pressed(sim: FightSimulation) -> bool:
	var word := 0
	if fight.mode == GameMode.FORCE:
		return sim.pads.physical_pressed[fight.force.human()] & PadState.START != 0
	match fight.human_mask:
		1:
			word = sim.pads.physical_pressed[0]
		2:
			word = sim.pads.physical_pressed[1]
		3:
			word = sim.pads.physical_pressed[0] | sim.pads.physical_pressed[1]
	return word & PadState.START != 0
