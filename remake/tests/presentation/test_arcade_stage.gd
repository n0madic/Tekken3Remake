extends TestSuite
## The arcade stages (StageView with ArcadeStageData, docs/research/arcade/stages.md):
## the sky's cylinder mapping agrees with FUN_801A7688's scrolling, the pitch clamps move its
## top edge, and a converted arcade stage is placed as the arcade places it.


## The sky shader takes a direction's yaw as atan2(−x, −z): the camera's forward at yaw Y must
## give Y back, so the screen centre shows the strip column the game shows there.
func test_sky_yaw_from_the_view_direction() -> void:
	var worst := 0.0
	for y in range(0, 4096, 97):
		var forward := -CameraRig.view_basis(0.0, WorldSpace.radians(y)).z
		var back := atan2(-forward.x, -forward.z) * 4096.0 / TAU
		worst = maxf(worst, absf(wrapf(back - y, -2048.0, 2048.0)))
	expect(worst < 1e-3, "yaw recovered within %.5f units" % worst)


## Without a clamp the sky's top edge stays at one elevation whatever the pitch (a cylinder);
## stage 0 keeps it at the screen's top when the camera looks up past it.
func test_view_pitch_moves_only_clamped_skies() -> void:
	var view := _sky_view({"pitch_scale": 256, "offset": -32, "rows": 4, "kind": "tiles", "step": 546})
	view.set_view_pitch(0)
	var level := (view.sky_material.get_shader_parameter("top") as float)
	expect(is_equal_approx(level, 240.0 + 32.0), "top at pitch 0: %f" % level)
	view.set_view_pitch(-400)
	expect(is_equal_approx((view.sky_material.get_shader_parameter("top") as float), level), "unclamped: unchanged")
	view.arcade.sky["clamp_top"] = true
	view.set_view_pitch(-400)
	var clamped := (view.sky_material.get_shader_parameter("top") as float)
	# The top row would be 400 − 32 lines down; clamped to 0, the screen's top (240 lines above
	# the view axis, which points 400 units up).
	expect(is_equal_approx(clamped, 400.0 + 240.0), "clamped to the screen's top: %f" % clamped)
	# A texture setting change sets the sky up again at the same pitch.
	view._sky_parameters()
	expect(is_equal_approx((view.sky_material.get_shader_parameter("top") as float), clamped), "the pitch is kept")
	_free(view)


## FUN_801D8FD0 draws the sky with the camera's yaw minus the backdrop's turn: the sky turns with
## the scene. A direction the turned scene shows a feature at must look up the sky at its own
## unturned yaw, which is the direction's yaw minus the turn (the shader's `- turn`).
func test_sky_turns_with_the_backdrop() -> void:
	var view := _sky_view({"pitch_scale": 256, "offset": 0, "rows": 4, "kind": "tiles", "step": 546})
	var worst := 0.0
	for turn: int in [-477, 77, 300, 1000, 4000]:
		view.set_backdrop_turn(turn)
		expect(is_equal_approx((view.sky_material.get_shader_parameter("turn") as float), float(turn)), "the turn reaches the sky")
		for yaw in range(0, 4096, 311):
			var forward := -CameraRig.view_basis(0.0, WorldSpace.radians(yaw)).z
			var turned := view.panorama.basis * forward
			var seen := atan2(-turned.x, -turned.z) * 4096.0 / TAU
			worst = maxf(worst, absf(wrapf(seen - turn - yaw, -2048.0, 2048.0)))
	expect(worst < 1e-2, "scene feature and sky lookup agree within %.5f units" % worst)
	_free(view)


## The shader subtracts the turn from the yaw (the test above holds its sign against the scene).
func test_sky_shader_subtracts_the_turn() -> void:
	var source := FileAccess.get_file_as_string("res://presentation/stage/arcade_sky.gdshader")
	expect(source.contains("* UNITS / TAU - turn;"), "the sky's yaw is the direction's yaw minus the turn")


## A rebuilt sky material (a texture setting changed) keeps the turn of the last step.
func test_sky_parameters_keep_the_turn() -> void:
	var view := _sky_view({"pitch_scale": 256, "offset": 0, "rows": 4, "kind": "tiles", "step": 546})
	view.set_backdrop_turn(0x80)
	view._sky_parameters()
	expect(is_equal_approx((view.sky_material.get_shader_parameter("turn") as float), 128.0), "the turn survives")
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


## The arcade floor is the 10 × 10 tiles around the tile under the midpoint (FUN_801A941C): it
## moves by whole tiles, and every tile shows the quarter-tile pattern.
func test_floor_follows_by_whole_tiles() -> void:
	var dir := AssetCatalog.ROOT.path_join("stages/a")
	if not require(dir.path_join("arcade/arcade.json")):
		return
	var saved: Variant = Settings.value("stage_backdrops")
	Settings.values["stage_backdrops"] = "arcade"
	var view := StageView.new()
	view.setup(StageData.load_from(dir))
	Settings.values["stage_backdrops"] = saved
	view.follow(WorldSpace.point(1200, 0, -1200))
	expect(view.floor_mesh.position.is_equal_approx(Vector3.ZERO), "under tile (0, 0): %s" % view.floor_mesh.position)
	view.follow(WorldSpace.point(1300, 0, 0))
	expect(view.floor_mesh.position.is_equal_approx(WorldSpace.point(2500, 0, 0)), "under tile (1, 0): %s" % view.floor_mesh.position)
	expect_equal(view.floor_grid_origin(), Vector2i(-4, -5), "the grid from tile (−4, −5)")
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


## Frees a view whose meshes setup never parented.
static func _free(view: StageView) -> void:
	for node: Node in [view.panorama, view.floor_mesh]:
		if node.get_parent() == null:
			node.free()
	view.free()
