extends TestSuite
## The sword glow's drawing (SwordGlowView): where a quad's corners stand in view space, the
## depth of the ordering-table entry it is filed in, the colour and the picture's coordinates, and
## the mesh a ribbon makes.

const FRAME_TAN := Vector2(1.5, 0.9)


func _ribbon(textured: bool) -> SwordGlow.Ribbon:
	var ribbon := SwordGlow.Ribbon.new()
	for p in SwordGlow.POINTS:
		ribbon.points.append(150 + 5 * p)
		ribbon.points.append(100 + 9 * p)
	ribbon.depth = PackedInt32Array([40, 41, 42, 43])
	ribbon.colour = Vector3i(0x40, 0x20, 0)
	ribbon.textured = textured
	return ribbon


func _near(actual: float, expected: float, epsilon: float, message: String) -> void:
	expect(absf(actual - expected) <= epsilon, "%s: %s, expected %s" % [message, actual, expected])


func _mesh(view: SwordGlowView) -> ImmediateMesh:
	var instance: MeshInstance3D = view.get_child(0)
	return instance.mesh as ImmediateMesh


func _vertices(view: SwordGlowView) -> int:
	var mesh := _mesh(view)
	if mesh.get_surface_count() == 0:
		return 0
	var vertices: PackedVector3Array = mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	return vertices.size()


func test_the_screen_centre_is_on_the_view_axis() -> void:
	var at := SwordGlowView.view_position(Vector2(ViewMatrix.SCREEN_OFFSET_X, ViewMatrix.SCREEN_OFFSET_Y), 4.0, FRAME_TAN)
	_near(at.x, 0.0, 1e-6, "x")
	_near(at.y, 0.0, 1e-6, "y")
	_near(at.z, -4.0, 1e-6, "z: in front of the camera")


func test_the_frame_edges_reach_the_frame_extent_at_their_depth() -> void:
	var right := SwordGlowView.view_position(Vector2(ViewMatrix.SCREEN_OFFSET_X + CameraRig.HALF_WIDTH, ViewMatrix.SCREEN_OFFSET_Y), 2.0, FRAME_TAN)
	_near(right.x, FRAME_TAN.x * 2.0, 1e-5, "the right edge")
	var top := SwordGlowView.view_position(Vector2(ViewMatrix.SCREEN_OFFSET_X, 0), 2.0, FRAME_TAN)
	_near(top.y, FRAME_TAN.y * 2.0, 1e-5, "the top of the screen is up")
	var bottom := SwordGlowView.view_position(Vector2(ViewMatrix.SCREEN_OFFSET_X, 2 * ViewMatrix.SCREEN_OFFSET_Y), 2.0, FRAME_TAN)
	_near(bottom.y, -FRAME_TAN.y * 2.0, 1e-5, "the bottom is down")


func test_an_entry_is_as_deep_as_its_far_edge_but_never_inside_the_near_limit() -> void:
	_near(SwordGlowView.entry_depth(100), (100 + 0.999) * 32.0 / WorldSpace.UNITS_PER_METRE, 1e-6, "entry 100")
	expect_equal(SwordGlowView.entry_depth(0), FaceKeys.NEAR_CLAMP, "entry 0")
	expect(SwordGlowView.entry_depth(60) > SwordGlowView.entry_depth(59), "deeper entries are further away")


func test_the_vertex_colour_is_the_games_over_0x80() -> void:
	expect_equal(SwordGlowView.vertex_colour(Vector3i(0x40, 0x20, 0)), Color(0.5, 0.25, 0.0), "colour")
	expect_equal(SwordGlowView.vertex_colour(Vector3i(0x80, 0x80, 0x80)), Color.WHITE, "full")


func test_texels_are_the_centres_of_the_pictures_columns_and_rows() -> void:
	var columns := ArcadeSwordGlow.PICTURE + 1.0
	expect_equal(SwordGlowView.texture_coordinate(Vector2i(0, 0)), Vector2(0.5 / columns, 0.5 / ArcadeSwordGlow.PICTURE), "the first texel")
	expect_equal(SwordGlowView.texture_coordinate(Vector2i(15, 15)), Vector2(15.5 / columns, 15.5 / ArcadeSwordGlow.PICTURE), "the last texel")
	_near(SwordGlowView.texture_coordinate(Vector2i(-1, 0)).x, (columns - 0.5) / columns, 1e-6, "the white column")


func test_the_picture_needs_all_its_levels() -> void:
	var view := SwordGlowView.new()
	expect(not view.has_levels(), "none to begin with")
	view.set_levels(PackedInt32Array([1, 2, 3]))
	expect(not view.has_levels(), "too few levels")
	var levels := PackedInt32Array()
	levels.resize(ArcadeSwordGlow.PICTURE * ArcadeSwordGlow.PICTURE)
	view.set_levels(levels)
	expect(view.has_levels(), "a full picture")
	view.set_levels(PackedInt32Array())
	expect(not view.has_levels(), "cleared")
	view.free()


func test_a_ribbon_makes_ten_quads_and_no_ribbon_no_mesh() -> void:
	var view := SwordGlowView.new()
	view.show_between(1.0, FRAME_TAN)
	expect_equal(_vertices(view), 0, "nothing without a ribbon")
	view.set_ribbon(0, _ribbon(false), true)
	view.show_between(1.0, FRAME_TAN)
	expect_equal(_vertices(view), SwordGlow.QUADS * 6, "two triangles a quad")
	view.set_ribbon(1, _ribbon(true), true)
	view.show_between(0.5, FRAME_TAN)
	expect_equal(_vertices(view), 2 * SwordGlow.QUADS * 6, "a second fighter's ribbon")
	view.set_ribbon(0, null)
	view.set_ribbon(1, null)
	view.show_between(1.0, FRAME_TAN)
	expect_equal(_vertices(view), 0, "both gone")
	view.free()


func test_an_appearing_ribbon_is_not_blended_from_the_old_one() -> void:
	var view := SwordGlowView.new()
	var far := _ribbon(false)
	for i in far.points.size():
		far.points[i] += 1000
	view.set_ribbon(0, far, true)
	view.set_ribbon(0, _ribbon(false), true)
	view.show_between(0.0, FRAME_TAN)
	var vertices: PackedVector3Array = _mesh(view).surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var first := SwordGlowView.view_position(Vector2(_ribbon(false).points[2 * SwordGlow.corner(0, 0)], _ribbon(false).points[2 * SwordGlow.corner(0, 0) + 1]),
			SwordGlowView.entry_depth(SwordGlow.entry(_ribbon(false), 0)), FRAME_TAN)
	_near(vertices[0].x, first.x, 1e-5, "at its own place from the first step")
	view.free()
