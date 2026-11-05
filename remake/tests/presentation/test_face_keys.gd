extends TestSuite
## The fighters' sort keys (FaceKeys, fighter_skin.gdshaderinc): the converter's per-triangle keys
## reach the key texture with corner numbers over the whole model, the flat meshes name their
## triangles in the vertex colour, and the shader draws a face at one depth.

const STRIDE := 28
const SHADER_INCLUDE := "res://presentation/fighter/fighter_skin.gdshaderinc"


func _corner(bone: int) -> PackedFloat32Array:
	var corner := PackedFloat32Array()
	corner.resize(STRIDE)
	corner[12] = bone
	corner[13] = bone
	corner[14] = bone
	return corner


func _surface(triangles: int, keys: Array = []) -> CharacterModel.Surface:
	var surface := CharacterModel.Surface.new()
	for i in triangles * 3:
		surface.vertices.append_array(_corner(i % 5))
	surface.keys = PackedInt32Array(keys)
	return surface


## A quad face (number 0, bias 3: two triangles sharing one key whose key corner is the second
## triangle's middle vertex) in the body, and a triangle face (number 1, bias −6) in a hand.
func _model() -> CharacterModel:
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.face_count = 2
	model.surfaces.append(_surface(2, [0, 1, 2, 4, 3, 0, 0, 1, 2, 4, 3, 0]))
	var hand := CharacterModel.VariantGroup.new()
	hand.variants.append([_surface(1, [0, 1, 2, 2, -6, 1])])
	model.hands.append(hand)
	return model


func test_triangles_are_numbered_over_the_surfaces() -> void:
	var model := _model()
	var keys := FaceKeys.of(model)
	var hand_surface := (model.hands[0].variants[0] as Array)[0] as CharacterModel.Surface
	expect_equal(keys.first(model.surfaces[0]), 0, "the body first")
	expect_equal(keys.first(hand_surface), 2, "the hand after the body's two triangles")
	expect_equal(keys.triangles, 3, "all the triangles")
	expect(FaceKeys.of(model) == keys, "built once per model")


func test_key_texture_holds_corner_numbers_of_the_whole_model() -> void:
	var model := _model()
	var image := FaceKeys.of(model).keys.get_image()
	expect_equal(image.get_width(), FaceKeys.DATA_WIDTH, "rows of DATA_WIDTH texels")
	expect(image.get_pixel(0, 0).is_equal_approx(Color(0, 1, 2, 4)), "the quad's first triangle: its face's corners and key corner")
	expect(image.get_pixel(1, 0).is_equal_approx(Color(3, 0, 0, 0)), "the bias and the face number")
	# The second triangle's vertices are 3–5 of the surface, but its face's corners are the first's.
	expect(image.get_pixel(FaceKeys.KEY_TEXELS, 0).is_equal_approx(Color(0, 1, 2, 4)), "the second triangle shares the face's key")
	# The hand's first corner is corner 6 of the model.
	var hand := FaceKeys.KEY_TEXELS * 2
	expect(image.get_pixel(hand, 0).is_equal_approx(Color(6, 7, 8, 8)), "the hand's corners numbered after the body's")
	expect(image.get_pixel(hand + 1, 0).is_equal_approx(Color(-6, 1, 0, 0)), "a negative bias and face 1")


func test_corner_texture_is_shared_with_the_curved_grids() -> void:
	var model := _model()
	var keys := FaceKeys.of(model)
	var image := keys.corners.get_image()
	var hand_corner := 6 * FaceKeys.CORNER_TEXELS      # the hand's first corner, bone 0 (vertex 0 % 5)
	expect_equal(image.get_pixel(hand_corner, 0).a, 0.0, "pa's joint")
	expect_equal(image.get_width(), FaceKeys.DATA_WIDTH, "the corner texture's rows")
	expect_equal(keys.corners.get_height() * FaceKeys.DATA_WIDTH >= keys.triangles * 3 * FaceKeys.CORNER_TEXELS, true, "room for every corner")
	var hand_surface := (model.hands[0].variants[0] as Array)[0] as CharacterModel.Surface
	var custom0: PackedFloat32Array = CurvedMesh.of(model).arrays(hand_surface)[Mesh.ARRAY_CUSTOM0]
	expect_equal(custom0[0], 2.0, "a curved grid names the same triangle number")


func test_flat_corners_name_their_triangle_in_the_colour() -> void:
	var model := _model()
	var keys := FaceKeys.of(model)
	var colours := keys.colors(model.surfaces[0], STRIDE)
	expect_equal(colours.size(), 6, "a colour per corner")
	expect_equal([colours[0], colours[2], colours[3], colours[5]], [Color8(0, 0, 0), Color8(0, 0, 0), Color8(1, 0, 0), Color8(1, 0, 0)],
		"three corners to a triangle")
	var hand_surface := (model.hands[0].variants[0] as Array)[0] as CharacterModel.Surface
	expect_equal(keys.colors(hand_surface, STRIDE)[1], Color8(2, 0, 0), "the hand's triangle after the body's")


func test_triangle_numbers_beyond_a_byte() -> void:
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.surfaces.append(_surface(70000))
	var colours := FaceKeys.of(model).colors(model.surfaces[0], STRIDE)
	var last := 70000 - 1
	expect_equal(colours[3 * last + 1], Color8(last & 0xFF, (last >> 8) & 0xFF, last >> 16), "three bytes of the number")


func test_model_without_keys_has_no_key_texture() -> void:
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.surfaces.append(_surface(1))
	var keys := FaceKeys.of(model)
	expect(not keys.has_keys and keys.keys == null, "no keys, no texture")
	expect(keys.corners != null, "the corners are still there for the curved grids")


func test_surfaces_load_their_keys() -> void:
	var corners := PackedFloat32Array()
	corners.resize(3 * STRIDE)
	var blob := corners.to_byte_array()
	var keys_at := blob.size()
	blob.append_array(PackedInt32Array([0, 1, 2, 2, -4, 7]).to_byte_array())
	var surfaces := CharacterModel._surfaces([{"double_sided": true, "offset": 0, "vertex_count": 3, "keys": keys_at},
		{"double_sided": false, "offset": 0, "vertex_count": 3}], blob, STRIDE)
	expect_equal(surfaces[0].keys, PackedInt32Array([0, 1, 2, 2, -4, 7]), "the triangle's six ints")
	expect(surfaces[1].keys.is_empty(), "a surface of an older conversion has none")


func test_shader_draws_a_face_at_one_depth() -> void:
	var code := FileAccess.get_file_as_string(SHADER_INCLUDE)
	expect(code.contains("float face_key_depth("), "the key's depth")
	expect(code.contains("POSITION.z = face_depth * POSITION.w;"), "clip-space depth shifted to the face's, constant over it")
	expect(code.contains("PROJECTION_MATRIX[3][3] == 0.0"), "not in the orthographic shadow pass")
	expect(code.contains("DEPTH = face_depth >= 0.0 ? face_depth : FRAGCOORD.z;"), "the Compatibility renderer writes it from the fragment")
	expect(code.contains("#if CURRENT_RENDERER == RENDERER_COMPATIBILITY"), "chosen by the renderer")
