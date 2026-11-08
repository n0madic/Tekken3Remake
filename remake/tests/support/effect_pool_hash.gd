class_name EffectPoolHash
extends RefCounted
## A running hash of the effect pool after each simulated frame: a
## characterization, not a proof against the game. No trace holds the objects' fields (the shared `rand()`
## guards their draws and the hit segments their reach), so what the presentation reads from them (model,
## flipbook frame, position, counters) is guarded only by this. A change that is meant to move the pool has
## to move the hashes with it (tests/support/effect_pool_hashes.gd); one that is not must leave them as they are.

const PRIME := 0x100000001B3
const MASK := 0xFFFFFFFFFFFF            ## 48 bits: a hash a test table and a message can hold exactly

var value := 0x811C9DC5


func add(pool: EffectPool) -> void:
	_mix(pool.objects.size())
	for o: EffectObjects.Obj in pool.objects:
		for v: int in [o.type, o.flags, o.state, o.model, o.pitch, o.yaw, o.speed, o.vx, o.vy, o.vz, o.x, o.y, o.z,
				o.px, o.py, o.pz, o.a, o.b, o.c, o.d, o.clut, o.tpage, o.uv, o.uv_table, 1 if o.gone else 0]:
			_mix(v)
	for v: int in [pool.live, pool.replay_glows, pool.end_cleared, pool.burn_flags, pool.glow_mask[0],
			pool.glow_mask[1], pool.counter, pool.echo_voice]:
		_mix(v)
	for owner: Array in pool.segments:
		_mix(owner.size())
		for segment: PackedInt32Array in owner:
			for v: int in segment:
				_mix(v)
	_mix(pool.lights.size())
	for light: PackedInt32Array in pool.lights:
		for v: int in light:
			_mix(v)


func _mix(v: int) -> void:
	value = ((value ^ v) * PRIME) & MASK
