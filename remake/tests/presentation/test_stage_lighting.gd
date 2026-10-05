extends TestSuite
## The stage's light rig from its record: the fighters' parameters (StageLighting.fighter_parameters,
## stages.md#lighting) and the environment each view's camera carries.


func _stage(number: int) -> StageData:
	var s := StageData.new()
	s.number = number
	s.ambient = 137
	s.base_colour = Vector3(126, 126, 128) / StageData.BASE_NEUTRAL
	s.light_colour = Color8(234, 220, 188)
	s.light_pitch = 512
	s.light_yaw = 2560
	return s


func test_gte_units() -> void:
	var p := StageLighting.fighter_parameters(_stage(4))
	expect_equal(p["back_colour"], Vector3.ONE * (137 * 16 / 4096.0), "SetBackColor: ambient << 4")
	expect_equal(StageLighting.back_colour(250, 0, 0), Vector3(250 * 16 / 4096.0, 0, 0), "the FREEZE SIGNAL's red")
	expect_equal(p["light_colour"], Vector3(234, 220, 188) / 256.0, "colour matrix column 0: byte << 4")
	expect_equal(p["fill_colour"], Vector3(117, 110, 94) / 256.0, "the light from below: (byte >> 1) << 4")
	expect_equal(p["base_colour"], Vector3(126, 126, 128) / 128.0)
	expect(not p.has("light_towards"), "the main light's direction is the engine's")
	expect(StageLighting.light_travel(_stage(4)).is_equal_approx(Vector3(0.5, -sqrt(0.5), -0.5)),
		"the light travels down, towards +x and −z")


func test_no_light_from_below_on_stage_17() -> void:
	expect_equal(StageLighting.fighter_parameters(_stage(StageLighting.NO_FILL_STAGE))["fill_colour"], Vector3.ZERO)


func test_each_camera_carries_its_stage_environment() -> void:
	var cameras: Array[Camera3D] = [Camera3D.new(), Camera3D.new()]
	var rigs: Array[StageLighting] = [StageLighting.new(), StageLighting.new()]
	var dark := _stage(4)
	var bright := _stage(5)
	bright.ambient = 175
	rigs[0].setup(dark, cameras[0])
	rigs[1].setup(bright, cameras[1])
	expect(cameras[0].environment == rigs[0].environment and cameras[1].environment == rigs[1].environment, "its own")
	expect(cameras[0].environment != cameras[1].environment, "not shared between views")
	expect_equal(cameras[0].environment.ambient_light_color.r8, 137, "stage 4's ambient")
	expect_equal(cameras[1].environment.ambient_light_color.r8, 175, "the other stage's ambient")
	for i in 2:
		cameras[i].free()
		rigs[i].free()


## The fighter view lights with the back colour it is given (the stage's until then) and takes
## new ones, on every material.
func test_view_takes_the_frames_back_colour() -> void:
	var dir := AssetCatalog.ROOT.path_join("characters/costume_00")
	if not require(dir.path_join("model.json")):
		return
	var view := FighterView.new()
	view.setup(CharacterModel.load_from(dir))
	view.set_lighting(StageLighting.fighter_parameters(_stage(4)))
	var stage_back: Vector3 = view.materials[0].get_shader_parameter("back_colour")
	var red := StageLighting.fighter_back_colour(2200, 0, Color8(250, 0, 0, 1))
	view.set_back_colour(red)
	for material in view.materials:
		expect_equal(material.get_shader_parameter("back_colour"), red, "red while the FREEZE SIGNAL's flag is set")
	view.set_back_colour(StageLighting.fighter_back_colour(2200, 0, StageLighting.NO_SIGNAL))
	expect_equal(view.materials[0].get_shader_parameter("back_colour"), stage_back, "the stage's again")
	view.free()


## The fighter shader takes every directional light that reaches the fighters' render layer for the
## stage's main light and adds the fill light itself, so exactly one of the stage's two directional
## lights (the sun) may reach that layer.
func test_only_the_sun_reaches_the_fighters() -> void:
	var camera := Camera3D.new()
	var lighting := StageLighting.new()
	lighting.setup(_stage(4), camera)
	expect(lighting.sun.light_cull_mask & StageLighting.FIGHTER_LAYER != 0, "the sun lights the fighters")
	expect(lighting.fill.light_cull_mask & StageLighting.FIGHTER_LAYER == 0, "the fill light does not")
	expect(lighting.fill.light_cull_mask & 1 != 0, "but it lights the floor")
	var reaching := 0
	for child in lighting.get_children():
		var light := child as DirectionalLight3D
		if light != null and light.light_cull_mask & StageLighting.FIGHTER_LAYER != 0:
			reaching += 1
	expect_equal(reaching, 1, "directional lights on the fighters' layer")
	camera.free()
	lighting.free()


## Every mesh of a fighter is on the fighters' layer (hands included), or it would be lit twice
## (with the fill light) or not by the sun.
func test_fighter_meshes_are_on_the_fighters_layer() -> void:
	var dir := AssetCatalog.ROOT.path_join("characters/costume_00")
	if not require(dir.path_join("model.json")):
		return
	var view := FighterView.new()
	view.setup(CharacterModel.load_from(dir))
	expect_equal(view.mesh_instance.layers, StageLighting.FIGHTER_LAYER, "the body")
	expect(not view.hand_instances.is_empty(), "the model has hands to check")
	for hand in view.hand_instances:
		expect_equal(hand.layers, StageLighting.FIGHTER_LAYER, "a hand")
	view.free()


const BACK_COLOUR_FILE := "back_colour.bin"
const BACK_COLOUR_CASE := 14


## The back colour of a fighter against the game's FUN_8003A3B8 run in the CPU harness
## (`work/traces/back_colour.bin`, tools/research/back_colour_cases.py): every stage's light record with
## each flash count, and random records, counts and practice signals. SetBackColor's red, green and
## blue are the bytes the remake's colour is made of.
func test_back_colour_matches_the_original() -> void:
	if not require(TraceFiles.path(BACK_COLOUR_FILE), "run tools/research/export_traces.py first"):
		return
	var data := FileAccess.get_file_as_bytes(TraceFiles.path(BACK_COLOUR_FILE))
	var count := data.decode_u32(8)
	var failed := 0
	var flashes := 0
	for n in count:
		var pos := 12 + BACK_COLOUR_CASE * n
		var word := data.decode_u16(pos)
		var flash := data.decode_u8(pos + 2)
		var practice := data.decode_u8(pos + 3) != 0
		var freeze := Color8(data.decode_u8(pos + 5), data.decode_u8(pos + 6), data.decode_u8(pos + 7), data.decode_u8(pos + 4))
		var want := StageLighting.back_colour(data.decode_u16(pos + 8), data.decode_u16(pos + 10), data.decode_u16(pos + 12))
		var got := StageLighting.fighter_back_colour(word, flash, freeze if practice else StageLighting.NO_SIGNAL)
		if flash != 0 and flash <= FighterAnimation.FLASH_FRAMES:
			flashes += 1
		if got != want:
			failed += 1
			if failed <= 5:
				Log.info("case %d: light word %d, flash %d, practice %s: %s, the game %s" % [n, word, flash, practice, got, want])
	expect_equal(failed, 0, "cases that differ of %d" % count)
	expect(flashes > 100, "the cases reach many flash counts (%d)" % flashes)


## The flash's precedence and its end: a burning body is black, the FREEZE SIGNAL beats a flash.
func test_back_colour_precedence() -> void:
	var red := Color8(250, 0, 0, 1)
	expect_equal(StageLighting.fighter_back_colour(2200, FighterAnimation.LIT_BLACK, red), Vector3.ZERO, "burning")
	expect_equal(StageLighting.fighter_back_colour(2200, 5, red), StageLighting.back_colour(250, 0, 0), "signal over flash")
	expect_equal(StageLighting.fighter_back_colour(2200, 0, StageLighting.NO_SIGNAL), StageLighting.back_colour(137, 137, 137),
		"the stage's level: the record's word >> 4")


## The core's counter: a pick-up (count 1) lights 32 frames with counts 1 to 32 and then ends; the
## frame's count is the one before the step. A burning fighter shows black and holds the flash.
func test_flash_counter_lights_32_frames() -> void:
	var fight := FightState.new(null, RuleSet.original())
	var f := fight.fighters[0]
	fight.health_flash[0] = 1
	var seen: Array[int] = []
	for frame in FighterAnimation.FLASH_FRAMES + 3:
		FighterAnimation.flash_step(fight, f)
		seen.append(fight.flash_level[0])
	var expected: Array[int] = []
	for count in range(1, FighterAnimation.FLASH_FRAMES + 1):
		expected.append(count)
	expected.append_array([0, 0, 0])
	expect_equal(seen, expected, "the counts the fighter is lit with")
	expect_equal(fight.health_flash[0], 0, "ended")
	expect_equal(fight.flash_level[1], 0, "the other fighter is not lit")
