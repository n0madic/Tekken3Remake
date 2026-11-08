class_name ArcadeMoveSystem
extends MoveSystem
## The arcade's move lifecycle (World ver. E1, docs/research/arcade/moves.md): the PlayStation's
## engine on flat data. One table of rows for all bank types, no CALL / RETURN rows, attack joints in
## the row, the arcade's slot numbers and air kinds.
##
## Written from the decompiled FUN_8018C498 (start all), FUN_80190FF8 (start or advance), FUN_8018F528
## (step and branch step), FUN_8018F9A4 (branch find), FUN_8018E8D8 (input match), FUN_80190600 (hit
## reaction), FUN_80190A7C (air kind), FUN_80190C78 (launch), FUN_8018F424 / FUN_80190240 /
## FUN_80190334 (reversals); proven by tests/fight/test_arcade_fight_traces.gd.

const ARCADE_STAND_SLOT := 3
const ARCADE_CROUCH_SLOT := 0x19
const ARCADE_COLLAPSE_SLOT := 0xE5C
const ARCADE_LAUNCH_AIR_KIND := 0xC
const THROW_REACTION_SLOT := 0                    ## the victim's slot: the reaction record's first word
const THROW_START_A := 0x1F                       ## transitions that start the thrower (with Transition.THROW)
const THROW_START_B := 0x20
const SEQUENCES_A_FIRST := 0xC00C
const SEQUENCES_A_COUNT := 0x3F
const PRESS_COUNT_FIRST := 0xC007
const PRESS_COUNT_LAST := 0xC00A
const PRESS_COUNT_NEEDED := 4
const COOLDOWN_FLAGS := 0x1C                      ## a side step row is passed over while cooling down
const REVERSAL_FIRST := 0x45
const FRESH_AIR_A := 0xE53                        ## air reaction slots a juggle hit does not count as fresh in
const FRESH_AIR_B := 0xE54
const AIR_WINDOWS: Array[Array] = [
	[0xE55, 0xE58, 0x12], [0xE56, 0xE59, 10], [0xE57, 0xE5A, 7],
]                                                 ## slots and the pose frame that ends their freshness
const AIR_STAND_SLOT := 0xE46
const AIR_LIFT := 0x6D                            ## hit direction y above it: air kind 1
const AIR_HIGH := 0x3FF
const THROWN_MASH_SCALE := 0x20
const THROWN_MASH_DIVISOR := 0x2D
const POWER_FRAMES := 0x78
const ALERT_FRAMES := 9
const BRANCH_COOLDOWN_LIMIT := 0x19
const LOOK_AHEAD_FRAMES := 5
const LAUNCH_SPEED_KINDS: Array[int] = [3, 5]
const KIND_RESTART_AT_6 := 1

var neutral_guard := 0                            ## 0x8021FC70: humans' neutral guard (a setting)


func launch_air_kind() -> int:
	return ARCADE_LAUNCH_AIR_KIND


## The humans' guard stays only with the neutral guard setting.
func guard_off(f: FighterState) -> bool:
	return f.is_cpu != 0 or neutral_guard == 0


# ---- angles ---------------------------------------------------------------------------------

## FUN_801A0A6C: both fighters' angles from the directions FUN_8018B050 stored.
func relative_angles(f: FighterState, opp: FighterState) -> void:
	_own_angles(f)
	_own_angles(opp)
	f.opp_quadrant = opp.facing_quadrant
	opp.opp_quadrant = f.facing_quadrant
	f.opp_rel_angle = opp.rel_angle
	opp.opp_rel_angle = f.rel_angle


func _own_angles(f: FighterState) -> void:
	f.heading_delta = (f.heading - f.target_dir) & 0xFFFF
	f.facing_quadrant = FightMath.quadrant(f.heading_delta)
	f.rel_angle = FightMath.fold(f.heading_delta)
	if f.dist > 0x200:
		f.aim_dir = f.target_dir if f.rel_angle < 0x4000 else (f.target_dir - 0x8000) & 0xFFFF


# ---- starting moves -------------------------------------------------------------------------

## The order of the frame: fighter 0 first unless the main loop's frame is odd.
func _first() -> FighterState:
	return fight.fighters[1 if fight.frame_counter & 1 else 0]


func _second() -> FighterState:
	return fight.fighters[0 if fight.frame_counter & 1 else 1]


static func _reached_entry(f: FighterState) -> bool:
	return f.move_row != null and f.entry_frame <= f.pose_frame


## FUN_8018C498.
func start_all() -> void:
	var a := _first()
	var b := _second()
	if _reached_entry(b) and b.transition == Transition.THROW:
		throw_victim_start(a, b)
		start_or_advance(a, b)
		start_or_advance(b, a)
		return
	if _reached_entry(a) and a.transition == Transition.THROW:
		throw_victim_start(b, a)
	start_or_advance(b, a)
	start_or_advance(a, b)


## FUN_8018F318: the victim's move is the first word of the thrower's reaction record.
func throw_victim_start(victim: FighterState, thrower: FighterState) -> void:
	var slot := t.reactions[thrower.move_row.reaction][THROW_REACTION_SLOT]
	victim.move_slot = slot
	victim.move_row = fight.move_for_slot(victim, slot)
	victim.pose_frame = 1
	victim.entry_frame = 1
	victim.transition = FightMath.transition_remap(Transition.THROWN, victim.move_row, victim.entry_frame)
	victim.trans_bit7 = 0
	victim.trans_bit6 = 0


## FUN_80190FF8.
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
	var pose_flags := f.pose_move.flags
	var move_flags := move.flags
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
	f.in_reaction = f.hit_clean
	if f.got_hit != 0 and f.health != 0:
		f.hit_freeze = f.hit_freeze_in
	if f.branch_kind == 3 or f.branch_kind == 1 or move.anim != f.pose_move.anim:
		f.move_changed = 1
	if pose_flags & MoveFlag.STICK_GUARD and move_flags & MoveFlag.STICK_GUARD:
		f.move_flag_ba = 1
	if pose_flags & MoveFlag.POWER:
		f.power_timer = POWER_FRAMES
	if move_flags & MoveFlag.ALERT:
		f.attack_alert = ALERT_FRAMES
	if f.trans_bit7 != 0:
		f.trans_bit7 = 0
		f.heading = Fx.s16(f.heading - FightMath.HALF_TURN)
		f.facing = Fx.s16(f.facing - FightMath.HALF_TURN)
	if f.apply_end_turn != 0 and f.transition != Transition.THROWN:
		f.heading = Fx.s16(f.heading + f.pose_move.end_turn)
		f.facing = f.heading
	f.apply_end_turn = 0
	relative_angles(f, opp)
	var reanchor := 1 if pose_flags & MoveFlag.REANCHOR else 0
	var tail := _transition(f, opp, f.transition, reanchor)
	if tail and reanchor != 0:
		f.pos_x = f.root_x
		f.pos_z = f.root_z
	_finish(f)


func _reset_for_move(f: FighterState, opp: FighterState, _move: MoveRow) -> void:
	f.hit_done[3] = 0
	f.air_phase = 0
	f.slide_state = 0
	f.track_mode = Tracking.NONE
	f.hold_frames = -1
	f.opp_start_x = opp.root_x
	f.opp_start_z = opp.root_z
	f.frame_step = 1
	f.hit_done[0] = 0
	f.track_accum = 0
	f.step_kind = 0
	f.cond_flag_used = 0
	f.skip_step_physics = 0
	f.move_flag_ba = 0
	f.hit_freeze = 0
	f.hit_cooldown = 0


func _load_move_words(f: FighterState, move: MoveRow) -> void:
	if f.damage_override == 0:
		f.attack_class = move.attack_class()
		f.damage = 0 if f.attack_class == 1 else move.damage()
	else:
		f.damage = f.damage_override
	f.state = move.state & 0xFFFFFFFF
	f.attack = move.attack
	f.state_class = (f.state >> StateBit.CLASS_SHIFT) & 0x1F
	f.guard = f.state & StateBit.GUARDS
	f.attack_hi = f.attack >> 8
	if f.state & StateBit.HUMAN_GUARD and guard_off(f):
		f.state &= ~StateBit.GUARDS & 0xFFFFFFFF
		f.guard &= ~StateBit.GUARDS & 0xFFFF


func _transition(f: FighterState, opp: FighterState, code: int, reanchor: int) -> bool:
	match code:
		Transition.REVERSE:
			var last := f.move_row.length - 1
			f.root_move = f.move_row
			f.facing = f.heading
			f.pose_frame = last
			f.root_frame = last
			if reanchor:
				_anchor(f)
			f.frame_step = -1
			f.throw_state = 0
			return false
		THROW_START_A, THROW_START_B:
			_start_throw(f, opp)
			return false
	return super(f, opp, code, reanchor)


## Transitions LAUNCH and HIT_AIR: the flight from the entry frame. A launch goes into air kind 0xC;
## a juggle keeps the velocity of the earlier hits.
func _start_airborne(f: FighterState, launch: bool) -> void:
	if launch:
		f.air_kind = ARCADE_LAUNCH_AIR_KIND
		f.launch_armed = 1
		f.move_slot = t.air_kinds[ARCADE_LAUNCH_AIR_KIND][1]
		f.ground_offset = t.air_kinds[ARCADE_LAUNCH_AIR_KIND][0]
	f.pos_y = f.root_y
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


## Transitions 0x1F–0x21: the thrower aligns with its victim.
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
	elif f.throw_state < 0:
		f.heading = Fx.s16(f.heading - FightMath.HALF_TURN)
		f.facing = f.heading
		f.pos_x = opp.root_x
		f.pos_z = opp.root_z
	_stop_push(f)
	f.throw_state = 1 if f.throw_state < 0 else Fx.s16(f.throw_state + 1)


## Transition THROWN; FUN_80190978 sets the recovery after the throw.
func _start_thrown(f: FighterState, opp: FighterState) -> void:
	var move := f.move_row
	if f.throw_state >= 0:
		var pose := f.pose_move
		var counter := not ((Fx.s16(pose.damage_word) == 0 or pose.active_first <= f.pose_frame) and opp.power_timer == 0)
		f.attack_pending = 1 if counter else 0
	_restart(f)
	f.hit_done[3] = 1
	f.root_move = move
	if f.throw_state >= 0:
		f.heading = Fx.s16(f.heading - FightMath.HALF_TURN)
		f.facing = f.heading
		_anchor(f)
		FighterSounds.script_stop(f)
	f.throw_state = Fx.s16(f.throw_state - 1) if f.throw_state < 1 else -1
	var other := opp.move_row
	if other.hold_frame == 0:
		var diff := other.length - move.length
		f.recover_frames = clampi(other.length if diff < 1 else move.length + diff, 0, MAX_THROWN_RECOVERY)
	else:
		f.recover_frames = other.hold_frame + move.length
	var mash := Fx.s16(Fx.div_trunc(Fx.s16(other.damage_word) * THROWN_MASH_SCALE, THROWN_MASH_DIVISOR) + 0x22)
	f.recover_mash = clampi(mash, MIN_THROWN_MASH, MAX_MASH)
	_stop_push(f)


## The end of FUN_80190FF8.
func _finish(f: FighterState) -> void:
	var move := f.move_row
	f.move_row = null
	f.pose_move = move
	f.cur_slot = f.move_slot
	f.move_slot = -1
	var segments := 0
	if move.active_first != 0:
		if (move.attack_joints >> 16) & 0xFF != 0:
			segments = 2
		elif move.attack_joints & 0xFF != 0:
			segments = 1
	f.attack_seg_count = segments
	f.move_frame = 1 if f.move_changed != 0 else f.pose_frame
	f.cur_transition = f.transition
	f.transition = 0
	f.trans_bit7 = 0
	f.trans_bit6 = 0


## FUN_80190C78.
func _launch_trajectory(f: FighterState) -> void:
	var move := f.move_row
	f.entry_frame = 1
	var hold := move.hold_frame if move.hold_frame != 0 else f.pose_move.length
	var y := f.root_y
	var ground := Fx.s16(f.ground_offset)
	var dmg := Fx.s16(f.last_damage)
	var jug := Fx.s16(f.juggle_count)
	var speed := dmg + (jug + 1) * 7 + 10 + (10 if f.air_kind == ARCADE_LAUNCH_AIR_KIND else 0)
	f.air_speed = Fx.s16(clampi(speed, 0, 100))
	var v := mini(Fx.w32(dmg * 4 - (Fx.w32(f.vel_y + f.hit_dir_y) >> 3) - (jug * 7 - 0x28)), 100)
	f.air_vel_y = Fx.s16(-v)
	var time := Fx.div_trunc(Fx.w32(v + CameraMath.isqrt(absi(Fx.w32(v * v + Fx.w32(ground + y) * 12)))), 6)
	var e := -time
	if time < 1:
		time = 1
		e = -1
	e = maxi(hold + e + 1, 1)
	if f.state & StateBit.DOWN == 0 and e != 1:
		time = time - 1 + e
		e = 1
	elif jug == 0:
		time += 10
		e = maxi(hold - time + 1, 1)
	elif f.pose_move.anim == move.anim and absi(f.pose_frame - e) < 10:
		var i := f.pose_frame - 10
		var back := -i
		if i < 1:
			i = 1
			back = -1
		time = time + e + back
		e = i
	var n := time + 1
	var fall := Fx.w32(n * n * 6) >> 1
	if Fx.w32(Fx.w32(v * n - fall) - y) < ground:
		f.air_vel_y = Fx.s16(-Fx.div_trunc(Fx.w32(ground + y + fall), n))
	f.push_table = t.launch_push
	f.push_table_pos = 0
	f.push_table_frames = 8
	f.entry_frame = Fx.s16(e)
	f.push_dir = Fx.s16(f.target_dir - FightMath.HALF_TURN)
	if f.air_kind == KIND_RESTART_AT_6:
		f.air_vel_y = 400
		f.entry_frame = 6
		f.push_frames = maxi(move.length - 6, 0)
		f.push_speed = 0x28
	elif f.air_kind in LAUNCH_SPEED_KINDS:
		f.push_frames = maxi(Fx.s16(move.length - f.entry_frame), 0)
		f.push_speed = 0x14
	fight.air_frames[f.index] = n


# ---- the frame's move step ------------------------------------------------------------------

## FUN_8018C340: the branch steps, a KO's collapse, then the air velocities of a launch.
func step_all() -> void:
	var a := _first()
	var b := _second()
	_step_collapse(b, a)
	_step_collapse(a, b)
	_air_velocity(b, a)
	_air_velocity(a, b)


func _step_collapse(f: FighterState, opp: FighterState) -> void:
	_step_against(f, opp)
	if f.health != 0 or f.hit_clean == 0:
		return
	var row := fight.move_for_slot(f, f.move_slot)
	if row.stance_slot == ARCADE_STAND_SLOT or row.stance_slot == ARCADE_CROUCH_SLOT \
			or (row.state & StateBit.DOWN == 0 and row.air_first == 0):
		_collapse(f, opp)


## FUN_80192978.
func _air_velocity(f: FighterState, opp: FighterState) -> void:
	if f.cur_transition != Transition.LAUNCH and f.cur_transition != Transition.HIT_AIR:
		return
	f.air_vel_x = Fx.s16(Fx.div_trunc(f.air_speed * FightMath.sin_q15(opp.target_dir, t), 0x7FFF))
	f.air_vel_z = Fx.s16(Fx.div_trunc(f.air_speed * FightMath.cos_q15(opp.target_dir, t), 0x7FFF))


## FUN_8018F528.
func _step_against(f: FighterState, opp: FighterState) -> void:
	f.branch_window = -1
	if f.got_hit != 0:
		var kind := opp.attack_class
		if kind == 0 or (kind == 2 and f.in_air == 0 and f.state & StateBit.DOWN == 0):
			_hit_select_reaction(f, opp)
			f.branch_kind = 1
			return
	branch_step(f, opp)


## FUN_80190600's tests: the guard word against the attack, and no remap of the transition.
func _hit_guarded(f: FighterState, attacker: FighterState) -> bool:
	return f.guard & attacker.attack != 0


func _hit_transition(_f: FighterState, code: int) -> int:
	return code


## FUN_80190A7C.
func _air_reaction_kind(f: FighterState, _attacker: FighterState) -> void:
	var slot := f.cur_slot & 0xFFFF
	var fresh := slot != FRESH_AIR_A and slot != FRESH_AIR_B
	for window: Array in AIR_WINDOWS:
		if slot in [window[0], window[1]] and f.pose_frame > (window[2] as int):
			fresh = false
	var kind := 0
	if fresh:
		if f.hit_dir_y > AIR_LIFT:
			kind = 1
		elif slot != AIR_STAND_SLOT and f.facing_quadrant == 1:
			kind = 9
		elif slot != AIR_STAND_SLOT and f.facing_quadrant == 3:
			kind = 6
	elif slot == FRESH_AIR_A or Fx.s16(absi(f.root_y)) <= AIR_HIGH:
		kind = 4
	f.air_kind = kind
	_air_kind_rows(f)


## FUN_8018F3A0: a KO'd fighter falls with slot 0xE5C (the pending slot stays).
func _collapse(f: FighterState, opp: FighterState) -> void:
	var row := fight.move_for_slot(f, ARCADE_COLLAPSE_SLOT)
	f.pose_move = row
	f.root_move = row
	f.move_row = row
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

## FUN_8018F528's branch step.
func branch_step(f: FighterState, opp: FighterState) -> void:
	if f.move_row != null or f.step_cooldown > BRANCH_COOLDOWN_LIMIT:
		return
	var rows := f.pose_move.bank.branches
	var row := rows[_find(f, opp, f.pose_move.branches, f.pose_frame)]
	if row[ROW_COMMAND] != END:
		_take(f, row[ROW_TARGET], row[ROW_FLAGS])
		f.branch_window = Fx.s16(row[ROW_LAST] - f.pose_frame)
		f.entry_frame = row[ROW_LAST] if f.frame_step < 0 else row[ROW_ENTRY]
		if (f.entry_frame & 0xFFFF) == 0xFF:
			f.entry_frame = f.pose_move.length
		f.branch_kind = 2
		return
	var first := row[ROW_FIRST]
	var last := row[ROW_LAST]
	var newest := f.in_history[f.in_hist_index]
	var look := first - LOOK_AHEAD_FRAMES <= f.pose_frame and f.pose_frame < first and f.frame_step >= 1 \
		and newest & FighterInput.HIST_BUTTONS != 0
	if not look:
		look = first <= f.pose_frame and f.pose_frame <= last and f.frame_step > 0
	if look:
		var target := fight.move_for_slot(f, row[ROW_TARGET])
		var heading := f.heading
		f.heading = Fx.s16(heading + f.pose_move.end_turn)
		relative_angles(f, opp)
		var hit := target.bank.branches[_find(f, opp, target.branches, 1)]
		f.heading = heading
		relative_angles(f, opp)
		if hit[ROW_COMMAND] != END:
			f.entry_frame = first
			_take(f, hit[ROW_TARGET], hit[ROW_FLAGS])
			f.branch_window = Fx.s16(hit[ROW_LAST] - f.pose_frame)
			f.trans_bit6 = row[ROW_FLAGS] & 0x40
			f.apply_end_turn = 1
			f.branch_kind = 3
			return
	var frame := f.pose_frame + f.frame_step
	if frame >= 1 and frame <= f.pose_move.length:
		return
	f.entry_frame = f.pose_frame
	_take(f, row[ROW_TARGET], row[ROW_FLAGS])
	f.apply_end_turn = 1
	f.branch_kind = 4


## A branch row's target becomes the pending move; the transition's remap reads the entry frame
## the fighter holds when the row is taken.
func _take(f: FighterState, target: int, flags: int) -> void:
	f.move_slot = Fx.s16(target)
	f.move_row = fight.move_for_slot(f, f.move_slot)
	f.transition = _remap(f, flags & 0x3F)
	f.trans_bit7 = flags & 0x80
	f.trans_bit6 = flags & 0x40


## FUN_8018F9A4: the index of the first matching row of a list, else of its terminator.
func _find(f: FighterState, opp: FighterState, start: int, frame: int) -> int:
	var rows := f.pose_move.bank.branches
	fight.situation[f.index] = 0
	var i := start
	while true:
		var row := rows[i]
		if row[ROW_COMMAND] != END and not _row_matches(f, opp, row, frame):
			i += 1
			continue
		if row[ROW_COMMAND] != END and row[ROW_FLAGS] == Transition.TO_TERMINATOR:
			while rows[i][ROW_COMMAND] != END:
				i += 1
			row = rows[i]
		if row[ROW_FLAGS] != COOLDOWN_FLAGS or row[ROW_COMMAND] == END or f.step_cooldown == 0:
			return i
		i += 1
	return -1


func _row_matches(f: FighterState, opp: FighterState, row: PackedInt32Array, frame: int) -> bool:
	return _input_match(f, row, f.in_dir, f.in_pressed) and row[ROW_FIRST] <= frame and frame <= row[ROW_LAST] \
		and _restriction_ok(f, opp, row[ROW_RESTRICTION]) and row[ROW_CONDITION] < REVERSAL_FIRST \
		and (row[ROW_CONDITION] == 0 or condition(row, f, opp))


## FUN_8018F914.
func _restriction_ok(f: FighterState, opp: FighterState, value: int) -> bool:
	if value == 0:
		return true
	if value < 0x18:
		return f.bank_type == value - 1
	if value < 0x2F:
		return f.bank_type != value - 0x18
	if value < 0x46:
		return opp.bank_type == value - 0x2F
	if value < 0x5C:
		return f.char_id == value - 0x46
	return f.char_id != value - 0x5C


## FUN_8018E8D8: the arcade's commands: 0xC00C on are its motion sequences, 0xC007–0xC00A count
## presses of a button in the last second.
func _input_match(f: FighterState, row: PackedInt32Array, direction: int, pressed: int) -> bool:
	var cmd := row[ROW_COMMAND]
	if cmd < END or cmd >= 0xC7FF:
		return super(f, row, direction, pressed)
	if cmd == 0xC001:
		return _double_tap(f, 6)
	if cmd == 0xC002:
		return _double_tap(f, 4)
	if cmd >= PRESS_COUNT_FIRST and cmd <= PRESS_COUNT_LAST:
		return f.press_count[cmd - PRESS_COUNT_FIRST] >= PRESS_COUNT_NEEDED
	if cmd >= SEQUENCES_A_FIRST and cmd - SEQUENCES_A_FIRST < SEQUENCES_A_COUNT:
		return _sequence_match(f, t.sequences_a[cmd - SEQUENCES_A_FIRST])
	return false


## FUN_8018FB3C: body contact has no flags of its own, it is the push of the last separation.
func condition(row: PackedInt32Array, f: FighterState, opp: FighterState) -> bool:
	var kind := row[ROW_CONDITION]
	if kind == BranchCondition.BODY_CONTACT:
		return _pushed(f)
	if kind == BranchCondition.BODY_CONTACT_GROUNDED:
		return _pushed(f) and opp.in_air == 0 and opp.state & StateBit.DOWN == 0
	return super(row, f, opp)


static func _pushed(f: FighterState) -> bool:
	return f.body_push_x != 0 or f.body_push_y != 0 or f.body_push_z != 0


# ---- reversals ------------------------------------------------------------------------------

## FUN_8018C2DC.
func branch_all() -> void:
	var a := _first()
	var b := _second()
	reaction_branch(b, a)
	reaction_branch(a, b)


## FUN_8018F424.
func reaction_branch(f: FighterState, opp: FighterState) -> void:
	f.damage_override = 0
	if f.got_hit == 0:
		return
	var row := _reversal_row(f, opp)
	if row.is_empty():
		return
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
	opp.contact_this_move = 0
	f.transition = _remap(f, row[ROW_FLAGS] & 0x3F)
	f.trans_bit7 = 0
	f.trans_bit6 = 0
	f.damage_override = Fx.s16(Fx.div_trunc(Fx.s16(opp.damage), 2) + 0x19)


## FUN_80190240: the first row of the running move's list with a matching reversal condition.
func _reversal_row(f: FighterState, opp: FighterState) -> PackedInt32Array:
	var rows := f.pose_move.bank.branches
	var i := f.pose_move.branches
	while rows[i][ROW_COMMAND] != END:
		var row := rows[i]
		if row[ROW_FIRST] <= f.pose_frame and f.pose_frame <= row[ROW_LAST] and _input_match(f, row, f.in_dir, f.in_pressed) \
				and _restriction_ok(f, opp, row[ROW_RESTRICTION]) and row[ROW_CONDITION] >= REVERSAL_FIRST \
				and _reversal_condition(row, f, opp):
			return row
		i += 1
	return PackedInt32Array()


## FUN_80190334.
func _reversal_condition(row: PackedInt32Array, f: FighterState, opp: FighterState) -> bool:
	var kind := row[ROW_CONDITION]
	var param := row[ROW_PARAMETER]
	var facing_each_other := Fx.s16(f.rel_angle) < FACING_EACH_OTHER and Fx.s16(opp.rel_angle) < FACING_EACH_OTHER
	match kind:
		BranchCondition.REVERSAL_HIGH, BranchCondition.REVERSAL_MID, BranchCondition.REVERSAL_LOW, \
				BranchCondition.REVERSAL_HIGH_MID:
			if opp.pose_move.flags & MoveFlag.ALERT or not facing_each_other:
				return false
			var level := Fx.s16(opp.attack)
			var ok := false
			match kind:
				BranchCondition.REVERSAL_HIGH: ok = level == AttackWord.HIGH
				BranchCondition.REVERSAL_MID: ok = level == AttackWord.MID
				BranchCondition.REVERSAL_LOW: ok = level == AttackWord.LOW
				_: ok = level == AttackWord.HIGH or level == AttackWord.MID
			return ok and _uses_joint(opp.pose_move, param)
	return super(row, f, opp)


static func _uses_joint(move: MoveRow, joint: int) -> bool:
	if joint == 0:
		return true
	for shift: int in [0, 8, 16, 24]:
		if (move.attack_joints >> shift) & 0xFF == joint:
			return true
	return false
