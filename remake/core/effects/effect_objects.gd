class_name EffectObjects
## The effect object pool (effects.md#effect-objects): sparks, power glows, fire breath, smoke,
## floor fire, breath and gas clouds, burning bodies and the voice echoes. It is simulation
## state: the objects draw from the shared `rand()`, their number decides the chance of
## optional spawns, and fire, breath and gas publish projectile hit segments.
##
## `EffectsUpdate` (0x8006F8A8) updates the live objects in allocation order; an object spawned
## during the pass is updated in the same pass. A finished object turns into type 0 and leaves
## the pool two updates later (FUN_8006F894, FUN_8006F840). The presentation draws the objects
## from their type, phase, counters and position.
##
## Type 15 is Tekken Ball's charged ball: a glow of the hitter's character, or a flame for a
## charge of 100 or more (FUN_80073F78).

const CAPACITY := 80
const VISIBLE := 0x40
const SEGMENT := 0x02
const OWNER_0 := 0x10               ## owner bits: 0x10 >> player
const MARK := 0x80                  ## allocated (FUN_8006F840 only frees marked objects)
const FLOOR := -0xD8
const GLOW_JOINTS := [6, 10, 0xE, 0x11, 0x8006, 0x800A, 0x800E, 0x8011]
const GLOW_JOINT_BIT := 0x80000000
const HANDS_GLOW := 0x440
const FIRE_BREATH := 0x18
const BREATH_CLOUD := 0x19
const GON_FLAME := 0x1A
const GAS := 0x1B
const DOCTOR_CLOUD := 0x1C
const SPARK_DAMAGE := 0x15
## Fixed CLUTs (0x800AE248…) and the fade ramps of rows 509 and 510 (FUN_8006E848).
const CLUT_DUST := 0x7DC6
const CLUT_GLOW := 0x7DC7
const CLUT_FIRE := 0x7DC8
const CLUT_BURST := 0x7DC9
const CLUT_CLOUD := 0x7DCA
const TPAGE_ADD := 0x3F
const TPAGE_HALF := 0x1F

## One pool object (0xA0 bytes in the game; the draw primitives are the presentation's).
class Obj:
	var type := 0                   ## +0x0C
	var flags := MARK               ## +0x0D
	var state := 0                  ## +0x0E
	var model := 0                  ## +0x08 the quad model (EffectObjects.Model)
	var pitch := 0                  ## +0x10 s16 direction
	var yaw := 0                    ## +0x12
	var speed := 0                  ## +0x18 s16
	var vx := 0                     ## +0x1C velocity, 16.16
	var vy := 0                     ## +0x20
	var vz := 0                     ## +0x24
	var x := 0                      ## +0x28
	var y := 0
	var z := 0
	var px := 0                     ## +0x34 the previous position (hit segment start)
	var py := 0
	var pz := 0
	var a := 0                      ## +0x40 per type counters and parameters
	var b := 0                      ## +0x44
	var c := 0                      ## +0x48
	var d := 0                      ## +0x4C
	var clut := 0                   ## the frame's CLUT id as the game computes it
	var tpage := TPAGE_ADD          ## additive or 50 % blending
	var uv := -1                    ## the frame of the phase's UV table (−1: the model's own)
	var uv_table := UvTable.MODEL   ## the phase's UV table (the presentation draws from it)
	var gone := false               ## unlinked (FUN_8006F840)

	func position() -> PackedInt32Array:
		return PackedInt32Array([x, y, z])

## Quad models of the objects (the executable's small models at 0x800254xx–0x800259xx).
enum Model { NONE, SPARK, GLOW, GLOW_RISE, EMBER, FIREBALL_A, FIREBALL_B, SMOKE, FLAME_A, FLAME_B,
	FLOOR_FIRE, CLOUD, BURN, BURN_GON, POWER_SPARK, GAS_A, GAS_B, BALL }
## The UV tables of the animated phases (effects.md, "UV animation"): MODEL is the model's own
## sprite; BALL_CHARACTER the character flipbook uploaded for Tekken Ball's charged ball.
enum UvTable { MODEL, FIREBALL_GROW, FIREBALL_LOOP, FIREBALL_BURST, SMOKE_PUFF, SMOKE_FADE, FLAME_GROW,
	FLAME_LOOP, FLAME_BURST, FIRE_FADE, CLOUD, GAS, BALL_CHARACTER }


# ==== the pool ====================================================================================

## FUN_8006F750: every object back in the free list.
static func reset(fight: FightState) -> void:
	fight.effects.objects.clear()


## EffectAlloc (0x8006F7DC): a new object at the end of the live list, null when all 80 are used.
static func alloc(fight: FightState, type: int) -> Obj:
	var pool := fight.effects
	if pool.objects.size() >= CAPACITY:
		return null
	var o := Obj.new()
	o.type = type
	o.flags = MARK
	o.state = 0
	pool.objects.append(o)
	return o


## FUN_8006F894: the object ends; it stays in the pool as type 0 for two more updates.
static func finish(o: Obj) -> void:
	o.type = 0
	o.state = 0
	o.flags = MARK


## Round start (FUN_8006E8FC): the pool emptied and the eight power glows created.
static func round_start(fight: FightState) -> void:
	var pool := fight.effects
	reset(fight)
	pool.replay_glows = 0
	pool.end_cleared = 0
	for f in fight.active():
		f.keep_light = 0
	pool.glow_mask = PackedInt32Array([0, 0])
	_spawn_glows(fight)


static func _spawn_glows(fight: FightState) -> void:
	for joint: int in GLOW_JOINTS:
		var o := alloc(fight, 3)
		if o != null:
			o.a = joint


## EffectsUpdate (0x8006F8A8). `enabled` is FightFrame's 0x800958C0 (0 while the fight only
## draws): the objects update and are counted only when it is set.
static func update(fight: FightState, enabled: bool, events: SimEvents) -> void:
	var pool := fight.effects
	pool.segments[0].clear()
	pool.segments[1].clear()
	if enabled:
		for f in fight.active():
			f.keep_light = 0
		pool.counter += 1
		_power_glow_joints(fight)
	if pool.replay_glows == 0 and fight.replay_playing != 0:
		reset(fight)
		_spawn_glows(fight)
		pool.burn_flags = 0
		pool.replay_glows += 1
	if pool.end_cleared == 0 and fight.camera_phase >= 3 and fight.camera_phase <= 7:
		reset(fight)
		pool.end_cleared += 1
	var count := 0
	var i := 0
	while i < pool.objects.size():
		var o := pool.objects[i]
		if enabled:
			_update_object(fight, o, events)
			count += 1
			if o.flags & SEGMENT:
				pool.segments[0 if o.flags & OWNER_0 else 1].append(
					PackedInt32Array([o.px, o.py, o.pz, o.x, o.y, o.z]))
		if o.gone:
			pool.objects.remove_at(i)
		else:
			i += 1
	pool.live = count


static func _update_object(fight: FightState, o: Obj, events: SimEvents) -> void:
	match o.type:
		0:
			_placeholder(o)
		1:
			_spark(fight, o, false)
		2:
			_spark_spray(fight, o, false)
		3:
			_glow(fight, o)
		4:
			_glow_rise(fight, o)
		5:
			_ember(fight, o)
		6:
			_fireball(fight, o)
		7:
			_smoke(fight, o)
		8:
			_flame(fight, o)
		9:
			_floor_fire(fight, o)
		10:
			_cloud(fight, o)
		11:
			_burn(fight, o)
		12:
			_spark(fight, o, true)
		13:
			_spark_spray(fight, o, true)
		15:
			_ball_glow(fight, o)
		16:
			_announcer_wait(o, events)
		17:
			_voice_echo(fight, o, events)
		18:
			_replay_echo(fight, o, events)
		19:
			_gas_emitter(fight, o)
		20:
			_gas(fight, o)


# ==== helpers =====================================================================================

## The chance of an optional spawn: `rand() < ((80 − live)·k / 80000)·4`.
static func _chance(fight: FightState, r: int, k: int) -> bool:
	return r < Fx.div_trunc((CAPACITY - fight.effects.live) * k, 80000) * 4


## FUN_8006E408: the velocity of the direction (pitch, yaw) and the speed (16.16).
static func _aim(fight: FightState, o: Obj) -> void:
	var t := fight.tables
	var p := -o.pitch & 0xFFF
	var w := -o.yaw & 0xFFF
	o.vy = Fx.w32(Fx.s16(o.speed) * FightMath.sin12(p, t))
	var h := (Fx.s16(o.speed) * FightMath.cos12(p, t)) >> 12
	o.vx = Fx.w32(h * FightMath.sin12(w, t))
	o.vz = Fx.w32(h * FightMath.cos12(w, t))


## FUN_8006E3B8: the horizontal velocity of the yaw and the speed.
static func _aim_flat(fight: FightState, o: Obj) -> void:
	var t := fight.tables
	var w := -o.yaw & 0xFFF
	o.vx = Fx.w32(Fx.s16(o.speed) * FightMath.sin12(w, t))
	o.vz = Fx.w32(Fx.s16(o.speed) * FightMath.cos12(w, t))


## One step along the velocity (the upper halves of the 16.16 values).
static func _move(o: Obj) -> void:
	o.x = Fx.w32(o.x + Fx.s16(o.vx >> 16))
	o.y = Fx.w32(o.y + Fx.s16(o.vy >> 16))
	o.z = Fx.w32(o.z + Fx.s16(o.vz >> 16))


static func _save_previous(o: Obj) -> void:
	o.px = o.x
	o.py = o.y
	o.pz = o.z


## Two rand() draws as the game combines them: r1 | r2 << 16.
static func _rand2(fight: FightState) -> Vector2i:
	var r1 := fight.rng.next()
	var r2 := fight.rng.next()
	return Vector2i(r1, r1 | r2 << 16)


## The owner fighter of an object (owner bit 0x10 → fighter 0, else fighter 1).
static func _owner(fight: FightState, o: Obj) -> FighterState:
	return fight.fighters[0] if o.flags & OWNER_0 else fight.fighters[1]


## The owner's move still runs descriptor `code` inside its active window (the game's test
## reads "before the active window" as ended).
static func _owner_active(fight: FightState, o: Obj, code: int) -> bool:
	var f := _owner(fight, o)
	if AttackRecords.first_joint(f.pose_move, fight.tables) != code:
		return false
	return not (f.pose_frame < f.pose_move.active_first)


static func _spawn_smoke(fight: FightState, o: Obj, pitch: int, yaw: int) -> void:
	var s := alloc(fight, 7)
	if s != null:
		s.x = o.x
		s.y = o.y
		s.z = o.z
		s.pitch = pitch
		s.yaw = yaw


# ==== types =======================================================================================

## Type 0: a finished object, freed on its second update.
## The fade ramp CLUTs: row 509 (glows, power sparks) and row 510 (sparks).
static func ramp509(i: int) -> int:
	return ((0x10 + i) & 0x3F) | 0x7F40


static func ramp510(i: int) -> int:
	return ((0x10 + i) & 0x3F) | 0x7F80


static func _placeholder(o: Obj) -> void:
	if o.state == 0:
		o.a = 2
		o.state += 1
	elif o.state != 1:
		return
	o.a -= 1
	if o.a < 1 and o.flags & MARK:
		o.gone = true


## Types 1 and 12: six decelerating sparks along the hit direction ± 60° (12: the power ramp).
static func _spark(fight: FightState, o: Obj, power: bool) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE
		o.model = Model.POWER_SPARK if power else Model.SPARK
		o.clut = CLUT_DUST
		var r := _rand2(fight)
		var u := r.y
		var i4 := ((r.x & 0x7FF) - 0x3FF) * 2
		o.b = ((u >> 4) & 0x1F) + 10
		var i3 := (((u >> 2) & 0x7FF) - 0x3FF) * 2
		o.c = (u >> 6) & 0x1FF
		o.a = 0
		o.d = ((u >> 8) & 0x1FF) + 0x680
		o.pitch = Fx.s16(o.pitch + Fx.div_trunc(i4, 3))
		o.yaw = Fx.s16(o.yaw + Fx.div_trunc(i3, 3))
	elif o.state != 1:
		return
	o.a += 1
	if o.a < o.b:
		var i := Fx.div_trunc(o.a * 0x10, o.b)
		o.clut = ramp509(i) if power else ramp510(i)
		var w := FightMath.cos12(Fx.div_trunc(o.a * 0x3FF, o.b) & 0x3FF, fight.tables)
		o.speed = Fx.s16(o.c + (((o.d - o.c) * (w * 4 + 0x2000)) >> 15))
		_aim(fight, o)
		_move(o)
		if o.y < 0:
			return
	finish(o)


## Types 2 and 13: twenty sparks sprayed from a jittered start at a constant speed.
static func _spark_spray(fight: FightState, o: Obj, power: bool) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE
		o.model = Model.POWER_SPARK if power else Model.SPARK
		o.clut = CLUT_DUST
		var r := _rand2(fight)
		var u := r.y
		o.b = ((u >> 10) & 0x1F) + 0x14
		o.a = 0
		o.x = Fx.w32(o.x - 0x7F + (r.x & 0xFF))
		o.y = Fx.w32(o.y - 0x7F + ((u >> 2) & 0xFF))
		o.z = Fx.w32(o.z - 0x7F + ((u >> 4) & 0xFF))
		o.pitch = Fx.s16(o.pitch - 0x3F + ((u >> 6) & 0x7F))
		o.yaw = Fx.s16(o.yaw - 0x3F + ((u >> 8) & 0x7F))
		o.speed = Fx.s16((((u >> 12) & 0x7FF) * 5) >> 2)
		_aim(fight, o)
		o.x = Fx.w32(o.x + (o.vx >> 13))
		o.y = Fx.w32(o.y + (o.vy >> 13))
		o.z = Fx.w32(o.z + (o.vz >> 13))
	elif o.state != 1:
		return
	o.a += 1
	if o.a < o.b:
		var i := Fx.div_trunc(o.a * 0x10, o.b)
		o.clut = ramp509(i) if power else ramp510(i)
		_move(o)
		if o.y < 0:
			return
	finish(o)


## Type 3: the power glow on one joint (6, 10, 14, 17; +0x8000 for fighter 1), shown while
## PowerGlowJoints sets the joint's bit, with rising particles.
static func _glow(fight: FightState, o: Obj) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | 0x20
		o.model = Model.GLOW
		o.clut = CLUT_GLOW
		o.b = -1
	elif o.state != 1:
		return
	var player := (o.a & 0x8000) >> 15
	var mask: int = fight.effects.glow_mask[player]
	if (mask >> (o.a & 0x1F)) & 1 == 0:
		o.flags &= ~VISIBLE
		return
	o.flags |= VISIBLE
	var joint := o.a & 0x7FFF
	var f := fight.fighters[player]
	var e := fight.tables.effects
	var body := f.body
	var p: PackedInt32Array
	if joint == 6:
		var block := 19 if f.char_id == Character.TRUE_OGRE else 6
		var off: PackedInt32Array = e.hand_offsets[f.char_id][0]
		var m := Gte.apply(body.joints[block].rot, off[0], off[1], off[2])
		p = PackedInt32Array([Fx.w32(m[0] + body.joints[block].t[0]), Fx.w32(m[1] + body.joints[block].t[1]),
			Fx.w32(m[2] + body.joints[block].t[2])])
	elif joint == 10:
		var off: PackedInt32Array = e.hand_offsets[f.char_id][1]
		var m := Gte.apply(body.joints[10].rot, off[0], off[1], off[2])
		p = PackedInt32Array([Fx.w32(m[0] + body.joints[10].t[0]), Fx.w32(m[1] + body.joints[10].t[1]),
			Fx.w32(m[2] + body.joints[10].t[2])])
	else:
		p = body.joints[joint].t.duplicate()
	o.x = p[0]
	o.y = p[1]
	o.z = p[2]
	o.b += 1
	o.clut = ramp509((o.b >> 1) & 7)
	if mask & GLOW_JOINT_BIT:
		var s := alloc(fight, 4)
		if s != null:
			s.x = o.x
			s.y = o.y
			s.z = o.z
	var r := fight.rng.next()
	if _chance(fight, r, 0xC8000):
		var s := alloc(fight, 5)
		if s != null:
			s.x = o.x
			s.y = o.y
			s.z = o.z
	if r & 0x80:
		fight.effects.lights.append(PackedInt32Array([o.x, o.y, o.z, 1]))


## Type 4: a rising glow particle (16 frames).
static func _glow_rise(fight: FightState, o: Obj) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | 0x20
		o.model = Model.GLOW_RISE
		o.clut = CLUT_GLOW
		o.b = -1
		var r := _rand2(fight)
		o.vy = 0
		o.x = Fx.w32(o.x - 0x3F + (r.x & 0x7F))
		o.y = Fx.w32(o.y - 0x3F + ((r.y >> 2) & 0x7F))
		o.z = Fx.w32(o.z - 0x3F + ((r.y >> 4) & 0x7F))
	elif o.state != 1:
		return
	o.b += 1
	if o.b < 0x10:
		o.clut = ramp509(o.b)
		o.vy = Fx.w32(o.vy + 0x12000)
		o.y = Fx.w32(o.y - (o.vy >> 16))
	else:
		finish(o)


## Type 5: a rising ember (32 frames).
static func _ember(fight: FightState, o: Obj) -> void:
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE
		o.model = Model.EMBER
		o.clut = CLUT_GLOW
		o.a = -1
		o.vy = 0
		var r := _rand2(fight)
		o.x = Fx.w32(o.x - 0x7F + (r.x & 0xFF))
		o.z = Fx.w32(o.z - 0x7F + ((r.y >> 4) & 0xFF))
	elif o.state != 1:
		return
	o.a += 1
	if o.a < 0x20:
		o.clut = ramp509(o.a >> 1)
		o.vy = Fx.w32(o.vy + 0x12000)
		o.y = Fx.w32(o.y - (o.vy >> 16))
	else:
		finish(o)


## Type 6: the fireball of a fire breath (descriptor 0x18): grows, loops, bursts; slides along
## the floor; a projectile segment on the frames of its owner's display buffer; smoke and floor
## fire.
static func _fireball(fight: FightState, o: Obj) -> void:
	var pool := fight.effects
	var own_buffer := (o.flags & OWNER_0 == 0) == (fight.display_buffer == 0)
	if o.d != 0:
		if not _owner_active(fight, o, FIRE_BREATH):
			o.d = 0
		if own_buffer:
			_save_previous(o)
	match o.state:
		0, 1:
			if o.state == 0:
				_fireball_start(fight, o)
			_fireball_grow(fight, o)
		2:
			_fireball_loop(fight, o)
		3:
			_fireball_burst(fight, o)
	o.x = Fx.w32(o.x + Fx.s16(o.vx >> 16))
	o.y = Fx.w32(o.y + Fx.s16(o.vy >> 16))
	o.z = Fx.w32(o.z + Fx.s16(o.vz >> 16))
	if o.y > FLOOR:
		o.y = FLOOR
		o.pitch = 0
		o.vy = 0
		_aim_flat(fight, o)
	o.flags &= ~SEGMENT
	if o.d != 0 and not own_buffer:
		o.flags |= SEGMENT
	var r := fight.rng.next()
	if _chance(fight, r, 0x3C000):
		_spawn_smoke(fight, o, o.pitch, o.yaw)
	elif o.y == FLOOR and o.d != 0:
		r = fight.rng.next()
		if _chance(fight, r, 0x24000):
			var s := alloc(fight, 9)
			if s != null:
				s.x = o.x
				s.z = o.z
	if o.state >= 1 and o.state <= 2 and (r >> 8) & 0xF == 0:
		pool.lights.append(PackedInt32Array([o.x, o.y, o.z, 0]))


static func _fireball_start(fight: FightState, o: Obj) -> void:
	o.state += 1
	o.flags |= VISIBLE
	o.clut = CLUT_FIRE
	_save_previous(o)
	var r := fight.rng.next()
	o.model = Model.FIREBALL_A if r & 1 == 0 else Model.FIREBALL_B
	o.b = ((r >> 2) & 3) + 5
	o.c = -1
	o.d = 1
	o.speed = 0xA00
	o.a = 0
	o.pitch = Fx.s16(o.pitch - 0x3F + ((r >> 4) & 0x7F))
	o.yaw = Fx.s16(o.yaw - 0x1F + ((r >> 6) & 0x3F))
	_aim(fight, o)


static func _fireball_grow(fight: FightState, o: Obj) -> void:
	o.c += 1
	o.uv = o.c
	o.uv_table = UvTable.FIREBALL_GROW
	if o.c > 6:
		o.state += 1
		o.c = fight.rng.next()
		o.speed = 0x1000
		_aim(fight, o)


static func _fireball_loop(fight: FightState, o: Obj) -> void:
	o.c = Fx.w32(o.c + 1)
	o.uv = o.c & 7
	o.uv_table = UvTable.FIREBALL_LOOP
	o.a += 1
	if o.b <= o.a:
		o.c = -1
		o.state += 1
		o.model = Model.FIREBALL_A if fight.rng.next() & 1 == 0 else Model.FIREBALL_B


static func _fireball_burst(fight: FightState, o: Obj) -> void:
	o.clut = CLUT_BURST
	o.c += 1
	if o.c < 8:
		o.uv = o.c
		o.uv_table = UvTable.FIREBALL_BURST
		o.model = Model.FIREBALL_A if o.c & 1 == 0 else Model.FIREBALL_B
		if o.d != 0 and fight.tables.effects.segment_frames["fireball"][o.c] == 0:
			o.d = 0
	else:
		finish(o)


## Type 7: a smoke or ember puff that rises faster and faster; ends at the floor.
static func _smoke(fight: FightState, o: Obj) -> void:
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE
				o.model = Model.SMOKE
				o.clut = CLUT_GLOW
				var r := _rand2(fight)
				var u := r.y
				o.b = (u >> 10) & 0x1F
				o.a = 0
				o.x = Fx.w32(o.x - 0x7F + (r.x & 0xFF))
				o.y = Fx.w32(o.y - 0x7F + ((u >> 2) & 0xFF))
				o.z = Fx.w32(o.z - 0x7F + ((u >> 4) & 0xFF))
				o.pitch = Fx.s16(o.pitch - 0x3F + ((u >> 6) & 0x7F))
				o.yaw = Fx.s16(o.yaw - 0x3F + ((u >> 8) & 0x7F))
				o.speed = Fx.s16(((((u >> 12) & 0x3FF) * 5) >> 2) + 0x200)
				_aim(fight, o)
			o.a += 1
			o.uv = (o.a & 0xE) >> 1
			o.uv_table = UvTable.SMOKE_PUFF
			if o.b <= o.a:
				o.a = -1
				o.state += 1
		2:
			o.a += 1
			if o.a < 0xC:
				o.uv = o.a
				o.uv_table = UvTable.SMOKE_FADE
			else:
				finish(o)
	o.vy = Fx.w32(o.vy - 0x30000)
	_move(o)
	if o.y >= 0:
		finish(o)


## Type 8: Gon's flame (descriptor 0x1A): a projectile until its owner is hit (then gone) or
## the move leaves the active window; during the replay it follows the recorded hits.
static func _flame(fight: FightState, o: Obj) -> void:
	if o.flags & SEGMENT:
		if fight.replay_playing == 0:
			if not _owner_active(fight, o, GON_FLAME):
				o.flags &= ~SEGMENT
		elif o.flags & OWNER_0 == 0:
			if fight.effects.burn_flags & 0x10:
				finish(o)
				return
		elif fight.effects.burn_flags & 8:
			finish(o)
			return
		if o.flags & SEGMENT and o.state >= 1 and o.state <= 2:
			var target := fight.fighters[0] if o.flags & OWNER_0 == 0 else fight.fighters[1]
			if target.hit_clean != 0:
				finish(o)
				return
			if target.guarded != 0:
				o.state = 3
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE | SEGMENT
				o.clut = CLUT_FIRE
				var r := fight.rng.next()
				o.model = Model.FLAME_B if r & 1 == 0 else Model.FLAME_A
				o.b = ((r >> 2) & 3) + 5
				o.c = -1
				o.a = 0
				o.speed = 0x800
				_aim(fight, o)
			o.c += 1
			o.uv = o.c >> 1
			o.uv_table = UvTable.FLAME_GROW
			if o.c > 6:
				o.state += 1
				o.c = fight.rng.next()
		2:
			o.c = Fx.w32(o.c + 1)
			o.uv = (o.c & 6) >> 1
			o.uv_table = UvTable.FLAME_LOOP
			o.a += 1
			if o.b <= o.a:
				o.state = 4
				o.c = -1
		3, 4:
			if o.state == 3:
				o.state = 4
				o.vx = 0
				o.vy = 0
				o.vz = 0
				o.c = -1
			o.clut = CLUT_BURST
			o.c += 1
			if o.c < 9:
				o.uv = o.c >> 1
				o.uv_table = UvTable.FLAME_BURST
				if o.flags & SEGMENT and fight.tables.effects.segment_frames["flame"][o.c] == 0:
					o.flags &= ~SEGMENT
			else:
				finish(o)
	_save_previous(o)
	_move(o)
	if o.y > FLOOR:
		o.y = FLOOR
		o.pitch = 0
		o.vy = 0
		_aim_flat(fight, o)
	var r := fight.rng.next()
	if _chance(fight, r, 0x3C000):
		_spawn_smoke(fight, o, o.pitch, o.yaw)
	if (r >> 8) & 0xF == 0:
		fight.effects.lights.append(PackedInt32Array([o.x, o.y, o.z, 0]))


## Type 9: floor fire: flickers for 60–91 frames, then rises and fades; emits smoke.
static func _floor_fire(fight: FightState, o: Obj) -> void:
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE
				o.model = Model.FLOOR_FIRE
				o.clut = CLUT_GLOW
				var r := _rand2(fight)
				o.y = -0x100
				o.vy = 0
				o.a = r.y >> 2
				o.b = (r.x & 0x1F) + 0x3C
			o.a = Fx.w32(o.a + 1)
			o.uv = (o.a & 0xE) >> 1
			o.uv_table = UvTable.SMOKE_PUFF
			o.b -= 1
			if o.b < 0:
				o.a = -1
				o.state += 1
		2:
			o.a += 1
			if o.a < 0x10:
				o.uv = o.a
				o.uv_table = UvTable.FIRE_FADE
				o.vy = Fx.w32(o.vy - 0x24000)
				o.y = Fx.w32(o.y + (o.vy >> 16))
			else:
				finish(o)
	var r := fight.rng.next()
	if _chance(fight, r, 0x28000):
		_spawn_smoke(fight, o, 0x400, 0)


## Type 10: a breath cloud (descriptors 0x19 and 0x1C): 21 frames, a projectile for its first
## ones while the owner's move stays active.
static func _cloud(fight: FightState, o: Obj) -> void:
	if o.flags & SEGMENT:
		var code := DOCTOR_CLOUD if o.d != 0 else BREATH_CLOUD
		if not _owner_active(fight, o, code):
			o.flags &= ~SEGMENT
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | SEGMENT
		o.model = Model.CLOUD
		o.tpage = TPAGE_HALF
		o.clut = CLUT_CLOUD if o.d == 0 else CLUT_DUST
		var r := _rand2(fight)
		o.c = -1
		o.speed = 0x300
		o.pitch = Fx.s16(o.pitch - 0x7F + (r.x & 0xFF))
		o.yaw = Fx.s16(o.yaw - 0x7F + ((r.y >> 2) & 0xFF))
		_aim(fight, o)
	if o.state == 1:
		o.c += 1
		if o.c < 0x15:
			o.uv = o.c
			o.uv_table = UvTable.CLOUD
			if o.flags & SEGMENT and fight.tables.effects.segment_frames["cloud"][o.c] == 0:
				o.flags &= ~SEGMENT
		else:
			finish(o)
	_save_previous(o)
	_move(o)


## Type 11: one flame of a burning body, following its joint; then it rises and bursts.
static func _burn(fight: FightState, o: Obj) -> void:
	match o.state:
		0, 1:
			if o.state == 0:
				o.state += 1
				o.flags |= VISIBLE
				o.model = Model.BURN_GON if o.flags & 0x20 else Model.BURN
				o.clut = CLUT_FIRE
				var r := fight.rng.next()
				o.a = (r & 0xF) + 0x3C
				o.b = r >> 4
			_burn_follow(fight, o)
		2:
			o.uv = o.a >> 1
			o.uv_table = UvTable.FLAME_LOOP
			o.vy = Fx.w32(o.vy - 0x18000)
			o.a += 1
			o.y = Fx.w32(o.y + (o.vy >> 16))
			if o.a > 6:
				o.a = -1
				o.state += 1
		3:
			o.a += 1
			if o.a < 5:
				o.uv = o.a >> 1
				o.uv_table = UvTable.FLAME_BURST
				o.clut = CLUT_BURST
				o.vy = Fx.w32(o.vy - 0x18000)
				o.y = Fx.w32(o.y + (o.vy >> 16))
			else:
				finish(o)


static func _burn_follow(fight: FightState, o: Obj) -> void:
	o.b = Fx.w32(o.b + 1)
	var f: FighterState
	if o.flags & 0x10:
		f = fight.fighters[0]
	elif o.flags & 8:
		f = fight.fighters[1]
	else:
		f = fight.fighters[0]
	var joint := f.body.joints[o.d]
	o.x = joint.t[0]
	o.y = joint.t[1]
	o.z = joint.t[2]
	o.uv = (o.b & 6) >> 1
	o.uv_table = UvTable.FLAME_LOOP
	var r := fight.rng.next()
	if _chance(fight, r, 0x3C000):
		_spawn_smoke(fight, o, 0x400, 0)
	o.a -= 1
	if o.a < 0:
		o.a = 0
		o.vy = 0
		o.state += 1
	f.keep_light = 1


## Type 15 (FUN_80073F78): Tekken Ball's charged ball. `d` 0 glows with the character flipbook of
## player `a` (a 12-frame loop), `d` 1 is a flame that grows over 7 frames, then flickers. It
## follows the ball one frame ahead and ends (freeing its start mark, 0x800B645C) once the ball's
## render kind no longer shows that charge; a frame in 16 lights the scene.
static func _ball_glow(fight: FightState, o: Obj) -> void:
	var ball := fight.ball
	var r := fight.rng.next()
	fight.rng.next()
	if o.d == 0:
		if o.state == 0:
			_ball_glow_start(fight, o)
		if o.state == 1:
			o.c += 1
			if o.c > 0xB:
				o.c = 0
			o.uv = o.c
			o.uv_table = UvTable.BALL_CHARACTER
	elif o.d == 1:
		match o.state:
			0, 1:
				if o.state == 0:
					_ball_glow_start(fight, o)
				o.c += 1
				o.uv = o.c
				o.uv_table = UvTable.FIREBALL_GROW
				if o.c > 6:
					o.state += 1
					o.c = fight.rng.next()
			2:
				o.c = (o.c + 1) & 0xFFFFFFFF
				o.uv = o.c & 7
				o.uv_table = UvTable.FIREBALL_LOOP
	o.px = o.x
	o.py = o.y
	o.pz = o.z
	var b := ball.b
	o.x = Fx.w32(b.s32(TekkenBall.B_POS) + (b.s32(TekkenBall.B_VEL) >> 8))
	o.y = Fx.w32(b.s32(TekkenBall.B_POS + 4) + (b.s32(TekkenBall.B_VEL + 4) >> 8))
	o.z = Fx.w32(b.s32(TekkenBall.B_POS + 8) + (b.s32(TekkenBall.B_VEL + 8) >> 8))
	var kind := b.u8(TekkenBall.B_KIND)
	if kind == 5 or kind == 8:
		return
	if o.d == 0:
		if r & 0xF == 0:
			fight.effects.lights.append(PackedInt32Array([o.x, o.y, o.z, 1]))
		if kind == (6 if o.a == 0 else 7):
			return
	elif o.d == 1:
		if r & 0xF == 0:
			fight.effects.lights.append(PackedInt32Array([o.x, o.y, o.z, 0]))
		if kind == 9:
			return
	ball.v.put8(TekkenBall.GLOWS - TekkenBall.BASE, 0)
	finish(o)


## FUN_800741E0: the charged ball's effect appears with a random tilt.
static func _ball_glow_start(fight: FightState, o: Obj) -> void:
	o.state += 1
	o.flags |= VISIBLE
	o.model = Model.BALL
	o.speed = 0
	o.c = -1
	if o.d == 1:
		o.flags |= SEGMENT
	var r := _rand2(fight)
	var u := r.y
	o.speed = 0
	o.pitch = Fx.s16(o.pitch - 0x3F + ((Fx.w32(u) >> 4) & 0x7F))
	o.yaw = Fx.s16(o.yaw - 0x1F + ((Fx.w32(u) >> 6) & 0x3F))
	_aim(fight, o)


## Type 16: waits for the announcer's voice (SPU voice 2) to stop, then plays 0x86DA. The
## simulation takes the voice as silent (as the harness does), so it plays at once.
static func _announcer_wait(o: Obj, events: SimEvents) -> void:
	if o.state == 0:
		o.state = 1
	elif o.state == 1:
		events.add(SimEvents.Kind.SOUND, -1, 0x86DA, 0)
		finish(o)


## Type 17: a throw voice echoed twice, 15 frames apart (twice as fast during the replay), with
## the SPU voice bits changed.
static func _voice_echo(fight: FightState, o: Obj, events: SimEvents) -> void:
	o.c -= 2 if fight.replay_playing != 0 else 1
	match o.state:
		0:
			o.c = 0xF
			o.state += 1
		1:
			if o.c < 0:
				o.b = (o.b & ~0x3C00) | (o.a * 0x400 + 0x3000)
				events.add(SimEvents.Kind.SOUND, o.a, o.b, o.a).c = 1
				o.c = 0xF
				o.state += 1
		2:
			if o.c < 0:
				o.b = (o.b & ~0x3C00) | (o.a * 0x400 + 0x3800)
				events.add(SimEvents.Kind.SOUND, o.a, o.b, o.a).c = 2
				finish(o)


## Type 18: a voice repeated during the replay, on rotating SPU voices.
static func _replay_echo(fight: FightState, o: Obj, events: SimEvents) -> void:
	match o.state:
		0:
			o.b = mokujin_code(fight, o.b)
			if o.b & 0x3C00 == 0:
				finish(o)
			else:
				o.c = 0xF
				o.state += 1
		1, 2:
			o.c -= 2 if fight.replay_playing != 0 else 1
			if o.c < 0:
				fight.effects.echo_voice = (fight.effects.echo_voice + 1) & 7
				events.add(SimEvents.Kind.SOUND, o.a, (o.b & ~0x3C00) | fight.effects.echo_voice << 10, o.a).c = o.state | 0x80
				o.c = 0xF
				o.state += 1
		3:
			finish(o)


## FUN_80075830: Mokujin's replacement of a sound code (the sound code of a listed sound id).
static func mokujin_code(fight: FightState, code: int) -> int:
	for pair: PackedInt32Array in fight.tables.effects.mokujin_sounds:
		if code == fight.tables.sound_codes[pair[0]]:
			return pair[1]
	return code


## Type 19: Gon's gas emitter (descriptor 0x1B) at the hips: clouds on a timetable while the
## move stays active.
static func _gas_emitter(fight: FightState, o: Obj) -> void:
	if not _owner_active(fight, o, GAS):
		finish(o)
		return
	if o.state == 0:
		o.a = -1
		o.b = 0
		o.state += 1
	elif o.state != 1:
		return
	o.a += 1
	var times: Array = fight.tables.effects.gas_times
	var entry: PackedInt32Array = times[o.b]
	if entry[0] <= o.a:
		var s := alloc(fight, 20)
		if s != null:
			s.flags |= o.flags & (0x10 | 8)
			s.x = o.x
			s.y = -entry[2]
			s.z = o.z
			s.pitch = 0
			s.speed = Fx.s16(entry[1] << 4)
			s.yaw = o.yaw
		o.b += 1
		if o.b >= times.size():
			finish(o)


## Type 20: a gas cloud: 27 frames rising slowly, a projectile for its first frames.
static func _gas(fight: FightState, o: Obj) -> void:
	if o.flags & SEGMENT and not _owner_active(fight, o, GAS):
		o.flags &= ~SEGMENT
	_save_previous(o)
	if o.state == 0:
		o.state += 1
		o.flags |= VISIBLE | SEGMENT
		o.model = Model.GAS_A if fight.rng.next() & 1 == 0 else Model.GAS_B
		o.clut = CLUT_DUST
		o.tpage = TPAGE_HALF
		o.c = -1
		_aim(fight, o)
		_move(o)
		o.vy = 0
	if o.state == 1:
		o.c += 1
		if o.c < 0x36:
			o.uv = (o.c & 0x7FFE) >> 1
			o.uv_table = UvTable.GAS
			o.vy = Fx.w32(o.vy - 0x3999)
			o.y = Fx.w32(o.y + (o.vy >> 16))
			if o.flags & SEGMENT and fight.tables.effects.segment_frames["gas"][o.c >> 1] == 0:
				o.flags &= ~SEGMENT
		else:
			finish(o)


# ==== spawns ======================================================================================

## PowerGlowJoints (0x8006F5D8): the joints that glow this frame: while the power timer runs,
## the running attack's joints (by the descriptor), or both hands (Gon, or a move without
## attack joints). The game reads a move without descriptor from address 0 (bug #56); the
## remake takes it as having no attack joints.
static func _power_glow_joints(fight: FightState) -> void:
	var pool := fight.effects
	for p in 2:
		pool.glow_mask[p] = 0
		var f := fight.fighters[p]
		if fight.replay.power_timer(f) == 0:
			continue
		var h := AttackRecords.header(f.pose_move, fight.tables)
		if f.char_id != Character.GON and h[0] + h[1] + h[2] + h[3] != 0:
			if f.pose_frame <= f.pose_move.active_last:
				for k in 4:
					var j: int = fight.tables.effects.glow_joints[h[k]] if h[k] < fight.tables.effects.glow_joints.size() else 0
					if j != 0:
						pool.glow_mask[p] |= (1 << (j & 0x1F)) | GLOW_JOINT_BIT
			continue
		pool.glow_mask[p] |= HANDS_GLOW


## EffectDescriptorSpawn (0x8006F3DC) for a fighter: fire breath, breath clouds, Gon's flame
## and gas start inside the active window of a move with descriptor 0x18–0x1C.
static func descriptor_spawn(fight: FightState, f: FighterState, enabled: bool, events: SimEvents) -> void:
	if not enabled or fight.effects.end_cleared != 0:
		return
	var move := f.pose_move
	var code := AttackRecords.first_joint(f.pose_move, fight.tables)
	if code < FIRE_BREATH or code > DOCTOR_CLOUD:
		return
	if f.pose_frame < move.active_first or move.active_last < f.pose_frame:
		return
	var e := fight.tables.effects
	match code:
		FIRE_BREATH:
			if f.pose_frame == move.active_first:
				Vibration.fighter(fight, f.index, 3, events)
			var offsets: Array = e.breath_offsets[f.player_index]
			_emit(fight, f, 6, 2, offsets)
			var head := f.body.joints[2]
			var v0: PackedInt32Array = offsets[0]
			var m := Gte.apply(head.rot, v0[0], v0[1], v0[2])
			fight.effects.lights.append(PackedInt32Array([m[0] + head.t[0], m[1] + head.t[1], m[2] + head.t[2], 0]))
		BREATH_CLOUD, DOCTOR_CLOUD:
			var o := _emit(fight, f, 10, 2, e.cloud_offsets)
			if o != null:
				o.d = 1 if code == DOCTOR_CLOUD else 0
		GON_FLAME:
			if f.pose_frame == move.active_first:
				Vibration.fighter(fight, f.index, 4, events)
			var o := _emit(fight, f, 8, 2, e.flame_offsets)
			if o != null:
				fight.effects.lights.append(PackedInt32Array([o.x, o.y, o.z, 0]))
		GAS:
			if f.pose_frame == move.active_first:
				_emit(fight, f, 19, 11, e.gas_offsets)


## An object at the first of two offsets from a joint, aimed at the second (FUN_8006E21C).
static func _emit(fight: FightState, f: FighterState, type: int, joint: int, offsets: Array) -> Obj:
	var j := f.body.joints[joint]
	var p := PackedInt32Array()
	for k in 2:
		var v: PackedInt32Array = offsets[k]
		var m := Gte.apply(j.rot, v[0], v[1], v[2])
		p.append_array(PackedInt32Array([Fx.w32(m[0] + j.t[0]), Fx.w32(m[1] + j.t[1]), Fx.w32(m[2] + j.t[2])]))
	var o := alloc(fight, type)
	if o == null:
		return null
	o.flags |= OWNER_0 if f.player_index == 0 else 8
	o.x = p[0]
	o.y = p[1]
	o.z = p[2]
	var d := direction(fight, p[3] - p[0], p[4] - p[1], p[5] - p[2])
	o.pitch = d.x
	o.yaw = d.y
	return o


## FUN_8006E21C: (pitch, yaw) of a vector, as the effects measure it.
static func direction(fight: FightState, dx: int, dy: int, dz: int) -> Vector2i:
	var ct := fight.tables.camera
	var yaw := (Fx.s16(CameraMath.atan2_units4096(dx, dz, ct)) - 0x400) & 0xFFF
	var flat := _flat_length(fight, dx, dz, yaw)
	var pitch := (Fx.s16(CameraMath.atan2_units4096(dy, flat, ct)) - 0x400) & 0xFFF
	return Vector2i(pitch, yaw)


## FUN_8006E2AC: the horizontal length from the larger component and the yaw.
static func _flat_length(fight: FightState, x: int, z: int, yaw: int) -> int:
	var t := fight.tables
	var n := x
	var s := 0
	if absi(z) < absi(x):
		var sv := FightMath.sin12(yaw & 0xFFF, t)
		s = Fx.s16(sv << 3)
		if sv & 0x1FFF == 0:
			s = 1
	else:
		var cv := FightMath.cos12(yaw & 0xFFF, t)
		s = Fx.s16(cv << 3)
		n = z
		if cv & 0x1FFF == 0:
			s = 1
	return absi(Fx.div_trunc(Fx.w32(n << 16), s) >> 1)


## FUN_80076F10's effect objects of a damaging hit: fire (descriptor 0x18 or 0x1A) sets the
## defender alight; otherwise a hit of 21 or more sprays sparks along the attacker's first
## attack segment (the power sparks while its power timer runs).
static func hit_objects(fight: FightState, damage: int, defender: FighterState, attacker_index: int,
		point: PackedInt32Array, events: SimEvents) -> void:
	var attacker := fight.fighters[attacker_index]
	var code := AttackRecords.first_joint(attacker.pose_move, fight.tables)
	if code == BREATH_CLOUD or code == GAS or code == DOCTOR_CLOUD:
		return
	if code == FIRE_BREATH or code == GON_FLAME:
		burn(fight, defender.index, events)
		# Logged with an unset point, which the replay's burn does not use.
		var root := PackedInt32Array([defender.root_x, defender.root_y, defender.root_z])
		fight.replay.log_effect(defender.index, 0x82, root, PackedInt32Array([0, 0, 0]), 0)
		return
	if damage < SPARK_DAMAGE:
		return
	var seg := attacker.attack_segs[0]
	var d := direction(fight, seg[3] - seg[0], seg[4] - seg[1], seg[5] - seg[2])
	var power := attacker.power_timer != 0
	var dir := PackedInt32Array([d.x, d.y, damage])
	_spray(fight, 13 if power else 2, 20, point, d)
	fight.replay.log_effect(attacker_index, 0x84 if power else 0x81, point, dir, 0)
	_spray(fight, 12 if power else 1, 6, point, d)
	fight.replay.log_effect(attacker_index, 0x83 if power else 0x80, point, dir, 0)


static func _spray(fight: FightState, type: int, count: int, point: PackedInt32Array, d: Vector2i) -> void:
	for i in count:
		var o := alloc(fight, type)
		if o == null:
			return
		o.x = point[0]
		o.y = point[1]
		o.z = point[2]
		o.pitch = Fx.s16(d.x)
		o.yaw = Fx.s16(d.y)


## FUN_8006F248: a burning body: ten flames on the body's joints (one for Gon), pad vibration.
static func burn(fight: FightState, player: int, events: SimEvents) -> void:
	Vibration.fighter(fight, player, 0, events)
	var f := fight.fighters[fight.fighters[player].last_attacker]
	var count := 10
	if f.char_id == Character.GON:
		count = 1
		fight.effects.burn_flags |= 0x10 >> player
	var joints: PackedInt32Array = fight.tables.effects.burn_joints
	for i in count:
		var o := alloc(fight, 11)
		if o == null:
			return
		if f.char_id == Character.GON:
			o.flags |= 0x20
		o.c = i
		o.d = joints[i]
		o.flags |= 0x10 >> player


## FUN_8006F4F0 / FUN_8006F584: the echo of a throw voice (17, not while its fighter is in a
## throw) and of a voice replayed during the replay (18).
static func voice_echo(fight: FightState, player: int, code: int, replayed: bool) -> void:
	if not replayed and fight.fighters[player].in_throw != 0:
		return
	var o := alloc(fight, 18 if replayed else 17)
	if o != null:
		o.a = player
		o.b = code & 0xFFFF


## FUN_8004A954: the replay plays the effect log's entries of the frame: flipbooks (sets
## 0x80+ re-create effect objects) and dust rings.
static func play_log(fight: FightState, events: SimEvents) -> void:
	for e in fight.replay.log_take():
		if e.mode == 1:
			events.add_at(SimEvents.Kind.DUST, -1, e.point.duplicate())
			continue
		if e.mode != 0:
			continue
		if e.index & 0x80 == 0:
			if e.set == 3:
				events.add_at(SimEvents.Kind.SPARK, -1, e.point.duplicate(), e.index)
			else:
				events.add_at(SimEvents.Kind.EFFECT, -1, e.point.duplicate(), e.set)
			continue
		var d := Vector2i(e.direction[0], e.direction[1])
		match e.index & 0x7F:
			0:
				_spray(fight, 1, 6, e.point, d)
			1:
				_spray(fight, 2, 20, e.point, d)
			2:
				burn(fight, e.set, events)
			3:
				_spray(fight, 12, 6, e.point, d)
			4:
				_spray(fight, 13, 20, e.point, d)


## FUN_8006F4BC: the announcer's follow-up sound once its voice ends.
static func announcer_follow_up(fight: FightState) -> void:
	alloc(fight, 16)
