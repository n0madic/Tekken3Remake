class_name FighterAnimation
extends RefCounted
## FighterSkeletonUpdate (0x8002BCB8) / FighterAnimate (0x8003AAD0): root and pose decoding,
## RootReanchor, FighterTransitionBlend, RootUpdate, the hand poses, blinking, and
## FighterComposeJoints with the blend, the head look-at, True Ogre's sway and the costume
## attachments (moves.md#root-motion, moves.md#motion-blending, animation.md).
##
## Written from the verified ports root_reanchor, root_update, transition_blend,
## matrix_add_scaled and matrix_orthonormalize in tools/research/fight_sim.py and the decompiled
## FighterAnimate, FighterComposeJoints, HeadLookAt, FUN_80034354 and FUN_80033C54.

const HEAD_SLOT := 2
const CHEST_JOINT := 1
const HEAD_JOINT := 2
const GAZE_HALF_TURN := 0x800          ## GonEyesFollow: the angle below which the look is to the first side
const GAZE_FORWARD := 0xF00            ## the angle the second side's counts from
const GAZE_UNITS := 0x3C               ## angle units per step of the eyes' shift
const GAZE_RANGE := 0x11               ## the largest shift
const SCREEN_JOINT := 11
const FLASH_FRAMES := 0x20
const LIT_BLACK := -1               ## FightState.flash_level of a burning fighter: back colour black
const LOOK_UP := 0x11C7
const LOOK_DOWN := -0x2AAA
const LOOK_STEP := 0x71C
const LOOK_HOLD := 0x3C
const BLINK_CLOSED := 4
const ENTRY_DST_CODES := [Transition.CONTINUE, Transition.SLIDE_CONTINUE, Transition.SLIDE_TURNED,
	Transition.CONTINUE_TRACK_SLOW, Transition.CONTINUE_TRACK, Transition.CONTINUE_EASE,
	Transition.CONTINUE_EASE_TURNING, Transition.STEP, Transition.SIDE_STEP_CONTINUE, Transition.TO_TERMINATOR]

## The transition blend's mode (moves.md#motion-blending): the old pose decaying into a new move,
## or a forward blend into the pending branch move or the stance.
enum Blend { NONE, DECAY, BRANCH, STANCE }

var fight: FightState
var t: FightTables
var solver: PoseSolver
var look_base: PackedInt32Array           ## 0x8009E900: the rotation of angles (0x4000, 0, 0x4000)
var camera: CameraDirector                ## the fight's, whose `overhead` flag (0x800B08D4) Gon's face reads; null: none


func _init(fight_state: FightState) -> void:
	fight = fight_state
	t = fight_state.tables
	solver = PoseSolver.new(t.pose)
	look_base = _angles_to_matrix(PackedInt32Array([0x4000, 0, 0x4000]))


## PoseSolver.build with Gameplay fix #8 as it is now: the option can change in the middle of a session.
func _solve(pose: PackedInt32Array, slots: Array[PackedInt32Array]) -> void:
	solver.wide_elbow = fight.rules.fix_elbow_bend_overflow
	solver.build(pose, slots)


## FighterSkeletonUpdate: every active fighter in index order (FUN_8003AA6C).
func update_all(view: ViewMatrix, blend_enabled: bool, draw: bool) -> void:
	for f in fight.active():
		if f.active != 0:
			# FUN_800363B0: Mokujin's stick is drawn only with Yoshimitsu's moves.
			if f.char_id == Character.MOKUJIN:
				f.body.stick_shown = f.bank_type == BankType.YOSHIMITSU
			if f.keep_light == 0:
				flash_step(fight, f)
			else:
				# FUN_8003AA6C: SetBackColor(0, 0, 0) instead of FUN_8003A3B8; the flash waits.
				fight.flash_level[f.index] = LIT_BLACK
			animate(f, view, blend_enabled, draw)


## FUN_8003A3B8's counter: a lighting flash (Tekken Force's health pick-up) runs 32 frames. The
## count lights the frame it is read in (FightState.flash_level, StageLighting.fighter_back_colour)
## and is stepped after: counts 1 to 32 colour the fighter, then it ends.
static func flash_step(fight: FightState, f: FighterState) -> void:
	var p := f.player_index
	fight.flash_level[f.index] = fight.health_flash[p]
	if fight.health_flash[p] != 0:
		fight.health_flash[p] += 1
		if fight.health_flash[p] > FLASH_FRAMES:
			fight.health_flash[p] = 0


## FighterAnimate for one fighter.
func animate(f: FighterState, view: ViewMatrix, blend_enabled: bool, draw: bool) -> void:
	var body := f.body
	fight.replay.play_pose(f)
	# FUN_80038B60: a throw victim takes its partner's scale.
	f.scale = fight.fighters[f.throw_partner].scale_base if f.throw_state < 0 else f.scale_base
	var d := _decode_root(f, f.root_move, f.root_frame - 1)
	f.root_dx = d[0]
	f.root_dy = d[1]
	f.root_dz = d[2]
	body.pose_vector = f.pose_move.anim_bank.pose(f.pose_move.anim, f.pose_frame - 1)
	_reanchor(f)
	body.decoded_root_dy = f.root_move.anim_bank.pose(f.root_move.anim, f.root_frame - 1)[1]
	if blend_enabled and fight.blend_skip == 0:
		_transition_blend(f)
	fight.blend_skip = 0
	fight.replay.record_pose(f)
	_root_update(f)
	if fight.paused_player == 0 and fight.freeze == 0:
		f.hands.update(f.char_id, f.air_free, t.fighter)
		if f.char_id != Character.TRUE_OGRE:
			fight.gon_mouth[f.player_index] = f.hands.variant[1]
			for c in 2:
				f.hands.variant[c] = fight.replay.hand_pose(f, f.hands.variant[c], c)
		else:
			f.hands.wing_variant = fight.replay.wings(f, f.hands.wing_variant)
			f.hands.variant[0] = fight.replay.hand_pose(f, f.hands.variant[0], 0)
	_blink(f)
	_compose(f)
	if draw:
		f.screen_x = view.screen_of(body.joints[SCREEN_JOINT])[0]


func _decode_root(f: FighterState, move: MoveRow, frame: int) -> PackedInt32Array:
	var p := move.anim_bank.pose(move.anim, frame)
	return PackedInt32Array([Fx.s16((p[0] * f.scale) >> 12), Fx.s16((p[1] * f.scale) >> 12), Fx.s16((p[2] * f.scale) >> 12)])


## RootReanchor (0x8003AC1C): switching the root move does not make the body jump.
func _reanchor(f: FighterState) -> void:
	if f.anchor_dirty == 0:
		return
	var frame := maxi(0, f.root_frame - f.frame_step - 1)
	f.anchor_dirty = 0
	var d := _decode_root(f, f.root_move, frame)
	var a := (((0x8000 - f.facing) >> 3) & 0x1FFE) >> 1
	var c := FightMath.cos12(a, t)
	var s := FightMath.sin12(a, t)
	f.pos_x = Fx.w32(f.root_x - Fx.trunc12(d[0] * c - d[2] * s))
	f.pos_z = Fx.w32(f.root_z - Fx.trunc12(d[0] * s + d[2] * c))


## RootUpdate (0x8003AD48): root matrix, blend weight and root position.
func _root_update(f: FighterState) -> void:
	var body := f.body
	var angles := PackedInt32Array([Fx.s16(-f.tilt_x), Fx.s16(f.heading - 0x8000), Fx.s16(-f.tilt_z)])
	angles = fight.replay.root_rotation(f, angles)
	if fight.replay_playing != 0:
		f.heading = Fx.s16(angles[1] - 0x8000)
	body.root_mat = FighterSkeleton.rotation_xyz(angles[0] & 0xFFFF, angles[1] & 0xFFFF, angles[2] & 0xFFFF, t.pose)
	var dy := f.root_dy
	if f.blend_mode == Blend.NONE or f.blend_frames == 0:
		f.blend_weight = 0x1000
		f.root_dy_blended = dy
	else:
		f.blend_weight = Fx.s16(Fx.div_trunc(Fx.w32(f.blend_counter << 12), f.blend_frames))
		var v := Fx.w32(f.blend_root_delta[1] * f.blend_weight * 2)
		dy = Fx.s16(((v + 0x1FFF if v < 0 else v) >> 13) + dy)
		f.root_dy_blended = dy
	f.root_x = f.pos_x
	f.root_y = f.pos_y
	f.root_z = f.pos_z
	if f.air_phase == 0:
		var a := ((0x8000 - f.facing) >> 4) & 0xFFF
		var c := FightMath.cos12(a, t)
		var s := FightMath.sin12(a, t)
		f.root_x = Fx.w32(f.root_x + Fx.trunc12(f.root_dx * c - f.root_dz * s))
		f.root_y = Fx.w32(f.root_y + dy)
		f.root_z = Fx.w32(f.root_z + Fx.trunc12(f.root_dx * s + f.root_dz * c))
	elif f.air_phase == 2:
		f.root_y = Fx.w32(f.root_y + dy)
	fight.replay.root_position(f)


# ---- FighterTransitionBlend (0x8003C4C4) ------------------------------------------------------

## BlendSuppressed (0x8003CAD0): move flag bit 8, +0xBA, or the bytes +0x89 and +0x8A of the word
## at +0x88 (guardedPrev, inReaction).
func _blend_suppressed(f: FighterState) -> bool:
	return f.pose_move.flags & MoveFlag.NO_BLEND != 0 or f.move_flag_ba != 0 or f.guarded_prev != 0 \
		or f.in_reaction != 0


func _decay_length(f: FighterState) -> int:
	var pose := f.pose_move
	if f.last_pose_move == pose and f.branch_kind != 3:
		return 0
	if f.move_changed == 0:
		return 0
	var frame := f.pose_frame
	var left := maxi(0, pose.length - frame)
	var n := 0
	if left != 0:
		var active := pose.active_first
		if active == 0 or active <= frame:
			n = 0x10 if f.throw_state < 0 else 4
		else:
			n = mini(active - frame, 0x10)
	if left < n:
		n = left
	return n if n >= 2 else 0


func _no_blend_forward(f: FighterState) -> bool:
	return f.pose_move.flags & MoveFlag.NO_BLEND_FORWARD != 0 or f.move_flag_bb != 0 or f.trans_bit6 != 0 \
		or f.juggle_count != 0 or (f.in_air != 0 and f.was_hit_this_move != 0)


func _branch_length(f: FighterState) -> int:
	if f.move_row == null:
		return 0
	if f.pose_frame < f.entry_frame and f.branch_kind != 3:
		return maxi(0, f.entry_frame - f.pose_frame + 1)
	return 0


func _stance_length(f: FighterState) -> int:
	if f.move_row != null:
		return 0
	var left := f.pose_move.length - f.pose_frame
	if left >= 0x10:
		return 0
	var n := left + 1 if f.frame_step >= 1 else f.pose_frame
	return n if n >= 2 else 0


func _transition_blend(f: FighterState) -> void:
	if fight.freeze != 0 or fight.paused_player != 0:
		_blend_finish(f)
		return
	if fight.blend_hold == 0:
		var n := 0
		if fight.replay_playing == 0:
			n = _blend_choose(f)
		if f.blend_active != 0:
			_blend_start(f, n)
			_blend_deltas(f)
	else:
		fight.blend_hold -= 1
		f.blend_mode = Blend.NONE
	if f.blend_active == 0:
		_blend_count(f)
	_blend_finish(f)


## Ends a finished blend and starts a new one: the decay blend when the move changed, else a
## forward blend into the pending move or the stance; returns its length (0: none).
func _blend_choose(f: FighterState) -> int:
	var n := 0
	f.blend_active = 0
	var forward := true
	if not _blend_suppressed(f):
		if f.blend_mode == Blend.DECAY and f.blend_counter == 0:
			f.blend_mode = Blend.NONE
		n = _decay_length(f)
		if n != 0:
			f.blend_active = 1
			f.blend_mode = Blend.DECAY
		forward = f.blend_mode != Blend.DECAY
	elif f.blend_mode == Blend.DECAY:
		f.blend_mode = Blend.NONE
	if not forward:
		return n
	if _no_blend_forward(f):
		if f.blend_mode == Blend.BRANCH or f.blend_mode == Blend.STANCE:
			f.blend_mode = Blend.NONE
		return n
	if f.blend_mode == Blend.BRANCH and f.blend_counter == f.blend_frames:
		f.blend_mode = Blend.NONE
	if f.blend_mode == Blend.STANCE and (f.blend_counter == f.blend_frames or f.move_changed != 0):
		f.blend_mode = Blend.NONE
	if f.blend_mode == Blend.NONE:
		n = _branch_length(f)
		var mode := Blend.BRANCH
		if n == 0:
			n = _stance_length(f)
			mode = Blend.STANCE
		if n != 0:
			f.blend_mode = mode
			f.blend_active = 1
	return n


## The blend's source and destination poses and its length `n` (during replay playback the
## recorded ones are kept and only the counter restarts).
func _blend_start(f: FighterState, n: int) -> void:
	var playback := fight.replay_playing != 0
	match f.blend_mode:
		Blend.BRANCH:
			if not playback:
				f.blend_src_move = f.pose_move
				f.blend_src_frame = f.entry_frame & 0xFF
				f.blend_dst_move = fight.move_for_slot(f, f.move_slot)
				f.blend_dst_frame = (f.entry_frame if f.transition in ENTRY_DST_CODES else 0) & 0xFF
				f.blend_frames = n
			f.blend_counter = 0
		Blend.STANCE:
			if not playback:
				f.blend_src_move = f.pose_move
				f.blend_src_frame = (0 if f.frame_step < 1 else f.pose_move.length) & 0xFF
				f.blend_dst_move = fight.move_for_slot(f, Fx.s16(f.pose_move.stance_slot))
				f.blend_dst_frame = 0
				if f.blend_dst_move == null:
					# Bug #61 (not reproduced): no stance row, the blend keeps the running move.
					f.blend_dst_move = f.pose_move
					f.blend_dst_frame = f.blend_src_frame
				f.blend_frames = n
			f.blend_counter = 0
		Blend.DECAY:
			if not playback:
				f.blend_counter = n - 1
				f.blend_frames = n
				f.blend_src_move = f.last_pose_move
				f.blend_src_frame = (f.event_frame - 1) & 0xFF
				f.blend_dst_move = f.pose_move
				f.blend_dst_frame = (f.pose_frame - 1) & 0xFF
			else:
				f.blend_counter = f.blend_frames - 1


## The root and joint rotation differences: the displayed pose against the new move's first pose
## for the decay blend, destination against source for the forward blends.
func _blend_deltas(f: FighterState) -> void:
	var body := f.body
	if f.blend_mode == Blend.DECAY:
		var dst := _decode_root(f, f.blend_dst_move, f.blend_dst_frame)
		# +0x1810 and +0x1814 are never written; +0x1812 is the displayed root dy.
		var shown := PackedInt32Array([0, f.root_dy_blended, 0])
		for k in 3:
			f.blend_root_delta[k] = Fx.s16(shown[k] - dst[k])
		var slots := _pose_slots(f.blend_dst_move, f.blend_dst_frame)
		for i in range(1, FighterBody.JOINTS):
			var prev := body.prev_local_mats[i - 1]
			var delta := body.blend_delta[i - 1]
			for e in 9:
				delta[e] = Fx.s16(prev[e] - slots[i][e])
	elif f.blend_mode == Blend.BRANCH or f.blend_mode == Blend.STANCE:
		var src := _decode_root(f, f.blend_src_move, f.blend_src_frame)
		var dst := _decode_root(f, f.blend_dst_move, f.blend_dst_frame)
		for k in 3:
			f.blend_root_delta[k] = Fx.s16(dst[k] - src[k])
		var a := _pose_slots(f.blend_src_move, f.blend_src_frame)
		var b := _pose_slots(f.blend_dst_move, f.blend_dst_frame)
		for i in range(1, FighterBody.JOINTS):
			var delta := body.blend_delta[i - 1]
			for e in 9:
				delta[e] = Fx.s16(b[i][e] - a[i][e])


## A running blend's counter: down for the decay blend, up to its length for the forward ones.
func _blend_count(f: FighterState) -> void:
	match f.blend_mode:
		Blend.DECAY:
			if f.blend_counter >= 1:
				f.blend_counter -= 1
			elif f.blend_counter < 0:
				f.blend_counter = 0
		Blend.NONE:
			f.blend_counter = 0
			f.blend_frames = 0
		Blend.BRANCH, Blend.STANCE:
			if f.blend_counter < f.blend_frames:
				f.blend_counter += 1
			elif f.blend_frames < f.blend_counter:
				f.blend_counter = f.blend_frames


func _blend_finish(f: FighterState) -> void:
	f.last_pose_move = f.pose_move
	f.last_pose_frame = f.pose_frame
	f.root_dy_blended = f.body.decoded_root_dy


## The 18 local rotations of a move's frame, from zeroed slots (the pose solver leaves slots
## whose limb target is too close unchanged).
func _pose_slots(move: MoveRow, frame: int) -> Array[PackedInt32Array]:
	var slots: Array[PackedInt32Array] = []
	for i in FighterBody.JOINTS:
		slots.append(PackedInt32Array([0, 0, 0, 0, 0, 0, 0, 0, 0]))
	_solve(move.anim_bank.pose(move.anim, frame), slots)
	return slots


# ---- blinking (FUN_80034354) -----------------------------------------------------------------

## The eyes: moves with flag 0x40000 (and lying moves without the look-at flag) keep them
## closed; otherwise they stay open for a random odd 1–255 frames and closed for 4. Gon's
## mouth follows with HandFaceCommand kind 1. The texture copies are the presentation's.
func _blink(f: FighterState) -> void:
	var hands := f.hands
	var flags := f.pose_move.flags
	var gon := f.char_id == Character.GON
	var closed := false
	if flags & MoveFlag.REACT_CHAIN:
		closed = true
		# Under the overhead KO camera (0x800B08D4) Gon shuts his eyes on these moves by the jaw's
		# shape 3 (and a palette swap of his own, FighterView.set_overhead).
		if gon and camera != null and camera.overhead != 0:
			hands.command(1, 3, 1, f.char_id)
	elif f.pose_move.state & StateBit.DOWN and flags & MoveFlag.LOOK_AT == 0:
		closed = true
	if closed:
		hands.face_speed = 2
		hands.face = 1
	if hands.face_speed == 0:
		if hands.face == 0:
			if gon and fight.gon_mouth[f.player_index] == 0 and hands.current[1] == 0:
				hands.command(1, 3, 1, f.char_id)
				fight.gon_mouth[f.player_index] = 0
			hands.face_speed = BLINK_CLOSED
			hands.face = 1
		else:
			if gon and fight.gon_mouth[f.player_index] == 0 and hands.current[1] == 0:
				hands.command(1, 0, 1, f.char_id)
				fight.gon_mouth[f.player_index] = 0
			hands.face_speed = (fight.rng.next() & 0xFE) + 1
			hands.face = 0
	hands.face_speed = Fx.s16(hands.face_speed - 1)


# ---- FighterComposeJoints (0x8003B220) ---------------------------------------------------------

func _compose(f: FighterState) -> void:
	var body := f.body
	body.root = JointFrame.new(body.root_mat, PackedInt32Array([f.root_x, f.root_y, f.root_z]))
	if fight.paused_player == 0 and fight.freeze == 0:
		_solve(body.pose_vector, body.local_mats)
		if f.blend_mode == Blend.NONE:
			for i in range(1, FighterBody.JOINTS):
				body.prev_local_mats[i - 1] = body.local_mats[i].duplicate()
		else:
			for i in range(1, FighterBody.JOINTS):
				var m := _add_scaled(body.blend_delta[i - 1], body.local_mats[i], f.blend_weight)
				body.local_mats[i] = _orthonormalize(m)
				body.prev_local_mats[i - 1] = body.local_mats[i].duplicate()
		if f.no_look_at == 0:
			if f.char_id == Character.GON:
				_gon_eyes_follow(f, fight.opponent(f))
			_head_look_at(f, fight.opponent(f))
	var ogre := f.char_id == Character.TRUE_OGRE
	var tilt := 0
	if ogre:
		tilt = CameraMath.atan2_units4096(body.local_mats[5][0], body.local_mats[5][1], t.camera) * -4
	for i in FighterBody.JOINTS:
		if not body.present[i]:
			continue
		var local := _ogre_local(f, i, tilt) if ogre else body.local_mats[i]
		var offset := body.offsets[_ogre_slot(i) if ogre else i]
		var parent := body.root if body.parents[i] < 0 else body.joints[body.parents[i]]
		body.joints[i] = JointFrame.compose_offset(parent, local, offset)
	for i in range(FighterBody.JOINTS, FighterBody.PARTS):
		if not body.present[i]:
			continue
		var a := i - FighterBody.JOINTS
		var parent := body.root if body.parents[i] < 0 else body.joints[body.parents[i]]
		if fight.freeze == 0 and fight.paused_player == 0:
			body.attach_local[a] = body.attachments.update(a, parent, body.joints[i], body.offsets[i], body.joints)
		var local := _ogre_local(f, i, tilt) if ogre else body.attach_local[a]
		var offset := body.offsets[_ogre_slot(i) if ogre else i]
		body.joints[i] = JointFrame.compose_offset(parent, local, offset)
	body.draw_joints = body.joints.duplicate()


## MatrixAddScaled (0x8003A980): base + sat16(weight · delta >> 12).
static func _add_scaled(delta: PackedInt32Array, base: PackedInt32Array, weight: int) -> PackedInt32Array:
	var w := Fx.s16(weight)
	var out := PackedInt32Array()
	out.resize(9)
	for e in 9:
		out[e] = Fx.s16(Fx.sat16((w * Fx.s16(delta[e])) >> 12) + base[e])
	return out


## MatrixOrthonormalize (0x800762B0): Gram–Schmidt on the first two columns, the third their
## cross product.
func _orthonormalize(m: PackedInt32Array) -> PackedInt32Array:
	var c0 := Gte.vector_normal(PackedInt32Array([m[0], m[3], m[6]]), t.fighter.rsqrt)
	var dot := Fx.w32(m[1] * c0[0] + m[4] * c0[1] + m[7] * c0[2]) >> 12
	var v := PackedInt32Array([Fx.w32(m[1] - (Fx.w32(dot * c0[0]) >> 12)), Fx.w32(m[4] - (Fx.w32(dot * c0[1]) >> 12)),
		Fx.w32(m[7] - (Fx.w32(dot * c0[2]) >> 12))])
	var c1 := Gte.vector_normal(v, t.fighter.rsqrt)
	var d1 := Fx.s16(c0[0])
	var d2 := Fx.s16(c0[1])
	var d3 := Fx.s16(c0[2])
	var i1 := Fx.s16(c1[0])
	var i2 := Fx.s16(c1[1])
	var i3 := Fx.s16(c1[2])
	var c2 := PackedInt32Array([(d2 * i3 - d3 * i2) >> 12, (d3 * i1 - d1 * i3) >> 12, (d1 * i2 - d2 * i1) >> 12])
	var out := PackedInt32Array()
	out.resize(9)
	for r in 3:
		out[3 * r] = Fx.s16(c0[r])
		out[3 * r + 1] = Fx.s16(c1[r])
		out[3 * r + 2] = Fx.s16(c2[r])
	return out


# ---- True Ogre (FUN_80033C54) -------------------------------------------------------------------

## The local matrix slot True Ogre draws joint `i` with: joints 5, 6, 18 and 19 (the wings and
## tail) take the next slot of the cycle 5 → 18 → 19 → 6 → 5. ComposeJoint reads the joint offset
## from the slot's matrix too, so these joints are also placed with the slot's offset.
static func _ogre_slot(i: int) -> int:
	match i:
		5:
			return 0x12
		6:
			return 5
		0x12:
			return 0x13
		0x13:
			return 6
	return i


## The local rotation True Ogre draws joint `i` with: joints 5, 6, 18 and 19 sway with a counter
## and his level channel (written into the slot of _ogre_slot); the others keep their pose
## rotation.
func _ogre_local(f: FighterState, i: int, tilt: int) -> PackedInt32Array:
	var body := f.body
	var phase := -1
	var slot := _ogre_slot(i)
	match i:
		6:
			phase = 1
		5:
			if fight.paused_player == 0 and fight.freeze == 0:
				body.ogre_sway = Fx.s16(body.ogre_sway + 1)
			fight.ogre_phase_x = (body.ogre_sway & 0x7F) << 5
			fight.ogre_phase_y = (body.ogre_sway & 0x3F) << 6
			fight.ogre_height = clampi(-body.joints[6].t[1] / 2, 0, 0x100)
			phase = 0
		0x12:
			phase = 2
		0x13:
			phase = 3
	var m := body.local_mats[slot] if slot < FighterBody.JOINTS else body.attach_local[slot - FighterBody.JOINTS]
	if fight.paused_player != 0 or fight.freeze != 0 or phase < 0:
		return m
	var level := f.hands.ogre_level
	var amount: int = fight.ogre_height * (0x100 - level)
	amount = (amount + 0xFF if amount < 0 else amount) >> 8
	var sx: int = FightMath.sin12(fight.ogre_phase_x + phase * 0x400, t) * amount
	var angle_x := Fx.s16((sx + 0x1FF if sx < 0 else sx) >> 9)
	var sy: int = FightMath.sin12(fight.ogre_phase_y + phase * 0x400, t) * amount
	var angle_y := Fx.s16(((sy + 0xFF if sy < 0 else sy) & 0xFFFFFFFF) >> 8) + tilt
	var rot := _angles_to_matrix(PackedInt32Array([0, angle_x, Fx.s16(angle_y)]))
	var row_scale := ((level + 3 if level < 0 else level) >> 2) + 0x100
	var col_scale := ((level + 7 if level < 0 else level) >> 3) + 0x100
	if i == 0x13:
		row_scale = 0x200 - row_scale
	for r in 3:
		var a := rot[3 * r] * row_scale
		rot[3 * r] = Fx.s16(((a + 0xFF if a < 0 else a) & 0xFFFFFFFF) >> 8)
		var b := rot[3 * r + 1] * col_scale
		rot[3 * r + 1] = Fx.s16(((b + 0xFF if b < 0 else b) & 0xFFFFFFFF) >> 8)
		var c := rot[3 * r + 2] * col_scale
		rot[3 * r + 2] = Fx.s16(((c + 0xFF if c < 0 else c) & 0xFFFFFFFF) >> 8)
	if slot < FighterBody.JOINTS:
		body.local_mats[slot] = rot
	else:
		body.attach_local[slot - FighterBody.JOINTS] = rot
	return rot


# ---- head look-at (HeadLookAt, 0x800392C8) -----------------------------------------------------

## GonEyesFollow (0x80039A50): the direction of the opponent's head in the frame of Gon's own
## head (his joint block of the last frame), as an angle in 4096 units that GonEyesSetOffset turns
## into the pupils' shift: 0 to 17 to one side, 0 to −17 to the other. HeadLookAt leaves his yaw alone.
func _gon_eyes_follow(f: FighterState, opp: FighterState) -> void:
	var head := f.body.joints[HEAD_JOINT]
	# A record without a model (Tekken Ball's second fighter) has no joints: its words are zero.
	var target := opp.body.joints[HEAD_JOINT].t if opp.body != null else PackedInt32Array([0, 0, 0])
	f.body.gon_gaze = gon_gaze(head.rot, head.t, target, t.camera)


## The shift GonEyesFollow turns the opponent's head position `target` into, for Gon's head
## frame (`rot`, `own`).
static func gon_gaze(rot: PackedInt32Array, own: PackedInt32Array, target: PackedInt32Array,
		tables: CameraTables) -> int:
	var local := Gte.apply_lv(Fx.transpose(rot),
			PackedInt32Array([target[0] - own[0], target[1] - own[1], target[2] - own[2]]))
	var angle := CameraMath.atan2_units4096(local[0], local[1], tables)
	if angle < GAZE_HALF_TURN:
		return maxi(-Fx.div_trunc(angle, GAZE_UNITS), -GAZE_RANGE)
	return mini(-Fx.div_trunc(angle - GAZE_FORWARD, GAZE_UNITS), GAZE_RANGE)


func _head_look_at(f: FighterState, opp: FighterState) -> void:
	var body := f.body
	var look := body.look_at
	var active := 0
	var pose := f.pose_move
	if pose.flags & MoveFlag.LOOK_AT and fight.camera_phase == CameraPhase.FIGHT:
		active = 1
		if pose.active_first != 0:
			var from := maxi(pose.active_last, pose.length - 0x11)
			if f.pose_frame < from:
				active = 0
	var was := look.active
	look.active = active
	if active == 0:
		return
	var o1 := opp.body.joints[CHEST_JOINT].t
	var o2 := opp.body.joints[HEAD_JOINT].t
	var head := body.joints[HEAD_JOINT].t
	var tx := Fx.s16(Fx.s16(o1[0] + ((o2[0] - o1[0]) >> 1)) - head[0])
	var ty := Fx.s16(Fx.s16(o1[1] + ((o2[1] - o1[1]) >> 1)) - head[1])
	var tz := Fx.s16(Fx.s16(o1[2] + ((o2[2] - o1[2]) >> 1)) - head[2])
	# FUN_8004B4B0: the chest's axes, then the target in the chest frame (MAC results).
	var chest := body.joints[CHEST_JOINT].rot
	var ax := Fx.mvmva(chest, 0x1000, 0, 0)
	var ay := Fx.mvmva(chest, 0, 0x1000, 0)
	var az := Fx.mvmva(chest, 0, 0, 0x1000)
	var frame := PackedInt32Array([ax[0], ax[1], ax[2], ay[0], ay[1], ay[2], az[0], az[1], az[2]])
	var local := Gte.apply(frame, tx, ty, tz)
	var lx := local[0]
	var ly := local[1]
	var lz := local[2]
	var elevation := FightMath.atan2_angle(t.pose.square_root0(Fx.w32(ly * ly + lz * lz)), Fx.s16(lx), t)
	var pitch := Fx.s16(-elevation)
	if pitch > LOOK_UP:
		pitch = LOOK_UP
	if pitch < LOOK_DOWN:
		pitch = LOOK_DOWN
	var yaw := 0 if f.char_id == Character.GON else Fx.s16(FightMath.atan2_angle(Fx.s16(ly), Fx.s16(lz), t))
	var tilt := FightMath.atan2_angle(t.pose.square_root0(Fx.w32(ax[0] * ax[0] + ax[2] * ax[2])), Fx.s16(ax[1]), t)
	var tilt_up := Fx.s16(tilt) + 0x4000
	var limit := 0
	if tilt_up < 0xAAB:
		limit = 0x38E3
	elif tilt_up < 0x38E3:
		limit = 0x38E3 - Fx.div_trunc((Fx.s16(tilt) + 0x3556) * 0x238E, 0x2E39)
	else:
		limit = 0x1555
	yaw = clampi(yaw, -limit, limit)
	var newly := active != was
	var refresh := true
	if not newly:
		if absi(ly) < 400 and absi(lz) < 300:
			look.hold = (look.hold + 1) & 0xFF
			refresh = look.hold >= LOOK_HOLD
			if refresh:
				look.hold = 0
		else:
			look.hold = 0
	else:
		look.hold = 0
	if refresh:
		look.target = PackedInt32Array([0, pitch, yaw, look.target[3]])
	if look.snap != 0:
		look.target = PackedInt32Array([0, pitch, yaw, look.target[3]])
		look.current = look.target.duplicate()
		look.snap = 0
	elif newly:
		look.current = _head_angles(body.local_mats[HEAD_SLOT])
	else:
		for k: int in [1, 2]:
			var e := look.target[k] - look.current[k]
			var step := e - Fx.div_trunc(e, 2)
			if absi(step) > LOOK_STEP:
				step = LOOK_STEP if step > 0 else -LOOK_STEP
			look.current[k] = Fx.s16(look.current[k] + step)
		look.current[0] = look.target[0]
	body.local_mats[HEAD_SLOT] = Fx.mul_matrix(look_base, _angles_to_matrix(look.current))


## The three angles of the head's animated local matrix, so the look-at starts without a pop.
func _head_angles(m: PackedInt32Array) -> PackedInt32Array:
	var v48 := Gte.apply(m, 0x1000, 0, 0)
	var v38 := Gte.apply(m, 0, 0, 0x1000)
	var a28 := Fx.s16(FightMath.atan2_angle(Fx.s16(v48[1]), Fx.s16(v48[2]), t))
	var n := -a28
	var idx := ((n + 0xF if n < 0 else n) >> 4) & 0xFFF
	var s := FightMath.sin12(idx, t)
	var c := FightMath.cos12(idx, t)
	var y48 := Fx.trunc12(v48[1] * c - v48[2] * s)
	var y38 := Fx.trunc12(v38[1] * c - v38[2] * s)
	var z38 := Fx.trunc12(v38[1] * s + v38[2] * c)
	var a24raw := FightMath.atan2_angle(Fx.s16(v48[0]), Fx.s16(y48), t) - 0x4000
	var a24 := Fx.s16(a24raw)
	var m2 := -a24
	var idx2 := ((m2 + 0xF if m2 < 0 else m2) >> 4) & 0xFFF
	var s2 := FightMath.sin12(idx2, t)
	var c2 := FightMath.cos12(idx2, t)
	var x38 := Fx.trunc12(v38[0] * c2 - y38 * s2)
	var a26 := Fx.s16(FightMath.atan2_angle(Fx.s16(z38), Fx.s16(x38), t) - 0x4000)
	return PackedInt32Array([a26, a24, a28, 0])


## FUN_8003A5A0: a rotation from three 16-bit angles (x at +0, y at +2, z at +4).
func _angles_to_matrix(a: PackedInt32Array) -> PackedInt32Array:
	var i0 := ((a[0] & 0xFFFF) >> 4) & 0xFFF
	var i1 := ((a[1] & 0xFFFF) >> 4) & 0xFFF
	var i2 := (Fx.s16(a[2]) >> 4) & 0xFFF
	var s0 := FightMath.sin12(i0, t)
	var c0 := FightMath.cos12(i0, t)
	var s1 := FightMath.sin12(i1, t)
	var c1 := FightMath.cos12(i1, t)
	var s2 := FightMath.sin12(i2, t)
	var c2 := FightMath.cos12(i2, t)
	var r3 := (c0 * c2) >> 12
	var g1 := Fx.mvmva_gpf(s0, c2, s2, c1)
	var r6 := (c0 * s2) >> 12
	var g2 := Fx.mvmva_gpf(s1, g1[0], g1[1], r3)
	var g3 := Fx.mvmva_gpf(c1, c2, s2, c0)
	var m := PackedInt32Array()
	m.resize(9)
	m[7] = Fx.s16(g1[2])
	m[6] = Fx.s16(-s1)
	m[1] = Fx.s16(g2[0] - r6)
	m[4] = Fx.s16(r3 + g2[1])
	m[2] = Fx.s16(g1[1] + g2[2])
	m[5] = Fx.s16(((r6 * s1) >> 12) - g1[0])
	m[0] = Fx.s16(g3[0])
	m[3] = Fx.s16(g3[1])
	m[8] = Fx.s16(g3[2])
	return m
