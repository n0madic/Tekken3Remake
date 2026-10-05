extends TestSuite
## The drawing rules the Tekken Force and Tekken Ball views take from the game: the items' boxes,
## the GPU's coordinate limits (the ball's streaks), and the one-sided panorama seen from the
## cameras that orbit inside it.

const FIGHT_STAGES := 15               ## FightContent.STAGE_LETTERS: stages 0–14


## FUN_800B4374's box: 0x15E00 / (SZ >> 2) wide, 0x2BC00 / (SZ >> 2) high, centred on the point's x,
## its bottom a height above the point (SZ 7964: 45 × 90, the size of the items in the Force
## traces' packets).
func test_item_box_follows_the_game_formula() -> void:
	var box := ForceItemsView.picture_box(PackedInt32Array([473, 524, 7964]))
	expect_equal(box, PackedFloat32Array([451, 344, 45, 90, 7964]), "picture box")


func test_item_box_survives_a_point_at_the_eye() -> void:
	var box := ForceItemsView.picture_box(PackedInt32Array([100, 100, 0]))
	expect_equal(box[2], float(ForceItemsView.WIDTH), "a depth of 0 counts as 1")


func test_gpu_coordinates_wrap_at_11_bits() -> void:
	expect_equal(ScreenCanvas.gpu_coordinate(1023), 1023, "the largest")
	expect_equal(ScreenCanvas.gpu_coordinate(1024), -1024, "past it wraps")
	expect_equal(ScreenCanvas.gpu_coordinate(-1), -1, "negative")
	expect_equal(ScreenCanvas.gpu_coordinate(0x10005), 5, "upper bits dropped")


func test_gpu_skips_oversized_polygons() -> void:
	var fits: Array[Vector2i] = [Vector2i(0, 0), Vector2i(1023, 480), Vector2i(-0, 511)]
	expect(ScreenCanvas.gpu_draws(fits), "1023 × 511 is drawn")
	var wide: Array[Vector2i] = [Vector2i(-1, 0), Vector2i(1023, 0), Vector2i(0, 10)]
	expect(not ScreenCanvas.gpu_draws(wide), "1024 wide is skipped")
	var tall: Array[Vector2i] = [Vector2i(0, -40), Vector2i(8, 480), Vector2i(0, 480)]
	expect(not ScreenCanvas.gpu_draws(tall), "520 tall is skipped")


## The panorama is culled from outside (panorama.gdshader): the ranking's orbiting camera and
## the rig's coverage eye stay inside every fight stage's panorama.
func test_backdrop_cameras_stay_inside_the_panorama() -> void:
	if not require(AssetCatalog.ROOT.path_join("stages/a/stage.json")):
		return
	for letter in FightContent.STAGE_LETTERS.substr(0, FIGHT_STAGES):
		var stage := StageData.load_from(AssetCatalog.ROOT.path_join("stages/" + letter))
		var e := stage.panorama_extent
		var k := StageView.PANORAMA_PARALLAX
		var box := Rect2(e[0] * k, e[2] * k, (e[1] - e[0]) * k, (e[3] - e[2]) * k)
		var orbit := RankingScreen.ORBIT_RADIUS
		expect(box.has_point(Vector2(-orbit, -orbit)) and box.has_point(Vector2(orbit, orbit)),
			"stage %s: the ranking orbit inside %s" % [letter, box])
		expect(box.has_point(Vector2(stage.coverage_eye[0], stage.coverage_eye[2])),
			"stage %s: the coverage eye inside %s" % [letter, box])
