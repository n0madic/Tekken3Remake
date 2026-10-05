class_name EffectsView
extends Node3D
## Draws the flipbook effects the simulation requests (effects.md#flipbook-ring): camera-facing
## sprites with HDR additive or 50 % blending, the character sets' decaying point light, and
## the six-puff landing dust ring. The simulation's EFFECTS_DRAW says each step whether they are
## drawn and whether they advance a frame; sprite and light nodes are pooled, sprites share one quad mesh.
##
## Sizes follow FUN_80077158: a 32-texel frame covers 32·0x2E0B/H world units at the game's
## projection distance H = 500 (754 units). Additive sprites fade over their last 10 frames.

const SPRITE_UNITS := 32.0 * 0x2E0B / 500.0
const FADE_FRAMES := 10
const LIGHT_FRAMES := 48              ## FUN_8003A160's countdown
const LIGHT_RANGE := 3.0
const LIGHT_ENERGY := 1.0
const HDR_BOOST := 1.6                ## additive sprites are brighter than white for the glow
const DRIFT := 0x1900                 ## EffectSpawn: the drift speed (position << 7 units a frame)

class Sprite:
	var node: MeshInstance3D
	var material: StandardMaterial3D
	var book: EffectData.Flipbook
	var frame := 0                    ## 1-based once running; 0 before its start delay ends
	var delay := 0
	var velocity := Vector3.ZERO      ## the drift per frame (Godot units)

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
		if e.point.is_empty():
			continue
		var at := WorldSpace.point_i(e.point)
		match e.kind:
			SimEvents.Kind.EFFECT:
				_character(e.a, at)
			SimEvents.Kind.SPARK:
				if e.a < data.system.size():
					_spawn(data.system[e.a], at, 0)
			SimEvents.Kind.HIT_SPARK:
				# HitSpawnEffect: set 3 index 0 (hit), 1 (no damage) or 2 (guard); a damaging
				# hit from 21 on adds the attacker's character flipbook. Both drift along the hit
				# direction (EffectSpawn).
				var drift := drift_of(e.vector)
				if e.a < data.system.size():
					_spawn(data.system[e.a], at, 0, drift)
				if e.a == 0 and e.b >= EffectObjects.SPARK_DAMAGE:
					_character(e.c, at, drift)
			SimEvents.Kind.DUST, SimEvents.Kind.LANDING_DUST:
				for i in data.dust_offsets.size():
					var o := data.dust_offsets[i]
					var p := WorldSpace.point(e.point[0] + o.x, data.dust_y + o.y, e.point[2] + o.z)
					_spawn(data.dust, p, i * data.dust_interval)


func clear() -> void:
	objects.clear()
	for s in sprites:
		_release(s)
	for l in lights:
		_release_light(l)
	sprites.clear()
	lights.clear()


## EffectSpawn's drift: 0x1900 / 128 game units a frame along the hit direction (none without one).
static func drift_of(direction: PackedInt32Array) -> Vector3:
	if direction.size() < 3:
		return Vector3.ZERO
	var d := Vector3(direction[0], direction[1], direction[2])
	var length := sqrt(d.length_squared())
	if length == 0.0:
		return Vector3.ZERO
	return WorldSpace.point(d.x, d.y, d.z) * (DRIFT / 128.0 / length)


func _character(set_index: int, at: Vector3, drift := Vector3.ZERO) -> void:
	if set_index < 0 or set_index >= character.size():
		return
	var book := character[set_index]
	if book != null:
		_spawn(book, at, 0, drift)
		_light(at, book.light)


func _spawn(book: EffectData.Flipbook, at: Vector3, delay: int, drift := Vector3.ZERO) -> void:
	if book == null:
		return
	var s: Sprite = _free.pop_back() if not _free.is_empty() else _new_sprite()
	s.book = book
	s.delay = delay
	s.velocity = drift
	s.frame = 0 if delay > 0 else 1
	s.material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD if book.additive else BaseMaterial3D.BLEND_MODE_MIX
	s.material.albedo_texture = book.texture
	s.material.uv1_scale = Vector3(1.0 / book.frames, 1, 1)
	s.node.position = at
	sprites.append(s)
	_paint(s)


func _new_sprite() -> Sprite:
	var s := Sprite.new()
	s.material = StandardMaterial3D.new()
	s.material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	s.material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	s.material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	s.material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	s.material.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	s.node = MeshInstance3D.new()
	s.node.mesh = _quad
	s.node.material_override = s.material
	s.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flipbooks.add_child(s.node)
	return s


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
			s.node.position += s.velocity
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
	s.material.uv1_offset = Vector3(float(s.frame - 1) / s.book.frames, 0, 0)
	var level := 1.0
	if s.book.additive:
		var into_fade := s.frame - s.book.frames + FADE_FRAMES
		if into_fade > 0:
			level = (128.0 - (into_fade * 0x9999 >> 12)) / 128.0
		s.material.albedo_color = Color(level, level, level) * HDR_BOOST
	else:
		s.material.albedo_color = Color(1, 1, 1, 0.5)


func _paint_light(l: Light) -> void:
	l.node.light_energy = LIGHT_ENERGY * float(l.left) / LIGHT_FRAMES
