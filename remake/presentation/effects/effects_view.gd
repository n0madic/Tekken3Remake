class_name EffectsView
extends Node3D
## Draws the flipbook effects the simulation requests (effects.md#flipbook-ring): camera-facing
## sprites with HDR additive or 50 % blending, the character sets' decaying point light, and
## the six-puff landing dust ring. The simulation's EFFECTS_DRAW says each step whether they are
## drawn and whether they advance a frame; sprite and light nodes are pooled, sprites share one quad mesh.
##
## Sizes follow FUN_80077158: a 32-texel frame covers 32·0x2E0B/H world units at the game's
## projection distance H = 500 (754 units). Additive sprites fade over their last 10 frames.
##
## Depth: the game files a sprite in the ordering table 440 units nearer than its centre (the dust
## ring: nearest of all), so it is drawn over the fighter it hits; the fighters' faces stand at their
## own entries, and flipbook.gdshaderinc draws a sprite at the depth of its entry for the depth test
## to give the same order.
##
## Tekken Ball: the game files a whole sprite in the ordering table 0x6E depth units (OTZ, a quarter
## of the world depth) nearer than its centre, and the ball as one entry at its centre, so a spark
## near the ball is drawn over all of it. The remake's ball is a solid sphere that would cut the
## spark where it passes through, so `place` draws such a spark in front of the sphere, along the
## same view ray and scaled to match: it looks the same, but is not cut.

const ADD_SHADER := preload("res://presentation/effects/flipbook.gdshader")
const HALF_SHADER := preload("res://presentation/effects/flipbook_half.gdshader")
const SPRITE_UNITS := 32.0 * 0x2E0B / 500.0
const SORT_BIAS := 0x6E * 4.0 / WorldSpace.UNITS_PER_METRE   ## FUN_80077158's `(otz − 0x6E) >> 3`, in metres of depth
const BALL_MARGIN := 8.0 / WorldSpace.UNITS_PER_METRE        ## clearance in front of the ball's surface
const MIN_PULL := 0.25                ## the least a sprite is scaled by when pulled toward the camera
const FADE_FRAMES := 10
const LIGHT_FRAMES := 48              ## FUN_8003A160's countdown
const LIGHT_RANGE := 3.0
const LIGHT_ENERGY := 1.0
const HDR_BOOST := 1.6                ## additive sprites are brighter than white for the glow
const DRIFT := 0x1900                 ## EffectSpawn: the drift speed (position << 7 units a frame)
const DRIFT_DECAY := 0x76 / 128.0     ## FUN_80077158: the drift speed is multiplied by this before each step

class Sprite:
	var node: MeshInstance3D
	var additive_material: ShaderMaterial
	var half_material: ShaderMaterial
	var material: ShaderMaterial          ## the one of the two the flipbook's blending uses
	var book: EffectData.Flipbook
	var frame := 0                    ## 1-based once running; 0 before its start delay ends
	var delay := 0
	var mirrored := false             ## the frame's left and right swapped (FUN_80077158's record +0x3C)
	var velocity := Vector3.ZERO      ## the drift per frame (Godot units)
	var at := Vector3.ZERO            ## where the effect is; the node is there unless `place` pulls it toward the camera

class Light:
	var node: OmniLight3D
	var left := LIGHT_FRAMES
	var colour: Color

var data: EffectData
var character: Array[EffectData.Flipbook] = []   ## sets 0 and 1: the fighters' flipbooks
var sprites: Array[Sprite] = []
var lights: Array[Light] = []
var objects := EffectObjectsView.new()
var flipbooks := Node3D.new()        ## the sprites and lights, hidden on steps that do not draw them
var _free: Array[Sprite] = []        ## ended sprites, reused by the next spawns
var _free_lights: Array[OmniLight3D] = []   ## ended lights, hidden, reused by the next ones
var _quad := QuadMesh.new()
## The arcade's hit colour GREEN (ArcadeSettings.hit_colour): the hit's flipbook (system set 0, the
## only record with the exchange word) has red and green exchanged.
var green_hit := false


func setup(effects: EffectData) -> void:
	data = effects
	character = data.character.duplicate()
	objects.setup(data)
	add_child(objects)
	add_child(flipbooks)
	_quad.size = Vector2.ONE * SPRITE_UNITS / WorldSpace.UNITS_PER_METRE


## The fight's character flipbooks (sets 0 and 1) by the fighters' costume slots.
func set_costumes(slots: PackedInt32Array) -> void:
	character.clear()
	for slot in slots:
		character.append(data.costume(slot))
	objects.set_costumes(character)


## The set's flipbook from another costume slot's (the arcade's scenes).
func set_book(set_index: int, slot: int) -> void:
	character[set_index] = data.costume(slot)


## One simulation step: ends every effect on EFFECTS_CLEAR, advances the running ones when
## EFFECTS_DRAW says so, starts the step's new ones, and shows them only if the step draws them.
func step(events: SimEvents) -> void:
	if events.has(SimEvents.Kind.EFFECTS_CLEAR):
		clear()
	var draw := events.first(SimEvents.Kind.EFFECTS_DRAW)
	flipbooks.visible = draw != null
	if draw != null and draw.a == SimEvents.EFFECTS_ADVANCE:
		_advance()
	for e in events.items:
		if e.kind == SimEvents.Kind.EFFECT_BOOK:
			set_book(e.a, e.b)
		if e.point.is_empty():
			continue
		var at := WorldSpace.point_i(e.point)
		match e.kind:
			SimEvents.Kind.EFFECT:
				_character(e.a, at, Vector3.ZERO, e.mirrored)
			SimEvents.Kind.SPARK:
				if e.a < data.system.size():
					_spawn(data.system[e.a], at, 0, Vector3.ZERO, e.mirrored)
			SimEvents.Kind.HIT_SPARK:
				# HitSpawnEffect: set 3 index 0 (hit), 1 (no damage) or 2 (guard); a damaging
				# hit from 21 on adds the attacker's character flipbook. Both drift along the hit
				# direction (EffectSpawn) and are mirrored by which way it goes on the screen.
				var drift := drift_of(e.vector)
				if e.a < data.system.size():
					_spawn(data.system[e.a], at, 0, drift, e.mirrored)
				if e.a == 0 and e.b >= EffectObjects.SPARK_DAMAGE:
					_character(e.c, at, drift, e.mirrored)
			SimEvents.Kind.DUST, SimEvents.Kind.LANDING_DUST:
				for i in data.dust_offsets.size():
					var o := data.dust_offsets[i]
					var p := WorldSpace.point(e.point[0] + o.x, data.dust_y + o.y, e.point[2] + o.z)
					_spawn(data.dust, p, i * data.dust_interval, Vector3.ZERO, false, true)


## The step's effect objects: the pool as its update drew it (EFFECT_OBJECTS_DRAW), none on a step
## that did not run it. The arcade's scenes do not, so a replay skipped with sparks in flight leaves
## them in the pool undrawn until True Ogre's round clears it (issue n0madic/Tekken3Remake#37).
func show_objects(events: SimEvents, pool: EffectPool) -> void:
	if events.has(SimEvents.Kind.EFFECT_OBJECTS_DRAW):
		objects.show_pool(pool)
	else:
		objects.clear()


## Every rendered frame, with the camera's position and viewing direction and Tekken Ball's solid
## ball as `BallView.occluder` gives it: the sprites the game draws over the ball are placed clear
## of the sphere (`pull_over_ball`), the others where they are; the effect objects likewise.
func place(eye: Vector3, forward: Vector3, ball: Vector4) -> void:
	objects.set_ball(ball)
	objects.place_glow(eye, forward, ball)
	for s in sprites:
		var k := pull_over_ball(eye, forward, s.at, ball)
		s.node.position = eye + (s.at - eye) * k
		s.node.scale = Vector3.ONE * k


## The factor, 1 or less, that moves a sprite centred at `at` along its view ray from `eye` (and
## scales it) so that its plane is just in front of the ball sphere `ball` = (centre, radius):
## 1 for a sprite the game draws behind the ball (its centre more than SORT_BIAS beyond the ball's
## centre), one clear of the sphere already, or one too far from it to touch it.
static func pull_over_ball(eye: Vector3, forward: Vector3, at: Vector3, ball: Vector4) -> float:
	if ball.w <= 0.0:
		return 1.0
	var centre := Vector3(ball.x, ball.y, ball.z)
	if at.distance_to(centre) >= ball.w + SPRITE_UNITS / WorldSpace.UNITS_PER_METRE * 0.5 * sqrt(2.0):
		return 1.0
	var depth := (at - eye).dot(forward)
	var ball_depth := (centre - eye).dot(forward)
	var front := ball_depth - ball.w - BALL_MARGIN
	if depth - SORT_BIAS >= ball_depth or depth <= front or front <= 0.0:
		return 1.0
	return maxf(front / depth, MIN_PULL)


func clear() -> void:
	objects.clear()
	for s in sprites:
		_release(s)
	for l in lights:
		_release_light(l)
	sprites.clear()
	lights.clear()


## EffectSpawn's initial drift: 0x1900 / 128 game units a frame along the hit direction (none without
## one); `_advance` decays it by DRIFT_DECAY each frame.
static func drift_of(direction: PackedInt32Array) -> Vector3:
	if direction.size() < 3:
		return Vector3.ZERO
	var d := Vector3(direction[0], direction[1], direction[2])
	var length := sqrt(d.length_squared())
	if length == 0.0:
		return Vector3.ZERO
	return WorldSpace.point(d.x, d.y, d.z) * (DRIFT / 128.0 / length)


func _character(set_index: int, at: Vector3, drift := Vector3.ZERO, mirrored := false) -> void:
	if set_index < 0 or set_index >= character.size():
		return
	var book := character[set_index]
	if book != null:
		_spawn(book, at, 0, drift, mirrored)
		_light(at, book.light)


func _spawn(book: EffectData.Flipbook, at: Vector3, delay: int, drift := Vector3.ZERO, mirrored := false, over_all := false) -> void:
	if book == null:
		return
	var s: Sprite = _free.pop_back() if not _free.is_empty() else _new_sprite()
	s.book = book
	s.delay = delay
	s.mirrored = mirrored
	s.velocity = drift
	s.frame = 0 if delay > 0 else 1
	s.material = s.additive_material if book.additive else s.half_material
	s.node.material_override = s.material
	s.material.set_shader_parameter("albedo_texture", book.texture)
	s.material.set_shader_parameter("frame_scale", (-1.0 if mirrored else 1.0) / book.frames)
	s.material.set_shader_parameter("over_all", over_all)
	s.material.set_shader_parameter("exchange_red_green", green_hit and not data.system.is_empty() and book == data.system[0])
	s.at = at
	s.node.position = at
	s.node.scale = Vector3.ONE
	sprites.append(s)
	_paint(s)


func _new_sprite() -> Sprite:
	var s := Sprite.new()
	s.additive_material = _new_material(ADD_SHADER)
	s.half_material = _new_material(HALF_SHADER)
	s.node = MeshInstance3D.new()
	s.node.mesh = _quad
	s.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flipbooks.add_child(s.node)
	return s


## A sprite's material: the shader keeps the quad facing the camera (scaled by the node's, which
## `place` changes near the ball) and sets its depth (flipbook.gdshaderinc).
static func _new_material(shader: Shader) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("units_per_metre", WorldSpace.UNITS_PER_METRE)
	material.set_shader_parameter("depth_near", FaceKeys.NEAR_CLAMP)
	return material


## An ended sprite goes back to the pool, hidden.
func _release(s: Sprite) -> void:
	s.node.visible = false
	s.book = null
	_free.append(s)


func _light(at: Vector3, colour: Color) -> void:
	if colour == Color.BLACK:
		return
	var l := Light.new()
	l.colour = colour
	if _free_lights.is_empty():
		l.node = OmniLight3D.new()
		l.node.omni_range = LIGHT_RANGE
		flipbooks.add_child(l.node)
	else:
		l.node = _free_lights.pop_back()
		l.node.visible = true
	l.node.light_color = colour
	l.node.position = at
	lights.append(l)
	_paint_light(l)


## An ended light's node goes back to the pool, hidden.
func _release_light(l: Light) -> void:
	l.node.visible = false
	_free_lights.append(l.node)


## One frame of the running sprites and lights; the ended ones leave in order.
func _advance() -> void:
	var kept := 0
	for i in sprites.size():
		var s := sprites[i]
		if s.delay > 0:
			s.delay -= 1
			if s.delay == 0:
				s.frame = 1
		else:
			s.frame += 1
			s.velocity *= DRIFT_DECAY
			s.at += s.velocity
			s.node.position = s.at
		if s.frame > s.book.frames:
			_release(s)
		else:
			_paint(s)
			sprites[kept] = s
			kept += 1
	sprites.resize(kept)
	kept = 0
	for i in lights.size():
		var l := lights[i]
		l.left -= 1
		if l.left <= 0:
			_release_light(l)
		else:
			_paint_light(l)
			lights[kept] = l
			kept += 1
	lights.resize(kept)


func _paint(s: Sprite) -> void:
	s.node.visible = s.frame > 0
	if s.frame <= 0:
		return
	# A mirrored frame is read from its right edge to its left: the offset is the frame's end.
	s.material.set_shader_parameter("frame_offset", float(s.frame if s.mirrored else s.frame - 1) / s.book.frames)
	var level := 1.0
	if s.book.additive:
		var into_fade := s.frame - s.book.frames + FADE_FRAMES
		if into_fade > 0:
			level = (128.0 - (into_fade * 0x9999 >> 12)) / 128.0
		s.material.set_shader_parameter("tint", Color(level, level, level) * HDR_BOOST)
	else:
		s.material.set_shader_parameter("tint", Color(1, 1, 1, 0.5))


func _paint_light(l: Light) -> void:
	l.node.light_energy = LIGHT_ENERGY * float(l.left) / LIGHT_FRAMES
