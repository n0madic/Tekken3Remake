class_name ArcadeSwordGlow
extends RefCounted
## The glow along Yoshimitsu's sword on the arcade's models (docs/research/code/effects.md#sword-glow):
## FUN_80192ecc. The same ribbon of ten quads in the plane of the screen as the PlayStation's
## (SwordGlow), built from the same four blade points of the sword hand, but
##
## - the half width is WIDTH / depth of the first point (WIDTH when that is 0) and the ribbon's ends
##   are as wide as the rest;
## - each quad is flat coloured and textured with a 16 × 16 picture, a ramp from black at the edges
##   to white on the centre line that also darkens towards the ribbon's ends (`uv()`, the levels of
##   the picture are the converter's: characters/arcade_sword_glow.json); the colour is the
##   costume's and brighter on the frames of one parity, so the glow pulses.
##
## Proven against the game's code by tools/research/verify_arcade_sword_glow.py (the Python port,
## `arcade_sword_glow.py`) and by tests/core/test_arcade_sword_glow.gd (its cases,
## `arcade_sword_glow_cases.py`).

## The quads' texels (u, v) per corner in the 16 × 16 picture, eight values a quad (0x8015F0C4).
const PICTURE := 16
const UV: Array[int] = [
	15, 0, 15, 15, 0, 0, 0, 15,
	15, 15, 15, 15, 0, 15, 0, 15,
	15, 15, 15, 15, 0, 15, 0, 15,
	15, 15, 15, 15, 0, 15, 0, 7,
	15, 0, 15, 15, 0, 0, 0, 7,
	15, 0, 15, 15, 0, 0, 0, 15,
	15, 15, 15, 15, 0, 15, 0, 15,
	15, 15, 15, 15, 0, 15, 0, 15,
	15, 15, 15, 15, 0, 15, 0, 7,
	15, 0, 15, 15, 0, 0, 0, 7,
]
## The colour (0x80 = full) by costume slot on the frames of even and odd parity: slot 8 green, slot
## 9 red, any other (Mokujin) orange.
const COLOUR_GREEN: Array[int] = [0x10, 0x28, 0, 0x20, 0x40, 0]
const COLOUR_RED: Array[int] = [0x40, 0x20, 0, 0x60, 0x28, 0]
const COLOUR_ORANGE: Array[int] = [0x28, 0x18, 0, 0x50, 0x28, 0]


## The colour of the quads for a costume slot on a frame whose counter has parity `parity`.
static func colour_of(slot: int, parity: int) -> Vector3i:
	var table := COLOUR_ORANGE
	if slot == SwordGlow.SLOT_GREEN:
		table = COLOUR_GREEN
	elif slot == SwordGlow.SLOT_RED:
		table = COLOUR_RED
	var o := 3 * (parity & 1)
	return Vector3i(table[o], table[o + 1], table[o + 2])


## The frame's ribbon of fighter `f` seen with `view` (the fighters' view), null when it has none
## (SwordGlow.shown). `parity` is the frame counter's low bit.
static func ribbon(f: FighterState, view: ViewMatrix, t: FightTables, parity: int) -> SwordGlow.Ribbon:
	if not SwordGlow.shown(f):
		return null
	return build(f.body.joints[SwordGlow.SWORD_JOINT], view, t, f.costume_slot, parity)


## The ribbon of the sword joint's block `block`, whoever it belongs to.
static func build(block: JointFrame, view: ViewMatrix, t: FightTables, slot: int, parity: int) -> SwordGlow.Ribbon:
	var out := SwordGlow.Ribbon.new()
	var xy: Array[Vector2i] = []
	SwordGlow.project(block, view, out.depth, xy)
	out.points = _points(xy, out.depth, t)
	out.colour = colour_of(slot, parity)
	out.textured = true
	return out


## The eighteen points from the four projected ones: P1 to P4 are the projected points, P0 and P5
## the line's ends one width beyond them along the first and the last segment, and each gets a point
## on either side at right angles to the first segment (P0 to P2) or to the last (P3 to P5).
static func _points(xy: Array[Vector2i], depth: PackedInt32Array, t: FightTables) -> PackedInt32Array:
	var width := SwordGlow.WIDTH if depth[0] == 0 else SwordGlow.WIDTH / depth[0]
	var d := SwordGlow.offsets(xy, width, t)
	var centre: Array[Vector2i] = [
		Vector2i(Fx.s16(xy[0].x - d[1]), Fx.s16(xy[0].y - d[0])), xy[0], xy[1], xy[2], xy[3],
		Vector2i(Fx.s16(xy[3].x + d[3]), Fx.s16(xy[3].y + d[2]))]
	var out := PackedInt32Array()
	out.resize(2 * SwordGlow.POINTS)
	for k in 6:
		var o := 0 if k <= 2 else 2
		var dy := d[o]
		var dx := d[o + 1]
		var p := centre[k]
		out[2 * k] = p.x
		out[2 * k + 1] = p.y
		out[2 * (6 + k)] = Fx.s16(p.x + dy)
		out[2 * (6 + k) + 1] = Fx.s16(p.y - dx)
		out[2 * (12 + k)] = Fx.s16(p.x - dy)
		out[2 * (12 + k) + 1] = Fx.s16(p.y + dx)
	return out


## The texel (u, v) of corner `v` of quad `q` in the picture.
static func uv(q: int, v: int) -> Vector2i:
	return Vector2i(UV[8 * q + 2 * v], UV[8 * q + 2 * v + 1])
