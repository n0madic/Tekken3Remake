class_name Opponents
extends RefCounted
## The CPU opponents of the modes (arcade.ovl; modes.md#arcade-ladder): the arcade ladder
## (FUN_800B2494), the team battle teams (FUN_800B2724, screens_sim.team_fill) and the survival
## picks (FUN_800B2B98, screens_sim.survival_pick). The picks draw from the frame generator
## (FUN_8004D13C, `x·5 + 1` at 0x8009F650).

const CHARACTERS := 22
const ORIGINAL_TEN := 0x3FF
const LADDER_EXCLUDED := 0xFFEF9FFF  ## stages 5–8: no Heihachi, Ogre or True Ogre
const TIME_ATTACK_MASK := 0x157FFF
const ARCADE_MASK := 0x1FFFFF
const GON_BIT := 0x20000
const LADDER_STAGES := 10
const TEAM_POOL := 0x1F7FFF
const TEAM_MET := 0x74               ## mode context: u16 per character, the team battle met counts
const SURVIVAL_POOLS := [0x3FF, 0xFBFFF, 0x1FFFFF]
const SURVIVAL_RING := 0x50          ## mode context: the last four opponents
const SURVIVAL_RING_INDEX := 0x4C
const SURVIVAL_MET := 0x60           ## mode context: u16 per character
const SURVIVAL_WINS := 0x44
const SURVIVAL_NEXT := 0x48


## FUN_8004D13C: the frame generator's next value.
static func frame_random(fight: FightState) -> int:
	fight.frame_rng = (fight.frame_rng * 5 + 1) & 0xFFFFFFFF
	return fight.frame_rng


## FUN_8004D068: a stable insertion sort of (id, key) pairs by the unsigned key.
static func sort_pairs(pairs: Array[Vector2i], ascending: bool) -> void:
	for i in pairs.size() - 1:
		var j := i
		while j >= 0:
			var a := pairs[j].y
			var b := pairs[j + 1].y
			if not (b < a if ascending else a < b):
				break
			var t := pairs[j]
			pairs[j] = pairs[j + 1]
			pairs[j + 1] = t
			j -= 1


static func _bits(mask: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for c in CHARACTERS:
		if (mask >> c) & 1:
			out.append(c)
	return out


## Draws one of `pool`'s first `count[0]` entries and moves the last into its place.
static func _draw(fight: FightState, pool: PackedInt32Array, count: PackedInt32Array) -> int:
	var i := frame_random(fight) % count[0]
	var c := pool[i]
	pool[i] = pool[count[0] - 1]
	count[0] -= 1
	return c


## FUN_800B2494: the ten stages (character, costume, stage index) at the mode context's +0x90,
## for the player's costume key `key`.
static func build_ladder(g: GameFlow, key: int) -> void:
	var region := g.region
	var boss := Character.JIN if key >> 2 == Character.HEIHACHI else Character.HEIHACHI
	var pool_mask := 0
	if region.mode == GameMode.TIME_ATTACK:
		pool_mask = g.progress.unlocked & TIME_ATTACK_MASK
	else:
		pool_mask = g.progress.unlocked & ARCADE_MASK
		if g.progress.ball_played != 0:
			pool_mask |= GON_BIT
	var left := pool_mask & LADDER_EXCLUDED & ~(1 << ((key >> 2) & 31)) & ~(1 << boss)
	var at := ModeRegion.CONTEXT + 0x90
	var pool := _bits(left & ORIGINAL_TEN)
	var count := PackedInt32Array([pool.size()])
	var stage := 0
	while stage < 4:
		var c := _draw(g.fight, pool, count)
		left &= ~(1 << c)
		region.put8(at + 4 * stage, c)
		stage += 1
	pool = _bits(left)
	count[0] = pool.size()
	while stage < 8:
		region.put8(at + 4 * stage, _draw(g.fight, pool, count))
		stage += 1
	region.put8(at + 4 * 8, boss)
	region.put8(at + 4 * 9, Character.OGRE)
	for i in LADDER_STAGES:
		# The costume: 1 when the player's is not costume 0; Ogre and True Ogre always 0.
		var c := region.u8(at + 4 * i)
		region.put8(at + 4 * i + 2, i)
		region.put8(at + 4 * i + 1, 0 if c == Character.TRUE_OGRE or c == Character.OGRE else (1 if key & 3 != 0 else 0))


## FUN_800B2724: completes a team (13 bytes at `team`: members as costume keys, +10 count chosen,
## +11 costume, +12 size) from the unlocked characters not in it. With `active` set (meant for a
## CPU team; the game passes the side's active flag, bug #60) and three or more members, one of
## the two least-used characters is taken first. The rest come at random from the characters met least often in team
## battle, widening the met-count window until there are enough, shuffled into the free places.
static func team_fill(g: GameFlow, active: int, team: int, other: int) -> void:
	var region := g.region
	var fight := g.fight
	var size := region.u8(team + 12)
	var chosen_count := region.u8(team + 10)
	var avail := g.progress.unlocked & TEAM_POOL
	for i in chosen_count:
		avail &= ~(1 << ((region.u8(team + i) >> 2) & 31))
	var extra := 0
	var chosen := 0
	if active != 0 and size >= 3:
		var pairs: Array[Vector2i] = []
		for c in _bits(avail):
			pairs.append(Vector2i(c, g.progress.usage(c)))
		if not pairs.is_empty():
			sort_pairs(pairs, true)
		if pairs.size() >= 2:
			extra = 1
			var c := pairs[frame_random(fight) & 1].x
			chosen |= 1 << (c & 31)
			avail &= ~(1 << (c & 31))
	var met: Array[Vector2i] = []
	for c in _bits(avail):
		met.append(Vector2i(c, region.ctx16(TEAM_MET + 2 * c)))
	if not met.is_empty():
		sort_pairs(met, true)
	var need := size - (chosen_count + extra)
	var tolerance := 0
	var n := 0
	while not met.is_empty():
		var threshold := (met[0].y + tolerance) & 0xFFFFFFFF
		n = 0
		while n < met.size() and not threshold < met[n].y:
			n += 1
		if not n < need:
			break
		tolerance += 1
	var pool_mask := 0
	for k in n:
		pool_mask |= 1 << (met[k].x & 31)
	var pool := _bits(pool_mask)
	var count := PackedInt32Array([pool.size()])
	for i in range(extra, size - chosen_count):
		chosen |= 1 << (_draw(fight, pool, count) & 31)
	pool = _bits(chosen)
	count[0] = pool.size()
	var costume := region.u8(team + 11)
	for s in range(chosen_count, size):
		var c := _draw(fight, pool, count)
		var key := (c * 4 + costume) & 0xFF
		for i in region.u8(other + 10):
			if region.u8(other + i) == key:
				key = (c * 4 + (costume ^ 1)) & 0xFF
				break
		region.put8(team + s, key)
	for i in size:
		var c := region.u8(team + i) >> 2
		region.ctx_put16(TEAM_MET + 2 * c, region.ctx16(TEAM_MET + 2 * c) + 1)


## FUN_800B2B98: the next survival opponent (a costume key at +0x48). By the stage counter the
## pool is the ten original characters (stages 0–6), all but Ogre and True Ogre (7–16), then all,
## always within 0x157FFF, without the last four opponents. The pick is random among those met
## least often (within 4 of the least from 20 wins on), in a costume from the frame counter.
static func survival_pick(g: GameFlow) -> void:
	var region := g.region
	var stage := region.ctx32(0x24)
	var mask: int = SURVIVAL_POOLS[0] if stage < 7 else (SURVIVAL_POOLS[2] if stage >= 0x11 else SURVIVAL_POOLS[1])
	mask &= TIME_ATTACK_MASK
	for i in 4:
		var v := region.ctx32(SURVIVAL_RING + 4 * i)
		if v != CHARACTERS:
			mask &= ~(1 << (v & 31))
	var pairs: Array[Vector2i] = []
	for c in _bits(mask):
		pairs.append(Vector2i(c, region.ctx16(SURVIVAL_MET + 2 * c)))
	if not pairs.is_empty():
		sort_pairs(pairs, true)
	var threshold := (pairs[0].y + (4 if region.ctx32(SURVIVAL_WINS) >= 0x14 else 0)) & 0xFFFFFFFF
	var n := 0
	while n < pairs.size() and not threshold < pairs[n].y:
		n += 1
	var c := pairs[frame_random(g.fight) % n].x
	region.ctx_put32(SURVIVAL_NEXT, c * 4 + (g.fight.vblank & 1))
	var index := region.ctx32(SURVIVAL_RING_INDEX) + 1
	if index >= 4:
		index = 0
	region.ctx_put32(SURVIVAL_RING_INDEX, index)
	region.ctx_put32(SURVIVAL_RING + 4 * index, c)
