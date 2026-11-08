class_name ArcadeFighterPhysics
extends FighterPhysics
## FUN_8019F3FC: the arcade's physics for both fighters at once. The PlayStation's steps without the
## home-only branches (Gon, Tekken Ball, slides to a point, forced hits), in two passes over the pair:
## first the movement of both, then the bookkeeping of both. The flight keeps the velocities
## FUN_80192978 set, the reaction record follows the opponent's move every frame.

const ATTACK_FACE_JOINTS := 0xC         ## only a first joint below it shows the attack face


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


## The flight keeps the velocities FUN_80192978 set.
func _air_velocity(_f: FighterState) -> void:
	pass


func _book(f: FighterState, opp: FighterState) -> void:
	_tick_cooldowns(f)
	_count_active_segments(f)
	_air_flags(f)
	_recovery(f)
	_about_to_hit(f, opp)
	f.reaction = t.reactions[opp.pose_move.reaction]
	_guard_state(f)
	_airborne_state(f)
	_face_shape(f)
	_settle_flags(f, opp)


## The second segment is a second joint pair in the row.
func _count_active_segments(f: FighterState) -> void:
	var pose := f.pose_move
	if f.pose_frame < pose.active_first or pose.active_last < f.pose_frame:
		f.active_segs = 0
	else:
		f.active_segs = 1 if (pose.attack_joints >> 16) & 0xFF == 0 else 2


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
func _shows_attack_face(f: FighterState) -> bool:
	return f.pose_move.attack_joints & 0xFF < ATTACK_FACE_JOINTS
