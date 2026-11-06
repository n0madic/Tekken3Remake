extends TestSuite
## The flipbook sprites' depth (flipbook.gdshaderinc, sprite_depth_of()): the ordering-table slot the
## game files a sprite under (FUN_80077158: (otz − 0x6E) >> 3 with otz = Z >> 2, slot 1 for the dust
## ring's calls), as the depth the shader draws the whole quad at, in the fighters' faces' scale.
##
## Shaders cannot run in the headless test runner, so this holds the formula as a reference (`_slot`,
## in game units of depth) with the cases that matter, and pins the shader's source to the same
## formula and constants: a change to one without the other fails here. The pictures are checked by
## eye (docs/remake-plan.md, Effects).

const SHADER_INCLUDE := "res://presentation/effects/flipbook.gdshaderinc"
const ENTRY_UNITS := 32


## The slot FUN_80077158 files a sprite centred at the screen depth `z` (game units) under.
static func _slot(z: int, over_all: bool) -> int:
	return 1 if over_all else maxi(((z >> 2) - 0x6E) >> 3, 0)


func test_a_sprite_is_filed_440_units_nearer_than_its_centre() -> void:
	for z: int in [1000, 3200, 4097, 9000]:
		var nearer := z - _slot(z, false) * ENTRY_UNITS
		expect(nearer >= 440 and nearer < 440 + ENTRY_UNITS, "z %d: %d units nearer, to the entry" % [z, nearer])
	expect_equal(_slot(3200, false), 86, "(800 − 110) >> 3")


func test_a_sprite_near_the_camera_takes_the_first_slot() -> void:
	expect_equal(_slot(440, false), 0, "nothing nearer than the first slot")
	expect_equal(_slot(100, false), 0, "a negative one is the first as well")


func test_the_dust_ring_is_in_slot_1_at_any_depth() -> void:
	expect_equal(_slot(100, true), 1, "close")
	expect_equal(_slot(9000, true), 1, "and far")


func test_the_sort_bias_is_the_games() -> void:
	expect_equal(roundi(EffectsView.SORT_BIAS * WorldSpace.UNITS_PER_METRE), 0x6E * 4, "0x6E of otz, 440 units of depth")


func test_the_near_clamp_keeps_a_sprite_in_front_of_the_cameras_near_plane() -> void:
	expect(FaceKeys.NEAR_CLAMP > CameraRig.NEAR, "a clamped sprite is not clipped")
	expect((1 + 0.999) * ENTRY_UNITS / WorldSpace.UNITS_PER_METRE > CameraRig.NEAR, "nor is the dust ring's slot")


## Pins the shader's source to the reference above: its constants and the slot.
func test_shader_is_the_reference() -> void:
	var code := FileAccess.get_file_as_string(SHADER_INCLUDE)
	expect(code.contains("const int SORT_BIAS_OTZ = 0x6E;"), "the bias, in otz")
	expect(code.contains("const int DUST_SLOT = 1;"), "the dust ring's slot")
	expect(code.contains("const float ENTRY_UNITS = %d.0;" % ENTRY_UNITS), "an entry's depth")
	expect(code.contains("uniform float units_per_metre = %s;" % str(snappedf(WorldSpace.UNITS_PER_METRE, 0.1))), "the shader's default unit")
	expect(code.contains("uniform float depth_near = %s;" % str(snappedf(FaceKeys.NEAR_CLAMP, 0.01))), "the shader's default near clamp")
	expect(code.contains("int units = int(max(-view_z * units_per_metre, 0.0));"), "the depth in game units")
	expect(code.contains("int slot = over_all ? DUST_SLOT : max(((units >> 2) - SORT_BIAS_OTZ) >> 3, 0);"), "(otz − 0x6E) >> 3, slot 1 for the dust")
	expect(code.contains("float z = max((float(slot) + ENTRY_LAST) * ENTRY_UNITS / units_per_metre, depth_near);"),
		"the slot's depth, behind the faces filed in it")


func test_shader_draws_a_quad_at_one_depth() -> void:
	var code := FileAccess.get_file_as_string(SHADER_INCLUDE)
	expect(code.contains("POSITION.z = sprite_depth * POSITION.w;"), "clip-space depth shifted to the entry's, constant over the quad")
	expect(code.contains("PROJECTION_MATRIX[3][3] == 0.0"), "not in the orthographic shadow pass")
	expect(code.contains("DEPTH = sprite_depth >= 0.0 ? sprite_depth : FRAGCOORD.z;"), "the Compatibility renderer writes it from the fragment")
	expect(code.contains("#if CURRENT_RENDERER == RENDERER_COMPATIBILITY"), "chosen by the renderer")
	expect(code.contains("VERTEX = centre + vec3(VERTEX.xy * length(MODEL_MATRIX[0].xyz), 0.0);"), "the quad faces the camera, at the node's scale")
