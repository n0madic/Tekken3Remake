extends TestSuite
## The arcade stages (StageView with ArcadeStageData, docs/research/arcade/stages.md):
## the sky is laid out on the 4:3 frame and scrolled as FUN_801A7688 does, the pitch clamps move
## its top edge, and a converted arcade stage is placed as the arcade places it.


## FUN_801A7688 lays the sky out on the screen: the frame's left edge shows strip pixel
## ((turn − yaw) & 0xFFF)·512 / step, whatever the zoom, for the camera of this frame.
func test_sky_scrolls_with_the_yaw_minus_the_turn() -> void:
	var view := _sky_view({"pitch_scale": 256, "offset": 0, "rows": 4, "kind": "tiles", "step": 546})
	var camera := _camera()
	for case: Array in [[0, 0], [1000, 0], [1000, 300], [4000, -477]]:
		var yaw: int = case[0]
		var turn: int = case[1]
		camera.transform = Transform3D(CameraRig.view_basis(0.0, WorldSpace.radians(yaw)), Vector3.ZERO)
		view.set_backdrop_turn(turn)
		view.place_sky(camera, Vector2(0.368, 0.276))
		var expected := float(posmod(turn - yaw, 4096)) * 512.0 / 546.0
		var scroll := view.sky_material.get_shader_parameter("scroll") as float
		expect(absf(wrapf(scroll - expected, -2048.0, 2048.0)) < 1e-2, "yaw %d turn %d: %f against %f" % [yaw, turn, scroll, expected])
	camera.free()
	_free(view)


## The top row lies −pitch · k / 256 + offset lines down the frame; stage 0's kind keeps it at or
## above the frame's top, stage 11's also not more than 192 lines above.
func test_sky_top_follows_the_pitch_with_the_clamps() -> void:
	var view := _sky_view({"pitch_scale": 128, "offset": -32, "rows": 4, "kind": "tiles", "step": 546})
	var camera := _camera()
	var tops: Dictionary[int, float] = {}
	for pitch: int in [-400, 0, 200, 600]:
		camera.transform = Transform3D(CameraRig.view_basis(WorldSpace.radians(pitch), 0.0), Vector3.ZERO)
		view.place_sky(camera, Vector2(0.368, 0.276))
		tops[pitch] = view.sky_material.get_shader_parameter("sky_top") as float
	expect(is_equal_approx(tops[0], -32.0), "pitch 0: %f" % tops[0])
	expect(absf(tops[-400] - (200.0 - 32.0)) < 1e-2, "looking up: %f" % tops[-400])
	view.arcade.sky["clamp_top"] = true
	view.arcade.sky["clamp_bottom"] = -192
	for pitch: int in [-400, 600]:
		camera.transform = Transform3D(CameraRig.view_basis(WorldSpace.radians(pitch), 0.0), Vector3.ZERO)
		view.place_sky(camera, Vector2(0.368, 0.276))
		tops[pitch] = view.sky_material.get_shader_parameter("sky_top") as float
	expect(is_equal_approx(tops[-400], 0.0), "clamped to the frame's top: %f" % tops[-400])
	expect(is_equal_approx(tops[600], -192.0), "at most 192 lines above: %f" % tops[600])
	camera.free()
	_free(view)


## The shader takes a direction's place in the 4:3 frame from the camera's view: the frame's
## corners are the strip's 512 × 480 screen (the arcade's), not angles at the scroll rates.
func test_sky_shader_lays_the_strip_on_the_frame() -> void:
	var source := FileAccess.get_file_as_string("res://presentation/stage/arcade_sky.gdshader")
	expect(source.contains("HALF_HEIGHT - HALF_HEIGHT * d.y / depth / frame_tan.y - sky_top"), "rows are frame lines below the top row")
	expect(source.contains("scroll + HALF_WIDTH + HALF_WIDTH * d.x / depth / frame_tan.x"), "columns are frame pixels from the scroll")


## The rig's 4:3 frame (±184/H, ±138/H) is the sky's screen.
func test_rig_frame_tan_from_the_projection() -> void:
	var rig := CameraRig.new()
	rig.set_view(CameraView.new(0, 0, 0, 0, 0, 400), true)
	rig.place(1.0, Vector2(1920, 1080))
	expect(rig.frame_tan.is_equal_approx(Vector2(184.0, 138.0) / 400.0), "frame_tan %s" % rig.frame_tan)
	rig.camera.free()
	rig.free()


## A rebuilt sky material (a texture setting changed) keeps the strip's turn length.
func test_sky_parameters_set_the_turn_length() -> void:
	var view := _sky_view({"pitch_scale": 256, "offset": 0, "rows": 4, "kind": "tiles", "step": 546, "turn_pixels": 3840.0})
	view._sky_parameters()
	expect(is_equal_approx((view.sky_material.get_shader_parameter("turn_pixels") as float), 3840.0), "turn_pixels")
	_free(view)


func test_converted_stage_is_placed_as_the_arcade_places_it() -> void:
	var dir := AssetCatalog.ROOT.path_join("stages/a")
	if not require(dir.path_join("arcade/arcade.json")):
		return
	var stage := StageData.load_from(dir)
	expect(stage.arcade != null, "the arcade version loads")
	expect_equal(stage.arcade.scene.size() % stage.arcade.vertex_floats, 0, "whole corners")
	expect_equal(stage.arcade.scene.size() / stage.arcade.vertex_floats % 3, 0, "whole triangles")
	var saved: Variant = Settings.value("stage_backdrops")
	Settings.values["stage_backdrops"] = "arcade"
	var view := StageView.new()
	view.setup(stage)
	expect(view.arcade != null and view.sky_material != null, "the arcade scene and sky are drawn")
	expect(is_equal_approx(view.panorama.scale.x, 10.0), "scaled by 10: %s" % view.panorama.scale)
	expect_equal(StageView.floor_half_extent(stage, view.arcade), 12500, "10 × 10 tiles of 2,500 units")
	expect_equal(view.coverage().size(), 0, "the sky covers every view")
	var environment := Environment.new()
	var root := (Engine.get_main_loop() as SceneTree).root
	root.add_child(view)
	view.apply_environment(environment)
	expect_equal(environment.background_mode, Environment.BG_SKY, "the sky is the background")
	# A hidden view (the attract demonstration's between performances) leaves the clear colour.
	view.visible = false
	expect_equal(environment.background_mode, Environment.BG_COLOR, "hidden: no sky")
	view.visible = true
	expect_equal(environment.background_mode, Environment.BG_SKY, "shown again: the sky")
	root.remove_child(view)
	# Hidden through its parent, as in EnbuView between performances.
	var parent := Node3D.new()
	root.add_child(parent)
	parent.add_child(view)
	parent.visible = false
	expect_equal(environment.background_mode, Environment.BG_COLOR, "parent hidden: no sky")
	parent.visible = true
	expect_equal(environment.background_mode, Environment.BG_SKY, "parent shown: the sky")
	parent.remove_child(view)
	parent.free()
	var ogre := Environment.new()
	view.apply_environment(ogre, true)
	expect_equal(ogre.background_mode, Environment.BG_CLEAR_COLOR, "no sky in True Ogre fights")
	view.free()
	Settings.values["stage_backdrops"] = "playstation"
	var ps := StageView.new()
	ps.setup(stage)
	expect(ps.arcade == null and is_equal_approx(ps.panorama.scale.x, 8.0), "PlayStation: the panorama")
	ps.free()
	Settings.values["stage_backdrops"] = saved


## FUN_801E2114 copies the next of 16 frames every fourth step; the loaded picture shows until
## the first copy.
func test_texture_animation_cycles_every_period() -> void:
	var view := StageView.new()
	view.arcade = ArcadeStageData.new()
	view.arcade.scene_animation_rect = PackedInt32Array([0, 0, 64, 64])
	view.arcade.scene_animation_frames = 16
	view.arcade.scene_animation_period = 4
	view.panorama.material_override = ShaderMaterial.new()
	var shown := PackedInt32Array()
	for i in 4 * 17:
		view.step()
		shown.append((view.panorama.material_override as ShaderMaterial).get_shader_parameter("frame") as int)
	expect_equal(shown.slice(0, 5), PackedInt32Array([-1, -1, -1, 0, 0]), "the first copy on step 4")
	expect_equal(shown[4 * 2 - 1], 1, "the next every 4 steps")
	expect_equal(shown[4 * 16 - 1], 15, "the 16th frame")
	expect_equal(shown[4 * 17 - 1], 0, "then from the first again")
	_free(view)


## The arcade floor's square (10 × 10 tiles) is centred on the midpoint and turns with the scene,
## so its edge stays under the scene's walls (game-bugs.md #67); its pattern stays in world axes
## (the shader reads the world position), and every tile shows the quarter-tile pattern.
func test_floor_square_follows_the_scene() -> void:
	var dir := AssetCatalog.ROOT.path_join("stages/a")
	if not require(dir.path_join("arcade/arcade.json")):
		return
	var saved: Variant = Settings.value("stage_backdrops")
	Settings.values["stage_backdrops"] = "arcade"
	var view := StageView.new()
	view.setup(StageData.load_from(dir))
	Settings.values["stage_backdrops"] = saved
	var midpoint := WorldSpace.point(1300, 0, -1200)
	view.follow(midpoint)
	expect(view.floor_mesh.position.is_equal_approx(midpoint), "centred on the midpoint: %s" % view.floor_mesh.position)
	view.set_backdrop_turn(0x80)
	expect(is_equal_approx(view.floor_mesh.rotation.y, view.panorama.rotation.y), "turned with the scene")
	expect(view.floor_mesh.rotation.y != 0.0, "the turn applied")
	var material := (view.floor_mesh.mesh as ArrayMesh).surface_get_material(0) as ShaderMaterial
	var pattern := material.get_shader_parameter("pattern") as Texture2D
	expect(pattern != null and pattern.get_width() == StageView.FLOOR_PATTERN * 128, "the quarter-tile pattern on every tile")
	view.panorama.free()
	view.floor_mesh.free()
	view.free()


func test_the_setting_offers_arcade_only_when_converted() -> void:
	var choices := Settings.choices("stage_backdrops")
	expect("playstation" in choices, "PlayStation is always offered")
	expect_equal("arcade" in choices, Assets.has_group("arcade"), "Arcade only with the arcade group")


func _sky_view(sky: Dictionary) -> StageView:
	var view := StageView.new()
	view.arcade = ArcadeStageData.new()
	view.arcade.sky = sky
	view.sky_material = ShaderMaterial.new()
	return view


## A camera in the tree (place_sky reads its global basis).
static func _camera() -> Camera3D:
	var camera := Camera3D.new()
	(Engine.get_main_loop() as SceneTree).root.add_child(camera)
	return camera


## Frees a view whose meshes setup never parented.
static func _free(view: StageView) -> void:
	for node: Node in [view.panorama, view.floor_mesh]:
		if node.get_parent() == null:
			node.free()
	view.free()
