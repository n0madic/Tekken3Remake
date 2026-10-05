extends TestSuite
## The converted asset folder: manifest, character model and stage are consistent.

const MODEL := AssetCatalog.ROOT + "characters/costume_00"
const STAGE := AssetCatalog.ROOT + "stages/e"


func test_manifest_reports_groups() -> void:
	if not require(AssetCatalog.MANIFEST):
		return
	var catalog := AssetCatalog.new()
	catalog.reload()
	expect(catalog.is_available(), "manifest not loaded")
	expect(catalog.has_group("core"), "core group missing")
	# Optional groups count only when converted and present in the build.
	var groups: Dictionary = catalog.manifest["groups"]
	var movies: bool = groups["movies"]
	expect_equal(catalog.has_group("movies"), movies and DirAccess.dir_exists_absolute(AssetCatalog.ROOT + "movies"))
	catalog.free()


func test_character_joints_are_ordered_parent_first() -> void:
	if not require(MODEL + "/model.json"):
		return
	var model := CharacterModel.load_from(MODEL)
	expect_equal(model.parts.size(), CharacterModel.PART_COUNT)
	var parents := model.joint_parents()
	expect_equal(parents[0], -1, "root joint parent")
	for m in FighterSkeleton.JOINTS:
		expect(parents[m] < m, "joint %d has parent %d" % [m, parents[m]])


func test_character_mesh_is_whole() -> void:
	if not require(MODEL + "/model.json"):
		return
	var model := CharacterModel.load_from(MODEL)
	expect(model.surfaces.size() > 0, "no surfaces")
	for surface in model.surfaces:
		var floats := surface.vertices.size()
		expect_equal(floats % (3 * model.vertex_floats), 0, "whole triangles")
		# The seam weights wb and wc leave the first joint a share (0.5 / 0.5 on the PlayStation's
		# models, any split of up to three joints on the arcade's); bone indices are joints.
		var bad := 0
		for i in range(0, floats, model.vertex_floats):
			var wb := surface.vertices[i + 6]
			var wc := surface.vertices[i + 26]
			var bones := [surface.vertices[i + 12], surface.vertices[i + 13], surface.vertices[i + 14],
				surface.vertices[i + 21], surface.vertices[i + 27]]
			if wb < 0.0 or wc < 0.0 or wb + wc >= 1.0 or bones.any(func(b: float) -> bool: return b >= CharacterModel.JOINT_COUNT):
				bad += 1
		expect_equal(bad, 0, "corners with bad weights or bones")


func test_stage_loads() -> void:
	if not require(STAGE + "/stage.json"):
		return
	var stage := StageData.load_from(STAGE)
	expect_equal(stage.number, 4)
	expect_equal(stage.floor_tiles.size(), 100)
	expect_equal(stage.panorama.size() % (3 * stage.vertex_floats), 0, "whole triangles")
	expect_equal(stage.base_colour, Vector3(126, 126, 128) / StageData.BASE_NEUTRAL, "the fighters' base colour (stages.md#lighting)")


func test_floor_pattern_is_composed_and_smoothed() -> void:
	if not require(STAGE + "/stage.json"):
		return
	var stage := StageData.load_from(STAGE)
	var exact := (load(StageView.floor_texture_path(stage, false)) as Texture2D).get_image()
	var smooth := (load(StageView.floor_texture_path(stage, true)) as Texture2D).get_image()
	var size := StageView.FLOOR_PATTERN * 64
	expect_equal(exact.get_size(), Vector2i(size, size), "exact pattern size")
	expect_equal(smooth.get_size(), Vector2i(size, size), "smoothed pattern size")
	# Smoothing must lower the colour step across tile seams below the step inside tiles.
	var seam := 0.0
	var inside := 0.0
	for y in range(0, size, 7):
		for x in range(0, size):
			var step := _luma(smooth.get_pixel((x + 1) % size, y)) - _luma(smooth.get_pixel(x, y))
			if x % 64 == 63:
				seam += absf(step)
			else:
				inside += absf(step) / 63.0
	expect(seam < inside, "seam step %.2f is not below the step inside tiles %.2f" % [seam, inside])


static func _luma(c: Color) -> float:
	return c.r * 0.299 + c.g * 0.587 + c.b * 0.114


func test_floor_reaches_under_the_panorama_walls() -> void:
	if not require(STAGE + "/stage.json"):
		return
	var stage := StageData.load_from(STAGE)
	var walls := 0
	for v in stage.panorama_extent:
		walls = maxi(walls, absi(v))
	walls = int(walls * StageView.PANORAMA_PARALLAX)
	expect(walls > 0, "panorama extent missing")
	# The floor is a square, so its corners reach the wall corners too.
	expect(StageView.floor_half_extent(stage) > walls, "floor %d does not reach the walls at %d" % [StageView.floor_half_extent(stage), walls])


func test_json_ints_keep_unsigned_words() -> void:
	# JSON numbers of 32-bit unsigned words (sound script entries, attribute words) keep their bits.
	var words := JsonFile.ints([0x90011078, 5.0, 0x7FFFFFFF, -3])
	expect_equal(words[0], 0x90011078 - 0x100000000)
	expect_equal((words[0] >> 16) & 0xFFFF, 0x9001, "code")
	expect_equal(words[0] & 0xFFF, 0x78, "frame")
	expect_equal(words[1], 5)
	expect_equal(words[2], 0x7FFFFFFF)
	expect_equal(words[3], -3)
