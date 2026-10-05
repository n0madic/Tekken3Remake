class_name CurvedMesh
extends RefCounted
## The fighters' curved surfaces (the Shading setting's "curved"): every triangle of a model is
## drawn as a grid of LEVEL × LEVEL smaller ones whose vertices the shader lifts onto the
## triangle's PN patch (curved point-normal triangles) after skinning its three corners.
##
## The corners of every surface the model has (body, hand and wing variants) go into one float texture,
## CORNER_TEXELS texels each (fighter_skin.gdshaderinc, corner()); a grid vertex keeps its
## triangle's index and its barycentric weights in CUSTOM0 and the interpolated UV. Built once
## per model (`of`) and shared by every view of it.

const LEVEL := 3
const DATA_WIDTH := 1024                ## texels per row of the corner texture
const CORNER_TEXELS := 6

var texture: ImageTexture               ## the corners of every surface
var _arrays: Dictionary = {}            ## CharacterModel.Surface → its grid's mesh arrays
var _data := PackedFloat32Array()       ## RGBA per texel
var _triangles := 0
var _grid_uvw: Array[Vector3] = []      ## barycentric weights of the grid's vertices
var _grid_indices := PackedInt32Array()


## The curved grids of `model`, built on first use and kept on the model.
static func of(model: CharacterModel) -> CurvedMesh:
	if model.curved_cache == null:
		model.curved_cache = CurvedMesh.new(model)
	return model.curved_cache as CurvedMesh


func _init(model: CharacterModel) -> void:
	_build_grid()
	for surface in model.surfaces:
		_arrays[surface] = _add(surface.vertices, model.vertex_floats)
	for group in model.variant_groups():
		for variant: Array in group.variants:
			for surface: CharacterModel.Surface in variant:
				_arrays[surface] = _add(surface.vertices, model.vertex_floats)
	texture = _texture()
	_data = PackedFloat32Array()


## The mesh arrays of one of the model's surfaces.
func arrays(surface: CharacterModel.Surface) -> Array:
	return _arrays[surface]


static func format() -> int:
	return Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT


func _build_grid() -> void:
	for i in LEVEL + 1:
		for j in LEVEL + 1 - i:
			_grid_uvw.append(Vector3(LEVEL - i - j, i, j) / LEVEL)
	# Vertex (i, j) moves i steps towards corner 1 and j towards corner 2; both kinds of grid
	# triangle keep the winding of (corner 0, corner 1, corner 2).
	for i in LEVEL:
		for j in LEVEL - i:
			_grid_indices.append_array([grid_index(i, j), grid_index(i + 1, j), grid_index(i, j + 1)])
			if i + j + 1 < LEVEL:
				_grid_indices.append_array([grid_index(i + 1, j), grid_index(i + 1, j + 1), grid_index(i, j + 1)])


## The index of grid vertex (i, j) in rows of LEVEL + 1, LEVEL, ... vertices.
static func grid_index(i: int, j: int) -> int:
	return i * (LEVEL + 1) - ((i * (i - 1)) >> 1) + j


## The grid arrays of a surface (converter corners of `stride` floats); stores its corners.
func _add(v: PackedFloat32Array, stride: int) -> Array:
	var triangles := v.size() / stride / 3
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var indices := PackedInt32Array()
	for t in triangles:
		var corner_uvs: Array[Vector2] = []
		for k in 3:
			var o := (3 * t + k) * stride
			corner_uvs.append(Vector2(v[o + 10], v[o + 11]))
			# pa, bone_a | pb, bone_b | s_own, wb + 2 · curves | s_other, bone_other | the game's n,
			# bone_n | pc, bone_c + wc
			_data.append_array([v[o], v[o + 1], v[o + 2], v[o + 12],
				v[o + 3], v[o + 4], v[o + 5], v[o + 13],
				v[o + 15], v[o + 16], v[o + 17], v[o + 6] + 2.0 * v[o + 22],
				v[o + 18], v[o + 19], v[o + 20], v[o + 21],
				v[o + 7], v[o + 8], v[o + 9], v[o + 14],
				v[o + 23], v[o + 24], v[o + 25], v[o + 27] + v[o + 26]])
		var base := positions.size()
		for w in _grid_uvw:
			positions.append(w)
			uvs.append(corner_uvs[0] * w.x + corner_uvs[1] * w.y + corner_uvs[2] * w.z)
			custom0.append_array([_triangles + t, w.x, w.y, w.z])
		for index in _grid_indices:
			indices.append(base + index)
	_triangles += triangles
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _texture() -> ImageTexture:
	var texels := _data.size() / 4
	var height := maxi(1, ceili(float(texels) / DATA_WIDTH))
	var data := _data.duplicate()
	data.resize(DATA_WIDTH * height * 4)
	var image := Image.create_from_data(DATA_WIDTH, height, false, Image.FORMAT_RGBAF, data.to_byte_array())
	return ImageTexture.create_from_image(image)
