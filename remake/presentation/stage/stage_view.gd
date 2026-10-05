class_name StageView
extends Node3D
## Draws a stage: the distant panorama and the tiled floor.
##
## The game draws the panorama with one eighth of the camera's displacement from the
## fighters' midpoint and a per-stage height (StageBackgroundDraw). In world terms that is
## the panorama scaled by 8 around the midpoint, raised to that height, which is how it is
## placed here.
## The whole panorama is drawn: the game's visibility cells only spare it the hidden objects. It
## turns about the midpoint with the camera's sideways slides (BackdropTurn): the game turns its
## objects by Ry(−angle), which is a turn by +angle about Godot's y (WorldSpace's axes).
##
## A kind-0 floor darkens with the distance past the fighters (FloorDrawGrid, stages.md#floor):
## per pixel here, from the depth beyond the camera's distance to the fighters' midpoint.
##
## With the Stage backdrops setting on Arcade and the stage's arcade version converted
## (ArcadeStageData), the arcade's scene, sky and floor are drawn instead
## (docs/research/arcade/stages.md): the scene is placed like the panorama, scaled by
## 10 instead of 8, with stages 6 and 12's texture animation and stages 3 and 11's animated props
## (step: the carousel, and the helicopter after a round's end and in replays); the sky is the
## environment's background (apply_environment), and the floor is the arcade's pattern of
## 2,500-unit tiles, 10 × 10 around the fighters as in the game, with the scene's ground beyond
## it. Every tile shows its quarter-tile texture: the arcade's own budget of 11 split tiles a frame
## (FUN_801A941C, the others at half the resolution) is not reproduced.

const PANORAMA_SHADER := preload("res://presentation/stage/panorama.gdshader")
const FLOOR_SHADER := preload("res://presentation/stage/floor.gdshader")
const PANORAMA_PARALLAX := 8.0
const FLOOR_PATTERN := 10        ## the game draws 10 × 10 tiles around the fighters
## How far the floor reaches past the panorama's footprint (game units): the walls stand
## on it, their base below the ground, so the floor edge is never visible.
const FLOOR_UNDER_WALLS := 500
const TILED_FLOOR_HALF := 60000
const FLOOR_FADE_FILE := "floor_fade.json"
const ARCADE_SCENE_SHADER := preload("res://presentation/stage/arcade_scene.gdshader")
const ARCADE_SKY_SHADER := preload("res://presentation/stage/arcade_sky.gdshader")
const SKY_SCREEN_CENTRE := 240     ## the arcade's projection centre row (480-line display)
const SKY_KINDS := {"tiles": 0, "gradient": 1, "fill": 2}
const ANGLE_HALF := 2048           ## 4096-unit angles wrap to −2048 … 2047
const FADE_SCALE := 0x4000000      ## FloorDrawGrid: the table index is depth · (FADE_SCALE / fade) >> 16

static var _fade_table: ImageTexture
static var _arcade_fade_table: ImageTexture
static var _arcade_sine: PackedInt32Array

var panorama := MeshInstance3D.new()
var floor_mesh := MeshInstance3D.new()
var arcade: ArcadeStageData           ## the arcade version drawn, or null
var sky_material: ShaderMaterial       ## the arcade's sky, or null
var _stage: StageData
var _steps := 0                        ## simulation steps since setup (the texture animation's clock)
var props: ArcadeProps                 ## the arcade's animated props, or null
var prop_nodes: Array[MeshInstance3D] = []
var _round := -1                       ## the round the props were started for
var _environment: Environment          ## the view's environment, its background the sky while shown
var _target := Vector3.ZERO            ## the fighters' midpoint (Godot space)
var _view_pitch := 0                   ## the camera's pitch of the last step (the sky's top edge)
var _backdrop_turn := 0                ## the backdrop's turn of the last step (the sky turns with it)


## The arcade version to draw for `stage` (the Stage backdrops setting), or null.
static func arcade_of(stage: StageData) -> ArcadeStageData:
	if stage.arcade == null or not stage.tile_map.is_empty() or Settings.text("stage_backdrops") != "arcade":
		return null
	return stage.arcade


func setup(stage: StageData) -> void:
	_stage = stage
	_steps = 0
	arcade = arcade_of(stage)
	if not Settings.changed.is_connected(_on_setting_changed):
		Settings.changed.connect(_on_setting_changed)
	# The tile-map stages (Tekken Ball, Tekken Force) draw their backdrop in screen space
	# (TiledPanorama) and have no panorama objects.
	if arcade != null:
		panorama.mesh = _arcade_mesh(arcade.scene, arcade.vertex_floats)
		panorama.material_override = ShaderMaterial.new()
		_panorama_textures()
		_build_props(stage)
		panorama.scale = Vector3(arcade.scene_scale, arcade.scene_scale * arcade.scene_y_scale, arcade.scene_scale)
		panorama.position = WorldSpace.point(0, arcade.scene_height, 0)
		panorama.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		sky_material = ShaderMaterial.new()
		_sky_parameters()
	elif stage.tile_map.is_empty():
		panorama.mesh = _panorama_mesh(stage)
		panorama.material_override = ShaderMaterial.new()
		_panorama_textures()
		panorama.scale = Vector3.ONE * PANORAMA_PARALLAX
		panorama.position = WorldSpace.point(0, stage.panorama_height, 0)
		panorama.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		panorama.visible = false
	add_child(panorama)
	floor_mesh.mesh = _floor_mesh(stage, arcade)
	add_child(floor_mesh)


## Keeps the panorama and the floor around the fighters' midpoint (Godot units, x and z): the
## game centres its floor grid under the fighters every frame, so the floor never ends. The
## floor's pattern comes from the world position and stays in place. The arcade's floor is its
## 10 × 10 tiles around the tile under the midpoint, so it moves by whole tiles.
func follow(midpoint: Vector3) -> void:
	_target = midpoint
	panorama.position.x = midpoint.x
	panorama.position.z = midpoint.z
	var centre := midpoint
	if arcade != null:
		var tile := arcade.floor_tile_size
		var origin := floor_grid_origin()
		centre = WorldSpace.point(tile * (origin.x + FLOOR_PATTERN / 2), 0, tile * (origin.y + FLOOR_PATTERN / 2))
	floor_mesh.position.x = centre.x
	floor_mesh.position.z = centre.z


## The arcade floor grid's first tile (x, z in tiles of the game's grid; FUN_801A941C draws
## FLOOR_PATTERN × FLOOR_PATTERN tiles around the one under the fighters' midpoint).
func floor_grid_origin() -> Vector2i:
	var tile := arcade.floor_tile_size
	var half := FLOOR_PATTERN / 2
	return Vector2i(floori((_target.x * WorldSpace.UNITS_PER_METRE + tile / 2.0) / tile) - half,
		floori((-_target.z * WorldSpace.UNITS_PER_METRE + tile / 2.0) / tile) - half)


static func _panorama_mesh(stage: StageData) -> ArrayMesh:
	var v := stage.panorama
	var stride := stage.vertex_floats
	var count := v.size() / stride
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	positions.resize(count)
	uvs.resize(count)
	colours.resize(count)
	for i in count:
		var o := i * stride
		positions[i] = WorldSpace.point(v[o], v[o + 1], v[o + 2])
		uvs[i] = Vector2(v[o + 3], v[o + 4])
		# Packet RGB modulation, 0x80 = unchanged; halved to fit the vertex colour range.
		colours[i] = Color(v[o + 5] / 2.0, v[o + 6] / 2.0, v[o + 7] / 2.0)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_COLOR] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The arcade scene or a prop (arcade.py's scene.bin format): positions, atlas texels, the
## texture window in CUSTOM0 and the colour factor in CUSTOM1, as floats (ARRAY_COLOR would
## store 8 bits per channel, too coarse for the dark linear colours of untextured packets).
static func _arcade_mesh(v: PackedFloat32Array, stride: int) -> ArrayMesh:
	var count := v.size() / stride
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var windows := PackedFloat32Array()
	var colours := PackedFloat32Array()
	positions.resize(count)
	uvs.resize(count)
	windows.resize(4 * count)
	colours.resize(3 * count)
	for i in count:
		var o := i * stride
		positions[i] = WorldSpace.point(v[o], v[o + 1], v[o + 2])
		uvs[i] = Vector2(v[o + 3], v[o + 4])
		for k in 4:
			windows[4 * i + k] = v[o + 5 + k]
		for k in 3:
			colours[3 * i + k] = v[o + 9 + k]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = windows
	arrays[Mesh.ARRAY_CUSTOM1] = colours
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {},
		Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT
		| Mesh.ARRAY_CUSTOM_RGB_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	return mesh


## One simulation step (the camera's yaw, and in fights the round's number and state):
## stages 6 and 12 copy the next frame into their animated texture every `period` steps, cycling
## (FUN_801E2114, called every frame of the stage's display); the loaded picture shows until the
## first copy. The props start again with each round (FUN_801E3D94: the helicopter's mode from
## the first player's attack buttons held then, `held`, else the step counter's low bits as the
## arcade's counter); the carousel turns every step, the helicopter flies only while shown: in
## the replay and from the win poses on (FUN_801E2A2C).
func step(camera_yaw: int = 0, round_number: int = -1, round_state: int = -1, held: int = 0) -> void:
	_steps += 1
	if arcade == null:
		return
	if not arcade.scene_animation_rect.is_empty():
		var copies := _steps / arcade.scene_animation_period
		var frame := (copies - 1) % arcade.scene_animation_frames if copies > 0 else -1
		(panorama.material_override as ShaderMaterial).set_shader_parameter("frame", frame)
	if props == null:
		return
	if round_number >= 0 and round_number != _round:
		_round = round_number
		props.start(ArcadeProps.arcade_buttons(held), _steps)
	if props.kind == ArcadeProps.HELICOPTER:
		var shown := round_state >= RoundState.REPLAY
		prop_nodes[0].visible = shown
		if not shown:
			return
	props.step(camera_yaw)
	_place_props()


## The props' meshes under the scene (FUN_801E2A68 draws them with the scene's matrices): the
## carousel's parts side by side, the helicopter's rotor on its body.
func _build_props(stage: StageData) -> void:
	if arcade.props_kind.is_empty() or arcade.props_meshes.is_empty():
		return
	props = ArcadeProps.new(arcade.props_kind, _arcade_sine_table(stage.directory.get_base_dir()))
	for k in arcade.props_meshes.size():
		var node := MeshInstance3D.new()
		node.mesh = _arcade_mesh(arcade.props_meshes[k], arcade.vertex_floats)
		node.material_override = panorama.material_override
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var parent: Node3D = prop_nodes[0] if props.kind == ArcadeProps.HELICOPTER and k > 0 else panorama
		parent.add_child(node)
		prop_nodes.append(node)
	if props.kind == ArcadeProps.HELICOPTER:
		prop_nodes[0].visible = false
	props.start()
	_place_props()


## The props' transforms from their SVECTOR angles and positions: libgte RotMatrix (Rx · Ry · Rz)
## for the carousel, RotMatrixYXZ (Ry · Rx · Rz) for the helicopter (both checked in the CPU
## harness), in the game's y-down frame turned into Godot's.
func _place_props() -> void:
	var flip := Basis.from_scale(Vector3(1, -1, -1))
	for k in prop_nodes.size():
		var a := props.angles[k]
		var rx := Basis(Vector3.RIGHT, WorldSpace.radians(a[0]))
		var ry := Basis(Vector3.UP, WorldSpace.radians(a[1]))
		var rz := Basis(Vector3.BACK, WorldSpace.radians(a[2]))
		var turn := ry * rx * rz if props.kind == ArcadeProps.HELICOPTER else rx * ry * rz
		prop_nodes[k].transform = Transform3D(flip * turn * flip, WorldSpace.point_i(props.positions[k]))


static func _arcade_sine_table(stages_dir: String) -> PackedInt32Array:
	if _arcade_sine.is_empty():
		var d: Dictionary = JsonFile.read(stages_dir.path_join(ArcadeStageData.SINE_FILE))
		_arcade_sine = JsonFile.ints(d.get("table", []))
	return _arcade_sine


## The pitch of `camera` (4096 units, positive looking down, as CameraView's).
static func camera_pitch(camera: Camera3D) -> int:
	return roundi(asin(clampf(camera.global_basis.z.y, -1.0, 1.0)) * WorldSpace.ANGLE_UNITS / TAU)


## The floor's kind of this stage as drawn (stages.md#floor; the arcade's own when it is drawn).
func floor_kind() -> int:
	return arcade.floor_kind if arcade != null else _stage.floor_kind


## The camera rig's coverage: the arcade's sky surrounds the camera, so it covers every view.
func coverage() -> PackedInt32Array:
	return PackedInt32Array() if arcade != null else _stage.coverage


## Shows the arcade's sky as `environment`'s background (no sky in True Ogre fights, which
## clear to black in the arcade too: FUN_801A7688), only while this view is shown: a hidden view's
## camera may still be the viewport's (the attract demonstration's, set up at boot), and between
## the 2D screens the background must stay the clear colour.
func apply_environment(environment: Environment, true_ogre: bool = false) -> void:
	if sky_material == null or true_ogre:
		return
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	_environment = environment
	_show_sky()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED or what == NOTIFICATION_ENTER_TREE:
		_show_sky()


func _show_sky() -> void:
	if _environment != null:
		_environment.background_mode = Environment.BG_SKY if is_visible_in_tree() else Environment.BG_COLOR


## The camera's pitch of this step (4096 units): where the sky's top edge stands after the
## stage's clamps (FUN_801A7688: the top row lies −pitch · k / 256 + offset lines down the
## 480-line display; stages 0, 3, 5 and 11 keep it at or above the screen's top, 11 not
## more than 192 lines above).
func set_view_pitch(pitch: int) -> void:
	_view_pitch = pitch
	if sky_material == null:
		return
	var k := float(JsonFile.number(arcade.sky.get("pitch_scale", 0)))
	if k <= 0.0:
		return
	var p := wrapi(pitch, -ANGLE_HALF, ANGLE_HALF)
	var y := int(-p * k / 256.0) + JsonFile.number(arcade.sky.get("offset", 0))
	if arcade.sky.get("clamp_top", false) or str(arcade.sky.get("kind", "")) == "gradient":
		y = mini(y, 0)
	var bottom: Variant = arcade.sky.get("clamp_bottom")
	if bottom != null:
		y = maxi(y, JsonFile.number(bottom))
	sky_material.set_shader_parameter("top", -p + (SKY_SCREEN_CENTRE - y) * 256.0 / k)


func _sky_parameters() -> void:
	var sky := arcade.sky
	sky_material.shader = RenderQuality.shader(ARCADE_SKY_SHADER)
	sky_material.set_shader_parameter("kind", SKY_KINDS.get(str(sky.get("kind", "tiles")), 0))
	if sky.has("texture"):
		sky_material.set_shader_parameter("strip", TexturePacks.texture(arcade.directory.path_join(str(sky["texture"]))))
	sky_material.set_shader_parameter("yaw_step", float(JsonFile.number(sky.get("step", 1))))
	sky_material.set_shader_parameter("pitch_scale", float(JsonFile.number(sky.get("pitch_scale", 256))))
	sky_material.set_shader_parameter("rows", float(JsonFile.number(sky.get("rows", 0))))
	sky_material.set_shader_parameter("upper_fill", _fill(sky.get("upper_fill")))
	sky_material.set_shader_parameter("lower_fill", _fill(sky.get("lower_fill")))
	var gradient: Variant = sky.get("gradient")
	if gradient is Array and (gradient as Array).size() == 2:
		var stops: Array = gradient
		sky_material.set_shader_parameter("gradient_top", _fill(stops[0]))
		sky_material.set_shader_parameter("gradient_bottom", _fill(stops[1]))
	set_view_pitch(_view_pitch)
	sky_material.set_shader_parameter("turn", float(_backdrop_turn))


## An RGB fill (enabled: alpha 1) or none (alpha 0).
static func _fill(value: Variant) -> Color:
	if value == null:
		return Color(0, 0, 0, 0)
	var c := JsonFile.ints(value)
	return Color8(c[0], c[1], c[2])


## Where the floor ends (the tile-map stages' backdrop covers the rest): a Godot-space line
## dot(xz, (x, y)) = z.
func set_floor_edge(edge: Vector3) -> void:
	var material := (floor_mesh.mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("far_edge", edge)


## The spotlight floor of this step (kind 0: none): the light points in Godot space.
func set_spotlight(kind: int, a: Vector3, b: Vector3, k: float, limit: float) -> void:
	var material := (floor_mesh.mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("spot_kind", kind)
	material.set_shader_parameter("spot_lights", Vector4(a.x, a.z, b.x, b.z))
	material.set_shader_parameter("spot_k", k)
	material.set_shader_parameter("spot_limit", limit)


## Chooses the floor picture: the exact pattern or the one with smoothed tile seams (the arcade's
## with `a`).
static func floor_texture_path(stage: StageData, smooth: bool, a: ArcadeStageData = null) -> String:
	if a != null:
		return a.directory.path_join(a.floor_pattern_smooth if smooth else a.floor_pattern)
	return stage.directory.path_join(stage.floor_pattern_smooth if smooth else stage.floor_pattern)


## Half the side of the floor square (game units). The game's floor is a 10 × 10-tile grid
## (±9,000 units) that fades out, leaving gaps before the panorama walls (±9,600 units in
## stg_e, more in the corners). Here the floor reaches under the walls instead.
static func floor_half_extent(stage: StageData, a: ArcadeStageData = null) -> int:
	# The arcade draws its 10 × 10 tiles and nothing more: its scene's own ground lies beyond.
	if a != null:
		return a.floor_tile_size * FLOOR_PATTERN / 2
	# The tile-map stages have no walls: the floor reaches the backdrop's edge wherever the
	# camera looks (the far edge is cut per frame, StageView.set_floor_edge).
	if not stage.tile_map.is_empty():
		return TILED_FLOOR_HALF
	var reach := 0
	for v in stage.panorama_extent:
		reach = maxi(reach, absi(v))
	var walls := int(reach * PANORAMA_PARALLAX)
	return maxi(walls, stage.floor_tile_size * FLOOR_PATTERN / 2) + FLOOR_UNDER_WALLS


## One quad under the whole panorama. The floor shader derives the texture coordinates
## from the world position, so the pattern repeats without per-tile seams.
static func _floor_mesh(stage: StageData, a: ArcadeStageData) -> ArrayMesh:
	var half := float(floor_half_extent(stage, a))
	var quad: Array[Vector3] = [
		WorldSpace.point(-half, 0, half), WorldSpace.point(half, 0, half),
		WorldSpace.point(-half, 0, -half), WorldSpace.point(half, 0, -half),
	]
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	for i: int in [0, 1, 2, 1, 3, 2]:
		positions.append(quad[i])
		normals.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var material := ShaderMaterial.new()
	_floor_textures(material, stage, a)
	var tile_size := a.floor_tile_size if a != null else stage.floor_tile_size
	var shade := a.floor_shade if a != null else stage.floor_shade
	var fade := a.floor_fade if a != null else stage.floor_fade
	material.set_shader_parameter("pattern_size", tile_size * FLOOR_PATTERN / WorldSpace.UNITS_PER_METRE)
	if shade != 0 and fade > 0:
		var table := _arcade_floor_fade_table(stage.directory.get_base_dir()) if a != null \
			else _floor_fade_table(stage.directory.get_base_dir())
		material.set_shader_parameter("fade_table", table)
		material.set_shader_parameter("shade", shade)
		material.set_shader_parameter("fade_scale", FADE_SCALE / fade)
		material.set_shader_parameter("units_per_metre", WorldSpace.UNITS_PER_METRE)
	mesh.surface_set_material(0, material)
	return mesh


## FloorDrawGrid's shading table (stages/floor_fade.json) as a 1-texel-high picture of its bytes.
static func _floor_fade_table(stages_dir: String) -> ImageTexture:
	if _fade_table == null:
		_fade_table = _table_texture(stages_dir.path_join(FLOOR_FADE_FILE))
	return _fade_table


## The arcade floor's table (FUN_801A941C, stages/arcade_floor_fade.json).
static func _arcade_floor_fade_table(stages_dir: String) -> ImageTexture:
	if _arcade_fade_table == null:
		_arcade_fade_table = _table_texture(stages_dir.path_join(ArcadeStageData.FADE_FILE))
	return _arcade_fade_table


static func _table_texture(path: String) -> ImageTexture:
	var d: Dictionary = JsonFile.read(path)
	var table := JsonFile.ints(d.get("table", []))
	var bytes := PackedByteArray()
	for v in table:
		bytes.append(v & 0xFF)
	if bytes.is_empty():
		bytes.append(0)
	return ImageTexture.create_from_image(Image.create_from_data(bytes.size(), 1, false, Image.FORMAT_R8, bytes))


## The panorama's turn of this step (BackdropTurn.angle, 4096 units); the arcade's sky turns
## with it (FUN_801D8FD0 draws it with the camera's yaw minus the turn).
func set_backdrop_turn(angle: int) -> void:
	panorama.rotation.y = WorldSpace.radians(angle)
	_backdrop_turn = angle
	if sky_material != null:
		sky_material.set_shader_parameter("turn", float(angle))


## The camera's horizontal distance to the fighters' midpoint (game units) of this step, from
## which the floor's shading starts.
func set_floor_distance(distance: float) -> void:
	var material := (floor_mesh.mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial
	material.set_shader_parameter("camera_distance", distance)


static func _floor_textures(material: ShaderMaterial, stage: StageData, a: ArcadeStageData) -> void:
	material.shader = RenderQuality.shader(FLOOR_SHADER)
	material.set_shader_parameter("pattern", TexturePacks.texture(floor_texture_path(stage, true, a)))


func _panorama_textures() -> void:
	var material := panorama.material_override as ShaderMaterial
	if arcade != null:
		material.shader = RenderQuality.shader(ARCADE_SCENE_SHADER)
		material.set_shader_parameter("atlas", TexturePacks.texture(arcade.directory.path_join(arcade.scene_texture)))
		if not arcade.scene_animation_rect.is_empty():
			var r := arcade.scene_animation_rect
			material.set_shader_parameter("frames", TexturePacks.texture(arcade.directory.path_join(arcade.scene_animation_texture)))
			material.set_shader_parameter("frames_rect", Vector4(r[0], r[1], r[2], r[3]))
		return
	material.shader = RenderQuality.shader(PANORAMA_SHADER)
	material.set_shader_parameter("atlas", TexturePacks.texture(_stage.directory + "/panorama.png"))


## The Textures or Texture pack setting changed: the shaders and pictures again.
func _on_setting_changed(key: String) -> void:
	if _stage == null or not key in RenderQuality.TEXTURE_SETTINGS:
		return
	if panorama.material_override != null:
		_panorama_textures()
	var floor_material := (floor_mesh.mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial
	_floor_textures(floor_material, _stage, arcade)
	if sky_material != null:
		_sky_parameters()
