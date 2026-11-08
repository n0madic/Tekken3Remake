class_name ArcadeFighterPhysics
extends FighterPhysics
## FUN_8019F3FC: the arcade's physics for both fighters at once. The PlayStation's steps without the
## home-only branches (Gon, Tekken Ball, slides to a point, forced hits), in two passes over the pair:
## first the movement of both, then the bookkeeping of both. The flight keeps the velocities
## FUN_80192978 set, the reaction record follows the opponent's move every frame.

const ROUND_FIGHT := 1
const ROUND_RESULT := 2


## One frame of the pair. The dust and the shake of a landing belong to the frame (ArcadeSimulation).
func update_pair(a: FighterState, b: FighterState, events: SimEvents) -> void:
	for f: FighterState in [a, b]:
		f.landed_a = 0
		f.landed_b = 0
		f.about_to_hit = 0
	moves.relative_angles(b, a)
	_move(a, b, events)
	_move(b, a, events)
	_book(a, b)
	_book(b, a)


func _move(f: FighterState, opp: FighterState, events: SimEvents) -> void:
	_slide(f)
	if f.ballistic == 0 or (f.hit_freeze != 0 and opp.bank_type == BankType.OGRE):
		_step_displacement(f)
	else:
		_flight(f, events)
	if f.in_air == 0:
		f.launch_armed = 0
	if f.turn_frames != 0:
		f.turn_frames = Fx.s16(f.turn_frames - 1)
		f.heading = Fx.s16(f.heading + f.turn_step)
		if f.throw_state == 1:
			f.facing = f.heading
	_push(f)
	_tracking(f, opp)


## The flight without the PlayStation's polar velocity.
func _flight(f: FighterState, events: SimEvents) -> void:
	f.air_vel_y = Fx.s16(f.air_vel_y + 6)
	f.pos_y = Fx.w32(f.pos_y + f.air_vel_y)
	f.pos_x = Fx.w32(f.pos_x + f.air_vel_x)
	f.pos_z = Fx.w32(f.pos_z + f.air_vel_z)
	if f.air_vel_y > 0 and -f.ground_offset <= f.pos_y:
		if f.air_kind == LANDING_SHAKE:
			CameraShake.start(fight, 1, events)
		f.pos_x = f.root_x
		f.pos_y = 0
		f.pos_z = f.root_z
		if f.air_kind == ArcadeMoveSystem.ARCADE_LAUNCH_AIR_KIND:
			f.landed_a = 1
		else:
			f.landed_b = 1
		f.ballistic = 0
		f.air_phase = 2


func _book(f: FighterState, opp: FighterState) -> void:
	if f.attack_alert > 0:
		f.attack_alert -= 1
	if f.hit_cooldown > 0:
		f.hit_cooldown -= 1
	var pose := f.pose_move
	if f.pose_frame < pose.active_first or pose.active_last < f.pose_frame:
		f.active_segs = 0
	else:
		f.active_segs = 1 if (pose.attack_joints >> 16) & 0xFF == 0 else 2
	f.in_air = 1 if f.juggle_count != 0 or (pose.air_first <= f.pose_frame and f.pose_frame <= pose.air_last) else 0
	if f.pose_frame == pose.air_last and f.hold_frames == -1 and f.pose_frame != 1 and f.air_phase != 2:
		if f.was_hit_this_move == 0 or f.air_kind == ArcadeMoveSystem.ARCADE_LAUNCH_AIR_KIND \
				or (f.state_class != 9 and f.state & StateBit.DOWN == 0):
			f.landed_a = 1
		else:
			f.landed_b = 1
	_recovery(f)
	_about_to_hit(f, opp)
	f.reaction = t.reactions[opp.pose_move.reaction]
	_guard_state(f)
	if f.state_class == 9:
		var first := f.pose_move.air_first
		if first != 0 and first <= f.pose_frame:
			f.state |= 4
	_face_shape(f)
	f.ogre_freeze = 1 if f.hit_freeze != 0 and opp.bank_type == BankType.OGRE else 0
	f.air_free = 1 if f.in_reaction == 0 and f.in_air != 0 else 0
	if f.hit_clean == 0 and opp.hit_clean == 0:
		if f.power_timer != 0:
			f.power_timer -= 1
			f.guard &= 0xFFE7
			if f.power_timer < 0:
				f.power_timer = 0
	else:
		f.power_timer = 0
	if f.in_air != 0:
		f.push_repeat_timer = 0
	if f.push_repeat_timer < 1:
		f.push_repeat_timer = 0
	else:
		f.push_repeat_timer -= 1
	if f.push_repeat_timer == 0:
		f.push_repeat = 0


## No Gon: a damage move up to 3 frames before its active window, or the flag.
func _about_to_hit(f: FighterState, _opp: FighterState) -> void:
	var pose := f.pose_move
	if f.damage != 0:
		var low := pose.active_first - 3
		if low < 0:
			low = 1
		if low <= f.pose_frame and f.pose_frame <= pose.active_first:
			f.about_to_hit = 1
	if pose.flags & MoveFlag.ABOUT_TO_HIT:
		f.about_to_hit = 1


## The attack shape only for a first joint below the twelfth (FUN_80194250 / FUN_80194298).
func _face_shape(f: FighterState) -> void:
	if f.hit_clean != 0:
		f.hands.command(3, t.face_shape(t.face_hit, f.costume_slot), 10)
	elif f.skip_step_physics == 0:
		if f.move_changed != 0 and f.damage == 0 and f.in_reaction == 0 \
				and (fight.round_state == ROUND_FIGHT or fight.round_state == ROUND_RESULT):
			f.hands.command(3, t.face_shape(t.face_attack, f.costume_slot), 10)
		if f.damage != 0 and f.pose_move.active_first - f.pose_frame < 8 and f.pose_move.attack_joints & 0xFF < 0xC:
			f.hands.command(3, t.face_shape(t.face_attack, f.costume_slot), 10)


## The guard words: the stick's guard state, with the humans' neutral guard (ArcadeMoveSystem).
func _guard_state(f: FighterState) -> void:
	var pose := f.pose_move
	var direction := f.in_history[f.in_hist_index] & FighterInput.HIST_DIRECTION
	var neutral := (moves as ArcadeMoveSystem).neutral_guard
	if not pose.flags & MoveFlag.STICK_GUARD:
		if f.step_kind != 0:
			if direction == 4:
				_set_guard_state(f, StateWord.GUARD_HIGH)
			elif direction == 1:
				_set_guard_state(f, StateWord.GUARD_LOW)
			else:
				_set_guard_state(f, Fx.s16(pose.state))
				if f.state & StateBit.HUMAN_GUARD and (f.is_cpu != 0 or neutral == 0):
					f.state &= 0xFFFFFFE7
	elif f.is_cpu == 0 and neutral != 0:
		if direction == 4 or direction == 5:
			_set_guard_state(f, StateWord.GUARD_HIGH)
		elif direction == 1 or direction == 2:
			_set_guard_state(f, StateWord.GUARD_LOW)
	elif direction == 4:
		_set_guard_state(f, StateWord.GUARD_HIGH)
	elif direction == 1:
		_set_guard_state(f, StateWord.GUARD_LOW)
	f.guard = f.state & StateBit.GUARDS if f.in_air == 0 and f.rel_angle < 0x4000 else 0
