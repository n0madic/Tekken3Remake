extends TestSuite
## The fighters' face depth (fighter_skin.gdshaderinc, face_key_depth()): the ordering-table entry
## the game files a face under, as the depth the shader draws all of the face at.
##
## Shaders cannot run in the headless test runner, so this holds the formula as a reference
## (`_depth`, in game units of depth) with the cases that matter, checks that the key texture's
## corner numbers lead the shader to the right corners, and pins the shader's source to the same
## formula and constants: a change to one without the other fails here. The pictures are checked by
## eye (docs/remake-plan.md, Characters).

const SHADER_INCLUDE := "res://presentation/fighter/fighter_skin.gdshaderinc"
const TABLE_ENTRIES := 1024
const ENTRY_UNITS := 32
const STRIDE := 28


## face_key_depth() in game units of depth. `z0` and `zk` are the screen depths (SZ) of the face's
## corner 0 and key corner, `front` its NCLIP > 0 (the bias changes sign behind), `rank` the
## fighter's place in the drawing order and `face` its number among the model's `faces`. −1: past
## the table's last entry, the face keeps its own depth.
static func _depth(z0: int, zk: int, bias: int, front: bool, rank: int, face: int, faces: int) -> float:
	var sum := (z0 >> 5) + (zk >> 5) - (bias if front else -bias)
	if sum >= 2 * TABLE_ENTRIES:
		return -1.0
	var tie := (minf(rank, FaceKeys.FIGHTER_SLOTS - 1) + (face + 0.5) / faces) / FaceKeys.FIGHTER_SLOTS
	return ((maxi(sum, 0) >> 1) + tie) * ENTRY_UNITS


## The entry (0..1023) a depth in game units lies in.
static func _entry(depth: float) -> int:
	return int(depth) / ENTRY_UNITS


func test_a_face_lies_in_the_entry_of_its_two_corners_mean() -> void:
	expect_equal(_entry(_depth(3200, 3200, 0, true, 0, 0, 1)), 100, "corners of 100 entries each")
	expect_equal(_entry(_depth(3200, 3520, 0, true, 0, 0, 1)), 105, "a quad's far corner 3 counts, not corner 2")
	expect_equal(_entry(_depth(3232, 3200, 0, true, 0, 0, 1)), 100, "an odd sum rounds down: the mask clears bit 0")


func test_bias_moves_a_face_nearer_in_front_and_farther_behind() -> void:
	expect_equal(_entry(_depth(3200, 3200, 6, true, 0, 0, 1)), 97, "bias 6 subtracts from the sum")
	expect_equal(_entry(_depth(3200, 3200, 6, false, 0, 0, 1)), 103, "seen from behind its sign flips")
	expect_equal(_entry(_depth(3200, 3200, -6, true, 0, 0, 1)), 103, "a negative bias pushes it back")


func test_entries_outside_the_table() -> void:
	expect_equal(_entry(_depth(64, 64, 63, true, 0, 0, 1)), 0, "a close-up's negative sum takes the first entry")
	expect_equal(_depth(32 * 1023, 32 * 1025, 0, true, 0, 0, 1) >= 0.0, false, "past the last entry: its own depth")
	expect_equal(_entry(_depth(32 * 1023, 32 * 1024, 0, true, 0, 0, 1)), 1023, "the last entry is still in")


func test_the_first_player_is_over_the_second_and_a_lower_face_over_a_higher() -> void:
	var first_player := _depth(3200, 3200, 0, true, 0, 300, 400)
	var second_player := _depth(3200, 3200, 0, true, 1, 0, 900)
	expect(first_player < second_player, "the first player's last face is nearer than the second's first")
	expect(_depth(3200, 3200, 0, true, 0, 0, 400) < _depth(3200, 3200, 0, true, 0, 1, 400), "face 0 is over face 1")
	for rank in 3:
		var depth := _depth(3200, 3200, 0, true, rank, 399, 400)
		expect_equal(_entry(depth), 100, "every tie-break stays inside its entry (rank %d)" % rank)
	expect_equal(_entry(_depth(3200, 3200, 0, true, 7, 399, 400)), 100, "so does a rank past the last slot")


func test_the_near_clamp_is_in_front_of_the_cameras_near_plane() -> void:
	expect(FaceKeys.NEAR_CLAMP > CameraRig.NEAR, "a clamped face is not clipped")
	expect(FaceKeys.NEAR_CLAMP < 0.5, "and not far from it")


## A quad (corners P0–P3 drawn as the triangles 0 1 2 and 1 3 2, one key) in the body: the key
## texture must lead to P3 as its key corner, and to P0, P1, P2 as its first three.
func test_the_key_corner_of_a_quad_resolves_to_its_fourth_point() -> void:
	var points := [Vector3(1, 0, 0), Vector3(2, 0, 0), Vector3(3, 0, 0), Vector3(4, 0, 0)]
	var surface := CharacterModel.Surface.new()
	for i: int in [0, 1, 2, 1, 3, 2]:
		var corner := PackedFloat32Array()
		corner.resize(STRIDE)
		var p: Vector3 = points[i]
		corner[0] = p.x
		corner[1] = p.y
		corner[2] = p.z
		surface.vertices.append_array(corner)
	surface.keys = PackedInt32Array([0, 1, 2, 4, 5, 0, 0, 1, 2, 4, 5, 0])
	var model := CharacterModel.new()
	model.vertex_floats = STRIDE
	model.face_count = 1
	model.surfaces.append(surface)
	var keys := FaceKeys.of(model)
	var corners_image := keys.corners.get_image()
	var key_image := keys.keys.get_image()
	for triangle in 2:
		var row := key_image.get_pixel(triangle * FaceKeys.KEY_TEXELS, 0)
		var found: Array[float] = []
		for k in 4:
			var number_float: float = row[k]
			var number := int(number_float)
			var texel := number * FaceKeys.CORNER_TEXELS
			found.append(corners_image.get_pixel(texel % FaceKeys.DATA_WIDTH, texel / FaceKeys.DATA_WIDTH).r)
		expect_equal(found, [1.0, 2.0, 3.0, 4.0], "triangle %d: corners 0, 1, 2 and the key corner" % triangle)


## Pins the shader's source to the reference above: its constants, the sum, the bias's sign, the
## entry and the tie-break.
func test_shader_is_the_reference() -> void:
	var code := FileAccess.get_file_as_string(SHADER_INCLUDE)
	expect(code.contains("const float TABLE_ENTRIES = %d.0;" % TABLE_ENTRIES), "the table's entries")
	expect(code.contains("const float ENTRY_UNITS = %d.0;" % ENTRY_UNITS), "an entry's depth")
	expect(code.contains("uniform int fighter_slots = %d;" % FaceKeys.FIGHTER_SLOTS), "the fighter slots of the tie-break")
	expect(code.contains("uniform float face_near = %s;" % str(snappedf(FaceKeys.NEAR_CLAMP, 0.01))), "the shader's default near clamp")
	expect(code.contains("(int(max(-v0.z * units_per_metre, 0.0)) >> 5) + (int(max(-vk.z * units_per_metre, 0.0)) >> 5) - bias;"),
		"the sum of the two corners' Z >> 5 less the bias")
	expect(code.contains("if (dot(cross(v1 - v0, v2 - v0), v0) <= 0.0) {\n\t\t\tbias = -bias;"), "the bias flips behind")
	expect(code.contains("if (bias != 0) {"), "the facing is only worked out for a face with a bias")
	expect(code.contains("if (sum >= 2 * int(TABLE_ENTRIES)) {\n\t\treturn -1.0;"), "past the table")
	expect(code.contains("float entry = float(max(sum, 0) >> 1) + rank;"), "the entry, the first at least")
	expect(code.contains("float rank = (float(min(fighter_rank, fighter_slots - 1)) + within) / float(fighter_slots);"), "the tie-break")
	expect(code.contains("float within = (info.y + 0.5) / float(face_count);"), "by face number")


func test_shader_draws_a_face_at_one_depth() -> void:
	var code := FileAccess.get_file_as_string(SHADER_INCLUDE)
	expect(code.contains("POSITION.z = face_depth * POSITION.w;"), "clip-space depth shifted to the face's, constant over it")
	expect(code.contains("PROJECTION_MATRIX[3][3] == 0.0"), "not in the orthographic shadow pass")
	expect(code.contains("DEPTH = face_depth >= 0.0 ? face_depth : FRAGCOORD.z;"), "the Compatibility renderer writes it from the fragment")
	expect(code.contains("#if CURRENT_RENDERER == RENDERER_COMPATIBILITY"), "chosen by the renderer")
