class_name CurvedMesh
extends RefCounted
## The fighters' curved surfaces (the Shading setting's "curved"): every triangle of a model is
## drawn as a grid of LEVEL × LEVEL smaller ones whose vertices the shader lifts onto the
## triangle's PN patch (curved point-normal triangles) after skinning its three corners.
##
## The corners of every surface the model has (body, hand and wing variants) are in FaceKeys'
## corner texture (fighter_skin.gdshaderinc, corner()); a grid vertex keeps its triangle's number
## there and its barycentric weights in CUSTOM0 and the interpolated UV. Built once per model
## (`of`) and shared by every view of it.

const LEVEL := 3

var _keys: FaceKeys
var _arrays: Dictionary = {}            ## CharacterModel.Surface → its grid's mesh arrays
var _grid_uvw: Array[Vector3] = []      ## barycentric weights of the grid's vertices
var _grid_indices := PackedInt32Array()


## The curved grids of `model`, built on first use and kept on the model.
static func of(model: CharacterModel) -> CurvedMesh:
	if model.curved_cache == null:
		model.curved_cache = CurvedMesh.new(model)
	return model.curved_cache as CurvedMesh


func _init(model: CharacterModel) -> void:
	_keys = FaceKeys.of(model)
	_build_grid()
	for surface in model.surfaces:
		_arrays[surface] = _add(surface, model.vertex_floats)
	for group in model.variant_groups():
		for variant: Array in group.variants:
			for surface: CharacterModel.Surface in variant:
				_arrays[surface] = _add(surface, model.vertex_floats)


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


## The grid arrays of a surface (converter corners of `stride` floats).
func _add(surface: CharacterModel.Surface, stride: int) -> Array:
	var v := surface.vertices
	var triangles := v.size() / stride / 3
	var first := _keys.first(surface)
	var positions := PackedVector3Array()
	var uvs := PackedVector2Array()
	var custom0 := PackedFloat32Array()
	var indices := PackedInt32Array()
	for t in triangles:
		var corner_uvs: Array[Vector2] = []
		for k in 3:
			var o := (3 * t + k) * stride
			corner_uvs.append(Vector2(v[o + 10], v[o + 11]))
		var base := positions.size()
		for w in _grid_uvw:
			positions.append(w)
			uvs.append(corner_uvs[0] * w.x + corner_uvs[1] * w.y + corner_uvs[2] * w.z)
			custom0.append_array([first + t, w.x, w.y, w.z])
		for index in _grid_indices:
			indices.append(base + index)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_CUSTOM0] = custom0
	arrays[Mesh.ARRAY_INDEX] = indices
	return arrays
