class_name MoveSystem
extends RefCounted
## The move lifecycle (moves.md): MoveStartAll / MoveStartOrAdvance with every transition code,
## MoveStepAll / MoveStep (distances, hit reactions, KO collapse, throw pairing), MoveBranchStep
## with BranchFind, InputMatch and BranchCondition, and MoveBranchAll with the reversals.
##
## Written from the verified ports in tools/research/fight_sim.py (MoveStartOrAdvance, MoveBranchStep,
## BranchCondition, InputMatch, relative angles and LaunchTrajectory in fight_math.py) and the
## decompiled MoveStartAll, MoveStep, MoveReactionBranch, BranchFindReversal, HitSelectReaction,
## AirReactionKind, FighterCollapse and ThrowVictimStart.

const END := 0xC000
const CALL := 0xC00C
const RETURN := 0xC00D
const ROW_COMMAND := 0
const ROW_RESTRICTION := 1
const ROW_CONDITION := 2
const ROW_PARAMETER := 3
const ROW_TARGET := 4
const ROW_FLAGS := 5
const ROW_FIRST := 6
const ROW_LAST := 7
const ROW_ENTRY := 8
const HISTORY := 60
const COLLAPSE_SLOT := 0xD66
const STAND_SLOT := 3
const CROUCH_SLOT := 40
const FACING_LIMIT := 0x4FA4       ## relAngle 112°: beyond it the fighter counts as turned away
const TRACK_MODES: Array[int] = [Tracking.TARGET_SLOW, Tracking.TARGET_HALF, Tracking.TARGET]
const SIDE_STEP_COOLDOWN := 24
const THROW_TURN_FRAMES := 0x10
const MAX_THROWN_RECOVERY := 300
const MIN_THROWN_MASH := 34
const MAX_MASH := 66
const LAUNCH_AIR_KIND := 5
const HIGH_ATTACK_RANGE := 0x700
const FACING_EACH_OTHER := 0x2AAA   ## relAngle 60°, both fighters (reversals)

## The fields of a reaction record (21 s16, combat.md#reactions): reaction slots standing and
## crouching, then the push-back.
enum Reaction {
	FRONT, FRONT_CROUCH, COUNTER, COUNTER_CROUCH, SIDE_1, SIDE_1_CROUCH, SIDE_3, SIDE_3_CROUCH,
	BACK, BACK_CROUCH, GUARD, GUARD_CROUCH, DOWN, DOWN_OTHER,
	PUSH_ANGLE, PUSH_HIT, UNUSED_ANGLE, PUSH_COUNTER, PUSH_ANGLE_DOWN, PUSH_DOWN, PUSH_GUARD,
}

var fight: FightState
var t: FightTables


func _init(fight_state: FightState) -> void:
	fight = fight_state
	t = fight_state.tables


# ---- angles ---------------------------------------------------------------------------------

## FighterRelativeAngles (0x80043D2C).
func relative_angles(f: FighterState, opp: FighterState) -> void:
	if f.fixed_facing == 0:
		var target := FightMath.atan2_angle(opp.root_z - f.root_z, opp.root_x - f.root_x, t)
		f.target_dir = target
		f.opp_to_self_dir = (target - 0x8000) & 0xFFFF
		f.opp_heading = opp.heading & 0xFFFF
	else:
		var side := 0x4000 if f.fixed_facing_side == 0 else -0x4000
		f.opp_to_self_dir = (side - 0x8000) & 0xFFFF
		f.opp_heading = (side - 0x8000) & 0xFFFF
		f.target_dir = side & 0xFFFF
	f.heading_delta = (f.heading - f.target_dir) & 0xFFFF
	f.facing_quadrant = FightMath.quadrant(f.heading_delta)
	f.opp_heading_delta = (f.opp_heading - f.opp_to_self_dir) & 0xFFFF
	f.opp_quadrant = FightMath.quadrant(f.opp_heading_delta)
	f.rel_angle = FightMath.fold(f.heading_delta)
	f.opp_rel_angle = FightMath.fold(f.opp_heading_delta)
	if f.dist > 0x200:
		f.aim_dir = f.target_dir if f.rel_angle < 0x4000 else (f.target_dir - 0x8000) & 0xFFFF
		f.opp_aim_dir = f.opp_to_self_dir if f.opp_rel_angle < 0x4000 else (f.opp_to_self_dir - 0x8000) & 0xFFFF


# ---- MoveStartAll / MoveStartOrAdvance ------------------------------------------------------

## MoveStartAll (0x80045834): a pending throw (transition THROW) that reached its entry frame is
## resolved first (one of several by the frame counter), its victim starting with THROWN.
func start_all() -> void:
	var throwers: Array[FighterState] = []
	for f in fight.active():
		if f.move_row != null and f.entry_frame <= f.pose_frame and f.transition == Transition.THROW:
			throwers.append(f)
	var first := 0
	var second := 1
	var rest := 2                      # Tekken Force: the record outside the throw
	if not throwers.is_empty():
		var chosen := throwers[fight.frame_counter % throwers.size()]
		first = chosen.throw_partner
		second = chosen.index
		rest = 3 - (first + second)
	var f := fight.fighters[first]
	if throwers.is_empty():
		start_or_advance(f, fight.fighters[f.cur_opp_index])
		start_or_advance(fight.fighters[second], fight.fighters[fight.fighters[second].cur_opp_index])
	else:
		throw_victim_start(f, fight.fighters[f.throw_partner])
		start_or_advance(f, fight.fighters[f.throw_partner])
		start_or_advance(fight.fighters[second], fight.fighters[fight.fighters[second].throw_partner])
	if fight.mode == GameMode.FORCE:
		var r := fight.fighters[rest]
		start_or_advance(r, fight.fighters[r.cur_opp_index])


## ThrowVictimStart (0x8002D9B0): the victim's move is the thrower's pending move's +0x32 entry.
func throw_victim_start(victim: FighterState, thrower: FighterState) -> void:
	var value := thrower.move_row.reaction
	var slot := 0
	if value & 0xF000 == 0:
		slot = t.reactions[value][0]
	else:
		slot = t.throw_victim_slots[value & 0xFFF]
	victim.move_slot = slot
	victim.move_row = fight.move_for_slot(victim, slot)
	victim.pose_frame = 1
	victim.entry_frame = 1
	victim.transition = FightMath.transition_remap(Transition.THROWN, victim.move_row, victim.entry_frame)
	victim.trans_bit7 = thrower.trans_bit7
	thrower.trans_bit7 = 0
	victim.trans_bit6 = 0


## MoveStartOrAdvance (0x8002F600).
func start_or_advance(f: FighterState, opp: FighterState) -> void:
	if f.active == 0:
		return
	f.step_cooldown = maxi(f.step_cooldown - 1, 0)
	if not _pending_starts(f):
		_advance(f)
		return
	var move := f.move_row
	if f.branch_kind == 3:
		f.entry_frame = 1
	_reset_for_move(f, opp, move)
	_load_move_words(f, move)
	var move_flags := move.flags
	var pose_flags := f.pose_move.flags
	f.crouch_move = 1 if move_flags & MoveFlag.BUFFER_INPUT else 0
	FighterInput.buffer_enable(f, move_flags & MoveFlag.BUFFER_INPUT != 0)
	if f.cmd_read < f.cmd_count:
		f.cmd_read += 1
	f.guarded_prev = 1 if f.guarded != 0 else 0
	if f.got_hit == 0:
		f.was_hit_this_move = 0
		f.ballistic = 0
		f.juggle_count = 0
	if f.contact == 0:
		f.contact_this_move = 0
	_count_react_chain(f, move_flags, pose_flags)
	f.in_reaction = f.hit_clean
	if f.got_hit != 0 and f.health != 0:
		f.hit_freeze = f.hit_freeze_in
	if f.branch_kind == 1 or f.branch_kind == 3 or move.anim_bank != f.pose_move.anim_bank or move.anim != f.pose_move.anim:
		f.move_changed = 1
	var reanchor := 1 if pose_flags & MoveFlag.REANCHOR else 0
	if pose_flags & MoveFlag.POWER:
		f.power_timer = 0x78
	if move_flags & MoveFlag.ALERT:
		f.attack_alert = 9
	if f.trans_bit7 != 0:
		f.trans_bit7 = 0
		f.heading = Fx.s16(f.heading - FightMath.HALF_TURN)
		f.facing = Fx.s16(f.facing - FightMath.HALF_TURN)
	if f.apply_end_turn != 0 and f.transition != Transition.THROWN:
		f.heading = Fx.s16(f.heading + f.pose_move.end_turn)
		f.facing = f.heading
	relative_angles(f, opp)
	var tail := _transition(f, opp, f.transition, reanchor)
	if tail and reanchor != 0:
		f.pos_x = f.root_x
		f.pos_z = f.root_z
	_finish(f)


## The pending move starts at its entry frame (playing backwards: at or before it), or when the
## running move has run out.
func _pending_starts(f: FighterState) -> bool:
	if f.move_row == null:
		return false
	if f.frame_step >= 1:
		return not (f.pose_frame < f.entry_frame) or f.pose_move.length <= f.pose_frame
	if f.frame_step < 0:
		return f.pose_frame <= f.entry_frame or f.pose_frame < 1
	return true


## The per-move state cleared at a move start.
func _reset_for_move(f: FighterState, opp: FighterState, move: MoveRow) -> void:
	f.prev_pose_frame = f.pose_frame
	f.prev_slot = f.cur_slot
	f.prev_move_unk10 = Fx.s16(move.stance_slot)
	f.hit_done[3] = 0
	f.move_flag_ba = 0
	f.skip_step_physics = 0
	f.hit_done[2] = 0
	f.air_phase = 0
	f.slide_state = 0
	f.track_mode = Tracking.NONE
	f.hold_frames = -1
	f.opp_start_x = opp.root_x
	f.opp_start_z = opp.root_z
	f.frame_step = 1
	f.track_accum = 0
	f.step_kind = 0
	f.cond_flag_used = 0
	f.hit_freeze = 0
	f.hit_done[0] = 0
	f.hit_done[1] = 0
	f.hit_cooldown = 0


## The move's damage, attack class, state, attack and guard words; the guard of a humans-only
## guard state is dropped for the CPU.
func _load_move_words(f: FighterState, move: MoveRow) -> void:
	if f.damage_override == 0:
		f.attack_class = move.attack_class()
		f.damage = 0 if f.attack_class == 1 else move.damage()
	else:
		f.damage = f.damage_override
	f.state = move.state
	f.attack = move.attack
	f.guard = f.state & StateBit.GUARDS
	f.state_class = (f.state >> StateBit.CLASS_SHIFT) & 0x1F
	f.attack_hi = f.attack >> 8
	if fight.mode != GameMode.PRACTICE:
		f.human_guard = 1 if f.is_cpu == 0 else 0
	if f.state & StateBit.HUMAN_GUARD and f.human_guard == 0:
		f.state &= ~StateBit.GUARDS & 0xFFFFFFFF
		f.guard &= ~StateBit.GUARDS & 0xFFFF


## reactChain: consecutive reactions (and reaction-chain moves) counted, reset outside them.
func _count_react_chain(f: FighterState, move_flags: int, pose_flags: int) -> void:
	var chain := f.hit_clean != 0 or (pose_flags & MoveFlag.REACT_CHAIN != 0 and move_flags & MoveFlag.REACT_CHAIN != 0) \
		or (f.throw_state < 0 and move_flags & MoveFlag.REACT_CHAIN != 0)
	if chain:
		f.react_chain = Fx.s16(f.react_chain + 1)
	elif f.in_reaction == 0 and f.throw_state >= 0:
		f.react_chain = 0
	elif f.transition != Transition.STEP and f.transition != Transition.STEP_CROUCH:
		if f.transition == Transition.THROWN:
			f.react_chain = Fx.s16(f.react_chain + 1)
		elif (f.move_slot & 0xFFFF) == 0x9A6:
			pass
		elif (f.move_slot & 0xFFFF) == 0xCC6:
			f.react_chain = Fx.s16(f.react_chain + 1)
		else:
			f.react_chain = 0


func _advance(f: FighterState) -> void:
	f.move_frame = Fx.s16(f.move_frame + 1)
	f.move_changed = 0
	var freeze := f.hit_freeze
	if freeze > 0:
		f.hit_freeze = freeze - 1
		if freeze != 1:
			return
		f.hit_freeze = 0
		f.pose_frame = Fx.s16(f.pose_frame + 1)
		f.root_frame = f.pose_frame
		f.root_move = f.pose_move
		return
	var hold := f.hold_frames
	var hold_frame := f.pose_move.hold_frame
	if hold < 0:
		if f.ballistic == 0:
			f.pose_frame = Fx.s16(f.pose_frame + f.frame_step)
			if f.pose_frame < 1:
				f.pose_frame = 1
			f.root_frame = f.pose_frame
		elif (f.pose_frame & 0xFFFF) != hold_frame:
			f.pose_frame = Fx.s16(f.pose_frame + 1)
			f.root_frame = f.pose_frame
		return
	if (f.pose_frame & 0xFFFF) == hold_frame:
		if hold < 1:
			if hold != 0:
				return
			f.pose_frame = Fx.s16(f.pose_frame + 1)
			f.root_frame = f.pose_frame
			f.root_move = f.pose_move
			return
		f.hold_frames = hold - 1
	else:
		f.pose_frame = Fx.s16(f.pose_frame + 1)
	f.root_frame = Fx.s16(f.root_frame + 1)


func _continue_frames(f: FighterState) -> void:
	if FightMath.move_keeps_frame(f.move_row, f.branch_kind, f.pose_frame):
		f.pose_frame = Fx.s16(f.pose_frame + 1)
		f.root_frame = Fx.s16(f.root_frame + 1)
	else:
		f.pose_frame = 1
		f.root_frame = 1
	_clamp_to_length(f)


func _clamp_to_length(f: FighterState) -> void:
	var n := f.move_row.length
	if n < f.pose_frame:
		f.pose_frame = n
		f.root_frame = n


func _recover_mash(f: FighterState) -> void:
	var value := 0
	if not f.pose_move.flags & MoveFlag.LAUNCH_ANGLE:
		value = f.last_damage + Fx.div_trunc(Fx.s16(f.recover_mash), 2)
	f.recover_mash = mini(Fx.s16(value), MAX_MASH)
	f.recover_frames = f.move_row.length


func _load_push(f: FighterState, index: int) -> void:
	var entry := t.push_entry(index)
	f.push_frames = entry[0]
	f.push_speed = entry[1]
	f.push_table = entry.slice(2)
	f.push_table_pos = 0
	f.push_table_frames = 8


func _turn_step(target: int, heading: int, frames: int) -> int:
	return Fx.s16(Fx.div_trunc(Fx.s16(target - heading), Fx.s16(frames)))


func _timed_turn(f: FighterState, target: int) -> void:
	var frames := f.move_row.active_first - 1
	f.turn_frames = frames if frames >= 1 else 1
	f.turn_step = _turn_step(target, f.heading, f.turn_frames)


func _keep_root_move(f: FighterState) -> void:
	f.root_frame = Fx.s16(f.root_frame + 1)
	var n := f.root_move.length
	if n < f.root_frame:
		f.root_frame = n


func _restart(f: FighterState) -> void:
	f.pose_frame = 1
	f.root_frame = 1


func _anchor(f: FighterState) -> void:
	f.pos_x = f.root_x
	f.pos_z = f.root_z


func _clear_turn(f: FighterState) -> void:
	f.turn_frames = 0
	f.turn_step = 0


## One transition case (moves.md#transition-codes); true when the common re-anchor tail runs.
func _transition(f: FighterState, opp: FighterState, code: int, reanchor: int) -> bool:
	var move := f.move_row
	match code:
		Transition.FACE_OPPONENT:
			_restart(f)
			f.throw_state = 0
			f.root_move = move
			f.heading = Fx.s16(f.target_dir)
			f.facing = f.heading
			_anchor(f)
			return false
		Transition.CONTINUE_FACING, Transition.CONTINUE, Transition.CONTINUE_FIXED:
			if code == Transition.CONTINUE_FACING:
				f.facing = f.heading
			_continue_frames(f)
			f.track_mode = Tracking.TIMED
			f.throw_state = 0
			f.anchor_dirty = 1
			f.root_move = move
			_anchor(f)
			return false
		Transition.HOLD_TURN:
			_hold(f)
			f.track_mode = Tracking.TIMED
			if f.rel_angle <= FACING_LIMIT:
				_timed_turn(f, f.target_dir)
			f.throw_state = 0
			return false
		Transition.HOLD_TRACK:
			_hold(f)
			f.track_mode = Tracking.TARGET_SLOW if f.rel_angle < FACING_LIMIT else Tracking.AFTER_ACTIVE
			_clear_turn(f)
			f.throw_state = 0
			return false
		Transition.RESTART:
			_restart(f)
			f.root_move = move
			f.facing = f.heading
			if reanchor:
				_anchor(f)
			f.throw_state = 0
			return false
		Transition.REVERSE:
			f.root_move = move
			f.facing = f.heading
			f.pose_frame = move.length
			f.root_frame = move.length
			if reanchor:
				_anchor(f)
			f.frame_step = -1
			f.throw_state = 0
			return false
		Transition.REWIND:
			f.pose_frame = maxi(f.pose_frame - 1, 1)
			f.frame_step = -1
			f.anchor_dirty = 1
			f.throw_state = 0
			f.root_frame = f.pose_frame
			f.root_move = move
			f.facing = f.heading
			_anchor(f)
			return false
		Transition.TRACK_FAST:
			_restart(f)
			f.track_mode = Tracking.TARGET_FAST
			f.throw_state = 0
			_clear_turn(f)
			f.root_move = move
			f.facing = Fx.s16(f.aim_dir)
			return true
		Transition.TURN, Transition.TURN_AIM:
			f.facing = f.heading if code == Transition.TURN else Fx.s16(f.aim_dir)
			_restart(f)
			f.root_move = move
			var frames := mini(0x10, f.pose_move.length) if move.active_first == 0 else move.active_first - 1
			f.turn_frames = maxi(frames, 1)
			f.aim_dir = f.target_dir if (f.rel_angle & 0xFFFF) < FightMath.QUARTER_TURN \
				else (f.target_dir - FightMath.HALF_TURN) & 0xFFFF
			f.turn_step = _turn_step(f.aim_dir, f.heading, f.turn_frames)
			if reanchor:
				_anchor(f)
			f.track_mode = Tracking.TIMED
			f.throw_state = 0
			return false
		Transition.TRACK_SLOW, Transition.TRACK_HALF, Transition.TRACK:
			_restart(f)
			f.root_move = move
			if f.rel_angle < FACING_LIMIT:
				f.facing = Fx.s16(f.target_dir)
				f.track_mode = TRACK_MODES[code - Transition.TRACK_SLOW]
			else:
				f.facing = Fx.s16(f.aim_dir)
				f.track_mode = Tracking.AFTER_ACTIVE
			f.throw_state = 0
			_clear_turn(f)
			return true
		Transition.TRACK_AIM:
			_restart(f)
			f.track_mode = Tracking.AIM
			f.throw_state = 0
			_clear_turn(f)
			f.root_move = move
			f.facing = Fx.s16(f.aim_dir)
			return true
		Transition.SLIDE, Transition.SLIDE_CONTINUE, Transition.SLIDE_TURNED:
			if code == Transition.SLIDE:
				_restart(f)
			else:
				_continue_frames(f)
			f.track_mode = Tracking.TIMED
			f.root_move = move
			f.facing = Fx.s16(f.target_dir)
			f.throw_state = 0
			f.slide_state = 1
			f.slide_step_x = 0
			f.slide_step_z = 0
			if code == Transition.SLIDE_TURNED:
				f.heading = Fx.s16(f.heading - FightMath.HALF_TURN)
			_timed_turn(f, f.target_dir)
			return true
		Transition.SWAP:
			return false
		Transition.CONTINUE_TRACK_SLOW, Transition.CONTINUE_TRACK:
			_continue_frames(f)
			f.root_move = move
			if f.rel_angle < FACING_LIMIT:
				f.track_mode = Tracking.TARGET_SLOW if code == Transition.CONTINUE_TRACK_SLOW else Tracking.TARGET
			else:
				f.track_mode = Tracking.AFTER_ACTIVE
			f.throw_state = 0
			_clear_turn(f)
			f.anchor_dirty = 1
			_anchor(f)
			return false
		Transition.CONTINUE_EASE, Transition.CONTINUE_EASE_TURNING:
			f.throw_state = 0
			_continue_frames(f)
			f.track_mode = Tracking.EASE
			if code == Transition.CONTINUE_EASE:
				_clear_turn(f)
			f.anchor_dirty = 1
			f.root_move = move
			_anchor(f)
			return false
		Transition.APPROACH:
			_restart(f)
			f.root_move = move
			f.facing = f.heading
			if reanchor:
				_anchor(f)
			f.track_mode = Tracking.APPROACH
			f.throw_state = 0
			return false
		Transition.EASE:
			_restart(f)
			f.throw_state = 0
			f.track_mode = Tracking.EASE
			f.root_move = move
			f.facing = Fx.s16(f.aim_dir)
			return true
		Transition.STEP, Transition.STEP_CROUCH:
			f.pose_frame = Fx.s16(f.pose_frame + 1)
			f.root_frame = Fx.s16(f.root_frame + 1)
			_clamp_to_length(f)
			f.root_move = move
			f.facing = f.heading
			f.step_kind = 1 if code == Transition.STEP else 2
			return false
		Transition.SIDE_STEP:
			_restart(f)
			f.track_mode = Tracking.SIDE_STEP
			f.throw_state = 0
			_clear_turn(f)
			f.facing = f.heading
			f.root_move = move
			if reanchor:
				_anchor(f)
			f.step_cooldown = SIDE_STEP_COOLDOWN
			return false
		Transition.SIDE_STEP_CONTINUE:
			_continue_frames(f)
			f.track_mode = Tracking.SIDE_STEP
			f.throw_state = 0
			_clear_turn(f)
			f.facing = f.heading
			f.root_move = move
			return true
		Transition.LAUNCH, Transition.HIT_AIR:
			_start_airborne(f, code == Transition.LAUNCH)
			return true
		Transition.THROW:
			_start_throw(f, opp)
			return false
		Transition.THROWN:
			_start_thrown(f, opp)
			return false
		Transition.HIT_GUARD, Transition.HIT_COUNTER:
			if code == Transition.HIT_COUNTER:
				_recover_mash(f)
			var push := Reaction.PUSH_GUARD if code == Transition.HIT_GUARD else Reaction.PUSH_COUNTER
			_start_pushed(f, push, f.target_dir, Reaction.PUSH_ANGLE)
			f.track_mode = Tracking.EASE_BY_POSE
			f.facing = Fx.s16(f.aim_dir)
			return true
		Transition.HIT_DOWN:
			_recover_mash(f)
			_start_pushed(f, Reaction.PUSH_DOWN, f.target_dir, Reaction.PUSH_ANGLE_DOWN)
			f.recover_mash = 0
			f.track_mode = Tracking.TIMED
			f.facing = f.heading
			return true
		Transition.HIT_SIDE_1, Transition.HIT_SIDE_3, Transition.HIT_OTHER, Transition.HIT_FRONT, Transition.HIT_BACK:
			_recover_mash(f)
			var base := f.aim_dir if code == Transition.HIT_FRONT else f.target_dir
			_start_pushed(f, Reaction.PUSH_HIT, base, Reaction.PUSH_ANGLE)
			_push_repeat_count(f)
			f.track_mode = Tracking.TIMED
			f.facing = f.heading
			return true
	_restart(f)
	f.root_move = move
	f.heading = Fx.s16(f.target_dir)
	f.facing = f.heading
	return true


## Transitions HOLD_TURN and HOLD_TRACK: the pose restarts and holds for the branch window, the
## root continues on the old root move.
func _hold(f: FighterState) -> void:
	f.pose_frame = 1
	_keep_root_move(f)
	f.hold_frames = f.branch_window
	f.facing = f.heading


## Transitions LAUNCH and HIT_AIR: the ballistic flight from the entry frame (combat.md#launches-
## and-juggles); a launch goes into air kind 5, a juggle keeps the velocity of earlier hits.
func _start_airborne(f: FighterState, launch: bool) -> void:
	if launch:
		f.air_kind = LAUNCH_AIR_KIND
		f.launch_armed = 1
		f.pos_y = f.root_y
		f.move_slot = t.air_kinds[LAUNCH_AIR_KIND][1]
		f.ground_offset = t.air_kinds[LAUNCH_AIR_KIND][0]
	else:
		f.pos_y = f.root_y
		if f.juggle_count == 0:
			f.air_vel_x = 0
			f.air_vel_y = 0
			f.air_vel_z = 0
	_launch_trajectory(f)
	f.pose_frame = f.entry_frame
	f.root_frame = f.entry_frame
	f.air_phase = 1
	f.ballistic = 1
	f.throw_state = 0
	f.root_move = f.move_row
	f.juggle_count = Fx.s16(f.juggle_count + 1)
	_recover_mash(f)
	f.track_mode = Tracking.TIMED
	if f.pose_move.flags & MoveFlag.LAUNCH_ANGLE:
		f.facing = Fx.s16(f.aim_dir + f.reaction[Reaction.PUSH_ANGLE])
	else:
		f.facing = Fx.s16(f.aim_dir)
	_clear_turn(f)


## Transition THROW: the thrower aligns with its victim (combat.md#throws).
func _start_throw(f: FighterState, opp: FighterState) -> void:
	_restart(f)
	f.root_move = f.move_row
	if f.throw_state == 0:
		var target := f.target_dir
		match f.opp_quadrant:
			1:
				f.heading = Fx.s16(target - FightMath.QUARTER_TURN)
			2:
				f.heading = Fx.s16(target)
			3:
				f.heading = Fx.s16(target + FightMath.QUARTER_TURN)
			_:
				f.heading = Fx.s16(target - FightMath.HALF_TURN)
		f.turn_frames = THROW_TURN_FRAMES
		f.facing = f.heading
		f.turn_step = Fx.s16(Fx.div_trunc(Fx.s16(opp.heading - f.heading), THROW_TURN_FRAMES))
		f.pos_x = opp.root_x
		f.pos_z = opp.root_z
	elif f.throw_state < 0 or f.move_row.flags & MoveFlag.PARTNER:
		f.heading = opp.facing
		f.facing = opp.facing
		f.pos_x = opp.root_x
		f.pos_z = opp.root_z
	_stop_push(f)
	f.throw_state = 1 if f.throw_state < 0 else Fx.s16(f.throw_state + 1)


## Transition THROWN: the victim turns to the thrower; the time spent down afterwards comes from the
## thrower's move (combat.md#knock-down-recovery).
func _start_thrown(f: FighterState, opp: FighterState) -> void:
	var move := f.move_row
	if f.throw_state >= 0:
		var pose := f.pose_move
		var counter := not ((Fx.s16(pose.damage_word) == 0 or pose.active_first <= f.pose_frame) and opp.power_timer == 0)
		f.attack_pending = 1 if counter else 0
	_restart(f)
	f.hit_done[3] = 1
	f.root_move = move
	if f.throw_state < 0:
		if move.flags & MoveFlag.PARTNER:
			f.facing = f.heading
			_anchor(f)
	else:
		f.heading = Fx.s16(f.heading - FightMath.HALF_TURN)
		f.facing = f.heading
		_anchor(f)
		FighterSounds.script_stop(f)
	f.throw_state = Fx.s16(f.throw_state - 1) if f.throw_state < 1 else -1
	var other := opp.move_row
	if other.hold_frame == 0:
		var diff := other.length - move.length
		f.recover_frames = other.length if diff < 1 else move.length + diff
		f.recover_frames = clampi(f.recover_frames, 0, MAX_THROWN_RECOVERY)
	else:
		f.recover_frames = other.hold_frame + move.length
	var mash := Fx.s16(Fx.div_trunc(Fx.s16(other.damage_word) * 0x20, 0x2D) + 0x22)
	f.recover_mash = clampi(mash, MIN_THROWN_MASH, MAX_MASH)
	_stop_push(f)


## The hit and guard reactions: restart pushed back along `base` + the record's angle + 180°
## (combat.md#push-back).
func _start_pushed(f: FighterState, push_field: int, base: int, angle_field: int) -> void:
	_load_push(f, f.reaction[push_field])
	f.push_dir = Fx.s16(base + f.reaction[angle_field] - FightMath.HALF_TURN)
	_restart(f)
	f.throw_state = 0
	f.root_move = f.move_row
	_clear_turn(f)


func _stop_push(f: FighterState) -> void:
	f.push_frames = 0
	f.push_speed = 0
	f.push_table_frames = 0


## PushRepeatCount (0x8003159C).
func _push_repeat_count(f: FighterState) -> void:
	var code := f.transition & 0xFFFF
	if code == Transition.HIT_SIDE_1 or code == Transition.HIT_SIDE_3 or code == Transition.HIT_BACK:
		if f.push_repeat_timer == 0:
			f.push_repeat = 0
		elif (f.push_repeat_trans & 0xFFFF) == code:
			f.push_repeat = Fx.s16(f.push_repeat + 1)
		f.push_repeat_trans = f.transition
		f.push_repeat_timer = f.move_row.length + 10


func _finish(f: FighterState) -> void:
	var move := f.move_row
	f.move_row = null
	f.pose_move = move
	f.cur_slot = f.move_slot
	f.move_slot = -1
	var segs := 0
	if move.active_first != 0:
		var d := _descriptor(move)
		segs = 2 if d[2] != 0 else (1 if d[0] != 0 else 0)
	f.attack_seg_count = segs
	f.move_frame = 1 if f.move_changed != 0 else f.pose_frame
	f.cur_transition = f.transition
	f.transition = 0
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	f.apply_end_turn = 0
	f.in_throw = 1 if f.throw_state != 0 else 0
	if f.bank_type == BankType.GON and f.pose_frame == 1 and f.pose_move.air_first != 1:
		f.pos_y = 0


## The first bytes of a move's attack descriptor (joints a0, b0, a1, b1, then two layout bytes).
func _descriptor(move: MoveRow) -> PackedByteArray:
	return AttackRecords.header(move, t)


## LaunchTrajectory (0x8002F2C8): the launch of a hit or launching reaction (combat.md).
func _launch_trajectory(f: FighterState) -> void:
	var move := f.move_row
	var hold := move.hold_frame if move.hold_frame != 0 else f.pose_move.length
	var y := f.root_y
	var ground := Fx.s16(f.ground_offset)
	var dmg := Fx.s16(f.last_damage)
	var jug := Fx.s16(f.juggle_count)
	var speed := dmg + (jug + 1) * 7 + 10 + (10 if f.air_kind == 5 else 0)
	f.air_speed = Fx.s16(clampi(speed, 0, 100))
	var v := Fx.w32(dmg * 4 - (Fx.w32(f.vel_y + f.hit_dir_y) >> 3) - (jug * 7 - 40))
	var vc := mini(v, 100)
	var sq := vc * vc
	if v < -100:
		vc = -100
		sq = 10000
	f.air_vel_y = Fx.s16(-vc)
	var sum := vc + CameraMath.isqrt(absi(Fx.w32(sq + Fx.w32(ground + y) * 12)))
	var time := 0
	if fight.rules.fix_juggle_arc_overflow and sum < 0:
		time = 0
	else:
		# The game divides the (possibly negative) sum as an unsigned int and keeps computing
		# with 32-bit wrap-around; high bounces depend on it (game bug #7).
		time = (sum & 0xFFFFFFFF) / 6
	var e := Fx.w32(-time)
	if time == 0:
		time = 1
		e = -1
	e = Fx.w32(hold + e + 1)
	if e < 1:
		e = 1
	var entry := 0
	if (f.state & StateBit.DOWN) == 0 and e != 1:
		time = (time - 1 + e) & 0xFFFFFFFF
		entry = 1
	elif jug == 0:
		time = (time + 10) & 0xFFFFFFFF
		entry = Fx.w32(hold - time + 1)
		if entry < 1:
			entry = 1
	else:
		entry = e
		var same_anim := f.pose_move.anim_bank == move.anim_bank and f.pose_move.anim == move.anim
		if same_anim and absi(Fx.s16(f.pose_frame) - e) < 10:
			entry = Fx.s16(f.pose_frame) - 10
			var back := -entry
			if entry < 1:
				entry = 1
				back = -1
			time = (time + e + back) & 0xFFFFFFFF
	var n := Fx.w32(time + 1)
	var fall := Fx.w32(n * n * 6) >> 1
	if Fx.w32(Fx.w32(vc * n - fall) - y) < ground:
		f.air_vel_y = Fx.s16(Fx.div_trunc(-Fx.w32(ground + y + fall), n))
	f.push_table = t.launch_push
	f.push_table_pos = 0
	f.push_table_frames = 8
	f.entry_frame = Fx.s16(entry)
	f.push_dir = Fx.s16(f.target_dir - 0x8000)
	if f.air_kind == 1:
		f.air_vel_y = 400
		f.entry_frame = 6
		f.push_frames = maxi(move.length - 6, 0)
		f.push_speed = 0x28
	fight.air_frames[f.index] = n


# ---- MoveStepAll / MoveStep ----------------------------------------------------------------

## MoveStepAll (0x80045450): the fighters in the order of the frame counter's parity.
func step_all() -> void:
	if fight.frame_counter & 1 == 0:
		step(fight.fighters[1])
		step(fight.fighters[0])
	else:
		step(fight.fighters[0])
		step(fight.fighters[1])
	# The third record only while the level's enemies come (0x800B70E8 clear); Ghidra's
	# decompile drops that test.
	if fight.mode == GameMode.FORCE and not fight.force.level_ended():
		step(fight.fighters[2])


## MoveStep (0x800454E0).
func step(f: FighterState) -> void:
	var opp := fight.opponent(f)
	relative_angles(f, opp)
	var a := f.index
	var b := opp.index
	if a > 1:
		a = 1 << (a - 1)
	if b > 1:
		b = 1 << (b - 1)
	f.dist = fight.pair_distance[a + b] & 0xFFFFFFFF
	var big := 0
	if f.char_id == Character.KUMA or f.char_id == Character.TRUE_OGRE:
		big = 1
	if opp.char_id == Character.KUMA or opp.char_id == Character.TRUE_OGRE:
		big += 1
	f.dist_adj = (f.dist - big * 5 * 8) & 0xFFFFFFFF
	if f.got_hit != 0:
		var kind := opp.attack_class
		var react := kind == 0 or (kind == 2 and f.in_air == 0 and f.state & StateBit.DOWN == 0)
		if react:
			_hit_select_reaction(f, opp)
			f.branch_kind = 1
			if f.throw_state > 0:
				f.attack_class = 1
	if fight.mode == GameMode.BALL and fight.ball.point_loser() == f.index + 1:
		# Tekken Ball: the ball landing on this side knocks the fighter off its feet.
		f.in_air = 1
		f.guarded = 0
		f.hit_clean = 1
		relative_angles(f, fight.fighters[TekkenBall.THIRD])
		_hit_select_reaction(f, opp)
		f.attack_class = 1
	if f.move_row == null:
		branch_step(f, opp)
	if f.health == 0 and f.hit_clean != 0:
		var next := fight.move_for_slot(f, f.move_slot)
		if fight.collapse_on_ko == 0:
			if next.stance_slot == STAND_SLOT or next.stance_slot == CROUCH_SLOT:
				f.in_air = 1
				f.guarded = 0
				f.hit_clean = 1
				f.guard = 0
				_hit_select_reaction(f, opp)
				f.attack_class = 1
		elif next.stance_slot == STAND_SLOT or next.stance_slot == CROUCH_SLOT \
				or (next.state & StateBit.DOWN == 0 and next.air_first == 0):
			_collapse(f, opp)
			f.attack_class = 1
	if f.transition == Transition.THROW:
		f.throw_partner = opp.index
		opp.throw_partner = f.index
		opp.in_throw = 1
		f.in_throw = 1


## HitSelectReaction (0x8002EDF8): the defender's reaction move from its reaction record.
func _hit_select_reaction(f: FighterState, attacker: FighterState) -> void:
	var r := f.reaction
	var crouch := 0 if f.state & StateBit.STANDING != 0 else 1     # the crouching slot follows the standing one
	var code := 0
	if f.guarded != 0:
		code = Transition.HIT_GUARD
		f.move_slot = r[Reaction.GUARD + crouch]
	elif f.in_air != 0 or f.pose_move.state & StateBit.AIRBORNE != 0:
		code = Transition.HIT_AIR
		_air_reaction_kind(f, attacker)
	elif f.state & StateBit.DOWN_REVERSED != 0:
		code = Transition.HIT_DOWN
		f.move_slot = r[Reaction.DOWN_OTHER]
	elif f.state & StateBit.DOWN != 0:
		code = Transition.HIT_DOWN
		f.move_slot = r[Reaction.DOWN]
	elif f.counter_hit != 0:
		code = Transition.HIT_COUNTER
		f.move_slot = r[Reaction.COUNTER + crouch]
	else:
		match f.facing_quadrant:
			0:
				code = Transition.HIT_FRONT
				f.move_slot = r[Reaction.FRONT + crouch]
			1:
				code = Transition.HIT_SIDE_1
				f.move_slot = r[Reaction.SIDE_1 + crouch]
			2:
				code = Transition.HIT_BACK
				f.move_slot = r[Reaction.BACK + crouch]
			3:
				code = Transition.HIT_SIDE_3
				f.move_slot = r[Reaction.SIDE_3 + crouch]
	if code != 0:
		# TransitionRemap works on the pending move, which is still the previous one here.
		f.transition = FightMath.transition_remap(code, f.move_row, f.entry_frame) if f.move_row != null else code
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	f.entry_frame = f.pose_frame
	f.move_row = fight.move_for_slot(f, f.move_slot)


## AirReactionKind (0x8002F0E8): the air kind (ground offset and air move) of a juggle hit.
func _air_reaction_kind(f: FighterState, attacker: FighterState) -> void:
	var fresh := f.cur_slot != 0xD62
	if f.cur_slot == 0xD63 and f.pose_frame > 0x12:
		fresh = false
	if f.cur_slot == 0xD64 and f.pose_frame > 0x12:
		fresh = false
	if not fresh:
		if f.cur_slot != 0xD62:
			var height := Fx.s16(f.root_y)
			if f.root_y < 0:
				if 0x3FF < -height:
					f.air_kind = 0
					_air_kind_rows(f)
					return
			elif 0x3FF < height:
				f.air_kind = 0
				_air_kind_rows(f)
				return
		f.air_kind = 2
		_air_kind_rows(f)
		return
	var special := 0
	if attacker.bank_type == BankType.JIN:
		special = 1 if attacker.cur_slot == 0x241 else 0
	if attacker.bank_type == BankType.GUN_JACK and attacker.cur_slot == 0x14A:
		special = 1
		if attacker.move_row != null and (attacker.move_slot & 0xFFFF) - 0x848 < 2:
			special = 2
	if special == 1 or (special != 2 and f.hit_dir_y > 0x6D):
		f.air_kind = 1
	elif f.cur_slot != 0xD58 and f.facing_quadrant == 1:
		f.air_kind = 4
	elif f.cur_slot != 0xD58 and f.facing_quadrant == 3:
		f.air_kind = 3
	else:
		f.air_kind = 0
	_air_kind_rows(f)


func _air_kind_rows(f: FighterState) -> void:
	var row := t.air_kinds[f.air_kind]
	f.move_slot = row[1]
	f.ground_offset = row[0]


## FighterCollapse (0x8002DA80): a KO'd fighter falls with the collapse move 0xD66.
func _collapse(f: FighterState, opp: FighterState) -> void:
	f.move_slot = COLLAPSE_SLOT
	f.move_row = fight.move_for_slot(f, COLLAPSE_SLOT)
	f.pose_frame = 1
	f.entry_frame = 1
	f.transition = FightMath.transition_remap(Transition.RESTART, f.move_row, f.entry_frame)
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	f.guarded = 0
	f.hit_clean = 1
	f.guard = 0
	start_or_advance(f, opp)


# ---- branches -------------------------------------------------------------------------------

## A row of a branch list: its list (a bank's branch rows or the common rows) and index.
class Cursor:
	var rows: Array[PackedInt32Array]
	var i: int

	func _init(list: Array[PackedInt32Array], index: int) -> void:
		rows = list
		i = index

	func row() -> PackedInt32Array:
		return rows[i]


## MoveBranchStep (0x8002DC3C).
func branch_step(f: FighterState, opp: FighterState) -> void:
	f.branch_window = -1
	if f.move_row != null or f.step_cooldown > 0x19:
		return
	var found := _branch_find(f, opp, Cursor.new(f.pose_move.bank.branches, f.pose_move.branches), f.pose_frame)
	var row := found.row()
	if row[ROW_COMMAND] != END:
		f.move_slot = Fx.s16(row[ROW_TARGET])
		f.move_row = fight.move_for_slot(f, f.move_slot)
		f.branch_window = Fx.s16(row[ROW_LAST] - f.pose_frame)
		var flags := row[ROW_FLAGS]
		f.transition = _remap(f, flags & 0x3F)
		f.trans_bit7 = flags >> 7
		f.trans_bit6 = (flags >> 6) & 1
		f.entry_frame = row[ROW_LAST] if f.frame_step < 0 else row[ROW_ENTRY]
		if (f.entry_frame & 0xFFFF) == 0xFF:
			f.entry_frame = f.pose_move.length
		f.branch_kind = 2
		return
	var first := row[ROW_FIRST]
	var last := row[ROW_LAST]
	var look := false
	if f.pose_frame >= first - 5 and f.pose_frame < first:
		look = f.frame_step >= 1 and (f.in_history[f.in_hist_index] & FighterInput.HIST_BUTTONS) != 0
	if not look and first <= f.pose_frame and f.pose_frame <= last and f.frame_step > 0:
		look = true
	if not look and fight.mode == GameMode.BALL:
		# Tekken Ball: some moves look ahead from a tuned frame on (FUN_800B0B54).
		var from := fight.ball.drift(f.player_index)[4]
		look = from != 0 and f.pose_frame >= from and f.frame_step >= 1
	if look:
		var target := fight.move_for_slot(f, row[ROW_TARGET])
		var heading := f.heading
		f.heading = Fx.s16(heading + f.pose_move.end_turn)
		relative_angles(f, opp)
		var ahead := _branch_find(f, opp, Cursor.new(target.bank.branches, target.branches), 1)
		f.heading = heading
		relative_angles(f, opp)
		var hit := ahead.row()
		if hit[ROW_COMMAND] != END:
			f.move_slot = Fx.s16(hit[ROW_TARGET])
			f.move_row = fight.move_for_slot(f, f.move_slot)
			f.entry_frame = first
			f.trans_bit6 = (row[ROW_FLAGS] >> 6) & 1
			f.branch_window = Fx.s16(hit[ROW_LAST] - f.pose_frame)
			var flags := hit[ROW_FLAGS]
			f.transition = _remap(f, flags & 0x3F)
			f.apply_end_turn = 1
			f.branch_kind = 3
			f.trans_bit7 = flags >> 7
			return
	var frame := f.pose_frame + f.frame_step
	if f.pose_move.length < frame or frame < 1:
		f.entry_frame = f.pose_frame
		f.move_slot = Fx.s16(row[ROW_TARGET])
		f.move_row = fight.move_for_slot(f, f.move_slot)
		var flags := row[ROW_FLAGS]
		f.transition = _remap(f, flags & 0x3F)
		f.trans_bit7 = flags >> 7
		f.apply_end_turn = 1
		f.branch_kind = 4
		f.trans_bit6 = (flags >> 6) & 1


func _remap(f: FighterState, code: int) -> int:
	return FightMath.transition_remap(code, f.move_row, f.entry_frame)


## BranchFind (0x8002E078): the first matching row of a list, else its terminator.
func _branch_find(f: FighterState, opp: FighterState, start: Cursor, frame: int) -> Cursor:
	var direction := f.in_dir
	var pressed := f.in_pressed
	fight.situation[f.index] = 0
	var list := start.rows
	var i := start.i
	var ret_list := list
	var ret := 0
	while true:
		var match_list: Array[PackedInt32Array] = list
		var match_i := -1
		while true:
			var cmd := list[i][ROW_COMMAND]
			if cmd == END:
				match_list = list
				match_i = i
				break
			if cmd == RETURN:
				list = ret_list
				i = ret + 1
				continue
			var row_list := list
			var row_i := i
			if cmd == CALL:
				ret_list = list
				ret = i
				row_list = t.common_branches
				row_i = list[i][ROW_TARGET]
			var row := row_list[row_i]
			if _input_match(f, row, direction, pressed) and row[ROW_FIRST] <= frame and frame <= row[ROW_LAST] \
					and _restriction_ok(f, opp, row[ROW_RESTRICTION]) and row[ROW_CONDITION] < BranchCondition.REVERSAL_HIT \
					and (row[ROW_CONDITION] == 0 or condition(row, f, opp)):
				match_list = row_list
				match_i = row_i
				break
			list = row_list
			i = row_i + 1
		var flag := match_list[match_i][ROW_FLAGS]
		if flag == Transition.TO_TERMINATOR:
			while match_list[match_i][ROW_COMMAND] != END:
				match_i += 1
			flag = match_list[match_i][ROW_FLAGS]
		var at_end := match_list[match_i][ROW_COMMAND] == END
		var skip_step := flag == Transition.SIDE_STEP and not at_end and f.step_cooldown != 0
		var skip_throw := fight.mode == GameMode.FORCE and match_list[match_i][ROW_FLAGS] == Transition.THROW and not at_end \
			and f.in_throw == 0 and opp.in_throw != 0
		if not (skip_step or skip_throw):
			return Cursor.new(match_list, match_i)
		list = match_list
		i = match_i + 1
	return null


## practice.ovl FUN_800B3520 (the FREEZE SIGNAL): a branch of the running move could be taken
## now (input aside), or, near the move's end, a branch of its default continuation.
func can_act(f: FighterState, opp: FighterState) -> bool:
	var found := _can_act_find(f, opp, Cursor.new(f.pose_move.bank.branches, f.pose_move.branches), false)
	var row := found.row()
	if row[ROW_COMMAND] != END:
		return true
	var first := row[ROW_FIRST]
	var frame := f.pose_frame
	if ((first - 5 <= frame and frame < first) or (frame >= first and frame <= row[ROW_LAST])) and f.frame_step > 0:
		var target := fight.move_for_slot(f, row[ROW_TARGET])
		var ahead := _can_act_find(f, opp, Cursor.new(target.bank.branches, target.branches), true)
		return ahead.row()[ROW_COMMAND] != END
	return false


## The branch search of FUN_800B3520: window, restriction and condition (no input); for the
## continuation (`ahead`) rows open from the first frame.
func _can_act_find(f: FighterState, opp: FighterState, start: Cursor, ahead: bool) -> Cursor:
	var list := start.rows
	var i := start.i
	var ret_list := list
	var ret := 0
	while true:
		var cmd := list[i][ROW_COMMAND]
		if cmd == END:
			return Cursor.new(list, i)
		if cmd == RETURN:
			list = ret_list
			i = ret + 1
			continue
		var row_list := list
		var row_i := i
		if cmd == CALL:
			ret_list = list
			ret = i
			row_list = t.common_branches
			row_i = list[i][ROW_TARGET]
		var row := row_list[row_i]
		var in_window := row[ROW_FIRST] < 2 and row[ROW_LAST] != 0 if ahead \
			else row[ROW_FIRST] <= f.pose_frame and f.pose_frame <= row[ROW_LAST]
		var c := row[ROW_CONDITION]
		if in_window and _restriction_ok(f, opp, row[ROW_RESTRICTION]) and c < 0x45 \
				and not (row[ROW_COMMAND] == 0x10 and c == 0 and row[ROW_FLAGS] == 2) \
				and ((not ahead and c - 0x3A >= 0 and c - 0x3A < 3) or c == 0 or condition(row, f, opp)):
			return Cursor.new(row_list, row_i)
		list = row_list
		i = row_i + 1
	return null


func _restriction_ok(f: FighterState, opp: FighterState, value: int) -> bool:
	if value == 0:
		return true
	if value < 0x18:
		return f.bank_type == value - 1
	if value < 0x2F:
		return value - 0x18 != f.bank_type
	if value < 0x46:
		return opp.bank_type == value - 0x2F
	if value < 0x5D:
		return f.char_id == value - 0x46
	return value - 0x5D != f.char_id


## InputMatch (0x8002CE7C).
func _input_match(f: FighterState, row: PackedInt32Array, direction: int, pressed: int) -> bool:
	var cmd := row[ROW_COMMAND]
	if cmd < 0xC000:
		if (cmd & direction) == 0 and (cmd & 0x3FE0) != 0:
			return false
		if cmd & 0x1F == 0x10:
			return true
		if cmd & 0x10:
			return (cmd & 0xF & pressed) != 0
		var mask := cmd & 0xF
		if mask != 0 or pressed != 0:
			if (mask & pressed) == 0:
				return false
			return mask == (f.in_held & mask)
		return true
	if cmd < 0xC00E:
		if cmd == 0xC001:
			return _double_tap(f, 6)
		if cmd == 0xC002:
			return _double_tap(f, 4)
		return false
	if cmd < 0xC7FF:
		if cmd - 0xC00E < 0x3F:
			return _sequence_match(f, t.sequences_a[cmd - 0xC00E])
		return false
	if cmd - 0xC7FF < 0x29:
		return _sequence_match(f, t.sequences_b[cmd - 0xC7FF])
	return false


static func _buttons_match(spec: int, pressed: int, held: int) -> bool:
	if spec & 0x1F == 0x10:
		return true
	if spec & 0x10:
		return (pressed & spec & 0xF) != 0
	var mask := spec & 0xF
	if mask == 0 and pressed == 0:
		return true
	return (pressed & mask) != 0 and mask == (held & mask)


static func _prev(i: int) -> int:
	return i - 1 if i > 0 else HISTORY - 1


## FUN_8002CB08 / FUN_8002CBF0: forward (6) or back (4) double tap within 20 frames.
func _double_tap(f: FighterState, direction: int) -> bool:
	var h := f.in_history
	var i := f.in_hist_index
	if h[i] & 0xF != direction:
		return false
	var j := _prev(i)
	if h[j] & 0xF != 5:
		return false
	var budget := 0x13
	var k := j
	while true:
		k = _prev(j)
		var d := h[k] & 0xF
		if d != 5:
			if d != direction:
				return false
			break
		budget -= 1
		j = k
		if budget <= 0:
			break
	if budget <= 0:
		return false
	while true:
		var m := _prev(k)
		if h[m] & 0xF != direction:
			break
		budget -= 1
		k = m
		if budget <= 0:
			break
	return budget > 0


## InputSequenceMatch (0x8002CCD8).
func _sequence_match(f: FighterState, seq: PackedInt32Array) -> bool:
	var window := seq[0]
	var k := seq.size() - 2          # index of the last step (steps start at 1)
	var last := seq[k + 1] if k >= 0 else 0
	var idx := f.in_hist_index & 0xFFFFFFFF
	var want := 0
	var pos := 0
	if (last & 0xF) == last:
		pos = idx + 1 if idx < 0x3B else 0
		want = last
	else:
		if (last & FighterInput.HIST_DIRECTION) != (f.in_history[idx] & FighterInput.HIST_DIRECTION):
			return false
		if not _buttons_match(last >> 8, f.in_pressed, f.in_held):
			return false
		k -= 1
		if k < 0:
			return true
		want = seq[k + 1]
		pos = idx
	while true:
		if window < 1:
			return false
		pos = pos - 1 if pos > 0 else 0x3B
		var entry := f.in_history[pos]
		var hit := false
		if (want & FighterInput.HIST_DIRECTION) == (entry & FighterInput.HIST_DIRECTION):
			var spec := want >> 8
			if spec & 0x1F == 0x10:
				hit = true
			elif spec & 0x10:
				hit = (spec & (entry >> 4)) != 0
			else:
				hit = (spec & 0xF) == (entry >> 4)
		if not hit:
			if entry >> 4:
				return false
		else:
			k -= 1
			if k < 0:
				return true
			want = seq[k + 1]
		window -= 1
	return false


## SituationClassify (0x800313B0): the throw situation code, cached per player.
func _situation_classify(f: FighterState, opp: FighterState) -> void:
	var code := -1
	if f.contact != 0 and opp.in_air == 0 and opp.about_to_hit == 0:
		var q := f.opp_quadrant
		if f.rel_angle < 0x2AAA:
			var s := opp.state
			var table := PackedInt32Array()
			if s & 0x80:
				table = PackedInt32Array([10, 12, 11, 13]) if not s & 0x200 else PackedInt32Array([14, 16, 15, 17])
			elif s & 0x40:
				table = PackedInt32Array([2, 4, 3, 5])
			elif s & 0x20:
				table = PackedInt32Array([6, 8, 7, 9])
			if not table.is_empty() and q >= 0 and q <= 3:
				code = table[q]
		elif f.rel_angle > 0x5555 and opp.state & StateBit.STANDING:
			code = 0x12 if q == 0 else 0x13 if q == 2 else -1
	fight.situation[f.index] = code


## BranchCondition (0x8002E310), types 0x00–0x44.
func condition(row: PackedInt32Array, f: FighterState, opp: FighterState) -> bool:
	var kind := row[ROW_CONDITION]
	var param := row[ROW_PARAMETER]
	if kind == BranchCondition.ALWAYS:
		return true
	if kind == BranchCondition.CONTACT:
		return f.contact != 0
	if kind >= BranchCondition.SITUATION_FIRST and kind <= BranchCondition.SITUATION_5_9:
		if fight.situation[f.index] == 0:
			_situation_classify(f, opp)
		var sit := fight.situation[f.index]
		if kind <= BranchCondition.SITUATION_LAST:
			return f.dist_adj <= param and kind == sit
		if param < f.dist_adj:
			return false
		match kind:
			BranchCondition.SITUATION_2_6: return sit == 2 or sit == 6
			BranchCondition.SITUATION_3_7: return sit == 3 or sit == 7
			BranchCondition.SITUATION_4_8: return sit == 4 or sit == 8
			_: return sit == 5 or sit == 9
	var opp_down := opp.state & StateBit.DOWN != 0
	var turned_away := f.rel_angle > FightMath.QUARTER_TURN
	match kind:
		BranchCondition.NEAR: return f.dist <= param
		BranchCondition.FAR: return f.dist >= param
		BranchCondition.HIT: return f.contact != 0 and (f.attack & opp.guard) == 0
		BranchCondition.OPP_GUARDED: return opp.guarded != 0
		BranchCondition.WHIFFED: return f.whiffed != 0
		BranchCondition.OPP_NOT_THROWING: return opp.transition != Transition.THROW
		BranchCondition.OPP_ATTACKING: return opp.damage != 0
		BranchCondition.OPP_ATTACKING_STANDING: return opp.damage != 0 and (opp.state & StateBit.POSTURE) == StateBit.STANDING
		BranchCondition.OPP_ATTACKING_CROUCHING: return opp.damage != 0 and (opp.state & StateBit.POSTURE) == StateBit.CROUCHING
		BranchCondition.OPP_NOT_ATTACKING: return opp.damage == 0
		BranchCondition.OPP_STANDING: return (opp.state & (StateBit.AIRBORNE | StateBit.POSTURE)) == StateBit.STANDING
		BranchCondition.OPP_CROUCHING: return (opp.state & (StateBit.AIRBORNE | StateBit.POSTURE)) == StateBit.CROUCHING
		BranchCondition.TURNED_AWAY: return turned_away
		BranchCondition.TURNED_SIDE_A: return ((f.heading_delta - 0x4E38) & 0xFFFF) < 0x31C8
		BranchCondition.TURNED_SIDE_B:
			var delta := f.heading_delta & 0xFFFF
			return delta >= FightMath.HALF_TURN and delta <= 0xB1C6
		BranchCondition.FACING_QUADRANT_0: return f.facing_quadrant == 0
		BranchCondition.FACING_QUADRANT_1: return f.facing_quadrant == 1
		BranchCondition.FACING_QUADRANT_3: return f.facing_quadrant == 3
		BranchCondition.FACING_QUADRANT_2: return f.facing_quadrant == 2
		BranchCondition.OPP_QUADRANT_0: return f.opp_quadrant == 0
		BranchCondition.OPP_QUADRANT_1: return f.opp_quadrant == 1
		BranchCondition.OPP_QUADRANT_3: return f.opp_quadrant == 3
		BranchCondition.OPP_QUADRANT_2: return f.opp_quadrant == 2
		BranchCondition.NEVER: return false
		BranchCondition.HIGH_ATTACK_COMING:
			return opp.attack == AttackWord.HIGH and opp.pose_frame <= opp.pose_move.active_last \
				and f.dist < HIGH_ATTACK_RANGE
		BranchCondition.RECOVERED: return f.recover_mash == 0 and f.recover_frames == 0
		BranchCondition.RECOVERING: return f.recover_mash != 0 or f.recover_frames != 0
		BranchCondition.BODY_CONTACT: return f.body_contact != 0
		BranchCondition.BODY_CONTACT_GROUNDED: return f.body_contact != 0 and opp.in_air == 0 and not opp_down
		BranchCondition.OPP_DOWN: return opp_down
		BranchCondition.OPP_NOT_DOWN: return not opp_down
		BranchCondition.OPP_DOWN_NEAR: return opp_down and opp.pose_move.air_first == 0 and f.dist <= param
		BranchCondition.OPP_DOWN_TURNED_AWAY: return opp_down and f.rel_angle >= FightMath.QUARTER_TURN
		BranchCondition.OPP_COUNTER_HIT: return opp.counter_hit != 0 and opp.in_air == 0
		BranchCondition.TAP_LP:
			f.cond_flag_used = 1
			return f.tap_lp != 0
		BranchCondition.TAP_RP:
			f.cond_flag_used = 1
			return f.tap_rp != 0
		BranchCondition.TAP_BOTH:
			f.cond_flag_used = 1
			return f.tap_both != 0
		BranchCondition.KO: return f.health == 0
		BranchCondition.SIDE_CLEAR: return f.side_flag == 0
		BranchCondition.SIDE_SET: return f.side_flag != 0
		BranchCondition.SIDE_CLEAR_TURNED_AWAY: return f.side_flag == 0 and turned_away
		BranchCondition.SIDE_SET_TURNED_AWAY: return f.side_flag != 0 and turned_away
		BranchCondition.NOT_LAUNCHED: return f.launch_armed == 0 and f.health != 0
		BranchCondition.POWER: return f.power_timer != 0
		BranchCondition.NO_POWER: return f.power_timer == 0
	return false


# ---- reversals ------------------------------------------------------------------------------

## MoveBranchAll (0x8004539C): MoveReactionBranch for both fighters by frame parity.
func branch_all() -> void:
	var order: Array[int] = [1, 0]
	if fight.frame_counter & 1:
		order = [0, 1]
	if fight.mode == GameMode.FORCE:
		order.append(2)
	for i in order:
		var f := fight.fighters[i]
		reaction_branch(f, fight.opponent(f))


## MoveReactionBranch (0x8002DB08): a hit fighter's running move may reverse or parry the hit.
func reaction_branch(f: FighterState, opp: FighterState) -> void:
	if opp.char_id == Character.GON:
		return
	f.damage_override = 0
	if f.got_hit == 0:
		return
	var found := _find_reversal(f, opp)
	if found == null:
		return
	var row := found.row()
	f.move_slot = Fx.s16(row[ROW_TARGET])
	f.move_row = fight.move_for_slot(f, f.move_slot)
	f.entry_frame = row[ROW_ENTRY]
	f.was_hit_this_move = 0
	f.got_hit = 0
	f.guarded = 0
	f.hit_clean = 0
	f.hit_cooldown = 0
	f.branch_window = Fx.s16(row[ROW_LAST] - f.pose_frame)
	opp.contact = 0
	opp.hit_done[0] = 0
	opp.hit_done[1] = 0
	opp.hit_done[2] = 0
	opp.contact_this_move = 0
	f.transition = _remap(f, row[ROW_FLAGS] & 0x3F)
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	for s in f.hit_slots:
		s.used = 0
	f.damage_override = Fx.s16(Fx.div_trunc(Fx.s16(opp.damage), 2) + 0x19)


## BranchFindReversal (0x8002E95C): the first row of the running move's list with a reversal
## condition (0x45–0x4B) that matches, or null.
func _find_reversal(f: FighterState, opp: FighterState) -> Cursor:
	var frame := f.pose_frame
	var direction := f.in_dir
	var pressed := f.in_pressed
	var list := f.pose_move.bank.branches
	var i := f.pose_move.branches
	var ret_list := list
	var ret := 0
	while true:
		var cmd := list[i][ROW_COMMAND]
		if cmd == END:
			return null
		if cmd == RETURN:
			list = ret_list
			i = ret + 1
			continue
		var row_list := list
		var row_i := i
		if cmd == CALL:
			ret_list = list
			ret = i
			row_list = t.common_branches
			row_i = list[i][ROW_TARGET]
		var row := row_list[row_i]
		if row[ROW_FIRST] <= frame and frame <= row[ROW_LAST] and _input_match(f, row, direction, pressed) \
				and _restriction_ok(f, opp, row[ROW_RESTRICTION]) and row[ROW_CONDITION] >= BranchCondition.REVERSAL_HIT \
				and _reversal_condition(row, f, opp):
			return Cursor.new(row_list, row_i)
		list = row_list
		i = row_i + 1
	return null


## ReversalCondition (0x8002EB24), types 0x45–0x4B.
func _reversal_condition(row: PackedInt32Array, f: FighterState, opp: FighterState) -> bool:
	var kind := row[ROW_CONDITION]
	var param := row[ROW_PARAMETER]
	var facing_each_other := Fx.s16(f.rel_angle) < FACING_EACH_OTHER and Fx.s16(opp.rel_angle) < FACING_EACH_OTHER
	match kind:
		BranchCondition.REVERSAL_HIT:
			return f.got_hit != 0 and facing_each_other
		BranchCondition.REVERSAL_HIGH, BranchCondition.REVERSAL_MID, BranchCondition.REVERSAL_LOW, \
				BranchCondition.REVERSAL_HIGH_MID:
			if opp.pose_move.flags & MoveFlag.ALERT:
				return false
			if not facing_each_other:
				return false
			var level := Fx.s16(opp.attack)
			var ok := false
			match kind:
				BranchCondition.REVERSAL_HIGH: ok = level == AttackWord.HIGH
				BranchCondition.REVERSAL_MID: ok = level == AttackWord.MID
				BranchCondition.REVERSAL_LOW: ok = level == AttackWord.LOW
				_: ok = level == AttackWord.HIGH or level == AttackWord.MID
			return ok and AttackRecords.uses_joint(opp, param, t)
		BranchCondition.REVERSAL_SLOT:
			return param == Fx.s16(opp.cur_slot) and facing_each_other
		BranchCondition.REVERSAL_ANIM:
			return facing_each_other and _anim_in_list(opp.pose_move, param)
	return false


## MoveInSlotList (the list `param` of 0x80095AB8): whether the attacker's animation tag is in it.
func _anim_in_list(move: MoveRow, list: int) -> bool:
	return t.reversal_lists[list].has(move.anim_bank.anim_tag(move.anim)) if list < t.reversal_lists.size() else false
