class_name FighterPhysics
extends RefCounted
## FighterMovePhysics (0x8003F330): slides, the move's step displacement, launches, push-back,
## timed turns and tracking, and the per-frame bookkeeping (moves.md#displacement-and-slides,
## moves.md#facing-and-tracking, moves.md#per-frame-bookkeeping-in-fightermovephysics).
## Written from the verified port `move_physics` in tools/research/fight_sim.py.
## Tekken Ball drifts the anchor of some moves (the tuning of FUN_800B0B54).
## Tekken Force's thrown bodies and power moves hit whoever they touch (forced hits).

const LANDING_SHAKE := 1        ## air kind whose landing shakes the camera (script 1)
const FORCED_ATTACK := AttackWord.UNBLOCKABLE  ## the attack of a forced hit (attackHi 6)
const FORCED_ATTACK_HI := 6
const FORCED_THROWN_SPEED := 0x59   ## a thrown CPU body hits above this speed
const FORCED_THROWN_FRAME := 10     ## ... after this frame of the throw
const FORCED_DAMAGE := 10
const POWER_MOVE_COST := 0xA0000    ## the health a power move costs

var fight: FightState
var t: FightTables
var moves: MoveSystem


func _init(fight_state: FightState, move_system: MoveSystem) -> void:
	fight = fight_state
	t = fight_state.tables
	moves = move_system


## (length · sin / 0x7FFF, length · cos / 0x7FFF) in 32-bit C arithmetic.
func polar(length: int, angle: int) -> Vector2i:
	return Vector2i(Fx.div_trunc(Fx.w32(length * FightMath.sin_q15(angle, t)), 0x7FFF),
		Fx.div_trunc(Fx.w32(length * FightMath.cos_q15(angle, t)), 0x7FFF))


static func clamp_symmetric(v: int, limit: int) -> int:
	v = Fx.s16(v)
	if v < 0:
		return Fx.s16(-limit) if v < -limit else v
	return Fx.s16(limit) if limit < v else v


static func track_budget(step: int, accum: int, limit: int) -> int:
	var a := absi(Fx.s16(accum))
	step = Fx.s16(step)
	if limit < a + absi(step):
		var rest := Fx.s16(limit - a)
		return -rest if step < 0 else rest
	return 0


static func _degrees(d: int) -> int:
	return Fx.div_trunc(d * 0xFFFF, 0x168)


static func _towards(target: int, current: int, frames: int) -> int:
	return Fx.s16(Fx.div_trunc(Fx.s16(target - current), frames))


## FighterMovePhysics for one fighter; effects outside the record go to `events`.
func update(f: FighterState, events: SimEvents) -> void:
	var opp := fight.opponent(f)
	f.landed_a = 0
	f.landed_b = 0
	f.about_to_hit = 0
	moves.relative_angles(f, opp)
	_slide(f)
	if f.ballistic == 0 or (f.hit_freeze != 0 and opp.bank_type == BankType.OGRE):
		_step_displacement(f)
	else:
		_flight(f, events)
	if f.char_id == Character.GON and f.in_reaction != 0 and f.juggle_count == 0:
		if f.in_air == 0:
			f.pos_y = 0
		else:
			var y := Fx.w32(f.root_y + 0x80)
			if y < 0:
				f.pos_y = y >> 1
	if fight.mode == GameMode.BALL:
		_ball_drift(f)
	if f.in_air == 0:
		f.launch_armed = 0
	if f.turn_frames != 0:
		f.turn_frames = Fx.s16(f.turn_frames - 1)
		f.heading = Fx.s16(f.heading + f.turn_step)
		if f.throw_state == 1:
			f.facing = f.heading
	if f.slide_to_point == 1:
		_slide_to_point(f)
	_push(f)
	_tracking(f, opp)
	_bookkeeping(f, opp, events)


## Slides (transitions SLIDE*): from the root move's air window on, the distance to the opponent
## (less 500, at most 0xA0C) is spread over the window; at its end the anchor snaps to the root.
func _slide(f: FighterState) -> void:
	if f.slide_state == 1:
		var root := f.root_move
		if root.air_first <= f.pose_frame:
			var frames := root.air_last - f.pose_frame
			if frames == 0:
				frames = 1
			f.slide_state = 2
			var d := fight.fighter_distance & 0xFFFFFFFF
			var total := 0xA0C if d > 0xC00 else Fx.w32(d - 500)
			var s := polar(Fx.s16(Fx.div_trunc(total, frames)), f.target_dir)
			f.slide_step_x = s.x
			f.slide_step_z = s.y
			f.air_phase = 2
	elif f.slide_state == 2:
		f.pos_z = Fx.w32(f.pos_z + f.slide_step_z)
		f.pos_x = Fx.w32(f.pos_x + f.slide_step_x)
		if f.root_move.air_last <= f.pose_frame:
			f.slide_state = 0
			f.slide_step_x = 0
			f.slide_step_z = 0
			f.pos_x = f.root_x
			f.pos_z = f.root_z


## The move's step displacement inside its air window: step / 256 units a frame against the
## facing, through the per-player 24.8 accumulators.
func _step_displacement(f: FighterState) -> void:
	var pose := f.pose_move
	var first := pose.air_first
	var step := pose.step
	if first == 0 or f.pose_frame < first - 1 or pose.air_last < f.pose_frame or step == 0:
		return
	var i := f.index
	var old_x := f.pos_x
	var old_z := f.pos_z
	var d := polar(step, f.facing)
	fight.step_accum_x[i] = Fx.w32(fight.step_accum_x[i] + d.x)
	fight.step_accum_z[i] = Fx.w32(fight.step_accum_z[i] + d.y)
	f.pos_x = Fx.w32(f.pos_x - (fight.step_accum_x[i] >> 8))
	f.pos_z = Fx.w32(f.pos_z - (fight.step_accum_z[i] >> 8))
	fight.step_accum_x[i] = Fx.w32(fight.step_accum_x[i] + Fx.w32(Fx.w32(f.pos_x - old_x) * 0x100))
	fight.step_accum_z[i] = Fx.w32(fight.step_accum_z[i] + Fx.w32(Fx.w32(f.pos_z - old_z) * 0x100))


## Ballistic flight (combat.md#launches-and-juggles) until the body lands.
func _flight(f: FighterState, events: SimEvents) -> void:
	f.air_vel_y = Fx.s16(f.air_vel_y + 6)
	f.pos_y = Fx.w32(f.pos_y + f.air_vel_y)
	f.pos_x = Fx.w32(f.pos_x + f.air_vel_x)
	f.pos_z = Fx.w32(f.pos_z + f.air_vel_z)
	var v := polar(f.air_speed, f.target_dir + FightMath.HALF_TURN)
	f.air_vel_x = Fx.s16(v.x)
	f.air_vel_z = Fx.s16(v.y)
	if f.air_vel_y > 0 and -f.ground_offset <= f.pos_y:
		if f.air_kind == LANDING_SHAKE:
			CameraShake.start(fight, 1, events)
		f.pos_z = f.root_z
		f.pos_y = 0
		f.pos_x = f.root_x
		if f.air_kind == MoveSystem.LAUNCH_AIR_KIND:
			f.landed_a = 1
		else:
			f.landed_b = 1
		f.ballistic = 0
		f.air_phase = 2


## Slide to point: the anchor is set back along the direction from the target, and the push-back
## carries it there over 16 frames.
func _slide_to_point(f: FighterState) -> void:
	f.slide_to_point = 0
	var dz := Fx.w32(f.root_z - f.slide_target_z)
	var dx := Fx.w32(f.root_x - f.slide_target_x)
	f.push_dir = Fx.s16(FightMath.atan2_angle(dz, dx, t))
	f.push_frames = 0x10
	var dist := CameraMath.isqrt(Fx.w32(dx * dx + dz * dz))
	f.push_speed = Fx.s16(Fx.div_trunc(dist, f.push_frames))
	var o := polar(dist, f.push_dir + FightMath.HALF_TURN)
	f.pos_x = Fx.w32(f.root_x - o.x)
	f.pos_z = Fx.w32(f.root_z - o.y)


## Push-back along pushDir: the push speed, the push table, and the repeated-hit bonus.
func _push(f: FighterState) -> void:
	var push := 0
	if f.push_frames > 0:
		push = f.push_speed
		f.push_frames -= 1
	if f.push_table_frames > 0:
		f.push_table_frames -= 1
		push += f.push_table[f.push_table_pos]
		f.push_table_pos += 1
		if f.push_repeat > 0:
			push += f.push_repeat * 0x28 + 10
	if push != 0:
		var p := polar(push, f.push_dir)
		f.pos_x = Fx.w32(f.pos_x + p.x)
		f.pos_z = Fx.w32(f.pos_z + p.y)


## The per-frame bookkeeping after tracking (moves.md#per-frame-bookkeeping-in-fightermovephysics).
func _bookkeeping(f: FighterState, opp: FighterState, events: SimEvents) -> void:
	if f.attack_alert > 0:
		f.attack_alert -= 1
	if f.hit_cooldown > 0:
		f.hit_cooldown -= 1
	var pose := f.pose_move
	if f.pose_frame < pose.active_first or pose.active_last < f.pose_frame:
		f.active_segs = 0
	else:
		f.active_segs = 2 if AttackRecords.header(pose, t)[2] != 0 else 1
	f.forced_hit = 0
	if fight.mode == GameMode.FORCE:
		_forced_hit(f)
	if f.juggle_count != 0 or (pose.air_first <= f.pose_frame and f.pose_frame <= pose.air_last):
		f.in_air = 1
	else:
		f.in_air = 0
	if f.pose_frame == pose.air_last and f.hold_frames == -1 and f.pose_frame != 1 and f.air_phase != 2:
		if f.was_hit_this_move == 0 or f.air_kind == MoveSystem.LAUNCH_AIR_KIND \
				or (f.state_class != 9 and f.state & StateBit.DOWN == 0):
			f.landed_a = 1
		else:
			f.landed_b = 1
	_recovery(f)
	_about_to_hit(f, opp)
	_guard_state(f)
	if f.state_class == 9:                       # FUN_80040C04
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
	if fight.mode == GameMode.FORCE:
		f.no_look_at = 0 if f.is_cpu == 0 and f.fixed_facing == 0 else 1
	if f.active != 0 and f.landed_b != 0:
		events.add_at(SimEvents.Kind.LANDING_DUST, f.index, PackedInt32Array([f.root_x, f.root_y, f.root_z]))
		CameraShake.start(fight, 0, events)


## Knock-down recovery (combat.md#knock-down-recovery): the counters run down, faster with
## button presses.
func _recovery(f: FighterState) -> void:
	if f.recover_frames != 0:
		f.recover_frames = Fx.s16(f.recover_frames - 1)
		if f.recover_frames < 0 or f.hit_clean != 0:
			f.recover_frames = 0
	if f.recover_frames < 0x1F and f.recover_mash != 0:
		var entry := f.in_history[f.in_hist_index]
		var mash := 3 if entry & FighterInput.HIST_RP else (1 if entry & FighterInput.HIST_BUTTONS else 0)
		f.recover_mash = Fx.s16(f.recover_mash - 1 - mash)
		if f.recover_mash < 0:
			f.recover_mash = 0


## aboutToHit: a damage move up to 3 frames before its active window, flag 10, or Gon against
## anyone else.
func _about_to_hit(f: FighterState, opp: FighterState) -> void:
	var pose := f.pose_move
	if f.damage != 0:
		var active := pose.active_first
		var low := active - 3 if active >= 3 else 1
		if low <= f.pose_frame and f.pose_frame <= active:
			f.about_to_hit = 1
	if pose.flags & MoveFlag.ABOUT_TO_HIT:
		f.about_to_hit = 1
	if f.char_id == Character.GON and opp.char_id != Character.GON:
		f.about_to_hit = 1


## The hand and face shape: hit, or the attack shape before an attack's active window and at the
## start of a non-damage move during the fight.
func _face_shape(f: FighterState) -> void:
	if f.hit_clean != 0:
		f.hands.command(3, t.face_shape(t.face_hit, f.costume_slot), 10, f.char_id)
	elif f.skip_step_physics == 0:
		if f.move_changed != 0 and f.damage == 0 and f.in_reaction == 0 and (fight.round_state == RoundState.FIGHT or fight.round_state == RoundState.RESULT):
			f.hands.command(3, t.face_shape(t.face_attack, f.costume_slot), 10, f.char_id)
		if f.damage != 0 and f.pose_move.active_first - f.pose_frame < 8:
			f.hands.command(3, t.face_shape(t.face_attack, f.costume_slot), 10, f.char_id)


## Tekken Force: a CPU body thrown fast enough, or the player's power move (which costs health),
## hits any enemy it touches (Combat.hit_test).
func _forced_hit(f: FighterState) -> void:
	var pose := f.pose_move
	if f.is_cpu != 0:
		if f.throw_state < 0 and FORCED_THROWN_FRAME < f.pose_frame and f.pose_frame < pose.length:
			var speed := CameraMath.isqrt(f.vel_x * f.vel_x + f.vel_y * f.vel_y + f.vel_z * f.vel_z)
			if speed > FORCED_THROWN_SPEED:
				f.forced_hit = 1
				f.attack_hi = FORCED_ATTACK_HI
				f.attack = FORCED_ATTACK
				f.damage = (speed >> 4) + FORCED_DAMAGE
	elif pose.flags & MoveFlag.POWER:
		f.forced_hit = 1
		f.attack_hi = FORCED_ATTACK_HI
		f.attack = FORCED_ATTACK
		f.damage = FORCED_DAMAGE
		if f.move_changed != 0 and f.health > POWER_MOVE_COST:
			f.health -= POWER_MOVE_COST


func _set_guard_state(f: FighterState, value: int) -> void:
	f.state = value & 0xFFFFFFFF
	f.guard = value & 0x18


## The guard stance from the stick while the move allows it (flag 0x4000 or a side step).
func _guard_state(f: FighterState) -> void:
	var pose := f.pose_move
	var direction := f.in_history[f.in_hist_index] & FighterInput.HIST_DIRECTION
	if not pose.flags & MoveFlag.STICK_GUARD:
		if f.step_kind != 0:
			if direction == 4:
				_set_guard_state(f, StateWord.GUARD_HIGH)
			elif direction == 1:
				_set_guard_state(f, StateWord.GUARD_LOW)
			else:
				_set_guard_state(f, Fx.s16(pose.state))
				if f.state & StateBit.HUMAN_GUARD and f.human_guard == 0:
					f.state &= 0xFFFFFFE7
	elif f.human_guard == 0:
		if direction == 4:
			_set_guard_state(f, StateWord.GUARD_HIGH)
		elif direction == 1:
			_set_guard_state(f, StateWord.GUARD_LOW)
	elif direction == 4 or direction == 5:
		_set_guard_state(f, StateWord.GUARD_HIGH)
	elif direction == 1 or direction == 2:
		_set_guard_state(f, StateWord.GUARD_LOW)
	f.guard = f.state & StateBit.GUARDS if f.in_air == 0 and f.rel_angle < 0x4000 else 0


func _track_step(f: FighterState, step: int, budget: int, set_facing: bool = false) -> void:
	var over := track_budget(step, f.track_accum, budget)
	if over != 0:
		f.track_mode = Tracking.AFTER_ACTIVE
		step = over
	var accum := f.track_accum
	f.heading = Fx.s16(f.heading + step)
	if set_facing:
		f.facing = f.heading
	f.track_accum = Fx.s16(accum + step)
	if f.pose_move.active_first <= f.pose_frame:
		f.track_mode = Tracking.AFTER_ACTIVE


func _timed_turn(f: FighterState) -> void:
	f.turn_frames = Fx.s16(f.pose_move.active_first - (f.pose_frame & 0xFFFF))
	if f.turn_frames < 1:
		f.turn_frames = 1
	f.turn_step = clamp_symmetric(_towards(f.target_dir, f.heading, f.turn_frames), 0x9F4)
	f.track_mode = Tracking.TIMED_ALERT


## Heading tracking by the transition's tracking mode (moves.md#facing-and-tracking).
func _tracking(f: FighterState, opp: FighterState) -> void:
	var pose := f.pose_move
	var mode := f.track_mode
	var remaining := Fx.s16(pose.active_first + 1 - (f.pose_frame & 0xFFFF))
	if remaining < 1:
		remaining = 1
	var alert := opp.attack_alert != 0 and f.attack_seg_count != 0
	match mode:
		Tracking.NONE:
			f.heading = f.facing
		Tracking.AIM:
			var step := clamp_symmetric(_towards(f.aim_dir, f.heading, remaining), 0x1555)
			_track_step(f, step, 0x7FFF, true)
		Tracking.TARGET, Tracking.TARGET_HALF:
			if alert and f.move_frame < 9:
				_timed_turn(f)
				return
			var degrees := 1 if f.in_air != 0 else (0xE if f.move_frame > 7 else 3)
			var limit := _degrees(degrees)
			limit = Fx.s16(Fx.w32(limit << 16) >> 17) if mode == Tracking.TARGET_HALF else Fx.s16(limit)
			_track_step(f, clamp_symmetric(_towards(f.target_dir, f.heading, remaining), limit), 0x5555)
		Tracking.TARGET_SLOW:
			if f.turn_frames == 0 and not alert:
				var degrees := 1 if f.in_air != 0 else (3 if f.move_frame > 7 else 2)
				var step := clamp_symmetric(_towards(f.target_dir, f.heading, remaining), Fx.s16(_degrees(degrees)))
				_track_step(f, step, 0xE38)
		Tracking.TARGET_FAST:
			if not alert or f.move_frame > 8:
				var degrees := 4 if f.in_air != 0 else (100 if f.move_frame > 7 else 3)
				var step := clamp_symmetric(_towards(f.target_dir, f.heading, remaining), Fx.s16(_degrees(degrees)))
				_track_step(f, step, 0x9554)
			else:
				_timed_turn(f)
		Tracking.AFTER_ACTIVE:
			if f.damage == 0 or pose.air_first == 0 or f.in_air != 0 or f.pose_frame < pose.active_last:
				var frame := f.pose_frame
				var active := pose.active_first
				if active < frame and (frame - active) % 5 == 0 and f.rel_angle < 0x5556:
					var length := pose.length
					f.turn_frames = Fx.s16(5 if length - frame < 6 else length - frame)
					if f.turn_frames < 0:
						f.turn_frames = 0
					else:
						f.turn_step = clamp_symmetric(_towards(f.aim_dir, f.heading, f.turn_frames), 0x222)
			else:
				f.turn_frames = 0
				f.turn_step = 0
		Tracking.EASE_BY_POSE:
			var end := pose.air_last if pose.air_last != 0 else pose.length
			if f.pose_frame <= end:
				var delta := Fx.s16(Fx.div_trunc(Fx.s16(f.aim_dir - f.heading) * f.pose_frame, end if end != 0 else 1))
				f.heading = Fx.s16(f.heading + clamp_symmetric(delta, 0x38E))
		Tracking.EASE:
			var frames := mini(f.move_frame, 8)
			var delta := Fx.s16(Fx.div_trunc(Fx.s16(f.aim_dir - f.heading) * frames, 8))
			f.heading = Fx.s16(f.heading + clamp_symmetric(delta, 0x71C))
		Tracking.APPROACH:
			if (fight.fighter_distance & 0xFFFFFFFF) > 0x4AF:
				var aim := FightMath.atan2_angle(Fx.w32(f.opp_start_z - f.root_z), Fx.w32(f.opp_start_x - f.root_x), t)
				var diff := ((f.facing & 0xFFFF) - aim) & 0xFFFFFFFF
				if diff & 0x8000:
					diff = ~diff
				if diff & 0xFFFF > 0x3FFF:
					aim -= 0x8000
				var delta := Fx.s16(Fx.div_trunc(Fx.s16(aim - (f.facing & 0xFFFF)) * f.pose_frame, pose.length))
				f.facing = Fx.s16(f.facing + clamp_symmetric(delta, 0x5B0))
				f.anchor_dirty = 1
				f.heading = f.facing
		Tracking.SIDE_STEP:
			var length := pose.length
			if f.pose_frame <= length:
				var side := 0
				if f.char_id == 7 and f.facing_quadrant == 2:
					side = 0x71C if f.root_dx < 0 else -0x71C
				else:
					side = -0x11C7 if f.root_dx < 0 else 0x11C7
				f.anchor_dirty = 1
				f.facing = Fx.s16(f.aim_dir + Fx.s16(Fx.div_trunc(side * f.pose_frame, length)))
				f.heading = f.facing


## Tekken Ball: within the tuned frames of the move the anchor drifts at the tuned speed along the
## tuned angle from the opponent's direction.
func _ball_drift(f: FighterState) -> void:
	var d := fight.ball.drift(f.player_index)
	var speed := d[1]
	if speed == 0 or f.pose_frame < d[2] or f.pose_frame > d[3]:
		return
	var angle := f.target_dir + Fx.s16(d[0])
	f.pos_x = Fx.w32(f.pos_x + Fx.div_trunc(speed * FightMath.sin_q15(angle, t), 0x7FFF))
	f.pos_z = Fx.w32(f.pos_z + Fx.div_trunc(speed * FightMath.cos_q15(angle, t), 0x7FFF))
