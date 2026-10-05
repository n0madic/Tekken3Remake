class_name FighterView
extends Node3D
## Draws one fighter from its converted model and the joint frames of the simulation.
## The mesh keeps part-local positions; the fighter shaders skin them on the GPU.
##
## The hands are separate meshes, one per vertex variant, swapped as the simulation's hand
## channels select variants; so are an arcade True Ogre's wings and tail (`set_hands`). The eyes
## close by swapping the atlas for the one with the closed-eye rectangle copied over the eyes (the
## game's blink copies it within VRAM).
## Between two simulation steps the joint rows are interpolated for high refresh rates.

const SHADER := preload("res://presentation/fighter/fighter.gdshader")
const SHADER_DOUBLE_SIDED := preload("res://presentation/fighter/fighter_double_sided.gdshader")
const JOINT_SLOTS := 22
const STICK_JOINT := 18             ## Mokujin's stick (attachment part 18)
const OVERHEAD_SEEN := 4            ## the value FUN_80034354 leaves in Gon's palette cache (fighter +0x1291)
## The mesh is stored in part-local units, so the engine cannot derive its bounds; they are
## rebuilt every frame from the joint positions, grown by the largest reach of a part.
const BOUNDS_MARGIN := 0.8
const HALF_RGBA_BYTES := 8          ## a CUSTOM_RGBA_HALF attribute per vertex
const NO_BACK_COLOUR := Vector3(-1.0, -1.0, -1.0)   ## set_back_colour not called yet: the stage's

var model: CharacterModel
var materials: Array[ShaderMaterial] = []     ## single-sided, double-sided
var mesh_instance := MeshInstance3D.new()
var hand_instances: Array[MeshInstance3D] = []
var hand_meshes: Array[Array] = []            ## per hand: ArrayMesh per variant
var hand_channels := PackedInt32Array()
var wing_instances: Array[MeshInstance3D] = []
var wing_meshes: Array[Array] = []            ## per wing group: ArrayMesh per variant
var wing_channels := PackedInt32Array()
var texture_open: Texture2D
var eye_textures := {}                        ## eye shape (int) → Texture2D, the shapes the model has
var texture_swap: Texture2D                   ## Gon's atlas with his head palette swapped, else null
var gaze_atlas: GazeAtlas                     ## Gon's atlas with his eyes' look direction, else null
var face: ArcadeFace                          ## an arcade model's face changes, null for the PlayStation's blink
var _eye_shape := CharacterModel.OPEN_SHAPE
var _albedo: Texture2D                        ## the atlas the materials have (_show_atlas)
var _swapped := false                         ## Gon's head palette is the swapped one (_step_palette)
var _swap_seen := 0                           ## the variant PartSelectVertexVariant last swapped for (fighter +0x1291)
var _overhead := false                        ## the overhead KO camera (0x800B08D4): the palette follows set_overhead
var _gaze_cache := PackedInt32Array([0, 0])   ## the shift each eye last copied (fighter +0x1292, +0x1293)
var _gaze_shifts := PackedInt32Array([GazeAtlas.NO_SHIFT, GazeAtlas.NO_SHIFT])   ## what each eye's strip shows
var _hidden_joints := -1                      ## the mask the materials have, -1 unknown
var _lighting: Dictionary = {}                ## the stage's light rig parameters (set_lighting)
var _back_colour := NO_BACK_COLOUR            ## this frame's back colour (set_back_colour), or the stage's
var _rows := PackedVector4Array()
var _previous_rows := PackedVector4Array()
var _bounds := AABB()
var _curved: CurvedMesh                       ## the curved grids' corners, null for flat triangles
var _hand_variants := PackedInt32Array([0, 0])
var _wing_variants := PackedInt32Array([0, 0])
var _arcade: ArcadeAttachments                ## an arcade model's attachment joints, else null
## The flat surfaces' mesh arrays (Surface → Array): the view's own, or one its fight shares
## (FightView: a model swapped in again, Tekken Force's enemies, does not split its corners again).
var array_cache: Dictionary = {}


func _init() -> void:
	mesh_instance.layers = StageLighting.FIGHTER_LAYER
	add_child(mesh_instance)
	Settings.changed.connect(_on_setting_changed)


func setup(character: CharacterModel) -> void:
	model = character
	materials.clear()
	_eye_shape = CharacterModel.OPEN_SHAPE
	_swapped = false
	_swap_seen = 0
	_overhead = false
	_gaze_cache = PackedInt32Array([0, 0])
	_gaze_shifts = PackedInt32Array([GazeAtlas.NO_SHIFT, GazeAtlas.NO_SHIFT])
	face = ArcadeFace.new(model.arcade_eyes, ArcadeFace.next_seed()) if model.arcade_eyes != null else null
	_hidden_joints = -1
	_load_textures()
	for shader: Shader in [SHADER, SHADER_DOUBLE_SIDED]:
		var material := ShaderMaterial.new()
		material.shader = RenderQuality.shader(shader)
		material.set_shader_parameter("albedo_texture", texture_open)
		materials.append(material)
	_apply_lighting()
	_albedo = texture_open
	_arcade = ArcadeAttachments.new(model) if not model.arcade_attachments.is_empty() else null
	_build_meshes()
	_previous_rows = PackedVector4Array()


## The body, hand and wing meshes: the converter's triangles, or with the Shading setting's
## "curved" the grids CurvedMesh lifts onto curved patches.
func _build_meshes() -> void:
	for node in hand_instances + wing_instances:
		node.queue_free()
	hand_instances.clear()
	hand_meshes.clear()
	hand_channels.clear()
	wing_instances.clear()
	wing_meshes.clear()
	wing_channels.clear()
	_curved = CurvedMesh.of(model) if Settings.text("shading") == "curved" else null
	mesh_instance.mesh = _mesh(model.surfaces)
	for hand in model.hands:
		_add_variants(hand, hand_instances, hand_meshes, hand_channels)
	for wing in model.wings:
		_add_variants(wing, wing_instances, wing_meshes, wing_channels)
	_apply_shading()


## A mesh instance showing the first variant of `group`, with a mesh per variant (the group's
## `select` repeats the meshes of equal variants), added to the given lists (its pose value's index
## in `channels`).
func _add_variants(group: CharacterModel.VariantGroup, instances: Array[MeshInstance3D],
		meshes_of: Array[Array], channels: PackedInt32Array) -> void:
	var meshes: Array[ArrayMesh] = []
	for variant: Array in group.variants:
		var surfaces: Array[CharacterModel.Surface] = []
		surfaces.assign(variant)
		meshes.append(_mesh(surfaces))
	var shown: Array[ArrayMesh] = meshes
	if not group.select.is_empty():
		shown = []
		for entry in group.select:
			shown.append(meshes[entry])
	var instance := MeshInstance3D.new()
	instance.mesh = shown[0]
	instance.layers = StageLighting.FIGHTER_LAYER
	add_child(instance)
	instances.append(instance)
	meshes_of.append(shown)
	channels.append(group.channel)


func _load_textures() -> void:
	texture_open = TexturePacks.texture(model.directory.path_join(model.texture))
	eye_textures.clear()
	for shape: int in model.eye_textures:
		eye_textures[shape] = TexturePacks.texture(model.directory.path_join(model.eye_textures[shape] as String))
	texture_swap = TexturePacks.texture(model.directory.path_join(model.swap_texture)) if model.swap_texture != "" else null
	gaze_atlas = null
	if not model.gaze.is_empty():
		gaze_atlas = GazeAtlas.new(model.gaze, texture_open, texture_swap if texture_swap != null else texture_open,
				TexturePacks.texture(model.directory.path_join(model.gaze["sheet"] as String)))


## The Textures or Texture pack setting changed: the shaders and atlases again.
func _on_setting_changed(key: String) -> void:
	if model != null and key == "shading":
		_apply_shading()
		if (Settings.text("shading") == "curved") != (_curved != null):
			_build_meshes()
			set_hand_variants(_hand_variants)
			set_wing_variants(_wing_variants)
			show_between(1.0)
	if model == null or not key in RenderQuality.TEXTURE_SETTINGS:
		return
	_load_textures()
	var shaders: Array[Shader] = [SHADER, SHADER_DOUBLE_SIDED]
	for i in materials.size():
		materials[i].shader = RenderQuality.shader(shaders[i])
	_apply_lighting()
	_apply_shading()
	_albedo = null
	_hidden_joints = -1
	set_eye_shape(_eye_shape)
	show_between(1.0)


func _mesh(surfaces: Array[CharacterModel.Surface]) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for surface in surfaces:
		if _curved != null:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _curved.arrays(surface), [], {}, CurvedMesh.format())
		else:
			if not array_cache.has(surface):
				array_cache[surface] = _arrays(surface.vertices, model.vertex_floats)
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, array_cache[surface] as Array, [], {}, _format())
		mesh.surface_set_material(mesh.get_surface_count() - 1, materials[1 if surface.double_sided else 0])
	return mesh


## The vertex variants a fighter's hand channels select: the PlayStation's models' by
## FighterHands.variant, an arcade model's hands (or jaw) by the arcade's own numbers of the
## channels' values, and an arcade True Ogre's wings and tail by the wing sequence the simulation
## steps (the arcade's tables, the same variants) and his level channel (ArcadePoses).
func set_hands(hands: FighterHands) -> void:
	var arcade := model != null and model.arcade
	_step_palette(hands.variant)
	set_hand_variants(ArcadePoses.hand_variants(hands) if arcade else hands.variant)
	set_wing_variants(ArcadePoses.wing_variants(hands))


## The vertex variant each hand channel shows (FighterHands.variant).
func set_hand_variants(variants: PackedInt32Array) -> void:
	_hand_variants = variants
	_show_variants(hand_instances, hand_meshes, hand_channels, variants)


## The vertex variant each wing group shows: the wings' (channel 0), the tail's (channel 1).
func set_wing_variants(variants: PackedInt32Array) -> void:
	_wing_variants = variants
	_show_variants(wing_instances, wing_meshes, wing_channels, variants)


static func _show_variants(instances: Array[MeshInstance3D], meshes_of: Array[Array], channels: PackedInt32Array,
		variants: PackedInt32Array) -> void:
	for i in instances.size():
		var meshes := meshes_of[i]
		var v := clampi(variants[channels[i]], 0, meshes.size() - 1)
		instances[i].mesh = meshes[v] as ArrayMesh


## The stage light rig the fighter is lit by (StageLighting.fighter_parameters).
func set_lighting(parameters: Dictionary) -> void:
	_lighting = parameters
	_apply_lighting()


## The back colour the fighter is lit with this frame (StageLighting.fighter_back_colour: the
## pick-up flash, practice's FREEZE SIGNAL, a burning body), in GTE units of 4096, replacing the
## stage's (set_lighting) from the first call on.
func set_back_colour(colour: Vector3) -> void:
	if colour == _back_colour:
		return
	_back_colour = colour
	_apply_lighting()


func _apply_lighting() -> void:
	for material in materials:
		for key: String in _lighting:
			material.set_shader_parameter(key, _lighting[key])
		if _back_colour != NO_BACK_COLOUR:
			material.set_shader_parameter("back_colour", _back_colour)


## The Shading setting's uniforms (fighter_skin.gdshaderinc): the game's own normals or the
## smooth ones, and the curved grids' corners.
func _apply_shading() -> void:
	for material in materials:
		material.set_shader_parameter("smooth_normals", Settings.text("shading") != "original")
		material.set_shader_parameter("smooth_crease_cos", model.smooth_crease_cos)
		material.set_shader_parameter("curved", _curved != null)
		material.set_shader_parameter("corner_data", _curved.texture if _curved != null else null)
		material.set_shader_parameter("corner_texels", CurvedMesh.CORNER_TEXELS)


## The PlayStation's blink: the closed-eye atlas while `closed`.
func set_eyes_closed(closed: bool) -> void:
	set_eye_shape(CharacterModel.CLOSED_SHAPE if closed else CharacterModel.OPEN_SHAPE)


## An arcade model's face for one simulation step (ArcadeFace.step).
func step_face(held: bool, down: bool) -> void:
	set_eye_shape(face.step(held, down))


## An attack shout of voice id `code` (SimEvents SHOUT) changes an arcade model's face.
func shout(code: int) -> void:
	if face != null:
		face.shout(code)


## The atlas with eye shape `shape` over the eyes (the eyes as loaded when the model lacks it).
func set_eye_shape(shape: int) -> void:
	_eye_shape = shape
	_show_atlas()


## PartSelectVertexVariant's palette swap for Gon: it runs for every row of both hand channels
## with that channel's variant (the head's rows 19 and 20 are channel 0's for Gon), and when the
## variant differs from the last it swapped for (fighter +0x1291, 0 when the fight is set up)
## copies his head's palette from the swapped one for the model's `swap_variants`, else back
## from the one FUN_800342a0 saved: channel 1's variant, called last, decides.
func _step_palette(variants: PackedInt32Array) -> void:
	if texture_swap == null or _overhead:
		return
	for variant in variants:
		if variant != _swap_seen:
			_swap_seen = variant
			_swapped = model.swap_variants.has(variant)
	_show_atlas()


## GonEyesSetOffset: Gon's eyes' look direction (`FightState` body.gon_gaze, −17 to 17): eye 0 takes
## the shifts from 0 up, eye 1 those below, the other staying at 0; an eye copies its strip when its
## shift differs from the one it last copied (so one that was never copied keeps the strip as loaded
## while the look stays at 0).
func set_gaze(offset: int) -> void:
	if gaze_atlas == null:
		return
	var wanted := PackedInt32Array([offset if offset >= 0 else 0, offset if offset < 0 else 0])
	for eye in 2:
		if wanted[eye] != _gaze_cache[eye]:
			_gaze_cache[eye] = wanted[eye]
			_gaze_shifts[eye] = wanted[eye]
	_show_atlas()


## Under the overhead KO camera (0x800B08D4: `overhead`) PartSelectVertexVariant leaves Gon's
## palette alone; FUN_80034354 swaps it, once, on his moves with flag 0x40000 (`react_chain`), and
## nothing copies it back before the next fight is set up. Call before set_hands.
func set_overhead(overhead: bool, react_chain: bool) -> void:
	_overhead = overhead
	if overhead and react_chain and texture_swap != null and _swap_seen != OVERHEAD_SEEN:
		_swap_seen = OVERHEAD_SEEN
		_swapped = true
		_show_atlas()


## The atlas for the eye shape, Gon's head palette and his eyes' look direction: the swapped palette
## over the eye shapes (Gon has none), the pasted patches over either.
func _show_atlas() -> void:
	var texture: Texture2D
	if gaze_atlas != null:
		texture = gaze_atlas.show(_swapped, _gaze_shifts)
	else:
		texture = texture_swap if _swapped else eye_textures.get(_eye_shape, texture_open) as Texture2D
	if texture == _albedo:
		return
	_albedo = texture
	for material in materials:
		material.set_shader_parameter("albedo_texture", texture)


## The wind on an arcade model's swinging attachments (ArcadeWind.vector), felt from the next
## set_joints on.
func set_wind(vector: PackedInt32Array) -> void:
	if _arcade != null:
		_arcade.wind = vector


## Hides the faces skinned to the joints of bit mask `mask` (a part the game stops drawing).
func set_hidden_joints(mask: int) -> void:
	if mask == _hidden_joints:
		return
	_hidden_joints = mask
	for material in materials:
		material.set_shader_parameter("hidden_joints", mask)


## Applies the world joint frames of a simulation step (game units), and an arcade model's
## attachment joints built from them. The view node itself stays at the origin: the joints carry
## the fighter's position. `snap` drops interpolation, and an arcade model's attachments start
## again from their rest (the fighter appears: their last step is stale).
func set_joints(joints: Array[JointFrame], snap: bool = false) -> void:
	var all := joints
	if _arcade != null:
		if snap:
			_arcade.reset()
		all = _arcade.update(joints)
	var rows := PackedVector4Array()
	rows.resize(3 * CharacterModel.JOINT_COUNT)
	var bounds := AABB()
	for j in all.size():
		var r := WorldSpace.joint_rows(all[j])
		rows[3 * j] = r[0]
		rows[3 * j + 1] = r[1]
		rows[3 * j + 2] = r[2]
		if j >= joints.size() and not _arcade.has_joint(j):
			continue                    # an attachment the model does not have, at the origin
		var origin := Vector3(r[0].w, r[1].w, r[2].w)
		bounds = AABB(origin, Vector3.ZERO) if j == 0 else bounds.expand(origin)
	_previous_rows = rows if snap or _rows.is_empty() else _rows
	_rows = rows
	_bounds = bounds.grow(BOUNDS_MARGIN)
	show_between(1.0)


## Draws the pose between the previous step (0) and the current one (1).
func show_between(weight: float) -> void:
	if _rows.is_empty():
		return
	var rows := _rows
	if weight < 1.0 and _previous_rows.size() == _rows.size():
		rows = PackedVector4Array()
		rows.resize(_rows.size())
		for i in _rows.size():
			rows[i] = _previous_rows[i].lerp(_rows[i], weight)
	for material in materials:
		material.set_shader_parameter("bone_rows", rows)
	mesh_instance.custom_aabb = _bounds
	for h in hand_instances + wing_instances:
		h.custom_aabb = _bounds


static func _format() -> int:
	return (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_HALF << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
		| (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)


## Splits the converter's interleaved corners (pa, pb, wb, n, uv, bones, the smooth normal's
## halves s_own and s_other, bone_other, the third term pc, wc, bone_c) into mesh arrays: CUSTOM1.w
## is bone_c + wc, UV2 and CUSTOM3.w hold pc; s_own in half precision.
static func _arrays(v: PackedFloat32Array, stride: int) -> Array:
	var count := v.size() / stride
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var custom1 := PackedFloat32Array()
	var custom2 := PackedByteArray()
	var custom3 := PackedFloat32Array()
	var uv2s := PackedVector2Array()
	positions.resize(count)
	normals.resize(count)
	uvs.resize(count)
	custom0.resize(4 * count)
	custom1.resize(4 * count)
	custom2.resize(HALF_RGBA_BYTES * count)
	custom3.resize(4 * count)
	uv2s.resize(count)
	for i in count:
		var o := i * stride
		positions[i] = Vector3(v[o], v[o + 1], v[o + 2])
		custom0[4 * i] = v[o + 3]
		custom0[4 * i + 1] = v[o + 4]
		custom0[4 * i + 2] = v[o + 5]
		custom0[4 * i + 3] = v[o + 6]
		normals[i] = Vector3(v[o + 7], v[o + 8], v[o + 9])
		uvs[i] = Vector2(v[o + 10], v[o + 11])
		custom1[4 * i] = v[o + 12]
		custom1[4 * i + 1] = v[o + 13]
		custom1[4 * i + 2] = v[o + 14]
		custom1[4 * i + 3] = v[o + 27] + v[o + 26]
		uv2s[i] = Vector2(v[o + 23], v[o + 24])
		var h := HALF_RGBA_BYTES * i
		custom2.encode_half(h, v[o + 15])
		custom2.encode_half(h + 2, v[o + 16])
		custom2.encode_half(h + 4, v[o + 17])
		custom2.encode_half(h + 6, v[o + 21])
		custom3[4 * i] = v[o + 18]
		custom3[4 * i + 1] = v[o + 19]
		custom3[4 * i + 2] = v[o + 20]
		custom3[4 * i + 3] = v[o + 25]
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_TEX_UV2] = uv2s
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_CUSTOM1] = custom1
	arrays[Mesh.ARRAY_CUSTOM2] = custom2
	arrays[Mesh.ARRAY_CUSTOM3] = custom3
	return arrays
