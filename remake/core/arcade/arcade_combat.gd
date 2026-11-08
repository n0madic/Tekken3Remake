class_name ArcadeCombat
extends Combat
## Between the arcade's two fighters: the attack segments live from the joints (FUN_80198A48,
## FUN_80198BF8), the body spheres (FUN_8019EF90), the push (FUN_8018B808) and the hits, which run for
## the pair at once and without slots (FUN_8018B91C, FUN_8018B47C, FUN_8018BB68). A defender's single
## hit record is its first HitSlot: point, direction, zone.

const SEGMENTS_PER_ROW := 2
const CLASS_JUMP := 12
const ANGLE_BEHIND := 0x3FFF
const CHIP_PER_DAMAGE := 0xA0000    ## 16.16 per 100 of damage
const CHIP_BASE := 0x20000
const STATE_DOWN_AIR := 0x400
const PROFILE_SHARED := 6           ## the first fighter's profile 6 holds for both

## (bank type, characters, joint, local point, target joint), run every frame.
const ARCADE_WEAPON_POINTS := [
	[BankType.YOSHIMITSU, [], 10, [100, -720, 0], 18], [BankType.YOSHIMITSU, [], 10, [100, -360, 0], 19],
	[BankType.OGRE, [Character.TRUE_OGRE, 0xF], 11, [100, -500, 0], 22],
	[BankType.OGRE, [Character.TRUE_OGRE, 0xF], 2, [800, 0, 600], 23],
]

var effect_objects: ArcadeEffectObjects


func _set_point(seg: PackedInt32Array, at: int, f: FighterState, joint: int) -> void:
	var j := _segment_joint(f, joint)
	if j == NO_SEGMENT:
		return
	var p := f.body.joints[j].t
	seg[at] = p[0]
	seg[at + 1] = p[1]
	seg[at + 2] = p[2]


## FUN_80198A48: a segment without a joint of its own starts where its end joint was last frame.
func save_segment_starts(f: FighterState) -> void:
	var count := f.attack_seg_count
	if count != 1 and count != SEGMENTS_PER_ROW:
		return
	var joints := f.pose_move.attack_joints
	for k in count:
		if (joints >> (8 * (2 * k + 1))) & 0xFF == 0:
			_set_point(f.attack_segs[k], 0, f, (joints >> (16 * k)) & 0xFF)


## FUN_80198BF8.
func shapes(f: FighterState) -> void:
	var joints := f.body.joints
	for w: Array in ARCADE_WEAPON_POINTS:
		var characters: Array = w[1]
		if f.bank_type != w[0] or (not characters.is_empty() and not f.char_id in characters):
			continue
		var joint: JointFrame = joints[w[2]]
		var point: Array = w[3]
		var p := PackedInt32Array(point)
		var m := joint.rot
		var out := PackedInt32Array([0, 0, 0])
		for r in 3:
			out[r] = Fx.w32(Fx.w32((m[3 * r] * p[0] + m[3 * r + 1] * p[1] + m[3 * r + 2] * p[2]) >> 12) + joint.t[r])
		var target: int = w[4]
		joints[target] = JointFrame.new(joints[target].rot, out)
	_body_shapes(f, joints)
	if f.attack_seg_count != 0:
		var row := f.pose_move.attack_joints
		for k in SEGMENTS_PER_ROW:
			var seg := f.attack_segs[k]
			_set_point(seg, 3, f, (row >> (16 * k)) & 0xFF)
			var start := (row >> (8 * (2 * k + 1))) & 0xFF
			if start != 0:
				_set_point(seg, 0, f, start)


## FUN_8019EF90.
func sphere_profiles(a: FighterState, b: FighterState) -> void:
	var first := a.pose_move.body_profile
	var second := PROFILE_SHARED if first == PROFILE_SHARED else b.pose_move.body_profile
	_apply_profile(a, first)
	_apply_profile(b, second)


## FUN_8019F00C: the numbers of the profiles differ from the PlayStation's.
func _profile_radii(f: FighterState, profile: int) -> PackedInt32Array:
	var radii := t.body_radii[f.char_id]
	var r := PackedInt32Array()
	r.resize(radii.size())
	match profile & 0xF:
		0:
			return super(f, profile)
		1:
			for k in r.size():
				r[k] = radii[k] if k == 0 or k == 3 else 1
		2:
			r.fill(1)
		3:
			for k in r.size():
				r[k] = radii[k] >> 1
		4:
			r.fill(0)
		5, 6:
			for k in r.size():
				r[k] = radii[k] >> 1 if k == 0 or k == 3 else 1
		7:
			for k in r.size():
				r[k] = radii[0] + 0x3C if k == 0 else 1 if k >= 4 else radii[k]
		8:
			for k in r.size():
				r[k] = radii[k] + 100
		_:
			return radii
	return r


## FUN_8018B808: no pair in a throw is pushed.
func separate(a: FighterState, b: FighterState) -> void:
	if a.throw_state != 0 or b.throw_state != 0:
		return
	_overlap_solve(a, b)
	for f: FighterState in [a, b]:
		f.pos_x = Fx.w32(f.pos_x + f.body_push_x)
		f.pos_y = Fx.w32(f.pos_y + f.body_push_y)
		f.pos_z = Fx.w32(f.pos_z + f.body_push_z)
		f.root_x = Fx.w32(f.root_x + f.body_push_x)
		f.root_y = Fx.w32(f.root_y + f.body_push_y)
		f.root_z = Fx.w32(f.root_z + f.body_push_z)


func _half_push(v: int) -> int:
	return Fx.div_trunc(v, 2)


func _is_projectile(attacker: FighterState) -> bool:
	var first := (attacker.pose_move.attack_joints & 0xFF) - PROJECTILE_JOINT
	return first >= 0 and first < 2


## FUN_8018B91C: the geometry of both directions before any of their outcomes.
func test_hits(a: FighterState, b: FighterState) -> void:
	for f: FighterState in [a, b]:
		f.got_hit = 0
		f.contact = 0
		f.whiffed = 0
		f.hit_freeze_in = 0
	var a_hits := _hit_segments(a, b, b.hit_slots[0])
	var b_hits := _hit_segments(b, a, a.hit_slots[0])
	_outcome(a, b, a_hits)
	_outcome(b, a, b_hits)
	for f: FighterState in [a, b]:
		if f.pose_move.active_last == f.pose_frame and f.contact_this_move == 0:
			f.whiffed = 1


func _outcome(attacker: FighterState, defender: FighterState, touched: bool) -> void:
	if attacker.attack == LOW_ATTACK and defender.state_class == CLASS_JUMP:
		var row := defender.pose_move
		var in_window := row.air_first <= defender.pose_frame and defender.pose_frame <= row.air_last - 5
		if in_window or defender.in_air != 0:
			return
	var level := attacker.attack | (1 if defender.step_kind == 2 else 0)
	if attacker.active == 0 or defender.active == 0 or attacker.hit_done[0] != 0 or not touched:
		return
	if level & defender.state & StateBit.POSTURE == 0:
		return
	if attacker.damage == 0 and (defender.health == 0 or defender.about_to_hit != 0):
		return
	attacker.hit_done[0] = 1
	attacker.contact_this_move = 1
	attacker.contact = 1
	defender.was_hit_this_move = 1
	defender.got_hit = 1
	defender.hit_freeze_in = attacker.pose_move.hit_freeze
	if attacker.damage != 0 or defender.in_air != 0:
		defender.hit_cooldown = 4


## FUN_8018B47C.
static func attack_direction(f: FighterState, opp: FighterState) -> void:
	attack_velocity(f)
	if f.contact != 0:
		opp.hit_dir_x = f.atk_dir_x
		opp.hit_dir_y = f.atk_dir_y
		opp.hit_dir_z = f.atk_dir_z


## FUN_8018BB68.
func apply_hits(a: FighterState, b: FighterState, events: SimEvents) -> void:
	for f: FighterState in [a, b]:
		f.counter_hit = 0
		f.close_hit = 0
		f.ko = 0
		f.last_damage = 0
		f.guarded = 0
		f.hit_clean = 0
	# The stale chip of the other fighter is what a guard without chip damage shows at 0 health.
	var chip := _apply(a, b, 0, events)
	_apply(b, a, chip, events)
	for pair: Array in [[a, b], [b, a]]:
		var f: FighterState = pair[0]
		var opp: FighterState = pair[1]
		if f.health == 0 and fight.no_damage == 0:
			f.ko = 1
			if fight.ko_started == 0:
				fight.replay.start_ko(opp)
				fight.ko_started = 1


func _extra(value: int, fallback: int) -> int:
	return value if value != 0 else fallback


func _apply(f: FighterState, o: FighterState, chip_in: int, events: SimEvents) -> int:
	var chip := chip_in
	var old := f.health
	if o.extra_kind == 1:
		var v := _extra(o.extra_damage, o.damage)
		f.health = Fx.w32(f.health - v * 0x10000)
		f.last_damage = Fx.s16(f.last_damage + v)
	if f.extra_kind == 2:
		var v := _extra(f.extra_damage, f.damage)
		f.health = Fx.w32(f.health - v * 0x10000)
		f.last_damage = Fx.s16(f.last_damage + v)
	if f.extra_kind == 3:
		f.health = Fx.w32(f.health + _extra(f.extra_damage, o.damage) * 0x10000)
	if f.got_hit != 0:
		chip = _hit(f, o, chip, events)
	if fight.no_damage != 0:
		f.health = old
	f.health = mini(maxi(f.health, 0), f.health_max)
	return chip


func _hit(f: FighterState, o: FighterState, chip_in: int, events: SimEvents) -> int:
	var chip := chip_in
	var slot := f.hit_slots[0]
	var size := absi(Fx.s16(o.damage))
	var shown := Fx.s16(size)
	var close := o.pose_move.close_reaction
	if close != 0 and (fight.fighter_distance & 0xFFFFFFFF) < (t.close_reactions[close][1] & 0xFFFFFFFF):
		f.close_hit = 1
		f.reaction = t.reactions[t.close_reactions[close][0] & 0xFFFF]
	if shown < 1:
		if shown == 0:
			f.guarded = 1
			_spark_event(events, f, slot, 1, 0, 1 - f.index)
		return chip
	if f.guard & o.attack == 0 or f.rel_angle > ANGLE_BEHIND:
		var d := _landed(f, o, slot, size, shown)
		f.health = Fx.w32(f.health - d * 0x10000)
		var effect := maxi(shown, Fx.s16(d))
		_spark_event(events, f, slot, 0, effect, 1 - f.index)
		f.hit_clean = 1
		f.last_damage = Fx.s16(Fx.s16(d) + f.last_damage)
		return chip
	if fight.chip_damage != 0 or o.power_timer != 0:
		f.guarded = 1
		chip = Fx.w32(Fx.div_trunc(Fx.w32(Fx.s16(o.damage) * CHIP_PER_DAMAGE), 100) + CHIP_BASE)
		f.health = Fx.w32(f.health - chip)
	if f.health < 1:
		_spark_event(events, f, slot, 0, chip >> 16, 1 - f.index)
		f.hit_clean = 1
	else:
		_spark_event(events, f, slot, 2, 0, 1 - f.index)
		f.guarded = 1
	return chip


## FUN_801AD114 for a hit that lands (kind 0), FUN_801AD0B8 for the others: `side` is the attacker.
func _spark_event(events: SimEvents, f: FighterState, slot: HitSlot, kind: int, damage: int, side: int) -> void:
	super(events, f, slot, kind, damage, side)
	fight.replay.log_effect(EffectLog.SYSTEM_SET, kind, slot.point, slot.direction, EffectLog.FLIPBOOK)
	if kind != 0:
		return
	if damage >= ArcadeEffectObjects.BIG_HIT:
		fight.replay.log_effect(side, 0, slot.point, slot.direction, EffectLog.FLIPBOOK)
	effect_objects.hit_objects(damage, side, slot.point)


## The damage of a hit that lands: the zone or the close hit, the counter's bonus, the air's scale.
func _landed(f: FighterState, o: FighterState, slot: HitSlot, size: int, shown: int) -> int:
	var d := 0
	if f.close_hit == 0:
		d = Fx.s16(Fx.div_trunc(shown * FightMath.ZONE_PERCENT[slot.zone], 100))
	else:
		d = size + Fx.div_trunc(Fx.s16(size), 2)
	var row := f.pose_move
	var startup := f.damage != 0 and f.pose_frame < row.active_first
	if startup or f.power_timer != 0 or o.power_timer != 0:
		f.counter_hit = 1
		var own := absi(Fx.s16(f.damage))
		var e := 0
		if o.power_timer == 0 and f.power_timer == 0:
			var w := row.active_first
			if w == 0 or w < f.pose_frame:
				w = f.pose_frame & 0xFFFF
			e = Fx.div_trunc(Fx.w32(Fx.div_trunc(own * 3, 10) * f.pose_frame), Fx.s16(w))
		else:
			e = Fx.div_trunc(Fx.s16(d) * 3, 10)
		d = e + Fx.div_trunc(Fx.s16(d) * 12, 10)
	if f.in_air != 0 or row.state & STATE_DOWN_AIR:
		if f.juggle_count == 0:
			d = Fx.div_trunc(Fx.s16(d) * 0x50, 100)
		else:
			d = Fx.div_trunc(Fx.s16(d), 2)
	return d
