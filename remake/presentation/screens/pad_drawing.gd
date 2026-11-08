class_name PadDrawing
extends RefCounted
## A pad drawn with vector shapes where the conversion has no pad picture (the arcade's set: the
## cabinet has a stick and four buttons, and no key configuration screen). The shapes stand on the
## button places of the PlayStation's picture (SettingsView.BUTTON_SPOTS in its PAD_SIZE units), so
## the key fields' leader lines end on them as they do on the picture.

const BODY := Color(0.17, 0.19, 0.25, 0.95)
const BUTTON := Color(0.27, 0.3, 0.38)
const LINE := Color(0.55, 0.6, 0.75, 0.75)
const MARK := Color(0.75, 0.78, 0.86, 0.6)
const LINE_WIDTH := 1.1                ## outlines, in picture units
const ARC_STEPS := 8
## The body in picture units: a rounded slab and two grips (capsules from, to, radius).
const SLAB := Rect2(6, 36, 132, 70)
const SLAB_RADIUS := 24.0
const GRIPS := [[Vector2(24, 96), Vector2(18, 116), 17.0], [Vector2(120, 96), Vector2(126, 116), 17.0]]
## The buttons' shapes around their places.
const SHOULDERS := {PadState.L2: Vector2(32, 9), PadState.L1: Vector2(36, 11),
	PadState.R2: Vector2(32, 9), PadState.R1: Vector2(36, 11)}
const SHOULDER_RADIUS := 4.0
const FACE_RADIUS := 7.5
const ARM_LENGTH := 13.5               ## a direction pad arm from the centre
const ARM_HALF_WIDTH := 5.5
const PILL_HALF_LENGTH := 4.0           ## Select and Start
const PILL_RADIUS := 2.6
const FACE_BUTTONS: Array[int] = [PadState.TRIANGLE, PadState.SQUARE, PadState.CIRCLE, PadState.CROSS]
const PILLS: Array[int] = [PadState.SELECT, PadState.START]

static var _body := PackedVector2Array()


## Draws the pad into `picture`, which stands for `size` picture units.
static func draw(item: CanvasItem, picture: Rect2, spots: Dictionary, size: Vector2) -> void:
	var scale := picture.size / size
	var xf := Transform2D(0.0, scale, 0.0, picture.position)
	var width := maxf(1.0, LINE_WIDTH * scale.y)
	_shape(item, xf * body(), BODY, width)
	for bit: int in SHOULDERS:
		_shape(item, xf * button_shape(bit, spots), BUTTON, width)
	_shape(item, xf * button_shape(PadState.UP, spots), BUTTON, width)
	var centre := _cross_centre(spots)
	for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		var tip := centre + direction * (ARM_LENGTH - 2.5)
		var side := direction.orthogonal() * 2.5
		var back := tip - direction * 3.5
		item.draw_colored_polygon(xf * PackedVector2Array([tip, back + side, back - side]), MARK)
	for bit in PILLS:
		_shape(item, xf * button_shape(bit, spots), BUTTON, width)
	for bit in FACE_BUTTONS:
		_shape(item, xf * button_shape(bit, spots), BUTTON, width)
		ButtonGlyphs.draw(item, bit, xf * (spots[bit] as Vector2), FACE_RADIUS * scale.y * 0.95)


## The body's outline in picture units: the slab and the grips as one polygon.
static func body() -> PackedVector2Array:
	if _body.is_empty():
		var outline := rounded_rect(SLAB, SLAB_RADIUS)
		for grip: Array in GRIPS:
			outline = _largest(Geometry2D.merge_polygons(outline, capsule(grip[0] as Vector2, grip[1] as Vector2, grip[2] as float)))
		_body = outline
	return _body


## A button's shape in picture units around its place in `spots` (the direction buttons share the cross).
static func button_shape(bit: int, spots: Dictionary) -> PackedVector2Array:
	var at: Vector2 = spots[bit]
	if SHOULDERS.has(bit):
		var extent: Vector2 = SHOULDERS[bit]
		return rounded_rect(Rect2(at - extent / 2.0, extent), SHOULDER_RADIUS)
	if bit & PadState.DIRECTIONS:
		var c := _cross_centre(spots)
		var a := ARM_LENGTH
		var w := ARM_HALF_WIDTH
		return PackedVector2Array([c + Vector2(-w, -a), c + Vector2(w, -a), c + Vector2(w, -w), c + Vector2(a, -w),
			c + Vector2(a, w), c + Vector2(w, w), c + Vector2(w, a), c + Vector2(-w, a), c + Vector2(-w, w),
			c + Vector2(-a, w), c + Vector2(-a, -w), c + Vector2(-w, -w)])
	if bit in PILLS:
		return capsule(at - Vector2(PILL_HALF_LENGTH, 0), at + Vector2(PILL_HALF_LENGTH, 0), PILL_RADIUS)
	return circle(at, FACE_RADIUS)


static func rounded_rect(r: Rect2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	var centres := [Vector2(r.end.x - radius, r.position.y + radius), Vector2(r.end.x - radius, r.end.y - radius),
		Vector2(r.position.x + radius, r.end.y - radius), Vector2(r.position.x + radius, r.position.y + radius)]
	for k in centres.size():
		points.append_array(_arc(centres[k] as Vector2, radius, -PI / 2.0 + k * PI / 2.0, PI / 2.0))
	return points


## A stadium from `a` to `b` with `radius`.
static func capsule(a: Vector2, b: Vector2, radius: float) -> PackedVector2Array:
	var base := (b - a).angle()
	var points := _arc(b, radius, base - PI / 2.0, PI)
	points.append_array(_arc(a, radius, base + PI / 2.0, PI))
	return points


static func circle(at: Vector2, radius: float) -> PackedVector2Array:
	return _arc(at, radius, 0.0, TAU - TAU / (4 * ARC_STEPS), 4 * ARC_STEPS - 1)


static func _arc(at: Vector2, radius: float, from: float, sweep: float, steps := ARC_STEPS) -> PackedVector2Array:
	var points := PackedVector2Array()
	for k in steps + 1:
		points.append(at + Vector2.from_angle(from + sweep * k / steps) * radius)
	return points


static func _cross_centre(spots: Dictionary) -> Vector2:
	return Vector2(((spots[PadState.LEFT] as Vector2).x + (spots[PadState.RIGHT] as Vector2).x) / 2.0,
		((spots[PadState.UP] as Vector2).y + (spots[PadState.DOWN] as Vector2).y) / 2.0)


static func _shape(item: CanvasItem, points: PackedVector2Array, fill: Color, width: float) -> void:
	item.draw_colored_polygon(points, fill)
	var closed := points.duplicate()
	closed.append(points[0])
	item.draw_polyline(closed, LINE, width, true)


## The outer polygon of a union (its holes are smaller).
static func _largest(polygons: Array[PackedVector2Array]) -> PackedVector2Array:
	var best := PackedVector2Array()
	var best_area := -1.0
	for p in polygons:
		var area := absf(_area(p))
		if area > best_area:
			best = p
			best_area = area
	return best


static func _area(p: PackedVector2Array) -> float:
	var sum := 0.0
	for i in p.size():
		sum += p[i].cross(p[(i + 1) % p.size()])
	return sum / 2.0
