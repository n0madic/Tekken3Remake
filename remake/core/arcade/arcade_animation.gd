class_name ArcadeAnimation
extends FighterAnimation
## FUN_8018B388 / FUN_80198298: the arcade's skeleton step. Poses are 57 channels (the root in polar
## form: an angle, a height and a distance; then three Euler angles per joint), no inverse kinematics.
## The root channels stay in one global (0x8021FAC8): whoever reads them reads the last decoded.

const FIRST_JOINT_CHANNEL := 3
const CHANNEL_ANGLE := 0
const CHANNEL_HEIGHT := 1
const CHANNEL_DISTANCE := 2
const LONGEST_BLEND := 0x10
const THROWN_BLEND := 0x10
const SHORT_BLEND := 4
const LEFT_TO_BLEND := 0xF
## True Ogre's sway: the joints that sway and their phases, in quarter turns (FUN_80193B20).
const OGRE_PHASES := {5: 0, 6: 1, 0x12: 2, 0x13: 3}
const OGRE_NARROWS := 0x13                          ## this joint's level narrows it, the others' widen
const OGRE_PHASE_STEP := 0x400
const OGRE_TILT_JOINT := 5
const OGRE_HEIGHT_JOINT := 6
const OGRE_MAX_HEIGHT := 0x100

var root_channels := PackedInt32Array([0, 0, 0])    ## 0x8021FAC8
var _ogre_tilt := 0                                 ## 0x8021F63C
var frame_view := ViewMatrix.new()                  ## the GTE's matrix of the frame (FUN_80198230)
var wind: ArcadeWind                                ## the attachments' wind (FUN_8019C738)


## FUN_8018B388.
func update_pair() -> void:
	for f in fight.active():
		if f.active != 0:
			animate_arcade(f)


## FUN_80198298.
func animate_arcade(f: FighterState) -> void:
	fight.replay.play_pose(f)
	decode_root(f)
	f.body.pose_vector = f.pose_move.anim_bank.pose(f.pose_move.anim, f.pose_frame - 1)
	_reanchor(f)
	if fight.blend_enabled != 0 and fight.blend_skip == 0:
		_transition_blend(f)
	fight.blend_skip = 0
	fight.replay.record_pose(f)
	root_update(f)
	if fight.paused_player == 0 and fight.freeze == 0:
		_update_hands(f)
	_blink(f)
	_compose(f)


## FUN_80198424: the running frame's root channels into the global and the record.
func decode_root(f: FighterState) -> void:
	var d := _decode_root(f, f.root_move, f.root_frame - 1)
	root_channels = d.slice(0, FIRST_JOINT_CHANNEL)
	f.root_dx = d[CHANNEL_ANGLE]
	f.root_dy = d[CHANNEL_HEIGHT]
	f.root_dz = d[CHANNEL_DISTANCE]


## FUN_80194B58: all the channels of a frame, height and distance scaled (a throw victim's by its
## opponent's scale); the angle stays.
func _decode_root(f: FighterState, move: MoveRow, frame: int) -> PackedInt32Array:
	var scale := fight.fighters[1 - f.index].scale if f.throw_state < 0 else f.scale
	var p := move.anim_bank.pose(move.anim, frame)
	p[CHANNEL_HEIGHT] = Fx.s16(Fx.trunc12(p[CHANNEL_HEIGHT] * scale))
	p[CHANNEL_DISTANCE] = Fx.s16(Fx.trunc12(p[CHANNEL_DISTANCE] * scale))
	return p


## FUN_801991B4.
func _reanchor(f: FighterState) -> void:
	if f.anchor_dirty == 0:
		return
	f.anchor_dirty = 0
	var d := _decode_root(f, f.root_move, maxi(0, f.root_frame - f.frame_step - 1))
	var a := (d[CHANNEL_ANGLE] + 0x8000 - f.facing) >> 4
	var distance: int = d[CHANNEL_DISTANCE]
	f.pos_x = Fx.w32(f.root_x - Fx.trunc12(distance * FightMath.sin12(a, t)))
	f.pos_z = Fx.w32(f.root_z + Fx.trunc12(distance * FightMath.cos12(a, t)))


## FUN_80194458: the replay shows the variants it recorded.
func _update_hands(f: FighterState) -> void:
	var hands := f.hands
	hands.update(0, f.air_free)
	if (hands as ArcadeHands).is_ogre():
		hands.wing_variant = fight.replay.wings(f, hands.wing_variant)
		hands.variant[0] = fight.replay.hand_pose(f, hands.variant[0], 0)
	else:
		for c in FighterHands.CHANNELS:
			hands.variant[c] = fight.replay.hand_pose(f, hands.variant[c], c)
	hands.replay_levels = fight.replay.hand_levels(f)


## FUN_801984E8: the root's matrix and position, from the global's channels. A playing replay's heading
## comes from its rotation.
func root_update(f: FighterState) -> void:
	var angles := PackedInt32Array([Fx.s16(f.tilt_x) >> 4, Fx.s16((0x8000 - f.heading) >> 4), Fx.s16(f.tilt_z) >> 4])
	angles = fight.replay.root_rotation(f, angles)
	if fight.replay_playing != 0:
		f.heading = Fx.s16(angles[1] * -0x10 - 0x8000)
	f.body.root_mat = _root_matrix(angles[0], angles[1], angles[2])
	var y := root_channels[CHANNEL_HEIGHT]
	if f.blend_mode == Blend.NONE or f.blend_frames == 0:
		f.blend_weight = 0x1000
	else:
		f.blend_weight = Fx.s16(Fx.div_trunc(Fx.w32(f.blend_counter << 12), f.blend_frames))
		var v := Fx.w32(f.blend_root_delta[CHANNEL_HEIGHT] * Fx.s16(f.blend_weight * 2))
		y = Fx.s16(y + ((v + 0x1FFF if v < 0 else v) >> 13))
	f.root_dy_blended = y
	f.root_x = f.pos_x
	f.root_y = f.pos_y
	f.root_z = f.pos_z
	if f.air_phase == 1:
		_replay_root(f)
		return
	f.root_y = Fx.w32(f.pos_y - y)
	if f.air_phase != 2:
		var a := (root_channels[CHANNEL_ANGLE] + 0x8000 - f.facing) >> 4
		var distance := root_channels[CHANNEL_DISTANCE]
		f.root_x = Fx.w32(f.pos_x + Fx.trunc12(distance * FightMath.sin12(a, t)))
		f.root_z = Fx.w32(f.pos_z - Fx.trunc12(distance * FightMath.cos12(a, t)))
	_replay_root(f)


## FUN_8019571C.
func _replay_root(f: FighterState) -> void:
	var replay := fight.replay as ArcadeReplay
	replay.root_position(f)
	if replay.starts_kept_camera(f):
		camera.replay_start(fight.fighters[0], fight.fighters[1])


## FUN_801A24A4: the rotation of three angles in 4096 units.
func _root_matrix(ax: int, ay: int, az: int) -> PackedInt32Array:
	var sx := FightMath.sin12(ax, t)
	var cx := FightMath.cos12(ax, t)
	var sy := FightMath.sin12(ay, t)
	var cy := FightMath.cos12(ay, t)
	var sz := FightMath.sin12(az, t)
	var cz := FightMath.cos12(az, t)
	var a := Fx.trunc12(sx * sy)
	var b := Fx.trunc12(cx * sy)
	return PackedInt32Array([
		Fx.s16(Fx.trunc12(cy * cz)), Fx.s16(Fx.trunc12(cy * sz)), Fx.s16(-sy),
		Fx.s16(Fx.trunc12(a * cz) - Fx.trunc12(cx * sz)), Fx.s16(Fx.trunc12(a * sz) + Fx.trunc12(cx * cz)), Fx.s16(Fx.trunc12(sx * cy)),
		Fx.s16(Fx.trunc12(b * cz) + Fx.trunc12(sx * sz)), Fx.s16(Fx.trunc12(b * sz) - Fx.trunc12(sx * cz)), Fx.s16(Fx.trunc12(cx * cy)),
	])


## The local rotation of a joint's channels: FUN_801984A0 and FUN_8019A498.
func _joint_local(pose: PackedInt32Array, joint: int) -> PackedInt32Array:
	var at := FIRST_JOINT_CHANNEL + 3 * joint
	return solver.euler_to_matrix(pose[at], Fx.s16(-pose[at + 1]), Fx.s16(-pose[at + 2]))


# ---- FUN_8019CD04 ---------------------------------------------------------------------------

func _transition_blend(f: FighterState) -> void:
	if fight.freeze != 0 or fight.paused_player != 0:
		_blend_finish(f)
		return
	if fight.blend_hold != 0:
		fight.blend_hold -= 1
		f.blend_mode = Blend.NONE
		if f.blend_active == 0:
			_blend_count(f)
		_blend_finish(f)
		return
	var n := 0
	if fight.replay_playing == 0:
		n = _blend_choose(f)
	if f.blend_active != 0:
		_blend_start_arcade(f, n)
	else:
		_blend_count(f)
	_blend_finish(f)


func _blend_choose(f: FighterState) -> int:
	f.blend_active = 0
	var pose := f.pose_move
	if f.blend_mode == Blend.DECAY and f.blend_counter == 0:
		f.blend_mode = Blend.NONE
	if f.last_pose_move != pose:
		if pose.flags & MoveFlag.NO_BLEND == 0:
			if f.move_changed != 0:
				var n := mini(_decay_frames(f), maxi(pose.length - f.pose_frame, 0))
				if n > 1:
					f.blend_active = 1
					f.blend_mode = Blend.DECAY
					return n
		elif f.blend_mode == Blend.DECAY:
			f.blend_mode = Blend.NONE
	if f.blend_mode == Blend.DECAY:
		return 0
	if f.juggle_count != 0 or (f.in_air != 0 and f.was_hit_this_move != 0) \
			or pose.flags & MoveFlag.NO_BLEND_FORWARD != 0 or f.trans_bit6 != 0:
		f.blend_mode = Blend.NONE
		return 0
	if f.move_row == null:
		return _stance_blend(f)
	if f.blend_mode == Blend.BRANCH:
		if f.blend_counter == f.blend_frames:
			f.blend_mode = Blend.NONE
	elif f.pose_frame < f.entry_frame:
		f.blend_mode = Blend.BRANCH
		f.blend_active = 1
	return 0


## The length of a decay blend, before the end of the move limits it. A hit during the move ends the
## running blend.
func _decay_frames(f: FighterState) -> int:
	var pose := f.pose_move
	if f.move_flag_ba != 0 or pose.length - f.pose_frame <= 0:
		return 0
	var first := pose.active_first
	if first != 0 and f.pose_frame < first:
		return mini(first - f.pose_frame, LONGEST_BLEND)
	if f.throw_state < 0:
		return THROWN_BLEND
	if f.was_hit_this_move == 0:
		return SHORT_BLEND
	f.blend_mode = Blend.NONE
	return 0


func _stance_blend(f: FighterState) -> int:
	var left := f.pose_move.length - f.pose_frame
	if left > LEFT_TO_BLEND:
		f.blend_mode = Blend.NONE
		return 0
	if f.blend_mode == Blend.STANCE:
		if f.move_changed != 0:
			f.blend_mode = Blend.NONE
		return 0
	var n := left + 1 if f.frame_step >= 1 else f.pose_frame
	if n < 2:
		return 0
	f.blend_mode = Blend.STANCE
	f.blend_active = 1
	return n


func _blend_start_arcade(f: FighterState, n: int) -> void:
	var playback := fight.replay_playing != 0
	match f.blend_mode:
		Blend.DECAY:
			if not playback:
				f.blend_src_move = f.last_pose_move
				f.blend_src_frame = (f.event_frame - 1) & 0xFF
				f.blend_dst_move = f.pose_move
				f.blend_dst_frame = (f.pose_frame - 1) & 0xFF
				f.blend_frames = n
			f.blend_counter = f.blend_frames - 1
			_decay_deltas(f)
		Blend.BRANCH:
			if not playback:
				f.blend_src_move = f.pose_move
				f.blend_src_frame = f.entry_frame & 0xFF
				f.blend_dst_move = fight.move_for_slot(f, f.move_slot)
				f.blend_dst_frame = (f.entry_frame if f.transition in ENTRY_DST_CODES else 0) & 0xFF
				f.blend_frames = maxi(f.entry_frame - f.pose_frame + 1, 1)
			f.blend_counter = 0
			_forward_deltas(f)
		Blend.STANCE:
			if not playback:
				f.blend_src_move = f.pose_move
				f.blend_src_frame = (0 if f.frame_step < 1 else f.pose_move.length) & 0xFF
				f.blend_dst_move = fight.move_for_slot(f, Fx.s16(f.pose_move.stance_slot))
				f.blend_dst_frame = 0
				f.blend_frames = n
			f.blend_counter = 0
			_forward_deltas(f)


## The shown pose against the new move's first: only the height of the shown root is kept.
func _decay_deltas(f: FighterState) -> void:
	var dst := _decode_root(f, f.blend_dst_move, f.blend_dst_frame)
	f.blend_root_delta[CHANNEL_ANGLE] = Fx.s16(-dst[CHANNEL_ANGLE])
	f.blend_root_delta[CHANNEL_HEIGHT] = Fx.s16(f.root_dy_blended - dst[CHANNEL_HEIGHT])
	f.blend_root_delta[CHANNEL_DISTANCE] = Fx.s16(-dst[CHANNEL_DISTANCE])
	var body := f.body
	for j in range(1, FighterBody.JOINTS):
		var local := _joint_local(dst, j)
		var saved := body.prev_local_mats[j - 1]
		var delta := body.blend_delta[j - 1]
		for e in 9:
			delta[e] = Fx.s16(saved[e] - local[e])


func _forward_deltas(f: FighterState) -> void:
	var src := _decode_root(f, f.blend_src_move, f.blend_src_frame)
	var dst := _decode_root(f, f.blend_dst_move, f.blend_dst_frame)
	for k in FIRST_JOINT_CHANNEL:
		f.blend_root_delta[k] = Fx.s16(dst[k] - src[k])
	var body := f.body
	for j in range(1, FighterBody.JOINTS):
		var a := _joint_local(src, j)
		var b := _joint_local(dst, j)
		var delta := body.blend_delta[j - 1]
		for e in 9:
			delta[e] = Fx.s16(b[e] - a[e])


func _blend_finish(f: FighterState) -> void:
	f.last_pose_move = f.pose_move
	f.last_pose_frame = f.pose_frame
	f.root_dy_blended = root_channels[CHANNEL_HEIGHT]


# ---- FUN_80193F90 ---------------------------------------------------------------------------

func _blink(f: FighterState) -> void:
	var hands := f.hands as ArcadeHands
	var pose := f.pose_move
	var tables := t.fighter
	if pose.flags & MoveFlag.REACT_CHAIN:
		hands.face_command(_of_costume(tables.face_react, f), 2)
	elif pose.state & StateBit.DOWN and pose.flags & MoveFlag.LOOK_AT == 0:
		hands.face_command(_of_costume(tables.face_down, f), 2)
	if hands.face_speed == 0:
		if hands.face == 0:
			hands.face_command(_of_costume(tables.face_blink, f), 3)
		else:
			hands.face_command(0, (fight.rng.next() & 0xFE) | 1)
	hands.face_speed = Fx.s16(hands.face_speed - 1)


static func _of_costume(table: PackedInt32Array, f: FighterState) -> int:
	return table[f.costume_slot] if f.costume_slot >= 0 and f.costume_slot < table.size() else 0


# ---- FUN_80198754 ---------------------------------------------------------------------------

func _compose(f: FighterState) -> void:
	var body := f.body
	body.root = JointFrame.new(body.root_mat, PackedInt32Array([f.root_x, f.root_y, f.root_z]))
	for j in FighterBody.JOINTS:
		var local := _joint_local(body.pose_vector, j)
		if j != 0:
			if f.blend_mode != Blend.NONE:
				local = _orthonormalize(_add_scaled(body.blend_delta[j - 1], local, f.blend_weight))
			body.prev_local_mats[j - 1] = local
		body.local_mats[j] = local
	_head_look_at(f, fight.fighters[1 - f.index])
	var ogre := (f.hands as ArcadeHands).is_ogre()
	if ogre:
		_ogre_sway_start(f)
	for j in FighterBody.JOINTS:
		var parent := body.root if body.parents[j] < 0 else body.joints[body.parents[j]]
		var local := body.local_mats[j]
		if ogre and OGRE_PHASES.has(j):
			local = _ogre_sway_local(f, j)
		body.joints[j] = JointFrame.compose_offset(parent, local, _ogre_offset(body, j) if ogre else body.offsets[j])
	_compose_rows(f, ogre)
	body.draw_joints = body.joints.duplicate()
	f.screen_x = frame_view.screen_of(body.joints[SCREEN_JOINT])[0]       # FUN_8019A6B8, FUN_8019A6D0


## FUN_80198754's rows 18–23: FUN_8019B6D8 keeps the rotations of the frames when the game stands still.
func _compose_rows(f: FighterState, ogre: bool) -> void:
	var body := f.body as ArcadeBody
	body.begin_rows()
	body.rows.wind = wind.vector
	var moves := fight.paused_player == 0 and fight.freeze == 0
	for a: CharacterModel.ArcadeAttachment in body.model.arcade_attachments:
		var row := a.joint - CharacterModel.ARCADE_JOINT + ArcadeBody.FIRST_ROW
		var local := body.row_local(a, moves)
		var offset := ArcadeBody.row_offset(a)
		if ogre and OGRE_PHASES.has(row):
			local = _ogre_sway_local(f, row)
			offset = _ogre_offset(body, row)
		body.compose_row(a, local, offset)


# ---- True Ogre ------------------------------------------------------------------------------

## FUN_80193A38: the sway's counter, its phases (not while the game stands still), the tilt from joint
## 5's pose and the amount by how high the tail hung last frame.
func _ogre_sway_start(f: FighterState) -> void:
	var body := f.body
	body.ogre_sway = Fx.s16(body.ogre_sway + 1)
	if fight.paused_player == 0 and fight.freeze == 0:
		fight.ogre_phase_x = (body.ogre_sway & 0x7F) << 5
		fight.ogre_phase_y = (body.ogre_sway & 0x3F) << 6
	var tilt_channel := FIRST_JOINT_CHANNEL + 3 * OGRE_TILT_JOINT + 2
	_ogre_tilt = Fx.div_trunc(Fx.s16(-body.pose_vector[tilt_channel]), 4)
	fight.ogre_height = clampi(Fx.div_trunc(-body.joints[OGRE_HEIGHT_JOINT].t[1], 2), 0, OGRE_MAX_HEIGHT)


## FUN_80193B20 for a joint that sways: the rotation of its phase, scaled by the level (the replay's
## while it plays).
func _ogre_sway_local(f: FighterState, j: int) -> PackedInt32Array:
	var level := (fight.replay as ArcadeReplay).ogre_level(f)
	var phase := (OGRE_PHASES[j] as int) * OGRE_PHASE_STEP
	var amount := Fx.div_trunc((OGRE_MAX_HEIGHT - level) * fight.ogre_height, 0x100)
	var half_sine := Fx.div_trunc(FightMath.sin12(fight.ogre_phase_x + phase, t), 2)
	var angle_x := Fx.s16(_ogre_shift(half_sine * amount))
	var angle_y := Fx.s16(Fx.s16(_ogre_shift(FightMath.sin12(fight.ogre_phase_y + phase, t) * amount)) + _ogre_tilt)
	var rot := _angles_to_matrix(PackedInt32Array([0, angle_x, angle_y]))
	var quarter := Fx.div_trunc(level, 4)
	var row_scale := 0x100 + (-quarter if j == OGRE_NARROWS else quarter)
	var col_scale := 0x100 + Fx.div_trunc(level, 8)
	for r in 3:
		rot[3 * r] = Fx.s16(_ogre_shift(rot[3 * r] * row_scale))
		rot[3 * r + 1] = Fx.s16(_ogre_shift(rot[3 * r + 1] * col_scale))
		rot[3 * r + 2] = Fx.s16(_ogre_shift(rot[3 * r + 2] * col_scale))
	return rot


## The offset True Ogre's joint is placed with: its slot's, joint 5's being an attachment row's.
static func _ogre_offset(body: FighterBody, j: int) -> PackedInt32Array:
	var slot := _ogre_slot(j)
	if slot < FighterBody.JOINTS:
		return body.offsets[slot]
	var row := body.model.arcade_attachments[slot - FighterBody.JOINTS]
	return PackedInt32Array([row.offset.x, row.offset.y, -row.offset.z])


## The program's division by 256 of a signed product: rounded up when negative, as a logical shift.
static func _ogre_shift(value: int) -> int:
	return ((value + 0xFF if value < 0 else value) & 0xFFFFFFFF) >> 8


## FUN_8019A498.
func _angles_to_matrix(a: PackedInt32Array) -> PackedInt32Array:
	return solver.euler_to_matrix(a[0], a[1], a[2])


## The opponent's middle point of joints 1 and 2 in the look-at, by a division.
func _look_midpoint(a: int, b: int) -> int:
	return a + Fx.div_trunc(b - a, 2)
