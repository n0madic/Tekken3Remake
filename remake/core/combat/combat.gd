class_name Combat
extends RefCounted
## Everything between the two fighters' bodies (combat.md, fight-frame.md): PairwiseDistances,
## ArenaBounds with its ramp and the throw link, the saved segment ends, FighterVelocity,
## CollisionShapesUpdate with the baked attack points, BodySphereProfile, BodySeparate,
## HitTest, AttackVelocity and HitApply.
##
## Written from the verified ports in tools/research/fight_sim.py (arena_bounds, body_separate,
## collision_shapes_update, attack_segments_baked, hit_test, hit_apply) and the decompiled
## PairwiseDistances, BodySphereProfile and HitSpawnEffect.

const ARENA_HALF := 300000
const FOLLOW_START := 0x1CFF
const FOLLOW_MAX := 0x1E00
const RAMP_MAX := 2000
const SEPARATION_RANGE := 3000
const FRONT_REACH := 200
const FRONT_NEAR := 500
const CHARGE_OVERLAP := 400
const HEIGHT_GAP := 299
const SCREEN_EDGE := 0x191
const LOW_ATTACK := AttackWord.LOW
const JUMP_CLASS := 12
const PROJECTILE_JOINT := 0x18
const HURT_ZONE_Y := {8: -0x78, 11: -0x3C}
## Byte offset of frame t's points in a baked attack record, by layout kind: (stride, lead).
const LAYOUT_STRIDE := {0: Vector2i(10, 0), 1: Vector2i(5, 5), 2: Vector2i(10, 10), 3: Vector2i(15, 5),
	4: Vector2i(15, 5), 5: Vector2i(20, 0), 6: Vector2i(10, 5), 7: Vector2i(10, 5), 9: Vector2i(10, 5),
	10: Vector2i(15, 0), 12: Vector2i(15, 0), 13: Vector2i(15, 0), 14: Vector2i(15, 0)}
## Weapon points computed into spare joints outside the active window: bank type, character
## (−1: any), joint, local point, target joint.
const WEAPON_POINTS := [
	[BankType.YOSHIMITSU, -1, 10, [100, -720, 0], 18], [BankType.YOSHIMITSU, -1, 10, [100, -360, 0], 19],
	[BankType.OGRE, Character.TRUE_OGRE, 11, [100, -500, 0], 22],
	[BankType.OGRE, Character.TRUE_OGRE, 2, [800, 0, 600], 23],
	[BankType.GON, -1, 11, [200, 900, 0], 21], [BankType.GON, -1, 2, [400, 0, 100], 23],
]

var fight: FightState
var t: FightTables
var moves: MoveSystem
var physics: FighterPhysics


func _init(fight_state: FightState, move_system: MoveSystem, fighter_physics: FighterPhysics) -> void:
	fight = fight_state
	t = fight_state.tables
	moves = move_system
	physics = fighter_physics


static func _pair(a: int, b: int) -> int:
	if a > 1:
		a = 1 << (a - 1)
	if b > 1:
		b = 1 << (b - 1)
	return a + b


# ---- distances --------------------------------------------------------------------------------

## PairwiseDistances (0x8004391C): distance, offset and direction of every pair, then per
## fighter its distance to its opponent and the direction (or, with a fixed facing or an
## opponent off screen, a screen-based stand-in).
func pairwise_distances() -> void:
	var fs := fight.active()
	var offscreen := PackedInt32Array([0, 0, 0])
	for i in fs.size():
		offscreen[i] = 1 if (fs[i].screen_x & 0xFFFF) >= SCREEN_EDGE else 0
		if fight.mode == GameMode.FORCE and fs[i].is_cpu != 0 and fight.force.slot_free(fs[i].index - 1):
			offscreen[i] = 1
	for i in range(fs.size() - 1, 0, -1):
		for j in range(i - 1, -1, -1):
			var dx := Fx.w32(fs[i].root_x - fs[j].root_x)
			var dz := Fx.w32(fs[i].root_z - fs[j].root_z)
			var p := _pair(i, j)
			fight.pair_distance[p] = CameraMath.isqrt(Fx.w32(dx * dx + dz * dz))
			fight.pair_dx[p] = dx
			fight.pair_dz[p] = dz
			fight.pair_dir[p] = FightMath.atan2_angle(dz, dx, t)
	for f in fs:
		f.placed_x = f.root_x
		f.placed_z = f.root_z
		var o := fight.opponent_index(f)
		var p := _pair(f.index, o)
		f.dist = fight.pair_distance[p] & 0xFFFFFFFF
		var opp := fight.fighters[o]
		var big := 0
		if f.char_id == Character.KUMA or f.char_id == Character.TRUE_OGRE:
			big = 1
		if opp.char_id == Character.KUMA or opp.char_id == Character.TRUE_OGRE:
			big += 1
		f.dist_adj = (f.dist - big * 0x28) & 0xFFFFFFFF
		f.dir_x = fight.pair_dx[p]
		f.dir_z = fight.pair_dz[p]
		var dir := fight.pair_dir[p] if o < f.index else fight.pair_dir[p] - 0x8000
		if f.fixed_facing == 0 and offscreen[o] == 0:
			f.target_dir = dir & 0xFFFF
		else:
			var x := absi(0xB4 - absi(0xB4 - Fx.s16(f.screen_x)))
			f.target_dir = (0x4000 if f.fixed_facing_side == 0 else -0x4000) & 0xFFFF
			f.dist = x * 10
			f.dir_x = x * 10
			f.dir_z = 0
	fight.fighter_distance = fs[0].dist


# ---- arena bounds -----------------------------------------------------------------------------

const BALL_COURT_X := 0x1400
const BALL_COURT_Z := 0x100
const BALL_CROSS := 1000
const BALL_CEILING := -0x1200
const NO_POSTURE := 0x5000
const THROW_DRIFT := 0x578
const FORCED_HIT_SOUND := 0x4951    ## FUN_800421BC: SoundPlayFighter(0, 0x4951, 0)


static func _excess(v: int, limit: int) -> int:
	var over := absi(v) - limit
	if over <= 0:
		return 0
	return -over if v > 0 else over


static func _clamp_ramp(v: int, limit: int) -> int:
	if limit < absi(v):
		return -limit if v < 1 else limit
	return v


## ArenaBounds (0x80043394) for the normal modes: the root back inside |x|, |z| ≤ 300,000, and
## the pull towards the opponent (or back to where the fighter stood) beyond 0x1E00 apart;
## Tekken Ball's court and Tekken Force's walls in their modes.
func arena_bounds(f: FighterState) -> void:
	var opp := fight.opponent(f)
	var dx := 0
	var dy := 0
	var dz := 0
	if fight.mode == GameMode.BALL:
		# The Tekken Ball court: a fighter on the other half goes back to the net, and one far
		# across loses its posture (no attack can hit it) and its body push.
		dz = _excess(f.root_z, BALL_COURT_Z)
		dx = _excess(f.root_x, BALL_COURT_X)
		var x := f.root_x
		if (f.index == 0 and x >= 0) or (f.index == 1 and x < 1):
			dx = -x
			if absi(x) > BALL_CROSS:
				f.state = NO_POSTURE
				f.hit_done[0] = 0
				f.hit_done[1] = 0
				f.no_body_push = 1
		if BALL_CEILING - f.root_y > 0:
			dy = BALL_CEILING - f.root_y
	elif fight.mode == GameMode.FORCE and fight.round_state != RoundState.INTRO:
		var d := fight.force.walls(f)
		dz = d.x
		dx = d.y
	else:
		dx = _excess(f.root_x, ARENA_HALF)
		dz = _excess(f.root_z, ARENA_HALF)
		if FOLLOW_START < f.dist:
			var ex := Fx.w32(opp.placed_x - f.root_x)
			var ez := Fx.w32(opp.placed_z - f.root_z)
			var d := FightMath.sqrt_table(Fx.w32(ex * ex + ez * ez), t)
			if d < FOLLOW_MAX + 1:
				if f.dist <= d:
					dx = Fx.w32(f.placed_x - f.root_x)
					dz = Fx.w32(f.placed_z - f.root_z)
			else:
				var v := physics.polar(Fx.w32(d - FOLLOW_MAX), f.target_dir)
				dx = v.x
				dz = v.y
	if fight.mode == GameMode.BALL and f.throw_state < 0:
		fight.bound_ramp[f.index] = 0
		fight.bound_ramp_step[f.index] = 0
	var limit := fight.bound_ramp[f.index]
	dx = _clamp_ramp(dx, limit)
	dy = _clamp_ramp(dy, limit)
	dz = _clamp_ramp(dz, limit)
	var movers: Array[FighterState] = [f]
	if f.in_throw != 0 and opp.in_throw != 0 and fight.throw_link != 0:
		movers.append(opp)
	for m in movers:
		m.pos_x = Fx.w32(m.pos_x + dx)
		m.pos_z = Fx.w32(m.pos_z + dz)
		m.pos_y = Fx.w32(m.pos_y + dy)
		m.root_x = Fx.w32(m.root_x + dx)
		m.root_z = Fx.w32(m.root_z + dz)
		m.root_y = Fx.w32(m.root_y + dy)


## FUN_800432B0 (Tekken Ball and Tekken Force): a throw victim's anchor follows the thrower's
## while the throw link holds; in Tekken Force the link drops when the pair drifts more than
## 0x578 apart after the move's 18th frame.
func throw_anchor(f: FighterState) -> void:
	if fight.mode != GameMode.BALL and fight.mode != GameMode.FORCE:
		return
	var opp := fight.opponent(f)
	if f.in_throw == 0 or opp.in_throw == 0 or f.throw_state >= 0:
		return
	if fight.mode == GameMode.FORCE and f.move_frame > 0x12 \
			and (fight.pair_distance[_pair(f.index, opp.index)] & 0xFFFFFFFF) > THROW_DRIFT:
		fight.throw_link = 0
	if fight.throw_link != 0:
		f.pos_x = opp.pos_x
		f.pos_z = opp.pos_z


## FUN_80043260: the throw link follows the number of fighters in a throw.
func update_throw_link() -> void:
	if fight.throw_count < 2:
		fight.throw_link = 0
	elif fight.throw_count_seen != fight.throw_count:
		fight.throw_link = 1
	fight.throw_count_seen = fight.throw_count


## ArenaRampStep (0x800431D8): the correction limit grows by an increment that grows by 2.
func ramp_step() -> void:
	for i in 3:
		if fight.bound_ramp[i] < RAMP_MAX:
			fight.bound_ramp[i] += fight.bound_ramp_step[i]
			fight.bound_ramp_step[i] += 2
		if RAMP_MAX < fight.bound_ramp[i]:
			fight.bound_ramp[i] = RAMP_MAX
			fight.bound_ramp_step[i] = 2


## FUN_80045B10: the number of fighters in a throw.
func count_throws() -> int:
	var n := 0
	for f in fight.active():
		if f.in_throw != 0:
			n += 1
	return n


# ---- per-frame records ----------------------------------------------------------------------

## FighterSavePrevSegments (0x8006AD84): the anchor and segment ends of the last frame; a
## segment without a start joint then sweeps from its old end.
func save_prev_segments(f: FighterState) -> void:
	var i := f.index
	fight.segment_anchor[i] = PackedInt32Array([f.pos_x, f.pos_y, f.pos_z])
	var s0 := f.attack_segs[0]
	var s1 := f.attack_segs[1]
	fight.segment_end0[i] = s0.slice(3, 6)
	fight.segment_end1[i] = s1.slice(3, 6)
	for k in 3:
		s0[k] = s0[3 + k]
		s1[k] = s1[3 + k]


## SavePlayerPosition (0x80046F98).
func save_position(f: FighterState) -> void:
	var r := fight.prev_roots[f.index]
	r[0] = f.root_x
	r[1] = f.root_y
	r[2] = f.root_z


## FighterVelocity (0x80040CA4).
static func velocity(f: FighterState) -> void:
	f.vel_x = Fx.w32(f.root_x - f.prev_root_x)
	f.vel_y = Fx.w32(f.root_y - f.prev_root_y)
	f.vel_z = Fx.w32(f.root_z - f.prev_root_z)
	f.prev_root_x = f.root_x
	f.prev_root_y = f.root_y
	f.prev_root_z = f.root_z


## AttackVelocity (0x80040CF8): the direction of the first attack segment.
static func attack_velocity(f: FighterState) -> void:
	var s := f.attack_segs[0]
	f.atk_dir_x = Fx.w32(s[3] - s[0])
	f.atk_dir_y = Fx.w32(s[4] - s[1])
	f.atk_dir_z = Fx.w32(s[5] - s[2])


# ---- collision shapes -----------------------------------------------------------------------

## CollisionShapesUpdate (0x80042204): attack segments (baked inside the active window, from the
## joints outside it), the hurt cylinders and the body spheres.
func collision_shapes(f: FighterState, joints: Array[JointFrame]) -> void:
	var pose := f.pose_move
	if pose.active_first <= f.pose_frame and f.pose_frame <= pose.active_last:
		_attack_segments_baked(f)
	else:
		for w: Array in WEAPON_POINTS:
			if f.bank_type != w[0] or (w[1] >= 0 and f.char_id != w[1]):
				continue
			var joint: JointFrame = joints[w[2]]
			var point: Array = w[3]
			var p := PackedInt32Array(point)
			var m := joint.rot
			var out := PackedInt32Array([0, 0, 0])
			for r in 3:
				out[r] = Fx.w32(Fx.w32((m[3 * r] * p[0] + m[3 * r + 1] * p[1] + m[3 * r + 2] * p[2]) >> 12) + joint.t[r])
			# A new frame: the one composed this step stays in FighterBody.draw_joints.
			var target: int = w[4]
			joints[target] = JointFrame.new(joints[target].rot, out)
		var d := AttackRecords.header(pose, t)
		for k in f.attack_seg_count:
			var seg := f.attack_segs[k]
			var a := _segment_joint(f, d[2 * k])
			if a >= 0:
				var p := joints[a].t
				seg[3] = p[0]
				seg[4] = p[1]
				seg[5] = p[2]
			var b := d[2 * k + 1]
			if b != 0:
				b = _segment_joint(f, b)
				if b >= 0:
					var q := joints[b].t
					seg[0] = q[0]
					seg[1] = q[1]
					seg[2] = q[2]
	for k in 14:
		var p := joints[t.hurt_zone_joints[k]].t
		var zone := f.hurt_zones[k]
		zone[0] = p[0]
		var lift: int = HURT_ZONE_Y.get(k, 0)
		zone[1] = Fx.w32(p[1] + lift)
		zone[2] = p[2]
	for k in 8:
		var p := joints[t.body_sphere_joints[k]].t
		var sphere := f.body_points[k]
		sphere[0] = p[0]
		sphere[1] = p[1]
		sphere[2] = p[2]
	f.prev_hurt_zone = f.hurt_zones[0].slice(0, 3)


func _segment_joint(f: FighterState, joint: int) -> int:
	if joint == 0x13:
		return 6 if f.char_id == Character.OGRE else joint
	return joint if joint < 0x18 else -1


## FUN_8006A6A4: the attack segments inside the active window from the baked points.
func _attack_segments_baked(f: FighterState) -> void:
	var move := f.pose_move
	if f.attack_seg_count == 0 or not AttackRecords.has_descriptor(move):
		return
	var data := AttackRecords.bytes_of(move, t)
	var desc := AttackRecords.offset_of(move, t)
	if data[desc] > 0x17:
		return
	var i := f.index
	var seg0 := f.attack_segs[0]
	var seg1 := f.attack_segs[1]
	var delta := Fx.w32(f.heading - f.facing)
	var swing := PackedInt32Array()
	if delta != 0:
		var sc := _trig_neg16(delta)
		swing = PackedInt32Array([sc.x, sc.y, delta, f.root_x, f.root_y, f.root_z])
	var trig := _trig_neg16(f.heading)
	var flags := data[desc + 4] << 8 | data[desc + 5]
	var extra := 0
	match fight.alt_points[i]:
		1:
			extra = (flags & 0x7FFF) >> 4
		2:
			extra = (flags & 0x7FFE) >> 3 if data[desc + 4] & 0x80 else 0
		0:
			extra = 0
		_:
			return
	var kind := flags & 0xF
	var frame := f.pose_frame - move.active_first
	if not LAYOUT_STRIDE.has(kind):
		return
	var layout: Vector2i = LAYOUT_STRIDE[kind]
	var p := desc + 6 + layout.x * frame + layout.y + extra
	var cur := PackedInt32Array([f.pos_x, f.pos_y, f.pos_z])
	var prev := fight.segment_anchor[i]
	var q := 0
	if kind in [1, 2, 4, 6, 7]:
		if frame != 0:
			_copy(seg0, 0, fight.segment_end0[i], 0)
		else:
			_place(seg0, 0, _unpack(data, p - (10 if kind == 2 else 5)), prev, trig, swing)
		_place(seg0, 3, _unpack(data, p), cur, trig, swing)
		q = p + 5
	else:
		_place(seg0, 0, _unpack(data, p), cur, trig, swing)
		_place(seg0, 3, _unpack(data, p + 5), cur, trig, swing)
		q = p + 10
	match kind:
		2, 3:
			if frame != 0:
				_copy(seg1, 0, fight.segment_end1[i], 0)
			else:
				_place(seg1, 0, _unpack(data, q - (10 if kind == 2 else 15)), prev, trig, swing)
			_place(seg1, 3, _unpack(data, q), cur, trig, swing)
		4, 5:
			_place(seg1, 0, _unpack(data, q), cur, trig, swing)
			_place(seg1, 3, _unpack(data, q + 5), cur, trig, swing)
		6, 10:
			_place(seg1, 0, _unpack(data, q), cur, trig, swing)
			_copy(seg1, 3, seg0, 3)
		7:
			_copy(seg1, 0, seg0, 3)
			_place(seg1, 3, _unpack(data, q), cur, trig, swing)
		9, 12:
			if kind == 12:
				_place(seg1, 0, _unpack(data, q), cur, trig, swing)
			elif frame == 0:
				_place(seg1, 0, _unpack(data, q - 5), prev, trig, swing)
			else:
				_copy(seg1, 0, fight.segment_end1[i], 0)
			_copy(seg1, 3, seg0, 0)
		13:
			_copy(seg1, 0, seg0, 0)
			_place(seg1, 3, _unpack(data, q), cur, trig, swing)
		14:
			_place(seg1, 3, _unpack(data, q), cur, trig, swing)
			_copy(seg1, 0, seg1, 3)


static func _copy(dst: PackedInt32Array, at: int, src: PackedInt32Array, from: int) -> void:
	for k in 3:
		dst[at + k] = src[from + k]


## sin and cos of −angle (16-bit angle units, the plain int), 4.12.
func _trig_neg16(angle: int) -> Vector2i:
	var a := -angle
	var idx := ((a + 0xF if a < 0 else a) >> 4) & 0xFFF
	return Vector2i(FightMath.sin12(idx, t), FightMath.cos12(idx, t))


## FUN_800699FC: a 40-bit point, x and y 13 bits (bias 0x1000), z 14 bits (bias 0x2000).
static func _unpack(data: PackedByteArray, at: int) -> PackedInt32Array:
	var v := 0
	for k in 5:
		v |= (data[at + k] if at + k < data.size() else 0) << (8 * k)
	return PackedInt32Array([(v & 0x1FFF) - 0x1000, ((v >> 13) & 0x1FFF) - 0x1000, (v >> 26) - 0x2000])


## FUN_8006A518: origin (swung about the root by heading − facing) + point rotated by −heading.
static func _place(out: PackedInt32Array, at: int, p: PackedInt32Array, origin: PackedInt32Array,
		trig: Vector2i, swing: PackedInt32Array) -> void:
	var ox := origin[0]
	var oy := origin[1]
	var oz := origin[2]
	if not swing.is_empty():
		var s := swing[0]
		var c := swing[1]
		var dx := Fx.w32(swing[3] - ox)
		var dz := Fx.w32(swing[5] - oz)
		ox = Fx.w32(swing[3] - Fx.trunc12(Fx.w32(dx * c - dz * s)))
		oz = Fx.w32(swing[5] - Fx.trunc12(Fx.w32(dx * s + dz * c)))
	var sn := trig.x
	var cs := trig.y
	out[at] = Fx.w32(ox + Fx.trunc12(Fx.w32(p[0] * cs)) - Fx.trunc12(Fx.w32(p[2] * sn)))
	out[at + 1] = Fx.w32(oy + p[1])
	out[at + 2] = Fx.w32(oz + Fx.trunc12(Fx.w32(p[0] * sn)) + Fx.trunc12(Fx.w32(p[2] * cs)))


## BodySphereProfile (0x8003EEFC): the body sphere radii by the move's profile (+0x30).
func body_sphere_profile(f: FighterState) -> void:
	var pose := f.pose_move
	var profile := pose.body_profile
	var radii := t.body_radii[f.char_id]
	var r := PackedInt32Array()
	r.resize(8)
	match profile & 0xF:
		0:
			var drop := false
			if (profile >> 12) & 1 == 0 or pose.active_first == 0:
				drop = true
			elif pose.active_first - 8 < f.pose_frame:
				drop = f.pose_frame < pose.active_last
			for k in 8:
				r[k] = 0 if drop and (Fx.s16(profile) >> (k + 4)) & 1 else radii[k]
		1:
			for k in 8:
				r[k] = radii[0] if k == 0 else radii[3] if k == 3 else 1
		2:
			r.fill(1)
		3:
			for k in 8:
				r[k] = radii[k] >> 1
		4:
			r.fill(0)
		5:
			for k in 8:
				r[k] = radii[0] >> 1 if k == 0 else radii[3] >> 1 if k == 3 else 1
		6:
			for k in 8:
				r[k] = radii[0] + 0x3C if k == 0 else 1 if k == 4 or k == 5 or k == 6 or k == 7 else radii[k]
		7:
			for k in 8:
				r[k] = radii[k] + 100
		_:
			for k in 8:
				r[k] = radii[k]
	for k in 8:
		var zero := false
		if pose.active_first == 0:
			if f.in_air == 0 or f.was_hit_this_move == 0:
				if pose.flags & MoveFlag.BODY_ADJUST and (k >= 6 or k == 4 or k == 5):
					zero = true
			elif k >= 6:
				zero = true
		elif k == 1 or k == 2:
			zero = true
		f.body_points[k][3] = 0 if zero else Fx.s16(r[k])


# ---- body separation --------------------------------------------------------------------------

## FUN_80043F40: clears the contact flags; a fighter in a throw and its partner are not pushed.
func clear_contacts() -> void:
	# FUN_80043F40: the third record too in Tekken Ball (the ball's attacker) and Tekken Force.
	var records: Array[FighterState] = fight.fighters.slice(0, FightState.RECORDS) if fight.mode == GameMode.BALL or fight.mode == GameMode.FORCE else fight.active()
	for f in records:
		f.body_contact = 0
		f.no_body_push = 0
		for k in 3:
			f.body_contact_with[k] = 0
	for f in records:
		if f.throw_state != 0:
			f.no_body_push = 1
			fight.fighters[f.throw_partner].no_body_push = 1


## BodySeparate (0x8004401C).
func body_separate(a: FighterState, b: FighterState) -> void:
	var pair := fight.pair_distance[_pair(a.index, b.index)] & 0xFFFFFFFF
	var solid := a.invulnerable != 1 and a.active != 0 and b.invulnerable != 1 and b.active != 0
	if not (pair < SEPARATION_RANGE + 1 and solid and (a.no_body_push == 0 or b.no_body_push == 0)):
		return
	_overlap_solve(a, b)
	for pair_f: Array in [[a, b], [b, a]]:
		var f: FighterState = pair_f[0]
		var other: FighterState = pair_f[1]
		if f.body_push_x != 0 or f.body_push_y != 0 or f.body_push_z != 0:
			f.body_contact = 1
			f.body_contact_with[other.index] = 1
			if fight.mode == GameMode.FORCE and fight.throw_count > 1:
				# Tekken Force during throws: a pushable body is pushed twice as far, the other not.
				if f.no_body_push == 0:
					f.body_push_x = Fx.w32(f.body_push_x << 1)
					f.body_push_y = Fx.w32(f.body_push_y << 1)
					f.body_push_z = Fx.w32(f.body_push_z << 1)
				else:
					f.body_push_x = 0
					f.body_push_y = 0
					f.body_push_z = 0
			f.pos_x = Fx.w32(f.pos_x + f.body_push_x)
			f.pos_y = Fx.w32(f.pos_y + f.body_push_y)
			f.pos_z = Fx.w32(f.pos_z + f.body_push_z)
			f.root_x = Fx.w32(f.root_x + f.body_push_x)
			f.root_y = Fx.w32(f.root_y + f.body_push_y)
			f.root_z = Fx.w32(f.root_z + f.body_push_z)


static func _axis_angle(facing: int) -> int:
	return 0x400 - Fx.div_trunc(Fx.s16(facing), 16)


func _deepest_overlap(a: FighterState, b: FighterState) -> int:
	var best := 0
	for pa in a.body_points:
		var ar := pa[3] & 0xFFFF
		if ar == 0:
			continue
		for pb in b.body_points:
			var br := pb[3] & 0xFFFF
			if br == 0:
				continue
			var reach := ar + br
			var dx := Fx.s16(pb[0] - pa[0])
			var dy := Fx.s16(pb[1] - pa[1])
			var dz := Fx.s16(pb[2] - pa[2])
			if absi(dx) < reach & 0xFFFF and absi(dy) < reach & 0xFFFF and absi(dz) < reach & 0xFFFF:
				var d := FightMath.sqrt_table(Fx.w32(dx * dx + dy * dy + dz * dz), t)
				if Fx.s16(best) < Fx.s16(reach - d):
					best = (reach - d) & 0xFFFF
	return Fx.s16(best)


## BodyOverlapSolve (0x80046FCC): fills bodyPushX/Y/Z of both fighters.
func _overlap_solve(a: FighterState, b: FighterState) -> void:
	for f: FighterState in [a, b]:
		f.body_push_x = 0
		f.body_push_y = 0
		f.body_push_z = 0
	var overlap := _deepest_overlap(a, b)
	var charging := false
	if a.pose_move.active_first != 0 and b.pose_move.active_first != 0:
		if overlap < 1 and absi(a.root_y - b.root_y) > HEIGHT_GAP:
			return
		var fronts: Array[Vector2i] = []
		for f: FighterState in [a, b]:
			var angle := _axis_angle(f.facing) & 0xFFF
			fronts.append(Vector2i(Fx.trunc12(FightMath.cos12(angle, t) * FRONT_REACH),
				Fx.trunc12(FightMath.sin12(angle, t) * FRONT_REACH)))
		var gx := Fx.w32(b.root_x + fronts[1].x - (a.root_x + fronts[0].x))
		var gz := Fx.w32(b.root_z + fronts[1].y - (a.root_z + fronts[0].y))
		if absi(gx) < FRONT_NEAR and absi(gz) < FRONT_NEAR \
				and Fx.w32(Fx.w32((b.pos_x - a.pos_x) * gx) + Fx.w32((b.pos_z - a.pos_z) * gz)) < 0:
			charging = true
			if overlap < CHARGE_OVERLAP:
				overlap = CHARGE_OVERLAP
	if overlap <= 0:
		return
	var moved := PackedInt32Array()
	for f: FighterState in [a, b]:
		var prev := fight.prev_roots[f.index]
		var dx := Fx.s16(f.root_x - (prev[0] & 0xFFFF))
		var dy := Fx.s16(f.root_y - (prev[1] & 0xFFFF))
		var dz := Fx.s16(f.root_z - (prev[2] & 0xFFFF))
		moved.append(FightMath.sqrt_table(Fx.w32(dx * dx + dy * dy + dz * dz), t) & 0xFFFF)
	var toward := CameraMath.atan2_units4096(Fx.w32(b.root_x - a.root_x), Fx.w32(b.root_z - a.root_z), t.camera)
	var axes := PackedInt32Array()
	for k in 2:
		var f: FighterState = a if k == 0 else b
		var target := toward if k == 0 else Fx.s16(toward + 0x800)
		var angle := _axis_angle(f.facing)
		var off := (angle - target) & 0xFFF
		if off > 0x7FF:
			off = 0x1000 - off
		if off > 0x400:
			angle = 0xC00 - Fx.div_trunc(Fx.s16(f.facing), 16)
		axes.append(angle & 0xFFF)
	var d1 := moved[0]
	var d2 := moved[1]
	var w1 := d1
	var w2 := d2
	if d1 == 0 and d2 == 0:
		w1 = 1
		w2 = 1
	var total := w1 + w2
	var share_a := Fx.div_trunc(Fx.w32(overlap * w1), total)
	var share_b := Fx.div_trunc(Fx.w32(overlap * w2), total)
	var cos0 := FightMath.cos12(axes[0], t)
	var cos1 := FightMath.cos12(axes[1], t)
	var sin0 := FightMath.sin12(axes[0], t)
	var sin1 := FightMath.sin12(axes[1], t)
	var ax := a.root_x + Fx.trunc12(cos1 * d2) - Fx.trunc12(cos0 * share_a)
	var az := a.root_z + Fx.trunc12(sin1 * d2) - Fx.trunc12(sin0 * share_a)
	var bx := b.root_x + Fx.trunc12(cos0 * d1) - Fx.trunc12(cos1 * share_b)
	var bz := b.root_z + Fx.trunc12(sin0 * d1) - Fx.trunc12(sin1 * share_b)
	for k in 2:
		var f: FighterState = a if k == 0 else b
		var px := Fx.w32((ax if k == 0 else bx) - f.root_x)
		var pz := Fx.w32((az if k == 0 else bz) - f.root_z)
		f.body_push_x = px if charging else px >> 1
		f.body_push_z = pz if charging else pz >> 1
		f.body_push_y = 0


# ---- hits -------------------------------------------------------------------------------------

## HitClearSlots (0x800442A0).
static func clear_hit_slots(f: FighterState) -> void:
	f.contact = 0
	f.whiffed = 0
	f.got_hit = 0
	f.hit_freeze_in = 0
	f.forced_hit_in = 0
	for s in f.hit_slots:
		s.clear()


## HitTest (0x80044304). A forced hit (Tekken Force) lands on a CPU defender it touches, at the
## defender's root, without the segment test.
func hit_test(attacker: FighterState, defender: FighterState, events: SimEvents) -> void:
	var slot: HitSlot = null
	for s in defender.hit_slots:
		if s.used == 0:
			slot = s
	var done := defender.index
	if slot != null and attacker.invulnerable == 0 and defender.invulnerable == 0 and attacker.active != 0 \
			and defender.active != 0 and attacker.hit_done[done] == 0:
		var pose := defender.pose_move
		var skip := attacker.attack == LOW_ATTACK and defender.state_class == JUMP_CLASS \
			and ((pose.air_first <= defender.pose_frame and defender.pose_frame <= pose.air_last - 5) or defender.in_air != 0)
		if not skip and not ((fight.mode == GameMode.BALL or fight.mode == GameMode.FORCE) and defender.in_throw != 0):
			var level := attacker.attack | (1 if defender.step_kind == 2 else 0)
			var hit := false
			if attacker.forced_hit == 0 or defender.is_cpu == 0 or defender.body_contact_with[attacker.index] == 0:
				hit = _hit_segments(attacker, defender, slot)
			else:
				var a := PackedInt32Array([attacker.root_x, attacker.root_y, attacker.root_z])
				var d := PackedInt32Array([defender.root_x, defender.root_y, defender.root_z])
				for k in 3:
					slot.point[k] = d[k]
					slot.direction[k] = Fx.s16(Fx.w32(a[k] - d[k]) >> 1)
				hit = true
				events.add(SimEvents.Kind.SOUND, 0, FORCED_HIT_SOUND, 0)
			if hit and level & defender.state & StateBit.POSTURE:
				attacker.hit_done[done] = 1
				attacker.contact_this_move = 1
				attacker.contact = 1
				attacker.last_hit_target = defender.index
				defender.was_hit_this_move = 1
				defender.got_hit = 1
				defender.hit_freeze_in = attacker.pose_move.hit_freeze
				slot.used = 1
				slot.attacker = attacker.index
				defender.forced_hit_in = attacker.forced_hit
				if attacker.cur_slot == 0x898:
					defender.hit_freeze_in = 0x1E
				if attacker.damage != 0 or defender.in_air != 0:
					defender.hit_cooldown = 4
	if attacker.pose_move.active_last == attacker.pose_frame and attacker.contact_this_move == 0:
		attacker.whiffed = 1


## HitTestSegments (0x80047E54): the attacker's live segments against the defender's cylinders.
## Projectile descriptors (first joint ≥ 0x18) use the segments their owner's effect objects
## published this frame (fire, breath and gas clouds) instead.
func _hit_segments(attacker: FighterState, defender: FighterState, slot: HitSlot) -> bool:
	var d := AttackRecords.header(attacker.pose_move, t)
	var segments: Array = attacker.attack_segs
	var count := mini(attacker.active_segs, 4)
	if d[0] >= PROJECTILE_JOINT:
		segments = fight.effects.segments[mini(attacker.index, 1)]
		count = segments.size()
	for k in count:
		if defender.hit_cooldown != 0:
			return false
		var s: PackedInt32Array = segments[k]
		for z in 14:
			if FightMath.segment_hits_cylinder(s, defender.hurt_zones[z], fight.rules.fix_segment_hit_overflow):
				slot.zone = z
				for c in 3:
					slot.point[c] = s[3 + c]
					slot.direction[c] = Fx.s16(s[3 + c] - s[c])
				return true
	return false


## HitExtraDamage (0x80044C4C).
func _extra_damage(f: FighterState) -> int:
	var total := 0
	var own := f.extra_damage if f.extra_damage != 0 else f.damage
	if f.extra_kind == 2:
		total = own
	if f.extra_kind == 3:
		total -= own
	if f.throw_state < 0:
		var opp := fight.opponent(f)
		if opp.extra_kind == 1:
			total += opp.extra_damage if opp.extra_damage != 0 else opp.damage
	return total


## HitClassify (0x80044D24).
func _classify(defender: FighterState, attacker: FighterState, slot: HitSlot) -> void:
	if attacker.damage == 0:
		slot.no_damage = 1
		return
	var close := attacker.pose_move.close_reaction
	if close != 0 and (fight.fighter_distance & 0xFFFFFFFF) < (t.close_reactions[close][1] & 0xFFFFFFFF):
		slot.close = 1
	if (defender.guard & attacker.attack) == 0 or (defender.rel_angle & 0xFFFF) > 0x3FFF:
		slot.hit = 1
		var startup := defender.damage != 0 and defender.pose_frame < defender.pose_move.active_first
		if startup or defender.power_timer != 0 or attacker.power_timer != 0:
			slot.counter = 1
		if defender.in_air != 0 or defender.pose_move.state & StateBit.AIRBORNE:
			slot.airborne = 1
	else:
		slot.guarded = 1
		if fight.chip_damage != 0 or attacker.power_timer != 0:
			slot.chip = 1


## HitDamage (0x80044E70): the attacker's base damage into the slot and the hit's damage added.
func _damage(defender: FighterState, attacker: FighterState, slot: HitSlot) -> void:
	slot.base_damage = attacker.damage & 0xFFFF
	var base := Fx.s16(attacker.damage)
	var d := 0
	if slot.guarded != 0:
		d = Fx.s16(Fx.div_trunc(base, 10) + 2) if slot.chip != 0 else 0
	else:
		if slot.close != 0:
			d = base + Fx.div_trunc(base, 2)
		else:
			d = Fx.s16(Fx.div_trunc(base * FightMath.ZONE_PERCENT[slot.zone], 100))
		if slot.counter != 0:
			var e := Fx.div_trunc(absi(Fx.s16(defender.damage)) * 3, 10)
			if defender.power_timer == 0 and attacker.power_timer == 0:
				var w := defender.pose_move.active_first
				if w == 0 or w < defender.pose_frame:
					w = defender.pose_frame & 0xFFFF
				e = Fx.div_trunc(Fx.div_trunc(Fx.s16(e) * 3, 10) * defender.pose_frame, Fx.s16(w))
			d = e + Fx.div_trunc(Fx.s16(d) * 12, 10)
		d = Fx.s16(d)
		if slot.airborne != 0:
			d = Fx.s16(Fx.div_trunc(d * 80, 100)) if defender.juggle_count == 0 else Fx.s16(Fx.div_trunc(d, 2))
	slot.damage = Fx.s16(slot.damage + d)


## HitApply (0x80044634): classification, damage, the best slot, the reaction record and KO.
func hit_apply(f: FighterState, events: SimEvents) -> void:
	var opp := fight.opponent(f)
	var extra := _extra_damage(f)
	var total := 0
	for slot in f.hit_slots:
		if slot.used != 0:
			f.fixed_facing = 0
			opp = fight.fighters[slot.attacker]
			moves.relative_angles(f, opp)
			_classify(f, opp, slot)
			_damage(f, opp, slot)
			total += slot.damage
	if f.got_hit != 0:
		var best := 0
		var other := f.hit_slots[1]
		if other.used != 0:
			var a := f.hit_slots[0].score()
			var b := other.score()
			if a < b or (a == b and f.hit_slots[0].damage < other.damage):
				best = 1
		f.best_hit_slot = best
		var s := f.hit_slots[best]
		f.last_damage = absi(s.damage)
		f.close_hit = s.close
		f.guarded = s.guarded
		f.hit_clean = s.hit
		f.counter_hit = s.counter
		# Practice's COUNTER ATTACKS: every clean hit outside a reaction counts as a counter hit.
		if fight.mode == GameMode.PRACTICE and fight.counter_forced[f.index] != 0 and f.in_reaction == 0 and f.hit_clean != 0:
			f.counter_hit = 1
		f.last_attacker = s.attacker
		f.hit_dir_x = opp.atk_dir_x
		f.hit_dir_y = opp.atk_dir_y
		f.hit_dir_z = opp.atk_dir_z
		f.reaction_throw_slot = -1
		if fight.mode == GameMode.BALL and fight.ball.charged_hit():
			# Tekken Ball's charged hit (0x800B6B54, read past Ghidra's decompile): the reaction
			# of the ball's attacker, the third record.
			_set_reaction(f, fight.fighters[TekkenBall.THIRD].pose_move.reaction)
		elif f.forced_hit_in != 0:
			f.reaction = t.forced_reaction
		elif f.close_hit == 0:
			_set_reaction(f, opp.pose_move.reaction)
		else:
			_set_reaction(f, t.close_reactions[opp.pose_move.close_reaction][0] & 0xFFFF)
	var old := f.health
	if fight.no_damage == 0 and fight.practice == 0:
		f.health = Fx.w32(old - (extra + total) * 0x10000)
	if fight.mode == GameMode.BALL and opp.index != TekkenBall.THIRD:
		# Tekken Ball: only the ball (the third record) does damage.
		f.health = old
	if f.health < 0:
		f.health = 0
	if f.health_max < f.health:
		f.health = f.health_max
	if f.health == 0 and old != 0:
		f.ko = 1
	if f.ko != 0 and f.hit_slots[f.best_hit_slot].chip != 0:
		f.guarded = 0
		f.hit_clean = 1
	if f.got_hit != 0:
		_spawn_effect(f, f.hit_slots[f.best_hit_slot], Fx.s16(total), events)
	if f.ko != 0 and fight.ko_started == 0 and fight.mode != GameMode.FORCE:
		fight.replay.start_ko(opp)
		fight.ko_started = 1
	if fight.mode == GameMode.FORCE and f.is_cpu != 0:
		_force_score(f, extra)
	f.last_extra_damage = Fx.s16(extra)


## Tekken Force: the damage an enemy took from the player or a forced hit, and twice the extra
## damage, scored.
func _force_score(f: FighterState, extra: int) -> void:
	var score := 0
	if f.got_hit != 0:
		var player := fight.force.player()
		for slot in f.hit_slots:
			if slot.used != 0:
				var attacker := fight.fighters[slot.attacker]
				if attacker == player or attacker.forced_hit != 0:
					score += Fx.s16(slot.base_damage)
	if extra > 0:
		score += extra * 2
	if score != 0:
		fight.force.add_score(score)


## The reaction of a move's +0x32 word: a record below 0x1000, else a throw victim entry
## (only its first field, the victim's move slot, is meaningful).
func _set_reaction(f: FighterState, value: int) -> void:
	if value & 0xF000 == 0:
		f.reaction = t.reactions[value]
	else:
		var n := value & 0xFFF
		f.reaction = t.throw_victim_slots.slice(n, n + FightTables.REACTION_WORDS)
		f.reaction_throw_slot = n


func _spark_event(events: SimEvents, f: FighterState, slot: HitSlot, kind: int, damage: int, side: int) -> void:
	var e := events.add_at(SimEvents.Kind.HIT_SPARK, f.index, slot.point.duplicate(), kind, damage)
	e.c = side
	e.vector = slot.direction.duplicate()


## HitSpawnEffect (0x80044B78): the guard or hit flash and spark at the contact point.
func _spawn_effect(f: FighterState, slot: HitSlot, total: int, events: SimEvents) -> void:
	if slot.hit == 0 and f.ko == 0:
		if slot.guarded != 0:
			_spark_event(events, f, slot, 2, 0, slot.attacker)
			fight.replay.log_effect(3, 2, slot.point, slot.direction, 0)
		elif slot.no_damage != 0:
			_spark_event(events, f, slot, 1, 0, slot.attacker)
			fight.replay.log_effect(3, 1, slot.point, slot.direction, 0)
		return
	var damage := maxi(total, Fx.s16(slot.base_damage))
	# Tekken Ball flips the spark's side by the defender (the attacker may be the ball's record).
	var side := 1 - f.index if fight.mode == GameMode.BALL else slot.attacker
	_spark_event(events, f, slot, 0, damage, side)
	fight.replay.log_effect(3, 0, slot.point, slot.direction, 0)
	if damage >= EffectObjects.SPARK_DAMAGE:
		fight.replay.log_effect(side, 0, slot.point, slot.direction, 0)
	EffectObjects.hit_objects(fight, damage, f, side, slot.point, events)
