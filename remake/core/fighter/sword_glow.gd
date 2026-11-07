class_name SwordGlow
extends RefCounted
## The glow along Yoshimitsu's sword (docs/research/code/effects.md#sword-glow): FUN_80031980 and
## its set-up FUN_8003161C. A ribbon of ten additive quads in the plane of the screen, built every
## frame from the four blade points of joint 10 (the sword hand) as the GTE projects them.
##
## `Ribbon` holds what the game puts in its quads: eighteen screen points (six on the centre
## line, six on each edge), the depth entry of the four blade points and the colour of the
## centre line. The edges and the ends of the line are black, so the glow fades towards them
## (`lit()`). The arcade models' glow is another routine (ArcadeSwordGlow), built from the same
## projected points; Tekken Force's models have none.
##
## Proven against the game's code by tools/research/verify_sword_glow.py (the Python port,
## `sword_glow.py`) and by tests/core/test_sword_glow.gd (its cases, `sword_glow_cases.py`).

const SWORD_JOINT := 10
const YOSHIMITSU := 4
const MOKUJIN := 15
const YOSHIMITSU_BANK := 4
## The blade's four points in the sword joint's axes (0x80095BA0), x, y, z each.
const BLADE: Array[int] = [60, -150, 0, 50, -550, 0, 30, -720, 0, -60, -950, 0]
## The quads (0x80019F24): four point numbers (0–5 the centre line, 6–11 and 12–17 the edges) and
## the blade point whose depth files the quad.
const QUAD_POINTS: Array[int] = [
	0, 1, 12, 13, 0,   1, 2, 13, 14, 1,   2, 3, 14, 15, 2,   3, 4, 15, 16, 3,   5, 4, 17, 16, 3,
	0, 1, 6, 7, 0,    1, 2, 7, 8, 1,     2, 3, 8, 9, 2,     3, 4, 9, 10, 3,    5, 4, 11, 10, 3,
]
const QUADS := 10
const QUAD_STRIDE := 5
## Which of a quad's first two corners are on the centre line (bit 0, bit 1): the quads at the
## ends of each half start black.
const LIT: Array[int] = [2, 3, 3, 3, 2, 2, 3, 3, 3, 2]
const POINTS := 18
const WIDTH := 2000                      ## the half width is WIDTH / depth, in screen units
const NEAR_WIDTH := 200                  ## when the first point's depth is 9 or less
const NEAR_DEPTH := 9
const DEPTH_SHIFT := 5                   ## the entry of a point is SZ >> 5 (32 units)
const DEPTH_BIAS := 8                    ## the quads are filed this many entries nearer
const ENTRY_MASK := 0x3FF
## Vertex colours of the centre line by costume slot, for the frame's display buffer 0 and 1 (the
## second is dimmer, so the glow pulses): Yoshimitsu's costumes 8 and 9, then Mokujin's.
const COLOUR_GREEN: Array[int] = [0x18, 0x30, 0x18, 0x0C, 0x1E, 0x0C]
const COLOUR_RED: Array[int] = [0x48, 0x1E, 0x1E, 0x30, 0x18, 0x18]
const COLOUR_ORANGE: Array[int] = [0x3C, 0x1E, 0x0C, 0x1E, 0x12, 0x0C]
const SLOT_GREEN := 8
const SLOT_RED := 9


## What one frame's glow is made of.
class Ribbon:
	var points := PackedInt32Array()         ## POINTS (x, y) pairs, in the GTE's screen units
	var depth := PackedInt32Array()          ## the four blade points' ordering-table entries
	var colour := Vector3i.ZERO              ## the centre line's vertex colour, 0x80 = full
	var textured := false                    ## ArcadeSwordGlow's: the colour is the quad's, shaded by its picture


## FUN_80031980's test: Yoshimitsu, or Mokujin while he fights with Yoshimitsu's moves.
static func shown(f: FighterState) -> bool:
	return f.char_id == YOSHIMITSU or (f.char_id == MOKUJIN and f.bank_type == YOSHIMITSU_BANK)


## The centre line's colour for a costume slot in a display buffer.
static func colour_of(slot: int, buffer: int) -> Vector3i:
	var table := COLOUR_ORANGE
	if slot == SLOT_GREEN:
		table = COLOUR_GREEN
	elif slot == SLOT_RED:
		table = COLOUR_RED
	var o := 3 * (buffer & 1)
	return Vector3i(table[o], table[o + 1], table[o + 2])


## The frame's ribbon of fighter `f` seen with `view` (the fighters' view) in display buffer
## `buffer`, null when it has none.
static func ribbon(f: FighterState, view: ViewMatrix, t: FightTables, buffer: int) -> Ribbon:
	if not shown(f):
		return null
	return build(f.body.joints[SWORD_JOINT], view, t, f.costume_slot, buffer)


## The ribbon of the sword joint's block `block`, whoever it belongs to.
static func build(block: JointFrame, view: ViewMatrix, t: FightTables, slot: int, buffer: int) -> Ribbon:
	var out := Ribbon.new()
	var xy: Array[Vector2i] = []
	project(block, view, out.depth, xy)
	out.points = _points(xy, out.depth, t)
	out.colour = colour_of(slot, buffer)
	return out


## FUN_80037AB0 on the view and the sword's block, then FUN_80036D4C on the blade points: their
## screen positions and depth entries (SZ >> 5).
static func project(block: JointFrame, view: ViewMatrix, depth: PackedInt32Array, xy: Array[Vector2i]) -> void:
	var rot := Fx.mul_matrix(view.rot, block.rot)
	var moved := Gte.apply_lv(view.rot, block.t)
	var shift := PackedInt32Array([Fx.w32(moved[0] + view.t[0]), Fx.w32(moved[1] + view.t[1]), Fx.w32(moved[2] + view.t[2])])
	for i in BLADE.size() / 3:
		var v := Gte.apply(rot, BLADE[3 * i], BLADE[3 * i + 1], BLADE[3 * i + 2])
		var at := PackedInt32Array([Fx.w32(v[0] + shift[0]), Fx.w32(v[1] + shift[1]), Fx.w32(v[2] + shift[2])])
		var s := Gte.rtps_origin(at, view.h, ViewMatrix.SCREEN_OFFSET_X, ViewMatrix.SCREEN_OFFSET_Y)
		xy.append(Vector2i(s[0], s[1]))
		depth.append(s[2] >> DEPTH_SHIFT)


## The eighteen points from the four projected ones. P1 to P4 are the projected points, P0 and P5
## the line's ends, one width beyond them along the first and the last segment; the half width is
## WIDTH / depth of the first point. P0 to P5 get a point on each side of the line, at right
## angles to the first segment for the first three and to the last for the others; the sides of
## the two ends are a quarter narrower, and P5 reaches a quarter of the width further after its
## sides are made.
static func _points(xy: Array[Vector2i], depth: PackedInt32Array, t: FightTables) -> PackedInt32Array:
	var width := WIDTH / depth[0] if depth[0] > NEAR_DEPTH else NEAR_WIDTH
	var d := offsets(xy, width, t)
	var dy_a := d[0]
	var dx_a := d[1]
	var dy_b := d[2]
	var dx_b := d[3]
	var centre: Array[Vector2i] = [Vector2i.ZERO, xy[0], xy[1], xy[2], xy[3], Vector2i.ZERO]
	centre[0] = Vector2i(Fx.s16(xy[0].x - dx_a), Fx.s16(xy[0].y - dy_a))
	centre[5] = Vector2i(Fx.s16(xy[3].x + dx_b), Fx.s16(xy[3].y + dy_b))
	var out := PackedInt32Array()
	out.resize(2 * POINTS)
	var dy := dy_a
	var dx := dx_a
	var quarter_x := 0
	var quarter_y := 0
	for k in 6:
		if k == 3:
			dy = dy_b
			dx = dx_b
		var p := centre[k]
		var ax := Fx.s16(p.x + dy)
		var ay := Fx.s16(p.y - dx)
		var bx := Fx.s16(p.x - dy)
		var by := Fx.s16(p.y + dx)
		quarter_y = dx >> 2
		quarter_x = dy >> 2
		if k == 0 or k == 5:
			ax = Fx.s16(ax - quarter_x)
			ay = Fx.s16(ay + quarter_y)
			bx = Fx.s16(bx + quarter_x)
			by = Fx.s16(by - quarter_y)
		out[2 * k] = p.x
		out[2 * k + 1] = p.y
		out[2 * (6 + k)] = ax
		out[2 * (6 + k) + 1] = ay
		out[2 * (12 + k)] = bx
		out[2 * (12 + k) + 1] = by
	out[10] = Fx.s16(out[10] + quarter_y)
	out[11] = Fx.s16(out[11] + quarter_x)
	return out


## The half width `width` as (dy, dx) at right angles to the first segment of the projected points
## (P1 to P2) and to the last (P3 to P4): the cosine and the sine of the segment's angle times the
## width in 4.12, towards zero. Both routines build their edges from these.
static func offsets(xy: Array[Vector2i], width: int, t: FightTables) -> PackedInt32Array:
	var angle_a := Gte.ratan2(xy[1].x - xy[0].x, xy[1].y - xy[0].y, t.fighter.ratan) & 0xFFF
	var angle_b := Gte.ratan2(xy[3].x - xy[2].x, xy[3].y - xy[2].y, t.fighter.ratan) & 0xFFF
	return PackedInt32Array([
		Fx.trunc12(FightMath.cos12(angle_a, t) * width), Fx.trunc12(FightMath.sin12(angle_a, t) * width),
		Fx.trunc12(FightMath.cos12(angle_b, t) * width), Fx.trunc12(FightMath.sin12(angle_b, t) * width)])


## The point number of corner `v` of quad `q`.
static func corner(q: int, v: int) -> int:
	return QUAD_POINTS[QUAD_STRIDE * q + v]


## Whether corner `v` (0–3) of quad `q` is coloured: only the first two can be.
static func lit(q: int, v: int) -> bool:
	return v < 2 and (LIT[q] >> v) & 1 != 0


## The ordering-table entry of quad `q`: its blade point's entry less DEPTH_BIAS, wrapped.
static func entry(glow: Ribbon, q: int) -> int:
	return (glow.depth[QUAD_POINTS[QUAD_STRIDE * q + 4]] - DEPTH_BIAS) & ENTRY_MASK
