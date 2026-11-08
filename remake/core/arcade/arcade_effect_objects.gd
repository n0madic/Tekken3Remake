class_name ArcadeEffectObjects
extends RefCounted
## The arcade's effect objects (docs/research/arcade/audio-and-effects.md#4-effect-objects): sparks, power
## glows, fire breath, smoke, floor fire, breath clouds and burning bodies. The same machine as the
## PlayStation's `EffectObjects`, with other counts and fixed chances instead of the live count's. It is
## simulation state: the objects draw on the shared `rand()`, which the CPU's decisions read, and the
## fire and the clouds publish the hit segments of their owner's move.
##
## TODO: the update functions below (`_spark`, `_spray`, `_rise`, `_ember`, `_smoke`, `_floor_fire`,
## `_cloud` ...) are near copies of `EffectObjects`' (~600 lines); only `finish`, `move`, `save_previous`
## and `rand2` are shared. They differ in being instance methods over `tables` instead of statics over
## `fight`, in the look lines (`_show` flipbooks against clut and uv_table) and in the tables they read.
## Merging them takes the PlayStation's statics turned into instance methods with a hook for the look, and
## a trace that reaches the object types `tests/support/effect_pool_hashes.gd` lists as uncovered.
##
## The pool is `fight.effects`, the objects `EffectObjects.Obj`. FUN_801DC990 walks the live ones in
## allocation order; it takes the next link before each update, so an object spawned while the last one
## updates waits for the next frame, otherwise it updates in the same walk. The presentation draws an
## object from `model`, and `uv` as a frame of the flipbook `uv_table` (`Book`): the arcade fades by frames,
## not by CLUT ramps.

const CAPACITY := 120
const VISIBLE := 0x40
const FOLLOWS := 0x20               ## glow and rise (FUN_801DC990 draws them with the fighter's blend)
const SEGMENT := 0x04
const OWNER_0 := 0x10
const OWNER_1 := 0x08
const MARK := 0x80                  ## allocated (FUN_801DD110 frees marked objects only)
const FLOOR := -0xD8
const GLOW_JOINTS: Array[int] = [6, 10, 0xE, 0x11, 0x8006, 0x800A, 0x800E, 0x8011]
const GLOW_SIDE := 0x8000
const GLOW_JOINT_BIT := 0x80000000
const HANDS_GLOW := 0x440
const FIRE_BREATH := 0x18
const BREATH_CLOUD := 0x19
const HEAD_JOINT := 2
const BIG_HIT := 0x15
const SPRAY_COUNT := 30
const SPARK_COUNT := 12
const LIGHT_FIRE := 0
const LIGHT_GLOW := 1
const SMOKE_PITCH := 0x400
const END_PHASE_FIRST := 3          ## camera phases in which FUN_801DC990 empties the pool once
const END_PHASE_LAST := 7
## `EffectLog.Entry.index` of the objects a hit starts: their playback in FUN_801ACCE4.
const LOG_SPARKS := 0x80
const LOG_SPRAY := 0x81
const LOG_BURN := 0x82
const LOG_POWER_SPARKS := 0x83
const LOG_POWER_SPRAY := 0x84

enum Type { FINISHED, SPARK, SPRAY, GLOW, RISE, EMBER, FIREBALL, SMOKE, FLOOR_FIRE = 9, CLOUD, BURN, POWER_SPARK,
	POWER_SPRAY }
## The flipbooks: their UV tables in the program.
enum Book {
	MODEL,                          ## the model's own sprite
	SPARK,                          ## 0x8017C5F8
	POWER_SPARK,                    ## 0x8017C914
	GLOW,                           ## 0x8017C65C
	RISE,                           ## 0x8017C6C4
	EMBER,                          ## 0x8017C704
	FIRE_GROW,                      ## 0x8017C7A4
	FIRE_LOOP,                      ## 0x8017C7B4
	FIRE_BURST,                     ## 0x8017C7C4
	FLOOR_FIRE,                     ## 0x8017C7FC
	FLOOR_FADE,                     ## 0x8017C81C
	CLOUD,                          ## 0x8017C87C
}

var fight: FightState
var tables: ArcadeEffectTables


func _init(fight_state: FightState, effect_tables: ArcadeEffectTables) -> void:
	fight = fight_state
	tables = effect_tables


# ==== the pool ====================================================================================

## FUN_801DD0B0: a new object at the end of the walk, null when all are used.
func alloc(type: int) -> EffectObjects.Obj:
	var objects := fight.effects.objects
	if objects.size() >= CAPACITY:
		return null
	var o := EffectObjects.Obj.new()
	o.type = type
	o.flags = MARK
	objects.append(o)
	return o


## FUN_801DC094.
func round_start() -> void:
	var pool := fight.effects
	pool.objects.clear()
	pool.replay_glows = 0
	pool.end_cleared = 0
	pool.segments[0].clear()
	pool.segments[1].clear()
	pool.glow_mask = PackedInt32Array([0, 0])
	for f: FighterState in fight.fighters:
		f.keep_light = 0
	_spawn_glows()


func _spawn_glows() -> void:
	for joint: int in GLOW_JOINTS:
		var o := alloc(Type.GLOW)
		if o != null:
			o.a = joint


## FUN_801DC990. `enabled` is the frame's 0x8021FB38: without it the objects only draw.
func update(enabled: bool) -> void:
	var pool := fight.effects
	pool.segments[0].clear()
	pool.segments[1].clear()
	if enabled:
		for f: FighterState in fight.fighters:
			f.keep_light = 0
		pool.counter += 1
		_glow_masks()
	if pool.replay_glows == 0 and fight.replay_playing != 0:
		pool.objects.clear()
		_spawn_glows()
		pool.replay_glows += 1
	if pool.end_cleared == 0 and fight.camera_phase >= END_PHASE_FIRST and fight.camera_phase <= END_PHASE_LAST:
		pool.objects.clear()
		pool.end_cleared += 1
	if not enabled:
		pool.live = pool.objects.size()
		return
	var objects := pool.objects
	var i := 0
	while i < objects.size():
		var o := objects[i]
		var last := i == objects.size() - 1
		_update_object(o)
		if o.flags & SEGMENT:
			pool.segments[0 if o.flags & OWNER_0 else 1].append(PackedInt32Array([o.px, o.py, o.pz, o.x, o.y, o.z]))
		if o.gone:
			objects.remove_at(i)
		else:
			i += 1
		if last:
			break
	pool.live = objects.size()


func _update_object(o: EffectObjects.Obj) -> void:
	match o.type:
		Type.FINISHED:
			_finished(o)
		Type.SPARK:
			_spark(o, false)
		Type.SPRAY:
			_spray(o, false)
		Type.GLOW:
			_glow(o)
		Type.RISE:
			_rise(o)
		Type.EMBER:
			_ember(o)
		Type.FIREBALL:
			_fireball(o)
		Type.SMOKE:
			_smoke(o)
		Type.FLOOR_FIRE:
			_floor_fire(o)
		Type.CLOUD:
			_cloud(o)
		Type.BURN:
			_burn(o)
		Type.POWER_SPARK:
			_spark(o, true)
		Type.POWER_SPRAY:
			_spray(o, true)


# ==== spawns from the fight =======================================================================

## FUN_801DC758: the fire breath and the breath cloud start on every frame of their move's active window.
func descriptor_spawn(f: FighterState, enabled: bool) -> void:
	if not enabled or fight.effects.end_cleared != 0:
		return
	var move := f.pose_move
	var code := move.attack_joints & 0xFF
	if code != FIRE_BREATH and code != BREATH_CLOUD:
		return
	if f.pose_frame < move.active_first or move.active_last < f.pose_frame:
		return
	if code == FIRE_BREATH:
		var start := _emit(f, Type.FIREBALL, tables.breath_offsets[f.index])
		fight.effects.lights.append(PackedInt32Array([start[0], start[1], start[2], LIGHT_FIRE]))
	else:
		_emit(f, Type.CLOUD, tables.cloud_offsets)


## An object at the first of two offsets from the head, aimed at the second; returns that first point.
func _emit(f: FighterState, type: int, offsets: Array) -> PackedInt32Array:
	var head := f.body.joints[HEAD_JOINT]
	var points: Array[PackedInt32Array] = []
	for k in 2:
		var v: PackedInt32Array = offsets[k]
		var m := Gte.apply(head.rot, v[0], v[1], v[2])
		points.append(PackedInt32Array([Fx.w32(m[0] + head.t[0]), Fx.w32(m[1] + head.t[1]), Fx.w32(m[2] + head.t[2])]))
	var p := points[0]
	var q := points[1]
	var o := alloc(type)
	if o != null:
		o.flags |= OWNER_0 if f.index == 0 else OWNER_1
		o.x = p[0]
		o.y = p[1]
		o.z = p[2]
		var d := direction(q[0] - p[0], q[1] - p[1], q[2] - p[2])
		o.pitch = d.x
		o.yaw = d.y
	return p


## FUN_801AD114's objects of a hit that lands: fire sets the defender alight; a big hit sprays sparks along
## the attacker's first segment. FUN_801AD114 is the attacker's.
func hit_objects(damage: int, attacker_index: int, point: PackedInt32Array) -> void:
	var attacker := fight.fighters[attacker_index]
	var code := attacker.pose_move.attack_joints & 0xFF
	if code == BREATH_CLOUD:
		return
	if code == FIRE_BREATH:
		_burn_spawn(attacker_index)
		fight.replay.log_effect(attacker_index, LOG_BURN, point, PackedInt32Array([0, 0, 0]), EffectLog.FLIPBOOK)
		return
	if damage < BIG_HIT:
		return
	var seg := attacker.attack_segs[0]
	var d := direction(seg[3] - seg[0], seg[4] - seg[1], seg[5] - seg[2])
	var logged := PackedInt32Array([d.x, d.y, damage])
	if attacker.power_timer != 0:
		_spawn_logged(LOG_POWER_SPRAY, attacker_index, point, logged)
		_spawn_logged(LOG_POWER_SPARKS, attacker_index, point, logged)
	else:
		_spawn_logged(LOG_SPRAY, attacker_index, point, logged)
		_spawn_logged(LOG_SPARKS, attacker_index, point, logged)


func _spawn_logged(index: int, attacker_index: int, point: PackedInt32Array, logged: PackedInt32Array) -> void:
	_spawn_hit_objects(index, point, Vector2i(logged[0], logged[1]))
	fight.replay.log_effect(attacker_index, index, point, logged, EffectLog.FLIPBOOK)


func _spawn_hit_objects(index: int, point: PackedInt32Array, d: Vector2i) -> void:
	match index:
		LOG_SPARKS:
			_spray_spawn(Type.SPARK, SPARK_COUNT, point, d)
		LOG_SPRAY:
			_spray_spawn(Type.SPRAY, SPRAY_COUNT, point, d)
		LOG_POWER_SPARKS:
			_spray_spawn(Type.POWER_SPARK, SPARK_COUNT, point, d)
		LOG_POWER_SPRAY:
			_spray_spawn(Type.POWER_SPRAY, SPRAY_COUNT, point, d)


## FUN_801AE6B4, FUN_801ADD18: the replay starts the frame's logged effects again; the objects draw on
## the fight's `rand` as they did the first time. FUN_801ACCE4's cases are the objects.
func play_log(events: SimEvents, view: CameraView) -> void:
	for e: EffectLog.Entry in fight.replay.log_take():
		if EffectObjects.play_logged_flipbook(e, events, view):
			continue
		if e.index == LOG_BURN:
			_burn_spawn(e.set)
		else:
			_spawn_hit_objects(e.index, e.point, Vector2i(e.direction[0], e.direction[1]))


## FUN_801DC1CC, FUN_801DC118, FUN_801DC328, FUN_801DC274.
func _spray_spawn(type: int, count: int, point: PackedInt32Array, d: Vector2i) -> void:
	for i in count:
		var o := alloc(type)
		if o == null:
			return
		o.x = point[0]
		o.y = point[1]
		o.z = point[2]
		o.pitch = d.x
		o.yaw = d.y


## FUN_801DC6C0: `c` names the attacker, the flames follow the other fighter's joints.
func _burn_spawn(attacker_index: int) -> void:
	for joint: int in tables.burn_joints:
		var o := alloc(Type.BURN)
		if o == null:
			return
		o.c = attacker_index
		o.d = joint


## FUN_801DC81C: the joints that glow this frame, while the power timer runs.
func _glow_masks() -> void:
	var pool := fight.effects
	for p in 2:
		pool.glow_mask[p] = 0
		var f := fight.fighters[p]
		if fight.replay.power_timer(f) == 0:
			continue
		var move := f.pose_move
		if move.attack_joints == 0:
			pool.glow_mask[p] |= HANDS_GLOW
		elif f.pose_frame <= move.active_last:
			for k in 4:
				var code := (move.attack_joints >> (8 * k)) & 0xFF
				var joint := tables.glow_joints[code] if code < tables.glow_joints.size() else 0
				if joint != 0:
					pool.glow_mask[p] |= (1 << (joint & 0x1F)) | GLOW_JOINT_BIT


# ==== helpers =====================================================================================

## FUN_801DAF50: (pitch, yaw) of a vector.
func direction(dx: int, dy: int, dz: int) -> Vector2i:
	var yaw := _angle(dx, dz)
	var pitch := _angle(dy, _flat_length(dx, dz, yaw))
	return Vector2i(pitch, yaw)


## FUN_801DAE68: the 4096-unit angle of (a, b). Components this far apart never reach 0x8000, the division's
## overflow, in the game's world.
func _angle(a_in: int, b_in: int) -> int:
	var octant := 0
	var a := a_in
	var b := b_in
	if a < 0:
		octant = 4
		a = -a
	if b < 0:
		octant |= 2
		b = -b
	var low := a
	var high := b
	if b < a:
		octant |= 1
		low = b
		high = a
	var v := 0
	if high != 0:
		var q := Fx.div_trunc(Fx.w32(low << 16), high)
		v = tables.atan_table[q >> 4] if q < 0x10000 else 0x2000
	if tables.angle_sign[octant] != 0:
		v = -v
	return (-(v + tables.angle_base[octant]) >> 4) & 0xFFF


## FUN_801DAFC4: the horizontal length from the larger component and the yaw.
func _flat_length(x: int, z: int, yaw: int) -> int:
	var n := x
	var s := 0
	if absi(z) < absi(x):
		s = tables.sin_table[yaw]
	else:
		s = tables.cos_table[yaw]
		n = z
	if s == 0:
		s = 1
	return absi(Fx.div_trunc(Fx.w32(n << 16), s) >> 1)


## FUN_801DB180: the velocity (16.16) of the direction and the speed.
func _aim(o: EffectObjects.Obj) -> void:
	var p := -o.pitch & 0xFFF
	var w := -o.yaw & 0xFFF
	var speed := Fx.s16(o.speed)
	o.vy = Fx.w32((speed * tables.sin_table[p]) >> 3)
	var h := (speed * tables.cos_table[p]) >> 15
	o.vx = Fx.w32((h * tables.sin_table[w]) >> 3)
	o.vz = Fx.w32((h * tables.cos_table[w]) >> 3)


## FUN_801DB110: the horizontal velocity of the yaw and the speed.
func _aim_flat(o: EffectObjects.Obj) -> void:
	var w := -o.yaw & 0xFFF
	var speed := Fx.s16(o.speed)
	o.vx = Fx.w32((speed * tables.sin_table[w]) >> 3)
	o.vz = Fx.w32((speed * tables.cos_table[w]) >> 3)


## FUN_801E0B3C: the owner's move no longer runs `code`, or is before its active window.
func _owner_ended(o: EffectObjects.Obj, code: int) -> bool:
	var f := fight.fighters[0] if o.flags & OWNER_0 else fight.fighters[1]
	var move := f.pose_move
	if move.attack_joints & 0xFF != code:
		return true
	return f.pose_frame < move.active_first


func _spawn_at(type: int, o: EffectObjects.Obj) -> EffectObjects.Obj:
	var s := alloc(type)
	if s != null:
		s.x = o.x
		s.y = o.y
		s.z = o.z
	return s


func _spawn_smoke(o: EffectObjects.Obj, pitch: int, yaw: int) -> void:
	var s := _spawn_at(Type.SMOKE, o)
	if s != null:
		s.pitch = pitch
		s.yaw = yaw


func _light(o: EffectObjects.Obj, kind: int) -> void:
	fight.effects.lights.append(PackedInt32Array([o.x, o.y, o.z, kind]))


static func _show(o: EffectObjects.Obj, book: Book, frame: int) -> void:
	o.uv_table = book as int as EffectObjects.UvTable
	o.uv = frame


# ==== types =======================================================================================

## Type 0 (FUN_801DD17C): a finished object, freed on its second update.
static func _finished(o: EffectObjects.Obj) -> void:
	if o.state == 0:
		o.a = 2
		o.state += 1
	elif o.state != 1:
		return
	o.a -= 1
	if o.a < 1 and o.flags & MARK:
		o.gone = true


## The frame of a spark's life: 32 frames over `b` updates.
static func _spark_frame(o: EffectObjects.Obj, power: bool) -> void:
	_show(o, Book.POWER_SPARK if power else Book.SPARK, Fx.div_trunc(o.a * 0x10, maxi(o.b >> 1, 1)))


## Types 1 and 12 (FUN_801DD21C, FUN_801E02BC): decelerating sparks along the hit direction ± 60°.
func _spark(o: EffectObjects.Obj, power: bool) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE
		o.model = EffectObjects.Model.POWER_SPARK if power else EffectObjects.Model.SPARK
		var r := EffectObjects.rand2(fight)
		var u := r.y
		var pitch_step := ((r.x & 0x7FF) - 0x3FF) * 2
		var yaw_step := (((u >> 2) & 0x7FF) - 0x3FF) * 2
		o.b = ((u >> 4) & 0x1F) + 10
		o.c = (u >> 6) & 0x1FF
		o.a = 0
		o.d = ((u >> 8) & 0x1FF) + 0x680
		o.pitch = Fx.s16(o.pitch + Fx.div_trunc(pitch_step, 3))
		o.yaw = Fx.s16(o.yaw + Fx.div_trunc(yaw_step, 3))
	elif o.state != 1:
		return
	o.a += 1
	if o.a < o.b:
		_spark_frame(o, power)
		var ease := Fx.div_trunc(tables.cos_table[Fx.div_trunc(o.a * 0x7FF, o.b) & 0xFFF] + 0x7FFF, 2)
		o.speed = Fx.s16(((o.d - o.c) * ease >> 15) + o.c)
		_aim(o)
		EffectObjects.move(o)
		if o.y < 0:
			return
	EffectObjects.finish(o)


## Types 2 and 13 (FUN_801DD67C, FUN_801E071C): sparks sprayed from a jittered start at a constant speed.
func _spray(o: EffectObjects.Obj, power: bool) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE
		o.model = EffectObjects.Model.POWER_SPARK if power else EffectObjects.Model.SPARK
		var r := EffectObjects.rand2(fight)
		var u := r.y
		o.b = ((u >> 10) & 0x1F) + 0x14
		o.a = 0
		o.x = Fx.w32(o.x - 0x7F + (r.x & 0xFF))
		o.y = Fx.w32(o.y - 0x7F + ((u >> 2) & 0xFF))
		o.z = Fx.w32(o.z - 0x7F + ((u >> 4) & 0xFF))
		o.pitch = Fx.s16(o.pitch - 0x3F + ((u >> 6) & 0x7F))
		o.yaw = Fx.s16(o.yaw - 0x3F + ((u >> 8) & 0x7F))
		o.speed = Fx.s16((((u >> 12) & 0x7FF) * 5) >> 2)
		_aim(o)
		o.x = Fx.w32(o.x + (o.vx >> 13))
		o.y = Fx.w32(o.y + (o.vy >> 13))
		o.z = Fx.w32(o.z + (o.vz >> 13))
	elif o.state != 1:
		return
	o.a += 1
	if o.a < o.b:
		_spark_frame(o, power)
		EffectObjects.move(o)
		if o.y < 0:
			return
	EffectObjects.finish(o)


## Type 3 (FUN_801DDA9C): the power glow on one joint (+0x8000: the second fighter's), shown while the
## masks set its bit, with rising particles.
func _glow(o: EffectObjects.Obj) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | FOLLOWS
		o.model = EffectObjects.Model.GLOW
		o.b = -1
	elif o.state != 1:
		return
	var side := (o.a & GLOW_SIDE) >> 15
	var t := fight.fighters[side].body.joints[o.a & 0x7FFF].t
	o.x = t[0]
	o.y = t[1]
	o.z = t[2]
	o.b += 1
	_show(o, Book.GLOW, o.b & 7)
	var mask: int = fight.effects.glow_mask[side]
	if (mask >> (o.a & 0x1F)) & 1 == 0:
		o.flags &= ~VISIBLE
		return
	o.flags |= VISIBLE
	if mask & GLOW_JOINT_BIT:
		_spawn_at(Type.RISE, o)
	var r := fight.rng.next()
	if r & 0xF == 0:
		_spawn_at(Type.EMBER, o)
	if r & 0x80:
		_light(o, LIGHT_GLOW)


## Type 4 (FUN_801DDED0): a rising glow particle.
func _rise(o: EffectObjects.Obj) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | FOLLOWS
		o.model = EffectObjects.Model.GLOW_RISE
		o.b = -1
		var r := EffectObjects.rand2(fight)
		o.vy = 0
		o.x = Fx.w32(o.x - 0x3F + (r.x & 0x7F))
		o.y = Fx.w32(o.y - 0x3F + ((r.y >> 2) & 0x7F))
		o.z = Fx.w32(o.z - 0x3F + ((r.y >> 4) & 0x7F))
	elif o.state != 1:
		return
	o.b += 1
	if o.b < 0x10:
		_show(o, Book.RISE, o.b)
		o.vy = Fx.w32(o.vy + 0x12000)
		o.y = Fx.w32(o.y - (o.vy >> 16))
	else:
		EffectObjects.finish(o)


## Type 5 (FUN_801DE204): a rising ember.
func _ember(o: EffectObjects.Obj) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE
		o.model = EffectObjects.Model.EMBER
		o.a = -1
		o.vy = 0
		var r := EffectObjects.rand2(fight)
		o.x = Fx.w32(o.x - 0x7F + (r.x & 0xFF))
		o.z = Fx.w32(o.z - 0x7F + ((r.y >> 4) & 0xFF))
	elif o.state != 1:
		return
	o.a += 1
	if o.a < 0x20:
		_show(o, Book.EMBER, o.a)
		o.vy = Fx.w32(o.vy + 0x12000)
		o.y = Fx.w32(o.y - (o.vy >> 16))
	else:
		EffectObjects.finish(o)


## Type 6 (FUN_801DE520): a fireball of the fire breath: grows, loops, bursts; slides along the floor; its
## hit segment lives while the owner's move does. The update that finishes a burst still moves and draws.
func _fireball(o: EffectObjects.Obj) -> void:
	if o.flags & SEGMENT and _owner_ended(o, FIRE_BREATH):
		o.flags &= ~SEGMENT
	match o.state:
		0, 1:
			if o.state == 0:
				_fireball_start(o)
			_fireball_grow(o)
		2:
			_fireball_loop(o)
		3:
			_fireball_burst(o)
	EffectObjects.save_previous(o)
	EffectObjects.move(o)
	if o.y > FLOOR:
		o.y = FLOOR
		o.pitch = 0
		o.vy = 0
		_aim_flat(o)
	var r := fight.rng.next()
	if r & 0x3F == 0:
		_spawn_smoke(o, o.pitch, o.yaw)
	if o.y == FLOOR:
		r = fight.rng.next()
		if r & 0x7F == 0:
			var s := alloc(Type.FLOOR_FIRE)
			if s != null:
				s.x = o.x
				s.z = o.z
	if o.state >= 1 and o.state <= 2 and r & 0xF == 0:
		_light(o, LIGHT_FIRE)


func _fireball_start(o: EffectObjects.Obj) -> void:
	o.state += 1
	o.flags |= VISIBLE | SEGMENT
	var r := EffectObjects.rand2(fight)
	o.model = EffectObjects.Model.FIREBALL_B if r.x & 1 == 0 else EffectObjects.Model.FIREBALL_A
	o.a = 0
	o.c = 0
	o.speed = 0xA00
	o.b = ((r.y >> 2) & 3) + 5
	o.pitch = Fx.s16(o.pitch - 0x3F + ((r.y >> 4) & 0x7F))
	o.yaw = Fx.s16(o.yaw - 0x1F + ((r.y >> 6) & 0x3F))
	_aim(o)


func _fireball_grow(o: EffectObjects.Obj) -> void:
	_show(o, Book.FIRE_GROW, o.c & 7)
	o.c += 1
	if o.c > 7:
		o.state += 1
		o.c = fight.rng.next()
		o.speed = 0x1000
		_aim(o)


func _fireball_loop(o: EffectObjects.Obj) -> void:
	o.c += 1
	_show(o, Book.FIRE_LOOP, o.c & 7)
	o.a += 1
	if o.b <= o.a:
		o.c = -1
		o.state += 1


func _fireball_burst(o: EffectObjects.Obj) -> void:
	o.c += 1
	if o.c < 7:
		_show(o, Book.FIRE_BURST, o.c & 7)
		if o.flags & SEGMENT and tables.segment_fireball[o.c & 7] == 0:
			o.flags &= ~SEGMENT
	else:
		EffectObjects.finish(o)


## Type 7 (FUN_801DEDF0): a smoke puff that rises faster and faster; ends at the floor.
func _smoke(o: EffectObjects.Obj) -> void:
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE
				o.model = EffectObjects.Model.SMOKE
				var r := EffectObjects.rand2(fight)
				var u := r.y
				o.b = (u >> 10) & 0x1F
				o.a = 0
				o.x = Fx.w32(o.x - 0x7F + (r.x & 0xFF))
				o.y = Fx.w32(o.y - 0x7F + ((u >> 2) & 0xFF))
				o.z = Fx.w32(o.z - 0x7F + ((u >> 4) & 0xFF))
				o.pitch = Fx.s16(o.pitch - 0x3F + ((u >> 6) & 0x7F))
				o.yaw = Fx.s16(o.yaw - 0x3F + ((u >> 8) & 0x7F))
				o.speed = Fx.s16((((u >> 12) & 0x3FF) * 5 >> 2) + 0x200)
				_aim(o)
			o.a += 1
			_show(o, Book.FIRE_LOOP, (o.a & 0xE) >> 1)
			if o.b <= o.a:
				o.a = -1
				o.state += 1
		2:
			o.a += 1
			if o.a < 8:
				_show(o, Book.FIRE_BURST, o.a)
			else:
				EffectObjects.finish(o)
	o.vy = Fx.w32(o.vy - 0x30000)
	EffectObjects.move(o)
	if o.y >= 0:
		EffectObjects.finish(o)


## Type 9 (FUN_801DF394): floor fire: flickers, then rises and fades; emits smoke until its last update.
func _floor_fire(o: EffectObjects.Obj) -> void:
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE
				o.model = EffectObjects.Model.FLOOR_FIRE
				var r := EffectObjects.rand2(fight)
				o.y = -0x100
				o.a = r.y >> 2
				o.vy = 0
				o.b = (r.x & 0x1F) + 0x3C
			o.a = Fx.w32(o.a + 1)
			_show(o, Book.FLOOR_FIRE, (o.a & 0x1E) >> 1)
			o.b -= 1
			if o.b < 0:
				o.a = -1
				o.state += 1
		2:
			o.a += 1
			if o.a < 0x20:
				o.vy = Fx.w32(o.vy - 0x24000)
				_show(o, Book.FLOOR_FADE, (o.a & 0x1E) >> 1)
				o.y = Fx.w32(o.y + (o.vy >> 16))
			else:
				EffectObjects.finish(o)
	if fight.rng.next() & 0x1F == 0:
		_spawn_smoke(o, SMOKE_PITCH, 0)


## Type 10 (FUN_801DF8C8): a breath cloud, a hit segment for its first frames while the owner's move runs.
func _cloud(o: EffectObjects.Obj) -> void:
	if o.flags & SEGMENT and _owner_ended(o, BREATH_CLOUD):
		o.flags &= ~SEGMENT
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | SEGMENT
		o.model = EffectObjects.Model.CLOUD
		var r := EffectObjects.rand2(fight)
		o.c = -1
		o.speed = 0x300
		o.pitch = Fx.s16(o.pitch - 0x7F + (r.x & 0xFF))
		o.yaw = Fx.s16(o.yaw - 0x7F + ((r.y >> 2) & 0xFF))
		_aim(o)
	if o.state == 1:
		o.c += 1
		if o.c < tables.segment_cloud.size():
			_show(o, Book.CLOUD, o.c)
			if o.flags & SEGMENT and tables.segment_cloud[o.c] == 0:
				o.flags &= ~SEGMENT
		else:
			EffectObjects.finish(o)
	EffectObjects.save_previous(o)
	EffectObjects.move(o)


## Type 11 (FUN_801DFCC0): one flame of a burning body, following its joint; then it rises and bursts. The
## body burns on the attacker's opponent: `c` is the attacker.
func _burn(o: EffectObjects.Obj) -> void:
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE
				o.model = EffectObjects.Model.BURN
				var first := fight.rng.next()
				var second := fight.rng.next()
				o.a = (second & 0xF) + 0x3C
				o.b = (first << 16 | second) >> 2
			_burn_follow(o)
		2:
			o.a += 1
			if o.a < 0x10:
				_show(o, Book.FIRE_BURST, (o.a & 0xE) >> 1)
				o.vy = Fx.w32(o.vy - 0x18000)
				o.y = Fx.w32(o.y + (o.vy >> 16))
			else:
				EffectObjects.finish(o)


func _burn_follow(o: EffectObjects.Obj) -> void:
	o.b = Fx.w32(o.b + 1)
	var f := fight.fighters[1 - o.c]
	var t := f.body.joints[o.d].t
	o.x = t[0]
	o.y = t[1]
	o.z = t[2]
	_show(o, Book.FIRE_LOOP, (o.b & 0xE) >> 1)
	var r := fight.rng.next()
	if r & 0x1F == 0:
		_spawn_smoke(o, SMOKE_PITCH, 0)
	o.a -= 1
	if o.a < 0:
		o.a = -1
		o.vy = 0
		o.state += 1
	f.keep_light = 1
	if o.state == 1 and r & 0xF == 0:
		_light(o, LIGHT_FIRE)
