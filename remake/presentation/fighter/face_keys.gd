class_name FaceKeys
extends RefCounted
## The fighters' per-triangle data for the shaders (fighter_skin.gdshaderinc), built once per
## model and shared by every view of it:
##
## - the corners of every surface the model has (body, hand and wing variants) in one float texture,
##   CORNER_TEXELS texels each (corner(), corner_point()), which CurvedMesh's grids and the sort
##   keys read;
## - per triangle, the sort key of its face in a second one, KEY_TEXELS texels each: the face's
##   corners 0, 1, 2 and key corner (corner numbers in the first texture), then its bias and number
##   (face_key_depth()). The game files a face in its ordering table under the depths of two of its
##   corners less the bias, so the shader draws all of the face at the depth that entry stands for
##   (docs/research/formats/3dmk-models.md#drawing-order).
##
## Triangles are numbered over the model's surfaces in order: the body's, then each variant group's.
## A flat mesh names the triangle of each corner in its vertex colour (`colors`), a curved grid in
## CUSTOM0.x.

const DATA_WIDTH := 1024                ## texels per row of both textures
const CORNER_TEXELS := 6
const KEY_TEXELS := 2

var corners: ImageTexture               ## the corners of every surface
var keys: ImageTexture                  ## the triangles' sort keys, null when the model has none
var has_keys := false
var triangles := 0
var _first: Dictionary = {}             ## CharacterModel.Surface → the number of its first triangle
var _colors: Dictionary = {}            ## CharacterModel.Surface → its corners' triangle numbers as colours
var _corner_data := PackedFloat32Array()     ## RGBA per texel
var _key_data := PackedFloat32Array()


## The corners and keys of `model`, built on first use and kept on the model.
static func of(model: CharacterModel) -> FaceKeys:
	if model.keys_cache == null:
		model.keys_cache = FaceKeys.new(model)
	return model.keys_cache as FaceKeys


func _init(model: CharacterModel) -> void:
	has_keys = model.face_count > 0
	for surface in model.surfaces:
		_add(surface, model.vertex_floats)
	for group in model.variant_groups():
		for variant: Array in group.variants:
			for surface: CharacterModel.Surface in variant:
				_add(surface, model.vertex_floats)
	corners = _texture(_corner_data)
	keys = _texture(_key_data) if has_keys else null
	_corner_data = PackedFloat32Array()
	_key_data = PackedFloat32Array()


## The number of `surface`'s first triangle.
func first(surface: CharacterModel.Surface) -> int:
	return _first[surface]


## The vertex colours of a flat `surface`'s corners, which hold the number of their triangle in
## the colour's bytes (red the lowest).
func colors(surface: CharacterModel.Surface, stride: int) -> PackedColorArray:
	if not _colors.has(surface):
		var out := PackedColorArray()
		var base := first(surface)
		for i in surface.vertices.size() / stride:
			var n := base + i / 3
			out.append(Color8(n & 0xFF, (n >> 8) & 0xFF, (n >> 16) & 0xFF))
		_colors[surface] = out
	return _colors[surface]


## Stores a surface's corners (converter corners of `stride` floats) and keys.
func _add(surface: CharacterModel.Surface, stride: int) -> void:
	var v := surface.vertices
	var count := v.size() / stride / 3
	_first[surface] = triangles
	for t in count:
		for k in 3:
			var o := (3 * t + k) * stride
			# pa, bone_a | pb, bone_b | s_own, wb + 2 · curves | s_other, bone_other | the game's n,
			# bone_n | pc, bone_c + wc
			_corner_data.append_array([v[o], v[o + 1], v[o + 2], v[o + 12],
				v[o + 3], v[o + 4], v[o + 5], v[o + 13],
				v[o + 15], v[o + 16], v[o + 17], v[o + 6] + 2.0 * v[o + 22],
				v[o + 18], v[o + 19], v[o + 20], v[o + 21],
				v[o + 7], v[o + 8], v[o + 9], v[o + 14],
				v[o + 23], v[o + 24], v[o + 25], v[o + 27] + v[o + 26]])
	if has_keys:
		var corner_base := 3 * triangles
		for t in count:
			var o := t * CharacterModel.FACE_KEY_INTS
			if surface.keys.is_empty():
				_key_data.append_array([0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])
				continue
			# The key's corners are vertex numbers in the surface: here they are corner numbers.
			_key_data.append_array([corner_base + surface.keys[o], corner_base + surface.keys[o + 1],
				corner_base + surface.keys[o + 2], corner_base + surface.keys[o + 3],
				surface.keys[o + 4], surface.keys[o + 5], 0.0, 0.0])
	triangles += count


static func _texture(data: PackedFloat32Array) -> ImageTexture:
	var texels := data.size() / 4
	var height := maxi(1, ceili(float(texels) / DATA_WIDTH))
	var padded := data.duplicate()
	padded.resize(DATA_WIDTH * height * 4)
	var image := Image.create_from_data(DATA_WIDTH, height, false, Image.FORMAT_RGBAF, padded.to_byte_array())
	return ImageTexture.create_from_image(image)
