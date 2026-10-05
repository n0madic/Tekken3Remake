extends TestSuite
## The curved surfaces' grids (CurvedMesh) and the flat mesh arrays (FighterView._arrays) on a
## synthetic model: every triangle becomes a LEVEL × LEVEL grid wound like the triangle, its
## corners land in the corner texture in order, the grids are built once per model, and the smooth
## normal's halves reach CUSTOM2 / CUSTOM3 and the third joint's term CUSTOM1.w, UV2 and CUSTOM3.w.

const STRIDE := 28


## A converter corner: positions, seam weight, the game's normal, UV, bones, the smooth normal's
## halves, the other joint, the curves flag and the third joint's term (pc, wc, bone_c).
func _corner(p: Vector3, uv: Vector2, bone: int, curves: bool) -> PackedFloat32Array:
	return PackedFloat32Array([p.x, p.y, p.z, p.x, p.y, p.z, 0.0, 0.0, 1.0, 0.0, uv.x, uv.y,
		bone, bone, bone, 0.0, 2.0, 0.0, 0.5, 0.25, 0.0, 7.0, 1.0 if curves else 0.0,
		3.0, 4.0, 5.0, 0.25, 11.0])


func _surface(triangles: int, bone: int) -> CharacterModel.Surface:
	var surface := CharacterModel.Surface.new()
	for t in triangles:
		surface.vertices.append_array(_corner(Vector3(t, 0, 0), Vector2(0, 0), bone, true))
		surface.vertices.append_array(_corner(Vector3(t + 1, 0, 0), Vector2(1, 0), bone, false))
		surface.vertices.append_array(_corner(Vector3(t, 1, 0), Vector2(0, 1), bone, true))
	return surface


func _model() -> CharacterModel:
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.surfaces.append(_surface(2, 3))
	var hand := CharacterModel.VariantGroup.new()
	hand.variants.append([_surface(1, 9)])
	model.hands.append(hand)
	return model


func test_grid_per_triangle() -> void:
	var model := _model()
	var curved := CurvedMesh.of(model)
	var arrays := curved.arrays(model.surfaces[0])
	var per_triangle := ((CurvedMesh.LEVEL + 1) * (CurvedMesh.LEVEL + 2)) >> 1
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var custom0: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM0]
	var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	expect_equal(positions.size(), 2 * per_triangle, "a grid of vertices per triangle")
	expect_equal(indices.size(), 2 * 3 * CurvedMesh.LEVEL * CurvedMesh.LEVEL, "LEVEL² triangles per triangle")
	expect_equal(custom0[4 * per_triangle], 1.0, "the second grid names the second triangle")
	for i in range(0, indices.size(), 3):
		var a := positions[indices[i]]
		var b := positions[indices[i + 1]]
		var c := positions[indices[i + 2]]
		# Barycentric (w0, w1, w2): the winding of (corner 0, corner 1, corner 2) is positive in
		# the (w1, w2) plane.
		var cross := (b.y - a.y) * (c.z - a.z) - (b.z - a.z) * (c.y - a.y)
		expect(cross > 0.0, "grid triangle at index %d wound like its triangle" % i)
	for i in positions.size():
		var w := positions[i]
		expect(is_equal_approx(w.x + w.y + w.z, 1.0), "barycentric weights sum to 1")
		expect(uvs[i].is_equal_approx(Vector2(w.y, w.z)), "the UV interpolated")


func test_corner_texture() -> void:
	var model := _model()
	var curved := CurvedMesh.of(model)
	var image := curved.texture.get_image()
	expect_equal(image.get_width(), CurvedMesh.DATA_WIDTH, "rows of DATA_WIDTH texels")
	# The hand's surface follows the body's two triangles: its triangle is the third.
	var hand_surface := (model.hands[0].variants[0] as Array)[0] as CharacterModel.Surface
	var hand_custom0: PackedFloat32Array = curved.arrays(hand_surface)[Mesh.ARRAY_CUSTOM0]
	expect_equal(hand_custom0[0], 2.0, "the hand's triangles numbered after the body's")
	var first := 2 * 3 * CurvedMesh.CORNER_TEXELS       # the hand triangle's first corner
	expect(image.get_pixel(first, 0).is_equal_approx(Color(0, 0, 0, 9)), "pa and bone_a")
	expect(image.get_pixel(first + 2, 0).is_equal_approx(Color(0, 2, 0, 2)), "s_own, wb + 2 · curves")
	expect(image.get_pixel(first + 3, 0).is_equal_approx(Color(0.5, 0.25, 0, 7)), "s_other, bone_other")
	expect(image.get_pixel(first + 4, 0).is_equal_approx(Color(0, 1, 0, 9)), "the game's normal, bone_n")
	expect(image.get_pixel(first + 5, 0).is_equal_approx(Color(3, 4, 5, 11.25)), "pc, bone_c + wc")
	expect(image.get_pixel(first + CurvedMesh.CORNER_TEXELS + 2, 0).a == 0.0, "an edge that stays straight")


func test_built_once_per_model() -> void:
	var model := _model()
	expect(CurvedMesh.of(model) == CurvedMesh.of(model), "shared by every view of the model")


func test_grid_index() -> void:
	var seen := {}
	for i in CurvedMesh.LEVEL + 1:
		for j in CurvedMesh.LEVEL + 1 - i:
			seen[CurvedMesh.grid_index(i, j)] = true
	expect_equal(seen.size(), ((CurvedMesh.LEVEL + 1) * (CurvedMesh.LEVEL + 2)) >> 1, "every grid vertex its own index")
	expect_equal(CurvedMesh.grid_index(CurvedMesh.LEVEL, 0), seen.size() - 1, "the last one last")


func test_flat_arrays_carry_the_halves() -> void:
	var arrays := FighterView._arrays(_surface(1, 4).vertices, STRIDE)
	var custom1: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM1]
	var custom2: PackedByteArray = arrays[Mesh.ARRAY_CUSTOM2]
	var custom3: PackedFloat32Array = arrays[Mesh.ARRAY_CUSTOM3]
	var uv2s: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	expect_equal(custom2.size(), 3 * FighterView.HALF_RGBA_BYTES, "four halves per vertex")
	expect_equal(custom2.decode_half(2), 2.0, "s_own.y")
	expect_equal(custom2.decode_half(6), 7.0, "bone_other")
	expect_equal(custom3[0], 0.5, "s_other.x")
	expect_equal(custom3[1], 0.25, "s_other.y")
	expect_equal(custom1[3], 11.25, "bone_c + wc")
	expect_equal(uv2s[0], Vector2(3, 4), "pc.xy")
	expect_equal(custom3[3], 5.0, "pc.z")
