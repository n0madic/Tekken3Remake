class_name EffectObjectsView
extends Node3D
## Draws the effect object pool (FightState.effects, effects.md#effect-objects) as the game does:
## each object a camera-facing quad of its model (the executable's small models), textured from the
## object page (VRAM (960, 256), 4-bit) through its CLUT — the fixed ones and the fade ramps of rows
## 509 and 510 — at the frame of its phase's UV table, or its model's own 16 × 16 sprite. One
## MultiMesh draws the additive page, one the 50 % page. Tekken Ball's charged ball (UV table
## BALL_CHARACTER) shows the hitter's character flipbook instead: the game points its quad at the
## flipbook's VRAM upload; the remake draws the converted flipbook's frames in turn on the ball's
## model, additively.

const MAX_OBJECTS := EffectObjects.CAPACITY
const ADD_SHADER := preload("res://presentation/effects/effect_object.gdshader")
const HALF_SHADER := preload("res://presentation/effects/effect_object_half.gdshader")

var additive := MultiMeshInstance3D.new()
var half := MultiMeshInstance3D.new()
var ball_glow := MeshInstance3D.new()
var quad_corners: Array[Color] = []    ## by EffectObjects.Model: corners 0 and 3 (corners)
var sprites: Dictionary = {}           ## model → (u, v, size)
var uv_frames: Array = []              ## by EffectObjects.UvTable − 1: Array[PackedInt32Array] of (u, v, size)
var clut_rows: Dictionary = {}         ## CLUT id → palette row
var costumes: Array[EffectData.Flipbook] = []   ## the players' character flipbooks
var ball_glow_frames := PackedInt32Array()      ## per glow step: the flipbook frame (−1 none)
var _ball_material := StandardMaterial3D.new()


func setup(data: EffectData) -> void:
	var d := data.objects
	var m := 1.0 / WorldSpace.UNITS_PER_METRE
	for q: Array in d.get("quads", []) as Array:
		if q.size() < 4:
			quad_corners.append(Color())      # model 0: none (show_pool skips it)
			continue
		var a := JsonFile.ints(q[0])
		var b := JsonFile.ints(q[3])
		quad_corners.append(Color(a[0] * m, a[1] * m, b[0] * m, b[1] * m))
	var own: Dictionary = d.get("sprites", {})
	for model: String in own:
		sprites[model.to_int()] = JsonFile.ints(own[model])
	for t: Dictionary in d.get("uv_tables", []) as Array:
		var size := JsonFile.number(t["size"])
		var frames: Array[PackedInt32Array] = []
		for f: Variant in t["frames"] as Array:
			var uv := JsonFile.ints(f)
			frames.append(PackedInt32Array([uv[0], uv[1], size]))
		uv_frames.append(frames)
	ball_glow_frames = JsonFile.ints(d.get("ball_glow_frames", []))
	var rows: Array = d.get("clut_rows", [])
	for i in rows.size():
		clut_rows[JsonFile.number(rows[i])] = i
	var page: Texture2D = null
	var palettes: Texture2D = null
	if d.has("page"):
		page = load(data.directory.path_join(str(d["page"]))) as Texture2D
		palettes = load(data.directory.path_join(str(d["palettes"]))) as Texture2D
	_prepare(additive, ADD_SHADER, page, palettes)
	_prepare(half, HALF_SHADER, page, palettes)
	var quad := QuadMesh.new()
	ball_glow.mesh = quad
	_ball_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ball_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_ball_material.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_ball_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ball_material.no_depth_test = false
	_ball_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR
	ball_glow.material_override = _ball_material
	ball_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ball_glow.visible = false
	add_child(ball_glow)


func _prepare(node: MultiMeshInstance3D, shader: Shader, page: Texture2D, palettes: Texture2D) -> void:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	mm.mesh = QuadMesh.new()
	mm.instance_count = MAX_OBJECTS
	mm.visible_instance_count = 0
	node.multimesh = mm
	var material := ShaderMaterial.new()
	material.shader = shader
	material.set_shader_parameter("page", page)
	material.set_shader_parameter("palettes", palettes)
	if shader == ADD_SHADER:
		material.set_shader_parameter("hdr_boost", EffectsView.HDR_BOOST)
	node.material_override = material
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The instances are placed in view space by the shader: the node's bounds cannot be known.
	node.custom_aabb = AABB(Vector3(-1000, -1000, -1000), Vector3(2000, 2000, 2000))
	add_child(node)


## The players' character flipbooks (the charged ball's glow).
func set_costumes(books: Array[EffectData.Flipbook]) -> void:
	costumes = books


func clear() -> void:
	additive.multimesh.visible_instance_count = 0
	half.multimesh.visible_instance_count = 0
	ball_glow.visible = false


## The sprite of an object this frame: (u0, v0, frame size) on the object page, or empty.
func sprite_of(o: EffectObjects.Obj) -> PackedInt32Array:
	if o.uv_table == EffectObjects.UvTable.MODEL or o.uv < 0:
		var own: PackedInt32Array = sprites.get(o.model, PackedInt32Array())
		if own.is_empty():
			# An animated model before its first frame: the table's first frame.
			if o.uv_table == EffectObjects.UvTable.MODEL:
				return PackedInt32Array()
			return _table_frame(o.uv_table, 0)
		return own
	return _table_frame(o.uv_table, o.uv)


func _table_frame(table: int, frame: int) -> PackedInt32Array:
	var frames := uv_frames[table - 1] as Array
	return frames[clampi(frame, 0, frames.size() - 1)] as PackedInt32Array


## The pool after a simulation step.
func show_pool(pool: EffectPool) -> void:
	var counts := [0, 0]
	ball_glow.visible = false
	for o in pool.objects:
		if o.gone or o.flags & EffectObjects.VISIBLE == 0 or o.model <= 0 or o.model >= quad_corners.size():
			continue
		if o.uv_table == EffectObjects.UvTable.BALL_CHARACTER:
			_show_ball_glow(o)
			continue
		var s := sprite_of(o)
		if s.is_empty() or not clut_rows.has(o.clut):
			continue
		var target := half if o.tpage == EffectObjects.TPAGE_HALF else additive
		var k := 1 if target == half else 0
		var i: int = counts[k]
		if i >= MAX_OBJECTS:
			continue
		counts[k] = i + 1
		var mm := target.multimesh
		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, WorldSpace.point(o.x, o.y, o.z)))
		var row: int = clut_rows[o.clut]
		mm.set_instance_color(i, Color(s[0], s[1], s[2], row))
		mm.set_instance_custom_data(i, corners(o.model))
	additive.multimesh.visible_instance_count = counts[0]
	half.multimesh.visible_instance_count = counts[1]


## A model's corners 0 and 3 as (x0, y0, x1, y1) in metres.
func corners(model: int) -> Color:
	return quad_corners[model]


## The charged ball's glow on the ball's quad, additively: step `uv` of the glow's UV table points
## the quad at a frame of the hitter's flipbook upload (FUN_800743EC), converted as that frame of
## the character flipbook (`ball_glow_frames`).
func _show_ball_glow(o: EffectObjects.Obj) -> void:
	var player := clampi(o.a, 0, 1)
	if player >= costumes.size() or costumes[player] == null:
		return
	var book := costumes[player]
	var frame := ball_glow_frames[o.uv] if o.uv >= 0 and o.uv < ball_glow_frames.size() else -1
	if frame < 0 or frame >= book.frames:
		return
	var c := corners(o.model)
	var quad := ball_glow.mesh as QuadMesh
	quad.size = Vector2(c.b - c.r, c.a - c.g)
	_ball_material.albedo_texture = book.texture
	_ball_material.uv1_scale = Vector3(1.0 / book.frames, 1, 1)
	_ball_material.uv1_offset = Vector3(float(frame) / book.frames, 0, 0)
	ball_glow.position = WorldSpace.point(o.x, o.y, o.z)
	ball_glow.visible = true
