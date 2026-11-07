class_name SwordGlowView
extends Node3D
## Draws the glow along Yoshimitsu's sword (SwordGlow; effects.md#sword-glow): per fighter a ribbon
## of ten additive quads, black at the edges and the ends and coloured along its centre line.
##
## The game draws the ribbon in the plane of the screen. Here each quad is put at the view depth of
## the ordering-table entry the game files it in (the depth the fighters' faces and the flipbook
## sprites stand at, FaceKeys), with its corners scaled along their view rays so that they project to
## the same screen points, which makes the depth test reproduce the table's order. The node is a
## child of the camera, so the vertices are in view space.
##
## The ribbons come from the simulation steps; between two steps their points and depths are
## interpolated, the colour is the later step's (the game's two display buffers differ in
## brightness, so the glow pulses from frame to frame as it does there).
##
## The PlayStation's ribbon is its vertex colours alone (SwordGlow); the arcade's quads are shaded
## by a 16 × 16 grey picture (ArcadeSwordGlow, `set_levels`). Both read one texture: the picture's
## columns, then one more column of white for the quads without a picture.

const ENTRY_UNITS := 32.0                       ## an ordering-table entry's depth in game units
const ENTRY_LAST := 0.999                       ## inside its entry the quad is behind every face
## A texel is five bits a channel (a white one 0xFFFF) and the GPU multiplies it by the vertex
## colour / 0x80.
const WHITE := 31
const FULL := 128.0
const COLUMNS := ArcadeSwordGlow.PICTURE + 1        ## the picture and the column of white
const SPAN := 1000.0                            ## half the size of the box the culling sees
const SHADER := preload("res://presentation/fighter/sword_glow.gdshader")
const LEVELS_FILE := "characters/arcade_sword_glow.json"    ## the converter's picture of the arcade quads

var _mesh := ImmediateMesh.new()
var _material := ShaderMaterial.new()
var _has_levels := false
var _previous: Array[SwordGlow.Ribbon] = []
var _current: Array[SwordGlow.Ribbon] = []


func _init() -> void:
	var instance := MeshInstance3D.new()
	instance.mesh = _mesh
	_material.shader = SHADER
	_set_texture(PackedInt32Array())
	instance.material_override = _material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# The vertices follow the camera and move with it: no box of the mesh tells where they are.
	instance.custom_aabb = AABB(Vector3.ONE * -SPAN, Vector3.ONE * 2.0 * SPAN)
	add_child(instance)


## The grey levels (0–31, 16 rows of 16) of the arcade quads' picture, as the converter wrote them
## (characters/arcade_sword_glow.json); empty: none.
func set_levels(levels: PackedInt32Array) -> void:
	_has_levels = levels.size() == ArcadeSwordGlow.PICTURE * ArcadeSwordGlow.PICTURE
	_set_texture(levels if _has_levels else PackedInt32Array())


## `set_levels` from the converted assets, when they have the picture.
func load_levels() -> void:
	var path := Assets.path(LEVELS_FILE)
	if not FileAccess.file_exists(path):
		Log.warning("SwordGlowView: %s is missing; the arcade models get the PlayStation's glow (convert again)" % path)
		return
	var data: Dictionary = JsonFile.read(path)
	set_levels(JsonFile.ints(data.get("levels", [])))


## Whether the arcade ribbons can be drawn (their picture is known).
func has_levels() -> bool:
	return _has_levels


## Fighter `i`'s ribbon after a simulation step (null: none); `snap` drops the interpolation.
func set_ribbon(i: int, ribbon: SwordGlow.Ribbon, snap: bool = false) -> void:
	while _current.size() <= i:
		_current.append(null)
		_previous.append(null)
	_previous[i] = ribbon if snap else _current[i]
	_current[i] = ribbon


## Draws the ribbons between the last two steps (`weight` 0 → previous, 1 → current) for a camera
## whose frame spans `frame_tan` in view-plane units (CameraRig.frame_tan).
func show_between(weight: float, frame_tan: Vector2) -> void:
	_mesh.clear_surfaces()
	var begun := false
	for i in _current.size():
		var now := _current[i]
		if now == null:
			continue
		if not begun:
			_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			begun = true
		_add(_previous[i] if _previous[i] != null else now, now, weight, frame_tan)
	if begun:
		_mesh.surface_end()


## The game's vertex colour (0x80 = full) as the shader takes it, in display values: it multiplies
## the texel and turns the product into the linear colour the renderer adds in.
static func vertex_colour(colour: Vector3i) -> Color:
	return Color(colour.x / FULL, colour.y / FULL, colour.z / FULL)


## The texture coordinates of texel (u, v) of the picture; the white column for a texel outside it
## (`Vector2i(-1, 0)`: the PlayStation's quads).
static func texture_coordinate(texel: Vector2i) -> Vector2:
	var column := COLUMNS - 1 if texel.x < 0 else texel.x
	return Vector2((column + 0.5) / COLUMNS, (texel.y + 0.5) / ArcadeSwordGlow.PICTURE)


## The view-space position (Godot: x right, y up, looking along −z) of the screen point `point` (the
## game's GTE units, rows of the 480-line display) at the view depth `depth` (metres). The frame spans
## 368 columns (±184 round x = 192) and 480 rows (±240 round y = 240) and `frame_tan` is its half
## extent in view-plane units.
static func view_position(point: Vector2, depth: float, frame_tan: Vector2) -> Vector3:
	var x := (point.x - ViewMatrix.SCREEN_OFFSET_X) / CameraRig.HALF_WIDTH * frame_tan.x
	var y := (point.y - ViewMatrix.SCREEN_OFFSET_Y) / ViewMatrix.SCREEN_OFFSET_Y * frame_tan.y
	return Vector3(x * depth, -y * depth, -depth)


## The view depth (metres) of ordering-table entry `entry`: its far edge, never nearer than the
## faces' limit.
static func entry_depth(entry: int) -> float:
	return maxf((entry + ENTRY_LAST) * ENTRY_UNITS / WorldSpace.UNITS_PER_METRE, FaceKeys.NEAR_CLAMP)


func _add(from: SwordGlow.Ribbon, to: SwordGlow.Ribbon, weight: float, frame_tan: Vector2) -> void:
	var points: Array[Vector2] = []
	for p in SwordGlow.POINTS:
		points.append(Vector2(lerpf(from.points[2 * p], to.points[2 * p], weight), lerpf(from.points[2 * p + 1], to.points[2 * p + 1], weight)))
	var depth := PackedFloat32Array()
	for d in to.depth.size():
		depth.append(lerpf(from.depth[d], to.depth[d], weight))
	var lit := vertex_colour(to.colour)
	for q in SwordGlow.QUADS:
		var entry := (floori(depth[SwordGlow.QUAD_POINTS[SwordGlow.QUAD_STRIDE * q + 4]]) - SwordGlow.DEPTH_BIAS) & SwordGlow.ENTRY_MASK
		var z := entry_depth(entry)
		var at: Array[Vector3] = []
		var colour: Array[Color] = []
		var uv: Array[Vector2] = []
		for v in 4:
			at.append(view_position(points[SwordGlow.corner(q, v)], z, frame_tan))
			# The PlayStation's quads are black but along the centre line; the arcade's are flat
			# coloured and shaded by the picture.
			colour.append(lit if to.textured or SwordGlow.lit(q, v) else Color.BLACK)
			uv.append(texture_coordinate(ArcadeSwordGlow.uv(q, v) if to.textured else Vector2i(-1, 0)))
		# A quad is the triangles of corners 0, 1, 2 and 1, 3, 2.
		for corner: int in [0, 1, 2, 1, 3, 2]:
			_mesh.surface_set_color(colour[corner])
			_mesh.surface_set_uv(uv[corner])
			_mesh.surface_add_vertex(at[corner])


## The texture: the picture's rows with a column of white beside them.
func _set_texture(levels: PackedInt32Array) -> void:
	var bytes := PackedByteArray()
	bytes.resize(COLUMNS * ArcadeSwordGlow.PICTURE)
	for v in ArcadeSwordGlow.PICTURE:
		for u in ArcadeSwordGlow.PICTURE:
			var level := levels[v * ArcadeSwordGlow.PICTURE + u] if not levels.is_empty() else 0
			bytes[v * COLUMNS + u] = level * 8
		bytes[v * COLUMNS + COLUMNS - 1] = WHITE * 8
	var image := Image.create_from_data(COLUMNS, ArcadeSwordGlow.PICTURE, false, Image.FORMAT_R8, bytes)
	_material.set_shader_parameter("levels", ImageTexture.create_from_image(image))
